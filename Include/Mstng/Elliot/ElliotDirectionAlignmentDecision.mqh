//+------------------------------------------------------------------+
//|                             ElliotDirectionAlignmentDecision.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef ELLIOT_DIRECTION_ALIGNMENT_DECISION_MQH
#define ELLIOT_DIRECTION_ALIGNMENT_DECISION_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ElliotTimeFrameRange.mqh>
#include <Mstng\Elliot\TrendAlignDecision.mqh>

/** Elliott売買方向一致の判定ルール。 */
enum ElliotDirectionAlignmentRule {
    ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES = 0,
    ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200 = 1,
    ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200 = 2
};

/**
 * 指定開始足から現在時間足までのElliott売買方向一致を判定するクラス。
 * 一覧表示と複数通貨スキャンで共通の対象時間足構成を提供する。
 */
class ElliotDirectionAlignmentDecision {
public:
    /**
     * 一致判定の開始時間足を指定して初期化する。
     *
     * @param fromAlignmentStartTimeFrame 一致判定の開始時間足
     * @param fromAlignmentRule 一致判定ルール
     */
    ElliotDirectionAlignmentDecision(
        ENUM_TIMEFRAMES fromAlignmentStartTimeFrame = PERIOD_D1,
        ElliotDirectionAlignmentRule fromAlignmentRule =
            ELLIOT_DIRECTION_ALIGNMENT_RULE_ALL_TIME_FRAMES
    ) {
        this.alignmentStartTimeFrame = fromAlignmentStartTimeFrame;
        this.alignmentRule = fromAlignmentRule;
    }

    /**
     * 一致判定の開始時間足を取得する。
     *
     * @return 一致判定の開始時間足
     */
    ENUM_TIMEFRAMES getAlignmentStartTimeFrame() {
        return this.alignmentStartTimeFrame;
    }

    /**
     * 一致判定ルールを取得する。
     *
     * @return 一致判定ルール
     */
    ElliotDirectionAlignmentRule getAlignmentRule() {
        return this.alignmentRule;
    }

    /**
     * 指定開始足から現在時間足までの対象時間足一覧を生成する。
     *
     * @param fromCurrentTimeFrame 現在時間足
     * @param fromTimeFrames 対象時間足一覧の格納先
     * @return 対応時間足の場合true
     */
    bool buildTargetTimeFrames(
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        ENUM_TIMEFRAMES &fromTimeFrames[]
    ) {
        return ElliotTimeFrameRange::build(
            this.alignmentStartTimeFrame,
            fromCurrentTimeFrame,
            fromTimeFrames
        );
    }

    /**
     * 一致判定に必要な全時間足の分析結果が揃っているか判定する。
     *
     * @param fromElliotAll 複数時間足Elliott分析結果
     * @param fromCurrentTimeFrame 現在時間足
     * @return 判定可能な場合true
     */
    bool isReady(
        ElliotAll *fromElliotAll,
        ENUM_TIMEFRAMES fromCurrentTimeFrame
    ) {
        if (this.alignmentRule
                == ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200
                && (fromCurrentTimeFrame != PERIOD_D1
                    || this.alignmentStartTimeFrame != PERIOD_MN1)) {
            return false;
        }

        if (this.alignmentRule
                == ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200
                && (fromCurrentTimeFrame != PERIOD_H1
                    || this.alignmentStartTimeFrame != PERIOD_MN1)) {
            return false;
        }

        ENUM_TIMEFRAMES timeFrames[];

        if (!this.buildTargetTimeFrames(fromCurrentTimeFrame, timeFrames)) {
            return false;
        }

        return this.isReadyWithTimeFrames(
            fromElliotAll,
            fromCurrentTimeFrame,
            timeFrames
        );
    }

