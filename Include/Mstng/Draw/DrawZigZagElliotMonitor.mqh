#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_MQH

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Draw\DrawZigZagElliotMonitorSortCombo.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorProgress.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSort.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSymbolState.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorTarget.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 監視パネルの1オブジェクトへ反映済みの描画値を保持する。
 */
struct DrawZigZagElliotMonitorObject {
    /** 固有接頭辞を含むオブジェクト名。 */
    string objectName;

    /** オブジェクトを作成済みの場合true。 */
    bool created;

    /** 反映済みの左位置。 */
    long positionX;

    /** 反映済みの上位置。 */
    long positionY;

    /** 反映済みの幅。 */
    long width;

    /** 反映済みの高さ。 */
    long height;

    /** 反映済みのフォントサイズ。 */
    long fontSize;

    /** 反映済みの文字色または枠色。 */
    long foreground;

    /** 反映済みの背景色。 */
    long background;

    /** 反映済みの表示文字列。 */
    string text;

    /** 反映済みのツールチップ。 */
    string tooltip;

    /**
     * 作成直後に全可変項目を設定できる状態へ戻す。
     */
    void reset() {
        this.created = false;
        this.positionX = -1;
        this.positionY = -1;
        this.width = -1;
        this.height = -1;
        this.fontSize = -1;
        this.foreground = -1;
        this.background = -1;
        this.text = "未設定の描画値";
        this.tooltip = "未設定の描画値";
    }
};

/**
 * 選択した対象通貨のM1判定とチャート表示状況を、独立した固定パネルに表示する。
 * 現在の判定と保持された直近成立時刻を区別し、描画変更だけを呼び出し元へ通知する。
 */
class DrawZigZagElliotMonitor {
public:
    /**
     * 未初期化状態で作成する。
     */
    DrawZigZagElliotMonitor() {
        this.chartId = 0;
        this.objectPrefix = "";
        this.initialized = false;
        this.changed = false;
        this.requestedFontSize = 10;
        this.measuredFontSize = 0;
        this.previousRowCount = 0;
        this.mouseMoveOwned = false;
        this.targetMode = ZIGZAG_MONITOR_TARGET_GMO;
        this.gmoSymbols.setGmo();
        this.sortOrder.reset();
    }

    /**
     * 自身が所有する描画オブジェクトを解放する。
     */
    ~DrawZigZagElliotMonitor() {
        this.destroy();
    }

    /**
     * 描画先とインスタンス固有の接頭辞を指定する。
     *
     * @param fromChartId 描画対象チャート。0は現在のチャート。
     * @param fromPrefix 他の描画と重複しない40文字以内の接頭辞。
     * @param fromFontSize 一覧の基準フォントサイズ。
     * @return パネルを作成できた場合true。
     */
    bool initialize(const long fromChartId, const string fromPrefix, const int fromFontSize) {
        if (fromPrefix == "" || StringLen(fromPrefix) > 40 || fromChartId < 0) {
            return false;
        }

        this.destroy();
        this.chartId = fromChartId;
        this.objectPrefix = fromPrefix;
        this.requestedFontSize = (int)MathMax(6, MathMin(16, fromFontSize));
        this.sortOrder.reset();
        this.targetMode = ZIGZAG_MONITOR_TARGET_GMO;
        this.initialized = true;
        if (!this.enableMouseMove() || this.ensureObject("Panel", OBJ_RECTANGLE_LABEL) < 0) {
            this.destroy();

            return false;
        }

        return true;
    }

    /**
     * 選択された表示順へ索引だけを並べ替え、変更した項目だけを反映する。
     *
     * @param fromStates 監視対象の状態一覧。元の並びは変更しない。
     * @param fromMonitoring 監視が有効な場合true。
     * @param fromAutoOpen 自動チャート表示が有効な場合true。
     * @param fromOpenCount 監視機能が現在保持しているチャート枚数。
     * @param fromMaxOpenCharts チャート表示枚数の上限。
     * @param fromLastEvaluationTime 最後に判定・データ確認を試みたサーバー時刻。
     * @param fromProgress 共通の対象M1に対する進捗と確認処理の状況。
     * @param fromTargetMode コントローラーが監視している通貨ペア範囲。
     * @return 描画オブジェクトを変更した場合true。
     */
    bool update(CArrayObj &fromStates, const bool fromMonitoring, const bool fromAutoOpen,
            const int fromOpenCount, const int fromMaxOpenCharts, const datetime fromLastEvaluationTime,
            const ZigZagElliotMonitorProgress &fromProgress,
            const ENUM_ZIGZAG_MONITOR_TARGET fromTargetMode = ZIGZAG_MONITOR_TARGET_GMO) {
        if (!this.initialized) {
            return false;
        }

        this.changed = false;
        this.targetMode = fromTargetMode;
        this.measuredFontSize = 0;
        int indexes[];
        int confirmedCount = 0;
        int entryCount = 0;
        int gmoCount = 0;
        int stateCount = this.prepareIndexes(fromStates, indexes, confirmedCount, entryCount, gmoCount, fromProgress);
        this.prepareLayout(stateCount);
        this.drawRectangle("Panel", this.panelLeft, this.panelTop, this.panelWidth,
            this.panelHeight, C'12,15,20', C'65,74,88');

        string title = "通貨監視 " + ZigZagElliotMonitorTarget::getLabel(this.targetMode)
            + StringFormat(" / 対象%d / M1", stateCount);

        string monitorText = "監視：OFF";
        color monitorColor = C'70,75,83';
        if (fromMonitoring) {
            monitorText = "監視：ON";
            monitorColor = C'22,91,81';
        }

        string autoText = "自動表示：OFF";
        color autoColor = C'70,75,83';
        if (fromAutoOpen) {
            autoText = "自動表示：ON";
            autoColor = C'42,75,116';
        }

        string entryPriorityText = "ENTRY優先：OFF";
        color entryPriorityColor = C'70,75,83';
        if (this.sortOrder.isEntryPriority()) {
            entryPriorityText = "ENTRY優先：ON";
            entryPriorityColor = C'42,75,116';
        }

        this.drawLabel("Title", this.contentLeft, this.panelTop + 11, this.titleWidth,
            this.bodyFontSize + 2, clrWhiteSmoke, title, "M1新バーごとに現行M1条件のエントリー判定を監視します。");
        this.drawButton("MonitorButton", this.monitorButtonLeft, this.buttonTop, this.buttonWidth,
            monitorText, monitorColor, "監視のON/OFF。OFF中は最後の判定を保持します。");
        this.drawButton("AutoButton", this.autoButtonLeft, this.buttonTop, this.buttonWidth,
            autoText, autoColor, "新規成立時のチャート自動表示を切り替えます。");
        this.drawButton("EntryPriorityButton", this.entryPriorityButtonLeft, this.buttonTop, this.buttonWidth,
            entryPriorityText, entryPriorityColor,
            "ONは今回のM1で判定済みのENTRYを先頭にし、各グループ内を選択列で並べます。"
                + "\nOFFは全通貨を選択列で並べます。前回M1のENTRYは優先しません。");
        this.drawColumnHeaders();
        this.removeHiddenChartButtons(fromStates, indexes);

        for (int i = 0; i < this.visibleRowCount; i++) {
            ZigZagElliotMonitorSymbolState *state = fromStates.At(indexes[i]);
            this.drawRow(i, state, fromProgress);
        }

        for (int i = this.visibleRowCount; i < this.previousRowCount; i++) {
            this.removeRow(i);
        }

        this.previousRowCount = this.visibleRowCount;
        string emptyText = "";
        if (stateCount == 0) {
            emptyText = "監視対象がありません";
        } else if (this.visibleRowCount == 0) {
            emptyText = "一覧表示にはチャートの高さが必要です";
        }

        if (emptyText != "") {
            this.drawLabel("Empty", this.contentLeft, this.rowsTop + 4, this.contentWidth,
                this.bodyFontSize, clrSilver, emptyText, emptyText);
        } else {
            // 空文字のラベルは既定文字が表示されるため、通常表示では削除する。
            this.removeObject(this.objectPrefix + "Empty");
        }

        string summary = "対象M1 " + this.formatServerTime(fromProgress.targetBarTime)
            + StringFormat(" SRV  ・ 判定済み %d / %d  ・ ENTRY %d",
                fromProgress.completedCount, fromProgress.totalCount, fromProgress.entryCount);
        string progressCounts = StringFormat("待機 %d  ・ 未確認 %d  ・ エラー %d  ・ 確認中 %d",
            fromProgress.waitingCount, fromProgress.uncheckedCount,
            fromProgress.errorCount, fromProgress.checkingCount);
        string summaryTooltip = summary + "\n" + progressCounts
            + "\n判定済みは、この対象M1の成立・不成立が確定した通貨数です。"
            + StringFormat("\n起動・監視再開後の確認済み %d / %d", confirmedCount, stateCount)
            + StringFormat("\n保持中のENTRY表示 %d（前回の対象足を含む）", entryCount);
        if (this.visibleRowCount < stateCount) {
            summaryTooltip += StringFormat("\n一覧 %d / %d（高さ不足）", this.visibleRowCount, stateCount);
        }

        string activityText = "確認前";
        color activityColor = C'201,211,222';
        if (!fromMonitoring) {
            activityText = "監視停止";
            activityColor = clrSilver;
        } else if (fromProgress.activeSymbol != "") {
            activityText = "確認中 " + fromProgress.activeSymbol;
            activityColor = C'135,206,250';
        } else if (fromProgress.lastSymbol != "") {
            activityText = "直前 " + fromProgress.lastSymbol
                + "（" + this.formatDuration(fromProgress.lastDurationMs) + "）";
        }

        if (fromMonitoring) {
            if (fromProgress.totalCount == 0) {
                activityText += "  ・ 監視対象なし";
            } else if (fromProgress.checkingCount > 0 || fromProgress.uncheckedCount > 0) {
                activityText += "  ・ 順次確認中";
            } else if (fromProgress.waitingCount > 0 || fromProgress.errorCount > 0) {
                activityText += "  ・ データ再確認待ち";
            } else {
                activityText += "  ・ 次のM1足待ち";
            }
        }

        string activityTooltip = activityText + "\n" + progressCounts
            + "\n直前の確認通貨：" + fromProgress.lastSymbol
            + "\n直前の確認処理時間：" + this.formatDuration(fromProgress.lastDurationMs)
            + "\n処理時間にはチャート表示処理を含めません。";
        activityText += "  ・ " + progressCounts;
        string openCountText = IntegerToString(fromOpenCount);
        if (fromOpenCount < 0) {
            openCountText = "不明";
        }

        string cycleText = "最終確認 " + this.formatJapanTime(fromLastEvaluationTime)
            + StringFormat(" JST  ・ 表示 %s / %d枚", openCountText, fromMaxOpenCharts);
        string cycleTooltip = cycleText + "\n最終確認：" + this.formatServerTime(fromLastEvaluationTime)
            + " SRV\n最後に判定・データ確認を試みた時刻です。";
        if (fromOpenCount < 0) {
            cycleTooltip += "\n管理チャート枚数を参照できません。";
        }

        this.drawLabel("Summary", this.contentLeft, this.footerTop, this.contentWidth,
            this.bodyFontSize, C'201,211,222', summary, summaryTooltip);
        this.drawLabel("Activity", this.contentLeft, this.footerTop + 24, this.contentWidth,
            this.bodyFontSize, activityColor, activityText, activityTooltip);
        this.drawLabel("Cycle", this.contentLeft, this.footerTop + 48, this.contentWidth,
            this.bodyFontSize, C'153,167,184', cycleText, cycleTooltip);
        this.drawSortControls();

        return this.changed;
    }

