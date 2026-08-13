//+------------------------------------------------------------------+
//|                           ZigZagElliotAlertDatabaseSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Database\Entity\ZigZagElliotAlertEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertPointEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertTimeFrameEntity.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Database\ZigZagElliotAlertDatabaseContext.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Log\Logger.mqh>

/** 動作確認用データベースファイル名。 */
input string databaseFileName =
    "mstng-zigzag-elliot-alert-smoke-test.sqlite";

/** 共有フォルダ使用有無。 */
input bool useCommonFolder = true;

/** 実行前に対象テーブルを再作成する場合true。 */
input bool recreateDatabaseObjects = true;

/**
 * 指定SQLの先頭列をlongとして取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromSql 実行するSQL。
 * @param fromValue 取得値の格納先。
 * @param fromLogger ロガー。
 * @return 取得に成功した場合true。
 */
bool readLong(
    const int fromDatabaseHandle,
    const string fromSql,
    long &fromValue,
    Logger &fromLogger
) {
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, fromSql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int errorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", errorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseColumnLong(requestHandle, 0, fromValue)) {
        int errorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumnLong failed. error=%d", errorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * 指定SQLの先頭列を文字列として取得する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromSql 実行するSQL。
 * @param fromValue 取得値の格納先。
 * @param fromLogger ロガー。
 * @return 取得に成功した場合true。
 */
bool readText(
    const int fromDatabaseHandle,
    const string fromSql,
    string &fromValue,
    Logger &fromLogger
) {
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, fromSql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int errorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", errorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseColumnText(requestHandle, 0, fromValue)) {
        int errorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumnText failed. error=%d", errorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return true;
}

/**
 * ZigZagElliotアラート用データベースオブジェクトを削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全オブジェクトを削除できた場合true。
 */
bool dropDatabaseObjects(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string sqlList[6];
    sqlList[0] =
        "DROP TABLE IF EXISTS zigzag_elliot_observation_timeframes";
    sqlList[1] = "DROP TABLE IF EXISTS zigzag_elliot_observations";
    sqlList[2] = "DROP TABLE IF EXISTS zigzag_elliot_alert_points";
    sqlList[3] = "DROP TABLE IF EXISTS zigzag_elliot_alert_timeframes";
    sqlList[4] = "DROP TABLE IF EXISTS zigzag_elliot_alerts";
    sqlList[5] = "DROP TABLE IF EXISTS zigzag_elliot_alert_runs";

    for (int i = 0; i < ArraySize(sqlList); i++) {
        ResetLastError();

        if (!DatabaseExecute(fromDatabaseHandle, sqlList[i])) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseExecute failed. index=%d error=%d",
                    i,
                    GetLastError()
                )
            );

            return false;
        }
    }

    return true;
}

/**
 * スモークテスト用実行レコードを初期化する。
 *
 * @param fromEntity 初期化対象。
 */
