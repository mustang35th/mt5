//+------------------------------------------------------------------+
//|                                                  ZigZagPoint.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Object.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\FiboDepthZone.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

class Wave; // forward 宣言

/**
 * ZigZagPoint は ZigZag インジケータから検出された
 * ひとつの転換ポイントを表すデータクラスです。
 */
class ZigZagPoint : public CObject {
public:
    /** 分析対象の市場コンテキスト */
    MarketContext marketContext;

    /** ポイントの価格 */
    double rate;

    /** ローソク足の位置を表すバーインデックス */
    int barIndex;

    /** ローソク足の開始時刻 */
    datetime barTime;

    /** 次のローソク足の開始時刻 */
    datetime barTimeNext;

    /** 波動開始からの経過本数 */
    int waveBarsFromStart;

    /** ZigZagの山の場合true、谷の場合false */
    bool isPeak;

    /** ZigZagから取得できず補完したポイントの場合true */
    bool isAddedPoint;

    /** 前回ポイントとの価格差。単位はpips、小数点以下1桁 */
    double pipsDiff;

    /** 前回ポイントからのフィボナッチ・リトレースメント。単位は%、小数点以下1桁 */
    double fibonacciPercent;

    /** フィボナッチ深度ゾーン */
    ENUM_FIBO_DEPTH_ZONE fiboDepthZone;

    /** フィボナッチ深度ゾーンの表示名 */
    string fiboDepthZoneLabel;

    /** 前回ポイントからのフィボナッチ・エクスパンション。単位は%、小数点以下1桁 */
    double fibonacciExpansionPercent;

    /** エリオット波動ラベルがアルファベットの場合true */
    bool isElliotAlphabet;

    /** エリオット波動番号 */
    int elliotIndex;

    /** エリオット波動ラベル */
    string elliotLabel;

    /** 下位波動番号 */
    int subElliotIndex;

    /** 下位波動ラベル */
    string subElliotLabel;

    /** 再分析前のエリオット波動番号 */
    int orgElliotIndex;

    /** 再分析前のエリオット波動ラベル */
    string orgElliotLabel;

    /** 補正済みポイントの場合true */
    bool isCorrect;

    /** 親Waveへの非所有参照 */
    Wave *parentWave;
    
public:
    /**
     * デフォルトコンストラクタ。
     * 無効な状態を表す初期値を設定します。
     */
    ZigZagPoint() {
    }

