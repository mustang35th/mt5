//+------------------------------------------------------------------+
//|                              M15ElliotEmaSortDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_M15_ELLIOT_EMA_SORT_DECISION_MQH
#define MSTNG_ELLIOT_M15_ELLIOT_EMA_SORT_DECISION_MQH

#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * M15 Elliott・EMA200方向ソート判定結果。
 */
class M15ElliotEmaSortResult {
public:
    /** 判定に必要な分析結果が揃っている場合true。 */
    bool isEvaluated;
    /** M15最新Waveの方向一致ランク。 */
    int m15WaveDirectionRank;
    /** M15 EMA200の方向一致ランク。 */
    int m15EmaDirectionRank;
    /** H1最新Waveの方向一致ランク。 */
    int h1WaveDirectionRank;
    /** H1 EMA200の方向一致ランク。 */
    int h1EmaDirectionRank;
    /** H4最新Waveの方向一致ランク。 */
    int h4WaveDirectionRank;
    /** H4 EMA200の方向一致ランク。 */
    int h4EmaDirectionRank;
    /** D1 EMA200の方向一致ランク。 */
    int d1EmaDirectionRank;

    /**
     * 未判定状態で初期化する。
     */
    M15ElliotEmaSortResult() {
        this.reset();
    }

    /**
     * 全フィールドを未判定状態へ戻す。
     */
    void reset() {
        this.isEvaluated = false;
        this.m15WaveDirectionRank = 0;
        this.m15EmaDirectionRank = 0;
        this.h1WaveDirectionRank = 0;
        this.h1EmaDirectionRank = 0;
        this.h4WaveDirectionRank = 0;
        this.h4EmaDirectionRank = 0;
        this.d1EmaDirectionRank = 0;
    }
};

/**
 * M15一覧専用のElliott最新Wave方向とEMA200方向を判定するクラス。
 *
 * M15、H1、H4、D1の順に現在の売買方向との一致を評価し、
 * 現在足の逆行を上位足の一致で相殺しない辞書順を提供する。
 */
class M15ElliotEmaSortDecision {
public:
    /**
     * M15 Elliott・EMA200方向ソート結果を生成する。
     *
     * @param fromElliotAll 複数時間足のElliott分析結果。
     * @param fromResult 判定結果の格納先。
     */
    void evaluate(
        ElliotAll *fromElliotAll,
        M15ElliotEmaSortResult &fromResult
    ) {
        fromResult.reset();

        if (fromElliotAll == NULL
                || !fromElliotAll.isAnalysisSucceeded) {
            return;
        }

        Elliot *elliotM15 = fromElliotAll.getElliot(PERIOD_M15);
        Elliot *elliotH1 = fromElliotAll.getElliot(PERIOD_H1);
        Elliot *elliotH4 = fromElliotAll.getElliot(PERIOD_H4);
        Elliot *elliotD1 = fromElliotAll.getElliot(PERIOD_D1);

        if (elliotM15 == NULL
                || elliotH1 == NULL
                || elliotH4 == NULL
                || elliotD1 == NULL) {
            return;
        }

        if (elliotM15.getLatestWave() == NULL
                || elliotH1.getLatestWave() == NULL
                || elliotH4.getLatestWave() == NULL) {
            return;
        }

        bool isBuy = elliotM15.isBuy;

        fromResult.m15WaveDirectionRank =
            this.getWaveDirectionRank(elliotM15, isBuy);
        fromResult.m15EmaDirectionRank =
            this.getEmaDirectionRank(elliotM15, isBuy);
        fromResult.h1WaveDirectionRank =
            this.getWaveDirectionRank(elliotH1, isBuy);
        fromResult.h1EmaDirectionRank =
            this.getEmaDirectionRank(elliotH1, isBuy);
        fromResult.h4WaveDirectionRank =
            this.getWaveDirectionRank(elliotH4, isBuy);
        fromResult.h4EmaDirectionRank =
            this.getEmaDirectionRank(elliotH4, isBuy);
        fromResult.d1EmaDirectionRank =
            this.getEmaDirectionRank(elliotD1, isBuy);
        fromResult.isEvaluated = true;
    }

    /**
     * 2つのM15 Elliott・EMA200方向ソート結果を比較する。
     *
     * @param fromLeftResult 左側の判定結果。
     * @param fromRightResult 右側の判定結果。
     * @return 左側を前にする場合-1、同順位の場合0、右側を前にする場合1。
     */
    int compare(
        M15ElliotEmaSortResult &fromLeftResult,
        M15ElliotEmaSortResult &fromRightResult
    ) {
        if (fromLeftResult.isEvaluated != fromRightResult.isEvaluated) {
            if (fromLeftResult.isEvaluated) {
                return -1;
            }

            return 1;
        }

        int compareResult = this.compareRank(
            fromLeftResult.m15WaveDirectionRank,
            fromRightResult.m15WaveDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.m15EmaDirectionRank,
            fromRightResult.m15EmaDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.h1WaveDirectionRank,
            fromRightResult.h1WaveDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.h1EmaDirectionRank,
            fromRightResult.h1EmaDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.h4WaveDirectionRank,
            fromRightResult.h4WaveDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        compareResult = this.compareRank(
            fromLeftResult.h4EmaDirectionRank,
            fromRightResult.h4EmaDirectionRank
        );

        if (compareResult != 0) {
            return compareResult;
        }

        return this.compareRank(
            fromLeftResult.d1EmaDirectionRank,
            fromRightResult.d1EmaDirectionRank
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

#endif // MSTNG_ELLIOT_M15_ELLIOT_EMA_SORT_DECISION_MQH
