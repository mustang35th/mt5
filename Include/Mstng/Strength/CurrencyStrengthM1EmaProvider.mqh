//+------------------------------------------------------------------+
//|                              CurrencyStrengthM1EmaProvider.mqh   |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_M1_EMA_PROVIDER_MQH
#define MSTNG_CURRENCY_STRENGTH_M1_EMA_PROVIDER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Oscillator\Ema200.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidate.mqh>
#include <Mstng\Util\Util.mqh>
#include <Mstng\Util\WarmUpSeriesUtil.mqh>

/**
 * 対象時刻までに確定した最新M1足の共通EMA200判定を取得し、
 * シンボル別M1ハンドルを保持する。
 */
class CurrencyStrengthM1EmaProvider {
public:
    /**
     * シンボル別のEMA200保持領域を初期化する。
     */
    CurrencyStrengthM1EmaProvider() {
        ArrayResize(this.ema200Values, 0);
    }

    /**
     * 保持するM1 EMA200とハンドルを解放する。
     */
    ~CurrencyStrengthM1EmaProvider() {
        this.clear();
    }

    /**
     * 対象時刻までに確定した最新M1足の共通EMA200判定を候補へ反映する。
     *
     * ハンドルのみ再利用し、取得失敗や過去の判定結果はキャッシュしない。
     * 次のM1足が未生成でも、60秒が経過した足は確定足として扱う。
     * M5始値のみテストの下位足参照を避けるため、テスターでは取得しない。
     *
     * @param fromTargetTime LIVEの判定基準となるサーバー時刻。
     * @param fromCandidate 実シンボル名とEMA200判定の格納先候補。
     * @return 共通EMA200判定を取得できた場合true。
     */
    bool update(
        const datetime fromTargetTime,
        CurrencyStrengthEntryCandidate &fromCandidate
    ) {
        fromCandidate.resetM1Ema();

        if (Util::isStrategyTester()
                || fromCandidate.resolvedSymbolName == ""
                || fromTargetTime <= 0) {
            return false;
        }

        int periodSeconds = PeriodSeconds(PERIOD_M1);
        int profileCloseShift = ZigZagElliotAnalysisProfile::getEma200CloseShift();
        int compareOffset =
            ZigZagElliotAnalysisProfile::getEma200CompareBarIndex()
            - profileCloseShift;

        if (periodSeconds <= 0 || fromTargetTime < periodSeconds
                || profileCloseShift < 1 || compareOffset <= 0) {
            return false;
        }

        string symbolName = fromCandidate.resolvedSymbolName;
        MarketContext context(symbolName, PERIOD_M1);
        int maximumOffset = compareOffset;
        if (ZigZagElliotAnalysisProfile::getEma200CountBars() > maximumOffset) {
            maximumOffset = ZigZagElliotAnalysisProfile::getEma200CountBars();
        }

        int requiredBars = profileCloseShift - 1 + maximumOffset
            + ZigZagElliotAnalysisProfile::getEma200Period();
        ENUM_TIMEFRAMES timeFrames[] = {PERIOD_M1};
        if (Bars(symbolName, PERIOD_M1) < requiredBars
                || !WarmUpSeriesUtil::isSeriesSynchronized(context)) {
            WarmUpSeriesUtil::warmUp(context, timeFrames, requiredBars);

            return false;
        }

        // 60秒以上前に開始した最も新しい足を選び、未確定足を参照しない。
        int sourceShift = iBarShift(
            symbolName,
            PERIOD_M1,
            fromTargetTime - periodSeconds,
            false
        );

        if (sourceShift < 0) {
            WarmUpSeriesUtil::warmUp(context, timeFrames, requiredBars);

            return false;
        }

        datetime sourceBarTime = iTime(symbolName, PERIOD_M1, sourceShift);
        if (sourceBarTime <= 0 || sourceBarTime + periodSeconds > fromTargetTime) {
            return false;
        }

        // 最新確定M1足をshift 1相当とし、共通参照足と比較間隔を維持する。
        int closeShift = sourceShift + profileCloseShift - 1;
        datetime emaBarTime = iTime(symbolName, PERIOD_M1, closeShift);
        if (emaBarTime <= 0 || emaBarTime > sourceBarTime) {
            return false;
        }

        requiredBars = closeShift + maximumOffset
            + ZigZagElliotAnalysisProfile::getEma200Period();
        if (Bars(symbolName, PERIOD_M1) < requiredBars) {
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
        if (iTime(symbolName, PERIOD_M1, sourceShift) != sourceBarTime
                || iTime(symbolName, PERIOD_M1, closeShift) != emaBarTime) {
            return false;
        }

        fromCandidate.m1EmaAvailable = true;
        fromCandidate.m1EmaIsBuy = ema200.isBuy;
        fromCandidate.m1EmaIsSell = ema200.isSell;
        fromCandidate.m1EmaBarTime = emaBarTime;
        fromCandidate.m1EmaValue = ema200.ema200Shift1;
        fromCandidate.m1EmaDigits = context.digits;
        fromCandidate.m1EmaCloseDiffPips = ema200.closeEma200DiffPips;
        fromCandidate.m1EmaSlopePips = ema200.slopePips;

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
    /** 実シンボルごとにM1ハンドルを所有する共通EMA200。 */
    Ema200 *ema200Values[];

    /**
     * 実シンボルのM1 EMA200を取得し、未登録なら生成する。
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

        MarketContext context(fromSymbolName, PERIOD_M1);
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

#endif // MSTNG_CURRENCY_STRENGTH_M1_EMA_PROVIDER_MQH
