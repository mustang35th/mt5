//+------------------------------------------------------------------+
//|                                            UpdateTimingStats.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_COMMON_UPDATE_TIMING_STATS_MQH
#define MSTNG_COMMON_UPDATE_TIMING_STATS_MQH

/**
 * 更新開始の間隔と遅延、正常終了の間隔および最後の実行状態を保持する。
 * 時刻は呼び出し元から受け取り、実行間隔や再試行の制御は行わない。
 */
class UpdateTimingStats {
public:
    /**
     * 計測状態を初期化する。
     */
    UpdateTimingStats() {
        this.reset();
    }

    /**
     * 計測値、実行状態および改訂番号を未計測へ戻す。
     */
    void reset() {
        this.attemptStarted = false;
        this.attemptPending = false;
        this.attemptIntervalMeasured = false;
        this.successRecorded = false;
        this.successIntervalMeasured = false;
        this.lastSucceeded = false;
        this.lastAttemptStartTick = 0;
        this.lastSuccessTick = 0;
        this.attemptIntervalMilliseconds = 0;
        this.successIntervalMilliseconds = 0;
        this.timerDelayMilliseconds = 0;
        this.startDelayMilliseconds = 0;
        this.auxiliaryMilliseconds = 0.0;
        this.lastAttemptMilliseconds = 0.0;
        this.lastState = "未計測";
        this.revision = 0;
        this.attemptRevision = 0;
        this.timerRecorded = false;
        this.timerGapMeasured = false;
        this.lastTimerEndTick = 0;
        this.timerGapMilliseconds = 0;
        this.timerMilliseconds = 0.0;
        this.timerLabelMilliseconds = 0.0;
        this.maximumTimerMilliseconds = 0.0;
        this.maximumTimerLabelMilliseconds = 0.0;
        this.timerAnalysisExecuted = false;
    }

    /**
     * 更新開始を記録し、前回開始からの間隔と予定時刻からの遅延を求める。
     * 初回の間隔と遅延は未計測とし、前回の終了状態と成功履歴は変更しない。
     *
     * @param fromTimerEntryTick タイマー処理へ入った単調増加ミリ秒
     * @param fromAttemptStartTick 更新処理を開始する単調増加ミリ秒
     * @param fromIntervalSeconds 前回開始から待つ設定秒数。負値は0として扱う
     * @param fromAuxiliaryMicroseconds 更新開始前の補助処理の所要マイクロ秒
     */
    void beginAttempt(
        ulong fromTimerEntryTick,
        ulong fromAttemptStartTick,
        int fromIntervalSeconds,
        ulong fromAuxiliaryMicroseconds
    ) {
        this.attemptIntervalMilliseconds = 0;
        this.timerDelayMilliseconds = 0;
        this.startDelayMilliseconds = 0;
        this.attemptIntervalMeasured = this.attemptStarted;

        if (this.attemptStarted) {
            ulong intervalMilliseconds = 0;
            if (fromIntervalSeconds > 0) {
                intervalMilliseconds = (ulong)fromIntervalSeconds * 1000;
            }

            if (fromAttemptStartTick >= this.lastAttemptStartTick) {
                this.attemptIntervalMilliseconds =
                    fromAttemptStartTick - this.lastAttemptStartTick;
            }

            if (fromTimerEntryTick >= this.lastAttemptStartTick) {
                ulong timerElapsedMilliseconds =
                    fromTimerEntryTick - this.lastAttemptStartTick;
                if (timerElapsedMilliseconds > intervalMilliseconds) {
                    this.timerDelayMilliseconds =
                        timerElapsedMilliseconds - intervalMilliseconds;
                }
            }

            if (this.attemptIntervalMilliseconds > intervalMilliseconds) {
                this.startDelayMilliseconds =
                    this.attemptIntervalMilliseconds - intervalMilliseconds;
            }
        }

        this.lastAttemptStartTick = fromAttemptStartTick;
        this.auxiliaryMilliseconds = (double)fromAuxiliaryMicroseconds / 1000.0;
        this.attemptStarted = true;
        this.attemptPending = true;
        this.attemptRevision++;
    }

    /**
     * 更新の所要時間と終了状態を記録する。
     * beginAttemptで開始した更新の終了時に呼び、正常終了時だけ成功履歴を更新する。
     * 未開始または終了記録済みの場合は何もしない。
     *
     * @param fromAttemptEndTick 更新処理を終了した単調増加ミリ秒
     * @param fromElapsedMicroseconds 更新処理の所要マイクロ秒
     * @param fromSucceeded 正常終了した場合true
     * @param fromState 通常更新・準備中・再試行などの実行状態
     */
    void finishAttempt(
        ulong fromAttemptEndTick,
        ulong fromElapsedMicroseconds,
        bool fromSucceeded,
        string fromState
    ) {
        if (!this.attemptPending) {
            return;
        }

        this.lastAttemptMilliseconds = (double)fromElapsedMicroseconds / 1000.0;
        this.lastSucceeded = fromSucceeded;
        this.lastState = fromState;

        if (fromSucceeded) {
            this.successIntervalMeasured = this.successRecorded;
            this.successIntervalMilliseconds = 0;
            if (this.successRecorded && fromAttemptEndTick >= this.lastSuccessTick) {
                this.successIntervalMilliseconds =
                    fromAttemptEndTick - this.lastSuccessTick;
            }

            this.lastSuccessTick = fromAttemptEndTick;
            this.successRecorded = true;
        }

        this.attemptPending = false;
        this.attemptRevision++;
        this.revision++;
    }

