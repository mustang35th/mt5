//+------------------------------------------------------------------+
//|         CurrencyStrengthExecutionInfoProvider.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_CURRENCY_STRENGTH_EXECUTION_INFO_PROVIDER_MQH
#define MSTNG_CURRENCY_STRENGTH_EXECUTION_INFO_PROVIDER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankQueryMode.mqh>

/**
 * EAとインジケータで共有する実行時通貨強弱情報を取得する。
 *
 * 年別データベース接続と同一M5バーの検索結果を保持し、呼び出し元へ
 * 値としてCurrencyStrengthExecutionInfoを返す。
 */
class CurrencyStrengthExecutionInfoProvider {
public:
    /**
     * データベース設定と検索方法を指定して初期化する。
     *
     * @param fromBaseFileName 年を付与する前のファイル名。
     * @param fromSplitByYear 年単位で分割する場合true。
     * @param fromUseCommonFolder 共有フォルダを使用する場合true。
     * @param fromDatabaseProfile 参照元DBプロファイル。
     * @param fromQueryMode 順位の検索方法。
     * @param fromRefreshSeconds ライブ実行中の同一M5バー再検索間隔秒。
     */
    CurrencyStrengthExecutionInfoProvider(
        const string fromBaseFileName,
        const bool fromSplitByYear,
        const bool fromUseCommonFolder,
        const CurrencyStrengthRankDatabaseProfile fromDatabaseProfile,
        const CurrencyStrengthRankQueryMode fromQueryMode,
        const int fromRefreshSeconds = 15
    ) {
        this.databaseProfile = fromDatabaseProfile;
        this.queryMode = fromQueryMode;
        this.refreshSeconds = fromRefreshSeconds;

        if (this.refreshSeconds < 0) {
            this.refreshSeconds = 0;
        }

        this.queryService = new CurrencyStrengthYearlyRankQueryService(
            fromBaseFileName,
            fromSplitByYear,
            fromUseCommonFolder
        );
        this.cacheReady = false;
        this.cachedKey = "";
        this.lastQueryTickCount = 0;
        this.cachedInfo.reset();
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * デストラクタ。
     */
    ~CurrencyStrengthExecutionInfoProvider() {
        this.close();
    }

    /**
     * 指定した実行時刻に対応する通貨ペア順位を取得する。
     *
     * 実行時刻はM5バー開始時刻へ切り下げる。テスターでは同じ検索条件を
     * 再検索せず、ライブでは再検索間隔を経過するまで結果を再利用する。
     *
     * @param fromMarketContext 対象銘柄の市場コンテキスト。
     * @param fromExecutionTime 分析または売買判定の実行時刻。
     * @param fromInfo 取得結果の格納先。
     * @return 実行時通貨強弱情報の取得状態。
     */
    ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS load(
        MarketContext &fromMarketContext,
        const datetime fromExecutionTime,
        CurrencyStrengthExecutionInfo &fromInfo
    ) {
        fromInfo.reset();
        datetime targetM5BarTime = this.floorToM5(fromExecutionTime);
        fromInfo.targetM5BarTime = targetM5BarTime;

        if (targetM5BarTime > 0) {
            fromInfo.targetM5BarTimeText = TimeToString(
                targetM5BarTime,
                TIME_DATE | TIME_MINUTES
            );
        }

        bool runtimeTester = (bool)MQLInfoInteger(MQL_TESTER);
        fromInfo.calculationVersion =
            CurrencyStrengthCalculationProfile::getCalculationVersion(
                runtimeTester
            );

        if (this.queryService == NULL
                || targetM5BarTime <= 0
                || fromMarketContext.symbolName == "") {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR;
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "query condition is invalid. symbol=%s execution=%s",
                    fromMarketContext.symbolName,
                    TimeToString(fromExecutionTime, TIME_DATE | TIME_SECONDS)
                )
            );

            return fromInfo.status;
        }

        string baseCurrency = SymbolInfoString(
            fromMarketContext.symbolName,
            SYMBOL_CURRENCY_BASE
        );
        string quoteCurrency = SymbolInfoString(
            fromMarketContext.symbolName,
            SYMBOL_CURRENCY_PROFIT
        );

