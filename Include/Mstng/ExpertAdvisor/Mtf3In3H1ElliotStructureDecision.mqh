//+------------------------------------------------------------------+
//|                             Mtf3In3H1ElliotStructureDecision.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_EXPERT_ADVISOR_MTF3_IN3_H1_ELLIOT_STRUCTURE_DECISION_MQH
#define MSTNG_EXPERT_ADVISOR_MTF3_IN3_H1_ELLIOT_STRUCTURE_DECISION_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * H1エントリーにおけるD1、H4およびH1のElliott構造ランク。
 */
enum Mtf3In3H1ElliotStructureRank {
    /** D1推進Waveの奇数phase。 */
    mtf3In3H1ElliotStructureRankS = 0,

    /** D1修正Waveの奇数phase。 */
    mtf3In3H1ElliotStructureRankA = 1,

    /** D1推進Waveの偶数phase。 */
    mtf3In3H1ElliotStructureRankB = 2,

    /** D1修正Waveの偶数phase。 */
    mtf3In3H1ElliotStructureRankC = 3,

    /** 親子関係または波動情報に矛盾がある。 */
    mtf3In3H1ElliotStructureRankException = 4,

    /** H1以外、またはD1、H4、H1の売買方向が不一致。 */
    mtf3In3H1ElliotStructureRankNotApplicable = 5
};

/**
 * H1エントリーのElliott構造ランク判定結果。
 */
class Mtf3In3H1ElliotStructureResult {
public:
    /** 構造ランク。 */
    Mtf3In3H1ElliotStructureRank rank;

    /** BUYまたはSELLが一致し、構造を評価した場合true。 */
    bool isEvaluated;

    /** D1、H4およびH1の親子構造が有効な場合true。 */
    bool isStructureValid;

    /** D1またはH4が5、Eの終盤phaseの場合true。 */
    bool isLate;

    /** 売買方向といずれかの現在脚方向が一致しない場合true。 */
    bool isDirectionException;

    /** D1のWave種別。 */
    string d1WaveType;

    /** D1の有効Elliottラベル。 */
    string d1ElliotLabel;

    /** H4のWave種別。 */
    string h4WaveType;

    /** H4の有効Elliottラベル。 */
    string h4ElliotLabel;

    /** H1のElliottラベル。 */
    string h1ElliotLabel;

    /**
     * 未判定状態で初期化する。
     */
    Mtf3In3H1ElliotStructureResult() {
        this.reset();
    }

    /**
     * 全フィールドを未判定状態へ戻す。
     */
    void reset() {
        this.rank = mtf3In3H1ElliotStructureRankNotApplicable;
        this.isEvaluated = false;
        this.isStructureValid = false;
        this.isLate = false;
        this.isDirectionException = false;
        this.d1WaveType = "";
        this.d1ElliotLabel = "";
        this.h4WaveType = "";
        this.h4ElliotLabel = "";
        this.h1ElliotLabel = "";
    }

    /**
     * 構造ランクの表示名を取得する。
     *
     * @return S、A、B、C、EXCEPTIONまたはNOT_APPLICABLE。
     */
    string getRankLabel() {
        switch (this.rank) {
            case mtf3In3H1ElliotStructureRankS:
                return "S";

            case mtf3In3H1ElliotStructureRankA:
                return "A";

            case mtf3In3H1ElliotStructureRankB:
                return "B";

            case mtf3In3H1ElliotStructureRankC:
                return "C";

            case mtf3In3H1ElliotStructureRankException:
                return "EXCEPTION";

            default:
                return "NOT_APPLICABLE";
        }
    }

    /**
     * 終盤および方向例外を含む表示名を取得する。
     *
     * @return アラート表示用の構造ランク名。
     */
    string getDisplayLabel() {
        string text = this.getRankLabel();

        if (!this.isEvaluated) {
            return text;
        }

        if (this.isLate) {
            text += "-LATE";
        }

        if (this.isDirectionException) {
            text += "-DIR";
        }

        return text;
    }
};

/**
 * H1エントリーのD1、H4およびH1から構造ランクを判定するクラス。
 *
 * エントリー可否には影響を与えず、表示と検証に使用する。
 */
