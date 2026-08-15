//+------------------------------------------------------------------+
//|                                        H1ZigZagTrailDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Strategy
 * File: H1ZigZagTrailDecision.mqh
 */

#ifndef MSTNGEA_STRATEGY_H1ZIGZAGTRAILDECISION_MQH
#define MSTNGEA_STRATEGY_H1ZIGZAGTRAILDECISION_MQH

#include <Mstng\Elliot\Wave.mqh>
#include <MstngEa\Domain\H1ZigZagTrailDecisionResult.mqh>
#include <MstngEa\Domain\PositionSnapshot.mqh>

/**
 * 確定したH1 ZigZagスイングからトレイルSL候補を判定する。
 *
 * 最新ポイントは1つ前のポイントが確定したことの確認にだけ使い、
 * 実際のSL基準には1つ前のポイントを使用する。
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
        fromResult.reset();

        if (!this.isPositionValid(fromPositionSnapshot)) {
            fromResult.skipReason = "INVALID_POSITION";

            return false;
        }

        if (fromBufferPips < 0.0
                || fromPipSize <= 0.0
                || fromTickSize <= 0.0) {
            fromResult.skipReason = "INVALID_PRICE_UNIT";

            return false;
        }

        if (fromLatestWave == NULL) {
            fromResult.skipReason = "WAVE_UNAVAILABLE";

            return false;
        }

        if (fromLatestWave.marketContext.timeFrame != PERIOD_H1) {
            fromResult.skipReason = "INVALID_TIMEFRAME";

            return false;
        }

        ZigZagPoint *latestPoint = fromLatestWave.getLatestPoint();
        ZigZagPoint *pivotPoint = fromLatestWave.getLatestPoint2();

        if (latestPoint == NULL || pivotPoint == NULL) {
            fromResult.skipReason = "POINTS_UNAVAILABLE";

            return false;
        }

        this.setPointResult(latestPoint, pivotPoint, fromResult);

        if (latestPoint.rate <= 0.0
                || pivotPoint.rate <= 0.0
                || latestPoint.barTime <= 0
                || pivotPoint.barTime <= 0) {
            fromResult.skipReason = "INVALID_POINT";

            return false;
        }

        if (latestPoint.isAddedPoint || pivotPoint.isAddedPoint) {
            fromResult.skipReason = "ADDED_POINT";

            return false;
        }

        if (latestPoint.barIndex < 1 || pivotPoint.barIndex < 1) {
            fromResult.skipReason = "FORMING_BAR";

            return false;
        }

        if (pivotPoint.barTime >= latestPoint.barTime) {
            fromResult.skipReason = "INVALID_POINT_ORDER";

            return false;
        }

        long positionOpenSeconds =
            fromPositionSnapshot.openTimeMilliseconds / 1000;

        if ((long)pivotPoint.barTime <= positionOpenSeconds) {
            fromResult.skipReason = "PIVOT_BEFORE_POSITION_OPEN";

            return false;
        }

        if (!this.isDirectionMatched(
                fromPositionSnapshot.isBuy,
                latestPoint,
                pivotPoint
        )) {
            fromResult.skipReason = "DIRECTION_MISMATCH";

            return false;
        }

        double bufferPrice = fromBufferPips * fromPipSize;
        double targetStopLoss = pivotPoint.rate + bufferPrice;

        if (fromPositionSnapshot.isBuy) {
            targetStopLoss = pivotPoint.rate - bufferPrice;
        }

        targetStopLoss = this.normalizeTargetStopLoss(
            targetStopLoss,
            fromPositionSnapshot.isBuy,
            fromTickSize
        );
        fromResult.targetStopLoss = targetStopLoss;

        if (targetStopLoss <= 0.0) {
            fromResult.skipReason = "INVALID_TARGET";

            return false;
        }

        if (!this.isImprovedByOneTick(
                fromPositionSnapshot,
                targetStopLoss,
                fromTickSize
        )) {
            fromResult.skipReason = "NOT_IMPROVED";

            return false;
        }

        fromResult.shouldModify = true;
        fromResult.skipReason = "";

        return true;
    }

private:
    /**
     * ポジション状態がトレイル判定可能か確認する。
     *
     * @param fromPositionSnapshot 現在のポジション状態。
     * @return 判定可能な場合true。
     */
    bool isPositionValid(PositionSnapshot &fromPositionSnapshot) {
        return fromPositionSnapshot.hasPosition
            && fromPositionSnapshot.openTimeMilliseconds > 0
            && fromPositionSnapshot.openPrice > 0.0
            && fromPositionSnapshot.stopLoss > 0.0;
    }

    /**
     * 使用ポイントの診断情報を結果へ設定する。
     *
     * @param fromLatestPoint 最新ポイント。
     * @param fromPivotPoint SL基準にする1つ前のポイント。
     * @param fromResult 判定結果。
     */
    void setPointResult(
        ZigZagPoint *fromLatestPoint,
        ZigZagPoint *fromPivotPoint,
        H1ZigZagTrailDecisionResult &fromResult
    ) {
        fromResult.pivotRate = fromPivotPoint.rate;
        fromResult.pivotBarTime = fromPivotPoint.barTime;
        fromResult.pivotBarIndex = fromPivotPoint.barIndex;
        fromResult.pivotIsPeak = fromPivotPoint.isPeak;
        fromResult.latestBarTime = fromLatestPoint.barTime;
    }

    /**
     * ポジション方向と2つのZigZagポイントの極性を確認する。
     *
     * @param fromIsBuy BUYポジションの場合true。
     * @param fromLatestPoint 最新ポイント。
     * @param fromPivotPoint 1つ前のポイント。
     * @return BUYは谷から山、SELLは山から谷の場合true。
     */
    bool isDirectionMatched(
        const bool fromIsBuy,
        ZigZagPoint *fromLatestPoint,
        ZigZagPoint *fromPivotPoint
    ) {
        if (fromIsBuy) {
            return !fromPivotPoint.isPeak && fromLatestPoint.isPeak;
        }

        return fromPivotPoint.isPeak && !fromLatestPoint.isPeak;
    }

    /**
     * BUYは下方向、SELLは上方向へ最小価格刻みにそろえる。
     *
     * @param fromTargetStopLoss 補正前のSL候補。
     * @param fromIsBuy BUYポジションの場合true。
     * @param fromTickSize 最小価格刻み。
     * @return 最小価格刻みにそろえたSL候補。
     */
    double normalizeTargetStopLoss(
        const double fromTargetStopLoss,
        const bool fromIsBuy,
        const double fromTickSize
    ) {
        double tickCount = fromTargetStopLoss / fromTickSize;
        double tickCountTolerance = 0.0000001;
        double normalizedTickCount = MathCeil(
            tickCount - tickCountTolerance
        );

        if (fromIsBuy) {
            normalizedTickCount = MathFloor(
                tickCount + tickCountTolerance
            );
        }

        return NormalizeDouble(normalizedTickCount * fromTickSize, 8);
    }

    /**
     * SL候補が現在SLより1tick以上利益側へ進むか確認する。
     *
     * @param fromPositionSnapshot 現在のポジション状態。
     * @param fromTargetStopLoss SL候補。
     * @param fromTickSize 最小価格刻み。
     * @return 1tick以上改善する場合true。
     */
    bool isImprovedByOneTick(
        PositionSnapshot &fromPositionSnapshot,
        const double fromTargetStopLoss,
        const double fromTickSize
    ) {
        double improvement = fromPositionSnapshot.stopLoss
            - fromTargetStopLoss;

        if (fromPositionSnapshot.isBuy) {
            improvement = fromTargetStopLoss
                - fromPositionSnapshot.stopLoss;
        }

        double comparisonTolerance = fromTickSize * 0.000001;

        return improvement + comparisonTolerance >= fromTickSize;
    }
};

#endif // MSTNGEA_STRATEGY_H1ZIGZAGTRAILDECISION_MQH
