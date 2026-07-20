//+------------------------------------------------------------------+
//|                                                    ElliotAll.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef ELLIOT_ALL_MQH
#define ELLIOT_ALL_MQH

#include <Mstng\Analysis\MarketActivityAnalyzer.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\TimeFrameInfoAll.mqh>
#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\Elliot\HigherStochasticMainOrderDecision.mqh>
#include <Mstng\Elliot\LossCut.mqh>
#include <Mstng\Elliot\TradeTimeInfo.mqh>
#include <Mstng\Elliot\TrendAlignDecision.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Util\TodayRate.mqh>
#include <Mstng\Util\UtilAll.mqh>

/**
 * ElliotAll クラスは、複数時間足のElliott波動分析を統合して管理する。
 * 時間足別Elliot生成、Oscillator共有、ロスカット候補、CSV/表示用文字列の
 * 生成、補助判定までを1か所で扱う。
 */
class ElliotAll : public CObject {
public:
    /** タイマーから分析を実行する場合true。テスターではfalse。 */
    bool isTimer;

    /** 分析対象の市場コンテキスト。 */
    MarketContext marketContext;

    /** 実行時に取得した通貨強弱情報。 */
    CurrencyStrengthExecutionInfo currencyStrengthExecutionInfo;

    /** 通貨強弱をエントリー条件として使用する場合true。 */
    bool isCurrencyStrengthEntryFilterEnabled;
    
    /** 通貨ペア名を分割した左側の通貨コード。 */
    string symbolNameLeft;

    /** 通貨ペア名を分割した右側の通貨コード。 */
    string symbolNameRight;
    
    /** サーバー時刻、JST、取引セッション情報。 */
    TradeTimeInfo tradeTimeInfo;
    
    /** 直近の分析処理時間。単位: ミリ秒。 */
    uint execTime;

    /** インジケーター側で設定されたタイマー間隔。単位: 秒。 */
    int timerSeconds;
    
    /** 当日高値・安値、Bid、Ask、スプレッド情報。 */
    TodayRate todayRate;

    /** 現在時間足のElliottポイントから算出したロスカット候補。 */
    LossCut lossCut;
    
    /**
     * 時間足別Elliot一覧。
     *
     * 各要素の所有権は本クラスが持ち、デストラクタで解放する。
     */
    CArrayObj elliotList;

    /** 対象時間足すべてのElliott分析が成功した場合true。 */
    bool isAnalysisSucceeded;
    
    /** 現在時間足に対応するElliot。elliotList内要素への非所有参照。 */
    Elliot *elliotCurrent;
    
    /** 分析結果メールを送信する場合true。 */
    bool isSendMail;

    /** 分析結果メールの件名。 */
    string mailTitile;
    
    //MarketActivityAnalyzer marketActivityAnalyzer;
    
    /** 上位足ストキャスMain0並び順多数決判定。 */
    HigherStochasticMainOrderDecision higherStochasticMainOrderDecision;
    
    /** 上位足トレンド一致判定。 */
    TrendAlignDecision trendAlignDecision;
    
    /**
     * デフォルトコンストラクタ。
     */
    ElliotAll() {
        this.initializeMembers();
    }
    
