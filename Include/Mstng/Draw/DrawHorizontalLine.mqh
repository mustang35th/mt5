//+------------------------------------------------------------------+
//|                                           DrawHorizontalLine.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Draw\DrawBase.mqh>
#include <Mstng\Draw\DrawProperties.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>

class DrawHorizontalLine : public DrawBase {
public:
    
    DrawHorizontalLine() {
        this.logger.setLevel(LOG_INFO);
    }
    
    ~DrawHorizontalLine() {
    }
    
    void draw(ElliotAll &fromElliotAll) {
        this.logger.setMarketContext(fromElliotAll.marketContext);
        
        if (fromElliotAll.marketContext.timeFrame < PERIOD_MN1) {
            Elliot *elliotHigher = fromElliotAll.getElliot(fromElliotAll.marketContext.timeFrame, 1); // 上位足
            
            if (elliotHigher != NULL) {
                this.draw(elliotHigher, 3, true);
            }
        }
    }
    
private:    
    void draw(Elliot &elliot, int lineSize, bool isUpper = false) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("elliot = %s", elliot.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("lineSize = %d", lineSize));
        this.logger.debug(__FUNCTION__, StringFormat("isUpper = %s", (string)isUpper));
        
        string preObjectName;
        StringConcatenate(preObjectName, "HorizontalLine", elliot.marketContext.timeFrameLabel);
        
        color lineColor = clrLightGray;
        
        CArrayObj *zigZagPointList = &(elliot.zigZagPointList);
        int zigZagTotal = zigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("zigZagTotal = %d", zigZagTotal));
        
        for (int i = 1; i < zigZagTotal; i++) {
            string objectName;
            StringConcatenate(objectName, preObjectName, "_i", StringUtil::zeroPadding(i, 3));
            
            this.logger.debug(__FUNCTION__, objectName);
                
            ZigZagPoint *zigZagPointFrom = zigZagPointList.At(i);
            
            int to = 0;
            
            if (i >= 4) {
                to = i - 3;
            }
            
            ZigZagPoint *zigZagPointTo = zigZagPointList.At(to);
            
            
            double rateFrom = zigZagPointFrom.rate;
            double rateTo = zigZagPointTo.rate;
            
            bool isBuy = !zigZagPointFrom.isPeak;
            
            datetime datetimeFrom = zigZagPointFrom.barTime;
            datetime datetimeTo = zigZagPointTo.barTime;

            if (isUpper) {
                datetimeFrom = this.getDatetime(elliot.marketContext.timeFrame, datetimeFrom, rateFrom, isBuy, true);
                
                if (to == 0) {
                    datetimeTo = iTime(elliot.marketContext.symbolName, NULL, to);
                } else {
                    datetimeTo = this.getDatetime(elliot.marketContext.timeFrame, datetimeTo, rateTo, isBuy, false);
                }
            }

            DrawUtil::setTrendLine(
                objectName,
                datetimeFrom,
                rateFrom,
                datetimeTo,
                rateFrom,
                lineColor,
                STYLE_SOLID,
                lineSize,
                false
            );
            
            DrawProperties drawProperties;
            datetime drawDatetime = TimeUtil::addBars(datetimeTo, elliot.marketContext.timeFrame, 3);
            
            int digits = RateUtil::getDigits(elliot.marketContext.symbolName);
            string text = DoubleToString(rateFrom, digits);
            
            DrawUtil::setText(objectName + "Label", drawProperties.elliotFontFace, lineColor, 11, text, drawDatetime, rateFrom);
            
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};
