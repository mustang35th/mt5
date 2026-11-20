#property version "1.00"
#property script_show_inputs
#property description "全28通貨ペアの価格履歴を順に準備し、不足した時間足をエキスパートログに表示します。"

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Util\PriceHistoryRangeLoader.mqh>
#include <Mstng\Util\PriceHistorySymbolResolver.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 初回監視に必要な本数、または検証に使う期間を指定する。
 */
enum PriceHistoryLoadMode {
    PRICE_HISTORY_MONITOR = 0, // 監視準備（8時間足）
    PRICE_HISTORY_RANGE = 1    // 過去検証（M1・M5）
};

input(name="取得モード") PriceHistoryLoadMode loadMode = PRICE_HISTORY_MONITOR;
input(name="過去検証の開始日時（サーバー時刻・0＝直近365日）") datetime historyStart = 0;
input(name="最大巡回数（初回を含む・1～30）") int maxPasses = 5;

/**
 * 通貨ペアごとの解決済み銘柄名と、時間足ごとの進捗を保持する。
 */
struct PriceHistoryPair {
    /** 共通の通貨ペア名。 */
    string canonicalName;

    /** 口座で選択した銘柄名。 */
    string symbolName;

    /** 各時間足の取得完了状態。 */
    bool ready[8];

    /** 各時間足の最終確認結果。 */
    string detail[8];
};

/**
 * 同期済みで必要本数が揃った足をスキップし、不足足だけ取得を要求する。
 */
bool prepareMonitorBars(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame,
        string &fromDetail) {
    int required = 206;
    if (fromTimeFrame == PERIOD_MN1) {
        required = 61;
    }

    int available = Bars(fromSymbol, fromTimeFrame);
    bool synced = (bool)SeriesInfoInteger(fromSymbol, fromTimeFrame, SERIES_SYNCHRONIZED);
    int errorCode = 0;
    if (!synced || available < required) {
        MqlRates rates[];
        ResetLastError();
        int copied = CopyRates(fromSymbol, fromTimeFrame, 0, required, rates);
        if (copied < required) {
            errorCode = GetLastError();
        }

        available = Bars(fromSymbol, fromTimeFrame);
        synced = (bool)SeriesInfoInteger(fromSymbol, fromTimeFrame, SERIES_SYNCHRONIZED);
    }

    fromDetail = StringFormat("%d/%d本", (int)MathMin(available, required), required);
    if (!synced) {
        fromDetail += " 未同期";
    }

    if (errorCode != 0 && (!synced || available < required)) {
        fromDetail += StringFormat(" (MT5 %d)", errorCode);
    }

    return synced && available >= required;
}

/**
 * 実行中だけ使う進捗ラベルを作成する。表示できなくてもログと取得処理は続ける。
 */
string createProgressLabel() {
    string name = "MstngHistoryLoad-" + (string)GetMicrosecondCount();
    if (ObjectFind(0, name) >= 0 || !ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
        return "";
    }

    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 22);
    ObjectSetInteger(0, name, OBJPROP_COLOR, ChartGetInteger(0, CHART_COLOR_FOREGROUND));
    ObjectSetString(0, name, OBJPROP_FONT, "Meiryo");
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");

    return name;
}

/**
 * 任意の通常チャートで、全28ペアを順に処理し、未完了だけを再試行する。
 */
