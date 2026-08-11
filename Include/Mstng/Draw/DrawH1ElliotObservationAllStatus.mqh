//+------------------------------------------------------------------+
//|                     DrawH1ElliotObservationAllStatus.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_H1_ELLIOT_OBSERVATION_ALL_STATUS_MQH
#define MSTNG_DRAW_H1_ELLIOT_OBSERVATION_ALL_STATUS_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Indicator\ZigZagElliot\H1ElliotObservationAllStatus.mqh>

/**
 * 全28通貨H1観測処理の実行状態を固定パネルへ描画するクラス。
 *
 * チャートオブジェクトは初回だけ生成し、状態が変化した場合だけ文字列と
 * 色を更新する。詳細表示時は28通貨を4列7行で表示する。
 */
class DrawH1ElliotObservationAllStatus {
public:
    /**
     * 描画先と初期配置を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     * @param fromObjectSuffix オブジェクト名を一意にする接尾辞。
     * @param fromCorner パネル配置基準の角。
     * @param fromXDistance 基準角からのX距離。
     * @param fromYDistance 基準角からのY距離。
     * @param fromDetailVisible 28通貨詳細を表示する場合true。
     */
    DrawH1ElliotObservationAllStatus(
        long fromChartId = 0,
        string fromObjectSuffix = "Default",
        ENUM_BASE_CORNER fromCorner = CORNER_LEFT_UPPER,
        int fromXDistance = 12,
        int fromYDistance = 12,
        bool fromDetailVisible = true
    ) {
        this.chartId = fromChartId;

        if (fromObjectSuffix == "") {
            fromObjectSuffix = "Default";
        }

        if (StringLen(fromObjectSuffix) > 18) {
            fromObjectSuffix = StringSubstr(fromObjectSuffix, 0, 18);
        }

        this.objectPrefix = Constant::PREFIX_FIXED
            + "H1ObsAll_"
            + fromObjectSuffix
            + "_";
        this.created = false;
        this.visible = true;
        this.detailVisible = fromDetailVisible;
        this.createdDetailVisible = false;
        this.corner = fromCorner;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;

        if (this.xDistance < 0) {
            this.xDistance = 0;
        }

        if (this.yDistance < 0) {
            this.yDistance = 0;
        }

        this.panelWidth = 740;
        this.summaryPanelHeight = 139;
        this.detailPanelHeight = 275;
        this.headerHeight = 26;
        this.summaryFirstYDistance = 35;
        this.summaryRowHeight = 18;
        this.separatorYDistance = 128;
        this.detailFirstYDistance = 139;
        this.detailRowHeight = 18;
        this.detailColumnWidth = 180;
        this.fontName = "MS Gothic";
        this.titleFontSize = 11;
        this.bodyFontSize = 9;
        this.panelBackgroundColor = C'18,18,18';
        this.normalHeaderColor = C'45,88,110';
        this.borderColor = C'80,95,105';
        this.titleColor = clrWhite;
        this.normalColor = clrWhiteSmoke;
        this.mutedColor = C'145,155,165';
        this.okColor = clrLimeGreen;
        this.runningColor = clrAqua;
        this.waitColor = C'150,190,215';
        this.retryColor = clrGold;
        this.databaseColor = clrOrange;
        this.errorColor = clrTomato;
        this.gapColor = C'255,90,120';
        this.resetCache();
    }

    /**
     * 保持しているチャートオブジェクトを破棄する。
     */
    ~DrawH1ElliotObservationAllStatus() {
        this.destroyObjects();
    }

