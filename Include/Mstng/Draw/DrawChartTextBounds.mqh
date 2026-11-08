//+------------------------------------------------------------------+
//|                                          DrawChartTextBounds.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_DRAW_CHART_TEXT_BOUNDS_MQH
#define MSTNG_DRAW_CHART_TEXT_BOUNDS_MQH

/**
 * 同一時間足の連続した文字描画で、取得済みの画面情報と計測用フォントを共用する。
 * 描画の開始ごとに生成し、途中で別の計測用フォントを設定する処理とは共用しない。
 */
class DrawChartTextContext {
public:
    /** 取得済みのチャート幅。 */
    long chartWidth;

    /** 取得済みのメインチャート高さ。 */
    long chartHeight;

    /** 取得済みの表示価格下限。 */
    double priceMin;

    /** 取得済みの表示価格上限。 */
    double priceMax;

    /**
     * 画面情報とフォントを未取得として初期化する。
     */
    DrawChartTextContext() {
        this.chartWidth = 0;
        this.chartHeight = 0;
        this.priceMin = 0.0;
        this.priceMax = 0.0;
        this.chartWidthReady = false;
        this.chartHeightReady = false;
        this.priceRangeReady = false;
        this.fontReady = false;
        this.font = "";
        this.fontSize = 0;
    }

    /**
     * チャート幅を必要時に取得する。失敗時は次回に再試行する。
     */
    bool loadChartWidth() {
        if (!this.chartWidthReady) {
            this.chartWidthReady = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0, this.chartWidth);
        }

        return this.chartWidthReady;
    }

    /**
     * メインチャート高さを必要時に取得する。失敗時は次回に再試行する。
     */
    bool loadChartHeight() {
        if (!this.chartHeightReady) {
            this.chartHeightReady = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0, this.chartHeight)
                && this.chartHeight > 0;
        }

        return this.chartHeightReady;
    }

    /**
     * 価格換算に必要な高さと表示価格範囲を取得する。成功値だけを保持する。
     */
    bool loadPriceRange() {
        if (this.priceRangeReady) {
            return true;
        }

        if (!this.loadChartHeight() || this.chartHeight <= 1) {
            this.chartHeightReady = false;

            return false;
        }

        if (!ChartGetDouble(0, CHART_PRICE_MIN, 0, this.priceMin)
                || !ChartGetDouble(0, CHART_PRICE_MAX, 0, this.priceMax)
                || this.priceMax <= this.priceMin) {
            return false;
        }

        this.priceRangeReady = true;

        return true;
    }

    /**
     * 同じ計測用フォントの設定を省略する。設定に失敗した場合は再試行する。
     *
     * @param fromFont フォント名。
     * @param fromFontSize 文字サイズ。
     */
    bool prepareFont(const string fromFont, const int fromFontSize) {
        if (this.fontReady && this.font == fromFont && this.fontSize == fromFontSize) {
            return true;
        }

        this.fontReady = false;
        if (!TextSetFont(fromFont, -fromFontSize * 10)) {
            return false;
        }

        this.font = fromFont;
        this.fontSize = fromFontSize;
        this.fontReady = true;

        return true;
    }

private:
    /** チャート幅の取得済みフラグ。 */
    bool chartWidthReady;

    /** メインチャート高さの取得済みフラグ。 */
    bool chartHeightReady;

    /** 有効な表示価格範囲の取得済みフラグ。 */
    bool priceRangeReady;

    /** 計測用フォントの設定済みフラグ。 */
    bool fontReady;

    /** 設定済みの計測用フォント名。 */
    string font;

    /** 設定済みの計測用文字サイズ。 */
    int fontSize;
};

/**
 * 価格を変えず、チャート文字の表示時刻だけを右側の予約領域から左へ寄せる。
 */
