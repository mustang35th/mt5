/**
 * Package: MstngEa.Strategy
 * File: IStrategyAdapter.mqh
 */

#ifndef MSTNGEA_STRATEGY_ISTRATEGYADAPTER_MQH
#define MSTNGEA_STRATEGY_ISTRATEGYADAPTER_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <MstngEa\Domain\ExitDecision.mqh>
#include <MstngEa\Domain\SignalDecision.mqh>

/**
 * 戦略アダプタ共通IF
 */
class IStrategyAdapter {
public:
    /**
     * エントリー判定
     *
     * @param elliotAllValue 分析結果
     * @return 判定結果
     */
    virtual SignalDecision analyzeEntry(ElliotAll *elliotAllValue) = 0;

    /**
     * 決済判定
     *
     * @param elliotAllValue 分析結果
     * @param isBuyPositionValue true: 買いポジション
     * @return 判定結果
     */
    virtual ExitDecision analyzeExit(
        ElliotAll *elliotAllValue,
        bool isBuyPositionValue
    ) = 0;

    /**
     * エリオット情報文字列取得
     *
     * @return エリオット情報文字列
     */
    virtual string getElliottInfoText() = 0;

    /**
     * 戦略名取得
     *
     * @return 戦略名
     */
    virtual string getStrategyName() = 0;
};

#endif
