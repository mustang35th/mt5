//+------------------------------------------------------------------+
//|                                  ProfitRetracementStateStore.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Persistence
 * File: ProfitRetracementStateStore.mqh
 */

#ifndef MSTNGEA_PERSISTENCE_PROFITRETRACEMENTSTATESTORE_MQH
#define MSTNGEA_PERSISTENCE_PROFITRETRACEMENTSTATESTORE_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <MstngEa\Domain\ProfitRetracementState.mqh>

/**
 * Persists the profit retracement state for one EA context.
 */
class ProfitRetracementStateStore {
public:
    /**
     * Constructor.
     *
     * @param fromMarketContext Market context.
     * @param fromMagicNumber Magic number.
     * @param fromEnabled true to enable persistence outside the tester.
     */
    ProfitRetracementStateStore(
        MarketContext &fromMarketContext,
        ulong fromMagicNumber,
        bool fromEnabled
    ) {
        this.marketContext = fromMarketContext;
        this.magicNumber = fromMagicNumber;
        this.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        this.accountServer = AccountInfoString(ACCOUNT_SERVER);
        this.enabled = fromEnabled;

        if (MQLInfoInteger(MQL_TESTER)) {
            this.enabled = false;
        }

        this.commonFolder = this.enabled;
        this.lastErrorMessage = "";
        this.lastSavedText = "";
        this.lastSaveMilliseconds = 0;
        this.isKnownEmpty = false;
        this.filePath = this.buildFilePath();
        this.temporaryFilePath = this.buildTemporaryFilePath();
    }

    /**
     * Returns whether persistence is enabled.
     *
     * @return true when enabled.
     */
    bool isEnabled() {
        return this.enabled;
    }

    /**
     * Returns whether the final state file exists.
     *
     * @return true when the file exists.
     */
    bool exists() {
        if (!this.enabled) {
            return false;
        }

        bool isExisting = FileIsExist(
            this.filePath,
            this.getCommonFlag()
        );

        if (isExisting) {
            this.isKnownEmpty = false;
        }

        return isExisting;
    }

    /**
     * Loads and validates the persisted state.
     *
     * @param fromState Destination state.
     * @return true when a valid state was loaded.
     */
    bool load(ProfitRetracementState &fromState) {
        this.lastErrorMessage = "";

        if (!this.enabled) {
            this.lastErrorMessage = "Profit retracement persistence is disabled";
            return false;
        }

        if (!this.exists()) {
            this.lastErrorMessage = "Profit retracement state file does not exist";
            return false;
        }

        int fileHandle = FileOpen(
            this.filePath,
            FILE_READ | FILE_TXT | FILE_UNICODE | FILE_SHARE_READ
                | this.getCommonFlag()
        );

        if (fileHandle == INVALID_HANDLE) {
            this.setFileError("Profit retracement state open failed");
            return false;
        }

        string lines[];
        bool isRead = this.readLines(fileHandle, lines);
        FileClose(fileHandle);

        if (!isRead) {
            return false;
        }

        ProfitRetracementState loadedState;

        if (!this.parseLines(lines, loadedState)) {
            return false;
        }

        fromState.copyFrom(loadedState);
        this.lastSavedText = this.buildStateText(fromState);
        this.lastSaveMilliseconds = GetTickCount64();
        this.isKnownEmpty = false;
        return true;
    }

