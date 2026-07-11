//+------------------------------------------------------------------+
//|                  ElliotReanalysisThreeWaveContinuation.mqh       |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Analysis\ElliotBase.mqh>

/**
 * 3分割された同方向の継続波を統合して再分析するクラス。
 *
 * 同方向の古いWaveと新しいWaveの間に反対方向の2ポイントWaveがあり、
 * 中央Waveが古いWave内の修正極値を超えても起点を超えず、
 * 新しいWaveがトレンド極値を更新した場合、3つのWaveを1つへ統合する。
 */
class ElliotReanalysisThreeWaveContinuation : public ElliotBase {
public:
    /**
     * シンボル、時間足および元Wave一覧を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisThreeWaveContinuation(
        string fromSymbolName,
        ENUM_TIMEFRAMES fromTimeFrame,
        CArrayObj &fromWaveList
    ) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromWaveList);
    }

    /**
     * 市場コンテキストおよび元Wave一覧を指定して初期化する。
     *
     * @param fromMarketContext 再分析対象の市場コンテキスト
     * @param fromWaveList 再分析対象Wave一覧
     */
    ElliotReanalysisThreeWaveContinuation(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.initialize(fromMarketContext, fromWaveList);
    }

    /**
     * デストラクタ。
     */
    ~ElliotReanalysisThreeWaveContinuation() {
    }

    /**
     * 3分割された継続波を検索し、最初に見つかった1組を再分析する。
     *
     * @return 再分析に成功した場合true。対象がない場合もtrue
     */
    bool analyze() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        int waveTotal = this.waveList.Total();

        this.logger.debug(__FUNCTION__, StringFormat("waveTotal = %d", waveTotal));

        if (waveTotal < 3) {
            this.logger.debug(__FUNCTION__, "対象外");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

            return true;
        }

