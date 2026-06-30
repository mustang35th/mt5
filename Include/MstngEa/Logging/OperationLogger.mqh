/**
 * Package: MstngEa.Logging
 * File: OperationLogger.mqh
 */

#ifndef MSTNGEA_LOGGING_OPERATIONLOGGER_MQH
#define MSTNGEA_LOGGING_OPERATIONLOGGER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <MstngEa\Logging\LogLevel.mqh>

/**
 * 運用ログ出力
 */
class OperationLogger {
public:
    /** ログ出力対象の市場コンテキスト */
    MarketContext marketContext;

    /** ログレベル */
    EaLogLevel logLevel;

    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     */
    OperationLogger(string symbolNameValue, ENUM_TIMEFRAMES timeFrameValue) {
        MarketContext context(symbolNameValue, timeFrameValue);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param marketContextValue ログ出力対象の市場コンテキスト
     */
    OperationLogger(MarketContext &marketContextValue) {
        this.initializeMarketContext(marketContextValue);
    }

    /**
     * ログレベル設定
     *
     * @param logLevelValue ログレベル
     */
    void setLogLevel(EaLogLevel logLevelValue) {
        // ログレベルを更新
        this.logLevel = logLevelValue;
    }

    /**
     * DEBUG出力
     *
     * @param categoryValue 区分
     * @param messageValue メッセージ
     */
    void debug(string categoryValue, string messageValue) {

        if (this.logLevel > LOG_LEVEL_DEBUG) {
            return;
        }

        // DEBUGログを出力
        this.write(LOG_LEVEL_DEBUG, categoryValue, messageValue);
    }

    /**
     * INFO出力
     *
     * @param categoryValue 区分
     * @param messageValue メッセージ
     */
    void info(string categoryValue, string messageValue) {

        if (this.logLevel > LOG_LEVEL_INFO) {
            return;
        }

        // INFOログを出力
        this.write(LOG_LEVEL_INFO, categoryValue, messageValue);
    }

    /**
     * WARN出力
     *
     * @param categoryValue 区分
     * @param messageValue メッセージ
     */
    void warn(string categoryValue, string messageValue) {

        if (this.logLevel > LOG_LEVEL_WARN) {
            return;
        }

        // WARNログを出力
        this.write(LOG_LEVEL_WARN, categoryValue, messageValue);
    }

    /**
     * ERROR出力
     *
     * @param categoryValue 区分
     * @param messageValue メッセージ
     */
    void error(string categoryValue, string messageValue) {

        if (this.logLevel > LOG_LEVEL_ERROR) {
            return;
        }

        // ERRORログを出力
        this.write(LOG_LEVEL_ERROR, categoryValue, messageValue);
    }

private:
    /**
     * 市場コンテキストを設定する。
     *
     * @param marketContextValue ログ出力対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &marketContextValue) {
        this.marketContext = marketContextValue;
        this.logLevel = LOG_LEVEL_INFO;
    }

    /**
     * ログ文字列出力
     *
     * @param logLevelValue ログレベル
     * @param categoryValue 区分
     * @param messageValue メッセージ
     */
    void write(EaLogLevel logLevelValue, string categoryValue, string messageValue) {
        // 出力パスを生成
        string currentFilePath = this.buildFilePath();

        int fileHandle = FileOpen(
            currentFilePath,
            FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_WRITE
        );

        if (fileHandle == INVALID_HANDLE) {
            Print("OperationLogger FileOpen failed: " + currentFilePath);
            return;
        }

        // 追記位置へ移動
        FileSeek(fileHandle, 0, SEEK_END);

        string line = this.buildLogLine(logLevelValue, categoryValue, messageValue);
        FileWriteString(fileHandle, line + "\r\n");
        FileClose(fileHandle);
    }

    /**
     * ログ1行生成
     *
     * @param logLevelValue ログレベル
     * @param categoryValue 区分
     * @param messageValue メッセージ
     * @return ログ1行
     */
    string buildLogLine(EaLogLevel logLevelValue, string categoryValue, string messageValue) {
        // ログ本文を構築
        string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
        line += " [" + this.getLevelLabel(logLevelValue) + "]";
        line += " [" + categoryValue + "] ";
        line += messageValue;

        return line;
    }

    /**
     * ログレベル文字列取得
     *
     * @param logLevelValue ログレベル
     * @return ログレベル文字列
     */
    string getLevelLabel(EaLogLevel logLevelValue) {

        if (logLevelValue == LOG_LEVEL_DEBUG) {
            return "DEBUG";
        }

        if (logLevelValue == LOG_LEVEL_INFO) {
            return "INFO";
        }

        if (logLevelValue == LOG_LEVEL_WARN) {
            return "WARN";
        }

        return "ERROR";
    }

    /**
     * 出力先生成
     *
     * @return 出力先
     */
    string buildFilePath() {
        // 共通データフォルダ配下の相対パスを返却
        string timeFrameLabel = IntegerToString((int)this.marketContext.timeFrame);
        string filePath = "MstngEa\\Logs\\MstngEa_";
        filePath += this.marketContext.symbolName;
        filePath += "_";
        filePath += timeFrameLabel;
        filePath += ".log";

        return filePath;
    }
};

#endif
