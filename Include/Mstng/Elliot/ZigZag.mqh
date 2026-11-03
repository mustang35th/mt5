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
 * 標準ZigZag相当のロジックを使い、転換ポイントをZigZagPointとして収集するクラス。
 *
 * Depth、Deviation、Backstepを指定してZigZagLogicを実行し、
 * 検出した非ゼロ値をポイント一覧へ保持する。
 */
class ZigZag {
public:
    /** 分析対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** ZigZagの検出ポイントを保持するリスト。 */
    CArrayObj zigZagPointList;
    
    /**
     * シンボル、時間足およびZigZagパラメータを指定して初期化する。
     *
     * @param fromSymbolName 対象シンボル名
     * @param fromTimeFrame 対象時間足
     * @param fromDepth ZigZagのDepth
     * @param fromDeviation ZigZagのDeviation
     * @param fromBackstep ZigZagのBackstep
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
     *
     * 内部で確保したZigZagPointオブジェクトを解放する。
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
     * 条件成立時に補完ZigZagポイントを先頭へ追加する。
     *
     * @param isBuy 上昇方向判定フラグ
     * @return 補完不要または追加成功の場合true。価格データ取得などに失敗した場合false。
     */
    bool addPoint(bool isBuy) {
        ZigZagPoint *zigZagPoint0 = this.zigZagPointList.At(0);

        if (zigZagPoint0 == NULL) {
            return false;
        }
        
        if (this.isPointAddCondition(isBuy, zigZagPoint0)) {
            ZigZagPoint *zigZagPoint = new ZigZagPoint(this.marketContext);

            if (zigZagPoint == NULL) {
                return false;
            }
            
            zigZagPoint.isAddedPoint = true;
            zigZagPoint.isPeak = !zigZagPoint0.isPeak;

            bool isPriceReady = false;
            
            if (zigZagPoint.isPeak) {
                isPriceReady = this.getZigZagHigh(0, zigZagPoint0.barIndex, zigZagPoint);
            } else {
                isPriceReady = this.getZigZagLow(0, zigZagPoint0.barIndex, zigZagPoint);
            }

            if (!isPriceReady || !this.zigZagPointList.Insert(zigZagPoint, 0)) {
                delete zigZagPoint;

                return false;
            }
            
        }

        return true;
    }
    
    /**
     * 内部に保持しているすべてのZigZagPointオブジェクトを解放する。
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
     * ZigZagLogicを計算し、検出ポイントを更新する。
     *
     * @param fromMaxBars 処理対象とする最大バー数
     * @return 正常に更新できた場合true
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
    /** ロガー。 */
    Logger logger;

    /** ZigZagのDepthパラメータ。 */
    int depth;

    /** ZigZagのDeviationパラメータ。 */
    int deviation;

    /** ZigZagのBackstepパラメータ。 */
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
     * 指定区間の最高値を取得し、ZigZagPointへ設定する。
     *
     * @param start 取得開始シフト。0が最新足
     * @param end 取得終了シフト。このシフトは含めない。
     * @param zigZagPoint 設定対象ポイント
     * @return 対象区間の全価格を取得して設定できた場合true。
     */
    bool getZigZagHigh(int start, int end, ZigZagPoint &zigZagPoint) {
        if (start < 0) {
            start = 0;
        }
    
        if (end <= start) {
            // 不正範囲の場合は start を採用（最低限動くように）
            end = start + 1;
        }
    
        int count = end - start;
        double highs[];
        ArraySetAsSeries(highs, true);

        ResetLastError();
        int copied = CopyHigh(this.marketContext.symbolName, this.marketContext.timeFrame, start, count, highs);
        if (copied != count) {
            this.logger.error(__FUNCTION__, StringFormat(
                "Failed to copy high data. requested=%d copied=%d error=%d", count, copied, GetLastError()));

            return false;
        }

        int position = start;
        double high = highs[0];
    
        for (int i = 1; i < count; i++) {
            double highCurrent = highs[i];
    
            if (highCurrent >= high) {
                high = highCurrent;
                position = start + i;
            }
        }
    
        zigZagPoint.rate = high;
        zigZagPoint.setBarIndexAndTime(this.marketContext, position);

        return true;
    }

    /**
     * 指定区間の最安値を取得し、ZigZagPointへ設定する。
     *
     * @param start 取得開始シフト。0が最新足
     * @param end 取得終了シフト。このシフトは含めない。
     * @param zigZagPoint 設定対象ポイント
     * @return 対象区間の全価格を取得して設定できた場合true。
     */
    bool getZigZagLow(int start, int end, ZigZagPoint &zigZagPoint) {
        if (start < 0) {
            start = 0;
        }
    
        if (end <= start) {
            // 不正範囲の場合は start を採用（最低限動くように）
            end = start + 1;
        }
    
        int count = end - start;
        double lows[];
        ArraySetAsSeries(lows, true);

        ResetLastError();
        int copied = CopyLow(this.marketContext.symbolName, this.marketContext.timeFrame, start, count, lows);
        if (copied != count) {
            this.logger.error(__FUNCTION__, StringFormat(
                "Failed to copy low data. requested=%d copied=%d error=%d", count, copied, GetLastError()));

            return false;
        }

        int position = start;
        double low = lows[0];
    
        for (int i = 1; i < count; i++) {
            double lowCurrent = lows[i];
    
            if (lowCurrent <= low) {
                low = lowCurrent;
                position = start + i;
            }
        }
    
        zigZagPoint.rate = low;
        zigZagPoint.setBarIndexAndTime(this.marketContext, position);

        return true;
    }

    /**
     * 検索モードから山かを判定する。
     *
     * @param fromSearchMode ZigZagの検索モード
     * @return 山の場合true、谷の場合false
     */
    bool isPeak(int fromSearchMode) {
        return fromSearchMode == 1;
    }
    
    /**
     * ポイント追加判定を行う。
     *
     * BUYの場合は最新ポイントが谷、SELLの場合は最新ポイントが山なら追加対象とする。
     *
     * @param isBuy 売買方向。true: BUY、false: SELL
     * @param zigZagPoint0 判定対象ポイント
     * @return 追加する場合true
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










