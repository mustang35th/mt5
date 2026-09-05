#ifndef MSTNGH1EA_RUNTIME_OPERATIONLOGGER_MQH
#define MSTNGH1EA_RUNTIME_OPERATIONLOGGER_MQH

#include <Mstng\Log\Logger.mqh>
#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>

/**
 * 既存Loggerと、DB障害時にも利用できる追記専用運用ログ。
 */
class H1EaOperationLogger {
public:
    /**
     * 出力先を初期化する。ファイルは出力時だけ開く。
     */
    void initialize(const string fromSymbol, const ulong fromMagic, const string fromRunUid) {
        this.logger.setSymbolNameAndTimeFrame(fromSymbol, PERIOD_H1);
        this.logger.setLevel(LOG_INFO);
        this.identity = fromSymbol + "|" + H1EaTextUtil::ticket(fromMagic) + "|" + fromRunUid;
        this.fileName = "MstngH1Ea\\Logs\\" + fromRunUid + ".log";
        FolderCreate("MstngH1Ea", FILE_COMMON);
        FolderCreate("MstngH1Ea\\Logs", FILE_COMMON);
    }

    /**
     * 通常の状態変更を記録する。
     */
    void info(const string fromMethod, const string fromMessage) {
        this.logger.info(fromMethod, fromMessage);
        this.append("INFO", fromMethod, fromMessage);
    }

    /**
     * 判定拒否・保存失敗を記録する。
     */
    void error(const string fromMethod, const string fromMessage) {
        this.logger.error(fromMethod, fromMessage);
        this.append("ERROR", fromMethod, fromMessage);
    }

    /**
     * 通常時は出力しない診断情報を渡す。
     */
    void debug(const string fromMethod, const string fromMessage) {
        this.logger.debug(fromMethod, fromMessage);
    }

private:
    /** 既存形式のターミナルログ。 */
    Logger logger;
    /** 実行識別情報。 */
    string identity;
    /** Common内の追記先。 */
    string fileName;

    /**
     * DBに依存せず1行追記し、直ちにハンドルを閉じる。
     */
    void append(const string fromLevel, const string fromMethod, const string fromMessage) {
        if (this.fileName == "") {
            return;
        }
        int fileHandle = FileOpen(this.fileName,
            FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ,
            0, CP_UTF8);
        if (fileHandle == INVALID_HANDLE) {
            this.logger.error("H1EaOperationLogger.append", "LOG_UNAVAILABLE: " + this.fileName);
            return;
        }
        FileSeek(fileHandle, 0, SEEK_END);
        string record = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS)
            + " [" + fromLevel + "] " + this.identity + " " + fromMethod + ": " + fromMessage + "\r\n";
        if (FileWriteString(fileHandle, record) == 0) {
            this.logger.error("H1EaOperationLogger.append", "LOG_WRITE_FAILED");
        }
        FileFlush(fileHandle);
        FileClose(fileHandle);
    }
};

#endif
