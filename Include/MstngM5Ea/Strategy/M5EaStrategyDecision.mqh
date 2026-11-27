#ifndef MSTNGM5EA_STRATEGY_DECISION_MQH
#define MSTNGM5EA_STRATEGY_DECISION_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3M5Policy.mqh>
#include <MstngEaCommon\Runtime\EaTextUtil.mqh>
#include <MstngM5Ea\Strategy\M5EaStrategySnapshot.mqh>

/**
 * 通常版ZigZagElliotのM5判定に保存済み回数を接続する。
 * 元分析の回数キーを固定し、採用分析のSL・診断値を所有権解放前にコピーする。
 */
class M5EaStrategyDecision {
public:
    /**
     * Judgeを実行せず、元M5のシグナル識別キーと価格を取り出す。
     */
    bool prepare(ElliotAll *fromElliotAll, const datetime fromBarTime,
            M5EaStrategySnapshot &fromSnapshot) {
        fromSnapshot.reset();
        fromSnapshot.barTime = fromBarTime;
        fromSnapshot.evaluatedTime = TimeCurrent();
        fromSnapshot.reasonCode = "ANALYSIS_UNAVAILABLE";

        if (!this.isAnalysisAvailable(fromElliotAll) || fromBarTime <= 0) {
            return false;
        }

        ZigZagPoint *pivot = fromElliotAll.elliotCurrent.getLatestPoint2();
        if (pivot == NULL || pivot.barTime <= 0) {
            return false;
        }

        if (!MathIsValidNumber(fromElliotAll.todayRate.spread)
                || fromElliotAll.todayRate.spread < 0.0
                || !MathIsValidNumber(fromElliotAll.todayRate.bid)
                || !MathIsValidNumber(fromElliotAll.todayRate.ask)
                || fromElliotAll.todayRate.bid <= 0.0
                || fromElliotAll.todayRate.ask < fromElliotAll.todayRate.bid
                || fromElliotAll.todayRate.ask == EMPTY_VALUE) {
            fromSnapshot.reasonCode = "PRICE_UNAVAILABLE";
            return false;
        }

        fromSnapshot.isBuy = fromElliotAll.elliotCurrent.isBuy;
        fromSnapshot.signalSide = this.direction(fromSnapshot.isBuy);
        fromSnapshot.signalReferenceTime = pivot.barTime;
        fromSnapshot.signalReferencePrice = pivot.rate;
        fromSnapshot.signalReferenceIsHigh = pivot.isPeak;
        fromSnapshot.spreadPips = fromElliotAll.todayRate.spread;
        fromSnapshot.bid = fromElliotAll.todayRate.bid;
        fromSnapshot.ask = fromElliotAll.todayRate.ask;

        fromSnapshot.analysisSnapshotText = "M5_EA_ANALYSIS_V1";
        this.appendAnalysisSnapshot(fromSnapshot.analysisSnapshotText, "SOURCE", fromElliotAll);
        fromSnapshot.reasonCode = "NOT_EVALUATED";

        return true;
    }

    /**
     * 保存済み回数を復元し、既存のJudge・加算・初回Entryを1回実行する。
     * Judge不成立も正常終了とし、補正生成失敗時には回数を消費しない。
     */
    bool evaluate(ElliotAll *fromElliotAll, const int fromPreviousCount,
            M5EaStrategySnapshot &fromSnapshot,
            const int fromMinimumRankDifference = 4) {
        if (fromPreviousCount < 0 || fromPreviousCount >= INT_MAX) {
            fromSnapshot.reasonCode = "SIGNAL_COUNT_INVALID";
            return false;
        }

        if (fromMinimumRankDifference < 1 || fromMinimumRankDifference > 7) {
            fromSnapshot.reasonCode = "RANK_DIFFERENCE_INVALID";

            return false;
        }

        if (!this.isAnalysisAvailable(fromElliotAll)
                || fromSnapshot.signalReferenceTime <= 0
                || fromSnapshot.reasonCode != "NOT_EVALUATED") {
            fromSnapshot.reasonCode = "ANALYSIS_UNAVAILABLE";
            return false;
        }

        ZigZagPoint *pivot = fromElliotAll.elliotCurrent.getLatestPoint2();
        if (pivot == NULL || pivot.barTime != fromSnapshot.signalReferenceTime
                || pivot.rate != fromSnapshot.signalReferencePrice
                || pivot.isPeak != fromSnapshot.signalReferenceIsHigh
                || fromElliotAll.elliotCurrent.isBuy != fromSnapshot.isBuy) {
            fromSnapshot.reasonCode = "ANALYSIS_SNAPSHOT_CHANGED";
            return false;
        }

        MarketContext context = fromElliotAll.marketContext;
        SignalCount signalCount(context);
        if (!signalCount.restoreCount(fromSnapshot.signalReferenceTime,
                fromSnapshot.isBuy, fromPreviousCount)) {
            fromSnapshot.reasonCode = "SIGNAL_COUNT_RESTORE_FAILED";
            return false;
        }

        ExpertAdvisorMtf3In3Config config;
        Mtf3In3M5Policy::apply(config, false, fromMinimumRankDifference);
        ExpertAdvisorMTF_3in3 *strategy = ExpertAdvisorMtf3In3Factory::create(context, config);
        if (strategy == NULL) {
            fromSnapshot.reasonCode = "STRATEGY_UNAVAILABLE";
            return false;
        }

        strategy.analyze(fromElliotAll, GetPointer(signalCount), 1);

        fromSnapshot.alertResult = strategy.getAlertResult();
        fromSnapshot.correctionTimeFrame = strategy.getCorrectionTimeFrame();
        string judgmentRejectReason = strategy.getJudgmentAnalysisRejectReason();
        ElliotAll *judgment = strategy.getJudgmentElliotAll();
        fromSnapshot.isJudgmentAnalysisAvailable = this.isAnalysisAvailable(judgment);
        if (fromSnapshot.isJudgmentAnalysisAvailable) {
            ZigZagPoint *selectedPivot = judgment.elliotCurrent.getLatestPoint2();
            if (selectedPivot != NULL) {
                fromSnapshot.initialStopLossPivotTime = selectedPivot.barTime;
                fromSnapshot.initialStopLossPivotPrice = selectedPivot.rate;
                fromSnapshot.initialStopLossPivotIsHigh = selectedPivot.isPeak;
            }
        }

        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "M5_D1_TO_M5_POLICY", "1");
#ifdef MSTNG_M5_D1_RELAXED_COMPARISON
        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "D1_DIRECTION_REQUIRED", "0");
