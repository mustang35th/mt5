//+------------------------------------------------------------------+
//|                                              StrategyFactory.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.App
 * File: StrategyFactory.mqh
 */

#ifndef MSTNGEA_APP_STRATEGYFACTORY_MQH
#define MSTNGEA_APP_STRATEGYFACTORY_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <MstngEa\Config\StrategyType.mqh>
#include <MstngEa\Strategy\ExpertAdvisorMtf3In3Adapter.mqh>
#include <MstngEa\Strategy\ExpertAdvisorMtf3In3BuySellD1Adapter.mqh>
#include <MstngEa\Strategy\ExpertAdvisorMtfBuySellCount3Adapter.mqh>
#include <MstngEa\Strategy\IStrategyAdapter.mqh>

/**
 * 戦略生成
 */
class StrategyFactory {
public:
    /**
     * 戦略生成
     *
     * @param strategyTypeValue 戦略種別
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param signalCountValue シグナル回数
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード
     * @return 戦略
     */
    static IStrategyAdapter *create(
        StrategyType strategyTypeValue,
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue,
        SignalCount *signalCountValue,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY
    ) {
        MarketContext context(symbolNameValue, timeFrameValue);
        return StrategyFactory::create(
            strategyTypeValue,
            context,
            signalCountValue,
            fromH1W1ConfirmationMode
        );
    }

    /**
     * Create strategy.
     *
     * @param fromStrategyType Strategy type
     * @param fromMarketContext Market context
     * @param fromSignalCount Signal count
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード
     * @return Strategy
     */
    static IStrategyAdapter *create(
        StrategyType fromStrategyType,
        MarketContext &fromMarketContext,
        SignalCount *fromSignalCount,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY
    ) {

        if (fromStrategyType == STRATEGY_TYPE_MTF_3IN3) {
            return new ExpertAdvisorMtf3In3Adapter(
                fromMarketContext,
                fromSignalCount,
                fromH1W1ConfirmationMode
            );
        }

        if (fromStrategyType == STRATEGY_TYPE_MTF_3IN3_BUY_SELL_D1) {
            return new ExpertAdvisorMtf3In3BuySellD1Adapter(
                fromMarketContext,
                fromSignalCount
            );
        }

        if (fromStrategyType == STRATEGY_TYPE_MTF_BUY_SELL_COUNT3) {
            return new ExpertAdvisorMtfBuySellCount3Adapter(
                fromMarketContext,
                fromSignalCount
            );
        }

        return NULL;
    }
};

#endif
