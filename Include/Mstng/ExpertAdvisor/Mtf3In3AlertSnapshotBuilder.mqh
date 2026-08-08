//+------------------------------------------------------------------+
//|                        Mtf3In3AlertSnapshotBuilder.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_SNAPSHOT_BUILDER_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_SNAPSHOT_BUILDER_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertSnapshot.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1ElliotStructureDecision.mqh>
#include <Mstng\Util\RateUtil.mqh>

/**
 * MTF_3in3アラート時点の分析結果をDB保存用へ変換するクラス。
 */
class Mtf3In3AlertSnapshotBuilder {
public:
    /**
     * アラート本体、時間足別分析および最新Waveの全ポイントを生成する。
     *
     * @param fromElliotAll 判定に使用した全時間足のElliott分析結果
     * @param fromResult MTF_3in3のアラート判定結果
     * @param fromRunUid プログラム実行を識別するUID
     * @param fromSource 呼び出し元識別子
     * @param fromMagicNumber EAのマジックナンバー。インジケーターは0
     * @param fromAlertText アラート表示本文
     * @param fromSnapshot 生成したスナップショットの格納先
     * @return 全項目を生成できた場合true
     */
    static bool build(
        ElliotAll *fromElliotAll,
        Mtf3In3AlertResult &fromResult,
        const string fromRunUid,
        const string fromSource,
        const ulong fromMagicNumber,
        const string fromAlertText,
        Mtf3In3AlertSnapshot &fromSnapshot
    ) {
        fromSnapshot.clear();

        if (fromElliotAll == NULL
                || !fromElliotAll.isAnalysisSucceeded
                || fromElliotAll.elliotCurrent == NULL
                || !fromResult.isAlert
                || fromRunUid == ""
                || fromSource == "") {
            return false;
        }

        datetime currentBarTime = iTime(
            fromElliotAll.marketContext.symbolName,
            fromElliotAll.marketContext.timeFrame,
            0
        );

        if (currentBarTime <= 0) {
            return false;
        }

        ZigZagPoint *signalReferencePoint =
            fromElliotAll.elliotCurrent.getLatestPoint2();
        datetime signalReferencePointTime = 0;

        if (signalReferencePoint != NULL) {
            signalReferencePointTime = signalReferencePoint.barTime;
        }

        datetime createdAt = getCreatedAt(fromElliotAll);

        if (!buildAlert(
            fromElliotAll,
            fromResult,
            fromRunUid,
            fromSource,
            fromMagicNumber,
            fromAlertText,
            currentBarTime,
            signalReferencePointTime,
            createdAt,
            fromSnapshot.alert
        )) {
            fromSnapshot.clear();

            return false;
        }

        if (!buildTimeFramesAndPoints(
            fromElliotAll,
            signalReferencePoint,
            createdAt,
            fromSnapshot
        ) || !isSignalReferenceValid(
            signalReferencePoint,
            fromSnapshot.points
        )) {
            fromSnapshot.clear();

            return false;
        }

        fromSnapshot.alert.waveSummaryText = buildWaveSummaryText(
            fromSnapshot.timeFrames
        );
        fromSnapshot.alert.snapshotHash = createSnapshotHash(
            fromSnapshot.alert,
            fromSnapshot.timeFrames,
            fromSnapshot.points
        );

        return true;
    }

private:
    /**
     * アラート本体を生成する。
     *
     * @param fromElliotAll Elliott分析結果
     * @param fromResult アラート判定結果
     * @param fromRunUid 実行UID
     * @param fromSource 呼び出し元識別子
     * @param fromMagicNumber マジックナンバー
     * @param fromAlertText アラート表示本文
     * @param fromCurrentBarTime 現在バー開始時刻
     * @param fromSignalReferencePointTime シグナル基準ポイント時刻
     * @param fromCreatedAt レコード生成時刻
     * @param fromEntity 生成先
     * @return 生成できた場合true
     */
    static bool buildAlert(
        ElliotAll *fromElliotAll,
        Mtf3In3AlertResult &fromResult,
        const string fromRunUid,
        const string fromSource,
        const ulong fromMagicNumber,
        const string fromAlertText,
        const datetime fromCurrentBarTime,
        const datetime fromSignalReferencePointTime,
        const datetime fromCreatedAt,
        ZigZagElliotAlertEntity &fromEntity
    ) {
        ZeroMemory(fromEntity);

        CurrencyStrengthExecutionInfo executionInfo =
            fromElliotAll.currencyStrengthExecutionInfo;
        CurrencyStrengthPairRankInfo pairRankInfo =
            executionInfo.pairRankInfo;
        Mtf3In3H1ElliotStructureDecision structureDecision;
        Mtf3In3H1ElliotStructureResult structureResult;
        structureDecision.evaluate(fromElliotAll, structureResult);

        string side = getSide(fromResult.isBuy);
        string marketSignalKey = createMarketSignalKey(
            fromElliotAll.marketContext,
            fromCurrentBarTime,
            fromSignalReferencePointTime,
            side
        );
        double referencePrice = fromElliotAll.todayRate.bid;

        if (fromResult.isBuy) {
            referencePrice = fromElliotAll.todayRate.ask;
        }

        double stopLoss = fromElliotAll.lossCut.lc5;
        bool isStopLossAvailable = referencePrice > 0.0
            && stopLoss > 0.0;
        double riskPips = 0.0;

        if (isStopLossAvailable) {
            riskPips = RateUtil::getDiffPips(
                referencePrice,
                stopLoss,
                fromElliotAll.marketContext
            );
        }

        fromEntity.id = 0;
        fromEntity.runId = 0;
        fromEntity.eventUid = fromRunUid + "|" + marketSignalKey;
        fromEntity.marketSignalKey = marketSignalKey;
        fromEntity.snapshotHash = "";
        fromEntity.serverTime = fromElliotAll.tradeTimeInfo.serverTime;
        fromEntity.serverTimeText = formatDateTime(fromEntity.serverTime);
        fromEntity.jstTime = fromElliotAll.tradeTimeInfo.jstTime;
        fromEntity.jstTimeText = formatDateTime(fromEntity.jstTime);
        fromEntity.currentBarTime = fromCurrentBarTime;
        fromEntity.currentBarTimeText = formatDateTime(
            fromCurrentBarTime
        );
        fromEntity.signalReferencePointTime =
            fromSignalReferencePointTime;
        fromEntity.signalReferencePointTimeText = formatDateTime(
            fromSignalReferencePointTime
        );
        fromEntity.symbolName = normalizeText(
            fromElliotAll.marketContext.symbolName
        );
        fromEntity.timeFrame = (int)fromElliotAll.marketContext.timeFrame;
        fromEntity.timeFrameText = normalizeText(
            fromElliotAll.marketContext.timeFrameLabel
        );
        fromEntity.magicNumber = StringFormat("%I64u", fromMagicNumber);
        fromEntity.strategy = "MTF_3in3";
        fromEntity.side = side;
        fromEntity.isJudge = boolToInteger(fromResult.isJudge);
        fromEntity.signalCount = fromResult.signalCount;
        fromEntity.entryCount = fromResult.entryCount;
        fromEntity.isEntryCountMatch = boolToInteger(
            fromResult.isEntryCountMatch
        );
        fromEntity.isEntryEvaluated = boolToInteger(
            fromResult.isEntryEvaluated
        );
        fromEntity.isAlert = boolToInteger(fromResult.isAlert);
        fromEntity.isEntry = boolToInteger(fromResult.isEntry);
        fromEntity.entryResult = normalizeText(fromResult.entryResult);
        fromEntity.isSendMail = boolToInteger(fromResult.isSendMail);
        fromEntity.currentElliotLabel = normalizeText(
            fromResult.currentElliotLabel
        );
        fromEntity.isEntryWave = boolToInteger(fromResult.isEntryWave);
        fromEntity.closeEma200DiffPips =
            fromResult.closeEma200DiffPips;
        fromEntity.maxCloseEma200DiffPips =
            fromResult.maxCloseEma200DiffPips;
        fromEntity.isEma200DistanceWithin = boolToInteger(
            fromResult.isEma200DistanceWithin
        );
        fromEntity.spreadPips = fromElliotAll.todayRate.spread;
        fromEntity.isCurrencyStrengthEnabled = boolToInteger(
            fromElliotAll.isCurrencyStrengthEntryFilterEnabled
        );
        fromEntity.currencyStrengthStatus = (int)executionInfo.status;
        fromEntity.isCurrencyStrengthAvailable = boolToInteger(
            executionInfo.isAvailable()
        );
        fromEntity.currencyStrengthCalculationVersion = normalizeText(
            executionInfo.calculationVersion
        );
        fromEntity.currencyStrengthRunId = pairRankInfo.runId;
        fromEntity.currencyStrengthSourceMode = normalizeText(
            executionInfo.sourceMode
        );
        fromEntity.currencyStrengthTargetM5BarTime =
            executionInfo.targetM5BarTime;
        fromEntity.currencyStrengthM5BarTime = pairRankInfo.m5BarTime;
        fromEntity.baseCurrency = normalizeText(pairRankInfo.baseCurrency);
        fromEntity.baseLongMediumRank =
            pairRankInfo.baseLongMediumTermAverageRank;
        fromEntity.baseMediumShortRank =
            pairRankInfo.baseMediumShortTermAverageRank;
        fromEntity.quoteCurrency = normalizeText(
            pairRankInfo.quoteCurrency
        );
        fromEntity.quoteLongMediumRank =
            pairRankInfo.quoteLongMediumTermAverageRank;
        fromEntity.quoteMediumShortRank =
            pairRankInfo.quoteMediumShortTermAverageRank;
        fromEntity.longMediumRankDifference =
            executionInfo.getLongMediumRankDifference();
        fromEntity.mediumShortRankDifference =
            executionInfo.getMediumShortRankDifference();
        fromEntity.referencePrice = referencePrice;
        fromEntity.isStopLossAvailable = boolToInteger(
            isStopLossAvailable
        );
        fromEntity.stopLoss = stopLoss;
        fromEntity.riskPips = riskPips;
        fromEntity.h1StructureRank = normalizeText(
            structureResult.getRankLabel()
        );
        fromEntity.isH1StructureValid = boolToInteger(
            structureResult.isStructureValid
        );
        fromEntity.isH1StructureLate = boolToInteger(
            structureResult.isLate
        );
        fromEntity.isH1DirectionException = boolToInteger(
            structureResult.isDirectionException
        );
        fromEntity.alertTitle = normalizeText(fromElliotAll.mailTitile);
        fromEntity.alertText = normalizeText(fromAlertText);
        fromEntity.waveSummaryText = "";
        fromEntity.elliotCsvText = normalizeText(
            fromElliotAll.getCsv(true)
        );
        fromEntity.createdAt = fromCreatedAt;
        fromEntity.createdAtText = formatDateTime(fromCreatedAt);

        return true;
    }

