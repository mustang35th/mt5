//+------------------------------------------------------------------+
//|                                                ElliotAllList.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>

/**
 * 複数シンボルのElliotAllをまとめて管理するクラス。
 *
 * Market Watchの対象シンボルを分析し、一覧の生成とログ出力を行う。
 */
class ElliotAllList {
public:
    /** 複数シンボル分析の基準となる市場コンテキスト */
    MarketContext marketContext;
    
    /** シンボル別オシレーターハンドル管理クラス */
    OscillatorHandleManager *oscillatorHandleManager;
    
    /** シンボル別ElliotAll一覧 */
    CArrayObj elliotAllList;
    
    /**
     * 複数シンボル分析用コンテキストで初期化する。
     *
     * @param fromTimeFrame 分析終了時間足
     * @param fromIsTimer true: タイマー実行
     */
    ElliotAllList(ENUM_TIMEFRAMES fromTimeFrame, bool fromIsTimer) {
        MarketContext context(
            "ALL",
            fromTimeFrame,
            TimeUtil::convertTimeFrameToString(fromTimeFrame),
            0
        );
        this.initialize(context, fromIsTimer);
    }

    /**
     * 市場コンテキストとタイマー実行状態を指定して初期化する。
     *
     * @param fromMarketContext 複数シンボル分析の基準となる市場コンテキスト
     * @param fromIsTimer true: タイマー実行
     */
    ElliotAllList(MarketContext &fromMarketContext, bool fromIsTimer) {
        this.initialize(fromMarketContext, fromIsTimer);
    }

    /**
     * デストラクタ。保持したElliotAllを解放する。
     */
    ~ElliotAllList() {
        this.clearElliotAllList();
    }

    /**
     * 複数シンボル分析の基準となる市場コンテキストを設定する。
     *
     * 旧コンテキストで生成したElliotAll一覧を破棄する。
     *
     * @param fromMarketContext 複数シンボル分析の基準となる市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.clearElliotAllList();
        this.marketContext = fromMarketContext;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
    }
    
    /**
     * 対象シンボルごとのElliotAllを生成して分析する。
     *
     * @param fromOscillatorHandleManager シンボル別ハンドル管理クラス
     */
    void setList(OscillatorHandleManager *fromOscillatorHandleManager) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.oscillatorHandleManager = fromOscillatorHandleManager;
        
        // 処理開始時刻を記録（ミリ秒）
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
        
        // 処理終了時刻を記録し、実行時間を計算する
        long endTime = GetTickCount();
        long elapsedTime = endTime - startTime;
        
        this.logger.debug(__FUNCTION__, StringFormat("setList:End Time: %s (MS: %d)", TimeToString(TimeCurrent(), TIME_SECONDS), endTime));
        this.logger.debug(__FUNCTION__, StringFormat("setList:Total Elapsed Time: %d ms (%.3f seconds)", elapsedTime, (double)elapsedTime / 1000.0));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /** 保持している全分析結果をログへ出力する。 */
    void print() {
        int total = this.elliotAllList.Total();

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = this.elliotAllList.At(i);

            if (elliotAll == NULL) {
                continue;
            }

            if (!elliotAll.isAnalysisSucceeded) {
                Print("ElliotAllList ERROR " + elliotAll.marketContext.symbolName);
            }

            /*if (elliotAll != NULL) {
                
                Print(elliotAll.getCsv());
            }*/
        }
    }

private:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;
    
    /** true: タイマー実行 */
    bool isTimer;

    /**
     * 市場コンテキストとタイマー実行状態を初期化する。
     *
     * @param fromMarketContext 複数シンボル分析の基準となる市場コンテキスト
     * @param fromIsTimer true: タイマー実行
     */
    void initialize(MarketContext &fromMarketContext, bool fromIsTimer) {
        this.setMarketContext(fromMarketContext);
        this.isTimer = fromIsTimer;
    }
    
    /**
     * 指定シンボルのElliotAllを生成して一覧へ追加する。
     *
     * @param fromSymbolName 追加対象シンボル
     */
    void addElliotAll(string fromSymbolName) {
        MarketContext context = this.marketContext;
        context.setSymbolName(fromSymbolName);
        ElliotAll *elliotAll = new ElliotAll(context);
        
        elliotAll.isTimer = this.isTimer;
        elliotAll.setOscillatorHandlePool(oscillatorHandleManager.getPoolByMarketContext(context));
        
        elliotAll.analyze();
        
        this.elliotAllList.Add(elliotAll);
        
        this.logger.debug(__FUNCTION__, StringFormat("symbol = %s execTime = %dms", elliotAll.marketContext.symbolName, elliotAll.execTime));
    }

    /**
     * 保持しているElliotAllを破棄し、一覧を空にする。
     */
    void clearElliotAllList() {
        int total = this.elliotAllList.Total();

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll = this.elliotAllList.At(i);

            if (elliotAll != NULL) {
                delete elliotAll;
            }
        }

        this.elliotAllList.Clear();
    }

};

