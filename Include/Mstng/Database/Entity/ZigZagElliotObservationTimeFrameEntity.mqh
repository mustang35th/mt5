//+------------------------------------------------------------------+
//|           ZigZagElliotObservationTimeFrameEntity.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_OBSERVATION_TF_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_OBSERVATION_TF_ENTITY_MQH

/**
 * ZigZagElliot観測の時間足別分析スナップショット。
 *
 * DAOが保存する論理列順にフィールドを定義する。
 */
struct ZigZagElliotObservationTimeFrameEntity {
    /** 時間足別分析ID。 */
    long id;

    /** 観測ID。 */
    long observationId;

    /** 分析時間足。 */
    int timeFrame;

    /** 分析時間足表示文字列。 */
    string timeFrameText;

    /** 上位足からの表示順。0が最上位足。 */
    int timeFrameOrder;

    /** 観測基準時間足の場合1。 */
    int isAnchorTimeFrame;

    /** Elliott分析方向がBUYの場合1。 */
    int isBuy;

    /** Elliott分析方向表示文字列。 */
    string buySellLabel;

    /** 保持するWave数。 */
    int waveCount;

    /** 最新Waveの一覧内インデックス。 */
    int latestWaveIndex;

    /** 最新Waveが確定済みの場合1。 */
    int isWaveConfirmed;

    /** 最新Waveが推進波の場合1、修正波の場合0。 */
    int isWaveMotive;

    /** 最新Waveが上昇方向の場合1、下降方向の場合0。 */
    int isWaveUptrend;

    /** 最新Wave方向表示文字列。 */
    string waveTrendLabel;

    /** 1つ前のWaveの最終Elliottラベル。 */
    string previousLastElliotLabel;

    /** 最新Waveのポイント数。 */
    int pointCount;

    /** 最新ポイントのElliott番号。 */
    int latestElliotIndex;

    /** 最新ポイントのElliottラベル。 */
    string latestElliotLabel;

    /** 最新ポイントの下位波動番号。 */
    int latestSubElliotIndex;

    /** 最新ポイントの下位波動ラベル。 */
    string latestSubElliotLabel;

    /** 最新ポイントのバー時刻。 */
    datetime latestPointTime;

    /** 最新ポイントのバー時刻表示文字列。 */
    string latestPointTimeText;

    /** 最新ポイントのバー日本時刻。 */
    datetime latestPointJstTime;

    /** 最新ポイントのバー日本時刻表示文字列。 */
    string latestPointJstTimeText;

    /** 最新ポイントの価格。 */
    double latestPointRate;

    /** 1本前の確定足始値。 */
    double previousOpen;

    /** 1本前の確定足高値。 */
    double previousHigh;

    /** 1本前の確定足安値。 */
    double previousLow;

    /** 1本前の確定足終値。 */
    double previousClose;

    /** 現在足始値。 */
    double currentOpen;

    /** 現在足高値。 */
    double currentHigh;

    /** 現在足安値。 */
    double currentLow;

    /** 現在足終値。 */
    double currentClose;

    /** フィボナッチエクスパンション価格が利用可能な場合1。 */
    int isFiboExpansionAvailable;

    /** FE61.8%価格。 */
    double fe618Price;

    /** FE100.0%価格。 */
    double fe1000Price;

    /** FE127.2%価格。 */
    double fe1272Price;

    /** FE161.8%価格。 */
    double fe1618Price;

    /** FE200.0%価格。 */
    double fe2000Price;

    /** 現在価格からFE200.0%までの距離pips。 */
    double distanceToFe2000Pips;

    /** オシレーター総合判定値。 */
    int oscillatorCount;

    /** オシレーター方向がBUYの場合1。 */
    int isOscillatorBuy;

    /** 3本ストキャスMain値の並び順コード。 */
    int stochasticMainOrder;

    /** 3本ストキャスMain値の並び順表示文字列。 */
    string stochasticMainOrderText;

    /** 3本ストキャスMain値の方向表示文字列。 */
    string stochasticMainDirectionText;

    /** 短期ストキャスクロス継続数。 */
    int stochasticShortCount;

    /** 短期ストキャスMain最新値。 */
    double stochasticShortMain;

    /** 短期ストキャスSignal最新値。 */
    double stochasticShortSignal;

    /** 中期ストキャスクロス継続数。 */
    int stochasticMiddleCount;

    /** 中期ストキャスMain最新値。 */
    double stochasticMiddleMain;

    /** 中期ストキャスSignal最新値。 */
    double stochasticMiddleSignal;

    /** 長期ストキャスクロス継続数。 */
    int stochasticLongCount;

    /** 長期ストキャスMain最新値。 */
    double stochasticLongMain;

    /** 長期ストキャスSignal最新値。 */
    double stochasticLongSignal;

    /** GMMAトレンド継続数。 */
    int gmmaTrendCount;

    /** GMMAクロス継続数。 */
    int gmmaCrossCount;

    /** EMA30現在値。 */
    double ema30;

    /** EMA60現在値。 */
    double ema60;

    /** EMA30とEMA60の距離pips。 */
    double ema30Ema60DiffPips;

    /** ATR14 pips。 */
    double atr14Pips;

    /** EMA200判定の確定足終値。 */
    double ema200Close1;

    /** EMA200[1]。 */
    double ema200Shift1;

    /** EMA200比較値。 */
    double ema200Compare;

    /** EMA200傾きpips。 */
    double ema200SlopePips;

    /** Close1とEMA200[1]の距離pips。 */
    double ema200CloseDiffPips;

    /** Close1とEMA200[1]の位置関係コード。 */
    int ema200ClosePosition;

    /** EMA200傾き方向コード。 */
    int ema200SlopeDirection;

    /** EMA200上昇回数。 */
    int ema200UpCount;

    /** EMA200下降回数。 */
    int ema200DownCount;

    /** EMA200トレンド継続数。 */
    int ema200TrendCount;

    /** EMA200がBUY方向の場合1。 */
    int isEma200Buy;

    /** EMA200がSELL方向の場合1。 */
    int isEma200Sell;

    /** レコード作成時刻。 */
    datetime createdAt;

    /** レコード作成時刻表示文字列。 */
    string createdAtText;
};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_OBSERVATION_TF_ENTITY_MQH
