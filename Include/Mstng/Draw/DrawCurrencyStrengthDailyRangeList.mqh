//+------------------------------------------------------------------+
//|                         DrawCurrencyStrengthDailyRangeList.mqh    |
//+------------------------------------------------------------------+
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_DAILY_RANGE_LIST_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_DAILY_RANGE_LIST_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Strength\CurrencyStrengthDailyRangeList.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 当日の日足値幅を円換算順位・元pips・円換算pipsで14件ずつ表示する。
 * 市場データの取得は行わず、保持済み一覧の開閉・並び替え・ページ切替を担当する。
 */
class DrawCurrencyStrengthDailyRangeList {
public:
    /**
     * 表示位置と同一チャート内の識別子を指定する。
     *
     * @param fromChartId 対象チャートID。0はカレント。
     * @param fromXDistance 左端からの位置。
     * @param fromYDistance 上端からの位置。
     * @param fromInstanceKey 計算方式などの識別子。
     */
    DrawCurrencyStrengthDailyRangeList(
        const long fromChartId,
        const int fromXDistance,
        const int fromYDistance,
        const string fromInstanceKey = ""
    ) {
        this.chartId = fromChartId;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.created = false;
        this.collapsed = false;
        this.sortByJpy = true;
        this.pageIndex = 0;
        this.pageCount = 2;
        ArrayInitialize(this.cellValid, false);

        string basePrefix = Constant::PREFIX_FIXED + "CurrencyDailyRange_";
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
    ~DrawCurrencyStrengthDailyRangeList() {
        this.destroyObjects();
    }

    /**
     * 保持済みの値幅一覧を描画し、変更された文字・色・説明だけを反映する。
     * 折りたたみ中は一覧の参照も並び替えも行わない。
     *
     * @param fromList 表示用一覧。NULLは取得待ち。
     * @return 描画成功時true。
     */
    bool draw(CurrencyStrengthDailyRangeList *fromList) {
        bool changed = !this.created;
        if (!this.created && !this.create()) {
            return false;
        }

        if (this.collapsed) {
            if (changed) {
                DrawChartRedrawBatch::request(this.chartId);
            }

            return true;
        }

        int displayOrder[];
        int jpyRanks[];
        int total = this.buildDisplayOrder(fromList, displayOrder, jpyRanks);
        this.pageCount = 2;
        if (total > 0) {
            this.pageCount = (total + 13) / 14;
        }

        this.pageIndex = MathMax(0, MathMin(this.pageIndex, this.pageCount - 1));
        bool succeeded = true;
        for (int i = 0; i < 14; i++) {
            string rankText = " ";
            string pairText = " ";
            string pipsText = " ";
            string jpyText = " ";
            string tooltip = "\n";
            color pipsColor = clrSilver;
            color jpyColor = clrSilver;
            int sourceIndex = this.pageIndex * 14 + i;
            CurrencyStrengthDailyRangeInfo info;
            if (fromList != NULL && sourceIndex < total
                    && fromList.get(displayOrder[sourceIndex], info)) {
                rankText = "—";
                pairText = info.symbolName;
                pipsText = "—";
                jpyText = "—";
                if (info.rangeAvailable) {
                    pipsText = IntegerToString(info.pips);
                    pipsColor = clrWhiteSmoke;
                }

                if (info.jpyAvailable) {
                    jpyText = IntegerToString(info.jpyPips);
                    jpyColor = clrGold;
                }

                int rank = jpyRanks[displayOrder[sourceIndex]];
                if (rank > 0) {
                    rankText = IntegerToString(rank);
                }

                tooltip = this.getRowTooltip(info, rank);
            }

            if (!this.updateCell(i * 4, this.getRowName(i, "Rank"), rankText, clrSilver, tooltip, changed)
                    || !this.updateCell(i * 4 + 1, this.getRowName(i, "Pair"), pairText, clrWhiteSmoke, tooltip, changed)
                    || !this.updateCell(i * 4 + 2, this.getRowName(i, "Pips"), pipsText, pipsColor, tooltip, changed)
                    || !this.updateCell(i * 4 + 3, this.getRowName(i, "Jpy"), jpyText, jpyColor, tooltip, changed)) {
                succeeded = false;
            }
        }

        string sortText = "ペア順";
        if (this.sortByJpy) {
            sortText = "円換算順";
        }

        string updatedText = "更新：取得待ち";
        string updatedTooltip = "日足高値・安値はサーバーの日付区切りを使用します。";
        if (Util::isStrategyTester()) {
            updatedText = "通常チャート専用（取得対象外）";
        } else if (fromList != NULL && fromList.getUpdatedAt() > 0) {
            updatedText = "更新 " + TimeUtil::formatYyyymmddhhmiss(fromList.getUpdatedAt()) + " SRV";
        }

        if (!this.updateCell(56, this.objectPrefix + "SortButton", sortText, clrWhiteSmoke,
                "クリックして円換算pipsの大きい順／通貨ペアのアルファベット順を切替", changed)
                || !this.updateCell(57, this.objectPrefix + "Page",
                    IntegerToString(this.pageIndex + 1) + " / " + IntegerToString(this.pageCount),
                    clrWhiteSmoke, "14件ずつ表示", changed)
                || !this.updateCell(58, this.objectPrefix + "Updated", updatedText,
                    clrSilver, updatedTooltip, changed)) {
            succeeded = false;
        }

        if (changed) {
            DrawChartRedrawBatch::request(this.chartId);
        }

        return succeeded;
    }

    /**
     * 見出し・並び順・ページの操作を保持する。再描画は呼び出し側で行う。
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
                && StringFind(fromName, Constant::PREFIX_FIXED + "CurrencyDailyRange_") == 0) {
            int nameLength = StringLen(fromName);
            isTitle = StringSubstr(fromName, nameLength - StringLen("_Title")) == "_Title"
                || StringSubstr(fromName, nameLength - StringLen("_TitleBackground")) == "_TitleBackground";
        }

        if (isTitle) {
            this.setCollapsed(!this.collapsed);

            return true;
        }

        if (this.collapsed) {
            return false;
        }

        if (fromName == this.objectPrefix + "SortButton") {
            ObjectSetInteger(this.chartId, fromName, OBJPROP_STATE, false);
            this.setSortByJpy(!this.sortByJpy);
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
     * 開閉状態を変更し、次回描画で再生成する。
     */
    void setCollapsed(const bool fromCollapsed) {
        if (this.collapsed == fromCollapsed) {
            return;
        }

        this.collapsed = fromCollapsed;
        this.destroyObjects();
    }

    /**
     * 円換算pipsの降順の場合trueを返す。
     */
    bool isSortByJpy() const {
        return this.sortByJpy;
    }

    /**
     * 並び順を変更し、最初のページへ戻す。
     */
    void setSortByJpy(const bool fromSortByJpy) {
        if (this.sortByJpy == fromSortByJpy) {
            return;
        }

        this.sortByJpy = fromSortByJpy;
        this.pageIndex = 0;
    }

    /**
     * 開閉状態に応じた幅を返す。
     */
    int getPanelWidth() const {
        if (this.collapsed) {
            return 200;
        }

        return 300;
    }

    /**
     * 左位置を変更する。
     * 同位置の場合は再生成せず、並び順・ページ・開閉状態を維持する。
     */
    bool setXDistance(const int fromXDistance) {
        return this.setPosition(fromXDistance, this.yDistance);
    }

    /**
     * スコア表の直下へ配置し、同位置の場合は再生成しない。
     * 並び順・ページ・開閉状態を維持する。
     *
     * @param fromXDistance 左端の位置。
     * @param fromYDistance 上端の位置。
     * @return 位置を反映した場合true。
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
        string familyPrefix = Constant::PREFIX_FIXED + "CurrencyDailyRange_";
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
     * 表示オブジェクトを削除し、開閉・並び順・ページは保持する。
     */
    void clear() {
        this.destroyObjects();
        DrawChartRedrawBatch::request(this.chartId);
    }

private:
    /** 対象チャートID。 */
    long chartId;

    /** 所有オブジェクト名の接頭辞。 */
    string objectPrefix;

    /** 左端の位置。 */
    int xDistance;

    /** 上端の位置。 */
    int yDistance;

    /** 所有オブジェクトを生成済みの場合true。 */
    bool created;

    /** 見出しだけを表示する場合true。 */
    bool collapsed;

    /** 円換算pipsの降順の場合true。 */
    bool sortByJpy;

    /** 表示中のページ番号。0始まり。 */
    int pageIndex;

    /** 保持中の表示ページ数。 */
    int pageCount;

    /** セル・操作ラベルへ反映済みの文字。 */
    string cellTexts[59];

    /** セル・操作ラベルへ反映済みの文字色。 */
    color cellColors[59];

    /** セル・操作ラベルへ反映済みの説明。 */
    string cellTooltips[59];

    /** 各セルの反映値が有効な場合true。 */
    bool cellValid[59];

    /**
     * 固定部分と空のセルを生成する。
     */
    bool create() {
        this.destroyObjects();
        int panelHeight = 384;
        string titleText = "▼ 日足値幅";
        string titleTooltip = "クリックして日足値幅一覧を閉じる";
        if (this.collapsed) {
            panelHeight = 27;
            titleText = "▶ 日足値幅";
            titleTooltip = "クリックして日足値幅一覧を開く";
        }

        if (!this.createRectangle("Panel", 0, 0, this.getPanelWidth(), panelHeight, C'18,18,18', clrDimGray, 0)
                || !this.createRectangle("TitleBackground", 1, 1, this.getPanelWidth() - 2, 25,
                    C'56,74,104', C'56,74,104', 1)
                || !this.createLabel("Title", 14, 5, 11, clrWhite, titleText, false)
                || !ObjectSetString(this.chartId, this.objectPrefix + "Title", OBJPROP_TOOLTIP, titleTooltip)
                || !ObjectSetString(this.chartId, this.objectPrefix + "TitleBackground", OBJPROP_TOOLTIP, titleTooltip)) {
            this.destroyObjects();

            return false;
        }

        if (this.collapsed) {
            this.created = true;

            return true;
        }

        if (!this.createButton("SortButton", 14, 31, 100, "円換算順")
                || !this.createButton("PreviousButton", 174, 31, 24, "<")
                || !this.createButton("NextButton", 266, 31, 24, ">")
                || !this.createLabel("Page", 254, 34, 9, clrWhiteSmoke, "1 / 2", true)
                || !this.createLabel("HeaderRank", 32, 58, 9, clrSilver, "NO", true)
                || !this.createLabel("HeaderPair", 44, 58, 9, clrSilver, "通貨ペア", false)
                || !this.createLabel("HeaderPips", 195, 58, 9, clrSilver, "元pips", true)
                || !this.createLabel("HeaderJpy", 286, 58, 9, clrGold, "円換算pips", true)
                || !this.createRectangle("Separator", 12, 73, 276, 1, clrDimGray, clrDimGray, 0)
                || !this.createLabel("Footer", 14, 343, 8, clrSilver, "当日D1 高値−安値（SRV基準）", false)
                || !this.createLabel("Updated", 14, 361, 8, clrSilver, "更新：取得待ち", false)) {
            this.destroyObjects();

            return false;
        }

        string comparisonTooltip = "円換算pipsは円建て1pip＝0.01円を基準にそろえた比較値です。取引損益額ではありません。";
        if (!ObjectSetString(this.chartId, this.objectPrefix + "HeaderRank", OBJPROP_TOOLTIP,
                "全28通貨ペアの円換算pips順位。ペア順でも同じ順位を表示。同値は同順位（1・2・2・4）、未取得は—。")
                || !ObjectSetString(this.chartId, this.objectPrefix + "HeaderJpy", OBJPROP_TOOLTIP, comparisonTooltip)
                || !ObjectSetString(this.chartId, this.objectPrefix + "Footer", OBJPROP_TOOLTIP, comparisonTooltip)
                || !ObjectSetString(this.chartId, this.objectPrefix + "PreviousButton", OBJPROP_TOOLTIP, "前の14件")
                || !ObjectSetString(this.chartId, this.objectPrefix + "NextButton", OBJPROP_TOOLTIP, "次の14件")) {
            this.destroyObjects();

            return false;
        }

        for (int i = 0; i < 14; i++) {
            int rowTop = 80 + i * 18;
            string rowPrefix = "Row_" + IntegerToString(i) + "_";
            if (!this.createLabel(rowPrefix + "Rank", 32, rowTop, 10, clrSilver, " ", true)
                    || !this.createLabel(rowPrefix + "Pair", 44, rowTop, 10, clrWhiteSmoke, " ", false)
                    || !this.createLabel(rowPrefix + "Pips", 195, rowTop, 10, clrWhiteSmoke, " ", true)
                    || !this.createLabel(rowPrefix + "Jpy", 286, rowTop, 10, clrGold, " ", true)) {
                this.destroyObjects();

                return false;
            }
        }

        this.created = true;

        return true;
    }

    /**
     * 固定背景を生成する。
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
     * 固定位置・フォントの文字ラベルを生成する。
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
     * 押下状態を残さない操作ボタンを生成する。
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
     * 作成時だけ共通属性を設定する。
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
     * 反映済み値と異なる項目だけを設定する。失敗したセルは次回再試行する。
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
     * 全28件の表示順と円換算順位を作る。円換算不明は末尾、同値は通貨ペア名で固定する。
     * 順位は表示順と独立し、同値は同順位、次の順位は同順位件数分を飛ばす。
     *
     * @param fromList 保持中の日足値幅一覧。
     * @param fromOrder 表示順に並べた元データ位置。
     * @param fromRanks 元データ位置ごとの円換算順位。未取得は0。
     * @return 表示対象件数。
     */
    int buildDisplayOrder(CurrencyStrengthDailyRangeList *fromList, int &fromOrder[], int &fromRanks[]) {
        ArrayResize(fromOrder, 0);
        ArrayResize(fromRanks, 0);
        if (fromList == NULL) {
            return 0;
        }

        int total = MathMin(28, fromList.size());
        string names[28];
        bool available[28];
        int values[28];
        if (total <= 0 || ArrayResize(fromOrder, total) != total
                || ArrayResize(fromRanks, total) != total) {
            return 0;
        }

        for (int i = 0; i < total; i++) {
            fromOrder[i] = i;
            fromRanks[i] = 0;
            CurrencyStrengthDailyRangeInfo info;
            names[i] = "";
            available[i] = false;
            values[i] = 0;
            if (fromList.get(i, info)) {
                names[i] = info.symbolName;
                available[i] = info.jpyAvailable;
                values[i] = info.jpyPips;
            }
        }

        // 表示ページや並び順によらず、取得済みの全ペアを同じ整数pipsで比較する。
        for (int i = 0; i < total; i++) {
            if (!available[i]) {
                continue;
            }

            int rank = 1;
            for (int j = 0; j < total; j++) {
                if (available[j] && values[j] > values[i]) {
                    rank++;
                }
            }

            fromRanks[i] = rank;
        }

        for (int i = 1; i < total; i++) {
            int source = fromOrder[i];
            int j = i - 1;
            while (j >= 0) {
                int previous = fromOrder[j];
                bool precedes = StringCompare(names[source], names[previous]) < 0;
                if (this.sortByJpy && available[source] != available[previous]) {
                    precedes = available[source];
                } else if (this.sortByJpy && available[source] && values[source] != values[previous]) {
                    precedes = values[source] > values[previous];
                }

                if (!precedes) {
                    break;
                }

                fromOrder[j + 1] = previous;
                j--;
            }

            fromOrder[j + 1] = source;
        }

        return total;
    }

    /**
     * 円換算順位、元値幅と換算に使った値・時刻を説明する。
     */
    string getRowTooltip(const CurrencyStrengthDailyRangeInfo &fromInfo, const int fromRank) {
        string text = fromInfo.symbolName;
        if (fromInfo.resolvedSymbolName != "" && fromInfo.resolvedSymbolName != fromInfo.symbolName) {
            text += "（" + fromInfo.resolvedSymbolName + "）";
        }

        if (fromRank > 0) {
            text += "\n円換算順位：" + IntegerToString(fromRank) + "位（全28ペア・同値は同順位）";
        } else {
            text += "\n円換算順位：—（取得待ち）";
        }

        text += "\n日足開始：" + this.formatTime(fromInfo.dayTime);
        if (fromInfo.rangeAvailable) {
            text += "\n高値：" + DoubleToString(fromInfo.high, fromInfo.digits)
                + " / 安値：" + DoubleToString(fromInfo.low, fromInfo.digits)
                + "\n元値幅：" + IntegerToString(fromInfo.pips) + " pips";
        } else {
            text += "\n元値幅：—（日足取得待ち）";
        }

        if (!fromInfo.jpyAvailable) {
            text += "\n円換算：—（取得待ち）";
        } else if (StringSubstr(fromInfo.symbolName, 3, 3) == "JPY") {
            text += "\n円換算：" + IntegerToString(fromInfo.jpyPips) + " pips（JPY建てのため元値幅と同じ）";
        } else {
            text += "\n円換算：" + IntegerToString(fromInfo.jpyPips) + " pips"
                + "\n換算レート：" + fromInfo.conversionSymbolName
                + " Bid " + DoubleToString(fromInfo.conversionRate, 6);
            if (fromInfo.inverseConversion) {
                text += "（逆通貨ペアで除算）";
            }

            text += "\n換算気配：" + this.formatTime(fromInfo.conversionTime);
        }

        text += "\n更新：" + this.formatTime(fromInfo.updatedAt)
            + "\n円建て1pip＝0.01円基準の比較値。取引損益額ではありません。";

        return text;
    }

    /**
     * 未取得を区別してサーバー時刻を整形する。
     */
    string formatTime(const datetime fromTime) {
        if (fromTime <= 0) {
            return "—（取得待ち）";
        }

        return TimeUtil::formatYyyymmddhhmiss(fromTime) + " SRV";
    }

    /**
     * 行・列に対応するオブジェクト名を返す。
     */
    string getRowName(const int fromRow, const string fromColumn) {
        return this.objectPrefix + "Row_" + IntegerToString(fromRow) + "_" + fromColumn;
    }

    /**
     * 途中生成分も含めて所有オブジェクトと反映キャッシュを無効化する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        ArrayInitialize(this.cellValid, false);
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_DAILY_RANGE_LIST_MQH
