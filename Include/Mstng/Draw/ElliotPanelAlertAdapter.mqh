#ifndef MSTNG_DRAW_ELLIOT_PANEL_ALERT_ADAPTER_MQH
#define MSTNG_DRAW_ELLIOT_PANEL_ALERT_ADAPTER_MQH

#include <Mstng\Draw\ElliotPanelData.mqh>
#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryData.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * アラートの保存分析を共通パネルへ変換する。
 * 現在値の再計算や別DBからの補完を行わず、補正前後と欠損状態を保持する。
 */
class ElliotPanelAlertAdapter {
public:
    /**
     * 表示する分析だけを選び、最終判定と通貨強弱は保存アラートの値を維持する。
     */
    static void build(const ZigZagElliotAlertHistorySnapshot &fromSnapshot,
            const bool fromOriginal, const int fromDigits, ElliotPanelData &fromData) {
        fromData.clear();
        fromData.symbolName = fromSnapshot.alert.symbolName;
        fromData.digits = fromDigits;
        fromData.savedTime = fromSnapshot.alert.currentBarTime;
        fromData.allowLive = false;
        fromData.title = "保存アラート / " + fromData.symbolName;
        fromData.headerTime = "SRV " + timeText(fromSnapshot.alert.serverTime);
        if (fromSnapshot.alert.jstTime > 0) {
            fromData.headerTime = "JST " + timeText(fromSnapshot.alert.jstTime);
        }

        fromData.headerTime += " / " + fromSnapshot.alert.side + " / " + fromSnapshot.alert.entryResult;
        string analysis = "元分析（参考）";
        if (fromSnapshot.correctionStatus == "APPLIED") {
            analysis = "補正後（採用）";
            if (fromOriginal) {
                analysis = "補正前（比較用）";
            }
        } else if (fromSnapshot.correctionStatus == "NONE") {
            analysis = "元分析（採用）";
        }

        fromData.metadata = analysis + " / Run " + IntegerToString(fromSnapshot.alert.runId)
            + " / Alert " + IntegerToString(fromSnapshot.alert.id) + " / " + fromSnapshot.run.sourceMode
            + " / Count " + IntegerToString(fromSnapshot.alert.signalCount) + " / 採用SL候補 ";
        if (fromSnapshot.originalAvailable
                && (fromSnapshot.correctionStatus == "APPLIED" || fromSnapshot.correctionStatus == "NONE")
                && fromSnapshot.correction.isSelectedStopLossAvailable == 1) {
            fromData.metadata += DoubleToString(fromSnapshot.correction.selectedStopLoss, fromDigits)
                + " / " + DoubleToString(fromSnapshot.correction.selectedRiskPips, 1) + " pips";
        } else {
            fromData.metadata += "—";
        }

        fromData.hint = "前・次：同じRunの検索結果 / 行選択で詳細 / 保存値のみ（実SLではありません）";
        fillStrength(fromSnapshot, fromData.strength);
        if (!fromSnapshot.originalAvailable) {
            fromData.status = fromSnapshot.originalReason;
            return;
        }

        if (fromSnapshot.correctionStatus == "INCOMPLETE" || fromSnapshot.correctionStatus == "UNRECORDED") {
            fromData.status = fromSnapshot.correctionReason;
        }

        if (!fromOriginal && fromSnapshot.correctionStatus == "APPLIED") {
            fillFrames(fromSnapshot.correctedTimeFrames, fromSnapshot.correctedPoints, fromData);
        } else {
            fillFrames(fromSnapshot.originalTimeFrames, fromSnapshot.originalPoints, fromData);
        }
    }

private:
    /**
     * 保存された日時だけをチャート共通書式で表示する。
     */
    static string timeText(const datetime fromTime) {
        if (fromTime <= 0) {
            return "未記録";
        }

        return TimeUtil::formatYyyymmddhhmiss(fromTime);
    }

    /**
     * 保存された時間足と、その分析に属する一意の最新ポイントを対応させる。
     */
    static void fillFrames(const ZigZagElliotAlertTimeFrameEntity &fromFrames[],
            const ZigZagElliotAlertPointEntity &fromPoints[], ElliotPanelData &fromData) {
        fromData.rowCount = MathMin(8, ArraySize(fromFrames));
        for (int i = 0; i < fromData.rowCount; i++) {
            fillFrame(fromFrames[i], fromData.frames[i]);
            int latestIndex = -1;
            int latestCount = 0;
            for (int j = 0; j < ArraySize(fromPoints); j++) {
                if (fromPoints[j].alertTimeFrameId == fromFrames[i].id
                        && fromPoints[j].timeFrame == fromFrames[i].timeFrame && fromPoints[j].isLatest == 1) {
                    latestIndex = j;
                    latestCount++;
                }
            }

            if (latestCount == 1) {
                fillPoint(fromPoints[latestIndex], fromData.frames[i]);
            }
        }
    }

