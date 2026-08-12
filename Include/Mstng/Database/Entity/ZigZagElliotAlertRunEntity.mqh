//+------------------------------------------------------------------+
//|                                   ZigZagElliotAlertRunEntity.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_RUN_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_RUN_ENTITY_MQH

/**
 * ZigZagElliotアラート記録を生成した1回の実行を表すデータベースレコード。
 *
 * DAOが保存する論理列順にフィールドを定義する。
 */
struct ZigZagElliotAlertRunEntity {
    /** 実行ID。 */
    long id;

    /** 実行を一意に識別するUID。 */
    string runUid;

    /** データベーススキーマバージョン。 */
    int schemaVersion;

    /** 実行モード。LIVE、TESTERまたはOPTIMIZATION。 */
    string sourceMode;

    /** 呼び出し元識別子。 */
    string source;

    /** 実行プログラム名。 */
    string programName;

    /** 実行プログラムバージョン。 */
    string programVersion;

    /** 戦略名。 */
    string strategy;

    /** 戦略バージョン。 */
    string strategyVersion;

    /** Elliott分析バージョン。 */
    string analysisVersion;

    /** 分析結果へ影響する設定のCanonical Text。Legacy行は空文字。 */
    string analysisInputText;

    /** 分析設定Canonical TextのSHA-256。Legacy行は空文字。 */
    string analysisInputHash;

    /** 取引サーバー名。 */
    string sourceServer;

    /** 口座ログイン番号。 */
    long sourceLogin;

    /** チャートID。 */
    long sourceChartId;

    /** ターミナルビルド番号。 */
    int terminalBuild;

    /** テスター開始時刻。対象外または取得できない場合は0。 */
    datetime testerFrom;

    /** テスター終了時刻。対象外または取得できない場合は0。 */
    datetime testerTo;

    /** テスターモデル識別子。対象外または取得できない場合は空文字。 */
    string testerModel;

    /** 実行時の入力設定文字列。取得できない場合は空文字。 */
    string inputText;

    /** 入力設定を識別するハッシュ。取得できない場合は空文字。 */
    string inputHash;

    /** プログラム実行開始時刻。 */
    datetime startedAt;

    /** プログラム実行開始時刻表示文字列。 */
    string startedAtText;

    /** 実行開始時点の市場時刻。取得できない場合は0。 */
    datetime marketStartedAt;

    /** 実行開始時点の市場時刻表示文字列。 */
    string marketStartedAtText;

    /** レコード作成時刻。 */
    datetime createdAt;

    /** レコード作成時刻表示文字列。 */
    string createdAtText;
};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_RUN_ENTITY_MQH
