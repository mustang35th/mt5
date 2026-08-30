//+------------------------------------------------------------------+
//|                   ElliotHigherSegmentPointListBuilder.mqh        |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_HIGHER_SEGMENT_POINT_BUILDER_MQH
#define MSTNG_ELLIOT_HIGHER_SEGMENT_POINT_BUILDER_MQH

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Wave.mqh>
#include <Mstng\Elliot\ZigZagPoint.mqh>

/**
 * 上位足の1区間に対応するポイント列を構築するクラス。
 *
 * 新しい順の下位足ZigZagポイントから上位足の左右境界を特定し、
 * 境界内にある4つの実ポイントを古い順に複製する。
 */
class ElliotHigherSegmentPointListBuilder {
public:
    /**
     * 下位足ポイント一覧から上位足1区間用のポイント列を構築する。
     *
     * 成功時の出力は、補完ポイントを含まない4点の古い順となる。
     * 失敗時の出力は空となり、入力ポイントは変更しない。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromRawPointList 抽出済み下位足ポイント一覧。インデックス0が最新
     * @param fromHigherLeftPoint 上位足区間の古い側境界
     * @param fromHigherRightPoint 上位足区間の新しい側境界
     * @param fromIsUptrend 期待する上位足区間の方向
     * @param toZigZagPointList 構築したポイント一覧
     * @return Strict V1条件をすべて満たした場合true
     */
    bool build(
        MarketContext &fromMarketContext,
        CArrayObj &fromRawPointList,
        ZigZagPoint &fromHigherLeftPoint,
        ZigZagPoint &fromHigherRightPoint,
        const bool fromIsUptrend,
        CArrayObj &toZigZagPointList
    ) {
        this.errorMessage = "";
        toZigZagPointList.Clear();

        if (!this.validateInput(
                fromMarketContext,
                fromRawPointList,
                fromHigherLeftPoint,
                fromHigherRightPoint
            )) {
            return false;
        }

        int rightIndex = -1;
        int leftIndex = -1;

        if (!this.findUniqueBoundaryPair(
                fromMarketContext,
                fromRawPointList,
                fromHigherLeftPoint,
                fromHigherRightPoint,
                fromIsUptrend,
                rightIndex,
                leftIndex
            )) {
            return false;
        }

        if (!this.copyPointSequence(
                fromRawPointList,
                rightIndex,
                leftIndex,
                toZigZagPointList
            )) {
            toZigZagPointList.Clear();
            return false;
        }

        return true;
    }

