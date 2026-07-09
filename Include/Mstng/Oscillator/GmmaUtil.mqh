//+------------------------------------------------------------------+
//|                                                     GmmaUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_UTIL_GMMA_UTIL_MQH
#define MSTNG_UTIL_GMMA_UTIL_MQH

/**
 * GMMAトレンド種別。
 */
enum ENUM_GMMA_TREND {
    GMMA_TREND_NON = 0,
    GMMA_TREND_BUY = 1,
    GMMA_TREND_SELL = 2
};

/**
 * GMMAユーティリティクラス。
 */
class GmmaUtil {
public:
    /**
     * GMMA長期線のトレンド方向を取得する。
     *
     * EMA30 と EMA60 の1本前と現在値を比較し、
     * 両方とも上昇している場合は買いトレンド、
     * 両方とも下降している場合は売りトレンドと判定する。
     * 上昇・下降が揃わない場合はトレンドなしとする。
     *
     * @param ema30Before EMA30の1本前の値。
     * @param ema30Current EMA30の現在値。
     * @param ema60Before EMA60の1本前の値。
     * @param ema60Current EMA60の現在値。
     * @return GMMAトレンド。
     */
    static ENUM_GMMA_TREND getGmmaTrend(double ema30Before, double ema30Current,
                                        double ema60Before, double ema60Current) {
        if (ema30Before < ema30Current
                && ema60Before < ema60Current) {
            return GMMA_TREND_BUY;
        }

        if (ema30Before > ema30Current
                && ema60Before > ema60Current) {
            return GMMA_TREND_SELL;
        }

        return GMMA_TREND_NON;
    }
};

#endif