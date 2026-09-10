//+------------------------------------------------------------------+
//|                     ZigZagElliotM5ObservationDatabaseContext.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ZIGZAG_ELLIOT_M5_OBSERVATION_CONTEXT_MQH
#define MSTNG_DATABASE_ZIGZAG_ELLIOT_M5_OBSERVATION_CONTEXT_MQH

#include <Mstng\Database\Dao\ZigZagElliotAlertRunDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationCaptureMetricsDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationTimeFrameDao.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\Service\ZigZagElliotObservationDatabaseGuard.mqh>
#include <Mstng\Database\Service\ZigZagElliotObservationPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Elliot\ZigZagElliotObservationProfile.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 用途を読み取り検査したM5専用DBの接続と観測保存を管理するクラス。
 */
class ZigZagElliotM5ObservationDatabaseContext {
public:
    /**
     * M5専用データベースの保存先を指定して初期化する。
     *
     * @param fromFileName データベースファイル名。
     * @param fromUseCommonFolder 共通フォルダを使用する場合true。
     */
    ZigZagElliotM5ObservationDatabaseContext(
        const string fromFileName,
        const bool fromUseCommonFolder = true
    ) : observationProfile(PERIOD_M5) {
        this.fileName = fromFileName;
        this.useCommonFolder = fromUseCommonFolder;
        this.databaseRejected = false;
        this.logger.setLevel(LOG_INFO);
        this.database = NULL;
        this.runDao = NULL;
        this.observationDao = NULL;
        this.timeFrameDao = NULL;
        this.captureMetricsDao = NULL;
        this.persistenceService = NULL;
    }

    /**
     * データベース関連リソースを解放する。
     */
    ~ZigZagElliotM5ObservationDatabaseContext() {
        this.close();
    }

    /**
     * 用途検査後にM5専用DBを開き、必要な4テーブルを一括準備する。
     *
     * @return 接続とテーブル準備に成功した場合true。
     */
    bool open() {
        if (this.isReady()) {
            return true;
        }

        this.close();
        this.databaseRejected = false;

        if (this.fileName == NULL || this.fileName == "") {
            this.databaseRejected = true;
            this.logger.error(__FUNCTION__, "M5 observation database fileName is empty.");

            return false;
        }

        if (!this.inspectExistingDatabase()) {
            return false;
        }

        this.database = new SqliteDatabase(this.fileName, this.useCommonFolder);

        if (this.database == NULL || !this.database.open()) {
            this.close();

            return false;
        }

        int databaseHandle = this.database.getHandle();

        // 読み取り検査後に接続先の内容が変わった場合も、書き込み前に再確認する。
        if (!this.inspectHandle(databaseHandle)
                || !this.configureConnection(databaseHandle)
                || !this.initializePersistence(databaseHandle)) {
            this.close();

            return false;
        }

        return true;
    }

    /**
     * 接続とDAOを解放する。直前の用途拒否状態は保持する。
     */
    void close() {
        if (this.persistenceService != NULL) {
            delete this.persistenceService;
            this.persistenceService = NULL;
        }

        if (this.captureMetricsDao != NULL) {
            delete this.captureMetricsDao;
            this.captureMetricsDao = NULL;
        }

        if (this.timeFrameDao != NULL) {
            delete this.timeFrameDao;
            this.timeFrameDao = NULL;
        }

        if (this.observationDao != NULL) {
            delete this.observationDao;
            this.observationDao = NULL;
        }

        if (this.runDao != NULL) {
            delete this.runDao;
            this.runDao = NULL;
        }

        if (this.database != NULL) {
            this.database.close();
            delete this.database;
            this.database = NULL;
        }
    }

    /**
     * M5固定Profileに一致するRunを保存し、再接続時は同じUIDを再利用する。
     *
     * @param fromRunEntity 保存対象Run。成功時にIDを設定する。
     * @return 保存または整合した既存Runの確認に成功した場合true。
     */
    bool saveRun(ZigZagElliotAlertRunEntity &fromRunEntity) {
        if (!this.isReady() || !this.isRunValid(fromRunEntity)) {
            return false;
        }

        long existingRunId = 0;

        if (!this.runDao.findIdByRunUid(fromRunEntity.runUid, existingRunId)) {
            return false;
        }

        if (existingRunId > 0) {
            if (!this.isExistingRunMatching(existingRunId, fromRunEntity)) {
                return false;
            }

            fromRunEntity.id = existingRunId;

            return true;
        }

        fromRunEntity.id = 0;

        return this.runDao.insert(fromRunEntity);
    }

