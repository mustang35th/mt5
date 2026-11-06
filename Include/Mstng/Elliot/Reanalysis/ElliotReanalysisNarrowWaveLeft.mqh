//+------------------------------------------------------------------+
//|                               ElliotReanalysisNarrowWaveLeft.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Analysis\ElliotBase.mqh>
#include <Mstng\Elliot\Reanalysis\ElliotReanalysisWaveList.mqh>

/**
 * 左側Waveの値幅内に収まる狭い波動を再分析するクラス。
 *
 * 対象Waveと1つ前のWaveが異なる方向の場合に、前Wave終端の高値・安値内で
 * 連続するポイントを除外し、Wave一覧を再構築する。
 * 対象Waveの先頭側を調整して、左側Waveとの重なりを整理する。
 */
class ElliotReanalysisNarrowWaveLeft : public ElliotBase {
public:
    /**
     * シンボル、時間足および元Wave一覧を指定して初期化する。
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
    
    /**
     * デストラクタ。
     */
    ~ElliotReanalysisNarrowWaveLeft() {
    }
    
    /**
     * 左側基準の狭いWaveを検索し、最初に見つかった1件を再分析する。
     *
     * @return 再分析に成功した場合true。対象がない場合もtrue
     */
    bool analyze() {
        this.reanalysisPerformed = false;

        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int waveTotal = this.waveList.Total();
        
        if (this.logger.isDebugOutputEnabled()) {
            this.logger.debug(__FUNCTION__, StringFormat("waveTotal = %d", waveTotal));
        }
        
        if (waveTotal < 2) {
            this.logger.debug(__FUNCTION__, "対象外");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
            
            return true;
        }
        
        for (int i = 0; i < waveTotal - 1; i++) {
            double high = 0.0;
            double low = 0.0;

            if (this.isTarget(i, high, low)) {
                this.reanalysisPerformed = true;

                if (!this.reanalyze(i, high, low)) {
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
    
    /**
     * 直前の分析処理で再分析対象を検出したかを返す。
     *
     * @return 対象を検出して再分析を試行した場合true。成否とは別に保持する
     */
    bool wasReanalysisPerformed() const {
        return this.reanalysisPerformed;
    }

private:
    /** 直前の分析処理で再分析を試行した場合true。 */
    bool reanalysisPerformed;

    /**
     * 市場コンテキストおよび元Wave一覧を初期化する。
     *
     * @param fromMarketContext 再分析対象の市場コンテキスト
     * @param fromWaveList 再分析対象Wave一覧
     */
    void initialize(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.logger.setLevel(LOG_INFO);
        this.reanalysisPerformed = false;

        this.init(fromMarketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        WaveUtil::copyWaveList(fromWaveList, this.waveList);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定Waveが左側基準の再分析対象か判定する。
     *
     * 1つ前のWaveと異方向で、前Wave終端の値幅内に連続ポイントがある場合に
     * 再分析対象とする。
     *
     * @param waveIndex 判定対象Wave位置
     * @param fromHigh 判定に使用した高値。戻り値がtrueの場合に再分析で使用する
     * @param fromLow 判定に使用した安値。戻り値がtrueの場合に再分析で使用する
     * @return 前Waveと異方向で狭い波動を含む場合true
     */
    bool isTarget(int waveIndex, double &fromHigh, double &fromLow) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        bool isDebugOutputEnabled = this.logger.isDebugOutputEnabled();
        
        
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        }
        
        bool isTarget = false;
        
        if (!this.isSameTrendBeforeWave(waveIndex)) {
            this.setHighLowAtBeforeWave(waveIndex, fromHigh, fromLow);
        
            if (this.isNarrowWave(waveIndex, fromHigh, fromLow)) {
                isTarget = true;
            }
        }
        
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("isTarget = %s", (string)isTarget));
        }
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isTarget;
    }
    
    /**
     * 前Waveの値幅内にある対象Waveの先頭側ポイントを除外して再分析する。
     *
     * 先頭ポイントと最新ポイントを保持し、前Wave終端の値幅を抜けた位置から
     * 中間ポイントを再分析用ポイント列へ追加する。
     *
     * @param waveIndex 再分析対象Wave位置
     * @param fromHigh 対象判定で取得した基準高値
     * @param fromLow 対象判定で取得した基準安値
     * @return Wave一覧の再構築に成功した場合true
     */
    bool reanalyze(int waveIndex, double fromHigh, double fromLow) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
                
        if (this.logger.isDebugOutputEnabled()) {
            this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        }
        
        CArrayObj zigZagPointListReanalyze;
        
        Wave *waveCurrent = this.waveList.At(waveIndex);
        this.buildReanalysisPoints(waveCurrent, fromHigh, fromLow, zigZagPointListReanalyze);

        LogUtil::printZigZagPointList(this.logger, __FUNCTION__, zigZagPointListReanalyze);


        ElliotReanalysisWaveList::replaceWaveRange(this.logger, this.marketContext, this.waveList,
                waveIndex, 1, zigZagPointListReanalyze, waveCurrent.isMotive, waveCurrent.isUptrend);

        if (!this.makeZigZagPointListAndReanalyze()) {
            this.logger.error(__FUNCTION__, "makeZigZagPointListAndReanalyze false");

            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

    /**
     * 左側基準の狭い波動を除いたポイント列を生成する。
     *
     * 両端のポイントを保持し、基準値幅を抜けた位置から残りの中間ポイントを追加する。
     * 先頭側から走査し、生成先の末尾へ順に追加する。
     *
     * @param fromWaveCurrent 再分析対象Wave
     * @param fromHigh 対象判定で取得した基準高値
     * @param fromLow 対象判定で取得した基準安値
     * @param fromResult 生成先。呼び出し元が所有する空のポイント一覧
     */
    void buildReanalysisPoints(
        Wave &fromWaveCurrent,
        double fromHigh,
        double fromLow,
        CArrayObj &fromResult
    ) {
        CArrayObj *fromZigZagPointList = &(fromWaveCurrent.zigZagPointList);
        
        bool isBreak = false;
        
        ZigZagPoint *zigZagPoint0 = fromZigZagPointList.At(0);        
        ZigZagPointUtil::addPoint(fromResult, zigZagPoint0);
        
        for (int i = 1; i < fromZigZagPointList.Total() - 1; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            
            if (isBreak) {
                ZigZagPointUtil::addPoint(fromResult, zigZagPoint);
            } else {
                if (!this.isBetweenHighAndLow(fromHigh, fromLow, zigZagPoint.rate)) {
                    isBreak = true;
                    
                    ZigZagPointUtil::addPoint(fromResult, zigZagPoint);
                }
            }
        }
        
        ZigZagPoint *latestZigZagPoint = fromWaveCurrent.getLatestPoint();
        ZigZagPointUtil::addPoint(fromResult, latestZigZagPoint);
    }

    /**
     * 対象Waveに基準値幅内の連続2ポイントがあるか判定する。
     *
     * 前Wave終端の高値と安値の内側に、対象Wave内の隣接ポイントが
     * 2つ続けて入る場合に狭い波動とみなす。
     *
     * @param waveIndex 判定対象Wave位置
     * @param high 基準高値
     * @param low 基準安値
     * @return 値幅内に連続2ポイントがある場合true
     */
    bool isNarrowWave(int waveIndex, double high, double low) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        bool isDebugOutputEnabled = this.logger.isDebugOutputEnabled();
        
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        }
        
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
                
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("isNarrowWave = %s", (string)isNarrowWave));
        }
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isNarrowWave;
    }
    
    
};







