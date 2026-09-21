#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_LIVE_ALERT_TOOLTIP_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_LIVE_ALERT_TOOLTIP_MQH

#include <Mstng\Draw\DrawZigZagElliotAlertMarkers.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>

/**
 * 通常アラートの採用分析を、DB表示と同じツールチップへ変換する。
 * 判定時点の値だけを文字列として保持し、DB接続や相場の再分析は行わない。
 */
class DrawZigZagElliotLiveAlertTooltip {
public:
    /**
     * 描画済みの通常M5・H1ラベルへ判定時点の概要を付ける。
     *
     * @param fromObjectName 描画済みオブジェクト名。
     * @param fromSource 元分析。判定日時はここから取得する。
     * @param fromJudgment 全条件に採用した分析。補正時は補正後。
     * @param fromResult 最終エントリー判定結果。
     * @param fromCorrectionTimeFrame 補正対象足。補正なしはPERIOD_CURRENT。
     * @return 設定に成功した場合true。
     */
    static bool apply(const string fromObjectName, ElliotAll *fromSource,
            ElliotAll *fromJudgment, const Mtf3In3AlertResult &fromResult,
            const ENUM_TIMEFRAMES fromCorrectionTimeFrame) {
        if (fromSource == NULL || fromJudgment == NULL
                || !fromJudgment.isAnalysisSucceeded || !fromResult.isAlert
                || (fromSource.marketContext.timeFrame != PERIOD_M5
                    && fromSource.marketContext.timeFrame != PERIOD_H1)
                || ObjectFind(0, fromObjectName) < 0) {
            return false;
        }
        ZigZagElliotAlertHistoryMarker marker;
        ZeroMemory(marker);
        marker.timeFrame = fromSource.marketContext.timeFrame;
        marker.serverTime = fromSource.tradeTimeInfo.serverTime;
        marker.jstTime = fromSource.tradeTimeInfo.jstTime;
        marker.side = direction(fromResult.isBuy);
        marker.isEntry = (int)fromResult.isEntry;
        marker.entryResult = fromResult.entryResult;
        marker.correctionStatus = "NONE";
        marker.correctionText = "";
        if (fromCorrectionTimeFrame == PERIOD_H1 || fromCorrectionTimeFrame == PERIOD_H4) {
            Elliot *original = fromSource.getElliot(fromCorrectionTimeFrame);
            Elliot *corrected = fromJudgment.getElliot(fromCorrectionTimeFrame);
            if (original == NULL || corrected == NULL || fromJudgment == fromSource) {
                return false;
            }
            marker.correctionStatus = "APPLIED";
            string frameLabel = "H1";
            if (fromCorrectionTimeFrame == PERIOD_H4) {
                frameLabel = "H4";
            }
            marker.correctionText = frameLabel + " " + direction(original.isBuy)
                + "→" + direction(corrected.isBuy);
        }
        ENUM_TIMEFRAMES frames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5
        };
        for (int i = 0; i < ArraySize(frames); i++) {
            marker.waves[i].clear();
            if (marker.timeFrame == PERIOD_H1 && i > 4) {
                continue;
            }
            Elliot *elliot = fromJudgment.getElliot(frames[i]);
            if (elliot == NULL) {
                continue;
            }
            marker.waves[i].direction = "S";
            if (elliot.isBuy) {
                marker.waves[i].direction = "B";
            }
            if (frames[i] != PERIOD_MN1) {
                if (elliot.oscillator.ema200.isBuy && !elliot.oscillator.ema200.isSell) {
                    marker.waves[i].emaDirection = "B";
                } else if (!elliot.oscillator.ema200.isBuy && elliot.oscillator.ema200.isSell) {
                    marker.waves[i].emaDirection = "S";
                }
            }
            Wave *wave = elliot.getLatestWave();
            ZigZagPoint *point = elliot.getLatestPoint();
            if (wave != NULL) {
                marker.waves[i].state = "未";
                if (wave.isConfirmed) {
                    marker.waves[i].state = "確";
                }
            }
            if (point != NULL) {
                marker.waves[i].wave = point.elliotLabel;
                if (point.subElliotIndex > 0) {
                    marker.waves[i].subWave = point.subElliotLabel;
                }
            }
        }
        DrawZigZagElliotAlertMarkers formatter(0, "");
        return ObjectSetString(0, fromObjectName, OBJPROP_TOOLTIP, formatter.formatTooltip(marker));
    }

private:
    /**
     * 売買方向を補正説明用の文字列へ変換する。
     */
    static string direction(const bool fromIsBuy) {
        if (fromIsBuy) {
            return "BUY";
        }
        return "SELL";
    }
};

#endif
