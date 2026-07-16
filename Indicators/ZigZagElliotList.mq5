//+------------------------------------------------------------------+
//|                                             ZigZagElliotList.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.01"
#property indicator_chart_window

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Draw\DrawElliotAllList.mqh>
#include <Mstng\Elliot\ElliotAllList.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorEma200.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorOscillator.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>

Logger gLogger;

bool gIsTimer = true;

string gSymbolName;
ENUM_TIMEFRAMES gTimeFrame;

DrawElliotAllList *gDrawElliotAllList;
OscillatorHandleManager *gOscillatorHandleManager;

static datetime gStaticLasttime;

int OnInit() {
    //if (Util::isStrategyTester()) {
        gIsTimer = false;
    //}
    
    gSymbolName = _Symbol;
    gTimeFrame = _Period;
    
    gLogger.setLevel(LOG_INFO);
    MarketContext context(gSymbolName, gTimeFrame);
    gLogger.setMarketContext(context);
    
    LogUtil::printMethodStart(gLogger, __FUNCTION__);
    
    gDrawElliotAllList = new DrawElliotAllList(0);
    setOscillatorHandleManager();
    
    LogUtil::printMethodEnd(gLogger, __FUNCTION__, true);
    
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    LogUtil::printMethodStart(gLogger, __FUNCTION__);
    
    if (gDrawElliotAllList != NULL) {
        gDrawElliotAllList.clear();
        delete gDrawElliotAllList;
        gDrawElliotAllList = NULL;
    }

    delete gOscillatorHandleManager;
    
    LogUtil::printMethodEnd(gLogger, __FUNCTION__, true);
}

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
    
    datetime temptime = iTime(gSymbolName, gTimeFrame, 0);

    if (gStaticLasttime == temptime) {
        return(rates_total);
    }
    
    exec();
    
    gStaticLasttime = temptime;
    
    return(rates_total);
}

void exec() {
    LogUtil::printMethodStart(gLogger, __FUNCTION__);
    
    // ⏰ 処理開始時刻を記録 (ミリ秒)
    long startTime = GetTickCount();    
    gLogger.debug(__FUNCTION__, StringFormat("▼▼▼▼▼　Start Time: %s (MS: %d)", TimeToString(TimeCurrent(), TIME_SECONDS), startTime));
    
    
    ElliotAllList *elliotAllList = new ElliotAllList(gTimeFrame, gIsTimer);
    
    elliotAllList.setList(gOscillatorHandleManager);
    
    elliotAllList.print();
    
    //printStochasticOrder(elliotAllList);
    printEma200(elliotAllList);
    //printD1BuySell(elliotAllList);
    
    //printH4M15BuySell(elliotAllList);

    if (gDrawElliotAllList != NULL) {
        if (!gDrawElliotAllList.draw(elliotAllList)) {
            gLogger.error(__FUNCTION__, "failed to draw ElliotAll list panel");
        }
    }
    
    delete elliotAllList;
    
    
    // ⏳ 処理終了時刻を記録し、実行時間を計算
    long endTime = GetTickCount();
    long elapsedTime = endTime - startTime;
    
    //gLogger.debug(__FUNCTION__, StringFormat("　　　　　　　End Time: %s (MS: %d)", TimeToString(TimeCurrent(), TIME_SECONDS), endTime));
    //gLogger.debug(__FUNCTION__, StringFormat("▲▲▲▲▲　Total Elapsed Time: %d ms (%.3f seconds)", elapsedTime, (double)elapsedTime / 1000.0));
}

void setOscillatorHandleManager() {
    gOscillatorHandleManager = new OscillatorHandleManager(gTimeFrame);
    
    if (gIsTimer) {
        gOscillatorHandleManager.setTimeframesFromMn1ToAll();
    } else {
        gOscillatorHandleManager.setTimeframesFromD1ToAll();
    }
}

void printEma200(ElliotAllList *elliotAllList) {
    Print("");
    Print("▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼　Ema200　▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼");

    printElliotAllByEma200(elliotAllList, true);
    printElliotAllByEma200(elliotAllList, false);

    Print("▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲　Ema200　▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲");
}