    /**
     * Saves the state using a temporary file and atomic replacement.
     *
     * @param fromState State to persist.
     * @param fromForce true to bypass the write interval.
     * @return true when saved or no write is currently required.
     */
    bool save(ProfitRetracementState &fromState, bool fromForce) {
        this.lastErrorMessage = "";

        if (!this.enabled) {
            return true;
        }

        if (!this.validateState(fromState)) {
            return false;
        }

        string stateText = this.buildStateText(fromState);

        if (stateText == this.lastSavedText) {
            if (!fromForce || this.exists()) {
                return true;
            }
        }

        ulong currentMilliseconds = GetTickCount64();

        if (!fromForce
                && this.lastSavedText != ""
                && currentMilliseconds >= this.lastSaveMilliseconds
                && currentMilliseconds - this.lastSaveMilliseconds < 1000) {
            return true;
        }

        int fileHandle = FileOpen(
            this.temporaryFilePath,
            FILE_WRITE | FILE_TXT | FILE_UNICODE | this.getCommonFlag()
        );

        if (fileHandle == INVALID_HANDLE) {
            this.setFileError("Profit retracement temporary state open failed");
            return false;
        }

        this.isKnownEmpty = false;

        string persistedText = stateText;
        persistedText += "updated_server_time="
            + (string)((long)TimeCurrent())
            + "\r\n";
        uint writtenSize = FileWriteString(fileHandle, persistedText);
        FileFlush(fileHandle);
        FileClose(fileHandle);

        uint expectedSize = (uint)StringLen(persistedText) * 2;

        if (writtenSize != expectedSize) {
            FileDelete(
                this.temporaryFilePath,
                this.getCommonFlag()
            );
            this.lastErrorMessage =
                "Profit retracement temporary state write is incomplete";
            return false;
        }

        ResetLastError();
        bool isMoved = FileMove(
            this.temporaryFilePath,
            this.getCommonFlag(),
            this.filePath,
            FILE_REWRITE | this.getCommonFlag()
        );

        if (!isMoved) {
            this.setFileError("Profit retracement state replace failed");
            return false;
        }

        this.lastSavedText = stateText;
        this.lastSaveMilliseconds = currentMilliseconds;
        this.isKnownEmpty = false;
        return true;
    }

    /**
     * Clears final and temporary state files.
     *
     * @return true when both files are absent.
     */
    bool clear() {
        this.lastErrorMessage = "";
        this.lastSavedText = "";
        this.lastSaveMilliseconds = 0;

        if (!this.enabled) {
            this.isKnownEmpty = true;
            return true;
        }

        if (this.isKnownEmpty) {
            return true;
        }

        bool isCleared = true;
        int commonFlag = this.getCommonFlag();

        if (FileIsExist(this.filePath, commonFlag)) {
            ResetLastError();

            if (!FileDelete(this.filePath, commonFlag)) {
                this.setFileError("Profit retracement state delete failed");
                isCleared = false;
            }
        }

        if (FileIsExist(this.temporaryFilePath, commonFlag)) {
            ResetLastError();

            if (!FileDelete(this.temporaryFilePath, commonFlag)) {
                this.setFileError("Profit retracement temporary state delete failed");
                isCleared = false;
            }
        }

        if (isCleared) {
            this.isKnownEmpty = true;
        }

        return isCleared;
    }

    /**
     * Returns the final state file path.
     *
     * @return Relative state file path.
     */
    string getFilePath() {
        return this.filePath;
    }

    /**
     * Returns the temporary state file path.
     *
     * @return Relative temporary file path.
     */
    string getTemporaryFilePath() {
        return this.temporaryFilePath;
    }

    /**
     * Returns whether the common files folder is used.
     *
     * @return true when FILE_COMMON is used.
     */
    bool isCommonFolder() {
        return this.commonFolder;
    }

    /**
     * Returns the last error message.
     *
     * @return Last error message.
     */
    string getLastErrorMessage() {
        return this.lastErrorMessage;
    }

private:
    /** Market context */
    MarketContext marketContext;

    /** Magic number */
    ulong magicNumber;

    /** Account login */
    long accountLogin;

    /** Account server */
    string accountServer;

    /** true when persistence is enabled */
    bool enabled;

    /** true when FILE_COMMON is used */
    bool commonFolder;

    /** Final state file path */
    string filePath;

    /** Temporary state file path */
    string temporaryFilePath;

    /** Last error message */
    string lastErrorMessage;

    /** Last successfully saved payload */
    string lastSavedText;

    /** Last successful save tick */
    ulong lastSaveMilliseconds;

    /** true after this instance confirmed both state files are absent */
    bool isKnownEmpty;

