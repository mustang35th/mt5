//+------------------------------------------------------------------+
//|                                                     DrawGmma.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_GMMA_MQH
#define MSTNG_DRAW_GMMA_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\DrawUtil.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\GmmaUtil.mqh>

/**
 * GMMAの長期線の間を矩形で塗り分ける描画クラス。
 *
 * EMA30とEMA60の位置関係、差分増減、またはトレンド判定に応じて色を決める。
 * 値の取得は呼び出し元で行い、本クラスは描画のみに責務を限定する。
 */
class DrawGmma : public CObject {
public:
    /** 描画対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** 上昇時の塗り色。 */
    color upColor;

    /** 下降時の塗り色。 */
    color downColor;

    /** 描画対象の最大バー数。 */
    int maxBars;

    /**
     * シンボル、時間足および描画設定を指定して初期化する。
     *
     * @param fromSymbolName 描画対象シンボル
     * @param fromTimeFrame 描画対象時間足
     * @param fromObjectPrefix 描画オブジェクト名プレフィックス
     * @param fromUpColor 上昇時の塗り色
     * @param fromDownColor 下降時の塗り色
     * @param fromMaxBars 描画対象の最大バー数
     */
    DrawGmma(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        string fromObjectPrefix = "GmmaRect_",
        color fromUpColor = clrLightBlue,
        color fromDownColor = clrLightPink,
        int fromMaxBars = 500
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromObjectPrefix, fromUpColor, fromDownColor, fromMaxBars);
    }

    /**
     * 市場コンテキストと描画設定を指定して初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     * @param fromObjectPrefix 描画オブジェクト名プレフィックス
     * @param fromUpColor 上昇時の塗り色
     * @param fromDownColor 下降時の塗り色
     * @param fromMaxBars 描画対象の最大バー数
     */
    DrawGmma(
        MarketContext &fromMarketContext,
        string fromObjectPrefix = "GmmaRect_",
        color fromUpColor = clrLightBlue,
        color fromDownColor = clrLightPink,
        int fromMaxBars = 500
    ) {
        this.initialize(fromMarketContext, fromObjectPrefix, fromUpColor, fromDownColor, fromMaxBars);
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
     * 描画済みのGMMA矩形オブジェクトを全削除する。
     *
     * @param chartId 描画対象チャートID
     */
    void clear(long chartId = 0) {
        string prefix = this.objectPrefix;

        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "start. chartId=%I64d, prefix=%s",
                chartId,
                prefix
            )
        );

        int deletedCount = ObjectsDeleteAll(chartId, prefix);

        this.logger.debug(
            __FUNCTION__,
            StringFormat("end. deletedCount=%d", deletedCount)
        );
    }

    /**
     * GMMA長期線の間を矩形で描画する。
     *
     * @param ema30Buffer EMA30バッファ
     * @param ema60Buffer EMA60バッファ
     * @param rates_total 総バー数
     * @param prev_calculated 前回計算済みバー数
     * @param chartId 描画対象チャートID
     */
    void drawLongTerm(
        const double &ema30Buffer[],
        const double &ema60Buffer[],
        const int rates_total,
        const int prev_calculated,
        long chartId = 0
    ) {
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "start. rates_total=%d, prev_calculated=%d, maxBars=%d, chartId=%I64d",
                rates_total,
                prev_calculated,
                this.maxBars,
                chartId
            )
        );

        if (rates_total < 2) {
            this.logger.warn(
                __FUNCTION__,
                StringFormat("rates_total is too small. rates_total=%d", rates_total)
            );

            return;
        }

        int start = MathMax(0, rates_total - this.maxBars);

        if (prev_calculated > 0) {
            start = MathMax(start, prev_calculated - 1);
        }

        int drawCount = 0;
        int emptySkipCount = 0;

        for (int i = start; i < rates_total - 1; i++) {
            double ema30 = ema30Buffer[i];
            double ema60 = ema60Buffer[i];

            if (ema30 == EMPTY_VALUE || ema60 == EMPTY_VALUE) {
                emptySkipCount++;
                continue;
            }

            this.logger.debug(
                __FUNCTION__,
                StringFormat("i=%d, ema30=%f, ema60=%f", i, ema30, ema60)
            );

            int timeIndex = rates_total - i - 2;
            this.logger.debug(__FUNCTION__, StringFormat("timeIndex = %d", timeIndex));

            datetime time = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, timeIndex);
            datetime timeBefore = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, timeIndex + 1);

            string name = this.objectPrefix + IntegerToString((int)time);

            double topRate = MathMax(ema30, ema60);
            double bottomRate = MathMin(ema30, ema60);

            color rectColor;

            if (ema30 > ema60) {
                rectColor = this.upColor;
            } else {
                rectColor = this.downColor;
            }

            DrawUtil::setRectangle(
                name,
                timeBefore,
                topRate,
                time,
                bottomRate,
                rectColor,
                STYLE_SOLID,
                1,
                false,
                (int)chartId
            );

            string objectName = Constant::PREFIX + name;
            ObjectSetInteger(chartId, objectName, OBJPROP_BACK, true);
            ObjectSetInteger(chartId, objectName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(chartId, objectName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, 0);

            drawCount++;
        }

        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "end. start=%d, drawCount=%d, emptySkipCount=%d",
                start,
                drawCount,
                emptySkipCount
            )
        );
    }

    /**
     * GMMA長期線の差分増減に応じて、長期線の間を矩形で描画する。
     *
     * 差分はEMA30 - EMA60で算出し、1本前の足と現在足の差分を比較して色を決定する。
     *
     * @param ema30Buffer EMA30バッファ
     * @param ema60Buffer EMA60バッファ
     * @param rates_total 総バー数
     * @param prev_calculated 前回計算済みバー数
     * @param chartId 描画対象チャートID
     */
    void drawLongTermDiff(
        const double &ema30Buffer[],
        const double &ema60Buffer[],
        const int rates_total,
        const int prev_calculated,
        long chartId = 0
    ) {
        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "start. rates_total=%d, prev_calculated=%d, maxBars=%d, chartId=%I64d",
                rates_total,
                prev_calculated,
                this.maxBars,
                chartId
            )
        );

        if (rates_total < 3) {
            this.logger.warn(
                __FUNCTION__,
                StringFormat("rates_total is too small. rates_total=%d", rates_total)
            );

            return;
        }

        int start = MathMax(1, rates_total - this.maxBars);

        if (prev_calculated > 0) {
            start = MathMax(start, prev_calculated - 1);
        }

        int drawCount = 0;
        int emptySkipCount = 0;

        for (int i = start; i < rates_total - 1; i++) {
            double currentEma30 = ema30Buffer[i];
            double currentEma60 = ema60Buffer[i];
            double previousEma30 = ema30Buffer[i - 1];
            double previousEma60 = ema60Buffer[i - 1];

            if (currentEma30 == EMPTY_VALUE || currentEma60 == EMPTY_VALUE) {
                emptySkipCount++;
                continue;
            }

            if (previousEma30 == EMPTY_VALUE || previousEma60 == EMPTY_VALUE) {
                emptySkipCount++;
                continue;
            }

            double currentDiff = currentEma30 - currentEma60;
            double previousDiff = previousEma30 - previousEma60;

            this.logger.debug(
                __FUNCTION__,
                StringFormat(
                    "i=%d, currentEma30=%f, currentEma60=%f, previousEma30=%f, previousEma60=%f, currentDiff=%f, previousDiff=%f",
                    i,
                    currentEma30,
                    currentEma60,
                    previousEma30,
                    previousEma60,
                    currentDiff,
                    previousDiff
                )
            );

            int timeIndex = rates_total - i - 2;
            this.logger.debug(__FUNCTION__, StringFormat("timeIndex = %d", timeIndex));

            datetime time = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, timeIndex);
            datetime timeBefore = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, timeIndex + 1);

            string name = this.objectPrefix + "Diff_" + IntegerToString((int)time);

            double topRate = MathMax(currentEma30, currentEma60);
            double bottomRate = MathMin(currentEma30, currentEma60);

            color rectColor = clrWhite;

            if (previousDiff < currentDiff) {
                rectColor = this.upColor;
            } else {
                if (previousDiff > currentDiff) {
                    rectColor = this.downColor;
                }
            }

            DrawUtil::setRectangle(
                name,
                timeBefore,
                topRate,
                time,
                bottomRate,
                rectColor,
                STYLE_SOLID,
                1,
                false,
                (int)chartId
            );

            string objectName = Constant::PREFIX + name;
            ObjectSetInteger(chartId, objectName, OBJPROP_BACK, true);
            ObjectSetInteger(chartId, objectName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(chartId, objectName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, 0);

            drawCount++;
        }

        this.logger.debug(
            __FUNCTION__,
            StringFormat(
                "end. start=%d, drawCount=%d, emptySkipCount=%d",
                start,
                drawCount,
                emptySkipCount
            )
        );
    }


    /**
     * GMMA長期線のトレンド方向に応じて、長期線の間を矩形で描画する。
     *
     * GmmaUtil::getGmmaTrendの戻り値から色を決定する。
     *
     * @param ema30Buffer EMA30バッファ
     * @param ema60Buffer EMA60バッファ
     * @param rates_total 総バー数
     * @param prev_calculated 前回計算済みバー数
     * @param chartId 描画対象チャートID
     * @param fromExpectedBarTime EMA取得前の最新足時刻。0の場合は照合を省略する
     * @return 時刻取得と追加属性の設定要求に成功した場合true。描画対象なしもtrue
     */
    bool drawLongTermTrend(
        const double &ema30Buffer[],
        const double &ema60Buffer[],
        const int rates_total,
        const int prev_calculated,
        long chartId = 0,
        datetime fromExpectedBarTime = 0
    ) {
        bool isDebugOutputEnabled = this.logger.isDebugOutputEnabled();

        if (isDebugOutputEnabled) {
            this.logger.debug(
                __FUNCTION__,
                StringFormat(
                    "start. rates_total=%d, prev_calculated=%d, maxBars=%d, chartId=%I64d",
                    rates_total,
                    prev_calculated,
                    this.maxBars,
                    chartId
                )
            );
        }

        if (rates_total < 3) {
            this.logger.warn(
                __FUNCTION__,
                StringFormat("rates_total is too small. rates_total=%d", rates_total)
            );

            return true;
        }

        int start = MathMax(1, rates_total - this.maxBars);

        if (prev_calculated > 0) {
            start = MathMax(start, prev_calculated - 1);
        }

        // 描画区間の両端に必要な実際の足時刻を、今回の更新分だけ取得する。
        datetime barTimes[];
        int timeCount = rates_total - start;

        if (timeCount > 1) {
            ArraySetAsSeries(barTimes, true);

            if (CopyTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0, timeCount, barTimes) != timeCount) {
                return false;
            }

            if (fromExpectedBarTime > 0 && barTimes[0] != fromExpectedBarTime) {
                return false;
            }

            for (int i = 0; i < timeCount; i++) {
                if (barTimes[i] <= 0 || (i > 0 && barTimes[i] >= barTimes[i - 1])) {
                    return false;
                }
            }

            // EMAと矩形の時刻がずれないよう、描画を始める前に足切り替わりを確認する。
            if (iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0) != barTimes[0]) {
                return false;
            }
        }

        int drawCount = 0;
        int emptySkipCount = 0;

        for (int i = start; i < rates_total - 1; i++) {
            double currentEma30 = ema30Buffer[i];
            double currentEma60 = ema60Buffer[i];
            double previousEma30 = ema30Buffer[i - 1];
            double previousEma60 = ema60Buffer[i - 1];

            if (currentEma30 == EMPTY_VALUE || currentEma60 == EMPTY_VALUE) {
                if (isDebugOutputEnabled) {
                    emptySkipCount++;
                }
                continue;
            }

            if (previousEma30 == EMPTY_VALUE || previousEma60 == EMPTY_VALUE) {
                if (isDebugOutputEnabled) {
                    emptySkipCount++;
                }
                continue;
            }

            ENUM_GMMA_TREND trend = GmmaUtil::getGmmaTrend(
                previousEma30,
                currentEma30,
                previousEma60,
                currentEma60
            );

            if (isDebugOutputEnabled) {
                this.logger.debug(
                    __FUNCTION__,
                    StringFormat(
                        "i=%d, previousEma30=%f, currentEma30=%f, previousEma60=%f, currentEma60=%f, trend=%d",
                        i,
                        previousEma30,
                        currentEma30,
                        previousEma60,
                        currentEma60,
                        (int)trend
                    )
                );
            }

            int timeIndex = rates_total - i - 2;
            if (isDebugOutputEnabled) {
                this.logger.debug(__FUNCTION__, StringFormat("timeIndex = %d", timeIndex));
            }

            datetime time = barTimes[timeIndex];
            datetime timeBefore = barTimes[timeIndex + 1];

            string name = this.objectPrefix + "Trend_" + IntegerToString((int)time);

            double topRate = MathMax(currentEma30, currentEma60);
            double bottomRate = MathMin(currentEma30, currentEma60);

            color rectColor = clrWhite;

            if (trend == GMMA_TREND_BUY) {
                rectColor = this.upColor;
            } else {
                if (trend == GMMA_TREND_SELL) {
                    rectColor = this.downColor;
                }
            }

            DrawUtil::setRectangle(
                name,
                timeBefore,
                topRate,
                time,
                bottomRate,
                rectColor,
                STYLE_SOLID,
                1,
                false,
                (int)chartId
            );

            // 共通描画で設定済みの背面・塗り・線幅は再設定せず、実際の作成名を使う。
            if (!ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(chartId, name, OBJPROP_HIDDEN, true)) {
                return false;
            }

            if (isDebugOutputEnabled) {
                drawCount++;
            }
        }

        if (isDebugOutputEnabled) {
            this.logger.debug(
                __FUNCTION__,
                StringFormat(
                    "end. start=%d, drawCount=%d, emptySkipCount=%d",
                    start,
                    drawCount,
                    emptySkipCount
                )
            );
        }

        return true;
    }

private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /**
     * 市場コンテキストと描画設定を初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     * @param fromObjectPrefix 描画オブジェクト名プレフィックス
     * @param fromUpColor 上昇時の塗り色
     * @param fromDownColor 下降時の塗り色
     * @param fromMaxBars 描画対象の最大バー数
     */
    void initialize(
        MarketContext &fromMarketContext,
        string fromObjectPrefix,
        color fromUpColor,
        color fromDownColor,
        int fromMaxBars
    ) {
        this.initializeMarketContext(fromMarketContext);

        this.objectPrefix = fromObjectPrefix;
        this.upColor = fromUpColor;
        this.downColor = fromDownColor;
        this.maxBars = fromMaxBars;

        if (this.logger.isDebugOutputEnabled()) {
            this.logger.debug(
                __FUNCTION__,
                StringFormat(
                    "initialized. objectPrefix=%s, upColor=%d, downColor=%d, maxBars=%d",
                    this.objectPrefix,
                    (int)this.upColor,
                    (int)this.downColor,
                    this.maxBars
                )
            );
        }
    }

    /**
     * 市場コンテキストとロガーを初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
    }
};

#endif // MSTNG_DRAW_GMMA_MQH
