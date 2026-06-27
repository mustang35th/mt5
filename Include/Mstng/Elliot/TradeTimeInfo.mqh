//+------------------------------------------------------------------+
//|                                                TradeTimeInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Util\TimeJapanUtil.mqh>

/**
 * 取引セッション種別
 */
enum SessionType {
    sessionUnknown = 0,        // 未判定
    sessionTokyo = 1,          // 東京
    sessionLondon = 2,         // ロンドン
    sessionNewYork = 3,        // ニューヨーク
    sessionTokyoLondon = 4,    // 東京ロンドン重複
    sessionLondonNewYork = 5,  // ロンドンニューヨーク重複
    sessionOther = 6           // その他
};

/**
 * 取引時間情報
 */
class TradeTimeInfo {
public:
    /** サーバー時間 */
    datetime serverTime;

    /** 日本時間 */
    datetime jstTime;

    /** JST差分時間 */
    int jstOffsetHour;

    /** サーバー時間の時 */
    int serverHour;

    /** サーバー時間の分 */
    int serverMinute;

    /** 日本時間の時 */
    int jstHour;

    /** 日本時間の分 */
    int jstMinute;

    /** 曜日 */
    int dayOfWeek;

    /** 取引セッション種別 */
    SessionType sessionType;

    /** 東京時間 */
    bool isTokyoSession;

    /** ロンドン時間 */
    bool isLondonSession;

    /** ニューヨーク時間 */
    bool isNewYorkSession;

    /** ロンドンニューヨーク重複時間 */
    bool isLondonNewYorkOverlap;

    /** ロールオーバー時間 */
    bool isRolloverTime;

    /** 月曜早朝 */
    bool isMondayEarly;

    /** 金曜深夜 */
    bool isFridayLate;

    /**
     * コンストラクタ
     */
    TradeTimeInfo() {
        // 初期化
        this.clear();
    }

    /**
     * 初期化
     */
    void clear() {
        // 時刻初期化
        this.serverTime = 0;
        this.jstTime = 0;
        this.jstOffsetHour = 0;

        // 時分初期化
        this.serverHour = 0;
        this.serverMinute = 0;
        this.jstHour = 0;
        this.jstMinute = 0;
        this.dayOfWeek = 0;

        // セッション初期化
        this.sessionType = sessionUnknown;
        this.isTokyoSession = false;
        this.isLondonSession = false;
        this.isNewYorkSession = false;
        this.isLondonNewYorkOverlap = false;

        // 取引禁止時間初期化
        this.isRolloverTime = false;
        this.isMondayEarly = false;
        this.isFridayLate = false;
    }

    /**
     * データ設定
     *
     * @param serverTimeValue サーバー時刻
     */
    void setData(const datetime serverTimeValue) {
        // 初期化
        this.clear();

        // 時刻設定
        this.serverTime = serverTimeValue;
        this.jstOffsetHour = TimeJapanUtil::getJstOffsetHour(serverTimeValue);
        this.jstTime = TimeJapanUtil::getJapanTime(serverTimeValue);

        // サーバー時刻分解
        MqlDateTime serverDateTime;
        TimeToStruct(this.serverTime, serverDateTime);

        this.serverHour = serverDateTime.hour;
        this.serverMinute = serverDateTime.min;

        // 日本時刻分解
        MqlDateTime jstDateTime;
        TimeToStruct(this.jstTime, jstDateTime);

        this.jstHour = jstDateTime.hour;
        this.jstMinute = jstDateTime.min;
        this.dayOfWeek = jstDateTime.day_of_week;

        // 取引禁止時間判定
        this.isRolloverTime = this.isRolloverTimeRange();
        this.isMondayEarly = this.isMondayEarlyTime();
        this.isFridayLate = this.isFridayLateTime();

        // 週末セッション除外
        if (this.isWeekendSessionBlockedTime()) {
            this.sessionType = sessionOther;

            return;
        }

        // セッション判定
        this.isTokyoSession = this.isTokyoSessionTime();
        this.isLondonSession = this.isLondonSessionTime();
        this.isNewYorkSession = this.isNewYorkSessionTime();
        this.isLondonNewYorkOverlap = this.isLondonNewYorkOverlapTime();
        this.sessionType = this.resolveSessionType();
    }

    /**
     * 取引可能時間か判定
     *
     * @return true: 取引可能
     */
    bool isTradableTime() {
        if (this.isRolloverTime) {
            return false;
        }

        if (this.isMondayEarly) {
            return false;
        }

        if (this.isFridayLate) {
            return false;
        }

        if (this.sessionType == sessionUnknown) {
            return false;
        }

        if (this.sessionType == sessionOther) {
            return false;
        }

        return true;
    }

    /**
     * セッション名を取得
     *
     * @return セッション名
     */
    string getSessionName() {
        switch (this.sessionType) {
            case sessionTokyo:
                return "Tokyo";

            case sessionLondon:
                return "London";

            case sessionNewYork:
                return "NewYork";

            case sessionTokyoLondon:
                return "TokyoLondon";

            case sessionLondonNewYork:
                return "LondonNewYork";

            case sessionOther:
                return "Other";

            case sessionUnknown:
            default:
                return "Unknown";
        }
    }

