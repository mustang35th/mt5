//+------------------------------------------------------------------+
//|                                            DatabaseSmokeTest.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Dao\OscillatorDao.mqh>
#include <Mstng\Database\Entity\OscillatorEntity.mqh>
#include <Mstng\Database\Service\OscillatorPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/** 動作確認用データベースファイル名。 */
input string databaseFileName = "mstng-database-smoke-test.sqlite";

/** 共有フォルダ使用有無。 */
input bool useCommonFolder = true;

/**
 * 保存内容と読込内容が一致するか検証する。
 *
 * @param fromCalculatedAt 保存した計算時刻。
 * @param fromMarketContext 保存した市場コンテキスト。
 * @param fromOscillatorCount 保存したオシレーター総合判定値。
 * @param fromIsBuy 保存したBUYフラグ。
 * @param fromEntity 読み込んだエンティティ。
 * @return 全項目が一致する場合はtrue。
 */
bool isSmokeTestResultValid(
    const datetime fromCalculatedAt,
    MarketContext &fromMarketContext,
    const int fromOscillatorCount,
    const bool fromIsBuy,
    OscillatorEntity &fromEntity
) {
    int expectedIsBuy = 0;

    if (fromIsBuy) {
        expectedIsBuy = 1;
    }

    return fromEntity.id > 0
        && fromEntity.calculatedAt == fromCalculatedAt
        && fromEntity.symbolName == fromMarketContext.symbolName
        && fromEntity.timeFrame == (int)fromMarketContext.timeFrame
        && fromEntity.oscillatorCount == fromOscillatorCount
        && fromEntity.isBuy == expectedIsBuy;
}

/**
 * SQLite動作確認スクリプトを実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);
    SqliteDatabase database(databaseFileName, useCommonFolder);

    if (!database.open()) {
        logger.error(__FUNCTION__, "Database smoke test failed at open.");

        return;
    }

    OscillatorDao oscillatorDao(database.getHandle());

    if (!oscillatorDao.createTable()) {
        logger.error(__FUNCTION__, "Database smoke test failed at createTable.");

        return;
    }

    OscillatorPersistenceService persistenceService(GetPointer(oscillatorDao));
    MarketContext marketContext(_Symbol, (ENUM_TIMEFRAMES)_Period);
    datetime calculatedAt = TimeLocal();
    int oscillatorCount = 2;
    bool isBuy = true;

    if (!persistenceService.save(
        calculatedAt,
        marketContext,
        oscillatorCount,
        isBuy
    )) {
        logger.error(__FUNCTION__, "Database smoke test failed at insert.");

        return;
    }

    OscillatorEntity loadedEntity;

    if (!oscillatorDao.findLatest(
        marketContext.symbolName,
        marketContext.timeFrame,
        loadedEntity
    )) {
        logger.error(__FUNCTION__, "Database smoke test failed at select.");

        return;
    }

    if (!isSmokeTestResultValid(
        calculatedAt,
        marketContext,
        oscillatorCount,
        isBuy,
        loadedEntity
    )) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Database smoke test value mismatch. id=%I64d calculatedAt=%s symbolName=%s timeFrame=%d oscillatorCount=%d isBuy=%d",
                loadedEntity.id,
                TimeToString(loadedEntity.calculatedAt, TIME_DATE | TIME_SECONDS),
                loadedEntity.symbolName,
                loadedEntity.timeFrame,
                loadedEntity.oscillatorCount,
                loadedEntity.isBuy
            )
        );

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Database smoke test passed. fileName=%s id=%I64d symbolName=%s timeFrame=%d oscillatorCount=%d isBuy=%d",
            database.getFileName(),
            loadedEntity.id,
            loadedEntity.symbolName,
            loadedEntity.timeFrame,
            loadedEntity.oscillatorCount,
            loadedEntity.isBuy
        )
    );

    database.close();
}