    /**
     * Reads text lines with a strict upper bound.
     *
     * @param fromFileHandle Open file handle.
     * @param fromLines Destination lines.
     * @return true when read successfully.
     */
    bool readLines(int fromFileHandle, string &fromLines[]) {
        ArrayResize(fromLines, 0);

        while (!FileIsEnding(fromFileHandle)) {
            if (ArraySize(fromLines) >= 64) {
                this.lastErrorMessage = "Profit retracement state has too many lines";
                return false;
            }

            int lineIndex = ArraySize(fromLines);
            ArrayResize(fromLines, lineIndex + 1);
            fromLines[lineIndex] = FileReadString(fromFileHandle);
        }

        return true;
    }

    /**
     * Parses and validates serialized lines.
     *
     * @param fromLines Serialized lines.
     * @param fromState Destination state.
     * @return true when valid.
     */
    bool parseLines(string &fromLines[], ProfitRetracementState &fromState) {
        if (ArraySize(fromLines) != 22) {
            this.lastErrorMessage = "Profit retracement state field count is invalid";
            return false;
        }

        if (fromLines[0] != "MSTNGEA_PROFIT_RETRACEMENT_STATE") {
            this.lastErrorMessage = "Profit retracement state signature is invalid";
            return false;
        }

        string value = "";
        long longValue = 0;
        ulong unsignedValue = 0;
        bool boolValue = false;

        if (!this.getLineValue(fromLines[1], "schema_version", value)
                || value != "1") {
            this.lastErrorMessage = "Profit retracement state schema is unsupported";
            return false;
        }

        if (!this.getLineValue(fromLines[2], "account_login", value)
                || !this.parseLong(value, longValue)
                || longValue != this.accountLogin) {
            this.lastErrorMessage = "Profit retracement state account login mismatch";
            return false;
        }

        if (!this.getLineValue(fromLines[3], "account_server", value)
                || value != this.accountServer) {
            this.lastErrorMessage = "Profit retracement state account server mismatch";
            return false;
        }

        if (!this.getLineValue(fromLines[4], "symbol", value)
                || value != this.marketContext.symbolName) {
            this.lastErrorMessage = "Profit retracement state symbol mismatch";
            return false;
        }

        if (!this.getLineValue(fromLines[5], "timeframe", value)
                || !this.parseLong(value, longValue)
                || longValue != (long)this.marketContext.timeFrame) {
            this.lastErrorMessage = "Profit retracement state timeframe mismatch";
            return false;
        }

        if (!this.getLineValue(fromLines[6], "magic", value)
                || !this.parseUnsignedLong(value, unsignedValue)
                || unsignedValue != this.magicNumber) {
            this.lastErrorMessage = "Profit retracement state magic mismatch";
            return false;
        }

        if (!this.getLineValue(fromLines[7], "position_identifier", value)
                || !this.parseUnsignedLong(value, fromState.positionIdentifier)) {
            this.lastErrorMessage = "Profit retracement position identifier is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[8], "position_ticket", value)
                || !this.parseUnsignedLong(value, fromState.positionTicket)) {
            this.lastErrorMessage = "Profit retracement position ticket is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[9], "open_time_msc", value)
                || !this.parseLong(value, fromState.positionOpenTimeMilliseconds)) {
            this.lastErrorMessage = "Profit retracement open time is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[10], "is_buy", value)
                || !this.parseBool(value, boolValue)) {
            this.lastErrorMessage = "Profit retracement side is invalid";
            return false;
        }
        fromState.isBuy = boolValue;

        if (!this.getLineValue(fromLines[11], "open_price", value)
                || !this.parseDouble(value, fromState.openPrice)) {
            this.lastErrorMessage = "Profit retracement open price is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[12], "initial_stop_loss", value)
                || !this.parseDouble(value, fromState.initialStopLoss)) {
            this.lastErrorMessage = "Profit retracement initial stop loss is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[13], "position_volume", value)
                || !this.parseDouble(value, fromState.positionVolume)) {
            this.lastErrorMessage = "Profit retracement position volume is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[14], "best_price", value)
                || !this.parseDouble(value, fromState.bestPrice)) {
            this.lastErrorMessage = "Profit retracement best price is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[15], "max_floating_profit", value)
                || !this.parseDouble(value, fromState.maxFloatingProfit)) {
            this.lastErrorMessage = "Profit retracement max profit is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[16], "initial_risk_distance", value)
                || !this.parseDouble(value, fromState.initialRiskDistance)) {
            this.lastErrorMessage = "Profit retracement initial risk is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[17], "initial_risk_available", value)
                || !this.parseBool(value, boolValue)) {
            this.lastErrorMessage = "Profit retracement initial risk availability is invalid";
            return false;
        }
        fromState.isInitialRiskAvailable = boolValue;

        if (!this.getLineValue(fromLines[18], "activated", value)
                || !this.parseBool(value, boolValue)) {
            this.lastErrorMessage = "Profit retracement activation is invalid";
            return false;
        }
        fromState.activated = boolValue;

        if (!this.getLineValue(fromLines[19], "configured_start_r", value)
                || !this.parseDouble(value, fromState.configuredStartR)) {
            this.lastErrorMessage = "Profit retracement start R is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[20], "configured_rate", value)
                || !this.parseDouble(value, fromState.configuredRetracementRate)) {
            this.lastErrorMessage = "Profit retracement rate is invalid";
            return false;
        }

        if (!this.getLineValue(fromLines[21], "updated_server_time", value)
                || !this.parseLong(value, longValue)) {
            this.lastErrorMessage = "Profit retracement update time is invalid";
            return false;
        }

        if (!this.validateState(fromState)) {
            return false;
        }

        return true;
    }

