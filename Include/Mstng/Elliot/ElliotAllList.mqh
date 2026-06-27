//+------------------------------------------------------------------+
//|                                                ElliotAllList.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>

class ElliotAllList {
public:
    ENUM_TIMEFRAMES timeFrame;
    string timeFrameLabel;
    
    OscillatorHandleManager *oscillatorHandleManager;
    
    CArrayObj elliotAllList;
    
    ElliotAllList(ENUM_TIMEFRAMES fromTimeFrame, bool fromIsTimer) {
        //this.logger.setLevel(LOG_INFO);
        this.logger.setSymbolNameAndTimeFrame("ALL", fromTimeFrame);
        
        this.timeFrame = fromTimeFrame;
        this.timeFrameLabel = TimeUtil::convertTimeFrameToString(this.timeFrame);
        
        this.isTimer = fromIsTimer;
    }

    ~ElliotAllList() {
        int total = this.elliotAllList.Total();

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = this.elliotAllList.At(i);

            if (elliotAll != NULL) {
                delete elliotAll;
            }
        }
    }
    
    void setList(OscillatorHandleManager *fromOscillatorHandleManager) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.oscillatorHandleManager = fromOscillatorHandleManager;
        
        // ⏰ 処理開始時刻を記録 (ミリ秒)
        long startTime = GetTickCount();
        
        this.logger.debug(__FUNCTION__, StringFormat("setList:Start Time: %s (MS: %d)", TimeToString(TimeCurrent(), TIME_SECONDS), startTime));
    
    
        SymbolNameInfoAll symbolNameInfoAll;
        
        const int total = symbolNameInfoAll.size();

        int count = 0;
        
        for (int i = 0; i < total; i++) {
            SymbolNameInfo *info = symbolNameInfoAll.getSymbolNameInfo(i);
            
            if (info == NULL) {
                continue;
            }

            const string symbol = info.symbolName;
            
            if (info.isTarget) {
                this.addElliotAll(symbol);
                count++;
            }
            
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("symbolNameInfoAll isTarget = %d", count));
        this.logger.debug(__FUNCTION__, StringFormat("elliotAllList = %d", this.elliotAllList.Total()));
        
        // ⏳ 処理終了時刻を記録し、実行時間を計算
        long endTime = GetTickCount();
        long elapsedTime = endTime - startTime;
        
        this.logger.debug(__FUNCTION__, StringFormat("setList:End Time: %s (MS: %d)", TimeToString(TimeCurrent(), TIME_SECONDS), endTime));
        this.logger.debug(__FUNCTION__, StringFormat("setList:Total Elapsed Time: %d ms (%.3f seconds)", elapsedTime, (double)elapsedTime / 1000.0));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    void print() {
        int total = this.elliotAllList.Total();

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = this.elliotAllList.At(i);

            if (elliotAll != NULL) {
                //Print("symbolName -> " + elliotAll.symbolName);
                //Print(elliotAll.getText());
                
                Print(elliotAll.getCsv());
            }
        }
    }

private:
    Logger logger;
    
    bool isTimer;
    
    void addElliotAll(string fromSymbolName) {
        ElliotAll *elliotAll = new ElliotAll(fromSymbolName, this.timeFrame);
        
        elliotAll.isTimer = this.isTimer;
        elliotAll.setOscillatorHandlePool(oscillatorHandleManager.getPoolBySymbol(fromSymbolName));
        
        elliotAll.analyze();
        
        this.elliotAllList.Add(elliotAll);
        
        this.logger.debug(__FUNCTION__, StringFormat("symbol = %s execTime = %dms", elliotAll.symbolName, elliotAll.execTime));
    }

};