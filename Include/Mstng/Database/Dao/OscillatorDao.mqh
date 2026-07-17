//+------------------------------------------------------------------+
//|                                                OscillatorDao.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_DAO_OSCILLATOR_DAO_MQH
#define MSTNG_DATABASE_DAO_OSCILLATOR_DAO_MQH

#include <Mstng\Database\Entity\OscillatorEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * オシレーター計算結果をSQLiteへ保存・取得するDAO。
 */
class OscillatorDao {
public:
    /**
     * 使用するデータベースハンドルを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     */
    OscillatorDao(const int fromDatabaseHandle) {
        this.databaseHandle = fromDatabaseHandle;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * オシレーター計算結果テーブルを作成する。
     *
     * @return 作成または存在確認に成功した場合はtrue。
     */
    bool createTable() {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "CREATE TABLE IF NOT EXISTS oscillator_values (";
        sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
        sql += "calculated_at INTEGER NOT NULL,";
        sql += "symbol_name TEXT NOT NULL,";
        sql += "time_frame INTEGER NOT NULL,";
        sql += "oscillator_count INTEGER NOT NULL,";
        sql += "is_buy INTEGER NOT NULL";
        sql += ")";

        ResetLastError();

        if (!DatabaseExecute(this.databaseHandle, sql)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseExecute failed. error=%d", GetLastError())
            );

            return false;
        }

        this.logger.info(__FUNCTION__, "oscillator_values table is ready.");

        return true;
    }

    /**
     * オシレーター計算結果を保存する。
     *
     * @param fromEntity 保存対象エンティティ。
     * @return 保存に成功した場合はtrue。
     */
    bool insert(OscillatorEntity &fromEntity) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "INSERT INTO oscillator_values (";
        sql += "calculated_at, symbol_name, time_frame, oscillator_count, is_buy";
        sql += ") VALUES (?1, ?2, ?3, ?4, ?5)";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        bool isBound = DatabaseBind(requestHandle, 0, fromEntity.calculatedAt);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, 1, fromEntity.symbolName);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 2, fromEntity.timeFrame);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 3, fromEntity.oscillatorCount);
        }
        if (isBound) {
            isBound = DatabaseBind(requestHandle, 4, fromEntity.isBuy);
        }

        if (!isBound) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        ResetLastError();
        DatabaseRead(requestHandle);
        int executeErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);

        // INSERTは結果行を返さないため正常時もNO_MORE_DATAとなる
        if (executeErrorCode != ERR_DATABASE_NO_MORE_DATA) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("INSERT failed. error=%d", executeErrorCode)
            );

            return false;
        }

        return true;
    }

    /**
     * 指定したシンボルと時間足の最新レコードを取得する。
     *
     * @param fromSymbolName シンボル名。
     * @param fromTimeFrame 時間足。
     * @param fromEntity 取得結果の格納先。
     * @return レコードを取得できた場合はtrue。
     */
    bool findLatest(
        const string fromSymbolName,
        const ENUM_TIMEFRAMES fromTimeFrame,
        OscillatorEntity &fromEntity
    ) {
        if (!this.isDatabaseReady(__FUNCTION__)) {
            return false;
        }

        string sql = "SELECT ";
        sql += "id, calculated_at, symbol_name, time_frame, oscillator_count, is_buy ";
        sql += "FROM oscillator_values ";
        sql += "WHERE symbol_name = ?1 AND time_frame = ?2 ";
        sql += "ORDER BY id DESC LIMIT 1";

        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        bool isBound = DatabaseBind(requestHandle, 0, fromSymbolName);

        if (isBound) {
            isBound = DatabaseBind(requestHandle, 1, (int)fromTimeFrame);
        }

        if (!isBound) {
            int bindErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
            );

            return false;
        }

        ResetLastError();
        bool isRead = DatabaseReadBind(requestHandle, fromEntity);
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);

        if (!isRead) {
            if (readErrorCode == ERR_DATABASE_NO_MORE_DATA) {
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "Record not found. symbolName=%s timeFrame=%d",
                        fromSymbolName,
                        (int)fromTimeFrame
                    )
                );
            } else {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat("DatabaseReadBind failed. error=%d", readErrorCode)
                );
            }

            return false;
        }

        return true;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** ロガー。 */
    Logger logger;

    /**
     * データベースハンドルが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合はtrue。
     */
    bool isDatabaseReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE) {
            return true;
        }

        this.logger.error(fromMethodName, "databaseHandle is INVALID_HANDLE.");

        return false;
    }
};

#endif // MSTNG_DATABASE_DAO_OSCILLATOR_DAO_MQH
