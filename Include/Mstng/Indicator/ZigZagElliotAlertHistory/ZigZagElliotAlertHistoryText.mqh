#ifndef MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_TEXT_MQH
#define MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_TEXT_MQH

#include <Mstng\Indicator\ZigZagElliotAlertHistory\ZigZagElliotAlertHistoryData.mqh>

/**
 * 保存されたアラート文字へ、同じ分析の再カウント前ラベルを表示用に付加する。
 * 矢印・構造ランク・保存済みの判定内容は変更しない。
 */
class ZigZagElliotAlertHistoryText {
public:
    /**
     * 保存文字の3足の波動が一致する場合だけ、再カウント前ラベルを付加する。
     */
    static string format(const string fromText, const ENUM_TIMEFRAMES fromTimeFrame,
            const ZigZagElliotAlertHistoryWaveSummary &fromWaves[]) {
        string text = fromText;
        StringReplace(text, "[D1補正]", "[D1C]");
        StringReplace(text, "[H4補正]", "[H4C]");
        StringReplace(text, "[H1補正]", "[H1C]");

        int firstIndex = -1;
        if (fromTimeFrame == PERIOD_M5) {
            firstIndex = 4;
        } else if (fromTimeFrame == PERIOD_M15) {
            firstIndex = 3;
        } else if (fromTimeFrame == PERIOD_H1) {
            firstIndex = 2;
        }
        if (firstIndex < 0 || ArraySize(fromWaves) < firstIndex + 3) {
            return text;
        }

        string originalWaves = "";
        string displayWaves = "";
        for (int i = firstIndex; i < firstIndex + 3; i++) {
            if (fromWaves[i].wave == "") {
                return text;
            }

            string wave = fromWaves[i].wave;
            if (fromWaves[i].subWave != "") {
                wave += "." + fromWaves[i].subWave;
            }
            if (i > firstIndex) {
                originalWaves += "-";
                displayWaves += "-";
            }
            originalWaves += wave;
            displayWaves += wave;
            if (fromWaves[i].originalWave != "" && fromWaves[i].originalWave != fromWaves[i].wave) {
                displayWaves += "[" + fromWaves[i].originalWave + "]";
            }
        }

        int start = StringFind(text, "▲" + originalWaves);
        if (start < 0) {
            start = StringFind(text, "▼" + originalWaves);
        }
        if (start < 0) {
            return text;
        }

        int end = start + 1 + StringLen(originalWaves);
        if (end < StringLen(text) && StringSubstr(text, end, 1) != " ") {
            return text;
        }

        return StringSubstr(text, 0, start + 1) + displayWaves + StringSubstr(text, end);
    }

    /**
     * 元分析または補正分析の時間足と最新ポイントだけから表示概要を作る。
     */
    static string formatSnapshot(const string fromText, const ENUM_TIMEFRAMES fromTimeFrame,
            const ZigZagElliotAlertTimeFrameEntity &fromTimeFrames[],
            const ZigZagElliotAlertPointEntity &fromPoints[]) {
        int frames[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
        ZigZagElliotAlertHistoryWaveSummary waves[7];
        for (int i = 0; i < ArraySize(frames); i++) {
            waves[i].clear();
            for (int j = 0; j < ArraySize(fromTimeFrames); j++) {
                if (fromTimeFrames[j].timeFrame != frames[i]) {
                    continue;
                }
                if (waves[i].recorded) {
                    waves[i].clear();
                    break;
                }

                waves[i].recorded = true;
                waves[i].wave = fromTimeFrames[j].latestElliotLabel;
                if (fromTimeFrames[j].latestSubElliotIndex > 0) {
                    waves[i].subWave = fromTimeFrames[j].latestSubElliotLabel;
                }
                int latestCount = 0;
                for (int k = 0; k < ArraySize(fromPoints); k++) {
                    if (fromPoints[k].alertTimeFrameId != fromTimeFrames[j].id || fromPoints[k].isLatest != 1) {
                        continue;
                    }

                    latestCount++;
                    if (fromPoints[k].timeFrame == frames[i] && fromPoints[k].isOriginalElliotAvailable == 1
                            && fromPoints[k].elliotLabel == fromTimeFrames[j].latestElliotLabel
                            && fromPoints[k].subElliotIndex == fromTimeFrames[j].latestSubElliotIndex
                            && fromPoints[k].subElliotLabel == fromTimeFrames[j].latestSubElliotLabel) {
                        waves[i].originalWave = fromPoints[k].orgElliotLabel;
                    }
                }

                if (latestCount != 1) {
                    waves[i].originalWave = "";
                }
            }
        }

        return format(fromText, fromTimeFrame, waves);
    }
};

#endif
