//+------------------------------------------------------------------+
//|                    ZigZagElliotAlertDatabaseContext.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_ZIGZAG_ELLIOT_ALERT_DATABASE_CONTEXT_MQH
#define MSTNG_DATABASE_ZIGZAG_ELLIOT_ALERT_DATABASE_CONTEXT_MQH

#include <Mstng\Database\Dao\ZigZagElliotAlertDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertPointDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertRunDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotAlertTimeFrameDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationTimeFrameDao.mqh>
#include <Mstng\Database\Service\ZigZagElliotAlertPersistenceService.mqh>
#include <Mstng\Database\Service\ZigZagElliotObservationPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * ZigZagElliot用SQLite接続と永続化クラスを管理するクラス。
 */
class ZigZagElliotAlertDatabaseContext {
public:
    /**
     * データベースファイル名と共通フォルダ使用有無を指定して初期化する。
     *
     * @param fromFileName データベースファイル名
     * @param fromUseCommonFolder 共通フォルダを使用する場合true
     * @param fromObservationEnabled Elliott観測テーブルを準備する場合true
     */
    ZigZagElliotAlertDatabaseContext(
        const string fromFileName,
        const bool fromUseCommonFolder,
        const bool fromObservationEnabled = false
    ) {
        this.fileName = fromFileName;
        this.useCommonFolder = fromUseCommonFolder;
        this.observationEnabled = fromObservationEnabled;
        this.logger.setLevel(LOG_INFO);
        this.database = NULL;
        this.alertDao = NULL;
        this.pointDao = NULL;
        this.runDao = NULL;
        this.timeFrameDao = NULL;
        this.observationDao = NULL;
        this.observationTimeFrameDao = NULL;
        this.persistenceService = NULL;
        this.observationPersistenceService = NULL;
    }

    /**
     * デストラクタ。
     */
    ~ZigZagElliotAlertDatabaseContext() {
        this.close();
    }

    /**
     * データベースを開き、アラートおよび観測関連テーブルを準備する。
     *
     * @return 準備に成功した場合true
     */
    bool open() {
        if (this.isReady()) {
            return true;
        }

        this.close();
        this.database = new SqliteDatabase(
            this.fileName,
            this.useCommonFolder
        );

        if (this.database == NULL || !this.database.open()) {
            this.close();

            return false;
        }

        int databaseHandle = this.database.getHandle();

        if (!this.configureConnection(databaseHandle)) {
            this.close();

            return false;
        }

        this.alertDao = new ZigZagElliotAlertDao(databaseHandle);
        this.pointDao = new ZigZagElliotAlertPointDao(databaseHandle);
        this.runDao = new ZigZagElliotAlertRunDao(databaseHandle);
        this.timeFrameDao = new ZigZagElliotAlertTimeFrameDao(databaseHandle);

        if (this.alertDao == NULL
                || this.pointDao == NULL
                || this.runDao == NULL
                || this.timeFrameDao == NULL) {
            this.close();

            return false;
        }

        this.persistenceService =
            new ZigZagElliotAlertPersistenceService(
                databaseHandle,
                this.alertDao,
                this.pointDao,
                this.runDao,
                this.timeFrameDao
            );

        if (this.persistenceService == NULL
                || !this.persistenceService.createTables()) {
            this.close();

            return false;
        }

        if (this.observationEnabled) {
            this.initializeObservation(databaseHandle);
        }

        return true;
    }

    /**
     * データベース関連リソースを解放する。
     */
    void close() {
        this.releaseObservation();

        if (this.persistenceService != NULL) {
            delete this.persistenceService;
            this.persistenceService = NULL;
        }

        if (this.timeFrameDao != NULL) {
            delete this.timeFrameDao;
            this.timeFrameDao = NULL;
        }

        if (this.runDao != NULL) {
            delete this.runDao;
            this.runDao = NULL;
        }

        if (this.pointDao != NULL) {
            delete this.pointDao;
            this.pointDao = NULL;
        }

        if (this.alertDao != NULL) {
            delete this.alertDao;
            this.alertDao = NULL;
        }

        if (this.database != NULL) {
            this.database.close();
            delete this.database;
            this.database = NULL;
        }
    }

    /**
     * 永続化サービスを取得する。
     *
     * @return 永続化サービス。未準備の場合NULL
     */
    ZigZagElliotAlertPersistenceService *getPersistenceService() {
        return this.persistenceService;
    }

    /**
     * Elliott観測永続化サービスを取得する。
     *
     * @return 永続化サービス。未準備の場合NULL
     */
    ZigZagElliotObservationPersistenceService *getObservationPersistenceService() {
        return this.observationPersistenceService;
    }

