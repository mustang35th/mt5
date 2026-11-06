//+------------------------------------------------------------------+
//|                                     ElliotReanalysisWaveList.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\WaveUtil.mqh>
#include <Mstng\Log\Logger.mqh>

/**
 * 再分析で選択したポイント列を使ってWave一覧を再構築する補助クラス。
 *
 * 判定とポイント生成は各再分析クラスが担当し、本クラスは指定範囲の置換だけを行う。
 * Waveの生成順序とディープコピーを維持し、元Waveやポイントの所有権は移さない。
 */
class ElliotReanalysisWaveList {
public:
    /**
     * 指定範囲のWaveを1つのWaveへ置換し、元一覧へディープコピーする。
     *
     * 対象より新しいWave、置換Wave、対象より古いWaveの順に作業一覧を生成する。
     * 呼び出し側で有効な置換範囲を選択してから使用し、置換後の再分析も呼び出し側で行う。
     *
     * @param fromLogger ロガー
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromWaveList 置換対象Wave一覧。インデックス0が最新
     * @param fromWaveIndex 置換範囲の開始位置
     * @param fromReplaceCount 置換するWave数
     * @param fromZigZagPointList 置換Waveを構成するポイント列
     * @param fromIsMotive 置換Waveが推進波の場合true
     * @param fromIsUptrend 置換Waveが上昇トレンドの場合true
     */
    static void replaceWaveRange(
        Logger &fromLogger,
        MarketContext &fromMarketContext,
        CArrayObj &fromWaveList,
        int fromWaveIndex,
        int fromReplaceCount,
        CArrayObj &fromZigZagPointList,
        bool fromIsMotive,
        bool fromIsUptrend
    ) {
        CArrayObj waveListNew;

        // 対象より新しいWaveをコピーする。
        for (int i = 0; i < fromWaveIndex; i++) {
            Wave *wave = fromWaveList.At(i);
            WaveUtil::addWave(fromLogger, waveListNew, fromMarketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
        }

        // 再分析Waveを追加する。
        WaveUtil::addWave(fromLogger, waveListNew, fromMarketContext, fromZigZagPointList, fromIsMotive, fromIsUptrend);

        // 対象より古いWaveをコピーする。
        for (int i = fromWaveIndex + fromReplaceCount; i < fromWaveList.Total(); i++) {
            Wave *wave = fromWaveList.At(i);
            WaveUtil::addWave(fromLogger, waveListNew, fromMarketContext, wave.zigZagPointList, wave.isMotive, wave.isUptrend);
        }

        WaveUtil::copyWaveList(waveListNew, fromWaveList);
    }
};
