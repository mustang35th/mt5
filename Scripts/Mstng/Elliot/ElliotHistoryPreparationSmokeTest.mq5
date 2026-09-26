#property strict

#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 共通履歴準備の実装を固定市場スタブで検証するScript。
 * production headerだけの市場・時計参照を置換し、DB・売買・実履歴取得は実行しない。
 * テスターの実履歴範囲や処理速度を検証するものではない。
 */

/** 検証失敗数。 */
int failureCount = 0;
/** 検証した条件数。 */
int assertionCount = 0;
/** 固定テスト銘柄。 */
const string testSymbol = "HISTORY_TEST";
/** スタブ対象の全7時間足。 */
ENUM_TIMEFRAMES testTimeFrames[] = {
    PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
};
/** 時間足ごとの可視履歴本数。 */
int testBars[7];
/** 時間足ごとの同期状態。 */
bool testSynchronized[7];
/** Testerとして動作する場合true。 */
bool testTester = true;
/** シミュレーションの現在時刻。 */
datetime testCurrentTime = 0;
/** LIVEの単調経過時計。 */
ulong testClock = 0;
/** 初期取得要求の時間足数。 */
int initialRequestCount = 0;
/** 初期取得要求の順序。 */
ENUM_TIMEFRAMES initialTimeFrames[7];
/** 初期取得要求本数。 */
int initialRequestedBars = 0;
/** 不足履歴の再取得要求数。 */
int retryRequestCount = 0;
/** 最後の再取得対象足。 */
ENUM_TIMEFRAMES lastRetryTimeFrame = PERIOD_CURRENT;
/** 最後の再取得要求本数。 */
int lastRetryBars = 0;
/** Bars参照回数。キャッシュで参照を省略したか確認する。 */
int barsReadCount = 0;
/** CopyRatesの戻り値。履歴本数の更新とは分離する。 */
int copyResult = -1;
/** 再取得時に対象足の可視本数を必要本数へ増やす場合true。 */
bool applyRequestedBars = false;

/**
 * 1条件を検証し、失敗だけを出力する。
 */
void verify(const bool fromPassed, const string fromName) {
    assertionCount++;
    if (!fromPassed) {
        failureCount++;
        Print("ERROR ElliotHistoryPreparationSmokeTest ", fromName);
    }
}

/**
 * 対象を固定7足へ制限する。想定外の足は失敗にする。
 */
int findTestTimeFrame(const ENUM_TIMEFRAMES fromTimeFrame) {
    for (int i = 0; i < ArraySize(testTimeFrames); i++) {
        if (testTimeFrames[i] == fromTimeFrame) {
            return i;
        }
    }
    verify(false, "unexpected timeframe " + EnumToString(fromTimeFrame));
    return -1;
}

/**
 * 全足が必要本数ちょうどの固定市場へ戻す。
 */
void resetMarket(const bool fromTester = true) {
    testTester = fromTester;
    testCurrentTime = D'2026.08.03 10:00:00';
    testClock = 100000;
    initialRequestCount = 0;
    initialRequestedBars = 0;
    retryRequestCount = 0;
    lastRetryTimeFrame = PERIOD_CURRENT;
    lastRetryBars = 0;
    barsReadCount = 0;
    copyResult = -1;
    applyRequestedBars = false;
    for (int i = 0; i < ArraySize(testTimeFrames); i++) {
        testBars[i] = 206;
        testSynchronized[i] = true;
        initialTimeFrames[i] = PERIOD_CURRENT;
    }
    testBars[0] = 61;
}

/**
 * 共通準備が使用するMQL_TESTERの取得だけを提供する。
 */
int testMqlInfoInteger(const ENUM_MQL_INFO_INTEGER fromProperty) {
    verify(fromProperty == MQL_TESTER, "only MQL_TESTER is stubbed");
    if (testTester) {
        return 1;
    }
    return 0;
}

/**
 * 固定したサーバー時刻を返す。
 */
datetime testTimeCurrent() {
    return testCurrentTime;
}

/**
 * 固定したLIVE経過時計を返す。
 */
ulong testGetTickCount64() {
    return testClock;
}

/**
 * 固定市場の可視本数を返す。実市場へは問い合わせない。
 */
int testGetBars(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame) {
    verify(fromSymbol == testSymbol, "Bars symbol is fixed");
    barsReadCount++;
    int index = findTestTimeFrame(fromTimeFrame);
    if (index < 0) {
        return 0;
    }
    return testBars[index];
}

/**
 * 取得要求を記録し、指定時だけ可視本数を更新する。
 */
