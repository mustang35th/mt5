//+------------------------------------------------------------------+
//|                  ZigZagElliotEntryOutcomeCalculator.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_OUTCOME_CALCULATOR_MQH
#define MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_OUTCOME_CALCULATOR_MQH

/**
 * ZigZagElliotエントリー候補の初期SLまたは期間終了までの評価結果。
 */
struct ZigZagElliotEntryOutcomeResult {
    /** データ評価状態。READYまたは入力エラーコード。 */
    string dataStatus;

    /** 決済理由。INITIAL_SL、HORIZONまたはNOT_EVALUATED。 */
    string exitReason;

    /** 決済時刻。SLの場合は到達したM1バー開始時刻。 */
    datetime exitTime;

    /** 決済価格。 */
    double exitPrice;

    /** エントリー価格から初期SLまでの価格差。 */
    double riskPrice;

    /** エントリー価格から初期SLまでの距離pips。 */
    double riskPips;

    /** 最大有利変動pips。 */
    double mfePips;

    /** 最大有利変動R。 */
    double mfeR;

    /** 最大不利変動pips。 */
    double maePips;

    /** 最大不利変動R。 */
    double maeR;

    /** 決済損益pips。 */
    double profitPips;

    /** 決済損益R。 */
    double profitR;

    /** エントリー後に評価したM1バー数。 */
    int barsHeldM1;

    /** 評価したM1バーのうちspreadが0だった本数。 */
    int zeroSpreadBarCount;

    /** SL到達バー内の価格順序が不明な場合true。 */
    bool exitBarOrderUnknown;

    /**
     * 全項目を未評価状態へ初期化する。
     */
    void reset() {
        this.dataStatus = "NOT_EVALUATED";
        this.exitReason = "NOT_EVALUATED";
        this.exitTime = 0;
        this.exitPrice = 0.0;
        this.riskPrice = 0.0;
        this.riskPips = 0.0;
        this.mfePips = 0.0;
        this.mfeR = 0.0;
        this.maePips = 0.0;
        this.maeR = 0.0;
        this.profitPips = 0.0;
        this.profitR = 0.0;
        this.barsHeldM1 = 0;
        this.zeroSpreadBarCount = 0;
        this.exitBarOrderUnknown = false;
    }
};

/**
 * 時系列昇順のM1 OHLCからエントリー後の値動き結果を計算する。
 *
 * BUYはBid OHLCを使用する。SELLはMqlRatesのspreadをpoint換算して
 * Bid OHLCへ加算したAsk OHLCを使用する。初期SLだけを評価し、SL到達
 * バーでは有利側の極値をMFEへ含めない。
 */
