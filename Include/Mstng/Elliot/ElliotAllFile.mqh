//+------------------------------------------------------------------+
//|                                                ElliotAllFile.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef __ELLIOT_ALL_FILE_MQH__
#define __ELLIOT_ALL_FILE_MQH__

#include <Mstng/Common/File/CsvFileWriter.mqh>

/** エリオット全体情報 共通CSV列数 */
#define ELLIOT_ALL_FILE_COMMON_FIELD_COUNT 32

/** エリオット全体情報 1時間足CSV列数 */
#define ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT 96

/** 互換用：1時間足CSV列数 */
#define ELLIOT_ALL_FILE_FIELD_COUNT ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT

/**
 * エリオット全体情報ファイル出力
 */
class ElliotAllFile {
public:
    /**
     * コンストラクタ
     */
    ElliotAllFile() {
        this.symbolName = _Symbol;
        this.timeFrame = (ENUM_TIMEFRAMES)_Period;
        this.timeFrameLabel = this.convertTimeFrameToString(this.timeFrame);
        this.folderName = "ElliotAll";
        this.fileName = this.createKeyFileName(this.symbolName, this.timeFrame);
        this.useCommonFolder = true;
        this.delimiter = ",";
        this.flushEveryWrite = true;
        this.useAnsi = true;
        this.writeMode = CSV_FILE_WRITE_MODE_APPEND;

        this.clearTrendAlignDecision();
        this.clearHigherStochasticMainOrderDecision();
    }

    /**
     * コンストラクタ
     *
     * @param folderNameValue フォルダ名
     * @param fileNameValue ファイル名
     * @param useCommonFolderValue 共有フォルダ使用有無
     * @param writeModeValue 出力モード
     */
    ElliotAllFile(
        const string folderNameValue,
        const string fileNameValue,
        const bool useCommonFolderValue = true,
        const ENUM_CSV_FILE_WRITE_MODE writeModeValue = CSV_FILE_WRITE_MODE_APPEND
    ) {
        this.symbolName = _Symbol;
        this.timeFrame = (ENUM_TIMEFRAMES)_Period;
        this.timeFrameLabel = this.convertTimeFrameToString(this.timeFrame);
        this.folderName = folderNameValue;
        this.fileName = fileNameValue;
        this.useCommonFolder = useCommonFolderValue;
        this.delimiter = ",";
        this.flushEveryWrite = true;
        this.useAnsi = true;
        this.writeMode = writeModeValue;

        this.clearTrendAlignDecision();
        this.clearHigherStochasticMainOrderDecision();
    }

    /**
     * 設定
     *
     * @param folderNameValue フォルダ名
     * @param fileNameValue ファイル名
     * @param useCommonFolderValue 共有フォルダ使用有無
     * @param delimiterValue 区切り文字
     * @param flushEveryWriteValue 書き込み毎のフラッシュ有無
     * @param useAnsiValue ANSI出力有無
     * @param writeModeValue 出力モード
     */
    void setup(
        const string folderNameValue,
        const string fileNameValue,
        const bool useCommonFolderValue = true,
        const string delimiterValue = ",",
        const bool flushEveryWriteValue = true,
        const bool useAnsiValue = true,
        const ENUM_CSV_FILE_WRITE_MODE writeModeValue = CSV_FILE_WRITE_MODE_APPEND
    ) {
        this.symbolName = _Symbol;
        this.timeFrame = (ENUM_TIMEFRAMES)_Period;
        this.timeFrameLabel = this.convertTimeFrameToString(this.timeFrame);
        this.folderName = folderNameValue;
        this.fileName = fileNameValue;
        this.useCommonFolder = useCommonFolderValue;
        this.delimiter = delimiterValue;
        this.flushEveryWrite = flushEveryWriteValue;
        this.useAnsi = useAnsiValue;
        this.writeMode = writeModeValue;

        this.setupCsvFileWriter();
    }

    /**
     * 同一フォルダ内キー指定設定
     *
     * @param folderNameValue フォルダ名
     * @param symbolNameValue 通貨ペア
     * @param timeFrameValue 時間足
     * @param useCommonFolderValue 共有フォルダ使用有無
     * @param delimiterValue 区切り文字
     * @param flushEveryWriteValue 書き込み毎のフラッシュ有無
     * @param useAnsiValue ANSI出力有無
     * @param writeModeValue 出力モード
     */
    void setupByKeySameFolder(
        const string folderNameValue,
        const string symbolNameValue,
        const ENUM_TIMEFRAMES timeFrameValue,
        const bool useCommonFolderValue = true,
        const string delimiterValue = ",",
        const bool flushEveryWriteValue = true,
        const bool useAnsiValue = true,
        const ENUM_CSV_FILE_WRITE_MODE writeModeValue = CSV_FILE_WRITE_MODE_APPEND
    ) {
        this.symbolName = symbolNameValue;
        this.timeFrame = timeFrameValue;
        this.timeFrameLabel = this.convertTimeFrameToString(this.timeFrame);
        this.folderName = folderNameValue;
        this.fileName = this.createKeyFileName(this.symbolName, this.timeFrame);
        this.useCommonFolder = useCommonFolderValue;
        this.delimiter = delimiterValue;
        this.flushEveryWrite = flushEveryWriteValue;
        this.useAnsi = useAnsiValue;
        this.writeMode = writeModeValue;

        this.setupCsvFileWriter();
    }

    /**
     * 同一フォルダ内複数時間足キー指定設定
     *
     * @param folderNameValue フォルダ名
     * @param symbolNameValue 通貨ペア
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param useCommonFolderValue 共有フォルダ使用有無
     * @param delimiterValue 区切り文字
     * @param flushEveryWriteValue 書き込み毎のフラッシュ有無
     * @param useAnsiValue ANSI出力有無
     * @param writeModeValue 出力モード
     */
    void setupMultiTimeFrameSameFolder(
        const string folderNameValue,
        const string symbolNameValue,
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        const bool useCommonFolderValue = true,
        const string delimiterValue = ",",
        const bool flushEveryWriteValue = true,
        const bool useAnsiValue = true,
        const ENUM_CSV_FILE_WRITE_MODE writeModeValue = CSV_FILE_WRITE_MODE_APPEND
    ) {
        this.symbolName = symbolNameValue;
        this.timeFrame = startTimeFrameValue;
        this.timeFrameLabel = this.convertTimeFrameToString(this.timeFrame);
        this.folderName = folderNameValue;
        this.fileName = this.createMultiTimeFrameKeyFileName(
            this.symbolName,
            startTimeFrameValue,
            endTimeFrameValue
        );
        this.useCommonFolder = useCommonFolderValue;
        this.delimiter = delimiterValue;
        this.flushEveryWrite = flushEveryWriteValue;
        this.useAnsi = useAnsiValue;
        this.writeMode = writeModeValue;

        this.setupCsvFileWriter();
    }

    /**
     * キー設定
     *
     * @param symbolNameValue 通貨ペア
     * @param timeFrameValue 時間足
     */
    void setKey(const string symbolNameValue, const ENUM_TIMEFRAMES timeFrameValue) {
        this.symbolName = symbolNameValue;
        this.timeFrame = timeFrameValue;
        this.timeFrameLabel = this.convertTimeFrameToString(this.timeFrame);
    }

    /**
     * 初期化
     *
     * @return 成功時true
     */
    bool initialize() {
        this.setupCsvFileWriter();

        if (!this.csvFileWriter.open()) {
            return false;
        }

        return this.writeHeader();
    }

