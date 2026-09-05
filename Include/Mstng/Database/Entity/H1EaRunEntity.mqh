#ifndef MSTNG_DATABASE_ENTITY_H1_EA_RUN_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_H1_EA_RUN_ENTITY_MQH

/**
 * H1 EA Runの保存スナップショット。
 * 任意文字列は空文字、任意正値は0、数量・損益はEMPTY_VALUEをNULLとして扱う。
 */
struct H1EaRunEntity {
    /** 主キー。 */
    long id;
    /** 起動ごとの一意ID。 */
    string runUid;
    /** 保存契約バージョン。 */
    int schemaVersion;
    /** LIVEまたはTESTER。 */
    string sourceMode;
    /** LIVEまたはTesterの実行コンテキストキー。 */
    string contextKey;
    /** 接続サーバー。 */
    string accountServer;
    /** 口座番号。 */
    long accountLogin;
    /** brokerシンボル名。 */
    string symbolName;
    /** PERIOD_H1。 */
    int timeFrame;
    /** Magic Number。 */
    string magicNumber;
    /** EAバージョン。 */
    string programVersion;
    /** エントリーおよびポジション管理ロジック世代。 */
    string strategyVersion;
    /** 分析計算世代。 */
    string analysisVersion;
    /** 分析結果へ影響する設定のCanonical Text。 */
    string analysisInputText;
    /** analysis_input_textのSHA-256。 */
    string analysisInputHash;
    /** 有効設定のCanonical Text。 */
    string configText;
    /** config_textのSHA-256。 */
    string configHash;
    /** TimeLocal()による起動時刻。 */
    long startedAt;
    /** TimeLocal()による終了時刻。 */
    long endedAt;
    /** 最終Lease更新時刻。 */
    long heartbeatAt;
    /** Lease失効時刻。 */
    long leaseExpiresAt;
    /** Run状態。 */
    string status;
    /** 終了または異常理由。通常は空文字。 */
    string errorText;

    /**
     * 未取得値と有効な0を区別して初期化する。
     */
    H1EaRunEntity() {
        this.reset();
    }

    /**
     * 保存前の未取得状態へ戻す。
     */
    void reset() {
        this.id = 0;
        this.runUid = "";
        this.schemaVersion = 1;
        this.sourceMode = "";
        this.contextKey = "";
        this.accountServer = "";
        this.accountLogin = 0;
        this.symbolName = "";
        this.timeFrame = PERIOD_H1;
        this.magicNumber = "";
        this.programVersion = "";
        this.strategyVersion = "";
        this.analysisVersion = "";
        this.analysisInputText = "";
        this.analysisInputHash = "";
        this.configText = "";
        this.configHash = "";
        this.startedAt = 0;
        this.endedAt = 0;
        this.heartbeatAt = 0;
        this.leaseExpiresAt = 0;
        this.status = "";
        this.errorText = "";
    }
};

#endif