class ZigZagElliotEntryOutcomeCalculator {
public:
    /**
     * 初期SLまたは指定期間終了までの結果を計算する。
     *
     * fromRatesには、fromEntryTime以降かつfromHorizonEndより前に開始した
     * 完成済みM1バーを時系列昇順で渡す。SLへ到達しない場合は配列末尾の
     * closeをfromHorizonEnd時点の決済価格として使用する。
     *
     * @param fromSide BUYまたはSELL。
     * @param fromEntryPrice エントリー約定価格。BUYはAsk、SELLはBid。
     * @param fromStopLoss 初期SL価格。
     * @param fromPipSize 1pip相当の価格幅。
     * @param fromPoint 1point相当の価格幅。
     * @param fromEntryTime エントリー時刻。
     * @param fromHorizonEnd 評価終了時刻。
     * @param fromRates 完成済みM1 OHLC一覧。
     * @param fromResult 計算結果。
     * @return READYまで計算できた場合true。
     */
    static bool calculate(
        const string fromSide,
        const double fromEntryPrice,
        const double fromStopLoss,
        const double fromPipSize,
        const double fromPoint,
        const datetime fromEntryTime,
        const datetime fromHorizonEnd,
        const MqlRates &fromRates[],
        ZigZagElliotEntryOutcomeResult &fromResult
    ) {
        fromResult.reset();
        bool isBuy = false;
        string validationStatus = validateInput(
            fromSide,
            fromEntryPrice,
            fromStopLoss,
            fromPipSize,
            fromPoint,
            fromEntryTime,
            fromHorizonEnd,
            fromRates,
            isBuy
        );

        if (validationStatus != "") {
            fromResult.dataStatus = validationStatus;

            return false;
        }

        fromResult.riskPrice = MathAbs(
            fromEntryPrice - fromStopLoss
        );
        fromResult.riskPips = priceToPips(
            fromResult.riskPrice,
            fromPipSize
        );
        double maximumFavorablePrice = 0.0;
        double maximumAdversePrice = 0.0;
        int rateCount = ArraySize(fromRates);

        for (int i = 0; i < rateCount; i++) {
            double spreadPrice = (double)fromRates[i].spread * fromPoint;
            double openPrice = fromRates[i].open;
            double highPrice = fromRates[i].high;
            double lowPrice = fromRates[i].low;
            double closePrice = fromRates[i].close;

            if (!isBuy) {
                openPrice += spreadPrice;
                highPrice += spreadPrice;
                lowPrice += spreadPrice;
                closePrice += spreadPrice;
            }

            fromResult.barsHeldM1++;

            if (!isBuy && fromRates[i].spread == 0) {
                fromResult.zeroSpreadBarCount++;
            }

            bool isStoppedAtOpen = isStopLossAtOpen(
                isBuy,
                openPrice,
                fromStopLoss
            );

            if (isStoppedAtOpen) {
                double adversePrice = getAdversePriceDifference(
                    isBuy,
                    fromEntryPrice,
                    openPrice
                );
                maximumAdversePrice = MathMax(
                    maximumAdversePrice,
                    adversePrice
                );
                setExitResult(
                    isBuy,
                    fromEntryPrice,
                    openPrice,
                    fromRates[i].time,
                    "INITIAL_SL",
                    false,
                    fromPipSize,
                    maximumFavorablePrice,
                    maximumAdversePrice,
                    fromResult
                );

                return true;
            }

            bool isStoppedInBar = isStopLossInBar(
                isBuy,
                highPrice,
                lowPrice,
                fromStopLoss
            );

            if (isStoppedInBar) {
                double adversePrice = getAdversePriceDifference(
                    isBuy,
                    fromEntryPrice,
                    fromStopLoss
                );
                maximumAdversePrice = MathMax(
                    maximumAdversePrice,
                    adversePrice
                );
                setExitResult(
                    isBuy,
                    fromEntryPrice,
                    fromStopLoss,
                    fromRates[i].time,
                    "INITIAL_SL",
                    true,
                    fromPipSize,
                    maximumFavorablePrice,
                    maximumAdversePrice,
                    fromResult
                );

                return true;
            }

            double favorablePrice = getFavorablePriceDifference(
                isBuy,
                fromEntryPrice,
                highPrice,
                lowPrice
            );
            double adversePrice = getAdversePriceDifference(
                isBuy,
                fromEntryPrice,
                highPrice,
                lowPrice
            );
            maximumFavorablePrice = MathMax(
                maximumFavorablePrice,
                favorablePrice
            );
            maximumAdversePrice = MathMax(
                maximumAdversePrice,
                adversePrice
            );

            if (i == rateCount - 1) {
                setExitResult(
                    isBuy,
                    fromEntryPrice,
                    closePrice,
                    fromHorizonEnd,
                    "HORIZON",
                    false,
                    fromPipSize,
                    maximumFavorablePrice,
                    maximumAdversePrice,
                    fromResult
                );

                return true;
            }
        }

        fromResult.dataStatus = "INTERNAL_ERROR";

        return false;
    }

private:
    /**
     * 入力と全M1バーを検証する。
     *
     * @param fromSide BUYまたはSELL。
     * @param fromEntryPrice エントリー価格。
     * @param fromStopLoss 初期SL。
     * @param fromPipSize 1pip価格幅。
     * @param fromPoint 1point価格幅。
     * @param fromEntryTime エントリー時刻。
     * @param fromHorizonEnd 評価終了時刻。
     * @param fromRates M1 OHLC一覧。
     * @param fromIsBuy BUYの場合trueを設定する。
     * @return 正常な場合は空文字、異常な場合は状態コード。
     */
    static string validateInput(
        const string fromSide,
        const double fromEntryPrice,
        const double fromStopLoss,
        const double fromPipSize,
        const double fromPoint,
        const datetime fromEntryTime,
        const datetime fromHorizonEnd,
        const MqlRates &fromRates[],
        bool &fromIsBuy
    ) {
        fromIsBuy = false;

        if (fromSide == "BUY") {
            fromIsBuy = true;
        } else if (fromSide != "SELL") {
            return "INVALID_SIDE";
        }

        if (!isPositiveNumber(fromEntryPrice)) {
            return "INVALID_ENTRY_PRICE";
        }

        if (!isPositiveNumber(fromStopLoss)) {
            return "INVALID_STOP_LOSS";
        }

        if (fromIsBuy && fromStopLoss >= fromEntryPrice) {
            return "INVALID_STOP_LOSS_SIDE";
        }

        if (!fromIsBuy && fromStopLoss <= fromEntryPrice) {
            return "INVALID_STOP_LOSS_SIDE";
        }

        if (!isPositiveNumber(fromPipSize)) {
            return "INVALID_PIP_SIZE";
        }

        if (!isPositiveNumber(fromPoint)) {
            return "INVALID_POINT";
        }

        if (fromEntryTime <= 0
                || fromHorizonEnd <= fromEntryTime) {
            return "INVALID_TIME_RANGE";
        }

        int rateCount = ArraySize(fromRates);

        if (rateCount <= 0) {
            return "RATES_UNAVAILABLE";
        }

        datetime previousRateTime = 0;

        for (int i = 0; i < rateCount; i++) {
            string rateStatus = validateRate(
                fromRates[i],
                fromEntryTime,
                fromHorizonEnd,
                previousRateTime
            );

            if (rateStatus != "") {
                return rateStatus;
            }

            previousRateTime = fromRates[i].time;
        }

        return "";
    }

