//+------------------------------------------------------------------+
//|                                          ElliotWithHigherAll.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\Elliot\Analysis\ElliotBase.mqh>
#include <Mstng\Elliot\Analysis\ElliotRecount.mqh>
#include <Mstng\Elliot\Analysis\ElliotSubwaves.mqh>
#include <Mstng\Elliot\Analysis\ElliotWithHigher.mqh>
#include <Mstng\Elliot\Analysis\ElliotWithHigherUtil.mqh>
#include <Mstng\Elliot\Analysis\ZigZagCorrector.mqh>

/** 上位足から参照する最大Wave数。 */
#define ELLIOT_HIGHER_WAVES 5

/**
 * 上位足同期後の再分析を繰り返す最大ラウンド数。
 *
 * 1ラウンドで同方向Wave統合、左側の狭いWave統合、右側の狭いWave統合を順に試す。
 * 過剰な統合で下位足の細部を潰しすぎないよう、再分析は最大3ラウンドに制限する。
 */
#define ELLIOT_REANALYZE_MAX_ROUNDS 3

/**
 * 上位足と同期して下位足のElliott波動を総合分析するクラス。
 *
 * 上位足のWave区間ごとに下位足ポイントを抽出し、ZigZag補正、Wave生成、
 * 最新Waveの再分析、再カウント、内部波動設定を順に実行する。
 */
class ElliotWithHigherAll : public ElliotBase {
public:
    /**
     * シンボル、時間足および売買方向を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    ElliotWithHigherAll(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsBuy, string fromBuySellLabel) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromIsBuy, fromBuySellLabel);
    }

    /**
     * 市場コンテキストおよび売買方向を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    ElliotWithHigherAll(MarketContext &fromMarketContext, bool fromIsBuy, string fromBuySellLabel) {
        this.initialize(fromMarketContext, fromIsBuy, fromBuySellLabel);
    }
    
    /**
     * デストラクタ。
     */
    ~ElliotWithHigherAll() {
    }

    /**
     * 上位足を基準に下位足の全分析処理を実行する。
     *
     * 分析範囲のZigZagポイントを取得し、上位足ポイントへ補正した後、
     * 上位足Wave区間ごとの下位足分析、必要時の最新Wave再分析、
     * 再カウント、内部波動設定を順に行う。
     *
     * @param elliotHigher 上位足Elliott分析結果
     * @return 分析に成功した場合true
     */
    bool analyze(Elliot &elliotHigher) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int bars = ElliotWithHigherUtil::getBars(this.logger, elliotHigher, this.marketContext);
        
