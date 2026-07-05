/**
 * Package: MstngEa.Trade
 * File: TradeExecutor.mqh
 */

#ifndef MSTNGEA_TRADE_TRADEEXECUTOR_MQH
#define MSTNGEA_TRADE_TRADEEXECUTOR_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <MstngEa\Logging\OperationLogger.mqh>
#include <MstngEa\Logging\TradeCsvLogger.mqh>
#include <MstngEa\Logging\CloseTradeCsvLogger.mqh>
#include <MstngEa\Presentation\CloseProfitTextView.mqh>
#include <MstngEa\Trade\TradeRequestBuilder.mqh>

/**
 * 売買実行
 */
class TradeExecutor {
public:
    /** Market context */
    MarketContext marketContext;

    /** シンボル名 */
    string symbolName;

    /** マジックナンバー */
    ulong magicNumber;

    /** 数量 */
    double lotSize;

    /** 運用ログ */
    OperationLogger *operationLogger;

    /** 取引CSVログ */
    TradeCsvLogger *tradeCsvLogger;

    /** 決済専用CSVログ */
    CloseTradeCsvLogger *closeTradeCsvLogger;

    /** 決済損益表示 */
    CloseProfitTextView *closeProfitTextView;

    /** 最終リターンコード */
    uint lastRetcode;

    /** 最終エラーメッセージ */
    string lastErrorMessage;

    /** 最終約定チケット */
    ulong lastDealTicket;

    /** 最終注文チケット */
    ulong lastOrderTicket;

    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param magicNumberValue マジックナンバー
     * @param lotSizeValue 数量
     * @param operationLoggerValue 運用ログ
     * @param tradeCsvLoggerValue 取引CSVログ
     * @param closeTradeCsvLoggerValue 決済専用CSVログ
     * @param closeProfitTextViewValue 決済損益表示
     */
    TradeExecutor(
        string symbolNameValue,
        ulong magicNumberValue,
        double lotSizeValue,
        OperationLogger *operationLoggerValue,
        TradeCsvLogger *tradeCsvLoggerValue,
        CloseTradeCsvLogger *closeTradeCsvLoggerValue,
        CloseProfitTextView *closeProfitTextViewValue
    ) {
        // 依存を保持
        MarketContext context(symbolNameValue, PERIOD_CURRENT);
        this.initialize(
            context,
            magicNumberValue,
            lotSizeValue,
            operationLoggerValue,
            tradeCsvLoggerValue,
            closeTradeCsvLoggerValue,
            closeProfitTextViewValue
        );
    }

    /**
     * Constructor
     *
     * @param fromMarketContext Market context
     * @param fromMagicNumber Magic number
     * @param fromLotSize Lot size
     * @param fromOperationLogger Operation logger
     * @param fromTradeCsvLogger Trade CSV logger
     * @param fromCloseTradeCsvLogger Close trade CSV logger
     * @param fromCloseProfitTextView Close profit view
     */
    TradeExecutor(
        MarketContext &fromMarketContext,
        ulong fromMagicNumber,
        double fromLotSize,
        OperationLogger *fromOperationLogger,
        TradeCsvLogger *fromTradeCsvLogger,
        CloseTradeCsvLogger *fromCloseTradeCsvLogger,
        CloseProfitTextView *fromCloseProfitTextView
    ) {
        this.initialize(
            fromMarketContext,
            fromMagicNumber,
            fromLotSize,
            fromOperationLogger,
            fromTradeCsvLogger,
            fromCloseTradeCsvLogger,
            fromCloseProfitTextView
        );
    }

    /**
     * 買い発注
     *
     * @param strategyNameValue 戦略名
     * @param reasonValue 理由
     * @return true: 発注成功
     */
    bool openBuy(
        string strategyNameValue,
        string reasonValue,
        double stopLossValue,
        string csvTextValue
    ) {
        return this.openPosition(
            strategyNameValue,
            reasonValue,
            ORDER_TYPE_BUY,
            "BUY",
            stopLossValue,
            csvTextValue
        );
    }

