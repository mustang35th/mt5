//+------------------------------------------------------------------+
//|                                                TimeJapanUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __TIME_JAPAN_UTIL_MQH__
#define __TIME_JAPAN_UTIL_MQH__

/**
 * 日本時間ユーティリティ。
 */
class TimeJapanUtil {
public:
    /**
     * サーバー時刻を日本時間へ変換します。
     *
     * @param fromDatetimeValue サーバー時刻
     * @return 日本時間
     */
    static datetime getJapanTime(const datetime fromDatetimeValue) {
        // JST差分時間取得
        int jstOffsetHour = TimeJapanUtil::getJstOffsetHour(fromDatetimeValue);

        // 秒変換
        int offsetSeconds = jstOffsetHour * 60 * 60;

        return fromDatetimeValue + offsetSeconds;
    }

    /**
     * JSTとの差分時間（時間）を取得します。
     *
     * @param fromDatetimeValue サーバー時刻
     * @return JST差分時間（時間）
     */
    static int getJstOffsetHour(const datetime fromDatetimeValue) {
        // 夏時間判定
        bool isSummer = TimeJapanUtil::isSummerTime(fromDatetimeValue);

        if (isSummer) {
            return 6;
        }

        return 7;
    }

    /**
     * 指定時間帯かどうかを判定します。
     *
     * @param fromDatetimeValue サーバー時刻
     * @return true の場合、指定時間帯
     */
    static bool isTimeRange(const datetime fromDatetimeValue) {
        // 日本時間取得
        datetime fromTime = TimeJapanUtil::getJapanTime(fromDatetimeValue);

        MqlDateTime time;
        TimeToStruct(fromTime, time);

        if (
            time.hour >= 6
            && time.hour < 8
        ) {
            return true;
        }

        return false;
    }

private:
    /**
     * 夏時間かを判定します。
     *
     * @param fromDatetimeValue サーバー時刻
     * @return 夏時間期間内であれば true
     */
    static bool isSummerTime(const datetime fromDatetimeValue) {
        // 年取得
        MqlDateTime dateTime;
        TimeToStruct(fromDatetimeValue, dateTime);

        int year = dateTime.year;

        // 夏時間期間取得
        datetime dstStart = TimeJapanUtil::getDstStartDatetime(year);
        datetime dstEnd = TimeJapanUtil::getDstEndDatetime(year) + 86399;

        if (
            dstStart <= fromDatetimeValue
            && fromDatetimeValue <= dstEnd
        ) {
            return true;
        }

        return false;
    }

    /**
     * 指定年月の第 n 曜日を取得します。
     *
     * @param yearValue 年
     * @param monthValue 月
     * @param weekdayValue 曜日
     * @param nthValue 第 n
     * @return 日付（1〜31）
     */
    static int getNthWeekdayOfMonth(
        const int yearValue,
        const int monthValue,
        const int weekdayValue,
        const int nthValue
    ) {
        // 月初取得
        datetime first = StringToTime(
            StringFormat(
                "%04d.%02d.01 00:00:00",
                yearValue,
                monthValue
            )
        );

        MqlDateTime dateTime;
        TimeToStruct(first, dateTime);

        // 日付計算
        int firstDow = dateTime.day_of_week;
        int offset = (7 + weekdayValue - firstDow) % 7;

        return 1 + offset + 7 * (nthValue - 1);
    }

    /**
     * 夏時間開始日時を取得します。
     *
     * @param yearValue 年
     * @return 夏時間開始日時
     */
    static datetime getDstStartDatetime(const int yearValue) {
        // 3月第2日曜取得
        int day = TimeJapanUtil::getNthWeekdayOfMonth(yearValue, 3, 0, 2);

        return StringToTime(
            StringFormat(
                "%04d.%02d.%02d 00:00:00",
                yearValue,
                3,
                day
            )
        );
    }

    /**
     * 夏時間終了日時を取得します。
     *
     * @param yearValue 年
     * @return 夏時間終了日時
     */
    static datetime getDstEndDatetime(const int yearValue) {
        // 11月第1日曜取得
        int day = TimeJapanUtil::getNthWeekdayOfMonth(yearValue, 11, 0, 1);

        return StringToTime(
            StringFormat(
                "%04d.%02d.%02d 00:00:00",
                yearValue,
                11,
                day
            )
        );
    }
};

#endif
