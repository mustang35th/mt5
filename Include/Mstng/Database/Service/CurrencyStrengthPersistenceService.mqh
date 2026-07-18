//+------------------------------------------------------------------+
//|                    CurrencyStrengthPersistenceService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_PERSISTENCE_SERVICE_MQH
#define MSTNG_CURRENCY_STRENGTH_PERSISTENCE_SERVICE_MQH

#include <Mstng\Database\Dao\CurrencyStrengthPairVoteDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthResultDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthRunDao.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthPairVoteEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthResultEntity.mqh>
#include <Mstng\Database\Entity\CurrencyStrengthRunEntity.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>
#include <Mstng\Strength\CurrencyStrengthInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairVote.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 通貨強弱の集計履歴をデータベース保存形式へ変換するサービス。
 */
class CurrencyStrengthPersistenceService {
public:
    /**
     * データベースハンドルと使用する3 DAOを指定して初期化する。
     *
     * @param fromDatabaseHandle データベースハンドル。
     * @param fromRunDao 集計単位DAO。
     * @param fromPairVoteDao 票内訳DAO。
     * @param fromResultDao 通貨別結果DAO。
     */
    CurrencyStrengthPersistenceService(
        const int fromDatabaseHandle,
        CurrencyStrengthRunDao *fromRunDao,
        CurrencyStrengthPairVoteDao *fromPairVoteDao,
        CurrencyStrengthResultDao *fromResultDao
    ) {
        this.databaseHandle = fromDatabaseHandle;
        this.runDao = fromRunDao;
        this.pairVoteDao = fromPairVoteDao;
        this.resultDao = fromResultDao;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 通貨強弱のテーブル、インデックス、確認用ビューを準備する。
     *
     * @return 全データベースオブジェクトを準備できた場合true。
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

        if (!this.pairVoteDao.createTable()) {
            return false;
        }

        if (!this.resultDao.createTable()) {
            return false;
        }

        return this.pairVoteDao.createContributionsView();
    }

    /**
     * 1回分の通貨強弱集計を保存する。
     *
     * @param fromCalculatedAt 集計時刻。
     * @param fromM15BarTime M15現在足の開始時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceServer 口座サーバー名。
     * @param fromSourceLogin 口座ログイン番号。
     * @param fromSourceChartId 保存元チャートID。
     * @param fromCalculator 保存対象の集計結果。
     * @return 保存に成功した場合true。
     */
    bool save(
        const datetime fromCalculatedAt,
        const datetime fromM15BarTime,
        const string fromCalculationVersion,
        const string fromSourceServer,
        const long fromSourceLogin,
        const long fromSourceChartId,
        CurrencyStrengthCalculator *fromCalculator
    ) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        if (fromCalculator == NULL) {
            this.logger.error(__FUNCTION__, "fromCalculator is NULL.");

            return false;
        }

        int expectedVoteCount = fromCalculator.validPairCount
            * fromCalculator.getTimeFrameCount();