    /**
     * 売り発注
     *
     * @param strategyNameValue 戦略名
     * @param reasonValue 理由
     * @return true: 発注成功
     */
    bool openSell(
        string strategyNameValue,
        string reasonValue,
        double stopLossValue,
        string csvTextValue
    ) {
        return this.openPosition(
            strategyNameValue,
            reasonValue,
            ORDER_TYPE_SELL,
            "SELL",
            stopLossValue,
            csvTextValue
        );
    }

    /**
     * 決済
     *
     * @param strategyNameValue 戦略名
     * @param reasonValue 理由
     * @return true: 決済成功
     */
    bool closePosition(string strategyNameValue, string reasonValue) {
        this.clearLastExecutionResult();

        ulong positionTicket = 0;
        double positionVolume = 0.0;
        long positionType = POSITION_TYPE_BUY;

        if (!this.selectOwnPosition(positionTicket, positionVolume, positionType)) {
            this.lastErrorMessage = "Target position not found";
            this.writeWarn(this.lastErrorMessage);

            return false;
        }

        double closeProfit = this.readPositionProfit(positionTicket);

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        // 決済注文を構築
        request.action = TRADE_ACTION_DEAL;
        request.symbol = this.marketContext.symbolName;
        request.magic = this.magicNumber;
        request.position = positionTicket;
        request.volume = this.normalizeVolume(positionVolume);
        request.deviation = 10;
        request.type_filling = this.resolveFillingType();
        request.comment = this.buildOrderComment(strategyNameValue);

        if (positionType == POSITION_TYPE_BUY) {
            request.type = ORDER_TYPE_SELL;
            request.price = this.getMarketPrice(ORDER_TYPE_SELL);
        } else {
            request.type = ORDER_TYPE_BUY;
            request.price = this.getMarketPrice(ORDER_TYPE_BUY);
        }

        if (request.price <= 0.0) {
            this.lastErrorMessage = "Close price not available";
            this.writeError(this.lastErrorMessage);

            return false;
        }

        ResetLastError();
        bool isSuccess = OrderSend(request, result);
        this.captureResult(result);

        if (!isSuccess) {
            this.lastErrorMessage = "OrderSend close failed. lastError="
                + IntegerToString(GetLastError());
            this.writeError(this.lastErrorMessage);

            return false;
        }

        if (!this.isSuccessRetcode(result.retcode)) {
            this.lastErrorMessage = "Close rejected. retcode=" + IntegerToString((int)result.retcode);
            this.writeError(this.lastErrorMessage);

            return false;
        }

        string sideLabel = "SELL";

        if (positionType == POSITION_TYPE_SELL) {
            sideLabel = "BUY";
        }

        string entryCsvText = this.tradeCsvLogger.loadPendingCsvText();

        this.tradeCsvLogger.writeTrade(
            strategyNameValue,
            "CLOSE",
            sideLabel,
            request.volume,
            result.price,
            positionTicket,
            result.deal,
            closeProfit,
            reasonValue,
            entryCsvText
        );

        if (this.closeTradeCsvLogger != NULL) {
            this.closeTradeCsvLogger.writeTrade(
                strategyNameValue,
                "CLOSE",
                sideLabel,
                request.volume,
                result.price,
                positionTicket,
                result.deal,
                closeProfit,
                reasonValue,
                entryCsvText
            );
        }

        this.tradeCsvLogger.clearPendingCsvText();

        this.drawCloseProfitByDeal(result.deal, closeProfit, result.price);

        this.writeInfo(
            "closePosition success. ticket="
            + (string)positionTicket
            + ", deal="
            + (string)result.deal
            + ", retcode="
            + IntegerToString((int)result.retcode)
        );

        return true;
    }



