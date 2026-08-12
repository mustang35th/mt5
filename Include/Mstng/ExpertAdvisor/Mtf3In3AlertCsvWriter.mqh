//+------------------------------------------------------------------+
//|                                        Mtf3In3AlertCsvWriter.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_CSV_WRITER_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_CSV_WRITER_MQH

#include <Mstng\Common\File\CsvFileWriter.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1ElliotStructureDecision.mqh>

#define MTF3_IN3_ALERT_CSV_FIELD_COUNT 64

/**
 * MTF_3in3のアラート候補を検証用CSVへ追記する。
 */
class Mtf3In3AlertCsvWriter {
public:
    /**
     * isAlertがtrueの候補を1行として保存する。
     *
     * 最適化中は複数エージェントの同時書き込みを避けるため出力しない。
     *
     * @param fromElliotAll 判定に使用した全時間足のElliott分析結果。
     * @param fromResult MTF_3in3のアラート判定結果。
     * @param fromSource 呼び出し元識別子。
     * @param fromMagicNumber EAのマジックナンバー。インジケーターは0。
     * @return 出力成功、対象外または最適化による省略の場合true。
     */
    static bool write(
        ElliotAll *fromElliotAll,
        Mtf3In3AlertResult &fromResult,
        const string fromSource,
        const ulong fromMagicNumber = 0
    ) {
        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            return true;
        }

        if (!fromResult.isAlert) {
            return true;
        }

        if (fromElliotAll == NULL
                || !fromElliotAll.isAnalysisSucceeded
                || fromElliotAll.elliotCurrent == NULL) {
            Print("Mtf3In3AlertCsvWriter.write invalid Elliott analysis");

            return false;
        }

        string headerValues[];

        if (!setHeaderValues(headerValues)) {
            return false;
        }

        string currentValidationRunId = getValidationRunId();
        string fileName = createFileName(
            fromElliotAll.tradeTimeInfo.serverTime,
            fromElliotAll.marketContext
        );

        if (fileName == "") {
            return false;
        }

        CsvFileWriter fileWriter(
            fileName,
            true,
            ",",
            true,
            true,
            "Logs\\Mtf3In3AlertValidation\\MTF3IN3_ALERT_V2",
            CSV_FILE_WRITE_MODE_APPEND
        );

        if (!fileWriter.writeHeader(headerValues, true)) {
            fileWriter.close();

            return false;
        }

        string rowValues[];

        if (!setRowValues(
            currentValidationRunId,
            fromSource,
            fromMagicNumber,
            fromElliotAll,
            fromResult,
            rowValues
        )) {
            fileWriter.close();

            return false;
        }

        bool isWritten = fileWriter.writeRow(rowValues);
        fileWriter.close();

        return isWritten;
    }

