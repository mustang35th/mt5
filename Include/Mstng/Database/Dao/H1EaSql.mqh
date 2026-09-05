#ifndef MSTNG_DATABASE_DAO_H1_EA_SQL_MQH
#define MSTNG_DATABASE_DAO_H1_EA_SQL_MQH

/**
 * H1 EA専用SQLの値表現と読み取りを統一する。
 */
class H1EaSql {
public:
    /**
     * SQLite文字列リテラルを生成する。
     */
    static string text(const string fromText) {
        string escaped = fromText;
        StringReplace(escaped, "'", "''");
        return "'" + escaped + "'";
    }

    /**
     * 未取得の文字列をNULLとして保存する。
     */
    static string optionalText(const string fromText) {
        if (fromText == "") {
            return "NULL";
        }
        return H1EaSql::text(fromText);
    }

    /**
     * 未取得の正整数をNULLとして保存する。
     */
    static string optionalLong(const long fromNumber, const long fromNull = 0) {
        if (fromNumber == fromNull) {
            return "NULL";
        }
        return IntegerToString(fromNumber);
    }

    /**
     * doubleの有効な0と未取得値を分離する。
     */
    static string real(const double fromNumber, const double fromNull = EMPTY_VALUE) {
        if (fromNumber == fromNull || !MathIsValidNumber(fromNumber)) {
            return "NULL";
        }
        return StringFormat("%.17g", fromNumber);
    }

    /**
     * 一行一列の整数を取得する。
     */
    static bool scalar(const int fromHandle, const string fromSql, long &fromResult) {
        int request = DatabasePrepare(fromHandle, fromSql);
        if (request == INVALID_HANDLE) {
            return false;
        }
        bool success = DatabaseRead(request) && DatabaseColumnLong(request, 0, fromResult);
        DatabaseFinalize(request);
        return success;
    }

    /**
     * 任意件数のSQLを実行する。
     */
    static bool execute(const int fromHandle, const string fromSql) {
        ResetLastError();
        return DatabaseExecute(fromHandle, fromSql);
    }

    /**
     * 採番後の回復snapshotをUTF-8 SHA-256へ変換する。
     */
    static string hash(const string fromText) {
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
     * SHA-256の小文字64桁表現を検証する。
     */
    static bool isHash(const string fromHash) {
        if (StringLen(fromHash) != 64) {
            return false;
        }
        for (int i = 0; i < StringLen(fromHash); i++) {
            ushort character = StringGetCharacter(fromHash, i);
            if ((character < '0' || character > '9')
                    && (character < 'a' || character > 'f')) {
                return false;
            }
        }
        return true;
    }
};

#endif
