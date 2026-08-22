//+------------------------------------------------------------------+
//|                                  ExpertAdvisorMtf3In3Adapter.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Strategy
 * File: ExpertAdvisorMtf3In3Adapter.mqh
 */

#ifndef MSTNGEA_STRATEGY_EXPERTADVISORMTF3IN3ADAPTER_MQH
#define MSTNGEA_STRATEGY_EXPERTADVISORMTF3IN3ADAPTER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\ExpertAdvisor\ElliottWaveInfo.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentMode.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationMode.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <MstngEa\Strategy\IStrategyAdapter.mqh>

/**
 * ExpertAdvisorMTF_3in3 アダプタ
 */
class ExpertAdvisorMtf3In3Adapter : public IStrategyAdapter {
public:
    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param signalCountValue シグナル回数
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード
     * @param fromH1Ema200ConfirmationMode H1エントリーのEMA200確認モード
     */
    ExpertAdvisorMtf3In3Adapter(
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue,
        SignalCount *signalCountValue,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1Ema200ConfirmationMode fromH1Ema200ConfirmationMode =
            H1_EMA200_CONFIRMATION_H1_ONLY
    ) {
        this.expertAdvisorMtf3In3 = NULL;
        this.signalCount = NULL;
        MarketContext context(symbolNameValue, timeFrameValue);
        this.initialize(
            context,
            signalCountValue,
            fromH1W1ConfirmationMode,
            fromH1Ema200ConfirmationMode
        );
    }

    /**
     * コンストラクタ
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromSignalCount シグナル回数
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード
     * @param fromH1Ema200ConfirmationMode H1エントリーのEMA200確認モード
     */
    ExpertAdvisorMtf3In3Adapter(
        MarketContext &fromMarketContext,
        SignalCount *fromSignalCount,
        H1W1ConfirmationMode fromH1W1ConfirmationMode =
            H1_W1_CONFIRMATION_OBSERVE_ONLY,
        H1Ema200ConfirmationMode fromH1Ema200ConfirmationMode =
            H1_EMA200_CONFIRMATION_H1_ONLY
    ) {
        this.expertAdvisorMtf3In3 = NULL;
        this.signalCount = NULL;
        this.initialize(
            fromMarketContext,
            fromSignalCount,
            fromH1W1ConfirmationMode,
            fromH1Ema200ConfirmationMode
        );
    }

    /**
     * デストラクタ
     */
    ~ExpertAdvisorMtf3In3Adapter() {
        if (this.expertAdvisorMtf3In3 != NULL) {
            delete this.expertAdvisorMtf3In3;
            this.expertAdvisorMtf3In3 = NULL;
        }

        this.signalCount = NULL;
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
        signalDecision.mtf3In3AlertResult.reset();

        if (this.expertAdvisorMtf3In3 == NULL) {
            return signalDecision;
        }

        // 外部戦略で判定
        this.expertAdvisorMtf3In3.analyze(elliotAllValue, this.signalCount);
        this.updateElliottInfoText();
        signalDecision.isEntry = this.expertAdvisorMtf3In3.isEntry;
        signalDecision.isBuy = this.expertAdvisorMtf3In3.isBuy;
        signalDecision.reason = this.expertAdvisorMtf3In3.name;
        signalDecision.stopLoss = this.expertAdvisorMtf3In3.stopLoss;
        signalDecision.csvText = this.expertAdvisorMtf3In3.csvText;
        signalDecision.alertText = this.expertAdvisorMtf3In3.alertText;
        signalDecision.mtf3In3AlertResult =
            this.expertAdvisorMtf3In3.getAlertResult();

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

        if (this.expertAdvisorMtf3In3 == NULL) {
            return exitDecision;
        }

        // 外部戦略で判定
        exitDecision.isExit = this.expertAdvisorMtf3In3.isExit(
            elliotAllValue,
            isBuyPositionValue
        );
        this.updateElliottInfoText();
        exitDecision.reason = this.expertAdvisorMtf3In3.name;

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
        return "MTF_3in3";
    }

private:
    /** 外部戦略 */
    ExpertAdvisorMTF_3in3 *expertAdvisorMtf3In3;

    /** シグナル回数 */
    SignalCount *signalCount;

    /** エリオット情報 */
    string elliottInfoText;

    /**
     * 市場コンテキストを使用して初期化する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromSignalCount シグナル回数
     * @param fromH1W1ConfirmationMode H1エントリーのW1確認モード
     * @param fromH1Ema200ConfirmationMode H1エントリーのEMA200確認モード
     */
    void initialize(
        MarketContext &fromMarketContext,
        SignalCount *fromSignalCount,
        H1W1ConfirmationMode fromH1W1ConfirmationMode,
        H1Ema200ConfirmationMode fromH1Ema200ConfirmationMode
    ) {
        // 外部戦略を生成
        this.expertAdvisorMtf3In3 = ExpertAdvisorMtf3In3Factory::create(
            fromMarketContext,
            false,
            fromH1W1ConfirmationMode,
            H1_DIRECTION_ALIGNMENT_D1_TO_H1,
            fromH1Ema200ConfirmationMode
        );
        this.signalCount = fromSignalCount;
        this.elliottInfoText = "-";
    }

    /**
     * エリオット情報文字列更新
     */
    void updateElliottInfoText() {
        if (this.expertAdvisorMtf3In3 == NULL) {
            this.elliottInfoText = "-";
            return;
        }

        int totalCount = this.expertAdvisorMtf3In3.elliottWaveInfoList.Total();
        string text = "";
        int i;

        if (totalCount <= 0) {
            this.elliottInfoText = "-";
            return;
        }

        for (i = totalCount - 1; i >= 0; i--) {
            ElliottWaveInfo *elliottWaveInfo =
                (ElliottWaveInfo *)this.expertAdvisorMtf3In3.elliottWaveInfoList.At(i);

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
