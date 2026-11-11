//+------------------------------------------------------------------+
//|                              DrawEconomicCalendarSchedule.mqh    |
//+------------------------------------------------------------------+
#property strict

#ifndef MSTNG_DRAW_ECONOMIC_CALENDAR_SCHEDULE_MQH
#define MSTNG_DRAW_ECONOMIC_CALENDAR_SCHEDULE_MQH

#include <Mstng\Calendar\EconomicCalendarSchedule.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 保持済みの経済指標予定を、日足値幅の右隣へ8件ずつ表示する。
 * カレンダー取得は行わず、重要度・開閉・ページ・残り時間の表示だけを担当する。
 */
class DrawEconomicCalendarSchedule {
public:
    /**
     * 対象チャートと表示位置を保持する。
     *
     * @param fromChartId 対象チャートID。0はカレント。
     * @param fromXDistance 左端位置。
     * @param fromYDistance 上端位置。
     * @param fromInstanceKey 同一チャート内の識別子。
     */
    DrawEconomicCalendarSchedule(const long fromChartId, const int fromXDistance,
            const int fromYDistance, const string fromInstanceKey = "") {
        this.chartId = fromChartId;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.created = false;
        this.collapsed = false;
        this.includeModerate = false;
        this.modeButtonsValid = false;
        this.appliedIncludeModerate = false;
        this.pageIndex = 0;
        this.pageCount = 1;
        ArrayInitialize(this.cellValid, false);
        ArrayInitialize(this.nameValid, false);

        string basePrefix = Constant::PREFIX_FIXED + "EconomicCalendar_";
        if (fromInstanceKey != "") {
            basePrefix += StringSubstr(fromInstanceKey, 0, 12) + "_";
        }

        static int nextInstanceIndex = 0;
        int instanceIndex = nextInstanceIndex;
        this.objectPrefix = basePrefix + IntegerToString(instanceIndex) + "_";
        while (ObjectFind(this.chartId, this.objectPrefix + "Panel") >= 0
                || ObjectFind(this.chartId, this.objectPrefix + "Title") >= 0) {
            instanceIndex++;
            this.objectPrefix = basePrefix + IntegerToString(instanceIndex) + "_";
        }

        nextInstanceIndex = instanceIndex + 1;
    }

    /**
     * 所有する描画オブジェクトを解放する。
     */
    ~DrawEconomicCalendarSchedule() {
        this.destroyObjects();
    }

