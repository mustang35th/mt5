#ifndef MSTNG_CURRENCY_STRENGTH_RANK_HISTORY_SELECTION_MQH
#define MSTNG_CURRENCY_STRENGTH_RANK_HISTORY_SELECTION_MQH

#include <Mstng\Strength\CurrencyStrengthAllRankPoint.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>

/**
 * 同一チャートの履歴クリックを順位比較へ渡す表示専用スナップショット。
 * 時刻はlparam、方式（移動応答は要求ID）はdparam、順位と移動情報は63文字以内で渡す。
 */
struct CurrencyStrengthRankHistorySelection {
    /** 対象M5サーバー時刻。 */
    datetime m5BarTime;

    /** 集計ID。0は記録なし。 */
    long runId;

    /** LIVE・TESTER、または記録なしのNONE。 */
    string sourceMode;

    /** 最初にクリックした履歴インスタンス。旧形式は0。 */
    int sourceId;

    /** キャッシュ内の直前の有効点。0は移動不可。 */
    datetime previousTime;

    /** キャッシュ内の直後の有効点。0は移動不可。 */
    datetime nextTime;

    /** 固定順USD・JPY・EUR・GBP・AUD・NZD・CAD・CHFの長中期順位。 */
    int longMediumRanks[8];

    /** 同じ固定順の中短期順位。 */
    int mediumShortRanks[8];

    /**
     * 標準コントロールのイベントと区別する専用IDを返す。
     */
    static ushort eventId() { return 42101; }

    /**
     * キャッシュ内の前後移動要求のID。
     */
    static ushort navigationEventId() { return 42102; }

    /**
     * 要求IDを伴う移動応答のID。
     */
    static ushort navigationReplyEventId() { return 42103; }

    /**
     * 履歴インスタンスの終了通知ID。
     */
    static ushort sourceClosedEventId() { return 42104; }

    /**
     * 完全な保存順位があるか判定する。
     */
    bool hasRanks() const { return this.runId > 0; }

    /**
     * キャッシュの実順位を短いイベント文字列にする。無効点は記録なし。
     */
    static string encode(const CurrencyStrengthAllRankPoint &fromPoint) {
        if (!fromPoint.isValid()) {
            return "CSRH1|NONE|0|0000000000000000";
        }

        string currencies[8] = {"USD", "JPY", "EUR", "GBP", "AUD", "NZD", "CAD", "CHF"};
        string ranks = "";
        for (int i = 0; i < 8; i++) {
            ranks += IntegerToString(fromPoint.getLongMediumRank(currencies[i]));
            ranks += IntegerToString(fromPoint.getMediumShortRank(currencies[i]));
        }

        return "CSRH1|" + fromPoint.sourceMode + "|"
            + StringFormat("%I64d", fromPoint.runId) + "|" + ranks;
    }

    /**
     * 移動元・前後間隔付きの保存順位を固定長59文字へ変換する。
     * IDとM5単位の間隔を16進数にし、63文字制限内で一括転送する。
     */
    static string encodeNavigation(const CurrencyStrengthAllRankPoint &fromPoint,
            const int fromSourceId, const datetime fromTime,
            const datetime fromPreviousTime, const datetime fromNextTime) {
        string fields[];
        StringSplit(CurrencyStrengthRankHistorySelection::encode(fromPoint), '|', fields);
        string source = "N";
        if (fields[1] == "LIVE") {
            source = "L";
        } else if (fields[1] == "TESTER") {
            source = "T";
        }

        ulong previousGap = 0;
        ulong nextGap = 0;
        if (fromPreviousTime > 0 && fromPreviousTime < fromTime) {
            previousGap = (ulong)(fromTime - fromPreviousTime) / 300;
        }

        if (fromNextTime > fromTime) {
            nextGap = (ulong)(fromNextTime - fromTime) / 300;
        }

        return "R2" + source + CurrencyStrengthRankHistorySelection::toHex((ulong)StringToInteger(fields[2]), 16)
            + fields[3] + CurrencyStrengthRankHistorySelection::toHex((ulong)fromSourceId, 8)
            + CurrencyStrengthRankHistorySelection::toHex(previousGap, 8)
            + CurrencyStrengthRankHistorySelection::toHex(nextGap, 8);
    }