void initializeRunEntity(ZigZagElliotAlertRunEntity &fromEntity) {
    fromEntity.id = 0;
    fromEntity.runUid = "zigzag-elliot-alert-smoke-run-v1";
    fromEntity.schemaVersion = 3;
    fromEntity.sourceMode = "TESTER";
    fromEntity.source = "ZigZagElliot";
    fromEntity.programName = "ZigZagElliot";
    fromEntity.programVersion = "1.00-smoke";
    fromEntity.strategy = "MTF_3in3";
    fromEntity.strategyVersion = "mtf-3in3-smoke-v1";
    fromEntity.analysisVersion =
        ZigZagElliotAnalysisProfile::getAnalysisVersion();
    fromEntity.analysisInputText =
        ZigZagElliotAnalysisProfile::createCanonicalText();
    fromEntity.analysisInputHash =
        ZigZagElliotAnalysisProfile::createHash();
    fromEntity.sourceServer = "zigzag-elliot-alert-smoke";
    fromEntity.sourceLogin = 100001;
    fromEntity.sourceChartId = 200001;
    fromEntity.terminalBuild = 5000;
    fromEntity.testerFrom = D'2026.01.01 00:00:00';
    fromEntity.testerTo = D'2026.12.31 23:59:59';
    fromEntity.testerModel = "OPEN_PRICES";
    fromEntity.inputText = "symbol=GBPAUD,timeframe=H1";
    fromEntity.inputHash = "smoke-input-hash-v1";
    fromEntity.startedAt = D'2026.07.20 00:00:00';
    fromEntity.startedAtText = TimeToString(
        fromEntity.startedAt,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.marketStartedAt = D'2026.07.20 00:00:00';
    fromEntity.marketStartedAtText = TimeToString(
        fromEntity.marketStartedAt,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.createdAt = D'2026.08.08 12:00:00';
    fromEntity.createdAtText = TimeToString(
        fromEntity.createdAt,
        TIME_DATE | TIME_SECONDS
    );
}

/**
 * スモークテスト用アラートレコードを初期化する。
 *
 * @param fromRunId 実行ID。
 * @param fromEntity 初期化対象。
 */
void initializeAlertEntity(
    const long fromRunId,
    ZigZagElliotAlertEntity &fromEntity
) {
    fromEntity.id = 0;
    fromEntity.runId = fromRunId;
    fromEntity.eventUid = "zigzag-elliot-alert-smoke-event-v1";
    fromEntity.marketSignalKey =
        "GBPAUD|H1|20260720000000|20260719220000|BUY|MTF_3in3";
    fromEntity.snapshotHash = "zigzag-elliot-alert-smoke-snapshot-v1";
    fromEntity.serverTime = D'2026.07.20 00:00:00';
    fromEntity.serverTimeText = TimeToString(
        fromEntity.serverTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.jstTime = D'2026.07.20 06:00:00';
    fromEntity.jstTimeText = TimeToString(
        fromEntity.jstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.currentBarTime = D'2026.07.20 00:00:00';
    fromEntity.currentBarTimeText = TimeToString(
        fromEntity.currentBarTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.signalReferencePointTime = D'2026.07.19 22:00:00';
    fromEntity.signalReferencePointTimeText = TimeToString(
        fromEntity.signalReferencePointTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.symbolName = "GBPAUD";
    fromEntity.timeFrame = (int)PERIOD_H1;
    fromEntity.timeFrameText = "H1";
    fromEntity.magicNumber = "0";
    fromEntity.strategy = "MTF_3in3";
    fromEntity.side = "BUY";
    fromEntity.isJudge = 1;
    fromEntity.signalCount = 3;
    fromEntity.entryCount = 3;
    fromEntity.isEntryCountMatch = 1;
    fromEntity.isEntryEvaluated = 1;
    fromEntity.isAlert = 1;
    fromEntity.isEntry = 1;
    fromEntity.entryResult = "ENTRY";
    fromEntity.isSendMail = 0;
    // Elliottラベル未設定時のMQL5 NULL文字列を再現する。
    fromEntity.currentElliotLabel = NULL;
    fromEntity.isEntryWave = 1;
    fromEntity.closeEma200DiffPips = 12.3;
    fromEntity.maxCloseEma200DiffPips = 30.0;
    fromEntity.isEma200DistanceWithin = 1;
    fromEntity.w1ConfirmationMode = "DIRECTION_OR_EMA200";
    fromEntity.w1ConfirmationState = "STRONG";
    fromEntity.isW1ConfirmationAvailable = 1;
    fromEntity.isW1ConfirmationValid = 1;
    fromEntity.isW1DirectionMatched = 1;
    fromEntity.w1Ema200Direction = "BUY";
    fromEntity.isW1Ema200Matched = 1;
    fromEntity.isW1ConfirmationPassed = 1;
    fromEntity.spreadPips = 2.1;
    fromEntity.isCurrencyStrengthEnabled = 1;
    fromEntity.currencyStrengthStatus = 1;
    fromEntity.isCurrencyStrengthAvailable = 1;
    fromEntity.currencyStrengthCalculationVersion =
        "pair-direction-weighted-closed-v1";
    fromEntity.currencyStrengthRunId = 900001;
    fromEntity.currencyStrengthSourceMode = "TESTER";
    fromEntity.currencyStrengthTargetM5BarTime = D'2026.07.20 00:00:00';
    fromEntity.currencyStrengthM5BarTime = D'2026.07.20 00:00:00';
    fromEntity.baseCurrency = "GBP";
    fromEntity.baseLongMediumRank = 2;
    fromEntity.baseMediumShortRank = 3;
    fromEntity.quoteCurrency = "AUD";
    fromEntity.quoteLongMediumRank = 7;
    fromEntity.quoteMediumShortRank = 6;
    fromEntity.longMediumRankDifference = 5;
    fromEntity.mediumShortRankDifference = 3;
    fromEntity.referencePrice = 1.91234;
    fromEntity.isStopLossAvailable = 1;
    fromEntity.stopLoss = 1.90234;
    fromEntity.riskPips = 100.0;
    fromEntity.h1StructureRank = "A";
    fromEntity.isH1StructureValid = 1;
    fromEntity.isH1StructureLate = 0;
    fromEntity.isH1DirectionException = 0;
    fromEntity.alertTitle = "MTF_3in3 BUY,検証";
    fromEntity.alertText = "GBPAUD H1 BUY,アラート検証";
    fromEntity.waveSummaryText = "MN1:P1|W1:P2|D1:P3|H4:P4|H1:P5";
    fromEntity.elliotCsvText =
        "GBPAUD,20260720000000,H1,BUY,\"検証\"";
    fromEntity.createdAt = D'2026.08.08 12:00:01';
    fromEntity.createdAtText = TimeToString(
        fromEntity.createdAt,
        TIME_DATE | TIME_SECONDS
    );
}

/**
 * スモークテスト用時間足別レコードを初期化する。
 *
 * @param fromTimeFrame 時間足。
 * @param fromTimeFrameText 時間足表示文字列。
 * @param fromTimeFrameOrder 時間足順。
 * @param fromPointCount 最新Waveのポイント数。
 * @param fromEntity 初期化対象。
 */
void initializeTimeFrameEntity(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const string fromTimeFrameText,
    const int fromTimeFrameOrder,
    const int fromPointCount,
    ZigZagElliotAlertTimeFrameEntity &fromEntity
) {
    double priceBase = 1.80000 + (double)fromTimeFrameOrder * 0.01000;

    fromEntity.id = 0;
    fromEntity.alertId = 0;
    fromEntity.timeFrame = (int)fromTimeFrame;
    fromEntity.timeFrameText = fromTimeFrameText;
    fromEntity.timeFrameOrder = fromTimeFrameOrder;
    fromEntity.isCurrentTimeFrame = 0;

    if (fromTimeFrame == PERIOD_H1) {
        fromEntity.isCurrentTimeFrame = 1;
    }

    fromEntity.isBuy = 1;
    fromEntity.buySellLabel = "BUY";
    fromEntity.waveCount = fromTimeFrameOrder + 1;
    fromEntity.latestWaveIndex = 0;
    fromEntity.isWaveConfirmed = 1;
    fromEntity.isWaveMotive = 1;
    fromEntity.isWaveUptrend = 1;
    fromEntity.waveTrendLabel = "UP";
    fromEntity.previousLastElliotLabel = "C";
    fromEntity.pointCount = fromPointCount;
    fromEntity.latestElliotIndex = fromPointCount - 1;
    fromEntity.latestElliotLabel =
        "P" + IntegerToString(fromPointCount - 1);
    fromEntity.latestSubElliotIndex = fromPointCount - 1;
    fromEntity.latestSubElliotLabel =
        "S" + IntegerToString(fromPointCount - 1);
    fromEntity.previousOpen = priceBase;
    fromEntity.previousHigh = priceBase + 0.00300;
    fromEntity.previousLow = priceBase - 0.00200;
    fromEntity.previousClose = priceBase + 0.00100;
    fromEntity.currentOpen = priceBase + 0.00100;
    fromEntity.currentHigh = priceBase + 0.00400;
    fromEntity.currentLow = priceBase - 0.00100;
    fromEntity.currentClose = priceBase + 0.00200;
    fromEntity.isFiboExpansionAvailable = 1;
    fromEntity.fe618Price = priceBase + 0.00618;
    fromEntity.fe1000Price = priceBase + 0.01000;
    fromEntity.fe1272Price = priceBase + 0.01272;
    fromEntity.fe1618Price = priceBase + 0.01618;
    fromEntity.fe2000Price = priceBase + 0.02000;
    fromEntity.distanceToFe2000Pips = 200.0;
    fromEntity.oscillatorCount = 3;
    fromEntity.isOscillatorBuy = 1;
    fromEntity.stochasticMainOrder = 123;
    fromEntity.stochasticMainOrderText = "SHORT>MIDDLE>LONG";
    fromEntity.stochasticMainDirectionText = "BUY";
    fromEntity.stochasticShortCount = 3;
    fromEntity.stochasticShortMain = 70.0 + fromTimeFrameOrder;
    fromEntity.stochasticShortSignal = 65.0 + fromTimeFrameOrder;
    fromEntity.stochasticMiddleCount = 2;
    fromEntity.stochasticMiddleMain = 60.0 + fromTimeFrameOrder;
    fromEntity.stochasticMiddleSignal = 55.0 + fromTimeFrameOrder;
    fromEntity.stochasticLongCount = 1;
    fromEntity.stochasticLongMain = 50.0 + fromTimeFrameOrder;
    fromEntity.stochasticLongSignal = 45.0 + fromTimeFrameOrder;
    fromEntity.gmmaTrendCount = fromTimeFrameOrder + 1;
    fromEntity.gmmaCrossCount = fromTimeFrameOrder + 2;
    fromEntity.ema30 = priceBase + 0.00300;
    fromEntity.ema60 = priceBase + 0.00200;
    fromEntity.ema30Ema60DiffPips = 10.0;
    fromEntity.atr14Pips = 80.0 + fromTimeFrameOrder;
    fromEntity.ema200Close1 = priceBase + 0.00100;
    fromEntity.ema200Shift1 = priceBase - 0.00100;
    fromEntity.ema200Compare = priceBase - 0.00200;
    fromEntity.ema200SlopePips = 10.0;
    fromEntity.ema200CloseDiffPips = 20.0;
    fromEntity.ema200ClosePosition = 1;
    fromEntity.ema200SlopeDirection = 1;
    fromEntity.ema200UpCount = 3;
    fromEntity.ema200DownCount = 0;
    fromEntity.ema200TrendCount = 3;
    fromEntity.isEma200Buy = 1;
    fromEntity.isEma200Sell = 0;
    fromEntity.rawCsvText =
        fromTimeFrameText + ",BUY,P"
        + IntegerToString(fromPointCount - 1);
    fromEntity.createdAt = D'2026.08.08 12:00:02';
    fromEntity.createdAtText = TimeToString(
        fromEntity.createdAt,
        TIME_DATE | TIME_SECONDS
    );
}

/**
 * MN1からH1までの時間足別Fixtureを生成する。
 *
 * @param fromEntities 生成先配列。
 */
void initializeTimeFrameEntities(
    ZigZagElliotAlertTimeFrameEntity &fromEntities[]
) {
    ArrayResize(fromEntities, 5);
    initializeTimeFrameEntity(PERIOD_MN1, "MN1", 0, 2, fromEntities[0]);
    initializeTimeFrameEntity(PERIOD_W1, "W1", 1, 3, fromEntities[1]);
    initializeTimeFrameEntity(PERIOD_D1, "D1", 2, 4, fromEntities[2]);
    initializeTimeFrameEntity(PERIOD_H4, "H4", 3, 5, fromEntities[3]);
    initializeTimeFrameEntity(PERIOD_H1, "H1", 4, 6, fromEntities[4]);

    // MN1で発生した未設定ラベルのMQL5 NULL文字列を再現する。
    fromEntities[0].previousLastElliotLabel = NULL;
    fromEntities[0].latestSubElliotLabel = NULL;
}

/**
 * スモークテスト用波動ポイントを初期化する。
 *
 * @param fromTimeFrame 時間足。
 * @param fromTimeFrameOrder 時間足順。
 * @param fromPointOrder ポイント順。
 * @param fromPointCount 対象時間足のポイント数。
 * @param fromEntity 初期化対象。
 */
void initializePointEntity(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const int fromTimeFrameOrder,
    const int fromPointOrder,
    const int fromPointCount,
    ZigZagElliotAlertPointEntity &fromEntity
) {
    int periodSeconds = PeriodSeconds(fromTimeFrame);
    datetime currentBarTime = D'2026.07.20 00:00:00';

    fromEntity.id = 0;
    fromEntity.alertTimeFrameId = 0;
    fromEntity.timeFrame = (int)fromTimeFrame;
    fromEntity.pointOrder = fromPointOrder;
    fromEntity.isLatest = 0;

    if (fromPointOrder == fromPointCount - 1) {
        fromEntity.isLatest = 1;
    }

    fromEntity.isSignalReference = 0;

    if (fromTimeFrame == PERIOD_H1
            && fromPointOrder == fromPointCount - 2) {
        fromEntity.isSignalReference = 1;
    }

    fromEntity.rate = 1.80000
        + (double)fromTimeFrameOrder * 0.01000
        + (double)fromPointOrder * 0.00100;
    fromEntity.barIndex = fromPointCount - fromPointOrder;
    fromEntity.barTime = currentBarTime
        - (fromPointCount - fromPointOrder) * periodSeconds;
    fromEntity.barTimeText = TimeToString(
        fromEntity.barTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.isBarTimeNextAvailable = 1;
    fromEntity.barTimeNext = fromEntity.barTime + periodSeconds;
    fromEntity.barTimeNextText = TimeToString(
        fromEntity.barTimeNext,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.waveBarsFromStart = fromPointOrder;
    fromEntity.isPeak = 0;

    if (fromPointOrder % 2 == 1) {
        fromEntity.isPeak = 1;
    }

    fromEntity.isAddedPoint = 0;
    fromEntity.pipsDiff = 10.0 * fromPointOrder;
    fromEntity.isFibonacciAvailable = 0;
    fromEntity.fibonacciPercent = 0.0;

    if (fromPointOrder > 0) {
        fromEntity.isFibonacciAvailable = 1;
        fromEntity.fibonacciPercent = 38.2 + fromPointOrder;
    }

    fromEntity.fiboDepthZone = fromPointOrder;
    fromEntity.fiboDepthZoneLabel =
        "ZONE" + IntegerToString(fromPointOrder);
    fromEntity.isFibonacciExpansionAvailable = 0;
    fromEntity.fibonacciExpansionPercent = 0.0;

    if (fromPointOrder > 1) {
        fromEntity.isFibonacciExpansionAvailable = 1;
        fromEntity.fibonacciExpansionPercent = 100.0 + fromPointOrder;
    }

    fromEntity.isElliotAlphabet = 0;
    fromEntity.elliotIndex = fromPointOrder;
    fromEntity.elliotLabel = "P" + IntegerToString(fromPointOrder);
    fromEntity.isSubElliotAvailable = 1;
    fromEntity.subElliotIndex = fromPointOrder;
    fromEntity.subElliotLabel = "S" + IntegerToString(fromPointOrder);
    fromEntity.isOriginalElliotAvailable = 1;
    fromEntity.orgElliotIndex = fromPointOrder;
    fromEntity.orgElliotLabel = "O" + IntegerToString(fromPointOrder);
    fromEntity.isCorrect = 0;
    fromEntity.createdAt = D'2026.08.08 12:00:03';
    fromEntity.createdAtText = TimeToString(
        fromEntity.createdAt,
        TIME_DATE | TIME_SECONDS
    );
}

/**
 * MN1からH1までの最新WaveポイントFixtureを生成する。
 *
 * @param fromEntities 生成先配列。
 */
void initializePointEntities(
    ZigZagElliotAlertPointEntity &fromEntities[]
) {
    ENUM_TIMEFRAMES timeFrames[5];
    int pointCounts[5];
    timeFrames[0] = PERIOD_MN1;
    timeFrames[1] = PERIOD_W1;
    timeFrames[2] = PERIOD_D1;
    timeFrames[3] = PERIOD_H4;
    timeFrames[4] = PERIOD_H1;
    pointCounts[0] = 2;
    pointCounts[1] = 3;
    pointCounts[2] = 4;
    pointCounts[3] = 5;
    pointCounts[4] = 6;

    ArrayResize(fromEntities, 20);
    int index = 0;

    for (int i = 0; i < ArraySize(timeFrames); i++) {
        for (int j = 0; j < pointCounts[i]; j++) {
            initializePointEntity(
                timeFrames[i],
                i,
                j,
                pointCounts[i],
                fromEntities[index]
            );
            index++;
        }
    }

    // ポイントの未設定ラベルをMQL5 NULL文字列で再現する。
    fromEntities[0].fiboDepthZoneLabel = NULL;
    fromEntities[0].elliotLabel = NULL;
    fromEntities[0].subElliotLabel = NULL;
    fromEntities[0].orgElliotLabel = NULL;
}

/**
 * 指定SQLが1行も返さないことを確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromSql 実行するSQL。
 * @param fromLogger ロガー。
 * @return 0行の場合true。
 */
bool verifyNoRows(
    const int fromDatabaseHandle,
    const string fromSql,
    Logger &fromLogger
) {
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, fromSql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();
    bool hasRow = DatabaseRead(requestHandle);
    int errorCode = GetLastError();
    DatabaseFinalize(requestHandle);

    if (hasRow) {
        fromLogger.error(__FUNCTION__, "Unexpected row was returned.");

        return false;
    }

    if (errorCode != 0 && errorCode != ERR_DATABASE_NO_MORE_DATA) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", errorCode)
        );

        return false;
    }

    return true;
}

/**
 * 保存件数、重複、波動ポイント順およびSQLite整合性を検証する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunId 実行ID。
 * @param fromAlertId アラートID。
 * @param fromLogger ロガー。
 * @return 全検証に成功した場合true。
 */
bool verifySavedSnapshot(
    const int fromDatabaseHandle,
    const long fromRunId,
    const long fromAlertId,
    Logger &fromLogger
) {
    string runIdText = StringFormat("%I64d", fromRunId);
    string alertIdText = StringFormat("%I64d", fromAlertId);
    long runCount = 0;
    long alertCount = 0;
    long timeFrameCount = 0;
    long pointCount = 0;
    long pointOrderTotal = 0;
    long latestPointCount = 0;
    long signalReferenceCount = 0;
    long mismatchCount = 0;
    long normalizedAlertCount = 0;
    long normalizedTimeFrameCount = 0;
    long normalizedPointCount = 0;
    long foreignKeysEnabled = 0;
    string integrityResult = "";

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM zigzag_elliot_alert_runs "
                "WHERE run_uid = 'zigzag-elliot-alert-smoke-run-v1' "
                "AND schema_version = 3",
            runCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_alerts WHERE run_id = "
                    + runIdText,
                alertCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_alert_timeframes "
                    "WHERE alert_id = " + alertIdText,
                timeFrameCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_alert_points AS point "
                    "INNER JOIN zigzag_elliot_alert_timeframes AS time_frame "
                    "ON time_frame.id = point.alert_timeframe_id "
                    "WHERE time_frame.alert_id = " + alertIdText,
                pointCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COALESCE(SUM(point.point_order), 0) "
                    "FROM zigzag_elliot_alert_points AS point "
                    "INNER JOIN zigzag_elliot_alert_timeframes AS time_frame "
                    "ON time_frame.id = point.alert_timeframe_id "
                    "WHERE time_frame.alert_id = " + alertIdText,
                pointOrderTotal,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COALESCE(SUM(point.is_latest), 0) "
                    "FROM zigzag_elliot_alert_points AS point "
                    "INNER JOIN zigzag_elliot_alert_timeframes AS time_frame "
                    "ON time_frame.id = point.alert_timeframe_id "
                    "WHERE time_frame.alert_id = " + alertIdText,
                latestPointCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COALESCE(SUM(point.is_signal_reference), 0) "
                    "FROM zigzag_elliot_alert_points AS point "
                    "INNER JOIN zigzag_elliot_alert_timeframes AS time_frame "
                    "ON time_frame.id = point.alert_timeframe_id "
                    "WHERE time_frame.alert_id = " + alertIdText,
                signalReferenceCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_alerts "
                    "WHERE id = " + alertIdText + " "
                    "AND current_elliot_label = '' "
                    "AND current_elliot_label IS NOT NULL",
                normalizedAlertCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_alert_timeframes "
                    "WHERE alert_id = " + alertIdText + " "
                    "AND time_frame_text = 'MN1' "
                    "AND previous_last_elliot_label = '' "
                    "AND previous_last_elliot_label IS NOT NULL "
                    "AND latest_sub_elliot_label = '' "
                    "AND latest_sub_elliot_label IS NOT NULL",
                normalizedTimeFrameCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_alert_points AS point "
                    "INNER JOIN zigzag_elliot_alert_timeframes AS time_frame "
                    "ON time_frame.id = point.alert_timeframe_id "
                    "WHERE time_frame.alert_id = " + alertIdText + " "
                    "AND time_frame.time_frame_text = 'MN1' "
                    "AND point.point_order = 0 "
                    "AND point.fibo_depth_zone_label = '' "
                    "AND point.fibo_depth_zone_label IS NOT NULL "
                    "AND point.elliot_label = '' "
                    "AND point.elliot_label IS NOT NULL "
                    "AND point.sub_elliot_label = '' "
                    "AND point.sub_elliot_label IS NOT NULL "
                    "AND point.org_elliot_label = '' "
                    "AND point.org_elliot_label IS NOT NULL",
                normalizedPointCount,
                fromLogger
            )) {
        return false;
    }

    string mismatchSql =
        "SELECT COUNT(*) FROM ("
        "SELECT time_frame.id FROM zigzag_elliot_alert_timeframes AS time_frame "
        "LEFT JOIN zigzag_elliot_alert_points AS point "
        "ON point.alert_timeframe_id = time_frame.id "
        "WHERE time_frame.alert_id = " + alertIdText + " "
        "GROUP BY time_frame.id, time_frame.point_count "
        "HAVING COUNT(point.id) <> time_frame.point_count"
        ") AS mismatch";

    if (!readLong(
            fromDatabaseHandle,
            mismatchSql,
            mismatchCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                "PRAGMA foreign_keys",
                foreignKeysEnabled,
                fromLogger
            )
            || !readText(
                fromDatabaseHandle,
                "PRAGMA integrity_check",
                integrityResult,
                fromLogger
            )) {
        return false;
    }

    if (runCount != 1
            || alertCount != 1
            || timeFrameCount != 5
            || pointCount != 20
            || pointOrderTotal != 35
            || latestPointCount != 5
            || signalReferenceCount != 1
            || mismatchCount != 0
            || normalizedAlertCount != 1
            || normalizedTimeFrameCount != 1
            || normalizedPointCount != 1
            || foreignKeysEnabled != 1
            || integrityResult != "ok") {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Snapshot mismatch. runs=%I64d alerts=%I64d "
                + "timeFrames=%I64d points=%I64d pointOrderTotal=%I64d "
                + "latest=%I64d signalReference=%I64d mismatches=%I64d "
                + "normalizedAlert=%I64d normalizedTimeFrame=%I64d "
                + "normalizedPoint=%I64d "
                + "foreignKeys=%I64d integrity=%s",
                runCount,
                alertCount,
                timeFrameCount,
                pointCount,
                pointOrderTotal,
                latestPointCount,
                signalReferenceCount,
                mismatchCount,
                normalizedAlertCount,
                normalizedTimeFrameCount,
                normalizedPointCount,
                foreignKeysEnabled,
                integrityResult
            )
        );

        return false;
    }

    if (!verifyNoRows(
            fromDatabaseHandle,
            "PRAGMA foreign_key_check",
            fromLogger
        )) {
        return false;
    }

    return true;
}

/**
 * 保存したW1確認診断値を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromAlertId アラートID。
 * @param fromLogger ロガー。
 * @return 期待値と一致する場合true。
 */
bool verifyW1ConfirmationValues(
    const int fromDatabaseHandle,
    const long fromAlertId,
    Logger &fromLogger
) {
    long matchedCount = 0;
    string sql = "SELECT COUNT(*) FROM zigzag_elliot_alerts WHERE id = ";
    sql += StringFormat("%I64d", fromAlertId);
    sql += " AND w1_confirmation_mode = 'DIRECTION_OR_EMA200'";
    sql += " AND w1_confirmation_state = 'STRONG'";
    sql += " AND is_w1_confirmation_available = 1";
    sql += " AND is_w1_confirmation_valid = 1";
    sql += " AND is_w1_direction_matched = 1";
    sql += " AND w1_ema200_direction = 'BUY'";
    sql += " AND is_w1_ema200_matched = 1";
    sql += " AND is_w1_confirmation_passed = 1";

    return readLong(
        fromDatabaseHandle,
        sql,
        matchedCount,
        fromLogger
    ) && matchedCount == 1;
}

/**
 * 旧スキーマを再現するため、W1確認診断列を削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全対象列を削除できた場合true。
 */
bool removeW1ConfirmationSchemaForMigrationTest(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string columns[8] = {
        "w1_confirmation_mode",
        "w1_confirmation_state",
        "is_w1_confirmation_available",
        "is_w1_confirmation_valid",
        "is_w1_direction_matched",
        "w1_ema200_direction",
        "is_w1_ema200_matched",
        "is_w1_confirmation_passed"
    };

    for (int i = 0; i < ArraySize(columns); i++) {
        string sql = "ALTER TABLE zigzag_elliot_alerts DROP COLUMN ";
        sql += columns[i];
        ResetLastError();

        if (!DatabaseExecute(fromDatabaseHandle, sql)) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DROP COLUMN failed. column=%s error=%d",
                    columns[i],
                    GetLastError()
                )
            );

            return false;
        }
    }

    return true;
}