    /**
     * Validates state values before reading or writing.
     *
     * @param fromState State to validate.
     * @return true when valid.
     */
    bool validateState(ProfitRetracementState &fromState) {
        if (fromState.positionIdentifier == 0
                || fromState.positionTicket == 0
                || fromState.positionOpenTimeMilliseconds < 0
                || fromState.openPrice <= 0.0
                || fromState.initialStopLoss < 0.0
                || fromState.positionVolume <= 0.0
                || fromState.bestPrice <= 0.0
                || fromState.initialRiskDistance < 0.0) {
            this.lastErrorMessage = "Profit retracement state contains invalid values";
            return false;
        }

        if (!MathIsValidNumber(fromState.openPrice)
                || !MathIsValidNumber(fromState.initialStopLoss)
                || !MathIsValidNumber(fromState.positionVolume)
                || !MathIsValidNumber(fromState.bestPrice)
                || !MathIsValidNumber(fromState.maxFloatingProfit)
                || !MathIsValidNumber(fromState.initialRiskDistance)
                || !MathIsValidNumber(fromState.configuredStartR)
                || !MathIsValidNumber(fromState.configuredRetracementRate)) {
            this.lastErrorMessage = "Profit retracement state contains non-finite values";
            return false;
        }

        if (fromState.isInitialRiskAvailable
                && (fromState.initialStopLoss <= 0.0
                    || fromState.initialRiskDistance <= 0.0)) {
            this.lastErrorMessage = "Profit retracement initial risk is inconsistent";
            return false;
        }

        if (fromState.isInitialRiskAvailable) {
            bool isStopLossDirectionValid =
                fromState.initialStopLoss < fromState.openPrice;

            if (!fromState.isBuy) {
                isStopLossDirectionValid =
                    fromState.initialStopLoss > fromState.openPrice;
            }

            double expectedRiskDistance = MathAbs(
                fromState.openPrice - fromState.initialStopLoss
            );
            double allowedDifference = SymbolInfoDouble(
                this.marketContext.symbolName,
                SYMBOL_POINT
            ) * 2.0;

            if (allowedDifference <= 0.0) {
                allowedDifference = 0.00000001;
            }

            if (!isStopLossDirectionValid
                    || MathAbs(
                        fromState.initialRiskDistance
                            - expectedRiskDistance
                    ) > allowedDifference) {
                this.lastErrorMessage =
                    "Profit retracement initial risk direction is invalid";
                return false;
            }
        }

        if (fromState.activated && !fromState.isInitialRiskAvailable) {
            this.lastErrorMessage = "Profit retracement activation is inconsistent";
            return false;
        }

        return true;
    }

