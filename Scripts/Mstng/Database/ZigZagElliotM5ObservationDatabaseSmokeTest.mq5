//+------------------------------------------------------------------+
//|                   ZigZagElliotM5ObservationDatabaseSmokeTest.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property version   "1.01"

#include <Mstng\Database\Dao\ZigZagElliotAlertRunDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationCaptureMetricsDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationDao.mqh>
#include <Mstng\Database\Dao\ZigZagElliotObservationTimeFrameDao.mqh>
#include <Mstng\Database\Service\ZigZagElliotObservationDatabaseGuard.mqh>
#include <Mstng\Database\Service\ZigZagElliotObservationPersistenceService.mqh>
#include <Mstng\Database\ZigZagElliotM5ObservationDatabaseContext.mqh>
#include <Mstng\Elliot\ZigZagElliotObservationProfile.mqh>
#include <Mstng\ExpertAdvisor\ZigZagElliotObservationSnapshotBuilder.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>

/** GUID相当の専用ローカルファイルで接続テストも行う場合true。 */
input bool fileContextTestsEnabled = false;

/** テストのログ。 */
Logger testLogger;

/** 失敗した確認項目数。 */
int failedCount = 0;

/**
 * 検証結果を記録する。
 */
bool expect(const bool fromCondition, const string fromName) {
    if (!fromCondition) {
        failedCount++;
        testLogger.error(__FUNCTION__, "FAIL " + fromName);
        return false;
    }
    testLogger.info(__FUNCTION__, "PASS " + fromName);
    return true;
}

/**
 * メモリDB内のSQLを実行する。
 */
bool executeSql(const int fromHandle, const string fromSql) {
    return expect(DatabaseExecute(fromHandle, fromSql), "SQL " + fromSql);
}

/**
 * 集計SQLの先頭整数を期待値と比較する。
 */
bool expectLong(
    const int fromHandle,
    const string fromSql,
    const long fromExpected,
    const string fromName
) {
    int requestHandle = DatabasePrepare(fromHandle, fromSql);
    if (requestHandle == INVALID_HANDLE) {
        return expect(false, fromName + " prepare");
    }
    long actual = 0;
    bool isRead = DatabaseRead(requestHandle)
        && DatabaseColumnLong(requestHandle, 0, actual);
    DatabaseFinalize(requestHandle);
    return expect(isRead && actual == fromExpected, fromName + " actual=" + IntegerToString(actual));
}

/**
 * M5用途の読み取り検査と実際のスキーマ識別値を確認する。
 */
void expectGuard(const int fromHandle, const bool fromExpected, const string fromName) {
    bool isAllowed = false;
    string reason = "";
    bool isInspected = ZigZagElliotObservationDatabaseGuard::inspectM5(
        fromHandle, isAllowed, reason
    );
    expect(isInspected && isAllowed == fromExpected, fromName + " " + reason);
}

/**
 * 日時を既存DBの表記へ変換する。
 */
string dateText(const datetime fromTime) {
    return TimeToString(fromTime, TIME_DATE | TIME_SECONDS);
}

/**
 * 固定Profileに一致するテストRunを生成する。
 */
void initializeRun(
    const ZigZagElliotObservationProfile &fromProfile,
    ZigZagElliotAlertRunEntity &fromRun
) {
    ZeroMemory(fromRun);
    fromRun.runUid = "m5-memory-smoke-" + fromProfile.getStrategy();
    fromRun.schemaVersion = fromProfile.getSchemaVersion();
    fromRun.sourceMode = "TESTER";
    fromRun.source = "OBSERVATION_MEMORY_SMOKE";
    fromRun.sourceServer = "memory-smoke-server";
    fromRun.programName = "ZigZagElliotM5ObservationDatabaseSmokeTest";
    fromRun.programVersion = "1.01";
    fromRun.strategy = fromProfile.getStrategy();
    fromRun.strategyVersion = fromProfile.getStrategyVersion();
    fromRun.analysisVersion = fromProfile.getAnalysisVersion();
    fromRun.analysisInputText = fromProfile.createCanonicalText();
    fromRun.analysisInputHash = fromProfile.createHash();
    fromRun.testerModel = "SYNTHETIC_MEMORY_FIXTURE";
    fromRun.inputText = "memory-only";
    fromRun.inputHash = "memory-only";
    fromRun.startedAt = D'2026.09.10 11:00:00';
    fromRun.startedAtText = dateText(fromRun.startedAt);
    fromRun.marketStartedAt = fromRun.startedAt;
    fromRun.marketStartedAtText = fromRun.startedAtText;
    fromRun.createdAt = fromRun.startedAt;
    fromRun.createdAtText = fromRun.startedAtText;
    fromRun.status = "RUNNING";
    fromRun.errorText = "";
}