int testCopyRates(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame,
        const int fromStartPosition, const int fromCount, MqlRates &fromRates[]) {
    verify(fromSymbol == testSymbol && fromStartPosition == 0, "CopyRates target is fixed");
    int index = findTestTimeFrame(fromTimeFrame);
    retryRequestCount++;
    lastRetryTimeFrame = fromTimeFrame;
    lastRetryBars = fromCount;
    ArrayResize(fromRates, 0);
    if (index >= 0 && applyRequestedBars) {
        testBars[index] = fromCount;
    }
    return copyResult;
}

/**
 * 診断用の最古日時だけを返す。
 */
bool testSeriesInfoInteger(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame,
        const ENUM_SERIES_INFO_INTEGER fromProperty, long &fromValue) {
    verify(fromSymbol == testSymbol && fromProperty == SERIES_FIRSTDATE,
        "only fixed-symbol SERIES_FIRSTDATE is stubbed");
    if (findTestTimeFrame(fromTimeFrame) < 0) {
        return false;
    }
    fromValue = (long)D'2021.01.01 00:00:00';
    return true;
}

/**
 * 初期要求と同期確認だけを記録する固定市場の代替ユーティリティ。
 * 実際のWarmUpSeriesUtilは事前include済みだが、このScriptからは呼び出さない。
 */
class HistoryPreparationTestSeries {
public:
    /**
     * productionが渡した初期要求順と本数を記録する。
     */
    static void warmUp(const string fromSymbol, const ENUM_TIMEFRAMES &fromTimeFrames[],
            const int fromBars) {
        verify(fromSymbol == testSymbol, "initial request symbol is fixed");
        initialRequestCount = ArraySize(fromTimeFrames);
        initialRequestedBars = fromBars;
        verify(initialRequestCount <= 7, "initial request count fits fixed seven timeframes");
        for (int i = 0; i < initialRequestCount && i < 7; i++) {
            initialTimeFrames[i] = fromTimeFrames[i];
            findTestTimeFrame(fromTimeFrames[i]);
        }
    }

    /**
     * 固定市場の同期状態を返す。
     */
    static bool isSeriesSynchronized(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame) {
        verify(fromSymbol == testSymbol, "synchronization symbol is fixed");
        int index = findTestTimeFrame(fromTimeFrame);
        if (index < 0) {
            return false;
        }
        return testSynchronized[index];
    }
};

// 置換範囲はproductionの共通履歴準備headerだけに限定する。
#define WarmUpSeriesUtil HistoryPreparationTestSeries
#define MQLInfoInteger testMqlInfoInteger
#define TimeCurrent testTimeCurrent
#define GetTickCount64 testGetTickCount64
#define Bars testGetBars
#define CopyRates testCopyRates
#define SeriesInfoInteger testSeriesInfoInteger
#include <Mstng\Util\ElliotHistoryPreparation.mqh>
#undef SeriesInfoInteger
#undef CopyRates
#undef Bars
#undef GetTickCount64
#undef TimeCurrent
#undef MQLInfoInteger
#undef WarmUpSeriesUtil

/**
 * 初期取得順・500本要求・未初期化とresetの状態を検証する。
 */
void verifyInitializationAndReset() {
    resetMarket();
    ElliotHistoryPreparation preparation;
    verify(!preparation.prepare() && !preparation.isReady(), "uninitialized is not ready");
    verify(!preparation.initialize("", PERIOD_H1), "empty symbol rejected");
    verify(!preparation.initialize(testSymbol, PERIOD_M15), "unsupported anchor rejected");
    verify(initialRequestCount == 0, "invalid setup does not request history");
    verify(preparation.initialize(testSymbol, PERIOD_H1), "H1 initialized");
    verify(initialRequestCount == 5 && initialRequestedBars == 500, "H1 requests five series at 500 bars");
    for (int i = 0; i < 5; i++) {
        verify(initialTimeFrames[i] == testTimeFrames[4 - i], "H1 initial request order");
    }
    verify(!preparation.isReady(), "initialize is not history confirmation");
    verify(preparation.prepare() && preparation.isReady(), "H1 exact requirements ready");
    verify(StringFind(preparation.getStatusText(), "MN1[READY,sync=1,bars=61,required=61") >= 0,
        "all-series status includes MN1 requirements");
    verify(preparation.getMissingStatusText() == "", "ready has no missing-series status");
    preparation.reset();
    verify(!preparation.prepare() && !preparation.isReady(), "reset clears readiness");
    verify(preparation.getStatusText() == "" && preparation.getMissingStatusText() == "",
        "reset clears diagnostics");
    verify(preparation.initialize(testSymbol, PERIOD_M5), "M5 initialized after reset");
    verify(initialRequestCount == 7 && initialRequestedBars == 500, "M5 requests seven series at 500 bars");
    for (int i = 0; i < 7; i++) {
        verify(initialTimeFrames[i] == testTimeFrames[6 - i], "M5 initial request order");
    }
}

