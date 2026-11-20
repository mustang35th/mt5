#ifndef MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_SORT_COMBO_MQH
#define MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_SORT_COMBO_MQH

#include <Controls\ComboBox.mqh>

/**
 * 標準コンボボックスの通知を監視パネル内へ限定し、選択と外側クリックを管理する。
 * ソート設定や監視対象は変更せず、利用者の選択だけを呼び出し元へ返す。
 */
class DrawZigZagElliotMonitorSortCombo : public CComboBox {
public:
    /**
     * 未作成状態で準備する。
     */
    DrawZigZagElliotMonitorSortCombo() {
        this.created = false;
        this.attempted = false;
        this.layoutDirty = false;
        this.mouseMoveOwned = false;
        this.synchronizing = false;
        this.selectionPending = false;
        this.mouseDown = false;
        this.swallowClick = false;
        this.ownerChartId = 0;
        this.controlName = "";
        this.appliedColumn = -1;
        this.hoveredId = -1;
        this.nextControlId = 100000 + (long)(GetMicrosecondCount() % 1000000000);
    }

    /**
     * 自身のコントロールと変更したマウス通知設定を解放する。
     */
    ~DrawZigZagElliotMonitorSortCombo() {
        this.destroy();
    }

    /**
     * 初回と配置変更時だけ作成し、通常更新では変更された設定だけ同期する。
     *
     * @return 標準コントロールを表示可能な場合true。
     */
    bool prepare(const long fromChartId, const string fromName, const int fromLeft,
            const int fromTop, const int fromWidth, const int fromFontSize,
            const int fromColumn, bool &fromChanged) {
        fromChanged = false;
        if (this.attempted && !this.layoutDirty && this.ownerChartId == fromChartId
                && this.controlName == fromName && this.savedLeft == fromLeft
                && this.savedTop == fromTop && this.savedWidth == fromWidth
                && this.savedFontSize == fromFontSize) {
            if (this.created) {
                fromChanged = this.synchronize(fromColumn);
            }

            return this.created;
        }

        this.destroy();
        this.attempted = true;
        this.ownerChartId = fromChartId;
        this.controlName = fromName;
        this.savedLeft = fromLeft;
        this.savedTop = fromTop;
        this.savedWidth = fromWidth;
        this.savedFontSize = fromFontSize;
        this.savedChartWidth = (int)ChartGetInteger(fromChartId, CHART_WIDTH_IN_PIXELS, 0);
        this.savedChartHeight = (int)ChartGetInteger(fromChartId, CHART_HEIGHT_IN_PIXELS, 0);
        fromChanged = true;
        if (fromWidth < 40) {
            return false;
        }

        long mouseMoveEnabled = 0;
        if (!ChartGetInteger(fromChartId, CHART_EVENT_MOUSE_MOVE, 0, mouseMoveEnabled)) {
            return false;
        }

        if (mouseMoveEnabled == 0) {
            if (!ChartSetInteger(fromChartId, CHART_EVENT_MOUSE_MOVE, true)) {
                return false;
            }

            this.mouseMoveOwned = true;
        }

        this.ListViewItems(5);
        if (!this.Create(fromChartId, fromName, 0, fromLeft, fromTop, fromLeft + fromWidth, fromTop + 26)
                || !this.AddItem("通貨名", 0) || !this.AddItem("判定", 1)
                || !this.AddItem("長中期順位差", 3) || !this.AddItem("中短期順位差", 4)
                || !this.AddItem("直近成立時刻", 5)) {
            this.releaseControls();

            return false;
        }

        this.controlIdEnd = this.nextControlId + this.Id(this.nextControlId);
        this.nextControlId = this.controlIdEnd + 1;
        this.created = true;
        this.styleControls();
        this.synchronize(fromColumn);

        return true;
    }

    /**
     * モデルが変化した場合だけ選択値を反映し、非同期の利用者選択を上書きしない。
     */
    bool synchronize(const int fromColumn) {
        if (!this.created || this.appliedColumn == fromColumn) {
            return false;
        }

        this.selectionPending = false;
        this.synchronizing = true;
        bool selected = this.SelectByValue(fromColumn);
        this.synchronizing = false;
        if (selected) {
            this.appliedColumn = fromColumn;
        }

        return selected;
    }

