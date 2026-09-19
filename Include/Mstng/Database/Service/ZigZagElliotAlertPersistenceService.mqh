//+------------------------------------------------------------------+
//|                          ZigZagElliotAlertPersistenceService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZIGZAG_ELLIOT_ALERT_PERSISTENCE_MQH
#define MSTNG_ZIGZAG_ELLIOT_ALERT_PERSISTENCE_MQH

#include <Mstng\Database\Dao\ZigZagElliotAlertCorrectionDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertPointDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertRunDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertTimeFrameDao.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliotアラートスナップショットをSQLiteへ保存するサービス。
 *
 * 実行情報、アラート、時間足別分析および最新Waveのポイントを管理し、
 * アラート配下の全データを1トランザクションで保存する。
 */
class ZigZagElliotAlertPersistenceService {
public:
    /**
     * データベースハンドルとDAOを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル
     * @param fromAlertDao アラートDAO
     * @param fromPointDao ポイントDAO
     * @param fromRunDao 実行情報DAO
     * @param fromTimeFrameDao 時間足別分析DAO
     * @param fromCorrectionDao 補正メタ情報DAO。旧保存APIのみの場合はNULL。
     * @param fromCorrectedTimeFrameDao 補正後時間足DAO。
     * @param fromCorrectedPointDao 補正後ポイントDAO。
     */
    ZigZagElliotAlertPersistenceService(
        const int fromDatabaseHandle,
        ZigZagElliotAlertDao *fromAlertDao,
        ZigZagElliotAlertPointDao *fromPointDao,
        ZigZagElliotAlertRunDao *fromRunDao,
        ZigZagElliotAlertTimeFrameDao *fromTimeFrameDao,
        ZigZagElliotAlertCorrectionDao *fromCorrectionDao = NULL,
        ZigZagElliotAlertTimeFrameDao *fromCorrectedTimeFrameDao = NULL,
        ZigZagElliotAlertPointDao *fromCorrectedPointDao = NULL
    ) {
        this.databaseHandle = fromDatabaseHandle;
        this.alertDao = fromAlertDao;
        this.pointDao = fromPointDao;
        this.runDao = fromRunDao;
        this.timeFrameDao = fromTimeFrameDao;
        this.correctionDao = fromCorrectionDao;
        this.correctedTimeFrameDao = fromCorrectedTimeFrameDao;
        this.correctedPointDao = fromCorrectedPointDao;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * アラート関連テーブルと外部キー制約を準備する。
     *
     * @return 準備に成功した場合true
     */
    bool createTables() {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        if (!this.enableForeignKeys()) {
            return false;
        }

        if (!this.runDao.createTable()) {
            return false;
        }

        if (!this.alertDao.createTable()) {
            return false;
        }

        if (!this.timeFrameDao.createTable()) {
            return false;
        }

        if (!this.pointDao.createTable()) {
            return false;
        }
        if (this.correctionDao == NULL && this.correctedTimeFrameDao == NULL
                && this.correctedPointDao == NULL) {
            return true;
        }
        return this.isCorrectionReady()
            && this.correctionDao.createTable()
            && this.correctedTimeFrameDao.createTable()
            && this.correctedPointDao.createTable();
    }

    /**
     * 実行情報を保存または取得する。
     *
     * 同一runUidが存在する場合は既存IDを設定し、新しい行を追加しない。
     *
     * @param fromRunEntity 実行情報
     * @return 保存または取得に成功した場合true
     */
    bool saveRun(ZigZagElliotAlertRunEntity &fromRunEntity) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        this.normalizeRunTextValues(fromRunEntity);

        if (fromRunEntity.runUid == "") {
            this.logger.error(__FUNCTION__, "runUid is empty.");

            return false;
        }

        if (fromRunEntity.schemaVersion >= 2
                && (fromRunEntity.analysisVersion == ""
                    || fromRunEntity.analysisInputText == ""
                    || !this.isLowerHexSha256(
                        fromRunEntity.analysisInputHash
                    ))) {
            this.logger.error(
                __FUNCTION__,
                "schemaVersion 2 or later requires a valid analysis profile."
            );

            return false;
        }

        long existingRunId = 0;

        if (!this.runDao.findIdByRunUid(
                fromRunEntity.runUid,
                existingRunId
            )) {
            return false;
        }

        if (existingRunId > 0) {
            fromRunEntity.id = existingRunId;

            return true;
        }

        fromRunEntity.id = 0;

        return this.runDao.insert(fromRunEntity);
    }

    /**
     * 保存済みRunの実行状態、進捗およびテスター再現情報を更新する。
     *
     * @param fromRunEntity 更新対象Runと実行進捗。
     * @return 更新に成功した場合true。
     */
    bool updateRunExecutionProgress(
        ZigZagElliotAlertRunEntity &fromRunEntity
    ) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        this.normalizeRunTextValues(fromRunEntity);

        if (fromRunEntity.id <= 0
                || fromRunEntity.status == ""
                || fromRunEntity.testerFrom < 0
                || fromRunEntity.testerTo < 0
                || (fromRunEntity.testerFrom > 0
                    && fromRunEntity.testerTo > 0
                    && fromRunEntity.testerTo < fromRunEntity.testerFrom)
                || fromRunEntity.evaluationStartedAt < 0
                || fromRunEntity.lastCompletedH1BarTime < 0
                || fromRunEntity.evaluatedH1Count < 0
                || fromRunEntity.savedAlertCount < 0
                || fromRunEntity.completedAt < 0) {
            this.logger.error(
                __FUNCTION__,
                "Run execution progress value is invalid."
            );

            return false;
        }

