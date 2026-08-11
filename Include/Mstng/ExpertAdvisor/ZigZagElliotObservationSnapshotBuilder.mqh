//+------------------------------------------------------------------+
//|           ZigZagElliotObservationSnapshotBuilder.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_ZIGZAG_ELLIOT_OBSERVATION_BUILDER_MQH
#define MSTNG_EXPERT_ADVISOR_ZIGZAG_ELLIOT_OBSERVATION_BUILDER_MQH

#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\ExpertAdvisor\ZigZagElliotObservationSnapshot.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>

/**
 * H1新規足時点のElliott分析結果をDB保存用へ変換するクラス。
 *
 * 親観測とMN1、W1、D1、H4、H1の構造化スカラーだけを生成し、
 * 監査用CSVおよびWaveポイント配列は保持しない。
 */
class ZigZagElliotObservationSnapshotBuilder {
public:
    /**
     * H1観測スナップショットを生成する。
     *
     * @param fromElliotAll H1までのElliott分析結果
     * @param fromRunEntity 保存済み実行情報
     * @param fromAnchorBarTime 観測基準となるH1バー開始時刻
     * @param fromSnapshot 生成したスナップショットの格納先
     * @return 全項目を生成できた場合true
     */
    static bool build(
        ElliotAll *fromElliotAll,
        ZigZagElliotAlertRunEntity &fromRunEntity,
        const datetime fromAnchorBarTime,
        ZigZagElliotObservationSnapshot &fromSnapshot
    ) {
        fromSnapshot.clear();

        if (!isInputValid(
            fromElliotAll,
            fromRunEntity,
            fromAnchorBarTime
        )) {
            return false;
        }

        datetime createdAt = getCreatedAt(fromElliotAll);

        if (createdAt <= 0
                || !buildTimeFrames(
                    fromElliotAll,
                    createdAt,
                    fromSnapshot.timeFrames
                )) {
            fromSnapshot.clear();

            return false;
        }

        buildObservation(
            fromElliotAll,
            fromRunEntity,
            fromAnchorBarTime,
            createdAt,
            fromSnapshot.timeFrames,
            fromSnapshot.observation
        );
        fromSnapshot.observation.snapshotHash = createSnapshotHash(
            fromSnapshot.observation,
            fromSnapshot.timeFrames
        );

        if (fromSnapshot.observation.snapshotHash == "") {
            fromSnapshot.clear();

            return false;
        }

        return true;
    }

private:
    /**
     * Builder入力がH1観測に利用できるか判定する。
     *
     * @param fromElliotAll H1までのElliott分析結果
     * @param fromRunEntity 保存済み実行情報
     * @param fromAnchorBarTime H1バー開始時刻
     * @return 利用できる場合true
     */
    static bool isInputValid(
        ElliotAll *fromElliotAll,
        ZigZagElliotAlertRunEntity &fromRunEntity,
        const datetime fromAnchorBarTime
    ) {
        if (fromElliotAll == NULL
                || !fromElliotAll.isAnalysisSucceeded
                || fromElliotAll.elliotCurrent == NULL
                || fromAnchorBarTime <= 0
                || fromRunEntity.id <= 0
                || normalizeText(fromRunEntity.analysisInputHash) == ""
                || normalizeText(fromRunEntity.sourceMode) == "") {
            return false;
        }

        if (fromElliotAll.marketContext.timeFrame
                != ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
                || fromElliotAll.elliotCurrent.marketContext.timeFrame
                    != ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
                || fromElliotAll.elliotList.Total()
                    != ZigZagElliotAnalysisProfile::getObservationTimeFrameCount()) {
            return false;
        }

        return true;
    }