    /**
     * 全時間足と各時間足の最新Waveポイントを生成する。
     *
     * @param fromElliotAll Elliott分析結果
     * @param fromSignalReferencePoint シグナル基準ポイント
     * @param fromCreatedAt レコード生成時刻
     * @param fromSnapshot 生成先
     * @return 全時間足を生成できた場合true
     */
    static bool buildTimeFramesAndPoints(
        ElliotAll *fromElliotAll,
        ZigZagPoint *fromSignalReferencePoint,
        const datetime fromCreatedAt,
        Mtf3In3AlertSnapshot &fromSnapshot
    ) {
        int timeFrameCount = fromElliotAll.elliotList.Total();

        if (timeFrameCount <= 0
                || ArrayResize(
                    fromSnapshot.timeFrames,
                    timeFrameCount
                ) != timeFrameCount) {
            return false;
        }

        int timeFrameOrder = 0;

        for (int i = timeFrameCount - 1; i >= 0; i--) {
            Elliot *elliot = fromElliotAll.elliotList.At(i);

            if (elliot == NULL) {
                return false;
            }

            Wave *latestWave = elliot.getLatestWave();
            ZigZagPoint *latestPoint = elliot.getLatestPoint();

            if (latestWave == NULL || latestPoint == NULL) {
                return false;
            }

            ZigZagElliotAlertTimeFrameEntity timeFrameEntity;

            if (!buildTimeFrame(
                elliot,
                latestWave,
                latestPoint,
                timeFrameOrder,
                fromElliotAll.marketContext.timeFrame,
                fromCreatedAt,
                timeFrameEntity
            )) {
                return false;
            }

            fromSnapshot.timeFrames[timeFrameOrder] = timeFrameEntity;

            if (!appendPoints(
                elliot,
                latestWave,
                fromSignalReferencePoint,
                fromElliotAll.marketContext.timeFrame,
                fromCreatedAt,
                fromSnapshot.points
            )) {
                return false;
            }

            timeFrameOrder++;
        }

        return true;
    }

