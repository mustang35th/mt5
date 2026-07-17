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
        ArrayResize(
            this.resolvedSymbolNames,
            this.symbolNameInfoAll.size()
        );

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
     * D1、H4、H1、M15の売買方向を各1票として通貨強弱を集計する。
     *
     * 1通貨ペア内の全時間足を取得できた場合だけ票へ反映する。
     *
     * @param fromOscillatorHandleManager シンボル別ハンドル管理クラス。
     * @return 集計処理を実行できた場合true。
     */
    bool calculate(OscillatorHandleManager *fromOscillatorHandleManager) {
        this.reset();

        if (fromOscillatorHandleManager == NULL) {
            this.logger.error(__FUNCTION__, "fromOscillatorHandleManager is NULL");

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

            if (symbolName == "") {
                symbolName = this.resolveSymbolName(canonicalSymbolName);
            }

            if (symbolName == "") {
                this.logger.error(
                    __FUNCTION__,
                    "symbol resolution failed: " + canonicalSymbolName
                );

                continue;
            }

            if (!SymbolSelect(symbolName, true)) {
                this.logger.error(__FUNCTION__, "SymbolSelect failed: " + symbolName);
                this.resolvedSymbolNames[i] = "";

                continue;
            }

            MarketContext poolContext(symbolName, PERIOD_M15);
            OscillatorHandlePool *oscillatorHandlePool =
                fromOscillatorHandleManager.getOrCreatePool(poolContext);

            if (oscillatorHandlePool == NULL) {
                this.logger.error(__FUNCTION__, "oscillatorHandlePool is NULL: " + symbolName);

                continue;
            }

            if (!this.preparePair(symbolName, oscillatorHandlePool)) {
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

            int pairScores[4];
            bool pairIsBuyList[4];
            int pairOscillatorCounts[4];
            datetime pairBarTimes[4];
            bool isPairValid = true;

            for (int j = 0; j < this.getTimeFrameCount(); j++) {
                ENUM_TIMEFRAMES timeFrame = this.getTimeFrame(j);
                MarketContext context(symbolName, timeFrame);
                Oscillator oscillator(context);

                if (!oscillator.updateBuySell(context, oscillatorHandlePool)) {
                    isPairValid = false;
                    break;
                }

                pairScores[j] = -1;

                if (oscillator.isBuy) {
                    pairScores[j] = 1;
                }

                pairIsBuyList[j] = oscillator.isBuy;
                pairOscillatorCounts[j] = oscillator.oscillatorCount;
                pairBarTimes[j] = iTime(symbolName, timeFrame, 0);
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
        return 4;
    }

    /**
     * 指定番号の集計対象時間足を取得する。
     *
     * @param fromIndex 時間足番号。
     * @return D1、H4、H1、M15のいずれか。範囲外の場合PERIOD_CURRENT。
     */
    ENUM_TIMEFRAMES getTimeFrame(int fromIndex) {
        switch (fromIndex) {
            case 0:
                return PERIOD_D1;
            case 1:
                return PERIOD_H4;
            case 2:
                return PERIOD_H1;
            case 3:
                return PERIOD_M15;
        }

        return PERIOD_CURRENT;
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

    /** 正規名に対応する実シンボル名一覧。 */
    string resolvedSymbolNames[];

    /** 今回の集計へ反映した通貨強弱票一覧。 */
    CurrencyStrengthPairVote pairVotes[];

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
     * 指定ペアの価格系列と3本のストキャスハンドルを準備する。
     *
     * D1、H4、H1、M15の全ハンドルを一括生成しておくことで、
     * 最初に未準備だったハンドルだけがタイマーごとに順次生成されることを防ぐ。
     *
     * @param fromSymbolName 準備対象の実シンボル名。
     * @param fromOscillatorHandlePool 対象シンボルのハンドルプール。
     * @return 全価格系列と全ストキャスバッファが準備済みの場合true。
     */
    bool preparePair(
        string fromSymbolName,
        OscillatorHandlePool *fromOscillatorHandlePool
    ) {
        if (fromOscillatorHandlePool == NULL) {
            return false;
        }

        ENUM_TIMEFRAMES timeFrames[4];

        for (int i = 0; i < this.getTimeFrameCount(); i++) {
            timeFrames[i] = this.getTimeFrame(i);
        }

        MarketContext warmUpContext(fromSymbolName, PERIOD_M15);
        WarmUpSeriesUtil::warmUp(warmUpContext, timeFrames, 200);

        StochasticHandlePool *shortHandlePool =
            fromOscillatorHandlePool.getStochasticShortHandlePool();
        StochasticHandlePool *middleHandlePool =
            fromOscillatorHandlePool.getStochasticMiddleHandlePool();
        StochasticHandlePool *longHandlePool =
            fromOscillatorHandlePool.getStochasticLongHandlePool();
        bool isReady = true;

        for (int i = 0; i < this.getTimeFrameCount(); i++) {
            MarketContext context(fromSymbolName, timeFrames[i]);

            if (!WarmUpSeriesUtil::isSeriesSynchronized(context)) {
                isReady = false;
            }

            if (!this.isStochasticHandleReady(shortHandlePool, timeFrames[i])) {
                isReady = false;
            }

            if (!this.isStochasticHandleReady(middleHandlePool, timeFrames[i])) {
                isReady = false;
            }

            if (!this.isStochasticHandleReady(longHandlePool, timeFrames[i])) {
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
     * @return ハンドルが有効で1本以上計算済みの場合true。
     */
    bool isStochasticHandleReady(
        StochasticHandlePool *fromStochasticHandlePool,
        ENUM_TIMEFRAMES fromTimeFrame
    ) {
        if (fromStochasticHandlePool == NULL) {
            return false;
        }

        int handle = fromStochasticHandlePool.getHandle(fromTimeFrame);

        if (handle == INVALID_HANDLE) {
            return false;
        }

        return BarsCalculated(handle) > 0;
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
