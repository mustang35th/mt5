//+------------------------------------------------------------------+
//|                                                 ZigZagElliot.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"
#property indicator_chart_window

#property indicator_buffers 6
#property indicator_plots   6


#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Draw\Draw.mqh>
#include <Mstng\Draw\DrawElliotVerticalFit.mqh>
#include <Mstng\Elliot\ElliotAllFile.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3.mqh>
#include <Mstng\Indicator\Ema200Indicator.mqh>
#include <Mstng\Indicator\GmmaIndicator.mqh>
#include <Mstng\Indicator\JapanTimeAxisView.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <Mstng\Util\UtilAll.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

#property indicator_type1   DRAW_LINE
#property indicator_type2   DRAW_LINE
#property indicator_type3   DRAW_LINE
#property indicator_type4   DRAW_LINE
#property indicator_type5   DRAW_LINE
#property indicator_type6   DRAW_LINE

GmmaIndicator *g_gmmaIndicator = NULL;
Ema200Indicator *g_ema200Indicator = NULL;
JapanTimeAxisView *g_japanTimeAxisView = NULL;
DrawElliotVerticalFit *g_drawElliotVerticalFit = NULL;

Logger g_logger;

bool g_isTimer = true;
int g_timerSeconds = 30;

bool g_isInitialized = false;
bool g_isElliotInfoVisible = true;

MarketContext g_marketContext;

OscillatorHandlePool *g_oscillatorHandlePool;
ElliotAll *g_elliotAll;

SignalCount *g_signalCount;

Draw gDraw;

static datetime g_staticLasttime;
long g_lastExecuteTickCount = 0;

ElliotAllFile g_elliotAllFile;
ENUM_TIMEFRAMES LogStartTimeFrame = PERIOD_D1;

/**
 * インジケータを初期化する。
 *
 * @return 初期化結果
 */
int OnInit() {
    if (Util::isStrategyTester()) {
        g_isTimer = false;
    }

    MarketContext context(_Symbol, _Period);
    g_marketContext = context;
    
    g_logger.setLevel(LOG_INFO);
    g_logger.setMarketContext(g_marketContext);
    
    LogUtil::printMethodStart(g_logger, __FUNCTION__);
    g_logger.debug(__FUNCTION__, StringFormat("g_isTimer = %s", (string)g_isTimer));

    SymbolSelect(g_marketContext.symbolName, true);    // シンボル未選択（MarketWatch未登録）対策

    if (g_isTimer) {
        g_timerSeconds = 1;
        
        EventSetTimer(g_timerSeconds);
    }
    
    MarketContext warmUpContext(g_marketContext.symbolName, PERIOD_MN1);
    WarmUpSeriesUtil::warmUpFromMn1To(warmUpContext, 500);

    setOscillatorHandlePool();
    setSignalCount();
    
    
    setGmmaIndicator();
    setEma200Indicator();
    setJapanTimeAxisView();
    setElliotVerticalFit();
    setElliotInfoButton();
    setElliotVerticalFitButton();
    

    if (!g_isTimer) {
        g_elliotAllFile.setupMultiTimeFrameSameFolder(
            "Logs\\ElliotAllStochasticMainOrderTrade",  // フォルダ名
            g_marketContext,  // 市場コンテキスト
            LogStartTimeFrame,  // 開始時間足
            true,  // 共有フォルダ使用有無
            ",",  // 区切り文字
            true,  // 書き込み毎のフラッシュ有無
            true,  // ANSI出力有無
            CSV_FILE_WRITE_MODE_OVERWRITE  // 出力モード
        );
        
        if (!g_elliotAllFile.initializeMultiTimeFrame(LogStartTimeFrame, g_marketContext.timeFrame)) {
            Print("multi initializeMultiTimeFrame failed");
            g_elliotAllFile.close();
            
            return false;
        }
    }
    
    LogUtil::printMethodEnd(g_logger, __FUNCTION__, true);
    
    return INIT_SUCCEEDED;
}

/**
 * インジケータ終了時の解放処理を行う。
 *
 * @param reason 終了理由
 */