    /**
     * データベースが保存可能な状態か判定する。
     *
     * @return 保存可能な場合true
     */
    bool isReady() const {
        return this.database != NULL
            && this.database.isOpen()
            && this.persistenceService != NULL;
    }

private:
    /** データベースファイル名。 */
    string fileName;
    /** 共通フォルダ使用有無。 */
    bool useCommonFolder;
    /** Elliott観測テーブルを準備する場合true。 */
    bool observationEnabled;
    /** データベース接続設定用ロガー。 */
    Logger logger;
    /** SQLite接続。 */
    SqliteDatabase *database;
    /** アラートDAO。 */
    ZigZagElliotAlertDao *alertDao;
    /** ポイントDAO。 */
    ZigZagElliotAlertPointDao *pointDao;
    /** 実行情報DAO。 */
    ZigZagElliotAlertRunDao *runDao;
    /** 時間足別分析DAO。 */
    ZigZagElliotAlertTimeFrameDao *timeFrameDao;
    /** Elliott観測DAO。 */
    ZigZagElliotObservationDao *observationDao;
    /** Elliott時間足別観測DAO。 */
    ZigZagElliotObservationTimeFrameDao *observationTimeFrameDao;
    /** 永続化サービス。 */
    ZigZagElliotAlertPersistenceService *persistenceService;
    /** Elliott観測永続化サービス。 */
    ZigZagElliotObservationPersistenceService *observationPersistenceService;

    /**
     * 同一DBへの複数チャート書込みに必要な接続設定を適用する。
     *
     * @param fromDatabaseHandle データベースハンドル
     * @return busy timeoutとWALモードを確認できた場合true
     */
    bool configureConnection(const int fromDatabaseHandle) {
        ResetLastError();

        if (!DatabaseExecute(
                fromDatabaseHandle,
                "PRAGMA busy_timeout = 5000"
            )) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "busy_timeout configuration failed. error=%d",
                    GetLastError()
                )
            );

            return false;
        }

        long busyTimeout = 0;

        if (!this.readLongPragma(
                fromDatabaseHandle,
                "PRAGMA busy_timeout",
                busyTimeout
            ) || busyTimeout < 5000) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "busy_timeout verification failed. actual=%I64d",
                    busyTimeout
                )
            );

            return false;
        }

        string journalMode = "";

        if (!this.readTextPragma(
                fromDatabaseHandle,
                "PRAGMA journal_mode = WAL",
                journalMode
            ) || (journalMode != "wal" && journalMode != "WAL")) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "journal_mode verification failed. actual=%s",
                    journalMode
                )
            );

            return false;
        }

        return true;
    }

    /**
     * 単一整数を返すPRAGMAを実行する。
     *
     * @param fromDatabaseHandle データベースハンドル
     * @param fromSql PRAGMA文
     * @param fromValue 取得値の格納先
     * @return 取得できた場合true
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

        bool isRead = DatabaseRead(requestHandle);
        bool isReadValue = false;

        if (isRead) {
            isReadValue = DatabaseColumnLong(
                requestHandle,
                0,
                fromValue
            );
        }

        DatabaseFinalize(requestHandle);

        return isRead && isReadValue;
    }

    /**
     * 単一文字列を返すPRAGMAを実行する。
     *
     * @param fromDatabaseHandle データベースハンドル
     * @param fromSql PRAGMA文
     * @param fromValue 取得値の格納先
     * @return 取得できた場合true
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

        bool isRead = DatabaseRead(requestHandle);
        bool isReadValue = false;

        if (isRead) {
            isReadValue = DatabaseColumnText(
                requestHandle,
                0,
                fromValue
            );
        }

        DatabaseFinalize(requestHandle);

        return isRead && isReadValue;
    }

    /**
     * Elliott観測DAOと永続化サービスを初期化する。
     *
     * 初期化に失敗した場合は観測関連リソースだけを解放し、既存の
     * アラート永続化サービスとデータベース接続を維持する。
     *
     * @param fromDatabaseHandle データベースハンドル
     * @return 観測情報を保存可能になった場合true
     */
    bool initializeObservation(const int fromDatabaseHandle) {
        this.observationDao =
            new ZigZagElliotObservationDao(fromDatabaseHandle);
        this.observationTimeFrameDao =
            new ZigZagElliotObservationTimeFrameDao(fromDatabaseHandle);

        if (this.observationDao == NULL
                || this.observationTimeFrameDao == NULL) {
            this.releaseObservation();

            return false;
        }

        this.observationPersistenceService =
            new ZigZagElliotObservationPersistenceService(
                fromDatabaseHandle,
                this.observationDao,
                this.observationTimeFrameDao
            );

        if (this.observationPersistenceService == NULL
                || !this.observationPersistenceService.createTables()) {
            this.releaseObservation();

            return false;
        }

        return true;
    }

    /**
     * Elliott観測関連リソースを解放する。
     */
    void releaseObservation() {
        if (this.observationPersistenceService != NULL) {
            delete this.observationPersistenceService;
            this.observationPersistenceService = NULL;
        }

        if (this.observationTimeFrameDao != NULL) {
            delete this.observationTimeFrameDao;
            this.observationTimeFrameDao = NULL;
        }

        if (this.observationDao != NULL) {
            delete this.observationDao;
            this.observationDao = NULL;
        }
    }
};

#endif // MSTNG_DATABASE_ZIGZAG_ELLIOT_ALERT_DATABASE_CONTEXT_MQH