    /**
     * 1時間足分のElliott分析を生成する。
     *
     * @param fromElliot 対象時間足のElliott分析
     * @param fromLatestWave 最新Wave
     * @param fromLatestPoint 最新ポイント
     * @param fromTimeFrameOrder 上位足からの表示順
     * @param fromCurrentTimeFrame アラートの現在時間足
     * @param fromCreatedAt レコード生成時刻
     * @param fromEntity 生成先
     * @return 生成できた場合true
     */
    static bool buildTimeFrame(
        Elliot *fromElliot,
        Wave *fromLatestWave,
        ZigZagPoint *fromLatestPoint,
        const int fromTimeFrameOrder,
        const ENUM_TIMEFRAMES fromCurrentTimeFrame,
        const datetime fromCreatedAt,
        ZigZagElliotAlertTimeFrameEntity &fromEntity
    ) {
        ZeroMemory(fromEntity);

        FiboExpansionPriceInfo *fiboInfo =
            &(fromElliot.fiboExpansionPriceInfo);
        Oscillator *oscillator = &(fromElliot.oscillator);
        Ema200 *ema200 = &(fromElliot.oscillator.ema200);

        fromEntity.id = 0;
        fromEntity.alertId = 0;
        fromEntity.timeFrame = (int)fromElliot.marketContext.timeFrame;
        fromEntity.timeFrameText = normalizeText(
            fromElliot.marketContext.timeFrameLabel
        );
        fromEntity.timeFrameOrder = fromTimeFrameOrder;
        fromEntity.isCurrentTimeFrame = boolToInteger(
            fromElliot.marketContext.timeFrame == fromCurrentTimeFrame
        );
        fromEntity.isBuy = boolToInteger(fromElliot.isBuy);
        fromEntity.buySellLabel = normalizeText(fromElliot.buySellLabel);
        fromEntity.waveCount = fromElliot.waveList.Total();
        fromEntity.latestWaveIndex = fromLatestWave.index;
        fromEntity.isWaveConfirmed = boolToInteger(
            fromLatestWave.isConfirmed
        );
        fromEntity.isWaveMotive = boolToInteger(fromLatestWave.isMotive);
        fromEntity.isWaveUptrend = boolToInteger(
            fromLatestWave.isUptrend
        );
        fromEntity.waveTrendLabel = normalizeText(
            fromLatestWave.trendLabel
        );
        fromEntity.previousLastElliotLabel = normalizeText(
            fromLatestWave.previousLastElliotLabel
        );
        fromEntity.pointCount = fromLatestWave.zigZagPointList.Total();
        fromEntity.latestElliotIndex = fromLatestPoint.elliotIndex;
        fromEntity.latestElliotLabel = normalizeText(
            fromLatestPoint.elliotLabel
        );
        fromEntity.latestSubElliotIndex = fromLatestPoint.subElliotIndex;
        fromEntity.latestSubElliotLabel = normalizeText(
            fromLatestPoint.subElliotLabel
        );
        fromEntity.previousOpen = fromElliot.previousOhlcInfo.open;
        fromEntity.previousHigh = fromElliot.previousOhlcInfo.high;
        fromEntity.previousLow = fromElliot.previousOhlcInfo.low;
        fromEntity.previousClose = fromElliot.previousOhlcInfo.close;
        fromEntity.currentOpen = fromElliot.currentOhlcInfo.open;
        fromEntity.currentHigh = fromElliot.currentOhlcInfo.high;
        fromEntity.currentLow = fromElliot.currentOhlcInfo.low;
        fromEntity.currentClose = fromElliot.currentOhlcInfo.close;
        fromEntity.isFiboExpansionAvailable = boolToInteger(
            fiboInfo.FE618Price > 0.0 && fiboInfo.FE2000Price > 0.0
        );
        fromEntity.fe618Price = fiboInfo.FE618Price;
        fromEntity.fe1000Price = fiboInfo.FE1000Price;
        fromEntity.fe1272Price = fiboInfo.FE1272Price;
        fromEntity.fe1618Price = fiboInfo.FE1618Price;
        fromEntity.fe2000Price = fiboInfo.FE2000Price;
        fromEntity.distanceToFe2000Pips =
            fiboInfo.DistanceToFE2000Pips;
        fromEntity.oscillatorCount = oscillator.oscillatorCount;
        fromEntity.isOscillatorBuy = boolToInteger(oscillator.isBuy);
        fromEntity.stochasticMainOrder =
            (int)oscillator.stochasticMainOrder;
        fromEntity.stochasticMainOrderText = normalizeText(
            oscillator.getStochasticMainOrderText()
        );
        fromEntity.stochasticMainDirectionText = normalizeText(
            oscillator.getStochasticMainOrderDirectionText()
        );
        fromEntity.stochasticShortCount = oscillator.stochasticShort.count;
        fromEntity.stochasticShortMain = oscillator.stochasticShort.main0;
        fromEntity.stochasticShortSignal =
            oscillator.stochasticShort.signal0;
        fromEntity.stochasticMiddleCount =
            oscillator.stochasticMiddle.count;
        fromEntity.stochasticMiddleMain = oscillator.stochasticMiddle.main0;
        fromEntity.stochasticMiddleSignal =
            oscillator.stochasticMiddle.signal0;
        fromEntity.stochasticLongCount = oscillator.stochasticLong.count;
        fromEntity.stochasticLongMain = oscillator.stochasticLong.main0;
        fromEntity.stochasticLongSignal = oscillator.stochasticLong.signal0;
        fromEntity.gmmaTrendCount = oscillator.gmmaTrendCount;
        fromEntity.gmmaCrossCount = oscillator.gmmaCrossCount;
        fromEntity.ema30 = oscillator.ema30;
        fromEntity.ema60 = oscillator.ema60;
        fromEntity.ema30Ema60DiffPips = oscillator.ema30Ema60DiffPips;
        fromEntity.atr14Pips = oscillator.atr14;
        fromEntity.ema200Close1 = ema200.close1;
        fromEntity.ema200Shift1 = ema200.ema200Shift1;
        fromEntity.ema200Compare = ema200.ema200Compare;
        fromEntity.ema200SlopePips = ema200.slopePips;
        fromEntity.ema200CloseDiffPips = ema200.closeEma200DiffPips;
        fromEntity.ema200ClosePosition = (int)ema200.closePosition;
        fromEntity.ema200SlopeDirection = (int)ema200.slopeDirection;
        fromEntity.ema200UpCount = ema200.upCount;
        fromEntity.ema200DownCount = ema200.downCount;
        fromEntity.ema200TrendCount = ema200.trendCount;
        fromEntity.isEma200Buy = boolToInteger(ema200.isBuy);
        fromEntity.isEma200Sell = boolToInteger(ema200.isSell);
        fromEntity.rawCsvText = normalizeText(fromElliot.getCsv(true));
        fromEntity.createdAt = fromCreatedAt;
        fromEntity.createdAtText = formatDateTime(fromCreatedAt);

        return fromEntity.pointCount > 0;
    }

