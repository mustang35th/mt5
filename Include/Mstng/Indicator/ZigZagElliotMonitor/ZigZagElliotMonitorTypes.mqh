#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_TYPES_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_TYPES_MQH

#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorDirectionSnapshot.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorEntryDetails.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorStrengthSnapshot.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorWaveSnapshot.mqh>

/**
 * 監視対象1通貨の判定状態。
 */
enum ZigZagElliotMonitorStatus {
    ZIGZAG_MONITOR_WAITING = 0,
    ZIGZAG_MONITOR_NOT_MATCHED = 1,
    ZIGZAG_MONITOR_ENTRY = 2,
    ZIGZAG_MONITOR_ERROR = 3
};

/**
 * 分析オブジェクトを解放した後も保持できるM1判定結果。
 */
struct ZigZagElliotMonitorResult {
    /** 今回の取得・判定状態。 */
    ZigZagElliotMonitorStatus status;

    /** 今回のM1足で再試行を終えてよい場合true。 */
    bool completed;

    /** エントリー成立方向。 */
    bool isBuy;

    /** 元M1のシグナル基準時刻。 */
    datetime signalTime;

    /** 判定したM1バー開始時刻。 */
    datetime barTime;

    /** 通貨強弱の対象M5開始時刻。 */
    datetime targetM5BarTime;

    /** 実際の判定サーバー時刻。 */
    datetime evaluatedAtSrv;

    /** 待機・不成立・失敗の説明。 */
    string message;

    /** 一覧の判定列に表示する短い理由。 */
    string shortMessage;

    /** 直近の確認処理に要したミリ秒。未計測は-1。 */
    double durationMs;

    /** この確認で取得した現在順位と両期間の増減。描画専用の値コピー。 */
    ZigZagElliotMonitorStrengthSnapshot strength;

    /** 安定した確認で採用したM5・M1波動。未分析と未採用を区別する。 */
    ZigZagElliotMonitorWaveSnapshot waves;

    /** 安定した確認で取得した補正前6時間足のBUY・SELL方向。 */
    ZigZagElliotMonitorDirectionSnapshot directions;

    /** 同じ評価で使ったM1条件の値・停止理由・確定したシグナル回数。 */
    ZigZagElliotMonitorEntryDetails details;

    /**
     * 未取得の状態へ戻す。
     */
    void reset() {
        this.status = ZIGZAG_MONITOR_WAITING;
        this.completed = false;
        this.isBuy = false;
        this.signalTime = 0;
        this.barTime = 0;
        this.targetM5BarTime = 0;
        this.evaluatedAtSrv = 0;
        this.message = "準備待ち";
        this.shortMessage = "準備待ち";
        this.durationMs = -1.0;
        this.strength.reset();
        this.waves.reset();
        this.directions.reset();
        this.details.reset();
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_TYPES_MQH