        if (baseCurrency == "" || quoteCurrency == "") {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR;
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "symbol currency resolution failed. symbol=%s "
                        + "base=%s quote=%s",
                    fromMarketContext.symbolName,
                    baseCurrency,
                    quoteCurrency
                )
            );

            return fromInfo.status;
        }

        string sourceServer = AccountInfoString(ACCOUNT_SERVER);
        long sourceLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        string cacheKey = this.createCacheKey(
            fromMarketContext.symbolName,
            targetM5BarTime,
            runtimeTester,
            sourceServer,
            sourceLogin,
            fromInfo.calculationVersion
        );

        if (this.canUseCache(cacheKey, runtimeTester)) {
            fromInfo = this.cachedInfo;

            return fromInfo.status;
        }

        if (this.databaseProfile
                == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER) {
            this.loadLiveThenTester(
                targetM5BarTime,
                sourceServer,
                sourceLogin,
                baseCurrency,
                quoteCurrency,
                fromInfo
            );
        } else {
            this.loadSingleProfile(
                targetM5BarTime,
                runtimeTester,
                sourceServer,
                sourceLogin,
                baseCurrency,
                quoteCurrency,
                fromInfo
            );
        }

        if (fromInfo.status == CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND
                && !fromInfo.hasValidRanks()) {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR;
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "currency strength rank is invalid. runId=%I64d "
                        + "base=%s/%d/%d quote=%s/%d/%d",
                    fromInfo.pairRankInfo.runId,
                    fromInfo.pairRankInfo.baseCurrency,
                    fromInfo.pairRankInfo.baseLongMediumTermAverageRank,
                    fromInfo.pairRankInfo.baseMediumShortTermAverageRank,
                    fromInfo.pairRankInfo.quoteCurrency,
                    fromInfo.pairRankInfo.quoteLongMediumTermAverageRank,
                    fromInfo.pairRankInfo.quoteMediumShortTermAverageRank
                )
            );
        }

        this.cachedInfo = fromInfo;
        this.cachedKey = cacheKey;
        this.lastQueryTickCount = GetTickCount64();
        this.cacheReady = true;

        return fromInfo.status;
    }

    /**
     * データベース関連リソースと検索キャッシュを解放する。
     */
    void close() {
        if (this.queryService != NULL) {
            delete this.queryService;
            this.queryService = NULL;
        }

        this.cacheReady = false;
        this.cachedKey = "";
        this.lastQueryTickCount = 0;
        this.cachedInfo.reset();
    }

