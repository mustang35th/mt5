#ifndef __MARKET_ACTIVITY_ANALYZER_MQH__
#define __MARKET_ACTIVITY_ANALYZER_MQH__

/** JSTオフセット秒。 */
const int MARKET_ACTIVITY_ANALYZER_JST_OFFSET_SECONDS = 9 * 60 * 60;

/** デフォルト対象通貨ペアCSV。 */
const string MARKET_ACTIVITY_ANALYZER_DEFAULT_SYMBOLS_CSV =
    "EURUSD,USDJPY,GBPUSD,AUDUSD,USDCAD,USDCHF,NZDUSD,EURJPY,GBPJPY,AUDJPY";

/**
 * 市場活発度レベル。
 */
enum MarketActivityLevel {
    MARKET_ACTIVITY_CALM = 0,
    MARKET_ACTIVITY_NORMAL,
    MARKET_ACTIVITY_ACTIVE,
    MARKET_ACTIVITY_DANGER
};

/**
 * FX市場の活発度を判定するクラス。
 *
 * <p>複数通貨ペアの M1 レンジ拡大率、スプレッド比、
 * ロンドン/ニューヨークの夏時間・冬時間を考慮した
 * セッション補正を用いて市場の活発さを評価します。</p>
 */
class MarketActivityAnalyzer {
public:
    /**
     * @brief コンストラクタ。
     *
     * @param fromSymbolsCsv 対象通貨ペアCSV。空文字ならデフォルトを使用
     * @param fromFastBars 直近レンジ判定本数
     * @param fromSlowBars 基準レンジ判定本数
     * @param fromActiveThreshold 活発判定閾値
     * @param fromCalmThreshold 閑散判定閾値
     * @param fromDangerSpreadRatio 危険スプレッド比
     * @param fromSpreadPenaltyWeight スプレッド減点係数
     * @param fromUseSessionAdjustment セッション補正使用フラグ
     */
    MarketActivityAnalyzer(
        const string fromSymbolsCsv = "",
        const int fromFastBars = 5,
        const int fromSlowBars = 50,
        const double fromActiveThreshold = 1.20,
        const double fromCalmThreshold = 0.80,
        const double fromDangerSpreadRatio = 2.00,
        const double fromSpreadPenaltyWeight = 0.20,
        const bool fromUseSessionAdjustment = true
    ) {
        this.fastBars = fromFastBars;
        this.slowBars = fromSlowBars;
        this.activeThreshold = fromActiveThreshold;
        this.calmThreshold = fromCalmThreshold;
        this.dangerSpreadRatio = fromDangerSpreadRatio;
        this.spreadPenaltyWeight = fromSpreadPenaltyWeight;
        this.useSessionAdjustment = fromUseSessionAdjustment;

        string actualSymbolsCsv = fromSymbolsCsv;
        if (actualSymbolsCsv == "") {
            actualSymbolsCsv = MARKET_ACTIVITY_ANALYZER_DEFAULT_SYMBOLS_CSV;
        }

        this.setSymbolsFromCsv(actualSymbolsCsv);
        this.resetState();
    }

    /**
     * @brief 市場活発度を更新します。
     *
     * @return 更新成功なら true
     */
    bool update() {
        this.resetState();

        if (this.symbolCount <= 0) {
            return false;
        }

        double totalRangeRatio = 0.0;
        double totalSpreadRatio = 0.0;
        int validCount = 0;

        for (int i = 0; i < this.symbolCount; i++) {
            double rangeRatio = 0.0;
            double spreadRatio = 1.0;

            if (!this.getSymbolMetrics(this.symbols[i], rangeRatio, spreadRatio)) {
                continue;
            }

            totalRangeRatio += rangeRatio;
            totalSpreadRatio += spreadRatio;
            validCount++;
        }

        if (validCount <= 0) {
            return false;
        }

        this.lastValidSymbols = validCount;
        this.lastRangeScore = totalRangeRatio / validCount;
        this.lastSpreadRatio = totalSpreadRatio / validCount;

        double spreadPenalty = 0.0;
        if (this.lastSpreadRatio > 1.0) {
            spreadPenalty = (this.lastSpreadRatio - 1.0) * this.spreadPenaltyWeight;
        }

        this.lastScore = this.lastRangeScore - spreadPenalty + this.getSessionAdjustment();
        this.lastLevel = this.judgeLevel(this.lastScore, this.lastSpreadRatio);

        return true;
    }

