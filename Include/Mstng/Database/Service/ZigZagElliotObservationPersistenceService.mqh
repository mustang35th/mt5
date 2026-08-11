//+------------------------------------------------------------------+
//|       ZigZagElliotObservationPersistenceService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_SERVICE_ZZ_ELLIOT_OBSERVATION_MQH
#define MSTNG_DATABASE_SERVICE_ZZ_ELLIOT_OBSERVATION_MQH

#include <Mstng\Database\Dao\ZigZagElliotObservationDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationTimeFrameDao.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationTimeFrameEntity.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>

/**
 * ZigZagElliot観測本体と時間足別分析を一括保存するサービス。
 */
class ZigZagElliotObservationPersistenceService {
public:
    /**
     * データベースハンドルとDAOを指定して初期化する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromObservationDao 観測本体DAO。
     * @param fromTimeFrameDao 時間足別観測DAO。
     */
    ZigZagElliotObservationPersistenceService(
        const int fromDatabaseHandle,
        ZigZagElliotObservationDao *fromObservationDao,
        ZigZagElliotObservationTimeFrameDao *fromTimeFrameDao
    ) {
        this.databaseHandle = fromDatabaseHandle;
        this.observationDao = fromObservationDao;
        this.timeFrameDao = fromTimeFrameDao;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 観測関連テーブルと外部キー制約を準備する。
     *
     * @return 準備に成功した場合true。
     */
    bool createTables() {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        if (!this.setBusyTimeout(60000)) {
            this.setBusyTimeout(5000);

            return false;
        }

        bool isSucceeded = this.createTablesWithExtendedTimeout();
        bool isTimeoutRestored = this.setBusyTimeout(5000);

        if (!isTimeoutRestored) {
            return false;
        }

        return isSucceeded;
    }

    /**
     * 観測本体と時間足別分析を1トランザクションで保存する。
     *
     * 自然キー重複時は最初に保存したスナップショットを保持する。
     *
     * @param fromObservationEntity 観測本体。
     * @param fromTimeFrameEntities 時間足別分析一覧。
     * @return 新規保存または既存行取得に成功した場合true。
     */
    bool saveSnapshot(
        ZigZagElliotObservationEntity &fromObservationEntity,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
    ) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        this.normalizeSnapshotTextValues(
            fromObservationEntity,
            fromTimeFrameEntities
        );

        if (!this.isSnapshotValid(
                fromObservationEntity,
                fromTimeFrameEntities
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

        bool isInserted = false;
        bool isSaved = this.observationDao.insertOnConflictDoNothing(
            fromObservationEntity,
            isInserted
        );

        if (!isSaved) {
            this.rollbackAndClear(
                __FUNCTION__,
                fromObservationEntity,
                fromTimeFrameEntities
            );

            return false;
        }

        if (!isInserted) {
            long existingObservationId = 0;
            long existingRunId = 0;
            string existingSnapshotHash = "";
            isSaved = this.observationDao.findByNaturalKey(
                fromObservationEntity,
                existingObservationId,
                existingRunId,
                existingSnapshotHash
            );

            if (!isSaved || existingObservationId <= 0 || existingRunId <= 0) {
                this.logger.error(
                    __FUNCTION__,
                    "conflicted observation was not found."
                );
                this.rollbackAndClear(
                    __FUNCTION__,
                    fromObservationEntity,
                    fromTimeFrameEntities
                );

                return false;
            }

            fromObservationEntity.id = existingObservationId;
            fromObservationEntity.runId = existingRunId;

            if (existingSnapshotHash != fromObservationEntity.snapshotHash) {
                this.logger.info(
                    __FUNCTION__,
                    StringFormat(
                        "Existing observation snapshot is retained. observationId=%I64d symbol=%s anchorBarTime=%s existingHash=%s incomingHash=%s",
                        existingObservationId,
                        fromObservationEntity.symbolName,
                        fromObservationEntity.anchorBarTimeText,
                        existingSnapshotHash,
                        fromObservationEntity.snapshotHash
                    )
                );
            }

            if (!this.commitTransaction(__FUNCTION__)) {
                this.rollbackAndClear(
                    __FUNCTION__,
                    fromObservationEntity,
                    fromTimeFrameEntities
                );

                return false;
            }

            return true;
        }

        int timeFrameCount = ArraySize(fromTimeFrameEntities);

        for (int i = 0; isSaved && i < timeFrameCount; i++) {
            fromTimeFrameEntities[i].id = 0;
            fromTimeFrameEntities[i].observationId = fromObservationEntity.id;
            isSaved = this.timeFrameDao.insert(fromTimeFrameEntities[i]);
        }

        if (!isSaved) {
            this.rollbackAndClear(
                __FUNCTION__,
                fromObservationEntity,
                fromTimeFrameEntities
            );

            return false;
        }

        if (!this.commitTransaction(__FUNCTION__)) {
            this.rollbackAndClear(
                __FUNCTION__,
                fromObservationEntity,
                fromTimeFrameEntities
            );

            return false;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "Observation snapshot saved. observationId=%I64d symbol=%s anchorBarTime=%s timeFrames=%d",
                fromObservationEntity.id,
                fromObservationEntity.symbolName,
                fromObservationEntity.anchorBarTimeText,
                timeFrameCount
            )
        );

        return true;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** 観測本体DAO。 */
    ZigZagElliotObservationDao *observationDao;

    /** 時間足別観測DAO。 */
    ZigZagElliotObservationTimeFrameDao *timeFrameDao;

    /** ロガー。 */
    Logger logger;

    /**
     * 延長済みbusy_timeoutの範囲で親子テーブルと全インデックスを準備する。
     *
     * @return 準備に成功した場合true。
     */
    bool createTablesWithExtendedTimeout() {
        if (!this.enableForeignKeys()) {
            return false;
        }

        if (!this.observationDao.createTable()) {
            return false;
        }

        return this.timeFrameDao.createTable();
    }

    /**
     * SQLite接続のbusy_timeoutを設定して値を確認する。
     *
     * @param fromTimeoutMilliseconds タイムアウト時間（ミリ秒）。
     * @return 設定値が一致した場合true。
     */
    bool setBusyTimeout(const int fromTimeoutMilliseconds) {
        string sql = "PRAGMA busy_timeout = ";
        sql += IntegerToString(fromTimeoutMilliseconds);
        ResetLastError();

        if (!DatabaseExecute(this.databaseHandle, sql)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseExecute failed. timeout=%d error=%d",
                    fromTimeoutMilliseconds,
                    GetLastError()
                )
            );

            return false;
        }

        long actualTimeout = 0;

        if (!this.readBusyTimeout(actualTimeout)) {
            return false;
        }

        if (actualTimeout == fromTimeoutMilliseconds) {
            return true;
        }

        this.logger.error(
            __FUNCTION__,
            StringFormat(
                "busy_timeout verification failed. actual=%I64d expected=%d",
                actualTimeout,
                fromTimeoutMilliseconds
            )
        );

        return false;
    }

