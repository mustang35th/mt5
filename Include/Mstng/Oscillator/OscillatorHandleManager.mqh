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
 * 複数シンボルのOscillatorHandlePoolを管理するクラス。
 *
 * SymbolNameInfoAllに登録されたシンボルごとにハンドルプールを生成し、
 * 時間足範囲の設定、検索、ハンドル解放およびプール破棄を一括管理する。
 */
class OscillatorHandleManager : public CObject {
public:
    /** 複数シンボルのハンドル生成範囲を表す市場コンテキスト。 */
    MarketContext marketContext;

    /**
     * 終端時間足を指定してシンボル別ハンドルプールを初期化する。
     *
     * @param fromTimeFrame ハンドルを生成する終端時間足。
     */
    OscillatorHandleManager(const ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(
            "ALL",
            fromTimeFrame,
            TimeUtil::convertTimeFrameToString(fromTimeFrame),
            0
        );
        this.initialize(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト。
     */
    OscillatorHandleManager(MarketContext &fromMarketContext) {
        this.initialize(fromMarketContext);
    }

    /**
     * デストラクタ。
     *
     * 保持している全ハンドルプールを解放する。
     */
    ~OscillatorHandleManager() {
        this.clear();
    }

    /**
     * ハンドル生成範囲の市場コンテキストを設定する。
     *
     * 既存のシンボル別プールを削除してから再構築する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト。
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.clear();
        this.initialize(fromMarketContext);
    }

    /**
     * 管理しているハンドルプール数を取得する。
     *
     * @return ハンドルプール数。
     */
    int size() const {
        return this.poolList.Total();
    }

    /**
     * インデックスに対応するハンドルプールを取得する。
     *
     * @param index 取得対象インデックス。
     * @return 対応するハンドルプール。範囲外の場合NULL。
     */
    OscillatorHandlePool* getPoolByIndex(const int index) {
        if (index < 0 || index >= this.poolList.Total()) {
            return NULL;
        }
        return (OscillatorHandlePool*)this.poolList.At(index);
    }

    /**
     * シンボル名に対応するハンドルプールを取得する。
     *
     * シンボル名の先頭6文字を検索キーとして使用する。
     *
     * @param fromSymbolName 取得対象シンボル。
     * @return 対応するハンドルプール。存在しない場合NULL。
     */
    OscillatorHandlePool* getPoolBySymbol(const string fromSymbolName) {
        const string key = StringSubstr(fromSymbolName, 0, 6);

        const int total = this.poolList.Total();
        for (int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if (pool == NULL) {
                continue;
            }

            if (pool.marketContext.symbolName == key) {
                return pool;
            }
        }

        return NULL;
    }

    /**
     * MarketContextに対応するハンドルプールを取得する。
     *
     * @param fromMarketContext 取得対象の市場コンテキスト。
     * @return 対応するハンドルプール。存在しない場合NULL。
     */
    OscillatorHandlePool *getPoolByMarketContext(MarketContext &fromMarketContext) {
        return this.getPoolBySymbol(fromMarketContext.symbolName);
    }

    /**
     * MarketContextと完全一致するハンドルプールを取得し、未登録なら生成する。
     *
     * 接頭辞または接尾辞付きの実シンボルを動的に追加する場合に使用する。
     *
     * @param fromMarketContext 取得または生成する市場コンテキスト。
     * @return 対応するハンドルプール。生成に失敗した場合NULL。
     */
    OscillatorHandlePool *getOrCreatePool(MarketContext &fromMarketContext) {
        int total = this.poolList.Total();

        for (int i = 0; i < total; i++) {
            OscillatorHandlePool *oscillatorHandlePool = this.poolList.At(i);

            if (oscillatorHandlePool == NULL) {
                continue;
            }

            if (oscillatorHandlePool.marketContext.symbolName
                    == fromMarketContext.symbolName) {
                return oscillatorHandlePool;
            }
        }

        OscillatorHandlePool *oscillatorHandlePool =
            new OscillatorHandlePool(fromMarketContext);

        if (oscillatorHandlePool == NULL) {
            return NULL;
        }

        if (!this.poolList.Add(oscillatorHandlePool)) {
            delete oscillatorHandlePool;

            return NULL;
        }

        return oscillatorHandlePool;
    }

    /**
     * 全プールでMN1から終端時間足までのハンドルを生成する。
     */
    void setTimeframesFromMn1ToAll() {
        const int total = this.poolList.Total();
        for (int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if (pool == NULL) {
                continue;
            }
            pool.setTimeframesFromMn1To();
        }
    }

    /**
     * 全プールでD1から終端時間足までのハンドルを生成する。
     */
    void setTimeframesFromD1ToAll() {
        const int total = this.poolList.Total();
        for (int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if (pool == NULL) {
                continue;
            }
            pool.setTimeframesFromD1To();
        }
    }

    /**
     * 全プールが保持するインジケーターハンドルを解放する。
     *
     * OscillatorHandlePool自体は保持する。
     */
    void releaseAll() {
        const int total = this.poolList.Total();
        for (int i = 0; i < total; i++) {
            OscillatorHandlePool *pool = (OscillatorHandlePool*)this.poolList.At(i);
            if (pool == NULL) {
                continue;
            }
            pool.releaseAll();
        }
    }

    /**
     * 全ハンドルプールを削除し、一覧を空にする。
     */
    void clear() {
        const int total = this.poolList.Total();
        for (int i = 0; i < total; i++) {
            CObject *obj = this.poolList.At(i);
            if (obj != NULL) {
                delete obj;
            }
        }
        this.poolList.Clear();
    }

private:
    /** ハンドルプール生成対象のシンボル一覧。 */
    SymbolNameInfoAll symbolNameInfoAll;

    /** シンボル別OscillatorHandlePool一覧。 */
    CArrayObj poolList;

    /**
     * 市場コンテキストを初期化し、シンボル別プールを生成する。
     *
     * @param fromMarketContext ハンドル生成範囲の基準となる市場コンテキスト。
     */
    void initialize(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.buildPools();
    }

    /**
     * 登録されている全シンボルのハンドルプールを生成する。
     */
    void buildPools() {
        const int total = this.symbolNameInfoAll.size();

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *info = this.symbolNameInfoAll.getSymbolNameInfo(i);
            
            if (info == NULL) {
                continue;
            }

            MarketContext context = this.marketContext;
            context.setSymbolName(info.symbolName);

            OscillatorHandlePool *pool = new OscillatorHandlePool(context);
            this.poolList.Add(pool);
        }
    }
};

#endif // MSTNG_OSCILLATOR_HANDLE_MANAGER_MQH
