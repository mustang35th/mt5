//+------------------------------------------------------------------+
//|                 ZigZagElliotH1StudyOutcomeCalculator.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_CALCULATOR_MQH
#define MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_CALCULATOR_MQH

#include <Mstng\Analysis\ZigZagElliotH1StudyObservation.mqh>

/**
 * H1推移研究における1期間分の将来成績計算結果。
 */
struct ZigZagElliotH1StudyOutcomeCalculationResult {
    /** 将来成績を計算できた場合1。 */
    int isCalculated;

    /** 評価終了を確定したObservation ID。 */
    long endObsId;

    /** 評価終了サーバー時刻。 */
    datetime endTime;

    /** 評価期間終了時の価格。 */
    double exitPrice;

    /** Spread控除前の方向別損益pips。 */
    double grossProfitPips;

    /** エントリー時Spread控除後の方向別損益pips。 */
    double spreadAdjustedProfitPips;

    /** Spread控除前損益のエントリー時ATR換算値。 */
    double grossProfitAtr;

    /** Spread控除後損益のエントリー時ATR換算値。 */
    double spreadAdjustedProfitAtr;

    /** 最大有利変動pips。 */
    double mfePips;

    /** 最大不利変動pips。 */
    double maePips;

    /** 最大利益へ最初に到達するまでのH1本数。 */
    int maxProfitH1Bars;

    /** 実際に検証できたH1本数。 */
    int evaluatedH1Bars;

    /** READYまたは計算不能理由。 */
    string dataStatus;

    /** 将来成績計算上の補足。 */
    string note;

    /**
     * 全フィールドを未評価状態へ初期化する。
     */
    void reset() {
        this.isCalculated = 0;
        this.endObsId = 0;
        this.endTime = 0;
        this.exitPrice = 0.0;
        this.grossProfitPips = 0.0;
        this.spreadAdjustedProfitPips = 0.0;
        this.grossProfitAtr = 0.0;
        this.spreadAdjustedProfitAtr = 0.0;
        this.mfePips = 0.0;
        this.maePips = 0.0;
        this.maxProfitH1Bars = 0;
        this.evaluatedH1Bars = 0;
        this.dataStatus = "NOT_EVALUATED";
        this.note = "";
    }
};

/**
 * Observation DBのH1 OHLCだけで将来成績を計算するクラス。
 *
 * entryIndexの行を研究用エントリーH1とし、そのcurrentOpenを始値として
 * 使用する。評価対象H1の確定OHLCは、直後Observationに保存された
 * previousOpen、previousHigh、previousLowおよびpreviousCloseを使用する。
 */
class ZigZagElliotH1StudyOutcomeCalculator {
public:
    /**
     * W1、D1、H4、H1およびH4・H1 EMA200の完全一致方向を取得する。
     *
     * @param fromRow 判定対象Observation
     * @return BUY、SELLまたは不一致・欠損時の空文字
     */
    static string classifyFullAlignmentSide(
        const ZigZagElliotH1StudyObservationRow &fromRow
    ) {
        if (fromRow.isRequiredTimeFramesComplete != 1
                || fromRow.isW1Available != 1
                || fromRow.isD1Available != 1
                || fromRow.isH4Available != 1
                || fromRow.isH1Available != 1) {
            return "";
        }

        if (fromRow.w1IsBuy == 1
                && fromRow.d1IsBuy == 1
                && fromRow.h4IsBuy == 1
                && fromRow.h1IsBuy == 1
                && fromRow.h4IsEma200Buy == 1
                && fromRow.h4IsEma200Sell == 0
                && fromRow.h1IsEma200Buy == 1
                && fromRow.h1IsEma200Sell == 0) {
            return "BUY";
        }

        if (fromRow.w1IsBuy == 0
                && fromRow.d1IsBuy == 0
                && fromRow.h4IsBuy == 0
                && fromRow.h1IsBuy == 0
                && fromRow.h4IsEma200Buy == 0
                && fromRow.h4IsEma200Sell == 1
                && fromRow.h1IsEma200Buy == 0
                && fromRow.h1IsEma200Sell == 1) {
            return "SELL";
        }

        return "";
    }

