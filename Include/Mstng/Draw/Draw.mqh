//+------------------------------------------------------------------+
//|                                                         Draw.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Draw\DrawElliot.mqh>
#include <Mstng\Draw\DrawFiboExpansion.mqh>
#include <Mstng\Draw\DrawHorizontalLine.mqh>
#include <Mstng\Draw\DrawProperties.mqh>
#include <Mstng\Draw\DrawRoundLines.mqh>
#include <Mstng\Draw\DrawZigZag.mqh>
#include <Mstng\ExpertAdvisor\Common\ExpertAdvisorBuySell.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorEma200.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorOscillator.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>

#include <Mstng\Util\UtilAll.mqh>

/**
 * 描画処理の統括クラス。
 *
 * Elliotの解析結果に基づき、ZigZag、Elliottラベル、補助線、
 * レート情報、背景色などをまとめて描画する。
 * 再描画時はPREFIXに紐づく既存オブジェクトを削除してから描画する。
 */
class Draw {
public:
    /**
     * コンストラクタ。
     *
     * 描画処理用Loggerのログレベルを初期化する。
     */
    Draw() {
        this.logger.setLevel(LOG_INFO);
    }
    
    /**
     * デストラクタ。
     */
    ~Draw() {
    }
    
    /**
     * すべての描画を実行する。
     *
     * 既存描画を削除し、各描画モジュールを順に呼び出して再描画する。
     *
     * @param fromElliotAll Elliot解析結果
     * @param fromIsElliotInfoVisible エリオット情報表示有無
     * @param fromClampElliotVertical Elliottラベルを上下端へ収める場合true
     * @param fromSimpleElliotInfo Elliott情報を簡易表示する場合true
     * @param fromElliotHigherTimeFrameDisplayCount 波動ラベルを表示する上位時間足数
     */
    void drawAll(
        ElliotAll *fromElliotAll,
        bool fromIsElliotInfoVisible = true,
        bool fromClampElliotVertical = false,
        bool fromSimpleElliotInfo = false,
        int fromElliotHigherTimeFrameDisplayCount = 2
    ) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.elliotAll = fromElliotAll;
        
        // 当プロジェクトのオブジェクト接頭辞に該当するもののみ削除して再描画する。
        ObjectsDeleteAll(0, Constant::PREFIX, 0, -1);
        
        if (this.elliotAll.marketContext.timeFrame <= PERIOD_H1) {
            DrawRoundLines drawRoundLines(this.elliotAll.marketContext);

            drawRoundLines.draw();
        }
        
        
        DrawZigZag drawZigZag;
        
        drawZigZag.draw(this.elliotAll);
        
        
        DrawElliot drawElliot(
            fromSimpleElliotInfo,
            fromElliotHigherTimeFrameDisplayCount
        );
        
        drawElliot.draw(
            this.elliotAll,
            fromIsElliotInfoVisible,
            fromClampElliotVertical
        );
        
        
        DrawHorizontalLine drawHorizontalLine;
        
        drawHorizontalLine.draw(this.elliotAll);
        
        DrawFiboExpansion drawFiboExpansion;
        
        drawFiboExpansion.draw(this.elliotAll);
        
        
        this.drawTodayRate();
        this.drawTime();
        
        this.drawBidAsk(this.elliotAll.marketContext);
        
        //this.drawMarketActivityAnalyzer();
        
        this.drawBgColor();
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /*void drawBidAsk(string symbolName) {
        TodayRate todayRate;
        todayRate.update(symbolName);
        
        color fontColor = clrWhite;
        string objectName = "Ask";
        string text = StringFormat("A:%s", todayRate.askLabel);        
        int fontSize = 20;
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 130);
        
        objectName = "Bid";
        text = StringFormat("B:%s", todayRate.bidLabel);
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 160);
        
        objectName = "Spread";
        text = StringFormat("S:%s", todayRate.spreadLabel);
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight + 140, 145);
    }*/
    
    /**
     * シンボル名から市場コンテキストを作成し、Bid/Ask/Spreadを描画する。
     *
     * @param symbolName シンボル名
     */
    void drawBidAsk(string symbolName) {
        MarketContext context(symbolName, PERIOD_CURRENT);

        this.drawBidAsk(context);
    }

