#ifndef MSTNGH1EA_PRESENTATION_FLOATINGPROFITMONITOR_MQH
#define MSTNGH1EA_PRESENTATION_FLOATINGPROFITMONITOR_MQH

#include <Mstng\Database\Entity\H1EaRunEntity.mqh>
#include <MstngH1Ea\Runtime\H1EaClock.mqh>
#include <MstngH1Ea\Runtime\H1EaMonitorState.mqh>
#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>

/**
 * 表示専用の評価損益を全通貨・通貨別に集計し、1分間保持する。
 * 通貨とMagicが一致する実保有だけを読み、売買・DB・CSV処理を行わない。
 */
class H1EaFloatingProfitMonitor {
public:
    /**
     * 口座やポジションを参照せず、未取得状態にする。
     */
    H1EaFloatingProfitMonitor() {
        this.initialized = false;
        this.sampled = false;
        this.lastSampleTick = 0;
        this.sampleTime = 0;
        this.currency = "";
        this.digits = 2;
        this.clearSample(false);
    }

    /**
     * 登録済み28通貨の識別情報だけを受け取り、次の表示更新を初回取得にする。
     */
    void initialize(const H1EaRunEntity &fromRuns[]) {
        this.initialized = false;
        this.sampled = false;
        this.lastSampleTick = 0;
        this.sampleTime = 0;
        this.currency = "";
        this.digits = 2;
        this.clearSample(false);
        if (ArraySize(fromRuns) != 28) {
            return;
        }
        for (int i = 0; i < 28; i++) {
            if (fromRuns[i].symbolName == "" || H1EaTextUtil::parseTicket(fromRuns[i].magicNumber) == 0) {
                return;
            }
            for (int j = 0; j < i; j++) {
                if (fromRuns[i].symbolName == this.symbols[j]) {
                    return;
                }
            }
            this.symbols[i] = fromRuns[i].symbolName;
            this.magics[i] = H1EaTextUtil::parseTicket(fromRuns[i].magicNumber);
        }
        this.initialized = true;
    }

    /**
     * 初回と60秒経過後だけ取得し、ページ操作では直近の値を画面用コピーへ渡す。
     * 呼出元はパネル非表示・非ビジュアルTesterでは呼び出さない。
     */
    void updateAndCopy(H1EaMonitorState &fromState) {
        ulong now = H1EaClock::milliseconds();
        if (this.initialized && (!this.sampled || now < this.lastSampleTick
                || now - this.lastSampleTick >= 60000)) {
            this.lastSampleTick = now;
            this.sampled = true;
            this.readSample();
        }
        fromState.accountCurrency = this.currency;
        fromState.currencyDigits = this.digits;
        fromState.floatingProfitTime = this.sampleTime;
        fromState.floatingProfitKnown = this.initialized && this.sampled && this.totalKnown
            && fromState.symbolCount == 28;
        fromState.floatingProfit = this.totalProfit;
        fromState.positionCount = this.totalPositions;
        for (int i = 0; i < ArraySize(fromState.symbols); i++) {
            bool matches = this.initialized && this.sampled && i < fromState.symbolCount
                && fromState.symbols[i].symbolName == this.symbols[i];
            fromState.symbols[i].floatingProfitKnown = matches && this.profitKnown[i];
            fromState.symbols[i].floatingProfit = this.profits[i];
            fromState.symbols[i].positionCount = this.positionCounts[i];
            if (!matches) {
                fromState.floatingProfitKnown = false;
            }
        }
    }

private:
    /** 固定28通貨の登録完了。 */
    bool initialized;
    /** 初回取得を実行済みか。取得失敗時も再試行を1分空ける。 */
    bool sampled;
    /** 最後に取得した巡回時計。Testerはテスト内時刻。 */
    ulong lastSampleTick;
    /** 最後の取得を行ったサーバー時刻。 */
    datetime sampleTime;
    /** 登録通貨名。 */
    string symbols[28];
    /** 登録Magic。 */
    ulong magics[28];
    /** 通貨別の取得成功フラグ。 */
    bool profitKnown[28];
    /** 通貨別の評価損益とスワップの合計。 */
    double profits[28];
    /** 通貨別の実保有数。 */
    int positionCounts[28];
    /** 全対象を漏れなく取得できたか。 */
    bool totalKnown;
    /** 全対象の評価損益とスワップの合計。 */
    double totalProfit;
    /** 全対象の実保有数。 */
    int totalPositions;
    /** 口座通貨名。 */
    string currency;
    /** 口座通貨の表示小数桁数。 */
    int digits;

    /**
     * 前回の数値を破棄し、今回の集計を開始する。
     */
    void clearSample(const bool fromKnown) {
        this.totalKnown = fromKnown;
        this.totalProfit = 0.0;
        this.totalPositions = 0;
        for (int i = 0; i < 28; i++) {
            this.profitKnown[i] = fromKnown;
            this.profits[i] = 0.0;
            this.positionCounts[i] = 0;
        }
    }

    /**
     * 所属不明や走査中の保有数変化では、部分合計を正常値として表示しない。
     */
    void invalidateSample() {
        this.totalKnown = false;
        for (int i = 0; i < 28; i++) {
            this.profitKnown[i] = false;
        }
    }

    /**
     * 登録された通貨・Magicの組だけを対象にする。
     */
    int findSymbolIndex(const string fromSymbol, const ulong fromMagic) {
        for (int i = 0; i < 28; i++) {
            if (this.symbols[i] == fromSymbol && this.magics[i] == fromMagic) {
                return i;
            }
        }
        return -1;
    }

    /**
     * 実保有を1回走査し、同じ取得結果から全体と通貨別の金額を作る。
     * 取得不能は既知の0と区別し、手数料や決済済み損益を合算しない。
     */
    void readSample() {
        this.clearSample(true);
        this.sampleTime = TimeCurrent();
        ResetLastError();
        this.currency = AccountInfoString(ACCOUNT_CURRENCY);
        long currencyDigits = AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS);
        if (GetLastError() != 0 || this.currency == "" || currencyDigits < 0 || currencyDigits > 16) {
            this.invalidateSample();
            return;
        }
        this.digits = (int)currencyDigits;
        int positions = PositionsTotal();
        for (int i = 0; i < positions; i++) {
            string symbol = "";
            long magic = 0;
            if (PositionGetTicket(i) == 0 || !PositionGetString(POSITION_SYMBOL, symbol)
                    || !PositionGetInteger(POSITION_MAGIC, magic)) {
                this.invalidateSample();
                continue;
            }
            int symbolIndex = this.findSymbolIndex(symbol, (ulong)magic);
            if (symbolIndex < 0) {
                continue;
            }
            this.positionCounts[symbolIndex]++;
            this.totalPositions++;
            double profit = 0.0;
            double swap = 0.0;
            if (!PositionGetDouble(POSITION_PROFIT, profit) || !PositionGetDouble(POSITION_SWAP, swap)
                    || !MathIsValidNumber(profit) || !MathIsValidNumber(swap)
                    || !MathIsValidNumber(profit + swap)) {
                this.profitKnown[symbolIndex] = false;
                this.totalKnown = false;
                continue;
            }
            this.profits[symbolIndex] += profit + swap;
            this.totalProfit += profit + swap;
            if (!MathIsValidNumber(this.profits[symbolIndex]) || !MathIsValidNumber(this.totalProfit)) {
                this.profitKnown[symbolIndex] = false;
                this.totalKnown = false;
            }
        }
        if (PositionsTotal() != positions) {
            this.invalidateSample();
        }
    }
};

#endif