    /**
     * ストップロス変更
     *
     * @param strategyNameValue 戦略名
     * @param stopLossValue ストップロス価格
     * @param reasonValue 理由
     * @return true: 変更成功
     */
    bool modifyPositionStopLoss(
        string strategyNameValue,
        double stopLossValue,
        string reasonValue
    ) {
        this.clearLastExecutionResult();

        ulong positionTicket = 0;
        double positionVolume = 0.0;
        long positionType = POSITION_TYPE_BUY;

        if (!this.selectOwnPosition(positionTicket, positionVolume, positionType)) {
            this.lastErrorMessage = "Target position not found";
            this.writeWarn(this.lastErrorMessage);

            return false;
        }

        if (!PositionSelectByTicket(positionTicket)) {
            this.lastErrorMessage = "PositionSelectByTicket failed";
            this.writeError(this.lastErrorMessage);

            return false;
        }

        double marketPrice = 0.0;
        double currentTakeProfit = PositionGetDouble(POSITION_TP);
        ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;

        if (positionType == POSITION_TYPE_BUY) {
            marketPrice = this.getMarketPrice(ORDER_TYPE_SELL);
            orderType = ORDER_TYPE_BUY;
        } else {
            marketPrice = this.getMarketPrice(ORDER_TYPE_BUY);
            orderType = ORDER_TYPE_SELL;
        }

        if (marketPrice <= 0.0) {
            this.lastErrorMessage = "Modify stop loss market price not available";
            this.writeError(this.lastErrorMessage);

            return false;
        }

        double normalizedStopLoss = this.normalizePrice(stopLossValue);

        if (!this.isValidStopLoss(orderType, marketPrice, normalizedStopLoss)) {
            int digits = (int)SymbolInfoInteger(this.marketContext.symbolName, SYMBOL_DIGITS);

            this.lastErrorMessage = "Invalid break even stop loss. stopLoss="
                + DoubleToString(normalizedStopLoss, digits)
                + ", marketPrice="
                + DoubleToString(marketPrice, digits);
            this.writeError(this.lastErrorMessage);

            return false;
        }

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_SLTP;
        request.symbol = this.marketContext.symbolName;
        request.magic = this.magicNumber;
        request.position = positionTicket;
        request.sl = normalizedStopLoss;
        request.tp = currentTakeProfit;
        request.comment = this.buildOrderComment(strategyNameValue);

        ResetLastError();
        bool isSuccess = OrderSend(request, result);
        this.captureResult(result);

        if (!isSuccess) {
            this.lastErrorMessage = "OrderSend modify failed. lastError="
                + IntegerToString(GetLastError());
            this.writeError(this.lastErrorMessage);

            return false;
        }

        if (!this.isSuccessRetcode(result.retcode)) {
            this.lastErrorMessage = "Modify rejected. retcode=" + IntegerToString((int)result.retcode);
            this.writeError(this.lastErrorMessage);

            return false;
        }

        this.writeInfo(
            "modifyPositionStopLoss success. ticket="
            + (string)positionTicket
            + ", reason="
            + reasonValue
            + ", retcode="
            + IntegerToString((int)result.retcode)
        );

        return true;
    }

