//+------------------------------------------------------------------+
//|                         DrawCurrencyStrengthRankDeltaPanel.mqh  |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_PANEL_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_PANEL_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\ChartRedrawRequest.mqh>

/**
 * 順位差・両通貨順位・取得状態をサブパネル右上へ表示する。
 * 表示と再読込ボタンの受付だけを担当し、DB取得や順位差の判定は行わない。
 */
class DrawCurrencyStrengthRankDeltaPanel {
public:
    /**
     * チャートとインスタンス固有の描画識別子を設定する。
     *
     * @param fromChartId 描画先チャートID。
     * @param fromObjectSuffix 一意な接尾辞。先頭40文字を使用する。
     * @param fromRedrawRequest 呼び出し元が所有する再描画要求の集約先。
     */
    DrawCurrencyStrengthRankDeltaPanel(const long fromChartId,
            const string fromObjectSuffix, ChartRedrawRequest *fromRedrawRequest) {
        this.chartId = fromChartId;
        this.redrawRequest = fromRedrawRequest;
        string prefix = Constant::PREFIX_FIXED + "RankDelta_"
            + StringSubstr(fromObjectSuffix, 0, 40) + "_";
        for (int i = 0; i < 4; i++) {
            this.objectNames[i] = prefix + IntegerToString(i);
            this.resetItem(i);
        }
    }

    /**
     * 自身が作成した表示だけを解放する。
     */
    ~DrawCurrencyStrengthRankDeltaPanel() {
        this.clear();
    }

    /**
     * 右上の3行と任意の再読込ボタンを反映する。同値の項目は更新しない。
     *
     * @return 全表示の反映に成功した場合true。
     */
    bool draw(const int fromSubWindow, const string fromTitle,
            const string fromValue, const color fromValueColor,
            const string fromSource, const string fromTooltip, const bool fromShowReload) {
        if (fromSubWindow <= 0) {
            return false;
        }

        bool succeeded = this.updateItem(0, fromSubWindow, fromTitle, clrWhiteSmoke, fromTooltip);
        succeeded = this.updateItem(1, fromSubWindow, fromValue, fromValueColor, fromTooltip) && succeeded;
        succeeded = this.updateItem(2, fromSubWindow, fromSource, clrSilver, fromTooltip) && succeeded;
        if (fromShowReload) {
            succeeded = this.updateItem(3, fromSubWindow, "再読込", clrSilver,
                "表示期間全体を再取得します。\n" + fromTooltip) && succeeded;
        } else if (this.lastSubWindows[3] >= 0) {
            succeeded = this.removeItem(3) && succeeded;
        }

        return succeeded;
    }

    /**
     * 自分の生成済みボタンだけを受け付け、押下状態を解除する。
     *
     * @return 再読込ボタンのクリックを受け付けた場合true。
     */
    bool handleReloadClick(const string fromName) {
        if (!this.created[3] || fromName != this.objectNames[3]
                || ObjectFind(this.chartId, fromName) != this.lastSubWindows[3]) {
            return false;
        }

        bool released = ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
        this.requestRedraw();

        return released;
    }

    /**
     * 自身の4オブジェクトだけを消去する。
     */
    void clear() {
        for (int i = 0; i < 4; i++) {
            this.removeItem(i);
        }
    }

private:
    /** 描画先のチャートID。 */
    long chartId;

    /** 呼び出し元が所有する再描画要求の集約先。 */
    ChartRedrawRequest *redrawRequest;

    /** Title・Value・Source・Reloadの順の固有名。 */
    string objectNames[4];

    /** 固定設定まで完了している場合true。 */
    bool created[4];

    /** 文字・色・説明の全設定が完了している場合true。 */
    bool valuesReady[4];

    /** 作成済みのサブウィンドウ番号。未作成は-1。 */
    int lastSubWindows[4];

    /** 反映済みの表示文字。 */
    string lastTexts[4];

    /** 反映済みの文字色。 */
    color lastColors[4];

    /** 反映済みの説明文。 */
    string lastTooltips[4];

