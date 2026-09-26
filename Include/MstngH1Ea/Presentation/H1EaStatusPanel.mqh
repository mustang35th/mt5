#ifndef MSTNGH1EA_PRESENTATION_STATUSPANEL_MQH
#define MSTNGH1EA_PRESENTATION_STATUSPANEL_MQH

#include <Mstng\Log\Logger.mqh>
#include <MstngH1Ea\Runtime\H1EaClock.mqh>
#include <MstngH1Ea\Runtime\H1EaMonitorState.mqh>

/**
 * 全通貨EAの読取専用パネル。状態コピーだけを描画し、売買・DB処理を呼ばない。
 * 幅があれば14行を2列、狭いチャートではページ分割して全28通貨を確認できる。
 */
class H1EaStatusPanel {
public:
    /**
     * チャートを操作しない未初期化状態を作る。
     */
    H1EaStatusPanel() {
        this.chartId = 0;
        this.objectPrefix = "";
        this.enabled = false;
        this.created = false;
        this.drawFailed = false;
        this.nextRefreshTick = 0;
        this.forceRefresh = true;
        this.page = 0;
        this.pageCount = 1;
        this.columns = 0;
        this.rows = 0;
        this.compact = false;
    }

    /**
     * 自分が作成したオブジェクトだけを破棄する。
     */
    ~H1EaStatusPanel() { this.clear(); }

    /**
     * 表示設定と固有の名前領域を準備する。非表示Testerではオブジェクトを作らない。
     */
    void initialize(const long fromChartId, const bool fromEnabled) {
        this.chartId = fromChartId;
        this.objectPrefix = "MstngH1EaAllStatus_" + IntegerToString(fromChartId) + "_";
        this.enabled = fromEnabled;
        this.logger.setSymbolNameAndTimeFrame(_Symbol, PERIOD_H1);
        this.logger.setLevel(LOG_INFO);
        this.page = 0;
        this.nextRefreshTick = 0;
        this.forceRefresh = true;
        if (this.canDraw()) {
            this.clear();
        }
    }

    /**
     * 表示更新が必要かを確認する。Tickごとの状態集計を避ける。
     */
    bool isRefreshDue() {
        return this.canDraw() && (this.forceRefresh || H1EaClock::milliseconds() >= this.nextRefreshTick);
    }

    /**
     * チャート変更と自分のページボタンだけを扱う。売買操作は行わない。
     */
    void onChartEvent(const int fromId, const string fromObjectName) {
        if (!this.canDraw()) {
            return;
        }
        if (fromId == CHARTEVENT_CHART_CHANGE) {
            this.forceRefresh = true;
        } else if (fromId == CHARTEVENT_OBJECT_CLICK) {
            if (fromObjectName == this.objectPrefix + "Previous") {
                this.page = (this.page + this.pageCount - 1) % this.pageCount;
            } else if (fromObjectName == this.objectPrefix + "Next") {
                this.page = (this.page + 1) % this.pageCount;
            } else {
                return;
            }
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            this.forceRefresh = true;
        }
    }

