//+------------------------------------------------------------------+
//|                                      D1ElliotEmaSortDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_D1_ELLIOT_EMA_SORT_DECISION_MQH
#define MSTNG_ELLIOT_D1_ELLIOT_EMA_SORT_DECISION_MQH

#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * D1条件の一致ランク。
 */
enum D1ConditionSortRank {
    d1ConditionSortRankNg = 0,
    d1ConditionSortRankB = 1,
    d1ConditionSortRankA = 2,
    d1ConditionSortRankS = 3
};

/**
 * D1 Elliott・EMA200方向ソート判定結果。
 */
class D1ElliotEmaSortResult {
public:
    /** 判定に必要な分析結果が揃っている場合true。 */
    bool isEvaluated;
    /** D1に対するW1・MN1・W1 EMA200の一致ランク。 */
    D1ConditionSortRank d1ConditionRank;
    /** D1最新Waveの方向一致ランク。 */
    int d1WaveDirectionRank;
    /** D1 EMA200の方向一致ランク。 */
    int d1EmaDirectionRank;
    /** W1最新Waveの方向一致ランク。 */
    int w1WaveDirectionRank;
    /** W1 EMA200の方向一致ランク。 */
    int w1EmaDirectionRank;
    /** MN1最新Waveの方向一致ランク。 */
    int mn1WaveDirectionRank;

    /**
     * 未判定状態で初期化する。
     */
    D1ElliotEmaSortResult() {
        this.reset();
    }

    /**
     * 全フィールドを未判定状態へ戻す。
     */
    void reset() {
        this.isEvaluated = false;
        this.d1ConditionRank = d1ConditionSortRankNg;
        this.d1WaveDirectionRank = 0;
        this.d1EmaDirectionRank = 0;
        this.w1WaveDirectionRank = 0;
        this.w1EmaDirectionRank = 0;
        this.mn1WaveDirectionRank = 0;
    }
};

/**
 * D1一覧専用のElliott最新Wave方向とEMA200方向を判定するクラス。
 *
 * W1を必須条件、MN1とW1 EMA200を加点条件としてD1条件を評価する。
 * 同一条件ランク内ではD1、W1、MN1のWaveとEMA200を辞書順で比較する。
 */
class D1ElliotEmaSortDecision {
public:
    /**
     * D1 Elliott・EMA200方向ソート結果を生成する。
     *
     * @param fromElliotAll 複数時間足のElliott分析結果。
     * @param fromResult 判定結果の格納先。
     */
    void evaluate(
        ElliotAll *fromElliotAll,
        D1ElliotEmaSortResult &fromResult
    ) {
        fromResult.reset();

        if (fromElliotAll == NULL
                || !fromElliotAll.isAnalysisSucceeded) {
            return;
        }

        Elliot *elliotD1 = fromElliotAll.getElliot(PERIOD_D1);
        Elliot *elliotW1 = fromElliotAll.getElliot(PERIOD_W1);
        Elliot *elliotMN1 = fromElliotAll.getElliot(PERIOD_MN1);

        if (elliotD1 == NULL
                || elliotW1 == NULL
                || elliotMN1 == NULL) {
            return;
        }

        if (elliotD1.getLatestWave() == NULL
                || elliotW1.getLatestWave() == NULL
                || elliotMN1.getLatestWave() == NULL) {
            return;
        }

        bool isBuy = elliotD1.isBuy;

        fromResult.d1ConditionRank =
            D1ElliotEmaSortDecision::evaluateConditionRank(
                isBuy,
                elliotW1.isBuy,
                elliotMN1.isBuy,
                elliotW1.oscillator.ema200.isBuy,
                elliotW1.oscillator.ema200.isSell
            );
        fromResult.d1WaveDirectionRank =
            this.getWaveDirectionRank(elliotD1, isBuy);
        fromResult.d1EmaDirectionRank =
            this.getEmaDirectionRank(elliotD1, isBuy);
        fromResult.w1WaveDirectionRank =
            this.getWaveDirectionRank(elliotW1, isBuy);
        fromResult.w1EmaDirectionRank =
            this.getEmaDirectionRank(elliotW1, isBuy);
        fromResult.mn1WaveDirectionRank =
            this.getWaveDirectionRank(elliotMN1, isBuy);
        fromResult.isEvaluated = true;
    }

