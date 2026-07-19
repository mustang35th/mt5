//+------------------------------------------------------------------+
//|             DrawCurrencyStrengthRankPeriodLabel.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_RANK_PERIOD_LABEL_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_RANK_PERIOD_LABEL_MQH

#include <Mstng\Constant\Constant.mqh>

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
     */
    DrawCurrencyStrengthRankPeriodLabel(
        const long fromChartId,
        const string fromObjectSuffix
    ) {
        this.chartId = fromChartId;
        this.objectName = Constant::PREFIX_FIXED
            + "CurrencyStrengthRankPeriod_"
            + fromObjectSuffix;
    }

    /**
     * デストラクタ。
     */
    ~DrawCurrencyStrengthRankPeriodLabel() {
        this.clear();
    }

    /**
     * 指定サブウィンドウの右上へ期間名を描画する。
     *
     * @param fromSubWindow 描画対象サブウィンドウ番号。
     * @param fromText 表示する期間名。
     * @return 描画に成功した場合true。
     */
    bool draw(const int fromSubWindow, const string fromText) {
        if (fromSubWindow <= 0 || fromText == "") {
            return false;
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
            8
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
            clrWhiteSmoke
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
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 期間名ラベルを削除する。
     */
    void clear() {
        ObjectDelete(this.chartId, this.objectName);
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 期間名ラベルのオブジェクト名。 */
    string objectName;
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_RANK_PERIOD_LABEL_MQH
