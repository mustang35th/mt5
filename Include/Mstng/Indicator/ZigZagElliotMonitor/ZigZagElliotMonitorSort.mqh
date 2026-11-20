#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_SORT_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_SORT_MQH

#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSymbolState.mqh>

/**
 * 監視一覧のソート設定を保持し、2通貨の表示順を比較する。
 * 取得や分析は行わず、保持済みの判定・順位・成立時刻だけを参照する。
 */
class ZigZagElliotMonitorSort {
public:
    /**
     * 通貨名の昇順と、現在足のENTRY優先を初期設定にする。
     */
    ZigZagElliotMonitorSort() {
        this.reset();
    }

    /**
     * 通貨名の昇順とENTRY優先へ戻す。
     */
    void reset() {
        this.columnIndex = 0;
        this.ascending = true;
        this.entryPriority = true;
    }

    /**
     * ソート列を選択し、同じ列の場合は昇順と降順を切り替える。
     * 別の列は通貨名・判定が昇順、順位差と成立時刻は降順から開始する。
     *
     * @param fromColumnIndex 通貨0、判定1、長中期3、中短期4、直近成立5。
     * @return 選択できる列の場合true。それ以外は設定を変更せずfalse。
     */
    bool selectColumn(const int fromColumnIndex) {
        bool sameColumn = this.columnIndex == fromColumnIndex;
        if (!this.setColumn(fromColumnIndex)) {
            return false;
        }

        if (sameColumn) {
            this.toggleDirection();
        }

        return true;
    }

    /**
     * コンボボックスから列を選択し、同じ列では現在の昇降順を維持する。
     *
     * @param fromColumnIndex 通貨0、判定1、長中期3、中短期4、直近成立5。
     * @return 有効な列の場合true。無効な列では設定を変更せずfalse。
     */
    bool setColumn(const int fromColumnIndex) {
        if (fromColumnIndex != 0 && fromColumnIndex != 1 && fromColumnIndex != 3
                && fromColumnIndex != 4 && fromColumnIndex != 5) {
            return false;
        }

        if (this.columnIndex == fromColumnIndex) {
            return true;
        }

        this.columnIndex = fromColumnIndex;
        this.ascending = fromColumnIndex == 0 || fromColumnIndex == 1;

        return true;
    }

    /**
     * 選択列を変えずに昇順と降順を切り替える。
     */
    void toggleDirection() {
        this.ascending = !this.ascending;
    }

    /**
     * 現在足で成立したENTRYを先頭へまとめる設定を切り替える。
     */
    void toggleEntryPriority() {
        this.entryPriority = !this.entryPriority;
    }

    /**
     * 選択中のソート列を返す。
     */
    int getColumnIndex() const {
        return this.columnIndex;
    }

    /**
     * 選択列を昇順に表示する場合trueを返す。
     */
    bool isAscending() const {
        return this.ascending;
    }

    /**
     * 現在足のENTRYを優先表示する場合trueを返す。
     */
    bool isEntryPriority() const {
        return this.entryPriority;
    }

    /**
     * 現在のソート設定で、対象通貨を比較相手より前に表示するか返す。
     * 未取得の順位と未成立の時刻は昇降にかかわらず末尾へ置く。
     * 判定列では現在足を先に並べ、前回判定と未確認をこの順で末尾へ置く。
     * 選択キーが同値の場合は通貨名の昇順とし、同名なら順序を保つ。
     *
     * @param fromCurrent 移動を検討する通貨。
     * @param fromPrevious 比較相手の通貨。
     * @param fromTargetM1BarTime 一覧が現在扱っている共通M1開始時刻。
     * @return 対象通貨を比較相手より前に表示する場合true。
     */
    bool comesBefore(const ZigZagElliotMonitorSymbolState &fromCurrent,
            const ZigZagElliotMonitorSymbolState &fromPrevious,
            const datetime fromTargetM1BarTime) const {
        if (this.columnIndex == 1) {
            return this.isJudgmentBefore(fromCurrent, fromPrevious, fromTargetM1BarTime);
        }

        if (this.entryPriority) {
            bool currentEntry = this.isCurrentEntry(fromCurrent, fromTargetM1BarTime);
            bool previousEntry = this.isCurrentEntry(fromPrevious, fromTargetM1BarTime);
            if (currentEntry != previousEntry) {
                return currentEntry;
            }
        }

        int nameComparison = StringCompare(fromCurrent.canonicalSymbolName,
            fromPrevious.canonicalSymbolName);
        if (this.columnIndex == 0) {
            if (this.ascending) {
                return nameComparison < 0;
            }

            return nameComparison > 0;
        }

        if (this.columnIndex == 3 || this.columnIndex == 4) {
            bool longMedium = this.columnIndex == 3;
            bool currentAvailable = this.hasCurrentRanks(fromCurrent, longMedium, fromTargetM1BarTime);
            bool previousAvailable = this.hasCurrentRanks(fromPrevious, longMedium, fromTargetM1BarTime);
            if (currentAvailable != previousAvailable) {
                return currentAvailable;
            }

            if (currentAvailable) {
                int currentDifference = fromCurrent.result.strength.getRankDifference(longMedium);
                int previousDifference = fromPrevious.result.strength.getRankDifference(longMedium);
                if (currentDifference != previousDifference) {
                    return this.isValueBefore(currentDifference, previousDifference);
                }
            }
        } else if (this.columnIndex == 5) {
            bool currentAvailable = fromCurrent.lastEntryTime > 0;
            bool previousAvailable = fromPrevious.lastEntryTime > 0;
            if (currentAvailable != previousAvailable) {
                return currentAvailable;
            }

            if (currentAvailable && fromCurrent.lastEntryTime != fromPrevious.lastEntryTime) {
                return this.isValueBefore(fromCurrent.lastEntryTime, fromPrevious.lastEntryTime);
            }
        }

        return nameComparison < 0;
    }

private:
    /** ソート対象列。 */
    int columnIndex;

