//+------------------------------------------------------------------+
//|                            ElliotAnalysisController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_ANALYSIS_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_ANALYSIS_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ElliotAllFile.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>

/**
 * Elliott分析結果、オシレーターハンドルおよび分析CSVを管理するクラス。
 */
class ElliotAnalysisController {
public:
    /**
     * 保持リソースを初期化する。
     */
    ElliotAnalysisController() {
        this.oscillatorHandlePool = NULL;
        this.elliotAll = NULL;
        this.timerMode = true;
        this.analysisStartTimeFrame = PERIOD_MN1;
        this.mailValidationFileEnabled = false;
        this.h1DisplayWaveEntryLimitEnabled = false;
        this.currencyStrengthEntryFilterEnabled = false;
        this.fileInitialized = false;
        this.logStartTimeFrame = PERIOD_D1;
    }

    /**
     * 保持リソースを解放する。
     */
    ~ElliotAnalysisController() {
        this.destroy();
    }

    /**
     * 分析用ハンドルとテスター用CSVを初期化する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromConfig インジケータ設定
     * @param fromTimerMode タイマー実行の場合true
     * @return 初期化に成功した場合true
     */
    bool initialize(
        MarketContext &fromMarketContext,
        ZigZagElliotConfig &fromConfig,
        bool fromTimerMode
    ) {
        this.destroy();

        this.marketContext = fromMarketContext;
        this.timerMode = fromTimerMode;
        this.analysisStartTimeFrame = PERIOD_MN1;
        this.logStartTimeFrame = PERIOD_D1;

        if (!this.timerMode
                && (this.marketContext.timeFrame == PERIOD_W1
                    || this.marketContext.timeFrame == PERIOD_MN1)) {
            this.logStartTimeFrame = PERIOD_MN1;
        }

        this.mailValidationFileEnabled =
            fromConfig.mailValidationFileEnabled;
        this.h1DisplayWaveEntryLimitEnabled =
            fromConfig.h1DisplayWaveEntryLimitEnabled;
        this.currencyStrengthEntryFilterEnabled =
            fromConfig.currencyStrengthEnabled
                && fromConfig.currencyStrengthEntryFilterEnabled;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.oscillatorHandlePool =
            new OscillatorHandlePool(this.marketContext);

        if (this.oscillatorHandlePool == NULL) {
            this.logger.error(
                __FUNCTION__,
                "oscillator handle pool allocation failed"
            );

            return false;
        }

        if (this.analysisStartTimeFrame == PERIOD_MN1) {
            this.oscillatorHandlePool.setTimeframesFromMn1To();
        } else {
            this.oscillatorHandlePool.setTimeframesFromD1To();
        }

        return true;
    }

    /**
     * 全時間足のElliott分析結果を作成する。
     *
     * @param fromExecutionInfo 通貨強弱実行情報
     * @param fromTimerSeconds 分析実行間隔秒
     * @return 分析に成功した場合true
     */
    bool analyze(
        CurrencyStrengthExecutionInfo &fromExecutionInfo,
        int fromTimerSeconds
    ) {
        if (this.elliotAll != NULL) {
            delete this.elliotAll;
            this.elliotAll = NULL;
        }

        this.elliotAll = new ElliotAll(this.marketContext);

        if (this.elliotAll == NULL) {
            this.logger.error(
                __FUNCTION__,
                "ElliotAll allocation failed"
            );

            return false;
        }

        this.elliotAll.isTimer = this.timerMode;
        this.elliotAll.setAnalysisStartTimeFrame(
            this.analysisStartTimeFrame
        );
        this.elliotAll.isMailValidationFileEnabled =
            this.mailValidationFileEnabled;
        this.elliotAll.isH1DisplayWaveEntryLimitEnabled =
            this.h1DisplayWaveEntryLimitEnabled;
        this.elliotAll.isCurrencyStrengthEntryFilterEnabled =
            this.currencyStrengthEntryFilterEnabled;
        this.elliotAll.setOscillatorHandlePool(
            this.oscillatorHandlePool
        );
        this.elliotAll.setCurrencyStrengthExecutionInfo(
            fromExecutionInfo
        );
        this.elliotAll.timerSeconds = fromTimerSeconds;
        this.elliotAll.isSendMail = true;
        this.elliotAll.analyze();

        return this.elliotAll.isAnalysisSucceeded;
    }