    /**
     * 市場コンテキストを使用してBid、Askおよびスプレッドを描画する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void drawBidAsk(MarketContext &fromMarketContext) {
        MqlTick tick;
        int digits = fromMarketContext.digits;
        double spread = 0.0;
        
        bool isSuccess = SymbolInfoTick(fromMarketContext.symbolName, tick);
        
        if (isSuccess) {
            spread = RateUtil::getDiffPips(tick.bid, tick.ask, fromMarketContext);
        }
        
        color fontColor = clrWhite;
        string objectName;
        string text;        
        int fontSize = 20;
        
        
        objectName = "Ask";
        text = "";
        
        if (isSuccess) {
            text = StringFormat("A:%s", DoubleToString(tick.ask, digits));
        }
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 130);
        
        
        objectName = "Bid";
        text = "";
        
        if (isSuccess) {
            text = StringFormat("B:%s", DoubleToString(tick.bid, digits));
        }
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 160);
        
        
        objectName = "Spread";
        text = "";
        
        if (isSuccess) {
            text = StringFormat("S:%s", DoubleToString(spread, 1));
        }
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight + 140, 145);
    }
    
    /**
     * システム時刻（JST/サーバー）と実行時間を描画する。
     */
    void drawTime() {
        color fontColor = clrWhite;
        string objectName = "Sysdate";
        int fontSize = 14;
        
        string text = StringFormat("%s", TimeUtil::formatYyyymmddhhmiss(this.elliotAll.tradeTimeInfo.jstTime) + " JST");
                
        DrawUtil::setLabel(objectName + "JST", drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 210);
        
        text = StringFormat("%s", TimeUtil::formatYyyymmddhhmiss(this.elliotAll.tradeTimeInfo.serverTime));
                
        DrawUtil::setLabel(objectName + "GMT", drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 230);
        
        
        objectName = "execTime";
        text = StringFormat("[%dms]<%ds>", this.elliotAll.execTime, this.elliotAll.timerSeconds);
                
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 250);
    }
    
    /**
     * シンボル情報と当日高値・安値を描画する。
     */
    void drawTodayRate() {
        TodayRate todayRate = this.elliotAll.todayRate;
        
        color fontColor = clrWhite;
        string objectName = "TodayRateSymbol";
        string text = StringFormat(
            "%s,%s",
            this.elliotAll.marketContext.symbolName,
            this.elliotAll.marketContext.timeFrameLabel
        );
        int fontSize = 30;
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 0);
        
        
        objectName = "High";
        text = StringFormat("H:%s", todayRate.highLabel);
        fontSize = 20;
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 50);
        
        
        objectName = "Low";
        text = StringFormat("L:%s", todayRate.lowLabel);
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 80);
        
        
        objectName = "Diff";
        text = StringFormat("D:%s", todayRate.diffLabel);
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight + 140, 65);
        
        if (todayRate.diffJpy > 0) {
            objectName = "DiffJpy";
            text = StringFormat("D Jpy:%s", todayRate.diffJpyLabel);
            
            DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize - 5, text, drawProperties.objXRight + 142, 95);
        }
        
    }
    