void OnStart() {
    Logger logger(LOG_INFO);
    if (Util::isStrategyTester() || !TerminalInfoInteger(TERMINAL_CONNECTED)) {
        logger.error(__FUNCTION__, "口座へ接続した通常チャートで実行してください。");

        return;
    }

    if ((loadMode != PRICE_HISTORY_MONITOR && loadMode != PRICE_HISTORY_RANGE)
            || maxPasses < 1 || maxPasses > 30) {
        logger.error(__FUNCTION__, "取得モードと最大巡回数（1～30）を確認してください。");

        return;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1
    };
    int frameCount = ArraySize(timeFrames);
    datetime endTime = TimeCurrent();
    datetime startTime = historyStart;
    string modeText = "監視準備";
    if (loadMode == PRICE_HISTORY_RANGE) {
        frameCount = 2;
        if (startTime == 0) {
            startTime = endTime - 365 * 86400;
        }

        if (startTime <= 0 || startTime >= endTime) {
            logger.error(__FUNCTION__, "過去検証の開始日時は最終受信時刻より前のサーバー時刻を指定してください。");

            return;
        }

        modeText = "過去検証 " + TimeUtil::formatYyyymmddhhmiss(startTime) + " ～ "
            + TimeUtil::formatYyyymmddhhmiss(endTime) + " SRV";
    }

    SymbolNameInfoAll symbols;
    symbols.setAll();
    int pairCount = symbols.size();
    PriceHistoryPair pairs[];
    if (pairCount != 28 || ArrayResize(pairs, pairCount) != pairCount) {
        logger.error(__FUNCTION__, "全28ペアの一覧を準備できませんでした。");

        return;
    }

    for (int i = 0; i < pairCount; i++) {
        SymbolNameInfo *info = symbols.getSymbolNameInfo(i);
        if (info == NULL) {
            logger.error(__FUNCTION__, "通貨ペアの定義を取得できませんでした。");

            return;
        }

        pairs[i].canonicalName = info.symbolName;
        pairs[i].symbolName = "";
        for (int j = 0; j < frameCount; j++) {
            pairs[i].ready[j] = false;
            pairs[i].detail[j] = "未確認";
        }
    }

    int total = pairCount * frameCount;
    int completed = 0;
    string lastResult = "";
    string progressLabel = createProgressLabel();
    logger.info(__FUNCTION__, StringFormat("%s　%dペア / %d系列　取得開始", modeText, pairCount, total));

    for (int pass = 1; pass <= maxPasses && !IsStopped(); pass++) {
        for (int i = 0; i < pairCount && !IsStopped() && TerminalInfoInteger(TERMINAL_CONNECTED); i++) {
            if (pairs[i].symbolName == "") {
                pairs[i].symbolName = PriceHistorySymbolResolver::resolve(pairs[i].canonicalName);
                if (pairs[i].symbolName == "") {
                    continue;
                }
            }

            for (int j = 0; j < frameCount && !IsStopped() && TerminalInfoInteger(TERMINAL_CONNECTED); j++) {
                if (pairs[i].ready[j]) {
                    continue;
                }

                string frameName = TimeUtil::convertTimeFrameToString(timeFrames[j]);
                string progress = StringFormat("価格履歴 %d周目　%d/%dペア　%s %s　完了 %d/%d",
                    pass, i + 1, pairCount, pairs[i].symbolName, frameName, completed, total);
                if (progressLabel != "") {
                    ObjectSetString(0, progressLabel, OBJPROP_TEXT, progress + lastResult);
                    ChartRedraw(0);
                }

                if (loadMode == PRICE_HISTORY_MONITOR) {
                    pairs[i].ready[j] = prepareMonitorBars(pairs[i].symbolName, timeFrames[j], pairs[i].detail[j]);
                } else {
                    pairs[i].ready[j] = PriceHistoryRangeLoader::tryLoad(pairs[i].symbolName,
                        timeFrames[j], startTime, endTime, pairs[i].detail[j]);
                }

                if (pairs[i].ready[j]) {
                    completed++;
                }

                lastResult = "　直前 " + pairs[i].symbolName + " " + frameName + " " + pairs[i].detail[j];
            }
        }

        logger.info(__FUNCTION__, StringFormat("%d周目　完了 %d/%d系列", pass, completed, total));
        if (completed == total || !TerminalInfoInteger(TERMINAL_CONNECTED) || IsStopped()) {
            break;
        }

        if (pass < maxPasses) {
            Sleep(2000);
        }
    }

    if (progressLabel != "") {
        ObjectDelete(0, progressLabel);
        ChartRedraw(0);
    }

    int completePairs = 0;
    for (int i = 0; i < pairCount; i++) {
        string missing = "";
        for (int j = 0; j < frameCount; j++) {
            if (!pairs[i].ready[j]) {
                missing += "  " + TimeUtil::convertTimeFrameToString(timeFrames[j]) + " " + pairs[i].detail[j];
            }
        }

        if (missing == "") {
            completePairs++;
        } else if (pairs[i].symbolName == "") {
            logger.info(__FUNCTION__, pairs[i].canonicalName + " 未完了：銘柄を選択できていません。");
        } else {
            logger.info(__FUNCTION__, pairs[i].symbolName + " 未完了：" + missing);
        }
    }

    string status = "終了";
    if (IsStopped()) {
        status = "停止";
    } else if (!TerminalInfoInteger(TERMINAL_CONNECTED)) {
        status = "接続切断";
    }

    logger.info(__FUNCTION__, StringFormat("%s %s　完了 %d/%dペア　%d/%d系列　未完了 %d系列",
        modeText, status, completePairs, pairCount, completed, total, total - completed));
}
