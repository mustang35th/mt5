//+------------------------------------------------------------------+
//|                                              Ema200Indicator.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_EMA200_INDICATOR_MQH
#define MSTNG_EMA200_INDICATOR_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
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
        SetIndexBuffer(this.startPlotIndex + 3, this.buffer3, INDICATOR_DATA);
        SetIndexBuffer(this.startPlotIndex + 4, this.buffer4, INDICATOR_DATA);

        ArraySetAsSeries(this.buffer0, true);
        ArraySetAsSeries(this.buffer1, true);
        ArraySetAsSeries(this.buffer2, true);
        ArraySetAsSeries(this.buffer3, true);
        ArraySetAsSeries(this.buffer4, true);

        this.bufferResetPending = true;
        this.lastBufferBarTime = 0;
        this.lastBufferBarsCount = 0;
        this.initializePlotSettings();
        this.setHandles(oscillatorHandlePool);
    }

    /**
     * 終了処理
     */
    void deinit() {
        for (int i = 0; i < 5; i++) {
            this.handles[i] = INVALID_HANDLE;
        }

        ArrayFree(this.chartBarTimes);
        this.deleteLabels();
        this.labelsUpdatePending = false;
        this.lastUpdateM1BarTime = 0;
        this.bufferResetPending = true;
        this.lastBufferBarTime = 0;
        this.lastBufferBarsCount = 0;
        this.clearPlotSettings();
    }

    /**
     * 更新
     *
     * @param isTimer 通常チャートのM1単位で更新する場合true
     * @param fromResetBuffers 履歴再計算に伴い全バッファを初期化する場合true
     * @return 更新成否
     */
    bool update(bool isTimer, bool fromResetBuffers = false) {
        if (fromResetBuffers) {
            this.bufferResetPending = true;
        }

        ENUM_TIMEFRAMES updateTimeFrame = PERIOD_M1;
        
        if (!isTimer) {
            updateTimeFrame = this.marketContext.timeFrame;
        }
        
        datetime currentM1BarTime = iTime(this.marketContext.symbolName, updateTimeFrame, 0);

        if (currentM1BarTime <= 0) {
            return false;
        }

        if (!this.bufferResetPending && this.lastUpdateM1BarTime == currentM1BarTime) {
            if (this.labelsUpdatePending) {
                // ラベルだけの失敗では、取得済みのEMAを再計算しない。
                this.labelsUpdatePending = !this.updateLabels();
                ChartRedraw(0);
            }

            return !this.labelsUpdatePending;
        }

        // 同じM1内の履歴再計算が失敗した場合も、次回にデータ取得を再試行する。
        this.lastUpdateM1BarTime = 0;
        int barsCount = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);

        if (barsCount <= 0) {
            return false;
        }

        if (ArraySize(this.buffer0) != barsCount
                || ArraySize(this.buffer1) != barsCount
                || ArraySize(this.buffer2) != barsCount
                || ArraySize(this.buffer3) != barsCount
                || ArraySize(this.buffer4) != barsCount) {
            // タイマーが表示バッファの拡張より先に動いた場合は、準備後に全体を初期化する。
            this.bufferResetPending = true;

            return false;
        }

        datetime currentChartBarTime = currentM1BarTime;
        if (updateTimeFrame != this.marketContext.timeFrame) {
            currentChartBarTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);
        }

        this.clearBuffers(barsCount, currentChartBarTime);

        bool isSucceeded = true;

        if (this.displayCount > 0) {
            int chartBarCount = barsCount;
            if (chartBarCount > this.maxBars) {
                chartBarCount = this.maxBars;
            }

            // 最新足を添字0にそろえた時刻配列を、すべてのEMA線で共用する。
            if (ArrayResize(this.chartBarTimes, chartBarCount) != chartBarCount
                    || CopyTime(this.marketContext.symbolName, this.marketContext.timeFrame,
                        0, chartBarCount, this.chartBarTimes) != chartBarCount) {
                // 不足時は全線を空表示のままにし、更新済み時刻を進めず再試行する。
                isSucceeded = false;
            } else {
                for (int i = 0; i < this.displayCount; i++) {
                    if (!this.updateLine(i, this.chartBarTimes)) {
                        isSucceeded = false;
                    }
                }
            }
        }

        this.labelsUpdatePending = !this.updateLabels();

        if (isSucceeded) {
            this.lastUpdateM1BarTime = currentM1BarTime;
        }

        ChartRedraw(0);

        return isSucceeded && !this.labelsUpdatePending;
    }

