//+------------------------------------------------------------------+
//|                                                  ZigZagLogic.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.17" // バージョンを更新

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Log\LogUtil.mqh>

/**
 * ZigZagの山・谷を確定する際の探索状態を定義する。
 */
enum EnSearchMode {
    Extremum = 0, // 最初の極値を検索中
    Peak = 1,     // 次の山（Peak）を検索中
    Bottom = -1   // 次の谷（Bottom）を検索中
};

/**
 * 高値・安値データからZigZagの山と谷を算出する。
 *
 * 極値候補の抽出と交互性の判定を行い、価格および探索結果を公開バッファへ格納する。
 */
class ZigZagLogic {
public:
    /** 計算対象の市場コンテキスト */
    MarketContext marketContext;

    /** ZigZagの山・谷の価格を格納する計算結果バッファ */
    double zigZagBuffer[];

    /** 各バーで確定した山・谷の探索モードを格納するバッファ */
    int searchModeBuffer[];
    
    /**
     * シンボル、時間足およびZigZagパラメータを指定して初期化する。
     *
     * @param fromSymbol シンボル名
     * @param fromPeriod 時間足
     * @param fromDepth 探索深さ
     * @param fromDeviation 偏差
     * @param fromBackstep バックステップ
     */
    ZigZagLogic(string fromSymbol, ENUM_TIMEFRAMES fromPeriod, int fromDepth, int fromDeviation, int fromBackstep) {
        MarketContext context(fromSymbol, fromPeriod);
        this.initialize(context, fromDepth, fromDeviation, fromBackstep);
    }

    /**
     * 市場コンテキストとZigZagパラメータを指定して初期化する。
     *
     * @param fromMarketContext 計算対象の市場コンテキスト
     * @param fromDepth 探索深さ
     * @param fromDeviation 偏差
     * @param fromBackstep バックステップ
     */
    ZigZagLogic(
        MarketContext &fromMarketContext,
        int fromDepth,
        int fromDeviation,
        int fromBackstep
    ) {
        this.initialize(fromMarketContext, fromDepth, fromDeviation, fromBackstep);
    }

    /**
     * デストラクタ。
     */
    ~ZigZagLogic() {
    }

    /**
     * 計算対象の市場コンテキストを設定する。
     *
     * 旧市場の計算バッファを破棄し、point値とLoggerを更新する。
     *
     * @param fromMarketContext 計算対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        ArrayResize(this.zigZagBuffer, 0);
        ArrayResize(this.searchModeBuffer, 0);
        ArrayResize(this.highMapBuffer, 0);
        ArrayResize(this.lowMapBuffer, 0);

        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
        this.pointSize = this.marketContext.getPoint();

        if (this.pointSize <= 0.0) {
            Print("Error: Failed to get SYMBOL_POINT for ", this.marketContext.symbolName);
            this.pointSize = 0.00001;
        }
    }

    /**
     * 対象市場の高値・安値からZigZagを計算する。
     *
     * @param fromRatesTotal 取得および計算の対象とするバー数
     * @return 実際に計算したバー数。価格データを取得できない場合は0
     */
    int calculate(int fromRatesTotal) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int ratesTotal = fromRatesTotal;
        
        ArrayResize(this.zigZagBuffer, ratesTotal);
        ArrayResize(this.searchModeBuffer, ratesTotal);
        
        
        // データの取得
        double high[];
        double low[];
        
        int copiedHigh = CopyHigh(this.marketContext.symbolName, this.marketContext.timeFrame, 0, ratesTotal, high);
        int copiedLow  = CopyLow(this.marketContext.symbolName, this.marketContext.timeFrame, 0, ratesTotal, low);

        if (copiedHigh <= 0 || copiedLow <= 0) {
            // データ取得失敗時はエラーメッセージを出す
            this.logger.error(__FUNCTION__, "Failed to copy high/low data.");
            
            return 0;
        }
        
