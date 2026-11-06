//+------------------------------------------------------------------+
//|                                  ChartMouseMoveSubscription.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CHART_MOUSE_MOVE_SUBSCRIPTION_MQH
#define MSTNG_DRAW_CHART_MOUSE_MOVE_SUBSCRIPTION_MQH

#include <Mstng\Log\Logger.mqh>

/**
 * 順位履歴の帯が使うマウス移動イベントを、同一チャート内で共同管理する。
 * 一時グローバル変数へ参加数と最初の設定を保持し、最後の解放時だけ元へ戻す。
 * 管理対象外のプログラムが途中で有効化した要求までは識別できない。
 */
class ChartMouseMoveSubscription {
public:
    /**
     * 未参加状態で初期化する。取得するまで端末グローバル変数は作らない。
     */
    ChartMouseMoveSubscription() {
        this.chartId = 0;
        this.stateKey = "";
        this.acquired = false;
    }

    /**
     * 残っている参加を解放する。
     */
    ~ChartMouseMoveSubscription() {
        this.release();
    }

    /**
     * マウス移動イベントを有効にし、このインスタンスの参加を記録する。
     * 同じチャートへの二重取得は参加数を増やさない。
     *
     * @param fromChartId 対象チャート。0は現在のチャート。
     * @return 参加済み、または有効化と参加の記録に成功した場合true。
     */
    bool acquire(const long fromChartId) {
        long targetChartId = fromChartId;
        if (targetChartId == 0) {
            targetChartId = ChartID();
        }

        if (targetChartId <= 0) {
            return false;
        }

        if (this.acquired) {
            return this.chartId == targetChartId;
        }

        string key = "Mstng.CsrRibbon.Mouse." + IntegerToString(targetChartId);
        // 既存の共有値は保持し、同時作成で失敗した場合も存在を再確認する。
        if (!GlobalVariableCheck(key)
                && !GlobalVariableTemp(key)
                && !GlobalVariableCheck(key)) {
            return false;
        }

        double state = 0;
        if (!this.lock(key, state)) {
            return false;
        }

        if (state >= 2147483646.0) {
            this.unlock(key, state, state);

            return false;
        }

        long enabled = 0;
        if (!ChartGetInteger(targetChartId, CHART_EVENT_MOUSE_MOVE, 0, enabled)) {
            this.unlock(key, state, state);

            return false;
        }

        int count = (int)state / 2;
        int originalFlag = (int)state % 2;
        if (count == 0) {
            originalFlag = 0;
            if (enabled != 0) {
                originalFlag = 1;
            }
        }

        bool changed = enabled == 0;
        if (changed && !ChartSetInteger(targetChartId, CHART_EVENT_MOUSE_MOVE, true)) {
            this.unlock(key, state, state);

            return false;
        }

        double nextState = (double)(count + 1) * 2 + originalFlag;
        if (!this.unlock(key, state, nextState)) {
            if (changed) {
                ChartSetInteger(targetChartId, CHART_EVENT_MOUSE_MOVE, false);
            }

            return false;
        }

        this.chartId = targetChartId;
        this.stateKey = key;
        this.acquired = true;

        return true;
    }

    /**
     * 自身の参加を一度だけ解放し、最後の参加者なら最初の設定へ戻す。
     * API失敗時は参加を保持し、次のreleaseまたはデストラクタで再試行する。
     */
    void release() {
        if (!this.acquired) {
            return;
        }

        double state = 0;
        if (!this.lock(this.stateKey, state)) {
            this.logger.error(__FUNCTION__, "mouse move subscription lock failed");

            return;
        }

        int count = (int)state / 2;
        if (count <= 0) {
            if (this.unlock(this.stateKey, state, 0)) {
                this.reset();
            }

            return;
        }

        double nextState = state - 2;
        if (count == 1) {
            bool originalEnabled = (int)state % 2 != 0;
            if (!ChartSetInteger(this.chartId, CHART_EVENT_MOUSE_MOVE, originalEnabled)) {
                int error = GetLastError();
                this.unlock(this.stateKey, state, state);
                this.logger.error(__FUNCTION__, StringFormat(
                    "mouse move setting restore failed. error=%d", error
                ));

                return;
            }

            nextState = 0;
        }

        if (this.unlock(this.stateKey, state, nextState)) {
            this.reset();
        }
    }

private:
    /** 参加先の確定したチャートID。 */
    long chartId;

    /** 参加数と元の設定を格納する端末一時グローバル変数名。 */
    string stateKey;

    /** 自身の参加を記録済みの場合true。 */
    bool acquired;

    /** 解放・共有状態の反映失敗を記録する。 */
    Logger logger;

    /**
     * 非負の共有状態を負値へ変え、設定変更と参照数更新を排他実行する。
     * 待機でイベントを止めず、競合時は有限回だけ再試行する。
     *
     * @param fromKey 共有状態のキー。
     * @param fromState ロック前の参加数×2＋最初の設定値。
     * @return ロックを取得できた場合true。
     */
    bool lock(const string fromKey, double &fromState) {
        for (int i = 0; i < 32; i++) {
            double state = 0;
            if (!GlobalVariableGet(fromKey, state)
                    || !MathIsValidNumber(state)
                    || state != MathFloor(state)) {
                return false;
            }

            if (state < 0) {
                continue;
            }

            if (state > 2147483647.0) {
                return false;
            }

            if (GlobalVariableSetOnCondition(fromKey, -state - 1, state)) {
                fromState = state;

                return true;
            }
        }

        return false;
    }

    /**
     * 自身が取得した負値ロックを、次の共有状態へ置き換える。
     * 最後の解放後も一時変数を0で残し、次回はチャートの現在設定を読み直す。
     *
     * @param fromKey 共有状態のキー。
     * @param fromState ロック取得前の値。
     * @param fromNextState ロック解除後の値。
     * @return 自身のロックから状態を反映できた場合true。
     */
    bool unlock(const string fromKey, const double fromState, const double fromNextState) {
        if (!GlobalVariableSetOnCondition(fromKey, fromNextState, -fromState - 1)) {
            this.logger.error(__FUNCTION__, StringFormat(
                "mouse move subscription update failed. error=%d", GetLastError()
            ));

            return false;
        }

        return true;
    }

    /**
     * 自身の参加記録だけを初期状態へ戻す。
     */
    void reset() {
        this.chartId = 0;
        this.stateKey = "";
        this.acquired = false;
    }
};

#endif // MSTNG_DRAW_CHART_MOUSE_MOVE_SUBSCRIPTION_MQH
