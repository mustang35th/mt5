//+------------------------------------------------------------------+
//|                                     MailValidationFileWriter.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_MAIL_MAIL_VALIDATION_FILE_WRITER_MQH
#define MSTNG_MAIL_MAIL_VALIDATION_FILE_WRITER_MQH

#include <Mstng\Common\File\CsvFileWriter.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * Mailで生成したタイトルと本文を検証用テキストファイルへ保存する。
 */
class MailValidationFileWriter {
public:
    /**
     * Mail出力内容を日付・シンボル・時間足別ファイルへ追記する。
     *
     * 最適化中は複数エージェントの同時書き込みを避けるため出力しない。
     *
     * @param fromJstTime シグナル発生時の日本時間
     * @param fromServerTime シグナル発生時のサーバー時間
     * @param fromSymbolName 対象シンボル名
     * @param fromTimeFrame 対象時間足
     * @param fromIsTimer タイマー実行の場合true
     * @param fromIsSendMail メール送信対象の場合true
     * @param fromTitle Mailタイトル
     * @param fromBody Mail本文
     * @return 出力成功または最適化による出力省略の場合true
     */
    static bool write(
        const datetime fromJstTime,
        const datetime fromServerTime,
        const string fromSymbolName,
        const ENUM_TIMEFRAMES fromTimeFrame,
        const bool fromIsTimer,
        const bool fromIsSendMail,
        const string fromTitle,
        const string fromBody
    ) {
        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            return true;
        }

        string fileName = createFileName(
            fromJstTime,
            fromSymbolName,
            fromTimeFrame
        );
        string record = createRecord(
            fromJstTime,
            fromServerTime,
            fromSymbolName,
            fromTimeFrame,
            fromIsTimer,
            fromIsSendMail,
            fromTitle,
            fromBody
        );
        CsvFileWriter fileWriter(
            fileName,
            true,
            ",",
            true,
            false,
            "Logs\\MailValidation",
            CSV_FILE_WRITE_MODE_APPEND
        );
        bool isWritten = fileWriter.writeLine(record);
        fileWriter.close();

        return isWritten;
    }

private:
    /**
     * シグナル日、シンボルおよび時間足からファイル名を生成する。
     *
     * @param fromJstTime シグナル発生時の日本時間
     * @param fromSymbolName 対象シンボル名
     * @param fromTimeFrame 対象時間足
     * @return 検証ファイル名
     */
    static string createFileName(
        const datetime fromJstTime,
        const string fromSymbolName,
        const ENUM_TIMEFRAMES fromTimeFrame
    ) {
        datetime fileDateTime = fromJstTime;

        if (fileDateTime <= 0) {
            fileDateTime = TimeLocal();
        }

        MqlDateTime dateTime;
        TimeToStruct(fileDateTime, dateTime);

        string symbolName = sanitizeFileNamePart(fromSymbolName);
        string timeFrameLabel = sanitizeFileNamePart(
            TimeUtil::convertTimeFrameToString(fromTimeFrame)
        );

        return StringFormat(
            "%04d%02d%02d_%s_%s.txt",
            dateTime.year,
            dateTime.mon,
            dateTime.day,
            symbolName,
            timeFrameLabel
        );
    }

    /**
     * 1回のMail出力内容を区切り付きテキストへ変換する。
     *
     * @param fromJstTime シグナル発生時の日本時間
     * @param fromServerTime シグナル発生時のサーバー時間
     * @param fromSymbolName 対象シンボル名
     * @param fromTimeFrame 対象時間足
     * @param fromIsTimer タイマー実行の場合true
     * @param fromIsSendMail メール送信対象の場合true
     * @param fromTitle Mailタイトル
     * @param fromBody Mail本文
     * @return ファイルへ保存する1レコード
     */
    static string createRecord(
        const datetime fromJstTime,
        const datetime fromServerTime,
        const string fromSymbolName,
        const ENUM_TIMEFRAMES fromTimeFrame,
        const bool fromIsTimer,
        const bool fromIsSendMail,
        const string fromTitle,
        const string fromBody
    ) {
        string body = normalizeLineBreaks(fromBody);
        string record = "===== MAIL BEGIN =====\r\n";

        record += StringFormat(
            "JST=%s\r\n",
            TimeUtil::formatYyyymmddhhmiss(fromJstTime)
        );
        record += StringFormat(
            "SERVER=%s\r\n",
            TimeUtil::formatYyyymmddhhmiss(fromServerTime)
        );
        record += StringFormat("SYMBOL=%s\r\n", fromSymbolName);
        record += StringFormat(
            "TIMEFRAME=%s\r\n",
            TimeUtil::convertTimeFrameToString(fromTimeFrame)
        );
        record += StringFormat(
            "IS_TIMER=%s\r\n",
            formatBool(fromIsTimer)
        );
        record += StringFormat(
            "IS_SEND_MAIL=%s\r\n",
            formatBool(fromIsSendMail)
        );
        record += StringFormat("TITLE=%s\r\n", fromTitle);
        record += "BODY_BEGIN\r\n";
        record += body;

        if (StringLen(body) > 0
                && StringSubstr(body, StringLen(body) - 1, 1) != "\n") {
            record += "\r\n";
        }

        record += "BODY_END\r\n";
        record += "===== MAIL END =====";

        return record;
    }

    /**
     * ファイル名に使用できない文字をアンダースコアへ置換する。
     *
     * @param fromText 変換対象文字列
     * @return ファイル名へ使用可能な文字列
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
     * 改行コードをCRLFへ統一する。
     *
     * @param fromText 変換対象文字列
     * @return CRLFへ統一した文字列
     */
    static string normalizeLineBreaks(const string fromText) {
        string text = fromText;

        StringReplace(text, "\r\n", "\n");
        StringReplace(text, "\r", "\n");
        StringReplace(text, "\n", "\r\n");

        return text;
    }

    /**
     * bool値を表示文字列へ変換する。
     *
     * @param fromValue 変換対象値
     * @return trueまたはfalse
     */
    static string formatBool(const bool fromValue) {
        if (fromValue) {
            return "true";
        }

        return "false";
    }
};

#endif // MSTNG_MAIL_MAIL_VALIDATION_FILE_WRITER_MQH
