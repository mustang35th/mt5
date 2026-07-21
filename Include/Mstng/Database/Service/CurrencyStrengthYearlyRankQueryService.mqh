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
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankInfo.mqh>

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
     * 指定時刻以前の最新順位をLIVE優先で取得する。
     *
     * LIVEとTESTERのうちM5バー時刻が新しい結果を採用し、
     * 同じM5バー時刻に両方ある場合はLIVEを採用する。
     *
     * @param fromTargetM5BarTime 検索上限となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromInfo 取得結果の格納先。
     * @return 通貨ペア順位検索の結果状態。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS findLatestPairRanksAtOrBeforePreferLive(
        const datetime fromTargetM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        CurrencyStrengthPairRankInfo &fromInfo
    ) {
        fromInfo.reset();
        CurrencyStrengthPairRankInfo liveInfo;
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS liveStatus =
            this.findLatestPairRanksAtOrBefore(
                fromTargetM5BarTime,
                fromCalculationVersion,
                CurrencyStrengthCalculationProfile::getSourceMode(false),
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                liveInfo
            );

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            return liveStatus;
        }

        CurrencyStrengthPairRankInfo testerInfo;
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS testerStatus =
            this.findLatestPairRanksAtOrBefore(
                fromTargetM5BarTime,
                fromCalculationVersion,
                CurrencyStrengthCalculationProfile::getSourceMode(true),
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                testerInfo
            );

        if (testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            return testerStatus;
        }

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
                && testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            if (testerInfo.m5BarTime > liveInfo.m5BarTime) {
                fromInfo = testerInfo;
            } else {
                fromInfo = liveInfo;
            }

            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND;
        }

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            fromInfo = liveInfo;

            return liveStatus;
        }

        if (testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            fromInfo = testerInfo;

            return testerStatus;
        }

        return this.combineNotFoundStatuses(liveStatus, testerStatus);
    }

    /**
     * 現在開いているDBから指定した集計IDの全通貨順位を取得する。
     *
     * @param fromRunId 取得対象の集計ID。
     * @param fromRanks 取得結果の格納先。
     * @return 通貨順位検索の結果状態。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS findRanksByRunId(
        const long fromRunId,
        CurrencyStrengthRankInfo &fromRanks[]
    ) {
        ArrayResize(fromRanks, 0);

        if (this.database == NULL || !this.database.isOpen()) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        CurrencyStrengthResultDao resultDao(this.database.getHandle());
        bool isFound = false;

        if (!resultDao.findRanksByRunId(
            fromRunId,
            fromRanks,
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
     * 指定期間の完全集計から通貨ペアの順位を時刻昇順で取得する。
     *
     * 年別分割を使用している場合は、開始年から終了年までのDBを
     * 読み取り専用で順番に参照する。存在しない年のDBはスキップする。
     *
     * @param fromStartM5BarTime 検索開始となるM5バー時刻。
     * @param fromEndM5BarTime 検索終了となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromMaximumPointCount 取得を許可する最大件数。
     * @param fromPoints 取得結果の格納先。
     * @return 通貨ペア順位検索の結果状態。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS findPairRankPointsInRange(
        const datetime fromStartM5BarTime,
        const datetime fromEndM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        const int fromMaximumPointCount,
        CurrencyStrengthPairRankPoint &fromPoints[]
    ) {
        ArrayResize(fromPoints, 0);

        if (fromStartM5BarTime <= 0
                || fromEndM5BarTime < fromStartM5BarTime
                || fromCalculationVersion == ""
                || fromSourceMode == ""
                || fromBaseCurrency == ""
                || fromQuoteCurrency == ""
                || fromMaximumPointCount <= 0) {
            this.logger.error(__FUNCTION__, "search condition is invalid.");

            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        int startYear = CurrencyStrengthDatabaseFileResolver::getYear(
            fromStartM5BarTime
        );
        int endYear = CurrencyStrengthDatabaseFileResolver::getYear(
            fromEndM5BarTime
        );

        if (startYear <= 0 || endYear < startYear) {
            this.logger.error(__FUNCTION__, "search year is invalid.");

            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        bool databaseExists = false;

        if (!this.splitByYear) {
            if (!this.openFor(fromEndM5BarTime, databaseExists)) {
                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            }

            if (!databaseExists) {
                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND;
            }

            if (!this.findPairRankPointsInActiveDatabase(
                fromStartM5BarTime,
                fromEndM5BarTime,
                fromCalculationVersion,
                fromSourceMode,
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                fromMaximumPointCount,
                fromPoints
            )) {
                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            }

            if (ArraySize(fromPoints) > fromMaximumPointCount) {
                this.logPointLimitExceeded(
                    fromStartM5BarTime,
                    fromEndM5BarTime,
                    fromMaximumPointCount
                );
                ArrayResize(fromPoints, 0);

                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            }

            if (ArraySize(fromPoints) == 0) {
                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND;
            }

            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND;
        }

        bool anyDatabaseExists = false;

        for (int year = startYear; year <= endYear; year++) {
            databaseExists = false;

            if (!this.openForYear(year, databaseExists)) {
                ArrayResize(fromPoints, 0);

                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            }

            if (!databaseExists) {
                continue;
            }

            anyDatabaseExists = true;
            int currentPointCount = ArraySize(fromPoints);
            int remainingPointCount = (
                fromMaximumPointCount - currentPointCount
            );
            CurrencyStrengthPairRankPoint yearPoints[];

            if (!this.findPairRankPointsInActiveDatabase(
                fromStartM5BarTime,
                fromEndM5BarTime,
                fromCalculationVersion,
                fromSourceMode,
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                remainingPointCount,
                yearPoints
            )) {
                ArrayResize(fromPoints, 0);

                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            }

            if (ArraySize(yearPoints) > remainingPointCount) {
                this.logPointLimitExceeded(
                    fromStartM5BarTime,
                    fromEndM5BarTime,
                    fromMaximumPointCount
                );
                ArrayResize(fromPoints, 0);

                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            }

            if (!this.appendPoints(fromPoints, yearPoints)) {
                ArrayResize(fromPoints, 0);

                return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            }
        }

        if (ArraySize(fromPoints) > 0) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND;
        }

        if (anyDatabaseExists) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND;
        }

        return CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND;
    }

    /**
     * 指定期間の順位をLIVE優先で時刻昇順に取得する。
     *
     * 同じM5バー時刻にLIVEとTESTERの両方がある場合はLIVEを採用し、
     * LIVEがないM5バー時刻はTESTERで補完する。
     *
     * @param fromStartM5BarTime 検索開始となるM5バー時刻。
     * @param fromEndM5BarTime 検索終了となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromMaximumPointCount 取得を許可する最大件数。
     * @param fromPoints 取得結果の格納先。
     * @return 通貨ペア順位検索の結果状態。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS findPairRankPointsInRangePreferLive(
        const datetime fromStartM5BarTime,
        const datetime fromEndM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        const int fromMaximumPointCount,
        CurrencyStrengthPairRankPoint &fromPoints[]
    ) {
        ArrayResize(fromPoints, 0);
        CurrencyStrengthPairRankPoint livePoints[];
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS liveStatus =
            this.findPairRankPointsInRange(
                fromStartM5BarTime,
                fromEndM5BarTime,
                fromCalculationVersion,
                CurrencyStrengthCalculationProfile::getSourceMode(false),
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                fromMaximumPointCount,
                livePoints
            );

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            return liveStatus;
        }

        CurrencyStrengthPairRankPoint testerPoints[];
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS testerStatus =
            this.findPairRankPointsInRange(
                fromStartM5BarTime,
                fromEndM5BarTime,
                fromCalculationVersion,
                CurrencyStrengthCalculationProfile::getSourceMode(true),
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                fromMaximumPointCount,
                testerPoints
            );

        if (testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            return testerStatus;
        }

        if (!this.mergePairRankPointsPreferLive(
            livePoints,
            testerPoints,
            fromStartM5BarTime,
            fromEndM5BarTime,
            fromMaximumPointCount,
            fromPoints
        )) {
            ArrayResize(fromPoints, 0);

            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
        }

        if (ArraySize(fromPoints) > 0) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND;
        }

        return this.combineNotFoundStatuses(liveStatus, testerStatus);
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
     * LIVEとTESTERの未取得状態を1つの検索結果へまとめる。
     *
     * @param fromLiveStatus LIVE検索結果。
     * @param fromTesterStatus TESTER検索結果。
     * @return 統合後の未取得状態。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS combineNotFoundStatuses(
        const ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS fromLiveStatus,
        const ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS fromTesterStatus
    ) {
        if (fromLiveStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND
                && fromTesterStatus
                    == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND) {
            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND;
        }

        return CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND;
    }

    /**
     * LIVEとTESTERの時系列順位をM5バー時刻単位で統合する。
     *
     * @param fromLivePoints LIVE順位配列。
     * @param fromTesterPoints TESTER順位配列。
     * @param fromStartM5BarTime 検索開始となるM5バー時刻。
     * @param fromEndM5BarTime 検索終了となるM5バー時刻。
     * @param fromMaximumPointCount 取得を許可する最大件数。
     * @param fromDestination 統合結果の格納先。
     * @return 統合に成功した場合true。
     */
    bool mergePairRankPointsPreferLive(
        CurrencyStrengthPairRankPoint &fromLivePoints[],
        CurrencyStrengthPairRankPoint &fromTesterPoints[],
        const datetime fromStartM5BarTime,
        const datetime fromEndM5BarTime,
        const int fromMaximumPointCount,
        CurrencyStrengthPairRankPoint &fromDestination[]
    ) {
        ArrayResize(fromDestination, 0);
        int liveCount = ArraySize(fromLivePoints);
        int testerCount = ArraySize(fromTesterPoints);
        int maximumMergedCount = liveCount + testerCount;

        if (maximumMergedCount == 0) {
            return true;
        }

        if (ArrayResize(fromDestination, maximumMergedCount)
                != maximumMergedCount) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "ArrayResize failed. requested=%d",
                    maximumMergedCount
                )
            );

            return false;
        }

        int liveIndex = 0;
        int testerIndex = 0;
        int mergedCount = 0;

        while (liveIndex < liveCount || testerIndex < testerCount) {
            if (mergedCount >= fromMaximumPointCount) {
                this.logPointLimitExceeded(
                    fromStartM5BarTime,
                    fromEndM5BarTime,
                    fromMaximumPointCount
                );

                return false;
            }

            if (liveIndex >= liveCount) {
                fromDestination[mergedCount] = fromTesterPoints[testerIndex];
                testerIndex++;
            } else if (testerIndex >= testerCount) {
                fromDestination[mergedCount] = fromLivePoints[liveIndex];
                liveIndex++;
            } else if (fromLivePoints[liveIndex].m5BarTime
                    <= fromTesterPoints[testerIndex].m5BarTime) {
                fromDestination[mergedCount] = fromLivePoints[liveIndex];

                if (fromLivePoints[liveIndex].m5BarTime
                        == fromTesterPoints[testerIndex].m5BarTime) {
                    testerIndex++;
                }

                liveIndex++;
            } else {
                fromDestination[mergedCount] = fromTesterPoints[testerIndex];
                testerIndex++;
            }

            mergedCount++;
        }

        if (ArrayResize(fromDestination, mergedCount) != mergedCount) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("ArrayResize failed. requested=%d", mergedCount)
            );

            return false;
        }

        return true;
    }

    /**
     * 現在開いているDBから指定期間の順位を時刻昇順で取得する。
     *
     * @param fromStartM5BarTime 検索開始となるM5バー時刻。
     * @param fromEndM5BarTime 検索終了となるM5バー時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceMode 集計実行モード。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromMaximumPointCount 呼び出し元が受け入れる最大件数。
     * @param fromPoints 取得結果の格納先。
     * @return 検索処理に成功した場合true。
     */
    bool findPairRankPointsInActiveDatabase(
        const datetime fromStartM5BarTime,
        const datetime fromEndM5BarTime,
        const string fromCalculationVersion,
        const string fromSourceMode,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        const int fromMaximumPointCount,
        CurrencyStrengthPairRankPoint &fromPoints[]
    ) {
        ArrayResize(fromPoints, 0);

        if (this.database == NULL || !this.database.isOpen()) {
            return false;
        }

        CurrencyStrengthResultDao resultDao(this.database.getHandle());

        return resultDao.findPairRankPointsInRange(
            fromStartM5BarTime,
            fromEndM5BarTime,
            fromCalculationVersion,
            fromSourceMode,
            fromSourceServer,
            fromSourceLogin,
            fromBaseCurrency,
            fromQuoteCurrency,
            fromMaximumPointCount,
            fromPoints
        );
    }

    /**
     * 年別DBから取得した順位配列を結果配列の末尾へ追加する。
     *
     * @param fromDestination 追加先配列。
     * @param fromSource 追加元配列。
     * @return 追加に成功した場合true。
     */
    bool appendPoints(
        CurrencyStrengthPairRankPoint &fromDestination[],
        CurrencyStrengthPairRankPoint &fromSource[]
    ) {
        int destinationCount = ArraySize(fromDestination);
        int sourceCount = ArraySize(fromSource);

        if (sourceCount == 0) {
            return true;
        }

        int totalCount = destinationCount + sourceCount;

        if (ArrayResize(fromDestination, totalCount) != totalCount) {
            this.logger.error(
                __FUNCTION__,
                StringFormat("ArrayResize failed. requested=%d", totalCount)
            );

            return false;
        }

        for (int i = 0; i < sourceCount; i++) {
            fromDestination[destinationCount + i] = fromSource[i];
        }

        return true;
    }

    /**
     * 時系列順位の取得上限超過をログへ出力する。
     *
     * @param fromStartM5BarTime 検索開始となるM5バー時刻。
     * @param fromEndM5BarTime 検索終了となるM5バー時刻。
     * @param fromMaximumPointCount 取得を許可する最大件数。
     */
    void logPointLimitExceeded(
        const datetime fromStartM5BarTime,
        const datetime fromEndM5BarTime,
        const int fromMaximumPointCount
    ) {
        this.logger.error(
            __FUNCTION__,
            StringFormat(
                "currency strength rank point limit exceeded. "
                    + "start=%s end=%s maximum=%d",
                TimeToString(
                    fromStartM5BarTime,
                    TIME_DATE | TIME_MINUTES
                ),
                TimeToString(
                    fromEndM5BarTime,
                    TIME_DATE | TIME_MINUTES
                ),
                fromMaximumPointCount
            )
        );
    }

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
