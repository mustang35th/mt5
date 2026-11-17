#ifndef MSTNG_CURRENCY_STRENGTH_ENTRY_GAP_DIRECTION_PROVIDER_MQH
#define MSTNG_CURRENCY_STRENGTH_ENTRY_GAP_DIRECTION_PROVIDER_MQH

#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidateList.mqh>

/**
 * 候補一覧の両集計期間の増減判定に使う、過去30日の全通貨M5順位を共通で保持する。
 * 初回は全範囲、以後は末尾だけを更新し、同じM5では取得不足時だけ再照会する。
 */
class CurrencyStrengthEntryGapDirectionProvider {
public:
    /**
     * 現在順位と同じDB参照先・集計方式・口座条件を保持する。
     */
    CurrencyStrengthEntryGapDirectionProvider(const string fromFileName,
            const bool fromSplitByYear, const bool fromUseCommonFolder,
            const CurrencyStrengthVoteWeightMode fromVoteWeightMode,
            const string fromSourceServer, const long fromSourceLogin, const bool fromTester) {
        this.queryService = new CurrencyStrengthYearlyRankQueryService(
            fromFileName, fromSplitByYear, fromUseCommonFolder);
        this.calculationVersion = CurrencyStrengthCalculationProfile::getCalculationVersion(
            fromTester, fromVoteWeightMode);
        this.sourceServer = fromSourceServer;
        this.sourceLogin = fromSourceLogin;
        this.accountServer = AccountInfoString(ACCOUNT_SERVER);
        this.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        this.tester = fromTester;
        this.clearHistory();
    }

    /**
     * 保持している読み取り専用DBと履歴を解放する。
     */
    ~CurrencyStrengthEntryGapDirectionProvider() {
        if (this.queryService != NULL) {
            delete this.queryService;
        }
    }

    /**
     * 過去履歴を必要時だけ更新し、毎回の現在候補へ選択期間の増減方向を設定する。
     * 現在M5のDB点を読まず、同じM5の現在順位の訂正も候補から再評価する。
     *
     * @param fromCandidates 現在の順位から再構築した候補一覧。
     * @param fromTargetM5BarTime 現在候補のM5足開始時刻。
     * @param fromMode 増減判定に使用する集計期間。OFFでは履歴を照会しない。
     * @return DB照会が正常な場合true。履歴不足による未成立も正常とする。
     */
    bool update(CurrencyStrengthEntryCandidateList *fromCandidates, const datetime fromTargetM5BarTime,
            const CurrencyStrengthEntryGapMode fromMode = currencyStrengthEntryGapLongMedium) {
        if (fromCandidates == NULL) {
            return false;
        }

        if (fromMode == currencyStrengthEntryGapOff) {
            fromCandidates.clearGapDirections();

            return true;
        }

        if (this.queryService == NULL || fromTargetM5BarTime <= 300
                || fromTargetM5BarTime % 300 != 0 || !fromCandidates.isRankingReady()
                || (fromMode != currencyStrengthEntryGapLongMedium
                    && fromMode != currencyStrengthEntryGapMediumShort
                    && fromMode != currencyStrengthEntryGapBoth)) {
            fromCandidates.clearGapDirections();

            return false;
        }

        this.prepareAccount();
        if (this.targetM5BarTime > fromTargetM5BarTime) {
            this.clearHistory();
        }

        if (fromCandidates.size() == 0) {
            return true;
        }

        ulong nowTick = GetTickCount64();
        bool targetChanged = this.targetM5BarTime != fromTargetM5BarTime;
        bool retry = !this.tester && this.retryNeeded
            && nowTick - this.lastAttemptTick >= 60000;
        if (targetChanged || retry) {
            this.targetM5BarTime = fromTargetM5BarTime;
            this.querySucceeded = this.refresh(fromTargetM5BarTime);
            this.lastAttemptTick = GetTickCount64();
            this.retryNeeded = !this.querySucceeded || !this.hasPrevious(fromTargetM5BarTime);
        }

        if (!this.querySucceeded) {
            fromCandidates.clearGapDirections();

            return false;
        }

        fromCandidates.updateGapDirections(this.points, fromTargetM5BarTime, fromMode);

        return true;
    }

private:
    /** 全通貨順位を読み取り専用で取得する年別履歴検索。 */
    CurrencyStrengthYearlyRankQueryService *queryService;

    /** 時刻昇順の共通履歴。現在・未来の順位は保持しない。 */
    CurrencyStrengthAllRankPoint points[];

    /** 現在順位と同じ集計ルールと重み付け方式。 */
    string calculationVersion;

    /** 履歴取得条件の取引サーバー名。 */
    string sourceServer;

    /** 履歴取得条件の口座番号。 */
    long sourceLogin;

    /** 口座切り替えを検出する直前の稼働サーバー名。 */
    string accountServer;