        if (fromCalculator.getPairVoteCount() != expectedVoteCount) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "invalid vote count. expected=%d actual=%d",
                    expectedVoteCount,
                    fromCalculator.getPairVoteCount()
                )
            );

            return false;
        }

        CurrencyStrengthRunEntity runEntity;
        this.buildRunEntity(
            fromCalculatedAt,
            fromM15BarTime,
            fromCalculationVersion,
            fromSourceServer,
            fromSourceLogin,
            fromSourceChartId,
            fromCalculator,
            runEntity
        );

        CurrencyStrengthPairVoteEntity voteEntities[];

        if (!this.buildVoteEntities(fromCalculator, voteEntities)) {
            return false;
        }

        CurrencyStrengthResultEntity resultEntities[];

        if (!this.buildResultEntities(fromCalculator, resultEntities)) {
            return false;
        }

        return this.saveSnapshot(
            runEntity,
            voteEntities,
            resultEntities
        );
    }

    /**
     * 1回分の集計、票内訳、通貨別結果をトランザクション保存する。
     *
     * @param fromRunEntity 集計単位エンティティ。
     * @param fromVoteEntities 票内訳エンティティ一覧。
     * @param fromResultEntities 通貨別結果エンティティ一覧。
     * @return 全レコードを保存できた場合true。
     */
    bool saveSnapshot(
        CurrencyStrengthRunEntity &fromRunEntity,
        CurrencyStrengthPairVoteEntity &fromVoteEntities[],
        CurrencyStrengthResultEntity &fromResultEntities[]
    ) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        if (!this.setSnapshotUpdatedAt(
            fromRunEntity,
            fromVoteEntities,
            fromResultEntities
        )) {
            return false;
        }

        fromRunEntity.id = 0;
        fromRunEntity.voteCount = ArraySize(fromVoteEntities);

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

        bool isSaved = this.runDao.insert(fromRunEntity);

        if (isSaved) {
            this.setVoteRunIds(fromRunEntity.id, fromVoteEntities);
            this.setResultRunIds(fromRunEntity.id, fromResultEntities);
            isSaved = this.pairVoteDao.insertAll(fromVoteEntities);
        }

        if (isSaved) {
            isSaved = this.resultDao.insertAll(fromResultEntities);
        }

        if (!isSaved) {
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromRunEntity,
                fromVoteEntities,
                fromResultEntities
            );

            return false;
        }

        ResetLastError();

        if (!DatabaseTransactionCommit(this.databaseHandle)) {
            int commitErrorCode = GetLastError();
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseTransactionCommit failed. error=%d",
                    commitErrorCode
                )
            );
            this.rollbackTransaction(__FUNCTION__);
            this.clearSnapshotIds(
                fromRunEntity,
                fromVoteEntities,
                fromResultEntities
            );

            return false;
        }

        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "Snapshot saved. runId=%I64d votes=%d results=%d",
                fromRunEntity.id,
                ArraySize(fromVoteEntities),
                ArraySize(fromResultEntities)
            )
        );

        return true;
    }

    /**
     * 指定時刻より古い通貨強弱集計を削除する。
     *
     * @param fromCalculatedAt 削除境界時刻。
     * @return 削除に成功した場合true。
     */
    bool deleteRunsBefore(const datetime fromCalculatedAt) {
        if (!this.isReady(__FUNCTION__)) {
            return false;
        }

        return this.runDao.deleteBefore(fromCalculatedAt);
    }

