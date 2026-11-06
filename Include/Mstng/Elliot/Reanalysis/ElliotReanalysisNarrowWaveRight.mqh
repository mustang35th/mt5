//+------------------------------------------------------------------+
//|                              ElliotReanalysisNarrowWaveRight.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Analysis\ElliotBase.mqh>
#include <Mstng\Elliot\Reanalysis\ElliotReanalysisWaveList.mqh>

/**
 * 右側Waveの値幅内に収まる狭い波動を再分析するクラス。
 *
 * 対象Waveの右隣にある2ポイントWaveを基準とし、その高値・安値内で
 * 連続する対象Waveのポイントを除外してWave一覧を再構築する。
 * 対象Waveの終端側を調整して、右側Waveとの重なりを整理する。
 */
class ElliotReanalysisNarrowWaveRight : public ElliotBase {
public:
    /**
     * シンボル、時間足および元Wave一覧を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisNarrowWaveRight(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, CArrayObj &fromWaveList) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromWaveList);
    }

    /**
     * 市場コンテキストおよび元Wave一覧を指定して初期化する。
     *
     * @param fromMarketContext 再分析対象の市場コンテキスト
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisNarrowWaveRight(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.initialize(fromMarketContext, fromWaveList);
    }
    
    /**
     * デストラクタ。
     */
    ~ElliotReanalysisNarrowWaveRight() {
    }
    
    /**
     * 右側基準の狭いWaveを検索し、最初に見つかった1件を再分析する。
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
        
        // 最新は未確定のため対象外。最古側を除外し、1から走査する。
        for (int i = 1; i < waveTotal - 1; i++) {
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
     * 指定Waveが右側基準の再分析対象か判定する。
     *
     * 右隣Waveが異方向かつ2ポイント構成で、対象Wave内に右隣Waveの
     * 値幅内へ収まる連続ポイントがある場合に再分析対象とする。
     *
     * @param waveIndex 判定対象Wave位置
     * @param fromHigh 判定に使用した高値。戻り値がtrueの場合に再分析で使用する
     * @param fromLow 判定に使用した安値。戻り値がtrueの場合に再分析で使用する
     * @return 右隣が異方向の2ポイントWaveで、狭い波動を含む場合true
     */
    bool isTarget(int waveIndex, double &fromHigh, double &fromLow) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        bool isDebugOutputEnabled = this.logger.isDebugOutputEnabled();
        
        
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        }
        
        bool isTarget = false;
        
        Wave *waveCurrent = this.waveList.At(waveIndex);
        Wave *waveNext = this.waveList.At(waveIndex - 1);
        
        // 右側隣接Waveとの比較を行うため、waveIndex-1を参照する。
        bool isTargetWave = !this.isSameTrendBeforeWave(waveIndex - 1);
        bool isCurrentPointCountValid = waveCurrent.zigZagPointList.Total() > 2;
        // 右側隣接Waveは2ポイントのみを対象とする。
        bool isNextPointCountValid = waveNext.zigZagPointList.Total() == 2;

        if (isTargetWave
                && isCurrentPointCountValid
                && isNextPointCountValid) {
            this.setHighLowAtNextWave(waveIndex, fromHigh, fromLow);
        
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
     * 指定Waveの右隣にあるWave終端2点から高値と安値を取得する。
     *
     * @param fromWaveIndex 基準Wave位置
     * @param high 取得した高値を格納する変数
     * @param low 取得した安値を格納する変数
     */
    void setHighLowAtNextWave(int fromWaveIndex, double &high, double &low) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        bool isDebugOutputEnabled = this.logger.isDebugOutputEnabled();
        
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("fromWaveIndex = %d", fromWaveIndex));
        }
        
        int waveIndex = fromWaveIndex - 1;
        
        Wave *waveNext = this.waveList.At(waveIndex);
        CArrayObj *fromZigZagPointList = &(waveNext.zigZagPointList);
        
        int total = fromZigZagPointList.Total();
        
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        }
        
        ZigZagPoint *zigZagPointLast = fromZigZagPointList.At(total - 1);
        ZigZagPoint *zigZagPointLast2 = fromZigZagPointList.At(total - 2);
        
        if (zigZagPointLast2.isPeak) {
            high = zigZagPointLast2.rate;
            low = zigZagPointLast.rate;
        } else {
            high = zigZagPointLast.rate;
            low = zigZagPointLast2.rate;
        }
        
        if (isDebugOutputEnabled) {
            this.logger.debug(__FUNCTION__, StringFormat("high = %f", high));
            this.logger.debug(__FUNCTION__, StringFormat("low = %f", low));
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 右隣Waveの値幅内にある対象Waveの終端側ポイントを除外して再分析する。
     *
     * 最新ポイントと先頭ポイントを保持し、右隣Wave終端の値幅を抜けた位置から
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
     * 右側基準の狭い波動を除いたポイント列を生成する。
     *
     * 両端のポイントを保持し、基準値幅を抜けた位置から残りの中間ポイントを追加する。
     * 最新側から逆順に走査し、生成先の先頭へ順に挿入する。
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
        ZigZagPoint *latestZigZagPoint = fromWaveCurrent.getLatestPoint();

        ZigZagPointUtil::insertPoint(fromResult, latestZigZagPoint);
        
        CArrayObj *fromZigZagPointList = &(fromWaveCurrent.zigZagPointList);
        bool isBreak = false;
        
        for (int i = fromZigZagPointList.Total() - 2; i > 0; i--) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            
            if (isBreak) {
                ZigZagPointUtil::insertPoint(fromResult, zigZagPoint);
            } else {
                if (!this.isBetweenHighAndLow(fromHigh, fromLow, zigZagPoint.rate)) {
                    isBreak = true;
                    
                    ZigZagPointUtil::insertPoint(fromResult, zigZagPoint);
                }
            }
        }
        
        ZigZagPoint *zigZagPoint0 = fromZigZagPointList.At(0);        
        ZigZagPointUtil::insertPoint(fromResult, zigZagPoint0);
    }

    /**
     * 対象Waveに右隣Waveの値幅内で連続する2ポイントがあるか判定する。
     *
     * 右隣Wave終端の高値と安値の内側に、対象Wave内の隣接ポイントが
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
        
        for (int i = fromZigZagPointList.Total() - 2; i > 1; i--) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            ZigZagPoint *zigZagPointBefore = fromZigZagPointList.At(i - 1);
            
            if (this.isBetweenHighAndLow(high, low, zigZagPoint.rate)
                    && this.isBetweenHighAndLow(high, low, zigZagPointBefore.rate)) {
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