    /**
     * CSVヘッダーを取得
     *
     * @return CSVヘッダー
     */
    static string getCsvHeader() {
        return "ServerTime"
            + ",JstTime"
            + ",JstOffsetHour"
            + ",ServerHour"
            + ",ServerMinute"
            + ",JstHour"
            + ",JstMinute"
            + ",DayOfWeek"
            + ",SessionType"
            + ",IsTokyoSession"
            + ",IsLondonSession"
            + ",IsNewYorkSession"
            + ",IsLondonNewYorkOverlap"
            + ",IsRolloverTime"
            + ",IsMondayEarly"
            + ",IsFridayLate";
    }

    /**
     * CSVデータを取得
     *
     * @return CSVデータ
     */
    string getCsvData() {
        return TimeToString(this.serverTime, TIME_DATE | TIME_SECONDS)
            + "," + TimeToString(this.jstTime, TIME_DATE | TIME_SECONDS)
            + "," + IntegerToString(this.jstOffsetHour)
            + "," + IntegerToString(this.serverHour)
            + "," + IntegerToString(this.serverMinute)
            + "," + IntegerToString(this.jstHour)
            + "," + IntegerToString(this.jstMinute)
            + "," + IntegerToString(this.dayOfWeek)
            + "," + this.getSessionName()
            + "," + this.boolToCsv(this.isTokyoSession)
            + "," + this.boolToCsv(this.isLondonSession)
            + "," + this.boolToCsv(this.isNewYorkSession)
            + "," + this.boolToCsv(this.isLondonNewYorkOverlap)
            + "," + this.boolToCsv(this.isRolloverTime)
            + "," + this.boolToCsv(this.isMondayEarly)
            + "," + this.boolToCsv(this.isFridayLate);
    }

private:
    /**
     * bool値をCSV用文字列へ変換
     *
     * @param boolValue bool値
     * @return CSV用文字列
     */
    string boolToCsv(const bool boolValue) {
        if (boolValue) {
            return "true";
        }

        return "false";
    }

    /**
     * 東京時間か判定
     *
     * @return true: 東京時間
     */
    bool isTokyoSessionTime() {
        // 東京時間判定
        return this.isInJstHourRange(9, 15);
    }

    /**
     * ロンドン時間か判定
     *
     * @return true: ロンドン時間
     */
    bool isLondonSessionTime() {
        // 夏時間判定
        if (this.jstOffsetHour == 6) {
            return this.isInJstHourRange(16, 1);
        }

        return this.isInJstHourRange(17, 2);
    }

    /**
     * ニューヨーク時間か判定
     *
     * @return true: ニューヨーク時間
     */
    bool isNewYorkSessionTime() {
        // 夏時間判定
        if (this.jstOffsetHour == 6) {
            return this.isInJstHourRange(21, 6);
        }

        return this.isInJstHourRange(22, 7);
    }

    /**
     * ロンドンニューヨーク重複時間か判定
     *
     * @return true: ロンドンニューヨーク重複時間
     */
    bool isLondonNewYorkOverlapTime() {
        // 夏時間判定
        if (this.jstOffsetHour == 6) {
            return this.isInJstHourRange(21, 1);
        }

        return this.isInJstHourRange(22, 2);
    }

    /**
     * ロールオーバー時間帯か判定
     *
     * @return true: ロールオーバー時間帯
     */
    bool isRolloverTimeRange() {
        // JST 6時台から7時台
        return this.isInJstHourRange(6, 8);
    }

    /**
     * 月曜早朝か判定
     *
     * @return true: 月曜早朝
     */
    bool isMondayEarlyTime() {
        if (this.dayOfWeek != 1) {
            return false;
        }

        if (this.jstHour < 8) {
            return true;
        }

        return false;
    }

    /**
     * 金曜深夜か判定
     *
     * @return true: 金曜深夜
     */
    bool isFridayLateTime() {
        if (this.dayOfWeek == 5 && this.jstHour >= 23) {
            return true;
        }

        if (this.dayOfWeek == 6 && this.jstHour < 7) {
            return true;
        }

        return false;
    }

    /**
     * 週末セッション除外時間か判定
     *
     * @return true: 週末セッション除外時間
     */
    bool isWeekendSessionBlockedTime() {
        if (this.dayOfWeek == 0) {
            return true;
        }

        if (this.dayOfWeek == 6) {
            return true;
        }

        return false;
    }

    /**
     * セッション種別を解決
     *
     * @return 取引セッション種別
     */
    SessionType resolveSessionType() {
        if (this.isTokyoSession && this.isLondonSession) {
            return sessionTokyoLondon;
        }

        if (this.isLondonNewYorkOverlap) {
            return sessionLondonNewYork;
        }

        if (this.isTokyoSession) {
            return sessionTokyo;
        }

        if (this.isLondonSession) {
            return sessionLondon;
        }

        if (this.isNewYorkSession) {
            return sessionNewYork;
        }

        return sessionOther;
    }

    /**
     * JST時間範囲内か判定
     *
     * @param startHourValue 開始時
     * @param endHourValue 終了時
     * @return true: 範囲内
     */
    bool isInJstHourRange(const int startHourValue, const int endHourValue) {
        if (startHourValue == endHourValue) {
            return false;
        }

        if (startHourValue < endHourValue) {
            if (this.jstHour >= startHourValue && this.jstHour < endHourValue) {
                return true;
            }

            return false;
        }

        if (this.jstHour >= startHourValue) {
            return true;
        }

        if (this.jstHour < endHourValue) {
            return true;
        }

        return false;
    }
};
