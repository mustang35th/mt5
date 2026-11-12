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
 * 現在価格を基準に、時間足別の主要・補助ラウンドナンバー線を描画するクラス。
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
     * 現在価格の上下へ最大11本のラウンドナンバーラインを描画する。
     * 同じ区間・銘柄・桁数・ポイント値・線間隔では、削除された線だけを復元する。
     */
    void draw() {
        int minorStepPips = 0;
        int majorStepPips = 0;
        if (!this.getLineSteps(minorStepPips, majorStepPips)) {
            this.clear();

            return;
        }

        double basePrice = this.getBasePrice();
        double point = this.marketContext.getPoint();
        double minorStepPrice = RateUtil::pipsToPrice(minorStepPips, this.marketContext);
        double majorStepPrice = RateUtil::pipsToPrice(majorStepPips, this.marketContext);
        if (!MathIsValidNumber(basePrice) || basePrice <= 0
                || !MathIsValidNumber(point) || point <= 0
                || !MathIsValidNumber(minorStepPrice) || minorStepPrice <= 0
                || !MathIsValidNumber(majorStepPrice) || majorStepPrice <= 0) {
            this.clear();

            return;
        }

        double anchorPrice = this.getAnchorPrice(basePrice, minorStepPrice, point);
        bool rebuild = !this.linesReady
            || this.lastAnchorPrice != anchorPrice
            || this.lastSymbolName != this.marketContext.symbolName
            || this.lastDigits != this.getDigits()
            || this.lastPoint != point
            || this.lastMinorStepPips != minorStepPips
            || this.lastMajorStepPips != majorStepPips;
        if (rebuild && !this.clear()) {
            return;
        }

        bool succeeded = true;
        for (int i = -this.linesEachSide; i <= this.linesEachSide; i++) {
            int lineIndex = i + this.linesEachSide;
            if (!rebuild && (this.lineObjectNames[lineIndex] == ""
                    || ObjectFind(this.chartId, this.lineObjectNames[lineIndex]) == 0)) {
                continue;
            }

            double linePrice = NormalizeDouble(anchorPrice + (minorStepPrice * i), this.getDigits());
            if (linePrice <= 0) {
                this.lineObjectNames[lineIndex] = "";

                continue;
            }

            bool isMajorLine = this.isMajorLine(linePrice, majorStepPrice);
            this.lineObjectNames[lineIndex] = this.createObjectName(linePrice, isMajorLine);
            if (!this.drawHorizontalLine(linePrice, isMajorLine, this.lineObjectNames[lineIndex])) {
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
            this.lastMinorStepPips = minorStepPips;
            this.lastMajorStepPips = majorStepPips;
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

    /** 描画対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** 主要線の色。 */
    color majorLineColor;

    /** 補助線の色。 */
    color minorLineColor;

    /** 現在価格の上下へ描画する本数。 */
    int linesEachSide;

    /** 基準価格にBidを使用する場合true。 */
    bool useBidPrice;

    /** 描画対象のチャートID。 */
    long chartId;

    /** 正の価格となる最大11本の作成・設定に成功し、価格区間を再利用できる場合true。 */
    bool linesReady;

    /** 前回の線の基準価格。 */
    double lastAnchorPrice;

    /** 前回の描画対象銘柄。 */
    string lastSymbolName;

    /** 前回の小数桁数。 */
    int lastDigits;

    /** 前回の1ポイントの価格。 */
    double lastPoint;

    /** 前回の補助線間隔。単位: pips。 */
    int lastMinorStepPips;

    /** 前回の主要線間隔。単位: pips。 */
    int lastMajorStepPips;

    /** 価格の低い順に保持する11本のオブジェクト名。0以下の価格は空文字。 */
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
        this.majorLineColor = clrGold;
        this.minorLineColor = clrDarkGoldenrod;
        this.linesEachSide = 5;
        this.useBidPrice = true;
        this.chartId = 0;
        this.linesReady = false;
        this.lastAnchorPrice = 0;
        this.lastSymbolName = "";
        this.lastDigits = -1;
        this.lastPoint = 0;
        this.lastMinorStepPips = 0;
        this.lastMajorStepPips = 0;
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
     * 時間足に対応する補助線・主要線の間隔を取得する。
     * その他のH1以下は従来の50／100pips、未対応の上位足は非表示とする。
     *
     * @param fromMinorStepPips 補助線間隔の出力先。単位: pips。
     * @param fromMajorStepPips 主要線間隔の出力先。単位: pips。
     * @return 描画対象の時間足の場合true。
     */
    bool getLineSteps(int &fromMinorStepPips, int &fromMajorStepPips) {
        ENUM_TIMEFRAMES timeFrame = this.marketContext.timeFrame;
        if (timeFrame == PERIOD_CURRENT) {
            timeFrame = (ENUM_TIMEFRAMES)Period();
        }

        fromMinorStepPips = 50;
        fromMajorStepPips = 100;
        switch (timeFrame) {
            case PERIOD_M1:
                fromMinorStepPips = 10;
                fromMajorStepPips = 50;
                return true;
            case PERIOD_M5:
                fromMinorStepPips = 25;
                return true;
            case PERIOD_H4:
                fromMinorStepPips = 100;
                fromMajorStepPips = 500;
                return true;
            case PERIOD_D1:
                fromMinorStepPips = 500;
                fromMajorStepPips = 1000;
                return true;
            case PERIOD_W1:
            case PERIOD_MN1:
                fromMinorStepPips = 1000;
                fromMajorStepPips = 5000;
                return true;
        }

        return timeFrame > PERIOD_CURRENT && timeFrame <= PERIOD_H1;
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
     * ポイント単位の整数へ丸め、キリ番ちょうどの価格が小数誤差で1段下がるのを防ぐ。
     *
     * @param fromBasePrice 基準価格。
     * @param fromStepPrice ライン間隔の価格幅。
     * @param fromPoint 1ポイントの価格幅。
     * @return アンカー価格。
     */
    double getAnchorPrice(double fromBasePrice, double fromStepPrice, double fromPoint) {
        double basePoints = MathRound(fromBasePrice / fromPoint);
        double stepPoints = MathRound(fromStepPrice / fromPoint);
        double anchorPoints = MathFloor(basePoints / stepPoints) * stepPoints;

        return NormalizeDouble(anchorPoints * fromPoint, this.getDigits());
    }

    /**
     * 指定価格が主要線の間隔の整数倍か判定する。
     *
     * @param fromPrice 判定対象価格。
     * @param fromMajorStepPrice 主要線間隔の価格幅。
     * @return 主要線の場合true。
     */
    bool isMajorLine(double fromPrice, double fromMajorStepPrice) {
        double ratio = fromPrice / fromMajorStepPrice;
        
        return MathAbs(ratio - MathRound(ratio)) < 0.0000001;
    }

    /**
     * 指定価格へ水平線を描画する。
     *
     * @param fromPrice 描画価格
     * @param fromIsMajorLine 主要線の場合true
     * @param fromObjectName 専用接頭辞を付けたオブジェクト名
     * @return 作成と固定属性の設定に成功した場合true
     */
    bool drawHorizontalLine(double fromPrice, bool fromIsMajorLine, string fromObjectName) {
        color lineColor = this.minorLineColor;
        ENUM_LINE_STYLE lineStyle = STYLE_DOT;
        if (fromIsMajorLine) {
            lineColor = this.majorLineColor;
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
     * @param fromIsMajorLine 主要線の場合true
     * @return オブジェクト名
     */
    string createObjectName(double price, bool fromIsMajorLine) {
        string prefix = "ROUND_MINOR_";
        if (fromIsMajorLine) {
            prefix = "ROUND_MAJOR_";
        }

        return Constant::PREFIX_FIXED + "ZigZagElliotRound"
            + prefix + IntegerToString((int)MathRound(price / this.marketContext.getPoint()));
    }
};

const int DrawRoundLines::LINE_WIDTH = 1;
