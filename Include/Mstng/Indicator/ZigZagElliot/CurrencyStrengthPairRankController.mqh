//+------------------------------------------------------------------+
//|                           CurrencyStrengthPairRankController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZIGZAG_CURRENCY_STRENGTH_CONTROLLER_MQH
#define MSTNG_ZIGZAG_CURRENCY_STRENGTH_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Database\Service\CurrencyStrengthExecutionInfoProvider.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthPairRank.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthRankQueryMode.mqh>

/**
 * 通貨強弱情報の取得、変更検知および順位パネル表示を管理するクラス。
 */
class CurrencyStrengthPairRankController {
public:
    /**
     * 保持オブジェクトとキャッシュを初期化する。
     */
    CurrencyStrengthPairRankController() {
        this.pairRankDraw = NULL;
        this.executionInfoProvider = NULL;
        this.enabled = false;
        this.rankVisible = false;
        this.panelXDistance = 48;
        this.refreshSeconds = 15;
        this.databaseProfile =
            CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
        this.voteWeightMode = CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;
        this.databaseFileName = "";
        this.databaseSplitByYear = true;
        this.databaseUseCommonFolder = true;
        this.resetState();
    }

    /**
     * 保持リソースを解放する。
     */
    ~CurrencyStrengthPairRankController() {
        this.destroy();
    }

    /**
     * 市場コンテキストと設定を使用して初期化する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromConfig インジケータ設定
     */
    void initialize(
        MarketContext &fromMarketContext,
        ZigZagElliotConfig &fromConfig
    ) {
        this.destroy();

        this.marketContext = fromMarketContext;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.enabled = fromConfig.currencyStrengthEnabled;
        this.rankVisible = fromConfig.currencyStrengthRankVisible;
        this.panelXDistance =
            fromConfig.currencyStrengthRankPanelXDistance;
        this.refreshSeconds = fromConfig.currencyStrengthRefreshSeconds;
        this.databaseProfile =
            fromConfig.currencyStrengthDatabaseProfile;
        this.voteWeightMode = fromConfig.currencyStrengthVoteWeightMode;
        this.databaseFileName =
            fromConfig.currencyStrengthDatabaseFileName;
        this.databaseSplitByYear =
            fromConfig.currencyStrengthDatabaseSplitByYear;
        this.databaseUseCommonFolder =
            fromConfig.currencyStrengthDatabaseUseCommonFolder;
        this.baseCurrency = SymbolInfoString(
            this.marketContext.symbolName,
            SYMBOL_CURRENCY_BASE
        );
        this.quoteCurrency = SymbolInfoString(
            this.marketContext.symbolName,
            SYMBOL_CURRENCY_PROFIT
        );

        this.createView();
        this.createProvider();
    }

    /**
     * 現在時刻の通貨強弱情報を取得し、表示を更新する。
     */
    void update() {
        if (!this.enabled || this.executionInfoProvider == NULL) {
            this.executionInfo.reset();

            return;
        }

        datetime executionTime = TimeCurrent();

        if (executionTime <= 0) {
            executionTime = iTime(
                this.marketContext.symbolName,
                this.marketContext.timeFrame,
                0
            );
        }

        ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS executionStatus =
            this.executionInfoProvider.load(
                this.marketContext,
                executionTime,
                this.executionInfo
            );

        if (!this.rankVisible || this.pairRankDraw == NULL) {
            return;
        }

        if (executionStatus == CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR) {
            this.updateError(executionStatus);

            return;
        }

        if (executionStatus != CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND) {
            this.updateUnavailable(executionStatus);

            return;
        }

        this.updateFound(executionStatus);
    }

    /**
     * 最新の通貨強弱実行情報を取得する。
     *
     * @return 通貨強弱実行情報
     */
    CurrencyStrengthExecutionInfo getExecutionInfo() {
        return this.executionInfo;
    }

    /**
     * チャートサイズに合わせて順位パネルを再配置する。
     */
    void reposition() {
        if (this.pairRankDraw != NULL) {
            this.pairRankDraw.reposition();
        }
    }

    /**
     * 通常描画後に順位パネルを最前面へ再生成する。
     */
    void redrawOnTop() {
        if (!this.rankVisible || this.pairRankDraw == NULL) {
            return;
        }

        if (!this.pairRankDraw.redrawOnTop()) {
            this.logger.error(
                __FUNCTION__,
                "currency strength rank foreground redraw failed"
            );
        }
    }