    /**
     * 観測親Entityを生成する。
     *
     * @param fromElliotAll H1までのElliott分析結果
     * @param fromRunEntity 保存済み実行情報
     * @param fromAnchorBarTime H1バー開始時刻
     * @param fromCreatedAt レコード生成時刻
     * @param fromTimeFrameEntities 時間足別分析一覧
     * @param fromEntity 生成先
     */
    static void buildObservation(
        ElliotAll *fromElliotAll,
        ZigZagElliotAlertRunEntity &fromRunEntity,
        const datetime fromAnchorBarTime,
        const datetime fromCreatedAt,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotObservationEntity &fromEntity
    ) {
        ZeroMemory(fromEntity);
        fromEntity.id = 0;
        fromEntity.runId = fromRunEntity.id;
        fromEntity.sourceMode = normalizeText(fromRunEntity.sourceMode);
        fromEntity.sourceServer = normalizeText(fromRunEntity.sourceServer);
        fromEntity.symbolName = normalizeText(
            fromElliotAll.marketContext.symbolName
        );
        fromEntity.anchorTimeFrame = (int)
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame();
        fromEntity.anchorTimeFrameText = normalizeText(
            fromElliotAll.marketContext.timeFrameLabel
        );
        fromEntity.anchorBarTime = fromAnchorBarTime;
        fromEntity.anchorBarTimeText = formatDateTime(fromAnchorBarTime);
        fromEntity.anchorJstTime = TimeJapanUtil::getJapanTime(
            fromAnchorBarTime
        );
        fromEntity.anchorJstTimeText = formatDateTime(
            fromEntity.anchorJstTime
        );
        fromEntity.capturePhase = "BAR_OPEN_FIRST_SUCCESS";
        fromEntity.analysisVersion = normalizeText(
            fromRunEntity.analysisVersion
        );
        fromEntity.analysisInputHash = normalizeText(
            fromRunEntity.analysisInputHash
        );
        fromEntity.snapshotHash = "";
        fromEntity.timeFrameCount = ArraySize(fromTimeFrameEntities);
        fromEntity.createdAt = fromCreatedAt;
        fromEntity.createdAtText = formatDateTime(fromCreatedAt);
    }

    /**
     * MN1、W1、D1、H4、H1の時間足別Entityを生成する。
     *
     * ElliotAllの一覧は現在足から上位足の順であるため、逆順に走査して
     * 保存時の表示順を固定する。
     *
     * @param fromElliotAll H1までのElliott分析結果
     * @param fromCreatedAt レコード生成時刻
     * @param fromEntities 生成先配列
     * @return 5時間足を生成できた場合true
     */
    static bool buildTimeFrames(
        ElliotAll *fromElliotAll,
        const datetime fromCreatedAt,
        ZigZagElliotObservationTimeFrameEntity &fromEntities[]
    ) {
        int total = fromElliotAll.elliotList.Total();

        if (total
                != ZigZagElliotAnalysisProfile::getObservationTimeFrameCount()
                || ArrayResize(fromEntities, total) != total) {
            return false;
        }

        for (int i = 0; i < total; i++) {
            int sourceIndex = total - 1 - i;
            Elliot *elliot = fromElliotAll.elliotList.At(sourceIndex);

            if (elliot == NULL
                    || elliot.marketContext.timeFrame
                        != ZigZagElliotAnalysisProfile::getObservationTimeFrame(i)) {
                return false;
            }

            Wave *latestWave = elliot.getLatestWave();
            ZigZagPoint *latestPoint = elliot.getLatestPoint();

            if (latestWave == NULL
                    || latestPoint == NULL
                    || latestWave.zigZagPointList.Total() <= 0
                    || latestPoint.barTime <= 0) {
                return false;
            }

            if (!buildTimeFrame(
                elliot,
                latestWave,
                latestPoint,
                i,
                fromCreatedAt,
                fromEntities[i]
            )) {
                return false;
            }
        }

        return true;
    }

