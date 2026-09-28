#ifndef MSTNGH1EA_ANALYSIS_RESULTRECORDER_MQH
#define MSTNGH1EA_ANALYSIS_RESULTRECORDER_MQH

#include <Mstng\Database\Entity\H1EaRunEntity.mqh>
#include <Mstng\Database\H1EaDatabaseContext.mqh>
#include <Mstng\Log\Logger.mqh>
#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>

/**
 * TESTERの28 Runを一つの結果として記録する。売買・判定・CSVには関与しない。
 * 専用接続はロック待機を行わず、欠落が一度でも生じた結果を完了扱いにしない。
 */
class H1EaResultRecorder {
public:
    /**
     * DBへ接続せず未使用状態にする。
     */
    H1EaResultRecorder() {
        this.active = false;
        this.sessionInserted = false;
        this.failed = false;
        this.onTesterReached = false;
        this.statisticsAvailable = false;
        this.dealsComplete = false;
        this.sequence = 0;
        this.lastObservedTime = 0;
        this.lastSavedTime = 0;
        this.nextFailureRetryTime = 0;
        this.errorText = "";
        this.positionState = "";
        this.logger.setSymbolNameAndTimeFrame(_Symbol, PERIOD_H1);
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 自分の接続だけを閉じる。終端状態は明示的なclose()で確定する。
     */
    ~H1EaResultRecorder() {
        this.database.close();
    }

    /**
     * CSV設定と独立して、同じsessionの28 Runだけを記録対象にする。
     * DB障害はログと結果状態へ残し、EAの開始・売買を停止しない。
     */
    void initialize(const H1EaRunEntity &fromRuns[], const datetime fromTradeStart) {
        if (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION) || this.active) {
            return;
        }
        if (ArraySize(fromRuns) != 28 || !H1EaSql::isHash(fromRuns[0].sessionUid)) {
            this.fail("RESULT_RUNS_INVALID");
            return;
        }
        this.sessionUid = fromRuns[0].sessionUid;
        this.programVersion = fromRuns[0].programVersion;
        this.runIds = "";
        for (int i = 0; i < 28; i++) {
            if (fromRuns[i].id <= 0 || fromRuns[i].sourceMode != "TESTER"
                    || fromRuns[i].sessionUid != this.sessionUid || fromRuns[i].symbolName == ""
                    || fromRuns[i].programVersion != this.programVersion
                    || H1EaTextUtil::parseTicket(fromRuns[i].magicNumber) == 0) {
                this.fail("RESULT_RUN_SCOPE_INVALID");
                return;
            }
            for (int j = 0; j < i; j++) {
                if (fromRuns[j].id == fromRuns[i].id || fromRuns[j].symbolName == fromRuns[i].symbolName) {
                    this.fail("RESULT_RUN_DUPLICATE");
                    return;
                }
            }
            this.symbols[i] = fromRuns[i].symbolName;
            this.magics[i] = H1EaTextUtil::parseTicket(fromRuns[i].magicNumber);
            if (i > 0) {
                this.runIds += ",";
            }
            this.runIds += IntegerToString(fromRuns[i].id);
        }
        this.tradeStart = fromTradeStart;
        this.startedTime = TimeCurrent();
        ResetLastError();
        this.initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        this.accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
        this.accountServer = AccountInfoString(ACCOUNT_SERVER);
        this.leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
        if (GetLastError() != 0 || !this.isMeasurementValid(this.initialBalance)
                || this.accountCurrency == "" || this.accountServer == "" || this.leverage <= 0) {
            // 必須の口座情報を取得できない場合は、0や空文字でsessionを作らない。
            this.fail("RESULT_ACCOUNT_INVALID");
            return;
        }
        this.active = true;
        if (!this.ensureSession()) {
            this.fail("RESULT_SESSION_OPEN_FAILED");
            return;
        }
        this.logger.info(__FUNCTION__, "RESULT_RECORDING session=" + this.sessionUid + " interval=60");
        this.sample();
    }

