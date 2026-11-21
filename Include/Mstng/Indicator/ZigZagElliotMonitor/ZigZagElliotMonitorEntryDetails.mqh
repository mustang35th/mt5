#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_ENTRY_DETAILS_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_ENTRY_DETAILS_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>

/**
 * 監視したM1で実際に評価した条件と値を保持する。停止位置で未評価と未達を区別する。
 */
struct ZigZagElliotMonitorEntryDetails {
    /** 詳細表示用の最初の未達理由。空なら今回の判定・待機状態を表示する。 */
    string reason;

    /** 事前判定で長中期の逆行1を許容した場合true。 */
    bool longMediumPullback;

    /** 安定したM1判定で確定した同一シグナルの回数。未評価の場合0。 */
    int signalCount;

    /** 共通戦略のシグナル条件が止まった位置。 */
    Mtf3In3JudgeStep judgeStep;

    /** 採用した分析のスプレッド（pips）。 */
    double spreadPips;

    /** 採用したM1のGMMAトレンド判定に使ったカウント。 */
    int gmmaTrendCount;

    /** 採用したM1のGMMAクロス判定に使ったカウント。 */
    int gmmaCrossCount;

    /**
     * 未評価状態で生成する。
     */
    ZigZagElliotMonitorEntryDetails() {
        this.reset();
    }

    /**
     * 前回の評価結果を破棄する。
     */
    void reset() {
        this.reason = "";
        this.longMediumPullback = false;
        this.signalCount = 0;
        this.judgeStep = MTF3IN3_JUDGE_NOT_EVALUATED;
        this.spreadPips = 0.0;
        this.gmmaTrendCount = 0;
        this.gmmaCrossCount = 0;
    }

    /**
     * 元分析前に、両期間の順位方向、長中期増減、中短期増減の順で確認する。
     * 順位方向が一致すれば候補方向は一意になる。
     */
    bool checkStrength(const CurrencyStrengthExecutionInfo &fromInfo) {
        this.reason = "";
        this.longMediumPullback = false;
        bool isBuy = fromInfo.getLongMediumRankDifference() > 0;
        if (!fromInfo.isDirectionAligned(isBuy)) {
            if (fromInfo.getLongMediumRankDifference() == 0) {
                this.reason = "長中期順位差0";
            } else if (fromInfo.getMediumShortRankDifference() == 0) {
                this.reason = "中短期順位差0";
            } else {
                this.reason = "強弱の方向不一致";
            }

            return false;
        }

        if (!fromInfo.isLongMediumGapDirectionMatched(isBuy, true)) {
            this.reason = "長中期増減が逆";
            if (fromInfo.longMediumGapDirection.direction == 0) {
                this.reason = "長中期増減不明";
            }

            return false;
        }

        this.longMediumPullback = fromInfo.isM1LongMediumPullbackApplied(isBuy);
        if (!fromInfo.mediumShortGapDirection.isMatched(isBuy)) {
            this.reason = "中短期増減が逆";
            if (fromInfo.mediumShortGapDirection.direction == 0) {
                this.reason = "中短期増減不明";
            }

            return false;
        }

        return true;
    }

    /**
     * 同じ足の安定した戦略結果から、到達した条件の値だけをコピーする。
     *
     * @param fromAdopted 戦略が実際に採用した元または補正分析。未採用ならNULL。
     * @param fromStep 共通戦略の停止位置。
     * @param fromDirectionMatched 通貨強弱の候補方向とM1の方向が一致する場合true。
     */
    void capture(ElliotAll *fromAdopted, const Mtf3In3JudgeStep fromStep,
            const bool fromDirectionMatched) {
        if (fromAdopted == NULL) {
            this.judgeStep = MTF3IN3_JUDGE_NOT_EVALUATED;
            this.reason = "方向・補正未採用";
            return;
        }

        this.judgeStep = fromStep;
        if (this.spreadEvaluated()) {
            this.spreadPips = fromAdopted.todayRate.spread;
        }

        if (this.gmmaTrendEvaluated()) {
            this.gmmaTrendCount = fromAdopted.elliotCurrent.oscillator.gmmaTrendCount;
        }

        if (this.gmmaCrossEvaluated()) {
            this.gmmaCrossCount = fromAdopted.elliotCurrent.oscillator.gmmaCrossCount;
        }

        if (fromStep == MTF3IN3_JUDGE_NOT_EVALUATED && !fromDirectionMatched) {
            this.reason = "強弱とM1方向が逆";
            return;
        }

        this.reason = this.getJudgeReason();
    }

    /**
     * スプレッドの条件に到達したか返す。
     */
    bool spreadEvaluated() const {
        return this.judgeStep >= MTF3IN3_JUDGE_SPREAD;
    }

    /**
     * スプレッドを判定して通過したか返す。
     */
    bool spreadMatched() const {
        return this.judgeStep > MTF3IN3_JUDGE_SPREAD;
    }

    /**
     * M1 ZigZagの条件に到達したか返す。
     */
    bool zigZagEvaluated() const {
        return this.judgeStep >= MTF3IN3_JUDGE_ZIGZAG;
    }

    /**
     * M1 ZigZagを判定して通過したか返す。
     */
    bool zigZagMatched() const {
        return this.judgeStep > MTF3IN3_JUDGE_ZIGZAG;
    }

    /**
     * M1 GMMAトレンドの条件に到達したか返す。
     */
    bool gmmaTrendEvaluated() const {
        return this.judgeStep >= MTF3IN3_JUDGE_GMMA_TREND;
    }

    /**
     * M1 GMMAトレンドを判定して通過したか返す。
     */
    bool gmmaTrendMatched() const {
        return this.judgeStep > MTF3IN3_JUDGE_GMMA_TREND;
    }

    /**
     * M1 GMMAクロスの条件に到達したか返す。
     */
    bool gmmaCrossEvaluated() const {
        return this.judgeStep >= MTF3IN3_JUDGE_GMMA_CROSS;
    }

    /**
     * M1 GMMAクロスを判定して通過したか返す。
     */
    bool gmmaCrossMatched() const {
        return this.judgeStep > MTF3IN3_JUDGE_GMMA_CROSS;
    }

private:
    /**
     * M1で最初に未達となったシグナル条件の表示名を返す。
     */
    string getJudgeReason() const {
        switch (this.judgeStep) {
            case MTF3IN3_JUDGE_SPREAD:
                return "スプレッド超過";
            case MTF3IN3_JUDGE_WAVE_DIRECTION:
                return "M1波方向不一致";
            case MTF3IN3_JUDGE_ANALYSIS_DIRECTION:
            case MTF3IN3_JUDGE_DIRECTION_ALIGNMENT:
                return "時間足の方向不一致";
            case MTF3IN3_JUDGE_ZIGZAG:
                return "M1 ZigZag追加中";
            case MTF3IN3_JUDGE_WAVE:
                return "M5/M1波動未達";
            case MTF3IN3_JUDGE_GMMA_TREND:
                return "GMMAトレンド未達";
            case MTF3IN3_JUDGE_GMMA_CROSS:
                return "GMMAクロス未達";
            case MTF3IN3_JUDGE_NOT_EVALUATED:
                return "M1判定未実行";
            default:
                return "";
        }
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_ENTRY_DETAILS_MQH
