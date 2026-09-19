#ifndef MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_CONTROLLER_MQH
#define MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_CONTROLLER_MQH

#include <Mstng\Database\Query\ZigZagElliotAlertHistoryReader.mqh>
#include <Mstng\Draw\DrawZigZagElliotAlertHistory.mqh>
#include <Mstng\Draw\DrawZigZagElliotAlertMarkers.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryData.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 保存済みM5アラートの選択・履歴準備・チャート表示を制御する。
 * 分析クラスや売買・メール送信の処理は呼び出さない。
 */
class ZigZagElliotAlertHistoryController {
public:
    /**
     * 操作状態を初期化する。
     */
    ZigZagElliotAlertHistoryController() {
        this.chartId = 0;
        this.drawer = NULL;
        this.markerDrawer = NULL;
        this.selectedIndex = -1;
        this.resolvedRunId = 0;
        this.snapshotLoaded = false;
        this.historyPending = false;
        this.needsRedraw = false;
        this.autoScrollCaptured = false;
        this.ownsMarker = false;
        this.view = ALERT_HISTORY_SELECTED;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 自分が作成した描画と接続だけを解放する。
     */
    ~ZigZagElliotAlertHistoryController() {
        this.destroy();
    }

    /**
     * 検索条件を検証し、指定期間の最初のアラートを表示する。
     *
     * @return 初期化結果。
     */
    int initialize(const ZigZagElliotAlertHistoryConfig &fromConfig) {
        this.config = fromConfig;
        this.chartId = ChartID();
        this.symbolName = ChartSymbol(this.chartId);
        if (ChartPeriod(this.chartId) != PERIOD_M5) {
            this.logger.error(__FUNCTION__, "履歴表示はM5チャートで使用してください。");
            return INIT_PARAMETERS_INCORRECT;
        }
        if (!this.config.getPeriod(this.startTime, this.endTime, this.loadError)) {
            this.logger.error(__FUNCTION__, this.loadError);
            return INIT_PARAMETERS_INCORRECT;
        }
        if (ObjectFind(this.chartId, "ZzeHistoryOwner") >= 0) {
            this.logger.error(__FUNCTION__, "同じチャートには履歴表示を一つだけ追加してください。");
            return INIT_FAILED;
        }
        this.ownsMarker = ObjectCreate(this.chartId, "ZzeHistoryOwner", OBJ_LABEL, 0, 0, 0);
        if (!this.ownsMarker) {
            return INIT_FAILED;
        }
        // オブジェクト名の63文字制限内に収め、重複起動時は既存の接頭辞を所有しない。
        this.prefix = "ZzeHistory-" + IntegerToString((long)GetMicrosecondCount()) + "-";
        ObjectSetInteger(this.chartId, "ZzeHistoryOwner", OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, "ZzeHistoryOwner", OBJPROP_TEXT, "");
        this.drawer = new DrawZigZagElliotAlertHistory(this.chartId, this.prefix + "Wave-");
        if (this.drawer == NULL) {
            return INIT_FAILED;
        }
        this.markerDrawer = new DrawZigZagElliotAlertMarkers(this.chartId, this.prefix);
        if (this.markerDrawer == NULL) {
            return INIT_FAILED;
        }
        this.originalAutoScroll = (bool)ChartGetInteger(this.chartId, CHART_AUTOSCROLL);
        this.autoScrollCaptured = true;
        if (!EventSetTimer(1)) {
            this.logger.error(__FUNCTION__, "履歴表示タイマーを開始できません。");
            return INIT_FAILED;
        }
        IndicatorSetString(INDICATOR_SHORTNAME, "ZigZagElliot Alert History");
        this.reload();
        return INIT_SUCCEEDED;
    }

    /**
     * ボタンクリックと表示領域の変更を処理する。
     */
    void onChartEvent(const int fromEventId, const string fromObjectName) {
        if (fromEventId == CHARTEVENT_CHART_CHANGE) {
            this.needsRedraw = true;
            return;
        }
        if (fromEventId == CHARTEVENT_OBJECT_CLICK
                && StringFind(fromObjectName, this.prefix + "Marker-") == 0) {
            for (int i = 0; i < ArraySize(this.alertIds); i++) {
                if (fromObjectName == this.prefix + "Marker-" + IntegerToString(this.alertIds[i])) {
                    this.select(i);
                    return;
                }
            }
            return;
        }
        if (fromEventId != CHARTEVENT_OBJECT_CLICK
                || StringFind(fromObjectName, this.prefix + "Ui-") != 0) {
            return;
        }
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
        string action = StringSubstr(fromObjectName, StringLen(this.prefix + "Ui-"));
        if (action == "Previous" && this.selectedIndex > 0) {
            this.select(this.selectedIndex - 1);
        } else if (action == "Next" && this.selectedIndex + 1 < ArraySize(this.alertIds)) {
            this.select(this.selectedIndex + 1);
        } else if (action == "Refresh") {
            this.reload();
        } else if (action == "Locate" && this.snapshotLoaded) {
            this.beginHistory();
        } else if (this.snapshotLoaded) {
            bool canCompare = this.snapshot.correctionStatus == "APPLIED";
            if (action == "Selected" && (canCompare || this.snapshot.correctionStatus == "NONE")) {
                this.view = ALERT_HISTORY_SELECTED;
            } else if (action == "Original" && this.snapshot.originalAvailable) {
                this.view = ALERT_HISTORY_ORIGINAL;
            } else if (action == "Comparison" && canCompare) {
                this.view = ALERT_HISTORY_COMPARISON;
            }
        }
        this.render();
    }

    /**
     * 非同期で取得される価格履歴を再確認し、必要な場合だけ描画する。
     */
    void onTimer() {
        if (this.historyPending) {
            this.prepareHistory();
            this.needsRedraw = true;
        }
        if (this.needsRedraw) {
            this.render();
        }
    }

    /**
     * タイマー、DB接続、所有オブジェクトを解放する。
     */
    void destroy() {
        EventKillTimer();
        this.reader.close();
        if (this.drawer != NULL) {
            delete this.drawer;
            this.drawer = NULL;
        }
        if (this.markerDrawer != NULL) {
            this.markerDrawer.clear();
            delete this.markerDrawer;
            this.markerDrawer = NULL;
        }
        if (this.prefix != "") {
            ObjectsDeleteAll(this.chartId, this.prefix);
        }
        if (this.ownsMarker) {
            ObjectDelete(this.chartId, "ZzeHistoryOwner");
            this.ownsMarker = false;
        }
        if (this.autoScrollCaptured) {
            ChartSetInteger(this.chartId, CHART_AUTOSCROLL, this.originalAutoScroll);
            this.autoScrollCaptured = false;
        }
        ArrayFree(this.alertIds);
        ArrayFree(this.markers);
        this.snapshot.clear();
    }

private:
    /** 履歴表示設定。 */
    ZigZagElliotAlertHistoryConfig config;
    /** 読み取り専用Reader。 */
    ZigZagElliotAlertHistoryReader reader;
    /** 選択した保存分析。 */
    ZigZagElliotAlertHistorySnapshot snapshot;
    /** 保存波動の描画。 */
    DrawZigZagElliotAlertHistory *drawer;
    /** 全件の保存ラベル描画。 */
    DrawZigZagElliotAlertMarkers *markerDrawer;
    /** 選択一覧と同じ順序の保存ラベル。 */
    ZigZagElliotAlertHistoryMarker markers[];
    /** 操作ログ。 */
    Logger logger;
    /** 対象チャート。 */
    long chartId;
    /** 対象通貨。 */
    string symbolName;
    /** 自分の描画だけを識別する接頭辞。 */
    string prefix;
    /** 条件に一致するアラートIDの時刻順配列。 */
    long alertIds[];
    /** 現在の一覧内位置。 */
    int selectedIndex;
    /** 検索対象Run。 */
    long resolvedRunId;
    /** 開始日時以上。 */
    datetime startTime;
    /** 終了日の翌日未満。 */
    datetime endTime;
    /** 現在の表示モード。 */
    ZigZagElliotAlertHistoryView view;
    /** 親アラートを読み込めた場合true。 */
    bool snapshotLoaded;
    /** 価格履歴を取得中の場合true。 */
    bool historyPending;
    /** 描画更新が必要な場合true。 */
    bool needsRedraw;
    /** 価格履歴の再確認回数。 */
    int historyAttempts;
    /** 波動を表示するために必要な最初の時刻。 */
    datetime historyStartTime;
    /** 一覧の全ラベルを含む履歴終了時刻。 */
    datetime historyEndTime;
    /** 価格履歴の状態説明。 */
    string historyMessage;
    /** 読取エラーまたは検索結果の説明。 */
    string loadError;
    /** 元の自動スクロール状態を保持した場合true。 */
    bool autoScrollCaptured;
    /** 初期化前の自動スクロール。 */
    bool originalAutoScroll;
    /** チャート内の二重起動防止マーカーを所有する場合true。 */
    bool ownsMarker;

    /**
     * 一覧を再読込する。同じIDが残っている場合は選択を維持する。
     */
    void reload() {
        long previousId = 0;
        if (this.selectedIndex >= 0 && this.selectedIndex < ArraySize(this.alertIds)) {
            previousId = this.alertIds[this.selectedIndex];
        }
        this.reader.close();
        this.snapshot.clear();
        this.snapshotLoaded = false;
        this.historyPending = false;
        this.historyMessage = "";
        this.selectedIndex = -1;
        this.resolvedRunId = 0;
        ArrayFree(this.alertIds);
        ArrayFree(this.markers);
        this.drawer.clear();
        this.markerDrawer.clear();
        if (!this.reader.open(this.config.databaseFileName, this.config.useCommonFolder, this.loadError)
                || !this.reader.selectMarkers(this.symbolName, this.config.runId,
                    this.startTime, this.endTime, this.config.entryOnly,
                    this.resolvedRunId, this.alertIds, this.markers, this.loadError)) {
            this.logger.error(__FUNCTION__, this.loadError);
            this.render();
            return;
        }
        if (ArraySize(this.alertIds) == 0) {
            this.loadError = "指定した通貨・Run・期間に一致するM5アラートがありません。";
            this.render();
            return;
        }
        int initialIndex = 0;
        for (int i = 0; i < ArraySize(this.alertIds); i++) {
            if (this.alertIds[i] == previousId) {
                initialIndex = i;
                break;
            }
        }
        this.select(initialIndex);
    }

    /**
     * 一件の分析へ切り替え、前の波動を確実に消してから読み込む。
     */
    void select(const int fromIndex) {
        if (fromIndex < 0 || fromIndex >= ArraySize(this.alertIds)) {
            return;
        }
        this.drawer.clear();
        this.snapshot.clear();
        this.snapshotLoaded = false;
        this.historyPending = false;
        this.historyMessage = "";
        this.loadError = "";
        this.selectedIndex = fromIndex;
        this.view = ALERT_HISTORY_SELECTED;
        if (!this.reader.loadSnapshot(this.alertIds[fromIndex], this.snapshot, this.loadError)) {
            this.logger.error(__FUNCTION__, this.loadError);
            this.render();
            return;
        }
        if (this.snapshot.alert.symbolName != this.symbolName
                || this.snapshot.alert.timeFrame != PERIOD_M5
                || this.snapshot.alert.runId != this.resolvedRunId) {
            this.loadError = "選択したアラートの通貨・時間足・Runが検索条件と一致しません。";
            this.snapshot.clear();
            this.render();
            return;
        }
        this.snapshotLoaded = true;
        if (this.snapshot.correctionStatus == "UNRECORDED"
                || this.snapshot.correctionStatus == "INCOMPLETE") {
            this.view = ALERT_HISTORY_ORIGINAL;
        }
        this.beginHistory();
        this.render();
    }

    /**
     * 発生位置と表示対象Waveの価格履歴の準備を開始する。
     */
    void beginHistory() {
        this.historyStartTime = this.snapshot.alert.currentBarTime;
        this.historyEndTime = this.historyStartTime;
        for (int i = 0; i < ArraySize(this.markers); i++) {
            if (!this.markers[i].available) {
                continue;
            }
            if (this.markers[i].barTime < this.historyStartTime) {
                this.historyStartTime = this.markers[i].barTime;
            }
            if (this.markers[i].barTime > this.historyEndTime) {
                this.historyEndTime = this.markers[i].barTime;
            }
        }
        this.findHistoryStart(this.snapshot.originalPoints);
        if (this.snapshot.correctionStatus == "APPLIED") {
            this.findHistoryStart(this.snapshot.correctedPoints);
        }
        this.historyPending = true;
        this.historyAttempts = 0;
        this.historyMessage = "価格履歴を確認しています。";
        this.prepareHistory();
    }

    /**
     * 描画対象の現在足・上位足から必要履歴の開始時刻を探す。
     */
    void findHistoryStart(const ZigZagElliotAlertPointEntity &fromPoints[]) {
        for (int i = 0; i < ArraySize(fromPoints); i++) {
            int timeFrame = fromPoints[i].timeFrame;
            bool isVisible = timeFrame == PERIOD_M5 || timeFrame == PERIOD_M15
                || timeFrame == PERIOD_H1;
            if (this.config.higherCount == 3 && timeFrame == PERIOD_H4) {
                isVisible = true;
            }
            if (isVisible && fromPoints[i].barTime > 0
                    && fromPoints[i].barTime < this.historyStartTime) {
                this.historyStartTime = fromPoints[i].barTime;
            }
        }
    }

    /**
     * 履歴の非同期取得を進める。別の足へ代用して移動しない。
     */
    void prepareHistory() {
        this.historyAttempts++;
        datetime barTime = this.snapshot.alert.currentBarTime;
        datetime copiedTimes[];
        CopyTime(this.symbolName, PERIOD_M5, this.historyStartTime, this.historyEndTime, copiedTimes);
        int barIndex = iBarShift(this.symbolName, PERIOD_M5, barTime, true);
        datetime firstDate = (datetime)SeriesInfoInteger(this.symbolName, PERIOD_M5, SERIES_FIRSTDATE);
        bool hasWaveHistory = firstDate > 0 && firstDate <= this.historyStartTime;
        bool hasAlertHistoryEnd = iBarShift(this.symbolName, PERIOD_M5, this.historyEndTime, true) >= 0;
        if (barIndex >= 0 && hasWaveHistory && hasAlertHistoryEnd) {
            this.historyPending = false;
            this.historyMessage = "保存時点の最新Waveを表示しています。";
            if (!this.navigateToAlert(barIndex)) {
                this.historyMessage = "発生位置へ移動できません。「発生位置へ」で再試行してください。";
            }
            return;
        }
        if (this.historyAttempts >= 15) {
            this.historyPending = false;
            this.historyMessage = "価格履歴不足：接続先・履歴・最大バー数を確認し「発生位置へ」で再試行してください。";
            if (barIndex >= 0) {
                this.navigateToAlert(barIndex);
            }
            this.logger.info(__FUNCTION__, this.historyMessage);
            return;
        }
        this.historyMessage = "価格履歴を準備中（" + IntegerToString(this.historyAttempts)
            + "/15）。保存波動の日時・価格は変更しません。";
    }

    /**
     * 発生足が画面内に入るように移動する。
     */
    bool navigateToAlert(const int fromBarIndex) {
        int totalBars = Bars(this.symbolName, PERIOD_M5);
        int visibleBars = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_BARS);
        if (totalBars <= 0 || visibleBars <= 0) {
            return false;
        }
        int firstVisible = fromBarIndex + (int)((double)visibleBars * 0.6);
        if (firstVisible >= totalBars) {
            firstVisible = totalBars - 1;
        }
        if (!ChartSetInteger(this.chartId, CHART_AUTOSCROLL, false)
                || !ChartNavigate(this.chartId, CHART_BEGIN, totalBars - 1 - firstVisible)) {
            return false;
        }
        ChartRedraw(this.chartId);
        return true;
    }