    /**
     * M5観測永続化サービスを取得する。
     *
     * @return 未準備の場合NULL。
     */
    ZigZagElliotObservationPersistenceService *getPersistenceService() {
        return this.persistenceService;
    }

    /**
     * 実行情報DAOを取得する。Runの新規保存にはsaveRunを使用する。
     *
     * @return 未準備の場合NULL。
     */
    ZigZagElliotAlertRunDao *getRunDao() {
        return this.runDao;
    }

    /**
     * データベースハンドルを取得する。
     *
     * @return 未接続の場合INVALID_HANDLE。
     */
    int getHandle() const {
        if (this.database == NULL) {
            return INVALID_HANDLE;
        }

        return this.database.getHandle();
    }

    /**
     * M5観測を保存できる状態か判定する。
     *
     * @return 接続と全保存部品の準備ができている場合true。
     */
    bool isReady() const {
        return this.database != NULL
            && this.database.isOpen()
            && this.runDao != NULL
            && this.observationDao != NULL
            && this.timeFrameDao != NULL
            && this.captureMetricsDao != NULL
            && this.persistenceService != NULL;
    }

    /**
     * 最後のopenで別用途または未対応形式のDBを拒否したか判定する。
     *
     * @return 用途拒否の場合true。一時的な読取・接続エラーはfalse。
     */
    bool isDatabaseRejected() const {
        return this.databaseRejected;
    }

private:
    /** データベースファイル名。 */
    string fileName;
    /** 共通フォルダ使用有無。 */
    bool useCommonFolder;
    /** 最後の接続試行でDBの用途または形式を拒否した場合true。 */
    bool databaseRejected;
    /** 当該接続のM5固定観測Profile。 */
    ZigZagElliotObservationProfile observationProfile;
    /** 接続設定用ロガー。 */
    Logger logger;
    /** SQLite接続。 */
    SqliteDatabase *database;
    /** 実行情報DAO。 */
    ZigZagElliotAlertRunDao *runDao;
    /** 観測本体DAO。 */
    ZigZagElliotObservationDao *observationDao;
    /** 時間足別観測DAO。 */
    ZigZagElliotObservationTimeFrameDao *timeFrameDao;
    /** 取得品質DAO。 */
    ZigZagElliotObservationCaptureMetricsDao *captureMetricsDao;
    /** M5観測永続化サービス。 */
    ZigZagElliotObservationPersistenceService *persistenceService;

    /**
     * 既存ファイルを読み取り専用で検査し、用途不一致で書き込み接続しない。
     *
     * @return 新規ファイルまたは利用できる既存DBの場合true。
     */
    bool inspectExistingDatabase() {
        int folderFlag = 0;

        if (this.useCommonFolder) {
            folderFlag = FILE_COMMON;
        }

        if (!FileIsExist(this.fileName, folderFlag)) {
            return true;
        }

        SqliteDatabase readOnlyDatabase(this.fileName, this.useCommonFolder);

        if (!readOnlyDatabase.openReadOnly()) {
            return false;
        }

        bool isAllowed = this.inspectHandle(readOnlyDatabase.getHandle());
        readOnlyDatabase.close();

        return isAllowed;
    }

    /**
     * 接続先を読み取り検査し、用途拒否と一時的な読取失敗を区別する。
     *
     * @param fromDatabaseHandle 検査対象接続。
     * @return M5観測用途として許可された場合true。
     */
    bool inspectHandle(const int fromDatabaseHandle) {
        bool isAllowed = false;
        string reason = "";

        if (!ZigZagElliotObservationDatabaseGuard::inspectM5(
                fromDatabaseHandle,
                isAllowed,
                reason
            )) {
            this.logger.error(__FUNCTION__, "M5 database inspection failed. " + reason);

            return false;
        }

        if (!isAllowed) {
            this.databaseRejected = true;
            this.logger.error(__FUNCTION__, "M5 database rejected. " + reason);

            return false;
        }

        return true;
    }