void printElliotAllByEma200(ElliotAllList *elliotAllList, bool isBuy) {
    Print(StringFormat("Ema200 isBuy = %s", (string)isBuy));

    int total = elliotAllList.elliotAllList.Total();
    ExpertAdvisorEma200 expertAdvisorEma200(isBuy);

    for (int i = 0; i < total; i++) {
        ElliotAll *elliotAll = elliotAllList.elliotAllList.At(i);

        if (elliotAll == NULL) {
            continue;
        }

        if (expertAdvisorEma200.isEma200Candidate(elliotAll)) {
            Print("  " + elliotAll.getCsv());

            /*ExpertAdvisorOscillator *expertAdvisorOscillator = new ExpertAdvisorOscillator(elliotAll.marketContext);

            if (expertAdvisorOscillator.isStochasticMainOrder(elliotAll)) {
                if (elliotAll.elliotCurrent.isBuy == isBuy
                        && elliotAll.isBuySell(PERIOD_H4)
                        && expertAdvisorOscillator.isGmmaCross_2(elliotAll.elliotCurrent, isBuy)
                ) {
                    Print("  " + elliotAll.getCsv());
                }
            }

            delete expertAdvisorOscillator;*/
        }

    }

}

void printStochasticOrder(ElliotAllList *elliotAllList) {
    Print("");
    Print("▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼　StochasticOrder　▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼");
    
    printElliotAllByStochasticOrder(elliotAllList, true);
    printElliotAllByStochasticOrder(elliotAllList, false);
    
    Print("▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲　StochasticOrder　▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲");
}

void printElliotAllByStochasticOrder(ElliotAllList *elliotAllList, bool isBuy) {
    Print(StringFormat("StochasticOrder isBuy = %s", (string)isBuy));
    
    int total = elliotAllList.elliotAllList.Total();

    for (int i = 0; i < total; i++) {
        ElliotAll *elliotAll = elliotAllList.elliotAllList.At(i);
        
        if (elliotAll != NULL) {
            ExpertAdvisorOscillator *expertAdvisorOscillator = new ExpertAdvisorOscillator(elliotAll.marketContext);
        
            if (expertAdvisorOscillator.isStochasticMainOrder(elliotAll)) {
                if (elliotAll.elliotCurrent.isBuy == isBuy
                        && elliotAll.isBuySell(PERIOD_H4)
                        && expertAdvisorOscillator.isGmmaCross_2(elliotAll.elliotCurrent, isBuy)
                ) {
                    Print("  " + elliotAll.getCsv());
                }
            }
            
            delete expertAdvisorOscillator;
        }
        
    }
    
}

void printD1BuySell(ElliotAllList *elliotAllList) {
    Print("");
    Print("▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼　D1 BuySell　▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼");
    
    printElliotAllByCount(elliotAllList, 3);
    printElliotAllByCount(elliotAllList, -3);
    printElliotAllByCount(elliotAllList, 2);
    printElliotAllByCount(elliotAllList, -2);
    
    Print("▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲　D1 BuySell　▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲");
    //Print("");
}

void printElliotAllByCount(ElliotAllList *elliotAllList, int count) {
    Print(StringFormat("D1 BuySell = %d", count));
    
    int total = elliotAllList.elliotAllList.Total();

    for (int i = 0; i < total; i++) {
        ElliotAll *elliotAll = elliotAllList.elliotAllList.At(i);
        
        if (elliotAll != NULL) {
            Elliot *elliot = elliotAll.getElliot(PERIOD_D1);
            
            if (elliot != NULL
                    && elliot.oscillator.oscillatorCount == count
                    && elliotAll.isBuySell(PERIOD_D1)) {
                Print("  " + elliotAll.getCsv());
            }
        }
        
    }
    
}

void printH4M15BuySell(ElliotAllList *elliotAllList) {
    Print("");
    Print("▽▽▽▽▽▽▽▽▽▽ H4M15　BuySell ▽▽▽▽▽▽▽▽▽▽");
    
    printElliotAllByCount(elliotAllList, true);
    printElliotAllByCount(elliotAllList, false);
    
    Print("△△△△△△△△△△　H4M15　BuySell　△△△△△△△△△△");
    Print("");
}

void printElliotAllByCount(ElliotAllList *elliotAllList, bool isBuy) {
    Print(StringFormat("H4M15 BuySell isBuy = %s", (string)isBuy));
    
    int total = elliotAllList.elliotAllList.Total();

    for (int i = 0; i < total; i++) {
        ElliotAll *elliotAll = elliotAllList.elliotAllList.At(i);
        
        if (elliotAll != NULL) {
            if (elliotAll.isBuySellCount3(PERIOD_H4, isBuy)) {
                Print("  " + elliotAll.getCsv());
            }
        }
        
    }
    
}
