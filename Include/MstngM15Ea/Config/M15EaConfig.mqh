#ifndef MSTNGM15EA_CONFIG_CONFIG_MQH
#define MSTNGM15EA_CONFIG_CONFIG_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3H1Policy.mqh>
#include <MstngEa\Trade\MagicNumberUtil.mqh>
#include <MstngEaCommon\Runtime\EaTextUtil.mqh>

/**
 * M15単一通貨EAの設定と、H1から分離した保存・管理識別子を保持する。
 */
class M15EaConfig {
public:
    /** 対象シンボル。 */
    string symbolName;

    /** 接続サーバー。 */
    string accountServer;

    /** 口座番号。 */
    long accountLogin;

    /** 自EAの識別番号。 */
    ulong magicNumber;

    /** 固定ロット。 */
    double lotSize;

    /** 許容する最大初期SL幅。 */
    double maxInitialStopLossPips;

    /** 価格の最小表示単位。 */
    double pointSize;

    /** 注文価格の最小刻み。 */
    double tickSize;

    /** 1pipの価格幅。 */
    double pipSize;

    /** 価格の小数桁数。 */
    int digits;

    /** Tester実行の場合true。 */
    bool isTester;

    /** Tester売買開始日時。LIVEは0。 */
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

    /** D1・H4・H1の片足方向補正を使用する場合true。 */
    bool directionCorrectionEnabled;

    /** H4のFE上限。0は無効。 */
    double h4MaxFibonacciExpansionPercent;

    /** H1のFE上限。0は無効。 */
    double h1MaxFibonacciExpansionPercent;

    /**
     * 通常版ZigZagElliotと同じM15判定設定を初期値にする。
     */
    M15EaConfig() {
        this.symbolName = "";
        this.accountServer = "";
        this.accountLogin = 0;
        this.magicNumber = 0;
        this.lotSize = 0.01;
        this.maxInitialStopLossPips = 100.0;
        this.pointSize = 0.0;
        this.tickSize = 0.0;
        this.pipSize = 0.0;
        this.digits = 0;
        this.isTester = false;
        this.testerTradeStartTime = 0;
        this.sourceMode = "LIVE";
        this.runUid = "";
        this.contextKey = "";
        this.lockScope = "";
        this.databaseFileName = "mstng-m15-ea.sqlite";
        this.lastError = "";
        this.directionCorrectionEnabled = true;
        this.h4MaxFibonacciExpansionPercent = 161.8;
        this.h1MaxFibonacciExpansionPercent = 161.8;
    }

    /**
     * 設定・口座・価格単位を検証し、M15専用の保存識別子を生成する。
     */
    bool initialize(const string fromSymbol, const double fromLotSize,
            const double fromMaxInitialStopLossPips, const datetime fromTesterTradeStartTime = 0,
            const bool fromDirectionCorrectionEnabled = true,
            const double fromH4MaxFibonacciExpansionPercent = 161.8,
            const double fromH1MaxFibonacciExpansionPercent = 161.8) {
        this.lastError = "";
        this.symbolName = fromSymbol;
        this.lotSize = NormalizeDouble(fromLotSize, 8);
        this.maxInitialStopLossPips = fromMaxInitialStopLossPips;
        this.directionCorrectionEnabled = fromDirectionCorrectionEnabled;
        this.h4MaxFibonacciExpansionPercent = fromH4MaxFibonacciExpansionPercent;
        this.h1MaxFibonacciExpansionPercent = fromH1MaxFibonacciExpansionPercent;
        this.isTester = (bool)MQLInfoInteger(MQL_TESTER);
        this.testerTradeStartTime = 0;
        this.sourceMode = "LIVE";
        this.databaseFileName = "mstng-m15-ea.sqlite";
        if (this.isTester) {
            this.sourceMode = "TESTER";
            this.databaseFileName = "mstng-m15-ea-tester.sqlite";
            if (fromTesterTradeStartTime < 0) {
                return this.fail("INVALID_TESTER_TRADE_START_TIME");
            }
            this.testerTradeStartTime = fromTesterTradeStartTime;
        }
        if (_Period != PERIOD_M15) {
            return this.fail("M15_CHART_REQUIRED");
        }
        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            return this.fail("OPTIMIZATION_NOT_SUPPORTED");
        }
        if (!MathIsValidNumber(this.lotSize) || this.lotSize == EMPTY_VALUE || this.lotSize <= 0.0) {
            return this.fail("INVALID_LOT_SIZE");
        }
        if (!MathIsValidNumber(this.maxInitialStopLossPips)
                || this.maxInitialStopLossPips == EMPTY_VALUE || this.maxInitialStopLossPips <= 0.0) {
            return this.fail("MAX_INITIAL_SL_UNSET");
        }
        if (MathAbs(NormalizeDouble(this.maxInitialStopLossPips, 1)
                - this.maxInitialStopLossPips) > 0.00000001) {
            return this.fail("MAX_INITIAL_SL_REQUIRES_ONE_DECIMAL_PLACE");
        }
        if (!M15EaConfig::isFibonacciExpansionLimitValid(this.h4MaxFibonacciExpansionPercent)
                || !M15EaConfig::isFibonacciExpansionLimitValid(this.h1MaxFibonacciExpansionPercent)) {
            return this.fail("INVALID_HIGHER_FE_LIMIT");
        }
        if (AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
            return this.fail("HEDGING_ACCOUNT_REQUIRED");
        }
        this.accountServer = AccountInfoString(ACCOUNT_SERVER);
        this.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        if (this.accountServer == "" || this.accountLogin <= 0 || this.symbolName == ""
                || StringFind(this.accountServer, "|") >= 0 || StringFind(this.symbolName, "|") >= 0) {
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
        MarketContext context(this.symbolName, PERIOD_M15);
        this.magicNumber = MagicNumberUtil::build(13, context, STRATEGY_TYPE_MTF_3IN3);
        string identity = this.accountServer + "|" + IntegerToString(this.accountLogin);
        this.runUid = EaTextUtil::hash(this.sourceMode + "|" + identity + "|"
            + IntegerToString(ChartID()) + "|" + IntegerToString(TimeLocal()) + "|"
            + EaTextUtil::ticket(GetTickCount64()));
        this.lockScope = this.sourceMode + "|" + identity + "|" + this.symbolName
            + "|M15|" + EaTextUtil::ticket(this.magicNumber);
        this.contextKey = "M15_EA_CONTEXT_V1|" + this.sourceMode + "|";
        if (this.isTester) {
            this.contextKey += this.runUid + "|";
        }
        this.contextKey += identity + "|" + this.symbolName + "|M15|" + EaTextUtil::ticket(this.magicNumber);
        if (StringLen(this.runUid) != 64) {
            return this.fail("HASH_UNAVAILABLE");
        }
        return true;
    }