/**
 * 旧行へ設定されたW1確認診断の移行既定値を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromAlertId アラートID。
 * @param fromLogger ロガー。
 * @return 既定値と一致する場合true。
 */
bool verifyW1ConfirmationMigrationDefaults(
    const int fromDatabaseHandle,
    const long fromAlertId,
    Logger &fromLogger
) {
    long matchedCount = 0;
    string sql = "SELECT COUNT(*) FROM zigzag_elliot_alerts WHERE id = ";
    sql += StringFormat("%I64d", fromAlertId);
    sql += " AND w1_confirmation_mode = 'OFF'";
    sql += " AND w1_confirmation_state = 'NOT_EVALUATED'";
    sql += " AND is_w1_confirmation_available = 0";
    sql += " AND is_w1_confirmation_valid = 0";
    sql += " AND is_w1_direction_matched = 0";
    sql += " AND w1_ema200_direction = 'NONE'";
    sql += " AND is_w1_ema200_matched = 0";
    sql += " AND is_w1_confirmation_passed = 1";

    return readLong(
        fromDatabaseHandle,
        sql,
        matchedCount,
        fromLogger
    ) && matchedCount == 1;
}

/**
 * 必要に応じてスモークテスト用テーブルを削除する。
 *
 * @param fromLogger ロガー。
 * @return 再作成準備に成功した場合true。
 */
