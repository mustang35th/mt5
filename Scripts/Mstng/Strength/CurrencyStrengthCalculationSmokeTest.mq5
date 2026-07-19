//+------------------------------------------------------------------+
//|                   CurrencyStrengthCalculationSmokeTest.mq5      |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthPairVoteDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthResultDao.mqh>
#include <Mstng\Database\Dao\CurrencyStrengthRunDao.mqh>
#include <Mstng\Database\Service\CurrencyStrengthPersistenceService.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculator.mqh>
#include <Mstng\Strength\CurrencyStrengthInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairVote.mqh>
#include <Mstng\Util\StringUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/** 全28通貨ペアが準備されるまでの待機上限秒。 */
input int timeoutSeconds = 600;

/** 集計の再試行間隔ミリ秒。 */
input int retryIntervalMilliseconds = 1000;

/** 1票ごとの詳細を出力する場合true。 */
input bool printVoteDetails = false;

/** 実判定結果をデータベースへ保存する場合true。 */
input bool databaseEnabled = true;

/** 実判定結果の保存先データベースファイル名。 */
input string databaseFileName =
    "mstng-currency-strength-calculation-smoke-test.sqlite";

/** データベースを共有フォルダへ保存する場合true。 */
input bool databaseUseCommonFolder = true;

/**
 * bool値をログ用文字列へ変換する。
 *
 * @param fromValue 変換対象。
 * @return trueまたはfalse。
 */
string getBooleanText(const bool fromValue) {
    if (fromValue) {
        return "true";
    }

    return "false";
}

/**
 * isBuyを売買方向文字列へ変換する。
 *
 * @param fromIsBuy BUY判定の場合true。
 * @return BUYまたはSELL。
 */
string getDirectionText(const bool fromIsBuy) {
    if (fromIsBuy) {
        return "BUY";
    }

    return "SELL";
}

/**
 * 通貨コードに対応する集計番号を取得する。
 *
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromCurrencyName 通貨コード。
 * @return 集計番号。見つからない場合は-1。
 */
int findCurrencyIndex(
    CurrencyStrengthCalculator &fromCalculator,
    const string fromCurrencyName
) {
    for (int i = 0; i < fromCalculator.size(); i++) {
        CurrencyStrengthInfo *currencyStrengthInfo = fromCalculator.getInfo(i);

        if (currencyStrengthInfo == NULL) {
            continue;
        }

        if (currencyStrengthInfo.currencyName == fromCurrencyName) {
            return i;
        }
    }

    return -1;
}

/**
 * 全28通貨ペアの実判定が揃うまで集計を再試行する。
 *
 * @param fromOscillatorHandleManager オシレーターハンドル管理クラス。
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromM5BarTime スナップショット基準のM5足開始時刻。
 * @param fromTimeoutSeconds 待機上限秒。
 * @param fromRetryIntervalMilliseconds 再試行間隔ミリ秒。
 * @param fromLogger ロガー。
 * @return 28通貨ペア・196票が揃った場合true。
 */
bool calculateWithRetry(
    OscillatorHandleManager *fromOscillatorHandleManager,
    CurrencyStrengthCalculator &fromCalculator,
    const datetime fromM5BarTime,
    const int fromTimeoutSeconds,
    const int fromRetryIntervalMilliseconds,
    Logger &fromLogger
) {
    uint startTickCount = GetTickCount();
    uint timeoutMilliseconds = (uint)(fromTimeoutSeconds * 1000);
    int attemptCount = 0;

    while (!IsStopped()) {
        attemptCount++;

        bool isCalculated = fromCalculator.calculateAt(
            fromOscillatorHandleManager,
            _Symbol,
            fromM5BarTime
        );

        if (!isCalculated && fromCalculator.hasLastCalculationFatalError()) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "fatal calculation error. attempt=%d",
                    attemptCount
                )
            );

            return false;
        }

        int expectedPairCount = fromCalculator.getExpectedPairCount();
        int expectedVoteCount = expectedPairCount * fromCalculator.getTimeFrameCount();
        int validPairCount = fromCalculator.validPairCount;
        int voteCount = fromCalculator.getPairVoteCount();
        uint elapsedMilliseconds = GetTickCount() - startTickCount;

        if (validPairCount == expectedPairCount
                && voteCount == expectedVoteCount) {
            fromLogger.info(
                __FUNCTION__,
                StringFormat(
                    "all pairs ready. attempt=%d elapsed=%.1f sec pairs=%d votes=%d",
                    attemptCount,
                    (double)elapsedMilliseconds / 1000.0,
                    validPairCount,
                    voteCount
                )
            );

            return true;
        }

        fromLogger.info(
            __FUNCTION__,
            StringFormat(
                "waiting for history and indicators. attempt=%d elapsed=%.1f sec pairs=%d/%d votes=%d/%d",
                attemptCount,
                (double)elapsedMilliseconds / 1000.0,
                validPairCount,
                expectedPairCount,
                voteCount,
                expectedVoteCount
            )
        );

        if (elapsedMilliseconds >= timeoutMilliseconds) {
            break;
        }

        uint remainingMilliseconds = timeoutMilliseconds - elapsedMilliseconds;
        int sleepMilliseconds = fromRetryIntervalMilliseconds;

        if ((uint)sleepMilliseconds > remainingMilliseconds) {
            sleepMilliseconds = (int)remainingMilliseconds;
        }

        if (sleepMilliseconds > 0) {
            Sleep(sleepMilliseconds);
        }
    }

    if (IsStopped()) {
        fromLogger.warn(__FUNCTION__, "script stopped while waiting for data.");
    } else {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "timeout. pairs=%d/%d votes=%d/%d",
                fromCalculator.validPairCount,
                fromCalculator.getExpectedPairCount(),
                fromCalculator.getPairVoteCount(),
                fromCalculator.getExpectedPairCount()
                    * fromCalculator.getTimeFrameCount()
            )
        );
    }

    return false;
}

