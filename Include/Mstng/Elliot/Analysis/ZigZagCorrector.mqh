//+------------------------------------------------------------------+
//|                                              ZigZagCorrector.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\Log\LogUtil.mqh>

/**
 * 下位足ZigZagポイントを上位足ポイントの時刻へ同期するクラス。
 *
 * 上位足ポイントに対応する下位足ポイントが存在しない場合、対象区間で
 * 最も適切な高値または安値へ下位足ポイントを補正する。
 */
class ZigZagCorrector {
public:
    /** 補正対象の市場コンテキスト。 */
    MarketContext marketContext;
    
    /** 補正対象の下位足ZigZagポイント一覧。 */
    CArrayObj orgZigZagPointList;
    
    /**
     * シンボル名と時間足を指定して初期化する。
     *
     * @param fromSymbolName 補正対象シンボル
     * @param fromTimeFrame 補正対象時間足
     */
    ZigZagCorrector(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.setMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 補正対象の市場コンテキスト
     */
    ZigZagCorrector(MarketContext &fromMarketContext) {
        this.setMarketContext(fromMarketContext);
    }
    
    /**
     * デストラクタ。
     */
    ~ZigZagCorrector() {
    }

    /**
     * 補正対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 補正対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.orgZigZagPointList.Clear();

        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * 下位足ZigZagポイントを上位足のポイント位置へ補正する。
     *
     * 上位足ポイントの期間内に対応する下位足ポイントがない場合、
     * 対象期間の高値または安値へ最も近い下位足ポイントを移動する。
     *
     * @param elliotHigher 上位足Elliott分析結果
     * @param fromZigZagPointList 補正対象の下位足ポイント列
     * @return 必要な価格系列を取得して補正できた場合true。
     */
    bool correct(Elliot &elliotHigher, CArrayObj &fromZigZagPointList) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        // 分析後に展開したZigZagを補正対象としてコピーする。
        ZigZagPointUtil::copyZigZagPointList(fromZigZagPointList, this.orgZigZagPointList);
        
        CArrayObj zigZagPointListHigher;
        if (!this.copyHigherZigZagPoints(elliotHigher.waveList, zigZagPointListHigher)) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }
        
