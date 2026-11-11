//+------------------------------------------------------------------+
//|                                 EconomicCalendarScheduleInfo.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_CALENDAR_ECONOMIC_CALENDAR_SCHEDULE_INFO_MQH
#define MSTNG_CALENDAR_ECONOMIC_CALENDAR_SCHEDULE_INFO_MQH

/**
 * 経済指標予定の表示に必要な値を保持する。
 * 終日・時刻未定の予定はjapanTimeを0とし、JSTの日時を断定しない。
 */
struct EconomicCalendarScheduleInfo {
    /** カレンダーの発表値ID。 */
    ulong valueId;

    /** カレンダーが返したサーバー日時。 */
    datetime serverTime;

    /** 確定時刻をJSTへ変換した日時。未確定時刻は0。 */
    datetime japanTime;

    /** 対象通貨。 */
    string currency;

    /** 対象国または地域の名称。 */
    string country;

    /** ターミナル言語での指標名。 */
    string name;

    /** 指標の重要度。 */
    ENUM_CALENDAR_EVENT_IMPORTANCE importance;

    /** 時刻確定・終日・時刻未定などの区分。 */
    ENUM_CALENDAR_EVENT_TIMEMODE timeMode;

    /** 倍率・単位付き予想値。欠損はダッシュ。 */
    string forecastText;

    /** 倍率・単位付き前回値。改定値を使用した場合は改定表示付き。 */
    string previousText;
};

#endif // MSTNG_CALENDAR_ECONOMIC_CALENDAR_SCHEDULE_INFO_MQH