    /**
     * D1に対する上位足条件の一致ランクを判定する。
     *
     * W1一致を必須とし、MN1とW1 EMA200の一致数でS・A・Bを分ける。
     * EMA200がNONEまたはBUY・SELL競合の場合は一致として扱わない。
     *
     * @param fromIsD1Buy D1がBUY方向の場合true。
     * @param fromIsW1Buy W1がBUY方向の場合true。
     * @param fromIsMn1Buy MN1がBUY方向の場合true。
     * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true。
     * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true。
     * @return D1条件の一致ランク。
     */
    static D1ConditionSortRank evaluateConditionRank(
        bool fromIsD1Buy,
        bool fromIsW1Buy,
        bool fromIsMn1Buy,
        bool fromIsW1Ema200Buy,
        bool fromIsW1Ema200Sell
    ) {
        if (fromIsW1Buy != fromIsD1Buy) {
            return d1ConditionSortRankNg;
        }

        bool isMn1Matched = fromIsMn1Buy == fromIsD1Buy;
        bool isW1EmaMatched = false;

        if (fromIsW1Ema200Buy != fromIsW1Ema200Sell) {
            if (fromIsD1Buy && fromIsW1Ema200Buy) {
                isW1EmaMatched = true;
            } else if (!fromIsD1Buy && fromIsW1Ema200Sell) {
                isW1EmaMatched = true;
            }
        }

        if (isMn1Matched && isW1EmaMatched) {
            return d1ConditionSortRankS;
        }

        if (isMn1Matched || isW1EmaMatched) {
            return d1ConditionSortRankA;
        }

        return d1ConditionSortRankB;
    }

    /**
     * 2つのD1 Elliott・EMA200方向ソート結果を比較する。
     *
     * @param fromLeftResult 左側の判定結果。
     * @param fromRightResult 右側の判定結果。
     * @return 左側を前にする場合-1、同順位の場合0、右側を前にする場合1。
     */
    int compare(
        D1ElliotEmaSortResult &fromLeftResult,
        D1ElliotEmaSortResult &fromRightResult
    ) {
        if (fromLeftResult.isEvaluated != fromRightResult.isEvaluated) {
            if (fromLeftResult.isEvaluated) {
                return -1;
            }

            return 1;
        }

        int compareResult = this.compareRank(
            (int)fromLeftResult.d1ConditionRank,
            (int)fromRightResult.d1ConditionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.d1WaveDirectionRank,
            fromRightResult.d1WaveDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.d1EmaDirectionRank,
            fromRightResult.d1EmaDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.w1WaveDirectionRank,
            fromRightResult.w1WaveDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.w1EmaDirectionRank,
            fromRightResult.w1EmaDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        return this.compareRank(
            fromLeftResult.mn1WaveDirectionRank,
            fromRightResult.mn1WaveDirectionRank
        );
    }

private:
    /**
     * 最新Waveが売買方向と一致するかランク化する。
     *
     * @param fromElliot 判定対象のElliot。
     * @param fromIsBuy BUY方向の場合true。
     * @return 一致する場合2、不一致の場合0。
     */
    int getWaveDirectionRank(Elliot *fromElliot, bool fromIsBuy) {
        if (fromElliot == NULL) {
            return 0;
        }

        Wave *latestWave = fromElliot.getLatestWave();

        if (latestWave == NULL) {
            return 0;
        }

        if (latestWave.isUptrend == fromIsBuy) {
            return 2;
        }

        return 0;
    }

    /**
     * EMA200が売買方向と一致するかランク化する。
     *
     * @param fromElliot 判定対象のElliot。
     * @param fromIsBuy BUY方向の場合true。
     * @return 一致する場合2、NONEの場合1、反対方向の場合0。
     */
    int getEmaDirectionRank(Elliot *fromElliot, bool fromIsBuy) {
        if (fromElliot == NULL) {
            return 0;
        }

        string emaDirection =
            fromElliot.oscillator.ema200.getBuySellLabel();

        if (emaDirection == "NONE") {
            return 1;
        }

        if (fromIsBuy && emaDirection == "BUY") {
            return 2;
        }

        if (!fromIsBuy && emaDirection == "SELL") {
            return 2;
        }

        return 0;
    }

    /**
     * ランクを降順で比較する。
     *
     * @param fromLeftRank 左側ランク。
     * @param fromRightRank 右側ランク。
     * @return 左側を前にする場合-1、同順位の場合0、右側を前にする場合1。
     */
    int compareRank(int fromLeftRank, int fromRightRank) {
        if (fromLeftRank > fromRightRank) {
            return -1;
        }

        if (fromLeftRank < fromRightRank) {
            return 1;
        }

        return 0;
    }
};

#endif // MSTNG_ELLIOT_D1_ELLIOT_EMA_SORT_DECISION_MQH
