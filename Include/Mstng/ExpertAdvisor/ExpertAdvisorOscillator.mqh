//+------------------------------------------------------------------+
//|                                      ExpertAdvisorOscillator.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Util\UtilAll.mqh>

class ExpertAdvisorOscillator {
public:
    /** 判定対象の市場コンテキスト */
    MarketContext marketContext;

    /**
     * 判定対象を指定して初期化する。
     *
     * @param fromSymbolName 判定対象シンボル
     * @param fromTimeFrame 判定対象時間足
     */
    ExpertAdvisorOscillator(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    ExpertAdvisorOscillator(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    ~ExpertAdvisorOscillator() {
    }

    /**
     * 判定対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 判定対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /*bool isStochasticCross_1(Elliot &elliot, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int stochasticCount = elliot.oscillator.stochasticCount;
        bool isStochasticCross_1 = this.isValue_1(isBuy, stochasticCount);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.marketContext.timeFrameLabel));
        this.logger.debug(__FUNCTION__, StringFormat("stochasticCount = %s", StringUtil::addSign(stochasticCount)));
        this.logger.debug(__FUNCTION__, StringFormat("isStochasticCross_1 = %s", (string)isStochasticCross_1));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isStochasticCross_1;
    }
    
    bool isStochasticCross_2(Elliot &elliot, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int stochasticCount = elliot.oscillator.stochasticCount;
        bool isStochasticCross_2 = this.isValue_2(isBuy, stochasticCount);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.marketContext.timeFrameLabel));
        this.logger.debug(__FUNCTION__, StringFormat("stochasticCount = %s", StringUtil::addSign(stochasticCount)));
        this.logger.debug(__FUNCTION__, StringFormat("isStochasticCross_2 = %s", (string)isStochasticCross_2));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isStochasticCross_2;
    }*/
    
    bool isGmmaTrend_1(Elliot &elliot, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int gmmaTrend = elliot.oscillator.gmmaTrendCount;
        bool isgmmaTrend_1 = this.isValue_1(isBuy, gmmaTrend);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.marketContext.timeFrameLabel));
        this.logger.debug(__FUNCTION__, StringFormat("gmmaTrend = %s", StringUtil::addSign(gmmaTrend)));
        this.logger.debug(__FUNCTION__, StringFormat("isgmmaTrend_1 = %s", (string)isgmmaTrend_1));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isgmmaTrend_1;
    }
    
