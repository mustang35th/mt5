//+------------------------------------------------------------------+
//|                                               SqliteDatabase.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_SQLITE_DATABASE_MQH
#define MSTNG_DATABASE_SQLITE_DATABASE_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * SQLiteデータベースの接続を管理するクラス。
 *
 * データベースハンドルのオープンとクローズを担当する。
 */
class SqliteDatabase {
public:
    /**
     * データベースファイル名と共有フォルダ使用有無を指定して初期化する。
     *
     * @param fromFileName データベースファイル名。
     * @param fromUseCommonFolder 共有フォルダを使用する場合はtrue。
     */
    SqliteDatabase(
        const string fromFileName,
        const bool fromUseCommonFolder = true
    ) {
        this.fileName = fromFileName;
        this.useCommonFolder = fromUseCommonFolder;
        this.databaseHandle = INVALID_HANDLE;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * デストラクタ。
     */
    ~SqliteDatabase() {
        this.close();
    }

    /**
     * データベースを開く。存在しない場合は作成する。
     *
     * @return オープンに成功した場合はtrue。
     */
    bool open() {
        if (this.isOpen()) {
            return true;
        }

        uint flags = DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE;

        if (this.useCommonFolder) {
            flags = flags | DATABASE_OPEN_COMMON;
        }

        ResetLastError();
        this.databaseHandle = DatabaseOpen(this.fileName, flags);

        if (this.databaseHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseOpen failed. fileName=%s error=%d",
                    this.fileName,
                    GetLastError()
                )
            );

            return false;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "Database opened. fileName=%s common=%d",
                this.fileName,
                (int)this.useCommonFolder
            )
        );

        return true;
    }

    /**
     * データベースを読み取り専用で開く。
     *
     * 存在しないデータベースファイルは作成しない。
     *
     * @return オープンに成功した場合はtrue。
     */
    bool openReadOnly() {
        if (this.isOpen()) {
            return true;
        }

        uint flags = DATABASE_OPEN_READONLY;

        if (this.useCommonFolder) {
            flags = flags | DATABASE_OPEN_COMMON;
        }

        ResetLastError();
        this.databaseHandle = DatabaseOpen(this.fileName, flags);

        if (this.databaseHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseOpen failed. fileName=%s readOnly=1 error=%d",
                    this.fileName,
                    GetLastError()
                )
            );

            return false;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "Database opened. fileName=%s common=%d readOnly=1",
                this.fileName,
                (int)this.useCommonFolder
            )
        );

        return true;
    }

    /**
     * データベースを閉じる。
     */
    void close() {
        if (!this.isOpen()) {
            return;
        }

        int closedHandle = this.databaseHandle;
        this.databaseHandle = INVALID_HANDLE;

        ResetLastError();
        DatabaseClose(closedHandle);

        int errorCode = GetLastError();

        if (errorCode != 0) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseClose failed. fileName=%s error=%d",
                    this.fileName,
                    errorCode
                )
            );

            return;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat("Database closed. fileName=%s", this.fileName)
        );
    }

    /**
     * データベースがオープン済みか判定する。
     *
     * @return オープン済みの場合はtrue。
     */
    bool isOpen() const {
        return this.databaseHandle != INVALID_HANDLE;
    }

    /**
     * データベースハンドルを取得する。
     *
     * @return データベースハンドル。
     */
    int getHandle() const {
        return this.databaseHandle;
    }

    /**
     * データベースファイル名を取得する。
     *
     * @return データベースファイル名。
     */
    string getFileName() const {
        return this.fileName;
    }

    /**
     * 共有フォルダを使用するか判定する。
     *
     * @return 共有フォルダを使用する場合はtrue。
     */
    bool isCommonFolder() const {
        return this.useCommonFolder;
    }

private:
    /** データベースファイル名。 */
    string fileName;

    /** 共有フォルダ使用有無。 */
    bool useCommonFolder;

    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;
};

#endif // MSTNG_DATABASE_SQLITE_DATABASE_MQH
