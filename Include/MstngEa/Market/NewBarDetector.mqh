/**
 * Package: MstngEa.Market
 * File: NewBarDetector.mqh
 */

#ifndef MSTNGEA_MARKET_NEWBARDETECTOR_MQH
#define MSTNGEA_MARKET_NEWBARDETECTOR_MQH

#include <Mstng\Common\MarketContext.mqh>

/**
 * 新規バー検出
 */
class NewBarDetector {
public:
    /** 新規バー検出対象の市場コンテキスト */
    MarketContext marketContext;

    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     */
    NewBarDetector(string symbolNameValue, ENUM_TIMEFRAMES timeFrameValue) {
        MarketContext context(symbolNameValue, timeFrameValue);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param marketContextValue 新規バー検出対象の市場コンテキスト
     */
    NewBarDetector(MarketContext &marketContextValue) {
        this.initializeMarketContext(marketContextValue);
    }

    /**
     * 新規バー判定
     *
     * @return true: 新規バー
     */
    bool isNewBar() {
        // 現在バー時刻を取得
        datetime currentBarTime = iTime(
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            0
        );

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

    /**
     * 市場コンテキストを設定する。
     *
     * @param marketContextValue 新規バー検出対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &marketContextValue) {
        this.marketContext = marketContextValue;
        this.lastBarTime = 0;
    }
};

#endif
