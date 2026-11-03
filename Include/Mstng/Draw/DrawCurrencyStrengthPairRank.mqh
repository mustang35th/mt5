//+------------------------------------------------------------------+
//|                                 DrawCurrencyStrengthPairRank.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_PAIR_RANK_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_PAIR_RANK_MQH

#include <Canvas\Canvas.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Constant\ConstantCurrency.mqh>
#include <Mstng\Draw\DrawZigZagElliotInfoLayout.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthPairRankInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthRankAndSignal.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 表示中の通貨ペアに対応する通貨強弱順位を共通の右情報欄へ描画する。
 */
class DrawCurrencyStrengthPairRank {
public:
    /**
     * 描画対象チャートを指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     * @param fromXDistance チャート右端からの距離。
     * @param fromVoteWeightMode 通貨強弱の投票ウェイト方式。
     */
    DrawCurrencyStrengthPairRank(
        long fromChartId = 0,
        int fromXDistance = 10,
        CurrencyStrengthVoteWeightMode fromVoteWeightMode =
            CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM
    ) {
        this.chartId = fromChartId;
        this.destroyLegacyObjects();

        string baseObjectPrefix =
            Constant::PREFIX_FIXED + "CurrencyStrengthPairRank";
        int instanceIndex = 0;
        this.objectPrefix =
            baseObjectPrefix + IntegerToString(instanceIndex) + "_";

        while (ObjectFind(
                this.chartId,
                this.objectPrefix + "SourceBadge"
            ) >= 0) {
            instanceIndex++;
            this.objectPrefix =
                baseObjectPrefix + IntegerToString(instanceIndex) + "_";
        }

        this.calculationModeText =
            CurrencyStrengthCalculationProfile::getVoteWeightModeText(
                fromVoteWeightMode
            );
        this.created = false;
        this.connectionsReady = false;
        this.lastConnectionsVisible = false;
        this.lastConnectionsDimmed = false;
        this.lastConnectionInfo.reset();
        this.decisionReady = false;
        this.lastDecisionText = "";
        this.lastDecisionColor = clrNONE;
        this.lastDecisionTooltip = "";
        this.hasRankData = false;
        this.lastExecutionInfo.reset();
        this.lastBaseCurrency = "";
        this.lastQuoteCurrency = "";
        this.lastDisplayAvailable = false;
        this.lastDisplayError = false;
        this.corner = CORNER_RIGHT_UPPER;
        this.xDistance = fromXDistance;
        if (this.xDistance < DrawZigZagElliotInfoLayout::getMinimumRightDistance()) {
            this.xDistance = DrawZigZagElliotInfoLayout::getMinimumRightDistance();
        }

        this.reservedAreaEnabled = false;
        this.reservedLeft = 0;
        this.reservedTop = 0;
        this.reservedRight = 0;
        this.reservedBottom = 0;
        this.yDistance = 0;
        this.panelWidth = DrawZigZagElliotInfoLayout::getWidth();
        this.panelHeight = 272;
        this.rankTopOffset = 69;
        this.rankRowHeight = 19;
        this.fontName = "MS Gothic";
        this.titleFontSize = 15;
        this.bodyFontSize = 15;
        this.headerColor = C'180,180,180';
        this.mutedColor = C'130,130,130';
        this.buyColor = clrDeepSkyBlue;
        this.sellColor = clrHotPink;
        this.warningColor = clrGold;
        this.errorColor = clrTomato;
        this.rankGridColor = C'45,45,45';
        this.rankGridBoundaryColor = C'90,90,90';

        this.calculateYDistance();
    }

    /**
     * 保持しているチャートオブジェクトを破棄する。
     */
    ~DrawCurrencyStrengthPairRank() {
        this.destroyObjects();
    }

    /**
     * 表示中の通貨ペアに対応する順位を描画する。
     *
     * @param fromInfo 実行時通貨強弱情報。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthExecutionInfo &fromInfo) {
        if (!fromInfo.isAvailable()) {
            return this.drawUnavailable(
                fromInfo.pairRankInfo.baseCurrency,
                fromInfo.pairRankInfo.quoteCurrency
            );
        }

        // 描画に失敗しても、再生成時は今回取得した状態を使用する。
        this.lastExecutionInfo = fromInfo;
        this.lastBaseCurrency = fromInfo.pairRankInfo.baseCurrency;
        this.lastQuoteCurrency = fromInfo.pairRankInfo.quoteCurrency;
        this.lastDisplayAvailable = true;
        this.lastDisplayError = false;

        if (!this.ensureCreated()) {
            return false;
        }

        CurrencyStrengthPairRankInfo pairRankInfo = fromInfo.pairRankInfo;
        int longMediumDifference = fromInfo.getLongMediumRankDifference();
        int mediumShortDifference = fromInfo.getMediumShortRankDifference();

        this.updateSourceBadge(fromInfo.sourceMode);
        this.setLabelText(
            "ModeBadge",
            this.calculationModeText,
            this.headerColor
        );
        if (!this.updateDecision(fromInfo)) {
            return false;
        }

        this.setLabelText(
            "LongMediumSignal",
            this.formatSignal(longMediumDifference),
            this.getSignalColor(longMediumDifference)
        );
        this.setLabelText(
            "MediumShortSignal",
            this.formatSignal(mediumShortDifference),
            this.getSignalColor(mediumShortDifference)
        );
        this.updateRankColumn(
            "BaseLongMediumRank",
            "QuoteLongMediumRank",
            this.getColumnCenter(true),
            pairRankInfo.baseCurrency,
            pairRankInfo.baseLongMediumTermAverageRank,
            pairRankInfo.quoteCurrency,
            pairRankInfo.quoteLongMediumTermAverageRank
        );
        this.updateRankColumn(
            "BaseMediumShortRank",
            "QuoteMediumShortRank",
            this.getColumnCenter(false),
            pairRankInfo.baseCurrency,
            pairRankInfo.baseMediumShortTermAverageRank,
            pairRankInfo.quoteCurrency,
            pairRankInfo.quoteMediumShortTermAverageRank
        );

        if (!this.updateRankConnections()) {
            return false;
        }

        string m5BarTimeText = this.formatM5BarTime(pairRankInfo);

        this.setLabelText("M5BarTime", m5BarTimeText, this.mutedColor);

        if (fromInfo.targetM5BarTime > 0
                && pairRankInfo.m5BarTime != fromInfo.targetM5BarTime) {
            this.setLabelText("StateBadge", "STALE", this.warningColor);
        } else {
            this.setLabelText("StateBadge", " ", this.mutedColor);
        }

        this.hasRankData = true;
        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 従来形式の順位情報を描画する。
     *
     * @param fromInfo 通貨ペア順位情報。
     * @return 描画に成功した場合true。
     */
    bool draw(CurrencyStrengthPairRankInfo &fromInfo) {
        CurrencyStrengthExecutionInfo executionInfo;
        executionInfo.reset();
        executionInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
        executionInfo.targetM5BarTime = fromInfo.m5BarTime;
        executionInfo.sourceMode = "-";
        executionInfo.pairRankInfo = fromInfo;

        return this.draw(executionInfo);
    }

