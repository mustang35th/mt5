//+------------------------------------------------------------------+
//|                    ZigZagElliotObservationEntity.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_OBSERVATION_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_OBSERVATION_ENTITY_MQH

/**
 * H1新規足を基準とするZigZagElliot観測スナップショット。
 *
 * DAOが保存する論理列順にフィールドを定義する。
 */
struct ZigZagElliotObservationEntity {
    /** 観測ID。 */
    long id;

    /** 実行情報ID。 */
    long runId;

    /** 実行モード。 */
    string sourceMode;

    /** 取得元サーバー名。 */
    string sourceServer;

    /** 通貨ペア名。 */
    string symbolName;

    /** 観測基準時間足。 */
    int anchorTimeFrame;

    /** 観測基準時間足表示文字列。 */
    string anchorTimeFrameText;

    /** 観測基準バー開始時刻。 */
    datetime anchorBarTime;

    /** 観測基準バー開始時刻表示文字列。 */
    string anchorBarTimeText;

    /** 観測基準バー開始日本時刻。 */
    datetime anchorJstTime;

    /** 観測基準バー開始日本時刻表示文字列。 */
    string anchorJstTimeText;

    /** 観測タイミング種別。 */
    string capturePhase;

    /** Elliott分析バージョン。 */
    string analysisVersion;

    /** Elliott分析設定ハッシュ。 */
    string analysisInputHash;

    /** 観測内容ハッシュ。 */
    string snapshotHash;

    /** 保存する時間足数。 */
    int timeFrameCount;

    /** レコード作成時刻。 */
    datetime createdAt;

    /** レコード作成時刻表示文字列。 */
    string createdAtText;
};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_OBSERVATION_ENTITY_MQH
