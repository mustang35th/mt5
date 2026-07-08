//+------------------------------------------------------------------+
//|                                            SymbolNameInfoAll.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __SYMBOL_NAME_INFO_ALL_MQH__
#define __SYMBOL_NAME_INFO_ALL_MQH__

#include <Arrays\ArrayObj.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Constant\SymbolNameInfo.mqh>
#include <Mstng\Log\Logger.mqh>


/**
 * 通貨ペア情報の一覧を管理するクラス。
 *
 * 主要通貨ペアを内部リストに保持し、シンボル名とコードの相互変換、
 * 取引対象可否の参照を行う。
 */
class SymbolNameInfoAll {
public:
    /**
     * コンストラクタ。
     *
     * 内部のシンボルリストを初期化し、
     * 主要な通貨ペアを登録する。
     */
    SymbolNameInfoAll() {
        this.setGmo();
    }
    
    /**
     * 全対象を登録する。
     */
    void setAll() {
        // JPY 7。
        this.add(ConstantCurrency::USDJPY, 101, true);
        this.add(ConstantCurrency::EURJPY, 102, true);
        this.add(ConstantCurrency::GBPJPY, 103, true);
        this.add(ConstantCurrency::AUDJPY, 104, true);
        this.add(ConstantCurrency::NZDJPY, 105, true);
        this.add(ConstantCurrency::CADJPY, 106, true);
        this.add(ConstantCurrency::CHFJPY, 107, true);

        // USD 6。
        this.add(ConstantCurrency::EURUSD, 111, true);
        this.add(ConstantCurrency::GBPUSD, 112, true);
        this.add(ConstantCurrency::AUDUSD, 113, true);
        this.add(ConstantCurrency::NZDUSD, 114, true);
        this.add(ConstantCurrency::USDCAD, 115, true);
        this.add(ConstantCurrency::USDCHF, 116, true);

        // GBP 5。
        this.add(ConstantCurrency::EURGBP, 121, true);
        this.add(ConstantCurrency::GBPAUD, 122, true);
        this.add(ConstantCurrency::GBPNZD, 123, true);
        this.add(ConstantCurrency::GBPCAD, 124, true);
        this.add(ConstantCurrency::GBPCHF, 125, true);

        // EUR 4。
        this.add(ConstantCurrency::EURAUD, 131, true);
        this.add(ConstantCurrency::EURNZD, 132, true);
        this.add(ConstantCurrency::EURCAD, 133, true);
        this.add(ConstantCurrency::EURCHF, 134, true);

        // AUD 3。
        this.add(ConstantCurrency::AUDNZD, 141, true);
        this.add(ConstantCurrency::AUDCAD, 142, true);
        this.add(ConstantCurrency::AUDCHF, 143, true);

        // NZD 2。
        this.add(ConstantCurrency::NZDCAD, 151, true);
        this.add(ConstantCurrency::NZDCHF, 152, true);

        // CAD 1。
        this.add(ConstantCurrency::CADCHF, 162, true);
    }
    
    /**
     * GMO取引用に対象を登録する。
     */
    void setGmo() {
        // JPY 7。
        this.add(ConstantCurrency::USDJPY, 101, true);
        this.add(ConstantCurrency::EURJPY, 102, true);
        this.add(ConstantCurrency::GBPJPY, 103, true);
        this.add(ConstantCurrency::AUDJPY, 104, true);
        this.add(ConstantCurrency::NZDJPY, 105, true);
        this.add(ConstantCurrency::CADJPY, 106, true);
        this.add(ConstantCurrency::CHFJPY, 107, true);

        // USD 6。
        this.add(ConstantCurrency::EURUSD, 111, true);
        this.add(ConstantCurrency::GBPUSD, 112, true);
        this.add(ConstantCurrency::AUDUSD, 113, true);
        this.add(ConstantCurrency::NZDUSD, 114, true);
        this.add(ConstantCurrency::USDCAD, 115, false);
        this.add(ConstantCurrency::USDCHF, 116, true);

        // GBP 5。
        this.add(ConstantCurrency::EURGBP, 121, true);
        this.add(ConstantCurrency::GBPAUD, 122, true);
        this.add(ConstantCurrency::GBPNZD, 123, false);
        this.add(ConstantCurrency::GBPCAD, 124, false);
        this.add(ConstantCurrency::GBPCHF, 125, true);

        // EUR 4。
        this.add(ConstantCurrency::EURAUD, 131, true);
        this.add(ConstantCurrency::EURNZD, 132, false);
        this.add(ConstantCurrency::EURCAD, 133, false);
        this.add(ConstantCurrency::EURCHF, 134, true);

        // AUD 3。
        this.add(ConstantCurrency::AUDNZD, 141, true);
        this.add(ConstantCurrency::AUDCAD, 142, false);
        this.add(ConstantCurrency::AUDCHF, 143, false);

        // NZD 2。
        this.add(ConstantCurrency::NZDCAD, 151, false);
        this.add(ConstantCurrency::NZDCHF, 152, false);

        // CAD 1。
        this.add(ConstantCurrency::CADCHF, 162, false);
    }
    
