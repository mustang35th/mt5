//+------------------------------------------------------------------+
//|                                  M15ElliotAlignmentDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_M15_ELLIOT_ALIGNMENT_DECISION_MQH
#define MSTNG_ELLIOT_M15_ELLIOT_ALIGNMENT_DECISION_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\TrendAlignDecision.mqh>

/**
 * M15一覧の分析方向とEMA200方向による表示グループ。
 */
enum M15ElliotAlignmentGroup {
    m15ElliotAlignmentNone = -1,
    m15ElliotAlignmentAll = 0,
    m15ElliotAlignmentAnalysisOpposite = 1,
    m15ElliotAlignmentEmaMismatch = 2,
    m15ElliotAlignmentBoth = 3
};

/**
 * M15一覧の方向一致と例外時間足の判定結果。
 */
class M15ElliotAlignmentResult {
public:
    /** 判定に必要な分析結果とEMA200値が揃っている場合true。 */
    bool isEvaluated;

    /** 表示対象の多数派方向。対象外の場合NONE。 */
    TrendAlignType alignType;

    /** 表示先のグループ。対象外の場合None。 */
    M15ElliotAlignmentGroup group;

    /** 分析方向が逆の時間足。該当なしの場合PERIOD_CURRENT。 */
    ENUM_TIMEFRAMES analysisOppositeTimeFrame;

    /** EMA200が逆またはNONEの時間足。該当なしの場合PERIOD_CURRENT。 */
    ENUM_TIMEFRAMES emaMismatchTimeFrame;

    /** EMA200の不一致が正常に計算されたNONEの場合true。 */
    bool isEmaNone;

    /**
     * 未判定状態で初期化する。
     */
    M15ElliotAlignmentResult() {
        this.reset();
    }

    /**
     * 全フィールドを未判定状態へ戻す。
     */
    void reset() {
        this.isEvaluated = false;
        this.alignType = trendAlignNone;
        this.group = m15ElliotAlignmentNone;
        this.analysisOppositeTimeFrame = PERIOD_CURRENT;
        this.emaMismatchTimeFrame = PERIOD_CURRENT;
        this.isEmaNone = false;
    }
};

/**
 * MN1～M15の分析方向を基準にM15一覧を4グループへ分類するクラス。
 * 分析方向は1足の逆、W1～M15のEMA200は逆とNONEを合わせて1足まで許可する。
 */
class M15ElliotAlignmentDecision {
public:
    /**
     * 多数派方向と表示グループ、例外時間足を判定する。
     *
     * @param fromElliotAll 複数時間足のElliott分析結果。
     * @param fromResult 判定結果の格納先。
     */
    void evaluate(
        ElliotAll *fromElliotAll,
        M15ElliotAlignmentResult &fromResult
    ) {
        fromResult.reset();

        if (fromElliotAll == NULL || !fromElliotAll.isAnalysisSucceeded) {
            return;
        }

        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
        };
        int buyCount = 0;
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = fromElliotAll.getElliot(timeFrames[i]);
            if (!this.isAnalysisReady(elliot, timeFrames[i])) {
                return;
            }

            if (i > 0 && !this.isEmaReady(elliot, timeFrames[i])) {
                return;
            }