/**
 * 市場に接続しない構造化Snapshotを生成する。
 */
void initializeSnapshot(
    const ZigZagElliotObservationProfile &fromProfile,
    const ZigZagElliotAlertRunEntity &fromRun,
    const datetime fromAnchor,
    ZigZagElliotObservationSnapshot &fromSnapshot
) {
    fromSnapshot.clear();
    fromSnapshot.observation.runId = fromRun.id;
    fromSnapshot.observation.sourceMode = fromRun.sourceMode;
    fromSnapshot.observation.sourceServer = fromRun.sourceServer;
    fromSnapshot.observation.symbolName = "GBPAUD";
    fromSnapshot.observation.anchorTimeFrame = (int)fromProfile.getAnchorTimeFrame();
    string anchorText = EnumToString(fromProfile.getAnchorTimeFrame());
    StringReplace(anchorText, "PERIOD_", "");
    fromSnapshot.observation.anchorTimeFrameText = anchorText;
    fromSnapshot.observation.anchorBarTime = fromAnchor;
    fromSnapshot.observation.anchorBarTimeText = dateText(fromAnchor);
    fromSnapshot.observation.anchorJstTime = TimeJapanUtil::getJapanTime(fromAnchor);
    fromSnapshot.observation.anchorJstTimeText = dateText(fromSnapshot.observation.anchorJstTime);
    fromSnapshot.observation.capturePhase = fromProfile.getCapturePhase();
    fromSnapshot.observation.spreadPips = 31.4;
    fromSnapshot.observation.pipSize = 0.0001;
    fromSnapshot.observation.analysisVersion = fromRun.analysisVersion;
    fromSnapshot.observation.analysisInputHash = fromRun.analysisInputHash;
    fromSnapshot.observation.snapshotHash = "ORIGINAL_HASH";
    fromSnapshot.observation.timeFrameCount = fromProfile.getObservationTimeFrameCount();
    fromSnapshot.observation.createdAt = fromAnchor + 1;
    fromSnapshot.observation.createdAtText = dateText(fromAnchor + 1);
    int count = fromProfile.getObservationTimeFrameCount();
    ArrayResize(fromSnapshot.timeFrames, count);
    for (int i = 0; i < count; i++) {
        ZigZagElliotObservationTimeFrameEntity entity;
        ZeroMemory(entity);
        entity.timeFrame = (int)fromProfile.getObservationTimeFrame(i);
        entity.timeFrameText = EnumToString(fromProfile.getObservationTimeFrame(i));
        StringReplace(entity.timeFrameText, "PERIOD_", "");
        entity.timeFrameOrder = i;
        if (i == count - 1) {
            entity.isAnchorTimeFrame = 1;
        }
        entity.pointCount = 2;
        entity.latestPointTime = fromAnchor;
        entity.latestPointTimeText = dateText(fromAnchor);
        entity.latestPointJstTime = TimeJapanUtil::getJapanTime(fromAnchor);
        entity.latestPointJstTimeText = dateText(entity.latestPointJstTime);
        entity.latestPointRate = 1.3000;
        entity.previousOpen = 1.3000;
        entity.previousHigh = 1.3010;
        entity.previousLow = 1.2990;
        entity.previousClose = 1.3000;
        entity.currentOpen = 1.3000;
        entity.currentHigh = 1.3010;
        entity.currentLow = 1.2990;
        entity.currentClose = 1.3000;
        entity.createdAt = fromAnchor + 1;
        entity.createdAtText = dateText(entity.createdAt);
        fromSnapshot.timeFrames[i] = entity;
    }
    fromSnapshot.hasCaptureMetrics = fromProfile.requiresCaptureMetrics();
    fromSnapshot.captureMetrics.hasAnalysisElapsedMs = true;
    fromSnapshot.captureMetrics.analysisElapsedMs = 0;
    fromSnapshot.captureMetrics.hasCaptureElapsedMs = true;
    fromSnapshot.captureMetrics.captureElapsedMs = 120;
    fromSnapshot.captureMetrics.hasAnalysisAttemptCount = true;
    fromSnapshot.captureMetrics.analysisAttemptCount = 1;
}