    /**
     * 保持済み予定を参照し、文字・色・説明が変わった項目だけ反映する。
     * 折りたたみ中とテスターでは予定データを参照しない。
     *
     * @param fromSchedule 表示用の取得結果。NULLは取得待ち。
     * @return 描画に成功した場合true。
     */
    bool draw(EconomicCalendarSchedule *fromSchedule) {
        if (this.created && (ObjectFind(this.chartId, this.objectPrefix + "Panel") < 0
                || ObjectFind(this.chartId, this.objectPrefix + "Title") < 0)) {
            this.destroyObjects();
        }

        bool changed = !this.created;
        if (!this.created && !this.create()) {
            return false;
        }

        string titleTooltip = "クリックして経済指標予定を閉じる。確定時刻はJST、終日・時刻未定はSRV日付。";
        if (this.collapsed) {
            titleTooltip = "クリックして経済指標予定を開く";
        }

        bool succeeded = this.updateCell(40, this.objectPrefix + "Title", this.getTitleText(),
            clrWhite, titleTooltip, changed);
        if (this.collapsed) {
            if (!succeeded) {
                this.destroyObjects();
                changed = true;
            }

            if (changed) {
                DrawChartRedrawBatch::request(this.chartId);
            }

            return succeeded;
        }

        bool isTester = Util::isStrategyTester();
        bool hasSnapshot = false;
        bool hasError = false;
        datetime serverNow = 0;
        datetime japanNow = 0;
        int total = 0;
        if (!isTester && fromSchedule != NULL) {
            serverNow = fromSchedule.getServerNow();
            japanNow = fromSchedule.getJapanTime(serverNow);
            hasSnapshot = fromSchedule.hasSnapshot();
            hasError = fromSchedule.hasError();
            if (hasSnapshot) {
                total = fromSchedule.getCount(this.includeModerate, serverNow);
            }
        }

        this.pageCount = MathMax(1, (total + 7) / 8);
        this.pageIndex = MathMax(0, MathMin(this.pageIndex, this.pageCount - 1));
        for (int i = 0; i < 8; i++) {
            EconomicCalendarScheduleInfo info;
            int sourceIndex = this.pageIndex * 8 + i;
            bool hasRow = false;
            if (hasSnapshot && fromSchedule != NULL && sourceIndex < total) {
                hasRow = fromSchedule.get(sourceIndex, this.includeModerate, serverNow, info);
            }

            if (!this.drawRow(i, hasRow, info, serverNow, japanNow, changed)) {
                succeeded = false;
            }
        }

        string status = "取得待ち";
        string statusTooltip = "MT5の経済指標カレンダーを取得すると表示します。";
        color statusColor = clrSilver;
        string updated = "更新：取得待ち";
        string updatedTooltip = "更新は通常5分間隔。表示と残り時間は保持データから更新します。";
        if (isTester) {
            status = "通常チャート専用";
            statusTooltip = "テスターでは現在の経済指標予定を取得・表示しません。";
            updated = "テスター：取得対象外";
        } else if (fromSchedule != NULL) {
            if (hasSnapshot) {
                status = IntegerToString(total) + "件・発表予定順";
                if (total == 0) {
                    status = "対象の予定なし";
                }

                statusTooltip = "今後24時間・主要8通貨。終日・未定は当日分を含みます。"
                    + "\n通貨・★：予想/前回、時刻：SRV/JST、指標名：全文/国。";
                datetime updatedJapanTime = fromSchedule.getJapanTime(fromSchedule.getUpdatedAt());
                if (updatedJapanTime > 0) {
                    updated = "更新 " + TimeUtil::formatYyyymmddhhmiss(updatedJapanTime) + " JST";
                }
            }

            if (hasError) {
                status = "取得失敗";
                if (hasSnapshot) {
                    status = "取得失敗・前回データ表示";
                }

                statusColor = clrOrange;
                statusTooltip = "カレンダー取得失敗。error=" + IntegerToString(fromSchedule.getLastError())
                    + "。前回取得済みの予定がある場合は、その内容を保持しています。";
                updatedTooltip = statusTooltip;
            }
        }

        if (!this.updateModeButtons(changed)
                || !this.updateCell(43, this.objectPrefix + "Page",
                    IntegerToString(this.pageIndex + 1) + "/" + IntegerToString(this.pageCount),
                    clrWhiteSmoke, "前後の8件へ切り替えます", changed)
                || !this.updateCell(44, this.objectPrefix + "Status", status,
                    statusColor, statusTooltip, changed)
                || !this.updateCell(45, this.objectPrefix + "Updated", updated,
                    statusColor, updatedTooltip, changed)) {
            succeeded = false;
        }

        if (!succeeded) {
            this.destroyObjects();
            changed = true;
        }

        if (changed) {
            DrawChartRedrawBatch::request(this.chartId);
        }

        return succeeded;
    }

    /**
     * 開閉・重要度・ページのクリックを処理する。再描画は呼び出し側で行う。
     *
     * @param fromName クリックされたオブジェクト名。
     * @param fromAllowOtherInstances 単独配置確認後に旧描画を除去した直後のみtrue。
     * @return このパネルの操作を処理した場合true。
     */
    bool handleObjectClick(const string fromName, const bool fromAllowOtherInstances = false) {
        if (!this.created) {
            return false;
        }

        bool isTitle = fromName == this.objectPrefix + "Title"
            || fromName == this.objectPrefix + "TitleBackground";
        if (!isTitle && fromAllowOtherInstances
                && StringFind(fromName, Constant::PREFIX_FIXED + "EconomicCalendar_") == 0) {
            int length = StringLen(fromName);
            isTitle = (length >= 6 && StringSubstr(fromName, length - 6) == "_Title")
                || (length >= 16 && StringSubstr(fromName, length - 16) == "_TitleBackground");
        }

        if (isTitle) {
            this.setCollapsed(!this.collapsed);

            return true;
        }

        if (this.collapsed) {
            return false;
        }

        if (fromName == this.objectPrefix + "HighButton") {
            ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
            this.setIncludeModerate(false);
        } else if (fromName == this.objectPrefix + "ModerateButton") {
            ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
            this.setIncludeModerate(true);
        } else if (fromName == this.objectPrefix + "PreviousButton") {
            ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
            this.pageIndex = MathMax(0, this.pageIndex - 1);
        } else if (fromName == this.objectPrefix + "NextButton") {
            ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
            this.pageIndex = MathMin(this.pageCount - 1, this.pageIndex + 1);
        } else {
            return false;
        }

        DrawChartRedrawBatch::request(this.chartId);

        return true;
    }