    /**
     * SQLite接続のbusy_timeoutを取得する。
     *
     * @param fromTimeoutMilliseconds 取得値の格納先。
     * @return 取得に成功した場合true。
     */
    bool readBusyTimeout(long &fromTimeoutMilliseconds) {
        fromTimeoutMilliseconds = 0;
        ResetLastError();
        int requestHandle = DatabasePrepare(
            this.databaseHandle,
            "PRAGMA busy_timeout"
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

        ResetLastError();

        if (!DatabaseColumnLong(
                requestHandle,
                0,
                fromTimeoutMilliseconds
            )) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumnLong failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        DatabaseFinalize(requestHandle);

        return true;
    }

    /**
     * 観測スナップショットのNULL文字列を空文字列へ変換する。
     *
     * @param fromObservationEntity 観測本体。
     * @param fromTimeFrameEntities 時間足別分析一覧。
     */
    void normalizeSnapshotTextValues(
        ZigZagElliotObservationEntity &fromObservationEntity,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
    ) {
        this.normalizeObservationTextValues(fromObservationEntity);

        for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
            this.normalizeTimeFrameTextValues(fromTimeFrameEntities[i]);
        }
    }

    /**
     * 観測本体のNULL文字列を空文字列へ変換する。
     *
     * @param fromEntity 観測本体。
     */
    void normalizeObservationTextValues(
        ZigZagElliotObservationEntity &fromEntity
    ) {
        fromEntity.sourceMode = this.normalizeText(fromEntity.sourceMode);
        fromEntity.sourceServer = this.normalizeText(fromEntity.sourceServer);
        fromEntity.symbolName = this.normalizeText(fromEntity.symbolName);
        fromEntity.anchorTimeFrameText = this.normalizeText(
            fromEntity.anchorTimeFrameText
        );
        fromEntity.anchorBarTimeText = this.normalizeText(
            fromEntity.anchorBarTimeText
        );
        fromEntity.anchorJstTimeText = this.normalizeText(
            fromEntity.anchorJstTimeText
        );
        fromEntity.capturePhase = this.normalizeText(fromEntity.capturePhase);
        fromEntity.analysisVersion = this.normalizeText(
            fromEntity.analysisVersion
        );
        fromEntity.analysisInputHash = this.normalizeText(
            fromEntity.analysisInputHash
        );
        fromEntity.snapshotHash = this.normalizeText(fromEntity.snapshotHash);
        fromEntity.createdAtText = this.normalizeText(fromEntity.createdAtText);
    }

