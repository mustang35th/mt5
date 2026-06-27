/**
 * Package: MstngEa.App
 * File: StrategyFactory.mqh
 */

#ifndef MSTNGEA_APP_STRATEGYFACTORY_MQH
#define MSTNGEA_APP_STRATEGYFACTORY_MQH

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
     * @return 戦略
     */
    static IStrategyAdapter *create(
        StrategyType strategyTypeValue,
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue,
        SignalCount *signalCountValue
    ) {

        if (strategyTypeValue == STRATEGY_TYPE_MTF_3IN3) {
            return new ExpertAdvisorMtf3In3Adapter(
                symbolNameValue,
                timeFrameValue,
                signalCountValue
            );
        }

        if (strategyTypeValue == STRATEGY_TYPE_MTF_3IN3_BUY_SELL_D1) {
            return new ExpertAdvisorMtf3In3BuySellD1Adapter(
                symbolNameValue,
                timeFrameValue,
                signalCountValue
            );
        }

        if (strategyTypeValue == STRATEGY_TYPE_MTF_BUY_SELL_COUNT3) {
            return new ExpertAdvisorMtfBuySellCount3Adapter(
                symbolNameValue,
                timeFrameValue,
                signalCountValue
            );
        }

        return NULL;
    }
};

#endif
