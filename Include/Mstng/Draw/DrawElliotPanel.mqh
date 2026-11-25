#ifndef MSTNG_DRAW_ELLIOT_PANEL_MQH
#define MSTNG_DRAW_ELLIOT_PANEL_MQH

#include <Mstng\Draw\DrawElliotTable.mqh>
#include <Mstng\Draw\ElliotPanelData.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * パネル内で完結する操作と、保存履歴側へ渡す移動操作を区別する。
 */
enum ENUM_ELLIOT_PANEL_ACTION {
    ELLIOT_PANEL_ACTION_NONE,
    ELLIOT_PANEL_ACTION_HANDLED,
    ELLIOT_PANEL_ACTION_PREVIOUS,
    ELLIOT_PANEL_ACTION_NEXT,
    ELLIOT_PANEL_ACTION_CLOSED
};

/**
 * 現在値と保存波動を一枚で切り替える共通パネル。
 * データ取得・分析は行わず、表示内容と選択・開閉状態を独立して保持する。
 */
class DrawElliotPanel {
public:
    /**
     * 現在モード・一覧表示で初期化する。
     */
    DrawElliotPanel(const long fromChartId, const string fromPrefix) {
        this.chartId = fromChartId;
        this.prefix = fromPrefix;
        this.visible = true;
        this.expanded = false;
        this.savedMode = false;
        this.selectedTimeFrame = PERIOD_M5;
        this.panelLeft = 0;
        this.panelTop = 0;
        this.panelWidth = 0;
        this.panelHeight = 0;
        this.drawingSucceeded = true;
    }

    /**
     * 自分が所有するパネルだけを解放する。
     */
    ~DrawElliotPanel() {
        this.clear();
    }

    /**
     * 最新表示値を更新する。保存表示中は保存内容と選択状態を変えない。
     */
    bool updateLive(const ElliotPanelData &fromData) {
        this.liveData = fromData;
        if (this.savedMode || !this.visible) {
            return true;
        }

        return this.draw();
    }

    /**
     * 保存キャッシュだけを更新し、開閉・展開・表示モードを維持する。
     */
    bool updateSaved(const ElliotPanelData &fromData) {
        this.savedData = fromData;
        if (!this.savedMode || !this.visible) {
            return true;
        }

        return this.draw();
    }

    /**
     * 保存値へ切り替える。初回だけ詳細を展開し、前後移動では展開状態を保つ。
     */
    bool showSaved(const ElliotPanelData &fromData) {
        if (!this.savedMode) {
            this.expanded = true;
        }

        this.savedData = fromData;
        this.savedMode = true;
        this.visible = true;

        return this.draw();
    }

    /**
     * 最新のキャッシュへ戻り、選択時間足と展開状態を維持する。
     */
    bool showLive() {
        this.savedMode = false;
        this.visible = true;

        return this.draw();
    }

    /**
     * パネルの表示・非表示を切り替える。
     */
    void setVisible(const bool fromVisible) {
        this.visible = fromVisible;
        this.draw();
    }

    /**
     * 詳細欄の展開状態を設定する。
     */
    void setExpanded(const bool fromExpanded) {
        this.expanded = fromExpanded;
        this.draw();
    }

    /**
     * パネルの表示状態を返す。
     */
    bool isVisible() { return this.visible; }

    /**
     * 詳細欄の展開状態を返す。
     */
    bool isExpanded() { return this.expanded; }

    /**
     * 保存表示中の場合trueを返す。
     */
    bool isSavedMode() { return this.savedMode; }

    /**
     * 選択された保存時刻を返す。現在表示中は0。
     */
    datetime getSavedTime() {
        if (!this.savedMode) {
            return 0;
        }

        return this.savedData.savedTime;
    }

    /**
     * 選択時間足を返す。
     */
    int getSelectedTimeFrame() { return this.selectedTimeFrame; }

    /**
     * パネルの背後にある目印のホバーを抑止する。
     */
    bool containsPoint(const int fromX, const int fromY) {
        return this.visible && this.panelWidth > 0 && this.panelHeight > 0
            && fromX >= this.panelLeft && fromX < this.panelLeft + this.panelWidth
            && fromY >= this.panelTop && fromY < this.panelTop + this.panelHeight;
    }

