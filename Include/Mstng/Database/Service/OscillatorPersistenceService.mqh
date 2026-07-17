//+------------------------------------------------------------------+
//|                                 OscillatorPersistenceService.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_DATABASE_SERVICE_OSCILLATOR_PERSISTENCE_SERVICE_MQH
#define MSTNG_DATABASE_SERVICE_OSCILLATOR_PERSISTENCE_SERVICE_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Dao\OscillatorDao.mqh>
#include <Mstng\Database\Entity\OscillatorEntity.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * オシレーター計算結果の保存処理を調整するサービス。
 */
class OscillatorPersistenceService {
public:
    /**
     * 使用するDAOを指定して初期化する。
     *
     * @param fromOscillatorDao オシレーターDAO。
     */
    OscillatorPersistenceService(OscillatorDao *fromOscillatorDao) {
        this.oscillatorDao = fromOscillatorDao;
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * オシレーター計算結果をエンティティへ変換して保存する。
     *
     * @param fromCalculatedAt 計算時刻。
     * @param fromMarketContext 市場コンテキスト。
     * @param fromOscillatorCount オシレーター総合判定値。
     * @param fromIsBuy BUYフラグ。
     * @return 保存に成功した場合はtrue。
     */
    bool save(
        const datetime fromCalculatedAt,
        MarketContext &fromMarketContext,
        const int fromOscillatorCount,
        const bool fromIsBuy
    ) {
        if (this.oscillatorDao == NULL) {
            this.logger.error(__FUNCTION__, "oscillatorDao is NULL.");

            return false;
        }

        OscillatorEntity entity;
        entity.id = 0;
        entity.calculatedAt = fromCalculatedAt;
        entity.symbolName = fromMarketContext.symbolName;
        entity.timeFrame = (int)fromMarketContext.timeFrame;
        entity.oscillatorCount = fromOscillatorCount;
        entity.isBuy = 0;

        if (fromIsBuy) {
            entity.isBuy = 1;
        }

        return this.oscillatorDao.insert(entity);
    }

private:
    /** オシレーターDAO。 */
    OscillatorDao *oscillatorDao;

    /** ロガー。 */
    Logger logger;
};

#endif // MSTNG_DATABASE_SERVICE_OSCILLATOR_PERSISTENCE_SERVICE_MQH
