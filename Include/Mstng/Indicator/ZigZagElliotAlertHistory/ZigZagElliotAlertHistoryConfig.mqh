#ifndef MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_CONFIG_MQH
#define MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_CONFIG_MQH

/**
 * 履歴チャートで表示する上位足数。
 */
enum ZigZagElliotAlertHistoryHigherCount {
    ALERT_HISTORY_HIGHER_TWO = 2, // M15・H1
    ALERT_HISTORY_HIGHER_THREE = 3 // M15・H1・H4
};

/**
 * 保存済みM5アラートの検索条件と表示設定を保持する。
 */
class ZigZagElliotAlertHistoryConfig {
public:
    /** Alert DBファイル名。 */
    string databaseFileName;
    /** CommonフォルダのDBを読む場合true。 */
    bool useCommonFolder;
    /** Run ID。0は検索条件に一致する最新Run一つを選ぶ。 */
    long runId;
    /** 表示開始日。サーバー日付で0は制限なし。 */
    datetime startDate;
    /** 表示終了日。当日を含み、0は制限なし。 */
    datetime endDate;
    /** ENTRY成立だけを検索する場合true。 */
    bool entryOnly;
    /** 現在足に加えて表示する上位足数。 */
    int higherCount;
    /** 参照価格・SL候補・FEを表示する場合true。 */
    bool showPrices;
    /** 保存された各時間足の情報表を表示する場合true。 */
    bool showTable;

    /**
     * 既定の検索条件を初期化する。
     */
    ZigZagElliotAlertHistoryConfig() {
        this.databaseFileName = "mstng-zigzag-elliot-alert.sqlite";
        this.useCommonFolder = true;
        this.runId = 0;
        this.startDate = 0;
        this.endDate = 0;
        this.entryOnly = false;
        this.higherCount = 3;
        this.showPrices = true;
        this.showTable = true;
    }

    /**
     * 日付を開始日以上・終了日の翌日未満の検索区間へ変換する。
     * 入力に時刻が付いていても、表示日付の午前0時を基準にする。
     *
     * @param fromStartTime 開始日午前0時の出力先。
     * @param fromEndTime 終了日の翌日午前0時の出力先。
     * @param fromError 不正な設定の説明。
     * @return 有効な設定の場合true。
     */
    bool getPeriod(datetime &fromStartTime, datetime &fromEndTime, string &fromError) {
        fromStartTime = 0;
        fromEndTime = 0;
        fromError = "";
        if (this.databaseFileName == "" || this.runId < 0
                || this.startDate < 0 || this.endDate < 0
                || (this.higherCount != 2 && this.higherCount != 3)) {
            fromError = "DBファイル名・Run・日付・上位足数の設定を確認してください。";
            return false;
        }
        if (!this.getDayStart(this.startDate, fromStartTime)
                || !this.getDayStart(this.endDate, fromEndTime)) {
            fromError = "表示期間の日付を読み取れません。";
            return false;
        }
        if (fromStartTime > 0 && fromEndTime > 0 && fromStartTime > fromEndTime) {
            fromError = "表示開始日を表示終了日以前にしてください。";
            return false;
        }
        if (fromEndTime > 0) {
            fromEndTime += 86400;
        }
        return true;
    }

private:
    /**
     * サーバー日付の午前0時を取得する。0は無制限として保持する。
     */
    bool getDayStart(const datetime fromDate, datetime &fromDayStart) {
        fromDayStart = 0;
        if (fromDate == 0) {
            return true;
        }
        MqlDateTime dateParts;
        if (!TimeToStruct(fromDate, dateParts)) {
            return false;
        }
        dateParts.hour = 0;
        dateParts.min = 0;
        dateParts.sec = 0;
        fromDayStart = StructToTime(dateParts);
        return fromDayStart > 0;
    }
};

#endif
