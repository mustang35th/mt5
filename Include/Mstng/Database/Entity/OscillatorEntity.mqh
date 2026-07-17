//+------------------------------------------------------------------+
//|                                             OscillatorEntity.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_OSCILLATOR_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_OSCILLATOR_ENTITY_MQH

/**
 * オシレーター計算結果のデータベースレコード。
 *
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct OscillatorEntity {
    /** レコードID。 */
    long id;

    /** 計算時刻。 */
    datetime calculatedAt;

    /** シンボル名。 */
    string symbolName;

    /** 時間足。 */
    int timeFrame;

    /** オシレーター総合判定値。 */
    int oscillatorCount;

    /** BUYフラグ。trueの場合は1、falseの場合は0。 */
    int isBuy;

    /**
     * 全フィールドをログ出力用文字列へ変換する。
     *
     * @return エンティティの文字列表現。
     */
    string toString() const {
        string isBuyText = "false";

        if (this.isBuy == 1) {
            isBuyText = "true";
        }

        return StringFormat(
            "id=%I64d, calculatedAt=%s, symbolName=%s, timeFrame=%s, oscillatorCount=%d, isBuy=%s",
            this.id,
            TimeToString(this.calculatedAt, TIME_DATE | TIME_SECONDS),
            this.symbolName,
            EnumToString((ENUM_TIMEFRAMES)this.timeFrame),
            this.oscillatorCount,
            isBuyText
        );
    }
};

#endif // MSTNG_DATABASE_ENTITY_OSCILLATOR_ENTITY_MQH