    /**
     * 売買処理後に観測する。通常は秒内の重複読取を避け、約定通知時だけ再確認する。
     * 売買開始後の初回、保有数量・ID変更、1分間隔、および終了時に保存する。
     */
    void sample(const bool fromTradeEvent = false, const bool fromEnd = false) {
        if (!this.active || this.onTesterReached) {
            return;
        }
        datetime now = TimeCurrent();
        if (this.failed) {
            this.retryFailureState(now, fromEnd);
            return;
        }
        if (now < this.tradeStart || (!fromTradeEvent && !fromEnd && now <= this.lastObservedTime)) {
            return;
        }
        this.lastObservedTime = now;
        string identities[];
        int positions = 0;
        int pendingOrders = 0;
        int foreignPositions = 0;
        int foreignOrders = 0;
        double openProfit = 0.0;
        ResetLastError();
        int positionTotal = PositionsTotal();
        for (int i = 0; i < positionTotal; i++) {
            ulong ticket = PositionGetTicket(i);
            if (ticket == 0) {
                this.fail("RESULT_POSITION_READ_FAILED");
                return;
            }
            string symbol = PositionGetString(POSITION_SYMBOL);
            ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
            ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
            double volume = PositionGetDouble(POSITION_VOLUME);
            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            if (!this.isMeasurementValid(volume) || !this.isMeasurementValid(profit) || volume <= 0.0) {
                this.fail("RESULT_POSITION_VALUE_INVALID");
                return;
            }
            if (!this.addIdentity(identities, "P:" + H1EaTextUtil::ticket(identifier) + ":"
                    + H1EaTextUtil::ticket(ticket) + ":" + DoubleToString(volume, 8))) {
                this.fail("RESULT_SAMPLE_ALLOCATION_FAILED");
                return;
            }
            if (this.owns(symbol, magic)) {
                positions++;
                openProfit += profit;
            } else {
                foreignPositions++;
            }
        }
        int orderTotal = OrdersTotal();
        for (int i = 0; i < orderTotal; i++) {
            ulong ticket = OrderGetTicket(i);
            if (ticket == 0) {
                this.fail("RESULT_ORDER_READ_FAILED");
                return;
            }
            string symbol = OrderGetString(ORDER_SYMBOL);
            ulong magic = (ulong)OrderGetInteger(ORDER_MAGIC);
            double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
            if (!this.isMeasurementValid(volume) || volume < 0.0) {
                this.fail("RESULT_ORDER_VALUE_INVALID");
                return;
            }
            if (!this.addIdentity(identities, "O:" + H1EaTextUtil::ticket(ticket) + ":" + DoubleToString(volume, 8))) {
                this.fail("RESULT_SAMPLE_ALLOCATION_FAILED");
                return;
            }
            if (this.owns(symbol, magic)) {
                pendingOrders++;
            } else {
                foreignOrders++;
            }
        }
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double margin = AccountInfoDouble(ACCOUNT_MARGIN);
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        if (GetLastError() != 0 || !this.isMeasurementValid(balance) || !this.isMeasurementValid(equity)
                || !this.isMeasurementValid(margin) || !this.isMeasurementValid(freeMargin)
                || !this.isMeasurementValid(marginLevel) || !this.isMeasurementValid(openProfit)
                || positionTotal != PositionsTotal() || orderTotal != OrdersTotal()) {
            this.fail("RESULT_ACCOUNT_SAMPLE_INVALID");
            return;
        }
        string state = this.joinIdentities(identities);
        string reason = "INTERVAL";
        if (this.sequence == 0) {
            reason = "START";
        } else if (state != this.positionState) {
            reason = "POSITION_CHANGE";
        } else if (!fromEnd && now < this.lastSavedTime + 60) {
            return;
        }
        if (fromEnd) {
            reason = "END";
        }
        string sql = "INSERT INTO h1_ea_account_samples(session_uid,sequence,server_time,reason,"
            + "balance,equity,margin,free_margin,margin_level,open_profit,positions,pending_orders,foreign_positions,foreign_orders) VALUES("
            + H1EaSql::text(this.sessionUid) + "," + IntegerToString(this.sequence + 1) + ","
            + IntegerToString(now) + "," + H1EaSql::text(reason) + ","
            + H1EaSql::real(balance) + "," + H1EaSql::real(equity) + "," + H1EaSql::real(margin) + ","
            + H1EaSql::real(freeMargin) + "," + H1EaSql::real(marginLevel) + "," + H1EaSql::real(openProfit) + ","
            + IntegerToString(positions) + "," + IntegerToString(pendingOrders) + ","
            + IntegerToString(foreignPositions) + "," + IntegerToString(foreignOrders) + ")";
        if (!H1EaSql::execute(this.database.getHandle(), sql)) {
            this.fail("RESULT_SAMPLE_SAVE_FAILED");
            return;
        }
        this.sequence++;
        this.lastSavedTime = now;
        this.positionState = state;
    }

