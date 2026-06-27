/**
 * Package: Mstng.Common.File
 * File: CsvFileWriter.mqh
 */

#ifndef __CSV_FILE_WRITER_MQH__
#define __CSV_FILE_WRITER_MQH__

/**
 * CSVファイル出力モード
 */
enum ENUM_CSV_FILE_WRITE_MODE {
    /** 追記 */
    CSV_FILE_WRITE_MODE_APPEND = 0,

    /** 上書 */
    CSV_FILE_WRITE_MODE_OVERWRITE = 1
};

/**
 * CSVファイル出力
 */
class CsvFileWriter {
public:
    /**
     * コンストラクタ
     */
    CsvFileWriter() {
        this.folderName = "";
        this.fileName = "log.csv";
        this.delimiter = ",";
        this.useCommonFolder = true;
        this.useAnsi = true;
        this.flushEveryWrite = true;
        this.writeMode = CSV_FILE_WRITE_MODE_APPEND;
        this.isOverwriteExecuted = false;
        this.handle = INVALID_HANDLE;
    }

    /**
     * コンストラクタ
     *
     * @param fileNameValue ファイル名
     * @param useCommonFolderValue 共有フォルダ使用有無
     * @param delimiterValue 区切り文字
     * @param flushEveryWriteValue 書き込み毎のフラッシュ有無
     * @param useAnsiValue ANSI出力有無
     * @param folderNameValue フォルダ名
     * @param writeModeValue 出力モード
     */
    CsvFileWriter(
        const string fileNameValue,
        const bool useCommonFolderValue = true,
        const string delimiterValue = ",",
        const bool flushEveryWriteValue = true,
        const bool useAnsiValue = true,
        const string folderNameValue = "",
        const ENUM_CSV_FILE_WRITE_MODE writeModeValue = CSV_FILE_WRITE_MODE_APPEND
    ) {
        this.folderName = folderNameValue;
        this.fileName = fileNameValue;
        this.delimiter = delimiterValue;
        this.useCommonFolder = useCommonFolderValue;
        this.useAnsi = useAnsiValue;
        this.flushEveryWrite = flushEveryWriteValue;
        this.writeMode = writeModeValue;
        this.isOverwriteExecuted = false;
        this.handle = INVALID_HANDLE;
    }

    /**
     * デストラクタ
     */
    ~CsvFileWriter() {
        this.close();
    }

    /**
     * 設定
     *
     * @param fileNameValue ファイル名
     * @param useCommonFolderValue 共有フォルダ使用有無
     * @param delimiterValue 区切り文字
     * @param flushEveryWriteValue 書き込み毎のフラッシュ有無
     * @param useAnsiValue ANSI出力有無
     * @param folderNameValue フォルダ名
     * @param writeModeValue 出力モード
     */
    void setup(
        const string fileNameValue,
        const bool useCommonFolderValue = true,
        const string delimiterValue = ",",
        const bool flushEveryWriteValue = true,
        const bool useAnsiValue = true,
        const string folderNameValue = "",
        const ENUM_CSV_FILE_WRITE_MODE writeModeValue = CSV_FILE_WRITE_MODE_APPEND
    ) {
        this.close();

        this.folderName = folderNameValue;
        this.fileName = fileNameValue;
        this.delimiter = delimiterValue;
        this.useCommonFolder = useCommonFolderValue;
        this.useAnsi = useAnsiValue;
        this.flushEveryWrite = flushEveryWriteValue;
        this.writeMode = writeModeValue;
        this.isOverwriteExecuted = false;
    }

    /**
     * フォルダ指定設定
     *
     * @param folderNameValue フォルダ名
     * @param fileNameValue ファイル名
     * @param useCommonFolderValue 共有フォルダ使用有無
     * @param delimiterValue 区切り文字
     * @param flushEveryWriteValue 書き込み毎のフラッシュ有無
     * @param useAnsiValue ANSI出力有無
     * @param writeModeValue 出力モード
     */
    void setupWithFolder(
        const string folderNameValue,
        const string fileNameValue,
        const bool useCommonFolderValue = true,
        const string delimiterValue = ",",
        const bool flushEveryWriteValue = true,
        const bool useAnsiValue = true,
        const ENUM_CSV_FILE_WRITE_MODE writeModeValue = CSV_FILE_WRITE_MODE_APPEND
    ) {
        this.setup(
            fileNameValue,
            useCommonFolderValue,
            delimiterValue,
            flushEveryWriteValue,
            useAnsiValue,
            folderNameValue,
            writeModeValue
        );
    }

