//+------------------------------------------------------------------+
//|                                CurrencyStrengthCalculator.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_CALCULATOR_MQH
#define MSTNG_CURRENCY_STRENGTH_CALCULATOR_MQH

#include <Arrays\ArrayObj.mqh>

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Oscillator\Oscillator.mqh>
#include <Mstng\Oscillator\OscillatorHandleManager.mqh>
#include <Mstng\Strength\CurrencyStrengthInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairVote.mqh>
#include <Mstng\Util\StringUtil.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 全28通貨ペアの時間足別売買方向から8通貨の相対強弱を算出する。
 */
class CurrencyStrengthCalculator {
public:
    /** 集計に成功した通貨ペア数。 */
    int validPairCount;

    /**
     * 主要8通貨を登録して初期化する。
     */
    CurrencyStrengthCalculator() {
        this.logger.setLevel(LOG_INFO);
        this.validPairCount = 0;
        this.lastCalculationFatalError = false;
        this.lastPreparationFailureReason = "";
        int symbolCount = this.symbolNameInfoAll.size();
        ArrayResize(
            this.resolvedSymbolNames,
            symbolCount
        );

        for (int i = 0; i < symbolCount; i++) {
            this.resolvedSymbolNames[i] = "";
        }

        this.addCurrency(ConstantCurrency::USD);
        this.addCurrency(ConstantCurrency::JPY);
        this.addCurrency(ConstantCurrency::EUR);
        this.addCurrency(ConstantCurrency::GBP);
        this.addCurrency(ConstantCurrency::AUD);
        this.addCurrency(ConstantCurrency::NZD);
        this.addCurrency(ConstantCurrency::CAD);
        this.addCurrency(ConstantCurrency::CHF);
    }

    /**
     * 保持している通貨別情報を解放する。
     */
    ~CurrencyStrengthCalculator() {
        this.clear();
    }

    /**
     * MN1、W1、D1、H4、H1、M15、M5の売買方向を各1票として通貨強弱を集計する。
     *
     * 1通貨ペア内の全時間足を取得できた場合だけ票へ反映する。
     *
     * @param fromOscillatorHandleManager シンボル別ハンドル管理クラス。
     * @return 集計処理を実行できた場合true。
     */
    bool calculate(OscillatorHandleManager *fromOscillatorHandleManager) {
        return this.calculateAt(fromOscillatorHandleManager, "", 0);
    }

