#ifndef MSTNGM15EA_STRATEGY_DECISION_MQH
#define MSTNGM15EA_STRATEGY_DECISION_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>
#include <Mstng\ExpertAdvisor\Runtime\EaTextUtil.mqh>
#include <MstngM15Ea\Strategy\M15EaStrategySnapshot.mqh>

/**
 * 通常版ZigZagElliotのM15判定に保存済み回数を接続する。
 * 元分析の回数キーを固定し、採用分析のSL・診断値を所有権解放前にコピーする。
 */
class M15EaStrategyDecision {
public:
    /**
     * Judgeを実行せず、元M15のシグナル識別キーと価格を取り出す。
     */
    bool prepare(ElliotAll *fromElliotAll, const datetime fromBarTime,
            M15EaStrategySnapshot &fromSnapshot) {
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
        fromSnapshot.analysisSnapshotText = "M15_EA_ANALYSIS_V1";
        this.appendAnalysisSnapshot(fromSnapshot.analysisSnapshotText, "SOURCE", fromElliotAll);
        fromSnapshot.reasonCode = "NOT_EVALUATED";
        return true;
    }

    /**
     * 保存済み回数を復元し、既存のJudge・加算・初回Entryを1回実行する。
     * Judge不成立も正常終了とし、補正生成失敗時には回数を消費しない。
     */
    bool evaluate(ElliotAll *fromElliotAll, const int fromPreviousCount,
            M15EaStrategySnapshot &fromSnapshot,
            const bool fromDirectionCorrectionEnabled = true,
            const double fromH4MaxFibonacciExpansionPercent = 161.8,
            const double fromH1MaxFibonacciExpansionPercent = 161.8) {
        if (fromPreviousCount < 0 || fromPreviousCount >= INT_MAX) {
            fromSnapshot.reasonCode = "SIGNAL_COUNT_INVALID";
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
        ExpertAdvisorMTF_3in3 *strategy = ExpertAdvisorMtf3In3Factory::create(
            context, false, Mtf3In3H1Policy::getW1ConfirmationMode(),
            Mtf3In3H1Policy::getDirectionAlignmentMode(),
            Mtf3In3H1Policy::getEma200ConfirmationMode(),
            fromDirectionCorrectionEnabled,
            fromH4MaxFibonacciExpansionPercent, fromH1MaxFibonacciExpansionPercent
        );
        if (strategy == NULL) {
            fromSnapshot.reasonCode = "STRATEGY_UNAVAILABLE";
            return false;
        }
        strategy.analyze(fromElliotAll, GetPointer(signalCount), 1);
        fromSnapshot.alertResult = strategy.getAlertResult();
        fromSnapshot.correctionTimeFrame = strategy.getCorrectionTimeFrame();
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
        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "DIRECTION_CORRECTION_ENABLED",
            IntegerToString((int)fromDirectionCorrectionEnabled));
        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "H4_MAX_FE_PERCENT",
            this.number(fromH4MaxFibonacciExpansionPercent));
        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "H1_MAX_FE_PERCENT",
            this.number(fromH1MaxFibonacciExpansionPercent));
        EaTextUtil::appendField(fromSnapshot.analysisSnapshotText, "CORRECTION_TIME_FRAME",
            EnumToString(fromSnapshot.correctionTimeFrame));
        this.appendAnalysisSnapshot(fromSnapshot.analysisSnapshotText, "SELECTED", judgment);
        delete strategy;

        fromSnapshot.isJudge = fromSnapshot.alertResult.isJudge;
        fromSnapshot.signalCount = fromSnapshot.alertResult.signalCount;
        fromSnapshot.isEntryEvaluated = fromSnapshot.alertResult.isEntryEvaluated;
        fromSnapshot.isStrategyEntry = fromSnapshot.alertResult.isEntry;
        fromSnapshot.isSignalConsumed = fromSnapshot.isJudge && fromSnapshot.signalCount == 1;
        if (!fromSnapshot.isJudgmentAnalysisAvailable) {
            fromSnapshot.reasonCode = "JUDGMENT_ANALYSIS_UNAVAILABLE";
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
     * 共通戦略の情報生成が参照するMN1からM15までの最新点を確認する。
     */
    bool isAnalysisAvailable(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL || !fromElliotAll.isAnalysisSucceeded
                || fromElliotAll.marketContext.timeFrame != PERIOD_M15
                || fromElliotAll.elliotCurrent == NULL
                || fromElliotAll.elliotCurrent != fromElliotAll.getElliot(PERIOD_M15)) {
            return false;
        }
        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
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
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
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