    /**
     * @brief 活発状態か判定します。
     *
     * @return 活発なら true
     */
    bool isActive() const {
        return this.lastLevel == MARKET_ACTIVITY_ACTIVE;
    }

    /**
     * @brief 危険状態か判定します。
     *
     * @return 危険なら true
     */
    bool isDanger() const {
        return this.lastLevel == MARKET_ACTIVITY_DANGER;
    }

    /**
     * @brief 閑散状態か判定します。
     *
     * @return 閑散なら true
     */
    bool isCalm() const {
        return this.lastLevel == MARKET_ACTIVITY_CALM;
    }

    /**
     * @brief 市場レベルを返します。
     *
     * @return 市場活発度レベル
     */
    MarketActivityLevel getLevel() const {
        return this.lastLevel;
    }

    /**
     * @brief 総合スコアを返します。
     *
     * @return 総合スコア
     */
    double getScore() const {
        return this.lastScore;
    }

    /**
     * @brief レンジスコアを返します。
     *
     * @return レンジスコア
     */
    double getRangeScore() const {
        return this.lastRangeScore;
    }

    /**
     * @brief スプレッド比を返します。
     *
     * @return スプレッド比
     */
    double getSpreadRatio() const {
        return this.lastSpreadRatio;
    }

    /**
     * @brief 有効シンボル数を返します。
     *
     * @return 有効シンボル数
     */
    int getValidSymbols() const {
        return this.lastValidSymbols;
    }

    /**
     * @brief 市場レベルの文字列表現を返します。
     *
     * @return レベル文字列
     */
    string getLevelLabel() const {
        switch (this.lastLevel) {
            case MARKET_ACTIVITY_CALM:
                return "CALM";
            case MARKET_ACTIVITY_NORMAL:
                return "NORMAL";
            case MARKET_ACTIVITY_ACTIVE:
                return "ACTIVE";
            case MARKET_ACTIVITY_DANGER:
                return "DANGER";
        }

        return "UNKNOWN";
    }
    
    /**
     * @brief 現在の市場レベルに対応する色を返します。
     *
     * @return 表示色
     */
    color getLevelColor() const {
        return getLevelColor(this.lastLevel);
    }

    /**
     * @brief 指定した市場レベルに対応する色を返します。
     *
     * @param level 市場活発度レベル
     * @return 表示色
     */
    static color getLevelColor(const MarketActivityLevel level) {
        switch (level) {
            case MARKET_ACTIVITY_CALM:
                return clrSilver;

            case MARKET_ACTIVITY_NORMAL:
                return clrWhite;

            case MARKET_ACTIVITY_ACTIVE:
                return clrDodgerBlue;

            case MARKET_ACTIVITY_DANGER:
                return clrTomato;
        }

        return clrWhite;
    }

    /**
     * @brief 内容を文字列化して返します。
     *
     * @return 状態文字列
     */
    string toString() const {
        return StringFormat(
            "MarketActivity{level=%s, score=%.2f, rangeScore=%.2f, spreadRatio=%.2f, validSymbols=%d}",
            this.getLevelLabel(),
            this.lastScore,
            this.lastRangeScore,
            this.lastSpreadRatio,
            this.lastValidSymbols
        );
    }

private:
    string symbols[];
    int symbolCount;

    int fastBars;
    int slowBars;
    double activeThreshold;
    double calmThreshold;
    double dangerSpreadRatio;
    double spreadPenaltyWeight;
    bool useSessionAdjustment;

    double lastScore;
    double lastRangeScore;
    double lastSpreadRatio;
    int lastValidSymbols;
    MarketActivityLevel lastLevel;

