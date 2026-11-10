//+------------------------------------------------------------------+
//|                               CurrencyStrengthDailyRangeList.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_CURRENCY_STRENGTH_DAILY_RANGE_LIST_MQH
#define MSTNG_CURRENCY_STRENGTH_DAILY_RANGE_LIST_MQH

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthDailyRangeInfo.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * LIVEの28通貨ペアの日足値幅と円換算をまとめて取得する。
 * 日足は各1本、換算気配は決済通貨ごとに1回だけ取得する。
 */
class CurrencyStrengthDailyRangeList {
public:
    /**
     * 売買対象の絞り込みに関係なく全28通貨ペアを登録する。
     */
    CurrencyStrengthDailyRangeList() {
        this.updatedAt = 0;
        this.referenceSymbolName = "";
        this.symbolPrefix = "";
        this.symbolSuffix = "";
        SymbolNameInfoAll symbols;
        int total = symbols.size();
        ArrayResize(this.rows, total);
        ArrayResize(this.resolvedSymbolNames, total);
        for (int i = 0; i < total; i++) {
            SymbolNameInfo *info = symbols.getSymbolNameInfo(i);
            if (info != NULL) {
                this.rows[i].reset(info.symbolName);
            }

            this.resolvedSymbolNames[i] = "";
        }

        this.quoteCurrencies[0] = "USD";
        this.quoteCurrencies[1] = "JPY";
        this.quoteCurrencies[2] = "EUR";
        this.quoteCurrencies[3] = "GBP";
        this.quoteCurrencies[4] = "AUD";
        this.quoteCurrencies[5] = "NZD";
        this.quoteCurrencies[6] = "CAD";
        this.quoteCurrencies[7] = "CHF";
        for (int i = 0; i < 8; i++) {
            this.directSymbolNames[i] = "";
            this.inverseSymbolNames[i] = "";
        }

        this.resetConversions();
    }

    /**
     * 登録している通貨ペア数を取得する。
     *
     * @return 通貨ペア数。
     */
    int size() const {
        return ArraySize(this.rows);
    }

    /**
     * 指定行の今回取得結果を返す。
     *
     * @param fromIndex 行番号。
     * @param fromInfo 取得結果。
     * @return 行番号が有効な場合true。取得可否は結果のフラグを参照する。
     */
    bool get(const int fromIndex, CurrencyStrengthDailyRangeInfo &fromInfo) const {
        if (fromIndex < 0 || fromIndex >= this.size()) {
            return false;
        }

        fromInfo = this.rows[fromIndex];

        return true;
    }

    /**
     * 直近の取得開始時刻を返す。
     *
     * @return サーバー時刻。未取得の場合は0。
     */
    datetime getUpdatedAt() const {
        return this.updatedAt;
    }

    /**
     * 当日の日足値幅と、同じ日の最新気配による円換算値を更新する。
     * 取得失敗は行単位で未取得へ戻し、テスターでは市場データを参照しない。
     *
     * @param fromReferenceSymbol 接頭辞・接尾辞の基準となるチャートシンボル。
     * @return LIVEで取得を試行した場合true。全行の取得成功を意味しない。
     */
    bool update(const string fromReferenceSymbol) {
        if (Util::isStrategyTester()) {
            return false;
        }

        this.updatedAt = TimeCurrent();
        for (int i = 0; i < this.size(); i++) {
            string symbolName = this.rows[i].symbolName;
            this.rows[i].reset(symbolName, this.updatedAt);
        }

        this.resetConversions();
        if (this.updatedAt <= 0) {
            return false;
        }

        this.updateSymbolAffixes(fromReferenceSymbol);
        for (int i = 0; i < this.size(); i++) {
            if (this.resolvedSymbolNames[i] == "") {
                this.resolvedSymbolNames[i] = this.resolveSymbolName(this.rows[i].symbolName);
            }

            string symbolName = this.resolvedSymbolNames[i];
            this.rows[i].resolvedSymbolName = symbolName;
            if (symbolName == "") {
                continue;
            }

            if (!SymbolSelect(symbolName, true)) {
                this.resolvedSymbolNames[i] = "";
                continue;
            }

            this.readDailyRange(this.rows[i]);
        }

        for (int i = 0; i < this.size(); i++) {
            if (this.rows[i].rangeAvailable) {
                this.updateJpyRange(this.rows[i]);
            }
        }

        return true;
    }

private:
    /** 正規名順の取得結果。 */
    CurrencyStrengthDailyRangeInfo rows[];

