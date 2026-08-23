//+------------------------------------------------------------------+
//|                ZigZagElliotEntryHistoryValidator.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_HISTORY_VALIDATOR_MQH
#define MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_HISTORY_VALIDATOR_MQH

/**
 * H1とM1の履歴整合性検証結果。
 */
struct ZigZagElliotEntryHistoryValidationResult {
    /** 検証状態。 */
    string dataStatus;

    /** 不整合箇所の詳細。 */
    string calculationNote;

    /**
     * 検証前の状態へ初期化する。
     */
    void reset() {
        this.dataStatus = "NOT_VALIDATED";
        this.calculationNote = "";
    }
};

/**
 * 実在M1をH1単位で集約し、取得履歴の完全性を検証する。
 *
 * 無ティックの分にはM1バーが生成されないため、1時間60本という
 * 固定本数は要求しない。各H1のM1集計OHLCとtick volumeがH1に
 * 一致することを完全性の条件とする。
 */
class ZigZagElliotEntryHistoryValidator {
public:
    /**
     * 評価対象H1とM1履歴の整合性を検証する。
     *
     * @param fromH1Rates 時系列昇順のH1履歴。
     * @param fromHorizonH1Bars 評価対象H1本数。
     * @param fromM1Rates 時系列昇順のM1履歴。
     * @param fromPoint 対象シンボルの1point価格幅。
     * @param fromResult 検証結果。
     * @return 履歴が完全な場合true。
     */
    static bool validate(
        const MqlRates &fromH1Rates[],
        const int fromHorizonH1Bars,
        const MqlRates &fromM1Rates[],
        const double fromPoint,
        ZigZagElliotEntryHistoryValidationResult &fromResult
    ) {
        fromResult.reset();

        if (fromHorizonH1Bars <= 0
                || !MathIsValidNumber(fromPoint)
                || fromPoint <= 0.0) {
            return setFailure(
                fromResult,
                "INVALID_HISTORY_INPUT",
                "horizonH1Bars or point is invalid"
            );
        }

        int h1RateCount = ArraySize(fromH1Rates);
        int m1RateCount = ArraySize(fromM1Rates);

        if (h1RateCount < fromHorizonH1Bars) {
            return setFailure(
                fromResult,
                "HISTORY_PARTIAL",
                StringFormat(
                    "reason=H1_COUNT expected=%d actual=%d",
                    fromHorizonH1Bars,
                    h1RateCount
                )
            );
        }

        if (m1RateCount <= 0) {
            return setFailure(
                fromResult,
                "HISTORY_PARTIAL",
                "reason=M1_EMPTY"
            );
        }

        int h1Seconds = PeriodSeconds(PERIOD_H1);
        int m1Seconds = PeriodSeconds(PERIOD_M1);

        if (h1Seconds <= 0 || m1Seconds <= 0) {
            return setFailure(
                fromResult,
                "INVALID_HISTORY_INPUT",
                "PeriodSeconds failed"
            );
        }

        double priceTolerance = fromPoint * 0.5;
        int m1Index = 0;
        datetime previousH1Time = 0;
        datetime previousM1Time = 0;

        for (int i = 0; i < fromHorizonH1Bars; i++) {
            MqlRates h1Rate = fromH1Rates[i];

            if (!isRateValid(h1Rate)) {
                return setFailure(
                    fromResult,
                    "INVALID_H1_RATE",
                    StringFormat(
                        "h1=%s",
                        TimeToString(h1Rate.time, TIME_DATE | TIME_MINUTES)
                    )
                );
            }

            if (previousH1Time > 0
                    && h1Rate.time < previousH1Time + h1Seconds) {
                return setFailure(
                    fromResult,
                    "INVALID_H1_TIME_ORDER",
                    StringFormat(
                        "previous=%s current=%s",
                        TimeToString(
                            previousH1Time,
                            TIME_DATE | TIME_MINUTES
                        ),
                        TimeToString(
                            h1Rate.time,
                            TIME_DATE | TIME_MINUTES
                        )
                    )
                );
            }

            datetime h1EndTime = h1Rate.time + h1Seconds;

            if (m1Index < m1RateCount
                    && fromM1Rates[m1Index].time < h1Rate.time) {
                return setFailure(
                    fromResult,
                    "HISTORY_PARTIAL",
                    StringFormat(
                        "reason=M1_OUTSIDE_H1 m1=%s h1=%s",
                        TimeToString(
                            fromM1Rates[m1Index].time,
                            TIME_DATE | TIME_MINUTES
                        ),
                        TimeToString(
                            h1Rate.time,
                            TIME_DATE | TIME_MINUTES
                        )
                    )
                );
            }

            bool hasM1Rate = false;
            double aggregateOpen = 0.0;
            double aggregateHigh = 0.0;
            double aggregateLow = 0.0;
            double aggregateClose = 0.0;
            long aggregateTickVolume = 0;

            while (m1Index < m1RateCount
                    && fromM1Rates[m1Index].time < h1EndTime) {
                MqlRates m1Rate = fromM1Rates[m1Index];

                if (m1Rate.time < h1Rate.time
                        || ((long)m1Rate.time % m1Seconds) != 0
                        || (previousM1Time > 0
                            && m1Rate.time <= previousM1Time)
                        || !isRateValid(m1Rate)) {
                    return setFailure(
                        fromResult,
                        "INVALID_M1_RATE",
                        StringFormat(
                            "m1=%s h1=%s",
                            TimeToString(
                                m1Rate.time,
                                TIME_DATE | TIME_MINUTES
                            ),
                            TimeToString(
                                h1Rate.time,
                                TIME_DATE | TIME_MINUTES
                            )
                        )
                    );
                }

                if (!hasM1Rate) {
                    aggregateOpen = m1Rate.open;
                    aggregateHigh = m1Rate.high;
                    aggregateLow = m1Rate.low;
                    hasM1Rate = true;
                } else {
                    aggregateHigh = MathMax(
                        aggregateHigh,
                        m1Rate.high
                    );
                    aggregateLow = MathMin(
                        aggregateLow,
                        m1Rate.low
                    );
                }

                aggregateClose = m1Rate.close;
                aggregateTickVolume += m1Rate.tick_volume;
                previousM1Time = m1Rate.time;
                m1Index++;
            }

            if (!hasM1Rate) {
                return setFailure(
                    fromResult,
                    "HISTORY_PARTIAL",
                    StringFormat(
                        "reason=M1_H1_EMPTY h1=%s",
                        TimeToString(
                            h1Rate.time,
                            TIME_DATE | TIME_MINUTES
                        )
                    )
                );
            }

            string mismatchField = getOhlcMismatchField(
                aggregateOpen,
                aggregateHigh,
                aggregateLow,
                aggregateClose,
                h1Rate,
                priceTolerance
            );

            if (mismatchField != "") {
                return setFailure(
                    fromResult,
                    "HISTORY_PARTIAL",
                    StringFormat(
                        "reason=M1_H1_OHLC_MISMATCH field=%s h1=%s m1=%.10f/%.10f/%.10f/%.10f h1Rate=%.10f/%.10f/%.10f/%.10f",
                        mismatchField,
                        TimeToString(
                            h1Rate.time,
                            TIME_DATE | TIME_MINUTES
                        ),
                        aggregateOpen,
                        aggregateHigh,
                        aggregateLow,
                        aggregateClose,
                        h1Rate.open,
                        h1Rate.high,
                        h1Rate.low,
                        h1Rate.close
                    )
                );
            }

            if (aggregateTickVolume != h1Rate.tick_volume) {
                return setFailure(
                    fromResult,
                    "HISTORY_PARTIAL",
                    StringFormat(
                        "reason=M1_H1_VOLUME_MISMATCH h1=%s m1Volume=%I64d h1Volume=%I64d",
                        TimeToString(
                            h1Rate.time,
                            TIME_DATE | TIME_MINUTES
                        ),
                        aggregateTickVolume,
                        h1Rate.tick_volume
                    )
                );
            }

            previousH1Time = h1Rate.time;
        }

        if (m1Index != m1RateCount) {
            return setFailure(
                fromResult,
                "HISTORY_PARTIAL",
                StringFormat(
                    "reason=M1_OUTSIDE_H1 m1=%s remaining=%d",
                    TimeToString(
                        fromM1Rates[m1Index].time,
                        TIME_DATE | TIME_MINUTES
                    ),
                    m1RateCount - m1Index
                )
            );
        }

        fromResult.dataStatus = "READY";
        fromResult.calculationNote = "";

        return true;
    }

private:
    /**
     * OHLCとtick volumeが有効なバーか確認する。
     *
     * @param fromRate 確認対象。
     * @return 有効な場合true。
     */
    static bool isRateValid(const MqlRates &fromRate) {
        return fromRate.time > 0
            && MathIsValidNumber(fromRate.open)
            && MathIsValidNumber(fromRate.high)
            && MathIsValidNumber(fromRate.low)
            && MathIsValidNumber(fromRate.close)
            && fromRate.open > 0.0
            && fromRate.high >= fromRate.open
            && fromRate.high >= fromRate.close
            && fromRate.low <= fromRate.open
            && fromRate.low <= fromRate.close
            && fromRate.low > 0.0
            && fromRate.tick_volume > 0;
    }

