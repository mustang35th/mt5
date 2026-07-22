//+------------------------------------------------------------------+
//|                         CurrencyStrengthAllRankPoint.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_ALL_RANK_POINT_MQH
#define MSTNG_CURRENCY_STRENGTH_ALL_RANK_POINT_MQH

#include <Mstng\Constant\ConstantCurrency.mqh>

/**
 * 全8通貨の通貨強弱順位を時系列の1点として保持する。
 *
 * DAOのSELECT列順にフィールドを定義する。
 */
struct CurrencyStrengthAllRankPoint {
    /** 集計ID。 */
    long runId;

    /** 集計基準となるM5バー時刻。 */
    datetime m5BarTime;

    /** 集計レコード更新時刻。 */
    datetime updatedAt;

    /** 集計実行モード。 */
    string sourceMode;

    /** USDの長中期平均スコア順位。 */
    int usdLongMediumTermAverageRank;

    /** USDの中短期平均スコア順位。 */
    int usdMediumShortTermAverageRank;

    /** JPYの長中期平均スコア順位。 */
    int jpyLongMediumTermAverageRank;

    /** JPYの中短期平均スコア順位。 */
    int jpyMediumShortTermAverageRank;

    /** EURの長中期平均スコア順位。 */
    int eurLongMediumTermAverageRank;

    /** EURの中短期平均スコア順位。 */
    int eurMediumShortTermAverageRank;

    /** GBPの長中期平均スコア順位。 */
    int gbpLongMediumTermAverageRank;

    /** GBPの中短期平均スコア順位。 */
    int gbpMediumShortTermAverageRank;

    /** AUDの長中期平均スコア順位。 */
    int audLongMediumTermAverageRank;

    /** AUDの中短期平均スコア順位。 */
    int audMediumShortTermAverageRank;

    /** NZDの長中期平均スコア順位。 */
    int nzdLongMediumTermAverageRank;

    /** NZDの中短期平均スコア順位。 */
    int nzdMediumShortTermAverageRank;

    /** CADの長中期平均スコア順位。 */
    int cadLongMediumTermAverageRank;

    /** CADの中短期平均スコア順位。 */
    int cadMediumShortTermAverageRank;

    /** CHFの長中期平均スコア順位。 */
    int chfLongMediumTermAverageRank;

    /** CHFの中短期平均スコア順位。 */
    int chfMediumShortTermAverageRank;

    /**
     * 全フィールドが順位履歴として使用可能か判定する。
     *
     * @return 集計情報が設定済みで、全順位が1～8の場合true。
     */
    bool isValid() const {
        if (this.runId <= 0
                || this.m5BarTime <= 0
                || this.sourceMode == "") {
            return false;
        }

        return this.isValidRank(this.usdLongMediumTermAverageRank)
            && this.isValidRank(this.usdMediumShortTermAverageRank)
            && this.isValidRank(this.jpyLongMediumTermAverageRank)
            && this.isValidRank(this.jpyMediumShortTermAverageRank)
            && this.isValidRank(this.eurLongMediumTermAverageRank)
            && this.isValidRank(this.eurMediumShortTermAverageRank)
            && this.isValidRank(this.gbpLongMediumTermAverageRank)
            && this.isValidRank(this.gbpMediumShortTermAverageRank)
            && this.isValidRank(this.audLongMediumTermAverageRank)
            && this.isValidRank(this.audMediumShortTermAverageRank)
            && this.isValidRank(this.nzdLongMediumTermAverageRank)
            && this.isValidRank(this.nzdMediumShortTermAverageRank)
            && this.isValidRank(this.cadLongMediumTermAverageRank)
            && this.isValidRank(this.cadMediumShortTermAverageRank)
            && this.isValidRank(this.chfLongMediumTermAverageRank)
            && this.isValidRank(this.chfMediumShortTermAverageRank);
    }

    /**
     * 指定通貨の長中期平均スコア順位を取得する。
     *
     * @param fromCurrencyName 通貨コード。
     * @return 順位。対象外の通貨の場合は0。
     */
    int getLongMediumRank(const string fromCurrencyName) const {
        if (fromCurrencyName == ConstantCurrency::USD) {
            return this.usdLongMediumTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::JPY) {
            return this.jpyLongMediumTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::EUR) {
            return this.eurLongMediumTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::GBP) {
            return this.gbpLongMediumTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::AUD) {
            return this.audLongMediumTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::NZD) {
            return this.nzdLongMediumTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::CAD) {
            return this.cadLongMediumTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::CHF) {
            return this.chfLongMediumTermAverageRank;
        }

        return 0;
    }

