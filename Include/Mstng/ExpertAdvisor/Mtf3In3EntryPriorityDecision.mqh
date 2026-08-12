//+------------------------------------------------------------------+
//|                                 Mtf3In3EntryPriorityDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_ENTRY_PRIORITY_DECISION_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_ENTRY_PRIORITY_DECISION_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorEma200.mqh>

/**
 * MTF_3in3のエントリー優先度。
 */
enum Mtf3In3EntryPriorityRank {
    /** 全条件を満たす。 */
    mtf3In3EntryPriorityReady = 0,

    /** 副条件が1つだけ未達。 */
    mtf3In3EntryPriorityNear = 1,

    /** 対象波動は揃うが副条件が2つ以上未達。 */
    mtf3In3EntryPrioritySetup = 2,

    /** 対象時間足の対象波動が未完成。 */
    mtf3In3EntryPriorityAlign = 3,

    /** 判定に必要な分析結果が不足。 */
    mtf3In3EntryPriorityError = 4
};

/**
 * MTF_3in3のエントリー優先度判定結果。
 */
class Mtf3In3EntryPriorityResult {
public:
    /** エントリー優先度。 */
    Mtf3In3EntryPriorityRank rank;

    /** 1波または3波に一致した時間足数。 */
    int waveMatchCount;

    /** 一致した副条件数。 */
    int conditionMatchCount;

    /**
     * 未判定状態で初期化する。
     */
    Mtf3In3EntryPriorityResult() {
        this.reset();
    }

    /**
     * 全フィールドを未判定状態へ戻す。
     */
    void reset() {
        this.rank = mtf3In3EntryPriorityError;
        this.waveMatchCount = 0;
        this.conditionMatchCount = 0;
    }
};

/**
 * MTF_3in3の判定条件から副作用なしで表示用優先度を決定するクラス。
 */
class Mtf3In3EntryPriorityDecision {
public:
    /**
     * 現在足と上位2時間足の分析結果から優先度を判定する。
     *
     * @param fromElliotAll 複数時間足のElliott分析結果。
     * @param fromCurrentTimeFrame 判定基準の現在時間足。
     * @param fromResult 判定結果の格納先。
     */
    void evaluate(
        ElliotAll *fromElliotAll,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        Mtf3In3EntryPriorityResult &fromResult
    ) {
        fromResult.reset();

        if (fromElliotAll == NULL) {
            return;
        }

        if (!fromElliotAll.isAnalysisSucceeded) {
            return;
        }

        Elliot *elliotCurrent = fromElliotAll.getElliot(
            fromCurrentTimeFrame
        );
        Elliot *elliotHigher1 = fromElliotAll.getElliot(
            fromCurrentTimeFrame,
            1
        );
        Elliot *elliotHigher2 = fromElliotAll.getElliot(
            fromCurrentTimeFrame,
            2
        );

        if (elliotCurrent == NULL
                || elliotHigher1 == NULL
                || elliotHigher2 == NULL) {
            return;
        }

        ZigZagPoint *latestPointCurrent = elliotCurrent.getLatestPoint();
        ZigZagPoint *latestPointHigher1 = elliotHigher1.getLatestPoint();
        ZigZagPoint *latestPointHigher2 = elliotHigher2.getLatestPoint();
        bool isH1 = fromCurrentTimeFrame == PERIOD_H1;

        if (latestPointCurrent == NULL
                || (!isH1 && latestPointHigher1 == NULL)) {
            return;
        }

        int requiredWaveMatchCount = 3;

        if (isH1) {
            requiredWaveMatchCount = 1;
        } else {
            if (latestPointHigher2 == NULL) {
                return;
            }

            if (this.isEntryWave(latestPointHigher2)) {
                fromResult.waveMatchCount++;
            }
        }

        if (!isH1 && this.isEntryWave(latestPointHigher1)) {
            fromResult.waveMatchCount++;
        }

        if (this.isEntryWave(latestPointCurrent)) {
            fromResult.waveMatchCount++;
        }

        if (fromResult.waveMatchCount < requiredWaveMatchCount) {
            fromResult.rank = mtf3In3EntryPriorityAlign;
            return;
        }

        bool isBuy = elliotCurrent.isBuy;
        ExpertAdvisorEma200 expertAdvisorEma200(isBuy);

        if (this.isWaveDirectionMatched(elliotCurrent, isBuy)) {
            fromResult.conditionMatchCount++;
        }

        if (isH1 || !latestPointCurrent.isAddedPoint) {
            fromResult.conditionMatchCount++;
        }

        if (this.isDirectionCountMatched(
            elliotCurrent.oscillator.gmmaTrendCount,
            isBuy
        )) {
            fromResult.conditionMatchCount++;
        }

        if (this.isDirectionCountMatched(
            elliotCurrent.oscillator.gmmaCrossCount,
            isBuy
        )) {
            fromResult.conditionMatchCount++;
        }

        if (expertAdvisorEma200.isEma200BuySell(elliotCurrent)) {
            fromResult.conditionMatchCount++;
        }

        if (isH1
                || expertAdvisorEma200.isEma200BuySellOrNone(
                    elliotHigher2
                )) {
            fromResult.conditionMatchCount++;
        }

        if (isH1
                || expertAdvisorEma200.isEma200BuySell(
                    elliotHigher1
                )) {
            fromResult.conditionMatchCount++;
        }

        if (this.isM5Elliot3FibonacciExpansionWithin(
            elliotCurrent,
            latestPointCurrent
        )) {
            fromResult.conditionMatchCount++;
        }

        if (isH1 || this.isEma200DistanceWithin(elliotCurrent)) {
            fromResult.conditionMatchCount++;
        }

        if (fromResult.conditionMatchCount
                == Mtf3In3EntryPriorityDecision::requiredConditionCount) {
            fromResult.rank = mtf3In3EntryPriorityReady;
            return;
        }

        if (fromResult.conditionMatchCount
                == Mtf3In3EntryPriorityDecision::requiredConditionCount - 1) {
            fromResult.rank = mtf3In3EntryPriorityNear;
            return;
        }

        fromResult.rank = mtf3In3EntryPrioritySetup;
    }

private:
    /** READYに必要な副条件数。 */
    static const int requiredConditionCount;

