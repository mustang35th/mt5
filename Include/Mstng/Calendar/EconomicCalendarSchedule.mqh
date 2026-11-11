//+------------------------------------------------------------------+
//|                                     EconomicCalendarSchedule.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_CALENDAR_ECONOMIC_CALENDAR_SCHEDULE_MQH
#define MSTNG_CALENDAR_ECONOMIC_CALENDAR_SCHEDULE_MQH

#include <Mstng\Calendar\EconomicCalendarScheduleInfo.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 通常チャート用の主要8通貨・中重要度以上の経済指標予定と祝日を取得する。
 * 取得は完了から5分間隔とし、失敗時には最後の正常な一覧を維持する。
 */
class EconomicCalendarSchedule {
public:
    /**
     * 未取得状態で初期化する。構築時にはカレンダーへ問い合わせない。
     */
    EconomicCalendarSchedule() {
        this.snapshotAvailable = false;
        this.requestFailed = false;
        this.requestAttempted = false;
        this.lastAttemptTick = 0;
        this.lastErrorCode = 0;
        this.updatedAt = 0;
        this.metadataDay = 0;
        this.timeOffsetAvailable = false;
        this.serverGmtOffsetSeconds = 0;
    }

    /**
     * 当日0時から今後24時間までの予定を取得し、全件成功時だけ一覧を入れ替える。
     * 祝日以外の低重要度・対象外通貨は保持しない。祝日・終日・未定は当日分も取得する。
     * テスターでは取得しない。5分以内の再呼出しは直近の取得成否を返す。
     *
     * @return 正常な一覧を取得済みで、直近の取得が失敗していなければtrue。
     */
    bool update() {
        if (Util::isStrategyTester()) {
            return false;
        }

        ulong currentTick = GetTickCount64();
        if (this.requestAttempted && currentTick >= this.lastAttemptTick
                && currentTick - this.lastAttemptTick < 300000) {
            return this.snapshotAvailable && !this.requestFailed;
        }

        this.requestAttempted = true;
        this.lastAttemptTick = currentTick;
        datetime serverNow = this.getServerNow();
        datetime gmtNow = TimeGMT();
        if (serverNow <= 0 || gmtNow <= 0) {
            return this.failUpdate(ERR_INTERNAL_ERROR);
        }

        long offsetSeconds = (long)MathRound((double)(serverNow - gmtNow) / 60.0) * 60;
        if (offsetSeconds < -86400 || offsetSeconds > 86400) {
            return this.failUpdate(ERR_INTERNAL_ERROR);
        }

        datetime startDay = this.getDayStart(serverNow);
        if (startDay != this.metadataDay) {
            ArrayResize(this.events, 0);
            ArrayResize(this.countries, 0);
            this.metadataDay = startDay;
        }

        MqlCalendarValue values[];
        ResetLastError();
        int total = CalendarValueHistory(values, startDay, serverNow + 86400);
        int queryError = GetLastError();
        if (total < 0 || queryError != 0) {
            return this.failUpdate(queryError);
        }

        if (total != ArraySize(values)) {
            return this.failUpdate(ERR_CALENDAR_MORE_DATA);
        }

        EconomicCalendarScheduleInfo nextRows[];
        if (ArrayResize(nextRows, total) != total) {
            return this.failUpdate(ERR_NOT_ENOUGH_MEMORY);
        }

        int count = 0;
        for (int i = 0; i < total; i++) {
            int eventIndex = this.getEventIndex(values[i].event_id);
            if (eventIndex < 0) {
                return false;
            }

            bool isHoliday = this.events[eventIndex].type == CALENDAR_TYPE_HOLIDAY;
            if (!isHoliday && this.events[eventIndex].importance < CALENDAR_IMPORTANCE_MODERATE) {
                continue;
            }

            if (!isHoliday && (this.events[eventIndex].time_mode == CALENDAR_TIMEMODE_NOTIME
                    || this.events[eventIndex].time_mode == CALENDAR_TIMEMODE_TENTATIVE)
                    && values[i].HasActualValue()) {
                continue;
            }

            int countryIndex = this.getCountryIndex(this.events[eventIndex].country_id);
            if (countryIndex < 0) {
                return false;
            }

            if (!this.isTargetCurrency(this.countries[countryIndex].currency)) {
                continue;
            }

            this.fillRow(values[i], this.events[eventIndex], this.countries[countryIndex],
                offsetSeconds, nextRows[count]);
            if (this.isVisible(nextRows[count], true, serverNow, true)) {
                count++;
            }
        }

        if (ArrayResize(nextRows, count) != count) {
            return this.failUpdate(ERR_NOT_ENOUGH_MEMORY);
        }

        this.sortRows(nextRows);
        if (!ArraySwap(this.rows, nextRows)) {
            return this.failUpdate(ERR_INTERNAL_ERROR);
        }

        this.serverGmtOffsetSeconds = offsetSeconds;
        this.timeOffsetAvailable = true;
        this.updatedAt = serverNow;
        this.snapshotAvailable = true;
        this.requestFailed = false;
        this.lastErrorCode = 0;
        this.lastAttemptTick = GetTickCount64();

        return true;
    }

