//+------------------------------------------------------------------+
//|                                                   DrawElliot.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Draw\DrawProperties.mqh>
#include <Mstng\Draw\DrawPropertiesElliot.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * Elliotサマリー表の列種別。
 */
enum ElliotColmun {
    COLMUN_TIME_FRAME,
    COLMUN_BUYSELL,
    COLMUN_EMA200_BUYSELL,
    COLMUN_STOCHASTIC_MAIN_ORDER,
    COLMUN_STOCHASTIC_SHORT,
    COLMUN_STOCHASTIC_MIDDLE,
    COLMUN_STOCHASTIC_LONG,
    COLMUN_GMMA_TREND,
    COLMUN_GMMA_CROSS,
    COLMUN_IMPULSE,
    COLMUN_FRACTAL,
    COLMUN_ELLIOT
};

/**
 * Elliotの波形と状態情報をチャート上に表形式およびラベル付きで描画するクラス。
 */
class DrawElliot {
public:
    /**
     * 描画列幅の初期値を設定して初期化する。
     *
     * @param fromSimpleDisplay 簡易表示の場合true
     * @param fromHigherTimeFrameDisplayCount 波動ラベルを表示する上位時間足数
     */
    DrawElliot(
        bool fromSimpleDisplay = false,
        int fromHigherTimeFrameDisplayCount = 2
    ) {
        this.logger.setLevel(LOG_INFO);
        this.clampVertical = false;
        this.higherTimeFrameDisplayCount = fromHigherTimeFrameDisplayCount;

        if (this.higherTimeFrameDisplayCount != 2
                && this.higherTimeFrameDisplayCount != 3) {
            this.higherTimeFrameDisplayCount = 2;
        }

        this.layoutHigherTimeFrameDisplayCount = 2;
        
        this.addDrawPropertiesElliotList(true, 90); // COLMUN_TIME_FRAME
        this.addDrawPropertiesElliotList(true, 110);    // COLMUN_BUYSELL
        this.addDrawPropertiesElliotList(true, 110);    // COLMUN_EMA200_BUYSELL
        this.addDrawPropertiesElliotList(false, 70);     // COLMUN_STOCHASTIC_MAIN_ORDER
        this.addDrawPropertiesElliotList(!fromSimpleDisplay, 50);    // COLMUN_STOCHASTIC_SHORT
        this.addDrawPropertiesElliotList(!fromSimpleDisplay, 50);    // COLMUN_STOCHASTIC_MIDDLE
        this.addDrawPropertiesElliotList(!fromSimpleDisplay, 50);    // COLMUN_STOCHASTIC_LONG
        this.addDrawPropertiesElliotList(!fromSimpleDisplay, 90);    // COLMUN_GMMA_TREND
        this.addDrawPropertiesElliotList(!fromSimpleDisplay, 90);    // COLMUN_GMMA_CROSS
        this.addDrawPropertiesElliotList(false, 90);    // COLMUN_IMPULSE
        this.addDrawPropertiesElliotList(false, 90);    // COLMUN_FRACTAL
        this.addDrawPropertiesElliotList(true, 120);    // COLMUN_ELLIOT
    }
    
    /**
     * デストラクタ。
     */
    ~DrawElliot() {
        
    }

