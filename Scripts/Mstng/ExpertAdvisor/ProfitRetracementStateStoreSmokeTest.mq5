//+------------------------------------------------------------------+
//|                         ProfitRetracementStateStoreSmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Common\MarketContext.mqh>
#include <MstngEa\Domain\ProfitRetracementState.mqh>
#include <MstngEa\Persistence\ProfitRetracementStateStore.mqh>

/** 浮動小数点比較の許容誤差。 */
double comparisonTolerance = 0.000000000001;

/**
 * テスト状態を設定する。
 *
 * @param fromState 設定対象。
 * @param fromPositionIdentifier ポジション識別子。
 * @param fromPositionTicket ポジションチケット。
 * @param fromPositionOpenTimeMilliseconds ポジション開始時刻ミリ秒。
 * @param fromIsBuy BUYポジションの場合true。
 * @param fromOpenPrice 建値。
 * @param fromInitialStopLoss 初期ストップロス。
 * @param fromPositionVolume ポジション数量。
 * @param fromBestPrice 最大利益到達価格。
 * @param fromInitialRiskDistance 初期リスク価格差。
 * @param fromMaxFloatingProfit 最大含み益。
 * @param fromIsInitialRiskAvailable 初期リスクを利用できる場合true。
 * @param fromActivated 監視開始済みの場合true。
 * @param fromConfiguredStartR 保存時の監視開始R。
 * @param fromConfiguredRetracementRate 保存時の利益戻し率。
 */
void setState(
    ProfitRetracementState &fromState,
    const ulong fromPositionIdentifier,
    const ulong fromPositionTicket,
    const long fromPositionOpenTimeMilliseconds,
    const bool fromIsBuy,
    const double fromOpenPrice,
    const double fromInitialStopLoss,
    const double fromPositionVolume,
    const double fromBestPrice,
    const double fromInitialRiskDistance,
    const double fromMaxFloatingProfit,
    const bool fromIsInitialRiskAvailable,
    const bool fromActivated,
    const double fromConfiguredStartR,
    const double fromConfiguredRetracementRate
) {
    fromState.positionIdentifier = fromPositionIdentifier;
    fromState.positionTicket = fromPositionTicket;
    fromState.positionOpenTimeMilliseconds =
        fromPositionOpenTimeMilliseconds;
    fromState.isBuy = fromIsBuy;
    fromState.openPrice = fromOpenPrice;
    fromState.initialStopLoss = fromInitialStopLoss;
    fromState.positionVolume = fromPositionVolume;
    fromState.bestPrice = fromBestPrice;
    fromState.initialRiskDistance = fromInitialRiskDistance;
    fromState.maxFloatingProfit = fromMaxFloatingProfit;
    fromState.isInitialRiskAvailable = fromIsInitialRiskAvailable;
    fromState.activated = fromActivated;
    fromState.configuredStartR = fromConfiguredStartR;
    fromState.configuredRetracementRate =
        fromConfiguredRetracementRate;
}

/**
 * double値が許容誤差内で一致するか判定する。
 *
 * @param fromActual 実値。
 * @param fromExpected 期待値。
 * @return 一致する場合true。
 */
bool isDoubleMatched(
    const double fromActual,
    const double fromExpected
) {
    return MathAbs(fromActual - fromExpected) <= comparisonTolerance;
}

/**
 * 状態の全項目を比較する。
 *
 * @param fromActual 実値。
 * @param fromExpected 期待値。
 * @return 一致する場合true。
 */
bool isStateMatched(
    ProfitRetracementState &fromActual,
    ProfitRetracementState &fromExpected
) {
    return fromActual.positionIdentifier
            == fromExpected.positionIdentifier
        && fromActual.positionTicket == fromExpected.positionTicket
        && fromActual.positionOpenTimeMilliseconds
            == fromExpected.positionOpenTimeMilliseconds
        && fromActual.isBuy == fromExpected.isBuy
        && isDoubleMatched(fromActual.openPrice, fromExpected.openPrice)
        && isDoubleMatched(
            fromActual.initialStopLoss,
            fromExpected.initialStopLoss
        )
        && isDoubleMatched(
            fromActual.positionVolume,
            fromExpected.positionVolume
        )
        && isDoubleMatched(fromActual.bestPrice, fromExpected.bestPrice)
        && isDoubleMatched(
            fromActual.initialRiskDistance,
            fromExpected.initialRiskDistance
        )
        && isDoubleMatched(
            fromActual.maxFloatingProfit,
            fromExpected.maxFloatingProfit
        )
        && fromActual.isInitialRiskAvailable
            == fromExpected.isInitialRiskAvailable
        && fromActual.activated == fromExpected.activated
        && isDoubleMatched(
            fromActual.configuredStartR,
            fromExpected.configuredStartR
        )
        && isDoubleMatched(
            fromActual.configuredRetracementRate,
            fromExpected.configuredRetracementRate
        );
}

/**
 * ファイル操作フラグを取得する。
 *
 * @param fromStore 状態ストア。
 * @return テキスト書込み用フラグ。
 */
