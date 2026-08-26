//+------------------------------------------------------------------+
//|                             H1ElliotObservationAllController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZZE_H1_OBSERVATION_ALL_CONTROLLER_MQH
#define MSTNG_ZZE_H1_OBSERVATION_ALL_CONTROLLER_MQH

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\ZigZagElliotAlertDatabaseContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\ExpertAdvisor\ZigZagElliotObservationSnapshotBuilder.mqh>
#include <Mstng\Indicator\ZigZagElliot\H1ElliotObservationAllStatus.mqh>
#include <Mstng\Indicator\ZigZagElliot\H1ElliotObservationQueueItem.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 全28通貨のH1新規足Elliott観測を一括記録するクラス。
 *
 * 通貨ごとにH1境界を検出してMN1からH1までを分析する。生成済みSnapshotは
 * 中央FIFOへ固定し、単一DB接続と単一Runを使って古い順に保存する。
 */
class H1ElliotObservationAllController {
public:
    /**
     * 保持ポインタと実行状態を初期化する。
     */
    H1ElliotObservationAllController() {
        this.symbolNameInfoAll = NULL;
        this.oscillatorHandleManager = NULL;
        this.databaseContext = NULL;
        this.observationPersistenceService = NULL;
        this.initialized = false;
        this.executing = false;
        this.timerEnabled = false;
        this.testerMode = false;
        this.testerSaveGateOpen = false;
        this.databaseReady = false;
        this.competingWriterDetected = false;
        this.timerSeconds = 2;
        this.databaseRetrySeconds = 5;
        this.queueCapacity = 672;
        this.observationTesterSaveStartTime = 0;
        this.nextDatabaseRetryTime = 0;
        this.currentBatchH1BarTime = 0;
        this.lastDatabaseSaveServerTime = 0;
        this.lastExecutionMilliseconds = 0;
        this.totalSavedCount = 0;
        this.totalGapCount = 0;
        this.databaseFileName = "";
        this.databaseUseCommonFolder = true;
        this.lastDatabaseMessage = "";
        ZeroMemory(this.databaseRun);
        this.status.reset();
        this.clearStateArrays();
    }

    /**
     * 保持リソースを解放する。
     */
    ~H1ElliotObservationAllController() {
        this.destroy();
    }

    /**
     * 全通貨観測処理を初期化する。
     *
     * DBの一時的な初期化失敗ではインジケータを停止せず、タイマーから
     * 再接続する。入力、対象通貨または分析ハンドルの不正時だけ失敗する。
     *
     * @param fromDatabaseFileName 観測保存先DBファイル名
     * @param fromUseCommonFolder 共通フォルダを使用する場合true
     * @param fromTimerSeconds H1境界確認間隔秒
     * @param fromDatabaseRetrySeconds DB再接続間隔秒
     * @param fromTesterSaveStartTime TESTER観測保存開始サーバー時刻
     * @param fromQueueCapacity 保存待ちSnapshot最大数
     * @return 初期化結果
     */
    int initialize(
        const string fromDatabaseFileName,
        const bool fromUseCommonFolder,
        const int fromTimerSeconds,
        const int fromDatabaseRetrySeconds,
        const datetime fromTesterSaveStartTime,
        const int fromQueueCapacity
    ) {
        this.destroy();
        this.status.reset();

        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            this.status.message = "最適化では利用できません";

            return INIT_PARAMETERS_INCORRECT;
        }

        if (fromDatabaseFileName == ""
                || fromTimerSeconds <= 0
                || fromTimerSeconds > 60
                || fromDatabaseRetrySeconds <= 0
                || fromDatabaseRetrySeconds > 3600
                || fromTesterSaveStartTime < 0
                || fromQueueCapacity < 28) {
            this.status.message = "入力値が不正です";

            return INIT_PARAMETERS_INCORRECT;
        }

        this.databaseFileName = fromDatabaseFileName;
        this.databaseUseCommonFolder = fromUseCommonFolder;
        this.timerSeconds = fromTimerSeconds;
        this.databaseRetrySeconds = fromDatabaseRetrySeconds;
        this.queueCapacity = fromQueueCapacity;
        this.testerMode = MQLInfoInteger(MQL_TESTER) != 0;
        this.observationTesterSaveStartTime = 0;

        if (this.testerMode) {
            this.observationTesterSaveStartTime =
                fromTesterSaveStartTime;
        }
        this.testerSaveGateOpen =
            !this.isTesterSaveWindowEnabled();

        MarketContext allContext(
            "ALL",
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
        );
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(allContext);
        this.symbolNameInfoAll = new SymbolNameInfoAll();

        if (this.symbolNameInfoAll == NULL) {
            this.status.message = "通貨一覧を生成できません";
            this.destroy();

            return INIT_FAILED;
        }

        this.symbolNameInfoAll.setAll();

        if (!this.resolveTargetSymbols()) {
            this.status.message = "28通貨を解決できません";
            this.destroy();

            return INIT_FAILED;
        }

        this.initializeStateArrays();
        this.warmUpTargetSymbols();
        this.oscillatorHandleManager =
            new OscillatorHandleManager(
                ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
            );

        if (this.oscillatorHandleManager == NULL
                || !this.oscillatorHandleManager.setSymbolNameInfoAll(
                    this.symbolNameInfoAll
                )) {
            this.status.message = "分析ハンドルを生成できません";
            this.destroy();

            return INIT_FAILED;
        }

        this.oscillatorHandleManager.setTimeframesFromMn1ToAll();
        this.setDatabaseRun();
        this.nextDatabaseRetryTime =
            TimeLocal() + this.databaseRetrySeconds;

        if (!this.testerMode) {
            this.timerEnabled = EventSetTimer(this.timerSeconds);

            if (!this.timerEnabled) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "EventSetTimer failed. seconds=%d error=%d",
                        this.timerSeconds,
                        GetLastError()
                    )
                );
                this.status.message = "タイマーを開始できません";
                this.destroy();

                return INIT_FAILED;
            }
        }

        this.initialized = true;
        this.execute();
        this.refreshStatus();

        return INIT_SUCCEEDED;
    }

    /**
     * OnCalculateイベントを処理する。
     *
     * LIVEではタイマーだけを使用し、TESTERでは価格更新ごとに境界を確認する。
     *
     * @param fromRatesTotal 全バー数
     * @return 次回計算用の処理済みバー数
     */
    int onCalculate(const int fromRatesTotal) {
        if (this.initialized && this.testerMode) {
            this.execute();
        }

        return fromRatesTotal;
    }

    /**
     * OnTimerイベントでH1境界、分析再試行およびDB保存を処理する。
     */
    void onTimer() {
        if (this.initialized && !this.testerMode) {
            this.execute();
        }
    }

    /**
     * 表示用状態への非所有参照を取得する。
     *
     * @return Controller生存中だけ有効な表示用状態
     */
    H1ElliotObservationAllStatus *getStatus() {
        return &(this.status);
    }

    /**
     * DB接続、分析ハンドル、シンボル一覧およびFIFOを解放する。
     */
    void destroy() {
        if (this.timerEnabled) {
            EventKillTimer();
            this.timerEnabled = false;
        }

        this.snapshotQueue.Clear();
        this.releaseDatabase(false);

        if (this.oscillatorHandleManager != NULL) {
            delete this.oscillatorHandleManager;
            this.oscillatorHandleManager = NULL;
        }

        if (this.symbolNameInfoAll != NULL) {
            delete this.symbolNameInfoAll;
            this.symbolNameInfoAll = NULL;
        }

        this.initialized = false;
        this.executing = false;
        this.testerMode = false;
        this.testerSaveGateOpen = false;
        this.databaseReady = false;
        this.competingWriterDetected = false;
        this.nextDatabaseRetryTime = 0;
        this.currentBatchH1BarTime = 0;
        this.lastDatabaseSaveServerTime = 0;
        this.lastExecutionMilliseconds = 0;
        this.totalSavedCount = 0;
        this.totalGapCount = 0;
        this.observationTesterSaveStartTime = 0;
        this.lastDatabaseMessage = "";
        ZeroMemory(this.databaseRun);
        this.clearStateArrays();
        this.status.reset();
    }