void OnDeinit(const int reason) {
    LogUtil::printMethodStart(g_logger, __FUNCTION__);
    
    
    deleteGmmaIndicator();
    deleteEma200Indicator();
    deleteJapanTimeAxisView();
    deleteElliotVerticalFit();
    deleteElliotInfoButton();
    deleteElliotVerticalFitButton();
    
    
    deleteSignalCount();
    
    delete g_elliotAll;
    delete g_oscillatorHandlePool;
    
    if (!g_isTimer) {
        g_elliotAllFile.close();
    }
    
    // タイマー停止
    EventKillTimer();

    // 表示オブジェクト削除
    //ObjectsDeleteAll(0, 0, -1);
    ObjectsDeleteAll(0, Constant::PREFIX, 0, -1);
    ObjectsDeleteAll(0, Constant::PREFIX_FIXED, 0, -1);
    
    LogUtil::printMethodEnd(g_logger, __FUNCTION__, true);
}

/**
 * チャートイベントを処理する。
 *
 * @param id イベントID
 * @param lparam long型イベント値
 * @param dparam double型イベント値
 * @param sparam string型イベント値
 */
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if (id == CHARTEVENT_CHART_CHANGE) {
        if (updateElliotVerticalFit(false)) {
            redrawElliotInfo();
        }

        return;
    }

    if (id != CHARTEVENT_OBJECT_CLICK) {
        return;
    }

    if (sparam == getElliotVerticalFitButtonName()) {
        toggleElliotVerticalFit();

        return;
    }

    if (sparam == getElliotInfoButtonName()) {
        // 大きいエリオット情報のみ表示切替し、波動ラベルやライン描画は残す。
        g_isElliotInfoVisible = !g_isElliotInfoVisible;
        updateElliotInfoButton();
        redrawElliotInfo();
    }
}

/**
 * ティック更新時の描画処理を行う。
 *
 * @param rates_total 全バー数
 * @param prev_calculated 前回計算済みバー数
 * @param time 時刻配列
 * @param open 始値配列
 * @param high 高値配列
 * @param low 安値配列
 * @param close 終値配列
 * @param tick_volume ティック出来高配列
 * @param volume 出来高配列
 * @param spread スプレッド配列
 * @return 次回計算用の処理済みバー数
 */
int OnCalculate(const int32_t rates_total,
                const int32_t prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int32_t &spread[]) {
    
    if (g_gmmaIndicator != NULL) {
        g_gmmaIndicator.update();
    }
    
    updateEma200Indicator();
    
    if (g_isTimer) {
        gDraw.drawBidAsk(g_marketContext);
        
        return rates_total;
    }

    execute();
    
    return rates_total;
}

/**
 * タイマー更新時の描画および解析処理を行う。
 */
void OnTimer() {
    updateJapanTimeAxisView();
    updateEma200Indicator();

    if (updateElliotVerticalFit(false)) {
        redrawElliotInfo();
    }

    if (!g_isInitialized) {
        updateTimerSeconds();
        g_isInitialized = true;
    }

    if (!isExecuteTimerElapsed()) {
        return;
    }

    g_lastExecuteTickCount = GetTickCount();
    execute();
}

/**
 * 時間足に応じて実行間隔秒数を設定する。
 */
void updateTimerSeconds() {
    g_timerSeconds = 30;

    switch (g_marketContext.timeFrame) {
        case PERIOD_M15:
            g_timerSeconds = 25;
            break;
        case PERIOD_M5:
            g_timerSeconds = 20;
            break;
        case PERIOD_M1:
            g_timerSeconds = 15;
            break;
    }
}

/**
 * 前回実行から設定秒数が経過したか判定する。
 *
 * @return true: 実行間隔を経過した
 */
bool isExecuteTimerElapsed() {
    if (g_lastExecuteTickCount <= 0) {
        return true;
    }

    long elapsedMilliseconds = GetTickCount() - g_lastExecuteTickCount;
    long intervalMilliseconds = (long)g_timerSeconds * 1000;

    if (elapsedMilliseconds >= intervalMilliseconds) {
        return true;
    }

    return false;
}

/**
 * エリオット分析とチャート描画を実行する。
 */