    /**
     * 分析後Wave範囲から上位足1区間用のポイント列を構築する。
     *
     * Wave一覧は小さいインデックスほど新しいものとして扱う。各Wave内の
     * ポイントを新しい順へ平坦化し、隣接Waveの共有境界を1点にまとめた後、
     * 親境界間のStrict V1判定を実行する。Strict V1が失敗し、
     * 親方向4点の修正Waveと逆方向3点の修正Waveが連続する場合は、
     * 4つのアンカーポイントへ圧縮して再判定する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromWaveList 分析後Wave一覧。インデックス0が最新
     * @param fromWaveIndexStart 対象範囲の新しい側Waveインデックス
     * @param fromWaveIndexEnd 対象範囲の古い側Waveインデックス
     * @param fromHigherLeftPoint 上位足区間の古い側境界
     * @param fromHigherRightPoint 上位足区間の新しい側境界
     * @param fromIsUptrend 期待する上位足区間の方向
     * @param toZigZagPointList 構築したポイント一覧
     * @return Strict V1または修正Wave圧縮条件をすべて満たした場合true
     */
    bool buildFromWaveRange(
        MarketContext &fromMarketContext,
        CArrayObj &fromWaveList,
        const int fromWaveIndexStart,
        const int fromWaveIndexEnd,
        ZigZagPoint &fromHigherLeftPoint,
        ZigZagPoint &fromHigherRightPoint,
        const bool fromIsUptrend,
        CArrayObj &toZigZagPointList
    ) {
        this.errorMessage = "";
        toZigZagPointList.Clear();

        CArrayObj flattenedPointList;

        if (!this.flattenWaveRange(
                fromMarketContext,
                fromWaveList,
                fromWaveIndexStart,
                fromWaveIndexEnd,
                flattenedPointList
            )) {
            return false;
        }

        if (this.build(
                fromMarketContext,
                flattenedPointList,
                fromHigherLeftPoint,
                fromHigherRightPoint,
                fromIsUptrend,
                toZigZagPointList
            )) {
            return true;
        }

        string strictErrorMessage = this.errorMessage;

        if (!this.isCollapsibleCorrectionWavePair(
                fromMarketContext,
                fromWaveList,
                fromWaveIndexStart,
                fromWaveIndexEnd,
                fromIsUptrend,
                flattenedPointList
            )) {
            this.errorMessage = strictErrorMessage;
            return false;
        }

        if (!this.validatePointSequence(
                fromMarketContext,
                flattenedPointList,
                0,
                flattenedPointList.Total() - 1,
                fromIsUptrend
            )) {
            string sourceErrorMessage = this.errorMessage;
            toZigZagPointList.Clear();

            return this.fail(
                "correction wave pair source invalid. "
                + sourceErrorMessage
            );
        }

        CArrayObj collapsedPointList;

        if (!this.copyCollapsedCorrectionPointSequence(
                fromWaveList,
                fromWaveIndexStart,
                fromWaveIndexEnd,
                collapsedPointList
            )) {
            toZigZagPointList.Clear();
            return false;
        }

        if (!this.build(
                fromMarketContext,
                collapsedPointList,
                fromHigherLeftPoint,
                fromHigherRightPoint,
                fromIsUptrend,
                toZigZagPointList
            )) {
            string collapseErrorMessage = this.errorMessage;
            toZigZagPointList.Clear();

            return this.fail(
                "correction wave pair collapse failed. "
                + collapseErrorMessage
            );
        }

        return true;
    }

    /**
     * 直前の構築失敗理由を取得する。
     *
     * @return 構築成功時は空文字列、失敗時は理由
     */
    string getErrorMessage() {
        return this.errorMessage;
    }

private:
    /** 直前の構築失敗理由。 */
    string errorMessage;

    /**
     * 2つの修正Waveを4アンカーへ圧縮できる構造か判定する。
     *
     * Wave一覧は新しい順であり、新しいWaveは親と逆方向の3点、
     * 古いWaveは親方向の4点であることを要求する。
     * このメソッドは失敗理由を変更しない。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromWaveList 分析後Wave一覧
     * @param fromWaveIndexStart 対象範囲の新しい側Waveインデックス
     * @param fromWaveIndexEnd 対象範囲の古い側Waveインデックス
     * @param fromIsUptrend 期待する上位足区間の方向
     * @param fromFlattenedPointList 共有境界を除いた平坦化済みポイント一覧
     * @return 圧縮対象の構造である場合true
     */
    bool isCollapsibleCorrectionWavePair(
        MarketContext &fromMarketContext,
        CArrayObj &fromWaveList,
        const int fromWaveIndexStart,
        const int fromWaveIndexEnd,
        const bool fromIsUptrend,
        CArrayObj &fromFlattenedPointList
    ) {
        if (fromWaveIndexEnd != fromWaveIndexStart + 1
                || fromFlattenedPointList.Total() != 6) {
            return false;
        }

        Wave *newerWave = fromWaveList.At(fromWaveIndexStart);
        Wave *olderWave = fromWaveList.At(fromWaveIndexEnd);

        if (CheckPointer(newerWave) == POINTER_INVALID
                || CheckPointer(olderWave) == POINTER_INVALID) {
            return false;
        }

        if (newerWave.zigZagPointList.Total() != 3
                || olderWave.zigZagPointList.Total() != 4
                || newerWave.isMotive
                || olderWave.isMotive
                || olderWave.isUptrend != fromIsUptrend
                || newerWave.isUptrend == fromIsUptrend) {
            return false;
        }

        return this.isSharedWaveBoundary(
            fromMarketContext,
            newerWave,
            olderWave
        );
    }

