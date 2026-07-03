//+------------------------------------------------------------------+
//|                                                       ZigZag.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZagLogic.mqh>
#include <Mstng\Elliot\ZigZagPoint.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * ZigZag クラスは、標準 ZigZag インジケータをラップし、
 * 転換ポイントを ZigZagPoint オブジェクトとして収集します。
 *
 * - コンストラクタで Depth / Deviation / Backstep を設定します。
 * - update() メソッド呼び出しごとに iCustom で ZigZag を新規取得します。
 * - 非ゼロの値（ZigZag の節目）を ZigZagPoint として保持します。
 */
class ZigZag {
public:
    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;

    CArrayObj zigZagPointList;
    
    /**
     * ZigZag クラスのコンストラクタ。
     * ここで対象シンボル、時間足、ZigZag パラメータを設定します。
     *
     * @param fromSymbolName     対象シンボル名
     * @param fromTimeFrame      対象時間足
     * @param fromDepth          ZigZag の Depth（初期値 12）
     * @param fromDeviation      ZigZag の Deviation（初期値 5）
     * @param fromBackstep       ZigZag の Backstep（初期値 3）
     */
    ZigZag(string fromSymbolName,
           ENUM_TIMEFRAMES fromTimeFrame,
           int fromDepth = 12,
           int fromDeviation = 5,
           int fromBackstep = 3) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromDepth, fromDeviation, fromBackstep);
    }

    /**
     * 市場コンテキストとZigZagパラメータを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromDepth ZigZagのDepth
     * @param fromDeviation ZigZagのDeviation
     * @param fromBackstep ZigZagのBackstep
     */
    ZigZag(
        MarketContext &fromMarketContext,
        int fromDepth = 12,
        int fromDeviation = 5,
        int fromBackstep = 3
    ) {
        this.initialize(fromMarketContext, fromDepth, fromDeviation, fromBackstep);
    }

    /**
     * デストラクタ。
     * 内部で確保した ZigZagPoint オブジェクトを解放します。
     */
    ~ZigZag() {
        this.clearPoints();
    }

    /**
     * 分析対象の市場コンテキストを設定する。
     *
     * 旧市場で取得したZigZagポイントを破棄し、Loggerを更新する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.clearPoints();
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
    }

    /**
     * 新規の ZigZag ポイントを条件成立時に先頭へ追加します。
     *
     * @param isBuy 上昇方向判定フラグ
     */
    void addPoint(bool isBuy) {
        ZigZagPoint *zigZagPoint0 = this.zigZagPointList.At(0);
        
        if (this.isPointAddCondition(isBuy, zigZagPoint0)) {
            ZigZagPoint *zigZagPoint = new ZigZagPoint(this.marketContext);
            
            zigZagPoint.isAddedPoint = true;
            zigZagPoint.isPeak = !zigZagPoint0.isPeak;
            
            if (zigZagPoint.isPeak) {
                this.getZigZagHigh(0, zigZagPoint0.barIndex, zigZagPoint);
            } else {
                this.getZigZagLow(0, zigZagPoint0.barIndex, zigZagPoint);
            }
            
            this.zigZagPointList.Insert(zigZagPoint, 0);
        }
    }
    
    /**
     * 内部に保持しているすべての ZigZagPoint オブジェクトを解放します。
     * ポイントリストを再利用する前に呼び出されます。
     */
    void clearPoints() {
        int totalPoints = this.zigZagPointList.Total();

        for (int i = 0; i < totalPoints; i++) {
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);

            if (zigZagPoint != NULL) {
                delete zigZagPoint;
            }
        }

        this.zigZagPointList.Clear();
    }

    /**
     * ZigZag インジケータを毎回新規に取得してポイントを更新します。
     *
     * @return 正常に更新できた場合 true、失敗した場合 false
     */
    bool update(int fromMaxBars) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        this.logger.debug(__FUNCTION__, StringFormat("fromMaxBars = %d", fromMaxBars));
        
        ZigZagLogic zigZagLogic(this.marketContext, this.depth, this.deviation, this.backstep);
        
        int ratesTotal = zigZagLogic.calculate(fromMaxBars);
        
        this.logger.debug(__FUNCTION__, StringFormat("ratesTotal = %d", ratesTotal));
        
        this.clearPoints();
        
        for (int i = ratesTotal - 1; i >= 0; i--) {
            if (zigZagLogic.zigZagBuffer[i] != 0.0) {
                int relativeIndex = (ratesTotal - 1) - i;   // 相対インデックスを計算 (最新バーを0とする)
                                
                ZigZagPoint *zigZagPoint = new ZigZagPoint(this.marketContext);
                
                zigZagPoint.rate = zigZagLogic.zigZagBuffer[i];
                zigZagPoint.isPeak = this.isPeak(zigZagLogic.searchModeBuffer[i]);
                
                zigZagPoint.setBarIndexAndTime(this.marketContext, relativeIndex);
                
                this.zigZagPointList.Add(zigZagPoint);
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("zigZagPointList.Total = %d", this.zigZagPointList.Total()));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        if (this.zigZagPointList.Total() == 0) {
            return false;
        }

        return true;
    }