/**
 * 実際のisBuy判定を通貨ペア単位で出力する。
 *
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromPrintVoteDetails 1票ごとの詳細を出力する場合true。
 * @param fromLogger ロガー。
 */
void printPairVotes(
    CurrencyStrengthCalculator &fromCalculator,
    const bool fromPrintVoteDetails,
    Logger &fromLogger
) {
    string pairSummary = "";
    string previousCanonicalSymbolName = "";
    int voteCount = fromCalculator.getPairVoteCount();

    for (int i = 0; i < voteCount; i++) {
        CurrencyStrengthPairVote pairVote;

        if (!fromCalculator.getPairVote(i, pairVote)) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("getPairVote failed. voteIndex=%d", i)
            );

            continue;
        }

        if (pairVote.canonicalSymbolName != previousCanonicalSymbolName) {
            if (pairSummary != "") {
                fromLogger.info(__FUNCTION__, pairSummary);
            }

            previousCanonicalSymbolName = pairVote.canonicalSymbolName;
            pairSummary = StringFormat(
                "pairOrder=%d pair=%s resolved=%s",
                pairVote.pairOrder,
                pairVote.canonicalSymbolName,
                pairVote.resolvedSymbolName
            );
        }

        pairSummary += StringFormat(
            " %s=%s(isBuy=%s,oscillatorCount=%s)",
            TimeUtil::convertTimeFrameToString(pairVote.timeFrame),
            getDirectionText(pairVote.isBuy),
            getBooleanText(pairVote.isBuy),
            StringUtil::addSign(pairVote.oscillatorCount)
        );

        if (fromPrintVoteDetails) {
            fromLogger.info(
                __FUNCTION__,
                StringFormat(
                    "vote pair=%s timeFrame=%s barTime=%s isBuy=%s direction=%s oscillatorCount=%s base=%s(%s -> %s) quote=%s(%s -> %s)",
                    pairVote.canonicalSymbolName,
                    TimeUtil::convertTimeFrameToString(pairVote.timeFrame),
                    TimeToString(pairVote.barTime, TIME_DATE | TIME_SECONDS),
                    getBooleanText(pairVote.isBuy),
                    getDirectionText(pairVote.isBuy),
                    StringUtil::addSign(pairVote.oscillatorCount),
                    pairVote.baseCurrency,
                    StringUtil::addSign(pairVote.baseScore),
                    StringUtil::addSign(pairVote.baseScoreAfter),
                    pairVote.quoteCurrency,
                    StringUtil::addSign(0 - pairVote.baseScore),
                    StringUtil::addSign(pairVote.quoteScoreAfter)
                )
            );
        }
    }

    if (pairSummary != "") {
        fromLogger.info(__FUNCTION__, pairSummary);
    }
}

/**
 * 集計できなかった通貨ペアを出力する。
 *
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromLogger ロガー。
 */
void printMissingPairs(
    CurrencyStrengthCalculator &fromCalculator,
    Logger &fromLogger
) {
    bool completedPairOrders[28];
    SymbolNameInfoAll symbolNameInfoAll;

    for (int i = 0; i < 28; i++) {
        completedPairOrders[i] = false;
    }

    for (int i = 0; i < fromCalculator.getPairVoteCount(); i++) {
        CurrencyStrengthPairVote pairVote;

        if (!fromCalculator.getPairVote(i, pairVote)) {
            continue;
        }

        if (pairVote.pairOrder >= 0 && pairVote.pairOrder < 28) {
            completedPairOrders[pairVote.pairOrder] = true;
        }
    }

    string missingPairs = "";

    for (int i = 0; i < 28; i++) {
        if (completedPairOrders[i]) {
            continue;
        }

        SymbolNameInfo *symbolNameInfo = symbolNameInfoAll.getSymbolNameInfo(i);

        if (symbolNameInfo == NULL) {
            continue;
        }

        if (missingPairs != "") {
            missingPairs += ",";
        }

        missingPairs += symbolNameInfo.symbolName;
    }

    if (missingPairs != "") {
        fromLogger.warn(__FUNCTION__, "missing pairs=" + missingPairs);
    }
}