    /**
     * 取引トランザクション処理
     *
     * @param transValue トランザクション
     * @param requestValue 発注要求
     * @param resultValue 発注結果
     */
    void onTradeTransaction(
        const MqlTradeTransaction &transValue,
        const MqlTradeRequest &requestValue,
        const MqlTradeResult &resultValue
    ) {

        if (transValue.type != TRADE_TRANSACTION_DEAL_ADD) {
            return;
        }

        if (transValue.deal == 0) {
            return;
        }

        if (!HistoryDealSelect(transValue.deal)) {
            return;
        }

        string dealSymbolName = HistoryDealGetString(transValue.deal, DEAL_SYMBOL);
        long dealMagicNumber = HistoryDealGetInteger(transValue.deal, DEAL_MAGIC);
        long dealEntry = HistoryDealGetInteger(transValue.deal, DEAL_ENTRY);
        long dealReason = HistoryDealGetInteger(transValue.deal, DEAL_REASON);

        if (dealSymbolName != this.marketContext.symbolName) {
            return;
        }

        if ((ulong)dealMagicNumber != this.magicNumber) {
            return;
        }

        if (dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY) {
            return;
        }

        if (dealReason != DEAL_REASON_SL) {
            return;
        }

        string sideLabel = this.resolveDealSideLabel(transValue.deal);
        string strategyName = this.resolveStrategyNameFromComment(transValue.deal);
        double dealVolume = HistoryDealGetDouble(transValue.deal, DEAL_VOLUME);
        double dealPrice = HistoryDealGetDouble(transValue.deal, DEAL_PRICE);
        double dealProfit = HistoryDealGetDouble(transValue.deal, DEAL_PROFIT);
        ulong positionTicket = (ulong)HistoryDealGetInteger(transValue.deal, DEAL_POSITION_ID);
        string entryCsvText = this.tradeCsvLogger.loadPendingCsvText();

        this.tradeCsvLogger.writeTrade(
            strategyName,
            "CLOSE",
            sideLabel,
            dealVolume,
            dealPrice,
            positionTicket,
            transValue.deal,
            dealProfit,
            "STOP_LOSS",
            entryCsvText
        );

        if (this.closeTradeCsvLogger != NULL) {
            this.closeTradeCsvLogger.writeTrade(
                strategyName,
                "CLOSE",
                sideLabel,
                dealVolume,
                dealPrice,
                positionTicket,
                transValue.deal,
                dealProfit,
                "STOP_LOSS",
                entryCsvText
            );
        }

        this.tradeCsvLogger.clearPendingCsvText();

        this.drawCloseProfitByDeal(transValue.deal, dealProfit, dealPrice);

        this.writeInfo(
            "stop loss close detected. deal="
            + (string)transValue.deal
            + ", position="
            + (string)positionTicket
        );
    }

    /**
     * 決済損益描画
     *
     * @param dealTicketValue 約定チケット
     * @param profitValue 損益
     * @param fallbackPriceValue 代替価格
     */
    void drawCloseProfitByDeal(
        ulong dealTicketValue,
        double profitValue,
        double fallbackPriceValue
    ) {

        if (this.closeProfitTextView == NULL) {
            return;
        }

        datetime closeTime = TimeCurrent();
        double closePrice = fallbackPriceValue;

        if (dealTicketValue > 0 && HistoryDealSelect(dealTicketValue)) {
            closeTime = (datetime)HistoryDealGetInteger(dealTicketValue, DEAL_TIME);
            closePrice = HistoryDealGetDouble(dealTicketValue, DEAL_PRICE);
            profitValue = HistoryDealGetDouble(dealTicketValue, DEAL_PROFIT);
        }

        if (closeTime <= 0) {
            return;
        }

        if (closePrice <= 0.0) {
            return;
        }

        this.closeProfitTextView.draw(
            closeTime,
            closePrice,
            profitValue,
            dealTicketValue
        );
    }

    /**
     * 最終リターンコード取得
     *
     * @return 最終リターンコード
     */
    uint getLastRetcode() {
        return this.lastRetcode;
    }

