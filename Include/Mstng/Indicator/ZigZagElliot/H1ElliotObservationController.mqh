//+------------------------------------------------------------------+
//|                    H1ElliotObservationController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_H1_OBSERVATION_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_H1_OBSERVATION_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\Service\ZigZagElliotObservationPersistenceService.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\ExpertAdvisor\ZigZagElliotObservationSnapshot.mqh>
#include <Mstng\ExpertAdvisor\ZigZagElliotObservationSnapshotBuilder.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * H1新規足ごとのElliott観測保存を制御するクラス。
 *
 * LIVEでは起動中のH1足をbaselineとして保存せず、次の境界から保存する。
 * TESTERでは最初に観測したH1足も保存する。保存失敗時は構築済みSnapshotを
 * 保持し、再計算で内容を変えずに次回実行で再試行する。
 */
class H1ElliotObservationController {
public:
    /**
     * 未初期化状態を設定する。
     */
    H1ElliotObservationController() {
        this.persistenceService = NULL;
        this.initialized = false;
        this.executing = false;
        this.testerMode = false;
        this.hasPendingSnapshot = false;
        this.lastDetectedH1BarTime = 0;
        this.lastSavedH1BarTime = 0;
        this.pendingRetryCount = 0;
        this.lastPendingBoundaryLogBarTime = 0;
        ZeroMemory(this.databaseRun);
        this.pendingSnapshot.clear();
    }

    /**
     * 非所有リソースとの参照を解除する。
     */
    ~H1ElliotObservationController() {
        this.destroy();
    }

    /**
     * H1市場情報、保存Serviceおよび実行情報で初期化する。
     *
     * PersistenceServiceは所有せず、呼び出し側がControllerより長く
     * 生存させる。Run Entityは再試行中も同じ実行情報を使うためコピーする。
     *
     * @param fromMarketContext H1市場コンテキスト
     * @param fromPersistenceService 非所有の観測保存Service
     * @param fromRunEntity DB保存済み実行情報
     * @return 初期化に成功した場合true
     */
    bool initialize(
        MarketContext &fromMarketContext,
        ZigZagElliotObservationPersistenceService *fromPersistenceService,
        ZigZagElliotAlertRunEntity &fromRunEntity
    ) {
        this.destroy();
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(fromMarketContext);

        if (fromMarketContext.timeFrame
                != ZigZagElliotAnalysisProfile::getAnchorTimeFrame()) {
            this.logger.error(
                __FUNCTION__,
                "H1 Elliott observation is available only on PERIOD_H1."
            );

            return false;
        }

        if (fromPersistenceService == NULL
                || fromRunEntity.id <= 0
                || (fromRunEntity.sourceMode != "LIVE"
                    && fromRunEntity.sourceMode != "TESTER")
                || fromRunEntity.sourceServer == ""
                || fromRunEntity.analysisVersion == ""
                || fromRunEntity.analysisInputHash == "") {
            this.logger.error(
                __FUNCTION__,
                "persistence service or saved database run is invalid."
            );

            return false;
        }

        this.marketContext = fromMarketContext;
        this.persistenceService = fromPersistenceService;
        this.databaseRun = fromRunEntity;
        this.testerMode = MQLInfoInteger(MQL_TESTER) != 0;

        if (fromRunEntity.sourceMode == "TESTER") {
            this.testerMode = true;
        }

        this.initialized = true;

        return true;
    }

    /**
     * H1境界を判定し、必要な観測を保存する。
     *
     * pendingがある場合は新しいSnapshotを構築する前に必ず再試行する。
     * pending保存に成功していれば、同じ呼び出しで現在の新H1足も処理する。
     *
     * @param fromElliotAll H1までの最新Elliott分析結果
     * @param fromCurrentH1BarTime 分析前後で一致を確認済みのH1バー時刻
     * @return 保存不要または保存成功の場合true。再試行が必要な場合false
     */
    bool execute(
        ElliotAll *fromElliotAll,
        const datetime fromCurrentH1BarTime
    ) {
        if (!this.initialized
                || this.persistenceService == NULL
                || this.executing
                || fromCurrentH1BarTime <= 0) {
            return false;
        }

        this.executing = true;
        bool isSucceeded = this.executeInternal(
            fromElliotAll,
            fromCurrentH1BarTime
        );
        this.executing = false;

        return isSucceeded;
    }

