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
 * 日本時間軸の描画済みオブジェクトと反映済み属性を保持する。
 */
struct JapanTimeAxisObjectState {
    /** 対応するサーバー時刻。 */
    datetime barTime;

    /** 縦線の場合true、時刻ラベルの場合false。 */
    bool isLine;

    /** 描画オブジェクト名。 */
    string objectName;

    /** 今回の描画で使用する場合true。 */
    bool isUsed;

    /** 固定設定と表示属性の反映が完了している場合true。 */
    bool isReady;

    /** 時刻ラベルの反映済み描画価格。 */
    double price;

    /** 時刻ラベルの反映済み表示文字。 */
    string text;

    /** 縦線の反映済み色。 */
    color lineColor;

    /** 縦線の反映済み線種。 */
    ENUM_LINE_STYLE lineStyle;

    /** 縦線の反映済み幅。 */
    int lineWidth;
};

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
        this.initialize(
            context,
            Constant::PREFIX_FIXED + "JapanTimeAxis"
        );
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    JapanTimeAxisView(MarketContext &fromMarketContext) {
        this.initialize(
            fromMarketContext,
            Constant::PREFIX_FIXED + "JapanTimeAxis"
        );
    }

    /**
     * 市場コンテキストとオブジェクト接頭辞を指定して初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     * @param fromObjectPrefix オブジェクト名を分離する接頭辞
     */
    JapanTimeAxisView(
        MarketContext &fromMarketContext,
        const string fromObjectPrefix
    ) {
        this.initialize(fromMarketContext, fromObjectPrefix);
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        if (this.marketContext.symbolName != fromMarketContext.symbolName
                || this.marketContext.timeFrame != fromMarketContext.timeFrame) {
            this.timeAxisViewReady = false;
            this.timeAxisUpdatePending = true;
        }

        this.marketContext = fromMarketContext;
    }

    /**
     * 表示オブジェクトを作成する。
     */
    void create() {
        this.deleteTimeLabels();
        this.deleteVerticalLines();
        ArrayFree(this.timeAxisObjects);
        this.timeAxisViewReady = false;

        this.update();
    }

    /**
     * 全体表示を更新し、共有利用側からの履歴再読込も再判定する。
     */
    void update() {
        this.updateTimeAxis(true);
        this.updateRemainingTime();
    }

    /**
     * 日本時間の目安と縦線を更新する。
     *
     * @param fromForce 履歴再読込などで同じ画面でも再判定する場合true。
     */
    void updateTimeAxis(const bool fromForce = false) {
        this.lastUpdateMode = "通常更新";
        if (fromForce) {
            this.lastUpdateMode = "全体更新";
        } else if (this.timeAxisUpdatePending) {
            this.lastUpdateMode = "再試行";
        }

        this.drawTimeLabels(fromForce);
    }

    /**
     * 直前の時間軸更新が完了しているか取得する。
     *
     * @return 同じ画面の確認で更新を省略した場合もtrue
     */
    bool isTimeAxisUpdateSucceeded() {
        return this.timeAxisViewReady && !this.timeAxisUpdatePending;
    }

    /**
     * 直前の残り時間更新でデータ取得と描画が成功したか取得する。
     *
     * @return データが有効で、文字変更不要または描画成功の場合true
     */
    bool isRemainingTimeUpdateSucceeded() {
        return this.remainingTimeUpdateSucceeded;
    }

    /**
     * 直前の時間軸更新処理の種類を取得する。
     *
     * @return 計測表示用の更新種別
     */
    string getLastUpdateMode() {
        return this.lastUpdateMode;
    }

    /**
     * データ取得または描画の再試行待ちの場合だけ、日本時間軸を更新する。
     */
    void retryTimeAxisUpdate() {
        if (this.timeAxisUpdatePending) {
            this.updateTimeAxis();
        }
    }

    /**
     * 現在足の残り時間を更新する。
     */
    void updateRemainingTime() {
        this.remainingTimeUpdateSucceeded = false;
        this.remainingTimeDataReady = false;
        this.updateRemainingTimeLabel();
    }

    /**
     * 表示オブジェクトを削除する。
     */
    void destroy() {
        this.deleteTimeLabels();
        this.deleteVerticalLines();
        ObjectDelete(this.chartId, this.remainingObjectName);
        ArrayFree(this.timeAxisObjects);
        ArrayFree(this.timeAxisBarTimes);
        this.timeAxisUpdatePending = false;
        this.timeAxisViewReady = false;
        this.remainingLabelReady = false;
        this.remainingLabelText = "";
        this.remainingTimeUpdateSucceeded = false;
        this.remainingTimeDataReady = false;
        this.lastUpdateMode = "未計測";
    }

