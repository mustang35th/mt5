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
 * 明示的に有効化した場合だけ、D1・H4の片足逆方向を元H1方向へ補正する。
 * H1の最新ZigZagポイントは確定・未確定を問わず、
 * 通常版ZigZagElliot以外ではエントリー成立時にメール送信対象とする。
 */
class ExpertAdvisorMtf3In3H1 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     * @param fromDirectionCorrectionEnabled D1・H4の片足方向補正を使用する場合true。
     */
    ExpertAdvisorMtf3In3H1(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        bool fromDirectionCorrectionEnabled = false
    ) : ExpertAdvisorMTF_3in3(
        fromMarketContext,
        fromIsDrawArrow,
        Mtf3In3H1Policy::getW1ConfirmationMode(),
        Mtf3In3H1Policy::getDirectionAlignmentMode(),
        Mtf3In3H1Policy::getEma200ConfirmationMode()
    ) {
        this.isDirectionCorrectionEnabled = fromDirectionCorrectionEnabled;
        this.correctedElliotAll = NULL;
        this.correctedTimeFrame = PERIOD_CURRENT;
    }

    /**
     * 所有する補正分析を解放する。
     */
    ~ExpertAdvisorMtf3In3H1() {
        this.releaseCorrectedElliotAll();
    }

    /**
     * 直近の判定に採用した補正時間足を取得する。
     *
     * @return 補正分析の採用時はD1またはH4。それ以外はPERIOD_CURRENT。
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        if (this.correctedElliotAll != NULL && this.elliotAll == this.correctedElliotAll) {
            return this.correctedTimeFrame;
        }

        return PERIOD_CURRENT;
    }

protected:
    /**
     * 前回の補正分析を破棄し、今回の判定結果を初期化する。
     */
    virtual void resetStrategySpecificAnalysisOutcome() override {
        ExpertAdvisorMTF_3in3::resetStrategySpecificAnalysisOutcome();
        this.releaseCorrectedElliotAll();
    }

    /**
     * 元H1方向を基準にD1・H4の片足を補正し、全条件で使う分析を選択する。
     *
     * 両足同方向なら元分析、片足逆方向ならその足だけを補正したMN1～H1の
     * 再分析を採用する。両足逆方向、元方向不正および再分析失敗は除外する。
     * 無効設定では従来の分析をそのまま使用する。
     *
     * @param fromOriginal 元分析。所有権は呼び出し元が保持する。
     * @return 採用する分析への非所有参照。採用不能の場合NULL。
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        if (!this.isDirectionCorrectionEnabled) {
            return fromOriginal;
        }

        if (this.marketContext.timeFrame != PERIOD_H1
                || fromOriginal == NULL || !fromOriginal.isAnalysisSucceeded
                || fromOriginal.marketContext.timeFrame != PERIOD_H1
                || fromOriginal.marketContext.symbolName != this.marketContext.symbolName) {
            return NULL;
        }

        Elliot *originalD1 = fromOriginal.getElliot(PERIOD_D1);
        Elliot *originalH4 = fromOriginal.getElliot(PERIOD_H4);
        Elliot *originalH1 = fromOriginal.getElliot(PERIOD_H1);
        Mtf3In3HigherTimeFrameDecision decision;
        if (!decision.isDirectionStateValid(originalD1, PERIOD_D1)
                || !decision.isDirectionStateValid(originalH4, PERIOD_H4)
                || !decision.isDirectionStateValid(originalH1, PERIOD_H1)
                || fromOriginal.elliotCurrent != originalH1) {
            return NULL;
        }

        bool isD1Matched = originalD1.isBuy == originalH1.isBuy;
        bool isH4Matched = originalH4.isBuy == originalH1.isBuy;
        if (isD1Matched && isH4Matched) {
            return fromOriginal;
        }

        if (!isD1Matched && !isH4Matched) {
            return NULL;
        }

        ENUM_TIMEFRAMES correctionTimeFrame = PERIOD_H4;
        if (!isD1Matched) {
            correctionTimeFrame = PERIOD_D1;
        }

        this.correctedElliotAll = new ElliotAll(this.marketContext);
        if (this.correctedElliotAll == NULL
                || !this.correctedElliotAll.analyzeWithDirectionCorrection(
                    fromOriginal, correctionTimeFrame, originalH1.isBuy)) {
            this.logger.error(__FUNCTION__, "H1 corrected analysis failed");
            this.releaseCorrectedElliotAll();
            return NULL;
        }

        this.correctedTimeFrame = correctionTimeFrame;

        return this.correctedElliotAll;
    }

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

        ElliotAll *originalAnalysis = NULL;
        ENUM_TIMEFRAMES correctionTimeFrame = this.getCorrectionTimeFrame();
        if (correctionTimeFrame != PERIOD_CURRENT) {
            originalAnalysis = this.getSourceElliotAll();
        }

        return decision.evaluate(
            this.h1DirectionAlignmentMode,
            this.elliotAll,
            this.h1DirectionAlignmentResult,
            originalAnalysis,
            correctionTimeFrame
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
     * @return 通常版ZigZagElliot以外の場合true。
     */
    virtual bool shouldSendMail() override {
        return MQLInfoString(MQL_PROGRAM_NAME) != "ZigZagElliot";
    }

    /**
     * 元分析のD1、H4およびH1から既存履歴用のアラート文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    virtual string buildAlertText() override {
        return this.getH1AlertText(this.getSourceElliotAll());
    }

    /**
     * 判定に採用した構造ランクとD1・H4・H1の波動をチャートへ表示する。
     *
     * @return 採用した分析の文言。補正分析の場合は補正時間足を末尾へ付ける。
     */
    virtual string getChartAlertText() override {
        string chartAlertText = this.getH1AlertText(this.elliotAll, true);
        ENUM_TIMEFRAMES correctionTimeFrame = this.getCorrectionTimeFrame();
        if (chartAlertText != "" && correctionTimeFrame != PERIOD_CURRENT) {
            chartAlertText += " [" + TimeUtil::convertTimeFrameToString(correctionTimeFrame) + "C]";
        }

        return chartAlertText;
    }

    /**
     * 補正採用時は画面と同じ件名、および補正前後の全分析をメールへ渡す。
     */
    virtual void sendAlertMail() override {
        ElliotAll *sourceAnalysis = this.getSourceElliotAll();
        ENUM_TIMEFRAMES correctionTimeFrame = this.getCorrectionTimeFrame();
        if (correctionTimeFrame != PERIOD_CURRENT) {
            Mail::sendMail(sourceAnalysis, this.isSendMail, this.elliotAll,
                correctionTimeFrame, this.getChartAlertText());
            return;
        }

        Mail::sendMail(sourceAnalysis, this.isSendMail);
    }