    /** 前回解決した各通貨ペアの実シンボル名。 */
    string resolvedSymbolNames[];

    /** 前回の取得開始サーバー時刻。 */
    datetime updatedAt;

    /** 名前解決の基準として保持したシンボル名。 */
    string referenceSymbolName;

    /** 基準シンボルの接頭辞。 */
    string symbolPrefix;

    /** 基準シンボルの接尾辞。 */
    string symbolSuffix;

    /** 換算気配を共用する8通貨。 */
    string quoteCurrencies[8];

    /** 通貨/JPYの解決済み実シンボル名。 */
    string directSymbolNames[8];

    /** JPY/通貨の解決済み実シンボル名。 */
    string inverseSymbolNames[8];

    /** 今回すでに換算気配を確認した場合true。 */
    bool conversionChecked[8];

    /** 今回有効な換算気配を取得できた場合true。 */
    bool conversionAvailable[8];

    /** 今回の換算気配が逆シンボルの場合true。 */
    bool conversionInverse[8];

    /** 今回取得した換算Bid。 */
    double conversionBids[8];

    /** 今回取得した換算気配のサーバー時刻。 */
    datetime conversionTimes[8];

    /**
     * 解決済みシンボル名を残し、今回の換算気配だけ初期化する。
     */
    void resetConversions() {
        ArrayInitialize(this.conversionChecked, false);
        ArrayInitialize(this.conversionAvailable, false);
        ArrayInitialize(this.conversionInverse, false);
        ArrayInitialize(this.conversionBids, 0.0);
        ArrayInitialize(this.conversionTimes, 0);
    }

    /**
     * 有限で正の価格を判定する。
     */
    bool isPositivePrice(const double fromPrice) const {
        return MathIsValidNumber(fromPrice) && fromPrice != EMPTY_VALUE && fromPrice > 0.0;
    }

    /**
     * サーバー当日の時刻か確認する。土日は直前金曜の最終日足も許可する。
     * 気配の上限時刻だけ取得時点へ進め、日付の基準は更新開始時点に揃える。
     *
     * @param fromTime 検査するサーバー時刻。
     * @param fromUpperTime 許容する上限時刻。0の場合は更新開始時刻。
     */
    bool isCurrentDay(const datetime fromTime, const datetime fromUpperTime = 0) const {
        datetime upperTime = this.updatedAt;
        if (fromUpperTime > 0) {
            upperTime = fromUpperTime;
        }

        if (fromTime <= 0 || fromTime > upperTime) {
            return false;
        }

        datetime dayTime = fromTime - fromTime % 86400;
        datetime currentDay = this.updatedAt - this.updatedAt % 86400;
        if (dayTime == currentDay) {
            return true;
        }

        MqlDateTime currentParts;
        if (!TimeToStruct(this.updatedAt, currentParts)) {
            return false;
        }

        if (currentParts.day_of_week == 6) {
            return dayTime == currentDay - 86400;
        }

        if (currentParts.day_of_week == 0) {
            return dayTime == currentDay - 2 * 86400;
        }

        return false;
    }

    /**
     * 日足1本から、既存D表示と同じ丸め順序で値幅を計算する。
     */
    void readDailyRange(CurrencyStrengthDailyRangeInfo &fromInfo) {
        MqlRates rates[1];
        if (CopyRates(fromInfo.resolvedSymbolName, PERIOD_D1, 0, 1, rates) != 1
                || !this.isCurrentDay(rates[0].time)
                || !this.isPositivePrice(rates[0].high)
                || !this.isPositivePrice(rates[0].low)
                || rates[0].high < rates[0].low) {
            return;
        }

        double point = 0.0;
        long digits = 0;
        if (!SymbolInfoDouble(fromInfo.resolvedSymbolName, SYMBOL_POINT, point)
                || !this.isPositivePrice(point)
                || !SymbolInfoInteger(fromInfo.resolvedSymbolName, SYMBOL_DIGITS, digits)
                || digits < 1 || digits > 8) {
            return;
        }

        double pipSize = point * ZigZagElliotAnalysisProfile::getPipInPoints((int)digits);
        if (!this.isPositivePrice(pipSize)) {
            return;
        }

        double pips = NormalizeDouble((rates[0].high - rates[0].low) / pipSize,
            ZigZagElliotAnalysisProfile::getPipsResultDigits());
        double roundedPips = MathRound(pips);
        if (!MathIsValidNumber(roundedPips) || roundedPips < 0.0 || roundedPips > 2147483647.0) {
            return;
        }

        fromInfo.high = rates[0].high;
        fromInfo.low = rates[0].low;
        fromInfo.digits = (int)digits;
        fromInfo.pips = (int)roundedPips;
        fromInfo.dayTime = rates[0].time;
        fromInfo.rangeAvailable = true;
    }

