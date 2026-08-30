//+------------------------------------------------------------------+
//|                                  ZigZagElliotAnalysisProfile.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_ZIGZAG_ELLIOT_ANALYSIS_PROFILE_MQH
#define MSTNG_ELLIOT_ZIGZAG_ELLIOT_ANALYSIS_PROFILE_MQH

/**
 * ZigZagElliot分析結果へ影響する設定の単一正本。
 *
 * 計算処理と監査用Canonical Textは同じgetterを参照する。
 * 計算式を変更した場合は分析バージョンを更新する。
 */
class ZigZagElliotAnalysisProfile {
public:
    /** @return Elliott分析バージョン。 */
    static string getAnalysisVersion() { return "ELLIOT_MN1_V6"; }

    /** @return 分析Profileバージョン。 */
    static string getProfileVersion() {
        return "ZIGZAG_ELLIOT_ANALYSIS_PROFILE_V5";
    }

    /** @return 短期Stochastic K期間。 */
    static int getStochasticShortKPeriod() { return 5; }

    /** @return 短期Stochastic D期間。 */
    static int getStochasticShortDPeriod() { return 3; }

    /** @return 短期Stochastic Slowing期間。 */
    static int getStochasticShortSlowing() { return 3; }

    /** @return 中期Stochastic K期間。 */
    static int getStochasticMiddleKPeriod() { return 14; }

    /** @return 中期Stochastic D期間。 */
    static int getStochasticMiddleDPeriod() { return 3; }

    /** @return 中期Stochastic Slowing期間。 */
    static int getStochasticMiddleSlowing() { return 3; }

    /** @return 長期Stochastic K期間。 */
    static int getStochasticLongKPeriod() { return 21; }

    /** @return 長期Stochastic D期間。 */
    static int getStochasticLongDPeriod() { return 5; }

    /** @return 長期Stochastic Slowing期間。 */
    static int getStochasticLongSlowing() { return 5; }

    /** @return Stochastic平滑化方法。 */
    static ENUM_MA_METHOD getStochasticMaMethod() { return MODE_SMA; }

    /** @return Stochastic価格種別。 */
    static ENUM_STO_PRICE getStochasticPriceField() { return STO_LOWHIGH; }

    /** @return Stochasticクロス継続の最大参照本数。 */
    static int getStochasticLookback() { return 100; }

    /** @return Stochastic参照shift。 */
    static int getStochasticShift() { return 0; }

    /** @return Stochastic多数決の構成本数。 */
    static int getStochasticVoteMemberCount() { return 3; }

    /** @return Stochastic多数決でBUYとする本数。 */
    static int getStochasticBuyMajorityCount() { return 2; }

    /** @return Stochastic方向判定ルール。 */
    static string getStochasticDirectionRule() { return "MAIN_GE_SIGNAL"; }

    /**
     * Stochastic MainとSignalからBUY方向か判定する。
     *
     * @param fromMain Main値。
     * @param fromSignal Signal値。
     * @return MainがSignal以上の場合true。
     */
    static bool isStochasticBuyDirection(
        const double fromMain,
        const double fromSignal
    ) {
        return fromMain >= fromSignal;
    }

    /** @return Stochastic Main値の同値判定許容差。 */
    static double getStochasticMainOrderEpsilon() { return 0.0001; }

    /** @return GMMA短期EMA期間。 */
    static int getGmmaShortPeriod() { return 30; }

    /** @return GMMA長期EMA期間。 */
    static int getGmmaLongPeriod() { return 60; }

    /** @return GMMA移動平均方法。 */
    static ENUM_MA_METHOD getGmmaMaMethod() { return MODE_EMA; }

    /** @return GMMA適用価格。 */
    static ENUM_APPLIED_PRICE getGmmaAppliedPrice() { return PRICE_CLOSE; }

    /** @return GMMA移動平均の表示shift。 */
    static int getGmmaMaShift() { return 0; }

    /** @return GMMAトレンド継続判定の最大参照本数。 */
    static int getGmmaTrendLookback() { return 1000; }

    /** @return GMMAクロス継続判定の最大参照本数。 */
    static int getGmmaCrossLookback() { return 1000; }

    /** @return GMMA参照shift。 */
    static int getGmmaShift() { return 0; }

    /** @return ATR期間。 */
    static int getAtrPeriod() { return 14; }

    /** @return ATR参照shift。 */
    static int getAtrShift() { return 0; }