int getWriteFlags(ProfitRetracementStateStore &fromStore) {
    int flags = FILE_WRITE | FILE_TXT | FILE_UNICODE;

    if (fromStore.isCommonFolder()) {
        flags = flags | FILE_COMMON;
    }

    return flags;
}

/**
 * 任意の内容を状態ファイルへ書き込む。
 *
 * @param fromFilePath ファイルパス。
 * @param fromText 書込み内容。
 * @param fromStore 状態ストア。
 * @return 書込み成功の場合true。
 */
bool writeTextFile(
    const string fromFilePath,
    const string fromText,
    ProfitRetracementStateStore &fromStore
) {
    ResetLastError();
    int fileHandle = FileOpen(fromFilePath, getWriteFlags(fromStore));

    if (fileHandle == INVALID_HANDLE) {
        PrintFormat(
            "FAIL write test file. path=%s error=%d",
            fromFilePath,
            GetLastError()
        );

        return false;
    }

    uint writtenSize = FileWriteString(fileHandle, fromText);
    FileFlush(fileHandle);
    FileClose(fileHandle);

    uint expectedSize = (uint)StringLen(fromText) * 2;

    if (writtenSize != expectedSize) {
        PrintFormat(
            "FAIL write size. path=%s actual=%d expected=%d",
            fromFilePath,
            (int)writtenSize,
            (int)expectedSize
        );

        return false;
    }

    return true;
}

/**
 * ファイルが存在するか判定する。
 *
 * @param fromFilePath ファイルパス。
 * @param fromStore 状態ストア。
 * @return 存在する場合true。
 */
bool isFileExists(
    const string fromFilePath,
    ProfitRetracementStateStore &fromStore
) {
    int commonFlag = 0;

    if (fromStore.isCommonFolder()) {
        commonFlag = FILE_COMMON;
    }

    return FileIsExist(fromFilePath, commonFlag);
}

/**
 * 保存と別インスタンスからの読込みを検証する。
 *
 * @param fromMarketContext テスト用市場コンテキスト。
 * @param fromMagicNumber テスト用マジックナンバー。
 * @return 検証成功の場合true。
 */
bool validateRoundTrip(
    MarketContext &fromMarketContext,
    const ulong fromMagicNumber
) {
    ProfitRetracementStateStore writer(
        fromMarketContext,
        fromMagicNumber,
        true
    );
    ProfitRetracementState expected;
    setState(
        expected,
        (ulong)9007199254740993,
        (ulong)9007199254740995,
        (long)1767225600123,
        true,
        1.23456789012345,
        1.22222222222222,
        0.37,
        1.25678901234567,
        0.01234566790123,
        12345.6789012345,
        true,
        true,
        1.75,
        0.275
    );

    if (!writer.clear()) {
        Print("FAIL round trip initial clear: "
            + writer.getLastErrorMessage());

        return false;
    }

    if (!writer.save(expected, true) || !writer.exists()) {
        Print("FAIL round trip save: " + writer.getLastErrorMessage());

        return false;
    }

    // 別インスタンスから読み込み、EA再起動相当の状態復元を確認
    ProfitRetracementStateStore reader(
        fromMarketContext,
        fromMagicNumber,
        true
    );
    ProfitRetracementState actual;

    if (!reader.load(actual)) {
        Print("FAIL round trip load: " + reader.getLastErrorMessage());

        return false;
    }

    if (!isStateMatched(actual, expected)) {
        PrintFormat(
            "FAIL round trip mismatch. identifier=%I64u/%I64u ticket=%I64u/%I64u risk=%.14f/%.14f maxProfit=%.14f/%.14f",
            actual.positionIdentifier,
            expected.positionIdentifier,
            actual.positionTicket,
            expected.positionTicket,
            actual.initialRiskDistance,
            expected.initialRiskDistance,
            actual.maxFloatingProfit,
            expected.maxFloatingProfit
        );

        return false;
    }

    return true;
}

/**
 * 既存状態の全量上書きを検証する。
 *
 * @param fromStore 状態ストア。
 * @return 検証成功の場合true。
 */
bool validateOverwrite(ProfitRetracementStateStore &fromStore) {
    ProfitRetracementState expected;
    setState(
        expected,
        (ulong)9007199254740993,
        (ulong)9007199254741001,
        (long)1767225600123,
        false,
        1.19876543210987,
        1.22222222222222,
        1.25,
        1.17530864210987,
        0.02345678901234,
        54321.987654321,
        true,
        false,
        2.25,
        0.45
    );

    if (!fromStore.save(expected, true)) {
        Print("FAIL overwrite save: "
            + fromStore.getLastErrorMessage());

        return false;
    }

    ProfitRetracementState actual;

    if (!fromStore.load(actual)) {
        Print("FAIL overwrite load: "
            + fromStore.getLastErrorMessage());

        return false;
    }

    if (!isStateMatched(actual, expected)) {
        Print("FAIL overwrite mismatch");

        return false;
    }

    return true;
}

/**
 * 残留一時ファイルが正常な確定ファイルへ影響しないことを検証する。
 *
 * @param fromStore 状態ストア。
 * @return 検証成功の場合true。
 */