    /**
     * 2つのサーバー時刻が連続する取引可能H1か判定する。
     *
     * 通常の1時間差に加えて、金曜23時から月曜0時、12月24日23時から
     * 12月26日0時および12月31日23時から1月2日0時を連続とする。
     * Viewerの連続H1判定と同一規則である。
     *
     * @param fromPreviousTime 前のH1開始サーバー時刻
     * @param fromCurrentTime 現在のH1開始サーバー時刻
     * @return 連続する場合true
     */
    static bool isConsecutiveMarketH1(
        const datetime fromPreviousTime,
        const datetime fromCurrentTime
    ) {
        if (fromPreviousTime <= 0 || fromCurrentTime <= 0) {
            return false;
        }

        long elapsedSeconds = (long)fromCurrentTime
            - (long)fromPreviousTime;

        if (elapsedSeconds == 3600) {
            return true;
        }

        if (elapsedSeconds <= 0) {
            return false;
        }

        MqlDateTime previousDateTime;
        MqlDateTime currentDateTime;

        if (!TimeToStruct(fromPreviousTime, previousDateTime)
                || !TimeToStruct(fromCurrentTime, currentDateTime)) {
            return false;
        }

        bool isWeekend = elapsedSeconds == 49 * 3600
            && previousDateTime.day_of_week == 5
            && previousDateTime.hour == 23
            && previousDateTime.min == 0
            && currentDateTime.day_of_week == 1
            && currentDateTime.hour == 0
            && currentDateTime.min == 0;

        if (isWeekend) {
            return true;
        }

        bool isChristmas = elapsedSeconds == 25 * 3600
            && previousDateTime.year == currentDateTime.year
            && previousDateTime.mon == 12
            && previousDateTime.day == 24
            && previousDateTime.hour == 23
            && previousDateTime.min == 0
            && currentDateTime.mon == 12
            && currentDateTime.day == 26
            && currentDateTime.hour == 0
            && currentDateTime.min == 0;

        if (isChristmas) {
            return true;
        }

        bool isNewYear = elapsedSeconds == 25 * 3600
            && currentDateTime.year == previousDateTime.year + 1
            && previousDateTime.mon == 12
            && previousDateTime.day == 31
            && previousDateTime.hour == 23
            && previousDateTime.min == 0
            && currentDateTime.mon == 1
            && currentDateTime.day == 2
            && currentDateTime.hour == 0
            && currentDateTime.min == 0;

        return isNewYear;
    }