    /**
     * 折りたたみ状態を取得する。
     */
    bool isCollapsed() const {
        return this.collapsed;
    }

    /**
     * 開閉を変更し、次回描画で再生成する。ページと重要度は保持する。
     */
    void setCollapsed(const bool fromCollapsed) {
        if (this.collapsed == fromCollapsed) {
            return;
        }

        this.collapsed = fromCollapsed;
        this.destroyObjects();
    }

    /**
     * 中重要度も含める場合trueを返す。
     */
    bool isIncludeModerate() const {
        return this.includeModerate;
    }

    /**
     * 重要度を変更し、最初のページへ戻す。データは再取得しない。
     */
    void setIncludeModerate(const bool fromIncludeModerate) {
        if (this.includeModerate == fromIncludeModerate) {
            return;
        }

        this.includeModerate = fromIncludeModerate;
        this.pageIndex = 0;
    }

    /**
     * 日足値幅の右に収まる固定幅を返す。
     */
    int getPanelWidth() const {
        return 220;
    }

    /**
     * 開閉状態に応じた高さを返す。
     */
    int getPanelHeight() const {
        if (this.collapsed) {
            return 27;
        }

        return 384;
    }

    /**
     * 日足値幅の位置へ追従する。同位置では再生成しない。
     *
     * @param fromXDistance 左端位置。
     * @param fromYDistance 上端位置。
     * @return 位置を保持した場合true。
     */
    bool setPosition(const int fromXDistance, const int fromYDistance) {
        if (this.xDistance == fromXDistance && this.yDistance == fromYDistance) {
            return true;
        }

        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.destroyObjects();

        return true;
    }

    /**
     * 単独配置を確認済みの呼び出し側から、保存チャート由来の旧描画だけを除去する。
     *
     * @return 現在の所有描画を除く同系統オブジェクトの整理に成功した場合true。
     */
    bool clearOtherInstances() {
        string familyPrefix = Constant::PREFIX_FIXED + "EconomicCalendar_";
        int total = ObjectsTotal(this.chartId, 0, -1);
        if (total < 0) {
            return false;
        }

        bool succeeded = true;
        bool changed = false;
        for (int i = total - 1; i >= 0; i--) {
            string objectName = ObjectName(this.chartId, i, 0, -1);
            if (objectName == "") {
                succeeded = false;
                continue;
            }

            if (StringFind(objectName, familyPrefix) != 0
                    || StringFind(objectName, this.objectPrefix) == 0) {
                continue;
            }

            if (ObjectDelete(this.chartId, objectName)) {
                changed = true;
            } else {
                succeeded = false;
            }
        }

        if (changed) {
            DrawChartRedrawBatch::request(this.chartId);
        }

        return succeeded;
    }

    /**
     * 所有描画を消去する。開閉・重要度・ページは保持する。
     */
    void clear() {
        this.destroyObjects();
        DrawChartRedrawBatch::request(this.chartId);
    }

private:
    /** 対象チャートID。 */
    long chartId;

    /** 現在の所有オブジェクト接頭辞。 */
    string objectPrefix;

    /** 左端位置。 */
    int xDistance;

    /** 上端位置。 */
    int yDistance;

    /** 所有描画を作成済みの場合true。 */
    bool created;

    /** 見出しだけを表示する場合true。 */
    bool collapsed;

    /** 中重要度を含める場合true。 */
    bool includeModerate;

    /** 重要度ボタンの背景色を反映済みの場合true。 */
    bool modeButtonsValid;

    /** 反映済みの重要度条件。 */
    bool appliedIncludeModerate;

    /** 0始まりの表示ページ。 */
    int pageIndex;

    /** 表示ページ数。 */
    int pageCount;

    /** セルごとの反映キャッシュが有効な場合true。 */
    bool cellValid[46];

