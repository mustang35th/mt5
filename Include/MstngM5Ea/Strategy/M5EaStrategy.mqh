#ifndef MSTNGM5EA_STRATEGY_MQH
#define MSTNGM5EA_STRATEGY_MQH

#include <Mstng\Database\Service\CurrencyStrengthExecutionInfoProvider.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Strength\CurrencyStrengthRankGapDirectionProvider.mqh>
#include <Mstng\Util\ElliotHistoryPreparation.mqh>
#include <Mstng\Util\Util.mqh>
#include <MstngM5Ea\Config\M5EaConfig.mqh>
#include <MstngM5Ea\Strategy\M5EaStrategyDecision.mqh>

/**
 * MN1→W1→D1→H4→H1→M15→M5の分析リソースを所有するM5専用アダプター。
 * Entryの実行周期・バー消費はControllerが管理し、トレイル分析と分離する。
 */
class M5EaStrategy {
public:
    /**
     * 所有リソースを空状態で初期化する。
     */
    M5EaStrategy() {
        this.handlePool = NULL;
        this.elliotAll = NULL;
        this.isPrepared = false;
        this.lastError = "";
        this.historyStatusText = "";
        this.historyPreparation.reset();
        this.executionInfoProvider = NULL;
        this.gapDirectionProvider = NULL;
        this.currencyStrengthEnabled = false;
        this.longMediumGapDirectionEnabled = false;
        this.currencyStrengthMinimumRankDifference = 4;
    }

    /**
     * 分析とハンドルを解放する。
     */
    ~M5EaStrategy() {
        this.destroy();
    }

    /**
     * M5固定で既存Profileのハンドル構成と判定設定を準備する。
     *
     * @param fromConfig 検証済みM5 EA設定。
     * @return 初期化に成功した場合true。
     */
    bool initialize(const M5EaConfig &fromConfig) {
        this.destroy();
        this.currencyStrengthEnabled = fromConfig.currencyStrengthEnabled;
        this.longMediumGapDirectionEnabled = fromConfig.longMediumGapDirectionEnabled;
        this.currencyStrengthMinimumRankDifference = fromConfig.currencyStrengthMinimumRankDifference;
        MarketContext context(fromConfig.symbolName, PERIOD_M5);
        this.marketContext = context;

        if (this.currencyStrengthMinimumRankDifference < 1 || this.currencyStrengthMinimumRankDifference > 7
                || !this.historyPreparation.initialize(fromConfig.symbolName, PERIOD_M5, Util::isStrategyTester())) {
            this.lastError = "ANALYSIS_CONFIGURATION_INVALID";

            return false;
        }

        if (!this.initializeCurrencyStrength(fromConfig)) {
            this.destroy();

            return false;
        }

        this.handlePool = new OscillatorHandlePool(this.marketContext);

        if (this.handlePool == NULL) {
            this.lastError = "HANDLE_POOL_UNAVAILABLE";

            return false;
        }

        this.handlePool.setTimeframesFromMn1To();
        this.lastError = "";

        return true;
    }

    /**
     * 履歴準備だけを確認し、波動分析やJudge・Entry評価は行わない。
     * 成功してもevaluateは許可せず、通常のanalyzeを改めて必要とする。
     *
     * @param fromWarmupEndTime TESTER売買開始時刻。0は開始前の履歴確認間引きなし。
     * @return ハンドルプールと必要な価格系列が準備済みの場合true。
     */
    bool prepareHistory(const datetime fromWarmupEndTime = 0) {
        this.isPrepared = false;

        if (this.handlePool == NULL || !this.isHistoryReady(fromWarmupEndTime)) {
            this.lastError = "ANALYSIS_HISTORY_UNAVAILABLE";

            return false;
        }

        this.lastError = "";

        return true;
    }

    /**
     * 同じM5枠の通貨強弱と波動をそろえ、エントリー評価を準備する。
     */
    bool analyze(M5EaStrategySnapshot &fromSnapshot) {
        return this.analyzeCore(fromSnapshot, true);
    }

