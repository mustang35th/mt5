//+------------------------------------------------------------------+
//|                                  Ema200DistanceMailPolicy.mqh     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_MAIL_EMA200_DISTANCE_MAIL_POLICY_MQH
#define MSTNG_MAIL_EMA200_DISTANCE_MAIL_POLICY_MQH

/**
 * メール件名の注意表示専用に、通貨別EMA200距離上限を判定する。
 * エントリー条件・順位判定・保存済みの参考上限には適用しない。
 */
class Ema200DistanceMailPolicy {
public:
    /**
     * 決済通貨に対応するメール用距離上限を取得する。
     *
     * @param fromQuoteCurrency シンボルの決済通貨。USDJPYを含むJPY建ては50pips。
     * @return 時間足共通の上限pips。その他の通貨は25pips。
     */
    static double getMaxDistancePips(const string fromQuoteCurrency) {
        if (fromQuoteCurrency == "JPY") {
            return 50.0;
        }

        return 25.0;
    }

    /**
     * 丸め前の絶対距離がメール用上限を超えているか判定する。
     *
     * @param fromQuoteCurrency シンボルの決済通貨。未取得の場合は判定しない。
     * @param fromDistancePips 確定足終値とEMA200[1]の符号付き距離pips。
     * @return 有効な距離が上限を超えている場合true。上限と同値はfalse。
     */
    static bool isExceeded(const string fromQuoteCurrency, const double fromDistancePips) {
        if (fromQuoteCurrency == "" || !MathIsValidNumber(fromDistancePips)
                || MathAbs(fromDistancePips) == EMPTY_VALUE) {
            return false;
        }

        return MathAbs(fromDistancePips) > getMaxDistancePips(fromQuoteCurrency);
    }
};

#endif // MSTNG_MAIL_EMA200_DISTANCE_MAIL_POLICY_MQH
