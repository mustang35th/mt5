#ifndef MSTNGH1EA_INITIAL_STOP_LOSS_DECISION_MQH
#define MSTNGH1EA_INITIAL_STOP_LOSS_DECISION_MQH

#include <MstngEaCommon\Runtime\EaInitialStopLossDecision.mqh>

/**
 * H1初期SL判定結果の既存公開名を維持する互換型。
 */
struct H1EaInitialStopLossResult : EaInitialStopLossResult {
};

/**
 * H1シグナル基準点±10pipsを共通の初期SL判定へ渡す互換窓口。
 */
class H1EaInitialStopLossDecision {
public:
    /**
     * 方向、価格単位、最大リスクとbroker Stops距離を検証する。
     *
     * @param fromIsBuy BUY注文の場合true。
     * @param fromPivotPrice シグナル基準点の価格。
     * @param fromPivotIsHigh 基準点が山の場合true。
     * @param fromBid 現在Bid。
     * @param fromAsk 現在Ask。
     * @param fromPipSize 1pipの価格幅。
     * @param fromTickSize 最小価格刻み。
     * @param fromPointSize brokerのpoint幅。
     * @param fromStopsLevel 必須SL距離のpoints数。
     * @param fromMaxRiskPips 許可する正の最大初期SL幅。
     * @param fromResult 判定結果。
     * @return 初期SLが有効な場合true。
     */
    bool evaluate(
        const bool fromIsBuy,
        const double fromPivotPrice,
        const bool fromPivotIsHigh,
        const double fromBid,
        const double fromAsk,
        const double fromPipSize,
        const double fromTickSize,
        const double fromPointSize,
        const long fromStopsLevel,
        const double fromMaxRiskPips,
        H1EaInitialStopLossResult &fromResult
    ) {
        EaInitialStopLossDecision decision;

        return decision.evaluate(
            fromIsBuy, fromPivotPrice, fromPivotIsHigh, fromBid, fromAsk,
            fromPipSize, fromTickSize, fromPointSize, fromStopsLevel,
            fromMaxRiskPips, 10.0, fromResult
        );
    }
};

#endif
