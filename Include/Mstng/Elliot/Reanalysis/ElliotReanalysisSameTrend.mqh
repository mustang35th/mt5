//+------------------------------------------------------------------+
//|                                    ElliotReanalysisSameTrend.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Analysis\ElliotBase.mqh>

/**
 * 同じ方向で連続するWaveを統合して再分析するクラス。
 *
 * 対象Waveと1つ前のWaveが同方向の場合、前Wave終端の高値・安値を超えるまでの
 * 対象Waveポイントを除外し、2つのWaveを1つへ統合する。
 * 再構築後は、統合済みのWave一覧を再度ZigZagポイント列へ戻して分析し直す。
 */
class ElliotReanalysisSameTrend : public ElliotBase {
public:
    /**
     * シンボル、時間足および元Wave一覧を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisSameTrend(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, CArrayObj &fromWaveList) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromWaveList);
    }

    /**
     * 市場コンテキストおよび元Wave一覧を指定して初期化する。
     *
     * @param fromMarketContext 再分析対象の市場コンテキスト
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisSameTrend(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.initialize(fromMarketContext, fromWaveList);
    }
    
    /**
     * デストラクタ。
     */
    ~ElliotReanalysisSameTrend() {
    }
    
    /**
     * 同方向で連続するWaveを検索し、最初に見つかった1組を再分析する。
     *
     * @return 再分析に成功した場合true。対象がない場合もtrue
     */
    bool analyze() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        int waveTotal = this.waveList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("waveTotal = %d", waveTotal));
        
        if (waveTotal < 2) {
            this.logger.debug(__FUNCTION__, "対象外");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
            
            return true;
        }
        
        for (int i = 0; i < waveTotal - 1; i++) {
            if (this.isSameTrendBeforeWave(i)) {
                if (!this.reanalyze(i)) {
                    this.logger.error(__FUNCTION__, "reanalyze false");
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                    
                    return false;
                }
                
                break;
            }
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
private:
    /**
     * 市場コンテキストおよび元Wave一覧を初期化する。
     *
     * @param fromMarketContext 再分析対象の市場コンテキスト
     * @param fromWaveList 再分析対象Wave一覧
     */
    void initialize(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.logger.setLevel(LOG_INFO);

        this.init(fromMarketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        WaveUtil::copyWaveList(fromWaveList, this.waveList);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定Waveと1つ前のWaveを統合するための再分析を実行する。
     *
     * 前Wave終端の高値と安値を基準に、対象Waveのポイントを除外して
     * Wave一覧を再構築する。
     *
     * @param waveIndex 新しい側の対象Wave位置
     * @return 再分析に成功した場合true
     */
    bool reanalyze(int waveIndex) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        
        double high;
        double low;
        
        this.setHighLowAtBeforeWave(waveIndex, high, low);
        
        if (!this.excludePoint(waveIndex, high, low)) {
            this.logger.error(__FUNCTION__, "excludePoint false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 前Waveの値幅内にある対象Waveポイントを除外し、Wave一覧を再構築する。
     *
     * 値幅を超えるポイントがない場合は、対象Waveの最終ポイントだけを追加する。
     *
     * @param waveIndex 新しい側の対象Wave位置
     * @param high 前Wave終端の高値
     * @param low 前Wave終端の安値
     * @return Wave一覧の再構築に成功した場合true
     */
    bool excludePoint(int waveIndex, double high, double low) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        CArrayObj analyzedZigZagPointList;
        
        // 前Waveを統合先としてコピーする。
        Wave *waveBefore = this.waveList.At(waveIndex + 1);
        ZigZagPointUtil::copyZigZagPointList(waveBefore.zigZagPointList, analyzedZigZagPointList);
        
        Wave *wave = this.waveList.At(waveIndex);
        CArrayObj *fromZigZagPointList = &(wave.zigZagPointList);
        
        int addCount = 0;
        bool isBreak = false;
        
        for (int i = 1; i < fromZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            
            if (isBreak) {
                ZigZagPointUtil::addPoint(analyzedZigZagPointList, zigZagPoint);
            } else {
                double rate = zigZagPoint.rate;
                
                // 前Wave終端レンジを超えた時点から、ポイントを統合リストへ移送する。
                if (rate > high || low > rate) {
                    isBreak = true;
                    
                    ZigZagPointUtil::addPoint(analyzedZigZagPointList, zigZagPoint);
                    addCount++;
                }
                
            }
        }
        
        if (addCount == 0) {
            // 追加ポイントがない場合は、対象Waveの最終ポイントだけを必ず保持する。
            ZigZagPoint *zigZagPoint = ZigZagPointUtil::getLastNode(fromZigZagPointList);
            
            ZigZagPointUtil::addPoint(analyzedZigZagPointList, zigZagPoint);
        }
        CArrayObj waveListNew;  // 再構築用Wave一覧。
        
        // 右側Waveをコピーする。
        for (int i = 0; i < waveIndex; i++) {
            Wave *wave = this.waveList.At(i);
            
            WaveUtil::addWave(this.logger, waveListNew, this.marketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
        }
        
        
        // 再分析Waveを追加する。
        WaveUtil::addWave(this.logger, waveListNew, this.marketContext, analyzedZigZagPointList, waveBefore.isMotive, waveBefore.isUptrend);
        
        
        // 残りのWaveをコピーする。
        for (int i = waveIndex + 2; i < this.waveList.Total(); i++) {
            Wave *wave = this.waveList.At(i);
            
            WaveUtil::addWave(this.logger, waveListNew, this.marketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
        }
        
        
        WaveUtil::copyWaveList(waveListNew, this.waveList);
        
        
        if (!this.makeZigZagPointListAndReanalyze()) {
            this.logger.error(__FUNCTION__, "makeZigZagPointListAndReanalyze false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
};







