//+------------------------------------------------------------------+
//|                            CurrencyStrengthEntryAndTracker.mqh  |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_ENTRY_AND_TRACKER_MQH
#define MSTNG_CURRENCY_STRENGTH_ENTRY_AND_TRACKER_MQH

#include <Mstng\Strength\CurrencyStrengthEntryCandidate.mqh>

/**
 * 1通貨ペア・1売買方向のAND成立状態と新規成立の検出時刻を保持する。
 */
struct CurrencyStrengthEntryAndTrackerState {
    /** 正規化された通貨ペア名。 */
    string symbolName;

    /** BUY候補の場合true。 */
    bool isBuy;

    /** 前回の成立・不成立が既知の場合true。 */
    bool known;

    /** 前回のAND判定が成立している場合true。 */
    bool matched;

    /** 今回の正常な候補一覧で観測済みの場合true。 */
    bool seen;

    /** 不成立から成立への変化を検出したサーバー時刻。未検出は0。 */
    datetime detectedAt;

    /** NEW表示を終了する単調増加時計のミリ秒。非表示は0。 */
    ulong newUntilMilliseconds;
};

/**
 * 全候補のAND成立変化を銘柄と売買方向ごとに追跡する。
 * 初回・取得復旧時は基準登録だけ行い、既知の不成立からの成立だけをNEWとする。
 */
class CurrencyStrengthEntryAndTracker {
public:
    /**
     * AND成立の追跡状態を初期化する。
     */
    CurrencyStrengthEntryAndTracker() {
        this.reset();
    }

    /**
     * 初回またはEMAモード変更時に全追跡状態を破棄する。
     */
    void reset() {
        ArrayResize(this.states, 0);
        this.baselineCompleted = false;
        this.updateActive = false;
    }

    /**
     * 表示上限と絞り込みを適用する前の候補一覧の観測を開始する。
     *
     * 全体が未準備の場合、または前回の観測が完了していない場合は、
     * 復旧時の変化を新規成立と誤認しないよう基準を解除する。
     *
     * @param fromRankingReady 全通貨順位を正常に取得済みの場合true。
     */
    void beginUpdate(const bool fromRankingReady) {
        if (this.updateActive) {
            this.suspend();
        }

        if (!fromRankingReady) {
            this.suspend();

            return;
        }

        for (int i = 0; i < ArraySize(this.states); i++) {
            this.states[i].seen = false;
        }

        this.updateActive = true;
    }

    /**
     * 1候補の成立状態を観測し、不成立から成立した場合だけNEWを開始する。
     *
     * 初回一覧が完成した後の新規候補は、前回の非候補を不成立として扱う。
     * 強弱READYで必要なEMAが未取得の場合は不明とし、復旧時は基準登録だけ行う。
     *
     * @param fromCandidate 表示上限と絞り込みを適用する前の候補。
     * @param fromMode AND判定に使用するEMA200時間足。
     * @param fromServerTime 状態変化を観測したサーバー時刻。
     * @param fromNowMilliseconds 観測時の単調増加時計のミリ秒。
     */
    void observe(
        CurrencyStrengthEntryCandidate &fromCandidate,
        CurrencyStrengthEntryEmaMode fromMode,
        const datetime fromServerTime,
        const ulong fromNowMilliseconds
    ) {
        if (!this.updateActive) {
            return;
        }

        if (fromCandidate.symbolName == "") {
            this.suspend();

            return;
        }

        int stateIndex = this.findIndex(fromCandidate.symbolName, fromCandidate.isBuy);
        if (stateIndex < 0) {
            int stateCount = ArraySize(this.states);
            if (ArrayResize(this.states, stateCount + 1) != stateCount + 1) {
                this.suspend();

                return;
            }

            stateIndex = stateCount;
            this.states[stateIndex].symbolName = fromCandidate.symbolName;
            this.states[stateIndex].isBuy = fromCandidate.isBuy;
            this.states[stateIndex].known = this.baselineCompleted;
            this.states[stateIndex].matched = false;
            this.states[stateIndex].seen = false;
            this.states[stateIndex].detectedAt = 0;
            this.states[stateIndex].newUntilMilliseconds = 0;
        }

        this.states[stateIndex].seen = true;
        if (!this.isResultKnown(fromCandidate, fromMode)) {
            this.clearMatch(stateIndex, false);

            return;
        }

        if (!fromCandidate.isAndReady(fromMode)) {
            this.clearMatch(stateIndex, true);

            return;
        }

        if (this.baselineCompleted && this.states[stateIndex].known
                && !this.states[stateIndex].matched) {
            this.states[stateIndex].detectedAt = fromServerTime;
            this.states[stateIndex].newUntilMilliseconds = fromNowMilliseconds + 60000;
        }

        this.states[stateIndex].known = true;
        this.states[stateIndex].matched = true;
    }