/**
 * 通貨別の未正規化集計結果を出力する。
 *
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromLogger ロガー。
 */
void printCurrencyResults(
    CurrencyStrengthCalculator &fromCalculator,
    Logger &fromLogger
) {
    for (int i = 0; i < fromCalculator.size(); i++) {
        CurrencyStrengthInfo *currencyStrengthInfo = fromCalculator.getInfo(i);

        if (currencyStrengthInfo == NULL) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("currency info is NULL. currencyIndex=%d", i)
            );

            continue;
        }

        string resultText = "currency=" + currencyStrengthInfo.currencyName;

        for (int j = 0; j < fromCalculator.getTimeFrameCount(); j++) {
            resultText += StringFormat(
                " %s=%s(samples=%d)",
                TimeUtil::convertTimeFrameToString(fromCalculator.getTimeFrame(j)),
                StringUtil::addSign((int)currencyStrengthInfo.getScore(j)),
                currencyStrengthInfo.getSampleCount(j)
            );
        }

        resultText += StringFormat(
            " long=%.2f(rank=%d) medium=%.2f(rank=%d) short=%.2f(rank=%d) longMedium=%.2f(rank=%d) mediumShort=%.2f(rank=%d)",
            currencyStrengthInfo.getLongTermAverageScore(),
            fromCalculator.getLongTermAverageRank(i),
            currencyStrengthInfo.getMediumTermAverageScore(),
            fromCalculator.getMediumTermAverageRank(i),
            currencyStrengthInfo.getShortTermAverageScore(),
            fromCalculator.getShortTermAverageRank(i),
            currencyStrengthInfo.getLongMediumTermAverageScore(),
            fromCalculator.getLongMediumTermAverageRank(i),
            currencyStrengthInfo.getMediumShortTermAverageScore(),
            fromCalculator.getMediumShortTermAverageRank(i)
        );
        resultText += StringFormat(
            " total=%s(samples=%d)",
            StringUtil::addSign((int)currencyStrengthInfo.getTotalScore()),
            currencyStrengthInfo.getTotalSampleCount()
        );
        fromLogger.info(__FUNCTION__, resultText);
    }

    fromLogger.info(
        __FUNCTION__,
        "pair signal=" + fromCalculator.getPairSignalText()
    );
}

/**
 * 28通貨ペア・196票の内容と累積値を検証する。
 *
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromLogger ロガー。
 * @return 全票が期待値どおりの場合true。
 */
