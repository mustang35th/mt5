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

    /** EMA200のBUY判定。BUY1、それ以外0、未記録-1。 */
    int isEma200Buy;

    /** EMA200のSELL判定。SELL1、それ以外0、未記録-1。 */
    int isEma200Sell;

    /** 保存されたGMMAトレンド継続数。 */
    int gmmaTrendCount;

    /** 保存されたGMMAトレンド継続数が利用可能な場合true。 */
    bool hasGmmaTrendCount;

    /** 保存されたGMMAクロス継続数。 */
    int gmmaCrossCount;

    /** 保存されたGMMAクロス継続数が利用可能な場合true。 */
    bool hasGmmaCrossCount;

    /** 値動き判定の取得状態。有効1、判定不能0、未記録-1。 */
    int isPriceMovementValid;

    /** 保存された値動きレベル。未記録-1、未取得0、静か1、通常2、活発3。 */
    int priceMovementLevel;

    /** 保存された値動き活動度。 */
    double priceMovementActivityRatio;

    /** 保存された値動き活動度が利用可能な場合true。 */
    bool hasPriceMovementActivityRatio;

    /** F・FEの表示選択に使用する元波動番号。未記録-1。 */
    int originalWaveIndex;

    /** 直前推進波の副次波番号。該当なし0、1または3、未記録-1。 */
    int previousMotiveSubElliotIndex;

    /** 最新ポイントと前回ポイントの保存値幅pips。 */
    double pointPipsDiff;

    /** 保存された値幅が利用可能な場合true。 */
    bool hasPointPipsDiff;

    /** 最新ポイントの保存リトレースメント%。 */
    double pointFibonacciPercent;

    /** 保存されたリトレースメントが利用可能な場合true。 */
    bool hasPointFibonacciPercent;

    /** 最新ポイントの保存エクスパンション%。 */
    double pointFibonacciExpansionPercent;

    /** 保存されたエクスパンションが利用可能な場合true。 */
    bool hasPointFibonacciExpansionPercent;

    /** 最新ポイントの保存日本時刻。未記録は0。 */
    datetime pointJstTime;

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
        this.isEma200Buy = -1;
        this.isEma200Sell = -1;
        this.gmmaTrendCount = 0;
        this.hasGmmaTrendCount = false;
        this.gmmaCrossCount = 0;
        this.hasGmmaCrossCount = false;
        this.isPriceMovementValid = -1;
        this.priceMovementLevel = -1;
        this.priceMovementActivityRatio = 0.0;
        this.hasPriceMovementActivityRatio = false;
        this.originalWaveIndex = -1;
        this.previousMotiveSubElliotIndex = -1;
        this.pointPipsDiff = 0.0;
        this.hasPointPipsDiff = false;
        this.pointFibonacciPercent = 0.0;
        this.hasPointFibonacciPercent = false;
        this.pointFibonacciExpansionPercent = 0.0;
        this.hasPointFibonacciExpansionPercent = false;
        this.pointJstTime = 0;
    }
};

/**
 * 同じM5時刻の通貨強弱履歴にある一集計期間の順位と前M5比を保持する。
 */
struct M5ObservationHistoryStrengthPeriod {
    /** 両通貨の順位が有効な場合true。 */
    bool valid;

    /** 同じ参照元の直前M5と比較できた場合true。 */
    bool comparable;

    /** 基軸通貨の順位。未記録は0。 */
    int baseRank;

    /** 決済通貨の順位。未記録は0。 */
    int quoteRank;

    /** 決済通貨順位から基軸通貨順位を引いた値。 */
    int gap;

    /** 現在の順位差から直前M5の順位差を引いた値。 */
    int delta;

    /**
     * 数値と取得状態を未記録へ戻す。
     */
    void clear() {
        this.valid = false;
        this.comparable = false;
        this.baseRank = 0;
        this.quoteRank = 0;
        this.gap = 0;
        this.delta = 0;
    }
};

/**
 * 観測と同じM5時刻の通貨強弱DB履歴を保持する。
 * 観測保存時点のスナップショットとは区別し、強弱DBの取得元を併記する。
 */
struct M5ObservationHistoryStrength {
    /** 通貨強弱の参照設定が有効な場合true。 */
    bool enabled;

    /** 読取結果。未記録・取得失敗・無効などを区別する。 */
    string status;

    /** 基軸通貨名。 */
    string baseCurrency;

    /** 決済通貨名。 */
    string quoteCurrency;

    /** 選択した投票方式の表示名。 */
    string weightLabel;

    /** 実際に選択した通貨強弱履歴のLIVEまたはTESTER。 */
    string sourceMode;

    /** 通貨強弱DB内の集計ID。観測Run IDとは別の識別子。 */
    long runId;

    /** 通貨強弱履歴のM5開始サーバー時刻。 */
    datetime barTime;

    /** 通貨強弱DBの更新Unix時刻。観測取得サーバー時刻とは区別する。 */
    datetime updatedAt;

    /** 長中期の順位と前M5比。 */
    M5ObservationHistoryStrengthPeriod longMedium;

    /** 中短期の順位と前M5比。 */
    M5ObservationHistoryStrengthPeriod mediumShort;

    /**
     * 履歴と取得状態を初期化する。
     */
    void clear() {
        this.enabled = false;
        this.status = "未記録";
        this.baseCurrency = "";
        this.quoteCurrency = "";
        this.weightLabel = "";
        this.sourceMode = "";
        this.runId = 0;
        this.barTime = 0;
        this.updatedAt = 0;
        this.longMedium.clear();
        this.mediumShort.clear();
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

    /** 別DBから取得した、同M5時刻の通貨強弱履歴。 */
    M5ObservationHistoryStrength strength;

    /**
     * 観測を未取得状態へ戻し、7時間足の順序を固定する。
     */
    void clear() {
        this.id = 0;
        this.runId = 0;
        this.barTime = 0;
        this.jstTime = 0;
        this.captureTime = 0;
        this.strength.clear();
        int timeFrames[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
        for (int i = 0; i < 7; i++) {
            this.frames[i].clear();
            this.frames[i].timeFrame = timeFrames[i];
        }
    }
};

#endif // MSTNG_M5_OBSERVATION_HISTORY_DATA_MQH
