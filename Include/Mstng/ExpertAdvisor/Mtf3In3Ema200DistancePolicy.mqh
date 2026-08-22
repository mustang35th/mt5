//+------------------------------------------------------------------+
//|                          Mtf3In3Ema200DistancePolicy.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_EMA200_DISTANCE_POLICY_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_EMA200_DISTANCE_POLICY_MQH

/**
 * MTF_3in3の時間足別EMA200距離上限を管理する。
 */
class Mtf3In3Ema200DistancePolicy {
public:
    /**
     * 時間足に対応するClose1とEMA200[1]の許容距離を取得する。
     *
     * @param fromTimeFrame 判定対象時間足。
     * @return 許容距離pips。
     */
    double getMaxCloseEma200DiffPips(
        ENUM_TIMEFRAMES fromTimeFrame
    ) {
        if (fromTimeFrame == PERIOD_H1) {
            return Mtf3In3Ema200DistancePolicy::maxH1CloseEma200DiffPips;
        }

        return Mtf3In3Ema200DistancePolicy::maxCloseEma200DiffPips;
    }

    /**
     * Close1とEMA200[1]の絶対距離が時間足別上限以内か判定する。
     *
     * @param fromTimeFrame 判定対象時間足。
     * @param fromCloseEma200DiffPips Close1とEMA200[1]の距離pips。
     * @return 絶対距離が上限以内の場合true。
     */
    bool isCloseEma200DiffPipsWithin(
        ENUM_TIMEFRAMES fromTimeFrame,
        double fromCloseEma200DiffPips
    ) {
        if (!MathIsValidNumber(fromCloseEma200DiffPips)
                || fromCloseEma200DiffPips == EMPTY_VALUE) {
            return false;
        }

        double closeEma200DiffPips = MathAbs(fromCloseEma200DiffPips);

        return closeEma200DiffPips
            <= this.getMaxCloseEma200DiffPips(fromTimeFrame);
    }

private:
    /** H1のClose1とEMA200[1]のエントリー許容距離pips。 */
    static const double maxH1CloseEma200DiffPips;

    /** H1以外のClose1とEMA200[1]のエントリー許容距離pips。 */
    static const double maxCloseEma200DiffPips;
};

const double Mtf3In3Ema200DistancePolicy::maxH1CloseEma200DiffPips = 50.0;
const double Mtf3In3Ema200DistancePolicy::maxCloseEma200DiffPips = 25.0;

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_EMA200_DISTANCE_POLICY_MQH
