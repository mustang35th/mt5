#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_STRENGTH_SNAPSHOT_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_STRENGTH_SNAPSHOT_MQH

#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthRankGapDirectionInfo.mqh>

/**
 * 監視一覧に表示する通貨ペア順位と両期間の増減情報だけを保持する。
 * 順位の有効性は期間ごとに判定し、取得待ちと方向不明を区別する。
 */
struct ZigZagElliotMonitorStrengthSnapshot {
public:
    /** 今回の対象M5について取得結果を受け取った場合true。 */
    bool queried;

    /** 対象M5と通貨名が一致する取得済みレコードを保持する場合true。 */
    bool recordAvailable;

    /** 取得を試みた対象M5開始時刻。 */
    datetime targetM5BarTime;

    /** 取得結果を受け取ったサーバー時刻。 */
    datetime retrievedAtSrv;

    /** 表示対象通貨ペアの順位。 */
    CurrencyStrengthPairRankInfo pairRankInfo;

    /** 長中期の順位差増減情報。 */
    CurrencyStrengthRankGapDirectionInfo longMediumGapDirection;

    /** 中短期の順位差増減情報。 */
    CurrencyStrengthRankGapDirectionInfo mediumShortGapDirection;

    /** 順位を取得した集計実行モード。 */
    string sourceMode;

    /** 順位の取得元データベースファイル名。 */
    string sourceFileName;

    /**
     * 未取得状態で生成する。
     */
    ZigZagElliotMonitorStrengthSnapshot() {
        this.reset();
    }

    /**
     * 前回の取得結果を破棄し、未取得状態へ戻す。
     */
    void reset() {
        this.queried = false;
        this.recordAvailable = false;
        this.targetM5BarTime = 0;
        this.retrievedAtSrv = 0;
        this.pairRankInfo.reset();
        this.longMediumGapDirection.reset();
        this.mediumShortGapDirection.reset();
        this.sourceMode = "";
        this.sourceFileName = "";
    }

    /**
     * 対象M5と一致する取得結果から表示に必要な情報だけを保存する。
     * 取得失敗時も試行時刻を記録し、前回の順位は引き継がない。
     *
     * @param fromInfo 今回の取得結果。
     * @param fromTargetM5BarTime 今回の取得対象M5開始時刻。
     */
    void capture(const CurrencyStrengthExecutionInfo &fromInfo,
            const datetime fromTargetM5BarTime) {
        this.reset();
        this.queried = true;
        this.targetM5BarTime = fromTargetM5BarTime;
        this.retrievedAtSrv = TimeCurrent();

        if (fromInfo.status != CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND
                || fromTargetM5BarTime <= 0 || fromTargetM5BarTime % 300 != 0
                || fromInfo.targetM5BarTime != fromTargetM5BarTime
                || fromInfo.pairRankInfo.m5BarTime != fromTargetM5BarTime
                || fromInfo.pairRankInfo.baseCurrency == ""
                || fromInfo.pairRankInfo.quoteCurrency == ""
                || fromInfo.pairRankInfo.baseCurrency == fromInfo.pairRankInfo.quoteCurrency) {
            return;
        }

        this.recordAvailable = true;
        this.pairRankInfo = fromInfo.pairRankInfo;
        this.longMediumGapDirection = fromInfo.longMediumGapDirection;
        this.mediumShortGapDirection = fromInfo.mediumShortGapDirection;
        this.sourceMode = fromInfo.sourceMode;
        this.sourceFileName = fromInfo.sourceFileName;
    }

    /**
     * 指定期間の基軸・決済通貨順位がそれぞれ1～8か判定する。
     *
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @return 対象レコードと指定期間の順位が有効な場合true。
     */
    bool hasRanks(const bool fromLongMedium) const {
        if (!this.recordAvailable) {
            return false;
        }

        int baseRank = this.pairRankInfo.baseLongMediumTermAverageRank;
        int quoteRank = this.pairRankInfo.quoteLongMediumTermAverageRank;
        if (!fromLongMedium) {
            baseRank = this.pairRankInfo.baseMediumShortTermAverageRank;
            quoteRank = this.pairRankInfo.quoteMediumShortTermAverageRank;
        }

        return baseRank >= 1 && baseRank <= 8 && quoteRank >= 1 && quoteRank <= 8;
    }

