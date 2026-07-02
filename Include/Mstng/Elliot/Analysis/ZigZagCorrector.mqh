//+------------------------------------------------------------------+
//|                                              ZigZagCorrector.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\Log\LogUtil.mqh>

/**
 * 下位足ZigZagポイントを上位足ポイントの時刻へ同期するクラス。
 *
 * 上位足ポイントに対応する下位足ポイントが存在しない場合、対象区間で
 * 最も適切な高値または安値へ下位足ポイントを補正する。
 */
class ZigZagCorrector {
public:
    /** 補正対象の市場コンテキスト */
    MarketContext marketContext;
    
    /** 補正対象の下位足ZigZagポイント一覧 */
    CArrayObj orgZigZagPointList;
    
    /**
     * シンボル名と時間足を指定して初期化する。
     *
     * @param fromSymbolName 補正対象シンボル
     * @param fromTimeFrame 補正対象時間足
     */
    ZigZagCorrector(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.setMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 補正対象の市場コンテキスト
     */
    ZigZagCorrector(MarketContext &fromMarketContext) {
        this.setMarketContext(fromMarketContext);
    }
    
    /**
     * デストラクタ。
     */
    ~ZigZagCorrector() {
    }

    /**
     * 補正対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 補正対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.orgZigZagPointList.Clear();
        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * 下位足ZigZagポイントを上位足のポイント位置へ補正する。
     *
     * @param elliotHigher 上位足Elliott分析結果
     * @param fromZigZagPointList 補正対象の下位足ポイント列
     */
    void correct(Elliot &elliotHigher, CArrayObj &fromZigZagPointList) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        // 同期するのは分析後に展開したZigZag
        // 上位足のポイント内に下位足のポイントがあるか判定
        // ない場合、近くポイントを移動
        // 上位足topの場合、下位足もtop
        
        // まず全体コピー
        ZigZagPointUtil::copyZigZagPointList(fromZigZagPointList, this.orgZigZagPointList);
        
        CArrayObj waveListHigher;
        WaveUtil::copyWaveList(&(elliotHigher.waveList), waveListHigher);
        
        CArrayObj zigZagPointListHigher;
        ZigZagPointUtil::makeZigZagPointListFromWaveList(this.logger, waveListHigher, zigZagPointListHigher, true);
        
        // 上位足ポイント内にあるか判定
        int higherTotal = zigZagPointListHigher.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("higherTotal = %d", higherTotal));
        
        for (int i = 0; i < higherTotal; i++) {
            ZigZagPoint *zigZagPointHigher = zigZagPointListHigher.At(i);
            
            bool isInsideHigherPoint = this.isInsideHigherPoint(zigZagPointHigher);
            
            if (!isInsideHigherPoint) {
                this.logger.debug(__FUNCTION__, StringFormat("上位足ポイントの繰り返し i = %d", i));
                this.logger.debug(__FUNCTION__, "上位足ポイントの範囲外");
                
                this.logger.debug(__FUNCTION__, zigZagPointHigher.toString());
                
                this.correctPoint(zigZagPointHigher);
            }
            
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

private:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;

    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 補正対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 1つの上位足ポイントに対応する下位足ポイントを補正する。
     *
     * @param zigZagPointHigher 補正基準となる上位足ポイント
     */
    void correctPoint(ZigZagPoint &zigZagPointHigher) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        // 補正対象のPoint位置検索
        int correctIndex = this.getCorrectIndex(zigZagPointHigher);
        
        this.logger.debug(__FUNCTION__, StringFormat("correctIndex = %d", correctIndex));
        
        if (correctIndex == -1) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return;
        }
        
        
        ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(correctIndex);
        
        this.logger.debug(__FUNCTION__, "補正前");
        this.logger.debug(__FUNCTION__, zigZagPoint.toString());
        
        int leftIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, zigZagPointHigher.barTime);
        int rightIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, zigZagPointHigher.barTimeNext);
        
        int position = rightIndex;
        double rateNew = 0;
        
        if (zigZagPoint.isPeak) {  // 買い
            for (int i = rightIndex; i <= leftIndex; i++) {
                double rate = iHigh(this.marketContext.symbolName, this.marketContext.timeFrame, i);
                
                if (rate >= rateNew) {
                    position = i;
                    rateNew = rate;
                }
            }
            
        } else {    // 売り
            rateNew = 1000;
            
            for (int i = rightIndex; i <= leftIndex; i++) {
                double rate = iLow(this.marketContext.symbolName, this.marketContext.timeFrame, i);
                
                if (rate <= rateNew) {
                    position = i;
                    rateNew = rate;
                }
            }
        
        }
        
        zigZagPoint.rate = rateNew;
        zigZagPoint.setBarIndexAndTime(this.marketContext, position);
        zigZagPoint.isCorrect = true;
        
        this.logger.debug(__FUNCTION__, "補正後");
        this.logger.debug(__FUNCTION__, zigZagPoint.toString());
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 上位足ポイントの期間内に対応する下位足ポイントがあるか判定する。
     *
     * @param zigZagPointHigher 判定基準となる上位足ポイント
     * @return 対応する下位足ポイントがある場合true
     */
    bool isInsideHigherPoint(ZigZagPoint &zigZagPointHigher) {
            
        for (int i = 0; i < this.orgZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(i);
            
            if (zigZagPoint.barTimeNext < zigZagPointHigher.barTime) {  // 上位ポイント左側より過去の場合
                return false;
            }
            
            if (zigZagPointHigher.barTime <= zigZagPoint.barTime
                    && zigZagPoint.barTime <= zigZagPointHigher.barTimeNext) {
                return true;
            }
        }
        
        return true;
    }
    
    /**
     * 上位足ポイントの期間から補正対象となる下位足位置を取得する。
     *
     * @param zigZagPointHigher 補正基準となる上位足ポイント
     * @return 補正対象インデックス。対象がない場合-1
     */
    int getCorrectIndex(ZigZagPoint &zigZagPointHigher) {
        int leftIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, zigZagPointHigher.barTime);
        int rightIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, zigZagPointHigher.barTimeNext);
        
        
        // 左側から検索
        int index = this.getLeftIndex(leftIndex);
        
        ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(index);
        
        if (zigZagPointHigher.isPeak == zigZagPoint.isPeak) {
            return index;
        }
        
        
        // 右側の検索
        index = this.getRightIndex(rightIndex);
        
        zigZagPoint = this.orgZigZagPointList.At(index);
        
        if (zigZagPointHigher.isPeak == zigZagPoint.isPeak) {
            return index;
        }
        
        return -1;
    }
    
    /**
     * 左境界より過去側にある最初のポイント位置を取得する。
     *
     * @param leftIndex 左境界のバーインデックス
     * @return 該当位置。存在しない場合-1
     */
    int getLeftIndex(int leftIndex) {
        
        for (int i = 0; i < this.orgZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(i);
            
            if (zigZagPoint.barIndex > leftIndex) {
                return i;
            }
        }
        
        return -1;
    }
    
    /**
     * 右境界より過去側にあるポイントの直前位置を取得する。
     *
     * @param rightIndex 右境界のバーインデックス
     * @return 該当位置。存在しない場合-1
     */
    int getRightIndex(int rightIndex) {
        
        for (int i = 0; i < this.orgZigZagPointList.Total() - 1; i++) {
            ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(i + 1);
            
            if (zigZagPoint.barIndex > rightIndex) {
                return i;
            }
        }
        
        return -1;
    }
    
};