    /**
     * 最終エラー取得
     *
     * @return 最終エラー
     */
    string getLastErrorMessage() {
        return this.lastErrorMessage;
    }

private:
    /**
     * Initialize by market context.
     *
     * @param fromMarketContext Market context
     * @param fromMagicNumber Magic number
     * @param fromLotSize Lot size
     * @param fromOperationLogger Operation logger
     * @param fromTradeCsvLogger Trade CSV logger
     * @param fromCloseTradeCsvLogger Close trade CSV logger
     * @param fromCloseProfitTextView Close profit view
     */
    void initialize(
        MarketContext &fromMarketContext,
        ulong fromMagicNumber,
        double fromLotSize,
        OperationLogger *fromOperationLogger,
        TradeCsvLogger *fromTradeCsvLogger,
        CloseTradeCsvLogger *fromCloseTradeCsvLogger,
        CloseProfitTextView *fromCloseProfitTextView
    ) {
        this.marketContext = fromMarketContext;
        this.symbolName = fromMarketContext.symbolName;
        this.magicNumber = fromMagicNumber;
        this.lotSize = fromLotSize;
        this.operationLogger = fromOperationLogger;
        this.tradeCsvLogger = fromTradeCsvLogger;
        this.closeTradeCsvLogger = fromCloseTradeCsvLogger;
        this.closeProfitTextView = fromCloseProfitTextView;
        this.lastRetcode = 0;
        this.lastErrorMessage = "";
        this.lastDealTicket = 0;
        this.lastOrderTicket = 0;
    }

    /**
     * 新規発注
     *
     * @param strategyNameValue 戦略名
     * @param reasonValue 理由
     * @param orderTypeValue 発注種別
     * @param sideLabelValue 売買方向
     * @param stopLossValue ストップロス価格
     * @return true: 発注成功
     */
    bool openPosition(
        string strategyNameValue,
        string reasonValue,
        ENUM_ORDER_TYPE orderTypeValue,
        string sideLabelValue,
        double stopLossValue,
        string csvTextValue
    ) {
        this.clearLastExecutionResult();

        if (!this.isTradeEnvironmentReady()) {
            return false;
        }

        double normalizedVolume = this.normalizeVolume(this.lotSize);

        if (normalizedVolume <= 0.0) {
            this.lastErrorMessage = "Invalid lot size";
            this.writeError(this.lastErrorMessage);

            return false;
        }

        double marketPrice = this.getMarketPrice(orderTypeValue);

        if (marketPrice <= 0.0) {
            this.lastErrorMessage = "Open price not available";
            this.writeError(this.lastErrorMessage);

            return false;
        }

        MqlTradeRequest request;
        MqlTradeResult result;
        TradeRequestBuilder::buildMarketRequest(
            request,
            this.marketContext,
            this.magicNumber,
            normalizedVolume
        );
        ZeroMemory(result);

        // 発注内容を設定
        request.type = orderTypeValue;
        request.price = marketPrice;
        request.type_filling = this.resolveFillingType();
        request.comment = this.buildOrderComment(strategyNameValue);

        if (!this.applyStopLoss(request, orderTypeValue, marketPrice, stopLossValue)) {
            return false;
        }

        ResetLastError();
        bool isSuccess = OrderSend(request, result);
        this.captureResult(result);

        if (!isSuccess) {
            this.lastErrorMessage = "OrderSend open failed. lastError="
                + IntegerToString(GetLastError());
            this.writeError(this.lastErrorMessage);

            return false;
        }

        if (!this.isSuccessRetcode(result.retcode)) {
            this.lastErrorMessage = "Open rejected. retcode=" + IntegerToString((int)result.retcode);
            this.writeError(this.lastErrorMessage);

            return false;
        }

        ulong positionTicket = result.order;
        double positionVolume = 0.0;
        long positionType = POSITION_TYPE_BUY;

        if (this.selectOwnPosition(positionTicket, positionVolume, positionType)) {
            // 自EAポジションチケットへ置換
        }

        this.tradeCsvLogger.savePendingCsvText(csvTextValue);
        this.tradeCsvLogger.writeTrade(
            strategyNameValue,
            "OPEN",
            sideLabelValue,
            normalizedVolume,
            result.price,
            positionTicket,
            result.deal,
            0.0,
            reasonValue,
            ""
        );

        this.writeInfo(
            "openPosition success. side="
            + sideLabelValue
            + ", order="
            + (string)result.order
            + ", deal="
            + (string)result.deal
            + ", retcode="
            + IntegerToString((int)result.retcode)
        );

        return true;
    }


