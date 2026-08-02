//+------------------------------------------------------------------+
//|                    ElliotDirectionAlignmentDecision.mqh         |
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

/**
 * D1から現在時間足までのElliott売買方向一致を判定するクラス。
 * 一覧表示と複数通貨スキャンで共通の対象時間足構成を提供する。
 */
class ElliotDirectionAlignmentDecision {
public:
    /**
     * D1から現在時間足までの対象時間足一覧を生成する。
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
            PERIOD_D1,
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
     * D1から現在時間足までのElliott売買方向一致種別を取得する。
     *
     * @param fromElliotAll 複数時間足Elliott分析結果
     * @param fromCurrentTimeFrame 現在時間足
     * @return BUY一致、SELL一致、または不一致
     */
    TrendAlignType getAlignType(
        ElliotAll *fromElliotAll,
        ENUM_TIMEFRAMES fromCurrentTimeFrame
    ) {
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

private:
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
