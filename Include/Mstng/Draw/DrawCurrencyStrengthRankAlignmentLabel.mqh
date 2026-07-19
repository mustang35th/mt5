//+------------------------------------------------------------------+
//|          DrawCurrencyStrengthRankAlignmentLabel.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_ALIGNMENT_LABEL_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_ALIGNMENT_LABEL_MQH

#include <Mstng\Constant\Constant.mqh>

/**
 * 長中期と中短期の順位方向一致状態をサブパネル右上へ描画する。
 */
class DrawCurrencyStrengthRankAlignmentLabel {
public:
    /**
     * 描画対象チャートとオブジェクト識別子を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromObjectSuffix オブジェクト名を一意にする接尾辞。
     */
    DrawCurrencyStrengthRankAlignmentLabel(
        const long fromChartId,
        const string fromObjectSuffix
    ) {
        this.chartId = fromChartId;
        this.objectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthRankAlignment_"
            + fromObjectSuffix;
        this.created = false;
        this.lastSubWindow = -1;
        this.lastText = "";
        this.lastColor = clrNONE;
    }

    /**
     * デストラクタ。
     */
    ~DrawCurrencyStrengthRankAlignmentLabel() {
        this.clear();
    }

    /**
     * 指定サブウィンドウの右上へ方向一致状態を描画する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromText 表示する方向一致状態。
     * @param fromColor 文字色。
     * @return 描画に成功した場合true。
     */
    bool draw(
        const int fromSubWindow,
        const string fromText,
        const color fromColor
    ) {
        if (fromSubWindow <= 0 || fromText == "") {
            return false;
        }

        if (this.created
                && this.lastSubWindow == fromSubWindow
                && this.lastText == fromText
                && this.lastColor == fromColor) {
            return true;
        }

        int objectWindow = ObjectFind(this.chartId, this.objectName);

        if (objectWindow >= 0 && objectWindow != fromSubWindow) {
            ObjectDelete(this.chartId, this.objectName);
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

        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_CORNER,
            CORNER_RIGHT_UPPER
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_ANCHOR,
            ANCHOR_RIGHT_UPPER
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_XDISTANCE,
            48
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_YDISTANCE,
            49
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_FONTSIZE,
            10
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_COLOR,
            fromColor
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_SELECTABLE,
            false
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_SELECTED,
            false
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_HIDDEN,
            true
        );
        ObjectSetInteger(
            this.chartId,
            this.objectName,
            OBJPROP_ZORDER,
            2
        );
        ObjectSetString(
            this.chartId,
            this.objectName,
            OBJPROP_FONT,
            "MS Gothic"
        );
        ObjectSetString(
            this.chartId,
            this.objectName,
            OBJPROP_TEXT,
            fromText
        );
        this.created = true;
        this.lastSubWindow = fromSubWindow;
        this.lastText = fromText;
        this.lastColor = fromColor;
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 方向一致状態ラベルを削除する。
     */
    void clear() {
        if (!this.created) {
            return;
        }

        ObjectDelete(this.chartId, this.objectName);
        this.created = false;
        this.lastSubWindow = -1;
        this.lastText = "";
        this.lastColor = clrNONE;
        ChartRedraw(this.chartId);
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 方向一致状態ラベルのオブジェクト名。 */
    string objectName;

    /** ラベル生成済みの場合true。 */
    bool created;

    /** 前回描画したサブウィンドウ番号。 */
    int lastSubWindow;

    /** 前回描画した文字列。 */
    string lastText;

    /** 前回描画した文字色。 */
    color lastColor;
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_ALIGNMENT_LABEL_MQH
