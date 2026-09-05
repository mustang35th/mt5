#ifndef MSTNG_DATABASE_ENTITY_H1_EA_TRADE_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_H1_EA_TRADE_ENTITY_MQH

/**
 * H1 EA Tradeの保存スナップショット。
 * 任意文字列は空文字、任意正値は0、数量・損益はEMPTY_VALUEをNULLとして扱う。
 */
struct H1EaTradeEntity {
    /** 主キー。 */
    long id;
    /** 取引行を作成したRunの外部キー。 */
    long createdRunId;
    /** Decision外部キー。回復行ではNULL可。 */
    long decisionId;
    /** EAコンテキスト。 */
    string contextKey;
    /** NORMALまたはRECOVERED。 */
    string origin;
    /** 取引状態。 */
    string status;
    /** BUYまたはSELL。 */
    string side;
    /** 発注要求ロット。回復行はNULL可。 */
    double requestedVolume;
    /** 発注要求SL。回復行はNULL可。 */
    double requestedStopLoss;
    /** TimeCurrent()による発注要求時刻。回復行はNULL可。 */
    long entryRequestedServerTime;
    /** 新規注文ticket。 */
    string entryOrderTicket;
    /** 最初に確認した新規deal ticket。 */
    string entryDealTicket;
    /** 新規注文retcode。 */
    int entryRetcode;
    /** 安定したPosition ID。 */
    string positionIdentifier;
    /** 現在のPosition Ticket。 */
    string positionTicket;
    /** 最初のentry dealのDEAL_TIME_MSC。 */
    long openedAtMsc;
    /** broker約定平均価格。 */
    double openPrice;
    /** 成立数量。 */
    double openedVolume;
    /** 未約定の新規注文数量。 */
    double remainingEntryVolume;
    /** brokerで最後に確認したSL。Position消滅後も決済直前値を保持。 */
    double currentStopLoss;
    /** NONE、INITIAL_STOP_LOSS、H1_ZIGZAG_TRAIL、EXTERNALまたはUNKNOWN。 */
    string stopLossSource;
    /** 最後にトレイル評価を完了したH1バー時刻。 */
    long lastTrailEvaluatedH1BarTime;
    /** TRAIL_CANDIDATE、INITIAL_RESTOREまたはTRAIL_RESTORE。 */
    string pendingStopLossKind;
    /** トレイル候補を登録・復元した評価H1バー時刻。初期SL復元ではNULL。 */
    long pendingStopLossH1BarTime;
    /** broker反映を未確認の保護SL候補。 */
    double pendingStopLoss;
    /** トレイル候補の基準にした1つ前の確定ZigZag点時刻。初期SL復元ではNULL。 */
    long pendingStopLossPivotTime;
    /** トレイル候補の基準にしたZigZag点価格。初期SL復元ではNULL。 */
    double pendingStopLossPivotRate;
    /** 基準点の確定確認に使用した最新点時刻。初期SL復元ではNULL。 */
    long pendingStopLossLatestTime;
    /** broker結果を未確定のSL変更action。未送信時はNULL。 */
    string pendingStopLossActionUid;
    /** 自EA actionで最後に反映確認した候補の評価H1バー時刻。 */
    long lastAppliedTrailH1BarTime;
    /** 自EA actionで最後に反映確認したトレイルSL。 */
    double lastAppliedTrailStopLoss;
    /** 自EAが最後に適用した候補の基準点時刻。 */
    long lastAppliedTrailPivotTime;
    /** 自EAが最後に適用した候補の基準点価格。 */
    double lastAppliedTrailPivotRate;
    /** 自EAが最後に適用した候補の確認点時刻。 */
    long lastAppliedTrailLatestTime;
    /** TimeCurrent()による決済要求時刻。 */
    long exitRequestedServerTime;
    /** 決済注文ticket。 */
    string exitOrderTicket;
    /** 最後に確認した決済deal ticket。 */
    string exitDealTicket;
    /** 決済注文retcode。 */
    int exitRetcode;
    /** 最後のexit dealのDEAL_TIME_MSC。 */
    long closedAtMsc;
    /** broker履歴から求めた決済平均価格。 */
    double closePrice;
    /** 部分決済後の残存数量。 */
    double remainingPositionVolume;
    /** EAが保護水準跨ぎの成行決済を要求した理由。 */
    string exitIntentReason;
    /** EA側で正規化した最終決済分類。 */
    string closeReason;
    /** broker deal理由。例：SL、EXPERT、CLIENT。 */
    string brokerCloseReason;
    /** deal履歴の確定profit合計。 */
    double profit;
    /** commission合計。 */
    double commission;
    /** swap合計。 */
    double swap;
    /** fee合計。 */
    double fee;
    /** 最後の処理エラー。通常は空文字。 */
    string lastError;
    /** TimeLocal()による取引行作成時刻。 */
    long createdAt;
    /** TimeLocal()による最終更新時刻。 */
    long updatedAt;

    /**
     * 未取得値と有効な0を区別して初期化する。
     */
    H1EaTradeEntity() {
        this.reset();
    }

    /**
     * 保存前の未取得状態へ戻す。
     */
    void reset() {
        this.id = 0;
        this.createdRunId = 0;
        this.decisionId = 0;
        this.contextKey = "";
        this.origin = "NORMAL";
        this.status = "";
        this.side = "";
        this.requestedVolume = EMPTY_VALUE;
        this.requestedStopLoss = 0.0;
        this.entryRequestedServerTime = 0;
        this.entryOrderTicket = "";
        this.entryDealTicket = "";
        this.entryRetcode = -1;
        this.positionIdentifier = "";
        this.positionTicket = "";
        this.openedAtMsc = 0;
        this.openPrice = 0.0;
        this.openedVolume = EMPTY_VALUE;
        this.remainingEntryVolume = EMPTY_VALUE;
        this.currentStopLoss = 0.0;
        this.stopLossSource = "NONE";
        this.lastTrailEvaluatedH1BarTime = 0;
        this.pendingStopLossKind = "";
        this.pendingStopLossH1BarTime = 0;
        this.pendingStopLoss = 0.0;
        this.pendingStopLossPivotTime = 0;
        this.pendingStopLossPivotRate = 0.0;
        this.pendingStopLossLatestTime = 0;
        this.pendingStopLossActionUid = "";
        this.lastAppliedTrailH1BarTime = 0;
        this.lastAppliedTrailStopLoss = 0.0;
        this.lastAppliedTrailPivotTime = 0;
        this.lastAppliedTrailPivotRate = 0.0;
        this.lastAppliedTrailLatestTime = 0;
        this.exitRequestedServerTime = 0;
        this.exitOrderTicket = "";
        this.exitDealTicket = "";
        this.exitRetcode = -1;
        this.closedAtMsc = 0;
        this.closePrice = 0.0;
        this.remainingPositionVolume = EMPTY_VALUE;
        this.exitIntentReason = "";
        this.closeReason = "";
        this.brokerCloseReason = "";
        this.profit = EMPTY_VALUE;
        this.commission = EMPTY_VALUE;
        this.swap = EMPTY_VALUE;
        this.fee = EMPTY_VALUE;
        this.lastError = "";
        this.createdAt = 0;
        this.updatedAt = 0;
    }
};

#endif
