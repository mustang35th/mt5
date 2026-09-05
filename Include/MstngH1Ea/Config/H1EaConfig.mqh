#ifndef MSTNGH1EA_CONFIG_CONFIG_MQH
#define MSTNGH1EA_CONFIG_CONFIG_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <MstngEa\Trade\MagicNumberUtil.mqh>
#include <MstngH1Ea\Runtime\H1EaTextUtil.mqh>

/**
 * H1専用EAの固定仕様・取引input・Testerの売買開始日時を管理する。
 */
class H1EaConfig {
public:
    /** 対象シンボル。 */
    string symbolName;
    /** 接続サーバー。 */
    string accountServer;
    /** 口座番号。 */
    long accountLogin;
    /** 自EAの識別番号。 */
    ulong magicNumber;
    /** inputで指定した固定ロット。 */
    double lotSize;
    /** 許容する最大初期SL幅。0は未設定。 */
    double maxInitialStopLossPips;
    /** 価格の最小表示単位。 */
    double pointSize;
    /** 注文価格の最小刻み。 */
    double tickSize;
    /** 1pipの価格。 */
    double pipSize;
    /** 価格の小数桁数。 */
    int digits;
    /** Tester実行か。 */
    bool isTester;
    /** Testerの売買開始日時。0は制限なし。LIVEでは常に0。 */
    datetime testerTradeStartTime;
    /** LIVEまたはTESTER。 */
    string sourceMode;
    /** 再起動ごとの識別子。 */
    string runUid;
    /** 再起動復元用の実行コンテキスト。 */
    string contextKey;
    /** OS排他ハンドルのscope。 */
    string lockScope;
    /** Common内のDBファイル名。 */
    string databaseFileName;
    /** 最後の初期化エラー。 */
    string lastError;

