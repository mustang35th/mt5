//+------------------------------------------------------------------+
//|                                         ElliotWithHigherUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Elliot.mqh>

#define ELLIOT_UPPER_WAVES 5

/**
 * 上位足同期分析で使用するポイント抽出ユーティリティ。
 *
 * 上位足Waveの対象期間を下位足バー数へ変換し、上位足の左右ポイント間に
 * 含まれる下位足ZigZagポイントを抽出する。
 */
class ElliotWithHigherUtil {
public:
    /**
     * 上位足の最古Waveを基準に下位足の分析バー数を取得する。
     *
     * @param logger ロガー
     * @param elliotHigher 上位足Elliott分析結果
     * @param symbolName 分析対象シンボル
     * @param timeFrame 下位時間足
     * @return 下位足の分析バー数。取得失敗時は0
     */
    static int getBars(Logger &logger, Elliot &elliotHigher, string symbolName, ENUM_TIMEFRAMES timeFrame) {
        MarketContext context(symbolName, timeFrame);
        return getBars(logger, elliotHigher, context);
    }

    /**
     * 上位足の最古Waveを基準に下位足の分析バー数を取得する。
     *
     * @param logger ロガー
     * @param elliotHigher 上位足Elliott分析結果
     * @param marketContext 分析対象の市場コンテキスト
     * @return 下位足の分析バー数。取得失敗時は0
     */
    static int getBars(Logger &logger, Elliot &elliotHigher, MarketContext &marketContext) {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        Wave *oldestWaveHigher = elliotHigher.getOldestWave();
        
        if (oldestWaveHigher == NULL) {
            logger.error(__FUNCTION__, "oldestWaveHigher is NULL");
            
            logger.error(__FUNCTION__, elliotHigher.toString());
            logger.error(__FUNCTION__, StringFormat("elliotHigher.waveList.Total = %d", elliotHigher.waveList.Total()));
            
            return 300;
        }
        
        ZigZagPoint *zigZagPointHigher = oldestWaveHigher.zigZagPointList.At(0);
        
        logger.debug(__FUNCTION__, StringFormat("zigZagPointHigher.barIndex = %d", zigZagPointHigher.barIndex));
        logger.debug(__FUNCTION__, StringFormat("zigZagPointHigher.barTime = %s", TimeToString(zigZagPointHigher.barTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS)));
        
        int bars = iBarShift(marketContext.symbolName, marketContext.timeFrame, zigZagPointHigher.barTime, false);
        
        logger.debug(__FUNCTION__, StringFormat("bars = %d", bars));
        
        
        double multi = 1.1; // 余裕を持たせる
        
        if (bars < 100) {
            multi = 3;
        }
        
        bars = (int)(bars * multi);
        
        logger.debug(__FUNCTION__, StringFormat("bars multi = %d", bars));
        
        
        datetime time = iTime(marketContext.symbolName, marketContext.timeFrame, bars);
        logger.debug(__FUNCTION__, StringFormat("bars time = %s", TimeToString(time, TIME_DATE | TIME_MINUTES | TIME_SECONDS)));
        
        LogUtil::printMethodEnd(logger, __FUNCTION__, true);
        
        return bars;
    }
    