    /**
     * 指定通貨の中短期平均スコア順位を取得する。
     *
     * @param fromCurrencyName 通貨コード。
     * @return 順位。対象外の通貨の場合は0。
     */
    int getMediumShortRank(const string fromCurrencyName) const {
        if (fromCurrencyName == ConstantCurrency::USD) {
            return this.usdMediumShortTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::JPY) {
            return this.jpyMediumShortTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::EUR) {
            return this.eurMediumShortTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::GBP) {
            return this.gbpMediumShortTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::AUD) {
            return this.audMediumShortTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::NZD) {
            return this.nzdMediumShortTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::CAD) {
            return this.cadMediumShortTermAverageRank;
        }

        if (fromCurrencyName == ConstantCurrency::CHF) {
            return this.chfMediumShortTermAverageRank;
        }

        return 0;
    }

    /**
     * 指定された順位履歴点と全フィールドが同じか判定する。
     *
     * @param fromPoint 比較対象。
     * @return 全フィールドが同じ場合true。
     */
    bool isSame(const CurrencyStrengthAllRankPoint &fromPoint) const {
        return this.runId == fromPoint.runId
            && this.m5BarTime == fromPoint.m5BarTime
            && this.updatedAt == fromPoint.updatedAt
            && this.sourceMode == fromPoint.sourceMode
            && this.usdLongMediumTermAverageRank
                == fromPoint.usdLongMediumTermAverageRank
            && this.usdMediumShortTermAverageRank
                == fromPoint.usdMediumShortTermAverageRank
            && this.jpyLongMediumTermAverageRank
                == fromPoint.jpyLongMediumTermAverageRank
            && this.jpyMediumShortTermAverageRank
                == fromPoint.jpyMediumShortTermAverageRank
            && this.eurLongMediumTermAverageRank
                == fromPoint.eurLongMediumTermAverageRank
            && this.eurMediumShortTermAverageRank
                == fromPoint.eurMediumShortTermAverageRank
            && this.gbpLongMediumTermAverageRank
                == fromPoint.gbpLongMediumTermAverageRank
            && this.gbpMediumShortTermAverageRank
                == fromPoint.gbpMediumShortTermAverageRank
            && this.audLongMediumTermAverageRank
                == fromPoint.audLongMediumTermAverageRank
            && this.audMediumShortTermAverageRank
                == fromPoint.audMediumShortTermAverageRank
            && this.nzdLongMediumTermAverageRank
                == fromPoint.nzdLongMediumTermAverageRank
            && this.nzdMediumShortTermAverageRank
                == fromPoint.nzdMediumShortTermAverageRank
            && this.cadLongMediumTermAverageRank
                == fromPoint.cadLongMediumTermAverageRank
            && this.cadMediumShortTermAverageRank
                == fromPoint.cadMediumShortTermAverageRank
            && this.chfLongMediumTermAverageRank
                == fromPoint.chfLongMediumTermAverageRank
            && this.chfMediumShortTermAverageRank
                == fromPoint.chfMediumShortTermAverageRank;
    }

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.runId = 0;
        this.m5BarTime = 0;
        this.updatedAt = 0;
        this.sourceMode = "";
        this.usdLongMediumTermAverageRank = 0;
        this.usdMediumShortTermAverageRank = 0;
        this.jpyLongMediumTermAverageRank = 0;
        this.jpyMediumShortTermAverageRank = 0;
        this.eurLongMediumTermAverageRank = 0;
        this.eurMediumShortTermAverageRank = 0;
        this.gbpLongMediumTermAverageRank = 0;
        this.gbpMediumShortTermAverageRank = 0;
        this.audLongMediumTermAverageRank = 0;
        this.audMediumShortTermAverageRank = 0;
        this.nzdLongMediumTermAverageRank = 0;
        this.nzdMediumShortTermAverageRank = 0;
        this.cadLongMediumTermAverageRank = 0;
        this.cadMediumShortTermAverageRank = 0;
        this.chfLongMediumTermAverageRank = 0;
        this.chfMediumShortTermAverageRank = 0;
    }

private:
    /**
     * 順位が使用可能な範囲か判定する。
     *
     * @param fromRank 順位。
     * @return 1～8の場合true。
     */
    bool isValidRank(const int fromRank) const {
        return fromRank >= 1 && fromRank <= 8;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ALL_RANK_POINT_MQH
