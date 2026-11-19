#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_CONTROLLER_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_CONTROLLER_MQH

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Draw\DrawZigZagElliotMonitor.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorChartManager.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorEvaluationObserver.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorEvaluator.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorProgress.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSymbolState.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 通貨ペアを1件ずつ監視し、初回確認を含むM1成立を別チャートへ表示する。
 */
class ZigZagElliotMonitorController : public ZigZagElliotMonitorEvaluationObserver {
public:
    /**
     * 所有資源を初期化する。
     */
    ZigZagElliotMonitorController() {
        this.chartId = 0;
        this.nextIndex = 0;
        this.lastEvaluationTime = 0;
        this.lastOpenCount = -2;
        this.monitoring = false;
        this.autoOpen = false;
        this.initialized = false;
        this.executing = false;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 所有資源と自分の描画を解放する。
     */
    ~ZigZagElliotMonitorController() {
        this.destroy();
    }

    /**
     * 対象通貨・判定器・チャート管理・一覧を準備する。
     */
    bool initialize(const long fromChartId, ZigZagElliotMonitorConfig &fromConfig) {
        this.destroy();
        if (Util::isStrategyTester() || fromChartId <= 0) {
            return false;
        }

        this.chartId = fromChartId;
        this.config = fromConfig;
        this.monitoring = this.config.monitoringEnabled;
        this.autoOpen = this.config.autoOpenEnabled;
        this.prefix = "ZzeMon" + (string)this.chartId + "-" + (string)GetTickCount() + "-";
        if (!this.buildTargets() || !this.evaluator.initialize(this.config)
                || !this.chartManager.initialize(this.chartId, this.config)
                || !this.view.initialize(this.chartId, this.prefix, this.config.fontSize)) {
            this.destroy();

            return false;
        }

        this.initialized = true;
        this.updateView();

        return true;
    }

    /**
     * 1回のイベントでは最大1通貨を分析し、重い分析の連続実行を避ける。
     */
    void processNext() {
        if (!this.initialized || this.executing) {
            return;
        }

        this.executing = true;
        bool changed = this.progress.targetBarTime != ZigZagElliotMonitorProgress::getCurrentBarTime();
        int total = this.states.Total();
        if (this.monitoring && total > 0) {
            for (int i = 0; i < total; i++) {
                int index = (this.nextIndex + i) % total;
                ZigZagElliotMonitorSymbolState *state = this.states.At(index);
                if (state == NULL) {
                    continue;
                }

                if (state.symbolName == "" && GetTickCount64() >= state.nextRetryTick) {
                    string resolvedSymbol = this.resolveSymbolName(state.canonicalSymbolName);
                    if (resolvedSymbol != "") {
                        state.symbolName = resolvedSymbol;
                        state.marketContext.setSymbolName(resolvedSymbol);
                    }
                }

                ZigZagElliotMonitorResult result;
                result.reset();
                if (!this.evaluator.evaluate(*state, result, GetPointer(this))) {
                    continue;
                }

                this.progress.activeSymbol = "";
                this.progress.lastSymbol = state.canonicalSymbolName;
                this.progress.lastDurationMs = result.durationMs;
                state.result = result;
                this.lastEvaluationTime = result.evaluatedAtSrv;
                if (result.completed) {
                    state.baselineReady = true;
                }

                if (result.status == ZIGZAG_MONITOR_ENTRY) {
                    state.lastEntryTime = result.evaluatedAtSrv;
                    state.lastEntryIsBuy = result.isBuy;

                    // チャート起動の前に確認中を解除し、確定した判定と処理時間を表示する。
                    this.updateView(false);
                    if (!this.autoOpen) {
                        state.chartStatus = "自動表示OFF";
                    } else {
                        state.chartStatus = this.chartManager.openEntry(state.symbolName, result);
                    }
                }

                this.nextIndex = (index + 1) % total;
                changed = true;
                break;
            }
        }

        int openCount = this.chartManager.getOpenCount();
        if (changed || openCount != this.lastOpenCount) {
            this.updateView();
        }

        this.executing = false;
    }

    /**
     * スキップされなかった通貨だけを確認中として描画する。
     * 表示専用の時刻を記録し、判定足・シグナル回数には触れない。
     */
    virtual void onEvaluationStarted(ZigZagElliotMonitorSymbolState &fromState) {
        fromState.lastAttemptBarTime = ZigZagElliotMonitorProgress::getCurrentBarTime();
        this.progress.activeSymbol = fromState.canonicalSymbolName;
        this.updateView(false);
    }

    /**
     * 監視・自動表示・表示順の切替、通貨別の手動表示、画面サイズ変更を処理する。
     */
    void handleChartEvent(const int fromId, const string fromObjectName) {
        if (!this.initialized) {
            return;
        }

        if (fromId == CHARTEVENT_CHART_CHANGE) {
            this.updateView();

            return;
        }

        if (fromId != CHARTEVENT_OBJECT_CLICK) {
            return;
        }

        if (fromObjectName == this.view.getMonitorButtonName()) {
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            this.monitoring = !this.monitoring;
            if (this.monitoring) {
                this.resetBaselines();
            }

            this.updateView();
        } else if (fromObjectName == this.view.getAutoButtonName()) {
            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            this.autoOpen = !this.autoOpen;
            this.updateView();
        } else if (this.view.handleSortClick(fromObjectName)) {
            this.updateView(false);
        } else {
            this.openManualChart(fromObjectName);
        }
    }

    /**
     * 開いたチャートは残し、自分が所有する資源だけを解放する。
     */
    void destroy() {
        this.initialized = false;
        this.view.destroy();
        this.chartManager.destroy();
        this.states.Clear();
        this.evaluator.destroy();
        this.nextIndex = 0;
        this.lastEvaluationTime = 0;
        this.lastOpenCount = -2;
        this.executing = false;
        this.progress.reset();
    }

private:
    /** 監視元チャート。 */
    long chartId;

    /** このインスタンスの描画名接頭辞。 */
    string prefix;

    /** 共通設定。 */
    ZigZagElliotMonitorConfig config;

    /** 通貨ペアごとの状態を所有する一覧。 */
    CArrayObj states;

    /** 既存M1判定を呼び出す担当。 */
    ZigZagElliotMonitorEvaluator evaluator;

    /** チャート起動と重複管理の担当。 */
    ZigZagElliotMonitorChartManager chartManager;

    /** 一覧描画の担当。 */
    DrawZigZagElliotMonitor view;

    /** 今回のM1足の進捗と直近の確認時間。判定条件には使用しない。 */
    ZigZagElliotMonitorProgress progress;

    /** 監視実行状態。 */
    bool monitoring;

    /** 新規成立の自動表示状態。 */
    bool autoOpen;

    /** 初期化済みの場合true。 */
    bool initialized;

    /** イベント処理の重複を防ぐ実行状態。 */
    bool executing;

    /** 次に確認する通貨の位置。 */
    int nextIndex;

    /** 最後に判定・データ確認を試みたサーバー時刻。 */
    datetime lastEvaluationTime;

    /** 前回表示した管理チャート数。参照失敗は-1。 */
    int lastOpenCount;

    /** 診断ログ。 */
    Logger logger;

    /**
     * 通貨名に紐付くボタンから、判定状態と独立してM1チャートを表示する。
     * 表示順が変わっても押した通貨を使い、成立時刻・回数・初回状態は変更しない。
     */
    void openManualChart(const string fromObjectName) {
        for (int i = 0; i < this.states.Total(); i++) {
            ZigZagElliotMonitorSymbolState *state = this.states.At(i);
            if (state == NULL || fromObjectName != this.view.getChartButtonName(state.canonicalSymbolName)) {
                continue;
            }

            ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);
            if (state.symbolName == "") {
                string resolvedSymbol = this.resolveSymbolName(state.canonicalSymbolName);
                if (resolvedSymbol != "") {
                    state.symbolName = resolvedSymbol;
                    state.marketContext.setSymbolName(resolvedSymbol);
                }
            }

            if (state.symbolName == "") {
                state.chartStatus = "手動 銘柄なし";
            } else {
                state.chartStatus = "手動 " + this.chartManager.openManual(state.symbolName);
            }

            this.logger.info(__FUNCTION__, "手動表示結果。symbol=" + state.canonicalSymbolName
                + " actualSymbol=" + state.symbolName + " status=" + state.chartStatus);
            this.updateView();

            return;
        }
    }

