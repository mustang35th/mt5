#ifndef MSTNGH1EA_ANALYSIS_BASELINEREPORT_MQH
#define MSTNGH1EA_ANALYSIS_BASELINEREPORT_MQH

#include <Mstng\Database\Entity\H1EaRunEntity.mqh>
#include <Mstng\Log\Logger.mqh>
#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>

/**
 * 全体上限なしの基準テストを観測する。売買可否・DB・巡回状態を変更しない。
 * サンプルはテスト内1秒間隔、約定履歴はOnTesterで全件出力する。
 */
class H1EaBaselineReport {
public:
    /**
     * ファイルを開かず未使用状態にする。
     */
    H1EaBaselineReport() {
        this.active = false;
        this.finished = false;
        this.failed = false;
        this.samplesHandle = INVALID_HANDLE;
        this.lastSampleTime = 0;
        this.firstSampleTime = 0;
        this.lastWriteTime = 0;
        this.lastFlushTime = 0;
        this.sampleRows = 0;
        this.dealRows = 0;
        this.readErrors = 0;
        this.lastValues = "";
        this.folder = "";
        this.logger.setSymbolNameAndTimeFrame(_Symbol, PERIOD_H1);
        this.logger.setLevel(LOG_INFO);
    }

    /**
     * 異常終了時も自分のファイルハンドルだけを解放する。
     */
    ~H1EaBaselineReport() {
        this.close();
    }