    /**
     * 描画オブジェクトだけを消す。キャッシュと操作状態は維持する。
     */
    void clear() {
        if (StringLen(this.prefix) > 0) {
            ObjectsDeleteAll(this.chartId, this.prefix, 0, -1);
        }

        this.panelWidth = 0;
        this.panelHeight = 0;
    }

    /**
     * 枠・操作・一覧・項目別詳細・通貨強弱を同じレイアウトで描画する。
     */
    bool draw() {
        this.clear();
        if (!this.visible || StringLen(this.prefix) == 0) {
            return true;
        }

        ElliotPanelData data = this.liveData;
        if (this.savedMode) {
            data = this.savedData;
        }

        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS, 0);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        this.panelLeft = 12;
        this.panelTop = 12;
        this.panelWidth = MathMin(960, chartWidth - 24);
        int availableHeight = chartHeight - 24;
        if (this.panelWidth < 160 || availableHeight < 80) {
            this.panelWidth = 0;

            return false;
        }

        int rowCount = MathMax(0, MathMin(8, data.rowCount));
        int selectedIndex = this.resolveSelectedIndex(data);
        int headerHeight = 80;
        if (this.panelWidth < 760) {
            headerHeight = 104;
        }

        int rowHeight = 24;
        int detailRowHeight = 22;
        int detailColumns = 3;
        if (this.panelWidth < 960) {
            detailColumns = 2;
        }

        int extraCount = 0;
        if (selectedIndex >= 0) {
            extraCount = MathMax(0, MathMin(8, data.frames[selectedIndex].extraCount));
        }

        int extraRows = (extraCount + detailColumns - 1) / detailColumns;
        int detailHeight = 28 + (12 / detailColumns) * detailRowHeight + 82;
        if (extraCount > 0) {
            detailHeight += 20 + extraRows * detailRowHeight;
        }

        int listHeight = headerHeight + (rowCount + 1) * rowHeight + 26;
        if (this.expanded && listHeight + detailHeight > availableHeight) {
            rowHeight = 20;
            detailRowHeight = 18;
            detailHeight = 26 + (12 / detailColumns) * detailRowHeight + 76;
            if (extraCount > 0) {
                detailHeight += 20 + extraRows * detailRowHeight;
            }

            listHeight = headerHeight + (rowCount + 1) * rowHeight + 26;
        }

        bool showDetails = this.expanded && selectedIndex >= 0
            && listHeight + detailHeight <= availableHeight && this.panelWidth >= 640;
        int desiredHeight = listHeight;
        if (showDetails) {
            desiredHeight += detailHeight;
        }

        this.panelHeight = MathMin(availableHeight, MathMax(140, desiredHeight));
        this.drawingSucceeded = true;
        this.drawBackground("Background", this.panelLeft, this.panelTop,
            this.panelWidth, this.panelHeight, C'25,31,41', 30);
        this.drawHeader(data, headerHeight);
        if (rowCount == 0) {
            string message = data.status;
            if (StringLen(message) == 0) {
                message = "分析結果を待っています。";
            }

            this.drawText("Empty", message, this.panelLeft + 12, this.panelTop + headerHeight + 6,
                this.panelWidth - 24, 11, clrSilver);

            return this.drawingSucceeded;
        }

        int tableTop = this.panelTop + headerHeight;
        int requiredListHeight = headerHeight + (rowCount + 1) * rowHeight + 24;
        if (this.panelWidth < 640 || requiredListHeight > this.panelHeight) {
            this.drawText("Small", "一覧を見るにはチャートを広げてください。",
                this.panelLeft + 12, tableTop + 6, this.panelWidth - 24, 11, clrSilver);

            return this.drawingSucceeded;
        }

        this.drawTable(data, rowCount, tableTop, rowHeight);
        if (showDetails) {
            int detailTop = tableTop + (rowCount + 1) * rowHeight + 8;
            this.drawDetails(data.frames[selectedIndex], data.digits, detailTop,
                detailColumns, detailRowHeight);
            int strengthTop = detailTop + 24 + (12 / detailColumns) * detailRowHeight;
            this.drawStrength(data.strength, strengthTop, this.panelWidth - 24);
            if (extraCount > 0) {
                this.drawExtras(data.frames[selectedIndex], strengthTop + 76,
                    detailColumns, detailRowHeight);
            }
        }

