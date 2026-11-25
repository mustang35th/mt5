#ifndef MSTNG_INDICATOR_M5_OBSERVATION_DISPLAY_CONTROLLER_MQH
#define MSTNG_INDICATOR_M5_OBSERVATION_DISPLAY_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Query\ZigZagElliotM5ObservationHistoryReader.mqh>
#include <Mstng\Draw\ChartMouseMoveSubscription.mqh>
#include <Mstng\Draw\DrawZigZagElliotM5Observations.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 表示範囲内のM5観測を読み、保存値だけを目印・詳細パネルへ渡す。
 * 表示Runを保持し、マウス操作ではDBを参照せずキャッシュを使用する。
 */
class M5ObservationDisplayController {
public:
    /**
     * 未接続・未表示の状態を設定する。
     */
    M5ObservationDisplayController() {
        this.drawer = NULL;
        this.connected = false;
        this.resolvedRunId = 0;
        this.loadedStart = 0;
        this.loadedEnd = 0;
        this.lastKnownTime = 0;
        this.lastChartBarTime = 0;
        this.lastAttemptTick = 0;
        this.lastCheckTick = 0;
        this.status = "M5観測：読込待ち";
    }

    /**
     * 表示用接続と自分のオブジェクトを解放する。
     */
    ~M5ObservationDisplayController() {
        this.mouseMoveSubscription.release();
        this.reader.close();
        if (this.drawer != NULL) {
            delete this.drawer;
            this.drawer = NULL;
        }
    }

    /**
     * 参照設定を保持する。DBが未作成でも通常の分析を停止させない。
     */
    bool initialize(MarketContext &fromMarketContext, ZigZagElliotConfig &fromConfig) {
        if ((fromMarketContext.timeFrame != PERIOD_M1 && fromMarketContext.timeFrame != PERIOD_M5)
                || fromConfig.m5ObservationDisplayFileName == "" || fromConfig.m5ObservationDisplayRunId < 0) {
            return false;
        }

        this.marketContext = fromMarketContext;
        this.config = fromConfig;
        this.sourceMode = "LIVE";
        if (Util::isStrategyTester() || this.config.m5ObservationDisplayTesterData) {
            this.sourceMode = "TESTER";
        }

        this.sourceServer = AccountInfoString(ACCOUNT_SERVER);
        this.resolvedRunId = this.config.m5ObservationDisplayRunId;
        string prefix = "ZzeM5Obs-" + IntegerToString((long)GetMicrosecondCount()) + "-";
        this.drawer = new DrawZigZagElliotM5Observations(0, prefix);
        if (this.drawer != NULL) {
            this.mouseMoveSubscription.acquire(ChartID());
        }

        return this.drawer != NULL;
    }

    /**
     * 表示変更時と定期更新時に読込範囲を確認する。最大2000本、再取得は15秒ごと。
     * テスターでは表示足が進んだ時も取得し、その時点より後の記録は除外する。
     */
    void update(const bool fromViewChanged = false) {
        if (this.drawer == NULL) {
            return;
        }

        ulong nowTick = GetTickCount64();
        datetime chartBarTime = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, 0);
        datetime knownTime = TimeCurrent();
        bool clockRewound = this.lastKnownTime > knownTime;
        bool barChanged = this.lastChartBarTime != chartBarTime;
        if (!fromViewChanged && !barChanged && !clockRewound && this.lastCheckTick > 0
                && nowTick - this.lastCheckTick < 1000) {
            return;
        }

        this.lastCheckTick = nowTick;
        this.mouseMoveSubscription.acquire(ChartID());
        datetime startTime = 0;
        datetime endTime = 0;
        bool limited = false;
        if (knownTime <= 0 || !this.getVisibleRange(startTime, endTime, limited)) {
            this.clearDisplay("M5観測：チャート履歴の準備待ち");
            this.loadedStart = 0;
            this.loadedEnd = 0;
            return;
        }

        bool rangeChanged = startTime != this.loadedStart || endTime != this.loadedEnd;
        bool serverChanged = this.sourceServer != AccountInfoString(ACCOUNT_SERVER);
        if (serverChanged || clockRewound) {
            this.reader.close();
            this.connected = false;
            this.resolvedRunId = this.config.m5ObservationDisplayRunId;
            this.sourceServer = AccountInfoString(ACCOUNT_SERVER);
        }

        bool refresh = rangeChanged || serverChanged || clockRewound || this.lastAttemptTick == 0
            || nowTick - this.lastAttemptTick >= 15000 || (Util::isStrategyTester() && barChanged);
        if (!refresh) {
            if (fromViewChanged) {
                this.redraw();
            }

            return;
        }

        // 連続スクロール中のクエリを間引き、別範囲の保存値を残さない。
        if (!barChanged && !serverChanged && !clockRewound && this.lastAttemptTick > 0
                && nowTick - this.lastAttemptTick < 250) {
            if (rangeChanged || serverChanged) {
                this.clearDisplay("M5観測：表示範囲を読込中");
            }

            return;
        }

        this.lastAttemptTick = nowTick;
        this.lastChartBarTime = chartBarTime;
        this.lastKnownTime = knownTime;
        this.loadedStart = startTime;
        this.loadedEnd = endTime;
        string error = "";
        if (!this.connected) {
            this.connected = this.reader.open(this.config.m5ObservationDisplayFileName,
                this.config.m5ObservationDisplayUseCommonFolder, error);
        }

        M5ObservationHistoryRecord saved[];
        long selectedRunId = this.resolvedRunId;
        if (!this.connected || !this.reader.selectRecords(this.marketContext.symbolName,
                this.sourceMode, this.sourceServer, this.resolvedRunId, startTime, endTime,
                knownTime, selectedRunId, saved, error)) {
            this.reader.close();
            this.connected = false;
            this.clearDisplay("M5観測：読取失敗 " + error);
            return;
        }