    /** @return EMA期間。 */
    static int getEma200Period() { return 200; }

    /** @return EMA200移動平均方法。 */
    static ENUM_MA_METHOD getEma200MaMethod() { return MODE_EMA; }

    /** @return EMA200適用価格。 */
    static ENUM_APPLIED_PRICE getEma200AppliedPrice() { return PRICE_CLOSE; }

    /** @return EMA200移動平均の表示shift。 */
    static int getEma200MaShift() { return 0; }

    /** @return EMA200傾き比較対象shift。 */
    static int getEma200CompareBarIndex() { return 4; }

    /** @return EMA200と比較する終値のshift。 */
    static int getEma200CloseShift() { return 1; }

    /** @return EMA200上昇・下降判定本数。 */
    static int getEma200CountBars() { return 4; }

    /** @return EMA200傾き方向判定の最低pips。 */
    static double getEma200MinSlopePips() { return 0.0; }

    /** @return MN1でEMA200計算を省略する場合true。 */
    static bool isEma200SkippedForMn1() { return true; }

    /** @return pips換算ルール識別子。 */
    static string getPipsRule() {
        return "DIGITS_3_OR_5_POINT_X10_ELSE_POINT";
    }

    /** @return pips計算結果の丸め桁数。 */
    static int getPipsResultDigits() { return 1; }

    /**
     * 小数桁数から1pipあたりのPoint数を取得する。
     *
     * @param fromDigits シンボルの小数桁数。
     * @return 3桁・5桁は10、それ以外は1。
     */
    static double getPipInPoints(const int fromDigits) {
        if (fromDigits == 3 || fromDigits == 5) {
            return 10.0;
        }

        return 1.0;
    }

    /** @return H1観測の基準時間足。 */
    static ENUM_TIMEFRAMES getAnchorTimeFrame() { return PERIOD_H1; }

    /** @return H1観測の分析開始時間足。 */
    static ENUM_TIMEFRAMES getAnalysisStartTimeFrame() { return PERIOD_MN1; }

    /** @return H1観測に含める時間足数。 */
    static int getObservationTimeFrameCount() { return 5; }

    /** @return H1観測時間足の固定順序文字列。 */
    static string getObservationTimeFrameOrderText() {
        string text = "";

        for (int i = 0; i < getObservationTimeFrameCount(); i++) {
            if (i > 0) {
                text += ",";
            }

            text += IntegerToString(
                (int)getObservationTimeFrame(i)
            );
        }

        return text;
    }

    /**
     * H1観測の固定順序に対応する時間足を取得する。
     *
     * @param fromIndex 0から4の順序Index。
     * @return 対応時間足。範囲外の場合PERIOD_CURRENT。
     */
    static ENUM_TIMEFRAMES getObservationTimeFrame(const int fromIndex) {
        if (fromIndex == 0) {
            return PERIOD_MN1;
        }
        if (fromIndex == 1) {
            return PERIOD_W1;
        }
        if (fromIndex == 2) {
            return PERIOD_D1;
        }
        if (fromIndex == 3) {
            return PERIOD_H4;
        }
        if (fromIndex == 4) {
            return PERIOD_H1;
        }

        return PERIOD_CURRENT;
    }

    /** @return ZigZag Depth。 */
    static int getZigZagDepth() { return 12; }

    /** @return ZigZag Deviation。 */
    static int getZigZagDeviation() { return 5; }

    /** @return ZigZag Backstep。 */
    static int getZigZagBackstep() { return 3; }

    /** @return 最上位足ZigZag計算の最大バー数。 */
    static int getZigZagHighestMaxBars() { return 300; }

    /** @return Wave分割処理の終了規則。 */
    static string getWaveSplitTerminationRule() {
        return "POSITION_PROGRESS_TO_POINT_COUNT_V1";
    }

    /** @return 上位足から参照する最大Wave数。 */
    static int getHigherTimeFrameWaveLimit() { return 5; }

    /** @return 上位足同期後の再分析最大ラウンド数。 */
    static int getHigherReanalyzeMaxRounds() { return 3; }

    /** @return 上位足の確定修正区間を単一Waveへ統合する規則。 */
    static string getHigherCorrectiveSegmentRule() {
        return "STRICT_CONFIRMED_FOUR_POINT_OR_NESTED_ABC_AB_V2";
    }