    /**
     * 実行状態をパネルへ描画する。
     *
     * @param fromStatus 描画する実行状態。
     * @return 描画に成功した場合true。
     */
    bool draw(H1ElliotObservationAllStatus &fromStatus) {
        if (MQLInfoInteger(MQL_TESTER)
                && !MQLInfoInteger(MQL_VISUAL_MODE)) {
            if (this.created) {
                this.clear();
            }

            return true;
        }

        if (!this.visible) {
            if (this.created) {
                this.clear();
            }

            return true;
        }

        if (!this.created
                || this.createdDetailVisible != this.detailVisible) {
            if (!this.create()) {
                return false;
            }
        }

        bool changed = false;
        color headerColor = this.getOverallColor(fromStatus);
        string headerText = this.buildHeaderText(fromStatus);

        if (this.lastHeaderText != headerText) {
            ObjectSetString(
                this.chartId,
                this.objectPrefix + "Title",
                OBJPROP_TEXT,
                headerText
            );
            this.lastHeaderText = headerText;
            changed = true;
        }

        if (this.lastHeaderColor != headerColor) {
            ObjectSetInteger(
                this.chartId,
                this.objectPrefix + "TitleBackground",
                OBJPROP_BGCOLOR,
                headerColor
            );
            ObjectSetInteger(
                this.chartId,
                this.objectPrefix + "TitleBackground",
                OBJPROP_COLOR,
                headerColor
            );
            this.lastHeaderColor = headerColor;
            changed = true;
        }

        for (int i = 0; i < 5; i++) {
            string summaryText = this.buildSummaryText(fromStatus, i);
            color summaryColor = this.getSummaryColor(fromStatus, i);

            this.updateLabel(
                this.getSummaryObjectName(i),
                summaryText,
                summaryColor,
                this.lastSummaryTexts[i],
                this.lastSummaryColors[i],
                changed
            );
        }

        if (this.detailVisible) {
            for (int i = 0; i < 28; i++) {
                string detailText = this.buildDetailText(fromStatus, i);
                color detailColor = this.getDetailColor(fromStatus, i);

                this.updateLabel(
                    this.getDetailObjectName(i),
                    detailText,
                    detailColor,
                    this.lastDetailTexts[i],
                    this.lastDetailColors[i],
                    changed
                );
            }
        }

        if (changed) {
            ChartRedraw(this.chartId);
        }

        return true;
    }

    /**
     * パネルの表示可否を設定する。
     *
     * @param fromVisible 表示する場合true。
     */
    void setVisible(bool fromVisible) {
        if (this.visible == fromVisible) {
            return;
        }

        this.visible = fromVisible;

        if (!this.visible) {
            this.clear();
        }
    }

    /**
     * 28通貨詳細の表示可否を設定する。
     *
     * @param fromDetailVisible 詳細を表示する場合true。
     */
    void setDetailVisible(bool fromDetailVisible) {
        if (this.detailVisible == fromDetailVisible) {
            return;
        }

        this.detailVisible = fromDetailVisible;
        this.destroyObjects();
    }

    /**
     * パネルの配置を設定する。
     *
     * @param fromCorner パネル配置基準の角。
     * @param fromXDistance 基準角からのX距離。
     * @param fromYDistance 基準角からのY距離。
     */
    void setPosition(
        ENUM_BASE_CORNER fromCorner,
        int fromXDistance,
        int fromYDistance
    ) {
        if (fromXDistance < 0) {
            fromXDistance = 0;
        }

        if (fromYDistance < 0) {
            fromYDistance = 0;
        }

        if (this.corner == fromCorner
                && this.xDistance == fromXDistance
                && this.yDistance == fromYDistance) {
            return;
        }

        this.corner = fromCorner;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.destroyObjects();
    }

    /**
     * パネル専用チャートオブジェクトを削除する。
     */
    void clear() {
        bool wasCreated = this.created;

        this.destroyObjects();

        if (wasCreated) {
            ChartRedraw(this.chartId);
        }
    }

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** パネル専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** パネル生成済みの場合true。 */
    bool created;

    /** パネルを表示する場合true。 */
    bool visible;

    /** 28通貨詳細を表示する場合true。 */
    bool detailVisible;

    /** 生成済みパネルが詳細表示の場合true。 */
    bool createdDetailVisible;

    /** パネル配置基準の角。 */
    ENUM_BASE_CORNER corner;

    /** 基準角からのX距離。 */
    int xDistance;

    /** 基準角からのY距離。 */
    int yDistance;

