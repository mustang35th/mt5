//+------------------------------------------------------------------+
//|                   ZigZagElliotH1ObservationDatabaseSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Database\Dao\ZigZagElliotAlertRunDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationTimeFrameDao.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotObservationTimeFrameEntity.mqh>
#include <Mstng\Database\Service\ZigZagElliotObservationPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>

/** 動作確認専用データベースファイル名。 */
input string databaseFileName =
    "mstng-zigzag-elliot-h1-observation-smoke-test.sqlite";

/** 共有フォルダ使用有無。 */
input bool useCommonFolder = true;

/** 実行前に対象テーブルを再作成する場合true。 */
input bool recreateDatabaseObjects = true;

/** 専用データベースファイル名。 */
const string dedicatedDatabaseFileName =
    "mstng-zigzag-elliot-h1-observation-smoke-test.sqlite";

/** ロールバック検証用トリガー名。 */
const string rollbackTriggerName =
    "smoke_fail_zigzag_elliot_observation_child";

/** 分析Profile Canonical Textの固定SHA-256期待値。 */
const string expectedAnalysisProfileHash =
    "d2c1774928e006572b254cfbda33a01d6de54e23c108ef402be14e1ea5785631";

/**
 * 指定SQLを実行する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromSql 実行するSQL。
 * @param fromOperationName 処理名。
 * @param fromLogger ロガー。
 * @return 実行に成功した場合true。
 */
bool executeSql(
    const int fromDatabaseHandle,
    const string fromSql,
    const string fromOperationName,
    Logger &fromLogger
) {
    ResetLastError();

    if (!DatabaseExecute(fromDatabaseHandle, fromSql)) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseExecute failed. operation=%s error=%d",
                fromOperationName,
                GetLastError()
            )
        );

        return false;
    }

    return true;
}

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
 * @param fromColumnIndex 取得する列番号。
 * @return 取得に成功した場合true。
 */
bool readText(
    const int fromDatabaseHandle,
    const string fromSql,
    string &fromValue,
    Logger &fromLogger,
    const int fromColumnIndex = 0
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

    if (!DatabaseColumnText(
            requestHandle,
            fromColumnIndex,
            fromValue
        )) {
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
 * Observation専用データベースオブジェクトを子から順に削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全オブジェクトを削除できた場合true。
 */
bool dropDatabaseObjects(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string sqlList[4];
    sqlList[0] = "DROP TRIGGER IF EXISTS " + rollbackTriggerName;
    sqlList[1] =
        "DROP TABLE IF EXISTS zigzag_elliot_observation_timeframes";
    sqlList[2] = "DROP TABLE IF EXISTS zigzag_elliot_observations";
    sqlList[3] = "DROP TABLE IF EXISTS zigzag_elliot_alert_runs";

    for (int i = 0; i < ArraySize(sqlList); i++) {
        if (!executeSql(
                fromDatabaseHandle,
                sqlList[i],
                "drop database object",
                fromLogger
            )) {
            return false;
        }
    }

    return true;
}

/**
 * 分析Profile列追加前のRunテーブルとLegacy行を準備する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 準備に成功した場合true。
 */
bool createLegacyRunTable(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    if (!recreateDatabaseObjects) {
        return true;
    }

    string sql = "CREATE TABLE zigzag_elliot_alert_runs (";
    sql += "id INTEGER PRIMARY KEY AUTOINCREMENT,";
    sql += "run_uid TEXT NOT NULL,";
    sql += "schema_version INTEGER NOT NULL CHECK(schema_version > 0),";
    sql += "source_mode TEXT NOT NULL,source TEXT NOT NULL,";
    sql += "program_name TEXT NOT NULL,program_version TEXT NOT NULL,";
    sql += "strategy TEXT NOT NULL,strategy_version TEXT NOT NULL,";
    sql += "analysis_version TEXT NOT NULL,source_server TEXT NOT NULL,";
    sql += "source_login INTEGER NOT NULL,source_chart_id INTEGER NOT NULL,";
    sql += "terminal_build INTEGER NOT NULL,tester_from INTEGER NOT NULL,";
    sql += "tester_to INTEGER NOT NULL,tester_model TEXT NOT NULL,";
    sql += "input_text TEXT NOT NULL,input_hash TEXT NOT NULL,";
    sql += "started_at INTEGER NOT NULL,started_at_text TEXT NOT NULL,";
    sql += "market_started_at INTEGER NOT NULL,";
    sql += "market_started_at_text TEXT NOT NULL,";
    sql += "created_at INTEGER NOT NULL,created_at_text TEXT NOT NULL)";

    if (!executeSql(
            fromDatabaseHandle,
            sql,
            "create legacy alert run table",
            fromLogger
        )) {
        return false;
    }

    sql = "INSERT INTO zigzag_elliot_alert_runs (";
    sql += "run_uid,schema_version,source_mode,source,program_name,";
    sql += "program_version,strategy,strategy_version,analysis_version,";
    sql += "source_server,source_login,source_chart_id,terminal_build,";
    sql += "tester_from,tester_to,tester_model,input_text,input_hash,";
    sql += "started_at,started_at_text,market_started_at,";
    sql += "market_started_at_text,created_at,created_at_text) VALUES (";
    sql += "'legacy-run-v1',1,'TESTER','ZIGZAG_ELLIOT','Legacy',";
    sql += "'1.00','H1_ELLIOT_OBSERVATION','V1','ELLIOT_MN1_V1',";
    sql += "'legacy-server',0,0,0,0,0,'','','',0,'',0,'',0,'')";

    return executeSql(
        fromDatabaseHandle,
        sql,
        "insert legacy alert run",
        fromLogger
    );
}

/**
 * Legacy行保持と新規Runの分析Profile保存値を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunEntity 新規保存したRun。
 * @param fromLogger ロガー。
 * @return 期待値と一致する場合true。
 */
bool verifyRunAnalysisProfile(
    const int fromDatabaseHandle,
    ZigZagElliotAlertRunEntity &fromRunEntity,
    Logger &fromLogger
) {
    long legacyCount = 0;
    long modeProfileIndexCount = 0;
    long globalProfileIndexCount = 0;

    if (recreateDatabaseObjects
            && (!readLong(
                    fromDatabaseHandle,
                    "SELECT COUNT(*) FROM zigzag_elliot_alert_runs "
                        + "WHERE run_uid = 'legacy-run-v1' "
                        + "AND analysis_input_text = '' "
                        + "AND analysis_input_hash = ''",
                    legacyCount,
                    fromLogger
                ) || legacyCount != 1)) {
        return false;
    }

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' "
                + "AND name = "
                + "'idx_zigzag_elliot_observations_mode_profile_jst'",
            modeProfileIndexCount,
            fromLogger
        ) || modeProfileIndexCount != 1) {
        return false;
    }

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' "
                + "AND name = "
                + "'idx_zigzag_elliot_observations_profile_jst'",
            globalProfileIndexCount,
            fromLogger
        ) || globalProfileIndexCount != 1) {
        return false;
    }

    string sql = "SELECT analysis_version,analysis_input_text,";
    sql += "analysis_input_hash FROM zigzag_elliot_alert_runs WHERE id = ?1";
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE
            || !DatabaseBind(requestHandle, 0, fromRunEntity.id)) {
        if (requestHandle != INVALID_HANDLE) {
            DatabaseFinalize(requestHandle);
        }

        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare/Bind failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    string analysisVersion = "";
    string analysisInputText = "";
    string analysisInputHash = "";
    bool isRead = DatabaseColumnText(requestHandle, 0, analysisVersion)
        && DatabaseColumnText(requestHandle, 1, analysisInputText)
        && DatabaseColumnText(requestHandle, 2, analysisInputHash);
    DatabaseFinalize(requestHandle);

    return isRead
        && analysisVersion == ZigZagElliotAnalysisProfile::getAnalysisVersion()
        && analysisInputText
            == ZigZagElliotAnalysisProfile::createCanonicalText()
        && analysisInputHash == ZigZagElliotAnalysisProfile::createHash()
        && analysisInputHash == expectedAnalysisProfileHash
        && StringLen(analysisInputHash) == 64;
}