    /**
     * 指定開始足から現在時間足までのElliott売買方向一致種別を取得する。
     *
     * @param fromElliotAll 複数時間足Elliott分析結果
     * @param fromCurrentTimeFrame 現在時間足
     * @return BUY一致、SELL一致、または不一致
     */
    TrendAlignType getAlignType(
        ElliotAll *fromElliotAll,
        ENUM_TIMEFRAMES fromCurrentTimeFrame
    ) {
        if (this.alignmentRule
                == ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200
                && (fromCurrentTimeFrame != PERIOD_D1
                    || this.alignmentStartTimeFrame != PERIOD_MN1)) {
            return trendAlignNone;
        }

        if (this.alignmentRule
                == ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200
                && (fromCurrentTimeFrame != PERIOD_H1
                    || this.alignmentStartTimeFrame != PERIOD_MN1)) {
            return trendAlignNone;
        }

        ENUM_TIMEFRAMES timeFrames[];

        if (!this.buildTargetTimeFrames(fromCurrentTimeFrame, timeFrames)) {
            return trendAlignNone;
        }

        if (!this.isReadyWithTimeFrames(
            fromElliotAll,
            fromCurrentTimeFrame,
            timeFrames
        )) {
            return trendAlignNone;
        }

        if (this.alignmentRule
                == ELLIOT_DIRECTION_ALIGNMENT_RULE_D1_W1_WITH_MN1_OR_EMA200) {
            Elliot *elliotD1 = fromElliotAll.getElliot(PERIOD_D1);
            Elliot *elliotW1 = fromElliotAll.getElliot(PERIOD_W1);
            Elliot *elliotMN1 = fromElliotAll.getElliot(PERIOD_MN1);

            if (elliotD1 == NULL
                    || elliotW1 == NULL
                    || elliotMN1 == NULL) {
                return trendAlignNone;
            }

            return ElliotDirectionAlignmentDecision::evaluateD1W1WithMn1OrEma200(
                elliotD1.isBuy,
                elliotW1.isBuy,
                elliotMN1.isBuy,
                elliotW1.oscillator.ema200.isBuy,
                elliotW1.oscillator.ema200.isSell
            );
        }

        if (this.alignmentRule
                == ELLIOT_DIRECTION_ALIGNMENT_RULE_H1_W1_WITH_MN1_OR_EMA200) {
            Elliot *elliotH1 = fromElliotAll.getElliot(PERIOD_H1);
            Elliot *elliotH4 = fromElliotAll.getElliot(PERIOD_H4);
            Elliot *elliotD1 = fromElliotAll.getElliot(PERIOD_D1);
            Elliot *elliotW1 = fromElliotAll.getElliot(PERIOD_W1);
            Elliot *elliotMN1 = fromElliotAll.getElliot(PERIOD_MN1);

            if (elliotH1 == NULL
                    || elliotH4 == NULL
                    || elliotD1 == NULL
                    || elliotW1 == NULL
                    || elliotMN1 == NULL) {
                return trendAlignNone;
            }

            return ElliotDirectionAlignmentDecision::evaluateH1W1WithMn1OrEma200(
                elliotH1.isBuy,
                elliotH4.isBuy,
                elliotD1.isBuy,
                elliotW1.isBuy,
                elliotMN1.isBuy,
                elliotW1.oscillator.ema200.isBuy,
                elliotW1.oscillator.ema200.isSell
            );
        }

        bool isBuy = fromElliotAll.elliotCurrent.isBuy;
        int total = ArraySize(timeFrames);

        for (int i = 0; i < total; i++) {
            Elliot *elliot = fromElliotAll.getElliot(timeFrames[i]);

            if (elliot.isBuy != isBuy) {
                return trendAlignNone;
            }
        }

        if (isBuy) {
            return trendAlignBuy;
        }

        return trendAlignSell;
    }

