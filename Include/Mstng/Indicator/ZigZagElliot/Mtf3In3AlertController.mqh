//+------------------------------------------------------------------+
//|                                       Mtf3In3AlertController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\ZigZagElliotAlertDatabaseContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertCsvWriter.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertSnapshot.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertSnapshotBuilder.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * MTF_3in3アラート判定、シグナル回数および検証CSVを管理するクラス。
 */
class Mtf3In3AlertController {
public:
    /**
     * 保持リソースを初期化する。
     */
    Mtf3In3AlertController() {
        this.expertAdvisorMtf3In3 = NULL;
        this.signalCount = NULL;
        this.alertCsvEnabled = true;
        this.databaseContext = NULL;
        this.databaseReady = false;
        ZeroMemory(this.databaseRun);
    }

    /**
     * 保持リソースを解放する。
     */
    ~Mtf3In3AlertController() {
        this.destroy();
    }

    /**
     * 市場コンテキストとアラート出力設定を使用して初期化する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromConfig ZigZagElliot設定
     * @return 初期化に成功した場合true
     */
    bool initialize(
        MarketContext &fromMarketContext,
        ZigZagElliotConfig &fromConfig
    ) {
        this.destroy();

        this.marketContext = fromMarketContext;
        this.config = fromConfig;
        this.alertCsvEnabled = fromConfig.mtf3In3AlertCsvEnabled;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.signalCount = new SignalCount(this.marketContext);

        if (this.signalCount == NULL) {
            this.logger.error(
                __FUNCTION__,
                "signal count allocation failed"
            );

            return false;
        }

        this.expertAdvisorMtf3In3 = ExpertAdvisorMtf3In3Factory::create(
            this.marketContext
        );

        if (this.expertAdvisorMtf3In3 == NULL) {
            this.logger.error(
                __FUNCTION__,
                "MTF_3in3 expert advisor allocation failed"
            );
            delete this.signalCount;
            this.signalCount = NULL;

            return false;
        }

        this.initializeDatabase();

        return true;
    }

    /**
     * MTF_3in3アラートを分析し、必要に応じて検証CSVを出力する。
     *
     * @param fromElliotAll Elliott分析結果
     */
    void execute(ElliotAll *fromElliotAll) {
        if (
            fromElliotAll == NULL
            || this.expertAdvisorMtf3In3 == NULL
            || this.signalCount == NULL
        ) {
            return;
        }

        if (this.marketContext.timeFrame > PERIOD_H1) {
            return;
        }

        this.expertAdvisorMtf3In3.analyze(fromElliotAll, this.signalCount);

        if (!this.expertAdvisorMtf3In3.isAlert) {
            return;
        }

        Mtf3In3AlertResult alertResult =
            this.expertAdvisorMtf3In3.getAlertResult();

        if (this.config.mtf3In3AlertDatabaseEnabled
                && this.databaseReady) {
            Mtf3In3AlertSnapshot snapshot;
            bool isBuilt = Mtf3In3AlertSnapshotBuilder::build(
                fromElliotAll,
                alertResult,
                this.databaseRun.runUid,
                "ZIGZAG_ELLIOT",
                0,
                this.expertAdvisorMtf3In3.alertText,
                snapshot
            );

            if (!isBuilt) {
                this.logger.error(
                    __FUNCTION__,
                    "MTF_3in3 alert database snapshot build failed"
                );
            } else {
                snapshot.alert.runId = this.databaseRun.id;
                ZigZagElliotAlertPersistenceService *persistenceService =
                    this.databaseContext.getPersistenceService();
                bool isSaved = persistenceService != NULL
                    && persistenceService.saveSnapshot(
                        snapshot.alert,
                        snapshot.timeFrames,
                        snapshot.points
                    );

                if (!isSaved) {
                    this.logger.error(
                        __FUNCTION__,
                        "MTF_3in3 alert database save failed"
                    );
                }
            }
        }

        if (this.alertCsvEnabled) {
            bool isWritten = Mtf3In3AlertCsvWriter::write(
                fromElliotAll,
                alertResult,
                "ZIGZAG_ELLIOT"
            );

            if (!isWritten) {
                this.logger.error(
                    __FUNCTION__,
                    "MTF_3in3 alert validation CSV write failed"
                );
            }
        }
    }

