#ifndef MSTNG_DRAW_ELLIOT_PANEL_LAYOUT_MQH
#define MSTNG_DRAW_ELLIOT_PANEL_LAYOUT_MQH

/**
 * 現在・保存の共通パネルの寸法と各領域の配置を計算する。
 * チャート操作や表示状態を持たず、setChartSize成功後にcalculateで内容の配置を決定する。
 */
class ElliotPanelLayout {
public:
    /** パネル左端。 */
    int panelLeft;

    /** パネル上端。 */
    int panelTop;

    /** パネル幅。 */
    int panelWidth;

    /** パネル高さ。 */
    int panelHeight;

    /** 上下余白を除いた利用可能な高さ。 */
    int availableHeight;

    /** 一覧の行数。 */
    int rowCount;

    /** 選択行の追加指標数。 */
    int extraCount;

    /** 操作・日時を含むヘッダーの高さ。 */
    int headerHeight;

    /** 表の行高。 */
    int rowHeight;

    /** 表の上段見出しの高さ。 */
    int groupHeaderHeight;

    /** 詳細・追加指標の行高。 */
    int detailRowHeight;

    /** 詳細・追加指標の列数。 */
    int detailColumns;

    /** 一覧を表示できる場合true。 */
    bool showTable;

    /** 選択行の詳細を表示できる場合true。 */
    bool showDetails;

    /** 内容領域の左端。 */
    int contentLeft;

    /** 内容領域の幅。 */
    int contentWidth;

    /** 一覧見出しの上端。 */
    int tableTop;

    /** 詳細見出しの上端。 */
    int detailTop;

    /** 通貨強弱見出しの上端。 */
    int strengthTop;

    /** 追加指標見出しの上端。 */
    int extrasTop;

    /** 操作説明の上端。 */
    int hintTop;

    /** タイトルに使用できる幅。 */
    int titleWidth;

    /** 前後移動ボタンの上端。 */
    int navigationTop;

    /** 前後移動ボタンの左端。 */
    int navigationLeft;

    /** 前後移動ボタン一個分の幅。 */
    int navigationWidth;

    /** 閉じるボタンの左端。 */
    int closeLeft;

    /** 日時の上端。 */
    int timeTop;

    /** 補足情報の上端。 */
    int metadataTop;

    /** 詳細・追加指標一列分の幅。 */
    int detailItemWidth;

    /** 通貨強弱一列分の幅。 */
    int strengthItemWidth;

    /** 共通5列の相対横位置。 */
    int columnXs[5];

    /** 共通5列の幅。 */
    int columnWidths[5];

    /** GMMA2列の相対横位置。 */
    int gmmaColumnXs[2];

    /** GMMA2列の幅。 */
    int gmmaColumnWidths[2];

    /** 表の文字サイズ。 */
    int tableFontSize;

    /** Elliot欄を項目別表示する場合true。 */
    bool splitElliot;

    /**
     * チャート寸法から外枠を決め、選択状態を扱う前に最小サイズを確認する。
     *
     * @return パネルの最小幅・高さを確保できる場合true。
     */
    bool setChartSize(const int fromWidth, const int fromHeight) {
        this.panelLeft = 12;
        this.panelTop = 12;
        this.panelWidth = MathMin(960, fromWidth - 24);
        this.availableHeight = fromHeight - 24;

        return this.panelWidth >= 160 && this.availableHeight >= 80;
    }

    /**
     * 行数と展開状態から、表示可否・行高・各領域の配置を計算する。
     *
     * @param fromRowCount 一覧の行数。0から8へ制限する。
     * @param fromHasSelection 選択行が存在する場合true。
     * @param fromExtraCount 選択行の追加指標数。0から8へ制限する。
     * @param fromExpanded 詳細を展開する場合true。
     */
    void calculate(const int fromRowCount, const bool fromHasSelection,
            const int fromExtraCount, const bool fromExpanded) {
        this.rowCount = MathMax(0, MathMin(8, fromRowCount));
        this.headerHeight = 80;
        if (this.panelWidth < 760) {
            this.headerHeight = 104;
        }

        this.rowHeight = 24;
        this.groupHeaderHeight = 20;
        this.detailRowHeight = 22;
        this.detailColumns = 3;
        if (this.panelWidth < 960) {
            this.detailColumns = 2;
        }

        this.extraCount = 0;
        if (fromHasSelection) {
            this.extraCount = MathMax(0, MathMin(8, fromExtraCount));
        }

        int extraRows = (this.extraCount + this.detailColumns - 1) / this.detailColumns;
        int detailHeight = 28 + (12 / this.detailColumns) * this.detailRowHeight + 82;
        if (this.extraCount > 0) {
            detailHeight += 20 + extraRows * this.detailRowHeight;
        }

        int listHeight = this.headerHeight + this.groupHeaderHeight + (this.rowCount + 1) * this.rowHeight + 26;
        if (fromExpanded && listHeight + detailHeight > this.availableHeight) {
            this.rowHeight = 20;
            this.detailRowHeight = 18;
            detailHeight = 26 + (12 / this.detailColumns) * this.detailRowHeight + 76;
            if (this.extraCount > 0) {
                detailHeight += 20 + extraRows * this.detailRowHeight;
            }

            listHeight = this.headerHeight + this.groupHeaderHeight + (this.rowCount + 1) * this.rowHeight + 26;
        }

        this.showDetails = fromExpanded && fromHasSelection
            && listHeight + detailHeight <= this.availableHeight && this.panelWidth >= 640;
        int desiredHeight = listHeight;
        if (this.showDetails) {
            desiredHeight += detailHeight;
        }

        this.panelHeight = MathMin(this.availableHeight, MathMax(140, desiredHeight));
        int requiredListHeight = this.headerHeight + this.groupHeaderHeight + (this.rowCount + 1) * this.rowHeight + 24;
        this.showTable = this.rowCount > 0 && this.panelWidth >= 640 && requiredListHeight <= this.panelHeight;

        this.contentLeft = this.panelLeft + 12;
        this.contentWidth = this.panelWidth - 24;
        this.tableTop = this.panelTop + this.headerHeight;
        this.detailTop = this.tableTop + this.groupHeaderHeight + (this.rowCount + 1) * this.rowHeight + 8;
        this.strengthTop = this.detailTop + 24 + (12 / this.detailColumns) * this.detailRowHeight;
        this.extrasTop = this.strengthTop + 76;
        this.hintTop = this.panelTop + this.panelHeight - 20;
        this.detailItemWidth = this.contentWidth / this.detailColumns;
        this.strengthItemWidth = MathMin(620, this.contentWidth) / 5;

        this.calculateHeader();
        this.calculateTable();
    }

