//+------------------------------------------------------------------+
//|                                          ExpertAdvisorElliot.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Util\UtilAll.mqh>

class ExpertAdvisorElliot {
public:
    /** 判定対象の市場コンテキスト */
    MarketContext marketContext;

    /**
     * 判定対象を指定して初期化する。
     *
     * @param fromSymbolName 判定対象シンボル
     * @param fromTimeFrame 判定対象時間足
     */
    ExpertAdvisorElliot(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    ExpertAdvisorElliot(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    ~ExpertAdvisorElliot() {
    }

    /**
     * 判定対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    bool isZigZagConfirmed(Elliot &elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isZigZagConfirmed = false;
        
        // 最新のZigZagポイントを取得する
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        
        // 追加途中のポイントでなければ、ZigZagは確定と判定する
        if (!latestPoint.isAddedPoint) {
            isZigZagConfirmed = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("latestPoint = %s", latestPoint.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("isZigZagConfirmed = %s", (string)isZigZagConfirmed));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                    
        return isZigZagConfirmed;
    }
    
    bool isBuySell(Elliot &elliot, bool fromIsBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isBuySell = false;
        
        if (fromIsBuy) {
            if (elliot.isBuy) {
                isBuySell = true;
            }
        } else {
            if (!elliot.isBuy) {
                isBuySell = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.marketContext.timeFrameLabel));
        this.logger.debug(__FUNCTION__, StringFormat("elliot.isBuy = %s", (string)elliot.isBuy));
        
        this.logger.debug(__FUNCTION__, StringFormat("fromIsBuy = %s", (string)fromIsBuy));
        this.logger.debug(__FUNCTION__, StringFormat("isBuySell = %s", (string)isBuySell));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isBuySell;
    }
    
    /**
     * 現在時間足に応じた上位時間足の売買方向が一致するか判定する。
     *
     * @param fromElliotAll 全時間足のElliot情報
     * @param fromIsBuy BUY方向の場合true
     * @return 必要な上位時間足の売買方向が一致する場合true
     */
    bool isBuySell(
        ElliotAll &fromElliotAll,
        bool fromIsBuy
    ) {
        bool isBuySell = false;
    
        Elliot *elliotH4 = fromElliotAll.getElliot(PERIOD_H4);
        Elliot *elliotH1 = fromElliotAll.getElliot(PERIOD_H1);
        Elliot *elliotM15 = fromElliotAll.getElliot(PERIOD_M15);
        Elliot *elliotM5 = fromElliotAll.getElliot(PERIOD_M5);
    
        if (fromElliotAll.marketContext.timeFrame == PERIOD_M15) {
            if (elliotH4 == NULL || elliotH1 == NULL) {
                return false;
            }
    
            if (this.isBuySell(*elliotH4, fromIsBuy)
                    && this.isBuySell(*elliotH1, fromIsBuy)) {
                isBuySell = true;
            }
        }
    
        if (fromElliotAll.marketContext.timeFrame == PERIOD_M5) {
            if (elliotH4 == NULL || elliotH1 == NULL || elliotM15 == NULL) {
                return false;
            }
    
            if (this.isBuySell(*elliotH4, fromIsBuy)
                    && this.isBuySell(*elliotH1, fromIsBuy)
                    && this.isBuySell(*elliotM15, fromIsBuy)) {
                isBuySell = true;
            }
        }
    
        if (fromElliotAll.marketContext.timeFrame == PERIOD_M1) {
            if (elliotH4 == NULL || elliotH1 == NULL || elliotM15 == NULL || elliotM5 == NULL) {
                return false;
            }
    
            if (this.isBuySell(*elliotH4, fromIsBuy)
                    && this.isBuySell(*elliotH1, fromIsBuy)
                    && this.isBuySell(*elliotM15, fromIsBuy)
                    && this.isBuySell(*elliotM5, fromIsBuy)) {
                isBuySell = true;
            }
        }
    
        return isBuySell;
    }
    
    bool isMotiveWave(Elliot &elliot) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isMotiveWave = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        
        if (latestPoint.isMotiveWave()) {
            isMotiveWave = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("latestPoint = %s", latestPoint.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("isMotiveWave = %s", (string)isMotiveWave));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                    
        return isMotiveWave;
    }
    
    bool isSameTrend(Elliot &elliot, bool fromIsUptrend) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isSameTrend = false;
        
        bool isUptrend = elliot.isUptrend();
        
        if (fromIsUptrend) {
            if (isUptrend) {
                isSameTrend = true;
            }
        } else {
            if (!isUptrend) {
                isSameTrend = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isSameTrend = %s", (string)isSameTrend));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                    
        return isSameTrend;
    }
    
private:
    Logger logger;

    /**
     * 市場コンテキストとロガーを初期化する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
    }

};



