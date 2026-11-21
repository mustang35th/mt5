#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_NOTIFICATION_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_NOTIFICATION_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorTypes.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>

/**
 * M1エントリー成立時の端末内通知方式。
 */
enum ENUM_ZIGZAG_MONITOR_NOTIFY {
    ZIGZAG_MONITOR_NOTIFY_POPUP = 0, // ポップアップ
    ZIGZAG_MONITOR_NOTIFY_SOUND = 1, // 音のみ
    ZIGZAG_MONITOR_NOTIFY_OFF = 2 // OFF
};

/**
 * 監視で成立したM1エントリーを、判定時の波動・通貨強弱とともに端末へ通知する。
 */
class ZigZagElliotMonitorNotification {
public:
    /**
     * 通知方式に従って新しい成立を知らせる。本文はポップアップ表示時だけ作成する。
     *
     * @param fromMode 端末内の通知方式。
     * @param fromSymbol 監視一覧に表示する通貨ペア名。
     * @param fromGmo GMO対象ペアの場合true。
     * @param fromResult 成立した監視判定。
     */
    static void notify(const ENUM_ZIGZAG_MONITOR_NOTIFY fromMode, const string fromSymbol,
            const bool fromGmo, const ZigZagElliotMonitorResult &fromResult) {
        if (fromMode == ZIGZAG_MONITOR_NOTIFY_SOUND) {
            PlaySound("alert.wav");
            return;
        }

        if (fromMode != ZIGZAG_MONITOR_NOTIFY_POPUP) {
            return;
        }

        string message = "[M1 ENTRY] " + fromSymbol + " " + Constant::getBuySell(fromResult.isBuy);
        if (fromGmo) {
            message += " [G]";
        }

        message += "  " + TimeToString(TimeJapanUtil::getJapanTime(fromResult.evaluatedAtSrv), TIME_SECONDS) + " JST"
            + "\n波動 M5 " + formatWave(fromResult.waves.m5) + " / M1 " + formatWave(fromResult.waves.m1)
            + "\n順位差（直近変化） 長中期 " + formatStrength(fromResult.strength, true)
            + " / 中短期 " + formatStrength(fromResult.strength, false);
        if (fromResult.details.longMediumPullback) {
            message += "\n" + fromResult.strength.longMediumGapDirection.getM1LongMediumPullbackText();
        }

        Alert(message);
    }

private:
    /**
     * 採用した分析の波方向と主波ラベルを監視一覧と同じ記号で表す。
     */
    static string formatWave(const ZigZagElliotMonitorWaveInfo &fromWave) {
        if (!fromWave.available || fromWave.mainLabel == "") {
            return "—";
        }

        if (fromWave.isUptrend) {
            return "▲" + fromWave.mainLabel;
        }

        return "▼" + fromWave.mainLabel;
    }

    /**
     * 成立時の順位差と、直近で変化したときの増減方向・幅を表す。
     */
    static string formatStrength(const ZigZagElliotMonitorStrengthSnapshot &fromStrength,
            const bool fromLongMedium) {
        if (!fromStrength.hasRanks(fromLongMedium)) {
            return "—";
        }

        string arrow = "?";
        int direction = fromStrength.getDirection(fromLongMedium);
        if (direction > 0) {
            arrow = "↑";
        } else if (direction < 0) {
            arrow = "↓";
        }

        string changeText = "—";
        int change = fromStrength.getGapChange(fromLongMedium);
        if (change != 0) {
            changeText = StringFormat("%+d", change);
        }

        return StringFormat("%+d %s(%s)", fromStrength.getRankDifference(fromLongMedium), arrow, changeText);
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_NOTIFICATION_MQH