    /**
     * Provider、表示オブジェクトおよびキャッシュを解放する。
     */
    void destroy() {
        if (this.executionInfoProvider != NULL) {
            this.executionInfoProvider.close();
            delete this.executionInfoProvider;
            this.executionInfoProvider = NULL;
        }

        if (this.pairRankDraw != NULL) {
            this.pairRankDraw.clear();
            delete this.pairRankDraw;
            this.pairRankDraw = NULL;
        }

        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "CurrencyStrengthPairRank",
            0,
            -1
        );
        this.resetState();
    }

private:
    /** 市場コンテキスト。 */
    MarketContext marketContext;
    /** ロガー。 */
    Logger logger;
    /** 順位パネル描画。 */
    DrawCurrencyStrengthPairRank *pairRankDraw;
    /** 通貨強弱実行情報Provider。 */
    CurrencyStrengthExecutionInfoProvider *executionInfoProvider;
    /** 最新の通貨強弱実行情報。 */
    CurrencyStrengthExecutionInfo executionInfo;
    /** 通貨強弱を利用する場合true。 */
    bool enabled;
    /** 順位パネルを表示する場合true。 */
    bool rankVisible;
    /** 順位パネルの右端からの距離。 */
    int panelXDistance;
    /** DB再取得間隔秒。 */
    int refreshSeconds;
    /** DB参照プロファイル。 */
    CurrencyStrengthRankDatabaseProfile databaseProfile;
    /** 投票ウェイト方式。 */
    CurrencyStrengthVoteWeightMode voteWeightMode;
    /** DBファイル名。 */
    string databaseFileName;
    /** DBを年単位で分割する場合true。 */
    bool databaseSplitByYear;
    /** DBで共通フォルダを使用する場合true。 */
    bool databaseUseCommonFolder;
    /** 基軸通貨。 */
    string baseCurrency;
    /** 決済通貨。 */
    string quoteCurrency;
    /** 前回表示した実行ID。 */
    long lastRunId;
    /** 前回表示した対象M5バー時刻。 */
    datetime lastTargetM5BarTime;
    /** 前回表示したM5バー時刻。 */
    datetime lastM5BarTime;
    /** 前回表示した更新時刻。 */
    datetime lastUpdatedAt;
    /** 前回表示したデータソース。 */
    string lastSourceMode;
    /** 前回表示した基軸通貨の長中期順位。 */
    int baseLongMediumRank;
    /** 前回表示した基軸通貨の中短期順位。 */
    int baseMediumShortRank;
    /** 前回表示した決済通貨の長中期順位。 */
    int quoteLongMediumRank;
    /** 前回表示した決済通貨の中短期順位。 */
    int quoteMediumShortRank;
    /** 有効な順位を表示済みの場合true。 */
    bool rankAvailable;
    /** 前回表示した実行状態。 */
    ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS lastDisplayStatus;

    /**
     * 順位パネルを作成する。
     */
    void createView() {
        if (!this.rankVisible) {
            return;
        }

        int minimumPanelXDistance = 48;

        if (this.panelXDistance < minimumPanelXDistance) {
            this.panelXDistance = minimumPanelXDistance;
        }

        this.pairRankDraw = new DrawCurrencyStrengthPairRank(
            0,
            this.panelXDistance,
            this.voteWeightMode
        );

        if (this.pairRankDraw == NULL) {
            this.logger.error(
                __FUNCTION__,
                "currency strength rank draw allocation failed"
            );

            return;
        }

        this.pairRankDraw.drawUnavailable(
            this.baseCurrency,
            this.quoteCurrency
        );
    }

    /**
     * 通貨強弱実行情報Providerを作成する。
     */
    void createProvider() {
        if (!this.enabled) {
            return;
        }

        if (this.databaseFileName == ""
                || this.baseCurrency == ""
                || this.quoteCurrency == "") {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "currency strength rank setting is invalid. file=%s base=%s quote=%s",
                    this.databaseFileName,
                    this.baseCurrency,
                    this.quoteCurrency
                )
            );

            return;
        }

        this.executionInfoProvider =
            new CurrencyStrengthExecutionInfoProvider(
                this.databaseFileName,
                this.databaseSplitByYear,
                this.databaseUseCommonFolder,
                this.databaseProfile,
                CURRENCY_STRENGTH_RANK_QUERY_MODE_LATEST_AT_OR_BEFORE,
                this.refreshSeconds,
                this.voteWeightMode
            );

        if (this.executionInfoProvider == NULL) {
            this.logger.error(
                __FUNCTION__,
                "currency strength execution info provider allocation failed"
            );
        }
    }

    /**
     * エラー状態の表示を更新する。
     *
     * @param fromExecutionStatus 実行状態
     */
    void updateError(
        ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS fromExecutionStatus
    ) {
        if (this.lastDisplayStatus
                != CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR
                && !this.pairRankDraw.drawError()) {
            this.logger.error(
                __FUNCTION__,
                "currency strength error status draw failed"
            );

            return;
        }

        this.lastDisplayStatus = fromExecutionStatus;
    }

    /**
     * データ未取得状態の表示を更新する。
     *
     * @param fromExecutionStatus 実行状態
     */
    void updateUnavailable(
        ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS fromExecutionStatus
    ) {
        if (!this.rankAvailable
                && this.lastDisplayStatus == fromExecutionStatus) {
            return;
        }

        if (!this.pairRankDraw.drawUnavailable(
                this.baseCurrency,
                this.quoteCurrency)) {
            this.logger.error(
                __FUNCTION__,
                "currency strength unavailable rank draw failed"
            );

            return;
        }

        this.resetRankCache();
        this.lastDisplayStatus = fromExecutionStatus;
    }

    /**
     * 取得済み順位の変更を検知して表示を更新する。
     *
     * @param fromExecutionStatus 実行状態
     */
    void updateFound(
        ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS fromExecutionStatus
    ) {
        CurrencyStrengthPairRankInfo rankInfo;
        rankInfo = this.executionInfo.pairRankInfo;
        bool isChanged = !this.rankAvailable
            || this.lastDisplayStatus
                != CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;

        if (rankInfo.runId != this.lastRunId
                || this.executionInfo.targetM5BarTime
                    != this.lastTargetM5BarTime
                || rankInfo.m5BarTime != this.lastM5BarTime
                || rankInfo.updatedAt != this.lastUpdatedAt
                || this.executionInfo.sourceMode != this.lastSourceMode
                || rankInfo.baseLongMediumTermAverageRank
                    != this.baseLongMediumRank
                || rankInfo.baseMediumShortTermAverageRank
                    != this.baseMediumShortRank
                || rankInfo.quoteLongMediumTermAverageRank
                    != this.quoteLongMediumRank
                || rankInfo.quoteMediumShortTermAverageRank
                    != this.quoteMediumShortRank) {
            isChanged = true;
        }

        if (isChanged && !this.pairRankDraw.draw(this.executionInfo)) {
            this.logger.error(
                __FUNCTION__,
                "currency strength rank draw failed"
            );

            return;
        }

        this.lastRunId = rankInfo.runId;
        this.lastTargetM5BarTime = this.executionInfo.targetM5BarTime;
        this.lastM5BarTime = rankInfo.m5BarTime;
        this.lastUpdatedAt = rankInfo.updatedAt;
        this.lastSourceMode = this.executionInfo.sourceMode;
        this.baseLongMediumRank =
            rankInfo.baseLongMediumTermAverageRank;
        this.baseMediumShortRank =
            rankInfo.baseMediumShortTermAverageRank;
        this.quoteLongMediumRank =
            rankInfo.quoteLongMediumTermAverageRank;
        this.quoteMediumShortRank =
            rankInfo.quoteMediumShortTermAverageRank;
        this.rankAvailable = true;
        this.lastDisplayStatus = fromExecutionStatus;
    }

    /**
     * 全状態を初期値へ戻す。
     */
    void resetState() {
        this.baseCurrency = "";
        this.quoteCurrency = "";
        this.executionInfo.reset();
        this.resetRankCache();
        this.lastDisplayStatus =
            CURRENCY_STRENGTH_EXECUTION_STATUS_NOT_QUERIED;
    }

    /**
     * 順位変更検知用キャッシュを初期値へ戻す。
     */
    void resetRankCache() {
        this.lastRunId = 0;
        this.lastTargetM5BarTime = 0;
        this.lastM5BarTime = 0;
        this.lastUpdatedAt = 0;
        this.lastSourceMode = "";
        this.baseLongMediumRank = 0;
        this.baseMediumShortRank = 0;
        this.quoteLongMediumRank = 0;
        this.quoteMediumShortRank = 0;
        this.rankAvailable = false;
    }
};

#endif // MSTNG_ZIGZAG_CURRENCY_STRENGTH_CONTROLLER_MQH
