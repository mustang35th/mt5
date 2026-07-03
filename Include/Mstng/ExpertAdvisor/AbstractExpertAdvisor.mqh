//+------------------------------------------------------------------+
//|                                        AbstractExpertAdvisor.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\ElliottWaveInfo.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorElliot.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorEma200.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorOscillator.mqh>

#include <Mstng\Mail\Mail.mqh>
#include <Mstng\Signal\SignalCount.mqh>

/**
 * Elliott波動とオシレーター情報を使用するEA判定の基底クラス。
 */
class AbstractExpertAdvisor {
public:
    /** EA判定名 */
    string name;

    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;
    
    /** BUY方向の場合true */
    bool isBuy;

    /** BUYまたはSELLの表示ラベル */
    string buySellLabel;

    /** 売買方向の表示記号 */
    string buySellSymbol;

    /** 現在波動が上昇トレンドの場合true */
    bool isUptrend;

    /** アラート条件を満たした場合true */
    bool isAlert;

    /** エントリー条件を満たした場合true */
    bool isEntry;

    /** メールを送信する場合true */
    bool isSendMail;

    /** アラート表示文字列 */
    string alertText;

    /** ロスカット価格 */
    double stopLoss;

    /** シグナル記録用CSV文字列 */
    string csvText;

    /** 時間足別Elliott波動情報一覧 */
    CArrayObj elliottWaveInfoList;

    /**
     * デフォルトコンストラクタ。
     */
    AbstractExpertAdvisor() {
        this.initializeMembers();
    };

    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsDrawArrow シグナル矢印を描画する場合true
     */
    AbstractExpertAdvisor(MarketContext &fromMarketContext, bool fromIsDrawArrow) {
        this.initializeMembers();
        this.init(fromMarketContext, fromIsDrawArrow);
    };

    /**
     * デストラクタ。
     */
    ~AbstractExpertAdvisor() {
        this.releaseExpertAdvisorHelpers();
    };
    