    /**
     * D1とW1の方向一致に、MN1またはW1 EMA200の方向一致を加えて判定する。
     *
     * @param fromIsD1Buy D1がBUYの場合true
     * @param fromIsW1Buy W1がBUYの場合true
     * @param fromIsMn1Buy MN1がBUYの場合true
     * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true
     * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true
     * @return BUY一致、SELL一致、または不一致
     */
    static TrendAlignType evaluateD1W1WithMn1OrEma200(
        bool fromIsD1Buy,
        bool fromIsW1Buy,
        bool fromIsMn1Buy,
        bool fromIsW1Ema200Buy,
        bool fromIsW1Ema200Sell
    ) {
        if (fromIsW1Ema200Buy && fromIsW1Ema200Sell) {
            return trendAlignNone;
        }

        if (fromIsD1Buy != fromIsW1Buy) {
            return trendAlignNone;
        }

        bool isMn1Matched = fromIsD1Buy == fromIsMn1Buy;
        bool isW1Ema200Matched = false;

        if (fromIsD1Buy && fromIsW1Ema200Buy) {
            isW1Ema200Matched = true;
        } else if (!fromIsD1Buy && fromIsW1Ema200Sell) {
            isW1Ema200Matched = true;
        }

        if (!isMn1Matched && !isW1Ema200Matched) {
            return trendAlignNone;
        }

        if (fromIsD1Buy) {
            return trendAlignBuy;
        }

        return trendAlignSell;
    }

    /**
     * H1、H4、D1、W1の方向一致に、MN1またはW1 EMA200の方向一致を加えて判定する。
     *
     * @param fromIsH1Buy H1がBUYの場合true
     * @param fromIsH4Buy H4がBUYの場合true
     * @param fromIsD1Buy D1がBUYの場合true
     * @param fromIsW1Buy W1がBUYの場合true
     * @param fromIsMn1Buy MN1がBUYの場合true
     * @param fromIsW1Ema200Buy W1 EMA200がBUYの場合true
     * @param fromIsW1Ema200Sell W1 EMA200がSELLの場合true
     * @return BUY一致、SELL一致、または不一致
     */
    static TrendAlignType evaluateH1W1WithMn1OrEma200(
        bool fromIsH1Buy,
        bool fromIsH4Buy,
        bool fromIsD1Buy,
        bool fromIsW1Buy,
        bool fromIsMn1Buy,
        bool fromIsW1Ema200Buy,
        bool fromIsW1Ema200Sell
    ) {
        if (fromIsH1Buy != fromIsH4Buy
                || fromIsH1Buy != fromIsD1Buy) {
            return trendAlignNone;
        }

        return ElliotDirectionAlignmentDecision::evaluateD1W1WithMn1OrEma200(
            fromIsD1Buy,
            fromIsW1Buy,
            fromIsMn1Buy,
            fromIsW1Ema200Buy,
            fromIsW1Ema200Sell
        );
    }

private:
    /** 一致判定の開始時間足。 */
    ENUM_TIMEFRAMES alignmentStartTimeFrame;

    /** 一致判定ルール。 */
    ElliotDirectionAlignmentRule alignmentRule;

    /**
     * 指定時間足一覧の分析結果が一致判定に利用可能か判定する。
     *
     * @param fromElliotAll 複数時間足Elliott分析結果
     * @param fromCurrentTimeFrame 現在時間足
     * @param fromTimeFrames 対象時間足一覧
     * @return 判定可能な場合true
     */
    bool isReadyWithTimeFrames(
        ElliotAll *fromElliotAll,
        ENUM_TIMEFRAMES fromCurrentTimeFrame,
        ENUM_TIMEFRAMES &fromTimeFrames[]
    ) {
        if (fromElliotAll == NULL) {
            return false;
        }

        if (!fromElliotAll.isAnalysisSucceeded) {
            return false;
        }

        if (fromElliotAll.elliotCurrent == NULL) {
            return false;
        }

        if (fromElliotAll.elliotCurrent.marketContext.timeFrame != fromCurrentTimeFrame) {
            return false;
        }

        int total = ArraySize(fromTimeFrames);

        if (total == 0) {
            return false;
        }

        for (int i = 0; i < total; i++) {
            Elliot *elliot = fromElliotAll.getElliot(fromTimeFrames[i]);

            if (elliot == NULL) {
                return false;
            }

            if (elliot.getLatestWave() == NULL) {
                return false;
            }

            if (elliot.getLatestPoint() == NULL) {
                return false;
            }
        }

        return true;
    }
};

#endif
