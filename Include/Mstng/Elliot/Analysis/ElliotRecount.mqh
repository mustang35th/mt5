//+------------------------------------------------------------------+
//|                                                ElliotRecount.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Wave.mqh>
#include <Mstng\Elliot\WaveUtil.mqh>

/**
 * Elliott波動の再カウントを担当するクラス。
 *
 * Wave内のフィボナッチエクスパンションを確認し、浅い奇数波を
 * 再カウント対象として削除フラグに置き換える。
 * 最終的に削除対象を除外したポイント列をWaveへ反映する。
 */
class ElliotRecount {
public:
    /** 再カウント対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** 再カウント対象Wave一覧。インデックス0が最新。 */
    CArrayObj waveList;

    /**
     * シンボル、時間足およびWave一覧を指定して初期化する。
     *
     * @param fromSymbolName 再カウント対象シンボル
     * @param fromTimeFrame 再カウント対象時間足
     * @param fromWaveList 再カウント対象Wave一覧
     */
    ElliotRecount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, CArrayObj &fromWaveList) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromWaveList);
    }

    /**
     * 市場コンテキストおよびWave一覧を指定して初期化する。
     *
     * @param fromMarketContext 再カウント対象の市場コンテキスト
     * @param fromWaveList 再カウント対象Wave一覧
     */
    ElliotRecount(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.initialize(fromMarketContext, fromWaveList);
    }
    
    /**
     * デストラクタ。
     */
    ~ElliotRecount() {
    }

    /**
     * 再カウント対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 再カウント対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * 保持している全Waveを対象に再カウントを実行する。
     *
     * 元のElliott情報を退避した後、削除対象ポイントを判定し、
     * DELETEフラグのポイントを除外した結果をWaveへ反映する。
     */
    void recount() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int total = this.waveList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("waveList.total = %d", total));
        
        
        for (int i = 0; i < total; i++) {
            this.logger.debug(__FUNCTION__, StringFormat("waveList i = %d", i));
            
            Wave *wave = this.waveList.At(i);
            
            ZigZagPointUtil::setOrgField(wave.zigZagPointList); // 元情報に設定
            this.recount(wave);            
            
            ZigZagPointUtil::copyZigZagPointList(wave.zigZagPointList, wave.orgZigZagPointList);
            this.deleteZigZagPoint(wave);
            
        }
                
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /** 浅い推進波と判定する最小フィボナッチエクスパンション率。 */
    static const double minMotiveFibonacciExpansionPercent;

    /** 深い修正波と判定する最大フィボナッチリトレースメント率。 */
    static const double maxCorrectionFibonacciPercent;

    /**
     * 市場コンテキストおよびWave一覧を初期化する。
     *
     * @param fromMarketContext 再カウント対象の市場コンテキスト
     * @param fromWaveList 再カウント対象Wave一覧
     */
    void initialize(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.logger.setLevel(LOG_INFO);
        this.initializeMarketContext(fromMarketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        WaveUtil::copyWaveList(fromWaveList, this.waveList);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 市場コンテキストとロガーを初期化する。
     *
     * @param fromMarketContext 再カウント対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
    }
    
    /**
     * DELETEフラグが付いたポイントをWaveから除外する。
     *
     * @param wave 処理対象Wave
     */
    void deleteZigZagPoint(Wave *wave) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int total = wave.zigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("wave.zigZagPointList.total = %d", total));
        
        CArrayObj zigZagPointList;
        
        for (int i = 0; i < total; i++) {
            ZigZagPoint *zigZagPoint = wave.zigZagPointList.At(i);
            
            if (zigZagPoint.elliotIndex != Constant::DELETE_FLG) {
                ZigZagPoint *zigZagPointNew = zigZagPoint.clone();
                
                zigZagPointList.Add(zigZagPointNew);
                
                this.logger.debug(__FUNCTION__, StringFormat("zigZagPointNew = %s", zigZagPointNew.toString()));
            }
        }
        
        ZigZagPointUtil::copyZigZagPointList(zigZagPointList, wave.zigZagPointList);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定Waveの再カウント対象ポイントへDELETEフラグを設定する。
     *
     * 浅い推進波と深い修正波を削除対象とし、隣接ポイントも
     * 必要に応じて同じ削除対象へ含める。
     *
     * @param wave 処理対象Wave
     */
    void recount(Wave *wave) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
    
        if (wave == NULL) {
            this.logger.debug(__FUNCTION__, "wave is NULL");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            return;
        }
    
        this.logger.debug(
            __FUNCTION__,
            StringFormat("wave.isMotive = %s", wave.isMotive ? "true" : "false")
        );
    
        if (!wave.isMotive) {
            this.logger.debug(__FUNCTION__, "修正波なので対象外");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
            return;
        }
    
        int total = wave.zigZagPointList.Total();
    
        this.logger.debug(__FUNCTION__, StringFormat("wave.zigZagPointList.Total = %d", total));
    
        if (total < 4) {
            this.logger.debug(__FUNCTION__, "3波未満なので対象外");
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
            return;
        }
    
        for (int i = 2; i < total - 1; i++) {
            this.logger.debug(__FUNCTION__, StringFormat("i = %d", i));
    
            ZigZagPoint *zigZagPoint = wave.zigZagPointList.At(i);
    
            if (zigZagPoint == NULL) {
                this.logger.debug(__FUNCTION__, StringFormat("zigZagPoint is NULL. i = %d", i));
                continue;
            }
    
            if (zigZagPoint.elliotIndex == Constant::DELETE_FLG) {
                this.logger.debug(__FUNCTION__, "削除済みなのでスキップ");
                continue;
            }
    
            if (Util::isOdd(i)) {
                // 推進波
                // i + 2が存在する場合のみ、浅い推進波を削除対象にする。
                if (zigZagPoint.fibonacciExpansionPercent < ElliotRecount::minMotiveFibonacciExpansionPercent
                        && i + 2 < total) {
                    this.logger.debug(__FUNCTION__, "FEが浅い");
    
                    zigZagPoint.elliotIndex = Constant::DELETE_FLG;
                    zigZagPoint.elliotLabel = Constant::DELETE_LABEL;
    
                    ZigZagPoint *zigZagPointNext = wave.zigZagPointList.At(i + 1);
    
                    if (zigZagPointNext != NULL) {
                        zigZagPointNext.elliotIndex = Constant::DELETE_FLG;
                        zigZagPointNext.elliotLabel = Constant::DELETE_LABEL;
                    }
                }
            } else {
                // 修正波
                if (zigZagPoint.fibonacciPercent >= ElliotRecount::maxCorrectionFibonacciPercent) {
                    this.logger.debug(__FUNCTION__, "フィボナッチが深い");
    
                    zigZagPoint.elliotIndex = Constant::DELETE_FLG;
                    zigZagPoint.elliotLabel = Constant::DELETE_LABEL;
    
                    ZigZagPoint *zigZagPointBefore = wave.zigZagPointList.At(i - 1);
    
                    if (zigZagPointBefore != NULL) {
                        zigZagPointBefore.elliotIndex = Constant::DELETE_FLG;
                        zigZagPointBefore.elliotLabel = Constant::DELETE_LABEL;
                    }
                }
            }
        }
    
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
};

const double ElliotRecount::minMotiveFibonacciExpansionPercent = 100.0;
const double ElliotRecount::maxCorrectionFibonacciPercent = 85.0;





