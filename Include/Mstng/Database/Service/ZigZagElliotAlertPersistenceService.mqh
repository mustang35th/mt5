//+------------------------------------------------------------------+
//|                          ZigZagElliotAlertPersistenceService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ZIGZAG_ELLIOT_ALERT_PERSISTENCE_MQH
#define MSTNG_ZIGZAG_ELLIOT_ALERT_PERSISTENCE_MQH

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
     */
    ZigZagElliotAlertPersistenceService(
        const int fromDatabaseHandle,
        ZigZagElliotAlertDao *fromAlertDao,
        ZigZagElliotAlertPointDao *fromPointDao,
        ZigZagElliotAlertRunDao *fromRunDao,
        ZigZagElliotAlertTimeFrameDao *fromTimeFrameDao
    ) {
        this.databaseHandle = fromDatabaseHandle;
        this.alertDao = fromAlertDao;
        this.pointDao = fromPointDao;
        this.runDao = fromRunDao;
        this.timeFrameDao = fromTimeFrameDao;
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

        return this.pointDao.createTable();
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
        int savedPointCount = 0;

        for (int i = 0; isSaved && i < timeFrameCount; i++) {
            fromTimeFrameEntities[i].id = 0;
            fromTimeFrameEntities[i].alertId = fromAlertEntity.id;
            isSaved = this.timeFrameDao.insert(fromTimeFrameEntities[i]);
            int savedTimeFramePointCount = 0;

            for (int j = 0; isSaved && j < pointCount; j++) {
                if (fromPointEntities[j].timeFrame
                        != fromTimeFrameEntities[i].timeFrame) {
                    continue;
                }

                fromPointEntities[j].id = 0;
                fromPointEntities[j].alertTimeFrameId =
                    fromTimeFrameEntities[i].id;
                isSaved = this.pointDao.insert(fromPointEntities[j]);

                if (isSaved) {
                    savedPointCount++;
                    savedTimeFramePointCount++;
                }
            }

            if (isSaved
                    && savedTimeFramePointCount
                        != fromTimeFrameEntities[i].pointCount) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "timeframe point count is invalid. timeframe=%s saved=%d expected=%d",
                        fromTimeFrameEntities[i].timeFrameText,
                        savedTimeFramePointCount,
                        fromTimeFrameEntities[i].pointCount
                    )
                );
                isSaved = false;
            }
        }

        if (isSaved && savedPointCount != pointCount) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "point mapping is incomplete. saved=%d expected=%d",
                    savedPointCount,
                    pointCount
                )
            );
            isSaved = false;
        }

        if (!isSaved) {
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromAlertEntity,
                fromTimeFrameEntities,
                fromPointEntities
            );

            return false;
        }

        if (!this.commitTransaction(__FUNCTION__)) {
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromAlertEntity,
                fromTimeFrameEntities,
                fromPointEntities
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
    /** ロガー。 */
    Logger logger;

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