        if (!this.setZigZagPointList(bars)) {
            this.logger.error(__FUNCTION__, "setZigZagPointList false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        
        this.correctZigZagPoint(elliotHigher);  // ZigZag補正
        
        
        if (!this.analyzeWithHigher(elliotHigher)) {
            this.logger.error(__FUNCTION__, "analyzeWithHigher false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        if (this.needsReanalyzeWave0) { // 再分析が必要
            if (!this.analyzeElliotWave0()) {
                this.logger.error(__FUNCTION__, "analyzeElliotWave0 false");
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                
                return false;
            }
        }
        
        if (this.isReanalyze) {
            this.recount();
            this.setSubwaves();
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }

private:
    /** 再分析を実行する場合true。 */
    bool isReanalyze;

    /** 最新Waveの再分析が必要な場合true。 */
    bool needsReanalyzeWave0;

    /**
     * 市場コンテキストおよび売買方向を初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    void initialize(MarketContext &fromMarketContext, bool fromIsBuy, string fromBuySellLabel) {
        this.logger.setLevel(LOG_INFO);

        this.init(fromMarketContext, fromIsBuy, fromBuySellLabel);

        this.needsReanalyzeWave0 = false;
        this.isReanalyze = true;

        if (this.marketContext.timeFrame == PERIOD_M15) {
        }
    }
    
    /**
     * 上位足ポイントに合わせて下位足ZigZagポイントを補正する。
     *
     * 補正後のポイント列は、ZigZagCorrectorの結果を現在の分析対象へ反映する。
     *
     * @param elliotHigher 上位足Elliott分析結果
     */
    void correctZigZagPoint(Elliot &elliotHigher) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        ZigZagCorrector zigZagCorrector(this.marketContext);
        
        zigZagCorrector.correct(elliotHigher, this.zigZagPointList);
        ZigZagPointUtil::copyZigZagPointList(zigZagCorrector.orgZigZagPointList, this.zigZagPointList);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    
    /**
     * ポイント列の終端価格を確認し、補正が必要か判定する。
     *
     * 現在方向の高値または安値と先頭ポイントの価格が異なる場合、
     * 波動分析用に先頭ポイントの価格を一時的に補正する。
     *
     * @param fromZigZagPointList 判定対象ポイント列
     * @param isUptrend true: 上昇波、false: 下降波
     * @param oldRate 補正前レート
     * @return 補正が必要な場合true
     */
    bool isCorrectionNeeded(CArrayObj &fromZigZagPointList, bool isUptrend, double &oldRate) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isCorrectionNeeded = false;
        
        
        ZigZagPoint *zigZagPoint = fromZigZagPointList.At(0);
        
        double rate = this.getBeforeRate(fromZigZagPointList, isUptrend);
        
        if (rate != zigZagPoint.rate) {
            double shiftRate = RateUtil::pipsToPrice(10, this.marketContext);  // 10pipsずらす
        
            if (isUptrend) {
                rate += shiftRate;
            } else {
                rate -= shiftRate;
            }
            
            oldRate = zigZagPoint.rate;
            zigZagPoint.rate = rate;
        
            isCorrectionNeeded = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isCorrectionNeeded = %s", (string)isCorrectionNeeded));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isCorrectionNeeded;
    }
    
    
    /**
     * 上位足の各Wave区間と同期して下位足Waveを生成する。
     *
     * 上位足Waveの左右ポイントごとに下位足ポイントを抽出し、
     * 推進波または修正波としてWaveを追加する。
     *
     * @param elliotHigher 上位足Elliott分析結果
     * @return 同期分析に成功した場合true
     */
    bool analyzeWithHigher(Elliot &elliotHigher) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        CArrayObj *waveListHigher = &(elliotHigher.waveList);
        int waveHigherTotal = waveListHigher.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("waveListHigher.Total = %d", waveHigherTotal));
        
        int waveTotal = (int)MathMin(ELLIOT_HIGHER_WAVES, waveHigherTotal);
        
        int zigZagIndex = 0;    // 処理中のindex
        
        for (int i = 0; i < waveTotal; i++) {
            Wave *waveHigher = waveListHigher.At(i);
            
            this.logger.debug(__FUNCTION__, waveHigher.toString());
            
            CArrayObj *zigZagPointListHigher = &(waveHigher.orgZigZagPointList);
            
            int startPoint = zigZagPointListHigher.Total() - 1;
            
            for (int j = startPoint; j > 0; j--) {   // 後ろから
                this.logger.debug(__FUNCTION__, StringFormat("▼▼▼▼▼▼▼▼▼▼ j = %d START ▼▼▼▼▼▼▼▼▼▼", j));
                
                ZigZagPoint *zigZagPointHigherRight = zigZagPointListHigher.At(j);    // ポイント右側
                ZigZagPoint *zigZagPointHigherLeft = zigZagPointListHigher.At(j - 1);    // ポイント左側
                
                int elliotIndex = zigZagPointHigherRight.elliotIndex;
                
                if (elliotIndex == Constant::DELETE_FLG) {
                    elliotIndex = zigZagPointHigherRight.orgElliotIndex;
                }
                
                // 上位足のElliott番号から下位足Waveの種別を決める。
                bool isMotive = false;
        
                if (Util::isOdd(elliotIndex)) {  // 奇数は推進波
                    isMotive = true;
                }
                
                bool isUptrend = waveHigher.isUptrend;
                    
                if (Util::isEven(elliotIndex)) {    // 偶数は修正波
                    isUptrend = !isUptrend;
                }
                
                CArrayObj zigZagPointListWithHigher;
                
                bool result = ElliotWithHigherUtil::getZigZagPointWithHigher(this.logger, this.zigZagPointList, zigZagIndex,
                                                zigZagPointHigherLeft, zigZagPointHigherRight, 
                                                zigZagPointListWithHigher, isUptrend, 
                                                zigZagIndex);
                
                if (!result) {
                    this.logger.error(__FUNCTION__, "ElliotWithHigherUtil::getZigZagPointWithHigher false");
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                    
                    return false;
                }
                
                this.logger.debug(__FUNCTION__, StringFormat("zigZagIndex = %d", zigZagIndex));
                
                this.logger.debug(__FUNCTION__, "上位足からZigZagPointList取得");
                LogUtil::printZigZagPointList(logger, __FUNCTION__, zigZagPointListWithHigher);
                
                int zigZagPointTotal = zigZagPointListWithHigher.Total();
                
                if (zigZagPointTotal >= 2) {
                    bool isLatest = false;
                
                    if (i == 0 && j == startPoint) {
                        isLatest = true;  // 最新波動
                    }
                    
                    this.logger.debug(__FUNCTION__, StringFormat("isMotive = %s", (string)isMotive));
                    this.logger.debug(__FUNCTION__, StringFormat("isUptrend = %s", (string)isUptrend));
                    this.logger.debug(__FUNCTION__, StringFormat("isLatest = %s", (string)isLatest));
                    
                    
                    // 最新ポイントを一時補正する。
                    bool isCorrect = false;
                    double oldRate = 0;
                    int totalBefore = this.waveList.Total();
                    
                    if (isLatest) {
                        ZigZagPoint *zigZagPoint0 = zigZagPointListWithHigher.At(0);
        
                        if ((isUptrend && zigZagPoint0.isPeak && this.isBuy) 
                                || (!isUptrend && !zigZagPoint0.isPeak && !this.isBuy)) {
                            isCorrect = this.isCorrectionNeeded(zigZagPointListWithHigher, isUptrend, oldRate);
                        }
                    } else {
                    }
                    
                    if (!this.getWaveWithHigher(zigZagPointListWithHigher, isMotive, isUptrend, isLatest)) {    // 波動分析
                        this.logger.error(__FUNCTION__, "getWaveWithHigher false");
                        LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                        
                        return false;
                    }
                    
                    if (isCorrect) {    // 一時補正したrateを戻す。
                        Wave *wave = this.waveList.At(0);
                        
                        ZigZagPoint *zigZagPointLast = ZigZagPointUtil::getLastNode(wave.zigZagPointList);
                        
                        zigZagPointLast.rate = oldRate;
                    }
                    
                    if (isLatest) {
                    if (elliotHigher.isBuy == this.isBuy) { // トレンド一致の場合
                        this.addPointToWave0();
                            
                        } else {
                            if (!this.addWave0()) {
                                this.logger.error(__FUNCTION__, "addWave0 false");
                                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                                
                                return false;
                            }
                        }
                    }
                    
                } else {    // ポイントが2未満は分析不可
                }
                
                
                this.logger.debug(__FUNCTION__, StringFormat("▲▲▲▲▲▲▲▲▲▲ j = %d END ▲▲▲▲▲▲▲▲▲▲", j));
                this.logger.debug(__FUNCTION__, "");
            }
            
        }
    
        this.analyzeWave();
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 上位足区間から抽出したポイント列をWaveとして分析する。
     *
     * 2点のみの場合は最小構成のWaveとして追加し、3点以上の場合は
     * ElliotWithHigherで分析したうえで必要に応じて再分析を繰り返す。
     *
     * @param fromZigZagPointList 分析対象ポイント列
     * @param isMotive true: 推進波、false: 修正波
     * @param isUptrend true: 上昇波、false: 下降波
     * @param isLatest 最新区間の場合true
     * @return Wave分析に成功した場合true
     */
    bool getWaveWithHigher(CArrayObj &fromZigZagPointList, bool isMotive, bool isUptrend, bool isLatest) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int total = fromZigZagPointList.Total();
        
        logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        
        if (total == 2) {    // point数=2の場合、再分析不要
            this.logger.debug(__FUNCTION__, " 分析不要");
            
            this.addWavePoint2(fromZigZagPointList, isMotive, isUptrend);
            
        } else {
            ElliotWithHigher *elliotWithHigher = new ElliotWithHigher(this.marketContext, this.isBuy, this.buySellLabel,
                                                                        fromZigZagPointList, isMotive, isLatest);
            
            if (!elliotWithHigher.analyze()) {
                delete elliotWithHigher;
                
                this.logger.error(__FUNCTION__, "elliotWithHigher.analyze false");
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                
                return false;
            }
            
            int totalHigher = elliotWithHigher.waveList.Total();
            
            this.logger.debug(__FUNCTION__, StringFormat("elliotWithHigher.waveList.Total = %d", totalHigher));
            
            if (this.isReanalyze && totalHigher > 1) {
                for (int i = 0; i < ELLIOT_REANALYZE_MAX_ROUNDS; i++) {   // 再分析
                    // 同じ方向
                    if (!elliotWithHigher.reanalyzeSameTrend()) {
                        delete elliotWithHigher;
                        
                        this.logger.error(__FUNCTION__, "elliotWithHigher.reanalyzeSameTrend false");
                        LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                        
                        return false;
                    }
                    
                    if (elliotWithHigher.waveList.Total() == 1) {    // 波動の数が1の場合終了
                        break;
                    }
                    
                    // 左側を再分析
                    if (!elliotWithHigher.reanalyzeNarrowWaveLeft()) {
                        delete elliotWithHigher;
                        
                        this.logger.error(__FUNCTION__, "elliotWithHigher.reanalyzeNarrowWaveLeft false");
                        LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                        
                        return false;
                    }
                    
                    if (elliotWithHigher.waveList.Total() == 1) {    // 波動の数が1の場合終了
                        break;
                    }
                    
                    // 右側を再分析
                    if (!elliotWithHigher.reanalyzeNarrowWaveRight()) {
                        delete elliotWithHigher;
                        
                        this.logger.error(__FUNCTION__, "elliotWithHigher.reanalyzeNarrowWaveRight false");
                        LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                        
                        return false;
                    }
                    
                    if (elliotWithHigher.waveList.Total() == 1) {    // 波動の数が1の場合終了
                        break;
                    }
                }
            }
            
            // 再分析結果を追加
            for (int i = 0; i < elliotWithHigher.waveList.Total(); i++) {
                Wave *wave = elliotWithHigher.waveList.At(i);
                
                WaveUtil::addWave(this.logger, this.waveList, this.marketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
            }
            
            delete elliotWithHigher;
            
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 指定ポイント列の先頭2点から最小構成のWaveを追加する。
     *
     * @param fromZigZagPointList 追加元ポイント列
     * @param isMotive true: 推進波、false: 修正波
     * @param isUptrend true: 上昇波、false: 下降波
     */
    void addWavePoint2(CArrayObj &fromZigZagPointList, bool isMotive, bool isUptrend) {
        CArrayObj zigZagPointListAdd;
        
        for (int i = 0; i < fromZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            
            ZigZagPointUtil::insertPoint(zigZagPointListAdd, zigZagPoint);
        }
        
        WaveUtil::addWave(this.logger, this.waveList, this.marketContext, zigZagPointListAdd, isMotive, isUptrend);
    }
    
    /**
     * 最新Waveを作業用リストで再分析し、妥当な結果を反映する。
     *
     * @return 再分析に成功した場合true
     */
    bool analyzeElliotWave0() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        CArrayObj workWaveList;
        WaveUtil::copyWaveList(this.waveList, workWaveList);
        
        this.waveList.Clear();
        
        Wave *wave0 = workWaveList.At(0);
        CArrayObj fromZigZagPointList;
        ZigZagPointUtil::copyZigZagPointList(wave0.zigZagPointList, fromZigZagPointList);
        
        double rate = this.getBeforeRate(fromZigZagPointList, wave0.isUptrend);
        double shiftRate = RateUtil::pipsToPrice(10, this.marketContext);  // 10pipsずらす
        
        if (wave0.isUptrend) {
            rate += shiftRate;
        } else {
            rate -= shiftRate;
        }
        
        
        ZigZagPoint *zigZagPointLast = ZigZagPointUtil::getLastNode(fromZigZagPointList);
        double workRate = zigZagPointLast.rate;
        
        zigZagPointLast.rate = rate;
        
        // ポイント列を逆順へ入れ替える。
        CArrayObj reZigZagPointList;
        
        for (int i = 0; i < fromZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            
            ZigZagPointUtil::insertPoint(reZigZagPointList, zigZagPoint);
        }
        
        
        if (!this.getWaveWithHigher(reZigZagPointList, wave0.isMotive, wave0.isUptrend, false)) {
            this.logger.error(__FUNCTION__, "getWaveWithHigher false");
            
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        // 一時補正したポイントを戻す。
        wave0 = this.waveList.At(0);
        zigZagPointLast = ZigZagPointUtil::getLastNode(wave0.zigZagPointList);
        zigZagPointLast.rate = workRate;
        
        
        for (int i = 1; i < workWaveList.Total(); i++) {
            Wave *wave = workWaveList.At(i);
            Wave *waveClone = wave.clone();
            
            waveClone.setParentWave(waveClone);

            this.waveList.Add(waveClone);
        }
        
        
        this.analyzeWave();
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 直近ポイント群から、現在方向に対する高値/安値を取得する。
     *
     * @param fromZigZagPointList 取得対象のポイント列
     * @param isUptrend true: 上昇トレンド方向、false: 下降トレンド方向
     * @return 方向上の高値または低値
     */
    double getBeforeRate(CArrayObj &fromZigZagPointList, bool isUptrend) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        LogUtil::printZigZagPointList(this.logger, __FUNCTION__, fromZigZagPointList);
        
        ZigZagPoint *zigZagPoint0 = fromZigZagPointList.At(0);
        double rate = zigZagPoint0.rate;
        
        int total = fromZigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        
        for (int i = 1; i < total - 1; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);
            
            if (isUptrend) {
                if (zigZagPoint.rate > rate) {
                    rate = zigZagPoint.rate;
                }
            } else {
                if (zigZagPoint.rate < rate) {
                    rate = zigZagPoint.rate;
                }
            }
        }
        
        logger.debug(__FUNCTION__, StringFormat("rate = %f", rate));
        LogUtil::printMethodEnd(logger, __FUNCTION__, true);
        
        return rate;
    }
    
    /**
     * 上位足と異なる方向の最新Waveを追加する。
     *
     * @return 最新Waveを追加できた場合true
     */
    bool addWave0() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        Wave *wave0 = this.waveList.At(0);
        
        this.logger.debug(__FUNCTION__, StringFormat("wave0 = %s", wave0.toString()));
        
        ZigZagPoint *latestZigZagPoint = wave0.getLatestPoint();
        
        int zigZagIndex = ZigZagPointUtil::getIndex(this.logger, this.zigZagPointList, latestZigZagPoint);
        
        this.logger.debug(__FUNCTION__, StringFormat("zigZagIndex = %d", zigZagIndex));
        
        if (zigZagIndex > 0) {  // 0は追加なし
            if (zigZagIndex == 1) {  // ポイント数=1
                this.logger.debug(__FUNCTION__, "zigZagIndex 1");
                
                ZigZagPoint *zigZagPoint = this.zigZagPointList.At(0);
                
                ZigZagPointUtil::addPoint(wave0.zigZagPointList, zigZagPoint);
                
            } else {    // 2以上
                this.logger.debug(__FUNCTION__, "zigZagIndex 2以上");
                
                CArrayObj workZigZagPointList;
        
                for (int i = 0; i <= zigZagIndex; i++) {
                    ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
                    
                    ZigZagPointUtil::addPoint(workZigZagPointList, zigZagPoint);
                }

                
                CArrayObj workWaveList;
                WaveUtil::copyWaveList(this.waveList, workWaveList);
                
                this.waveList.Clear();
                
                Wave *wave0 = workWaveList.At(0);
                
                if (!this.getWaveWithHigher(workZigZagPointList, !wave0.isMotive, !wave0.isUptrend, true)) {
                    this.logger.error(__FUNCTION__, "getWaveWithHigher false");
                    
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                    
                    return false;
                }
                
                for (int i = 0; i < workWaveList.Total(); i++) {
                    Wave *wave = workWaveList.At(i);
                    Wave *waveClone = wave.clone();
                    
                    waveClone.setParentWave(waveClone);
                    
                    waveClone.index = i + 1;    // indexの再設定
                    
                    this.waveList.Add(waveClone);
                }
                
                LogUtil::printWaveList(this.logger, __FUNCTION__, this.waveList);

            }
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
        
    
    
    /**
     * 上位足と同方向の場合に最新ポイントをwaveList[0]へ追加する。
     *
     * Wave全体の再分析は行わず、最新Waveのポイント列だけを更新する。
     */
    void addPointToWave0() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        Wave *wave0 = this.waveList.At(0);
        ZigZagPoint *latestZigZagPoint = wave0.getLatestPoint();
        
        int zigZagIndex = ZigZagPointUtil::getIndex(this.logger, this.zigZagPointList, latestZigZagPoint);
        
        for (int i = zigZagIndex - 1; i >= 0; i--) { // 最新より右側を追加
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
            
            ZigZagPointUtil::addPoint(wave0.zigZagPointList, zigZagPoint);
            
            this.needsReanalyzeWave0 = true;    // 再分析が必要
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 生成した全WaveへElliott再カウントを適用する。
     */
    void recount() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        ElliotRecount elliotRecount(this.marketContext, this.waveList);
        
        elliotRecount.recount();
        
        WaveUtil::copyWaveList(elliotRecount.waveList, this.waveList);
        
        this.analyzeWave();
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 生成した全Waveへ内部波動ラベルを設定する。
     */
    void setSubwaves() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        ElliotSubwaves elliotSubwaves(this.marketContext, this.waveList);
        
        elliotSubwaves.setSubwaves();
        
        WaveUtil::copyWaveList(elliotSubwaves.waveList, this.waveList);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    
    }
};    















