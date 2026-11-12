//+------------------------------------------------------------------+
//|                    CurrencyStrengthTrendContinuationProvider.mqh |
//+------------------------------------------------------------------+
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_PROVIDER_MQH
#define MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_PROVIDER_MQH

#include <Mstng\Database\Service\CurrencyStrengthYearlyRankQueryService.mqh>
#include <Mstng\Strength\CurrencyStrengthEntryCandidateList.mqh>

/**
 * 継続候補用の直近3時間の全通貨順位を読み取り専用で保持する。
 * M5更新時に一括取得し、履歴不足・取得失敗時だけ60秒後に再試行する。
 */
class CurrencyStrengthTrendContinuationProvider {
public:
    /**
     * 既存のDB保存設定と同じ参照先・集計方式で初期化する。
     */
    CurrencyStrengthTrendContinuationProvider(const string fromFileName,
            const bool fromSplitByYear, const bool fromUseCommonFolder,
            const CurrencyStrengthVoteWeightMode fromVoteWeightMode,
            const string fromSourceServer, const long fromSourceLogin) {
        this.queryService = new CurrencyStrengthYearlyRankQueryService(
            fromFileName, fromSplitByYear, fromUseCommonFolder);
        this.calculationVersion = CurrencyStrengthCalculationProfile::getCalculationVersion(false, fromVoteWeightMode);
        this.sourceServer = fromSourceServer;
        this.sourceLogin = fromSourceLogin;
        this.targetM5BarTime = 0;
        this.lastAttemptTick = 0;
        this.querySucceeded = false;
        this.historyComplete = false;
    }

    /**
     * 読み取り専用DBと保持履歴を解放する。
     */
    ~CurrencyStrengthTrendContinuationProvider() {
        if (this.queryService != NULL) {
            delete this.queryService;
        }
    }

    /**
     * 履歴を必要時だけ取得し、再構築された現在候補へ判定結果を付与する。
     * 現在M5の順位は保存前の候補から評価し、DBは直前M5までを取得する。
     *
     * @return DB照会が正常な場合true。履歴不足は正常な未成立として扱う。
     */
    bool update(CurrencyStrengthEntryCandidateList *fromCandidates, const datetime fromTargetM5BarTime) {
        if (fromCandidates == NULL) {
            return false;
        }

        if (this.queryService == NULL || fromTargetM5BarTime < 10800
                || fromTargetM5BarTime % 300 != 0 || !fromCandidates.isRankingReady()) {
            fromCandidates.clearContinuation();

            return false;
        }

        ulong nowTick = GetTickCount64();
        bool targetChanged = this.targetM5BarTime != fromTargetM5BarTime;
        if (targetChanged || (!this.historyComplete && nowTick - this.lastAttemptTick >= 60000)) {
            this.targetM5BarTime = fromTargetM5BarTime;
            this.querySucceeded = false;
            this.historyComplete = false;
            ENUM_CURRENCY_STRENGTH_PAIR_RANK_QUERY_STATUS status =
                this.queryService.findAllRankPointsInRangePreferLive(
                    fromTargetM5BarTime - 10800, fromTargetM5BarTime - 300,
                    this.calculationVersion, this.sourceServer, this.sourceLogin, 36, this.points);
            this.lastAttemptTick = GetTickCount64();
            this.querySucceeded = status != CURRENCY_STRENGTH_PAIR_RANK_QUERY_ERROR;
            if (this.querySucceeded && ArraySize(this.points) == 36) {
                this.historyComplete = true;
                for (int i = 0; i < 36; i++) {
                    if (this.points[i].m5BarTime != fromTargetM5BarTime - 10800 + i * 300
                            || !this.points[i].isValid()) {
                        this.historyComplete = false;
                        break;
                    }
                }
            }
        }

        if (!this.querySucceeded) {
            fromCandidates.clearContinuation();

            return false;
        }

        fromCandidates.updateContinuation(this.points, fromTargetM5BarTime);

        return true;
    }

private:
    /** 読み取り専用の年別履歴検索。 */
    CurrencyStrengthYearlyRankQueryService *queryService;

    /** 同一M5時刻のLIVEを優先して統合した全8通貨順位。 */
    CurrencyStrengthAllRankPoint points[];

    /** 参照する集計方式・ルールの識別子。 */
    string calculationVersion;

    /** 参照元取引サーバー。 */
    string sourceServer;

    /** 参照元口座番号。 */
    long sourceLogin;

    /** 最後に照会した現在M5時刻。 */
    datetime targetM5BarTime;

    /** 最後の照会完了時の単調増加ミリ秒。 */
    ulong lastAttemptTick;

    /** 最後の照会がエラーなく終了した場合true。 */
    bool querySucceeded;

    /** 連続時間境界を含む36件の履歴が揃っている場合true。 */
    bool historyComplete;
};

#endif // MSTNG_CURRENCY_STRENGTH_TREND_CONTINUATION_PROVIDER_MQH
