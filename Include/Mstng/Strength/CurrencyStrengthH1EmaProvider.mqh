//+------------------------------------------------------------------+
//|                              CurrencyStrengthH1EmaProvider.mqh   |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_H1_EMA_PROVIDER_MQH
#define MSTNG_CURRENCY_STRENGTH_H1_EMA_PROVIDER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Oscillator\Ema200.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidate.mqh>
#include <Mstng\Strength\CurrencyStrengthPairVote.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 通貨強弱の集計に使用したH1確定足に合わせて、
 * 共通EMA200判定を取得し、シンボル別H1ハンドルを保持する。
 */
class CurrencyStrengthH1EmaProvider {
public:
    /**
     * シンボル別のEMA200保持領域を初期化する。
     */
    CurrencyStrengthH1EmaProvider() {
        ArrayResize(this.ema200Values, 0);
    }

    /**
     * 保持するH1 EMA200とハンドルを解放する。
     */
    ~CurrencyStrengthH1EmaProvider() {
        this.clear();
    }

    /**
     * H1票を最新確定足の基準として共通EMA200判定を候補へ反映する。
     *
     * ハンドルのみ再利用し、取得失敗や過去の判定結果はキャッシュしない。
     * 次のH1足が未生成でshift 0に残っていても、対象時点までに
     * 1時間が経過した足は通貨強弱と同じ確定足として扱う。
     *
     * @param fromPairVote 通貨強弱の集計に使用したH1票。
     * @param fromTargetM5BarTime 集計対象のM5足開始時刻。
     * @param fromCandidate EMA200判定の格納先候補。
     * @return 共通EMA200判定を取得できた場合true。
     */
    bool update(
        CurrencyStrengthPairVote &fromPairVote,
        const datetime fromTargetM5BarTime,
        CurrencyStrengthEntryCandidate &fromCandidate
    ) {
        fromCandidate.resetH1Ema();

        if (fromPairVote.timeFrame != PERIOD_H1
                || fromPairVote.canonicalSymbolName != fromCandidate.symbolName
                || fromPairVote.resolvedSymbolName == ""
                || fromPairVote.barTime <= 0
                || fromTargetM5BarTime <= 0
                || fromPairVote.barTime + PeriodSeconds(PERIOD_H1)
                    > fromTargetM5BarTime) {
            return false;
        }

        string symbolName = fromPairVote.resolvedSymbolName;
        int sourceShift = iBarShift(
            symbolName,
            PERIOD_H1,
            fromPairVote.barTime,
            true
        );

        if (sourceShift < 0
                || iTime(symbolName, PERIOD_H1, sourceShift)
                    != fromPairVote.barTime) {
            return false;
        }

        int profileCloseShift = ZigZagElliotAnalysisProfile::getEma200CloseShift();

        if (profileCloseShift < 1) {
            return false;
        }

        // 集計済みのH1確定足をshift 1相当とし、共通参照足と比較間隔を維持する。
        int closeShift = sourceShift + profileCloseShift - 1;
        datetime emaBarTime = iTime(symbolName, PERIOD_H1, closeShift);
        int compareOffset =
            ZigZagElliotAnalysisProfile::getEma200CompareBarIndex()
            - profileCloseShift;

        if (emaBarTime <= 0
                || emaBarTime > fromPairVote.barTime
                || compareOffset <= 0) {
            return false;
        }

        MarketContext context(symbolName, PERIOD_H1);
        int maximumOffset = compareOffset;

        if (ZigZagElliotAnalysisProfile::getEma200CountBars() > maximumOffset) {
            maximumOffset = ZigZagElliotAnalysisProfile::getEma200CountBars();
        }

        int requiredBars = closeShift + maximumOffset
            + ZigZagElliotAnalysisProfile::getEma200Period();

        // 比較対象の最も古いEMAにも200本分の価格系列を確保する。
        if (Bars(symbolName, PERIOD_H1) < requiredBars
                || !WarmUpSeriesUtil::isSeriesSynchronized(context)) {
            ENUM_TIMEFRAMES timeFrames[] = {PERIOD_H1};
            WarmUpSeriesUtil::warmUp(context, timeFrames, requiredBars);

            return false;
        }

        Ema200 *ema200 = this.getOrCreate(symbolName);

        if (ema200 == NULL) {
            return false;
        }

        if (!ema200.update(
            context,
            closeShift + compareOffset,
            ZigZagElliotAnalysisProfile::getEma200CountBars(),
            ZigZagElliotAnalysisProfile::getEma200MinSlopePips(),
            closeShift
        )) {
            return false;
        }

        // 更新中に新しい足が生成された場合は、ずれたshiftの結果を表示しない。
        if (iTime(symbolName, PERIOD_H1, sourceShift) != fromPairVote.barTime
                || iTime(symbolName, PERIOD_H1, closeShift) != emaBarTime) {
            return false;
        }

        fromCandidate.h1EmaAvailable = true;
        fromCandidate.h1EmaIsBuy = ema200.isBuy;
        fromCandidate.h1EmaIsSell = ema200.isSell;
        fromCandidate.h1EmaBarTime = emaBarTime;
        fromCandidate.h1EmaValue = ema200.ema200Shift1;
        fromCandidate.h1EmaDigits = context.digits;
        fromCandidate.h1EmaCloseDiffPips = ema200.closeEma200DiffPips;
        fromCandidate.h1EmaSlopePips = ema200.slopePips;

        return true;
    }

    /**
     * シンボル別EMA200と所有ハンドルをすべて解放する。
     */
    void clear() {
        for (int i = 0; i < ArraySize(this.ema200Values); i++) {
            if (this.ema200Values[i] != NULL) {
                delete this.ema200Values[i];
                this.ema200Values[i] = NULL;
            }
        }

        ArrayResize(this.ema200Values, 0);
    }

private:
    /** 実シンボルごとにH1ハンドルを所有する共通EMA200。 */
    Ema200 *ema200Values[];

    /**
     * 実シンボルのH1 EMA200を取得し、未登録なら生成する。
     *
     * @param fromSymbolName ブローカー上の実シンボル名。
     * @return 対象の共通EMA200。生成失敗の場合NULL。
     */
    Ema200 *getOrCreate(const string fromSymbolName) {
        int valueCount = ArraySize(this.ema200Values);

        for (int i = 0; i < valueCount; i++) {
            if (this.ema200Values[i] != NULL
                    && this.ema200Values[i].marketContext.symbolName
                        == fromSymbolName) {
                return this.ema200Values[i];
            }
        }

        MarketContext context(fromSymbolName, PERIOD_H1);
        Ema200 *ema200 = new Ema200(context);

        if (ema200 == NULL) {
            return NULL;
        }

        if (ArrayResize(this.ema200Values, valueCount + 1) != valueCount + 1) {
            delete ema200;

            return NULL;
        }

        this.ema200Values[valueCount] = ema200;

        return ema200;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_H1_EMA_PROVIDER_MQH