    /**
     * 2つの修正Waveから4アンカーを新しい順へ複製する。
     *
     * 古いWaveの内部A・Bを省略し、古い始点、共有境界、
     * 新しいWaveのA・Bを古い順のアンカーとして採用する。
     * Builder入力用には逆順で追加する。
     *
     * @param fromWaveList 分析後Wave一覧
     * @param fromWaveIndexStart 対象範囲の新しい側Waveインデックス
     * @param fromWaveIndexEnd 対象範囲の古い側Waveインデックス
     * @param toPointList 圧縮したポイント一覧。インデックス0が最新
     * @return 全アンカーを複製できた場合true
     */
    bool copyCollapsedCorrectionPointSequence(
        CArrayObj &fromWaveList,
        const int fromWaveIndexStart,
        const int fromWaveIndexEnd,
        CArrayObj &toPointList
    ) {
        toPointList.Clear();

        Wave *newerWave = fromWaveList.At(fromWaveIndexStart);
        Wave *olderWave = fromWaveList.At(fromWaveIndexEnd);

        if (!this.addClonedPoint(
                newerWave.zigZagPointList.At(2),
                "newer[2]",
                toPointList
            )
                || !this.addClonedPoint(
                    newerWave.zigZagPointList.At(1),
                    "newer[1]",
                    toPointList
                )
                || !this.addClonedPoint(
                    olderWave.zigZagPointList.At(3),
                    "older[3]",
                    toPointList
                )
                || !this.addClonedPoint(
                    olderWave.zigZagPointList.At(0),
                    "older[0]",
                    toPointList
                )) {
            toPointList.Clear();
            return false;
        }

        return true;
    }

    /**
     * ポイントを複製して一覧へ追加する。
     *
     * @param fromPoint 複製元ポイント
     * @param fromSourceLabel エラー表示用の位置
     * @param toPointList 追加先一覧
     * @return 複製と追加に成功した場合true
     */
    bool addClonedPoint(
        ZigZagPoint *fromPoint,
        const string fromSourceLabel,
        CArrayObj &toPointList
    ) {
        if (CheckPointer(fromPoint) == POINTER_INVALID) {
            return this.fail(
                "collapsed source point is invalid. source="
                + fromSourceLabel
            );
        }

        ZigZagPoint *clonedPoint = fromPoint.clone();

        if (clonedPoint == NULL) {
            return this.fail(
                "collapsed source point clone failed. source="
                + fromSourceLabel
            );
        }

        if (!toPointList.Add(clonedPoint)) {
            delete clonedPoint;

            return this.fail(
                "collapsed source point add failed. source="
                + fromSourceLabel
            );
        }

        return true;
    }

