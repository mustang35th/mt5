#ifndef MSTNG_UTIL_TEXT_HASH_UTIL_MQH
#define MSTNG_UTIL_TEXT_HASH_UTIL_MQH

/**
 * 文字列の比較用ハッシュを生成するユーティリティクラス。
 */
class TextHashUtil {
public:
    /**
     * MQL5文字列のUTF-16コード単位からFNV-1aハッシュを作成する。
     * 既存の設定ハッシュとの互換性を保つため、文字列をバイト列へ変換しない。
     *
     * @param fromText 対象文字列
     * @return 符号なし64bit整数の10進文字列
     */
    static string createFnv1a64(const string fromText) {
        ulong hashValue = 14695981039346656037;

        for (int i = 0; i < StringLen(fromText); i++) {
            hashValue ^= (ulong)StringGetCharacter(fromText, i);
            hashValue *= 1099511628211;
        }

        return StringFormat("%I64u", hashValue);
    }
};

#endif