    /**
     * 完了したTimer全体とラベル反映の所要時間を保持する。
     * 分析試行の成否・成功時刻は変更せず、待機だけのTimerも記録する。
     *
     * @param fromEntryTick Timer入口の単調増加ミリ秒
     * @param fromEndTick 最後の表示反映後の単調増加ミリ秒
     * @param fromElapsedMicroseconds Timer入口から最後の表示反映までの所要マイクロ秒
     * @param fromLabelMicroseconds 診断ラベルと処理時間ラベルの反映合計マイクロ秒
     * @param fromAnalysisExecuted 分析を試行したTimerの場合true。分析成功とは区別する
     */
    void recordTimer(ulong fromEntryTick, ulong fromEndTick,
            ulong fromElapsedMicroseconds, ulong fromLabelMicroseconds,
            bool fromAnalysisExecuted) {
        this.timerGapMeasured = this.timerRecorded;
        this.timerGapMilliseconds = 0;
        if (this.timerRecorded && fromEntryTick >= this.lastTimerEndTick) {
            this.timerGapMilliseconds = fromEntryTick - this.lastTimerEndTick;
        }

        this.timerMilliseconds = (double)fromElapsedMicroseconds / 1000.0;
        this.timerLabelMilliseconds = (double)fromLabelMicroseconds / 1000.0;
        this.maximumTimerMilliseconds = MathMax(
            this.maximumTimerMilliseconds, this.timerMilliseconds);
        this.maximumTimerLabelMilliseconds = MathMax(
            this.maximumTimerLabelMilliseconds, this.timerLabelMilliseconds);
        this.lastTimerEndTick = fromEndTick;
        this.timerAnalysisExecuted = fromAnalysisExecuted;
        this.timerRecorded = true;
        this.revision++;
    }

    /**
     * 完了したTimerを一度でも記録した場合trueを返す。
     */
    bool hasTimer() {
        return this.timerRecorded;
    }

    /**
     * 前回Timer終了から今回入口までの間隔を計測済みの場合trueを返す。
     */
    bool hasTimerGap() {
        return this.timerGapMeasured;
    }

    /**
     * 最後に完了したTimerが分析試行を含む場合trueを返す。
     */
    bool wasTimerAnalysisExecuted() {
        return this.timerAnalysisExecuted;
    }

    /**
     * 前回Timer終了から今回入口までのミリ秒を返す。通常の待機時間も含む。
     */
    ulong getTimerGapMilliseconds() {
        return this.timerGapMilliseconds;
    }

    /**
     * 最後に完了したTimer全体の所要ミリ秒を返す。
     */
    double getTimerMilliseconds() {
        return this.timerMilliseconds;
    }

    /**
     * 最後に完了したTimerのラベル反映合計ミリ秒を返す。FIT描画は含まない。
     */
    double getTimerLabelMilliseconds() {
        return this.timerLabelMilliseconds;
    }

    /**
     * 初期化後に記録したTimer全体の最大ミリ秒を返す。
     */
    double getMaximumTimerMilliseconds() {
        return this.maximumTimerMilliseconds;
    }

    /**
     * 初期化後に記録したラベル反映合計の最大ミリ秒を返す。
     */
    double getMaximumTimerLabelMilliseconds() {
        return this.maximumTimerLabelMilliseconds;
    }

    /**
     * 更新開始を一度でも記録した場合trueを返す。
     */
    bool hasAttempt() {
        return this.attemptStarted;
    }

    /**
     * 開始間隔と予定時刻からの遅延を計測済みの場合trueを返す。
     */
    bool hasAttemptInterval() {
        return this.attemptIntervalMeasured;
    }

    /**
     * 正常終了を一度でも記録した場合trueを返す。
     */
    bool hasSuccess() {
        return this.successRecorded;
    }

    /**
     * 正常終了から次の正常終了までの間隔を計測済みの場合trueを返す。
     */
    bool hasSuccessInterval() {
        return this.successIntervalMeasured;
    }

    /**
     * 最後に終了を記録した更新が正常終了の場合trueを返す。
     */
    bool isLastSucceeded() {
        return this.lastSucceeded;
    }

    /**
     * 前回開始から今回開始までのミリ秒を返す。初回は0。
     */
    ulong getAttemptIntervalMilliseconds() {
        return this.attemptIntervalMilliseconds;
    }