    /**
     * Elliott観測永続化サービスを取得する。
     *
     * 返却ポインタは非所有参照であり、呼び出し側では解放しない。
     *
     * @return 永続化サービス。未準備の場合NULL
     */
    ZigZagElliotObservationPersistenceService *getObservationPersistenceService() {
        if (!this.databaseReady || this.databaseContext == NULL) {
            return NULL;
        }

        return this.databaseContext.getObservationPersistenceService();
    }

    /**
     * データベースへ保存済みの実行情報を取得する。
     *
     * @param fromRunEntity 実行情報の格納先
     * @return 保存済みの実行情報を取得できた場合true
     */
    bool getDatabaseRun(ZigZagElliotAlertRunEntity &fromRunEntity) {
        ZeroMemory(fromRunEntity);

        if (!this.databaseReady || this.databaseRun.id <= 0) {
            return false;
        }

        fromRunEntity = this.databaseRun;

        return true;
    }

    /**
     * シグナル回数とMTF_3in3固定描画オブジェクトを解放する。
     */
    void destroy() {
        this.releaseDatabase();

        if (this.expertAdvisorMtf3In3 != NULL) {
            delete this.expertAdvisorMtf3In3;
            this.expertAdvisorMtf3In3 = NULL;
        }

        if (this.signalCount != NULL) {
            delete this.signalCount;
            this.signalCount = NULL;
        }

        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "ArrowMTF_3in3",
            0,
            -1
        );
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "TextMTF_3in3",
            0,
            -1
        );
    }