    /** 反映済み文字列。 */
    string cellTexts[46];

    /** 反映済み文字色。 */
    color cellColors[46];

    /** 反映済み説明文。 */
    string cellTooltips[46];

    /** 行ごとの省略名キャッシュが有効な場合true。 */
    bool nameValid[8];

    /** 省略前の指標名。 */
    string sourceNames[8];

    /** 幅196px以内に収めた表示名。 */
    string displayNames[8];

    /**
     * 固定背景・見出し・空の行を生成する。
     */
    bool create() {
        this.destroyObjects();
        string titleTooltip = "クリックして経済指標予定を閉じる。確定時刻はJST、終日・時刻未定はSRV日付。";
        if (this.collapsed) {
            titleTooltip = "クリックして経済指標予定を開く";
        }

        if (!this.createRectangle("Panel", 0, 0, 220, this.getPanelHeight(), C'18,18,18', clrDimGray, 0)
                || !this.createRectangle("TitleBackground", 1, 1, 218, 25, C'56,74,104', C'56,74,104', 1)
                || !this.createLabel("Title", 12, 5, 10, clrWhite, this.getTitleText(), false)
                || !ObjectSetString(this.chartId, this.objectPrefix + "TitleBackground", OBJPROP_TOOLTIP, titleTooltip)) {
            this.destroyObjects();

            return false;
        }

        if (this.collapsed) {
            this.created = true;

            return true;
        }

        if (!this.createButton("HighButton", 12, 31, 36, "高")
                || !this.createButton("ModerateButton", 52, 31, 56, "中以上")
                || !this.createButton("PreviousButton", 120, 31, 20, "<")
                || !this.createButton("NextButton", 188, 31, 20, ">")
                || !this.createLabel("Page", 180, 35, 8, clrWhiteSmoke, "1/1", true)
                || !this.createLabel("Status", 12, 57, 8, clrSilver, "取得待ち", false)
                || !this.createRectangle("Separator", 12, 73, 196, 1, clrDimGray, clrDimGray, 0)
                || !this.createLabel("Updated", 12, 343, 8, clrSilver, "更新：取得待ち", false)
                || !this.createLabel("Footer", 12, 361, 8, clrSilver, "未定・終日：SRV日付", false)) {
            this.destroyObjects();

            return false;
        }

        if (!ObjectSetString(this.chartId, this.objectPrefix + "Footer", OBJPROP_TOOLTIP,
                "発表時刻が確定した予定はJSTです。終日・時刻未定の予定にはJSTへの時刻変換や残り時間を表示しません。")
                || !ObjectSetString(this.chartId, this.objectPrefix + "PreviousButton", OBJPROP_TOOLTIP, "前の8件")
                || !ObjectSetString(this.chartId, this.objectPrefix + "NextButton", OBJPROP_TOOLTIP, "次の8件")) {
            this.destroyObjects();

            return false;
        }

        for (int i = 0; i < 8; i++) {
            int rowTop = 79 + i * 32;
            string rowPrefix = "Row_" + IntegerToString(i) + "_";
            if (!this.createLabel(rowPrefix + "Time", 12, rowTop, 8, clrWhiteSmoke, " ", false)
                    || !this.createLabel(rowPrefix + "Currency", 82, rowTop, 8, clrWhiteSmoke, " ", false)
                    || !this.createLabel(rowPrefix + "Importance", 108, rowTop, 8, clrGold, " ", false)
                    || !this.createLabel(rowPrefix + "Countdown", 208, rowTop, 8, clrSilver, " ", true)
                    || !this.createLabel(rowPrefix + "Name", 12, rowTop + 14, 9, clrWhiteSmoke, " ", false)) {
                this.destroyObjects();

                return false;
            }
        }

        this.created = true;

        return true;
    }