#endif
        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "MINIMUM_RANK_DIFFERENCE",
            IntegerToString(fromMinimumRankDifference));
        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "CORRECTION_TIME_FRAME",
            EnumToString(fromSnapshot.correctionTimeFrame));
        this.appendAnalysisSnapshot(fromSnapshot.analysisSnapshotText, "SELECTED", judgment);
        this.appendCurrencyStrengthSnapshot(fromSnapshot.analysisSnapshotText, fromElliotAll);

        delete strategy;

        fromSnapshot.isJudge = fromSnapshot.alertResult.isJudge;
        fromSnapshot.signalCount = fromSnapshot.alertResult.signalCount;
        fromSnapshot.isEntryEvaluated = fromSnapshot.alertResult.isEntryEvaluated;
        fromSnapshot.isStrategyEntry = fromSnapshot.alertResult.isEntry;
        fromSnapshot.isSignalConsumed = fromSnapshot.isJudge && fromSnapshot.signalCount == 1;
        if (!fromSnapshot.isJudgmentAnalysisAvailable) {
            fromSnapshot.reasonCode = "JUDGMENT_ANALYSIS_UNAVAILABLE";
            if (judgmentRejectReason != "") {
                fromSnapshot.reasonCode = judgmentRejectReason;
            }
        } else if (!fromSnapshot.isJudge) {
            fromSnapshot.reasonCode = "JUDGE_REJECTED";
        } else if (fromSnapshot.signalCount > 1) {
            fromSnapshot.reasonCode = "SIGNAL_ALREADY_CONSUMED";
        } else if (!fromSnapshot.isStrategyEntry) {
            fromSnapshot.reasonCode = fromSnapshot.alertResult.entryResult;
        } else {
            fromSnapshot.reasonCode = "STRATEGY_ENTRY";
        }

        return true;
    }

