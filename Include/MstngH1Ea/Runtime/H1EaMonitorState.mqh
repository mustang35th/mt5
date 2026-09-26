#ifndef MSTNGH1EA_RUNTIME_MONITORSTATE_MQH
#define MSTNGH1EA_RUNTIME_MONITORSTATE_MQH

/**
 * 通貨別の表示専用コピー。巡回可否と取引の最終確認値を保持し、発注許可には使わない。
 */
struct H1EaMonitorSymbolState {
    /** 登録済み通貨。 */
    string symbolName;
    /** 最後に確認した価格履歴の準備結果。分析・売買許可とは別。 */
    bool historyReady;
    /** WATCH・PREPARING・STOPPEDの排他的な分類。 */
    string category;
    /** 表示する状態コード。 */
    string status;
    /** 停止・準備待ちの理由。 */
    string reason;
    /** 最後に判定を確定したH1。DB照会済みバーとは別。 */
    datetime finalizedBar;
    /** 通貨別Run ID。 */
    long runId;
    /** 最後に確認したLease期限。 */
    datetime leaseExpiresAt;
    /** 取引状態の読取済みフラグ。brokerへの再照会は行わない。 */
    bool tradeKnown;
    /** 発注中・決済中・復旧待ちも含む管理対象取引。 */
    bool activeTrade;
    /** 最後に確認したTrade状態。 */
    string tradeStatus;
    /** 最後に確認した取引方向。 */
    string tradeSide;
    /** 最後に確認した保護SL。 */
    double stopLoss;
    /** 未反映のSL種別。 */
    string pendingStopLossKind;
    /** 未反映のSL候補価格。 */
    double pendingStopLoss;
    /** 価格表示桁数。 */
    int digits;
    /** 直近の取引エラー。 */
    string tradeError;
    /** この起動内の分析回数。失敗も含む。 */
    ulong analysisCount;
    /** 最後の分析実時間（microseconds）。 */
    ulong lastAnalysisMicros;
    /** 最大の分析実時間（microseconds）。 */
    ulong maxAnalysisMicros;
    /** 最後の分析終了時の実時計。 */
    ulong analysisFinishedMicros;

    /**
     * 未取得状態へ戻す。
     */
    void reset() {
        this.symbolName = "";
        this.historyReady = false;
        this.category = "PREPARING";
        this.status = "REGISTERED";
        this.reason = "";
        this.finalizedBar = 0;
        this.runId = 0;
        this.leaseExpiresAt = 0;
        this.tradeKnown = false;
        this.activeTrade = false;
        this.tradeStatus = "";
        this.tradeSide = "";
        this.stopLoss = 0.0;
        this.pendingStopLossKind = "";
        this.pendingStopLoss = 0.0;
        this.digits = 5;
        this.tradeError = "";
        this.analysisCount = 0;
        this.lastAnalysisMicros = 0;
        this.maxAnalysisMicros = 0;
        this.analysisFinishedMicros = 0;
    }
};

/**
 * 全28通貨の画面と定期ログに渡す読取専用の状態。DBや市場を読み直さない。
 */
struct H1EaMonitorState {
    /** 固定リスト順の通貨別状態。 */
    H1EaMonitorSymbolState symbols[28];
    /** 今回の起動グループ。 */
    string sessionUid;
    /** LIVEまたはTESTER。 */
    string sourceMode;
    /** 状態を集計したサーバー時刻。 */
    datetime serverTime;
    /** 売買開始前の期間。 */
    bool beforeTradeStart;
    /** 高速準備中。 */
    bool fastWarmup;
    /** 最後に設定成功したTimer周期。0は失敗・未設定。 */
    int timerSeconds;
    /** 登録通貨数。 */
    int symbolCount;
    /** 必要な価格履歴の準備が完了した通貨数。 */
    int historyReadyCount;
    /** WATCH通貨数。発注条件の成立数ではない。 */
    int watchingCount;
    /** 準備・分析待ち通貨数。 */
    int preparingCount;
    /** 新規停止通貨数。 */
    int stoppedCount;
    /** 管理対象取引数。実保有ポジション数とは異なる。 */
    int activeTradeCount;
    /** 処理を終えたTimer回数。 */
    ulong timerCount;
    /** 最後のTimer処理実時間。描画・定期ログは含めない。 */
    ulong lastTimerMicros;
    /** 最大Timer処理実時間。 */
    ulong maxTimerMicros;
    /** 全通貨の分析回数。 */
    ulong analysisCount;
    /** 全通貨で最後の分析実時間。 */
    ulong lastAnalysisMicros;
    /** 全通貨で最大の分析実時間。 */
    ulong maxAnalysisMicros;
    /** 通常保護巡回の直近開始間隔。Testerではテスト内時刻。 */
    ulong lastProtectionGapMs;
    /** 通常保護巡回の最大開始間隔。意図的な高速準備休止は除外。 */
    ulong maxProtectionGapMs;
    /** このEAが使用するメモリのMB値。 */
    long memoryMb;

    /**
     * 全項目を初期化し、前回の表示値を持ち越さない。
     */
    void reset() {
        for (int i = 0; i < ArraySize(this.symbols); i++) {
            this.symbols[i].reset();
        }
        this.sessionUid = "";
        this.sourceMode = "LIVE";
        this.serverTime = 0;
        this.beforeTradeStart = false;
        this.fastWarmup = false;
        this.timerSeconds = 0;
        this.symbolCount = 0;
        this.historyReadyCount = 0;
        this.watchingCount = 0;
        this.preparingCount = 0;
        this.stoppedCount = 0;
        this.activeTradeCount = 0;
        this.timerCount = 0;
        this.lastTimerMicros = 0;
        this.maxTimerMicros = 0;
        this.analysisCount = 0;
        this.lastAnalysisMicros = 0;
        this.maxAnalysisMicros = 0;
        this.lastProtectionGapMs = 0;
        this.maxProtectionGapMs = 0;
        this.memoryMb = 0;
    }
};

#endif
