/**
 * Package: MstngEa.Logging
 * File: TradeCsvLogger.mqh
 */

#ifndef MSTNGEA_LOGGING_TRADECLSVLOGGER_MQH
#define MSTNGEA_LOGGING_TRADECLSVLOGGER_MQH

/**
 * 取引結果CSV出力
 */
class TradeCsvLogger {
public:
    /** シンボル名 */
    string symbolName;

    /** 時間足 */
    ENUM_TIMEFRAMES timeFrame;

    /** マジックナンバー */
    ulong magicNumber;

    /**
     * コンストラクタ
     *
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param magicNumberValue マジックナンバー
     */
    TradeCsvLogger(
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue,
        ulong magicNumberValue
    ) {
        // 基本情報を保持
        this.symbolName = symbolNameValue;
        this.timeFrame = timeFrameValue;
        this.magicNumber = magicNumberValue;
    }

    /**
     * ヘッダー出力
     */
    void writeHeaderIfNeeded() {
        // 出力先を取得
        string currentFilePath = this.buildFilePath();

        int fileHandle = FileOpen(
            currentFilePath,
            FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_WRITE
        );

        if (fileHandle == INVALID_HANDLE) {
            Print("TradeCsvLogger FileOpen failed: " + currentFilePath);
            return;
        }

        if (FileSize(fileHandle) == 0) {
            string headerLine = "jst_time";
            headerLine += ",server_time";
            headerLine += ",symbol";
            headerLine += ",timeframe";
            headerLine += ",magic";
            headerLine += ",strategy";
            headerLine += ",action";
            headerLine += ",side";
            headerLine += ",volume";
            headerLine += ",price";
            headerLine += ",position_ticket";
            headerLine += ",deal_ticket";
            headerLine += ",profit";
            headerLine += ",reason";
            headerLine += ",entry_csv_text";

            // ヘッダーを出力
            this.writeLine(fileHandle, headerLine);
        }

        FileClose(fileHandle);
    }

    /**
     * 取引結果出力
     *
     * @param strategyNameValue 戦略名
     * @param actionValue 操作種別
     * @param sideValue 売買方向
     * @param volumeValue 数量
     * @param priceValue 価格
     * @param positionTicketValue ポジションチケット
     * @param dealTicketValue 約定チケット
     * @param profitValue 損益
     * @param reasonValue 理由
     * @param csvTextValue 追加CSV情報
     */
    void writeTrade(
        string strategyNameValue,
        string actionValue,
        string sideValue,
        double volumeValue,
        double priceValue,
        ulong positionTicketValue,
        ulong dealTicketValue,
        double profitValue,
        string reasonValue,
        string csvTextValue = ""
    ) {
        // 先頭ヘッダーを保証
        this.writeHeaderIfNeeded();

        string currentFilePath = this.buildFilePath();
        int fileHandle = FileOpen(
            currentFilePath,
            FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_WRITE
        );

        if (fileHandle == INVALID_HANDLE) {
            Print("TradeCsvLogger FileOpen failed: " + currentFilePath);
            return;
        }

        // 追記位置へ移動
        FileSeek(fileHandle, 0, SEEK_END);

        datetime serverTime = TimeCurrent();
        datetime jstTime = this.toJstTime(serverTime);

        string line = "";
        this.appendCsvField(line, this.formatDateTime(jstTime));
        this.appendCsvField(line, this.formatDateTime(serverTime));
        this.appendCsvField(line, this.symbolName);
        this.appendCsvField(line, IntegerToString((int)this.timeFrame));
        this.appendCsvField(line, (string)this.magicNumber);
        this.appendCsvField(line, strategyNameValue);
        this.appendCsvField(line, actionValue);
        this.appendCsvField(line, sideValue);
        this.appendCsvField(line, DoubleToString(volumeValue, 2));
        this.appendCsvField(line, DoubleToString(priceValue, _Digits));
        this.appendCsvField(line, (string)positionTicketValue);
        this.appendCsvField(line, (string)dealTicketValue);
        this.appendCsvField(line, DoubleToString(profitValue, 2));
        this.appendCsvField(line, reasonValue);

        if (csvTextValue == "") {
            this.appendCsvField(line, "");
        } else {
            line += "," + csvTextValue;
        }

        this.writeLine(fileHandle, line);
        FileClose(fileHandle);
    }

    /**
     * 保持CSV情報保存
     *
     * @param csvTextValue CSV情報
     */
    void savePendingCsvText(string csvTextValue) {

        if (csvTextValue == "") {
            this.clearPendingCsvText();
            return;
        }

        string stateFilePath = this.buildPendingCsvTextFilePath();
        int fileHandle = FileOpen(
            stateFilePath,
            FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON
        );

        if (fileHandle == INVALID_HANDLE) {
            Print("TradeCsvLogger FileOpen failed: " + stateFilePath);
            return;
        }

        // 保持情報を保存
        FileWriteString(fileHandle, csvTextValue);
        FileClose(fileHandle);
    }

    /**
     * 保持CSV情報取得
     *
     * @return CSV情報
     */
    string loadPendingCsvText() {
        string stateFilePath = this.buildPendingCsvTextFilePath();

        if (!FileIsExist(stateFilePath, FILE_COMMON)) {
            return "";
        }

        int fileHandle = FileOpen(
            stateFilePath,
            FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON
        );

        if (fileHandle == INVALID_HANDLE) {
            Print("TradeCsvLogger FileOpen failed: " + stateFilePath);
            return "";
        }

        string csvText = FileReadString(fileHandle);
        FileClose(fileHandle);

        return csvText;
    }

