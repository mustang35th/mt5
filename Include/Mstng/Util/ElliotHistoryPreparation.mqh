#ifndef MSTNG_UTIL_ELLIOT_HISTORY_PREPARATION_MQH
#define MSTNG_UTIL_ELLIOT_HISTORY_PREPARATION_MQH

#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * H1・M5の28通貨観測とH1 EAで使う、1通貨の価格履歴準備。
 * 履歴の同期・本数だけを管理し、分析成功・DB・保存/売買許可は扱わない。
 */
class ElliotHistoryPreparation {
public:
    /**
     * 未確認状態で初期化する。
     */
    ElliotHistoryPreparation() {
        this.reset();
    }

    /**
     * 保持した準備結果と再確認時刻を破棄する。
     */
    void reset() {
        this.symbolName = "";
        this.anchorTimeFrame = PERIOD_CURRENT;
        this.requireMinimumBars = true;
        this.initialized = false;
        this.checked = false;
        this.ready = false;
        this.beforeStart = false;
        this.lastWarmupEndTime = 0;
        this.lastCheckTick = 0;
        this.nextRequestTick = 0;
        this.statusText = "";
        this.missingStatusText = "";
    }

    /**
     * 対象足を固定し、基準足から上位足の順で初期履歴を要求する。
     * 500本は取得要求量であり、履歴準備完了の必要本数ではない。
     *
     * @param fromSymbol 対象通貨。
     * @param fromAnchorTimeFrame H1またはM5。
     * @param fromRequireMinimumBars falseは既存EAのLIVE同期確認に使用。
     * @return 対象設定が有効な場合true。取得完了はprepareで確認する。
     */
    bool initialize(const string fromSymbol, const ENUM_TIMEFRAMES fromAnchorTimeFrame,
            const bool fromRequireMinimumBars = true) {
        this.reset();
        if (fromSymbol == "" || (fromAnchorTimeFrame != PERIOD_H1
                && fromAnchorTimeFrame != PERIOD_M5)) {
            return false;
        }
        this.symbolName = fromSymbol;
        this.anchorTimeFrame = fromAnchorTimeFrame;
        this.requireMinimumBars = fromRequireMinimumBars;
        ENUM_TIMEFRAMES timeFrames[];
        int total = this.getTimeFrameCount();
        ArrayResize(timeFrames, total);
        for (int i = 0; i < total; i++) {
            // 始値のみの他通貨でも、最初に参照する足を基準足にする。
            timeFrames[i] = this.getTimeFrame(total - 1 - i);
        }
        WarmUpSeriesUtil::warmUp(this.symbolName, timeFrames, 500);
        this.nextRequestTick = this.getClock() + 60000;
        this.initialized = true;
        return true;
    }

    /**
     * 全対象足の同期・必要本数を確認する。
     * TESTERの指定開始前だけ最短1時間間隔とし、開始到達・時刻逆行で待機を解除する。
     * 開始後/LIVEは毎回状態を読み、不足履歴の再取得要求だけ最短60秒に抑える。
     *
     * @param fromWarmupEndTime 保存/売買開始サーバー時刻。0は開始前の間引きなし。
     * @return 全対象足の履歴準備が完了している場合true。分析成功は意味しない。
     */
    bool prepare(const datetime fromWarmupEndTime = 0) {
        if (!this.initialized) {
            return false;
        }
        ulong now = this.getClock();
        bool isBeforeStart = MQLInfoInteger(MQL_TESTER) && fromWarmupEndTime > 0
            && TimeCurrent() < fromWarmupEndTime;
        bool clockReversed = this.checked && now < this.lastCheckTick;
        bool phaseChanged = this.checked && (isBeforeStart != this.beforeStart
            || fromWarmupEndTime != this.lastWarmupEndTime);
        // 開始後に呼出側が0/指定日時を切り替えても、取得間隔は解除しない。
        if (clockReversed || (this.checked && isBeforeStart != this.beforeStart)) {
            this.nextRequestTick = 0;
        }
        if (this.checked && isBeforeStart && this.beforeStart && !phaseChanged
                && !clockReversed && now - this.lastCheckTick < 3600000) {
            return this.ready;
        }
        this.checked = true;
        this.beforeStart = isBeforeStart;
        this.lastWarmupEndTime = fromWarmupEndTime;
        this.lastCheckTick = now;
        this.ready = true;
        this.statusText = "";
        this.missingStatusText = "";
        bool mayRequest = now >= this.nextRequestTick;
        bool requested = false;
        for (int i = 0; i < this.getTimeFrameCount(); i++) {
            ENUM_TIMEFRAMES timeFrame = this.getTimeFrame(i);
            int requestBars = this.getRequiredBars(timeFrame);
            int requiredBars = 0;
            if (this.requireMinimumBars) {
                requiredBars = requestBars;
            }
            bool synchronized = WarmUpSeriesUtil::isSeriesSynchronized(this.symbolName, timeFrame);
            int availableBars = Bars(this.symbolName, timeFrame);
            if ((!synchronized || availableBars < requiredBars) && mayRequest) {
                MqlRates rates[];
                // 取得要求だけで成功扱いせず、Testerから見える履歴を読み直す。
                CopyRates(this.symbolName, timeFrame, 0, requestBars, rates);
                requested = true;
                synchronized = WarmUpSeriesUtil::isSeriesSynchronized(this.symbolName, timeFrame);
                availableBars = Bars(this.symbolName, timeFrame);
            }
            bool timeFrameReady = synchronized && availableBars >= requiredBars;
            string detail = this.createStatusText(timeFrame, synchronized, availableBars,
                requiredBars, timeFrameReady);
            if (this.statusText != "") {
                this.statusText += ", ";
            }
            this.statusText += detail;
            if (!timeFrameReady) {
                this.ready = false;
                if (this.missingStatusText != "") {
                    this.missingStatusText += ", ";
                }
                this.missingStatusText += detail;
            }
        }
        if (requested) {
            this.nextRequestTick = now + 60000;
        }
        return this.ready;
    }