/**
 * 入力ファイル名が専用SmokeTest DBか判定する。
 *
 * @return 専用ファイルの場合true。
 */
bool isDedicatedDatabaseFile() {
    if (databaseFileName == dedicatedDatabaseFileName) {
        return true;
    }

    return false;
}

/**
 * 必要に応じてSmokeTest用テーブルを再作成可能な状態にする。
 *
 * 専用DB以外はrecreate設定にかかわらず拒否する。
 *
 * @param fromLogger ロガー。
 * @return 実行準備に成功した場合true。
 */
bool prepareSmokeDatabase(Logger &fromLogger) {
    if (!isDedicatedDatabaseFile()) {
        fromLogger.error(
            __FUNCTION__,
            "Refusing to use a database other than the dedicated observation smoke-test database."
        );

        return false;
    }

    if (!recreateDatabaseObjects) {
        return true;
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
 * SmokeTest用実行情報を初期化する。
 *
 * @param fromEntity 初期化対象。
 */
void initializeRunEntity(ZigZagElliotAlertRunEntity &fromEntity) {
    ZeroMemory(fromEntity);
    fromEntity.id = 0;
    fromEntity.runUid = "zigzag-elliot-h1-observation-smoke-run-v1";
    fromEntity.schemaVersion = 5;
    fromEntity.sourceMode = "TESTER";
    fromEntity.source = "ZIGZAG_ELLIOT";
    fromEntity.programName = "ZigZagElliot";
    fromEntity.programVersion = "1.23-smoke";
    fromEntity.strategy = "H1_ELLIOT_OBSERVATION";
    fromEntity.strategyVersion = "h1-observation-smoke-v1";
    fromEntity.analysisVersion =
        ZigZagElliotAnalysisProfile::getAnalysisVersion();
    fromEntity.analysisInputText =
        ZigZagElliotAnalysisProfile::createCanonicalText();
    fromEntity.analysisInputHash =
        ZigZagElliotAnalysisProfile::createHash();
    fromEntity.sourceServer = "zigzag-elliot-observation-smoke";
    fromEntity.sourceLogin = 100001;
    fromEntity.sourceChartId = 200001;
    fromEntity.terminalBuild = 5000;
    fromEntity.testerFrom = D'2026.01.01 00:00:00';
    fromEntity.testerTo = D'2026.12.31 23:59:59';
    fromEntity.testerModel = "OPEN_PRICES";
    fromEntity.inputText = "symbol=GBPAUD,timeframe=H1";
    fromEntity.inputHash = "alert-input-hash-not-used-by-observation";
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
 * SmokeTest用Observation親Entityを初期化する。
 *
 * @param fromRunId 実行情報ID。
 * @param fromAnchorBarTime 観測対象H1バー開始時刻。
 * @param fromSnapshotHash 観測内容ハッシュ。
 * @param fromEntity 初期化対象。
 */
void initializeObservationEntity(
    const long fromRunId,
    const datetime fromAnchorBarTime,
    const string fromSnapshotHash,
    ZigZagElliotObservationEntity &fromEntity
) {
    ZeroMemory(fromEntity);
    fromEntity.id = 0;
    fromEntity.runId = fromRunId;
    fromEntity.sourceMode = "TESTER";
    fromEntity.sourceServer = "zigzag-elliot-observation-smoke";
    fromEntity.symbolName = "GBPAUD";
    fromEntity.anchorTimeFrame = (int)PERIOD_H1;
    fromEntity.anchorTimeFrameText = "H1";
    fromEntity.anchorBarTime = fromAnchorBarTime;
    fromEntity.anchorBarTimeText = TimeToString(
        fromAnchorBarTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.anchorJstTime = TimeJapanUtil::getJapanTime(
        fromAnchorBarTime
    );
    fromEntity.anchorJstTimeText = TimeToString(
        fromEntity.anchorJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.capturePhase = "BAR_OPEN_FIRST_SUCCESS";
    fromEntity.spreadPips = 31.4;
    fromEntity.pipSize = 0.0001;
    fromEntity.analysisVersion =
        ZigZagElliotAnalysisProfile::getAnalysisVersion();
    fromEntity.analysisInputHash =
        ZigZagElliotAnalysisProfile::createHash();
    fromEntity.snapshotHash = fromSnapshotHash;
    fromEntity.timeFrameCount = 5;
    fromEntity.createdAt = D'2026.08.08 12:00:01';
    fromEntity.createdAtText = TimeToString(
        fromEntity.createdAt,
        TIME_DATE | TIME_SECONDS
    );
}

/**
 * 1時間足分のObservation子Entityを初期化する。
 *
 * @param fromTimeFrame 時間足。
 * @param fromTimeFrameText 時間足表示文字列。
 * @param fromTimeFrameOrder 上位足からの順序。
 * @param fromPointCount 最新Waveポイント数。
 * @param fromEntity 初期化対象。
 */
void initializeTimeFrameEntity(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const string fromTimeFrameText,
    const int fromTimeFrameOrder,
    const int fromPointCount,
    ZigZagElliotObservationTimeFrameEntity &fromEntity
) {
    ZeroMemory(fromEntity);
    double priceBase = 1.80000
        + (double)fromTimeFrameOrder * 0.01000;

    fromEntity.id = 0;
    fromEntity.observationId = 0;
    fromEntity.timeFrame = (int)fromTimeFrame;
    fromEntity.timeFrameText = fromTimeFrameText;
    fromEntity.timeFrameOrder = fromTimeFrameOrder;
    fromEntity.isAnchorTimeFrame = 0;

    if (fromTimeFrame == PERIOD_H1) {
        fromEntity.isAnchorTimeFrame = 1;
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
    // 通常冬時間、開始前後、終了日、終了翌日の境界を固定する。
    if (fromTimeFrame == PERIOD_MN1) {
        fromEntity.latestPointTime = D'2026.01.20 12:00:00';
    } else if (fromTimeFrame == PERIOD_W1) {
        fromEntity.latestPointTime = D'2026.03.07 23:59:59';
    } else if (fromTimeFrame == PERIOD_D1) {
        fromEntity.latestPointTime = D'2026.03.08 00:00:00';
    } else if (fromTimeFrame == PERIOD_H4) {
        fromEntity.latestPointTime = D'2026.11.01 23:59:59';
    } else {
        fromEntity.latestPointTime = D'2026.11.02 00:00:00';
    }

    fromEntity.latestPointTimeText = TimeToString(
        fromEntity.latestPointTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.latestPointJstTime = TimeJapanUtil::getJapanTime(
        fromEntity.latestPointTime
    );
    fromEntity.latestPointJstTimeText = TimeToString(
        fromEntity.latestPointJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromEntity.latestPointRate = priceBase + 0.00100;
    fromEntity.latestPointIsAdded = fromTimeFrameOrder % 2;
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
    fromEntity.createdAt = D'2026.08.08 12:00:02';
    fromEntity.createdAtText = TimeToString(
        fromEntity.createdAt,
        TIME_DATE | TIME_SECONDS
    );
}

/**
 * MN1からH1までの固定5時間足Fixtureを生成する。
 *
 * @param fromEntities 生成先配列。
 */
void initializeTimeFrameEntities(
    ZigZagElliotObservationTimeFrameEntity &fromEntities[]
) {
    ArrayResize(fromEntities, 5);
    initializeTimeFrameEntity(PERIOD_MN1, "MN1", 0, 2, fromEntities[0]);
    initializeTimeFrameEntity(PERIOD_W1, "W1", 1, 3, fromEntities[1]);
    initializeTimeFrameEntity(PERIOD_D1, "D1", 2, 4, fromEntities[2]);
    initializeTimeFrameEntity(PERIOD_H4, "H4", 3, 5, fromEntities[3]);
    initializeTimeFrameEntity(PERIOD_H1, "H1", 4, 6, fromEntities[4]);

    // NULL文字列をServiceが空文字列へ正規化することも確認する。
    fromEntities[0].previousLastElliotLabel = NULL;
    fromEntities[0].latestSubElliotLabel = NULL;
}

/**
 * 旧スキーマを再現するため、最新補完ポイント列を削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 削除できた場合true。
 */
bool removeAddedPointSchemaForMigrationTest(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string sql = "ALTER TABLE zigzag_elliot_observation_timeframes ";
    sql += "DROP COLUMN latest_point_is_added";

    return executeSql(
        fromDatabaseHandle,
        sql,
        "remove latest point is-added schema for migration test",
        fromLogger
    );
}

/**
 * 非破壊migrationで追加したnullable最新補完ポイント列を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromObservationId 列追加前に保存したObservation ID。
 * @param fromLogger ロガー。
 * @return 列定義と既存行のNULLが正しい場合true。
 */
bool verifyAddedPointMigration(
    const int fromDatabaseHandle,
    const long fromObservationId,
    Logger &fromLogger
) {
    long schemaCount = 0;
    long legacyNullCount = 0;
    string observationIdText = StringFormat("%I64d", fromObservationId);

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM sqlite_master "
                + "WHERE type = 'table' "
                + "AND name = 'zigzag_elliot_observation_timeframes' "
                + "AND LOWER(sql) LIKE "
                + "'%latest_point_is_added integer%' "
                + "AND LOWER(sql) LIKE '%check(latest_point_is_added is null "
                + "or latest_point_is_added in (0, 1))%'",
            schemaCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    + "FROM zigzag_elliot_observation_timeframes "
                    + "WHERE observation_id = " + observationIdText + " "
                    + "AND latest_point_is_added IS NULL",
                legacyNullCount,
                fromLogger
            )) {
        return false;
    }

    if (schemaCount == 1 && legacyNullCount == 5) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Added point migration mismatch. schema=%I64d legacyNull=%I64d",
            schemaCount,
            legacyNullCount
        )
    );

    return false;
}

/**
 * 新規行の最新補完ポイント値が0または1で保存されたことを確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromObservationId 新規保存したObservation ID。
 * @param fromLogger ロガー。
 * @return Fixtureの0・1がすべて一致する場合true。
 */
bool verifyAddedPointValues(
    const int fromDatabaseHandle,
    const long fromObservationId,
    Logger &fromLogger
) {
    long validCount = 0;
    long addedCount = 0;
    long normalCount = 0;
    string observationIdText = StringFormat("%I64d", fromObservationId);

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) "
                + "FROM zigzag_elliot_observation_timeframes "
                + "WHERE observation_id = " + observationIdText + " "
                + "AND latest_point_is_added IN (0, 1)",
            validCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    + "FROM zigzag_elliot_observation_timeframes "
                    + "WHERE observation_id = " + observationIdText + " "
                    + "AND latest_point_is_added = 1",
                addedCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    + "FROM zigzag_elliot_observation_timeframes "
                    + "WHERE observation_id = " + observationIdText + " "
                    + "AND latest_point_is_added = 0",
                normalCount,
                fromLogger
            )) {
        return false;
    }

    if (validCount == 5 && addedCount == 2 && normalCount == 3) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Added point value mismatch. valid=%I64d added=%I64d normal=%I64d",
            validCount,
            addedCount,
            normalCount
        )
    );

    return false;
}