private:
    /**
     * 今回の判定に使用した順位・増減・参照元を診断値として保存する。
     */
    void appendCurrencyStrengthSnapshot(string &fromText, ElliotAll *fromElliotAll) {
        CurrencyStrengthExecutionInfo strength = fromElliotAll.currencyStrengthExecutionInfo;
        EaTextUtil::appendField(fromText, "STRENGTH_ENABLED",
            IntegerToString((int)fromElliotAll.isCurrencyStrengthEntryFilterEnabled));
        EaTextUtil::appendField(fromText, "STRENGTH_STATUS", IntegerToString((int)strength.status));
        EaTextUtil::appendField(fromText, "STRENGTH_TARGET", IntegerToString(strength.targetM5BarTime));
        EaTextUtil::appendField(fromText, "STRENGTH_SOURCE", strength.sourceMode);
        EaTextUtil::appendField(fromText, "STRENGTH_FILE", strength.sourceFileName);
        EaTextUtil::appendField(fromText, "STRENGTH_VERSION", strength.calculationVersion);
        EaTextUtil::appendField(fromText, "STRENGTH_RUN", IntegerToString(strength.pairRankInfo.runId));
        EaTextUtil::appendField(fromText, "STRENGTH_LONG_MEDIUM_BASE",
            IntegerToString(strength.pairRankInfo.baseLongMediumTermAverageRank));
        EaTextUtil::appendField(fromText, "STRENGTH_LONG_MEDIUM_QUOTE",
            IntegerToString(strength.pairRankInfo.quoteLongMediumTermAverageRank));
        EaTextUtil::appendField(fromText, "STRENGTH_MEDIUM_SHORT_BASE",
            IntegerToString(strength.pairRankInfo.baseMediumShortTermAverageRank));
        EaTextUtil::appendField(fromText, "STRENGTH_MEDIUM_SHORT_QUOTE",
            IntegerToString(strength.pairRankInfo.quoteMediumShortTermAverageRank));
        EaTextUtil::appendField(fromText, "STRENGTH_LONG_MEDIUM_GAP_ENABLED",
            IntegerToString((int)strength.longMediumGapDirectionFilterEnabled));
        EaTextUtil::appendField(fromText, "STRENGTH_LONG_MEDIUM_GAP_DIRECTION",
            IntegerToString(strength.longMediumGapDirection.direction));
        EaTextUtil::appendField(fromText, "STRENGTH_LONG_MEDIUM_GAP_CHANGE_TIME",
            IntegerToString(strength.longMediumGapDirection.directionChangedAt));
        EaTextUtil::appendField(fromText, "STRENGTH_LONG_MEDIUM_GAP_BEFORE",
            IntegerToString(strength.longMediumGapDirection.lastChangeBeforeGap));
        EaTextUtil::appendField(fromText, "STRENGTH_LONG_MEDIUM_GAP_AFTER",
            IntegerToString(strength.longMediumGapDirection.lastChangeAfterGap));
    }

    /**
     * 共通戦略の情報生成が参照するMN1からM5までの最新点を確認する。
     */
    bool isAnalysisAvailable(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL || !fromElliotAll.isAnalysisSucceeded
                || fromElliotAll.marketContext.timeFrame != PERIOD_M5
                || fromElliotAll.elliotCurrent == NULL
                || fromElliotAll.elliotCurrent != fromElliotAll.getElliot(PERIOD_M5)) {
            return false;
        }

        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
        };
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = fromElliotAll.getElliot(timeFrames[i]);
            if (elliot == NULL || elliot.getLatestPoint() == NULL) {
                return false;
            }
        }

        return true;
    }

    /**
     * 採用前後の実値を保存する。判定条件はここで再実装しない。
     */
    void appendAnalysisSnapshot(string &fromText, const string fromPrefix, ElliotAll *fromElliotAll) {
        EaTextUtil::appendField(fromText, fromPrefix + "_AVAILABLE",
            IntegerToString((int)this.isAnalysisAvailable(fromElliotAll)));
        if (!this.isAnalysisAvailable(fromElliotAll)) {
            return;
        }

        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
        };
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = fromElliotAll.getElliot(timeFrames[i]);
            ZigZagPoint *latest = elliot.getLatestPoint();
            string prefix = fromPrefix + "_" + EnumToString(timeFrames[i]);
            EaTextUtil::appendField(fromText, prefix + "_DIRECTION", this.direction(elliot.isBuy));
            EaTextUtil::appendField(fromText, prefix + "_WAVE_DIRECTION", this.direction(elliot.isUptrend()));
            EaTextUtil::appendField(fromText, prefix + "_EMA200", elliot.oscillator.ema200.getBuySellLabel());
            EaTextUtil::appendField(fromText, prefix + "_GMMA_TREND", IntegerToString(elliot.oscillator.gmmaTrendCount));
            EaTextUtil::appendField(fromText, prefix + "_GMMA_CROSS", IntegerToString(elliot.oscillator.gmmaCrossCount));
            EaTextUtil::appendField(fromText, prefix + "_ELLIOT_LABEL", elliot.getLatestPointElliotLabel());
            EaTextUtil::appendField(fromText, prefix + "_ORIGINAL_ELLIOT_INDEX", IntegerToString(latest.orgElliotIndex));
            EaTextUtil::appendField(fromText, prefix + "_ORIGINAL_ELLIOT_LABEL", latest.orgElliotLabel);
            EaTextUtil::appendField(fromText, prefix + "_FE_PERCENT", this.number(latest.fibonacciExpansionPercent));
            EaTextUtil::appendField(fromText, prefix + "_LATEST_TIME", IntegerToString(latest.barTime));
            EaTextUtil::appendField(fromText, prefix + "_LATEST_ADDED", IntegerToString((int)latest.isAddedPoint));

            ZigZagPoint *pivot = elliot.getLatestPoint2();
            if (pivot != NULL) {
                EaTextUtil::appendField(fromText, prefix + "_PIVOT_TIME", IntegerToString(pivot.barTime));
                EaTextUtil::appendField(fromText, prefix + "_PIVOT_PRICE", this.number(pivot.rate));
                EaTextUtil::appendField(fromText, prefix + "_PIVOT_HIGH", IntegerToString((int)pivot.isPeak));
            }
        }
    }

    /**
     * 数値未取得を有限値と区別して記録する。
     */
    string number(const double fromValue) {
        if (!MathIsValidNumber(fromValue) || fromValue == EMPTY_VALUE) {
            return "UNAVAILABLE";
        }

        return DoubleToString(fromValue, 8);
    }

    /**
     * 方向を監査用文字列へ変換する。
     */
    string direction(const bool fromIsBuy) {
        if (fromIsBuy) {
            return "BUY";
        }

        return "SELL";
    }
};

#endif