        // 実際にコピーできたバー数に調整
        ratesTotal = MathMin(copiedHigh, copiedLow);
        
        this.logger.debug(__FUNCTION__, StringFormat("ratesTotal = %d", ratesTotal));
        
        // バッファのリサイズ
        if (ArraySize(this.highMapBuffer) != ratesTotal) {
            ArrayResize(this.highMapBuffer, ratesTotal);
            ArrayResize(this.lowMapBuffer, ratesTotal);
        }

        int start = 0;
        int extremeSearch = Extremum;
        int lastHighPos = 0;
        int lastLowPos = 0;
        double val = 0;
        double res = 0;
        double lastHigh = 0;
        double lastLow = 0;

        // 初期化処理
        ArrayInitialize(this.zigZagBuffer, 0.0);
        ArrayInitialize(this.searchModeBuffer, 0);
        
        ArrayInitialize(this.highMapBuffer, 0.0);
        ArrayInitialize(this.lowMapBuffer, 0.0);
        start = this.depth;
        
        // 高値と安値の候補（Map）を検索
        for (int shift = start; shift < ratesTotal; shift++) {
            // 安値の検索
            val = low[this.getLowestIndex(low, this.depth, shift)];
            
            if (val == lastLow) {
                val = 0.0;
            } else {
                lastLow = val;
                
                if ((low[shift] - val) > this.deviation * this.pointSize) {
                    val = 0.0;
                } else {
                    for (int j = 1; j <= this.backstep; j++) {
                        res = this.lowMapBuffer[shift - j];
                        
                        if ((res != 0) && (res > val)) {
                            this.lowMapBuffer[shift - j] = 0.0;
                        }
                    }
                }
            }
            
            if (low[shift] == val) {
                this.lowMapBuffer[shift] = val;
            } else {
                this.lowMapBuffer[shift] = 0.0;
            }

            // 高値の検索
            val = high[this.getHighestIndex(high, this.depth, shift)];
            
            if (val == lastHigh) {
                val = 0.0;
            } else {
                lastHigh = val;
                
                if ((val - high[shift]) > this.deviation * this.pointSize) {
                    val = 0.0;
                } else {
                    for (int j = 1; j <= this.backstep; j++) {
                        res = this.highMapBuffer[shift - j];
                        
                        if ((res != 0) && (res < val)) {
                            this.highMapBuffer[shift - j] = 0.0;
                        }
                    }
                }
            }
            
            if (high[shift] == val) {
                this.highMapBuffer[shift] = val;
            } else {
                this.highMapBuffer[shift] = 0.0;
            }
        }

        // 最終的な極値の決定ロジック
        if (extremeSearch == 0) {
            lastLow = 0.0;
            lastHigh = 0.0;
        }

