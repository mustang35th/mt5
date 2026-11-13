//+------------------------------------------------------------------+
//|                     CurrencyStrengthRankDeltaHistoryProvider.mqh |
//+------------------------------------------------------------------+
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_RANK_DELTA_HISTORY_PROVIDER_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_DELTA_HISTORY_PROVIDER_MQH

#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>

/**
 * 順位差表示に使うM5順位履歴を読み取り専用で保持する。
 * 欠損時刻は補間せず、取得失敗時は直前のキャッシュを維持する。
 */
class CurrencyStrengthRankDeltaHistoryProvider {
public:
    /** 時刻昇順の履歴。startIndexより前は参照しない。 */
    CurrencyStrengthPairRankPoint points[];

    /** 有効な履歴の先頭位置。 */
    int startIndex;

    /**
     * DB参照先・集計方式・対象通貨を指定する。
     */
    CurrencyStrengthRankDeltaHistoryProvider(
        const string fromFileName, const bool fromSplitByYear,
        const bool fromUseCommonFolder, const CurrencyStrengthRankDatabaseProfile fromProfile,
        const CurrencyStrengthVoteWeightMode fromWeightMode, const bool fromTester,
        const string fromBaseCurrency, const string fromQuoteCurrency
    ) {
        this.queryService = new CurrencyStrengthYearlyRankQueryService(
            fromFileName, fromSplitByYear, fromUseCommonFolder);
        this.preferLive = fromProfile == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
        bool useTester = fromTester;
        if (fromProfile == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER) {
            useTester = true;
        } else if (fromProfile == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE) {
            useTester = false;
        }

        this.calculationVersion = CurrencyStrengthCalculationProfile::getCalculationVersion(
            useTester, fromWeightMode);
        this.sourceMode = CurrencyStrengthCalculationProfile::getSourceMode(useTester);
        this.baseCurrency = fromBaseCurrency;
        this.quoteCurrency = fromQuoteCurrency;
        this.startIndex = 0;
        this.cacheStartM5Time = 0;
        this.targetM5Time = 0;
        this.ready = false;
        this.error = false;
        this.statusText = "未取得";
    }

    /**
     * DBと履歴を解放する。
     */
    ~CurrencyStrengthRankDeltaHistoryProvider() {
        this.close();
    }

    /**
     * 初回・強制・期間拡張・時刻巻戻りでは全範囲、それ以外は末尾から取得する。
     * 呼出間隔は利用側で管理する。管理情報だけの更新では表示変更を通知しない。
     *
     * @param fromCacheStartM5Time 保持開始M5時刻。
     * @param fromTargetM5Time 検索上限のM5時刻。
     * @param fromForce 全範囲を再取得する場合true。
     * @param fromChangedStartM5Time 表示変更がある範囲の開始時刻。
     * @param fromChanged 時刻・順位・取得元が変わった場合、または初回取得時はtrue。
     * @return 取得とキャッシュ更新が成功した場合true。正常な0件も含む。
     */
    bool refresh(const datetime fromCacheStartM5Time, const datetime fromTargetM5Time,
            const bool fromForce, datetime &fromChangedStartM5Time, bool &fromChanged) {
        fromChangedStartM5Time = fromTargetM5Time;
        fromChanged = false;
        this.error = false;
        if (this.queryService == NULL || this.baseCurrency == "" || this.quoteCurrency == ""
                || fromCacheStartM5Time <= 0 || fromTargetM5Time < fromCacheStartM5Time
                || fromCacheStartM5Time % 300 != 0 || fromTargetM5Time % 300 != 0) {
            return this.fail("参照条件エラー");
        }

        datetime queryStartM5Time = fromCacheStartM5Time;
        int cachedCount = ArraySize(this.points) - this.startIndex;
        if (!fromForce && this.ready && cachedCount > 0
                && fromCacheStartM5Time >= this.cacheStartM5Time
                && fromTargetM5Time >= this.targetM5Time) {
            datetime lastTime = this.points[ArraySize(this.points) - 1].m5BarTime;
            if (lastTime >= fromCacheStartM5Time && lastTime <= fromTargetM5Time) {
                queryStartM5Time = lastTime;
            }
        }

        long maximumPointCount = ((long)fromTargetM5Time - (long)queryStartM5Time) / 300 + 2;
        if (maximumPointCount > 2147483647) {
            return this.fail("取得範囲エラー");
        }

        CurrencyStrengthPairRankPoint queriedPoints[];
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS queryStatus;
        string sourceServer = AccountInfoString(ACCOUNT_SERVER);
        long sourceLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        if (this.preferLive) {
            queryStatus = this.queryService.findPairRankPointsInRangePreferLive(
                queryStartM5Time, fromTargetM5Time, this.calculationVersion, sourceServer, sourceLogin,
                this.baseCurrency, this.quoteCurrency, (int)maximumPointCount, queriedPoints);
        } else {
            queryStatus = this.queryService.findPairRankPointsInRange(
                queryStartM5Time, fromTargetM5Time, this.calculationVersion, this.sourceMode,
                sourceServer, sourceLogin, this.baseCurrency, this.quoteCurrency,
                (int)maximumPointCount, queriedPoints);
        }

        if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            return this.fail("取得失敗");
        }

