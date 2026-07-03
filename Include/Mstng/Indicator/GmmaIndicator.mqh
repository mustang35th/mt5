//+------------------------------------------------------------------+
//|                                                GmmaIndicator.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_GMMA_INDICATOR_MQH
#define MSTNG_GMMA_INDICATOR_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Draw\DrawGmma.mqh>

/**
 * GMMA表示用インジケータクラス
 */
class GmmaIndicator {
public:
    /** 表示対象の市場コンテキスト */
    MarketContext marketContext;

    /**
     * コンストラクタ
     *
     * @param fromSymbolName 通貨ペア
     * @param fromTimeFrame 時間足
     */
    GmmaIndicator(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    GmmaIndicator(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * デストラクタ
     */
    ~GmmaIndicator() {
        this.deinit();
    }

    /**
     * 表示対象の市場コンテキストを設定する。
     *
     * 設定後はinit()を呼び出してハンドルと描画処理を再初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.deinit();
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * 初期化
     *
     * @param oscillatorHandlePool オシレーターハンドルプール
     */
    void init(OscillatorHandlePool *oscillatorHandlePool) {
        SetIndexBuffer(0, buffer30, INDICATOR_DATA);
        SetIndexBuffer(1, buffer60, INDICATOR_DATA);

        GmmaHandlePool *gmmaHandlePool = oscillatorHandlePool.getGmmaHandlePool();

        gmmaHandlePool.setParameters(this.ema30, this.ema60, MODE_EMA, PRICE_CLOSE);

        this.handle30 = gmmaHandlePool.getEma30Handle(this.marketContext.timeFrame);
        this.handle60 = gmmaHandlePool.getEma60Handle(this.marketContext.timeFrame);

        this.drawGmma = new DrawGmma(
            this.marketContext,
            "GmmaLongRect_",
            this.upColor,
            this.downColor,
            this.maxBars
        );
    }

    /**
     * 終了処理
     */
    void deinit() {
        if (this.drawGmma != NULL) {
            this.drawGmma.clear();
            delete this.drawGmma;
            this.drawGmma = NULL;
        }
    }

    /**
     * 更新
     *
     * @return 更新成否
     */
    bool update() {
        datetime temptime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);

        if (this.lasttimeGmma == temptime) {
            return true;
        }

        int barsCount = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);

        if (CopyBuffer(this.handle30, 0, 0, barsCount, buffer30) <= 0) {
            return false;
        }

        if (CopyBuffer(this.handle60, 0, 0, barsCount, buffer60) <= 0) {
            return false;
        }

        this.updateLineColors();

        if (this.drawGmma != NULL) {
            //this.drawGmma.drawLongTerm(buffer30, buffer60, barsCount, 0);
            //this.drawGmma.drawLongTermDiff(buffer30, buffer60, barsCount, 0);
            this.drawGmma.drawLongTermTrend(buffer30, buffer60, barsCount, 0);
        }

        this.lasttimeGmma = temptime;

        return true;
    }

private:
    /** 30期間EMAハンドル。 */
    int ema30;
    /** 60期間EMAハンドル。 */
    int ema60;
    /** 描画対象の最大バー数。 */
    int maxBars;
    /** 上昇色。 */
    color upColor;
    /** 下降色。 */
    color downColor;
    /** 線分上昇色。 */
    color lineUpColor;
    /** 線分下降色。 */
    color lineDownColor;
    /** 30期間EMAのデータバッファ。 */
    double buffer30[];
    /** 60期間EMAのデータバッファ。 */
    double buffer60[];
    /** 30期間EMAハンドル。 */
    int handle30;
    /** 60期間EMAハンドル。 */
    int handle60;
    /** 描画クラス。 */
    DrawGmma *drawGmma;
    /** 最終更新日時。 */
    datetime lasttimeGmma;

    /**
     * 市場コンテキストと表示設定を初期化する。
     *
     * @param fromMarketContext 表示対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.ema30 = 30;
        this.ema60 = 60;
        this.maxBars = 500;
        this.upColor = clrLightBlue;
        this.downColor = clrLightPink;
        this.lineUpColor = clrDodgerBlue;
        this.lineDownColor = clrMagenta;
        this.handle30 = INVALID_HANDLE;
        this.handle60 = INVALID_HANDLE;
        this.drawGmma = NULL;
        this.lasttimeGmma = 0;
    }

    /**
     * ライン色更新
     */
    void updateLineColors() {
        if (ArraySize(buffer30) < 2 || ArraySize(buffer60) < 2) {
            return;
        }

        int arraySize = ArraySize(buffer30);
        int index = arraySize - 1;

        double buffer30Value = buffer30[index];
        double buffer60Value = buffer60[index];
        color lineColor;

        if (buffer30Value > buffer60Value) {
            lineColor = this.lineUpColor;
        } else {
            lineColor = this.lineDownColor;
        }

        PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, lineColor);
        PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, lineColor);
    }
};

#endif




