//+------------------------------------------------------------------+
//|                    CurrencyStrengthPersistenceService.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_PERSISTENCE_SERVICE_MQH
#define MSTNG_CURRENCY_STRENGTH_PERSISTENCE_SERVICE_MQH

#include <Mstng\Database\Dao\CurrencyStrengthDao.mqh>
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
     * 使用するDAOを指定して初期化する。
     *
     * @param fromCurrencyStrengthDao 通貨強弱DAO。
     */
    CurrencyStrengthPersistenceService(
        CurrencyStrengthDao *fromCurrencyStrengthDao
    ) {
        this.currencyStrengthDao = fromCurrencyStrengthDao;
        this.logger.setLevel(LOG_INFO);
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
        if (this.currencyStrengthDao == NULL) {
            this.logger.error(__FUNCTION__, "currencyStrengthDao is NULL.");

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

        return this.currencyStrengthDao.saveSnapshot(
            runEntity,
            voteEntities,
            resultEntities
        );
    }

    /**
     * 指定時刻より古い通貨強弱集計を削除する。
     *
     * @param fromCalculatedAt 削除境界時刻。
     * @return 削除に成功した場合true。
     */
    bool deleteRunsBefore(const datetime fromCalculatedAt) {
        if (this.currencyStrengthDao == NULL) {
            this.logger.error(__FUNCTION__, "currencyStrengthDao is NULL.");

            return false;
        }

        return this.currencyStrengthDao.deleteRunsBefore(fromCalculatedAt);
    }

private:
    /** 通貨強弱DAO。 */
    CurrencyStrengthDao *currencyStrengthDao;

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
            fromEntities[i].d1Score = (int)currencyStrengthInfo.getScore(0);
            fromEntities[i].h4Score = (int)currencyStrengthInfo.getScore(1);
            fromEntities[i].h1Score = (int)currencyStrengthInfo.getScore(2);
            fromEntities[i].m15Score = (int)currencyStrengthInfo.getScore(3);
            fromEntities[i].totalScore = (int)currencyStrengthInfo.getTotalScore();
            fromEntities[i].d1SampleCount = currencyStrengthInfo.getSampleCount(0);
            fromEntities[i].h4SampleCount = currencyStrengthInfo.getSampleCount(1);
            fromEntities[i].h1SampleCount = currencyStrengthInfo.getSampleCount(2);
            fromEntities[i].m15SampleCount = currencyStrengthInfo.getSampleCount(3);
            fromEntities[i].totalSampleCount =
                currencyStrengthInfo.getTotalSampleCount();
        }

        return true;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_PERSISTENCE_SERVICE_MQH