    /**
     * 分析対象を指定して初期化する。
     *
     * @param fromSymbolName 分析対象シンボル
     * @param fromTimeFrame 呼び出し元となる現在時間足
     */
    ElliotAll(string fromSymbolName, ENUM_TIMEFRAMES fromTimeFrame) {
        this.initializeMembers();
        MarketContext context(fromSymbolName, fromTimeFrame);
        this.setMarketContext(context);
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * 渡されたMarketContextは値としてコピーして保持する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    ElliotAll(MarketContext &fromMarketContext) {
        this.initializeMembers();
        this.setMarketContext(fromMarketContext);
    }

    /**
     * デストラクタ。
     */
    ~ElliotAll() {
        delete this.timeFrameInfoAll;
        
        for (int i = 0; i < this.elliotList.Total(); i++) {
            Elliot *elliot = this.elliotList.At(i);
            
            delete elliot;
        }
    }

    /**
     * 分析対象の市場コンテキストを設定する。
     *
     * 既存の時間足別分析結果と時間足構成を破棄し、新しい市場向けに
     * 再初期化する。ハンドルプールは市場依存のため再設定が必要となる。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void setMarketContext(MarketContext &fromMarketContext) {
        this.elliotList.Clear();
        this.elliotCurrent = NULL;
        this.isAnalysisSucceeded = false;
        this.execTime = 0;
        this.oscillatorHandlePool = NULL;
        this.currencyStrengthExecutionInfo.reset();
        this.isCurrencyStrengthEntryFilterEnabled = false;

        if (this.timeFrameInfoAll != NULL) {
            delete this.timeFrameInfoAll;
            this.timeFrameInfoAll = NULL;
        }

        this.initializeMarketContext(fromMarketContext);
        this.timeFrameInfoAll = new TimeFrameInfoAll();
    }
    
    /**
     * 対象となる全時間足のElliott分析と付随情報の更新を実行する。
     *
     * 取引時間、当日レート、時間足別Elliott、トレンド一致、上位足
     * ストキャス多数決、ロスカット候補を順に設定し、処理時間を記録する。
     */
    void analyze() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        uint startCount = GetTickCount();
        
        this.tradeTimeInfo.setData(TimeCurrent());
        
        this.todayRate.update(this.marketContext);
        
        this.setTimeFrame(this.marketContext.timeFrame);
        
        this.setElliotAll();
        
        this.setTrendAlignDecision();
        
        this.setHigherStochasticMainOrderDecision();
        
        if (this.elliotCurrent != NULL) {
            this.lossCut.setData(this.elliotCurrent, this.todayRate);
        }
        
        
        this.logger.debug(__FUNCTION__, this.getCsv());
        
        this.execTime = GetTickCount() - startCount;
        
        this.logger.debug(__FUNCTION__, StringFormat("<elapsed=%d ms>", this.execTime));
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 全時間足の分析結果をCSV文字列として取得する。
     *
     * @param isDetail trueの場合、レート、複合判定、時間足別詳細を含める
     * @return 共通情報と各時間足情報を連結したCSV文字列
     */
    string getCsv(bool isDetail = false) {
        string csv = "";
        
        csv = StringFormat("%s,%s,", this.marketContext.symbolName, this.tradeTimeInfo.getCsvData());
        
        if (isDetail) {
            csv += StringFormat("%s,%s,%s,", this.todayRate.bidLabel, this.todayRate.askLabel, this.todayRate.spreadLabel);
            csv += StringFormat("%s,%s,%s,", this.todayRate.highLabel, this.todayRate.lowLabel, this.todayRate.diffLabel);
            
            csv += StringFormat("%s,", this.trendAlignDecision.getCsvData());
            csv += StringFormat("%s,", this.higherStochasticMainOrderDecision.getCsvData());
        }
        
        for (int i = this.elliotList.Total() - 1; i >= 0; i--) {
            Elliot *elliot = this.elliotList.At(i);
            
            csv += elliot.getCsv(isDetail);
        }
        
        return csv;
    }
    
    /**
     * 指定時間足のElliotを取得する。
     *
     * @param fromTimeFrame 取得対象時間足
     * @return elliotList内要素への非所有参照。存在しない場合NULL
     */
    Elliot *getElliot(ENUM_TIMEFRAMES fromTimeFrame) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        this.logger.debug(__FUNCTION__, StringFormat("fromTimeFrame = %s", TimeUtil::convertTimeFrameToString(fromTimeFrame)));
        
        for (int i = 0; i < this.elliotList.Total(); i++) {
            Elliot *elliot = this.elliotList.At(i);
            
            if (elliot.marketContext.timeFrame == fromTimeFrame) {
                LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                
                return elliot;
            }
        }
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
        
        return NULL;
    }
    