    /**
     * TESTERの28 Runだけを受け入れ、session単位の出力を開始する。
     * 出力失敗は売買停止理由にせず、不完全なレポートとして通知する。
     */
    void initialize(const H1EaRunEntity &fromRuns[], const datetime fromTradeStart) {
        if (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)
                || this.active || ArraySize(fromRuns) != 28) {
            return;
        }
        string session = fromRuns[0].sessionUid;
        if (StringLen(session) != 64) {
            return;
        }
        for (int i = 0; i < 28; i++) {
            if (fromRuns[i].sourceMode != "TESTER" || fromRuns[i].sessionUid != session
                    || fromRuns[i].symbolName == "" || H1EaTextUtil::parseTicket(fromRuns[i].magicNumber) == 0) {
                return;
            }
            this.symbols[i] = fromRuns[i].symbolName;
            this.magics[i] = H1EaTextUtil::parseTicket(fromRuns[i].magicNumber);
        }
        this.tradeStart = fromTradeStart;
        this.testStart = TimeCurrent();
        this.folder = "MstngH1Ea\\Backtests\\" + session;
        FolderCreate("MstngH1Ea", FILE_COMMON);
        FolderCreate("MstngH1Ea\\Backtests", FILE_COMMON);
        FolderCreate(this.folder, FILE_COMMON);
        this.active = true;
        int runsHandle = this.openFile("runs.csv");
        this.writeLine(runsHandle, "symbol,magic,runId,runUid,sessionUid,programVersion,strategyVersion,configHash,configText,analysisInputHash");
        for (int i = 0; i < 28; i++) {
            this.writeLine(runsHandle, this.quote(fromRuns[i].symbolName) + "," + fromRuns[i].magicNumber
                + "," + IntegerToString(fromRuns[i].id) + "," + this.quote(fromRuns[i].runUid)
                + "," + this.quote(session) + "," + this.quote(fromRuns[i].programVersion)
                + "," + this.quote(fromRuns[i].strategyVersion) + "," + this.quote(fromRuns[i].configHash)
                + "," + this.quote(fromRuns[i].configText) + "," + this.quote(fromRuns[i].analysisInputHash));
        }
        this.finishFile(runsHandle);
        this.samplesHandle = this.openFile("samples.csv");
        this.writeLine(this.samplesHandle, "serverTime,positions,pendingOrders,foreignPositions,foreignOrders,balance,equity,margin,freeMargin,marginLevel,openProfit,slRiskKnown,slRiskUnknown,readErrors,currencySlots");
        this.logger.info(__FUNCTION__, "BASELINE_REPORT " + this.folder);
        this.sample();
    }

    /**
     * 売買処理後の状態を最短1秒で読む。同値は60秒ごとの生存記録へ圧縮する。
     * 開始日時前は口座・ポジションを読み取らない。
     */
    void sample(const bool fromForce = false) {
        if (!this.active || this.finished || this.failed) {
            return;
        }
        datetime now = TimeCurrent();
        if (now < this.tradeStart || (!fromForce && now <= this.lastSampleTime)) {
            return;
        }
        this.lastSampleTime = now;
        if (this.firstSampleTime == 0) {
            this.firstSampleTime = now;
        }
        int positions = 0;
        int pendingOrders = 0;
        int foreignPositions = 0;
        int foreignOrders = 0;
        int unknownRisk = 0;
        int errors = 0;
        double openProfit = 0.0;
        double risk = 0.0;
        string currencies[];
        int longSlots[];
        int shortSlots[];
        for (int i = 0; i < PositionsTotal(); i++) {
            if (PositionGetTicket(i) == 0) {
                errors++;
                continue;
            }
            string symbol = PositionGetString(POSITION_SYMBOL);
            if (!this.owns(symbol, (ulong)PositionGetInteger(POSITION_MAGIC))) {
                foreignPositions++;
                continue;
            }
            positions++;
            double volume = PositionGetDouble(POSITION_VOLUME);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double stopLoss = PositionGetDouble(POSITION_SL);
            bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
            ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
            if (!isBuy) {
                orderType = ORDER_TYPE_SELL;
            }
            openProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            double loss = 0.0;
            if (volume <= 0.0 || currentPrice <= 0.0 || stopLoss <= 0.0
                    || !OrderCalcProfit(orderType, symbol, volume, currentPrice, stopLoss, loss)
                    || !MathIsValidNumber(loss)) {
                unknownRisk++;
            } else {
                risk += MathMax(0.0, -loss);
            }
            string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
            string quoteCurrency = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
            if (base == "" || quoteCurrency == "") {
                errors++;
            } else {
                this.addCurrency(base, isBuy, currencies, longSlots, shortSlots);
                this.addCurrency(quoteCurrency, !isBuy, currencies, longSlots, shortSlots);
            }
        }
        for (int i = 0; i < OrdersTotal(); i++) {
            if (OrderGetTicket(i) == 0) {
                errors++;
            } else if (this.owns(OrderGetString(ORDER_SYMBOL), (ulong)OrderGetInteger(ORDER_MAGIC))) {
                pendingOrders++;
            } else {
                foreignOrders++;
            }
        }
        string slots = "";
        for (int i = 0; i < ArraySize(currencies); i++) {
            if (i > 0) {
                slots += "|";
            }
            slots += currencies[i] + ":" + IntegerToString(longSlots[i]) + ":" + IntegerToString(shortSlots[i]);
        }
        string values = IntegerToString(positions) + "," + IntegerToString(pendingOrders)
            + "," + IntegerToString(foreignPositions) + "," + IntegerToString(foreignOrders)
            + "," + this.number(AccountInfoDouble(ACCOUNT_BALANCE))
            + "," + this.number(AccountInfoDouble(ACCOUNT_EQUITY))
            + "," + this.number(AccountInfoDouble(ACCOUNT_MARGIN))
            + "," + this.number(AccountInfoDouble(ACCOUNT_MARGIN_FREE))
            + "," + this.number(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL))
            + "," + this.number(openProfit) + "," + this.number(risk)
            + "," + IntegerToString(unknownRisk) + "," + IntegerToString(errors) + "," + this.quote(slots);
        this.readErrors += errors;
        if (fromForce || values != this.lastValues || now >= this.lastWriteTime + 60) {
            if (this.writeLine(this.samplesHandle, IntegerToString(now) + "," + values)) {
                this.sampleRows++;
            }
            if (now >= this.lastFlushTime + 60 || fromForce) {
                this.flushFile(this.samplesHandle);
                this.lastFlushTime = now;
            }
            this.lastWriteTime = now;
            this.lastValues = values;
        }
    }

    /**
     * OnTesterからだけ呼び、全約定とMT5標準成績を保存する。最適化基準には使わない。
     */
    void finish() {
        if (!this.active || this.finished || !MQLInfoInteger(MQL_TESTER)) {
            return;
        }
        this.sample(true);
        this.finishFile(this.samplesHandle);
        this.samplesHandle = INVALID_HANDLE;
        this.exportDeals();
        int summaryHandle = this.openFile("summary.csv");
        this.writeLine(summaryHandle, "key,value");
        this.writePair(summaryHandle, "schema", "H1_EA_BASELINE_V1");
        this.writePair(summaryHandle, "finalization", "ONTESTER");
        this.writePair(summaryHandle, "globalPositionLimit", "0");
        this.writePair(summaryHandle, "accountCurrency", AccountInfoString(ACCOUNT_CURRENCY));
        this.writePair(summaryHandle, "accountServer", AccountInfoString(ACCOUNT_SERVER));
        this.writePair(summaryHandle, "leverage", IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)));
        this.writePair(summaryHandle, "terminalBuild", IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
        this.writePair(summaryHandle, "chartSymbol", _Symbol);
        this.writePair(summaryHandle, "testStart", IntegerToString(this.testStart));
        this.writePair(summaryHandle, "tradeStart", IntegerToString(this.tradeStart));
        this.writePair(summaryHandle, "firstSampleTime", IntegerToString(this.firstSampleTime));
        this.writePair(summaryHandle, "testEnd", IntegerToString(TimeCurrent()));
        this.writePair(summaryHandle, "sampleRows", IntegerToString(this.sampleRows));
        this.writePair(summaryHandle, "dealRows", IntegerToString(this.dealRows));
        this.writePair(summaryHandle, "readErrors", IntegerToString(this.readErrors));
        this.writePair(summaryHandle, "initialDeposit", this.number(TesterStatistics(STAT_INITIAL_DEPOSIT)));
        this.writePair(summaryHandle, "netProfit", this.number(TesterStatistics(STAT_PROFIT)));
        this.writePair(summaryHandle, "equityDrawdown", this.number(TesterStatistics(STAT_EQUITY_DD)));
        this.writePair(summaryHandle, "equityDrawdownPercent", this.number(TesterStatistics(STAT_EQUITY_DDREL_PERCENT)));
        this.writePair(summaryHandle, "trades", this.number(TesterStatistics(STAT_TRADES)));
        this.writePair(summaryHandle, "ioFailed", IntegerToString((int)this.failed));
        this.finishFile(summaryHandle);
        this.finished = true;
        if (!this.failed) {
            int statusHandle = this.openFile("status.csv");
            this.writeLine(statusHandle, "key,value");
            this.writePair(statusHandle, "exportState", "EXPORTED");
            this.finishFile(statusHandle);
            if (!this.failed) {
                this.logger.info(__FUNCTION__, "BASELINE_EXPORTED " + this.folder);
            }
        }
    }

    /**
     * OnTester未到達の終了では標準成績を捏造せず、途中サンプルだけを閉じる。
     */
    void close() {
        if (this.samplesHandle != INVALID_HANDLE) {
            this.finishFile(this.samplesHandle);
            this.samplesHandle = INVALID_HANDLE;
        }
        this.active = false;
    }