    /**
     * 複数時間足用に初期化
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @return 成功時true
     */
    bool initializeMultiTimeFrame(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue
    ) {
        this.setupCsvFileWriter();

        if (!this.csvFileWriter.open()) {
            return false;
        }

        return this.writeMultiTimeFrameHeader(startTimeFrameValue, endTimeFrameValue);
    }

    /**
     * 終了
     */
    void close() {
        this.csvFileWriter.close();
    }

    /**
     * トレンド一致判定を初期化
     */
    void clearTrendAlignDecision() {
        // トレンド一致判定初期化
        this.trendAlignD1H4H1M15 = "";
        this.trendAlignD1H4H1 = "";
        this.trendAlignH4H1M15 = "";
        this.trendAlignH4H1 = "";
        this.trendAlignH1M15 = "";
    }

    /**
     * トレンド一致判定を設定
     *
     * @param d1H4H1M15Value D1/H4/H1/M15トレンド一致
     * @param h4H1M15Value H4/H1/M15トレンド一致
     * @param h1M15Value H1/M15トレンド一致
     */
    void setTrendAlignDecision(
        const string d1H4H1M15Value,
        const string h4H1M15Value,
        const string h1M15Value
    ) {
        // トレンド一致判定設定
        this.trendAlignD1H4H1M15 = d1H4H1M15Value;
        this.trendAlignD1H4H1 = "";
        this.trendAlignH4H1M15 = h4H1M15Value;
        this.trendAlignH4H1 = "";
        this.trendAlignH1M15 = h1M15Value;
    }

    /**
     * トレンド一致判定を設定
     *
     * @param d1H4H1M15Value D1/H4/H1/M15トレンド一致
     * @param d1H4H1Value D1/H4/H1トレンド一致
     * @param h4H1M15Value H4/H1/M15トレンド一致
     * @param h4H1Value H4/H1トレンド一致
     * @param h1M15Value H1/M15トレンド一致
     */
    void setTrendAlignDecision(
        const string d1H4H1M15Value,
        const string d1H4H1Value,
        const string h4H1M15Value,
        const string h4H1Value,
        const string h1M15Value
    ) {
        // トレンド一致判定設定
        this.trendAlignD1H4H1M15 = d1H4H1M15Value;
        this.trendAlignD1H4H1 = d1H4H1Value;
        this.trendAlignH4H1M15 = h4H1M15Value;
        this.trendAlignH4H1 = h4H1Value;
        this.trendAlignH1M15 = h1M15Value;
    }

    /**
     * 上位足ストキャスMain順序多数決判定を初期化
     */
    void clearHigherStochasticMainOrderDecision() {
        // 上位足ストキャスMain順序多数決判定初期化
        this.higherStochasticMainOrderBuySell = "";
        this.higherStochasticMainOrderBuyCount = 0;
        this.higherStochasticMainOrderSellCount = 0;
        this.higherStochasticMainOrderNoneCount = 0;
    }

    /**
     * 上位足ストキャスMain順序多数決判定を設定
     *
     * @param buySellValue 売買
     * @param buyCountValue 買い数
     * @param sellCountValue 売り数
     * @param noneCountValue 判定なし数
     */
    void setHigherStochasticMainOrderDecision(
        const string buySellValue,
        const int buyCountValue,
        const int sellCountValue,
        const int noneCountValue
    ) {
        // 上位足ストキャスMain順序多数決判定設定
        this.higherStochasticMainOrderBuySell = buySellValue;
        this.higherStochasticMainOrderBuyCount = buyCountValue;
        this.higherStochasticMainOrderSellCount = sellCountValue;
        this.higherStochasticMainOrderNoneCount = noneCountValue;
    }

    /**
     * ヘッダー出力
     *
     * @return 成功時true
     */
    bool writeHeader() {
        string headerValues[];
        this.createHeaderValuesWithCommon(headerValues);

        return this.csvFileWriter.writeHeader(headerValues, true);
    }

    /**
     * 複数時間足ヘッダー出力
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @return 成功時true
     */
    bool writeMultiTimeFrameHeader(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue
    ) {
        string headerValues[];

        if (!this.createMultiTimeFrameHeaderValuesWithCommon(
            startTimeFrameValue,
            endTimeFrameValue,
            headerValues
        )) {
            return false;
        }

        return this.csvFileWriter.writeHeader(headerValues, true);
    }

    /**
     * CSV文字列行出力
     *
     * 呼び出し側は、1時間足分のCSV文字列だけを渡す。
     * CSV出力時に左側へ共通情報を自動付与する。
     *
     * @param csvTextValue 1時間足CSV文字列
     * @return 成功時true
     */
    bool writeRowCsvTextValue(const string csvTextValue) {
        string fieldValues[];

        if (!this.splitSingleTimeFrameCsvText(csvTextValue, fieldValues)) {
            return false;
        }

        return this.writeRowValues(fieldValues);
    }

    /**
     * 行出力
     *
     * 呼び出し側は、1時間足分の列だけを渡す。
     * CSV出力時に左側へ共通情報を自動付与する。
     *
     * @param fieldValues フィールド値
     * @return 成功時true
     */
    bool writeRowValues(string &fieldValues[]) {
        int fieldCount = ArraySize(fieldValues);

        if (!this.isValidTimeFrameFieldCount(fieldCount)) {
            Print(
                "ElliotAllFile.writeRowValues invalid field count=" + IntegerToString(fieldCount)
                + " expected=" + IntegerToString(ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT)
            );

            return false;
        }

        string rowValues[];

        if (!this.prependCommonValues(fieldValues, rowValues)) {
            return false;
        }

        return this.csvFileWriter.writeRow(rowValues);
    }

    /**
     * 複数時間足行出力
     *
     * 呼び出し側は、複数時間足分の列だけを渡す。
     * CSV出力時に左側へ共通情報を自動付与する。
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param fieldValues フィールド値
     * @return 成功時true
     */
    bool writeMultiTimeFrameRowValues(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        string &fieldValues[]
    ) {
        int expectedFieldCount = this.getMultiTimeFrameFieldCount(
            startTimeFrameValue,
            endTimeFrameValue
        );

        if (expectedFieldCount <= 0) {
            return false;
        }

        int fieldCount = ArraySize(fieldValues);

        if (fieldCount != expectedFieldCount) {
            Print(
                "ElliotAllFile.writeMultiTimeFrameRowValues invalid field count="
                + IntegerToString(fieldCount)
                + " expected=" + IntegerToString(expectedFieldCount)
            );

            return false;
        }

        string rowValues[];

        if (!this.prependCommonValues(fieldValues, rowValues)) {
            return false;
        }

        return this.csvFileWriter.writeRow(rowValues);
    }

    /**
     * 複数時間足CSV文字列行出力
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param timeFrameCsvValues 時間足ごとのCSV文字列
     * @return 成功時true
     */
    bool writeMultiTimeFrameCsvTextValues(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        string &timeFrameCsvValues[]
    ) {
        string rowValues[];

        if (!this.createMultiTimeFrameRowValuesFromCsvTextValues(
            startTimeFrameValue,
            endTimeFrameValue,
            timeFrameCsvValues,
            rowValues
        )) {
            return false;
        }

        return this.writeMultiTimeFrameRowValues(
            startTimeFrameValue,
            endTimeFrameValue,
            rowValues
        );
    }

