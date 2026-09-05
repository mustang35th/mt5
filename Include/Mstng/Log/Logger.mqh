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
    /** デバッグレベル。 */
    LOG_DEBUG = 0,

    /** 情報レベル。 */
    LOG_INFO,

    /** 警告レベル。 */
    LOG_WARN,

    /** エラーレベル。 */
    LOG_ERROR
};

/**
 * Testerの重複ログ抑制区間へ入る前の状態を保持する。
 * begin/endを逆順に対応させ、呼び出し元の区間を復元する。
 */
struct LoggerRepeatScope {
    /** このトークンで区間を開始したか。 */
    bool started;
    /** 呼び出し前に抑制区間が有効だったか。 */
    bool wasActive;
    /** 呼び出し前のシンボル・H1開始時刻キー。 */
    string previousKey;
};

/**
 * Printを使用してターミナルへログを出力するクラス。
 *
 * 設定したログレベルと市場コンテキストを使用し、
 * シンボル名・時間足・メソッド名を含む形式で出力する。
 */
class Logger {
public:
    /**
     * ログレベルと現在チャートの時間足を初期化する。
     *
     * @param threshold 出力対象とする最小ログレベル。
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
     * @param fromMarketContext ログ出力対象の市場コンテキスト。
     * @param fromThreshold 出力対象とする最小ログレベル。
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
     * @return 最小ログレベルがLOG_DEBUGの場合true。
     */
    bool isDebugMode() {
        return (this.levelThreshold == LOG_DEBUG);
    }


    /**
     * 出力対象とする最小ログレベルを設定する。
     *
     * @param threshold 出力対象とする最小ログレベル。
     */
    void setLevel(LogLevel threshold) {
        this.levelThreshold = threshold;
    }
    
