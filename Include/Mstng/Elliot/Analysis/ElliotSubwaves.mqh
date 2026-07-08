//+------------------------------------------------------------------+
//|                                               ElliotSubwaves.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\Wave.mqh>
#include <Mstng\Elliot\WaveUtil.mqh>

/**
 * Elliott波動の内部波動ラベルを設定するクラス。
 *
 * 再カウント済みポイントと元のポイント列を対応付け、
 * 削除対象として扱われた区間へRoman数字の内部波動ラベルを設定する。
 */
class ElliotSubwaves {
public:
    /** 内部波動設定対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** 内部波動設定対象Wave一覧。インデックス0が最新。 */
    CArrayObj waveList;

    /**
     * シンボル、時間足およびWave一覧を指定して初期化する。
     *
     * @param fromSymbolName 内部波動設定対象シンボル
     * @param fromTimeFrame 内部波動設定対象時間足
     * @param fromWaveList 内部波動設定対象Wave一覧
     */
    ElliotSubwaves(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame, CArrayObj &fromWaveList) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initialize(context, fromWaveList);
    }

    /**
     * 市場コンテキストおよびWave一覧を指定して初期化する。
     *
     * @param fromMarketContext 内部波動設定対象の市場コンテキスト
     * @param fromWaveList 内部波動設定対象Wave一覧
     */
    ElliotSubwaves(MarketContext &fromMarketContext, CArrayObj &fromWaveList) {
        this.initialize(fromMarketContext, fromWaveList);
    }
    
    /**
     * デストラクタ。
     */
    ~ElliotSubwaves() {
    }

    /**
     * 内部波動設定対象の市場コンテキストを設定する。
     *
     * @param fromMarketContext 内部波動設定対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * 保持している全Waveへ再カウント結果と内部波動情報を設定する。
     *
     * 再カウント済みポイント列を退避したうえで元のポイント列へ戻し、
     * 再カウント結果と内部波動ラベルを順に反映する。
     */
    void setSubwaves() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int total = this.waveList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("waveList.total = %d", total));
        
        
        for (int i = 0; i < total; i++) {
            this.logger.debug(__FUNCTION__, StringFormat("waveList i = %d", i));
            
            Wave *wave = this.waveList.At(i);
            
            ZigZagPointUtil::copyZigZagPointList(wave.zigZagPointList, wave.recountZigZagPointList);
            ZigZagPointUtil::copyZigZagPointList(wave.orgZigZagPointList, wave.zigZagPointList);
            
            // 再カウント結果を元のポイント列へ反映する。
            this.setRecount(wave);
            
            // 内部波動ラベルを設定する。
            this.setSubwaves(wave);
        }
                
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;

    /**
     * 市場コンテキストおよびWave一覧を初期化する。
     *
     * @param fromMarketContext 内部波動設定対象の市場コンテキスト
     * @param fromWaveList 内部波動設定対象Wave一覧
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
     * @param fromMarketContext 内部波動設定対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;
        this.logger.setMarketContext(this.marketContext);
    }

    /**
     * 再カウント後のElliott番号とラベルを元のWaveポイントへ反映する。
     *
     * @param wave 処理対象Wave
     */
    void setRecount(Wave *wave) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int total = wave.recountZigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("wave.recountZigZagPointList.Total = %d", total));
        
        this.logger.debug(__FUNCTION__, "wave.zigZagPointListへ設定のループ");
        
        for (int i = 1; i < total; i++) {
            this.logger.debug(__FUNCTION__, StringFormat("i = %d", i));
            
            ZigZagPoint *recountZigZagPoint = wave.recountZigZagPointList.At(i);
            
            this.logger.debug(__FUNCTION__, StringFormat("recountZigZagPoint = %s", recountZigZagPoint.toString()));
            
            ZigZagPoint *zigZagPoint = ZigZagPointUtil::getFromBarIndex(wave.zigZagPointList, recountZigZagPoint.barIndex, recountZigZagPoint.isPeak);
            
            this.logger.debug(__FUNCTION__, StringFormat("zigZagPoint = %s", zigZagPoint.toString()));
            
            zigZagPoint.elliotIndex = recountZigZagPoint.elliotIndex;
            zigZagPoint.elliotLabel = recountZigZagPoint.elliotLabel;
            
            this.logger.debug(__FUNCTION__, "");
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定Waveのポイント列を走査して内部波動ラベルを設定する。
     *
     * DELETEフラグの連続区間を内部波動として数え、
     * 通常ポイントへ戻る位置で元のElliott番号を補完する。
     *
     * @param wave 処理対象Wave
     */
    void setSubwaves(Wave *wave) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        
        int total = wave.zigZagPointList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("wave.zigZagPoint.Total = %d", total));
        
        int countNon = 0;
        
        for (int i = 1; i < total; i++) {
            this.logger.debug(__FUNCTION__, StringFormat("i = %d", i));
            this.logger.debug(__FUNCTION__, StringFormat("countNon = %d", countNon));
            
            ZigZagPoint *zigZagPoint = wave.zigZagPointList.At(i);
            
            this.logger.debug(__FUNCTION__, StringFormat("zigZagPoint.elliotIndex = %d", zigZagPoint.elliotIndex));
            
            if (zigZagPoint.elliotIndex == Constant::DELETE_FLG) {
                countNon++;
                
                zigZagPoint.subElliotIndex = countNon;
                zigZagPoint.subElliotLabel = StringUtil::toRoman(zigZagPoint.subElliotIndex);
                
            } else {
                if (countNon > 0) {
                    zigZagPoint.subElliotIndex = countNon + 1;
                    zigZagPoint.subElliotLabel = StringUtil::toRoman(zigZagPoint.subElliotIndex);
                
                    this.setSubwaves(wave, i, countNon);
                }
                
                countNon = 0;
            }
            
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定範囲内の未設定ポイントへ基準ポイントのElliott番号を補完する。
     *
     * @param wave 処理対象Wave
     * @param endIndex ラベル設定終了位置
     * @param countNon 補完対象ポイント数
     */
    void setSubwaves(Wave *wave, int endIndex, int countNon) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("endIndex = %d", endIndex));
        this.logger.debug(__FUNCTION__, StringFormat("countNon = %d", countNon));
                
        ZigZagPoint *fromZigZagPoint = wave.zigZagPointList.At(endIndex);
        
        this.logger.debug(__FUNCTION__, StringFormat("fromZigZagPoint = %s", fromZigZagPoint.toString()));
        
        for (int i = endIndex - 1; i >= endIndex - countNon; i--) {
            ZigZagPoint *zigZagPoint = wave.zigZagPointList.At(i);
            
            zigZagPoint.elliotIndex = fromZigZagPoint.elliotIndex;
            zigZagPoint.elliotLabel = fromZigZagPoint.elliotLabel;
        }
        
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};