    /**
     * 丸め済みのDを現在Bidで換算する。JPY建てはDと同じ値を返す。
     */
    void updateJpyRange(CurrencyStrengthDailyRangeInfo &fromInfo) {
        string quoteCurrency = StringSubstr(fromInfo.symbolName, 3, 3);
        if (quoteCurrency == "JPY") {
            fromInfo.jpyPips = fromInfo.pips;
            fromInfo.jpyAvailable = true;
            fromInfo.conversionRate = 1.0;
            fromInfo.conversionSymbolName = "JPY";

            return;
        }

        int quoteIndex = -1;
        for (int i = 0; i < 8; i++) {
            if (this.quoteCurrencies[i] == quoteCurrency) {
                quoteIndex = i;
                break;
            }
        }

        if (quoteIndex < 0) {
            return;
        }

        this.readConversion(quoteIndex);
        datetime quoteTime = this.conversionTimes[quoteIndex];
        if (!this.conversionAvailable[quoteIndex]
                || quoteTime < fromInfo.dayTime
                || quoteTime - quoteTime % 86400 != fromInfo.dayTime - fromInfo.dayTime % 86400) {
            return;
        }

        double converted = 100.0 * 0.0001 * (double)fromInfo.pips;
        string symbolName = this.directSymbolNames[quoteIndex];
        if (this.conversionInverse[quoteIndex]) {
            converted /= this.conversionBids[quoteIndex];
            symbolName = this.inverseSymbolNames[quoteIndex];
        } else {
            converted *= this.conversionBids[quoteIndex];
        }

        double roundedPips = MathRound(converted);
        if (!MathIsValidNumber(roundedPips) || roundedPips < 0.0 || roundedPips > 2147483647.0) {
            return;
        }

        fromInfo.jpyPips = (int)roundedPips;
        fromInfo.jpyAvailable = true;
        fromInfo.conversionRate = this.conversionBids[quoteIndex];
        fromInfo.conversionSymbolName = symbolName;
        fromInfo.inverseConversion = this.conversionInverse[quoteIndex];
        fromInfo.conversionTime = quoteTime;
    }

    /**
     * 同じ決済通貨の換算気配を一度だけ取得し、直接ペアを優先する。
     */
    void readConversion(const int fromIndex) {
        if (this.conversionChecked[fromIndex]) {
            return;
        }

        this.conversionChecked[fromIndex] = true;
        MqlTick tick;
        if (this.readConversionTick(this.quoteCurrencies[fromIndex] + "JPY",
                this.directSymbolNames[fromIndex], tick)) {
            this.conversionAvailable[fromIndex] = true;
        } else if (this.readConversionTick("JPY" + this.quoteCurrencies[fromIndex],
                this.inverseSymbolNames[fromIndex], tick)) {
            this.conversionAvailable[fromIndex] = true;
            this.conversionInverse[fromIndex] = true;
        }

        if (this.conversionAvailable[fromIndex]) {
            this.conversionBids[fromIndex] = tick.bid;
            this.conversionTimes[fromIndex] = tick.time;
        }
    }

