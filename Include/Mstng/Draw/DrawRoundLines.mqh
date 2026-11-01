//+------------------------------------------------------------------+
//|                                               DrawRoundLines.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Util\RateUtil.mqh>

/**
 * 現在価格を基準に50pips間隔および100pips間隔の水平線を描画するクラス。
 * 同じ価格区間の線を保持し、全体描画では消去しない。
 */
class DrawRoundLines {
public:
    /**
     * シンボル名を指定して初期化する。
     *
     * @param fromSymbolName 描画対象のシンボル名
     */
    DrawRoundLines(string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);
        this.initialize(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    DrawRoundLines(MarketContext &fromMarketContext) {
        this.initialize(fromMarketContext);
    }

    /**
     * 保持するラウンドナンバー線を解放する。
     */
    ~DrawRoundLines() {
        this.clear();
    }

    /**
     * 描画対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * 現在価格の上下へラウンドナンバーラインを描画する。
     * 同じ区間・銘柄・桁数・ポイント値では、削除された線だけを復元する。
     */
    void draw() {
        double basePrice = this.getBasePrice();
        double point = this.marketContext.getPoint();
        double stepPrice50Pips = RateUtil::pipsToPrice(STEP_50_PIPS, this.marketContext);
        if (!MathIsValidNumber(basePrice) || basePrice <= 0
                || !MathIsValidNumber(point) || point <= 0
                || !MathIsValidNumber(stepPrice50Pips) || stepPrice50Pips <= 0) {
            this.clear();

            return;
        }

        double anchorPrice = this.getAnchorPrice(basePrice, stepPrice50Pips);
        bool rebuild = !this.linesReady
            || this.lastAnchorPrice != anchorPrice
            || this.lastSymbolName != this.marketContext.symbolName
            || this.lastDigits != this.getDigits()
            || this.lastPoint != point;
        if (rebuild && !this.clear()) {
            return;
        }

        bool succeeded = true;
        for (int i = -this.linesEachSide; i <= this.linesEachSide; i++) {
            int lineIndex = i + this.linesEachSide;
            if (!rebuild && ObjectFind(this.chartId, this.lineObjectNames[lineIndex]) == 0) {
                continue;
            }

            double linePrice = NormalizeDouble(anchorPrice + (stepPrice50Pips * i), this.getDigits());
            bool is100PipsLine = this.is100PipsLine(linePrice);
            this.lineObjectNames[lineIndex] = this.createObjectName(linePrice, is100PipsLine);
            if (!this.drawHorizontalLine(linePrice, is100PipsLine, this.lineObjectNames[lineIndex])) {
                succeeded = false;
            }
        }

        // 属性設定に失敗した線が存在していても、次回は全体を再試行する。
        this.linesReady = succeeded;
        if (succeeded) {
            this.lastAnchorPrice = anchorPrice;
            this.lastSymbolName = this.marketContext.symbolName;
            this.lastDigits = this.getDigits();
            this.lastPoint = point;
        }
    }

    /**
     * 所有する線を削除し、価格区間の保持状態を無効にする。
     *
     * @return 削除処理に成功した場合true。
     */
    bool clear() {
        this.linesReady = false;
        ResetLastError();
        int deletedCount = ObjectsDeleteAll(this.chartId,
            Constant::PREFIX_FIXED + "ZigZagElliotRound", 0, -1);

        return deletedCount >= 0 && GetLastError() == ERR_SUCCESS;
    }

private:
    /** 水平線の太さ。 */
    static const int LINE_WIDTH;

    /** 50pipsラインの間隔。 */
    static const int STEP_50_PIPS;

    /** 100pipsラインの間隔。 */
    static const int STEP_100_PIPS;
    
    /** 描画対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** 100pipsラインの色。 */
    color color100Pips;

    /** 50pipsラインの色。 */
    color color50Pips;

    /** 現在価格の上下へ描画する本数。 */
    int linesEachSide;

    /** 基準価格にBidを使用する場合true。 */
    bool useBidPrice;

    /** 描画対象のチャートID。 */
    long chartId;

    /** 11本すべての作成・設定に成功し、価格区間を再利用できる場合true。 */
    bool linesReady;

    /** 前回の線の基準価格。 */
    double lastAnchorPrice;

    /** 前回の描画対象銘柄。 */
    string lastSymbolName;

    /** 前回の小数桁数。 */
    int lastDigits;

    /** 前回の1ポイントの価格。 */
    double lastPoint;

    /** 価格の低い順に保持する11本のオブジェクト名。 */
    string lineObjectNames[11];

    /**
     * 描画設定を初期化する。
     *
     * @param fromSymbolName 描画対象のシンボル名
     */
    void initialize(string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);
        this.initialize(context);
    }