    /**
     * @brief 内部状態を初期化します。
     */
    void resetState() {
        this.lastScore = 0.0;
        this.lastRangeScore = 0.0;
        this.lastSpreadRatio = 1.0;
        this.lastValidSymbols = 0;
        this.lastLevel = MARKET_ACTIVITY_NORMAL;
    }

    /**
     * @brief CSV文字列から通貨ペア配列を設定します。
     *
     * @param symbolsCsv 通貨ペアCSV
     */
    void setSymbolsFromCsv(const string symbolsCsv) {
        ArrayResize(this.symbols, 0);
        this.symbolCount = 0;

        string parts[];
        int count = StringSplit(symbolsCsv, ',', parts);
        if (count <= 0) {
            return;
        }

        for (int i = 0; i < count; i++) {
            string symbol = parts[i];
            StringTrimLeft(symbol);
            StringTrimRight(symbol);

            if (symbol == "") {
                continue;
            }

            int newSize = ArraySize(this.symbols) + 1;
            ArrayResize(this.symbols, newSize);
            this.symbols[newSize - 1] = symbol;
        }

        this.symbolCount = ArraySize(this.symbols);
    }

    /**
     * @brief 現在のスプレッドを point 単位で返します。
     *
     * @param symbolName 通貨ペア名
     * @return スプレッド
     */
    double getCurrentSpreadPoints(const string symbolName) {
        double spreadPoints = (double)SymbolInfoInteger(symbolName, SYMBOL_SPREAD);
        if (spreadPoints > 0.0) {
            return spreadPoints;
        }

        double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
        double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
        double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);

        if (point <= 0.0 || ask <= 0.0 || bid <= 0.0) {
            return 0.0;
        }