bool validatePairVotes(
    CurrencyStrengthCalculator &fromCalculator,
    Logger &fromLogger
) {
    bool isValid = true;
    int timeFrameCount = fromCalculator.getTimeFrameCount();
    int expectedPairCount = fromCalculator.getExpectedPairCount();
    int expectedVoteCount = expectedPairCount * timeFrameCount;
    int currencyCount = fromCalculator.size();
    int runningScores[8][7];
    int runningSampleCounts[8][7];
    SymbolNameInfoAll symbolNameInfoAll;

    if (expectedPairCount != 28
            || timeFrameCount != 7
            || currencyCount != 8) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "definition count mismatch. expectedPairs=%d timeFrames=%d currencies=%d",
                expectedPairCount,
                timeFrameCount,
                currencyCount
            )
        );

        return false;
    }

    if (fromCalculator.validPairCount != expectedPairCount
            || fromCalculator.getPairVoteCount() != expectedVoteCount) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "result count mismatch. validPairs=%d/%d votes=%d/%d",
                fromCalculator.validPairCount,
                expectedPairCount,
                fromCalculator.getPairVoteCount(),
                expectedVoteCount
            )
        );

        return false;
    }

    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < timeFrameCount; j++) {
            runningScores[i][j] = 0;
            runningSampleCounts[i][j] = 0;
        }
    }

    for (int i = 0; i < fromCalculator.getPairVoteCount(); i++) {
        CurrencyStrengthPairVote pairVote;

        if (!fromCalculator.getPairVote(i, pairVote)) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("getPairVote failed. voteIndex=%d", i)
            );
            isValid = false;

            continue;
        }

        int expectedPairOrder = i / timeFrameCount;
        int expectedTimeFrameOrder = i % timeFrameCount;
        SymbolNameInfo *expectedSymbolNameInfo =
            symbolNameInfoAll.getSymbolNameInfo(expectedPairOrder);

        if (pairVote.pairOrder != expectedPairOrder
                || pairVote.timeFrameOrder != expectedTimeFrameOrder) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "vote order mismatch. voteIndex=%d pairOrder=%d/%d timeFrameOrder=%d/%d",
                    i,
                    pairVote.pairOrder,
                    expectedPairOrder,
                    pairVote.timeFrameOrder,
                    expectedTimeFrameOrder
                )
            );
            isValid = false;
        }

        if (expectedSymbolNameInfo == NULL
                || pairVote.canonicalSymbolName != expectedSymbolNameInfo.symbolName) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "canonical symbol mismatch. voteIndex=%d canonical=%s",
                    i,
                    pairVote.canonicalSymbolName
                )
            );
            isValid = false;
        }

        if (pairVote.timeFrame != fromCalculator.getTimeFrame(expectedTimeFrameOrder)
                || pairVote.barTime <= 0
                || StringLen(pairVote.resolvedSymbolName) == 0) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "market data mismatch. voteIndex=%d resolved=%s timeFrame=%s barTime=%s",
                    i,
                    pairVote.resolvedSymbolName,
                    TimeUtil::convertTimeFrameToString(pairVote.timeFrame),
                    TimeToString(pairVote.barTime, TIME_DATE | TIME_SECONDS)
                )
            );
            isValid = false;
        }

        string expectedBaseCurrency = "";
        string expectedQuoteCurrency = "";

        if (!StringUtil::splitCurrencyPairName(
                pairVote.canonicalSymbolName,
                expectedBaseCurrency,
                expectedQuoteCurrency
            )
                || pairVote.baseCurrency != expectedBaseCurrency
                || pairVote.quoteCurrency != expectedQuoteCurrency) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "currency split mismatch. voteIndex=%d pair=%s base=%s quote=%s",
                    i,
                    pairVote.canonicalSymbolName,
                    pairVote.baseCurrency,
                    pairVote.quoteCurrency
                )
            );
            isValid = false;
        }

        if (StringLen(pairVote.resolvedSymbolName) > 0) {
            string resolvedBaseCurrency = "";
            string resolvedQuoteCurrency = "";
            bool isResolvedBaseCurrencyRead = SymbolInfoString(
                pairVote.resolvedSymbolName,
                SYMBOL_CURRENCY_BASE,
                resolvedBaseCurrency
            );
            bool isResolvedQuoteCurrencyRead = SymbolInfoString(
                pairVote.resolvedSymbolName,
                SYMBOL_CURRENCY_PROFIT,
                resolvedQuoteCurrency
            );

            if (!isResolvedBaseCurrencyRead
                    || !isResolvedQuoteCurrencyRead
                    || resolvedBaseCurrency != expectedBaseCurrency
                    || resolvedQuoteCurrency != expectedQuoteCurrency) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "resolved symbol currency mismatch. voteIndex=%d pair=%s resolved=%s base=%s/%s quote=%s/%s",
                        i,
                        pairVote.canonicalSymbolName,
                        pairVote.resolvedSymbolName,
                        resolvedBaseCurrency,
                        expectedBaseCurrency,
                        resolvedQuoteCurrency,
                        expectedQuoteCurrency
                    )
                );
                isValid = false;
            }
        }

        int expectedBaseScore = -1;

        if (pairVote.isBuy) {
            expectedBaseScore = 1;
        }

        if (pairVote.baseScore != expectedBaseScore) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "base score mismatch. voteIndex=%d isBuy=%s baseScore=%d",
                    i,
                    getBooleanText(pairVote.isBuy),
                    pairVote.baseScore
                )
            );
            isValid = false;
        }

        bool isOscillatorCountValid = false;

        if (pairVote.isBuy
                && (pairVote.oscillatorCount == 2
                    || pairVote.oscillatorCount == 3)) {
            isOscillatorCountValid = true;
        }

        if (!pairVote.isBuy
                && (pairVote.oscillatorCount == -3
                    || pairVote.oscillatorCount == -2)) {
            isOscillatorCountValid = true;
        }

        if (!isOscillatorCountValid) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "oscillator count mismatch. voteIndex=%d isBuy=%s oscillatorCount=%d",
                    i,
                    getBooleanText(pairVote.isBuy),
                    pairVote.oscillatorCount
                )
            );
            isValid = false;
        }

        int baseCurrencyIndex = findCurrencyIndex(
            fromCalculator,
            pairVote.baseCurrency
        );
        int quoteCurrencyIndex = findCurrencyIndex(
            fromCalculator,
            pairVote.quoteCurrency
        );

        if (baseCurrencyIndex < 0 || quoteCurrencyIndex < 0
                || expectedTimeFrameOrder < 0
                || expectedTimeFrameOrder >= timeFrameCount) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "currency index mismatch. voteIndex=%d baseIndex=%d quoteIndex=%d timeFrameOrder=%d",
                    i,
                    baseCurrencyIndex,
                    quoteCurrencyIndex,
                    expectedTimeFrameOrder
                )
            );
            isValid = false;

            continue;
        }

        runningScores[baseCurrencyIndex][expectedTimeFrameOrder] +=
            pairVote.baseScore;
        runningScores[quoteCurrencyIndex][expectedTimeFrameOrder] +=
            0 - pairVote.baseScore;
        runningSampleCounts[baseCurrencyIndex][expectedTimeFrameOrder]++;
        runningSampleCounts[quoteCurrencyIndex][expectedTimeFrameOrder]++;

        if (pairVote.baseScoreAfter
                    != runningScores[baseCurrencyIndex][expectedTimeFrameOrder]
                || pairVote.quoteScoreAfter
                    != runningScores[quoteCurrencyIndex][expectedTimeFrameOrder]) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "running score mismatch. voteIndex=%d baseAfter=%d/%d quoteAfter=%d/%d",
                    i,
                    pairVote.baseScoreAfter,
                    runningScores[baseCurrencyIndex][expectedTimeFrameOrder],
                    pairVote.quoteScoreAfter,
                    runningScores[quoteCurrencyIndex][expectedTimeFrameOrder]
                )
            );
            isValid = false;
        }
    }

    for (int i = 0; i < currencyCount; i++) {
        CurrencyStrengthInfo *currencyStrengthInfo = fromCalculator.getInfo(i);

        if (currencyStrengthInfo == NULL) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("currency info is NULL. currencyIndex=%d", i)
            );
            isValid = false;

            continue;
        }

        for (int j = 0; j < timeFrameCount; j++) {
            if ((int)currencyStrengthInfo.getScore(j) != runningScores[i][j]
                    || currencyStrengthInfo.getSampleCount(j)
                        != runningSampleCounts[i][j]) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "recalculation mismatch. currency=%s timeFrame=%s score=%d/%d samples=%d/%d",
                        currencyStrengthInfo.currencyName,
                        TimeUtil::convertTimeFrameToString(
                            fromCalculator.getTimeFrame(j)
                        ),
                        (int)currencyStrengthInfo.getScore(j),
                        runningScores[i][j],
                        currencyStrengthInfo.getSampleCount(j),
                        runningSampleCounts[i][j]
                    )
                );
                isValid = false;
            }
        }
    }

    return isValid;
}

