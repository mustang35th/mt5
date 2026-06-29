//+------------------------------------------------------------------+
//|                                      OscillatorHandleManager.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_OSCILLATOR_HANDLE_MANAGER_MQH
#define MSTNG_OSCILLATOR_HANDLE_MANAGER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * @class OscillatorHandleManager
 * @brief SymbolNameInfoAll に含まれる全通貨ペア分の OscillatorHandlePool を管理します。
 *
 * - OscillatorHandlePool を CArrayObj で保持
 * - コンストラクタで SymbolNameInfoAll の全シンボルを走査し Pool を new して List に追加
 * - デストラクタで Pool を delete（内部の releaseAll は Pool 側デストラクタで実行）
 */
class OscillatorHandleManager : public CObject {
public:
    /**
     * @brief コンストラクタ
     *
     * @param fromTimeFrame Pool 側で使う終端時間足（例: PERIOD_M1 / PERIOD_H1 など）
     */
    OscillatorHandleManager(const ENUM_TIMEFRAMES fromTimeFrame) {
        this.timeFrame = fromTimeFrame;
        this.buildPools();
    }

    /**
     * @brief デストラクタ
     */
    ~OscillatorHandleManager() {
        this.clear();
    }

    /**
     * @brief 管理している Pool 数
     */
    int size() const {
        return this.poolList.Total();
    }

    /**
     * @brief index で Pool 取得（範囲外なら NULL）
     */
    OscillatorHandlePool* getPoolByIndex(const int index) {
        if(index < 0 || index >= this.poolList.Total()) {
            return NULL;
        }
        return (OscillatorHandlePool*)this.poolList.At(index);
    }

    /**
     * @brief symbolName で Pool 取得（見つからなければ NULL）
     */
    OscillatorHandlePool* getPoolBySymbol(const string fromSymbolName) {
        const string key = StringSubstr(fromSymbolName, 0, 6);

        const int total = this.poolList.Total();
        for(int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if(pool == NULL) {
                continue;
            }

            if(pool.symbolName == key) {
                return pool;
            }
        }

        return NULL;
    }

    /**
     * @brief 各 Pool に対し setTimeframesFromMn1To() を実行します。
     *        (MN1 -> this.timeFrame の範囲で各オシレーターのハンドルを準備)
     */
    void setTimeframesFromMn1ToAll() {
        const int total = this.poolList.Total();
        for(int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if(pool == NULL) {
                continue;
            }
            pool.setTimeframesFromMn1To();
        }
    }

    /**
     * @brief 各 Pool に対し setTimeframesFromD1To() を実行します。
     *        (D1 -> this.timeFrame の範囲で各オシレーターのハンドルを準備)
     */
    void setTimeframesFromD1ToAll() {
        const int total = this.poolList.Total();
        for(int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if(pool == NULL) {
                continue;
            }
            pool.setTimeframesFromD1To();
        }
    }

    /**
     * @brief 全 Pool の indicator handle を解放します（Pool 自体は保持）。
     */
    void releaseAll() {
        const int total = this.poolList.Total();
        for(int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if(pool == NULL) {
                continue;
            }
            pool.releaseAll();
        }
    }

    /**
     * @brief 全 Pool を delete し List を空にします。
     */
    void clear() {
        const int total = this.poolList.Total();
        for(int i = 0; i < total; i++) {
            CObject *obj = this.poolList.At(i);
            if(obj != NULL) {
                delete obj;
            }
        }
        this.poolList.Clear();
    }

private:
    ENUM_TIMEFRAMES timeFrame;

    // Symbol list
    SymbolNameInfoAll symbolNameInfoAll;

    // Pools for each symbol
    CArrayObj poolList;

    /**
     * @brief SymbolNameInfoAll の全シンボル分 Pool を生成して poolList に格納
     */
    void buildPools() {
        const int total = this.symbolNameInfoAll.size();

        for(int i = 0; i < total; i++) {
            SymbolNameInfo *info = this.symbolNameInfoAll.getSymbolNameInfo(i);
            
            if(info == NULL) {
                continue;
            }

            const string symbol = info.symbolName;
            MarketContext context(symbol, this.timeFrame);

            OscillatorHandlePool *pool = new OscillatorHandlePool(context);
            this.poolList.Add(pool);
        }
    }
};

#endif // MSTNG_OSCILLATOR_HANDLE_MANAGER_MQH
