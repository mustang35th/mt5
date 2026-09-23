#ifndef MSTNGH1EA_RUNTIME_RESTORATIONSTATE_MQH
#define MSTNGH1EA_RUNTIME_RESTORATIONSTATE_MQH

#include <Mstng\Database\Entity\H1EaRunEntity.mqh>
#include <Mstng\Database\Entity\H1EaTradeEntity.mqh>

/**
 * 通貨別DB復元の読取専用スナップショット。broker照合完了・売買許可とは別の状態。
 */
struct H1EaRestorationState {
    /** 今回の通貨別Run。 */
    H1EaRunEntity run;
    /** 最後に確認した取引。保留SLも含み、保護接続後はbroker照合結果を反映する。 */
    H1EaTradeEntity trade;
    /** DBへの接続と保存状態の復元が完了したか。 */
    bool databaseReady;
    /** 外部巡回による保護処理が接続済みか。現在の送信可否とは別。 */
    bool protectionEnabled;
    /** 外部巡回によるEntry評価が接続済みか。発注の成立とは別。 */
    bool entryEnabled;
    /** SignalCountの読取が完了したか。 */
    bool countsRestored;
    /** 取引の有無の読取が完了したか。 */
    bool tradeRestored;
    /** DBに未完了取引があるか。broker側の保有有無とは別。 */
    bool hasActiveTrade;
    /** 判定済みかどうかDB照会を完了したH1バー。未取得は0。 */
    datetime decisionBar;
    /** 同一バー反転禁止の復元値。 */
    datetime blockedEntryBar;
    /** DB_RESTORED・WAIT_H1・WAIT_DB・LEASE_LOST等。 */
    string status;
    /** 復元待機または失敗の理由。 */
    string reason;

    /**
     * 未復元状態で初期化する。
     */
    H1EaRestorationState() {
        this.reset();
    }

    /**
     * 呼出元に古い情報を返さないよう初期化する。
     */
    void reset() {
        this.run.reset();
        this.trade.reset();
        this.databaseReady = false;
        this.protectionEnabled = false;
        this.entryEnabled = false;
        this.countsRestored = false;
        this.tradeRestored = false;
        this.hasActiveTrade = false;
        this.decisionBar = 0;
        this.blockedEntryBar = 0;
        this.status = "UNREGISTERED";
        this.reason = "";
    }
};

#endif