/**
 * 旧スキーマを再現するため、スプレッド列を削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 削除できた場合true。
 */
bool removeSpreadSchemaForMigrationTest(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    return executeSql(
        fromDatabaseHandle,
        "ALTER TABLE zigzag_elliot_observations DROP COLUMN spread_pips",
        "remove spread schema for migration test",
        fromLogger
    );
}

/**
 * 非破壊migrationで追加したnullableスプレッド列を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 列定義が正しい場合true。
 */
bool verifySpreadMigration(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    long columnCount = 0;

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM sqlite_master "
                + "WHERE type = 'table' "
                + "AND name = 'zigzag_elliot_observations' "
                + "AND LOWER(sql) LIKE '%spread_pips real%' "
                + "AND LOWER(sql) LIKE "
                + "'%check(spread_pips is null or spread_pips >= 0)%'",
            columnCount,
            fromLogger
        )) {
        return false;
    }

    if (columnCount == 1) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Spread migration mismatch. columnCount=%I64d",
            columnCount
        )
    );

    return false;
}

/**
 * 旧スキーマを再現するため、pip size列を削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 削除できた場合true。
 */
bool removePipSizeSchemaForMigrationTest(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    return executeSql(
        fromDatabaseHandle,
        "ALTER TABLE zigzag_elliot_observations DROP COLUMN pip_size",
        "remove pip size schema for migration test",
        fromLogger
    );
}