    /**
     * Builds the complete serialized payload.
     *
     * @param fromState State to serialize.
     * @return Serialized payload.
     */
    string buildStateText(ProfitRetracementState &fromState) {
        string isBuyText = "0";
        string isInitialRiskAvailableText = "0";
        string activatedText = "0";

        if (fromState.isBuy) {
            isBuyText = "1";
        }

        if (fromState.isInitialRiskAvailable) {
            isInitialRiskAvailableText = "1";
        }

        if (fromState.activated) {
            activatedText = "1";
        }

        string stateText = "MSTNGEA_PROFIT_RETRACEMENT_STATE\r\n";
        stateText += "schema_version=1\r\n";
        stateText += "account_login=" + (string)this.accountLogin + "\r\n";
        stateText += "account_server=" + this.accountServer + "\r\n";
        stateText += "symbol=" + this.marketContext.symbolName + "\r\n";
        stateText += "timeframe=" + (string)((long)this.marketContext.timeFrame) + "\r\n";
        stateText += "magic=" + (string)this.magicNumber + "\r\n";
        stateText += "position_identifier=" + (string)fromState.positionIdentifier + "\r\n";
        stateText += "position_ticket=" + (string)fromState.positionTicket + "\r\n";
        stateText += "open_time_msc=" + (string)fromState.positionOpenTimeMilliseconds + "\r\n";
        stateText += "is_buy=" + isBuyText + "\r\n";
        stateText += "open_price=" + DoubleToString(fromState.openPrice, 16) + "\r\n";
        stateText += "initial_stop_loss=" + DoubleToString(fromState.initialStopLoss, 16) + "\r\n";
        stateText += "position_volume=" + DoubleToString(fromState.positionVolume, 16) + "\r\n";
        stateText += "best_price=" + DoubleToString(fromState.bestPrice, 16) + "\r\n";
        stateText += "max_floating_profit=" + DoubleToString(fromState.maxFloatingProfit, 16) + "\r\n";
        stateText += "initial_risk_distance=" + DoubleToString(fromState.initialRiskDistance, 16) + "\r\n";
        stateText += "initial_risk_available=" + isInitialRiskAvailableText + "\r\n";
        stateText += "activated=" + activatedText + "\r\n";
        stateText += "configured_start_r=" + DoubleToString(fromState.configuredStartR, 16) + "\r\n";
        stateText += "configured_rate=" + DoubleToString(fromState.configuredRetracementRate, 16) + "\r\n";
        return stateText;
    }

    /**
     * Extracts a value from a key-value line.
     *
     * @param fromLine Serialized line.
     * @param fromKey Expected key.
     * @param fromValue Extracted value.
     * @return true when the key matches.
     */
    bool getLineValue(string fromLine, string fromKey, string &fromValue) {
        string prefix = fromKey + "=";

        if (StringFind(fromLine, prefix) != 0) {
            return false;
        }

        fromValue = StringSubstr(fromLine, StringLen(prefix));
        return true;
    }

    /**
     * Parses a signed integer.
     *
     * @param fromText Source text.
     * @param fromValue Parsed value.
     * @return true when valid.
     */
    bool parseLong(string fromText, long &fromValue) {
        if (!this.isIntegerText(fromText, true)) {
            return false;
        }

        fromValue = StringToInteger(fromText);
        return true;
    }

    /**
     * Parses an unsigned integer without a floating-point conversion.
     *
     * @param fromText Source text.
     * @param fromValue Parsed value.
     * @return true when valid.
     */
    bool parseUnsignedLong(string fromText, ulong &fromValue) {
        if (!this.isIntegerText(fromText, false)) {
            return false;
        }

        long signedValue = StringToInteger(fromText);

        if (signedValue < 0) {
            return false;
        }

        fromValue = (ulong)signedValue;
        return true;
    }

