#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_SYMBOL_STATE_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_SYMBOL_STATE_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorStrengthProvider.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorTypes.mqh>
#include <Mstng\Oscillator\OscillatorHandlePool.mqh>
#include <Mstng\Signal\SignalCount.mqh>

/**
 * 1通貨の監視時刻、確定したシグナル回数と再利用する取得資源を所有する。
 */
class ZigZagElliotMonitorSymbolState : public CObject {
public:
    /** 接頭辞・接尾辞を除いた監視対象の通貨ペア名。 */
    string canonicalSymbolName;

    /** 口座で解決した実際の銘柄名。未解決の場合は空文字。 */
    string symbolName;

    /** M1の分析対象。 */
    MarketContext marketContext;

    /** 初回または再開後の確認が完了した場合true。 */
    bool baselineReady;

    /** 判定を完了したM1バー開始時刻。 */
    datetime lastProcessedBarTime;

    /** 現在評価しているM1バー開始時刻。 */
    datetime evaluationBarTime;

    /** 今回のM1評価へ固定したM5開始時刻。 */
    datetime targetM5BarTime;

    /** 次に不足データを再確認できる経過ミリ秒。 */
    ulong nextRetryTick;

    /** 最後に確認を開始した時点の共通サーバーM1枠。進捗表示専用。 */
    datetime lastAttemptBarTime;

    /** 一覧に保持する直近の判定結果。 */
    ZigZagElliotMonitorResult result;

    /** 最後にエントリー成立を確認したサーバー時刻。 */
    datetime lastEntryTime;

    /** 最後に記録した成立シグナルの売買方向。 */
    bool lastEntryIsBuy;

    /** 条件判定と分離したチャート表示状態。 */
    string chartStatus;

    /** 入力の整合確認を通過した判定だけを数える所有インスタンス。 */
    SignalCount *signalCount;

    /** この通貨の現在順位・増減履歴を再利用する所有インスタンス。 */
    ZigZagElliotMonitorStrengthProvider *strengthProvider;

    /** 必要になった通貨だけに作成する分析ハンドル。 */
    OscillatorHandlePool *oscillatorHandlePool;

    /**
     * 通貨ごとの状態を準備する。履歴とハンドルは最初の評価時に作成する。
     *
     * @param fromCanonicalSymbolName 正規通貨ペア名。
     * @param fromSymbolName 解決済み銘柄名。
     */
    ZigZagElliotMonitorSymbolState(const string fromCanonicalSymbolName,
            const string fromSymbolName) {
        this.canonicalSymbolName = fromCanonicalSymbolName;
        this.symbolName = fromSymbolName;
        this.marketContext.setTimeFrame(PERIOD_M1);
        if (fromSymbolName != "") {
            this.marketContext.setSymbolName(fromSymbolName);
        }

        this.baselineReady = false;
        this.lastProcessedBarTime = 0;
        this.evaluationBarTime = 0;
        this.targetM5BarTime = 0;
        this.nextRetryTick = 0;
        this.lastAttemptBarTime = 0;
        this.result.reset();
        this.lastEntryTime = 0;
        this.lastEntryIsBuy = false;
        this.chartStatus = "—";
        this.signalCount = NULL;
        this.strengthProvider = NULL;
        this.oscillatorHandlePool = NULL;
    }

    /**
     * 通貨ごとに所有する資源だけを解放する。
     */
    ~ZigZagElliotMonitorSymbolState() {
        if (this.signalCount != NULL) {
            delete this.signalCount;
            this.signalCount = NULL;
        }

        if (this.strengthProvider != NULL) {
            delete this.strengthProvider;
            this.strengthProvider = NULL;
        }

        if (this.oscillatorHandlePool != NULL) {
            delete this.oscillatorHandlePool;
            this.oscillatorHandlePool = NULL;
        }
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_SYMBOL_STATE_MQH