    /**
     * 1時間足の最新Waveポイントを配列へ追加する。
     *
     * @param fromElliot 対象時間足のElliott分析
     * @param fromLatestWave 最新Wave
     * @param fromSignalReferencePoint シグナル基準ポイント
     * @param fromCurrentTimeFrame アラートの現在時間足
     * @param fromCreatedAt レコード生成時刻
     * @param fromEntities 追加先配列
     * @return 全ポイントを追加できた場合true
     */
    static bool appendPoints(
        Elliot *fromElliot,
        Wave *fromLatestWave,
        ZigZagPoint *fromSignalReferencePoint,
        const ENUM_TIMEFRAMES fromCurrentTimeFrame,
        const datetime fromCreatedAt,
        ZigZagElliotAlertPointEntity &fromEntities[]
    ) {
        int pointCount = fromLatestWave.zigZagPointList.Total();

        if (pointCount <= 0) {
            return false;
        }

        bool isCurrentTimeFrame =
            fromElliot.marketContext.timeFrame == fromCurrentTimeFrame;

        for (int i = 0; i < pointCount; i++) {
            ZigZagPoint *point = fromLatestWave.zigZagPointList.At(i);

            if (point == NULL) {
                return false;
            }

            bool isSignalReference = isCurrentTimeFrame
                && fromSignalReferencePoint != NULL
                && point.barTime == fromSignalReferencePoint.barTime;
            ZigZagElliotAlertPointEntity pointEntity;
            buildPoint(
                point,
                fromElliot.marketContext.timeFrame,
                i,
                pointCount,
                isSignalReference,
                fromCreatedAt,
                pointEntity
            );

            int entityIndex = ArraySize(fromEntities);

            if (ArrayResize(fromEntities, entityIndex + 1)
                    != entityIndex + 1) {
                return false;
            }

            fromEntities[entityIndex] = pointEntity;
        }

        return true;
    }

