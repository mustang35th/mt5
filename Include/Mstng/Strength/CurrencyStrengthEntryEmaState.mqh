//+------------------------------------------------------------------+
//|                              CurrencyStrengthEntryEmaState.mqh   |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_ENTRY_EMA_STATE_MQH
#define MSTNG_CURRENCY_STRENGTH_ENTRY_EMA_STATE_MQH

#include <Mstng\Strength\CurrencyStrengthEntryAndTracker.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidateList.mqh>

/**
 * 候補一覧のEMA設定と実効モードを分け、全候補からM1補完を選択する。
 * 各モードの成立変化を独立して追跡し、自動切替だけではNEWを発生させない。
 */
class CurrencyStrengthEntryEmaState {
public:
    /**
     * 未集計のH1＋M1設定で初期化する。自動補完の許可は呼び出し元で指定する。
     */
    CurrencyStrengthEntryEmaState() {
        this.configuredMode = currencyStrengthEntryEmaH1AndM1;
        this.effectiveMode = currencyStrengthEntryEmaH1AndM1;
        this.autoFallbackAllowed = false;
        this.selectionPending = false;
        this.countsAvailable = false;
        this.readyEmaMissing = false;
        this.h1EmaMissing = false;
        this.m1EmaMissing = false;
        this.h1AndM1Count = 0;
        this.h1Count = 0;
        this.m1Count = 0;
    }

    /**
     * 保存対象の設定と通常チャートでの自動補完許可を更新する。
     * 変更時だけNEW追跡を初期化し、有効な集計があれば実効モードを選び直す。
     *
     * @param fromMode ユーザーが選択したEMAモード。
     * @param fromAutoFallbackAllowed 通常チャートでM1補完を許可する場合true。
     */
    void setMode(const CurrencyStrengthEntryEmaMode fromMode,
            const bool fromAutoFallbackAllowed) {
        if (fromMode != currencyStrengthEntryEmaH1
                && fromMode != currencyStrengthEntryEmaM1
                && fromMode != currencyStrengthEntryEmaH1AndM1) {
            return;
        }

        if (this.configuredMode == fromMode
                && this.autoFallbackAllowed == fromAutoFallbackAllowed) {
            return;
        }

        this.configuredMode = fromMode;
        this.effectiveMode = fromMode;
        this.autoFallbackAllowed = fromAutoFallbackAllowed;
        this.h1Tracker.reset();
        this.m1Tracker.reset();
        this.h1AndM1Tracker.reset();
        this.selectEffectiveMode();
    }

    /**
     * 保存対象のユーザー設定を取得する。
     *
     * @return 自動補完で書き換えないEMAモード。
     */
    CurrencyStrengthEntryEmaMode getConfiguredMode() const {
        return this.configuredMode;
    }

    /**
     * AND判定と表示に使用する実効モードを取得する。
     *
     * @return 現在のEMAモード。
     */
    CurrencyStrengthEntryEmaMode getEffectiveMode() const {
        return this.effectiveMode;
    }

    /**
     * H1＋M1設定をM1で補完しているか取得する。
     *
     * @return 自動補完を許可し、実効モードがM1の場合true。
     */
    bool isAutoFallback() const {
        return this.autoFallbackAllowed
            && this.configuredMode == currencyStrengthEntryEmaH1AndM1
            && this.effectiveMode == currencyStrengthEntryEmaM1;
    }

    /**
     * データ未取得のため自動選択を保留しているか取得する。
     *
     * @return 自動選択に必要な順位またはEMAが未取得の場合true。
     */
    bool isSelectionPending() const {
        return this.selectionPending;
    }

    /**
     * 未集計または実効モードの必要EMAが未取得のため、件数表示を待機にするか取得する。
     * 1件以上の成立が確定していれば一部候補の欠損だけでは待機にしない。
     *
     * @return 未集計、自動選択保留、または成立0件で必要EMA未取得の場合true。
     */
    bool isDisplayPending() const {
        if (!this.countsAvailable || this.selectionPending) {
            return true;
        }

        if (this.effectiveMode == currencyStrengthEntryEmaH1) {
            return this.h1Count == 0 && this.h1EmaMissing;
        }

        if (this.effectiveMode == currencyStrengthEntryEmaM1) {
            return this.m1Count == 0 && this.m1EmaMissing;
        }

        return this.h1AndM1Count == 0 && this.readyEmaMissing;
    }

