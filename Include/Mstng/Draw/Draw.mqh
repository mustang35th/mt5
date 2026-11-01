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
 * 時計・銘柄名・当日高安の情報ラベルは専用の固定接頭辞で再利用する。
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
        this.roundLinesDraw = NULL;

        for (int i = 0; i < 3; i++) {
            this.bidAskLabelReady[i] = false;
            this.bidAskLabelTexts[i] = "";
            this.bidAskLabelColors[i] = clrNONE;
        }

        for (int i = 0; i < 8; i++) {
            this.infoLabelReady[i] = false;
            this.infoLabelTexts[i] = "";
        }

        this.diffJpyLabelCleared = false;
    }
    
    /**
     * デストラクタ。
     */
    ~Draw() {
        this.clearInfoLabels();
        this.clearRoundLines();
        if (this.roundLinesDraw != NULL) {
            delete this.roundLinesDraw;
            this.roundLinesDraw = NULL;
        }
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
            if (this.roundLinesDraw == NULL) {
                this.roundLinesDraw = new DrawRoundLines(this.elliotAll.marketContext);
            } else {
                this.roundLinesDraw.setMarketContext(this.elliotAll.marketContext);
            }

            if (this.roundLinesDraw != NULL) {
                this.roundLinesDraw.draw();
            }
        } else {
            this.clearRoundLines();
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
        
        string objectName;
        string text;        
        
        
        objectName = "Ask";
        text = "";
        
        if (isSuccess) {
            text = StringFormat("A:%s", DoubleToString(tick.ask, digits));
        }
        
        this.updateBidAskLabel(0, objectName, text, drawProperties.objXRight, 130, clrAqua);
        
        
        objectName = "Bid";
        text = "";
        
        if (isSuccess) {
            text = StringFormat("B:%s", DoubleToString(tick.bid, digits));
        }
        
        this.updateBidAskLabel(1, objectName, text, drawProperties.objXRight, 160, clrHotPink);
        
        
        objectName = "Spread";
        text = "";
        color spreadColor = clrSilver;
        
        if (isSuccess) {
            text = StringFormat("S:%s", DoubleToString(spread, 1));
            if (spread > 5.0) {
                spreadColor = clrOrange;
            }
        }
        
        this.updateBidAskLabel(2, objectName, text, drawProperties.objXRight + 140, 145, spreadColor);
    }
    
    /**
     * システム時刻（JST/サーバー）と実行時間を描画する。
     */
    void drawTime() {
        color fontColor = clrWhite;
        string objectName = "Sysdate";
        int fontSize = 14;
        
        string text = StringFormat("%s", TimeUtil::formatYyyymmddhhmiss(this.elliotAll.tradeTimeInfo.jstTime) + " JST");
                
        this.updateInfoLabel(0, objectName + "JST", fontColor, fontSize, text, drawProperties.objXRight, 210);
        
        text = StringFormat("%s", TimeUtil::formatYyyymmddhhmiss(this.elliotAll.tradeTimeInfo.serverTime));
                
        this.updateInfoLabel(1, objectName + "GMT", fontColor, fontSize, text, drawProperties.objXRight, 230);
        
        
        objectName = "execTime";
        text = StringFormat("[%dms]<%ds>", this.elliotAll.execTime, this.elliotAll.timerSeconds);
                
        this.updateInfoLabel(2, objectName, fontColor, fontSize, text, drawProperties.objXRight, 250);
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
        
        this.updateInfoLabel(3, objectName, clrGold, fontSize, text, drawProperties.objXRight, 0);
        
        
        objectName = "High";
        text = StringFormat("H:%s", todayRate.highLabel);
        fontSize = 20;
        
        this.updateInfoLabel(4, objectName, clrLightSkyBlue, fontSize, text, drawProperties.objXRight, 50);
        
        
        objectName = "Low";
        text = StringFormat("L:%s", todayRate.lowLabel);
        
        this.updateInfoLabel(5, objectName, clrLightPink, fontSize, text, drawProperties.objXRight, 80);
        
        
        objectName = "Diff";
        text = StringFormat("D:%s", todayRate.diffLabel);
        
        this.updateInfoLabel(6, objectName, clrKhaki, fontSize, text, drawProperties.objXRight + 140, 65);
        
        if (todayRate.diffJpy > 0) {
            this.diffJpyLabelCleared = false;
            objectName = "DiffJpy";
            text = StringFormat("D Jpy:%s", todayRate.diffJpyLabel);
            
            this.updateInfoLabel(7, objectName, fontColor, fontSize - 5, text, drawProperties.objXRight + 142, 95);
        } else if (!this.diffJpyLabelCleared) {
            this.infoLabelReady[7] = false;
            this.infoLabelTexts[7] = "";
            objectName = this.getInfoLabelObjectName("DiffJpy");
            this.diffJpyLabelCleared = ObjectFind(0, objectName) < 0;
            if (!this.diffJpyLabelCleared) {
                this.diffJpyLabelCleared = ObjectDelete(0, objectName);
            }
        }
    }

    /**
     * 時計・銘柄名・当日高安の情報ラベルと反映履歴を初期化する。
     * 再初期化時と終了時に、専用の固定接頭辞のオブジェクトだけを削除する。
     */
    void clearInfoLabels() {
        ObjectsDeleteAll(0, Constant::PREFIX_FIXED + "ZigZagElliotInfo", 0, -1);

        for (int i = 0; i < 8; i++) {
            this.infoLabelReady[i] = false;
            this.infoLabelTexts[i] = "";
        }

        this.diffJpyLabelCleared = false;
    }

    /**
     * 保持するラウンドナンバー線と描画インスタンスを解放する。
     * 削除に失敗した場合は、次回に再試行できるようインスタンスを保持する。
     *
     * @return 削除済み、または解放に成功した場合true。
     */
    bool clearRoundLines() {
        if (this.roundLinesDraw != NULL) {
            if (!this.roundLinesDraw.clear()) {
                return false;
            }

            delete this.roundLinesDraw;
            this.roundLinesDraw = NULL;
        }

        return true;
    }

