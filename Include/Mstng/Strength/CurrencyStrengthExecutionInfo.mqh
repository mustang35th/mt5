//+------------------------------------------------------------------+
//|                                CurrencyStrengthExecutionInfo.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_EXECUTION_INFO_MQH
#define MSTNG_CURRENCY_STRENGTH_EXECUTION_INFO_MQH

#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthRankInfo.mqh>

/**
 * 実行時通貨強弱情報の取得状態。
 */
enum ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS {
    /** 取得処理に失敗した。 */
    CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR = -1,

    /** まだ取得していない。 */
    CURRENCY_STRENGTH_EXECUTION_STATUS_NOT_QUERIED = 0,

    /** 対象年のデータベースファイルが存在しない。 */
    CURRENCY_STRENGTH_EXECUTION_STATUS_DATABASE_NOT_FOUND = 1,

    /** データベースは存在するが対象レコードが存在しない。 */
    CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND = 2,

    /** 対象レコードを取得した。 */
    CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND = 3
};

/**
 * 1回の分析・売買判定で参照する通貨強弱順位を保持する。
 */
struct CurrencyStrengthExecutionInfo {
    /** 取得状態。 */
    ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS status;

    /** 検索対象となるM5バー開始時刻。 */
    datetime targetM5BarTime;

    /** 検索対象となるM5バー開始時刻表示文字列。 */
    string targetM5BarTimeText;

    /** 集計ルール識別子。 */
    string calculationVersion;

    /** 取得した順位の集計実行モード。 */
    string sourceMode;

    /** 取得元データベースファイル名。 */
    string sourceFileName;

    /** 通貨ペア順位検索結果。 */
    CurrencyStrengthPairRankInfo pairRankInfo;

    /** 同一集計に含まれる全通貨の順位。 */
    CurrencyStrengthRankInfo currencyRankInfos[8];

    /** 全通貨順位の格納件数。 */
    int currencyRankCount;

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.status = CURRENCY_STRENGTH_EXECUTION_STATUS_NOT_QUERIED;
        this.targetM5BarTime = 0;
        this.targetM5BarTimeText = "";
        this.calculationVersion = "";
        this.sourceMode = "";
        this.sourceFileName = "";
        this.pairRankInfo.reset();
        this.currencyRankCount = 0;

        for (int i = 0; i < 8; i++) {
            this.currencyRankInfos[i].reset();
        }
    }

    /**
     * 同一集計の全8通貨順位を保持しているか判定する。
     *
     * @return 8通貨すべての順位が有効な場合true。
     */
    bool hasAllCurrencyRanks() const {
        if (this.currencyRankCount != 8) {
            return false;
        }

        bool isBaseCurrencyFound = false;
        bool isQuoteCurrencyFound = false;

        for (int i = 0; i < this.currencyRankCount; i++) {
            if (!this.currencyRankInfos[i].isValid()) {
                return false;
            }

            if (this.currencyRankInfos[i].currencyName
                    == this.pairRankInfo.baseCurrency) {
                if (this.currencyRankInfos[i].longMediumTermAverageRank
                            != this.pairRankInfo
                                .baseLongMediumTermAverageRank
                        || this.currencyRankInfos[i]
                                .mediumShortTermAverageRank
                            != this.pairRankInfo
                                .baseMediumShortTermAverageRank) {
                    return false;
                }

                isBaseCurrencyFound = true;
            }

            if (this.currencyRankInfos[i].currencyName
                    == this.pairRankInfo.quoteCurrency) {
                if (this.currencyRankInfos[i].longMediumTermAverageRank
                            != this.pairRankInfo
                                .quoteLongMediumTermAverageRank
                        || this.currencyRankInfos[i]
                                .mediumShortTermAverageRank
                            != this.pairRankInfo
                                .quoteMediumShortTermAverageRank) {
                    return false;
                }

                isQuoteCurrencyFound = true;
            }

            for (int j = i + 1; j < this.currencyRankCount; j++) {
                if (this.currencyRankInfos[i].currencyName
                        == this.currencyRankInfos[j].currencyName) {
                    return false;
                }
            }
        }

        return isBaseCurrencyFound && isQuoteCurrencyFound;
    }

    /**
     * 通貨名と4種類の順位が売買判定に使用可能か判定する。
     *
     * @return 通貨名が設定済みで、全順位が1～8の場合true。
     */
    bool hasValidRanks() const {
        if (this.pairRankInfo.baseCurrency == ""
                || this.pairRankInfo.quoteCurrency == "") {
            return false;
        }

        if (this.pairRankInfo.baseLongMediumTermAverageRank < 1
                || this.pairRankInfo.baseLongMediumTermAverageRank > 8
                || this.pairRankInfo.baseMediumShortTermAverageRank < 1
                || this.pairRankInfo.baseMediumShortTermAverageRank > 8
                || this.pairRankInfo.quoteLongMediumTermAverageRank < 1
                || this.pairRankInfo.quoteLongMediumTermAverageRank > 8
                || this.pairRankInfo.quoteMediumShortTermAverageRank < 1
                || this.pairRankInfo.quoteMediumShortTermAverageRank > 8) {
            return false;
        }

        return true;
    }

    /**
     * 通貨強弱順位を取得済みか判定する。
     *
     * @return 取得済みの場合true。
     */
    bool isAvailable() const {
        return this.status == CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND
            && this.hasValidRanks();
    }

    /**
     * 検索対象と取得レコードのM5バー時刻が一致するか判定する。
     *
     * @return 取得済みかつM5バー時刻が一致する場合true。
     */
    bool isExactM5Bar() const {
        return this.isAvailable()
            && this.pairRankInfo.m5BarTime == this.targetM5BarTime;
    }

    /**
     * 長中期平均順位の通貨ペア差を取得する。
     *
     * @return 決済通貨順位から基軸通貨順位を引いた値。未取得の場合0。
     */
    int getLongMediumRankDifference() const {
        if (!this.isAvailable()) {
            return 0;
        }

        return this.pairRankInfo.quoteLongMediumTermAverageRank
            - this.pairRankInfo.baseLongMediumTermAverageRank;
    }

    /**
     * 中短期平均順位の通貨ペア差を取得する。
     *
     * @return 決済通貨順位から基軸通貨順位を引いた値。未取得の場合0。
     */
    int getMediumShortRankDifference() const {
        if (!this.isAvailable()) {
            return 0;
        }

        return this.pairRankInfo.quoteMediumShortTermAverageRank
            - this.pairRankInfo.baseMediumShortTermAverageRank;
    }

    /**
     * 長中期と中短期の順位方向が売買方向と一致するか判定する。
     *
     * @param fromIsBuy 買い方向の場合true。
     * @return 両方の順位差が売買方向と一致する場合true。
     */
    bool isDirectionAligned(const bool fromIsBuy) const {
        if (!this.isAvailable()) {
            return false;
        }

        int longMediumDifference = this.getLongMediumRankDifference();
        int mediumShortDifference = this.getMediumShortRankDifference();

        if (fromIsBuy) {
            return longMediumDifference > 0 && mediumShortDifference > 0;
        }

        return longMediumDifference < 0 && mediumShortDifference < 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_EXECUTION_INFO_MQH