    /** 口座切り替えを検出する直前の稼働口座番号。 */
    long accountLogin;

    /** テスターでは同じM5内の再取得を省く。 */
    bool tester;

    /** 最後に照会を試みた現在M5時刻。 */
    datetime targetM5BarTime;

    /** 正常に取得した履歴範囲の末尾時刻。0件の場合も記録する。 */
    datetime historyEndTime;

    /** 最後の照会完了時の単調増加ミリ秒。 */
    ulong lastAttemptTick;

    /** 初回の履歴取得に成功し、末尾更新を利用できる場合true。 */
    bool historyReady;

    /** 最後の履歴照会に成功した場合true。正常な0件も含む。 */
    bool querySucceeded;

    /** 取得失敗または直前M5不足により再確認が必要な場合true。 */
    bool retryNeeded;

    /**
     * 口座が変わった場合は前口座の履歴を捨て、新口座の条件に切り替える。
     */
    void prepareAccount() {
        string currentServer = AccountInfoString(ACCOUNT_SERVER);
        long currentLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        if (this.accountServer == currentServer && this.accountLogin == currentLogin) {
            return;
        }

        this.clearHistory();
        this.accountServer = currentServer;
        this.accountLogin = currentLogin;
        this.sourceServer = currentServer;
        this.sourceLogin = currentLogin;
    }

    /**
     * 初回と失敗後は30日分、通常は直前取得末尾を含む範囲を再取得する。
     */
    bool refresh(const datetime fromTargetM5BarTime) {
        datetime firstTime = (datetime)MathMax(300, (long)fromTargetM5BarTime - 30 * 86400);
        datetime lastTime = fromTargetM5BarTime - 300;
        datetime queryStartTime = firstTime;
        int pointCount = ArraySize(this.points);
        if (this.historyReady && pointCount > 0
                && this.historyEndTime >= firstTime && this.historyEndTime <= lastTime
                && this.points[pointCount - 1].m5BarTime >= firstTime) {
            queryStartTime = this.points[pointCount - 1].m5BarTime;
        }

        int maximumPointCount = (int)((lastTime - queryStartTime) / 300) + 1;
        CurrencyStrengthAllRankPoint queriedPoints[];
        // DB再作成・削除時に、前回開いた接続を再利用しない。
        this.queryService.close();
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS status =
            this.queryService.findAllRankPointsInRangePreferLive(
                queryStartTime, lastTime, this.calculationVersion,
                this.sourceServer, this.sourceLogin, maximumPointCount, queriedPoints);
        if (status == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR
                || status == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND
                || !this.replaceHistory(firstTime, queryStartTime, queriedPoints)) {
            ArrayResize(this.points, 0);
            this.historyReady = false;
            this.historyEndTime = 0;

            return false;
        }

        this.historyReady = true;
        this.historyEndTime = lastTime;

        return true;
    }

    /**
     * 30日より古い点を除き、再取得範囲の点を取得結果へ置き換える。
     */
    bool replaceHistory(const datetime fromFirstTime, const datetime fromQueryStartTime,
            const CurrencyStrengthAllRankPoint &fromQueriedPoints[]) {
        int pointCount = ArraySize(this.points);
        int firstIndex = 0;
        while (firstIndex < pointCount && this.points[firstIndex].m5BarTime < fromFirstTime) {
            firstIndex++;
        }

        int retainedCount = 0;
        for (int i = firstIndex; i < pointCount; i++) {
            if (this.points[i].m5BarTime >= fromQueryStartTime) {
                break;
            }

            if (retainedCount != i) {
                this.points[retainedCount] = this.points[i];
            }

            retainedCount++;
        }

        int queriedCount = ArraySize(fromQueriedPoints);
        int totalCount = retainedCount + queriedCount;
        if (ArrayResize(this.points, totalCount) != totalCount) {
            return false;
        }

        for (int i = 0; i < queriedCount; i++) {
            this.points[retainedCount + i] = fromQueriedPoints[i];
        }

        return true;
    }

    /**
     * 共通履歴に全8通貨の有効な直前M5が揃っているか判定する。
     */
    bool hasPrevious(const datetime fromTargetM5BarTime) {
        int pointCount = ArraySize(this.points);
        if (pointCount == 0) {
            return false;
        }

        return this.points[pointCount - 1].m5BarTime == fromTargetM5BarTime - 300
            && this.points[pointCount - 1].isValid();
    }

    /**
     * 履歴・照会状態とDB接続を初期化する。
     */
    void clearHistory() {
        ArrayResize(this.points, 0);
        this.targetM5BarTime = 0;
        this.historyEndTime = 0;
        this.lastAttemptTick = 0;
        this.historyReady = false;
        this.querySucceeded = false;
        this.retryNeeded = true;
        if (this.queryService != NULL) {
            this.queryService.close();
        }
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_ENTRY_GAP_DIRECTION_PROVIDER_MQH