    /**
     * Validates integer text.
     *
     * @param fromText Source text.
     * @param fromSigned true to permit a leading minus sign.
     * @return true when valid.
     */
    bool isIntegerText(string fromText, bool fromSigned) {
        int textLength = StringLen(fromText);

        if (textLength <= 0) {
            return false;
        }

        int startIndex = 0;

        if (fromSigned && StringGetCharacter(fromText, 0) == 45) {
            if (textLength == 1) {
                return false;
            }

            startIndex = 1;
        }

        for (int i = startIndex; i < textLength; i++) {
            ushort character = StringGetCharacter(fromText, i);

            if (character < 48 || character > 57) {
                return false;
            }
        }

        return true;
    }

    /**
     * Parses a finite decimal value.
     *
     * @param fromText Source text.
     * @param fromValue Parsed value.
     * @return true when valid.
     */
    bool parseDouble(string fromText, double &fromValue) {
        if (!this.isDecimalText(fromText)) {
            return false;
        }

        fromValue = StringToDouble(fromText);
        return MathIsValidNumber(fromValue);
    }

    /**
     * Validates decimal text emitted by DoubleToString.
     *
     * @param fromText Source text.
     * @return true when valid.
     */
    bool isDecimalText(string fromText) {
        int textLength = StringLen(fromText);

        if (textLength <= 0) {
            return false;
        }

        int startIndex = 0;
        bool hasDigit = false;
        bool hasDecimalPoint = false;

        if (StringGetCharacter(fromText, 0) == 45) {
            if (textLength == 1) {
                return false;
            }

            startIndex = 1;
        }

        for (int i = startIndex; i < textLength; i++) {
            ushort character = StringGetCharacter(fromText, i);

            if (character >= 48 && character <= 57) {
                hasDigit = true;
                continue;
            }

            if (character == 46 && !hasDecimalPoint) {
                hasDecimalPoint = true;
                continue;
            }

            return false;
        }

        return hasDigit;
    }

    /**
     * Parses a strict boolean value.
     *
     * @param fromText Source text.
     * @param fromValue Parsed value.
     * @return true when valid.
     */
    bool parseBool(string fromText, bool &fromValue) {
        if (fromText == "0") {
            fromValue = false;
            return true;
        }

        if (fromText == "1") {
            fromValue = true;
            return true;
        }

        return false;
    }

    /**
     * Builds the final state file path.
     *
     * @return Relative state file path.
     */
    string buildFilePath() {
        string filePathValue = "MstngEa\\Trades\\State\\ProfitRetracement\\MstngEa_";
        filePathValue += this.sanitizeFileNamePart(this.accountServer);
        filePathValue += "_" + (string)this.accountLogin;
        filePathValue += "_" + this.sanitizeFileNamePart(this.marketContext.symbolName);
        filePathValue += "_" + (string)((long)this.marketContext.timeFrame);
        filePathValue += "_" + (string)this.magicNumber;
        filePathValue += "_profitRetracementV1.state";
        return filePathValue;
    }

    /**
     * Builds the temporary state file path.
     *
     * @return Relative temporary state file path.
     */
    string buildTemporaryFilePath() {
        return this.filePath + "." + (string)ChartID() + ".tmp";
    }

    /**
     * Sanitizes a file name component.
     *
     * @param fromValue Raw component.
     * @return Sanitized component.
     */
    string sanitizeFileNamePart(string fromValue) {
        string value = fromValue;

        if (value == "") {
            value = "unknown";
        }

        StringReplace(value, "\\", "_");
        StringReplace(value, "/", "_");
        StringReplace(value, ":", "_");
        StringReplace(value, "*", "_");
        StringReplace(value, "?", "_");
        StringReplace(value, "\"", "_");
        StringReplace(value, "<", "_");
        StringReplace(value, ">", "_");
        StringReplace(value, "|", "_");
        return value;
    }

    /**
     * Returns the common folder flag.
     *
     * @return FILE_COMMON or zero.
     */
    int getCommonFlag() {
        if (this.commonFolder) {
            return FILE_COMMON;
        }

        return 0;
    }

    /**
     * Sets a file API error message.
     *
     * @param fromPrefix Error prefix.
     */
    void setFileError(string fromPrefix) {
        this.lastErrorMessage = fromPrefix
            + ". code="
            + IntegerToString(GetLastError());
    }
};

#endif