    /**
     * ディスクリショナリー向けの対象を登録する。
     */
    void setDiscretionary() {
        // JPY 7。
        this.add(ConstantCurrency::USDJPY, 101, true);
        this.add(ConstantCurrency::EURJPY, 102, true);
        this.add(ConstantCurrency::GBPJPY, 103, true);
        this.add(ConstantCurrency::AUDJPY, 104, true);
        this.add(ConstantCurrency::NZDJPY, 105, false);
        this.add(ConstantCurrency::CADJPY, 106, false);
        this.add(ConstantCurrency::CHFJPY, 107, false);

        // USD 6。
        this.add(ConstantCurrency::EURUSD, 111, true);
        this.add(ConstantCurrency::GBPUSD, 112, true);
        this.add(ConstantCurrency::AUDUSD, 113, true);
        this.add(ConstantCurrency::NZDUSD, 114, true);
        this.add(ConstantCurrency::USDCAD, 115, false);
        this.add(ConstantCurrency::USDCHF, 116, true);

        // GBP 5。
        this.add(ConstantCurrency::EURGBP, 121, false);
        this.add(ConstantCurrency::GBPAUD, 122, false);
        this.add(ConstantCurrency::GBPNZD, 123, false);
        this.add(ConstantCurrency::GBPCAD, 124, false);
        this.add(ConstantCurrency::GBPCHF, 125, false);

        // EUR 4。
        this.add(ConstantCurrency::EURAUD, 131, false);
        this.add(ConstantCurrency::EURNZD, 132, false);
        this.add(ConstantCurrency::EURCAD, 133, false);
        this.add(ConstantCurrency::EURCHF, 134, false);

        // AUD 3。
        this.add(ConstantCurrency::AUDNZD, 141, false);
        this.add(ConstantCurrency::AUDCAD, 142, false);
        this.add(ConstantCurrency::AUDCHF, 143, false);

        // NZD 2。
        this.add(ConstantCurrency::NZDCAD, 151, false);
        this.add(ConstantCurrency::NZDCHF, 152, false);

        // CAD 1。
        this.add(ConstantCurrency::CADCHF, 162, false);
    }

    /**
     * デストラクタ。
     *
     * 内部で保持しているSymbolNameInfoインスタンスを解放する。
     */
    ~SymbolNameInfoAll() {
        int total = this.symbolNameInfoList.Total();

        for (int i = 0; i < total; i++) {
            CObject *obj = this.symbolNameInfoList.At(i);

            if (obj != NULL) {
                delete obj;
            }
        }

        this.symbolNameInfoList.Clear();
    }

    

    /**
     * インデックスから SymbolNameInfo を取得する。
     *
     * @param index インデックス。
     * @return SymbolNameInfoへのポインタ。存在しない場合はNULL。
     */
    SymbolNameInfo *getSymbolNameInfo(int index) {
        if (index < 0) {
            return NULL;
        }

        if (index >= this.symbolNameInfoList.Total()) {
            return NULL;
        }

        return this.symbolNameInfoList.At(index);
    }

    /**
     * リストの要素数を取得する。
     *
     * @return 要素数。
     */
    int size() {
        return this.symbolNameInfoList.Total();
    }

    /**
     * シンボル名からコードを取得する。
     *
     * @param fromSymbolName シンボル名。サフィックス付きでも可。
     * @return 対応するコード。見つからない場合は-1。
     */
    int getCode(string fromSymbolName) {
        string symbolName = StringSubstr(fromSymbolName, 0, 6);

        SymbolNameInfo *symbolNameInfo = this.getSymbolNameInfo(symbolName);

        if (symbolNameInfo != NULL) {
            return symbolNameInfo.code;
        }

        return -1;
    }

    /**
     * シンボル名からGMO取引可否フラグを取得する。
     *
     * @param fromSymbolName シンボル名。サフィックス付きでも可。
     * @return GMO取引可能ならtrue。
     */
    bool isTarget(string fromSymbolName) {
        string symbolName = StringSubstr(fromSymbolName, 0, 6);

        SymbolNameInfo *symbolNameInfo = this.getSymbolNameInfo(symbolName);

        if (symbolNameInfo != NULL) {
            return symbolNameInfo.isTarget;
        }

        return false;
    }

    /**
     * シンボル名から SymbolNameInfo を取得する。
     *
     * @param fromSymbolName シンボル名。例: "USDJPY"。
     * @return SymbolNameInfoへのポインタ。存在しない場合はNULL。
     */
    SymbolNameInfo *getSymbolNameInfo(string fromSymbolName) {
        int total = this.symbolNameInfoList.Total();

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *symbolNameInfo = this.symbolNameInfoList.At(i);

            if (symbolNameInfo == NULL) {
                continue;
            }

            if (symbolNameInfo.symbolName == fromSymbolName) {
                return symbolNameInfo;
            }
        }

        return NULL;
    }

    /**
     * コードからシンボル名を取得する。
     *
     * @param fromCode コード。
     * @return 対応するシンボル名。見つからない場合は空文字。
     */
    string getSymbol(int fromCode) {
        int total = this.symbolNameInfoList.Total();

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *symbolNameInfo = this.symbolNameInfoList.At(i);

            if (symbolNameInfo == NULL) {
                continue;
            }

            if (symbolNameInfo.code == fromCode) {
                return symbolNameInfo.symbolName;
            }
        }

        return NULL;
    }

private:
    /** シンボル情報リスト。 */
    CArrayObj symbolNameInfoList;
    /** 通貨定数。 */
    ConstantCurrency constantCurrency;
    /** ロガー。 */
    Logger logger;
    
    /**
     * シンボル情報を追加する。
     *
     * @param fromSymbolName シンボル名。例: "USDJPY"。
     * @param fromCode コード。
     * @param fromIsGmo GMO取引可能ならtrue。
     */
    void add(string fromSymbolName, int fromCode, bool fromIsGmo) {
        SymbolNameInfo *symbolNameInfo = new SymbolNameInfo(fromSymbolName, fromCode, fromIsGmo);

        this.symbolNameInfoList.Add(symbolNameInfo);
    }
};

#endif // __SYMBOL_NAME_INFO_ALL_MQH__
