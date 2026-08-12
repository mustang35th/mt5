//+------------------------------------------------------------------+
//|                                 ZigZagElliotAlertPointEntity.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_POINT_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_POINT_ENTITY_MQH

/**
 * ZigZagElliotアラートの最新Waveを構成するポイントレコード。
 *
 * timeFrameは親時間足IDを割り当てるための論理項目でありDBへ保存しない。
 */
struct ZigZagElliotAlertPointEntity {
    /** ポイントID。 */
    long id;

    /** 時間足別分析ID。 */
    long alertTimeFrameId;

    /** 親時間足ID割り当て用の論理時間足。DBへは保存しない。 */
    int timeFrame;

    /** 最新Wave内のポイント順。0が最古。 */
    int pointOrder;

    /** 最新ポイントの場合1。 */
    int isLatest;

    /** シグナル基準ポイントの場合1。 */
    int isSignalReference;

    /** ポイント価格。 */
    double rate;

    /** 保存時点のバーインデックス。 */
    int barIndex;

    /** ポイントのバー開始時刻。 */
    datetime barTime;

    /** ポイントのバー開始時刻表示文字列。 */
    string barTimeText;

    /** 次のバー開始時刻を利用できる場合1。 */
    int isBarTimeNextAvailable;

    /** 次のバー開始時刻。利用できない場合は0。 */
    datetime barTimeNext;

    /** 次のバー開始時刻表示文字列。 */
    string barTimeNextText;

    /** 波動開始からの経過本数。 */
    int waveBarsFromStart;

    /** ZigZagの山の場合1、谷の場合0。 */
    int isPeak;

    /** 補完ポイントの場合1。 */
    int isAddedPoint;

    /** 前回ポイントとの価格差pips。 */
    double pipsDiff;

    /** フィボナッチ・リトレースメントが利用可能な場合1。 */
    int isFibonacciAvailable;

    /** フィボナッチ・リトレースメント%。 */
    double fibonacciPercent;

    /** フィボナッチ深度ゾーンコード。 */
    int fiboDepthZone;

    /** フィボナッチ深度ゾーン表示文字列。 */
    string fiboDepthZoneLabel;

    /** フィボナッチ・エクスパンションが利用可能な場合1。 */
    int isFibonacciExpansionAvailable;

    /** フィボナッチ・エクスパンション%。 */
    double fibonacciExpansionPercent;

    /** Elliottラベルがアルファベットの場合1。 */
    int isElliotAlphabet;

    /** Elliott波動番号。 */
    int elliotIndex;

    /** Elliott波動ラベル。 */
    string elliotLabel;

    /** 下位波動情報を利用できる場合1。 */
    int isSubElliotAvailable;

    /** 下位波動番号。 */
    int subElliotIndex;

    /** 下位波動ラベル。 */
    string subElliotLabel;

    /** 再分析前の波動情報を利用できる場合1。 */
    int isOriginalElliotAvailable;

    /** 再分析前のElliott波動番号。 */
    int orgElliotIndex;

    /** 再分析前のElliott波動ラベル。 */
    string orgElliotLabel;

    /** 補正済みポイントの場合1。 */
    int isCorrect;

    /** レコード作成時刻。 */
    datetime createdAt;

    /** レコード作成時刻表示文字列。 */
    string createdAtText;
};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_POINT_ENTITY_MQH
