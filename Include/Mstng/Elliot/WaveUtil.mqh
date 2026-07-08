//+------------------------------------------------------------------+
//|                                                     WaveUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Wave.mqh>

/**
 * Wave一覧の生成、ディープコピー、終端取得を提供するユーティリティ。
 */
class WaveUtil {
public:
    /**
     * ポイント列からWaveを生成して一覧へ追加する。
     *
     * @param logger ロガー
     * @param fromWaveList 追加先Wave一覧
     * @param fromSymbolName 対象シンボル
     * @param fromTimeFrame 対象時間足
     * @param fromZigZagPointList Waveを構成するポイント列
     * @param isMotive true: 推進波、false: 修正波
     * @param isUptrend true: 上昇波、false: 下降波
     */
    static void addWave(Logger &logger, CArrayObj &fromWaveList, string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame,
                CArrayObj &fromZigZagPointList, bool isMotive, bool isUptrend) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        addWave(logger, fromWaveList, context, fromZigZagPointList, isMotive, isUptrend);
    }

    /**
     * 市場コンテキストとポイント列からWaveを生成して一覧へ追加する。
     *
     * @param logger ロガー
     * @param fromWaveList 追加先Wave一覧
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromZigZagPointList Waveを構成するポイント列
     * @param isMotive true: 推進波、false: 修正波
     * @param isUptrend true: 上昇波、false: 下降波
     */
    static void addWave(
        Logger &logger,
        CArrayObj &fromWaveList,
        MarketContext &fromMarketContext,
        CArrayObj &fromZigZagPointList,
        bool isMotive,
        bool isUptrend
    ) {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        Wave *wave = new Wave(fromMarketContext, fromZigZagPointList, isMotive, isUptrend);
        
        wave.setParentWave(wave);
        
        wave.index = fromWaveList.Total();
        
        fromWaveList.Add(wave);
        
        LogUtil::printMethodEnd(logger, __FUNCTION__, true);
    }
    
    /**
     * Wave一覧をディープコピーする。
     *
     * @param fromWaveList コピー元Wave一覧
     * @param toWaveList コピー先Wave一覧
     */
    static void copyWaveList(CArrayObj &fromWaveList, CArrayObj &toWaveList) {
        
        // コピー先をクリア
        toWaveList.Clear();
        
        // コピー元リストの件数を取得
        int total = fromWaveList.Total();

        // 各要素を順番に取り出してディープコピーする
        for (int i = 0; i < total; i++) {
            Wave *wave = fromWaveList.At(i);

            // NULL の場合は安全のためスキップ
            if (wave == NULL) {
                continue;
            }

            // 元の Wave からクローンを作成
            Wave *waveClone = wave.clone();

            // クローン生成に失敗した場合はスキップ
            if (waveClone == NULL) {
                continue;
            }
            
            waveClone.setParentWave(waveClone);

            // クローンをコピー先リストに追加
            toWaveList.Add(waveClone);
        }
    }

    /**
     * Wave一覧の最後の要素を取得する。
     *
     * @param fromWaveList 対象Wave一覧
     * @return 最後のWave。空の場合NULL
     */
    static Wave *getLastNode(CArrayObj &fromWaveList) {
        return fromWaveList.At(fromWaveList.Total() - 1);
    }
};    