/**
 * 通貨別集計の票数とゼロサムを検証する。
 *
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromLogger ロガー。
 * @return 全通貨の集計値が期待どおりの場合true。
 */
bool validateCurrencyResults(
    CurrencyStrengthCalculator &fromCalculator,
    Logger &fromLogger
) {
    if (fromCalculator.getTimeFrameCount() != 7
            || fromCalculator.size() != 8) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "definition count mismatch. timeFrames=%d currencies=%d",
                fromCalculator.getTimeFrameCount(),
                fromCalculator.size()
            )
        );

        return false;
    }

    bool isValid = true;
    int totalScore = 0;
    int totalSampleCount = 0;
    double longTermAverageScoreTotal = 0.0;
    double mediumTermAverageScoreTotal = 0.0;
    double shortTermAverageScoreTotal = 0.0;
    double longMediumTermAverageScoreTotal = 0.0;
    double mediumShortTermAverageScoreTotal = 0.0;
    int timeFrameScores[7];

    for (int j = 0; j < fromCalculator.getTimeFrameCount(); j++) {
        timeFrameScores[j] = 0;
    }

    for (int i = 0; i < fromCalculator.size(); i++) {
        CurrencyStrengthInfo *currencyStrengthInfo = fromCalculator.getInfo(i);

        if (currencyStrengthInfo == NULL) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat("currency info is NULL. currencyIndex=%d", i)
            );
            isValid = false;

            continue;
        }

        int calculatedTotalScore = 0;
        int calculatedTotalSampleCount = 0;

        for (int j = 0; j < fromCalculator.getTimeFrameCount(); j++) {
            int score = (int)currencyStrengthInfo.getScore(j);
            int sampleCount = currencyStrengthInfo.getSampleCount(j);
            calculatedTotalScore += score;
            calculatedTotalSampleCount += sampleCount;
            timeFrameScores[j] += score;

            if (sampleCount != 7) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "sample count mismatch. currency=%s timeFrame=%s samples=%d/7",
                        currencyStrengthInfo.currencyName,
                        TimeUtil::convertTimeFrameToString(
                            fromCalculator.getTimeFrame(j)
                        ),
                        sampleCount
                    )
                );
                isValid = false;
            }
        }

        double expectedLongTermAverageScore = (
            currencyStrengthInfo.getScore(0)
            + currencyStrengthInfo.getScore(1)
            + currencyStrengthInfo.getScore(2)
        ) / 3.0;
        double expectedMediumTermAverageScore = (
            currencyStrengthInfo.getScore(2)
            + currencyStrengthInfo.getScore(3)
            + currencyStrengthInfo.getScore(4)
        ) / 3.0;
        double expectedShortTermAverageScore = (
            currencyStrengthInfo.getScore(4)
            + currencyStrengthInfo.getScore(5)
            + currencyStrengthInfo.getScore(6)
        ) / 3.0;
        double expectedLongMediumTermAverageScore = (
            currencyStrengthInfo.getScore(0)
            + currencyStrengthInfo.getScore(1)
            + currencyStrengthInfo.getScore(2)
            + currencyStrengthInfo.getScore(3)
            + currencyStrengthInfo.getScore(4)
        ) / 5.0;
        double expectedMediumShortTermAverageScore = (
            currencyStrengthInfo.getScore(2)
            + currencyStrengthInfo.getScore(3)
            + currencyStrengthInfo.getScore(4)
            + currencyStrengthInfo.getScore(5)
            + currencyStrengthInfo.getScore(6)
        ) / 5.0;
        double longTermAverageScore =
            currencyStrengthInfo.getLongTermAverageScore();
        double mediumTermAverageScore =
            currencyStrengthInfo.getMediumTermAverageScore();
        double shortTermAverageScore =
            currencyStrengthInfo.getShortTermAverageScore();
        double longMediumTermAverageScore =
            currencyStrengthInfo.getLongMediumTermAverageScore();
        double mediumShortTermAverageScore =
            currencyStrengthInfo.getMediumShortTermAverageScore();
        int expectedLongTermAverageRank = 1;
        int expectedMediumTermAverageRank = 1;
        int expectedShortTermAverageRank = 1;
        int expectedLongMediumTermAverageRank = 1;
        int expectedMediumShortTermAverageRank = 1;

        for (int j = 0; j < fromCalculator.size(); j++) {
            if (j == i) {
                continue;
            }

            CurrencyStrengthInfo *otherInfo = fromCalculator.getInfo(j);

            if (otherInfo == NULL) {
                continue;
            }

            if (otherInfo.getLongTermAverageScore()
                    - longTermAverageScore > 0.000001) {
                expectedLongTermAverageRank++;
            }

            if (otherInfo.getMediumTermAverageScore()
                    - mediumTermAverageScore > 0.000001) {
                expectedMediumTermAverageRank++;
            }

            if (otherInfo.getShortTermAverageScore()
                    - shortTermAverageScore > 0.000001) {
                expectedShortTermAverageRank++;
            }

            if (otherInfo.getLongMediumTermAverageScore()
                    - longMediumTermAverageScore > 0.000001) {
                expectedLongMediumTermAverageRank++;
            }

            if (otherInfo.getMediumShortTermAverageScore()
                    - mediumShortTermAverageScore > 0.000001) {
                expectedMediumShortTermAverageRank++;
            }
        }

        int longTermAverageRank = fromCalculator.getLongTermAverageRank(i);
        int mediumTermAverageRank = fromCalculator.getMediumTermAverageRank(i);
        int shortTermAverageRank = fromCalculator.getShortTermAverageRank(i);
        int longMediumTermAverageRank =
            fromCalculator.getLongMediumTermAverageRank(i);
        int mediumShortTermAverageRank =
            fromCalculator.getMediumShortTermAverageRank(i);

        if (MathAbs(
                longTermAverageScore - expectedLongTermAverageScore
            ) > 0.000001
                || MathAbs(
                    mediumTermAverageScore - expectedMediumTermAverageScore
                ) > 0.000001
                || MathAbs(
                    shortTermAverageScore - expectedShortTermAverageScore
                ) > 0.000001
                || MathAbs(
                    longMediumTermAverageScore
                    - expectedLongMediumTermAverageScore
                ) > 0.000001
                || MathAbs(
                    mediumShortTermAverageScore
                    - expectedMediumShortTermAverageScore
                ) > 0.000001) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "average score mismatch. currency=%s long=%.8f/%.8f medium=%.8f/%.8f short=%.8f/%.8f longMedium=%.8f/%.8f mediumShort=%.8f/%.8f",
                    currencyStrengthInfo.currencyName,
                    longTermAverageScore,
                    expectedLongTermAverageScore,
                    mediumTermAverageScore,
                    expectedMediumTermAverageScore,
                    shortTermAverageScore,
                    expectedShortTermAverageScore,
                    longMediumTermAverageScore,
                    expectedLongMediumTermAverageScore,
                    mediumShortTermAverageScore,
                    expectedMediumShortTermAverageScore
                )
            );
            isValid = false;
        }

        if (longTermAverageRank != expectedLongTermAverageRank
                || mediumTermAverageRank != expectedMediumTermAverageRank
                || shortTermAverageRank != expectedShortTermAverageRank
                || longMediumTermAverageRank
                    != expectedLongMediumTermAverageRank
                || mediumShortTermAverageRank
                    != expectedMediumShortTermAverageRank
                || longTermAverageRank < 1
                || longTermAverageRank > fromCalculator.size()
                || mediumTermAverageRank < 1
                || mediumTermAverageRank > fromCalculator.size()
                || shortTermAverageRank < 1
                || shortTermAverageRank > fromCalculator.size()
                || longMediumTermAverageRank < 1
                || longMediumTermAverageRank > fromCalculator.size()
                || mediumShortTermAverageRank < 1
                || mediumShortTermAverageRank > fromCalculator.size()) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "average rank mismatch. currency=%s long=%d/%d medium=%d/%d short=%d/%d longMedium=%d/%d mediumShort=%d/%d",
                    currencyStrengthInfo.currencyName,
                    longTermAverageRank,
                    expectedLongTermAverageRank,
                    mediumTermAverageRank,
                    expectedMediumTermAverageRank,
                    shortTermAverageRank,
                    expectedShortTermAverageRank,
                    longMediumTermAverageRank,
                    expectedLongMediumTermAverageRank,
                    mediumShortTermAverageRank,
                    expectedMediumShortTermAverageRank
                )
            );
            isValid = false;
        }

        longTermAverageScoreTotal += longTermAverageScore;
        mediumTermAverageScoreTotal += mediumTermAverageScore;
        shortTermAverageScoreTotal += shortTermAverageScore;
        longMediumTermAverageScoreTotal += longMediumTermAverageScore;
        mediumShortTermAverageScoreTotal += mediumShortTermAverageScore;

        if ((int)currencyStrengthInfo.getTotalScore() != calculatedTotalScore
                || currencyStrengthInfo.getTotalSampleCount()
                    != calculatedTotalSampleCount
                || calculatedTotalSampleCount != 49) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "currency total mismatch. currency=%s score=%d/%d samples=%d/%d",
                    currencyStrengthInfo.currencyName,
                    (int)currencyStrengthInfo.getTotalScore(),
                    calculatedTotalScore,
                    currencyStrengthInfo.getTotalSampleCount(),
                    49
                )
            );
            isValid = false;
        }

        totalScore += calculatedTotalScore;
        totalSampleCount += calculatedTotalSampleCount;
    }

    for (int j = 0; j < fromCalculator.getTimeFrameCount(); j++) {
        if (timeFrameScores[j] != 0) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "time frame score is not zero. timeFrame=%s score=%d",
                    TimeUtil::convertTimeFrameToString(
                        fromCalculator.getTimeFrame(j)
                    ),
                    timeFrameScores[j]
                )
            );
            isValid = false;
        }
    }

    if (totalScore != 0 || totalSampleCount != 392) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "all currency total mismatch. score=%d/0 samples=%d/392",
                totalScore,
                totalSampleCount
            )
        );
        isValid = false;
    }

    if (MathAbs(longTermAverageScoreTotal) > 0.000001
            || MathAbs(mediumTermAverageScoreTotal) > 0.000001
            || MathAbs(shortTermAverageScoreTotal) > 0.000001
            || MathAbs(longMediumTermAverageScoreTotal) > 0.000001
            || MathAbs(mediumShortTermAverageScoreTotal) > 0.000001) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "all currency average score is not zero. long=%.8f medium=%.8f short=%.8f longMedium=%.8f mediumShort=%.8f",
                longTermAverageScoreTotal,
                mediumTermAverageScoreTotal,
                shortTermAverageScoreTotal,
                longMediumTermAverageScoreTotal,
                mediumShortTermAverageScoreTotal
            )
        );
        isValid = false;
    }

    return isValid;
}

