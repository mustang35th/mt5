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
        this.drawingSucceeded = true;
        int width = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS, 0);
        int height = (int)ChartGetInteger(this.chartId, CHART_HEIGHT_IN_PIXELS, 0);
        if (width <= 0 || height <= 0) {
            return false;
        }

        int selectedIndex = -1;
        for (int i = 0; i < ArraySize(fromRecords); i++) {
            if (this.drawMarker(fromRecords[i], width, height)
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

        if (fromObjectName == this.prefix + "PanelClose") {
            this.selectedTime = 0;
            ObjectsDeleteAll(this.chartId, this.prefix + "Panel", 0, -1);

            return true;
        }

        if (StringFind(fromObjectName, this.prefix + "Marker-") != 0) {
            return false;
        }

        for (int i = 0; i < ArraySize(fromRecords); i++) {
            if (fromObjectName == this.markerName(fromRecords[i].barTime)) {
                this.selectedTime = fromRecords[i].barTime;
                this.draw(fromRecords, fromStatus, fromDigits);

                return true;
            }
        }

        return false;
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
    bool drawMarker(const M5ObservationHistoryRecord &fromRecord, const int fromWidth,
            const int fromHeight) {
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
        } else if (fromRecord.frames[6].hasData && fromRecord.frames[6].isUptrend == 1) {
            markerColor = clrDeepSkyBlue;
        } else if (fromRecord.frames[6].hasData && fromRecord.frames[6].isUptrend == 0) {
            markerColor = clrPlum;
        }
        if (fromRecord.barTime == this.selectedTime) {
            markerColor = clrGold;
        }

        this.drawLabel("Marker-" + IntegerToString((long)fromRecord.barTime), text,
            positionX, positionY, 9, markerColor, formatTooltip(fromRecord), 10, ANCHOR_CENTER);

        return true;
    }

    /**
     * 選択した一件の保存値をチャート中央へ表示する。
     */
    void drawPanel(const M5ObservationHistoryRecord &fromRecord, const int fromDigits,
            const int fromWidth, const int fromHeight) {
        int panelWidth = MathMin(780, fromWidth - 24);
        int panelHeight = MathMin(380, fromHeight - 24);
        int left = MathMax(0, (fromWidth - panelWidth) / 2);
        int top = MathMax(0, (fromHeight - panelHeight) / 2);
        if (panelWidth < 180 || panelHeight < 100) {
            return;
        }

        this.drawBackground(left, top, panelWidth, panelHeight);
        string title = shorten("M5保存情報 / M1波動は未収録", MathMax(8, (panelWidth - 58) / 12));
        this.drawLabel("PanelTitle", title, left + 10, top + 9,
            10, clrWhiteSmoke, "保存時点の分析。▲▼はWave方向、分析B/Sは売買分析方向。", 21);
        this.drawCloseButton(left + panelWidth - 34, top + 6);
        int textLimit = MathMax(8, (panelWidth - 24) / 12);
        if (panelHeight < 120) {
            this.panelLine("PanelSmall", "詳細を見るにはチャートを縦に広げてください。",
                left + 10, top + 31, textLimit, clrSilver);

            return;
        }

        string identification = "Run " + IntegerToString(fromRecord.runId)
            + " / ID " + IntegerToString(fromRecord.id);
        this.panelLine("PanelId", identification, left + 10, top + 31, textLimit, clrSilver);
        string barText = "対象 SV " + timeText(fromRecord.barTime, false)
            + " / JST " + timeText(fromRecord.jstTime, false);
        this.panelLine("PanelBar", barText, left + 10, top + 49, textLimit, clrSilver);
        string captureText = "取得 SV " + timeText(fromRecord.captureTime, true);
        this.panelLine("PanelCapture", captureText, left + 10, top + 67, textLimit, clrSilver);
        if (fromRecord.id <= 0) {
            this.panelLine("PanelMissing", "このM5時刻の記録はありません。", left + 10,
                top + 91, textLimit, clrSilver);

            return;
        }

        if (panelHeight < 225) {
            this.panelLine("PanelSmall", "7足の詳細を見るにはチャートを縦に広げてください。",
                left + 10, top + 91, textLimit, clrSilver);

            return;
        }

        bool twoLines = panelHeight >= 350;
        int rowHeight = 18;
        if (twoLines) {
            rowHeight = 37;
        }
        for (int i = 0; i < 7; i++) {
            int rowTop = top + 94 + i * rowHeight;
            string summary = this.frameSummary(fromRecord.frames[i], i);
            string point = this.pointSummary(fromRecord.frames[i], fromDigits);
            string details = summary + "\n" + point;
            color textColor = clrSilver;
            if (fromRecord.frames[i].hasData) {
                textColor = clrWhiteSmoke;
            }
            this.drawLabel("PanelFrame" + IntegerToString(i), shorten(summary, textLimit),
                left + 10, rowTop, 9, textColor, shorten(details, 159), 21);
            if (twoLines) {
                this.drawLabel("PanelPoint" + IntegerToString(i), shorten(point, textLimit),
                    left + 43, rowTop + 17, 8, clrSilver, shorten(details, 159), 21);
            }
        }
    }

    /**
     * 主波・副次波・元ラベルと、それぞれ独立した保存済み状態を一行へまとめる。
     */
    string frameSummary(const M5ObservationHistoryFrame &fromFrame, const int fromIndex) {
        string text = frameName(fromIndex) + "  ";
        if (!fromFrame.hasData) {
            return text + "未記録";
        }

        text += waveText(fromFrame, 0);
        if (fromFrame.originalWave != "" && fromFrame.originalWave != fromFrame.mainWave) {
            text += " [元 " + fromFrame.originalWave + "]";
        }
        text += "  Wave " + stateText(fromFrame.isConfirmed, "確定", "未確定");
        text += " / 点 " + stateText(fromFrame.isAdded, "追加途中", "通常");
        text += " / 分析 " + stateText(fromFrame.isBuy, "B", "S");

        return text;
    }

    /**
     * 最新ポイントの保存時刻と価格を表示する。未記録値をゼロで代用しない。
     */
    string pointSummary(const M5ObservationHistoryFrame &fromFrame, const int fromDigits) {
        if (!fromFrame.hasData) {
            return "最新ポイント: 未記録";
        }

        string rate = "未記録";
        if (fromFrame.hasPointRate) {
            rate = DoubleToString(fromFrame.pointRate, MathMax(0, MathMin(8, fromDigits)));
        }

        return "点 SV " + timeText(fromFrame.pointTime, false) + " / 価格 " + rate;
    }

    /**
     * パネルの説明一行を幅に収め、元の文字列はツールチップへ保持する。
     */
    void panelLine(const string fromKey, const string fromText, const int fromX, const int fromY,
            const int fromLimit, const color fromColor) {
        this.drawLabel(fromKey, shorten(fromText, fromLimit), fromX, fromY, 9, fromColor,
            shorten(fromText, 159), 21);
    }

    /**
     * 背景だけを描き、チャートオブジェクトの縮尺計算へ価格座標を追加しない。
     */
    void drawBackground(const int fromX, const int fromY, const int fromWidth, const int fromHeight) {
        string name = this.prefix + "PanelBackground";
        if (!this.createObject(name, OBJ_RECTANGLE_LABEL)) {
            return;
        }

        bool success = ObjectSetInteger(this.chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XDISTANCE, fromX)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YDISTANCE, fromY)
            && ObjectSetInteger(this.chartId, name, OBJPROP_XSIZE, fromWidth)
            && ObjectSetInteger(this.chartId, name, OBJPROP_YSIZE, fromHeight)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BGCOLOR, C'24,29,38')
            && ObjectSetInteger(this.chartId, name, OBJPROP_BORDER_TYPE, BORDER_FLAT)
            && ObjectSetInteger(this.chartId, name, OBJPROP_COLOR, clrSlateGray)
            && ObjectSetInteger(this.chartId, name, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, name, OBJPROP_ZORDER, 20)
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
    void drawLabel(const string fromKey, const string fromText, const int fromX, const int fromY,
            const int fromSize, const color fromColor, const string fromTooltip, const long fromZOrder,
            const ENUM_ANCHOR_POINT fromAnchor = ANCHOR_LEFT_UPPER) {
        string name = this.prefix + fromKey;
        if (!this.createObject(name, OBJ_LABEL)) {
            return;
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
