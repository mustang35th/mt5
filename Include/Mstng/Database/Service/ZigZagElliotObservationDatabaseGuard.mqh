#ifndef MSTNG_ZZE_OBSERVATION_DATABASE_GUARD_MQH
#define MSTNG_ZZE_OBSERVATION_DATABASE_GUARD_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * M5専用観測DBの用途と対応する物理スキーマを読み取りだけで検査する。
 *
 * WAL設定・DDL・migration・Run保存より前に実行する。
 * 初版では空DBと現行4テーブルの完全構成だけを許可し、自動修復しない。
 */
class ZigZagElliotObservationDatabaseGuard {
public:
    /**
     * M5観測を書き込めるDBか検査する。
     *
     * @param fromDatabaseHandle 読み取り可能なSQLiteハンドル。
     * @param fromIsAllowed 許可時true。falseのままの場合は書き込まない。
     * @param fromReason 拒否理由または読み取りエラー。
     * @return 検査を完了した場合true。一時的な読取失敗はfalseとして再試行する。
     */
    static bool inspectM5(
        const int fromDatabaseHandle,
        bool &fromIsAllowed,
        string &fromReason
    ) {
        fromIsAllowed = false;
        fromReason = "";
        if (fromDatabaseHandle == INVALID_HANDLE) {
            fromReason = "DATABASE_READ_ERROR: INVALID_HANDLE";
            return false;
        }

        string schemaText = "";
        int objectCount = 0;
        if (!readSchema(fromDatabaseHandle, schemaText, objectCount, fromReason)) {
            return false;
        }
        if (objectCount == 0) {
            fromIsAllowed = true;
            return true;
        }

        string schemaHash = hashText(schemaText);
        if (schemaHash == "") {
            fromReason = "DATABASE_READ_ERROR: schema hash failed";
            return false;
        }
        if (schemaHash != getSupportedSchemaHash()) {
            fromReason = "M5_DATABASE_REJECTED: unsupported or incomplete schema";
            return true;
        }

        string sql = "SELECT EXISTS(SELECT 1 FROM zigzag_elliot_alert_runs ";
        sql += "WHERE strategy <> 'M5_OBSERVATION_ALL' ";
        sql += "OR strategy_version <> 'M5_OBSERVATION_ALL_V1' ";
        sql += "OR schema_version <> 1 ";
        sql += "OR source_mode NOT IN ('LIVE', 'TESTER') ";
        sql += "OR substr(analysis_input_text, 1, 26) <> 'M5_OBSERVATION_PROFILE_V1|' ";
        sql += "OR analysis_version = '' OR length(analysis_input_hash) <> 64)";
        long hasForeignRun = 0;
        if (!readScalar(fromDatabaseHandle, sql, hasForeignRun, fromReason)) {
            return false;
        }
        if (hasForeignRun != 0) {
            fromReason = "M5_DATABASE_REJECTED: foreign or unsupported Run";
            return true;
        }

        sql = "SELECT EXISTS(SELECT 1 FROM zigzag_elliot_observations observation ";
        sql += "LEFT JOIN zigzag_elliot_alert_runs run ON run.id = observation.run_id ";
        sql += "WHERE observation.anchor_time_frame <> 5 ";
        sql += "OR observation.anchor_time_frame_text <> 'M5' ";
        sql += "OR observation.time_frame_count <> 7 ";
        sql += "OR observation.capture_phase <> 'BAR_OPEN_FIRST_SUCCESS' ";
        sql += "OR observation.pip_size IS NULL OR observation.pip_size <= 0 ";
        sql += "OR observation.spread_pips IS NULL ";
        sql += "OR run.id IS NULL ";
        sql += "OR observation.source_mode <> run.source_mode ";
        sql += "OR observation.source_server <> run.source_server ";
        sql += "OR observation.analysis_version <> run.analysis_version ";
        sql += "OR observation.analysis_input_hash <> run.analysis_input_hash)";
        long hasForeignObservation = 0;
        if (!readScalar(fromDatabaseHandle, sql, hasForeignObservation, fromReason)) {
            return false;
        }
        if (hasForeignObservation != 0) {
            fromReason = "M5_DATABASE_REJECTED: foreign or inconsistent observation";
            return true;
        }

        fromIsAllowed = true;
        return true;
    }