    /**
     * 予定1件を2行へ反映する。予定がない行はすべての文字と説明を消す。
     */
    bool drawRow(const int fromRow, const bool fromHasRow, const EconomicCalendarScheduleInfo &fromInfo,
            const datetime fromServerNow, const datetime fromJapanNow, bool &fromChanged) {
        string timeText = " ";
        string currencyText = " ";
        string importanceText = " ";
        string countdownText = " ";
        string nameText = " ";
        string timeTooltip = "\n";
        string valuesTooltip = "\n";
        string nameTooltip = "\n";
        color currencyColor = clrSilver;
        color countdownColor = clrSilver;
        color importanceColor = clrGold;
        if (fromHasRow) {
            timeText = this.getTimeText(fromInfo, fromJapanNow);
            currencyText = fromInfo.currency;
            currencyColor = ConstantCurrency::getColor(fromInfo.currency);
            importanceText = "★★";
            if (fromInfo.importance == CALENDAR_IMPORTANCE_HIGH) {
                importanceText = "★★★";
                importanceColor = clrOrangeRed;
            }

            countdownText = this.getCountdownText(fromInfo, fromServerNow, countdownColor);
            nameText = this.getDisplayName(fromRow, fromInfo.name);
            nameTooltip = fromInfo.name + "\n" + fromInfo.country + " / " + fromInfo.currency;
            valuesTooltip = "予想：" + fromInfo.forecastText + "\n前回：" + fromInfo.previousText;
            if (fromInfo.timeMode == CALENDAR_TIMEMODE_DATETIME) {
                timeTooltip = "JST " + this.formatTime(fromInfo.japanTime)
                    + "\nSRV " + this.formatTime(fromInfo.serverTime);
            } else {
                timeTooltip = "SRV日付 " + this.formatDate(fromInfo.serverTime)
                    + "\n終日・時刻未定のためJST確定時刻と残り時間は表示しません。";
            }
        }

        bool succeeded = true;
        if (!this.updateCell(fromRow * 5, this.getRowName(fromRow, "Time"), timeText,
                clrWhiteSmoke, timeTooltip, fromChanged)) {
            succeeded = false;
        }

        if (!this.updateCell(fromRow * 5 + 1, this.getRowName(fromRow, "Currency"), currencyText,
                currencyColor, valuesTooltip, fromChanged)) {
            succeeded = false;
        }

        if (!this.updateCell(fromRow * 5 + 2, this.getRowName(fromRow, "Importance"), importanceText,
                importanceColor, valuesTooltip, fromChanged)) {
            succeeded = false;
        }

        if (!this.updateCell(fromRow * 5 + 3, this.getRowName(fromRow, "Countdown"), countdownText,
                countdownColor, timeTooltip, fromChanged)) {
            succeeded = false;
        }

        if (!this.updateCell(fromRow * 5 + 4, this.getRowName(fromRow, "Name"), nameText,
                clrWhiteSmoke, nameTooltip, fromChanged)) {
            succeeded = false;
        }

        return succeeded;
    }

    /**
     * 当日の確定時刻はHH:mm、日付が違う場合はMM/dd HH:mmで表示する。
     * 未定・終日はSRV日付のみを表示する。
     */
    string getTimeText(const EconomicCalendarScheduleInfo &fromInfo, const datetime fromJapanNow) {
        if (fromInfo.timeMode != CALENDAR_TIMEMODE_DATETIME) {
            if (fromInfo.serverTime <= 0) {
                return "日付未定";
            }

            return StringSubstr(this.formatDate(fromInfo.serverTime), 5) + " SRV";
        }

        if (fromInfo.japanTime <= 0) {
            return "—";
        }

        string formatted = TimeUtil::formatYyyymmddhhmiss(fromInfo.japanTime);
        if (fromJapanNow > 0 && this.formatDate(fromInfo.japanTime) == this.formatDate(fromJapanNow)) {
            return StringSubstr(formatted, 11, 5);
        }

        return StringSubstr(formatted, 5, 11);
    }

    /**
     * 確定時刻までの残り時間と注意色を返す。未定・終日には計算しない。
     */
    string getCountdownText(const EconomicCalendarScheduleInfo &fromInfo, const datetime fromNow,
            color &fromColor) {
        fromColor = clrSilver;
        if (fromInfo.timeMode != CALENDAR_TIMEMODE_DATETIME) {
            if (fromInfo.timeMode == CALENDAR_TIMEMODE_DATE) {
                return "終日";
            }

            return "時刻未定";
        }

        if (fromNow <= 0 || fromInfo.serverTime <= 0) {
            return "—";
        }

        long remainingSeconds = (long)fromInfo.serverTime - (long)fromNow;
        if (remainingSeconds <= 1800) {
            fromColor = clrOrangeRed;
        } else if (remainingSeconds <= 3600) {
            fromColor = clrGold;
        }

        if (remainingSeconds <= 0) {
            return "発表時刻";
        }

        long remainingMinutes = (remainingSeconds + 59) / 60;
        if (remainingMinutes < 60) {
            return StringFormat("あと%I64d分", remainingMinutes);
        }

        return StringFormat("あと%I64dh%02dm", remainingMinutes / 60, (int)(remainingMinutes % 60));
    }