bool prepareSmokeDatabase(Logger &fromLogger) {
    if (!recreateDatabaseObjects) {
        return true;
    }

    if (databaseFileName
            != "mstng-zigzag-elliot-alert-smoke-test.sqlite") {
        fromLogger.error(
            __FUNCTION__,
            "Refusing to recreate a database other than the dedicated smoke-test database."
        );

        return false;
    }

    SqliteDatabase database(databaseFileName, useCommonFolder);

    if (!database.open()) {
        return false;
    }

    bool isDropped = dropDatabaseObjects(
        database.getHandle(),
        fromLogger
    );
    database.close();

    return isDropped;
}

/**
 * 保存失敗後のスナップショットIDがすべてクリアされたか確認する。
 *
 * @param fromAlertEntity アラート本体。
 * @param fromTimeFrameEntities 時間足別分析一覧。
 * @param fromPointEntities ポイント一覧。
 * @return 全IDが0の場合true。
 */
bool areSnapshotIdsCleared(
    ZigZagElliotAlertEntity &fromAlertEntity,
    ZigZagElliotAlertTimeFrameEntity &fromTimeFrameEntities[],
    ZigZagElliotAlertPointEntity &fromPointEntities[]
) {
    if (fromAlertEntity.id != 0) {
        return false;
    }

    for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
        if (fromTimeFrameEntities[i].id != 0
                || fromTimeFrameEntities[i].alertId != 0) {
            return false;
        }
    }

    for (int i = 0; i < ArraySize(fromPointEntities); i++) {
        if (fromPointEntities[i].id != 0
                || fromPointEntities[i].alertTimeFrameId != 0) {
            return false;
        }
    }

    return true;
}

