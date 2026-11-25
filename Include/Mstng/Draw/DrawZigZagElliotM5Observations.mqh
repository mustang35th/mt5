#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_M5_OBSERVATIONS_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_M5_OBSERVATIONS_MQH

#include <Mstng\Database\Query\ZigZagElliotM5ObservationHistoryData.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 保存済みM5観測を時刻別の目印と7時間足の詳細へ描画する。
 * 波動を再分析せず、チャート価格は目印の画面上の配置にだけ使用する。
 */
class DrawZigZagElliotM5Observations {
public:
    /**
     * 描画先とこのインスタンスが所有する接頭辞を保持する。
     */
    DrawZigZagElliotM5Observations(const long fromChartId, const string fromPrefix) {
        this.chartId = fromChartId;
        this.prefix = fromPrefix;
        this.selectedTime = 0;
        this.selectedFrameIndex = 6;
        this.hoverTime = 0;
        this.markerCount = 0;
        this.chartWidth = 0;
        this.chartHeight = 0;
        this.mouseX = -1;
        this.mouseY = -1;
        this.hoverLeft = 0;
        this.hoverTop = 0;
        this.hoverWidth = 0;
        this.hoverHeight = 0;
        this.drawingSucceeded = true;
    }

    /**
     * この表示だけが所有するオブジェクトを解放する。
     */
    ~DrawZigZagElliotM5Observations() {
        this.clear();
    }

    /**
     * 目印・状態表示・詳細を消去し、選択を解除する。
     */
    void clear() {
        if (this.prefix != "") {
            ObjectsDeleteAll(this.chartId, this.prefix, 0, -1);
        }

        this.selectedTime = 0;
        this.selectedFrameIndex = 6;
        this.hoverTime = 0;
        this.markerCount = 0;
        this.mouseX = -1;
        this.mouseY = -1;
        ArrayFree(this.markerXs);
        ArrayFree(this.markerYs);
        ArrayFree(this.markerIndexes);
    }

    /**
     * 表示範囲のキャッシュだけを描画する。選択は同じM5時刻が残る場合に維持する。
     *
     * @param fromRecords 表示する時刻順の観測。idが0の行は未収録。
     * @param fromStatus DB読取状態と対象Runの説明。
     * @param fromDigits チャート銘柄の価格桁数。
     * @return 表示範囲内のオブジェクト作成に成功した場合true。
     */
    bool draw(const M5ObservationHistoryRecord &fromRecords[], const string fromStatus,
            const int fromDigits) {
        if (this.prefix == "") {
            return false;
        }

        ObjectsDeleteAll(this.chartId, this.prefix, 0, -1);
        this.hoverTime = 0;
        this.markerCount = 0;
        this.drawingSucceeded = true;
        int width = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS, 0);
        int height = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        this.chartWidth = width;
        this.chartHeight = height;
        if (width <= 0 || height <= 0) {
            return false;
        }

        int recordCount = ArraySize(fromRecords);
        if (ArrayResize(this.markerXs, recordCount) != recordCount
                || ArrayResize(this.markerYs, recordCount) != recordCount
                || ArrayResize(this.markerIndexes, recordCount) != recordCount) {
            return false;
        }

        int selectedIndex = -1;
        for (int i = 0; i < recordCount; i++) {
            if (this.drawMarker(fromRecords[i], i, width, height)
                    && fromRecords[i].barTime == this.selectedTime) {
                selectedIndex = i;
            }
        }

        string status = "M5保存: " + fromStatus;
        int statusY = MathMax(20, height - 142);
        this.drawLabel("Status", this.shorten(status, MathMax(8, (width - 24) / 11)),
            12, statusY, 8, clrSilver, this.shorten(status, 159), 8);
        if (selectedIndex >= 0) {
            this.drawPanel(fromRecords, selectedIndex, fromDigits, width, height);
        } else {
            this.selectedTime = 0;
            this.selectedFrameIndex = 6;
            this.onMouseMove(this.mouseX, this.mouseY, fromRecords);
        }

