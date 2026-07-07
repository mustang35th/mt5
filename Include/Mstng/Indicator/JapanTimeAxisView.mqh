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

            if (this.marketContext.timeFrame == PERIOD_H1) {
                this.drawH1TimeFrameMark(barTime);

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
     * H1表示用の時間足切り替わり目印を描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @return true: 目印を描画した
     */
    bool drawH1TimeFrameMark(datetime fromBarTime) {
        if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_D1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_SOLID, 1);

            return true;
        }

        if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
            this.drawVerticalLine(fromBarTime);

            return true;
        }

        return false;
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