private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;
    
    /** 表示設定。 */
    DrawProperties drawProperties;

    /** 描画対象のElliot全体データ。 */
    ElliotAll *elliotAll;
    
    /*void drawBgColor() {
        color bgColor = clrBlack;
    
        color upColor = clrMidnightBlue;    
        color downColor = clrMaroon;
        
        Elliot *elliotM15 = this.elliotAll.getElliot(PERIOD_M15);
        
        if (elliotM15 != NULL
                && this.elliotAll.elliotCurrent != NULL
                && this.elliotAll.elliotCurrent.marketContext.timeFrame <= PERIOD_M15) {
            bool isBuy = elliotM15.isBuy;
        
            ExpertAdvisorBuySell *expertAdvisorBuySell = new ExpertAdvisorBuySell(
                this.elliotAll.marketContext.symbolName,
                this.elliotAll.elliotCurrent.marketContext.timeFrame
            );
            
            expertAdvisorBuySell.setRank(this.elliotAll);
            
            if (expertAdvisorBuySell.rank != EXPERT_ADVISOR_ENTRY_RANK_NON) {
                if (isBuy) {
                    bgColor = upColor;
                } else {
                    bgColor = downColor;
                }
            }
            
            delete expertAdvisorBuySell;
        }
        
        DrawUtil::setBgColor(bgColor);
    }*/
    
    /**
     * 市場状況に応じた背景色を設定する。
     *
     * 上位足とEMA200条件が揃った場合に背景色を売買方向へ合わせる。
     * 通常版M5では通貨強弱の両期間方向一致と順位差4以上を準備・成立の2段階で表示する。
     * 条件を満たさない場合は黒背景を設定する。
     */
    void drawBgColor() {
        color bgColor = clrBlack;
    
        color upColor = clrMidnightBlue;    
        color downColor = clrMaroon;
        
        /*ExpertAdvisorOscillator *expertAdvisorOscillator = new ExpertAdvisorOscillator(this.elliotAll.marketContext.symbolName, this.elliotAll.marketContext.timeFrame);
        
        if (expertAdvisorOscillator.isStochasticMainOrder(this.elliotAll)) {
            if (this.elliotAll.elliotCurrent.isBuy) {
                bgColor = upColor;
            } else {
                bgColor = downColor;
            }
        }*/
        
        if (this.elliotAll.marketContext.timeFrame >= PERIOD_H1) {
            DrawUtil::setBgColor(bgColor);

            return;
        }
        

        if (this.elliotAll.elliotCurrent == NULL) {
            DrawUtil::setBgColor(bgColor);

            return;
        }

        bool isBuy = this.elliotAll.elliotCurrent.isBuy;
        ExpertAdvisorEma200 expertAdvisorEma200(isBuy);

        Elliot *elliotHigher2 = this.elliotAll.getElliot(this.elliotAll.marketContext.timeFrame, 2);
        Elliot *elliotHigher1 = this.elliotAll.getElliot(this.elliotAll.marketContext.timeFrame, 1);
        Elliot *elliotCurrent = this.elliotAll.elliotCurrent;

        if (this.elliotAll.isBuySell(PERIOD_D1)
                && expertAdvisorEma200.isEma200BuySell(elliotHigher2)
                && expertAdvisorEma200.isEma200BuySell(elliotHigher1)
                && expertAdvisorEma200.isEma200BuySell(elliotCurrent)
        ) {
            if (isBuy) {
                bgColor = upColor;
            } else {
                bgColor = downColor;
            }
        }
        
        if (bgColor != clrBlack
                && this.elliotAll.marketContext.timeFrame == PERIOD_M5
                && MQLInfoString(MQL_PROGRAM_NAME) == "ZigZagElliot") {
            bgColor = this.getM5CurrencyStrengthBackgroundColor(isBuy);
        }

        DrawUtil::setBgColor(bgColor);
        
        //delete expertAdvisorOscillator;
    }

    /**
     * 通貨強弱の準備・成立状態に対応するM5背景色を取得する。
     *
     * 両期間が売買方向と一致し、片方だけ順位差4以上なら準備色、
     * 両方とも4以上なら成立色とする。差0・逆方向・欠損・時刻不一致は黒とする。
     * エントリーフィルターの有効状態や最低順位差設定には連動しない。
     *
     * @param fromIsBuy 買い方向の場合true。
     * @return BUYは濃紺系、SELLは暗赤系。未成立の場合は黒。
     */
    color getM5CurrencyStrengthBackgroundColor(const bool fromIsBuy) {
        CurrencyStrengthExecutionInfo executionInfo =
            this.elliotAll.currencyStrengthExecutionInfo;
        if (executionInfo.targetM5BarTime <= 0
                || !executionInfo.isExactM5Bar()
                || !executionInfo.isDirectionAligned(fromIsBuy)) {
            return clrBlack;
        }

        bool isLongMediumReady = MathAbs(executionInfo.getLongMediumRankDifference()) >= 4;
        bool isMediumShortReady = MathAbs(executionInfo.getMediumShortRankDifference()) >= 4;
        if (isLongMediumReady && isMediumShortReady) {
            if (fromIsBuy) {
                return clrMidnightBlue;
            }

            return clrMaroon;
        }

        if (isLongMediumReady || isMediumShortReady) {
            if (fromIsBuy) {
                return C'12,12,56';
            }

            return C'64,0,0';
        }

        return clrBlack;
    }

    /*void drawMarketActivityAnalyzer() {
        color fontColor = this.elliotAll.marketActivityAnalyzer.getLevelColor();
        string objectName = "MarketActivityAnalyzerLabel";
        string text = StringFormat("%s", this.elliotAll.marketActivityAnalyzer.getLevelLabel());
        int fontSize = 30;
        
        DrawUtil::setLabel(objectName, drawProperties.elliotFontFace, fontColor, fontSize, text, drawProperties.objXRight, 300);
    }*/
};