    /**
     * 標準コンボの通知を先に処理し、背面操作とソート変更を分けて呼び出し元へ返す。
     *
     * @param fromSortChanged 表示順を更新する必要がある場合true。
     * @return このパネルのソート操作として消費した場合true。
     */
    bool handleSortControlEvent(const int fromEventId, const long &fromLongParam,
            const double &fromDoubleParam, const string &fromStringParam, bool &fromSortChanged) {
        bool targetChanged = false;
        ENUM_ZIGZAG_MONITOR_TARGET selectedTarget = this.targetMode;

        return this.handleControlEvent(fromEventId, fromLongParam, fromDoubleParam,
            fromStringParam, fromSortChanged, targetChanged, selectedTarget);
    }

    /**
     * 展開中のコンボへ優先配送し、監視対象と並び順の変更を別々に通知する。
     *
     * @return コンボまたはソート操作として消費した場合true。
     */
    bool handleControlEvent(const int fromEventId, const long &fromLongParam,
            const double &fromDoubleParam, const string &fromStringParam, bool &fromSortChanged,
            bool &fromTargetChanged, ENUM_ZIGZAG_MONITOR_TARGET &fromSelectedTarget) {
        fromSortChanged = false;
        fromTargetChanged = false;
        fromSelectedTarget = this.targetMode;
        if (!this.initialized) {
            return false;
        }

        bool sortSelectionChanged = false;
        bool targetSelectionChanged = false;
        bool sortHandled = false;
        bool targetHandled = false;
        int selectedColumn = this.sortOrder.getColumnIndex();
        int selectedTarget = (int)this.targetMode;
        if (this.targetCombo.isPopupOpen()) {
            targetHandled = this.targetCombo.handleEvent(fromEventId, fromLongParam, fromDoubleParam,
                fromStringParam, targetSelectionChanged, selectedTarget);
            if (targetHandled) {
                this.sortCombo.blockEvent(fromEventId, fromLongParam, fromDoubleParam, fromStringParam);
            } else {
                sortHandled = this.sortCombo.handleEvent(fromEventId, fromLongParam, fromDoubleParam,
                    fromStringParam, sortSelectionChanged, selectedColumn);
            }
        } else {
            sortHandled = this.sortCombo.handleEvent(fromEventId, fromLongParam, fromDoubleParam,
                fromStringParam, sortSelectionChanged, selectedColumn);
            if (sortHandled) {
                this.targetCombo.blockEvent(fromEventId, fromLongParam, fromDoubleParam, fromStringParam);
            } else {
                targetHandled = this.targetCombo.handleEvent(fromEventId, fromLongParam, fromDoubleParam,
                    fromStringParam, targetSelectionChanged, selectedTarget);
            }
        }

        if (sortHandled && this.sortCombo.isPopupOpen()) {
            this.targetCombo.closePopup();
        } else if (targetHandled && this.targetCombo.isPopupOpen()) {
            this.sortCombo.closePopup();
        }

        if (sortSelectionChanged && selectedColumn != this.sortOrder.getColumnIndex()) {
            fromSortChanged = this.sortOrder.setColumn(selectedColumn);
        }

        ENUM_ZIGZAG_MONITOR_TARGET selectedMode = (ENUM_ZIGZAG_MONITOR_TARGET)selectedTarget;
        if (targetSelectionChanged && ZigZagElliotMonitorTarget::isValid(selectedMode)
                && selectedMode != this.targetMode) {
            fromSelectedTarget = selectedMode;
            fromTargetChanged = true;
        }

        if (sortHandled || targetHandled) {
            return true;
        }

        if (fromEventId == CHARTEVENT_OBJECT_CLICK) {
            fromSortChanged = this.handleSortClick(fromStringParam);

            return fromSortChanged;
        }

        return false;
    }

    /**
     * 自身のソート見出しとENTRY優先ボタンの押下を受け付ける。
     * 表示更新は呼び出し元に任せ、監視対象の並びは変更しない。
     *
     * @param fromObjectName クリックされたオブジェクト名。
     * @return ソート設定を切り替えた場合true。
     */
    bool handleSortClick(const string fromObjectName) {
        if (!this.initialized) {
            return false;
        }

        if (fromObjectName == this.objectPrefix + "EntryPriorityButton") {
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            this.sortOrder.toggleEntryPriority();

            return true;
        }

        if (fromObjectName == this.objectPrefix + "SortDirectionButton") {
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            this.sortOrder.toggleDirection();

            return true;
        }

        for (int i = 0; i < 8; i++) {
            if (fromObjectName != this.objectPrefix + "SortHeader" + IntegerToString(i)) {
                continue;
            }

            if (!this.sortOrder.selectColumn(i)) {
                return false;
            }

            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);

            return true;
        }

        return false;
    }

    /**
     * 監視切り替えボタンのオブジェクト名を取得する。
     */
    string getMonitorButtonName() { return this.objectPrefix + "MonitorButton"; }

    /**
     * 自動表示切り替えボタンのオブジェクト名を取得する。
     */
    string getAutoButtonName() { return this.objectPrefix + "AutoButton"; }

    /**
     * 並び順に依存しない通貨別の手動チャート表示ボタン名を取得する。
     *
     * @param fromCanonicalSymbolName 正規通貨ペア名。
     * @return インスタンスと通貨を特定するオブジェクト名。
     */
    string getChartButtonName(const string fromCanonicalSymbolName) {
        return this.objectPrefix + "Open" + fromCanonicalSymbolName;
    }

    /**
     * 自身の固有接頭辞に一致するオブジェクトだけを削除する。
     */
    void destroy() {
        this.sortCombo.destroy();
        this.targetCombo.destroy();
        if (this.mouseMoveOwned) {
            ChartSetInteger(this.chartId, CHART_EVENT_MOUSE_MOVE, false);
            this.mouseMoveOwned = false;
        }

        if (this.initialized && this.objectPrefix != "") {
            ObjectsDeleteAll(this.chartId, this.objectPrefix, -1, -1);
        }

        ArrayResize(this.objects, 0);
        this.previousRowCount = 0;
        this.initialized = false;
        this.objectPrefix = "";
    }