void execute() {
    LogUtil::printMethodStart(g_logger, __FUNCTION__);
    
    // ⏰ 処理開始時刻を記録 (ミリ秒)
    long startTime = GetTickCount();    
    g_logger.debug(__FUNCTION__, StringFormat("▼▼▼▼▼　Start Time: %s (MS: %d)", TimeToString(TimeCurrent(), TIME_SECONDS), startTime));
    
    ENUM_TIMEFRAMES timeFrame = PERIOD_MN1;
    MarketContext seriesContext(g_marketContext.symbolName, timeFrame);
    
    if (!WarmUpSeriesUtil::isSeriesSynchronized(seriesContext)) {
        WarmUpSeriesUtil::warmUpFromMn1To(seriesContext, 500);
        PrintFormat("MN1 series not synchronized yet. skip. symbol=%s tf=%d", g_marketContext.symbolName, (int)timeFrame);
        
        return;
    }
    
    setElliotAll();

    updateElliotVerticalFit(true);
        
    gDraw.drawAll(g_elliotAll, g_isElliotInfoVisible);

    // ⏳ 処理終了時刻を記録し、実行時間を計算
    long endTime = GetTickCount();
    long elapsedTime = endTime - startTime;
    
    g_logger.debug(__FUNCTION__, StringFormat("　　　　　　　End Time: %s (MS: %d)", TimeToString(TimeCurrent(), TIME_SECONDS), endTime));
    g_logger.debug(__FUNCTION__, StringFormat("▲▲▲▲▲　Total Elapsed Time: %d ms (%.3f seconds)", elapsedTime, (double)elapsedTime / 1000.0));
    
    
    // ここからExpertAdvisor
    datetime temptime = iTime(g_marketContext.symbolName, g_marketContext.timeFrame, 0);

    if (g_staticLasttime == temptime) {
        LogUtil::printMethodEnd(g_logger, __FUNCTION__, true);
        
        return;
    }
    
    
    if (!g_isTimer) {
        //string timeFrameCsvValues[];
        
        //ArrayResize(timeFrameCsvValues, g_elliotAll.elliotList.Total());

        /*if (!g_elliotAllFile.writeMultiTimeFrameCsvTextValues(
            LogStartTimeFrame,
            g_marketContext.timeFrame,
            timeFrameCsvValues
        )) {
            Print("writeMultiTimeFrameCsvTextValues failed");
            g_elliotAllFile.close();
        }*/
        
        if (g_elliotAll.isAnalysisSucceeded) {
            string csvText = g_elliotAll.getCsv(true);
            
            Print(csvText);
            
            if (!g_elliotAllFile.writeCsvTextValue(csvText)) {
                Print("writeCsvTextValue failed");
                g_elliotAllFile.close();
            }
        }
    }
    
    
    g_logger.debug(__FUNCTION__, "exec EA!!!");
        
    if (g_marketContext.timeFrame < PERIOD_H1) {
        ExpertAdvisorMTF_3in3 ea(g_elliotAll.marketContext);
        
        ea.analyze(g_elliotAll, g_signalCount);
    }
    
    g_staticLasttime = temptime;
    
    LogUtil::printMethodEnd(g_logger, __FUNCTION__, true);
}

/**
 * 全時間足のエリオット分析結果を作成する。
 */
void setElliotAll() {
    delete g_elliotAll;
    
    g_elliotAll = new ElliotAll(g_marketContext);
    
    g_elliotAll.isTimer = g_isTimer;
    g_elliotAll.setOscillatorHandlePool(g_oscillatorHandlePool);
    g_elliotAll.timerSeconds = g_timerSeconds;
    g_elliotAll.isSendMail = true;
    g_elliotAll.analyze();
}

/**
 * オシレーターハンドルプールを作成する。
 */
void setOscillatorHandlePool() {
    g_oscillatorHandlePool = new OscillatorHandlePool(g_marketContext);
    
    if (g_isTimer) {
        g_oscillatorHandlePool.setTimeframesFromMn1To();
    } else {
        g_oscillatorHandlePool.setTimeframesFromD1To();
    }
}

/**
 * シグナルカウントを作成する。
 */
void setSignalCount() {    
    g_signalCount = new SignalCount(g_marketContext);
}

/**
 * シグナルカウントを削除する。
 */
void deleteSignalCount() {
    delete g_signalCount;
}

/**
 * エリオット情報表示ボタンのオブジェクト名を取得する。
 *
 * @return ボタン名
 */
string getElliotInfoButtonName() {
    return Constant::PREFIX_FIXED + "ElliotInfoButton";
}