    /**
     * 順位を取得できない状態のパネルを描画する。
     *
     * @param fromBaseCurrency 基軸通貨名。
     * @param fromQuoteCurrency 決済通貨名。
     * @return 描画に成功した場合true。
     */
    bool drawUnavailable(string fromBaseCurrency, string fromQuoteCurrency) {
        this.hasRankData = false;
        this.lastExecutionInfo.reset();
        this.lastBaseCurrency = fromBaseCurrency;
        this.lastQuoteCurrency = fromQuoteCurrency;
        this.lastDisplayAvailable = false;
        this.lastDisplayError = false;

        if (!this.ensureCreated()) {
            return false;
        }

        this.setLabelText("SourceBadge", "-", this.mutedColor);
        this.setLabelText(
            "ModeBadge",
            this.calculationModeText,
            this.headerColor
        );
        if (!this.setDecision("NO DATA", this.mutedColor,
                "通貨強弱の順位を取得できません。READY／WATCHは判定しません。")) {
            return false;
        }

        this.setLabelText("StateBadge", " ", this.mutedColor);
        this.setLabelText("LongMediumSignal", "-", this.mutedColor);
        this.setLabelText("MediumShortSignal", "-", this.mutedColor);
        this.updateRankColumn(
            "BaseLongMediumRank",
            "QuoteLongMediumRank",
            this.getColumnCenter(true),
            fromBaseCurrency,
            0,
            fromQuoteCurrency,
            0
        );
        this.updateRankColumn(
            "BaseMediumShortRank",
            "QuoteMediumShortRank",
            this.getColumnCenter(false),
            fromBaseCurrency,
            0,
            fromQuoteCurrency,
            0
        );
        this.setLabelText("M5BarTime", "-", this.mutedColor);

        if (!this.updateRankConnections()) {
            return false;
        }

        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 取得エラーを表示し、直前の順位表示を維持する。
     *
     * @return 描画に成功した場合true。
     */
    bool drawError() {
        this.lastDisplayError = true;
        if (!this.ensureCreated()) {
            return false;
        }

        string errorText = "ERROR";

        if (this.hasRankData) {
            errorText = "ERR 前回値";
            if (!this.updateDecision(this.lastExecutionInfo, true)) {
                return false;
            }
        } else if (!this.setDecision("NO DATA", this.mutedColor,
                "ERROR：通貨強弱の取得に失敗しました。READY／WATCHは判定しません。")) {
            return false;
        }

        this.setLabelText("StateBadge", errorText, this.errorColor);
        if (!this.updateRankConnections()) {
            return false;
        }

        ChartRedraw(this.chartId);

        return true;
    }

    /**
     * 最終表示内容を再生成し、他のチャート描画より前面へ戻す。
     *
     * @return 再描画に成功した場合true。
     */
    bool redrawOnTop() {
        CurrencyStrengthExecutionInfo executionInfo;
        executionInfo = this.lastExecutionInfo;
        string baseCurrency = this.lastBaseCurrency;
        string quoteCurrency = this.lastQuoteCurrency;
        bool displayAvailable = this.lastDisplayAvailable;
        bool displayError = this.lastDisplayError;

        this.destroyObjects();

        bool isSuccess = false;

        if (displayAvailable) {
            isSuccess = this.draw(executionInfo);
        } else {
            isSuccess = this.drawUnavailable(baseCurrency, quoteCurrency);
        }

        // 再生成の途中で失敗しても、前回値に重ねる取得エラーを保持する。
        this.lastDisplayError = displayError;
        if (!isSuccess) {
            return false;
        }

        if (displayError) {
            return this.drawError();
        }

        return true;
    }

    /**
     * 他の表示用に予約した領域を設定し、重なる場合は右端位置を保って下へ移す。
     * 幅または高さが正でない領域を指定すると予約を解除する。
     *
     * @param fromLeft チャート左端からの予約領域左辺
     * @param fromTop チャート上端からの予約領域上辺
     * @param fromRight チャート左端からの予約領域右辺
     * @param fromBottom チャート上端からの予約領域下辺
     */
    void setReservedArea(int fromLeft, int fromTop, int fromRight, int fromBottom) {
        this.reservedLeft = fromLeft;
        this.reservedTop = fromTop;
        this.reservedRight = fromRight;
        this.reservedBottom = fromBottom;
        this.reservedAreaEnabled = fromRight > fromLeft && fromBottom > fromTop;
        this.reposition();
    }

    /**
     * チャートサイズと予約領域に合わせてパネルを再配置する。
     */
    void reposition() {
        this.calculateYDistance();

        if (!this.created) {
            return;
        }

        this.repositionRankGrid();
        if (!this.positionRankConnections()) {
            this.connectionsReady = false;
        }

        this.setLabelPosition("Decision", 0, 5);
        this.setLabelPosition("StateBadge", this.panelWidth, this.getModeBadgeTopOffset());
        this.setLabelPosition("SourceBadge", this.panelWidth, 5);
        this.setLabelPosition("LongMediumHeader", this.getColumnCenter(true), 28);
        this.setLabelPosition("MediumShortHeader", this.getColumnCenter(false), 28);
        this.setLabelPosition("LongMediumSignal", this.getColumnCenter(true), 47);
        this.setLabelPosition("MediumShortSignal", this.getColumnCenter(false), 47);
        this.repositionRankColumns();
        this.setLabelPosition(
            "M5BarTimeTitle",
            0,
            this.getM5BarTimeTopOffset()
        );
        this.setLabelPosition(
            "M5BarTime",
            this.getM5BarTimeLeftOffset(),
            this.getM5BarTimeTopOffset()
        );
        this.setLabelPosition(
            "ModeBadgeTitle",
            0,
            this.getModeBadgeTopOffset()
        );
        this.setLabelPosition(
            "ModeBadge",
            this.getModeBadgeLeftOffset(),
            this.getModeBadgeTopOffset()
        );
        ChartRedraw(this.chartId);
    }

    /**
     * 順位パネル専用のチャートオブジェクトを削除する。
     */
    void clear() {
        this.destroyObjects();
        this.lastExecutionInfo.reset();
        this.lastBaseCurrency = "";
        this.lastQuoteCurrency = "";
        this.lastDisplayAvailable = false;
        this.lastDisplayError = false;
        ChartRedraw(this.chartId);
    }

private:
    /** 判定ラベルの文字・色・説明を反映済みの場合true。 */
    bool decisionReady;

    /** 最後に反映した判定文字。 */
    string lastDecisionText;

    /** 最後に反映した判定色。 */
    color lastDecisionColor;

    /** 最後に反映した判定理由。 */
    string lastDecisionTooltip;

    /** 描画対象チャートID。 */
    long chartId;

    /** 順位パネル専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** 投票ウェイト方式の表示文字列。 */
    string calculationModeText;

    /** パネル生成済みの場合true。 */
    bool created;

    /** 通貨別の順位接続線を描く透明Canvas。 */
    CCanvas connectionCanvas;

    /** 接続線の描画内容を反映済みの場合true。 */
    bool connectionsReady;

    /** 最後に接続線へ反映した通貨名と4順位。 */
    CurrencyStrengthPairRankInfo lastConnectionInfo;

    /** 最後に接続線へ反映した順位の取得有無。 */
    bool lastConnectionsVisible;

    /** 最後に接続線を古いデータ・取得エラーの薄い色で描いた場合true。 */
    bool lastConnectionsDimmed;

    /** 直前の有効な順位を表示中の場合true。 */
    bool hasRankData;

    /** 再生成に使用する最新の実行時通貨強弱情報。描画失敗時も保持する。 */
    CurrencyStrengthExecutionInfo lastExecutionInfo;

    /** 再生成に使用する基軸通貨コード。 */
    string lastBaseCurrency;

    /** 再生成に使用する決済通貨コード。 */
    string lastQuoteCurrency;

    /** 再生成時に有効な順位を表示する場合true。 */
    bool lastDisplayAvailable;

    /** 再生成時に取得エラーを重ねる場合true。描画失敗時も保持する。 */
    bool lastDisplayError;

    /** パネル配置基準の角。 */
    ENUM_BASE_CORNER corner;

    /** チャート右端からの距離。 */
    int xDistance;

    /** 他の表示用に予約した領域が有効な場合true。 */
    bool reservedAreaEnabled;

    /** チャート左端からの予約領域左辺。 */
    int reservedLeft;

    /** チャート上端からの予約領域上辺。 */
    int reservedTop;

    /** チャート左端からの予約領域右辺。 */
    int reservedRight;

    /** チャート上端からの予約領域下辺。 */
    int reservedBottom;

    /** チャート上端からの距離。 */
    int yDistance;

    /** パネル幅。 */
    int panelWidth;

    /** パネル高さ。 */
    int panelHeight;

    /** 1位を表示するパネル上端からの位置。 */
    int rankTopOffset;

    /** 順位1段分の高さ。 */
    int rankRowHeight;

    /** 表示フォント名。 */
    string fontName;

    /** タイトル文字サイズ。 */
    int titleFontSize;

    /** 本文文字サイズ。 */
    int bodyFontSize;

    /** 列ヘッダー文字色。 */
    color headerColor;

    /** 補助文字色。 */
    color mutedColor;

    /** 買い方向文字色。 */
    color buyColor;

    /** 売り方向文字色。 */
    color sellColor;

    /** 警告文字色。 */
    color warningColor;

    /** エラー文字色。 */
    color errorColor;

    /** 順位行の罫線色。 */
    color rankGridColor;

    /** 順位領域境界と中央線の色。 */
    color rankGridBoundaryColor;

    /**
     * 必要に応じて順位パネルを生成する。
     *
     * @return パネルを使用できる場合true。
     */
    bool ensureCreated() {
        if (this.created) {
            if (ObjectFind(this.chartId, this.objectPrefix + "RankConnections") < 0
                    || this.connectionCanvas.ResourceName() == "") {
                return this.createRankConnections();
            }

            return true;
        }

        return this.create();
    }

    /**
     * 順位パネルを生成する。
     *
     * @return 生成に成功した場合true。
     */
    bool create() {
        this.destroyObjects();

        this.calculateYDistance();

        if (!this.createRankGrid() || !this.createRankConnections()) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "SourceBadge",
            this.panelWidth,
            5,
            this.bodyFontSize,
            this.mutedColor,
            "-",
            ANCHOR_RIGHT_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "Decision",
            0,
            5,
            this.titleFontSize,
            this.mutedColor,
            "NO DATA"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "StateBadge",
            this.panelWidth,
            this.getModeBadgeTopOffset(),
            this.bodyFontSize,
            this.mutedColor,
            " ",
            ANCHOR_RIGHT_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "LongMediumHeader",
            this.getColumnCenter(true),
            28,
            this.bodyFontSize,
            this.headerColor,
            "長中期",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "MediumShortHeader",
            this.getColumnCenter(false),
            28,
            this.bodyFontSize,
            this.headerColor,
            "中短期",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "LongMediumSignal",
            this.getColumnCenter(true),
            47,
            this.bodyFontSize,
            this.mutedColor,
            "-",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "MediumShortSignal",
            this.getColumnCenter(false),
            47,
            this.bodyFontSize,
            this.mutedColor,
            "-",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "BaseLongMediumRank",
            this.getColumnCenter(true),
            this.rankTopOffset,
            this.bodyFontSize,
            this.mutedColor,
            "-",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "BaseMediumShortRank",
            this.getColumnCenter(false),
            this.rankTopOffset,
            this.bodyFontSize,
            this.mutedColor,
            "-",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "QuoteLongMediumRank",
            this.getColumnCenter(true),
            this.rankTopOffset + this.rankRowHeight,
            this.bodyFontSize,
            this.mutedColor,
            "-",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "QuoteMediumShortRank",
            this.getColumnCenter(false),
            this.rankTopOffset + this.rankRowHeight,
            this.bodyFontSize,
            this.mutedColor,
            "-",
            ANCHOR_UPPER
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "M5BarTimeTitle",
            0,
            this.getM5BarTimeTopOffset(),
            DrawZigZagElliotInfoLayout::getTimeFontSize(),
            this.mutedColor,
            "M5"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "M5BarTime",
            this.getM5BarTimeLeftOffset(),
            this.getM5BarTimeTopOffset(),
            DrawZigZagElliotInfoLayout::getTimeFontSize(),
            this.mutedColor,
            "-"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "ModeBadgeTitle",
            0,
            this.getModeBadgeTopOffset(),
            this.bodyFontSize - 3,
            this.headerColor,
            "方式"
        )) {
            this.destroyObjects();

            return false;
        }