    /**
     * シンボル名と時間足を指定して初期化する。
     *
     * @param fromSymbolName シンボル名
     * @param fromTimeFrame 時間足
     */
    ZigZagPoint(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.setMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    ZigZagPoint(MarketContext &fromMarketContext) {
        this.setMarketContext(fromMarketContext);
    }

    /**
     * 分析対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
    }

    /**
     * このインスタンスの内容を複製した ZigZagPoint を生成して返します。
     *
     * @return 複製された ZigZagPoint。メモリ確保に失敗した場合は NULL。
     */
    ZigZagPoint *clone() const {
        ZigZagPoint *zigZagPoint = new ZigZagPoint();

        if (zigZagPoint == NULL) {
            return NULL;
        }

        zigZagPoint.marketContext = this.marketContext;

        zigZagPoint.rate = this.rate;
        zigZagPoint.barIndex = this.barIndex;
        zigZagPoint.barTime = this.barTime;
        zigZagPoint.barTimeNext = this.barTimeNext;

        zigZagPoint.waveBarsFromStart = this.waveBarsFromStart;

        zigZagPoint.isPeak = this.isPeak;
        zigZagPoint.isAddedPoint = this.isAddedPoint;

        zigZagPoint.pipsDiff = this.pipsDiff;
        
        zigZagPoint.fibonacciPercent = this.fibonacciPercent;
        zigZagPoint.fiboDepthZone = this.fiboDepthZone;
        zigZagPoint.fiboDepthZoneLabel = this.fiboDepthZoneLabel;
        
        zigZagPoint.fibonacciExpansionPercent = this.fibonacciExpansionPercent;

        zigZagPoint.elliotIndex = this.elliotIndex;
        zigZagPoint.elliotLabel = this.elliotLabel;
        zigZagPoint.isElliotAlphabet = this.isElliotAlphabet;
        
        zigZagPoint.subElliotIndex = this.subElliotIndex;
        zigZagPoint.subElliotLabel = this.subElliotLabel;

        zigZagPoint.orgElliotIndex = this.orgElliotIndex;
        zigZagPoint.orgElliotLabel = this.orgElliotLabel;

        zigZagPoint.isCorrect = this.isCorrect;
        
        return zigZagPoint;
    }

    /**
     * CObject インターフェースに従い、このインスタンスの複製を返します。
     *
     * @return 複製された CObject。
     */
    virtual CObject *Clone() const {
        ZigZagPoint *zigZagPoint = this.clone();

        return zigZagPoint;
    }

    /**
     * ポイント情報をCSV形式で取得する。
     *
     * @return CSV形式のポイント情報
     */
    string getCsv() {
        string csv = "";
                
        // elliotLabel, 
        // subElliotLabel, 
        // rate, 
        // pipsDiff, 
        // fibonacciExpansionPercent, 
        
        // fibonacciPercent, fiboDepthZoneLabel, barIndex, barTime, waveBarsFromStart,
        // isPeak, isAddedPoint
        
        
        csv += StringFormat("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", 
                    this.elliotLabel,
                    this.subElliotLabel,
                    this.getTextRate(),
                    DoubleToString(this.pipsDiff, 1),
                    DoubleToString(this.fibonacciExpansionPercent, 1),
                    
                    DoubleToString(this.fibonacciPercent, 1),
                    this.fiboDepthZoneLabel,
                    IntegerToString(this.barIndex),
                    TimeUtil::formatYyyymmddhhmiss(this.barTime),
                    IntegerToString(this.waveBarsFromStart),
                    
                    (string)isPeak,
                    (string)isAddedPoint
                );
        
        return csv;
    }
    
    /**
     * 波動ラベル、フィボナッチ情報、値幅および価格の表示文字列を取得する。
     *
     * @return ポイントのインデックス情報
     */
    string getTextIndexInfo() {
        string text = "";
        
        text += this.getTextSimple();
                
        text += this.getTextFibonacci();
        
        text += this.getTextPipsDiff();

        text += this.getTextRate();
        
        return text;
    }
    
    /**
     * 波動番号に応じたフィボナッチ情報を取得する。
     *
     * @return フィボナッチ情報。対象外の場合は空文字列
     */
    string getTextFibonacci() {
        string text = "";
        
        int index = this.orgElliotIndex;
        
        if (index > 1) {
	        if (Util::isEven(index)) {
                text += "[F" + DoubleToString(this.fibonacciPercent, 1) + "%]";
            } else {
                text += "[FE" + DoubleToString(this.fibonacciExpansionPercent, 1) + "%]";
            }
        }
        
        return text;
    }
    
    /**
     * 前回ポイントとの値幅を表示文字列で取得する。
     *
     * @return pips単位の値幅
     */
    string getTextPipsDiff() {
        string text = "";
        
        text += "<" + DoubleToString(this.pipsDiff, 1) + "p>";
        
        return text;
    }
    
    /**
     * シンボルの小数桁数に合わせた価格文字列を取得する。
     *
     * @return ポイントの価格文字列
     */
    string getTextRate() {
        string text = "";
        
        text += DoubleToString(this.rate, this.marketContext.digits);
        
        return text;
    }
    
    /**
     * 補完状態、親Waveの方向および波動ラベルを簡易表示で取得する。
     *
     * @return ポイントの簡易表示文字列
     */
    string getTextSimple() {
        string text = "";
        
        if (this.isAddedPoint) {
            text += "★";
        } else {
        }
        
        if (this.parentWave != NULL) {
            text += this.parentWave.trendLabel;
        }
        
        text += this.getElliotLabel();
                
        return text;
    }
    
    /**
     * 補完ポイントを表す表示文字列を取得する。
     *
     * @return 補完ポイントの場合は星印、それ以外は空文字列
     */
    string getTextAddedPoint() {
        string text = "";
        
        if (this.isAddedPoint) {
            text += "★";
        }
        
        return text;
    }
    
    
    /**
     * 上位波動と下位波動を結合したラベルを取得する。
     *
     * @return エリオット波動ラベル
     */
    string getElliotLabel() {
        string text = "";
        
        text += this.elliotLabel;
        
        if (this.subElliotLabel != NULL) {
            text += "." + this.subElliotLabel;
        }
                
        return text;
    }
    
    /**
     * 数字波かつ奇数波の推進波であるか判定する。
     *
     * @return 推進波の場合true
     */
    bool isMotiveWave() {
        bool isMotiveWave = false;
        
        if (Util::isOdd(this.elliotIndex)
                && this.isNumeric()
        ) {
            isMotiveWave = true;
        }
        
        return isMotiveWave;
    }
    
    /**
     * エリオット波動ラベルが数字であるか判定する。
     *
     * @return 数字波の場合true
     */
    bool isNumeric() {
        return !this.isElliotAlphabet;
    }
    
    /**
     * 指定したシンボル・時間足・バーインデックスから、
     * 本ポイントのバー情報（barIndex / barTime / barTimeNext）を設定する。
     *
     * 用途：
     *  - ZigZag の転換点が「どのバーに相当するか」を保持し、
     *    描画や差分計算（pipsDiff 等）で時刻情報を参照できるようにする。
     *
     * 設定内容：
     *  - barIndex    : 対象バーのシフト（0=最新、1=1本前…）
     *  - barTime     : 対象バーの開始時刻（iTime）
     *  - barTimeNext : 次バーの開始時刻（TimeUtil で算出）
     *
     * 注意：
     *  - fromBarIndex がヒストリ範囲外の場合、iTime が 0 を返す可能性がある。
     *  - barTimeNext の算出ロジックは TimeUtil::getNextBarTimeByShift に依存する。
     *
     * @param fromSymbolName  シンボル名（例："USDJPY"）
     * @param fromTimeframe   時間足（例：PERIOD_H1）
     * @param fromBarIndex    バーインデックス（シフト）
     */
    void setBarIndexAndTime(string fromSymbolName, ENUM_TIMEFRAMES fromTimeframe, int fromBarIndex) {
        MarketContext context(fromSymbolName, fromTimeframe);
        this.setBarIndexAndTime(context, fromBarIndex);
    }

    /**
     * 市場コンテキストとバーインデックスからバー情報を設定する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     * @param fromBarIndex バーインデックス
     */
    void setBarIndexAndTime(MarketContext &fromMarketContext, int fromBarIndex) {
        this.setMarketContext(fromMarketContext);

        // バー位置（シフト）を保存
        this.barIndex = fromBarIndex;
    
        // 対象バーの開始時刻を取得
        this.barTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, this.barIndex);
    
        // 次バーの開始時刻を取得（ユーティリティで算出）
        this.barTimeNext = TimeUtil::getNextBarTimeByShift(
            this.marketContext.symbolName,
            this.marketContext.timeFrame,
            this.barIndex
        );
    }
    