    /**
     * 初版M5専用DBの完全な物理スキーマ識別値を取得する。
     *
     * 4テーブル・14明示索引のsqlite_masterを正規化してSHA-256化する。
     * CHECK・FK・UNIQUE・DEFAULT・余分なトリガー等も検査対象とする。
     * 既存DAOのDDL変更時は対応スキーマを明示判断して契約テストも更新する。
     *
     * @return 対応スキーマのSHA-256。
     */
    static string getSupportedSchemaHash() {
        return "b2abb5f740fc8d451c6a9d70c408e357c6f51b5fb32cf961df650ff16c1da22a";
    }

private:
    /**
     * SQLite内部オブジェクトを除く定義を順序固定で読み取る。
     */
    static bool readSchema(
        const int fromDatabaseHandle,
        string &fromSchemaText,
        int &fromObjectCount,
        string &fromReason
    ) {
        string sql = "SELECT type, name, COALESCE(sql, '') FROM sqlite_master ";
        sql += "WHERE name NOT GLOB 'sqlite_*' ORDER BY type, name";
        ResetLastError();
        int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);
        if (requestHandle == INVALID_HANDLE) {
            return readError("DatabasePrepare", GetLastError(), fromReason);
        }

        while (true) {
            ResetLastError();
            if (!DatabaseRead(requestHandle)) {
                int errorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                if (errorCode == ERR_DATABASE_NO_MORE_DATA) {
                    return true;
                }
                return readError("DatabaseRead", errorCode, fromReason);
            }

            string objectType = "";
            string objectName = "";
            string definition = "";
            ResetLastError();
            if (!DatabaseColumnText(requestHandle, 0, objectType)
                    || !DatabaseColumnText(requestHandle, 1, objectName)
                    || !DatabaseColumnText(requestHandle, 2, definition)) {
                int errorCode = GetLastError();
                DatabaseFinalize(requestHandle);
                return readError("DatabaseColumnText", errorCode, fromReason);
            }
            fromSchemaText += objectType + ":" + objectName + ":";
            fromSchemaText += normalizeSql(definition) + "\n";
            fromObjectCount++;
        }
    }

    /**
     * SQLの文字列リテラルを保持し、外側の空白と大文字小文字を正規化する。
     *
     * SQLiteが保存するCREATE文はIF NOT EXISTSを除いた形式を正本とする。
     * 空白は1個へ圧縮し、TEXT NOT NULL等のトークン境界を失わない。
     */
    static string normalizeSql(const string fromSql) {
        string normalized = "";
        bool isLiteral = false;
        bool hasPendingSpace = false;
        for (int i = 0; i < StringLen(fromSql); i++) {
            ushort character = StringGetCharacter(fromSql, i);
            string part = StringSubstr(fromSql, i, 1);
            if (character == '\'') {
                if (hasPendingSpace && normalized != "") {
                    normalized += " ";
                }
                hasPendingSpace = false;
                isLiteral = !isLiteral;
                normalized += part;
                continue;
            }
            if (!isLiteral) {
                if (character == ' ' || character == '\t'
                        || character == '\r' || character == '\n') {
                    hasPendingSpace = true;
                    continue;
                }
                if (hasPendingSpace && normalized != "") {
                    normalized += " ";
                }
                hasPendingSpace = false;
                StringToUpper(part);
            }
            normalized += part;
        }
        return normalized;
    }

    /**
     * スキーマのUTF-8文字列を終端NULLを含めずSHA-256へ変換する。
     */
    static string hashText(const string fromText) {
        uchar source[];
        uchar key[];
        uchar digest[];
        int size = StringToCharArray(fromText, source, 0, WHOLE_ARRAY, CP_UTF8);
        if (size <= 1 || ArrayResize(source, size - 1) != size - 1) {
            return "";
        }
        if (CryptEncode(CRYPT_HASH_SHA256, source, key, digest) != 32) {
            return "";
        }
        string result = "";
        for (int i = 0; i < ArraySize(digest); i++) {
            result += StringFormat("%02x", (int)digest[i]);
        }
        return result;
    }

    /**
     * 検査用の整数1行を読み取る。
     */
    static bool readScalar(
        const int fromDatabaseHandle,
        const string fromSql,
        long &fromValue,
        string &fromReason
    ) {
        ResetLastError();
        int requestHandle = DatabasePrepare(fromDatabaseHandle, fromSql);
        if (requestHandle == INVALID_HANDLE) {
            return readError("DatabasePrepare", GetLastError(), fromReason);
        }
        ResetLastError();
        if (!DatabaseRead(requestHandle) || !DatabaseColumnLong(requestHandle, 0, fromValue)) {
            int errorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            return readError("DatabaseRead/ColumnLong", errorCode, fromReason);
        }
        DatabaseFinalize(requestHandle);
        return true;
    }

    /**
     * 読み取り失敗を用途違いと区別して記録する。
     */
    static bool readError(const string fromOperation, const int fromError, string &fromReason) {
        fromReason = StringFormat("DATABASE_READ_ERROR: %s error=%d", fromOperation, fromError);
        Logger logger;
        logger.setLevel(LOG_INFO);
        logger.error(__FUNCTION__, fromReason);
        return false;
    }
};

#endif // MSTNG_ZZE_OBSERVATION_DATABASE_GUARD_MQH
