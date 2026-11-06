//+------------------------------------------------------------------+
//|                    DrawCurrencyStrengthRegionRankComparison.mqh   |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_REGION_RANK_COMPARISON_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_REGION_RANK_COMPARISON_MQH

#include <Canvas\Canvas.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\DrawCurrencyStrengthRankComparison.mqh>

/**
 * 同一時点の長中期・中短期を、地域ごとの平均通貨順位で比較する。
 * 通貨順位比較の順位帯を共用し、ラベルの重なりだけを引き出し線で避ける。
 */
class DrawCurrencyStrengthRegionRankComparison {
public:
    /**
     * 描画対象と固定位置を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。
     * @param fromXDistance パネル左位置。
     * @param fromYDistance パネル上位置。
     * @param fromInstanceKey 同一チャート内の識別子。
     */
    DrawCurrencyStrengthRegionRankComparison(long fromChartId = 0,
            int fromXDistance = 12, int fromYDistance = 12,
            string fromInstanceKey = "") {
        this.chartId = fromChartId;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.panelWidth = 280;
        this.panelHeight = 350;
        this.plotTop = 80;
        this.plotHeight = 208;
        this.created = false;
        this.rankingReady = false;
        this.rankDetailsValid = false;
        this.renderPending = true;
        this.selectedRegion = -1;
        this.fontName = "MS Gothic";
        this.backgroundColor = C'18,18,18';
        this.mutedColor = C'130,130,130';
        this.regionNames[0] = "北米";
        this.regionNames[1] = "欧州";
        this.regionNames[2] = "アジア";
        this.regionNames[3] = "オセアニア";
        this.regionColors[0] = clrGold;
        this.regionColors[1] = clrDeepSkyBlue;
        this.regionColors[2] = clrViolet;
        this.regionColors[3] = clrLimeGreen;
        this.currencyNames[0] = "USD";
        this.currencyNames[1] = "CAD";
        this.currencyNames[2] = "EUR";
        this.currencyNames[3] = "GBP";
        this.currencyNames[4] = "CHF";
        this.currencyNames[5] = "JPY";
        this.currencyNames[6] = "AUD";
        this.currencyNames[7] = "NZD";
        this.currencyRegions[0] = 0;
        this.currencyRegions[1] = 0;
        this.currencyRegions[2] = 1;
        this.currencyRegions[3] = 1;
        this.currencyRegions[4] = 1;
        this.currencyRegions[5] = 2;
        this.currencyRegions[6] = 3;
        this.currencyRegions[7] = 3;

        string basePrefix = Constant::PREFIX_FIXED + "RegionRank_";
        if (fromInstanceKey != "") {
            basePrefix += StringSubstr(fromInstanceKey, 0, 12) + "_";
        }

        static int nextInstanceIndex = 0;
        int instanceIndex = nextInstanceIndex;
        this.objectPrefix = basePrefix + IntegerToString(instanceIndex) + "_";
        while (ObjectFind(this.chartId, this.objectPrefix + "Panel") >= 0) {
            instanceIndex++;
            this.objectPrefix = basePrefix + IntegerToString(instanceIndex) + "_";
        }

        nextInstanceIndex = instanceIndex + 1;
    }

    /**
     * 所有する描画オブジェクトとCanvasを解放する。
     */
    ~DrawCurrencyStrengthRegionRankComparison() {
        this.destroyObjects();
    }

    /**
     * 固定パネル幅を取得する。
     *
     * @return パネル幅。
     */
    int getPanelWidth() const {
        return this.panelWidth;
    }