    /**
     * OnTester到達の事実、標準統計と対象EAの全約定を保存する。
     * 指定した予定期間の完走を意味せず、ここではRECORDEDへ変更しない。
     */
    void finish() {
        if (!this.active || this.onTesterReached || !MQLInfoInteger(MQL_TESTER)) {
            return;
        }
        this.sample(true, true);
        this.onTesterReached = true;
        if (!this.ensureSession()) {
            this.fail("RESULT_FINISH_SESSION_UNAVAILABLE");
            return;
        }
        this.saveStatistics();
        this.saveDeals();
    }

    /**
     * 子Controller.shutdown後に監査を読み直し、記録完了・中断・失敗を確定する。
     */
    void close(const int fromReason) {
        if (!this.active) {
            this.database.close();
            return;
        }
        if (!this.onTesterReached) {
            this.sample(true, true);
        }
        if (!this.ensureSession()) {
            this.fail("RESULT_CLOSE_SESSION_UNAVAILABLE");
            this.database.close();
            this.active = false;
            return;
        }
        string state = "INTERRUPTED";
        if (fromReason == REASON_INITFAILED) {
            this.fail("RESULT_INITIALIZATION_FAILED");
        }
        if (!this.failed && !this.isFinalAuditComplete()) {
            this.fail("RESULT_FINAL_AUDIT_INCOMPLETE");
        }
        if (this.onTesterReached && !this.failed) {
            if (!this.statisticsAvailable || !this.dealsComplete) {
                this.fail("RESULT_FINAL_DATA_INCOMPLETE");
            } else {
                state = "RECORDED";
            }
        }
        if (this.failed) {
            state = "FAILED";
        }
        string sql = "UPDATE h1_ea_sessions SET recording_state=" + H1EaSql::text(state)
            + ",ended_server_time=" + IntegerToString(TimeCurrent())
            + ",finished_at=" + IntegerToString((long)TimeLocal())
            + ",error_text=" + H1EaSql::optionalText(this.errorText)
            + " WHERE session_uid=" + H1EaSql::text(this.sessionUid);
        if (!this.updateSession(sql)) {
            this.fail("RESULT_TERMINAL_STATE_SAVE_FAILED");
        } else {
            this.logger.info(__FUNCTION__, "RESULT_" + state + " session=" + this.sessionUid
                + " samples=" + IntegerToString(this.sequence));
        }
        this.database.close();
        this.active = false;
    }

private:
    /** 結果記録専用の一接続。 */
    H1EaDatabaseContext database;
    /** 観測を開始したか。 */
    bool active;
    /** session行の保存を確認したか。 */
    bool sessionInserted;
    /** 一度でも欠落・保存障害が発生したか。 */
    bool failed;
    /** OnTesterに到達したか。期間完走の保証ではない。 */
    bool onTesterReached;
    /** 標準統計の保存を確認したか。 */
    bool statisticsAvailable;
    /** 対象全約定の保存を確認したか。 */
    bool dealsComplete;
    /** 28 Run共通ID。 */
    string sessionUid;
    /** 今回の28 Run IDをSQL整数リストで保持する。 */
    string runIds;
    /** 対象通貨。 */
    string symbols[28];
    /** 対象通貨に対応するMagic。 */
    ulong magics[28];
    /** Runに記録したプログラム版。 */
    string programVersion;
    /** 口座通貨。 */
    string accountCurrency;
    /** 口座サーバー。 */
    string accountServer;
    /** 口座レバレッジ。 */
    long leverage;
    /** 起動時口座残高。 */
    double initialBalance;
    /** 起動時サーバー時刻。 */
    datetime startedTime;
    /** 売買開始時刻。 */
    datetime tradeStart;
    /** 保存済みサンプルの連番。 */
    long sequence;
    /** 最終観測時刻。 */
    datetime lastObservedTime;
    /** 最終保存時刻。 */
    datetime lastSavedTime;
    /** 障害状態の再保存を許可する次の時刻。 */
    datetime nextFailureRetryTime;
    /** 直近の保有・注文のIDと数量。 */
    string positionState;
    /** 最初の障害理由。 */
    string errorText;
    /** 通常形式の診断ログ。 */
    Logger logger;