    /**
     * フォルダ名設定
     *
     * @param folderNameValue フォルダ名
     */
    void setFolderName(const string folderNameValue) {
        this.close();
        this.folderName = folderNameValue;
        this.isOverwriteExecuted = false;
    }

    /**
     * ファイル名設定
     *
     * @param fileNameValue ファイル名
     */
    void setFileName(const string fileNameValue) {
        this.close();
        this.fileName = fileNameValue;
        this.isOverwriteExecuted = false;
    }

    /**
     * 出力モード設定
     *
     * @param writeModeValue 出力モード
     */
    void setWriteMode(const ENUM_CSV_FILE_WRITE_MODE writeModeValue) {
        this.close();
        this.writeMode = writeModeValue;
        this.isOverwriteExecuted = false;
    }

    /**
     * 出力モードに従って開く
     *
     * @return 成功時true
     */
    bool open() {
        if (this.writeMode == CSV_FILE_WRITE_MODE_OVERWRITE) {
            return this.openOverwrite();
        }

        return this.openAppend();
    }

    /**
     * 追記用に開く
     *
     * @return 成功時true
     */
    bool openAppend() {
        if (this.isOpen()) {
            return true;
        }

        if (!this.createFolderIfNeeded()) {
            return false;
        }

        return this.openFileAtEnd("openAppend");
    }

    /**
     * 上書用に開く
     *
     * @return 成功時true
     */
    bool openOverwrite() {
        if (this.isOpen()) {
            return true;
        }

        if (!this.createFolderIfNeeded()) {
            return false;
        }

        if (!this.isOverwriteExecuted) {
            if (!this.deleteFileIfExists()) {
                return false;
            }

            this.isOverwriteExecuted = true;
        }

        return this.openFileAtEnd("openOverwrite");
    }

    /**
     * 閉じる
     */
    void close() {
        if (this.handle != INVALID_HANDLE) {
            FileClose(this.handle);
            this.handle = INVALID_HANDLE;
        }
    }

    /**
     * オープン済み判定
     *
     * @return オープン済みの場合true
     */
    bool isOpen() const {
        return this.handle != INVALID_HANDLE;
    }

    /**
     * ファイルサイズ取得
     *
     * @return ファイルサイズ
     */
    ulong size() {
        if (!this.open()) {
            return 0;
        }

        return FileSize(this.handle);
    }

    /**
     * ヘッダー出力
     *
     * @param headerValues ヘッダー値
     * @param onlyIfEmptyValue 空ファイル時のみ出力するか
     * @return 成功時true
     */
    bool writeHeader(string &headerValues[], const bool onlyIfEmptyValue = true) {
        if (!this.open()) {
            return false;
        }

        if (onlyIfEmptyValue && FileSize(this.handle) > 0) {
            return true;
        }

        return this.writeRow(headerValues);
    }

    /**
     * 行出力
     *
     * @param fieldValues フィールド値
     * @return 成功時true
     */
    bool writeRow(string &fieldValues[]) {
        if (!this.open()) {
            return false;
        }

        // CSV行を作成して改行を追加
        string line = this.buildCsvLine(fieldValues);
        line = line + "\r\n";

        ResetLastError();

        uint writtenSize = FileWriteString(this.handle, line);

        if (writtenSize <= 0) {
            Print(
                "CsvFileWriter.writeRow failed. file=" + this.getFilePath()
                + " error=" + IntegerToString(GetLastError())
            );

            return false;
        }

        if (this.flushEveryWrite) {
            FileFlush(this.handle);
        }

        return true;
    }

