//+------------------------------------------------------------------+
//|                         ZigZagElliotH1StudyObservation.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_OBSERVATION_MQH
#define MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_OBSERVATION_MQH

/**
 * H1推移研究の取得元となるObservation Run。
 *
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct ZigZagElliotH1StudySourceRunInfo {
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

    /** Elliott分析設定ハッシュ。 */
    string analysisInputHash;

    /** 実行時入力設定ハッシュ。 */
    string inputHash;

    /** 取引サーバー名。 */
    string sourceServer;

    /** 口座ログイン番号。 */
    long sourceLogin;

    /** テスター開始時刻。 */
    datetime testerFrom;

    /** テスター終了時刻。 */
    datetime testerTo;

    /** テスターモデル識別子。 */
    string testerModel;

    /** Run実行状態。旧DBではLEGACY。 */
    string status;

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
        this.analysisInputHash = "";
        this.inputHash = "";
        this.sourceServer = "";
        this.sourceLogin = 0;
        this.testerFrom = 0;
        this.testerTo = 0;
        this.testerModel = "";
        this.status = "";
    }
};

/**
 * FULL Alignment Episodeを分離するObservation Streamキー。
 */
struct ZigZagElliotH1StudyStreamKey {
    /** Run ID。 */
    long runId;

    /** 実行モード。 */
    string sourceMode;

    /** 取引サーバー名。 */
    string sourceServer;

    /** 通貨ペア名。 */
    string symbolName;

    /** 観測基準時間足。 */
    int anchorTimeFrame;

    /** 観測タイミング種別。 */
    string capturePhase;

    /** Elliott分析バージョン。 */
    string analysisVersion;

    /** Elliott分析設定ハッシュ。 */
    string analysisInputHash;

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.runId = 0;
        this.sourceMode = "";
        this.sourceServer = "";
        this.symbolName = "";
        this.anchorTimeFrame = 0;
        this.capturePhase = "";
        this.analysisVersion = "";
        this.analysisInputHash = "";
    }
};

/**
 * H1推移研究でEpisode判定と将来成績計算に使用するObservation行。
 *
 * 不完全な親Observationも保持できるよう、子行の有無と判定値を分離する。
 * DatabaseReadBindで読み込む列順にフィールドを定義する。
 */
struct ZigZagElliotH1StudyObservationRow {
    /** Observation ID。 */
    long observationId;

    /** Run ID。 */
    long runId;

    /** 実行モード。 */
    string sourceMode;

    /** 取引サーバー名。 */
    string sourceServer;

    /** 通貨ペア名。 */
    string symbolName;

    /** 観測基準時間足。 */
    int anchorTimeFrame;

    /** 観測基準時間足表示文字列。 */
    string anchorTimeFrameText;

    /** 観測タイミング種別。 */
    string capturePhase;

    /** Elliott分析バージョン。 */
    string analysisVersion;

    /** Elliott分析設定ハッシュ。 */
    string analysisInputHash;

    /** H1バー開始の取引サーバー時刻。 */
    datetime anchorBarTime;

    /** H1バー開始の取引サーバー時刻表示文字列。 */
    string anchorBarTimeText;

    /** H1バー開始のJST。 */
    datetime anchorJstTime;

    /** H1バー開始のJST表示文字列。 */
    string anchorJstTimeText;

    /** スプレッドが取得元DBに保存されている場合1。 */
    int isSpreadAvailable;

    /** 観測時点のスプレッドpips。未記録の場合0。 */
    double spreadPips;

    /** 1pip相当の価格幅。 */
    double pipSize;

    /** pipSizeの取得元。SOURCE_DBまたはSYMBOL_RULE_V1。 */
    string pipSizeSource;

    /** Observation内容ハッシュ。 */
    string snapshotHash;

    /** 親に記録された時間足数。 */
    int timeFrameCount;

    /** W1、D1、H4およびH1子行がすべて存在する場合1。 */
    int isRequiredTimeFramesComplete;

    /** W1子行が存在する場合1。 */
    int isW1Available;

    /** W1分析方向。BUYは1、SELLは0、欠損は-1。 */
    int w1IsBuy;

    /** D1子行が存在する場合1。 */
    int isD1Available;

    /** D1分析方向。BUYは1、SELLは0、欠損は-1。 */
    int d1IsBuy;

    /** H4子行が存在する場合1。 */
    int isH4Available;

    /** H4分析方向。BUYは1、SELLは0、欠損は-1。 */
    int h4IsBuy;

    /** H4 EMA200がBUY方向の場合1。欠損は-1。 */
    int h4IsEma200Buy;

    /** H4 EMA200がSELL方向の場合1。欠損は-1。 */
    int h4IsEma200Sell;

    /** H1子行が存在する場合1。 */
    int isH1Available;

    /** H1分析方向。BUYは1、SELLは0、欠損は-1。 */
    int h1IsBuy;

    /** H1 EMA200がBUY方向の場合1。欠損は-1。 */
    int h1IsEma200Buy;

    /** H1 EMA200がSELL方向の場合1。欠損は-1。 */
    int h1IsEma200Sell;

    /** H1現在足始値。H1子行欠損時は0。 */
    double currentOpen;

    /** H1の1本前の確定足始値。H1子行欠損時は0。 */
    double previousOpen;

    /** H1の1本前の確定足高値。H1子行欠損時は0。 */
    double previousHigh;

    /** H1の1本前の確定足安値。H1子行欠損時は0。 */
    double previousLow;

    /** H1の1本前の確定足終値。H1子行欠損時は0。 */
    double previousClose;

    /** H1 ATR14が正の有限値として保存されている場合1。 */
    int isAtr14Available;

    /** H1 ATR14 pips。利用不可の場合0。 */
    double atr14Pips;

    /** 完全一致方向。BUY、SELLまたは空文字。 */
    string fullAlignmentSide;

    /**
     * 全フィールドを未取得状態へ初期化する。
     */
    void reset() {
        this.observationId = 0;
        this.runId = 0;
        this.sourceMode = "";
        this.sourceServer = "";
        this.symbolName = "";
        this.anchorTimeFrame = 0;
        this.anchorTimeFrameText = "";
        this.capturePhase = "";
        this.analysisVersion = "";
        this.analysisInputHash = "";
        this.anchorBarTime = 0;
        this.anchorBarTimeText = "";
        this.anchorJstTime = 0;
        this.anchorJstTimeText = "";
        this.isSpreadAvailable = 0;
        this.spreadPips = 0.0;
        this.pipSize = 0.0;
        this.pipSizeSource = "";
        this.snapshotHash = "";
        this.timeFrameCount = 0;
        this.isRequiredTimeFramesComplete = 0;
        this.isW1Available = 0;
        this.w1IsBuy = -1;
        this.isD1Available = 0;
        this.d1IsBuy = -1;
        this.isH4Available = 0;
        this.h4IsBuy = -1;
        this.h4IsEma200Buy = -1;
        this.h4IsEma200Sell = -1;
        this.isH1Available = 0;
        this.h1IsBuy = -1;
        this.h1IsEma200Buy = -1;
        this.h1IsEma200Sell = -1;
        this.currentOpen = 0.0;
        this.previousOpen = 0.0;
        this.previousHigh = 0.0;
        this.previousLow = 0.0;
        this.previousClose = 0.0;
        this.isAtr14Available = 0;
        this.atr14Pips = 0.0;
        this.fullAlignmentSide = "";
    }
};

#endif // MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_OBSERVATION_MQH