    /** パネル横幅。 */
    int panelWidth;

    /** 集約表示時のパネル高さ。 */
    int summaryPanelHeight;

    /** 詳細表示時のパネル高さ。 */
    int detailPanelHeight;

    /** タイトル背景の高さ。 */
    int headerHeight;

    /** 集約表示先頭行のY位置。 */
    int summaryFirstYDistance;

    /** 集約表示の行高さ。 */
    int summaryRowHeight;

    /** 区切り線のY位置。 */
    int separatorYDistance;

    /** 詳細表示先頭行のY位置。 */
    int detailFirstYDistance;

    /** 詳細表示の行高さ。 */
    int detailRowHeight;

    /** 詳細表示の列幅。 */
    int detailColumnWidth;

    /** 表示フォント名。 */
    string fontName;

    /** タイトルフォントサイズ。 */
    int titleFontSize;

    /** 本文フォントサイズ。 */
    int bodyFontSize;

    /** パネル背景色。 */
    color panelBackgroundColor;

    /** 通常時のタイトル背景色。 */
    color normalHeaderColor;

    /** パネル枠線色。 */
    color borderColor;

    /** タイトル文字色。 */
    color titleColor;

    /** 通常文字色。 */
    color normalColor;

    /** 非活性文字色。 */
    color mutedColor;

    /** 正常文字色。 */
    color okColor;

    /** 処理中文字色。 */
    color runningColor;

    /** 待機中文字色。 */
    color waitColor;

    /** 再試行文字色。 */
    color retryColor;

    /** DB待ち文字色。 */
    color databaseColor;

    /** エラー文字色。 */
    color errorColor;

    /** 欠損文字色。 */
    color gapColor;

    /** 前回タイトル文字列。 */
    string lastHeaderText;

    /** 前回タイトル背景色。 */
    color lastHeaderColor;

    /** 前回集約表示文字列。 */
    string lastSummaryTexts[5];

    /** 前回集約表示文字色。 */
    color lastSummaryColors[5];

    /** 前回通貨別表示文字列。 */
    string lastDetailTexts[28];

    /** 前回通貨別表示文字色。 */
    color lastDetailColors[28];