    /**
     * 1つのZigZagポイントを生成する。
     *
     * @param fromPoint 元のZigZagポイント
     * @param fromTimeFrame 親時間足
     * @param fromPointOrder 最新Wave内の順序。0が最古
     * @param fromPointCount 最新Waveのポイント数
     * @param fromIsSignalReference シグナル基準ポイントの場合true
     * @param fromCreatedAt レコード生成時刻
     * @param fromEntity 生成先
     */
    static void buildPoint(
        ZigZagPoint *fromPoint,
        const ENUM_TIMEFRAMES fromTimeFrame,
        const int fromPointOrder,
        const int fromPointCount,
        const bool fromIsSignalReference,
        const datetime fromCreatedAt,
        ZigZagElliotAlertPointEntity &fromEntity
    ) {
        ZeroMemory(fromEntity);

        bool isFibonacciAvailable = fromPointOrder >= 2
            && fromPointOrder % 2 == 0;
        bool isFibonacciExpansionAvailable = fromPointOrder >= 3
            && fromPointOrder % 2 != 0;

        fromEntity.id = 0;
        fromEntity.alertTimeFrameId = 0;
        fromEntity.timeFrame = (int)fromTimeFrame;
        fromEntity.pointOrder = fromPointOrder;
        fromEntity.isLatest = boolToInteger(
            fromPointOrder == fromPointCount - 1
        );
        fromEntity.isSignalReference = boolToInteger(
            fromIsSignalReference
        );
        fromEntity.rate = fromPoint.rate;
        fromEntity.barIndex = fromPoint.barIndex;
        fromEntity.barTime = fromPoint.barTime;
        fromEntity.barTimeText = formatDateTime(fromPoint.barTime);
        fromEntity.isBarTimeNextAvailable = boolToInteger(
            fromPoint.barTimeNext > 0
        );
        fromEntity.barTimeNext = fromPoint.barTimeNext;
        fromEntity.barTimeNextText = formatDateTime(
            fromPoint.barTimeNext
        );
        fromEntity.waveBarsFromStart = fromPoint.waveBarsFromStart;
        fromEntity.isPeak = boolToInteger(fromPoint.isPeak);
        fromEntity.isAddedPoint = boolToInteger(fromPoint.isAddedPoint);
        fromEntity.pipsDiff = fromPoint.pipsDiff;
        fromEntity.isFibonacciAvailable = boolToInteger(
            isFibonacciAvailable
        );
        fromEntity.fibonacciPercent = fromPoint.fibonacciPercent;
        fromEntity.fiboDepthZone = (int)fromPoint.fiboDepthZone;
        fromEntity.fiboDepthZoneLabel = normalizeText(
            fromPoint.fiboDepthZoneLabel
        );
        fromEntity.isFibonacciExpansionAvailable = boolToInteger(
            isFibonacciExpansionAvailable
        );
        fromEntity.fibonacciExpansionPercent =
            fromPoint.fibonacciExpansionPercent;
        fromEntity.isElliotAlphabet = boolToInteger(
            fromPoint.isElliotAlphabet
        );
        fromEntity.elliotIndex = fromPoint.elliotIndex;
        fromEntity.elliotLabel = normalizeText(fromPoint.elliotLabel);
        string subElliotLabel = normalizeText(fromPoint.subElliotLabel);
        fromEntity.isSubElliotAvailable = boolToInteger(
            subElliotLabel != ""
                || fromPoint.subElliotIndex != 0
        );
        fromEntity.subElliotIndex = fromPoint.subElliotIndex;
        fromEntity.subElliotLabel = subElliotLabel;
        string orgElliotLabel = normalizeText(fromPoint.orgElliotLabel);
        fromEntity.isOriginalElliotAvailable = boolToInteger(
            orgElliotLabel != ""
                || fromPoint.orgElliotIndex != 0
        );
        fromEntity.orgElliotIndex = fromPoint.orgElliotIndex;
        fromEntity.orgElliotLabel = orgElliotLabel;
        fromEntity.isCorrect = boolToInteger(fromPoint.isCorrect);
        fromEntity.createdAt = fromCreatedAt;
        fromEntity.createdAtText = formatDateTime(fromCreatedAt);
    }

