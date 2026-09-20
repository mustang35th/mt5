#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "1.00"
#property strict

#include <Mstng\Database\Query\ZigZagElliotAlertHistoryReader.mqh>
#include <Mstng\Database\Service\ZigZagElliotAlertPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryConfig.mqh>
#include <Mstng\Log\Logger.mqh>

/** 失敗した検証数。 */
int failedCount = 0;
/** 実行した検証数。 */
int checkedCount = 0;
/** 検証ログ。 */
Logger testLogger;

/**
 * 期待値を記録する。
 */
bool expect(const bool fromCondition, const string fromName) {
    checkedCount++;
    if (!fromCondition) {
        failedCount++;
        testLogger.error(__FUNCTION__, "FAIL " + fromName);
        return false;
    }
    testLogger.info(__FUNCTION__, "PASS " + fromName);
    return true;
}

/**
 * 今回新規作成したfixtureだけにSQLを実行する。
 */
bool executeSql(const int fromHandle, const string fromSql) {
    ResetLastError();
    return expect(DatabaseExecute(fromHandle, fromSql),
        "fixture SQL " + fromSql + " error=" + IntegerToString(GetLastError()));
}

/**
 * PRAGMAなどの先頭文字列を照合する。
 */
bool expectText(const int fromHandle, const string fromSql, const string fromExpected) {
    int requestHandle = DatabasePrepare(fromHandle, fromSql);
    if (requestHandle == INVALID_HANDLE) {
        return expect(false, "prepare " + fromSql);
    }
    string actual = "";
    bool isRead = DatabaseRead(requestHandle) && DatabaseColumnText(requestHandle, 0, actual);
    DatabaseFinalize(requestHandle);
    return expect(isRead && actual == fromExpected, fromSql + " = " + fromExpected);
}

/**
 * 保存先を入力に取らず、今回の未使用ローカル名だけを利用する。
 */
bool isUnusedFixtureName(const string fromFileName) {
    return !FileIsExist(fromFileName) && !FileIsExist(fromFileName + "-wal")
        && !FileIsExist(fromFileName + "-shm") && !FileIsExist(fromFileName + "-journal");
}

/**
 * 今回作った小さなローカルDBのバイト列をSHA-256で比較する。
 */