    /**
     * 通貨強弱の取得状態から独立して、保有ポジションの保護用に分析する。
     * この結果ではevaluateを許可しない。
     */
    bool analyzeForTrail(M5EaStrategySnapshot &fromSnapshot) {
        return this.analyzeCore(fromSnapshot, false);
    }

    /**
     * 直前の分析に保存済み回数を適用し、既存戦略を1回だけ実行する。
     *
     * @param fromPreviousCount このキーの保存済み回数。
     * @param fromSnapshot analyzeが返したスナップショット。
     * @return Judgeを評価できた場合true。
     */
    bool evaluate(const int fromPreviousCount, M5EaStrategySnapshot &fromSnapshot) {
        if (!this.isPrepared) {
            this.lastError = "ANALYSIS_NOT_PREPARED";

            return false;
        }

        this.isPrepared = false;
        M5EaStrategyDecision decision;
        bool isSucceeded = decision.evaluate(
            this.elliotAll, fromPreviousCount, fromSnapshot,
            this.currencyStrengthMinimumRankDifference
        );

        this.lastError = "";

        if (!isSucceeded) {
            this.lastError = fromSnapshot.reasonCode;
        }

        return isSucceeded;
    }

    /**
     * 最新M5 Waveを返す。次の分析まで有効な非所有参照。
     */
    Wave *getWave() {
        if (this.elliotAll == NULL || !this.elliotAll.isAnalysisSucceeded
                || this.elliotAll.elliotCurrent == NULL) {
            return NULL;
        }

        return this.elliotAll.elliotCurrent.getLatestWave();
    }

    /**
     * 直近の失敗理由を返す。
     */
    string getLastError() { return this.lastError; }

    /**
     * 最後に確認した価格履歴の準備結果だけを返す。市場参照・分析は行わない。
     */
    bool isHistoryPrepared() const { return this.historyPreparation.isReady(); }

    /**
     * 価格履歴を実際に確認済みかを返す。市場参照・分析は行わない。
     */
    bool isHistoryChecked() const { return this.historyPreparation.isChecked(); }

    /**
     * 直近の不足足を返す。bit 0からMN1・W1・D1・H4・H1・M15・M5の順。
     */
    int getHistoryMissingMask() const { return this.historyPreparation.getMissingMask(); }

    /**
     * 直近の未同期足を返す。不足足と同じビット順で、市場参照は行わない。
     */
    int getHistoryUnsynchronizedMask() const { return this.historyPreparation.getUnsynchronizedMask(); }

    /**
     * 直近の不足足だけの診断を返す。市場参照・分析は行わない。
     */
    string getHistoryMissingStatusText() const { return this.historyPreparation.getMissingStatusText(); }

    /**
     * 全分析時間足の同期・可視本数・必要本数・最古日時を返す。
     * 現在時刻は含めず、呼び出し側で状態変化時のログ抑制に使用する。
     */
    string getHistoryStatusText() { return this.historyStatusText; }