    /**
     * GMO対象フラグで実際の監視資源を限定し、正規名順に登録する。
     */
    bool buildTargets() {
        SymbolNameInfoAll symbols;
        symbols.setAll();
        if (this.config.gmoOnly) {
            symbols.setGmo();
        }

        string targetNames[];
        int count = 0;
        for (int i = 0; i < symbols.size(); i++) {
            SymbolNameInfo *info = symbols.getSymbolNameInfo(i);
            if (info == NULL || !info.isTarget) {
                continue;
            }

            if (ArrayResize(targetNames, count + 1) != count + 1) {
                return false;
            }

            targetNames[count] = info.symbolName;
            count++;
        }

        for (int i = 0; i < count - 1; i++) {
            for (int j = i + 1; j < count; j++) {
                if (StringCompare(targetNames[i], targetNames[j]) > 0) {
                    string swapName = targetNames[i];
                    targetNames[i] = targetNames[j];
                    targetNames[j] = swapName;
                }
            }
        }

        for (int i = 0; i < count; i++) {
            string resolvedSymbol = this.resolveSymbolName(targetNames[i]);
            ZigZagElliotMonitorSymbolState *state = new ZigZagElliotMonitorSymbolState(
                targetNames[i], resolvedSymbol);
            if (state == NULL) {
                return false;
            }

            if (!this.states.Add(state)) {
                delete state;

                return false;
            }
        }

        return count > 0;
    }

