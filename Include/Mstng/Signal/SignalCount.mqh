//+------------------------------------------------------------------+
//|                                                  SignalCount.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Signal\SignalInfo.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * シンボル単位でシグナル発生回数を管理するクラス。
 *
 * 基準時刻と売買方向の組み合わせごとにSignalInfoを保持し、
 * 同じシグナルが検出された回数を加算する。
 */
class SignalCount : public CObject {
public:
    /** 管理対象の市場コンテキスト。 */
    MarketContext marketContext;

    /**
     * 分析対象を指定して初期化する。
     *
     * @param fromSymbolName 対象シンボル。
     * @param fromTimeFrame 対象時間足。
     */
    SignalCount(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.initializeMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 管理対象の市場コンテキスト。
     */
    SignalCount(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }
    
    /**
     * デストラクタ。
     */
    ~SignalCount() {
    }

    /**
     * 管理対象の市場コンテキストを設定する。
     *
     * 別市場のシグナル発生回数が混在しないよう、保持中の情報をクリアする。
     *
     * @param fromMarketContext 管理対象の市場コンテキスト。
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.signalInfoList.Clear();
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * 指定シグナルの検出回数を加算する。
     *
     * 同じ時刻と売買方向のSignalInfoがない場合は新規作成する。
     *
     * @param time シグナルの基準時刻。
     * @param isBuy 売買方向。true: BUY、false: SELL。
     * @return 加算後の検出回数。
     */
    int addCount(datetime time, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        int count = 0;
                
        SignalInfo *signalInfo = this.getSignalInfo(time, isBuy);
        
        if (signalInfo == NULL) {
            this.logger.debug(__FUNCTION__, "SignalCountなし　新規作成");
            
            signalInfo = new SignalInfo(time, isBuy);
            count = signalInfo.addCount();
            
            this.signalInfoList.Add(signalInfo);
            
        } else {
            this.logger.debug(__FUNCTION__, "SignalCountあり");
            
            count = signalInfo.addCount();
        }
        
        this.logger.debug(__FUNCTION__, StringFormat("count = %d", count));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return count;
    }


private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;
    
    /** 時刻・売買方向別のSignalInfo一覧。 */
    CArrayObj signalInfoList;

    /**
     * 市場コンテキストとロガーを初期化する。
     *
     * @param fromMarketContext 管理対象の市場コンテキスト。
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
    }
    
    /**
     * 指定時刻と売買方向に一致するSignalInfoを取得する。
     *
     * @param time シグナルの基準時刻。
     * @param isBuy 売買方向。true: BUY、false: SELL。
     * @return 一致するSignalInfo。一致しない場合はNULL。
     */
    SignalInfo *getSignalInfo(datetime time, bool isBuy) {
        
        for (int i = 0; i < this.signalInfoList.Total(); i++) {
            SignalInfo *signalInfo = this.signalInfoList.At(i);
            
            if (signalInfo.isEqual(time, isBuy)) {
                return signalInfo;
            }
        }
        
        return NULL;
    }
};        





