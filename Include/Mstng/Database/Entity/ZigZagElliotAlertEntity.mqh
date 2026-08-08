//+------------------------------------------------------------------+
//|                            ZigZagElliotAlertEntity.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_ENTITY_MQH

/**
 * ZigZagElliotアラート本体のデータベースレコード。
 *
 * DAOが保存する論理列順にフィールドを定義する。
 */
struct ZigZagElliotAlertEntity {
    /** アラートID。 */
    long id;

    /** 実行ID。 */
    long runId;

    /** 実行内のイベントUID。 */
    string eventUid;

    /** 実行間で同一市場シグナルを照合するキー。 */
    string marketSignalKey;

    /** アラート内容を識別するスナップショットハッシュ。 */
    string snapshotHash;

    /** 判定時のサーバー時刻。 */
    datetime serverTime;

    /** 判定時のサーバー時刻表示文字列。 */
    string serverTimeText;

    /** 判定時の日本時刻。 */
    datetime jstTime;

    /** 判定時の日本時刻表示文字列。 */
    string jstTimeText;

    /** 現在バー開始時刻。 */
    datetime currentBarTime;

    /** 現在バー開始時刻表示文字列。 */
    string currentBarTimeText;

    /** シグナル基準ポイント時刻。 */
    datetime signalReferencePointTime;

    /** シグナル基準ポイント時刻表示文字列。 */
    string signalReferencePointTimeText;

    /** シンボル名。 */
    string symbolName;

    /** 現在時間足。 */
    int timeFrame;

    /** 現在時間足表示文字列。 */
    string timeFrameText;

    /** マジックナンバー文字列。 */
    string magicNumber;

    /** 戦略名。 */
    string strategy;

    /** 売買方向。BUYまたはSELL。 */
    string side;

    /** 戦略の基本条件判定結果。 */
    int isJudge;

    /** 同一シグナルの発生回数。 */
    int signalCount;

    /** エントリー対象とする発生回数。 */
    int entryCount;

    /** 発生回数がエントリー対象回数と一致する場合1。 */
    int isEntryCountMatch;

    /** エントリー判定を実行した場合1。 */
    int isEntryEvaluated;

    /** アラート対象の場合1。 */
    int isAlert;

    /** エントリー対象の場合1。 */
    int isEntry;

    /** エントリー判定結果コード。 */
    string entryResult;

    /** メール送信対象の場合1。 */
    int isSendMail;

    /** 現在時間足のElliottラベル。 */
    string currentElliotLabel;

    /** 現在時間足がエントリー対象波動の場合1。 */
    int isEntryWave;

    /** Close1とEMA200[1]の距離pips。 */
    double closeEma200DiffPips;

    /** Close1とEMA200[1]の許容距離pips。 */
    double maxCloseEma200DiffPips;

    /** Close1とEMA200[1]の距離が許容範囲内の場合1。 */
    int isEma200DistanceWithin;

    /** 判定時のスプレッドpips。 */
    double spreadPips;

    /** 通貨強弱フィルターが有効な場合1。 */
    int isCurrencyStrengthEnabled;

    /** 通貨強弱取得状態コード。 */
    int currencyStrengthStatus;

    /** 通貨強弱が利用可能な場合1。 */
    int isCurrencyStrengthAvailable;

    /** 通貨強弱計算バージョン。 */
    string currencyStrengthCalculationVersion;

    /** 通貨強弱Run ID。利用できない場合は0。 */
    long currencyStrengthRunId;

    /** 通貨強弱取得元モード。 */
    string currencyStrengthSourceMode;

    /** 通貨強弱の取得対象M5バー時刻。 */
    datetime currencyStrengthTargetM5BarTime;

    /** 実際に取得した通貨強弱M5バー時刻。 */
    datetime currencyStrengthM5BarTime;

    /** 基軸通貨名。 */
    string baseCurrency;

    /** 基軸通貨の長中期順位。 */
    int baseLongMediumRank;

    /** 基軸通貨の中短期順位。 */
    int baseMediumShortRank;

    /** 決済通貨名。 */
    string quoteCurrency;

    /** 決済通貨の長中期順位。 */
    int quoteLongMediumRank;

    /** 決済通貨の中短期順位。 */
    int quoteMediumShortRank;

    /** 長中期順位差。 */
    int longMediumRankDifference;

    /** 中短期順位差。 */
    int mediumShortRankDifference;

    /** 判定時の参照価格。 */
    double referencePrice;

    /** ロスカット価格を利用できる場合1。 */
    int isStopLossAvailable;

    /** ロスカット価格。利用できない場合は0。 */
    double stopLoss;

    /** 参照価格からロスカットまでの距離pips。利用できない場合は0。 */
    double riskPips;

    /** H1波動構造ランクラベル。 */
    string h1StructureRank;

    /** H1波動構造が有効な場合1。 */
    int isH1StructureValid;

    /** H1波動構造が遅い場合1。 */
    int isH1StructureLate;

    /** H1波動構造が方向例外の場合1。 */
    int isH1DirectionException;

    /** アラートタイトル。 */
    string alertTitle;

    /** アラート本文。 */
    string alertText;

    /** 全時間足の波動概要表示文字列。 */
    string waveSummaryText;

    /** 既存CSV形式のElliott分析スナップショット。 */
    string elliotCsvText;

    /** レコード作成時刻。 */
    datetime createdAt;

    /** レコード作成時刻表示文字列。 */
    string createdAtText;
};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_ENTITY_MQH