/**
 * H1の固定HashとM5の固定観測契約を確認する。
 */
void testProfiles() {
    ZigZagElliotObservationProfile h1Profile;
    ZigZagElliotObservationProfile m5Profile(PERIOD_M5);
    ZigZagElliotObservationProfile invalidProfile(PERIOD_M15);
    string expectedHash = "a4c9b3633501890e7110a1122b370dc12787d15d12f1efae82ca7b9657c9efbf";
    expect(h1Profile.createHash() == expectedHash, "H1 canonical SHA-256 unchanged");
    expect(h1Profile.createCanonicalText() == ZigZagElliotAnalysisProfile::createCanonicalText(),
        "H1 canonical delegation unchanged");
    expect(h1Profile.getObservationTimeFrameCount() == 5
        && h1Profile.getAnchorTimeFrame() == PERIOD_H1, "H1 5 timeframes");
    expect(m5Profile.getObservationTimeFrameCount() == 7
        && m5Profile.getAnchorTimeFrame() == PERIOD_M5, "M5 7 timeframes");
    expect(m5Profile.getObservationTimeFrameOrderText() == "49153,32769,16408,16388,16385,15,5",
        "M5 exact timeframe order");
    expect(m5Profile.getObservationTimeFrame(-1) == PERIOD_CURRENT
        && m5Profile.getObservationTimeFrame(7) == PERIOD_CURRENT, "out of range timeframe");
    expect(!invalidProfile.isValid() && invalidProfile.createHash() == "", "unsupported Profile rejected");
    expect(StringLen(m5Profile.createHash()) == 64 && m5Profile.createHash() != expectedHash,
        "M5 hash namespace differs");
    expect(StringFind(m5Profile.createCanonicalText(), "|ANCHOR_TF=5|") >= 0
        && StringFind(m5Profile.createCanonicalText(), "|ANCHOR_TF=16385|") < 0,
        "M5 canonical has no H1 anchor");
    expect(h1Profile.getSnapshotHashVersion() == "H1_OBSERVATION_V5"
        && m5Profile.getSnapshotHashVersion() == "M5_OBSERVATION_V1", "snapshot namespaces");
}

/**
 * 不正足構成・品質・実行元を保存前に拒否するか確認する。
 */
void testInvalidSnapshots(
    ZigZagElliotObservationPersistenceService &fromService,
    const ZigZagElliotObservationProfile &fromProfile,
    const ZigZagElliotAlertRunEntity &fromRun
) {
    ZigZagElliotObservationSnapshot snapshot;
    datetime anchor = D'2026.09.10 11:05:00';
    for (int i = 0; i < 10; i++) {
        initializeSnapshot(fromProfile, fromRun, anchor, snapshot);
        if (i == 0) {
            ArrayResize(snapshot.timeFrames, 6);
        } else if (i == 1) {
            snapshot.timeFrames[1].timeFrameOrder = 0;
        } else if (i == 2) {
            snapshot.timeFrames[4].isAnchorTimeFrame = 1;
        } else if (i == 3) {
            snapshot.timeFrames[5].timeFrame = PERIOD_M30;
        } else if (i == 4) {
            snapshot.observation.anchorTimeFrame = PERIOD_H1;
        } else if (i == 5) {
            snapshot.hasCaptureMetrics = false;
        } else if (i == 6) {
            snapshot.captureMetrics.analysisElapsedMs = -1;
        } else if (i == 7) {
            snapshot.captureMetrics.analysisAttemptCount = 0;
        } else if (i == 8) {
            snapshot.observation.sourceServer = "wrong-server";
        } else {
            snapshot.timeFrames[0].currentClose = EMPTY_VALUE;
        }
        expect(!fromService.saveSnapshot(snapshot), "invalid snapshot " + IntegerToString(i));
    }
}

/**
 * 子または品質INSERT失敗で親までロールバックされるか確認する。
 */
