//+------------------------------------------------------------------+
//|                    ZigZagElliotObservationPersistenceService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_SERVICE_ZZ_ELLIOT_OBSERVATION_MQH
#define MSTNG_DATABASE_SERVICE_ZZ_ELLIOT_OBSERVATION_MQH

#include <Mstng\Database\Dao\ZigZagElliotObservationCaptureMetricsDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationTimeFrameDao.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationTimeFrameEntity.mqh>
#include <Mstng\Elliot\ZigZagElliotObservationProfile.mqh>
#include <Mstng\ExpertAdvisor\ZigZagElliotObservationSnapshot.mqh>
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
        this.captureMetricsDao = NULL;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 固定観測Profileと取得品質DAOを指定して初期化する。
     *
     * @param fromDatabaseHandle SQLiteデータベースハンドル。
     * @param fromObservationDao 観測本体DAO。
     * @param fromTimeFrameDao 時間足別観測DAO。
     * @param fromProfile 起動時に固定した観測Profile。
     * @param fromCaptureMetricsDao M5取得品質DAO。
     */
    ZigZagElliotObservationPersistenceService(
        const int fromDatabaseHandle,
        ZigZagElliotObservationDao *fromObservationDao,
        ZigZagElliotObservationTimeFrameDao *fromTimeFrameDao,
        const ZigZagElliotObservationProfile &fromProfile,
        ZigZagElliotObservationCaptureMetricsDao *fromCaptureMetricsDao
    ) {
        this.databaseHandle = fromDatabaseHandle;
        this.observationDao = fromObservationDao;
        this.timeFrameDao = fromTimeFrameDao;
        this.observationProfile = fromProfile;
        this.captureMetricsDao = fromCaptureMetricsDao;
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
        ZigZagElliotObservationCaptureMetricsEntity captureMetrics;
        ZeroMemory(captureMetrics);

        return this.saveSnapshotInternal(
            fromObservationEntity, fromTimeFrameEntities, false, captureMetrics
        );
    }

    /**
     * 分析結果と任意の取得品質を同じSnapshotから保存する。
     *
     * @param fromSnapshot H1またはM5の固定済みSnapshot。
     * @return 新規保存または既存行取得に成功した場合true。
     */
    bool saveSnapshot(ZigZagElliotObservationSnapshot &fromSnapshot) {
        fromSnapshot.captureMetrics.observationId = 0;
        bool isSaved = this.saveSnapshotInternal(
            fromSnapshot.observation,
            fromSnapshot.timeFrames,
            fromSnapshot.hasCaptureMetrics,
            fromSnapshot.captureMetrics
        );

        if (!isSaved) {
            fromSnapshot.captureMetrics.observationId = 0;
        }

        return isSaved;
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** 観測本体DAO。 */
    ZigZagElliotObservationDao *observationDao;

    /** 時間足別観測DAO。 */
    ZigZagElliotObservationTimeFrameDao *timeFrameDao;

    /** 起動時に固定した観測Profile。既存コンストラクタではH1。 */
    ZigZagElliotObservationProfile observationProfile;

    /** M5取得品質DAO。H1では未使用。 */
    ZigZagElliotObservationCaptureMetricsDao *captureMetricsDao;

    /** ロガー。 */
    Logger logger;

    /**
     * Profileに応じた親・子・取得品質を原子的に保存する。
     *
     * @param fromObservationEntity 観測本体。
     * @param fromTimeFrameEntities 時間足別分析一覧。
     * @param fromHasCaptureMetrics 品質行を保持する場合true。
     * @param fromCaptureMetrics Snapshot生成時に固定した取得品質。
     * @return 保存または既存行取得に成功した場合true。
     */
    bool saveSnapshotInternal(
        ZigZagElliotObservationEntity &fromObservationEntity,
        ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[],
        const bool fromHasCaptureMetrics,
        ZigZagElliotObservationCaptureMetricsEntity &fromCaptureMetrics
    ) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        if (fromHasCaptureMetrics != this.observationProfile.requiresCaptureMetrics()
                || (fromHasCaptureMetrics && !fromCaptureMetrics.isValid())) {
            this.logger.error(__FUNCTION__, "observation capture metrics are invalid.");

            return false;
        }

        this.normalizeSnapshotTextValues(
            fromObservationEntity,
            fromTimeFrameEntities
        );

        if (!this.isSnapshotValid(
                fromObservationEntity,
                fromTimeFrameEntities
            ) || (this.observationProfile.isM5()
                && !this.isRunMatched(fromObservationEntity))) {
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

        if (isSaved && fromHasCaptureMetrics) {
            fromCaptureMetrics.observationId = fromObservationEntity.id;
            isSaved = this.captureMetricsDao.insert(fromCaptureMetrics);
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

    /**
     * 延長済みbusy_timeoutの範囲で親子テーブルと全インデックスを準備する。
     *
     * @return 準備に成功した場合true。
     */
    bool createTablesWithExtendedTimeout() {
        if (!this.enableForeignKeys()) {
            return false;
        }

        if (!this.observationDao.createTable(this.observationProfile.isM5())) {
            return false;
        }

        if (!this.timeFrameDao.createTable(this.observationProfile.isM5())) {
            return false;
        }

        if (this.observationProfile.requiresCaptureMetrics()) {
            return this.captureMetricsDao.createTable();
        }

        return true;
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
        fromEntity.latestPointFiboDepthZoneLabel = this.normalizeText(
            fromEntity.latestPointFiboDepthZoneLabel
        );
        fromEntity.latestPointOrgElliotLabel = this.normalizeText(
            fromEntity.latestPointOrgElliotLabel
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
     * 保存対象スナップショットの必須値とProfileの固定時間足を確認する。
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
                || fromObservationEntity.anchorTimeFrame
                    != (int)this.observationProfile.getAnchorTimeFrame()
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
                || !MathIsValidNumber(fromObservationEntity.spreadPips)
                || fromObservationEntity.spreadPips == EMPTY_VALUE
                || fromObservationEntity.spreadPips < 0.0
                || !MathIsValidNumber(fromObservationEntity.pipSize)
                || fromObservationEntity.pipSize == EMPTY_VALUE
                || fromObservationEntity.pipSize <= 0.0
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

        if (this.observationProfile.isM5()
                && (fromObservationEntity.anchorTimeFrameText != "M5"
                    || fromObservationEntity.anchorBarTimeText
                        != TimeToString(fromObservationEntity.anchorBarTime, TIME_DATE | TIME_SECONDS)
                    || fromObservationEntity.createdAtText
                        != TimeToString(fromObservationEntity.createdAt, TIME_DATE | TIME_SECONDS))) {
            this.logger.error(__FUNCTION__, "M5 observation time text is invalid.");

            return false;
        }

        int expectedTimeFrameCount = this.observationProfile.getObservationTimeFrameCount();

        if (timeFrameCount != expectedTimeFrameCount
                || fromObservationEntity.timeFrameCount != timeFrameCount) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "observation timeframe count is invalid. actual=%d expected=%d parent=%d",
                    timeFrameCount,
                    expectedTimeFrameCount,
                    fromObservationEntity.timeFrameCount
                )
            );

            return false;
        }

        for (int i = 0; i < timeFrameCount; i++) {
            ZigZagElliotObservationTimeFrameEntity entity =
                fromTimeFrameEntities[i];
            int expectedAnchorValue = 0;

            if (i == timeFrameCount - 1) {
                expectedAnchorValue = 1;
            }

            if (entity.timeFrame != (int)this.observationProfile.getObservationTimeFrame(i)
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
                    || !this.isBooleanValue(entity.latestPointIsAdded)
                    || !this.isBooleanValue(entity.latestPointIsPeak)
                    || !this.isBooleanValue(
                        entity.latestPointIsElliotAlphabet
                    )
                    || !this.isBooleanValue(entity.latestPointIsCorrect)
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

            if (this.observationProfile.isM5()
                    && !this.isM5TimeFrameValid(entity)) {
                this.logger.error(__FUNCTION__, "M5 timeframe scalar or text is invalid.");

                return false;
            }
        }

        return true;
    }

    /**
     * M5観測と保存済みRunが同じ固定Profile・実行元か確認する。
     *
     * @param fromEntity 保存する観測本体。
     * @return 実行元とProfileが一致する場合true。
     */
    bool isRunMatched(ZigZagElliotObservationEntity &fromEntity) {
        string sql = "SELECT COUNT(*) FROM zigzag_elliot_alert_runs WHERE id=?1";
        sql += " AND source_mode=?2 AND source_server=?3";
        sql += " AND analysis_version=?4 AND analysis_input_hash=?5";
        sql += " AND strategy=?6 AND strategy_version=?7 AND schema_version=?8";
        sql += " AND analysis_input_text=?9";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.databaseHandle, sql);

        if (requestHandle == INVALID_HANDLE) {
            this.logger.error(__FUNCTION__, "M5 Run query preparation failed.");

            return false;
        }

        string canonicalText = this.observationProfile.createCanonicalText();
        string profileHash = this.observationProfile.createHash();
        bool isMatched = fromEntity.analysisVersion
                == ZigZagElliotAnalysisProfile::getAnalysisVersion()
            && fromEntity.analysisInputHash == profileHash
            && profileHash != ""
            && DatabaseBind(requestHandle, 0, fromEntity.runId)
            && DatabaseBind(requestHandle, 1, fromEntity.sourceMode)
            && DatabaseBind(requestHandle, 2, fromEntity.sourceServer)
            && DatabaseBind(requestHandle, 3, fromEntity.analysisVersion)
            && DatabaseBind(requestHandle, 4, fromEntity.analysisInputHash)
            && DatabaseBind(requestHandle, 5, this.observationProfile.getStrategy())
            && DatabaseBind(requestHandle, 6, this.observationProfile.getStrategyVersion())
            && DatabaseBind(requestHandle, 7, this.observationProfile.getSchemaVersion())
            && DatabaseBind(requestHandle, 8, canonicalText);
        long count = 0;

        if (isMatched) {
            isMatched = DatabaseRead(requestHandle)
                && DatabaseColumnLong(requestHandle, 0, count)
                && count == 1;
        }

        DatabaseFinalize(requestHandle);

        if (!isMatched) {
            this.logger.error(__FUNCTION__, "M5 observation Run/Profile mismatch or query failed.");
        }

        return isMatched;
    }

    /**
     * M5の保存値に非有限値・EMPTY_VALUE・不一致の表示時刻がないか確認する。
     *
     * @param fromEntity 1時間足の分析結果。
     * @return 保存できる有限値と表示文字列の場合true。
     */
    bool isM5TimeFrameValid(ZigZagElliotObservationTimeFrameEntity &fromEntity) {
        string expectedTimeFrameText = EnumToString((ENUM_TIMEFRAMES)fromEntity.timeFrame);
        StringReplace(expectedTimeFrameText, "PERIOD_", "");

        if (fromEntity.timeFrameText != expectedTimeFrameText
                || fromEntity.latestPointTimeText
                    != TimeToString(fromEntity.latestPointTime, TIME_DATE | TIME_SECONDS)
                || fromEntity.createdAtText
                    != TimeToString(fromEntity.createdAt, TIME_DATE | TIME_SECONDS)
                || fromEntity.previousOpen <= 0.0 || fromEntity.previousHigh <= 0.0
                || fromEntity.previousLow <= 0.0 || fromEntity.previousClose <= 0.0
                || fromEntity.currentOpen <= 0.0 || fromEntity.currentHigh <= 0.0
                || fromEntity.currentLow <= 0.0 || fromEntity.currentClose <= 0.0) {
            return false;
        }

        double values[] = {
            fromEntity.latestPointRate, fromEntity.latestPointPipsDiff,
            fromEntity.latestPointFibonacciPercent, fromEntity.latestPointFibonacciExpansionPercent,
            fromEntity.previousOpen, fromEntity.previousHigh,
            fromEntity.previousLow, fromEntity.previousClose,
            fromEntity.currentOpen, fromEntity.currentHigh,
            fromEntity.currentLow, fromEntity.currentClose,
            fromEntity.fe618Price, fromEntity.fe1000Price, fromEntity.fe1272Price,
            fromEntity.fe1618Price, fromEntity.fe2000Price, fromEntity.distanceToFe2000Pips,
            fromEntity.stochasticShortMain, fromEntity.stochasticShortSignal,
            fromEntity.stochasticMiddleMain, fromEntity.stochasticMiddleSignal,
            fromEntity.stochasticLongMain, fromEntity.stochasticLongSignal,
            fromEntity.ema30, fromEntity.ema60, fromEntity.ema30Ema60DiffPips,
            fromEntity.atr14Pips, fromEntity.ema200Close1, fromEntity.ema200Shift1,
            fromEntity.ema200Compare, fromEntity.ema200SlopePips, fromEntity.ema200CloseDiffPips
        };

        for (int i = 0; i < ArraySize(values); i++) {
            if (!MathIsValidNumber(values[i]) || values[i] == EMPTY_VALUE) {
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
                && this.timeFrameDao != NULL
                && this.observationProfile.isValid()
                && (!this.observationProfile.requiresCaptureMetrics()
                    || this.captureMetricsDao != NULL)) {
            return true;
        }

        this.logger.error(fromMethodName, "observation persistence is not ready.");

        return false;
    }
};

#endif // MSTNG_DATABASE_SERVICE_ZZ_ELLIOT_OBSERVATION_MQH