    /**
     * 既存schemaへロック待機なしで接続し、今回のsessionだけを挿入する。
     */
    bool ensureSession() {
        if (this.database.getHandle() == INVALID_HANDLE
                && !this.database.open("mstng-h1-ea-tester.sqlite", false, 0)) {
            return false;
        }
        if (this.sessionInserted) {
            return true;
        }
        string state = "RECORDING";
        if (this.failed) {
            state = "FAILED";
        }
        string sql = "INSERT INTO h1_ea_sessions(session_uid,source_mode,account_currency,account_server,"
            + "leverage,program_version,started_server_time,trade_start_time,initial_balance,sample_interval_seconds,"
            + "recording_state,statistics_available,deals_complete,error_text,recorded_at) VALUES("
            + H1EaSql::text(this.sessionUid) + ",'TESTER'," + H1EaSql::text(this.accountCurrency) + ","
            + H1EaSql::text(this.accountServer) + "," + IntegerToString(this.leverage) + ","
            + H1EaSql::text(this.programVersion) + "," + IntegerToString(this.startedTime) + ","
            + IntegerToString(this.tradeStart) + "," + H1EaSql::real(this.initialBalance) + ",60,"
            + H1EaSql::text(state) + ",0,0," + H1EaSql::optionalText(this.errorText) + ","
            + IntegerToString((long)TimeLocal()) + ")";
        if (!H1EaSql::execute(this.database.getHandle(), sql)) {
            return false;
        }
        this.sessionInserted = true;
        return true;
    }

    /**
     * 未取得値のEMPTY_VALUEを、有効な0や有限の測定値と区別する。
     */
    bool isMeasurementValid(const double fromValue) {
        return MathIsValidNumber(fromValue) && fromValue != EMPTY_VALUE;
    }

    /**
     * session一行だけが更新されたことを確認する。
     */
    bool updateSession(const string fromSql) {
        long changed = 0;
        return H1EaSql::execute(this.database.getHandle(), fromSql)
            && H1EaSql::scalar(this.database.getHandle(), "SELECT changes()", changed) && changed == 1;
    }

    /**
     * 最初の障害を保持し、結果記録だけを不完全状態にする。
     */
    void fail(const string fromError) {
        if (!this.failed) {
            this.errorText = fromError;
            this.logger.error(__FUNCTION__, fromError + " session=" + this.sessionUid);
        }
        this.failed = true;
        this.retryFailureState(TimeCurrent(), true);
    }