void testRollback(
    const int fromHandle,
    ZigZagElliotObservationPersistenceService &fromService,
    const ZigZagElliotObservationProfile &fromProfile,
    const ZigZagElliotAlertRunEntity &fromRun
) {
    for (int i = 0; i < 2; i++) {
        string tableName = "zigzag_elliot_observation_timeframes";
        string condition = " WHEN NEW.time_frame_order=2";
        if (i == 1) {
            tableName = "zigzag_elliot_observation_capture_metrics";
            condition = "";
        }
        string sql = "CREATE TRIGGER smoke_fail BEFORE INSERT ON " + tableName + condition;
        sql += " BEGIN SELECT RAISE(ABORT,'intentional rollback test'); END";
        if (!executeSql(fromHandle, sql)) {
            return;
        }
        ZigZagElliotObservationSnapshot snapshot;
        initializeSnapshot(fromProfile, fromRun, D'2026.09.10 11:10:00', snapshot);
        expect(!fromService.saveSnapshot(snapshot), "injected failure " + tableName);
        bool idsReset = snapshot.observation.id == 0 && snapshot.captureMetrics.observationId == 0;
        for (int j = 0; j < ArraySize(snapshot.timeFrames); j++) {
            idsReset = idsReset && snapshot.timeFrames[j].id == 0
                && snapshot.timeFrames[j].observationId == 0;
        }
        expect(idsReset, "rollback IDs reset " + tableName);
        expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observations", 1, "rollback parent count");
        expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_timeframes", 7, "rollback child count");
        expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_capture_metrics", 1, "rollback quality count");
        executeSql(fromHandle, "DROP TRIGGER smoke_fail");
    }
}

/**
 * 専用メモリDBでM5の原子的保存とfirst-writeを確認する。
 */
void testM5Database(const int fromHandle) {
    ZigZagElliotObservationProfile profile(PERIOD_M5);
    ZigZagElliotAlertRunDao runDao(fromHandle);
    ZigZagElliotObservationDao observationDao(fromHandle);
    ZigZagElliotObservationTimeFrameDao timeFrameDao(fromHandle);
    ZigZagElliotObservationCaptureMetricsDao metricsDao(fromHandle);
    ZigZagElliotObservationPersistenceService service(
        fromHandle, &observationDao, &timeFrameDao, profile, &metricsDao
    );
    expectGuard(fromHandle, true, "empty database accepted");
    if (!executeSql(fromHandle, "PRAGMA foreign_keys = ON")
            || !expect(DatabaseTransactionBegin(fromHandle), "fresh schema transaction begin")) {
        return;
    }
    bool isPrepared = runDao.createTable() && service.createTables();
    if (!expect(isPrepared, "M5 fresh tables inside one transaction")) {
        DatabaseTransactionRollback(fromHandle);
        return;
    }
    if (!expect(DatabaseTransactionCommit(fromHandle), "fresh schema transaction commit")) {
        DatabaseTransactionRollback(fromHandle);
        return;
    }
    expectGuard(fromHandle, true, "current runtime M5 schema fingerprint accepted");
    ZigZagElliotAlertRunEntity run;
    initializeRun(profile, run);
    if (!expect(runDao.insert(run) && run.id > 0, "M5 Run")) {
        return;
    }
    expectGuard(fromHandle, true, "M5 Run-only accepted");
    ZigZagElliotObservationSnapshot snapshot;
    initializeSnapshot(profile, run, D'2026.09.10 11:00:00', snapshot);
    expect(!service.saveSnapshot(snapshot.observation, snapshot.timeFrames), "M5 two-argument save rejects missing quality");
    if (!expect(service.saveSnapshot(snapshot), "M5 parent + 7 children + quality")) {
        return;
    }
    long originalId = snapshot.observation.id;
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observations", 1, "one parent");
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_timeframes", 7, "seven children");
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_capture_metrics WHERE quote_tick_time_msc IS NULL AND capture_market_time IS NULL AND analysis_elapsed_ms=0", 1, "NULL and zero are distinct");
    expectGuard(fromHandle, true, "M5 snapshot database accepted");
    for (int i = 0; i < 2; i++) {
        initializeSnapshot(profile, run, D'2026.09.10 11:00:00', snapshot);
        if (i == 1) {
            snapshot.observation.snapshotHash = "CHANGED_HASH";
        }
        snapshot.captureMetrics.analysisElapsedMs = 999;
        snapshot.timeFrames[6].latestPointRate = 1.4000;
        expect(service.saveSnapshot(snapshot) && snapshot.observation.id == originalId,
            "first-write duplicate " + IntegerToString(i));
    }
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observations WHERE snapshot_hash='ORIGINAL_HASH'", 1, "first hash retained");
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_timeframes WHERE latest_point_rate=1.3", 7, "first children retained");
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_capture_metrics WHERE analysis_elapsed_ms=0", 1, "first quality retained");
    testInvalidSnapshots(service, profile, run);
    testRollback(fromHandle, service, profile, run);
    initializeSnapshot(profile, run, D'2026.09.10 11:15:00', snapshot);
    expect(service.saveSnapshot(snapshot), "save recovers after rollback");

    ZigZagElliotAlertRunEntity anotherRun;
    initializeRun(profile, anotherRun);
    anotherRun.runUid += "-another-writer";
    if (expect(runDao.insert(anotherRun), "another writer Run")) {
        initializeSnapshot(profile, anotherRun, D'2026.09.10 11:00:00', snapshot);
        expect(service.saveSnapshot(snapshot) && snapshot.observation.runId == run.id,
            "duplicate reports original writer Run");
        expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observations", 2,
            "another writer does not add duplicate");
    }

    executeSql(fromHandle, "DELETE FROM zigzag_elliot_observation_capture_metrics WHERE observation_id="
        + IntegerToString(originalId));
    initializeSnapshot(profile, run, D'2026.09.10 11:00:00', snapshot);
    expect(service.saveSnapshot(snapshot), "duplicate without old metrics accepted");
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_capture_metrics WHERE observation_id="
        + IntegerToString(originalId), 0, "missing old metrics are not backfilled");

    initializeSnapshot(profile, run, D'2026.09.10 11:20:00', snapshot);
    ZeroMemory(snapshot.captureMetrics);
    expect(service.saveSnapshot(snapshot), "all unknown capture values accepted");
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_capture_metrics WHERE quote_tick_time_msc IS NULL"
        + " AND capture_market_time IS NULL AND analysis_elapsed_ms IS NULL AND capture_elapsed_ms IS NULL"
        + " AND analysis_attempt_count IS NULL", 1, "all unknown values remain SQL NULL");
    snapshot.clear();
    expect(!snapshot.hasCaptureMetrics && ArraySize(snapshot.timeFrames) == 0, "Snapshot clear resets quality");
}