        string hint = data.hint;
        if (this.expanded && !showDetails) {
            hint = "詳細を見るにはチャートを広げるか、サブウィンドウを縮めてください。";
        } else if (StringLen(hint) == 0) {
            hint = "行をクリックして時間足を選択 / 詳細ボタンで展開・折り畳み";
        }

        this.drawText("Hint", hint, this.panelLeft + 12,
            this.panelTop + this.panelHeight - 20, this.panelWidth - 24, 9, clrSilver);

        return this.drawingSucceeded;
    }

    /**
     * 自分の操作を処理し、保存の前後移動だけを呼び出し側へ返す。
     */
    ENUM_ELLIOT_PANEL_ACTION onObjectClick(const string fromName) {
        if (!this.visible || StringLen(this.prefix) == 0 || StringFind(fromName, this.prefix) != 0) {
            return ELLIOT_PANEL_ACTION_NONE;
        }

        if (fromName == this.prefix + "Close") {
            this.visible = false;
            this.clear();

            return ELLIOT_PANEL_ACTION_CLOSED;
        }

        if (fromName == this.prefix + "Live") {
            this.showLive();

            return ELLIOT_PANEL_ACTION_HANDLED;
        }

        if (fromName == this.prefix + "Expand") {
            this.expanded = !this.expanded;
            this.draw();

            return ELLIOT_PANEL_ACTION_HANDLED;
        }

        if (fromName == this.prefix + "Previous" || fromName == this.prefix + "Next") {
            ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
            if (this.savedMode && fromName == this.prefix + "Previous" && this.savedData.canPrevious) {
                return ELLIOT_PANEL_ACTION_PREVIOUS;
            }
            if (this.savedMode && fromName == this.prefix + "Next" && this.savedData.canNext) {
                return ELLIOT_PANEL_ACTION_NEXT;
            }

            return ELLIOT_PANEL_ACTION_HANDLED;
        }

        ElliotPanelData data = this.liveData;
        if (this.savedMode) {
            data = this.savedData;
        }

        int rowCount = MathMax(0, MathMin(8, data.rowCount));
        for (int i = 0; i < rowCount; i++) {
            string rowPrefix = this.prefix + "Row" + IntegerToString(data.frames[i].timeFrame) + "-";
            if (StringFind(fromName, rowPrefix) == 0) {
                this.selectedTimeFrame = data.frames[i].timeFrame;
                this.expanded = true;
                this.draw();

                return ELLIOT_PANEL_ACTION_HANDLED;
            }
        }

        return ELLIOT_PANEL_ACTION_HANDLED;
    }

