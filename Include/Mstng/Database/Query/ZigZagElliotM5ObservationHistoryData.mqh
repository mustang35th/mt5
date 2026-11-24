#ifndef MSTNG_M5_OBSERVATION_HISTORY_DATA_MQH
#define MSTNG_M5_OBSERVATION_HISTORY_DATA_MQH

/**
 * M5観測ツールチップへ渡す一時間足の保存波動。
 * 不明なフラグは-1、未記録の文字列・日時は空文字・0で保持する。
 */
struct M5ObservationHistoryFrame {
    /** 分析時間足。 */
    int timeFrame;

    /** この時間足の保存行を取得できた場合true。 */
    bool hasData;

    /** 保存された主波ラベル。 */
    string mainWave;

    /** 保存された副次波ラベル。 */
    string subWave;

    /** 保存された再分析前の主波ラベル。 */
    string originalWave;

    /** 波方向。上昇1、下降0、不明-1。 */
    int isUptrend;

    /** 分析方向。BUY1、SELL0、不明-1。 */
    int isBuy;

    /** 最新Waveの確定状態。確定1、未確定0、不明-1。 */
    int isConfirmed;

    /** 最新ポイントの補完状態。補完1、通常0、不明-1。 */
    int isAdded;

    /** 最新ポイントの保存サーバー時刻。 */
    datetime pointTime;

    /** 最新ポイントの保存価格。 */
    double pointRate;

    /** 保存価格が利用可能な場合true。 */
    bool hasPointRate;

    /**
     * 保存値を未取得状態へ戻す。
     */
    void clear() {
        this.timeFrame = PERIOD_CURRENT;
        this.hasData = false;
        this.mainWave = "";
        this.subWave = "";
        this.originalWave = "";
        this.isUptrend = -1;
        this.isBuy = -1;
        this.isConfirmed = -1;
        this.isAdded = -1;
        this.pointTime = 0;
        this.pointRate = 0.0;
        this.hasPointRate = false;
    }
};

/**
 * 一つのM5観測と、MN1からM5までの固定7足を保持する。
 * M1波動や保存されていない日時は再計算で補完しない。
 */
struct M5ObservationHistoryRecord {
    /** 保存観測ID。 */
    long id;

    /** 保存Run ID。 */
    long runId;

    /** 観測基準M5足のサーバー開始時刻。 */
    datetime barTime;

    /** 保存された観測基準M5足の日本時刻。未記録は0。 */
    datetime jstTime;

    /** 保存された分析取得サーバー時刻。未記録は0。 */
    datetime captureTime;

    /** MN1・W1・D1・H4・H1・M15・M5の固定順。 */
    M5ObservationHistoryFrame frames[7];

    /**
     * 観測を未取得状態へ戻し、7時間足の順序を固定する。
     */
    void clear() {
        this.id = 0;
        this.runId = 0;
        this.barTime = 0;
        this.jstTime = 0;
        this.captureTime = 0;
        int timeFrames[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
        for (int i = 0; i < 7; i++) {
            this.frames[i].clear();
            this.frames[i].timeFrame = timeFrames[i];
        }
    }
};

#endif // MSTNG_M5_OBSERVATION_HISTORY_DATA_MQH
