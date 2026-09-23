#ifndef MSTNGH1EA_RUNTIME_EVENTTIMER_MQH
#define MSTNGH1EA_RUNTIME_EVENTTIMER_MQH

#include <MstngH1Ea\Runtime\H1EaClock.mqh>
#include <MstngH1Ea\Runtime\H1EaOperationLogger.mqh>

/**
 * EAイベントTimerの設定成功状態と再試行間隔を管理する。
 * 通貨別の分析・取引・DB状態は保持しない。Timer終了はEA入口が担当する。
 */
class H1EaEventTimer {
public:
    /**
     * Timer未設定で初期化する。
     */
    H1EaEventTimer() {
        this.timerSeconds = 0;
        this.nextTimerRetryTick = 0;
    }

    /**
     * 通常1秒、高速ウォームアップ30秒へ切り替える。失敗後は最短5秒で再試行する。
     *
     * @param fromFastWarmup 高速ウォームアップを選択する場合true。
     * @param fromLogger 既存の通貨別運用ログ。
     * @param fromResetMaintenance 通常周期への設定試行時true。失敗時も保守待ちを解除する。
     * @return 指定周期のTimer設定に成功済みの場合true。
     */
    bool update(const bool fromFastWarmup, H1EaOperationLogger &fromLogger,
            bool &fromResetMaintenance) {
        fromResetMaintenance = false;
        int requiredSeconds = 1;
        if (fromFastWarmup) {
            requiredSeconds = 30;
        }
        if (this.timerSeconds == requiredSeconds) {
            return true;
        }
        if (H1EaClock::milliseconds() < this.nextTimerRetryTick) {
            return false;
        }
        if (requiredSeconds == 1) {
            // 高速期間の30秒待ちをDB復旧・未保存イベント処理へ持ち込まない。
            fromResetMaintenance = true;
        }
        ResetLastError();
        if (!EventSetTimer(requiredSeconds)) {
            int errorCode = GetLastError();
            this.timerSeconds = 0;
            this.nextTimerRetryTick = H1EaClock::milliseconds() + 5000;
            fromLogger.error("H1EaController.updateEventTimer", "TIMER_UPDATE_FAILED seconds="
                + IntegerToString(requiredSeconds) + " error=" + IntegerToString(errorCode));
            return false;
        }
        this.timerSeconds = requiredSeconds;
        this.nextTimerRetryTick = 0;
        fromLogger.info("H1EaController.updateEventTimer", "TIMER_SECONDS="
            + IntegerToString(this.timerSeconds));
        return true;
    }

    /**
     * 所有元がTimerを終了した後、再起動に備えて設定成功状態を破棄する。
     * OSのTimerは操作しない。
     */
    void reset() {
        this.timerSeconds = 0;
        this.nextTimerRetryTick = 0;
    }

    /**
     * Entryを許可できる通常周期のTimer設定が成功済みか返す。
     */
    bool isNormalReady() const {
        return this.timerSeconds == 1;
    }

private:
    /** 設定成功を確認済みのTimer秒数。0は未設定または更新失敗。 */
    int timerSeconds;
    /** Timer設定失敗時の次回試行時刻。最短5秒で再試行する。 */
    ulong nextTimerRetryTick;
};

#endif