    /**
     * M1集計OHLCとH1 OHLCの不一致項目を取得する。
     *
     * @param fromOpen M1集計始値。
     * @param fromHigh M1集計高値。
     * @param fromLow M1集計安値。
     * @param fromClose M1集計終値。
     * @param fromH1Rate H1バー。
     * @param fromTolerance 価格許容差。
     * @return 不一致項目。一致時は空文字。
     */
    static string getOhlcMismatchField(
        const double fromOpen,
        const double fromHigh,
        const double fromLow,
        const double fromClose,
        const MqlRates &fromH1Rate,
        const double fromTolerance
    ) {
        if (MathAbs(fromOpen - fromH1Rate.open) > fromTolerance) {
            return "OPEN";
        }

        if (MathAbs(fromHigh - fromH1Rate.high) > fromTolerance) {
            return "HIGH";
        }

        if (MathAbs(fromLow - fromH1Rate.low) > fromTolerance) {
            return "LOW";
        }

        if (MathAbs(fromClose - fromH1Rate.close) > fromTolerance) {
            return "CLOSE";
        }

        return "";
    }

    /**
     * 失敗結果を設定する。
     *
     * @param fromResult 設定先。
     * @param fromDataStatus データ状態。
     * @param fromCalculationNote 詳細。
     * @return 常にfalse。
     */
    static bool setFailure(
        ZigZagElliotEntryHistoryValidationResult &fromResult,
        const string fromDataStatus,
        const string fromCalculationNote
    ) {
        fromResult.dataStatus = fromDataStatus;
        fromResult.calculationNote = fromCalculationNote;

        return false;
    }
};

#endif // MSTNG_ANALYSIS_ZIGZAG_ELLIOT_ENTRY_HISTORY_VALIDATOR_MQH
