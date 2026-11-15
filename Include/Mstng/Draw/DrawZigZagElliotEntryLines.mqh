#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_ENTRY_LINES_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_ENTRY_LINES_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>

/**
 * ENTRY成立時の発生足と判定日時を固定縦線として保持する。
 */
class DrawZigZagElliotEntryLines {
public:
    /**
     * 発生足へ売買方向別の縦線を追加する。既存線の位置と判定日時は変更しない。
     *
     * @param fromMarketContext 判定対象の銘柄と時間足。
     * @param fromBarTime ENTRYが成立した足の開始サーバー時刻。
     * @param fromServerTime 判定時のサーバー時刻。
     * @param fromJstTime 判定時の日本時刻。
     * @param fromIsBuy BUYの場合true。
     * @param fromChartId 描画先チャート。0は現在のチャート。
     * @param fromPrefix DB表示の所有接頭辞。空は通常線。DB線は同位置の通常線を優先する。
     * @return 描画済み、または描画に成功した場合true。
     */
    static bool draw(MarketContext &fromMarketContext, const datetime fromBarTime,
            const datetime fromServerTime, const datetime fromJstTime, const bool fromIsBuy,
            const long fromChartId = 0, const string fromPrefix = "") {
        if (fromBarTime <= 0 || fromServerTime <= 0) {
            return false;
        }

        string side = "SELL";
        color lineColor = clrMagenta;
        if (fromIsBuy) {
            side = "BUY";
            lineColor = clrDodgerBlue;
        }

        string key = IntegerToString((int)fromMarketContext.timeFrame)
            + side + IntegerToString((long)fromBarTime);
        string prefix = getPrefix();
        if (fromPrefix != "") {
            if (ObjectFind(fromChartId, prefix + key) >= 0) {
                return true;
            }

            prefix = fromPrefix;
        }

        string objectName = prefix + key;
        if (ObjectFind(fromChartId, objectName) >= 0) {
            return true;
        }

        string jstText = "—";
        if (fromJstTime > 0) {
            jstText = TimeToString(fromJstTime, TIME_DATE | TIME_SECONDS);
        }

        string tooltip = fromMarketContext.symbolName + " " + fromMarketContext.timeFrameLabel
            + " " + side + " ENTRY\n"
            + "判定: " + TimeToString(fromServerTime, TIME_DATE | TIME_SECONDS) + " SRV\n"
            + "判定: " + jstText + " JST";

        if (!ObjectCreate(fromChartId, objectName, OBJ_VLINE, 0, fromBarTime, 0.0)) {
            return false;
        }

        if (!ObjectSetInteger(fromChartId, objectName, OBJPROP_COLOR, lineColor)
                || !ObjectSetInteger(fromChartId, objectName, OBJPROP_STYLE, STYLE_DOT)
                || !ObjectSetInteger(fromChartId, objectName, OBJPROP_WIDTH, 1)
                || !ObjectSetInteger(fromChartId, objectName, OBJPROP_BACK, true)
                || !ObjectSetInteger(fromChartId, objectName, OBJPROP_RAY, false)
                || !ObjectSetInteger(fromChartId, objectName, OBJPROP_SELECTABLE, false)
                || !ObjectSetInteger(fromChartId, objectName, OBJPROP_SELECTED, false)
                || !ObjectSetInteger(fromChartId, objectName, OBJPROP_HIDDEN, true)
                || !ObjectSetString(fromChartId, objectName, OBJPROP_TOOLTIP, tooltip)) {
            ObjectDelete(fromChartId, objectName);

            return false;
        }

        return true;
    }

    /**
     * この表示機能が所有するENTRY縦線を削除する。
     *
     * @param fromChartId 描画先チャート。0は現在のチャート。
     * @param fromPrefix 所有接頭辞。空は通常線のみを削除する。
     */
    static void clear(const long fromChartId = 0, const string fromPrefix = "") {
        string prefix = fromPrefix;
        if (prefix == "") {
            prefix = getPrefix();
        }

        ObjectsDeleteAll(fromChartId, prefix, 0, OBJ_VLINE);
    }

    /**
     * 指定足に後から通常線が追加された場合、その足のDB重複線だけを削除する。
     *
     * @param fromChartId 描画先チャート。
     * @param fromPrefix DB表示が所有する接頭辞。
     * @param fromTimeFrame 判定時間足。
     * @param fromBarTime 判定した足の開始時刻。
     */
    static void removeLiveDuplicates(const long fromChartId, const string fromPrefix,
            const ENUM_TIMEFRAMES fromTimeFrame, const datetime fromBarTime) {
        if (fromPrefix == "" || fromPrefix == getPrefix() || fromBarTime <= 0) {
            return;
        }

        string sides[] = {"BUY", "SELL"};
        for (int i = 0; i < ArraySize(sides); i++) {
            string key = IntegerToString((int)fromTimeFrame) + sides[i] + IntegerToString((long)fromBarTime);
            if (ObjectFind(fromChartId, getPrefix() + key) >= 0) {
                ObjectDelete(fromChartId, fromPrefix + key);
            }
        }
    }

private:
    /**
     * 通常の波動再描画で削除されない専用接頭辞を返す。
     *
     * @return ENTRY縦線専用の接頭辞。
     */
    static string getPrefix() {
        return Constant::PREFIX_FIXED + "EntryLineMTF3in3";
    }
};

#endif