    /**
     * 通常60秒に1度、差分だけを描画する。操作時の再描画で定期期限を延長しない。
     * 生成失敗は売買処理へ伝播させない。
     */
    bool draw(H1EaMonitorState &fromState) {
        if (!this.canDraw()) {
            return true;
        }
        ulong now = H1EaClock::milliseconds();
        if (now >= this.nextRefreshTick) {
            this.nextRefreshTick = now + 60000;
        }
        this.forceRefresh = false;
        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS);
        int chartHeight = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        int columnCount = 1;
        if (chartWidth >= 1196) {
            columnCount = 2;
        }
        int rowCount = (chartHeight - 220) / 18;
        rowCount = MathMax(1, MathMin(14, rowCount));
        bool smallChart = chartWidth < 596 || chartHeight < 240;
        if (this.columns != columnCount || this.rows != rowCount || this.compact != smallChart) {
            this.clear();
            this.columns = columnCount;
            this.rows = rowCount;
            this.compact = smallChart;
        }
        this.pageCount = MathMax(1, (fromState.symbolCount + columnCount * rowCount - 1) / (columnCount * rowCount));
        if (this.page >= this.pageCount) {
            this.page = this.pageCount - 1;
        }
        if (!this.created && !this.create()) {
            return this.reportFailure();
        }
        bool changed = false;
        bool ok = true;
        string mode = "通常";
        if (fromState.beforeTradeStart) {
            mode = "売買開始前";
        }
        string timing = IntegerToString(fromState.timerSeconds) + "s";
        if (fromState.beforeTradeStart && fromState.fastWarmup && fromState.timerSeconds == 0) {
            timing = "Tick / 1時間";
        }
        string title = "H1 EA ALL  |  " + fromState.sourceMode + "  |  " + mode + "  " + timing;
        if (this.compact) {
            title = "H1 EA ALL";
        }
        string titleTip = "Session: " + fromState.sessionUid + "\nServer: "
            + TimeToString(fromState.serverTime, TIME_DATE | TIME_SECONDS)
            + "\n稼働は巡回の準備状態です。発注条件の成立を意味しません。";
        ok = this.label(0, title, clrWhite, 16, 18, titleTip, changed) && ok;
        string currency = fromState.accountCurrency;
        if (currency == "") {
            currency = "口座通貨未取得";
        }
        string positionText = "取得待ち";
        if (fromState.floatingProfitKnown) {
            positionText = IntegerToString(fromState.positionCount);
        }
        string profitText = this.formatFloatingProfit(fromState.floatingProfit,
            fromState.floatingProfitKnown, fromState.currencyDigits);
        string profitSummary = "EA評価損益 " + profitText + " " + currency + " ｜ 保有 " + positionText;
        if (this.compact) {
            profitSummary = "EA評価損益 " + profitText + " " + currency;
        }
        string profitTip = this.floatingProfitTooltip(fromState.floatingProfit,
            fromState.floatingProfitKnown, fromState.positionCount, currency,
            fromState.currencyDigits, fromState.floatingProfitTime);
        ok = this.label(156, profitSummary,
            this.floatingProfitColor(fromState.floatingProfit, fromState.floatingProfitKnown, fromState.currencyDigits),
            16, 42, profitTip, changed) && ok;
        string historyText = "履歴準備 ";
        if (fromState.symbolCount > 0 && fromState.historyReadyCount == fromState.symbolCount) {
            historyText = "履歴準備完了 ";
        }
        historyText += IntegerToString(fromState.historyReadyCount) + "/" + IntegerToString(fromState.symbolCount);
        string summary = "稼働 " + IntegerToString(fromState.watchingCount)
            + " / 準備 " + IntegerToString(fromState.preparingCount)
            + " / 停止 " + IntegerToString(fromState.stoppedCount)
            + " / 取引管理 " + IntegerToString(fromState.activeTradeCount);
        if (this.compact) {
            summary = "保有 " + positionText + " ｜ " + historyText;
        }
        ok = this.label(1, summary, clrWhiteSmoke, 16, 64,
            "取引管理数は発注中・決済中・復旧待ちも含む最終確認値です。", changed) && ok;
        string historyLine = historyText;
        if (this.compact) {
            historyLine = "";
        }
        ok = this.label(155, historyLine, clrWhiteSmoke, 16, 86,
            "価格履歴の同期と必要本数を確認した通貨数です。分析成功や売買許可とは別です。", changed) && ok;
        string metrics = "分析ms " + this.milliseconds(fromState.lastAnalysisMicros) + " / 最大 "
            + this.milliseconds(fromState.maxAnalysisMicros) + "  Timerms " + this.milliseconds(fromState.lastTimerMicros)
            + " / " + this.milliseconds(fromState.maxTimerMicros);
        if (this.compact) {
            metrics = "";
        }
        ok = this.label(2, metrics, clrSilver, 16, 104,
            "分析とTimer処理の実時間。失敗した分析も含みます。\nTimerは描画・定期ログの時間を含みません。", changed) && ok;
        string gaps = "保護間隔ms " + IntegerToString((long)fromState.lastProtectionGapMs) + " / 最大 "
            + IntegerToString((long)fromState.maxProtectionGapMs) + "  Memory " + IntegerToString(fromState.memoryMb) + " MB";
        if (this.compact) {
            gaps = "";
        }
        ok = this.label(3, gaps, clrSilver, 16, 122,
            "全通貨保護の巡回開始間隔。Testerではテスト内時刻です。\n高速準備による意図的な休止は除外します。", changed) && ok;
        int usedLabels = 4;
        if (!this.compact) {
            for (int i = 0; i < this.columns; i++) {
                int left = 16 + i * 584;
                ok = this.label(4 + i * 5, "通貨", clrSilver, left, 144, "", changed) && ok;
                ok = this.label(5 + i * 5, "状態", clrSilver, left + 64, 144, "理由は行のツールチップを参照。", changed) && ok;
                ok = this.label(6 + i * 5, "最終判定H1", clrSilver, left + 142, 144, "サーバー時刻。保存待ちを含む確定済みH1。", changed) && ok;
                ok = this.label(7 + i * 5, "取引(最終確認)", clrSilver, left + 254, 144, "現在値の再照会は行いません。", changed) && ok;
                ok = this.label(8 + i * 5, "評価損益 (" + currency + ")", clrSilver,
                    left + 564, 144, profitTip, changed, true) && ok;
            }
            if (this.columns == 1) {
                for (int i = 9; i < 14; i++) {
                    ok = this.label(i, "", clrSilver, 0, 0, "", changed) && ok;
                }
            }
            int slots = this.rows * this.columns;
            for (int i = 0; i < slots; i++) {
                int symbolIndex = this.page * slots + i;
                int left = 16 + (i / this.rows) * 584;
                int top = 166 + (i % this.rows) * 18;
                int offset = 14 + i * 5;
                if (symbolIndex >= fromState.symbolCount) {
                    for (int j = 0; j < 5; j++) {
                        ok = this.label(offset + j, "", clrSilver, 0, 0, "", changed) && ok;
                    }
                    continue;
                }
                H1EaMonitorSymbolState state = fromState.symbols[symbolIndex];
                string tooltip = this.buildTooltip(state) + "\n"
                    + this.floatingProfitTooltip(state.floatingProfit, state.floatingProfitKnown,
                        state.positionCount, currency, fromState.currencyDigits, fromState.floatingProfitTime);
                color statusColor = clrLightSkyBlue;
                if (state.category == "STOPPED") {
                    statusColor = clrTomato;
                } else if (state.category == "PREPARING") {
                    statusColor = clrGold;
                }
                string barText = "-";
                if (state.finalizedBar > 0) {
                    barText = StringSubstr(TimeToString(state.finalizedBar, TIME_DATE | TIME_MINUTES), 5);
                }
                color tradeColor = clrSilver;
                if (state.activeTrade && state.tradeSide == "BUY") {
                    tradeColor = clrDeepSkyBlue;
                } else if (state.activeTrade && state.tradeSide == "SELL") {
                    tradeColor = clrLightCoral;
                }
                ok = this.label(offset, state.symbolName, clrWhiteSmoke, left, top, tooltip, changed) && ok;
                ok = this.label(offset + 1, this.statusText(state.status), statusColor, left + 64, top, tooltip, changed) && ok;
                ok = this.label(offset + 2, barText, clrSilver, left + 142, top, tooltip, changed) && ok;
                ok = this.label(offset + 3, this.tradeText(state), tradeColor, left + 254, top, tooltip, changed) && ok;
                ok = this.label(offset + 4,
                    this.formatFloatingProfit(state.floatingProfit, state.floatingProfitKnown, fromState.currencyDigits),
                    this.floatingProfitColor(state.floatingProfit, state.floatingProfitKnown, fromState.currencyDigits),
                    left + 564, top, tooltip, changed, true) && ok;
            }
            usedLabels = 14 + slots * 5;
        }
        for (int i = usedLabels; i < 154; i++) {
            ok = this.label(i, "", clrSilver, 0, 0, "", changed) && ok;
        }
        int footer = 174 + this.rows * 18;
        int width = 584 * this.columns;
        int footerX = 90;
        string pageText = IntegerToString(this.page + 1) + " / " + IntegerToString(this.pageCount);
        if (this.compact) {
            footer = 86;
            footerX = 16;
            width = MathMax(100, chartWidth - 24);
            pageText = "目安: 596 x 240 px";
        }
        ok = this.label(154, pageText, clrSilver, footerX, footer, "表示だけのページ切り替えです。全28通貨の巡回は継続します。", changed) && ok;
        ok = ObjectSetInteger(this.chartId, this.objectPrefix + "Background", OBJPROP_XSIZE, width) && ok;
        ok = ObjectSetInteger(this.chartId, this.objectPrefix + "Background", OBJPROP_YSIZE, footer + 12) && ok;
        ok = this.button("Previous", "前", 16, footer, !this.compact) && ok;
        ok = this.button("Next", "次", width - 60, footer, !this.compact) && ok;
        if (!ok) {
            return this.reportFailure();
        }
        this.drawFailed = false;
        if (changed) {
            ChartRedraw(this.chartId);
        }
        return true;
    }

    /**
     * このパネルの名前領域だけを削除する。取引や他の描画は変更しない。
     */
    void clear() {
        if (this.objectPrefix != "" && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))) {
            ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        }
        this.created = false;
    }

