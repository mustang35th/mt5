//+------------------------------------------------------------------+
//|                                                       Elliot.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Analysis\ElliotHighest.mqh>
#include <Mstng\Elliot\Analysis\ElliotWithHigherAll.mqh>
#include <Mstng\Elliot\FiboExpansionPriceInfo.mqh>
#include <Mstng\Elliot\OhlcInfo.mqh>
#include <Mstng\Elliot\WaveUtil.mqh>

/*

1【3】
↓
elliotLabel【orgElliotLabel】

Wave
 zigZagPointList
  0 1 2 3
  
 orgZigZagPointList
  0 -1 -1 1
  0  1  2 3

zigZagPointListでリカウント
↓
zigZagPointList→orgZigZagPointListコピー
↓
zigZagPointListから不要は削除

*/

/**
 * 1つの時間足に対するElliott波動分析結果を保持するクラス。
 *
 * OHLC、Oscillator、Wave、ZigZagポイント、フィボナッチエクスパンションを
 * 統合し、上位足を利用した分析とCSV・表示用情報を提供する。
 */
class Elliot : public CObject {
public:
    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;
    
    /** 通貨ペア名を分割した左側の通貨コード */
    string symbolNameLeft;

    /** 通貨ペア名を分割した右側の通貨コード */
    string symbolNameRight;

    /** 売買方向。true: BUY、false: SELL */
    bool isBuy;

    /** 売買方向の表示用ラベル */
    string buySellLabel;
    
    /** 分析済みWave一覧。インデックス0が最新 */
    CArrayObj waveList;
    
    /** waveListから再構築したZigZagポイント一覧 */
    CArrayObj zigZagPointList;
    
    /** ストキャスティクス、GMMA、EMA200、ATRの分析結果 */
    Oscillator oscillator;
    
    /** 現在足のOHLC情報 */
    OhlcInfo currentOhlcInfo;

    /** 1本前の確定足のOHLC情報 */
    OhlcInfo previousOhlcInfo;
    
    /** 最新Waveから算出したフィボナッチエクスパンション価格情報 */
    FiboExpansionPriceInfo fiboExpansionPriceInfo;
    