    /**
     * 直近の全候補でH1＋M1のAND条件を満たす件数を取得する。
     *
     * @return 成立件数。集計が無効な場合は0。
     */
    int getH1AndM1Count() const {
        return this.h1AndM1Count;
    }

    /**
     * 直近の全候補でM1のAND条件を満たす件数を取得する。
     *
     * @return 成立件数。集計が無効な場合は0。
     */
    int getM1Count() const {
        return this.m1Count;
    }

    /**
     * 実データ更新時だけ全候補の件数と各モードの成立変化を観測する。
     * ボタン操作による再描画では集計と追跡を繰り返さない。
     *
     * @param fromCandidateList 表示上限と絞り込みを適用する前の候補一覧。
     * @param fromUpdateTracking 実データ更新として観測する場合true。
     * @param fromServerTime 新規成立を記録するサーバー時刻。
     * @param fromNowMilliseconds NEW期限に使用する単調増加ミリ秒。
     * @return 候補一覧が正常な場合true。取得失敗・未集計の場合は追跡を中断してfalse。
     */
    bool update(CurrencyStrengthEntryCandidateList *fromCandidateList,
            const bool fromUpdateTracking, const datetime fromServerTime,
            const ulong fromNowMilliseconds) {
        if (fromCandidateList == NULL || !fromCandidateList.isRankingReady()) {
            this.suspend();

            return false;
        }

        if (!fromUpdateTracking) {
            return true;
        }

        int nextH1AndM1Count = 0;
        int nextH1Count = 0;
        int nextM1Count = 0;
        bool nextReadyEmaMissing = false;
        bool nextH1EmaMissing = false;
        bool nextM1EmaMissing = false;
        this.h1Tracker.beginUpdate(true);
        this.m1Tracker.beginUpdate(true);
        this.h1AndM1Tracker.beginUpdate(true);

        int candidateCount = fromCandidateList.size();
        for (int i = 0; i < candidateCount; i++) {
            CurrencyStrengthEntryCandidate candidate;
            candidate.reset();
            if (!fromCandidateList.get(i, candidate) || candidate.symbolName == "") {
                this.suspend();

                return false;
            }

            if (candidate.isReady()) {
                if (!candidate.h1EmaAvailable || !candidate.m1EmaAvailable) {
                    nextReadyEmaMissing = true;
                }

                if (!candidate.h1EmaAvailable) {
                    nextH1EmaMissing = true;
                }

                if (!candidate.m1EmaAvailable) {
                    nextM1EmaMissing = true;
                }

                bool isH1Matched = candidate.isH1EmaMatched();
                if (isH1Matched) {
                    nextH1Count++;
                }

                if (candidate.isM1EmaMatched()) {
                    nextM1Count++;
                    if (isH1Matched) {
                        nextH1AndM1Count++;
                    }
                }
            }

            this.h1Tracker.observe(candidate, currencyStrengthEntryEmaH1,
                fromServerTime, fromNowMilliseconds);
            this.m1Tracker.observe(candidate, currencyStrengthEntryEmaM1,
                fromServerTime, fromNowMilliseconds);
            this.h1AndM1Tracker.observe(candidate, currencyStrengthEntryEmaH1AndM1,
                fromServerTime, fromNowMilliseconds);
        }

        this.h1Tracker.endUpdate();
        this.m1Tracker.endUpdate();
        this.h1AndM1Tracker.endUpdate();

        this.h1AndM1Count = nextH1AndM1Count;
        this.h1Count = nextH1Count;
        this.m1Count = nextM1Count;
        this.readyEmaMissing = nextReadyEmaMissing;
        this.h1EmaMissing = nextH1EmaMissing;
        this.m1EmaMissing = nextM1EmaMissing;
        this.countsAvailable = true;
        this.selectEffectiveMode();

        return true;
    }

    /**
     * 取得失敗時は集計とNEW追跡を中断し、直前の実効モードを保持する。
     * 次回の正常観測では各モードの成立状態を基準登録し直す。
     */
    void suspend() {
        this.h1Tracker.suspend();
        this.m1Tracker.suspend();
        this.h1AndM1Tracker.suspend();
        this.countsAvailable = false;
        this.readyEmaMissing = false;
        this.h1EmaMissing = false;
        this.m1EmaMissing = false;
        this.h1AndM1Count = 0;
        this.h1Count = 0;
        this.m1Count = 0;
        this.selectionPending = this.autoFallbackAllowed
            && this.configuredMode == currencyStrengthEntryEmaH1AndM1;
    }