    /**
     * 分析とハンドルを順に解放する。
     */
    void destroy() {
        this.isPrepared = false;
        this.historyStatusText = "";
        this.historyPreparation.reset();

        if (this.elliotAll != NULL) {
            delete this.elliotAll;
            this.elliotAll = NULL;
        }

        if (this.handlePool != NULL) {
            delete this.handlePool;
            this.handlePool = NULL;
        }

        if (this.executionInfoProvider != NULL) {
            delete this.executionInfoProvider;
            this.executionInfoProvider = NULL;
        }

        if (this.gapDirectionProvider != NULL) {
            delete this.gapDirectionProvider;
            this.gapDirectionProvider = NULL;
        }
    }

private:
    /**
     * shift 0を変更せず分析し、Judge前のキーを取り出す。
     *
     * @param fromSnapshot 分析結果の格納先。
     * @return 分析成功の場合true。失敗は回数を消費しない。
     */
    bool analyzeCore(M5EaStrategySnapshot &fromSnapshot, const bool fromForEntry) {
        fromSnapshot.reset();
        this.isPrepared = false;

        if (this.elliotAll != NULL) {
            delete this.elliotAll;
            this.elliotAll = NULL;
        }

        if (!this.prepareHistory()) {
            return false;
        }

        datetime barTime = iTime(this.marketContext.symbolName, PERIOD_M5, 0);
        CurrencyStrengthExecutionInfo executionInfo;
        executionInfo.reset();
        if (fromForEntry && !this.loadCurrencyStrength(barTime, executionInfo)) {
            fromSnapshot.barTime = barTime;
            fromSnapshot.reasonCode = this.lastError;

            return false;
        }

        this.elliotAll = new ElliotAll(this.marketContext);

        if (this.elliotAll == NULL) {
            this.lastError = "ANALYSIS_UNAVAILABLE";

            return false;
        }

        this.elliotAll.isTimer = !Util::isStrategyTester();
        this.elliotAll.setAnalysisStartTimeFrame(
            PERIOD_MN1
        );
        this.elliotAll.isMailValidationFileEnabled = false;
        this.elliotAll.isH1DisplayWaveEntryLimitEnabled = false;
        this.elliotAll.isCurrencyStrengthEntryFilterEnabled = fromForEntry && this.currencyStrengthEnabled;
        this.elliotAll.setCurrencyStrengthExecutionInfo(executionInfo);
        this.elliotAll.isSendMail = false;
        this.elliotAll.timerSeconds = 30;
        this.elliotAll.setOscillatorHandlePool(this.handlePool);

        LoggerRepeatScope logScope;
        Logger::beginTesterRepeatScope(this.marketContext.symbolName, barTime, logScope);
        this.elliotAll.analyze();
        Logger::endTesterRepeatScope(logScope, this.elliotAll.isAnalysisSucceeded);

        if (barTime != iTime(this.marketContext.symbolName, PERIOD_M5, 0)) {
            this.lastError = "ANALYSIS_BAR_CHANGED";

            return false;
        }

        M5EaStrategyDecision decision;
        bool isAnalysisPrepared = decision.prepare(this.elliotAll, barTime, fromSnapshot);
        this.isPrepared = fromForEntry && isAnalysisPrepared;
        this.lastError = "";

        if (!isAnalysisPrepared) {
            this.lastError = fromSnapshot.reasonCode;
        }

        return isAnalysisPrepared;
    }

    /** 分析対象。 */
    MarketContext marketContext;

    /** エントリーに通貨強弱条件を使用する場合true。 */
    bool currencyStrengthEnabled;

    /** 長中期の増減方向一致を使用する場合true。 */
    bool longMediumGapDirectionEnabled;

    /** 両期間の順位差または端順位条件に使用する最低差。 */
    int currencyStrengthMinimumRankDifference;

    /** 現在M5の順位取得。チャート表示を所有しない。 */
    CurrencyStrengthExecutionInfoProvider *executionInfoProvider;

    /** 過去M5の長中期増減情報取得。 */
    CurrencyStrengthRankGapDirectionProvider *gapDirectionProvider;

    /** 所有ハンドル。 */
    OscillatorHandlePool *handlePool;

    /** 所有分析結果。 */
    ElliotAll *elliotAll;

    /** 直前分析のJudge未評価フラグ。 */
    bool isPrepared;

    /** 直近失敗理由。 */
    string lastError;

    /** 全時間足の直近履歴診断。TesterではEAから見える系列だけを示す。 */
    string historyStatusText;

    /** 観測版と共通の価格履歴準備。分析成功とは分けて管理する。 */
    ElliotHistoryPreparation historyPreparation;

