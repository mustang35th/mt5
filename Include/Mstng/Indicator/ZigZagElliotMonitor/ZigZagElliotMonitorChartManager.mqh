#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_CHART_MANAGER_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_CHART_MANAGER_MQH

#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorTypes.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * M1成立結果と手動操作のチャート表示、および自動表示の重複起動を管理する。
 * 自分が開いたチャートだけを上限に数え、終了時もチャートは閉じない。
 */
class ZigZagElliotMonitorChartManager {
public:
    /**
     * チャート操作前の状態を準備する。
     */
    ZigZagElliotMonitorChartManager() {
        this.monitorChartId = 0;
        this.initialized = false;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * チャートを残したまま管理情報を解放する。
     */
    ~ZigZagElliotMonitorChartManager() {
        this.destroy();
    }

    /**
     * 監視元を保護するためのIDと、表示条件を保持する。
     *
     * @return 通常チャートで初期化できた場合true。
     */
    bool initialize(long fromMonitorChartId, ZigZagElliotMonitorConfig &fromConfig) {
        this.destroy();

        if (Util::isStrategyTester() || fromMonitorChartId <= 0 || fromConfig.maxOpenCharts <= 0) {
            return false;
        }

        this.monitorChartId = fromMonitorChartId;
        this.config = fromConfig;
        long chartIds[];
        if (!this.loadChartIds(chartIds)) {
            this.logger.error(__FUNCTION__, "監視元チャートを確認できません。" + this.chartListError);
            this.monitorChartId = 0;
            return false;
        }

        this.initialized = true;

        return true;
    }

    /**
     * 成立結果を稼働中に一度だけ処理し、チャート表示の状態を返す。
     * 上限や失敗も処理済みとし、手動で閉じた同じシグナルを再起動しない。
     */
    string openEntry(const string fromSymbolName, const ZigZagElliotMonitorResult &fromResult) {
        if (Util::isStrategyTester()) {
            return "テスター対象外";
        }

        if (!this.initialized) {
            return "未初期化";
        }

        if (fromResult.status != ZIGZAG_MONITOR_ENTRY) {
            return "対象外";
        }

        if (fromSymbolName == "" || fromResult.signalTime <= 0) {
            return "入力不正";
        }

        string direction = "SELL";
        if (fromResult.isBuy) {
            direction = "BUY";
        }

        string signalKey = fromSymbolName + "|M1|" + IntegerToString((long)fromResult.signalTime) + "|" + direction;
        if (this.isSignalProcessed(signalKey)) {
            return "処理済み";
        }

        // 起動前に記録できなければ操作を止め、失敗の連打も防ぐ。
        if (!this.recordSignal(signalKey)) {
            this.initialized = false;
            this.logger.error(__FUNCTION__, "シグナルの管理領域を確保できません。チャート表示を停止します。");
            return "管理失敗";
        }

        return this.openChart(fromSymbolName, false);
    }

    /**
     * 成立条件や自動表示設定に関係なく、指定通貨のM1を手動で前面表示する。
     * 自動表示の処理済みシグナルには触れず、閉じたチャートも再表示できる。
     */
    string openManual(const string fromSymbolName) {
        if (Util::isStrategyTester()) {
            return "テスター対象外";
        }

        if (!this.initialized) {
            return "未初期化";
        }

        if (fromSymbolName == "") {
            return "入力不正";
        }

        return this.openChart(fromSymbolName, true);
    }

    /**
     * 閉じられたチャートを除き、この管理機能が開いたチャート数を返す。
     *
     * @return 管理中の件数。参照できない場合は0件と区別して-1。
     */
    int getOpenCount() {
        if (!this.initialized || Util::isStrategyTester()) {
            return -1;
        }

        long chartIds[];
        if (!this.loadChartIds(chartIds)) {
            return -1;
        }

        this.removeClosedCharts(chartIds);

        return ArraySize(this.managedChartIds);
    }

    /**
     * 管理配列だけを解放し、既存チャートも作成したチャートも変更しない。
     */
    void destroy() {
        ArrayFree(this.processedSignalKeys);
        ArrayFree(this.managedChartIds);
        this.monitorChartId = 0;
        this.chartListError = "";
        this.initialized = false;
    }

private:
    /** 操作しない監視元のチャートID。 */
    long monitorChartId;

    /** 初期化に成功した場合true。 */
    bool initialized;

    /** 起動上限・テンプレート・前面表示の設定。 */
    ZigZagElliotMonitorConfig config;

    /** この稼働中に処理したシグナル。失敗と上限も含む。 */
    string processedSignalKeys[];

    /** この管理機能が新しく開いたチャートID。 */
    long managedChartIds[];

    /** 直近の一覧取得失敗の箇所とAPI戻り値。 */
    string chartListError;

    /** チャート操作のログ。 */
    Logger logger;

    /**
     * 既存チャートの再利用と新規作成を共通化し、自動・手動で同じ上限を守る。
     *
     * @param fromSymbolName 対象の実銘柄名。
     * @param fromForceBringToFront 設定に関係なく前面表示する場合true。
     * @return チャート表示の状態。
     */
    string openChart(const string fromSymbolName, const bool fromForceBringToFront) {
        long chartIds[];
        if (!this.loadChartIds(chartIds)) {
            this.logger.error(__FUNCTION__, "チャート一覧の参照に失敗しました。symbol=" + fromSymbolName
                + " " + this.chartListError);
            return "参照失敗";
        }

        this.removeClosedCharts(chartIds);
        long existingChartId = 0;
        if (!this.findExistingChart(chartIds, fromSymbolName, existingChartId)) {
            this.logger.error(__FUNCTION__, "既存チャートの参照に失敗しました。symbol=" + fromSymbolName);
            return "参照失敗";
        }

        if (existingChartId > 0) {
            this.bringToFront(existingChartId, fromForceBringToFront);
            return "既存表示";
        }

        int openCount = ArraySize(this.managedChartIds);
        if (openCount >= this.config.maxOpenCharts) {
            return "上限";
        }

        // 起動に成功した後で管理領域が不足しないよう、先に1件分を確保する。
        if (ArrayResize(this.managedChartIds, openCount + 1, 28) != openCount + 1) {
            this.logger.error(__FUNCTION__, "チャートの管理領域を確保できません。symbol=" + fromSymbolName);
            return "管理失敗";
        }

        this.managedChartIds[openCount] = 0;
        ResetLastError();
        long chartId = ChartOpen(fromSymbolName, PERIOD_M1);
        int errorCode = GetLastError();
        if (chartId <= 0 || this.isProtectedChart(chartId)) {
            ArrayResize(this.managedChartIds, openCount);
            this.logger.error(__FUNCTION__, "ChartOpen失敗。symbol=" + fromSymbolName + " error=" + IntegerToString(errorCode));
            return "起動失敗";
        }

        this.managedChartIds[openCount] = chartId;
        string displayStatus = "表示済み";
        if (this.config.templateName != "") {
            ResetLastError();
            if (ChartApplyTemplate(chartId, this.config.templateName)) {
                // trueはチャートキューへの受付であり、適用完了の確認ではない。
                displayStatus = "テンプレ受付";
            } else {
                errorCode = GetLastError();
                this.logger.error(__FUNCTION__, "ChartApplyTemplate失敗。symbol=" + fromSymbolName + " error=" + IntegerToString(errorCode));
                displayStatus = "テンプレ失敗";
            }
        }

        this.bringToFront(chartId, fromForceBringToFront);
        this.logger.info(__FUNCTION__, "チャート表示。symbol=" + fromSymbolName + " chartId=" + IntegerToString(chartId) + " status=" + displayStatus);

        return displayStatus;
    }

    /**
     * 監視元と現在のプログラムが動作するチャートを操作対象から除く。
     */
    bool isProtectedChart(const long fromChartId) {
        return fromChartId == this.monitorChartId || fromChartId == ChartID();
    }

    /**
     * 同じ実銘柄・M1・基準時刻・方向を既に処理したか確認する。
     */
    bool isSignalProcessed(const string fromSignalKey) {
        for (int i = ArraySize(this.processedSignalKeys) - 1; i >= 0; i--) {
            if (this.processedSignalKeys[i] == fromSignalKey) {
                return true;
            }
        }

        return false;
    }

    /**
     * 失敗や手動クローズの後も再起動しないため、処理前にキーを記録する。
     */
    bool recordSignal(const string fromSignalKey) {
        int count = ArraySize(this.processedSignalKeys);
        if (ArrayResize(this.processedSignalKeys, count + 1, 128) != count + 1) {
            return false;
        }

        this.processedSignalKeys[count] = fromSignalKey;

        return true;
    }

    /**
     * チャートID一覧を取得する。取得失敗や監視元の不在を空一覧として扱わない。
     */
    bool loadChartIds(long &fromChartIds[]) {
        ArrayFree(fromChartIds);
        this.chartListError = "";
        ResetLastError();
        long chartId = ChartFirst();
        int errorCode = GetLastError();
        if (chartId <= 0) {
            return this.failChartList("ChartFirst", chartId, errorCode, 0);
        }

        bool monitorFound = false;
        while (true) {
            // ID 0は操作関数で現在チャートを意味するため、一覧のIDとして使用しない。
            if (chartId <= 0 || this.containsChart(fromChartIds, chartId)) {
                return this.failChartList("invalidOrRepeatedId", chartId, 0, ArraySize(fromChartIds));
            }

            int count = ArraySize(fromChartIds);
            if (ArrayResize(fromChartIds, count + 1, 32) != count + 1) {
                return this.failChartList("ArrayResize", chartId, GetLastError(), count);
            }

            fromChartIds[count] = chartId;
            if (chartId == this.monitorChartId) {
                monitorFound = true;
            }

            ResetLastError();
            long nextChartId = ChartNext(chartId);
            errorCode = GetLastError();
            if (nextChartId == -1) {
                // -1は一覧の終端。終端のNOT_FOUNDと途中のチャート消失を区別する。
                if (errorCode != 0 && errorCode != ERR_CHART_NOT_FOUND) {
                    return this.failChartList("ChartNext", chartId, errorCode, count + 1);
                }

                ResetLastError();
                string lastSymbol = ChartSymbol(chartId);
                int lastChartError = GetLastError();
                if (lastSymbol == "") {
                    return this.failChartList("ChartSymbolAfterEnd", chartId, lastChartError, count + 1);
                }

                break;
            }

            chartId = nextChartId;
        }

        if (!monitorFound) {
            return this.failChartList("monitorMissing", this.monitorChartId, 0, ArraySize(fromChartIds));
        }

        return true;
    }

    /**
     * 一覧取得の失敗を保存する。定期確認のたびにはログを増やさない。
     */
    bool failChartList(const string fromOperation, const long fromChartId,
            const int fromErrorCode, const int fromCount) {
        this.chartListError = " operation=" + fromOperation + " chartId=" + IntegerToString(fromChartId)
            + " error=" + IntegerToString(fromErrorCode) + " count=" + IntegerToString(fromCount)
            + " monitorChartId=" + IntegerToString(this.monitorChartId);

        return false;
    }

    /**
     * 取得済みの一覧に対象チャートが含まれるか確認する。
     */
    bool containsChart(const long &fromChartIds[], const long fromChartId) {
        for (int i = 0; i < ArraySize(fromChartIds); i++) {
            if (fromChartIds[i] == fromChartId) {
                return true;
            }
        }

        return false;
    }

    /**
     * 完全に取得できた一覧だけを使い、手動で閉じたチャートの枠を解放する。
     */
    void removeClosedCharts(const long &fromChartIds[]) {
        int retainedCount = 0;
        int count = ArraySize(this.managedChartIds);
        for (int i = 0; i < count; i++) {
            long chartId = this.managedChartIds[i];
            if (!this.containsChart(fromChartIds, chartId)) {
                continue;
            }

            this.managedChartIds[retainedCount] = chartId;
            retainedCount++;
        }

        if (retainedCount != count) {
            ArrayResize(this.managedChartIds, retainedCount);
        }
    }

    /**
     * 監視元以外の同じ実銘柄・M1チャートを探す。
     *
     * @return 参照できた場合true。見つからない場合はIDを0で返す。
     */
    bool findExistingChart(const long &fromChartIds[], const string fromSymbolName, long &fromChartId) {
        fromChartId = 0;
        for (int i = 0; i < ArraySize(fromChartIds); i++) {
            long chartId = fromChartIds[i];
            if (this.isProtectedChart(chartId)) {
                continue;
            }

            ResetLastError();
            string symbolName = ChartSymbol(chartId);
            if (GetLastError() != 0 || symbolName == "") {
                return false;
            }

            if (symbolName != fromSymbolName) {
                continue;
            }

            ResetLastError();
            ENUM_TIMEFRAMES timeFrame = ChartPeriod(chartId);
            if (GetLastError() != 0 || timeFrame == PERIOD_CURRENT) {
                return false;
            }

            if (timeFrame == PERIOD_M1) {
                fromChartId = chartId;
                return true;
            }
        }

        return true;
    }

    /**
     * 手動操作時、または設定されている場合に対象チャートの前面表示を要求する。
     */
    void bringToFront(const long fromChartId, const bool fromForce) {
        if ((!fromForce && !this.config.bringToFront) || fromChartId <= 0 || this.isProtectedChart(fromChartId)) {
            return;
        }

        ResetLastError();
        if (!ChartSetInteger(fromChartId, CHART_BRING_TO_TOP, true)) {
            this.logger.error(__FUNCTION__, "チャートの前面表示に失敗しました。chartId=" + IntegerToString(fromChartId) + " error=" + IntegerToString(GetLastError()));
            return;
        }

        if (fromForce) {
            ChartRedraw(fromChartId);
        }
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_CHART_MANAGER_MQH