    /**
     * 指定時間足から相対位置で上位足のElliotを取得する。
     *
     * @param fromTimeFrame 基準時間足
     * @param upper 上位方向へ移動する時間足数
     * @return elliotList内要素への非所有参照。存在しない場合NULL
     */
    Elliot *getElliot(ENUM_TIMEFRAMES fromTimeFrame, int upper) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        this.logger.debug(__FUNCTION__, StringFormat("fromTimeFrame = %s, upper = %d", TimeUtil::convertTimeFrameToString(fromTimeFrame), upper));
        
        int index = this.timeFrameInfoAll.getIndex(fromTimeFrame);
        ENUM_TIMEFRAMES timeFrameTo = this.timeFrameInfoAll.getTimeFrame(index + upper);
        
        this.logger.debug(__FUNCTION__, StringFormat("timeFrameTo = %s", TimeUtil::convertTimeFrameToString(timeFrameTo)));
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return this.getElliot(timeFrameTo);
    }
    
    /**
     * 全時間足の分析結果を表示用テキストとして取得する。
     *
     * @return 各Elliotの表示文字列を改行で連結したテキスト
     */
    string getText() {
        string text = "";
                
        for (int i = this.elliotList.Total() - 1; i >= 0; i--) {
            Elliot *elliot = this.elliotList.At(i);
            
            text += StringFormat("%s\n", elliot.getText());
            
        }
        
        return text;
        
    }
    
    /**
     * 現在時間足から指定上位足まで売買方向が一致するか判定する。
     *
     * @param fromTimeFrame 判定対象となる最上位時間足
     * @return 全対象時間足の売買方向が一致する場合true
     */
    bool isBuySell(ENUM_TIMEFRAMES fromTimeFrame) {
        if (this.elliotCurrent == NULL) {
            return false;
        }
        
        for (int i = this.elliotList.Total() - 1; i >= 0; i--) {
            Elliot *elliot = this.elliotList.At(i);
            
            if (elliot != NULL) {
                if (this.elliotCurrent.marketContext.timeFrame < elliot.marketContext.timeFrame 
                        && elliot.marketContext.timeFrame <= fromTimeFrame) {
                    if (this.elliotCurrent.isBuy != elliot.isBuy) {
                        return false;
                    }
                }
            }
            
        }
        
        return true;
    }
    
    /**
     * 現在時間足から指定上位足までOscillator値が±3で一致するか判定する。
     *
     * @param fromTimeFrame 判定対象となる最上位時間足
     * @param isBuy trueの場合+3、falseの場合-3を期待する
     * @return 全対象時間足が期待値と一致する場合true
     */
    bool isBuySellCount3(ENUM_TIMEFRAMES fromTimeFrame, bool isBuy) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        this.logger.debug(__FUNCTION__, StringFormat("fromTimeFrame = %s", TimeUtil::convertTimeFrameToString(fromTimeFrame)));
        this.logger.debug(__FUNCTION__, StringFormat("isBuy = %s", (string)isBuy));
        
        if (this.elliotCurrent == NULL) {
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return false;
        }
        
        int count = 3;
        
        if (!isBuy) {
            count = -3;
        }
        
        for (int i = this.elliotList.Total() - 1; i >= 0; i--) {
            Elliot *elliot = this.elliotList.At(i);
            
            if (elliot != NULL) {
                this.logger.debug(__FUNCTION__, StringFormat("elliot.timeFrameLabel = %s", elliot.marketContext.timeFrameLabel));
                
                if (this.elliotCurrent.marketContext.timeFrame <= elliot.marketContext.timeFrame 
                        && elliot.marketContext.timeFrame <= fromTimeFrame) {
                    
                    this.logger.debug(__FUNCTION__, StringFormat("elliot.oscillator.oscillatorCount = %d", elliot.oscillator.oscillatorCount));
                    
                    if (count != elliot.oscillator.oscillatorCount) {
                        this.logger.debug(__FUNCTION__, "return false");
                        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
                        
                        return false;
                    }
                }
            }
        }
        
        this.logger.debug(__FUNCTION__, "return true");
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return true;
    }
    
    /**
     * 全時間足分析で共有するOscillatorハンドルプールを設定する。
     *
     * @param fromOscillatorHandlePool 呼び出し元が所有するハンドルプール
     */
    void setOscillatorHandlePool(OscillatorHandlePool *fromOscillatorHandlePool) {
        this.oscillatorHandlePool = fromOscillatorHandlePool;
    }

    /**
     * 実行時の通貨強弱情報を設定する。
     *
     * @param fromCurrencyStrengthExecutionInfo DB取得済みの通貨強弱情報
     */
    void setCurrencyStrengthExecutionInfo(
        CurrencyStrengthExecutionInfo &fromCurrencyStrengthExecutionInfo
    ) {
        this.currencyStrengthExecutionInfo = fromCurrencyStrengthExecutionInfo;
    }
    
    