    /**
     * シンボル名と時間足を設定する。
     *
     * @param fromSymbolName 対象シンボル。
     * @param fromTimeFrame 対象時間足。
     */
    void setSymbolNameAndTimeFrame(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext ログ出力対象の市場コンテキスト。
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * Testerだけで同一シンボル・H1内の重複ログ抑制区間を開始する。
     * 新しいキーの初回ログは出力し、同じキーの再試行では記録を保持する。
     *
     * @param fromSymbol 分析対象シンボル。
     * @param fromH1BarTime 分析対象H1の開始時刻。
     * @param fromScope 区間終了時に使用する呼び出し前の状態。
     */
    static void beginTesterRepeatScope(
        const string fromSymbol,
        const datetime fromH1BarTime,
        LoggerRepeatScope &fromScope
    ) {
        fromScope.started = false;
        fromScope.wasActive = false;
        fromScope.previousKey = "";
        if (!MQLInfoInteger(MQL_TESTER) || fromSymbol == "" || fromH1BarTime <= 0) {
            return;
        }

        fromScope.wasActive = Logger::repeatScopeActive;
        fromScope.previousKey = Logger::repeatScopeKey;
        fromScope.started = true;
        Logger::repeatScopeActive = true;
        Logger::repeatScopeKey = fromSymbol + "|" + IntegerToString((long)fromH1BarTime);
        if (Logger::repeatCacheKey != Logger::repeatScopeKey) {
            Logger::clearRepeatCache();
            Logger::repeatCacheKey = Logger::repeatScopeKey;
        }
    }

    /**
     * 重複ログ抑制区間を終了し、呼び出し前の有効状態を復元する。
     * 分析成功時は記録を解除し、同じH1内でも次に発生した障害を出力する。
     *
     * @param fromScope 対応するbeginが保持した状態。入れ子は逆順に終了する。
     * @param fromSucceeded 分析に成功した場合true。
     */
    static void endTesterRepeatScope(LoggerRepeatScope &fromScope, const bool fromSucceeded) {
        if (!fromScope.started) {
            return;
        }
        if (fromSucceeded) {
            Logger::clearRepeatCache();
        }
        Logger::repeatScopeActive = fromScope.wasActive;
        Logger::repeatScopeKey = fromScope.previousKey;
        fromScope.started = false;
    }

    /**
     * 指定したログレベルでメッセージを出力する。
     *
     * 最小ログレベル未満のメッセージは出力しない。
     * DEBUGは対象時間足が現在チャートの時間足と一致する場合のみ出力する。
     * INFO/WARN/ERRORは時間足条件に関係なく出力する。
     *
     * @param level ログレベル。
     * @param funcName 出力元のメソッド名。
     * @param message 出力メッセージ。
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

        if (Logger::isRepeatedOutput(level, output)) {
            return;
        }
        
        Print(output);
    }

    /**
     * DEBUGレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名。
     * @param message 出力メッセージ。
     */
    void debug(const string funcName, const string message) {
        this.log(LOG_DEBUG, funcName, message);
    }

    /**
     * INFOレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名。
     * @param message 出力メッセージ。
     */
    void info(const string funcName, const string message) {
        this.log(LOG_INFO, funcName, message);
    }

    /**
     * WARNレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名。
     * @param message 出力メッセージ。
     */
    void warn(const string funcName, const string message) {
        this.log(LOG_WARN, funcName, message);
    }

    /**
     * ERRORレベルのメッセージを出力する。
     *
     * @param funcName 出力元のメソッド名。
     * @param message 出力メッセージ。
     */
    void error(const string funcName, const string message) {
        this.log(LOG_ERROR, funcName, message);
    }
    
private:
    /** 出力対象とする最小ログレベル。 */
    LogLevel levelThreshold;

    /** 現在チャートの市場コンテキスト。 */
    MarketContext chartMarketContext;

    /** ログ出力対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** 明示的に開始したTesterの抑制区間だけでtrue。通常はfalse。 */
    static bool repeatScopeActive;
    /** 現在の抑制区間のシンボル・H1開始時刻キー。 */
    static string repeatScopeKey;
    /** 保持中のログに対応する区間キー。 */
    static string repeatCacheKey;
    /** 整形済み出力を完全一致で比較する固定長リング。 */
    static string repeatedOutputs[64];
    /** 現在記録している出力数。 */
    static int repeatedOutputCount;
    /** 新しい出力で置き換えるリング位置。 */
    static int nextRepeatedOutputIndex;

    /**
     * 重複記録を消し、次のログを初回として扱う。
     */
    static void clearRepeatCache() {
        for (int i = 0; i < Logger::repeatedOutputCount; i++) {
            Logger::repeatedOutputs[i] = "";
        }
        Logger::repeatCacheKey = "";
        Logger::repeatedOutputCount = 0;
        Logger::nextRepeatedOutputIndex = 0;
    }

    /**
     * 明示区間内のINFO/ERRORで同じ整形済み出力が既に出たか判定する。
     * 固定長リングからあふれた新規ログも抑殺せず出力する。
     */
    static bool isRepeatedOutput(const LogLevel fromLevel, const string fromOutput) {
        if (!Logger::repeatScopeActive || (fromLevel != LOG_INFO && fromLevel != LOG_ERROR)) {
            return false;
        }
        if (Logger::repeatCacheKey != Logger::repeatScopeKey) {
            Logger::clearRepeatCache();
            Logger::repeatCacheKey = Logger::repeatScopeKey;
        }
        for (int i = 0; i < Logger::repeatedOutputCount; i++) {
            if (Logger::repeatedOutputs[i] == fromOutput) {
                return true;
            }
        }
        Logger::repeatedOutputs[Logger::nextRepeatedOutputIndex] = fromOutput;
        Logger::nextRepeatedOutputIndex++;
        if (Logger::nextRepeatedOutputIndex >= ArraySize(Logger::repeatedOutputs)) {
            Logger::nextRepeatedOutputIndex = 0;
        }
        if (Logger::repeatedOutputCount < ArraySize(Logger::repeatedOutputs)) {
            Logger::repeatedOutputCount++;
        }
        return false;
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext ログ出力対象の市場コンテキスト。
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
    }
    
    /**
     * ログレベルを表示用文字列に変換する。
     *
     * @param level ログレベル。
     * @return ログレベルの表示用文字列。
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

bool Logger::repeatScopeActive = false;
string Logger::repeatScopeKey = "";
string Logger::repeatCacheKey = "";
string Logger::repeatedOutputs[64];
int Logger::repeatedOutputCount = 0;
int Logger::nextRepeatedOutputIndex = 0;
//+------------------------------------------------------------------+