/**
 * 別のメモリDBで旧H1の引数・足数・品質テーブル不要を確認する。
 */
void testH1Database(const int fromHandle) {
    ZigZagElliotObservationProfile profile;
    ZigZagElliotAlertRunDao runDao(fromHandle);
    ZigZagElliotObservationDao observationDao(fromHandle);
    ZigZagElliotObservationTimeFrameDao timeFrameDao(fromHandle);
    ZigZagElliotObservationPersistenceService service(fromHandle, &observationDao, &timeFrameDao);
    if (!expect(runDao.createTable(), "H1 Run table")) {
        return;
    }
    ZigZagElliotAlertRunEntity run;
    initializeRun(profile, run);
    if (!expect(runDao.insert(run), "H1 Run")) {
        return;
    }
    expectGuard(fromHandle, false, "H1 Run-only rejected by M5 guard");
    expectLong(fromHandle, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*'", 1,
        "guard did not create observation tables");
    if (!expect(service.createTables(), "H1 observation tables")) {
        return;
    }
    ZigZagElliotObservationSnapshot snapshot;
    initializeSnapshot(profile, run, D'2026.09.10 11:00:00', snapshot);
    expect(service.saveSnapshot(snapshot.observation, snapshot.timeFrames), "H1 legacy two-argument save");
    expectLong(fromHandle, "SELECT COUNT(*) FROM zigzag_elliot_observation_timeframes", 5, "H1 five children");
    expect(!DatabaseTableExists(fromHandle, "zigzag_elliot_observation_capture_metrics"), "H1 has no quality table");
}

/**
 * PRAGMAなどの先頭文字列を期待値と比較する。
 */
bool expectText(const int fromHandle, const string fromSql, const string fromExpected,
    const string fromName) {
    int requestHandle = DatabasePrepare(fromHandle, fromSql);
    if (requestHandle == INVALID_HANDLE) {
        return expect(false, fromName + " prepare");
    }
    string actual = "";
    bool isRead = DatabaseRead(requestHandle) && DatabaseColumnText(requestHandle, 0, actual);
    DatabaseFinalize(requestHandle);
    return expect(isRead && actual == fromExpected, fromName);
}

/**
 * テストが作った小さなローカルDBのバイト列をSHA-256で比較する。
 */
