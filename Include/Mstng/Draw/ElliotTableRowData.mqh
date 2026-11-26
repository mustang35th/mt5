#ifndef MSTNG_DRAW_ELLIOT_TABLE_ROW_DATA_MQH
#define MSTNG_DRAW_ELLIOT_TABLE_ROW_DATA_MQH

/**
 * 現在の分析結果と保存済み観測が共有する、一時間足分の表表示データ。
 * 値の取得・分析は行わず、不明な状態と取得済みのゼロを区別して保持する。
 */
struct ElliotTableRowData {
    /** 表示する時間足名。 */
    string timeFrameLabel;

    /** この時間足の表示元データが存在する場合true。 */
    bool hasData;

    /** 主波ラベル。 */
    string mainWave;

    /** 副次波ラベル。 */
    string subWave;

    /** 再分析前の主波ラベル。 */
    string originalWave;

    /** 波動方向。上昇1、下降0、不明-1。 */
    int isUptrend;

    /** 分析方向。BUY1、SELL0、不明-1。 */
    int isBuy;

    /** 確定状態。確定1、未確定0、不明-1。 */
    int isConfirmed;

    /** 補完状態。補完1、通常0、不明-1。 */
    int isAdded;

    /** EMA200のBUY判定。BUY1、それ以外0、不明-1。 */
    int isEma200Buy;

    /** EMA200のSELL判定。SELL1、それ以外0、不明-1。 */
    int isEma200Sell;

    /** 値動き判定の取得状態。有効1、判定不能0、未記録-1。 */
    int isPriceMovementValid;

    /** 値動きレベル。未記録-1、不明0、静か1、通常2、活発3。 */
    int priceMovementLevel;

    /** 値動きの活動度。 */
    double priceMovementActivityRatio;

    /** 活動度が取得済みの場合true。 */
    bool hasPriceMovementActivityRatio;

    /** GMMAのトレンド継続カウント。正は上昇、負は下降。 */
    int gmmaTrendCount;

    /** GMMAトレンド継続カウントが取得済みの場合true。 */
    bool hasGmmaTrendCount;

    /** EMA30とEMA60の上下関係の継続カウント。 */
    int gmmaCrossCount;

    /** GMMAクロス継続カウントが取得済みの場合true。 */
    bool hasGmmaCrossCount;

    /** F・FEの表示選択に使う元波動番号。未記録-1。 */
    int originalWaveIndex;

    /** 直前推進波の副次波番号。該当なし0、未記録-1。 */
    int previousMotiveSubElliotIndex;

    /** ポイント間の値幅pips。 */
    double pointPipsDiff;

    /** 値幅が取得済みの場合true。 */
    bool hasPointPipsDiff;

    /** ポイントのリトレースメント%。 */
    double pointFibonacciPercent;

    /** リトレースメントが取得済みの場合true。 */
    bool hasPointFibonacciPercent;

    /** ポイントのエクスパンション%。 */
    double pointFibonacciExpansionPercent;

    /** エクスパンションが取得済みの場合true。 */
    bool hasPointFibonacciExpansionPercent;

    /** ポイントの価格。 */
    double pointRate;

    /** 価格が取得済みの場合true。 */
    bool hasPointRate;

    /**
     * 表示元データが未取得の状態で初期化する。
     */
    ElliotTableRowData() {
        this.clear();
    }

    /**
     * 取得済み状態を解除し、方向・判定を不明へ戻す。
     */
    void clear() {
        this.timeFrameLabel = "";
        this.hasData = false;
        this.mainWave = "";
        this.subWave = "";
        this.originalWave = "";
        this.isUptrend = -1;
        this.isBuy = -1;
        this.isConfirmed = -1;
        this.isAdded = -1;
        this.isEma200Buy = -1;
        this.isEma200Sell = -1;
        this.isPriceMovementValid = -1;
        this.priceMovementLevel = -1;
        this.priceMovementActivityRatio = 0.0;
        this.hasPriceMovementActivityRatio = false;
        this.gmmaTrendCount = 0;
        this.hasGmmaTrendCount = false;
        this.gmmaCrossCount = 0;
        this.hasGmmaCrossCount = false;
        this.originalWaveIndex = -1;
        this.previousMotiveSubElliotIndex = -1;
        this.pointPipsDiff = 0.0;
        this.hasPointPipsDiff = false;
        this.pointFibonacciPercent = 0.0;
        this.hasPointFibonacciPercent = false;
        this.pointFibonacciExpansionPercent = 0.0;
        this.hasPointFibonacciExpansionPercent = false;
        this.pointRate = 0.0;
        this.hasPointRate = false;
    }
};

/**
 * 表とホバーの表示色を保持する。
 * 分析方向と波動方向を独立して扱い、表示先から配色を指定できる。
 */
struct ElliotTablePalette {
    /** BUY分析方向の色。 */
    color upColor;

    /** SELL分析方向の色。 */
    color downColor;

    /** 未確定BUY波動の色。 */
    color unconfirmedUpColor;

    /** 未確定SELL波動の色。 */
    color unconfirmedDownColor;

    /** 補完ポイントの色。 */
    color addedColor;

    /** 未記録・不明・静かな値動きの色。 */
    color unknownColor;

    /** NONE・通常の値動きの色。 */
    color neutralColor;

    /** 活発な値動きの色。 */
    color movementActiveColor;

    /** ホバーで示す上昇波動の色。 */
    color waveUpColor;

    /** ホバーで示す下降波動の色。 */
    color waveDownColor;

    /**
     * チャートと保存波動パネルで使用する標準配色を設定する。
     */
    ElliotTablePalette() {
        this.upColor = clrAqua;
        this.downColor = clrHotPink;
        this.unconfirmedUpColor = clrDodgerBlue;
        this.unconfirmedDownColor = clrMagenta;
        this.addedColor = clrWhite;
        this.unknownColor = clrSilver;
        this.neutralColor = clrWhite;
        this.movementActiveColor = clrDodgerBlue;
        this.waveUpColor = clrDeepSkyBlue;
        this.waveDownColor = clrPlum;
    }
};

#endif // MSTNG_DRAW_ELLIOT_TABLE_ROW_DATA_MQH
