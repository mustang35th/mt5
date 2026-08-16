//+------------------------------------------------------------------+
//|                                  ExpertAdvisorMtf3In3Factory.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_FACTORY_MQH
#define MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_FACTORY_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3H1.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3M15.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3M5.mqh>

/**
 * 現在時間足に対応するMTF_3in3判定クラスを生成する。
 *
 * H1、M15およびM5以外は、従来互換の共通クラスを生成する。
 */
class ExpertAdvisorMtf3In3Factory {
public:
    /**
     * 市場コンテキストに対応するMTF_3in3判定クラスを生成する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト。
     * @param fromIsDrawArrow シグナル矢印を描画する場合true。
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード。
     * @param fromH1DirectionAlignmentMode H1エントリーの方向一致モード。
     * @return 呼び出し側が所有するMTF_3in3判定クラス。
     */
    static ExpertAdvisorMTF_3in3 *create(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1DirectionAlignmentMode fromH1DirectionAlignmentMode =
            H1_DIRECTION_ALIGNMENT_D1_TO_H1
    ) {
        if (fromMarketContext.timeFrame == PERIOD_H1) {
            return new ExpertAdvisorMtf3In3H1(
                fromMarketContext,
                fromIsDrawArrow,
                fromH1W1ConfirmationMode,
                fromH1DirectionAlignmentMode
            );
        }

        if (fromMarketContext.timeFrame == PERIOD_M15) {
            return new ExpertAdvisorMtf3In3M15(
                fromMarketContext,
                fromIsDrawArrow
            );
        }

        if (fromMarketContext.timeFrame == PERIOD_M5) {
            return new ExpertAdvisorMtf3In3M5(
                fromMarketContext,
                fromIsDrawArrow
            );
        }

        return new ExpertAdvisorMTF_3in3(
            fromMarketContext,
            fromIsDrawArrow,
            fromH1W1ConfirmationMode,
            fromH1DirectionAlignmentMode
        );
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_FACTORY_MQH