    /** 選択列を昇順で比較する場合true。 */
    bool ascending;

    /** 現在足のENTRYを選択列より先に比較する場合true。 */
    bool entryPriority;

    /**
     * 判定列の現在足・前回足・未確認を区別し、同じ判定内は通貨名順に並べる。
     */
    bool isJudgmentBefore(const ZigZagElliotMonitorSymbolState &fromCurrent,
            const ZigZagElliotMonitorSymbolState &fromPrevious,
            const datetime fromTargetM1BarTime) const {
        int currentAge = this.getJudgmentAge(fromCurrent, fromTargetM1BarTime);
        int previousAge = this.getJudgmentAge(fromPrevious, fromTargetM1BarTime);
        if (currentAge != previousAge) {
            return currentAge < previousAge;
        }

        int nameComparison = StringCompare(fromCurrent.canonicalSymbolName,
            fromPrevious.canonicalSymbolName);
        if (currentAge != 0) {
            return nameComparison < 0;
        }

        if (this.entryPriority) {
            bool currentEntry = this.isCurrentEntry(fromCurrent, fromTargetM1BarTime);
            bool previousEntry = this.isCurrentEntry(fromPrevious, fromTargetM1BarTime);
            if (currentEntry != previousEntry) {
                return currentEntry;
            }
        }

        int currentPriority = this.getJudgmentPriority(fromCurrent);
        int previousPriority = this.getJudgmentPriority(fromPrevious);
        if (currentPriority != previousPriority) {
            return this.isValueBefore(currentPriority, previousPriority);
        }

        return nameComparison < 0;
    }

    /**
     * 結果自身の時刻から、現在足0・前回足1・未確認2を返す。
     * 足未取得の待機・エラーだけは結果の確認時刻をM1へ丸めて使う。
     * 分析開始時に先行更新されるlastAttemptBarTimeは参照しない。
     */
    int getJudgmentAge(const ZigZagElliotMonitorSymbolState &fromState,
            const datetime fromTargetM1BarTime) const {
        if (fromState.result.evaluatedAtSrv <= 0) {
            return 2;
        }

        if (fromTargetM1BarTime <= 0) {
            return 1;
        }

        datetime resultBarTime = fromState.result.barTime;
        if (resultBarTime == 0) {
            if (fromState.result.status != ZIGZAG_MONITOR_WAITING
                    && fromState.result.status != ZIGZAG_MONITOR_ERROR) {
                return 1;
            }

            resultBarTime = fromState.result.evaluatedAtSrv - fromState.result.evaluatedAtSrv % 60;
        }

        if (resultBarTime == fromTargetM1BarTime) {
            return 0;
        }

        return 1;
    }

    /**
     * 現在足の判定を、ENTRY・M1未達・確認済み・強弱未達・待機・エラーの順に分類する。
     * 確認済みは同じシグナルの確認を表し、ENTRY成立済みとは扱わない。
     */
    int getJudgmentPriority(const ZigZagElliotMonitorSymbolState &fromState) const {
        if (fromState.result.status == ZIGZAG_MONITOR_ENTRY && fromState.result.completed) {
            return 0;
        }

        if (fromState.result.status == ZIGZAG_MONITOR_NOT_MATCHED) {
            if (fromState.result.shortMessage == "M1未達") {
                return 1;
            }

            if (fromState.result.shortMessage == "確認済み") {
                return 2;
            }

            return 3;
        }

        if (fromState.result.status == ZIGZAG_MONITOR_ERROR) {
            return 5;
        }

        return 4;
    }

    /**
     * 共通M1枠で判定を完了したENTRYか確認する。
     */
    bool isCurrentEntry(const ZigZagElliotMonitorSymbolState &fromState,
            const datetime fromTargetM1BarTime) const {
        return fromTargetM1BarTime > 0 && fromState.result.completed
            && fromState.result.status == ZIGZAG_MONITOR_ENTRY
            && fromState.result.barTime == fromTargetM1BarTime;
    }

    /**
     * 指定期間の順位が共通M1枠に対応するM5枠で取得済みか確認する。
     */
    bool hasCurrentRanks(const ZigZagElliotMonitorSymbolState &fromState,
            const bool fromLongMedium, const datetime fromTargetM1BarTime) const {
        if (fromTargetM1BarTime <= 0) {
            return false;
        }

        datetime targetM5BarTime = fromTargetM1BarTime - fromTargetM1BarTime % 300;

        return fromState.result.strength.targetM5BarTime == targetM5BarTime
            && fromState.result.strength.hasRanks(fromLongMedium);
    }

    /**
     * 異なる有効値を、選択した昇順または降順で比較する。
     */
    bool isValueBefore(const long fromCurrent, const long fromPrevious) const {
        if (this.ascending) {
            return fromCurrent < fromPrevious;
        }

        return fromCurrent > fromPrevious;
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_SORT_MQH
