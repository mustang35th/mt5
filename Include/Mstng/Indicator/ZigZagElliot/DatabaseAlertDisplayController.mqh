#ifndef MSTNG_DATABASE_ALERT_DISPLAY_CONTROLLER_MQH
#define MSTNG_DATABASE_ALERT_DISPLAY_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Database\Query\ZigZagElliotAlertHistoryReader.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Draw\DrawZigZagElliotAlertMarkers.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryConfig.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 通常版M5・M15・H1の保存アラート表示を管理する。分析・判定・DB書込は行わない。
 * 準備完了後の新バーでのみ読み取り、表示変更では保存済みキャッシュを使う。
 */
class DatabaseAlertDisplayController {
public:
    /**
     * 未接続・未読込の状態を初期化する。
     */
    DatabaseAlertDisplayController() {
        this.drawer = NULL;
        this.objectPrefix = "";
        this.entryVerticalLineEnabled = false;
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
     * 単独稼働の初回表示時、または全インスタンス終了後に旧世代のDB描画を回収する。
     * 一覧取得に失敗した場合は削除せず、複数表示中は他の稼働中表示を保護する。
     *
     * @param fromActiveInstance 稼働中の表示イベントから呼ぶ場合true。終了処理ではfalse。
     * @param fromKeepPrefix 保護する現在のインスタンスの接頭辞。
     * @return 回収完了または他インスタンス保護の場合true。準備中・取得失敗・削除失敗はfalse。
     */
    static bool cleanupOrphanedObjects(const bool fromActiveInstance, const string fromKeepPrefix = "") {
        if (fromActiveInstance && ChartWindowFind() != 0) {
            return false;
        }

        ResetLastError();
        int indicatorCount = ChartIndicatorsTotal(0, 0);
        if (GetLastError() != 0 || indicatorCount < 0) {
            return false;
        }

        int instanceCount = 0;
        for (int i = 0; i < indicatorCount; i++) {
            ResetLastError();
            string indicatorName = ChartIndicatorName(0, 0, i);
            if (GetLastError() != 0 || indicatorName == "") {
                return false;
            }

            if (indicatorName == "ZigZagElliot" || StringFind(indicatorName, "ZigZagElliot(") == 0) {
                instanceCount++;
            }
        }

        if (fromActiveInstance && instanceCount == 0) {
            return false;
        }

        // 終了時は自身が一覧から外れる順序に依存せず、残る一つも必ず保護する。
        if (instanceCount > 1 || (!fromActiveInstance && instanceCount > 0)) {
            return true;
        }

        ResetLastError();
        int objectCount = ObjectsTotal(0, 0, -1);
        if (GetLastError() != 0 || objectCount < 0) {
            return false;
        }

        bool succeeded = true;
        bool changed = false;
        for (int i = objectCount - 1; i >= 0; i--) {
            ResetLastError();
            string objectName = ObjectName(0, i, 0, -1);
            if (GetLastError() != 0 || objectName == "") {
                succeeded = false;
                continue;
            }

            if (StringFind(objectName, "ZzeDbAlert-") != 0
                    || (fromKeepPrefix != "" && StringFind(objectName, fromKeepPrefix) == 0)) {
                continue;
            }

            ResetLastError();
            ENUM_OBJECT objectType = (ENUM_OBJECT)ObjectGetInteger(0, objectName, OBJPROP_TYPE);
            if (GetLastError() != 0) {
                succeeded = false;
                continue;
            }

            if (!isDatabaseAlertObject(objectName, objectType)) {
                continue;
            }

            if (!ObjectDelete(0, objectName) || ObjectFind(0, objectName) >= 0) {
                succeeded = false;
                continue;
            }

            changed = true;
        }

        if (changed) {
            DrawChartRedrawBatch::request();
        }

        return succeeded;
    }

    /**
     * 旧世代の回収から保護する、自分のDB描画の接頭辞を返す。
     */
    string getObjectPrefix() {
        return this.objectPrefix;
    }

    /**
     * 検索条件だけを確認する。ウォームアップ前にDBや履歴を要求しない。
     */
    bool initialize(MarketContext &fromMarketContext, ZigZagElliotConfig &fromConfig) {
        this.marketContext = fromMarketContext;
        this.entryVerticalLineEnabled = fromConfig.entryVerticalLineEnabled;
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
        if ((this.marketContext.timeFrame != PERIOD_M5 && this.marketContext.timeFrame != PERIOD_M15
                    && this.marketContext.timeFrame != PERIOD_H1)
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
        if (Util::isStrategyTester()) {
            this.sourceMode = "TESTER";
        }

        this.objectPrefix = "ZzeDbAlert-" + IntegerToString((long)GetMicrosecondCount()) + "-";
        this.drawer = new DrawZigZagElliotAlertMarkers(ChartID(), this.objectPrefix);

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
            if (this.entryVerticalLineEnabled) {
                this.drawer.removeLiveEntryDuplicates(this.marketContext.timeFrame, fromBarTime);
            }

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

        this.drawer.draw(this.markers, Constant::PREFIX_FIXED + "TextMTF_3in3", fromKnownTime,
            this.entryVerticalLineEnabled);
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

    /** このインスタンスが所有するDB描画の接頭辞。 */
    string objectPrefix;

    /** DBに保存されたENTRY縦線を復元する場合true。 */
    bool entryVerticalLineEnabled;

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
     * 生成時の世代番号・種類・オブジェクト型がDB描画の命名形式に一致するか確認する。
     */
    static bool isDatabaseAlertObject(const string fromName, const ENUM_OBJECT fromType) {
        int prefixLength = StringLen("ZzeDbAlert-");
        int generationEnd = StringFind(fromName, "-", prefixLength);
        if (generationEnd <= prefixLength) {
            return false;
        }

        for (int i = prefixLength; i < generationEnd; i++) {
            ushort character = StringGetCharacter(fromName, i);
            if (character < '0' || character > '9') {
                return false;
            }
        }

        string suffix = StringSubstr(fromName, generationEnd + 1);

        return (fromType == OBJ_LABEL && StringFind(suffix, "Marker-") == 0
                && StringLen(suffix) > StringLen("Marker-"))
            || (fromType == OBJ_TREND && StringFind(suffix, "MarkerLink-") == 0
                && StringLen(suffix) > StringLen("MarkerLink-"))
            || (fromType == OBJ_VLINE && StringFind(suffix, "EntryLine-") == 0
                && StringLen(suffix) > StringLen("EntryLine-"));
    }

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