    /**
     * 非所有参照、Runコピーおよび再試行状態を初期化する。
     */
    void destroy() {
        this.persistenceService = NULL;
        this.initialized = false;
        this.executing = false;
        this.testerMode = false;
        this.hasPendingSnapshot = false;
        this.lastDetectedH1BarTime = 0;
        this.lastSavedH1BarTime = 0;
        this.pendingRetryCount = 0;
        this.lastPendingBoundaryLogBarTime = 0;
        ZeroMemory(this.databaseRun);
        this.pendingSnapshot.clear();
    }

    /**
     * 保存再試行中のSnapshotがあるか返す。
     *
     * @return pendingがある場合true
     */
    bool hasPending() const {
        return this.hasPendingSnapshot;
    }

    /**
     * 保存再試行回数を返す。
     *
     * @return 現在のpendingに対する失敗回数
     */
    int getPendingRetryCount() const {
        return this.pendingRetryCount;
    }

    /**
     * 最後に検出したH1バー時刻を返す。
     *
     * @return H1バー開始時刻
     */
    datetime getLastDetectedH1BarTime() const {
        return this.lastDetectedH1BarTime;
    }

    /**
     * 最後に保存できたH1バー時刻を返す。
     *
     * @return H1バー開始時刻
     */
    datetime getLastSavedH1BarTime() const {
        return this.lastSavedH1BarTime;
    }

private:
    /** H1市場コンテキスト。 */
    MarketContext marketContext;

    /** 非所有の観測保存Service。 */
    ZigZagElliotObservationPersistenceService *persistenceService;

    /** 観測と紐付ける保存済み実行情報のコピー。 */
    ZigZagElliotAlertRunEntity databaseRun;

    /** 保存失敗後も内容を固定して保持するSnapshot。 */
    ZigZagElliotObservationSnapshot pendingSnapshot;

    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /** 初期化済みの場合true。 */
    bool initialized;

    /** execute実行中の場合true。 */
    bool executing;

    /** TESTERまたはOPTIMIZATION実行の場合true。 */
    bool testerMode;

    /** 保存待ちSnapshotがある場合true。 */
    bool hasPendingSnapshot;

    /** 最後に検出したH1バー開始時刻。 */
    datetime lastDetectedH1BarTime;

    /** 最後に保存したH1バー開始時刻。 */
    datetime lastSavedH1BarTime;

    /** 現在のpending保存失敗回数。 */
    int pendingRetryCount;

    /** pending中の境界跨ぎを最後に記録したH1バー時刻。 */
    datetime lastPendingBoundaryLogBarTime;

    /**
     * pending再試行とH1境界処理を実行する。
     *
     * @param fromElliotAll H1までの最新Elliott分析結果
     * @param fromCurrentH1BarTime 分析前後で一致を確認済みのH1バー時刻
     * @return 保存不要または保存成功の場合true
     */
    bool executeInternal(
        ElliotAll *fromElliotAll,
        const datetime fromCurrentH1BarTime
    ) {
        datetime currentH1BarTime = fromCurrentH1BarTime;

        if (this.hasPendingSnapshot) {
            this.logPendingBoundaryCrossing(currentH1BarTime);

            if (!this.savePendingSnapshot()) {
                return false;
            }
        }

        if (this.lastDetectedH1BarTime == 0) {
            if (!this.testerMode) {
                this.lastDetectedH1BarTime = currentH1BarTime;
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "LIVE H1 baseline initialized without save. h1=%s",
                        formatDateTime(currentH1BarTime)
                    )
                );

                return true;
            }

