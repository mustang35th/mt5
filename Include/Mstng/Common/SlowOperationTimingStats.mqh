//+------------------------------------------------------------------+
//|                                    SlowOperationTimingStats.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_COMMON_SLOW_OPERATION_TIMING_STATS_MQH
#define MSTNG_COMMON_SLOW_OPERATION_TIMING_STATS_MQH

/**
 * 遅延診断の計測区間を表す。
 * 全体とその内訳が重なるため、各区間の所要時間は合計しない。
 */
enum SlowOperationTimingStage {
    stageGmma,
    stageEma200,
    stageJapanTimeAxis,
    stageBidAsk,
    stageLabels,
    stageRedraw,
    stageCalculate,
    stageChartEvent,
    stageLogOutput,
    stageTimerGap,
    stageTimingCount
};

/**
 * 閾値以上の遅延だけを区間別に集計し、最大60秒に1回の診断文字列を作る。
 * 出力自体は行わず、遅いログ出力も次回分へ保持して再帰出力を防ぐ。
 */
class SlowOperationTimingStats {
public:
    /**
     * 保留中の計測と出力間隔を初期化する。
     */
    SlowOperationTimingStats() {
        this.reset();
    }

    /**
     * 全計測を消去し、次の遅延を直ちに出力できる状態へ戻す。
     */
    void reset() {
        this.clearPending();
        this.logRecorded = false;
        this.lastLogCompletedTick = 0;
    }

    /**
     * 1秒以上の処理、または5秒以上のTimer間隔を保持する。
     * 閾値未満では時刻取得と文字列生成を行わない。
     *
     * @param fromStage 計測区間
     * @param fromElapsedMicroseconds 計測した経過マイクロ秒
     */
    void record(SlowOperationTimingStage fromStage, ulong fromElapsedMicroseconds) {
        int stageIndex = (int)fromStage;
        if (stageIndex < 0 || stageIndex >= stageTimingCount) {
            return;
        }

        ulong thresholdMicroseconds = 1000000;
        if (fromStage == stageTimerGap) {
            thresholdMicroseconds = 5000000;
        }

        if (fromElapsedMicroseconds < thresholdMicroseconds) {
            return;
        }

        this.counts[stageIndex]++;
        this.pending = true;
        if (fromElapsedMicroseconds > this.peakMicroseconds[stageIndex]) {
            this.peakMicroseconds[stageIndex] = fromElapsedMicroseconds;
            this.peakEndTicks[stageIndex] = GetTickCount64();
        }
    }

    /**
     * 保留中の遅延があり、前回出力完了から60秒以上経過しているかを返す。
     * 初回または単調増加時刻が逆行した場合も出力を許可する。
     *
     * @param fromCurrentTick 今回の単調増加ミリ秒
     */
    bool isLogDue(ulong fromCurrentTick) {
        if (!this.pending) {
            return false;
        }

        if (!this.logRecorded || fromCurrentTick < this.lastLogCompletedTick) {
            return true;
        }

        return fromCurrentTick - this.lastLogCompletedTick >= 60000;
    }

    /**
     * 出力可能な場合だけ診断文字列を作り、保留中の計測を消去する。
     * ageMsは区間最大値を記録してからの経過時間で、出力待ちを含む。
     * ログ出力より先に消去するため、その出力の遅延を次回分へ記録できる。
     *
     * @param fromCurrentTick 文字列を取り出す単調増加ミリ秒
     * @return 出力する1行。保留なし、または出力間隔内なら空文字列
     */
    string takeLog(ulong fromCurrentTick) {
        if (!this.isLogDue(fromCurrentTick)) {
            return "";
        }

        string output = "SLOW_TIMING";
        for (int i = 0; i < stageTimingCount; i++) {
            if (this.counts[i] == 0) {
                continue;
            }

            ulong ageMilliseconds = 0;
            if (fromCurrentTick >= this.peakEndTicks[i]) {
                ageMilliseconds = fromCurrentTick - this.peakEndTicks[i];
            }

            output += StringFormat(" %s(count=%I64d maxMs=%.1f ageMs=%I64d)",
                this.getStageName((SlowOperationTimingStage)i),
                (long)this.counts[i], (double)this.peakMicroseconds[i] / 1000.0,
                (long)ageMilliseconds);
        }

        this.clearPending();

        return output;
    }

    /**
     * 診断ログの出力完了時刻を保存し、次回までの間隔を開始する。
     * 出力中に記録した遅延は消去しない。
     *
     * @param fromCurrentTick ログ出力完了時の単調増加ミリ秒
     */
    void markLogCompleted(ulong fromCurrentTick) {
        this.logRecorded = true;
        this.lastLogCompletedTick = fromCurrentTick;
    }

private:
    /** 前回取り出し以降の閾値以上の件数。 */
    ulong counts[stageTimingCount];

    /** 前回取り出し以降の最大所要マイクロ秒。 */
    ulong peakMicroseconds[stageTimingCount];

    /** 各最大値を記録した単調増加ミリ秒。 */
    ulong peakEndTicks[stageTimingCount];

    /** 未出力の遅延を保持している場合true。 */
    bool pending;

    /** 診断ログを一度でも出力した場合true。 */
    bool logRecorded;

    /** 直近の診断ログ出力完了時刻。 */
    ulong lastLogCompletedTick;

    /**
     * 出力間隔を維持したまま、保留中の計測だけを消去する。
     */
    void clearPending() {
        ArrayInitialize(this.counts, 0);
        ArrayInitialize(this.peakMicroseconds, 0);
        ArrayInitialize(this.peakEndTicks, 0);
        this.pending = false;
    }

    /**
     * 診断ログに使用する区間名を返す。
     *
     * @param fromStage 計測区間
     */
    string getStageName(SlowOperationTimingStage fromStage) {
        switch (fromStage) {
            case stageGmma: return "GMMA";
            case stageEma200: return "EMA200";
            case stageJapanTimeAxis: return "JapanTimeAxis";
            case stageBidAsk: return "BidAsk";
            case stageLabels: return "Labels";
            case stageRedraw: return "Redraw";
            case stageCalculate: return "OnCalculate";
            case stageChartEvent: return "OnChartEvent";
            case stageLogOutput: return "LogOutput";
            case stageTimerGap: return "TimerGap";
        }

        return "Unknown";
    }
};

#endif // MSTNG_COMMON_SLOW_OPERATION_TIMING_STATS_MQH
