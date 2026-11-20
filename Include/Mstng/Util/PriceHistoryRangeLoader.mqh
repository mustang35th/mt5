#ifndef MSTNG_UTIL_PRICE_HISTORY_RANGE_LOADER_MQH
#define MSTNG_UTIL_PRICE_HISTORY_RANGE_LOADER_MQH

#include <Mstng\Util\TimeUtil.mqh>

/**
 * 指定期間のM1・M5価格系列を、各巡回で不足している端から準備する。
 * 開始日以前の履歴、終了側の同期、期間内の実在バー数で準備結果を確認する。
 */
class PriceHistoryRangeLoader {
public:
    /**
     * 必要な場合だけ1本のCopyRatesで端末に系列構築を要求し、現在の取得状況を返す。
     *
     * @param fromSymbol 気配値に選択済みの実銘柄名。
     * @param fromTimeFrame M1またはM5。
     * @param fromStartTime 取得開始のサーバー時刻。
     * @param fromEndTime スクリプト開始時に固定した取得終了のサーバー時刻。
     * @param fromDetail 取得本数、または不足の理由。
     * @return 同期した系列が開始から終了までをカバーし、期間内に足がある場合true。
     */
    static bool tryLoad(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame,
            const datetime fromStartTime, const datetime fromEndTime, string &fromDetail) {
        if (fromSymbol == "" || fromStartTime <= 0 || fromEndTime < fromStartTime
                || (fromTimeFrame != PERIOD_M1 && fromTimeFrame != PERIOD_M5)) {
            fromDetail = "履歴の対象または期間が無効";

            return false;
        }

        datetime firstDate = (datetime)SeriesInfoInteger(fromSymbol, fromTimeFrame, SERIES_FIRSTDATE);
        bool needsStart = firstDate <= 0 || firstDate > fromStartTime;
        long maxBars = TerminalInfoInteger(TERMINAL_MAXBARS);
        if (needsStart) {
            datetime serverFirst = (datetime)SeriesInfoInteger(fromSymbol, PERIOD_M1, SERIES_SERVER_FIRSTDATE);
            if (serverFirst > fromStartTime) {
                fromDetail = "指定開始日はサーバーの履歴開始前。提供開始 SRV "
                    + TimeUtil::formatYyyymmddhhmiss(serverFirst);

                return false;
            }

            if (firstDate > 0 && maxBars > 0 && Bars(fromSymbol, fromTimeFrame) >= maxBars) {
                fromDetail = StringFormat("チャートの最大バー数 %I64d 本に到達。端末の系列先頭 SRV %s",
                    maxBars, TimeUtil::formatYyyymmddhhmiss(firstDate));

                return false;
            }
        }

        int periodSeconds = PeriodSeconds(fromTimeFrame);
        datetime lastDate = (datetime)SeriesInfoInteger(fromSymbol, fromTimeFrame, SERIES_LASTBAR_DATE);
        if (needsStart || !isEndReady(fromSymbol, fromTimeFrame, fromEndTime, periodSeconds, lastDate)) {
            MqlRates rate[1];
            int copied = 0;
            ResetLastError();
            if (needsStart) {
                // 指定時刻が休場中なら、その時刻以前の直近バーを起点にする。
                copied = CopyRates(fromSymbol, fromTimeFrame, fromStartTime, 1, rate);
            } else {
                copied = CopyRates(fromSymbol, fromTimeFrame, 0, 1, rate);
            }

            if (copied != 1) {
                fromDetail = StringFormat("価格履歴を要求中。CopyRates=%d error=%d", copied, GetLastError());

                return false;
            }

            firstDate = (datetime)SeriesInfoInteger(fromSymbol, fromTimeFrame, SERIES_FIRSTDATE);
            lastDate = (datetime)SeriesInfoInteger(fromSymbol, fromTimeFrame, SERIES_LASTBAR_DATE);
        }

        if (firstDate <= 0 || firstDate > fromStartTime) {
            fromDetail = "指定開始日までの履歴を取得中";

            return false;
        }

        if (!isEndReady(fromSymbol, fromTimeFrame, fromEndTime, periodSeconds, lastDate)) {
            fromDetail = "終了側の価格履歴または最終気配の同期待ち";

            return false;
        }

        int count = Bars(fromSymbol, fromTimeFrame, fromStartTime, fromEndTime);
        if (count <= 0) {
            fromDetail = "指定期間内のバーが0本";

            return false;
        }

        if (maxBars > 0 && count > maxBars) {
            fromDetail = StringFormat("対象 %d 本がチャートの最大バー数 %I64d 本を超過", count, maxBars);

            return false;
        }

        fromDetail = StringFormat("期間内 %d 本", count);

        return true;
    }

private:
    /**
     * 休場中は最終気配の足を終了側の到達点とし、古い履歴だけでの完了を防ぐ。
     */
    static bool isEndReady(const string fromSymbol, const ENUM_TIMEFRAMES fromTimeFrame,
            const datetime fromEndTime, const int fromPeriodSeconds, const datetime fromLastDate) {
        if (fromLastDate <= 0 || !SymbolIsSynchronized(fromSymbol)
                || !SeriesInfoInteger(fromSymbol, fromTimeFrame, SERIES_SYNCHRONIZED)) {
            return false;
        }

        MqlTick tick;
        if (!SymbolInfoTick(fromSymbol, tick) || tick.time <= 0) {
            return false;
        }

        datetime expectedTime = fromEndTime;
        if (tick.time < fromEndTime) {
            expectedTime = tick.time;
        }

        datetime expectedBar = (datetime)((long)expectedTime - (long)expectedTime % fromPeriodSeconds);

        return fromLastDate >= expectedBar;
    }
};

#endif // MSTNG_UTIL_PRICE_HISTORY_RANGE_LOADER_MQH