        if (!this.createLabel(
            "ModeBadge",
            this.getModeBadgeLeftOffset(),
            this.getModeBadgeTopOffset(),
            this.bodyFontSize - 3,
            this.headerColor,
            this.calculationModeText
        )) {
            this.destroyObjects();

            return false;
        }

        this.created = true;

        return true;
    }

    /**
     * 順位罫線と文字の間へ透明な接続線Canvasを生成する。
     *
     * @return Canvasと固定属性を設定できた場合true。
     */
    bool createRankConnections() {
        this.connectionsReady = false;
        this.connectionCanvas.Destroy();
        string objectName = this.objectPrefix + "RankConnections";
        if (!this.connectionCanvas.CreateBitmapLabel(
                this.chartId, 0, objectName, 0, 0,
                this.panelWidth, this.rankRowHeight * 8, COLOR_FORMAT_ARGB_NORMALIZE)) {
            this.connectionCanvas.Destroy();
            ObjectDelete(this.chartId, objectName);

            return false;
        }

        if (!ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner)
                || !ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
                || !ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false)
                || !ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false)
                || !ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false)
                || !ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true)
                || !ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 0)
                || !ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP,
                    "同時点の長中期と中短期の順位を通貨色で接続。古いデータ・取得エラー時は薄く表示。")
                || !this.positionRankConnections()) {
            this.connectionCanvas.Destroy();

            return false;
        }

        return true;
    }

    /**
     * 画面幅に追従する右上基準で接続線Canvasを配置する。
     *
     * @return 位置の設定に成功した場合true。
     */
    bool positionRankConnections() {
        string objectName = this.objectPrefix + "RankConnections";

        return ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE,
                this.xDistance + this.panelWidth)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE,
                this.yDistance + this.getRankGridTopOffset());
    }

    /**
     * 通貨名・順位・有効性・減衰状態が変わった場合だけ接続線を更新する。
     * 未取得は透明にし、古いデータと取得エラーの前回値は同じ通貨色で薄く描く。
     *
     * @return 接続線の更新に成功、または変更不要の場合true。
     */
    bool updateRankConnections() {
        bool visible = this.lastDisplayAvailable && (!this.lastDisplayError || this.hasRankData);
        bool dimmed = this.lastDisplayError
            || (this.lastExecutionInfo.targetM5BarTime > 0
                && this.lastExecutionInfo.pairRankInfo.m5BarTime
                    != this.lastExecutionInfo.targetM5BarTime);
        if (this.isConnectionSnapshotCurrent(
                this.lastExecutionInfo.pairRankInfo, visible, dimmed)) {
            return true;
        }

        this.connectionsReady = false;
        if (this.connectionCanvas.ResourceName() == "" || !this.positionRankConnections()) {
            return false;
        }

        this.connectionCanvas.Erase(0);
        if (visible) {
            uchar opacity = 230;
            if (dimmed) {
                opacity = 75;
            }

            this.drawRankConnection(this.lastExecutionInfo.pairRankInfo, true, opacity);
            this.drawRankConnection(this.lastExecutionInfo.pairRankInfo, false, opacity);
        }

        ResetLastError();
        this.connectionCanvas.Update(false);
        if (GetLastError() != 0) {
            return false;
        }

        this.lastConnectionInfo = this.lastExecutionInfo.pairRankInfo;
        this.lastConnectionsVisible = visible;
        this.lastConnectionsDimmed = dimmed;
        this.connectionsReady = true;

        return true;
    }

    /**
     * 接続線に必要な値だけを前回の成功内容と比較する。
     *
     * @param fromInfo 今回の通貨順位。
     * @param fromVisible 順位を取得できた場合true。
     * @param fromDimmed 古いデータ・取得エラーの場合true。
     * @return Canvasの再描画が不要な場合true。
     */
    bool isConnectionSnapshotCurrent(
        const CurrencyStrengthPairRankInfo &fromInfo,
        const bool fromVisible,
        const bool fromDimmed
    ) {
        return this.connectionsReady
            && this.lastConnectionsVisible == fromVisible
            && this.lastConnectionsDimmed == fromDimmed
            && this.lastConnectionInfo.baseCurrency == fromInfo.baseCurrency
            && this.lastConnectionInfo.quoteCurrency == fromInfo.quoteCurrency
            && this.lastConnectionInfo.baseLongMediumTermAverageRank == fromInfo.baseLongMediumTermAverageRank
            && this.lastConnectionInfo.baseMediumShortTermAverageRank == fromInfo.baseMediumShortTermAverageRank
            && this.lastConnectionInfo.quoteLongMediumTermAverageRank == fromInfo.quoteLongMediumTermAverageRank
            && this.lastConnectionInfo.quoteMediumShortTermAverageRank == fromInfo.quoteMediumShortTermAverageRank;
    }

    /**
     * 1通貨の長中期と中短期を細線と端点で結ぶ。
     * 同順位の列は端点を中央へ寄せ、上下2pxだけ分けて2色を区別する。
     *
     * @param fromInfo 今回の通貨順位。
     * @param fromBase 基軸通貨の場合true。
     * @param fromOpacity 通貨色の不透明度。
     */
    void drawRankConnection(
        const CurrencyStrengthPairRankInfo &fromInfo,
        const bool fromBase,
        const uchar fromOpacity
    ) {
        string currency = fromInfo.baseCurrency;
        int longRank = fromInfo.baseLongMediumTermAverageRank;
        int shortRank = fromInfo.baseMediumShortTermAverageRank;
        int tieOffset = -2;
        if (!fromBase) {
            currency = fromInfo.quoteCurrency;
            longRank = fromInfo.quoteLongMediumTermAverageRank;
            shortRank = fromInfo.quoteMediumShortTermAverageRank;
            tieOffset = 2;
        }

        if (currency == "" || !this.isValidRank(longRank) || !this.isValidRank(shortRank)) {
            return;
        }

        int leftX = this.getColumnCenter(true) + 42;
        int rightX = this.getColumnCenter(false) - 42;
        int leftY = this.getRankTopOffset(longRank) - this.getRankGridTopOffset() + 8;
        int rightY = this.getRankTopOffset(shortRank) - this.getRankGridTopOffset() + 8;
        if (fromInfo.baseLongMediumTermAverageRank == fromInfo.quoteLongMediumTermAverageRank) {
            leftX = this.panelWidth / 2 - 12;
            leftY += tieOffset;
        }

        if (fromInfo.baseMediumShortTermAverageRank == fromInfo.quoteMediumShortTermAverageRank) {
            rightX = this.panelWidth / 2 + 12;
            rightY += tieOffset;
        }

        uint lineColor = ColorToARGB(ConstantCurrency::getColor(currency), fromOpacity);
        this.connectionCanvas.LineAA(leftX, leftY, rightX, rightY, lineColor);
        this.connectionCanvas.FillCircle(leftX, leftY, 2, lineColor);
        this.connectionCanvas.FillCircle(rightX, rightY, 2, lineColor);
    }

    /**
     * 8順位の横罫線と期間列の中央縦線を生成する。
     *
     * 外枠は生成せず、横罫線を共通情報欄の左右端へ揃える。
     *
     * @return 生成に成功した場合true。
     */
    bool createRankGrid() {
        int gridTopOffset = this.getRankGridTopOffset();
        int horizontalRightOffset = 0;
        int horizontalWidth = this.panelWidth;

        for (int i = 0; i <= 8; i++) {
            color lineColor = this.rankGridColor;

            if (i == 0 || i == 8) {
                lineColor = this.rankGridBoundaryColor;
            }

            if (!this.createRankGridLine(
                "RankGridHorizontal" + IntegerToString(i),
                horizontalRightOffset,
                gridTopOffset + i * this.rankRowHeight,
                horizontalWidth,
                1,
                lineColor
            )) {
                return false;
            }
        }

        int centerTopOffset = 27;
        int gridBottomOffset = gridTopOffset + 8 * this.rankRowHeight;

        return this.createRankGridLine(
            "RankGridCenter",
            this.panelWidth / 2,
            centerTopOffset,
            1,
            gridBottomOffset - centerTopOffset + 1,
            this.rankGridBoundaryColor
        );
    }

    /**
     * 順位罫線用の矩形ラベルを生成する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromRightOffset パネル右端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromWidth 横幅。
     * @param fromHeight 高さ。
     * @param fromColor 罫線色。
     * @return 生成に成功した場合true。
     */
    bool createRankGridLine(
        string fromNameSuffix,
        int fromRightOffset,
        int fromTopOffset,
        int fromWidth,
        int fromHeight,
        color fromColor
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        if (!ObjectCreate(
            this.chartId,
            objectName,
            OBJ_RECTANGLE_LABEL,
            0,
            0,
            0
        )) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        this.setRankGridLinePosition(
            fromNameSuffix,
            fromRightOffset,
            fromTopOffset,
            fromWidth
        );
        ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, fromWidth);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, fromHeight);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, fromColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 1);

        return true;
    }

    /**
     * 保存済みの罫線を現在のパネル位置へ再配置する。
     */
    void repositionRankGrid() {
        int gridTopOffset = this.getRankGridTopOffset();

        for (int i = 0; i <= 8; i++) {
            this.setRankGridLinePosition(
                "RankGridHorizontal" + IntegerToString(i),
                0,
                gridTopOffset + i * this.rankRowHeight,
                this.panelWidth
            );
        }

        this.setRankGridLinePosition(
            "RankGridCenter",
            this.panelWidth / 2,
            27,
            1
        );
    }

    /**
     * 順位領域の上端位置を取得する。
     *
     * @return パネル上端からのY位置。
     */
    int getRankGridTopOffset() {
        return this.rankTopOffset - 3;
    }

    /**
     * 罫線を右上基準の固定座標へ配置する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromRightOffset パネル右端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromWidth 罫線の横幅。
     */
    void setRankGridLinePosition(
        string fromNameSuffix,
        int fromRightOffset,
        int fromTopOffset,
        int fromWidth
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        ObjectSetInteger(
            this.chartId,
            objectName,
            OBJPROP_XDISTANCE,
            this.xDistance + fromRightOffset + fromWidth
        );
        ObjectSetInteger(
            this.chartId,
            objectName,
            OBJPROP_YDISTANCE,
            this.yDistance + fromTopOffset
        );
    }

    /**
     * 実際に採用されたDB取得元を表示する。
     *
     * @param fromSourceMode LIVEまたはTESTER。
     */
    void updateSourceBadge(const string fromSourceMode) {
        string sourceMode = fromSourceMode;
        StringToUpper(sourceMode);

        if (sourceMode == "LIVE") {
            this.setLabelText("SourceBadge", "LIVE", clrLime);

            return;
        }

        if (sourceMode == "TESTER") {
            this.setLabelText("SourceBadge", "TESTER", this.warningColor);

            return;
        }

        if (sourceMode == "") {
            sourceMode = "-";
        }

        this.setLabelText("SourceBadge", sourceMode, this.mutedColor);
    }

    /**
     * 長中期と中短期の方向一致、READY／WATCHと各期間の理由を表示する。
     * 順位差基準は4固定とし、古い順位・取得エラーでは方向だけを表示する。
     *
     * @param fromInfo 取得済みの実行時通貨強弱情報。
     * @param fromError 取得エラーにより前回の順位を表示する場合true。
     * @return 判定表示に成功した場合true。
     */
    bool updateDecision(
        const CurrencyStrengthExecutionInfo &fromInfo,
        const bool fromError = false
    ) {
        int longMediumDifference = fromInfo.getLongMediumRankDifference();
        int mediumShortDifference = fromInfo.getMediumShortRankDifference();
        string decisionText = "MIXED";
        color decisionColor = this.warningColor;
        bool directionAligned = false;
        if (longMediumDifference > 0 && mediumShortDifference > 0) {
            decisionText = "BUY一致";
            decisionColor = this.buyColor;
            directionAligned = true;
        } else if (longMediumDifference < 0 && mediumShortDifference < 0) {
            decisionText = "SELL一致";
            decisionColor = this.sellColor;
            directionAligned = true;
        }

        if (fromError) {
            return this.setDecision(decisionText, this.mutedColor,
                "ERROR：前回の順位を表示しています。READY／WATCHは判定しません。");
        }

        string tooltip = "通貨強弱のみの判定（順位差基準4）。";
        bool currentRanks = fromInfo.targetM5BarTime > 0 && fromInfo.isExactM5Bar();
        if (!currentRanks) {
            tooltip += "\n対象M5時刻と一致する順位を未取得のため、READY／WATCHは判定しません。"
                + "\n以下は表示中の順位による参考情報です。";
            decisionColor = this.mutedColor;
        } else if (directionAligned) {
            int longMediumDirection = CurrencyStrengthRankAndSignal::getLongMediumDirection(
                fromInfo.pairRankInfo.baseLongMediumTermAverageRank,
                fromInfo.pairRankInfo.quoteLongMediumTermAverageRank,
                4
            );
            if (longMediumDirection != 0 && MathAbs(mediumShortDifference) >= 4) {
                decisionText += "｜READY";
                tooltip += "\nREADY：両期間の方向と順位条件が成立。";
            } else {
                decisionText += "｜WATCH";
                decisionColor = this.warningColor;
                tooltip += "\nWATCH：両期間の方向は一致、順位条件は未達。";
            }
        } else if (longMediumDifference == 0 || mediumShortDifference == 0) {
            tooltip += "\nMIXED：同順位の期間があり、両期間の方向は一致していません。";
        } else {
            tooltip += "\nMIXED：長中期と中短期の方向が逆です。";
        }

        tooltip += "\n" + this.getPeriodDecisionTooltip(fromInfo.pairRankInfo, true)
            + "\n" + this.getPeriodDecisionTooltip(fromInfo.pairRankInfo, false);

        return this.setDecision(decisionText, decisionColor, tooltip);
    }

    /**
     * 指定期間の順位・方向と、成立または未達の理由を取得する。
     *
     * @param fromInfo 表示する通貨ペア順位。
     * @param fromLongMedium 長中期の端順位OR条件を使用する場合true。
     * @return 期間名、順位差、条件達成状況の説明。
     */
    string getPeriodDecisionTooltip(
        const CurrencyStrengthPairRankInfo &fromInfo,
        const bool fromLongMedium
    ) {
        string periodLabel = "長中期";
        int baseRank = fromInfo.baseLongMediumTermAverageRank;
        int quoteRank = fromInfo.quoteLongMediumTermAverageRank;
        if (!fromLongMedium) {
            periodLabel = "中短期";
            baseRank = fromInfo.baseMediumShortTermAverageRank;
            quoteRank = fromInfo.quoteMediumShortTermAverageRank;
        }

        int difference = quoteRank - baseRank;
        string tooltip = periodLabel + "：" + this.formatSignal(difference)
            + StringFormat("（%s %d位／%s %d位）",
                fromInfo.baseCurrency, baseRank, fromInfo.quoteCurrency, quoteRank);
        if (difference == 0) {
            return tooltip + "\n未達：同順位です。";
        }

        if (MathAbs(difference) >= 4) {
            return tooltip + "\n成立：順位差4以上。";
        }

        if (fromLongMedium
                && CurrencyStrengthRankAndSignal::getLongMediumDirection(baseRank, quoteRank, 4) != 0) {
            string strongCurrency = fromInfo.baseCurrency;
            string weakCurrency = fromInfo.quoteCurrency;
            int strongRank = baseRank;
            if (difference < 0) {
                strongCurrency = fromInfo.quoteCurrency;
                weakCurrency = fromInfo.baseCurrency;
                strongRank = quoteRank;
            }

            if (strongRank == 1) {
                return tooltip + "\n成立：買う通貨" + strongCurrency + "が1位。";
            }

            return tooltip + "\n成立：売る通貨" + weakCurrency + "が8位。";
        }

        if (fromLongMedium) {
            return tooltip + "\n未達：差4未満で、強い通貨1位・弱い通貨8位にも該当しません。";
        }

        return tooltip + "\n未達：順位差4まであと" + (string)(4 - (int)MathAbs(difference)) + "。";
    }

    /**
     * 判定ラベルの文字・色・理由を変更時だけ反映する。
     * 失敗時はキャッシュを確定せず、次回に全項目を再試行する。
     *
     * @param fromText 表示する判定文字。
     * @param fromColor 判定色。
     * @param fromTooltip 判定理由。
     * @return 全項目の反映に成功した場合true。
     */
    bool setDecision(const string fromText, const color fromColor, const string fromTooltip) {
        bool initializeProperties = !this.decisionReady;
        this.decisionReady = false;
        string objectName = this.objectPrefix + "Decision";
        if (initializeProperties || this.lastDecisionText != fromText) {
            if (!ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText)) {
                return false;
            }
        }

        if (initializeProperties || this.lastDecisionColor != fromColor) {
            if (!ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor)) {
                return false;
            }
        }

        if (initializeProperties || this.lastDecisionTooltip != fromTooltip) {
            if (!ObjectSetString(this.chartId, objectName, OBJPROP_TOOLTIP, fromTooltip)) {
                return false;
            }
        }

        this.lastDecisionText = fromText;
        this.lastDecisionColor = fromColor;
        this.lastDecisionTooltip = fromTooltip;
        this.decisionReady = true;

        return true;
    }

    /**
     * 順位差を売買方向表示へ変換する。
     *
     * @param fromDifference 決済通貨順位から基軸通貨順位を引いた値。
     * @return BUY、SELLまたはFLATと順位差。
     */
    string formatSignal(const int fromDifference) {
        if (fromDifference > 0) {
            return StringFormat("BUY +%d", fromDifference);
        }

        if (fromDifference < 0) {
            return StringFormat("SELL %d", fromDifference);
        }

        return "FLAT 0";
    }

    /**
     * 順位差に対応する文字色を取得する。
     *
     * @param fromDifference 順位差。
     * @return 売買方向に対応する文字色。
     */
    color getSignalColor(const int fromDifference) {
        if (fromDifference > 0) {
            return this.buyColor;
        }

        if (fromDifference < 0) {
            return this.sellColor;
        }

        return this.mutedColor;
    }

    /**
     * 期間列内の2通貨を実際の順位位置へ表示する。
     *
     * @param fromBaseLabelName 基軸通貨ラベル名。
     * @param fromQuoteLabelName 決済通貨ラベル名。
     * @param fromColumnCenter 期間列の中心X位置。
     * @param fromBaseCurrency 基軸通貨コード。
     * @param fromBaseRank 基軸通貨順位。
     * @param fromQuoteCurrency 決済通貨コード。
     * @param fromQuoteRank 決済通貨順位。
     */
    void updateRankColumn(
        const string fromBaseLabelName,
        const string fromQuoteLabelName,
        const int fromColumnCenter,
        const string fromBaseCurrency,
        const int fromBaseRank,
        const string fromQuoteCurrency,
        const int fromQuoteRank
    ) {
        bool sameRank = this.isValidRank(fromBaseRank)
            && this.isValidRank(fromQuoteRank)
            && fromBaseRank == fromQuoteRank;

        this.setLabelText(
            fromBaseLabelName,
            this.formatRankEntry(fromBaseCurrency, fromBaseRank, sameRank),
            ConstantCurrency::getColor(fromBaseCurrency)
        );
        this.setLabelText(
            fromQuoteLabelName,
            this.formatRankEntry(fromQuoteCurrency, fromQuoteRank, sameRank),
            ConstantCurrency::getColor(fromQuoteCurrency)
        );

        this.positionRankColumn(
            fromBaseLabelName,
            fromQuoteLabelName,
            fromColumnCenter,
            fromBaseRank,
            fromQuoteRank
        );
    }

    /**
     * 期間列内の2通貨を順位に対応する座標へ配置する。
     *
     * @param fromBaseLabelName 基軸通貨ラベル名。
     * @param fromQuoteLabelName 決済通貨ラベル名。
     * @param fromColumnCenter 期間列の中心X位置。
     * @param fromBaseRank 基軸通貨順位。
     * @param fromQuoteRank 決済通貨順位。
     */
    void positionRankColumn(
        const string fromBaseLabelName,
        const string fromQuoteLabelName,
        const int fromColumnCenter,
        const int fromBaseRank,
        const int fromQuoteRank
    ) {
        bool baseRankValid = this.isValidRank(fromBaseRank);
        bool quoteRankValid = this.isValidRank(fromQuoteRank);
        int baseCenterOffset = fromColumnCenter;
        int quoteCenterOffset = fromColumnCenter;
        int baseTopOffset = this.rankTopOffset;
        int quoteTopOffset = this.rankTopOffset + this.rankRowHeight;

        if (baseRankValid) {
            baseTopOffset = this.getRankTopOffset(fromBaseRank);
        }

        if (quoteRankValid) {
            quoteTopOffset = this.getRankTopOffset(fromQuoteRank);
        }

        if (baseRankValid
                && quoteRankValid
                && fromBaseRank == fromQuoteRank) {
            // 文字サイズと実順位の高さを保ち、中央に接続線の通路を確保する。
            int groupOffset = -8;
            if (fromColumnCenter > this.panelWidth / 2) {
                groupOffset = 8;
            }

            int halfDistance = this.panelWidth / 8 - 3;
            baseCenterOffset = fromColumnCenter + groupOffset - halfDistance;
            quoteCenterOffset = fromColumnCenter + groupOffset + halfDistance;
        }

        this.setLabelPosition(
            fromBaseLabelName,
            baseCenterOffset,
            baseTopOffset
        );
        this.setLabelPosition(
            fromQuoteLabelName,
            quoteCenterOffset,
            quoteTopOffset
        );
    }

    /**
     * 保存済み順位を使用して2期間の順位列を再配置する。
     */
    void repositionRankColumns() {
        if (this.lastDisplayAvailable) {
            CurrencyStrengthPairRankInfo pairRankInfo =
                this.lastExecutionInfo.pairRankInfo;

            this.updateRankColumn(
                "BaseLongMediumRank",
                "QuoteLongMediumRank",
                this.getColumnCenter(true),
                pairRankInfo.baseCurrency,
                pairRankInfo.baseLongMediumTermAverageRank,
                pairRankInfo.quoteCurrency,
                pairRankInfo.quoteLongMediumTermAverageRank
            );
            this.updateRankColumn(
                "BaseMediumShortRank",
                "QuoteMediumShortRank",
                this.getColumnCenter(false),
                pairRankInfo.baseCurrency,
                pairRankInfo.baseMediumShortTermAverageRank,
                pairRankInfo.quoteCurrency,
                pairRankInfo.quoteMediumShortTermAverageRank
            );

            return;
        }

        this.updateRankColumn(
            "BaseLongMediumRank",
            "QuoteLongMediumRank",
            this.getColumnCenter(true),
            this.lastBaseCurrency,
            0,
            this.lastQuoteCurrency,
            0
        );
        this.updateRankColumn(
            "BaseMediumShortRank",
            "QuoteMediumShortRank",
            this.getColumnCenter(false),
            this.lastBaseCurrency,
            0,
            this.lastQuoteCurrency,
            0
        );
    }

    /**
     * 期間列の中心位置を取得する。
     *
     * @param fromLongMedium 長中期列の場合true。
     * @return パネル左端からの中心X位置。
     */
    int getColumnCenter(const bool fromLongMedium) {
        if (fromLongMedium) {
            return this.panelWidth / 4;
        }

        return this.panelWidth * 3 / 4;
    }

    /**
     * 指定順位のパネル上端からの位置を取得する。
     *
     * @param fromRank 1位から8位。
     * @return 順位に対応するY位置。
     */
    int getRankTopOffset(const int fromRank) {
        return this.rankTopOffset + (fromRank - 1) * this.rankRowHeight;
    }

    /**
     * M5時刻のパネル上端からの位置を取得する。
     *
     * @return M5時刻のY位置。
     */
    int getM5BarTimeTopOffset() {
        return this.rankTopOffset + 8 * this.rankRowHeight + 3;
    }

    /**
     * M5時刻の値を時計と同じ左位置へ揃える。
     *
     * @return M5時刻のX位置。
     */
    int getM5BarTimeLeftOffset() {
        return DrawZigZagElliotInfoLayout::getTimeValueLeftOffset();
    }

    /**
     * 投票ウェイト方式の値を時計と同じ左位置へ揃える。
     *
     * @return 投票ウェイト方式のX位置。
     */
    int getModeBadgeLeftOffset() {
        return DrawZigZagElliotInfoLayout::getTimeValueLeftOffset();
    }

    /**
     * 投票ウェイト方式をM5時刻の次の行へ配置する。
     *
     * @return 投票ウェイト方式のY位置。
     */
    int getModeBadgeTopOffset() {
        return this.getM5BarTimeTopOffset() + 24;
    }

    /**
     * 表示可能な通貨順位か判定する。
     *
     * @param fromRank 通貨順位。
     * @return 1位から8位の場合true。
     */
    bool isValidRank(const int fromRank) {
        return fromRank >= 1 && fromRank <= 8;
    }

    /**
     * 通貨コードと順位をコンパクトな表示文字列へ変換する。
     *
     * @param fromCurrency 通貨コード。
     * @param fromRank 順位。
     * @param fromCompact 同順位の横並び表示では空白を省略する。
     * @return 通貨コードと順位。未取得順位の場合はハイフン。
     */
    string formatRankEntry(
        const string fromCurrency,
        const int fromRank,
        const bool fromCompact = false
    ) {
        string currency = fromCurrency;

        if (currency == "") {
            currency = "-";
        }

        if (!this.isValidRank(fromRank)) {
            return currency + " -";
        }

        string separator = " ";
        if (fromCompact) {
            separator = "";
        }

        return currency + separator + IntegerToString(fromRank) + "位";
    }

    /**
     * M5バー時刻を時計と共通の年月日・時分秒形式へ変換する。
     *
     * @param fromInfo 通貨ペア順位情報。
     * @return サーバー時刻の年月日と時分秒。未取得の場合はハイフン。
     */
    string formatM5BarTime(CurrencyStrengthPairRankInfo &fromInfo) {
        if (fromInfo.m5BarTime <= 0) {
            return "-";
        }

        return TimeUtil::formatYyyymmddhhmiss(fromInfo.m5BarTime);
    }

    /**
     * 固定位置ラベルを生成する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     * @param fromFontSize フォントサイズ。
     * @param fromColor 文字色。
     * @param fromText 表示文字列。
     * @param fromAnchor ラベルの配置基準点。
     * @return 生成に成功した場合true。
     */
    bool createLabel(
        string fromNameSuffix,
        int fromLeftOffset,
        int fromTopOffset,
        int fromFontSize,
        color fromColor,
        string fromText,
        ENUM_ANCHOR_POINT fromAnchor = ANCHOR_LEFT_UPPER
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        if (!ObjectCreate(this.chartId, objectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        ObjectSetInteger(this.chartId, objectName, OBJPROP_CORNER, this.corner);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, fromAnchor);
        this.setLabelPosition(fromNameSuffix, fromLeftOffset, fromTopOffset);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, fromFontSize);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
        ObjectSetString(this.chartId, objectName, OBJPROP_FONT, this.fontName);
        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_HIDDEN, true);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_ZORDER, 2);

        return true;
    }

    /**
     * 共通情報欄の処理時間表示の下へ配置し、予約領域と重なる場合だけ下へ移す。
     * 明示された予約領域には従来の下部余白条件を適用する。
     */
    void calculateYDistance() {
        int chartHeight = (int)ChartGetInteger(
            this.chartId,
            CHART_HEIGHT_IN_PIXELS,
            0
        );
        this.yDistance = DrawZigZagElliotInfoLayout::getStrengthTop();

        if (!this.reservedAreaEnabled
                || this.reservedTop >= chartHeight
                || this.reservedBottom <= 0
                || this.yDistance >= this.reservedBottom
                || this.yDistance + this.panelHeight <= this.reservedTop) {
            return;
        }

        int chartWidth = (int)ChartGetInteger(this.chartId, CHART_WIDTH_IN_PIXELS, 0);
        if (chartWidth <= 0 || this.reservedLeft >= chartWidth || this.reservedRight <= 0) {
            return;
        }

        int panelLeft = chartWidth - this.xDistance - this.panelWidth;
        int panelRight = chartWidth - this.xDistance;
        if (panelLeft >= this.reservedRight || panelRight <= this.reservedLeft) {
            return;
        }

        int nextYDistance = this.reservedBottom + 8;
        // 最も上にある下部操作ボタンまでの75pxを確保する。
        int bottomControlHeight = 75;
        if (nextYDistance + this.panelHeight <= chartHeight - bottomControlHeight) {
            this.yDistance = nextYDistance;
        }
    }

    /**
     * 文字ラベルをパネル基準位置へ配置する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromLeftOffset パネル左端からの位置。
     * @param fromTopOffset パネル上端からの位置。
     */
    void setLabelPosition(
        string fromNameSuffix,
        int fromLeftOffset,
        int fromTopOffset
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;
        int labelXDistance = DrawZigZagElliotInfoLayout::getXDistance(
            this.xDistance, fromLeftOffset);

        ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, labelXDistance);
        ObjectSetInteger(
            this.chartId,
            objectName,
            OBJPROP_YDISTANCE,
            this.yDistance + fromTopOffset
        );
    }

    /**
     * ラベル文字列と文字色を更新する。
     *
     * @param fromNameSuffix オブジェクト名の末尾。
     * @param fromText 表示文字列。
     * @param fromColor 文字色。
     */
    void setLabelText(
        string fromNameSuffix,
        string fromText,
        color fromColor
    ) {
        string objectName = this.objectPrefix + fromNameSuffix;

        ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, fromText);
        ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, fromColor);
    }

    /**
     * 順位パネル専用オブジェクトを削除する。
     */
    void destroyObjects() {
        this.connectionCanvas.Destroy();
        this.connectionsReady = false;
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.decisionReady = false;
        this.hasRankData = false;
    }

    /**
     * 旧版の共通プレフィックスで保存された順位パネルを削除する。
     */
    void destroyLegacyObjects() {
        ObjectsDeleteAll(
            this.chartId,
            Constant::PREFIX_FIXED + "CurrencyStrengthPairRank_",
            0,
            -1
        );
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_PAIR_RANK_MQH