    /**
     * 保存分析と操作欄を描画する。
     */
    void render() {
        this.needsRedraw = false;
        if (this.drawer == NULL) {
            return;
        }
        if (this.snapshotLoaded) {
            int panelTop = 8;
            int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
            if (chartWidth < 1100) {
                panelTop = 204;
            }
            this.drawer.draw(this.snapshot, this.view, this.config.higherCount,
                this.config.showPrices, this.config.showTable, panelTop, false);
        } else {
            this.drawer.clear();
        }
        this.drawControls();
        if (this.markerDrawer != NULL) {
            this.markerDrawer.draw(this.markers);
        }
        ChartRedraw(this.chartId);
    }

    /**
     * 前後移動・表示モード・選択状態を画面右上へ配置する。
     */
    void drawControls() {
        color foreground = (color)ChartGetInteger(this.chartId, CHART_COLOR_FOREGROUND);
        color background = (color)ChartGetInteger(this.chartId, CHART_COLOR_BACKGROUND);
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
        int panelWidth = (int)MathMin(372, MathMax(24, chartWidth - 20));
        int panelX = (int)MathMax(10, chartWidth - panelWidth - 10);
        int contentX = panelX + 12;
        int contentWidth = panelWidth - 24;
        int selectedWidth = (int)(contentWidth * 126.0 / 348.0);
        int originalWidth = (int)(contentWidth * 100.0 / 348.0);
        int comparisonX = contentX + selectedWidth + originalWidth + 12;
        string panelName = this.prefix + "Ui-Background";
        if (ObjectFind(this.chartId, panelName) < 0) {
            ObjectCreate(this.chartId, panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        }
        ObjectSetInteger(this.chartId, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_XDISTANCE, panelX);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_YDISTANCE, 8);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_XSIZE, panelWidth);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_YSIZE, 186);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_BGCOLOR, background);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_COLOR, background);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, panelName, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, panelName, OBJPROP_TOOLTIP, "\n");
        int total = ArraySize(this.alertIds);
        this.button("Previous", "← 前", contentX, 14, 72, this.selectedIndex > 0, false);
        this.button("Next", "次 →", contentX + 78, 14, 72,
            this.selectedIndex >= 0 && this.selectedIndex + 1 < total, false);
        this.label("Count", IntegerToString(this.selectedIndex + 1) + " / "
            + IntegerToString(total) + "件", contentX + 162, 19, foreground, contentWidth - 162);
        this.button("Refresh", "再読込", contentX, 46, 75, true, false);
        this.button("Locate", "発生位置へ", contentX + 81, 46, 105, this.snapshotLoaded, false);
        bool canCompare = this.snapshotLoaded && this.snapshot.correctionStatus == "APPLIED";
        bool canSelect = canCompare
            || (this.snapshotLoaded && this.snapshot.correctionStatus == "NONE");
        this.button("Selected", "採用分析", contentX, 78, selectedWidth, canSelect,
            this.view == ALERT_HISTORY_SELECTED);
        string originalLabel = "補正前";
        if (!canCompare) {
            originalLabel = "元分析";
        }
        this.button("Original", originalLabel, contentX + selectedWidth + 6, 78, originalWidth,
            this.snapshotLoaded && this.snapshot.originalAvailable,
            this.view == ALERT_HISTORY_ORIGINAL);
        this.button("Comparison", "前後比較", comparisonX, 78,
            (int)MathMax(1, contentX + contentWidth - comparisonX), canCompare,
            this.view == ALERT_HISTORY_COMPARISON);
        string runText = this.symbolName + " M5 | Run " + IntegerToString(this.resolvedRunId);
        if (this.snapshotLoaded) {
            runText += " | " + this.snapshot.run.sourceMode;
        }
        this.label("Run", runText, contentX, 110, foreground, contentWidth);
        string selectedText = "指定期間の最初のアラートから日時順に表示";
        if (this.selectedIndex >= 0) {
            selectedText = "Alert " + IntegerToString(this.alertIds[this.selectedIndex]);
        }
        if (this.snapshotLoaded) {
            selectedText += " | Server " + TimeToString(this.snapshot.alert.currentBarTime, TIME_DATE | TIME_SECONDS);
        }
        this.label("Selection", selectedText, contentX, 130, foreground, contentWidth);
        string correctionText = "";
        if (this.snapshotLoaded) {
            correctionText = this.snapshot.alert.side + " | ENTRY: "
                + this.snapshot.alert.entryResult + " | " + this.correctionLabel();
        }
        this.label("Correction", correctionText, contentX, 150, foreground, contentWidth);
        string status = this.historyMessage;
        color statusColor = foreground;
        if (this.loadError != "") {
            status = this.loadError;
            statusColor = clrOrangeRed;
        } else if (this.snapshotLoaded) {
            if (!this.snapshot.originalAvailable) {
                status = this.snapshot.originalReason;
                statusColor = clrOrangeRed;
            } else if (this.snapshot.correctionStatus == "INCOMPLETE") {
                status = this.snapshot.correctionReason + " | " + status;
                statusColor = clrOrangeRed;
            }
            string server = this.snapshot.run.sourceServer;
            if (server != "" && server != AccountInfoString(ACCOUNT_SERVER)) {
                status = "保存元サーバー: " + server + "（現在の接続先と異なります） | " + status;
                statusColor = clrOrange;
            }
        }
        int unavailableCount = 0;
        for (int i = 0; i < ArraySize(this.markers); i++) {
            if (!this.markers[i].available) {
                unavailableCount++;
            }
        }
        if (unavailableCount > 0) {
            status = "ラベル保存値不足 " + IntegerToString(unavailableCount) + "件 | " + status;
            statusColor = clrOrange;
        }
        this.label("Status", status, contentX, 170, statusColor, contentWidth);
    }

    /**
     * 補正情報の保存状態を表示用に取得する。
     */
    string correctionLabel() {
        if (this.snapshot.correctionStatus == "APPLIED") {
            string timeFrame = "H1";
            if (this.snapshot.correction.correctionTimeFrame == PERIOD_H4) {
                timeFrame = "H4";
            }
            return timeFrame + "補正 " + this.snapshot.correction.originalDirection
                + "→" + this.snapshot.correction.correctedDirection;
        }
        if (this.snapshot.correctionStatus == "NONE") {
            return "補正なし・元分析を採用";
        }
        if (this.snapshot.correctionStatus == "INCOMPLETE") {
            return "補正データ不完全・元分析は比較用";
        }
        return "補正情報未記録";
    }

    /**
     * 有効状態を色で区別した操作ボタンを描画する。
     */
    void button(const string fromName, const string fromText,
            const int fromX, const int fromY, const int fromWidth,
            const bool fromEnabled, const bool fromSelected) {
        string name = this.prefix + "Ui-" + fromName;
        if (ObjectFind(this.chartId, name) < 0) {
            ObjectCreate(this.chartId, name, OBJ_BUTTON, 0, 0, 0);
        }
        color foreground = clrWhite;
        color background = C'55,55,55';
        if (!fromEnabled) {
            foreground = clrGray;
            background = C'35,35,35';
        } else if (fromSelected) {
            background = C'30,85,140';
        }
        ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX);
        ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY);
        ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, 25);
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, foreground);
        ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, background);
        ObjectSetInteger(this.chartId, name, OBJPROP_BORDER_COLOR, clrDimGray);
        ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(this.chartId, name, OBJPROP_STATE, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 20);
        ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic");
        ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText);
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, fromText);
    }

    /**
     * 幅に収まる一行ラベルを配置し、全文をツールチップへ保持する。
     */
    void label(const string fromName, const string fromText, const int fromX,
            const int fromY, const color fromColor, const int fromWidth) {
        string name = this.prefix + "Ui-" + fromName;
        if (ObjectFind(this.chartId, name) < 0) {
            ObjectCreate(this.chartId, name, OBJ_LABEL, 0, 0, 0);
        }
        string displayText = fromText;
        if (fromWidth < 20) {
            displayText = "";
        } else {
            TextSetFont("MS Gothic", -90);
            uint textWidth = 0;
            uint textHeight = 0;
            TextGetSize(displayText, textWidth, textHeight);
            while ((int)textWidth > fromWidth && StringLen(displayText) > 1) {
                displayText = StringSubstr(displayText, 0, StringLen(displayText) - 1);
                TextGetSize(displayText + "…", textWidth, textHeight);
            }
            if (displayText != fromText) {
                displayText += "…";
            }
        }
        ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX);
        ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY);
        ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, fromColor);
        ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true);
        ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic");
        ObjectSetString(this.chartId, name, OBJPROP_TEXT, displayText);
        ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, fromText);
    }
};

#endif