string localFileHash(const string fromFileName) {
    int fileHandle = FileOpen(fromFileName, FILE_READ | FILE_BIN);
    if (fileHandle == INVALID_HANDLE) {
        expect(false, "fixture file hash open");
        return "";
    }
    ulong size = FileSize(fileHandle);
    if (size == 0 || size > 1048576) {
        FileClose(fileHandle);
        expect(false, "fixture file hash size");
        return "";
    }
    uchar data[];
    bool isRead = ArrayResize(data, (int)size) == (int)size
        && FileReadArray(fileHandle, data, 0, (int)size) == size;
    FileClose(fileHandle);
    if (!expect(isRead, "fixture bytes read")) {
        return "";
    }
    uchar key[];
    uchar digest[];
    if (!expect(CryptEncode(CRYPT_HASH_SHA256, data, key, digest) == 32, "fixture SHA-256")) {
        return "";
    }
    string result = "";
    for (int i = 0; i < ArraySize(digest); i++) {
        result += StringFormat("%02x", (int)digest[i]);
    }
    return result;
}

/**
 * 保存先を入力に取らず、その実行で新規作成した専用DBだけを後片付けする。
 */
void removeFixture(const string fromFileName, const bool fromCreated) {
    if (!fromCreated || StringFind(fromFileName, "mstng-m5-storage-smoke-") != 0
            || StringFind(fromFileName, "\\") >= 0 || StringFind(fromFileName, "/") >= 0) {
        return;
    }
    string suffixes[] = {"", "-wal", "-shm", "-journal"};
    for (int i = 0; i < ArraySize(suffixes); i++) {
        string fileName = fromFileName + suffixes[i];
        if (FileIsExist(fileName)) {
            expect(FileDelete(fileName), "temporary fixture removed " + fileName);
        }
    }
}

/**
 * 作成先DBと副ファイルが存在しないことを確認する。
 */
bool isUnusedFixtureName(const string fromFileName) {
    return !FileIsExist(fromFileName) && !FileIsExist(fromFileName + "-wal")
        && !FileIsExist(fromFileName + "-shm") && !FileIsExist(fromFileName + "-journal");
}

/**
 * Commonを使わない専用DBでWAL、再接続、Run再利用、原子的保存を確認する。
 */
void testFileContext(const string fromFileName) {
    if (!expect(isUnusedFixtureName(fromFileName), "unused Context fixture path")) {
        return;
    }
    ZigZagElliotM5ObservationDatabaseContext context(fromFileName, false);
    bool isOpened = context.open();
    bool isCreated = FileIsExist(fromFileName);
    if (expect(isOpened && context.isReady() && !context.isDatabaseRejected(), "Context fresh open")) {
        expectText(context.getHandle(), "PRAGMA journal_mode", "wal", "Context uses WAL");
        expectLong(context.getHandle(), "PRAGMA foreign_keys", 1, "Context foreign keys enabled");
        expectLong(context.getHandle(), "PRAGMA busy_timeout", 5000, "Context timeout restored");
        expectGuard(context.getHandle(), true, "Context complete schema accepted");
        ZigZagElliotObservationProfile profile(PERIOD_M5);
        ZigZagElliotAlertRunEntity run;
        initializeRun(profile, run);
        if (expect(context.saveRun(run), "Context save Run")) {
            ZigZagElliotObservationSnapshot snapshot;
            initializeSnapshot(profile, run, D'2026.09.10 11:00:00', snapshot);
            if (expect(context.getPersistenceService().saveSnapshot(snapshot), "Context atomic snapshot")) {
                testRollback(context.getHandle(), context.getPersistenceService(), profile, run);
            }
            long originalRunId = run.id;
            context.close();
            expect(!context.isReady() && context.getHandle() == INVALID_HANDLE, "Context close releases handle");
            if (expect(context.open(), "Context reopens own saved DB")) {
                run.id = 0;
                expect(context.saveRun(run) && run.id == originalRunId, "Context reuses Run UID");
                expectLong(context.getHandle(), "SELECT COUNT(*) FROM zigzag_elliot_alert_runs", 1,
                    "reconnect did not duplicate Run");
                run.sourceServer = "different-server";
                expect(!context.saveRun(run), "Context rejects reused UID with changed source");
                run.sourceServer = "memory-smoke-server";
                run.strategy = "H1_OBSERVATION_ALL";
                expect(!context.saveRun(run), "Context rejects H1 Run before insert");
                expectLong(context.getHandle(), "SELECT COUNT(*) FROM zigzag_elliot_alert_runs", 1,
                    "rejected Run did not write");
                expectLong(context.getHandle(), "SELECT COUNT(*) FROM zigzag_elliot_observations", 1,
                    "Context snapshot survives reopen");
                expectLong(context.getHandle(), "SELECT COUNT(*) FROM zigzag_elliot_observation_timeframes", 7,
                    "Context children survive reopen");
                expectLong(context.getHandle(), "SELECT COUNT(*) FROM zigzag_elliot_observation_capture_metrics", 1,
                    "Context metrics survive reopen");
            }
        }
    }
    context.close();
    removeFixture(fromFileName, isCreated);
}