    /**
     * 時間足別の保存指標をコピーする。保存されていない追加情報は既定の未知状態を保つ。
     */
    static void fillFrame(const ZigZagElliotAlertTimeFrameEntity &fromSource, ElliotPanelFrame &fromTarget) {
        fromTarget.timeFrame = fromSource.timeFrame;
        fromTarget.row.timeFrameLabel = fromSource.timeFrameText;
        fromTarget.row.hasData = true;
        fromTarget.row.mainWave = fromSource.latestElliotLabel;
        fromTarget.row.subWave = fromSource.latestSubElliotLabel;
        fromTarget.row.isBuy = fromSource.isBuy;
        fromTarget.row.isUptrend = fromSource.isWaveUptrend;
        fromTarget.row.isConfirmed = fromSource.isWaveConfirmed;
        if (fromSource.timeFrame != PERIOD_MN1) {
            fromTarget.row.isEma200Buy = fromSource.isEma200Buy;
            fromTarget.row.isEma200Sell = fromSource.isEma200Sell;
        }

        fromTarget.row.isPriceMovementValid = fromSource.isPriceMovementValid;
        fromTarget.row.priceMovementLevel = fromSource.priceMovementLevel;
        fromTarget.row.priceMovementActivityRatio = fromSource.priceMovementActivityRatio;
        fromTarget.row.hasPriceMovementActivityRatio = fromSource.isPriceMovementValid == 1;
        fromTarget.row.gmmaTrendCount = fromSource.gmmaTrendCount;
        fromTarget.row.hasGmmaTrendCount = true;
        fromTarget.row.gmmaCrossCount = fromSource.gmmaCrossCount;
        fromTarget.row.hasGmmaCrossCount = true;
        fromTarget.extraCount = 4;
        string names[] = {"Oscillator", "Stoch短期", "Stoch中期", "Stoch長期"};
        int counts[] = {fromSource.oscillatorCount, fromSource.stochasticShortCount,
            fromSource.stochasticMiddleCount, fromSource.stochasticLongCount};
        for (int i = 0; i < 4; i++) {
            fromTarget.extraLabels[i] = names[i];
            fromTarget.extraValues[i] = StringFormat("%+d", counts[i]);
            fromTarget.extraColors[i] = clrWhiteSmoke;
        }
    }

    /**
     * 最新ポイントの取得可否フラグを維持し、F・FE・元波動を復元する。
     */
    static void fillPoint(const ZigZagElliotAlertPointEntity &fromSource, ElliotPanelFrame &fromTarget) {
        fromTarget.pointTime = fromSource.barTime;
        fromTarget.row.isAdded = fromSource.isAddedPoint;
        if (fromSource.isOriginalElliotAvailable == 1) {
            fromTarget.row.originalWave = fromSource.orgElliotLabel;
            fromTarget.row.originalWaveIndex = fromSource.orgElliotIndex;
        }

        fromTarget.row.pointRate = fromSource.rate;
        fromTarget.row.hasPointRate = true;
        fromTarget.row.pointPipsDiff = fromSource.pipsDiff;
        fromTarget.row.hasPointPipsDiff = true;
        fromTarget.row.pointFibonacciPercent = fromSource.fibonacciPercent;
        fromTarget.row.hasPointFibonacciPercent = fromSource.isFibonacciAvailable == 1;
        fromTarget.row.pointFibonacciExpansionPercent = fromSource.fibonacciExpansionPercent;
        fromTarget.row.hasPointFibonacciExpansionPercent = fromSource.isFibonacciExpansionAvailable == 1;
    }

    /**
     * アラート時の通貨強弱を復元する。前M5との差は未保存のため比較しない。
     */
    static void fillStrength(const ZigZagElliotAlertHistorySnapshot &fromSnapshot, ElliotPanelStrength &fromTarget) {
        fromTarget.enabled = true;
        fromTarget.title = "アラート時の通貨強弱［保存値］";
        fromTarget.status = fromSnapshot.strengthState;
        if (fromSnapshot.strengthState != "取得済み") {
            return;
        }

        fromTarget.title += " / " + fromSnapshot.alert.currencyStrengthSourceMode
            + " / 参照 SRV " + timeText(fromSnapshot.alert.currencyStrengthM5BarTime);
        fromTarget.tooltip = "アラート保存時の順位です。現在値や別DBの履歴で補完しません。"
            + "\n計算: " + fromSnapshot.alert.currencyStrengthCalculationVersion
            + " / 強弱Run " + IntegerToString(fromSnapshot.alert.currencyStrengthRunId)
            + "\n対象 SRV " + timeText(fromSnapshot.alert.currencyStrengthTargetM5BarTime)
            + "\n順位差＝決済通貨順位－基軸通貨順位。前M5比は未保存。";
        fromTarget.baseCurrency = fromSnapshot.alert.baseCurrency;
        fromTarget.quoteCurrency = fromSnapshot.alert.quoteCurrency;
        fromTarget.longMedium.valid = true;
        fromTarget.longMedium.baseRank = fromSnapshot.alert.baseLongMediumRank;
        fromTarget.longMedium.quoteRank = fromSnapshot.alert.quoteLongMediumRank;
        fromTarget.longMedium.gap = fromSnapshot.alert.longMediumRankDifference;
        fromTarget.mediumShort.valid = true;
        fromTarget.mediumShort.baseRank = fromSnapshot.alert.baseMediumShortRank;
        fromTarget.mediumShort.quoteRank = fromSnapshot.alert.quoteMediumShortRank;
        fromTarget.mediumShort.gap = fromSnapshot.alert.mediumShortRankDifference;
    }
};

#endif
