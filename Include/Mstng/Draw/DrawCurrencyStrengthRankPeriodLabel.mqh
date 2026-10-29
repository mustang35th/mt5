//+------------------------------------------------------------------+
//|                          DrawCurrencyStrengthRankPeriodLabel.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_PERIOD_LABEL_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_PERIOD_LABEL_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>

/**
 * 通貨強弱順位の選択期間をサブパネル右上へ描画する。
 */
class DrawCurrencyStrengthRankPeriodLabel {
public:
    /**
     * 描画対象チャートとオブジェクト識別子を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix オブジェクト名を一意にする接尾辞。
     * @param fromRedrawRequest 再描画要求の集約先。NULLの場合は従来どおり再描画する。
     */
    DrawCurrencyStrengthRankPeriodLabel(
        const long fromChartId,
        const string fromObjectSuffix,
        ChartRedrawRequest *fromRedrawRequest = NULL
    ) {
        this.chartId = fromChartId;
        this.redrawRequest = fromRedrawRequest;
        this.objectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthRankPeriod_"
            + fromObjectSuffix;
        this.lastSubWindow = -1;
        this.lastText = "";
    }

    /**
     * デストラクタ。
     */
    ~DrawCurrencyStrengthRankPeriodLabel() {
        this.clear();
    }

    /**
     * 指定サブウィンドウの右上へ期間名を描画する。
     * ラベルが存在し、前回設定した表示先と文字列が同じ場合は設定と再描画を省く。
     * 固定座標と表示設定は初期化時に行い、更新時は文字・色だけを反映する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromText 表示する期間名。
     * @return 描画または変更なしの確認に成功した場合true。
     */
    bool draw(const int fromSubWindow, const string fromText) {
        if (fromSubWindow <= 0 || fromText == "") {
            return false;
        }

        int objectWindow = ObjectFind(this.chartId, this.objectName);

        if (objectWindow == fromSubWindow
                && this.lastSubWindow == fromSubWindow
                && this.lastText == fromText) {
            return true;
        }

        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        bool initializeProperties = objectWindow != fromSubWindow || this.lastSubWindow < 0;
        this.lastSubWindow = -1;
        this.lastText = "";

        if (objectWindow >= 0 && objectWindow != fromSubWindow) {
            if (!ObjectDelete(this.chartId, this.objectName)) {
                return false;
            }

            objectWindow = -1;
        }

        if (objectWindow < 0
                && !ObjectCreate(
            this.chartId,
            this.objectName,
            OBJ_LABEL,
            fromSubWindow,
            0,
            0
        )) {
            return false;
        }

        if (initializeProperties && !this.configureObject()) {
            return false;
        }

        bool configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_COLOR,
            clrWhiteSmoke
        );
        configured = ObjectSetString(
            this.chartId,
            this.objectName,
            OBJPROP_TEXT,
            fromText
        ) && configured;

        if (!configured) {
            return false;
        }

        this.lastSubWindow = fromSubWindow;
        this.lastText = fromText;

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }

        return true;
    }

    /**
     * 期間名ラベルを削除する。
     */
    void clear() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        ObjectDelete(this.chartId, this.objectName);
        this.lastSubWindow = -1;
        this.lastText = "";
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 呼び出し元が所有する再描画要求の集約先。 */
    ChartRedrawRequest *redrawRequest;

    /** 期間名ラベルのオブジェクト名。 */
    string objectName;

    /** 前回設定が完了したサブウィンドウ番号。 */
    int lastSubWindow;

    /** 前回設定が完了した文字列。 */
    string lastText;

    /**
     * 期間名ラベルの固定座標と表示設定を初期化時・設定失敗後の再試行時に適用する。
     *
     * @return すべての設定に成功した場合true。
     */
    bool configureObject() {
        bool configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_CORNER,
            CORNER_RIGHT_UPPER
        );
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_ANCHOR,
            ANCHOR_RIGHT_UPPER
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_XDISTANCE,
            48
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_YDISTANCE,
            8
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_FONTSIZE,
            10
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_SELECTABLE,
            false
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_SELECTED,
            false
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_HIDDEN,
            true
        ) && configured;
        configured = ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_ZORDER,
            2
        ) && configured;
        configured = ObjectSetString(
            this.chartId,
            this.objectName,
            OBJPROP_FONT,
            "MS Gothic"
        ) && configured;

        return configured;
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_PERIOD_LABEL_MQH