/**
 * H1 RunだけのDBと不明DBの拒否時に、DB本体とjournal modeが変わらないか確認する。
 */
void testFileRejection(const string fromFileName, const bool fromH1RunOnly) {
    if (!expect(isUnusedFixtureName(fromFileName), "unused rejection fixture path")) {
        return;
    }
    SqliteDatabase fixture(fromFileName, false);
    if (!expect(fixture.open(), "rejection fixture open")) {
        return;
    }
    bool isCreated = true;
    if (fromH1RunOnly) {
        ZigZagElliotAlertRunDao runDao(fixture.getHandle());
        ZigZagElliotObservationProfile h1Profile;
        ZigZagElliotAlertRunEntity run;
        initializeRun(h1Profile, run);
        expect(runDao.createTable() && runDao.insert(run), "H1 Run-only fixture");
    } else {
        executeSql(fixture.getHandle(), "CREATE TABLE unrelated_data (value TEXT)");
        executeSql(fixture.getHandle(), "INSERT INTO unrelated_data VALUES ('keep unchanged')");
    }
    // MT5の新規DBはWALで開かれるため、拒否試験のfixtureだけ明示的にDELETEへ固定する。
    expectText(fixture.getHandle(), "PRAGMA journal_mode=DELETE", "delete", "fixture starts outside WAL");
    fixture.close();
    string beforeHash = localFileHash(fromFileName);
    ZigZagElliotM5ObservationDatabaseContext context(fromFileName, false);
    expect(!context.open() && context.isDatabaseRejected() && !context.isReady(), "Context rejects foreign DB");
    context.close();
    string afterHash = localFileHash(fromFileName);
    expect(beforeHash != "" && beforeHash == afterHash, "rejected DB bytes unchanged");
    expect(!FileIsExist(fromFileName + "-wal") && !FileIsExist(fromFileName + "-shm"),
        "rejection did not enable WAL");
    if (expect(fixture.openReadOnly(), "rejected fixture read-only recheck")) {
        expectText(fixture.getHandle(), "PRAGMA journal_mode", "delete", "rejected journal mode unchanged");
        expectLong(fixture.getHandle(), "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*'",
            1, "rejection did not create tables");
        fixture.close();
    }
    removeFixture(fromFileName, isCreated);
}

/**
 * メモリDBを検証し、有効化時だけ今回作成する専用ローカルDBも検証する。
 * 注文・接続・端末設定の変更は行わない。
 */
void OnStart() {
    testLogger.setLevel(LOG_INFO);
    testLogger.info(__FUNCTION__, "M5_STORAGE_SMOKE_START fileContextTestsEnabled="
        + IntegerToString((int)fileContextTestsEnabled));
    testProfiles();
    for (int i = 0; i < 2; i++) {
        int databaseHandle = DatabaseOpen(":memory:",
            DATABASE_OPEN_READWRITE | DATABASE_OPEN_CREATE | DATABASE_OPEN_MEMORY);
        if (!expect(databaseHandle != INVALID_HANDLE, "memory database open")) {
            continue;
        }
        if (i == 0) {
            testM5Database(databaseHandle);
        } else {
            testH1Database(databaseHandle);
        }
        DatabaseClose(databaseHandle);
    }
    if (fileContextTestsEnabled) {
        string prefix = "mstng-m5-storage-smoke-" + IntegerToString((long)TimeLocal())
            + "-" + IntegerToString((long)GetMicrosecondCount());
        testFileContext(prefix + "-context.sqlite");
        testFileRejection(prefix + "-h1.sqlite", true);
        testFileRejection(prefix + "-unknown.sqlite", false);
    }
    expect(failedCount == 0, "M5 observation database smoke test complete");
    testLogger.info(__FUNCTION__, "M5_STORAGE_SMOKE_RESULT failed=" + IntegerToString(failedCount));
}
