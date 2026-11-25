#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_M5_OBSERVATIONS_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_M5_OBSERVATIONS_MQH

#include <Mstng\Database\Query\ZigZagElliotM5ObservationHistoryData.mqh>

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
            this.drawPanel(fromRecords[selectedIndex], fromDigits, width, height);
        } else {
            this.selectedTime = 0;
            this.selectedFrameIndex = 6;
            this.onMouseMove(this.mouseX, this.mouseY, fromRecords);
        }

        return this.drawingSucceeded;
    }

    /**
     * この表示の目印選択または詳細を閉じる操作だけを処理する。
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

            for (int i = 0; i < 7; i++) {
                if (StringFind(fromObjectName, this.prefix + "PanelRow" + IntegerToString(i)) != 0) {
                    continue;
                }

                for (int j = 0; j < ArraySize(fromRecords); j++) {
                    if (fromRecords[j].barTime == this.selectedTime) {
                        this.selectedFrameIndex = i;
                        ObjectsDeleteAll(this.chartId, this.prefix + "Panel", 0, -1);
                        this.drawingSucceeded = true;
                        this.drawPanel(fromRecords[j], fromDigits, this.chartWidth, this.chartHeight);

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
        string stamp = "SV " + timeText(fromRecord.barTime, false);
        if (fromRecord.jstTime > 0) {
            stamp = "JST " + timeText(fromRecord.jstTime, false);
        }

        if (fromRecord.id <= 0) {
            return "M5保存情報: 記録なし\n" + stamp + "\nクリックで詳細";
        }

        string header = "M5保存 " + stamp;
        string tail = "\n取得SV " + timeText(fromRecord.captureTime, true);
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
     * 目印を覆わない位置に、保存時刻と7時間足の主波・副次波を表示する。
     */
    bool drawHover(const M5ObservationHistoryRecord &fromRecord, const int fromX, const int fromY) {
        int panelWidth = MathMin(400, this.chartWidth - 16);
        int panelHeight = 220;
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
        string stamp = "SV " + timeText(fromRecord.barTime, false);
        if (fromRecord.jstTime > 0) {
            stamp = "JST " + timeText(fromRecord.jstTime, false);
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
            string capture = "取得SV " + timeText(fromRecord.captureTime, true);
            this.drawLabel("HoverCapture", shorten(capture, textLimit), left + 10, top + 46,
                8, clrSilver, "\n", 31);
            for (int i = 0; i < 7; i++) {
                string text = frameName(i) + "  " + waveText(fromRecord.frames[i], textLimit - 6);
                this.drawLabel("HoverFrame" + IntegerToString(i), text,
                    left + 10, top + 66 + i * 18, 9, waveColor(fromRecord.frames[i]), "\n", 31);
            }
        }

        this.drawLabel("HoverHint", shorten("クリックで詳細を固定表示", textLimit),
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
    void drawPanel(const M5ObservationHistoryRecord &fromRecord, const int fromDigits,
            const int fromWidth, const int fromHeight) {
        int panelWidth = MathMin(1160, fromWidth - 24);
        int panelHeight = MathMin(540, fromHeight - 24);
        int left = MathMax(0, (fromWidth - panelWidth) / 2);
        int top = MathMax(0, (fromHeight - panelHeight) / 2);
        if (panelWidth < 180 || panelHeight < 100) {
            return;
        }

        this.drawBackground(left, top, panelWidth, panelHeight);
        this.drawLabel("PanelTitle", fitText("保存時点のエリオット表 / " + ChartSymbol(this.chartId),
            panelWidth - 64, 12), left + 12, top + 9, 12, clrWhiteSmoke, "\n", 21);
        this.drawCloseButton(left + panelWidth - 34, top + 6);
        string stamp = "観測 SV " + timeText(fromRecord.barTime, false);
        if (fromRecord.jstTime > 0) {
            stamp = "観測 JST " + timeText(fromRecord.jstTime, false);
        }

        this.drawLabel("PanelTime", fitText(stamp, panelWidth - 24, 14), left + 12, top + 32,
            14, clrWhite, stamp, 21);
        string metadata = "取得 SV " + timeText(fromRecord.captureTime, true)
            + " / Run " + IntegerToString(fromRecord.runId) + " / ID " + IntegerToString(fromRecord.id);
        this.drawLabel("PanelMetadata", fitText(metadata, panelWidth - 24, 9), left + 12, top + 58,
            9, clrSilver, shorten(metadata, 159), 21);
        if (fromRecord.id <= 0) {
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

        int rowHeight = 28;
        int detailRowHeight = 26;
        if (panelHeight < 525) {
            rowHeight = 24;
            detailRowHeight = 22;
        }

        int detailRows = 12 / detailColumns;
        int requiredHeight = 80 + 8 * rowHeight + 38 + detailRows * detailRowHeight + 25;
        if (panelWidth < 640 || panelHeight < requiredHeight) {
            if (panelHeight >= 140) {
                string message = "5列表と項目別詳細を見るにはチャートを広げてください。";
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
            this.drawTableRow(fromRecord.frames[i], i, fromDigits, left + 12,
                tableTop + (i + 1) * rowHeight, rowHeight, columnWidths);
        }

        int detailTop = tableTop + 8 * rowHeight + 12;
        this.drawLabel("PanelDetailTitle", frameName(this.selectedFrameIndex) + " の詳細",
            left + 12, detailTop, 11, clrWhiteSmoke, "行をクリックして時間足を切り替えます。", 21);
        this.drawFrameDetails(fromRecord.frames[this.selectedFrameIndex], fromDigits,
            left + 12, detailTop + 26, innerWidth, detailColumns, detailRowHeight);
        this.drawLabel("PanelHint", "行をクリックして項目別表示 / M1は未収録", left + 12,
            top + panelHeight - 21, 9, clrSilver, "保存値を表示します。現在の波動を再計算していません。", 21);
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
            values[10] = "SV " + timeText(fromFrame.pointTime, false);
            if (fromFrame.pointJstTime > 0) {
                values[10] = "JST " + timeText(fromFrame.pointJstTime, false);
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
     * 保存時刻を表示し、時刻0は未記録として扱う。
     */
    static string timeText(const datetime fromTime, const bool fromSeconds) {
        if (fromTime <= 0) {
            return "未記録";
        }

        int flags = TIME_DATE | TIME_MINUTES;
        if (fromSeconds) {
            flags = TIME_DATE | TIME_SECONDS;
        }

        return TimeToString(fromTime, flags);
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