        // 上位足ポイント内にあるか判定
        int higherTotal = zigZagPointListHigher.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("higherTotal = %d", higherTotal));
        
        for (int i = 0; i < higherTotal; i++) {
            ZigZagPoint *zigZagPointHigher = zigZagPointListHigher.At(i);
            
            bool isInsideHigherPoint = this.isInsideHigherPoint(zigZagPointHigher);
            
            if (!isInsideHigherPoint) {
                this.logger.debug(__FUNCTION__, StringFormat("上位足ポイントの繰り返し i = %d", i));
                this.logger.debug(__FUNCTION__, "上位足ポイントの範囲外");
                
                this.logger.debug(__FUNCTION__, zigZagPointHigher.toString());
                
                if (!this.correctPoint(zigZagPointHigher)) {
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                    return false;
                }
            }
            
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /**
     * 市場コンテキストを初期化する。
     *
     * @param fromMarketContext 補正対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 上位Waveの元ポイントだけを補正用に複製する。
     *
     * NULLを除いた各Waveの先頭ポイントは境界重複として除外し、
     * 最後の有効Waveだけ先頭ポイントも末尾へ追加する。
     * 元Waveと元ポイントの所有権は変更しない。
     *
     * @param fromWaveList 上位足のWave一覧。
     * @param fromPointList 複製したポイントの格納先。
     * @return 必要なポイントをすべて複製できた場合true。
     */
    bool copyHigherZigZagPoints(CArrayObj &fromWaveList, CArrayObj &fromPointList) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        fromPointList.Clear();
        int waveTotal = fromWaveList.Total();
        while (waveTotal > 0 && fromWaveList.At(waveTotal - 1) == NULL) {
            waveTotal--;
        }

        for (int i = 0; i < waveTotal; i++) {
            Wave *wave = fromWaveList.At(i);
            if (wave == NULL) {
                continue;
            }

            int pointTotal = wave.orgZigZagPointList.Total();
            int firstPointIndex = 0;
            while (firstPointIndex < pointTotal
                    && wave.orgZigZagPointList.At(firstPointIndex) == NULL) {
                firstPointIndex++;
            }

            int firstCopyIndex = firstPointIndex + 1;
            if (i == waveTotal - 1) {
                if (firstPointIndex >= pointTotal) {
                    this.logger.error(__FUNCTION__, "Higher wave endpoint is unavailable.");
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                    return false;
                }

                firstCopyIndex = firstPointIndex;
            }

            for (int j = pointTotal - 1; j >= firstCopyIndex; j--) {
                ZigZagPoint *point = wave.orgZigZagPointList.At(j);
                if (point == NULL) {
                    continue;
                }

                ZigZagPoint *pointClone = point.clone();
                if (pointClone == NULL) {
                    this.logger.error(__FUNCTION__, "Higher ZigZag point clone failed.");
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                    return false;
                }

                if (!fromPointList.Add(pointClone)) {
                    delete pointClone;
                    this.logger.error(__FUNCTION__, "Higher ZigZag point append failed.");
                    LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

                    return false;
                }
            }
        }

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }

    /**
     * 1つの上位足ポイントに対応する下位足ポイントを補正する。
     *
     * 上位足ポイントが山の場合は対象期間の高値、谷の場合は安値へ
     * 下位足ポイントの価格と時刻を合わせる。
     *
     * @param zigZagPointHigher 補正基準となる上位足ポイント
     * @return 補正できた場合または補正対象がない場合true。価格系列不足はfalse。
     */
    bool correctPoint(ZigZagPoint &zigZagPointHigher) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int leftIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, zigZagPointHigher.barTime);
        int rightIndex = iBarShift(this.marketContext.symbolName, this.marketContext.timeFrame, zigZagPointHigher.barTimeNext);

        if (leftIndex < 0 || rightIndex < 0 || leftIndex < rightIndex) {
            this.logger.error(__FUNCTION__, "ZigZag correction range is not ready.");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        // 補正対象のPoint位置検索
        int correctIndex = this.getCorrectIndex(zigZagPointHigher, leftIndex, rightIndex);
        
        this.logger.debug(__FUNCTION__, StringFormat("correctIndex = %d", correctIndex));
        
        if (correctIndex == -1) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

            return true;
        }
        
        
        ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(correctIndex);
        
        this.logger.debug(__FUNCTION__, "補正前");
        this.logger.debug(__FUNCTION__, zigZagPoint.toString());
        
        int requiredCount = leftIndex - rightIndex + 1;
        double prices[];
        ArraySetAsSeries(prices, true);
        int copiedCount = 0;

        if (zigZagPoint.isPeak) {
            copiedCount = CopyHigh(this.marketContext.symbolName, this.marketContext.timeFrame, rightIndex, requiredCount, prices);
        } else {
            copiedCount = CopyLow(this.marketContext.symbolName, this.marketContext.timeFrame, rightIndex, requiredCount, prices);
        }

        if (copiedCount != requiredCount) {
            this.logger.error(__FUNCTION__, "ZigZag correction price series is not ready.");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);

            return false;
        }

        int position = rightIndex;
        double rateNew = 0;

        if (zigZagPoint.isPeak) {  // 山
            for (int i = 0; i < requiredCount; i++) {
                double rate = prices[i];

                if (rate >= rateNew) {
                    position = rightIndex + i;
                    rateNew = rate;
                }
            }

        } else {    // 谷
            rateNew = 1000;

            for (int i = 0; i < requiredCount; i++) {
                double rate = prices[i];

                if (rate <= rateNew) {
                    position = rightIndex + i;
                    rateNew = rate;
                }
            }

        }
        
        zigZagPoint.rate = rateNew;
        zigZagPoint.setBarIndexAndTime(this.marketContext, position);
        zigZagPoint.isCorrect = true;
        
        this.logger.debug(__FUNCTION__, "補正後");
        this.logger.debug(__FUNCTION__, zigZagPoint.toString());
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return true;
    }
    
    /**
     * 上位足ポイントの期間内に対応する下位足ポイントがあるか判定する。
     *
     * @param zigZagPointHigher 判定基準となる上位足ポイント
     * @return 対応する下位足ポイントがある場合true
     */
    bool isInsideHigherPoint(ZigZagPoint &zigZagPointHigher) {
            
        for (int i = 0; i < this.orgZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(i);
            
            if (zigZagPoint.barTimeNext < zigZagPointHigher.barTime) {  // 上位ポイント左側より過去の場合
                return false;
            }
            
            if (zigZagPointHigher.barTime <= zigZagPoint.barTime
                    && zigZagPoint.barTime <= zigZagPointHigher.barTimeNext) {
                return true;
            }
        }
        
        return true;
    }
    
    /**
     * 上位足ポイントの期間から補正対象となる下位足位置を取得する。
     *
     * 左境界側と右境界側を順に確認し、上位足ポイントと同じ山谷種別の
     * 下位足ポイントを補正対象として返す。
     *
     * @param zigZagPointHigher 補正基準となる上位足ポイント
     * @param fromLeftIndex 検証済みの左境界バーインデックス。
     * @param fromRightIndex 検証済みの右境界バーインデックス。
     * @return 補正対象インデックス。対象がない場合-1
     */
    int getCorrectIndex(ZigZagPoint &zigZagPointHigher, int fromLeftIndex, int fromRightIndex) {
        // 左側から検索
        int index = this.getLeftIndex(fromLeftIndex);

        if (index >= 0) {
            ZigZagPoint *zigZagPoint =
                this.orgZigZagPointList.At(index);

            if (CheckPointer(zigZagPoint) != POINTER_INVALID
                    && zigZagPointHigher.isPeak == zigZagPoint.isPeak) {
                return index;
            }
        }
        
        
        // 右側の検索
        index = this.getRightIndex(fromRightIndex);

        if (index < 0) {
            return -1;
        }

        ZigZagPoint *zigZagPoint =
            this.orgZigZagPointList.At(index);

        if (CheckPointer(zigZagPoint) != POINTER_INVALID
                && zigZagPointHigher.isPeak == zigZagPoint.isPeak) {
            return index;
        }
        
        return -1;
    }
    
    /**
     * 左境界より過去側にある最初のポイント位置を取得する。
     *
     * @param leftIndex 左境界のバーインデックス
     * @return 該当位置。存在しない場合-1
     */
    int getLeftIndex(int leftIndex) {
        
        for (int i = 0; i < this.orgZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(i);
            
            if (zigZagPoint.barIndex > leftIndex) {
                return i;
            }
        }
        
        return -1;
    }
    
    /**
     * 右境界より過去側にあるポイントの直前位置を取得する。
     *
     * @param rightIndex 右境界のバーインデックス
     * @return 該当位置。存在しない場合-1
     */
    int getRightIndex(int rightIndex) {
        
        for (int i = 0; i < this.orgZigZagPointList.Total() - 1; i++) {
            ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(i + 1);
            
            if (zigZagPoint.barIndex > rightIndex) {
                return i;
            }
        }
        
        return -1;
    }
    
};