private:
    /** データベースハンドル。 */
    int databaseHandle;

    /** 集計単位DAO。 */
    CurrencyStrengthRunDao *runDao;

    /** 票内訳DAO。 */
    CurrencyStrengthPairVoteDao *pairVoteDao;

    /** 通貨別結果DAO。 */
    CurrencyStrengthResultDao *resultDao;

    /** ロガー。 */
    Logger logger;

    /**
     * 集計単位エンティティを生成する。
     *
     * @param fromCalculatedAt 集計時刻。
     * @param fromM15BarTime M15現在足の開始時刻。
     * @param fromCalculationVersion 集計ルール識別子。
     * @param fromSourceServer 口座サーバー名。
     * @param fromSourceLogin 口座ログイン番号。
     * @param fromSourceChartId 保存元チャートID。
     * @param fromCalculator 保存対象の集計結果。
     * @param fromEntity 生成結果の格納先。
     */
    void buildRunEntity(
        const datetime fromCalculatedAt,
        const datetime fromM15BarTime,
        const string fromCalculationVersion,
        const string fromSourceServer,
        const long fromSourceLogin,
        const long fromSourceChartId,
        CurrencyStrengthCalculator *fromCalculator,
        CurrencyStrengthRunEntity &fromEntity
    ) {
        fromEntity.id = 0;
        fromEntity.calculatedAt = fromCalculatedAt;
        fromEntity.m15BarTime = fromM15BarTime;
        fromEntity.calculationVersion = fromCalculationVersion;
        fromEntity.sourceServer = fromSourceServer;
        fromEntity.sourceLogin = fromSourceLogin;
        fromEntity.sourceChartId = fromSourceChartId;
        fromEntity.expectedPairCount = fromCalculator.getExpectedPairCount();
        fromEntity.validPairCount = fromCalculator.validPairCount;
        fromEntity.voteCount = fromCalculator.getPairVoteCount();
        fromEntity.isComplete = 0;

        if (fromEntity.validPairCount == fromEntity.expectedPairCount) {
            fromEntity.isComplete = 1;
        }

        fromEntity.updatedAt = 0;
        fromEntity.updatedAtText = "";
    }

    /**
     * 票エンティティ一覧を生成する。
     *
     * @param fromCalculator 保存対象の集計結果。
     * @param fromEntities 生成結果の格納先。
     * @return 生成に成功した場合true。
     */
    bool buildVoteEntities(
        CurrencyStrengthCalculator *fromCalculator,
        CurrencyStrengthPairVoteEntity &fromEntities[]
    ) {
        int total = fromCalculator.getPairVoteCount();

        if (ArrayResize(fromEntities, total) != total) {
            this.logger.error(__FUNCTION__, "fromEntities ArrayResize failed.");

            return false;
        }

        for (int i = 0; i < total; i++) {
            CurrencyStrengthPairVote pairVote;

            if (!fromCalculator.getPairVote(i, pairVote)) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat("getPairVote failed. index=%d", i)
                );

                return false;
            }

            fromEntities[i].id = 0;
            fromEntities[i].runId = 0;
            fromEntities[i].pairOrder = pairVote.pairOrder;
            fromEntities[i].timeFrameOrder = pairVote.timeFrameOrder;
            fromEntities[i].canonicalSymbolName = pairVote.canonicalSymbolName;
            fromEntities[i].resolvedSymbolName = pairVote.resolvedSymbolName;
            fromEntities[i].timeFrame = (int)pairVote.timeFrame;
            fromEntities[i].timeFrameText =
                TimeUtil::convertTimeFrameToString(pairVote.timeFrame);
            fromEntities[i].barTime = pairVote.barTime;
            fromEntities[i].barTimeText = TimeToString(
                pairVote.barTime,
                TIME_DATE | TIME_SECONDS
            );
            fromEntities[i].baseCurrency = pairVote.baseCurrency;
            fromEntities[i].quoteCurrency = pairVote.quoteCurrency;
            fromEntities[i].isBuy = 0;

            if (pairVote.isBuy) {
                fromEntities[i].isBuy = 1;
            }

            fromEntities[i].oscillatorCount = pairVote.oscillatorCount;
            fromEntities[i].baseScore = pairVote.baseScore;
            fromEntities[i].baseScoreAfter = pairVote.baseScoreAfter;
            fromEntities[i].quoteScoreAfter = pairVote.quoteScoreAfter;
            fromEntities[i].updatedAt = 0;
            fromEntities[i].updatedAtText = "";
        }

        return true;
    }

    /**
     * 通貨別結果エンティティ一覧を生成する。
     *
     * @param fromCalculator 保存対象の集計結果。
     * @param fromEntities 生成結果の格納先。
     * @return 生成に成功した場合true。
     */
    bool buildResultEntities(
        CurrencyStrengthCalculator *fromCalculator,
        CurrencyStrengthResultEntity &fromEntities[]
    ) {
        int total = fromCalculator.size();

        if (ArrayResize(fromEntities, total) != total) {
            this.logger.error(__FUNCTION__, "fromEntities ArrayResize failed.");

            return false;
        }

        for (int i = 0; i < total; i++) {
            CurrencyStrengthInfo *currencyStrengthInfo = fromCalculator.getInfo(i);

            if (currencyStrengthInfo == NULL) {
                this.logger.error(
                    __FUNCTION__,
                    StringFormat("currencyStrengthInfo is NULL. index=%d", i)
                );

                return false;
            }

            fromEntities[i].id = 0;
            fromEntities[i].runId = 0;
            fromEntities[i].currencyName = currencyStrengthInfo.currencyName;
            fromEntities[i].mn1Score = (int)currencyStrengthInfo.getScore(0);
            fromEntities[i].w1Score = (int)currencyStrengthInfo.getScore(1);
            fromEntities[i].d1Score = (int)currencyStrengthInfo.getScore(2);
            fromEntities[i].h4Score = (int)currencyStrengthInfo.getScore(3);
            fromEntities[i].h1Score = (int)currencyStrengthInfo.getScore(4);
            fromEntities[i].m15Score = (int)currencyStrengthInfo.getScore(5);
            fromEntities[i].totalScore = (int)currencyStrengthInfo.getTotalScore();
            fromEntities[i].mn1SampleCount = currencyStrengthInfo.getSampleCount(0);
            fromEntities[i].w1SampleCount = currencyStrengthInfo.getSampleCount(1);
            fromEntities[i].d1SampleCount = currencyStrengthInfo.getSampleCount(2);
            fromEntities[i].h4SampleCount = currencyStrengthInfo.getSampleCount(3);
            fromEntities[i].h1SampleCount = currencyStrengthInfo.getSampleCount(4);
            fromEntities[i].m15SampleCount = currencyStrengthInfo.getSampleCount(5);
            fromEntities[i].totalSampleCount =
                currencyStrengthInfo.getTotalSampleCount();
            fromEntities[i].updatedAt = 0;
            fromEntities[i].updatedAtText = "";
        }

        return true;
    }

    /**
     * スナップショット全体へ同一のレコード更新時刻を設定する。
     *
     * @param fromRunEntity 集計単位エンティティ。
     * @param fromVoteEntities 票内訳エンティティ一覧。
     * @param fromResultEntities 通貨別結果エンティティ一覧。
     * @return 更新時刻を設定できた場合true。
     */
    bool setSnapshotUpdatedAt(
        CurrencyStrengthRunEntity &fromRunEntity,
        CurrencyStrengthPairVoteEntity &fromVoteEntities[],
        CurrencyStrengthResultEntity &fromResultEntities[]
    ) {
        datetime updatedAt = TimeLocal();

        if (updatedAt <= 0) {
            updatedAt = TimeCurrent();
        }

        if (updatedAt <= 0) {
            this.logger.error(__FUNCTION__, "updatedAt could not be obtained.");

            return false;
        }

        string updatedAtText = TimeToString(
            updatedAt,
            TIME_DATE | TIME_SECONDS
        );
        fromRunEntity.updatedAt = updatedAt;
        fromRunEntity.updatedAtText = updatedAtText;

        int voteCount = ArraySize(fromVoteEntities);

        for (int i = 0; i < voteCount; i++) {
            fromVoteEntities[i].updatedAt = updatedAt;
            fromVoteEntities[i].updatedAtText = updatedAtText;
        }

        int resultCount = ArraySize(fromResultEntities);

        for (int i = 0; i < resultCount; i++) {
            fromResultEntities[i].updatedAt = updatedAt;
            fromResultEntities[i].updatedAtText = updatedAtText;
        }

        return true;
    }

    /**
     * SQLiteの外部キー制約を有効化する。
     *
     * @return 外部キー制約を有効化できた場合true。
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
     * 票内訳配列へ集計IDを設定する。
     *
     * @param fromRunId 集計ID。
     * @param fromEntities 設定対象エンティティ配列。
     */
    void setVoteRunIds(
        const long fromRunId,
        CurrencyStrengthPairVoteEntity &fromEntities[]
    ) {
        int entityCount = ArraySize(fromEntities);

        for (int i = 0; i < entityCount; i++) {
            fromEntities[i].runId = fromRunId;
        }
    }

    /**
     * 通貨別結果配列へ集計IDを設定する。
     *
     * @param fromRunId 集計ID。
     * @param fromEntities 設定対象エンティティ配列。
     */
    void setResultRunIds(
        const long fromRunId,
        CurrencyStrengthResultEntity &fromEntities[]
    ) {
        int entityCount = ArraySize(fromEntities);

        for (int i = 0; i < entityCount; i++) {
            fromEntities[i].runId = fromRunId;
        }
    }

    /**
     * 保存失敗時に集計IDをクリアする。
     *
     * @param fromRunEntity 集計エンティティ。
     * @param fromVoteEntities 票内訳エンティティ配列。
     * @param fromResultEntities 通貨別結果エンティティ配列。
     */
    void clearSnapshotIds(
        CurrencyStrengthRunEntity &fromRunEntity,
        CurrencyStrengthPairVoteEntity &fromVoteEntities[],
        CurrencyStrengthResultEntity &fromResultEntities[]
    ) {
        fromRunEntity.id = 0;
        this.setVoteRunIds(0, fromVoteEntities);
        this.setResultRunIds(0, fromResultEntities);
    }

    /**
     * 実行中のトランザクションをロールバックする。
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
     * データベースハンドルと3 DAOが利用可能か確認する。
     *
     * @param fromMethodName 呼び出し元メソッド名。
     * @return 利用可能な場合true。
     */
    bool isReady(const string fromMethodName) {
        if (this.databaseHandle == INVALID_HANDLE) {
            this.logger.error(fromMethodName, "databaseHandle is INVALID_HANDLE.");

            return false;
        }

        if (this.runDao == NULL) {
            this.logger.error(fromMethodName, "runDao is NULL.");

            return false;
        }

        if (this.pairVoteDao == NULL) {
            this.logger.error(fromMethodName, "pairVoteDao is NULL.");

            return false;
        }

        if (this.resultDao == NULL) {
            this.logger.error(fromMethodName, "resultDao is NULL.");

            return false;
        }

        return true;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_PERSISTENCE_SERVICE_MQH