    /** M5第3波のフィボナッチエクスパンション許容上限%。 */
    static const double maxM5Elliot3FibonacciExpansionPercent;

    /** Close1とEMA200[1]のエントリー許容距離pips。 */
    static const double maxCloseEma200DiffPips;

    /**
     * 現在足の売買方向と最新Wave方向が一致するか判定する。
     *
     * @param fromElliotCurrent 現在時間足のElliot。
     * @param fromIsBuy BUY方向の場合true。
     * @return 売買方向と最新Wave方向が一致する場合true。
     */
    bool isWaveDirectionMatched(
        Elliot *fromElliotCurrent,
        bool fromIsBuy
    ) {
        if (fromElliotCurrent == NULL) {
            return false;
        }

        Wave *latestWave = fromElliotCurrent.getLatestWave();

        if (latestWave == NULL) {
            return false;
        }

        return latestWave.isUptrend == fromIsBuy;
    }

    /**
     * 最新ポイントが第1波または第3波か判定する。
     *
     * @param fromLatestPoint 判定対象の最新ポイント。
     * @return 第1波または第3波の場合true。
     */
    bool isEntryWave(ZigZagPoint *fromLatestPoint) {
        if (fromLatestPoint == NULL) {
            return false;
        }

        if (fromLatestPoint.elliotLabel == "1"
                || fromLatestPoint.elliotLabel == "3") {
            return true;
        }

        return false;
    }

    /**
     * GMMAカウントが売買方向と一致するか判定する。
     *
     * @param fromCount GMMAカウント。
     * @param fromIsBuy BUY方向の場合true。
     * @return BUYは2以上、SELLは-2以下の場合true。
     */
    bool isDirectionCountMatched(int fromCount, bool fromIsBuy) {
        if (fromIsBuy) {
            if (fromCount > 1) {
                return true;
            }

            return false;
        }

        if (fromCount < -1) {
            return true;
        }

        return false;
    }

    /**
     * M5第3波のフィボナッチエクスパンション上限を確認する。
     *
     * @param fromElliotCurrent 現在時間足のElliot。
     * @param fromLatestPoint 現在時間足の最新ポイント。
     * @return M5第3波以外、またはFEが161.8%以下の場合true。
     */
    bool isM5Elliot3FibonacciExpansionWithin(
        Elliot *fromElliotCurrent,
        ZigZagPoint *fromLatestPoint
    ) {
        if (fromElliotCurrent == NULL || fromLatestPoint == NULL) {
            return false;
        }

        if (fromElliotCurrent.marketContext.timeFrame != PERIOD_M5) {
            return true;
        }

        if (fromLatestPoint.elliotLabel != "3") {
            return true;
        }

        double fibonacciExpansionPercent =
            fromLatestPoint.fibonacciExpansionPercent;

        if (!MathIsValidNumber(fibonacciExpansionPercent)
                || fibonacciExpansionPercent == EMPTY_VALUE
                || fibonacciExpansionPercent <= 0.0) {
            return false;
        }

        fibonacciExpansionPercent = NormalizeDouble(
            fibonacciExpansionPercent,
            1
        );

        if (fibonacciExpansionPercent
                <= Mtf3In3EntryPriorityDecision::maxM5Elliot3FibonacciExpansionPercent) {
            return true;
        }

        return false;
    }

    /**
     * Close1とEMA200[1]の距離が25pips以下か判定する。
     *
     * @param fromElliotCurrent 現在時間足のElliot。
     * @return 絶対距離が25pips以下の場合true。
     */
    bool isEma200DistanceWithin(Elliot *fromElliotCurrent) {
        if (fromElliotCurrent == NULL) {
            return false;
        }

        double closeEma200DiffPips = MathAbs(
            fromElliotCurrent.oscillator.ema200.closeEma200DiffPips
        );

        if (closeEma200DiffPips
                <= Mtf3In3EntryPriorityDecision::maxCloseEma200DiffPips) {
            return true;
        }

        return false;
    }
};

const int Mtf3In3EntryPriorityDecision::requiredConditionCount = 9;
const double Mtf3In3EntryPriorityDecision::maxM5Elliot3FibonacciExpansionPercent = 161.8;
const double Mtf3In3EntryPriorityDecision::maxCloseEma200DiffPips = 25.0;

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_ENTRY_PRIORITY_DECISION_MQH