    /**
     * エントリー後の指定H1本数について将来成績を計算する。
     *
     * entryIndexは候補行ではなく、次のH1始値を保持するエントリー行を
     * 指す。評価bar jの確定OHLCはentryIndex+j行のprevious OHLCであり、
     * 6H1ならentryIndex+6行が評価終了Observationとなる。
     *
     * @param fromRows 同一StreamのObservation時系列昇順配列
     * @param fromEntryIndex 研究用エントリーObservationの配列位置
     * @param fromSide BUYまたはSELL
     * @param fromHorizonH1Bars 6、12、24または48
     * @param fromResult 計算結果
     * @return READYまで計算できた場合true
     */
    static bool calculate(
        const ZigZagElliotH1StudyObservationRow &fromRows[],
        const int fromEntryIndex,
        const string fromSide,
        const int fromHorizonH1Bars,
        ZigZagElliotH1StudyOutcomeCalculationResult &fromResult
    ) {
        fromResult.reset();

        if (!isSupportedHorizon(fromHorizonH1Bars)) {
            return setFailure(
                fromResult,
                "INVALID_HORIZON",
                StringFormat("horizonH1Bars=%d", fromHorizonH1Bars)
            );
        }

        bool isBuy = fromSide == "BUY";

        if (!isBuy && fromSide != "SELL") {
            return setFailure(
                fromResult,
                "INVALID_SIDE",
                "side=" + fromSide
            );
        }

        int rowCount = ArraySize(fromRows);

        if (fromEntryIndex < 0 || fromEntryIndex >= rowCount) {
            return setFailure(
                fromResult,
                "INVALID_ENTRY_INDEX",
                StringFormat(
                    "entryIndex=%d;rowCount=%d",
                    fromEntryIndex,
                    rowCount
                )
            );
        }

        ZigZagElliotH1StudyObservationRow entryRow =
            fromRows[fromEntryIndex];
        string validationNote = "";
        string validationStatus = validateEntryRow(
            entryRow,
            validationNote
        );

        if (validationStatus != "") {
            return setFailure(
                fromResult,
                validationStatus,
                validationNote
            );
        }

        double maximumFavorablePrice = 0.0;
        double maximumAdversePrice = 0.0;
        int maximumProfitH1Bars = 0;

        for (int i = 1; i <= fromHorizonH1Bars; i++) {
            int rowIndex = fromEntryIndex + i;

            if (rowIndex >= rowCount) {
                return setFailure(
                    fromResult,
                    "FUTURE_INCOMPLETE",
                    StringFormat(
                        "h1Bar=%d;requiredRowIndex=%d;rowCount=%d",
                        i,
                        rowIndex,
                        rowCount
                    )
                );
            }

            ZigZagElliotH1StudyObservationRow previousRow =
                fromRows[rowIndex - 1];
            ZigZagElliotH1StudyObservationRow currentRow =
                fromRows[rowIndex];
            validationNote = "";
            validationStatus = validateOutcomeRow(
                previousRow,
                currentRow,
                entryRow.pipSize,
                validationNote
            );

            if (validationStatus != "") {
                return setFailure(
                    fromResult,
                    validationStatus,
                    StringFormat("h1Bar=%d;", i) + validationNote
                );
            }

            double favorablePrice = getFavorablePriceDifference(
                isBuy,
                entryRow.currentOpen,
                currentRow.previousHigh,
                currentRow.previousLow
            );
            double adversePrice = getAdversePriceDifference(
                isBuy,
                entryRow.currentOpen,
                currentRow.previousHigh,
                currentRow.previousLow
            );

            if (favorablePrice > maximumFavorablePrice) {
                maximumFavorablePrice = favorablePrice;
                maximumProfitH1Bars = i;
            }

            if (adversePrice > maximumAdversePrice) {
                maximumAdversePrice = adversePrice;
            }

            fromResult.evaluatedH1Bars = i;
        }

        int endIndex = fromEntryIndex + fromHorizonH1Bars;
        ZigZagElliotH1StudyObservationRow endRow = fromRows[endIndex];
        double grossProfitPrice = getDirectionalPriceDifference(
            isBuy,
            entryRow.currentOpen,
            endRow.previousClose
        );
        double grossProfitPips = grossProfitPrice / entryRow.pipSize;
        double spreadAdjustedProfitPips = grossProfitPips
            - entryRow.spreadPips;
        double grossProfitAtr = grossProfitPips / entryRow.atr14Pips;
        double spreadAdjustedProfitAtr = spreadAdjustedProfitPips
            / entryRow.atr14Pips;
        double mfePips = maximumFavorablePrice / entryRow.pipSize;
        double maePips = maximumAdversePrice / entryRow.pipSize;

        if (!areCalculatedValuesValid(
                grossProfitPips,
                spreadAdjustedProfitPips,
                grossProfitAtr,
                spreadAdjustedProfitAtr,
                mfePips,
                maePips
            )) {
            return setFailure(
                fromResult,
                "CALCULATION_INVALID",
                StringFormat(
                    "entryObservationId=%I64d;endObservationId=%I64d",
                    entryRow.observationId,
                    endRow.observationId
                )
            );
        }

        fromResult.isCalculated = 1;
        fromResult.endObsId = endRow.observationId;
        fromResult.endTime = endRow.anchorBarTime;
        fromResult.exitPrice = endRow.previousClose;
        fromResult.grossProfitPips = grossProfitPips;
        fromResult.spreadAdjustedProfitPips =
            spreadAdjustedProfitPips;
        fromResult.grossProfitAtr = grossProfitAtr;
        fromResult.spreadAdjustedProfitAtr =
            spreadAdjustedProfitAtr;
        fromResult.mfePips = mfePips;
        fromResult.maePips = maePips;
        fromResult.maxProfitH1Bars = maximumProfitH1Bars;
        fromResult.evaluatedH1Bars = fromHorizonH1Bars;
        fromResult.dataStatus = "READY";
        fromResult.note = StringFormat(
            "ENTRY_OBSERVATION_ID=%I64d;PIP_SIZE_SOURCE=%s;PRICE_MODEL=H1_BID_OHLC_V1;SPREAD_MODEL=ENTRY_SPREAD_ONCE_V1",
            entryRow.observationId,
            entryRow.pipSizeSource
        );

        return true;
    }

private:
    /**
     * 対応する評価期間か判定する。
     *
     * @param fromHorizonH1Bars 評価対象H1本数
     * @return 6、12、24または48の場合true
     */
    static bool isSupportedHorizon(const int fromHorizonH1Bars) {
        return fromHorizonH1Bars == 6
            || fromHorizonH1Bars == 12
            || fromHorizonH1Bars == 24
            || fromHorizonH1Bars == 48;
    }

