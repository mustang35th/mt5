#ifndef MSTNGEA_STRATEGY_H1ZIGZAGTRAILDECISION_MQH
#define MSTNGEA_STRATEGY_H1ZIGZAGTRAILDECISION_MQH

#include <MstngEa\Domain\H1ZigZagTrailDecisionResult.mqh>
#include <MstngEaCommon\Runtime\EaZigZagTrailDecision.mqh>

/**
 * H1の公開APIを維持し、確定ZigZagの純粋判定を共通処理へ委譲する。
 */
class H1ZigZagTrailDecision {
public:
    /**
     * H1 ZigZagトレイルのSL変更可否を判定する。
     *
     * @param fromPositionSnapshot 現在のポジション状態。
     * @param fromLatestWave H1 Elliott分析の最新Wave。
     * @param fromBufferPips ZigZagポイントから離すpips数。
     * @param fromPipSize 1pipの価格幅。
     * @param fromTickSize 最小価格刻み。
     * @param fromResult 判定結果の格納先。
     * @return SLを変更する場合true。
     */
    bool evaluate(
        PositionSnapshot &fromPositionSnapshot,
        Wave *fromLatestWave,
        const double fromBufferPips,
        const double fromPipSize,
        const double fromTickSize,
        H1ZigZagTrailDecisionResult &fromResult
    ) {
        EaZigZagTrailDecision decision;
        EaTrailDecision result;
        bool accepted = decision.evaluate(fromPositionSnapshot, fromLatestWave,
            PERIOD_H1, fromBufferPips, fromPipSize, fromTickSize, result);
        fromResult.shouldModify = result.shouldModify;
        fromResult.targetStopLoss = result.targetStopLoss;
        fromResult.pivotRate = result.pivotRate;
        fromResult.pivotBarTime = result.pivotBarTime;
        fromResult.pivotBarIndex = result.pivotBarIndex;
        fromResult.pivotIsPeak = result.pivotIsPeak;
        fromResult.latestBarTime = result.latestBarTime;
        fromResult.skipReason = result.skipReason;
        return accepted;
    }
};

#endif // MSTNGEA_STRATEGY_H1ZIGZAGTRAILDECISION_MQH