        if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND) {
            return this.fail("DB未検出");
        }

        bool rangeChanged = false;
        if (!this.replaceRange(queryStartM5Time, queriedPoints, rangeChanged)) {
            return this.fail("履歴のメモリ確保失敗");
        }

        bool initialLoad = !this.ready;
        // 表示期間から外れたバッファの消去は利用側で行い、前詰めだけでは再計算しない。
        this.prune(fromCacheStartM5Time);
        fromChanged = rangeChanged || initialLoad;
        if (rangeChanged) {
            fromChangedStartM5Time = queryStartM5Time;
        }

        if (initialLoad) {
            fromChangedStartM5Time = fromCacheStartM5Time;
        }

        this.ready = true;
        this.cacheStartM5Time = fromCacheStartM5Time;
        this.targetM5Time = fromTargetM5Time;
        this.statusText = "取得済み";
        if (ArraySize(this.points) == this.startIndex) {
            this.statusText = "履歴なし";
        }

        return true;
    }

    /**
     * 正常な取得が一度以上完了しているか返す。
     */
    bool isReady() const { return this.ready; }

    /**
     * 直近の取得またはキャッシュ更新が失敗したか返す。
     */
    bool hasError() const { return this.error; }

    /**
     * 直近の取得状態を返す。
     */
    string getStatusText() const { return this.statusText; }

    /**
     * 保持履歴を維持してDBハンドルだけを閉じ、次回検索で開き直す。
     */
    void reopenDatabase() {
        if (this.queryService != NULL) {
            this.queryService.close();
        }
    }

    /**
     * DBと履歴を解放する。解放後は再取得せず、新しいインスタンスを使用する。
     */
    void close() {
        if (this.queryService != NULL) {
            delete this.queryService;
            this.queryService = NULL;
        }

        ArrayFree(this.points);
        this.startIndex = 0;
        this.ready = false;
        this.error = false;
        this.statusText = "未取得";
    }

