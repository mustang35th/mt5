//+------------------------------------------------------------------+
//|              CurrencyStrengthYearlyPersistenceService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_YEARLY_PERSISTENCE_SERVICE_MQH
#define MSTNG_CURRENCY_STRENGTH_YEARLY_PERSISTENCE_SERVICE_MQH

#include <Mstng\Database\CurrencyStrengthDatabaseContext.mqh>
#include <Mstng\Database\CurrencyStrengthDatabaseFileResolver.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthRunDao.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthPairVoteEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthResultEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthRunEntity.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>

/**
 * M5バー時刻の年に応じて通貨強弱の保存先DBを切り替えるサービス。
 */
class CurrencyStrengthYearlyPersistenceService {
public:
    /**
     * 保存先設定を指定して初期化する。
     *
     * @param fromBaseFileName 年を付与する前のファイル名。
     * @param fromSplitByYear 年単位で分割する場合true。
     * @param fromUseCommonFolder 共有フォルダを使用する場合true。
     */
    CurrencyStrengthYearlyPersistenceService(
        const string fromBaseFileName,
        const bool fromSplitByYear,
        const bool fromUseCommonFolder
    ) {
        this.baseFileName = fromBaseFileName;
        this.splitByYear = fromSplitByYear;
        this.useCommonFolder = fromUseCommonFolder;
        this.activeYear = 0;
        this.maximumOpenedYear = 0;
        this.activeFileName = "";
        this.context = NULL;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * デストラクタ。
     */
    ~CurrencyStrengthYearlyPersistenceService() {
        this.close();
    }

    /**
     * 指定M5バー時刻に対応する保存先DBを準備する。
     *
     * @param fromM5BarTime 保存対象のM5バー時刻。
     * @return 準備に成功した場合true。
     */
    bool openFor(const datetime fromM5BarTime) {
        string resolvedFileName = "";
        int resolvedYear = CurrencyStrengthDatabaseFileResolver::getYear(
            fromM5BarTime
        );

        if (resolvedYear <= 0
                || !CurrencyStrengthDatabaseFileResolver::resolveFileName(
            this.baseFileName,
            this.splitByYear,
            fromM5BarTime,
            resolvedFileName
        )) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "database file resolution failed. base=%s m5=%s",
                    this.baseFileName,
                    TimeToString(fromM5BarTime, TIME_DATE | TIME_MINUTES)
                )
            );

            return false;
        }

        if (this.context != NULL
                && this.context.isReady()
                && this.activeFileName == resolvedFileName) {
            this.activeYear = resolvedYear;

            if (resolvedYear > this.maximumOpenedYear) {
                this.maximumOpenedYear = resolvedYear;
            }

            return true;
        }

        CurrencyStrengthDatabaseContext *nextContext =
            new CurrencyStrengthDatabaseContext(
                resolvedFileName,
                this.useCommonFolder
            );

        if (nextContext == NULL || !nextContext.open()) {
            if (nextContext != NULL) {
                delete nextContext;
                nextContext = NULL;
            }

            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "database context preparation failed. fileName=%s",
                    resolvedFileName
                )
            );

            return false;
        }

        CurrencyStrengthDatabaseContext *previousContext = this.context;
        this.context = nextContext;
        this.activeFileName = resolvedFileName;
        this.activeYear = resolvedYear;

        if (resolvedYear > this.maximumOpenedYear) {
            this.maximumOpenedYear = resolvedYear;
        }

        if (previousContext != NULL) {
            delete previousContext;
            previousContext = NULL;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "currency strength database selected. year=%d fileName=%s",
                this.activeYear,
                this.activeFileName
            )
        );

        return true;
    }

    /**
     * 1回分の通貨強弱集計を対象年DBへ保存する。
     *
     * @param fromCalculatedAt 集計時刻。
     * @param fromM5BarTime M5現在足の開始時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 口座サーバー名。
     * @param fromSourceLogin 口座ログイン番号。
     * @param fromSourceChartId 保存元チャートID。
     * @param fromCalculator 保存対象の集計結果。
     * @return 保存に成功した場合true。
     */
    bool save(
        const datetime fromCalculatedAt,
        const datetime fromM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        const long fromSourceChartId,
        CurrencyStrengthCalculator *fromCalculator
    ) {
        if (!this.openFor(fromM5BarTime)) {
            return false;
        }

        CurrencyStrengthPersistenceService *persistenceService =
            this.context.getPersistenceService();

        if (persistenceService == NULL) {
            return false;
        }

        return persistenceService.save(
            fromCalculatedAt,
            fromM5BarTime,
            fromCalculationVersion,
            fromSourceMode,
            fromSourceServer,
            fromSourceLogin,
            fromSourceChartId,
            fromCalculator
        );
    }

    /**
     * 1回分の集計エンティティを対象年DBへ保存する。
     *
     * @param fromRunEntity 集計単位エンティティ。
     * @param fromVoteEntities 票内訳エンティティ一覧。
     * @param fromResultEntities 通貨別結果エンティティ一覧。
     * @return 保存に成功した場合true。
     */
    bool saveSnapshot(
        CurrencyStrengthRunEntity &fromRunEntity,
        CurrencyStrengthPairVoteEntity &fromVoteEntities[],
        CurrencyStrengthResultEntity &fromResultEntities[]
    ) {
        if (!this.openFor(fromRunEntity.m5BarTime)) {
            return false;
        }

        CurrencyStrengthPersistenceService *persistenceService =
            this.context.getPersistenceService();

        if (persistenceService == NULL) {
            return false;
        }

        return persistenceService.saveSnapshot(
            fromRunEntity,
            fromVoteEntities,
            fromResultEntities
        );
    }

    /**
     * 全年別DBから指定時刻より古い通貨強弱集計を削除する。
     *
     * @param fromCalculatedAt 削除境界時刻。
     * @param fromSourceMode 削除対象の集計実行モード。
     * @return 削除に成功した場合true。
     */
    bool deleteRunsBefore(
        const datetime fromCalculatedAt,
        const string fromSourceMode
    ) {
        if (this.context == NULL
                || !this.context.isReady()
                || fromCalculatedAt <= 0) {
            return false;
        }

        if (!this.splitByYear) {
            CurrencyStrengthPersistenceService *persistenceService =
                this.context.getPersistenceService();

            if (persistenceService == NULL) {
                return false;
            }

            return persistenceService.deleteRunsBefore(
                fromCalculatedAt,
                fromSourceMode
            );
        }

        for (int i = 1970; i <= this.maximumOpenedYear; i++) {
            if (!this.deleteRunsBeforeForYear(
                i,
                fromCalculatedAt,
                fromSourceMode
            )) {
                return false;
            }
        }

        return true;
    }

    /**
     * データベース関連リソースを解放する。
     */
    void close() {
        if (this.context != NULL) {
            delete this.context;
            this.context = NULL;
        }

        this.activeYear = 0;
        this.maximumOpenedYear = 0;
        this.activeFileName = "";
    }

    /**
     * 現在選択している年を取得する。
     *
     * @return 西暦年。未選択の場合は0。
     */
    int getActiveYear() const {
        return this.activeYear;
    }

    /**
     * 現在選択しているファイル名を取得する。
     *
     * @return ファイル名。未選択の場合は空文字列。
     */
    string getActiveFileName() const {
        return this.activeFileName;
    }

