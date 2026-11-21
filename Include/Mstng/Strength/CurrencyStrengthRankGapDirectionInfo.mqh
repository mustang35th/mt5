#ifndef MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_INFO_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_INFO_MQH

#include <Mstng\Util\TimeUtil.mqh>

/**
 * 1集計期間の順位差の直近増減方向と、分析時の取得状態を保持する。
 */
struct CurrencyStrengthRankGapDirectionInfo {
    /** この集計期間の増減情報を評価する場合true。判定フィルタの有効設定とは独立。 */
    bool enabled;

    /** 現在または直前M5の取得待ちで、同じ枠内の再確認が必要な場合true。 */
    bool waiting;

    /** 判定対象時刻の現在順位差を保持している場合true。 */
    bool currentAvailable;

    /** 直前M5の順位差を保持している場合true。 */
    bool hasPrevious;

    /** 直近の増減方向。上昇1、下降-1、不明0。 */
    int direction;

    /** 判定対象M5時刻の選択集計期間の順位差。 */
    int currentGap;

    /** 直前M5時刻の選択集計期間の順位差。 */
    int previousGap;

    /** 直近のゼロでない変化の前後値を保持している場合true。 */
    bool lastChangeAvailable;

    /** directionChangedAtの変化直前の順位差。 */
    int lastChangeBeforeGap;

    /** directionChangedAtの変化直後の順位差。 */
    int lastChangeAfterGap;

    /** 判定対象となるM5開始時刻。 */
    datetime targetM5BarTime;

    /** 直近の増減が発生したM5開始時刻。方向不明の場合0。 */
    datetime directionChangedAt;

    /**
     * 増減情報を評価しない状態へ戻す。
     */
    void reset() {
        this.enabled = false;
        this.waiting = false;
        this.currentAvailable = false;
        this.hasPrevious = false;
        this.direction = 0;
        this.currentGap = 0;
        this.previousGap = 0;
        this.lastChangeAvailable = false;
        this.lastChangeBeforeGap = 0;
        this.lastChangeAfterGap = 0;
        this.targetM5BarTime = 0;
        this.directionChangedAt = 0;
    }

    /**
     * 現在の順位差と、横ばいへ引き継いだ直近増減方向が売買方向に合うか返す。
     *
     * @param fromIsBuy BUYの判定である場合true。
     * @return 未使用、またはデータがそろい両方向が一致する場合true。
     */
    bool isMatched(const bool fromIsBuy) const {
        if (!this.enabled) {
            return true;
        }

        if (this.waiting || !this.currentAvailable || !this.hasPrevious
                || this.targetM5BarTime <= 0 || this.directionChangedAt <= 0) {
            return false;
        }

        if (fromIsBuy) {
            return this.currentGap > 0 && this.direction == 1;
        }

        return this.currentGap < 0 && this.direction == -1;
    }

    /**
     * 現在順位と整合する、最後に順位差が変わったM5の増減を返す。
     * 横ばいの間はその変化を保持し、根拠がない場合は0を返す。
     */
    int getLastGapChange() const {
        if (!this.enabled || this.waiting || !this.currentAvailable || !this.hasPrevious
                || !this.lastChangeAvailable || this.targetM5BarTime % 300 != 0
                || this.directionChangedAt <= 300 || this.directionChangedAt > this.targetM5BarTime
                || this.directionChangedAt % 300 != 0 || this.lastChangeAfterGap != this.currentGap
                || this.lastChangeBeforeGap < -7 || this.lastChangeBeforeGap > 7
                || this.lastChangeAfterGap < -7 || this.lastChangeAfterGap > 7) {
            return 0;
        }

        int change = this.lastChangeAfterGap - this.lastChangeBeforeGap;
        if ((this.direction == 1 && change > 0) || (this.direction == -1 && change < 0)) {
            return change;
        }

        return 0;
    }

    /**
     * M1の長中期で、売買方向の順位差が4以上残った直近1順位の逆行を許容する。
     */
    bool isM1LongMediumPullbackAllowed(const bool fromIsBuy) const {
        if (fromIsBuy) {
            return this.currentGap >= 4 && this.getLastGapChange() == -1;
        }

        return this.currentGap <= -4 && this.getLastGapChange() == 1;
    }

    /**
     * M1の長中期で逆行1を許容した理由を、判定に使用した前後の順位差で示す。
     */
    string getM1LongMediumPullbackText() const {
        return StringFormat("長中期は逆行1を許容（%+d → %+d）",
            this.lastChangeBeforeGap, this.lastChangeAfterGap);
    }

    /**
     * 取得待ちと判定済みの方向不明を区別した表示文字列を返す。
     */
    string getStateText() const {
        if (!this.enabled) {
            return "OFF";
        }

        if (this.waiting) {
            return "データ待ち";
        }

        if (this.direction == 1) {
            return "上昇維持";
        }

        if (this.direction == -1) {
            return "下降維持";
        }

        return "方向不明";
    }

    /**
     * 判定で使った順位差と根拠時刻を、表示するときだけ文字列化する。
     *
     * @param fromLongMedium 長中期の説明の場合true、中短期の場合false。
     */
    string getTooltip(const bool fromLongMedium = true) const {
        string periodLabel = "長中期";
        if (!fromLongMedium) {
            periodLabel = "中短期";
        }

        if (!this.enabled) {
            return periodLabel + "増減フィルタ：OFF";
        }

        string text = periodLabel + "増減フィルタ：" + this.getStateText()
            + "\nM5単位・横ばいは直近方向を維持・履歴上限30日";
        if (this.currentAvailable) {
            text += StringFormat("\n現在の順位差：%+d", this.currentGap);
        }

        if (this.hasPrevious) {
            text += StringFormat(" / 直前M5：%+d / 変化：%+d",
                this.previousGap, this.currentGap - this.previousGap);
        }

        if (this.targetM5BarTime > 0) {
            text += "\n判定対象：" + TimeUtil::formatYyyymmddhhmiss(this.targetM5BarTime) + " SRV";
        }

        if (this.directionChangedAt > 0) {
            text += "\n増減の根拠：" + TimeUtil::formatYyyymmddhhmiss(this.directionChangedAt) + " SRV";
        } else if (!this.waiting) {
            text += "\n欠損・5分枠の途切れ、または30日以内に増減なし";
        }

        return text;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_INFO_MQH