/**
 * 検証済みの実判定結果をデータベースへ保存する。
 *
 * @param fromCalculator 通貨強弱計算クラス。
 * @param fromM5BarTime スナップショット基準のM5足開始時刻。
 * @param fromLogger ロガー。
 * @return スナップショットを保存できた場合true。
 */
bool saveDatabaseSnapshot(
    CurrencyStrengthCalculator &fromCalculator,
    const datetime fromM5BarTime,
    Logger &fromLogger
) {
    datetime calculatedAt = TimeCurrent();

    if (calculatedAt <= 0) {
        calculatedAt = TimeLocal();
    }

    if (calculatedAt <= 0 || fromM5BarTime <= 0) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "invalid snapshot time. calculatedAt=%I64d m5BarTime=%I64d",
                (long)calculatedAt,
                (long)fromM5BarTime
            )
        );

        return false;
    }

    SqliteDatabase database(
        databaseFileName,
        databaseUseCommonFolder
    );

    if (!database.open()) {
        fromLogger.error(__FUNCTION__, "database open failed.");

        return false;
    }

    CurrencyStrengthRunDao runDao(database.getHandle());
    CurrencyStrengthPairVoteDao pairVoteDao(database.getHandle());
    CurrencyStrengthResultDao resultDao(database.getHandle());
    CurrencyStrengthPersistenceService persistenceService(
        database.getHandle(),
        GetPointer(runDao),
        GetPointer(pairVoteDao),
        GetPointer(resultDao)
    );

    if (!persistenceService.createTables()) {
        fromLogger.error(__FUNCTION__, "database object creation failed.");
        database.close();

        return false;
    }

    bool isSaved = persistenceService.save(
        calculatedAt,
        fromM5BarTime,
        CurrencyStrengthCalculationProfile::getCalculationVersion(false),
        "LIVE",
        AccountInfoString(ACCOUNT_SERVER),
        AccountInfoInteger(ACCOUNT_LOGIN),
        ChartID(),
        GetPointer(fromCalculator)
    );
    database.close();

    if (!isSaved) {
        fromLogger.error(__FUNCTION__, "database snapshot save failed.");

        return false;
    }

    fromLogger.info(
        __FUNCTION__,
        StringFormat(
            "database snapshot saved. fileName=%s common=%s m5BarTime=%s",
            databaseFileName,
            getBooleanText(databaseUseCommonFolder),
            TimeToString(fromM5BarTime, TIME_DATE | TIME_SECONDS)
        )
    );

    return true;
}