    /**
     * エントリー行の価格単位と基準値を検証する。
     *
     * @param fromRow エントリーObservation
     * @param fromNote 異常詳細
     * @return 正常時は空文字、異常時は状態コード
     */
    static string validateEntryRow(
        const ZigZagElliotH1StudyObservationRow &fromRow,
        string &fromNote
    ) {
        fromNote = StringFormat(
            "entryObservationId=%I64d;entryTime=%s",
            fromRow.observationId,
            TimeToString(fromRow.anchorBarTime, TIME_DATE | TIME_SECONDS)
        );

        if (fromRow.observationId <= 0 || fromRow.anchorBarTime <= 0) {
            return "ENTRY_OBSERVATION_INVALID";
        }

        if (fromRow.isH1Available != 1) {
            return "ENTRY_H1_MISSING";
        }

        if (!isPositiveNumber(fromRow.currentOpen)) {
            return "ENTRY_PRICE_INVALID";
        }

        if (fromRow.isSpreadAvailable != 1) {
            return "ENTRY_SPREAD_MISSING";
        }

        if (!isNonNegativeNumber(fromRow.spreadPips)) {
            return "ENTRY_SPREAD_INVALID";
        }

        if (!isPositiveNumber(fromRow.pipSize)) {
            return "PIP_SIZE_INVALID";
        }

        if (fromRow.pipSizeSource == "") {
            return "PIP_SIZE_SOURCE_MISSING";
        }

        if (fromRow.isAtr14Available != 1) {
            return "ENTRY_ATR_MISSING";
        }

        if (!isPositiveNumber(fromRow.atr14Pips)) {
            return "ENTRY_ATR_INVALID";
        }

        return "";
    }