    /**
     * 保持CSV情報削除
     */
    void clearPendingCsvText() {
        string stateFilePath = this.buildPendingCsvTextFilePath();

        if (!FileIsExist(stateFilePath, FILE_COMMON)) {
            return;
        }

        // 保持ファイルを削除
        FileDelete(stateFilePath, FILE_COMMON);
    }

private:
    /**
     * JST時刻変換
     *
     * @param serverTimeValue サーバー時刻
     * @return JST時刻
     */
    datetime toJstTime(datetime serverTimeValue) {
        // OANDAサーバー時差を判定
        int serverUtcOffsetHours = this.resolveOandaServerUtcOffsetHours(serverTimeValue);

        // JSTへ変換
        int differenceHours = 9 - serverUtcOffsetHours;
        datetime jstTime = serverTimeValue + (differenceHours * 60 * 60);

        return jstTime;
    }

    /**
     * OANDAサーバーUTCオフセット時間取得
     *
     * @param serverTimeValue サーバー時刻
     * @return UTCオフセット時間
     */
    int resolveOandaServerUtcOffsetHours(datetime serverTimeValue) {
        // OANDA夏時間ならUTC+3
        if (this.isOandaDaylightSavingTime(serverTimeValue)) {
            return 3;
        }

        return 2;
    }

    /**
     * OANDA夏時間判定
     *
     * @param serverTimeValue サーバー時刻
     * @return true: 夏時間
     */
    bool isOandaDaylightSavingTime(datetime serverTimeValue) {
        MqlDateTime serverDateTime;
        TimeToStruct(serverTimeValue, serverDateTime);

        // 年単位の切替日を取得
        datetime daylightSavingStart = this.getNthSundayDateTime(serverDateTime.year, 3, 2);
        datetime daylightSavingEnd = this.getNthSundayDateTime(serverDateTime.year, 11, 1);

        if (serverTimeValue < daylightSavingStart) {
            return false;
        }

        if (serverTimeValue >= daylightSavingEnd) {
            return false;
        }

        return true;
    }

    /**
     * 第n日曜日日時取得
     *
     * @param yearValue 年
     * @param monthValue 月
     * @param nthValue 第n
     * @return 日時
     */
    datetime getNthSundayDateTime(
        int yearValue,
        int monthValue,
        int nthValue
    ) {
        MqlDateTime firstDateTime;
        firstDateTime.year = yearValue;
        firstDateTime.mon = monthValue;
        firstDateTime.day = 1;
        firstDateTime.hour = 0;
        firstDateTime.min = 0;
        firstDateTime.sec = 0;

        datetime firstDay = StructToTime(firstDateTime);

        MqlDateTime firstDayStruct;
        TimeToStruct(firstDay, firstDayStruct);

        // 第1日曜日までの日数を算出
        int shiftDays = 0 - firstDayStruct.day_of_week;

        if (shiftDays < 0) {
            shiftDays += 7;
        }

        int targetDay = 1 + shiftDays + ((nthValue - 1) * 7);
        firstDateTime.day = targetDay;

        return StructToTime(firstDateTime);
    }

    /**
     * CSV項目追加
     *
     * @param lineValue 行文字列
     * @param fieldValue 項目値
     */
    void appendCsvField(string &lineValue, string fieldValue) {

        if (lineValue != "") {
            lineValue += ",";
        }

        lineValue += this.escapeCsvField(fieldValue);
    }

    /**
     * CSV項目変換
     *
     * @param fieldValue 項目値
     * @return 変換後項目値
     */
    string escapeCsvField(string fieldValue) {
        string escapedField = fieldValue;
        StringReplace(escapedField, "\"", "\"\"");

        bool isQuoteRequired = false;

        if (StringFind(escapedField, ",") >= 0) {
            isQuoteRequired = true;
        }

        if (StringFind(escapedField, "\n") >= 0) {
            isQuoteRequired = true;
        }

        if (StringFind(escapedField, "\r") >= 0) {
            isQuoteRequired = true;
        }

        if (!isQuoteRequired) {
            return escapedField;
        }

        return "\"" + escapedField + "\"";
    }

    /**
     * 行出力
     *
     * @param fileHandleValue ファイルハンドル
     * @param lineValue 行文字列
     */
    void writeLine(int fileHandleValue, string lineValue) {
        FileWriteString(fileHandleValue, lineValue + "\r\n");
    }

    /**
     * 日時文字列変換
     *
     * @param dateTimeValue 日時
     * @return 日時文字列
     */
    string formatDateTime(datetime dateTimeValue) {
        // 表示形式へ変換
        string dateTimeText = TimeToString(dateTimeValue, TIME_DATE | TIME_SECONDS);

        return dateTimeText;
    }

    /**
     * 出力先生成
     *
     * @return 出力先
     */
    string buildFilePath() {
        // ファイルパスを構築
        string timeFrameLabel = IntegerToString((int)this.timeFrame);
        string filePath = "MstngEa\\Trades\\MstngEa_";
        filePath += this.symbolName;
        filePath += "_";
        filePath += timeFrameLabel;
        filePath += "_";
        filePath += (string)this.magicNumber;
        filePath += ".csv";

        return filePath;
    }

    /**
     * 保持CSVファイルパス生成
     *
     * @return ファイルパス
     */
    string buildPendingCsvTextFilePath() {
        string timeFrameLabel = IntegerToString((int)this.timeFrame);
        string filePath = "MstngEa\\Trades\\State\\MstngEa_";
        filePath += this.symbolName;
        filePath += "_";
        filePath += timeFrameLabel;
        filePath += "_";
        filePath += (string)this.magicNumber;
        filePath += "_entryCsvText.txt";

        return filePath;
    }
};

#endif
