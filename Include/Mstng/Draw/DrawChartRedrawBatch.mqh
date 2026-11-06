//+------------------------------------------------------------------+
//|                                         DrawChartRedrawBatch.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_DRAW_CHART_REDRAW_BATCH_MQH
#define MSTNG_DRAW_CHART_REDRAW_BATCH_MQH

/**
 * 同一チャートの再描画要求を処理単位でまとめる。
 * スコープを抜ける際に反映するため、早期returnでも要求を失わない。
 */
class DrawChartRedrawBatch {
public:
    /**
     * 対象チャートの再描画要求を保留する。同じチャートでの入れ子にも対応する。
     *
     * @param fromChartId 対象チャートID。0の場合はカレント。
     */
    DrawChartRedrawBatch(const long fromChartId = 0) {
        long resolvedChartId = DrawChartRedrawBatch::resolveChartId(fromChartId);
        this.joinedBatch = false;
        if (DrawChartRedrawBatch::batchDepth == 0) {
            DrawChartRedrawBatch::batchChartId = resolvedChartId;
            DrawChartRedrawBatch::redrawPending = false;
        }

        if (DrawChartRedrawBatch::batchChartId == resolvedChartId) {
            DrawChartRedrawBatch::batchDepth++;
            this.joinedBatch = true;
        }
    }

    /**
     * 早期returnを含むスコープ終了時に、保留中の再描画を反映する。
     */
    ~DrawChartRedrawBatch() {
        this.finish();
    }

    /**
     * 自身の保留を終了し、最も外側の処理が終了した場合だけ再描画する。
     * DB保存などの後続処理より前に反映する場合にも使用できる。
     */
    void finish() {
        if (!this.joinedBatch) {
            return;
        }

        this.joinedBatch = false;
        DrawChartRedrawBatch::batchDepth--;
        if (DrawChartRedrawBatch::batchDepth == 0) {
            bool mustRedraw = DrawChartRedrawBatch::redrawPending;
            long chartId = DrawChartRedrawBatch::batchChartId;
            DrawChartRedrawBatch::redrawPending = false;
            DrawChartRedrawBatch::batchChartId = -1;
            if (mustRedraw) {
                ChartRedraw(chartId);
            }
        }
    }

    /**
     * 対象チャートを再描画する。対象チャートの保留中だけ要求をまとめる。
     *
     * @param fromChartId 対象チャートID。0の場合はカレント。
     */
    static void request(const long fromChartId = 0) {
        long resolvedChartId = DrawChartRedrawBatch::resolveChartId(fromChartId);
        if (DrawChartRedrawBatch::batchDepth > 0
                && DrawChartRedrawBatch::batchChartId == resolvedChartId) {
            DrawChartRedrawBatch::redrawPending = true;

            return;
        }

        ChartRedraw(resolvedChartId);
    }

private:
    /** 自身が同一チャートの保留に参加している場合true。 */
    bool joinedBatch;

    /** 保留対象のチャートID。 */
    static long batchChartId;

    /** 同一チャートに対する保留の深さ。 */
    static int batchDepth;

    /** 保留中に再描画を要求された場合true。 */
    static bool redrawPending;

    /**
     * カレントチャート指定を実際のチャートIDへ変換する。
     *
     * @param fromChartId 指定されたチャートID。
     * @return 実際のチャートID。
     */
    static long resolveChartId(const long fromChartId) {
        if (fromChartId == 0) {
            return ChartID();
        }

        return fromChartId;
    }
};

long DrawChartRedrawBatch::batchChartId = -1;
int DrawChartRedrawBatch::batchDepth = 0;
bool DrawChartRedrawBatch::redrawPending = false;

#endif // MSTNG_DRAW_CHART_REDRAW_BATCH_MQH
