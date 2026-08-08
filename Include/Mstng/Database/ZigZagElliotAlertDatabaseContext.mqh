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
#include <Mstng\Database\Service\ZigZagElliotAlertPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>

/**
 * ZigZagElliotアラート用SQLite接続と永続化クラスを管理するクラス。
 */
class ZigZagElliotAlertDatabaseContext {
public:
    /**
     * データベースファイル名と共通フォルダ使用有無を指定して初期化する。
     *
     * @param fromFileName データベースファイル名
     * @param fromUseCommonFolder 共通フォルダを使用する場合true
     */
    ZigZagElliotAlertDatabaseContext(
        const string fromFileName,
        const bool fromUseCommonFolder
    ) {
        this.fileName = fromFileName;
        this.useCommonFolder = fromUseCommonFolder;
        this.database = NULL;
        this.alertDao = NULL;
        this.pointDao = NULL;
        this.runDao = NULL;
        this.timeFrameDao = NULL;
        this.persistenceService = NULL;
    }

    /**
     * デストラクタ。
     */
    ~ZigZagElliotAlertDatabaseContext() {
        this.close();
    }

    /**
     * データベースを開き、アラート関連テーブルを準備する。
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

        return true;
    }

    /**
     * データベース関連リソースを解放する。
     */
    void close() {
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
    /** 永続化サービス。 */
    ZigZagElliotAlertPersistenceService *persistenceService;
};

#endif // MSTNG_DATABASE_ZIGZAG_ELLIOT_ALERT_DATABASE_CONTEXT_MQH