    /**
     * 上位足の左右ポイント間にある下位足ZigZagポイントを抽出する。
     *
     * @param logger ロガー
     * @param orgZigZagPointList 抽出元ポイント列
     * @param start 抽出開始位置
     * @param zigZagPointHigherLeft 上位足左側ポイント
     * @param zigZagPointHigherRight 上位足右側ポイント
     * @param zigZagPointList 抽出結果
     * @param isUpTrend true: 上昇波、false: 下降波
     * @param endIndex 抽出終了位置
     * @return 抽出処理に成功した場合true
     */
    static bool getZigZagPointWithHigher(Logger &logger, CArrayObj &orgZigZagPointList, int start, 
                                        ZigZagPoint &zigZagPointHigherLeft, ZigZagPoint &zigZagPointHigherRight, 
                                        CArrayObj &zigZagPointList, bool isUpTrend, int &endIndex) {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        logger.debug(__FUNCTION__, "zigZagPointHigherLeft <<<<<");
        logger.debug(__FUNCTION__, zigZagPointHigherLeft.toString());
        logger.debug(__FUNCTION__, "zigZagPointHigherRight >>>>>");
        logger.debug(__FUNCTION__, zigZagPointHigherRight.toString());
        
        datetime datetimeStart = zigZagPointHigherLeft.barTime;
        datetime datetimeEnd = zigZagPointHigherRight.barTimeNext;
        
        logger.debug(__FUNCTION__, StringFormat("datetime = %s -> %s", 
            TimeUtil::formatYyyymmddhhmiss(datetimeStart),
            TimeUtil::formatYyyymmddhhmiss(datetimeEnd)));
        
        logger.debug(__FUNCTION__, StringFormat("start = %d", start));
        
        int orgTotal = orgZigZagPointList.Total();
        
        logger.debug(__FUNCTION__, StringFormat("orgTotal = %d", orgTotal));
        
        for (int i = start; i < orgTotal; i++) {
            logger.debug(__FUNCTION__, StringFormat("for i = %d", i));
            
            ZigZagPoint *zigZagPoint = orgZigZagPointList.At(i);
            
            if (zigZagPoint == NULL) {  // NULLチェック
                logger.error(__FUNCTION__, "zigZagPoint is NULL");
                LogUtil::printMethodEnd(logger, __FUNCTION__, false);
                
                return false;
            }
            
            if (i == start) {
                logger.debug(__FUNCTION__, zigZagPoint.toString());
            }
            
            // ポイント左より過去の場合終了
            if (zigZagPoint.barTimeNext < datetimeStart) {
                endIndex = i - 1;
                
                break;
            }
            
            if (zigZagPoint.barTimeNext == datetimeStart) {
                endIndex = i - 1;
                
                break;
            }
            
            // ポイント左内にポイントが2つある場合、終了
            // hasTwoLeftPoints
            if (hasTwoLeftPoints(logger, zigZagPointList, zigZagPointHigherLeft, zigZagPoint, isUpTrend)) {
                break;
            }
            
            // ポイント左右間の場合、ポイント追加
            if (datetimeStart <= zigZagPoint.barTimeNext 
                    && zigZagPoint.barTime <= datetimeEnd) {
                ZigZagPointUtil::addPoint(zigZagPointList, zigZagPoint);
            }
        }
        
        
        logger.debug(__FUNCTION__, StringFormat("endIndex = %d", endIndex));
        LogUtil::printMethodEnd(logger, __FUNCTION__, true);

        return true;
    }

private:
    /**
     * 上位足左ポイント側に波動生成に必要な2点があるか判定する。
     *
     * @param logger ロガー
     * @param zigZagPointList 確認対象ポイント列
     * @param zigZagPointHigherLeft 上位足左側ポイント
     * @param zigZagPoint 比較対象ポイント
     * @param isUpTrend true: 上昇波、false: 下降波
     * @return 必要な2点を確保できる場合true
     */
    static bool hasTwoLeftPoints(Logger &logger, CArrayObj &zigZagPointList, ZigZagPoint &zigZagPointHigherLeft, ZigZagPoint &zigZagPoint, bool isUpTrend) {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        logger.debug(__FUNCTION__, StringFormat("isUpTrend = %s", (string)isUpTrend));
        
        bool hasTwoLeftPoints = false;
        
        // ポイントが上位足左側の中に収まる場合
        if (zigZagPointHigherLeft.barTime <= zigZagPoint.barTime 
                && zigZagPoint.barTime <= zigZagPointHigherLeft.barTimeNext) {
            ZigZagPoint *zigZagPointBefore = ZigZagPointUtil::getLastNode(zigZagPointList);
            
            if (zigZagPointBefore != NULL) {
                logger.debug(__FUNCTION__, "zigZagPointBefore");
                logger.debug(__FUNCTION__, zigZagPointBefore.toString());
                
                
                // １つ前のポイントが上位足左側の中に収まる場合
                if (zigZagPointHigherLeft.barTime <= zigZagPointBefore.barTime 
                        && zigZagPointBefore.barTime <= zigZagPointHigherLeft.barTimeNext) {
                    
                    logger.debug(__FUNCTION__, "hasTwoLeftPoints if");
                    
                    if (isUpTrend) {
                        if (zigZagPoint.isPeak) {
                            hasTwoLeftPoints = true;
                        }
                    } else {
                        if (!zigZagPoint.isPeak) {
                            hasTwoLeftPoints = true;
                        }
                    }
                }
            }
            
        }
        
        logger.debug(__FUNCTION__, StringFormat("hasTwoLeftPoints = %s", (string)hasTwoLeftPoints));
        LogUtil::printMethodEnd(logger, __FUNCTION__, true);
        
        return hasTwoLeftPoints;
    }
};    