    /**
     * 1本分の確定H1 OHLCとObservation連続性を検証する。
     *
     * @param fromPreviousRow 評価対象H1開始時のObservation
     * @param fromCurrentRow 評価対象H1確定後のObservation
     * @param fromPipSize 1pip相当の価格幅
     * @param fromNote 異常詳細
     * @return 正常時は空文字、異常時は状態コード
     */
    static string validateOutcomeRow(
        const ZigZagElliotH1StudyObservationRow &fromPreviousRow,
        const ZigZagElliotH1StudyObservationRow &fromCurrentRow,
        const double fromPipSize,
        string &fromNote
    ) {
        fromNote = StringFormat(
            "previousObservationId=%I64d;currentObservationId=%I64d;previousTime=%s;currentTime=%s",
            fromPreviousRow.observationId,
            fromCurrentRow.observationId,
            TimeToString(
                fromPreviousRow.anchorBarTime,
                TIME_DATE | TIME_SECONDS
            ),
            TimeToString(
                fromCurrentRow.anchorBarTime,
                TIME_DATE | TIME_SECONDS
            )
        );

        if (fromPreviousRow.observationId <= 0
                || fromCurrentRow.observationId <= 0
                || fromPreviousRow.anchorBarTime <= 0
                || fromCurrentRow.anchorBarTime <= 0) {
            return "FUTURE_OBSERVATION_INVALID";
        }

        if (!isSameStream(fromPreviousRow, fromCurrentRow)) {
            return "FUTURE_STREAM_MISMATCH";
        }

        if (!isConsecutiveMarketH1(
                fromPreviousRow.anchorBarTime,
                fromCurrentRow.anchorBarTime
            )) {
            return "FUTURE_H1_GAP";
        }

        if (fromPreviousRow.isH1Available != 1
                || fromCurrentRow.isH1Available != 1) {
            return "FUTURE_H1_MISSING";
        }

        if (!isPositiveNumber(fromPreviousRow.currentOpen)) {
            return "FUTURE_CURRENT_OPEN_INVALID";
        }

        if (!isOhlcValid(
                fromCurrentRow.previousOpen,
                fromCurrentRow.previousHigh,
                fromCurrentRow.previousLow,
                fromCurrentRow.previousClose
            )) {
            return "FUTURE_OHLC_INVALID";
        }

        double openTolerance = fromPipSize * 0.000001;

        if (MathAbs(
                fromPreviousRow.currentOpen
                    - fromCurrentRow.previousOpen
            ) > openTolerance) {
            return "FUTURE_OPEN_MISMATCH";
        }

        return "";
    }

    /**
     * 2行が同じObservation Streamに属するか判定する。
     *
     * @param fromPreviousRow 前のObservation
     * @param fromCurrentRow 現在のObservation
     * @return 同じStreamの場合true
     */
    static bool isSameStream(
        const ZigZagElliotH1StudyObservationRow &fromPreviousRow,
        const ZigZagElliotH1StudyObservationRow &fromCurrentRow
    ) {
        return fromPreviousRow.runId == fromCurrentRow.runId
            && fromPreviousRow.sourceMode == fromCurrentRow.sourceMode
            && fromPreviousRow.sourceServer == fromCurrentRow.sourceServer
            && fromPreviousRow.symbolName == fromCurrentRow.symbolName
            && fromPreviousRow.anchorTimeFrame
                == fromCurrentRow.anchorTimeFrame
            && fromPreviousRow.capturePhase == fromCurrentRow.capturePhase
            && fromPreviousRow.analysisVersion
                == fromCurrentRow.analysisVersion
            && fromPreviousRow.analysisInputHash
                == fromCurrentRow.analysisInputHash;
    }

    /**
     * OHLCが正の有限値で価格関係も正常か判定する。
     *
     * @param fromOpen 始値
     * @param fromHigh 高値
     * @param fromLow 安値
     * @param fromClose 終値
     * @return 正常な場合true
     */
    static bool isOhlcValid(
        const double fromOpen,
        const double fromHigh,
        const double fromLow,
        const double fromClose
    ) {
        if (!isPositiveNumber(fromOpen)
                || !isPositiveNumber(fromHigh)
                || !isPositiveNumber(fromLow)
                || !isPositiveNumber(fromClose)) {
            return false;
        }

        return fromHigh >= fromLow
            && fromHigh >= fromOpen
            && fromHigh >= fromClose
            && fromLow <= fromOpen
            && fromLow <= fromClose;
    }

    /**
     * 正の有限値か判定する。
     *
     * @param fromValue 判定値
     * @return 正の有限値の場合true
     */
    static bool isPositiveNumber(const double fromValue) {
        return MathIsValidNumber(fromValue)
            && fromValue != EMPTY_VALUE
            && fromValue > 0.0;
    }

    /**
     * 0以上の有限値か判定する。
     *
     * @param fromValue 判定値
     * @return 0以上の有限値の場合true
     */
    static bool isNonNegativeNumber(const double fromValue) {
        return MathIsValidNumber(fromValue)
            && fromValue != EMPTY_VALUE
            && fromValue >= 0.0;
    }