/**
 * pip size列定義とJPY・非JPYの既存行補完を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromNonJpyObservationId 非JPY Observation ID。
 * @param fromJpyObservationId JPY Observation ID。
 * @param fromLogger ロガー。
 * @return 列定義と補完値が正しい場合true。
 */
bool verifyPipSizeMigration(
    const int fromDatabaseHandle,
    const long fromNonJpyObservationId,
    const long fromJpyObservationId,
    Logger &fromLogger
) {
    long schemaCount = 0;
    long jpyValueCount = 0;
    long nonJpyValueCount = 0;
    long invalidValueCount = 0;
    string nonJpyObservationIdText = StringFormat(
        "%I64d",
        fromNonJpyObservationId
    );
    string jpyObservationIdText = StringFormat(
        "%I64d",
        fromJpyObservationId
    );

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM sqlite_master "
                + "WHERE type = 'table' "
                + "AND name = 'zigzag_elliot_observations' "
                + "AND LOWER(sql) LIKE '%pip_size real%' "
                + "AND LOWER(sql) LIKE "
                + "'%check(pip_size is null or pip_size > 0)%'",
            schemaCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_observations "
                    + "WHERE id = " + jpyObservationIdText + " "
                    + "AND symbol_name = 'USDJPY' "
                    + "AND ABS(pip_size - 0.01) < 0.000000001",
                jpyValueCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_observations "
                    + "WHERE id = " + nonJpyObservationIdText + " "
                    + "AND symbol_name = 'GBPAUD' "
                    + "AND ABS(pip_size - 0.0001) < 0.000000001",
                nonJpyValueCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_observations "
                    + "WHERE id IN (" + nonJpyObservationIdText + ","
                    + jpyObservationIdText + ") "
                    + "AND (pip_size IS NULL OR pip_size <= 0)",
                invalidValueCount,
                fromLogger
            )) {
        return false;
    }

    if (schemaCount == 1
            && jpyValueCount == 1
            && nonJpyValueCount == 1
            && invalidValueCount == 0) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Pip size migration mismatch. schema=%I64d jpy=%I64d "
                + "nonJpy=%I64d invalid=%I64d",
            schemaCount,
            jpyValueCount,
            nonJpyValueCount,
            invalidValueCount
        )
    );

    return false;
}

/**
 * 旧スキーマを再現するため、日本時刻列と専用インデックスを削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 全対象を削除できた場合true。
 */
bool removeJstSchemaForMigrationTest(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string sqlList[11];
    sqlList[0] = "DROP INDEX IF EXISTS ";
    sqlList[0] += "idx_zigzag_elliot_observations_profile_jst";
    sqlList[1] = "DROP INDEX IF EXISTS ";
    sqlList[1] += "idx_zigzag_elliot_observations_mode_profile_jst";
    sqlList[2] = "DROP INDEX IF EXISTS ";
    sqlList[2] += "idx_zigzag_elliot_observations_mode_symbol_jst";
    sqlList[3] = "DROP INDEX IF EXISTS ";
    sqlList[3] += "idx_zigzag_elliot_observations_mode_jst";
    sqlList[4] = "DROP INDEX IF EXISTS ";
    sqlList[4] += "idx_zigzag_elliot_observations_jst_id";
    sqlList[5] = "DROP INDEX IF EXISTS ";
    sqlList[5] += "idx_zigzag_elliot_observations_jst_missing";
    sqlList[6] = "DROP INDEX IF EXISTS ";
    sqlList[6] += "idx_zigzag_elliot_observation_timeframes_jst_missing";
    sqlList[7] = "ALTER TABLE zigzag_elliot_observation_timeframes ";
    sqlList[7] += "DROP COLUMN latest_point_jst_time_text";
    sqlList[8] = "ALTER TABLE zigzag_elliot_observation_timeframes ";
    sqlList[8] += "DROP COLUMN latest_point_jst_time";
    sqlList[9] = "ALTER TABLE zigzag_elliot_observations ";
    sqlList[9] += "DROP COLUMN anchor_jst_time_text";
    sqlList[10] = "ALTER TABLE zigzag_elliot_observations ";
    sqlList[10] += "DROP COLUMN anchor_jst_time";

    for (int i = 0; i < ArraySize(sqlList); i++) {
        if (!executeSql(
                fromDatabaseHandle,
                sqlList[i],
                "remove JST schema for migration test",
                fromLogger
            )) {
            return false;
        }
    }

    return true;
}

/**
 * 旧スキーマから追加・補完した日本時刻列と検索インデックスを確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromObservationId 観測ID。
 * @param fromObservationEntity 変換元親Entity。
 * @param fromTimeFrameEntities 変換元子Entity一覧。
 * @param fromLogger ロガー。
 * @return 日本時刻列、補完値、インデックスが正しい場合true。
 */
