#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_PROGRESS_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_PROGRESS_MQH

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSymbolState.mqh>

/**
 * 保持済みの通貨状態から、共通のM1枠に対する確認進捗を集計する。
 * 価格履歴の取得やエントリー分析を追加せず、描画に必要な状態だけを保持する。
 */
class ZigZagElliotMonitorProgress {
public:
    /** 集計対象のサーバーM1枠。 */
    datetime targetBarTime;

    /** 確認中の正規通貨名。実処理中でなければ空文字。 */
    string activeSymbol;

    /** 最後に確認処理を終えた正規通貨名。 */
    string lastSymbol;

    /** 最後の確認処理に要したミリ秒。未計測は-1。 */
    double lastDurationMs;

    /** 有効な監視対象数。 */
    int totalCount;

    /** 対象M1枠の判定完了数。条件未達も含む。 */
    int completedCount;

    /** 対象M1枠で確認を試み、データなどを待っている数。 */
    int waitingCount;

    /** 対象M1枠の確認でエラーになった数。 */
    int errorCount;

    /** 対象M1枠でまだ確認を試みていない数。 */
    int uncheckedCount;

    /** 現在確認中の数。完了・待機・未確認と重複しない。 */
    int checkingCount;

    /** 対象M1枠の判定で成立した数。 */
    int entryCount;

    /**
     * 未確認状態で作成する。
     */
    ZigZagElliotMonitorProgress() {
        this.reset();
    }

    /**
     * 再初期化・監視再開時の表示状態を準備する。
     */
    void reset() {
        this.targetBarTime = 0;
        this.activeSymbol = "";
        this.lastSymbol = "";
        this.lastDurationMs = -1.0;
        this.clearCounts();
    }

    /**
     * 最後に受信したサーバー時刻から、全通貨共通の表示対象M1枠を求める。
     *
     * @return サーバー時刻が未取得なら0。
     */
    static datetime getCurrentBarTime() {
        datetime currentTime = TimeCurrent();
        if (currentTime <= 0) {
            return 0;
        }

        return (datetime)((long)currentTime - (long)currentTime % 60);
    }

    /**
     * 取得済みの状態だけで現在足の進捗を更新する。
     * 履歴未取得や旧足の同期待ちは、実際に確認した共通M1枠で待機に分類する。
     *
     * @param fromStates 全監視対象。画面外の通貨も集計する。
     * @param fromTargetBarTime 集計対象のサーバーM1枠。
     */
    void updateCounts(CArrayObj &fromStates, const datetime fromTargetBarTime) {
        this.targetBarTime = fromTargetBarTime;
        this.clearCounts();
        for (int i = 0; i < fromStates.Total(); i++) {
            ZigZagElliotMonitorSymbolState *state = fromStates.At(i);
            if (state == NULL) {
                continue;
            }

            this.totalCount++;
            if (this.activeSymbol != "" && state.canonicalSymbolName == this.activeSymbol) {
                this.checkingCount++;
            } else if (fromTargetBarTime > 0 && state.lastProcessedBarTime == fromTargetBarTime) {
                this.completedCount++;
                if (state.result.barTime == fromTargetBarTime && state.result.status == ZIGZAG_MONITOR_ENTRY) {
                    this.entryCount++;
                }
            } else if (fromTargetBarTime > 0 && state.lastAttemptBarTime == fromTargetBarTime) {
                if (state.result.status == ZIGZAG_MONITOR_ERROR) {
                    this.errorCount++;
                } else {
                    this.waitingCount++;
                }
            } else {
                this.uncheckedCount++;
            }
        }
    }

private:
    /**
     * 現在通貨と処理時間を保持したまま、集計値だけを初期化する。
     */
    void clearCounts() {
        this.totalCount = 0;
        this.completedCount = 0;
        this.waitingCount = 0;
        this.errorCount = 0;
        this.uncheckedCount = 0;
        this.checkingCount = 0;
        this.entryCount = 0;
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_PROGRESS_MQH