private:
    Logger logger;
    int depth;
    int deviation;
    int backstep;

    /**
     * 市場コンテキストおよびZigZagパラメータを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromDepth ZigZagのDepth
     * @param fromDeviation ZigZagのDeviation
     * @param fromBackstep ZigZagのBackstep
     */
    void initialize(
        MarketContext &fromMarketContext,
        int fromDepth,
        int fromDeviation,
        int fromBackstep
    ) {
        this.logger.setLevel(LOG_INFO);

        this.depth = fromDepth;
        this.deviation = fromDeviation;
        this.backstep = fromBackstep;
        this.setMarketContext(fromMarketContext);
    }

    /**
     * 指定区間の最高値（High）を取得し、ZigZagPoint に設定する。
     *
     * @param start        取得開始シフト（0が最新足）
     * @param end          取得終了シフト（start < end）
     * @param zigZagPoint  設定対象
     */
    void getZigZagHigh(int start, int end, ZigZagPoint &zigZagPoint) {
        if (start < 0) {
            start = 0;
        }
    
        if (end <= start) {
            // 不正範囲の場合は start を採用（最低限動くように）
            end = start + 1;
        }
    
        int position = start;
        double high = iHigh(this.marketContext.symbolName, this.marketContext.timeFrame, position);
    
        for (int i = start + 1; i < end; i++) {
            double highCurrent = iHigh(this.marketContext.symbolName, this.marketContext.timeFrame, i);
    
            if (highCurrent >= high) {
                high = highCurrent;
                position = i;
            }
        }
    
        zigZagPoint.rate = high;
        zigZagPoint.setBarIndexAndTime(this.marketContext, position);
    }

    /**
     * 指定区間の最安値（Low）を取得し、ZigZagPoint に設定する。
     *
     * @param start        取得開始シフト（0が最新足）
     * @param end          取得終了シフト（start < end）
     * @param zigZagPoint  設定対象
     */
    void getZigZagLow(int start, int end, ZigZagPoint &zigZagPoint) {
        if (start < 0) {
            start = 0;
        }
    
        if (end <= start) {
            // 不正範囲の場合は start を採用（最低限動くように）
            end = start + 1;
        }
    
        int position = start;
        double low = iLow(this.marketContext.symbolName, this.marketContext.timeFrame, position);
    
        for (int i = start + 1; i < end; i++) {
            double lowCurrent = iLow(this.marketContext.symbolName, this.marketContext.timeFrame, i);
    
            if (lowCurrent <= low) {
                low = lowCurrent;
                position = i;
            }
        }
    
        zigZagPoint.rate = low;
        zigZagPoint.setBarIndexAndTime(this.marketContext, position);
    }

    // 山か判定
    bool isPeak(int fromSearchMode) {
        return fromSearchMode == 1;
    }
    
    /**
     * ポイント追加判定を行う。
     *
     * 判定内容：
     * - BUY の場合は zigZagPoint0 が山（peak）でないなら追加対象
     * - SELL の場合は zigZagPoint0 が山（peak）なら追加対象
     *
     * @param isBuy         売買方向（true: BUY, false: SELL）
     * @param zigZagPoint0  判定対象ポイント
     *
     * @return 追加する場合 true
     */
    bool isPointAddCondition(bool isBuy, ZigZagPoint &zigZagPoint0) {
        bool isNeedAdd = false;
    
        if (isBuy) {
            if (!zigZagPoint0.isPeak) {
                isNeedAdd = true;
            }
        } else {
            if (zigZagPoint0.isPeak) {
                isNeedAdd = true;
            }
        }
    
        return isNeedAdd;
    }
};