    /**
     * ストップロス適用
     *
     * @param requestValue 発注要求
     * @param orderTypeValue 発注種別
     * @param marketPriceValue 現在価格
     * @param stopLossValue ストップロス価格
     * @return true: 適用成功
     */
    bool applyStopLoss(
        MqlTradeRequest &requestValue,
        ENUM_ORDER_TYPE orderTypeValue,
        double marketPriceValue,
        double stopLossValue
    ) {

        if (stopLossValue <= 0.0) {
            requestValue.sl = 0.0;
            return true;
        }

        double normalizedStopLoss = this.normalizePrice(stopLossValue);

        if (!this.isValidStopLoss(orderTypeValue, marketPriceValue, normalizedStopLoss)) {
            int digits = (int)SymbolInfoInteger(this.marketContext.symbolName, SYMBOL_DIGITS);

            this.lastErrorMessage = "Invalid stop loss. stopLoss="
                + DoubleToString(normalizedStopLoss, digits)
                + ", marketPrice="
                + DoubleToString(marketPriceValue, digits);
            this.writeError(this.lastErrorMessage);

            return false;
        }

        requestValue.sl = normalizedStopLoss;

        return true;
    }

    /**
     * ストップロス妥当性確認
     *
     * @param orderTypeValue 発注種別
     * @param marketPriceValue 現在価格
     * @param stopLossValue ストップロス価格
     * @return true: 妥当
     */
    bool isValidStopLoss(
        ENUM_ORDER_TYPE orderTypeValue,
        double marketPriceValue,
        double stopLossValue
    ) {
        long stopsLevelPoint = 0;
        double pointValue = 0.0;
        double minimumDistance = 0.0;

        SymbolInfoInteger(this.marketContext.symbolName, SYMBOL_TRADE_STOPS_LEVEL, stopsLevelPoint);
        SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_POINT, pointValue);

        if (pointValue > 0.0 && stopsLevelPoint > 0) {
            minimumDistance = stopsLevelPoint * pointValue;
        }

        if (orderTypeValue == ORDER_TYPE_BUY) {

            if (stopLossValue >= marketPriceValue) {
                return false;
            }

            if (minimumDistance > 0.0 && (marketPriceValue - stopLossValue) < minimumDistance) {
                return false;
            }

            return true;
        }

        if (stopLossValue <= marketPriceValue) {
            return false;
        }

        if (minimumDistance > 0.0 && (stopLossValue - marketPriceValue) < minimumDistance) {
            return false;
        }

