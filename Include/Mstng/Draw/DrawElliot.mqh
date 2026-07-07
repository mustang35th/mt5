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
 * Elliotの波形・状態情報をチャート上に表形式・ラベル付きで描画するクラスです。
 */
class DrawElliot {
public:
    /**
     * 描画列幅の初期値を設定して初期化する。
     */
    DrawElliot() {
        this.logger.setLevel(LOG_INFO);
        
        this.addDrawPropertiesElliotList(true, 90); // COLMUN_TIME_FRAME
        this.addDrawPropertiesElliotList(true, 110);    // COLMUN_BUYSELL
        this.addDrawPropertiesElliotList(true, 110);    // COLMUN_EMA200_BUYSELL
        this.addDrawPropertiesElliotList(false, 70);     // COLMUN_STOCHASTIC_MAIN_ORDER
        this.addDrawPropertiesElliotList(true, 50);    // COLMUN_STOCHASTIC_SHORT
        this.addDrawPropertiesElliotList(true, 50);    // COLMUN_STOCHASTIC_MIDDLE
        this.addDrawPropertiesElliotList(true, 50);    // COLMUN_HEIKEN_ASHI_SMOOTHED
        this.addDrawPropertiesElliotList(true, 90);    // COLMUN_GMMA_TREND
        this.addDrawPropertiesElliotList(true, 90);    // COLMUN_GMMA_CROSS
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
     */
    void draw(ElliotAll *fromElliotAll, bool fromIsElliotInfoVisible = true) {
        this.elliotAll = fromElliotAll;
        
        this.logger.setMarketContext(this.elliotAll.marketContext);
        
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (fromIsElliotInfoVisible) {
            this.setLabel();
        }
        
        int fontSize = 2;
        double upLevel = 0;
        double downLevel = 0;
        
        Elliot *elliot2 = this.elliotAll.getElliot(this.elliotAll.marketContext.timeFrame, 2);
        
        if (elliot2 != NULL) {
            fontSize = 4;
            upLevel = 3;
            downLevel = 4.5;
            
            this.setElliot(elliot2, "Elliot2", fontSize, upLevel, downLevel);
        }
        
        
        Elliot *elliot1 = this.elliotAll.getElliot(this.elliotAll.marketContext.timeFrame, 1);
        
        if (elliot1 != NULL) {
            fontSize = 2;
            upLevel = 2;
            downLevel = 3;
            
            this.setElliot(elliot1, "Elliot1", fontSize, upLevel, downLevel);
        }
        
        
        Elliot *elliot0 = this.elliotAll.getElliot(this.elliotAll.marketContext.timeFrame);
        
        if (elliot0 != NULL) {
            this.setElliot(elliot0, "Elliot0", 0, 0, 1.5);
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
     */
    void setElliot(Elliot &elliot, string fromName, int fromFontSize, double upLevel, double downLevel) {
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
            
            this.setWave(wave, fromName, fontSize, upLevel, downLevel);
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
            
            DrawUtil::setLabel(preName + text, drawProperties.elliotFontFace, fontColor, 
                                drawProperties.elliotAlertSize, zigZagPoint.getTextIndexInfo(), objX, objY);
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
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;
    
    /** 描画共通設定 */
    DrawProperties drawProperties;
    /** Elliot解析全体を保持する参照 */
    ElliotAll *elliotAll;
    
    /** 列表示設定のリスト（時間軸ごとに表示可否・幅を保持） */
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
     * @param width 列幅出力引数
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
     */
    void setWave(Wave &wave, string name, int fontSize, double upLevel, double downLevel) {
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
                double drawPrice = this.getDrawPrice(drawDatetime, zigZagPoint.rate, level);
                
                DrawUtil::setText(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawDatetime, drawPrice);
            }
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 矢印ラベル表示のための価格位置を算出する。
     *
     * @param time 基準時間
     * @param price 基準価格
     * @param level レベルオフセット
     * @return 調整後価格
     */
    double getDrawPrice(const datetime time, const double price, const double level) {
        int x, y, cw;
        datetime t;
        double p;
    
        double distance = 0;
        
        if (level < 0) {
            distance = level * (double)drawProperties.fontPixelHeight + level * drawProperties.elliotPixelDistance;
        } else {
       	    distance = (level - 1) * (double)drawProperties.fontPixelHeight + level * drawProperties.elliotPixelDistance;
        }
       
        ChartTimePriceToXY(0, 0, time, price, x, y);
        ChartXYToTimePrice(0, x, y + (int)distance, cw, t, p);
        
        return p;
    }

private:
    /**
     * 値の符号に応じて描画用フォントカラーを返す。
     *
     * @param value 判定値（正:上方向,負:下方向）
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