/**
 * MN1 60/61本とその他205/206本、同期失敗を検証する。
 */
void verifyRequirements() {
    resetMarket();
    ElliotHistoryPreparation preparation;
    preparation.initialize(testSymbol, PERIOD_H1);
    testBars[0] = 60;
    verify(!preparation.prepare(), "MN1 60 bars rejected");
    verify(StringFind(preparation.getMissingStatusText(), "MN1[WAIT,sync=1,bars=60,required=61") >= 0,
        "missing MN1 diagnosis");
    testBars[0] = 61;
    verify(preparation.prepare(), "MN1 61 bars accepted");
    for (int i = 1; i < 5; i++) {
        testBars[i] = 205;
        verify(!preparation.prepare(), EnumToString(testTimeFrames[i]) + " 205 rejected");
        testBars[i] = 206;
        verify(preparation.prepare(), EnumToString(testTimeFrames[i]) + " 206 accepted");
    }
    testBars[5] = 0;
    testBars[6] = 0;
    verify(preparation.prepare(), "H1 does not require M15 or M5");
    preparation.initialize(testSymbol, PERIOD_M5);
    verify(!preparation.prepare(), "M5 requires both additional series");
    for (int i = 5; i < 7; i++) {
        testBars[5] = 206;
        testBars[6] = 206;
        testBars[i] = 205;
        verify(!preparation.prepare(), EnumToString(testTimeFrames[i]) + " 205 rejected");
        testBars[i] = 206;
        verify(preparation.prepare(), EnumToString(testTimeFrames[i]) + " 206 accepted");
    }
    for (int i = 0; i < 7; i++) {
        testSynchronized[i] = false;
        verify(!preparation.prepare(), EnumToString(testTimeFrames[i]) + " unsynchronized rejected");
        testSynchronized[i] = true;
    }
    verify(preparation.prepare(), "all seven synchronized accepted");
}

/**
 * 取得再要求の60秒間隔と、CopyRates戻り値だけでは成功扱いしないことを検証する。
 */
void verifyRetryRequests() {
    resetMarket();
    datetime initialTime = testCurrentTime;
    testBars[0] = 60;
    ElliotHistoryPreparation preparation;
    preparation.initialize(testSymbol, PERIOD_H1);
    verify(!preparation.prepare() && retryRequestCount == 0, "initial request has one-minute cooldown");
    testCurrentTime = initialTime + 59;
    verify(!preparation.prepare() && retryRequestCount == 0, "no request at 59 seconds");
    testCurrentTime = initialTime + 60;
    verify(!preparation.prepare() && retryRequestCount == 1, "request failure remains not ready at 60 seconds");
    verify(lastRetryTimeFrame == PERIOD_MN1 && lastRetryBars == 61, "retry requests only missing MN1 at 61 bars");
    testCurrentTime = initialTime + 119;
    verify(!preparation.prepare() && retryRequestCount == 1, "failed request still respects cooldown");
    testCurrentTime = initialTime + 120;
    copyResult = 61;
    verify(!preparation.prepare() && retryRequestCount == 2, "CopyRates success alone does not bypass visible bars");
    testCurrentTime = initialTime + 180;
    applyRequestedBars = true;
    verify(preparation.prepare() && retryRequestCount == 3, "visible bars rechecked after request");
    testBars[1] = 205;
    testCurrentTime = initialTime + 240;
    copyResult = 206;
    verify(preparation.prepare(), "non-MN1 request can complete history");
    verify(lastRetryTimeFrame == PERIOD_W1 && lastRetryBars == 206, "other timeframe retry requests 206 bars");
}

/**
 * 開始前3599/3600秒の再確認境界を検証する。
 */
void verifyHourlyWarmup() {
    resetMarket();
    datetime initialTime = testCurrentTime;
    datetime startTime = initialTime + 7200;
    testBars[0] = 60;
    ElliotHistoryPreparation preparation;
    preparation.initialize(testSymbol, PERIOD_H1);
    verify(!preparation.prepare(startTime), "warmup initial check sees missing history");
    int initialReads = barsReadCount;
    testBars[0] = 61;
    testCurrentTime = initialTime + 3599;
    verify(!preparation.prepare(startTime), "warmup 3599 seconds keeps last result");
    verify(barsReadCount == initialReads, "warmup cache avoids market reads");
    testCurrentTime = initialTime + 3600;
    verify(preparation.prepare(startTime), "warmup 3600 seconds refreshes history");
    verify(barsReadCount > initialReads, "hourly boundary rereads history");
}

/**
 * H1途中の開始到達とサーバー時刻逆行で待機が解除されることを検証する。
 */
