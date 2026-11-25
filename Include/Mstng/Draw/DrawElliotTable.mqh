#ifndef MSTNG_DRAW_ELLIOT_TABLE_MQH
#define MSTNG_DRAW_ELLIOT_TABLE_MQH

#include <Mstng\Draw\ElliotTableFormatter.mqh>

/**
 * 共通5列の配置を保持し、チャート表と保存パネルの文字サイズ・背景を指定する。
 * 列の横位置はoriginXからの相対位置で、追加列の間隔も呼び出し側から指定できる。
 */
struct ElliotTableLayout {
    /** 表の左端。 */
    int originX;

    /** 行または見出しの上端。 */
    int originY;

    /** 表示フォント。 */
    string fontFace;

    /** 共通5列の相対横位置。 */
    int columnXs[5];

    /** 共通5列の幅。 */
    int columnWidths[5];

    /** 共通5列の文字サイズ。 */
    int columnFontSizes[5];

    /** 共通5列の文字の縦補正。 */
    int columnYOffsets[5];

    /** 共通5列の表示有無。 */
    bool columnVisible[5];

    /** セル固有の説明。空文字の場合は表示設定に従う。 */
    string tooltips[5];

    /** セル内の左右余白。 */
    int paddingX;

    /** セル内の上余白。 */
    int paddingY;

    /** 背景・区切りの高さ。 */
    int rowHeight;

    /** 行背景を表示する場合true。 */
    bool showBackground;

    /** 列間の縦区切りを表示する場合true。 */
    bool showSeparators;

    /** 列幅を超える文字を省略する場合true。 */
    bool clipText;

    /** 行または見出しの背景色。 */
    color backgroundColor;

    /** 縦区切りの色。 */
    color separatorColor;

    /** 見出し文字の色。 */
    color headerColor;

    /** 背景・区切りのクリック優先度。 */
    long backgroundZOrder;

    /** セル文字のクリック優先度。 */
    long textZOrder;

    /**
     * 背景なし・省略なしの5列表示で初期化する。
     */
    ElliotTableLayout() {
        this.originX = 0;
        this.originY = 0;
        this.fontFace = "MS Gothic";
        this.paddingX = 0;
        this.paddingY = 0;
        this.rowHeight = 26;
        this.showBackground = false;
        this.showSeparators = false;
        this.clipText = false;
        this.backgroundColor = C'25,31,41';
        this.separatorColor = C'51,61,77';
        this.headerColor = clrWhite;
        this.backgroundZOrder = 20;
        this.textZOrder = 0;
        for (int i = 0; i < 5; i++) {
            this.columnXs[i] = 0;
            this.columnWidths[i] = 0;
            this.columnFontSizes[i] = 11;
            this.columnYOffsets[i] = 0;
            this.columnVisible[i] = true;
            this.tooltips[i] = "";
        }
    }
};

/**
 * ライブ表と保存パネルの共通5列を、指定された配置と配色で描画する。
 * 分析・DB参照・選択状態を持たず、呼び出し側のオブジェクト接頭辞だけを使用する。
 */
class DrawElliotTable {
public:
    /**
     * 共通の列名を指定配置で描画する。
     */
    static bool drawHeader(const long fromChartId, const string fromPrefix,
            const ElliotTableLayout &fromLayout) {
        ElliotTableRowData row;
        row.clear();
        ElliotTablePalette palette;

        return drawCells(fromChartId, fromPrefix, row, 0, palette, fromLayout, true);
    }

    /**
     * 一時間足のセル・背景・区切りを描画する。
     */
    static bool drawRow(const long fromChartId, const string fromPrefix,
            const ElliotTableRowData &fromRow, const int fromDigits,
            const ElliotTablePalette &fromPalette, const ElliotTableLayout &fromLayout) {
        return drawCells(fromChartId, fromPrefix, fromRow, fromDigits, fromPalette, fromLayout, false);
    }

    /**
     * 実際のフォント幅を測り、指定幅を超える文字列を省略する。
     */
    static string fitText(const string fromText, const int fromWidth,
            const string fromFontFace, const int fromSize) {
        if (fromWidth <= 0) {
            return "";
        }

        uint width = 0;
        uint height = 0;
        if (!TextSetFont(fromFontFace, -10 * fromSize) || !TextGetSize(fromText, width, height)) {
            return shorten(fromText, MathMax(1, fromWidth / MathMax(1, fromSize)));
        }
        if ((int)width <= fromWidth) {
            return fromText;
        }

        for (int i = StringLen(fromText) - 1; i >= 0; i--) {
            string text = StringSubstr(fromText, 0, i) + "…";
            if (TextGetSize(text, width, height) && (int)width <= fromWidth) {
                return text;
            }
        }

        return "";
    }

private:
    /**
     * 見出しとデータ行に共通の配置・オブジェクト生成を行う。
     */
    static bool drawCells(const long fromChartId, const string fromPrefix,
            const ElliotTableRowData &fromRow, const int fromDigits,
            const ElliotTablePalette &fromPalette, const ElliotTableLayout &fromLayout,
            const bool fromHeader) {
        int right = 0;
        int lastColumn = -1;
        for (int i = 0; i < 5; i++) {
            if (fromLayout.columnVisible[i]) {
                right = MathMax(right, fromLayout.columnXs[i] + fromLayout.columnWidths[i]);
                lastColumn = i;
            }
        }

        bool success = true;
        if (fromLayout.showBackground && right > 0) {
            success = drawRectangle(fromChartId, fromPrefix + "Background", fromLayout.originX,
                fromLayout.originY, right, fromLayout.rowHeight, fromLayout.backgroundColor,
                fromLayout.backgroundZOrder);
        }

        for (int i = 0; i < 5; i++) {
            if (!fromLayout.columnVisible[i]) {
                continue;
            }

            string text = ElliotTableFormatter::columnName(i);
            color textColor = fromLayout.headerColor;
            string tooltip = "\n";
            if (!fromHeader) {
                text = ElliotTableFormatter::cellText(fromRow, i, fromDigits);
                textColor = ElliotTableFormatter::cellColor(fromRow, i, fromPalette);
                tooltip = fromLayout.tooltips[i];
                if (tooltip == "" && fromLayout.clipText) {
                    tooltip = shorten(text, 159);
                }
            }
            if (fromLayout.clipText) {
                text = fitText(text, fromLayout.columnWidths[i] - 2 * fromLayout.paddingX,
                    fromLayout.fontFace, fromLayout.columnFontSizes[i]);
            }

            bool drawn = drawLabel(fromChartId, fromPrefix + ElliotTableFormatter::columnKey(i),
                text, fromLayout.originX + fromLayout.columnXs[i] + fromLayout.paddingX,
                fromLayout.originY + fromLayout.columnYOffsets[i] + fromLayout.paddingY,
                fromLayout.fontFace, fromLayout.columnFontSizes[i], textColor, tooltip,
                fromLayout.textZOrder);
            success = drawn && success;
            if (fromLayout.showSeparators && i != lastColumn) {
                drawn = drawRectangle(fromChartId, fromPrefix + "Line" + IntegerToString(i),
                    fromLayout.originX + fromLayout.columnXs[i] + fromLayout.columnWidths[i] - 1,
                    fromLayout.originY, 1, fromLayout.rowHeight, fromLayout.separatorColor,
                    fromLayout.backgroundZOrder);
                success = drawn && success;
            }
        }

        return success;
    }

    /**
     * 所有するラベルを作成・更新する。
     */
    static bool drawLabel(const long fromChartId, const string fromName, const string fromText,
            const int fromX, const int fromY, const string fromFontFace, const int fromSize,
            const color fromColor, const string fromTooltip, const long fromZOrder) {
        if (ObjectFind(fromChartId, fromName) < 0
                && !ObjectCreate(fromChartId, fromName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        return ObjectSetInteger(fromChartId, fromName, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_COLOR, fromColor)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_FONTSIZE, fromSize)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_BACK, false)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_ZORDER, fromZOrder)
            && ObjectSetString(fromChartId, fromName, OBJPROP_FONT, fromFontFace)
            && ObjectSetString(fromChartId, fromName, OBJPROP_TEXT, fromText)
            && ObjectSetString(fromChartId, fromName, OBJPROP_TOOLTIP, fromTooltip);
    }

    /**
     * セルの背景または縦区切りを作成・更新する。
     */
    static bool drawRectangle(const long fromChartId, const string fromName, const int fromX,
            const int fromY, const int fromWidth, const int fromHeight, const color fromColor,
            const long fromZOrder) {
        if (ObjectFind(fromChartId, fromName) < 0
                && !ObjectCreate(fromChartId, fromName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        return ObjectSetInteger(fromChartId, fromName, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_XSIZE, fromWidth)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_YSIZE, fromHeight)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_BGCOLOR, fromColor)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_BORDER_TYPE, BORDER_FLAT)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_COLOR, clrSlateGray)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_BACK, false)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(fromChartId, fromName, OBJPROP_ZORDER, fromZOrder)
            && ObjectSetString(fromChartId, fromName, OBJPROP_TOOLTIP, "\n");
    }

    /**
     * ツールチップと幅計測失敗時の文字数上限を適用する。
     */
    static string shorten(const string fromText, const int fromLimit) {
        if (StringLen(fromText) <= fromLimit) {
            return fromText;
        }
        if (fromLimit <= 1) {
            return "…";
        }

        return StringSubstr(fromText, 0, fromLimit - 1) + "…";
    }
};

#endif // MSTNG_DRAW_ELLIOT_TABLE_MQH