/**
 * 大きいエリオット情報の表示切替ボタンを作成する。
 */
void setElliotInfoButton() {
    string objectName = getElliotInfoButtonName();

    ObjectDelete(0, objectName);

    if (!ObjectCreate(0, objectName, OBJ_BUTTON, 0, 0, 0)) {
        return;
    }

    // 右下へ固定し、再描画対象の通常プレフィックスとは分離する。
    ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
    ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 140);
    ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 45);
    ObjectSetInteger(0, objectName, OBJPROP_XSIZE, 130);
    ObjectSetInteger(0, objectName, OBJPROP_YSIZE, 24);
    ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
    ObjectSetInteger(0, objectName, OBJPROP_ZORDER, 1000);
    ObjectSetInteger(0, objectName, OBJPROP_BORDER_COLOR, clrWhite);
    ObjectSetString(0, objectName, OBJPROP_FONT, "Meiryo UI");

    updateElliotInfoButton();
}

/**
 * 大きいエリオット情報の表示状態に合わせてボタン表示を更新する。
 */
void updateElliotInfoButton() {
    string objectName = getElliotInfoButtonName();

    if (ObjectFind(0, objectName) < 0) {
        return;
    }

    string text = "波動情報: ON";
    color backgroundColor = clrDarkGreen;

    if (!g_isElliotInfoVisible) {
        text = "波動情報: OFF";
        backgroundColor = clrDimGray;
    }

    // ボタン状態と表示文字を同期して、現在の表示状態を見分けやすくする。
    ObjectSetInteger(0, objectName, OBJPROP_STATE, g_isElliotInfoVisible);
    ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, objectName, OBJPROP_BGCOLOR, backgroundColor);
    ObjectSetString(0, objectName, OBJPROP_TEXT, text);
}

/**
 * 大きいエリオット情報の表示状態を反映してチャートを再描画する。
 */
void redrawElliotInfo() {
    if (g_elliotAll == NULL) {
        return;
    }

    // 通常描画を再実行して、非表示時のエリオット情報オブジェクトも削除する。
    gDraw.drawAll(g_elliotAll, g_isElliotInfoVisible);
    ChartRedraw(0);
}

/**
 * 大きいエリオット情報の表示切替ボタンを削除する。
 */
void deleteElliotInfoButton() {
    ObjectDelete(0, getElliotInfoButtonName());
}

/**
 * Elliott上下FIT制御を作成する。
 */
void setElliotVerticalFit() {
    deleteElliotVerticalFit();

    g_drawElliotVerticalFit = new DrawElliotVerticalFit();
}

/**
 * Elliott上下FIT制御を削除する。
 *
 * FITが有効な場合は、変更前の価格軸設定を復元してから解放する。
 */
void deleteElliotVerticalFit() {
    if (g_drawElliotVerticalFit != NULL) {
        g_drawElliotVerticalFit.restore();
        delete g_drawElliotVerticalFit;
        g_drawElliotVerticalFit = NULL;
    }
}

/**
 * Elliott上下FITボタンのオブジェクト名を取得する。
 *
 * @return ボタン名
 */
string getElliotVerticalFitButtonName() {
    return Constant::PREFIX_FIXED + "ElliotVerticalFitButton";
}

/**
 * Elliott波動ラベルの上下FIT切替ボタンを作成する。
 */
void setElliotVerticalFitButton() {
    string objectName = getElliotVerticalFitButtonName();

    ObjectDelete(0, objectName);

    if (!ObjectCreate(0, objectName, OBJ_BUTTON, 0, 0, 0)) {
        return;
    }

    // 波動情報ボタンの左隣へ固定し、通常描画の削除対象から分離する。
    ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
    ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 280);
    ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 45);
    ObjectSetInteger(0, objectName, OBJPROP_XSIZE, 130);
    ObjectSetInteger(0, objectName, OBJPROP_YSIZE, 24);
    ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
    ObjectSetInteger(0, objectName, OBJPROP_ZORDER, 1000);
    ObjectSetInteger(0, objectName, OBJPROP_BORDER_COLOR, clrWhite);
    ObjectSetString(0, objectName, OBJPROP_FONT, "Meiryo UI");

    updateElliotVerticalFitButton();
}

