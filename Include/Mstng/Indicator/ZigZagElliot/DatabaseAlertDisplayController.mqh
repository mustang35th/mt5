#ifndef MSTNG_DATABASE_ALERT_DISPLAY_CONTROLLER_MQH
#define MSTNG_DATABASE_ALERT_DISPLAY_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Database\Query\ZigZagElliotAlertHistoryReader.mqh>
#include <Mstng\Draw\DrawZigZagElliotAlertMarkers.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryConfig.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 通常版M5・H1の保存アラート表示を管理する。分析・判定・DB書込は行わない。
 * 準備完了後の新バーでのみ読み取り、表示変更では保存済みキャッシュを使う。
 */
class DatabaseAlertDisplayController {
public:
    /**
     * 未接続・未読込の状態を初期化する。
     */
    DatabaseAlertDisplayController() {
        this.drawer = NULL;
        this.lastBarTime = 0;
        this.lastKnownTime = 0;
        this.resolvedRunId = 0;
        this.lastUnavailableCount = -1;
    }

    /**
     * 自分の表示と読取接続を解放する。
     */
    ~DatabaseAlertDisplayController() {
        this.reader.close();
        if (this.drawer != NULL) {
            this.drawer.clear();
            delete this.drawer;
            this.drawer = NULL;
        }
    }

    /**
     * 検索条件だけを確認する。ウォームアップ前にDBや履歴を要求しない。
     */
    bool initialize(MarketContext &fromMarketContext, ZigZagElliotConfig &fromConfig) {
        this.marketContext = fromMarketContext;
        this.config.databaseFileName = fromConfig.mtf3In3AlertDatabaseFileName;
        this.config.useCommonFolder = fromConfig.mtf3In3AlertDatabaseUseCommonFolder;
        this.allRuns = fromConfig.databaseAlertDisplayRunScope == DATABASE_ALERT_RUN_ALL;
        this.config.runId = fromConfig.databaseAlertDisplayRunId;
        if (this.allRuns) {
            this.config.runId = 0;
        }
        this.config.startDate = fromConfig.databaseAlertDisplayStartDate;
        this.config.endDate = fromConfig.databaseAlertDisplayEndDate;
        this.config.entryOnly = fromConfig.databaseAlertDisplayEntryOnly;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        string error = "";
        if ((this.marketContext.timeFrame != PERIOD_M5 && this.marketContext.timeFrame != PERIOD_H1)
                || (fromConfig.databaseAlertDisplayRunScope != DATABASE_ALERT_RUN_SELECTED
                    && fromConfig.databaseAlertDisplayRunScope != DATABASE_ALERT_RUN_ALL)) {
            this.reportError("DBアラート表示の時間足・Run対象を確認してください。");
            return false;
        }
        if (!this.config.getPeriod(this.startTime, this.endTime, error)) {
            this.reportError(error);
            return false;
        }
        this.sourceMode = "LIVE";
        if (MQLInfoInteger(MQL_TESTER)) {
            this.sourceMode = "TESTER";
        }
        string prefix = "ZzeDbAlert-" + IntegerToString((long)GetMicrosecondCount()) + "-";
        this.drawer = new DrawZigZagElliotAlertMarkers(ChartID(), prefix);
        return this.drawer != NULL;
    }

