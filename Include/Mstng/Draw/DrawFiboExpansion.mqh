//+------------------------------------------------------------------+
//|                                            DrawFiboExpansion.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Util\UtilAll.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>

class DrawFiboExpansion {
public:

    DrawFiboExpansion() {
        this.logger.setLevel(LOG_INFO);
    }

    ~DrawFiboExpansion() {
    }

    /**
     * 現在足のフィボナッチエクスパンションを描画する。
     *
     * @param fromElliotAll エリオット分析結果
     */
    void draw(ElliotAll &fromElliotAll) {
        this.logger.setMarketContext(fromElliotAll.marketContext);

        //Elliot *elliot = fromElliotAll.getElliot(fromElliotAll.marketContext.timeFrame, 0);
        
        Elliot *elliot = fromElliotAll.elliotCurrent;
        
        if (elliot == NULL) {
            this.logger.error(__FUNCTION__, "elliot is null.");
            return;
        }

        this.draw(elliot, 1);
    }


private:
    Logger logger;

    /**
     * 現在足の最新描画対象波のみフィボナッチエクスパンションを描画する。
     *
     * @param elliot エリオット分析結果
     * @param lineSize 線の太さ
     */
    void draw(Elliot &elliot, int lineSize) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.logger.debug(__FUNCTION__, StringFormat("elliot = %s", elliot.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("lineSize = %d", lineSize));

        string preObjectName;
        StringConcatenate(preObjectName, Constant::PREFIX, "FiboExpansion", elliot.marketContext.timeFrameLabel);

        color lineColor = clrLightGray;
        
        Wave *latestWave = elliot.getLatestWave();
        
        CArrayObj *zigZagPointList = &(latestWave.zigZagPointList);
        int zigZagTotal = zigZagPointList.Total();

        this.logger.debug(__FUNCTION__, StringFormat("zigZagTotal = %d", zigZagTotal));

        if (zigZagTotal < 4 || Util::isOdd(zigZagTotal)) {
            return;
        }
        
        ZigZagPoint *zigZagPoint0 = zigZagPointList.At(zigZagTotal - 4);
        ZigZagPoint *zigZagPoint1 = zigZagPointList.At(zigZagTotal - 3);
        ZigZagPoint *zigZagPoint2 = zigZagPointList.At(zigZagTotal - 2);
        
        DrawUtil::setFibonacciExpansion(preObjectName,
            zigZagPoint0.barTime,
            zigZagPoint0.rate,
            zigZagPoint1.barTime,
            zigZagPoint1.rate,
            zigZagPoint2.barTime,
            zigZagPoint2.rate,
            lineColor,
            STYLE_DOT,
            lineSize,
            true);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

};
