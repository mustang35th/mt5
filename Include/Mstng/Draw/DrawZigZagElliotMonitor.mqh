#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_MQH

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSymbolState.mqh>
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
 * GMO通貨のM1判定とチャート表示状況を、独立した固定パネルに表示する。
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
        this.gmoSymbols.setGmo();
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
        this.initialized = true;
        if (this.ensureObject("Panel", OBJ_RECTANGLE_LABEL) < 0) {
            this.destroy();

            return false;
        }

        return true;
    }

    /**
     * ENTRYを先頭、それ以外を通貨名順に並べ、変更した項目だけを反映する。
     *
     * @param fromStates 監視対象の状態一覧。元の並びは変更しない。
     * @param fromMonitoring 監視が有効な場合true。
     * @param fromAutoOpen 自動チャート表示が有効な場合true。
     * @param fromOpenCount 監視機能が現在保持しているチャート枚数。
     * @param fromMaxOpenCharts チャート表示枚数の上限。
     * @param fromLastEvaluationTime 最後に判定・データ確認を試みたサーバー時刻。
     * @return 描画オブジェクトを変更した場合true。
     */
    bool update(CArrayObj &fromStates, const bool fromMonitoring, const bool fromAutoOpen,
            const int fromOpenCount, const int fromMaxOpenCharts, const datetime fromLastEvaluationTime) {
        if (!this.initialized) {
            return false;
        }

        this.changed = false;
        this.measuredFontSize = 0;
        int indexes[];
        int confirmedCount = 0;
        int entryCount = 0;
        int gmoCount = 0;
        int stateCount = this.prepareIndexes(fromStates, indexes, confirmedCount, entryCount, gmoCount);
        this.prepareLayout(stateCount);
        this.drawRectangle("Panel", this.panelLeft, this.panelTop, this.panelWidth,
            this.panelHeight, C'12,15,20', C'65,74,88');

        string title = StringFormat("通貨監視 %dペア / M1", stateCount);
        if (stateCount > 0 && gmoCount == stateCount) {
            title = StringFormat("GMO監視 %dペア / M1", stateCount);
        }

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

        this.drawLabel("Title", this.contentLeft, this.panelTop + 11, this.titleWidth,
            this.bodyFontSize + 2, clrWhiteSmoke, title, "M1新バーごとに現行M1条件のエントリー判定を監視します。");
        this.drawButton("MonitorButton", this.monitorButtonLeft, this.buttonTop, this.buttonWidth,
            monitorText, monitorColor, "監視のON/OFF。OFF中は最後の判定を保持します。");
        this.drawButton("AutoButton", this.autoButtonLeft, this.buttonTop, this.buttonWidth,
            autoText, autoColor, "新規成立時のチャート自動表示を切り替えます。");
        this.drawColumnHeaders();
        this.removeHiddenChartButtons(fromStates, indexes);

        for (int i = 0; i < this.visibleRowCount; i++) {
            ZigZagElliotMonitorSymbolState *state = fromStates.At(indexes[i]);
            this.drawRow(i, state);
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

        string summary = StringFormat("確認済み %d / %d  ・ ENTRY %d", confirmedCount, stateCount, entryCount);
        if (this.visibleRowCount < stateCount) {
            summary += StringFormat("  ・ 一覧 %d / %d（高さ不足）", this.visibleRowCount, stateCount);
        }

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
            this.bodyFontSize, C'201,211,222', summary, summary);
        this.drawLabel("Cycle", this.contentLeft, this.footerTop + 24, this.contentWidth,
            this.bodyFontSize, C'153,167,184', cycleText, cycleTooltip);

        return this.changed;
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

    /** 両ボタンの上位置。 */
    int buttonTop;

    /** 両ボタンの横幅。 */
    int buttonWidth;

    /** 列見出しの上位置。 */
    int headerTop;

    /** 最初のデータ行の上位置。 */
    int rowsTop;

    /** 下部の集計表示の上位置。 */
    int footerTop;

    /** データ行の高さ。 */
    int rowHeight;

    /** チャートの高さ内へ表示できる行数。 */
    int visibleRowCount;

    /** 6列それぞれの左位置。 */
    int columnLeft[6];

    /** 6列それぞれの横幅。 */
    int columnWidth[6];

    /**
     * 有効な状態の参照番号をENTRY優先・通貨名順に並べる。
     */
    int prepareIndexes(CArrayObj &fromStates, int &fromIndexes[], int &fromConfirmedCount,
            int &fromEntryCount, int &fromGmoCount) {
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
                bool currentEntry = current.result.status == ZIGZAG_MONITOR_ENTRY;
                bool previousEntry = previous.result.status == ZIGZAG_MONITOR_ENTRY;
                bool movePrevious = StringCompare(current.canonicalSymbolName, previous.canonicalSymbolName) < 0;
                if (currentEntry != previousEntry) {
                    movePrevious = currentEntry;
                }

                if (!movePrevious) {
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
        this.panelWidth = (int)MathMax(1, MathMin(900, chartWidth - this.panelLeft * 2));
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
        this.autoButtonLeft = this.contentLeft + this.contentWidth - this.buttonWidth;
        this.monitorButtonLeft = this.autoButtonLeft - this.buttonWidth - 8;
        this.titleWidth = this.monitorButtonLeft - this.contentLeft - 12;
        this.headerTop = this.panelTop + 60;
        if (this.panelWidth < 600) {
            int buttonGap = (int)MathMin(8, this.contentWidth / 20);
            this.buttonWidth = (int)MathMax(1, (this.contentWidth - buttonGap) / 2);
            this.buttonTop = this.panelTop + 39;
            this.monitorButtonLeft = this.contentLeft;
            this.autoButtonLeft = this.contentLeft + this.buttonWidth + buttonGap;
            this.titleWidth = this.contentWidth;
            this.headerTop = this.panelTop + 80;
        }

        this.rowsTop = this.headerTop + 27;
        int availableHeight = (int)MathMax(0, chartHeight - this.rowsTop - 70);
        this.rowHeight = (int)MathMax(24, this.bodyFontSize * 2 + 4);
        if (fromStateCount > 0 && availableHeight < fromStateCount * this.rowHeight) {
            this.rowHeight = (int)MathMax(MathMax(18, this.bodyFontSize * 2), availableHeight / fromStateCount);
        }

        this.visibleRowCount = (int)MathMin(fromStateCount, availableHeight / this.rowHeight);
        this.footerTop = this.rowsTop + (int)MathMax(1, this.visibleRowCount) * this.rowHeight + 12;
        this.panelHeight = (int)MathMin(chartHeight - this.panelTop,
            this.footerTop - this.panelTop + 56);
        this.columnWidth[5] = (int)MathMin(this.contentWidth, MathMin(76, MathMax(40, this.contentWidth / 10)));
        int textWidth = this.contentWidth - this.columnWidth[5];
        this.columnWidth[0] = textWidth * 17 / 100;
        this.columnWidth[1] = textWidth * 14 / 100;
        this.columnWidth[2] = textWidth * 9 / 100;
        this.columnWidth[3] = textWidth * 32 / 100;
        this.columnWidth[4] = textWidth - this.columnWidth[0] - this.columnWidth[1]
            - this.columnWidth[2] - this.columnWidth[3];
        this.columnLeft[0] = this.contentLeft;
        for (int i = 1; i < 6; i++) {
            this.columnLeft[i] = this.columnLeft[i - 1] + this.columnWidth[i - 1];
        }
    }

    /**
     * 6列の見出しを表示する。
     */
    void drawColumnHeaders() {
        string titles[6] = {"通貨ペア [G]", "判定", "方向", "直近成立時刻 JST", "表示結果", "操作"};
        this.drawRectangle("Header", this.panelLeft + 1, this.headerTop - 4,
            (int)MathMax(1, this.panelWidth - 2), 27, C'31,39,50', C'31,39,50');
        for (int i = 0; i < 6; i++) {
            this.drawLabel("Header" + IntegerToString(i), this.columnLeft[i], this.headerTop,
                this.columnWidth[i] - 5, this.bodyFontSize, C'179,193,210', titles[i], titles[i]);
        }
    }

    /**
     * 現在判定、直近成立時刻、チャート状態を互いに独立した列へ表示する。
     */
    void drawRow(const int fromRowIndex, ZigZagElliotMonitorSymbolState *fromState) {
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
        string directionText = "—";
        color statusColor = clrGold;
        if (fromState.result.status == ZIGZAG_MONITOR_ENTRY) {
            statusText = "ENTRY";
            directionText = "SELL";
            statusColor = clrHotPink;
            rowColor = C'45,23,35';
            if (fromState.result.isBuy) {
                directionText = "BUY";
                statusColor = clrAqua;
                rowColor = C'17,38,43';
            }
        } else if (fromState.result.status == ZIGZAG_MONITOR_NOT_MATCHED) {
            statusText = "不成立";
            statusColor = C'158,170,185';
        } else if (fromState.result.status == ZIGZAG_MONITOR_ERROR) {
            statusText = "エラー";
            statusColor = clrCoral;
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

        string tooltip = this.buildTooltip(fromState);
        this.drawRectangle(rowPrefix + "Background", this.panelLeft + 1, rowTop - 1,
            (int)MathMax(1, this.panelWidth - 2), this.rowHeight, rowColor, rowColor);
        this.drawLabel(rowPrefix + "Column0", this.columnLeft[0], rowTop + 2,
            this.columnWidth[0] - 5, this.bodyFontSize, clrWhiteSmoke, symbolText, tooltip);
        this.drawLabel(rowPrefix + "Column1", this.columnLeft[1], rowTop + 2,
            this.columnWidth[1] - 5, this.bodyFontSize, statusColor, statusText, tooltip);
        this.drawLabel(rowPrefix + "Column2", this.columnLeft[2], rowTop + 2,
            this.columnWidth[2] - 5, this.bodyFontSize, statusColor, directionText, tooltip);
        this.drawLabel(rowPrefix + "Column3", this.columnLeft[3], rowTop + 2,
            this.columnWidth[3] - 5, this.bodyFontSize, entryTimeColor,
            this.formatJapanTime(fromState.lastEntryTime), tooltip);
        this.drawLabel(rowPrefix + "Column4", this.columnLeft[4], rowTop + 2,
            this.columnWidth[4] - 5, this.bodyFontSize, C'201,211,222', chartText, tooltip);
        this.drawButton("Open" + fromState.canonicalSymbolName, this.columnLeft[5], rowTop + 1,
            (int)MathMax(1, this.columnWidth[5] - 5), "表示", C'42,75,116',
            fromState.canonicalSymbolName + "のM1チャートを表示して前面へ移動します。"
                + "\nエントリー成立・監視・自動表示のON/OFFに関係なく操作できます。",
            this.rowHeight - 3);
    }

    /**
     * 省略された説明と、サーバー時刻の判定根拠をツールチップへまとめる。
     */
    string buildTooltip(ZigZagElliotMonitorSymbolState *fromState) {
        string text = fromState.canonicalSymbolName + " / " + fromState.symbolName
            + "\n判定：" + fromState.result.message
            + "\nM1判定足：" + this.formatServerTime(fromState.result.barTime) + " SRV"
            + "\n強弱対象：" + this.formatServerTime(fromState.result.targetM5BarTime) + " SRV"
            + "\n確認時刻：" + this.formatServerTime(fromState.result.evaluatedAtSrv) + " SRV";
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
     * 全文を測定し、列幅に収まらない場合だけ末尾を省略する。
     */
    string fitText(const string fromText, const int fromWidth, const int fromFontSize) {
        if (fromText == "" || fromWidth <= 0) {
            return "";
        }

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
            int maximumCount = fromWidth / (fromFontSize * 2);

            return StringSubstr(fromText, 0, maximumCount);
        }

        if ((int)textWidth <= fromWidth) {
            return fromText;
        }

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
        this.setString(objectName, OBJPROP_TEXT, this.fitText(fromText, fromWidth, fromFontSize),
            this.objects[objectIndex].text);
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
     * 表示範囲から外れた行のオブジェクトだけを削除する。
     */
    void removeRow(const int fromRowIndex) {
        string rowPrefix = this.objectPrefix + "Row" + IntegerToString(fromRowIndex);
        this.removeObject(rowPrefix + "Background");
        for (int i = 0; i < 5; i++) {
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