    /**
     * 保持済み一覧から、現在も表示対象の予定件数を取得する。
     *
     * @param fromIncludeModerate 中重要度も含める場合true。
     * @param fromNow 現在のサーバー日時。
     * @param fromIncludeHolidays 重要度に依存せず祝日を含める場合true。
     */
    int getCount(const bool fromIncludeModerate, const datetime fromNow,
            const bool fromIncludeHolidays = false) {
        int count = 0;
        for (int i = 0; i < ArraySize(this.rows); i++) {
            if (this.isVisible(this.rows[i], fromIncludeModerate, fromNow, fromIncludeHolidays)) {
                count++;
            }
        }

        return count;
    }

    /**
     * 当日祝日を先頭に、残りを時刻順で指定行から取得する。
     * 現在の日付で優先対象を選ぶため、再取得前に日付が変わっても順序を更新する。
     *
     * @param fromIndex 表示対象内での0始まりの行番号。
     * @param fromIncludeModerate 中重要度も含める場合true。
     * @param fromNow 現在のサーバー日時。
     * @param fromInfo 取得行。
     * @param fromIncludeHolidays 重要度に依存せず祝日を含める場合true。
     * @return 指定行が存在する場合true。
     */
    bool get(const int fromIndex, const bool fromIncludeModerate,
            const datetime fromNow, EconomicCalendarScheduleInfo &fromInfo,
            const bool fromIncludeHolidays = false) {
        if (fromIndex < 0) {
            return false;
        }

        int firstPass = 1;
        if (fromIncludeHolidays) {
            firstPass = 0;
        }

        datetime currentDay = this.getDayStart(fromNow);
        int index = 0;
        for (int pass = firstPass; pass < 2; pass++) {
            for (int i = 0; i < ArraySize(this.rows); i++) {
                if (!this.isVisible(this.rows[i], fromIncludeModerate, fromNow, fromIncludeHolidays)) {
                    continue;
                }

                bool isCurrentHoliday = this.rows[i].isHoliday
                    && this.getDayStart(this.rows[i].serverTime) == currentDay;
                if ((pass == 0) != isCurrentHoliday) {
                    continue;
                }

                if (index == fromIndex) {
                    fromInfo = this.rows[i];
                    if (!fromInfo.isHoliday && fromInfo.timeMode == CALENDAR_TIMEMODE_DATETIME) {
                        fromInfo.japanTime = this.getJapanTime(fromInfo.serverTime);
                    }

                    return true;
                }

                index++;
            }
        }

        return false;
    }

    /**
     * 現在の推定サーバー日時を返す。最後のTick時刻への置き換えは行わない。
     */
    datetime getServerNow() { return TimeTradeServer(); }

    /**
     * 正常な一覧を最後に取得したサーバー日時を返す。未取得の場合は0。
     */
    datetime getUpdatedAt() { return this.updatedAt; }

    /**
     * 取得時のサーバー対UTC差を使用して、確定時刻をJSTへ変換する。
     *
     * @param fromServerTime 変換対象の確定サーバー日時。
     * @return 日本日時。時差未取得または不正日時の場合は0。
     */
    datetime getJapanTime(const datetime fromServerTime) {
        if (!this.timeOffsetAvailable || fromServerTime <= 0) {
            return 0;
        }

        return (datetime)(fromServerTime - this.serverGmtOffsetSeconds + 9 * 3600);
    }

    /**
     * 0件を含め、正常な一覧を一度でも取得したかを返す。
     */
    bool hasSnapshot() { return this.snapshotAvailable; }

    /**
     * 直近の問い合わせが失敗したかを返す。
     */
    bool hasError() { return this.requestFailed; }

    /**
     * 直近の取得失敗コードを返す。正常取得後・未取得時は0。
     */
    int getLastError() { return this.lastErrorCode; }

private:
    /** 最後に正常取得した予定。 */
    EconomicCalendarScheduleInfo rows[];

    /** 当日中に取得したイベント定義。 */
    MqlCalendarEvent events[];

