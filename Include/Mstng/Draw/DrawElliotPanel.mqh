#ifndef MSTNG_DRAW_ELLIOT_PANEL_MQH
#define MSTNG_DRAW_ELLIOT_PANEL_MQH

#include <Mstng\Draw\DrawElliotTable.mqh>
#include <Mstng\Draw\ElliotPanelData.mqh>
#include <Mstng\Draw\ElliotPanelLayout.mqh>
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
        this.objectPrefix = fromPrefix;
        this.objects = new DrawChartObjectRegistry();
        this.previousObjects = NULL;
        this.previousObjectPrefix = "";
        this.drawBatchDepth = 0;
        this.drawPending = false;
        this.frontPending = false;
        this.previousPanelWidth = 0;
        this.previousPanelHeight = 0;
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
        if (this.objects != NULL) {
            delete this.objects;
        }
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
     * 現在表示中の世代に使うオブジェクト接頭辞を返す。
     */
    string getObjectPrefix() { return this.objectPrefix; }

    /**
     * 複数の更新要求を一回の描画へまとめる。
     */
    void beginDrawBatch() {
        this.drawBatchDepth++;
    }

    /**
     * 最外の更新区間を抜けた時だけ保留した描画を反映する。
     */
    bool endDrawBatch() {
        if (this.drawBatchDepth <= 0) {
            return true;
        }

        this.drawBatchDepth--;
        if (this.drawBatchDepth == 0 && this.drawPending) {
            return this.draw();
        }

        return true;
    }

    /**
     * 後から作成されたチャート要素より手前へ、完成した次世代を配置する。
     */
    bool requestBringToFront() {
        this.frontPending = true;

        return this.draw();
    }

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
        if (this.objects != NULL) {
            this.objects.clear();
        }
        if (this.previousObjects != NULL) {
            this.previousObjects.clear();
            delete this.previousObjects;
            this.previousObjects = NULL;
        }

        this.objectPrefix = this.prefix;
        this.previousObjectPrefix = "";
        this.drawPending = false;
        this.frontPending = false;
        this.panelWidth = 0;
        this.panelHeight = 0;
    }

    /**
     * 枠・操作・一覧・項目別詳細・通貨強弱を同じレイアウトで描画する。
     */
    bool draw() {
        if (this.drawBatchDepth > 0) {
            this.drawPending = true;

            return true;
        }

        this.drawPending = false;
        if (!this.visible || StringLen(this.prefix) == 0) {
            this.clear();

            return true;
        }

        ElliotPanelData data = this.liveData;
        if (this.savedMode) {
            data = this.savedData;
        }

        this.previousPanelWidth = this.panelWidth;
        this.previousPanelHeight = this.panelHeight;
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS, 0);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        ElliotPanelLayout layout;
        bool sizeAvailable = layout.setChartSize(chartWidth, chartHeight);
        this.panelLeft = layout.panelLeft;
        this.panelTop = layout.panelTop;
        this.panelWidth = layout.panelWidth;
        if (!sizeAvailable) {
            this.clear();

            return false;
        }

        int selectedIndex = this.resolveSelectedIndex(data);
        int extraCount = 0;
        if (selectedIndex >= 0) {
            extraCount = data.frames[selectedIndex].extraCount;
        }

        layout.calculate(data.rowCount, selectedIndex >= 0, extraCount, this.expanded);
        this.panelHeight = layout.panelHeight;
        if (!this.prepareObjects(data, layout.rowCount, layout.showTable)) {
            this.panelWidth = this.previousPanelWidth;
            this.panelHeight = this.previousPanelHeight;
            this.drawPending = true;

            return false;
        }

        this.drawingSucceeded = true;
        this.drawBackground("Background", this.panelLeft, this.panelTop,
            this.panelWidth, this.panelHeight, C'25,31,41', 30);
        this.drawHeader(data, layout);
        if (layout.rowCount == 0) {
            string message = data.status;
            if (StringLen(message) == 0) {
                message = "分析結果を待っています。";
            }

            this.drawText("Empty", message, layout.contentLeft, layout.getMessageTop(),
                layout.contentWidth, 11, clrSilver);

            return this.completeDraw();
        }

        if (!layout.showTable) {
            this.drawText("Small", "一覧を見るにはチャートを広げてください。",
                layout.contentLeft, layout.getMessageTop(), layout.contentWidth, 11, clrSilver);

            return this.completeDraw();
        }

        this.drawTable(data, layout);
        if (layout.showDetails) {
            this.drawDetails(data.frames[selectedIndex], data.digits, layout);
            this.drawStrength(data.strength, layout);
            if (layout.extraCount > 0) {
                this.drawExtras(data.frames[selectedIndex], layout);
            }
        }

        string hint = data.hint;
        if (this.expanded && !layout.showDetails) {
            hint = "詳細を見るにはチャートを広げるか、サブウィンドウを縮めてください。";
        } else if (StringLen(hint) == 0) {
            hint = "行をクリックして時間足を選択 / 詳細ボタンで展開・折り畳み";
        }

        this.drawText("Hint", hint, layout.contentLeft,
            layout.hintTop, layout.contentWidth, 9, clrSilver);

        return this.completeDraw();
    }

    /**
     * 自分の操作を処理し、保存の前後移動だけを呼び出し側へ返す。
     */
    ENUM_ELLIOT_PANEL_ACTION onObjectClick(const string fromName) {
        if (!this.visible || StringLen(this.objectPrefix) == 0 || StringFind(fromName, this.objectPrefix) != 0) {
            return ELLIOT_PANEL_ACTION_NONE;
        }

        if (fromName == this.objectPrefix + "Close") {
            this.visible = false;
            this.clear();

            return ELLIOT_PANEL_ACTION_CLOSED;
        }

        if (fromName == this.objectPrefix + "Live") {
            this.showLive();

            return ELLIOT_PANEL_ACTION_HANDLED;
        }

        if (fromName == this.objectPrefix + "Expand") {
            this.expanded = !this.expanded;
            this.draw();

            return ELLIOT_PANEL_ACTION_HANDLED;
        }

        if (fromName == this.objectPrefix + "Previous" || fromName == this.objectPrefix + "Next") {
            ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
            if (this.savedMode && fromName == this.objectPrefix + "Previous" && this.savedData.canPrevious) {
                return ELLIOT_PANEL_ACTION_PREVIOUS;
            }
            if (this.savedMode && fromName == this.objectPrefix + "Next" && this.savedData.canNext) {
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
            string rowPrefix = this.objectPrefix + "Row" + IntegerToString(data.frames[i].timeFrame) + "-";
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

    /** 現在描画する世代の接頭辞。 */
    string objectPrefix;

    /** 現在の世代が所有する描画要素。 */
    DrawChartObjectRegistry *objects;

    /** 新世代が完成するまで保持する旧世代。 */
    DrawChartObjectRegistry *previousObjects;

    /** 新世代の作成に失敗した場合に戻す接頭辞。 */
    string previousObjectPrefix;

    /** 描画を保留する更新区間の深さ。 */
    int drawBatchDepth;

    /** 更新区間の終了時に描画する場合true。 */
    bool drawPending;

    /** 新しい世代で前面へ配置する場合true。 */
    bool frontPending;

    /** 新世代の作成に失敗した場合に戻す表示幅。 */
    int previousPanelWidth;

    /** 新世代の作成に失敗した場合に戻す表示高さ。 */
    int previousPanelHeight;

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
     * 背景を追加する時と前面化する時だけ、旧表示を残して次世代を準備する。
     */
    bool prepareObjects(const ElliotPanelData &fromData, const int fromRowCount, const bool fromShowTable) {
        if (this.objects == NULL) {
            this.objects = new DrawChartObjectRegistry();
            if (this.objects == NULL) {
                return false;
            }
        }

        bool replace = false;
        if (!this.objects.isEmpty()) {
            replace = this.frontPending || ObjectFind(this.chartId, this.objectPrefix + "Background") < 0;
            if (!replace && fromShowTable) {
                replace = ObjectFind(this.chartId, this.objectPrefix + "HeaderBackground") < 0;
                for (int i = 0; i < fromRowCount && !replace; i++) {
                    string name = this.objectPrefix + "Row" + IntegerToString(fromData.frames[i].timeFrame)
                        + "-Background";
                    replace = ObjectFind(this.chartId, name) < 0;
                }
            }
        }

        if (replace) {
            DrawChartObjectRegistry *replacement = new DrawChartObjectRegistry();
            if (replacement == NULL) {
                return false;
            }

            this.previousObjects = this.objects;
            this.previousObjectPrefix = this.objectPrefix;
            this.objects = replacement;
            this.objectPrefix = this.prefix + "L1-";
            if (this.previousObjectPrefix == this.objectPrefix) {
                this.objectPrefix = this.prefix + "L0-";
            }
        }

        this.objects.begin(this.chartId, replace);

        return true;
    }

    /**
     * 不要な要素だけを回収し、完成した新世代がある場合だけ旧世代を解放する。
     */
    bool completeDraw() {
        bool success = this.drawingSucceeded;
        if (success) {
            success = this.objects.finish();
        }

        if (this.previousObjects != NULL) {
            if (success) {
                success = this.objects.show();
            }
            if (success) {
                this.previousObjects.clear();
                delete this.previousObjects;
                this.previousObjects = NULL;
                this.previousObjectPrefix = "";
            } else {
                this.objects.clear();
                delete this.objects;
                this.objects = this.previousObjects;
                this.previousObjects = NULL;
                this.objectPrefix = this.previousObjectPrefix;
                this.previousObjectPrefix = "";
                this.panelWidth = this.previousPanelWidth;
                this.panelHeight = this.previousPanelHeight;
                this.frontPending = true;
            }
        }

        if (success) {
            this.frontPending = false;
        } else {
            this.drawPending = true;
        }

        return success;
    }

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
    void drawHeader(const ElliotPanelData &fromData, const ElliotPanelLayout &fromLayout) {
        string mode = "現在";
        color modeColor = clrAqua;
        if (this.savedMode) {
            mode = "保存";
            modeColor = clrGold;
        }

        this.drawText("Title", "Elliot / " + fromData.symbolName + " / " + mode,
            fromLayout.contentLeft, fromLayout.getTitleTop(), fromLayout.titleWidth, 12, modeColor);
        this.drawButton("Close", "×", "パネルを閉じる",
            fromLayout.closeLeft, fromLayout.getButtonTop(), 24, true);
        string expandText = "詳細 ▼";
        if (this.expanded) {
            expandText = "一覧 ▲";
        }

        this.drawButton("Expand", expandText, "項目別詳細・通貨強弱・追加指標の表示を切り替えます。",
            fromLayout.getExpandLeft(), fromLayout.getButtonTop(), 80, true);

        if (this.savedMode) {
            this.drawButton("Previous", "◀ 前", "表示範囲内の古い保存データへ移動します。",
                fromLayout.getNavigationLeft(0), fromLayout.navigationTop,
                fromLayout.navigationWidth, fromData.canPrevious);
            this.drawButton("Next", "次 ▶", "表示範囲内の新しい保存データへ移動します。",
                fromLayout.getNavigationLeft(1), fromLayout.navigationTop,
                fromLayout.navigationWidth, fromData.canNext);
            this.drawButton("Live", "現在へ", "最新の分析結果へ戻ります。",
                fromLayout.getNavigationLeft(2), fromLayout.navigationTop, 78, true);
        }

        this.drawText("Time", fromData.headerTime, fromLayout.contentLeft, fromLayout.timeTop,
            fromLayout.contentWidth, 12, clrWhite);
        string metadata = fromData.metadata;
        if (StringLen(fromData.status) > 0 && fromData.rowCount > 0) {
            metadata = fromData.status + " / " + metadata;
        }

        this.drawText("Metadata", metadata, fromLayout.contentLeft, fromLayout.metadataTop,
            fromLayout.contentWidth, 9, clrSilver);
    }

    /**
     * GMMA付きの一覧を2段見出しで描画し、幅に余裕がある場合はElliot列を項目別に表示する。
     */
    void drawTable(const ElliotPanelData &fromData, const ElliotPanelLayout &fromLayout) {
        ElliotTableLayout layout;
        layout.objects = this.objects;
        layout.originX = fromLayout.contentLeft;
        layout.originY = fromLayout.tableTop;
        layout.paddingX = 3;
        layout.paddingY = 3;
        layout.rowHeight = fromLayout.rowHeight;
        layout.showBackground = true;
        layout.showSeparators = false;
        layout.clipText = true;
        layout.splitElliot = fromLayout.splitElliot;
        layout.showGmma = true;
        layout.groupHeaderHeight = fromLayout.groupHeaderHeight;
        layout.headerColor = clrWhiteSmoke;
        layout.backgroundColor = C'38,47,62';
        layout.backgroundZOrder = 31;
        layout.textZOrder = 32;
        for (int i = 0; i < 5; i++) {
            layout.columnXs[i] = fromLayout.columnXs[i];
            layout.columnWidths[i] = fromLayout.columnWidths[i];
            layout.columnFontSizes[i] = fromLayout.tableFontSize;
        }

        for (int i = 0; i < 2; i++) {
            layout.gmmaColumnXs[i] = fromLayout.gmmaColumnXs[i];
            layout.gmmaColumnWidths[i] = fromLayout.gmmaColumnWidths[i];
        }

        bool drawn = DrawElliotTable::drawHeader(this.chartId, this.objectPrefix + "Header", layout);
        this.drawingSucceeded = drawn && this.drawingSucceeded;
        layout.showSeparators = true;
        for (int i = 0; i < fromLayout.rowCount; i++) {
            layout.originY = fromLayout.getTableRowTop(i);
            layout.backgroundColor = C'25,31,41';
            if (i % 2 == 1) {
                layout.backgroundColor = C'31,38,49';
            }
            if (fromData.frames[i].timeFrame == this.selectedTimeFrame) {
                layout.backgroundColor = C'42,59,83';
            }

            string rowPrefix = this.objectPrefix + "Row" + IntegerToString(fromData.frames[i].timeFrame) + "-";
            layout.tooltips[3] = fromData.frames[i].movementTooltip;
            drawn = DrawElliotTable::drawRow(this.chartId, rowPrefix, fromData.frames[i].row,
                fromData.digits, fromData.palette, layout);
            this.drawingSucceeded = drawn && this.drawingSucceeded;
        }
    }

    /**
     * 選択行の12項目を現在・保存で同じ順序に表示する。
     */
    void drawDetails(const ElliotPanelFrame &fromFrame, const int fromDigits, const ElliotPanelLayout &fromLayout) {
        this.drawText("DetailTitle", fromFrame.row.timeFrameLabel + " の詳細",
            fromLayout.contentLeft, fromLayout.detailTop, fromLayout.contentWidth, 11, clrWhiteSmoke);
        string labels[] = {"主波", "副次波", "元波", "確定状態", "補完状態", "前推進波の副",
            "F", "FE", "値幅", "ポイント価格", "ポイント時刻", "波動方向"};
        for (int i = 0; i < 12; i++) {
            string value = detailValue(fromFrame, i, fromDigits);
            this.drawText("DetailLabel" + IntegerToString(i), labels[i], fromLayout.getDetailLeft(i),
                fromLayout.getDetailRowTop(i), 100, 10, clrSilver);
            this.drawText("DetailValue" + IntegerToString(i), value, fromLayout.getDetailValueLeft(i),
                fromLayout.getDetailRowTop(i), fromLayout.getDetailValueWidth(), 10, clrWhiteSmoke, labels[i] + ": " + value);
        }
    }

    /**
     * 追加オシレーターを選択行の詳細末尾へ表示する。
     */
    void drawExtras(const ElliotPanelFrame &fromFrame, const ElliotPanelLayout &fromLayout) {
        this.drawText("ExtraTitle", "追加指標", fromLayout.contentLeft, fromLayout.extrasTop,
            fromLayout.contentWidth, 10, clrWhiteSmoke);
        for (int i = 0; i < fromLayout.extraCount; i++) {
            this.drawText("ExtraLabel" + IntegerToString(i), fromFrame.extraLabels[i],
                fromLayout.getDetailLeft(i), fromLayout.getExtraRowTop(i), 100, 10, clrSilver);
            this.drawText("ExtraValue" + IntegerToString(i), fromFrame.extraValues[i],
                fromLayout.getDetailValueLeft(i), fromLayout.getExtraRowTop(i),
                fromLayout.getDetailValueWidth(), 10, fromFrame.extraColors[i]);
        }
    }

    /**
     * 取得元を明示した長中期・中短期の通貨強弱を描画する。
     */
    void drawStrength(const ElliotPanelStrength &fromStrength, const ElliotPanelLayout &fromLayout) {
        this.drawText("StrengthTitle", fromStrength.title, fromLayout.contentLeft, fromLayout.strengthTop,
            fromLayout.contentWidth, 10, clrWhiteSmoke, fromStrength.tooltip);
        string status = fromStrength.status;
        if (!fromStrength.enabled) {
            status = "通貨強弱OFF";
        }
        if (status != "取得済み" && StringLen(status) > 0) {
            this.drawText("StrengthStatus", status, fromLayout.contentLeft, fromLayout.getStrengthStatusTop(),
                fromLayout.contentWidth, 10, clrSilver, fromStrength.tooltip);

            return;
        }

        string headers[] = {"期間", fromStrength.baseCurrency, fromStrength.quoteCurrency, "順位差", "前M5比"};
        for (int i = 0; i < 5; i++) {
            this.drawText("StrengthHeader" + IntegerToString(i), headers[i],
                fromLayout.getStrengthLeft(i), fromLayout.getStrengthHeaderTop(), fromLayout.getStrengthTextWidth(), 9, clrSilver);
        }

        this.drawStrengthRow(fromStrength.longMedium, "長中期", "LongMedium", fromLayout.getStrengthRowTop(0), fromLayout);
        this.drawStrengthRow(fromStrength.mediumShort, "中短期", "MediumShort", fromLayout.getStrengthRowTop(1), fromLayout);
    }

    /**
     * 順位差と前M5比を独立した色で表示する。
     */
    void drawStrengthRow(const ElliotPanelStrengthPeriod &fromPeriod, const string fromTitle,
            const string fromKey, const int fromTop, const ElliotPanelLayout &fromLayout) {
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
                fromLayout.getStrengthLeft(i), fromTop, fromLayout.getStrengthTextWidth(), 10, textColor);
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

        string name = this.objectPrefix + fromKey;
        if (!this.objects.ensure(name, OBJ_LABEL)) {
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
        string name = this.objectPrefix + fromKey;
        if (!this.objects.ensure(name, OBJ_RECTANGLE_LABEL)) {
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
        string name = this.objectPrefix + fromKey;
        if (!this.objects.ensure(name, OBJ_BUTTON)) {
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