    /**
     * 指定Wave範囲を共有境界を除いて新しい順へ平坦化する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromWaveList 分析後Wave一覧
     * @param fromWaveIndexStart 対象範囲の新しい側Waveインデックス
     * @param fromWaveIndexEnd 対象範囲の古い側Waveインデックス
     * @param toPointList 平坦化したポイント一覧
     * @return 平坦化に成功した場合true
     */
    bool flattenWaveRange(
        MarketContext &fromMarketContext,
        CArrayObj &fromWaveList,
        const int fromWaveIndexStart,
        const int fromWaveIndexEnd,
        CArrayObj &toPointList
    ) {
        int waveTotal = fromWaveList.Total();

        if (fromWaveIndexStart < 0
                || fromWaveIndexEnd < fromWaveIndexStart
                || fromWaveIndexEnd >= waveTotal) {
            return this.fail(
                StringFormat(
                    "wave range is invalid. start=%d end=%d total=%d",
                    fromWaveIndexStart,
                    fromWaveIndexEnd,
                    waveTotal
                )
            );
        }

        Wave *newerWave = NULL;

        for (int i = fromWaveIndexStart; i <= fromWaveIndexEnd; i++) {
            Wave *wave = fromWaveList.At(i);

            if (CheckPointer(wave) == POINTER_INVALID) {
                return this.fail(
                    StringFormat("wave is invalid. waveIndex=%d", i)
                );
            }

            if (!this.isSameMarketContext(
                    fromMarketContext,
                    wave.marketContext
                )) {
                return this.fail(
                    StringFormat(
                        "wave market context mismatch. waveIndex=%d",
                        i
                    )
                );
            }

            int pointTotal = wave.zigZagPointList.Total();

            if (pointTotal < 2) {
                return this.fail(
                    StringFormat(
                        "wave must contain at least two points. waveIndex=%d total=%d",
                        i,
                        pointTotal
                    )
                );
            }

            if (newerWave != NULL
                    && !this.isSharedWaveBoundary(
                        fromMarketContext,
                        newerWave,
                        wave
                    )) {
                return this.fail(
                    StringFormat(
                        "shared wave boundary mismatch. newerWaveIndex=%d olderWaveIndex=%d",
                        i - 1,
                        i
                    )
                );
            }

            for (int j = pointTotal - 1; j >= 0; j--) {
                if (newerWave != NULL && j == pointTotal - 1) {
                    continue;
                }

                ZigZagPoint *point = wave.zigZagPointList.At(j);

                if (CheckPointer(point) == POINTER_INVALID) {
                    return this.fail(
                        StringFormat(
                            "wave point is invalid. waveIndex=%d pointIndex=%d",
                            i,
                            j
                        )
                    );
                }

                ZigZagPoint *clonedPoint = point.clone();

                if (clonedPoint == NULL) {
                    return this.fail(
                        StringFormat(
                            "wave point clone failed. waveIndex=%d pointIndex=%d",
                            i,
                            j
                        )
                    );
                }

                if (!toPointList.Add(clonedPoint)) {
                    delete clonedPoint;

                    return this.fail(
                        StringFormat(
                            "wave point add failed. waveIndex=%d pointIndex=%d",
                            i,
                            j
                        )
                    );
                }
            }

            newerWave = wave;
        }

        return true;
    }

    /**
     * 新旧Waveが同じ境界ポイントを共有するか判定する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromNewerWave 新しい側Wave
     * @param fromOlderWave 古い側Wave
     * @return 共有境界が一致する場合true
     */
    bool isSharedWaveBoundary(
        MarketContext &fromMarketContext,
        Wave *fromNewerWave,
        Wave *fromOlderWave
    ) {
        if (CheckPointer(fromNewerWave) == POINTER_INVALID
                || CheckPointer(fromOlderWave) == POINTER_INVALID
                || fromNewerWave.zigZagPointList.Total() < 2
                || fromOlderWave.zigZagPointList.Total() < 2) {
            return false;
        }

        ZigZagPoint *newerBoundary = fromNewerWave.zigZagPointList.At(0);
        ZigZagPoint *olderBoundary = fromOlderWave.zigZagPointList.At(
            fromOlderWave.zigZagPointList.Total() - 1
        );

        return this.isSamePoint(
            fromMarketContext,
            newerBoundary,
            olderBoundary
        );
    }

    /**
     * 2点が同じ下位足ZigZagポイントを表すか判定する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromPoint1 比較対象1
     * @param fromPoint2 比較対象2
     * @return 市場、時刻、価格および山谷が一致する場合true
     */
    bool isSamePoint(
        MarketContext &fromMarketContext,
        ZigZagPoint *fromPoint1,
        ZigZagPoint *fromPoint2
    ) {
        if (CheckPointer(fromPoint1) == POINTER_INVALID
                || CheckPointer(fromPoint2) == POINTER_INVALID) {
            return false;
        }

        if (!this.isSameMarketContext(
                    fromMarketContext,
                    fromPoint1.marketContext
                )
                || !this.isSameMarketContext(
                    fromMarketContext,
                    fromPoint2.marketContext
                )) {
            return false;
        }

        return fromPoint1.barTime == fromPoint2.barTime
            && fromPoint1.barTimeNext == fromPoint2.barTimeNext
            && NormalizeDouble(
                fromPoint1.rate,
                fromMarketContext.digits
            ) == NormalizeDouble(
                fromPoint2.rate,
                fromMarketContext.digits
            )
            && fromPoint1.isPeak == fromPoint2.isPeak
            && fromPoint1.isAddedPoint == fromPoint2.isAddedPoint;
    }