private:
    /** 処理経過およびエラー出力用ロガー。 */
    Logger logger;
    
    /**
     * 時間足別Oscillatorハンドルプールへの非所有参照。
     *
     * ライフサイクルは呼び出し元が管理する。
     */
    OscillatorHandlePool *oscillatorHandlePool;
    
    /** Elliott分析を開始する最上位時間足。 */
    ENUM_TIMEFRAMES startTimeFrame;

    /**
     * 時間足構成および分析対象フラグの管理クラス。
     *
     * 本クラスが所有し、デストラクタで解放する。
     */
    TimeFrameInfoAll *timeFrameInfoAll;

    /**
     * コンストラクタ共通の初期値を設定する。
     */
    void initializeMembers() {
        this.execTime = 0;
        this.timerSeconds = 0;
        this.isTimer = false;
        this.isAnalysisSucceeded = false;
        this.isSendMail = false;
        this.elliotCurrent = NULL;
        this.oscillatorHandlePool = NULL;
        this.timeFrameInfoAll = NULL;
        this.currencyStrengthExecutionInfo.reset();
        this.isCurrencyStrengthEntryFilterEnabled = false;
    }

    /**
     * 市場コンテキストと互換用フィールドを初期化する。
     *
     * @param fromMarketContext 分析対象の市場コンテキスト
     */
    void initializeMarketContext(MarketContext &fromMarketContext) {
        this.marketContext = fromMarketContext;

        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.todayRate.setMarketContext(this.marketContext);
        this.lossCut.setMarketContext(this.marketContext);

        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        // 既存利用箇所との互換性を維持する
        StringUtil::splitCurrencyPairName(this.marketContext.symbolName, this.symbolNameLeft, this.symbolNameRight);

        this.logger.debug(__FUNCTION__, "symbolName=" + this.marketContext.symbolName);
        this.logger.debug(__FUNCTION__, "symbolNameLeft=" + this.symbolNameLeft);
        this.logger.debug(__FUNCTION__, "symbolNameRight=" + this.symbolNameRight);
        this.logger.debug(__FUNCTION__, "timeFrame=" + IntegerToString(this.marketContext.timeFrame));
        this.logger.debug(__FUNCTION__, "timeFrameLabel=" + this.marketContext.timeFrameLabel);

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 上位足トレンド一致判定を設定する。
     */
    void setTrendAlignDecision() {
        this.trendAlignDecision.setData(
            this.getElliot(PERIOD_D1),
            this.getElliot(PERIOD_H4),
            this.getElliot(PERIOD_H1),
            this.getElliot(PERIOD_M15)
        );
    }
    
    /**
     * 上位足ストキャスMain0並び順多数決判定を設定する。
     */
    void setHigherStochasticMainOrderDecision() {
        this.higherStochasticMainOrderDecision.setData(
            this.getElliot(PERIOD_D1),
            this.getElliot(PERIOD_H4),
            this.getElliot(PERIOD_H1)
        );
    }
    
    /**
     * 分析対象時間足ごとのElliotを上位足から順に生成する。
     *
     * 全対象時間足を生成できた場合にisAnalysisSucceededをtrueへ設定し、
     * 現在時間足に対応するelliotCurrentを保持する。
     */
    void setElliotAll() {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        CArrayObj *timeFrameInfoList = &(timeFrameInfoAll.timeFrameInfoList);
        
        int total = timeFrameInfoList.Total();
        
        this.logger.debug(__FUNCTION__, StringFormat("total = %d", total));
        
        int countTarget = 0;
        int countElliot = 0;
        
        for (int i = total - 1; i >= 0; i--) {
            this.logger.debug(__FUNCTION__, StringFormat("i = %d", i));
            
            TimeFrameInfo *timeFrameInfo = timeFrameInfoList.At(i);
            
            this.logger.debug(__FUNCTION__, StringFormat("timeFrameInfo = %s", timeFrameInfo.toString()));
            
            if (timeFrameInfo.isElliotTarget) {
                countTarget++;
                
                Elliot *elliot = this.setElliot(timeFrameInfo.timeFrame);
                
                if (elliot == NULL) {
                    break;
                }
                
                this.elliotList.Insert(elliot, 0);
                countElliot++;
            }
        }
        
        if (countTarget == countElliot) {
            this.isAnalysisSucceeded = true;
        }
        
        this.elliotCurrent = this.getElliot(this.marketContext.timeFrame);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
    
    /**
     * 指定時間足のElliotを生成し、直上位足と連携して分析する。
     *
     * @param fromTimeFrame 分析対象時間足
     * @return 生成したElliot。分析失敗時NULL。成功時の所有権は呼び出し側へ移る
     */
    Elliot *setElliot(ENUM_TIMEFRAMES fromTimeFrame) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        this.logger.debug(__FUNCTION__, StringFormat("fromTimeFrame = %s", TimeUtil::convertTimeFrameToString(fromTimeFrame)));
        
        MarketContext elliotMarketContext = this.marketContext;
        elliotMarketContext.setTimeFrame(fromTimeFrame);
        Elliot *elliot = new Elliot(elliotMarketContext);
        
        Elliot *elliotUppaer = NULL;
        
        if (fromTimeFrame != PERIOD_MN1) {
            elliotUppaer = this.getElliot(fromTimeFrame, 1);
        }
        
        
        if (!elliot.analyze(elliotUppaer, oscillatorHandlePool)) {
            this.logger.error(__FUNCTION__, StringFormat("elliot.analyze false timeFrame = %s", TimeUtil::convertTimeFrameToString(fromTimeFrame)));

            delete elliot;
            
            LogUtil::printMethodEnd(this.logger, __FUNCTION__, false);
            
            return NULL;
        }
        
        elliot.setParentElliot(elliot);
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
        
        return elliot;
    }
    
    /**
     * 実行環境に応じてElliott分析対象の時間足範囲を設定する。
     *
     * タイマー実行時はMN1、その他通常時はD1を開始時間足とし、現在時間足までを
     * TimeFrameInfoAllの分析対象に設定する。
     *
     * @param fromTimeFrame 呼び出し元時間足。現在は保持済みtimeFrameを終了足に使用する
     */
    void setTimeFrame(ENUM_TIMEFRAMES fromTimeFrame) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);
        
        if (this.isTimer) {
            this.startTimeFrame = PERIOD_MN1;
        } else {
            this.startTimeFrame = PERIOD_D1;
        }
        
        this.timeFrameInfoAll.setElliotTarget(
            this.startTimeFrame,
            this.marketContext.timeFrame
        );
        
        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }
};

#endif // ELLIOT_ALL_MQH














