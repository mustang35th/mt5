//+------------------------------------------------------------------+
//|                                                   SignalInfo.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Object.mqh>

/**
 * 1つのシグナルの識別情報と検出回数を保持するクラス。
 *
 * シグナルは基準時刻とBUY・SELL方向の組み合わせで識別する。
 */
class SignalInfo : public CObject {
public:
    /**
     * シグナル識別情報を指定して初期化する。
     *
     * @param fromTime シグナルの基準時刻。
     * @param fromIsBuy 売買方向。true: BUY、false: SELL。
     */
    SignalInfo(datetime fromTime, bool fromIsBuy) {
        this.time = fromTime;
        this.isBuy = fromIsBuy;
        this.count = 0;
    }
    
    /**
     * デストラクタ。
     */
    ~SignalInfo() {
    }

    /**
     * シグナル検出回数を加算する。
     *
     * @return 加算後の検出回数。
     */
    int addCount() {
        this.count++;
        
        return this.count;
    }
    
    /**
     * 指定した識別情報と同じシグナルか判定する。
     *
     * @param fromTime シグナルの基準時刻。
     * @param fromIsBuy 売買方向。true: BUY、false: SELL。
     * @return 時刻と売買方向が一致する場合はtrue。
     */
    bool isEqual(datetime fromTime, bool fromIsBuy) {
        bool isEqual = false;
        
        if (this.time == fromTime && this.isBuy == fromIsBuy) {
            isEqual = true;
        }
        
        return isEqual;
    }

private:
    /** 基準となるZigZagポイントの時刻。 */
    datetime time;

    /** 売買方向。true: BUY、false: SELL。 */
    bool isBuy;
    
    /** 同一シグナルの検出回数。 */
    int count;

};