    /**
     * 行をそのまま出力
     *
     * @param lineValue 出力行
     * @return 成功時true
     */
    bool writeLine(const string lineValue) {
        if (!this.open()) {
            return false;
        }

        // 改行を追加
        string outputLine = lineValue + "\r\n";

        ResetLastError();

        uint writtenSize = FileWriteString(this.handle, outputLine);

        if (writtenSize <= 0) {
            Print(
                "CsvFileWriter.writeLine failed. file=" + this.getFilePath()
                + " error=" + IntegerToString(GetLastError())
            );

            return false;
        }

        if (this.flushEveryWrite) {
            FileFlush(this.handle);
        }

        return true;
    }

    /**
     * CSV行作成
     *
     * @param fieldValues フィールド値
     * @return CSV行
     */
    string buildCsvLine(string &fieldValues[]) {
        string line = "";
        int fieldCount = ArraySize(fieldValues);

        for (int i = 0; i < fieldCount; i++) {
            if (i > 0) {
                line = line + this.delimiter;
            }

            line = line + this.escapeCsv(fieldValues[i]);
        }

        return line;
    }

    /**
     * 日時文字列変換
     *
     * @param dateTimeValue 日時
     * @param modeValue 変換モード
     * @return 文字列
     */
    string toDateTimeString(
        const datetime dateTimeValue,
        const int modeValue = TIME_DATE | TIME_SECONDS
    ) const {
        return TimeToString(dateTimeValue, modeValue);
    }

    /**
     * double文字列変換
     *
     * @param doubleValue 数値
     * @param digitsValue 桁数
     * @return 文字列
     */
    string toDoubleString(const double doubleValue, const int digitsValue = 5) const {
        return DoubleToString(doubleValue, digitsValue);
    }

    /**
     * int文字列変換
     *
     * @param intValue 数値
     * @return 文字列
     */
    string toIntString(const int intValue) const {
        return IntegerToString(intValue);
    }

    /**
     * long文字列変換
     *
     * @param longValue 数値
     * @return 文字列
     */
    string toLongString(const long longValue) const {
        return IntegerToString(longValue);
    }

    /**
     * bool文字列変換
     *
     * @param boolValue 真偽値
     * @return 文字列
     */
    string toBoolString(const bool boolValue) const {
        if (boolValue) {
            return "true";
        }

        return "false";
    }

    /**
     * ファイル名取得
     *
     * @return ファイル名
     */
    string getFileName() const {
        return this.fileName;
    }

    /**
     * フォルダ名取得
     *
     * @return フォルダ名
     */
    string getFolderName() const {
        return this.folderName;
    }

    /**
     * ファイルパス取得
     *
     * @return ファイルパス
     */
    string getFilePath() const {
        string normalizedFolderName = this.normalizeFolderName(this.folderName);

        if (normalizedFolderName == "") {
            return this.fileName;
        }

        return normalizedFolderName + "\\" + this.fileName;
    }

    /**
     * 出力モード取得
     *
     * @return 出力モード
     */
    ENUM_CSV_FILE_WRITE_MODE getWriteMode() const {
        return this.writeMode;
    }

    /**
     * 共有フォルダ使用有無取得
     *
     * @return 共有フォルダ使用時true
     */
    bool isCommonFolder() const {
        return this.useCommonFolder;
    }

    /**
     * 共通データフォルダ取得
     *
     * @return 共通データフォルダ
     */
    string getCommonDataPath() const {
        return TerminalInfoString(TERMINAL_COMMONDATA_PATH);
    }

private:
    /** フォルダ名 */
    string folderName;

    /** ファイル名 */
    string fileName;

    /** 区切り文字 */
    string delimiter;

    /** 共有フォルダ使用有無 */
    bool useCommonFolder;

    /** ANSI出力有無 */
    bool useAnsi;

    /** 書き込み毎のフラッシュ有無 */
    bool flushEveryWrite;

    /** 出力モード */
    ENUM_CSV_FILE_WRITE_MODE writeMode;

    /** 上書実行済み */
    bool isOverwriteExecuted;

    /** ファイルハンドル */
    int handle;

