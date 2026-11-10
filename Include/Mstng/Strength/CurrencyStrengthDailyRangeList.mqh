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
 * LIVEの28通貨ペアの当日・5日平均値幅と円換算をまとめて取得する。
 * 日足は各最大14本、換算気配は決済通貨ごとに1回だけ取得する。
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
     * 当日・直近5平日の値幅と、現在気配による円換算値を更新する。
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
            if (this.rows[i].rangeAvailable || this.rows[i].averageAvailable) {
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
     * 日足をまとめて取得し、当日と平均をそれぞれ独立して計算する。
     * 履歴の準備待ちで従来の当日表示まで失わないよう、必要な場合だけ1本取得を試す。
     */
    void readDailyRange(CurrencyStrengthDailyRangeInfo &fromInfo) {
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

        fromInfo.digits = (int)digits;
        MqlRates rates[14];
        int copied = CopyRates(fromInfo.resolvedSymbolName, PERIOD_D1, 0, 14, rates);
        bool currentBarFound = false;
        if (copied > 0) {
            // CopyRatesの物理配列は古い足から並ぶ。
            currentBarFound = this.isCurrentDay(rates[copied - 1].time);
            if (currentBarFound) {
                this.setCurrentRange(fromInfo, rates[copied - 1], pipSize);
            }

            this.setAverageRange(fromInfo, rates, copied, pipSize);
        }

        if (!currentBarFound) {
            MqlRates currentRates[1];
            if (CopyRates(fromInfo.resolvedSymbolName, PERIOD_D1, 0, 1, currentRates) == 1
                    && this.isCurrentDay(currentRates[0].time)) {
                this.setCurrentRange(fromInfo, currentRates[0], pipSize);
            }
        }
    }

    /**
     * 正常な高値・安値の差を、丸め前のpipsで返す。
     */
    bool getRawPips(const MqlRates &fromRate, const double fromPipSize, double &fromPips) const {
        fromPips = 0.0;
        if (!this.isPositivePrice(fromRate.high) || !this.isPositivePrice(fromRate.low)
                || fromRate.high < fromRate.low) {
            return false;
        }

        fromPips = (fromRate.high - fromRate.low) / fromPipSize;

        return MathIsValidNumber(fromPips) && fromPips != EMPTY_VALUE && fromPips >= 0.0;
    }

    /**
     * 既存D表示と同じ小数1桁の正規化後、整数pipsへ丸める。
     */
    bool roundPips(const double fromPips, int &fromRoundedPips) const {
        if (!MathIsValidNumber(fromPips) || fromPips == EMPTY_VALUE || fromPips < 0.0) {
            return false;
        }

        double roundedPips = MathRound(NormalizeDouble(fromPips,
            ZigZagElliotAnalysisProfile::getPipsResultDigits()));
        if (!MathIsValidNumber(roundedPips) || roundedPips < 0.0 || roundedPips > 2147483647.0) {
            return false;
        }

        fromRoundedPips = (int)roundedPips;

        return true;
    }

    /**
     * 当日として確認済みの日足を、既存D表示と同じ計算で反映する。
     */
    void setCurrentRange(CurrencyStrengthDailyRangeInfo &fromInfo,
            const MqlRates &fromRate, const double fromPipSize) {
        double rawPips = 0.0;
        if (!this.getRawPips(fromRate, fromPipSize, rawPips)
                || !this.roundPips(rawPips, fromInfo.pips)) {
            return;
        }

        fromInfo.high = fromRate.high;
        fromInfo.low = fromRate.low;
        fromInfo.dayTime = fromRate.time;
        fromInfo.rangeAvailable = true;
    }

    /**
     * 当日より前の平日D1を新しい順に5本選び、生pipsを平均する。
     * 対象内の価格異常は件数不足とし、さらに古い6本目で補わない。
     */
    void setAverageRange(CurrencyStrengthDailyRangeInfo &fromInfo,
            const MqlRates &fromRates[], const int fromCount, const double fromPipSize) {
        datetime currentDay = this.updatedAt - this.updatedAt % 86400;
        int selectedCount = 0;
        double totalPips = 0.0;
        for (int i = fromCount - 1; i >= 0 && selectedCount < 5; i--) {
            MqlDateTime dayParts;
            if (fromRates[i].time <= 0 || !TimeToStruct(fromRates[i].time, dayParts)) {
                // 日付を分類できない足を飛ばして対象期間を延ばさない。
                return;
            }

            if (fromRates[i].time >= currentDay
                    || dayParts.day_of_week == 0 || dayParts.day_of_week == 6) {
                continue;
            }

            selectedCount++;
            double rawPips = 0.0;
            if (!this.getRawPips(fromRates[i], fromPipSize, rawPips)) {
                continue;
            }

            fromInfo.averageDayCount++;
            fromInfo.averageStartTime = fromRates[i].time;
            if (fromInfo.averageEndTime == 0) {
                fromInfo.averageEndTime = fromRates[i].time;
            }

            totalPips += rawPips;
        }

        if (fromInfo.averageDayCount == 5
                && this.roundPips(totalPips / 5.0, fromInfo.averagePips)) {
            fromInfo.averageAvailable = true;
        }
    }

    /**
     * 丸め済みの当日・5日平均を、同じ現在Bidでそれぞれ独立して換算する。
     */
    void updateJpyRange(CurrencyStrengthDailyRangeInfo &fromInfo) {
        string quoteCurrency = StringSubstr(fromInfo.symbolName, 3, 3);
        if (quoteCurrency == "JPY") {
            if (fromInfo.rangeAvailable) {
                fromInfo.jpyPips = fromInfo.pips;
                fromInfo.jpyAvailable = true;
            }

            if (fromInfo.averageAvailable) {
                fromInfo.averageJpyPips = fromInfo.averagePips;
                fromInfo.averageJpyAvailable = true;
            }

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
        if (!this.conversionAvailable[quoteIndex]) {
            return;
        }

        if (fromInfo.rangeAvailable && quoteTime >= fromInfo.dayTime
                && quoteTime - quoteTime % 86400 == fromInfo.dayTime - fromInfo.dayTime % 86400) {
            fromInfo.jpyAvailable = this.convertPips(fromInfo.pips, quoteIndex, fromInfo.jpyPips);
        }

        if (fromInfo.averageAvailable) {
            fromInfo.averageJpyAvailable = this.convertPips(
                fromInfo.averagePips, quoteIndex, fromInfo.averageJpyPips);
        }

        if (!fromInfo.jpyAvailable && !fromInfo.averageJpyAvailable) {
            return;
        }

        fromInfo.conversionRate = this.conversionBids[quoteIndex];
        fromInfo.conversionSymbolName = this.directSymbolNames[quoteIndex];
        fromInfo.inverseConversion = this.conversionInverse[quoteIndex];
        if (fromInfo.inverseConversion) {
            fromInfo.conversionSymbolName = this.inverseSymbolNames[quoteIndex];
        }

        fromInfo.conversionTime = quoteTime;
    }

    /**
     * 既存D Jpyの演算順序で整数pipsを円換算し、整数へ丸める。
     */
    bool convertPips(const int fromPips, const int fromQuoteIndex, int &fromJpyPips) const {
        double converted = 100.0 * 0.0001 * (double)fromPips;
        if (this.conversionInverse[fromQuoteIndex]) {
            converted /= this.conversionBids[fromQuoteIndex];
        } else {
            converted *= this.conversionBids[fromQuoteIndex];
        }

        double roundedPips = MathRound(converted);
        if (!MathIsValidNumber(roundedPips) || roundedPips < 0.0 || roundedPips > 2147483647.0) {
            return false;
        }

        fromJpyPips = (int)roundedPips;

        return true;
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