/**
 * Elliott上下FIT状態に合わせてボタン表示を更新する。
 */
void updateElliotVerticalFitButton() {
    string objectName = getElliotVerticalFitButtonName();

    if (ObjectFind(0, objectName) < 0) {
        return;
    }

    bool isEnabled = false;

    if (g_drawElliotVerticalFit != NULL) {
        isEnabled = g_drawElliotVerticalFit.isEnabled();
    }

    string text = "波動上下FIT";
    color backgroundColor = clrDimGray;

    if (isEnabled) {
        text = "上下FIT解除";
        backgroundColor = clrDarkGreen;
    }

    ObjectSetInteger(0, objectName, OBJPROP_STATE, isEnabled);
    ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, objectName, OBJPROP_BGCOLOR, backgroundColor);
    ObjectSetString(0, objectName, OBJPROP_TEXT, text);
}

/**
 * Elliott上下FITの有効・無効を切り替える。
 */
void toggleElliotVerticalFit() {
    if (g_drawElliotVerticalFit == NULL || g_elliotAll == NULL) {
        updateElliotVerticalFitButton();

        return;
    }

    if (g_drawElliotVerticalFit.isEnabled()) {
        if (!g_drawElliotVerticalFit.restore()) {
            updateElliotVerticalFitButton();

            return;
        }
    } else {
        if (!g_drawElliotVerticalFit.enable(g_elliotAll)) {
            updateElliotVerticalFitButton();

            return;
        }
    }

    updateElliotVerticalFitButton();
    redrawElliotInfo();
}

/**
 * 表示範囲または分析結果に合わせてElliott上下FITを更新する。
 *
 * @param fromForce trueの場合、表示範囲が同じでも再計算する
 * @return 価格軸を更新した場合true
 */
bool updateElliotVerticalFit(bool fromForce) {
    if (g_drawElliotVerticalFit == NULL || g_elliotAll == NULL) {
        return false;
    }

    return g_drawElliotVerticalFit.update(g_elliotAll, fromForce);
}

/**
 * Elliott上下FITボタンを削除する。
 */
void deleteElliotVerticalFitButton() {
    ObjectDelete(0, getElliotVerticalFitButtonName());
}

/**
 * GMMA表示用インジケータを設定する。
 */
void setGmmaIndicator() {
    deleteGmmaIndicator();

    g_gmmaIndicator = new GmmaIndicator(g_marketContext);
    g_gmmaIndicator.init(g_oscillatorHandlePool);
}

/**
 * GMMA表示用インジケータを削除する。
 */
void deleteGmmaIndicator() {
    if (g_gmmaIndicator != NULL) {
        g_gmmaIndicator.deinit();
        delete g_gmmaIndicator;
        g_gmmaIndicator = NULL;
    }
}

/**
 * 日本時間表示を設定する。
 */
void setJapanTimeAxisView() {
    deleteJapanTimeAxisView();

    g_japanTimeAxisView = new JapanTimeAxisView(g_marketContext);
    g_japanTimeAxisView.create();
}

/**
 * 日本時間表示を更新する。
 */
void updateJapanTimeAxisView() {
    if (g_japanTimeAxisView == NULL) {
        return;
    }

    g_japanTimeAxisView.update();
}

/**
 * 日本時間表示を削除する。
 */
void deleteJapanTimeAxisView() {
    if (g_japanTimeAxisView != NULL) {
        g_japanTimeAxisView.destroy();
        delete g_japanTimeAxisView;
        g_japanTimeAxisView = NULL;
    }
}

/**
 * EMA200表示用インジケータを設定する。
 */
void setEma200Indicator() {
    deleteEma200Indicator();

    g_ema200Indicator = new Ema200Indicator(g_marketContext);
    g_ema200Indicator.init(g_oscillatorHandlePool);
}

/**
 * EMA200表示用インジケータを更新する。
 */
void updateEma200Indicator() {
    if (g_ema200Indicator == NULL) {
        return;
    }

    g_ema200Indicator.update(g_isTimer);
}

/**
 * EMA200表示用インジケータを削除する。
 */
void deleteEma200Indicator() {
    if (g_ema200Indicator != NULL) {
        g_ema200Indicator.deinit();
        delete g_ema200Indicator;
        g_ema200Indicator = NULL;
    }
}










