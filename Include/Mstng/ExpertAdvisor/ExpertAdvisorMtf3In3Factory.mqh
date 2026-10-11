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
 * H1・M15はH1共通ポリシーに固定し、確認モード引数による上書きを受け付けない。
 * H1・M15は明示指定によりMN1方向とW1 EMA200の両方を必須にできる。
 * 確認モード引数はその他の従来互換経路のために維持する。
 * 呼び出し元のH1設定記録も共通ポリシーから生成すること。
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
     * @param fromH1W1ConfirmationMode H1以外の互換経路へ渡すW1確認モード。
     * @param fromH1DirectionAlignmentMode H1以外の互換経路へ渡す方向一致モード。
     * @param fromH1Ema200ConfirmationMode H1以外の互換経路へ渡すEMA200確認モード。
     * @param fromH1DirectionCorrectionEnabled H1はD1・H4、M15はD1・H4・H1の片足方向補正を使用する場合true。
     * @param fromM15H4MaxFibonacciExpansionPercent M15で使用するH4のFE上限（%）。0は制限なし。
     * @param fromM15H1MaxFibonacciExpansionPercent M15で使用するH1のFE上限（%）。0は制限なし。
     * @param fromH1Mn1AndW1Ema200Required H1・M15でMN1方向とW1 EMA200の両方を必須にする場合true。
     * @param fromH1H4WaveRestrictionEnabled H1・M15でH4の波番号と第5波構造を制限する場合true。
     * @param fromM5Mn1AndW1Ema200Required M5でMN1方向とW1 EMA200の両方を必須にする場合true。
     * @return 呼び出し側が所有するMTF_3in3判定クラス。
     */
    static ExpertAdvisorMTF_3in3 *create(
        MarketContext &fromMarketContext,
        bool fromIsDrawArrow = true,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1DirectionAlignmentMode fromH1DirectionAlignmentMode =
            H1_DIRECTION_ALIGNMENT_D1_TO_H1,
        H1Ema200ConfirmationMode fromH1Ema200ConfirmationMode =
            H1_EMA200_CONFIRMATION_H1_ONLY,
        bool fromH1DirectionCorrectionEnabled = false,
        double fromM15H4MaxFibonacciExpansionPercent = 0.0,
        double fromM15H1MaxFibonacciExpansionPercent = 0.0,
        bool fromH1Mn1AndW1Ema200Required = false,
        bool fromH1H4WaveRestrictionEnabled = true,
        bool fromM5Mn1AndW1Ema200Required = false
    ) {
        if (fromMarketContext.timeFrame == PERIOD_H1) {
            return new ExpertAdvisorMtf3In3H1(
                fromMarketContext,
                fromIsDrawArrow,
                fromH1DirectionCorrectionEnabled,
                fromH1Mn1AndW1Ema200Required,
                fromH1H4WaveRestrictionEnabled
            );
        }

        if (fromMarketContext.timeFrame == PERIOD_M15) {
            return new ExpertAdvisorMtf3In3M15(
                fromMarketContext,
                fromIsDrawArrow,
                fromH1DirectionCorrectionEnabled,
                fromM15H4MaxFibonacciExpansionPercent,
                fromM15H1MaxFibonacciExpansionPercent,
                fromH1Mn1AndW1Ema200Required,
                fromH1H4WaveRestrictionEnabled
            );
        }

        if (fromMarketContext.timeFrame == PERIOD_M5) {
            return new ExpertAdvisorMtf3In3M5(
                fromMarketContext,
                fromIsDrawArrow,
                fromM5Mn1AndW1Ema200Required
            );
        }

        return new ExpertAdvisorMTF_3in3(
            fromMarketContext,
            fromIsDrawArrow,
            fromH1W1ConfirmationMode,
            fromH1DirectionAlignmentMode,
            fromH1Ema200ConfirmationMode
        );
    }
};

#endif // MSTNG_EXPERT_ADVISOR_EXPERT_ADVISOR_MTF3_IN3_FACTORY_MQH