    /**
     * 形式・時刻・計算方式・全順位を確認してから受信値を反映する。
     * 不完全なイベントや異なる計算方式は表示を変更しない。
     */
    bool decode(const long fromTime, const double fromMode, const string fromPayload,
            const CurrencyStrengthVoteWeightMode fromExpectedMode) {
        if (fromTime <= 0 || fromTime % 300 != 0
                || !CurrencyStrengthCalculationProfile::isVoteWeightModeValid(fromExpectedMode)
                || fromMode != (double)fromExpectedMode || StringLen(fromPayload) > 63) {
            return false;
        }

        if (StringSubstr(fromPayload, 0, 2) == "R2") {
            return this.decodeNavigation(fromTime, fromMode, fromPayload, fromExpectedMode);
        }

        string fields[];
        if (StringSplit(fromPayload, '|', fields) != 4 || fields[0] != "CSRH1"
                || StringLen(fields[3]) != 16) {
            return false;
        }

        long nextRunId = StringToInteger(fields[2]);
        if (StringFormat("%I64d", nextRunId) != fields[2]
                || (fields[1] != "LIVE" && fields[1] != "TESTER" && fields[1] != "NONE")
                || (fields[1] == "NONE" && nextRunId != 0)
                || (fields[1] != "NONE" && nextRunId <= 0)) {
            return false;
        }

        for (int i = 0; i < 16; i++) {
            int rank = (int)StringGetCharacter(fields[3], i) - (int)'0';
            if ((nextRunId == 0 && rank != 0)
                    || (nextRunId > 0 && (rank < 1 || rank > 8))) {
                return false;
            }
        }

        this.m5BarTime = (datetime)fromTime;
        this.runId = nextRunId;
        this.sourceMode = fields[1];
        this.sourceId = 0;
        this.previousTime = 0;
        this.nextTime = 0;
        for (int i = 0; i < 8; i++) {
            this.longMediumRanks[i] = (int)StringGetCharacter(fields[3], i * 2) - (int)'0';
            this.mediumShortRanks[i] = (int)StringGetCharacter(fields[3], i * 2 + 1) - (int)'0';
        }

        return true;
    }

private:
    /**
     * 桁数固定の16進文字列を作る。
     */
    static string toHex(ulong fromValue, const int fromWidth) {
        string result = "";
        for (int i = 0; i < fromWidth; i++) {
            result = StringSubstr("0123456789ABCDEF", (int)(fromValue & 15), 1) + result;
            fromValue >>= 4;
        }

        return result;
    }

    /**
     * 大文字16進数だけを読み取る。
     */
    static bool readHex(const string fromText, ulong &fromValue) {
        fromValue = 0;
        for (int i = 0; i < StringLen(fromText); i++) {
            int digit = StringFind("0123456789ABCDEF", StringSubstr(fromText, i, 1));
            if (digit < 0) {
                return false;
            }

            fromValue = (fromValue << 4) | (ulong)digit;
        }

        return true;
    }

    /**
     * 移動情報を検証し、旧形式と共通の順位検証後にまとめて反映する。
     */
    bool decodeNavigation(const long fromTime, const double fromMode, const string fromPayload,
            const CurrencyStrengthVoteWeightMode fromExpectedMode) {
        if (StringLen(fromPayload) != 59) {
            return false;
        }

        ulong nextRunId = 0;
        ulong nextSourceId = 0;
        ulong previousGap = 0;
        ulong nextGap = 0;
        if (!this.readHex(StringSubstr(fromPayload, 3, 16), nextRunId)
                || nextRunId > 9223372036854775807
                || !this.readHex(StringSubstr(fromPayload, 35, 8), nextSourceId)
                || nextSourceId == 0 || nextSourceId > 2147483647
                || !this.readHex(StringSubstr(fromPayload, 43, 8), previousGap)
                || !this.readHex(StringSubstr(fromPayload, 51, 8), nextGap)
                || (previousGap > 0 && previousGap * 300 >= (ulong)fromTime)) {
            return false;
        }

        string source = "";
        string code = StringSubstr(fromPayload, 2, 1);
        if (code == "L") {
            source = "LIVE";
        } else if (code == "T") {
            source = "TESTER";
        } else if (code == "N") {
            source = "NONE";
        }

        string legacy = "CSRH1|" + source + "|" + StringFormat("%I64d", (long)nextRunId)
            + "|" + StringSubstr(fromPayload, 19, 16);
        if (!this.decode(fromTime, fromMode, legacy, fromExpectedMode)) {
            return false;
        }

        this.sourceId = (int)nextSourceId;
        if (previousGap > 0) {
            this.previousTime = (datetime)(fromTime - (long)previousGap * 300);
        }

        if (nextGap > 0) {
            this.nextTime = (datetime)(fromTime + (long)nextGap * 300);
        }

        return true;
    }
};

#endif // MSTNG_CURRENCY_STRENGTH_RANK_HISTORY_SELECTION_MQH