    /**
     * 指定M5足開始時点で確定済みの各時間足から売買方向を集計する。
     *
     * 1通貨ペア内の全時間足を取得できた場合だけ票へ反映する。
     * 対象時刻が0の場合は、従来どおり各時間足の現在足を参照する。
     *
     * @param fromOscillatorHandleManager シンボル別ハンドル管理クラス。
     * @param fromReferenceSymbolName 時間足境界の基準シンボル名。
     * @param fromTargetM5BarTime スナップショット対象のM5足開始時刻。
     * @return 集計処理を実行できた場合true。
     */
    bool calculateAt(
        OscillatorHandleManager *fromOscillatorHandleManager,
        const string fromReferenceSymbolName,
        const datetime fromTargetM5BarTime
    ) {
        this.reset();

        if (fromOscillatorHandleManager == NULL) {
            this.lastCalculationFatalError = true;
            this.logger.error(__FUNCTION__, "fromOscillatorHandleManager is NULL");

            return false;
        }

        datetime expectedBarTimes[7];

        for (int i = 0; i < this.getTimeFrameCount(); i++) {
            expectedBarTimes[i] = 0;
        }

        if (fromTargetM5BarTime > 0
                && !this.resolveExpectedBarTimes(
                    fromReferenceSymbolName,
                    fromTargetM5BarTime,
                    expectedBarTimes
                )) {
            this.setPreparationFailureReason(
                StringFormat(
                    "reference bar resolution failed. symbol=%s target=%s",
                    fromReferenceSymbolName,
                    TimeToString(
                        fromTargetM5BarTime,
                        TIME_DATE | TIME_MINUTES
                    )
                )
            );

            return false;
        }

        int total = this.symbolNameInfoAll.size();

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *symbolNameInfo = this.symbolNameInfoAll.getSymbolNameInfo(i);

            if (symbolNameInfo == NULL) {
                continue;
            }

            string canonicalSymbolName = symbolNameInfo.symbolName;
            string symbolName = this.resolvedSymbolNames[i];

            if (StringLen(symbolName) == 0) {
                symbolName = this.resolveSymbolName(canonicalSymbolName);
            }

            if (StringLen(symbolName) == 0) {
                this.setPreparationFailureReason(
                    "symbol resolution failed. symbol=" + canonicalSymbolName
                );
                this.logger.error(
                    __FUNCTION__,
                    "symbol resolution failed: " + canonicalSymbolName
                );

                continue;
            }

            if (!SymbolSelect(symbolName, true)) {
                this.setPreparationFailureReason(
                    "SymbolSelect failed. symbol=" + symbolName
                );
                this.logger.error(__FUNCTION__, "SymbolSelect failed: " + symbolName);
                this.resolvedSymbolNames[i] = "";

                continue;
            }

            MarketContext poolContext(symbolName, PERIOD_M15);
            OscillatorHandlePool *oscillatorHandlePool =
                fromOscillatorHandleManager.getOrCreatePool(poolContext);

            if (oscillatorHandlePool == NULL) {
                this.setPreparationFailureReason(
                    "oscillator handle pool is NULL. symbol=" + symbolName
                );
                this.logger.error(__FUNCTION__, "oscillatorHandlePool is NULL: " + symbolName);

                continue;
            }

            int pairShifts[7];
            datetime pairBarTimes[7];

            if (!this.preparePair(
                symbolName,
                oscillatorHandlePool,
                fromTargetM5BarTime,
                expectedBarTimes,
                pairShifts,
                pairBarTimes
            )) {
                continue;
            }

            string baseCurrency = "";
            string profitCurrency = "";

            // ブローカーのメタデータではなく正規名から集計先通貨を確定する。
            if (!StringUtil::splitCurrencyPairName(
                canonicalSymbolName,
                baseCurrency,
                profitCurrency
            )) {
                this.logger.error(
                    __FUNCTION__,
                    "currency pair split failed: " + canonicalSymbolName
                );

                continue;
            }

            CurrencyStrengthInfo *baseInfo = this.getInfo(baseCurrency);
            CurrencyStrengthInfo *profitInfo = this.getInfo(profitCurrency);

            if (baseInfo == NULL || profitInfo == NULL) {
                this.logger.error(__FUNCTION__, "currency info not found: " + symbolName);

                continue;
            }

            int pairScores[7];
            bool pairIsBuyList[7];
            int pairOscillatorCounts[7];
            bool isPairValid = true;

            // 始値モデルの時間足制約に合わせ、M5から上位足の順に参照する。
            for (int j = this.getTimeFrameCount() - 1; j >= 0; j--) {
                ENUM_TIMEFRAMES timeFrame = this.getTimeFrame(j);
                MarketContext context(symbolName, timeFrame);
                Oscillator oscillator(context);

                if (!oscillator.updateBuySell(
                    context,
                    oscillatorHandlePool,
                    pairShifts[j]
                )) {
                    this.setPreparationFailureReason(
                        StringFormat(
                            "oscillator update failed. symbol=%s timeFrame=%s shift=%d",
                            symbolName,
                            EnumToString(timeFrame),
                            pairShifts[j]
                        )
                    );
                    isPairValid = false;
                    break;
                }

                pairScores[j] = -1;

                if (oscillator.isBuy) {
                    pairScores[j] = 1;
                }

                pairIsBuyList[j] = oscillator.isBuy;
                pairOscillatorCounts[j] = oscillator.oscillatorCount;
            }

            if (!isPairValid) {
                continue;
            }

            int firstVoteIndex = ArraySize(this.pairVotes);
            int pairVoteCount = this.getTimeFrameCount();

            if (ArrayResize(
                this.pairVotes,
                firstVoteIndex + pairVoteCount
            ) != firstVoteIndex + pairVoteCount) {
                this.lastCalculationFatalError = true;
                this.logger.error(__FUNCTION__, "pairVotes ArrayResize failed");

                return false;
            }

            for (int j = 0; j < this.getTimeFrameCount(); j++) {
                baseInfo.addScore(j, pairScores[j]);
                profitInfo.addScore(j, 0 - pairScores[j]);

                CurrencyStrengthPairVote pairVote;
                pairVote.pairOrder = i;
                pairVote.timeFrameOrder = j;
                pairVote.canonicalSymbolName = canonicalSymbolName;
                pairVote.resolvedSymbolName = symbolName;
                pairVote.timeFrame = this.getTimeFrame(j);
                pairVote.barTime = pairBarTimes[j];
                pairVote.baseCurrency = baseCurrency;
                pairVote.quoteCurrency = profitCurrency;
                pairVote.isBuy = pairIsBuyList[j];
                pairVote.oscillatorCount = pairOscillatorCounts[j];
                pairVote.baseScore = pairScores[j];
                pairVote.baseScoreAfter = (int)baseInfo.getScore(j);
                pairVote.quoteScoreAfter = (int)profitInfo.getScore(j);
                this.pairVotes[firstVoteIndex + j] = pairVote;
            }

            this.resolvedSymbolNames[i] = symbolName;
            this.validPairCount++;
        }