/**
 * ZigZagElliotアラートDBのスモークテストを実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!prepareSmokeDatabase(logger)) {
        logger.error(__FUNCTION__, "Database preparation failed.");

        return;
    }

    ZigZagElliotAlertDatabaseContext context(
        databaseFileName,
        useCommonFolder
    );

    if (!context.open() || !context.isReady()) {
        logger.error(__FUNCTION__, "Database context open failed.");

        return;
    }

    ZigZagElliotAlertPersistenceService *persistenceService =
        context.getPersistenceService();

    if (persistenceService == NULL || !persistenceService.createTables()) {
        logger.error(__FUNCTION__, "Persistence service is not ready.");

        return;
    }

    ZigZagElliotAlertRunEntity invalidV3RunEntity;
    initializeRunEntity(invalidV3RunEntity);
    invalidV3RunEntity.runUid =
        "zigzag-elliot-alert-smoke-run-invalid-v3";
    invalidV3RunEntity.analysisInputHash = "INVALID";

    if (persistenceService.saveRun(invalidV3RunEntity)
            || invalidV3RunEntity.id != 0) {
        logger.error(__FUNCTION__, "Invalid V3 Run was not rejected.");

        return;
    }

    ZigZagElliotAlertRunEntity legacyV1RunEntity;
    initializeRunEntity(legacyV1RunEntity);
    legacyV1RunEntity.runUid =
        "zigzag-elliot-alert-smoke-run-legacy-v1";
    legacyV1RunEntity.schemaVersion = 1;
    legacyV1RunEntity.analysisVersion = "";
    legacyV1RunEntity.analysisInputText = "";
    legacyV1RunEntity.analysisInputHash = "";

    if (!persistenceService.saveRun(legacyV1RunEntity)
            || legacyV1RunEntity.id <= 0) {
        logger.error(__FUNCTION__, "Legacy V1 Run compatibility failed.");

        return;
    }

    ZigZagElliotAlertRunEntity runEntity;
    initializeRunEntity(runEntity);

    if (!persistenceService.saveRun(runEntity) || runEntity.id <= 0) {
        logger.error(__FUNCTION__, "Run save failed.");

        return;
    }

    ZigZagElliotAlertEntity alertEntity;
    ZigZagElliotAlertTimeFrameEntity timeFrameEntities[];
    ZigZagElliotAlertPointEntity pointEntities[];
    initializeAlertEntity(runEntity.id, alertEntity);
    initializeTimeFrameEntities(timeFrameEntities);
    initializePointEntities(pointEntities);

    if (!persistenceService.saveSnapshot(
            alertEntity,
            timeFrameEntities,
            pointEntities
        )
            || alertEntity.id <= 0) {
        logger.error(__FUNCTION__, "First snapshot save failed.");

        return;
    }

    long firstRunId = runEntity.id;
    long firstAlertId = alertEntity.id;
    ZigZagElliotAlertRunEntity duplicateRunEntity;
    initializeRunEntity(duplicateRunEntity);

    if (!persistenceService.saveRun(duplicateRunEntity)
            || duplicateRunEntity.id != firstRunId) {
        logger.error(__FUNCTION__, "Run duplicate verification failed.");

        return;
    }

    ZigZagElliotAlertEntity duplicateAlertEntity;
    ZigZagElliotAlertTimeFrameEntity duplicateTimeFrameEntities[];
    ZigZagElliotAlertPointEntity duplicatePointEntities[];
    initializeAlertEntity(duplicateRunEntity.id, duplicateAlertEntity);
    initializeTimeFrameEntities(duplicateTimeFrameEntities);
    initializePointEntities(duplicatePointEntities);

    if (!persistenceService.saveSnapshot(
            duplicateAlertEntity,
            duplicateTimeFrameEntities,
            duplicatePointEntities
        )
            || duplicateAlertEntity.id != firstAlertId) {
        logger.error(__FUNCTION__, "Snapshot duplicate verification failed.");

        return;
    }

    ZigZagElliotAlertEntity rollbackAlertEntity;
    ZigZagElliotAlertTimeFrameEntity rollbackTimeFrameEntities[];
    ZigZagElliotAlertPointEntity rollbackPointEntities[];
    initializeAlertEntity(runEntity.id, rollbackAlertEntity);
    rollbackAlertEntity.eventUid =
        "zigzag-elliot-alert-smoke-event-rollback";
    rollbackAlertEntity.marketSignalKey =
        "GBPAUD|H1|20260720010000|20260719220000|BUY|MTF_3in3";
    rollbackAlertEntity.snapshotHash =
        "zigzag-elliot-alert-smoke-snapshot-rollback";
    rollbackAlertEntity.currentBarTime = D'2026.07.20 01:00:00';
    rollbackAlertEntity.currentBarTimeText = TimeToString(
        rollbackAlertEntity.currentBarTime,
        TIME_DATE | TIME_SECONDS
    );
    initializeTimeFrameEntities(rollbackTimeFrameEntities);
    initializePointEntities(rollbackPointEntities);
    rollbackPointEntities[0].timeFrame = (int)PERIOD_M15;
    logger.info(
        __FUNCTION__,
        "Starting expected snapshot rollback verification."
    );

    if (persistenceService.saveSnapshot(
            rollbackAlertEntity,
            rollbackTimeFrameEntities,
            rollbackPointEntities
        )
            || !areSnapshotIdsCleared(
                rollbackAlertEntity,
                rollbackTimeFrameEntities,
                rollbackPointEntities
            )) {
        logger.error(__FUNCTION__, "Snapshot rollback verification failed.");

        return;
    }

    logger.info(__FUNCTION__, "Expected snapshot rollback was verified.");

    context.close();
    SqliteDatabase verificationDatabase(databaseFileName, useCommonFolder);

    if (!verificationDatabase.open()) {
        logger.error(__FUNCTION__, "Verification database open failed.");

        return;
    }

    ResetLastError();

    if (!DatabaseExecute(
            verificationDatabase.getHandle(),
            "PRAGMA foreign_keys = ON"
        )) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Foreign key activation failed. error=%d",
                GetLastError()
            )
        );
        verificationDatabase.close();

        return;
    }

    bool isVerified = verifySavedSnapshot(
        verificationDatabase.getHandle(),
        firstRunId,
        firstAlertId,
        logger
    ) && verifyW1ConfirmationValues(
        verificationDatabase.getHandle(),
        firstAlertId,
        logger
    );
    verificationDatabase.close();

    if (!isVerified) {
        logger.error(__FUNCTION__, "Saved snapshot verification failed.");

        return;
    }

    SqliteDatabase legacySchemaDatabase(databaseFileName, useCommonFolder);

    if (!legacySchemaDatabase.open()
            || !removeW1ConfirmationSchemaForMigrationTest(
                legacySchemaDatabase.getHandle(),
                logger
            )) {
        logger.error(__FUNCTION__, "Legacy W1 schema preparation failed.");
        legacySchemaDatabase.close();

        return;
    }

    legacySchemaDatabase.close();
    ZigZagElliotAlertDatabaseContext migrationContext(
        databaseFileName,
        useCommonFolder
    );

    if (!migrationContext.open() || !migrationContext.isReady()) {
        logger.error(__FUNCTION__, "Migration database context open failed.");

        return;
    }

    ZigZagElliotAlertPersistenceService *migrationPersistenceService =
        migrationContext.getPersistenceService();

    if (migrationPersistenceService == NULL
            || !migrationPersistenceService.createTables()) {
        logger.error(__FUNCTION__, "W1 confirmation migration failed.");
        migrationContext.close();

        return;
    }

    migrationContext.close();

    if (!verificationDatabase.open()) {
        logger.error(__FUNCTION__, "Migration verification open failed.");

        return;
    }

    ResetLastError();

    if (!DatabaseExecute(
            verificationDatabase.getHandle(),
            "PRAGMA foreign_keys = ON"
        )) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Migration foreign key activation failed. error=%d",
                GetLastError()
            )
        );
        verificationDatabase.close();

        return;
    }

    bool isMigrationVerified = verifySavedSnapshot(
        verificationDatabase.getHandle(),
        firstRunId,
        firstAlertId,
        logger
    ) && verifyW1ConfirmationMigrationDefaults(
        verificationDatabase.getHandle(),
        firstAlertId,
        logger
    );
    verificationDatabase.close();

    if (!isMigrationVerified) {
        logger.error(__FUNCTION__, "W1 confirmation migration verification failed.");

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "ZigZagElliot alert database smoke test passed. "
            + "fileName=%s runId=%I64d alertId=%I64d "
            + "timeFrames=5 points=20",
            databaseFileName,
            firstRunId,
            firstAlertId
        )
    );
}