    /** @return 親区間内の3Wave継続構造を単一Waveへ統合する規則。 */
    static string getHigherThreeWaveContinuationRule() {
        return "EXACT_PARENT_SEGMENT_THREE_WAVE_FOUR_ANCHOR_DOW_RECOUNT_V1";
    }

    /** @return 上位足Waveを取得できない場合の分析バー数。 */
    static int getHigherBarsFallbackCount() { return 300; }

    /** @return 小履歴用倍率へ切り替えるバー数上限。 */
    static int getHigherBarsSmallHistoryThreshold() { return 100; }

    /** @return 通常履歴の分析バー数倍率。 */
    static double getHigherBarsNormalMultiplier() { return 1.1; }

    /** @return 小履歴の分析バー数倍率。 */
    static double getHigherBarsSmallHistoryMultiplier() { return 3.0; }

    /** @return 最新ポイントを一時補正するpips幅。 */
    static double getLatestPointCorrectionPips() { return 10.0; }

    /** @return 浅い推進波とする最小Fibonacci Expansion率。 */
    static double getRecountMinMotiveExpansionPercent() { return 100.0; }

    /** @return 深い修正波とする最大Fibonacci Retracement率。 */
    static double getRecountMaxCorrectionPercent() { return 85.0; }

    /** @return Fibonacci深さ率の丸め桁数。 */
    static int getFiboDepthPercentDigits() { return 1; }

    /** @return Fibonacci深さを未判定とする下限。 */
    static double getFiboDepthMinimumPercent() { return 0.0; }

    /** @return SHALLOWゾーン上限。 */
    static double getFiboDepthShallowUpperPercent() { return 23.6; }

    /** @return LIGHTゾーン上限。 */
    static double getFiboDepthLightUpperPercent() { return 38.2; }

    /** @return NORMALゾーン上限。 */
    static double getFiboDepthNormalUpperPercent() { return 61.8; }

    /** @return DEEPゾーン上限。 */
    static double getFiboDepthDeepUpperPercent() { return 78.6; }

    /** @return 有効なFibonacci深さの上限。 */
    static double getFiboDepthValidMaximumPercent() { return 100.0; }

    /** @return Fibonacci Expansion 61.8%比率。 */
    static double getFibonacciExpansion618() { return 0.618; }

    /** @return Fibonacci Expansion 100.0%比率。 */
    static double getFibonacciExpansion1000() { return 1.000; }

    /** @return Fibonacci Expansion 127.2%比率。 */
    static double getFibonacciExpansion1272() { return 1.272; }

    /** @return Fibonacci Expansion 161.8%比率。 */
    static double getFibonacciExpansion1618() { return 1.618; }

    /** @return Fibonacci Expansion 200.0%比率。 */
    static double getFibonacciExpansion2000() { return 2.000; }