    /**
     * 正規名を優先し、接頭辞・接尾辞付き銘柄は通貨属性と一意性を確認する。
     */
    string resolveSymbolName(const string fromCanonicalSymbolName) {
        string baseCurrency = StringSubstr(fromCanonicalSymbolName, 0, 3);
        string quoteCurrency = StringSubstr(fromCanonicalSymbolName, 3, 3);
        bool custom = false;
        if (SymbolExist(fromCanonicalSymbolName, custom) && !custom
                && SymbolSelect(fromCanonicalSymbolName, true)
                && SymbolInfoString(fromCanonicalSymbolName, SYMBOL_CURRENCY_BASE) == baseCurrency
                && SymbolInfoString(fromCanonicalSymbolName, SYMBOL_CURRENCY_PROFIT) == quoteCurrency) {
            return fromCanonicalSymbolName;
        }

        string foundSymbol = "";
        int shortestLength = 0;
        bool ambiguous = false;
        int total = SymbolsTotal(false);
        for (int i = 0; i < total; i++) {
            string candidate = SymbolName(i, false);
            string upperCandidate = candidate;
            StringToUpper(upperCandidate);
            if (candidate == "" || StringFind(upperCandidate, fromCanonicalSymbolName) < 0
                    || !SymbolExist(candidate, custom) || custom
                    || !SymbolSelect(candidate, true)
                    || SymbolInfoString(candidate, SYMBOL_CURRENCY_BASE) != baseCurrency
                    || SymbolInfoString(candidate, SYMBOL_CURRENCY_PROFIT) != quoteCurrency) {
                continue;
            }

            int length = StringLen(candidate);
            if (foundSymbol == "" || length < shortestLength) {
                foundSymbol = candidate;
                shortestLength = length;
                ambiguous = false;
            } else if (length == shortestLength && candidate != foundSymbol) {
                ambiguous = true;
            }
        }

        if (foundSymbol == "" || ambiguous || !SymbolSelect(foundSymbol, true)) {
            return "";
        }

        return foundSymbol;
    }

    /**
     * 確認済み件数と判定対象足をリセットし、シグナル回数を保持して現在の足を再確認する。
     */
    void resetBaselines() {
        for (int i = 0; i < this.states.Total(); i++) {
            ZigZagElliotMonitorSymbolState *state = this.states.At(i);
            if (state == NULL) {
                continue;
            }

            state.baselineReady = false;
            state.lastProcessedBarTime = 0;
            state.evaluationBarTime = 0;
            state.targetM5BarTime = 0;
            state.nextRetryTick = 0;
            state.lastAttemptBarTime = 0;
            state.result.reset();
        }

        this.nextIndex = 0;
        this.progress.reset();
    }

    /**
     * 表示に変更がある場合だけまとめて再描画する。
     *
     * @param fromRefreshOpenCount 確認開始・完了の中間表示では保持済み枚数を使用する。
     */
    void updateView(const bool fromRefreshOpenCount = true) {
        this.progress.updateCounts(this.states, ZigZagElliotMonitorProgress::getCurrentBarTime());
        if (fromRefreshOpenCount) {
            this.lastOpenCount = this.chartManager.getOpenCount();
        }

        if (this.view.update(this.states, this.monitoring, this.autoOpen,
                this.lastOpenCount, this.config.maxOpenCharts, this.lastEvaluationTime, this.progress)) {
            ChartRedraw(this.chartId);
        }
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_CONTROLLER_MQH