    /**
     * 安全設定と市場の価格単位を検証し、固定設定を組み立てる。
     */
    bool initialize(const string fromSymbol, const double fromLotSize,
            const double fromMaxInitialStopLossPips, const datetime fromTesterTradeStartTime = 0) {
        this.lastError = "";
        this.symbolName = fromSymbol;
        this.lotSize = NormalizeDouble(fromLotSize, 8);
        this.maxInitialStopLossPips = fromMaxInitialStopLossPips;
        this.isTester = (bool)MQLInfoInteger(MQL_TESTER);
        this.testerTradeStartTime = 0;
        this.sourceMode = "LIVE";
        this.databaseFileName = "mstng-h1-ea.sqlite";
        if (this.isTester) {
            this.sourceMode = "TESTER";
            this.databaseFileName = "mstng-h1-ea-tester.sqlite";
            if (fromTesterTradeStartTime < 0) {
                return this.fail("INVALID_TESTER_TRADE_START_TIME");
            }
            this.testerTradeStartTime = fromTesterTradeStartTime;
        }
        if (_Period != PERIOD_H1) {
            return this.fail("H1_CHART_REQUIRED");
        }
        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            return this.fail("OPTIMIZATION_NOT_SUPPORTED");
        }
        if (!MathIsValidNumber(this.lotSize) || this.lotSize <= 0.0) {
            return this.fail("INVALID_LOT_SIZE");
        }
        if (!MathIsValidNumber(this.maxInitialStopLossPips)
                || this.maxInitialStopLossPips <= 0.0) {
            return this.fail("MAX_INITIAL_SL_UNSET: InpMaxInitialStopLossPipsへ正の上限pipsを設定してください");
        }
        if (MathAbs(NormalizeDouble(this.maxInitialStopLossPips, 1)
                - this.maxInitialStopLossPips) > 0.00000001) {
            return this.fail("MAX_INITIAL_SL_REQUIRES_ONE_DECIMAL_PLACE");
        }
        if (AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
            return this.fail("HEDGING_ACCOUNT_REQUIRED");
        }
        this.accountServer = AccountInfoString(ACCOUNT_SERVER);
        this.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        if (this.accountServer == "" || this.accountLogin <= 0 || this.symbolName == ""
                || StringFind(this.accountServer, "|") >= 0
                || StringFind(this.symbolName, "|") >= 0) {
            return this.fail("INVALID_CONTEXT");
        }
        if (!SymbolSelect(this.symbolName, true)) {
            return this.fail("SYMBOL_UNAVAILABLE");
        }
        this.digits = (int)SymbolInfoInteger(this.symbolName, SYMBOL_DIGITS);
        this.pointSize = SymbolInfoDouble(this.symbolName, SYMBOL_POINT);
        this.tickSize = SymbolInfoDouble(this.symbolName, SYMBOL_TRADE_TICK_SIZE);
        this.pipSize = this.pointSize * ZigZagElliotAnalysisProfile::getPipInPoints(this.digits);
        if (!MathIsValidNumber(this.pointSize) || this.pointSize <= 0.0
                || !MathIsValidNumber(this.tickSize) || this.tickSize <= 0.0
                || !MathIsValidNumber(this.pipSize) || this.pipSize <= 0.0) {
            return this.fail("INVALID_PRICE_UNITS");
        }
        MarketContext marketContext(this.symbolName, PERIOD_H1);
        this.magicNumber = MagicNumberUtil::build(12, marketContext, STRATEGY_TYPE_MTF_3IN3);
        string identity = this.accountServer + "|" + IntegerToString(this.accountLogin);
        this.runUid = H1EaTextUtil::hash(this.sourceMode + "|" + identity + "|"
            + IntegerToString(ChartID()) + "|" + IntegerToString(TimeLocal()) + "|"
            + H1EaTextUtil::ticket(GetTickCount64()));
        this.lockScope = this.sourceMode + "|" + identity + "|" + this.symbolName
            + "|H1|" + H1EaTextUtil::ticket(this.magicNumber);
        this.contextKey = "H1_EA_CONTEXT_V1|" + this.sourceMode + "|";
        if (this.isTester) {
            this.contextKey += this.runUid + "|";
        }
        this.contextKey += identity + "|" + this.symbolName + "|H1|"
            + H1EaTextUtil::ticket(this.magicNumber);
        if (StringLen(this.runUid) != 64) {
            return this.fail("HASH_UNAVAILABLE");
        }
        return true;
    }

    /**
     * DBへ保存する実行設定を固定順序・固定桁数で返す。
     */
    string createCanonicalText() const {
        return "H1_EA_CONFIG_V1|LOT_SIZE=" + DoubleToString(this.lotSize, 8)
            + "|MAX_INITIAL_SL_PIPS=" + DoubleToString(this.maxInitialStopLossPips, 1)
            + "|ZIGZAG_SL_BUFFER_PIPS=10.0|MAX_SPREAD_PIPS=5.0|ANALYSIS_START_TIME_FRAME=MN1"
            + "|H1_DIRECTION_ALIGNMENT_MODE=H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED"
            + "|H1_W1_CONFIRMATION_MODE=H1_W1_CONFIRMATION_OBSERVE_ONLY"
            + "|H1_EMA200_CONFIRMATION_MODE=H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED"
            + "|H1_DISPLAY_WAVE_ENTRY_LIMIT_ENABLED=0|CURRENCY_STRENGTH_ENTRY_FILTER_ENABLED=0"
            + "|ENTRY_COUNT=1|LIVE_FIRST_EVALUATION_SECONDS=1|LIVE_EVALUATION_INTERVAL_SECONDS=30"
            + "|TESTER_EVALUATION_TRIGGER=TICK"
            + "|TESTER_TRADE_START_TIME=" + IntegerToString(this.testerTradeStartTime);
    }

    /**
     * Testerの指定日時前だけ新規Entryの評価を止める。
     *
     * @param fromTime テスト内の現在サーバー時刻。
     * @return 開始前のウォームアップ期間の場合true。
     */
    bool isBeforeTesterTradeStart(const datetime fromTime) const {
        return this.isTester && this.testerTradeStartTime > 0
            && fromTime < this.testerTradeStartTime;
    }

    /**
     * プログラム世代を返す。
     */
    static string getProgramVersion() { return "1.05"; }

    /**
     * Entry互換条件とトレイルを含む戦略世代を返す。
     */
    static string getStrategyVersion() { return "H1_MTF3IN3_SPREAD5_ZIGZAG10_V1"; }

private:
    /**
     * 初期化拒否理由を保持する。
     */
    bool fail(const string fromReason) {
        this.lastError = fromReason;
        return false;
    }
};

#endif
