/**
 * Package: MstngEa.Strategy
 * File: ExpertAdvisorMtfBuySellCount3Adapter.mqh
 */

#ifndef MSTNGEA_STRATEGY_EXPERTADVISORMTFBUYSELLCOUNT3ADAPTER_MQH
#define MSTNGEA_STRATEGY_EXPERTADVISORMTFBUYSELLCOUNT3ADAPTER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\ExpertAdvisor\ElliottWaveInfo.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_BuySellCount3.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <MstngEa\Strategy\IStrategyAdapter.mqh>

/**
 * ExpertAdvisorMTF_BuySellCount3 アダプタ
 */
class ExpertAdvisorMtfBuySellCount3Adapter : public IStrategyAdapter {
public:
    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param signalCountValue シグナル回数
     */
    ExpertAdvisorMtfBuySellCount3Adapter(
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue,
        SignalCount *signalCountValue
    ) {
        MarketContext context(symbolNameValue, timeFrameValue);
        this.initialize(context, signalCountValue);
    }

    /**
     * Constructor
     *
     * @param fromMarketContext Market context
     * @param fromSignalCount Signal count
     */
    ExpertAdvisorMtfBuySellCount3Adapter(
        MarketContext &fromMarketContext,
        SignalCount *fromSignalCount
    ) {
        this.initialize(fromMarketContext, fromSignalCount);
    }

    /**
     * デストラクタ
     */
    ~ExpertAdvisorMtfBuySellCount3Adapter() {
        delete this.expertAdvisorMtfBuySellCount3;
    }

    /**
     * エントリー判定
     *
     * @param elliotAllValue 分析結果
     * @return 判定結果
     */
    SignalDecision analyzeEntry(ElliotAll *elliotAllValue) {
        SignalDecision signalDecision;

        signalDecision.isEntry = false;
        signalDecision.isBuy = true;
        signalDecision.reason = "";
        signalDecision.stopLoss = 0.0;
        signalDecision.csvText = "";
        signalDecision.alertText = "";

        this.expertAdvisorMtfBuySellCount3.analyze(elliotAllValue, this.signalCount);
        this.updateElliottInfoText();
        signalDecision.isEntry = this.expertAdvisorMtfBuySellCount3.isEntry;
        signalDecision.isBuy = this.expertAdvisorMtfBuySellCount3.isBuy;
        signalDecision.reason = this.expertAdvisorMtfBuySellCount3.name;
        signalDecision.stopLoss = this.expertAdvisorMtfBuySellCount3.stopLoss;
        signalDecision.csvText = this.expertAdvisorMtfBuySellCount3.csvText;
        signalDecision.alertText = this.expertAdvisorMtfBuySellCount3.alertText;

        return signalDecision;
    }

    /**
     * 決済判定
     *
     * @param elliotAllValue 分析結果
     * @param isBuyPositionValue true: 買いポジション
     * @return 判定結果
     */
    ExitDecision analyzeExit(ElliotAll *elliotAllValue, bool isBuyPositionValue) {
        ExitDecision exitDecision;

        exitDecision.isExit = false;
        exitDecision.reason = "";

        exitDecision.isExit = this.expertAdvisorMtfBuySellCount3.isExit(
            elliotAllValue,
            isBuyPositionValue
        );
        this.updateElliottInfoText();
        exitDecision.reason = this.expertAdvisorMtfBuySellCount3.name;

        return exitDecision;
    }

    /**
     * エリオット情報文字列取得
     *
     * @return エリオット情報文字列
     */
    string getElliottInfoText() {
        return this.elliottInfoText;
    }

    /**
     * 戦略名取得
     *
     * @return 戦略名
     */
    string getStrategyName() {
        return "MTF_BuySellCount3";
    }

private:
    /** 外部戦略 */
    ExpertAdvisorMTF_BuySellCount3 *expertAdvisorMtfBuySellCount3;

    /** シグナル回数 */
    SignalCount *signalCount;

    /** エリオット情報 */
    string elliottInfoText;

    /**
     * Initialize by market context.
     *
     * @param fromMarketContext Market context
     * @param fromSignalCount Signal count
     */
    void initialize(MarketContext &fromMarketContext, SignalCount *fromSignalCount) {
        this.expertAdvisorMtfBuySellCount3 = new ExpertAdvisorMTF_BuySellCount3(
            fromMarketContext.symbolName,
            fromMarketContext.timeFrame,
            false
        );
        this.signalCount = fromSignalCount;
        this.elliottInfoText = "-";
    }

    /**
     * エリオット情報文字列更新
     */
    void updateElliottInfoText() {
        int totalCount = this.expertAdvisorMtfBuySellCount3.elliottWaveInfoList.Total();
        string text = "";
        int i;

        if (totalCount <= 0) {
            this.elliottInfoText = "-";
            return;
        }

        for (i = totalCount - 1; i >= 0; i--) {
            ElliottWaveInfo *elliottWaveInfo =
                (ElliottWaveInfo *)this.expertAdvisorMtfBuySellCount3.elliottWaveInfoList.At(i);

            if (elliottWaveInfo == NULL) {
                continue;
            }

            if (text != "") {
                text += "\n";
            }

            text += this.formatElliottInfo(elliottWaveInfo);
        }

        if (text == "") {
            this.elliottInfoText = "-";
            return;
        }

        this.elliottInfoText = text;
    }

    /**
     * エリオット情報整形
     *
     * @param elliottWaveInfoValue エリオット情報
     * @return 整形文字列
     */
    string formatElliottInfo(ElliottWaveInfo *elliottWaveInfoValue) {
        string text = "";

        if (elliottWaveInfoValue == NULL) {
            return "-";
        }

        text += this.rightPad(elliottWaveInfoValue.timeFrame, 3);
        text += " ";
        text += this.rightPad(elliottWaveInfoValue.buySell, 4);
        text += " ";
        text += this.rightPad(elliottWaveInfoValue.oscillator, 2);
        text += " ";
        text += this.rightPad(elliottWaveInfoValue.oscillatorS, 3);
        text += " ";
        text += this.rightPad(elliottWaveInfoValue.oscillatorM, 3);
        text += " ";
        text += this.rightPad(elliottWaveInfoValue.oscillatorL, 3);
        text += " ";
        text += this.rightPad(elliottWaveInfoValue.gmma, 4);
        text += " ";
        text += elliottWaveInfoValue.elliott;

        return text;
    }

    /**
     * 右側空白埋め
     *
     * @param textValue 対象文字列
     * @param lengthValue 桁数
     * @return 整形後文字列
     */
    string rightPad(string textValue, int lengthValue) {
        string textValueWork = textValue;

        while (StringLen(textValueWork) < lengthValue) {
            textValueWork += " ";
        }

        return textValueWork;
    }
};

#endif
