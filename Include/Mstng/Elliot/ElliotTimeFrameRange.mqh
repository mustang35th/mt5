//+------------------------------------------------------------------+
//|                                ElliotTimeFrameRange.mqh         |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef ELLIOT_TIME_FRAME_RANGE_MQH
#define ELLIOT_TIME_FRAME_RANGE_MQH

/**
 * Elliott分析で使用する時間足範囲を生成するクラス。
 */
class ElliotTimeFrameRange {
public:
    /**
     * 開始時間足から現在時間足までの時間足一覧を生成する。
     *
     * @param fromStartTimeFrame 開始時間足
     * @param fromCurrentTimeFrame 現在時間足
     * @param fromTimeFrames 対象時間足一覧の格納先
     * @return 対応する正しい範囲の場合true
     */
    static bool build(
        ENUM_TIMEFRAMES fromStartTimeFrame,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        ENUM_TIMEFRAMES &fromTimeFrames[]
    ) {
        ENUM_TIMEFRAMES supportedTimeFrames[] = {
            PERIOD_MN1,
            PERIOD_W1,
            PERIOD_D1,
            PERIOD_H4,
            PERIOD_H1,
            PERIOD_M15,
            PERIOD_M5,
            PERIOD_M1
        };

        ArrayResize(fromTimeFrames, 0);

        int startIndex = ElliotTimeFrameRange::findIndex(
            supportedTimeFrames,
            fromStartTimeFrame
        );
        int currentIndex = ElliotTimeFrameRange::findIndex(
            supportedTimeFrames,
            fromCurrentTimeFrame
        );

        if (startIndex < 0 || currentIndex < 0) {
            return false;
        }

        if (startIndex > currentIndex) {
            return false;
        }

        int targetCount = currentIndex - startIndex + 1;
        ArrayResize(fromTimeFrames, targetCount);

        for (int i = 0; i < targetCount; i++) {
            fromTimeFrames[i] = supportedTimeFrames[startIndex + i];
        }

        return true;
    }

private:
    /**
     * 時間足一覧から指定時間足の位置を取得する。
     *
     * @param fromTimeFrames 時間足一覧
     * @param fromTimeFrame 検索する時間足
     * @return 見つかった位置。未対応の場合-1
     */
    static int findIndex(
        const ENUM_TIMEFRAMES &fromTimeFrames[],
        ENUM_TIMEFRAMES fromTimeFrame
    ) {
        int total = ArraySize(fromTimeFrames);

        for (int i = 0; i < total; i++) {
            if (fromTimeFrames[i] == fromTimeFrame) {
                return i;
            }
        }

        return -1;
    }
};

#endif
