//+------------------------------------------------------------------+
//|                                           DrawProcessingTime.mqh |
//+------------------------------------------------------------------+
#ifndef MSTNG_DRAW_PROCESSING_TIME_MQH
#define MSTNG_DRAW_PROCESSING_TIME_MQH

#include <Mstng\Common\ProcessingTimeStats.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\DrawZigZagElliotInfoLayout.mqh>

/**
 * ZigZagElliotの時計の下へ更新処理の集計を表示し、各処理の詳細を説明文へまとめる。
 * オブジェクトを再利用し、文字・説明・色の変更だけを反映する。
 */
class DrawProcessingTime {
public:
    /**
     * 描画状態を初期化する。
     */
    DrawProcessingTime() {
        this.initialized = false;
        this.updateBatchDepth = 0;
        this.displayUpdatePending = false;
        this.positionX = 0;
        this.fontFace = "MS Gothic";
        this.resetLabelCache();
        this.resetMetricCache();
    }

    /**
     * 所有する表示オブジェクトを解放する。
     */
    ~DrawProcessingTime() {
        this.clear();
    }

    /**
     * 時計と同じX座標・フォントで集計欄を作成する。
     *
     * @param fromX チャート右端から時計表示の左端までの距離
     * @param fromFont 時計表示のフォント
     * @return 全ラベルの作成要求に成功した場合true
     */
    bool initialize(int fromX, string fromFont) {
        this.positionX = fromX;
        this.fontFace = fromFont;
        this.initialized = true;
        this.updateBatchDepth = 0;
        this.displayUpdatePending = true;
        this.resetLabelCache();
        this.resetMetricCache();

        // 以前の表示形式で作成された補助処理の行を削除する。
        for (int i = 2; i < 5; i++) {
            ObjectDelete(0, this.getObjectName(i));
        }

        return this.flushDisplay();
    }

    /**
     * 指定した処理の集計を保持し、まとめ更新中は描画を終了時まで保留する。
     * 手動で削除されたラベルは、次の更新時に再作成する。
     *
     * @param fromIndex 更新処理0・EMA200 1・GMMA 2・日本時間軸3
     * @param fromStats 表示する処理時間と実行状態
     * @return 集計の保持と、必要な描画要求に成功した場合true
     */
    bool updateRow(int fromIndex, ProcessingTimeStats &fromStats) {
        if (!this.initialized || fromIndex < 0 || fromIndex >= 4) {
            return false;
        }

        string text = StringFormat("%s %7s %7s %7s", this.getRowLabel(fromIndex), "--", "--", "--");
        color textColor = clrSilver;

        if (fromStats.getCount() > 0) {
            text = StringFormat(
                "%s %7.1f %7.1f %7.1f",
                this.getRowLabel(fromIndex),
                fromStats.getLatestMilliseconds(),
                fromStats.getAverageMilliseconds(),
                fromStats.getMaximumMilliseconds()
            );
            textColor = clrWhite;
        }

        if (fromStats.getLastAttemptTime() > 0 && !fromStats.isLastSucceeded()) {
            text += " " + fromStats.getState();
            textColor = clrOrange;
        }

        this.metricTexts[fromIndex] = text;
        this.metricTooltips[fromIndex] = this.getTooltip(fromIndex, fromStats);
        this.displayUpdatePending = true;
        if (fromIndex == 0) {
            this.updateTextColor = textColor;
        }

        return this.flushDisplay();
    }

    /**
     * 処理時間ラベルの描画を、対応する終了呼び出しまで保留する。
     */
    void beginUpdateBatch() {
        if (this.initialized) {
            this.updateBatchDepth++;
        }
    }

    /**
     * 最外側のまとめ更新を終え、保留中の表示を一度だけ反映する。
     * 前回の描画が失敗している場合は、新しい計測がなくても再試行する。
     *
     * @return 保留中、更新不要、または描画要求に成功した場合true
     */
    bool endUpdateBatch() {
        if (this.updateBatchDepth > 0) {
            this.updateBatchDepth--;
        }

        return this.flushDisplay();
    }

    /**
     * 所有する集計ラベルだけを削除する。
     */
    void clear() {
        for (int i = 0; i < 5; i++) {
            ObjectDelete(0, this.getObjectName(i));
        }

        this.initialized = false;
        this.updateBatchDepth = 0;
        this.displayUpdatePending = false;
        this.resetLabelCache();
        this.resetMetricCache();
    }

private:
    /** 時計の位置とフォントが設定済みの場合true。 */
    bool initialized;

    /** 描画を保留するまとめ更新の階層。0の場合は即時反映する。 */
    int updateBatchDepth;

    /** 未反映の集計、または再試行が必要な描画がある場合true。 */
    bool displayUpdatePending;

    /** チャート右端から時計と共通の左端までの距離。 */
    int positionX;

    /** 等幅表示に使用するフォント。 */
    string fontFace;

    /** 各ラベルの全設定要求が成功済みの場合true。0はヘッダー、1は更新処理。 */
    bool labelReady[2];

    /** 最後に反映した表示文字。 */
    string labelTexts[2];

    /** 最後に反映した説明文字。 */
    string labelTooltips[2];

    /** 最後に反映した文字色。 */
    color labelColors[2];

    /** 各処理の最新の表示文字。 */
    string metricTexts[4];

    /** 各処理の数値と失敗状態を1行にまとめた説明文字。 */
    string metricTooltips[4];

    /** 画面に残す更新処理行の文字色。 */
    color updateTextColor;

    /**
     * ラベルの設定履歴を無効にする。
     */
    void resetLabelCache() {
        for (int i = 0; i < 2; i++) {
            this.labelReady[i] = false;
            this.labelTexts[i] = "";
            this.labelTooltips[i] = "";
            this.labelColors[i] = clrNONE;
        }
    }

    /**
     * 各処理の集計表示を未計測へ戻す。
     */
    void resetMetricCache() {
        ProcessingTimeStats emptyStats;
        for (int i = 0; i < 4; i++) {
            this.metricTexts[i] = StringFormat("%s %7s %7s %7s", this.getRowLabel(i), "--", "--", "--");
            this.metricTooltips[i] = this.getTooltip(i, emptyStats);
        }

        this.updateTextColor = clrSilver;
    }

    /**
     * まとめ更新の外側で、保留しているラベル表示を反映する。
     * 描画要求の失敗時は保留状態を残し、次回の反映で再試行する。
     *
     * @return 保留中、更新不要、または描画要求に成功した場合true
     */
    bool flushDisplay() {
        if (!this.initialized) {
            return false;
        }

        if (this.updateBatchDepth > 0 || !this.displayUpdatePending) {
            return true;
        }

        bool isSucceeded = this.updateDisplay();
        if (isSucceeded) {
            this.displayUpdatePending = false;
        }

        return isSucceeded;
    }

    /**
     * 更新処理の1行を表示し、見出しと数値の両方へ全処理の説明文を設定する。
     *
     * @return 更新要求に成功した場合true
     */
    bool updateDisplay() {
        // 標準ツールチップの後半が省略されないよう、画面にない処理を先頭へ短くまとめる。
        string tooltip = "直近/平均/最大(ms・直近20回)";
        for (int i = 1; i < 4; i++) {
            tooltip += "\n" + this.metricTooltips[i];
        }

        tooltip += "\n" + this.metricTooltips[0];

        bool headerSucceeded = this.updateLabel(
            0,
            "処理時間(ms)  直近    平均    最大",
            tooltip,
            clrSilver
        );
        bool rowSucceeded = this.updateLabel(1, this.metricTexts[0], tooltip, this.updateTextColor);

        return headerSucceeded && rowSucceeded;
    }

    /**
     * 表示する行名を半角10文字相当の幅で返す。
     *
     * @param fromIndex 処理の行番号
     * @return 表示する行名
     */
    string getRowLabel(int fromIndex) {
        switch (fromIndex) {
            case 0:
                return "更新処理  ";
            case 1:
                return "EMA200    ";
            case 2:
                return "GMMA      ";
            case 3:
                return "日本時間軸";
        }

        return "";
    }

    /**
     * 計測値と失敗状態を、桁合わせの空白を含まない1行へまとめる。
     *
     * @param fromIndex 処理の行番号
     * @param fromStats 処理時間と実行状態
     * @return マウスを重ねた際に表示する説明
     */
    string getTooltip(int fromIndex, ProcessingTimeStats &fromStats) {
        string rowLabel = this.getRowLabel(fromIndex);
        StringTrimRight(rowLabel);
        string text = rowLabel + " --/--/--";
        if (fromStats.getCount() > 0) {
            text = StringFormat(
                "%s %.1f/%.1f/%.1f",
                rowLabel,
                fromStats.getLatestMilliseconds(),
                fromStats.getAverageMilliseconds(),
                fromStats.getMaximumMilliseconds()
            );
        }

        if (fromStats.getLastAttemptTime() > 0 && !fromStats.isLastSucceeded()) {
            text += " " + fromStats.getState();
        }

        return text;
    }

    /**
     * ラベル固有の名前を返す。
     *
     * @param fromIndex ヘッダー0・更新処理1・旧補助行2から4
     * @return 通常の全体描画で削除されないオブジェクト名
     */
    string getObjectName(int fromIndex) {
        return Constant::PREFIX_FIXED + "ZigZagElliotProcessingTime" + IntegerToString(fromIndex);
    }

    /**
     * ラベルを再利用し、固定属性は初期設定時だけ反映する。
     * 途中で設定要求が失敗した場合は、次回に全属性を反映し直す。
     *
     * @param fromIndex ヘッダー0・更新処理1
     * @param fromText 表示文字
     * @param fromTooltip 説明文字
     * @param fromColor 文字色
     * @return 全設定要求に成功した場合true
     */
    bool updateLabel(int fromIndex, string fromText, string fromTooltip, color fromColor) {
        string objectName = this.getObjectName(fromIndex);

        if (ObjectFind(0, objectName) < 0) {
            this.labelReady[fromIndex] = false;
            if (!ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0)) {
                return false;
            }
        }

        bool initializeProperties = !this.labelReady[fromIndex];
        this.labelReady[fromIndex] = false;

        if (initializeProperties) {
            if (!ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_RIGHT_UPPER)
                    || !ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
                    || !ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, this.positionX)
                    || !ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE,
                        DrawZigZagElliotInfoLayout::getProcessingTop() + fromIndex * 16)
                    || !ObjectSetString(0, objectName, OBJPROP_FONT, this.fontFace)
                    || !ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 10)
                    || !ObjectSetInteger(0, objectName, OBJPROP_BACK, false)
                    || !ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false)
                    || !ObjectSetInteger(0, objectName, OBJPROP_SELECTED, false)
                    || !ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true)) {
                return false;
            }
        }

        if (initializeProperties || this.labelTexts[fromIndex] != fromText) {
            if (!ObjectSetString(0, objectName, OBJPROP_TEXT, fromText)) {
                return false;
            }
        }

        if (initializeProperties || this.labelTooltips[fromIndex] != fromTooltip) {
            if (!ObjectSetString(0, objectName, OBJPROP_TOOLTIP, fromTooltip)) {
                return false;
            }
        }

        if (initializeProperties || this.labelColors[fromIndex] != fromColor) {
            if (!ObjectSetInteger(0, objectName, OBJPROP_COLOR, fromColor)) {
                return false;
            }
        }

        this.labelTexts[fromIndex] = fromText;
        this.labelTooltips[fromIndex] = fromTooltip;
        this.labelColors[fromIndex] = fromColor;
        this.labelReady[fromIndex] = true;

        return true;
    }
};

#endif