string localFileHash(const string fromFileName) {
    int fileHandle = FileOpen(fromFileName, FILE_READ | FILE_BIN);
    if (!expect(fileHandle != INVALID_HANDLE, "fixture hash open")) {
        return "";
    }
    ulong size = FileSize(fileHandle);
    if (size == 0 || size > 8388608) {
        FileClose(fileHandle);
        expect(false, "fixture hash size");
        return "";
    }
    uchar data[];
    bool isRead = ArrayResize(data, (int)size) == (int)size
        && FileReadArray(fileHandle, data, 0, (int)size) == size;
    FileClose(fileHandle);
    if (!expect(isRead, "fixture hash read")) {
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
 * この実行で新規作成した専用DBと副ファイルだけを削除する。
 */
void removeFixture(const string fromFileName, const bool fromCreated) {
    if (!fromCreated || StringFind(fromFileName, "mstng-alert-history-smoke-") != 0
            || StringFind(fromFileName, "\\") >= 0 || StringFind(fromFileName, "/") >= 0) {
        return;
    }
    string suffixes[] = {"", "-wal", "-shm", "-journal"};
    for (int i = 0; i < ArraySize(suffixes); i++) {
        string fileName = fromFileName + suffixes[i];
        if (FileIsExist(fileName)) {
            expect(FileDelete(fileName), "owned fixture removed " + fileName);
        }
    }
}

/**
 * 保存サービスを使うための架空Runを作成する。
 */
long saveRun(ZigZagElliotAlertPersistenceService &fromService, const int fromNumber) {
    ZigZagElliotAlertRunEntity run;
    ZeroMemory(run);
    run.runUid = "history-fixture-run-" + IntegerToString(fromNumber);
    run.schemaVersion = 7;
    run.source = "ZigZagElliot";
    run.sourceMode = "TESTER";
    run.sourceServer = "qa-server";
    if (fromNumber == 1) {
        run.sourceMode = "LIVE";
    }
    if (fromNumber == 3) {
        run.sourceServer = "qa-other-server";
    }
    run.strategy = "MTF_3in3";
    run.analysisVersion = "history-fixture";
    run.analysisInputText = "synthetic-only";
    run.analysisInputHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    run.startedAt = 100;
    run.createdAt = 100;
    run.status = "COMPLETED";
    if (!expect(fromService.saveRun(run), "save synthetic Run")) {
        return 0;
    }
    return run.id;
}

/**
 * 7時間足と各最新Waveの4ポイントを作る。元と補正の価格・ラベルを明確に変える。
 */
void initializeAnalysis(const bool fromCorrected, const bool fromApplied, const bool fromBuy,
    const int fromCorrectionTimeFrame, ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[],
    ZigZagElliotAlertPointEntity &fromPoints[]) {
    ArrayResize(fromTimeFrames, 7);
    ArrayResize(fromPoints, 28);
    int timeFrames[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
    string labels[] = {"MN1", "W1", "D1", "H4", "H1", "M15", "M5"};
    string elliotLabel = "2";
    string prefix = "ORIGINAL:";
    int pointTimeOffset = 0;
    double pointRate = 149.0;
    if (!fromBuy) {
        pointRate = 151.0;
    }
    if (fromCorrected) {
        elliotLabel = "3";
        prefix = "CORRECTED:";
        pointTimeOffset = 100;
        pointRate = 149.5;
        if (!fromBuy) {
            pointRate = 150.5;
        }
    }
    for (int i = 0; i < 7; i++) {
        ZeroMemory(fromTimeFrames[i]);
        bool isBuy = fromBuy;
        if (!fromCorrected && fromApplied && timeFrames[i] == fromCorrectionTimeFrame) {
            isBuy = !fromBuy;
        }
        fromTimeFrames[i].timeFrame = timeFrames[i];
        fromTimeFrames[i].timeFrameText = labels[i];
        fromTimeFrames[i].timeFrameOrder = i;
        fromTimeFrames[i].isBuy = (int)isBuy;
        fromTimeFrames[i].buySellLabel = "SELL";
        if (isBuy) {
            fromTimeFrames[i].buySellLabel = "BUY";
        }
        fromTimeFrames[i].isOscillatorBuy = (int)isBuy;
        fromTimeFrames[i].isWaveUptrend = (int)isBuy;
        fromTimeFrames[i].waveCount = 1;
        fromTimeFrames[i].pointCount = 4;
        fromTimeFrames[i].latestElliotLabel = elliotLabel;
        fromTimeFrames[i].rawCsvText = prefix + labels[i];
        fromTimeFrames[i].ema200Close1 = 150.1;
        fromTimeFrames[i].ema200Shift1 = 150.0;
        fromTimeFrames[i].isEma200Buy = 1;
        fromTimeFrames[i].createdAt = 2200;
        if (timeFrames[i] == PERIOD_M5) {
            fromTimeFrames[i].isCurrentTimeFrame = 1;
        }
        for (int j = 0; j < 4; j++) {
            int pointIndex = i * 4 + j;
            ZeroMemory(fromPoints[pointIndex]);
            fromPoints[pointIndex].timeFrame = timeFrames[i];
            fromPoints[pointIndex].pointOrder = j;
            fromPoints[pointIndex].rate = pointRate + j * 0.01;
            fromPoints[pointIndex].barTime = 500 + j + pointTimeOffset;
            fromPoints[pointIndex].elliotLabel = elliotLabel;
            fromPoints[pointIndex].createdAt = 2200;
            if (j == 3) {
                fromPoints[pointIndex].isLatest = 1;
            }
            if (timeFrames[i] == PERIOD_M5 && j == 2) {
                fromPoints[pointIndex].isSignalReference = 1;
                fromPoints[pointIndex].rate = pointRate + 0.05;
                if (!fromBuy) {
                    fromPoints[pointIndex].rate = pointRate - 0.05;
                }
            }
        }
    }
}

/**
 * 保存済みと同じDDL・INSERT・トランザクションで、架空のアラート全体を作る。
 * UNRECORDEDは旧3引数API、その他は補正情報を含む6引数APIを利用する。
 */
long saveAlert(ZigZagElliotAlertPersistenceService &fromService, const long fromRunId,
    const int fromSerial, const datetime fromBarTime, const string fromStatus,
    const bool fromBuy = true, const int fromCorrectionTimeFrame = PERIOD_H1,
    const bool fromEntry = true, const string fromSymbol = "TESTJPY") {
    bool isApplied = fromStatus == "APPLIED";
    ZigZagElliotAlertEntity alert;
    ZeroMemory(alert);
    alert.runId = fromRunId;
    alert.eventUid = "history-event-" + IntegerToString(fromSerial);
    alert.marketSignalKey = "history-market-" + IntegerToString(fromSerial);
    alert.snapshotHash = "aaaaaaaaaaaaaaaa";
    alert.symbolName = fromSymbol;
    alert.timeFrame = PERIOD_M5;
    alert.timeFrameText = "M5";
    alert.strategy = "MTF_3in3";
    alert.magicNumber = "0";
    alert.side = "BUY";
    alert.currentBarTime = fromBarTime;
    alert.serverTime = fromBarTime;
    if (fromSerial == 1) {
        alert.serverTime++;
    }
    alert.jstTime = fromBarTime;
    alert.signalReferencePointTime = 502 + (fromSerial - 1) * 10;
    alert.alertText = "original " + IntegerToString(fromSerial);
    alert.isJudge = 1;
    alert.signalCount = 1;
    alert.entryCount = 1;
    alert.isEntryCountMatch = 1;
    alert.isEntryEvaluated = 1;
    alert.isAlert = 1;
    alert.isEntry = (int)fromEntry;
    alert.entryResult = "ENTRY";
    if (!fromEntry) {
        alert.entryResult = "REJECT_FE";
    }
    alert.currentElliotLabel = "2";
    if (isApplied) {
        alert.currentElliotLabel = "3";
    }
    alert.isEntryWave = 1;
    alert.w1ConfirmationMode = "OFF";
    alert.w1ConfirmationState = "NOT_APPLICABLE";
    alert.w1Ema200Direction = "NONE";
    alert.h1DirectionAlignmentMode = "D1_TO_H1";
    alert.h1DirectionAlignmentState = "NOT_APPLICABLE";
    alert.h1DirectionAlignmentDirection = "NONE";
    alert.referencePrice = 150.0;
    alert.isStopLossAvailable = 1;
    alert.stopLoss = 149.0;
    alert.riskPips = 100.0;
    alert.createdAt = 2200;
    if (!fromBuy) {
        alert.side = "SELL";
        alert.stopLoss = 151.0;
    }
    ZigZagElliotAlertTimeFrameEntity timeFrames[];
    ZigZagElliotAlertPointEntity points[];
    ZigZagElliotAlertTimeFrameEntity correctedTimeFrames[];
    ZigZagElliotAlertPointEntity correctedPoints[];
    initializeAnalysis(false, isApplied, fromBuy, fromCorrectionTimeFrame, timeFrames, points);
    if (fromSerial != 11) {
        timeFrames[6].currentOpen = 150.125;
    }
    for (int i = 0; i < ArraySize(points); i++) {
        points[i].barTime += (fromSerial - 1) * 10;
    }
    if (fromStatus == "UNRECORDED") {
        if (!expect(fromService.saveSnapshot(alert, timeFrames, points), "save legacy alert")) {
            return 0;
        }
        return alert.id;
    }
    ZigZagElliotAlertCorrectionEntity correction;
    ZeroMemory(correction);
    correction.correctionStatus = fromStatus;
    correction.selectedAnalysis = "ORIGINAL";
    correction.selectedAlertText = "synthetic " + fromStatus;
    correction.selectedCurrentElliotLabel = alert.currentElliotLabel;
    correction.selectedWaveSummaryText = "synthetic all seven";
    correction.referencePrice = alert.referencePrice;
    correction.isSelectedStopLossAvailable = 1;
    correction.selectedStopLoss = alert.stopLoss;
    correction.selectedRiskPips = alert.riskPips;
    correction.originalLc0 = points[26].rate;
    correction.originalLc5 = alert.stopLoss;
    correction.originalLc10 = alert.stopLoss;
    correction.originalLc15 = alert.stopLoss;
    correction.originalLossCutDiffPips = 95.0;
    correction.originalLossCutDiffJpy = 100.0;
    correction.originalAnalysisText = "ORIGINAL full seven";
    correction.comparisonHash = "bbbbbbbbbbbbbbbb";
    correction.createdAt = 2200;
    correction.createdAtText = "1970.01.01 00:36:40";
    if (isApplied) {
        initializeAnalysis(true, true, fromBuy, fromCorrectionTimeFrame, correctedTimeFrames, correctedPoints);
        for (int i = 0; i < ArraySize(correctedPoints); i++) {
            correctedPoints[i].barTime += (fromSerial - 1) * 10;
        }
        correction.correctionTimeFrame = fromCorrectionTimeFrame;
        correction.originalDirection = "SELL";
        if (!fromBuy) {
            correction.originalDirection = "BUY";
        }
        correction.correctedDirection = alert.side;
        correction.selectedAnalysis = "CORRECTED";
        correction.selectedStopLoss = 149.5;
        if (!fromBuy) {
            correction.selectedStopLoss = 150.5;
        }
        correction.selectedRiskPips = 50.0;
        correction.correctedLc0 = correctedPoints[26].rate;
        correction.correctedLc5 = correction.selectedStopLoss;
        correction.correctedLc10 = correction.selectedStopLoss;
        correction.correctedLc15 = correction.selectedStopLoss;
        correction.correctedLossCutDiffPips = 45.0;
        correction.correctedLossCutDiffJpy = 50.0;
        correction.correctedReferencePointTime = 602 + (fromSerial - 1) * 10;
        correction.correctedAnalysisText = "CORRECTED full seven";
        correction.correctedElliotCsvText = "CORRECTED csv";
    }
    if (!expect(fromService.saveSnapshot(alert, timeFrames, points, correction,
            correctedTimeFrames, correctedPoints), "save " + fromStatus + " alert")) {
        return 0;
    }
    return alert.id;
}

/**
 * 検索結果のRunと安定したID順を照合する。
 */
void expectSelection(ZigZagElliotAlertHistoryReader &fromReader, const string fromSymbol,
    const long fromRunId, const datetime fromStart, const datetime fromEnd, const bool fromEntryOnly,
    const long fromExpectedRun, const string fromExpectedIds, const string fromName) {
    long resolvedRunId = -1;
    long alertIds[];
    string error = "previous error";
    bool isSelected = fromReader.selectAlerts(fromSymbol, fromRunId, fromStart, fromEnd,
        fromEntryOnly, resolvedRunId, alertIds, error);
    string ids = "";
    for (int i = 0; i < ArraySize(alertIds); i++) {
        if (i > 0) {
            ids += ",";
        }
        ids += IntegerToString(alertIds[i]);
    }
    expect(isSelected && error == "" && resolvedRunId == fromExpectedRun && ids == fromExpectedIds,
        fromName + " actualRun=" + IntegerToString(resolvedRunId) + " ids=" + ids + " error=" + error);
    ZigZagElliotAlertHistoryMarker markers[];
    isSelected = fromReader.selectMarkers(fromSymbol, fromRunId, fromStart, fromEnd,
        fromEntryOnly, resolvedRunId, alertIds, markers, error);
    ids = "";
    for (int i = 0; i < ArraySize(alertIds); i++) {
        if (i > 0) {
            ids += ",";
        }
        ids += IntegerToString(alertIds[i]);
        expect(i < ArraySize(markers) && markers[i].alertId == alertIds[i], "marker identity order");
    }
    expect(isSelected && error == "" && resolvedRunId == fromExpectedRun && ids == fromExpectedIds
        && ArraySize(markers) == ArraySize(alertIds), "bulk markers: " + fromName);
}

/**
 * 一覧の採用文字・保存価格・旧記録の区別を実DBで照合する。
 */
void testMarkers(ZigZagElliotAlertHistoryReader &fromReader, const bool fromLegacy) {
    long runId = 0;
    long ids[];
    ZigZagElliotAlertHistoryMarker markers[];
    string error = "";
    bool success = fromReader.selectMarkers("TESTJPY", 2, 1000, 1500, false, runId, ids, markers, error);
    if (!expect(success && ArraySize(markers) == 6, "six bulk marker rows " + error)) {
        return;
    }
    expect(markers[0].available && markers[0].price == 150.125
        && markers[0].barTime == 1000 && markers[0].serverTime == 1001 && markers[0].jstTime == 1000,
        "marker uses saved original M5 open and separate dates");
    expect(markers[2].available && markers[2].text == "original 4 [元分析]",
        "missing correction row is explicitly original");
    expect(!markers[5].available && markers[5].alertId == 11, "invalid open keeps selection but hides label");
    if (fromLegacy) {
        expect(markers[0].text == "original 1 [元分析]", "legacy table missing uses original label");
    } else {
        expect(markers[0].text == "synthetic APPLIED" && markers[0].correctionText == "H1 SELL→BUY",
            "adopted label and H1 direction come from metadata");
        expect(markers[1].text == "synthetic NONE" && markers[1].isEntry == 0,
            "NONE and non-entry label retained");
        expect(markers[3].side == "SELL" && markers[3].correctionText == "H4 BUY→SELL",
            "SELL H4 metadata retained");
        expect(markers[4].available, "saved label is independent of detailed corrected point completeness");
    }
    string expectedWave = "3";
    string expectedStatus = "APPLIED";
    if (fromLegacy) {
        expectedWave = "2";
        expectedStatus = "UNRECORDED";
    }
    expect(markers[0].correctionStatus == expectedStatus, "tooltip identifies adopted or legacy analysis");
    for (int i = 0; i < 7; i++) {
        expect(markers[0].waves[i].recorded && markers[0].waves[i].wave == expectedWave
            && markers[0].waves[i].state == "未" && markers[0].waves[i].subWave == "",
            "all seven waves come from one adopted analysis " + IntegerToString(i));
        string expectedEma = "B";
        if (fromLegacy || i == 0) {
            expectedEma = "";
        }
        expect(markers[0].waves[i].emaDirection == expectedEma,
            "MN1 and absent legacy EMA flags stay unknown " + IntegerToString(i));
        expect(markers[2].waves[i].wave == "2", "legacy row reads original waves " + IntegerToString(i));
    }
    if (!fromLegacy) {
        expect(markers[0].waves[4].direction == "B" && markers[3].waves[3].direction == "S",
            "corrected H1 BUY and H4 SELL directions adopted");
        expect(markers[1].correctionStatus == "NONE" && markers[1].waves[4].wave == "2",
            "NONE uses original summary");
        expect(!markers[4].waves[0].recorded && markers[4].waves[0].direction == ""
            && markers[4].waves[0].wave == "", "missing corrected frame never falls back to original");
        expect(markers[4].waves[3].direction == "" && markers[4].waves[3].emaDirection == "",
            "invalid direction and contradictory EMA flags stay unknown");
        expect(markers[4].waves[1].emaDirection == "" && markers[4].waves[1].state == "",
            "neutral EMA and invalid confirmation stay unknown");
        expect(markers[4].waves[2].emaDirection == "S", "EMA SELL is independent of analysis BUY");
        expect(markers[4].waves[4].subWave == "1" && markers[4].waves[4].state == "確",
            "saved subwave and confirmed state read");
    }
    expect(!fromReader.selectMarkers("TESTJPY", -1, 0, 0, false, runId, ids, markers, error)
        && ArraySize(markers) == 0 && ArraySize(ids) == 0, "invalid request clears bulk marker cache");
}

/**
 * 通常版のモード・接続先・既知時刻をRun選択前に絞り、未来の判定を除く。
 */
void testDisplayFilters(ZigZagElliotAlertHistoryReader &fromReader) {
    long runId = 0;
    long ids[];
    ZigZagElliotAlertHistoryMarker markers[];
    string error = "";
    bool success = fromReader.selectMarkers("TESTJPY", 0, 0, 0, false, runId, ids, markers, error,
        "LIVE", "qa-server", 2000);
    expect(success && runId == 1 && ArraySize(ids) == 1 && ids[0] == 6,
        "LIVE selects matching older Run instead of latest TESTER Run");
    success = fromReader.selectMarkers("TESTJPY", 0, 0, 0, false, runId, ids, markers, error,
        "TESTER", "qa-server", 2000);
    expect(success && runId == 2 && ArraySize(ids) == 6,
        "TESTER excludes newer other-server Run before MAX selection");
    success = fromReader.selectMarkers("TESTJPY", 0, 0, 0, false, runId, ids, markers, error,
        "TESTER", "qa-other-server", 2000);
    expect(success && runId == 3 && ArraySize(ids) == 1 && ids[0] == 7, "exact server filter");
    success = fromReader.selectMarkers("TESTJPY", 2, 0, 0, false, runId, ids, markers, error,
        "LIVE", "qa-server", 2000);
    expect(success && ArraySize(ids) == 0, "explicit Run cannot bypass source mode");
    success = fromReader.selectMarkers("TESTJPY", 0, 0, 0, false, runId, ids, markers, error,
        "TESTER", "qa-server", 1000);
    expect(success && runId == 0 && ArraySize(ids) == 0,
        "current bar present but future judgment excluded");
    success = fromReader.selectMarkers("TESTJPY", 0, 0, 0, false, runId, ids, markers, error,
        "TESTER", "qa-server", 1001);
    expect(success && runId == 2 && ArraySize(ids) == 1 && ids[0] == 1,
        "judgment becomes visible exactly at saved server time");
    success = fromReader.selectMarkers("TESTJPY", 0, 0, 0, false, runId, ids, markers, error,
        "TESTER", "qa-server", 1100);
    expect(success && ArraySize(ids) == 3 && ids[0] == 1 && ids[1] == 3 && ids[2] == 4,
        "known-time cutoff preserves order and excludes later bars");
    expect(!fromReader.selectMarkers("TESTJPY", 0, 0, 0, false, runId, ids, markers, error,
        "TESTER", "qa-server", -1) && ArraySize(markers) == 0, "negative known time rejected");
}

/**
 * 補正状態・元補正テーブル固有ID・欠損時の結果初期化を実Readerで確認する。
 */
void testSnapshots(ZigZagElliotAlertHistoryReader &fromReader) {
    ZigZagElliotAlertHistorySnapshot snapshot;
    string error = "";
    if (expect(fromReader.loadSnapshot(1, snapshot, error), "load BUY H1 correction " + error)) {
        expect(snapshot.correctionStatus == "APPLIED" && snapshot.originalAvailable,
            "H1 correction available");
        expect(ArraySize(snapshot.originalTimeFrames) == 7 && ArraySize(snapshot.correctedTimeFrames) == 7
            && ArraySize(snapshot.originalPoints) == 28 && ArraySize(snapshot.correctedPoints) == 28,
            "complete original and corrected seven-frame latest waves");
        if (ArraySize(snapshot.correctedTimeFrames) == 7 && ArraySize(snapshot.originalTimeFrames) == 7
                && ArraySize(snapshot.correctedPoints) == 28 && ArraySize(snapshot.originalPoints) == 28) {
            expect(snapshot.originalTimeFrames[0].id == snapshot.correctedTimeFrames[0].id
                && snapshot.originalPoints[0].id == snapshot.correctedPoints[0].id,
                "fixture deliberately overlaps table-local IDs");
            expect(snapshot.originalTimeFrames[4].buySellLabel == "SELL"
                && snapshot.correctedTimeFrames[4].buySellLabel == "BUY",
                "H1 directions come from their own tables");
            expect(snapshot.originalTimeFrames[6].latestElliotLabel == "2"
                && snapshot.correctedTimeFrames[6].latestElliotLabel == "3"
                && snapshot.originalPoints[26].barTime == 502 && snapshot.correctedPoints[26].barTime == 602
                && snapshot.originalPoints[26].rate != snapshot.correctedPoints[26].rate,
                "points do not join across original and corrected IDs");
            expect(snapshot.originalTimeFrames[0].isEma200Buy == 1
                && snapshot.originalTimeFrames[0].isEma200Sell == 0, "saved EMA flags read");
        }
        expect(snapshot.alert.stopLoss == 149.0 && snapshot.correction.selectedStopLoss == 149.5,
            "original and selected stop losses stay distinct");
    }
    expect(fromReader.loadSnapshot(2, snapshot, error) && snapshot.correctionStatus == "APPLIED"
        && snapshot.correction.correctionTimeFrame == PERIOD_H4 && snapshot.alert.side == "SELL"
        && snapshot.correction.selectedStopLoss == 150.5, "SELL H4 correction available");
    expect(fromReader.loadSnapshot(3, snapshot, error) && snapshot.correctionStatus == "NONE"
        && snapshot.originalAvailable && ArraySize(snapshot.correctedPoints) == 0
        && ArraySize(snapshot.correctedTimeFrames) == 0, "NONE clears prior corrected arrays");
    expect(fromReader.loadSnapshot(4, snapshot, error) && snapshot.correctionStatus == "UNRECORDED"
        && snapshot.originalAvailable && ArraySize(snapshot.correctedPoints) == 0,
        "missing metadata is UNRECORDED");
    expect(fromReader.loadSnapshot(5, snapshot, error) && snapshot.correctionStatus == "INCOMPLETE"
        && snapshot.originalAvailable && snapshot.correctionReason != ""
        && ArraySize(snapshot.correctedTimeFrames) == 0 && ArraySize(snapshot.correctedPoints) == 0,
        "missing corrected point rejects full corrected payload");
    expect(fromReader.loadSnapshot(11, snapshot, error) && !snapshot.originalAvailable
        && snapshot.originalReason != "", "incomplete original is explicit");
    expect(fromReader.loadSnapshot(12, snapshot, error) && snapshot.correctionStatus == "INCOMPLETE"
        && snapshot.originalAvailable && ArraySize(snapshot.correctedPoints) == 0,
        "NONE rejects selected label inconsistent with original latest M5");
    expect(fromReader.loadSnapshot(13, snapshot, error) && snapshot.correctionStatus == "INCOMPLETE"
        && snapshot.originalAvailable && ArraySize(snapshot.correctedPoints) == 0,
        "malformed correction number is not converted to zero");
    expect(!fromReader.loadSnapshot(14, snapshot, error) && error != ""
        && !snapshot.originalAvailable, "missing parent Run fails without stale payload");
    expect(!fromReader.loadSnapshot(15, snapshot, error) && error != ""
        && !snapshot.originalAvailable, "malformed parent timestamp fails without coercion");
    expect(!fromReader.loadSnapshot(99999, snapshot, error) && error != ""
        && !snapshot.originalAvailable && ArraySize(snapshot.correctedPoints) == 0,
        "missing alert fails without stale payload");
    expect(fromReader.loadSnapshot(1, snapshot, error) && error == ""
        && snapshot.correctionStatus == "APPLIED", "reader recovers after missing alert");
}

/**
 * current schemaと旧EMA列なしschemaを、書込側を閉じた後で読み取る。
 */
void testFile(const string fromFileName, const bool fromLegacy) {
    if (!expect(isUnusedFixtureName(fromFileName), "unused fixture path")) {
        return;
    }
    SqliteDatabase database(fromFileName, false);
    if (!expect(database.open(), "fixture database open")) {
        return;
    }
    int databaseHandle = database.getHandle();
    ZigZagElliotAlertDao alertDao(databaseHandle);
    ZigZagElliotAlertPointDao pointDao(databaseHandle);
    ZigZagElliotAlertRunDao runDao(databaseHandle);
    ZigZagElliotAlertTimeFrameDao timeFrameDao(databaseHandle);
    ZigZagElliotAlertCorrectionDao correctionDao(databaseHandle);
    ZigZagElliotAlertTimeFrameDao correctedTimeFrameDao(databaseHandle, true);
    ZigZagElliotAlertPointDao correctedPointDao(databaseHandle, true);
    ZigZagElliotAlertPersistenceService service(databaseHandle, GetPointer(alertDao), GetPointer(pointDao),
        GetPointer(runDao), GetPointer(timeFrameDao), GetPointer(correctionDao),
        GetPointer(correctedTimeFrameDao), GetPointer(correctedPointDao));
    if (!expect(service.createTables(), "actual seven-table DDL")) {
        database.close();
        removeFixture(fromFileName, true);
        return;
    }
    long olderRun = saveRun(service, 1);
    long latestRun = saveRun(service, 2);
    long excludedRun = saveRun(service, 3);
    expect(saveAlert(service, latestRun, 1, 1000, "APPLIED") == 1, "H1 fixture id");
    expect(saveAlert(service, latestRun, 2, 1200, "APPLIED", false, PERIOD_H4) == 2, "H4 fixture id");
    expect(saveAlert(service, latestRun, 3, 1100, "NONE", true, PERIOD_H1, false) == 3, "non-entry id");
    expect(saveAlert(service, latestRun, 4, 1100, "UNRECORDED") == 4, "legacy row id");
    expect(saveAlert(service, latestRun, 5, 1300, "APPLIED") == 5, "incomplete correction id");
    expect(saveAlert(service, olderRun, 6, 1050, "NONE") == 6, "older Run id");
    expect(saveAlert(service, excludedRun, 7, 1500, "NONE") == 7, "exclusive endpoint id");
    expect(saveAlert(service, excludedRun, 8, 1150, "NONE") == 8, "non-alert id");
    expect(saveAlert(service, excludedRun, 9, 1150, "NONE") == 9, "non-M5 id");
    expect(saveAlert(service, latestRun, 10, 1150, "NONE", true, PERIOD_H1, true,
        "TEST' OR 1=1 --") == 10, "quoted symbol id");
    expect(saveAlert(service, latestRun, 11, 1350, "UNRECORDED") == 11, "incomplete original id");
    expect(saveAlert(service, latestRun, 12, 1600, "NONE", true, PERIOD_H1, true, "BADNONE") == 12,
        "inconsistent selected label id");
    expect(saveAlert(service, latestRun, 13, 1600, "NONE", true, PERIOD_H1, true, "BADTYPE") == 13,
        "malformed correction id");
    expect(saveAlert(service, latestRun, 14, 1600, "UNRECORDED", true, PERIOD_H1, true, "BADRUN") == 14,
        "missing Run id");
    expect(saveAlert(service, latestRun, 15, 1600, "UNRECORDED", true, PERIOD_H1, true, "BADTIME") == 15,
        "malformed timestamp id");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alerts SET is_alert=0 WHERE id=8");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alerts SET time_frame=16385,time_frame_text='H1' WHERE id=9");
    executeSql(databaseHandle, "DELETE FROM zigzag_elliot_alert_corrected_points WHERE id IN "
        "(SELECT p.id FROM zigzag_elliot_alert_corrected_points p JOIN zigzag_elliot_alert_corrected_timeframes t "
        "ON p.alert_timeframe_id=t.id WHERE t.alert_id=5 AND t.time_frame=5 AND p.point_order=3)");
    executeSql(databaseHandle, "DELETE FROM zigzag_elliot_alert_points WHERE id IN "
        "(SELECT p.id FROM zigzag_elliot_alert_points p JOIN zigzag_elliot_alert_timeframes t "
        "ON p.alert_timeframe_id=t.id WHERE t.alert_id=11 AND t.time_frame=5 AND p.point_order=3)");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alert_timeframes SET latest_elliot_label='3' "
        "WHERE alert_id=12 AND time_frame=5");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alert_points SET elliot_label='3' "
        "WHERE is_latest=1 AND alert_timeframe_id IN "
        "(SELECT id FROM zigzag_elliot_alert_timeframes WHERE alert_id=12 AND time_frame=5)");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alert_corrections SET selected_risk_pips='invalid' WHERE alert_id=13");
    executeSql(databaseHandle, "PRAGMA foreign_keys=OFF");
    executeSql(databaseHandle, "PRAGMA ignore_check_constraints=ON");
    executeSql(databaseHandle, "DELETE FROM zigzag_elliot_alert_corrected_timeframes WHERE alert_id=5 AND time_frame=49153");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alert_corrected_timeframes SET is_buy='invalid',is_ema200_sell=1 "
        "WHERE alert_id=5 AND time_frame=16388");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alert_corrected_timeframes SET is_ema200_buy=0,is_wave_confirmed='invalid' "
        "WHERE alert_id=5 AND time_frame=32769");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alert_corrected_timeframes SET is_ema200_buy=0,is_ema200_sell=1 "
        "WHERE alert_id=5 AND time_frame=16408");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alert_corrected_timeframes SET latest_sub_elliot_index=1,"
        "latest_sub_elliot_label='1',is_wave_confirmed=1 WHERE alert_id=5 AND time_frame=16385");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alerts SET run_id=99999 WHERE id=14");
    executeSql(databaseHandle, "UPDATE zigzag_elliot_alerts SET server_time='invalid' WHERE id=15");
    if (fromLegacy) {
        executeSql(databaseHandle, "DROP TABLE zigzag_elliot_alert_corrected_points");
        executeSql(databaseHandle, "DROP TABLE zigzag_elliot_alert_corrected_timeframes");
        executeSql(databaseHandle, "DROP TABLE zigzag_elliot_alert_corrections");
        executeSql(databaseHandle, "ALTER TABLE zigzag_elliot_alert_timeframes DROP COLUMN is_ema200_buy");
        executeSql(databaseHandle, "ALTER TABLE zigzag_elliot_alert_timeframes DROP COLUMN is_ema200_sell");
    }
    expectText(databaseHandle, "PRAGMA journal_mode=DELETE", "delete");
    database.close();
    string beforeHash = localFileHash(fromFileName);
    ZigZagElliotAlertHistoryReader reader;
    string error = "";
    if (expect(reader.open(fromFileName, false, error), "reader opens local fixture " + error)) {
        expectSelection(reader, "TESTJPY", 0, 1000, 1500, false, latestRun, "1,3,4,2,5,11",
            "auto Run uses same symbol/time/M5/is-alert predicates and stable order");
        expectSelection(reader, "TESTJPY", 0, 1000, 1500, true, latestRun, "1,4,2,5,11", "entry-only");
        expectSelection(reader, "TESTJPY", olderRun, 1000, 1500, false, olderRun, "6", "explicit Run isolated");
        expectSelection(reader, "TESTJPY", latestRun, 1100, 1200, false, latestRun, "3,4",
            "inclusive start and exclusive end");
        expectSelection(reader, "TESTJPY", 0, 1500, 0, true, excludedRun, "7", "unbounded end");
        expectSelection(reader, "TESTJPY", 0, 0, 1001, false, latestRun, "1", "unbounded start");
        expectSelection(reader, "TEST' OR 1=1 --", 0, 0, 0, false, latestRun, "10", "escaped exact symbol");
        expectSelection(reader, "UNKNOWN", 0, 0, 0, false, 0, "", "empty auto Run is successful");
        testMarkers(reader, fromLegacy);
        testDisplayFilters(reader);
        if (fromLegacy) {
            ZigZagElliotAlertHistorySnapshot snapshot;
            bool isLoaded = reader.loadSnapshot(3, snapshot, error);
            expect(isLoaded && snapshot.correctionStatus == "UNRECORDED" && snapshot.originalAvailable,
                "missing correction tables preserve legacy original " + error);
            if (ArraySize(snapshot.originalTimeFrames) == 7) {
                expect(snapshot.originalTimeFrames[0].isEma200Buy == 0
                    && snapshot.originalTimeFrames[0].isEma200Sell == 0,
                    "missing legacy EMA flags use documented zero fallback");
            } else {
                expect(false, "legacy has seven frames");
            }
        } else {
            testSnapshots(reader);
        }
    }
    reader.close();
    string afterHash = localFileHash(fromFileName);
    expect(beforeHash != "" && beforeHash == afterHash, "reader leaves database bytes unchanged");
    expect(!FileIsExist(fromFileName + "-wal") && !FileIsExist(fromFileName + "-shm")
        && !FileIsExist(fromFileName + "-journal"), "reader creates no side files");
    if (expect(database.openReadOnly(), "fixture read-only final check")) {
        expectText(database.getHandle(), "PRAGMA journal_mode", "delete");
        database.close();
    }
    removeFixture(fromFileName, true);
}

