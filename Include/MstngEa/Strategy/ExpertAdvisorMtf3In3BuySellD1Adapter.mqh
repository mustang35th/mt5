/**
 * Package: MstngEa.Strategy
 * File: ExpertAdvisorMtf3In3BuySellD1Adapter.mqh
 */

#ifndef MSTNGEA_STRATEGY_EXPERTADVISORMTF3IN3BUYSELLD1ADAPTER_MQH
#define MSTNGEA_STRATEGY_EXPERTADVISORMTF3IN3BUYSELLD1ADAPTER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\ExpertAdvisor\ElliottWaveInfo.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMTF_3in3_BuySellD1.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <MstngEa\Strategy\IStrategyAdapter.mqh>

/**
 * ExpertAdvisorMTF_3in3_BuySellD1 アダプタ
 */
class ExpertAdvisorMtf3In3BuySellD1Adapter : public IStrategyAdapter {
public:
    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param signalCountValue シグナル回数
     */
    ExpertAdvisorMtf3In3BuySellD1Adapter(
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
    ExpertAdvisorMtf3In3BuySellD1Adapter(
        MarketContext &fromMarketContext,
        SignalCount *fromSignalCount
    ) {
        this.initialize(fromMarketContext, fromSignalCount);
    }
    /**
     * デストラクタ
     */
    ~ExpertAdvisorMtf3In3BuySellD1Adapter() {
        delete this.expertAdvisorMtf3In3BuySellD1;
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

        this.expertAdvisorMtf3In3BuySellD1.analyze(elliotAllValue, this.signalCount);
        this.updateElliottInfoText();
        signalDecision.isEntry = this.expertAdvisorMtf3In3BuySellD1.isEntry;
        signalDecision.isBuy = this.expertAdvisorMtf3In3BuySellD1.isBuy;
        signalDecision.reason = this.expertAdvisorMtf3In3BuySellD1.name;
        signalDecision.stopLoss = this.expertAdvisorMtf3In3BuySellD1.stopLoss;
        signalDecision.csvText = this.expertAdvisorMtf3In3BuySellD1.csvText;
        signalDecision.alertText = this.expertAdvisorMtf3In3BuySellD1.alertText;

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

        exitDecision.isExit = this.expertAdvisorMtf3In3BuySellD1.isExit(
            elliotAllValue,
            isBuyPositionValue
        );
        this.updateElliottInfoText();
        exitDecision.reason = this.expertAdvisorMtf3In3BuySellD1.name;

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
        return "MTF_3in3_BuySellD1";
    }

private:
    /** 外部戦略 */
    ExpertAdvisorMTF_3in3_BuySellD1 *expertAdvisorMtf3In3BuySellD1;

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
        this.expertAdvisorMtf3In3BuySellD1 = new ExpertAdvisorMTF_3in3_BuySellD1(
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
        int totalCount = this.expertAdvisorMtf3In3BuySellD1.elliottWaveInfoList.Total();
        string text = "";
        int i;

        if (totalCount <= 0) {
            this.elliottInfoText = "-";
            return;
        }

        for (i = totalCount - 1; i >= 0; i--) {
            ElliottWaveInfo *elliottWaveInfo =
                (ElliottWaveInfo *)this.expertAdvisorMtf3In3BuySellD1.elliottWaveInfoList.At(i);

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
