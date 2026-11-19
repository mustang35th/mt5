#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_WAVE_SNAPSHOT_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_WAVE_SNAPSHOT_MQH

#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * 採用分析の1時間足について、最新波動の表示に必要な値だけを保持する。
 * 分析オブジェクトへの参照は残さず、主波と副波を分けて保存する。
 */
struct ZigZagElliotMonitorWaveInfo {
    /** 最新波動の方向と主波ラベルを取得済みの場合true。 */
    bool available;

    /** 最新Waveが上昇方向の場合true。オシレーターの売買方向とは区別する。 */
    bool isUptrend;

    /** エントリーの波動条件と同じ最新ポイントの主波ラベル。 */
    string mainLabel;

    /** 詳細表示に使う最新ポイントの副波ラベル。 */
    string subLabel;

    /** 最新Waveが確定している場合true。 */
    bool confirmed;

    /** 最新ポイントがZigZagから補完された場合true。 */
    bool addedPoint;

    /** 最新ポイントのバー開始サーバー時刻。 */
    datetime pointTime;

    /**
     * 未取得状態で生成する。
     */
    ZigZagElliotMonitorWaveInfo() {
        this.reset();
    }

    /**
     * 保持していた波動情報を破棄する。
     */
    void reset() {
        this.available = false;
        this.isUptrend = false;
        this.mainLabel = "";
        this.subLabel = "";
        this.confirmed = false;
        this.addedPoint = false;
        this.pointTime = 0;
    }

    /**
     * 既に分析された時間足の最新波動を値として保存する。
     *
     * @param fromElliot 採用分析の時間足。参照だけを行い、所有しない。
     */
    void capture(Elliot *fromElliot) {
        this.reset();
        if (fromElliot == NULL) {
            return;
        }

        Wave *wave = fromElliot.getLatestWave();
        ZigZagPoint *point = fromElliot.getLatestPoint();
        if (wave == NULL || point == NULL || point.elliotLabel == "") {
            return;
        }

        this.available = true;
        this.isUptrend = wave.isUptrend;
        this.mainLabel = point.elliotLabel;
        this.subLabel = point.subElliotLabel;
        this.confirmed = wave.isConfirmed;
        this.addedPoint = point.isAddedPoint;
        this.pointTime = point.barTime;
    }
};

/**
 * 安定したM1確認で採用したM5・M1の波動を、分析解放後も表示できる値として保持する。
 * 分析未実施と、分析完了後に方向条件などで採用されなかった状態を区別する。
 */
struct ZigZagElliotMonitorWaveSnapshot {
    /** 安定した元分析と戦略の確認が完了した場合true。 */
    bool analyzed;

    /** 戦略がエントリー判定用の分析を採用した場合true。 */
    bool adopted;

    /** 今回の確認対象M1開始サーバー時刻。 */
    datetime targetM1BarTime;

    /** 採用分析で方向を補正した時間足。補正なし・未採用はPERIOD_CURRENT。 */
    ENUM_TIMEFRAMES correctionTimeFrame;

    /** 採用分析のM5最新波動。 */
    ZigZagElliotMonitorWaveInfo m5;

    /** 採用分析のM1最新波動。 */
    ZigZagElliotMonitorWaveInfo m1;

    /**
     * 未分析状態で生成する。
     */
    ZigZagElliotMonitorWaveSnapshot() {
        this.reset();
    }

    /**
     * 前回の採用状態と波動情報を破棄する。
     */
    void reset() {
        this.analyzed = false;
        this.adopted = false;
        this.targetM1BarTime = 0;
        this.correctionTimeFrame = PERIOD_CURRENT;
        this.m5.reset();
        this.m1.reset();
    }

    /**
     * 戦略が採用した分析からM5・M1を保存する。追加分析は行わない。
     * 安定性と準備完了を確認した後だけ呼び出し、NULLは分析済み・未採用として保存する。
     *
     * @param fromAnalysis 戦略の採用分析。元分析や補正分析の所有権は移さない。
     * @param fromTargetM1BarTime 今回の確認対象M1開始サーバー時刻。
     * @param fromCorrectionTimeFrame 採用分析の方向補正時間足。
     */
    void capture(ElliotAll *fromAnalysis, const datetime fromTargetM1BarTime,
            const ENUM_TIMEFRAMES fromCorrectionTimeFrame) {
        this.reset();
        this.analyzed = true;
        this.targetM1BarTime = fromTargetM1BarTime;
        if (fromAnalysis == NULL) {
            return;
        }

        this.adopted = true;
        this.correctionTimeFrame = fromCorrectionTimeFrame;
        this.m5.capture(fromAnalysis.getElliot(PERIOD_M5));
        this.m1.capture(fromAnalysis.getElliot(PERIOD_M1));
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_WAVE_SNAPSHOT_MQH
