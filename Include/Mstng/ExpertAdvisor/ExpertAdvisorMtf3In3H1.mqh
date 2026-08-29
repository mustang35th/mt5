//+------------------------------------------------------------------+
//|                                       ExpertAdvisorMtf3In3H1.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_H1_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_H1_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentDecision.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationDecision.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1ElliotStructureDecision.mqh>

/**
 * H1を現在足としてMTF_3in3エントリーを判定する。
 *
 * D1とH4は売買方向の一致確認に使用し、H1の第1波/3波/5波を
 * エントリー対象波動とする。H4は第1波/3波、または第3波に
 * 副次波がある第5波を対象とする。H1 EMA200は常にH1方向を確認し、
 * H1_AND_H4_REQUIREDではH4 EMA200も同方向を要求する。
 * 選択した方向一致モードではW1 EMA200も判定に使用する。
 * H1の最新ZigZagポイントは確定・未確定を問わず、
 * エントリー成立時はメール送信対象とする。
 */
class ExpertAdvisorMtf3In3H1 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード。
     * @param fromH1DirectionAlignmentMode H1エントリーの方向一致モード。
     * @param fromH1Ema200ConfirmationMode H1エントリーのEMA200確認モード。
     */
    ExpertAdvisorMtf3In3H1(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1DirectionAlignmentMode fromH1DirectionAlignmentMode =
            H1_DIRECTION_ALIGNMENT_D1_TO_H1,
        H1Ema200ConfirmationMode fromH1Ema200ConfirmationMode =
            H1_EMA200_CONFIRMATION_H1_ONLY
    ) : ExpertAdvisorMTF_3in3(
        fromMarketContext,
        fromIsDrawArrow,
        fromH1W1ConfirmationMode,
        fromH1DirectionAlignmentMode,
        fromH1Ema200ConfirmationMode
    ) {
    }

protected:
    /**
     * H1を基準に上位時間足のElliott売買方向を照合する。
     *
     * OBSERVEでは診断結果だけを保持し、REQUIREDでは取得不能、
     * 不正値または選択モードの方向条件不一致をエントリーから除外する。
     *
     * @return 選択されたH1方向一致モードのゲートを通過する場合true。
     */
    virtual bool isTimeFrameDirectionAlignmentConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            this.h1DirectionAlignmentResult.reset();

            return false;
        }

        H1DirectionAlignmentDecision decision;

        return decision.evaluate(
            this.h1DirectionAlignmentMode,
            this.elliotAll,
            this.h1DirectionAlignmentResult
        );
    }

    /**
     * H1の波動条件を共通Judgeでは判定しない。
     *
     * H1およびH4の波動条件はEntry側で判定する。
     *
     * @return H1の場合true。それ以外の場合false。
     */
    virtual bool isTimeFrameWaveConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            return false;
        }

        return true;
    }

    /**
     * H1では最新ZigZagポイントの確定状態を条件に使用しない。
     *
     * @return H1の場合true。それ以外の場合false。
     */
    virtual bool isTimeFrameZigZagConfirmedConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            return false;
        }

        return true;
    }

    /**
     * 選択モードに従いH1およびH4のEMA200方向を判定する。
     *
     * @return 選択モードのEMA200方向条件を満たす場合true。
     */
    virtual bool isTimeFrameEma200ConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            return false;
        }

        H1Ema200ConfirmationDecision decision;

        return decision.evaluate(
            this.h1Ema200ConfirmationMode,
            this.isBuy,
            this.elliotCurrent,
            this.elliotH4
        );
    }

    /**
     * W1方向とW1 EMA200方向をH1エントリー方向と照合する。
     *
     * OBSERVE_ONLYではOR条件の診断結果を保持しつつ、エントリー判定は
     * 制限しない。強制モードではW1取得不能または不正値を拒否する。
     *
     * @return 選択されたW1確認モードのゲートを通過する場合true。
     */
    virtual bool isTimeFrameHigherConfirmationConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            this.w1ConfirmationResult.reset();

            return false;
        }

        H1W1ConfirmationDecision decision;
        Elliot *elliotW1 =
            this.elliotAll.getH1W1ConfirmationElliot();

        if (elliotW1 == NULL) {
            elliotW1 = this.elliotAll.getElliot(PERIOD_W1);
        }

        return decision.evaluate(
            this.h1W1ConfirmationMode,
            this.isBuy,
            elliotW1,
            this.w1ConfirmationResult
        );
    }

    /**
     * H1エントリー時のH4波動条件を判定する。
     *
     * H4の第1波および第3波はそのまま許可する。第5波は、第3波に
     * 副次波がある場合だけ許可する。
     *
     * @param fromRejectReason 条件未達時の結果コード。
     * @return H4波動条件を満たす場合true。
     */
    virtual bool isTimeFrameEntryConditionMatched(
        string &fromRejectReason
    ) override {
        fromRejectReason = "";

        if (this.marketContext.timeFrame != PERIOD_H1
                || this.elliotH4 == NULL
                || this.elliotH4.marketContext.timeFrame != PERIOD_H4) {
            fromRejectReason = "H4_ELLIOT_UNAVAILABLE";

            return false;
        }

        Wave *latestWave = this.elliotH4.getLatestWave();
        ZigZagPoint *latestPoint = this.elliotH4.getLatestPoint();

        if (latestWave == NULL || latestPoint == NULL) {
            fromRejectReason = "H4_ELLIOT_UNAVAILABLE";

            return false;
        }

        string elliotLabel = latestPoint.elliotLabel;

        if (elliotLabel == "1" || elliotLabel == "3") {
            return true;
        }

        if (elliotLabel != "5") {
            fromRejectReason = "H4_ELLIOT_LABEL_REJECTED";

            return false;
        }

        if (!latestWave.hasSubElliot(5, 3)) {
            fromRejectReason = "H4_WAVE3_SUB_ELLIOT_REJECTED";

            return false;
        }

        return true;
    }

    /**
     * H1では現在足とEMA200の距離制限を使用しない。
     *
     * @return 常にfalse。
     */
    virtual bool isTimeFrameEma200DistanceRequired() override {
        return false;
    }

    /**
     * H1対象波動判定を第1波/第3波/第5波に拡張する。
     *
     * @return H1対象波の場合true。
     */
    virtual bool isEntryWave(Elliot *fromElliot) override {
        if (fromElliot == NULL) {
            return false;
        }

        ZigZagPoint *latestPoint = fromElliot.getLatestPoint();
        if (latestPoint == NULL) {
            return false;
        }

        string elliotLabel = latestPoint.elliotLabel;

        return elliotLabel == "1"
            || elliotLabel == "3"
            || elliotLabel == "5";
    }

    /**
     * H1エントリー成立時にメールを送信するか判定する。
     *
     * @return 常にtrue。
     */
    virtual bool shouldSendMail() override {
        return true;
    }

    /**
     * D1、H4およびH1の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    virtual string buildAlertText() override {
        Mtf3In3H1ElliotStructureDecision structureDecision;
        Mtf3In3H1ElliotStructureResult structureResult;
        structureDecision.evaluate(this.elliotAll, structureResult);

        return "H1[" + structureResult.getDisplayLabel()
            + "] " + this.getThreeTimeFrameAlertText();
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_H1_MQH