    /**
     * 指定期間の決済通貨順位から基軸通貨順位を引いた値を返す。
     *
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @return 順位差。順位が無効の場合0。
     */
    int getRankDifference(const bool fromLongMedium) const {
        if (!this.hasRanks(fromLongMedium)) {
            return 0;
        }

        if (fromLongMedium) {
            return this.pairRankInfo.quoteLongMediumTermAverageRank
                - this.pairRankInfo.baseLongMediumTermAverageRank;
        }

        return this.pairRankInfo.quoteMediumShortTermAverageRank
            - this.pairRankInfo.baseMediumShortTermAverageRank;
    }

    /**
     * 現在順位と整合する直近の変化時点の増減を表示できるか判定する。
     * 横ばいでは判定方向の根拠となった変化前後の順位差を使用する。
     *
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @return 直近変化の前後順位差・時刻・方向が現在値と整合する場合true。
     */
    bool hasGapChange(const bool fromLongMedium) const {
        return this.getGapChange(fromLongMedium) != 0;
    }

    /**
     * 直近の変化時点における、変化後の順位差から変化前の順位差を引いた値を返す。
     * 横ばいでも変化時の値を維持し、無効時の0はhasGapChangeで区別する。
     *
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @return 直近変化の増減値。根拠が無効の場合0。
     */
    int getGapChange(const bool fromLongMedium) const {
        if (this.isGapWaiting(fromLongMedium)) {
            return 0;
        }

        if (fromLongMedium) {
            return this.longMediumGapDirection.getLastGapChange();
        }

        return this.mediumShortGapDirection.getLastGapChange();
    }

    /**
     * 現在順位と整合する増減情報をまだ取得できていないか判定する。
     * 過去履歴の欠損などで確定した方向不明は、取得待ちに含めない。
     *
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @return 順位または現在の増減情報が未取得・不整合・取得待ちの場合true。
     */
    bool isGapWaiting(const bool fromLongMedium) const {
        if (!this.hasRanks(fromLongMedium)) {
            return true;
        }

        int rankDifference = this.getRankDifference(fromLongMedium);
        if (fromLongMedium) {
            return this.isGapInfoWaiting(this.longMediumGapDirection, rankDifference);
        }

        return this.isGapInfoWaiting(this.mediumShortGapDirection, rankDifference);
    }

    /**
     * 現在順位と根拠時刻を確認した増減方向を返す。
     *
     * @param fromLongMedium 長中期の場合true、中短期の場合false。
     * @return 上昇1、下降-1、取得待ちまたは方向不明の場合0。
     */
    int getDirection(const bool fromLongMedium) const {
        if (this.isGapWaiting(fromLongMedium)) {
            return 0;
        }

        if (fromLongMedium) {
            return this.getValidDirection(this.longMediumGapDirection);
        }

        return this.getValidDirection(this.mediumShortGapDirection);
    }

private:
    /**
     * 指定した増減情報の現在順位と対象時刻が表示内容と整合するか確認する。
     *
     * @param fromGapInfo 確認する期間の増減情報。
     * @param fromRankDifference 同じ期間の現在順位差。
     * @return 取得待ち、未取得または不整合の場合true。
     */
    bool isGapInfoWaiting(const CurrencyStrengthRankGapDirectionInfo &fromGapInfo,
            const int fromRankDifference) const {
        return !fromGapInfo.enabled || !fromGapInfo.currentAvailable
            || fromGapInfo.targetM5BarTime != this.targetM5BarTime
            || fromGapInfo.currentGap != fromRankDifference || fromGapInfo.waiting;
    }

    /**
     * 直前順位と対象時刻以前の根拠を持つ増減方向だけを返す。
     *
     * @param fromGapInfo 現在順位との整合を確認済みの増減情報。
     * @return 有効な上昇1・下降-1。それ以外は0。
     */
    int getValidDirection(const CurrencyStrengthRankGapDirectionInfo &fromGapInfo) const {
        if (!fromGapInfo.hasPrevious || fromGapInfo.directionChangedAt <= 0
                || fromGapInfo.directionChangedAt > this.targetM5BarTime
                || (fromGapInfo.direction != 1 && fromGapInfo.direction != -1)) {
            return 0;
        }

        return fromGapInfo.direction;
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_STRENGTH_SNAPSHOT_MQH