    /**
     * 入力一覧と上位足境界の基本条件を検証する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromRawPointList 抽出済み下位足ポイント一覧
     * @param fromHigherLeftPoint 上位足区間の古い側境界
     * @param fromHigherRightPoint 上位足区間の新しい側境界
     * @return 入力の基本条件が有効な場合true
     */
    bool validateInput(
        MarketContext &fromMarketContext,
        CArrayObj &fromRawPointList,
        ZigZagPoint &fromHigherLeftPoint,
        ZigZagPoint &fromHigherRightPoint
    ) {
        if (fromRawPointList.Total() <= 0) {
            return this.fail("raw point list is empty");
        }

        if (fromHigherLeftPoint.marketContext.symbolName
                    != fromMarketContext.symbolName
                || fromHigherRightPoint.marketContext.symbolName
                    != fromMarketContext.symbolName) {
            return this.fail("higher boundary symbol mismatch");
        }

        if (fromHigherLeftPoint.barTimeNext
                    <= fromHigherLeftPoint.barTime
                || fromHigherRightPoint.barTimeNext
                    <= fromHigherRightPoint.barTime) {
            return this.fail("higher boundary time range is invalid");
        }

        if (fromHigherRightPoint.barTime
                < fromHigherLeftPoint.barTime) {
            return this.fail("higher boundary chronological order mismatch");
        }

        return true;
    }

    /**
     * 条件を満たす上位足境界ペアを一意に特定する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromRawPointList 抽出済み下位足ポイント一覧
     * @param fromHigherLeftPoint 上位足区間の古い側境界
     * @param fromHigherRightPoint 上位足区間の新しい側境界
     * @param fromIsUptrend 期待する上位足区間の方向
     * @param toRightIndex 新しい側境界のインデックス
     * @param toLeftIndex 古い側境界のインデックス
     * @return 有効な境界ペアが一意に存在する場合true
     */
    bool findUniqueBoundaryPair(
        MarketContext &fromMarketContext,
        CArrayObj &fromRawPointList,
        ZigZagPoint &fromHigherLeftPoint,
        ZigZagPoint &fromHigherRightPoint,
        const bool fromIsUptrend,
        int &toRightIndex,
        int &toLeftIndex
    ) {
        const int requiredPointCount = 4;
        int rawPointTotal = fromRawPointList.Total();
        int rightCandidateCount = 0;
        int leftCandidateCount = 0;
        int orderedPairCount = 0;
        int firstOrderedPointCount = 0;
        int firstFourRightIndex = -1;
        int firstFourLeftIndex = -1;
        int validPairCount = 0;
        double rightBoundaryRate = 0;
        double leftBoundaryRate = 0;

        if (!this.getBoundaryRate(
                fromMarketContext,
                fromRawPointList,
                fromHigherRightPoint,
                rightBoundaryRate
            )) {
            return this.fail("right boundary point not found");
        }

        if (!this.getBoundaryRate(
                fromMarketContext,
                fromRawPointList,
                fromHigherLeftPoint,
                leftBoundaryRate
            )) {
            return this.fail("left boundary point not found");
        }

        for (int i = 0; i < rawPointTotal; i++) {
            ZigZagPoint *rightPoint = fromRawPointList.At(i);

            if (this.isBoundaryPoint(
                    fromMarketContext,
                    rightPoint,
                    fromHigherRightPoint,
                    rightBoundaryRate
                )) {
                rightCandidateCount++;

                for (int j = i + 1; j < rawPointTotal; j++) {
                    ZigZagPoint *leftPoint = fromRawPointList.At(j);

                    if (!this.isBoundaryPoint(
                            fromMarketContext,
                            leftPoint,
                            fromHigherLeftPoint,
                            leftBoundaryRate
                        )) {
                        continue;
                    }

                    orderedPairCount++;
                    int pointCount = j - i + 1;

                    if (firstOrderedPointCount == 0) {
                        firstOrderedPointCount = pointCount;
                    }

                    if (pointCount != requiredPointCount) {
                        continue;
                    }

                    if (firstFourRightIndex < 0) {
                        firstFourRightIndex = i;
                        firstFourLeftIndex = j;
                    }

                    if (this.isValidPointSequence(
                            fromMarketContext,
                            fromRawPointList,
                            i,
                            j,
                            fromIsUptrend
                        )) {
                        validPairCount++;
                        toRightIndex = i;
                        toLeftIndex = j;
                    }
                }
            }
        }

        for (int i = 0; i < rawPointTotal; i++) {
            ZigZagPoint *leftPoint = fromRawPointList.At(i);

            if (this.isBoundaryPoint(
                    fromMarketContext,
                    leftPoint,
                    fromHigherLeftPoint,
                    leftBoundaryRate
                )) {
                leftCandidateCount++;
            }
        }

        if (rightCandidateCount == 0) {
            return this.fail("right boundary point not found");
        }

        if (leftCandidateCount == 0) {
            return this.fail("left boundary point not found");
        }

        if (orderedPairCount == 0) {
            return this.fail("boundary index order mismatch");
        }

        if (firstFourRightIndex < 0) {
            return this.fail(
                StringFormat(
                    "boundary slice must contain four points. total=%d",
                    firstOrderedPointCount
                )
            );
        }

        if (validPairCount == 0) {
            return this.validatePointSequence(
                fromMarketContext,
                fromRawPointList,
                firstFourRightIndex,
                firstFourLeftIndex,
                fromIsUptrend
            );
        }

        if (validPairCount > 1) {
            return this.fail(
                StringFormat(
                    "boundary pair is ambiguous. total=%d",
                    validPairCount
                )
            );
        }

        return true;
    }