        return true;
    }

    /**
     * 通貨数を取得する。
     *
     * @return 通貨数。
     */
    int size() {
        return this.currencyStrengthInfoList.Total();
    }

    /**
     * 保持している通貨強弱票数を取得する。
     *
     * @return 通貨強弱票数。
     */
    int getPairVoteCount() {
        return ArraySize(this.pairVotes);
    }

    /**
     * 直近集計で最初に検出した準備不足理由を取得する。
     *
     * @return 準備不足理由。検出されていない場合は空文字。
     */
    string getLastPreparationFailureReason() {
        return this.lastPreparationFailureReason;
    }

    /**
     * 直近集計が再試行待ちではなく致命的エラーで失敗したか判定する。
     *
     * @return 致命的エラーが発生した場合true。
     */
    bool hasLastCalculationFatalError() {
        return this.lastCalculationFatalError;
    }

    /**
     * 指定番号の通貨強弱票を取得する。
     *
     * @param fromIndex 票番号。
     * @param fromPairVote 取得結果の格納先。
     * @return 取得できた場合true。
     */
    bool getPairVote(
        int fromIndex,
        CurrencyStrengthPairVote &fromPairVote
    ) {
        if (fromIndex < 0 || fromIndex >= ArraySize(this.pairVotes)) {
            return false;
        }

        fromPairVote = this.pairVotes[fromIndex];

        return true;
    }

    /**
     * 指定番号の通貨別情報を取得する。
     *
     * @param fromIndex 通貨番号。
     * @return 通貨別情報。範囲外の場合NULL。
     */
    CurrencyStrengthInfo *getInfo(int fromIndex) {
        if (fromIndex < 0 || fromIndex >= this.currencyStrengthInfoList.Total()) {
            return NULL;
        }

        return this.currencyStrengthInfoList.At(fromIndex);
    }

    /**
     * 通貨コードに対応する通貨別情報を取得する。
     *
     * @param fromCurrencyName 通貨コード。
     * @return 通貨別情報。存在しない場合NULL。
     */
    CurrencyStrengthInfo *getInfo(string fromCurrencyName) {
        int total = this.currencyStrengthInfoList.Total();

        for (int i = 0; i < total; i++) {
            CurrencyStrengthInfo *currencyStrengthInfo = this.currencyStrengthInfoList.At(i);

            if (currencyStrengthInfo == NULL) {
                continue;
            }

            if (currencyStrengthInfo.currencyName == fromCurrencyName) {
                return currencyStrengthInfo;
            }
        }

        return NULL;
    }

    /**
     * 集計対象時間足数を取得する。
     *
     * @return 時間足数。
     */
    int getTimeFrameCount() {
        return 7;
    }

    /**
     * 指定番号の集計対象時間足を取得する。
     *
     * @param fromIndex 時間足番号。
     * @return MN1、W1、D1、H4、H1、M15、M5のいずれか。範囲外の場合PERIOD_CURRENT。
     */
    ENUM_TIMEFRAMES getTimeFrame(int fromIndex) {
        switch (fromIndex) {
            case 0:
                return PERIOD_MN1;
            case 1:
                return PERIOD_W1;
            case 2:
                return PERIOD_D1;
            case 3:
                return PERIOD_H4;
            case 4:
                return PERIOD_H1;
            case 5:
                return PERIOD_M15;
            case 6:
                return PERIOD_M5;
        }

        return PERIOD_CURRENT;
    }

    /**
     * 指定通貨の長期平均スコア順位を取得する。
     *
     * @param fromCurrencyIndex 通貨番号。
     * @return 降順の競技順位。完全な集計でない場合は0。
     */
    int getLongTermAverageRank(int fromCurrencyIndex) {
        return this.getAverageRank(fromCurrencyIndex, 0);
    }

    /**
     * 指定通貨の長中期平均スコア順位を取得する。
     *
     * @param fromCurrencyIndex 通貨番号。
     * @return 降順の競技順位。完全な集計でない場合は0。
     */
    int getLongMediumTermAverageRank(int fromCurrencyIndex) {
        return this.getAverageRank(fromCurrencyIndex, 3);
    }

    /**
     * 指定通貨の中期平均スコア順位を取得する。
     *
     * @param fromCurrencyIndex 通貨番号。
     * @return 降順の競技順位。完全な集計でない場合は0。
     */
    int getMediumTermAverageRank(int fromCurrencyIndex) {
        return this.getAverageRank(fromCurrencyIndex, 1);
    }

    /**
     * 指定通貨の中短期平均スコア順位を取得する。
     *
     * @param fromCurrencyIndex 通貨番号。
     * @return 降順の競技順位。完全な集計でない場合は0。
     */
    int getMediumShortTermAverageRank(int fromCurrencyIndex) {
        return this.getAverageRank(fromCurrencyIndex, 4);
    }

    /**
     * 指定通貨の短期平均スコア順位を取得する。
     *
     * @param fromCurrencyIndex 通貨番号。
     * @return 降順の競技順位。完全な集計でない場合は0。
     */
    int getShortTermAverageRank(int fromCurrencyIndex) {
        return this.getAverageRank(fromCurrencyIndex, 2);
    }

    /**
     * 集計対象の全通貨ペア数を取得する。
     *
     * @return 全通貨ペア数。
     */
    int getExpectedPairCount() {
        return this.symbolNameInfoAll.size();
    }

    /**
     * 最も強い通貨を取得する。
     *
     * @return 最強通貨。取得できない場合NULL。
     */
    CurrencyStrengthInfo *getStrongest() {
        CurrencyStrengthInfo *strongest = NULL;
        int total = this.currencyStrengthInfoList.Total();

        for (int i = 0; i < total; i++) {
            CurrencyStrengthInfo *currencyStrengthInfo = this.currencyStrengthInfoList.At(i);

            if (currencyStrengthInfo == NULL
                    || currencyStrengthInfo.getTotalSampleCount() <= 0) {
                continue;
            }

            if (strongest == NULL
                    || currencyStrengthInfo.getTotalScore() > strongest.getTotalScore()) {
                strongest = currencyStrengthInfo;
            }
        }

        return strongest;
    }

    /**
     * 最も弱い通貨を取得する。
     *
     * @return 最弱通貨。取得できない場合NULL。
     */
    CurrencyStrengthInfo *getWeakest() {
        CurrencyStrengthInfo *weakest = NULL;
        int total = this.currencyStrengthInfoList.Total();

        for (int i = 0; i < total; i++) {
            CurrencyStrengthInfo *currencyStrengthInfo = this.currencyStrengthInfoList.At(i);

            if (currencyStrengthInfo == NULL
                    || currencyStrengthInfo.getTotalSampleCount() <= 0) {
                continue;
            }

            if (weakest == NULL
                    || currencyStrengthInfo.getTotalScore() < weakest.getTotalScore()) {
                weakest = currencyStrengthInfo;
            }
        }

        return weakest;
    }

    /**
     * 最強通貨と最弱通貨から売買候補文字列を生成する。
     *
     * @return 例: EURJPY BUY。生成できない場合はハイフン。
     */
    string getPairSignalText() {
        if (this.validPairCount < this.getExpectedPairCount()) {
            return "-";
        }

        CurrencyStrengthInfo *strongest = this.getStrongest();
        CurrencyStrengthInfo *weakest = this.getWeakest();

        if (strongest == NULL || weakest == NULL) {
            return "-";
        }

        if (MathAbs(strongest.getTotalScore() - weakest.getTotalScore()) < 0.1) {
            return "-";
        }

        string symbolName = strongest.currencyName + weakest.currencyName;

        if (this.symbolNameInfoAll.getSymbolNameInfo(symbolName) != NULL) {
            return symbolName + " BUY";
        }

        symbolName = weakest.currencyName + strongest.currencyName;

        if (this.symbolNameInfoAll.getSymbolNameInfo(symbolName) != NULL) {
            return symbolName + " SELL";
        }

        return "-";
    }