            if (elliot.isBuy) {
                buyCount++;
            }
        }

        fromResult.isEvaluated = true;
        if (buyCount > 1 && buyCount < 5) {
            return;
        }

        bool isBuy = buyCount >= 5;
        ENUM_TIMEFRAMES analysisOppositeTimeFrame = PERIOD_CURRENT;
        ENUM_TIMEFRAMES emaMismatchTimeFrame = PERIOD_CURRENT;
        int emaMismatchCount = 0;
        bool isEmaNone = false;
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = fromElliotAll.getElliot(timeFrames[i]);
            if (elliot.isBuy != isBuy) {
                analysisOppositeTimeFrame = timeFrames[i];
            }

            // MN1のEMA200は判定対象に含めない。
            if (i == 0) {
                continue;
            }

            Ema200 *ema200 = GetPointer(elliot.oscillator.ema200);
            bool isNone = !ema200.isBuy && !ema200.isSell;
            if (isNone || ema200.isBuy != isBuy) {
                emaMismatchCount++;
                emaMismatchTimeFrame = timeFrames[i];
                isEmaNone = isNone;
            }
        }

        if (emaMismatchCount > 1) {
            return;
        }

        fromResult.alignType = trendAlignSell;
        if (isBuy) {
            fromResult.alignType = trendAlignBuy;
        }

        fromResult.group = m15ElliotAlignmentAll;
        if (analysisOppositeTimeFrame != PERIOD_CURRENT) {
            fromResult.group = m15ElliotAlignmentAnalysisOpposite;
        }

        if (emaMismatchCount == 1) {
            fromResult.group = m15ElliotAlignmentEmaMismatch;
            if (analysisOppositeTimeFrame != PERIOD_CURRENT) {
                fromResult.group = m15ElliotAlignmentBoth;
            }
        }

        fromResult.analysisOppositeTimeFrame = analysisOppositeTimeFrame;
        fromResult.emaMismatchTimeFrame = emaMismatchTimeFrame;
        fromResult.isEmaNone = isEmaNone;
    }

private:
    /**
     * 指定時間足の分析結果と最新波動、ポイントの存在を確認する。
     *
     * @param fromElliot 確認対象。
     * @param fromTimeFrame 期待する時間足。
     * @return 判定に使用できる場合true。
     */
    bool isAnalysisReady(Elliot *fromElliot, ENUM_TIMEFRAMES fromTimeFrame) {
        if (fromElliot == NULL
                || fromElliot.marketContext.timeFrame != fromTimeFrame
                || fromElliot.oscillator.marketContext.timeFrame != fromTimeFrame) {
            return false;
        }

        Wave *wave = fromElliot.getLatestWave();
        ZigZagPoint *point = fromElliot.getLatestPoint();
        if (wave == NULL || point == NULL) {
            return false;
        }

        return wave.marketContext.timeFrame == fromTimeFrame
            && point.marketContext.timeFrame == fromTimeFrame;
    }

    /**
     * 未計算値と取得失敗値を除いた価格か確認する。
     *
     * @param fromPrice 確認する価格。
     * @return 有効な価格の場合true。
     */
    bool isValidPrice(const double fromPrice) {
        return MathIsValidNumber(fromPrice)
            && fromPrice != EMPTY_VALUE && fromPrice != 0.0;
    }

    /**
     * 計算済みEMA200か確認し、正常なNONEと初期化状態を区別する。
     *
     * @param fromElliot 確認対象。
     * @param fromTimeFrame 期待する時間足。
     * @return 値と方向フラグ、ラベルが有効な場合true。
     */
    bool isEmaReady(Elliot *fromElliot, ENUM_TIMEFRAMES fromTimeFrame) {
        Ema200 *ema200 = GetPointer(fromElliot.oscillator.ema200);
        if (ema200.marketContext.timeFrame != fromTimeFrame
                || !this.isValidPrice(ema200.close1)
                || !this.isValidPrice(ema200.ema200Shift1)
                || !this.isValidPrice(ema200.ema200Compare)
                || !MathIsValidNumber(ema200.slopePips)
                || ema200.slopePips == EMPTY_VALUE
                || !MathIsValidNumber(ema200.closeEma200DiffPips)
                || ema200.closeEma200DiffPips == EMPTY_VALUE) {
            return false;
        }

        if (ema200.closePosition != EMA200_POSITION_ABOVE
                && ema200.closePosition != EMA200_POSITION_BELOW
                && ema200.closePosition != EMA200_POSITION_EQUAL) {
            return false;
        }

        if (ema200.slopeDirection != EMA200_SLOPE_UP
                && ema200.slopeDirection != EMA200_SLOPE_DOWN
                && ema200.slopeDirection != EMA200_SLOPE_NONE) {
            return false;
        }

        string direction = ema200.getBuySellLabel();
        if (ema200.isBuy && !ema200.isSell) {
            return direction == "BUY";
        }

        if (!ema200.isBuy && ema200.isSell) {
            return direction == "SELL";
        }

        return !ema200.isBuy && !ema200.isSell && direction == "NONE";
    }
};

#endif