    /**
     * 失敗状態の保存だけを1分に一度試す。Sleep・繰り返し待機はしない。
     */
    void retryFailureState(const datetime fromNow, const bool fromForce) {
        if (!this.active || (!fromForce && fromNow < this.nextFailureRetryTime)) {
            return;
        }
        this.nextFailureRetryTime = fromNow + 60;
        if (this.ensureSession()) {
            this.updateSession("UPDATE h1_ea_sessions SET recording_state='FAILED',error_text="
                + H1EaSql::text(this.errorText) + " WHERE session_uid=" + H1EaSql::text(this.sessionUid));
        }
    }

    /**
     * 通貨とMagicの組み合わせが対象EAに属するか判定する。
     */
    bool owns(const string fromSymbol, const ulong fromMagic) {
        for (int i = 0; i < 28; i++) {
            if (this.symbols[i] == fromSymbol && this.magics[i] == fromMagic) {
                return true;
            }
        }
        return false;
    }

    /**
     * 列挙順の変化で誤検出しないよう、IDと数量を文字順へ挿入する。
     */
    bool addIdentity(string &fromValues[], const string fromValue) {
        int size = ArraySize(fromValues);
        if (ArrayResize(fromValues, size + 1) != size + 1) {
            return false;
        }
        int index = size;
        while (index > 0 && StringCompare(fromValues[index - 1], fromValue) > 0) {
            fromValues[index] = fromValues[index - 1];
            index--;
        }
        fromValues[index] = fromValue;
        return true;
    }

    /**
     * 比較用の状態文字列を作成する。
     */
    string joinIdentities(const string &fromValues[]) {
        string result = "";
        for (int i = 0; i < ArraySize(fromValues); i++) {
            result += fromValues[i] + "|";
        }
        return result;
    }

    /**
     * OnTester専用の標準統計を読み、未取得値を0に置き換えず保存する。
     */
    void saveStatistics() {
        ResetLastError();
        double initialDeposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
        double netProfit = TesterStatistics(STAT_PROFIT);
        double equityDrawdown = TesterStatistics(STAT_EQUITY_DD);
        double equityDrawdownPercent = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
        double trades = TesterStatistics(STAT_TRADES);
        if (GetLastError() != 0 || !this.isMeasurementValid(initialDeposit) || !this.isMeasurementValid(netProfit)
                || !this.isMeasurementValid(equityDrawdown) || !this.isMeasurementValid(equityDrawdownPercent)
                || !this.isMeasurementValid(trades) || initialDeposit < 0.0 || equityDrawdown < 0.0
                || equityDrawdownPercent < 0.0 || trades < 0.0 || trades != MathFloor(trades)) {
            this.fail("RESULT_STATISTICS_INVALID");
            return;
        }
        string sql = "UPDATE h1_ea_sessions SET statistics_available=1,initial_deposit="
            + H1EaSql::real(initialDeposit) + ",net_profit=" + H1EaSql::real(netProfit)
            + ",equity_drawdown=" + H1EaSql::real(equityDrawdown)
            + ",equity_drawdown_percent=" + H1EaSql::real(equityDrawdownPercent)
            + ",mt5_trades=" + IntegerToString((long)trades)
            + " WHERE session_uid=" + H1EaSql::text(this.sessionUid);
        if (!this.updateSession(sql)) {
            this.fail("RESULT_STATISTICS_SAVE_FAILED");
            return;
        }
        this.statisticsAvailable = true;
    }

    /**
     * Position ID一覧への重複なし追加。符号なしIDを維持する。
     */
    bool addPositionId(ulong &fromIds[], const ulong fromId) {
        if (fromId == 0 || this.containsPositionId(fromIds, fromId)) {
            return true;
        }
        int size = ArraySize(fromIds);
        if (ArrayResize(fromIds, size + 1) != size + 1) {
            return false;
        }
        fromIds[size] = fromId;
        return true;
    }

    /**
     * Magicが異なる決済でも、所有が確認済みのPosition IDなら同じ取引とする。
     */
    bool containsPositionId(const ulong &fromIds[], const ulong fromId) {
        if (fromId == 0) {
            return false;
        }
        for (int i = 0; i < ArraySize(fromIds); i++) {
            if (fromIds[i] == fromId) {
                return true;
            }
        }
        return false;
    }