    /**
     * 市場コンテキストと描画設定を初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void initialize(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
        this.color100Pips = clrGold;
        this.color50Pips = clrGold;
        this.linesEachSide = 5;
        this.useBidPrice = true;
        this.chartId = 0;
        this.linesReady = false;
        this.lastAnchorPrice = 0;
        this.lastSymbolName = "";
        this.lastDigits = -1;
        this.lastPoint = 0;
    }

    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
    }
   
    /**
     * 水平線計算の基準価格を取得する。
     *
     * @return BidまたはAsk
     */
    double getBasePrice() {
        return useBidPrice
            ? SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_BID)
            : SymbolInfoDouble(this.marketContext.symbolName, SYMBOL_ASK);
    }

    /**
     * 描画対象シンボルの小数桁数を取得する。
     *
     * @return 小数桁数
     */
    int getDigits() {
        return this.marketContext.digits;
    }

    /**
     * 基準価格以下で最も近いライン価格を取得する。
     *
     * @param basePrice 基準価格
     * @param stepPrice ライン間隔の価格幅
     * @return アンカー価格
     */
    double getAnchorPrice(double basePrice, double stepPrice) {
        return MathFloor(basePrice / stepPrice) * stepPrice;
    }

    /**
     * 指定価格が100pipsラインに該当するか判定する。
     *
     * @param price 判定対象価格
     * @return 100pipsラインの場合true
     */
    bool is100PipsLine(double price) {
        double stepPrice100Pips = RateUtil::pipsToPrice(STEP_100_PIPS, this.marketContext);
        double ratio = price / stepPrice100Pips;
        
        return MathAbs(ratio - MathRound(ratio)) < 0.0000001;
    }

    /**
     * 指定価格へ水平線を描画する。
     *
     * @param fromPrice 描画価格
     * @param fromIs100PipsLine 100pipsラインの場合true
     * @param fromObjectName 専用接頭辞を付けたオブジェクト名
     * @return 作成と固定属性の設定に成功した場合true
     */
    bool drawHorizontalLine(double fromPrice, bool fromIs100PipsLine, string fromObjectName) {
        color lineColor = this.color50Pips;
        ENUM_LINE_STYLE lineStyle = STYLE_DOT;
        if (fromIs100PipsLine) {
            lineColor = this.color100Pips;
            lineStyle = STYLE_SOLID;
        }

        if (!ObjectCreate(this.chartId, fromObjectName, OBJ_HLINE, 0, 0, fromPrice)) {
            return false;
        }

        return ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_COLOR, lineColor)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STYLE, lineStyle)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_WIDTH, LINE_WIDTH)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BACK, false);
    }

    /**
     * 水平線のオブジェクト名を生成する。
     *
     * @param price 描画価格
     * @param is100PipsLine 100pipsラインの場合true
     * @return オブジェクト名
     */
    string createObjectName(double price, bool is100PipsLine) {
        string prefix = "ROUND_050_";
        if (is100PipsLine) {
            prefix = "ROUND_100_";
        }

        return Constant::PREFIX_FIXED + "ZigZagElliotRound"
            + prefix + IntegerToString((int)MathRound(price / this.marketContext.getPoint()));
    }
};

const int DrawRoundLines::LINE_WIDTH = 1;
const int DrawRoundLines::STEP_50_PIPS = 50;
const int DrawRoundLines::STEP_100_PIPS = 100;
