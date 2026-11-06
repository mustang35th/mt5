//+------------------------------------------------------------------+
//|                         DrawCurrencyStrengthRankReloadButton.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_RELOAD_BUTTON_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_RELOAD_BUTTON_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>

/**
 * 通貨強弱順位の履歴再読込ボタンをサブパネル右上へ描画する。
 * クリックの受付と表示だけを担当し、履歴の取得は呼び出し元へ委ねる。
 */
class DrawCurrencyStrengthRankReloadButton {
public:
    /**
     * 描画対象チャートとオブジェクト識別子を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix オブジェクト名を一意にする接尾辞。
     * @param fromRedrawRequest 再描画要求の集約先。NULLの場合は直接再描画する。
     */
    DrawCurrencyStrengthRankReloadButton(
        const long fromChartId,
        const string fromObjectSuffix,
        ChartRedrawRequest *fromRedrawRequest = NULL
    ) {
        this.chartId = fromChartId;
        this.redrawRequest = fromRedrawRequest;
        this.objectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthRankReload_"
            + fromObjectSuffix;
        this.resetCache();
    }

    /**
     * 所有する再読込ボタンを削除する。
     */
    ~DrawCurrencyStrengthRankReloadButton() {
        this.clear();
    }

    /**
     * 指定サブウィンドウへ再読込ボタンを描画する。
     * 固定属性は生成時だけ設定し、説明と色は前回の成功値から変わった場合だけ反映する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromTooltip 再読込対象や状態を示す説明文。
     * @param fromColor ボタンの文字色。
     * @return 描画または変更なしの確認に成功した場合true。
     */
    bool draw(
        const int fromSubWindow,
        const string fromTooltip,
        const color fromColor
    ) {
        if (fromSubWindow <= 0) {
            return false;
        }

        int objectWindow = ObjectFind(this.chartId, this.objectName);
        bool initializeProperties = !this.created
            || this.lastSubWindow != fromSubWindow
            || objectWindow != fromSubWindow;
        bool changed = false;
        if (initializeProperties) {
            this.resetCache();
            if (objectWindow >= 0 && objectWindow != fromSubWindow) {
                if (!ObjectDelete(this.chartId, this.objectName)) {
                    return false;
                }

                objectWindow = -1;
                changed = true;
            }

            if (objectWindow < 0
                    && !ObjectCreate(this.chartId, this.objectName, OBJ_BUTTON,
                        fromSubWindow, 0, 0)) {
                if (changed) {
                    this.requestRedraw();
                }

                return false;
            }

            bool configured = this.configureObject();
            changed = true;
            if (!configured) {
                this.requestRedraw();

                return false;
            }

            this.created = true;
            this.lastSubWindow = fromSubWindow;
        }

        bool updated = true;
        if (!this.tooltipReady || this.lastTooltip != fromTooltip) {
            if (ObjectSetString(this.chartId, this.objectName, OBJPROP_TOOLTIP, fromTooltip)) {
                this.lastTooltip = fromTooltip;
                this.tooltipReady = true;
                changed = true;
            } else {
                updated = false;
            }
        }

        if (!this.colorReady || this.lastColor != fromColor) {
            if (ObjectSetInteger(this.chartId, this.objectName, OBJPROP_COLOR, fromColor)) {
                this.lastColor = fromColor;
                this.colorReady = true;
                changed = true;
            } else {
                updated = false;
            }
        }

        if (changed) {
            this.requestRedraw();
        }

        return updated;
    }

    /**
     * 自身の生成済みボタンのクリックを受け付け、押下状態を解除する。
     *
     * @param fromObjectName クリックされたチャートオブジェクト名。
     * @return 自身の有効なボタンの押下状態を解除できた場合true。
     */
    bool handleClick(const string fromObjectName) {
        if (!this.created || fromObjectName != this.objectName
                || this.lastSubWindow <= 0
                || ObjectFind(this.chartId, this.objectName) != this.lastSubWindow) {
            return false;
        }

        bool released = ObjectSetInteger(this.chartId, this.objectName, OBJPROP_STATE, false);
        this.requestRedraw();

        return released;
    }

    /**
     * 再読込ボタンを削除し、表示の成功値を初期化する。
     */
    void clear() {
        bool deleted = ObjectDelete(this.chartId, this.objectName);
        this.resetCache();
        if (deleted) {
            this.requestRedraw();
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 呼び出し元が所有する再描画要求の集約先。 */
    ChartRedrawRequest *redrawRequest;

    /** 再読込ボタンのオブジェクト名。 */
    string objectName;

    /** ボタンの固定属性の設定が完了した場合true。 */
    bool created;

    /** 固定属性を設定済みのサブウィンドウ番号。 */
    int lastSubWindow;

    /** 説明文を一度以上正常に設定できた場合true。 */
    bool tooltipReady;

    /** 前回設定に成功した説明文。 */
    string lastTooltip;

    /** 文字色を一度以上正常に設定できた場合true。 */
    bool colorReady;

    /** 前回設定に成功した文字色。 */
    color lastColor;

    /**
     * オブジェクトの削除・再生成に備えて成功値を無効化する。
     */
    void resetCache() {
        this.created = false;
        this.lastSubWindow = -1;
        this.tooltipReady = false;
        this.lastTooltip = "";
        this.colorReady = false;
        this.lastColor = clrNONE;
    }

    /**
     * ボタンの固定座標・文字・表示設定を生成時に適用する。
     *
     * @return すべての固定属性を設定できた場合true。
     */
    bool configureObject() {
        bool configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        // OBJ_BUTTONは左上固定アンカーのため、右端から左上までの距離を指定する。
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_XDISTANCE, 310) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_YDISTANCE, 5) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_XSIZE, 100) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_YSIZE, 20) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_FONTSIZE, 9) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_BGCOLOR, C'35,35,35') && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_BORDER_COLOR, clrDimGray) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_BACK, false) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_SELECTABLE, false) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_SELECTED, false) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_HIDDEN, true) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_ZORDER, 3) && configured;
        configured = ObjectSetInteger(this.chartId, this.objectName,
            OBJPROP_STATE, false) && configured;
        configured = ObjectSetString(this.chartId, this.objectName,
            OBJPROP_FONT, "MS Gothic") && configured;
        configured = ObjectSetString(this.chartId, this.objectName,
            OBJPROP_TEXT, "履歴を再読込") && configured;

        return configured;
    }

    /**
     * 呼び出し元の集約先へ再描画を要求する。
     */
    void requestRedraw() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        } else {
            ChartRedraw(this.chartId);
        }
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_RELOAD_BUTTON_MQH