    /**
     * 対象EAのPosition IDを先に特定して、部分約定・SL決済を含む全明細を保存する。
     * 一括保存とdeals_completeを同じtransactionで確定する。
     */
    void saveDeals() {
        if (!HistorySelect(0, TimeCurrent())) {
            this.fail("RESULT_HISTORY_SELECT_FAILED");
            return;
        }
        ulong positionIds[];
        ResetLastError();
        int total = HistoryDealsTotal();
        if (GetLastError() != 0 || total < 0) {
            this.fail("RESULT_HISTORY_COUNT_FAILED");
            return;
        }
        for (int i = 0; i < total; i++) {
            ulong ticket = HistoryDealGetTicket(i);
            ResetLastError();
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            ulong magic = (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC);
            ulong identifier = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
            if (ticket == 0 || GetLastError() != 0) {
                this.fail("RESULT_HISTORY_SCOPE_FAILED");
                return;
            }
            if (this.owns(symbol, magic) && !this.addPositionId(positionIds, identifier)) {
                this.fail("RESULT_DEAL_ALLOCATION_FAILED");
                return;
            }
        }
        int handle = this.database.getHandle();
        if (!H1EaSql::execute(handle, "BEGIN IMMEDIATE")) {
            this.fail("RESULT_DEALS_BEGIN_FAILED");
            return;
        }
        bool success = true;
        long savedDeals = 0;
        for (int i = 0; i < total; i++) {
            ulong ticket = HistoryDealGetTicket(i);
            ResetLastError();
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            ulong magic = (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC);
            ulong identifier = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
            if (ticket == 0 || GetLastError() != 0) {
                success = false;
                break;
            }
            if (!this.owns(symbol, magic) && !this.containsPositionId(positionIds, identifier)) {
                continue;
            }
            if (!this.saveDeal(ticket, identifier, symbol, magic)) {
                success = false;
                break;
            }
            savedDeals++;
        }
        long storedDeals = -1;
        ResetLastError();
        int finalTotal = HistoryDealsTotal();
        bool historyCountValid = GetLastError() == 0 && finalTotal == total;
        success = success && historyCountValid
            && H1EaSql::scalar(handle, "SELECT COUNT(*) FROM h1_ea_deals WHERE session_uid="
                + H1EaSql::text(this.sessionUid), storedDeals) && storedDeals == savedDeals;
        if (success) {
            success = this.updateSession("UPDATE h1_ea_sessions SET deals_complete=1 WHERE session_uid="
                + H1EaSql::text(this.sessionUid));
        }
        if (success && H1EaSql::execute(handle, "COMMIT")) {
            this.dealsComplete = true;
            return;
        }
        H1EaSql::execute(handle, "ROLLBACK");
        this.fail("RESULT_DEALS_SAVE_FAILED");
    }