    bool isGmmaTrend_2(Elliot &elliot, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int gmmaTrend = elliot.oscillator.gmmaTrendCount;
        bool isgmmaTrend_2 = this.isValue_2(isBuy, gmmaTrend);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.marketContext.timeFrameLabel));
        this.logger.debug(__FUNCTION__, StringFormat("gmmaTrend = %s", StringUtil::addSign(gmmaTrend)));
        this.logger.debug(__FUNCTION__, StringFormat("isgmmaTrend_2 = %s", (string)isgmmaTrend_2));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isgmmaTrend_2;
    }
    
    bool isGmmaCross_2(Elliot &elliot, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int gmmaCount = elliot.oscillator.gmmaCrossCount;
        bool isGmmaCross_2 = this.isValue_2(isBuy, gmmaCount);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.marketContext.timeFrameLabel));
        this.logger.debug(__FUNCTION__, StringFormat("gmmaCount = %s", StringUtil::addSign(gmmaCount)));
        this.logger.debug(__FUNCTION__, StringFormat("isGmmaCross_2 = %s", (string)isGmmaCross_2));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isGmmaCross_2;
    }
    
    bool isTrendCountNeutral(Elliot *elliot) {
        Oscillator oscillator = elliot.oscillator;
        
        return this.isTrendCountNeutral(oscillator.stochasticShort.count, oscillator.stochasticMiddle.count, oscillator.stochasticLong.count);
    }
    
    bool isStochasticMainOrder(ElliotAll *elliotAll) {
        Elliot *elliotD1 = elliotAll.getElliot(PERIOD_D1);
        Elliot *elliotH4 = elliotAll.getElliot(PERIOD_H4);
        Elliot *elliotH1 = elliotAll.getElliot(PERIOD_H1);
        
        if (elliotD1 == NULL
                || elliotH4 == NULL
                || elliotH1 == NULL
                || elliotAll.elliotCurrent == NULL) {
            return false;
        }
        
        bool isBuy = elliotAll.elliotCurrent.isBuy;
        
        bool isStochasticMainOrder = false;
        
        if (isBuy) {
            if (this.isStochasticMainOrder(elliotD1, STOCH_MAIN_ORDER_S_M_L)
                    || this.isStochasticMainOrder(elliotH4, STOCH_MAIN_ORDER_S_M_L)) {
                if (this.isStochasticMainOrder(elliotH1, STOCH_MAIN_ORDER_S_M_L)
                        || this.isStochasticMainOrder(elliotH1, STOCH_MAIN_ORDER_M_S_L)) {
                    isStochasticMainOrder = true;
                }
            }
        } else {
            if (this.isStochasticMainOrder(elliotD1, STOCH_MAIN_ORDER_L_M_S)
                    || this.isStochasticMainOrder(elliotH4, STOCH_MAIN_ORDER_L_M_S)) {
                if (this.isStochasticMainOrder(elliotH1, STOCH_MAIN_ORDER_L_M_S)
                        || this.isStochasticMainOrder(elliotH1, STOCH_MAIN_ORDER_L_S_M)) {
                    isStochasticMainOrder = true;
                }
            }
        }
        
        return isStochasticMainOrder;
    }
    
    bool isStochasticMainOrderD1H1(ElliotAll *elliotAll) {
        Elliot *elliotD1 = elliotAll.getElliot(PERIOD_D1);
        Elliot *elliotH1 = elliotAll.getElliot(PERIOD_H1);
        
        if (elliotD1 == NULL
                || elliotH1 == NULL
                || elliotAll.elliotCurrent == NULL) {
            return false;
        }
        
        bool isBuy = elliotAll.elliotCurrent.isBuy;
        
        bool isStochasticMainOrder = false;
        
        if (isBuy) {
            if (elliotD1.oscillator.isBuyStochasticMainOrder()
                    && elliotH1.oscillator.isBuyStochasticMainOrder()) {
                isStochasticMainOrder = true;
            }
        } else {
            if (elliotD1.oscillator.isSellStochasticMainOrder()
                    && elliotH1.oscillator.isSellStochasticMainOrder()) {
                isStochasticMainOrder = true;
            }
        }
        
        return isStochasticMainOrder;
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
    
    bool isStochasticMainOrder(Elliot *elliot, ENUM_STOCHASTIC_MAIN_ORDER value) {
        bool isStochasticMainOrder = false;
        
        if (elliot.oscillator.stochasticMainOrder == value) {
            isStochasticMainOrder = true;
        }
        
        return isStochasticMainOrder;
    }
    
    bool isTrendCountNeutral(int countShort, int countMiddle, int countLong) {
        int plusCount = 0;
        int minusCount = 0;
    
        if (countShort == 1) {
            plusCount++;
        } else if (countShort == -1) {
            minusCount++;
        }
    
        if (countMiddle == 1) {
            plusCount++;
        } else if (countMiddle == -1) {
            minusCount++;
        }
    
        if (countLong == 1) {
            plusCount++;
        } else if (countLong == -1) {
            minusCount++;
        }
    
        if (plusCount == 2 || minusCount == 2) {
            return false;
        }
    
        return true;
    }
    
    bool isValue_1(bool isBuy, int count) {
        return this.isValue(isBuy, count, 0, 0);
    }
    
    bool isValue_2(bool isBuy, int count) {
        return this.isValue(isBuy, count, 1, -1);
    }
    
    bool isValue(bool isBuy, int count, int buyValue, int sellValue) {
        bool isValue = false;
        
        if (isBuy) {
            if (count > buyValue) {
                isValue = true;
            }
        } else {
            if (count < sellValue) {
                isValue = true;
            }
        }
        
        return isValue;
    }
};    