    /**
     * キャッシュした実シンボルで正のBidと当日の気配時刻を確認する。
     */
    bool readConversionTick(const string fromCanonicalSymbol, string &fromResolvedSymbol, MqlTick &fromTick) {
        if (fromResolvedSymbol == "") {
            for (int i = 0; i < this.size(); i++) {
                if (this.rows[i].symbolName == fromCanonicalSymbol) {
                    fromResolvedSymbol = this.resolvedSymbolNames[i];
                    break;
                }
            }

            if (fromResolvedSymbol == "") {
                fromResolvedSymbol = this.resolveSymbolName(fromCanonicalSymbol);
            }
        }

        if (fromResolvedSymbol == "") {
            return false;
        }

        if (!SymbolSelect(fromResolvedSymbol, true)) {
            fromResolvedSymbol = "";

            return false;
        }

        return SymbolInfoTick(fromResolvedSymbol, fromTick)
            && this.isPositivePrice(fromTick.bid) && this.isCurrentDay(fromTick.time, TimeCurrent());
    }

    /**
     * 基準名の変更時だけ接頭辞・接尾辞と解決済み名を更新する。
     */
    void updateSymbolAffixes(const string fromReferenceSymbol) {
        if (this.referenceSymbolName == fromReferenceSymbol) {
            return;
        }

        this.referenceSymbolName = fromReferenceSymbol;
        this.symbolPrefix = "";
        this.symbolSuffix = "";
        for (int i = 0; i < this.size(); i++) {
            this.resolvedSymbolNames[i] = "";
            int position = StringFind(fromReferenceSymbol, this.rows[i].symbolName);
            if (position >= 0) {
                this.symbolPrefix = StringSubstr(fromReferenceSymbol, 0, position);
                this.symbolSuffix = StringSubstr(fromReferenceSymbol, position + 6);
            }
        }

        for (int i = 0; i < 8; i++) {
            this.directSymbolNames[i] = "";
            this.inverseSymbolNames[i] = "";
        }
    }

    /**
     * 正規名とメタデータが一致するシンボルを選択する。
     * 不一致だった未選択シンボルは元の非表示へ戻す。
     */
    bool selectMatchingSymbol(const string fromSymbolName, const string fromCanonicalSymbol) {
        bool isCustom = false;
        if (!SymbolExist(fromSymbolName, isCustom)) {
            return false;
        }

        bool wasSelected = (bool)SymbolInfoInteger(fromSymbolName, SYMBOL_SELECT);
        if (!SymbolSelect(fromSymbolName, true)) {
            return false;
        }

        if (SymbolInfoString(fromSymbolName, SYMBOL_CURRENCY_BASE) == StringSubstr(fromCanonicalSymbol, 0, 3)
                && SymbolInfoString(fromSymbolName, SYMBOL_CURRENCY_PROFIT) == StringSubstr(fromCanonicalSymbol, 3, 3)) {
            return true;
        }

        if (!wasSelected) {
            SymbolSelect(fromSymbolName, false);
        }

        return false;
    }

    /**
     * 基準チャートの接頭辞・接尾辞、完全一致、最短の一致候補の順で解決する。
     */
    string resolveSymbolName(const string fromCanonicalSymbol) {
        string preferredSymbol = this.symbolPrefix + fromCanonicalSymbol + this.symbolSuffix;
        if (this.selectMatchingSymbol(preferredSymbol, fromCanonicalSymbol)) {
            return preferredSymbol;
        }

        if (preferredSymbol != fromCanonicalSymbol
                && this.selectMatchingSymbol(fromCanonicalSymbol, fromCanonicalSymbol)) {
            return fromCanonicalSymbol;
        }

        string resolvedSymbol = "";
        bool resolvedWasSelected = false;
        int total = SymbolsTotal(false);
        for (int i = 0; i < total; i++) {
            string candidate = SymbolName(i, false);
            if (candidate == "" || StringFind(candidate, fromCanonicalSymbol) < 0
                    || (resolvedSymbol != "" && StringLen(candidate) >= StringLen(resolvedSymbol))) {
                continue;
            }

            bool wasSelected = (bool)SymbolInfoInteger(candidate, SYMBOL_SELECT);
            if (!this.selectMatchingSymbol(candidate, fromCanonicalSymbol)) {
                continue;
            }

            if (resolvedSymbol != "" && !resolvedWasSelected) {
                SymbolSelect(resolvedSymbol, false);
            }

            resolvedSymbol = candidate;
            resolvedWasSelected = wasSelected;
        }

        return resolvedSymbol;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_DAILY_RANGE_LIST_MQH
