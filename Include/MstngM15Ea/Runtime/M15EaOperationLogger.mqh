#ifndef MSTNGM15EA_RUNTIME_OPERATIONLOGGER_MQH
#define MSTNGM15EA_RUNTIME_OPERATIONLOGGER_MQH

#include <Mstng\Log\Logger.mqh>
#include <MstngEaCommon\Runtime\EaTextUtil.mqh>

/**
 * 既存Loggerと、DB障害時にも利用できる追記専用運用ログ。
 */
class M15EaOperationLogger {
public:
    /**
     * 初期化前の終了処理ではファイルへ書き込まない。
     */
    M15EaOperationLogger() {
        this.identity = "";
        this.fileName = "";
    }

    /**
     * 出力先を初期化する。ファイルは出力時だけ開く。
     */
    void initialize(const string fromSymbol, const ulong fromMagic, const string fromRunUid) {
        this.logger.setSymbolNameAndTimeFrame(fromSymbol, PERIOD_M15);
        this.logger.setLevel(LOG_INFO);
        this.identity = fromSymbol + "|" + EaTextUtil::ticket(fromMagic) + "|" + fromRunUid;

        this.fileName = "MstngM15Ea\\Logs\\" + fromRunUid + ".log";
        FolderCreate("MstngM15Ea", FILE_COMMON);
        FolderCreate("MstngM15Ea\\Logs", FILE_COMMON);
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
            this.logger.error("M15EaOperationLogger.append", "LOG_UNAVAILABLE: " + this.fileName);
            return;
        }

        FileSeek(fileHandle, 0, SEEK_END);
        string record = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS)
            + " [" + fromLevel + "] " + this.identity + " " + fromMethod + ": " + fromMessage + "\r\n";
        if (FileWriteString(fileHandle, record) == 0) {
            this.logger.error("M15EaOperationLogger.append", "LOG_WRITE_FAILED");
        }

        FileFlush(fileHandle);
        FileClose(fileHandle);
    }
};

#endif