    /**
     * 分析対象を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
    * @param fromTimeFrame 分析対象時間足
     */
    Elliot(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * 渡されたMarketContextは値としてコピーして保持する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    Elliot(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * デストラクタ。
     */
    ~Elliot() {
    }

    /**
     * 対象時間足のElliott波動分析を実行する。
     *
     * @param elliotHigher 上位足分析結果。最上位足の場合NULL
     * @param oscillatorHandlePool Oscillatorハンドルプール
     * @return 分析に成功した場合true
     */
    bool analyze(Elliot *elliotHigher, OscillatorHandlePool *oscillatorHandlePool) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        
        int copiedCount = CopyRates(this.marketContext.symbolName, this.marketContext.timeFrame, 0, 2, rates);
        
        if (copiedCount < 2) {
            this.logger.error(__FUNCTION__, "CopyRates failed");
        
            return false;
        }
        
        // 現在足 shift=0
        currentOhlcInfo.setDataByRates(rates[0]);
        
        // 一本前の確定足 shift=1
        previousOhlcInfo.setDataByRates(rates[1]);

        
        if (!this.setOscillator(oscillatorHandlePool)) {
            this.logger.error(__FUNCTION__, "setOscillator false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        if (elliotHigher == NULL) { // 最上位足
            ElliotHighest elliotHighest(this.marketContext, this.isBuy, this.buySellLabel);
            
            if (!elliotHighest.analyze()) {
                this.logger.error(__FUNCTION__, "elliotHighest.analyze false");
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                
                return false;
            }
            
            WaveUtil::copyWaveList(elliotHighest.waveList, this.waveList);  // Listのコピー
            
        } else {
            ElliotWithHigherAll elliotWithHigherAll(this.marketContext, this.isBuy, this.buySellLabel);
            
            if (!elliotWithHigherAll.analyze(elliotHigher)) {
                this.logger.error(__FUNCTION__, "elliotWithHigherAll.analyze false");
                
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
                
                return false;
            }
            
            WaveUtil::copyWaveList(elliotWithHigherAll.waveList, this.waveList);
            
            /*if (this.needsReanalyzeWave0) { // 再分析が必要
                this.analyzeElliotWave0();
            }*/
            
            // 再カウント
        }
        
        this.setCCompleted();
        this.setFiboExpansionPriceInfo();
        
        this.setZigZagPointList();
        LogUtil::printZigZagPointList(this.logger, __FUNCTION__, zigZagPointList);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 最新Waveの直近3基準点からフィボナッチエクスパンション価格情報を設定する。
     */
    void setFiboExpansionPriceInfo() {
        Wave *latestWave = this.getLatestWave();
        
        if (latestWave == NULL) {
            return;
        }
        
        CArrayObj *latestZigZagPointList = &(latestWave.zigZagPointList);
        
        int total = latestZigZagPointList.Total();
        
        if (total >= 4 && Util::isEven(total)) {
            ZigZagPoint *zigZagPoint0 = latestZigZagPointList.At(total - 4);
            ZigZagPoint *zigZagPoint1 = latestZigZagPointList.At(total - 3);
            ZigZagPoint *zigZagPoint2 = latestZigZagPointList.At(total - 2);
            ZigZagPoint *latestZigZagPoint = this.getLatestPoint();
            
            this.fiboExpansionPriceInfo.setData(
                zigZagPoint0.rate,
                zigZagPoint1.rate,
                zigZagPoint2.rate,
                latestZigZagPoint.rate,
                this.marketContext
            );
            
            //this.fiboExpansionPriceInfo.setDataByThreeRates(zigZagPoint0.rate, zigZagPoint1.rate, zigZagPoint2.rate);
        }
        
    }
    
    /**
     * 時間足単位のCSVデータを取得する。
     *
     * @param isDetail trueの場合、Oscillator詳細と過去ポイントを含める
     * @return CSVデータ。必要なWaveまたはポイントがない場合NULL
     */
    string getCsv(bool isDetail = false) {
        string csv = "";
        
        Wave *latestWave = this.getLatestWave();
        
        if (latestWave == NULL) {
            return NULL;
        }
        
        ZigZagPoint *latestPoint = this.getLatestPoint();
        
        if (latestPoint == NULL) {
            return NULL;
        }
        
        // ポイント最新
        // 
        
        csv += StringFormat("■,%s,%s,%s,%s,%s,%s,%s,%s,%s,", 
                            this.marketContext.timeFrameLabel,
                            this.buySellLabel,
                            latestWave.trendLabel, 
                            latestPoint.getCsv(),
                            this.previousOhlcInfo.getCsvData(this.marketContext.digits),
                            
                            this.currentOhlcInfo.getCsvData(this.marketContext.digits),
                            this.fiboExpansionPriceInfo.getCsvText(),
                            latestWave.previousLastElliotLabel,
                            this.oscillator.getAtr14Text()
                            );
        
        csv += this.oscillator.getCsv(isDetail);
        
        if (isDetail) {
            csv += latestWave.getCsv();
        }
        
        return csv;
    }
    
    /**
     * 最新ZigZagポイントを取得する。
     *
     * @return 最新Waveの最新ZigZagポイント。取得できない場合NULL
     */
    ZigZagPoint *getLatestPoint() {
        Wave *latestWave = this.getLatestWave();
        
        if (latestWave == NULL) {
            return NULL;
        }
        
        return latestWave.getLatestPoint();
    }
    
    /**
     * 最新ポイントのElliottラベルを取得する。
     *
     * @return 最新ポイントのElliottラベル。取得できない場合NULL
     */
    string getLatestPointElliotLabel() {
        ZigZagPoint *latestPoint = this.getLatestPoint();
        
        if (latestPoint == NULL) {
            return NULL;
        }
        
        return latestPoint.getElliotLabel();
    }
    
    /**
     * 最新ポイントの1つ前を取得する。
     *
     * @return 最新Waveの1つ前のZigZagポイント。取得できない場合NULL
     */
    ZigZagPoint *getLatestPoint2() {
        Wave *latestWave = this.getLatestWave();
        
        if (latestWave == NULL) {
            return NULL;
        }
        
        return latestWave.getLatestPoint2();
    }
    
    /**
     * 最新Waveを取得する。
     *
     * @return waveListのインデックス0にある最新Wave
     */
    Wave *getLatestWave() {
        return this.waveList.At(0);
    }
    
    // 最古の波動を取得
    /**
     * 最古のWaveを取得する。
     *
     * @return waveListの最後にある最古のWave
     */
    Wave *getOldestWave() {
        return this.waveList.At(this.waveList.Total() - 1);
    }
    
    /**
     * チャート表示用の分析結果テキストを取得する。
     *
     * @return チャート表示用テキスト
     */
    string getText() {
        string text = "";
        
        Wave *wave = this.getLatestWave();
        ZigZagPoint *zigZagPoint = this.getLatestPoint();
        
        text += StringFormat("%s/%s/%s\n", this.marketContext.timeFrameLabel, this.buySellLabel, zigZagPoint.getTextIndexInfo());
        
        text += StringFormat("EMA200/%s/\n", this.oscillator.ema200.getText());
        
        text += StringFormat("O/%s/", StringUtil::addSign(this.oscillator.oscillatorCount));
        text += StringFormat(" SMO/%s/%s/\n", this.oscillator.getStochasticMainOrderText(), this.oscillator.getStochasticMainOrderDirectionText());
        
        text += StringFormat("S%s\n", this.oscillator.stochasticShort.getText());
        text += StringFormat("M%s\n", this.oscillator.stochasticMiddle.getText());
        text += StringFormat("L%s\n", this.oscillator.stochasticLong.getText());
        
        text += StringFormat("GT/%s/", StringUtil::addSign(this.oscillator.gmmaTrendCount));
        text += StringFormat(" GC/%s/", StringUtil::addSign(this.oscillator.gmmaCrossCount));
        
        text += "\n";
        
        return text;
    }
    
    /**
     * 保持しているWave数を取得する。
     *
     * @return Wave数
     */
    int getWaveCount() {
        return this.waveList.Total();
    }
    
    /**
     * 1つ前のWaveにおける最終Elliottラベルを取得する。
     *
     * @return 1つ前のWaveにおける最終Elliottラベル
     */
    string getPreviousLastElliotLabel() {
        Wave *latestWave = this.getLatestWave();
        
        return latestWave.previousLastElliotLabel;
    }
        
    /**
     * 最新Waveが上昇方向か判定する。
     *
     * @return 最新Waveが上昇方向の場合true
     */
    bool isUptrend() {
        Wave *latestWave = this.getLatestWave();
        
        return latestWave.isUptrend;
    }
    
    /**
     * 全Waveへ親Elliot参照を設定する。
     *
     * @param elliot 親として設定するElliot
     */
    void setParentElliot(Elliot *elliot) {
        for (int i = 0; i < this.waveList.Total(); i++) {
            Wave *wave = this.waveList.At(i);
    
            if (wave == NULL) {
                continue;
            }
    
            wave.parentElliot = elliot;
        }
    }
    
    /**
     * 分析対象と売買方向を文字列化する。
     *
     * @return 分析対象と売買方向を含むデバッグ文字列
     */
    string toString() const {
        return StringFormat(
            "Elliot{symbolName=%s, symbolNameLeft=%s, symbolNameRight=%s, timeFrame=%d, timeFrameLabel=%s, isBuy=%s, buySellLabel=%s}",
            this.marketContext.symbolName,
            symbolNameLeft,
            symbolNameRight,
            (int)this.marketContext.timeFrame,
            this.marketContext.timeFrameLabel,
            isBuy ? "true" : "false",
            buySellLabel
        );
    }
    
private:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;

    /**
     * 市場コンテキストと互換用フィールドを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.oscillator.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        // 既存利用箇所との互換性を維持する
        StringUtil::splitCurrencyPairName(this.marketContext.symbolName, this.symbolNameLeft, this.symbolNameRight);

        this.logger.debug(__FUNCTION__, "symbolName=" + this.marketContext.symbolName);
        this.logger.debug(__FUNCTION__, "symbolNameLeft=" + this.symbolNameLeft);
        this.logger.debug(__FUNCTION__, "symbolNameRight=" + this.symbolNameRight);
        this.logger.debug(__FUNCTION__, "timeFrame=" + IntegerToString(this.marketContext.timeFrame));
        this.logger.debug(__FUNCTION__, "timeFrameLabel=" + this.marketContext.timeFrameLabel);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 最新Waveの状態から修正C波完了フラグを設定する。
     */
    void setCCompleted() {
        
        for (int i = 0; i < this.waveList.Total() - 1; i++) {
            Wave *wave = this.waveList.At(i);
            
            /*if (wave.isImpulseWave()) { // Impulse設定
                wave.isImpulse = true;
            }*/
            
            // Fractal設定
            Wave *waveBefore = this.waveList.At(i + 1);
            
            ZigZagPoint *latestPoint = waveBefore.getLatestPoint();
            
            if (latestPoint != NULL) {
                /*if (latestPoint.elliotLabel == "C") {
                    wave.isPrevCorrectionCCompleted = true;
                }*/
                
                //　前回波動が修正波
                // 1個　A
                // 3個　C
                // 5個　E
            
                if (latestPoint.isElliotAlphabet) {
                    int previousTotal = waveBefore.zigZagPointList.Total();
                    
                    if (previousTotal == 2) {
                        wave.previousLastElliotLabel = "A";
                    }
                    
                    if (previousTotal == 4) {
                        wave.previousLastElliotLabel = "C";
                    }
                    
                    if (previousTotal == 6) {
                        wave.previousLastElliotLabel = "E";
                    }
                }
            }
        }
    }
    
    
    /**
     * 対象時間足のOscillator情報を更新し、売買方向を設定する。
     *
     * @param oscillatorHandlePool Oscillatorハンドルプール
     * @return 更新に成功した場合true
     */
    bool setOscillator(OscillatorHandlePool *oscillatorHandlePool) {
        if (!this.oscillator.update(
            this.marketContext,
            oscillatorHandlePool
        )) {
            return false;
        }

        this.oscillator.setBuySell();
        
        this.isBuy = this.oscillator.isBuy;
        this.buySellLabel = Constant::getBuySell(this.isBuy);
        
        return true;
    }
    
    /**
     * 全Waveから表示・参照用ZigZagポイント一覧を再構築する。
     */
    void setZigZagPointList() {
        for (int i = 0; i < this.waveList.Total(); i++) {
            Wave *wave = this.waveList.At(i);
    
            if (wave != NULL) {
                int total = wave.zigZagPointList.Total();
                
                for (int i = total - 1; i > 0; i--) {
                    ZigZagPoint *zigZagPoint = wave.zigZagPointList.At(i);
        
                    if (zigZagPoint == NULL) {
                        continue;
                    }
        
                    ZigZagPoint *zigZagPointClone = zigZagPoint.clone();
        
                    if (zigZagPointClone == NULL) {
                        continue;
                    }
        
                    this.zigZagPointList.Add(zigZagPointClone);
                }
            }
        }
    }
};




