private:
    /** 描画先チャートID。 */
    long chartId;

    /** 他の描画と共有しないオブジェクト名接頭辞。 */
    string objectPrefix;

    /** initializeに成功している場合true。 */
    bool initialized;

    /** 今回のupdateで描画値を変更した場合true。 */
    bool changed;

    /** 反映済みのオブジェクトとプロパティ値。 */
    DrawZigZagElliotMonitorObject objects[];

    /** GMO対象の印を付けるための共通定義。 */
    SymbolNameInfoAll gmoSymbols;

    /** 画面更新と監視切替をまたいで保持する表示順。 */
    ZigZagElliotMonitorSort sortOrder;

    /** 並び順選択の標準コンボボックス。 */
    DrawZigZagElliotMonitorSortCombo sortCombo;

    /** 監視対象選択の標準コンボボックス。 */
    DrawZigZagElliotMonitorSortCombo targetCombo;

    /** 最後に描画した監視対象。 */
    ENUM_ZIGZAG_MONITOR_TARGET targetMode;

    /** 2つの標準コンボに必要なマウス通知を自身が有効にした場合true。 */
    bool mouseMoveOwned;

    /** 利用者が指定した基準フォントサイズ。 */
    int requestedFontSize;

    /** 今回の更新中に文字計測へ設定済みのフォントサイズ。 */
    int measuredFontSize;

    /** 前回描画した行数。 */
    int previousRowCount;

    /** 現在のチャート幅に合わせた文字サイズ。 */
    int bodyFontSize;

    /** パネルの左位置。 */
    int panelLeft;

    /** パネルの上位置。 */
    int panelTop;

    /** パネルの横幅。 */
    int panelWidth;

    /** パネルの高さ。 */
    int panelHeight;

    /** パネル内の文字領域の左位置。 */
    int contentLeft;

    /** パネル内の文字領域の幅。 */
    int contentWidth;

    /** タイトルの表示可能幅。 */
    int titleWidth;

    /** 監視ボタンの左位置。 */
    int monitorButtonLeft;

    /** 自動表示ボタンの左位置。 */
    int autoButtonLeft;

    /** ENTRY優先切替ボタンの左位置。 */
    int entryPriorityButtonLeft;

    /** 上部3ボタンの上位置。 */
    int buttonTop;

    /** 上部3ボタンの横幅。 */
    int buttonWidth;

    /** 列見出しの上位置。 */
    int headerTop;

    /** 並び順選択行の上位置。 */
    int sortTop;

    /** 監視対象選択行の上位置。 */
    int targetTop;

    /** 最初のデータ行の上位置。 */
    int rowsTop;

    /** 下部の集計表示の上位置。 */
    int footerTop;

    /** データ行の高さ。 */
    int rowHeight;

    /** チャートの高さ内へ表示できる行数。 */
    int visibleRowCount;

    /** 既存列IDを維持した14列それぞれの左位置。 */
    int columnLeft[14];

    /** 既存列IDを維持した14列それぞれの横幅。 */
    int columnWidth[14];

    /**
     * 2つの標準コンボが共用するマウス通知を、作成時に一度だけ確保する。
     */
    bool enableMouseMove() {
        long mouseMoveEnabled = 0;
        if (!ChartGetInteger(this.chartId, CHART_EVENT_MOUSE_MOVE, 0, mouseMoveEnabled)) {
            return false;
        }

        if (mouseMoveEnabled == 0) {
            if (!ChartSetInteger(this.chartId, CHART_EVENT_MOUSE_MOVE, true)) {
                return false;
            }

            this.mouseMoveOwned = true;
        }

        return true;
    }

    /**
     * 有効な状態を集計し、参照番号だけを選択された表示順へ並べる。
     */
    int prepareIndexes(CArrayObj &fromStates, int &fromIndexes[], int &fromConfirmedCount,
            int &fromEntryCount, int &fromGmoCount, const ZigZagElliotMonitorProgress &fromProgress) {
        int totalCount = fromStates.Total();
        if (ArrayResize(fromIndexes, totalCount) != totalCount) {
            return 0;
        }

        int stateCount = 0;
        for (int i = 0; i < totalCount; i++) {
            ZigZagElliotMonitorSymbolState *state = fromStates.At(i);
            if (state == NULL) {
                continue;
            }

            fromIndexes[stateCount] = i;
            stateCount++;
            if (state.result.completed || state.baselineReady) {
                fromConfirmedCount++;
            }

            if (state.result.status == ZIGZAG_MONITOR_ENTRY) {
                fromEntryCount++;
            }

            if (this.isGmo(state.canonicalSymbolName)) {
                fromGmoCount++;
            }
        }

        for (int i = 1; i < stateCount; i++) {
            int currentIndex = fromIndexes[i];
            ZigZagElliotMonitorSymbolState *current = fromStates.At(currentIndex);
            int j = i - 1;
            while (j >= 0) {
                ZigZagElliotMonitorSymbolState *previous = fromStates.At(fromIndexes[j]);
                if (!this.sortOrder.comesBefore(*current, *previous, fromProgress.targetBarTime)) {
                    break;
                }

                fromIndexes[j + 1] = fromIndexes[j];
                j--;
            }

            fromIndexes[j + 1] = currentIndex;
        }

        return stateCount;
    }

    /**
     * チャート幅内で列とボタンを配置し、高さ不足の場合は行高と表示行数を調整する。
     */
    void prepareLayout(const int fromStateCount) {
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS, 0);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        chartWidth = (int)MathMax(1, chartWidth);
        chartHeight = (int)MathMax(1, chartHeight);
        this.panelLeft = (int)MathMin(10, chartWidth / 20);
        this.panelTop = (int)MathMin(10, chartHeight / 20);
        this.panelWidth = (int)MathMax(1, MathMin(1400, chartWidth - this.panelLeft * 2));
        int padding = (int)MathMin(12, this.panelWidth / 10);
        this.contentLeft = this.panelLeft + padding;
        this.contentWidth = (int)MathMax(1, this.panelWidth - padding * 2);
        this.bodyFontSize = this.requestedFontSize;
        if (this.panelWidth < 720) {
            this.bodyFontSize = (int)MathMin(this.bodyFontSize, 8);
        }

        if (this.panelWidth < 440) {
            this.bodyFontSize = (int)MathMin(this.bodyFontSize, 7);
        }

        this.buttonWidth = 116;
        this.buttonTop = this.panelTop + 10;
        this.entryPriorityButtonLeft = this.contentLeft + this.contentWidth - this.buttonWidth;
        this.autoButtonLeft = this.entryPriorityButtonLeft - this.buttonWidth - 8;
        this.monitorButtonLeft = this.autoButtonLeft - this.buttonWidth - 8;
        this.titleWidth = this.monitorButtonLeft - this.contentLeft - 12;
        if (this.panelWidth < 760) {
            int buttonGap = (int)MathMin(8, this.contentWidth / 20);
            this.buttonWidth = (int)MathMax(1, (this.contentWidth - buttonGap * 2) / 3);
            this.buttonTop = this.panelTop + 39;
            this.monitorButtonLeft = this.contentLeft;
            this.autoButtonLeft = this.contentLeft + this.buttonWidth + buttonGap;
            this.entryPriorityButtonLeft = this.autoButtonLeft + this.buttonWidth + buttonGap;
            this.titleWidth = this.contentWidth;
        }

        this.targetTop = this.buttonTop + 34;
        this.sortTop = this.targetTop;
        if (this.panelWidth < 760) {
            this.sortTop += 34;
        }

        this.headerTop = this.sortTop + 34;
        this.rowsTop = this.headerTop + 27;
        int availableHeight = (int)MathMax(0, chartHeight - this.rowsTop - 94);
        this.rowHeight = (int)MathMax(24, this.bodyFontSize * 2 + 4);
        if (fromStateCount > 0 && availableHeight < fromStateCount * this.rowHeight) {
            this.rowHeight = (int)MathMax(MathMax(18, this.bodyFontSize * 2), availableHeight / fromStateCount);
        }

        this.visibleRowCount = (int)MathMin(fromStateCount, availableHeight / this.rowHeight);
        this.footerTop = this.rowsTop + (int)MathMax(1, this.visibleRowCount) * this.rowHeight + 12;
        this.panelHeight = (int)MathMin(chartHeight - this.panelTop,
            this.footerTop - this.panelTop + 80);
        this.columnWidth[7] = (int)MathMin(this.contentWidth, MathMin(76, MathMax(40, this.contentWidth / 10)));
        int textWidth = this.contentWidth - this.columnWidth[7];
        int directionBudget = (int)MathMin(textWidth, this.contentWidth * 28 / 100);
        int directionWidth = (int)MathMin(this.bodyFontSize * 6, directionBudget / 6);
        this.columnWidth[2] = directionWidth;
        for (int i = 9; i < 14; i++) {
            this.columnWidth[i] = directionWidth;
        }

        textWidth -= directionWidth * 6;
        this.columnWidth[8] = textWidth * 13 / 100;
        textWidth -= this.columnWidth[8];
        this.columnWidth[0] = textWidth * 13 / 94;
        this.columnWidth[1] = textWidth * 16 / 94;
        this.columnWidth[3] = textWidth * 12 / 94;
        this.columnWidth[4] = textWidth * 12 / 94;
        this.columnWidth[5] = textWidth * 23 / 94;
        this.columnWidth[6] = textWidth - this.columnWidth[0] - this.columnWidth[1]
            - this.columnWidth[3] - this.columnWidth[4] - this.columnWidth[5];
        int displayOrder[14] = {0, 1, 2, 9, 10, 11, 12, 13, 8, 3, 4, 5, 6, 7};
        int nextLeft = this.contentLeft;
        for (int i = 0; i < 14; i++) {
            int columnIndex = displayOrder[i];
            this.columnLeft[columnIndex] = nextLeft;
            nextLeft += this.columnWidth[columnIndex];
        }
    }

    /**
     * 表の描画後に標準コンボを配置し、展開したリストを既存ラベルより前へ出す。
     */
    void drawSortControls() {
        int gap = (int)MathMin(8, this.contentWidth / 40);
        int targetLabelWidth = (int)MathMin(this.bodyFontSize * 8, this.contentWidth / 4);
        int targetComboWidth = (int)MathMax(0, MathMin(180, this.contentWidth - targetLabelWidth - gap));
        int targetComboLeft = this.contentLeft + targetLabelWidth + gap;
        int sortLeft = this.contentLeft;
        int sortWidth = this.contentWidth;
        if (this.targetTop == this.sortTop) {
            sortLeft = targetComboLeft + targetComboWidth + 24;
            sortWidth = (int)MathMax(0, this.contentWidth - (sortLeft - this.contentLeft));
        }

        int labelWidth = (int)MathMin(this.bodyFontSize * 6, sortWidth / 5);
        int orderWidth = (int)MathMax(1, MathMin(116, (sortWidth - labelWidth - gap * 2) / 3));
        int comboWidth = (int)MathMax(0, MathMin(220, sortWidth - labelWidth - orderWidth - gap * 2));
        int comboLeft = sortLeft + labelWidth + gap;
        this.drawLabel("TargetLabel", this.contentLeft, this.targetTop + 3, targetLabelWidth,
            this.bodyFontSize, C'201,211,222', "監視対象", "監視する通貨ペア範囲を選びます。並び順とENTRY優先は維持します。");
        this.drawLabel("SortLabel", sortLeft, this.sortTop + 3, labelWidth,
            this.bodyFontSize, C'201,211,222', "並び順", "並び順を選択し、右のボタンで順序を切り替えます。");
        this.drawButton("SortDirectionButton", comboLeft + comboWidth + gap, this.sortTop,
            orderWidth, this.getSortDirectionText(), C'42,75,116',
            this.getSortTooltip(this.sortOrder.getColumnIndex()) + "\nクリックで順序を反転します。", 26);

        bool comboChanged = false;
        if (this.sortCombo.prepare(this.chartId, this.objectPrefix + "SortBox", comboLeft,
                this.sortTop, comboWidth, this.bodyFontSize, this.sortOrder.getColumnIndex(), comboChanged,
                false, true)) {
            this.removeObject(this.objectPrefix + "SortComboError");
        } else {
            this.drawLabel("SortComboError", comboLeft, this.sortTop + 3, comboWidth,
                this.bodyFontSize, clrOrange, "選択欄を表示できません",
                "並び順の選択欄を作成できません。画面幅を広げるか、列見出しをクリックして並べ替えてください。");
        }

        if (comboChanged) {
            this.changed = true;
        }

        if (this.targetCombo.prepare(this.chartId, this.objectPrefix + "PairBox", targetComboLeft,
                this.targetTop, targetComboWidth, this.bodyFontSize, (int)this.targetMode, comboChanged,
                true, true)) {
            this.removeObject(this.objectPrefix + "TargetComboError");
        } else {
            this.drawLabel("TargetComboError", targetComboLeft, this.targetTop + 3, targetComboWidth,
                this.bodyFontSize, clrOrange, "選択欄を表示できません",
                "監視対象の選択欄を作成できません。画面幅を広げて再確認してください。");
        }

        if (comboChanged) {
            this.changed = true;
        }
    }

    /**
     * ソート対象に応じた意味で現在の順序を表示する。
     */
    string getSortDirectionText() {
        int columnIndex = this.sortOrder.getColumnIndex();
        if (columnIndex == 0) {
            if (this.sortOrder.isAscending()) {
                return "A→Z";
            }

            return "Z→A";
        }

        if (columnIndex == 1) {
            if (this.sortOrder.isAscending()) {
                return "優先順";
            }

            return "逆順";
        }

        if (columnIndex == 5) {
            if (this.sortOrder.isAscending()) {
                return "古い順";
            }

            return "新しい順";
        }

        if (this.sortOrder.isAscending()) {
            return "小さい順";
        }

        return "大きい順";
    }

    /**
     * ソート対象の見出しをボタンにし、選択列の順序を矢印で表示する。
     */
    void drawColumnHeaders() {
        string titles[14] = {"通貨ペア [G]", "判定", "D1", "長中期", "中短期", "直近成立時刻 JST", "表示結果", "操作", "波動 M5/M1", "H4", "H1", "M15", "M5", "M1"};
        this.drawRectangle("Header", this.panelLeft + 1, this.headerTop - 4,
            (int)MathMax(1, this.panelWidth - 2), 27, C'31,39,50', C'31,39,50');
        for (int i = 0; i < 14; i++) {
            string labelSuffix = "Header" + IntegerToString(i);
            string buttonSuffix = "SortHeader" + IntegerToString(i);
            if (i == 0 || i == 1 || i == 3 || i == 4 || i == 5) {
                this.removeObject(this.objectPrefix + labelSuffix);
                string title = titles[i];
                color background = C'31,39,50';
                if (this.sortOrder.getColumnIndex() == i) {
                    background = C'42,75,116';
                    string directionMark = "▼ ";
                    if (this.sortOrder.isAscending()) {
                        directionMark = "▲ ";
                    }

                    title = directionMark + title;
                }

                this.drawButton(buttonSuffix, this.columnLeft[i], this.headerTop - 3,
                    (int)MathMax(1, this.columnWidth[i] - 5), title, background,
                    this.getSortTooltip(i), 25);
            } else {
                this.removeObject(this.objectPrefix + buttonSuffix);
                string tooltip = titles[i];
                if (i == 2 || i >= 9) {
                    tooltip += "：補正前の元分析の売買方向です。BUYは水色、SELLはピンクです。"
                        + "\n補は、この足で方向補正が採用された印です。補正後の方向は行のツールチップで確認できます。"
                        + "\n前回M1・確認中の値は灰色で表示します。";
                }

                this.drawLabel(labelSuffix, this.columnLeft[i], this.headerTop,
                    this.columnWidth[i] - 5, this.bodyFontSize, C'179,193,210', titles[i], tooltip);
            }
        }
    }

    /**
     * 列ごとのソート基準と現在の選択状態を説明する。
     */
    string getSortTooltip(const int fromColumnIndex) {
        string text = "通貨名で並べ替えます。初回選択はA→Zです。";
        if (fromColumnIndex == 1) {
            text = "判定状態で並べ替えます。初回選択は優先順です。"
                + "\nENTRY→M1未達→確認済み→強弱未達→各種待機→エラーの順です。"
                + "\n前回→未確認は昇降とも末尾固定です。同判定は通貨名A→Zです。"
                + "\n確認済みは同一シグナルの確認で、ENTRY成立済みとは限りません。"
                + "\n確認中は保存済みの判定状態を並べ替えに使います。";
        } else if (fromColumnIndex == 3 || fromColumnIndex == 4) {
            text = "現在M5の順位差で並べ替えます。初回選択は大きい順です。"
                + "\n増減矢印はソートに使いません。未取得・前回M5の値は末尾にします。";
        } else if (fromColumnIndex == 5) {
            text = "直近成立時刻で並べ替えます。初回選択は新しい順です。"
                + "\n成立記録がない通貨は末尾にします。";
        }

        if (this.sortOrder.getColumnIndex() == fromColumnIndex) {
            string direction = "降順 ▼";
            if (this.sortOrder.isAscending()) {
                direction = "昇順 ▲";
            }

            text += "\n現在の選択：" + direction;
        }

        text += "\nクリックで選択し、同じ見出しを再クリックすると昇順・降順を切り替えます。";
        if (this.sortOrder.isEntryPriority()) {
            text += "\nENTRY優先ON：今回M1のENTRYを先頭にし、各グループ内をこの列で並べます。";
        } else {
            text += "\nENTRY優先OFF：全通貨をこの列で並べます。";
        }

        return text;
    }

    /**
     * 確認理由と前回の結果を区別し、直近成立時刻とチャート状態を独立した列へ表示する。
     */
    void drawRow(const int fromRowIndex, ZigZagElliotMonitorSymbolState *fromState,
            const ZigZagElliotMonitorProgress &fromProgress) {
        if (fromState == NULL) {
            return;
        }

        string rowPrefix = "Row" + IntegerToString(fromRowIndex);
        int rowTop = this.rowsTop + fromRowIndex * this.rowHeight;
        color rowColor = C'12,15,20';
        if (fromRowIndex % 2 != 0) {
            rowColor = C'20,24,31';
        }

        string statusText = "待機";
        color statusColor = clrGold;
        if (fromState.result.status == ZIGZAG_MONITOR_ENTRY) {
            statusText = "ENTRY";
            statusColor = clrHotPink;
            rowColor = C'45,23,35';
            if (fromState.result.isBuy) {
                statusColor = clrAqua;
                rowColor = C'17,38,43';
            }
        } else if (fromState.result.status == ZIGZAG_MONITOR_NOT_MATCHED) {
            statusText = "不成立";
            statusColor = C'158,170,185';
            if (fromState.result.shortMessage == "M1未達") {
                statusColor = clrOrange;
            } else if (fromState.result.shortMessage == "確認済み") {
                statusColor = C'201,211,222';
            }
        } else if (fromState.result.status == ZIGZAG_MONITOR_ERROR) {
            statusText = "エラー";
            statusColor = clrRed;
        }

        if (fromState.result.shortMessage != "") {
            statusText = fromState.result.shortMessage;
        }

        bool active = fromProgress.activeSymbol != ""
            && (fromProgress.activeSymbol == fromState.canonicalSymbolName
                || fromProgress.activeSymbol == fromState.symbolName);
        if (active) {
            statusText = "確認中";
            statusColor = C'135,206,250';
            rowColor = C'24,42,57';
        } else if (fromState.result.evaluatedAtSrv == 0) {
            statusText = "未確認";
            statusColor = C'201,211,222';
        } else if (fromState.lastAttemptBarTime != fromProgress.targetBarTime) {
            statusText = "前回 " + statusText;
            statusColor = C'119,132,148';
            rowColor = C'12,15,20';
            if (fromRowIndex % 2 != 0) {
                rowColor = C'20,24,31';
            }
        }

        string symbolText = fromState.canonicalSymbolName;
        if (this.isGmo(fromState.canonicalSymbolName)) {
            symbolText += " [G]";
        }

        string chartText = fromState.chartStatus;
        if (chartText == "") {
            chartText = "—";
            if (fromState.lastEntryTime > 0 || fromState.result.status == ZIGZAG_MONITOR_ENTRY) {
                chartText = "未表示";
            }
        }

        color entryTimeColor = C'158,170,185';
        if (fromState.lastEntryTime > 0) {
            entryTimeColor = clrHotPink;
            if (fromState.lastEntryIsBuy) {
                entryTimeColor = clrAqua;
            }
        }

        string tooltip = this.buildTooltip(fromState, fromProgress);
        datetime currentM5BarTime = (datetime)((long)fromProgress.targetBarTime
            - (long)fromProgress.targetBarTime % 300);
        this.drawRectangle(rowPrefix + "Background", this.panelLeft + 1, rowTop - 1,
            (int)MathMax(1, this.panelWidth - 2), this.rowHeight, rowColor, rowColor);
        this.drawLabel(rowPrefix + "Column0", this.columnLeft[0], rowTop + 2,
            this.columnWidth[0] - 5, this.bodyFontSize, clrWhiteSmoke, symbolText, tooltip);
        this.drawLabel(rowPrefix + "Column1", this.columnLeft[1], rowTop + 2,
            this.columnWidth[1] - 5, this.bodyFontSize, statusColor, statusText, tooltip);
        this.drawDirectionCells(rowPrefix, rowTop + 2, fromState, active, fromProgress.targetBarTime);
        this.drawWaveCell(rowPrefix, rowTop + 2, fromState, active, fromProgress.targetBarTime);
        this.drawStrengthCell(rowPrefix, rowTop + 2, fromState, active, true, currentM5BarTime);
        this.drawStrengthCell(rowPrefix, rowTop + 2, fromState, active, false, currentM5BarTime);
        this.drawLabel(rowPrefix + "Column5", this.columnLeft[5], rowTop + 2,
            this.columnWidth[5] - 5, this.bodyFontSize, entryTimeColor,
            this.formatJapanTime(fromState.lastEntryTime), tooltip);
        this.drawLabel(rowPrefix + "Column6", this.columnLeft[6], rowTop + 2,
            this.columnWidth[6] - 5, this.bodyFontSize, C'201,211,222', chartText, tooltip);
        this.drawButton("Open" + fromState.canonicalSymbolName, this.columnLeft[7], rowTop + 1,
            (int)MathMax(1, this.columnWidth[7] - 5), "表示", C'42,75,116',
            fromState.canonicalSymbolName + "のM1チャートを表示して前面へ移動します。"
                + "\nエントリー成立・監視・自動表示のON/OFFに関係なく操作できます。",
            this.rowHeight - 3);
    }

    /**
     * 補正前のD1・H4・H1・M15・M5・M1方向を、成立状態と独立して表示する。
     */
    void drawDirectionCells(const string fromRowPrefix, const int fromTop,
            ZigZagElliotMonitorSymbolState *fromState, const bool fromActive,
            const datetime fromCurrentM1BarTime) {
        int directionColumns[6] = {2, 9, 10, 11, 12, 13};
        ENUM_TIMEFRAMES timeFrames[6] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1};
        bool fresh = !fromActive && fromCurrentM1BarTime > 0
            && fromState.result.directions.targetM1BarTime == fromCurrentM1BarTime;
        for (int i = 0; i < 6; i++) {
            ZigZagElliotMonitorDirectionInfo directionInfo = fromState.result.directions.items[i];
            bool available = fromState.result.directions.analyzed && directionInfo.available
                && directionInfo.timeFrame == timeFrames[i];
            string text = "—";
            color directionColor = C'119,132,148';
            if (available) {
                text = "SELL";
                if (directionInfo.isBuy) {
                    text = "BUY";
                }

                if (directionInfo.corrected && directionInfo.adoptedAvailable
                        && directionInfo.isBuy != directionInfo.adoptedIsBuy) {
                    text += "補";
                }

                if (fresh) {
                    directionColor = clrHotPink;
                    if (directionInfo.isBuy) {
                        directionColor = clrAqua;
                    }
                }
            }

            int columnIndex = directionColumns[i];
            this.drawLabel(fromRowPrefix + "Column" + IntegerToString(columnIndex),
                this.columnLeft[columnIndex], fromTop, this.columnWidth[columnIndex] - 5,
                this.bodyFontSize, directionColor, text,
                this.getDirectionTooltip(fromState, directionInfo, timeFrames[i], fromActive,
                    fromCurrentM1BarTime));
        }
    }

    /**
     * 元分析の売買方向と、採用された方向補正を時刻・判定理由とともに説明する。
     */
    string getDirectionTooltip(ZigZagElliotMonitorSymbolState *fromState,
            const ZigZagElliotMonitorDirectionInfo &fromDirection,
            const ENUM_TIMEFRAMES fromTimeFrame, const bool fromActive,
            const datetime fromCurrentM1BarTime) {
        string timeFrameText = EnumToString(fromTimeFrame);
        StringReplace(timeFrameText, "PERIOD_", "");
        string text = fromState.canonicalSymbolName + " / " + timeFrameText + "方向"
            + "\n一覧は補正前の元分析の売買方向を表示しています。";
        bool available = fromState.result.directions.analyzed && fromDirection.available
            && fromDirection.timeFrame == fromTimeFrame;
        if (available) {
            string originalDirection = "SELL";
            if (fromDirection.isBuy) {
                originalDirection = "BUY";
            }

            text += "\n元方向：" + originalDirection;
            if (fromDirection.adoptedAvailable) {
                string adoptedDirection = "SELL";
                if (fromDirection.adoptedIsBuy) {
                    adoptedDirection = "BUY";
                }

                text += "\n採用方向：" + adoptedDirection;
                if (fromDirection.corrected && fromDirection.isBuy != fromDirection.adoptedIsBuy) {
                    text += "\n補：" + originalDirection + " → " + adoptedDirection
                        + " の方向補正が採用されています。表示色は元方向のままです。";
                }
            } else {
                text += "\n採用方向：—（有効な情報なし）";
            }
        } else if (fromState.result.directions.analyzed) {
            text += "\n元方向：—（未取得）";
        } else {
            text += "\n元方向：—（未分析）";
        }

        string reason = fromState.result.message;
        if (reason == "") {
            reason = fromState.result.shortMessage;
        }

        text += "\n分析対象M1：" + this.formatServerTime(fromState.result.directions.targetM1BarTime)
            + " SRV / " + this.formatJapanTime(fromState.result.directions.targetM1BarTime) + " JST"
            + "\n確認時刻：" + this.formatServerTime(fromState.result.evaluatedAtSrv)
            + " SRV / " + this.formatJapanTime(fromState.result.evaluatedAtSrv) + " JST"
            + "\n判定理由：" + reason;
        if (fromState.result.directions.targetM1BarTime > 0
                && fromState.result.directions.targetM1BarTime != fromCurrentM1BarTime) {
            text += "\n前回のM1の保存値です。現在の対象M1："
                + this.formatServerTime(fromCurrentM1BarTime) + " SRV";
        }

        if (fromActive) {
            text += "\n現在確認中です。表示は保存済みの元分析で、今回の確認はまだ完了していません。";
        }

        return text;
    }

    /**
     * M5・M1の採用波動を、各足の方向色で同じ論理列内へ表示する。
     * 狭い列と未分析・未採用は単一セルにし、全文をツールチップへ残す。
     */
    void drawWaveCell(const string fromRowPrefix, const int fromTop,
            ZigZagElliotMonitorSymbolState *fromState, const bool fromActive,
            const datetime fromCurrentM1BarTime) {
        int cellWidth = (int)MathMax(0, this.columnWidth[8] - 5);
        string tooltip = this.getWaveTooltip(fromState, fromActive, fromCurrentM1BarTime);
        string fullText = this.getWaveCellText(fromState.result.waves);
        bool fresh = !fromActive && fromCurrentM1BarTime > 0
            && fromState.result.waves.targetM1BarTime == fromCurrentM1BarTime;
        if (!fromState.result.waves.analyzed || !fromState.result.waves.adopted
                || cellWidth < this.bodyFontSize * 8) {
            this.removeWaveParts(fromRowPrefix);
            this.drawLabel(fromRowPrefix + "Column8", this.columnLeft[8], fromTop,
                cellWidth, this.bodyFontSize, C'119,132,148', fullText, tooltip);

            return;
        }

        this.removeObject(this.objectPrefix + fromRowPrefix + "Column8");
        bool corrected = fromState.result.waves.correctionTimeFrame != PERIOD_CURRENT;
        int correctionWidth = 0;
        if (corrected) {
            correctionWidth = this.bodyFontSize * 2;
        }

        int separatorWidth = this.bodyFontSize + 4;
        int waveWidth = cellWidth - separatorWidth - correctionWidth;
        int m5Width = waveWidth / 2;
        int m1Width = waveWidth - m5Width;
        int separatorLeft = this.columnLeft[8] + m5Width;
        int m1Left = separatorLeft + separatorWidth;
        this.drawLabel(fromRowPrefix + "Column8M5", this.columnLeft[8], fromTop,
            m5Width, this.bodyFontSize, this.getWaveColor(fromState.result.waves.m5, fresh),
            this.getWaveText(fromState.result.waves.m5), tooltip);
        this.drawLabel(fromRowPrefix + "Column8Separator", separatorLeft, fromTop,
            separatorWidth, this.bodyFontSize, C'119,132,148', "/", tooltip);
        this.drawLabel(fromRowPrefix + "Column8M1", m1Left, fromTop,
            m1Width, this.bodyFontSize, this.getWaveColor(fromState.result.waves.m1, fresh),
            this.getWaveText(fromState.result.waves.m1), tooltip);
        if (corrected) {
            color correctionColor = C'119,132,148';
            if (fresh) {
                correctionColor = clrGold;
            }

            this.drawLabel(fromRowPrefix + "Column8Correction", m1Left + m1Width, fromTop,
                correctionWidth, this.bodyFontSize, correctionColor, "補", tooltip);
        } else {
            this.removeObject(this.objectPrefix + fromRowPrefix + "Column8Correction");
        }
    }

    /**
     * 単一セルとツールチップで共用する波動一覧の全文を返す。
     */
    string getWaveCellText(const ZigZagElliotMonitorWaveSnapshot &fromWaves) {
        if (!fromWaves.analyzed) {
            return "未分析";
        }

        if (!fromWaves.adopted) {
            return "未採用";
        }

        string text = this.getWaveText(fromWaves.m5) + " / " + this.getWaveText(fromWaves.m1);
        if (fromWaves.correctionTimeFrame != PERIOD_CURRENT) {
            text += " 補";
        }

        return text;
    }

    /**
     * 波番号や補正波文字を変えず、実際の波動方向の矢印を付ける。
     */
    string getWaveText(const ZigZagElliotMonitorWaveInfo &fromWave) {
        if (!fromWave.available || fromWave.mainLabel == "") {
            return "—";
        }

        if (fromWave.isUptrend) {
            return "▲" + fromWave.mainLabel;
        }

        return "▼" + fromWave.mainLabel;
    }

    /**
     * 現在足の取得済み波動だけを方向色にし、過去・確認中・未取得は灰色にする。
     */
    color getWaveColor(const ZigZagElliotMonitorWaveInfo &fromWave, const bool fromFresh) {
        if (!fromFresh || !fromWave.available || fromWave.mainLabel == "") {
            return C'119,132,148';
        }

        if (fromWave.isUptrend) {
            return clrAqua;
        }

        return clrHotPink;
    }

    /**
     * 採用状態、両足の詳細、補正対象と分析時刻を説明する。
     */
    string getWaveTooltip(ZigZagElliotMonitorSymbolState *fromState, const bool fromActive,
            const datetime fromCurrentM1BarTime) {
        string text = fromState.canonicalSymbolName + " / 波動 M5/M1"
            + "\n表示：" + this.getWaveCellText(fromState.result.waves);
        if (!fromState.result.waves.analyzed) {
            text += "\n今回の波動分析結果はまだありません。";
        } else if (!fromState.result.waves.adopted) {
            text += "\n分析結果は判定へ採用されていません。";
        } else {
            text += this.getWaveDetails(fromState.result.waves.m5, "M5")
                + this.getWaveDetails(fromState.result.waves.m1, "M1");
            if (fromState.result.waves.correctionTimeFrame != PERIOD_CURRENT) {
                string correctionTimeFrame = EnumToString(fromState.result.waves.correctionTimeFrame);
                StringReplace(correctionTimeFrame, "PERIOD_", "");
                text += "\n補正対象：" + correctionTimeFrame
                    + "\n補正後に採用された分析の波動を表示しています。元方向の分析ではありません。";
            } else {
                text += "\n方向補正なしで採用された分析の波動です。";
            }
        }

        text += "\n分析対象M1：" + this.formatServerTime(fromState.result.waves.targetM1BarTime)
            + " SRV / " + this.formatJapanTime(fromState.result.waves.targetM1BarTime) + " JST"
            + "\n確認時刻：" + this.formatServerTime(fromState.result.evaluatedAtSrv)
            + " SRV / " + this.formatJapanTime(fromState.result.evaluatedAtSrv) + " JST";
        if (fromState.result.waves.targetM1BarTime > 0
                && fromState.result.waves.targetM1BarTime != fromCurrentM1BarTime) {
            text += "\n前回の分析結果です。現在の対象M1："
                + this.formatServerTime(fromCurrentM1BarTime) + " SRV";
        }

        if (fromActive) {
            text += "\n現在確認中です。表示は保存済みの分析結果で、今回の確認はまだ完了していません。";
        }

        return text;
    }

    /**
     * 1時間足の主波・副波、確定・補完状態とポイント時刻を全文で返す。
     */
    string getWaveDetails(const ZigZagElliotMonitorWaveInfo &fromWave, const string fromTimeFrame) {
        if (!fromWave.available) {
            return "\n" + fromTimeFrame + "：—（波動未取得）";
        }

        string subLabel = fromWave.subLabel;
        if (subLabel == "") {
            subLabel = "—";
        }

        string confirmation = "未確定";
        if (fromWave.confirmed) {
            confirmation = "確定";
        }

        string addedPoint = "なし";
        if (fromWave.addedPoint) {
            addedPoint = "あり";
        }

        return "\n" + fromTimeFrame + "：" + this.getWaveText(fromWave)
            + " / 副波：" + subLabel + " / " + confirmation + " / 補完ポイント：" + addedPoint
            + "\n" + fromTimeFrame + "ポイント：" + this.formatServerTime(fromWave.pointTime)
            + " SRV / " + this.formatJapanTime(fromWave.pointTime) + " JST";
    }

    /**
     * 順位差・判定方向の右に直近の変化時点の増減を別色で並べる。
     * 文字幅を測って配置し、列幅を超える部分は省略して全文をツールチップへ残す。
     */
    void drawStrengthCell(const string fromRowPrefix, const int fromTop,
            ZigZagElliotMonitorSymbolState *fromState, const bool fromActive,
            const bool fromLongMedium, const datetime fromCurrentM5BarTime) {
        int columnIndex = 3;
        if (!fromLongMedium) {
            columnIndex = 4;
        }

        string suffix = fromRowPrefix + "Column" + IntegerToString(columnIndex);
        int cellWidth = (int)MathMax(0, this.columnWidth[columnIndex] - 5);
        string text = this.getStrengthText(fromState.result.strength, fromLongMedium, fromCurrentM5BarTime);
        string tooltip = this.getStrengthTooltip(fromState.result.strength, fromState.canonicalSymbolName,
            fromActive, fromLongMedium, fromCurrentM5BarTime);
        int rankWidth = cellWidth;
        int changeWidth = 0;
        if (fromState.result.strength.hasRanks(fromLongMedium)) {
            int measuredWidth = this.measureTextWidth(text, this.bodyFontSize);
            if (measuredWidth >= 0) {
                rankWidth = (int)MathMin(cellWidth, measuredWidth + 1);
                changeWidth = cellWidth - rankWidth;
            }
        }

        this.drawLabel(suffix, this.columnLeft[columnIndex], fromTop, rankWidth,
            this.bodyFontSize, this.getStrengthColor(fromState.result.strength, fromLongMedium,
                fromCurrentM5BarTime), text, tooltip);
        if (changeWidth > 0) {
            this.drawLabel(suffix + "Delta", this.columnLeft[columnIndex] + rankWidth,
                fromTop, changeWidth, this.bodyFontSize,
                this.getStrengthChangeColor(fromState.result.strength, fromLongMedium, fromCurrentM5BarTime),
                this.getStrengthChangeText(fromState.result.strength, fromLongMedium), tooltip);
        } else {
            this.removeObject(this.objectPrefix + suffix + "Delta");
        }
    }

    /**
     * 取得済みの順位差と、横ばいへ引き継いだ増減方向を表示する。
     */
    string getStrengthText(const ZigZagElliotMonitorStrengthSnapshot &fromStrength,
            const bool fromLongMedium, const datetime fromCurrentM5BarTime) {
        if (!fromStrength.hasRanks(fromLongMedium)) {
            return "—";
        }

        string text = this.formatRankGap(fromStrength.getRankDifference(fromLongMedium));
        if (fromStrength.isGapWaiting(fromLongMedium)) {
            text += " 待";
        } else {
            int direction = fromStrength.getDirection(fromLongMedium);
            if (direction == 1) {
                text += " ↑";
            } else if (direction == -1) {
                text += " ↓";
            } else {
                text += " ?";
            }
        }

        if (fromStrength.targetM5BarTime != fromCurrentM5BarTime) {
            text = "前回 " + text;
        }

        return text;
    }

    /**
     * 直近の変化時点の増減を括弧付きで返し、横ばいでも値を維持する。
     */
    string getStrengthChangeText(const ZigZagElliotMonitorStrengthSnapshot &fromStrength,
            const bool fromLongMedium) {
        if (!fromStrength.hasGapChange(fromLongMedium)) {
            return "（—）";
        }

        int change = fromStrength.getGapChange(fromLongMedium);
        return "（" + this.formatRankGap(change) + "）";
    }

    /**
     * 増減数値の符号で色を選び、根拠不明・前回M5を灰色にする。
     */
    color getStrengthChangeColor(const ZigZagElliotMonitorStrengthSnapshot &fromStrength,
            const bool fromLongMedium, const datetime fromCurrentM5BarTime) {
        if (!fromStrength.hasGapChange(fromLongMedium)
                || fromStrength.targetM5BarTime != fromCurrentM5BarTime) {
            return C'158,170,185';
        }

        int change = fromStrength.getGapChange(fromLongMedium);
        if (change > 0) {
            return clrAqua;
        }

        if (change < 0) {
            return clrHotPink;
        }

        return C'158,170,185';
    }

    /**
     * 現在M5の順位差だけを正負の色で示し、未取得・同順位・前回値を灰色にする。
     */
    color getStrengthColor(const ZigZagElliotMonitorStrengthSnapshot &fromStrength,
            const bool fromLongMedium, const datetime fromCurrentM5BarTime) {
        if (!fromStrength.hasRanks(fromLongMedium)
                || fromStrength.targetM5BarTime != fromCurrentM5BarTime) {
            return C'158,170,185';
        }

        int difference = fromStrength.getRankDifference(fromLongMedium);
        if (difference > 0) {
            return clrAqua;
        }

        if (difference < 0) {
            return clrHotPink;
        }

        return C'158,170,185';
    }

    /**
     * 期間ごとの順位と増減根拠を、取得時刻・取得元とともに表示する。
     * レコード更新時刻だけはDBに保存されたUTCとして扱う。
     */
    string getStrengthTooltip(const ZigZagElliotMonitorStrengthSnapshot &fromStrength,
            const string fromSymbolName, const bool fromActive, const bool fromLongMedium,
            const datetime fromCurrentM5BarTime) {
        string periodLabel = "長中期";
        int baseRank = fromStrength.pairRankInfo.baseLongMediumTermAverageRank;
        int quoteRank = fromStrength.pairRankInfo.quoteLongMediumTermAverageRank;
        CurrencyStrengthRankGapDirectionInfo gapInfo = fromStrength.longMediumGapDirection;
        if (!fromLongMedium) {
            periodLabel = "中短期";
            baseRank = fromStrength.pairRankInfo.baseMediumShortTermAverageRank;
            quoteRank = fromStrength.pairRankInfo.quoteMediumShortTermAverageRank;
            gapInfo = fromStrength.mediumShortGapDirection;
        }

        string text = fromSymbolName + " / " + periodLabel;
        bool ranksAvailable = fromStrength.hasRanks(fromLongMedium);
        if (ranksAvailable) {
            text += "\n一覧：" + this.getStrengthText(fromStrength, fromLongMedium, fromCurrentM5BarTime)
                + this.getStrengthChangeText(fromStrength, fromLongMedium)
                + StringFormat("\n基軸 %s：%d位 / 決済 %s：%d位",
                fromStrength.pairRankInfo.baseCurrency, baseRank,
                fromStrength.pairRankInfo.quoteCurrency, quoteRank)
                + "\n現在の順位差：" + this.formatRankGap(fromStrength.getRankDifference(fromLongMedium))
                + "（決済順位 − 基軸順位）";
        } else if (fromStrength.queried) {
            text += "\n現在順位：未取得";
        } else {
            text += "\n現在順位：未照会";
        }

        if (fromStrength.hasGapChange(fromLongMedium)) {
            text += "\n直近変化の順位差：" + this.formatRankGap(gapInfo.lastChangeBeforeGap)
                + " → " + this.formatRankGap(gapInfo.lastChangeAfterGap)
                + " / 増減：" + this.getStrengthChangeText(fromStrength, fromLongMedium)
                + "\n変化時刻：" + this.formatServerTime(gapInfo.directionChangedAt)
                + " SRV / " + this.formatJapanTime(gapInfo.directionChangedAt) + " JST";
        } else if (ranksAvailable) {
            text += "\n直近変化の増減：—（根拠データ未取得・不整合、または履歴内に変化なし）";
        }

        text += "\n括弧内は最後に順位差が変化したM5の増減（変化後 − 変化前）。"
            + "横ばいでは値を維持し、新しい変化で更新します。根拠不明は—です。";
        string directionText = "未取得";
        if (ranksAvailable) {
            directionText = "不明";
            if (fromStrength.isGapWaiting(fromLongMedium)) {
                directionText = "取得待ち";
            } else if (fromStrength.getDirection(fromLongMedium) == 1) {
                directionText = "上昇";
            } else if (fromStrength.getDirection(fromLongMedium) == -1) {
                directionText = "下降";
            }
        }

        text += "\n増減方向：" + directionText + "（横ばいは直近方向を引き継ぎ）";
        if (ranksAvailable && !fromStrength.hasGapChange(fromLongMedium)
                && fromStrength.getDirection(fromLongMedium) != 0) {
            text += "\n増減の根拠：" + this.formatServerTime(gapInfo.directionChangedAt) + " SRV";
        }

        text += "\n対象M5：" + this.formatServerTime(fromStrength.targetM5BarTime) + " SRV"
            + " / " + this.formatJapanTime(fromStrength.targetM5BarTime) + " JST"
            + "\n照会時刻：" + this.formatServerTime(fromStrength.retrievedAtSrv) + " SRV"
            + " / " + this.formatJapanTime(fromStrength.retrievedAtSrv) + " JST";
        if (ranksAvailable && fromStrength.pairRankInfo.updatedAt > 0) {
            text += "\nレコード更新：" + this.formatServerTime(fromStrength.pairRankInfo.updatedAt) + " UTC";
        }

        if (ranksAvailable && (fromStrength.sourceMode == "LIVE" || fromStrength.sourceMode == "TESTER")) {
            text += "\n現在順位の取得元：" + fromStrength.sourceMode
                + "\n現在順位のDB：" + fromStrength.sourceFileName;
        } else if (ranksAvailable) {
            text += "\n現在順位の取得元：不明";
        } else {
            text += "\n現在順位の取得元：未取得";
        }

        text += "\n取得元表示は現在順位のもので、増減履歴全件の由来を示すものではありません。";
        if (ranksAvailable && fromStrength.targetM5BarTime != fromCurrentM5BarTime) {
            text += "\n前回のM5の保存値です。現在の対象M5："
                + this.formatServerTime(fromCurrentM5BarTime) + " SRV";
        }

        if (fromActive) {
            text += "\n現在確認中です。この通貨強弱は直前の確認データです。";
        }

        return text;
    }

    /**
     * 順位差と変化時点の増減を、正負の符号付きで表示する。
     */
    string formatRankGap(const int fromGap) {
        if (fromGap < 0) {
            return "−" + IntegerToString(-fromGap);
        }

        return "+" + IntegerToString(fromGap);
    }

    /**
     * 省略された説明と、サーバー時刻の判定根拠をツールチップへまとめる。
     */
    string buildTooltip(ZigZagElliotMonitorSymbolState *fromState,
            const ZigZagElliotMonitorProgress &fromProgress) {
        string text = fromState.canonicalSymbolName + " / " + fromState.symbolName
            + "\n現在の対象M1：" + this.formatServerTime(fromProgress.targetBarTime) + " SRV"
            + "\n直近の確認対象M1：" + this.formatServerTime(fromState.lastAttemptBarTime) + " SRV"
            + "\n判定：" + fromState.result.message
            + "\nM1判定足：" + this.formatServerTime(fromState.result.barTime) + " SRV"
            + "\n強弱対象：" + this.formatServerTime(fromState.result.targetM5BarTime) + " SRV"
            + "\n確認時刻：" + this.formatServerTime(fromState.result.evaluatedAtSrv) + " SRV"
            + "\n確認処理時間：" + this.formatDuration(fromState.result.durationMs);
        if (fromProgress.activeSymbol != ""
                && (fromProgress.activeSymbol == fromState.canonicalSymbolName
                    || fromProgress.activeSymbol == fromState.symbolName)) {
            text += "\n現在確認中です。判定・処理時間は直前に完了した確認の記録です。";
        } else if (fromState.result.evaluatedAtSrv > 0
                && fromState.lastAttemptBarTime != fromProgress.targetBarTime) {
            text += "\n前回の対象足の結果です。現在の対象M1の結果ではありません。";
        }

        if (fromState.lastEntryTime > 0) {
            string direction = "SELL";
            if (fromState.lastEntryIsBuy) {
                direction = "BUY";
            }

            text += "\n直近成立 " + direction + "：" + this.formatJapanTime(fromState.lastEntryTime)
                + " JST\n直近成立：" + this.formatServerTime(fromState.lastEntryTime) + " SRV";
        }

        text += "\n直近の表示処理結果（自動／手動）：" + fromState.chartStatus
            + "\n表示結果は処理時点の記録です。手動で閉じても保持します。";

        return text;
    }

    /**
     * 共通定義のGMO対象だけに印を付ける。
     */
    bool isGmo(const string fromSymbolName) {
        SymbolNameInfo *symbolInfo = this.gmoSymbols.getSymbolNameInfo(fromSymbolName);
        if (symbolInfo == NULL) {
            return false;
        }

        return symbolInfo.isTarget;
    }

    /**
     * サーバー時刻を共通ルールで日本時間へ変換して表示する。
     */
    string formatJapanTime(const datetime fromTime) {
        if (fromTime <= 0) {
            return "—";
        }

        return TimeUtil::formatYyyymmddhhmiss(TimeJapanUtil::getJapanTime(fromTime));
    }

    /**
     * 根拠時刻を変換せずに表示する。
     */
    string formatServerTime(const datetime fromTime) {
        if (fromTime <= 0) {
            return "—";
        }

        return TimeUtil::formatYyyymmddhhmiss(fromTime);
    }

    /**
     * 未計測を区別して確認処理のミリ秒を表示する。
     */
    string formatDuration(const double fromDurationMs) {
        if (fromDurationMs < 0) {
            return "未計測";
        }

        return StringFormat("%.1f ms", fromDurationMs);
    }

    /**
     * ラベルと同じフォントの文字幅を返す。測定できない場合は-1。
     */
    int measureTextWidth(const string fromText, const int fromFontSize) {
        uint textWidth = 0;
        uint textHeight = 0;
        bool fontReady = true;
        if (this.measuredFontSize != fromFontSize) {
            fontReady = TextSetFont("Meiryo", -fromFontSize * 10);
            if (fontReady) {
                this.measuredFontSize = fromFontSize;
            }
        }

        if (!fontReady || !TextGetSize(fromText, textWidth, textHeight)) {
            return -1;
        }

        return (int)textWidth;
    }

    /**
     * 全文を測定し、列幅に収まらない場合だけ末尾を省略する。
     */
    string fitText(const string fromText, const int fromWidth, const int fromFontSize) {
        if (fromText == "" || fromWidth <= 0) {
            return "";
        }

        int fullWidth = this.measureTextWidth(fromText, fromFontSize);
        if (fullWidth < 0) {
            int maximumCount = fromWidth / (fromFontSize * 2);

            return StringSubstr(fromText, 0, maximumCount);
        }

        if (fullWidth <= fromWidth) {
            return fromText;
        }

        uint textWidth = 0;
        uint textHeight = 0;
        if (!TextGetSize("…", textWidth, textHeight) || (int)textWidth > fromWidth) {
            return "";
        }

        int leftCount = 0;
        int rightCount = StringLen(fromText);
        while (leftCount < rightCount) {
            int middleCount = leftCount + (rightCount - leftCount + 1) / 2;
            string shortened = StringSubstr(fromText, 0, middleCount) + "…";
            if (TextGetSize(shortened, textWidth, textHeight) && (int)textWidth <= fromWidth) {
                leftCount = middleCount;
            } else {
                rightCount = middleCount - 1;
            }
        }

        return StringSubstr(fromText, 0, leftCount) + "…";
    }

    /**
     * 文字ラベルの可変項目だけを更新する。
     */
    void drawLabel(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromWidth, const int fromFontSize, const color fromColor,
            const string fromText, const string fromTooltip) {
        int objectIndex = this.ensureObject(fromSuffix, OBJ_LABEL);
        if (objectIndex < 0) {
            return;
        }

        string objectName = this.objects[objectIndex].objectName;
        this.setInteger(objectName, OBJPROP_XDISTANCE, fromLeft, this.objects[objectIndex].positionX);
        this.setInteger(objectName, OBJPROP_YDISTANCE, fromTop, this.objects[objectIndex].positionY);
        this.setInteger(objectName, OBJPROP_FONTSIZE, fromFontSize, this.objects[objectIndex].fontSize);
        this.setInteger(objectName, OBJPROP_COLOR, fromColor, this.objects[objectIndex].foreground);
        string text = this.fitText(fromText, fromWidth, fromFontSize);
        if (text == "") {
            text = " ";
        }

        this.setString(objectName, OBJPROP_TEXT, text, this.objects[objectIndex].text);
        this.setString(objectName, OBJPROP_TOOLTIP, fromTooltip, this.objects[objectIndex].tooltip);
    }

    /**
     * 背景矩形の位置・サイズ・色を必要な場合だけ更新する。
     */
    void drawRectangle(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromWidth, const int fromHeight, const color fromBackground, const color fromBorder) {
        int objectIndex = this.ensureObject(fromSuffix, OBJ_RECTANGLE_LABEL);
        if (objectIndex < 0) {
            return;
        }

        string objectName = this.objects[objectIndex].objectName;
        this.setInteger(objectName, OBJPROP_XDISTANCE, fromLeft, this.objects[objectIndex].positionX);
        this.setInteger(objectName, OBJPROP_YDISTANCE, fromTop, this.objects[objectIndex].positionY);
        this.setInteger(objectName, OBJPROP_XSIZE, fromWidth, this.objects[objectIndex].width);
        this.setInteger(objectName, OBJPROP_YSIZE, fromHeight, this.objects[objectIndex].height);
        this.setInteger(objectName, OBJPROP_BGCOLOR, fromBackground, this.objects[objectIndex].background);
        this.setInteger(objectName, OBJPROP_COLOR, fromBorder, this.objects[objectIndex].foreground);
        this.setString(objectName, OBJPROP_TOOLTIP, "\n", this.objects[objectIndex].tooltip);
    }

    /**
     * ボタンの表示だけを更新する。押下状態の解除はイベント処理側が行う。
     */
    void drawButton(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromWidth, const string fromText, const color fromBackground, const string fromTooltip,
            const int fromHeight = 27) {
        int objectIndex = this.ensureObject(fromSuffix, OBJ_BUTTON);
        if (objectIndex < 0) {
            return;
        }

        string objectName = this.objects[objectIndex].objectName;
        this.setInteger(objectName, OBJPROP_XDISTANCE, fromLeft, this.objects[objectIndex].positionX);
        this.setInteger(objectName, OBJPROP_YDISTANCE, fromTop, this.objects[objectIndex].positionY);
        this.setInteger(objectName, OBJPROP_XSIZE, fromWidth, this.objects[objectIndex].width);
        this.setInteger(objectName, OBJPROP_YSIZE, fromHeight, this.objects[objectIndex].height);
        this.setInteger(objectName, OBJPROP_FONTSIZE, this.bodyFontSize, this.objects[objectIndex].fontSize);
        this.setInteger(objectName, OBJPROP_BGCOLOR, fromBackground, this.objects[objectIndex].background);
        this.setInteger(objectName, OBJPROP_COLOR, clrWhite, this.objects[objectIndex].foreground);
        this.setString(objectName, OBJPROP_TEXT, this.fitText(fromText, fromWidth - 8, this.bodyFontSize),
            this.objects[objectIndex].text);
        this.setString(objectName, OBJPROP_TOOLTIP, fromTooltip, this.objects[objectIndex].tooltip);
    }

    /**
     * 固定プロパティを新規作成時だけ設定して、反映値の保持位置を返す。
     */
    int ensureObject(const string fromSuffix, const ENUM_OBJECT fromType) {
        string objectName = this.objectPrefix + fromSuffix;
        int objectIndex = this.findObject(objectName);
        if (objectIndex >= 0 && this.objects[objectIndex].created) {
            return objectIndex;
        }

        if (objectIndex < 0) {
            objectIndex = ArraySize(this.objects);
            if (ArrayResize(this.objects, objectIndex + 1) != objectIndex + 1) {
                return -1;
            }

            this.objects[objectIndex].objectName = objectName;
        }

        this.objects[objectIndex].reset();
        if (!ObjectCreate(this.chartId, objectName, fromType, 0, 0, 0)) {
            return -1;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        if (fromType == OBJ_RECTANGLE_LABEL) {
            ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 0);
        } else {
            ObjectSetString(this.chartId, objectName, OBJPROP_FONT, "Meiryo");
            ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 2);
            if (fromType == OBJ_LABEL) {
                ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            } else {
                ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false);
                ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_COLOR, C'97,112,132');
            }
        }

        this.objects[objectIndex].created = true;
        this.changed = true;

        return objectIndex;
    }

    /**
     * 所有オブジェクト名に対応する保持位置を取得する。
     */
    int findObject(const string fromObjectName) {
        int objectCount = ArraySize(this.objects);
        for (int i = 0; i < objectCount; i++) {
            if (this.objects[i].objectName == fromObjectName) {
                return i;
            }
        }

        return -1;
    }

    /**
     * 整数プロパティに差分がある場合だけ反映する。
     */
    void setInteger(const string fromObjectName, const ENUM_OBJECT_PROPERTY_INTEGER fromProperty,
            const long fromValue, long &fromPrevious) {
        if (fromValue == fromPrevious) {
            return;
        }

        if (ObjectSetInteger(this.chartId, fromObjectName, fromProperty, fromValue)) {
            fromPrevious = fromValue;
            this.changed = true;
        }
    }

    /**
     * 文字列プロパティに差分がある場合だけ反映する。
     */
    void setString(const string fromObjectName, const ENUM_OBJECT_PROPERTY_STRING fromProperty,
            const string fromValue, string &fromPrevious) {
        if (fromValue == fromPrevious) {
            return;
        }

        if (ObjectSetString(this.chartId, fromObjectName, fromProperty, fromValue)) {
            fromPrevious = fromValue;
            this.changed = true;
        }
    }

    /**
     * 表示範囲から外れた通貨の手動ボタンを削除し、再表示できる状態へ戻す。
     * 行番号では判定せず、並び替え後も表示中の同じ通貨のボタンを維持する。
     */
    void removeHiddenChartButtons(CArrayObj &fromStates, const int &fromIndexes[]) {
        string buttonPrefix = this.objectPrefix + "Open";
        int objectCount = ArraySize(this.objects);
        for (int i = 0; i < objectCount; i++) {
            if (!this.objects[i].created || StringFind(this.objects[i].objectName, buttonPrefix) != 0) {
                continue;
            }

            bool visible = false;
            for (int j = 0; j < this.visibleRowCount; j++) {
                ZigZagElliotMonitorSymbolState *state = fromStates.At(fromIndexes[j]);
                if (state != NULL
                        && this.objects[i].objectName == this.getChartButtonName(state.canonicalSymbolName)) {
                    visible = true;
                    break;
                }
            }

            if (!visible) {
                this.removeObject(this.objects[i].objectName);
            }
        }
    }

    /**
     * 単一セルへの切替えや行削除時に、分割表示の波動ラベルを消去する。
     *
     * @param fromRowPrefix 固有接頭辞を含まない行名。
     */
    void removeWaveParts(const string fromRowPrefix) {
        string wavePrefix = this.objectPrefix + fromRowPrefix + "Column8";
        this.removeObject(wavePrefix + "M5");
        this.removeObject(wavePrefix + "Separator");
        this.removeObject(wavePrefix + "M1");
        this.removeObject(wavePrefix + "Correction");
    }

    /**
     * 表示範囲から外れた行のオブジェクトだけを削除する。
     */
    void removeRow(const int fromRowIndex) {
        string rowPrefix = this.objectPrefix + "Row" + IntegerToString(fromRowIndex);
        this.removeObject(rowPrefix + "Background");
        for (int i = 0; i < 7; i++) {
            this.removeObject(rowPrefix + "Column" + IntegerToString(i));
        }

        this.removeObject(rowPrefix + "Column8");
        this.removeObject(rowPrefix + "Column3Delta");
        this.removeObject(rowPrefix + "Column4Delta");
        this.removeWaveParts("Row" + IntegerToString(fromRowIndex));
        for (int i = 9; i < 14; i++) {
            this.removeObject(rowPrefix + "Column" + IntegerToString(i));
        }
    }

    /**
     * 所有一覧にある作成済みオブジェクトだけを削除する。
     */
    void removeObject(const string fromObjectName) {
        int objectIndex = this.findObject(fromObjectName);
        if (objectIndex < 0 || !this.objects[objectIndex].created) {
            return;
        }

        if (ObjectDelete(this.chartId, fromObjectName)) {
            this.objects[objectIndex].created = false;
            this.changed = true;
        }
    }
};

#endif // MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_MQH
