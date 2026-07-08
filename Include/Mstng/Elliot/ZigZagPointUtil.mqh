//+------------------------------------------------------------------+
//|                                              ZigZagPointUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __ZIGZAG_POINT_UTIL_MQH__
#define __ZIGZAG_POINT_UTIL_MQH__

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Elliot\Wave.mqh>

/**
 * ZigZagPointに関するリスト操作を集約したユーティリティ。
 *
 * ポイントリストの検索、コピー、挿入、Wave一覧からの再構築を提供する。
 */
class ZigZagPointUtil {
public:
    
    /**
     * ポイントを追加し、元データは保持せず clone をリストへ格納する。
     *
     * @param pointList 追加先のポイントリスト
     * @param fromZigZagPoint 追加元のポイント
     */
    static void addPoint(CArrayObj &pointList, ZigZagPoint &fromZigZagPoint) {
        ZigZagPoint *zigZagPoint = fromZigZagPoint.clone();
        
        pointList.Add(zigZagPoint);
    }
    
    /**
     * ZigZagPointのリストをディープコピーする。
     *
     * @param fromZigZagPointList コピー元のZigZagPointリスト
     * @param toZigZagPointList コピー先のZigZagPointリスト
     */
    static void copyZigZagPointList(CArrayObj &fromZigZagPointList, CArrayObj &toZigZagPointList) {
        toZigZagPointList.Clear();
        
        // コピー元リストの件数を取得
        int total = fromZigZagPointList.Total();

        // 各要素を順番に取り出してディープコピーする
        for (int i = 0; i < total; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);

            // NULL の場合は安全のためスキップ
            if (zigZagPoint == NULL) {
                continue;
            }

            // 元の ZigZagPoint からクローンを作成
            ZigZagPoint *zigZagPointClone = zigZagPoint.clone();

            // クローン生成に失敗した場合はスキップ
            if (zigZagPointClone == NULL) {
                continue;
            }

            // クローンをコピー先リストに追加
            toZigZagPointList.Add(zigZagPointClone);
        }
    }
    
    /**
     * 同じバー位置とPeak/Bottom属性を持つポイント位置を検索する。
     *
     * @param logger ロガー
     * @param fromZigZagPointList 検索対象一覧
     * @param fromZigZagPoint 検索条件となるポイント
     * @return 該当インデックス。存在しない場合-1
     */
    static int getIndex(Logger &logger, CArrayObj &fromZigZagPointList, ZigZagPoint &fromZigZagPoint) {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
        int index = 0;
        
        int total = fromZigZagPointList.Total();

        for (int i = 0; i < total; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);

            if (zigZagPoint == NULL) {
                continue;
            }
            
            if (zigZagPoint.barIndex == fromZigZagPoint.barIndex) {
                index = i;
                break;
            }
        }
        
        logger.debug(__FUNCTION__, StringFormat("ZigZagPointListの検索 index = %d", index));
        LogUtil::printMethodEnd(logger, __FUNCTION__, true);
        
        return index;
    }
    
    /**
     * ポイント一覧の最後の要素を取得する。
     *
     * @param fromZigZagPointList 対象のポイント一覧
     * @return 最後の要素。空の場合NULL
     */
    static ZigZagPoint *getLastNode(CArrayObj &fromZigZagPointList) {
        return fromZigZagPointList.At(fromZigZagPointList.Total() - 1);
    }
    
    /**
     * バー位置とPeak/Bottom属性が一致するポイントを取得する。
     *
     * @param fromZigZagPointList 検索対象一覧
     * @param barIndex バー位置
     * @param isPeak true: Peak、false: Bottom
     * @return 一致するポイント。存在しない場合NULL
     */
    static ZigZagPoint *getFromBarIndex(CArrayObj &fromZigZagPointList, int barIndex, bool isPeak) {
        int total = fromZigZagPointList.Total();

        for (int i = 0; i < total; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);

            if (zigZagPoint == NULL) {
                continue;
            }
            
            if (zigZagPoint.barIndex == barIndex
                    && zigZagPoint.isPeak == isPeak) {
                return zigZagPoint;
            }
        }
        
        return NULL;
    }

    /**
     * 指定されたZigZagPointをディープコピーし、リストの先頭に挿入する。
     *
     * @param pointList 挿入先のZigZagPointリスト
     * @param fromZigZagPoint 挿入元となるZigZagPoint
     */
    static void insertPoint(CArrayObj &pointList, ZigZagPoint &fromZigZagPoint) {
        // 引数のポイントからクローンを生成
        ZigZagPoint *zigZagPoint = fromZigZagPoint.clone();

        // クローンをリストの先頭に挿入
        pointList.Insert(zigZagPoint, 0);
    }
    
    /**
     * Wave一覧から重複境界を除いたZigZagポイント一覧を再構築する。
     *
     * @param logger ロガー
     * @param fromWaveList 変換元Wave一覧
     * @param toZigZagPointList 変換先ポイント一覧
     * @param isOrg trueの場合orgZigZagPointListを使用する
     */
    static void makeZigZagPointListFromWaveList(Logger &logger, CArrayObj &fromWaveList, CArrayObj &toZigZagPointList, bool isOrg = false) {
        LogUtil::printMethodStart(logger, __FUNCTION__);
        
                
        int waveTotal = fromWaveList.Total();
        
        for (int i = 0; i < waveTotal ; i++) {
            Wave *wave = fromWaveList.At(i);
            CArrayObj zigZagPointList;
            
            if (isOrg) {
                zigZagPointList = wave.orgZigZagPointList;
            } else {
                zigZagPointList = wave.zigZagPointList;
            }
            
            int total = zigZagPointList.Total();
            
            for (int j = total - 1; j > 0; j--) {
                ZigZagPoint *zigZagPoint = zigZagPointList.At(j);
                
                ZigZagPointUtil::addPoint(toZigZagPointList, zigZagPoint);
            }
            
            if (i == waveTotal - 1) {   // 先頭のWaveはPoint0を追加要
                ZigZagPoint *zigZagPoint = zigZagPointList.At(0);
                
                ZigZagPointUtil::addPoint(toZigZagPointList, zigZagPoint);
            }
        }
        
        LogUtil::printMethodEnd(logger, __FUNCTION__, true);
    }
    
    /**
     * 全ポイントへ現在のElliott情報を元情報として保存する。
     *
     * @param fromZigZagPointList 設定対象ポイント一覧
     */
    static void setOrgField(CArrayObj &fromZigZagPointList) {
        int total = fromZigZagPointList.Total();

        for (int i = 0; i < total; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);

            if (zigZagPoint == NULL) {
                continue;
            }
            
            zigZagPoint.orgElliotIndex = zigZagPoint.elliotIndex;
            zigZagPoint.orgElliotLabel = zigZagPoint.elliotLabel;
        }
    }
    
};

#endif // __ZIGZAG_POINT_UTIL_MQH__