            return this.buildAndSave(
                fromElliotAll,
                currentH1BarTime
            );
        }

        if (currentH1BarTime == this.lastDetectedH1BarTime) {
            return true;
        }

        if (currentH1BarTime < this.lastDetectedH1BarTime) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "H1 bar time moved backwards. previous=%s current=%s",
                    formatDateTime(this.lastDetectedH1BarTime),
                    formatDateTime(currentH1BarTime)
                )
            );
            this.lastDetectedH1BarTime = currentH1BarTime;

            return true;
        }

        return this.buildAndSave(fromElliotAll, currentH1BarTime);
    }

    /**
     * 現在の分析結果からpendingを構築して保存する。
     *
     * 構築成功時点で検出時刻を進め、保存失敗時は同じSnapshotを保持する。
     *
     * @param fromElliotAll H1までの最新Elliott分析結果
     * @param fromAnchorBarTime 観測対象H1バー開始時刻
     * @return 保存に成功した場合true
     */
    bool buildAndSave(
        ElliotAll *fromElliotAll,
        const datetime fromAnchorBarTime
    ) {
        if (!this.isAnalysisInputValid(fromElliotAll)) {
            this.logger.info(
                __FUNCTION__,
                "H1 Elliott analysis is not ready. retry on next execution."
            );

            return false;
        }

        this.pendingSnapshot.clear();

        if (!ZigZagElliotObservationSnapshotBuilder::build(
            fromElliotAll,
            this.databaseRun,
            fromAnchorBarTime,
            this.pendingSnapshot
        )) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "H1 Elliott observation build failed. h1=%s",
                    formatDateTime(fromAnchorBarTime)
                )
            );

            return false;
        }

        this.hasPendingSnapshot = true;
        this.pendingRetryCount = 0;
        this.lastPendingBoundaryLogBarTime = 0;
        this.lastDetectedH1BarTime = fromAnchorBarTime;

        return this.savePendingSnapshot();
    }

    /**
     * 保持中のSnapshotを再計算せず保存する。
     *
     * @return 保存に成功した場合true
     */
    bool savePendingSnapshot() {
        if (!this.hasPendingSnapshot || this.persistenceService == NULL) {
            return false;
        }

        datetime anchorBarTime =
            this.pendingSnapshot.observation.anchorBarTime;
        bool isSaved = this.persistenceService.saveSnapshot(
            this.pendingSnapshot.observation,
            this.pendingSnapshot.timeFrames
        );

        if (!isSaved) {
            this.pendingRetryCount++;
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "H1 Elliott observation save failed. h1=%s retries=%d",
                    formatDateTime(anchorBarTime),
                    this.pendingRetryCount
                )
            );

            return false;
        }

        this.lastSavedH1BarTime = anchorBarTime;
        this.hasPendingSnapshot = false;
        this.pendingRetryCount = 0;
        this.lastPendingBoundaryLogBarTime = 0;
        this.pendingSnapshot.clear();
        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "H1 Elliott observation saved. h1=%s",
                formatDateTime(anchorBarTime)
            )
        );

        return true;
    }

    /**
     * 保存待ち中に次のH1境界を跨いだ場合、対象バーごとに1回記録する。
     *
     * pendingを破棄せず、保存成功後に現在足のSnapshot構築へ進む。
     *
     * @param fromCurrentH1BarTime 現在のH1バー開始時刻
     */
    void logPendingBoundaryCrossing(
        const datetime fromCurrentH1BarTime
    ) {
        datetime pendingBarTime =
            this.pendingSnapshot.observation.anchorBarTime;

        if (fromCurrentH1BarTime <= pendingBarTime
                || fromCurrentH1BarTime
                    == this.lastPendingBoundaryLogBarTime) {
            return;
        }

        this.lastPendingBoundaryLogBarTime = fromCurrentH1BarTime;
        this.logger.error(
            __FUNCTION__,
            StringFormat(
                "H1 boundary crossed while snapshot is pending. pending=%s current=%s",
                formatDateTime(pendingBarTime),
                formatDateTime(fromCurrentH1BarTime)
            )
        );
    }

    /**
     * 分析結果がこのControllerのH1市場に一致するか判定する。
     *
     * @param fromElliotAll H1までのElliott分析結果
     * @return 利用できる場合true
     */
    bool isAnalysisInputValid(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL
                || !fromElliotAll.isAnalysisSucceeded
                || fromElliotAll.elliotCurrent == NULL
                || fromElliotAll.marketContext.timeFrame
                    != ZigZagElliotAnalysisProfile::getAnchorTimeFrame()
                || fromElliotAll.marketContext.symbolName
                    != this.marketContext.symbolName) {
            return false;
        }

        return true;
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

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_H1_OBSERVATION_CONTROLLER_MQH
