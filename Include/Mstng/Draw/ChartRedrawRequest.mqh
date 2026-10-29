//+------------------------------------------------------------------+
//|                                           ChartRedrawRequest.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CHART_REDRAW_REQUEST_MQH
#define MSTNG_DRAW_CHART_REDRAW_REQUEST_MQH

/**
 * 複数の描画処理による再描画要求を、イベント終了時の1回にまとめる。
 */
class ChartRedrawRequest {
public:
    /**
     * 再描画要求がない状態で初期化する。
     */
    ChartRedrawRequest() {
        this.pending = false;
    }

    /**
     * 表示の更新または削除に伴う再描画要求を記録する。
     */
    void request() {
        this.pending = true;
    }

    /**
     * 記録した要求がある場合だけ、まとめて1回再描画を要求する。
     *
     * @param fromChartId 再描画対象チャートID。
     */
    void flush(const long fromChartId) {
        if (!this.pending) {
            return;
        }

        this.pending = false;
        ChartRedraw(fromChartId);
    }

private:
    /** まだ反映していない再描画要求がある場合true。 */
    bool pending;
};

#endif // MSTNG_DRAW_CHART_REDRAW_REQUEST_MQH