    /**
     * 波動番号とラベル種別からエリオット波動ラベルを設定する。
     */
    void setElliotLabel() {
        this.elliotLabel = this.getIndexText(this.elliotIndex, this.isElliotAlphabet);
    }
    
    
    /**
     * ZigZagPoint の内容を文字列化する。
     *
     * 仕様：
     * - 先頭で改行する
     * - 項目ごとに改行する
     * - 「,」は出力しない
     * - rate の小数点は symbolName から取得した digits に合わせる
     * - コメントに単位/小数点指定がある double は反映する
     *
     * @return 内容文字列
     */
    string toString() {
        string text = "\n";
    
        int digits = 5;
    
        if (this.marketContext.symbolName != "") {
            digits = this.marketContext.digits;
    
            if (digits <= 0) {
                digits = 5;
            }
        }
    
        string rateFormat = StringFormat("rate=%%.%df\n", digits);
    
        text += StringFormat("symbolName=%s\n", this.marketContext.symbolName);
        text += StringFormat("timeFrame=%d\n", (int)this.marketContext.timeFrame);
        text += StringFormat("timeFrameLabel=%s\n", this.marketContext.timeFrameLabel);
    
        text += StringFormat(rateFormat, this.rate);
    
        text += StringFormat("barIndex=%d\n", this.barIndex);
        text += StringFormat("barTime=%s\n", TimeToString(this.barTime, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
        text += StringFormat("barTimeNext=%s\n", TimeToString(this.barTimeNext, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
    
        text += StringFormat("isPeak=%s\n", this.isPeak ? "true" : "false");
        text += StringFormat("isAddedPoint=%s\n", this.isAddedPoint ? "true" : "false");
    
        text += StringFormat("pipsDiff=%.1f pips\n", this.pipsDiff);
        text += StringFormat("fibonacciPercent=%.1f %%\n", this.fibonacciPercent);
        text += StringFormat("fibonacciExpansionPercent=%.1f %%\n", this.fibonacciExpansionPercent);
    
        text += StringFormat("elliotIndex=%d\n", this.elliotIndex);
        text += StringFormat("elliotLabel=%s\n", this.elliotLabel);
        text += StringFormat("isElliotAlphabet=%s\n", this.isElliotAlphabet ? "true" : "false");
        
        text += StringFormat("subElliotIndex=%s\n", this.subElliotIndex);
        text += StringFormat("subElliotLabel=%s\n", this.subElliotLabel);
        
        text += StringFormat("orgElliotIndex=%d\n", this.orgElliotIndex);
        text += StringFormat("orgElliotLabel=%s\n", this.orgElliotLabel);
        
        text += StringFormat("isCorrect=%s\n", (string)this.isCorrect);
        
        if (this.parentWave != NULL) {
            text += StringFormat("parentWave=%s\n", this.parentWave.toString());
        } else {
            text += StringFormat("parentWave=%s\n", "NULL");
        }
        
        text += StringFormat("getTextSimple()=%s\n", this.getTextSimple());
        text += StringFormat("getTextIndexInfo()=%s\n", this.getTextIndexInfo());
        
        return text;
    }

private:
    /**
     * 波動番号を数字またはアルファベットの表示文字列へ変換する。
     *
     * @param fromIndex 波動番号
     * @param fromIsAlphabet アルファベットへ変換する場合true
     * @return 変換後の波動ラベル
     */
    string getIndexText(int fromIndex, bool fromIsAlphabet) {
        string indexText = string(fromIndex);
        
        if (fromIsAlphabet) {
            switch(fromIndex) {
                case 1:
                    indexText = "A";
                    break;
                
                case 2:
                    indexText = "B";
                    break;
                
                case 3:
                    indexText = "C";
                    break;
                
                case 4:
                    indexText = "D";
                    break;
                    
                case 5:
                    indexText = "E";
                    break;
                    
                default:
                    indexText = "#" + indexText;
            }
        }
        
        return indexText;
    }
};






