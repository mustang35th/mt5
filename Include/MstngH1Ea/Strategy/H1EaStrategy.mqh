#ifndef MSTNGH1EA_STRATEGY_MQH
#define MSTNGH1EA_STRATEGY_MQH

#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Util\ElliotHistoryPreparation.mqh>
#include <MstngH1Ea\Strategy\H1EaStrategyDecision.mqh>

/**
 * MN1→W1→D1→H4→H1の分析リソースを所有するH1専用アダプター。
 * Entryの実行周期・バー消費はControllerが管理し、トレイル分析と分離する。
 */
class H1EaStrategy {
public:
    /**
     * 所有リソースを空状態で初期化する。
     */
    H1EaStrategy() {
        this.handlePool = NULL;
        this.elliotAll = NULL;
        this.isPrepared = false;
        this.lastError = "";
        this.historyStatusText = "";
        this.historyPreparation.reset();
    }

    /**
     * 分析とハンドルを解放する。
     */
    ~H1EaStrategy() {
        this.destroy();
    }

    /**
     * H1固定で既存Profileのハンドル構成を準備する。
     *
     * @param fromSymbol 対象シンボル。
     * @return 初期化に成功した場合true。
     */
    bool initialize(const string fromSymbol) {
        this.destroy();
        MarketContext context(fromSymbol, PERIOD_H1);
        this.marketContext = context;
        if (!this.historyPreparation.initialize(fromSymbol, PERIOD_H1, (bool)MQLInfoInteger(MQL_TESTER))) {
            this.lastError = "ANALYSIS_HISTORY_CONFIGURATION_INVALID";
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
     * shift 0を変更せず分析し、Judge前のキーを取り出す。
     *
     * @param fromSnapshot 分析結果の格納先。
     * @return 分析成功の場合true。失敗は回数を消費しない。
     */
    bool analyze(H1EaStrategySnapshot &fromSnapshot) {
        fromSnapshot.reset();
        this.isPrepared = false;

        if (this.elliotAll != NULL) {
            delete this.elliotAll;
            this.elliotAll = NULL;
        }

        if (!this.prepareHistory()) {
            return false;
        }

        datetime barTime = iTime(this.marketContext.symbolName, PERIOD_H1, 0);
        this.elliotAll = new ElliotAll(this.marketContext);

        if (this.elliotAll == NULL) {
            this.lastError = "ANALYSIS_UNAVAILABLE";

            return false;
        }

        this.elliotAll.isTimer = !MQLInfoInteger(MQL_TESTER);
        this.elliotAll.setAnalysisStartTimeFrame(
            Mtf3In3H1Policy::getAnalysisStartTimeFrame()
        );
        this.elliotAll.isMailValidationFileEnabled = false;
        this.elliotAll.isH1DisplayWaveEntryLimitEnabled = false;
        this.elliotAll.isCurrencyStrengthEntryFilterEnabled = false;
        this.elliotAll.isSendMail = false;
        this.elliotAll.timerSeconds = 30;
        this.elliotAll.setOscillatorHandlePool(this.handlePool);
        LoggerRepeatScope logScope;
        Logger::beginTesterRepeatScope(this.marketContext.symbolName, barTime, logScope);
        this.elliotAll.analyze();
        Logger::endTesterRepeatScope(logScope, this.elliotAll.isAnalysisSucceeded);

        if (barTime != iTime(this.marketContext.symbolName, PERIOD_H1, 0)) {
            this.lastError = "ANALYSIS_BAR_CHANGED";

            return false;
        }

        H1EaStrategyDecision decision;
        this.isPrepared = decision.prepare(this.elliotAll, barTime, fromSnapshot);
        this.lastError = "";

        if (!this.isPrepared) {
            this.lastError = fromSnapshot.reasonCode;
        }

        return this.isPrepared;
    }

    /**
     * 直前の分析に保存済み回数を適用し、既存戦略を1回だけ実行する。
     *
     * @param fromPreviousCount このキーの保存済み回数。
     * @param fromSnapshot analyzeが返したスナップショット。
     * @return Judgeを評価できた場合true。
     */
    bool evaluate(const int fromPreviousCount, H1EaStrategySnapshot &fromSnapshot) {
        if (!this.isPrepared) {
            this.lastError = "ANALYSIS_NOT_PREPARED";

            return false;
        }

        this.isPrepared = false;
        H1EaStrategyDecision decision;
        bool isSucceeded = decision.evaluate(
            this.elliotAll, fromPreviousCount, fromSnapshot
        );
        this.lastError = "";

        if (!isSucceeded) {
            this.lastError = fromSnapshot.reasonCode;
        }

        return isSucceeded;
    }

    /**
     * 最新H1 Waveを返す。次の分析まで有効な非所有参照。
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
    }

private:
    /** 分析対象。 */
    MarketContext marketContext;
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
     * 共通履歴準備へ委譲し、既存の時間足別診断を更新する。
     */
    bool isHistoryReady(const datetime fromWarmupEndTime) {
        bool ready = this.historyPreparation.prepare(fromWarmupEndTime);
        this.historyStatusText = this.historyPreparation.getStatusText();
        return ready;
    }
};

#endif