    /**
     * 1時間足分の構造化Elliott分析Entityを生成する。
     *
     * @param fromElliot 対象時間足のElliott分析
     * @param fromLatestWave 最新Wave
     * @param fromLatestPoint 最新ポイント
     * @param fromTimeFrameOrder 上位足からの表示順
     * @param fromCreatedAt レコード生成時刻
     * @param fromEntity 生成先
     * @return 生成できた場合true
     */
    static bool buildTimeFrame(
        Elliot *fromElliot,
        Wave *fromLatestWave,
        ZigZagPoint *fromLatestPoint,
        const int fromTimeFrameOrder,
        const datetime fromCreatedAt,
        ZigZagElliotObservationTimeFrameEntity &fromEntity
    ) {
        ZeroMemory(fromEntity);

        FiboExpansionPriceInfo *fiboInfo =
            &(fromElliot.fiboExpansionPriceInfo);
        Oscillator *oscillator = &(fromElliot.oscillator);
        Ema200 *ema200 = &(fromElliot.oscillator.ema200);

        fromEntity.id = 0;
        fromEntity.observationId = 0;
        fromEntity.timeFrame = (int)fromElliot.marketContext.timeFrame;
        fromEntity.timeFrameText = normalizeText(
            fromElliot.marketContext.timeFrameLabel
        );
        fromEntity.timeFrameOrder = fromTimeFrameOrder;
        fromEntity.isAnchorTimeFrame = boolToInteger(
            fromElliot.marketContext.timeFrame
                == ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
        );
        fromEntity.isBuy = boolToInteger(fromElliot.isBuy);
        fromEntity.buySellLabel = normalizeText(fromElliot.buySellLabel);
        fromEntity.waveCount = fromElliot.waveList.Total();
        fromEntity.latestWaveIndex = fromLatestWave.index;
        fromEntity.isWaveConfirmed = boolToInteger(
            fromLatestWave.isConfirmed
        );
        fromEntity.isWaveMotive = boolToInteger(fromLatestWave.isMotive);
        fromEntity.isWaveUptrend = boolToInteger(fromLatestWave.isUptrend);
        fromEntity.waveTrendLabel = normalizeText(fromLatestWave.trendLabel);
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
        fromEntity.latestPointTime = fromLatestPoint.barTime;
        fromEntity.latestPointTimeText = formatDateTime(
            fromLatestPoint.barTime
        );
        fromEntity.latestPointJstTime = TimeJapanUtil::getJapanTime(
            fromLatestPoint.barTime
        );
        fromEntity.latestPointJstTimeText = formatDateTime(
            fromEntity.latestPointJstTime
        );
        fromEntity.latestPointRate = fromLatestPoint.rate;
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
        fromEntity.distanceToFe2000Pips = fiboInfo.DistanceToFE2000Pips;
        fromEntity.oscillatorCount = oscillator.oscillatorCount;
        fromEntity.isOscillatorBuy = boolToInteger(oscillator.isBuy);
        fromEntity.stochasticMainOrder = (int)oscillator.stochasticMainOrder;
        fromEntity.stochasticMainOrderText = normalizeText(
            oscillator.getStochasticMainOrderText()
        );
        fromEntity.stochasticMainDirectionText = normalizeText(
            oscillator.getStochasticMainOrderDirectionText()
        );
        fromEntity.stochasticShortCount = oscillator.stochasticShort.count;
        fromEntity.stochasticShortMain = oscillator.stochasticShort.main0;
        fromEntity.stochasticShortSignal = oscillator.stochasticShort.signal0;
        fromEntity.stochasticMiddleCount = oscillator.stochasticMiddle.count;
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
        fromEntity.createdAt = fromCreatedAt;
        fromEntity.createdAtText = formatDateTime(fromCreatedAt);

        return fromEntity.pointCount > 0;
    }

    /**
     * 構造化スカラーだけから安定した観測ハッシュを生成する。
     *
     * IDと作成時刻は保存再試行で変化し得るためハッシュ対象外とする。
     *
     * @param fromEntity 観測親Entity
     * @param fromTimeFrameEntities 時間足別分析一覧
     * @return 16進16桁のハッシュ
     */
    static string createSnapshotHash(
        ZigZagElliotObservationEntity &fromEntity,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
    ) {
        string sourceText = "H1_OBSERVATION_V1";
        appendText(sourceText, fromEntity.sourceMode);
        appendText(sourceText, fromEntity.sourceServer);
        appendText(sourceText, fromEntity.symbolName);
        appendInteger(sourceText, fromEntity.anchorTimeFrame);
        appendDateTime(sourceText, fromEntity.anchorBarTime);
        appendText(sourceText, fromEntity.capturePhase);
        appendText(sourceText, fromEntity.analysisVersion);
        appendText(sourceText, fromEntity.analysisInputHash);
        appendInteger(sourceText, ArraySize(fromTimeFrameEntities));

        for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
            appendTimeFrameHashValues(
                sourceText,
                fromTimeFrameEntities[i]
            );
        }