    /**
     * 指標名が変わった行だけ幅を測り、196px以内へ省略する。
     */
    string getDisplayName(const int fromRow, const string fromName) {
        if (this.nameValid[fromRow] && this.sourceNames[fromRow] == fromName) {
            return this.displayNames[fromRow];
        }

        string cleanName = fromName;
        StringReplace(cleanName, "\r", " ");
        StringReplace(cleanName, "\n", " ");
        StringReplace(cleanName, "\t", " ");
        string result = cleanName;
        uint width = 0;
        uint height = 0;
        bool canMeasure = TextSetFont("MS Gothic", -90) && TextGetSize(cleanName, width, height);
        if (!canMeasure) {
            if (StringLen(cleanName) > 12) {
                result = StringSubstr(cleanName, 0, 12) + "…";
            }
        } else if (width > 196) {
            int lower = 0;
            int upper = StringLen(cleanName);
            while (lower < upper) {
                int middle = (lower + upper + 1) / 2;
                string candidate = StringSubstr(cleanName, 0, middle) + "…";
                if (TextGetSize(candidate, width, height) && width <= 196) {
                    lower = middle;
                } else {
                    upper = middle - 1;
                }
            }

            result = StringSubstr(cleanName, 0, lower) + "…";
        }

        this.sourceNames[fromRow] = fromName;
        this.displayNames[fromRow] = result;
        this.nameValid[fromRow] = true;

        return result;
    }

    /**
     * 重要度の選択状態が変わった場合だけ文字色と背景色を反映する。
     */
    bool updateModeButtons(bool &fromChanged) {
        color highColor = clrBlack;
        color moderateColor = clrWhiteSmoke;
        color highBackground = clrGold;
        color moderateBackground = C'45,45,45';
        if (this.includeModerate) {
            highColor = clrWhiteSmoke;
            moderateColor = clrBlack;
            highBackground = C'45,45,45';
            moderateBackground = clrGold;
        }

        if (!this.updateCell(41, this.objectPrefix + "HighButton", "高", highColor,
                "重要度が高い予定だけ表示", fromChanged)
                || !this.updateCell(42, this.objectPrefix + "ModerateButton", "中以上", moderateColor,
                    "重要度が中・高の予定を表示", fromChanged)) {
            return false;
        }

        if (!this.modeButtonsValid || this.appliedIncludeModerate != this.includeModerate) {
            if (!ObjectSetInteger(this.chartId, this.objectPrefix + "HighButton", OBJPROP_BGCOLOR, highBackground)
                    || !ObjectSetInteger(this.chartId, this.objectPrefix + "ModerateButton", OBJPROP_BGCOLOR, moderateBackground)) {
                this.modeButtonsValid = false;

                return false;
            }

            this.appliedIncludeModerate = this.includeModerate;
            this.modeButtonsValid = true;
            fromChanged = true;
        }

        return true;
    }

    /**
     * 反映済みの文字・色・説明と異なる項目だけ更新する。失敗時は再試行する。
     */
    bool updateCell(const int fromIndex, const string fromName, const string fromText,
            const color fromColor, const string fromTooltip, bool &fromChanged) {
        bool valid = this.cellValid[fromIndex];
        if (!valid || this.cellTexts[fromIndex] != fromText) {
            if (!ObjectSetString(this.chartId, fromName, OBJPROP_TEXT, fromText)) {
                this.cellValid[fromIndex] = false;

                return false;
            }

            this.cellTexts[fromIndex] = fromText;
            fromChanged = true;
        }

        if (!valid || this.cellColors[fromIndex] != fromColor) {
            if (!ObjectSetInteger(this.chartId, fromName, OBJPROP_COLOR, fromColor)) {
                this.cellValid[fromIndex] = false;

                return false;
            }

            this.cellColors[fromIndex] = fromColor;
            fromChanged = true;
        }

        if (!valid || this.cellTooltips[fromIndex] != fromTooltip) {
            if (!ObjectSetString(this.chartId, fromName, OBJPROP_TOOLTIP, fromTooltip)) {
                this.cellValid[fromIndex] = false;

                return false;
            }

            this.cellTooltips[fromIndex] = fromTooltip;
        }

        this.cellValid[fromIndex] = true;

        return true;
    }

