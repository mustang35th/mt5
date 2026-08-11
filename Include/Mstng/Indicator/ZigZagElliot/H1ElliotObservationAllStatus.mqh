//+------------------------------------------------------------------+
//|                         H1ElliotObservationAllStatus.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_H1_ELLIOT_OBSERVATION_ALL_STATUS_MQH
#define MSTNG_H1_ELLIOT_OBSERVATION_ALL_STATUS_MQH

enum H1ElliotObservationAllSymbolStatus {
    h1ElliotObservationAllSymbolStatusBase = 0,
    h1ElliotObservationAllSymbolStatusWait = 1,
    h1ElliotObservationAllSymbolStatusRun = 2,
    h1ElliotObservationAllSymbolStatusRetry = 3,
    h1ElliotObservationAllSymbolStatusDatabase = 4,
    h1ElliotObservationAllSymbolStatusOk = 5,
    h1ElliotObservationAllSymbolStatusError = 6,
    h1ElliotObservationAllSymbolStatusGap = 7
};

/**
 * 全28通貨H1観測処理の表示用状態を保持するクラス。
 *
 * 収集処理から描画処理へ渡す値だけを保持し、DBや分析オブジェクトへの
 * 参照は保持しない。
 */
class H1ElliotObservationAllStatus {
public:
    /** インジケータが実行中の場合true。 */
    bool isRunning;

    /** DB Writerとして有効な場合true。 */
    bool isWriterActive;

    /** DB接続が利用可能な場合true。 */
    bool isDatabaseConnected;

    /** 記録対象Run ID。 */
    long runId;

    /** LIVEまたはTESTERなどの実行元モード。 */
    string sourceMode;

    /** 現在処理対象のH1開始時刻。JST。 */
    datetime currentH1JapanTime;

    /** 最後にDB保存できた時刻。JST。 */
    datetime lastSavedJapanTime;

    /** 対象通貨数。 */
    int targetCount;

    /** 初期化準備が完了した通貨数。 */
    int readyCount;

    /** 現在H1で新規足を検出した通貨数。 */
    int detectedCount;

    /** 現在H1で分析に成功した通貨数。 */
    int analyzedCount;

    /** 現在H1でDB保存に成功した通貨数。 */
    int savedCount;

    /** DB保存待ちSnapshot数。 */
    int queueSize;

    /** DB保存待ちキュー容量。 */
    int queueCapacity;

    /** 起動後に検出した欠損数。 */
    int gapCount;

    /** 直近処理時間。ミリ秒。 */
    int elapsedMilliseconds;

    /** 集約状態へ補足表示するメッセージ。 */
    string message;

    /** 通貨名。 */
    string symbolNames[28];

    /** 通貨ごとの処理状態。 */
    H1ElliotObservationAllSymbolStatus symbolStatuses[28];

    /** 通貨ごとのDB保存待ちSnapshot数。 */
    int symbolPendingCounts[28];

    /** 通貨ごとの分析再試行回数。 */
    int symbolRetryCounts[28];

    /** 通貨ごとの現在H1開始時刻。サーバー時刻。 */
    datetime symbolCurrentH1Times[28];

    /** 通貨ごとの最後にSnapshotを生成したH1開始時刻。サーバー時刻。 */
    datetime symbolLastCapturedTimes[28];

    /** 通貨ごとの最後にDB保存したH1開始時刻。サーバー時刻。 */
    datetime symbolLastSavedTimes[28];

    /** 通貨ごとの補足メッセージ。 */
    string symbolMessages[28];

    /**
     * 初期状態を設定する。
     */
    H1ElliotObservationAllStatus() {
        this.reset();
    }

    /**
     * 全状態を初期化する。
     */
    void reset() {
        this.isRunning = false;
        this.isWriterActive = false;
        this.isDatabaseConnected = false;
        this.runId = 0;
        this.sourceMode = "-";
        this.currentH1JapanTime = 0;
        this.lastSavedJapanTime = 0;
        this.targetCount = 28;
        this.readyCount = 0;
        this.detectedCount = 0;
        this.analyzedCount = 0;
        this.savedCount = 0;
        this.queueSize = 0;
        this.queueCapacity = 0;
        this.gapCount = 0;
        this.elapsedMilliseconds = 0;
        this.message = "";

        for (int i = 0; i < 28; i++) {
            this.clearSymbol(i);
        }
    }