private:
    /** 直前の残り時間更新で、データ取得と描画が成功した場合true。 */
    bool remainingTimeUpdateSucceeded;

    /** 今回の残り秒数計算に必要な時刻・期間を取得できた場合true。 */
    bool remainingTimeDataReady;

    /** 直前のupdateTimeAxisで実行した処理の種類。 */
    string lastUpdateMode;

    /** 時刻と種別の順に保持する描画オブジェクト状態。 */
    JapanTimeAxisObjectState timeAxisObjects[];

    /** 可視範囲と直前の足時刻を古い順で保持する作業配列。 */
    datetime timeAxisBarTimes[];

    /** データ取得または描画の失敗により時間軸の再更新が必要な場合true。 */
    bool timeAxisUpdatePending;

    /** 前回の画面状態でデータ取得と描画が完了した場合true。 */
    bool timeAxisViewReady;

    /** 描画済み画面の左端バー位置。 */
    int lastFirstVisibleBar;

    /** 描画済み画面の表示バー数。 */
    int lastVisibleBars;

    /** 描画時の取得可能バー数。 */
    int lastTotalBars;

    /** 描画時の最新足時刻。 */
    datetime lastLatestBarTime;

    /** 描画済み時刻ラベルの価格位置。 */
    double lastDrawPrice;

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

    /** 残り時間ラベルの固定設定と初回文字の反映が完了している場合true。 */
    bool remainingLabelReady;

    /** 残り時間ラベルへ最後に反映した表示文字。 */
    string remainingLabelText;

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
     * @param fromObjectPrefix オブジェクト名を分離する接頭辞
     */
    void initialize(
        MarketContext &fromMarketContext,
        const string fromObjectPrefix
    ) {
        this.marketContext = fromMarketContext;
        this.chartId = 0;
        ArraySetAsSeries(this.timeAxisBarTimes, false);
        this.timeAxisUpdatePending = false;
        this.timeAxisViewReady = false;
        this.lastFirstVisibleBar = -1;
        this.lastVisibleBars = 0;
        this.lastTotalBars = 0;
        this.lastLatestBarTime = 0;
        this.lastDrawPrice = 0.0;
        string objectPrefix = fromObjectPrefix;
        StringTrimLeft(objectPrefix);
        StringTrimRight(objectPrefix);

        if (objectPrefix == "") {
            objectPrefix = Constant::PREFIX_FIXED + "JapanTimeAxis";
        }

        this.timeLabelPrefix = objectPrefix + "Time";
        this.verticalLinePrefix = objectPrefix + "Line";
        this.remainingObjectName = objectPrefix + "Remaining";
        this.remainingLabelReady = false;
        this.remainingLabelText = "";
        this.remainingTimeUpdateSucceeded = false;
        this.remainingTimeDataReady = false;
        this.lastUpdateMode = "未計測";
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
     * 画面状態が変わった場合、または取得・描画の再試行時に日本時間軸を更新する。
     *
     * @param fromForce 同じ画面状態でも再判定する場合true。
     */
    void drawTimeLabels(const bool fromForce) {
        int firstVisibleBar = (int)ChartGetInteger(this.chartId, CHART_FIRST_VISIBLE_BAR, 0);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_VISIBLE_BARS, 0);
        bool hasVisibleRange = firstVisibleBar >= 0 && visibleBars > 0;
        int totalBars = 0;
        datetime latestBarTime = 0;
        double drawPrice = 0.0;
        if (hasVisibleRange) {
            totalBars = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);
            latestBarTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);
            if (totalBars <= 0 || latestBarTime <= 0) {
                this.timeAxisViewReady = false;
                this.timeAxisUpdatePending = true;

                return;
            }

            drawPrice = this.getBottomLabelPrice();
        }

        if (!fromForce && this.timeAxisViewReady && !this.timeAxisUpdatePending
                && this.lastFirstVisibleBar == firstVisibleBar
                && this.lastVisibleBars == visibleBars
                && this.lastTotalBars == totalBars
                && this.lastLatestBarTime == latestBarTime
                && this.lastDrawPrice == drawPrice
                && this.areTimeAxisObjectsReady(true)) {
            this.lastUpdateMode = "確認のみ";

            return;
        }

        this.timeAxisViewReady = false;
        this.timeAxisUpdatePending = false;
        int startIndex = 0;
        int copiedBarCount = 0;
        if (hasVisibleRange && !this.copyVisibleBarTimes(
                firstVisibleBar, visibleBars, totalBars, startIndex, copiedBarCount)) {
            this.timeAxisUpdatePending = true;

            return;
        }

        int objectCount = ArraySize(this.timeAxisObjects);
        for (int i = 0; i < objectCount; i++) {
            this.timeAxisObjects[i].isUsed = false;
        }

        int labelCount = 0;
        for (int i = startIndex; i < copiedBarCount; i++) {
            datetime barTime = this.timeAxisBarTimes[i];
            datetime previousBarTime = 0;
            if (i > 0) {
                previousBarTime = this.timeAxisBarTimes[i - 1];
            }

            if (this.marketContext.timeFrame == PERIOD_M1) {
                this.drawM1TimeFrameMark(barTime, drawPrice, visibleBars);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_M5) {
                this.drawM5TimeFrameMark(barTime, drawPrice, visibleBars, previousBarTime);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_M15) {
                this.drawM15TimeFrameMark(barTime, drawPrice, visibleBars, previousBarTime);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_H1) {
                this.drawH1TimeFrameMark(barTime, drawPrice, visibleBars, previousBarTime);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_H4) {
                this.drawH4TimeFrameMark(barTime, drawPrice, visibleBars, previousBarTime);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_D1) {
                this.drawD1TimeFrameMark(barTime, drawPrice, visibleBars, previousBarTime);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_W1) {
                this.drawW1TimeFrameMark(barTime, drawPrice, visibleBars, previousBarTime);

                continue;
            }

            if (this.marketContext.timeFrame == PERIOD_MN1) {
                this.drawMn1TimeFrameMark(barTime, drawPrice, visibleBars, previousBarTime);

                continue;
            }

            if (!this.isJapanTimeLabelBar(barTime)) {
                continue;
            }

            this.drawLowerTimeFrameVerticalLine(barTime);
            this.drawTimeLabel(barTime, drawPrice);
            labelCount++;

            if (labelCount >= this.maxLabelCount) {
                break;
            }
        }

        this.deleteUnusedTimeAxisObjects();
        if (this.timeAxisUpdatePending || !this.areTimeAxisObjectsReady(false)) {
            this.timeAxisUpdatePending = true;

            return;
        }

        this.lastFirstVisibleBar = firstVisibleBar;
        this.lastVisibleBars = visibleBars;
        this.lastTotalBars = totalBars;
        this.lastLatestBarTime = latestBarTime;
        this.lastDrawPrice = drawPrice;
        this.timeAxisViewReady = true;
    }

    /**
     * 描画オブジェクトの反映完了と、必要時には削除されていないことを確認する。
     *
     * @param fromCheckExistence 同じ画面の更新を省略する前に存在確認する場合true。
     * @return 全オブジェクトが今回使用され、設定を反映できている場合true。
     */
    bool areTimeAxisObjectsReady(const bool fromCheckExistence) {
        int objectCount = ArraySize(this.timeAxisObjects);
        for (int i = 0; i < objectCount; i++) {
            if (!this.timeAxisObjects[i].isUsed || !this.timeAxisObjects[i].isReady) {
                return false;
            }

            if (fromCheckExistence && ObjectFind(this.chartId, this.timeAxisObjects[i].objectName) < 0) {
                return false;
            }
        }

        return true;
    }

    /**
     * 可視範囲と存在する直前の1本をまとめて取得する。
     * 全件が揃わない場合はfalseを返し、描画済みオブジェクトを維持する。
     *
     * @param fromFirstVisibleBar 画面左端のバー位置。
     * @param fromVisibleBars 画面の表示バー数。
     * @param fromTotalBars 検索時点で取得可能なバー数。
     * @param fromStartIndex 描画対象が始まる配列位置を返す。
     * @param fromCopiedBarCount 取得済み本数を返す。表示対象がない場合は0。
     * @return 必要な足時刻をすべて取得できた場合true。
     */
    bool copyVisibleBarTimes(
        const int fromFirstVisibleBar,
        const int fromVisibleBars,
        const int fromTotalBars,
        int &fromStartIndex,
        int &fromCopiedBarCount
    ) {
        fromStartIndex = 0;
        fromCopiedBarCount = 0;
        if (fromTotalBars <= 0) {
            return false;
        }

        int lastBar = fromFirstVisibleBar - fromVisibleBars + 1;
        if (lastBar < 0) {
            lastBar = 0;
        }

        int firstBar = fromFirstVisibleBar;
        if (firstBar >= fromTotalBars) {
            firstBar = fromTotalBars - 1;
        }

        if (lastBar > firstBar) {
            return true;
        }

        int requestedCount = firstBar - lastBar + 1;
        if (firstBar < fromTotalBars - 1) {
            requestedCount++;
            fromStartIndex = 1;
        }

        if (ArrayResize(this.timeAxisBarTimes, requestedCount, 256) != requestedCount) {
            return false;
        }

        int copiedCount = CopyTime(
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            lastBar,
            requestedCount,
            this.timeAxisBarTimes
        );
        if (copiedCount != requestedCount) {
            return false;
        }

        for (int i = 0; i < copiedCount; i++) {
            if (this.timeAxisBarTimes[i] <= 0) {
                return false;
            }
        }

        fromCopiedBarCount = copiedCount;

        return true;
    }

    /**
     * 時刻と種別を二分探索し、今回使用する描画状態を取得または追加する。
     *
     * @param fromBarTime サーバー時刻のバー時刻。
     * @param fromIsLine 縦線の場合true。
     * @return 描画状態の位置。確保失敗の場合は-1。
     */
    int getTimeAxisObjectIndex(const datetime fromBarTime, const bool fromIsLine) {
        int objectCount = ArraySize(this.timeAxisObjects);
        int leftIndex = 0;
        int rightIndex = objectCount - 1;
        while (leftIndex <= rightIndex) {
            int middleIndex = leftIndex + (rightIndex - leftIndex) / 2;
            datetime barTime = this.timeAxisObjects[middleIndex].barTime;
            bool isLine = this.timeAxisObjects[middleIndex].isLine;
            if (barTime == fromBarTime && isLine == fromIsLine) {
                this.timeAxisObjects[middleIndex].isUsed = true;

                return middleIndex;
            }

            if (barTime < fromBarTime || (barTime == fromBarTime && !isLine && fromIsLine)) {
                leftIndex = middleIndex + 1;
            } else {
                rightIndex = middleIndex - 1;
            }
        }

        if (ArrayResize(this.timeAxisObjects, objectCount + 1, 32) != objectCount + 1) {
            this.timeAxisUpdatePending = true;

            return -1;
        }

        for (int i = objectCount; i > leftIndex; i--) {
            this.timeAxisObjects[i] = this.timeAxisObjects[i - 1];
        }

        string objectPrefix = this.timeLabelPrefix;
        if (fromIsLine) {
            objectPrefix = this.verticalLinePrefix;
        }

        this.timeAxisObjects[leftIndex].barTime = fromBarTime;
        this.timeAxisObjects[leftIndex].isLine = fromIsLine;
        this.timeAxisObjects[leftIndex].objectName = objectPrefix + IntegerToString((int)fromBarTime);
        this.timeAxisObjects[leftIndex].isUsed = true;
        this.timeAxisObjects[leftIndex].isReady = false;
        this.timeAxisObjects[leftIndex].price = 0.0;
        this.timeAxisObjects[leftIndex].text = "";
        this.timeAxisObjects[leftIndex].lineColor = clrNONE;
        this.timeAxisObjects[leftIndex].lineStyle = STYLE_DOT;
        this.timeAxisObjects[leftIndex].lineWidth = 0;

        return leftIndex;
    }

    /**
     * 今回使わなかった描画オブジェクトだけ削除し、保持配列を一度だけ詰める。
     * 削除に失敗したオブジェクトは保持し、次回更新で再試行する。
     */
    void deleteUnusedTimeAxisObjects() {
        int objectCount = ArraySize(this.timeAxisObjects);
        int writeIndex = 0;
        for (int i = 0; i < objectCount; i++) {
            if (!this.timeAxisObjects[i].isUsed) {
                string objectName = this.timeAxisObjects[i].objectName;
                if (ObjectFind(this.chartId, objectName) < 0
                        || ObjectDelete(this.chartId, objectName)) {
                    continue;
                }
            }

            if (writeIndex != i) {
                this.timeAxisObjects[writeIndex] = this.timeAxisObjects[i];
            }

            writeIndex++;
        }

        if (writeIndex != objectCount) {
            ArrayResize(this.timeAxisObjects, writeIndex);
        }
    }

    /**
     * 時刻ラベルを再利用し、描画価格と文字を変更時だけ反映する。
     * 作成・設定に失敗した場合は反映済み状態を進めず、次回更新で再試行する。
     *
     * @param fromBarTime サーバー時刻のバー時刻。
     * @param fromDrawPrice 描画価格。
     * @param fromText 表示文字。
     */
    void updateTimeLabel(const datetime fromBarTime, const double fromDrawPrice, const string fromText) {
        int objectIndex = this.getTimeAxisObjectIndex(fromBarTime, false);
        if (objectIndex < 0) {
            return;
        }

        string objectName = this.timeAxisObjects[objectIndex].objectName;
        if (ObjectFind(this.chartId, objectName) < 0) {
            this.timeAxisObjects[objectIndex].isReady = false;

            if (!ObjectCreate(this.chartId, objectName, OBJ_TEXT, 0, fromBarTime, fromDrawPrice)) {
                return;
            }
        }

        bool initializeProperties = !this.timeAxisObjects[objectIndex].isReady;
        this.timeAxisObjects[objectIndex].isReady = false;
        if (initializeProperties) {
            if (!ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.fontColor)
                    || !ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, this.timeLabelFontSize)
                    || !ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER)
                    || !ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true)
                    || !ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontFace)) {
                return;
            }
        }

        if ((initializeProperties || this.timeAxisObjects[objectIndex].price != fromDrawPrice)
                && !ObjectMove(this.chartId, objectName, 0, fromBarTime, fromDrawPrice)) {
            return;
        }

        if ((initializeProperties || this.timeAxisObjects[objectIndex].text != fromText)
                && !ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText)) {
            return;
        }

        this.timeAxisObjects[objectIndex].price = fromDrawPrice;
        this.timeAxisObjects[objectIndex].text = fromText;
        this.timeAxisObjects[objectIndex].isReady = true;
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

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
    }

    /**
     * 日本時間の分単位ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawMinuteTimeLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanMinuteTimeLabel(fromBarTime);

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
    }

    /**
     * 日本時間のH4ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawFourHourLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanFourHourLabel(fromBarTime);

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
    }

    /**
     * 日本時間の日付ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawDayLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanDateLabel(fromBarTime);

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
    }

    /**
     * 日本時間の週ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawWeekLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanWeekLabel(fromBarTime);

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
    }

    /**
     * 日本時間の月ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawMonthLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanMonthLabel(fromBarTime);

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
    }

    /**
     * 日本時間の四半期ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawQuarterLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanQuarterLabel(fromBarTime);

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
    }

    /**
     * 日本時間の年ラベルを描画する。
     *
     * @param fromBarTime サーバー時刻のバー時刻
     * @param fromDrawPrice 描画価格
     */
    void drawYearLabel(datetime fromBarTime, double fromDrawPrice) {
        string labelText = this.formatJapanYearLabel(fromBarTime);

        this.updateTimeLabel(fromBarTime, fromDrawPrice, labelText);
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
        int objectIndex = this.getTimeAxisObjectIndex(fromBarTime, true);
        if (objectIndex < 0) {
            return;
        }

        string objectName = this.timeAxisObjects[objectIndex].objectName;
        if (ObjectFind(this.chartId, objectName) < 0) {
            this.timeAxisObjects[objectIndex].isReady = false;

            if (!ObjectCreate(this.chartId, objectName, OBJ_VLINE, 0, fromBarTime, 0)) {
                return;
            }
        }

        bool initializeProperties = !this.timeAxisObjects[objectIndex].isReady;
        this.timeAxisObjects[objectIndex].isReady = false;
        if (initializeProperties) {
            if (!ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, true)
                    || !ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true)) {
                return;
            }
        }

        if ((initializeProperties || this.timeAxisObjects[objectIndex].lineColor != fromLineColor)
                && !ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromLineColor)) {
            return;
        }

        if ((initializeProperties || this.timeAxisObjects[objectIndex].lineStyle != fromLineStyle)
                && !ObjectSetInteger(this.chartId, objectName, OBJPROP_STYLE, fromLineStyle)) {
            return;
        }

        if ((initializeProperties || this.timeAxisObjects[objectIndex].lineWidth != fromLineWidth)
                && !ObjectSetInteger(this.chartId, objectName, OBJPROP_WIDTH, fromLineWidth)) {
            return;
        }

        this.timeAxisObjects[objectIndex].lineColor = fromLineColor;
        this.timeAxisObjects[objectIndex].lineStyle = fromLineStyle;
        this.timeAxisObjects[objectIndex].lineWidth = fromLineWidth;
        this.timeAxisObjects[objectIndex].isReady = true;
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
     *
     * 固定設定は初回と削除後の再作成時に反映し、文字は変更時だけ更新する。
     * 設定に失敗した場合はキャッシュを確定せず、次回更新で再試行する。
     */
    void updateRemainingTimeLabel() {
        if (ObjectFind(this.chartId, this.remainingObjectName) < 0) {
            this.remainingLabelReady = false;

            if (!ObjectCreate(this.chartId, this.remainingObjectName, OBJ_LABEL, 0, 0, 0)) {
                return;
            }
        }

        if (!this.remainingLabelReady) {
            if (!ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_CORNER, CORNER_RIGHT_LOWER)
                    || !ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_XDISTANCE, 280)
                    || !ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_YDISTANCE, 16)
                    || !ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_COLOR, this.fontColor)
                    || !ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_FONTSIZE, this.remainingFontSize)
                    || !ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(this.chartId, this.remainingObjectName, OBJPROP_HIDDEN, true)
                    || !ObjectSetString(this.chartId, this.remainingObjectName, OBJPROP_FONT, this.fontFace)) {
                return;
            }
        }

        string labelText = this.formatRemainingTime(this.getRemainingSeconds());
        if (this.remainingLabelReady && this.remainingLabelText == labelText) {
            this.remainingTimeUpdateSucceeded = this.remainingTimeDataReady;

            return;
        }

        if (ObjectSetString(this.chartId, this.remainingObjectName, OBJPROP_TEXT, labelText)) {
            this.remainingLabelText = labelText;
            this.remainingLabelReady = true;
            this.remainingTimeUpdateSucceeded = this.remainingTimeDataReady;
        }
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 目印を描画した
     */
    bool drawM5TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars, datetime fromPreviousBarTime) {
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

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 目印を描画した
     */
    bool drawM15TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars, datetime fromPreviousBarTime) {
        if (fromVisibleBars <= this.m15FourHourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                this.drawVerticalLine(fromBarTime, this.verticalLineColor, STYLE_SOLID, 1);
                this.drawFourHourLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m15DayLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_D1, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawDayLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.m15WeekLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawWeekLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 目印を描画した
     */
    bool drawH1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars, datetime fromPreviousBarTime) {
        if (fromVisibleBars <= this.h1FourHourLabelMaxBars) {
            if (this.isTimeFrameOpenBar(fromBarTime, PERIOD_H4)) {
                this.drawVerticalLine(fromBarTime);
                this.drawFourHourLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.h1DayLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_D1, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawDayLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.h1WeekLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawWeekLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 目印を描画した
     */
    bool drawH4TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars, datetime fromPreviousBarTime) {
        if (fromVisibleBars <= this.h4DayLabelMaxBars && this.isTimeFrameOpenBar(fromBarTime, PERIOD_D1)) {
            this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
            this.drawDayLabel(fromBarTime, fromDrawPrice);

            return true;
        }

        if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 目印を描画した
     */
    bool drawD1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars, datetime fromPreviousBarTime) {
        if (fromVisibleBars <= this.d1WeekLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_W1, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawWeekLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.d1MonthLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawMonthLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInQuarter(fromBarTime, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 目印を描画した
     */
    bool drawW1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars, datetime fromPreviousBarTime) {
        if (fromVisibleBars <= this.w1MonthLabelMaxBars) {
            if (this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawMonthLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.w1QuarterLabelMaxBars) {
            if (this.isFirstChartBarInQuarter(fromBarTime, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawQuarterLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInYear(fromBarTime, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 目印を描画した
     */
    bool drawMn1TimeFrameMark(datetime fromBarTime, double fromDrawPrice, int fromVisibleBars, datetime fromPreviousBarTime) {
        if (fromVisibleBars <= this.mn1YearLabelMaxBars) {
            if (this.isFirstChartBarInYear(fromBarTime, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawYearLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (fromVisibleBars <= this.mn1FiveYearLabelMaxBars) {
            if (this.isFirstChartBarInYearStep(fromBarTime, 5, fromPreviousBarTime)) {
                this.drawVerticalLine(fromBarTime, this.dayLineColor, STYLE_DOT, 1);
                this.drawYearLabel(fromBarTime, fromDrawPrice);

                return true;
            }

            return false;
        }

        if (this.isFirstChartBarInYearStep(fromBarTime, 10, fromPreviousBarTime)) {
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
            this.timeAxisUpdatePending = true;

            return false;
        }

        datetime openTime = iTime(this.marketContext.symbolName, fromTimeFrame, barIndex);
        if (openTime <= 0) {
            this.timeAxisUpdatePending = true;

            return false;
        }

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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 指定時間足へ切り替わった最初のチャート足
     */
    bool isFirstChartBarInTimeFrame(datetime fromBarTime, ENUM_TIMEFRAMES fromTimeFrame, datetime fromPreviousBarTime) {
        int targetBarIndex = iBarShift(this.marketContext.symbolName, fromTimeFrame, fromBarTime, false);

        if (targetBarIndex < 0) {
            this.timeAxisUpdatePending = true;

            return false;
        }

        if (fromPreviousBarTime <= 0) {
            return this.isTimeFrameOpenBar(fromBarTime, fromTimeFrame);
        }

        int previousTargetBarIndex = iBarShift(this.marketContext.symbolName, fromTimeFrame, fromPreviousBarTime, false);

        if (previousTargetBarIndex < 0) {
            this.timeAxisUpdatePending = true;

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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 四半期へ切り替わった最初のチャート足
     */
    bool isFirstChartBarInQuarter(datetime fromBarTime, datetime fromPreviousBarTime) {
        if (!this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 年へ切り替わった最初のチャート足
     */
    bool isFirstChartBarInYear(datetime fromBarTime, datetime fromPreviousBarTime) {
        if (!this.isFirstChartBarInTimeFrame(fromBarTime, PERIOD_MN1, fromPreviousBarTime)) {
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
     * @param fromPreviousBarTime 直前のチャート足時刻。存在しない場合は0。
     * @return true: 指定年数の刻みへ切り替わった最初のチャート足
     */
    bool isFirstChartBarInYearStep(datetime fromBarTime, int fromYearStep, datetime fromPreviousBarTime) {
        if (fromYearStep <= 0) {
            return false;
        }

        if (!this.isFirstChartBarInYear(fromBarTime, fromPreviousBarTime)) {
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

        this.remainingTimeDataReady = currentTime > 0;
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