    /** 当日中に取得した国定義。 */
    MqlCalendarCountry countries[];

    /** 正常取得済みか。0件成功も含む。 */
    bool snapshotAvailable;

    /** 直近の取得失敗状態。 */
    bool requestFailed;

    /** 問い合わせを試行済みか。 */
    bool requestAttempted;

    /** 直近の問い合わせ完了時刻。単調増加ミリ秒。 */
    ulong lastAttemptTick;

    /** 直近の取得失敗コード。 */
    int lastErrorCode;

    /** 最後の正常取得時のサーバー日時。 */
    datetime updatedAt;

    /** イベント・国のキャッシュを取得したサーバー日。 */
    datetime metadataDay;

    /** サーバー対UTC差を取得済みか。 */
    bool timeOffsetAvailable;

    /** 分単位へ丸めたサーバー対UTC差。単位は秒。 */
    long serverGmtOffsetSeconds;

    /**
     * 既存一覧を維持して失敗を記録し、5分後に再試行できるようにする。
     */
    bool failUpdate(const int fromError) {
        this.requestFailed = true;
        this.lastErrorCode = fromError;
        if (this.lastErrorCode == 0) {
            this.lastErrorCode = ERR_INTERNAL_ERROR;
        }

        this.lastAttemptTick = GetTickCount64();

        return false;
    }

    /**
     * イベント定義を再利用し、未取得のIDだけ問い合わせる。
     */
    int getEventIndex(const ulong fromId) {
        int count = ArraySize(this.events);
        for (int i = 0; i < count; i++) {
            if (this.events[i].id == fromId) {
                return i;
            }
        }

        MqlCalendarEvent event;
        ResetLastError();
        if (!CalendarEventById(fromId, event)) {
            this.failUpdate(GetLastError());

            return -1;
        }

        if (ArrayResize(this.events, count + 1, 64) != count + 1) {
            this.failUpdate(ERR_NOT_ENOUGH_MEMORY);

            return -1;
        }

        this.events[count] = event;

        return count;
    }

    /**
     * 国定義を再利用し、未取得のIDだけ問い合わせる。
     */
    int getCountryIndex(const ulong fromId) {
        int count = ArraySize(this.countries);
        for (int i = 0; i < count; i++) {
            if (this.countries[i].id == fromId) {
                return i;
            }
        }

        MqlCalendarCountry country;
        ResetLastError();
        if (!CalendarCountryById(fromId, country)) {
            this.failUpdate(GetLastError());

            return -1;
        }

        if (ArrayResize(this.countries, count + 1, 32) != count + 1) {
            this.failUpdate(ERR_NOT_ENOUGH_MEMORY);

            return -1;
        }

        this.countries[count] = country;

        return count;
    }

    /**
     * 主要8通貨に含まれるかを返す。
     */
    bool isTargetCurrency(const string fromCurrency) {
        return fromCurrency == "USD" || fromCurrency == "JPY" || fromCurrency == "EUR"
            || fromCurrency == "GBP" || fromCurrency == "AUD" || fromCurrency == "NZD"
            || fromCurrency == "CAD" || fromCurrency == "CHF";
    }

    /**
     * 指定日時が属するサーバー日の0時を返す。
     */
    datetime getDayStart(const datetime fromTime) {
        return (datetime)(fromTime - (long)fromTime % 86400);
    }

    /**
     * 重要度と経過時間による表示条件を判定する。
     * 祝日・時刻未確定の予定はサーバー日の終わりまで保持する。
     */
    bool isVisible(const EconomicCalendarScheduleInfo &fromInfo,
            const bool fromIncludeModerate, const datetime fromNow,
            const bool fromIncludeHolidays) {
        if (fromNow <= 0 || fromInfo.serverTime <= 0
                || fromInfo.serverTime >= fromNow + 86400) {
            return false;
        }

        if (fromInfo.isHoliday) {
            return fromIncludeHolidays
                && this.getDayStart(fromInfo.serverTime) >= this.getDayStart(fromNow);
        }

        if (fromInfo.importance != CALENDAR_IMPORTANCE_HIGH
                && (!fromIncludeModerate || fromInfo.importance != CALENDAR_IMPORTANCE_MODERATE)) {
            return false;
        }

        if (fromInfo.timeMode == CALENDAR_TIMEMODE_DATETIME) {
            return fromInfo.serverTime >= fromNow;
        }

        return this.getDayStart(fromInfo.serverTime) >= this.getDayStart(fromNow);
    }

