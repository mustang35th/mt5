#ifndef MSTNGM5EA_CONFIG_CONFIG_MQH
#define MSTNGM5EA_CONFIG_CONFIG_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>
#include <Mstng\Util\Util.mqh>
#include <MstngEa\Trade\MagicNumberUtil.mqh>
#include <MstngEaCommon\Runtime\EaTextUtil.mqh>

/**
 * M5単一通貨EAへ渡す取引設定と通貨強弱の参照設定。
 */
struct M5EaSettings {
    /** 固定ロット。 */
    double lotSize;

    /** 許容する最大初期SL幅。 */
    double maxInitialStopLossPips;

    /** Testerだけで使用する売買開始日時。0は日時制限なし。 */
    datetime testerTradeStartTime;

    /** 初期SLのZigZag基準点からの余白。 */
    double initialStopLossBufferPips;

    /** トレイルSLの確定ZigZagからの余白。 */
    double trailStopLossBufferPips;

    /** 通貨強弱をエントリー条件として使用する場合true。 */
    bool currencyStrengthEnabled;

    /** 各期間で端順位とOR判定する順位差基準。 */
    int currencyStrengthMinimumRankDifference;

    /** 長中期順位差の直近増減方向を要求する場合true。 */
    bool longMediumGapDirectionEnabled;

    /** 通貨強弱順位を参照するDB名。 */
    string currencyStrengthDatabaseFileName;

    /** 年別の通貨強弱DBを参照する場合true。 */
    bool currencyStrengthDatabaseSplitByYear;

    /** 通貨強弱DBをCommonから読む場合true。 */
    bool currencyStrengthDatabaseUseCommonFolder;

    /** 通貨強弱のLIVE・TESTER参照元。 */
    CurrencyStrengthRankDatabaseProfile currencyStrengthDatabaseProfile;

    /** 通貨強弱の票重み付け方式。 */
    CurrencyStrengthVoteWeightMode currencyStrengthVoteWeightMode;

    /**
     * 通常版M5と同じ通貨強弱条件、既存EAと同じSL余白で初期化する。
     */
    M5EaSettings() {
        this.lotSize = 0.01;
        this.maxInitialStopLossPips = 100.0;
        this.testerTradeStartTime = 0;
        this.initialStopLossBufferPips = 10.0;
        this.trailStopLossBufferPips = 10.0;
        this.currencyStrengthEnabled = true;
        this.currencyStrengthMinimumRankDifference = 4;
        this.longMediumGapDirectionEnabled = true;
        this.currencyStrengthDatabaseFileName = "mstng-currency-strength.sqlite";
        this.currencyStrengthDatabaseSplitByYear = true;
        this.currencyStrengthDatabaseUseCommonFolder = true;
        this.currencyStrengthDatabaseProfile = CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
        this.currencyStrengthVoteWeightMode = CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;
    }
};

/**
 * M5単一通貨EAの有効設定と、専用の保存・管理識別子を保持する。
 */
class M5EaConfig {
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

    /** 初期SLのZigZag基準点からの余白。 */
    double initialStopLossBufferPips;

    /** トレイルSLの確定ZigZagからの余白。 */
    double trailStopLossBufferPips;

    /** 通貨強弱をエントリー条件として使用する場合true。 */
    bool currencyStrengthEnabled;

    /** 各期間で端順位とOR判定する順位差基準。 */
    int currencyStrengthMinimumRankDifference;

    /** 長中期順位差の直近増減方向を要求する場合true。 */
    bool longMediumGapDirectionEnabled;

    /** 通貨強弱順位を参照するDB名。 */
    string currencyStrengthDatabaseFileName;

    /** 年別の通貨強弱DBを参照する場合true。 */
    bool currencyStrengthDatabaseSplitByYear;

    /** 通貨強弱DBをCommonから読む場合true。 */
    bool currencyStrengthDatabaseUseCommonFolder;

    /** 通貨強弱のLIVE・TESTER参照元。 */
    CurrencyStrengthRankDatabaseProfile currencyStrengthDatabaseProfile;

    /** 通貨強弱の票重み付け方式。 */
    CurrencyStrengthVoteWeightMode currencyStrengthVoteWeightMode;

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

    /** Common内の取引DBファイル名。 */
    string databaseFileName;

    /** 最後の初期化エラー。 */
    string lastError;

    /**
     * 保存先・口座情報を未取得にし、入力の初期値を保持する。
     */
    M5EaConfig() {
        M5EaSettings settings;
        this.copySettings(settings);
        this.symbolName = "";
        this.accountServer = "";
        this.accountLogin = 0;
        this.magicNumber = 0;
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
        this.databaseFileName = "mstng-m5-ea.sqlite";
        this.lastError = "";
    }