    /**
     * Elliot分析結果を描画する。
     *
     * @param fromElliotAll Elliot解析結果
     * @param fromIsElliotInfoVisible エリオット情報表示有無
     * @param fromClampVertical Elliottラベルを上下端へ収める場合true
     */
    void draw(
        ElliotAll *fromElliotAll,
        bool fromIsElliotInfoVisible = true,
        bool fromClampVertical = false
    ) {
        this.elliotAll = fromElliotAll;
        this.clampVertical = fromClampVertical;
        
        this.logger.setMarketContext(this.elliotAll.marketContext);
        
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (fromIsElliotInfoVisible) {
            this.setLabel();
        }
        
        this.layoutHigherTimeFrameDisplayCount =
            this.getLayoutHigherTimeFrameDisplayCount();

        for (int higherIndex = this.layoutHigherTimeFrameDisplayCount;
                higherIndex >= 0;
                higherIndex--) {
            Elliot *elliot = this.elliotAll.getElliot(
                this.elliotAll.marketContext.timeFrame,
                higherIndex
            );

            if (elliot == NULL) {
                continue;
            }

            int fontSizeIncrease = higherIndex * 2;
            double upLevel = 0;

            if (higherIndex > 0) {
                upLevel = (double)(higherIndex + 1);
            }

            double downLevel = (double)(higherIndex + 1) * 1.5;

            // 上位3足目は拡大フォント同士の間隔を上下で広げる。
            if (higherIndex == 3) {
                upLevel += 0.5;
                downLevel += 1.5;
            }

            int edgeLane =
                this.layoutHigherTimeFrameDisplayCount - higherIndex;

            this.setElliot(
                elliot,
                "Elliot" + IntegerToString(higherIndex),
                fontSizeIncrease,
                upLevel,
                downLevel,
                edgeLane
            );
        }
        
        if (fromIsElliotInfoVisible) {
            this.setElliotTable();
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定Elliotの波形ラベルを描画する。
     *
     * @param elliot 描画対象Elliot
     * @param fromName オブジェクト名プレフィックス
     * @param fromFontSize 文字サイズ加算値
     * @param upLevel 上方向オフセット
     * @param downLevel 下方向オフセット
     * @param fromEdgeLane 上下端で使用する表示レーン
     */
    void setElliot(
        Elliot &elliot,
        string fromName,
        int fromFontSize,
        double upLevel,
        double downLevel,
        int fromEdgeLane
    ) {
        //this.logger.setLevel(LOG_DEBUG);
        
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int fontSize = drawProperties.elliotFontSize + fromFontSize;
        
        CArrayObj *waveList = &(elliot.waveList);
        
        int waveTotal = waveList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("waveTotal = %d", waveTotal));
        
        //LogUtil::printWaveList(this.logger, __FUNCTION__, waveList);
        
        for (int i = 0; i < waveTotal; i++) {
            Wave *wave = waveList.At(i);
            
            /*if (i == 0 || i == 1) {
                LogUtil::printZigZagPointList(this.logger, __FUNCTION__, wave.zigZagPointList);
            }*/
            
            this.setWave(wave, fromName, fontSize, upLevel, downLevel, fromEdgeLane);
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        //this.logger.setLevel(LOG_INFO);
    }
    
    /**
     * 全時間足Elliotのサマリー表を描画する。
     */
    void setElliotTable() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int objY = 70;
        int elliotHeihgt = 40;
        
        CArrayObj *elliotList = &(this.elliotAll.elliotList);
        
        for (int i = elliotList.Total() - 1; i >= 0; i--) {
            Elliot *elliot = elliotList.At(i);
            
            this.setElliotTable(elliot, objY);
                
            objY += (int)((double)elliotHeihgt * 1.3);
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 1行分のElliotサマリーを描画する。
     *
     * @param elliot 表示対象Elliot
     * @param objY Y座標
     */
    void setElliotTable(Elliot &elliot, int objY) {
        int objX = 0;
        color fontColorAll = clrWhite;
        string timeFrameLabel = elliot.marketContext.timeFrameLabel;
        string preName = "Elliot" + timeFrameLabel;
        //string text = "";
        int width = 0;
        
        Wave *latestWave = elliot.getLatestWave();
        
        if (latestWave == NULL) {
            return;
        }
        
        //Print(latestWave.toString());
        
        if (elliot.isBuy) {
            fontColorAll = drawProperties.elliotUpColor;
        } else {
            fontColorAll = drawProperties.elliotDownColor;
        }
        
        if (this.isVisible(COLMUN_TIME_FRAME, width)) {
            string text = "TimeFrame";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColorAll, 
                                drawProperties.elliotAlertSize, timeFrameLabel, objX, objY);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_BUYSELL, width)) {
            string text = "BuySell";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColorAll, 
                                drawProperties.elliotAlertSize, elliot.buySellLabel, objX, objY);
            objX += width;
        }
        
        
        if (this.isVisible(COLMUN_EMA200_BUYSELL, width)) {
            string text = "EMA200";
            
            string signalTextLabel = elliot.oscillator.ema200.getBuySellLabel();
            
            color fontColor = clrWhite;
            
            if (signalTextLabel == "BUY") {
                fontColor = drawProperties.elliotUpColor;
            }
            
            if (signalTextLabel == "SELL") {
                fontColor = drawProperties.elliotDownColor;
            }
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                                drawProperties.elliotAlertSize, signalTextLabel, objX, objY);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_STOCHASTIC_MAIN_ORDER, width)) {
            string text = "SMO";
            
            color fontColor = elliot.oscillator.getStochasticMainOrderColor();
            string smoText = elliot.oscillator.getStochasticMainOrderText();

            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                            drawProperties.elliotAlertSize / 2, smoText, objX, objY + 10);
            
            objX += width;
        }
        
        if (this.isVisible(COLMUN_STOCHASTIC_SHORT, width)) {
            string text = "S";
            //int stochasticCount = elliot.oscillator.stochasticCount;
            int stochasticCount = elliot.oscillator.stochasticShort.count;
            
            color fontColor = this.getColor(stochasticCount);
                        
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                                (drawProperties.elliotAlertSize / 2), StringUtil::addSign(stochasticCount), objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_STOCHASTIC_MIDDLE, width)) {
            string text = "M";
            //int macdTrendCount = elliot.oscillator.macdTrendCount;
            int macdTrendCount = elliot.oscillator.stochasticMiddle.count;
            
            color fontColor = this.getColor(macdTrendCount);
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                                (drawProperties.elliotAlertSize / 2), StringUtil::addSign(macdTrendCount), objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_STOCHASTIC_LONG, width)) {
            string text = "L";
            //int heikenAshiSmoothedCount = elliot.oscillator.heikenAshiSmoothedCount;
            int heikenAshiSmoothedCount = elliot.oscillator.stochasticLong.count;
            
            color fontColor = this.getColor(heikenAshiSmoothedCount);
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                                (drawProperties.elliotAlertSize / 2), StringUtil::addSign(heikenAshiSmoothedCount), objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_GMMA_TREND, width)) {
            int gmmaTrendCount = elliot.oscillator.gmmaTrendCount;
            string text = "GT";
            color fontColor = this.getColor(gmmaTrendCount);
            
            int fontSize = drawProperties.elliotAlertSize;
            
            if (MathAbs(gmmaTrendCount) >= 100) {
                fontSize -= 6;
            }
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                            fontSize, StringUtil::addSign(gmmaTrendCount), objX, objY);
            
            objX += width;
        }
        
        if (this.isVisible(COLMUN_GMMA_CROSS, width)) {
            int gmmaCrossCount = elliot.oscillator.gmmaCrossCount;            
            string text = "GC";
            color fontColor = this.getColor(gmmaCrossCount);
            
            int fontSize = drawProperties.elliotAlertSize;
            
            if (MathAbs(gmmaCrossCount) >= 100) {
                fontSize -= 6;
            }
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                            fontSize, StringUtil::addSign(gmmaCrossCount), objX, objY);
            
            objX += width;
        }
        
        if (this.isVisible(COLMUN_FRACTAL, width)) {
            string text = "PLE";
            color fontColor = fontColorAll;
            
            string pleText = " ";
            
            if (!StringUtil::isEmpty(latestWave.previousLastElliotLabel)) {
                pleText = latestWave.previousLastElliotLabel;
                
                if (pleText == "A" || pleText == "E") {
                    fontColor = clrWhite;
                }
            }
            
            
            /*if (latestWave.isPrevCorrectionCCompleted) {
                fractalText = "CCmp";
            }*/
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                                drawProperties.elliotAlertSize, pleText, objX, objY);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_ELLIOT, width)) {
            string text = "Elliot";
            color fontColor = fontColorAll;
            
            ZigZagPoint *zigZagPoint = latestWave.getLatestPoint();
            
            // 未確定の場合色変更
            if (!latestWave.isConfirmed) {
                if (elliot.isBuy) {
                    fontColor = drawProperties.elliotMikakuteiUpColor;
                } else {
                    fontColor = drawProperties.elliotMikakuteiDownColor;
                }
            }
            
            if (zigZagPoint.isAddedPoint) {
                fontColor = clrWhite;
            }

            string elliotText = zigZagPoint.getTextIndexInfo();

            if (!latestWave.isConfirmed) {
                elliotText = latestWave.getConfirmedLabel() + elliotText;
            }

            int previousMotiveSubElliotIndex =
                latestWave.getPreviousMotiveSubElliotIndex();

            if (previousMotiveSubElliotIndex > 0) {
                elliotText = StringFormat(
                    "[%d副] %s",
                    previousMotiveSubElliotIndex,
                    elliotText
                );
            }
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                                drawProperties.elliotAlertSize, elliotText, objX, objY);
        }
        
        // エリオット
        /*if (arrayAlertFlg[++pipeIndex]) {
            objectName = PREFIX + "ElliotAlert" + strPeriod;
            fontColor = ElliotUpColor;
            
            if (!latestWave.isUpTrend) {
                fontColor = ElliotDownColor;
            }
            
            string alertText = elliot.elliotAlert;
            Point *point = latestWave.getLatestPoint();
            
            if (CheckPointer(point) != POINTER_INVALID) {
                if (common.isGuusuu(point.index)) { // 偶数は色反転
                    if (fontColor == ElliotUpColor) {
                        fontColor = ElliotDownColor;
                    } else {
                        fontColor = ElliotUpColor;
                    }
                } else {
                    if (!elliot.isKakutei()) {    // 未確定の色設定
                        if (fontColor == ElliotUpColor) {
                            fontColor = ElliotMikakuteiUpColor;
                        } else {
                            fontColor = ElliotMikakuteiDownColor;
                        }
                    }
                }
                
                draw.setLabel(objectName, ElliotFontFace, fontColor, ElliotAlertSize, alertText, this.getX(objX), objY);
            }
        }*/
        
        
        this.setPipeAll(preName, objY);
    }

