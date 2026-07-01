//+------------------------------------------------------------------+
//|                                               Ema200Indicator.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_EMA200_INDICATOR_MQH
#define MSTNG_EMA200_INDICATOR_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Draw\DrawUtil.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>

/**
 * EMA200表示用インジケータクラス
 */
class Ema200Indicator {
public:
    /** 表示対象の市場コンテキスト */
    MarketContext marketContext;

    /**
     * コンストラクタ
     *
     * @param fromSymbolName 通貨ペア
     * @param fromChartTimeFrame チャート時間足
     */
    Ema200Indicator(string fromSymbolName, ENUM_TIMEFRAMES fromChartTimeFrame) {
        MarketContext context(fromSymbolName, fromChartTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    Ema200Indicator(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * デストラクタ
     */
    ~Ema200Indicator() {
        this.deinit();
    }

    /**
     * 表示対象の市場コンテキストを設定する。
     *
     * 設定後はinit()を呼び出してハンドルと表示設定を再初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.deinit();
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * 初期化
     *
     * @param oscillatorHandlePool オシレーターハンドルプール
     */
    void init(OscillatorHandlePool *oscillatorHandlePool) {
        SetIndexBuffer(this.startPlotIndex + 0, this.buffer0, INDICATOR_DATA);
        SetIndexBuffer(this.startPlotIndex + 1, this.buffer1, INDICATOR_DATA);
        SetIndexBuffer(this.startPlotIndex + 2, this.buffer2, INDICATOR_DATA);

        ArraySetAsSeries(this.buffer0, true);
        ArraySetAsSeries(this.buffer1, true);
        ArraySetAsSeries(this.buffer2, true);

        this.initializePlotSettings();
        this.setHandles(oscillatorHandlePool);
    }

    /**
     * 終了処理
     */
    void deinit() {
        for (int i = 0; i < 3; i++) {
            this.handles[i] = INVALID_HANDLE;
        }

        this.deleteLabels();
        this.clearPlotSettings();
    }

    /**
     * 更新
     *
     * @return 更新成否
     */
    bool update(bool isTimer) {
        ENUM_TIMEFRAMES updateTimeFrame = PERIOD_M1;
        
        if (!isTimer) {
            updateTimeFrame = this.marketContext.timeFrame;
        }
        
        datetime currentM1BarTime = iTime(this.marketContext.symbolName, updateTimeFrame, 0);

        if (currentM1BarTime <= 0) {
            return false;
        }

        if (this.lastUpdateM1BarTime == currentM1BarTime) {
            return true;
        }

        int barsCount = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);

        if (barsCount <= 0) {
            return false;
        }

        this.clearBuffers();

        bool isSucceeded = true;

        for (int i = 0; i < this.displayCount; i++) {
            if (!this.updateLine(i, barsCount)) {
                isSucceeded = false;
            }
        }

        this.updateLabels();

        this.lastUpdateM1BarTime = currentM1BarTime;
        ChartRedraw(0);

        return isSucceeded;
    }

private:
    int emaPeriod;
    int maxBars;
    int startPlotIndex;
    int displayCount;
    ENUM_TIMEFRAMES timeFrames[3];
    int handles[3];
    double buffer0[];
    double buffer1[];
    double buffer2[];
    datetime lastUpdateM1BarTime;
    int labelShiftBars;
    int labelFontSize;
    string labelFontFace;

    /**
     * 市場コンテキストおよび表示設定を初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.emaPeriod = 200;
        this.maxBars = 500;
        this.startPlotIndex = 2;
        this.displayCount = 0;
        this.lastUpdateM1BarTime = 0;
        this.labelShiftBars = 3;
        this.labelFontSize = 10;
        this.labelFontFace = "Arial";

        for (int i = 0; i < 3; i++) {
            this.timeFrames[i] = PERIOD_CURRENT;
            this.handles[i] = INVALID_HANDLE;
        }

        this.setupTimeFrames();
    }

    /**
     * 表示するEMA200時間足設定
     */
    void setupTimeFrames() {
        this.displayCount = 0;

        switch (this.marketContext.timeFrame) {
            case PERIOD_D1:
                this.addTimeFrame(PERIOD_D1);
                break;
            case PERIOD_H4:
                this.addTimeFrame(PERIOD_D1);
                this.addTimeFrame(PERIOD_H4);
                break;
            case PERIOD_H1:
                this.addTimeFrame(PERIOD_D1);
                this.addTimeFrame(PERIOD_H4);
                this.addTimeFrame(PERIOD_H1);
                break;
            case PERIOD_M15:
                this.addTimeFrame(PERIOD_H4);
                this.addTimeFrame(PERIOD_H1);
                this.addTimeFrame(PERIOD_M15);
                break;
            case PERIOD_M5:
                this.addTimeFrame(PERIOD_H1);
                this.addTimeFrame(PERIOD_M15);
                this.addTimeFrame(PERIOD_M5);
                break;
            case PERIOD_M1:
                this.addTimeFrame(PERIOD_M15);
                this.addTimeFrame(PERIOD_M5);
                this.addTimeFrame(PERIOD_M1);
                break;
            default:
                break;
        }
    }

    /**
     * 表示時間足追加
     *
     * @param timeFrameValue 時間足
     */
    void addTimeFrame(ENUM_TIMEFRAMES timeFrameValue) {
        if (this.displayCount >= 3) {
            return;
        }

        this.timeFrames[this.displayCount] = timeFrameValue;
        this.displayCount++;
    }

    /**
     * ハンドル設定
     *
     * @param oscillatorHandlePool オシレーターハンドルプール
     */
    void setHandles(OscillatorHandlePool *oscillatorHandlePool) {
        if (oscillatorHandlePool == NULL) {
            return;
        }

        Ema200HandlePool *ema200HandlePool = oscillatorHandlePool.getEma200HandlePool();

        if (ema200HandlePool == NULL) {
            return;
        }

        ema200HandlePool.setParameters(this.emaPeriod, MODE_EMA, PRICE_CLOSE);

        for (int i = 0; i < this.displayCount; i++) {
            this.handles[i] = ema200HandlePool.getEma200Handle(this.timeFrames[i]);
        }
    }

    /**
     * Plot設定初期化
     */
    void initializePlotSettings() {
        this.clearPlotSettings();

        for (int i = 0; i < this.displayCount; i++) {
            this.setupPlot(i, this.timeFrames[i]);
        }
    }

    /**
     * Plot設定クリア
     */
    void clearPlotSettings() {
        for (int i = 0; i < 3; i++) {
            int plotIndex = this.startPlotIndex + i;

            PlotIndexSetInteger(plotIndex, PLOT_DRAW_TYPE, DRAW_NONE);
            PlotIndexSetInteger(plotIndex, PLOT_LINE_STYLE, STYLE_SOLID);
            PlotIndexSetInteger(plotIndex, PLOT_LINE_WIDTH, 1);
            PlotIndexSetInteger(plotIndex, PLOT_LINE_COLOR, 0, clrGray);
            PlotIndexSetDouble(plotIndex, PLOT_EMPTY_VALUE, EMPTY_VALUE);
            PlotIndexSetString(plotIndex, PLOT_LABEL, "");
        }
    }

    /**
     * Plot設定
     *
     * @param lineIndex ライン番号
     * @param timeFrameValue 時間足
     */
    void setupPlot(int lineIndex, ENUM_TIMEFRAMES timeFrameValue) {
        int plotIndex = this.startPlotIndex + lineIndex;
        color lineColor = this.getLineColor(timeFrameValue);
        int lineWidth = this.getLineWidth(timeFrameValue);
        string lineLabel = StringFormat("EMA200 %s", this.getTimeFrameLabel(timeFrameValue));

        PlotIndexSetInteger(plotIndex, PLOT_DRAW_TYPE, DRAW_LINE);
        PlotIndexSetInteger(plotIndex, PLOT_LINE_STYLE, STYLE_SOLID);
        PlotIndexSetInteger(plotIndex, PLOT_LINE_WIDTH, lineWidth);
        PlotIndexSetInteger(plotIndex, PLOT_LINE_COLOR, 0, lineColor);
        PlotIndexSetDouble(plotIndex, PLOT_EMPTY_VALUE, EMPTY_VALUE);
        PlotIndexSetString(plotIndex, PLOT_LABEL, lineLabel);
    }

    /**
     * バッファ初期化
     */
    void clearBuffers() {
        ArrayInitialize(this.buffer0, EMPTY_VALUE);
        ArrayInitialize(this.buffer1, EMPTY_VALUE);
        ArrayInitialize(this.buffer2, EMPTY_VALUE);
    }

    /**
     * ライン更新
     *
     * @param lineIndex ライン番号
     * @param barsCount バー数
     * @return 更新成否
     */
    bool updateLine(int lineIndex, int barsCount) {
        if (lineIndex < 0 || lineIndex >= this.displayCount) {
            return false;
        }

        if (this.handles[lineIndex] == INVALID_HANDLE) {
            return false;
        }

        int calculatedCount = BarsCalculated(this.handles[lineIndex]);

        if (calculatedCount <= 0) {
            return false;
        }

        int limit = barsCount;

        if (limit > this.maxBars) {
            limit = this.maxBars;
        }

        bool isSucceeded = true;

        for (int barIndex = 0; barIndex < limit; barIndex++) {
            datetime barTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, barIndex);

            if (barTime == 0) {
                this.setBufferValue(lineIndex, barIndex, EMPTY_VALUE);
                isSucceeded = false;
                continue;
            }

            int targetBarIndex = this.getTargetBarIndex(lineIndex, barIndex, barTime);

            if (targetBarIndex < 0 || targetBarIndex >= calculatedCount) {
                this.setBufferValue(lineIndex, barIndex, EMPTY_VALUE);
                isSucceeded = false;
                continue;
            }

            double values[];

            ArrayResize(values, 1);

            if (CopyBuffer(this.handles[lineIndex], 0, targetBarIndex, 1, values) <= 0) {
                this.setBufferValue(lineIndex, barIndex, EMPTY_VALUE);
                isSucceeded = false;
                continue;
            }

            this.setBufferValue(lineIndex, barIndex, values[0]);
        }

        return isSucceeded;
    }

    /**
     * 対象時間足バー番号取得
     *
     * @param lineIndex ライン番号
     * @param chartBarIndex チャート足バー番号
     * @param chartBarTime チャート足時刻
     * @return 対象時間足バー番号
     */
    int getTargetBarIndex(int lineIndex, int chartBarIndex, datetime chartBarTime) {
        ENUM_TIMEFRAMES targetTimeFrame = this.timeFrames[lineIndex];

        if (targetTimeFrame == this.marketContext.timeFrame) {
            return chartBarIndex;
        }

        return iBarShift(this.marketContext.symbolName, targetTimeFrame, chartBarTime, false);
    }

    /**
     * バッファ値設定
     *
     * @param lineIndex ライン番号
     * @param barIndex バー番号
     * @param value EMA200値
     */
    void setBufferValue(int lineIndex, int barIndex, double value) {
        switch (lineIndex) {
            case 0:
                this.buffer0[barIndex] = value;
                break;
            case 1:
                this.buffer1[barIndex] = value;
                break;
            case 2:
                this.buffer2[barIndex] = value;
                break;
        }
    }

    /**
     * EMA200ラベルを更新します。
     */
    void updateLabels() {
        datetime labelTime = this.getLabelTime();

        if (labelTime <= 0) {
            return;
        }

        for (int i = 0; i < this.displayCount; i++) {
            double labelPrice = this.getBufferValue(i, 0);

            if (labelPrice == EMPTY_VALUE || labelPrice <= 0) {
                this.deleteLabel(i);
                continue;
            }

            ENUM_TIMEFRAMES labelTimeFrame = this.timeFrames[i];
            string labelText = StringFormat("EMA200 %s", this.getTimeFrameLabel(labelTimeFrame));
            string objectName = this.getLabelObjectName(labelTimeFrame);
            color labelColor = this.getLineColor(labelTimeFrame);

            DrawUtil::setTextMoveFixed(objectName, this.labelFontFace, labelColor, this.labelFontSize, labelText, labelTime, labelPrice, 0);
        }
    }

    /**
     * EMA200ラベルを削除します。
     */
    void deleteLabels() {
        for (int i = 0; i < 3; i++) {
            this.deleteLabel(i);
        }
    }

    /**
     * EMA200ラベルを削除します。
     *
     * @param lineIndex ライン番号
     */
    void deleteLabel(int lineIndex) {
        if (lineIndex < 0 || lineIndex >= 3) {
            return;
        }

        ENUM_TIMEFRAMES labelTimeFrame = this.timeFrames[lineIndex];
        string objectName = this.getLabelObjectName(labelTimeFrame);

        DrawUtil::deleteFixedObject(objectName, 0);
    }

    /**
     * ラベル表示位置の時間を取得します。
     *
     * @return ラベル表示位置の時間
     */
    datetime getLabelTime() {
        datetime currentTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);

        if (currentTime <= 0) {
            return 0;
        }

        int periodSeconds = PeriodSeconds(this.marketContext.timeFrame);

        if (periodSeconds <= 0) {
            periodSeconds = 60;
        }

        return currentTime + periodSeconds * this.labelShiftBars;
    }

