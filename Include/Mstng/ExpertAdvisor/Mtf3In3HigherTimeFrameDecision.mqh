#ifndef MSTNG_MTF3_IN3_HIGHER_TIME_FRAME_DECISION_MQH
#define MSTNG_MTF3_IN3_HIGHER_TIME_FRAME_DECISION_MQH

#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * H1とM5で共有するMN1・W1・D1のエントリー条件。
 * H1の既存診断順序を保つため、方向とD1 EMA200を個別にも判定できる。
 */
class Mtf3In3HigherTimeFrameDecision {
public:
    /**
     * エントリー方向を基準に上位足の全条件を判定する。
     *
     * @param fromElliotAll 分析済みの全時間足情報。
     * @param fromIsBuy BUYエントリーの場合true。
     * @param fromRejectReason 不成立理由。通過時は空文字。
     * @return 上位足の方向とD1 EMA200が条件を満たす場合true。
     */
    bool evaluate(ElliotAll *fromElliotAll, const bool fromIsBuy, string &fromRejectReason) {
        fromRejectReason = "HIGHER_ANALYSIS_UNAVAILABLE";

        if (fromElliotAll == NULL || !fromElliotAll.isAnalysisSucceeded) {
            return false;
        }

        Elliot *elliotCurrent = fromElliotAll.elliotCurrent;
        if (elliotCurrent == NULL
                || !this.isDirectionStateValid(elliotCurrent, elliotCurrent.marketContext.timeFrame)
                || elliotCurrent.isBuy != fromIsBuy) {
            fromRejectReason = "ENTRY_DIRECTION_INVALID";
            return false;
        }

        Elliot *elliotD1 = fromElliotAll.getElliot(PERIOD_D1);
        if (!this.evaluateDirection(fromIsBuy,
                fromElliotAll.getElliot(PERIOD_MN1),
                fromElliotAll.getElliot(PERIOD_W1), elliotD1, fromRejectReason)) {
            return false;
        }

        return this.evaluateD1Ema200(fromIsBuy, elliotD1, fromRejectReason);
    }

    /**
     * W1・D1一致と、MN1方向またはW1 EMA200の一致を判定する。
     * MN1一致時も、従来のH1と同じくW1 EMA200の整合性を必須とする。
     *
     * @param fromRejectReason 不成立理由。通過時は空文字。
     * @param fromOriginalD1 D1補正を明示検証した場合だけ渡す元D1。それ以外はNULL。
     * @return 上位足の方向条件を満たす場合true。
     */
    bool evaluateDirection(const bool fromIsBuy, Elliot *fromMn1, Elliot *fromW1,
            Elliot *fromD1, string &fromRejectReason, Elliot *fromOriginalD1 = NULL) {
        fromRejectReason = "";

        bool isD1Valid = this.isDirectionStateValid(fromD1, PERIOD_D1);
        if (fromOriginalD1 != NULL) {
            isD1Valid = this.isCorrectedDirectionStateValid(
                fromD1, fromOriginalD1, PERIOD_D1, fromIsBuy
            );
        }

        if (fromMn1 == NULL || fromW1 == NULL || fromD1 == NULL) {
            fromRejectReason = "HIGHER_TIMEFRAME_UNAVAILABLE";
        } else if (!this.isDirectionStateValid(fromMn1, PERIOD_MN1)
                || !this.isDirectionStateValid(fromW1, PERIOD_W1)
                || !isD1Valid) {
            fromRejectReason = "HIGHER_DIRECTION_INVALID";
        } else if (!this.isEma200StateValid(fromW1, PERIOD_W1)) {
            fromRejectReason = "W1_EMA200_INVALID";
        } else if (fromW1.isBuy != fromIsBuy) {
            fromRejectReason = "W1_DIRECTION_MISMATCH";
        } else if (fromD1.isBuy != fromIsBuy) {
            fromRejectReason = "D1_DIRECTION_MISMATCH";
        } else if (fromMn1.isBuy != fromIsBuy
                && !this.isEma200DirectionMatched(fromW1, PERIOD_W1, fromIsBuy)) {
            fromRejectReason = "MN1_OR_W1_EMA200_MISMATCH";
        }

        return fromRejectReason == "";
    }