    /**
     * 現在H1の集約件数を初期化する。
     */
    void resetCycle() {
        this.detectedCount = 0;
        this.analyzedCount = 0;
        this.savedCount = 0;
        this.elapsedMilliseconds = 0;
        this.message = "";
    }

    /**
     * 通貨の表示状態を設定する。
     *
     * @param fromIndex 通貨インデックス。
     * @param fromSymbolName 通貨名。
     * @param fromStatus 処理状態。
     * @param fromPendingCount DB保存待ちSnapshot数。
     * @param fromMessage 補足メッセージ。
     * @return 設定できた場合true。
     */
    bool setSymbol(
        int fromIndex,
        string fromSymbolName,
        H1ElliotObservationAllSymbolStatus fromStatus,
        int fromPendingCount,
        string fromMessage
    ) {
        if (!this.isValidIndex(fromIndex)) {
            return false;
        }

        this.symbolNames[fromIndex] = fromSymbolName;
        this.symbolStatuses[fromIndex] = fromStatus;
        this.symbolPendingCounts[fromIndex] = fromPendingCount;
        this.symbolRetryCounts[fromIndex] = 0;
        this.symbolCurrentH1Times[fromIndex] = 0;
        this.symbolLastCapturedTimes[fromIndex] = 0;
        this.symbolLastSavedTimes[fromIndex] = 0;
        this.symbolMessages[fromIndex] = fromMessage;

        if (this.symbolPendingCounts[fromIndex] < 0) {
            this.symbolPendingCounts[fromIndex] = 0;
        }

        return true;
    }

    /**
     * Controllerが返す状態コードと詳細値を通貨の表示状態へ設定する。
     *
     * @param fromIndex 通貨インデックス。
     * @param fromSymbolName 通貨名。
     * @param fromStatusCode BASE、WAIT、RUN、RETRY、DB、OK、ERR、GAP。
     * @param fromCurrentH1Time 現在H1開始時刻。サーバー時刻。
     * @param fromLastCapturedTime 最終Snapshot生成H1時刻。サーバー時刻。
     * @param fromLastSavedTime 最終DB保存H1時刻。サーバー時刻。
     * @param fromPendingCount DB保存待ちSnapshot数。
     * @param fromRetryCount 分析再試行回数。
     * @param fromMessage 補足メッセージ。
     * @return 設定できた場合true。
     */
    bool setSymbol(
        int fromIndex,
        string fromSymbolName,
        string fromStatusCode,
        datetime fromCurrentH1Time,
        datetime fromLastCapturedTime,
        datetime fromLastSavedTime,
        int fromPendingCount,
        int fromRetryCount,
        string fromMessage
    ) {
        if (!this.isValidIndex(fromIndex)) {
            return false;
        }

        this.symbolNames[fromIndex] = fromSymbolName;
        this.symbolStatuses[fromIndex] = this.convertStatus(fromStatusCode);
        this.symbolPendingCounts[fromIndex] = fromPendingCount;
        this.symbolRetryCounts[fromIndex] = fromRetryCount;
        this.symbolCurrentH1Times[fromIndex] = fromCurrentH1Time;
        this.symbolLastCapturedTimes[fromIndex] = fromLastCapturedTime;
        this.symbolLastSavedTimes[fromIndex] = fromLastSavedTime;
        this.symbolMessages[fromIndex] = fromMessage;

        if (this.symbolPendingCounts[fromIndex] < 0) {
            this.symbolPendingCounts[fromIndex] = 0;
        }

        if (this.symbolRetryCounts[fromIndex] < 0) {
            this.symbolRetryCounts[fromIndex] = 0;
        }

        return true;
    }

    /**
     * 指定通貨の表示状態を初期化する。
     *
     * @param fromIndex 通貨インデックス。
     */
    void clearSymbol(int fromIndex) {
        if (!this.isValidIndex(fromIndex)) {
            return;
        }

        this.symbolNames[fromIndex] = "";
        this.symbolStatuses[fromIndex] = h1ElliotObservationAllSymbolStatusBase;
        this.symbolPendingCounts[fromIndex] = 0;
        this.symbolRetryCounts[fromIndex] = 0;
        this.symbolCurrentH1Times[fromIndex] = 0;
        this.symbolLastCapturedTimes[fromIndex] = 0;
        this.symbolLastSavedTimes[fromIndex] = 0;
        this.symbolMessages[fromIndex] = "";
    }

