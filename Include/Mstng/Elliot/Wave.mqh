//+------------------------------------------------------------------+
//|                                                         Wave.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef __WAVE_MQH__
#define __WAVE_MQH__

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZag.mqh>
#include <Mstng\Util\UtilAll.mqh>

class Elliot; // forward 宣言

/**
 * 波動情報クラス。
 *
 * ZigZagPoint のリストを保持し、Elliot ラベル付けや pips 差分などの
 * 波動分析に必要な属性を設定する。
 */
class Wave : public CObject {
public:
    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;
    
    /** 親となるWave一覧内のインデックス。0が最新 */
    int index;
    
    /** Wave確定状態。true: 確定、false: 未確定 */
    bool isConfirmed;

    /** Wave種別。true: 推進波、false: 修正波 */
    bool isMotive;

    /** Wave方向。true: 上昇、false: 下降 */
    bool isUptrend;

    /** Wave方向の表示用ラベル。上昇は▲、下降は▼ */
    string trendLabel;
    
    /** 1つ前のWaveにおける最終Elliottラベル */
    string previousLastElliotLabel;
    
    /** 分析に使用するZigZagポイント一覧 */
    CArrayObj zigZagPointList;

    /** 再カウント処理で生成されたZigZagポイント一覧 */
    CArrayObj recountZigZagPointList;

    /** 補正・再分析前の元ZigZagポイント一覧 */
    CArrayObj orgZigZagPointList;
    
    /** このWaveを保持するElliotへの非所有参照 */
    Elliot *parentElliot;
    
    /**
     * デフォルトコンストラクタ。
     */
    Wave() {
    }
    