    /**
     * 閉じる・展開ボタンの上端を返す。
     */
    int getButtonTop() const { return this.panelTop + 6; }

    /**
     * タイトルの上端を返す。
     */
    int getTitleTop() const { return this.panelTop + 9; }

    /**
     * 展開ボタンの左端を返す。
     */
    int getExpandLeft() const { return this.closeLeft - 86; }

    /**
     * 次・現在へボタンの左端を返す。前ボタンを0とする。
     */
    int getNavigationLeft(const int fromIndex) const { return this.navigationLeft + fromIndex * (this.navigationWidth + 6); }

    /**
     * 空データ・サイズ不足メッセージの上端を返す。
     */
    int getMessageTop() const { return this.tableTop + 6; }

    /**
     * 上下2段の見出しを除いた一覧行の上端を返す。
     */
    int getTableRowTop(const int fromIndex) const { return this.tableTop + this.groupHeaderHeight + (fromIndex + 1) * this.rowHeight; }

    /**
     * 詳細・追加指標の項目左端を返す。
     */
    int getDetailLeft(const int fromIndex) const { return this.contentLeft + (fromIndex % this.detailColumns) * this.detailItemWidth; }

    /**
     * 詳細値・追加指標値の左端を返す。
     */
    int getDetailValueLeft(const int fromIndex) const { return this.getDetailLeft(fromIndex) + 104; }

    /**
     * 詳細値・追加指標値の幅を返す。
     */
    int getDetailValueWidth() const { return this.detailItemWidth - 112; }

    /**
     * 詳細項目の上端を返す。
     */
    int getDetailRowTop(const int fromIndex) const { return this.detailTop + 24 + (fromIndex / this.detailColumns) * this.detailRowHeight; }

    /**
     * 追加指標の上端を返す。
     */
    int getExtraRowTop(const int fromIndex) const { return this.extrasTop + 20 + (fromIndex / this.detailColumns) * this.detailRowHeight; }

    /**
     * 通貨強弱の列左端を返す。
     */
    int getStrengthLeft(const int fromIndex) const { return this.contentLeft + fromIndex * this.strengthItemWidth; }

    /**
     * 通貨強弱の列内で使用できる文字幅を返す。
     */
    int getStrengthTextWidth() const { return this.strengthItemWidth - 6; }

    /**
     * 通貨強弱の取得状態の上端を返す。
     */
    int getStrengthStatusTop() const { return this.strengthTop + 24; }

    /**
     * 通貨強弱の列見出しの上端を返す。
     */
    int getStrengthHeaderTop() const { return this.strengthTop + 20; }

    /**
     * 通貨強弱の長中期・中短期の行上端を返す。
     */
    int getStrengthRowTop(const int fromIndex) const { return this.strengthTop + 38 + fromIndex * 18; }

private:
    /**
     * 幅に応じてタイトル・操作ボタン・日時を一段または二段へ配置する。
     */
    void calculateHeader() {
        this.navigationTop = this.panelTop + 6;
        this.titleWidth = this.panelWidth - 390;
        this.timeTop = this.panelTop + 32;
        this.metadataTop = this.panelTop + 58;
        this.closeLeft = this.panelLeft + this.panelWidth - 34;
        this.navigationLeft = this.closeLeft - 86 - 230;
        if (this.headerHeight > 80) {
            this.titleWidth = this.panelWidth - 140;
            this.navigationTop = this.panelTop + 32;
            this.timeTop = this.panelTop + 60;
            this.metadataTop = this.panelTop + 82;
            this.navigationLeft = this.panelLeft + 12;
        }

        this.navigationWidth = MathMax(20, MathMin(60, (this.panelWidth - 114) / 2));
    }

    /**
     * 値動き・GMMA・Elliotの列幅と表の文字サイズを決定する。
     */
    void calculateTable() {
        this.splitElliot = this.panelWidth >= 960;
        this.tableFontSize = 11;
        if (this.rowHeight < 24) {
            this.tableFontSize = 10;
        }

        int widths[] = {64, 64, 64, 96, this.panelWidth - 424};
        int positionX = 0;
        for (int i = 0; i < 5; i++) {
            if (i == 4) {
                positionX += 112;
            }

            this.columnXs[i] = positionX;
            this.columnWidths[i] = widths[i];
            positionX += widths[i];
        }

        this.gmmaColumnXs[0] = this.columnXs[3] + this.columnWidths[3];
        this.gmmaColumnWidths[0] = 56;
        this.gmmaColumnXs[1] = this.gmmaColumnXs[0] + this.gmmaColumnWidths[0];
        this.gmmaColumnWidths[1] = 56;
    }
};

#endif // MSTNG_DRAW_ELLIOT_PANEL_LAYOUT_MQH