    /**
     * 指定境界内のポイントがStrict V1の配列条件を満たすか判定する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromRawPointList 抽出済み下位足ポイント一覧
     * @param fromRightIndex 新しい側境界のインデックス
     * @param fromLeftIndex 古い側境界のインデックス
     * @param fromIsUptrend 期待する上位足区間の方向
     * @return Strict V1の配列条件を満たす場合true
     */
    bool validatePointSequence(
        MarketContext &fromMarketContext,
        CArrayObj &fromRawPointList,
        const int fromRightIndex,
        const int fromLeftIndex,
        const bool fromIsUptrend
    ) {
        ZigZagPoint *previousPoint = NULL;
        int pointIndex = 0;

        for (int i = fromLeftIndex; i >= fromRightIndex; i--) {
            ZigZagPoint *point = fromRawPointList.At(i);

            if (CheckPointer(point) == POINTER_INVALID) {
                return this.fail(
                    StringFormat("point is invalid. pointIndex=%d", pointIndex)
                );
            }

            if (!this.isSameMarketContext(
                    fromMarketContext,
                    point.marketContext
                )) {
                return this.fail(
                    StringFormat(
                        "point market context mismatch. pointIndex=%d",
                        pointIndex
                    )
                );
            }

            if (point.isAddedPoint) {
                return this.fail(
                    StringFormat(
                        "added point is not allowed. pointIndex=%d",
                        pointIndex
                    )
                );
            }

            if (previousPoint != NULL) {
                if (point.barTime <= previousPoint.barTime) {
                    return this.fail(
                        StringFormat(
                            "point time is not strictly ascending. pointIndex=%d",
                            pointIndex
                        )
                    );
                }

                if (point.isPeak == previousPoint.isPeak) {
                    return this.fail(
                        StringFormat(
                            "peak and bottom do not alternate. pointIndex=%d",
                            pointIndex
                        )
                    );
                }

                if (point.isPeak && point.rate <= previousPoint.rate) {
                    return this.fail(
                        StringFormat(
                            "peak rate direction mismatch. pointIndex=%d",
                            pointIndex
                        )
                    );
                }

                if (!point.isPeak && point.rate >= previousPoint.rate) {
                    return this.fail(
                        StringFormat(
                            "bottom rate direction mismatch. pointIndex=%d",
                            pointIndex
                        )
                    );
                }
            }

            previousPoint = point;
            pointIndex++;
        }

        ZigZagPoint *firstPoint = fromRawPointList.At(fromLeftIndex);
        ZigZagPoint *latestPoint = fromRawPointList.At(fromRightIndex);

        if (!this.isDirectionMatched(
                firstPoint,
                latestPoint,
                fromIsUptrend
            )) {
            return this.fail("higher segment direction mismatch");
        }

        return true;
    }