        return this.runDao.updateExecutionProgress(fromRunEntity);
    }

    /**
     * 1アラート分の親子スナップショットを保存する。
     *
     * 同一実行内の同一自然キーが存在する場合は最初のスナップショットを保持し、
     * 子データを更新しない。
     *
     * @param fromAlertEntity アラート本体
     * @param fromTimeFrameEntities 時間足別分析一覧
     * @param fromPointEntities 最新Waveポイント一覧
     * @return 保存または重複確認に成功した場合true
     */
    bool saveSnapshot(
        ZigZagElliotAlertEntity &fromAlertEntity,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotAlertPointEntity &fromPointEntities[]
    ) {
        ZigZagElliotAlertCorrectionEntity correction;
        ZeroMemory(correction);
        ZigZagElliotAlertTimeFrameEntity correctedTimeFrames[];
        ZigZagElliotAlertPointEntity correctedPoints[];
        return this.saveSnapshotInternal(
            fromAlertEntity, fromTimeFrameEntities, fromPointEntities,
            false, correction, correctedTimeFrames, correctedPoints
        );
    }

    /**
     * 元分析と補正比較情報を1トランザクションで保存する。
     *
     * 既存親があれば補正未記録の場合も追記せず、最初の全体を保持する。
     *
     * @param fromAlertEntity 元分析と最終判定のアラート本体。
     * @param fromTimeFrameEntities 元分析の時間足一覧。
     * @param fromPointEntities 元分析の最新Waveポイント。
     * @param fromCorrection 補正なしもNONEとして保存する比較情報。
     * @param fromCorrectedTimeFrames 補正採用時だけ保存する全7時間足。
     * @param fromCorrectedPoints 補正後の最新Waveポイント。
     * @return 保存または重複確認に成功した場合true。
     */
    bool saveSnapshot(
        ZigZagElliotAlertEntity &fromAlertEntity,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotAlertPointEntity &fromPointEntities[],
        ZigZagElliotAlertCorrectionEntity &fromCorrection,
        ZigZagElliotAlertTimeFrameEntity &fromCorrectedTimeFrames[],
        ZigZagElliotAlertPointEntity &fromCorrectedPoints[]
    ) {
        return this.saveSnapshotInternal(
            fromAlertEntity, fromTimeFrameEntities, fromPointEntities,
            true, fromCorrection, fromCorrectedTimeFrames, fromCorrectedPoints
        );
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;
    /** アラートDAO。 */
    ZigZagElliotAlertDao *alertDao;
    /** ポイントDAO。 */
    ZigZagElliotAlertPointDao *pointDao;
    /** 実行情報DAO。 */
    ZigZagElliotAlertRunDao *runDao;
    /** 時間足別分析DAO。 */
    ZigZagElliotAlertTimeFrameDao *timeFrameDao;
    /** 補正比較情報DAOへの非所有参照。 */
    ZigZagElliotAlertCorrectionDao *correctionDao;
    /** 補正後時間足DAOへの非所有参照。 */
    ZigZagElliotAlertTimeFrameDao *correctedTimeFrameDao;
    /** 補正後ポイントDAOへの非所有参照。 */
    ZigZagElliotAlertPointDao *correctedPointDao;
    /** ロガー。 */
    Logger logger;

    /**
     * 旧保存APIと補正付きAPIで共有する原子的な保存処理。
     *
     * @return 保存または既存アラート保持に成功した場合true。
     */
    bool saveSnapshotInternal(
        ZigZagElliotAlertEntity &fromAlertEntity,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotAlertPointEntity &fromPointEntities[],
        const bool fromHasCorrection,
        ZigZagElliotAlertCorrectionEntity &fromCorrection,
        ZigZagElliotAlertTimeFrameEntity &fromCorrectedTimeFrames[],
        ZigZagElliotAlertPointEntity &fromCorrectedPoints[]
    ) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        this.normalizeSnapshotTextValues(
            fromAlertEntity,
            fromTimeFrameEntities,
            fromPointEntities
        );

        if (!this.isSnapshotValid(
                fromAlertEntity,
                fromTimeFrameEntities,
                fromPointEntities
            )) {
            return false;
        }

        if (fromHasCorrection) {
            fromCorrection.alertId = 0;
            this.normalizeCorrectionTextValues(fromCorrection);
            for (int i = 0; i < ArraySize(fromCorrectedTimeFrames); i++) {
                this.normalizeTimeFrameTextValues(fromCorrectedTimeFrames[i]);
            }
            for (int i = 0; i < ArraySize(fromCorrectedPoints); i++) {
                this.normalizePointTextValues(fromCorrectedPoints[i]);
            }
            if (!this.isCorrectionReady() || !this.isCorrectionSnapshotValid(
                    fromAlertEntity, fromTimeFrameEntities, fromPointEntities,
                    fromCorrection, fromCorrectedTimeFrames, fromCorrectedPoints)) {
                this.logger.error(__FUNCTION__, "correction snapshot is invalid.");
                return false;
            }
        }

        ResetLastError();

        if (!DatabaseTransactionBegin(this.databaseHandle)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionBegin failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        long existingAlertId = 0;
        string existingSnapshotHash = "";
        bool isSaved = this.alertDao.findByNaturalKey(
            fromAlertEntity,
            existingAlertId,
            existingSnapshotHash
        );

        if (isSaved && existingAlertId > 0) {
            fromAlertEntity.id = existingAlertId;

            if (existingSnapshotHash != fromAlertEntity.snapshotHash) {
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "Existing alert snapshot is retained. alertId=%I64d eventUid=%s",
                        existingAlertId,
                        fromAlertEntity.eventUid
                    )
                );
            }

            if (!this.commitTransaction(__FUNCTION__)) {
                this.rollbackTransaction(__FUNCTION__);

                return false;
            }

            return true;
        }

        if (isSaved) {
            isSaved = this.alertDao.insert(fromAlertEntity);
        }

        int timeFrameCount = ArraySize(fromTimeFrameEntities);
        int pointCount = ArraySize(fromPointEntities);
        if (isSaved) {
            isSaved = this.saveAnalysisChildren(
                fromAlertEntity.id, fromTimeFrameEntities, fromPointEntities,
                this.timeFrameDao, this.pointDao
            );
        }
        if (isSaved && fromHasCorrection) {
            fromCorrection.alertId = fromAlertEntity.id;
            isSaved = this.correctionDao.insert(fromCorrection);
            if (isSaved && fromCorrection.correctionStatus == "APPLIED") {
                isSaved = this.saveAnalysisChildren(
                    fromAlertEntity.id, fromCorrectedTimeFrames, fromCorrectedPoints,
                    this.correctedTimeFrameDao, this.correctedPointDao
                );
            }
        }

        if (!isSaved) {
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromAlertEntity, fromTimeFrameEntities, fromPointEntities
            );
            this.clearCorrectionIds(
                fromCorrection, fromCorrectedTimeFrames, fromCorrectedPoints
            );

            return false;
        }

        if (!this.commitTransaction(__FUNCTION__)) {
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromAlertEntity, fromTimeFrameEntities, fromPointEntities
            );
            this.clearCorrectionIds(
                fromCorrection, fromCorrectedTimeFrames, fromCorrectedPoints
            );

            return false;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "Alert snapshot saved. alertId=%I64d timeFrames=%d points=%d",
                fromAlertEntity.id,
                timeFrameCount,
                pointCount
            )
        );

        return true;
    }

    /**
     * 元分析または補正分析の時間足とポイントを対応付けて保存する。
     *
     * 呼び出し元が開始した同一トランザクション内だけで実行する。
     *
     * @return 全時間足と全ポイントを保存できた場合true。
     */
    bool saveAnalysisChildren(
        const long fromAlertId,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[],
        ZigZagElliotAlertPointEntity &fromPoints[],
        ZigZagElliotAlertTimeFrameDao *fromTimeFrameDao,
        ZigZagElliotAlertPointDao *fromPointDao
    ) {
        int savedPointCount = 0;
        for (int i = 0; i < ArraySize(fromTimeFrames); i++) {
            fromTimeFrames[i].id = 0;
            fromTimeFrames[i].alertId = fromAlertId;
            if (!fromTimeFrameDao.insert(fromTimeFrames[i])) {
                return false;
            }
            int savedTimeFramePointCount = 0;
            for (int j = 0; j < ArraySize(fromPoints); j++) {
                if (fromPoints[j].timeFrame != fromTimeFrames[i].timeFrame) {
                    continue;
                }
                fromPoints[j].id = 0;
                fromPoints[j].alertTimeFrameId = fromTimeFrames[i].id;
                if (!fromPointDao.insert(fromPoints[j])) {
                    return false;
                }
                savedPointCount++;
                savedTimeFramePointCount++;
            }
            if (savedTimeFramePointCount != fromTimeFrames[i].pointCount) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "timeframe point count is invalid. timeframe=%s saved=%d expected=%d",
                        fromTimeFrames[i].timeFrameText,
                        savedTimeFramePointCount,
                        fromTimeFrames[i].pointCount
                    )
                );
                return false;
            }
        }
        if (savedPointCount != ArraySize(fromPoints)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "point mapping is incomplete. saved=%d expected=%d",
                    savedPointCount,
                    ArraySize(fromPoints)
                )
            );
            return false;
        }
        return true;
    }

    /**
     * 保存失敗後に補正側の採番を未保存へ戻す。
     */
    void clearCorrectionIds(
        ZigZagElliotAlertCorrectionEntity &fromCorrection,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[],
        ZigZagElliotAlertPointEntity &fromPoints[]
    ) {
        fromCorrection.alertId = 0;
        for (int i = 0; i < ArraySize(fromTimeFrames); i++) {
            fromTimeFrames[i].id = 0;
            fromTimeFrames[i].alertId = 0;
        }
        for (int i = 0; i < ArraySize(fromPoints); i++) {
            fromPoints[i].id = 0;
            fromPoints[i].alertTimeFrameId = 0;
        }
    }

    /**
     * 補正比較情報用DAOがすべて設定されているか確認する。
     */
    bool isCorrectionReady() {
        return this.correctionDao != NULL && this.correctedTimeFrameDao != NULL
            && this.correctedPointDao != NULL;
    }

    /**
     * 補正比較情報のNULL文字列を保存用の空文字列へ正規化する。
     */
    void normalizeCorrectionTextValues(ZigZagElliotAlertCorrectionEntity &fromCorrection) {
        fromCorrection.correctionStatus = this.normalizeText(fromCorrection.correctionStatus);
        fromCorrection.originalDirection = this.normalizeText(fromCorrection.originalDirection);
        fromCorrection.correctedDirection = this.normalizeText(fromCorrection.correctedDirection);
        fromCorrection.selectedAnalysis = this.normalizeText(fromCorrection.selectedAnalysis);
        fromCorrection.selectedAlertText = this.normalizeText(fromCorrection.selectedAlertText);
        fromCorrection.selectedCurrentElliotLabel = this.normalizeText(fromCorrection.selectedCurrentElliotLabel);
        fromCorrection.selectedWaveSummaryText = this.normalizeText(fromCorrection.selectedWaveSummaryText);
        fromCorrection.originalAnalysisText = this.normalizeText(fromCorrection.originalAnalysisText);
        fromCorrection.correctedAnalysisText = this.normalizeText(fromCorrection.correctedAnalysisText);
        fromCorrection.correctedElliotCsvText = this.normalizeText(fromCorrection.correctedElliotCsvText);
        fromCorrection.comparisonHash = this.normalizeText(fromCorrection.comparisonHash);
        fromCorrection.createdAtText = this.normalizeText(fromCorrection.createdAtText);
    }

    /**
     * 補正比較値と元アラート、および採用分析の対応を検証する。
     *
     * 旧3引数APIには適用せず、新規の比較情報付き保存を検証する。
     *
     * @return 同一判定の元分析と採用分析として整合する場合true。
     */
    bool isCorrectionSnapshotValid(
        ZigZagElliotAlertEntity &fromAlert,
        ZigZagElliotAlertTimeFrameEntity &fromOriginalTimeFrames[],
        ZigZagElliotAlertPointEntity &fromOriginalPoints[],
        ZigZagElliotAlertCorrectionEntity &fromCorrection,
        ZigZagElliotAlertTimeFrameEntity &fromCorrectedTimeFrames[],
        ZigZagElliotAlertPointEntity &fromCorrectedPoints[]
    ) {
        if (!MathIsValidNumber(fromCorrection.referencePrice)
                || !MathIsValidNumber(fromCorrection.selectedStopLoss)
                || !MathIsValidNumber(fromCorrection.selectedRiskPips)
                || !MathIsValidNumber(fromCorrection.originalLc0)
                || !MathIsValidNumber(fromCorrection.originalLc5)
                || !MathIsValidNumber(fromCorrection.originalLc10)
                || !MathIsValidNumber(fromCorrection.originalLc15)
                || !MathIsValidNumber(fromCorrection.originalLossCutDiffPips)
                || !MathIsValidNumber(fromCorrection.originalLossCutDiffJpy)
                || !MathIsValidNumber(fromCorrection.correctedLc0)
                || !MathIsValidNumber(fromCorrection.correctedLc5)
                || !MathIsValidNumber(fromCorrection.correctedLc10)
                || !MathIsValidNumber(fromCorrection.correctedLc15)
                || !MathIsValidNumber(fromCorrection.correctedLossCutDiffPips)
                || !MathIsValidNumber(fromCorrection.correctedLossCutDiffJpy)
                || !MathIsValidNumber(fromAlert.referencePrice)
                || !MathIsValidNumber(fromAlert.stopLoss)
                || !MathIsValidNumber(fromAlert.riskPips)) {
            return false;
        }
        if (fromCorrection.comparisonHash == "" || fromCorrection.originalAnalysisText == ""
                || fromCorrection.selectedAlertText == "" || fromCorrection.selectedWaveSummaryText == ""
                || fromCorrection.createdAt <= 0 || fromCorrection.createdAtText == ""
                || fromCorrection.referencePrice != fromAlert.referencePrice
                || fromCorrection.originalLc5 != fromAlert.stopLoss
                || fromCorrection.selectedCurrentElliotLabel != fromAlert.currentElliotLabel
                || fromCorrection.selectedRiskPips < 0.0 || fromAlert.riskPips < 0.0
                || (fromAlert.side != "BUY" && fromAlert.side != "SELL")) {
            return false;
        }
        int expectedOriginalAvailable = 0;
        if (fromAlert.referencePrice > 0.0 && fromAlert.stopLoss > 0.0) {
            expectedOriginalAvailable = 1;
        }
        int expectedSelectedAvailable = 0;
        if (fromCorrection.referencePrice > 0.0 && fromCorrection.selectedStopLoss > 0.0) {
            expectedSelectedAvailable = 1;
        }
        if (fromAlert.isStopLossAvailable != expectedOriginalAvailable
                || fromCorrection.isSelectedStopLossAvailable != expectedSelectedAvailable
                || (expectedSelectedAvailable == 0 && fromCorrection.selectedRiskPips != 0.0)) {
            return false;
        }
        if (!this.isAnalysisStructureValid(
                fromOriginalTimeFrames, fromOriginalPoints, fromAlert.timeFrame,
                fromAlert.signalReferencePointTime, fromCorrection.originalLc0)) {
            return false;
        }
        int currentIndex = this.findTimeFrameIndex(fromOriginalTimeFrames, fromAlert.timeFrame);
        if (currentIndex < 0 || fromOriginalTimeFrames[currentIndex].buySellLabel != fromAlert.side) {
            return false;
        }
        if (fromCorrection.correctionStatus == "NONE") {
            return fromCorrection.correctionTimeFrame == 0
                && fromCorrection.originalDirection == "" && fromCorrection.correctedDirection == ""
                && fromCorrection.selectedAnalysis == "ORIGINAL"
                && fromCorrection.selectedStopLoss == fromCorrection.originalLc5
                && fromCorrection.selectedRiskPips == fromAlert.riskPips
                && fromCorrection.selectedCurrentElliotLabel
                    == fromOriginalTimeFrames[currentIndex].latestElliotLabel
                && fromCorrection.correctedLc0 == 0.0 && fromCorrection.correctedLc5 == 0.0
                && fromCorrection.correctedLc10 == 0.0 && fromCorrection.correctedLc15 == 0.0
                && fromCorrection.correctedLossCutDiffPips == 0.0
                && fromCorrection.correctedLossCutDiffJpy == 0.0
                && fromCorrection.correctedReferencePointTime == 0
                && fromCorrection.correctedAnalysisText == ""
                && fromCorrection.correctedElliotCsvText == ""
                && ArraySize(fromCorrectedTimeFrames) == 0 && ArraySize(fromCorrectedPoints) == 0;
        }
        if (fromCorrection.correctionStatus != "APPLIED" || fromAlert.timeFrame != PERIOD_M5
                || fromCorrection.selectedAnalysis != "CORRECTED"
                || (fromCorrection.correctionTimeFrame != PERIOD_H4
                    && fromCorrection.correctionTimeFrame != PERIOD_H1)
                || fromCorrection.selectedStopLoss != fromCorrection.correctedLc5
                || fromCorrection.correctedReferencePointTime <= 0
                || fromCorrection.correctedAnalysisText == ""
                || fromCorrection.correctedElliotCsvText == ""
                || !this.isAnalysisStructureValid(
                    fromCorrectedTimeFrames, fromCorrectedPoints, PERIOD_M5,
                    fromCorrection.correctedReferencePointTime, fromCorrection.correctedLc0)) {
            return false;
        }
        return this.isAppliedDirectionValid(
            fromOriginalTimeFrames, fromCorrectedTimeFrames, fromCorrection
        );
    }

    /**
     * 時間足の一意性と最新ポイント・SL基準ポイントの対応を確認する。
     *
     * @return 全ポイントが過不足なく親時間足へ対応する場合true。
     */
    bool isAnalysisStructureValid(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[],
        ZigZagElliotAlertPointEntity &fromPoints[],
        const int fromCurrentTimeFrame,
        const datetime fromReferenceTime,
        const double fromReferenceRate
    ) {
        int timeFrameCount = ArraySize(fromTimeFrames);
        int totalPointCount = ArraySize(fromPoints);
        if (timeFrameCount <= 0 || totalPointCount <= 0 || fromReferenceTime < 0) {
            return false;
        }
        int mappedPointCount = 0;
        int currentCount = 0;
        int referenceCount = 0;
        for (int i = 0; i < timeFrameCount; i++) {
            if (fromTimeFrames[i].timeFrame <= 0 || fromTimeFrames[i].pointCount <= 0
                    || fromTimeFrames[i].timeFrameOrder < 0
                    || fromTimeFrames[i].timeFrameOrder >= timeFrameCount
                    || (fromTimeFrames[i].isBuy != 0 && fromTimeFrames[i].isBuy != 1)) {
                return false;
            }
            string expectedDirection = "SELL";
            if (fromTimeFrames[i].isBuy == 1) {
                expectedDirection = "BUY";
            }
            int expectedCurrent = 0;
            if (fromTimeFrames[i].timeFrame == fromCurrentTimeFrame) {
                expectedCurrent = 1;
                currentCount++;
            }
            if (fromTimeFrames[i].buySellLabel != expectedDirection
                    || fromTimeFrames[i].isCurrentTimeFrame != expectedCurrent) {
                return false;
            }
            for (int j = 0; j < i; j++) {
                if (fromTimeFrames[j].timeFrame == fromTimeFrames[i].timeFrame
                        || fromTimeFrames[j].timeFrameOrder == fromTimeFrames[i].timeFrameOrder) {
                    return false;
                }
            }
            int pointCount = 0;
            int latestCount = 0;
            for (int j = 0; j < totalPointCount; j++) {
                if (fromPoints[j].timeFrame != fromTimeFrames[i].timeFrame) {
                    continue;
                }
                pointCount++;
                mappedPointCount++;
                if (fromPoints[j].pointOrder < 0
                        || fromPoints[j].pointOrder >= fromTimeFrames[i].pointCount
                        || fromPoints[j].barTime <= 0 || !MathIsValidNumber(fromPoints[j].rate)
                        || (fromPoints[j].isLatest != 0 && fromPoints[j].isLatest != 1)
                        || (fromPoints[j].isSignalReference != 0 && fromPoints[j].isSignalReference != 1)) {
                    return false;
                }
                for (int k = 0; k < j; k++) {
                    if (fromPoints[k].timeFrame == fromPoints[j].timeFrame
                            && fromPoints[k].pointOrder == fromPoints[j].pointOrder) {
                        return false;
                    }
                }
                if (fromPoints[j].isLatest == 1) {
                    latestCount++;
                    if (fromPoints[j].pointOrder != fromTimeFrames[i].pointCount - 1
                            || fromPoints[j].elliotLabel != fromTimeFrames[i].latestElliotLabel
                            || fromPoints[j].elliotIndex != fromTimeFrames[i].latestElliotIndex
                            || fromPoints[j].subElliotLabel != fromTimeFrames[i].latestSubElliotLabel
                            || fromPoints[j].subElliotIndex != fromTimeFrames[i].latestSubElliotIndex) {
                        return false;
                    }
                }
                if (fromPoints[j].isSignalReference == 1) {
                    referenceCount++;
                    if (expectedCurrent != 1 || fromPoints[j].barTime != fromReferenceTime
                            || fromPoints[j].rate != fromReferenceRate) {
                        return false;
                    }
                }
            }
            if (pointCount != fromTimeFrames[i].pointCount || latestCount != 1) {
                return false;
            }
        }
        int expectedReferenceCount = 0;
        if (fromReferenceTime > 0) {
            expectedReferenceCount = 1;
        }
        return mappedPointCount == totalPointCount && currentCount == 1
            && referenceCount == expectedReferenceCount;
    }

    /**
     * 補正採用時の7足構成とH4またはH1だけの方向変更を確認する。
     */
    bool isAppliedDirectionValid(
        ZigZagElliotAlertTimeFrameEntity &fromOriginal[],
        ZigZagElliotAlertTimeFrameEntity &fromCorrected[],
        ZigZagElliotAlertCorrectionEntity &fromCorrection
    ) {
        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
        };
        if (ArraySize(fromOriginal) != ArraySize(timeFrames)
                || ArraySize(fromCorrected) != ArraySize(timeFrames)) {
            return false;
        }
        int currentIsBuy = fromOriginal[6].isBuy;
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            if (fromOriginal[i].timeFrame != timeFrames[i] || fromCorrected[i].timeFrame != timeFrames[i]
                    || fromOriginal[i].timeFrameOrder != i || fromCorrected[i].timeFrameOrder != i) {
                return false;
            }
            if (timeFrames[i] == fromCorrection.correctionTimeFrame) {
                if (fromOriginal[i].isBuy == currentIsBuy || fromCorrected[i].isBuy != currentIsBuy
                        || fromCorrection.originalDirection != fromOriginal[i].buySellLabel
                        || fromCorrection.correctedDirection != fromCorrected[i].buySellLabel) {
                    return false;
                }
            } else if (fromOriginal[i].isBuy != fromCorrected[i].isBuy) {
                return false;
            }
            if ((timeFrames[i] == PERIOD_H4 || timeFrames[i] == PERIOD_H1)
                    && timeFrames[i] != fromCorrection.correctionTimeFrame
                    && fromOriginal[i].isBuy != currentIsBuy) {
                return false;
            }
        }
        return fromCorrection.selectedCurrentElliotLabel == fromCorrected[6].latestElliotLabel;
    }

    /**
     * 時間足一覧から対応位置を取得する。
     *
     * @return 対応位置。存在しない場合は-1。
     */
    int findTimeFrameIndex(
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[],
        const int fromTimeFrame
    ) {
        for (int i = 0; i < ArraySize(fromTimeFrames); i++) {
            if (fromTimeFrames[i].timeFrame == fromTimeFrame) {
                return i;
            }
        }
        return -1;
    }

    /**
     * 文字列が64桁の小文字16進SHA-256か判定する。
     *
     * @param fromHash 判定対象Hash
     * @return SHA-256形式の場合true
     */
    bool isLowerHexSha256(const string fromHash) {
        if (StringLen(fromHash) != 64) {
            return false;
        }

        for (int i = 0; i < StringLen(fromHash); i++) {
            ushort characterCode = StringGetCharacter(fromHash, i);
            bool isDigit = characterCode >= '0' && characterCode <= '9';
            bool isLowerHexLetter =
                characterCode >= 'a' && characterCode <= 'f';

            if (!isDigit && !isLowerHexLetter) {
                return false;
            }
        }

        return true;
    }

    /**
     * 実行情報のNULL文字列をDB保存用の空文字列へ変換する。
     *
     * @param fromRunEntity 実行情報
     */
    void normalizeRunTextValues(
        ZigZagElliotAlertRunEntity &fromRunEntity
    ) {
        fromRunEntity.runUid = this.normalizeText(fromRunEntity.runUid);
        fromRunEntity.sourceMode = this.normalizeText(
            fromRunEntity.sourceMode
        );
        fromRunEntity.source = this.normalizeText(fromRunEntity.source);
        fromRunEntity.programName = this.normalizeText(
            fromRunEntity.programName
        );
        fromRunEntity.programVersion = this.normalizeText(
            fromRunEntity.programVersion
        );
        fromRunEntity.strategy = this.normalizeText(fromRunEntity.strategy);
        fromRunEntity.strategyVersion = this.normalizeText(
            fromRunEntity.strategyVersion
        );
        fromRunEntity.analysisVersion = this.normalizeText(
            fromRunEntity.analysisVersion
        );
        fromRunEntity.analysisInputText = this.normalizeText(
            fromRunEntity.analysisInputText
        );
        fromRunEntity.analysisInputHash = this.normalizeText(
            fromRunEntity.analysisInputHash
        );
        fromRunEntity.sourceServer = this.normalizeText(
            fromRunEntity.sourceServer
        );
        fromRunEntity.testerModel = this.normalizeText(
            fromRunEntity.testerModel
        );
        fromRunEntity.inputText = this.normalizeText(fromRunEntity.inputText);
        fromRunEntity.inputHash = this.normalizeText(fromRunEntity.inputHash);
        fromRunEntity.startedAtText = this.normalizeText(
            fromRunEntity.startedAtText
        );
        fromRunEntity.marketStartedAtText = this.normalizeText(
            fromRunEntity.marketStartedAtText
        );
        fromRunEntity.createdAtText = this.normalizeText(
            fromRunEntity.createdAtText
        );
        fromRunEntity.status = this.normalizeText(fromRunEntity.status);

        if (fromRunEntity.status == "") {
            fromRunEntity.status = "LEGACY";
        }

        fromRunEntity.errorText = this.normalizeText(fromRunEntity.errorText);
    }

    /**
     * アラートスナップショットのNULL文字列をDB保存用の空文字列へ変換する。
     *
     * @param fromAlertEntity アラート本体
     * @param fromTimeFrameEntities 時間足別分析一覧
     * @param fromPointEntities ポイント一覧
     */
    void normalizeSnapshotTextValues(
        ZigZagElliotAlertEntity &fromAlertEntity,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotAlertPointEntity &fromPointEntities[]
    ) {
        this.normalizeAlertTextValues(fromAlertEntity);

        for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
            this.normalizeTimeFrameTextValues(fromTimeFrameEntities[i]);
        }

        for (int i = 0; i < ArraySize(fromPointEntities); i++) {
            this.normalizePointTextValues(fromPointEntities[i]);
        }
    }

    /**
     * アラート本体のNULL文字列を空文字列へ変換する。
     *
     * @param fromEntity アラート本体
     */
    void normalizeAlertTextValues(ZigZagElliotAlertEntity &fromEntity) {
        fromEntity.eventUid = this.normalizeText(fromEntity.eventUid);
        fromEntity.marketSignalKey = this.normalizeText(
            fromEntity.marketSignalKey
        );
        fromEntity.snapshotHash = this.normalizeText(fromEntity.snapshotHash);
        fromEntity.serverTimeText = this.normalizeText(
            fromEntity.serverTimeText
        );
        fromEntity.jstTimeText = this.normalizeText(fromEntity.jstTimeText);
        fromEntity.currentBarTimeText = this.normalizeText(
            fromEntity.currentBarTimeText
        );
        fromEntity.signalReferencePointTimeText = this.normalizeText(
            fromEntity.signalReferencePointTimeText
        );
        fromEntity.symbolName = this.normalizeText(fromEntity.symbolName);
        fromEntity.timeFrameText = this.normalizeText(
            fromEntity.timeFrameText
        );
        fromEntity.magicNumber = this.normalizeText(fromEntity.magicNumber);
        fromEntity.strategy = this.normalizeText(fromEntity.strategy);
        fromEntity.side = this.normalizeText(fromEntity.side);
        fromEntity.entryResult = this.normalizeText(fromEntity.entryResult);
        fromEntity.currentElliotLabel = this.normalizeText(
            fromEntity.currentElliotLabel
        );
        fromEntity.w1ConfirmationMode = this.normalizeText(
            fromEntity.w1ConfirmationMode
        );
        fromEntity.w1ConfirmationState = this.normalizeText(
            fromEntity.w1ConfirmationState
        );
        fromEntity.w1Ema200Direction = this.normalizeText(
            fromEntity.w1Ema200Direction
        );
        fromEntity.h1DirectionAlignmentMode = this.normalizeText(
            fromEntity.h1DirectionAlignmentMode
        );
        fromEntity.h1DirectionAlignmentState = this.normalizeText(
            fromEntity.h1DirectionAlignmentState
        );
        fromEntity.h1DirectionAlignmentDirection = this.normalizeText(
            fromEntity.h1DirectionAlignmentDirection
        );
        fromEntity.currencyStrengthCalculationVersion = this.normalizeText(
            fromEntity.currencyStrengthCalculationVersion
        );
        fromEntity.currencyStrengthSourceMode = this.normalizeText(
            fromEntity.currencyStrengthSourceMode
        );
        fromEntity.baseCurrency = this.normalizeText(fromEntity.baseCurrency);
        fromEntity.quoteCurrency = this.normalizeText(
            fromEntity.quoteCurrency
        );
        fromEntity.h1StructureRank = this.normalizeText(
            fromEntity.h1StructureRank
        );
        fromEntity.alertTitle = this.normalizeText(fromEntity.alertTitle);
        fromEntity.alertText = this.normalizeText(fromEntity.alertText);
        fromEntity.waveSummaryText = this.normalizeText(
            fromEntity.waveSummaryText
        );
        fromEntity.elliotCsvText = this.normalizeText(
            fromEntity.elliotCsvText
        );
        fromEntity.createdAtText = this.normalizeText(
            fromEntity.createdAtText
        );
    }

    /**
     * 時間足別分析のNULL文字列を空文字列へ変換する。
     *
     * @param fromEntity 時間足別分析
     */
    void normalizeTimeFrameTextValues(
        ZigZagElliotAlertTimeFrameEntity &fromEntity
    ) {
        fromEntity.timeFrameText = this.normalizeText(
            fromEntity.timeFrameText
        );
        fromEntity.buySellLabel = this.normalizeText(
            fromEntity.buySellLabel
        );
        fromEntity.waveTrendLabel = this.normalizeText(
            fromEntity.waveTrendLabel
        );
        fromEntity.previousLastElliotLabel = this.normalizeText(
            fromEntity.previousLastElliotLabel
        );
        fromEntity.latestElliotLabel = this.normalizeText(
            fromEntity.latestElliotLabel
        );
        fromEntity.latestSubElliotLabel = this.normalizeText(
            fromEntity.latestSubElliotLabel
        );
        fromEntity.stochasticMainOrderText = this.normalizeText(
            fromEntity.stochasticMainOrderText
        );
        fromEntity.stochasticMainDirectionText = this.normalizeText(
            fromEntity.stochasticMainDirectionText
        );
        fromEntity.rawCsvText = this.normalizeText(fromEntity.rawCsvText);
        fromEntity.createdAtText = this.normalizeText(
            fromEntity.createdAtText
        );
    }

    /**
     * ポイントのNULL文字列を空文字列へ変換する。
     *
     * @param fromEntity ポイント
     */
    void normalizePointTextValues(
        ZigZagElliotAlertPointEntity &fromEntity
    ) {
        fromEntity.barTimeText = this.normalizeText(fromEntity.barTimeText);
        fromEntity.barTimeNextText = this.normalizeText(
            fromEntity.barTimeNextText
        );
        fromEntity.fiboDepthZoneLabel = this.normalizeText(
            fromEntity.fiboDepthZoneLabel
        );
        fromEntity.elliotLabel = this.normalizeText(fromEntity.elliotLabel);
        fromEntity.subElliotLabel = this.normalizeText(
            fromEntity.subElliotLabel
        );
        fromEntity.orgElliotLabel = this.normalizeText(
            fromEntity.orgElliotLabel
        );
        fromEntity.createdAtText = this.normalizeText(
            fromEntity.createdAtText
        );
    }

    /**
     * NULL文字列をDB保存用の空文字列へ変換する。
     *
     * @param fromText 対象文字列
     * @return NULLの場合は空文字列、それ以外は元の文字列
     */
    string normalizeText(const string fromText) {
        if (fromText == NULL) {
            return "";
        }

        return fromText;
    }

    /**
     * 外部キー制約を有効化して設定値を確認する。
     *
     * @return 有効化に成功した場合true
     */
    bool enableForeignKeys() {
        ResetLastError();

        if (!DatabaseExecute(this.databaseHandle, "PRAGMA foreign_keys = ON")) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseExecute failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA foreign_keys"
        );

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabasePrepare failed. error=%d", GetLastError())
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat("DatabaseRead failed. error=%d", readErrorCode)
            );

            return false;
        }

        int isEnabled = 0;
        ResetLastError();

        if (!DatabaseColumnInteger(requestHandle, 0, isEnabled)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnInteger failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        if (isEnabled != 1) {
            this.logger.error(__FUNCTION__, "foreign key setting is disabled.");

            return false;
        }

        return true;
    }

    /**
     * 保存対象スナップショットの必須値を確認する。
     *
     * @param fromAlertEntity アラート本体
     * @param fromTimeFrameEntities 時間足別分析一覧
     * @param fromPointEntities ポイント一覧
     * @return 保存可能な場合true
     */
    bool isSnapshotValid(
        ZigZagElliotAlertEntity &fromAlertEntity,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotAlertPointEntity &fromPointEntities[]
    ) {
        if (fromAlertEntity.runId <= 0
                || fromAlertEntity.eventUid == ""
                || fromAlertEntity.marketSignalKey == ""
                || fromAlertEntity.symbolName == ""
                || fromAlertEntity.currentBarTime <= 0
                || fromAlertEntity.strategy == ""
                || fromAlertEntity.side == ""
                || fromAlertEntity.w1ConfirmationMode == ""
                || fromAlertEntity.w1ConfirmationState == ""
                || fromAlertEntity.w1Ema200Direction == ""
                || fromAlertEntity.h1DirectionAlignmentMode == ""
                || fromAlertEntity.h1DirectionAlignmentState == ""
                || fromAlertEntity.h1DirectionAlignmentDirection == ""
                || fromAlertEntity.snapshotHash == "") {
            this.logger.error(__FUNCTION__, "alert required value is invalid.");

            return false;
        }

        if (ArraySize(fromTimeFrameEntities) <= 0
                || ArraySize(fromPointEntities) <= 0) {
            this.logger.error(__FUNCTION__, "snapshot child array is empty.");

            return false;
        }

        return true;
    }

    /**
     * トランザクションをコミットする。
     *
     * @param fromMethodName 呼び出し元メソッド名
     * @return 成功した場合true
     */
    bool commitTransaction(const string fromMethodName) {
        ResetLastError();

        if (!DatabaseTransactionCommit(this.databaseHandle)) {
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseTransactionCommit failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        return true;
    }

    /**
     * トランザクションをロールバックする。
     *
     * @param fromMethodName 呼び出し元メソッド名
     */
    void rollbackTransaction(const string fromMethodName) {
        ResetLastError();

        if (!DatabaseTransactionRollback(this.databaseHandle)) {
            this.logger.error(
                fromMethodName,
                StringFormat(
                    "DatabaseTransactionRollback failed. error=%d",
                    GetLastError()
                )
            );
        }
    }

    /**
     * ROLLBACK後に親子IDを未保存状態へ戻す。
     *
     * @param fromAlertEntity アラート本体
     * @param fromTimeFrameEntities 時間足別分析一覧
     * @param fromPointEntities ポイント一覧
     */
    void clearSnapshotIds(
        ZigZagElliotAlertEntity &fromAlertEntity,
        ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
        ZigZagElliotAlertPointEntity &fromPointEntities[]
    ) {
        fromAlertEntity.id = 0;

        for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
            fromTimeFrameEntities[i].id = 0;
            fromTimeFrameEntities[i].alertId = 0;
        }

        for (int i = 0; i < ArraySize(fromPointEntities); i++) {
            fromPointEntities[i].id = 0;
            fromPointEntities[i].alertTimeFrameId = 0;
        }
    }

    /**
     * データベースとDAOが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名
     * @return 利用可能な場合true
     */
    bool isReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE
                && this.alertDao != NULL
                && this.pointDao != NULL
                && this.runDao != NULL
                && this.timeFrameDao != NULL) {
            return true;
        }

        this.logger.error(fromMethodName, "database service is not ready.");

        return false;
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_ALERT_PERSISTENCE_MQH