    /**
     * 1項目の作成・反映済み状態を初期化する。
     */
    void resetItem(const int fromIndex) {
        this.created[fromIndex] = false;
        this.valuesReady[fromIndex] = false;
        this.lastSubWindows[fromIndex] = -1;
        this.lastTexts[fromIndex] = "";
        this.lastColors[fromIndex] = clrNONE;
        this.lastTooltips[fromIndex] = "";
    }

    /**
     * 1項目を削除する。失敗した場合は次回の削除対象として保持する。
     */
    bool removeItem(const int fromIndex) {
        if (ObjectFind(this.chartId, this.objectNames[fromIndex]) < 0) {
            this.resetItem(fromIndex);

            return true;
        }

        if (!ObjectDelete(this.chartId, this.objectNames[fromIndex])) {
            return false;
        }

        this.resetItem(fromIndex);
        this.requestRedraw();

        return true;
    }

    /**
     * 必要なら再作成し、文字・色・説明の変更項目を更新する。
     */
    bool updateItem(const int fromIndex, const int fromSubWindow,
            const string fromText, const color fromColor, const string fromTooltip) {
        string objectName = this.objectNames[fromIndex];
        int objectWindow = ObjectFind(this.chartId, objectName);
        if (objectWindow != fromSubWindow || !this.created[fromIndex]) {
            this.created[fromIndex] = false;
            this.valuesReady[fromIndex] = false;
            if (objectWindow >= 0 && objectWindow != fromSubWindow) {
                if (!this.removeItem(fromIndex)) {
                    return false;
                }

                objectWindow = -1;
            }

            ENUM_OBJECT objectType = OBJ_LABEL;
            if (fromIndex == 3) {
                objectType = OBJ_BUTTON;
            }

            if (objectWindow < 0
                    && !ObjectCreate(this.chartId, objectName, objectType, fromSubWindow, 0, 0)) {
                return false;
            }

            this.lastSubWindows[fromIndex] = fromSubWindow;
            this.requestRedraw();
            if (!this.configureItem(fromIndex)) {
                return false;
            }

            this.created[fromIndex] = true;
        }

        bool succeeded = true;
        if (!this.valuesReady[fromIndex] || this.lastTexts[fromIndex] != fromText) {
            if (ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText)) {
                this.lastTexts[fromIndex] = fromText;
                this.requestRedraw();
            } else {
                succeeded = false;
            }
        }

        if (!this.valuesReady[fromIndex] || this.lastColors[fromIndex] != fromColor) {
            if (ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor)) {
                this.lastColors[fromIndex] = fromColor;
                this.requestRedraw();
            } else {
                succeeded = false;
            }
        }

        if (!this.valuesReady[fromIndex] || this.lastTooltips[fromIndex] != fromTooltip) {
            if (ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, fromTooltip)) {
                this.lastTooltips[fromIndex] = fromTooltip;
                this.requestRedraw();
            } else {
                succeeded = false;
            }
        }

        this.valuesReady[fromIndex] = succeeded;

        return succeeded;
    }

    /**
     * 位置・フォント・選択可否などの固定項目を生成時だけ反映する。
     */
    bool configureItem(const int fromIndex) {
        string objectName = this.objectNames[fromIndex];
        int distance = 12;
        int top = 8 + fromIndex * 19;
        if (fromIndex == 3) {
            distance = 360;
            top = 8;
        }

        bool configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, distance) && configured;
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, top) && configured;
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, 9) && configured;
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false) && configured;
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false) && configured;
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false) && configured;
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true) && configured;
        configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 3) && configured;
        configured = ObjectSetString(this.chartId, objectName, OBJPROP_FONT, "MS Gothic") && configured;
        if (fromIndex == 3) {
            configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, 64) && configured;
            configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, 18) && configured;
            configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, C'35,35,35') && configured;
            configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_COLOR, clrDimGray) && configured;
            configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false) && configured;
        } else {
            configured = ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER) && configured;
        }

        return configured;
    }

    /**
     * 再描画を呼び出し元で集約する。集約先未指定時はその場で反映する。
     */
    void requestRedraw() {
        if (this.redrawRequest != NULL) {
            this.redrawRequest.request();
        } else {
            ChartRedraw(this.chartId);
        }
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_DELTA_PANEL_MQH
