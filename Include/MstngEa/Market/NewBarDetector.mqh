/**
 * Package: MstngEa.Market
 * File: NewBarDetector.mqh
 */

#ifndef MSTNGEA_MARKET_NEWBARDETECTOR_MQH
#define MSTNGEA_MARKET_NEWBARDETECTOR_MQH

/**
 * 新規バー検出
 */
class NewBarDetector {
public:
    /** シンボル名 */
    string symbolName;

    /** 時間足 */
    ENUM_TIMEFRAMES timeFrame;

    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     */
    NewBarDetector(string symbolNameValue, ENUM_TIMEFRAMES timeFrameValue) {
        // 基本情報を保持
        this.symbolName = symbolNameValue;
        this.timeFrame = timeFrameValue;
        this.lastBarTime = 0;
    }

    /**
     * 新規バー判定
     *
     * @return true: 新規バー
     */
    bool isNewBar() {
        // 現在バー時刻を取得
        datetime currentBarTime = iTime(this.symbolName, this.timeFrame, 0);

        if (currentBarTime <= 0) {
            return false;
        }

        if (this.lastBarTime == 0) {
            this.lastBarTime = currentBarTime;
            return false;
        }

        if (this.lastBarTime != currentBarTime) {
            this.lastBarTime = currentBarTime;
            return true;
        }

        return false;
    }

    /**
     * 現在バー時刻取得
     *
     * @return 現在バー時刻
     */
    datetime getLastBarTime() {
        return this.lastBarTime;
    }

private:
    /** 最終バー時刻 */
    datetime lastBarTime;
};

#endif