    /**
     * 指定境界内のポイントがStrict V1の配列条件を満たすか副作用なく判定する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromRawPointList 抽出済み下位足ポイント一覧
     * @param fromRightIndex 新しい側境界のインデックス
     * @param fromLeftIndex 古い側境界のインデックス
     * @param fromIsUptrend 期待する上位足区間の方向
     * @return Strict V1の配列条件を満たす場合true
     */
    bool isValidPointSequence(
        MarketContext &fromMarketContext,
        CArrayObj &fromRawPointList,
        const int fromRightIndex,
        const int fromLeftIndex,
        const bool fromIsUptrend
    ) {
        string oldErrorMessage = this.errorMessage;
        bool isValid = this.validatePointSequence(
            fromMarketContext,
            fromRawPointList,
            fromRightIndex,
            fromLeftIndex,
            fromIsUptrend
        );
        this.errorMessage = oldErrorMessage;

        return isValid;
    }

    /**
     * 境界内ポイントを古い順に複製する。
     *
     * @param fromRawPointList コピー元ポイント一覧
     * @param fromRightIndex 新しい側境界のインデックス
     * @param fromLeftIndex 古い側境界のインデックス
     * @param toZigZagPointList コピー先ポイント一覧
     * @return 全ポイントを複製できた場合true
     */
    bool copyPointSequence(
        CArrayObj &fromRawPointList,
        const int fromRightIndex,
        const int fromLeftIndex,
        CArrayObj &toZigZagPointList
    ) {
        for (int i = fromLeftIndex; i >= fromRightIndex; i--) {
            ZigZagPoint *point = fromRawPointList.At(i);
            ZigZagPoint *clonedPoint = point.clone();

            if (clonedPoint == NULL) {
                return this.fail(
                    StringFormat("point clone failed. rawIndex=%d", i)
                );
            }

            if (!toZigZagPointList.Add(clonedPoint)) {
                delete clonedPoint;
                return this.fail(
                    StringFormat("point add failed. rawIndex=%d", i)
                );
            }
        }

        return true;
    }

    /**
     * 下位足ポイントが上位足境界と一致するか判定する。
     *
     * 上位足レートと一致する候補を優先する。一致候補がない場合は、
     * 上位足バー内にある同じ山谷種別の下位足候補から極値を採用する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromPoint 下位足ポイント
     * @param fromHigherPoint 上位足境界
     * @param fromBoundaryRate 採用する境界レート
     * @return シンボル、山谷、所属時間およびレートが一致する場合true
     */
    bool isBoundaryPoint(
        MarketContext &fromMarketContext,
        ZigZagPoint *fromPoint,
        ZigZagPoint &fromHigherPoint,
        const double fromBoundaryRate
    ) {
        if (!this.isBoundaryCandidate(
                fromMarketContext,
                fromPoint,
                fromHigherPoint
            )) {
            return false;
        }

        return NormalizeDouble(
            fromPoint.rate,
            fromMarketContext.digits
        ) == fromBoundaryRate;
    }

