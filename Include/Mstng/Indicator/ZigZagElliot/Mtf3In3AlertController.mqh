//+------------------------------------------------------------------+
//|                                       Mtf3In3AlertController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH

#include <Arrays\ArrayString.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\ZigZagElliotAlertDatabaseContext.mqh>
#include <Mstng\Draw\DrawZigZagElliotLiveAlertTooltip.mqh>
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
        this.databaseSavePeriodReached = false;
        this.databaseFirstSnapshotSaved = false;
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
        if (this.marketContext.timeFrame == PERIOD_H1) {
            this.config.applyH1EntryPolicy();
        }
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
            this.marketContext,
            true,
            this.config.h1W1ConfirmationMode,
            this.config.h1DirectionAlignmentMode,
            this.config.h1Ema200ConfirmationMode
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

        if (!fromElliotAll.isAnalysisSucceeded || fromElliotAll.elliotCurrent == NULL) {
            return;
        }
        ZigZagPoint *sourceSignalPoint = fromElliotAll.elliotCurrent.getLatestPoint2();
        if (sourceSignalPoint == NULL || !this.restoreAlertSignalCount(
                sourceSignalPoint.barTime, fromElliotAll.elliotCurrent.isBuy)) {
            return;
        }

        this.expertAdvisorMtf3In3.analyze(fromElliotAll, this.signalCount);

        bool isDatabaseSaveAllowed = false;
        if (this.config.mtf3In3AlertDatabaseEnabled
                && this.databaseReady
                && fromElliotAll.isAnalysisSucceeded
                && fromElliotAll.elliotCurrent != NULL) {
            datetime currentBarTime =
                fromElliotAll.elliotCurrent.currentOhlcBarTime;
            isDatabaseSaveAllowed =
                this.isDatabaseSaveTimeReached(currentBarTime);

            if (isDatabaseSaveAllowed
                    && this.getEffectiveDatabaseSaveStartTime() > 0
                    && !this.databaseSavePeriodReached) {
                this.databaseSavePeriodReached = true;
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "ZigZagElliot database save period reached. start=%s currentBar=%s",
                        this.formatDatabaseSaveStartTime(
                            this.getEffectiveDatabaseSaveStartTime()
                        ),
                        TimeToString(currentBarTime, TIME_DATE | TIME_SECONDS)
                    )
                );
            }
        }

        if (!this.expertAdvisorMtf3In3.isAlert) {
            return;
        }

        Mtf3In3AlertResult alertResult =
            this.expertAdvisorMtf3In3.getAlertResult();

        if (this.marketContext.timeFrame == PERIOD_M5 || this.marketContext.timeFrame == PERIOD_H1) {
            string objectName = Constant::PREFIX_FIXED + "TextMTF_3in3"
                + IntegerToString((int)fromElliotAll.elliotCurrent.currentOhlcBarTime);
            if (!DrawZigZagElliotLiveAlertTooltip::apply(
                    objectName, fromElliotAll, this.expertAdvisorMtf3In3.getJudgmentElliotAll(),
                    alertResult, this.expertAdvisorMtf3In3.getCorrectionTimeFrame())) {
                this.logger.error(__FUNCTION__, "normal alert tooltip update failed");
            }
        }

        if (isDatabaseSaveAllowed) {
            Mtf3In3AlertSnapshot snapshot;
            bool isBuilt = Mtf3In3AlertSnapshotBuilder::build(
                fromElliotAll,
                alertResult,
                this.databaseRun.runUid,
                "ZIGZAG_ELLIOT",
                0,
                this.expertAdvisorMtf3In3.alertText,
                snapshot,
                this.expertAdvisorMtf3In3.getJudgmentElliotAll(),
                this.expertAdvisorMtf3In3.getCorrectionTimeFrame(),
                this.expertAdvisorMtf3In3.getJudgmentAlertText()
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
                        snapshot.points,
                        snapshot.correction,
                        snapshot.correctedTimeFrames,
                        snapshot.correctedPoints
                    );

                if (!isSaved) {
                    this.logger.error(
                        __FUNCTION__,
                        "MTF_3in3 alert database save failed"
                    );
                } else if (this.getEffectiveDatabaseSaveStartTime() > 0
                        && !this.databaseFirstSnapshotSaved) {
                    this.databaseFirstSnapshotSaved = true;
                    this.logger.info(
                        __FUNCTION__,
                        StringFormat(
                            "ZigZagElliot database first alert saved after tester save start. runId=%I64d currentBar=%s",
                            this.databaseRun.id,
                            TimeToString(
                                snapshot.alert.currentBarTime,
                                TIME_DATE | TIME_SECONDS
                            )
                        )
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
     * シグナル回数とMTF_3in3固定描画オブジェクトを解放する。
     */
    void destroy() {
        this.releaseDatabase();
        this.checkedSignalKeys.Clear();

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
    /** DB照合と復元を完了した起点・方向。回数を繰り返し巻き戻さない。 */
    CArrayString checkedSignalKeys;
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
    /** テスターの保存対象期間への到達をログへ出力済みの場合true。 */
    bool databaseSavePeriodReached;
    /** 保存開始日時以降の最初のAlert保存をログへ出力済みの場合true。 */
    bool databaseFirstSnapshotSaved;

    /**
     * 初めて判定する起点・方向のアラート済み状態をDBから復元する。
     *
     * テスターとDB保存無効時は従来どおり。照合失敗時はキャッシュせず、
     * 次回のバー判定で再試行する。復元は分析・描画・メール処理より前に行う。
     * @param fromReferenceTime 補正前のシグナル基準時刻。
     * @param fromIsBuy 補正前の分析方向。
     * @return 判定を継続できる場合true。
     */
    bool restoreAlertSignalCount(const datetime fromReferenceTime, const bool fromIsBuy) {
        if (!this.config.mtf3In3AlertDatabaseEnabled
                || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)
                || (this.marketContext.timeFrame != PERIOD_M5
                    && this.marketContext.timeFrame != PERIOD_H1)) {
            return true;
        }
        if (fromReferenceTime <= 0 || this.signalCount == NULL) {
            return false;
        }
        string signalKey = StringFormat("%I64d|%d", (long)fromReferenceTime, (int)fromIsBuy);
        if (this.checkedSignalKeys.SearchLinear(signalKey) >= 0) {
            return true;
        }
        if (!this.databaseReady && !this.initializeDatabase()) {
            this.logger.error(__FUNCTION__, "signal history unavailable; alert judgment deferred");
            return false;
        }
        ZigZagElliotAlertPersistenceService *persistenceService =
            this.databaseContext.getPersistenceService();
        int savedCount = 0;
        if (persistenceService == NULL || !persistenceService.loadAlertSignalCount(
                this.databaseRun.sourceServer, this.databaseRun.sourceLogin,
                this.marketContext.symbolName, this.marketContext.timeFrame,
                fromReferenceTime, fromIsBuy, TimeCurrent(), savedCount)) {
            this.logger.error(__FUNCTION__, "signal history lookup failed; alert judgment deferred");
            return false;
        }
        if (savedCount > 0 && !this.signalCount.restoreCount(
                fromReferenceTime, fromIsBuy, savedCount)) {
            this.logger.error(__FUNCTION__, "signal count restore failed; alert judgment deferred");
            return false;
        }
        if (!this.checkedSignalKeys.Add(signalKey)) {
            return false;
        }
        if (savedCount > 0) {
            this.logger.info(__FUNCTION__, StringFormat(
                "alert signal restored. referenceTime=%s isBuy=%s count=%d",
                TimeToString(fromReferenceTime, TIME_DATE | TIME_SECONDS),
                (string)fromIsBuy, savedCount));
        }
        return true;
    }

    /**
     * 取得済みの対象足がテスターのDB保存開始日時に達したか判定する。
     *
     * @param fromCurrentBarTime 分析に使用した現在足の開始サーバー時刻
     * @return LIVE、日時制限なし、または保存対象期間の場合true
     */
    bool isDatabaseSaveTimeReached(const datetime fromCurrentBarTime) {
        if (!MQLInfoInteger(MQL_TESTER)
                || this.config.mtf3In3AlertTesterSaveStartTime == 0) {
            return true;
        }

        return fromCurrentBarTime > 0
            && fromCurrentBarTime >= this.config.mtf3In3AlertTesterSaveStartTime;
    }

    /**
     * 実行モードへ適用するDB保存開始日時を取得する。
     *
     * @return テスターの設定日時。LIVEは0
     */
    datetime getEffectiveDatabaseSaveStartTime() {
        if (!MQLInfoInteger(MQL_TESTER)) {
            return 0;
        }

        return this.config.mtf3In3AlertTesterSaveStartTime;
    }

    /**
     * DB保存開始日時を設定記録とログ用の文字列へ変換する。
     *
     * @param fromSaveStartTime 保存開始サーバー時刻
     * @return 日時制限なしは0、それ以外は秒までの日時文字列
     */
    string formatDatabaseSaveStartTime(const datetime fromSaveStartTime) {
        if (fromSaveStartTime == 0) {
            return "0";
        }

        return TimeToString(fromSaveStartTime, TIME_DATE | TIME_SECONDS);
    }

    /**
     * ZigZagElliotデータベースを開き、実行情報を保存する。
     *
     * 初期化に失敗した場合は、
     * データベースだけを無効化する。
     *
     * @return 保存可能になった場合true
     */
    bool initializeDatabase() {
        if (!this.config.mtf3In3AlertDatabaseEnabled) {
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
            false,
            true
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
        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "ZigZagElliot database save policy. testerSaveStartTime=%s effectiveSaveStartTime=%s basis=SERVER_BAR_OPEN zero=UNRESTRICTED",
                this.formatDatabaseSaveStartTime(
                    this.config.mtf3In3AlertTesterSaveStartTime
                ),
                this.formatDatabaseSaveStartTime(
                    this.getEffectiveDatabaseSaveStartTime()
                )
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
        this.databaseRun.schemaVersion = 7;
        this.databaseRun.sourceMode = "LIVE";

        if (Util::isStrategyTester()) {
            this.databaseRun.sourceMode = "TESTER";
        }

        this.databaseRun.source = "ZIGZAG_ELLIOT";
        this.databaseRun.programName = MQLInfoString(MQL_PROGRAM_NAME);
        this.databaseRun.programVersion = "1.53";
        this.databaseRun.strategy = "MTF_3in3";
        this.databaseRun.strategyVersion = "MTF3IN3_V6";
        if (this.marketContext.timeFrame == PERIOD_M5) {
            this.databaseRun.strategyVersion = "MTF3IN3_M5_CORRECTED_WAVES_V12";
        }
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
     * 判定とDB保存の設定を比較用文字列として取得する。
     *
     * @return 設定文字列
     */
    string createInputText() {
        string inputText = "";
        inputText += "h1DisplayWaveEntryLimitEnabled="
            + (string)this.config.h1DisplayWaveEntryLimitEnabled;
        inputText += "|h1W1ConfirmationMode="
            + getH1W1ConfirmationModeText(
                this.config.h1W1ConfirmationMode
            );
        inputText += "|h1DirectionAlignmentMode="
            + getH1DirectionAlignmentModeText(
                this.config.h1DirectionAlignmentMode
            );
        inputText += "|h1Ema200ConfirmationMode="
            + getH1Ema200ConfirmationModeText(
                this.config.h1Ema200ConfirmationMode
            );
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
        inputText += "|mtf3In3AlertTesterSaveStartTime="
            + this.formatDatabaseSaveStartTime(
                this.config.mtf3In3AlertTesterSaveStartTime
            );
        inputText += "|mtf3In3AlertEffectiveSaveStartTime="
            + this.formatDatabaseSaveStartTime(
                this.getEffectiveDatabaseSaveStartTime()
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
        this.databaseSavePeriodReached = false;
        this.databaseFirstSnapshotSaved = false;
        ZeroMemory(this.databaseRun);

        if (this.databaseContext != NULL) {
            this.databaseContext.close();
            delete this.databaseContext;
            this.databaseContext = NULL;
        }
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH
