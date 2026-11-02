//+------------------------------------------------------------------+
//|                                          DrawChartTextBounds.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_DRAW_CHART_TEXT_BOUNDS_MQH
#define MSTNG_DRAW_CHART_TEXT_BOUNDS_MQH

/**
 * 価格を変えず、チャート文字の表示時刻だけを右側の予約領域から左へ寄せる。
 */
class DrawChartTextBounds {
public:
    /**
     * 文字の右端が予約領域へ入る場合だけ表示時刻を左へ補正する。
     * 座標の丸め後も境界内にあることを確認し、成功時だけ時刻を更新する。
     *
     * @param fromTime 元の表示時刻。成功時は補正後の表示時刻。
     * @param fromPrice 変更しない表示価格。
     * @param fromText 表示文字。
     * @param fromFont フォント名。
     * @param fromFontSize 文字サイズ。
     * @param fromReservedRightWidth チャート右端から確保する幅。0は補正しない。
     * @param fromCenterAnchor 中央アンカーの場合true、左アンカーの場合false。
     * @return 補正不要、または境界内の表示時刻を取得できた場合true。
     */
    static bool fitTime(
        datetime &fromTime,
        const double fromPrice,
        const string fromText,
        const string fromFont,
        const int fromFontSize,
        const int fromReservedRightWidth,
        const bool fromCenterAnchor
    ) {
        if (fromReservedRightWidth <= 0 || fromText == "") {
            return true;
        }

        long chartWidth = 0;
        uint textWidth = 0;
        uint textHeight = 0;
        int originalX = 0;
        int originalY = 0;
        if (!ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, chartWidth)
                || !TextSetFont(fromFont, -fromFontSize * 10)
                || !TextGetSize(fromText, textWidth, textHeight)
                || textWidth == 0
                || !ChartTimePriceToXY(0, 0, fromTime, fromPrice, originalX, originalY)) {
            return false;
        }

        // フォントの描画端とピクセル変換の丸めに余裕を持たせる。
        int rightWidth = (int)textWidth + 2;
        int leftWidth = 0;
        if (fromCenterAnchor) {
            rightWidth = ((int)textWidth + 1) / 2 + 2;
            leftWidth = (int)textWidth / 2 + 2;
        }

        int maximumX = (int)chartWidth - fromReservedRightWidth - rightWidth;
        if (originalX <= maximumX) {
            return true;
        }

        // 逆変換では時刻だけを使い、画面外の価格でもメイン画面内のY座標を参照する。
        long chartHeight = 0;
        if (!ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, chartHeight) || chartHeight <= 0) {
            return false;
        }

        int conversionY = (int)chartHeight / 2;
        int targetX = maximumX;
        for (int i = 0; i < 8 && targetX >= leftWidth; i++) {
            int subwindow = 0;
            datetime adjustedTime = 0;
            double ignoredPrice = 0.0;
            int adjustedX = 0;
            int ignoredY = 0;
            if (!ChartXYToTimePrice(0, targetX, conversionY, subwindow, adjustedTime, ignoredPrice)
                    || subwindow != 0 || adjustedTime <= 0
                    || !ChartTimePriceToXY(0, 0, adjustedTime, fromPrice, adjustedX, ignoredY)) {
                return false;
            }

            if (adjustedX <= maximumX && adjustedX >= leftWidth) {
                fromTime = adjustedTime;

                return true;
            }

            if (adjustedX < leftWidth) {
                return false;
            }

            targetX -= (int)MathMax(2, 2 * (adjustedX - targetX) + 2);
        }

        return false;
    }
};

#endif