        this.resolvedRunId = selectedRunId;
        datetime barTimes[];
        int count = CopyTime(this.marketContext.symbolName, PERIOD_M5, startTime, endTime - 1, barTimes);
        if (count <= 0 || count > 2000 || ArrayResize(this.records, count) != count) {
            this.clearDisplay("M5観測：M5チャート履歴の準備待ち");
            // コピー準備後は次のイベントで再読込できるようにする。
            this.loadedStart = 0;
            this.loadedEnd = 0;
            return;
        }

        int savedIndex = 0;
        int matched = 0;
        for (int i = 0; i < count; i++) {
            this.records[i].clear();
            this.records[i].barTime = barTimes[i];
            this.records[i].runId = this.resolvedRunId;
            while (savedIndex < ArraySize(saved) && saved[savedIndex].barTime < barTimes[i]) {
                savedIndex++;
            }

            if (savedIndex < ArraySize(saved) && saved[savedIndex].barTime == barTimes[i]) {
                this.records[i] = saved[savedIndex];
                matched++;
            }
        }

        this.status = "M5保存 " + this.sourceMode + " Run " + IntegerToString(this.resolvedRunId)
            + " / " + IntegerToString(matched) + "件 ●詳細・?記録なし";
        if (this.resolvedRunId <= 0) {
            this.status = "M5観測：銘柄・サーバー・モードが一致する記録なし";
        }
        if (limited) {
            this.status += "（表示範囲の新しいM5時刻2000枠まで）";
        }

        this.redraw();
    }

    /**
     * 取得済みの保存値だけを再描画する。
     */
    void redraw() {
        if (this.drawer != NULL) {
            this.drawer.draw(this.records, this.status, this.marketContext.digits);
            ChartRedraw(0);
        }
    }

    /**
     * 描画済みの目印に重なった時だけ、保存値の色付き説明を更新する。
     * DBの追加取得やチャート時系列の参照は行わない。
     */
    void onMouseMove(const int fromX, const int fromY) {
        if (this.drawer != NULL && this.drawer.onMouseMove(fromX, fromY, this.records)) {
            ChartRedraw(0);
        }
    }

    /**
     * 自分の目印・詳細閉じるボタンだけを処理する。DBの追加取得は行わない。
     */
    bool onObjectClick(const string fromObjectName) {
        if (this.drawer == NULL) {
            return false;
        }

        return this.drawer.onObjectClick(fromObjectName, this.records, this.status, this.marketContext.digits);
    }

private:
    /** 表示対象の銘柄とチャート時間足。 */
    MarketContext marketContext;

    /** 起動時に固定する表示設定。 */
    ZigZagElliotConfig config;

    /** 読み取り専用の観測DB接続。 */
    ZigZagElliotM5ObservationHistoryReader reader;

    /** このインスタンスが所有する目印・パネル。 */
    DrawZigZagElliotM5Observations *drawer;

    /** 順位帯などと共同管理する、ホバー用のマウス移動通知。 */
    ChartMouseMoveSubscription mouseMoveSubscription;

    /** 表示範囲のM5足。未収録足もid=0として保持する。 */
    M5ObservationHistoryRecord records[];

    /** DB接続が有効な場合true。 */
    bool connected;

    /** 読取対象のLIVEまたはTESTER。 */
    string sourceMode;

    /** 読取対象の取引サーバー。 */
    string sourceServer;

    /** 最初に解決した一つのRun ID。 */
    long resolvedRunId;

    /** 最後の読込開始時刻。 */
    datetime loadedStart;

    /** 最後の読込終了時刻。含まない。 */
    datetime loadedEnd;

    /** 最後の取得時点で知り得た市場時刻。 */
    datetime lastKnownTime;

    /** 最後に確認した表示時間足の現在バー。 */
    datetime lastChartBarTime;

    /** DB読込を最後に試みた単調時計。 */
    ulong lastAttemptTick;

    /** 可視範囲を最後に確認した単調時計。 */
    ulong lastCheckTick;

    /** DB・Run・取得状態の表示文。 */
    string status;

    /**
     * 可視チャート足の時刻をM5枠へ対応付け、最大2000枠に制限する。
     */
    bool getVisibleRange(datetime &fromStart, datetime &fromEnd, bool &fromLimited) {
        int total = Bars(this.marketContext.symbolName, this.marketContext.timeFrame);
        int first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
        int visible = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
        if (total <= 0 || first < 0 || visible <= 0) {
            return false;
        }

        first = MathMin(first, total - 1);
        int last = MathMax(0, first - visible + 1);
        datetime oldest = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, first);
        datetime newest = iTime(this.marketContext.symbolName, this.marketContext.timeFrame, last);
        if (oldest <= 0 || newest < oldest) {
            return false;
        }

        fromStart = (datetime)(((long)oldest / 300) * 300);
        fromEnd = (datetime)(((long)newest / 300) * 300 + 300);
        fromLimited = fromEnd - fromStart > 2000 * 300;
        if (fromLimited) {
            fromStart = fromEnd - 2000 * 300;
        }

        return fromEnd > fromStart;
    }

    /**
     * 失敗・準備待ちを記録なしと混同せず、古い保存値と選択パネルを消す。
     */
    void clearDisplay(const string fromStatus) {
        bool changed = this.status != fromStatus || ArraySize(this.records) > 0;
        ArrayFree(this.records);
        this.status = fromStatus;
        if (changed) {
            this.redraw();
        }
    }
};

#endif // MSTNG_INDICATOR_M5_OBSERVATION_DISPLAY_CONTROLLER_MQH