private:
    /** 年別順位検索サービス。 */
    CurrencyStrengthYearlyRankQueryService *queryService;

    /** 参照元DBプロファイル。 */
    CurrencyStrengthRankDatabaseProfile databaseProfile;

    /** 順位の検索方法。 */
    CurrencyStrengthRankQueryMode queryMode;

    /** ライブ実行中の同一M5バー再検索間隔秒。 */
    int refreshSeconds;

    /** キャッシュが利用可能な場合true。 */
    bool cacheReady;

    /** キャッシュの検索条件キー。 */
    string cachedKey;

    /** キャッシュした実行時通貨強弱情報。 */
    CurrencyStrengthExecutionInfo cachedInfo;

    /** 前回DB検索時の経過ミリ秒。 */
    ulong lastQueryTickCount;

    /** ロガー。 */
    Logger logger;

    /**
     * 1つのDBプロファイルから順位を取得する。
     *
     * @param fromTargetM5BarTime 検索対象M5バー時刻。
     * @param fromRuntimeTester ストラテジーテスターの場合true。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromInfo 取得結果の格納先。
     */
    void loadSingleProfile(
        const datetime fromTargetM5BarTime,
        const bool fromRuntimeTester,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        CurrencyStrengthExecutionInfo &fromInfo
    ) {
        bool useTesterProfile = this.usesTesterDatabaseProfile(
            fromRuntimeTester
        );
        string sourceMode = CurrencyStrengthCalculationProfile::getSourceMode(
            useTesterProfile
        );
        CurrencyStrengthPairRankInfo pairRankInfo;
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS queryStatus =
            this.queryService.findLatestPairRanksAtOrBefore(
                fromTargetM5BarTime,
                fromInfo.calculationVersion,
                sourceMode,
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                pairRankInfo
            );

        string sourceFileName = this.queryService.getActiveFileName();
        fromInfo.sourceMode = sourceMode;
        this.applyQueryResult(queryStatus, pairRankInfo, fromInfo);

        if (fromInfo.status == CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND) {
            CurrencyStrengthRankInfo currencyRanks[];

            if (!this.loadCurrencyRanks(pairRankInfo.runId, currencyRanks)) {
                ArrayResize(currencyRanks, 0);
            }

            this.copyCurrencyRanks(currencyRanks, fromInfo);
            fromInfo.sourceFileName = sourceFileName;
        }
    }

    /**
     * LIVEとTESTERを検索し、新しいM5順位を取得する。
     *
     * 同じM5バー時刻に両方の順位が存在する場合はLIVEを採用する。
     * どちらか一方の検索がエラーの場合は全体をエラーとする。
     *
     * @param fromTargetM5BarTime 検索対象M5バー時刻。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromBaseCurrency 基軸通貨。
     * @param fromQuoteCurrency 決済通貨。
     * @param fromInfo 取得結果の格納先。
     */
    void loadLiveThenTester(
        const datetime fromTargetM5BarTime,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromBaseCurrency,
        const string fromQuoteCurrency,
        CurrencyStrengthExecutionInfo &fromInfo
    ) {
        string liveSourceMode = CurrencyStrengthCalculationProfile::getSourceMode(
            false
        );
        CurrencyStrengthPairRankInfo liveInfo;
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS liveStatus =
            this.queryService.findLatestPairRanksAtOrBefore(
                fromTargetM5BarTime,
                fromInfo.calculationVersion,
                liveSourceMode,
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                liveInfo
            );
        string liveFileName = this.queryService.getActiveFileName();
        liveStatus = this.applyExactMode(liveStatus, liveInfo, fromInfo);
        CurrencyStrengthRankInfo liveRanks[];

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            if (!this.loadCurrencyRanks(liveInfo.runId, liveRanks)) {
                ArrayResize(liveRanks, 0);
            }
        }

        string testerSourceMode =
            CurrencyStrengthCalculationProfile::getSourceMode(true);
        CurrencyStrengthPairRankInfo testerInfo;
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS testerStatus =
            this.queryService.findLatestPairRanksAtOrBefore(
                fromTargetM5BarTime,
                fromInfo.calculationVersion,
                testerSourceMode,
                fromSourceServer,
                fromSourceLogin,
                fromBaseCurrency,
                fromQuoteCurrency,
                testerInfo
            );
        string testerFileName = this.queryService.getActiveFileName();
        testerStatus = this.applyExactMode(testerStatus, testerInfo, fromInfo);
        CurrencyStrengthRankInfo testerRanks[];

        if (testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            if (!this.loadCurrencyRanks(testerInfo.runId, testerRanks)) {
                ArrayResize(testerRanks, 0);
            }
        }

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR
                || testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR;
            fromInfo.sourceMode = "LIVE>TESTER";

            return;
        }

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
                && testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            if (testerInfo.m5BarTime > liveInfo.m5BarTime) {
                fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
                fromInfo.sourceMode = testerSourceMode;
                fromInfo.sourceFileName = testerFileName;
                fromInfo.pairRankInfo = testerInfo;
                this.copyCurrencyRanks(testerRanks, fromInfo);
            } else {
                fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
                fromInfo.sourceMode = liveSourceMode;
                fromInfo.sourceFileName = liveFileName;
                fromInfo.pairRankInfo = liveInfo;
                this.copyCurrencyRanks(liveRanks, fromInfo);
            }

            return;
        }

        if (liveStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
            fromInfo.sourceMode = liveSourceMode;
            fromInfo.sourceFileName = liveFileName;
            fromInfo.pairRankInfo = liveInfo;
            this.copyCurrencyRanks(liveRanks, fromInfo);

            return;
        }

        if (testerStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
            fromInfo.sourceMode = testerSourceMode;
            fromInfo.sourceFileName = testerFileName;
            fromInfo.pairRankInfo = testerInfo;
            this.copyCurrencyRanks(testerRanks, fromInfo);

            return;
        }

        fromInfo.sourceMode = "LIVE>TESTER";

        if (liveStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND
                && testerStatus
                    == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND) {
            fromInfo.status =
                CURRENCY_STRENGTH_EXECUTION_STATUS_DATABASE_NOT_FOUND;

            return;
        }

        fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND;
    }

    /**
     * 現在開いているDBから指定集計の全通貨順位を取得する。
     *
     * 順位が8件に満たない場合は通貨ペア順位を有効なままとし、
     * メール側で不完全データとして表示する。
     *
     * @param fromRunId 取得対象の集計ID。
     * @param fromRanks 取得結果の格納先。
     * @return DB検索に成功した場合true。
     */
    bool loadCurrencyRanks(
        const long fromRunId,
        CurrencyStrengthRankInfo &fromRanks[]
    ) {
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS queryStatus =
            this.queryService.findRanksByRunId(fromRunId, fromRanks);

        if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "currency rank query failed. runId=%I64d",
                    fromRunId
                )
            );

            return false;
        }

        if (queryStatus != CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            ArrayResize(fromRanks, 0);
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "currency ranks were not found. runId=%I64d",
                    fromRunId
                )
            );

            return true;
        }

        int rankCount = ArraySize(fromRanks);

        if (rankCount != 8) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "currency rank count is invalid. runId=%I64d count=%d",
                    fromRunId,
                    rankCount
                )
            );
        }

        return true;
    }

    /**
     * 動的配列の全通貨順位を実行時情報へコピーする。
     *
     * @param fromRanks コピー元の全通貨順位。
     * @param fromInfo コピー先の実行時情報。
     */
    void copyCurrencyRanks(
        CurrencyStrengthRankInfo &fromRanks[],
        CurrencyStrengthExecutionInfo &fromInfo
    ) {
        fromInfo.currencyRankCount = 0;

        for (int i = 0; i < 8; i++) {
            fromInfo.currencyRankInfos[i].reset();
        }

        int rankCount = ArraySize(fromRanks);

        if (rankCount > 8) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "currency rank count exceeded. count=%d",
                    rankCount
                )
            );

            return;
        }

        for (int i = 0; i < rankCount; i++) {
            fromInfo.currencyRankInfos[i] = fromRanks[i];
        }

        fromInfo.currencyRankCount = rankCount;

        if (rankCount == 8 && !fromInfo.hasAllCurrencyRanks()) {
            this.logger.error(
                __FUNCTION__,
                StringFormat(
                    "currency ranks do not match pair ranks. runId=%I64d",
                    fromInfo.pairRankInfo.runId
                )
            );
            fromInfo.currencyRankCount = 0;

            for (int i = 0; i < 8; i++) {
                fromInfo.currencyRankInfos[i].reset();
            }
        }
    }

    /**
     * DAO検索結果を実行時情報へ反映する。
     *
     * @param fromQueryStatus DAO検索結果。
     * @param fromPairRankInfo 取得した通貨ペア順位。
     * @param fromInfo 反映先の実行時情報。
     */
    void applyQueryResult(
        const ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS fromQueryStatus,
        CurrencyStrengthPairRankInfo &fromPairRankInfo,
        CurrencyStrengthExecutionInfo &fromInfo
    ) {
        ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS queryStatus =
            this.applyExactMode(fromQueryStatus, fromPairRankInfo, fromInfo);

        if (queryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND) {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
            fromInfo.pairRankInfo = fromPairRankInfo;

            return;
        }

        if (queryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_DATABASE_NOT_FOUND) {
            fromInfo.status =
                CURRENCY_STRENGTH_EXECUTION_STATUS_DATABASE_NOT_FOUND;

            return;
        }

        if (queryStatus
                == CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND) {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND;

            return;
        }

        fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR;
    }

    /**
     * 完全一致検索時にM5バー時刻が異なる取得結果を未取得へ変換する。
     *
     * @param fromQueryStatus DAO検索結果。
     * @param fromPairRankInfo 取得した通貨ペア順位。
     * @param fromInfo 実行時通貨強弱情報。
     * @return 検索方法を反映した検索結果。
     */
    ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS applyExactMode(
        const ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS fromQueryStatus,
        CurrencyStrengthPairRankInfo &fromPairRankInfo,
        CurrencyStrengthExecutionInfo &fromInfo
    ) {
        if (fromQueryStatus == CURRENCY_STRENGTH_PAIR_RANK_QUERY_FOUND
                && this.queryMode == CURRENCY_STRENGTH_RANK_QUERY_MODE_EXACT
                && fromPairRankInfo.m5BarTime != fromInfo.targetM5BarTime) {
            fromPairRankInfo.reset();

            return CURRENCY_STRENGTH_PAIR_RANK_QUERY_RECORD_NOT_FOUND;
        }

        return fromQueryStatus;
    }

    /**
     * 実行環境と設定からTESTERプロファイルを使用するか判定する。
     *
     * @param fromRuntimeTester ストラテジーテスターの場合true。
     * @return TESTERプロファイルを使用する場合true。
     */
    bool usesTesterDatabaseProfile(const bool fromRuntimeTester) const {
        if (this.databaseProfile
                == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER) {
            return true;
        }

        if (this.databaseProfile
                == CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE) {
            return false;
        }

        return fromRuntimeTester;
    }

    /**
     * 同じ検索条件のキャッシュを利用できるか判定する。
     *
     * @param fromCacheKey 現在の検索条件キー。
     * @param fromRuntimeTester ストラテジーテスターの場合true。
     * @return キャッシュを利用する場合true。
     */
    bool canUseCache(
        const string fromCacheKey,
        const bool fromRuntimeTester
    ) const {
        if (!this.cacheReady || this.cachedKey != fromCacheKey) {
            return false;
        }

        if (fromRuntimeTester) {
            return true;
        }

        if (this.refreshSeconds <= 0) {
            return false;
        }

        ulong refreshMilliseconds = (ulong)this.refreshSeconds * 1000;

        return GetTickCount64() - this.lastQueryTickCount
            < refreshMilliseconds;
    }

    /**
     * DB検索結果を識別するキャッシュキーを作成する。
     *
     * @param fromSymbolName 銘柄名。
     * @param fromTargetM5BarTime 検索対象M5バー時刻。
     * @param fromRuntimeTester ストラテジーテスターの場合true。
     * @param fromSourceServer 集計元の取引サーバー名。
     * @param fromSourceLogin 集計元の口座ログイン番号。
     * @param fromCalculationVersion 集計ルール識別子。
     * @return キャッシュキー。
     */
    string createCacheKey(
        const string fromSymbolName,
        const datetime fromTargetM5BarTime,
        const bool fromRuntimeTester,
        const string fromSourceServer,
        const long fromSourceLogin,
        const string fromCalculationVersion
    ) const {
        return StringFormat(
            "%s|%I64d|%d|%d|%d|%s|%I64d|%s",
            fromSymbolName,
            (long)fromTargetM5BarTime,
            (int)fromRuntimeTester,
            (int)this.databaseProfile,
            (int)this.queryMode,
            fromSourceServer,
            fromSourceLogin,
            fromCalculationVersion
        );
    }

    /**
     * 日時をM5バー開始時刻へ切り下げる。
     *
     * @param fromTime 切り下げ対象時刻。
     * @return M5バー開始時刻。変換できない場合0。
     */
    datetime floorToM5(const datetime fromTime) const {
        int m5Seconds = PeriodSeconds(PERIOD_M5);

        if (fromTime <= 0 || m5Seconds <= 0) {
            return 0;
        }

        long timeSeconds = (long)fromTime;

        return (datetime)(timeSeconds - (timeSeconds % m5Seconds));
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_EXECUTION_INFO_PROVIDER_MQH