    /**
     * 正常な候補一覧の観測を完了し、消えた候補を既知の不成立として記録する。
     */
    void endUpdate() {
        if (!this.updateActive) {
            return;
        }

        for (int i = 0; i < ArraySize(this.states); i++) {
            if (!this.states[i].seen) {
                this.clearMatch(i, true);
            }
        }

        this.baselineCompleted = true;
        this.updateActive = false;
    }

    /**
     * 指定した候補のNEW表示期間が継続しているか判定する。
     *
     * @param fromSymbolName 正規化された通貨ペア名。
     * @param fromIsBuy BUY候補の場合true。
     * @param fromNowMilliseconds 現在の単調増加時計のミリ秒。
     * @return 新規成立から60秒未満で、既知の成立状態が続いている場合true。
     */
    bool isNew(
        const string fromSymbolName,
        const bool fromIsBuy,
        const ulong fromNowMilliseconds
    ) {
        int stateIndex = this.findIndex(fromSymbolName, fromIsBuy);
        if (stateIndex < 0) {
            return false;
        }

        return this.states[stateIndex].known
            && this.states[stateIndex].matched
            && this.states[stateIndex].newUntilMilliseconds > 0
            && fromNowMilliseconds < this.states[stateIndex].newUntilMilliseconds;
    }

    /**
     * 直近の不成立から成立への変化を検出したサーバー時刻を取得する。
     *
     * 成立が続く間はNEW終了後も保持する。初回成立・不成立・取得不明では0を返す。
     *
     * @param fromSymbolName 正規化された通貨ペア名。
     * @param fromIsBuy BUY候補の場合true。
     * @return 実際の新規成立を観測したサーバー時刻。未検出は0。
     */
    datetime getDetectedAt(const string fromSymbolName, const bool fromIsBuy) {
        int stateIndex = this.findIndex(fromSymbolName, fromIsBuy);
        if (stateIndex < 0 || !this.states[stateIndex].known
                || !this.states[stateIndex].matched) {
            return 0;
        }

        return this.states[stateIndex].detectedAt;
    }

    /**
     * 集計失敗・データ未準備時に追跡を中断し、次回正常取得を基準登録へ戻す。
     */
    void suspend() {
        for (int i = 0; i < ArraySize(this.states); i++) {
            this.clearMatch(i, false);
            this.states[i].seen = false;
        }

        this.baselineCompleted = false;
        this.updateActive = false;
    }

private:
    /** 通貨ペアと売買方向ごとの追跡状態。分析オブジェクトは保持しない。 */
    CurrencyStrengthEntryAndTrackerState states[];

    /** 正常な候補一覧を一度以上観測済みの場合true。 */
    bool baselineCompleted;

    /** beginUpdateからendUpdateまでの正常な観測中の場合true。 */
    bool updateActive;

    /**
     * 通貨ペアと売買方向に対応する保持位置を取得する。
     *
     * @param fromSymbolName 正規化された通貨ペア名。
     * @param fromIsBuy BUY候補の場合true。
     * @return 保持位置。未登録の場合は-1。
     */
    int findIndex(const string fromSymbolName, const bool fromIsBuy) {
        for (int i = 0; i < ArraySize(this.states); i++) {
            if (this.states[i].symbolName == fromSymbolName
                    && this.states[i].isBuy == fromIsBuy) {
                return i;
            }
        }

        return -1;
    }

    /**
     * 選択したAND条件について成立・不成立を確定できるか判定する。
     *
     * @param fromCandidate 判定対象候補。
     * @param fromMode AND判定に使用するEMA200時間足。
     * @return 強弱未READY、または必要なEMAをすべて取得済みの場合true。
     */
    bool isResultKnown(
        CurrencyStrengthEntryCandidate &fromCandidate,
        CurrencyStrengthEntryEmaMode fromMode
    ) {
        if (!fromCandidate.isReady()) {
            return true;
        }

        if (fromMode == currencyStrengthEntryEmaM1) {
            return fromCandidate.m1EmaAvailable;
        }

        if (fromMode == currencyStrengthEntryEmaH1AndM1) {
            return fromCandidate.h1EmaAvailable && fromCandidate.m1EmaAvailable;
        }

        return fromCandidate.h1EmaAvailable;
    }

    /**
     * 指定候補の成立・NEW・検出時刻を解除する。
     *
     * @param fromStateIndex 解除対象の保持位置。
     * @param fromKnown 不成立が既知の場合true、取得不明の場合false。
     */
    void clearMatch(const int fromStateIndex, const bool fromKnown) {
        this.states[fromStateIndex].known = fromKnown;
        this.states[fromStateIndex].matched = false;
        this.states[fromStateIndex].detectedAt = 0;
        this.states[fromStateIndex].newUntilMilliseconds = 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_AND_TRACKER_MQH
