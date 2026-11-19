#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_DIRECTION_SNAPSHOT_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_DIRECTION_SNAPSHOT_MQH

#include <Mstng\ExpertAdvisor\Mtf3In3HigherTimeFrameDecision.mqh>

/**
 * 1時間足の補正前BUY・SELLと、採用分析の比較用方向を値だけで保持する。
 * 波動の上昇・下降方向や、最終エントリー成立とは区別する。
 */
struct ZigZagElliotMonitorDirectionInfo {
    /** 方向を取得する対象時間足。 */
    ENUM_TIMEFRAMES timeFrame;

    /** 元分析の方向が有効な場合true。 */
    bool available;

    /** 元分析がBUY方向の場合true。availableがtrueの場合だけ使用する。 */
    bool isBuy;

    /** 採用分析の方向が有効な場合true。 */
    bool adoptedAvailable;

    /** 採用分析がBUY方向の場合true。adoptedAvailableがtrueの場合だけ使用する。 */
    bool adoptedIsBuy;

    /** 採用された明示補正の時間足で、補正前後の方向が有効な場合true。 */
    bool corrected;
};

/**
 * 安定したM1確認で取得したD1からM1までの補正前方向を表示用に保存する。
 * 採用分析がない場合も元方向を保持し、分析オブジェクトの寿命には依存しない。
 */
struct ZigZagElliotMonitorDirectionSnapshot {
    /** 有効な元分析から方向の確認を行った場合true。 */
    bool analyzed;

    /** 今回の確認対象M1開始サーバー時刻。 */
    datetime targetM1BarTime;

    /** D1・H4・H1・M15・M5・M1の順に保持する方向情報。 */
    ZigZagElliotMonitorDirectionInfo items[6];

    /**
     * 全時間足が未取得の状態で生成する。
     */
    ZigZagElliotMonitorDirectionSnapshot() {
        this.reset();
    }

    /**
     * 時間足の表示順を設定し、前回の方向と補正情報を破棄する。
     */
    void reset() {
        this.analyzed = false;
        this.targetM1BarTime = 0;
        ENUM_TIMEFRAMES timeFrames[6] = {
            PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1
        };
        for (int i = 0; i < 6; i++) {
            this.items[i].timeFrame = timeFrames[i];
            this.items[i].available = false;
            this.items[i].isBuy = false;
            this.items[i].adoptedAvailable = false;
            this.items[i].adoptedIsBuy = false;
            this.items[i].corrected = false;
        }
    }

    /**
     * 元分析の各時間足を個別に確認し、補正前方向と採用方向を保存する。
     * 安定性と準備完了を確認した後だけ呼び出し、追加分析や取得は行わない。
     *
     * @param fromOriginal 補正前の分析。NULL・未完了・対象不正の場合は未分析のまま保持する。
     * @param fromAdopted 戦略が採用した分析。NULLの場合も元方向は保存する。
     * @param fromTargetM1BarTime 今回の確認対象M1開始サーバー時刻。
     * @param fromCorrectionTimeFrame 採用分析で明示的に補正したH4・H1・M15。
     */
    void capture(ElliotAll *fromOriginal, ElliotAll *fromAdopted,
            const datetime fromTargetM1BarTime, const ENUM_TIMEFRAMES fromCorrectionTimeFrame) {
        this.reset();
        if (fromOriginal == NULL || !fromOriginal.isAnalysisSucceeded
                || fromOriginal.marketContext.timeFrame != PERIOD_M1
                || fromOriginal.marketContext.symbolName == ""
                || fromTargetM1BarTime <= 0 || fromTargetM1BarTime % 60 != 0) {
            return;
        }

        this.analyzed = true;
        this.targetM1BarTime = fromTargetM1BarTime;
        Mtf3In3HigherTimeFrameDecision decision;
        Elliot *originalM1 = fromOriginal.getElliot(PERIOD_M1);
        bool originalM1Valid = decision.isDirectionStateValid(originalM1, PERIOD_M1)
            && originalM1.marketContext.symbolName == fromOriginal.marketContext.symbolName;
        bool adoptedAnalysisAvailable = fromAdopted != NULL && fromAdopted.isAnalysisSucceeded
            && fromAdopted.marketContext.timeFrame == PERIOD_M1
            && fromAdopted.marketContext.symbolName == fromOriginal.marketContext.symbolName;

        for (int i = 0; i < 6; i++) {
            ENUM_TIMEFRAMES timeFrame = this.items[i].timeFrame;
            Elliot *original = fromOriginal.getElliot(timeFrame);
            if (!decision.isDirectionStateValid(original, timeFrame)
                    || original.marketContext.symbolName != fromOriginal.marketContext.symbolName) {
                continue;
            }

            this.items[i].available = true;
            this.items[i].isBuy = original.isBuy;
            if (!adoptedAnalysisAvailable) {
                continue;
            }

            Elliot *adopted = fromAdopted.getElliot(timeFrame);
            if (adopted == NULL || adopted.marketContext.symbolName != fromOriginal.marketContext.symbolName) {
                continue;
            }

            bool corrected = timeFrame == fromCorrectionTimeFrame
                && (timeFrame == PERIOD_H4 || timeFrame == PERIOD_H1 || timeFrame == PERIOD_M15);
            if (corrected) {
                if (!originalM1Valid
                        || !decision.isCorrectedDirectionStateValid(adopted, original, timeFrame, originalM1.isBuy)) {
                    continue;
                }
            } else if (!decision.isDirectionStateValid(adopted, timeFrame)) {
                continue;
            }

            this.items[i].adoptedAvailable = true;
            this.items[i].adoptedIsBuy = adopted.isBuy;
            this.items[i].corrected = corrected;
        }
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_DIRECTION_SNAPSHOT_MQH