    /**
     * シグナル基準ポイントの保存件数を確認する。
     *
     * @param fromSignalReferencePoint シグナル基準ポイント
     * @param fromEntities 最新Waveポイント一覧
     * @return 基準ポイントの有無と保存件数が一致する場合true
     */
    static bool isSignalReferenceValid(
        ZigZagPoint *fromSignalReferencePoint,
        ZigZagElliotAlertPointEntity &fromEntities[]
    ) {
        int expectedCount = 0;

        if (fromSignalReferencePoint != NULL) {
            expectedCount = 1;
        }

        int actualCount = 0;

        for (int i = 0; i < ArraySize(fromEntities); i++) {
            if (fromEntities[i].isSignalReference == 1) {
                actualCount++;
            }
        }

        return actualCount == expectedCount;
    }

    /**
     * DB保存時刻を取得する。
     *
     * @param fromElliotAll Elliott分析結果
     * @return 利用可能な実行時刻。取得できない場合0
     */
    static datetime getCreatedAt(ElliotAll *fromElliotAll) {
        datetime createdAt = TimeCurrent();

        if (createdAt <= 0) {
            createdAt = fromElliotAll.tradeTimeInfo.serverTime;
        }

        if (createdAt <= 0) {
            createdAt = TimeLocal();
        }

        return createdAt;
    }