    /**
     * 準備済み表示足バーで全ラベルを一括更新する。同じバーの重複読込は行わない。
     * 実行モード・接続先・既知の判定時刻を、Run自動選択より先に絞り込む。
     */
    void update(const datetime fromBarTime, const datetime fromKnownTime, const string fromSourceServer) {
        if (this.drawer == NULL) {
            return;
        }
        if (fromBarTime <= 0 || fromKnownTime <= 0 || fromSourceServer == "") {
            ArrayFree(this.markers);
            this.resolvedRunId = 0;
            this.lastBarTime = 0;
            this.sourceServer = "";
            this.drawer.clear();
            this.reportError("DBアラート表示はサーバー名・現在時刻の取得待ちです。");
            return;
        }
        bool contextChanged = this.sourceServer != fromSourceServer || fromKnownTime < this.lastKnownTime;
        if (!contextChanged && this.lastBarTime == fromBarTime) {
            return;
        }
        if (contextChanged) {
            ArrayFree(this.markers);
            this.resolvedRunId = 0;
            this.lastUnavailableCount = -1;
        }
        this.sourceServer = fromSourceServer;
        this.lastBarTime = fromBarTime;
        this.lastKnownTime = fromKnownTime;
        long runId = this.config.runId;
        if (!this.allRuns && runId == 0 && this.resolvedRunId > 0) {
            runId = this.resolvedRunId;
        }
        long selectedRunId = 0;
        long alertIds[];
        ZigZagElliotAlertHistoryMarker loadedMarkers[];
        string error = "";
        bool success = this.reader.open(this.config.databaseFileName, this.config.useCommonFolder, error)
            && this.reader.selectMarkers(this.marketContext.symbolName, runId, this.startTime, this.endTime,
                this.config.entryOnly, selectedRunId, alertIds, loadedMarkers, error,
                this.sourceMode, this.sourceServer, fromKnownTime, this.marketContext.timeFrame, this.allRuns);
        this.reader.close();
        if (!success) {
            this.reportError(error);
            this.redraw(fromKnownTime);
            return;
        }
        if (ArrayResize(this.markers, ArraySize(loadedMarkers)) != ArraySize(loadedMarkers)) {
            ArrayFree(this.markers);
            this.reportError("DBアラート表示のメモリを確保できません。");
            this.redraw(fromKnownTime);
            return;
        }
        for (int i = 0; i < ArraySize(loadedMarkers); i++) {
            this.markers[i] = loadedMarkers[i];
        }
        int unavailableCount = 0;
        for (int i = 0; i < ArraySize(this.markers); i++) {
            if (!this.markers[i].available) {
                unavailableCount++;
            }
        }
        if (this.lastError != "" || this.resolvedRunId != selectedRunId
                || this.lastUnavailableCount != unavailableCount) {
            this.logger.info(__FUNCTION__, StringFormat("DB alert display run=%I64d allRuns=%d frame=%s count=%d unavailable=%d mode=%s server=%s",
                selectedRunId, (int)this.allRuns, EnumToString(this.marketContext.timeFrame),
                ArraySize(this.markers), unavailableCount, this.sourceMode, this.sourceServer));
        }
        this.lastError = "";
        this.lastUnavailableCount = unavailableCount;
        this.resolvedRunId = selectedRunId;
        this.redraw(fromKnownTime);
    }

    /**
     * キャッシュだけを再配置する。通常描画と同じ時刻・文字・色のラベルは省く。
     */
    void redraw(const datetime fromKnownTime) {
        if (this.drawer == NULL) {
            return;
        }
        if (fromKnownTime <= 0) {
            this.drawer.clear();
            return;
        }
        this.drawer.draw(this.markers, Constant::PREFIX_FIXED + "TextMTF_3in3", fromKnownTime);
    }

private:
    /** 現在の通貨と時間足。 */
    MarketContext marketContext;
    /** 表示用検索条件。 */
    ZigZagElliotAlertHistoryConfig config;
    /** 一括読取専用接続。 */
    ZigZagElliotAlertHistoryReader reader;
    /** 保存ラベル描画。 */
    DrawZigZagElliotAlertMarkers *drawer;
    /** 保存ラベルのキャッシュ。 */
    ZigZagElliotAlertHistoryMarker markers[];
    /** 表示開始日を含む時刻。 */
    datetime startTime;
    /** 表示終了日の翌日を含まない時刻。 */
    datetime endTime;
    /** 最後にDB読込を試みた表示足バー。 */
    datetime lastBarTime;
    /** 最後にDB検索へ渡した既知時刻。 */
    datetime lastKnownTime;
    /** 自動選択後に保持するRun。 */
    long resolvedRunId;
    /** 条件に一致する全Runを毎回読み取る場合true。 */
    bool allRuns;
    /** LIVEまたはTESTER。 */
    string sourceMode;
    /** 検索対象サーバー。 */
    string sourceServer;
    /** 重複ログを抑える直前のエラー。 */
    string lastError;
    /** 直前の表示値不足件数。 */
    int lastUnavailableCount;
    /** 表示用診断ログ。 */
    Logger logger;

    /**
     * 同じ表示エラーを毎バー記録しない。通常の分析は止めない。
     */
    void reportError(const string fromError) {
        if (this.lastError != fromError) {
            this.logger.info(__FUNCTION__, fromError);
            this.lastError = fromError;
        }
    }
};

#endif