    /**
     * 1バーの有利側価格差を取得する。
     *
     * @param fromIsBuy BUYの場合true
     * @param fromEntryPrice エントリー価格
     * @param fromHighPrice 確定H1高値
     * @param fromLowPrice 確定H1安値
     * @return 0以上の有利側価格差
     */
    static double getFavorablePriceDifference(
        const bool fromIsBuy,
        const double fromEntryPrice,
        const double fromHighPrice,
        const double fromLowPrice
    ) {
        double difference = fromEntryPrice - fromLowPrice;

        if (fromIsBuy) {
            difference = fromHighPrice - fromEntryPrice;
        }

        return MathMax(0.0, difference);
    }

    /**
     * 1バーの不利側価格差を取得する。
     *
     * @param fromIsBuy BUYの場合true
     * @param fromEntryPrice エントリー価格
     * @param fromHighPrice 確定H1高値
     * @param fromLowPrice 確定H1安値
     * @return 0以上の不利側価格差
     */
    static double getAdversePriceDifference(
        const bool fromIsBuy,
        const double fromEntryPrice,
        const double fromHighPrice,
        const double fromLowPrice
    ) {
        double difference = fromHighPrice - fromEntryPrice;

        if (fromIsBuy) {
            difference = fromEntryPrice - fromLowPrice;
        }

        return MathMax(0.0, difference);
    }

    /**
     * 売買方向に応じた決済価格差を取得する。
     *
     * @param fromIsBuy BUYの場合true
     * @param fromEntryPrice エントリー価格
     * @param fromExitPrice 決済価格
     * @return 方向別価格差
     */
    static double getDirectionalPriceDifference(
        const bool fromIsBuy,
        const double fromEntryPrice,
        const double fromExitPrice
    ) {
        double difference = fromEntryPrice - fromExitPrice;

        if (fromIsBuy) {
            difference = fromExitPrice - fromEntryPrice;
        }

        return difference;
    }

    /**
     * 算出した全指標が有限値か判定する。
     *
     * @param fromGrossProfitPips Spread控除前損益pips
     * @param fromSpreadAdjustedProfitPips Spread控除後損益pips
     * @param fromGrossProfitAtr Spread控除前ATR換算損益
     * @param fromSpreadAdjustedProfitAtr Spread控除後ATR換算損益
     * @param fromMfePips 最大有利変動pips
     * @param fromMaePips 最大不利変動pips
     * @return 全指標が有限値の場合true
     */
    static bool areCalculatedValuesValid(
        const double fromGrossProfitPips,
        const double fromSpreadAdjustedProfitPips,
        const double fromGrossProfitAtr,
        const double fromSpreadAdjustedProfitAtr,
        const double fromMfePips,
        const double fromMaePips
    ) {
        return MathIsValidNumber(fromGrossProfitPips)
            && MathIsValidNumber(fromSpreadAdjustedProfitPips)
            && MathIsValidNumber(fromGrossProfitAtr)
            && MathIsValidNumber(fromSpreadAdjustedProfitAtr)
            && MathIsValidNumber(fromMfePips)
            && MathIsValidNumber(fromMaePips)
            && fromGrossProfitPips != EMPTY_VALUE
            && fromSpreadAdjustedProfitPips != EMPTY_VALUE
            && fromGrossProfitAtr != EMPTY_VALUE
            && fromSpreadAdjustedProfitAtr != EMPTY_VALUE
            && fromMfePips != EMPTY_VALUE
            && fromMaePips != EMPTY_VALUE;
    }

    /**
     * 計算不能結果を設定する。
     *
     * @param fromResult 設定先
     * @param fromDataStatus 計算不能理由
     * @param fromNote 補足
     * @return 常にfalse
     */
    static bool setFailure(
        ZigZagElliotH1StudyOutcomeCalculationResult &fromResult,
        const string fromDataStatus,
        const string fromNote
    ) {
        fromResult.isCalculated = 0;
        fromResult.dataStatus = fromDataStatus;
        fromResult.note = fromNote;

        return false;
    }
};

#endif // MSTNG_ANALYSIS_ZIGZAG_ELLIOT_H1_STUDY_OUTCOME_CALCULATOR_MQH
