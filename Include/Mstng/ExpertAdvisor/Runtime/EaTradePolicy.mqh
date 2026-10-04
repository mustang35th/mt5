#ifndef MSTNG_EA_TRADE_POLICY_MQH
#define MSTNG_EA_TRADE_POLICY_MQH

#include <Mstng\Elliot\Wave.mqh>
#include <MstngEa\Domain\PositionSnapshot.mqh>

/**
 * 戦略判定から発注処理へ渡す、保存形式に依存しない要求値。
 */
struct EaEntryRequest {
    /** BUYまたはSELL。 */
    string side;
    /** 発注要求ロット。 */
    double requestedVolume;
    /** 必須の初期SL。 */
    double initialStopLoss;
    /** 判定した基準足の開始時刻。 */
    long barTime;
    /** 許容する初期SL幅。 */
    double maxInitialRiskPips;
};

/**
 * 時間足別の戦略から受け取る、保護SL候補の判定結果。
 */
struct EaTrailDecision {
    /** SLを変更する場合true。 */
    bool shouldModify;
    /** 変更候補のSL価格。 */
    double targetStopLoss;
    /** 基準ZigZagポイント価格。 */
    double pivotRate;
    /** 基準ZigZagポイント時刻。 */
    datetime pivotBarTime;
    /** 基準ZigZagポイントのバー位置。 */
    int pivotBarIndex;
    /** 基準ポイントが山の場合true。 */
    bool pivotIsPeak;
    /** 確定確認に使用した最新ポイント時刻。 */
    datetime latestBarTime;
    /** 変更を見送った理由。 */
    string skipReason;

    /**
     * 未判定状態へ戻す。
     */
    void reset() {
        this.shouldModify = false;
        this.targetStopLoss = 0.0;
        this.pivotRate = 0.0;
        this.pivotBarTime = 0;
        this.pivotBarIndex = -1;
        this.pivotIsPeak = false;
        this.latestBarTime = 0;
        this.skipReason = "NOT_EVALUATED";
    }
};

/**
 * 戦略ごとの時間足と、既存保存値との互換性を保つ識別文字列。
 */
struct EaTradeProfile {
    /** 発注期限と気配の検証に使う時間足。 */
    ENUM_TIMEFRAMES timeFrame;
    /** 要求IDの接頭辞。 */
    string actionUidPrefix;
    /** トレイル評価IDの接頭辞。 */
    string trailEvaluationUidPrefix;
    /** 取消IDの接頭辞。 */
    string cancelUidPrefix;
    /** 約定再監査IDの接頭辞。 */
    string dealAuditUidPrefix;
    /** 復旧IDの接頭辞。 */
    string recoveryUidPrefix;
    /** 復旧状態文字列の接頭辞。 */
    string recoverySnapshotPrefix;
    /** メモリ内保留状態の隔離文字列接頭辞。 */
    string pendingMemoryPrefix;
    /** 新規注文コメントの接頭辞。 */
    string entryCommentPrefix;
    /** 決済注文コメントの接頭辞。 */
    string closeCommentPrefix;
    /** 戦略のトレイルSLを表す保存値。 */
    string trailStopLossSource;
    /** トレイル水準を跨いだ決済理由。 */
    string trailCrossedReason;
    /** 保留候補の基準足を表す監査キー。 */
    string pendingBarField;
    /** 適用済み候補の基準足を表す監査キー。 */
    string lastAppliedTrailBarField;
    /** 最後の評価基準足を表す監査キー。 */
    string lastTrailEvaluatedBarField;

    /**
     * 未設定値を明示し、途中まで設定したProfileを拒否する。
     */
    EaTradeProfile() {
        this.timeFrame = PERIOD_CURRENT;
        this.actionUidPrefix = "";
        this.trailEvaluationUidPrefix = "";
        this.cancelUidPrefix = "";
        this.dealAuditUidPrefix = "";
        this.recoveryUidPrefix = "";
        this.recoverySnapshotPrefix = "";
        this.pendingMemoryPrefix = "";
        this.entryCommentPrefix = "";
        this.closeCommentPrefix = "";
        this.trailStopLossSource = "";
        this.trailCrossedReason = "";
        this.pendingBarField = "";
        this.lastAppliedTrailBarField = "";
        this.lastTrailEvaluatedBarField = "";
    }

    /**
     * 時間足や識別文字列の暗黙流用を防ぐ。
     */
    bool isValid() const {
        return this.timeFrame != PERIOD_CURRENT && PeriodSeconds(this.timeFrame) > 0
            && this.actionUidPrefix != "" && this.trailEvaluationUidPrefix != ""
            && this.cancelUidPrefix != "" && this.dealAuditUidPrefix != ""
            && this.recoveryUidPrefix != "" && this.recoverySnapshotPrefix != ""
            && this.pendingMemoryPrefix != "" && this.entryCommentPrefix != ""
            && this.closeCommentPrefix != "" && this.trailStopLossSource != ""
            && this.trailCrossedReason != "" && this.pendingBarField != ""
            && this.lastAppliedTrailBarField != "" && this.lastTrailEvaluatedBarField != "";
    }
};

/**
 * 時間足別の戦略判定と既存運用ログを共通発注処理へ接続する。
 */
class IEaTradePolicy {
public:
    /**
     * 派生実装を安全に破棄する。
     */
    virtual ~IEaTradePolicy() {}

    /**
     * 通貨・実行識別子からログ出力先を初期化する。
     */
    virtual void initialize(const string fromSymbol, const ulong fromMagic,
        const string fromRunUid) = 0;

    /**
     * 戦略固有のトレイル候補を判定する。
     */
    virtual bool evaluateTrail(PositionSnapshot &fromPosition, Wave *fromWave,
        const double fromPipSize, const double fromTickSize, EaTrailDecision &fromResult) = 0;

    /**
     * 既存の決済理由分類を返す。
     */
    virtual string closeReason(const string fromIntent, const string fromStopLossSource,
        const string fromBrokerReason) = 0;

    /**
     * DB障害中も運用ログを記録する。
     */
    virtual void writeLog(const string fromLevel, const string fromMessage) = 0;
};

#endif