        for (int i = 0; i < waveTotal - 2; i++) {
            if (this.isTarget(i)) {
                if (!this.reanalyze(i)) {
                    this.logger.error(__FUNCTION__, "reanalyze false");
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                    return false;
                }

                break;
            }
        }

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

private:
    /**
     * 市場コンテキストおよび元Wave一覧を初期化する。
     *
     * @param fromMarketContext 再分析対象の市場コンテキスト
     * @param fromWaveList 再分析対象Wave一覧
     */
    void initialize(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.logger.setLevel(LOG_INFO);

        this.init(fromMarketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        WaveUtil::copyWaveList(fromWaveList, this.waveList);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 2ポイントWaveを挟む同方向Waveが継続する3分割構成か判定する。
     *
     * 中央Waveが古いWaveの修正極値を超えても起点を超えず、
     * 新しいWaveが古いトレンド極値を更新した場合に対象とする。
     *
     * @param waveIndex 最新側の同方向Wave位置
     * @return 3分割された継続波の場合true
     */
    bool isTarget(int waveIndex) {
        Wave *waveNew = this.waveList.At(waveIndex);
        Wave *waveMiddle = this.waveList.At(waveIndex + 1);
        Wave *waveOld = this.waveList.At(waveIndex + 2);

        if (waveNew == NULL || waveMiddle == NULL || waveOld == NULL) {
            return false;
        }

        if (waveNew.isUptrend != waveOld.isUptrend
                || waveMiddle.isUptrend == waveNew.isUptrend) {
            return false;
        }

        if (waveNew.isMotive != waveMiddle.isMotive
                || waveMiddle.isMotive != waveOld.isMotive) {
            return false;
        }

        if (waveMiddle.zigZagPointList.Total() != 2
                || waveOld.zigZagPointList.Total() < 4
                || waveNew.zigZagPointList.Total() < 2) {
            return false;
        }

        ZigZagPoint *oldOriginPoint = waveOld.zigZagPointList.At(0);
        ZigZagPoint *oldTrendPoint = waveOld.getLatestPoint();
        ZigZagPoint *oldCorrectionPoint = waveOld.getLatestPoint2();
        ZigZagPoint *middleOldestPoint = waveMiddle.zigZagPointList.At(0);
        ZigZagPoint *middleLatestPoint = waveMiddle.getLatestPoint();
        ZigZagPoint *newOldestPoint = waveNew.zigZagPointList.At(0);
        ZigZagPoint *newLatestPoint = waveNew.getLatestPoint();

        if (oldOriginPoint == NULL
                || oldTrendPoint == NULL
                || oldCorrectionPoint == NULL
                || middleOldestPoint == NULL
                || middleLatestPoint == NULL
                || newOldestPoint == NULL
                || newLatestPoint == NULL) {
            return false;
        }

        if (!this.isSamePoint(oldTrendPoint, middleOldestPoint)
                || !this.isSamePoint(middleLatestPoint, newOldestPoint)) {
            return false;
        }

        if (oldOriginPoint.isPeak == waveOld.isUptrend
                || oldTrendPoint.isPeak != waveOld.isUptrend
                || oldCorrectionPoint.isPeak == waveOld.isUptrend
                || middleLatestPoint.isPeak != waveMiddle.isUptrend
                || newLatestPoint.isPeak != waveNew.isUptrend) {
            return false;
        }

        if (waveNew.isUptrend) {
            if (middleLatestPoint.rate < oldCorrectionPoint.rate
                    && middleLatestPoint.rate > oldOriginPoint.rate
                    && newLatestPoint.rate > oldTrendPoint.rate) {
                return true;
            }
        } else {
            if (middleLatestPoint.rate > oldCorrectionPoint.rate
                    && middleLatestPoint.rate < oldOriginPoint.rate
                    && newLatestPoint.rate < oldTrendPoint.rate) {
                return true;
            }
        }

        return false;
    }

    /**
     * 3分割されたWaveを1つへ統合して再分析する。
     *
     * 古いWaveの最新トレンド極値を保持し、その直前2ポイントを除外する。
     * 続けて中央Waveの最新修正極値と最新Waveの残りのポイントを連結する。
     *
     * @param waveIndex 最新側の同方向Wave位置
     * @return 再分析に成功した場合true
     */
    bool reanalyze(int waveIndex) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        Wave *waveNew = this.waveList.At(waveIndex);
        Wave *waveMiddle = this.waveList.At(waveIndex + 1);
        Wave *waveOld = this.waveList.At(waveIndex + 2);
        CArrayObj mergedZigZagPointList;

        int oldPointTotal = waveOld.zigZagPointList.Total();
        int obsoleteTrendPointIndex = oldPointTotal - 3;

        for (int i = 0; i < oldPointTotal; i++) {
            if (i == obsoleteTrendPointIndex || i == obsoleteTrendPointIndex + 1) {
                continue;
            }

            ZigZagPoint *zigZagPoint = waveOld.zigZagPointList.At(i);
            ZigZagPointUtil::addPoint(mergedZigZagPointList, zigZagPoint);
        }

        ZigZagPoint *middleLatestPoint = waveMiddle.getLatestPoint();
        ZigZagPointUtil::addPoint(mergedZigZagPointList, middleLatestPoint);

        for (int i = 1; i < waveNew.zigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = waveNew.zigZagPointList.At(i);
            ZigZagPointUtil::addPoint(mergedZigZagPointList, zigZagPoint);
        }

        CArrayObj waveListNew;

        for (int i = 0; i < waveIndex; i++) {
            Wave *wave = this.waveList.At(i);
            WaveUtil::addWave(this.logger, waveListNew, this.marketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
        }

        WaveUtil::addWave(this.logger, waveListNew, this.marketContext, mergedZigZagPointList, waveOld.isMotive, waveOld.isUptrend);

        for (int i = waveIndex + 3; i < this.waveList.Total(); i++) {
            Wave *wave = this.waveList.At(i);
            WaveUtil::addWave(this.logger, waveListNew, this.marketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
        }

        WaveUtil::copyWaveList(waveListNew, this.waveList);

        if (!this.makeZigZagPointListAndReanalyze()) {
            this.logger.error(__FUNCTION__, "makeZigZagPointListAndReanalyze false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

    /**
     * 2つのポイントが同じ転換点を表すか判定する。
     *
     * @param firstPoint 比較対象ポイント
     * @param secondPoint 比較対象ポイント
     * @return 時刻と山谷種別が一致する場合true
     */
    bool isSamePoint(ZigZagPoint &firstPoint, ZigZagPoint &secondPoint) {
        return firstPoint.barTime == secondPoint.barTime
                && firstPoint.isPeak == secondPoint.isPeak;
    }
};