    /**
     * 実行間で共通となる市場シグナルキーを生成する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromCurrentBarTime 現在バー開始時刻
     * @param fromSignalReferencePointTime シグナル基準ポイント時刻
     * @param fromSide 売買方向
     * @return 市場シグナルキー
     */
    static string createMarketSignalKey(
        MarketContext &fromMarketContext,
        const datetime fromCurrentBarTime,
        const datetime fromSignalReferencePointTime,
        const string fromSide
    ) {
        return StringFormat(
            "%s|%s|%d|%I64d|%I64d|MTF_3in3|%s",
            AccountInfoString(ACCOUNT_SERVER),
            fromMarketContext.symbolName,
            (int)fromMarketContext.timeFrame,
            (long)fromCurrentBarTime,
            (long)fromSignalReferencePointTime,
            fromSide
        );
    }

    /**
     * 時間足別の波動概要を上位足から連結する。
     *
     * @param fromEntities 時間足別分析一覧
     * @return 波動概要
     */
    static string buildWaveSummaryText(
        ZigZagElliotAlertTimeFrameEntity &fromEntities[]
    ) {
        string summary = "";
        int total = ArraySize(fromEntities);

        for (int i = 0; i < total; i++) {
            if (summary != "") {
                summary += " | ";
            }

            summary += StringFormat(
                "%s:%s:%s:%s:%s:%s",
                fromEntities[i].timeFrameText,
                fromEntities[i].buySellLabel,
                getWaveTypeText(fromEntities[i].isWaveMotive),
                getWaveDirectionText(fromEntities[i].isWaveUptrend),
                fromEntities[i].latestElliotLabel,
                getConfirmedText(fromEntities[i].isWaveConfirmed)
            );
        }

        return summary;
    }

    /**
     * アラート内容の安定ハッシュを生成する。
     *
     * @param fromEntity アラート本体
     * @param fromTimeFrameEntities 時間足別分析一覧
     * @param fromPointEntities 最新Waveポイント一覧
     * @return 16進16桁のハッシュ
     */
    static string createSnapshotHash(
        ZigZagElliotAlertEntity &fromEntity,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotAlertPointEntity &fromPointEntities[]
    ) {
        string sourceText = fromEntity.marketSignalKey;
        sourceText += "|" + fromEntity.entryResult;
        sourceText += "|" + IntegerToString(fromEntity.signalCount);
        sourceText += "|" + IntegerToString(fromEntity.entryCount);
        sourceText += "|" + IntegerToString(fromEntity.isEntry);
        sourceText += "|" + StringFormat(
            "%I64d",
            fromEntity.currencyStrengthRunId
        );
        sourceText += "|" + DoubleToString(fromEntity.referencePrice, 8);
        sourceText += "|" + DoubleToString(fromEntity.stopLoss, 8);
        sourceText += "|" + fromEntity.h1StructureRank;
        sourceText += "|" + fromEntity.waveSummaryText;
        sourceText += "|" + fromEntity.elliotCsvText;
        sourceText += "|" + fromEntity.alertText;

        for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
            sourceText += "|TF:";
            sourceText += IntegerToString(
                fromTimeFrameEntities[i].timeFrame
            );
            sourceText += ":" + IntegerToString(
                fromTimeFrameEntities[i].timeFrameOrder
            );
            sourceText += ":" + fromTimeFrameEntities[i].rawCsvText;
        }

