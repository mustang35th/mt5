#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Database\ZigZagElliotObservationWriterLock.mqh>

/** 失敗した検証件数。 */
int failureCount = 0;

/** 実行した検証件数。 */
int assertionCount = 0;

/** この実行だけが使用するテストファイル名の接頭辞。 */
string testPrefix = "";

/**
 * 検証結果を集計する。
 */
void expect(const bool fromSuccess, const string fromCaseName) {
    assertionCount++;
    if (!fromSuccess) {
        failureCount++;
        Print("FAIL ", fromCaseName, " error=", GetLastError());
    }
}

/**
 * このテスト実行のsidecarだけを削除する。
 */
void removeTestLock(const string fromDatabaseFileName,
        const bool fromUseCommonFolder, const string fromSourceMode,
        const string fromAnchorTimeFrameText) {
    if (testPrefix == "" || StringFind(fromDatabaseFileName, testPrefix) != 0) {
        expect(false, "cleanup scope rejected");

        return;
    }

    string fileName = fromDatabaseFileName + "." + fromSourceMode
        + "." + fromAnchorTimeFrameText + ".writer.lock";
    int flags = 0;
    if (fromUseCommonFolder) {
        flags = FILE_COMMON;
    }

    if (FileIsExist(fileName, flags)) {
        expect(FileDelete(fileName, flags), "cleanup " + fileName);
    }
}

/**
 * 同じ保存先の排他、別DB・基準足・モード・保存場所の独立性を確認する。
 */
void validateScopes(const string fromDatabaseFileName) {
    ZigZagElliotObservationWriterLock first;
    ZigZagElliotObservationWriterLock second;
    ZigZagElliotObservationWriterLock otherDatabase;
    ZigZagElliotObservationWriterLock otherAnchor;
    ZigZagElliotObservationWriterLock otherMode;
    ZigZagElliotObservationWriterLock commonFolder;
    ZigZagElliotObservationWriterLock commonCompetitor;
    string otherDatabaseFileName = fromDatabaseFileName + ".other";

    expect(!first.isHeld(), "initially not held");
    expect(!first.acquire("", false, "LIVE", "H1") && !first.isHeld(),
        "empty database rejected");
    expect(first.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "first owner acquired");
    expect(first.isHeld(), "first owner retained");
    expect(first.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "same owner acquire is idempotent");
    expect(!second.acquire(fromDatabaseFileName, false, "LIVE", "H1")
        && !second.isHeld(), "same scope competing owner rejected");
    expect(first.isHeld(), "failed competitor does not release owner");

    expect(otherDatabase.acquire(otherDatabaseFileName, false, "LIVE", "H1"),
        "different database independent");
    expect(otherAnchor.acquire(fromDatabaseFileName, false, "LIVE", "M5"),
        "different observation profile anchor independent");
    expect(otherMode.acquire(fromDatabaseFileName, false, "TESTER", "H1"),
        "different source mode independent");
    expect(commonFolder.acquire(fromDatabaseFileName, true, "LIVE", "H1"),
        "local and common destinations independent");
    expect(!commonCompetitor.acquire(fromDatabaseFileName, true, "LIVE", "H1")
        && !commonCompetitor.isHeld(), "common scope competing owner rejected");

    first.release();
    expect(!first.isHeld(), "release resets held state");
    string fileName = fromDatabaseFileName + ".LIVE.H1.writer.lock";
    expect(FileIsExist(fileName), "released sidecar remains present");
    expect(second.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "new owner acquires existing released sidecar");
    expect(!first.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "new owner remains exclusive");

    second.release();
    expect(first.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "original owner reacquires after release");
    first.release();
    first.release();
    expect(!first.isHeld(), "release is idempotent");
    otherDatabase.release();
    otherAnchor.release();
    otherMode.release();
    commonFolder.release();
    expect(commonCompetitor.acquire(fromDatabaseFileName, true, "LIVE", "H1"),
        "common owner reacquires after release");
    commonCompetitor.release();

    expect(!FileIsExist(fromDatabaseFileName)
        && !FileIsExist(fromDatabaseFileName, FILE_COMMON)
        && !FileIsExist(otherDatabaseFileName), "database files were never created");
    removeTestLock(fromDatabaseFileName, false, "LIVE", "H1");
    removeTestLock(fromDatabaseFileName, false, "LIVE", "M5");
    removeTestLock(fromDatabaseFileName, false, "TESTER", "H1");
    removeTestLock(otherDatabaseFileName, false, "LIVE", "H1");
    removeTestLock(fromDatabaseFileName, true, "LIVE", "H1");
}

/**
 * 事前に残った空sidecarは取得を妨げず、デストラクタで解放されることを確認する。
 */
void validateStaleFileAndDestruction(const string fromDatabaseFileName) {
    string fileName = fromDatabaseFileName + ".LIVE.H1.writer.lock";
    int fileHandle = FileOpen(fileName, FILE_BIN | FILE_READ | FILE_WRITE);
    expect(fileHandle != INVALID_HANDLE, "prepare stale empty sidecar");
    if (fileHandle == INVALID_HANDLE) {
        return;
    }

    expect(FileSize(fileHandle) == 0, "stale sidecar is empty");
    FileClose(fileHandle);

    ZigZagElliotObservationWriterLock *temporaryOwner =
        new ZigZagElliotObservationWriterLock();
    expect(temporaryOwner != NULL, "temporary owner allocation");
    if (temporaryOwner == NULL) {
        removeTestLock(fromDatabaseFileName, false, "LIVE", "H1");

        return;
    }

    expect(temporaryOwner.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "stale empty sidecar does not imply ownership");
    ZigZagElliotObservationWriterLock nextOwner;
    expect(!nextOwner.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "temporary owner is exclusive");
    delete temporaryOwner;
    expect(nextOwner.acquire(fromDatabaseFileName, false, "LIVE", "H1"),
        "destructor releases handle");
    nextOwner.release();
    removeTestLock(fromDatabaseFileName, false, "LIVE", "H1");
}

/**
 * 運用DBに触れず、一意のテスト名でWriter排他を検証する。
 */
void OnStart() {
    failureCount = 0;
    assertionCount = 0;
    testPrefix = StringFormat("mstng-observation-writer-lock-smoke-%I64u-%I64u-%I64d",
        GetTickCount64(), GetMicrosecondCount(), ChartID());
    validateScopes(testPrefix + ".sqlite");
    validateStaleFileAndDestruction(testPrefix + ".stale.sqlite");
    if (failureCount == 0) {
        PrintFormat("ZigZagElliotObservationWriterLockSmokeTest PASS assertions=%d",
            assertionCount);

        return;
    }

    PrintFormat("ZigZagElliotObservationWriterLockSmokeTest FAIL count=%d assertions=%d",
        failureCount, assertionCount);
}