    /**
     * 保持済みの通貨順位と順位帯を受け取り、地域平均を表示する。
     *
     * @param fromComparison 同一時点の通貨順位比較。
     * @return 待機表示を含め、描画に成功した場合true。
     */
    bool draw(DrawCurrencyStrengthRankComparison *fromComparison) {
        int nextPanelHeight = this.panelHeight;
        int nextPlotTop = this.plotTop;
        int nextPlotHeight = this.plotHeight;
        if (fromComparison != NULL) {
            nextPanelHeight = fromComparison.getPanelHeight();
            nextPlotTop = fromComparison.getPlotTop();
            nextPlotHeight = fromComparison.getPlotHeight();
        }

        bool layoutChanged = this.panelHeight != nextPanelHeight
            || this.plotTop != nextPlotTop || this.plotHeight != nextPlotHeight;
        bool mustCreate = !this.created || layoutChanged;
        if (layoutChanged) {
            this.rankDetailsValid = false;
        }

        this.panelHeight = nextPanelHeight;
        this.plotTop = nextPlotTop;
        this.plotHeight = nextPlotHeight;
        bool ranksReady = this.readRanks(fromComparison);
        if (this.rankingReady != ranksReady) {
            this.renderPending = true;
        }

        this.rankingReady = ranksReady;
        if (!this.rankingReady) {
            this.selectedRegion = -1;
        }

        if (mustCreate && !this.create()) {
            return false;
        }

        this.render();

        return true;
    }

    /**
     * 全描画と地域選択を解除する。
     */
    void clear() {
        this.destroyObjects();
        this.rankingReady = false;
        this.rankDetailsValid = false;
        this.selectedRegion = -1;
    }

    /**
     * 地域ラベルまたは解除ボタンのクリックを処理する。
     *
     * @param fromObjectName クリックされたオブジェクト名。
     * @return このパネルのクリックを処理した場合true。
     */
    bool handleObjectClick(const string fromObjectName) {
        if (!this.created) {
            return false;
        }

        if (fromObjectName == this.objectPrefix + "ClearSelection") {
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            this.clearSelection();

            return true;
        }

        if (!this.rankingReady) {
            return false;
        }

        for (int i = 0; i < 4; i++) {
            if (fromObjectName != this.getLabelName(true, i)
                    && fromObjectName != this.getLabelName(false, i)) {
                continue;
            }

            if (this.selectedRegion == i) {
                this.selectedRegion = -1;
            } else {
                this.selectedRegion = i;
            }

            this.renderPending = true;
            this.render();

            return true;
        }

        return false;
    }

    /**
     * 地域選択だけを解除し、表示済みの平均順位を維持する。
     */
    void clearSelection() {
        if (this.selectedRegion < 0) {
            return;
        }

        this.selectedRegion = -1;
        this.renderPending = true;
        if (this.created) {
            this.render();
        }
    }

    /**
     * 選択中の地域名を取得する。
     *
     * @return 未選択の場合は空文字。
     */
    string getSelectedRegionName() const {
        if (!this.rankingReady || this.selectedRegion < 0) {
            return "";
        }

        return this.regionNames[this.selectedRegion];
    }