bool validateTemporaryFileIsolation(
    ProfitRetracementStateStore &fromStore
) {
    ProfitRetracementState expected;
    setState(
        expected,
        (ulong)9007199254740997,
        (ulong)9007199254740999,
        (long)1767225600999,
        true,
        155.123456789012,
        154.0,
        2.5,
        157.987654321098,
        1.123456789012,
        9876.54321098765,
        true,
        true,
        1.5,
        0.3
    );

    if (!fromStore.save(expected, true)) {
        Print("FAIL temporary isolation save: "
            + fromStore.getLastErrorMessage());

        return false;
    }

    string temporaryFilePath = fromStore.getTemporaryFilePath();

    if (!writeTextFile(
            temporaryFilePath,
            "incomplete temporary state",
            fromStore
        )) {
        return false;
    }

    ProfitRetracementState actual;

    if (!fromStore.load(actual)) {
        Print("FAIL temporary isolation load: "
            + fromStore.getLastErrorMessage());

        return false;
    }

    if (!isStateMatched(actual, expected)) {
        Print("FAIL temporary file affected final state");

        return false;
    }

    if (!fromStore.clear()) {
        Print("FAIL temporary isolation clear: "
            + fromStore.getLastErrorMessage());

        return false;
    }

    if (fromStore.exists()
            || isFileExists(temporaryFilePath, fromStore)) {
        Print("FAIL clear left final or temporary file");

        return false;
    }

    return true;
}

/**
 * 破損ファイルを復元せず、読込み先も変更しないことを検証する。
 *
 * @param fromStore 状態ストア。
 * @return 検証成功の場合true。
 */
bool validateCorruptedFileRejection(
    ProfitRetracementStateStore &fromStore
) {
    if (!writeTextFile(
            fromStore.getFilePath(),
            "invalid-field-count",
            fromStore
        )) {
        return false;
    }

    ProfitRetracementState actual;
    ProfitRetracementState expectedUnchanged;
    setState(
        actual,
        (ulong)101,
        (ulong)102,
        (long)103,
        false,
        104.0,
        103.0,
        0.1,
        107.0,
        105.0,
        106.0,
        true,
        true,
        1.5,
        0.3
    );
    setState(
        expectedUnchanged,
        (ulong)101,
        (ulong)102,
        (long)103,
        false,
        104.0,
        103.0,
        0.1,
        107.0,
        105.0,
        106.0,
        true,
        true,
        1.5,
        0.3
    );

    if (fromStore.load(actual)) {
        Print("FAIL corrupted file was accepted");

        return false;
    }

    if (!isStateMatched(actual, expectedUnchanged)) {
        Print("FAIL corrupted load changed destination state");

        return false;
    }

    if (StringLen(fromStore.getLastErrorMessage()) == 0) {
        Print("FAIL corrupted load has no error detail");

        return false;
    }

    if (StringFind(
            fromStore.getLastErrorMessage(),
            "field count"
        ) < 0) {
        Print("FAIL invalid field count was not identified: "
            + fromStore.getLastErrorMessage());

        return false;
    }

    string unsupportedSchemaText =
        "MSTNGEA_PROFIT_RETRACEMENT_STATE\r\nschema_version=999";

    for (int i = 2; i < 22; i++) {
        unsupportedSchemaText += "\r\nunused";
    }

    if (!writeTextFile(
            fromStore.getFilePath(),
            unsupportedSchemaText,
            fromStore
        )) {
        return false;
    }

    if (fromStore.load(actual)) {
        Print("FAIL unsupported schema was accepted");

        return false;
    }

    if (!isStateMatched(actual, expectedUnchanged)) {
        Print("FAIL unsupported schema changed destination state");

        return false;
    }

    if (StringFind(
            fromStore.getLastErrorMessage(),
            "schema"
        ) < 0) {
        Print("FAIL unsupported schema was not identified: "
            + fromStore.getLastErrorMessage());

        return false;
    }

    return true;
}

/**
 * 利益戻し状態ストアの永続化動作を検証する。
 */
void OnStart() {
    MarketContext marketContext(
        "MSTNG_STATE_STORE_SMOKE",
        PERIOD_H1,
        "H1",
        5
    );
    ulong magicNumber = (ulong)987654321098765;
    ProfitRetracementStateStore store(
        marketContext,
        magicNumber,
        true
    );
    int failureCount = 0;

    if (!validateRoundTrip(marketContext, magicNumber)) {
        failureCount++;
    }

    if (!validateOverwrite(store)) {
        failureCount++;
    }

    if (!validateTemporaryFileIsolation(store)) {
        failureCount++;
    }

    if (!validateCorruptedFileRejection(store)) {
        failureCount++;
    }

    if (!store.clear()) {
        Print("FAIL final clear: " + store.getLastErrorMessage());
        failureCount++;
    }

    if (failureCount == 0) {
        Print("ProfitRetracementStateStoreSmokeTest PASS");

        return;
    }

    PrintFormat(
        "ProfitRetracementStateStoreSmokeTest FAIL count=%d",
        failureCount
    );
}