private:
    /** 市場コンテキスト。 */
    MarketContext marketContext;
    /** MTF_3in3外部戦略。 */
    ExpertAdvisorMTF_3in3 *expertAdvisorMtf3In3;
    /** ロガー。 */
    Logger logger;
    /** シグナル回数。 */
    SignalCount *signalCount;
    /** 検証CSVを出力する場合true。 */
    bool alertCsvEnabled;
    /** ZigZagElliot設定。 */
    ZigZagElliotConfig config;
    /** ZigZagElliotデータベース接続。 */
    ZigZagElliotAlertDatabaseContext *databaseContext;
    /** データベースへ保存済みの実行情報。 */
    ZigZagElliotAlertRunEntity databaseRun;
    /** データベースへ保存可能な場合true。 */
    bool databaseReady;

    /**
     * ZigZagElliotデータベースを開き、実行情報を保存する。
     *
     * 初期化に失敗した場合も既存アラート処理を継続できるよう、
     * データベースだけを無効化する。
     *
     * @return 保存可能になった場合true
     */
    bool initializeDatabase() {
        bool observationEnabled =
            this.config.h1ElliotObservationDatabaseEnabled
            && this.marketContext.timeFrame
                == ZigZagElliotAnalysisProfile::getAnchorTimeFrame();

        if (!this.config.mtf3In3AlertDatabaseEnabled
                && !observationEnabled) {
            return false;
        }

        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            this.logger.info(
                __FUNCTION__,
                "ZigZagElliot database is disabled during optimization."
            );

            return false;
        }

        this.databaseContext = new ZigZagElliotAlertDatabaseContext(
            this.config.mtf3In3AlertDatabaseFileName,
            this.config.mtf3In3AlertDatabaseUseCommonFolder,
            observationEnabled
        );

        if (this.databaseContext == NULL || !this.databaseContext.open()) {
            this.logger.error(
                __FUNCTION__,
                "ZigZagElliot database initialization failed"
            );
            this.releaseDatabase();

            return false;
        }

        this.setDatabaseRun();
        ZigZagElliotAlertPersistenceService *persistenceService =
            this.databaseContext.getPersistenceService();

        if (persistenceService == NULL
                || !persistenceService.saveRun(this.databaseRun)) {
            this.logger.error(
                __FUNCTION__,
                "ZigZagElliot database run save failed"
            );
            this.releaseDatabase();

            return false;
        }

        this.databaseReady = true;
        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "ZigZagElliot database is ready. runId=%I64d runUid=%s",
                this.databaseRun.id,
                this.databaseRun.runUid
            )
        );

        return true;
    }

    /**
     * 現在の実行情報をデータベースEntityへ設定する。
     */
    void setDatabaseRun() {
        ZeroMemory(this.databaseRun);
        datetime localTime = TimeLocal();
        datetime marketTime = TimeCurrent();
        string inputText = this.createInputText();

        this.databaseRun.runUid = StringFormat(
            "%s_%I64u_%I64d",
            TimeUtil::formatYyyymmddhhmiss(localTime),
            GetTickCount64(),
            ChartID()
        );
        this.databaseRun.schemaVersion = 2;
        this.databaseRun.sourceMode = "LIVE";

        if (Util::isStrategyTester()) {
            this.databaseRun.sourceMode = "TESTER";
        }

        this.databaseRun.source = "ZIGZAG_ELLIOT";
        this.databaseRun.programName = MQLInfoString(MQL_PROGRAM_NAME);
        this.databaseRun.programVersion = "1.23";
        this.databaseRun.strategy = "MTF_3in3";
        this.databaseRun.strategyVersion = "MTF3IN3_V1";
        this.databaseRun.analysisVersion =
            ZigZagElliotAnalysisProfile::getAnalysisVersion();
        this.databaseRun.analysisInputText =
            ZigZagElliotAnalysisProfile::createCanonicalText();
        this.databaseRun.analysisInputHash =
            ZigZagElliotAnalysisProfile::createHash();
        this.databaseRun.sourceServer = AccountInfoString(ACCOUNT_SERVER);
        this.databaseRun.sourceLogin = (long)AccountInfoInteger(ACCOUNT_LOGIN);
        this.databaseRun.sourceChartId = ChartID();
        this.databaseRun.terminalBuild =
            (int)TerminalInfoInteger(TERMINAL_BUILD);
        this.databaseRun.testerFrom = 0;
        this.databaseRun.testerTo = 0;
        this.databaseRun.testerModel = "";
        this.databaseRun.inputText = inputText;
        this.databaseRun.inputHash = this.createTextHash(inputText);
        this.databaseRun.startedAt = localTime;
        this.databaseRun.startedAtText =
            TimeUtil::formatYyyymmddhhmiss(localTime);
        this.databaseRun.marketStartedAt = marketTime;
        this.databaseRun.marketStartedAtText =
            TimeUtil::formatYyyymmddhhmiss(marketTime);
        this.databaseRun.createdAt = localTime;
        this.databaseRun.createdAtText =
            TimeUtil::formatYyyymmddhhmiss(localTime);
    }

    /**
     * 判定結果へ影響する設定を比較用文字列として取得する。
     *
     * @return 設定文字列
     */
    string createInputText() {
        string inputText = "";
        inputText += "h1DisplayWaveEntryLimitEnabled="
            + (string)this.config.h1DisplayWaveEntryLimitEnabled;
        inputText += "|currencyStrengthEnabled="
            + (string)this.config.currencyStrengthEnabled;
        inputText += "|currencyStrengthEntryFilterEnabled="
            + (string)this.config.currencyStrengthEntryFilterEnabled;
        inputText += "|currencyStrengthDatabaseProfile="
            + IntegerToString(
                (int)this.config.currencyStrengthDatabaseProfile
            );
        inputText += "|currencyStrengthVoteWeightMode="
            + IntegerToString(
                (int)this.config.currencyStrengthVoteWeightMode
            );

        return inputText;
    }

    /**
     * 文字列から比較用のFNV-1aハッシュを作成する。
     *
     * @param fromText 対象文字列
     * @return 符号なし64bit整数の10進文字列
     */
    string createTextHash(const string fromText) {
        ulong hashValue = 14695981039346656037;

        for (int i = 0; i < StringLen(fromText); i++) {
            hashValue ^= (ulong)StringGetCharacter(fromText, i);
            hashValue *= 1099511628211;
        }

        return StringFormat("%I64u", hashValue);
    }

    /**
     * ZigZagElliotデータベース関連リソースを解放する。
     */
    void releaseDatabase() {
        this.databaseReady = false;
        ZeroMemory(this.databaseRun);

        if (this.databaseContext != NULL) {
            this.databaseContext.close();
            delete this.databaseContext;
            this.databaseContext = NULL;
        }
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH
