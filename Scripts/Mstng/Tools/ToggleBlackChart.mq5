//+------------------------------------------------------------------+
//|                                             ToggleBlackChart.mq5 |
//+------------------------------------------------------------------+
// 実行したチャートを黒画面に切り替え、再実行で元の表示状態と背景色に戻す。
#property version "1.00"
#property description "黒画面と元のチャート表示を切り替えます。監視パネルとボタンは引き続き使用できます。"

#include <Mstng\Log\Logger.mqh>

/** このチャートに元の設定を保存する非表示ラベル名。 */
const string restoreLabel = "Mstng.ToggleBlackChart.Restore.v1";

/**
 * 保存用ラベルの文字列から元の表示状態を、色から元の背景色を読み取る。
 */
bool readSavedDisplay(long &fromShow, long &fromBackground) {
    if (ObjectGetInteger(0, restoreLabel, OBJPROP_TYPE) != OBJ_LABEL) {
        return false;
    }

    string tag = ObjectGetString(0, restoreLabel, OBJPROP_TEXT);
    if (tag == "ToggleBlackChart:visible") {
        fromShow = 1;
    } else if (tag == "ToggleBlackChart:hidden") {
        fromShow = 0;
    } else {
        return false;
    }

    return ObjectGetInteger(0, restoreLabel, OBJPROP_COLOR, 0, fromBackground);
}

/**
 * このスクリプトの復元情報を削除し、チャートへの反映を確認する。
 */
bool removeSavedDisplay() {
    return ObjectDelete(0, restoreLabel) && ObjectFind(0, restoreLabel) < 0;
}

/**
 * 全時間足で非表示のラベルを作成し、両方の元値が保存されたことを確認する。
 */
bool saveDisplay(const long fromShow, const long fromBackground) {
    if (!ObjectCreate(0, restoreLabel, OBJ_LABEL, 0, 0, 0)) {
        return false;
    }

    string tag = "ToggleBlackChart:hidden";
    if (fromShow != 0) {
        tag = "ToggleBlackChart:visible";
    }

    long savedShow = 0;
    long savedBackground = 0;
    if (ObjectSetInteger(0, restoreLabel, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS)
            && ObjectSetInteger(0, restoreLabel, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(0, restoreLabel, OBJPROP_COLOR, fromBackground)
            && ObjectSetString(0, restoreLabel, OBJPROP_TEXT, tag)
            && readSavedDisplay(savedShow, savedBackground)
            && savedShow == fromShow && savedBackground == fromBackground) {
        return true;
    }

    removeSavedDisplay();

    return false;
}

/**
 * 現在のチャートへ背景色と価格チャートの表示状態を適用し、結果を読み戻す。
 */
bool applyDisplay(const long fromShow, const long fromBackground) {
    if (!ChartSetInteger(0, CHART_COLOR_BACKGROUND, fromBackground)
            || !ChartSetInteger(0, CHART_SHOW, fromShow)) {
        return false;
    }

    ChartRedraw(0);
    long actualShow = 0;
    long actualBackground = 0;

    return ChartGetInteger(0, CHART_SHOW, 0, actualShow) && actualShow == fromShow
        && ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0, actualBackground) && actualBackground == fromBackground;
}

/**
 * 保存情報があれば復元し、初回は元の設定を保存して黒画面に切り替える。
 */
void OnStart() {
    Logger logger(LOG_INFO);
    long savedShow = 0;
    long savedBackground = 0;
    if (ObjectFind(0, restoreLabel) >= 0) {
        if (!readSavedDisplay(savedShow, savedBackground)) {
            logger.error(__FUNCTION__, "復元情報を読み取れません。保存用ラベルと同名のオブジェクトを確認してください。");
            return;
        }

        if (!applyDisplay(savedShow, savedBackground) || !removeSavedDisplay()) {
            logger.error(__FUNCTION__, "復元を完了できません。もう一度実行してください。");
            return;
        }

        logger.info(__FUNCTION__, "元のチャート表示と背景色に戻しました。");
        return;
    }

    if (!ChartGetInteger(0, CHART_SHOW, 0, savedShow)
            || !ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0, savedBackground)
            || !saveDisplay(savedShow, savedBackground)) {
        logger.error(__FUNCTION__, "現在の表示設定を保存できません。");
        return;
    }

    if (!applyDisplay(0, clrBlack)) {
        if (applyDisplay(savedShow, savedBackground) && removeSavedDisplay()) {
            logger.error(__FUNCTION__, "黒画面への切替に失敗したため、元の設定に戻しました。");
        } else {
            logger.error(__FUNCTION__, "黒画面への切替が中断されました。もう一度実行して復元してください。");
        }

        return;
    }

    logger.info(__FUNCTION__, "黒画面に切り替えました。もう一度実行すると元に戻ります。");
}
