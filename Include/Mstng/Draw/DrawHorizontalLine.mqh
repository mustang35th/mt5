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

/**
 * 高値/安値のポイントを繋いだ水平ラインを描画するクラスです。
 */
class DrawHorizontalLine : public DrawBase {
public:
    
    /**
     * デフォルトコンストラクタ。
     */
    DrawHorizontalLine() {
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    DrawHorizontalLine(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * デストラクタ。
     */
    ~DrawHorizontalLine() {
    }
    
    /**
     * 指定分析結果の高値安値ラインを描画する。
     *
     * @param fromElliotAll Elliot解析結果
     */
    void draw(ElliotAll &fromElliotAll) {
        this.initializeMarketContext(fromElliotAll.marketContext);
        
        if (fromElliotAll.marketContext.timeFrame < PERIOD_MN1) {
            Elliot *elliotHigher = fromElliotAll.getElliot(fromElliotAll.marketContext.timeFrame, 1); // 上位足
            
            if (elliotHigher != NULL) {
                this.draw(elliotHigher, 3, true);
            }
        }
    }
    
private:    
    /**
     * 波動のポイントを使って水平ラインを描画する。
     *
     * @param elliot 描画対象のElliot
     * @param lineSize ライン幅
     * @param isUpper 上位足由来ならtrue
     */
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
                    datetimeTo = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, to);
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
            
            string text = DoubleToString(rateFrom, elliot.marketContext.digits);
            
            DrawUtil::setText(objectName + "Label", drawProperties.elliotFontFace, lineColor, 11, text, drawDatetime, rateFrom);
            
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};