    /**
     * 実効モードで観測した新規成立の表示期間が継続しているか取得する。
     *
     * @param fromSymbolName 正規化された通貨ペア名。
     * @param fromIsBuy BUY候補の場合true。
     * @param fromNowMilliseconds 現在の単調増加ミリ秒。
     * @return 実効モードで実際の新規成立を観測し、NEW期限内の場合true。
     */
    bool isNew(const string fromSymbolName, const bool fromIsBuy,
            const ulong fromNowMilliseconds) {
        if (this.effectiveMode == currencyStrengthEntryEmaM1) {
            return this.m1Tracker.isNew(fromSymbolName, fromIsBuy, fromNowMilliseconds);
        }

        if (this.effectiveMode == currencyStrengthEntryEmaH1AndM1) {
            return this.h1AndM1Tracker.isNew(fromSymbolName, fromIsBuy, fromNowMilliseconds);
        }

        return this.h1Tracker.isNew(fromSymbolName, fromIsBuy, fromNowMilliseconds);
    }

    /**
     * 実効モードの直近の新規成立検出時刻を取得する。
     *
     * @param fromSymbolName 正規化された通貨ペア名。
     * @param fromIsBuy BUY候補の場合true。
     * @return 実際の新規成立を観測したサーバー時刻。未検出は0。
     */
    datetime getDetectedAt(const string fromSymbolName, const bool fromIsBuy) {
        if (this.effectiveMode == currencyStrengthEntryEmaM1) {
            return this.m1Tracker.getDetectedAt(fromSymbolName, fromIsBuy);
        }

        if (this.effectiveMode == currencyStrengthEntryEmaH1AndM1) {
            return this.h1AndM1Tracker.getDetectedAt(fromSymbolName, fromIsBuy);
        }

        return this.h1Tracker.getDetectedAt(fromSymbolName, fromIsBuy);
    }

private:
    /** 保存対象のユーザー選択モード。 */
    CurrencyStrengthEntryEmaMode configuredMode;

    /** 現在のAND判定と表示に使用するモード。 */
    CurrencyStrengthEntryEmaMode effectiveMode;

    /** 通常チャートでM1補完を許可する場合true。 */
    bool autoFallbackAllowed;

    /** 未取得データのため実効モードの自動選択を保留している場合true。 */
    bool selectionPending;

    /** 全候補の件数とREADY候補のEMA取得状態を正常に確認済みの場合true。 */
    bool countsAvailable;

    /** READY候補にH1またはM1の未取得データがある場合true。 */
    bool readyEmaMissing;

    /** READY候補にH1の未取得データがある場合true。 */
    bool h1EmaMissing;

    /** READY候補にM1の未取得データがある場合true。 */
    bool m1EmaMissing;

    /** 全候補のH1＋M1成立件数。 */
    int h1AndM1Count;

    /** 全候補のH1成立件数。 */
    int h1Count;

    /** 全候補のM1成立件数。 */
    int m1Count;

    /** H1条件の成立変化。実効モードにかかわらず観測する。 */
    CurrencyStrengthEntryAndTracker h1Tracker;

    /** M1条件の成立変化。実効モードにかかわらず観測する。 */
    CurrencyStrengthEntryAndTracker m1Tracker;

    /** H1＋M1条件の成立変化。実効モードにかかわらず観測する。 */
    CurrencyStrengthEntryAndTracker h1AndM1Tracker;

    /**
     * 有効な集計からH1＋M1を優先し、正常評価で0件の場合だけM1へ補完する。
     * H1＋M1成立が1件でもあれば復帰し、未取得による0件では実効モードを保持する。
     */
    void selectEffectiveMode() {
        this.selectionPending = false;
        if (!this.autoFallbackAllowed
                || this.configuredMode != currencyStrengthEntryEmaH1AndM1) {
            this.effectiveMode = this.configuredMode;

            return;
        }

        if (!this.countsAvailable) {
            this.selectionPending = true;

            return;
        }

        if (this.h1AndM1Count > 0) {
            this.effectiveMode = currencyStrengthEntryEmaH1AndM1;

            return;
        }

        if (this.readyEmaMissing) {
            this.selectionPending = true;

            return;
        }

        this.effectiveMode = currencyStrengthEntryEmaH1AndM1;
        if (this.m1Count > 0) {
            this.effectiveMode = currencyStrengthEntryEmaM1;
        }
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_EMA_STATE_MQH