    /**
     * 固定矩形を生成する。
     */
    bool createRectangle(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromWidth, const int fromHeight, const color fromBackground,
            const color fromBorder, const int fromZOrder) {
        string objectName = this.objectPrefix + fromSuffix;
        if (!ObjectCreate(this.chartId, objectName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        return this.configureObject(objectName, fromLeft, fromTop, fromZOrder)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, fromWidth)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, fromHeight)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, fromBackground)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromBorder)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    }

    /**
     * 文字ラベルを生成し、固定の書体・サイズ・アンカーを設定する。
     */
    bool createLabel(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromFontSize, const color fromColor, const string fromText, const bool fromRightAligned) {
        string objectName = this.objectPrefix + fromSuffix;
        if (!ObjectCreate(this.chartId, objectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
        if (fromRightAligned) {
            anchor = ANCHOR_RIGHT_UPPER;
        }

        return this.configureObject(objectName, fromLeft, fromTop, 2)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, anchor)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, fromFontSize)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor)
            && ObjectSetString(this.chartId, objectName, OBJPROP_FONT, "MS Gothic")
            && ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
    }

    /**
     * 押下状態を保持しない操作ボタンを生成する。
     */
    bool createButton(const string fromSuffix, const int fromLeft, const int fromTop,
            const int fromWidth, const string fromText) {
        string objectName = this.objectPrefix + fromSuffix;
        if (!ObjectCreate(this.chartId, objectName, OBJ_BUTTON, 0, 0, 0)) {
            return false;
        }

        return this.configureObject(objectName, fromLeft, fromTop, 3)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, fromWidth)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, 20)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, 9)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, clrWhiteSmoke)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, C'45,45,45')
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_COLOR, clrDimGray)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_STATE, false)
            && ObjectSetString(this.chartId, objectName, OBJPROP_FONT, "MS Gothic")
            && ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
    }

    /**
     * 作成時だけ位置・選択可否・クリック優先度などを設定する。
     */
    bool configureObject(const string fromName, const int fromLeft, const int fromTop, const int fromZOrder) {
        return ObjectSetInteger(this.chartId, fromName, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_XDISTANCE, this.xDistance + fromLeft)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_YDISTANCE, this.yDistance + fromTop)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_SELECTED, false)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(this.chartId, fromName, OBJPROP_ZORDER, fromZOrder)
            && ObjectSetString(this.chartId, fromName, OBJPROP_TOOLTIP, "\n");
    }

    /**
     * 開閉記号を含む見出し文字を返す。
     */
    string getTitleText() const {
        if (this.collapsed) {
            return "▶ 経済指標 JST";
        }

        return "▼ 経済指標 JST";
    }

    /**
     * 未取得と日時を区別して表示する。
     */
    string formatTime(const datetime fromTime) {
        if (fromTime <= 0) {
            return "—";
        }

        return TimeUtil::formatYyyymmddhhmiss(fromTime);
    }

    /**
     * タイムゾーン変換せず日付だけ表示する。
     */
    string formatDate(const datetime fromTime) {
        if (fromTime <= 0) {
            return "—";
        }

        return StringSubstr(TimeUtil::formatYyyymmddhhmiss(fromTime), 0, 10);
    }

    /**
     * 行・表示項目の専用オブジェクト名を返す。
     */
    string getRowName(const int fromRow, const string fromColumn) {
        return this.objectPrefix + "Row_" + IntegerToString(fromRow) + "_" + fromColumn;
    }

    /**
     * 部分生成分も含めて描画と反映キャッシュを消去する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.modeButtonsValid = false;
        ArrayInitialize(this.cellValid, false);
        ArrayInitialize(this.nameValid, false);
    }
};

#endif // MSTNG_DRAW_ECONOMIC_CALENDAR_SCHEDULE_MQH