void verifyStartAndClockReversal() {
    resetMarket();
    testCurrentTime = D'2026.08.03 10:29:59';
    datetime startTime = D'2026.08.03 10:30:00';
    testBars[0] = 60;
    ElliotHistoryPreparation preparation;
    preparation.initialize(testSymbol, PERIOD_H1);
    verify(!preparation.prepare(startTime), "one second before non-hourly start");
    applyRequestedBars = true;
    copyResult = 61;
    testCurrentTime = startTime;
    verify(preparation.prepare(startTime), "exact 10:30 start clears hourly wait");
    verify(retryRequestCount == 1, "start boundary clears initial request cooldown");
    testSynchronized[1] = false;
    verify(!preparation.prepare(startTime), "after start live synchronization is reread in same second");

    resetMarket();
    testBars[0] = 60;
    startTime = testCurrentTime + 7200;
    preparation.initialize(testSymbol, PERIOD_H1);
    verify(!preparation.prepare(startTime), "reverse-clock initial history missing");
    applyRequestedBars = true;
    copyResult = 61;
    testCurrentTime--;
    verify(preparation.prepare(startTime), "clock reversal clears cached missing result");
    verify(retryRequestCount == 1, "clock reversal clears request cooldown");
}

/**
 * 開始後にEAの準備と分析が0/指定開始時刻を交互に渡しても再要求を増やさない。
 */
void verifyAlternatingStartArguments() {
    resetMarket();
    datetime initialTime = testCurrentTime;
    datetime startTime = initialTime - 1800;
    testBars[0] = 60;
    ElliotHistoryPreparation preparation;
    preparation.initialize(testSymbol, PERIOD_H1);
    verify(!preparation.prepare(startTime), "after-start initial missing history");
    testCurrentTime = initialTime + 60;
    verify(!preparation.prepare(startTime) && retryRequestCount == 1, "after-start first retry");
    verify(!preparation.prepare() && retryRequestCount == 1, "zero start argument does not clear cooldown");
    testCurrentTime = initialTime + 119;
    verify(!preparation.prepare(startTime) && retryRequestCount == 1, "specified start argument does not clear cooldown");
    verify(!preparation.prepare() && retryRequestCount == 1, "second zero argument respects 59-second boundary");
    testCurrentTime = initialTime + 120;
    verify(!preparation.prepare(startTime) && retryRequestCount == 2, "alternating arguments retry at 60 seconds");
}

/**
 * LIVE EAの同期のみ互換と、LIVE観測の最低本数条件を検証する。
 */
void verifyLiveRequirementsAndClock() {
    resetMarket(false);
    for (int i = 0; i < 7; i++) {
        testBars[i] = 0;
    }
    datetime futureStart = testCurrentTime + 7200;
    ElliotHistoryPreparation preparation;
    preparation.initialize(testSymbol, PERIOD_H1, false);
    verify(preparation.prepare(futureStart), "LIVE EA keeps synchronization-only readiness");
    verify(StringFind(preparation.getStatusText(), "required=0") >= 0, "LIVE EA required bars reported as zero");
    testSynchronized[0] = false;
    verify(!preparation.prepare(futureStart), "LIVE never caches future-start readiness");
    testCurrentTime += 7200;
    testClock += 59999;
    verify(!preparation.prepare(futureStart) && retryRequestCount == 0, "LIVE cooldown uses monotonic milliseconds");
    testClock++;
    verify(!preparation.prepare(futureStart) && retryRequestCount == 1, "LIVE retry at 60000 milliseconds");
    testSynchronized[0] = true;
    verify(preparation.prepare(futureStart), "LIVE synchronization recovery immediately visible");

    resetMarket(false);
    testBars[0] = 60;
    preparation.initialize(testSymbol, PERIOD_M5);
    verify(!preparation.prepare(futureStart), "LIVE observation still needs MN1 61 bars");
    testBars[0] = 61;
    testBars[6] = 205;
    verify(!preparation.prepare(futureStart), "LIVE observation still needs M5 206 bars");
    testBars[6] = 206;
    verify(preparation.prepare(futureStart), "LIVE observation exact requirements ready");
}

/**
 * 実市場・DB・売買へアクセスせず、productionの準備ロジックを実行する。
 */
void OnStart() {
    failureCount = 0;
    assertionCount = 0;
    verifyInitializationAndReset();
    verifyRequirements();
    verifyRetryRequests();
    verifyHourlyWarmup();
    verifyStartAndClockReversal();
    verifyAlternatingStartArguments();
    verifyLiveRequirementsAndClock();
    Print("INFO ElliotHistoryPreparationSmokeTest assertions=", assertionCount, " failures=", failureCount);
}