    /**
     * 空CSVを取得
     *
     * 指定した項目数分の空CSVを作成する。
     *
     * @param countValue 空項目数
     * @return 空CSV
     */
    string getCsvBlank(const int countValue) const {
        if (countValue <= 0) {
            return "";
        }

        string csvText = "";

        for (int i = 1; i < countValue; i++) {
            csvText += this.delimiter;
        }

        return csvText;
    }

    /**
     * CSV文字列行出力
     *
     * 1つのstringに1行分のCSVデータが全て入っている場合に使用する。
     * 呼び出し側で、共通情報 + 時間足データを作成して渡す。
     *
     * 単一時間足の場合:
     *   共通情報列数 + 1時間足分の列数
     *
     * 複数時間足の場合:
     *   共通情報列数 + 1時間足分の列数 * 時間足数
     *
     * @param csvTextValue 共通情報を含むCSV文字列
     * @return 成功時true
     */
    bool writeCsvTextValue(const string csvTextValue) {
        string rowValues[];

        if (!this.createRowValuesFromCsvTextValue(csvTextValue, rowValues)) {
            return false;
        }

        return this.csvFileWriter.writeRow(rowValues);
    }

    /**
     * 複数時間足CSV文字列から1行データ作成
     *
     * 作成されるrowValuesは共通情報なし。
     * writeMultiTimeFrameRowValues()で出力すると、共通情報が左側へ付与される。
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param timeFrameCsvValues 時間足ごとのCSV文字列
     * @param rowValues 作成後の1行データ
     * @return 成功時true
     */
    bool createMultiTimeFrameRowValuesFromCsvTextValues(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        string &timeFrameCsvValues[],
        string &rowValues[]
    ) {
        ENUM_TIMEFRAMES timeFrameValues[];

        if (!this.createTimeFrameRange(startTimeFrameValue, endTimeFrameValue, timeFrameValues)) {
            return false;
        }

        int timeFrameCount = ArraySize(timeFrameValues);
        int csvTextCount = ArraySize(timeFrameCsvValues);

        if (csvTextCount != timeFrameCount) {
            Print(
                "ElliotAllFile.createMultiTimeFrameRowValuesFromCsvTextValues invalid timeframe csv count="
                + IntegerToString(csvTextCount)
                + " expected=" + IntegerToString(timeFrameCount)
            );

            return false;
        }

        int totalFieldCount = timeFrameCount * ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT;
        ArrayResize(rowValues, totalFieldCount);

        int rowIndex = 0;

        for (int i = 0; i < timeFrameCount; i++) {
            string singleTimeFrameValues[];

            if (!this.splitSingleTimeFrameCsvText(
                timeFrameCsvValues[i],
                singleTimeFrameValues
            )) {
                Print(
                    "ElliotAllFile.createMultiTimeFrameRowValuesFromCsvTextValues split failed. timeframe="
                    + this.convertTimeFrameToString(timeFrameValues[i])
                );

                return false;
            }

            if (!this.appendTimeFrameRowValues(singleTimeFrameValues, rowValues, rowIndex)) {
                Print(
                    "ElliotAllFile.createMultiTimeFrameRowValuesFromCsvTextValues append failed. timeframe="
                    + this.convertTimeFrameToString(timeFrameValues[i])
                );

                return false;
            }
        }

        if (rowIndex != totalFieldCount) {
            Print(
                "ElliotAllFile.createMultiTimeFrameRowValuesFromCsvTextValues invalid field count. index="
                + IntegerToString(rowIndex)
                + " expected=" + IntegerToString(totalFieldCount)
            );

            return false;
        }

        return true;
    }

    /**
     * 複数時間足フィールド数取得
     *
     * 共通情報を含まない、時間足部分のみの列数を返す。
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @return フィールド数
     */
    int getMultiTimeFrameFieldCount(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue
    ) const {
        ENUM_TIMEFRAMES timeFrameValues[];

        if (!this.createTimeFrameRange(startTimeFrameValue, endTimeFrameValue, timeFrameValues)) {
            return 0;
        }

        return ArraySize(timeFrameValues) * ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT;
    }

    /**
     * 複数時間足フィールド数取得 共通情報付き
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @return フィールド数
     */
    int getMultiTimeFrameFieldCountWithCommon(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue
    ) const {
        int fieldCount = this.getMultiTimeFrameFieldCount(
            startTimeFrameValue,
            endTimeFrameValue
        );

        if (fieldCount <= 0) {
            return 0;
        }

        return ELLIOT_ALL_FILE_COMMON_FIELD_COUNT + fieldCount;
    }

    /**
     * 複数時間足ヘッダー値作成
     *
     * 共通情報なしのヘッダーを作成する。
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param headerValues ヘッダー値
     * @return 成功時true
     */
    bool createMultiTimeFrameHeaderValues(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        string &headerValues[]
    ) const {
        ENUM_TIMEFRAMES timeFrameValues[];

        if (!this.createTimeFrameRange(startTimeFrameValue, endTimeFrameValue, timeFrameValues)) {
            return false;
        }

        int totalFieldCount = ArraySize(timeFrameValues) * ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT;
        ArrayResize(headerValues, totalFieldCount);

        int index = 0;

        for (int i = 0; i < ArraySize(timeFrameValues); i++) {
            string prefix = this.convertTimeFrameToString(timeFrameValues[i]) + ":";
            string baseHeaderValues[];
            this.createHeaderValues(baseHeaderValues);

            for (int j = 0; j < ArraySize(baseHeaderValues); j++) {
                headerValues[index++] = prefix + baseHeaderValues[j];
            }
        }

        if (index != totalFieldCount) {
            Print(
                "ElliotAllFile.createMultiTimeFrameHeaderValues invalid field count. index="
                + IntegerToString(index)
                + " expected=" + IntegerToString(totalFieldCount)
            );

            return false;
        }

        return true;
    }

    /**
     * 複数時間足ヘッダー値作成 共通情報付き
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param headerValues ヘッダー値
     * @return 成功時true
     */
    bool createMultiTimeFrameHeaderValuesWithCommon(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        string &headerValues[]
    ) const {
        ENUM_TIMEFRAMES timeFrameValues[];

        if (!this.createTimeFrameRange(startTimeFrameValue, endTimeFrameValue, timeFrameValues)) {
            return false;
        }

        string commonHeaderValues[];
        this.createCommonHeaderValues(commonHeaderValues);

        int totalFieldCount = ArraySize(commonHeaderValues)
            + ArraySize(timeFrameValues) * ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT;

        ArrayResize(headerValues, totalFieldCount);

        int index = 0;

        for (int i = 0; i < ArraySize(commonHeaderValues); i++) {
            headerValues[index++] = commonHeaderValues[i];
        }

        for (int i = 0; i < ArraySize(timeFrameValues); i++) {
            string prefix = this.convertTimeFrameToString(timeFrameValues[i]) + ":";
            string baseHeaderValues[];
            this.createHeaderValues(baseHeaderValues);

            for (int j = 0; j < ArraySize(baseHeaderValues); j++) {
                headerValues[index++] = prefix + baseHeaderValues[j];
            }
        }

        if (index != totalFieldCount) {
            Print(
                "ElliotAllFile.createMultiTimeFrameHeaderValuesWithCommon invalid field count. index="
                + IntegerToString(index)
                + " expected=" + IntegerToString(totalFieldCount)
            );

            return false;
        }

        return true;
    }