bool verifyJstMigration(
    const int fromDatabaseHandle,
    const long fromObservationId,
    ZigZagElliotObservationEntity &fromObservationEntity,
    ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[],
    Logger &fromLogger
) {
    datetime expectedAnchorJstTime = TimeJapanUtil::getJapanTime(
        fromObservationEntity.anchorBarTime
    );
    string expectedAnchorJstTimeText = TimeToString(
        expectedAnchorJstTime,
        TIME_DATE | TIME_SECONDS
    );

    if ((long)(expectedAnchorJstTime - fromObservationEntity.anchorBarTime)
            != 21600) {
        fromLogger.error(__FUNCTION__, "Summer fixture offset is invalid.");

        return false;
    }

    string observationIdText = StringFormat("%I64d", fromObservationId);
    string parentSql =
        "SELECT COUNT(*) FROM zigzag_elliot_observations WHERE id = ";
    parentSql += observationIdText;
    parentSql += " AND anchor_jst_time = ";
    parentSql += StringFormat("%I64d", (long)expectedAnchorJstTime);
    parentSql += " AND anchor_jst_time_text = '";
    parentSql += expectedAnchorJstTimeText + "'";

    string childSql = "SELECT COUNT(*) FROM ";
    childSql += "zigzag_elliot_observation_timeframes WHERE observation_id = ";
    childSql += observationIdText + " AND (";

    int expectedOffsetSeconds[5];
    expectedOffsetSeconds[0] = 25200;
    expectedOffsetSeconds[1] = 25200;
    expectedOffsetSeconds[2] = 21600;
    expectedOffsetSeconds[3] = 21600;
    expectedOffsetSeconds[4] = 25200;

    if (ArraySize(fromTimeFrameEntities) != ArraySize(expectedOffsetSeconds)) {
        fromLogger.error(__FUNCTION__, "DST fixture count is invalid.");

        return false;
    }

    for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
        datetime expectedPointJstTime = TimeJapanUtil::getJapanTime(
            fromTimeFrameEntities[i].latestPointTime
        );
        string expectedPointJstTimeText = TimeToString(
            expectedPointJstTime,
            TIME_DATE | TIME_SECONDS
        );

        if ((long)(
                expectedPointJstTime
                - fromTimeFrameEntities[i].latestPointTime
            ) != expectedOffsetSeconds[i]) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("DST boundary fixture is invalid. index=%d", i)
            );

            return false;
        }

        if (i > 0) {
            childSql += " OR ";
        }

        childSql += "(time_frame = ";
        childSql += IntegerToString(fromTimeFrameEntities[i].timeFrame);
        childSql += " AND latest_point_jst_time = ";
        childSql += StringFormat("%I64d", (long)expectedPointJstTime);
        childSql += " AND latest_point_jst_time_text = '";
        childSql += expectedPointJstTimeText + "')";
    }

    childSql += ")";
    long parentCount = 0;
    long childCount = 0;
    long indexCount = 0;
    long partialIndexCount = 0;
    long busyTimeout = 0;
    string parentQueryPlan = "";
    string childQueryPlan = "";

    if (!readLong(
            fromDatabaseHandle,
            parentSql,
            parentCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                childSql,
                childCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' "
                    + "AND name IN ("
                    + "'idx_zigzag_elliot_observations_mode_jst',"
                    + "'idx_zigzag_elliot_observations_mode_symbol_jst',"
                    + "'idx_zigzag_elliot_observations_jst_id',"
                    + "'idx_zigzag_elliot_observations_jst_missing',"
                    + "'idx_zigzag_elliot_observation_timeframes_jst_missing')",
                indexCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' "
                    + "AND name IN ("
                    + "'idx_zigzag_elliot_observations_jst_missing',"
                    + "'idx_zigzag_elliot_observation_timeframes_jst_missing') "
                    + "AND LOWER(sql) LIKE '% where %'",
                partialIndexCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "PRAGMA busy_timeout",
                busyTimeout,
                fromLogger
            )
            || !readText(
                fromDatabaseHandle,
                "EXPLAIN QUERY PLAN SELECT COUNT(*) FROM "
                    + "zigzag_elliot_observations "
                    + "WHERE anchor_jst_time <= 0 "
                    + "OR anchor_jst_time_text = ''",
                parentQueryPlan,
                fromLogger,
                3
            )
            || !readText(
                fromDatabaseHandle,
                "EXPLAIN QUERY PLAN SELECT COUNT(*) FROM "
                    + "zigzag_elliot_observation_timeframes "
                    + "WHERE latest_point_jst_time <= 0 "
                    + "OR latest_point_jst_time_text = ''",
                childQueryPlan,
                fromLogger,
                3
            )) {
        return false;
    }

    if (parentCount == 1
            && childCount == ArraySize(fromTimeFrameEntities)
            && indexCount == 5
            && partialIndexCount == 2
            && busyTimeout == 5000
            && StringFind(
                parentQueryPlan,
                "idx_zigzag_elliot_observations_jst_missing"
            ) >= 0
            && StringFind(
                childQueryPlan,
                "idx_zigzag_elliot_observation_timeframes_jst_missing"
            ) >= 0) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "JST migration mismatch. parent=%I64d child=%I64d indexes=%I64d "
                + "partialIndexes=%I64d busyTimeout=%I64d "
                + "parentPlan=%s childPlan=%s",
            parentCount,
            childCount,
            indexCount,
            partialIndexCount,
            busyTimeout,
            parentQueryPlan,
            childQueryPlan
        )
    );

    return false;
}

/**
 * 観測親子IDが未保存状態へ戻っているか確認する。
 *
 * @param fromObservationEntity 観測親Entity。
 * @param fromTimeFrameEntities 時間足別Entity一覧。
 * @return 全IDが0の場合true。
 */
bool areSnapshotIdsCleared(
    ZigZagElliotObservationEntity &fromObservationEntity,
    ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
) {
    if (fromObservationEntity.id != 0) {
        return false;
    }

    for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
        if (fromTimeFrameEntities[i].id != 0
                || fromTimeFrameEntities[i].observationId != 0) {
            return false;
        }
    }

    return true;
}

/**
 * 新規保存後の観測親子IDが割り当てられたか確認する。
 *
 * @param fromObservationEntity 観測親Entity。
 * @param fromTimeFrameEntities 時間足別Entity一覧。
 * @return 親子IDと関連IDが正しい場合true。
 */
bool areSnapshotIdsAssigned(
    ZigZagElliotObservationEntity &fromObservationEntity,
    ZigZagElliotObservationTimeFrameEntity &fromTimeFrameEntities[]
) {
    if (fromObservationEntity.id <= 0) {
        return false;
    }

    for (int i = 0; i < ArraySize(fromTimeFrameEntities); i++) {
        if (fromTimeFrameEntities[i].id <= 0
                || fromTimeFrameEntities[i].observationId
                    != fromObservationEntity.id) {
            return false;
        }
    }

    return true;
}

/**
 * 観測親子の総件数が期待値と一致するか確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromExpectedObservationCount 観測親期待件数。
 * @param fromExpectedTimeFrameCount 時間足別期待件数。
 * @param fromLogger ロガー。
 * @return 件数が一致する場合true。
 */
bool verifyTotalCounts(
    const int fromDatabaseHandle,
    const long fromExpectedObservationCount,
    const long fromExpectedTimeFrameCount,
    Logger &fromLogger
) {
    long observationCount = 0;
    long timeFrameCount = 0;

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM zigzag_elliot_observations",
            observationCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    "FROM zigzag_elliot_observation_timeframes",
                timeFrameCount,
                fromLogger
            )) {
        return false;
    }

    if (observationCount != fromExpectedObservationCount
            || timeFrameCount != fromExpectedTimeFrameCount) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Count mismatch. observations=%I64d/%I64d timeFrames=%I64d/%I64d",
                observationCount,
                fromExpectedObservationCount,
                timeFrameCount,
                fromExpectedTimeFrameCount
            )
        );

        return false;
    }

    return true;
}

/**
 * 保存済み観測、固定5時間足、first-write方針およびSQLite整合性を確認する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromRunId 実行情報ID。
 * @param fromObservationId 観測ID。
 * @param fromLogger ロガー。
 * @return 全検証に成功した場合true。
 */
