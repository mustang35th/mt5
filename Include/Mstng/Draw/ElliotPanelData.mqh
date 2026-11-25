#ifndef MSTNG_DRAW_ELLIOT_PANEL_DATA_MQH
#define MSTNG_DRAW_ELLIOT_PANEL_DATA_MQH

#include <Mstng\Draw\ElliotTableRowData.mqh>

/**
 * 共通パネルへ渡す一時間足の一覧・詳細・追加指標を保持する。
 * 分析結果と保存値の取得処理には依存しない。
 */
struct ElliotPanelFrame {
    /** 選択状態を保持する時間足。 */
    int timeFrame;

    /** 共通5列の表示値。 */
    ElliotTableRowData row;

    /** ポイントのサーバー時刻。未取得は0。 */
    datetime pointTime;

    /** ポイントの日本時刻。未取得は0。 */
    datetime pointJstTime;

    /** ライブ値動きの計算値を補足するツールチップ。 */
    string movementTooltip;

    /** 追加指標数。最大8項目。 */
    int extraCount;

    /** 追加指標の項目名。 */
    string extraLabels[8];

    /** 追加指標の表示値。 */
    string extraValues[8];

    /** 追加指標の文字色。 */
    color extraColors[8];

    /**
     * 未取得状態で初期化する。
     */
    ElliotPanelFrame() {
        this.clear();
    }

    /**
     * 詳細と追加指標を未取得状態へ戻す。
     */
    void clear() {
        this.timeFrame = PERIOD_CURRENT;
        this.row.clear();
        this.pointTime = 0;
        this.pointJstTime = 0;
        this.movementTooltip = "";
        this.extraCount = 0;
        for (int i = 0; i < 8; i++) {
            this.extraLabels[i] = "";
            this.extraValues[i] = "";
            this.extraColors[i] = clrSilver;
        }
    }
};

/**
 * 一集計期間の通貨順位と順位差を表示用に保持する。
 */
struct ElliotPanelStrengthPeriod {
    /** 両通貨の順位が有効な場合true。 */
    bool valid;

    /** 直前M5との比較が有効な場合true。 */
    bool comparable;

    /** 基軸通貨順位。 */
    int baseRank;

    /** 決済通貨順位。 */
    int quoteRank;

    /** 決済通貨順位から基軸通貨順位を引いた値。 */
    int gap;

    /** 直前M5からの順位差の増減。 */
    int delta;

    /**
     * 未取得状態で初期化する。
     */
    ElliotPanelStrengthPeriod() {
        this.clear();
    }

    /**
     * 有効状態と比較状態を解除する。
     */
    void clear() {
        this.valid = false;
        this.comparable = false;
        this.baseRank = 0;
        this.quoteRank = 0;
        this.gap = 0;
        this.delta = 0;
    }
};

/**
 * 現在値または保存履歴の取得元を明示した通貨強弱表示データ。
 */
struct ElliotPanelStrength {
    /** 通貨強弱の参照設定が有効な場合true。 */
    bool enabled;

    /** 現在値・同M5履歴と参照方式を示す見出し。 */
    string title;

    /** 取得元と時刻の補足。 */
    string tooltip;

    /** 取得済み・未記録などの状態。 */
    string status;

    /** 基軸通貨名。 */
    string baseCurrency;

    /** 決済通貨名。 */
    string quoteCurrency;

    /** 長中期の順位。 */
    ElliotPanelStrengthPeriod longMedium;

    /** 中短期の順位。 */
    ElliotPanelStrengthPeriod mediumShort;

    /**
     * 未取得状態で初期化する。
     */
    ElliotPanelStrength() {
        this.clear();
    }

    /**
     * 取得元と順位を未取得へ戻す。
     */
    void clear() {
        this.enabled = false;
        this.title = "通貨強弱";
        this.tooltip = "";
        this.status = "未記録";
        this.baseCurrency = "";
        this.quoteCurrency = "";
        this.longMedium.clear();
        this.mediumShort.clear();
    }
};

/**
 * 一枚の共通パネルへ渡す表示内容。
 * 選択・開閉状態は含めず、パネル側が現在値と保存値を別々に保持する。
 */
struct ElliotPanelData {
    /** 対象通貨ペア。 */
    string symbolName;

    /** 分析時刻または観測時刻の表示文字列。 */
    string headerTime;

    /** 取得時刻・参照元などの補足。 */
    string metadata;

    /** パネル下端の操作説明。 */
    string hint;

    /** 未取得などの状態表示。通常表示は空文字。 */
    string status;

    /** 価格小数桁数。 */
    int digits;

    /** 一覧行数。最大8時間足。 */
    int rowCount;

    /** 保存モードの対象M5開始時刻。 */
    datetime savedTime;

    /** 前の保存データへ移動できる場合true。 */
    bool canPrevious;

    /** 次の保存データへ移動できる場合true。 */
    bool canNext;

    /** 一覧の表示順に並んだ時間足。 */
    ElliotPanelFrame frames[8];

    /** 通貨強弱の表示内容。 */
    ElliotPanelStrength strength;

    /** 一覧の配色。 */
    ElliotTablePalette palette;

    /**
     * 未取得状態で初期化する。
     */
    ElliotPanelData() {
        this.clear();
    }

    /**
     * 内容を未取得状態へ戻す。
     */
    void clear() {
        this.symbolName = "";
        this.headerTime = "";
        this.metadata = "";
        this.hint = "";
        this.status = "";
        this.digits = 0;
        this.rowCount = 0;
        this.savedTime = 0;
        this.canPrevious = false;
        this.canNext = false;
        this.strength.clear();
        ElliotTablePalette defaultPalette;
        this.palette = defaultPalette;
        for (int i = 0; i < 8; i++) {
            this.frames[i].clear();
        }
    }
};

#endif // MSTNG_DRAW_ELLIOT_PANEL_DATA_MQH