    /**
     * 1本のM1 OHLCと時刻を検証する。
     *
     * @param fromRate 検証対象バー。
     * @param fromEntryTime エントリー時刻。
     * @param fromHorizonEnd 評価終了時刻。
     * @param fromPreviousRateTime 直前バー開始時刻。
     * @return 正常な場合は空文字、異常な場合は状態コード。
     */
    static string validateRate(
        const MqlRates &fromRate,
        const datetime fromEntryTime,
        const datetime fromHorizonEnd,
        const datetime fromPreviousRateTime
    ) {
        if (fromRate.time <= 0
                || fromRate.time < fromEntryTime
                || fromRate.time >= fromHorizonEnd) {
            return "INVALID_RATE_TIME_RANGE";
        }

        if (fromPreviousRateTime > 0
                && fromRate.time <= fromPreviousRateTime) {
            return "INVALID_RATE_TIME_ORDER";
        }

        if (!isPositiveNumber(fromRate.open)
                || !isPositiveNumber(fromRate.high)
                || !isPositiveNumber(fromRate.low)
                || !isPositiveNumber(fromRate.close)) {
            return "INVALID_RATE_OHLC";
        }

        if (fromRate.high < fromRate.low
                || fromRate.open > fromRate.high
                || fromRate.open < fromRate.low
                || fromRate.close > fromRate.high
                || fromRate.close < fromRate.low) {
            return "INVALID_RATE_OHLC";
        }

        if (fromRate.spread < 0) {
            return "INVALID_RATE_SPREAD";
        }

        return "";
    }

    /**
     * 有効な正数か判定する。
     *
     * @param fromValue 判定値。
     * @return 有効な正数の場合true。
     */
    static bool isPositiveNumber(const double fromValue) {
        return MathIsValidNumber(fromValue) && fromValue > 0.0;
    }

    /**
     * 始値で初期SLを越えているか判定する。
     *
     * @param fromIsBuy BUYの場合true。
     * @param fromOpenPrice 売買側の始値。
     * @param fromStopLoss 初期SL。
     * @return 始値で決済する場合true。
     */
    static bool isStopLossAtOpen(
        const bool fromIsBuy,
        const double fromOpenPrice,
        const double fromStopLoss
    ) {
        if (fromIsBuy) {
            return fromOpenPrice <= fromStopLoss;
        }

        return fromOpenPrice >= fromStopLoss;
    }