private:
    /** 出力を開始したか。 */
    bool active;
    /** OnTesterの出力が終了したか。 */
    bool finished;
    /** 一度でも入出力に失敗したか。 */
    bool failed;
    /** Common配下のsession固有フォルダ。 */
    string folder;
    /** 登録済み28通貨。 */
    string symbols[28];
    /** 通貨に対応するMagic。 */
    ulong magics[28];
    /** 売買開始日時。 */
    datetime tradeStart;
    /** 初期化時のサーバー時刻。 */
    datetime testStart;
    /** 最初に観測できた時刻。 */
    datetime firstSampleTime;
    /** 最後に読み取った時刻。 */
    datetime lastSampleTime;
    /** 最後に出力した時刻。 */
    datetime lastWriteTime;
    /** 最後にバッファを確定した時刻。 */
    datetime lastFlushTime;
    /** 出力済み行数。 */
    long sampleRows;
    /** 出力済み約定数。切れたCSVを集計しないための件数。 */
    long dealRows;
    /** 読取失敗の累積。 */
    long readErrors;
    /** 同値圧縮用の前回データ。 */
    string lastValues;
    /** 連続サンプルのファイル。 */
    int samplesHandle;
    /** 通常形式の診断ログ。 */
    Logger logger;

    /**
     * 通貨とMagicが同じ登録だけを自EAに帰属させる。
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
     * 通貨の買い・売り側ポジション件数を加算する。金額エクスポージャーではない。
     */
    void addCurrency(const string fromCurrency, const bool fromLong, string &fromCurrencies[],
            int &fromLongSlots[], int &fromShortSlots[]) {
        int index = -1;
        for (int i = 0; i < ArraySize(fromCurrencies); i++) {
            if (fromCurrencies[i] == fromCurrency) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            index = ArraySize(fromCurrencies);
            ArrayResize(fromCurrencies, index + 1);
            ArrayResize(fromLongSlots, index + 1);
            ArrayResize(fromShortSlots, index + 1);
            fromCurrencies[index] = fromCurrency;
            fromLongSlots[index] = 0;
            fromShortSlots[index] = 0;
        }
        if (fromLong) {
            fromLongSlots[index]++;
        } else {
            fromShortSlots[index]++;
        }
    }

    /**
     * 全約定を残す。Magicの異なるSL決済もposition IDで後から突合できる。
     */
    void exportDeals() {
        if (!HistorySelect(0, TimeCurrent())) {
            this.fail("HISTORY_SELECT_FAILED");
            return;
        }
        int handle = this.openFile("deals.csv");
        this.writeLine(handle, "ticket,timeMsc,positionId,symbol,magic,type,entry,volume,profit,commission,swap,fee");
        for (int i = 0; i < HistoryDealsTotal(); i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if (ticket == 0) {
                this.fail("HISTORY_DEAL_FAILED");
                break;
            }
            ResetLastError();
            string row = H1EaTextUtil::ticket(ticket)
                + "," + IntegerToString(HistoryDealGetInteger(ticket, DEAL_TIME_MSC))
                + "," + H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID))
                + "," + this.quote(HistoryDealGetString(ticket, DEAL_SYMBOL))
                + "," + H1EaTextUtil::ticket((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC))
                + "," + IntegerToString(HistoryDealGetInteger(ticket, DEAL_TYPE))
                + "," + IntegerToString(HistoryDealGetInteger(ticket, DEAL_ENTRY))
                + "," + DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 8)
                + "," + this.number(HistoryDealGetDouble(ticket, DEAL_PROFIT))
                + "," + this.number(HistoryDealGetDouble(ticket, DEAL_COMMISSION))
                + "," + this.number(HistoryDealGetDouble(ticket, DEAL_SWAP))
                + "," + this.number(HistoryDealGetDouble(ticket, DEAL_FEE));
            if (GetLastError() != 0) {
                this.fail("HISTORY_PROPERTY_FAILED");
                break;
            }
            if (!this.writeLine(handle, row)) {
                break;
            }
            this.dealRows++;
        }
        this.finishFile(handle);
    }

    /**
     * セッション内のUTF-8 CSVを開く。
     */
    int openFile(const string fromName) {
        int handle = FileOpen(this.folder + "\\" + fromName,
            FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, 0, CP_UTF8);
        if (handle == INVALID_HANDLE) {
            this.fail("FILE_OPEN_FAILED: " + fromName);
        }
        return handle;
    }

    /**
     * 文字列列は常に引用し、カンマ・改行・引用符を保持する。
     */
    string quote(string fromText) {
        StringReplace(fromText, "\"", "\"\"");
        return "\"" + fromText + "\"";
    }

    /**
     * 金額は8桁で出力する。不正値は空欄にして0と区別する。
     */
    string number(const double fromValue) {
        if (!MathIsValidNumber(fromValue)) {
            this.readErrors++;
            return "";
        }
        return DoubleToString(fromValue, 8);
    }

    /**
     * 1行を出力する。失敗を記録し、呼出元の売買には影響させない。
     */
    bool writeLine(const int fromHandle, const string fromLine) {
        ResetLastError();
        if (fromHandle == INVALID_HANDLE || FileWriteString(fromHandle, fromLine + "\r\n") == 0) {
            this.fail("FILE_WRITE_FAILED");
            return false;
        }
        if (GetLastError() != 0) {
            this.fail("FILE_WRITE_ERROR");
            return false;
        }
        return true;
    }

    /**
     * 成績表のキーと値を2列で出力する。
     */
    void writePair(const int fromHandle, const string fromKey, const string fromValue) {
        this.writeLine(fromHandle, this.quote(fromKey) + "," + this.quote(fromValue));
    }

    /**
     * バッファ書込の失敗も結果の欠落として扱う。
     */
    void flushFile(const int fromHandle) {
        if (fromHandle == INVALID_HANDLE) {
            return;
        }
        ResetLastError();
        FileFlush(fromHandle);
        if (GetLastError() != 0) {
            this.fail("FILE_FLUSH_FAILED");
        }
    }

    /**
     * ファイルを確実に閉じる。
     */
    void finishFile(const int fromHandle) {
        if (fromHandle != INVALID_HANDLE) {
            this.flushFile(fromHandle);
            FileClose(fromHandle);
        }
    }

    /**
     * エラーを一度だけ通知し、正常レポートとして扱わせない。
     */
    void fail(const string fromReason) {
        if (!this.failed) {
            this.logger.error(__FUNCTION__, "BASELINE_INCOMPLETE " + fromReason + " " + this.folder);
        }
        this.failed = true;
    }
};

#endif