        return this.drawingSucceeded;
    }

    /**
     * この表示の目印選択、詳細の前後移動・時間足選択・閉じる操作を処理する。
     *
     * @return この表示がクリックを処理した場合true。
     */
    bool onObjectClick(const string fromObjectName, const M5ObservationHistoryRecord &fromRecords[],
            const string fromStatus, const int fromDigits) {
        if (this.prefix == "" || StringFind(fromObjectName, this.prefix) != 0) {
            return false;
        }

        if (StringFind(fromObjectName, this.prefix + "Panel") == 0) {
            if (fromObjectName == this.prefix + "PanelClose") {
                this.selectedTime = 0;
                this.selectedFrameIndex = 6;
                this.draw(fromRecords, fromStatus, fromDigits);

                return true;
            }

            if (fromObjectName == this.prefix + "PanelPrevious"
                    || fromObjectName == this.prefix + "PanelNext") {
                int direction = 1;
                if (fromObjectName == this.prefix + "PanelPrevious") {
                    direction = -1;
                }

                int targetIndex = this.findAdjacentRecordIndex(fromRecords, this.selectedTime, direction);
                if (targetIndex < 0) {
                    ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_STATE, false);

                    return true;
                }

                this.selectedTime = fromRecords[targetIndex].barTime;
                this.draw(fromRecords, fromStatus, fromDigits);

                return true;
            }

            for (int i = 0; i < 7; i++) {
                if (StringFind(fromObjectName, this.prefix + "PanelRow" + IntegerToString(i)) != 0) {
                    continue;
                }

                for (int j = 0; j < ArraySize(fromRecords); j++) {
                    if (fromRecords[j].barTime == this.selectedTime) {
                        this.selectedFrameIndex = i;
                        ObjectsDeleteAll(this.chartId, this.prefix + "Panel", 0, -1);
                        this.drawingSucceeded = true;
                        this.drawPanel(fromRecords, j, fromDigits, this.chartWidth, this.chartHeight);

                        return true;
                    }
                }
            }

            return true;
        }

        if (StringFind(fromObjectName, this.prefix + "Marker-") != 0) {
            return false;
        }

        for (int i = 0; i < ArraySize(fromRecords); i++) {
            if (fromObjectName == this.markerName(fromRecords[i].barTime)) {
                if (this.selectedTime != fromRecords[i].barTime) {
                    this.selectedFrameIndex = 6;
                }

                this.selectedTime = fromRecords[i].barTime;
                this.draw(fromRecords, fromStatus, fromDigits);

                return true;
            }
        }

        return false;
    }

    /**
     * キャッシュ済み目印座標だけでホバー対象を探し、保存波動の色付き説明を更新する。
     * 固定詳細を表示している間は、背後の目印によるホバー表示を抑止する。
     *
     * @return ホバーパネルの表示が変わった場合true。
     */
    bool onMouseMove(const int fromX, const int fromY,
            const M5ObservationHistoryRecord &fromRecords[]) {
        this.mouseX = fromX;
        this.mouseY = fromY;
        int markerIndex = -1;
        int nearestDistance = 129;
        bool overHover = this.hoverTime > 0
            && fromX >= this.hoverLeft && fromX < this.hoverLeft + this.hoverWidth
            && fromY >= this.hoverTop && fromY < this.hoverTop + this.hoverHeight;
        if (!overHover && this.selectedTime == 0 && fromX >= 0 && fromX < this.chartWidth
                && fromY >= 0 && fromY < this.chartHeight) {
            for (int i = 0; i < this.markerCount; i++) {
                int distanceX = fromX - this.markerXs[i];
                int distanceY = fromY - this.markerYs[i];
                if (MathAbs(distanceX) > 8 || MathAbs(distanceY) > 8) {
                    continue;
                }

                int distance = distanceX * distanceX + distanceY * distanceY;
                if (distance < nearestDistance) {
                    markerIndex = i;
                    nearestDistance = distance;
                }
            }
        }

        datetime nextTime = 0;
        int recordIndex = -1;
        if (markerIndex >= 0) {
            recordIndex = this.markerIndexes[markerIndex];
            if (recordIndex >= 0 && recordIndex < ArraySize(fromRecords)) {
                nextTime = fromRecords[recordIndex].barTime;
            }
        }
        if (nextTime == this.hoverTime) {
            return false;
        }

        bool changed = this.hoverTime > 0;
        ObjectsDeleteAll(this.chartId, this.prefix + "Hover", 0, -1);
        this.hoverTime = 0;
        if (nextTime > 0 && this.drawHover(fromRecords[recordIndex],
                this.markerXs[markerIndex], this.markerYs[markerIndex])) {
            this.hoverTime = nextTime;
            changed = true;
        }

        return changed;
    }

    /**
     * 全7時間足と観測時刻を優先し、長い波動ラベルだけを縮めた説明を返す。
     * 波方向の矢印は保存済みWave方向を用い、売買分析方向から推測しない。
     *
     * @return 最大159文字の目印用ツールチップ。
     */
    static string formatTooltip(const M5ObservationHistoryRecord &fromRecord) {
        string stamp = "SRV " + timeText(fromRecord.barTime);
        if (fromRecord.jstTime > 0) {
            stamp = "JST " + timeText(fromRecord.jstTime);
        }

        if (fromRecord.id <= 0) {
            return "M5保存情報: 記録なし\n" + stamp + "\nクリックで詳細";
        }

        string header = "M5保存 " + stamp;
        string tail = "\n取得 SRV " + timeText(fromRecord.captureTime);
        string result = "";
        for (int i = 10; i >= 1; i--) {
            result = header;
            for (int j = 0; j < 7; j++) {
                result += "\n" + frameName(j) + " " + waveText(fromRecord.frames[j], i);
            }

            result += tail;
            if (StringLen(result) <= 159) {
                return result;
            }
        }

        return shorten(result, 159);
    }