    /**
     * パネルを生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool create() {
        this.destroyObjects();

        int panelHeight = this.summaryPanelHeight;

        if (this.detailVisible) {
            panelHeight = this.detailPanelHeight;
        }

        if (!this.createRectangle(
            this.objectPrefix + "Panel",
            0,
            0,
            this.panelWidth,
            panelHeight,
            this.panelBackgroundColor,
            this.borderColor,
            0
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createRectangle(
            this.objectPrefix + "TitleBackground",
            1,
            1,
            this.panelWidth - 2,
            this.headerHeight,
            this.normalHeaderColor,
            this.normalHeaderColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            this.objectPrefix + "Title",
            14,
            5,
            this.titleFontSize,
            this.titleColor,
            "H1 OBSERVATION ALL"
        )) {
            this.destroyObjects();

            return false;
        }

        for (int i = 0; i < 5; i++) {
            if (!this.createLabel(
                this.getSummaryObjectName(i),
                14,
                this.summaryFirstYDistance + (i * this.summaryRowHeight),
                this.bodyFontSize,
                this.normalColor,
                ""
            )) {
                this.destroyObjects();

                return false;
            }
        }

        if (!this.createRectangle(
            this.objectPrefix + "Separator",
            12,
            this.separatorYDistance,
            this.panelWidth - 24,
            1,
            this.borderColor,
            this.borderColor,
            1
        )) {
            this.destroyObjects();

            return false;
        }

        if (this.detailVisible) {
            for (int i = 0; i < 28; i++) {
                int rowIndex = i / 4;
                int columnIndex = i % 4;

                if (!this.createLabel(
                    this.getDetailObjectName(i),
                    14 + (columnIndex * this.detailColumnWidth),
                    this.detailFirstYDistance + (rowIndex * this.detailRowHeight),
                    this.bodyFontSize,
                    this.mutedColor,
                    "-"
                )) {
                    this.destroyObjects();

                    return false;
                }
            }
        }

        this.created = true;
        this.createdDetailVisible = this.detailVisible;
        this.resetCache();

        return true;
    }

    /**
     * 矩形ラベルを生成する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromLeftOffset パネル左端からのX位置。
     * @param fromTopOffset パネル上端からのY位置。
     * @param fromWidth 横幅。
     * @param fromHeight 高さ。
     * @param fromBackgroundColor 背景色。
     * @param fromBorderColor 枠線色。
     * @param fromZOrder Zオーダー。
     * @return 生成に成功した場合true。
     */
    bool createRectangle(
        string fromObjectName,
        int fromLeftOffset,
        int fromTopOffset,
        int fromWidth,
        int fromHeight,
        color fromBackgroundColor,
        color fromBorderColor,
        int fromZOrder
    ) {
        if (!ObjectCreate(
            this.chartId,
            fromObjectName,
            OBJ_RECTANGLE_LABEL,
            0,
            0,
            0
        )) {
            return false;
        }

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_XDISTANCE,
            this.getRectangleXDistance(fromLeftOffset, fromWidth)
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_YDISTANCE,
            this.getRectangleYDistance(fromTopOffset, fromHeight)
        );
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BGCOLOR, fromBackgroundColor);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_COLOR, fromBorderColor);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ZORDER, fromZOrder);

        return true;
    }

    /**
     * 固定位置ラベルを生成する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromLeftOffset パネル左端からのX位置。
     * @param fromTopOffset パネル上端からのY位置。
     * @param fromFontSize フォントサイズ。
     * @param fromColor 文字色。
     * @param fromText 表示文字列。
     * @return 生成に成功した場合true。
     */
    bool createLabel(
        string fromObjectName,
        int fromLeftOffset,
        int fromTopOffset,
        int fromFontSize,
        color fromColor,
        string fromText
    ) {
        if (!ObjectCreate(this.chartId, fromObjectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_XDISTANCE,
            this.getLabelXDistance(fromLeftOffset)
        );
        ObjectSetInteger(
            this.chartId,
            fromObjectName,
            OBJPROP_YDISTANCE,
            this.getLabelYDistance(fromTopOffset)
        );
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_FONTSIZE, fromFontSize);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_COLOR, fromColor);
        ObjectSetString(this.chartId, fromObjectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, fromObjectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * ラベルの文字列と色を差分更新する。
     *
     * @param fromObjectName オブジェクト名。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     * @param fromLastText 前回表示文字列。
     * @param fromLastColor 前回表示文字色。
     * @param fromChanged 更新した場合trueを設定する参照。
     */
    void updateLabel(
        string fromObjectName,
        string fromText,
        color fromColor,
        string &fromLastText,
        color &fromLastColor,
        bool &fromChanged
    ) {
        if (fromLastText != fromText) {
            ObjectSetString(
                this.chartId,
                fromObjectName,
                OBJPROP_TEXT,
                fromText
            );
            fromLastText = fromText;
            fromChanged = true;
        }

        if (fromLastColor != fromColor) {
            ObjectSetInteger(
                this.chartId,
                fromObjectName,
                OBJPROP_COLOR,
                fromColor
            );
            fromLastColor = fromColor;
            fromChanged = true;
        }
    }

    /**
     * タイトル文字列を生成する。
     *
     * @param fromStatus 実行状態。
     * @return タイトル文字列。
     */
    string buildHeaderText(H1ElliotObservationAllStatus &fromStatus) {
        string runText = "-";

        if (fromStatus.runId > 0) {
            runText = StringFormat("%I64d", fromStatus.runId);
        }

        return "H1 OBSERVATION ALL  ["
            + this.getOverallText(fromStatus)
            + "]  Run "
            + runText;
    }

    /**
     * 集約表示の1行を生成する。
     *
     * @param fromStatus 実行状態。
     * @param fromRowIndex 集約表示行番号。
     * @return 表示文字列。
     */
    string buildSummaryText(
        H1ElliotObservationAllStatus &fromStatus,
        int fromRowIndex
    ) {
        if (fromRowIndex == 0) {
            string writerText = "PASSIVE";
            string databaseText = "WAIT";

            if (fromStatus.isWriterActive) {
                writerText = "ACTIVE";
            }

            if (fromStatus.isDatabaseConnected) {
                databaseText = "OK";
            }

            return StringFormat(
                "%s | Writer %s | DB %s | Ready %d/%d",
                fromStatus.sourceMode,
                writerText,
                databaseText,
                fromStatus.readyCount,
                fromStatus.targetCount
            );
        }

        if (fromRowIndex == 1) {
            return StringFormat(
                "H1 JST %s | Detect %d | Analyze %d | Save %d/%d",
                this.formatDateTime(fromStatus.currentH1JapanTime, false),
                fromStatus.detectedCount,
                fromStatus.analyzedCount,
                fromStatus.savedCount,
                fromStatus.detectedCount
            );
        }

        if (fromRowIndex == 2) {
            return StringFormat(
                "Queue %d/%d | Gap %d | Last %s | %d ms",
                fromStatus.queueSize,
                fromStatus.queueCapacity,
                fromStatus.gapCount,
                this.formatDateTime(fromStatus.lastSavedJapanTime, true),
                fromStatus.elapsedMilliseconds
            );
        }

        if (fromRowIndex == 3) {
            return StringFormat(
                "BASE %d | WAIT %d | RUN %d | RETRY %d | DB %d | OK %d | ERR %d | GAP %d",
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusBase),
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusWait),
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusRun),
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusRetry),
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusDatabase),
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusOk),
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusError),
                fromStatus.getStatusCount(h1ElliotObservationAllSymbolStatusGap)
            );
        }

        if (fromStatus.message == "") {
            return "Info -";
        }

        return "Info " + fromStatus.message;
    }

    /**
     * 通貨別表示文字列を生成する。
     *
     * @param fromStatus 実行状態。
     * @param fromIndex 通貨インデックス。
     * @return 表示文字列。
     */
    string buildDetailText(
        H1ElliotObservationAllStatus &fromStatus,
        int fromIndex
    ) {
        if (fromIndex < 0
                || fromIndex >= 28
                || fromStatus.symbolNames[fromIndex] == "") {
            return "-";
        }

        string statusText = this.padRight(
            fromStatus.getSymbolStatusText(fromIndex),
            5
        );
        string detailText = fromStatus.symbolNames[fromIndex]
            + " "
            + statusText;

        if (fromStatus.symbolPendingCounts[fromIndex] > 0) {
            detailText += " Q"
                + IntegerToString(fromStatus.symbolPendingCounts[fromIndex]);
        }

        if (fromStatus.symbolRetryCounts[fromIndex] > 0) {
            detailText += " R"
                + IntegerToString(fromStatus.symbolRetryCounts[fromIndex]);
        }

        return detailText;
    }

    /**
     * 全体状態文字列を取得する。
     *
     * @param fromStatus 実行状態。
     * @return 全体状態文字列。
     */
    string getOverallText(H1ElliotObservationAllStatus &fromStatus) {
        if (!fromStatus.isRunning) {
            return "STOPPED";
        }

        if (fromStatus.getStatusCount(
            h1ElliotObservationAllSymbolStatusError
        ) > 0) {
            return "ERROR";
        }

        if (fromStatus.gapCount > 0
                || fromStatus.getStatusCount(
            h1ElliotObservationAllSymbolStatusGap
        ) > 0) {
            return "GAP";
        }

        if (!fromStatus.isWriterActive) {
            return "PASSIVE";
        }

        if (!fromStatus.isDatabaseConnected) {
            return "DB WAIT";
        }

        if (fromStatus.getStatusCount(
            h1ElliotObservationAllSymbolStatusRun
        ) > 0) {
            return "ANALYZING";
        }

        if (fromStatus.queueSize > 0
                || fromStatus.getStatusCount(
            h1ElliotObservationAllSymbolStatusRetry
        ) > 0
                || fromStatus.getStatusCount(
            h1ElliotObservationAllSymbolStatusDatabase
        ) > 0) {
            return "WAITING";
        }

        return "ACTIVE";
    }

    /**
     * 全体状態色を取得する。
     *
     * @param fromStatus 実行状態。
     * @return 全体状態色。
     */
    color getOverallColor(H1ElliotObservationAllStatus &fromStatus) {
        string statusText = this.getOverallText(fromStatus);

        if (statusText == "ACTIVE") {
            return C'30,120,78';
        }

        if (statusText == "ANALYZING") {
            return C'35,100,130';
        }

        if (statusText == "WAITING" || statusText == "DB WAIT") {
            return C'140,105,25';
        }

        if (statusText == "ERROR" || statusText == "GAP") {
            return C'150,58,58';
        }

        return this.normalHeaderColor;
    }

    /**
     * 集約表示行の文字色を取得する。
     *
     * @param fromStatus 実行状態。
     * @param fromRowIndex 集約表示行番号。
     * @return 文字色。
     */
    color getSummaryColor(
        H1ElliotObservationAllStatus &fromStatus,
        int fromRowIndex
    ) {
        if (fromRowIndex == 0 && !fromStatus.isDatabaseConnected) {
            return this.databaseColor;
        }

        if (fromRowIndex == 2 && fromStatus.gapCount > 0) {
            return this.gapColor;
        }

        if (fromRowIndex == 4 && fromStatus.message != "") {
            return this.waitColor;
        }

        return this.normalColor;
    }

    /**
     * 通貨別状態の文字色を取得する。
     *
     * @param fromStatus 実行状態。
     * @param fromIndex 通貨インデックス。
     * @return 文字色。
     */
    color getDetailColor(
        H1ElliotObservationAllStatus &fromStatus,
        int fromIndex
    ) {
        if (fromIndex < 0
                || fromIndex >= 28
                || fromStatus.symbolNames[fromIndex] == "") {
            return this.mutedColor;
        }

        H1ElliotObservationAllSymbolStatus symbolStatus =
            fromStatus.symbolStatuses[fromIndex];

        if (symbolStatus == h1ElliotObservationAllSymbolStatusOk) {
            return this.okColor;
        }

        if (symbolStatus == h1ElliotObservationAllSymbolStatusRun) {
            return this.runningColor;
        }

        if (symbolStatus == h1ElliotObservationAllSymbolStatusWait) {
            return this.waitColor;
        }

        if (symbolStatus == h1ElliotObservationAllSymbolStatusRetry) {
            return this.retryColor;
        }

        if (symbolStatus == h1ElliotObservationAllSymbolStatusDatabase) {
            return this.databaseColor;
        }

        if (symbolStatus == h1ElliotObservationAllSymbolStatusError) {
            return this.errorColor;
        }

        if (symbolStatus == h1ElliotObservationAllSymbolStatusGap) {
            return this.gapColor;
        }

        return this.mutedColor;
    }

    /**
     * 日時をパネル表示用文字列へ変換する。
     *
     * @param fromDatetime 変換対象日時。
     * @param fromIncludeSeconds 秒まで表示する場合true。
     * @return 表示用日時。未設定の場合ハイフン。
     */
    string formatDateTime(datetime fromDatetime, bool fromIncludeSeconds) {
        if (fromDatetime <= 0) {
            return "-";
        }

        MqlDateTime dateTime;
        TimeToStruct(fromDatetime, dateTime);

        if (fromIncludeSeconds) {
            return StringFormat(
                "%04d.%02d.%02d %02d:%02d:%02d",
                dateTime.year,
                dateTime.mon,
                dateTime.day,
                dateTime.hour,
                dateTime.min,
                dateTime.sec
            );
        }

        return StringFormat(
            "%04d.%02d.%02d %02d:%02d",
            dateTime.year,
            dateTime.mon,
            dateTime.day,
            dateTime.hour,
            dateTime.min
        );
    }

    /**
     * 文字列を指定長まで右側空白で埋める。
     *
     * @param fromText 対象文字列。
     * @param fromLength 最小文字数。
     * @return 整形後文字列。
     */
    string padRight(string fromText, int fromLength) {
        string result = fromText;

        while (StringLen(result) < fromLength) {
            result += " ";
        }

        return result;
    }

    /**
     * 矩形のX距離を取得する。
     *
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromWidth 矩形横幅。
     * @return 基準角からのX距離。
     */
    int getRectangleXDistance(int fromLeftOffset, int fromWidth) {
        if (this.corner == CORNER_RIGHT_UPPER
                || this.corner == CORNER_RIGHT_LOWER) {
            return this.xDistance
                + this.panelWidth
                - fromLeftOffset
                - fromWidth;
        }

        return this.xDistance + fromLeftOffset;
    }

    /**
     * 矩形のY距離を取得する。
     *
     * @param fromTopOffset パネル上端からの位置。
     * @param fromHeight 矩形高さ。
     * @return 基準角からのY距離。
     */
    int getRectangleYDistance(int fromTopOffset, int fromHeight) {
        int panelHeight = this.summaryPanelHeight;

        if (this.detailVisible) {
            panelHeight = this.detailPanelHeight;
        }

        if (this.corner == CORNER_LEFT_LOWER
                || this.corner == CORNER_RIGHT_LOWER) {
            return this.yDistance
                + panelHeight
                - fromTopOffset
                - fromHeight;
        }

        return this.yDistance + fromTopOffset;
    }

    /**
     * ラベルのX距離を取得する。
     *
     * @param fromLeftOffset パネル左端からの位置。
     * @return 基準角からのX距離。
     */
    int getLabelXDistance(int fromLeftOffset) {
        if (this.corner == CORNER_RIGHT_UPPER
                || this.corner == CORNER_RIGHT_LOWER) {
            return this.xDistance + this.panelWidth - fromLeftOffset;
        }

        return this.xDistance + fromLeftOffset;
    }

    /**
     * ラベルのY距離を取得する。
     *
     * @param fromTopOffset パネル上端からの位置。
     * @return 基準角からのY距離。
     */
    int getLabelYDistance(int fromTopOffset) {
        int panelHeight = this.summaryPanelHeight;

        if (this.detailVisible) {
            panelHeight = this.detailPanelHeight;
        }

        if (this.corner == CORNER_LEFT_LOWER
                || this.corner == CORNER_RIGHT_LOWER) {
            return this.yDistance + panelHeight - fromTopOffset;
        }

        return this.yDistance + fromTopOffset;
    }

    /**
     * 集約表示ラベルのオブジェクト名を取得する。
     *
     * @param fromIndex 集約表示行番号。
     * @return オブジェクト名。
     */
    string getSummaryObjectName(int fromIndex) {
        return this.objectPrefix + "Summary_" + IntegerToString(fromIndex);
    }

    /**
     * 通貨別ラベルのオブジェクト名を取得する。
     *
     * @param fromIndex 通貨インデックス。
     * @return オブジェクト名。
     */
    string getDetailObjectName(int fromIndex) {
        return this.objectPrefix + "Symbol_" + IntegerToString(fromIndex);
    }

    /**
     * パネル専用チャートオブジェクトを削除する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.createdDetailVisible = false;
        this.resetCache();
    }

    /**
     * 前回描画値を初期化する。
     */
    void resetCache() {
        this.lastHeaderText = "";
        this.lastHeaderColor = clrNONE;

        for (int i = 0; i < 5; i++) {
            this.lastSummaryTexts[i] = "";
            this.lastSummaryColors[i] = clrNONE;
        }

        for (int i = 0; i < 28; i++) {
            this.lastDetailTexts[i] = "";
            this.lastDetailColors[i] = clrNONE;
        }
    }
};

#endif // MSTNG_DRAW_H1_ELLIOT_OBSERVATION_ALL_STATUS_MQH