    /**
     * 検査済み接続だけに外部キー、待機時間およびWALを設定して検証する。
     *
     * @param fromDatabaseHandle 設定対象接続。
     * @return 全設定を検証できた場合true。
     */
    bool configureConnection(const int fromDatabaseHandle) {
        ResetLastError();

        if (!DatabaseExecute(fromDatabaseHandle, "PRAGMA foreign_keys = ON")
                || !DatabaseExecute(fromDatabaseHandle, "PRAGMA busy_timeout = 5000")) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("connection PRAGMA failed. error=%d", GetLastError())
            );

            return false;
        }

        long foreignKeys = 0;
        long busyTimeout = 0;

        if (!this.readLongPragma(fromDatabaseHandle, "PRAGMA foreign_keys", foreignKeys)
                || foreignKeys != 1
                || !this.readLongPragma(fromDatabaseHandle, "PRAGMA busy_timeout", busyTimeout)
                || busyTimeout < 5000) {
            this.logger.error(__FUNCTION__, "foreign_keys or busy_timeout verification failed.");

            return false;
        }

        string journalMode = "";

        if (!this.readTextPragma(fromDatabaseHandle, "PRAGMA journal_mode = WAL", journalMode)
                || (journalMode != "wal" && journalMode != "WAL")) {
            this.logger.error(__FUNCTION__, "journal_mode verification failed. actual=" + journalMode);

            return false;
        }

        return true;
    }

    /**
     * 同じ接続にDAOを作り、4テーブルの準備を原子的に行う。
     *
     * @param fromDatabaseHandle 準備対象接続。
     * @return 部分スキーマを残さず準備できた場合true。
     */
    bool initializePersistence(const int fromDatabaseHandle) {
        this.runDao = new ZigZagElliotAlertRunDao(fromDatabaseHandle);
        this.observationDao = new ZigZagElliotObservationDao(fromDatabaseHandle);
        this.timeFrameDao = new ZigZagElliotObservationTimeFrameDao(fromDatabaseHandle);
        this.captureMetricsDao = new ZigZagElliotObservationCaptureMetricsDao(fromDatabaseHandle);

        if (this.runDao == NULL || this.observationDao == NULL
                || this.timeFrameDao == NULL || this.captureMetricsDao == NULL) {
            return false;
        }

        this.persistenceService = new ZigZagElliotObservationPersistenceService(
            fromDatabaseHandle,
            this.observationDao,
            this.timeFrameDao,
            this.observationProfile,
            this.captureMetricsDao
        );

        if (this.persistenceService == NULL) {
            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionBegin(fromDatabaseHandle)) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("schema transaction begin failed. error=%d", GetLastError())
            );

            return false;
        }

        bool isCreated = this.runDao.createTable() && this.persistenceService.createTables();

        if (isCreated && DatabaseTransactionCommit(fromDatabaseHandle)) {
            return true;
        }

        int errorCode = GetLastError();
        DatabaseTransactionRollback(fromDatabaseHandle);
        this.logger.error(
            __FUNCTION__,
            StringFormat("M5 observation schema preparation failed. error=%d", errorCode)
        );

        return false;
    }

    /**
     * M5以外や不整合な分析ProfileのRunを保存前に拒否する。
     *
     * @param fromRunEntity 確認するRun。
     * @return M5固定契約と実行元の必須値が有効な場合true。
     */
    bool isRunValid(const ZigZagElliotAlertRunEntity &fromRunEntity) {
        string profileHash = this.observationProfile.createHash();

        if (fromRunEntity.runUid == NULL || fromRunEntity.runUid == ""
                || (fromRunEntity.sourceMode != "LIVE" && fromRunEntity.sourceMode != "TESTER")
                || fromRunEntity.sourceServer == NULL || fromRunEntity.sourceServer == ""
                || fromRunEntity.schemaVersion != this.observationProfile.getSchemaVersion()
                || fromRunEntity.strategy != this.observationProfile.getStrategy()
                || fromRunEntity.strategyVersion != this.observationProfile.getStrategyVersion()
                || fromRunEntity.analysisVersion != this.observationProfile.getAnalysisVersion()
                || fromRunEntity.analysisInputText != this.observationProfile.createCanonicalText()
                || StringLen(profileHash) != 64
                || fromRunEntity.analysisInputHash != profileHash) {
            this.logger.error(__FUNCTION__, "M5 observation Run profile or source is invalid.");

            return false;
        }

        return true;
    }

    /**
     * 同一UIDの既存Runが実行元と分析Profileの一致するRunか確認する。
     *
     * @param fromRunId 既存Run ID。
     * @param fromRunEntity 再利用を要求するRun。
     * @return 一致する場合true。
     */
    bool isExistingRunMatching(
        const long fromRunId,
        const ZigZagElliotAlertRunEntity &fromRunEntity
    ) {
        string sql = "SELECT COUNT(*) FROM zigzag_elliot_alert_runs WHERE id = ?1";
        sql += " AND source_mode = ?2 AND source_server = ?3 AND schema_version = ?4";
        sql += " AND strategy = ?5 AND strategy_version = ?6 AND analysis_version = ?7";
        sql += " AND analysis_input_text = ?8 AND analysis_input_hash = ?9";
        ResetLastError();
        int requestHandle = DatabasePrepare(this.getHandle(), sql);

        if (requestHandle == INVALID_HANDLE) {
            return false;
        }

        bool isBound = DatabaseBind(requestHandle, 0, fromRunId)
            && DatabaseBind(requestHandle, 1, fromRunEntity.sourceMode)
            && DatabaseBind(requestHandle, 2, fromRunEntity.sourceServer)
            && DatabaseBind(requestHandle, 3, fromRunEntity.schemaVersion)
            && DatabaseBind(requestHandle, 4, fromRunEntity.strategy)
            && DatabaseBind(requestHandle, 5, fromRunEntity.strategyVersion)
            && DatabaseBind(requestHandle, 6, fromRunEntity.analysisVersion)
            && DatabaseBind(requestHandle, 7, fromRunEntity.analysisInputText)
            && DatabaseBind(requestHandle, 8, fromRunEntity.analysisInputHash);
        long matchingCount = 0;
        bool isMatching = isBound
            && DatabaseRead(requestHandle)
            && DatabaseColumnLong(requestHandle, 0, matchingCount)
            && matchingCount == 1;
        DatabaseFinalize(requestHandle);

        if (!isMatching) {
            this.logger.error(__FUNCTION__, "Existing M5 Run could not be matched to source and profile.");
        }

        return isMatching;
    }

    /**
     * 単一整数を返すPRAGMAを読み取る。
     *
     * @param fromDatabaseHandle 対象接続。
     * @param fromSql PRAGMA文。
     * @param fromValue 取得値の格納先。
     * @return 取得できた場合true。
     */
    bool readLongPragma(
        const int fromDatabaseHandle,
        const string fromSql,
        long &fromValue
    ) {
        fromValue = 0;
        ResetLastError();
        int requestHandle = DatabasePrepare(fromDatabaseHandle, fromSql);

        if (requestHandle == INVALID_HANDLE) {
            return false;
        }

        bool isRead = DatabaseRead(requestHandle)
            && DatabaseColumnLong(requestHandle, 0, fromValue);
        DatabaseFinalize(requestHandle);

        return isRead;
    }

    /**
     * 単一文字列を返すPRAGMAを読み取る。
     *
     * @param fromDatabaseHandle 対象接続。
     * @param fromSql PRAGMA文。
     * @param fromValue 取得値の格納先。
     * @return 取得できた場合true。
     */
    bool readTextPragma(
        const int fromDatabaseHandle,
        const string fromSql,
        string &fromValue
    ) {
        fromValue = "";
        ResetLastError();
        int requestHandle = DatabasePrepare(fromDatabaseHandle, fromSql);

        if (requestHandle == INVALID_HANDLE) {
            return false;
        }

        bool isRead = DatabaseRead(requestHandle)
            && DatabaseColumnText(requestHandle, 0, fromValue);
        DatabaseFinalize(requestHandle);

        return isRead;
    }
};

#endif // MSTNG_DATABASE_ZIGZAG_ELLIOT_M5_OBSERVATION_CONTEXT_MQH