class Mtf3In3H1ElliotStructureDecision {
public:
    /**
     * D1、H4およびH1のElliott構造を評価する。
     *
     * D1、H4およびH1のBUYまたはSELLが一致することを評価の前提とする。
     * D1とH4の削除済みポイントは、下位波生成処理と同じく元phaseを使用する。
     *
     * @param fromElliotAll 複数時間足のElliott分析結果。
     * @param fromResult 判定結果の格納先。
     */
    void evaluate(
        ElliotAll *fromElliotAll,
        Mtf3In3H1ElliotStructureResult &fromResult
    ) {
        fromResult.reset();

        if (fromElliotAll == NULL) {
            return;
        }

        if (!fromElliotAll.isAnalysisSucceeded) {
            return;
        }

        if (fromElliotAll.marketContext.timeFrame != PERIOD_H1) {
            return;
        }

        fromResult.rank = mtf3In3H1ElliotStructureRankException;

        Elliot *elliotD1 = fromElliotAll.getElliot(PERIOD_D1);
        Elliot *elliotH4 = fromElliotAll.getElliot(PERIOD_H4);
        Elliot *elliotH1 = fromElliotAll.getElliot(PERIOD_H1);

        if (elliotD1 == NULL || elliotH4 == NULL || elliotH1 == NULL) {
            return;
        }

        Wave *waveD1 = elliotD1.getLatestWave();
        Wave *waveH4 = elliotH4.getLatestWave();
        Wave *waveH1 = elliotH1.getLatestWave();
        ZigZagPoint *pointD1 = elliotD1.getLatestPoint();
        ZigZagPoint *pointH4 = elliotH4.getLatestPoint();
        ZigZagPoint *pointH1 = elliotH1.getLatestPoint();

        if (waveD1 == NULL || waveH4 == NULL || waveH1 == NULL
                || pointD1 == NULL || pointH4 == NULL || pointH1 == NULL) {
            return;
        }

        if (elliotD1.isBuy != elliotH4.isBuy
                || elliotD1.isBuy != elliotH1.isBuy) {
            fromResult.rank =
                mtf3In3H1ElliotStructureRankNotApplicable;

            return;
        }

        fromResult.isEvaluated = true;

        int d1Index = this.getPhaseIndex(pointD1, true);
        int h4Index = this.getPhaseIndex(pointH4, true);
        int h1Index = this.getPhaseIndex(pointH1, false);

        fromResult.d1WaveType = this.getWaveTypeLabel(waveD1);
        fromResult.d1ElliotLabel = this.getPhaseLabel(
            d1Index,
            pointD1.isElliotAlphabet
        );
        fromResult.h4WaveType = this.getWaveTypeLabel(waveH4);
        fromResult.h4ElliotLabel = this.getPhaseLabel(
            h4Index,
            pointH4.isElliotAlphabet
        );
        fromResult.h1ElliotLabel = this.getPhaseLabel(
            h1Index,
            pointH1.isElliotAlphabet
        );

        if (!this.isValidPhaseIndex(d1Index)
                || !this.isValidPhaseIndex(h4Index)
                || !this.isValidPhaseIndex(h1Index)) {
            return;
        }

        fromResult.isLate = d1Index == 5 || h4Index == 5;
        fromResult.isDirectionException =
            !this.isCurrentLegDirectionMatched(
                waveD1,
                d1Index,
                elliotH1.isBuy
            )
            || !this.isCurrentLegDirectionMatched(
                waveH4,
                h4Index,
                elliotH1.isBuy
            )
            || !this.isCurrentLegDirectionMatched(
                waveH1,
                h1Index,
                elliotH1.isBuy
            );

        if (!this.isPointWaveTypeMatched(pointD1, waveD1)
                || !this.isPointWaveTypeMatched(pointH4, waveH4)
                || !this.isPointWaveTypeMatched(pointH1, waveH1)) {
            return;
        }

        if (waveH4.isMotive != this.isOddPhase(d1Index)
                || waveH1.isMotive != this.isOddPhase(h4Index)) {
            return;
        }

        string expectedH1Label = IntegerToString(h1Index);

        if (!waveH1.isMotive
                || pointH1.isElliotAlphabet
                || (h1Index != 1 && h1Index != 3)
                || pointH1.elliotLabel != expectedH1Label) {
            return;
        }

        bool isD1OddPhase = this.isOddPhase(d1Index);

        if (waveD1.isMotive) {
            if (isD1OddPhase) {
                fromResult.rank = mtf3In3H1ElliotStructureRankS;
            } else {
                fromResult.rank = mtf3In3H1ElliotStructureRankB;
            }
        } else {
            if (isD1OddPhase) {
                fromResult.rank = mtf3In3H1ElliotStructureRankA;
            } else {
                fromResult.rank = mtf3In3H1ElliotStructureRankC;
            }
        }

        fromResult.isStructureValid = true;
    }

private:
    /**
     * ポイントの評価用phase番号を取得する。
     *
     * @param fromPoint 対象ポイント。
     * @param fromAllowsOriginal 削除済みの場合に元番号を使用する場合true。
     * @return 評価用phase番号。
     */
    int getPhaseIndex(
        ZigZagPoint *fromPoint,
        const bool fromAllowsOriginal
    ) {
        int index = fromPoint.elliotIndex;

        if (fromAllowsOriginal && index == Constant::DELETE_FLG) {
            index = fromPoint.orgElliotIndex;
        }

        return index;
    }

