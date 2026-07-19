//+------------------------------------------------------------------+
//|             CurrencyStrengthYearlyRankQueryService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_YEARLY_RANK_QUERY_SERVICE_MQH
#define MSTNG_CURRENCY_STRENGTH_YEARLY_RANK_QUERY_SERVICE_MQH

#include <Mstng\Database\CurrencyStrengthDatabaseFileResolver.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthResultDao.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>

/**
 * M5バー時刻の年に応じて通貨強弱順位の参照元DBを切り替えるサービス。
 *
 * データベースは読み取り専用で開き、テーブル作成や移行は行わない。
 * 対象年に該当レコードがない場合は前年DBも検索する。
 */
class CurrencyStrengthYearlyRankQueryService {
public:
    /**
     * 参照元設定を指定して初期化する。
     *
     * @param fromBaseFileName 年を付与する前のファイル名。
     * @param fromSplitByYear 年単位で分割する場合true。
     * @param fromUseCommonFolder 共有フォルダを使用する場合true。
     */
    CurrencyStrengthYearlyRankQueryService(
        const string fromBaseFileName,
        const bool fromSplitByYear,
        const bool fromUseCommonFolder
    ) {
        this.baseFileName = fromBaseFileName;
        this.splitByYear = fromSplitByYear;
        this.useCommonFolder = fromUseCommonFolder;
        this.activeYear = 0;
        this.activeFileName = "";
        this.database = NULL;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * デストラクタ。
     */
    ~CurrencyStrengthYearlyRankQueryService() {
        this.close();
    }

    /**
     * 指定時刻以前の最新完全集計から通貨ペアの順位を取得する。
     *
     * @param fromTargetM5BarTime 検索上限となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromInfo 取得結果の格納先。
     * @return 通貨ペア順位検索の結果状態。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS findLatestPairRanksAtOrBefore(
        const datetime fromTargetM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        CurrencyStrengthPairRankInfo &fromInfo
    ) {
        fromInfo.reset();
        int targetYear = CurrencyStrengthDatabaseFileResolver::getYear(
            fromTargetM5BarTime
        );
        bool databaseExists = false;

        if (!this.openFor(fromTargetM5BarTime, databaseExists)) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS currentYearStatus =
            CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND;

        if (databaseExists) {
            currentYearStatus = this.findLatestPairRanksInActiveDatabase(
                fromTargetM5BarTime,
                fromCalculationVersion,
                fromSourceMode,
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                fromInfo
            );
        }

        if (currentYearStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
                || currentYearStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR
                || !this.splitByYear
                || targetYear <= 1970) {
            return currentYearStatus;
        }

        bool previousDatabaseExists = false;

        if (!this.openForYear(targetYear - 1, previousDatabaseExists)) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS previousYearStatus =
            CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND;

        if (previousDatabaseExists) {
            previousYearStatus = this.findLatestPairRanksInActiveDatabase(
                fromTargetM5BarTime,
                fromCalculationVersion,
                fromSourceMode,
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                fromInfo
            );
        }

        if (previousYearStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
                || previousYearStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            return previousYearStatus;
        }

        if (currentYearStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND
                || previousYearStatus
                    == CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND;
        }

        return CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND;
    }

    /**
     * データベース関連リソースを解放する。
     */
    void close() {
        if (this.database != NULL) {
            delete this.database;
            this.database = NULL;
        }

        this.activeYear = 0;
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

    /** 現在選択しているファイル名。 */
    string activeFileName;

    /** 現在選択している読み取り専用データベース。 */
    SqliteDatabase *database;

    /** ロガー。 */
    Logger logger;

    /**
     * 現在開いているDBから指定時刻以前の最新順位を取得する。
     *
     * @param fromTargetM5BarTime 検索上限となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromInfo 取得結果の格納先。
     * @return 通貨ペア順位検索の結果状態。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS findLatestPairRanksInActiveDatabase(
        const datetime fromTargetM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        CurrencyStrengthPairRankInfo &fromInfo
    ) {
        if (this.database == NULL || !this.database.isOpen()) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        CurrencyStrengthResultDao resultDao(this.database.getHandle());
        bool isFound = false;

        if (!resultDao.findLatestPairRanksAtOrBefore(
            fromTargetM5BarTime,
            fromCalculationVersion,
            fromSourceMode,
            fromSourceServer,
            fromSourceLogin,
            fromBaseCurrency,
            fromQuoteCurrency,
            fromInfo,
            isFound
        )) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        if (!isFound) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND;
        }

        return CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND;
    }

    /**
     * 指定M5バー時刻に対応する参照元DBを読み取り専用で開く。
     *
     * 対象ファイルが存在しない場合はエラーにせず、
     * fromDatabaseExistsへfalseを設定する。
     *
     * @param fromM5BarTime 検索上限となるM5バー時刻。
     * @param fromDatabaseExists 対象DBが存在する場合true。
     * @return ファイル解決とオープン判定に成功した場合true。
     */
    bool openFor(
        const datetime fromM5BarTime,
        bool &fromDatabaseExists
    ) {
        fromDatabaseExists = false;
        int resolvedYear = CurrencyStrengthDatabaseFileResolver::getYear(
            fromM5BarTime
        );

        if (resolvedYear <= 0) {
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

        return this.openForYear(resolvedYear, fromDatabaseExists);
    }

    /**
     * 指定年に対応する参照元DBを読み取り専用で開く。
     *
     * 対象ファイルが存在しない場合はエラーにせず、
     * fromDatabaseExistsへfalseを設定する。
     *
     * @param fromYear 参照対象年。
     * @param fromDatabaseExists 対象DBが存在する場合true。
     * @return ファイル解決とオープン判定に成功した場合true。
     */
    bool openForYear(
        const int fromYear,
        bool &fromDatabaseExists
    ) {
        fromDatabaseExists = false;
        string resolvedFileName = this.baseFileName;

        if (this.splitByYear
                && !CurrencyStrengthDatabaseFileResolver::resolveFileNameForYear(
            this.baseFileName,
            fromYear,
            resolvedFileName
        )) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "database file resolution failed. base=%s year=%d",
                    this.baseFileName,
                    fromYear
                )
            );

            return false;
        }

        if (resolvedFileName == "" || fromYear < 1970) {
            return false;
        }

        if (this.database != NULL
                && this.database.isOpen()
                && this.activeFileName == resolvedFileName) {
            this.activeYear = fromYear;
            fromDatabaseExists = true;

            return true;
        }

        int fileFlags = 0;

        if (this.useCommonFolder) {
            fileFlags = FILE_COMMON;
        }

        if (!FileIsExist(resolvedFileName, fileFlags)) {
            return true;
        }

        SqliteDatabase *nextDatabase = new SqliteDatabase(
            resolvedFileName,
            this.useCommonFolder
        );

        if (nextDatabase == NULL || !nextDatabase.openReadOnly()) {
            if (nextDatabase != NULL) {
                delete nextDatabase;
                nextDatabase = NULL;
            }

            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "read-only database open failed. fileName=%s",
                    resolvedFileName
                )
            );

            return false;
        }

        SqliteDatabase *previousDatabase = this.database;
        this.database = nextDatabase;
        this.activeYear = fromYear;
        this.activeFileName = resolvedFileName;
        fromDatabaseExists = true;

        if (previousDatabase != NULL) {
            delete previousDatabase;
            previousDatabase = NULL;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "currency strength rank database selected. year=%d fileName=%s",
                this.activeYear,
                this.activeFileName
            )
        );

        return true;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_YEARLY_RANK_QUERY_SERVICE_MQH