    /**
     * ファイルを末尾位置で開く
     *
     * @param methodNameValue 呼び出し元メソッド名
     * @return 成功時true
     */
    bool openFileAtEnd(const string methodNameValue) {
        ResetLastError();

        int flags = FILE_READ | FILE_WRITE | FILE_TXT;

        if (this.useCommonFolder) {
            flags = flags | FILE_COMMON;
        }

        if (this.useAnsi) {
            flags = flags | FILE_ANSI;
        } else {
            flags = flags | FILE_UNICODE;
        }

        string filePath = this.getFilePath();
        this.handle = FileOpen(filePath, flags);

        if (this.handle == INVALID_HANDLE) {
            Print(
                "CsvFileWriter." + methodNameValue + " failed. file=" + filePath
                + " error=" + IntegerToString(GetLastError())
            );

            return false;
        }

        FileSeek(this.handle, 0, SEEK_END);

        return true;
    }

    /**
     * 既存ファイルがあれば削除
     *
     * @return 成功時true
     */
    bool deleteFileIfExists() {
        string filePath = this.getFilePath();
        int commonFlag = this.getCommonFlag();

        if (!FileIsExist(filePath, commonFlag)) {
            return true;
        }

        ResetLastError();

        if (!FileDelete(filePath, commonFlag)) {
            Print(
                "CsvFileWriter.deleteFileIfExists failed. file=" + filePath
                + " error=" + IntegerToString(GetLastError())
            );

            return false;
        }

        return true;
    }

    /**
     * 必要に応じてフォルダ作成
     *
     * @return 成功時true
     */
    bool createFolderIfNeeded() {
        string normalizedFolderName = this.normalizeFolderName(this.folderName);

        if (normalizedFolderName == "") {
            return true;
        }

        ushort separator = StringGetCharacter("\\", 0);
        string folderParts[];
        int folderPartCount = StringSplit(normalizedFolderName, separator, folderParts);

        if (folderPartCount <= 0) {
            return true;
        }

        string currentFolderName = "";
        int commonFlag = this.getCommonFlag();

        for (int i = 0; i < folderPartCount; i++) {
            if (folderParts[i] == "") {
                continue;
            }

            if (currentFolderName == "") {
                currentFolderName = folderParts[i];
            } else {
                currentFolderName = currentFolderName + "\\" + folderParts[i];
            }

            // 既存フォルダの場合もあるためFileOpen側で最終判定
            ResetLastError();
            FolderCreate(currentFolderName, commonFlag);
        }

        return true;
    }

    /**
     * 共通フォルダフラグ取得
     *
     * @return 共通フォルダフラグ
     */
    int getCommonFlag() const {
        if (this.useCommonFolder) {
            return FILE_COMMON;
        }

        return 0;
    }

    /**
     * フォルダ名正規化
     *
     * @param folderNameValue フォルダ名
     * @return 正規化後フォルダ名
     */
    string normalizeFolderName(const string folderNameValue) const {
        string normalizedFolderName = folderNameValue;
        StringReplace(normalizedFolderName, "/", "\\");

        while (StringLen(normalizedFolderName) > 0
            && StringSubstr(normalizedFolderName, 0, 1) == "\\") {
            normalizedFolderName = StringSubstr(normalizedFolderName, 1);
        }

        while (StringLen(normalizedFolderName) > 0
            && StringSubstr(
                normalizedFolderName,
                StringLen(normalizedFolderName) - 1,
                1
            ) == "\\") {
            normalizedFolderName = StringSubstr(normalizedFolderName, 0, StringLen(normalizedFolderName) - 1);
        }

        return normalizedFolderName;
    }

    /**
     * CSVエスケープ
     *
     * @param valueValue 値
     * @return エスケープ後文字列
     */
    string escapeCsv(const string valueValue) {
        string escapedValue = valueValue;
        bool needsQuote = false;

        // 区切り文字を含む場合は引用符が必要
        if (StringFind(escapedValue, this.delimiter) >= 0) {
            needsQuote = true;
        }

        // ダブルクォートを含む場合は引用符が必要
        if (StringFind(escapedValue, "\"") >= 0) {
            needsQuote = true;
        }

        // 改行を含む場合は引用符が必要
        if (StringFind(escapedValue, "\r") >= 0) {
            needsQuote = true;
        }

        if (StringFind(escapedValue, "\n") >= 0) {
            needsQuote = true;
        }

        if (needsQuote) {
            StringReplace(escapedValue, "\"", "\"\"");
            escapedValue = "\"" + escapedValue + "\"";
        }

        return escapedValue;
    }
};

#endif
//+------------------------------------------------------------------+