    /**
     * 約定の識別子をTEXT、金額・数量を実数として保存する。
     */
    bool saveDeal(const ulong fromTicket, const ulong fromIdentifier,
            const string fromSymbol, const ulong fromMagic) {
        ResetLastError();
        long timeMsc = HistoryDealGetInteger(fromTicket, DEAL_TIME_MSC);
        long dealType = HistoryDealGetInteger(fromTicket, DEAL_TYPE);
        long entryType = HistoryDealGetInteger(fromTicket, DEAL_ENTRY);
        long reason = HistoryDealGetInteger(fromTicket, DEAL_REASON);
        double volume = HistoryDealGetDouble(fromTicket, DEAL_VOLUME);
        double price = HistoryDealGetDouble(fromTicket, DEAL_PRICE);
        double profit = HistoryDealGetDouble(fromTicket, DEAL_PROFIT);
        double commission = HistoryDealGetDouble(fromTicket, DEAL_COMMISSION);
        double swap = HistoryDealGetDouble(fromTicket, DEAL_SWAP);
        double fee = HistoryDealGetDouble(fromTicket, DEAL_FEE);
        if (GetLastError() != 0 || timeMsc <= 0 || !this.isMeasurementValid(volume) || !this.isMeasurementValid(price)
                || !this.isMeasurementValid(profit) || !this.isMeasurementValid(commission) || !this.isMeasurementValid(swap)
                || !this.isMeasurementValid(fee)) {
            return false;
        }
        string sql = "INSERT INTO h1_ea_deals(session_uid,ticket,time_msc,position_identifier,symbol,magic_number,"
            + "deal_type,entry_type,volume,price,profit,commission,swap,fee,reason) VALUES("
            + H1EaSql::text(this.sessionUid) + "," + H1EaSql::text(H1EaTextUtil::ticket(fromTicket)) + ","
            + IntegerToString(timeMsc) + "," + H1EaSql::text(H1EaTextUtil::ticket(fromIdentifier)) + ","
            + H1EaSql::text(fromSymbol) + "," + H1EaSql::text(H1EaTextUtil::ticket(fromMagic)) + ","
            + IntegerToString(dealType) + "," + IntegerToString(entryType) + ","
            + H1EaSql::real(volume) + "," + H1EaSql::real(price) + "," + H1EaSql::real(profit) + ","
            + H1EaSql::real(commission) + "," + H1EaSql::real(swap) + "," + H1EaSql::real(fee) + ","
            + IntegerToString(reason) + ")";
        return H1EaSql::execute(this.database.getHandle(), sql);
    }

    /**
     * 全子Runの正常終了と、保存約定に対応する既存DB監査明細の存在を確認する。
     */
    bool isFinalAuditComplete() {
        int handle = this.database.getHandle();
        string scope = "session_uid=" + H1EaSql::text(this.sessionUid);
        long total = 0;
        long stopped = 0;
        long missing = 0;
        if (!H1EaSql::scalar(handle, "SELECT COUNT(*) FROM h1_ea_runs WHERE " + scope, total)
                || total != 28
                || !H1EaSql::scalar(handle, "SELECT COUNT(*) FROM h1_ea_runs WHERE " + scope
                    + " AND id IN (" + this.runIds + ") AND status='STOPPED' AND ended_at IS NOT NULL"
                    + " AND COALESCE(error_text,'')=''", stopped) || stopped != 28) {
            return false;
        }
        // OnTester未到達は約定エクスポート前なので、Runの終了状態だけを確認する。
        if (!this.onTesterReached) {
            return true;
        }
        string sql = "SELECT COUNT(*) FROM h1_ea_deals d WHERE d.session_uid=" + H1EaSql::text(this.sessionUid)
            + " AND d.deal_type IN (0,1) AND NOT EXISTS (SELECT 1 FROM h1_ea_trade_events e"
            + " JOIN h1_ea_trades t ON t.id=e.trade_id JOIN h1_ea_runs r ON r.id=t.created_run_id"
            + " WHERE r.session_uid=d.session_uid AND e.event_type='DEAL_ADD'"
            + " AND e.deal_ticket=d.ticket AND e.position_identifier=d.position_identifier)";
        if (!H1EaSql::scalar(handle, sql, missing) || missing != 0) {
            return false;
        }
        // 保存集合が空または一部欠落した場合も、既存監査側から検出する。
        string reverseSql = "SELECT COUNT(*) FROM h1_ea_trade_events e"
            + " JOIN h1_ea_trades t ON t.id=e.trade_id JOIN h1_ea_runs r ON r.id=t.created_run_id"
            + " WHERE r.session_uid=" + H1EaSql::text(this.sessionUid)
            + " AND e.event_type='DEAL_ADD' AND NOT EXISTS (SELECT 1 FROM h1_ea_deals d"
            + " WHERE d.session_uid=r.session_uid AND d.ticket=e.deal_ticket"
            + " AND d.position_identifier=e.position_identifier AND d.deal_type IN (0,1))";
        return H1EaSql::scalar(handle, reverseSql, missing) && missing == 0;
    }
};

#endif