    /**
     * 保存設定を、実際のM15判定と同じ固定値・丸めで文字列化する。
     */
    string createCanonicalText() const {
        return "M15_EA_CONFIG_V1|LOT_SIZE=" + DoubleToString(this.lotSize, 8)
            + "|MAX_INITIAL_SL_PIPS=" + DoubleToString(this.maxInitialStopLossPips, 1)
            + "|ZIGZAG_SL_BUFFER_PIPS=10.0|MAX_SPREAD_PIPS=5.0|ANALYSIS_START_TIME_FRAME=MN1"
            + "|DIRECTION_ALIGNMENT_MODE="
            + getH1DirectionAlignmentModeText(Mtf3In3H1Policy::getDirectionAlignmentMode())
            + "|W1_CONFIRMATION_MODE=" + getH1W1ConfirmationModeText(Mtf3In3H1Policy::getW1ConfirmationMode())
            + "|EMA200_CONFIRMATION_MODE=D1_H4_H1_M15_REQUIRED|GMMA_TIME_FRAME=M15|ZIGZAG_CONFIRMED_REQUIRED=1"
            + "|DIRECTION_CORRECTION_ENABLED=" + IntegerToString((int)this.directionCorrectionEnabled)
            + "|H4_MAX_FE_PERCENT=" + DoubleToString(this.h4MaxFibonacciExpansionPercent, 1)
            + "|H1_MAX_FE_PERCENT=" + DoubleToString(this.h1MaxFibonacciExpansionPercent, 1)
            + "|CURRENCY_STRENGTH_ENTRY_FILTER_ENABLED=0|ENTRY_COUNT=1"
            + "|LIVE_FIRST_EVALUATION_SECONDS=1|LIVE_EVALUATION_INTERVAL_SECONDS=30"
            + "|TESTER_EVALUATION_TRIGGER=TICK|TESTER_TRADE_START_TIME=" + IntegerToString(this.testerTradeStartTime);
    }

    /**
     * Testerの開始日時前だけ新規Entryを止める。
     */
    bool isBeforeTesterTradeStart(const datetime fromTime) const {
        return this.isTester && this.testerTradeStartTime > 0 && fromTime < this.testerTradeStartTime;
    }

    /**
     * 0による無効化または小数1桁で正となる有限のFE上限を許可する。
     */
    static bool isFibonacciExpansionLimitValid(const double fromLimit) {
        return MathIsValidNumber(fromLimit) && fromLimit != EMPTY_VALUE && fromLimit >= 0.0
            && (fromLimit == 0.0 || NormalizeDouble(fromLimit, 1) > 0.0);
    }

    /**
     * M15単一通貨EAのプログラム世代を返す。
     */
    static string getProgramVersion() { return "1.00"; }

    /**
     * 補正・FE・確定ZigZagを含むM15戦略世代を返す。
     */
    static string getStrategyVersion() { return "M15_MTF3IN3_EMA4_FE_ZIGZAG10_V1"; }

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