    /**
     * 分析対象と描画設定を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromIsDrawArrow シグナル矢印を描画する場合true
     */
    void init(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsDrawArrow) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.init(context, fromIsDrawArrow);
    }

    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsDrawArrow シグナル矢印を描画する場合true
     */
    void init(MarketContext &fromMarketContext, bool fromIsDrawArrow) {
        this.setMarketContext(fromMarketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.isDrawArrow = fromIsDrawArrow;

        this.logger.debug(__FUNCTION__, "symbolName=" + this.marketContext.symbolName);
        this.logger.debug(__FUNCTION__, "timeFrame=" + IntegerToString(this.marketContext.timeFrame));
        this.logger.debug(__FUNCTION__, "timeFrameLabel=" + this.marketContext.timeFrameLabel);

        this.isDarwText = false;
        this.fontSize = 10;
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 分析対象の市場コンテキストを設定する。
     *
     * 判定補助クラスを新しい市場向けに再生成し、旧分析結果への
     * 非所有参照と判定状態をクリアする。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.releaseExpertAdvisorHelpers();
        this.elliottWaveInfoList.Clear();
        this.resetAnalysisReferences();
        this.initializeMarketContext(fromMarketContext);

        this.expertAdvisorElliot = new ExpertAdvisorElliot(this.marketContext);
        this.expertAdvisorOscillator = new ExpertAdvisorOscillator(this.marketContext);
    }

    /**
     * Elliott分析結果からアラートおよびエントリーを判定する。
     *
     * @param fromElliotAll 全時間足のElliott分析結果
     * @param signalCount 同一シグナルの発生回数管理
     * @param entryCount エントリー対象とする発生回数
     */
    void analyze(ElliotAll *fromElliotAll, SignalCount *signalCount, int entryCount = 1) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (!this.setElliotAll(fromElliotAll)) {
            this.logger.error(__FUNCTION__, StringFormat("%s setElliotAll returned false", this.name));
            
            return;
        }
        
        bool isJudge = this.isJudge();
        
        if (isJudge) {
            this.isAlert = true;
            
            int count = signalCount.addCount(this.pointElliotCurrent_2.barTime, this.isBuy);
            
            if (count == entryCount) {
                this.elliotAll.mailTitile = StringFormat("【%s】", this.name);
                
                this.setEntry();
            } else {
                this.isAlert = false;
            }
            
            this.setCsvText();
            this.setStopLoss();
        }
        
        if (this.isDrawArrow) {
            this.drawArrow();
        }
        
        delete this.expertAdvisorEma200;
        this.expertAdvisorEma200 = NULL;
        
        this.logger.debug(__FUNCTION__, StringFormat("isEntry = %s", (string)this.isEntry));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 保有方向と反対のGMMAクロスが発生したか判定する。
     *
     * @param fromElliotAll 全時間足のElliott分析結果
     * @param isBuyPosition BUYポジションの場合true
     * @return 決済条件を満たす場合true
     */
    bool isExit(ElliotAll *fromElliotAll, bool isBuyPosition) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (!this.setElliotAll(fromElliotAll)) {
            this.logger.error(__FUNCTION__, StringFormat("%s setElliotAll returned false", this.name));
            
            return false;
        }
        
        bool isExit = false;
        
        if (this.expertAdvisorOscillator.isGmmaCross_2(this.elliotCurrent, !isBuyPosition)) {
            isExit = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isExit = %s", (string)isExit));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isExit;
    }

    /**
     * ロスカット価格を変更可能か判定する。
     *
     * @return 変更可能な場合true。現状は常にfalse
     */
    bool isStopLossModifiable() {
        bool isStopLossModifiable = false;
        
        
        
        
        return isStopLossModifiable;
    }
    
protected:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;

    /** シグナル矢印を描画する場合true */
    bool isDrawArrow;

    /** 矢印の代わりにテキストを描画する場合true */
    bool isDarwText;

    /** Elliott波動条件の判定補助クラス */
    ExpertAdvisorElliot *expertAdvisorElliot;
    
    
    /** EMA200 エキスパートアドバイザー。 */
    ExpertAdvisorEma200 *expertAdvisorEma200;

    /** オシレーター条件の判定補助クラス */
    ExpertAdvisorOscillator *expertAdvisorOscillator;

    /** 全時間足のElliott分析結果への非所有参照 */
    ElliotAll *elliotAll;
    
    //Elliot *elliotMN1;
    //Elliot *elliotW1;
    /** D1のElliott分析結果への非所有参照 */
    Elliot *elliotD1;

    /** H4のElliott分析結果への非所有参照 */
    Elliot *elliotH4;

    /** H1のElliott分析結果への非所有参照 */
    Elliot *elliotH1;

    /** M15のElliott分析結果への非所有参照 */
    Elliot *elliotM15;

    /** M5のElliott分析結果への非所有参照 */
    Elliot *elliotM5;

    /** M1のElliott分析結果への非所有参照 */
    Elliot *elliotM1;

    /** 現在時間足から2つ上位のElliott分析結果への非所有参照 */
    Elliot *elliotHigher2;

    /** 現在時間足から1つ上位のElliott分析結果への非所有参照 */
    Elliot *elliotHigher1;

    /** 現在時間足のElliott分析結果への非所有参照 */
    Elliot *elliotCurrent;

    /** 現在時間足の1つ前のZigZagポイントへの非所有参照 */
    ZigZagPoint *pointElliotCurrent_2;

    /** 現在時間足の最新ZigZagポイントへの非所有参照 */
    ZigZagPoint *pointElliotCurrent_1;

    /** チャート描画用フォントサイズ */
    int fontSize;

    /** BUY方向の矢印コード */
    int arrowCdUp;

    /** SELL方向の矢印コード */
    int arrowCdDown;

    /**
     * 派生EA固有のアラート条件を判定する。
     *
     * @return アラート条件を満たす場合true
     */
    virtual bool isJudge() = 0;

    /**
     * 派生EA固有のエントリー条件を設定する。
     */
    virtual void setEntry() = 0;

    /**
     * M15の最新ポイントがエントリー対象波動か判定する。
     *
     * @return 第1波、第3波、第5波またはC波の場合true
     */
    bool isElliotM15() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
                
        bool isElliotM15 = false;
        
        ZigZagPoint *latestPointM15 = this.elliotM15.getLatestPoint();
        string elliotLabelM15 = latestPointM15.elliotLabel;
        
        if (elliotLabelM15 == "1" || elliotLabelM15 == "3" || elliotLabelM15 == "5"
                || elliotLabelM15 == "C") {
            isElliotM15 = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliotM15 = %s", (string)isElliotM15));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliotM15;
    }

    /**
     * M5波動に対してM1の最新ポイントがエントリー対象波動か判定する。
     *
     * @return M5とM1の波動条件を満たす場合true
     */
    bool isElliotM1() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
                
        bool isElliot = false;
        
        ZigZagPoint *latestPointM5 = this.elliotM5.getLatestPoint();
        string elliotLabelM5 = latestPointM5.elliotLabel;
        //int elliotIndexM5 = latestPointM5.elliotIndex;
        
        ZigZagPoint *latestPointM1 = this.elliotM1.getLatestPoint();
        string elliotLabelM1 = latestPointM1.elliotLabel;
        
        if (elliotLabelM5 == "1") {
            if (elliotLabelM1 == "1" || elliotLabelM1 == "3" || elliotLabelM1 == "5") {
                isElliot = true;
            }
        }
        
        if (elliotLabelM5 == "3") {
            if (elliotLabelM1 == "1" || elliotLabelM1 == "3") {
                isElliot = true;
            }
        }
        
        if (elliotLabelM5 == "5") {
            if (elliotLabelM1 == "1" || elliotLabelM1 == "3") {
                isElliot = true;
            }
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("isElliot = %s", (string)isElliot));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isElliot;
    }

    /**
     * 指定したElliotのフィボナッチエクスパンションが上限以内か判定する。
     *
     * @param elliot 判定対象
     * @param inValue フィボナッチエクスパンション上限値
     * @return 上限値以下の場合true
     */
    bool isFibonacciExpansionPercent(Elliot *elliot, double inValue) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isFibonacciExpansionPercent = false;
        
        ZigZagPoint *latestPoint = elliot.getLatestPoint();
        double fibonacciExpansionPercent = latestPoint.fibonacciExpansionPercent;
        
        if (fibonacciExpansionPercent <= inValue) {
            isFibonacciExpansionPercent = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("fibonacciExpansionPercent = %f", fibonacciExpansionPercent));
        this.logger.debug(__FUNCTION__, StringFormat("isFibonacciExpansionPercent = %s", (string)isFibonacciExpansionPercent));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isFibonacciExpansionPercent;
    }

    /**
     * 現在時間足のフィボナッチエクスパンションが上限以内か判定する。
     *
     * @param inValue フィボナッチエクスパンション上限値
     * @return 上限値以下の場合true
     */
    bool isFibonacciExpansionPercent(double inValue) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        bool isFibonacciExpansionPercent = false;
        double fibonacciExpansionPercent = pointElliotCurrent_1.fibonacciExpansionPercent;
        
        if (fibonacciExpansionPercent <= inValue) {
            isFibonacciExpansionPercent = true;
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("fibonacciExpansionPercent = %f", fibonacciExpansionPercent));
        this.logger.debug(__FUNCTION__, StringFormat("isFibonacciExpansionPercent = %s", (string)isFibonacciExpansionPercent));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return isFibonacciExpansionPercent;
    }

    /**
     * ロスカット幅が指定値以内か判定する。
     *
     * @param inValue ロスカット幅の上限値
     * @return 上限値以下の場合true
     */
    bool isLossCut(double inValue) {
        bool isLossCut = false;
        
        double diff = this.elliotAll.lossCut.diff;
        
        if (!this.marketContext.isJpy()) {
            diff = this.elliotAll.lossCut.diffJpy;
        }
        
        if (diff <= inValue) {
            isLossCut = true;
        }
        
        return isLossCut;
    }
    
    /*bool isLossCutJpy(double inValue) {
        bool isLossCut = false;
        
        if (this.elliotAll.lossCut.diffJpy <= inValue) {
            isLossCut = true;
        }
        
        return isLossCut;
    }*/

    /**
     * 現在スプレッドが許容範囲内か判定する。
     *
     * @return スプレッドが3以下の場合true
     */
    bool isSpread() {
        bool isSpread = false;
        
        if (this.elliotAll.todayRate.spread <= 3) {
            isSpread = true;
        }
        
        return isSpread;
    }
    
