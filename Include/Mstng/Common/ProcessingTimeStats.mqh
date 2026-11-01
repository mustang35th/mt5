//+------------------------------------------------------------------+
//|                                          ProcessingTimeStats.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_COMMON_PROCESSING_TIME_STATS_MQH
#define MSTNG_COMMON_PROCESSING_TIME_STATS_MQH

/**
 * 正常終了した直近20回の処理時間と、最後の実行状態を保持する。
 */
class ProcessingTimeStats {
public:
    /**
     * 計測履歴を初期化する。
     */
    ProcessingTimeStats() {
        this.reset();
    }

    /**
     * 処理時間と実行状態を未計測へ戻す。
     */
    void reset() {
        ArrayInitialize(this.samples, 0.0);
        this.sampleCount = 0;
        this.nextSampleIndex = 0;
        this.totalMilliseconds = 0.0;
        this.latestMilliseconds = 0.0;
        this.maximumMilliseconds = 0.0;
        this.lastAttemptTime = 0;
        this.lastSuccessTime = 0;
        this.lastSucceeded = false;
        this.state = "未計測";
    }

    /**
     * 実行状態を記録し、正常終了の場合だけ時間の履歴へ追加する。
     * スキップした処理ではこのメソッドを呼ばない。
     *
     * @param fromElapsedMicroseconds 計測した経過マイクロ秒
     * @param fromSucceeded 正常終了した場合true
     * @param fromState 通常更新・全体更新・再試行などの実行状態
     */
    void record(ulong fromElapsedMicroseconds, bool fromSucceeded, string fromState) {
        this.lastAttemptTime = TimeLocal();
        this.lastSucceeded = fromSucceeded;
        this.state = fromState;

        if (!fromSucceeded) {
            return;
        }

        double milliseconds = (double)fromElapsedMicroseconds / 1000.0;
        if (this.sampleCount == ArraySize(this.samples)) {
            this.totalMilliseconds -= this.samples[this.nextSampleIndex];
        } else {
            this.sampleCount++;
        }

        this.samples[this.nextSampleIndex] = milliseconds;
        this.totalMilliseconds += milliseconds;
        this.latestMilliseconds = milliseconds;
        this.lastSuccessTime = this.lastAttemptTime;
        this.nextSampleIndex++;
        if (this.nextSampleIndex == ArraySize(this.samples)) {
            this.nextSampleIndex = 0;
        }

        this.maximumMilliseconds = 0.0;
        for (int i = 0; i < this.sampleCount; i++) {
            if (this.samples[i] > this.maximumMilliseconds) {
                this.maximumMilliseconds = this.samples[i];
            }
        }
    }

    /**
     * 集計中の正常終了件数を返す。
     */
    int getCount() { return this.sampleCount; }

    /**
     * 直近の正常終了時の所要ミリ秒を返す。
     */
    double getLatestMilliseconds() { return this.latestMilliseconds; }

    /**
     * 正常終了履歴の平均ミリ秒を返す。未計測の場合は0。
     */
    double getAverageMilliseconds() {
        if (this.sampleCount == 0) {
            return 0.0;
        }

        return this.totalMilliseconds / this.sampleCount;
    }

    /**
     * 正常終了履歴の最大ミリ秒を返す。
     */
    double getMaximumMilliseconds() { return this.maximumMilliseconds; }

    /**
     * 最後に実行を試みたローカル時刻を返す。
     */
    datetime getLastAttemptTime() { return this.lastAttemptTime; }

    /**
     * 最後に正常終了したローカル時刻を返す。
     */
    datetime getLastSuccessTime() { return this.lastSuccessTime; }

    /**
     * 最後に記録した実行状態を返す。
     */
    string getState() { return this.state; }

    /**
     * 最後に記録した実行が正常終了した場合trueを返す。
     */
    bool isLastSucceeded() { return this.lastSucceeded; }

private:
    /** 正常終了した直近20回のミリ秒を保持するリング配列。 */
    double samples[20];

    /** 集計中の正常終了件数。 */
    int sampleCount;

    /** 次に上書きする履歴位置。 */
    int nextSampleIndex;

    /** 集計中の処理時間の合計ミリ秒。 */
    double totalMilliseconds;

    /** 直近の正常終了時のミリ秒。 */
    double latestMilliseconds;

    /** 集計中の処理時間の最大ミリ秒。 */
    double maximumMilliseconds;

    /** 最後に実行を試みたローカル時刻。 */
    datetime lastAttemptTime;

    /** 最後に正常終了したローカル時刻。 */
    datetime lastSuccessTime;

    /** 最後に記録した実行が正常終了した場合true。 */
    bool lastSucceeded;

    /** 最後に記録した実行状態。 */
    string state;
};

#endif
