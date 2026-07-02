//+------------------------------------------------------------------+
//|                                                TimeFrameInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Object.mqh>

/**
 * 時間足情報を保持するクラス。
 */
class TimeFrameInfo : public CObject {
public:
    /** 時間足 */
    ENUM_TIMEFRAMES timeFrame;

    /** エリオット処理対象 */
    bool isElliotTarget;

    /**
     * コンストラクタ。
     *
     * @param fromTimeFrame 時間足
     */
    TimeFrameInfo(ENUM_TIMEFRAMES fromTimeFrame) {
        this.timeFrame = fromTimeFrame;
    }

    /** デストラクタ。 */
    ~TimeFrameInfo() {
    }
    
    /**
     * 文字列表現を返す。
     *
     * @return 時間足情報の文字列
     */
    string toString() {
        return StringFormat("TimeFrameInfo{timeFrame = %s, isElliotTarget = %s}",
                            EnumToString(timeFrame),
                            (string)isElliotTarget);
    }
};