private:
    /** D1・H4の片足方向補正を明示的に使用する場合true。 */
    bool isDirectionCorrectionEnabled;

    /** 全条件の判定に採用する補正分析。本クラスが所有する。 */
    ElliotAll *correctedElliotAll;

    /** 補正分析で方向を変更した時間足。補正なしはPERIOD_CURRENT。 */
    ENUM_TIMEFRAMES correctedTimeFrame;

    /**
     * 指定したH1分析から構造ランクと3足の波動文言を生成する。
     *
     * @param fromAnalysis 元分析または判定用の補正分析。
     * @param fromIncludeOriginal 再カウント前の主波ラベルを併記する場合true。
     * @return アラート文言。分析未採用の場合は空文字列。
     */
    string getH1AlertText(ElliotAll *fromAnalysis, const bool fromIncludeOriginal = false) {
        if (fromAnalysis == NULL) {
            return "";
        }

        Mtf3In3H1ElliotStructureDecision structureDecision;
        Mtf3In3H1ElliotStructureResult structureResult;
        structureDecision.evaluate(fromAnalysis, structureResult);

        return "H1[" + structureResult.getDisplayLabel()
            + "] " + this.getThreeTimeFrameAlertText(fromAnalysis, fromIncludeOriginal);
    }

    /**
     * 所有する補正分析を解放し、次回への持ち越しを防止する。
     */
    void releaseCorrectedElliotAll() {
        if (this.correctedElliotAll != NULL) {
            delete this.correctedElliotAll;
            this.correctedElliotAll = NULL;
        }
        this.correctedTimeFrame = PERIOD_CURRENT;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_H1_MQH