    /**
     * 固定順序の分析設定文字列を生成する。
     *
     * @return 監査およびHash生成に使用するCanonical Text。
     */
    static string createCanonicalText() {
        string text = getProfileVersion();
        appendInteger(text, "STO_SHORT_K", getStochasticShortKPeriod());
        appendInteger(text, "STO_SHORT_D", getStochasticShortDPeriod());
        appendInteger(text, "STO_SHORT_SLOWING", getStochasticShortSlowing());
        appendInteger(text, "STO_MIDDLE_K", getStochasticMiddleKPeriod());
        appendInteger(text, "STO_MIDDLE_D", getStochasticMiddleDPeriod());
        appendInteger(text, "STO_MIDDLE_SLOWING", getStochasticMiddleSlowing());
        appendInteger(text, "STO_LONG_K", getStochasticLongKPeriod());
        appendInteger(text, "STO_LONG_D", getStochasticLongDPeriod());
        appendInteger(text, "STO_LONG_SLOWING", getStochasticLongSlowing());
        appendInteger(text, "STO_MA_METHOD", (int)getStochasticMaMethod());
        appendInteger(text, "STO_PRICE_FIELD", (int)getStochasticPriceField());
        appendInteger(text, "STO_LOOKBACK", getStochasticLookback());
        appendInteger(text, "STO_SHIFT", getStochasticShift());
        appendInteger(text, "STO_VOTE_MEMBERS", getStochasticVoteMemberCount());
        appendInteger(text, "STO_BUY_MAJORITY", getStochasticBuyMajorityCount());
        appendText(text, "STO_RULE", getStochasticDirectionRule());
        appendDouble(text, "STO_MAIN_ORDER_EPSILON", getStochasticMainOrderEpsilon(), 4);
        appendInteger(text, "GMMA_SHORT_PERIOD", getGmmaShortPeriod());
        appendInteger(text, "GMMA_LONG_PERIOD", getGmmaLongPeriod());
        appendInteger(text, "GMMA_MA_METHOD", (int)getGmmaMaMethod());
        appendInteger(text, "GMMA_APPLIED_PRICE", (int)getGmmaAppliedPrice());
        appendInteger(text, "GMMA_MA_SHIFT", getGmmaMaShift());
        appendInteger(text, "GMMA_TREND_LOOKBACK", getGmmaTrendLookback());
        appendInteger(text, "GMMA_CROSS_LOOKBACK", getGmmaCrossLookback());
        appendInteger(text, "GMMA_SHIFT", getGmmaShift());
        appendInteger(text, "ATR_PERIOD", getAtrPeriod());
        appendInteger(text, "ATR_SHIFT", getAtrShift());
        appendInteger(text, "EMA200_PERIOD", getEma200Period());
        appendInteger(text, "EMA200_MA_METHOD", (int)getEma200MaMethod());
        appendInteger(text, "EMA200_APPLIED_PRICE", (int)getEma200AppliedPrice());
        appendInteger(text, "EMA200_MA_SHIFT", getEma200MaShift());
        appendInteger(text, "EMA200_CLOSE_SHIFT", getEma200CloseShift());
        appendInteger(text, "EMA200_COMPARE_SHIFT", getEma200CompareBarIndex());
        appendInteger(text, "EMA200_COUNT_BARS", getEma200CountBars());
        appendDouble(text, "EMA200_MIN_SLOPE_PIPS", getEma200MinSlopePips(), 1);
        appendInteger(text, "EMA200_SKIP_MN1", boolToInteger(isEma200SkippedForMn1()));
        appendText(text, "PIPS_RULE", getPipsRule());
        appendInteger(text, "PIPS_RESULT_DIGITS", getPipsResultDigits());
        appendInteger(text, "ANCHOR_TF", (int)getAnchorTimeFrame());
        appendInteger(
            text,
            "ANALYSIS_START_TF",
            (int)getAnalysisStartTimeFrame()
        );
        appendInteger(
            text,
            "TF_COUNT",
            getObservationTimeFrameCount()
        );
        appendText(text, "TF_ORDER", getObservationTimeFrameOrderText());
        appendInteger(text, "ZIGZAG_DEPTH", getZigZagDepth());
        appendInteger(text, "ZIGZAG_DEVIATION", getZigZagDeviation());
        appendInteger(text, "ZIGZAG_BACKSTEP", getZigZagBackstep());
        appendInteger(text, "ZIGZAG_HIGHEST_MAX_BARS", getZigZagHighestMaxBars());
        appendText(
            text,
            "ELLIOT_WAVE_SPLIT_TERMINATION_RULE",
            getWaveSplitTerminationRule()
        );
        appendInteger(
            text,
            "ELLIOT_HIGHER_WAVE_LIMIT",
            getHigherTimeFrameWaveLimit()
        );
        appendInteger(
            text,
            "ELLIOT_HIGHER_REANALYZE_MAX_ROUNDS",
            getHigherReanalyzeMaxRounds()
        );
        appendText(
            text,
            "ELLIOT_HIGHER_CORRECTIVE_SEGMENT_RULE",
            getHigherCorrectiveSegmentRule()
        );
        appendText(
            text,
            "ELLIOT_HIGHER_THREE_WAVE_CONTINUATION_RULE",
            getHigherThreeWaveContinuationRule()
        );
        appendInteger(
            text,
            "ELLIOT_HIGHER_BARS_FALLBACK",
            getHigherBarsFallbackCount()
        );
        appendInteger(
            text,
            "ELLIOT_HIGHER_BARS_SMALL_THRESHOLD",
            getHigherBarsSmallHistoryThreshold()
        );
        appendDouble(
            text,
            "ELLIOT_HIGHER_BARS_NORMAL_MULTIPLIER",
            getHigherBarsNormalMultiplier(),
            1
        );
        appendDouble(
            text,
            "ELLIOT_HIGHER_BARS_SMALL_MULTIPLIER",
            getHigherBarsSmallHistoryMultiplier(),
            1
        );
        appendDouble(
            text,
            "ELLIOT_LATEST_POINT_CORRECTION_PIPS",
            getLatestPointCorrectionPips(),
            1
        );
        appendDouble(
            text,
            "RECOUNT_MIN_MOTIVE_FE_PERCENT",
            getRecountMinMotiveExpansionPercent(),
            1
        );
        appendDouble(
            text,
            "RECOUNT_MAX_CORRECTION_FIB_PERCENT",
            getRecountMaxCorrectionPercent(),
            1
        );
        appendInteger(
            text,
            "FIBO_DEPTH_PERCENT_DIGITS",
            getFiboDepthPercentDigits()
        );
        appendDouble(
            text,
            "FIBO_DEPTH_MIN_PERCENT",
            getFiboDepthMinimumPercent(),
            1
        );
        appendDouble(
            text,
            "FIBO_DEPTH_SHALLOW_UPPER_PERCENT",
            getFiboDepthShallowUpperPercent(),
            1
        );
        appendDouble(
            text,
            "FIBO_DEPTH_LIGHT_UPPER_PERCENT",
            getFiboDepthLightUpperPercent(),
            1
        );
        appendDouble(
            text,
            "FIBO_DEPTH_NORMAL_UPPER_PERCENT",
            getFiboDepthNormalUpperPercent(),
            1
        );
        appendDouble(
            text,
            "FIBO_DEPTH_DEEP_UPPER_PERCENT",
            getFiboDepthDeepUpperPercent(),
            1
        );
        appendDouble(
            text,
            "FIBO_DEPTH_VALID_MAX_PERCENT",
            getFiboDepthValidMaximumPercent(),
            1
        );
        appendDouble(text, "FE618", getFibonacciExpansion618(), 3);
        appendDouble(text, "FE1000", getFibonacciExpansion1000(), 3);
        appendDouble(text, "FE1272", getFibonacciExpansion1272(), 3);
        appendDouble(text, "FE1618", getFibonacciExpansion1618(), 3);
        appendDouble(text, "FE2000", getFibonacciExpansion2000(), 3);

        return text;
    }