    /**
     * ネイティブ値を表示用の1行へ変換する。
     */
    void fillRow(const MqlCalendarValue &fromValue, const MqlCalendarEvent &fromEvent,
            const MqlCalendarCountry &fromCountry, const long fromOffsetSeconds,
            EconomicCalendarScheduleInfo &fromInfo) {
        fromInfo.valueId = fromValue.id;
        fromInfo.serverTime = fromValue.time;
        fromInfo.japanTime = 0;
        fromInfo.currency = fromCountry.currency;
        fromInfo.country = fromCountry.name;
        fromInfo.name = fromEvent.name;
        fromInfo.importance = fromEvent.importance;
        fromInfo.timeMode = fromEvent.time_mode;
        fromInfo.isHoliday = fromEvent.type == CALENDAR_TYPE_HOLIDAY;
        if (fromInfo.isHoliday) {
            fromInfo.forecastText = "";
            fromInfo.previousText = "";

            return;
        }

        if (fromInfo.timeMode == CALENDAR_TIMEMODE_DATETIME) {
            fromInfo.japanTime = (datetime)(fromInfo.serverTime - fromOffsetSeconds + 9 * 3600);
        }

        fromInfo.forecastText = "—";
        if (fromValue.HasForecastValue()) {
            fromInfo.forecastText = this.formatValue(fromValue.GetForecastValue(), fromEvent, fromCountry.currency);
        }

        fromInfo.previousText = "—";
        if (fromValue.HasRevisedValue()) {
            fromInfo.previousText = this.formatValue(fromValue.GetRevisedValue(), fromEvent, fromCountry.currency) + " (改)";
        } else if (fromValue.HasPreviousValue()) {
            fromInfo.previousText = this.formatValue(fromValue.GetPreviousValue(), fromEvent, fromCountry.currency);
        }
    }

    /**
     * 1e6固定小数の解除済み数値に、定義された表示桁・倍率・単位を付ける。
     */
    string formatValue(const double fromValue, const MqlCalendarEvent &fromEvent,
            const string fromCurrency) {
        if (!MathIsValidNumber(fromValue)) {
            return "—";
        }

        int digits = 16;
        if (fromEvent.digits < 16) {
            digits = (int)fromEvent.digits;
        }

        string multiplier = "";
        switch (fromEvent.multiplier) {
            case CALENDAR_MULTIPLIER_THOUSANDS: multiplier = "千"; break;
            case CALENDAR_MULTIPLIER_MILLIONS: multiplier = "百万"; break;
            case CALENDAR_MULTIPLIER_BILLIONS: multiplier = "十億"; break;
            case CALENDAR_MULTIPLIER_TRILLIONS: multiplier = "兆"; break;
        }

        string unit = "";
        switch (fromEvent.unit) {
            case CALENDAR_UNIT_PERCENT: unit = "%"; break;
            case CALENDAR_UNIT_CURRENCY: unit = fromCurrency; break;
            case CALENDAR_UNIT_HOUR: unit = "時間"; break;
            case CALENDAR_UNIT_JOB: unit = "雇用"; break;
            case CALENDAR_UNIT_RIG: unit = "リグ"; break;
            case CALENDAR_UNIT_USD: unit = "USD"; break;
            case CALENDAR_UNIT_PEOPLE: unit = "人"; break;
            case CALENDAR_UNIT_MORTGAGE: unit = "住宅ローン件"; break;
            case CALENDAR_UNIT_VOTE: unit = "票"; break;
            case CALENDAR_UNIT_BARREL: unit = "バレル"; break;
            case CALENDAR_UNIT_CUBICFEET: unit = "立方フィート"; break;
            case CALENDAR_UNIT_POSITION: unit = "枚"; break;
            case CALENDAR_UNIT_BUILDING: unit = "棟"; break;
        }

        return DoubleToString(fromValue, digits) + multiplier + unit;
    }

    /**
     * 時刻昇順、同時刻なら値ID順に整列する。
     */
    void sortRows(EconomicCalendarScheduleInfo &fromRows[]) {
        for (int i = 1; i < ArraySize(fromRows); i++) {
            EconomicCalendarScheduleInfo current = fromRows[i];
            int position = i - 1;
            while (position >= 0 && (fromRows[position].serverTime > current.serverTime
                    || (fromRows[position].serverTime == current.serverTime
                        && fromRows[position].valueId > current.valueId))) {
                fromRows[position + 1] = fromRows[position];
                position--;
            }

            fromRows[position + 1] = current;
        }
    }
};

#endif // MSTNG_CALENDAR_ECONOMIC_CALENDAR_SCHEDULE_MQH