    /**
     * バッファ値を取得します。
     *
     * @param lineIndex ライン番号
     * @param barIndex バー番号
     * @return バッファ値
     */
    double getBufferValue(int lineIndex, int barIndex) {
        switch (lineIndex) {
            case 0:
                return this.buffer0[barIndex];
            case 1:
                return this.buffer1[barIndex];
            case 2:
                return this.buffer2[barIndex];
        }

        return EMPTY_VALUE;
    }

    /**
     * ラベル用オブジェクト名を取得します。
     *
     * @param timeFrameValue 時間足
     * @return ラベル用オブジェクト名
     */
    string getLabelObjectName(ENUM_TIMEFRAMES timeFrameValue) {
        return StringFormat("Ema200Label%s", this.getTimeFrameLabel(timeFrameValue));
    }

    /**
     * ライン色取得
     *
     * @param timeFrameValue 時間足
     * @return ライン色
     */
    color getLineColor(ENUM_TIMEFRAMES timeFrameValue) {
        switch (timeFrameValue) {
            case PERIOD_D1:
                return clrRed;
            case PERIOD_H4:
                return clrOrange;
            case PERIOD_H1:
                return clrDodgerBlue;
            case PERIOD_M15:
                return clrLimeGreen;
            case PERIOD_M5:
                return clrMagenta;
            case PERIOD_M1:
                return clrAqua;
        }

        return clrGray;
    }

    /**
     * ライン幅取得
     *
     * @param timeFrameValue 時間足
     * @return ライン幅
     */
    int getLineWidth(ENUM_TIMEFRAMES timeFrameValue) {
        switch (timeFrameValue) {
            case PERIOD_D1:
                return 6;
            case PERIOD_H4:
                return 5;
            case PERIOD_H1:
                return 4;
            case PERIOD_M15:
                return 3;
            case PERIOD_M5:
                return 2;
            case PERIOD_M1:
                return 1;
        }

        return 1;
    }

    /**
     * 時間足ラベル取得
     *
     * @param timeFrameValue 時間足
     * @return 時間足ラベル
     */
    string getTimeFrameLabel(ENUM_TIMEFRAMES timeFrameValue) {
        switch (timeFrameValue) {
            case PERIOD_D1:
                return "D1";
            case PERIOD_H4:
                return "H4";
            case PERIOD_H1:
                return "H1";
            case PERIOD_M15:
                return "M15";
            case PERIOD_M5:
                return "M5";
            case PERIOD_M1:
                return "M1";
        }

        return "NONE";
    }
};

#endif