private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;
    
    /** 表示設定。 */
    DrawProperties drawProperties;

    /** 同じ価格区間のラウンドナンバー線を保持する描画インスタンス。 */
    DrawRoundLines *roundLinesDraw;

    /** 描画対象のElliot全体データ。 */
    ElliotAll *elliotAll;

    /** Ask・Bid・Spreadラベルの初期設定および文字・色反映が成功した場合true。 */
    bool bidAskLabelReady[3];

    /** Ask・Bid・Spreadラベルへ最後に反映した文字。 */
    string bidAskLabelTexts[3];

    /** Ask・Bid・Spreadラベルへ最後に反映した色。 */
    color bidAskLabelColors[3];

    /** 時計3個と当日レート5個の固定設定・文字反映が成功した場合true。 */
    bool infoLabelReady[8];

    /** 情報ラベルへ最後に反映した文字。 */
    string infoLabelTexts[8];

    /** 非表示の円換算値幅ラベルが存在しない、または削除要求が成功した場合true。 */
    bool diffJpyLabelCleared;

    /**
     * 全体描画の削除対象から除外する情報ラベル名を返す。
     *
     * @param fromObjectName 接頭辞を除いたラベル名
     * @return 専用の固定接頭辞を付けたオブジェクト名
     */
    string getInfoLabelObjectName(string fromObjectName) {
        return Constant::PREFIX_FIXED + "ZigZagElliotInfo" + fromObjectName;
    }

    /**
     * 情報ラベルを再利用し、表示文字が変わった場合だけ更新する。
     * 各ラベルの色・フォント・サイズ・座標は固定し、初回と再試行時だけ反映する。
     * 手動削除時は再作成し、設定に失敗した場合は次回に全属性を再試行する。
     *
     * @param fromIndex 時計3個・当日レート5個に対応するキャッシュ番号
     * @param fromObjectName 接頭辞を除いたラベル名
     * @param fromColor 文字色
     * @param fromFontSize 文字サイズ
     * @param fromText 表示文字
     * @param fromX X座標
     * @param fromY Y座標
     */
    void updateInfoLabel(
        int fromIndex,
        string fromObjectName,
        color fromColor,
        int fromFontSize,
        string fromText,
        int fromX,
        int fromY
    ) {
        string objectName = this.getInfoLabelObjectName(fromObjectName);
        if (ObjectFind(0, objectName) < 0) {
            this.infoLabelReady[fromIndex] = false;
            if (!ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0)) {
                return;
            }
        }

        bool initializeProperties = !this.infoLabelReady[fromIndex];
        this.infoLabelReady[fromIndex] = false;
        if (initializeProperties) {
            if (!ObjectSetInteger(0, objectName, OBJPROP_COLOR, fromColor)
                    || !ObjectSetString(0, objectName, OBJPROP_FONT, this.drawProperties.elliotFontFace)
                    || !ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, fromFontSize)
                    || !ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, fromX)
                    || !ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, fromY)) {
                return;
            }
        }

        if (initializeProperties || this.infoLabelTexts[fromIndex] != fromText) {
            if (!ObjectSetString(0, objectName, OBJPROP_TEXT, fromText)) {
                return;
            }
        }

        this.infoLabelTexts[fromIndex] = fromText;
        this.infoLabelReady[fromIndex] = true;
    }

    /**
     * レートラベルを再利用し、表示文字と色をそれぞれ変更時だけ更新する。
     *
     * 全体再描画や手動操作で削除された場合は固定設定ごと復元する。
     * 設定に失敗した場合はキャッシュを確定せず、次回描画で再試行する。
     *
     * @param fromIndex Ask・Bid・Spreadに対応するキャッシュ番号
     * @param fromObjectName 共通接頭辞を除いたラベル名
     * @param fromText 表示文字
     * @param fromX X座標
     * @param fromY Y座標
     * @param fromColor 表示色
     */
    void updateBidAskLabel(
        int fromIndex,
        string fromObjectName,
        string fromText,
        int fromX,
        int fromY,
        color fromColor
    ) {
        string objectName = Constant::PREFIX + fromObjectName;

        if (ObjectFind(0, objectName) < 0) {
            this.bidAskLabelReady[fromIndex] = false;

            if (!ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0)) {
                return;
            }
        }

        bool initializeProperties = !this.bidAskLabelReady[fromIndex];
        this.bidAskLabelReady[fromIndex] = false;
        if (initializeProperties) {
            if (!ObjectSetString(0, objectName, OBJPROP_FONT, this.drawProperties.elliotFontFace)
                    || !ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 20)
                    || !ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, fromX)
                    || !ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, fromY)) {
                return;
            }
        }

        if (initializeProperties || this.bidAskLabelColors[fromIndex] != fromColor) {
            if (!ObjectSetInteger(0, objectName, OBJPROP_COLOR, fromColor)) {
                return;
            }
        }

        if (initializeProperties || this.bidAskLabelTexts[fromIndex] != fromText) {
            if (!ObjectSetString(0, objectName, OBJPROP_TEXT, fromText)) {
                return;
            }
        }

        this.bidAskLabelTexts[fromIndex] = fromText;
        this.bidAskLabelColors[fromIndex] = fromColor;
        this.bidAskLabelReady[fromIndex] = true;
    }
    
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
     * 通常版M5では通貨強弱とGMMAを組み合わせ、準備・成立の2段階で表示する。
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
            bgColor = this.getM5BackgroundColor(isBuy);
        }

        DrawUtil::setBgColor(bgColor);
        
        //delete expertAdvisorOscillator;
    }

    /**
     * 通貨強弱とGMMAの準備・成立状態に対応するM5背景色を取得する。
     *
     * 強弱の両期間とGMMAトレンド・クロスが売買方向と一致し、
     * 長中期は順位差4以上または方向に合う1位・8位、中短期は順位差4以上で達成とする。
     * 少なくとも片方の期間が達成なら準備色とする。
     * 両期間達成かつGMMA両カウントの絶対値が2以上なら成立色とする。
     * 差0・GMMAの0・逆方向・欠損・時刻不一致は黒とする。
     * エントリーフィルターの有効状態や最低順位差設定には連動しない。
     *
     * @param fromIsBuy 買い方向の場合true。
     * @return BUYは濃紺系、SELLは暗赤系。未成立の場合は黒。
     */
    color getM5BackgroundColor(const bool fromIsBuy) {
        CurrencyStrengthExecutionInfo executionInfo =
            this.elliotAll.currencyStrengthExecutionInfo;
        if (executionInfo.targetM5BarTime <= 0
                || !executionInfo.isExactM5Bar()
                || !executionInfo.isDirectionAligned(fromIsBuy)) {
            return clrBlack;
        }

        int gmmaTrendCount = this.elliotAll.elliotCurrent.oscillator.gmmaTrendCount;
        int gmmaCrossCount = this.elliotAll.elliotCurrent.oscillator.gmmaCrossCount;
        bool isGmmaAligned = gmmaTrendCount > 0 && gmmaCrossCount > 0;
        bool isGmmaReady = gmmaTrendCount >= 2 && gmmaCrossCount >= 2;
        if (!fromIsBuy) {
            isGmmaAligned = gmmaTrendCount < 0 && gmmaCrossCount < 0;
            isGmmaReady = gmmaTrendCount <= -2 && gmmaCrossCount <= -2;
        }

        if (!isGmmaAligned) {
            return clrBlack;
        }

        bool isLongMediumReady = MathAbs(executionInfo.getLongMediumRankDifference()) >= 4;
        if (!isLongMediumReady) {
            if (fromIsBuy) {
                isLongMediumReady = executionInfo.pairRankInfo.baseLongMediumTermAverageRank == 1
                    || executionInfo.pairRankInfo.quoteLongMediumTermAverageRank == 8;
            } else {
                isLongMediumReady = executionInfo.pairRankInfo.baseLongMediumTermAverageRank == 8
                    || executionInfo.pairRankInfo.quoteLongMediumTermAverageRank == 1;
            }
        }

        bool isMediumShortReady = MathAbs(executionInfo.getMediumShortRankDifference()) >= 4;
        if (isLongMediumReady && isMediumShortReady && isGmmaReady) {
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