bool verifySavedObservation(
    const int fromDatabaseHandle,
    const long fromRunId,
    const long fromObservationId,
    Logger &fromLogger
) {
    string runIdText = StringFormat("%I64d", fromRunId);
    string observationIdText = StringFormat("%I64d", fromObservationId);
    long runCount = 0;
    long observationCount = 0;
    long timeFrameCount = 0;
    long layoutCount = 0;
    long h1AnchorCount = 0;
    long invalidAnchorCount = 0;
    long spreadValueCount = 0;
    long pipSizeValueCount = 0;
    long legacyAddedPointNullCount = 0;
    long retainedHashCount = 0;
    long replacedChildCount = 0;
    long normalizedTextCount = 0;
    long foreignKeysEnabled = 0;
    long rawColumnTableCount = 0;
    long pointTableCount = 0;
    string integrityResult = "";

    string layoutSql =
        "SELECT COUNT(*) FROM zigzag_elliot_observation_timeframes "
        "WHERE observation_id = " + observationIdText + " AND (";
    layoutSql += StringFormat(
        "(time_frame = %d AND time_frame_order = 0) OR ",
        (int)PERIOD_MN1
    );
    layoutSql += StringFormat(
        "(time_frame = %d AND time_frame_order = 1) OR ",
        (int)PERIOD_W1
    );
    layoutSql += StringFormat(
        "(time_frame = %d AND time_frame_order = 2) OR ",
        (int)PERIOD_D1
    );
    layoutSql += StringFormat(
        "(time_frame = %d AND time_frame_order = 3) OR ",
        (int)PERIOD_H4
    );
    layoutSql += StringFormat(
        "(time_frame = %d AND time_frame_order = 4))",
        (int)PERIOD_H1
    );

    if (!readLong(
            fromDatabaseHandle,
            "SELECT COUNT(*) FROM zigzag_elliot_alert_runs WHERE id = "
                + runIdText,
            runCount,
            fromLogger
        )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_observations WHERE id = "
                    + observationIdText + " AND run_id = " + runIdText
                    + " AND anchor_time_frame = "
                    + IntegerToString((int)PERIOD_H1)
                    + " AND capture_phase = 'BAR_OPEN_FIRST_SUCCESS'",
                observationCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    "FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = " + observationIdText,
                timeFrameCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                layoutSql,
                layoutCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    "FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = " + observationIdText
                    + " AND time_frame = "
                    + IntegerToString((int)PERIOD_H1)
                    + " AND time_frame_order = 4 "
                    + "AND is_anchor_time_frame = 1",
                h1AnchorCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    "FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = " + observationIdText
                    + " AND is_anchor_time_frame = 1 "
                    + "AND time_frame <> "
                    + IntegerToString((int)PERIOD_H1),
                invalidAnchorCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_observations WHERE id = "
                    + observationIdText
                    + " AND ABS(spread_pips - 31.4) < 0.000001",
                spreadValueCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_observations WHERE id = "
                    + observationIdText
                    + " AND ABS(pip_size - 0.0001) < 0.000000001",
                pipSizeValueCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    "FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = " + observationIdText
                    + " AND latest_point_is_added IS NULL",
                legacyAddedPointNullCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM zigzag_elliot_observations WHERE id = "
                    + observationIdText
                    + " AND snapshot_hash = 'observation-snapshot-v1'",
                retainedHashCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    "FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = " + observationIdText
                    + " AND latest_elliot_label = 'REPLACED'",
                replacedChildCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) "
                    "FROM zigzag_elliot_observation_timeframes "
                    "WHERE observation_id = " + observationIdText
                    + " AND time_frame = "
                    + IntegerToString((int)PERIOD_MN1)
                    + " AND previous_last_elliot_label = '' "
                    + "AND previous_last_elliot_label IS NOT NULL "
                    + "AND latest_sub_elliot_label = '' "
                    + "AND latest_sub_elliot_label IS NOT NULL",
                normalizedTextCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "PRAGMA foreign_keys",
                foreignKeysEnabled,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM sqlite_master "
                    "WHERE type = 'table' "
                    "AND name IN ('zigzag_elliot_observations', "
                    "'zigzag_elliot_observation_timeframes') "
                    "AND LOWER(sql) LIKE '%raw_csv%'",
                rawColumnTableCount,
                fromLogger
            )
            || !readLong(
                fromDatabaseHandle,
                "SELECT COUNT(*) FROM sqlite_master "
                    "WHERE type = 'table' "
                    "AND name = 'zigzag_elliot_observation_points'",
                pointTableCount,
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
            || observationCount != 1
            || timeFrameCount != 5
            || layoutCount != 5
            || h1AnchorCount != 1
            || invalidAnchorCount != 0
            || spreadValueCount != 1
            || pipSizeValueCount != 1
            || legacyAddedPointNullCount != 5
            || retainedHashCount != 1
            || replacedChildCount != 0
            || normalizedTextCount != 1
            || foreignKeysEnabled != 1
            || rawColumnTableCount != 0
            || pointTableCount != 0
            || integrityResult != "ok") {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Observation mismatch. runs=%I64d observations=%I64d "
                + "timeFrames=%I64d layout=%I64d h1Anchor=%I64d "
                + "invalidAnchor=%I64d spread=%I64d pipSize=%I64d "
                + "legacyAddedNull=%I64d retainedHash=%I64d "
                + "replacedChild=%I64d normalized=%I64d "
                + "foreignKeys=%I64d rawTables=%I64d pointTables=%I64d "
                + "integrity=%s",
                runCount,
                observationCount,
                timeFrameCount,
                layoutCount,
                h1AnchorCount,
                invalidAnchorCount,
                spreadValueCount,
                pipSizeValueCount,
                legacyAddedPointNullCount,
                retainedHashCount,
                replacedChildCount,
                normalizedTextCount,
                foreignKeysEnabled,
                rawColumnTableCount,
                pointTableCount,
                integrityResult
            )
        );

        return false;
    }

    return verifyNoRows(
        fromDatabaseHandle,
        "PRAGMA foreign_key_check",
        fromLogger
    );
}

/**
 * 子INSERTを意図的に失敗させるロールバック検証Triggerを作成する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 作成に成功した場合true。
 */
bool createRollbackTrigger(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    string sql = "CREATE TRIGGER " + rollbackTriggerName + " ";
    sql += "BEFORE INSERT ON zigzag_elliot_observation_timeframes ";
    sql += "WHEN NEW.time_frame = "
        + IntegerToString((int)PERIOD_D1) + " ";
    sql += "BEGIN SELECT RAISE(ABORT, 'forced smoke rollback'); END";

    return executeSql(
        fromDatabaseHandle,
        sql,
        "create rollback trigger",
        fromLogger
    );
}

