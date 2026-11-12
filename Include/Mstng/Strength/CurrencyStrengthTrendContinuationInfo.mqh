//+------------------------------------------------------------------+
//|                         CurrencyStrengthTrendContinuationInfo.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_INFO_MQH
#define MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_INFO_MQH

/**
 * 直近3時間の通貨強弱方向の継続判定を保持する。
 */
struct CurrencyStrengthTrendContinuationInfo {
    /** 判定対象のM5全36枠を有効な順位で評価できた場合true。 */
    bool available;

    /** 判定対象36枠のうち有効な順位を取得できた件数。 */
    int validCount;

    /** 判定対象36枠のうち両期間が現在の候補方向に一致した件数。 */
    int matchedCount;

    /** 現在から両期間の方向一致が途切れず続く秒数。最大3時間。 */
    int consecutiveSeconds;

    /** 評価した履歴にTESTER補完を含む場合true。連続時間の境界も含む。 */
    bool supplemented;

    /** 直近30分とその前30分の全12枠を比較できた場合true。 */
    bool gapAvailable;

    /** 直近6枠の候補方向を正とする中短期順位差平均。 */
    double recentAverageDifference;

    /** その前6枠の候補方向を正とする中短期順位差平均。 */
    double previousAverageDifference;

    /** 順位差平均が0.5以上拡大なら1、0.5以上縮小なら-1、それ以外は0。 */
    int gapChange;

    /**
     * 判定値を未取得状態へ初期化する。
     */
    void reset() {
        this.available = false;
        this.validCount = 0;
        this.matchedCount = 0;
        this.consecutiveSeconds = 0;
        this.supplemented = false;
        this.gapAvailable = false;
        this.recentAverageDifference = 0.0;
        this.previousAverageDifference = 0.0;
        this.gapChange = 0;
    }

    /**
     * 全履歴が揃い、方向一致率80%以上と直近連続30分を満たすか判定する。
     *
     * @return 継続条件を満たす場合true。
     */
    bool isQualified() const {
        return this.available
            && this.matchedCount * 100 >= 36 * 80
            && this.consecutiveSeconds >= 1800;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_INFO_MQH