/**
 * 28通貨ペアの実isBuy判定動作確認を実行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (MQLInfoInteger(MQL_TESTER)) {
        logger.error(
            __FUNCTION__,
            "Run this script on an online chart, not in Strategy Tester."
        );

        return;
    }

    if (timeoutSeconds <= 0 || retryIntervalMilliseconds <= 0) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "invalid inputs. timeoutSeconds=%d retryIntervalMilliseconds=%d",
                timeoutSeconds,
                retryIntervalMilliseconds
            )
        );

        return;
    }

    if (databaseEnabled && StringLen(databaseFileName) == 0) {
        logger.error(__FUNCTION__, "databaseFileName is empty.");

        return;
    }

    if (!TerminalInfoInteger(TERMINAL_CONNECTED)) {
        logger.error(
            __FUNCTION__,
            "Terminal is not connected. Connect to the broker before running."
        );

        return;
    }

    datetime m5BarTime = iTime(_Symbol, PERIOD_M5, 0);

    if (m5BarTime <= 0) {
        logger.error(__FUNCTION__, "current M5 bar time is unavailable.");

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Currency strength calculation smoke test started. closed bars before m5BarTime=%s.",
            TimeToString(m5BarTime, TIME_DATE | TIME_SECONDS)
        )
    );

    OscillatorHandleManager oscillatorHandleManager(PERIOD_M15);
    CurrencyStrengthCalculator calculator;

    if (calculator.getLongTermAverageRank(0) != 0
            || calculator.getMediumTermAverageRank(0) != 0
            || calculator.getShortTermAverageRank(0) != 0
            || calculator.getLongMediumTermAverageRank(0) != 0
            || calculator.getMediumShortTermAverageRank(0) != 0) {
        logger.error(
            __FUNCTION__,
            "Currency strength calculation smoke test FAILED: incomplete ranks must be zero."
        );

        return;
    }

    bool isComplete = calculateWithRetry(
        GetPointer(oscillatorHandleManager),
        calculator,
        m5BarTime,
        timeoutSeconds,
        retryIntervalMilliseconds,
        logger
    );

    printPairVotes(calculator, printVoteDetails, logger);
    printCurrencyResults(calculator, logger);

    if (!isComplete) {
        printMissingPairs(calculator, logger);
        logger.error(
            __FUNCTION__,
            "Currency strength calculation smoke test FAILED: all 28 pairs were not ready."
        );

        return;
    }

    bool arePairVotesValid = validatePairVotes(calculator, logger);
    bool areCurrencyResultsValid = validateCurrencyResults(calculator, logger);

    if (!arePairVotesValid || !areCurrencyResultsValid) {
        logger.error(
            __FUNCTION__,
            "Currency strength calculation smoke test FAILED: validation error."
        );

        return;
    }

    string databaseStatus = "SKIPPED";

    if (databaseEnabled) {
        if (!saveDatabaseSnapshot(calculator, m5BarTime, logger)) {
            logger.error(
                __FUNCTION__,
                "Currency strength calculation smoke test FAILED: database save error."
            );

            return;
        }

        databaseStatus = "SAVED";
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Currency strength calculation smoke test PASSED. pairs=%d votes=%d currencies=%d database=%s",
            calculator.validPairCount,
            calculator.getPairVoteCount(),
            calculator.size(),
            databaseStatus
        )
    );
}