    /**
     * 所有する標準イベントだけを処理し、背面へ伝えてはいけないクリックを消費する。
     *
     * @param fromSelectionChanged 利用者の選択通知を受け取った場合true。
     * @param fromColumn 利用者が選択した列ID。
     * @return このコントロールが消費したイベントの場合true。
     */
    bool handleEvent(const int fromEventId, const long &fromLongParam,
            const double &fromDoubleParam, const string &fromStringParam,
            bool &fromSelectionChanged, int &fromColumn) {
        fromSelectionChanged = false;
        if (fromEventId == CHARTEVENT_CHART_CHANGE) {
            if (this.attempted) {
                int chartWidth = (int)ChartGetInteger(this.ownerChartId, CHART_WIDTH_IN_PIXELS, 0);
                int chartHeight = (int)ChartGetInteger(this.ownerChartId, CHART_HEIGHT_IN_PIXELS, 0);
                if (chartWidth != this.savedChartWidth || chartHeight != this.savedChartHeight) {
                    this.layoutDirty = true;
                }
            }

            if (this.created && this.isListOpen()) {
                this.closeList();
                ChartRedraw(this.ownerChartId);
            }

            return false;
        }

        if (!this.created) {
            return false;
        }

        if (fromEventId >= CHARTEVENT_CUSTOM) {
            CWnd *source = this.ControlFind(fromLongParam);
            if (source == NULL || source.Name() != fromStringParam) {
                return false;
            }

            if (fromEventId == CHARTEVENT_CUSTOM + ON_CHANGE && fromLongParam == this.Id()) {
                if (this.selectionPending) {
                    this.selectionPending = false;
                    fromColumn = (int)this.Value();
                    fromSelectionChanged = true;
                }

                return true;
            }

            if (fromEventId == CHARTEVENT_CUSTOM + ON_CLICK && !source.IsVisible()) {
                return true;
            }

            if (fromEventId == CHARTEVENT_CUSTOM + ON_MOUSE_FOCUS_SET) {
                for (long controlId = this.Id() + 1; controlId < this.controlIdEnd; controlId++) {
                    CWndObj *control = dynamic_cast<CWndObj *>(this.ControlFind(controlId));
                    if (control != NULL && controlId != fromLongParam) {
                        control.MouseFocusKill();
                    }
                }

                return true;
            }

            if (CComboBox::OnEvent(fromEventId, fromLongParam, fromDoubleParam, fromStringParam)) {
                ChartRedraw(this.ownerChartId);
            }

            return true;
        }

        bool listOpen = this.isListOpen();
        int mouseX = (int)fromLongParam;
        int mouseY = (int)fromDoubleParam;
        if (fromEventId == CHARTEVENT_MOUSE_MOVE) {
            bool pressed = (StringToInteger(fromStringParam) & MOUSE_LEFT) != 0;
            bool newPress = pressed && !this.mouseDown;
            bool buttonChanged = pressed != this.mouseDown;
            this.mouseDown = pressed;
            if (newPress) {
                this.swallowClick = false;
                if (listOpen && !this.containsPopup(mouseX, mouseY)) {
                    this.closeList();
                    this.swallowClick = true;
                    ChartRedraw(this.ownerChartId);

                    return true;
                }
            }

            long currentHoveredId = this.getHoveredId(mouseX, mouseY);
            bool hoverChanged = currentHoveredId != this.hoveredId;
            this.hoveredId = currentHoveredId;
            bool handled = CComboBox::OnEvent(fromEventId, fromLongParam, fromDoubleParam, fromStringParam);
            if (hoverChanged || (handled && buttonChanged)) {
                ChartRedraw(this.ownerChartId);
            }

            return handled || this.swallowClick;
        }

        if (fromEventId == CHARTEVENT_OBJECT_CLICK || fromEventId == CHARTEVENT_CLICK) {
            bool ownObject = this.ownsObject(fromStringParam);
            if (this.swallowClick) {
                return true;
            }

            if (listOpen && !this.containsPopup(mouseX, mouseY)) {
                this.closeList();
                this.swallowClick = true;
                ChartRedraw(this.ownerChartId);

                return true;
            }

            return ownObject || listOpen;
        }

        if (this.ownsObject(fromStringParam)) {
            CComboBox::OnEvent(fromEventId, fromLongParam, fromDoubleParam, fromStringParam);

            return true;
        }

        return false;
    }

    /**
     * 保持した選択設定を破棄し、所有するコントロールだけを解放する。
     */
    void destroy() {
        this.releaseControls();
        this.attempted = false;
        this.layoutDirty = false;
        this.appliedColumn = -1;
        this.mouseDown = false;
        this.swallowClick = false;
        this.hoveredId = -1;
    }

protected:
    /**
     * 標準の選択通知を保ち、プログラム同期と利用者選択を区別する。
     */
    virtual bool OnChangeList() {
        if (!this.synchronizing) {
            this.selectionPending = true;
        }

        return CComboBox::OnChangeList();
    }

private:
    /** 標準コントロールを作成済みの場合true。 */
    bool created;