        return true;
    }

    /**
     * 価格正規化
     *
     * @param priceValue 価格
     * @return 正規化価格
     */
    double normalizePrice(double priceValue) {
        int digits = (int)SymbolInfoInteger(this.marketContext.symbolName, SYMBOL_DIGITS);

        return NormalizeDouble(priceValue, digits);
    }


    /**
     * 約定売買方向取得
     *
     * @param dealTicketValue 約定チケット
     * @return 売買方向
     */
    string resolveDealSideLabel(ulong dealTicketValue) {
        long dealType = HistoryDealGetInteger(dealTicketValue, DEAL_TYPE);

        if (dealType == DEAL_TYPE_BUY) {
            return "BUY";
        }

        if (dealType == DEAL_TYPE_SELL) {
            return "SELL";
        }

        return "UNKNOWN";
    }

    /**
     * コメントから戦略名取得
     *
     * @param dealTicketValue 約定チケット
     * @return 戦略名
     */
    string resolveStrategyNameFromComment(ulong dealTicketValue) {
        string commentText = HistoryDealGetString(dealTicketValue, DEAL_COMMENT);
        string prefix = "MstngEa_";

        if (StringFind(commentText, prefix) == 0) {
            return StringSubstr(commentText, StringLen(prefix));
        }

        if (commentText == "") {
            return "UNKNOWN";
        }

        return commentText;
    }

    /**
     * 実行結果初期化
     */
    void clearLastExecutionResult() {
        // 最終実行結果を初期化
        this.lastRetcode = 0;
        this.lastErrorMessage = "";
        this.lastDealTicket = 0;
        this.lastOrderTicket = 0;
    }

    /**
     * 実行結果保持
     *
     * @param resultValue 売買結果
     */
    void captureResult(MqlTradeResult &resultValue) {
        // 最終実行結果を保持
        this.lastRetcode = resultValue.retcode;
        this.lastDealTicket = resultValue.deal;
        this.lastOrderTicket = resultValue.order;
    }

    /**
     * 取引環境確認
     *
     * @return true: 取引可能
     */
    bool isTradeEnvironmentReady() {
        long tradeMode = SYMBOL_TRADE_MODE_DISABLED;

        if (!SymbolInfoInteger(this.marketContext.symbolName, SYMBOL_TRADE_MODE, tradeMode)) {
            this.lastErrorMessage = "Failed to read SYMBOL_TRADE_MODE";
            this.writeError(this.lastErrorMessage);

            return false;
        }

        if (tradeMode == SYMBOL_TRADE_MODE_DISABLED) {
            this.lastErrorMessage = "Trade mode disabled";
            this.writeWarn(this.lastErrorMessage);

            return false;
        }

        if (!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
            this.lastErrorMessage = "MQL trade not allowed";
            this.writeWarn(this.lastErrorMessage);

            return false;
        }

        if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
            this.lastErrorMessage = "Terminal trade not allowed";
            this.writeWarn(this.lastErrorMessage);

            return false;
        }

        return true;
    }

    /**
     * 自EAポジション選択
     *
     * @param positionTicketValue チケット
     * @param positionVolumeValue 数量
     * @param positionTypeValue ポジション種別
     * @return true: 選択成功
     */
    bool selectOwnPosition(
        ulong &positionTicketValue,
        double &positionVolumeValue,
        long &positionTypeValue
    ) {
        int total = PositionsTotal();

        for (int i = 0; i < total; i++) {
            ulong currentTicket = PositionGetTicket(i);

            if (currentTicket == 0) {
                continue;
            }

            if (!PositionSelectByTicket(currentTicket)) {
                continue;
            }

            string currentSymbolName = PositionGetString(POSITION_SYMBOL);
            long currentMagicNumber = PositionGetInteger(POSITION_MAGIC);

            if (currentSymbolName != this.marketContext.symbolName) {
                continue;
            }

            if ((ulong)currentMagicNumber != this.magicNumber) {
                continue;
            }

            positionTicketValue = currentTicket;
            positionVolumeValue = PositionGetDouble(POSITION_VOLUME);
            positionTypeValue = PositionGetInteger(POSITION_TYPE);

            return true;
        }

        return false;
    }

    /**
     * 損益取得
     *
     * @param positionTicketValue ポジションチケット
     * @return 損益
     */
    double readPositionProfit(ulong positionTicketValue) {

        if (!PositionSelectByTicket(positionTicketValue)) {
            return 0.0;
        }

        return PositionGetDouble(POSITION_PROFIT);
    }

    /**
     * 発注コメント生成
     *
     * @param strategyNameValue 戦略名
     * @return コメント
     */
    string buildOrderComment(string strategyNameValue) {
        string commentText = "MstngEa_" + strategyNameValue;

        if (StringLen(commentText) > 31) {
            commentText = StringSubstr(commentText, 0, 31);
        }

        return commentText;
    }

    /**
     * 成功リターンコード判定
     *
     * @param retcodeValue リターンコード
     * @return true: 成功
     */
    bool isSuccessRetcode(uint retcodeValue) {

        if (retcodeValue == TRADE_RETCODE_DONE) {
            return true;
        }

        if (retcodeValue == TRADE_RETCODE_DONE_PARTIAL) {
            return true;
        }

        if (retcodeValue == TRADE_RETCODE_PLACED) {
            return true;
        }

        return false;
    }

    /**
     * 執行方式取得
     *
     * @return 執行方式
     */
    ENUM_ORDER_TYPE_FILLING resolveFillingType() {
        long fillingMode = 0;

        if (!SymbolInfoInteger(this.marketContext.symbolName, SYMBOL_FILLING_MODE, fillingMode)) {
            return ORDER_FILLING_FOK;
        }

        if ((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
            return ORDER_FILLING_FOK;
        }

        if ((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
            return ORDER_FILLING_IOC;
        }

        return ORDER_FILLING_RETURN;
    }

    /**
     * 現在価格取得
     *
     * @param orderTypeValue 発注種別
     * @return 現在価格
     */
    double getMarketPrice(ENUM_ORDER_TYPE orderTypeValue) {
        MqlTick mqlTick;
        ZeroMemory(mqlTick);

        if (!SymbolInfoTick(this.marketContext.symbolName, mqlTick)) {
            return 0.0;
        }

        if (orderTypeValue == ORDER_TYPE_BUY) {
            return mqlTick.ask;
        }

        return mqlTick.bid;
    }

    /**
     * 数量正規化
     *
     * @param volumeValue 数量
     * @return 正規化数量
     */
    double normalizeVolume(double volumeValue) {
        double minVolume = 0.0;
        double maxVolume = 0.0;
        double volumeStep = 0.0;

        if (!SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_VOLUME_MIN, minVolume)) {
            return 0.0;
        }

        if (!SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_VOLUME_MAX, maxVolume)) {
            return 0.0;
        }

        if (!SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_VOLUME_STEP, volumeStep)) {
            return 0.0;
        }

        double normalizedVolume = volumeValue;

        if (normalizedVolume < minVolume) {
            normalizedVolume = minVolume;
        }

        if (normalizedVolume > maxVolume) {
            normalizedVolume = maxVolume;
        }

        if (volumeStep > 0.0) {
            normalizedVolume = MathFloor(normalizedVolume / volumeStep) * volumeStep;
        }

        int volumeDigits = this.getVolumeDigits(volumeStep);
        normalizedVolume = NormalizeDouble(normalizedVolume, volumeDigits);

        if (normalizedVolume < minVolume) {
            normalizedVolume = minVolume;
        }

        return normalizedVolume;
    }

    /**
     * 数量桁数取得
     *
     * @param volumeStepValue 数量ステップ
     * @return 桁数
     */
    int getVolumeDigits(double volumeStepValue) {
        int volumeDigits = 0;
        double currentStep = volumeStepValue;

        while (currentStep < 1.0 && volumeDigits < 8) {
            currentStep = currentStep * 10.0;
            volumeDigits++;
        }

        return volumeDigits;
    }

    /**
     * INFOログ出力
     *
     * @param messageValue メッセージ
     */
    void writeInfo(string messageValue) {

        if (this.operationLogger == NULL) {
            return;
        }

        // INFOログを出力
        this.operationLogger.info("TradeExecutor", messageValue);
    }

    /**
     * WARNログ出力
     *
     * @param messageValue メッセージ
     */
    void writeWarn(string messageValue) {

        if (this.operationLogger == NULL) {
            return;
        }

        // WARNログを出力
        this.operationLogger.warn("TradeExecutor", messageValue);
    }

    /**
     * ERRORログ出力
     *
     * @param messageValue メッセージ
     */
    void writeError(string messageValue) {

        if (this.operationLogger == NULL) {
            return;
        }

        // ERRORログを出力
        this.operationLogger.error("TradeExecutor", messageValue);
    }
};

#endif