    /**
     * 複数時間足行データ追加
     *
     * @param sourceValues 追加元フィールド値
     * @param destinationValues 追加先フィールド値
     * @param destinationIndex 追加先インデックス
     * @return 成功時true
     */
    bool appendTimeFrameRowValues(
        string &sourceValues[],
        string &destinationValues[],
        int &destinationIndex
    ) const {
        int sourceCount = ArraySize(sourceValues);

        if (!this.isValidTimeFrameFieldCount(sourceCount)) {
            Print(
                "ElliotAllFile.appendTimeFrameRowValues invalid source count="
                + IntegerToString(sourceCount)
                + " expected=" + IntegerToString(ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT)
            );

            return false;
        }

        int destinationCount = ArraySize(destinationValues);

        if (destinationIndex + sourceCount > destinationCount) {
            Print(
                "ElliotAllFile.appendTimeFrameRowValues destination overflow. index="
                + IntegerToString(destinationIndex)
                + " sourceCount=" + IntegerToString(sourceCount)
                + " destinationCount=" + IntegerToString(destinationCount)
            );

            return false;
        }

        for (int i = 0; i < sourceCount; i++) {
            destinationValues[destinationIndex++] = sourceValues[i];
        }

        return true;
    }

    /**
     * 時間足範囲取得
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param timeFrameValues 時間足配列
     * @return 成功時true
     */
    bool getTimeFrameRange(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        ENUM_TIMEFRAMES &timeFrameValues[]
    ) const {
        return this.createTimeFrameRange(startTimeFrameValue, endTimeFrameValue, timeFrameValues);
    }

    /**
     * 通貨ペア取得
     *
     * @return 通貨ペア
     */
    string getSymbolName() const {
        return this.symbolName;
    }

    /**
     * 時間足取得
     *
     * @return 時間足
     */
    ENUM_TIMEFRAMES getTimeFrame() const {
        return this.timeFrame;
    }

    /**
     * 時間足ラベル取得
     *
     * @return 時間足ラベル
     */
    string getTimeFrameLabel() const {
        return this.timeFrameLabel;
    }