private:
    /** 描画先チャート。 */
    long chartId;
    /** このパネル専用のオブジェクト接頭辞。 */
    string objectPrefix;
    /** inputの表示指定。 */
    bool enabled;
    /** オブジェクト生成済み。 */
    bool created;
    /** 同じ描画失敗ログを繰り返さないための状態。 */
    bool drawFailed;
    /** 次の表示更新時刻。 */
    ulong nextRefreshTick;
    /** ページ・サイズ操作による即時再描画。定期更新の期限とは分ける。 */
    bool forceRefresh;
    /** 表示中ページ。 */
    int page;
    /** ページ数。 */
    int pageCount;
    /** 表示ブロック数。 */
    int columns;
    /** 1ブロックの行数。 */
    int rows;
    /** 小さすぎるチャートは要約だけにする。 */
    bool compact;
    /** 描画エラーを記録する既存Logger。 */
    Logger logger;
    /** ラベル文字列の差分キャッシュ。 */
    string lastTexts[157];
    /** ツールチップの差分キャッシュ。 */
    string lastTooltips[157];
    /** 色の差分キャッシュ。 */
    color lastColors[157];
    /** X位置の差分キャッシュ。 */
    int lastX[157];
    /** Y位置の差分キャッシュ。 */
    int lastY[157];
    /** 左揃え・右揃えの差分キャッシュ。 */
    ENUM_ANCHOR_POINT lastAnchors[157];

    /**
     * LIVEまたはビジュアルTesterで、表示指定がある場合だけ描画する。
     */
    bool canDraw() {
        return this.enabled && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
    }

    /**
     * 自分の描画オブジェクトを生成する。
     */
    bool create() {
        this.clear();
        string background = this.objectPrefix + "Background";
        if (!ObjectCreate(this.chartId, background, OBJ_RECTANGLE_LABEL, 0, 0, 0)
                || !ObjectSetInteger(this.chartId, background, OBJPROP_CORNER, CORNER_LEFT_UPPER)
                || !ObjectSetInteger(this.chartId, background, OBJPROP_XDISTANCE, 12)
                || !ObjectSetInteger(this.chartId, background, OBJPROP_YDISTANCE, 12)
                || !ObjectSetInteger(this.chartId, background, OBJPROP_BGCOLOR, C'18,24,32')
                || !ObjectSetInteger(this.chartId, background, OBJPROP_COLOR, C'65,80,95')
                || !ObjectSetInteger(this.chartId, background, OBJPROP_BORDER_TYPE, BORDER_FLAT)
                || !ObjectSetInteger(this.chartId, background, OBJPROP_SELECTABLE, false)
                || !ObjectSetInteger(this.chartId, background, OBJPROP_HIDDEN, true)) {
            return false;
        }
        for (int i = 0; i < ArraySize(this.lastTexts); i++) {
            string name = this.objectPrefix + "Label" + IntegerToString(i);
            if (!ObjectCreate(this.chartId, name, OBJ_LABEL, 0, 0, 0)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 9)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true)
                    || !ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic")) {
                return false;
            }
            this.lastTexts[i] = "<UNSET>";
            this.lastTooltips[i] = "<UNSET>";
            this.lastColors[i] = clrNONE;
            this.lastX[i] = -1;
            this.lastY[i] = -1;
            this.lastAnchors[i] = ANCHOR_LEFT_UPPER;
        }
        if (!ObjectCreate(this.chartId, this.objectPrefix + "Previous", OBJ_BUTTON, 0, 0, 0)
                || !ObjectCreate(this.chartId, this.objectPrefix + "Next", OBJ_BUTTON, 0, 0, 0)) {
            return false;
        }
        this.created = true;
        return true;
    }

    /**
     * ラベルの変更箇所だけをキューへ送る。成功した値だけをキャッシュする。
     */
    bool label(const int fromIndex, const string fromText, const color fromColor,
            const int fromX, const int fromY, const string fromTooltip, bool &fromChanged,
            const bool fromRightAligned = false) {
        string name = this.objectPrefix + "Label" + IntegerToString(fromIndex);
        ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
        if (fromRightAligned) {
            anchor = ANCHOR_RIGHT_UPPER;
        }
        if (this.lastTexts[fromIndex] != fromText || this.lastTooltips[fromIndex] != fromTooltip
                || this.lastColors[fromIndex] != fromColor || this.lastX[fromIndex] != fromX
                || this.lastY[fromIndex] != fromY || this.lastAnchors[fromIndex] != anchor) {
            if (!ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText)
                    || !ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, fromTooltip)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, fromColor)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_ANCHOR, anchor)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
                    || !ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)) {
                return false;
            }
            this.lastTexts[fromIndex] = fromText;
            this.lastTooltips[fromIndex] = fromTooltip;
            this.lastColors[fromIndex] = fromColor;
            this.lastX[fromIndex] = fromX;
            this.lastY[fromIndex] = fromY;
            this.lastAnchors[fromIndex] = anchor;
            fromChanged = true;
        }
        return true;
    }

    /**
     * ページ操作ボタンを配置する。
     */
    bool button(const string fromSuffix, const string fromText, const int fromX, const int fromY, const bool fromVisible) {
        long periods = OBJ_NO_PERIODS;
        if (fromVisible) {
            periods = OBJ_ALL_PERIODS;
        }
        string name = this.objectPrefix + fromSuffix;
        return ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText)
            && ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic")
            && ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 9)
            && ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, 56)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, 20)
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, clrWhiteSmoke)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, C'38,52,68')
            && ObjectSetInteger(this.chartId, name, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(this.chartId, name, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_TIMEFRAMES, periods);
    }

    /**
     * 描画失敗を一度記録し、次の更新で再生成する。
     */
    bool reportFailure() {
        if (!this.drawFailed) {
            this.logger.error(__FUNCTION__, "STATUS_PANEL_DRAW_FAILED error=" + IntegerToString(GetLastError()));
        }
        this.drawFailed = true;
        this.clear();
        return false;
    }

    /**
     * 口座通貨の桁数に丸め、符号と3桁区切りを付ける。丸めたゼロに符号を付けない。
     */
    string formatFloatingProfit(const double fromProfit, const bool fromKnown, const int fromDigits) {
        if (!fromKnown || !MathIsValidNumber(fromProfit)) {
            return "取得待ち";
        }
        int digits = MathMax(0, MathMin(16, fromDigits));
        double rounded = StringToDouble(DoubleToString(fromProfit, digits));
        string text = DoubleToString(MathAbs(rounded), digits);
        int integerEnd = StringFind(text, ".");
        if (integerEnd < 0) {
            integerEnd = StringLen(text);
        }
        for (int i = integerEnd - 3; i > 0; i -= 3) {
            text = StringSubstr(text, 0, i) + "," + StringSubstr(text, i);
        }
        if (rounded > 0.0) {
            return "+" + text;
        }
        if (rounded < 0.0) {
            return "-" + text;
        }
        return text;
    }

    /**
     * 表示桁へ丸めた評価損益の正負で色分けする。未取得とゼロは灰色にする。
     */
    color floatingProfitColor(const double fromProfit, const bool fromKnown, const int fromDigits) {
        if (!fromKnown || !MathIsValidNumber(fromProfit)) {
            return clrSilver;
        }
        double rounded = StringToDouble(DoubleToString(fromProfit, MathMax(0, MathMin(16, fromDigits))));
        if (rounded > 0.0) {
            return clrDeepSkyBlue;
        }
        if (rounded < 0.0) {
            return clrLightCoral;
        }
        return clrSilver;
    }

    /**
     * 金額・保有数と同じ読取スナップショットの単位・確認時刻・集計定義を表示する。
     */
    string floatingProfitTooltip(const double fromProfit, const bool fromKnown, const int fromCount,
            const string fromCurrency, const int fromDigits, const datetime fromTime) {
        string countText = "取得待ち";
        if (fromKnown) {
            countText = IntegerToString(fromCount);
        }
        string timeText = "未確認";
        if (fromTime > 0) {
            timeText = TimeToString(fromTime, TIME_DATE | TIME_SECONDS);
        }
        return "EA評価損益: " + this.formatFloatingProfit(fromProfit, fromKnown, fromDigits)
            + " " + fromCurrency + "\n保有: " + countText
            + "\n確認時刻(Server): " + timeText
            + "\nこのEAの対象通貨・Magicに一致するポジションだけを集計。"
            + "\nSWAPを含み、手数料を除きます。通常60秒ごとの確認値です。";
    }

    /**
     * 状態コードを短い日本語へ変換する。
     */
    string statusText(const string fromStatus) {
        if (fromStatus == "WATCH") { return "稼働"; }
        if (fromStatus == "WARMUP") { return "開始前"; }
        if (fromStatus == "WAIT_HISTORY") { return "履歴待ち"; }
        if (fromStatus == "WAIT_ANALYSIS") { return "分析待ち"; }
        if (fromStatus == "WAIT_BAR_DB") { return "判定復元"; }
        if (fromStatus == "WAIT_DB") { return "DB待ち"; }
        if (fromStatus == "SAVE_PENDING") { return "保存待ち"; }
        if (fromStatus == "LEASE_LOST") { return "Lease失効"; }
        if (fromStatus == "LOCK_LOST") { return "Lock喪失"; }
        if (fromStatus == "AUDIT_STATE_LOST") { return "監査欠落"; }
        if (fromStatus == "TIMER_WAIT") { return "Timer待ち"; }
        if (fromStatus == "RESOURCE_ERROR") { return "準備異常"; }
        return "停止";
    }

    /**
     * Tradeの最終確認状態を表示する。保有数へ読み替えない。
     */
    string tradeText(H1EaMonitorSymbolState &fromState) {
        if (!fromState.tradeKnown) { return "未取得"; }
        if (!fromState.activeTrade) { return "なし"; }
        string text = "復旧待ち";
        if (fromState.tradeStatus == "OPEN") { text = "保有"; }
        if (fromState.tradeStatus == "OPEN_PENDING") { text = "発注中"; }
        if (fromState.tradeStatus == "OPEN_PARTIAL") { text = "一部約定"; }
        if (fromState.tradeStatus == "CLOSE_PENDING") { text = "決済中"; }
        if (fromState.tradeStatus == "CLOSE_PARTIAL") { text = "一部決済"; }
        return fromState.tradeSide + " " + text;
    }

    /**
     * 行の詳細をツールチップへまとめる。
     */
    string buildTooltip(H1EaMonitorSymbolState &fromState) {
        string historyText = "WAIT";
        if (fromState.historyReady) {
            historyText = "OK";
        }
        string text = fromState.symbolName + "  " + fromState.status + "\n" + fromState.reason
            + "\n履歴準備: " + historyText
            + "\nRun: " + IntegerToString(fromState.runId)
            + "\nLease: " + TimeToString(fromState.leaseExpiresAt, TIME_DATE | TIME_SECONDS)
            + "\nTrade: " + fromState.tradeStatus + " " + fromState.tradeSide
            + "\nSL: " + DoubleToString(fromState.stopLoss, fromState.digits)
            + "\n保留SL: " + fromState.pendingStopLossKind + " " + DoubleToString(fromState.pendingStopLoss, fromState.digits)
            + "\n分析ms: " + this.milliseconds(fromState.lastAnalysisMicros) + " / 最大 " + this.milliseconds(fromState.maxAnalysisMicros);
        if (fromState.finalizedBar > 0) {
            text += "\n判定H1(Server): " + TimeToString(fromState.finalizedBar, TIME_DATE | TIME_MINUTES);
        }
        if (fromState.tradeError != "") {
            text += "\n取引エラー: " + fromState.tradeError;
        }
        return text;
    }

    /**
     * 実測microsecondsをmsで表示する。
     */
    string milliseconds(const ulong fromMicros) { return DoubleToString((double)fromMicros / 1000.0, 1); }
};

#endif