private:
    /**
     * コンストラクタ共通の初期値を設定する。
     */
    void initializeMembers() {
        this.expertAdvisorElliot = NULL;
        this.expertAdvisorEma200 = NULL;
        this.expertAdvisorOscillator = NULL;
        this.resetAnalysisReferences();
    }

    /**
     * 判定補助クラスを解放する。
     */
    void releaseExpertAdvisorHelpers() {
        if (this.expertAdvisorElliot != NULL) {
            delete this.expertAdvisorElliot;
            this.expertAdvisorElliot = NULL;
        }

        if (this.expertAdvisorEma200 != NULL) {
            delete this.expertAdvisorEma200;
            this.expertAdvisorEma200 = NULL;
        }

        if (this.expertAdvisorOscillator != NULL) {
            delete this.expertAdvisorOscillator;
            this.expertAdvisorOscillator = NULL;
        }
    }

    /**
     * Elliott分析結果への非所有参照と判定状態を初期化する。
     */
    void resetAnalysisReferences() {
        this.elliotAll = NULL;
        this.elliotD1 = NULL;
        this.elliotH4 = NULL;
        this.elliotH1 = NULL;
        this.elliotM15 = NULL;
        this.elliotM5 = NULL;
        this.elliotM1 = NULL;
        this.elliotHigher2 = NULL;
        this.elliotHigher1 = NULL;
        this.elliotCurrent = NULL;
        this.pointElliotCurrent_2 = NULL;
        this.pointElliotCurrent_1 = NULL;
        this.isBuy = false;
        this.buySellLabel = "";
        this.buySellSymbol = "";
        this.isUptrend = false;
        this.isAlert = false;
        this.isEntry = false;
        this.isSendMail = false;
        this.alertText = "";
        this.stopLoss = 0.0;
        this.csvText = "";
    }

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
     * Elliott分析結果を保持し、判定に使用する時間足別参照を設定する。
     *
     * @param fromElliotAll 全時間足のElliott分析結果
     * @return 判定に必要な情報を設定できた場合true
     */
    bool setElliotAll(ElliotAll *fromElliotAll) {
        LogUtil::printMethodStart(logger, __FUNCTION__);

        if (this.expertAdvisorEma200 != NULL) {
            delete this.expertAdvisorEma200;
            this.expertAdvisorEma200 = NULL;
        }
        
        this.elliotAll = fromElliotAll;
        
        if (!this.elliotAll.isAnalysisSucceeded) {
            this.logger.error(__FUNCTION__, "elliotAll.isAnalysisSucceeded is false");
            
            return false;
        }
        
        this.isAlert = false;
        this.isEntry = false;
        this.isSendMail = false;
        
        this.alertText = "";
                    
        //this.elliotMN1 = this.elliotAll.elliotMN1;
        //this.elliotW1 = this.elliotAll.elliotW1;
        this.elliotD1 = this.elliotAll.getElliot(PERIOD_D1);
        this.elliotH4 = this.elliotAll.getElliot(PERIOD_H4);
        this.elliotH1 = this.elliotAll.getElliot(PERIOD_H1);
        this.elliotM15 = this.elliotAll.getElliot(PERIOD_M15);
        this.elliotM5 = this.elliotAll.getElliot(PERIOD_M5);
        this.elliotM1 = this.elliotAll.getElliot(PERIOD_M1);
        
        this.elliotHigher2 = this.elliotAll.getElliot(this.marketContext.timeFrame, 2);
        this.elliotHigher1 = this.elliotAll.getElliot(this.marketContext.timeFrame, 1);
        this.elliotCurrent = this.elliotAll.elliotCurrent;
        
        this.isBuy = this.elliotCurrent.isBuy;
        this.buySellLabel = this.elliotCurrent.buySellLabel;
        
        this.buySellSymbol = "▲";
        
        if (!this.isBuy) {
            this.buySellSymbol = "▼";
        }
        
        this.isUptrend = this.elliotCurrent.isUptrend();
        
        this.pointElliotCurrent_2 = this.elliotCurrent.getLatestPoint2();
        if (this.pointElliotCurrent_2 == NULL) {
            this.logger.error(__FUNCTION__, "pointElliotCurrent_2 is NULL");
            
            return false;
        }
        
        this.pointElliotCurrent_1 = this.elliotCurrent.getLatestPoint();
        if (this.pointElliotCurrent_1 == NULL) {
            this.logger.error(__FUNCTION__, "pointElliotCurrent_1 is NULL");
            
            return false;
        }
        
        this.setElliottWaveInfoList();
        
        this.expertAdvisorEma200 = new ExpertAdvisorEma200(this.isBuy);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }

    /**
     * 判定結果に応じてチャート描画、メール送信またはログ出力を行う。
     */
    void drawArrow() {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        if (this.isAlert) {
            color fontColor = clrLightGray;
            int arrowCd = 117;
            double offset = 0;
            
            if (this.isBuy) {
                arrowCd = this.arrowCdUp;
                
                fontColor = clrBlue;
                
                if (this.isEntry) {
                    fontColor = clrDodgerBlue;
                }            
            } else {
                arrowCd = this.arrowCdDown;
                
                fontColor = clrRed;
                
                if (this.isEntry) {
                    fontColor = clrMagenta;
                }
            }
            
            if (this.isDarwText) {
                datetime drawDatetime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);
                double drawPrice = iOpen(this.marketContext.symbolName, this.marketContext.timeFrame, 0) /*+ common.getOffset(isBuy, offset)*/;
    
                DrawUtil::setTextFixed("Text" + this.name  + IntegerToString((int)drawDatetime), "MS Gothic", fontColor, 
                        this.fontSize, this.alertText, drawDatetime, drawPrice);
                
            } else {
                DrawUtil::setArrow("Arrow" + this.name, fontColor, arrowCd, this.fontSize, 0, offset);
            }
            
            if (this.elliotAll.isSendMail) {
                Mail::sendMail(this.elliotAll, this.isSendMail);
            } else {
                string text = "Alert";
                
                if (this.isEntry) {
                    text = "Entry";
                }
                
                Print(StringFormat(",%s,%s", text, elliotAll.getCsv()));
            }
            
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 時間足別のElliott波動情報一覧を再構築する。
     */
    void setElliottWaveInfoList() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.elliottWaveInfoList.Clear();
        
        CArrayObj *elliotList = &(this.elliotAll.elliotList);
        
        for (int i = 0; i < elliotList.Total(); i++) {
            Elliot *elliot = elliotList.At(i);
            
            Wave *latestWave = elliot.getLatestWave();
        
            if (latestWave == NULL) {
                return;
            }
        
            ZigZagPoint *zigZagPoint = latestWave.getLatestPoint();
            
            //ElliottWaveInfo *elliottWaveInfo = new ElliottWaveInfo(elliot.marketContext.timeFrameLabel, elliot.buySellLabel, 
            //    StringUtil::addSign(elliot.oscillator.oscillatorCount), StringUtil::addSign(elliot.oscillator.gmmaCrossCount), zigZagPoint.getTextIndexInfo());
            
            ElliottWaveInfo *elliottWaveInfo = new ElliottWaveInfo(elliot.marketContext);

            elliottWaveInfo.buySell = elliot.buySellLabel;
            elliottWaveInfo.oscillator = StringUtil::addSign(elliot.oscillator.oscillatorCount);
            elliottWaveInfo.oscillatorS = StringUtil::addSign(elliot.oscillator.stochasticShort.count);
            elliottWaveInfo.oscillatorM = StringUtil::addSign(elliot.oscillator.stochasticMiddle.count);
            elliottWaveInfo.oscillatorL = StringUtil::addSign(elliot.oscillator.stochasticLong.count);
            elliottWaveInfo.gmma = StringUtil::addSign(elliot.oscillator.gmmaCrossCount);
            elliottWaveInfo.elliott = zigZagPoint.getTextIndexInfo();
            
            this.elliottWaveInfoList.Add(elliottWaveInfo);
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 詳細なElliott分析結果をCSV文字列へ設定する。
     */
    void setCsvText() {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        this.csvText = this.elliotAll.getCsv(true);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * Elliott分析結果からロスカット価格を設定する。
     */
    void setStopLoss() {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        this.stopLoss = this.elliotAll.lossCut.lc5;
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};