    /**
     * D1 EMA200がエントリー方向と一致するか判定する。
     *
     * @param fromRejectReason 不成立理由。通過時は空文字。
     * @return D1 EMA200が有効かつ同方向の場合true。
     */
    bool evaluateD1Ema200(const bool fromIsBuy, Elliot *fromD1, string &fromRejectReason) {
        fromRejectReason = "";

        if (fromD1 == NULL) {
            fromRejectReason = "D1_EMA200_UNAVAILABLE";
        } else if (!this.isEma200StateValid(fromD1, PERIOD_D1)) {
            fromRejectReason = "D1_EMA200_INVALID";
        } else if (!this.isEma200DirectionMatched(fromD1, PERIOD_D1, fromIsBuy)) {
            fromRejectReason = "D1_EMA200_MISMATCH";
        }

        return fromRejectReason == "";
    }

    /**
     * Elliott方向値・ラベル・時間足の整合性を確認する。
     *
     * @return 従来のH1方向判定で有効な状態の場合true。
     */
    bool isDirectionStateValid(Elliot *fromElliot, const ENUM_TIMEFRAMES fromTimeFrame) {
        if (fromElliot == NULL
                || fromElliot.marketContext.timeFrame != fromTimeFrame
                || fromElliot.oscillator.marketContext.timeFrame != fromTimeFrame
                || fromElliot.isBuy != fromElliot.oscillator.isBuy) {
            return false;
        }

        if (fromElliot.isBuy) {
            return fromElliot.buySellLabel == "BUY";
        }

        return fromElliot.buySellLabel == "SELL";
    }

    /**
     * 明示補正した1足だけ、元Oscillator方向と異なる波動分析方向を許可する。
     *
     * 元分析の方向整合を必須とし、補正後のOscillatorは元の実測方向を保持する。
     * 通常の方向整合チェックを置き換えず、補正対象を検証した呼び出し元で使用する。
     *
     * @param fromElliot 補正後の対象時間足。
     * @param fromOriginal 補正前の同じ時間足。
     * @param fromTimeFrame 明示された補正時間足。
     * @param fromIsBuy 現在足を基準に指定した補正後方向。
     * @return 元方向と補正後方向が指定どおり整合する場合true。
     */
    bool isCorrectedDirectionStateValid(
        Elliot *fromElliot,
        Elliot *fromOriginal,
        const ENUM_TIMEFRAMES fromTimeFrame,
        const bool fromIsBuy
    ) {
        if (!this.isDirectionStateValid(fromOriginal, fromTimeFrame)
                || fromElliot == NULL || fromElliot == fromOriginal
                || fromElliot.marketContext.timeFrame != fromTimeFrame
                || fromElliot.oscillator.marketContext.timeFrame != fromTimeFrame
                || fromElliot.marketContext.symbolName != fromOriginal.marketContext.symbolName
                || fromElliot.oscillator.isBuy != fromOriginal.oscillator.isBuy
                || fromElliot.isBuy != fromIsBuy || fromOriginal.isBuy == fromIsBuy) {
            return false;
        }

        if (fromIsBuy) {
            return fromElliot.buySellLabel == "BUY";
        }

        return fromElliot.buySellLabel == "SELL";
    }

    /**
     * EMA200の時間足・排他的な方向フラグ・表示値を確認する。
     *
     * @return BUY、SELLまたはNONEとして整合する場合true。
     */
    bool isEma200StateValid(Elliot *fromElliot, const ENUM_TIMEFRAMES fromTimeFrame) {
        if (fromElliot == NULL
                || fromElliot.marketContext.timeFrame != fromTimeFrame
                || fromElliot.oscillator.marketContext.timeFrame != fromTimeFrame
                || fromElliot.oscillator.ema200.marketContext.timeFrame != fromTimeFrame) {
            return false;
        }

        bool isBuy = fromElliot.oscillator.ema200.isBuy;
        bool isSell = fromElliot.oscillator.ema200.isSell;
        string direction = fromElliot.oscillator.ema200.getBuySellLabel();
        if (isBuy && !isSell) {
            return direction == "BUY";
        }

        if (!isBuy && isSell) {
            return direction == "SELL";
        }

        if (!isBuy && !isSell) {
            return direction == "NONE";
        }

        return false;
    }

    /**
     * 有効なEMA200方向がエントリー方向と一致するか確認する。
     *
     * @return NONEを除き、指定方向と一致する場合true。
     */
    bool isEma200DirectionMatched(Elliot *fromElliot,
            const ENUM_TIMEFRAMES fromTimeFrame, const bool fromIsBuy) {
        if (!this.isEma200StateValid(fromElliot, fromTimeFrame)) {
            return false;
        }

        if (fromIsBuy) {
            return fromElliot.oscillator.ema200.isBuy;
        }

        return fromElliot.oscillator.ema200.isSell;
    }
};

#endif // MSTNG_MTF3_IN3_HIGHER_TIME_FRAME_DECISION_MQH