private:
    /** 描画先チャート。 */
    long chartId;

    /** このインスタンスだけが使用するオブジェクト接頭辞。 */
    string prefix;

    /** 詳細表示中のM5バー開始時刻。0は未選択。 */
    datetime selectedTime;

    /** 詳細の選択時間足。0から6がMN1からM5に対応する。 */
    int selectedFrameIndex;

    /** ホバー表示中のM5バー開始時刻。0は未表示。 */
    datetime hoverTime;

    /** 描画済み目印の横座標。 */
    int markerXs[];

    /** 描画済み目印の縦座標。 */
    int markerYs[];

    /** 描画済み目印に対応する観測キャッシュの添字。 */
    int markerIndexes[];

    /** 有効な描画済み目印の数。 */
    int markerCount;

    /** 最後に描画したメインチャートの幅。 */
    int chartWidth;

    /** 最後に描画したメインチャートの高さ。 */
    int chartHeight;

    /** 再描画時にもホバー位置を維持するための最終マウス横座標。 */
    int mouseX;

    /** 再描画時にもホバー位置を維持するための最終マウス縦座標。 */
    int mouseY;

    /** ホバーパネルが覆う領域の左端。 */
    int hoverLeft;

    /** ホバーパネルが覆う領域の上端。 */
    int hoverTop;

    /** ホバーパネルが覆う領域の幅。 */
    int hoverWidth;

    /** ホバーパネルが覆う領域の高さ。 */
    int hoverHeight;

    /** 今回の描画中にオブジェクト設定が成功している場合true。 */
    bool drawingSucceeded;

    /**
     * 目印の名前を保存時刻から生成する。
     */
    string markerName(const datetime fromTime) {
        return this.prefix + "Marker-" + IntegerToString((long)fromTime);
    }

    /**
     * 描画済み目印の中から、指定方向で最も近い保存済み観測を探す。
     * 未記録枠と同時刻を除外し、キャッシュの添字順には依存しない。
     *
     * @param fromDirection 古い観測は-1、新しい観測は1。
     * @return 対象のキャッシュ添字。移動先がなければ-1。
     */
    int findAdjacentRecordIndex(const M5ObservationHistoryRecord &fromRecords[],
            const datetime fromTime, const int fromDirection) {
        if (fromTime <= 0 || (fromDirection != -1 && fromDirection != 1)) {
            return -1;
        }

        int nearestIndex = -1;
        int count = MathMin(this.markerCount, ArraySize(this.markerIndexes));
        for (int i = 0; i < count; i++) {
            int recordIndex = this.markerIndexes[i];
            if (recordIndex < 0 || recordIndex >= ArraySize(fromRecords)) {
                continue;
            }
            if (fromRecords[recordIndex].id <= 0 || fromRecords[recordIndex].barTime <= 0) {
                continue;
            }

            datetime recordTime = fromRecords[recordIndex].barTime;
            if (fromDirection < 0 && recordTime < fromTime) {
                if (nearestIndex < 0 || recordTime > fromRecords[nearestIndex].barTime) {
                    nearestIndex = recordIndex;
                }
            } else if (fromDirection > 0 && recordTime > fromTime) {
                if (nearestIndex < 0 || recordTime < fromRecords[nearestIndex].barTime) {
                    nearestIndex = recordIndex;
                }
            }
        }

        return nearestIndex;
    }

    /**
     * 前後の保存済み観測との間隔が5分を超える場合だけ、移動間隔を明示する。
     */
    static string navigationGapText(const datetime fromTime, const datetime fromPreviousTime,
            const datetime fromNextTime) {
        string result = "";
        if (fromPreviousTime > 0 && fromTime - fromPreviousTime > 300) {
            result = "前まで " + IntegerToString((long)(fromTime - fromPreviousTime) / 60) + "分";
        }
        if (fromNextTime > 0 && fromNextTime - fromTime > 300) {
            if (result != "") {
                result += " / ";
            }

            result += "次まで " + IntegerToString((long)(fromNextTime - fromTime) / 60) + "分";
        }

        return result;
    }

    /**
     * 保存されたM5開始時刻の足を探し、安値の下へ目印を配置する。
     * 保存値の価格や波動にはチャートの現在値を混ぜない。
     */
    bool drawMarker(const M5ObservationHistoryRecord &fromRecord, const int fromIndex,
            const int fromWidth, const int fromHeight) {
        if (fromRecord.barTime <= 0) {
            return false;
        }

        string symbol = ChartSymbol(this.chartId);
        ENUM_TIMEFRAMES period = ChartPeriod(this.chartId);
        int shift = iBarShift(symbol, period, fromRecord.barTime, true);
        if (shift < 0) {
            return false;
        }

        double low = iLow(symbol, period, shift);
        int positionX = 0;
        int positionY = 0;
        if (low <= 0.0 || !ChartTimePriceToXY(this.chartId, 0, fromRecord.barTime, low,
                positionX, positionY) || positionX < 5 || positionX >= fromWidth - 6) {
            return false;
        }

        positionY = MathMax(18, MathMin(fromHeight - 24, positionY + 12));
        string text = "●";
        color markerColor = clrSilver;
        if (fromRecord.id <= 0) {
            text = "?";
            markerColor = clrDimGray;
        } else {
            markerColor = waveColor(fromRecord.frames[6]);
        }
        if (fromRecord.barTime == this.selectedTime) {
            markerColor = clrGold;
        }

        if (!this.drawLabel("Marker-" + IntegerToString((long)fromRecord.barTime), text,
                positionX, positionY, 9, markerColor, "\n", 10, ANCHOR_CENTER)) {
            return false;
        }

        this.markerXs[this.markerCount] = positionX;
        this.markerYs[this.markerCount] = positionY;
        this.markerIndexes[this.markerCount] = fromIndex;
        this.markerCount++;

        return true;
    }

    /**
     * 目印を覆わない位置に、保存波動と同じM5時刻の通貨強弱履歴を表示する。
     */
    bool drawHover(const M5ObservationHistoryRecord &fromRecord, const int fromX, const int fromY) {
        int panelWidth = MathMin(460, this.chartWidth - 16);
        int panelHeight = 310;
        if (this.chartHeight < panelHeight + 16) {
            panelHeight = 220;
        }
        if (fromRecord.id <= 0 || this.chartHeight < panelHeight + 16) {
            panelHeight = 100;
        }
        if (panelWidth < 180 || this.chartHeight < panelHeight + 16) {
            return false;
        }

        int left = fromX + 16;
        int top = MathMax(8, MathMin(this.chartHeight - panelHeight - 8, fromY - 12));
        if (left + panelWidth > this.chartWidth - 8) {
            if (fromX - panelWidth - 16 >= 8) {
                left = fromX - panelWidth - 16;
            } else if (fromY + panelHeight + 16 <= this.chartHeight - 8) {
                left = MathMax(8, MathMin(this.chartWidth - panelWidth - 8, fromX - panelWidth / 2));
                top = fromY + 16;
            } else if (fromY - panelHeight - 16 >= 8) {
                left = MathMax(8, MathMin(this.chartWidth - panelWidth - 8, fromX - panelWidth / 2));
                top = fromY - panelHeight - 16;
            } else {
                int rightSpace = this.chartWidth - fromX - 24;
                int leftSpace = fromX - 24;
                panelWidth = MathMax(rightSpace, leftSpace);
                if (panelWidth < 180) {
                    return false;
                }

                if (leftSpace > rightSpace) {
                    left = 8;
                }
            }
        }

        int textLimit = MathMax(8, (panelWidth - 20) / 12);
        bool previousSucceeded = this.drawingSucceeded;
        this.drawingSucceeded = true;
        this.drawBackground(left, top, panelWidth, panelHeight, "HoverBackground", 30);
        this.drawLabel("HoverTitle", "M5保存波動", left + 10, top + 8,
            9, clrWhiteSmoke, "\n", 31);
        string stamp = "SRV " + timeText(fromRecord.barTime);
        if (fromRecord.jstTime > 0) {
            stamp = "JST " + timeText(fromRecord.jstTime);
        }

        this.drawLabel("HoverTime", shorten(stamp, textLimit), left + 10, top + 28,
            9, clrSilver, "\n", 31);
        if (panelHeight == 100) {
            string explanation = "7足表示にはチャートを広げてください";
            if (fromRecord.id <= 0) {
                explanation = "このM5時刻の記録はありません";
            }

            this.drawLabel("HoverMessage", shorten(explanation, textLimit), left + 10, top + 50,
                9, clrSilver, "\n", 31);
        } else {
            string capture = "取得 SRV " + timeText(fromRecord.captureTime);
            this.drawLabel("HoverCapture", shorten(capture, textLimit), left + 10, top + 46,
                8, clrSilver, "\n", 31);
            for (int i = 0; i < 7; i++) {
                string text = frameName(i) + "  " + waveText(fromRecord.frames[i], textLimit - 6);
                this.drawLabel("HoverFrame" + IntegerToString(i), text,
                    left + 10, top + 66 + i * 18, 9, waveColor(fromRecord.frames[i]), "\n", 31);
            }

            if (panelHeight >= 310) {
                this.drawStrengthTable(fromRecord.strength, "HoverStrength", left + 10, top + 198,
                    panelWidth - 20, 9, 31, true);
            }
        }

        string hint = "クリックで詳細を固定表示";
        if (panelHeight == 220) {
            hint = "クリック詳細で通貨強弱を確認";
        }

        this.drawLabel("HoverHint", shorten(hint, textLimit),
            left + 10, top + panelHeight - 21, 8, clrSilver, "\n", 31);

        bool hoverSucceeded = this.drawingSucceeded;
        this.drawingSucceeded = previousSucceeded && hoverSucceeded;
        if (!hoverSucceeded) {
            ObjectsDeleteAll(this.chartId, this.prefix + "Hover", 0, -1);
        } else {
            this.hoverLeft = left;
            this.hoverTop = top;
            this.hoverWidth = panelWidth;
            this.hoverHeight = panelHeight;
        }

        return hoverSucceeded;
    }

    /**
     * 保存時点の5列表と、選択した時間足の項目別詳細を表示する。
     */
    void drawPanel(const M5ObservationHistoryRecord &fromRecords[], const int fromIndex,
            const int fromDigits, const int fromWidth, const int fromHeight) {
        int panelWidth = MathMin(1160, fromWidth - 24);
        int panelHeight = MathMin(540, fromHeight - 24);
        int left = MathMax(0, (fromWidth - panelWidth) / 2);
        int top = MathMax(0, (fromHeight - panelHeight) / 2);
        if (panelWidth < 180 || panelHeight < 100) {
            return;
        }

        int previousIndex = this.findAdjacentRecordIndex(fromRecords, fromRecords[fromIndex].barTime, -1);
        int nextIndex = this.findAdjacentRecordIndex(fromRecords, fromRecords[fromIndex].barTime, 1);
        datetime previousTime = 0;
        datetime nextTime = 0;
        if (previousIndex >= 0) {
            previousTime = fromRecords[previousIndex].barTime;
        }
        if (nextIndex >= 0) {
            nextTime = fromRecords[nextIndex].barTime;
        }

        this.drawBackground(left, top, panelWidth, panelHeight);
        this.drawLabel("PanelTitle", fitText("保存時点のエリオット表 / " + ChartSymbol(this.chartId),
            panelWidth - 194, 12), left + 12, top + 9, 12, clrWhiteSmoke, "\n", 21);
        this.drawNavigationButton("PanelPrevious", "◀ 前", "古い", left + panelWidth - 174,
            top + 6, previousIndex >= 0);
        this.drawNavigationButton("PanelNext", "次 ▶", "新しい", left + panelWidth - 104,
            top + 6, nextIndex >= 0);
        this.drawCloseButton(left + panelWidth - 34, top + 6);
        string stamp = "観測 SRV " + timeText(fromRecords[fromIndex].barTime);
        if (fromRecords[fromIndex].jstTime > 0) {
            stamp = "観測 JST " + timeText(fromRecords[fromIndex].jstTime);
        }

        this.drawLabel("PanelTime", fitText(stamp, panelWidth - 24, 14), left + 12, top + 32,
            14, clrWhite, stamp, 21);
        string metadata = "取得 SRV " + timeText(fromRecords[fromIndex].captureTime);
        string gap = navigationGapText(fromRecords[fromIndex].barTime, previousTime, nextTime);
        if (gap != "") {
            metadata += " / " + gap;
        }

        metadata += " / Run " + IntegerToString(fromRecords[fromIndex].runId)
            + " / ID " + IntegerToString(fromRecords[fromIndex].id);
        this.drawLabel("PanelMetadata", fitText(metadata, panelWidth - 24, 9), left + 12, top + 58,
            9, clrSilver, shorten(metadata, 159), 21);
        if (fromRecords[fromIndex].id <= 0) {
            if (panelHeight >= 140) {
                this.drawLabel("PanelMissing", fitText("このM5時刻の記録はありません。", panelWidth - 24, 11),
                    left + 12, top + 96, 11, clrSilver, "\n", 21);
            }

            return;
        }

        int detailColumns = 2;
        if (panelWidth >= 960) {
            detailColumns = 3;
        }

        int rowHeight = 26;
        int detailRowHeight = 24;
        int detailRows = 12 / detailColumns;
        int requiredHeight = 80 + 8 * rowHeight + 34 + detailRows * detailRowHeight + 88 + 25;
        if (requiredHeight > panelHeight) {
            rowHeight = 24;
            detailRowHeight = 20;
            requiredHeight = 80 + 8 * rowHeight + 34 + detailRows * detailRowHeight + 88 + 25;
        }

        if (panelWidth < 640 || panelHeight < requiredHeight) {
            if (panelHeight >= 140) {
                string message = "波動表・項目別詳細・通貨強弱を見るにはチャートを広げてください。";
                this.drawLabel("PanelSmall", fitText(message, panelWidth - 24, 11),
                    left + 12, top + 96, 11, clrSilver, message, 21);
            }

            return;
        }

        int innerWidth = panelWidth - 24;
        int columnWidths[] = {90, 88, 94, 134, innerWidth - 406};
        string headers[] = {"TimeFrame", "BuySell", "EMA200", "値動き", "Elliot"};
        int tableTop = top + 80;
        this.drawBackground(left + 12, tableTop, innerWidth, rowHeight, "PanelHeader", 21, C'38,47,62');
        int positionX = left + 12;
        for (int i = 0; i < 5; i++) {
            this.drawLabel("PanelHeader" + IntegerToString(i), headers[i], positionX + 8,
                tableTop + 5, 11, clrWhiteSmoke, "\n", 22);
            positionX += columnWidths[i];
        }

        for (int i = 0; i < 7; i++) {
            this.drawTableRow(fromRecords[fromIndex].frames[i], i, fromDigits, left + 12,
                tableTop + (i + 1) * rowHeight, rowHeight, columnWidths);
        }

        int detailTop = tableTop + 8 * rowHeight + 10;
        this.drawLabel("PanelDetailTitle", frameName(this.selectedFrameIndex) + " の詳細",
            left + 12, detailTop, 11, clrWhiteSmoke, "行をクリックして時間足を切り替えます。", 21);
        this.drawFrameDetails(fromRecords[fromIndex].frames[this.selectedFrameIndex], fromDigits,
            left + 12, detailTop + 24, innerWidth, detailColumns, detailRowHeight);
        int strengthTop = detailTop + 24 + detailRows * detailRowHeight + 8;
        this.drawStrengthTable(fromRecords[fromIndex].strength, "PanelStrength", left + 12, strengthTop,
            MathMin(620, innerWidth), 10, 21, false);
        this.drawLabel("PanelHint", "前・次：表示範囲内 / 行選択で詳細 / M1は未収録", left + 12,
            top + panelHeight - 21, 9, clrSilver, "保存値を表示します。現在の波動を再計算していません。", 21);
    }

    /**
     * 観測と同じM5時刻の通貨強弱を、両順位・順位差・前M5比の2行で表示する。
     */
    void drawStrengthTable(const M5ObservationHistoryStrength &fromStrength, const string fromKey,
            const int fromX, const int fromY, const int fromWidth, const int fromSize,
            const long fromZOrder, const bool fromHover) {
        string tooltip = "同じM5時刻の通貨強弱DB履歴です。観測保存時点の値とは限りません。";
        if (fromStrength.runId > 0) {
            tooltip += "\n通貨強弱 Run " + IntegerToString(fromStrength.runId);
        }
        if (fromHover) {
            tooltip = "\n";
        }

        this.drawLabel(fromKey + "Title", fitText(strengthTitle(fromStrength), fromWidth, fromSize),
            fromX, fromY, fromSize, clrWhiteSmoke, tooltip, fromZOrder);
        string status = strengthStatusText(fromStrength);
        if (status != "") {
            this.drawLabel(fromKey + "Status", fitText(status, fromWidth, fromSize),
                fromX, fromY + 28, fromSize, clrSilver, tooltip, fromZOrder);

            return;
        }
        if (fromWidth < 340) {
            this.drawLabel(fromKey + "Small", fitText("通貨強弱はクリック詳細で確認", fromWidth, fromSize),
                fromX, fromY + 28, fromSize, clrSilver, tooltip, fromZOrder);

            return;
        }

        int columnWidths[5];
        columnWidths[0] = fromWidth * 22 / 100;
        columnWidths[1] = fromWidth * 18 / 100;
        columnWidths[2] = fromWidth * 18 / 100;
        columnWidths[3] = fromWidth * 18 / 100;
        columnWidths[4] = fromWidth - columnWidths[0] - columnWidths[1] - columnWidths[2] - columnWidths[3];
        string headers[5];
        headers[0] = "期間";
        headers[1] = fromStrength.baseCurrency;
        headers[2] = fromStrength.quoteCurrency;
        headers[3] = "順位差";
        headers[4] = "前M5比";
        int positionX = fromX;
        for (int i = 0; i < 5; i++) {
            this.drawLabel(fromKey + "Header" + IntegerToString(i), fitText(headers[i], columnWidths[i] - 6, 9),
                positionX, fromY + 20, 9, clrSilver, tooltip, fromZOrder);
            positionX += columnWidths[i];
        }

        this.drawStrengthRow(fromStrength.longMedium, "長中期", fromKey + "LongMedium",
            fromX, fromY + 38, columnWidths, fromSize, fromZOrder, fromHover);
        this.drawStrengthRow(fromStrength.mediumShort, "中短期", fromKey + "MediumShort",
            fromX, fromY + 58, columnWidths, fromSize, fromZOrder, fromHover);
    }

    /**
     * 順位差と前M5比を別々の色にし、優位方向と増減方向を区別する。
     */
    void drawStrengthRow(const M5ObservationHistoryStrengthPeriod &fromPeriod, const string fromTitle,
            const string fromKey, const int fromX, const int fromY, const int &fromWidths[],
            const int fromSize, const long fromZOrder, const bool fromHover) {
        string values[5];
        values[0] = fromTitle;
        values[1] = strengthRankText(fromPeriod.baseRank, fromPeriod.valid);
        values[2] = strengthRankText(fromPeriod.quoteRank, fromPeriod.valid);
        values[3] = strengthGapText(fromPeriod);
        values[4] = strengthDeltaText(fromPeriod);
        color colors[5];
        colors[0] = clrWhiteSmoke;
        colors[1] = strengthValueColor(0, fromPeriod.valid);
        colors[2] = strengthValueColor(0, fromPeriod.valid);
        colors[3] = strengthValueColor(fromPeriod.gap, fromPeriod.valid);
        colors[4] = strengthValueColor(fromPeriod.delta, fromPeriod.valid && fromPeriod.comparable);
        int positionX = fromX;
        for (int i = 0; i < 5; i++) {
            string tooltip = values[i];
            if (fromHover) {
                tooltip = "\n";
            }

            this.drawLabel(fromKey + "Cell" + IntegerToString(i), fitText(values[i], fromWidths[i] - 6, fromSize),
                positionX, fromY, fromSize, colors[i], tooltip, fromZOrder);
            positionX += fromWidths[i];
        }
    }

    /**
     * 同時刻の別DB履歴であることと、実際の参照方式・モードを示す。
     */
    static string strengthTitle(const M5ObservationHistoryStrength &fromStrength) {
        string text = "同M5の通貨強弱履歴";
        if (fromStrength.weightLabel != "") {
            text += " / " + fromStrength.weightLabel;
        }
        if (fromStrength.sourceMode != "") {
            text += " / " + fromStrength.sourceMode;
        }

        return text;
    }

    /**
     * 強弱取得の失敗・設定OFF・未記録を、成功した順位表と区別する。
     */
    static string strengthStatusText(const M5ObservationHistoryStrength &fromStrength) {
        if (!fromStrength.enabled) {
            return "通貨強弱OFF";
        }
        if (fromStrength.status == "取得済み") {
            return "";
        }
        if (fromStrength.status == "") {
            return "未記録";
        }

        return fromStrength.status;
    }

    /**
     * 保存された有効な通貨順位だけを表示する。
     */
    static string strengthRankText(const int fromRank, const bool fromValid) {
        if (!fromValid) {
            return "未記録";
        }

        return IntegerToString(fromRank) + "位";
    }

    /**
     * 基軸通貨に対する強弱を符号付きの順位差で表示する。
     */
    static string strengthGapText(const M5ObservationHistoryStrengthPeriod &fromPeriod) {
        if (!fromPeriod.valid) {
            return "未記録";
        }
        if (fromPeriod.gap == 0) {
            return "0";
        }

        return StringFormat("%+d", fromPeriod.gap);
    }

    /**
     * 直前M5との比較可否を明示し、順位差の増減を矢印で示す。
     */
    static string strengthDeltaText(const M5ObservationHistoryStrengthPeriod &fromPeriod) {
        if (!fromPeriod.valid) {
            return "未記録";
        }
        if (!fromPeriod.comparable) {
            return "比較なし";
        }
        if (fromPeriod.delta > 0) {
            return StringFormat("↑ +%d", fromPeriod.delta);
        }
        if (fromPeriod.delta < 0) {
            return StringFormat("↓ %d", fromPeriod.delta);
        }

        return "→ 0";
    }

    /**
     * 順位差・増減の正負を水色・ピンクにし、ゼロと欠損を区別する。
     */
    static color strengthValueColor(const int fromValue, const bool fromValid) {
        if (!fromValid) {
            return clrSilver;
        }
        if (fromValue > 0) {
            return clrAqua;
        }
        if (fromValue < 0) {
            return clrHotPink;
        }

        return clrWhite;
    }

    /**
     * 各セルの判定に対応する文字色で一行を描き、行全体を選択可能にする。
     */
    void drawTableRow(const M5ObservationHistoryFrame &fromFrame, const int fromIndex,
            const int fromDigits, const int fromX, const int fromY, const int fromHeight,
            const int &fromWidths[]) {
        string key = "PanelRow" + IntegerToString(fromIndex);
        color background = C'25,31,41';
        if (fromIndex % 2 == 1) {
            background = C'31,38,49';
        }
        if (fromIndex == this.selectedFrameIndex) {
            background = C'42,59,83';
        }

        int totalWidth = 0;
        for (int i = 0; i < 5; i++) {
            totalWidth += fromWidths[i];
        }

        this.drawBackground(fromX, fromY, totalWidth, fromHeight, key + "Background", 21, background);
        string values[5];
        values[0] = frameName(fromIndex);
        values[1] = "未記録";
        if (fromFrame.hasData) {
            values[1] = stateText(fromFrame.isBuy, "BUY", "SELL");
        }

        values[2] = emaText(fromFrame);
        values[3] = movementText(fromFrame);
        values[4] = tableElliotText(fromFrame, fromDigits);
        color directionColor = clrSilver;
        if (fromFrame.hasData) {
            directionColor = analysisColor(fromFrame.isBuy);
        }

        color colors[5];
        colors[0] = directionColor;
        colors[1] = directionColor;
        colors[2] = emaColor(fromFrame);
        colors[3] = movementColor(fromFrame);
        colors[4] = elliotColor(fromFrame);
        int positionX = fromX;
        for (int i = 0; i < 5; i++) {
            this.drawLabel(key + "Cell" + IntegerToString(i), fitText(values[i], fromWidths[i] - 16, 11),
                positionX + 8, fromY + 5, 11, colors[i], shorten(values[i], 159), 22);
            positionX += fromWidths[i];
            if (i < 4) {
                this.drawBackground(positionX - 1, fromY, 1, fromHeight, key + "Line" + IntegerToString(i),
                    21, C'51,61,77');
            }
        }
    }

    /**
     * 選択した足の保存値を項目名と値に分け、欠損を明示する。
     */
    void drawFrameDetails(const M5ObservationHistoryFrame &fromFrame, const int fromDigits,
            const int fromX, const int fromY, const int fromWidth, const int fromColumns,
            const int fromRowHeight) {
        string labels[] = {"主波", "副次波", "元波", "確定状態", "補完状態", "前推進波の副",
            "F", "FE", "値幅", "ポイント価格", "ポイント時刻", "波動方向"};
        string values[12];
        for (int i = 0; i < 12; i++) {
            values[i] = "未記録";
        }

        if (fromFrame.hasData) {
            values[0] = recordedText(fromFrame.mainWave);
            values[1] = fromFrame.subWave;
            if (values[1] == "") {
                values[1] = "なし";
            }

            values[2] = recordedText(fromFrame.originalWave);
            values[3] = stateText(fromFrame.isConfirmed, "確定", "未確定");
            values[4] = stateText(fromFrame.isAdded, "補完 ★", "通常");
            if (fromFrame.previousMotiveSubElliotIndex >= 0) {
                values[5] = "なし";
                if (fromFrame.previousMotiveSubElliotIndex > 0) {
                    values[5] = IntegerToString(fromFrame.previousMotiveSubElliotIndex) + "副";
                }
            }

            values[6] = numberText(fromFrame.pointFibonacciPercent, fromFrame.hasPointFibonacciPercent, 1, "%");
            values[7] = numberText(fromFrame.pointFibonacciExpansionPercent,
                fromFrame.hasPointFibonacciExpansionPercent, 1, "%");
            values[8] = numberText(fromFrame.pointPipsDiff, fromFrame.hasPointPipsDiff, 1, " pips");
            values[9] = numberText(fromFrame.pointRate, fromFrame.hasPointRate, fromDigits);
            values[10] = "SRV " + timeText(fromFrame.pointTime);
            if (fromFrame.pointJstTime > 0) {
                values[10] = "JST " + timeText(fromFrame.pointJstTime);
            }

            values[11] = stateText(fromFrame.isUptrend, "上昇 ▲", "下降 ▼");
        }

        int itemWidth = fromWidth / fromColumns;
        for (int i = 0; i < 12; i++) {
            int positionX = fromX + (i % fromColumns) * itemWidth;
            int positionY = fromY + (i / fromColumns) * fromRowHeight;
            this.drawLabel("PanelDetailLabel" + IntegerToString(i), labels[i], positionX,
                positionY, 10, clrSilver, "\n", 21);
            this.drawLabel("PanelDetailValue" + IntegerToString(i), fitText(values[i], itemWidth - 114, 11),
                positionX + 104, positionY, 11, clrWhiteSmoke, shorten(labels[i] + ": " + values[i], 159), 21);
        }
    }

    /**
     * チャートのElliot列と同じ順序で、保存済みポイント情報を組み立てる。
     */
    static string tableElliotText(const M5ObservationHistoryFrame &fromFrame, const int fromDigits) {
        if (!fromFrame.hasData) {
            return "未記録";
        }

        string text = "";
        if (fromFrame.previousMotiveSubElliotIndex > 0) {
            text += "[" + IntegerToString(fromFrame.previousMotiveSubElliotIndex) + "副] ";
        }
        if (fromFrame.isConfirmed == 0) {
            text += "【未】";
        }
        if (fromFrame.isAdded == 1) {
            text += "★";
        }

        text += waveText(fromFrame, 0);
        if (fromFrame.originalWave != "" && fromFrame.originalWave != fromFrame.mainWave) {
            text += "[" + fromFrame.originalWave + "]";
        }
        if (fromFrame.originalWaveIndex > 1) {
            if (fromFrame.originalWaveIndex % 2 == 0) {
                text += "[F" + numberText(fromFrame.pointFibonacciPercent,
                    fromFrame.hasPointFibonacciPercent, 1, "%") + "]";
            } else {
                text += "[FE" + numberText(fromFrame.pointFibonacciExpansionPercent,
                    fromFrame.hasPointFibonacciExpansionPercent, 1, "%") + "]";
            }
        } else if (fromFrame.originalWaveIndex < 0) {
            text += "[F/FE未記録]";
        }

        text += "<" + numberText(fromFrame.pointPipsDiff, fromFrame.hasPointPipsDiff, 1, "p") + ">";
        text += numberText(fromFrame.pointRate, fromFrame.hasPointRate, fromDigits);

        return text;
    }

    /**
     * 分析方向の色をチャート表へ合わせる。
     */
    static color analysisColor(const int fromIsBuy) {
        if (fromIsBuy == 1) {
            return clrAqua;
        }
        if (fromIsBuy == 0) {
            return clrHotPink;
        }

        return clrSilver;
    }

    /**
     * チャートと同じ優先順で、補完・未確定・分析方向の色を選ぶ。
     */
    static color elliotColor(const M5ObservationHistoryFrame &fromFrame) {
        if (!fromFrame.hasData) {
            return clrSilver;
        }
        if (fromFrame.isAdded == 1) {
            return clrWhite;
        }
        if (fromFrame.isAdded < 0 || fromFrame.isConfirmed < 0 || fromFrame.isBuy < 0) {
            return clrSilver;
        }
        if (fromFrame.isConfirmed == 0) {
            if (fromFrame.isBuy == 1) {
                return clrDodgerBlue;
            }

            return clrMagenta;
        }

        return analysisColor(fromFrame.isBuy);
    }

    /**
     * EMA200の保存済みフラグをBUY・SELL・NONEへ変換する。
     */
    static string emaText(const M5ObservationHistoryFrame &fromFrame) {
        if (!fromFrame.hasData || fromFrame.isEma200Buy < 0 || fromFrame.isEma200Sell < 0) {
            return "未記録";
        }
        if (fromFrame.isEma200Buy == 1 && fromFrame.isEma200Sell == 0) {
            return "BUY";
        }
        if (fromFrame.isEma200Sell == 1 && fromFrame.isEma200Buy == 0) {
            return "SELL";
        }
        if (fromFrame.isEma200Buy == 0 && fromFrame.isEma200Sell == 0) {
            return "NONE";
        }

        return "判定不能";
    }

    /**
     * EMA200は分析方向と独立したチャートの方向色を使用する。
     */
    static color emaColor(const M5ObservationHistoryFrame &fromFrame) {
        string direction = emaText(fromFrame);
        if (direction == "BUY") {
            return clrAqua;
        }
        if (direction == "SELL") {
            return clrHotPink;
        }
        if (direction == "NONE") {
            return clrWhite;
        }

        return clrSilver;
    }

    /**
     * 値動きの保存状態と活動度をチャートと同じ書式へ変換する。
     */
    static string movementText(const M5ObservationHistoryFrame &fromFrame) {
        if (!fromFrame.hasData || fromFrame.isPriceMovementValid < 0) {
            return "未記録";
        }
        if (fromFrame.isPriceMovementValid == 0) {
            return "判定不能";
        }
        if (fromFrame.priceMovementLevel < 0) {
            return "未記録";
        }

        string text = "判定不能";
        if (fromFrame.priceMovementLevel == 1) {
            text = "静か";
        } else if (fromFrame.priceMovementLevel == 2) {
            text = "通常";
        } else if (fromFrame.priceMovementLevel == 3) {
            text = "活発";
        }

        return text + " " + numberText(fromFrame.priceMovementActivityRatio,
            fromFrame.hasPriceMovementActivityRatio, 2);
    }

    /**
     * 値動き列は静か・通常・活発をチャートと同じ色で表示する。
     */
    static color movementColor(const M5ObservationHistoryFrame &fromFrame) {
        if (fromFrame.hasData && fromFrame.isPriceMovementValid == 1) {
            if (fromFrame.priceMovementLevel == 2) {
                return clrWhite;
            }
            if (fromFrame.priceMovementLevel == 3) {
                return clrDodgerBlue;
            }
        }

        return clrSilver;
    }

    /**
     * 保存有無を維持し、取得済みのゼロを未記録と混同しない。
     */
    static string numberText(const double fromValue, const bool fromHasValue,
            const int fromDigits, const string fromSuffix = "") {
        if (!fromHasValue) {
            return "未記録";
        }

        return DoubleToString(fromValue, MathMax(0, MathMin(8, fromDigits))) + fromSuffix;
    }

    /**
     * 空の保存ラベルを未記録として表示する。
     */
    static string recordedText(const string fromText) {
        if (fromText == "") {
            return "未記録";
        }

        return fromText;
    }

    /**
     * 実際のフォント幅を確認し、隣の列へはみ出さない長さへ省略する。
     */
    static string fitText(const string fromText, const int fromWidth, const int fromSize) {
        if (fromWidth <= 0) {
            return "";
        }

        uint width = 0;
        uint height = 0;
        if (!TextSetFont("MS Gothic", -10 * fromSize) || !TextGetSize(fromText, width, height)) {
            return shorten(fromText, MathMax(1, fromWidth / MathMax(1, fromSize)));
        }
        if ((int)width <= fromWidth) {
            return fromText;
        }

        for (int i = StringLen(fromText) - 1; i >= 0; i--) {
            string text = StringSubstr(fromText, 0, i) + "…";
            if (TextGetSize(text, width, height) && (int)width <= fromWidth) {
                return text;
            }
        }

        return "";
    }

    /**
     * 背景だけを描き、チャートオブジェクトの縮尺計算へ価格座標を追加しない。
     */
    void drawBackground(const int fromX, const int fromY, const int fromWidth, const int fromHeight,
            const string fromKey = "PanelBackground", const long fromZOrder = 20,
            const color fromBackground = C'24,29,38') {
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_RECTANGLE_LABEL)) {
            return;
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, fromWidth)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, fromHeight)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, fromBackground)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BORDER_TYPE, BORDER_FLAT)
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, clrSlateGray)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, fromZOrder)
            && ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, "\n");
        this.drawingSucceeded = this.drawingSucceeded && success;
    }

    /**
     * 表示範囲内の保存済み観測を移動するボタンを描画する。
     * 移動先がない場合は灰色にし、クリック処理でも移動を抑止する。
     */
    void drawNavigationButton(const string fromKey, const string fromText, const string fromDirection,
            const int fromX, const int fromY, const bool fromEnabled) {
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_BUTTON)) {
            return;
        }

        color textColor = clrDimGray;
        color backgroundColor = C'30,35,44';
        string tooltip = "表示範囲内に" + fromDirection + "保存済み観測がありません。";
        if (fromEnabled) {
            textColor = clrWhiteSmoke;
            backgroundColor = C'45,53,66';
            tooltip = "表示範囲内の" + fromDirection + "保存済み観測へ移動します。";
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, 64)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, 22)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, backgroundColor)
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, textColor)
            && ObjectSetInteger(this.chartId, name, OBJPROP_STATE, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 9)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 22)
            && ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic")
            && ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText)
            && ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, tooltip);
        this.drawingSucceeded = this.drawingSucceeded && success;
    }

    /**
     * 詳細を閉じるボタンを描画する。
     */
    void drawCloseButton(const int fromX, const int fromY) {
        string name = this.prefix + "PanelClose";
        if (!this.createObject(name, OBJ_BUTTON)) {
            return;
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, 24)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, 20)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, C'45,53,66')
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, clrWhiteSmoke)
            && ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, 9)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 22)
            && ObjectSetString(this.chartId, name, OBJPROP_TEXT, "×")
            && ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, "M5保存情報を閉じる");
        this.drawingSucceeded = this.drawingSucceeded && success;
    }

    /**
     * 自分の名前でオブジェクトを生成し、ドラッグと一覧表示を無効にする。
     */
    bool createObject(const string fromName, const ENUM_OBJECT fromType) {
        if (!ObjectCreate(this.chartId, fromName, fromType, 0, 0, 0)) {
            this.drawingSucceeded = false;
            return false;
        }

        bool success = ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTED, false)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_HIDDEN, true);
        this.drawingSucceeded = this.drawingSucceeded && success;

        return success;
    }

    /**
     * 固定画面座標の文字を表示する。
     */
    bool drawLabel(const string fromKey, const string fromText, const int fromX, const int fromY,
            const int fromSize, const color fromColor, const string fromTooltip, const long fromZOrder,
            const ENUM_ANCHOR_POINT fromAnchor = ANCHOR_LEFT_UPPER) {
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_LABEL)) {
            return false;
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ANCHOR, fromAnchor)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, fromColor)
            && ObjectSetInteger(this.chartId, name, OBJPROP_FONTSIZE, fromSize)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, fromZOrder)
            && ObjectSetString(this.chartId, name, OBJPROP_FONT, "MS Gothic")
            && ObjectSetString(this.chartId, name, OBJPROP_TEXT, fromText)
            && ObjectSetString(this.chartId, name, OBJPROP_TOOLTIP, fromTooltip);
        this.drawingSucceeded = this.drawingSucceeded && success;

        return success;
    }

    /**
     * 保存済みWave方向を色へ変換し、未記録・方向不明は灰色にする。
     */
    static color waveColor(const M5ObservationHistoryFrame &fromFrame) {
        if (fromFrame.hasData && fromFrame.isUptrend == 1) {
            return clrDeepSkyBlue;
        }
        if (fromFrame.hasData && fromFrame.isUptrend == 0) {
            return clrPlum;
        }

        return clrSilver;
    }

    /**
     * 表示順に対応する固定の時間足名を返す。
     */
    static string frameName(const int fromIndex) {
        string names[] = {"MN1", "W1", "D1", "H4", "H1", "M15", "M5"};
        if (fromIndex < 0 || fromIndex >= ArraySize(names)) {
            return "—";
        }

        return names[fromIndex];
    }

    /**
     * 主波・副次波を省略上限に収め、保存済みWave方向を前へ付ける。
     */
    static string waveText(const M5ObservationHistoryFrame &fromFrame, const int fromLimit) {
        if (!fromFrame.hasData) {
            return "未記録";
        }

        string direction = "?";
        if (fromFrame.isUptrend == 1) {
            direction = "▲";
        } else if (fromFrame.isUptrend == 0) {
            direction = "▼";
        }
        string wave = fromFrame.mainWave;
        if (wave == "") {
            wave = "—";
        }
        if (fromFrame.subWave != "") {
            wave += "." + fromFrame.subWave;
        }

        return direction + shorten(wave, fromLimit);
    }

    /**
     * 0・1・未記録の3状態を混同せず表示する。
     */
    static string stateText(const int fromState, const string fromTrue, const string fromFalse) {
        if (fromState == 1) {
            return fromTrue;
        }
        if (fromState == 0) {
            return fromFalse;
        }

        return "未記録";
    }

    /**
     * 保存時刻をチャート共通のyyyy/MM/dd HH:mm:ss形式で表示し、時刻0は未記録として扱う。
     */
    static string timeText(const datetime fromTime) {
        if (fromTime <= 0) {
            return "未記録";
        }

        return TimeUtil::formatYyyymmddhhmiss(fromTime);
    }

    /**
     * 上限を超えた文字列を省略記号付きで短縮する。上限0は全文を保持する。
     */
    static string shorten(const string fromText, const int fromLimit) {
        if (fromLimit <= 0 || StringLen(fromText) <= fromLimit) {
            return fromText;
        }

        return StringSubstr(fromText, 0, fromLimit - 1) + "…";
    }
};

#endif // MSTNG_DRAW_ZIGZAG_ELLIOT_M5_OBSERVATIONS_MQH
