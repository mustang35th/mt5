//+------------------------------------------------------------------+
//|                                             ElliotWithHigher.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\Analysis\ElliotBase.mqh>
#include <Mstng\Elliot\Reanalysis\ElliotReanalysisNarrowWaveLeft.mqh>
#include <Mstng\Elliot\Reanalysis\ElliotReanalysisNarrowWaveRight.mqh>
#include <Mstng\Elliot\Reanalysis\ElliotReanalysisSameTrend.mqh>


/**
 * 上位足と同期済みのポイント列をWaveとして分析するクラス。
 *
 * 通常分析に加え、同一方向Waveや狭いWaveを対象とした再分析を提供する。
 */
class ElliotWithHigher : public ElliotBase {
public:
    /** 最初に生成するWaveが推進波の場合true */
    bool isMotive;
    /** 最新側のポイント列を分析する場合true */
    bool isLatest;

    /**
     * シンボル、時間足および分析条件を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     * @param fromZigZagPointList 分析対象ポイント列
     * @param fromIsMotive 最初のWaveが推進波の場合true
     * @param fromIsLatest 最新側のポイント列を分析する場合true
     */
    ElliotWithHigher(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, bool fromIsBuy, string fromBuySellLabel,
                    CArrayObj &fromZigZagPointList, bool fromIsMotive, bool fromIsLatest) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromIsBuy, fromBuySellLabel, fromZigZagPointList, fromIsMotive, fromIsLatest);
    }

    /**
     * 市場コンテキストおよび分析条件を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     * @param fromZigZagPointList 分析対象ポイント列
     * @param fromIsMotive 最初のWaveが推進波の場合true
     * @param fromIsLatest 最新側のポイント列を分析する場合true
     */
    ElliotWithHigher(
        MarketContext &fromMarketContext,
        bool fromIsBuy,
        string fromBuySellLabel,
        CArrayObj &fromZigZagPointList,
        bool fromIsMotive,
        bool fromIsLatest
    ) {
        this.initialize(fromMarketContext, fromIsBuy, fromBuySellLabel, fromZigZagPointList, fromIsMotive, fromIsLatest);
    }

    /**
     * ElliotWithHigher を破棄します。
     */
    ~ElliotWithHigher(){
    }

    /**
     * 上位足同期済みポイント列のWave分析を実行する。
     *
     * @return Waveを生成できた場合true
     */
    bool analyze() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);


        int position = 0;

        if (this.isLatest) {    // 最新波動の場合のみ実行
            this.logger.debug(__FUNCTION__, "最新波動");

            if (!this.getWave0(this.isMotive)) {
                this.logger.error(__FUNCTION__, "getWave0 false");
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                return false;
            }

            Wave *wave = this.waveList.At(0);

            position = wave.zigZagPointList.Total();
        }


        this.logger.debug(__FUNCTION__, StringFormat("ループ前 position = %d", position));


        if (!this.makeWaveList(position, this.isMotive)) {
            this.logger.error(__FUNCTION__, "makeWaveList false");

            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }


        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

    /**
     * 同じ方向の連続Waveを再分析する。
     *
     * @return 再分析に成功した場合true
     */
    bool reanalyzeSameTrend() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);


        ElliotReanalysisSameTrend *elliotReanalysisSameTrend = new ElliotReanalysisSameTrend(this.marketContext, this.waveList);


        if (!elliotReanalysisSameTrend.analyze()) {
            delete elliotReanalysisSameTrend;

            this.logger.error(__FUNCTION__, "elliotReanalysisSameTrend.analyze false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        WaveUtil::copyWaveList(elliotReanalysisSameTrend.waveList, this.waveList);

        delete elliotReanalysisSameTrend;


        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

    /**
     * 左側の狭いWaveを隣接Waveへ統合して再分析する。
     *
     * @return 再分析に成功した場合true
     */
    bool reanalyzeNarrowWaveLeft() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);


        ElliotReanalysisNarrowWaveLeft *elliotReanalysisNarrowWaveLeft = new ElliotReanalysisNarrowWaveLeft(this.marketContext, this.waveList);


        if (!elliotReanalysisNarrowWaveLeft.analyze()) {
            delete elliotReanalysisNarrowWaveLeft;

            this.logger.error(__FUNCTION__, "elliotReanalysisNarrowWaveLeft.analyze false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        WaveUtil::copyWaveList(elliotReanalysisNarrowWaveLeft.waveList, this.waveList);

        delete elliotReanalysisNarrowWaveLeft;


        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

    /**
     * 右側の狭いWaveを隣接Waveへ統合して再分析する。
     *
     * @return 再分析に成功した場合true
     */
    bool reanalyzeNarrowWaveRight() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);


        ElliotReanalysisNarrowWaveRight *elliotReanalysisNarrowWaveRight = new ElliotReanalysisNarrowWaveRight(this.marketContext, this.waveList);


        if (!elliotReanalysisNarrowWaveRight.analyze()) {
            delete elliotReanalysisNarrowWaveRight;

            this.logger.error(__FUNCTION__, "elliotReanalysisNarrowWaveRight.analyze false");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        WaveUtil::copyWaveList(elliotReanalysisNarrowWaveRight.waveList, this.waveList);

        delete elliotReanalysisNarrowWaveRight;


        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

private:
    /**
     * 市場コンテキストおよび分析条件を初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromIsBuy 売買方向。true: BUY、false: SELL
     * @param fromBuySellLabel 売買方向表示用ラベル
     * @param fromZigZagPointList 分析対象ポイント列
     * @param fromIsMotive 最初のWaveが推進波の場合true
     * @param fromIsLatest 最新側のポイント列を分析する場合true
     */
    void initialize(
        MarketContext &fromMarketContext,
        bool fromIsBuy,
        string fromBuySellLabel,
        CArrayObj &fromZigZagPointList,
        bool fromIsMotive,
        bool fromIsLatest
    ) {
        this.logger.setLevel(LOG_INFO);

        this.init(fromMarketContext, fromIsBuy, fromBuySellLabel);
        
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        ZigZagPointUtil::copyZigZagPointList(fromZigZagPointList, this.zigZagPointList);
        
        LogUtil::printZigZagPointList(logger, __FUNCTION__, this.zigZagPointList);
        
        this.isMotive = fromIsMotive;
        this.isLatest = fromIsLatest;
        
        this.logger.debug(__FUNCTION__, StringFormat("isMotive = %s", (string)isMotive));
        this.logger.debug(__FUNCTION__, StringFormat("isLatest = %s", (string)isLatest));
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};