private:
    /** 通貨別強弱情報一覧。 */
    CArrayObj currencyStrengthInfoList;

    /** 全28通貨ペア情報。 */
    SymbolNameInfoAll symbolNameInfoAll;

    /** ロガー。 */
    Logger logger;

    /** 直近集計で致命的エラーが発生した場合true。 */
    bool lastCalculationFatalError;

    /** 直近集計で最初に検出した準備不足理由。 */
    string lastPreparationFailureReason;

    /** 正規名に対応する実シンボル名一覧。 */
    string resolvedSymbolNames[];

    /** 今回の集計へ反映した通貨強弱票一覧。 */
    CurrencyStrengthPairVote pairVotes[];

    /**
     * 指定通貨の期間別平均スコア順位を取得する。
     *
     * 自分より平均スコアが高い通貨数に1を加え、同点は同順位とする。
     *
     * @param fromCurrencyIndex 通貨番号。
     * @param fromAverageType 0=長期、1=中期、2=短期、3=長中期、4=中短期。
     * @return 降順の競技順位。順位を算出できない場合は0。
     */
    int getAverageRank(int fromCurrencyIndex, int fromAverageType) {
        if (this.validPairCount < this.getExpectedPairCount()) {
            return 0;
        }

        CurrencyStrengthInfo *targetInfo = this.getInfo(fromCurrencyIndex);

        if (targetInfo == NULL || targetInfo.getTotalSampleCount() <= 0) {
            return 0;
        }

        double targetScore = this.getAverageScore(targetInfo, fromAverageType);
        int rank = 1;
        int total = this.size();

        for (int i = 0; i < total; i++) {
            if (i == fromCurrencyIndex) {
                continue;
            }

            CurrencyStrengthInfo *otherInfo = this.getInfo(i);

            if (otherInfo == NULL || otherInfo.getTotalSampleCount() <= 0) {
                continue;
            }

            double otherScore = this.getAverageScore(
                otherInfo,
                fromAverageType
            );

            if (otherScore - targetScore > 0.000001) {
                rank++;
            }
        }

        return rank;
    }

    /**
     * 指定期間の平均スコアを取得する。
     *
     * @param fromInfo 通貨別集計結果。
     * @param fromAverageType 0=長期、1=中期、2=短期、3=長中期、4=中短期。
     * @return 平均スコア。取得できない場合は0。
     */
    double getAverageScore(
        CurrencyStrengthInfo *fromInfo,
        int fromAverageType
    ) {
        if (fromInfo == NULL) {
            return 0.0;
        }

        switch (fromAverageType) {
            case 0:
                return fromInfo.getLongTermAverageScore();
            case 1:
                return fromInfo.getMediumTermAverageScore();
            case 2:
                return fromInfo.getShortTermAverageScore();
            case 3:
                return fromInfo.getLongMediumTermAverageScore();
            case 4:
                return fromInfo.getMediumShortTermAverageScore();
        }

        return 0.0;
    }

    /**
     * 通貨別強弱情報を追加する。
     *
     * @param fromCurrencyName 通貨コード。
     */
    void addCurrency(string fromCurrencyName) {
        CurrencyStrengthInfo *currencyStrengthInfo = new CurrencyStrengthInfo(fromCurrencyName);

        if (currencyStrengthInfo == NULL) {
            return;
        }

        if (!this.currencyStrengthInfoList.Add(currencyStrengthInfo)) {
            this.logger.error(__FUNCTION__, "currencyStrengthInfoList.Add failed");
            delete currencyStrengthInfo;
        }
    }

    /**
     * 集計値を初期化する。
     */
    void reset() {
        this.validPairCount = 0;
        this.lastCalculationFatalError = false;
        this.lastPreparationFailureReason = "";
        ArrayResize(this.pairVotes, 0);
        int total = this.currencyStrengthInfoList.Total();

        for (int i = 0; i < total; i++) {
            CurrencyStrengthInfo *currencyStrengthInfo = this.currencyStrengthInfoList.At(i);

            if (currencyStrengthInfo != NULL) {
                currencyStrengthInfo.reset();
            }
        }
    }

    /**
     * 保持している通貨別強弱情報を解放する。
     */
    void clear() {
        int total = this.currencyStrengthInfoList.Total();

        for (int i = 0; i < total; i++) {
            CurrencyStrengthInfo *currencyStrengthInfo = this.currencyStrengthInfoList.At(i);

            if (currencyStrengthInfo != NULL) {
                delete currencyStrengthInfo;
            }
        }

        this.currencyStrengthInfoList.Clear();
        ArrayFree(this.pairVotes);
    }

    /**
     * 始値モデルで最初に参照するM5系列を同期する。
     *
     * M5の同期が完了するまで上位足へアクセスしないことで、シンボルごとの
     * 利用可能な最小時間足をM5に固定する。
     *
     * @param fromSymbolName 同期対象シンボル名。
     * @return M5系列が同期済みの場合true。
     */
    bool warmUpM5Series(const string fromSymbolName) {
        ENUM_TIMEFRAMES timeFrames[1];
        timeFrames[0] = PERIOD_M5;

        MarketContext warmUpContext(fromSymbolName, PERIOD_M5);
        WarmUpSeriesUtil::warmUp(warmUpContext, timeFrames, 200);

        return WarmUpSeriesUtil::isSeriesSynchronized(warmUpContext);
    }

    /**
     * 基準M5足の開始時点で確定している時間足別バー時刻を取得する。
     *
     * @param fromReferenceSymbolName 時間足境界の基準シンボル名。
     * @param fromTargetM5BarTime スナップショット対象のM5足開始時刻。
     * @param fromBarTimes 時間足別の確定バー時刻格納先。
     * @return 全時間足の確定バー時刻を取得できた場合true。
     */
    bool resolveExpectedBarTimes(
        const string fromReferenceSymbolName,
        const datetime fromTargetM5BarTime,
        datetime &fromBarTimes[]
    ) {
        if (fromReferenceSymbolName == "" || fromTargetM5BarTime <= 0) {
            return false;
        }

        if (!SymbolSelect(fromReferenceSymbolName, true)) {
            return false;
        }

        if (!this.warmUpM5Series(fromReferenceSymbolName)) {
            return false;
        }

        ENUM_TIMEFRAMES warmUpTimeFrames[7];
        int timeFrameCount = this.getTimeFrameCount();

        for (int i = 0; i < timeFrameCount; i++) {
            int timeFrameIndex = timeFrameCount - 1 - i;
            warmUpTimeFrames[i] = this.getTimeFrame(timeFrameIndex);
        }

        MarketContext warmUpContext(fromReferenceSymbolName, PERIOD_M15);
        WarmUpSeriesUtil::warmUp(warmUpContext, warmUpTimeFrames, 200);

        // 配列格納順は維持し、系列参照だけをM5から上位足の順にする。
        for (int i = timeFrameCount - 1; i >= 0; i--) {
            ENUM_TIMEFRAMES timeFrame = this.getTimeFrame(i);
            MarketContext context(fromReferenceSymbolName, timeFrame);

            if (!WarmUpSeriesUtil::isSeriesSynchronized(context)) {
                return false;
            }

            int containingShift = iBarShift(
                fromReferenceSymbolName,
                timeFrame,
                fromTargetM5BarTime,
                true
            );

            if (containingShift < 0) {
                containingShift = iBarShift(
                    fromReferenceSymbolName,
                    timeFrame,
                    fromTargetM5BarTime,
                    false
                );
            }

            if (containingShift < 0) {
                return false;
            }

            datetime containingBarTime = iTime(
                fromReferenceSymbolName,
                timeFrame,
                containingShift
            );

            if (containingBarTime <= 0
                    || containingBarTime > fromTargetM5BarTime) {
                return false;
            }

            if (timeFrame == PERIOD_M5
                    && containingBarTime != fromTargetM5BarTime) {
                return false;
            }

            datetime sourceBarTime = iTime(
                fromReferenceSymbolName,
                timeFrame,
                containingShift + 1
            );

            if (sourceBarTime <= 0 || sourceBarTime >= fromTargetM5BarTime) {
                return false;
            }

            fromBarTimes[i] = sourceBarTime;
        }

        return true;
    }

    /**
     * 指定ペアの価格系列と3本のストキャスハンドルを準備する。
     *
     * M5、M15、H1、H4、D1、W1、MN1の順で全ハンドルを一括生成しておくことで、
     * 最初に未準備だったハンドルだけがタイマーごとに順次生成されることを防ぐ。
     *
     * @param fromSymbolName 準備対象の実シンボル名。
     * @param fromOscillatorHandlePool 対象シンボルのハンドルプール。
     * @param fromM5BarTime スナップショット対象のM5足開始時刻。0の場合は現在足。
     * @param fromExpectedBarTimes 時間足別の期待する確定バー時刻。
     * @param fromShifts 時間足別の参照シフト格納先。
     * @param fromBarTimes 時間足別の足開始時刻格納先。
     * @return 全価格系列と全ストキャスバッファが準備済みの場合true。
     */
    bool preparePair(
        string fromSymbolName,
        OscillatorHandlePool *fromOscillatorHandlePool,
        const datetime fromM5BarTime,
        const datetime &fromExpectedBarTimes[],
        int &fromShifts[],
        datetime &fromBarTimes[]
    ) {
        if (fromOscillatorHandlePool == NULL) {
            this.setPreparationFailureReason(
                "oscillator handle pool is NULL. symbol=" + fromSymbolName
            );

            return false;
        }

        if (!this.warmUpM5Series(fromSymbolName)) {
            this.setPreparationFailureReason(
                "M5 series is not synchronized. symbol=" + fromSymbolName
            );

            return false;
        }

        ENUM_TIMEFRAMES warmUpTimeFrames[7];
        int timeFrameCount = this.getTimeFrameCount();

        for (int i = 0; i < timeFrameCount; i++) {
            int timeFrameIndex = timeFrameCount - 1 - i;
            warmUpTimeFrames[i] = this.getTimeFrame(timeFrameIndex);
        }

        MarketContext warmUpContext(fromSymbolName, PERIOD_M15);
        WarmUpSeriesUtil::warmUp(warmUpContext, warmUpTimeFrames, 200);

        StochasticHandlePool *shortHandlePool =
            fromOscillatorHandlePool.getStochasticShortHandlePool();
        StochasticHandlePool *middleHandlePool =
            fromOscillatorHandlePool.getStochasticMiddleHandlePool();
        StochasticHandlePool *longHandlePool =
            fromOscillatorHandlePool.getStochasticLongHandlePool();
        bool isReady = true;

        // 始値モデルでは各シンボルの最初の参照時間足をM5に固定する。
        for (int i = timeFrameCount - 1; i >= 0; i--) {
            ENUM_TIMEFRAMES timeFrame = this.getTimeFrame(i);
            MarketContext context(fromSymbolName, timeFrame);

            if (!WarmUpSeriesUtil::isSeriesSynchronized(context)) {
                this.setPreparationFailureReason(
                    StringFormat(
                        "series is not synchronized. symbol=%s timeFrame=%s",
                        fromSymbolName,
                        EnumToString(timeFrame)
                    )
                );
                isReady = false;
            }

            int shift = 0;

            if (fromM5BarTime > 0) {
                shift = iBarShift(
                    fromSymbolName,
                    timeFrame,
                    fromExpectedBarTimes[i],
                    true
                );

                if (shift < 0) {
                    // 実バー欠損時は期待時刻より前の直近確定足を使用する。
                    shift = iBarShift(
                        fromSymbolName,
                        timeFrame,
                        fromExpectedBarTimes[i],
                        false
                    );
                }
            }

            datetime barTime = 0;

            if (shift >= 0) {
                barTime = iTime(fromSymbolName, timeFrame, shift);
            }

            if (shift < 0 || barTime <= 0) {
                this.setPreparationFailureReason(
                    StringFormat(
                        "source bar was not found. symbol=%s timeFrame=%s shift=%d",
                        fromSymbolName,
                        EnumToString(timeFrame),
                        shift
                    )
                );
                isReady = false;
            }

            // 次の足が未生成でshift 0に残っていても、対象時刻より前なら確定足として扱う。
            if (fromM5BarTime > 0
                    && (barTime > fromExpectedBarTimes[i]
                        || barTime >= fromM5BarTime)) {
                this.setPreparationFailureReason(
                    StringFormat(
                        "source bar time is invalid. symbol=%s timeFrame=%s barTime=%s expected=%s target=%s",
                        fromSymbolName,
                        EnumToString(timeFrame),
                        TimeToString(barTime, TIME_DATE | TIME_MINUTES),
                        TimeToString(
                            fromExpectedBarTimes[i],
                            TIME_DATE | TIME_MINUTES
                        ),
                        TimeToString(fromM5BarTime, TIME_DATE | TIME_MINUTES)
                    )
                );
                isReady = false;
            }

            fromShifts[i] = shift;
            fromBarTimes[i] = barTime;

            if (!this.isStochasticHandleReady(
                shortHandlePool,
                timeFrame,
                shift
            )) {
                this.setStochasticPreparationFailureReason(
                    fromSymbolName,
                    timeFrame,
                    "short",
                    shortHandlePool,
                    shift
                );
                isReady = false;
            }

            if (!this.isStochasticHandleReady(
                middleHandlePool,
                timeFrame,
                shift
            )) {
                this.setStochasticPreparationFailureReason(
                    fromSymbolName,
                    timeFrame,
                    "middle",
                    middleHandlePool,
                    shift
                );
                isReady = false;
            }

            if (!this.isStochasticHandleReady(
                longHandlePool,
                timeFrame,
                shift
            )) {
                this.setStochasticPreparationFailureReason(
                    fromSymbolName,
                    timeFrame,
                    "long",
                    longHandlePool,
                    shift
                );
                isReady = false;
            }
        }

        return isReady;
    }

    /**
     * ストキャスハンドルを生成し、バッファ計算済みか判定する。
     *
     * @param fromStochasticHandlePool 対象ストキャスハンドルプール。
     * @param fromTimeFrame 対象時間足。
     * @param fromShift 参照シフト。
     * @return ハンドルが有効で1本以上計算済みの場合true。
     */
    bool isStochasticHandleReady(
        StochasticHandlePool *fromStochasticHandlePool,
        ENUM_TIMEFRAMES fromTimeFrame,
        const int fromShift
    ) {
        if (fromStochasticHandlePool == NULL || fromShift < 0) {
            return false;
        }

        int handle = fromStochasticHandlePool.getHandle(fromTimeFrame);

        if (handle == INVALID_HANDLE) {
            return false;
        }

        return BarsCalculated(handle) > fromShift;
    }

    /**
     * 最初に検出した準備不足理由を保持する。
     *
     * @param fromReason 準備不足理由。
     */
    void setPreparationFailureReason(const string fromReason) {
        if (this.lastPreparationFailureReason != "") {
            return;
        }

        this.lastPreparationFailureReason = fromReason;
    }

    /**
     * ストキャスの準備不足状況を最初の理由として保持する。
     *
     * @param fromSymbolName 対象シンボル名。
     * @param fromTimeFrame 対象時間足。
     * @param fromOscillatorName ストキャス種別。
     * @param fromStochasticHandlePool 対象ハンドルプール。
     * @param fromShift 参照シフト。
     */
    void setStochasticPreparationFailureReason(
        const string fromSymbolName,
        const ENUM_TIMEFRAMES fromTimeFrame,
        const string fromOscillatorName,
        StochasticHandlePool *fromStochasticHandlePool,
        const int fromShift
    ) {
        if (this.lastPreparationFailureReason != "") {
            return;
        }

        int handle = INVALID_HANDLE;
        int calculatedBars = -1;

        if (fromStochasticHandlePool != NULL) {
            handle = fromStochasticHandlePool.getHandle(fromTimeFrame);
        }

        if (handle != INVALID_HANDLE) {
            calculatedBars = BarsCalculated(handle);
        }

        this.lastPreparationFailureReason = StringFormat(
            "stochastic is not ready. symbol=%s timeFrame=%s oscillator=%s seriesBars=%d calculatedBars=%d requiredCalculatedBars=%d shift=%d",
            fromSymbolName,
            EnumToString(fromTimeFrame),
            fromOscillatorName,
            Bars(fromSymbolName, fromTimeFrame),
            calculatedBars,
            fromShift + 1,
            fromShift
        );
    }

    /**
     * 正規シンボル名に対応するブローカーの実シンボル名を解決する。
     *
     * 完全一致を優先し、見つからない場合は接頭辞または接尾辞付き候補から
     * 基軸通貨と決済通貨が一致する最短名を選択する。
     *
     * @param fromCanonicalSymbolName 6文字の正規シンボル名。
     * @return 解決した実シンボル名。見つからない場合は空文字。
     */
    string resolveSymbolName(string fromCanonicalSymbolName) {
        bool isCustom = false;

        if (SymbolExist(fromCanonicalSymbolName, isCustom)) {
            if (SymbolSelect(fromCanonicalSymbolName, true)) {
                return fromCanonicalSymbolName;
            }
        }

        string expectedBaseCurrency = StringSubstr(fromCanonicalSymbolName, 0, 3);
        string expectedProfitCurrency = StringSubstr(fromCanonicalSymbolName, 3, 3);
        string resolvedSymbolName = "";
        int resolvedLength = 0;
        bool resolvedWasSelected = false;
        int total = SymbolsTotal(false);

        for (int i = 0; i < total; i++) {
            string candidateSymbolName = SymbolName(i, false);

            if (candidateSymbolName == ""
                    || StringFind(candidateSymbolName, fromCanonicalSymbolName) < 0) {
                continue;
            }

            bool candidateWasSelected = (bool)SymbolInfoInteger(
                candidateSymbolName,
                SYMBOL_SELECT
            );

            if (!SymbolSelect(candidateSymbolName, true)) {
                continue;
            }

            string baseCurrency = SymbolInfoString(
                candidateSymbolName,
                SYMBOL_CURRENCY_BASE
            );
            string profitCurrency = SymbolInfoString(
                candidateSymbolName,
                SYMBOL_CURRENCY_PROFIT
            );

            if (baseCurrency != expectedBaseCurrency
                    || profitCurrency != expectedProfitCurrency) {
                if (!candidateWasSelected) {
                    SymbolSelect(candidateSymbolName, false);
                }

                continue;
            }

            int candidateLength = StringLen(candidateSymbolName);

            if (resolvedSymbolName == "" || candidateLength < resolvedLength) {
                if (resolvedSymbolName != "" && !resolvedWasSelected) {
                    SymbolSelect(resolvedSymbolName, false);
                }

                resolvedSymbolName = candidateSymbolName;
                resolvedLength = candidateLength;
                resolvedWasSelected = candidateWasSelected;
            } else if (!candidateWasSelected) {
                SymbolSelect(candidateSymbolName, false);
            }
        }

        return resolvedSymbolName;
    }
};

#endif
