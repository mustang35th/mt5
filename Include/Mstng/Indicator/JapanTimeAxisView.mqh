//+------------------------------------------------------------------+
//|                                            JapanTimeAxisView.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_JAPANTIMEAXISVIEW_MQH
#define MSTNG_INDICATOR_JAPANTIMEAXISVIEW_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>

/**
 * チャート上へ日本時間の目安と足の残り時間を表示するクラス。
 */
class JapanTimeAxisView {
public:
    /**
     * デフォルトコンストラクタ。
     */
    JapanTimeAxisView() {
        MarketContext context(_Symbol, (ENUM_TIMEFRAMES)_Period);
        this.initialize(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    JapanTimeAxisView(MarketContext &fromMarketContext) {
        this.initialize(fromMarketContext);
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
    }

    /**
     * 表示オブジェクトを作成する。
     */
    void create() {
        this.update();
    }

    /**
     * 表示を更新する。
     */
    void update() {
        this.drawTimeLabels();
        this.updateRemainingTimeLabel();
    }

    /**
     * 表示オブジェクトを削除する。
     */
    void destroy() {
        this.deleteTimeLabels();
        this.deleteVerticalLines();
        ObjectDelete(this.chartId, this.remainingObjectName);
    }

private:
    /** 表示対象の市場コンテキスト */
    MarketContext marketContext;

    /** 描画対象チャートID */
    long chartId;

    /** 時刻ラベル名プレフィックス */
    string timeLabelPrefix;

    /** 縦線名プレフィックス */
    string verticalLinePrefix;

    /** 残り時間ラベル名 */
    string remainingObjectName;

    /** フォント名 */
    string fontFace;

    /** 時刻ラベル文字サイズ */
    int timeLabelFontSize;

    /** 残り時間文字サイズ */
    int remainingFontSize;

    /** 文字色 */
    color fontColor;

    /** 縦線色 */
    color verticalLineColor;

    /** 日足切り替わり縦線色 */
    color dayLineColor;

    /** 最大表示ラベル数 */
    int maxLabelCount;

    /** H4表示で日付ラベルを表示する最大バー数 */
    int h4DayLabelMaxBars;

    /** H4表示で日足縦線を表示する最大バー数 */
    int h4DayLineMaxBars;

    /** D1表示で週ラベルを表示する最大バー数 */
    int d1WeekLabelMaxBars;

    /** D1表示で月ラベルを表示する最大バー数 */
    int d1MonthLabelMaxBars;

    /** M1表示で15分ラベルを表示する最大バー数 */
    int m1FifteenMinuteLabelMaxBars;

    /** M1表示で1時間ラベルを表示する最大バー数 */
    int m1HourLabelMaxBars;

    /** M1表示でH4ラベルを表示する最大バー数 */
    int m1FourHourLabelMaxBars;

    /** M5表示で1時間ラベルを表示する最大バー数 */
    int m5HourLabelMaxBars;

    /** M5表示でH4ラベルを表示する最大バー数 */
    int m5FourHourLabelMaxBars;

    /** M5表示で日付ラベルを表示する最大バー数 */
    int m5DayLabelMaxBars;

    /** M15表示でH4ラベルを表示する最大バー数 */
    int m15FourHourLabelMaxBars;

    /** M15表示で日付ラベルを表示する最大バー数 */
    int m15DayLabelMaxBars;

    /** M15表示で週ラベルを表示する最大バー数 */
    int m15WeekLabelMaxBars;

    /** H1表示でH4ラベルを表示する最大バー数 */
    int h1FourHourLabelMaxBars;

    /** H1表示で日付ラベルを表示する最大バー数 */
    int h1DayLabelMaxBars;

    /** H1表示で週ラベルを表示する最大バー数 */
    int h1WeekLabelMaxBars;

    /** W1表示で月ラベルを表示する最大バー数 */
    int w1MonthLabelMaxBars;

    /** W1表示で四半期ラベルを表示する最大バー数 */
    int w1QuarterLabelMaxBars;

    /** MN1表示で年ラベルを表示する最大バー数 */
    int mn1YearLabelMaxBars;

    /** MN1表示で5年ラベルを表示する最大バー数 */
    int mn1FiveYearLabelMaxBars;

    /**
     * 初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void initialize(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.chartId = 0;
        this.timeLabelPrefix = Constant::PREFIX_FIXED + "JapanTimeAxisTime";
        this.verticalLinePrefix = Constant::PREFIX_FIXED + "JapanTimeAxisLine";
        this.remainingObjectName = Constant::PREFIX_FIXED + "JapanTimeAxisRemaining";
        this.fontFace = "Meiryo UI";
        this.timeLabelFontSize = 8;
        this.remainingFontSize = 9;
        this.fontColor = clrWhite;
        this.verticalLineColor = clrDimGray;
        this.dayLineColor = clrSilver;
        this.maxLabelCount = 80;
        this.h4DayLabelMaxBars = 120;
        this.h4DayLineMaxBars = 360;
        this.d1WeekLabelMaxBars = 180;
        this.d1MonthLabelMaxBars = 720;
        this.m1FifteenMinuteLabelMaxBars = 180;
        this.m1HourLabelMaxBars = 720;
        this.m1FourHourLabelMaxBars = 2880;
        this.m5HourLabelMaxBars = 180;
        this.m5FourHourLabelMaxBars = 576;
        this.m5DayLabelMaxBars = 1728;
        this.m15FourHourLabelMaxBars = 192;
        this.m15DayLabelMaxBars = 672;
        this.m15WeekLabelMaxBars = 2016;
        this.h1FourHourLabelMaxBars = 168;
        this.h1DayLabelMaxBars = 720;
        this.h1WeekLabelMaxBars = 2160;
        this.w1MonthLabelMaxBars = 104;
        this.w1QuarterLabelMaxBars = 260;
        this.mn1YearLabelMaxBars = 120;
        this.mn1FiveYearLabelMaxBars = 300;
    }

    /**
     * 日本時間ラベルを描画する。
     */
    void drawTimeLabels() {
        this.deleteTimeLabels();
        this.deleteVerticalLines();

        int firstVisibleBar = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR, 0);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS, 0);

        if (firstVisibleBar < 0) {
            return;
        }

        if (visibleBars <= 0) {
            return;
        }

        double drawPrice = this.getBottomLabelPrice();
        int labelCount = 0;
        int lastBar = firstVisibleBar - visibleBars + 1;

        if (lastBar < 0) {
            lastBar = 0;
        }

        for (int i = firstVisibleBar; i >= lastBar; i--) {
            datetime barTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, i);

            if (barTime <= 0) {
                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_M1) {
                this.drawM1TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_M5) {
                this.drawM5TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_M15) {
                this.drawM15TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_H1) {
                this.drawH1TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_H4) {
                this.drawH4TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_D1) {
                this.drawD1TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_W1) {
                this.drawW1TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_MN1) {
                this.drawMn1TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (!this.isJapanTimeLabelBar(barTime)) {
                continue;
            }

            this.drawLowerTimeFrameVerticalLine(barTime);
            this.drawTimeLabel(barTime, drawPrice);
            labelCount++;

            if (labelCount >= this.maxLabelCount) {
                return;
            }
        }
    }