private:
    enum TargetSymbolCount {
        /** 必須対象通貨数。 */
        requiredTargetSymbolCount = 28
    };

    /** 全対象シンボル一覧。 */
    SymbolNameInfoAll *symbolNameInfoAll;

    /** 全対象シンボルの共有オシレーターハンドル管理。 */
    OscillatorHandleManager *oscillatorHandleManager;

    /** 単一SQLite接続と永続化Serviceの所有者。 */
    ZigZagElliotAlertDatabaseContext *databaseContext;

    /** DB Contextが所有する観測永続化Serviceへの非所有参照。 */
    ZigZagElliotObservationPersistenceService
        *observationPersistenceService;

    /** 全観測に紐付ける単一Run。 */
    ZigZagElliotAlertRunEntity databaseRun;

    /** Snapshotの所有権を持つ先入れ先出しキュー。 */
    CArrayObj snapshotQueue;

    /** 表示用状態。 */
    H1ElliotObservationAllStatus status;

    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /** 初期化済みの場合true。 */
    bool initialized;

    /** 一括処理中の場合true。 */
    bool executing;

    /** タイマー開始済みの場合true。 */
    bool timerEnabled;

    /** ストラテジーテスターの場合true。 */
    bool testerMode;

    /** TESTERの全通貨事前分析が完了し保存可能な場合true。 */
    bool testerSaveGateOpen;

    /** 観測を保存可能なDB接続がある場合true。 */
    bool databaseReady;

    /** 別RunのWriterによる自然キー競合を検出した場合true。 */
    bool competingWriterDetected;

    /** 観測保存先DBファイル名。 */
    string databaseFileName;

    /** 観測DBで共通フォルダを使用する場合true。 */
    bool databaseUseCommonFolder;

    /** H1境界確認間隔秒。 */
    int timerSeconds;

    /** DB初期化または保存失敗後の再試行間隔秒。 */
    int databaseRetrySeconds;

    /** Snapshotキュー最大数。 */
    int queueCapacity;

    /** TESTERで観測保存を開始するサーバー時刻。 */
    datetime observationTesterSaveStartTime;

    /** 次にDB接続または保存を再試行できるローカル時刻。 */
    datetime nextDatabaseRetryTime;

    /** 現在集計表示している最新H1バー開始時刻。 */
    datetime currentBatchH1BarTime;

    /** 最後にDB保存できたサーバー時刻。 */
    datetime lastDatabaseSaveServerTime;

    /** 直近一括処理時間。ミリ秒。 */
    int lastExecutionMilliseconds;

    /** 起動後に保存完了したSnapshot総数。 */
    int totalSavedCount;

    /** 起動後に検出した欠損総数。 */
    int totalGapCount;

    /** DB状態の表示用メッセージ。 */
    string lastDatabaseMessage;

    /** 対象シンボル名。 */
    string symbolNames[];

    /** 通貨ごとの現在H1バー開始時刻。 */
    datetime currentH1BarTimes[];

    /** 通貨ごとの最後に検出したH1バー開始時刻。 */
    datetime lastDetectedH1BarTimes[];

    /** 通貨ごとの分析待ちH1バー開始時刻。 */
    datetime pendingAnalysisH1BarTimes[];

    /** 通貨ごとの最後にSnapshotを生成したH1バー開始時刻。 */
    datetime lastCapturedH1BarTimes[];

    /** 通貨ごとの最後に保存したH1バー開始時刻。 */
    datetime lastSavedH1BarTimes[];

    /** 通貨ごとの保存待ちSnapshot数。 */
    int symbolQueuedCounts[];

    /** 通貨ごとの連続分析再試行回数。 */
    int symbolRetryCounts[];

    /** 通貨ごとの初回分析履歴ゲート通過状態。 */
    bool analysisReadyFlags[];

    /** 通貨ごとにTESTER事前分析が成功したH1バー開始時刻。 */
    datetime testerPreflightH1BarTimes[];

    /** 通貨ごとにTESTER事前分析を試行したH1バー開始時刻。 */
    datetime testerPreflightAttemptH1BarTimes[];

    /** 通貨ごとに別RunのWriter競合を検出した場合true。 */
    bool symbolCompetingWriterFlags[];

    /** 通貨ごとの状態コード。 */
    string symbolStatusCodes[];

    /** 通貨ごとの補足メッセージ。 */
    string symbolMessages[];

    /**
     * H1境界検出、対象通貨分析およびFIFO保存を1回実行する。
     */
    void execute() {
        if (!this.initialized || this.executing) {
            return;
        }

        if (this.competingWriterDetected) {
            this.lastExecutionMilliseconds = 0;
            this.refreshStatus();

            return;
        }

        this.executing = true;
        ulong startTick = GetTickCount64();
        int total = ArraySize(this.symbolNames);

        for (int i = 0; i < total; i++) {
            this.processSymbol(i);
        }

        bool testerSaveGateOpened = this.tryOpenTesterSaveGate();

        if (testerSaveGateOpened) {
            for (int i = 0; i < total; i++) {
                this.processSymbol(i);
            }
        }

        if (this.isPersistenceAllowed()) {
            this.tryReconnectDatabaseIfDue();
            this.drainSnapshotQueue();
        } else {
            this.lastDatabaseMessage =
                "TESTER保存開始前ウォームアップ";

            if (this.currentBatchH1BarTime
                    >= this.observationTesterSaveStartTime) {
                this.lastDatabaseMessage =
                    "全通貨のTESTER事前分析成功待ち";
            }
        }
        ulong elapsed = GetTickCount64() - startTick;
        this.lastExecutionMilliseconds = (int)elapsed;
        this.executing = false;
        this.refreshStatus();
    }

    /**
     * 1通貨のH1境界を確認し、必要な分析を実行する。
     *
     * @param fromIndex 対象通貨インデックス
     */
    void processSymbol(const int fromIndex) {
        string symbolName = this.symbolNames[fromIndex];
        ResetLastError();
        datetime currentH1BarTime = iTime(
            symbolName,
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame(),
            0
        );

        if (currentH1BarTime <= 0) {
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "RETRY",
                "H1系列を取得待ち"
            );
            this.warmUpSymbol(fromIndex);

            return;
        }

        this.currentH1BarTimes[fromIndex] = currentH1BarTime;

        if (currentH1BarTime > this.currentBatchH1BarTime) {
            this.currentBatchH1BarTime = currentH1BarTime;
        }

        if (this.isTesterSaveWindowEnabled()
                && !this.testerSaveGateOpen) {
            this.processTesterPreflight(
                fromIndex,
                currentH1BarTime
            );

            return;
        }

        if (this.testerMode
                && !this.analysisReadyFlags[fromIndex]) {
            datetime previousDetectedH1BarTime =
                this.lastDetectedH1BarTimes[fromIndex];
            this.lastDetectedH1BarTimes[fromIndex] = currentH1BarTime;
            this.pendingAnalysisH1BarTimes[fromIndex] = 0;

            if (previousDetectedH1BarTime == currentH1BarTime) {
                return;
            }

            if (!this.isAnalysisSeriesReady(fromIndex)) {
                this.symbolRetryCounts[fromIndex]++;
                this.setSymbolStatus(
                    fromIndex,
                    "RETRY",
                    "TESTER履歴を準備中"
                );
                this.warmUpSymbol(fromIndex);

                return;
            }

            this.pendingAnalysisH1BarTimes[fromIndex] = currentH1BarTime;
            this.symbolRetryCounts[fromIndex] = 0;
            this.capturePendingObservation(fromIndex);

            return;
        }

        if (!this.testerMode
                && !this.analysisReadyFlags[fromIndex]
                && this.isAnalysisSeriesReady(fromIndex)) {
            this.analysisReadyFlags[fromIndex] = true;
        }

        if (this.lastDetectedH1BarTimes[fromIndex] == 0) {
            this.lastDetectedH1BarTimes[fromIndex] = currentH1BarTime;

            if (!this.testerMode) {
                if (!this.analysisReadyFlags[fromIndex]) {
                    this.warmUpSymbol(fromIndex);
                }

                this.setSymbolStatus(
                    fromIndex,
                    "BASE",
                    "現在H1をbaselineに設定"
                );

                return;
            }

            this.pendingAnalysisH1BarTimes[fromIndex] = currentH1BarTime;
        } else if (currentH1BarTime
                < this.lastDetectedH1BarTimes[fromIndex]) {
            this.lastDetectedH1BarTimes[fromIndex] = currentH1BarTime;
            this.pendingAnalysisH1BarTimes[fromIndex] = 0;
            this.symbolRetryCounts[fromIndex] = 0;
            this.setSymbolStatus(
                fromIndex,
                "ERR",
                "H1時刻が過去へ移動したためbaselineを再設定"
            );

            return;
        } else if (currentH1BarTime
                > this.lastDetectedH1BarTimes[fromIndex]) {
            this.handleNewBoundary(fromIndex, currentH1BarTime);
        }

        if (this.pendingAnalysisH1BarTimes[fromIndex] > 0) {
            this.capturePendingObservation(fromIndex);

            return;
        }

        if (this.symbolQueuedCounts[fromIndex] > 0) {
            this.setSymbolStatus(fromIndex, "DB", "DB保存待ち");

            return;
        }

        if (this.symbolCompetingWriterFlags[fromIndex]) {
            this.setSymbolStatus(
                fromIndex,
                "ERR",
                "別WriterのRunへ既存行あり"
            );

            return;
        }

        this.setSymbolStatus(fromIndex, "WAIT", "次のH1待ち");
    }

    /**
     * TESTER保存開始前の1通貨を実分析し、結果を保存せず破棄する。
     *
     * 保存開始時刻までは最初の成功後にH1時刻だけ追従する。保存開始時刻へ
     * 到達したH1では改めて実分析し、全通貨同一passの成功を確認する。
     *
     * @param fromIndex 対象通貨インデックス
     * @param fromCurrentH1BarTime 現在H1バー開始時刻
     */
    void processTesterPreflight(
        const int fromIndex,
        const datetime fromCurrentH1BarTime
    ) {
        bool saveStartReached =
            fromCurrentH1BarTime
                >= this.observationTesterSaveStartTime;

        if (!saveStartReached
                && this.analysisReadyFlags[fromIndex]) {
            this.lastDetectedH1BarTimes[fromIndex] =
                fromCurrentH1BarTime;
            this.pendingAnalysisH1BarTimes[fromIndex] = 0;
            this.symbolRetryCounts[fromIndex] = 0;
            this.setSymbolStatus(
                fromIndex,
                "WAIT",
                "TESTER保存開始前ウォームアップ"
            );

            return;
        }

        if (this.lastDetectedH1BarTimes[fromIndex]
                != fromCurrentH1BarTime) {
            this.lastDetectedH1BarTimes[fromIndex] =
                fromCurrentH1BarTime;
            this.pendingAnalysisH1BarTimes[fromIndex] =
                fromCurrentH1BarTime;
            this.symbolRetryCounts[fromIndex] = 0;
        }

        if (saveStartReached
                && this.testerPreflightH1BarTimes[fromIndex]
                    != fromCurrentH1BarTime) {
            this.analysisReadyFlags[fromIndex] = false;
        }

        if (this.analysisReadyFlags[fromIndex]
                && (!saveStartReached
                    || this.testerPreflightH1BarTimes[fromIndex]
                        == fromCurrentH1BarTime)) {
            this.pendingAnalysisH1BarTimes[fromIndex] = 0;
            this.symbolRetryCounts[fromIndex] = 0;
            this.setSymbolStatus(
                fromIndex,
                "WAIT",
                "全通貨のTESTER事前分析成功待ち"
            );

            return;
        }

        if (this.testerPreflightAttemptH1BarTimes[fromIndex]
                == fromCurrentH1BarTime) {
            this.pendingAnalysisH1BarTimes[fromIndex] = 0;
            this.setSymbolStatus(
                fromIndex,
                "RETRY",
                "次のH1でTESTER事前分析を再試行"
            );

            return;
        }

        if (this.pendingAnalysisH1BarTimes[fromIndex] <= 0) {
            this.pendingAnalysisH1BarTimes[fromIndex] =
                fromCurrentH1BarTime;
        }
        this.testerPreflightAttemptH1BarTimes[fromIndex] =
            fromCurrentH1BarTime;
        this.capturePendingObservation(fromIndex, true);
    }

    /**
     * TESTER事前分析中のH1境界変化を欠損にせず現在足へ追従する。
     *
     * @param fromIndex 対象通貨インデックス
     * @param fromCurrentH1BarTime 現在H1バー開始時刻
     */
    void handleTesterPreflightBoundaryChanged(
        const int fromIndex,
        const datetime fromCurrentH1BarTime
    ) {
        this.analysisReadyFlags[fromIndex] = false;
        this.lastDetectedH1BarTimes[fromIndex] =
            fromCurrentH1BarTime;
        this.pendingAnalysisH1BarTimes[fromIndex] = 0;
        this.currentH1BarTimes[fromIndex] =
            fromCurrentH1BarTime;
        this.symbolRetryCounts[fromIndex]++;

        if (fromCurrentH1BarTime > 0) {
            this.pendingAnalysisH1BarTimes[fromIndex] =
                fromCurrentH1BarTime;
        }

        if (fromCurrentH1BarTime > this.currentBatchH1BarTime) {
            this.currentBatchH1BarTime = fromCurrentH1BarTime;
        }
        this.setSymbolStatus(
            fromIndex,
            "WAIT",
            "H1境界更新後にTESTER事前分析を再試行"
        );
    }

    /**
     * TESTER保存開始条件を確認し、全通貨を同一H1の保存対象にする。
     *
     * @return この呼び出しで保存ゲートを開いた場合true
     */
    bool tryOpenTesterSaveGate() {
        if (!this.isTesterSaveWindowEnabled()
                || this.testerSaveGateOpen
                || this.getReadyCount()
                    != requiredTargetSymbolCount) {
            return false;
        }

        for (int i = 0; i < ArraySize(this.symbolNames); i++) {
            if (this.currentH1BarTimes[i]
                        < this.observationTesterSaveStartTime
                    || this.currentH1BarTimes[i]
                        != this.currentBatchH1BarTime
                    || this.testerPreflightH1BarTimes[i]
                        != this.currentH1BarTimes[i]) {
                return false;
            }
        }

        this.testerSaveGateOpen = true;
        this.nextDatabaseRetryTime = 0;
        this.lastDatabaseMessage = "";

        for (int i = 0; i < ArraySize(this.symbolNames); i++) {
            this.lastDetectedH1BarTimes[i] =
                this.currentH1BarTimes[i];
            this.pendingAnalysisH1BarTimes[i] =
                this.currentH1BarTimes[i];
            this.symbolRetryCounts[i] = 0;
            this.setSymbolStatus(
                i,
                "BASE",
                "TESTER観測保存を開始"
            );
        }
        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "TESTER observation save gate opened. saveStart=%s h1=%s",
                this.formatDateTime(
                    this.observationTesterSaveStartTime
                ),
                this.formatDateTime(this.currentBatchH1BarTime)
            )
        );

        return true;
    }

    /**
     * TESTERの保存開始日時を使用するか確認する。
     *
     * @return TESTERで0以外の保存開始日時を使用する場合true
     */
    bool isTesterSaveWindowEnabled() {
        return this.testerMode
            && this.observationTesterSaveStartTime > 0;
    }

    /**
     * DB接続とSnapshot保存を実行可能か確認する。
     *
     * @return 保存処理を実行可能な場合true
     */
    bool isPersistenceAllowed() {
        return !this.isTesterSaveWindowEnabled()
            || this.testerSaveGateOpen;
    }

    /**
     * 新しいH1境界を通貨状態へ反映する。
     *
     * 前の分析待ちが残っている場合は復元不能な欠損として記録し、現在足を
     * 新しい分析対象にする。
     *
     * @param fromIndex 対象通貨インデックス
     * @param fromCurrentH1BarTime 新しいH1バー開始時刻
     */
    void handleNewBoundary(
        const int fromIndex,
        const datetime fromCurrentH1BarTime
    ) {
        datetime previousBarTime =
            this.lastDetectedH1BarTimes[fromIndex];
        datetime pendingBarTime =
            this.pendingAnalysisH1BarTimes[fromIndex];
        int skippedBarCount = this.countSkippedH1Bars(
            this.symbolNames[fromIndex],
            previousBarTime,
            fromCurrentH1BarTime
        );

        if (skippedBarCount > 0) {
            this.totalGapCount += skippedBarCount;
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "Skipped H1 observations detected. symbol=%s previous=%s current=%s gaps=%d",
                    this.symbolNames[fromIndex],
                    this.formatDateTime(previousBarTime),
                    this.formatDateTime(fromCurrentH1BarTime),
                    skippedBarCount
                )
            );
        }

        if (pendingBarTime > 0 && pendingBarTime < fromCurrentH1BarTime) {
            this.totalGapCount++;
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "H1 observation gap detected. symbol=%s pending=%s current=%s",
                    this.symbolNames[fromIndex],
                    this.formatDateTime(pendingBarTime),
                    this.formatDateTime(fromCurrentH1BarTime)
                )
            );
            this.setSymbolStatus(
                fromIndex,
                "GAP",
                "前H1の分析が完了せず欠損"
            );
        }

        this.lastDetectedH1BarTimes[fromIndex] = fromCurrentH1BarTime;
        this.pendingAnalysisH1BarTimes[fromIndex] = fromCurrentH1BarTime;
        this.symbolRetryCounts[fromIndex] = 0;
    }

    /**
     * 1通貨の分析待ちH1について分析し、固定SnapshotをFIFOへ追加する。
     *
     * @param fromIndex 対象通貨インデックス
     * @param fromDiscard 分析成功結果を保存せず破棄する場合true
     */
    void capturePendingObservation(
        const int fromIndex,
        const bool fromDiscard = false
    ) {
        if (!fromDiscard
                && this.snapshotQueue.Total() >= this.queueCapacity) {
            this.setSymbolStatus(
                fromIndex,
                "DB",
                "保存待ちキューが満杯"
            );

            return;
        }

        if (!fromDiscard && this.databaseRun.sourceServer == "") {
            this.databaseRun.sourceServer = AccountInfoString(ACCOUNT_SERVER);

            if (this.databaseRun.sourceServer == "") {
                this.symbolRetryCounts[fromIndex]++;
                this.setSymbolStatus(
                    fromIndex,
                    "RETRY",
                    "取引サーバー情報を取得待ち"
                );

                return;
            }
        }

        if (!this.isAnalysisSeriesReady(fromIndex)) {
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "RETRY",
                "MN1-H1系列を準備中"
            );
            this.warmUpSymbol(fromIndex);

            return;
        }

        string symbolName = this.symbolNames[fromIndex];
        datetime targetH1BarTime =
            this.pendingAnalysisH1BarTimes[fromIndex];
        datetime beforeH1BarTime = iTime(
            symbolName,
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame(),
            0
        );

        if (beforeH1BarTime != targetH1BarTime) {
            if (fromDiscard) {
                this.handleTesterPreflightBoundaryChanged(
                    fromIndex,
                    beforeH1BarTime
                );

                return;
            }
            this.handleBoundaryChangedDuringAnalysis(
                fromIndex,
                targetH1BarTime,
                beforeH1BarTime
            );

            return;
        }

        if (fromDiscard) {
            this.setSymbolStatus(
                fromIndex,
                "RUN",
                "TESTER事前分析中"
            );
        } else {
            this.setSymbolStatus(fromIndex, "RUN", "Elliott分析中");
        }
        MarketContext marketContext(
            symbolName,
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
        );
        OscillatorHandlePool *handlePool =
            this.oscillatorHandleManager.getPoolByIndex(fromIndex);

        if (handlePool == NULL) {
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "ERR",
                "オシレーターハンドルがありません"
            );

            return;
        }

        ElliotAll *elliotAll = new ElliotAll(marketContext);

        if (elliotAll == NULL) {
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "ERR",
                "分析オブジェクトを生成できません"
            );

            return;
        }

        elliotAll.isTimer = true;
        elliotAll.timerSeconds = this.timerSeconds;
        elliotAll.setAnalysisStartTimeFrame(
            ZigZagElliotAnalysisProfile::getAnalysisStartTimeFrame()
        );
        elliotAll.setOscillatorHandlePool(handlePool);
        elliotAll.analyze();
        datetime afterH1BarTime = iTime(
            symbolName,
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame(),
            0
        );

        if (afterH1BarTime != targetH1BarTime) {
            delete elliotAll;

            if (fromDiscard) {
                this.handleTesterPreflightBoundaryChanged(
                    fromIndex,
                    afterH1BarTime
                );

                return;
            }
            this.handleBoundaryChangedDuringAnalysis(
                fromIndex,
                targetH1BarTime,
                afterH1BarTime
            );

            return;
        }

        if (!elliotAll.isAnalysisSucceeded
                || elliotAll.elliotCurrent == NULL) {
            delete elliotAll;
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "RETRY",
                "Elliott分析を再試行"
            );

            return;
        }

        if (fromDiscard) {
            delete elliotAll;
            this.analysisReadyFlags[fromIndex] = true;
            this.testerPreflightH1BarTimes[fromIndex] =
                targetH1BarTime;
            this.pendingAnalysisH1BarTimes[fromIndex] = 0;
            this.symbolRetryCounts[fromIndex] = 0;
            this.setSymbolStatus(
                fromIndex,
                "WAIT",
                "TESTER事前分析成功"
            );

            return;
        }

        H1ElliotObservationQueueItem *queueItem =
            new H1ElliotObservationQueueItem();

        if (queueItem == NULL) {
            delete elliotAll;
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "ERR",
                "Snapshot領域を確保できません"
            );

            return;
        }

        ZigZagElliotAlertRunEntity snapshotRun = this.databaseRun;

        if (snapshotRun.id <= 0) {
            snapshotRun.id = 1;
        }

        bool isBuilt = ZigZagElliotObservationSnapshotBuilder::build(
            elliotAll,
            snapshotRun,
            targetH1BarTime,
            queueItem.snapshot
        );
        delete elliotAll;

        if (!isBuilt) {
            delete queueItem;
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "RETRY",
                "Snapshot生成を再試行"
            );

            return;
        }

        queueItem.symbolName = symbolName;
        queueItem.anchorBarTime = targetH1BarTime;

        if (!this.snapshotQueue.Add(queueItem)) {
            delete queueItem;
            this.symbolRetryCounts[fromIndex]++;
            this.setSymbolStatus(
                fromIndex,
                "ERR",
                "Snapshotをキューへ追加できません"
            );

            return;
        }

        this.analysisReadyFlags[fromIndex] = true;
        this.pendingAnalysisH1BarTimes[fromIndex] = 0;
        this.lastCapturedH1BarTimes[fromIndex] = targetH1BarTime;
        this.symbolQueuedCounts[fromIndex]++;
        this.symbolRetryCounts[fromIndex] = 0;
        this.setSymbolStatus(fromIndex, "DB", "Snapshot生成済み");
    }

    /**
     * 分析前後にH1境界が変化した場合、旧対象を欠損として現在足へ進める。
     *
     * @param fromIndex 対象通貨インデックス
     * @param fromTargetH1BarTime 旧分析対象H1バー開始時刻
     * @param fromCurrentH1BarTime 現在のH1バー開始時刻
     */
    void handleBoundaryChangedDuringAnalysis(
        const int fromIndex,
        const datetime fromTargetH1BarTime,
        const datetime fromCurrentH1BarTime
    ) {
        if (fromCurrentH1BarTime > fromTargetH1BarTime) {
            this.totalGapCount++;
            this.lastDetectedH1BarTimes[fromIndex] = fromCurrentH1BarTime;
            this.pendingAnalysisH1BarTimes[fromIndex] =
                fromCurrentH1BarTime;
            this.currentH1BarTimes[fromIndex] = fromCurrentH1BarTime;

            if (fromCurrentH1BarTime > this.currentBatchH1BarTime) {
                this.currentBatchH1BarTime = fromCurrentH1BarTime;
            }

            this.setSymbolStatus(
                fromIndex,
                "GAP",
                "分析中にH1境界が変化"
            );

            return;
        }

        this.symbolRetryCounts[fromIndex]++;
        this.setSymbolStatus(
            fromIndex,
            "RETRY",
            "H1時刻の再確認待ち"
        );
    }

    /**
     * FIFO先頭からSnapshotを直列保存する。
     *
     * 1件でも失敗した場合は順序を維持して停止し、DB接続を再初期化する。
     */
    void drainSnapshotQueue() {
        if (this.snapshotQueue.Total() == 0
                || !this.databaseReady
                || this.observationPersistenceService == NULL) {
            return;
        }

        datetime localTime = TimeLocal();

        if (this.nextDatabaseRetryTime > localTime) {
            return;
        }

        while (this.snapshotQueue.Total() > 0) {
            H1ElliotObservationQueueItem *queueItem =
                this.snapshotQueue.At(0);

            if (queueItem == NULL) {
                this.snapshotQueue.Delete(0);
                continue;
            }

            long expectedRunId = this.databaseRun.id;
            queueItem.snapshot.observation.runId = expectedRunId;
            bool isSaved =
                this.observationPersistenceService.saveSnapshot(
                    queueItem.snapshot.observation,
                    queueItem.snapshot.timeFrames
                );

            if (!isSaved) {
                queueItem.retryCount++;
                int stateIndex = this.findSymbolIndex(
                    queueItem.symbolName
                );

                if (stateIndex >= 0) {
                    this.symbolRetryCounts[stateIndex] =
                        queueItem.retryCount;
                    this.setSymbolStatus(
                        stateIndex,
                        "DB",
                        "DB保存を再試行"
                    );
                }

                this.lastDatabaseMessage = "DB保存失敗、再接続待ち";
                this.releaseDatabase(false);
                this.nextDatabaseRetryTime =
                    localTime + this.databaseRetrySeconds;

                return;
            }

            int stateIndex = this.findSymbolIndex(queueItem.symbolName);
            bool isCompetingWriter =
                queueItem.snapshot.observation.runId != expectedRunId;

            if (isCompetingWriter) {
                this.competingWriterDetected = true;
                this.lastDatabaseMessage =
                    "別RunのWriterによる自然キー競合を検出";

                if (stateIndex >= 0) {
                    this.symbolCompetingWriterFlags[stateIndex] = true;
                    this.setSymbolStatus(
                        stateIndex,
                        "ERR",
                        "別Writerを停止して再起動してください"
                    );
                }

                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "Competing observation writer detected. symbol=%s anchor=%s expectedRunId=%I64d actualRunId=%I64d",
                        queueItem.symbolName,
                        this.formatDateTime(queueItem.anchorBarTime),
                        expectedRunId,
                        queueItem.snapshot.observation.runId
                    )
                );

                return;
            }

            if (stateIndex >= 0) {
                if (this.symbolQueuedCounts[stateIndex] > 0) {
                    this.symbolQueuedCounts[stateIndex]--;
                }

                this.lastSavedH1BarTimes[stateIndex] =
                    queueItem.anchorBarTime;
                this.symbolRetryCounts[stateIndex] = 0;

                if (this.symbolCompetingWriterFlags[stateIndex]) {
                    this.setSymbolStatus(
                        stateIndex,
                        "ERR",
                        "別WriterのRunへ既存行あり"
                    );
                } else if (this.symbolQueuedCounts[stateIndex] > 0) {
                    this.setSymbolStatus(
                        stateIndex,
                        "DB",
                        "後続Snapshotを保存待ち"
                    );
                } else {
                    this.setSymbolStatus(
                        stateIndex,
                        "OK",
                        "DB保存完了"
                    );
                }
            }

            this.totalSavedCount++;
            this.lastDatabaseSaveServerTime = TimeCurrent();
            this.nextDatabaseRetryTime = 0;
            this.snapshotQueue.Delete(0);
        }
    }

    /**
     * 再試行時刻に達している場合、DB接続と同一Runを再準備する。
     */
    void tryReconnectDatabaseIfDue() {
        if (this.databaseReady) {
            return;
        }

        datetime localTime = TimeLocal();

        if (this.nextDatabaseRetryTime > localTime) {
            return;
        }

        if (!this.tryInitializeDatabase()) {
            this.nextDatabaseRetryTime =
                localTime + this.databaseRetrySeconds;
        }
    }

    /**
     * SQLite接続、観測Serviceおよび単一Runを準備する。
     *
     * @return 観測を保存可能になった場合true
     */
    bool tryInitializeDatabase() {
        this.releaseDatabase(false);
        this.databaseRun.sourceServer =
            AccountInfoString(ACCOUNT_SERVER);
        this.databaseRun.sourceLogin =
            (long)AccountInfoInteger(ACCOUNT_LOGIN);

        if (this.databaseRun.sourceServer == "") {
            this.lastDatabaseMessage = "取引サーバー接続を待機中";

            return false;
        }

        this.databaseContext = new ZigZagElliotAlertDatabaseContext(
            this.databaseFileName,
            this.databaseUseCommonFolder,
            true
        );

        if (this.databaseContext == NULL
                || !this.databaseContext.open()) {
            this.lastDatabaseMessage = "DB接続を再試行中";
            this.releaseDatabase(false);

            return false;
        }

        ZigZagElliotAlertPersistenceService *alertPersistenceService =
            this.databaseContext.getPersistenceService();
        this.observationPersistenceService =
            this.databaseContext.getObservationPersistenceService();

        if (alertPersistenceService == NULL
                || this.observationPersistenceService == NULL
                || !alertPersistenceService.saveRun(this.databaseRun)) {
            this.lastDatabaseMessage = "DB Run保存を再試行中";
            this.releaseDatabase(false);

            return false;
        }

        this.databaseReady = true;
        this.nextDatabaseRetryTime = 0;
        this.lastDatabaseMessage = "";
        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "H1 observation database is ready. runId=%I64d runUid=%s",
                this.databaseRun.id,
                this.databaseRun.runUid
            )
        );

        return true;
    }

    /**
     * DB関連リソースを解放する。
     *
     * @param fromClearRun Run情報も初期化する場合true
     */
    void releaseDatabase(const bool fromClearRun) {
        this.databaseReady = false;
        this.observationPersistenceService = NULL;

        if (this.databaseContext != NULL) {
            this.databaseContext.close();
            delete this.databaseContext;
            this.databaseContext = NULL;
        }

        if (fromClearRun) {
            ZeroMemory(this.databaseRun);
        }
    }

    /**
     * 28通貨の正規名をブローカーの実シンボル名へ解決する。
     *
     * 完全一致を優先し、接頭辞または接尾辞付き候補では通貨属性が一致する
     * 最短名を選択する。解決結果はSymbolNameInfoへ反映する。
     *
     * @return 全28通貨を解決できた場合true
     */
    bool resolveTargetSymbols() {
        if (this.symbolNameInfoAll == NULL
                || this.symbolNameInfoAll.size()
                    != requiredTargetSymbolCount) {
            return false;
        }

        for (int i = 0; i < this.symbolNameInfoAll.size(); i++) {
            SymbolNameInfo *info =
                this.symbolNameInfoAll.getSymbolNameInfo(i);

            if (info == NULL || !info.isTarget) {
                return false;
            }

            string resolvedSymbolName =
                this.resolveSymbolName(info.symbolName);

            if (resolvedSymbolName == "") {
                this.logger.error(
                    __FUNCTION__,
                    "failed to resolve symbol=" + info.symbolName
                );

                return false;
            }

            info.symbolName = resolvedSymbolName;
        }

        return true;
    }

    /**
     * 正規通貨ペア名に対応する実シンボル名を取得する。
     *
     * @param fromCanonicalSymbolName 6文字の正規通貨ペア名
     * @return 解決した実シンボル名。存在しない場合は空文字
     */
    string resolveSymbolName(const string fromCanonicalSymbolName) {
        bool isCustom = false;

        if (SymbolExist(fromCanonicalSymbolName, isCustom)
                && SymbolSelect(fromCanonicalSymbolName, true)) {
            return fromCanonicalSymbolName;
        }

        string expectedBase = StringSubstr(fromCanonicalSymbolName, 0, 3);
        string expectedProfit = StringSubstr(fromCanonicalSymbolName, 3, 3);
        string resolvedSymbolName = "";
        int resolvedLength = 0;
        int total = SymbolsTotal(false);

        for (int i = 0; i < total; i++) {
            string candidate = SymbolName(i, false);

            if (candidate == ""
                    || StringFind(candidate, fromCanonicalSymbolName) < 0
                    || !SymbolSelect(candidate, true)
                    || SymbolInfoString(candidate, SYMBOL_CURRENCY_BASE)
                        != expectedBase
                    || SymbolInfoString(candidate, SYMBOL_CURRENCY_PROFIT)
                        != expectedProfit) {
                continue;
            }

            int candidateLength = StringLen(candidate);

            if (resolvedSymbolName == ""
                    || candidateLength < resolvedLength) {
                resolvedSymbolName = candidate;
                resolvedLength = candidateLength;
            }
        }

        return resolvedSymbolName;
    }

    /**
     * 28通貨の状態配列を初期化する。
     */
    void initializeStateArrays() {
        int total = this.symbolNameInfoAll.size();
        ArrayResize(this.symbolNames, total);
        ArrayResize(this.currentH1BarTimes, total);
        ArrayResize(this.lastDetectedH1BarTimes, total);
        ArrayResize(this.pendingAnalysisH1BarTimes, total);
        ArrayResize(this.lastCapturedH1BarTimes, total);
        ArrayResize(this.lastSavedH1BarTimes, total);
        ArrayResize(this.symbolQueuedCounts, total);
        ArrayResize(this.symbolRetryCounts, total);
        ArrayResize(this.analysisReadyFlags, total);
        ArrayResize(this.testerPreflightH1BarTimes, total);
        ArrayResize(this.testerPreflightAttemptH1BarTimes, total);
        ArrayResize(this.symbolCompetingWriterFlags, total);
        ArrayResize(this.symbolStatusCodes, total);
        ArrayResize(this.symbolMessages, total);

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *info =
                this.symbolNameInfoAll.getSymbolNameInfo(i);
            this.symbolNames[i] = info.symbolName;
            this.currentH1BarTimes[i] = 0;
            this.lastDetectedH1BarTimes[i] = 0;
            this.pendingAnalysisH1BarTimes[i] = 0;
            this.lastCapturedH1BarTimes[i] = 0;
            this.lastSavedH1BarTimes[i] = 0;
            this.symbolQueuedCounts[i] = 0;
            this.symbolRetryCounts[i] = 0;
            this.analysisReadyFlags[i] = false;
            this.testerPreflightH1BarTimes[i] = 0;
            this.testerPreflightAttemptH1BarTimes[i] = 0;
            this.symbolCompetingWriterFlags[i] = false;
            this.symbolStatusCodes[i] = "BASE";
            this.symbolMessages[i] = "初期化中";
        }
    }

    /**
     * 全通貨のMN1、W1、D1、H4、H1系列を取得要求する。
     */
    void warmUpTargetSymbols() {
        for (int i = 0; i < this.symbolNameInfoAll.size(); i++) {
            this.warmUpSymbol(i);
        }
    }

    /**
     * 指定通貨の観測対象系列を取得要求する。
     *
     * @param fromIndex 対象通貨インデックス
     */
    void warmUpSymbol(const int fromIndex) {
        ENUM_TIMEFRAMES timeFrames[];
        int timeFrameCount =
            ZigZagElliotAnalysisProfile::getObservationTimeFrameCount();
        ArrayResize(timeFrames, timeFrameCount);

        for (int i = 0; i < timeFrameCount; i++) {
            timeFrames[i] =
                ZigZagElliotAnalysisProfile::getObservationTimeFrame(i);
        }

        if (this.testerMode) {
            for (int i = 0; i < timeFrameCount; i++) {
                timeFrames[i] =
                    ZigZagElliotAnalysisProfile::getObservationTimeFrame(
                        timeFrameCount - 1 - i
                    );
            }
        }

        MarketContext context(
            this.symbolNames[fromIndex],
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
        );
        WarmUpSeriesUtil::warmUp(context, timeFrames, 500);
    }

    /**
     * 指定通貨の全観測対象系列が同期済みか確認する。
     *
     * @param fromIndex 対象通貨インデックス
     * @return 全系列が同期済みの場合true
     */
    bool isAnalysisSeriesReady(const int fromIndex) {
        ENUM_TIMEFRAMES timeFrames[];
        int timeFrameCount =
            ZigZagElliotAnalysisProfile::getObservationTimeFrameCount();
        ArrayResize(timeFrames, timeFrameCount);

        for (int i = 0; i < timeFrameCount; i++) {
            timeFrames[i] =
                ZigZagElliotAnalysisProfile::getObservationTimeFrame(i);
        }
        string symbolName = this.symbolNames[fromIndex];

        for (int i = 0; i < ArraySize(timeFrames); i++) {
            if (!WarmUpSeriesUtil::isSeriesSynchronized(
                symbolName,
                timeFrames[i]
            )) {
                return false;
            }

            int requiredBars = 206;

            if (timeFrames[i]
                    == ZigZagElliotAnalysisProfile::getAnalysisStartTimeFrame()) {
                requiredBars = 61;
            }

            if (Bars(symbolName, timeFrames[i]) < requiredBars) {
                return false;
            }
        }

        return true;
    }

    /**
     * 前回確認後に通過済みとなった中間H1バー数を取得する。
     *
     * 週末など取引バーが存在しない時間は欠損へ含めない。
     *
     * @param fromSymbolName 対象シンボル名
     * @param fromPreviousBarTime 前回確認したH1バー開始時刻
     * @param fromCurrentBarTime 現在のH1バー開始時刻
     * @return 観測できなかった中間H1バー数
     */
    int countSkippedH1Bars(
        const string fromSymbolName,
        const datetime fromPreviousBarTime,
        const datetime fromCurrentBarTime
    ) {
        if (fromPreviousBarTime <= 0
                || fromCurrentBarTime <= fromPreviousBarTime
                || fromCurrentBarTime - fromPreviousBarTime
                    <= PeriodSeconds(
                        ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
                    )) {
            return 0;
        }

        datetime barTimes[];
        int copiedCount = CopyTime(
            fromSymbolName,
            ZigZagElliotAnalysisProfile::getAnchorTimeFrame(),
            fromPreviousBarTime + 1,
            fromCurrentBarTime,
            barTimes
        );

        if (copiedCount <= 1) {
            return 0;
        }

        return copiedCount - 1;
    }

    /**
     * 起動単位のDB Run情報を構築する。
     */
    void setDatabaseRun() {
        ZeroMemory(this.databaseRun);
        datetime localTime = TimeLocal();
        datetime marketTime = TimeCurrent();
        string inputText = this.createInputText();

        this.databaseRun.runUid = StringFormat(
            "%s_%I64u_%I64d",
            TimeUtil::formatYyyymmddhhmiss(localTime),
            GetTickCount64(),
            ChartID()
        );
        this.databaseRun.schemaVersion = 3;
        this.databaseRun.sourceMode = "LIVE";

        if (this.testerMode) {
            this.databaseRun.sourceMode = "TESTER";
        }

        this.databaseRun.source = "ZIGZAG_ELLIOT";
        this.databaseRun.programName = MQLInfoString(MQL_PROGRAM_NAME);
        this.databaseRun.programVersion = "1.01";
        this.databaseRun.strategy = "H1_OBSERVATION_ALL";
        this.databaseRun.strategyVersion = "H1_OBSERVATION_ALL_V2";
        this.databaseRun.analysisVersion =
            ZigZagElliotAnalysisProfile::getAnalysisVersion();
        this.databaseRun.analysisInputText =
            ZigZagElliotAnalysisProfile::createCanonicalText();
        this.databaseRun.analysisInputHash =
            ZigZagElliotAnalysisProfile::createHash();
        this.databaseRun.sourceServer = AccountInfoString(ACCOUNT_SERVER);
        this.databaseRun.sourceLogin =
            (long)AccountInfoInteger(ACCOUNT_LOGIN);
        this.databaseRun.sourceChartId = ChartID();
        this.databaseRun.terminalBuild =
            (int)TerminalInfoInteger(TERMINAL_BUILD);
        this.databaseRun.testerFrom = 0;
        this.databaseRun.testerTo = 0;
        this.databaseRun.testerModel = "";
        this.databaseRun.inputText = inputText;
        this.databaseRun.inputHash = this.createTextHash(inputText);
        this.databaseRun.startedAt = localTime;
        this.databaseRun.startedAtText =
            TimeUtil::formatYyyymmddhhmiss(localTime);
        this.databaseRun.marketStartedAt = marketTime;
        this.databaseRun.marketStartedAtText =
            TimeUtil::formatYyyymmddhhmiss(marketTime);
        this.databaseRun.createdAt = localTime;
        this.databaseRun.createdAtText =
            TimeUtil::formatYyyymmddhhmiss(localTime);
    }

    /**
     * Run比較用の入力設定文字列を生成する。
     *
     * @return 入力設定文字列
     */
    string createInputText() {
        string inputText = "databaseFileName=" + this.databaseFileName;
        inputText += "|databaseUseCommonFolder="
            + (string)this.databaseUseCommonFolder;
        inputText += "|timerSeconds=" + IntegerToString(this.timerSeconds);
        inputText += "|databaseRetrySeconds="
            + IntegerToString(this.databaseRetrySeconds);
        inputText += "|observationTesterSaveStartTime="
            + StringFormat(
                "%I64d",
                (long)this.observationTesterSaveStartTime
            );
        inputText += "|queueCapacity="
            + IntegerToString(this.queueCapacity);

        for (int i = 0; i < ArraySize(this.symbolNames); i++) {
            inputText += "|symbol" + IntegerToString(i) + "="
                + this.symbolNames[i];
        }

        return inputText;
    }

    /**
     * 文字列から比較用FNV-1aハッシュを生成する。
     *
     * @param fromText 対象文字列
     * @return 符号なし64bit整数の10進文字列
     */
    string createTextHash(const string fromText) {
        ulong hashValue = 14695981039346656037;

        for (int i = 0; i < StringLen(fromText); i++) {
            hashValue ^= (ulong)StringGetCharacter(fromText, i);
            hashValue *= 1099511628211;
        }

        return StringFormat("%I64u", hashValue);
    }

    /**
     * 実シンボル名から状態配列インデックスを取得する。
     *
     * @param fromSymbolName 実シンボル名
     * @return インデックス。存在しない場合-1
     */
    int findSymbolIndex(const string fromSymbolName) {
        for (int i = 0; i < ArraySize(this.symbolNames); i++) {
            if (this.symbolNames[i] == fromSymbolName) {
                return i;
            }
        }

        return -1;
    }

    /**
     * 通貨ごとの状態コードと補足メッセージを更新する。
     *
     * @param fromIndex 対象通貨インデックス
     * @param fromStatusCode 状態コード
     * @param fromMessage 補足メッセージ
     */
    void setSymbolStatus(
        const int fromIndex,
        const string fromStatusCode,
        const string fromMessage
    ) {
        this.symbolStatusCodes[fromIndex] = fromStatusCode;
        this.symbolMessages[fromIndex] = fromMessage;
    }

    /**
     * 内部状態を描画用Modelへ反映する。
     */
    void refreshStatus() {
        this.status.isRunning = this.initialized;
        this.status.isWriterActive =
            this.initialized
                && !this.competingWriterDetected
                && this.isPersistenceAllowed();
        this.status.isDatabaseConnected = this.databaseReady;
        this.status.runId = this.databaseRun.id;
        this.status.sourceMode = this.databaseRun.sourceMode;
        this.status.currentH1JapanTime = 0;
        this.status.lastSavedJapanTime = 0;

        if (this.currentBatchH1BarTime > 0) {
            this.status.currentH1JapanTime =
                TimeJapanUtil::getJapanTime(
                    this.currentBatchH1BarTime
                );
        }

        if (this.lastDatabaseSaveServerTime > 0) {
            this.status.lastSavedJapanTime =
                TimeJapanUtil::getJapanTime(
                    this.lastDatabaseSaveServerTime
                );
        }
        this.status.targetCount = ArraySize(this.symbolNames);
        this.status.readyCount = this.getReadyCount();
        this.status.detectedCount = this.getCurrentDetectedCount();
        this.status.analyzedCount = this.getCurrentAnalyzedCount();
        this.status.savedCount = this.getCurrentSavedCount();
        this.status.queueSize = this.snapshotQueue.Total();
        this.status.queueCapacity = this.queueCapacity;
        this.status.gapCount = this.totalGapCount;
        this.status.elapsedMilliseconds =
            this.lastExecutionMilliseconds;
        this.status.message = this.lastDatabaseMessage;

        if (this.competingWriterDetected) {
            this.status.message =
                "別RunのWriterによる自然キー競合を検出";
        }

        for (int i = 0; i < ArraySize(this.symbolNames); i++) {
            this.status.setSymbol(
                i,
                this.symbolNames[i],
                this.symbolStatusCodes[i],
                this.currentH1BarTimes[i],
                this.lastCapturedH1BarTimes[i],
                this.lastSavedH1BarTimes[i],
                this.symbolQueuedCounts[i],
                this.symbolRetryCounts[i],
                this.symbolMessages[i]
            );
        }
    }

    /**
     * 初回分析履歴ゲートを通過した通貨数を取得する。
     *
     * @return 準備済み通貨数
     */
    int getReadyCount() {
        int count = 0;

        for (int i = 0; i < ArraySize(this.analysisReadyFlags); i++) {
            if (this.analysisReadyFlags[i]) {
                count++;
            }
        }

        return count;
    }

    /**
     * 現在集計H1を検出済みの通貨数を取得する。
     *
     * @return 検出済み通貨数
     */
    int getCurrentDetectedCount() {
        if (this.isTesterSaveWindowEnabled()
                && !this.testerSaveGateOpen) {
            return 0;
        }
        int count = 0;

        for (int i = 0; i < ArraySize(this.currentH1BarTimes); i++) {
            if (this.currentBatchH1BarTime > 0
                    && this.currentH1BarTimes[i]
                        == this.currentBatchH1BarTime
                    && (this.pendingAnalysisH1BarTimes[i]
                            == this.currentBatchH1BarTime
                        || this.lastCapturedH1BarTimes[i]
                            == this.currentBatchH1BarTime
                        || this.lastSavedH1BarTimes[i]
                            == this.currentBatchH1BarTime)) {
                count++;
            }
        }

        return count;
    }

    /**
     * 現在集計H1のSnapshot生成済み通貨数を取得する。
     *
     * @return 分析成功通貨数
     */
    int getCurrentAnalyzedCount() {
        if (this.isTesterSaveWindowEnabled()
                && !this.testerSaveGateOpen) {
            return 0;
        }
        int count = 0;

        for (int i = 0; i < ArraySize(this.lastCapturedH1BarTimes); i++) {
            if (this.currentBatchH1BarTime > 0
                    && this.lastCapturedH1BarTimes[i]
                        == this.currentBatchH1BarTime) {
                count++;
            }
        }

        return count;
    }

    /**
     * 現在集計H1のDB保存済み通貨数を取得する。
     *
     * @return 保存成功通貨数
     */
    int getCurrentSavedCount() {
        if (this.isTesterSaveWindowEnabled()
                && !this.testerSaveGateOpen) {
            return 0;
        }
        int count = 0;

        for (int i = 0; i < ArraySize(this.lastSavedH1BarTimes); i++) {
            if (this.currentBatchH1BarTime > 0
                    && this.lastSavedH1BarTimes[i]
                        == this.currentBatchH1BarTime) {
                count++;
            }
        }

        return count;
    }

    /**
     * 通貨状態用の動的配列を解放する。
     */
    void clearStateArrays() {
        ArrayResize(this.symbolNames, 0);
        ArrayResize(this.currentH1BarTimes, 0);
        ArrayResize(this.lastDetectedH1BarTimes, 0);
        ArrayResize(this.pendingAnalysisH1BarTimes, 0);
        ArrayResize(this.lastCapturedH1BarTimes, 0);
        ArrayResize(this.lastSavedH1BarTimes, 0);
        ArrayResize(this.symbolQueuedCounts, 0);
        ArrayResize(this.symbolRetryCounts, 0);
        ArrayResize(this.analysisReadyFlags, 0);
        ArrayResize(this.testerPreflightH1BarTimes, 0);
        ArrayResize(this.testerPreflightAttemptH1BarTimes, 0);
        ArrayResize(this.symbolCompetingWriterFlags, 0);
        ArrayResize(this.symbolStatusCodes, 0);
        ArrayResize(this.symbolMessages, 0);
    }

    /**
     * datetimeをログ表示用文字列へ変換する。
     *
     * @param fromDateTime 変換対象日時
     * @return 日時文字列
     */
    string formatDateTime(const datetime fromDateTime) {
        if (fromDateTime <= 0) {
            return "";
        }

        return TimeToString(fromDateTime, TIME_DATE | TIME_SECONDS);
    }
};

#endif // MSTNG_ZZE_H1_OBSERVATION_ALL_CONTROLLER_MQH