        return (ask - bid) / point;
    }

    /**
     * @brief 指定通貨ペアのレンジ比とスプレッド比を取得します。
     *
     * @param symbolName 通貨ペア名
     * @param rangeRatio レンジ比
     * @param spreadRatio スプレッド比
     * @return 取得成功なら true
     */
    bool getSymbolMetrics(const string symbolName, double &rangeRatio, double &spreadRatio) {
        rangeRatio = 0.0;
        spreadRatio = 1.0;

        if (!SymbolSelect(symbolName, true)) {
            return false;
        }

        int requiredBars = this.slowBars + 5;

        MqlRates rates[];
        ArraySetAsSeries(rates, true);

        int copied = CopyRates(symbolName, PERIOD_M1, 0, requiredBars, rates);
        if (copied < this.slowBars + 2) {
            return false;
        }

        double fastRangeSum = 0.0;
        double slowRangeSum = 0.0;
        int fastCount = 0;
        int slowCount = 0;

        for (int i = 1; i <= this.slowBars && i < copied; i++) {
            double barRange = rates[i].high - rates[i].low;
            if (barRange <= 0.0) {
                continue;
            }

            slowRangeSum += barRange;
            slowCount++;

            if (i <= this.fastBars) {
                fastRangeSum += barRange;
                fastCount++;
            }
        }

        if (fastCount == 0 || slowCount == 0) {
            return false;
        }

        double fastAverageRange = fastRangeSum / fastCount;
        double slowAverageRange = slowRangeSum / slowCount;

        if (slowAverageRange <= 0.0) {
            return false;
        }

        rangeRatio = fastAverageRange / slowAverageRange;

        double currentSpread = this.getCurrentSpreadPoints(symbolName);
        if (currentSpread <= 0.0) {
            spreadRatio = 1.0;
        } else {
            double spreadSum = 0.0;
            int spreadCount = 0;

            for (int i = 1; i <= this.slowBars && i < copied; i++) {
                if (rates[i].spread > 0) {
                    spreadSum += rates[i].spread;
                    spreadCount++;
                }
            }

            if (spreadCount > 0) {
                double averageSpread = spreadSum / spreadCount;
                spreadRatio = (averageSpread > 0.0) ? (currentSpread / averageSpread) : 1.0;
            } else {
                spreadRatio = 1.0;
            }
        }

        rangeRatio = MathMin(rangeRatio, 3.0);
        spreadRatio = MathMin(spreadRatio, 5.0);

        return true;
    }

    /**
     * @brief セッション補正値を返します。
     *
     * <p>ロンドン/ニューヨークの夏時間・冬時間を考慮して、
     * 活発になりやすい時間帯を UTC 基準で補正します。</p>
     *
     * @return セッション補正値
     */
    double getSessionAdjustment() const {
        if (!this.useSessionAdjustment) {
            return 0.0;
        }

        datetime nowUtc = TimeGMT();

        bool londonDst = isLondonDstUtc(nowUtc);
        bool newYorkDst = isNewYorkDstUtc(nowUtc);

        int londonOpenUtc = londonDst ? 7 : 8;
        int londonCloseUtc = londonDst ? 16 : 17;

        int newYorkOpenUtc = newYorkDst ? 12 : 13;
        int newYorkCloseUtc = newYorkDst ? 21 : 22;

        MqlDateTime utcStruct;
        TimeToStruct(nowUtc, utcStruct);
        int utcHour = utcStruct.hour;

        int overlapStartUtc = MathMax(londonOpenUtc, newYorkOpenUtc);
        int overlapEndUtc = MathMin(londonCloseUtc, newYorkCloseUtc);

        if (utcHour >= overlapStartUtc && utcHour < overlapEndUtc) {
            return 0.10;
        }

        if (utcHour >= londonOpenUtc && utcHour < MathMin(londonOpenUtc + 4, londonCloseUtc)) {
            return 0.05;
        }

        if (utcHour >= newYorkOpenUtc && utcHour < MathMin(newYorkOpenUtc + 3, newYorkCloseUtc)) {
            return 0.05;
        }

        datetime nowJst = nowUtc + MARKET_ACTIVITY_ANALYZER_JST_OFFSET_SECONDS;
        MqlDateTime jstStruct;
        TimeToStruct(nowJst, jstStruct);

        if (jstStruct.hour >= 6 && jstStruct.hour <= 8) {
            return -0.05;
        }

        return 0.0;
    }

    /**
     * @brief スコアとスプレッド比から市場レベルを判定します。
     *
     * @param score 総合スコア
     * @param spreadRatio スプレッド比
     * @return 市場活発度レベル
     */
    MarketActivityLevel judgeLevel(const double score, const double spreadRatio) const {
        if (spreadRatio >= this.dangerSpreadRatio) {
            return MARKET_ACTIVITY_DANGER;
        }

        if (score >= this.activeThreshold) {
            return MARKET_ACTIVITY_ACTIVE;
        }

        if (score <= this.calmThreshold) {
            return MARKET_ACTIVITY_CALM;
        }

        return MARKET_ACTIVITY_NORMAL;
    }
};

/**
 * @brief うるう年か判定します。
 *
 * @param year 年
 * @return うるう年なら true
 */
bool isLeapYear(const int year) {
    if ((year % 400) == 0) {
        return true;
    }

    if ((year % 100) == 0) {
        return false;
    }

    return (year % 4) == 0;
}

/**
 * @brief 指定年月の日数を返します。
 *
 * @param year 年
 * @param month 月
 * @return 日数
 */
int getDaysInMonth(const int year, const int month) {
    switch (month) {
        case 1: return 31;
        case 2: return isLeapYear(year) ? 29 : 28;
        case 3: return 31;
        case 4: return 30;
        case 5: return 31;
        case 6: return 30;
        case 7: return 31;
        case 8: return 31;
        case 9: return 30;
        case 10: return 31;
        case 11: return 30;
        case 12: return 31;
    }

    return 30;
}

/**
 * @brief UTC基準で月内の第n曜日の日付を返します。
 *
 * <p>weekday は MqlDateTime.day_of_week と同じで、0=日曜です。</p>
 *
 * @param year 年
 * @param month 月
 * @param weekday 曜日
 * @param nth 第n
 * @return 日付
 */
