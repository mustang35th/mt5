#ifndef MSTNGH1EA_STRATEGY_DECISION_MQH
#define MSTNGH1EA_STRATEGY_DECISION_MQH

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentDecision.mqh>
#include <Mstng\ExpertAdvisor\H1EntryWaveDecision.mqh>
#include <MstngH1Ea\Strategy\H1EaStrategySnapshot.mqh>

/**
 * 通常版H1初期設定の戦略を、DBから復元した回数で評価する。
 * 分析データを変更せず、発注、通知、描画、CSV保存は行わない。
 */
class H1EaStrategyDecision {
public:
    /**
     * Judgeを実行せず分析値とシグナル識別キーを取り出す。
     *
     * @param fromElliotAll MN1からH1までの分析結果。
     * @param fromH1BarTime 評価対象H1バー。
     * @param fromSnapshot スナップショットの格納先。
     * @return 必要な分析値とキーを取得できた場合true。
     */
    bool prepare(
        ElliotAll *fromElliotAll,
        const datetime fromH1BarTime,
        H1EaStrategySnapshot &fromSnapshot
    ) {
        fromSnapshot.reset();
        fromSnapshot.h1BarTime = fromH1BarTime;
        fromSnapshot.evaluatedTime = TimeCurrent();
        fromSnapshot.reasonCode = "ANALYSIS_UNAVAILABLE";

        if (fromElliotAll == NULL || !fromElliotAll.isAnalysisSucceeded
                || fromH1BarTime <= 0
                || fromElliotAll.marketContext.timeFrame != PERIOD_H1) {
            return false;
        }

        Elliot *elliotMn1 = fromElliotAll.getElliot(PERIOD_MN1);
        Elliot *elliotW1 = fromElliotAll.getElliot(PERIOD_W1);
        Elliot *elliotD1 = fromElliotAll.getElliot(PERIOD_D1);
        Elliot *elliotH4 = fromElliotAll.getElliot(PERIOD_H4);
        Elliot *elliotH1 = fromElliotAll.getElliot(PERIOD_H1);

        if (elliotMn1 == NULL || elliotW1 == NULL || elliotD1 == NULL
                || elliotH4 == NULL || elliotH1 == NULL
                || fromElliotAll.elliotCurrent != elliotH1) {
            return false;
        }

        // 基底戦略の情報生成は全時間足の最新点を参照する。
        if (elliotMn1.getLatestPoint() == NULL
                || elliotW1.getLatestPoint() == NULL
                || elliotD1.getLatestPoint() == NULL
                || elliotH4.getLatestPoint() == NULL) {
            return false;
        }

        ZigZagPoint *pivot = elliotH1.getLatestPoint2();
        ZigZagPoint *latest = elliotH1.getLatestPoint();

        if (pivot == NULL || latest == NULL || pivot.barTime <= 0) {
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

        fromSnapshot.isBuy = elliotH1.isBuy;
        fromSnapshot.signalSide = this.direction(elliotH1.isBuy);
        fromSnapshot.signalReferenceTime = pivot.barTime;
        fromSnapshot.signalReferencePrice = pivot.rate;
        fromSnapshot.signalReferenceIsHigh = pivot.isPeak;
        fromSnapshot.spreadPips = fromElliotAll.todayRate.spread;
        fromSnapshot.bid = fromElliotAll.todayRate.bid;
        fromSnapshot.ask = fromElliotAll.todayRate.ask;
        fromSnapshot.mn1Direction = this.direction(elliotMn1.isBuy);
        fromSnapshot.w1Direction = this.direction(elliotW1.isBuy);
        fromSnapshot.d1Direction = this.direction(elliotD1.isBuy);
        fromSnapshot.h4Direction = this.direction(elliotH4.isBuy);
        fromSnapshot.h1Direction = this.direction(elliotH1.isBuy);
        fromSnapshot.w1Ema200Direction = elliotW1.oscillator.ema200.getBuySellLabel();
        fromSnapshot.h4Ema200Direction = elliotH4.oscillator.ema200.getBuySellLabel();
        fromSnapshot.h1Ema200Direction = elliotH1.oscillator.ema200.getBuySellLabel();
        fromSnapshot.h1GmmaTrendCount = elliotH1.oscillator.gmmaTrendCount;
        fromSnapshot.h1GmmaCrossCount = elliotH1.oscillator.gmmaCrossCount;
        fromSnapshot.h1ElliotLabel = elliotH1.getLatestPointElliotLabel();
        fromSnapshot.h4ElliotLabel = elliotH4.getLatestPointElliotLabel();
        fromSnapshot.h1WaveDirection = this.direction(elliotH1.isUptrend());

        // 診断値だけを先に取り出す。Judge回数と詳細Entry実行順は変更しない。
        H1EntryWaveDecision waveDecision;
        H1EntryWaveResult waveResult;
        fromSnapshot.isH1WaveAccepted = waveDecision.evaluate(
            elliotH1, PERIOD_H1, "ELLIOT_LABEL_REJECTED",
            "ELLIOT_LABEL_REJECTED", "H1_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
            waveResult
        );
        fromSnapshot.isH4WaveAccepted = waveDecision.evaluate(
            elliotH4, PERIOD_H4, "H4_ELLIOT_UNAVAILABLE",
            "H4_ELLIOT_LABEL_REJECTED", "H4_WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
            waveResult
        );
        H1DirectionAlignmentDecision alignmentDecision;
        H1DirectionAlignmentResult alignmentResult;
        fromSnapshot.isH1DirectionAlignmentPassed = alignmentDecision.evaluate(
            H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
            fromElliotAll, alignmentResult
        );
        fromSnapshot.analysisSnapshotText = StringFormat(
            "MN1=%s|W1=%s|D1=%s|H4=%s|H1=%s|W1_EMA200=%s|H4_EMA200=%s|H1_EMA200=%s|H1_GT=%d|H1_GC=%d|H1_WAVE=%s|H4_WAVE=%s|DIRECTION_STATE=%s",
            fromSnapshot.mn1Direction, fromSnapshot.w1Direction,
            fromSnapshot.d1Direction, fromSnapshot.h4Direction,
            fromSnapshot.h1Direction, fromSnapshot.w1Ema200Direction,
            fromSnapshot.h4Ema200Direction, fromSnapshot.h1Ema200Direction,
            fromSnapshot.h1GmmaTrendCount, fromSnapshot.h1GmmaCrossCount,
            fromSnapshot.h1ElliotLabel, fromSnapshot.h4ElliotLabel,
            alignmentResult.state
        );
        fromSnapshot.reasonCode = "NOT_EVALUATED";

        return true;
    }

    /**
     * 保存済み回数を復元し、既存のJudge→加算→初回Entryを1回実行する。
     *
     * @param fromElliotAll prepareで使用した分析結果。
     * @param fromPreviousCount このキーの保存済みJudge回数。
     * @param fromSnapshot prepareで作成したスナップショット。
     * @return 戦略評価に成功した場合true。Judge NGも成功。
     */
    bool evaluate(
        ElliotAll *fromElliotAll,
        const int fromPreviousCount,
        H1EaStrategySnapshot &fromSnapshot
    ) {
        if (fromPreviousCount < 0 || fromPreviousCount >= INT_MAX) {
            fromSnapshot.reasonCode = "SIGNAL_COUNT_INVALID";

            return false;
        }

        if (fromElliotAll == NULL || !fromElliotAll.isAnalysisSucceeded
                || fromElliotAll.elliotCurrent == NULL
                || fromSnapshot.signalReferenceTime <= 0
                || fromSnapshot.reasonCode != "NOT_EVALUATED") {
            fromSnapshot.reasonCode = "ANALYSIS_UNAVAILABLE";

            return false;
        }

        ZigZagPoint *pivot = fromElliotAll.elliotCurrent.getLatestPoint2();

        if (pivot == NULL || pivot.barTime != fromSnapshot.signalReferenceTime
                || fromElliotAll.elliotCurrent.isBuy != fromSnapshot.isBuy) {
            fromSnapshot.reasonCode = "ANALYSIS_SNAPSHOT_CHANGED";

            return false;
        }

        MarketContext context = fromElliotAll.marketContext;
        SignalCount signalCount(context);

        if (!signalCount.restoreCount(
                fromSnapshot.signalReferenceTime, fromSnapshot.isBuy,
                fromPreviousCount)) {
            fromSnapshot.reasonCode = "SIGNAL_COUNT_RESTORE_FAILED";

            return false;
        }

        ExpertAdvisorMTF_3in3 *strategy = ExpertAdvisorMtf3In3Factory::create(
            context, false, H1_W1_CONFIRMATION_OBSERVE_ONLY,
            H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
            H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED
        );

        if (strategy == NULL) {
            fromSnapshot.reasonCode = "STRATEGY_UNAVAILABLE";

            return false;
        }

        strategy.analyze(fromElliotAll, GetPointer(signalCount), 1);
        fromSnapshot.alertResult = strategy.getAlertResult();
        delete strategy;
        fromSnapshot.isJudge = fromSnapshot.alertResult.isJudge;
        fromSnapshot.signalCount = fromSnapshot.alertResult.signalCount;
        fromSnapshot.isEntryEvaluated = fromSnapshot.alertResult.isEntryEvaluated;
        fromSnapshot.isStrategyEntry = fromSnapshot.alertResult.isEntry;
        fromSnapshot.isSignalConsumed = fromSnapshot.isJudge
            && fromSnapshot.signalCount == 1;

        if (!fromSnapshot.isJudge) {
            fromSnapshot.reasonCode = this.getJudgeRejectReason(fromSnapshot);
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
     * 方向フラグを永続化用文字列へ変換する。
     */
    string direction(const bool fromIsBuy) {
        if (fromIsBuy) {
            return "BUY";
        }

        return "SELL";
    }

    /**
     * 共通Judgeの評価順に沿って診断用のNG理由を選ぶ。
     */
    string getJudgeRejectReason(H1EaStrategySnapshot &fromSnapshot) {
        if (fromSnapshot.spreadPips > 5.0) {
            return "SPREAD_TOO_WIDE";
        }

        if (fromSnapshot.h1Direction != fromSnapshot.h1WaveDirection) {
            return "H1_WAVE_DIRECTION_MISMATCH";
        }

        if (!fromSnapshot.isH1DirectionAlignmentPassed) {
            return "DIRECTION_ALIGNMENT_REJECTED";
        }

        if ((fromSnapshot.isBuy && fromSnapshot.h1GmmaTrendCount < 2)
                || (!fromSnapshot.isBuy && fromSnapshot.h1GmmaTrendCount > -2)) {
            return "H1_GMMA_TREND_REJECTED";
        }

        if ((fromSnapshot.isBuy && fromSnapshot.h1GmmaCrossCount < 2)
                || (!fromSnapshot.isBuy && fromSnapshot.h1GmmaCrossCount > -2)) {
            return "H1_GMMA_CROSS_REJECTED";
        }

        if (fromSnapshot.h1Ema200Direction != fromSnapshot.signalSide
                || fromSnapshot.h4Ema200Direction != fromSnapshot.signalSide) {
            return "EMA200_DIRECTION_REJECTED";
        }

        return "JUDGE_REJECTED";
    }
};

#endif