protected:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;
    
    /** 描画共通設定。 */
    DrawProperties drawProperties;
    /** Elliot解析全体を保持する参照。 */
    ElliotAll *elliotAll;

    /** Elliottラベルをチャート上下端へ収める場合true。 */
    bool clampVertical;

    /** 波動ラベルを表示する設定上の上位時間足数。 */
    int higherTimeFrameDisplayCount;

    /** 現在の描画で使用する上位時間足数。 */
    int layoutHigherTimeFrameDisplayCount;
    
    /** 列表示設定のリスト。時間軸ごとに表示可否と幅を保持する。 */
    CArrayObj drawPropertiesElliotList;
    
    /**
     * 列表示設定をリストに追加する。
     *
     * @param isVisible 列表示フラグ
     * @param width 列幅
     */
    void addDrawPropertiesElliotList(bool isVisible, int width) {
        DrawPropertiesElliot *drawPropertiesElliot = new DrawPropertiesElliot(isVisible, width);
        
        this.drawPropertiesElliotList.Add(drawPropertiesElliot);
    }
    
    /**
     * 対象インデックスの列表示設定を参照し、表示可否と列幅を返す。
     *
     * @param index 列インデックス
     * @param width 列幅を格納する変数
     * @return 表示対象ならtrue
     */
    bool isVisible(int index, int &width) {
        bool isVisible = false;
        
        DrawPropertiesElliot *drawPropertiesElliot = this.drawPropertiesElliotList.At(index);
        
        if (drawPropertiesElliot != NULL) {
            isVisible = drawPropertiesElliot.isVisible;
            width = drawPropertiesElliot.width;
        }
        
        return isVisible;
    }
    
    /**
     * サマリー表のヘッダを描画する。
     */
    void setLabel() {
        string preName = "ElliotLabel";
        color fontColor = clrWhite;
        int size = 20;
        int objX = 0;
        int objY = 10;
        
        string text = "";
        int width = 0;
        
        if (this.isVisible(COLMUN_TIME_FRAME, width)) {
            text = "TimeFrame";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size - 6, text, objX, objY + 15);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_BUYSELL, width)) {
            text = "BuySell";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_EMA200_BUYSELL, width)) {
            text = "EMA200";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX, objY + 10);
            objX += width;
        }        
        
        if (this.isVisible(COLMUN_STOCHASTIC_MAIN_ORDER, width)) {
            text = "SMO";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_STOCHASTIC_SHORT, width)) {
            text = "S";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX + 10, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_STOCHASTIC_MIDDLE, width)) {
            text = "M";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX + 10, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_STOCHASTIC_LONG, width)) {
            text = "L";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX + 10, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_GMMA_TREND, width)) {
            text = "GT";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_GMMA_CROSS, width)) {
            text = "GC";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_IMPULSE, width)) {
            text = "Impulse";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size - 3, text, objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_FRACTAL, width)) {
            text = "PLE";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX, objY + 10);
            objX += width;
        }
        
        if (this.isVisible(COLMUN_ELLIOT, width)) {
            text = "Elliot";
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, size, text, objX, objY + 10);
            objX += width;
        }
        
        this.setPipeAll(preName, objY);
    }
    
    /**
     * 列境界のパイプ文字列を描画する。
     */
    void setPipeAll(string objectName, int objY) {
        int objX = 0;
        
        for (int i = 0; i < this.drawPropertiesElliotList.Total() - 1; i++) {
            DrawPropertiesElliot *drawPropertiesElliot = this.drawPropertiesElliotList.At(i);
            
            if (drawPropertiesElliot.isVisible) {
                objX += drawPropertiesElliot.width;
                
                DrawUtil::setLabel(objectName + "Pipe" + IntegerToString(i), drawProperties.elliotFontFace, clrWhite, 
                                    drawProperties.elliotAlertSize, "|", objX - 15, objY);
            }
            
        }
    }
    
    /**
     * 波動とポイント情報を描画する。
     *
     * @param wave 描画対象波
     * @param name 表示名
     * @param fontSize 文字サイズ
     * @param upLevel 上方向オフセット
     * @param downLevel 下方向オフセット
     * @param fromEdgeLane 上下端で使用する表示レーン
     */
    void setWave(
        Wave &wave,
        string name,
        int fontSize,
        double upLevel,
        double downLevel,
        int fromEdgeLane
    ) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        this.logger.debug(__FUNCTION__, wave.toString());
        
        bool isUpper = false;
        
        if (wave.marketContext.timeFrame > Period()) {
            isUpper = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isUpper = %s", (string)isUpper));
        
        
        CArrayObj *zigZagPointList = &(wave.zigZagPointList);
                        
        int total = zigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        
        for (int i = 1; i < total; i++) {  // ポイント0は対象外
            this.logger.debug(__FUNCTION__, StringFormat("i = %d", i));
            
            ZigZagPoint *zigZagPoint = zigZagPointList.At(i);
            
            if (zigZagPoint != NULL) {
                string timeFrameLabel = "";
                
                if (isUpper) {
                    timeFrameLabel = zigZagPoint.marketContext.timeFrameLabel + " ";
                }
                
                string text = timeFrameLabel + zigZagPoint.getTextIndexInfo();

                if (wave.index == 0 && i == total - 1 && !wave.isConfirmed) {
                    text = wave.getConfirmedLabel() + text;
                }

                double level = 0;
                color fontColor = White;
                
                if (wave.index == 0) {  // 最新波動
                    if (zigZagPoint.isPeak) {
                        fontColor = drawProperties.elliotUpColor;
                    } else {
                        fontColor = drawProperties.elliotDownColor;
                    }
                    
                    if (i == total - 1 && !wave.isConfirmed) {  // 最新ポイント
                        if (zigZagPoint.isPeak) {
                            fontColor = drawProperties.elliotMikakuteiUpColor;
                        } else {
                            fontColor = drawProperties.elliotMikakuteiDownColor;
                        }
                    }
                }
                
                if (zigZagPoint.isPeak) {
                    level = 0 - upLevel;
                } else {
                    level = downLevel;
                }
                
                string elliotId = "_w" + StringUtil::zeroPadding(wave.index, 2) + "_i" + StringUtil::zeroPadding(i, 2);
                string objectName = name + elliotId;
                
                datetime drawDatetime = zigZagPoint.barTime;
                double drawPrice = this.getDrawPrice(
                    drawDatetime,
                    zigZagPoint.rate,
                    level,
                    fontSize,
                    fromEdgeLane
                );
                
                DrawUtil::setText(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawDatetime, drawPrice);
            }
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 矢印ラベル表示のための価格位置を算出する。
     *
     * チャート座標へ変換できない場合は、表示価格幅から1ピクセル当たりの
     * 価格を算出して同じ上下オフセットを適用する。
     *
     * @param time 基準時間
     * @param price 基準価格
     * @param level レベルオフセット
     * @param fromFontSize 文字サイズ
     * @param fromEdgeLane 上下端で使用する表示レーン
     * @return 調整後価格
     */
    double getDrawPrice(
        const datetime time,
        const double price,
        const double level,
        const int fromFontSize,
        const int fromEdgeLane
    ) {
        int xPosition = 0;
        int yPosition = 0;
        int subWindow = 0;
        datetime drawTime = 0;
        double convertedPrice = 0;
        double drawPrice = price;
    
        double distance = 0;
        
        if (level < 0) {
            distance = level * (double)drawProperties.fontPixelHeight + level * drawProperties.elliotPixelDistance;
        } else {
       	    distance = (level - 1) * (double)drawProperties.fontPixelHeight + level * drawProperties.elliotPixelDistance;
        }

        int pixelDistance = (int)distance;
       
        bool isConverted = false;

        if (ChartTimePriceToXY(0, 0, time, price, xPosition, yPosition)) {
            if (ChartXYToTimePrice(
                    0,
                    xPosition,
                    yPosition + pixelDistance,
                    subWindow,
                    drawTime,
                    convertedPrice
            )) {
                drawPrice = convertedPrice;
                isConverted = true;
            }
        }

        if (!isConverted) {
            int chartHeight = (int)ChartGetInteger(
                0,
                CHART_HEIGHT_IN_PIXELS,
                0
            );
            double priceMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
            double priceMax = ChartGetDouble(0, CHART_PRICE_MAX, 0);

            if (chartHeight > 1 && priceMax > priceMin) {
                double pricePerPixel =
                    (priceMax - priceMin) / ((double)chartHeight - 1.0);
                drawPrice = price - (double)pixelDistance * pricePerPixel;
            }
        }

        if (this.clampVertical) {
            return this.clampDrawPrice(drawPrice, fromFontSize, fromEdgeLane);
        }

        return drawPrice;
    }

    /**
     * ラベル中心価格をチャート上下端の表示レーン内へ収める。
     *
     * @param fromPrice 補正前価格
     * @param fromFontSize 文字サイズ
     * @param fromEdgeLane 上下端で使用する表示レーン
     * @return 上下端へ収めた価格
     */
    double clampDrawPrice(
        const double fromPrice,
        const int fromFontSize,
        const int fromEdgeLane
    ) {
        int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
        double priceMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
        double priceMax = ChartGetDouble(0, CHART_PRICE_MAX, 0);

        if (chartHeight <= 1 || priceMax <= priceMin) {
            return fromPrice;
        }

        int baseFontSize = drawProperties.elliotFontSize;

        if (baseFontSize <= 0) {
            return fromPrice;
        }

        double baseFontHeight = (double)drawProperties.fontPixelHeight;

        if (baseFontHeight <= 0) {
            baseFontHeight = (double)baseFontSize;
        }

        int edgeLane = fromEdgeLane;

        if (edgeLane < 0) {
            edgeLane = 0;
        }

        double labelHeight = baseFontHeight * (double)fromFontSize / (double)baseFontSize;
        double maxFontSize = (double)(
            baseFontSize + this.layoutHigherTimeFrameDisplayCount * 2
        );
        double maxLabelHeight = baseFontHeight * maxFontSize / (double)baseFontSize;
        double edgeInset = labelHeight / 2.0 + (double)drawProperties.elliotPixelDistance;

        edgeInset += (double)edgeLane * (
            maxLabelHeight + (double)drawProperties.elliotPixelDistance
        );

        double maxInset = ((double)chartHeight - 1.0) / 2.0;

        if (edgeInset > maxInset) {
            edgeInset = maxInset;
        }

        double pricePerPixel = (priceMax - priceMin) / ((double)chartHeight - 1.0);
        double topPrice = priceMax - edgeInset * pricePerPixel;
        double bottomPrice = priceMin + edgeInset * pricePerPixel;

        if (fromPrice > topPrice) {
            return topPrice;
        }

        if (fromPrice < bottomPrice) {
            return bottomPrice;
        }

        return fromPrice;
    }

private:
    /**
     * 現在足で使用する波動ラベルの上位時間足数を取得する。
     *
     * 上位3足が存在しない場合は従来の上位2足レイアウトを維持する。
     *
     * @return 描画レイアウトへ使用する上位時間足数
     */
    int getLayoutHigherTimeFrameDisplayCount() {
        if (this.higherTimeFrameDisplayCount == 3) {
            Elliot *elliotHigher3 = this.elliotAll.getElliot(
                this.elliotAll.marketContext.timeFrame,
                3
            );

            if (elliotHigher3 != NULL) {
                return 3;
            }
        }

        return 2;
    }

    /**
     * 値の符号に応じて描画用フォントカラーを返す。
     *
     * @param value 判定値。正: 上方向、負: 下方向
     * @return フォント色
     */
    color getColor(int value) {
        if (value == 0) {
            return clrWhite;
        }
    
        color fontColor = drawProperties.elliotUpColor;
            
        if (value < 0) {
            fontColor = drawProperties.elliotDownColor;
        }
        
        return fontColor;
    }

};