    /**
     * 通常版と同じ順位・増減Providerを表示なしで準備する。
     */
    bool initializeCurrencyStrength(const M5EaConfig &fromConfig) {
        if (!this.currencyStrengthEnabled) {
            return true;
        }

        this.executionInfoProvider = new CurrencyStrengthExecutionInfoProvider(
            fromConfig.currencyStrengthDatabaseFileName, fromConfig.currencyStrengthDatabaseSplitByYear,
            fromConfig.currencyStrengthDatabaseUseCommonFolder, fromConfig.currencyStrengthDatabaseProfile,
            CURRENCY_STRENGTH_RANK_QUERY_MODE_LATEST_AT_OR_BEFORE, 15,
            fromConfig.currencyStrengthVoteWeightMode);
        if (this.executionInfoProvider == NULL) {
            this.lastError = "CURRENCY_STRENGTH_PROVIDER_UNAVAILABLE";

            return false;
        }

        if (this.longMediumGapDirectionEnabled) {
            string baseCurrency = SymbolInfoString(this.marketContext.symbolName, SYMBOL_CURRENCY_BASE);
            string quoteCurrency = SymbolInfoString(this.marketContext.symbolName, SYMBOL_CURRENCY_PROFIT);
            if (baseCurrency == "" || quoteCurrency == "") {
                this.lastError = "CURRENCY_STRENGTH_CURRENCY_UNAVAILABLE";

                return false;
            }

            this.gapDirectionProvider = new CurrencyStrengthRankGapDirectionProvider(
                fromConfig.currencyStrengthDatabaseFileName, fromConfig.currencyStrengthDatabaseSplitByYear,
                fromConfig.currencyStrengthDatabaseUseCommonFolder, fromConfig.currencyStrengthDatabaseProfile,
                fromConfig.currencyStrengthVoteWeightMode, Util::isStrategyTester(),
                baseCurrency, quoteCurrency, 15);
            if (this.gapDirectionProvider == NULL) {
                this.lastError = "CURRENCY_STRENGTH_GAP_PROVIDER_UNAVAILABLE";

                return false;
            }
        }

        return true;
    }

    /**
     * 今回のM5と一致する現在順位・必要な履歴だけを採用する。
     * 待機は回数未消費で再確認し、方向不明は通常のJudgeへ渡す。
     */
    bool loadCurrencyStrength(const datetime fromBarTime, CurrencyStrengthExecutionInfo &fromInfo) {
        fromInfo.reset();
        if (!this.currencyStrengthEnabled) {
            return true;
        }

        this.lastError = "CURRENCY_STRENGTH_WAITING";
        if (this.executionInfoProvider == NULL || fromBarTime <= 0) {
            return false;
        }

        datetime executionTime = TimeCurrent();
        if (executionTime <= 0) {
            executionTime = fromBarTime;
        }

        this.executionInfoProvider.load(this.marketContext, executionTime, fromInfo);
        if (!fromInfo.isAvailable() || !fromInfo.isExactM5Bar()
                || fromInfo.targetM5BarTime != fromBarTime) {
            return false;
        }

        fromInfo.longMediumGapDirectionFilterEnabled = this.longMediumGapDirectionEnabled;
        if (this.longMediumGapDirectionEnabled) {
            if (this.gapDirectionProvider == NULL) {
                return false;
            }

            this.gapDirectionProvider.load(fromInfo, fromInfo.longMediumGapDirection);
            if (!fromInfo.longMediumGapDirection.enabled || fromInfo.longMediumGapDirection.waiting
                    || fromInfo.longMediumGapDirection.targetM5BarTime != fromBarTime) {
                return false;
            }
        }

        this.lastError = "";

        return true;
    }

    /**
     * 共通履歴準備へ委譲し、既存の時間足別診断を更新する。
     */
    bool isHistoryReady(const datetime fromWarmupEndTime) {
        bool ready = this.historyPreparation.prepare(fromWarmupEndTime);
        this.historyStatusText = this.historyPreparation.getStatusText();

        return ready;
    }
};

#endif