    /**
     * 最後に確認した履歴準備結果を返す。追加の市場参照は行わない。
     */
    bool isReady() const { return this.checked && this.ready; }

    /**
     * 全対象足の同期・本数・最古日時を返す。
     */
    string getStatusText() const { return this.statusText; }

    /**
     * 不足足だけの診断を返す。全足準備済みなら空文字。
     */
    string getMissingStatusText() const { return this.missingStatusText; }

private:
    /** 対象通貨。 */
    string symbolName;
    /** 最下位の対象足。 */
    ENUM_TIMEFRAMES anchorTimeFrame;
    /** 同期に加えて最低本数を要求する場合true。 */
    bool requireMinimumBars;
    /** 対象設定済みの場合true。 */
    bool initialized;
    /** 少なくとも1回履歴を確認済みの場合true。 */
    bool checked;
    /** 全対象足の直近の履歴準備結果。 */
    bool ready;
    /** 前回確認時に指定開始前だった場合true。 */
    bool beforeStart;
    /** 前回指定された開始時刻。 */
    datetime lastWarmupEndTime;
    /** 前回確認時の経過時刻。Testerはサーバー時刻を使用する。 */
    ulong lastCheckTick;
    /** 次の不足履歴取得要求が可能な経過時刻。 */
    ulong nextRequestTick;
    /** 全対象足の履歴診断。 */
    string statusText;
    /** 不足足だけの履歴診断。 */
    string missingStatusText;

    /**
     * Testerはシミュレーション時刻、LIVEは単調経過時刻を返す。
     */
    ulong getClock() const {
        if (MQLInfoInteger(MQL_TESTER)) {
            return (ulong)TimeCurrent() * 1000;
        }
        return GetTickCount64();
    }

    /**
     * H1は5足、M5は7足を対象にする。
     */
    int getTimeFrameCount() const {
        if (this.anchorTimeFrame == PERIOD_M5) {
            return 7;
        }
        return 5;
    }

    /**
     * 上位足からの固定順で対象時間足を返す。
     */
    ENUM_TIMEFRAMES getTimeFrame(const int fromIndex) const {
        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
        };
        return timeFrames[fromIndex];
    }

    /**
     * MN1は61本、その他の対象足は206本を必要とする。
     */
    int getRequiredBars(const ENUM_TIMEFRAMES fromTimeFrame) const {
        if (fromTimeFrame == PERIOD_MN1) {
            return 61;
        }
        return 206;
    }

    /**
     * 既存EA診断と同じ形式で1時間足の準備状態を作る。
     */
    string createStatusText(const ENUM_TIMEFRAMES fromTimeFrame, const bool fromSynchronized,
            const int fromAvailableBars, const int fromRequiredBars, const bool fromReady) {
        long firstDate = 0;
        string firstDateText = "UNAVAILABLE";
        if (SeriesInfoInteger(this.symbolName, fromTimeFrame, SERIES_FIRSTDATE, firstDate)
                && firstDate > 0) {
            firstDateText = TimeToString((datetime)firstDate, TIME_DATE | TIME_MINUTES);
        }
        string timeFrameText = EnumToString(fromTimeFrame);
        StringReplace(timeFrameText, "PERIOD_", "");
        string stateText = "WAIT";
        if (fromReady) {
            stateText = "READY";
        }
        return StringFormat("%s[%s,sync=%d,bars=%d,required=%d,first=%s]", timeFrameText,
            stateText, (int)fromSynchronized, fromAvailableBars, fromRequiredBars, firstDateText);
    }
};

#endif