    /**
     * コンストラクタ。
     *
     * 外部から渡された ZigZagPoint リストを内部リストへコピーし、
     * 推進波／修正波、トレンド方向の属性を保持する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 分析対象時間足
     * @param fromZigZagPointList ZigZagPoint の参照リスト
     * @param fromIsMotive        推進波かどうか
     * @param fromIsUptrend       上昇トレンドかどうか
     */
    Wave(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, CArrayObj &fromZigZagPointList, bool fromIsMotive, bool fromIsUptrend) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromZigZagPointList, fromIsMotive, fromIsUptrend);
    }

    /**
     * 市場コンテキストとZigZagポイント一覧を指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromZigZagPointList ZigZagPointの参照リスト
     * @param fromIsMotive 推進波の場合true
     * @param fromIsUptrend 上昇トレンドの場合true
     */
    Wave(MarketContext &fromMarketContext, CArrayObj &fromZigZagPointList, bool fromIsMotive, bool fromIsUptrend) {
        this.initialize(fromMarketContext, fromZigZagPointList, fromIsMotive, fromIsUptrend);
    }

    /**
     * デストラクタ。
     *
     * 現状、zigZagPointList の解放方針は ZigZagPointUtil 側の実装に依存する。
     * （必要であればここで delete & Clear を追加する）
     */
    ~Wave() {
    }
    
    /**
     * 波動分析を実行する。
     *
     * 現在有効化している処理:
     * - Elliot ラベル付け
     * - pips 差分の算出
     *
     */
    void analyze() {
        this.setElliotLabel();
        // this.setHighLow();
        this.setPipsAndWaveBarsFromStart();
        this.setFibonacci();
        this.setFibonacciExpansion();
    }
    
    /**
     * Wave を複製します（深いコピー）。
     *
     * zigZagPointList の要素も複製して新しいリストに追加します。
     *
     * @return 複製された Wave のポインタ（呼び出し側で delete するか、所有権管理に委譲）
     */
    Wave *clone() {
        Wave *clonedWave = new Wave();
        clonedWave.setMarketContext(this.marketContext);
    
        clonedWave.index = this.index;
    
        clonedWave.isConfirmed = this.isConfirmed;
        clonedWave.isMotive = this.isMotive;
        clonedWave.isUptrend = this.isUptrend;
        clonedWave.trendLabel = this.trendLabel;
        
        ZigZagPointUtil::copyZigZagPointList(this.zigZagPointList, clonedWave.zigZagPointList);
        ZigZagPointUtil::copyZigZagPointList(this.orgZigZagPointList, clonedWave.orgZigZagPointList);
    
        return clonedWave;
    }
    
    /**
     * CSV出力用に直近の過去ポイント情報を取得する。
     *
     * pre3、pre2、pre1に相当する3ポイント分を出力し、不足分は空列で補う。
     *
     * @return 3ポイント分のCSV文字列
     */
    string getCsv() {
        const int countCsv = 12;
        
        string csv = "";
        
        //pre3, pre2, pre1
        
        // 偶数 0,1,2,3→0,1,2
        
        // 奇数 0,1,2→,0,1
        
        // 2個 0,1→,,0
        
        int total = this.zigZagPointList.Total();
        
        if (total < 2) {
            csv += StringFormat("%s,", Util::getCsvBlank(countCsv));
            csv += StringFormat("%s,", Util::getCsvBlank(countCsv));
            csv += StringFormat("%s,", Util::getCsvBlank(countCsv));
        } else {
            if (total == 2) {
                csv += StringFormat("%s,", Util::getCsvBlank(countCsv));
                csv += StringFormat("%s,", Util::getCsvBlank(countCsv));
                
                ZigZagPoint *zigZagPoint = this.zigZagPointList.At(0);
                
                csv += StringFormat("%s,", zigZagPoint.getCsv());
            } else {
                if (Util::isEven(total)) {  // 偶数
                    for (int i = total - 4; i < total - 1; i++) {
                        ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
                
                        csv += StringFormat("%s,", zigZagPoint.getCsv());
                    }
                } else {
                    csv += StringFormat("%s,", Util::getCsvBlank(countCsv));
                    
                    for (int i = total - 3; i < total - 1; i++) {
                        ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
                
                        csv += StringFormat("%s,", zigZagPoint.getCsv());
                    }
                }
            }
        }
        
        
        
        
        
        return csv;
    }
    
    /**
     * 最新ポイントを取得する。
     *
     * @return zigZagPointListの最後にある最新ポイント。空の場合NULL
     */
    ZigZagPoint *getLatestPoint() {
        return ZigZagPointUtil::getLastNode(this.zigZagPointList);
    }
    
    /**
     * 最新ポイントの1つ前を取得する。
     *
     * @return 最新ポイントの1つ前。2点未満の場合NULL
     */
    ZigZagPoint *getLatestPoint2() {
        int total = this.zigZagPointList.Total();
        
        if (total < 2) {
            return NULL;
        }
        
        return this.zigZagPointList.At(total - 2);
    }
    
    /**
     * 1つ前のWaveと比較して現在Waveの確定状態を設定する。
     *
     * @param waveBefore 1つ前のWave
     */
    void setConfirmed(Wave &waveBefore) {
        this.isConfirmed = false;
        
        int total = this.zigZagPointList.Total();        
                    
        // 0,1はなし
        if (total < 2) {
            return;
        }
        
        if (total == 2) {   // 1波の場合、前回の波動と比較
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(1);
            ZigZagPoint *zigZagPointBefore = waveBefore.zigZagPointList.At(waveBefore.zigZagPointList.Total() - 2);
            
            if (this.isUptrend) {
                if (zigZagPointBefore.rate < zigZagPoint.rate) {
                    this.isConfirmed = true;
                }
            } else {
                if (zigZagPointBefore.rate > zigZagPoint.rate) {
                    this.isConfirmed = true;
                }
            }
            
            return;
        }
        
        if (Util::isEven(total)) {   // 波動は奇数
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(total - 1);
            ZigZagPoint *zigZagPointBefore = this.zigZagPointList.At(total - 3);
            
            if (this.isUptrend) {
                if (zigZagPointBefore.rate < zigZagPoint.rate) {
                    this.isConfirmed = true;
                }
            } else {
                if (zigZagPointBefore.rate > zigZagPoint.rate) {
                    this.isConfirmed = true;
                }
            }            
        } else {
            this.isConfirmed = true;
        }
    }
    
    /**
     * zigZagPointList 内の全 ZigZagPoint に親 Wave（参照）を設定する。
     *
     * 目的：
     *  - ZigZagPoint 側から parentWave 経由で Wave 情報（trendLabel 等）へアクセスできるようにする。
     *
     * 注意：
     *  - ZigZagPoint::parentWave は「参照」であり、ZigZagPoint 側では delete しない（所有権は Wave 側）。
     *  - zigZagPointList は CArrayObj のため、At(i) の戻りは CObject* になることが多い。
     *    そのため ZigZagPoint* へキャストして使用する。
     *
     * @param wave 設定する親 Wave（NULL も許容）
     */
    void setParentWave(Wave *wave) {
        for (int i = 0; i < this.zigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
    
            if (zigZagPoint == NULL) {
                continue;
            }
    
            zigZagPoint.parentWave = wave;
        }
        
        for (int i = 0; i < this.orgZigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = this.orgZigZagPointList.At(i);
    
            if (zigZagPoint == NULL) {
                continue;
            }
    
            zigZagPoint.parentWave = wave;
        }
    }
    
    /**
     * デバッグ用に、この Wave の内容を文字列として返します。
     *
     * zigZagPointList は全要素を連結するとログが肥大化しやすいため、
     * 件数と、先頭/末尾のポイント（取得できる場合）を出力します。
     *
     * @return "Wave{...}" 形式の文字列
     */
    string toString() {
        string text = "";
    
        // 先頭で改行
        text += "\n";
    
        // 項目毎に改行（"," は付けない）
        text += "    symbolName=" + this.marketContext.symbolName + "\n";
        text += "    timeFrame=" + IntegerToString((int)this.marketContext.timeFrame) + "\n";
        text += "    timeFrameLabel=" + this.marketContext.timeFrameLabel + "\n";
    
        text += "    index=" + IntegerToString(this.index) + "\n";

        string isConfirmedText = "false";
        string isMotiveText = "false";
        string isUptrendText = "false";

        if (this.isConfirmed) {
            isConfirmedText = "true";
        }

        if (this.isMotive) {
            isMotiveText = "true";
        }

        if (this.isUptrend) {
            isUptrendText = "true";
        }

        text += "    isConfirmed=" + isConfirmedText + "\n";
        text += "    isMotive=" + isMotiveText + "\n";
        text += "    isUptrend=" + isUptrendText + "\n";
        text += "    trendLabel=" + this.trendLabel + "\n";
    
        // CArrayObj は件数のみ
        text += "    zigZagPointListTotal=" + IntegerToString(this.zigZagPointList.Total()) + "\n";
    
        return text;
    }

private:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;

    /**
     * 市場コンテキストとWave属性を初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromZigZagPointList ZigZagPointの参照リスト
     * @param fromIsMotive 推進波の場合true
     * @param fromIsUptrend 上昇トレンドの場合true
     */
    void initialize(MarketContext &fromMarketContext, CArrayObj &fromZigZagPointList, bool fromIsMotive, bool fromIsUptrend) {
        this.setMarketContext(fromMarketContext);

        // ZigZagPointをディープコピーして参照共有による副作用を避ける
        ZigZagPointUtil::copyZigZagPointList(fromZigZagPointList, this.zigZagPointList);

        this.isMotive = fromIsMotive;
        this.setTrend(fromIsUptrend);
    }

    /**
     * 市場コンテキストを設定する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
    }

    /**
     * Elliot ラベル付けの設定を行う。
     *
     * - 推進波の場合: 数字ラベル
     * - 修正波の場合: アルファベットラベル
     */
    void setElliotLabel() {
        bool isAlphabet = false;
        
        // 修正波は A-B-C などのアルファベット表記とする
        if (!this.isMotive) {
            isAlphabet = true;
        }
        
        this.setElliotLabel(isAlphabet);
    }
    
    /**
     * ZigZagPoint に Elliot インデックスとラベルを設定する。
     *
     * @param isAlphabet true の場合はアルファベット表記でラベルを生成する
     */
    void setElliotLabel(bool isAlphabet) {
        // 0 から順に Elliot インデックスを設定
        for (int i = 0; i < this.zigZagPointList.Total(); i++) {
            ZigZagPoint *zigZagPoint = zigZagPointList.At(i);
            
            zigZagPoint.elliotIndex = i;
            zigZagPoint.isElliotAlphabet = isAlphabet;
            zigZagPoint.setElliotLabel();
        }
    }
    
    /**
     * 戻り波の値幅を直前の進行波に対する比率として設定する。
     *
     * 計算結果は対象ポイントのfibonacciPercentとfiboDepthZoneへ保持する。
     */
    void setFibonacci() {
        for (int i = 1; i < this.zigZagPointList.Total() - 1; i += 2) {
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
            ZigZagPoint *zigZagPointNext = this.zigZagPointList.At(i + 1);
            
            double percent = 0;
            
            if (zigZagPoint.pipsDiff > 0) {
                percent = zigZagPointNext.pipsDiff / zigZagPoint.pipsDiff;
            }
            
            zigZagPointNext.fibonacciPercent = NormalizeDouble(percent * 100, 1);
            
            zigZagPointNext.fiboDepthZone = FiboDepthZone::getZone(zigZagPointNext.fibonacciPercent);
            zigZagPointNext.fiboDepthZoneLabel = FiboDepthZone::toString(zigZagPointNext.fiboDepthZone);
            
        }
    }
    
    /**
     * 進行波の値幅を2つ前の進行波に対する比率として設定する。
     *
     * 計算結果は対象ポイントのfibonacciExpansionPercentへ保持する。
     */
    void setFibonacciExpansion() {
        for (int i = 3; i < this.zigZagPointList.Total(); i += 2) {
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
            ZigZagPoint *zigZagPointBefore2 = this.zigZagPointList.At(i - 2);
            
            double percent = 0;
            
            if (zigZagPointBefore2.pipsDiff > 0) {
                percent = zigZagPoint.pipsDiff / zigZagPointBefore2.pipsDiff;
            }
            
            zigZagPoint.fibonacciExpansionPercent = percent * 100;
        }
    }
    
    /**
     * ZigZagPoint 間の pips 差分を計算して設定する。
     *
     * - i と i+1 のレート差分を pips に換算し、
     *   「次の点（i+1）」へ格納する。
     *
     */
    void setPipsAndWaveBarsFromStart() {        
        // 最後の点は next が存在しないため Total()-1 まで
        for (int i = 0; i < this.zigZagPointList.Total() - 1; i++) {
            ZigZagPoint *zigZagPoint = this.zigZagPointList.At(i);
            ZigZagPoint *zigZagPointNext = this.zigZagPointList.At(i + 1);
            
            // 2 点間の値幅を pips に換算し、次の点に保持
            zigZagPointNext.pipsDiff = RateUtil::getDiffPips(zigZagPoint.rate, zigZagPointNext.rate, this.marketContext.symbolName);
            
            zigZagPointNext.waveBarsFromStart = zigZagPoint.barIndex - zigZagPointNext.barIndex;
        }
    }
    
    /**
     * Wave方向と表示用ラベルを設定する。
     *
     * @param fromIsUptrend true: 上昇、false: 下降
     */
    void setTrend(bool fromIsUptrend) {
        this.isUptrend = fromIsUptrend;
        
        if (this.isUptrend) {
            this.trendLabel = "▲";
        } else {
            this.trendLabel = "▼";
        }
    }
};

#endif







