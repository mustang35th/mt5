#ifndef MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_PROVIDER_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_PROVIDER_MQH

#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDeltaHistoryProvider.mqh>
#include <Mstng\Strength\CurrencyStrengthRankGapDirectionEvaluator.mqh>
#include <Mstng\Strength\CurrencyStrengthRankGapDirectionInfo.mqh>

/**
 * 両集計期間の増減情報に使う過去M5履歴を保持し、現在の分析順位と組み合わせる。
 * 現在値をDBから重複取得せず、同じM5内の履歴再取得間隔を守る。
 */
class CurrencyStrengthRankGapDirectionProvider {
public:
    /**
     * 履歴参照条件と再確認間隔を保持する。実際の履歴取得はload時に行う。
     */
    CurrencyStrengthRankGapDirectionProvider(const string fromFileName,
            const bool fromSplitByYear, const bool fromUseCommonFolder,
            const CurrencyStrengthRankDatabaseProfile fromProfile,
            const CurrencyStrengthVoteWeightMode fromWeightMode, const bool fromTester,
            const string fromBaseCurrency, const string fromQuoteCurrency,
            const int fromRefreshSeconds) {
        this.fileName = fromFileName;
        this.splitByYear = fromSplitByYear;
        this.useCommonFolder = fromUseCommonFolder;
        this.profile = fromProfile;
        this.weightMode = fromWeightMode;
        this.tester = fromTester;
        this.baseCurrency = fromBaseCurrency;
        this.quoteCurrency = fromQuoteCurrency;
        this.refreshMilliseconds = (ulong)MathMax(1, fromRefreshSeconds) * 1000;
        this.calculationVersion = CurrencyStrengthCalculationProfile::getCalculationVersion(
            fromTester, fromWeightMode);
        this.history = NULL;
        this.sourceServer = "";
        this.sourceLogin = 0;
        this.lastQueryTarget = 0;
        this.lastQueryTicks = 0;
        this.querySucceeded = false;
        this.cachedResultReady = false;
        this.cachedResult.reset();
        this.historyRevision = 0;
        this.cachedMediumShortResultReady = false;
        this.cachedMediumShortHistoryRevision = 0;
        this.cachedMediumShortResult.reset();
    }

    /**
     * 保持履歴とDB接続を解放する。
     */
    ~CurrencyStrengthRankGapDirectionProvider() {
        this.releaseHistory();
    }

    /**
     * 現在順位と同じ対象M5に対する過去履歴を取得し、増減方向を返す。
     * 取得失敗時も試行時刻を保持し、次回の取得間隔まではSQLを繰り返さない。
     *
     * @param fromExecutionInfo 今回の分析に採用した現在順位。
     * @param fromResult 取得状態を含む長中期増減判定。
     */
    void load(const CurrencyStrengthExecutionInfo &fromExecutionInfo,
            CurrencyStrengthRankGapDirectionInfo &fromResult) {
        fromResult.reset();
        fromResult.enabled = true;
        fromResult.waiting = true;
        datetime targetTime = fromExecutionInfo.targetM5BarTime;
        fromResult.targetM5BarTime = targetTime;
        if (targetTime <= 300 || targetTime % 300 != 0 || !fromExecutionInfo.isExactM5Bar()
                || fromExecutionInfo.pairRankInfo.runId <= 0
                || fromExecutionInfo.pairRankInfo.baseCurrency != this.baseCurrency
                || fromExecutionInfo.pairRankInfo.quoteCurrency != this.quoteCurrency
                || fromExecutionInfo.calculationVersion != this.calculationVersion) {
            return;
        }

        fromResult.currentAvailable = true;
        fromResult.currentGap = fromExecutionInfo.getLongMediumRankDifference();
        if (!this.prepareHistory()) {
            return;
        }

        ulong nowTicks = GetTickCount64();
        bool historyChanged = false;
        if (this.lastQueryTarget != targetTime
                || (!this.tester && nowTicks - this.lastQueryTicks >= this.refreshMilliseconds)) {
            this.lastQueryTarget = targetTime;
            this.lastQueryTicks = nowTicks;
            datetime firstTime = (datetime)MathMax(300, (long)targetTime - 30 * 86400);
            datetime changedStart = 0;
            // 現在枠は実行時情報だけを使う。履歴側の取得上限は必ず直前M5とする。
            this.querySucceeded = this.history.refresh(firstTime, targetTime - 300,
                false, changedStart, historyChanged);
            if (this.querySucceeded && historyChanged) {
                this.historyRevision++;
            }
        }

        if (!this.querySucceeded) {
            return;
        }

        if (this.cachedResultReady && !historyChanged
                && this.cachedResult.targetM5BarTime == targetTime
                && this.cachedResult.currentGap == fromResult.currentGap) {
            fromResult = this.cachedResult;

            return;
        }

        CurrencyStrengthRankGapDirectionEvaluator::evaluate(this.history.points,
            this.history.startIndex, fromExecutionInfo, fromResult);
        this.cachedResult = fromResult;
        this.cachedResultReady = true;
    }

