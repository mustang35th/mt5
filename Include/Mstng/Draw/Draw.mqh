//+------------------------------------------------------------------+
//|                                                         Draw.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Draw\DrawElliot.mqh>
#include <Mstng\Draw\DrawFiboExpansion.mqh>
#include <Mstng\Draw\DrawHorizontalLine.mqh>
#include <Mstng\Draw\DrawProperties.mqh>
#include <Mstng\Draw\DrawRoundLines.mqh>
#include <Mstng\Draw\DrawZigZag.mqh>
#include <Mstng\Draw\DrawZigZagElliotInfoLayout.mqh>
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
        this.infoRightDistance = DrawZigZagElliotInfoLayout::getMinimumRightDistance();
        this.symbolLabelName = "";
        this.lastBidAskLabelCheckTick = 0;

        for (int i = 0; i < 6; i++) {
            this.bidAskLabelReady[i] = false;
            this.bidAskLabelTexts[i] = "";
            this.bidAskLabelColors[i] = clrNONE;
        }

        for (int i = 0; i < 19; i++) {
            this.infoLabelReady[i] = false;
            this.infoLabelTexts[i] = "";
            this.infoLabelTooltips[i] = "";
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
     * 右側情報欄の余白を設定し、変更時だけ固定座標を再反映する。
     *
     * @param fromRightDistance チャート右端から情報欄までの距離
     */
    void setInfoRightDistance(int fromRightDistance) {
        int rightDistance = fromRightDistance;
        if (rightDistance < DrawZigZagElliotInfoLayout::getMinimumRightDistance()) {
            rightDistance = DrawZigZagElliotInfoLayout::getMinimumRightDistance();
        }

        if (this.infoRightDistance == rightDistance) {
            return;
        }

        this.infoRightDistance = rightDistance;
        this.invalidateBidAskLabels();

        for (int i = 0; i < 19; i++) {
            this.infoLabelReady[i] = false;
        }
    }

    /**
     * レートラベルの作成状態を無効化し、次回描画で存在と固定設定を確認する。
     */
    void invalidateBidAskLabels() {
        for (int i = 0; i < 6; i++) {
            this.bidAskLabelReady[i] = false;
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
        this.invalidateBidAskLabels();
        
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
        drawElliot.setReservedRightWidth(
            DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance) + 12
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
     * ラベルの存在は未準備時と1秒経過後の描画時だけ確認する。
     * 価格・色は描画呼び出しごとに変更を反映する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void drawBidAsk(MarketContext &fromMarketContext) {
        const ulong labelCheckIntervalMilliseconds = 1000;
        ulong currentTick = GetTickCount64();
        bool checkLabelExistence =
            currentTick - this.lastBidAskLabelCheckTick >= labelCheckIntervalMilliseconds;
        if (checkLabelExistence) {
            this.lastBidAskLabelCheckTick = currentTick;
        }

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
            text = DoubleToString(tick.ask, digits);
        }
        
        this.updateBidAskLabel(3, "AskTitle", "A:", 0, 116, clrAqua, checkLabelExistence);
        this.updateBidAskLabel(0, objectName, text,
            DrawZigZagElliotInfoLayout::getPriceValueRightOffset(), 116, clrAqua, checkLabelExistence, ANCHOR_RIGHT_UPPER);
        
        
        objectName = "Bid";
        text = "";
        
        if (isSuccess) {
            text = DoubleToString(tick.bid, digits);
        }
        
        this.updateBidAskLabel(4, "BidTitle", "B:", 0, 146, clrHotPink, checkLabelExistence);
        this.updateBidAskLabel(1, objectName, text,
            DrawZigZagElliotInfoLayout::getPriceValueRightOffset(), 146, clrHotPink, checkLabelExistence, ANCHOR_RIGHT_UPPER);
        
        
        objectName = "Spread";
        text = "";
        color spreadColor = clrSilver;
        
        if (isSuccess) {
            text = DoubleToString(spread, 1);
            if (spread > 5.0) {
                spreadColor = clrOrange;
            }
        }
        
        this.updateBidAskLabel(5, "SpreadTitle", "S:",
            DrawZigZagElliotInfoLayout::getSecondaryTitleLeftOffset(), 116, spreadColor, checkLabelExistence);
        this.updateBidAskLabel(2, objectName, text,
            DrawZigZagElliotInfoLayout::getSecondaryValueLeftOffset(), 116, spreadColor, checkLabelExistence);
    }
    
    /**
     * システム時刻（JST/サーバー）とJST基準の時差、実行時間を描画する。
     */
    void drawTime() {
        color fontColor = clrWhite;
        string objectName = "Sysdate";
        int fontSize = DrawZigZagElliotInfoLayout::getTimeFontSize();
        
        string text = TimeUtil::formatYyyymmddhhmiss(this.elliotAll.tradeTimeInfo.jstTime);
                
        this.updateInfoLabel(13, "JstTitle", fontColor, fontSize, "JST", 0, 180);
        this.updateInfoLabel(0, objectName + "JST", fontColor, fontSize, text,
            DrawZigZagElliotInfoLayout::getTimeValueLeftOffset(), 180);
        
        int serverOffsetHour = -this.elliotAll.tradeTimeInfo.jstOffsetHour;
        text = TimeUtil::formatYyyymmddhhmiss(this.elliotAll.tradeTimeInfo.serverTime);
        string tooltip = StringFormat("サーバー時刻 = JST %+d時間", serverOffsetHour);
                
        this.updateInfoLabel(14, "ServerTitle", fontColor, fontSize, "SRV", 0, 202, tooltip);
        this.updateInfoLabel(1, objectName + "GMT", fontColor, fontSize, text,
            DrawZigZagElliotInfoLayout::getTimeValueLeftOffset(), 202, tooltip);
        this.updateInfoLabel(15, "ServerOffset", fontColor, fontSize - 2,
            StringFormat("(%+dh)", serverOffsetHour), DrawZigZagElliotInfoLayout::getWidth(), 204,
            tooltip, ANCHOR_RIGHT_UPPER);
        
        
        objectName = "execTime";
        text = StringFormat("[%dms]<%ds>", this.elliotAll.execTime, this.elliotAll.timerSeconds);
                
        this.updateInfoLabel(2, objectName, fontColor, fontSize, text, 0, 224);
    }
    
    /**
     * シンボル情報と当日高値・安値を描画する。
     */
    void drawTodayRate() {
        TodayRate todayRate = this.elliotAll.todayRate;
        
        color fontColor = clrWhite;
        string objectName;
        string text;
        int fontSize = 30;
        
        this.drawSymbolName();
        this.updateInfoLabel(8, "TodayRateTimeFrame", clrWhite, fontSize,
            this.elliotAll.marketContext.timeFrameLabel,
            DrawZigZagElliotInfoLayout::getWidth(), 0, "", ANCHOR_RIGHT_UPPER);
        
        
        objectName = "High";
        text = todayRate.highLabel;
        fontSize = 20;
        
        this.updateInfoLabel(9, "HighTitle", clrLightSkyBlue, fontSize, "H:", 0, 46);
        this.updateInfoLabel(4, objectName, clrLightSkyBlue, fontSize, text,
            DrawZigZagElliotInfoLayout::getPriceValueRightOffset(), 46, "", ANCHOR_RIGHT_UPPER);
        
        
        objectName = "Low";
        text = todayRate.lowLabel;
        
        this.updateInfoLabel(10, "LowTitle", clrLightPink, fontSize, "L:", 0, 76);
        this.updateInfoLabel(5, objectName, clrLightPink, fontSize, text,
            DrawZigZagElliotInfoLayout::getPriceValueRightOffset(), 76, "", ANCHOR_RIGHT_UPPER);
        
        
        objectName = "Diff";
        text = todayRate.diffLabel;
        
        this.updateInfoLabel(11, "DiffTitle", clrKhaki, fontSize, "D:",
            DrawZigZagElliotInfoLayout::getSecondaryTitleLeftOffset(), 46);
        this.updateInfoLabel(6, objectName, clrKhaki, fontSize, text,
            DrawZigZagElliotInfoLayout::getSecondaryValueLeftOffset(), 46);
        
        if (todayRate.diffJpy > 0) {
            this.diffJpyLabelCleared = false;
            objectName = "DiffJpy";
            text = todayRate.diffJpyLabel;
            
            this.updateInfoLabel(12, "DiffJpyTitle", fontColor, fontSize - 5, "D Jpy:",
                DrawZigZagElliotInfoLayout::getSecondaryTitleLeftOffset(), 76);
            this.updateInfoLabel(7, objectName, fontColor, fontSize - 5, text,
                DrawZigZagElliotInfoLayout::getJpyValueLeftOffset(), 76);
        } else if (!this.diffJpyLabelCleared) {
            this.infoLabelReady[7] = false;
            this.infoLabelTexts[7] = "";
            this.infoLabelReady[12] = false;
            this.infoLabelTexts[12] = "";
            objectName = this.getInfoLabelObjectName("DiffJpy");
            bool valueCleared = ObjectFind(0, objectName) < 0;
            if (!valueCleared) {
                valueCleared = ObjectDelete(0, objectName);
            }

            objectName = this.getInfoLabelObjectName("DiffJpyTitle");
            bool titleCleared = ObjectFind(0, objectName) < 0;
            if (!titleCleared) {
                titleCleared = ObjectDelete(0, objectName);
            }

            this.diffJpyLabelCleared = valueCleared && titleCleared;
        }
    }

    /**
     * 時計・銘柄名・当日高安の情報ラベルと反映履歴を初期化する。
     * 再初期化時と終了時に、専用の固定接頭辞のオブジェクトだけを削除する。
     */
    void clearInfoLabels() {
        ObjectsDeleteAll(0, Constant::PREFIX_FIXED + "ZigZagElliotInfo", 0, -1);

        for (int i = 0; i < 19; i++) {
            this.infoLabelReady[i] = false;
            this.infoLabelTexts[i] = "";
            this.infoLabelTooltips[i] = "";
        }

        this.diffJpyLabelCleared = false;
        this.symbolLabelName = "";
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
    bool bidAskLabelReady[6];

    /** レートラベル6件の存在を定期確認した最後の単調増加時刻。単位: ミリ秒。 */
    ulong lastBidAskLabelCheckTick;

    /** Ask・Bid・Spreadラベルへ最後に反映した文字。 */
    string bidAskLabelTexts[6];

    /** Ask・Bid・Spreadラベルへ最後に反映した色。 */
    color bidAskLabelColors[6];

    /** 時計6個・銘柄5個・当日レート8個の固定設定・文字反映が成功した場合true。 */
    bool infoLabelReady[19];

    /** 情報ラベルへ最後に反映した文字。 */
    string infoLabelTexts[19];

    /** 情報ラベルへ最後に反映した説明文。 */
    string infoLabelTooltips[19];

    /** チャート右端から共通情報欄までの余白。 */
    int infoRightDistance;

    /** 非表示の円換算値幅ラベルが存在しない、または削除要求が成功した場合true。 */
    bool diffJpyLabelCleared;

    /** 通貨別の文字列・色・位置を確定した銘柄名。 */
    string symbolLabelName;

    /** 銘柄名とGMO対象の目印を説明するツールチップ。 */
    string symbolLabelTooltip;

    /** 銘柄の接頭辞・基軸通貨・決済通貨・GMO目印を含む接尾辞。 */
    string symbolLabelTexts[4];

    /** 銘柄名の各部分に対応する表示色。 */
    color symbolLabelColors[4];

    /** 銘柄名の各部分を描く情報欄左端からの距離。 */
    int symbolLabelOffsets[4];

    /**
     * 銘柄名を通貨固有色で分け、GMO対象には末尾へ金色の[G]を付ける。
     * 文字幅と通貨情報は銘柄変更時だけ取得し、取得失敗時は再試行する。
     */
    void drawSymbolName() {
        string symbolName = this.elliotAll.marketContext.symbolName;
        if (this.symbolLabelName != symbolName) {
            this.prepareSymbolLabelLayout(symbolName);
            this.infoLabelReady[3] = false;
            for (int i = 16; i < 19; i++) {
                this.infoLabelReady[i] = false;
            }
        }

        for (int i = 0; i < 4; i++) {
            int cacheIndex = 3;
            string objectName = "TodayRateSymbol";
            if (i > 0) {
                cacheIndex = 15 + i;
                objectName += IntegerToString(i);
            }

            // 空文字ではMT5の既定文字が出るため、空の部分には空白を設定する。
            string text = this.symbolLabelTexts[i];
            if (text == "") {
                text = " ";
            }

            this.updateInfoLabel(cacheIndex, objectName, this.symbolLabelColors[i], 30,
                text, this.symbolLabelOffsets[i], 0, this.symbolLabelTooltip);
        }
    }

    /**
     * GMO対象判定と銘柄名の通貨部分・各文字の開始位置を保持する。
     * 分割できない銘柄は元の名前を金色で表示する。
     *
     * @param fromSymbolName 接頭辞・接尾辞を含む元の銘柄名。
     */
    void prepareSymbolLabelLayout(const string fromSymbolName) {
        this.symbolLabelName = "";
        for (int i = 0; i < 4; i++) {
            this.symbolLabelTexts[i] = "";
            this.symbolLabelColors[i] = clrGold;
            this.symbolLabelOffsets[i] = 0;
        }

        SymbolNameInfoAll symbolNameInfoAll;
        symbolNameInfoAll.setGmo();
        string gmoSuffix = "";
        this.symbolLabelTooltip = fromSymbolName;
        if (symbolNameInfoAll.isUniqueTarget(fromSymbolName)) {
            gmoSuffix = " [G]";
            this.symbolLabelTooltip += "\n[G]: GMO対象通貨ペア（メールと共通の登録一覧）";
        }

        string displaySymbolName = fromSymbolName + gmoSuffix;
        this.symbolLabelTexts[0] = displaySymbolName;
        string baseCurrency = "";
        string quoteCurrency = "";
        if (!SymbolInfoString(fromSymbolName, SYMBOL_CURRENCY_BASE, baseCurrency)
                || !SymbolInfoString(fromSymbolName, SYMBOL_CURRENCY_PROFIT, quoteCurrency)) {
            return;
        }

        StringToUpper(baseCurrency);
        StringToUpper(quoteCurrency);
        if (baseCurrency == "" || quoteCurrency == "") {
            return;
        }

        string normalizedSymbol = fromSymbolName;
        StringToUpper(normalizedSymbol);
        int pairPosition = StringFind(normalizedSymbol, baseCurrency + quoteCurrency);
        if (pairPosition < 0) {
            this.symbolLabelName = fromSymbolName;

            return;
        }

        int positions[4];
        positions[0] = 0;
        positions[1] = pairPosition;
        positions[2] = positions[1] + StringLen(baseCurrency);
        positions[3] = positions[2] + StringLen(quoteCurrency);
        int offsets[4] = {0, 0, 0, 0};
        if (!TextSetFont(this.drawProperties.elliotFontFace, -300)) {
            return;
        }

        for (int i = 1; i < 4; i++) {
            if (positions[i] == 0) {
                continue;
            }

            uint textWidth = 0;
            uint textHeight = 0;
            if (!TextGetSize(StringSubstr(displaySymbolName, 0, positions[i]), textWidth, textHeight)
                    || textWidth == 0) {
                return;
            }

            offsets[i] = (int)textWidth;
        }

        for (int i = 0; i < 3; i++) {
            this.symbolLabelTexts[i] = "";
            if (positions[i + 1] > positions[i]) {
                this.symbolLabelTexts[i] = StringSubstr(displaySymbolName, positions[i], positions[i + 1] - positions[i]);
            }

            this.symbolLabelOffsets[i] = offsets[i];
        }

        if (positions[3] < StringLen(displaySymbolName)) {
            this.symbolLabelTexts[3] = StringSubstr(displaySymbolName, positions[3]);
        }

        this.symbolLabelOffsets[3] = offsets[3];
        this.symbolLabelColors[1] = ConstantCurrency::getColor(baseCurrency);
        this.symbolLabelColors[2] = ConstantCurrency::getColor(quoteCurrency);
        this.symbolLabelName = fromSymbolName;
    }

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
     * 情報ラベルを再利用し、表示文字と説明文をそれぞれ変更時だけ更新する。
     * 各ラベルの色・フォント・サイズ・座標は固定し、初回と再試行時だけ反映する。
     * 手動削除時は再作成し、設定に失敗した場合は次回に全属性を再試行する。
     *
     * @param fromIndex 時計・銘柄・当日レートの項目名と値に対応するキャッシュ番号
     * @param fromObjectName 接頭辞を除いたラベル名
     * @param fromColor 文字色
     * @param fromFontSize 文字サイズ
     * @param fromText 表示文字
     * @param fromX 情報欄左端からのX位置
     * @param fromY Y座標
     * @param fromTooltip 説明文。空文字の場合は標準の説明を使用する。
     * @param fromAnchor 左揃え・右揃えの基準点
     */
    void updateInfoLabel(
        int fromIndex,
        string fromObjectName,
        color fromColor,
        int fromFontSize,
        string fromText,
        int fromX,
        int fromY,
        string fromTooltip = "",
        ENUM_ANCHOR_POINT fromAnchor = ANCHOR_LEFT_UPPER
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
            if (!ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_RIGHT_UPPER)
                    || !ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, fromAnchor)
                    || !ObjectSetInteger(0, objectName, OBJPROP_COLOR, fromColor)
                    || !ObjectSetString(0, objectName, OBJPROP_FONT, this.drawProperties.elliotFontFace)
                    || !ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, fromFontSize)
                    || !ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE,
                        DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance, fromX))
                    || !ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, fromY)) {
                return;
            }
        }

        if (initializeProperties || this.infoLabelTexts[fromIndex] != fromText) {
            if (!ObjectSetString(0, objectName, OBJPROP_TEXT, fromText)) {
                return;
            }
        }

        if ((initializeProperties && fromTooltip != "") || this.infoLabelTooltips[fromIndex] != fromTooltip) {
            if (!ObjectSetString(0, objectName, OBJPROP_TOOLTIP, fromTooltip)) {
                return;
            }
        }

        this.infoLabelTexts[fromIndex] = fromText;
        this.infoLabelTooltips[fromIndex] = fromTooltip;
        this.infoLabelReady[fromIndex] = true;
    }

    /**
     * レートラベルを再利用し、表示文字と色をそれぞれ変更時だけ更新する。
     *
     * 全体再描画時は即座に、手動削除時は次回の定期確認で固定設定ごと復元する。
     * 設定に失敗した場合はキャッシュを確定せず、次回描画で再試行する。
     *
     * @param fromIndex Ask・Bid・Spreadの値0～2・項目名3～5に対応するキャッシュ番号
     * @param fromObjectName 共通接頭辞を除いたラベル名
     * @param fromText 表示文字
     * @param fromX 情報欄左端からのX位置
     * @param fromY Y座標
     * @param fromColor 表示色
     * @param fromCheckExistence 定期的な存在確認を行う場合true。
     * @param fromAnchor 左揃え・右揃えの基準点
     */
    void updateBidAskLabel(
        int fromIndex,
        string fromObjectName,
        string fromText,
        int fromX,
        int fromY,
        color fromColor,
        bool fromCheckExistence,
        ENUM_ANCHOR_POINT fromAnchor = ANCHOR_LEFT_UPPER
    ) {
        string objectName = Constant::PREFIX + fromObjectName;

        if ((!this.bidAskLabelReady[fromIndex] || fromCheckExistence)
                && ObjectFind(0, objectName) < 0) {
            this.bidAskLabelReady[fromIndex] = false;

            if (!ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0)) {
                return;
            }
        }

        bool initializeProperties = !this.bidAskLabelReady[fromIndex];
        this.bidAskLabelReady[fromIndex] = false;
        if (initializeProperties) {
            if (!ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_RIGHT_UPPER)
                    || !ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, fromAnchor)
                    || !ObjectSetString(0, objectName, OBJPROP_FONT, this.drawProperties.elliotFontFace)
                    || !ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 20)
                    || !ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE,
                        DrawZigZagElliotInfoLayout::getXDistance(this.infoRightDistance, fromX))
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


