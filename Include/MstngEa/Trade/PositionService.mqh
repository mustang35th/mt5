/**
 * Package: MstngEa.Trade
 * File: PositionService.mqh
 */

#ifndef MSTNGEA_TRADE_POSITIONSERVICE_MQH
#define MSTNGEA_TRADE_POSITIONSERVICE_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <MstngEa\Domain\PositionSnapshot.mqh>

/**
 * 自EAポジション取得
 */
class PositionService {
public:
    /** Market context */
    MarketContext marketContext;

    /** シンボル名 */
    string symbolName;

    /** マジックナンバー */
    ulong magicNumber;

    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param magicNumberValue マジックナンバー
     */
    PositionService(string symbolNameValue, ulong magicNumberValue) {
        // 基本情報を保持
        MarketContext context(symbolNameValue, PERIOD_CURRENT);
        this.initialize(context, magicNumberValue);
    }

    /**
     * Constructor
     *
     * @param fromMarketContext Market context
     * @param fromMagicNumber Magic number
     */
    PositionService(MarketContext &fromMarketContext, ulong fromMagicNumber) {
        this.initialize(fromMarketContext, fromMagicNumber);
    }

    /**
     * 状態更新
     */
    void refresh() {
        // スナップショットを初期化
        this.positionSnapshot = PositionSnapshot();

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

            // 現在ポジションを反映
            this.positionSnapshot.hasPosition = true;
            this.positionSnapshot.ticket = currentTicket;
            this.positionSnapshot.volume = PositionGetDouble(POSITION_VOLUME);
            this.positionSnapshot.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            this.positionSnapshot.stopLoss = PositionGetDouble(POSITION_SL);
            this.positionSnapshot.floatingProfit = PositionGetDouble(POSITION_PROFIT);

            long positionType = PositionGetInteger(POSITION_TYPE);
            this.positionSnapshot.isBuy = positionType == POSITION_TYPE_BUY;

            return;
        }
    }

    /**
     * ポジション有無
     *
     * @return true: ポジションあり
     */
    bool hasPosition() {
        return this.positionSnapshot.hasPosition;
    }

    /**
     * 買いポジション判定
     *
     * @return true: 買い
     */
    bool isBuyPosition() {
        return this.positionSnapshot.isBuy;
    }

    /**
     * スナップショット取得
     *
     * @return ポジション状態
     */
    PositionSnapshot getSnapshot() {
        return this.positionSnapshot;
    }

private:
    /**
     * Initialize by market context.
     *
     * @param fromMarketContext Market context
     * @param fromMagicNumber Magic number
     */
    void initialize(MarketContext &fromMarketContext, ulong fromMagicNumber) {
        this.marketContext = fromMarketContext;
        this.symbolName = fromMarketContext.symbolName;
        this.magicNumber = fromMagicNumber;
        this.refresh();
    }

    /** ポジション状態 */
    PositionSnapshot positionSnapshot;
};

#endif
