//+------------------------------------------------------------------+
//|                               ElliotReanalysisNarrowWaveLeft.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Analysis\ElliotBase.mqh>

/**
 * 左側Waveの値幅内に収まる狭い波動を再分析するクラス。
 *
 * 対象Waveと1つ前のWaveが異なる方向の場合に、前Wave終端の高値・安値内で
 * 連続するポイントを除外し、Wave一覧を再構築する。
 */
class ElliotReanalysisNarrowWaveLeft : public ElliotBase {
public:
    /**
     * 再分析条件と元Wave一覧を設定する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisNarrowWaveLeft(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, CArrayObj &fromWaveList) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromWaveList);
    }

    /**
     * 市場コンテキストおよび元Wave一覧を指定して初期化する。
     *
     * @param fromMarketContext 再分析対象の市場コンテキスト
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisNarrowWaveLeft(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.initialize(fromMarketContext, fromWaveList);
    }
    
    ~ElliotReanalysisNarrowWaveLeft() {
    }
    
    /**
     * 左側基準の狭いWaveを検索して最初の1件を再分析する。
     *
     * @return 再分析に成功した場合はtrue。対象がない場合はスキップしてtrue
     */
    bool analyze() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int waveTotal = this.waveList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("waveTotal = %d", waveTotal));
        
        if (waveTotal < 2) {
            this.logger.debug(__FUNCTION__, "対象外");
            
            return true;
        }
        
        for (int i = 0; i < waveTotal - 1; i++) {
            if (this.isTarget(i)) {
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
     * 指定Waveが左側基準の再分析対象か判定する。
     *
     * @param waveIndex 判定対象Wave位置
     * @return 前Waveと異方向で狭い波動を含む場合true
     */
    bool isTarget(int waveIndex) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        
        bool isTarget = false;
        
        if (!this.isSameTrendBeforeWave(waveIndex)) {
            double high;
            double low;
            
            this.setHighLowAtBeforeWave(waveIndex, high, low);
        
            if (this.isNarrowWave(waveIndex, high, low)) {
                isTarget = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isTarget = %s", (string)isTarget));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isTarget;
    }
    
    /**
     * 前Waveの値幅内にある対象Waveの先頭側ポイントを除外して再分析する。
     *
     * @param waveIndex 再分析対象Wave位置
     * @return Wave一覧の再構築に成功した場合true
     */
    bool reanalyze(int waveIndex) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
                
        this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        
        CArrayObj zigZagPointListReanalyze;
        
        Wave *waveCurrent = this.waveList.At(waveIndex);
        CArrayObj *fromZigZagPointList = &(waveCurrent.zigZagPointList);
        
        double high;
        double low;
            
        this.setHighLowAtBeforeWave(waveIndex, high, low);
        
        bool isBreak = false;
        
        ZigZagPoint *zigZagPoint0 = fromZigZagPointList.At(0);        
        ZigZagPointUtil::addPoint(zigZagPointListReanalyze, zigZagPoint0);
        
        for (int i = 1; i < fromZigZagPointList.Total() - 1; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            
            if (isBreak) {
                ZigZagPointUtil::addPoint(zigZagPointListReanalyze, zigZagPoint);
            } else {
                if (!this.isBetweenHighAndLow(high, low, zigZagPoint.rate)) {
                    isBreak = true;
                    
                    ZigZagPointUtil::addPoint(zigZagPointListReanalyze, zigZagPoint);
                }
            }
        }
        
        ZigZagPoint *latestZigZagPoint = waveCurrent.getLatestPoint();
        ZigZagPointUtil::addPoint(zigZagPointListReanalyze, latestZigZagPoint);
                
        LogUtil::printZigZagPointList(this.logger, __FUNCTION__, zigZagPointListReanalyze);
        
        
        CArrayObj waveListNew;
        
        // 右側波動のコピー
        for (int i = 0; i < waveIndex; i++) {
            Wave *wave = this.waveList.At(i);
            
            WaveUtil::addWave(this.logger, waveListNew, this.marketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
        }
        
        
        // 再分析Waveの追加
        WaveUtil::addWave(this.logger, waveListNew, this.marketContext, zigZagPointListReanalyze, waveCurrent.isMotive, waveCurrent.isUptrend);
        
        // 残りのコピー
        for (int i = waveIndex + 1; i < this.waveList.Total(); i++) {
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
    
    /**
     * 対象Waveに基準値幅内の連続2ポイントがあるか判定する。
     *
     * @param waveIndex 判定対象Wave位置
     * @param high 基準高値
     * @param low 基準安値
     * @return 値幅内に連続2ポイントがある場合true
     */
    bool isNarrowWave(int waveIndex, double high, double low) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        
        bool isNarrowWave = false;
        
        Wave *wave = this.waveList.At(waveIndex);
        CArrayObj *fromZigZagPointList = &(wave.zigZagPointList);
        
        for (int i = 0; i < fromZigZagPointList.Total() - 2; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            ZigZagPoint *zigZagPointNext = fromZigZagPointList.At(i + 1);
            
            if (this.isBetweenHighAndLow(high, low, zigZagPoint.rate)
                    && this.isBetweenHighAndLow(high, low, zigZagPointNext.rate)) {
                isNarrowWave = true;
                break;
            }
        }
                
        this.logger.debug(__FUNCTION__, StringFormat("isNarrowWave = %s", (string)isNarrowWave));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isNarrowWave;
    }
    
    
};