    /**
     * 設定済み通貨数を取得する。
     *
     * @return 設定済み通貨数。
     */
    int getSymbolCount() {
        int symbolCount = 0;

        for (int i = 0; i < 28; i++) {
            if (this.symbolNames[i] != "") {
                symbolCount++;
            }
        }

        return symbolCount;
    }

    /**
     * 指定状態の通貨数を取得する。
     *
     * @param fromStatus 集計する処理状態。
     * @return 指定状態の通貨数。
     */
    int getStatusCount(H1ElliotObservationAllSymbolStatus fromStatus) {
        int statusCount = 0;

        for (int i = 0; i < 28; i++) {
            if (this.symbolNames[i] != ""
                    && this.symbolStatuses[i] == fromStatus) {
                statusCount++;
            }
        }

        return statusCount;
    }

    /**
     * 通貨別DB保存待ちSnapshotの合計を取得する。
     *
     * @return DB保存待ちSnapshotの合計。
     */
    int getSymbolPendingCount() {
        int pendingCount = 0;

        for (int i = 0; i < 28; i++) {
            pendingCount += this.symbolPendingCounts[i];
        }

        return pendingCount;
    }

    /**
     * 通貨の状態表示文字列を取得する。
     *
     * @param fromIndex 通貨インデックス。
     * @return 状態表示文字列。範囲外の場合ERR。
     */
    string getSymbolStatusText(int fromIndex) {
        if (!this.isValidIndex(fromIndex)) {
            return "ERR";
        }

        return this.getStatusText(this.symbolStatuses[fromIndex]);
    }

    /**
     * 状態表示文字列を取得する。
     *
     * @param fromStatus 処理状態。
     * @return BASE、WAIT、RUN、RETRY、DB、OK、ERR、GAP。
     */
    string getStatusText(H1ElliotObservationAllSymbolStatus fromStatus) {
        if (fromStatus == h1ElliotObservationAllSymbolStatusBase) {
            return "BASE";
        }

        if (fromStatus == h1ElliotObservationAllSymbolStatusWait) {
            return "WAIT";
        }

        if (fromStatus == h1ElliotObservationAllSymbolStatusRun) {
            return "RUN";
        }

        if (fromStatus == h1ElliotObservationAllSymbolStatusRetry) {
            return "RETRY";
        }

        if (fromStatus == h1ElliotObservationAllSymbolStatusDatabase) {
            return "DB";
        }

        if (fromStatus == h1ElliotObservationAllSymbolStatusOk) {
            return "OK";
        }

        if (fromStatus == h1ElliotObservationAllSymbolStatusGap) {
            return "GAP";
        }

        return "ERR";
    }

private:
    /**
     * 状態コードを表示状態へ変換する。
     *
     * @param fromStatusCode 状態コード。
     * @return 対応する表示状態。不明な場合はERR。
     */
    H1ElliotObservationAllSymbolStatus convertStatus(string fromStatusCode) {
        string statusCode = fromStatusCode;
        StringTrimLeft(statusCode);
        StringTrimRight(statusCode);
        StringToUpper(statusCode);

        if (statusCode == "BASE") {
            return h1ElliotObservationAllSymbolStatusBase;
        }

        if (statusCode == "WAIT") {
            return h1ElliotObservationAllSymbolStatusWait;
        }

        if (statusCode == "RUN") {
            return h1ElliotObservationAllSymbolStatusRun;
        }

        if (statusCode == "RETRY") {
            return h1ElliotObservationAllSymbolStatusRetry;
        }

        if (statusCode == "DB") {
            return h1ElliotObservationAllSymbolStatusDatabase;
        }

        if (statusCode == "OK") {
            return h1ElliotObservationAllSymbolStatusOk;
        }

        if (statusCode == "GAP") {
            return h1ElliotObservationAllSymbolStatusGap;
        }

        return h1ElliotObservationAllSymbolStatusError;
    }

    /**
     * 通貨インデックスが有効か判定する。
     *
     * @param fromIndex 通貨インデックス。
     * @return 0以上28未満の場合true。
     */
    bool isValidIndex(int fromIndex) {
        return 0 <= fromIndex && fromIndex < 28;
    }
};

#endif // MSTNG_H1_ELLIOT_OBSERVATION_ALL_STATUS_MQH