    /**
     * 最新のElliott分析結果を取得する。
     *
     * 返却ポインタは非所有参照であり、呼び出し側では解放しない。
     *
     * @return Elliott分析結果
     */
    ElliotAll *getElliotAll() {
        return this.elliotAll;
    }

    /**
     * オシレーターハンドルプールを取得する。
     *
     * 返却ポインタは非所有参照であり、呼び出し側では解放しない。
     *
     * @return オシレーターハンドルプール
     */
    OscillatorHandlePool *getOscillatorHandlePool() {
        return this.oscillatorHandlePool;
    }

    /**
     * テスター用Elliott分析CSVを初期化する。
     *
     * @return 初期化に成功した場合true
     */
    bool initializeOutput() {
        if (this.timerMode || this.fileInitialized) {
            return true;
        }

        return this.openFile();
    }

    /**
     * テスター用Elliott分析CSVへ最新結果を書き込む。
     *
     * @return 書き込みに成功した場合true
     */
    bool writeCsv() {
        if (this.timerMode || !this.fileInitialized) {
            return true;
        }

        if (this.elliotAll == NULL
                || !this.elliotAll.isAnalysisSucceeded) {
            return false;
        }

        string csvText = this.elliotAll.getCsv(
            true,
            this.logStartTimeFrame
        );

        if (!this.elliotAllFile.writeCsvTextValue(
                csvText,
                this.logStartTimeFrame,
                this.marketContext.timeFrame)) {
            this.logger.error(
                __FUNCTION__,
                "ElliotAll CSV write failed"
            );
            this.elliotAllFile.close();
            this.fileInitialized = false;

            return false;
        }

        return true;
    }

    /**
     * 分析結果、CSVおよびハンドルプールを解放する。
     */
    void destroy() {
        if (this.elliotAll != NULL) {
            delete this.elliotAll;
            this.elliotAll = NULL;
        }

        if (this.fileInitialized) {
            this.elliotAllFile.close();
            this.fileInitialized = false;
        }

        if (this.oscillatorHandlePool != NULL) {
            delete this.oscillatorHandlePool;
            this.oscillatorHandlePool = NULL;
        }
    }

private:
    /** 市場コンテキスト。 */
    MarketContext marketContext;
    /** ロガー。 */
    Logger logger;
    /** オシレーターハンドルプール。 */
    OscillatorHandlePool *oscillatorHandlePool;
    /** 最新のElliott分析結果。 */
    ElliotAll *elliotAll;
    /** テスター用Elliott分析CSV。 */
    ElliotAllFile elliotAllFile;
    /** タイマー実行の場合true。 */
    bool timerMode;
    /** Elliott分析開始時間足。 */
    ENUM_TIMEFRAMES analysisStartTimeFrame;
    /** Mail内容を検証用ファイルへ出力する場合true。 */
    bool mailValidationFileEnabled;
    /** H1表示波ごとのエントリー回数制限を使用する場合true。 */
    bool h1DisplayWaveEntryLimitEnabled;
    /** 通貨強弱をエントリー条件として使用する場合true。 */
    bool currencyStrengthEntryFilterEnabled;
    /** CSV初期化済みの場合true。 */
    bool fileInitialized;
    /** CSV出力開始時間足。 */
    ENUM_TIMEFRAMES logStartTimeFrame;

    /**
     * テスター用Elliott分析CSVを初期化する。
     *
     * @return 初期化に成功した場合true
     */
    bool openFile() {
        this.elliotAllFile.setupMultiTimeFrameSameFolder(
            "Logs\\ElliotAllStochasticMainOrderTrade",
            this.marketContext,
            this.logStartTimeFrame,
            true,
            ",",
            true,
            true,
            CSV_FILE_WRITE_MODE_OVERWRITE
        );

        if (!this.elliotAllFile.initializeMultiTimeFrame(
                this.logStartTimeFrame,
                this.marketContext.timeFrame)) {
            this.logger.error(
                __FUNCTION__,
                "ElliotAll CSV initialize failed"
            );
            this.elliotAllFile.close();

            return false;
        }

        this.fileInitialized = true;

        return true;
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_ANALYSIS_CONTROLLER_MQH