int getNthWeekdayOfMonthUtc(const int year, const int month, const int weekday, const int nth) {
    MqlDateTime firstDateTime;
    firstDateTime.year = year;
    firstDateTime.mon = month;
    firstDateTime.day = 1;
    firstDateTime.hour = 0;
    firstDateTime.min = 0;
    firstDateTime.sec = 0;

    datetime firstTime = StructToTime(firstDateTime);

    MqlDateTime firstStruct;
    TimeToStruct(firstTime, firstStruct);

    int offset = weekday - firstStruct.day_of_week;
    if (offset < 0) {
        offset += 7;
    }

    return 1 + offset + (nth - 1) * 7;
}

/**
 * @brief UTC基準で月内の最後の曜日の日付を返します。
 *
 * <p>weekday は MqlDateTime.day_of_week と同じで、0=日曜です。</p>
 *
 * @param year 年
 * @param month 月
 * @param weekday 曜日
 * @return 日付
 */
int getLastWeekdayOfMonthUtc(const int year, const int month, const int weekday) {
    int lastDay = getDaysInMonth(year, month);

    MqlDateTime lastDateTime;
    lastDateTime.year = year;
    lastDateTime.mon = month;
    lastDateTime.day = lastDay;
    lastDateTime.hour = 0;
    lastDateTime.min = 0;
    lastDateTime.sec = 0;

    datetime lastTime = StructToTime(lastDateTime);

    MqlDateTime lastStruct;
    TimeToStruct(lastTime, lastStruct);

    int offset = lastStruct.day_of_week - weekday;
    if (offset < 0) {
        offset += 7;
    }

    return lastDay - offset;
}

/**
 * @brief ロンドンが夏時間かUTC時刻で判定します。
 *
 * <p>BST は 3月最終日曜 01:00 UTC 開始、10月最終日曜 01:00 UTC 終了です。</p>
 *
 * @param utcTime UTC時刻
 * @return 夏時間なら true
 */
bool isLondonDstUtc(const datetime utcTime) {
    MqlDateTime nowStruct;
    TimeToStruct(utcTime, nowStruct);

    int startDay = getLastWeekdayOfMonthUtc(nowStruct.year, 3, 0);
    int endDay = getLastWeekdayOfMonthUtc(nowStruct.year, 10, 0);

    MqlDateTime startStruct;
    startStruct.year = nowStruct.year;
    startStruct.mon = 3;
    startStruct.day = startDay;
    startStruct.hour = 1;
    startStruct.min = 0;
    startStruct.sec = 0;

    MqlDateTime endStruct;
    endStruct.year = nowStruct.year;
    endStruct.mon = 10;
    endStruct.day = endDay;
    endStruct.hour = 1;
    endStruct.min = 0;
    endStruct.sec = 0;

    datetime startTime = StructToTime(startStruct);
    datetime endTime = StructToTime(endStruct);

    return utcTime >= startTime && utcTime < endTime;
}

/**
 * @brief ニューヨークが夏時間かUTC時刻で判定します。
 *
 * <p>米東部時間の DST は 3月第2日曜 07:00 UTC 開始、
 * 11月第1日曜 06:00 UTC 終了です。</p>
 *
 * @param utcTime UTC時刻
 * @return 夏時間なら true
 */
bool isNewYorkDstUtc(const datetime utcTime) {
    MqlDateTime nowStruct;
    TimeToStruct(utcTime, nowStruct);

    int startDay = getNthWeekdayOfMonthUtc(nowStruct.year, 3, 0, 2);
    int endDay = getNthWeekdayOfMonthUtc(nowStruct.year, 11, 0, 1);

    MqlDateTime startStruct;
    startStruct.year = nowStruct.year;
    startStruct.mon = 3;
    startStruct.day = startDay;
    startStruct.hour = 7;
    startStruct.min = 0;
    startStruct.sec = 0;

    MqlDateTime endStruct;
    endStruct.year = nowStruct.year;
    endStruct.mon = 11;
    endStruct.day = endDay;
    endStruct.hour = 6;
    endStruct.min = 0;
    endStruct.sec = 0;

    datetime startTime = StructToTime(startStruct);
    datetime endTime = StructToTime(endStruct);

    return utcTime >= startTime && utcTime < endTime;
}

#endif // __MARKET_ACTIVITY_ANALYZER_MQH__