    /**
     * バー内で初期SLへ到達したか判定する。
     *
     * @param fromIsBuy BUYの場合true。
     * @param fromHighPrice 売買側の高値。
     * @param fromLowPrice 売買側の安値。
     * @param fromStopLoss 初期SL。
     * @return バー内でSLへ到達した場合true。
     */
    static bool isStopLossInBar(
        const bool fromIsBuy,
        const double fromHighPrice,
        const double fromLowPrice,
        const double fromStopLoss
    ) {
        if (fromIsBuy) {
            return fromLowPrice <= fromStopLoss;
        }

        return fromHighPrice >= fromStopLoss;
    }

    /**
     * 1バーの有利側価格差を取得する。
     *
     * @param fromIsBuy BUYの場合true。
     * @param fromEntryPrice エントリー価格。
     * @param fromHighPrice 売買側の高値。
     * @param fromLowPrice 売買側の安値。
     * @return 0以上の有利側価格差。
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
     * @param fromIsBuy BUYの場合true。
     * @param fromEntryPrice エントリー価格。
     * @param fromHighPrice 売買側の高値。
     * @param fromLowPrice 売買側の安値。
     * @return 0以上の不利側価格差。
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
     * 1価格の不利側価格差を取得する。
     *
     * @param fromIsBuy BUYの場合true。
     * @param fromEntryPrice エントリー価格。
     * @param fromPrice 評価価格。
     * @return 0以上の不利側価格差。
     */
    static double getAdversePriceDifference(
        const bool fromIsBuy,
        const double fromEntryPrice,
        const double fromPrice
    ) {
        double difference = fromPrice - fromEntryPrice;

        if (fromIsBuy) {
            difference = fromEntryPrice - fromPrice;
        }

        return MathMax(0.0, difference);
    }

    /**
     * 決済結果とMFE、MAE、Rを設定する。
     *
     * @param fromIsBuy BUYの場合true。
     * @param fromEntryPrice エントリー価格。
     * @param fromExitPrice 決済価格。
     * @param fromExitTime 決済時刻。
     * @param fromExitReason 決済理由。
     * @param fromExitBarOrderUnknown 決済バー内順序が不明な場合true。
     * @param fromPipSize 1pip価格幅。
     * @param fromMaximumFavorablePrice 最大有利価格差。
     * @param fromMaximumAdversePrice 最大不利価格差。
     * @param fromResult 設定先。
     */
    static void setExitResult(
        const bool fromIsBuy,
        const double fromEntryPrice,
        const double fromExitPrice,
        const datetime fromExitTime,
        const string fromExitReason,
        const bool fromExitBarOrderUnknown,
        const double fromPipSize,
        const double fromMaximumFavorablePrice,
        const double fromMaximumAdversePrice,
        ZigZagElliotEntryOutcomeResult &fromResult
    ) {
        double profitPrice = fromEntryPrice - fromExitPrice;

        if (fromIsBuy) {
            profitPrice = fromExitPrice - fromEntryPrice;
        }

        fromResult.dataStatus = "READY";
        fromResult.exitReason = fromExitReason;
        fromResult.exitTime = fromExitTime;
        fromResult.exitPrice = fromExitPrice;
        fromResult.mfePips = priceToPips(
            fromMaximumFavorablePrice,
            fromPipSize
        );
        fromResult.maePips = priceToPips(
            fromMaximumAdversePrice,
            fromPipSize
        );
        fromResult.profitPips = priceToPips(
            profitPrice,
            fromPipSize
        );
        fromResult.mfeR = fromResult.mfePips / fromResult.riskPips;
        fromResult.maeR = fromResult.maePips / fromResult.riskPips;
        fromResult.profitR = fromResult.profitPips / fromResult.riskPips;
        fromResult.exitBarOrderUnknown = fromExitBarOrderUnknown;
    }

    /**
     * 価格差をpipsへ変換する。
     *
     * @param fromPriceDifference 価格差。
     * @param fromPipSize 1pip価格幅。
     * @return pips。
     */
    static double priceToPips(
        const double fromPriceDifference,
        const double fromPipSize
    ) {
        return fromPriceDifference / fromPipSize;
    }
};

#endif // MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_OUTCOME_CALCULATOR_MQH
