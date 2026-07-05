/**
 * Package: MstngEa.Trade
 * File: TradeRequestBuilder.mqh
 */

#ifndef MSTNGEA_TRADE_TRADEREQUESTBUILDER_MQH
#define MSTNGEA_TRADE_TRADEREQUESTBUILDER_MQH

#include <Mstng\Common\MarketContext.mqh>

/**
 * 発注要求生成
 */
class TradeRequestBuilder {
public:
    /**
     * 発注要求初期化
     *
     * @param requestValue 発注要求
     * @param symbolNameValue シンボル名
     * @param magicNumberValue マジックナンバー
     * @param volumeValue 数量
     */
    static void buildMarketRequest(
        MqlTradeRequest &requestValue,
        string symbolNameValue,
        ulong magicNumberValue,
        double volumeValue
    ) {
        // 要求を初期化
        ZeroMemory(requestValue);
        requestValue.action = TRADE_ACTION_DEAL;
        requestValue.symbol = symbolNameValue;
        requestValue.magic = magicNumberValue;
        requestValue.volume = volumeValue;
        requestValue.deviation = 10;
        requestValue.type_filling = ORDER_FILLING_FOK;
    }

    /**
     * Build market request.
     *
     * @param requestValue Trade request
     * @param fromMarketContext Market context
     * @param fromMagicNumber Magic number
     * @param fromVolume Volume
     */
    static void buildMarketRequest(
        MqlTradeRequest &requestValue,
        MarketContext &fromMarketContext,
        ulong fromMagicNumber,
        double fromVolume
    ) {
        TradeRequestBuilder::buildMarketRequest(
            requestValue,
            fromMarketContext.symbolName,
            fromMagicNumber,
            fromVolume
        );
    }
};

#endif