        return createTextHash(sourceText);
    }

    /**
     * 文字列から安定した16進16桁のハッシュを生成する。
     *
     * @param fromSourceText ハッシュ対象文字列
     * @return 16進16桁のハッシュ
     */
    static string createTextHash(const string fromSourceText) {
        uint hash1 = 2166136261;
        uint hash2 = 5381;
        int length = StringLen(fromSourceText);

        for (int i = 0; i < length; i++) {
            uint character = (uint)StringGetCharacter(fromSourceText, i);
            hash1 = (hash1 ^ character) * 16777619;
            hash2 = ((hash2 << 5) + hash2) ^ character;
        }

        return StringFormat("%08X%08X", hash1, hash2);
    }

    /**
     * 1時間足分の全構造化スカラーをハッシュ元へ追加する。
     *
     * @param fromSourceText ハッシュ元文字列
     * @param fromEntity 時間足別分析Entity
     */
    static void appendTimeFrameHashValues(
        string &fromSourceText,
        ZigZagElliotObservationTimeFrameEntity &fromEntity
    ) {
        appendInteger(fromSourceText, fromEntity.timeFrame);
        appendText(fromSourceText, fromEntity.timeFrameText);
        appendInteger(fromSourceText, fromEntity.timeFrameOrder);
        appendInteger(fromSourceText, fromEntity.isAnchorTimeFrame);
        appendInteger(fromSourceText, fromEntity.isBuy);
        appendText(fromSourceText, fromEntity.buySellLabel);
        appendInteger(fromSourceText, fromEntity.waveCount);
        appendInteger(fromSourceText, fromEntity.latestWaveIndex);
        appendInteger(fromSourceText, fromEntity.isWaveConfirmed);
        appendInteger(fromSourceText, fromEntity.isWaveMotive);
        appendInteger(fromSourceText, fromEntity.isWaveUptrend);
        appendText(fromSourceText, fromEntity.waveTrendLabel);
        appendText(fromSourceText, fromEntity.previousLastElliotLabel);
        appendInteger(fromSourceText, fromEntity.pointCount);
        appendInteger(fromSourceText, fromEntity.latestElliotIndex);
        appendText(fromSourceText, fromEntity.latestElliotLabel);
        appendInteger(fromSourceText, fromEntity.latestSubElliotIndex);
        appendText(fromSourceText, fromEntity.latestSubElliotLabel);
        appendDateTime(fromSourceText, fromEntity.latestPointTime);
        appendDouble(fromSourceText, fromEntity.latestPointRate);
        appendDouble(fromSourceText, fromEntity.previousOpen);
        appendDouble(fromSourceText, fromEntity.previousHigh);
        appendDouble(fromSourceText, fromEntity.previousLow);
        appendDouble(fromSourceText, fromEntity.previousClose);
        appendDouble(fromSourceText, fromEntity.currentOpen);
        appendDouble(fromSourceText, fromEntity.currentHigh);
        appendDouble(fromSourceText, fromEntity.currentLow);
        appendDouble(fromSourceText, fromEntity.currentClose);
        appendInteger(fromSourceText, fromEntity.isFiboExpansionAvailable);
        appendDouble(fromSourceText, fromEntity.fe618Price);
        appendDouble(fromSourceText, fromEntity.fe1000Price);
        appendDouble(fromSourceText, fromEntity.fe1272Price);
        appendDouble(fromSourceText, fromEntity.fe1618Price);
        appendDouble(fromSourceText, fromEntity.fe2000Price);
        appendDouble(fromSourceText, fromEntity.distanceToFe2000Pips);
        appendInteger(fromSourceText, fromEntity.oscillatorCount);
        appendInteger(fromSourceText, fromEntity.isOscillatorBuy);
        appendInteger(fromSourceText, fromEntity.stochasticMainOrder);
        appendText(fromSourceText, fromEntity.stochasticMainOrderText);
        appendText(fromSourceText, fromEntity.stochasticMainDirectionText);
        appendInteger(fromSourceText, fromEntity.stochasticShortCount);
        appendDouble(fromSourceText, fromEntity.stochasticShortMain);
        appendDouble(fromSourceText, fromEntity.stochasticShortSignal);
        appendInteger(fromSourceText, fromEntity.stochasticMiddleCount);
        appendDouble(fromSourceText, fromEntity.stochasticMiddleMain);
        appendDouble(fromSourceText, fromEntity.stochasticMiddleSignal);
        appendInteger(fromSourceText, fromEntity.stochasticLongCount);
        appendDouble(fromSourceText, fromEntity.stochasticLongMain);
        appendDouble(fromSourceText, fromEntity.stochasticLongSignal);
        appendInteger(fromSourceText, fromEntity.gmmaTrendCount);
        appendInteger(fromSourceText, fromEntity.gmmaCrossCount);
        appendDouble(fromSourceText, fromEntity.ema30);
        appendDouble(fromSourceText, fromEntity.ema60);
        appendDouble(fromSourceText, fromEntity.ema30Ema60DiffPips);
        appendDouble(fromSourceText, fromEntity.atr14Pips);
        appendDouble(fromSourceText, fromEntity.ema200Close1);
        appendDouble(fromSourceText, fromEntity.ema200Shift1);
        appendDouble(fromSourceText, fromEntity.ema200Compare);
        appendDouble(fromSourceText, fromEntity.ema200SlopePips);
        appendDouble(fromSourceText, fromEntity.ema200CloseDiffPips);
        appendInteger(fromSourceText, fromEntity.ema200ClosePosition);
        appendInteger(fromSourceText, fromEntity.ema200SlopeDirection);
        appendInteger(fromSourceText, fromEntity.ema200UpCount);
        appendInteger(fromSourceText, fromEntity.ema200DownCount);
        appendInteger(fromSourceText, fromEntity.ema200TrendCount);
        appendInteger(fromSourceText, fromEntity.isEma200Buy);
        appendInteger(fromSourceText, fromEntity.isEma200Sell);
    }

    /**
     * 文字列を長さ付きでハッシュ元へ追加する。
     *
     * @param fromSourceText ハッシュ元文字列
     * @param fromValue 追加する値
     */
    static void appendText(string &fromSourceText, const string fromValue) {
        string value = normalizeText(fromValue);
        fromSourceText += "|S" + IntegerToString(StringLen(value));
        fromSourceText += ":" + value;
    }

    /**
     * 整数値をハッシュ元へ追加する。
     *
     * @param fromSourceText ハッシュ元文字列
     * @param fromValue 追加する値
     */
    static void appendInteger(
        string &fromSourceText,
        const int fromValue
    ) {
        fromSourceText += "|I" + IntegerToString(fromValue);
    }

    /**
     * 日時値をハッシュ元へ追加する。
     *
     * @param fromSourceText ハッシュ元文字列
     * @param fromValue 追加する値
     */
    static void appendDateTime(
        string &fromSourceText,
        const datetime fromValue
    ) {
        fromSourceText += "|T" + StringFormat("%I64d", (long)fromValue);
    }

    /**
     * 小数値を固定精度でハッシュ元へ追加する。
     *
     * @param fromSourceText ハッシュ元文字列
     * @param fromValue 追加する値
     */
    static void appendDouble(
        string &fromSourceText,
        const double fromValue
    ) {
        fromSourceText += "|D" + DoubleToString(fromValue, 8);
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
};

#endif // MSTNG_EXPERT_ADVISOR_ZIGZAG_ELLIOT_OBSERVATION_BUILDER_MQH
