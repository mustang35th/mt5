#ifndef MSTNGH1EA_STRATEGY_MQH
#define MSTNGH1EA_STRATEGY_MQH

#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>
#include <MstngH1Ea\Runtime\H1EaClock.mqh>
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
        this.nextHistoryRequestTick = 0;
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
        WarmUpSeriesUtil::warmUpFromMn1To(this.marketContext, 500);
        this.nextHistoryRequestTick = H1EaClock::milliseconds() + 60000;
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
     * @return ハンドルプールと必要な価格系列が準備済みの場合true。
     */
    bool prepareHistory() {
        this.isPrepared = false;

        if (this.handlePool == NULL || !this.isHistoryReady()) {
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
            ZigZagElliotAnalysisProfile::getAnalysisStartTimeFrame()
        );
        this.elliotAll.isMailValidationFileEnabled = false;
        this.elliotAll.isH1DisplayWaveEntryLimitEnabled = false;
        this.elliotAll.isCurrencyStrengthEntryFilterEnabled = false;
        this.elliotAll.isSendMail = false;
        this.elliotAll.timerSeconds = 30;
        this.elliotAll.setOscillatorHandlePool(this.handlePool);
        this.elliotAll.analyze();

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
        this.nextHistoryRequestTick = 0;

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
    /** 不足系列の再取得要求を最短60秒間隔に抑える経過時刻。 */
    ulong nextHistoryRequestTick;

    /**
     * 既存Controllerと同じ系列同期・Testerの履歴本数を確認する。
     * 不足しても残り時間足の診断を収集し、取得再要求だけ間隔を制限する。
     */
    bool isHistoryReady() {
        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1
        };
        bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
        bool isReady = true;
        bool mayRequest = H1EaClock::milliseconds() >= this.nextHistoryRequestTick;
        bool wasRequested = false;
        this.historyStatusText = "";

        for (int i = 0; i < ArraySize(timeFrames); i++) {
            int requestBars = 206;
            if (timeFrames[i] == PERIOD_MN1) {
                requestBars = 61;
            }
            int requiredBars = 0;
            if (isTester) {
                requiredBars = requestBars;
            }
            bool isSynchronized = WarmUpSeriesUtil::isSeriesSynchronized(
                this.marketContext.symbolName, timeFrames[i]
            );
            int availableBars = Bars(this.marketContext.symbolName, timeFrames[i]);
            if ((!isSynchronized || availableBars < requiredBars) && mayRequest) {
                MqlRates requestedRates[];
                // Testerの可視履歴を必ず拡張できるとは扱わず、要求後も再確認する。
                CopyRates(this.marketContext.symbolName, timeFrames[i], 0, requestBars, requestedRates);
                wasRequested = true;
                isSynchronized = WarmUpSeriesUtil::isSeriesSynchronized(
                    this.marketContext.symbolName, timeFrames[i]
                );
                availableBars = Bars(this.marketContext.symbolName, timeFrames[i]);
            }
            bool isTimeFrameReady = isSynchronized && availableBars >= requiredBars;
            if (!isTimeFrameReady) {
                isReady = false;
            }
            long firstDate = 0;
            string firstDateText = "UNAVAILABLE";
            if (SeriesInfoInteger(this.marketContext.symbolName, timeFrames[i], SERIES_FIRSTDATE, firstDate)
                    && firstDate > 0) {
                firstDateText = TimeToString((datetime)firstDate, TIME_DATE | TIME_MINUTES);
            }
            string timeFrameText = EnumToString(timeFrames[i]);
            StringReplace(timeFrameText, "PERIOD_", "");
            string stateText = "WAIT";
            if (isTimeFrameReady) {
                stateText = "READY";
            }
            if (this.historyStatusText != "") {
                this.historyStatusText += ", ";
            }
            this.historyStatusText += StringFormat(
                "%s[%s,sync=%d,bars=%d,required=%d,first=%s]",
                timeFrameText, stateText, (int)isSynchronized, availableBars, requiredBars, firstDateText
            );
        }
        if (wasRequested) {
            this.nextHistoryRequestTick = H1EaClock::milliseconds() + 60000;
        }
        return isReady;
    }
};

#endif