    /**
     * 選択地域に属する通貨名を取得する。
     *
     * @param fromCurrencies 通貨名の格納先。未選択の場合は空配列。
     */
    void getSelectedCurrencies(string &fromCurrencies[]) const {
        ArrayResize(fromCurrencies, 0);
        if (!this.rankingReady || this.selectedRegion < 0) {
            return;
        }

        for (int i = 0; i < 8; i++) {
            if (this.currencyRegions[i] != this.selectedRegion) {
                continue;
            }

            int count = ArraySize(fromCurrencies);
            ArrayResize(fromCurrencies, count + 1);
            fromCurrencies[count] = this.currencyNames[i];
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** パネル左位置。 */
    int xDistance;

    /** パネル上位置。 */
    int yDistance;

    /** パネル幅。 */
    int panelWidth;

    /** 通貨順位比較と共通のパネル高さ。 */
    int panelHeight;

    /** パネル上端からの描画領域位置。 */
    int plotTop;

    /** 通貨順位比較と共通の描画領域高さ。 */
    int plotHeight;

    /** 描画オブジェクト生成済みの場合true。 */
    bool created;

    /** 全通貨の順位を取得済みの場合true。 */
    bool rankingReady;

    /** 現在の順位・座標に対応する地域平均と説明文を保持している場合true。 */
    bool rankDetailsValid;

    /** 順位・配置・選択の変更または再生成により表示更新が必要な場合true。 */
    bool renderPending;

    /** 選択地域番号。未選択は-1。 */
    int selectedRegion;

    /** 接続線と引き出し線を描くCanvas。 */
    CCanvas lineCanvas;

    /** 表示フォント。 */
    string fontName;

    /** パネル背景色。 */
    color backgroundColor;

    /** 補助文字色。 */
    color mutedColor;

    /** 地域名。 */
    string regionNames[4];

    /** 地域ごとの固定表示色。 */
    color regionColors[4];

    /** 主要8通貨名。 */
    string currencyNames[8];

    /** 通貨ごとの所属地域番号。 */
    int currencyRegions[8];

    /** 通貨ごとの長中期実順位。 */
    int leftRanks[8];

    /** 通貨ごとの中短期実順位。 */
    int rightRanks[8];

    /** 地域ごとの長中期平均順位。 */
    double leftMeans[4];

    /** 地域ごとの中短期平均順位。 */
    double rightMeans[4];

    /** 地域ごとの長中期最大順位差。 */
    int leftSpans[4];

    /** 地域ごとの中短期最大順位差。 */
    int rightSpans[4];

    /** 平均順位に対応する長中期の正確な縦位置。 */
    int leftPoints[4];

    /** 平均順位に対応する中短期の正確な縦位置。 */
    int rightPoints[4];

    /** 重なりを避けた長中期ラベルの中心位置。 */
    int leftLabelPoints[4];

    /** 重なりを避けた中短期ラベルの中心位置。 */
    int rightLabelPoints[4];

    /** 既存比較と共有する各順位の中心位置。 */
    int rankPoints[8];

    /** 地域内の順位詳細。 */
    string regionTooltips[4];

    /**
     * 通貨順位を取得し、地域ごとの平均とばらつきを算出する。
     * 順位と実際の描画座標が同じ場合は、地域情報と説明文を再利用する。
     *
     * @param fromComparison 順位取得元。
     * @return 全順位を取得できた場合true。
     */
    bool readRanks(DrawCurrencyStrengthRankComparison *fromComparison) {
        if (fromComparison == NULL || !fromComparison.isRankingReady()) {
            this.rankDetailsValid = false;

            return false;
        }

        int nextLeftRanks[8];
        int nextRightRanks[8];
        int nextRankPoints[8];
        bool ranksChanged = !this.rankDetailsValid;
        for (int i = 0; i < 8; i++) {
            nextLeftRanks[i] = fromComparison.getCurrencyRank(this.currencyNames[i], true);
            nextRightRanks[i] = fromComparison.getCurrencyRank(this.currencyNames[i], false);
            if (nextLeftRanks[i] < 1 || nextLeftRanks[i] > 8
                    || nextRightRanks[i] < 1 || nextRightRanks[i] > 8) {
                this.rankDetailsValid = false;

                return false;
            }

            nextRankPoints[i] = (int)MathRound(fromComparison.getRankYDistance(i + 1.0));
            if (this.rankDetailsValid
                    && (this.leftRanks[i] != nextLeftRanks[i]
                        || this.rightRanks[i] != nextRightRanks[i]
                        || this.rankPoints[i] != nextRankPoints[i])) {
                ranksChanged = true;
            }
        }

        // 整数順位の中心が同じでも、平均順位の補間位置が変わった場合は更新する。
        if (!ranksChanged) {
            for (int i = 0; i < 4; i++) {
                if (this.leftPoints[i] != (int)MathRound(
                        fromComparison.getRankYDistance(this.leftMeans[i]))
                        || this.rightPoints[i] != (int)MathRound(
                            fromComparison.getRankYDistance(this.rightMeans[i]))) {
                    ranksChanged = true;
                    break;
                }
            }
        }

        if (!ranksChanged) {
            return true;
        }

        this.rankDetailsValid = false;
        ArrayCopy(this.leftRanks, nextLeftRanks);
        ArrayCopy(this.rightRanks, nextRightRanks);
        ArrayCopy(this.rankPoints, nextRankPoints);
        for (int i = 0; i < 4; i++) {
            int count = 0;
            int leftSum = 0;
            int rightSum = 0;
            int leftMinimum = 8;
            int leftMaximum = 1;
            int rightMinimum = 8;
            int rightMaximum = 1;
            string details = this.regionNames[i] + "（全8通貨中の順位）";
            for (int j = 0; j < 8; j++) {
                if (this.currencyRegions[j] != i) {
                    continue;
                }

                count++;
                leftSum += this.leftRanks[j];
                rightSum += this.rightRanks[j];
                leftMinimum = (int)MathMin(leftMinimum, this.leftRanks[j]);
                leftMaximum = (int)MathMax(leftMaximum, this.leftRanks[j]);
                rightMinimum = (int)MathMin(rightMinimum, this.rightRanks[j]);
                rightMaximum = (int)MathMax(rightMaximum, this.rightRanks[j]);
                details += StringFormat("\n%s：長中期 %d位 / 中短期 %d位",
                    this.currencyNames[j], this.leftRanks[j], this.rightRanks[j]);
            }

            if (count <= 0) {
                return false;
            }

            this.leftMeans[i] = (double)leftSum / count;
            this.rightMeans[i] = (double)rightSum / count;
            this.leftSpans[i] = leftMaximum - leftMinimum;
            this.rightSpans[i] = rightMaximum - rightMinimum;
            this.leftPoints[i] = (int)MathRound(
                fromComparison.getRankYDistance(this.leftMeans[i]));
            this.rightPoints[i] = (int)MathRound(
                fromComparison.getRankYDistance(this.rightMeans[i]));
            details += StringFormat("\n平均：長中期 %.1f位 / 中短期 %.1f位"
                "\n地域内順位差：長中期 %d / 中短期 %d",
                this.leftMeans[i], this.rightMeans[i], this.leftSpans[i], this.rightSpans[i]);
            if (this.leftSpans[i] <= 2 && this.rightSpans[i] <= 2) {
                details += "\n実線：両期間とも順位差2以内";
            } else {
                details += "\n破線：いずれかの期間で順位差3以上";
            }

            details += "\nクリックで所属通貨を強調・再クリックで解除";
            this.regionTooltips[i] = details;
        }

        this.arrangeLabels(this.leftPoints, this.leftLabelPoints);
        this.arrangeLabels(this.rightPoints, this.rightLabelPoints);
        this.rankDetailsValid = true;
        this.renderPending = true;

        return true;
    }

    /**
     * 線端点を動かさず、近接するラベルだけを22px間隔に広げる。
     *
     * @param fromPoints 平均順位の正確な位置。
     * @param fromLabelPoints ラベル中心位置の格納先。
     */
    void arrangeLabels(const int &fromPoints[], int &fromLabelPoints[]) {
        int order[4];
        for (int i = 0; i < 4; i++) {
            order[i] = i;
        }

        for (int i = 1; i < 4; i++) {
            int regionIndex = order[i];
            int j = i - 1;
            while (j >= 0 && fromPoints[order[j]] > fromPoints[regionIndex]) {
                order[j + 1] = order[j];
                j--;
            }

            order[j + 1] = regionIndex;
        }

        int minimum = this.plotTop + 10;
        int maximum = this.plotTop + this.plotHeight - 10;
        for (int i = 0; i < 4; i++) {
            int labelPoint = (int)MathMax(fromPoints[order[i]], minimum);
            if (i > 0) {
                labelPoint = (int)MathMax(labelPoint, fromLabelPoints[order[i - 1]] + 22);
            }

            fromLabelPoints[order[i]] = labelPoint;
        }

        fromLabelPoints[order[3]] = (int)MathMin(fromLabelPoints[order[3]], maximum);
        for (int i = 2; i >= 0; i--) {
            fromLabelPoints[order[i]] = (int)MathMin(fromLabelPoints[order[i]],
                fromLabelPoints[order[i + 1]] - 22);
        }
    }

    /**
     * 背景、Canvas、クリック可能な地域名を生成する。
     *
     * @return 全オブジェクトを生成できた場合true。
     */
    bool create() {
        this.destroyObjects();
        int footerTop = this.plotTop + this.plotHeight + 9;
        if (!this.createRectangle("Panel", 0, 0, this.panelWidth, this.panelHeight,
                this.backgroundColor, clrDimGray)
                || !this.createRectangle("TitleBackground", 1, 1, this.panelWidth - 2, 25,
                    C'56,74,104', C'56,74,104')
                || !this.createRectangle("HeaderSeparator", 12, 73, this.panelWidth - 24, 1,
                    clrDimGray, clrDimGray)
                || !this.createRectangle("FooterSeparator", 12, footerTop,
                    this.panelWidth - 24, 1, clrDimGray, clrDimGray)) {
            this.destroyObjects();

            return false;
        }

        string canvasName = this.objectPrefix + "Lines";
        if (!this.lineCanvas.CreateBitmapLabel(this.chartId, 0, canvasName,
                this.xDistance + 8, this.yDistance + this.plotTop,
                this.panelWidth - 16, this.plotHeight, COLOR_FORMAT_ARGB_NORMALIZE)) {
            this.destroyObjects();

            return false;
        }

        this.configureObject(canvasName, 0);
        ObjectSetInteger(this.chartId, canvasName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetString(this.chartId, canvasName, OBJPROP_TOOLTIP, "\n");
        if (!this.createLabel("Title", 14, 5, 11, clrWhite, "地域順位比較")
                || !this.createLabel("Status", 14, 32, 10, this.mutedColor, "WAITING DATA")
                || !this.createLabel("LeftHeader", 14, 55, 10, C'180,180,180', "LONG-MID")
                || !this.createLabel("RightHeader", this.panelWidth - 102, 55,
                    10, C'180,180,180', "MID-SHORT")
                || !this.createLabel("Footer", 14, footerTop + 9, 9, this.mutedColor,
                    "地域内の平均順位（全8通貨基準）")
                || !this.createLabel("Hint", 14, footerTop + 30, 9, this.mutedColor,
                    "実線：差2以内 / 破線：差3以上")
                || !this.createClearButton()) {
            this.destroyObjects();

            return false;
        }

        ObjectSetString(this.chartId, this.objectPrefix + "LeftHeader", OBJPROP_TOOLTIP,
            "長中期：所属通貨の長中期順位を単純平均");
        ObjectSetString(this.chartId, this.objectPrefix + "RightHeader", OBJPROP_TOOLTIP,
            "中短期：所属通貨の中短期順位を単純平均");
        ObjectSetString(this.chartId, this.objectPrefix + "Hint", OBJPROP_TOOLTIP,
            "長中期・中短期とも地域内順位差2以内なら実線。どちらかが3以上なら破線。");
        for (int i = 0; i < 4; i++) {
            if (!this.createLabel("Left" + IntegerToString(i), 10, this.plotTop + 2,
                    9, this.regionColors[i], " ")
                    || !this.createLabel("Right" + IntegerToString(i), 182, this.plotTop + 2,
                        9, this.regionColors[i], " ")) {
                this.destroyObjects();

                return false;
            }
        }

        this.created = true;

        return true;
    }

    /**
     * 保持済み平均順位からラベル・接続線・選択状態を描画する。
     */
    void render() {
        if (!this.created || !this.renderPending) {
            return;
        }

        string status = "WAITING DATA";
        color statusColor = clrGold;
        if (this.rankingReady) {
            status = "4地域・通貨順位の平均";
            statusColor = this.mutedColor;
            if (this.selectedRegion >= 0) {
                status = "選択：" + this.regionNames[this.selectedRegion];
                statusColor = clrWhite;
            }
        }

        ObjectSetString(this.chartId, this.objectPrefix + "Status", OBJPROP_TEXT, status);
        ObjectSetInteger(this.chartId, this.objectPrefix + "Status", OBJPROP_COLOR, statusColor);
        color clearColor = this.mutedColor;
        if (this.selectedRegion >= 0) {
            clearColor = clrWhite;
        }

        ObjectSetInteger(this.chartId, this.objectPrefix + "ClearSelection", OBJPROP_COLOR, clearColor);
        this.lineCanvas.Erase(0);
        for (int i = 0; i < 4; i++) {
            string leftText = " ";
            string rightText = " ";
            string tooltip = "\n";
            color labelColor = this.regionColors[i];
            if (this.rankingReady) {
                leftText = StringFormat("%.1f %s", this.leftMeans[i], this.regionNames[i]);
                rightText = StringFormat("%.1f %s", this.rightMeans[i], this.regionNames[i]);
                tooltip = this.regionTooltips[i];
                ObjectSetInteger(this.chartId, this.getLabelName(true, i), OBJPROP_YDISTANCE,
                    this.yDistance + this.leftLabelPoints[i] - 8);
                ObjectSetInteger(this.chartId, this.getLabelName(false, i), OBJPROP_YDISTANCE,
                    this.yDistance + this.rightLabelPoints[i] - 8);
                if (this.selectedRegion >= 0 && this.selectedRegion != i) {
                    labelColor = this.mutedColor;
                }
            }

            ObjectSetString(this.chartId, this.getLabelName(true, i), OBJPROP_TEXT, leftText);
            ObjectSetString(this.chartId, this.getLabelName(false, i), OBJPROP_TEXT, rightText);
            ObjectSetString(this.chartId, this.getLabelName(true, i), OBJPROP_TOOLTIP, tooltip);
            ObjectSetString(this.chartId, this.getLabelName(false, i), OBJPROP_TOOLTIP, tooltip);
            ObjectSetInteger(this.chartId, this.getLabelName(true, i), OBJPROP_COLOR, labelColor);
            ObjectSetInteger(this.chartId, this.getLabelName(false, i), OBJPROP_COLOR, labelColor);
        }

        if (this.rankingReady) {
            for (int i = 0; i < 8; i++) {
                if (this.rankPoints[i] < 0) {
                    continue;
                }

                this.lineCanvas.LineHorizontal(96, 168,
                    this.rankPoints[i] - this.plotTop, ColorToARGB(clrDimGray, 65));
            }

            for (int i = 0; i < 4; i++) {
                if (i != this.selectedRegion) {
                    this.drawConnection(i);
                }
            }

            if (this.selectedRegion >= 0) {
                this.drawConnection(this.selectedRegion);
            }
        }

        this.lineCanvas.Update(false);
        this.renderPending = false;
    }

    /**
     * 地域の接続線と、重なりを避けたラベルへの引き出し線を描く。
     *
     * @param fromRegionIndex 地域番号。
     */
    void drawConnection(const int fromRegionIndex) {
        uchar opacity = 230;
        if (this.selectedRegion >= 0 && this.selectedRegion != fromRegionIndex) {
            opacity = 55;
        }

        uint lineColor = ColorToARGB(this.regionColors[fromRegionIndex], opacity);
        uint lineStyle = STYLE_SOLID;
        if (this.leftSpans[fromRegionIndex] > 2 || this.rightSpans[fromRegionIndex] > 2) {
            lineStyle = STYLE_DASH;
        }

        int leftPoint = this.leftPoints[fromRegionIndex] - this.plotTop;
        int rightPoint = this.rightPoints[fromRegionIndex] - this.plotTop;
        int leftLabelPoint = this.leftLabelPoints[fromRegionIndex] - this.plotTop;
        int rightLabelPoint = this.rightLabelPoints[fromRegionIndex] - this.plotTop;
        this.lineCanvas.LineAA(92, leftLabelPoint, 96, leftPoint, lineColor, STYLE_SOLID);
        this.lineCanvas.LineAA(168, rightPoint, 172, rightLabelPoint, lineColor, STYLE_SOLID);
        int radius = 2;
        if (this.selectedRegion == fromRegionIndex) {
            this.lineCanvas.LineAA(96, leftPoint - 1, 168, rightPoint - 1, lineColor, lineStyle);
            this.lineCanvas.LineAA(96, leftPoint + 1, 168, rightPoint + 1, lineColor, lineStyle);
            radius = 3;
        }

        this.lineCanvas.LineAA(96, leftPoint, 168, rightPoint, lineColor, lineStyle);
        this.lineCanvas.FillCircle(96, leftPoint, radius, lineColor);
        this.lineCanvas.FillCircle(168, rightPoint, radius, lineColor);
    }

    /**
     * 地域ラベルの専用オブジェクト名を取得する。
     *
     * @param fromLeft 長中期側の場合true。
     * @param fromRegionIndex 地域番号。
     * @return オブジェクト名。
     */
    string getLabelName(const bool fromLeft, const int fromRegionIndex) const {
        string side = "Right";
        if (fromLeft) {
            side = "Left";
        }

        return this.objectPrefix + side + IntegerToString(fromRegionIndex);
    }

    /**
     * 固定位置の背景矩形を生成する。
     *
     * @return 生成できた場合true。
     */
    bool createRectangle(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromWidth, const int fromHeight, const color fromBackground,
            const color fromBorder) {
        string objectName = this.objectPrefix + fromSuffix;
        if (!ObjectCreate(this.chartId, objectName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        this.configureObject(objectName, 0);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, this.xDistance + fromLeft);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + fromTop);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, fromBackground);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromBorder);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, "\n");

        return true;
    }