class DrawChartTextBounds {
public:
    /**
     * 最新足が横方向の画面内にある場合だけ、右側情報欄を避ける補正を使用する。
     * 表示価格範囲の中間値で横位置を調べ、取得失敗時は従来の補正を維持する。
     *
     * @param fromSymbolName チャートの銘柄。
     * @param fromTimeFrame チャートの時間足。
     * @return 最新表示、または表示状態を判定できない場合true。
     */
    static bool shouldAdjustRightBoundary(
        const string fromSymbolName,
        const ENUM_TIMEFRAMES fromTimeFrame
    ) {
        datetime latestBarTime = iTime(fromSymbolName, fromTimeFrame, 0);
        DrawChartTextContext drawContext;
        if (latestBarTime <= 0 || !drawContext.loadChartWidth() || drawContext.chartWidth <= 0
                || !drawContext.loadPriceRange()) {
            return true;
        }

        double middlePrice = drawContext.priceMin + (drawContext.priceMax - drawContext.priceMin) / 2.0;
        int latestBarX = 0;
        int latestBarY = 0;
        if (!ChartTimePriceToXY(0, 0, latestBarTime, middlePrice, latestBarX, latestBarY)) {
            return true;
        }

        return latestBarX >= 0 && latestBarX < drawContext.chartWidth;
    }

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
        DrawChartTextContext drawContext;

        return fitTime(fromTime, fromPrice, fromText, fromFont, fromFontSize,
            fromReservedRightWidth, fromCenterAnchor, drawContext);
    }

    /**
     * 同じ描画内の画面情報と計測用フォントを共用し、表示時刻を補正する。
     *
     * @param fromTime 元の表示時刻。成功時は補正後の表示時刻。
     * @param fromPrice 変更しない表示価格。
     * @param fromText 表示文字。
     * @param fromFont フォント名。
     * @param fromFontSize 文字サイズ。
     * @param fromReservedRightWidth チャート右端から確保する幅。0は補正しない。
     * @param fromCenterAnchor 中央アンカーの場合true、左アンカーの場合false。
     * @param fromContext 呼び出し間で別の計測用フォントを設定しない描画用情報。
     * @param fromHideRightOutsideAnchor 右端補正時、元の基準位置が画面右端以上なら非表示にする。
     * @param fromAdjustRightBoundary falseの場合、右画面外の除外だけ行い、表示時刻を補正しない。
     * @return 補正不要、または境界内の表示時刻を取得できた場合true。
     */
    static bool fitTime(
        datetime &fromTime,
        const double fromPrice,
        const string fromText,
        const string fromFont,
        const int fromFontSize,
        const int fromReservedRightWidth,
        const bool fromCenterAnchor,
        DrawChartTextContext &fromContext,
        const bool fromHideRightOutsideAnchor = false,
        const bool fromAdjustRightBoundary = true
    ) {
        if (fromReservedRightWidth <= 0 || fromText == "") {
            return true;
        }

        uint textWidth = 0;
        uint textHeight = 0;
        int originalX = 0;
        int originalY = 0;
        if (!fromContext.loadChartWidth()
                || !fromContext.prepareFont(fromFont, fromFontSize)
                || !TextGetSize(fromText, textWidth, textHeight)
                || textWidth == 0
                || !ChartTimePriceToXY(0, 0, fromTime, fromPrice, originalX, originalY)) {
            return false;
        }

        if (fromHideRightOutsideAnchor && originalX >= fromContext.chartWidth) {
            return false;
        }

        if (!fromAdjustRightBoundary) {
            return true;
        }

        // フォントの描画端とピクセル変換の丸めに余裕を持たせる。
        int rightWidth = (int)textWidth + 2;
        int leftWidth = 0;
        if (fromCenterAnchor) {
            rightWidth = ((int)textWidth + 1) / 2 + 2;
            leftWidth = (int)textWidth / 2 + 2;
        }

        int maximumX = (int)fromContext.chartWidth - fromReservedRightWidth - rightWidth;
        if (originalX <= maximumX) {
            return true;
        }

        // 逆変換では時刻だけを使い、画面外の価格でもメイン画面内のY座標を参照する。
        if (!fromContext.loadChartHeight()) {
            return false;
        }

        int conversionY = (int)fromContext.chartHeight / 2;
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