        for (int i = 0; i < ArraySize(fromPointEntities); i++) {
            sourceText += "|POINT:";
            sourceText += IntegerToString(fromPointEntities[i].timeFrame);
            sourceText += ":" + IntegerToString(
                fromPointEntities[i].pointOrder
            );
            sourceText += ":" + StringFormat(
                "%I64d",
                (long)fromPointEntities[i].barTime
            );
            sourceText += ":" + StringFormat(
                "%I64d",
                (long)fromPointEntities[i].barTimeNext
            );
            sourceText += ":" + DoubleToString(
                fromPointEntities[i].rate,
                8
            );
            sourceText += ":" + DoubleToString(
                fromPointEntities[i].pipsDiff,
                8
            );
            sourceText += ":" + DoubleToString(
                fromPointEntities[i].fibonacciPercent,
                8
            );
            sourceText += ":" + DoubleToString(
                fromPointEntities[i].fibonacciExpansionPercent,
                8
            );
            sourceText += ":" + IntegerToString(
                fromPointEntities[i].elliotIndex
            );
            sourceText += ":" + fromPointEntities[i].elliotLabel;
            sourceText += ":" + IntegerToString(
                fromPointEntities[i].subElliotIndex
            );
            sourceText += ":" + fromPointEntities[i].subElliotLabel;
            sourceText += ":" + IntegerToString(
                fromPointEntities[i].orgElliotIndex
            );
            sourceText += ":" + fromPointEntities[i].orgElliotLabel;
            sourceText += ":" + IntegerToString(
                fromPointEntities[i].isAddedPoint
            );
            sourceText += ":" + IntegerToString(
                fromPointEntities[i].isCorrect
            );
        }

        uint hash1 = 2166136261;
        uint hash2 = 5381;
        int length = StringLen(sourceText);

        for (int i = 0; i < length; i++) {
            uint character = (uint)StringGetCharacter(sourceText, i);
            hash1 = (hash1 ^ character) * 16777619;
            hash2 = ((hash2 << 5) + hash2) ^ character;
        }

        return StringFormat("%08X%08X", hash1, hash2);
    }

    /**
     * datetimeをDB確認用文字列へ変換する。
     *
     * @param fromDateTime 変換対象日時
     * @return 日時文字列。未設定の場合は空文字列
     */
    static string formatDateTime(const datetime fromDateTime) {
        if (fromDateTime <= 0) {
            return "";
        }

        return TimeToString(fromDateTime, TIME_DATE | TIME_SECONDS);
    }

    /**
     * DB保存用文字列のNULLを空文字列へ変換する。
     *
     * @param fromText 対象文字列
     * @return NULLの場合は空文字列、それ以外は元の文字列
     */
    static string normalizeText(const string fromText) {
        if (fromText == NULL) {
            return "";
        }

        return fromText;
    }

    /**
     * bool値をDB保存用整数へ変換する。
     *
     * @param fromValue 変換対象値
     * @return trueの場合1、falseの場合0
     */
    static int boolToInteger(const bool fromValue) {
        if (fromValue) {
            return 1;
        }

        return 0;
    }

    /**
     * 売買方向文字列を取得する。
     *
     * @param fromIsBuy BUYの場合true
     * @return BUYまたはSELL
     */
    static string getSide(const bool fromIsBuy) {
        if (fromIsBuy) {
            return "BUY";
        }

        return "SELL";
    }

    /**
     * Wave種別を取得する。
     *
     * @param fromIsMotive 推進波の場合1
     * @return MOTIVEまたはCORRECTIVE
     */
    static string getWaveTypeText(const int fromIsMotive) {
        if (fromIsMotive == 1) {
            return "MOTIVE";
        }

        return "CORRECTIVE";
    }

    /**
     * Wave方向を取得する。
     *
     * @param fromIsUptrend 上昇方向の場合1
     * @return UPまたはDOWN
     */
    static string getWaveDirectionText(const int fromIsUptrend) {
        if (fromIsUptrend == 1) {
            return "UP";
        }

        return "DOWN";
    }

    /**
     * Wave確定状態を取得する。
     *
     * @param fromIsConfirmed 確定済みの場合1
     * @return CONFIRMEDまたはUNCONFIRMED
     */
    static string getConfirmedText(const int fromIsConfirmed) {
        if (fromIsConfirmed == 1) {
            return "CONFIRMED";
        }

        return "UNCONFIRMED";
    }
};

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_SNAPSHOT_BUILDER_MQH
