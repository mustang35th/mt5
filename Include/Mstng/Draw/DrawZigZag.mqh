//+------------------------------------------------------------------+
//|                                                   DrawZigZag.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Draw\DrawBase.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>

class DrawZigZag : public DrawBase {
public:

    DrawZigZag() {
    }

    ~DrawZigZag() {
    }

    void draw(ElliotAll &fromElliotAll) {
        this.logger.setMarketContext(fromElliotAll.marketContext);

        if (fromElliotAll.timeFrame < PERIOD_MN1) {
            Elliot *elliotHigher = fromElliotAll.getElliot(fromElliotAll.timeFrame, 1);

            if (elliotHigher != NULL) {
                this.draw(elliotHigher, true, 3, true);
            }
        }

        Elliot *elliot = fromElliotAll.getElliot(fromElliotAll.timeFrame);

        if (elliot != NULL) {
            this.draw(elliot, false, 1);
        }
    }

private:
    void draw(Elliot &elliot, bool isOrg, int lineSize, bool isUpper = false) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.logger.debug(__FUNCTION__, StringFormat("elliot = %s", elliot.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("isOrg = %s", (string)isOrg));
        this.logger.debug(__FUNCTION__, StringFormat("lineSize = %d", lineSize));
        this.logger.debug(__FUNCTION__, StringFormat("isUpper = %s", (string)isUpper));

        string preObjectName;
        StringConcatenate(preObjectName, "ZigZag", elliot.timeFrameLabel);

        CArrayObj *waveList = &(elliot.waveList);
        int waveListTotal = waveList.Total();

        this.logger.debug(__FUNCTION__, StringFormat("waveListTotal = %d", waveListTotal));

        for (int i = 0; i < waveListTotal; i++) {
            Wave *wave = waveList.At(i);
            CArrayObj *zigZagPointList;

            if (isOrg && elliot.timeFrame != PERIOD_MN1) {
                zigZagPointList = &(wave.orgZigZagPointList);
            } else {
                zigZagPointList = &(wave.zigZagPointList);
            }

            LogUtil::printZigZagPointList(this.logger, __FUNCTION__, zigZagPointList);

            int zigZagPointCount = zigZagPointList.Total();

            for (int j = 0; j < zigZagPointCount - 1; j++) {
                string objectName;
                StringConcatenate(
                    objectName,
                    preObjectName,
                    "_i",
                    StringUtil::zeroPadding(i, 2),
                    "_j",
                    StringUtil::zeroPadding(j, 2)
                );

                this.logger.debug(__FUNCTION__, objectName);

                ZigZagPoint *zigZagPointFrom = zigZagPointList.At(j);
                ZigZagPoint *zigZagPointTo = zigZagPointList.At(j + 1);

                double rateFrom = zigZagPointFrom.rate;
                double rateTo = zigZagPointTo.rate;
                bool isBuy = this.isBuy(rateFrom, rateTo);
                color lineColor = this.getLineColor(isBuy, isUpper);
                datetime datetimeFrom = zigZagPointFrom.barTime;
                datetime datetimeTo = zigZagPointTo.barTime;

                if (isUpper) {
                    datetimeFrom = this.getDatetime(elliot.timeFrame, datetimeFrom, rateFrom, isBuy, true);
                    datetimeTo = this.getDatetime(elliot.timeFrame, datetimeTo, rateTo, isBuy, false);
                }

                DrawUtil::setTrendLine(
                    objectName,
                    datetimeFrom,
                    rateFrom,
                    datetimeTo,
                    rateTo,
                    lineColor,
                    STYLE_SOLID,
                    lineSize,
                    false
                );
            }
        }

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 描画色を取得する。
     *
     * @param isBuy 上昇波の場合true
     * @param isUpper 上位足描画の場合true
     * @return 描画色
     */
    color getLineColor(bool isBuy, bool isUpper) {
        if (isBuy) {
            if (isUpper) {
                return clrBlue;
            }

            return clrDodgerBlue;
        }

        if (isUpper) {
            return clrRed;
        }

        return clrMagenta;
    }

};