    /**
     * 1回の履歴取得を共用し、長中期と中短期を独立に評価する。
     * 片方の過去順位が欠損していても、他方の有効な結果を保持する。
     *
     * @param fromExecutionInfo 今回の分析に採用した現在順位。
     * @param fromLongMediumResult 長中期の増減情報。
     * @param fromMediumShortResult 中短期の増減情報。
     */
    void load(const CurrencyStrengthExecutionInfo &fromExecutionInfo,
            CurrencyStrengthRankGapDirectionInfo &fromLongMediumResult,
            CurrencyStrengthRankGapDirectionInfo &fromMediumShortResult) {
        this.load(fromExecutionInfo, fromLongMediumResult);
        fromMediumShortResult.reset();
        fromMediumShortResult.enabled = true;
        fromMediumShortResult.waiting = true;
        fromMediumShortResult.targetM5BarTime = fromExecutionInfo.targetM5BarTime;
        if (!fromLongMediumResult.currentAvailable) {
            return;
        }

        fromMediumShortResult.currentAvailable = true;
        fromMediumShortResult.currentGap = fromExecutionInfo.getMediumShortRankDifference();
        if (this.history == NULL || !this.querySucceeded
                || this.lastQueryTarget != fromExecutionInfo.targetM5BarTime) {
            return;
        }

        if (this.cachedMediumShortResultReady
                && this.cachedMediumShortHistoryRevision == this.historyRevision
                && this.cachedMediumShortResult.targetM5BarTime == fromExecutionInfo.targetM5BarTime
                && this.cachedMediumShortResult.currentGap == fromMediumShortResult.currentGap) {
            fromMediumShortResult = this.cachedMediumShortResult;

            return;
        }

        CurrencyStrengthRankGapDirectionEvaluator::evaluate(this.history.points,
            this.history.startIndex, fromExecutionInfo, fromMediumShortResult, false);
        this.cachedMediumShortResult = fromMediumShortResult;
        this.cachedMediumShortResultReady = true;
        this.cachedMediumShortHistoryRevision = this.historyRevision;
    }

private:
    /** 年なしの履歴DBファイル名。 */
    string fileName;

    /** 年別履歴DBを使用する場合true。 */
    bool splitByYear;

    /** MT5共通フォルダを使用する場合true。 */
    bool useCommonFolder;

    /** LIVE・TESTERの参照規則。 */
    CurrencyStrengthRankDatabaseProfile profile;

    /** 現在順位と同じ票重み付け方式。 */
    CurrencyStrengthVoteWeightMode weightMode;

    /** テスターでは同じM5内のSQL再取得を省く。 */
    bool tester;

    /** 基軸通貨コード。 */
    string baseCurrency;

    /** 決済通貨コード。 */
    string quoteCurrency;

    /** 同じM5内での履歴再取得間隔。 */
    ulong refreshMilliseconds;

    /** 現在順位との整合確認に使う集計方式。 */
    string calculationVersion;

    /** 過去30日を保持し、通常は末尾だけ再取得する履歴管理。 */
    CurrencyStrengthRankDeltaHistoryProvider *history;

    /** 保持履歴を取得したサーバー名。 */
    string sourceServer;

    /** 保持履歴を取得した口座番号。 */
    long sourceLogin;

    /** 最後に過去履歴の取得を試みた現在M5時刻。 */
    datetime lastQueryTarget;

    /** 最後に過去履歴の取得を試みた経過ミリ秒。 */
    ulong lastQueryTicks;

    /** 最後の履歴取得が成功した場合true。正常な0件も含む。 */
    bool querySucceeded;

    /** 現在値・履歴が同じ場合に再利用する増減判定。 */
    CurrencyStrengthRankGapDirectionInfo cachedResult;

    /** 同じ対象M5・順位差で判定結果を再利用できる場合true。 */
    bool cachedResultReady;

    /** 長中期だけを評価した間の履歴変更も、中短期のキャッシュへ伝える更新番号。 */
    ulong historyRevision;

    /** 中短期の現在値・対象M5・履歴が同じ場合に再利用する増減情報。 */
    CurrencyStrengthRankGapDirectionInfo cachedMediumShortResult;

    /** 中短期の判定結果を再利用できる場合true。 */
    bool cachedMediumShortResultReady;

    /** 中短期の判定結果に反映済みの履歴更新番号。 */
    ulong cachedMediumShortHistoryRevision;

    /**
     * サーバー・口座が変わった場合に古い履歴を捨て、現在環境用に作り直す。
     */
    bool prepareHistory() {
        string currentServer = AccountInfoString(ACCOUNT_SERVER);
        long currentLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        if (this.history != NULL
                && (this.sourceServer != currentServer || this.sourceLogin != currentLogin)) {
            this.releaseHistory();
        }

        if (this.history == NULL) {
            this.history = new CurrencyStrengthRankDeltaHistoryProvider(this.fileName,
                this.splitByYear, this.useCommonFolder, this.profile, this.weightMode,
                this.tester, this.baseCurrency, this.quoteCurrency);
            this.sourceServer = currentServer;
            this.sourceLogin = currentLogin;
        }

        return this.history != NULL;
    }

    /**
     * インスタンスが所有する履歴だけを解放し、取得状態を初期化する。
     */
    void releaseHistory() {
        if (this.history != NULL) {
            delete this.history;
            this.history = NULL;
        }

        this.lastQueryTarget = 0;
        this.lastQueryTicks = 0;
        this.querySucceeded = false;
        this.cachedResultReady = false;
        this.cachedResult.reset();
        this.historyRevision = 0;
        this.cachedMediumShortResultReady = false;
        this.cachedMediumShortHistoryRevision = 0;
        this.cachedMediumShortResult.reset();
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_GAP_DIRECTION_PROVIDER_MQH
