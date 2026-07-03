//+------------------------------------------------------------------+
//|                                                   ElliotBase.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Wave.mqh>
#include <Mstng\Elliot\WaveUtil.mqh>
#include <Mstng\Elliot\ZigZagPointUtil.mqh>
#include <Mstng\Log\LogUtil.mqh>
#include <Mstng\Oscillator\Oscillator.mqh>
#include <Mstng\Util\StringUtil.mqh>

/**
 * Elliott波動分析の共通基底クラス。
 *
 * ZigZagポイント列からWaveを切り出し、波動ラベル、フィボナッチ情報、
 * 確定状態などの共通分析を行う。派生クラスは、最上位足や上位足連携などの
 * 分析方法に応じて本クラスのprotectedメソッドを使用する。
 *
 * zigZagPointListおよびwaveListは、インデックス0が最新データである。
 */
class ElliotBase {
public:
    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;
    
    /** 売買方向。true: BUY、false: SELL */
    bool isBuy;
    /** 売買方向表示用ラベル */
    string buySellLabel;
    
    /** ZigZagポイント。インデックス0が最新 */
    CArrayObj zigZagPointList;
    
    /** 分析済みWave。インデックス0が最新 */
    CArrayObj waveList;
    
    /**
     * ElliotBase を生成します。
     */
    ElliotBase() {        
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    ElliotBase(MarketContext &fromMarketContext) {
        this.init(fromMarketContext);
    }
    
    /**
     * ElliotBase を破棄します。
     */
    ~ElliotBase() {
    }
    
    /**
     * シンボルと時間足を初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     */
    void init(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.init(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void init(MarketContext &fromMarketContext) {
        this.setMarketContext(fromMarketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.logger.debug(__FUNCTION__, "symbolName=" + this.marketContext.symbolName);
        this.logger.debug(__FUNCTION__, "timeFrame=" + IntegerToString(this.marketContext.timeFrame));
        this.logger.debug(__FUNCTION__, "timeFrameLabel=" + this.marketContext.timeFrameLabel);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * シンボル、時間足、売買方向を初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    void init(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsBuy, string fromBuySellLabel) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.init(context, fromIsBuy, fromBuySellLabel);
    }

    /**
     * 市場コンテキストと売買方向を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     */
    void init(MarketContext &fromMarketContext, bool fromIsBuy, string fromBuySellLabel) {
        this.setMarketContext(fromMarketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.isBuy = fromIsBuy;
        this.buySellLabel = fromBuySellLabel;
        
        this.logger.debug(__FUNCTION__, "symbolName=" + this.marketContext.symbolName);
        this.logger.debug(__FUNCTION__, "timeFrame=" + IntegerToString(this.marketContext.timeFrame));
        this.logger.debug(__FUNCTION__, "timeFrameLabel=" + this.marketContext.timeFrameLabel);
        this.logger.debug(__FUNCTION__, "isBuy=" + (string)this.isBuy);
        this.logger.debug(__FUNCTION__, "buySellLabel=" + this.buySellLabel);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 分析対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.zigZagPointList.Clear();
        this.waveList.Clear();
        this.initializeMarketContext(fromMarketContext);
    }

protected:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;
    
    /**
     * waveList内の全Waveを分析し、最新Waveの確定状態を設定する。
     *
     * Waveが1件の場合は確定扱いとする。複数件の場合は、最新Waveと
     * 1つ前のWaveを比較して最新Waveの確定状態を判定する。
     */
    void analyzeWave() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int waveTotal = this.waveList.Total();
        
        for (int i = 0; i < waveTotal; i++) {
            Wave *wave = this.waveList.At(i);
            
            wave.analyze();
        }
        
        // 確定処理
        if (waveTotal == 1) {
            Wave *wave0 = this.waveList.At(0);
            
            wave0.isConfirmed = true;
        }
        
        if (waveTotal > 1) {
            Wave *wave0 = this.waveList.At(0);
            Wave *wave1 = this.waveList.At(1);
            
            wave0.setConfirmed(wave1);
        }
        
        
        // 再分析後のポイント設定は既存実装で未使用のため現時点は実施しない。
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 指定位置から1つのWaveを切り出してwaveListへ追加する。
     *
     * ZigZagポイントを2点単位で過去方向へ走査し、同方向の極値が
     * 起点を更新した位置で現在のWaveを終了する。
     *
     * @param fromZigZagIndex 切り出し開始位置。0が最新ポイント
     * @param isMotive true: 推進波、false: 修正波
     * @return Waveを追加できた場合true
     */
    bool getWave(int fromZigZagIndex, bool isMotive) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        this.logger.debug(__FUNCTION__, StringFormat("fromZigZagIndex = %d", fromZigZagIndex));
        this.logger.debug(__FUNCTION__, StringFormat("isMotive = %s", (string)isMotive));
        
        int zigZagIndex = fromZigZagIndex;
        
        CArrayObj pointList;
        
        bool isUptrend;
        
        if (!this.isUptrend(zigZagIndex, isUptrend)) {
            this.logger.error(__FUNCTION__, "isUptrend false");
            
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        bool isPeakLastPoint = this.isPeakLastPoint(zigZagIndex);
        
        if (this.isInsertRequired(isUptrend, isPeakLastPoint)) {
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(zigZagIndex);
            
            ZigZagPointUtil::insertPoint(pointList, zigZagPoint);
            
            zigZagIndex++;
        }
        
        
        this.logger.debug(__FUNCTION__, StringFormat("zigZagIndex = %d", zigZagIndex));
        
        if (this.logger.isDebugMode()) {
            ZigZagPoint *zigZagPointLast = this.zigZagPointList.At(this.zigZagPointList.Total() - 1);
        
            this.logger.debug(__FUNCTION__, "Last ZigZagPoint = " + zigZagPointLast.toString());
        }
        
        
        for (int i = zigZagIndex; i < this.zigZagPointList.Total(); i += 2) {
            this.logger.debug(__FUNCTION__, StringFormat("for内 i = %d", i));
            
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
            ZigZagPoint *zigZagPointBefore = this.zigZagPointList.At(i + 1);
            
            if (zigZagPoint != NULL 
                    && zigZagPointBefore != NULL) {
                ZigZagPointUtil::insertPoint(pointList, zigZagPoint);
                ZigZagPointUtil::insertPoint(pointList, zigZagPointBefore);
                
                ZigZagPoint *zigZagPointBefore2 = this.zigZagPointList.At(i + 2);
                
                if (zigZagPointBefore2 != NULL) {
                    if (this.isBreak(isUptrend, zigZagPointBefore2, zigZagPoint)) {
                        break;
                    }
                }
                
                
                ZigZagPoint *zigZagPointBefore3 = this.zigZagPointList.At(i + 3);
                
                if (zigZagPointBefore3 != NULL) {
                    if (this.isBreak(isUptrend, zigZagPointBefore3, zigZagPointBefore)) {
                        break;
                    }
                }
            }
        }

        if (pointList.Total() == 1) {
            ZigZagPoint *zigZagPointRest = this.zigZagPointList.At(zigZagIndex);

            if (zigZagPointRest != NULL) {
                ZigZagPointUtil::insertPoint(pointList, zigZagPointRest);
            }
        }

        if (pointList.Total() < 2) {
            this.logger.error(__FUNCTION__, StringFormat("pointList.Total < 2 fromZigZagIndex = %d", fromZigZagIndex));

            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        WaveUtil::addWave(
            this.logger,
            this.waveList,
            this.marketContext,
            pointList,
            isMotive,
            isUptrend
        );
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 最新位置から最初のWaveを生成する。
     *
     * 生成したWaveの方向と売買方向が一致しない場合は、開始位置を1つ
     * 過去へ移して再生成し、最初に取得した最新ポイントを末尾へ補完する。
     *
     * @param isMotive true: 推進波、false: 修正波
     * @return 最新Waveを生成できた場合true
     */
    bool getWave0(bool isMotive) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (!this.getWave(0, isMotive)) {
            this.logger.error(__FUNCTION__, "getWave 0 false");
            
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        Wave *wave0 = this.waveList.At(0);
        
        bool isSameTrend = this.isSameTrend(wave0, this.isBuy);
        
        int total = wave0.zigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        
        // 最新の場合、0からだけでは確定できない
        // トレンドが違う場合、1から波動取得
        if (total > 2) {    // ポイント数=2が確定なので処理対象外
            if (!isSameTrend) {    // 次の波動が最新
                // 最新ポイントの追加
                ZigZagPoint *latestPoint = wave0.getLatestPoint();
                ZigZagPoint *zigZagPoint = latestPoint.clone();
            
                this.waveList.Clear();
                
                if (!this.getWave(1, isMotive)) {
                    this.logger.error(__FUNCTION__, "getWave 1 false");
                    
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                    
                    return false;
                }
                
                wave0 = this.waveList.At(0);
                wave0.zigZagPointList.Add(zigZagPoint);
            }
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 指定レートが高値と安値の間にあるか判定する。
     *
     * @param high 高値
     * @param low 安値
     * @param rate 判定対象レート
     * @return 境界値を除き、lowより大きくhighより小さい場合true
     */
    bool isBetweenHighAndLow(double high, double low, double rate) {
        bool isBetweenHighAndLow = false;
        
        if (low < rate && rate < high) {
            isBetweenHighAndLow = true;
        }
        
        return isBetweenHighAndLow;
    }
    
    /**
     * 指定位置からZigZagポイント全体をWaveへ分割する。
     *
     * 直前Waveの終点を次のWaveの起点として共有しながら過去方向へ進む。
     * 異常な位置更新による無限ループを防ぐため、最大30回で終了する。
     *
     * @param fromPosition Wave分割開始位置
     * @param isMotive 最初に生成するWaveの種別
     * @return 全Waveを生成して分析できた場合true
     */
    bool makeWaveList(int fromPosition, bool isMotive) {
        int position = fromPosition;
        int count = 0;
        
        int total = this.zigZagPointList.Total();
        
        ZigZagPoint *zigZagPoint0 = this.zigZagPointList.At(0);
        ZigZagPoint *zigZagPointLast = this.zigZagPointList.At(total - 1);
        
        // D1の3波が長くてH4の波動が複数のWaveとなるケースに備えたデバッグ条件は、
        // 運用時には外部の一時デバッグフラグで制御する。
        
        this.logger.debug(__FUNCTION__, StringFormat("fromPosition = %d", fromPosition));
        this.logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        
        this.logger.debug(__FUNCTION__, zigZagPoint0.toString());
        this.logger.debug(__FUNCTION__, zigZagPointLast.toString());
        
        const int MAX_LOOP = 30;
        
        while (position < total) {
            int previousPosition = position;
            int startPosition = 0;
            
            if (position > 0) {
                startPosition = position - 1;
            }
            
            if (!this.getWave(startPosition, isMotive)) {
                this.logger.error(__FUNCTION__, "getWave false");
                
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                
                return false;
            }
            
            Wave *wave = WaveUtil::getLastNode(this.waveList);
            position = startPosition + wave.zigZagPointList.Total();

            this.logger.debug(__FUNCTION__, StringFormat("ループ内 position = %d", position));

            if (position <= previousPosition) {
                this.logger.error(__FUNCTION__, StringFormat("position not advanced previousPosition = %d position = %d", previousPosition, position));

                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                return false;
            }
                        
            if (++count > MAX_LOOP) {
                this.logger.error(__FUNCTION__, StringFormat("ループ終了 = %d回", MAX_LOOP));
                
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                
                return false;
            }
        }
        
        this.analyzeWave();
        
        return true;
    }
    
    
    /**
     * 波動のトレンド方向と売買方向が一致しているかを判定する。
     *
     * 判定ルール：
     * - wave.isUptrend == true（上昇トレンド）の場合は、BUY（fromIsBuy==true）なら一致
     * - wave.isUptrend == false（下降トレンド）の場合は、SELL（fromIsBuy==false）なら一致
     *
     * @param wave       判定対象の波動
     * @param fromIsBuy  売買方向（true: BUY, false: SELL）
     *
     * @return 一致する場合 true
     */
    bool isSameTrend(Wave &wave, bool fromIsBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isSameTrend = false;
    
        this.logger.debug(__FUNCTION__, StringFormat("wave.isUptrend = %s fromIsBuy=%s", (string)wave.isUptrend, (string)fromIsBuy));
    
        if (wave.isUptrend) {   // 上昇トレンド
            if (fromIsBuy) {
                isSameTrend = true;
            }
        } else {                // 下降トレンド
            if (!fromIsBuy) {
                isSameTrend = true;
            }
        }
    
        this.logger.debug(__FUNCTION__, StringFormat("isSameTrend = %s", (string)isSameTrend));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isSameTrend;
    }
    
    /**
     * 指定Waveと1つ前のWaveの方向が一致するか判定する。
     *
     * @param waveIndex 判定対象Waveのインデックス
     * @return 両Waveの上昇・下降方向が一致する場合true
     */
    bool isSameTrendBeforeWave(int waveIndex) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        

        this.logger.debug(__FUNCTION__, StringFormat("waveIndex = %d", waveIndex));
        
        bool isSameTrend = false;
        
        Wave *wave = this.waveList.At(waveIndex);
        Wave *waveBefore = this.waveList.At(waveIndex + 1);
        
        if (waveBefore.isUptrend == wave.isUptrend) {
            isSameTrend = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isSameTrend = %s", (string)isSameTrend));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isSameTrend;
    }
    
    /**
     * 指定Waveの1つ前のWaveから、終端2点の高値と安値を取得する。
     *
     * @param fromWaveIndex 基準Waveのインデックス
     * @param high 取得した高値
     * @param low 取得した安値
     */
    void setHighLowAtBeforeWave(int fromWaveIndex, double &high, double &low) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("fromWaveIndex = %d", fromWaveIndex));
        
        int waveIndex = fromWaveIndex + 1;
        
        Wave *waveBefore = this.waveList.At(waveIndex);
        CArrayObj *fromZigZagPointList = &(waveBefore.zigZagPointList);
        
        int total = fromZigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        
        ZigZagPoint *zigZagPointLast = fromZigZagPointList.At(total - 1);
        ZigZagPoint *zigZagPointLast2 = fromZigZagPointList.At(total - 2);
        
        if (zigZagPointLast2.isPeak) {
            high = zigZagPointLast2.rate;
            low = zigZagPointLast.rate;
        } else {
            high = zigZagPointLast.rate;
            low = zigZagPointLast2.rate;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("high = %f", high));
        this.logger.debug(__FUNCTION__, StringFormat("low = %f", low));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定ZigZagポイントを起点とする波動方向を判定する。
     *
     * 同種の極値となる2つ前のポイントを優先して比較する。2つ前がない
     * 場合は1つ前のポイントとの価格差から方向を判定する。
     *
     * @param zigZagIndex 判定起点となるZigZagポイント位置
     * @param isUptrend 判定結果。true: 上昇、false: 下降
     * @return 判定起点を取得できた場合true
     */
    bool isUptrend(int zigZagIndex, bool &isUptrend) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("zigZagIndex = %d", zigZagIndex));
        this.logger.debug(__FUNCTION__, StringFormat("zigZagPointList.Total = %d", this.zigZagPointList.Total()));
        
        if (this.zigZagPointList.Total() == 1) {
            LogUtil::printZigZagPointList(logger, __FUNCTION__, this.zigZagPointList);
        }
        
        isUptrend = false;
        
        ZigZagPoint *zigZagPoint = this.zigZagPointList.At(zigZagIndex);
        
        if (zigZagPoint == NULL) {
            this.logger.error(__FUNCTION__, StringFormat("zigZagPoint is NULL zigZagIndex = %d", zigZagIndex));
            
            return false;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("zigZagPoint = %s", zigZagPoint.toString()));
        
        ZigZagPoint *zigZagPointBefore2 = this.zigZagPointList.At(zigZagIndex + 2);
        
        if (zigZagPointBefore2 != NULL) { // 2つ前がある場合
            this.logger.debug(__FUNCTION__, StringFormat("zigZagPointBefore2 = %s", zigZagPointBefore2.toString()));
            
            if (zigZagPointBefore2.rate < zigZagPoint.rate) {
                isUptrend = true;    
            }
        } else {    // ない場合
            ZigZagPoint *zigZagPointBefore = this.zigZagPointList.At(zigZagIndex + 1);
            
            if (zigZagPointBefore != NULL) {
                if (zigZagPointBefore.rate < zigZagPoint.rate) {
                    isUptrend = true;    
                }
            } else {    // 前回ポイントなし　★★★★★
                this.logger.error(__FUNCTION__, "zigZagPointBefore is NULL!");
                this.logger.error(__FUNCTION__, StringFormat("zigZagPoint = %s", zigZagPoint.toString()));
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isUptrend=%s", (string)isUptrend));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * ZigZagを計算し、波動分析用ポイント列を設定する。
     *
     * ZigZag更新後、売買方向に必要な最新側の山または谷がない場合は
     * 補完ポイントを追加してからディープコピーする。
     *
     * @param fromMaxBars ZigZag計算対象の最大バー数
     * @return ポイント列を設定できた場合true
     */
    bool setZigZagPointList(int fromMaxBars = 300) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        ZigZag zigZag(this.marketContext);
                
        // ZigZag を更新（転換点検出）
        bool updateResult = zigZag.update(fromMaxBars);
    
        if (!updateResult) {
            // ZigZag の更新に失敗した場合は解析できないため終了
            this.logger.error(__FUNCTION__, "ZigZag update failed.");
    
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
    
            return false;
        }
        
        // ZigZag の転換点が不足するケースがあるため、売買方向に応じて最新ポイントを補完する
        zigZag.addPoint(this.isBuy);
    
        // ZigZag の転換点リストを、本クラスの保持リストへコピー（解析対象の点列として保持）
        ZigZagPointUtil::copyZigZagPointList(zigZag.zigZagPointList, this.zigZagPointList);    // 全体のコピー
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    
    /**
     * 現在のwaveListからZigZagポイント列を再構築して再分析する。
     *
     * 最新Waveの推進波・修正波種別を維持し、既存Waveをクリアした後に
     * 再構築したポイント列からWaveを作り直す。
     *
     * @return 再分析に成功した場合true
     */
    bool makeZigZagPointListAndReanalyze() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        this.zigZagPointList.Clear();
        
        Wave *wave0 = this.waveList.At(0);
        bool isMotive = wave0.isMotive;
        
        ZigZagPointUtil::makeZigZagPointListFromWaveList(this.logger, this.waveList, this.zigZagPointList);
        
        LogUtil::printZigZagPointList(this.logger, __FUNCTION__, this.zigZagPointList);
        
        this.waveList.Clear();
        
        
        if (!this.makeWaveList(0, isMotive)) {
            this.logger.error(__FUNCTION__, "makeWaveList false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
private:
    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setMarketContext(this.marketContext);
    }

    /**
     * 同方向の過去極値が比較対象を更新したか判定する。
     *
     * @param isUpTrend true: 上昇波、false: 下降波
     * @param pointBefore 過去側の同種極値
     * @param point 比較基準ポイント
     * @return 現在のWaveを終了する場合true
     */
    bool isBreak(bool isUpTrend, ZigZagPoint &pointBefore, ZigZagPoint &point) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("isUpTrend = %s", (string)isUpTrend));
        this.logger.debug(__FUNCTION__, StringFormat("pointBefore = %s", pointBefore.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("point = %s", point.toString()));
        
        bool isBreak = false;
        
        if (isUpTrend) {
            if (pointBefore.rate > point.rate) {
                isBreak = true;
            }
        } else {
            if (pointBefore.rate < point.rate) {
                isBreak = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isBreak = %s", (string)isBreak));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isBreak;
    }
    
    /**
     * Waveの先頭へ起点ポイントを追加する必要があるか判定する。
     *
     * 上昇波が谷から始まる場合、または下降波が山から始まる場合に追加する。
     *
     * @param isUptrend true: 上昇波、false: 下降波
     * @param isPeakLastPoint 開始位置が山の場合true
     * @return 起点ポイントの追加が必要な場合true
     */
    bool isInsertRequired(bool isUptrend, bool isPeakLastPoint) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isInsertRequired = false;
        
        if (isUptrend) {    // 上昇トレンド
            if (!isPeakLastPoint) {  // 開始が底の場合
                isInsertRequired = true;
            }
        } else {    // 下降トレンド
            if (isPeakLastPoint) {
                isInsertRequired = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isInsertRequired=%s", (string)isInsertRequired));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isInsertRequired;
    }
    
    /**
     * 指定位置のZigZagポイントが山か判定する。
     *
     * @param zigZagIndex 判定対象位置
     * @return 山の場合true、谷の場合false
     */
    bool isPeakLastPoint(int zigZagIndex) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        this.logger.debug(__FUNCTION__, StringFormat("zigZagIndex=%d", zigZagIndex));
        
        ZigZagPoint *zigZagPoint = this.zigZagPointList.At(zigZagIndex);
        
        bool isPeak = zigZagPoint.isPeak;
        
        this.logger.debug(__FUNCTION__, StringFormat("isPeak = %s", (string)isPeak));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isPeak;
    }
};













