//+------------------------------------------------------------------+
//|                                      H1EntryWaveDecision.mqh     |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_H1_ENTRY_WAVE_DECISION_MQH
#define MSTNG_EXPERT_ADVISOR_H1_ENTRY_WAVE_DECISION_MQH

#include <Mstng\Elliot\Elliot.mqh>
#include <Mstng\Util\StringUtil.mqh>

/**
 * H1エントリーで使用する時間足別波動判定結果。
 */
struct H1EntryWaveResult {
    /** 波動判定状態。 */
    string state;

    /** 判定対象として期待した時間足。 */
    ENUM_TIMEFRAMES timeFrame;

    /** 最新Elliottラベル。 */
    string elliotLabel;

    /** エントリー対象外理由。許可時は空文字列。 */
    string rejectReason;

    /** 対象時間足の最新Waveとポイントを取得できた場合true。 */
    bool isAvailable;

    /** 最新ラベルが1、3または5の場合true。 */
    bool isEntryLabel;

    /** 対象ラベルと第5波構造が有効な場合true。 */
    bool isValid;

    /** 最新ラベルが5の場合true。 */
    bool isWave5;

    /** 第5波と同じWave内に数字の第3波が存在する場合true。 */
    bool hasWave3;

    /** 同じWave内の数字の第3波に副次波情報がある場合true。 */
    bool hasWave3SubElliot;

    /** H1エントリー用の波動条件を満たす場合true。 */
    bool isAllowed;

    /**
     * 指定時間足の未判定状態へ初期化する。
     *
     * @param fromTimeFrame 判定対象として期待する時間足。
     */
    void reset(const ENUM_TIMEFRAMES fromTimeFrame) {
        this.state = "NOT_EVALUATED";
        this.timeFrame = fromTimeFrame;
        this.elliotLabel = "";
        this.rejectReason = "";
        this.isAvailable = false;
        this.isEntryLabel = false;
        this.isValid = false;
        this.isWave5 = false;
        this.hasWave3 = false;
        this.hasWave3SubElliot = false;
        this.isAllowed = false;
    }
};

/**
 * H1エントリーにおけるH1およびH4の波動条件を共通判定する。
 *
 * 第1波と第3波は許可する。第5波は、有効な数字の推進波であり、
 * 同じWave内の数字の第3波に副次波情報が一切ない場合だけ許可する。
 */
class H1EntryWaveDecision {
public:
    /**
     * 時間足別の理由コードを指定して波動条件を判定する。
     *
     * @param fromElliot 判定対象のElliott分析結果。
     * @param fromExpectedTimeFrame 期待する時間足。
     * @param fromUnavailableReason 分析結果を取得できない場合の理由。
     * @param fromLabelRejectedReason ラベルまたは第5波構造が不正な場合の理由。
     * @param fromWave3SubElliotPresentReason 第3波に副次波がある場合の理由。
     * @param fromResult 判定結果の格納先。
     * @return エントリー波動条件を満たす場合true。
     */
    bool evaluate(
        Elliot *fromElliot,
        const ENUM_TIMEFRAMES fromExpectedTimeFrame,
        const string fromUnavailableReason,
        const string fromLabelRejectedReason,
        const string fromWave3SubElliotPresentReason,
        H1EntryWaveResult &fromResult
    ) {
        fromResult.reset(fromExpectedTimeFrame);

        if (fromElliot == NULL
                || fromElliot.marketContext.timeFrame
                    != fromExpectedTimeFrame) {
            fromResult.state = "UNAVAILABLE";
            fromResult.rejectReason = fromUnavailableReason;

            return false;
        }

        Wave *latestWave = fromElliot.getLatestWave();
        ZigZagPoint *latestPoint = fromElliot.getLatestPoint();

        if (latestWave == NULL || latestPoint == NULL) {
            fromResult.state = "UNAVAILABLE";
            fromResult.rejectReason = fromUnavailableReason;

            return false;
        }

        fromResult.isAvailable = true;
        fromResult.elliotLabel = latestPoint.elliotLabel;
        fromResult.rejectReason = fromLabelRejectedReason;

        if (fromResult.elliotLabel == "1"
                || fromResult.elliotLabel == "3") {
            fromResult.state = "ALLOWED_1_OR_3";
            fromResult.isEntryLabel = true;
            fromResult.isValid = true;
            fromResult.isAllowed = true;
            fromResult.rejectReason = "";

            return true;
        }

        if (fromResult.elliotLabel != "5") {
            fromResult.state = "LABEL_REJECTED";

            return false;
        }

        fromResult.isEntryLabel = true;
        fromResult.isWave5 = true;

        if (!latestWave.isMotive
                || !latestPoint.isNumeric()
                || latestPoint.elliotIndex != 5) {
            fromResult.state = "WAVE5_STRUCTURE_INVALID";

            return false;
        }

        for (int i = 0; i < latestWave.zigZagPointList.Total(); i++) {
            ZigZagPoint *point = latestWave.zigZagPointList.At(i);

            if (point == NULL
                    || !point.isNumeric()
                    || point.elliotIndex != 3) {
                continue;
            }

            fromResult.hasWave3 = true;

            if (point.subElliotIndex != 0
                    || !StringUtil::isEmpty(point.subElliotLabel)) {
                fromResult.hasWave3SubElliot = true;
            }
        }

        if (!fromResult.hasWave3) {
            fromResult.state = "WAVE5_STRUCTURE_INVALID";

            return false;
        }

        fromResult.isValid = true;

        if (fromResult.hasWave3SubElliot) {
            fromResult.state = "WAVE3_SUB_ELLIOT_PRESENT";
            fromResult.rejectReason = fromWave3SubElliotPresentReason;

            return false;
        }

        fromResult.state = "ALLOWED_5";
        fromResult.isAllowed = true;
        fromResult.rejectReason = "";

        return true;
    }

    /**
     * 共通理由コードを使用して波動条件を判定する。
     *
     * @param fromElliot 判定対象のElliott分析結果。
     * @param fromExpectedTimeFrame 期待する時間足。
     * @param fromResult 判定結果の格納先。
     * @return エントリー波動条件を満たす場合true。
     */
    bool evaluate(
        Elliot *fromElliot,
        const ENUM_TIMEFRAMES fromExpectedTimeFrame,
        H1EntryWaveResult &fromResult
    ) {
        return this.evaluate(
            fromElliot,
            fromExpectedTimeFrame,
            "ELLIOT_UNAVAILABLE",
            "ELLIOT_LABEL_REJECTED",
            "WAVE3_SUB_ELLIOT_PRESENT_REJECTED",
            fromResult
        );
    }
};

#endif // MSTNG_EXPERT_ADVISOR_H1_ENTRY_WAVE_DECISION_MQH