private:
    /** 年別DBの読み取り専用検索。 */
    CurrencyStrengthYearlyRankQueryService *queryService;

    /** 同一時刻はLIVEを優先する場合true。 */
    bool preferLive;

    /** 集計ルールと重み付け方式の識別子。 */
    string calculationVersion;

    /** 単一参照時の実行モード。 */
    string sourceMode;

    /** 基軸通貨。 */
    string baseCurrency;

    /** 決済通貨。 */
    string quoteCurrency;

    /** 最後に正常取得した保持開始時刻。 */
    datetime cacheStartM5Time;

    /** 最後に正常取得した検索上限時刻。 */
    datetime targetM5Time;

    /** 正常な取得済みの場合true。0件も含む。 */
    bool ready;

    /** 直近の処理が失敗した場合true。 */
    bool error;

    /** 直近の取得状態。 */
    string statusText;

    /**
     * 保持履歴を変更せず、失敗状態を設定する。
     */
    bool fail(const string fromText) {
        this.error = true;
        this.statusText = fromText;
        if (this.ready) {
            this.statusText += "（前回履歴を保持）";
        }

        return false;
    }

    /**
     * 指定時刻以上の最初の有効位置を二分探索する。
     */
    int lowerBound(const datetime fromTime) const {
        int leftIndex = this.startIndex;
        int rightIndex = ArraySize(this.points);
        while (leftIndex < rightIndex) {
            int middleIndex = leftIndex + (rightIndex - leftIndex) / 2;
            if (this.points[middleIndex].m5BarTime < fromTime) {
                leftIndex = middleIndex + 1;
            } else {
                rightIndex = middleIndex;
            }
        }

        return leftIndex;
    }

    /**
     * 表示・ツールチップに使う集計の有効性・時刻・両期間順位・取得元を比較する。
     */
    bool sameDisplay(const CurrencyStrengthPairRankPoint &fromLeft,
            const CurrencyStrengthPairRankPoint &fromRight) const {
        return (fromLeft.runId > 0) == (fromRight.runId > 0)
            && fromLeft.m5BarTime == fromRight.m5BarTime
            && fromLeft.sourceMode == fromRight.sourceMode
            && fromLeft.baseLongMediumTermAverageRank == fromRight.baseLongMediumTermAverageRank
            && fromLeft.baseMediumShortTermAverageRank == fromRight.baseMediumShortTermAverageRank
            && fromLeft.quoteLongMediumTermAverageRank == fromRight.quoteLongMediumTermAverageRank
            && fromLeft.quoteMediumShortTermAverageRank == fromRight.quoteMediumShortTermAverageRank;
    }

    /**
     * 管理情報を含むすべての値を比較する。
     */
    bool samePoint(const CurrencyStrengthPairRankPoint &fromLeft,
            const CurrencyStrengthPairRankPoint &fromRight) const {
        return fromLeft.runId == fromRight.runId && fromLeft.updatedAt == fromRight.updatedAt
            && this.sameDisplay(fromLeft, fromRight);
    }

    /**
     * 末尾範囲の変更点だけをコピーし、管理情報と表示の変更を区別する。
     * 容量は288件単位の余裕を確保し、確保失敗時は元の配列を維持する。
     */
    bool replaceRange(const datetime fromTime, CurrencyStrengthPairRankPoint &fromPoints[],
            bool &fromChanged) {
        int cachedSize = ArraySize(this.points);
        int replaceIndex = this.lowerBound(fromTime);
        int queryCount = ArraySize(fromPoints);
        int nextSize = replaceIndex + queryCount;
        fromChanged = nextSize != cachedSize;
        if (nextSize != cachedSize && ArrayResize(this.points, nextSize, 288) != nextSize) {
            return false;
        }

        for (int i = 0; i < queryCount; i++) {
            int pointIndex = replaceIndex + i;
            if (pointIndex < cachedSize) {
                if (this.samePoint(this.points[pointIndex], fromPoints[i])) {
                    continue;
                }

                if (!this.sameDisplay(this.points[pointIndex], fromPoints[i])) {
                    fromChanged = true;
                }
            } else {
                fromChanged = true;
            }

            this.points[pointIndex] = fromPoints[i];
        }

        return true;
    }

    /**
     * 期限切れを参照対象から外し、288件以上または有効件数以上で前詰めする。
     */
    void prune(const datetime fromTime) {
        this.startIndex = this.lowerBound(fromTime);
        if (this.startIndex <= 0) {
            return;
        }

        int nextCount = ArraySize(this.points) - this.startIndex;
        if (nextCount <= 0) {
            ArrayFree(this.points);
            this.startIndex = 0;

            return;
        }

        if (this.startIndex < 288 && this.startIndex < nextCount) {
            return;
        }

        for (int i = 0; i < nextCount; i++) {
            this.points[i] = this.points[this.startIndex + i];
        }

        if (ArrayResize(this.points, nextCount) != nextCount) {
            for (int i = nextCount - 1; i >= 0; i--) {
                this.points[this.startIndex + i] = this.points[i];
            }

            return;
        }

        this.startIndex = 0;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_DELTA_HISTORY_PROVIDER_MQH