    /**
     * 前回正常終了から今回正常終了までのミリ秒を返す。未計測の場合は0。
     */
    ulong getSuccessIntervalMilliseconds() {
        return this.successIntervalMilliseconds;
    }

    /**
     * 予定時刻からタイマー処理へ入るまでの遅延ミリ秒を返す。初回は0。
     */
    ulong getTimerDelayMilliseconds() {
        return this.timerDelayMilliseconds;
    }

    /**
     * 予定時刻から更新処理を開始するまでの遅延ミリ秒を返す。初回は0。
     */
    ulong getStartDelayMilliseconds() {
        return this.startDelayMilliseconds;
    }

    /**
     * 最後の正常終了から現在までの経過ミリ秒を返す。
     *
     * @param fromCurrentTick 現在の単調増加ミリ秒
     * @return 正常終了未記録または成功時刻より前の場合は0
     */
    ulong getElapsedSinceSuccessMilliseconds(ulong fromCurrentTick) {
        if (!this.successRecorded || fromCurrentTick < this.lastSuccessTick) {
            return 0;
        }

        return fromCurrentTick - this.lastSuccessTick;
    }

    /**
     * 最後の開始前に実行した補助処理の所要ミリ秒を返す。
     */
    double getAuxiliaryMilliseconds() {
        return this.auxiliaryMilliseconds;
    }

    /**
     * 最後に終了を記録した更新の所要ミリ秒を、成否を問わず返す。
     */
    double getLastAttemptMilliseconds() {
        return this.lastAttemptMilliseconds;
    }

    /**
     * 最後に終了を記録した更新の状態を返す。
     */
    string getLastState() {
        return this.lastState;
    }

    /**
     * 分析試行またはTimerの終了を記録するたびに増える改訂番号を返す。初期化時は0。
     */
    ulong getRevision() {
        return this.revision;
    }

    /**
     * 分析試行の開始または有効な終了記録で増える改訂番号を返す。初期化時は0。
     * Timerだけの記録では変更せず、分析診断の説明文を再利用する判定に使う。
     */
    ulong getAttemptRevision() {
        return this.attemptRevision;
    }

private:
    /** 更新開始を一度でも記録した場合true。 */
    bool attemptStarted;

    /** 開始済みの更新の終了が未記録の場合true。 */
    bool attemptPending;

    /** 更新開始の間隔と遅延を計測済みの場合true。 */
    bool attemptIntervalMeasured;

    /** 正常終了を一度でも記録した場合true。 */
    bool successRecorded;

    /** 正常終了の間隔を計測済みの場合true。 */
    bool successIntervalMeasured;

    /** 最後に終了を記録した更新が正常終了の場合true。 */
    bool lastSucceeded;

    /** 最後に記録した更新開始の単調増加ミリ秒。0も有効な時刻として扱う。 */
    ulong lastAttemptStartTick;

    /** 最後に記録した正常終了の単調増加ミリ秒。0も有効な時刻として扱う。 */
    ulong lastSuccessTick;

    /** 前回開始から今回開始までのミリ秒。 */
    ulong attemptIntervalMilliseconds;

    /** 前回正常終了から今回正常終了までのミリ秒。 */
    ulong successIntervalMilliseconds;

    /** 前回開始に設定間隔を加えた予定時刻からタイマー処理へ入るまでの遅延ミリ秒。 */
    ulong timerDelayMilliseconds;

    /** 前回開始に設定間隔を加えた予定時刻から更新開始までの遅延ミリ秒。 */
    ulong startDelayMilliseconds;

    /** 更新開始前の補助処理の所要ミリ秒。 */
    double auxiliaryMilliseconds;

    /** 最後に終了を記録した更新の所要ミリ秒。 */
    double lastAttemptMilliseconds;

    /** 最後に終了を記録した更新の状態。 */
    string lastState;

    /** Timerを一度でも記録した場合true。 */
    bool timerRecorded;

    /** Timer間の間隔を計測済みの場合true。 */
    bool timerGapMeasured;

    /** 最後に完了したTimerの終了時刻。 */
    ulong lastTimerEndTick;

    /** 前回Timer終了から今回入口までのミリ秒。通常の待機時間も含む。 */
    ulong timerGapMilliseconds;

    /** 最後に完了したTimer全体のミリ秒。診断ログ出力自体は含まない。 */
    double timerMilliseconds;

    /** 最後に完了したTimerの診断・処理時間ラベル反映合計ミリ秒。 */
    double timerLabelMilliseconds;

    /** 初期化後のTimer全体の最大ミリ秒。 */
    double maximumTimerMilliseconds;

    /** 初期化後のラベル反映合計の最大ミリ秒。 */
    double maximumTimerLabelMilliseconds;

    /** 最後に完了したTimerで分析を試行した場合true。 */
    bool timerAnalysisExecuted;

    /** 終了記録の改訂番号。 */
    ulong revision;

    /** 分析試行の開始・終了記録の改訂番号。 */
    ulong attemptRevision;
};

#endif // MSTNG_COMMON_UPDATE_TIMING_STATS_MQH
