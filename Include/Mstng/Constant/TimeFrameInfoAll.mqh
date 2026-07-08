//+------------------------------------------------------------------+
//|                                             TimeFrameInfoAll.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Arrays\ArrayObj.mqh>

#include <Mstng\Constant\TimeFrameInfo.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * 時間足情報を一括管理するクラス。
 */
class TimeFrameInfoAll {
public:
    /** 時間足リスト。 */
    CArrayObj timeFrameInfoList;
    
    /**
     * コンストラクタ。
     *
     * 内部の時間足リストを初期化し、
     * 主要なタイムフレームを登録する。
     */
    TimeFrameInfoAll() {
        this.logger.setLevel(LOG_INFO);
        
        this.add(PERIOD_M1);
        this.add(PERIOD_M5);
        this.add(PERIOD_M15);
        this.add(PERIOD_H1);
        this.add(PERIOD_H4);
        this.add(PERIOD_D1);
        this.add(PERIOD_W1);
        this.add(PERIOD_MN1);
    }

    /**
     * デストラクタ。
     *
     * 内部で保持しているTimeFrameInfoインスタンスを解放する。
     */
    ~TimeFrameInfoAll() {
        int total = this.timeFrameInfoList.Total();

        for (int i = 0; i < total; i++) {
            CObject *obj = this.timeFrameInfoList.At(i);

            if (obj != NULL) {
                delete obj;
            }
        }

        this.timeFrameInfoList.Clear();
    }
    
    /**
     * 要素数を取得する。
     *
     * @return 時間足情報数。
     */
    int getCount() {
        return this.timeFrameInfoList.Total();
    }
    
    /**
     * タイムフレームからインデックスを取得する。
     *
     * PERIOD_CURRENTが渡された場合は、
     * 現在チャートの Period() を使用する。
     *
     * 対応するタイムフレームが無い場合は 0 を返す。
     *
     * @param fromTimeFrame 検索対象のタイムフレーム。
     * @return 見つかったインデックス。0始まり。
     */
    int getIndex(ENUM_TIMEFRAMES fromTimeFrame) {
        int index = 0;

        int timeFrameValue = fromTimeFrame;

        if (timeFrameValue == PERIOD_CURRENT) {
            timeFrameValue = Period();
        }

        int total = this.timeFrameInfoList.Total();

        for (int i = 0; i < total; i++) {
            TimeFrameInfo *timeFrameInfo = this.timeFrameInfoList.At(i);

            if (timeFrameInfo != NULL) {
                if (timeFrameInfo.timeFrame == timeFrameValue) {
                    index = i;
                    break;
                }
            }
        }

        return index;
    }

    /**
     * インデックスからタイムフレームを取得する。
     *
     * 範囲外のインデックスが指定された場合は 0 を返す。
     *
     * @param index インデックス。0始まり。
     * @return 対応するタイムフレーム。
     */
    ENUM_TIMEFRAMES getTimeFrame(int index) {
        this.logger.debug(
            __FUNCTION__,
            StringFormat("index=%d", index)
        );

        int total = this.timeFrameInfoList.Total();

        if (index < 0) {
            return (ENUM_TIMEFRAMES)0;
        }

        if (index >= total) {
            return (ENUM_TIMEFRAMES)0;
        }

        TimeFrameInfo *timeFrameInfo = this.timeFrameInfoList.At(index);

        if (timeFrameInfo == NULL) {
            return (ENUM_TIMEFRAMES)0;
        }

        return timeFrameInfo.timeFrame;
    }

    /**
     * 基準タイムフレームから、指定本数ずらしたタイムフレームを取得する。
     *
     * 例:
     *   fromTimeFrame = PERIOD_M5, add = 1  → PERIOD_M15
     *
     * @param fromTimeFrame 基準タイムフレーム。
     * @param add ずらすインデックス数。負数も可。
     * @return 対応するタイムフレーム。
     */
    ENUM_TIMEFRAMES getTimeFrame(ENUM_TIMEFRAMES fromTimeFrame, int add) {
        int index = this.getIndex(fromTimeFrame);

        return this.getTimeFrame(index + add);
    }
    
    /**
     * エリオット対象時間足を設定する。
     *
     * startTimeFrame 〜 endTimeFrame の範囲の時間足をtrueにする。
     *
     * @param startTimeFrame 開始時間足。
     * @param endTimeFrame 終了時間足。
     */
    void setElliotTarget(ENUM_TIMEFRAMES startTimeFrame, ENUM_TIMEFRAMES endTimeFrame) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("startTimeFrame = %s", TimeUtil::convertTimeFrameToString(startTimeFrame)));
        this.logger.debug(__FUNCTION__, StringFormat("endTimeFrame = %s", TimeUtil::convertTimeFrameToString(endTimeFrame)));
        
        int total = this.timeFrameInfoList.Total();

        for (int i = 0; i < total; i++) {
            TimeFrameInfo *timeFrameInfo = this.timeFrameInfoList.At(i);

            if (timeFrameInfo != NULL) {
                if (startTimeFrame >= timeFrameInfo.timeFrame
                        && timeFrameInfo.timeFrame >= endTimeFrame) {
                    timeFrameInfo.isElliotTarget = true;
                    
                    this.logger.debug(__FUNCTION__, StringFormat("isElliotTarget = true -> timeFrameInfo.timeFrame = %s", 
                        TimeUtil::convertTimeFrameToString(timeFrameInfo.timeFrame)));
                }
            }
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
private:
    /** ロガー。 */
    Logger logger;
    
    /**
     * タイムフレーム情報を追加する。
     *
     * @param addTimeFrame 追加するタイムフレーム。
     */
    void add(ENUM_TIMEFRAMES addTimeFrame) {
        TimeFrameInfo *timeFrameInfo = new TimeFrameInfo(addTimeFrame);
        
        this.timeFrameInfoList.Add(timeFrameInfo);
    }
};
