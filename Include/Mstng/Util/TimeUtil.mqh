//+------------------------------------------------------------------+
//|                                                     TimeUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * 時間足（ENUM_TIMEFRAMES）に関するユーティリティメソッドを提供するクラス。
 *
 * ENUM_TIMEFRAMES を「M1」「H1」「D1」などの
 * 人間が読みやすい文字列表現へ変換する処理をまとめています。
 */
class TimeUtil {
public:
    /**
     * ENUM_TIMEFRAMES を人間が読める文字列に変換します。
     *
     * PERIOD_M1 → "M1"、PERIOD_H1 → "H1" のように、
     * MT5 の時間足を文字列表現に変換します。
     * 想定外の値が渡された場合は "UNKNOWN" を返します。
     *
     * @param fromTimeFrame 変換対象の時間足（ENUM_TIMEFRAMES）。
     *
     * @return 時間足を表す文字列。
     */
    static string convertTimeFrameToString(ENUM_TIMEFRAMES fromTimeFrame) {

        switch (fromTimeFrame) {

            case PERIOD_CURRENT:  return "CURRENT";

            case PERIOD_M1:   return "M1";
            case PERIOD_M2:   return "M2";
            case PERIOD_M3:   return "M3";
            case PERIOD_M4:   return "M4";
            case PERIOD_M5:   return "M5";
            case PERIOD_M6:   return "M6";
            case PERIOD_M10:  return "M10";
            case PERIOD_M12:  return "M12";
            case PERIOD_M15:  return "M15";
            case PERIOD_M20:  return "M20";
            case PERIOD_M30:  return "M30";

            case PERIOD_H1:   return "H1";
            case PERIOD_H2:   return "H2";
            case PERIOD_H3:   return "H3";
            case PERIOD_H4:   return "H4";
            case PERIOD_H6:   return "H6";
            case PERIOD_H8:   return "H8";
            case PERIOD_H12:  return "H12";

            case PERIOD_D1:   return "D1";
            case PERIOD_W1:   return "W1";
            case PERIOD_MN1:  return "MN1";
        }

        return "UNKNOWN";
    }
    
    /**
     * datetime を "yyyymmddhhmi" 形式（例: 202512240915）に変換する。
     *
     * @param fromDatetime 対象日時
     * @return "yyyymmddhhmi" 形式の文字列
     */
    static string formatYyyymmddhhmi(datetime fromDatetime) {
        MqlDateTime dt;
        TimeToStruct(fromDatetime, dt);

        return StringFormat("%04d%02d%02d%02d%02d",
                            dt.year,
                            dt.mon,
                            dt.day,
                            dt.hour,
                            dt.min);
    }
    
    /**
     * datetime を "yyyy/mm/dd hh:mm:ss" 形式（例: 2025/12/24 09:15:30）に変換する。
     *
     * @param fromDatetime 対象日時
     * @return 変換された日時文字列
     */
    static string formatYyyymmddhhmiss(datetime fromDatetime) {
        MqlDateTime dt;
        TimeToStruct(fromDatetime, dt);

        return StringFormat("%04d/%02d/%02d %02d:%02d:%02d",
                            dt.year,
                            dt.mon,
                            dt.day,
                            dt.hour,
                            dt.min,
                            dt.sec);
    }


    /**
     * バーインデックスから「次の足」の datetime を取得します。
     *
     * MT5 のバーインデックスは 0 が最新バーで、値が大きくなるほど過去の足です。
     * 「時間的に次の足」は、shift が 1 小さいバーになります。
     *
     * @param symbolName   対象シンボル（例: _Symbol）。
     * @param timeframe    対象時間足。
     * @param shift        基準となるバーインデックス（0 = 最新バー）。
     *
     * @return 次の足の datetime。存在しない場合は 0 を返します。
     */
    static datetime getNextBarTimeByShift(
        string symbolName,
        ENUM_TIMEFRAMES timeframe,
        int shift
    ) {
        // shift が 0 の場合、まだ次の「確定足」は存在しないので、
        // 現在のバーの開始時刻 + PeriodSeconds を「次の足の時間」とみなします。
        if (shift == 0) {
            datetime currentBarTime = iTime(symbolName, timeframe, 0);

            return (currentBarTime + PeriodSeconds(timeframe));
        }

        // それ以外の場合は、時間的に次の足は shift - 1 になる
        int nextShift = shift - 1;

        if (nextShift < 0) {

            return 0;
        }

        datetime nextBarTime = iTime(symbolName, timeframe, nextShift);

        return nextBarTime;
    }

    /**
     * datetime に指定した時間足の本数を加算した日時を返す。
     *
     * @param fromDatetime 元の datetime
     * @param timeframe 加算対象の時間足
     * @param barCount 加算する時間足の本数
     * @return 加算後の datetime
     */
    static datetime addBars(
        datetime fromDatetime,
        ENUM_TIMEFRAMES timeframe,
        int barCount
    ) {
        int periodSeconds = PeriodSeconds(timeframe);

        if (periodSeconds <= 0) {
            return fromDatetime;
        }

        if (barCount == 0) {
            return fromDatetime;
        }

        long addSeconds = (long)periodSeconds * (long)barCount;

        return (datetime)((long)fromDatetime + addSeconds);
    }
};