    /**
     * 時間足別分析のNULL文字列を空文字列へ変換する。
     *
     * @param fromEntity 時間足別分析。
     */
    void normalizeTimeFrameTextValues(
        ZigZagElliotObservationTimeFrameEntity &fromEntity
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
        fromEntity.latestPointTimeText = this.normalizeText(
            fromEntity.latestPointTimeText
        );
        fromEntity.latestPointJstTimeText = this.normalizeText(
            fromEntity.latestPointJstTimeText
        );
        fromEntity.stochasticMainOrderText = this.normalizeText(
            fromEntity.stochasticMainOrderText
        );
        fromEntity.stochasticMainDirectionText = this.normalizeText(
            fromEntity.stochasticMainDirectionText
        );
        fromEntity.createdAtText = this.normalizeText(
            fromEntity.createdAtText
        );
    }

    /**
     * 保存対象スナップショットの必須値と固定5時間足を確認する。
     *
     * @param fromObservationEntity 観測本体。
     * @param fromTimeFrameEntities 時間足別分析一覧。
     * @return 保存可能な場合true。
     */
    bool isSnapshotValid(
        ZigZagElliotObservationEntity &fromObservationEntity,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
    ) {
        if (fromObservationEntity.runId <= 0
                || (fromObservationEntity.sourceMode != "LIVE"
                    && fromObservationEntity.sourceMode != "TESTER")
                || fromObservationEntity.sourceServer == ""
                || fromObservationEntity.symbolName == ""
                || fromObservationEntity.anchorTimeFrame != (int)PERIOD_H1
                || fromObservationEntity.anchorTimeFrameText == ""
                || fromObservationEntity.anchorBarTime <= 0
                || fromObservationEntity.anchorBarTimeText == ""
                || !this.isJapanTimeValid(
                    fromObservationEntity.anchorBarTime,
                    fromObservationEntity.anchorJstTime,
                    fromObservationEntity.anchorJstTimeText
                )
                || fromObservationEntity.capturePhase
                    != "BAR_OPEN_FIRST_SUCCESS"
                || fromObservationEntity.analysisVersion == ""
                || fromObservationEntity.analysisInputHash == ""
                || fromObservationEntity.snapshotHash == ""
                || fromObservationEntity.createdAt <= 0
                || fromObservationEntity.createdAtText == "") {
            this.logger.error(
                __FUNCTION__,
                "observation required value is invalid."
            );

            return false;
        }

        int timeFrameCount = ArraySize(fromTimeFrameEntities);

        if (timeFrameCount != 5
                || fromObservationEntity.timeFrameCount != timeFrameCount) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "observation timeframe count is invalid. actual=%d expected=5 parent=%d",
                    timeFrameCount,
                    fromObservationEntity.timeFrameCount
                )
            );

            return false;
        }

        int expectedTimeFrames[5];
        expectedTimeFrames[0] = (int)PERIOD_MN1;
        expectedTimeFrames[1] = (int)PERIOD_W1;
        expectedTimeFrames[2] = (int)PERIOD_D1;
        expectedTimeFrames[3] = (int)PERIOD_H4;
        expectedTimeFrames[4] = (int)PERIOD_H1;

        for (int i = 0; i < timeFrameCount; i++) {
            ZigZagElliotObservationTimeFrameEntity entity =
                fromTimeFrameEntities[i];
            int expectedAnchorValue = 0;

            if (i == timeFrameCount - 1) {
                expectedAnchorValue = 1;
            }

            if (entity.timeFrame != expectedTimeFrames[i]
                    || entity.timeFrameOrder != i
                    || entity.isAnchorTimeFrame != expectedAnchorValue
                    || entity.timeFrameText == ""
                    || entity.pointCount <= 0
                    || entity.latestPointTime <= 0
                    || entity.latestPointTimeText == ""
                    || !this.isJapanTimeValid(
                        entity.latestPointTime,
                        entity.latestPointJstTime,
                        entity.latestPointJstTimeText
                    )
                    || entity.latestPointRate <= 0.0
                    || entity.createdAt <= 0
                    || entity.createdAtText == ""
                    || !this.isBooleanValue(entity.isBuy)
                    || !this.isBooleanValue(entity.isWaveConfirmed)
                    || !this.isBooleanValue(entity.isWaveMotive)
                    || !this.isBooleanValue(entity.isWaveUptrend)
                    || !this.isBooleanValue(entity.isFiboExpansionAvailable)
                    || !this.isBooleanValue(entity.isOscillatorBuy)
                    || !this.isBooleanValue(entity.isEma200Buy)
                    || !this.isBooleanValue(entity.isEma200Sell)) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat(
                        "observation timeframe value is invalid. order=%d timeframe=%d",
                        i,
                        entity.timeFrame
                    )
                );

                return false;
            }
        }

        return true;
    }

    /**
     * 0または1の真偽値か確認する。
     *
     * @param fromValue 確認対象値。
     * @return 0または1の場合true。
     */
    bool isBooleanValue(const int fromValue) {
        return fromValue == 0 || fromValue == 1;
    }

    /**
     * サーバー時刻から生成した日本時刻と表示文字列か確認する。
     *
     * @param fromServerTime 変換元サーバー時刻。
     * @param fromJstTime 日本時刻。
     * @param fromJstTimeText 日本時刻表示文字列。
     * @return TimeJapanUtilの変換結果と一致する場合true。
     */
    bool isJapanTimeValid(
        const datetime fromServerTime,
        const datetime fromJstTime,
        const string fromJstTimeText
    ) {
        if (fromServerTime <= 0 || fromJstTime <= 0 || fromJstTimeText == "") {
            return false;
        }

        datetime expectedJstTime = TimeJapanUtil::getJapanTime(
            fromServerTime
        );
        string expectedJstTimeText = TimeToString(
            expectedJstTime,
            TIME_DATE | TIME_SECONDS
        );

        return fromJstTime == expectedJstTime
            && fromJstTimeText == expectedJstTimeText;
    }

    /**
     * NULL文字列をDB保存用の空文字列へ変換する。
     *
     * @param fromText 対象文字列。
     * @return NULLの場合は空文字列、それ以外は元の文字列。
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
     * @return 有効化に成功した場合true。
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
     * トランザクションをコミットする。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 成功した場合true。
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
     * @param fromMethodName 呼び出し元メソッド名。
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
     * ロールバックして親子IDを未保存状態へ戻す。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @param fromObservationEntity 観測本体。
     * @param fromTimeFrameEntities 時間足別分析一覧。
     */
    void rollbackAndClear(
        const string fromMethodName,
        ZigZagElliotObservationEntity &fromObservationEntity,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
    ) {
        this.rollbackTransaction(fromMethodName);
        this.clearSnapshotIds(
            fromObservationEntity,
            fromTimeFrameEntities
        );
    }

    /**
     * 親子IDを未保存状態へ戻す。
     *
     * @param fromObservationEntity 観測本体。
     * @param fromTimeFrameEntities 時間足別分析一覧。
     */
    void clearSnapshotIds(
        ZigZagElliotObservationEntity &fromObservationEntity,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
    ) {
        fromObservationEntity.id = 0;

        for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
            fromTimeFrameEntities[i].id = 0;
            fromTimeFrameEntities[i].observationId = 0;
        }
    }

    /**
     * サービスが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合true。
     */
    bool isReady(const string fromMethodName) {
        if (this.databaseHandle != INVALID_HANDLE
                && this.observationDao != NULL
                && this.timeFrameDao != NULL) {
            return true;
        }

        this.logger.error(fromMethodName, "observation persistence is not ready.");

        return false;
    }
};

#endif // MSTNG_DATABASE_SERVICE_ZZ_ELLIOT_OBSERVATION_MQH
