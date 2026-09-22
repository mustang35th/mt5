#ifndef MSTNGH1EA_RUNTIME_PREPARATIONSTATE_MQH
#define MSTNGH1EA_RUNTIME_PREPARATIONSTATE_MQH

/**
 * 売買開始前の通貨別登録・履歴準備状態。
 * Run・取引状態とは分離し、履歴準備完了だけではEntryを許可しない。
 */
struct H1EaPreparationState {
    /** 固定リストから登録したシンボル名。 */
    string symbolName;
    /** この通貨の登録が完了したか。 */
    bool registered;
    /** この通貨の分析リソースを初期化したか。 */
    bool resourcesInitialized;
    /** 直近の履歴確認が成功したか。指標計算・波動分析の成功とは別。 */
    bool historyReady;
    /** 直近の履歴確認対象H1バー。取得不能時は0。 */
    datetime h1BarTime;
    /** 未登録・登録済み・履歴待ち・準備済み・エラー。 */
    string status;
    /** 直近の未準備・失敗理由。 */
    string reason;

    /**
     * 未登録状態を作る。
     */
    H1EaPreparationState() {
        this.reset();
    }

    /**
     * 保存済み売買状態に触れず、準備状態だけを初期化する。
     */
    void reset() {
        this.symbolName = "";
        this.registered = false;
        this.resourcesInitialized = false;
        this.historyReady = false;
        this.h1BarTime = 0;
        this.status = "UNREGISTERED";
        this.reason = "";
    }
};

#endif
