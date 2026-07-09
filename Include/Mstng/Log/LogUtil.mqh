//+------------------------------------------------------------------+
//|                                                      LogUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Arrays\ArrayObj.mqh>

#include <Mstng\Log\Logger.mqh>
#include <Mstng\Elliot\Wave.mqh>

/**
 * ログ出力のユーティリティクラス。
 *
 * 主にZigZagPointやWaveの情報を整形して
 * DEBUGログとして出力するための静的ヘルパーを提供する。
 */
class LogUtil {
public:

    /**
     * インデックス情報をログ出力用の文字列に整形して返す。
     *
     * @param i インデックス番号。
     * @return インデックス情報を表す文字列。例: "i=0, "。
     */
    static string getTextIndex(int i) {
        return StringFormat("i = %d, ", i);
    }
    
    /**
     * メソッド終了と処理結果をデバッグログへ出力する。
     *
     * @param logger 出力に使用するLogger。
     * @param functionName 呼び出し元のメソッド名。
     * @param isSucceeded 処理に成功した場合true。
     */
    static void printMethodEnd(Logger &logger, string functionName, bool isSucceeded) {
        string text = "failed";
        
        if (isSucceeded) {
            text = "success";
        }
        
        logger.debug(functionName, StringFormat("END (%s)", text));
    }
    
    /**
     * メソッド開始をデバッグログへ出力する。
     *
     * @param logger 出力に使用するLogger。
     * @param functionName 呼び出し元のメソッド名。
     */
    static void printMethodStart(Logger &logger, string functionName) {
        logger.debug(functionName, "START ");
    }
    
    /**
     * 引数で渡されたZigZagPointのリスト内容をすべてログ出力する。
     * 各要素についてインデックスとZigZagPoint#toString()の結果を出力する。
     *
     * @param logger 出力に使用するLogger。
     * @param functionName 呼び出し元のメソッド名。
     * @param fromZigZagPointList 出力対象のZigZagPointリスト。
     */
    static void printZigZagPointList(Logger &logger, string functionName, CArrayObj &fromZigZagPointList) {
        logger.debug(functionName, "▽▽▽▽▽▽▽▽▽▽ ZigZagPointList ▽▽▽▽▽▽▽▽▽▽");
        
        // リストの総件数を取得し、先に件数情報を出力する。
        int total = fromZigZagPointList.Total();
        logger.debug(functionName, StringFormat("total ZigZag points = %d", total));

        // 各ZigZagPointを順番に取り出してログ出力する。
        for (int i = 0; i < total; i++) {
            ZigZagPoint *zigZagPoint = fromZigZagPointList.At(i);

            // NULLの場合は安全のためスキップする。
            if (zigZagPoint == NULL) {
                logger.debug(functionName, getTextIndex(i) + "zigZagPoint is NULL");
                
                continue;
            }

            // インデックス情報とZigZagPointの文字列表現をログ出力する。
            logger.debug(functionName, getTextIndex(i) + zigZagPoint.toString());
        }
        
        logger.debug(functionName, "△△△△△△△△△△ ZigZagPointList △△△△△△△△△△");
    }
    
    /**
     * Wave一覧をインデックス情報とともにデバッグログへ出力する。
     *
     * @param logger 出力に使用するLogger。
     * @param functionName 呼び出し元のメソッド名。
     * @param fromWaveList 出力対象のWave一覧。
     * @param isZigZagPoint 各WaveのZigZagPoint一覧も出力する場合true。
     */
    static void printWaveList(Logger &logger, string functionName, CArrayObj &fromWaveList, bool isZigZagPoint = false) {
        logger.debug(functionName, "▽▽▽▽▽▽▽▽▽▽ WaveList ▽▽▽▽▽▽▽▽▽▽");
    
        // リストの総件数を取得し、先に件数情報を出力する。
        int total = fromWaveList.Total();
        logger.debug(functionName, StringFormat("total Waves = %d", total));
    
        // 各Waveを順番に取り出してログ出力する。
        for (int i = 0; i < total; i++) {
            Wave *wave = (Wave *)fromWaveList.At(i);
    
            // NULLの場合は安全のためスキップする。
            if (wave == NULL) {
                logger.debug(functionName, getTextIndex(i) + "wave is NULL");
                continue;
            }
    
            // インデックス情報とWaveの文字列表現をログ出力する。
            logger.debug(functionName, getTextIndex(i) + wave.toString());
            
            if (isZigZagPoint) {
                LogUtil::printZigZagPointList(logger, functionName, wave.zigZagPointList);
            }
            
        }
    
        logger.debug(functionName, "△△△△△△△△△△ WaveList △△△△△△△△△△");
    }

};




