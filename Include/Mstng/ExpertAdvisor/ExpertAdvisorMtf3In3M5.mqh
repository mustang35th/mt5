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

/**
 * M5を現在足としてMTF_3in3エントリーを判定する。
 *
 * H1、M15およびM5の波動条件に加え、M5固有の
 * FE上限、H1表示波の重複制限およびメール送信停止を管理する。
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
     * H1、M15およびM5が第1波または第3波か判定する。
     *
     * @return M5用の波動条件を満たす場合true。
     */
    virtual bool isTimeFrameWaveConditionMatched() override {
        if (this.marketContext.timeFrame != PERIOD_M5) {
            return false;
        }

        return this.isEntryWave(this.elliotHigher2)
            && this.isEntryWave(this.elliotHigher1)
            && this.isEntryWave(this.elliotCurrent);
    }

    /**
     * M5第3波のフィボナッチエクスパンション上限を確認する。
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
     * M5エントリー成立時のメール送信を停止する。
     *
     * @return 常にfalse。
     */
    virtual bool shouldSendMail() override {
        return false;
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
