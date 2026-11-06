#ifndef MSTNG_UTIL_ELLIOT_HISTORY_PREPARATION_MQH
#define MSTNG_UTIL_ELLIOT_HISTORY_PREPARATION_MQH

#include <Mstng\Util\Util.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * H1・M5の28通貨観測とH1・M15 EAで使う、1通貨の価格履歴準備。
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
        this.missingMask = 0;
        this.unsynchronizedMask = 0;
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
     * @param fromAnchorTimeFrame H1、M15またはM5。
     * @param fromRequireMinimumBars falseは既存EAのLIVE同期確認に使用。
     * @return 対象設定が有効な場合true。取得完了はprepareで確認する。
     */
    bool initialize(const string fromSymbol, const ENUM_TIMEFRAMES fromAnchorTimeFrame,
            const bool fromRequireMinimumBars = true) {
        this.reset();

        if (fromSymbol == "" || (fromAnchorTimeFrame != PERIOD_H1
                && fromAnchorTimeFrame != PERIOD_M15 && fromAnchorTimeFrame != PERIOD_M5)) {
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
        bool isBeforeStart = Util::isStrategyTester() && fromWarmupEndTime > 0
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
        this.missingMask = 0;
        this.unsynchronizedMask = 0;
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

            bool synchronized = false;
            int availableBars = 0;
            this.checkTimeFrame(timeFrame, requestBars, requiredBars, mayRequest,
                synchronized, availableBars, requested);

            this.applyTimeFrameResult(i, timeFrame, synchronized, availableBars, requiredBars);
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
     * 履歴を実際に確認済みかを返す。追加の市場参照は行わない。
     */
    bool isChecked() const { return this.checked; }

    /**
     * 不足足のビット列を返す。bit 0からMN1・W1・D1・H4・H1・M15・M5の順。
     */
    int getMissingMask() const { return this.missingMask; }

    /**
     * 未同期足のビット列を返す。不足足と同じ時間足順で、追加の市場参照は行わない。
     */
    int getUnsynchronizedMask() const { return this.unsynchronizedMask; }

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

    /** 直近の実確認で不足した足。bit 0からMN1・W1・D1・H4・H1・M15・M5の順。 */
    int missingMask;

    /** 直近の実確認で未同期だった足。不足足と同じビット順。 */
    int unsynchronizedMask;

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
     * 指定時間足の同期状態と履歴本数を確認し、不足時に再取得を要求する。
     *
     * 取得要求後は同期状態と本数を読み直す。要求済みフラグはtrueに更新するだけで、
     * 他の時間足ですでに行った取得要求の記録を保持する。
     *
     * @param fromTimeFrame 確認対象の時間足。
     * @param fromRequestBars 不足時に取得を要求する本数。
     * @param fromRequiredBars 準備完了に必要な本数。同期だけを確認する場合は0。
     * @param fromMayRequest 再取得の間隔を満たし、取得要求が可能な場合true。
     * @param fromSynchronized 最後に読み取った同期状態。
     * @param fromAvailableBars 最後に読み取った履歴本数。
     * @param fromRequested 全時間足の取得要求済みフラグ。今回要求した場合だけtrueに更新。
     */
    void checkTimeFrame(
        const ENUM_TIMEFRAMES fromTimeFrame,
        const int fromRequestBars,
        const int fromRequiredBars,
        const bool fromMayRequest,
        bool &fromSynchronized,
        int &fromAvailableBars,
        bool &fromRequested
    ) {
        fromSynchronized = WarmUpSeriesUtil::isSeriesSynchronized(this.symbolName, fromTimeFrame);
        fromAvailableBars = Bars(this.symbolName, fromTimeFrame);
        if ((!fromSynchronized || fromAvailableBars < fromRequiredBars) && fromMayRequest) {
            MqlRates rates[];
            // 取得要求だけで成功扱いせず、Testerから見える履歴を読み直す。
            CopyRates(this.symbolName, fromTimeFrame, 0, fromRequestBars, rates);
            fromRequested = true;
            fromSynchronized = WarmUpSeriesUtil::isSeriesSynchronized(this.symbolName, fromTimeFrame);
            fromAvailableBars = Bars(this.symbolName, fromTimeFrame);
        }
    }

    /**
     * 指定時間足の確認結果を準備状態・不足フラグ・診断文へ反映する。
     *
     * 未準備の足があれば全体の準備状態をfalseにし、他の足で記録した結果は保持する。
     * 全足の診断文と不足足だけの診断文には、確認した時間足順で追記する。
     *
     * @param fromIndex 上位足からの対象インデックス。不足・未同期フラグのbit位置。
     * @param fromTimeFrame 確認対象の時間足。
     * @param fromSynchronized 確認後の同期状態。
     * @param fromAvailableBars 確認後の履歴本数。
     * @param fromRequiredBars 準備完了に必要な本数。同期だけを確認する場合は0。
     */
    void applyTimeFrameResult(
        const int fromIndex,
        const ENUM_TIMEFRAMES fromTimeFrame,
        const bool fromSynchronized,
        const int fromAvailableBars,
        const int fromRequiredBars
    ) {
        bool timeFrameReady = fromSynchronized && fromAvailableBars >= fromRequiredBars;
        if (!fromSynchronized) {
            this.unsynchronizedMask |= 1 << fromIndex;
        }

        string detail = this.createStatusText(fromTimeFrame, fromSynchronized, fromAvailableBars,
            fromRequiredBars, timeFrameReady);
        if (this.statusText != "") {
            this.statusText += ", ";
        }
        this.statusText += detail;
        if (!timeFrameReady) {
            this.ready = false;
            this.missingMask |= 1 << fromIndex;
            if (this.missingStatusText != "") {
                this.missingStatusText += ", ";
            }
            this.missingStatusText += detail;
        }
    }

    /**
     * Testerはシミュレーション時刻、LIVEは単調経過時刻を返す。
     */
    ulong getClock() const {
        if (Util::isStrategyTester()) {
            return (ulong)TimeCurrent() * 1000;
        }

        return GetTickCount64();
    }

    /**
     * H1は5足、M15は6足、M5は7足を対象にする。
     */
    int getTimeFrameCount() const {
        if (this.anchorTimeFrame == PERIOD_M5) {
            return 7;
        }

        if (this.anchorTimeFrame == PERIOD_M15) {
            return 6;
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