/**
 * ロールバック検証Triggerを削除する。
 *
 * @param fromDatabaseHandle データベースハンドル。
 * @param fromLogger ロガー。
 * @return 削除に成功した場合true。
 */
bool dropRollbackTrigger(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    return executeSql(
        fromDatabaseHandle,
        "DROP TRIGGER IF EXISTS " + rollbackTriggerName,
        "drop rollback trigger",
        fromLogger
    );
}

/**
 * ZigZagElliot H1 Observation DBのSmokeTestを実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!prepareSmokeDatabase(logger)) {
        logger.error(__FUNCTION__, "Database preparation failed.");

        return;
    }

    SqliteDatabase database(databaseFileName, useCommonFolder);

    if (!database.open()) {
        logger.error(__FUNCTION__, "Database open failed.");

        return;
    }

    int databaseHandle = database.getHandle();

    if (!createLegacyRunTable(databaseHandle, logger)) {
        logger.error(__FUNCTION__, "Legacy Run table preparation failed.");

        return;
    }

    ZigZagElliotAlertRunDao runDao(databaseHandle);
    ZigZagElliotObservationDao observationDao(databaseHandle);
    ZigZagElliotObservationTimeFrameDao timeFrameDao(databaseHandle);
    ZigZagElliotObservationPersistenceService persistenceService(
        databaseHandle,
        GetPointer(observationDao),
        GetPointer(timeFrameDao)
    );

    if (!runDao.createTable() || !persistenceService.createTables()) {
        logger.error(__FUNCTION__, "Observation table creation failed.");

        return;
    }

    if (!removeSpreadSchemaForMigrationTest(databaseHandle, logger)
            || !persistenceService.createTables()
            || !verifySpreadMigration(databaseHandle, logger)
            || !persistenceService.createTables()) {
        logger.error(__FUNCTION__, "Spread schema migration verification failed.");

        return;
    }

    logger.info(__FUNCTION__, "Spread schema migration was verified.");

    ZigZagElliotAlertRunEntity runEntity;
    initializeRunEntity(runEntity);

    if (!runDao.insert(runEntity)
            || runEntity.id <= 0
            || !verifyRunAnalysisProfile(
                databaseHandle,
                runEntity,
                logger
            )) {
        logger.error(__FUNCTION__, "Run save failed.");

        return;
    }

    ZigZagElliotObservationEntity observationEntity;
    ZigZagElliotObservationTimeFrameEntity timeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 00:00:00',
        "observation-snapshot-v1",
        observationEntity
    );
    initializeTimeFrameEntities(timeFrameEntities);

    if (!persistenceService.saveSnapshot(
            observationEntity,
            timeFrameEntities
        )
            || !areSnapshotIdsAssigned(
                observationEntity,
                timeFrameEntities
            )) {
        logger.error(__FUNCTION__, "First observation save failed.");

        return;
    }

    long firstObservationId = observationEntity.id;

    if (!removeAddedPointSchemaForMigrationTest(databaseHandle, logger)
            || !persistenceService.createTables()
            || !verifyAddedPointMigration(
                databaseHandle,
                firstObservationId,
                logger
            )
            || !persistenceService.createTables()
            || !verifyAddedPointMigration(
                databaseHandle,
                firstObservationId,
                logger
            )) {
        logger.error(
            __FUNCTION__,
            "Added point schema migration verification failed."
        );

        return;
    }

    logger.info(
        __FUNCTION__,
        "Added point schema migration was verified."
    );

    ZigZagElliotObservationEntity jpyMigrationObservationEntity;
    ZigZagElliotObservationTimeFrameEntity jpyMigrationTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 00:00:00',
        "observation-snapshot-pip-size-migration-jpy",
        jpyMigrationObservationEntity
    );
    initializeTimeFrameEntities(jpyMigrationTimeFrameEntities);
    jpyMigrationObservationEntity.symbolName = "USDJPY";
    jpyMigrationObservationEntity.pipSize = 0.01;

    if (!persistenceService.saveSnapshot(
            jpyMigrationObservationEntity,
            jpyMigrationTimeFrameEntities
        )
            || !areSnapshotIdsAssigned(
                jpyMigrationObservationEntity,
                jpyMigrationTimeFrameEntities
            )
            || !verifyAddedPointValues(
                databaseHandle,
                jpyMigrationObservationEntity.id,
                logger
            )) {
        logger.error(__FUNCTION__, "JPY migration observation save failed.");

        return;
    }

    long jpyMigrationObservationId = jpyMigrationObservationEntity.id;
    string deleteJpyMigrationSql =
        "DELETE FROM zigzag_elliot_observations WHERE id = ";
    deleteJpyMigrationSql += StringFormat(
        "%I64d",
        jpyMigrationObservationId
    );

    if (!removePipSizeSchemaForMigrationTest(databaseHandle, logger)
            || !persistenceService.createTables()
            || !verifyPipSizeMigration(
                databaseHandle,
                firstObservationId,
                jpyMigrationObservationId,
                logger
            )
            || !persistenceService.createTables()
            || !verifyPipSizeMigration(
                databaseHandle,
                firstObservationId,
                jpyMigrationObservationId,
                logger
            )
            || !executeSql(
                databaseHandle,
                deleteJpyMigrationSql,
                "delete JPY pip size migration observation",
                logger
            )
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(
            __FUNCTION__,
            "Pip size schema migration verification failed."
        );

        return;
    }

    logger.info(__FUNCTION__, "Pip size schema migration was verified.");

    if (!removeJstSchemaForMigrationTest(databaseHandle, logger)
            || !persistenceService.createTables()
            || !verifyJstMigration(
                databaseHandle,
                firstObservationId,
                observationEntity,
                timeFrameEntities,
                logger
            )) {
        logger.error(__FUNCTION__, "JST schema migration verification failed.");

        return;
    }

    logger.info(__FUNCTION__, "JST schema migration was verified.");

    ZigZagElliotObservationEntity duplicateObservationEntity;
    ZigZagElliotObservationTimeFrameEntity duplicateTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 00:00:00',
        "observation-snapshot-v1",
        duplicateObservationEntity
    );
    initializeTimeFrameEntities(duplicateTimeFrameEntities);

    if (!persistenceService.saveSnapshot(
            duplicateObservationEntity,
            duplicateTimeFrameEntities
        )
            || duplicateObservationEntity.id != firstObservationId
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(__FUNCTION__, "Same-hash duplicate verification failed.");

        return;
    }

    ZigZagElliotObservationEntity changedHashObservationEntity;
    ZigZagElliotObservationTimeFrameEntity changedHashTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 00:00:00',
        "observation-snapshot-v2",
        changedHashObservationEntity
    );
    initializeTimeFrameEntities(changedHashTimeFrameEntities);
    changedHashTimeFrameEntities[4].latestElliotLabel = "REPLACED";

    if (!persistenceService.saveSnapshot(
            changedHashObservationEntity,
            changedHashTimeFrameEntities
        )
            || changedHashObservationEntity.id != firstObservationId
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(__FUNCTION__, "First-write retention verification failed.");

        return;
    }

    ZigZagElliotObservationEntity invalidObservationEntity;
    ZigZagElliotObservationTimeFrameEntity invalidTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 01:00:00',
        "observation-snapshot-invalid",
        invalidObservationEntity
    );
    initializeTimeFrameEntities(invalidTimeFrameEntities);
    invalidObservationEntity.anchorJstTime = 0;
    logger.info(
        __FUNCTION__,
        "Starting expected parent JST validation failure verification."
    );

    if (persistenceService.saveSnapshot(
            invalidObservationEntity,
            invalidTimeFrameEntities
        )
            || !areSnapshotIdsCleared(
                invalidObservationEntity,
                invalidTimeFrameEntities
            )
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(__FUNCTION__, "Parent JST validation failure verification failed.");

        return;
    }

    logger.info(__FUNCTION__, "Expected parent JST validation failure was verified.");

    ZigZagElliotObservationEntity invalidChildObservationEntity;
    ZigZagElliotObservationTimeFrameEntity invalidChildTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 01:00:00',
        "observation-snapshot-invalid-child-jst",
        invalidChildObservationEntity
    );
    initializeTimeFrameEntities(invalidChildTimeFrameEntities);
    invalidChildTimeFrameEntities[4].latestPointJstTime = 0;
    logger.info(
        __FUNCTION__,
        "Starting expected child JST validation failure verification."
    );

    if (persistenceService.saveSnapshot(
            invalidChildObservationEntity,
            invalidChildTimeFrameEntities
        )
            || !areSnapshotIdsCleared(
                invalidChildObservationEntity,
                invalidChildTimeFrameEntities
            )
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(__FUNCTION__, "Child JST validation failure verification failed.");

        return;
    }

    logger.info(__FUNCTION__, "Expected child JST validation failure was verified.");

    ZigZagElliotObservationEntity invalidSpreadObservationEntity;
    ZigZagElliotObservationTimeFrameEntity invalidSpreadTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 01:00:00',
        "observation-snapshot-invalid-spread",
        invalidSpreadObservationEntity
    );
    initializeTimeFrameEntities(invalidSpreadTimeFrameEntities);
    invalidSpreadObservationEntity.spreadPips = -0.1;
    logger.info(
        __FUNCTION__,
        "Starting expected spread validation failure verification."
    );

    if (persistenceService.saveSnapshot(
            invalidSpreadObservationEntity,
            invalidSpreadTimeFrameEntities
        )
            || !areSnapshotIdsCleared(
                invalidSpreadObservationEntity,
                invalidSpreadTimeFrameEntities
            )
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(__FUNCTION__, "Spread validation failure verification failed.");

        return;
    }

    logger.info(__FUNCTION__, "Expected spread validation failure was verified.");

    ZigZagElliotObservationEntity invalidPipSizeObservationEntity;
    ZigZagElliotObservationTimeFrameEntity invalidPipSizeTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 01:00:00',
        "observation-snapshot-invalid-pip-size",
        invalidPipSizeObservationEntity
    );
    initializeTimeFrameEntities(invalidPipSizeTimeFrameEntities);
    invalidPipSizeObservationEntity.pipSize = 0.0;
    logger.info(
        __FUNCTION__,
        "Starting expected pip size validation failure verification."
    );

    if (persistenceService.saveSnapshot(
            invalidPipSizeObservationEntity,
            invalidPipSizeTimeFrameEntities
        )
            || !areSnapshotIdsCleared(
                invalidPipSizeObservationEntity,
                invalidPipSizeTimeFrameEntities
            )
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(
            __FUNCTION__,
            "Pip size validation failure verification failed."
        );

        return;
    }

    logger.info(
        __FUNCTION__,
        "Expected pip size validation failure was verified."
    );

    ZigZagElliotObservationEntity invalidAddedPointObservationEntity;
    ZigZagElliotObservationTimeFrameEntity invalidAddedPointTimeFrames[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 01:00:00',
        "observation-snapshot-invalid-added-point",
        invalidAddedPointObservationEntity
    );
    initializeTimeFrameEntities(invalidAddedPointTimeFrames);
    invalidAddedPointTimeFrames[3].latestPointIsAdded = 2;
    logger.info(
        __FUNCTION__,
        "Starting expected added point validation failure verification."
    );

    if (persistenceService.saveSnapshot(
            invalidAddedPointObservationEntity,
            invalidAddedPointTimeFrames
        )
            || !areSnapshotIdsCleared(
                invalidAddedPointObservationEntity,
                invalidAddedPointTimeFrames
            )
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(
            __FUNCTION__,
            "Added point validation failure verification failed."
        );

        return;
    }

    logger.info(
        __FUNCTION__,
        "Expected added point validation failure was verified."
    );

    if (!createRollbackTrigger(databaseHandle, logger)) {
        return;
    }

    ZigZagElliotObservationEntity rollbackObservationEntity;
    ZigZagElliotObservationTimeFrameEntity rollbackTimeFrameEntities[];
    initializeObservationEntity(
        runEntity.id,
        D'2026.07.20 02:00:00',
        "observation-snapshot-rollback",
        rollbackObservationEntity
    );
    initializeTimeFrameEntities(rollbackTimeFrameEntities);
    logger.info(
        __FUNCTION__,
        "Starting expected transaction rollback verification."
    );
    bool rollbackSaveResult = persistenceService.saveSnapshot(
        rollbackObservationEntity,
        rollbackTimeFrameEntities
    );
    bool isTriggerDropped = dropRollbackTrigger(databaseHandle, logger);

    if (rollbackSaveResult
            || !isTriggerDropped
            || !areSnapshotIdsCleared(
                rollbackObservationEntity,
                rollbackTimeFrameEntities
            )
            || !verifyTotalCounts(databaseHandle, 1, 5, logger)) {
        logger.error(__FUNCTION__, "Transaction rollback verification failed.");

        return;
    }

    logger.info(__FUNCTION__, "Expected transaction rollback was verified.");

    if (!verifySavedObservation(
            databaseHandle,
            runEntity.id,
            firstObservationId,
            logger
        )) {
        logger.error(__FUNCTION__, "Saved observation verification failed.");

        return;
    }

    database.close();
    logger.info(
        __FUNCTION__,
        StringFormat(
            "ZigZagElliot H1 observation database smoke test passed. "
            + "fileName=%s runId=%I64d observationId=%I64d timeFrames=5",
            databaseFileName,
            runEntity.id,
            firstObservationId
        )
    );
}