private:
    /** 年を付与する前のファイル名。 */
    string baseFileName;

    /** 年単位のファイル分割有無。 */
    bool splitByYear;

    /** 共有フォルダ使用有無。 */
    bool useCommonFolder;

    /** 現在選択している年。 */
    int activeYear;

    /** 現在までに選択した最大年。 */
    int maximumOpenedYear;

    /** 現在選択しているファイル名。 */
    string activeFileName;

    /** 現在選択しているDBコンテキスト。 */
    CurrencyStrengthDatabaseContext *context;

    /** ロガー。 */
    Logger logger;

    /**
     * 指定年DBから古い集計を削除する。
     *
     * @param fromYear 対象年。
     * @param fromCalculatedAt 削除境界時刻。
     * @param fromSourceMode 削除対象の集計実行モード。
     * @return 削除に成功した場合true。
     */
    bool deleteRunsBeforeForYear(
        const int fromYear,
        const datetime fromCalculatedAt,
        const string fromSourceMode
    ) {
        if (fromYear == this.activeYear) {
            CurrencyStrengthPersistenceService *persistenceService =
                this.context.getPersistenceService();

            if (persistenceService == NULL) {
                return false;
            }

            return persistenceService.deleteRunsBefore(
                fromCalculatedAt,
                fromSourceMode
            );
        }

        string fileName = "";

        if (!CurrencyStrengthDatabaseFileResolver::resolveFileNameForYear(
            this.baseFileName,
            fromYear,
            fileName
        )) {
            return false;
        }

        int fileFlags = 0;

        if (this.useCommonFolder) {
            fileFlags = FILE_COMMON;
        }

        if (!FileIsExist(fileName, fileFlags)) {
            return true;
        }

        SqliteDatabase cleanupDatabase(fileName, this.useCommonFolder);

        if (!cleanupDatabase.open()) {
            return false;
        }

        ResetLastError();

        if (!DatabaseExecute(
            cleanupDatabase.getHandle(),
            "PRAGMA foreign_keys = ON"
        )) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "foreign key activation failed. fileName=%s error=%d",
                    fileName,
                    GetLastError()
                )
            );
            cleanupDatabase.close();

            return false;
        }

        CurrencyStrengthRunDao cleanupRunDao(cleanupDatabase.getHandle());
        bool isDeleted = cleanupRunDao.deleteBefore(
            fromCalculatedAt,
            fromSourceMode
        );
        cleanupDatabase.close();

        return isDeleted;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_YEARLY_PERSISTENCE_SERVICE_MQH