private:
    /** 1回のEAまたはインジケーター実行を識別するID。 */
    static string validationRunId;

    /**
     * CSVヘッダーを設定する。
     *
     * @param fromValues 設定先配列。
     * @return 列数が正しい場合true。
     */
    static bool setHeaderValues(string &fromValues[]) {
        ArrayResize(fromValues, MTF3_IN3_ALERT_CSV_FIELD_COUNT);
        int index = 0;

        fromValues[index++] = "schema_version";
        fromValues[index++] = "validation_run_id";
        fromValues[index++] = "event_id";
        fromValues[index++] = "source";
        fromValues[index++] = "server_time";
        fromValues[index++] = "jst_time";
        fromValues[index++] = "current_bar_time";
        fromValues[index++] = "signal_point_time";
        fromValues[index++] = "symbol";
        fromValues[index++] = "timeframe";
        fromValues[index++] = "magic";
        fromValues[index++] = "strategy";
        fromValues[index++] = "side";
        fromValues[index++] = "is_judge";
        fromValues[index++] = "signal_count";
        fromValues[index++] = "entry_count";
        fromValues[index++] = "is_entry_count_match";
        fromValues[index++] = "is_entry_evaluated";
        fromValues[index++] = "is_alert";
        fromValues[index++] = "is_entry";
        fromValues[index++] = "entry_result";
        fromValues[index++] = "is_send_mail";
        fromValues[index++] = "current_elliot_label";
        fromValues[index++] = "is_entry_wave";
        fromValues[index++] = "close_ema200_diff_pips";
        fromValues[index++] = "max_close_ema200_diff_pips";
        fromValues[index++] = "is_ema200_distance_within";
        fromValues[index++] = "spread_pips";
        fromValues[index++] = "gmma_trend_count";
        fromValues[index++] = "gmma_cross_count";
        fromValues[index++] = "higher2_timeframe";
        fromValues[index++] = "higher2_ema200_direction";
        fromValues[index++] = "higher1_timeframe";
        fromValues[index++] = "higher1_ema200_direction";
        fromValues[index++] = "current_timeframe";
        fromValues[index++] = "current_ema200_direction";
        fromValues[index++] = "currency_strength_enabled";
        fromValues[index++] = "currency_strength_status";
        fromValues[index++] = "currency_strength_available";
        fromValues[index++] = "currency_strength_calculation_version";
        fromValues[index++] = "currency_strength_run_id";
        fromValues[index++] = "currency_strength_source_mode";
        fromValues[index++] = "currency_strength_target_m5_bar_time";
        fromValues[index++] = "currency_strength_m5_bar_time";
        fromValues[index++] = "base_currency";
        fromValues[index++] = "base_long_medium_rank";
        fromValues[index++] = "base_medium_short_rank";
        fromValues[index++] = "quote_currency";
        fromValues[index++] = "quote_long_medium_rank";
        fromValues[index++] = "quote_medium_short_rank";
        fromValues[index++] = "long_medium_rank_difference";
        fromValues[index++] = "medium_short_rank_difference";
        fromValues[index++] = "reference_price";
        fromValues[index++] = "stop_loss";
        fromValues[index++] = "h1_structure_rank";
        fromValues[index++] = "h1_structure_valid";
        fromValues[index++] = "h1_structure_late";
        fromValues[index++] = "h1_direction_exception";
        fromValues[index++] = "d1_wave_type";
        fromValues[index++] = "d1_elliot_label";
        fromValues[index++] = "h4_wave_type";
        fromValues[index++] = "h4_elliot_label";
        fromValues[index++] = "h1_elliot_label";
        fromValues[index++] = "elliot_csv_text";

        return validateFieldCount(index, "header");
    }

    /**
     * CSVデータ行を設定する。
     *
     * @param fromValidationRunId 検証実行ID。
     * @param fromSource 呼び出し元識別子。
     * @param fromMagicNumber EAのマジックナンバー。
     * @param fromElliotAll 判定に使用したElliott分析結果。
     * @param fromResult MTF_3in3のアラート判定結果。
     * @param fromValues 設定先配列。
     * @return 列数が正しい場合true。
     */
    static bool setRowValues(
        const string fromValidationRunId,
        const string fromSource,
        const ulong fromMagicNumber,
        ElliotAll *fromElliotAll,
        Mtf3In3AlertResult &fromResult,
        string &fromValues[]
    ) {
        Elliot *elliotCurrent = fromElliotAll.elliotCurrent;
        Elliot *elliotHigher2 = fromElliotAll.getElliot(
            fromElliotAll.marketContext.timeFrame,
            2
        );
        Elliot *elliotHigher1 = fromElliotAll.getElliot(
            fromElliotAll.marketContext.timeFrame,
            1
        );
        ZigZagPoint *signalPoint = elliotCurrent.getLatestPoint2();
        datetime currentBarTime = iTime(
            fromElliotAll.marketContext.symbolName,
            fromElliotAll.marketContext.timeFrame,
            0
        );
        datetime signalPointTime = 0;

        if (signalPoint != NULL) {
            signalPointTime = signalPoint.barTime;
        }

        CurrencyStrengthExecutionInfo executionInfo =
            fromElliotAll.currencyStrengthExecutionInfo;
        CurrencyStrengthPairRankInfo pairRankInfo = executionInfo.pairRankInfo;
        Mtf3In3H1ElliotStructureDecision structureDecision;
        Mtf3In3H1ElliotStructureResult structureResult;
        structureDecision.evaluate(fromElliotAll, structureResult);
        string side = getSide(fromResult.isBuy);
        double referencePrice = fromElliotAll.todayRate.bid;

        if (fromResult.isBuy) {
            referencePrice = fromElliotAll.todayRate.ask;
        }

        string eventId = createEventId(
            fromValidationRunId,
            fromElliotAll.marketContext,
            currentBarTime,
            signalPointTime,
            side
        );
        int digits = fromElliotAll.marketContext.digits;

        if (digits < 0 || digits > 8) {
            digits = 8;
        }

        ArrayResize(fromValues, MTF3_IN3_ALERT_CSV_FIELD_COUNT);
        int index = 0;

        fromValues[index++] = "MTF3IN3_ALERT_V2";
        fromValues[index++] = fromValidationRunId;
        fromValues[index++] = eventId;
        fromValues[index++] = fromSource;
        fromValues[index++] = formatDateTime(
            fromElliotAll.tradeTimeInfo.serverTime
        );
        fromValues[index++] = formatDateTime(
            fromElliotAll.tradeTimeInfo.jstTime
        );
        fromValues[index++] = formatDateTime(currentBarTime);
        fromValues[index++] = formatDateTime(signalPointTime);
        fromValues[index++] = fromElliotAll.marketContext.symbolName;
        fromValues[index++] = fromElliotAll.marketContext.timeFrameLabel;
        fromValues[index++] = StringFormat("%I64u", fromMagicNumber);
        fromValues[index++] = "MTF_3in3";
        fromValues[index++] = side;
        fromValues[index++] = formatBool(fromResult.isJudge);
        fromValues[index++] = IntegerToString(fromResult.signalCount);
        fromValues[index++] = IntegerToString(fromResult.entryCount);
        fromValues[index++] = formatBool(fromResult.isEntryCountMatch);
        fromValues[index++] = formatBool(fromResult.isEntryEvaluated);
        fromValues[index++] = formatBool(fromResult.isAlert);
        fromValues[index++] = formatBool(fromResult.isEntry);
        fromValues[index++] = fromResult.entryResult;
        fromValues[index++] = formatBool(fromResult.isSendMail);
        fromValues[index++] = fromResult.currentElliotLabel;
        fromValues[index++] = formatBool(fromResult.isEntryWave);
        fromValues[index++] = DoubleToString(
            fromResult.closeEma200DiffPips,
            1
        );
        fromValues[index++] = DoubleToString(
            fromResult.maxCloseEma200DiffPips,
            1
        );
        fromValues[index++] = formatBool(
            fromResult.isEma200DistanceWithin
        );
        fromValues[index++] = DoubleToString(
            fromElliotAll.todayRate.spread,
            1
        );
        fromValues[index++] = IntegerToString(
            elliotCurrent.oscillator.gmmaTrendCount
        );
        fromValues[index++] = IntegerToString(
            elliotCurrent.oscillator.gmmaCrossCount
        );
        fromValues[index++] = getTimeFrameLabel(elliotHigher2);
        fromValues[index++] = getEma200Direction(elliotHigher2);
        fromValues[index++] = getTimeFrameLabel(elliotHigher1);
        fromValues[index++] = getEma200Direction(elliotHigher1);
        fromValues[index++] = getTimeFrameLabel(elliotCurrent);
        fromValues[index++] = getEma200Direction(elliotCurrent);
        fromValues[index++] = formatBool(
            fromElliotAll.isCurrencyStrengthEntryFilterEnabled
        );
        fromValues[index++] = IntegerToString((int)executionInfo.status);
        fromValues[index++] = formatBool(executionInfo.isAvailable());
        fromValues[index++] = executionInfo.calculationVersion;
        fromValues[index++] = StringFormat("%I64d", pairRankInfo.runId);
        fromValues[index++] = executionInfo.sourceMode;
        fromValues[index++] = formatDateTime(executionInfo.targetM5BarTime);
        fromValues[index++] = formatDateTime(pairRankInfo.m5BarTime);
        fromValues[index++] = pairRankInfo.baseCurrency;
        fromValues[index++] = IntegerToString(
            pairRankInfo.baseLongMediumTermAverageRank
        );
        fromValues[index++] = IntegerToString(
            pairRankInfo.baseMediumShortTermAverageRank
        );
        fromValues[index++] = pairRankInfo.quoteCurrency;
        fromValues[index++] = IntegerToString(
            pairRankInfo.quoteLongMediumTermAverageRank
        );
        fromValues[index++] = IntegerToString(
            pairRankInfo.quoteMediumShortTermAverageRank
        );
        fromValues[index++] = IntegerToString(
            executionInfo.getLongMediumRankDifference()
        );
        fromValues[index++] = IntegerToString(
            executionInfo.getMediumShortRankDifference()
        );
        fromValues[index++] = DoubleToString(referencePrice, digits);
        fromValues[index++] = DoubleToString(
            fromElliotAll.lossCut.lc5,
            digits
        );
        fromValues[index++] = structureResult.getRankLabel();
        fromValues[index++] = formatBool(
            structureResult.isStructureValid
        );
        fromValues[index++] = formatBool(structureResult.isLate);
        fromValues[index++] = formatBool(
            structureResult.isDirectionException
        );
        fromValues[index++] = structureResult.d1WaveType;
        fromValues[index++] = structureResult.d1ElliotLabel;
        fromValues[index++] = structureResult.h4WaveType;
        fromValues[index++] = structureResult.h4ElliotLabel;
        fromValues[index++] = structureResult.h1ElliotLabel;
        fromValues[index++] = fromElliotAll.getCsv(true);

        return validateFieldCount(index, "data");
    }

    /**
     * 検証実行IDを取得する。
     *
     * @return 同一プログラム実行中は固定の検証実行ID。
     */
    static string getValidationRunId() {
        if (Mtf3In3AlertCsvWriter::validationRunId != "") {
            return Mtf3In3AlertCsvWriter::validationRunId;
        }

        datetime localTime = TimeLocal();

        if (localTime <= 0) {
            localTime = TimeCurrent();
        }

        MqlDateTime dateTime;
        TimeToStruct(localTime, dateTime);

        Mtf3In3AlertCsvWriter::validationRunId = StringFormat(
            "%04d%02d%02d_%02d%02d%02d_%I64u_%I64d",
            dateTime.year,
            dateTime.mon,
            dateTime.day,
            dateTime.hour,
            dateTime.min,
            dateTime.sec,
            GetTickCount64(),
            ChartID()
        );

        return Mtf3In3AlertCsvWriter::validationRunId;
    }

    /**
     * サーバー日付単位のCSVファイル名を生成する。
     *
     * @param fromServerTime サーバー時刻。
     * @param fromMarketContext 市場コンテキスト。
     * @return CSVファイル名。時刻変換に失敗した場合は空文字。
     */
    static string createFileName(
        const datetime fromServerTime,
        MarketContext &fromMarketContext
    ) {
        datetime serverTime = fromServerTime;

        if (serverTime <= 0) {
            serverTime = TimeCurrent();
        }

        if (serverTime <= 0) {
            Print("Mtf3In3AlertCsvWriter.createFileName invalid server time");

            return "";
        }

        MqlDateTime dateTime;

        if (!TimeToStruct(serverTime, dateTime)) {
            PrintFormat(
                "Mtf3In3AlertCsvWriter.createFileName TimeToStruct failed. error=%d",
                GetLastError()
            );

            return "";
        }

        return StringFormat(
            "%04d%02d%02d_%s_%s.csv",
            dateTime.year,
            dateTime.mon,
            dateTime.day,
            sanitizeFileNamePart(fromMarketContext.symbolName),
            sanitizeFileNamePart(fromMarketContext.timeFrameLabel)
        );
    }

    /**
     * 候補行を一意に識別するイベントIDを生成する。
     *
     * @param fromValidationRunId 検証実行ID。
     * @param fromMarketContext 市場コンテキスト。
     * @param fromCurrentBarTime 現在バー開始時刻。
     * @param fromSignalPointTime 判定基準ZigZagポイント時刻。
     * @param fromSide 売買方向。
     * @return イベントID。
     */
    static string createEventId(
        const string fromValidationRunId,
        MarketContext &fromMarketContext,
        const datetime fromCurrentBarTime,
        const datetime fromSignalPointTime,
        const string fromSide
    ) {
        return StringFormat(
            "%s_%s_%s_%I64d_%I64d_%s",
            fromValidationRunId,
            sanitizeFileNamePart(fromMarketContext.symbolName),
            sanitizeFileNamePart(fromMarketContext.timeFrameLabel),
            (long)fromCurrentBarTime,
            (long)fromSignalPointTime,
            fromSide
        );
    }

    /**
     * 指定したElliotの時間足表示名を取得する。
     *
     * @param fromElliot 対象Elliot。
     * @return 時間足表示名。対象がない場合は空文字。
     */
    static string getTimeFrameLabel(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return "";
        }

        return fromElliot.marketContext.timeFrameLabel;
    }

    /**
     * 指定したElliotのEMA200方向を取得する。
     *
     * @param fromElliot 対象Elliot。
     * @return BUY、SELLまたはNONE。対象がない場合は空文字。
     */
    static string getEma200Direction(Elliot *fromElliot) {
        if (fromElliot == NULL) {
            return "";
        }

        return fromElliot.oscillator.ema200.getBuySellLabel();
    }

    /**
     * BUYまたはSELLの方向文字列を取得する。
     *
     * @param fromIsBuy BUY方向の場合true。
     * @return BUYまたはSELL。
     */
    static string getSide(const bool fromIsBuy) {
        if (fromIsBuy) {
            return "BUY";
        }

        return "SELL";
    }

    /**
     * 日時をCSV表示文字列へ変換する。
     *
     * @param fromDateTime 変換対象日時。
     * @return 日時文字列。未設定の場合は空文字。
     */
    static string formatDateTime(const datetime fromDateTime) {
        if (fromDateTime <= 0) {
            return "";
        }

        return TimeToString(fromDateTime, TIME_DATE | TIME_SECONDS);
    }

    /**
     * bool値をCSV表示文字列へ変換する。
     *
     * @param fromValue 変換対象値。
     * @return trueまたはfalse。
     */
    static string formatBool(const bool fromValue) {
        if (fromValue) {
            return "true";
        }

        return "false";
    }

    /**
     * ファイル名に使用できない文字をアンダースコアへ置換する。
     *
     * @param fromText 変換対象文字列。
     * @return ファイル名へ使用可能な文字列。
     */
    static string sanitizeFileNamePart(const string fromText) {
        string text = fromText;

        StringReplace(text, "\\", "_");
        StringReplace(text, "/", "_");
        StringReplace(text, ":", "_");
        StringReplace(text, "*", "_");
        StringReplace(text, "?", "_");
        StringReplace(text, "\"", "_");
        StringReplace(text, "<", "_");
        StringReplace(text, ">", "_");
        StringReplace(text, "|", "_");

        if (text == "") {
            return "UNKNOWN";
        }

        return text;
    }

    /**
     * 設定したCSV列数を検証する。
     *
     * @param fromFieldCount 設定済み列数。
     * @param fromRowType headerまたはdata。
     * @return 期待列数と一致する場合true。
     */
    static bool validateFieldCount(
        const int fromFieldCount,
        const string fromRowType
    ) {
        if (fromFieldCount == MTF3_IN3_ALERT_CSV_FIELD_COUNT) {
            return true;
        }

        Print(
            "Mtf3In3AlertCsvWriter invalid field count. type="
            + fromRowType
            + " actual=" + IntegerToString(fromFieldCount)
            + " expected="
            + IntegerToString(MTF3_IN3_ALERT_CSV_FIELD_COUNT)
        );

        return false;
    }
};

string Mtf3In3AlertCsvWriter::validationRunId = "";

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_ALERT_CSV_WRITER_MQH