private:
    /** 描画先チャート。 */
    long chartId;

    /** このパネルだけが所有する接頭辞。 */
    string prefix;

    /** 最新の分析結果の表示用キャッシュ。 */
    ElliotPanelData liveData;

    /** 選択した保存時刻の表示用キャッシュ。 */
    ElliotPanelData savedData;

    /** 表示中の場合true。 */
    bool visible;

    /** 詳細を展開する場合true。 */
    bool expanded;

    /** 保存データを表示する場合true。 */
    bool savedMode;

    /** 行番号ではなく時間足で保持する選択状態。 */
    int selectedTimeFrame;

    /** 描画したパネルの左端。 */
    int panelLeft;

    /** 描画したパネルの上端。 */
    int panelTop;

    /** 描画したパネルの幅。 */
    int panelWidth;

    /** 描画したパネルの高さ。 */
    int panelHeight;

    /** 今回の描画で全オブジェクトを作成できた場合true。 */
    bool drawingSucceeded;

    /**
     * 切替先に同じ時間足がなければM5、さらに無ければ最後の行を選択する。
     */
    int resolveSelectedIndex(const ElliotPanelData &fromData) {
        int rowCount = MathMax(0, MathMin(8, fromData.rowCount));
        int fallbackIndex = rowCount - 1;
        for (int i = 0; i < rowCount; i++) {
            if (fromData.frames[i].timeFrame == this.selectedTimeFrame) {
                return i;
            }
            if (fromData.frames[i].timeFrame == PERIOD_M5) {
                fallbackIndex = i;
            }
        }

        if (fallbackIndex >= 0) {
            this.selectedTimeFrame = fromData.frames[fallbackIndex].timeFrame;
        }

        return fallbackIndex;
    }

    /**
     * 現在・保存を明示した見出しと共通操作を描画する。
     */
    void drawHeader(const ElliotPanelData &fromData, const int fromHeaderHeight) {
        string mode = "現在";
        color modeColor = clrAqua;
        if (this.savedMode) {
            mode = "保存";
            modeColor = clrGold;
        }

        int buttonTop = this.panelTop + 6;
        int titleWidth = this.panelWidth - 390;
        int timeTop = this.panelTop + 32;
        int metadataTop = this.panelTop + 58;
        if (fromHeaderHeight > 80) {
            titleWidth = this.panelWidth - 140;
            buttonTop = this.panelTop + 32;
            timeTop = this.panelTop + 60;
            metadataTop = this.panelTop + 82;
        }

        this.drawText("Title", "Elliot / " + fromData.symbolName + " / " + mode,
            this.panelLeft + 12, this.panelTop + 9, titleWidth, 12, modeColor);
        int closeLeft = this.panelLeft + this.panelWidth - 34;
        this.drawButton("Close", "×", "パネルを閉じる", closeLeft, this.panelTop + 6, 24, true);
        string expandText = "詳細 ▼";
        if (this.expanded) {
            expandText = "一覧 ▲";
        }

        this.drawButton("Expand", expandText, "項目別詳細・通貨強弱・追加指標の表示を切り替えます。",
            closeLeft - 86, this.panelTop + 6, 80, true);
        int navigationLeft = closeLeft - 86 - 230;
        if (fromHeaderHeight > 80) {
            navigationLeft = this.panelLeft + 12;
        }

        if (this.savedMode) {
            int navigationWidth = MathMax(20, MathMin(60, (this.panelWidth - 114) / 2));
            this.drawButton("Previous", "◀ 前", "表示範囲内の古い保存データへ移動します。",
                navigationLeft, buttonTop, navigationWidth, fromData.canPrevious);
            this.drawButton("Next", "次 ▶", "表示範囲内の新しい保存データへ移動します。",
                navigationLeft + navigationWidth + 6, buttonTop, navigationWidth, fromData.canNext);
            this.drawButton("Live", "現在へ", "最新の分析結果へ戻ります。",
                navigationLeft + 2 * (navigationWidth + 6), buttonTop, 78, true);
        }

        this.drawText("Time", fromData.headerTime, this.panelLeft + 12, timeTop,
            this.panelWidth - 24, 12, clrWhite);
        string metadata = fromData.metadata;
        if (StringLen(fromData.status) > 0 && fromData.rowCount > 0) {
            metadata = fromData.status + " / " + metadata;
        }

        this.drawText("Metadata", metadata, this.panelLeft + 12, metadataTop,
            this.panelWidth - 24, 9, clrSilver);
    }

    /**
     * 可変行数の一覧を共通表描画へ渡す。
     */
    void drawTable(const ElliotPanelData &fromData, const int fromRowCount,
            const int fromTop, const int fromRowHeight) {
        ElliotTableLayout layout;
        layout.originX = this.panelLeft + 12;
        layout.originY = fromTop;
        layout.paddingX = 6;
        layout.paddingY = 3;
        layout.rowHeight = fromRowHeight;
        layout.showBackground = true;
        layout.showSeparators = false;
        layout.clipText = true;
        layout.headerColor = clrWhiteSmoke;
        layout.backgroundColor = C'38,47,62';
        layout.backgroundZOrder = 31;
        layout.textZOrder = 32;
        int widths[] = {80, 80, 80, 120, this.panelWidth - 384};
        int positionX = 0;
        for (int i = 0; i < 5; i++) {
            layout.columnXs[i] = positionX;
            layout.columnWidths[i] = widths[i];
            layout.columnFontSizes[i] = 11;
            if (fromRowHeight < 24) {
                layout.columnFontSizes[i] = 10;
            }

            positionX += widths[i];
        }

        bool drawn = DrawElliotTable::drawHeader(this.chartId, this.prefix + "Header", layout);
        this.drawingSucceeded = drawn && this.drawingSucceeded;
        layout.showSeparators = true;
        for (int i = 0; i < fromRowCount; i++) {
            layout.originY = fromTop + (i + 1) * fromRowHeight;
            layout.backgroundColor = C'25,31,41';
            if (i % 2 == 1) {
                layout.backgroundColor = C'31,38,49';
            }
            if (fromData.frames[i].timeFrame == this.selectedTimeFrame) {
                layout.backgroundColor = C'42,59,83';
            }

            string rowPrefix = this.prefix + "Row" + IntegerToString(fromData.frames[i].timeFrame) + "-";
            layout.tooltips[3] = fromData.frames[i].movementTooltip;
            drawn = DrawElliotTable::drawRow(this.chartId, rowPrefix, fromData.frames[i].row,
                fromData.digits, fromData.palette, layout);
            this.drawingSucceeded = drawn && this.drawingSucceeded;
        }
    }

    /**
     * 選択行の12項目を現在・保存で同じ順序に表示する。
     */
    void drawDetails(const ElliotPanelFrame &fromFrame, const int fromDigits, const int fromTop,
            const int fromColumns, const int fromRowHeight) {
        this.drawText("DetailTitle", fromFrame.row.timeFrameLabel + " の詳細",
            this.panelLeft + 12, fromTop, this.panelWidth - 24, 11, clrWhiteSmoke);
        string labels[] = {"主波", "副次波", "元波", "確定状態", "補完状態", "前推進波の副",
            "F", "FE", "値幅", "ポイント価格", "ポイント時刻", "波動方向"};
        int itemWidth = (this.panelWidth - 24) / fromColumns;
        for (int i = 0; i < 12; i++) {
            int positionX = this.panelLeft + 12 + (i % fromColumns) * itemWidth;
            int positionY = fromTop + 24 + (i / fromColumns) * fromRowHeight;
            string value = detailValue(fromFrame, i, fromDigits);
            this.drawText("DetailLabel" + IntegerToString(i), labels[i], positionX, positionY, 100, 10, clrSilver);
            this.drawText("DetailValue" + IntegerToString(i), value, positionX + 104,
                positionY, itemWidth - 112, 10, clrWhiteSmoke, labels[i] + ": " + value);
        }
    }

    /**
     * 追加オシレーターを選択行の詳細末尾へ表示する。
     */
    void drawExtras(const ElliotPanelFrame &fromFrame, const int fromTop,
            const int fromColumns, const int fromRowHeight) {
        this.drawText("ExtraTitle", "追加指標", this.panelLeft + 12, fromTop,
            this.panelWidth - 24, 10, clrWhiteSmoke);
        int itemWidth = (this.panelWidth - 24) / fromColumns;
        int count = MathMax(0, MathMin(8, fromFrame.extraCount));
        for (int i = 0; i < count; i++) {
            int positionX = this.panelLeft + 12 + (i % fromColumns) * itemWidth;
            int positionY = fromTop + 20 + (i / fromColumns) * fromRowHeight;
            this.drawText("ExtraLabel" + IntegerToString(i), fromFrame.extraLabels[i],
                positionX, positionY, 100, 10, clrSilver);
            this.drawText("ExtraValue" + IntegerToString(i), fromFrame.extraValues[i],
                positionX + 104, positionY, itemWidth - 112, 10, fromFrame.extraColors[i]);
        }
    }

    /**
     * 取得元を明示した長中期・中短期の通貨強弱を描画する。
     */
    void drawStrength(const ElliotPanelStrength &fromStrength, const int fromTop, const int fromWidth) {
        this.drawText("StrengthTitle", fromStrength.title, this.panelLeft + 12, fromTop,
            fromWidth, 10, clrWhiteSmoke, fromStrength.tooltip);
        string status = fromStrength.status;
        if (!fromStrength.enabled) {
            status = "通貨強弱OFF";
        }
        if (status != "取得済み" && StringLen(status) > 0) {
            this.drawText("StrengthStatus", status, this.panelLeft + 12, fromTop + 24,
                fromWidth, 10, clrSilver, fromStrength.tooltip);

            return;
        }

        int width = MathMin(620, fromWidth);
        string headers[] = {"期間", fromStrength.baseCurrency, fromStrength.quoteCurrency, "順位差", "前M5比"};
        int itemWidth = width / 5;
        for (int i = 0; i < 5; i++) {
            this.drawText("StrengthHeader" + IntegerToString(i), headers[i],
                this.panelLeft + 12 + i * itemWidth, fromTop + 20, itemWidth - 6, 9, clrSilver);
        }

        this.drawStrengthRow(fromStrength.longMedium, "長中期", "LongMedium", fromTop + 38, itemWidth);
        this.drawStrengthRow(fromStrength.mediumShort, "中短期", "MediumShort", fromTop + 56, itemWidth);
    }

    /**
     * 順位差と前M5比を独立した色で表示する。
     */
    void drawStrengthRow(const ElliotPanelStrengthPeriod &fromPeriod, const string fromTitle,
            const string fromKey, const int fromTop, const int fromWidth) {
        string values[5];
        values[0] = fromTitle;
        values[1] = "未記録";
        values[2] = "未記録";
        values[3] = "未記録";
        values[4] = "未記録";
        if (fromPeriod.valid) {
            values[1] = IntegerToString(fromPeriod.baseRank) + "位";
            values[2] = IntegerToString(fromPeriod.quoteRank) + "位";
            values[3] = StringFormat("%+d", fromPeriod.gap);
            values[4] = "比較なし";
            if (fromPeriod.comparable) {
                values[4] = "→ 0";
                if (fromPeriod.delta > 0) {
                    values[4] = StringFormat("↑ +%d", fromPeriod.delta);
                } else if (fromPeriod.delta < 0) {
                    values[4] = StringFormat("↓ %d", fromPeriod.delta);
                }
            }
        }

        for (int i = 0; i < 5; i++) {
            color textColor = clrWhiteSmoke;
            if (!fromPeriod.valid && i > 0) {
                textColor = clrSilver;
            }
            if (i == 3) {
                textColor = strengthColor(fromPeriod.gap, fromPeriod.valid);
            }
            if (i == 4) {
                textColor = strengthColor(fromPeriod.delta, fromPeriod.valid && fromPeriod.comparable);
            }

            this.drawText("Strength" + fromKey + IntegerToString(i), values[i],
                this.panelLeft + 12 + i * fromWidth, fromTop, fromWidth - 6, 10, textColor);
        }
    }

    /**
     * 保存の欠損と取得済みゼロを区別して詳細値を整形する。
     */
    static string detailValue(const ElliotPanelFrame &fromFrame, const int fromIndex, const int fromDigits) {
        if (!fromFrame.row.hasData) {
            return "未記録";
        }

        if (fromIndex == 0) {
            return recordedText(fromFrame.row.mainWave);
        }
        if (fromIndex == 1) {
            if (StringLen(fromFrame.row.subWave) == 0) {
                return "なし";
            }

            return fromFrame.row.subWave;
        }
        if (fromIndex == 2) {
            return recordedText(fromFrame.row.originalWave);
        }
        if (fromIndex == 3) {
            return stateText(fromFrame.row.isConfirmed, "確定", "未確定");
        }
        if (fromIndex == 4) {
            return stateText(fromFrame.row.isAdded, "補完 ★", "通常");
        }
        if (fromIndex == 5) {
            if (fromFrame.row.previousMotiveSubElliotIndex < 0) {
                return "未記録";
            }
            if (fromFrame.row.previousMotiveSubElliotIndex == 0) {
                return "なし";
            }

            return IntegerToString(fromFrame.row.previousMotiveSubElliotIndex) + "副";
        }
        if (fromIndex == 6) {
            return numberText(fromFrame.row.pointFibonacciPercent, fromFrame.row.hasPointFibonacciPercent, 1, "%");
        }
        if (fromIndex == 7) {
            return numberText(fromFrame.row.pointFibonacciExpansionPercent,
                fromFrame.row.hasPointFibonacciExpansionPercent, 1, "%");
        }
        if (fromIndex == 8) {
            return numberText(fromFrame.row.pointPipsDiff, fromFrame.row.hasPointPipsDiff, 1, " pips");
        }
        if (fromIndex == 9) {
            return numberText(fromFrame.row.pointRate, fromFrame.row.hasPointRate, fromDigits, "");
        }
        if (fromIndex == 10) {
            if (fromFrame.pointJstTime > 0) {
                return "JST " + TimeUtil::formatYyyymmddhhmiss(fromFrame.pointJstTime);
            }
            if (fromFrame.pointTime > 0) {
                return "SRV " + TimeUtil::formatYyyymmddhhmiss(fromFrame.pointTime);
            }

            return "未記録";
        }
        if (fromIndex == 11) {
            return stateText(fromFrame.row.isUptrend, "上昇 ▲", "下降 ▼");
        }

        return "";
    }

    /**
     * 未取得状態を維持した数値を返す。
     */
    static string numberText(const double fromValue, const bool fromHasValue,
            const int fromDigits, const string fromSuffix) {
        if (!fromHasValue) {
            return "未記録";
        }

        return DoubleToString(fromValue, fromDigits) + fromSuffix;
    }

    /**
     * 空または未設定のラベルを未記録へ変換する。
     */
    static string recordedText(const string fromText) {
        if (StringLen(fromText) == 0) {
            return "未記録";
        }

        return fromText;
    }

    /**
     * 三状態のフラグを表示名へ変換する。
     */
    static string stateText(const int fromValue, const string fromTrue, const string fromFalse) {
        if (fromValue == 1) {
            return fromTrue;
        }
        if (fromValue == 0) {
            return fromFalse;
        }

        return "未記録";
    }

    /**
     * 順位差・増減の正負と欠損を色へ変換する。
     */
    static color strengthColor(const int fromValue, const bool fromValid) {
        if (!fromValid) {
            return clrSilver;
        }
        if (fromValue > 0) {
            return clrAqua;
        }
        if (fromValue < 0) {
            return clrHotPink;
        }

        return clrWhite;
    }

    /**
     * セル幅に収まる文字を描画し、全文をツールチップへ保持する。
     */
    void drawText(const string fromKey, const string fromText, const int fromX, const int fromY,
            const int fromWidth, const int fromSize, const color fromColor, const string fromTooltip = "") {
        string text = DrawElliotTable::fitText(fromText, fromWidth, "MS Gothic", fromSize);
        if (StringLen(text) == 0) {
            return;
        }

        string name = this.prefix + fromKey;
        if (!ObjectCreate(this.chartId, name, OBJ_LABEL, 0, 0, 0)) {
            this.drawingSucceeded = false;
            return;
        }

        string tooltip = fromTooltip;
        if (StringLen(tooltip) == 0) {
            tooltip = fromText;
        }
        if (StringLen(tooltip) > 159) {
            tooltip = StringSubstr(tooltip, 0, 158) + "…";
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, fromColor)
            && ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, fromSize)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 32)
            && ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic")
            && ObjectSetString(this.chartId, name, OBJPROP_TEXT, text)
            && ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, tooltip);
        this.drawingSucceeded = success && this.drawingSucceeded;
    }

    /**
     * 枠の背景を描画する。
     */
    void drawBackground(const string fromKey, const int fromX, const int fromY, const int fromWidth,
            const int fromHeight, const color fromColor, const long fromZOrder) {
        string name = this.prefix + fromKey;
        if (!ObjectCreate(this.chartId, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            this.drawingSucceeded = false;
            return;
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, fromWidth)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, fromHeight)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, fromColor)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BORDER_TYPE, BORDER_FLAT)
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, clrSlateGray)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, fromZOrder)
            && ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, "\n");
        this.drawingSucceeded = success && this.drawingSucceeded;
    }

    /**
     * 共通操作ボタンを描画し、無効な移動先は灰色で表示する。
     */
    void drawButton(const string fromKey, const string fromText, const string fromTooltip,
            const int fromX, const int fromY, const int fromWidth, const bool fromEnabled) {
        string name = this.prefix + fromKey;
        if (!ObjectCreate(this.chartId, name, OBJ_BUTTON, 0, 0, 0)) {
            this.drawingSucceeded = false;
            return;
        }

        color textColor = clrWhiteSmoke;
        if (!fromEnabled) {
            textColor = clrGray;
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, fromWidth)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, 22)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, C'45,53,66')
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, textColor)
            && ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 9)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(this.chartId, name, OBJPROP_STATE, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 33)
            && ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic")
            && ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText)
            && ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, fromTooltip);
        this.drawingSucceeded = success && this.drawingSucceeded;
    }
};

#endif // MSTNG_DRAW_ELLIOT_PANEL_MQH
