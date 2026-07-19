//+------------------------------------------------------------------+
//|                        CurrencyStrengthDatabaseContext.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_DATABASE_CONTEXT_MQH
#define MSTNG_CURRENCY_STRENGTH_DATABASE_CONTEXT_MQH

#include <Mstng\Database\Dao\CurrencyStrengthPairVoteDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthResultDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthRunDao.mqh>
#include <Mstng\Database\Service\CurrencyStrengthPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>

/**
 * 1つの通貨強弱データベース接続と永続化関連クラスを管理するクラス。
 */
class CurrencyStrengthDatabaseContext {
public:
    /**
     * データベースファイル名と共有フォルダ使用有無を指定して初期化する。
     *
     * @param fromFileName データベースファイル名。
     * @param fromUseCommonFolder 共有フォルダを使用する場合true。
     */
    CurrencyStrengthDatabaseContext(
        const string fromFileName,
        const bool fromUseCommonFolder
    ) {
        this.fileName = fromFileName;
        this.useCommonFolder = fromUseCommonFolder;
        this.database = NULL;
        this.pairVoteDao = NULL;
        this.resultDao = NULL;
        this.runDao = NULL;
        this.persistenceService = NULL;
    }

    /**
     * デストラクタ。
     */
    ~CurrencyStrengthDatabaseContext() {
        this.close();
    }

    /**
     * データベースを開いて必要なテーブルを準備する。
     *
     * @return 準備に成功した場合true。
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

        this.runDao = new CurrencyStrengthRunDao(
            this.database.getHandle()
        );
        this.pairVoteDao = new CurrencyStrengthPairVoteDao(
            this.database.getHandle()
        );
        this.resultDao = new CurrencyStrengthResultDao(
            this.database.getHandle()
        );

        if (this.runDao == NULL
                || this.pairVoteDao == NULL
                || this.resultDao == NULL) {
            this.close();

            return false;
        }

        this.persistenceService = new CurrencyStrengthPersistenceService(
            this.database.getHandle(),
            this.runDao,
            this.pairVoteDao,
            this.resultDao
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

        if (this.resultDao != NULL) {
            delete this.resultDao;
            this.resultDao = NULL;
        }

        if (this.pairVoteDao != NULL) {
            delete this.pairVoteDao;
            this.pairVoteDao = NULL;
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
     * 永続化サービスを取得する。
     *
     * @return 永続化サービス。未準備の場合はNULL。
     */
    CurrencyStrengthPersistenceService *getPersistenceService() {
        return this.persistenceService;
    }

    /**
     * データベースファイル名を取得する。
     *
     * @return データベースファイル名。
     */
    string getFileName() const {
        return this.fileName;
    }

    /**
     * データベースが保存可能な状態か判定する。
     *
     * @return 保存可能な場合true。
     */
    bool isReady() const {
        return this.database != NULL
            && this.database.isOpen()
            && this.persistenceService != NULL;
    }

private:
    /** データベースファイル名。 */
    string fileName;

    /** 共有フォルダ使用有無。 */
    bool useCommonFolder;

    /** SQLite接続。 */
    SqliteDatabase *database;

    /** 票内訳DAO。 */
    CurrencyStrengthPairVoteDao *pairVoteDao;

    /** 通貨別結果DAO。 */
    CurrencyStrengthResultDao *resultDao;

    /** 集計単位DAO。 */
    CurrencyStrengthRunDao *runDao;

    /** 永続化サービス。 */
    CurrencyStrengthPersistenceService *persistenceService;
};

#endif // MSTNG_CURRENCY_STRENGTH_DATABASE_CONTEXT_MQH