    /**
     * Wave種別の表示名を取得する。
     *
     * @param fromWave 対象Wave。
     * @return MOTIVEまたはCORRECTIVE。
     */
    string getWaveTypeLabel(Wave *fromWave) {
        if (fromWave.isMotive) {
            return "MOTIVE";
        }

        return "CORRECTIVE";
    }

    /**
     * phase番号とラベル種別から表示名を取得する。
     *
     * @param fromIndex phase番号。
     * @param fromIsAlphabet アルファベット波の場合true。
     * @return 数字またはアルファベットのphase表示名。
     */
    string getPhaseLabel(
        const int fromIndex,
        const bool fromIsAlphabet
    ) {
        if (!fromIsAlphabet) {
            return IntegerToString(fromIndex);
        }

        switch (fromIndex) {
            case 1:
                return "A";

            case 2:
                return "B";

            case 3:
                return "C";

            case 4:
                return "D";

            case 5:
                return "E";

            default:
                return "#" + IntegerToString(fromIndex);
        }
    }

    /**
     * phase番号が1から5の範囲か判定する。
     *
     * @param fromIndex phase番号。
     * @return 有効なphase番号の場合true。
     */
    bool isValidPhaseIndex(const int fromIndex) {
        return 1 <= fromIndex && fromIndex <= 5;
    }

    /**
     * phase番号が奇数か判定する。
     *
     * @param fromIndex phase番号。
     * @return 奇数の場合true。
     */
    bool isOddPhase(const int fromIndex) {
        return fromIndex % 2 != 0;
    }

    /**
     * ポイントの数字・アルファベット種別がWave種別と一致するか判定する。
     *
     * @param fromPoint 対象ポイント。
     * @param fromWave 対象Wave。
     * @return 種別が一致する場合true。
     */
    bool isPointWaveTypeMatched(
        ZigZagPoint *fromPoint,
        Wave *fromWave
    ) {
        if (fromWave.isMotive) {
            return !fromPoint.isElliotAlphabet;
        }

        return fromPoint.isElliotAlphabet;
    }

    /**
     * 現在phaseの脚方向が売買方向と一致するか判定する。
     *
     * 偶数phaseではWave方向と現在脚方向が逆になる。
     *
     * @param fromWave 対象Wave。
     * @param fromIndex phase番号。
     * @param fromIsBuy BUY方向の場合true。
     * @return 現在脚方向が売買方向と一致する場合true。
     */
    bool isCurrentLegDirectionMatched(
        Wave *fromWave,
        const int fromIndex,
        const bool fromIsBuy
    ) {
        bool isCurrentLegUptrend = fromWave.isUptrend;

        if (!this.isOddPhase(fromIndex)) {
            isCurrentLegUptrend = !isCurrentLegUptrend;
        }

        return isCurrentLegUptrend == fromIsBuy;
    }
};

#endif // MSTNG_EXPERT_ADVISOR_MTF3_IN3_H1_ELLIOT_STRUCTURE_DECISION_MQH