    /**
     * Canonical TextのSHA-256を生成する。
     *
     * @return 64桁の小文字16進SHA-256。生成失敗時は空文字列。
     */
    static string createHash() {
        return createSha256Hash(createCanonicalText());
    }

private:
    /** Canonical Textへ文字列値を追加する。 */
    static void appendText(
        string &fromText,
        const string fromName,
        const string fromValue
    ) {
        fromText += "|" + fromName + "=" + fromValue;
    }

    /** Canonical Textへ整数値を追加する。 */
    static void appendInteger(
        string &fromText,
        const string fromName,
        const int fromValue
    ) {
        appendText(fromText, fromName, IntegerToString(fromValue));
    }

    /** Canonical Textへ小数値を追加する。 */
    static void appendDouble(
        string &fromText,
        const string fromName,
        const double fromValue,
        const int fromDigits
    ) {
        appendText(fromText, fromName, DoubleToString(fromValue, fromDigits));
    }

    /** bool値を0または1へ変換する。 */
    static int boolToInteger(const bool fromValue) {
        if (fromValue) {
            return 1;
        }

        return 0;
    }

    /** UTF-8文字列からSHA-256を生成する。 */
    static string createSha256Hash(const string fromText) {
        uchar sourceBytes[];
        int sourceSize = StringToCharArray(
            fromText,
            sourceBytes,
            0,
            WHOLE_ARRAY,
            CP_UTF8
        );

        if (sourceSize <= 1
                || ArrayResize(sourceBytes, sourceSize - 1) != sourceSize - 1) {
            return "";
        }

        uchar keyBytes[];
        uchar hashBytes[];
        ArrayResize(keyBytes, 0);
        ResetLastError();
        int hashSize = CryptEncode(
            CRYPT_HASH_SHA256,
            sourceBytes,
            keyBytes,
            hashBytes
        );

        if (hashSize != 32) {
            return "";
        }

        string hashText = "";
        string hexDigits = "0123456789abcdef";

        for (int i = 0; i < hashSize; i++) {
            int byteValue = (int)hashBytes[i];
            hashText += StringSubstr(hexDigits, byteValue / 16, 1);
            hashText += StringSubstr(hexDigits, byteValue % 16, 1);
        }

        return hashText;
    }
};

#endif // MSTNG_ELLIOT_ZIGZAG_ELLIOT_ANALYSIS_PROFILE_MQH
