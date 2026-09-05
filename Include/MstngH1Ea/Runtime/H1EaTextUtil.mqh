#ifndef MSTNGH1EA_RUNTIME_TEXTUTIL_MQH
#define MSTNGH1EA_RUNTIME_TEXTUTIL_MQH

/**
 * H1 EAの識別子と監査文字列を生成する。
 */
class H1EaTextUtil {
public:
    /**
     * 終端NULLを除くUTF-8文字列のSHA-256を返す。
     */
    static string hash(const string fromText) {
        uchar sourceBytes[];
        int sourceSize = StringToCharArray(fromText, sourceBytes, 0, WHOLE_ARRAY, CP_UTF8);
        if (sourceSize <= 1 || ArrayResize(sourceBytes, sourceSize - 1) != sourceSize - 1) {
            return "";
        }
        uchar keyBytes[];
        uchar resultBytes[];
        if (CryptEncode(CRYPT_HASH_SHA256, sourceBytes, keyBytes, resultBytes) != 32) {
            return "";
        }
        string result = "";
        for (int i = 0; i < ArraySize(resultBytes); i++) {
            result += StringFormat("%02x", (int)resultBytes[i]);
        }
        return result;
    }

    /**
     * 区切り文字を値が含んでも曖昧にならないフィールドを追加する。
     */
    static void appendField(string &fromText, const string fromName, const string fromValue) {
        uchar valueBytes[];
        int byteCount = StringToCharArray(fromValue, valueBytes, 0, WHOLE_ARRAY, CP_UTF8) - 1;
        fromText += "|" + fromName + "#" + IntegerToString(byteCount) + "=" + fromValue;
    }

    /**
     * ticketを符号なし10進文字列へ変換する。
     */
    static string ticket(const ulong fromTicket) {
        return StringFormat("%I64u", fromTicket);
    }

    /**
     * TEXTのticketを符号付きlongを経由せず読み戻す。不正値は0。
     */
    static ulong parseTicket(const string fromText) {
        int length = StringLen(fromText);
        if (length == 0 || length > 20) {
            return 0;
        }
        ulong result = 0;
        for (int i = 0; i < length; i++) {
            ushort character = StringGetCharacter(fromText, i);
            if (character < '0' || character > '9') {
                return 0;
            }
            ulong number = (ulong)(character - '0');
            if (result > (ULONG_MAX - number) / 10) {
                return 0;
            }
            result = result * 10 + number;
        }
        return result;
    }
};

#endif