    /**
     * キー取得
     *
     * @return キー
     */
    string getKey() const {
        return this.symbolName + "_" + this.timeFrameLabel;
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
     * ファイルパス取得
     *
     * @return ファイルパス
     */
    string getFilePath() const {
        return this.csvFileWriter.getFilePath();
    }

    /**
     * 共通データフォルダ取得
     *
     * @return 共通データフォルダ
     */
    string getCommonDataPath() const {
        return this.csvFileWriter.getCommonDataPath();
    }

private:
    /** CSVファイル出力 */
    CsvFileWriter csvFileWriter;

    /** 通貨ペア */
    string symbolName;

    /** 時間足 */
    ENUM_TIMEFRAMES timeFrame;

    /** 時間足ラベル */
    string timeFrameLabel;

    /** フォルダ名 */
    string folderName;

    /** ファイル名 */
    string fileName;

    /** 共有フォルダ使用有無 */
    bool useCommonFolder;

    /** 区切り文字 */
    string delimiter;

    /** 書き込み毎のフラッシュ有無 */
    bool flushEveryWrite;

    /** ANSI出力有無 */
    bool useAnsi;

    /** 出力モード */
    ENUM_CSV_FILE_WRITE_MODE writeMode;

    /** D1/H4/H1/M15トレンド一致 */
    string trendAlignD1H4H1M15;

    /** D1/H4/H1トレンド一致 */
    string trendAlignD1H4H1;

    /** H4/H1/M15トレンド一致 */
    string trendAlignH4H1M15;

    /** H4/H1トレンド一致 */
    string trendAlignH4H1;

    /** H1/M15トレンド一致 */
    string trendAlignH1M15;

    /** 上位足ストキャスMain順序多数決売買 */
    string higherStochasticMainOrderBuySell;

    /** 上位足ストキャスMain順序多数決買い数 */
    int higherStochasticMainOrderBuyCount;

    /** 上位足ストキャスMain順序多数決売り数 */
    int higherStochasticMainOrderSellCount;

    /** 上位足ストキャスMain順序多数決判定なし数 */
    int higherStochasticMainOrderNoneCount;

    /**
     * CSVファイル出力設定
     */
    void setupCsvFileWriter() {
        this.csvFileWriter.setupWithFolder(
            this.folderName,
            this.fileName,
            this.useCommonFolder,
            this.delimiter,
            this.flushEveryWrite,
            this.useAnsi,
            this.writeMode
        );
    }

    /**
     * 共通ヘッダー値作成
     *
     * @param headerValues ヘッダー値
     */
    void createCommonHeaderValues(string &headerValues[]) const {
        ArrayResize(headerValues, ELLIOT_ALL_FILE_COMMON_FIELD_COUNT);

        int index = 0;
        headerValues[index++] = "通貨ペア";
        headerValues[index++] = "ServerTime";
        headerValues[index++] = "JstTime";
        headerValues[index++] = "JstOffsetHour";
        headerValues[index++] = "ServerHour";
        headerValues[index++] = "ServerMinute";
        headerValues[index++] = "JstHour";
        headerValues[index++] = "JstMinute";
        headerValues[index++] = "DayOfWeek";
        headerValues[index++] = "SessionType";
        headerValues[index++] = "IsTokyoSession";
        headerValues[index++] = "IsLondonSession";
        headerValues[index++] = "IsNewYorkSession";
        headerValues[index++] = "IsLondonNewYorkOverlap";
        headerValues[index++] = "IsRolloverTime";
        headerValues[index++] = "IsMondayEarly";
        headerValues[index++] = "IsFridayLate";
        headerValues[index++] = "bidレート";
        headerValues[index++] = "askレート";
        headerValues[index++] = "スプレッドpips";
        headerValues[index++] = "日足高値";
        headerValues[index++] = "日足安値";
        headerValues[index++] = "日足値幅pips";
        headerValues[index++] = "TrendAlign_D1_H4_H1_M15";
        headerValues[index++] = "TrendAlign_D1_H4_H1";
        headerValues[index++] = "TrendAlign_H4_H1_M15";
        headerValues[index++] = "TrendAlign_H4_H1";
        headerValues[index++] = "TrendAlign_H1_M15";
        headerValues[index++] = "HigherStochasticMainOrderBuySell";
        headerValues[index++] = "HigherStochasticMainOrderBuyCount";
        headerValues[index++] = "HigherStochasticMainOrderSellCount";
        headerValues[index++] = "HigherStochasticMainOrderNoneCount";
    }

    /**
     * 共通値作成
     *
     * @param commonValues 共通値
     */
    void createCommonValues(string &commonValues[]) const {
        ArrayResize(commonValues, ELLIOT_ALL_FILE_COMMON_FIELD_COUNT);

        int digits = this.getSymbolDigits(this.symbolName);

        datetime serverTime = TimeTradeServer();

        if (serverTime <= 0) {
            serverTime = TimeCurrent();
        }

        int jstOffsetHour = this.getJstOffsetHour(serverTime);
        datetime jstTime = serverTime + jstOffsetHour * 60 * 60;

        MqlDateTime serverDateTime;
        TimeToStruct(serverTime, serverDateTime);

        MqlDateTime jstDateTime;
        TimeToStruct(jstTime, jstDateTime);

        int serverHour = serverDateTime.hour;
        int serverMinute = serverDateTime.min;
        int jstHour = jstDateTime.hour;
        int jstMinute = jstDateTime.min;
        int dayOfWeek = jstDateTime.day_of_week;

        bool isWeekendSessionBlockedTime = this.isWeekendSessionBlockedTime(dayOfWeek);
        bool isTokyoSession = false;
        bool isLondonSession = false;
        bool isNewYorkSession = false;

        if (!isWeekendSessionBlockedTime) {
            isTokyoSession = this.isTokyoSession(jstHour);
            isLondonSession = this.isLondonSession(jstHour, jstOffsetHour);
            isNewYorkSession = this.isNewYorkSession(jstHour, jstOffsetHour);
        }

        bool isLondonNewYorkOverlap = isLondonSession && isNewYorkSession;
        bool isRolloverTime = this.isRolloverTime(jstHour, jstMinute);
        bool isMondayEarly = this.isMondayEarly(dayOfWeek, jstHour);
        bool isFridayLate = this.isFridayLate(dayOfWeek, jstHour);

        string sessionType = this.getSessionType(
            isWeekendSessionBlockedTime,
            isTokyoSession,
            isLondonSession,
            isNewYorkSession,
            isLondonNewYorkOverlap
        );

        MqlTick tick;
        double bid = 0.0;
        double ask = 0.0;

        if (SymbolInfoTick(this.symbolName, tick)) {
            bid = tick.bid;
            ask = tick.ask;
        } else {
            bid = SymbolInfoDouble(this.symbolName, SYMBOL_BID);
            ask = SymbolInfoDouble(this.symbolName, SYMBOL_ASK);
        }

        double spreadPips = 0.0;

        if (ask > 0.0 && bid > 0.0) {
            spreadPips = this.convertPriceDifferenceToPips(ask - bid, this.symbolName);
        } else {
            int spreadPoints = (int)SymbolInfoInteger(this.symbolName, SYMBOL_SPREAD);
            spreadPips = this.convertPriceDifferenceToPips(
                spreadPoints * SymbolInfoDouble(this.symbolName, SYMBOL_POINT),
                this.symbolName
            );
        }

        double dailyHigh = iHigh(this.symbolName, PERIOD_D1, 0);
        double dailyLow = iLow(this.symbolName, PERIOD_D1, 0);
        double dailyRangePips = 0.0;

        if (dailyHigh > 0.0 && dailyLow > 0.0) {
            dailyRangePips = this.convertPriceDifferenceToPips(dailyHigh - dailyLow, this.symbolName);
        }

        int index = 0;
        commonValues[index++] = this.symbolName;
        commonValues[index++] = TimeToString(serverTime, TIME_DATE | TIME_SECONDS);
        commonValues[index++] = TimeToString(jstTime, TIME_DATE | TIME_SECONDS);
        commonValues[index++] = IntegerToString(jstOffsetHour);
        commonValues[index++] = IntegerToString(serverHour);
        commonValues[index++] = IntegerToString(serverMinute);
        commonValues[index++] = IntegerToString(jstHour);
        commonValues[index++] = IntegerToString(jstMinute);
        commonValues[index++] = IntegerToString(dayOfWeek);
        commonValues[index++] = sessionType;
        commonValues[index++] = this.boolToString(isTokyoSession);
        commonValues[index++] = this.boolToString(isLondonSession);
        commonValues[index++] = this.boolToString(isNewYorkSession);
        commonValues[index++] = this.boolToString(isLondonNewYorkOverlap);
        commonValues[index++] = this.boolToString(isRolloverTime);
        commonValues[index++] = this.boolToString(isMondayEarly);
        commonValues[index++] = this.boolToString(isFridayLate);
        commonValues[index++] = DoubleToString(bid, digits);
        commonValues[index++] = DoubleToString(ask, digits);
        commonValues[index++] = DoubleToString(spreadPips, 1);
        commonValues[index++] = DoubleToString(dailyHigh, digits);
        commonValues[index++] = DoubleToString(dailyLow, digits);
        commonValues[index++] = DoubleToString(dailyRangePips, 1);
        commonValues[index++] = this.trendAlignD1H4H1M15;
        commonValues[index++] = this.trendAlignD1H4H1;
        commonValues[index++] = this.trendAlignH4H1M15;
        commonValues[index++] = this.trendAlignH4H1;
        commonValues[index++] = this.trendAlignH1M15;
        commonValues[index++] = this.higherStochasticMainOrderBuySell;
        commonValues[index++] = IntegerToString(this.higherStochasticMainOrderBuyCount);
        commonValues[index++] = IntegerToString(this.higherStochasticMainOrderSellCount);
        commonValues[index++] = IntegerToString(this.higherStochasticMainOrderNoneCount);

        if (index != ELLIOT_ALL_FILE_COMMON_FIELD_COUNT) {
            Print(
                "ElliotAllFile.createCommonValues invalid field count. index="
                + IntegerToString(index)
                + " expected=" + IntegerToString(ELLIOT_ALL_FILE_COMMON_FIELD_COUNT)
            );
        }
    }

    /**
     * JST差分時間を取得
     *
     * @param serverTimeValue サーバー時刻
     * @return JST差分時間
     */
    int getJstOffsetHour(const datetime serverTimeValue) const {
        // 夏時間判定
        bool isSummer = this.isSummerTime(serverTimeValue);

        if (isSummer) {
            return 6;
        }

        return 7;
    }

    /**
     * 夏時間か判定
     *
     * @param serverTimeValue サーバー時刻
     * @return true: 夏時間
     */
    bool isSummerTime(const datetime serverTimeValue) const {
        // 年取得
        MqlDateTime dateTime;
        TimeToStruct(serverTimeValue, dateTime);

        int year = dateTime.year;

        // 夏時間期間取得
        datetime dstStart = this.getDstStartDatetime(year);
        datetime dstEnd = this.getDstEndDatetime(year) + 86399;

        if (
            dstStart <= serverTimeValue
            && serverTimeValue <= dstEnd
        ) {
            return true;
        }

        return false;
    }

    /**
     * 夏時間開始日時を取得
     *
     * @param yearValue 年
     * @return 夏時間開始日時
     */
    datetime getDstStartDatetime(const int yearValue) const {
        // 3月第2日曜
        int day = this.getNthWeekdayOfMonth(yearValue, 3, 0, 2);

        return StringToTime(
            StringFormat(
                "%04d.%02d.%02d 00:00:00",
                yearValue,
                3,
                day
            )
        );
    }

    /**
     * 夏時間終了日時を取得
     *
     * @param yearValue 年
     * @return 夏時間終了日時
     */
    datetime getDstEndDatetime(const int yearValue) const {
        // 11月第1日曜
        int day = this.getNthWeekdayOfMonth(yearValue, 11, 0, 1);

        return StringToTime(
            StringFormat(
                "%04d.%02d.%02d 00:00:00",
                yearValue,
                11,
                day
            )
        );
    }

    /**
     * 指定年月の第n曜日の日付を取得
     *
     * @param yearValue 年
     * @param monthValue 月
     * @param weekdayValue 曜日
     * @param nthValue 第n
     * @return 日
     */
    int getNthWeekdayOfMonth(
        const int yearValue,
        const int monthValue,
        const int weekdayValue,
        const int nthValue
    ) const {
        // 月初取得
        datetime firstDateTime = StringToTime(
            StringFormat(
                "%04d.%02d.01 00:00:00",
                yearValue,
                monthValue
            )
        );

        MqlDateTime dateTime;
        TimeToStruct(firstDateTime, dateTime);

        // 日付計算
        int firstDayOfWeek = dateTime.day_of_week;
        int offsetDay = (7 + weekdayValue - firstDayOfWeek) % 7;

        return 1 + offsetDay + 7 * (nthValue - 1);
    }

    /**
     * 週末セッション除外時間か判定
     *
     * @param dayOfWeekValue 曜日
     * @return true: 週末セッション除外時間
     */
    bool isWeekendSessionBlockedTime(const int dayOfWeekValue) const {
        if (dayOfWeekValue == 0) {
            return true;
        }

        if (dayOfWeekValue == 6) {
            return true;
        }

        return false;
    }

    /**
     * 東京セッションか判定
     *
     * @param jstHourValue 日本時間の時
     * @return true: 東京セッション
     */
    bool isTokyoSession(const int jstHourValue) const {
        if (jstHourValue >= 9 && jstHourValue < 15) {
            return true;
        }

        return false;
    }

    /**
     * ロンドンセッションか判定
     *
     * @param jstHourValue 日本時間の時
     * @param jstOffsetHourValue JST差分時間
     * @return true: ロンドンセッション
     */
    bool isLondonSession(const int jstHourValue, const int jstOffsetHourValue) const {
        if (jstOffsetHourValue == 6) {
            if (jstHourValue >= 16 || jstHourValue < 1) {
                return true;
            }

            return false;
        }

        if (jstHourValue >= 17 || jstHourValue < 2) {
            return true;
        }

        return false;
    }

    /**
     * ニューヨークセッションか判定
     *
     * @param jstHourValue 日本時間の時
     * @param jstOffsetHourValue JST差分時間
     * @return true: ニューヨークセッション
     */
    bool isNewYorkSession(const int jstHourValue, const int jstOffsetHourValue) const {
        if (jstOffsetHourValue == 6) {
            if (jstHourValue >= 21 || jstHourValue < 6) {
                return true;
            }

            return false;
        }

        if (jstHourValue >= 22 || jstHourValue < 7) {
            return true;
        }

        return false;
    }

    /**
     * ロールオーバー時間か判定
     *
     * @param jstHourValue 日本時間の時
     * @param jstMinuteValue 日本時間の分
     * @return true: ロールオーバー時間
     */
    bool isRolloverTime(const int jstHourValue, const int jstMinuteValue) const {
        if (jstHourValue == 6) {
            return true;
        }

        return false;
    }

    /**
     * 月曜早朝か判定
     *
     * @param dayOfWeekValue 曜日
     * @param jstHourValue 日本時間の時
     * @return true: 月曜早朝
     */
    bool isMondayEarly(const int dayOfWeekValue, const int jstHourValue) const {
        if (dayOfWeekValue != 1) {
            return false;
        }

        if (jstHourValue < 8) {
            return true;
        }

        return false;
    }

    /**
     * 金曜深夜か判定
     *
     * @param dayOfWeekValue 曜日
     * @param jstHourValue 日本時間の時
     * @return true: 金曜深夜
     */
    bool isFridayLate(const int dayOfWeekValue, const int jstHourValue) const {
        if (dayOfWeekValue == 5 && jstHourValue >= 23) {
            return true;
        }

        if (dayOfWeekValue == 6 && jstHourValue < 7) {
            return true;
        }

        return false;
    }

    /**
     * セッション種別を取得
     *
     * @param isWeekendSessionBlockedTimeValue 週末セッション除外時間
     * @param isTokyoSessionValue 東京セッション
     * @param isLondonSessionValue ロンドンセッション
     * @param isNewYorkSessionValue ニューヨークセッション
     * @param isLondonNewYorkOverlapValue ロンドンニューヨーク重複時間
     * @return セッション種別
     */
    string getSessionType(
        const bool isWeekendSessionBlockedTimeValue,
        const bool isTokyoSessionValue,
        const bool isLondonSessionValue,
        const bool isNewYorkSessionValue,
        const bool isLondonNewYorkOverlapValue
    ) const {
        if (isWeekendSessionBlockedTimeValue) {
            return "Other";
        }

        if (isLondonNewYorkOverlapValue) {
            return "LondonNewYork";
        }

        if (isTokyoSessionValue && isLondonSessionValue) {
            return "TokyoLondon";
        }

        if (isTokyoSessionValue) {
            return "Tokyo";
        }

        if (isLondonSessionValue) {
            return "London";
        }

        if (isNewYorkSessionValue) {
            return "NewYork";
        }

        return "Other";
    }

    /**
     * bool値文字列変換
     *
     * @param boolValue bool値
     * @return 文字列
     */
    string boolToString(const bool boolValue) const {
        if (boolValue) {
            return "true";
        }

        return "false";
    }

    /**
     * 通貨ペア桁数取得
     *
     * @param symbolNameValue 通貨ペア
     * @return 桁数
     */
    int getSymbolDigits(const string symbolNameValue) const {
        long digitsValue = 0;

        if (SymbolInfoInteger(symbolNameValue, SYMBOL_DIGITS, digitsValue)) {
            return (int)digitsValue;
        }

        return _Digits;
    }

    /**
     * pipsサイズ取得
     *
     * @param symbolNameValue 通貨ペア
     * @return 1pipあたりの価格差
     */
    double getPipSize(const string symbolNameValue) const {
        int digits = this.getSymbolDigits(symbolNameValue);
        double point = SymbolInfoDouble(symbolNameValue, SYMBOL_POINT);

        if (point <= 0.0) {
            point = _Point;
        }

        if (digits == 3 || digits == 5) {
            return point * 10.0;
        }

        return point;
    }

    /**
     * 価格差をpipsへ変換
     *
     * @param priceDifferenceValue 価格差
     * @param symbolNameValue 通貨ペア
     * @return pips
     */
    double convertPriceDifferenceToPips(
        const double priceDifferenceValue,
        const string symbolNameValue
    ) const {
        double pipSize = this.getPipSize(symbolNameValue);

        if (pipSize <= 0.0) {
            return 0.0;
        }

        return priceDifferenceValue / pipSize;
    }

    bool prependCommonValues(string &sourceValues[], string &rowValues[]) {
        string commonValues[];
        this.createCommonValues(commonValues);

        int totalFieldCount = ArraySize(commonValues) + ArraySize(sourceValues);
        ArrayResize(rowValues, totalFieldCount);

        int index = 0;

        for (int i = 0; i < ArraySize(commonValues); i++) {
            rowValues[index++] = commonValues[i];
        }

        for (int i = 0; i < ArraySize(sourceValues); i++) {
            rowValues[index++] = sourceValues[i];
        }

        if (index != totalFieldCount) {
            Print(
                "ElliotAllFile.prependCommonValues invalid field count. index="
                + IntegerToString(index)
                + " expected=" + IntegerToString(totalFieldCount)
            );

            return false;
        }

        return true;
    }

    /**
     * 共通ヘッダー + 1時間足ヘッダー作成
     *
     * @param headerValues ヘッダー値
     */
    void createHeaderValuesWithCommon(string &headerValues[]) const {
        string commonHeaderValues[];
        string baseHeaderValues[];

        this.createCommonHeaderValues(commonHeaderValues);
        this.createHeaderValues(baseHeaderValues);

        int totalFieldCount = ArraySize(commonHeaderValues) + ArraySize(baseHeaderValues);
        ArrayResize(headerValues, totalFieldCount);

        int index = 0;

        for (int i = 0; i < ArraySize(commonHeaderValues); i++) {
            headerValues[index++] = commonHeaderValues[i];
        }

        for (int i = 0; i < ArraySize(baseHeaderValues); i++) {
            headerValues[index++] = baseHeaderValues[i];
        }

        if (index != totalFieldCount) {
            Print(
                "ElliotAllFile.createHeaderValuesWithCommon invalid field count. index="
                + IntegerToString(index)
                + " expected=" + IntegerToString(totalFieldCount)
            );
        }
    }

    /**
     * CSV文字列から行データ作成
     *
     * 1つのstringに全CSVデータが入っている場合に使用する。
     * 共通情報 + 時間足データを対象にする。
     *
     * 有効な列数:
     *   共通情報列数 + 1時間足分の列数 * 時間足数
     *
     * 注意:
     *   csvTextValue の末尾に区切り文字が付いている場合、
     *   StringSplit() が末尾の空列も1列として数えるため、
     *   分解前に末尾の区切り文字だけ除去する。
     *
     * @param csvTextValue 共通情報を含むCSV文字列
     * @param rowValues 作成後の行データ
     * @return 成功時true
     */
    bool createRowValuesFromCsvTextValue(
        const string csvTextValue,
        string &rowValues[]
    ) const {
        string normalizedCsvText = this.removeTrailingDelimiter(csvTextValue);

        ushort delimiterCharacter = StringGetCharacter(this.delimiter, 0);
        int fieldCount = StringSplit(normalizedCsvText, delimiterCharacter, rowValues);

        if (fieldCount <= 0) {
            Print(
                "ElliotAllFile.createRowValuesFromCsvTextValue empty csv. csv="
                + csvTextValue
            );

            return false;
        }

        int commonFieldCount = ELLIOT_ALL_FILE_COMMON_FIELD_COUNT;
        int timeFrameFieldCount = fieldCount - commonFieldCount;

        if (timeFrameFieldCount <= 0) {
            Print(
                "ElliotAllFile.createRowValuesFromCsvTextValue invalid field count="
                + IntegerToString(fieldCount)
                + " expected greater than common field count="
                + IntegerToString(commonFieldCount)
                + " csv=" + normalizedCsvText
            );

            return false;
        }

        if ((timeFrameFieldCount % ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT) != 0) {
            Print(
                "ElliotAllFile.createRowValuesFromCsvTextValue invalid field count="
                + IntegerToString(fieldCount)
                + " expected common field count "
                + IntegerToString(commonFieldCount)
                + " + multiple of "
                + IntegerToString(ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT)
                + " csv=" + normalizedCsvText
            );

            return false;
        }

        return true;
    }

    /**
     * 末尾区切り文字除去
     *
     * CSV文字列の末尾に付いた区切り文字だけを除去する。
     * 中間の空項目は維持する。
     *
     * @param csvTextValue CSV文字列
     * @return 末尾区切り文字除去後CSV文字列
     */
    string removeTrailingDelimiter(const string csvTextValue) const {
        string result = csvTextValue;
        string delimiterValue = this.delimiter;

        StringTrimLeft(result);
        StringTrimRight(result);

        if (delimiterValue == "") {
            return result;
        }

        int delimiterLength = StringLen(delimiterValue);

        while (StringLen(result) >= delimiterLength) {
            int startPosition = StringLen(result) - delimiterLength;

            if (StringSubstr(result, startPosition, delimiterLength) != delimiterValue) {
                break;
            }

            result = StringSubstr(result, 0, startPosition);
            StringTrimRight(result);
        }

        return result;
    }

    /**
     * 1時間足CSV文字列分解
     *
     * @param csvTextValue CSV文字列
     * @param fieldValues フィールド値
     * @return 成功時true
     */
    bool splitSingleTimeFrameCsvText(
        const string csvTextValue,
        string &fieldValues[]
    ) const {
        ushort delimiterCharacter = StringGetCharacter(this.delimiter, 0);
        int fieldCount = StringSplit(csvTextValue, delimiterCharacter, fieldValues);

        if (fieldCount != ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT) {
            Print(
                "ElliotAllFile.splitSingleTimeFrameCsvText invalid field count="
                + IntegerToString(fieldCount)
                + " expected=" + IntegerToString(ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT)
                + " csv=" + csvTextValue
            );

            return false;
        }

        return true;
    }

    /**
     * キーファイル名作成
     *
     * @param symbolNameValue 通貨ペア
     * @param timeFrameValue 時間足
     * @return キーファイル名
     */
    string createKeyFileName(
        const string symbolNameValue,
        const ENUM_TIMEFRAMES timeFrameValue
    ) const {
        return symbolNameValue + "_" + this.convertTimeFrameToString(timeFrameValue) + ".csv";
    }

    /**
     * 複数時間足キーファイル名作成
     *
     * @param symbolNameValue 通貨ペア
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @return キーファイル名
     */
    string createMultiTimeFrameKeyFileName(
        const string symbolNameValue,
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue
    ) const {
        return symbolNameValue
            + "_" + this.convertTimeFrameToString(startTimeFrameValue)
            + "_TO_" + this.convertTimeFrameToString(endTimeFrameValue)
            + ".csv";
    }

    /**
     * 時間足文字列変換
     *
     * @param timeFrameValue 時間足
     * @return 時間足文字列
     */
    string convertTimeFrameToString(const ENUM_TIMEFRAMES timeFrameValue) const {
        switch (timeFrameValue) {
            case PERIOD_M1: return "M1";
            case PERIOD_M2: return "M2";
            case PERIOD_M3: return "M3";
            case PERIOD_M4: return "M4";
            case PERIOD_M5: return "M5";
            case PERIOD_M6: return "M6";
            case PERIOD_M10: return "M10";
            case PERIOD_M12: return "M12";
            case PERIOD_M15: return "M15";
            case PERIOD_M20: return "M20";
            case PERIOD_M30: return "M30";
            case PERIOD_H1: return "H1";
            case PERIOD_H2: return "H2";
            case PERIOD_H3: return "H3";
            case PERIOD_H4: return "H4";
            case PERIOD_H6: return "H6";
            case PERIOD_H8: return "H8";
            case PERIOD_H12: return "H12";
            case PERIOD_D1: return "D1";
            case PERIOD_W1: return "W1";
            case PERIOD_MN1: return "MN1";
        }

        return EnumToString(timeFrameValue);
    }

    /**
     * ヘッダー値作成
     *
     * @param headerValues ヘッダー値
     */
    void createHeaderValues(string &headerValues[]) const {
        ArrayResize(headerValues, ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT);

        int index = 0;
        headerValues[index++] = "目印";
        headerValues[index++] = "時間足";
        headerValues[index++] = "売買";
        headerValues[index++] = "トレンド";
        headerValues[index++] = "latest:エリオット波動";
        headerValues[index++] = "latest:エリオット下位波動";
        headerValues[index++] = "latest:レート";
        headerValues[index++] = "latest:波動のpips";
        headerValues[index++] = "latest:フィボナッチエクスパンション";
        headerValues[index++] = "latest:フィボナッチ";
        headerValues[index++] = "latest:fiboDepthZoneLabel";
        headerValues[index++] = "latest:barIndex";
        headerValues[index++] = "latest:barTime";
        headerValues[index++] = "latest:waveBarsFromStart";
        headerValues[index++] = "latest:isPeak";
        headerValues[index++] = "latest:isAddedPoint";
        headerValues[index++] = "Open1";
        headerValues[index++] = "High1";
        headerValues[index++] = "Low1";
        headerValues[index++] = "Close1";
        headerValues[index++] = "Open0";
        headerValues[index++] = "High0";
        headerValues[index++] = "Low0";
        headerValues[index++] = "Close0";
        headerValues[index++] = "FE618Price";
        headerValues[index++] = "FE1000Price";
        headerValues[index++] = "FE1272Price";
        headerValues[index++] = "FE1618Price";
        headerValues[index++] = "FE2000Price";
        headerValues[index++] = "DistanceToFE2000Pips";
        headerValues[index++] = "前波動最後のエリオット波動";
        headerValues[index++] = "ATR14";
        headerValues[index++] = "オシレータ値";
        headerValues[index++] = "ストキャスティクスのメイン順序";
        headerValues[index++] = "ストキャスティクスのメイン順序による売買";
        headerValues[index++] = "ストキャス短期値";
        headerValues[index++] = "ストキャス短期Main";
        headerValues[index++] = "ストキャス短期Signal";
        headerValues[index++] = "ストキャス中期値";
        headerValues[index++] = "ストキャス中期Main";
        headerValues[index++] = "ストキャス中期Signal";
        headerValues[index++] = "ストキャス長期値";
        headerValues[index++] = "ストキャス長期Main";
        headerValues[index++] = "ストキャス長期Signal";
        headerValues[index++] = "GMMAトレンド値";
        headerValues[index++] = "GMMAクロス値";
        headerValues[index++] = "EMA30";
        headerValues[index++] = "EMA60";
        headerValues[index++] = "EMA30Ema60DiffPips";
        headerValues[index++] = "Ema200ClosePosition";
        headerValues[index++] = "Ema200Close1";
        headerValues[index++] = "Ema200Shift1";
        headerValues[index++] = "Ema200Compare";
        headerValues[index++] = "Ema200SlopePips";
        headerValues[index++] = "Ema200SlopeDirection";
        headerValues[index++] = "Ema200UpCount";
        headerValues[index++] = "Ema200DownCount";
        headerValues[index++] = "Ema200TrendCount";
        headerValues[index++] = "Ema200IsBuy";
        headerValues[index++] = "Ema200IsSell";
        headerValues[index++] = "pre3:エリオット波動";
        headerValues[index++] = "pre3:エリオット下位波動";
        headerValues[index++] = "pre3:レート";
        headerValues[index++] = "pre3:波動のpips";
        headerValues[index++] = "pre3:フィボナッチエクスパンション";
        headerValues[index++] = "pre3:フィボナッチ";
        headerValues[index++] = "pre3:fiboDepthZoneLabel";
        headerValues[index++] = "pre3:barIndex";
        headerValues[index++] = "pre3:barTime";
        headerValues[index++] = "pre3:waveBarsFromStart";
        headerValues[index++] = "pre3:isPeak";
        headerValues[index++] = "pre3:isAddedPoint";
        headerValues[index++] = "pre2:エリオット波動";
        headerValues[index++] = "pre2:エリオット下位波動";
        headerValues[index++] = "pre2:レート";
        headerValues[index++] = "pre2:波動のpips";
        headerValues[index++] = "pre2:フィボナッチエクスパンション";
        headerValues[index++] = "pre2:フィボナッチ";
        headerValues[index++] = "pre2:fiboDepthZoneLabel";
        headerValues[index++] = "pre2:barIndex";
        headerValues[index++] = "pre2:barTime";
        headerValues[index++] = "pre2:waveBarsFromStart";
        headerValues[index++] = "pre2:isPeak";
        headerValues[index++] = "pre2:isAddedPoint";
        headerValues[index++] = "pre1:エリオット波動";
        headerValues[index++] = "pre1:エリオット下位波動";
        headerValues[index++] = "pre1:レート";
        headerValues[index++] = "pre1:波動のpips";
        headerValues[index++] = "pre1:フィボナッチエクスパンション";
        headerValues[index++] = "pre1:フィボナッチ";
        headerValues[index++] = "pre1:fiboDepthZoneLabel";
        headerValues[index++] = "pre1:barIndex";
        headerValues[index++] = "pre1:barTime";
        headerValues[index++] = "pre1:waveBarsFromStart";
        headerValues[index++] = "pre1:isPeak";
        headerValues[index++] = "pre1:isAddedPoint";

        if (!this.isValidTimeFrameFieldCount(index)) {
            Print(
                "ElliotAllFile.createHeaderValues invalid field count. index="
                + IntegerToString(index)
                + " expected=" + IntegerToString(ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT)
            );
        }
    }

    /**
     * 時間足範囲作成
     *
     * @param startTimeFrameValue 開始時間足
     * @param endTimeFrameValue 終了時間足
     * @param timeFrameValues 時間足配列
     * @return 成功時true
     */
    bool createTimeFrameRange(
        const ENUM_TIMEFRAMES startTimeFrameValue,
        const ENUM_TIMEFRAMES endTimeFrameValue,
        ENUM_TIMEFRAMES &timeFrameValues[]
    ) const {
        ENUM_TIMEFRAMES supportedTimeFrames[];
        this.createSupportedTimeFrames(supportedTimeFrames);

        int startIndex = this.findSupportedTimeFrameIndex(startTimeFrameValue);
        int endIndex = this.findSupportedTimeFrameIndex(endTimeFrameValue);

        if (startIndex < 0 || endIndex < 0) {
            Print(
                "ElliotAllFile.createTimeFrameRange unsupported timeframe. start="
                + EnumToString(startTimeFrameValue)
                + " end=" + EnumToString(endTimeFrameValue)
            );

            return false;
        }

        if (startIndex > endIndex) {
            Print(
                "ElliotAllFile.createTimeFrameRange invalid order. start must be higher timeframe. start="
                + this.convertTimeFrameToString(startTimeFrameValue)
                + " end=" + this.convertTimeFrameToString(endTimeFrameValue)
            );

            return false;
        }

        int count = endIndex - startIndex + 1;
        ArrayResize(timeFrameValues, count);

        int index = 0;

        for (int i = startIndex; i <= endIndex; i++) {
            timeFrameValues[index++] = supportedTimeFrames[i];
        }

        return true;
    }

    /**
     * 対象時間足作成
     *
     * @param supportedTimeFrames 対象時間足
     */
    void createSupportedTimeFrames(ENUM_TIMEFRAMES &supportedTimeFrames[]) const {
        ArrayResize(supportedTimeFrames, 6);
        supportedTimeFrames[0] = PERIOD_D1;
        supportedTimeFrames[1] = PERIOD_H4;
        supportedTimeFrames[2] = PERIOD_H1;
        supportedTimeFrames[3] = PERIOD_M15;
        supportedTimeFrames[4] = PERIOD_M5;
        supportedTimeFrames[5] = PERIOD_M1;
    }

    /**
     * 対象時間足インデックス検索
     *
     * @param timeFrameValue 時間足
     * @return インデックス
     */
    int findSupportedTimeFrameIndex(const ENUM_TIMEFRAMES timeFrameValue) const {
        ENUM_TIMEFRAMES supportedTimeFrames[];
        this.createSupportedTimeFrames(supportedTimeFrames);

        for (int i = 0; i < ArraySize(supportedTimeFrames); i++) {
            if (supportedTimeFrames[i] == timeFrameValue) {
                return i;
            }
        }

        return -1;
    }

    /**
     * 1時間足フィールド数妥当性判定
     *
     * @param fieldCountValue フィールド数
     * @return 妥当な場合true
     */
    bool isValidTimeFrameFieldCount(const int fieldCountValue) const {
        return fieldCountValue == ELLIOT_ALL_FILE_TIMEFRAME_FIELD_COUNT;
    }
};

#endif
//+------------------------------------------------------------------+
