//+------------------------------------------------------------------+
//|                                       ExpertAdvisorMtf3In3M5.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M5_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M5_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3HigherTimeFrameDecision.mqh>

/**
 * M5を現在足としてMTF_3in3エントリーを判定する。
 *
 * M5の1・3・A・C波を対象とし、M5固有の
 * FE上限、H1表示波の重複制限および成立時のメール送信を管理する。
 */
class ExpertAdvisorMtf3In3M5 : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     */
    ExpertAdvisorMtf3In3M5(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true
    ) : ExpertAdvisorMTF_3in3(fromMarketContext, fromIsDrawArrow) {
    }

protected:
    /**
     * M5ではEMA200距離を診断用に保持し、エントリー制限を一旦無効にする。
     *
     * @return 常にfalse。
     */
    virtual bool isTimeFrameEma200DistanceRequired() override {
        return false;
    }

    /**
     * D1・H4・H1・M15・M5のEMA200がM5分析方向と一致するか判定する。
     *
     * @return 全5足が有効かつ同方向の場合true。NONEは許可しない。
     */
    virtual bool isTimeFrameEma200ConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5 || this.elliotAll == NULL) {
            return false;
        }
        Mtf3In3HigherTimeFrameDecision decision;
        ENUM_TIMEFRAMES timeFrames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            if (!decision.isEma200DirectionMatched(
                    this.elliotAll.getElliot(timeFrames[i]), timeFrames[i], this.isBuy)) {
                return false;
            }
        }
        return true;
    }

    /**
     * M15がM5と同方向で、H4またはH1も同方向か判定する。
     * W1・D1とMN1の追加条件は共通の上位足判定で確認する。
     *
     * @return M5固有の分析方向条件を満たす場合true。
     */
    virtual bool isTimeFrameAnalysisDirectionConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5 || this.elliotAll == NULL) {
            return false;
        }
        return this.elliotAll.isBuySellH4OrH1AndM15();
    }

    /**
     * H1と共通のMN1・W1・D1条件をM5分析方向で判定する。
     *
     * @return 上位足条件を満たす場合true。
     */
    virtual bool isTimeFrameDirectionAlignmentConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5) {
            return false;
        }
        Mtf3In3HigherTimeFrameDecision decision;
        string rejectReason;
        bool isPassed = decision.evaluate(this.elliotAll, this.isBuy, rejectReason);
        if (!isPassed) {
            this.logger.debug(__FUNCTION__, "higher timeframe rejected: " + rejectReason);
        }
        return isPassed;
    }

    /**
     * M5の主波だけを判定し、H1・M15の波動番号は制限しない。
     *
     * @return M5用の波動条件を満たす場合true。
     */
    virtual bool isTimeFrameWaveConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5) {
            return false;
        }

        return this.isEntryWave(this.elliotCurrent);
    }

    /**
     * M5の最新主波が1・3・A・C波のいずれか判定する。
     *
     * @param fromElliot 判定対象。副次波ラベルは使用しない。
     * @return M5の主波がエントリー対象の場合true。
     */
    virtual bool isEntryWave(Elliot *fromElliot) override {
        if (fromElliot == NULL || fromElliot.marketContext.timeFrame != PERIOD_M5) {
            return false;
        }
        ZigZagPoint *latestPoint = fromElliot.getLatestPoint();
        if (latestPoint == NULL) {
            return false;
        }
        string elliotLabel = latestPoint.elliotLabel;
        return elliotLabel == "1" || elliotLabel == "3"
            || elliotLabel == "A" || elliotLabel == "C";
    }

    /**
     * M5第3波・C波のフィボナッチエクスパンション上限を確認する。
     *
     * @param fromRejectReason 条件未達時の結果コード。
     * @return M5固有の追加条件を満たす場合true。
     */
    virtual bool isTimeFrameEntryConditionMatched(
        string &fromRejectReason
    ) override {
        fromRejectReason = "";

        if (this.isM5EntryFibonacciExpansionWithin()) {
            return true;
        }

        fromRejectReason = "M5_ELLIOT3_FE_REJECTED";
        if (this.elliotCurrent != NULL) {
            ZigZagPoint *latestPoint = this.elliotCurrent.getLatestPoint();
            if (latestPoint != NULL && latestPoint.elliotLabel == "C") {
                fromRejectReason = "M5_ELLIOTC_FE_REJECTED";
            }
        }

        return false;
    }

    /**
     * M5エントリー対象のH1表示波を使用済みとして登録する。
     *
     * @return 登録不要、またはH1表示波を新規登録できた場合true。
     */
    virtual bool tryRegisterEntryScope() override {
        return this.tryRegisterH1EntryScope();
    }

    /**
     * M5エントリー成立時にメールを送信するか判定する。
     *
     * @return 常にtrue。
     */
    virtual bool shouldSendMail() override {
        return true;
    }

    /**
     * H1、M15およびM5の波動情報からアラート表示文字列を生成する。
     *
     * @return アラート表示文字列。
     */
    virtual string buildAlertText() override {
        return this.getThreeTimeFrameAlertText();
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_M5_MQH