private:
    /** EMAの期間。 */
    int emaPeriod;

    /** 描画に使用する最大バー数。 */
    int maxBars;

    /** 表示開始インデックス。 */
    int startPlotIndex;

    /** 表示対象の時間足数。 */
    int displayCount;

    /** 表示対象の時間足配列。 */
    ENUM_TIMEFRAMES timeFrames[5];

    /** 時間足ごとのEMAハンドル配列。 */
    int handles[5];

    /** 全EMA線で共用するチャート足時刻の作業配列。seriesで最新足が添字0。 */
    datetime chartBarTimes[];

    /** EMAの主軸データバッファ。 */
    double buffer0[];

    /** EMAの短期データバッファ。 */
    double buffer1[];

    /** EMAの長期データバッファ。 */
    double buffer2[];

    /** EMAの最上位データバッファ。 */
    double buffer3[];

    /** EMAの追加上位足データバッファ。 */
    double buffer4[];

    /** 最終更新したM1バー時刻。 */
    datetime lastUpdateM1BarTime;

    /** 初回・履歴再計算・バッファ本数不一致により全体初期化が必要な場合true。 */
    bool bufferResetPending;

    /** 前回バッファを初期化した時点のチャート最新足時刻。EMA取得の成否には依存しない。 */
    datetime lastBufferBarTime;

    /** 前回バッファを初期化した時点のチャート足本数。 */
    int lastBufferBarsCount;

    /** ラベル表示のシフト数。 */
    int labelShiftBars;

    /** ラベル文字サイズ。 */
    int labelFontSize;

    /** ラベル文字フォント。 */
    string labelFontFace;

    /** ラベルの設定と表示内容の反映が成功した場合true。 */
    bool labelReady[5];

    /** ラベルへ最後に反映した表示時刻。 */
    datetime labelTimes[5];

    /** ラベルへ最後に反映した価格位置。 */
    double labelPrices[5];

    /** ラベルへ最後に反映した表示文字。 */
    string labelTexts[5];

    /** ラベルへ最後に反映した文字色。 */
    color labelColors[5];

    /** ラベルの更新に失敗し、同じ足でも再試行する場合true。 */
    bool labelsUpdatePending;

    /**
     * 市場コンテキストおよび表示設定を初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.emaPeriod = 200;
        this.maxBars = 2000;
        this.startPlotIndex = 2;
        this.displayCount = 0;
        this.lastUpdateM1BarTime = 0;
        this.bufferResetPending = true;
        this.lastBufferBarTime = 0;
        this.lastBufferBarsCount = 0;
        this.labelShiftBars = 3;
        this.labelFontSize = 10;
        this.labelFontFace = "Arial";
        this.labelsUpdatePending = false;
        ArraySetAsSeries(this.chartBarTimes, true);

        for (int i = 0; i < 5; i++) {
            this.timeFrames[i] = PERIOD_CURRENT;
            this.handles[i] = INVALID_HANDLE;
            this.labelReady[i] = false;
            this.labelTimes[i] = 0;
            this.labelPrices[i] = 0;
            this.labelTexts[i] = "";
            this.labelColors[i] = clrNONE;
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
                this.addTimeFrame(PERIOD_W1);
                this.addTimeFrame(PERIOD_D1);
                break;
            case PERIOD_W1:
                this.addTimeFrame(PERIOD_W1);
                break;
            case PERIOD_H4:
                this.addTimeFrame(PERIOD_W1);
                this.addTimeFrame(PERIOD_D1);
                this.addTimeFrame(PERIOD_H4);
                break;
            case PERIOD_H1:
                this.addTimeFrame(PERIOD_W1);
                this.addTimeFrame(PERIOD_D1);
                this.addTimeFrame(PERIOD_H4);
                this.addTimeFrame(PERIOD_H1);
                break;
            case PERIOD_M15:
                this.addTimeFrame(PERIOD_D1);
                this.addTimeFrame(PERIOD_H4);
                this.addTimeFrame(PERIOD_H1);
                this.addTimeFrame(PERIOD_M15);
                break;
            case PERIOD_M5:
                this.addTimeFrame(PERIOD_D1);
                this.addTimeFrame(PERIOD_H4);
                this.addTimeFrame(PERIOD_H1);
                this.addTimeFrame(PERIOD_M15);
                this.addTimeFrame(PERIOD_M5);
                break;
            case PERIOD_M1:
                this.addTimeFrame(PERIOD_H1);
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
        if (this.displayCount >= 5) {
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
        for (int i = 0; i < 5; i++) {
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
     * 表示範囲と新しい足で範囲外へ移動した部分を空にする。
     * 初回・履歴再計算・足の対応が確認できない場合は全体を初期化する。
     *
     * @param fromBarsCount バッファと一致するチャート足本数
     * @param fromBarTime チャート最新足時刻
     */
    void clearBuffers(int fromBarsCount, datetime fromBarTime) {
        int clearCount = fromBarsCount;

        if (!this.bufferResetPending
                && this.lastBufferBarTime > 0
                && this.lastBufferBarsCount > 0) {
            if (fromBarTime == this.lastBufferBarTime && fromBarsCount == this.lastBufferBarsCount) {
                clearCount = MathMin(fromBarsCount, this.maxBars);
            } else if (fromBarTime > this.lastBufferBarTime) {
                int newBars = iBarShift(
                    this.marketContext.symbolName,
                    this.marketContext.timeFrame,
                    this.lastBufferBarTime,
                    true
                );

                if (newBars > 0 && newBars < fromBarsCount
                        && (fromBarsCount - newBars == this.lastBufferBarsCount
                            || fromBarsCount == this.lastBufferBarsCount)) {
                    clearCount = MathMin(this.maxBars, fromBarsCount - newBars) + newBars;
                }
            }
        }

        this.clearBuffer(this.buffer0, clearCount);
        this.clearBuffer(this.buffer1, clearCount);
        this.clearBuffer(this.buffer2, clearCount);
        this.clearBuffer(this.buffer3, clearCount);
        this.clearBuffer(this.buffer4, clearCount);

        // 一部のEMA取得が失敗しても、次回はこの初期化時点からの移動範囲を消去する。
        this.lastBufferBarTime = fromBarTime;
        this.lastBufferBarsCount = fromBarsCount;
        this.bufferResetPending = false;
    }

    /**
     * バッファの最新側を指定本数だけ空にする。
     *
     * @param fromBuffer series順の表示バッファ
     * @param fromClearCount 初期化する本数
     */
    void clearBuffer(double &fromBuffer[], int fromClearCount) {
        int bufferSize = ArraySize(fromBuffer);

        if (fromClearCount == bufferSize) {
            ArrayInitialize(fromBuffer, EMPTY_VALUE);
        } else {
            // ArrayFillはseries設定を無視するため、通常順の末尾側を指定する。
            ArrayFill(fromBuffer, bufferSize - fromClearCount, fromClearCount, EMPTY_VALUE);
        }
    }

    /**
     * 対応する足番号を求め、必要範囲のEMAを一括取得してラインを更新する。
     * チャート足時刻はupdate()で取得済みの共通配列を参照する。
     *
     * @param lineIndex ライン番号
     * @param fromBarTimes 最新足を添字0とする、表示対象範囲のチャート足時刻。
     * @return 更新成否
     */
    bool updateLine(int lineIndex, const datetime &fromBarTimes[]) {
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

        int limit = ArraySize(fromBarTimes);
        if (limit <= 0) {
            return false;
        }

        int targetBarIndices[];

        if (ArrayResize(targetBarIndices, limit) != limit) {
            return false;
        }

        ArrayInitialize(targetBarIndices, -1);

        int firstTargetBarIndex = calculatedCount;
        int lastTargetBarIndex = -1;
        bool isSucceeded = true;

        for (int barIndex = 0; barIndex < limit; barIndex++) {
            datetime barTime = fromBarTimes[barIndex];

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

            targetBarIndices[barIndex] = targetBarIndex;

            if (targetBarIndex < firstTargetBarIndex) {
                firstTargetBarIndex = targetBarIndex;
            }

            if (targetBarIndex > lastTargetBarIndex) {
                lastTargetBarIndex = targetBarIndex;
            }
        }

        if (lastTargetBarIndex < firstTargetBarIndex) {
            return false;
        }

        int copyCount = lastTargetBarIndex - firstTargetBarIndex + 1;
        double values[];

        ArraySetAsSeries(values, true);

        // 部分取得時は足番号と値の対応を確定せず、次回更新で再試行する。
        if (CopyBuffer(this.handles[lineIndex], 0, firstTargetBarIndex, copyCount, values) != copyCount) {
            return false;
        }

        for (int barIndex = 0; barIndex < limit; barIndex++) {
            int targetBarIndex = targetBarIndices[barIndex];

            if (targetBarIndex < 0) {
                continue;
            }

            this.setBufferValue(lineIndex, barIndex, values[targetBarIndex - firstTargetBarIndex]);
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
            case 3:
                this.buffer3[barIndex] = value;
                break;
            case 4:
                this.buffer4[barIndex] = value;
                break;
        }
    }

    /**
     * EMA200ラベルを更新します。
     *
     * @return 全ラベルの更新成否
     */
    bool updateLabels() {
        if (this.displayCount <= 0) {
            return true;
        }

        datetime labelTime = this.getLabelTime();

        if (labelTime <= 0) {
            return false;
        }

        bool isSucceeded = true;

        for (int i = 0; i < this.displayCount; i++) {
            double labelPrice = this.getBufferValue(i, 0);

            if (labelPrice == EMPTY_VALUE || labelPrice <= 0) {
                if (!this.deleteLabel(i)) {
                    isSucceeded = false;
                }

                continue;
            }

            ENUM_TIMEFRAMES labelTimeFrame = this.timeFrames[i];
            string labelRate = DoubleToString(labelPrice, this.marketContext.digits);
            string labelText = StringFormat("EMA200 %s %s", this.getTimeFrameLabel(labelTimeFrame), labelRate);
            color labelColor = this.getLineColor(labelTimeFrame);

            if (!this.updateLabel(i, labelTime, labelPrice, labelText, labelColor)) {
                isSucceeded = false;
            }
        }

        return isSucceeded;
    }

    /**
     * EMA200ラベルを再利用し、変更された位置・文字・色だけを反映する。
     * 固定設定は初期反映・再作成・前回失敗時だけ設定する。
     *
     * @param fromLineIndex ライン番号
     * @param fromTime 表示時刻
     * @param fromPrice 価格位置
     * @param fromText 表示文字
     * @param fromColor 文字色
     * @return 更新成否
     */
    bool updateLabel(int fromLineIndex, datetime fromTime, double fromPrice, string fromText, color fromColor) {
        string objectName = this.getLabelObjectName(this.timeFrames[fromLineIndex]);

        if (ObjectFind(0, objectName) < 0) {
            this.labelReady[fromLineIndex] = false;

            if (!ObjectCreate(0, objectName, OBJ_TEXT, 0, fromTime, fromPrice)) {
                return false;
            }
        }

        bool initializeProperties = !this.labelReady[fromLineIndex];
        // 途中で失敗した場合は、次回に位置・文字・色をすべて反映し直す。
        this.labelReady[fromLineIndex] = false;

        if (initializeProperties) {
            if (!ObjectSetString(0, objectName, OBJPROP_FONT, this.labelFontFace)
                    || !ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, this.labelFontSize)
                    || !ObjectSetInteger(0, objectName, OBJPROP_BACK, false)
                    || !ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT)) {
                return false;
            }
        }

        if (initializeProperties
                || this.labelTimes[fromLineIndex] != fromTime
                || this.labelPrices[fromLineIndex] != fromPrice) {
            if (!ObjectMove(0, objectName, 0, fromTime, fromPrice)) {
                return false;
            }
        }

        if (initializeProperties || this.labelTexts[fromLineIndex] != fromText) {
            if (!ObjectSetString(0, objectName, OBJPROP_TEXT, fromText)) {
                return false;
            }
        }

        if (initializeProperties || this.labelColors[fromLineIndex] != fromColor) {
            if (!ObjectSetInteger(0, objectName, OBJPROP_COLOR, fromColor)) {
                return false;
            }
        }

        this.labelTimes[fromLineIndex] = fromTime;
        this.labelPrices[fromLineIndex] = fromPrice;
        this.labelTexts[fromLineIndex] = fromText;
        this.labelColors[fromLineIndex] = fromColor;
        this.labelReady[fromLineIndex] = true;

        return true;
    }

    /**
     * EMA200ラベルを削除します。
     */
    void deleteLabels() {
        for (int i = 0; i < 5; i++) {
            this.deleteLabel(i);
        }
    }

    /**
     * EMA200ラベルを削除します。
     *
     * @param lineIndex ライン番号
     * @return 削除済み、または削除要求が成功した場合true
     */
    bool deleteLabel(int lineIndex) {
        if (lineIndex < 0 || lineIndex >= 5) {
            return false;
        }

        this.labelReady[lineIndex] = false;
        ENUM_TIMEFRAMES labelTimeFrame = this.timeFrames[lineIndex];
        string objectName = this.getLabelObjectName(labelTimeFrame);

        if (ObjectFind(0, objectName) < 0) {
            return true;
        }

        return ObjectDelete(0, objectName);
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
            case 3:
                return this.buffer3[barIndex];
            case 4:
                return this.buffer4[barIndex];
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
        return Constant::PREFIX_FIXED + StringFormat("Ema200Label%s", this.getTimeFrameLabel(timeFrameValue));
    }

    /**
     * ライン色取得
     *
     * @param timeFrameValue 時間足
     * @return ライン色
     */
    color getLineColor(ENUM_TIMEFRAMES timeFrameValue) {
        switch (timeFrameValue) {
            case PERIOD_W1:
                return clrSilver;
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
            case PERIOD_W1:
                return 7;
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
            case PERIOD_W1:
                return "W1";
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