/**
 * サーバー日付の時刻丸めと終了日を含む区間を確認する。
 */
void testPeriods() {
    ZigZagElliotAlertHistoryConfig config;
    datetime startTime = 99;
    datetime endTime = 99;
    string error = "previous error";
    expect(config.getPeriod(startTime, endTime, error) && startTime == 0 && endTime == 0 && error == "",
        "default period is unbounded");
    config.startDate = D'2026.09.19 22:30:45';
    config.endDate = D'2026.09.19 01:02:03';
    expect(config.getPeriod(startTime, endTime, error) && startTime == D'2026.09.19 00:00:00'
        && endTime == D'2026.09.20 00:00:00', "same day ignores input times and includes whole day");
    config.startDate = D'2026.09.20';
    expect(!config.getPeriod(startTime, endTime, error) && error != "", "reversed dates rejected");
    config.startDate = 0;
    config.endDate = D'2024.02.29 23:59:59';
    expect(config.getPeriod(startTime, endTime, error) && startTime == 0 && endTime == D'2024.03.01',
        "leap day end advances to next day");
    config.startDate = D'2026.12.31 23:59:59';
    config.endDate = 0;
    expect(config.getPeriod(startTime, endTime, error) && startTime == D'2026.12.31' && endTime == 0,
        "open-ended start rounds to midnight");
    config.runId = -1;
    expect(!config.getPeriod(startTime, endTime, error), "negative Run rejected");
    config.runId = 0;
    config.higherCount = 4;
    expect(!config.getPeriod(startTime, endTime, error), "unsupported higher-frame count rejected");
}

/**
 * 独自ローカルDBだけでReaderを検証する。接続・注文・メールやCommonファイルを操作しない。
 */
void OnStart() {
    testLogger.setLevel(LOG_INFO);
    testLogger.info(__FUNCTION__, "ALERT_HISTORY_SMOKE_START");
    testPeriods();
    string prefix = "mstng-alert-history-smoke-" + IntegerToString((long)TimeLocal())
        + "-" + IntegerToString((long)GetMicrosecondCount());
    string missingFile = prefix + "-missing.sqlite";
    if (expect(isUnusedFixtureName(missingFile), "missing path is unused")) {
        ZigZagElliotAlertHistoryReader reader;
        string error = "";
        expect(!reader.open(missingFile, false, error) && error != "", "missing database rejected");
        reader.close();
        expect(isUnusedFixtureName(missingFile), "read-only open never creates missing database");
    }
    testFile(prefix + "-current.sqlite", false);
    testFile(prefix + "-legacy.sqlite", true);
    testLogger.info(__FUNCTION__, "ALERT_HISTORY_SMOKE_RESULT checked=" + IntegerToString(checkedCount)
        + " failed=" + IntegerToString(failedCount));
}
