//+------------------------------------------------------------------+
//|                 CurrencyStrengthDatabaseFileResolver.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_DATABASE_FILE_RESOLVER_MQH
#define MSTNG_CURRENCY_STRENGTH_DATABASE_FILE_RESOLVER_MQH

/**
 * 通貨強弱データベースの年別ファイル名を解決するクラス。
 */
class CurrencyStrengthDatabaseFileResolver {
public:
    /**
     * M5バー時刻に対応するデータベースファイル名を解決する。
     *
     * @param fromBaseFileName 年を付与する前のファイル名。
     * @param fromSplitByYear 年単位で分割する場合true。
     * @param fromM5BarTime 保存対象のM5バー時刻。
     * @param fromResolvedFileName 解決したファイル名の格納先。
     * @return 解決に成功した場合true。
     */
    static bool resolveFileName(
        const string fromBaseFileName,
        const bool fromSplitByYear,
        const datetime fromM5BarTime,
        string &fromResolvedFileName
    ) {
        fromResolvedFileName = "";

        if (fromBaseFileName == "") {
            return false;
        }

        if (!fromSplitByYear) {
            fromResolvedFileName = fromBaseFileName;

            return true;
        }

        MqlDateTime dateTime;

        if (fromM5BarTime <= 0 || !TimeToStruct(fromM5BarTime, dateTime)) {
            return false;
        }

        return resolveFileNameForYear(
            fromBaseFileName,
            dateTime.year,
            fromResolvedFileName
        );
    }

    /**
     * 指定年に対応するデータベースファイル名を解決する。
     *
     * @param fromBaseFileName 年を付与する前のファイル名。
     * @param fromYear 保存対象年。
     * @param fromResolvedFileName 解決したファイル名の格納先。
     * @return 解決に成功した場合true。
     */
    static bool resolveFileNameForYear(
        const string fromBaseFileName,
        const int fromYear,
        string &fromResolvedFileName
    ) {
        fromResolvedFileName = "";

        if (fromBaseFileName == "" || fromYear < 1970) {
            return false;
        }

        int separatorPosition = findLastSeparatorPosition(fromBaseFileName);
        int extensionPosition = findLastCharacterPosition(
            fromBaseFileName,
            "."
        );
        string yearSuffix = StringFormat("-%04d", fromYear);

        if (extensionPosition > separatorPosition) {
            fromResolvedFileName = StringSubstr(
                fromBaseFileName,
                0,
                extensionPosition
            ) + yearSuffix + StringSubstr(
                fromBaseFileName,
                extensionPosition
            );
        } else {
            fromResolvedFileName = fromBaseFileName + yearSuffix;
        }

        return true;
    }

    /**
     * 日時から西暦年を取得する。
     *
     * @param fromTime 対象日時。
     * @return 西暦年。取得できない場合は0。
     */
    static int getYear(const datetime fromTime) {
        MqlDateTime dateTime;

        if (fromTime <= 0 || !TimeToStruct(fromTime, dateTime)) {
            return 0;
        }

        return dateTime.year;
    }

private:
    /**
     * 最後に出現するフォルダ区切り位置を取得する。
     *
     * @param fromText 検索対象文字列。
     * @return 区切り位置。存在しない場合は-1。
     */
    static int findLastSeparatorPosition(const string fromText) {
        int backslashPosition = findLastCharacterPosition(fromText, "\\");
        int slashPosition = findLastCharacterPosition(fromText, "/");

        if (backslashPosition > slashPosition) {
            return backslashPosition;
        }

        return slashPosition;
    }

    /**
     * 指定文字列が最後に出現する位置を取得する。
     *
     * @param fromText 検索対象文字列。
     * @param fromSearchText 検索文字列。
     * @return 最後の出現位置。存在しない場合は-1。
     */
    static int findLastCharacterPosition(
        const string fromText,
        const string fromSearchText
    ) {
        int lastPosition = -1;
        int searchPosition = StringFind(fromText, fromSearchText);

        while (searchPosition >= 0) {
            lastPosition = searchPosition;
            searchPosition = StringFind(
                fromText,
                fromSearchText,
                searchPosition + 1
            );
        }

        return lastPosition;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_DATABASE_FILE_RESOLVER_MQH
