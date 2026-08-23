//+------------------------------------------------------------------+
//|                           ZigZagElliotEntryCandidate.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_CANDIDATE_MQH
#define MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_CANDIDATE_MQH

/**
 * エントリー候補を生成したZigZagElliot Runのメタデータ。
 *
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct SourceRunInfo {
    /** Run ID。 */
    long runId;

    /** Runを一意に識別するUID。 */
    string runUid;

    /** データベーススキーマバージョン。 */
    int schemaVersion;

    /** 実行モード。 */
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

    /** 取引サーバー名。 */
    string sourceServer;

    /** 口座ログイン番号。 */
    long sourceLogin;

    /** チャートID。 */
    long sourceChartId;

    /** ターミナルビルド番号。 */
    int terminalBuild;

    /** テスター開始時刻。 */
    datetime testerFrom;

    /** テスター終了時刻。 */
    datetime testerTo;

    /** テスターモデル識別子。 */
    string testerModel;

    /** 実行時の入力設定文字列。 */
    string inputText;

    /** 実行時の入力設定ハッシュ。 */
    string inputHash;

    /** プログラム実行開始時刻。 */
    datetime startedAt;

    /** プログラム実行開始時刻表示文字列。 */
    string startedAtText;

    /** 実行開始時点の市場時刻。 */
    datetime marketStartedAt;

    /** 実行開始時点の市場時刻表示文字列。 */
    string marketStartedAtText;

    /** レコード作成時刻。 */
    datetime createdAt;

    /** レコード作成時刻表示文字列。 */
    string createdAtText;

    /** Elliott分析設定のCanonical Text。 */
    string analysisInputText;

    /** Elliott分析設定のハッシュ。 */
    string analysisInputHash;

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.runId = 0;
        this.runUid = "";
        this.schemaVersion = 0;
        this.sourceMode = "";
        this.source = "";
        this.programName = "";
        this.programVersion = "";
        this.strategy = "";
        this.strategyVersion = "";
        this.analysisVersion = "";
        this.sourceServer = "";
        this.sourceLogin = 0;
        this.sourceChartId = 0;
        this.terminalBuild = 0;
        this.testerFrom = 0;
        this.testerTo = 0;
        this.testerModel = "";
        this.inputText = "";
        this.inputHash = "";
        this.startedAt = 0;
        this.startedAtText = "";
        this.marketStartedAt = 0;
        this.marketStartedAtText = "";
        this.createdAt = 0;
        this.createdAtText = "";
        this.analysisInputText = "";
        this.analysisInputHash = "";
    }
};

/**
 * H1エントリー後の値動き検証に使用する候補レコード。
 *
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct EntryCandidate {
    /** アラートID。 */
    long alertId;

    /** Run ID。 */
    long runId;

    /** Run間で同一市場シグナルを照合するキー。 */
    string marketSignalKey;

    /** シグナル判定時のサーバー時刻。 */
    datetime entryTime;

    /** H1バー開始時刻。 */
    datetime currentBarTime;

    /** シンボル名。 */
    string symbolName;

    /** 売買方向。 */
    string side;

    /** シグナル判定時の参照価格。 */
    double entryPrice;

    /** 初期ストップロス価格。 */
    double stopLoss;

    /** 参照価格からストップロスまでの距離pips。 */
    double riskPips;

    /** シグナル判定時のスプレッドpips。 */
    double spreadPips;

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.alertId = 0;
        this.runId = 0;
        this.marketSignalKey = "";
        this.entryTime = 0;
        this.currentBarTime = 0;
        this.symbolName = "";
        this.side = "";
        this.entryPrice = 0.0;
        this.stopLoss = 0.0;
        this.riskPips = 0.0;
        this.spreadPips = 0.0;
    }
};

#endif // MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_CANDIDATE_MQH