    /**
     * 日本時間ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawTimeLabel(datetime fromBarTime, double fromDrawPrice) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        string labelText = IntegerToString(japanDateTime.hour) + "時";
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間の分単位ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawMinuteTimeLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanMinuteTimeLabel(fromBarTime);
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間のH4ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawFourHourLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanFourHourLabel(fromBarTime);
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間の日付ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawDayLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanDateLabel(fromBarTime);
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間の週ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawWeekLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanWeekLabel(fromBarTime);
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間の月ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawMonthLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanMonthLabel(fromBarTime);
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間の四半期ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawQuarterLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanQuarterLabel(fromBarTime);
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間の年ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawYearLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanYearLabel(fromBarTime);
        string objectName = this.timeLabelPrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 日本時間の目安になる縦線を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     */
    void drawVerticalLine(datetime fromBarTime) {
        this.drawVerticalLine(fromBarTime, this.verticalLineColor, STYLE_DOT, 1);
    }

    /**
     * 日本時間の目安になる縦線を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromLineColor 縦線色
     * @param fromLineStyle 縦線スタイル
     * @param fromLineWidth 縦線幅
     */
    void drawVerticalLine(
        datetime fromBarTime,
        color fromLineColor,
        ENUM_LINE_STYLE fromLineStyle,
        int fromLineWidth
    ) {
        string objectName = this.verticalLinePrefix + IntegerToString((int)fromBarTime);

        if (!ObjectCreate(this.chartId, objectName, OBJ_VLINE, 0, fromBarTime, 0)) {
            return;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromLineColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STYLE, fromLineStyle);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_WIDTH, fromLineWidth);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
    }

    /**
     * 下位足用の日本時間目安縦線を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     */
    void drawLowerTimeFrameVerticalLine(datetime fromBarTime) {
        if (this.marketContext.timeFrame == PERIOD_M5 || this.marketContext.timeFrame == PERIOD_M1) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                this.drawVerticalLine(fromBarTime, this.verticalLineColor, STYLE_SOLID, 1);

                return;
            }
        }

        this.drawVerticalLine(fromBarTime);
    }

    /**
     * M1用の日本時間目安縦線を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     */
    void drawM1VerticalLine(datetime fromBarTime) {
        if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
            this.drawVerticalLine(fromBarTime, this.verticalLineColor, STYLE_SOLID, 1);

            return;
        }

        this.drawVerticalLine(fromBarTime);
    }

    /**
     * 残り時間ラベルを更新する。
     */
    void updateRemainingTimeLabel() {
        if (ObjectFind(this.chartId, this.remainingObjectName) < 0) {
            if (!ObjectCreate(this.chartId, this.remainingObjectName, OBJ_LABEL, 0, 0, 0)) {
                return;
            }
        }

        string labelText = this.formatRemainingTime(this.getRemainingSeconds());

        ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
        ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_XDISTANCE, 280);
        ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_YDISTANCE, 16);
        ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_COLOR, this.fontColor);
        ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_FONTSIZE, this.remainingFontSize);
        ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, this.remainingObjectName, OBJPROP_FONT, this.fontFace);
        ObjectSetString(this.chartId, this.remainingObjectName, OBJPROP_TEXT, labelText);
    }

    /**
     * 時刻ラベルを削除する。
     */
    void deleteTimeLabels() {
        ObjectsDeleteAll(this.chartId, this.timeLabelPrefix, 0, OBJ_TEXT);
    }

    /**
     * 縦線を削除する。
     */
    void deleteVerticalLines() {
        ObjectsDeleteAll(this.chartId, this.verticalLinePrefix, 0, OBJ_VLINE);
    }

    /**
     * 時刻ラベルを出すバーか判定する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return true: ラベルを表示する
     */
    bool isJapanTimeLabelBar(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        if (this.marketContext.timeFrame == PERIOD_M15) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                return true;
            }

            return false;
        }

        if (this.marketContext.timeFrame < PERIOD_H1) {
            if (japanDateTime.min == 0) {
                return true;
            }

            return false;
        }

        if (this.marketContext.timeFrame == PERIOD_H1) {
            return true;
        }

        if (japanDateTime.hour == 0 && japanDateTime.min == 0) {
            return true;
        }

        return false;
    }

    /**
     * M1表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawM1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.m1FifteenMinuteLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_M15)) {
                this.drawM1VerticalLine(fromBarTime);
                this.drawMinuteTimeLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m1HourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H1)) {
                this.drawM1VerticalLine(fromBarTime);
                this.drawTimeLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m1FourHourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                this.drawVerticalLine(fromBarTime, this.verticalLineColor, STYLE_SOLID, 1);
                this.drawFourHourLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_D1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_SOLID, 1);
            this.drawDayLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        return false;
    }

    /**
     * M5表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawM5TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.m5HourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H1)) {
                this.drawLowerTimeFrameVerticalLine(fromBarTime);
                this.drawTimeLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m5FourHourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                this.drawVerticalLine(fromBarTime, this.verticalLineColor, STYLE_SOLID, 1);
                this.drawFourHourLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m5DayLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_D1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_SOLID, 1);
                this.drawDayLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawWeekLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        return false;
    }

    /**
     * M15表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawM15TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.m15FourHourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                this.drawVerticalLine(fromBarTime, this.verticalLineColor, STYLE_SOLID, 1);
                this.drawFourHourLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m15DayLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_D1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawDayLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m15WeekLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawWeekLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawMonthLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        return false;
    }

    /**
     * H1表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawH1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.h1FourHourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                this.drawVerticalLine(fromBarTime);
                this.drawFourHourLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.h1DayLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_D1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawDayLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.h1WeekLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawWeekLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawMonthLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        return false;
    }

    /**
     * H4表示用の日足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawH4TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.h4DayLabelMaxBars && this.isTimeFrameOpenBar(fromBarTime, PERIOD_D1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawDayLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawWeekLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        if (fromVisibleBars <= this.h4DayLineMaxBars && this.isTimeFrameOpenBar(fromBarTime, PERIOD_D1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);

            return true;
        }

        return false;
    }

    /**
     * D1表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawD1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.d1WeekLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawWeekLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.d1MonthLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawMonthLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInQuarter(fromBarTime)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawQuarterLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        return false;
    }

    /**
     * W1表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawW1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.w1MonthLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawMonthLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.w1QuarterLabelMaxBars) {
            if (this.isFirstChartBarInQuarter(fromBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawQuarterLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInYear(fromBarTime)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawYearLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        return false;
    }

    /**
     * MN1表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     * @param fromVisibleBars 表示中のバー数
     * @return true: 目印を描画した
     */
    bool drawMn1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars) {
        if (fromVisibleBars <= this.mn1YearLabelMaxBars) {
            if (this.isFirstChartBarInYear(fromBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawYearLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.mn1FiveYearLabelMaxBars) {
            if (this.isFirstChartBarInYearStep(fromBarTime, 5)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawYearLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInYearStep(fromBarTime, 10)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawYearLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        return false;
    }

    /**
     * 日本時間の日付ラベル文字列を作成する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return 日付ラベル文字列
     */
    string formatJapanDateLabel(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        string weekNames[7] = {"日", "月", "火", "水", "木", "金", "土"};
        string weekName = "";

        if (japanDateTime.day_of_week >= 0 && japanDateTime.day_of_week < 7) {
            weekName = weekNames[japanDateTime.day_of_week];
        }

        return StringFormat("%d/%d(%s)", japanDateTime.mon, japanDateTime.day, weekName);
    }

    /**
     * 日本時間の分単位ラベル文字列を作成する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return 分単位ラベル文字列
     */
    string formatJapanMinuteTimeLabel(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        if (japanDateTime.min == 0) {
            return IntegerToString(japanDateTime.hour) + "時";
        }

        return StringFormat("%d:%02d", japanDateTime.hour, japanDateTime.min);
    }

    /**
     * 日本時間のH4ラベル文字列を作成する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return H4ラベル文字列
     */
    string formatJapanFourHourLabel(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        return StringFormat("H4 %d時", japanDateTime.hour);
    }

    /**
     * 日本時間の週ラベル文字列を作成する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return 週ラベル文字列
     */
    string formatJapanWeekLabel(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        return StringFormat("%d/%d週", japanDateTime.mon, japanDateTime.day);
    }

    /**
     * 日本時間の月ラベル文字列を作成する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return 月ラベル文字列
     */
    string formatJapanMonthLabel(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        return StringFormat("%d月", japanDateTime.mon);
    }

    /**
     * 日本時間の四半期ラベル文字列を作成する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return 四半期ラベル文字列
     */
    string formatJapanQuarterLabel(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);
        int quarter = ((japanDateTime.mon - 1) / 3) + 1;

        return StringFormat("%dQ%d", japanDateTime.year, quarter);
    }

    /**
     * 日本時間の年ラベル文字列を作成する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return 年ラベル文字列
     */
    string formatJapanYearLabel(datetime fromBarTime) {
        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        return StringFormat("%d年", japanDateTime.year);
    }

    /**
     * 指定時間足の開始バーか判定する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromTimeFrame 判定する時間足
     * @return true: 指定時間足の開始バー
     */
    bool isTimeFrameOpenBar(datetime fromBarTime, ENUM_TIMEFRAMES fromTimeFrame) {
        int barIndex = iBarShift(this.marketContext.symbolName, fromTimeFrame, fromBarTime, false);

        if (barIndex < 0) {
            return false;
        }

        datetime openTime = iTime(this.marketContext.symbolName, fromTimeFrame, barIndex);

        if (openTime == fromBarTime) {
            return true;
        }

        return false;
    }

    /**
     * 指定時間足へ切り替わった最初のチャート足か判定する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromTimeFrame 判定する時間足
     * @return true: 指定時間足へ切り替わった最初のチャート足
     */
    bool isFirstChartBarInTimeFrame(datetime fromBarTime, ENUM_TIMEFRAMES fromTimeFrame) {
        int targetBarIndex = iBarShift(this.marketContext.symbolName, fromTimeFrame, fromBarTime, false);

        if (targetBarIndex < 0) {
            return false;
        }

        int chartBarIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, fromBarTime, true);

        if (chartBarIndex < 0) {
            chartBarIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, fromBarTime, false);
        }

        if (chartBarIndex < 0) {
            return false;
        }

        datetime previousChartBarTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, chartBarIndex + 1);

        if (previousChartBarTime <= 0) {
            return this.isTimeFrameOpenBar(fromBarTime, fromTimeFrame);
        }

        int previousTargetBarIndex = iBarShift(this.marketContext.symbolName, fromTimeFrame, previousChartBarTime, false);

        if (previousTargetBarIndex < 0) {
            return false;
        }

        if (previousTargetBarIndex != targetBarIndex) {
            return true;
        }

        return false;
    }

    /**
     * 四半期へ切り替わった最初のチャート足か判定する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return true: 四半期へ切り替わった最初のチャート足
     */
    bool isFirstChartBarInQuarter(datetime fromBarTime) {
        if (!this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1)) {
            return false;
        }

        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        if (japanDateTime.mon == 1) {
            return true;
        }

        if (japanDateTime.mon == 4) {
            return true;
        }

        if (japanDateTime.mon == 7) {
            return true;
        }

        if (japanDateTime.mon == 10) {
            return true;
        }

        return false;
    }

    /**
     * 年へ切り替わった最初のチャート足か判定する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return true: 年へ切り替わった最初のチャート足
     */
    bool isFirstChartBarInYear(datetime fromBarTime) {
        if (!this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1)) {
            return false;
        }

        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        if (japanDateTime.mon == 1) {
            return true;
        }

        return false;
    }

    /**
     * 指定年数の刻みへ切り替わった最初のチャート足か判定する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromYearStep 年数の刻み
     * @return true: 指定年数の刻みへ切り替わった最初のチャート足
     */
    bool isFirstChartBarInYearStep(datetime fromBarTime, int fromYearStep) {
        if (fromYearStep <= 0) {
            return false;
        }

        if (!this.isFirstChartBarInYear(fromBarTime)) {
            return false;
        }

        datetime japanTime = TimeJapanUtil::getJapanTime(fromBarTime);
        MqlDateTime japanDateTime;
        TimeToStruct(japanTime, japanDateTime);

        if (japanDateTime.year % fromYearStep == 0) {
            return true;
        }

        return false;
    }

    /**
     * 時刻ラベルの描画価格を取得する。
     *
     * @return 描画価格
     */
    double getBottomLabelPrice() {
        double priceMin = ChartGetDouble(this.chartId, CHART_PRICE_MIN, 0);
        double priceMax = ChartGetDouble(this.chartId, CHART_PRICE_MAX, 0);

        if (priceMax <= priceMin) {
            return SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_BID);
        }

        return priceMin + ((priceMax - priceMin) * 0.02);
    }

    /**
     * 現在足の残り秒数を取得する。
     *
     * @return 残り秒数
     */
    int getRemainingSeconds() {
        datetime barTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);
        int periodSeconds = PeriodSeconds(this.marketContext.timeFrame);

        if (barTime <= 0) {
            return 0;
        }

        if (periodSeconds <= 0) {
            return 0;
        }

        datetime currentTime = TimeTradeServer();

        if (currentTime <= 0) {
            currentTime = TimeCurrent();
        }

        int remainingSeconds = (int)(barTime + periodSeconds - currentTime);

        if (remainingSeconds < 0) {
            remainingSeconds = 0;
        }

        return remainingSeconds;
    }

    /**
     * 残り秒数を表示文字列へ変換する。
     *
     * @param fromRemainingSeconds 残り秒数
     * @return 表示文字列
     */
    string formatRemainingTime(int fromRemainingSeconds) {
        if (fromRemainingSeconds >= 3600) {
            int hour = fromRemainingSeconds / 3600;
            int minute = (fromRemainingSeconds % 3600) / 60;
            int second = fromRemainingSeconds % 60;

            return StringFormat("残り: %d:%02d:%02d", hour, minute, second);
        }

        if (fromRemainingSeconds >= 60) {
            int minute = fromRemainingSeconds / 60;
            int second = fromRemainingSeconds % 60;

            return StringFormat("残り: %d分%02d秒", minute, second);
        }

        return "残り: " + IntegerToString(fromRemainingSeconds) + "秒";
    }
};

#endif