    /**
     * 設定・口座・価格単位を検証し、M5専用の保存識別子を生成する。
     *
     * @param fromSymbol 対象シンボル。
     * @param fromSettings EAの入力設定。
     * @return M5チャートと取引設定が有効な場合true。
     */
    bool initialize(const string fromSymbol, const M5EaSettings &fromSettings) {
        this.lastError = "";
        this.symbolName = fromSymbol;
        this.copySettings(fromSettings);
        this.lotSize = NormalizeDouble(fromSettings.lotSize, 8);
        this.isTester = Util::isStrategyTester();
        this.testerTradeStartTime = 0;
        this.sourceMode = "LIVE";
        this.databaseFileName = "mstng-m5-ea.sqlite";
        if (this.isTester) {
            this.sourceMode = "TESTER";
            this.databaseFileName = "mstng-m5-ea-tester.sqlite";
            if (fromSettings.testerTradeStartTime < 0) {
                return this.fail("INVALID_TESTER_TRADE_START_TIME");
            }

            this.testerTradeStartTime = fromSettings.testerTradeStartTime;
        }

        if (_Period != PERIOD_M5) {
            return this.fail("M5_CHART_REQUIRED");
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

        if (!M5EaConfig::isPipsSettingValid(this.maxInitialStopLossPips)) {
            return this.fail("MAX_INITIAL_SL_REQUIRES_ONE_DECIMAL_PLACE");
        }

        if (!M5EaConfig::isPipsSettingValid(this.initialStopLossBufferPips)
                || !M5EaConfig::isPipsSettingValid(this.trailStopLossBufferPips)) {
            return this.fail("INVALID_SL_BUFFER_PIPS");
        }

        if (this.currencyStrengthMinimumRankDifference < 1
                || this.currencyStrengthMinimumRankDifference > 7) {
            return this.fail("INVALID_CURRENCY_STRENGTH_RANK_DIFFERENCE");
        }

        if (this.currencyStrengthDatabaseProfile < CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_TESTER
                || this.currencyStrengthDatabaseProfile > CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER
                || this.currencyStrengthVoteWeightMode < CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM
                || this.currencyStrengthVoteWeightMode > CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED
                || (this.currencyStrengthEnabled && StringLen(this.currencyStrengthDatabaseFileName) == 0)) {
            return this.fail("INVALID_CURRENCY_STRENGTH_SOURCE");
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

        MarketContext context(this.symbolName, PERIOD_M5);
        this.magicNumber = MagicNumberUtil::build(14, context, STRATEGY_TYPE_MTF_3IN3);
        string identity = this.accountServer + "|" + IntegerToString(this.accountLogin);
        this.runUid = EaTextUtil::hash(this.sourceMode + "|" + identity + "|"
            + IntegerToString(ChartID()) + "|" + IntegerToString(TimeLocal()) + "|"
            + EaTextUtil::ticket(GetTickCount64()));
        this.lockScope = this.sourceMode + "|" + identity + "|" + this.symbolName
            + "|M5|" + EaTextUtil::ticket(this.magicNumber);
        this.contextKey = "M5_EA_CONTEXT_V1|" + this.sourceMode + "|";
        if (this.isTester) {
            this.contextKey += this.runUid + "|";
        }

        this.contextKey += identity + "|" + this.symbolName + "|M5|" + EaTextUtil::ticket(this.magicNumber);
        if (StringLen(this.runUid) != 64) {
            return this.fail("HASH_UNAVAILABLE");
        }

        return true;
    }

    /**
     * 実際のM5判定と取引・参照設定を保存用文字列へ固定する。
     */
    string createCanonicalText() const {
        string text = "M5_EA_CONFIG_V1|LOT_SIZE=" + DoubleToString(this.lotSize, 8)
            + "|MAX_INITIAL_SL_PIPS=" + DoubleToString(this.maxInitialStopLossPips, 1)
            + "|INITIAL_SL_BUFFER_PIPS=" + DoubleToString(this.initialStopLossBufferPips, 1)
            + "|TRAIL_SL_BUFFER_PIPS=" + DoubleToString(this.trailStopLossBufferPips, 1)
            + "|MAX_SPREAD_PIPS=5.0|ANALYSIS_START_TIME_FRAME=MN1"
            + "|DIRECTION_ALIGNMENT_MODE=D1_H4_H1_M15_ONE_CORRECTION"
            + "|EMA200_CONFIRMATION_MODE=H1_M15_M5_REQUIRED|EMA200_DISTANCE_REQUIRED=0"
            + "|MAIN_WAVE_CONDITION=M15_1_OR_3_AND_M5_1_OR_3|M5_WAVE3_MAX_FE_PERCENT=161.8"
            + "|GMMA_TIME_FRAME=M5|ZIGZAG_CONFIRMED_REQUIRED=1|H1_DISPLAY_WAVE_ENTRY_LIMIT_ENABLED=0"
            + "|CURRENCY_STRENGTH_ENTRY_FILTER_ENABLED=" + IntegerToString((int)this.currencyStrengthEnabled)
            + "|CURRENCY_STRENGTH_MINIMUM_RANK_DIFFERENCE=" + IntegerToString(this.currencyStrengthMinimumRankDifference)
            + "|CURRENCY_STRENGTH_RANK_CONDITION=BOTH_DIRECTION_AND_EACH_GAP_OR_END_RANK"
            + "|LONG_MEDIUM_GAP_DIRECTION_ENABLED=" + IntegerToString((int)this.longMediumGapDirectionEnabled)
            + "|MEDIUM_SHORT_GAP_DIRECTION_ENABLED=0|ENTRY_COUNT=1"
            + "|CURRENCY_STRENGTH_DATABASE_PROFILE=" + IntegerToString((int)this.currencyStrengthDatabaseProfile)
            + "|CURRENCY_STRENGTH_VOTE_WEIGHT_MODE=" + IntegerToString((int)this.currencyStrengthVoteWeightMode)
            + "|CURRENCY_STRENGTH_DATABASE_SPLIT_BY_YEAR=" + IntegerToString((int)this.currencyStrengthDatabaseSplitByYear)
            + "|CURRENCY_STRENGTH_DATABASE_USE_COMMON_FOLDER=" + IntegerToString((int)this.currencyStrengthDatabaseUseCommonFolder)
            + "|CURRENCY_STRENGTH_REFRESH_SECONDS=15"
            + "|LIVE_FIRST_EVALUATION_SECONDS=1|LIVE_EVALUATION_INTERVAL_SECONDS=30"
            + "|TESTER_WARMUP_DEFER_DB_TIMER=1"
            + "|TESTER_EVALUATION_TRIGGER=TICK|TESTER_TRADE_START_TIME=" + IntegerToString(this.testerTradeStartTime);
#ifdef MSTNG_M5_D1_RELAXED_COMPARISON
        StringReplace(text, "DIRECTION_ALIGNMENT_MODE=D1_H4_H1_M15_ONE_CORRECTION",
            "DIRECTION_ALIGNMENT_MODE=D1_OPTIONAL_H4_H1_M15_ONE_CORRECTION");
#endif
        EaTextUtil::appendField(text, "CURRENCY_STRENGTH_DATABASE_FILE_NAME", this.currencyStrengthDatabaseFileName);

        return text;
    }

    /**
     * Testerの開始日時前だけ新規Entryを止める。
     */
    bool isBeforeTesterTradeStart(const datetime fromTime) const {
        return this.isTester && this.testerTradeStartTime > 0 && fromTime < this.testerTradeStartTime;
    }

    /**
     * 0以上・小数1桁の有限なpips設定を許可する。
     */
    static bool isPipsSettingValid(const double fromPips) {
        return MathIsValidNumber(fromPips) && fromPips != EMPTY_VALUE && fromPips >= 0.0
            && MathAbs(NormalizeDouble(fromPips, 1) - fromPips) <= 0.00000001;
    }

    /**
     * M5単一通貨EAのプログラム世代を返す。
     */
    static string getProgramVersion() { return "1.03"; }

    /**
     * 通常版M5判定・通貨強弱・確定ZigZag SLを含む戦略世代を返す。
     */
    static string getStrategyVersion() {
#ifdef MSTNG_M5_D1_RELAXED_COMPARISON
        return "M5_ZIGZAG_ELLIOT_STRENGTH_ZIGZAG_SL_D1_OPTIONAL_TEST_V1";
#else
        return "M5_ZIGZAG_ELLIOT_STRENGTH_ZIGZAG_SL_D1_CORRECTION_V2";
#endif
    }

private:
    /**
     * 入力設定を保持する。Tester開始時刻はinitializeで実行環境に従い適用する。
     */
    void copySettings(const M5EaSettings &fromSettings) {
        this.lotSize = fromSettings.lotSize;
        this.maxInitialStopLossPips = fromSettings.maxInitialStopLossPips;
        this.initialStopLossBufferPips = fromSettings.initialStopLossBufferPips;
        this.trailStopLossBufferPips = fromSettings.trailStopLossBufferPips;
        this.currencyStrengthEnabled = fromSettings.currencyStrengthEnabled;
        this.currencyStrengthMinimumRankDifference = fromSettings.currencyStrengthMinimumRankDifference;
        this.longMediumGapDirectionEnabled = fromSettings.longMediumGapDirectionEnabled;
        this.currencyStrengthDatabaseFileName = fromSettings.currencyStrengthDatabaseFileName;
        this.currencyStrengthDatabaseSplitByYear = fromSettings.currencyStrengthDatabaseSplitByYear;
        this.currencyStrengthDatabaseUseCommonFolder = fromSettings.currencyStrengthDatabaseUseCommonFolder;
        this.currencyStrengthDatabaseProfile = fromSettings.currencyStrengthDatabaseProfile;
        this.currencyStrengthVoteWeightMode = fromSettings.currencyStrengthVoteWeightMode;
    }

    /**
     * 初期化拒否理由を保持する。
     */
    bool fail(const string fromReason) {
        this.lastError = fromReason;

        return false;
    }
};

#endif