    /**
     * 上位足境界に採用する下位足候補レートを取得する。
     *
     * 親レートと一致する候補があればそのレートを返す。一致候補が
     * なければ、山は最高値、谷は最安値となる候補レートを返す。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromRawPointList 抽出済み下位足ポイント一覧
     * @param fromHigherPoint 上位足境界
     * @param toBoundaryRate 採用する境界レート
     * @return 同じ山谷種別の期間内候補が存在する場合true
     */
    bool getBoundaryRate(
        MarketContext &fromMarketContext,
        CArrayObj &fromRawPointList,
        ZigZagPoint &fromHigherPoint,
        double &toBoundaryRate
    ) {
        double higherRate = NormalizeDouble(
            fromHigherPoint.rate,
            fromMarketContext.digits
        );
        bool hasExactRateCandidate = false;
        bool hasExtremeRate = false;
        double extremeRate = 0;

        for (int i = 0; i < fromRawPointList.Total(); i++) {
            ZigZagPoint *point = fromRawPointList.At(i);

            if (!this.isBoundaryCandidate(
                    fromMarketContext,
                    point,
                    fromHigherPoint
                )) {
                continue;
            }

            double rate = NormalizeDouble(
                point.rate,
                fromMarketContext.digits
            );

            if (rate == higherRate) {
                hasExactRateCandidate = true;
            }

            if (!hasExtremeRate
                    || (fromHigherPoint.isPeak && rate > extremeRate)
                    || (!fromHigherPoint.isPeak && rate < extremeRate)) {
                extremeRate = rate;
                hasExtremeRate = true;
            }
        }

        if (hasExactRateCandidate) {
            toBoundaryRate = higherRate;

            return true;
        }

        if (!hasExtremeRate) {
            return false;
        }

        toBoundaryRate = extremeRate;

        return true;
    }

    /**
     * 下位足ポイントが上位足境界の基本候補か判定する。
     *
     * @param fromMarketContext 期待するシンボルと時間足
     * @param fromPoint 下位足ポイント
     * @param fromHigherPoint 上位足境界
     * @return シンボル、山谷および半開時間範囲が一致する場合true
     */
    bool isBoundaryCandidate(
        MarketContext &fromMarketContext,
        ZigZagPoint *fromPoint,
        ZigZagPoint &fromHigherPoint
    ) {
        if (CheckPointer(fromPoint) == POINTER_INVALID) {
            return false;
        }

        if (fromPoint.marketContext.symbolName
                    != fromMarketContext.symbolName
                || fromPoint.marketContext.symbolName
                    != fromHigherPoint.marketContext.symbolName
                || fromPoint.isPeak != fromHigherPoint.isPeak) {
            return false;
        }

        return fromHigherPoint.barTime <= fromPoint.barTime
            && fromPoint.barTime < fromHigherPoint.barTimeNext;
    }

    /**
     * 市場コンテキストのシンボルと時間足が一致するか判定する。
     *
     * @param fromExpectedContext 期待する市場コンテキスト
     * @param fromActualContext 比較対象の市場コンテキスト
     * @return シンボルと時間足が一致する場合true
     */
    bool isSameMarketContext(
        MarketContext &fromExpectedContext,
        MarketContext &fromActualContext
    ) {
        return fromExpectedContext.symbolName == fromActualContext.symbolName
            && fromExpectedContext.timeFrame == fromActualContext.timeFrame;
    }

    /**
     * 先頭点と終端点が期待方向に一致するか判定する。
     *
     * @param fromFirstPoint 最古ポイント
     * @param fromLatestPoint 最新ポイント
     * @param fromIsUptrend 期待する上位足区間の方向
     * @return 山谷種別と価格方向が一致する場合true
     */
    bool isDirectionMatched(
        ZigZagPoint *fromFirstPoint,
        ZigZagPoint *fromLatestPoint,
        const bool fromIsUptrend
    ) {
        if (CheckPointer(fromFirstPoint) == POINTER_INVALID
                || CheckPointer(fromLatestPoint) == POINTER_INVALID) {
            return false;
        }

        if (fromIsUptrend) {
            return !fromFirstPoint.isPeak
                && fromLatestPoint.isPeak
                && fromFirstPoint.rate < fromLatestPoint.rate;
        }

        return fromFirstPoint.isPeak
            && !fromLatestPoint.isPeak
            && fromFirstPoint.rate > fromLatestPoint.rate;
    }

    /**
     * 構築失敗理由を設定する。
     *
     * @param fromMessage 失敗理由
     * @return 常にfalse
     */
    bool fail(string fromMessage) {
        this.errorMessage = fromMessage;
        return false;
    }
};

#endif // MSTNG_ELLIOT_HIGHER_SEGMENT_POINT_BUILDER_MQH