        for (int shift = start; shift < ratesTotal; shift++) {
            res = 0.0;
            
            switch (extremeSearch) {
                case Extremum:
                    if (lastLow == 0.0 && lastHigh == 0.0) {
                        if (this.highMapBuffer[shift] != 0) {
                            lastHigh = high[shift];
                            lastHighPos = shift;
                            extremeSearch = Bottom;
                            this.zigZagBuffer[shift] = lastHigh;
                            res = 1;
                            
                            this.searchModeBuffer[shift] = Peak;
                        }
                        
                        if (this.lowMapBuffer[shift] != 0.0) {
                            lastLow = low[shift];
                            lastLowPos = shift;
                            extremeSearch = Peak;
                            this.zigZagBuffer[shift] = lastLow;
                            res = 1;
                            
                            this.searchModeBuffer[shift] = Bottom;
                        }
                    }
                    break;
                    
                case Peak:
                    if (this.lowMapBuffer[shift] != 0.0 && this.lowMapBuffer[shift] < lastLow && this.highMapBuffer[shift] == 0.0) {
                        this.zigZagBuffer[lastLowPos] = 0.0;
                        lastLowPos = shift;
                        lastLow = this.lowMapBuffer[shift];
                        this.zigZagBuffer[shift] = lastLow;
                        res = 1;
                        
                        this.searchModeBuffer[shift] = Bottom;
                    }
                    
                    if (this.highMapBuffer[shift] != 0.0 && this.lowMapBuffer[shift] == 0.0) {
                        lastHigh = this.highMapBuffer[shift];
                        lastHighPos = shift;
                        this.zigZagBuffer[shift] = lastHigh;
                        extremeSearch = Bottom;
                        res = 1;
                        
                        this.searchModeBuffer[shift] = Peak;
                    }
                    break;
                    
                case Bottom:
                    if (this.highMapBuffer[shift] != 0.0 && this.highMapBuffer[shift] > lastHigh && this.lowMapBuffer[shift] == 0.0) {
                        this.zigZagBuffer[lastHighPos] = 0.0;
                        lastHighPos = shift;
                        lastHigh = this.highMapBuffer[shift];
                        this.zigZagBuffer[shift] = lastHigh;
                        
                        this.searchModeBuffer[shift] = Peak;
                    }
                    
                    if (this.lowMapBuffer[shift] != 0.0 && this.highMapBuffer[shift] == 0.0) {
                        lastLow = this.lowMapBuffer[shift];
                        lastLowPos = shift;
                        this.zigZagBuffer[shift] = lastLow;
                        extremeSearch = Peak;
                        
                        this.searchModeBuffer[shift] = Bottom;
                    }
                    break;
            }
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);

        return ratesTotal;
    }

private:
    /** 処理経過およびエラー出力用ロガー */
    Logger logger;
    
    /** 極値探索に使用する対象バー数 */
    int depth;

    /** 極値候補を除外する最小価格差 */
    int deviation;

    /** 過去の極値候補を無効化する確認バー数 */
    int backstep;

    /** 対象シンボルの1ポイントの価格 */
    double pointSize;

    /** 高値候補を格納する内部計算バッファ */
    double highMapBuffer[];

    /** 安値候補を格納する内部計算バッファ */
    double lowMapBuffer[];

    /**
     * 市場コンテキスト、互換用フィールドおよびZigZagパラメータを初期化する。
     *
     * @param fromMarketContext 計算対象の市場コンテキスト
     * @param fromDepth 探索深さ
     * @param fromDeviation 偏差
     * @param fromBackstep バックステップ
     */
    void initialize(
        MarketContext &fromMarketContext,
        int fromDepth,
        int fromDeviation,
        int fromBackstep
    ) {
        this.logger.setLevel(LOG_INFO);

        // 既存利用箇所との互換性を維持する
        this.depth = fromDepth;
        this.deviation = fromDeviation;
        this.backstep = fromBackstep;
        this.setMarketContext(fromMarketContext);
    }
    
    /**
     * 指定範囲内の最高値のインデックスを検索する。
     *
     * @param array 検索対象配列
     * @param fromDepth 検索深さ
     * @param start 検索開始位置
     * @return 最高値のインデックス
     */
    int getHighestIndex(const double &array[], int fromDepth, int start) {
        if (start < 0) {
            return 0;
        }
        
        double max = array[start];
        int index = start;

        for (int i = start - 1; i > start - fromDepth && i >= 0; i--) {
            if (array[i] > max) {
                index = i;
                max = array[i];
            }
        }

        return index;
    }

    /**
     * 指定範囲内の最安値のインデックスを検索する。
     *
     * @param array 検索対象配列
     * @param fromDepth 検索深さ
     * @param start 検索開始位置
     * @return 最安値のインデックス
     */
    int getLowestIndex(const double &array[], int fromDepth, int start) {
        if (start < 0) {
            return 0;
        }
        
        double min = array[start];
        int index = start;

        for (int i = start - 1; i > start - fromDepth && i >= 0; i--) {
            if (array[i] < min) {
                index = i;
                min = array[i];
            }
        }

        return index;
    }

};