    /** 現在の配置で作成を試みた場合true。 */
    bool attempted;

    /** 画面変更後に再配置が必要な場合true。 */
    bool layoutDirty;

    /** マウス通知を自身が有効へ変更した場合true。 */
    bool mouseMoveOwned;

    /** モデル側の選択を同期している場合true。 */
    bool synchronizing;

    /** 利用者の選択通知が到着するまでtrue。 */
    bool selectionPending;

    /** 直前に確認した左ボタン押下状態。 */
    bool mouseDown;

    /** リストを閉じた押下の背面クリックを抑止する場合true。 */
    bool swallowClick;

    /** 表示先チャートID。 */
    long ownerChartId;

    /** 所有する標準コントロール名。 */
    string controlName;

    /** 直前に要求された左位置。 */
    int savedLeft;

    /** 直前に要求された上位置。 */
    int savedTop;

    /** 直前に要求された横幅。 */
    int savedWidth;

    /** 直前に要求された文字サイズ。 */
    int savedFontSize;

    /** 作成時のチャート幅。 */
    int savedChartWidth;

    /** 作成時のチャート高。 */
    int savedChartHeight;

    /** 最後に反映したモデルのソート列。 */
    int appliedColumn;

    /** 次回作成で使用する固有IDの開始値。 */
    long nextControlId;

    /** 現在の固有ID範囲の終端。 */
    long controlIdEnd;

    /** マウス下にある所有コントロールID。 */
    long hoveredId;

    /**
     * 作成済みの子コントロールと変更した通知設定を解放する。
     */
    void releaseControls() {
        CComboBox::Destroy();
        if (this.attempted && this.controlName != "") {
            ObjectsDeleteAll(this.ownerChartId, this.controlName, 0, -1);
        }

        if (this.mouseMoveOwned) {
            ChartSetInteger(this.ownerChartId, CHART_EVENT_MOUSE_MOVE, false);
            this.mouseMoveOwned = false;
        }

        this.created = false;
        this.selectionPending = false;
    }

    /**
     * 固有IDを持つ子オブジェクトの文字とクリック優先度を設定する。
     */
    void styleControls() {
        for (long controlId = this.Id(); controlId < this.controlIdEnd; controlId++) {
            CWndObj *control = dynamic_cast<CWndObj *>(this.ControlFind(controlId));
            if (control == NULL) {
                continue;
            }

            control.Font("Meiryo");
            control.FontSize((int)MathMin(10, this.savedFontSize));
            control.ZOrder(20000 + controlId - this.Id());
        }
    }

    /**
     * 標準クラスが所有するリストの表示状態を返す。
     */
    bool isListOpen() {
        CWnd *list = this.Control(2);

        return list != NULL && list.IsVisible();
    }

    /**
     * リストと押下状態をそろえて閉じる。
     */
    void closeList() {
        this.ListHide();
        CBmpButton *drop = dynamic_cast<CBmpButton *>(this.Control(1));
        if (drop != NULL) {
            drop.Pressed(false);
        }
    }

    /**
     * 展開中リストを含むクリック領域内か確認する。
     */
    bool containsPopup(const int fromMouseX, const int fromMouseY) {
        CWnd *list = this.Control(2);

        return this.Contains(fromMouseX, fromMouseY)
            || (list != NULL && list.IsVisible() && list.Contains(fromMouseX, fromMouseY));
    }

    /**
     * 固有IDで管理された子の名前と厳密に一致するか確認する。
     */
    bool ownsObject(const string fromName) {
        for (long controlId = this.Id(); controlId < this.controlIdEnd; controlId++) {
            CWnd *control = this.ControlFind(controlId);
            if (control != NULL && control.Name() == fromName) {
                return true;
            }
        }

        return false;
    }

    /**
     * マウス移動で見た目が変わり得る所有コントロールを確認する。
     */
    long getHoveredId(const int fromMouseX, const int fromMouseY) {
        for (long controlId = this.controlIdEnd - 1; controlId >= this.Id(); controlId--) {
            CWnd *control = this.ControlFind(controlId);
            if (control != NULL && control.IsVisible() && control.Contains(fromMouseX, fromMouseY)) {
                return controlId;
            }
        }

        return -1;
    }
};

#endif // MSTNG_DRAW_ZIGZAG_ELLIOT_MONITOR_SORT_COMBO_MQH