    /**
     * 固定文字ラベルを生成する。
     *
     * @return 生成できた場合true。
     */
    bool createLabel(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromFontSize, const color fromColor, const string fromText) {
        string objectName = this.objectPrefix + fromSuffix;
        if (!ObjectCreate(this.chartId, objectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        this.configureObject(objectName, 2);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, this.xDistance + fromLeft);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + fromTop);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, fromFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, "\n");

        return true;
    }

    /**
     * 地域選択だけを解除するボタンを生成する。
     *
     * @return 生成できた場合true。
     */
    bool createClearButton() {
        string objectName = this.objectPrefix + "ClearSelection";
        if (!ObjectCreate(this.chartId, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return false;
        }

        this.configureObject(objectName, 3);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE,
            this.xDistance + this.panelWidth - 66);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + 29);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, 52);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, 22);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, this.mutedColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, C'35,35,35');
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_COLOR, clrDimGray);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, "解除");
        ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, "地域の強調を解除します");

        return true;
    }

    /**
     * 固定パネル用の属性とクリック優先度を設定する。
     *
     * @param fromObjectName 対象オブジェクト名。
     * @param fromZOrder クリック優先度。
     */
    void configureObject(const string fromObjectName, const int fromZOrder) {
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ZORDER, fromZOrder);
    }

    /**
     * 再生成時に順位・選択を保持したまま、所有する描画だけを解放する。
     */
    void destroyObjects() {
        this.lineCanvas.Destroy();
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.renderPending = true;
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_REGION_RANK_COMPARISON_MQH
