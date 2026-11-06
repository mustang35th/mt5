//+------------------------------------------------------------------+
//|                          DrawCurrencyStrengthRankSourceLabel.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_SOURCE_LABEL_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_SOURCE_LABEL_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>

/**
 * 最新通貨強弱順位の取得元をサブパネル右上へ描画する。
 */
class DrawCurrencyStrengthRankSourceLabel {
public:
    /**
     * 描画対象チャートとオブジェクト識別子を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix オブジェクト名を一意にする接尾辞。
     * @param fromRedrawRequest 再描画要求の集約先。NULLの場合は従来どおり再描画する。
     */
    DrawCurrencyStrengthRankSourceLabel(
        const long fromChartId,
        const string fromObjectSuffix,
        ChartRedrawRequest *fromRedrawRequest = NULL
    ) {
        this.chartId = fromChartId;
        this.redrawRequest = fromRedrawRequest;
        this.objectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthRankSource_"
            + fromObjectSuffix;
        this.created = false;
        this.lastSubWindow = -1;
        this.lastText = "";
        this.lastColor = clrNONE;
        this.lastTooltip = "";
        this.textReady = false;
        this.colorReady = false;
        this.tooltipReady = false;
    }

    /**
     * デストラクタ。
     */
    ~DrawCurrencyStrengthRankSourceLabel() {
        this.clear();
    }

    /**
     * 指定サブウィンドウの右上へ最新順位の取得元を描画する。
     * 固定座標は初期化時に設定し、文字・色・説明は成功値から変わった項目だけ反映する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromText 表示する取得元。
     * @param fromColor 文字色。
     * @param fromTooltip 取得状態の説明。空文字の場合は既定ツールチップを非表示にする。
     * @return 描画に成功した場合true。
     */
    bool draw(
        const int fromSubWindow,
        const string fromText,
        const color fromColor,
        const string fromTooltip = ""
    ) {
        if (fromSubWindow <= 0 || fromText == "") {
            return false;
        }

        string tooltip = fromTooltip;
        if (tooltip == "") {
            tooltip = "\n";
        }

        if (this.created && this.textReady && this.colorReady && this.tooltipReady
                && this.lastSubWindow == fromSubWindow
                && this.lastText == fromText
                && this.lastColor == fromColor
                && this.lastTooltip == tooltip) {
            return true;
        }

        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        int objectWindow = ObjectFind(this.chartId, this.objectName);
        bool initializeProperties = !this.created
            || this.lastSubWindow != fromSubWindow || objectWindow != fromSubWindow;
        if (initializeProperties) {
            this.created = false;
            this.textReady = false;
            this.colorReady = false;
            this.tooltipReady = false;
        }

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

        this.created = true;
        this.lastSubWindow = fromSubWindow;

        bool updated = true;
        if (!this.colorReady || this.lastColor != fromColor) {
            if (ObjectSetInteger(this.chartId, this.objectName, OBJPROP_COLOR, fromColor)) {
                this.lastColor = fromColor;
                this.colorReady = true;
            } else {
                updated = false;
            }
        }

        if (!this.textReady || this.lastText != fromText) {
            if (ObjectSetString(this.chartId, this.objectName, OBJPROP_TEXT, fromText)) {
                this.lastText = fromText;
                this.textReady = true;
            } else {
                updated = false;
            }
        }

        if (!this.tooltipReady || this.lastTooltip != tooltip) {
            if (ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP, tooltip)) {
                this.lastTooltip = tooltip;
                this.tooltipReady = true;
            } else {
                updated = false;
            }
        }

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }

        return updated;
    }

    /**
     * 最新順位取得元ラベルを削除する。
     */
    void clear() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        }

        ObjectDelete(this.chartId, this.objectName);
        this.created = false;
        this.lastSubWindow = -1;
        this.lastText = "";
        this.lastColor = clrNONE;
        this.lastTooltip = "";
        this.textReady = false;
        this.colorReady = false;
        this.tooltipReady = false;

        if (this.redrawRequest == NULL) {
            ChartRedraw(this.chartId);
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 呼び出し元が所有する再描画要求の集約先。 */
    ChartRedrawRequest *redrawRequest;

    /** 最新順位取得元ラベルのオブジェクト名。 */
    string objectName;

    /** ラベルの固定属性の設定が完了した場合true。 */
    bool created;

    /** 前回描画したサブウィンドウ番号。 */
    int lastSubWindow;

    /** 前回描画した文字列。 */
    string lastText;

    /** 前回描画した文字色。 */
    color lastColor;

    /** 前回設定に成功したツールチップ。空指定は改行へ正規化して保持する。 */
    string lastTooltip;

    /** 文字列を一度以上正常に設定できた場合true。 */
    bool textReady;

    /** 文字色を一度以上正常に設定できた場合true。 */
    bool colorReady;

    /** ツールチップを一度以上正常に設定できた場合true。 */
    bool tooltipReady;

    /**
     * ラベル生成時または設定失敗後の再試行時に固定座標と表示設定を反映する。
     *
     * @return 固定の表示設定に成功した場合true。
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
            68
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

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_SOURCE_LABEL_MQH
