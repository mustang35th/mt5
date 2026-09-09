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
#include <Mstng\ExpertAdvisor\H1EntryWaveDecision.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1ElliotStructureDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>

/**
 * H1を現在足としてMTF_3in3エントリーを判定する。
 *
 * D1とH4は売買方向の一致確認に使用し、H1とH4の第1波/3波、
 * または第3波に副次波がない有効な第5波をエントリー対象とする。
 * 方向一致、W1追加診断およびEMA200確認はMtf3In3H1Policyの固定設定を使い、
 * 呼び出し元の設定によってH1条件を上書きしない。
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
     */
    ExpertAdvisorMtf3In3H1(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true
    ) : ExpertAdvisorMTF_3in3(
        fromMarketContext,
        fromIsDrawArrow,
        Mtf3In3H1Policy::getW1ConfirmationMode(),
        Mtf3In3H1Policy::getDirectionAlignmentMode(),
        Mtf3In3H1Policy::getEma200ConfirmationMode()
    ) {
    }

protected:
    /**
     * H1エントリーのスプレッドが許容範囲内か判定する。
     *
     * @return スプレッドが5.0 pips以下の場合true。
     */
    virtual bool isSpread() override {
        return this.elliotAll.todayRate.spread <= 5.0;
    }

    /**
     * H1を基準に上位時間足のElliott売買方向を照合する。
     *
     * 共通ポリシーの方向条件を使い、取得不能、不正値および不一致を除外する。
     *
     * @return 共通H1方向一致条件を通過する場合true。
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
     * 共通ポリシーに従いH1、H4およびD1のEMA200方向を判定する。
     *
     * @return 共通EMA200方向条件を満たす場合true。
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
            this.elliotH4,
            this.elliotD1
        );
    }

    /**
     * W1方向とW1 EMA200方向をH1エントリー方向と照合する。
     *
     * 主条件と同じW1分析結果から診断を記録する。共通ポリシーの
     * OBSERVE_ONLYを使用し、追加確認によるエントリー制限は行わない。
     *
     * @return W1診断後にエントリー判定を継続する場合true。
     */
    virtual bool isTimeFrameHigherConfirmationConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_H1) {
            this.w1ConfirmationResult.reset();

            return false;
        }

        H1W1ConfirmationDecision decision;
        Elliot *elliotW1 = this.elliotAll.getElliot(PERIOD_W1);

        return decision.evaluate(
            this.h1W1ConfirmationMode,
            this.isBuy,
            elliotW1,
            this.w1ConfirmationResult
        );
    }

    /**
     * H1エントリー時のH1およびH4波動条件を判定する。
     *
     * H1を先に判定し、通過した場合だけH4を判定する。第1波と第3波は
     * 許可し、第5波は同じWaveの第3波に副次波がない場合だけ許可する。
     *
     * @param fromRejectReason 条件未達時の結果コード。
     * @return H1およびH4の波動条件を満たす場合true。
     */
    virtual bool isTimeFrameEntryConditionMatched(
        string &fromRejectReason
    ) override {
        fromRejectReason = "";

        if (this.marketContext.timeFrame != PERIOD_H1) {
            fromRejectReason = "H4_ELLIOT_UNAVAILABLE";

            return false;
        }

        H1EntryWaveDecision decision;
        H1EntryWaveResult h1Result;

        if (!decision.evaluate(
                this.elliotCurrent,
                PERIOD_H1,
                "ELLIOT_LABEL_REJECTED",
                "ELLIOT_LABEL_REJECTED",
                "H1_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
                h1Result
            )) {
            fromRejectReason = h1Result.rejectReason;

            return false;
        }

        H1EntryWaveResult h4Result;

        if (!decision.evaluate(
                this.elliotH4,
                PERIOD_H4,
                "H4_ELLIOT_UNAVAILABLE",
                "H4_ELLIOT_LABEL_REJECTED",
                "H4_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
                h4Result
            )) {
            fromRejectReason = h4Result.rejectReason;

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
     * H1の最新ラベルがEntry側で詳細判定する対象か確認する。
     *
     * 第5波の構造と第3波の副次波はisTimeFrameEntryConditionMatched()で
     * 判定し、その結果コードをエントリー対象外理由へ反映する。
     *
     * @return H1対象波の場合true。
     */
    virtual bool isEntryWave(Elliot *fromElliot) override {
        H1EntryWaveDecision decision;
        H1EntryWaveResult result;
        decision.evaluate(fromElliot, PERIOD_H1, result);

        return result.isEntryLabel;
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
