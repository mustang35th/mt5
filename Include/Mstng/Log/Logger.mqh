//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * ログ出力の重要度を表す列挙型。
 */
enum LogLevel {
    /** デバッグレベル */
    LOG_DEBUG = 0,

    /** 情報レベル */
    LOG_INFO,

    /** 警告レベル */
    LOG_WARN,

    /** エラーレベル */
    LOG_ERROR
};

/**
 * Printを使用してターミナルへログを出力するクラスです。
 *
 * 設定したログレベルと市場コンテキストを使用し、
 * シンボル名・時間足・メソッド名を含む形式で出力する。
 */
class Logger {
public:
    /**
     * ログレベルと現在チャートの時間足を初期化する。
     *
     * @param threshold 出力対象とする最小ログレベル
     */
    Logger(LogLevel threshold = LOG_DEBUG) {
        this.levelThreshold = threshold;

        MarketContext context(_Symbol, (ENUM_TIMEFRAMES)_Period);
        this.chartMarketContext = context;
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストとログレベルを初期化する。
     *
     * @param fromMarketContext ログ出力対象の市場コンテキスト
     * @param fromThreshold 出力対象とする最小ログレベル
     */
    Logger(MarketContext &fromMarketContext, LogLevel fromThreshold = LOG_DEBUG) {
        this.levelThreshold = fromThreshold;

        MarketContext chartContext(_Symbol, (ENUM_TIMEFRAMES)_Period);
        this.chartMarketContext = chartContext;
        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * デバッグログを出力する設定か判定する。
     *
     * @return 最小ログレベルがLOG_DEBUGの場合true
     */
    bool isDebugMode() {
        return (this.levelThreshold == LOG_DEBUG);
    }


    /**
     * 出力対象とする最小ログレベルを設定する。
     *
     * @param threshold 出力対象とする最小ログレベル
     */
    void setLevel(LogLevel threshold) {
        this.levelThreshold = threshold;
    }
    
    /**
     * シンボル名と時間足を設定する。
     *
     * @param fromSymbolName 対象シンボル
     * @param fromTimeFrame 対象時間足
     */
    void setSymbolNameAndTimeFrame(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext ログ出力対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * 指定したログレベルでメッセージを出力する。
     *
     * 最小ログレベル未満のメッセージは出力しない。
     * DEBUGは対象時間足が現在チャートの時間足と一致する場合のみ出力する。
     * INFO/WARN/ERRORは時間足条件に関係なく出力する。
     *
     * @param level ログレベル
     * @param funcName 出力元のメソッド名
     * @param message 出力メッセージ
     */
    void log(LogLevel level, const string funcName, const string message) {
        if (level < this.levelThreshold) {
            return;
        }
        
        if (level == LOG_DEBUG
                && this.marketContext.timeFrame != this.chartMarketContext.timeFrame) {
            return;
        }
        
        string output = StringFormat(
            "[%s] (%s, %s) %s: %s",
            this.levelToString(level),
            this.marketContext.symbolName,
            this.marketContext.timeFrameLabel,
            funcName,
            message
        );
        
        Print(output);
    }

    /**
     * DEBUGレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名
     * @param message 出力メッセージ
     */
    void debug(const string funcName, const string message) {
        this.log(LOG_DEBUG, funcName, message);
    }

    /**
     * INFOレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名
     * @param message 出力メッセージ
     */
    void info(const string funcName, const string message) {
        this.log(LOG_INFO, funcName, message);
    }

    /**
     * WARNレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名
     * @param message 出力メッセージ
     */
    void warn(const string funcName, const string message) {
        this.log(LOG_WARN, funcName, message);
    }

    /**
     * ERRORレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名
     * @param message 出力メッセージ
     */
    void error(const string funcName, const string message) {
        this.log(LOG_ERROR, funcName, message);
    }
    
private:
    /** 出力対象とする最小ログレベル */
    LogLevel levelThreshold;

    /** 現在チャートの市場コンテキスト */
    MarketContext chartMarketContext;

    /** ログ出力対象の市場コンテキスト */
    MarketContext marketContext;

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext ログ出力対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
    }
    
    /**
     * ログレベルを表示用文字列に変換する。
     *
     * @param level ログレベル
     * @return ログレベルの表示用文字列
     */
    string levelToString(LogLevel level) {
        switch(level) {
        case LOG_DEBUG:
            return "DEBUG";
        case LOG_INFO:
            return "INFO";
        case LOG_WARN:
            return "WARN";
        case LOG_ERROR:
            return "ERROR";
        }
        return "UNKNOWN";
    }

};
//+------------------------------------------------------------------+


