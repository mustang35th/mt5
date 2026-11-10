//+------------------------------------------------------------------+
//|                        DrawCurrencyStrengthSnapshotHeader.mqh     |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_DRAW_CURRENCY_STRENGTH_SNAPSHOT_HEADER_MQH
#define MSTNG_DRAW_CURRENCY_STRENGTH_SNAPSHOT_HEADER_MQH

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Draw\DrawChartRedrawBatch.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 通貨強弱の各パネルで共通する集計対象時刻を固定位置に表示する。
 * 同一のサーバー時刻を秒までのJSTとSRVの1行で表示する。
 */
class DrawCurrencyStrengthSnapshotHeader {
public:
    /**
     * 共通日時ヘッダーの表示位置と幅を指定して初期化する。
     *
     * @param fromChartId 描画対象チャートID。0の場合はカレント。
     * @param fromXDistance チャート左端からの距離。
     * @param fromYDistance チャート上端からの距離。
     * @param fromWidth ヘッダーの幅。
     * @param fromInstanceKey 同一チャート内のインスタンス識別子。
     */
    DrawCurrencyStrengthSnapshotHeader(
        long fromChartId,
        int fromXDistance,
        int fromYDistance,
        int fromWidth,
        string fromInstanceKey = ""
    ) {
        this.chartId = fromChartId;
        this.xDistance = fromXDistance;
        this.yDistance = fromYDistance;
        this.width = fromWidth;
        this.appliedWidth = 0;
        this.height = 24;
        this.created = false;
        this.timingTooltip = "\n";
        this.appliedTimingTooltip = "";

        // オブジェクト名の63文字制限内に識別子と連番を収める。
        string baseObjectPrefix = Constant::PREFIX_FIXED + "CurrencySnapshot_";
        if (fromInstanceKey != "") {
            baseObjectPrefix += StringSubstr(fromInstanceKey, 0, 12) + "_";
        }

        // 描画前に複数生成された場合にも名前を重複させない。
        static int nextInstanceIndex = 0;
        int instanceIndex = nextInstanceIndex;
        this.objectPrefix = baseObjectPrefix + IntegerToString(instanceIndex) + "_";
        while (ObjectFind(this.chartId, this.objectPrefix + "Panel") >= 0
                || ObjectFind(this.chartId, this.objectPrefix + "Text") >= 0) {
            instanceIndex++;
            this.objectPrefix = baseObjectPrefix + IntegerToString(instanceIndex) + "_";
        }

        nextInstanceIndex = instanceIndex + 1;
    }

    /**
     * 所有する描画オブジェクトを解放する。
     */
    ~DrawCurrencyStrengthSnapshotHeader() {
        this.destroyObjects();
    }

    /**
     * 完全集計時は対象日時、それ以外は集計待ちの状態を表示する。
     *
     * @param fromSnapshotTime 集計対象のサーバー時刻。
     * @param fromValidPairCount 集計できた通貨ペア数。
     * @param fromExpectedPairCount 集計に必要な通貨ペア数。
     * @return 描画に成功した場合true。集計待ちは正常表示としてtrue。
     */
    bool draw(
        datetime fromSnapshotTime,
        int fromValidPairCount,
        int fromExpectedPairCount
    ) {
        if (!this.created && !this.create()) {
            return false;
        }

        string displayText = "集計待ち：件数未確定";
        color displayColor = clrYellow;
        if (fromExpectedPairCount > 0
                && fromValidPairCount >= 0
                && fromValidPairCount <= fromExpectedPairCount) {
            displayText = StringFormat(
                "集計待ち：%d/%dペア",
                fromValidPairCount,
                fromExpectedPairCount
            );
            if (fromValidPairCount == fromExpectedPairCount) {
                displayText = "集計対象：—（取得待ち）";
                if (fromSnapshotTime > 0) {
                    displayText = "集計対象："
                        + TimeUtil::formatYyyymmddhhmiss(
                            TimeJapanUtil::getJapanTime(fromSnapshotTime)
                        )
                        + " JST ｜ "
                        + TimeUtil::formatYyyymmddhhmiss(fromSnapshotTime) + " SRV";
                    displayColor = clrWhiteSmoke;
                }
            }
        }

        string objectName = this.objectPrefix + "Text";
        if (!ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, displayText)
                || !ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, displayColor)) {
            this.destroyObjects();

            return false;
        }

        DrawChartRedrawBatch::request(this.chartId);

        return true;
    }

    /**
     * 集計の計測値を既存ヘッダーの説明へ反映する。
     * 同じ説明文の再設定と追加の再描画は行わず、未生成時も次回生成用に保持する。
     *
     * @param fromTooltip 表示する計測値の説明。
     * @return 生成済みの両オブジェクトへ反映できた場合true。
     */
    bool updateTimingTooltip(const string fromTooltip) {
        this.timingTooltip = fromTooltip;
        if (!this.created) {
            return false;
        }

        if (this.appliedTimingTooltip == this.timingTooltip) {
            return true;
        }

        if (!ObjectSetString(this.chartId, this.objectPrefix + "Panel", OBJPROP_TOOLTIP, this.timingTooltip)
                || !ObjectSetString(this.chartId, this.objectPrefix + "Text", OBJPROP_TOOLTIP, this.timingTooltip)) {
            return false;
        }

        this.appliedTimingTooltip = this.timingTooltip;

        return true;
    }

    /**
     * パネルの開閉に合わせて背景幅を更新する。
     * 日時と診断説明は維持し、同じ幅の再設定を省く。
     *
     * @param fromWidth 更新後の幅。
     * @return 幅を保持し、生成済みなら反映できた場合true。
     */
    bool setWidth(const int fromWidth) {
        if (fromWidth <= 0) {
            return false;
        }

        this.width = fromWidth;
        if (!this.created || this.appliedWidth == this.width) {
            return true;
        }

        if (!ObjectSetInteger(this.chartId, this.objectPrefix + "Panel", OBJPROP_XSIZE, this.width)) {
            return false;
        }

        this.appliedWidth = this.width;
        DrawChartRedrawBatch::request(this.chartId);

        return true;
    }

    /**
     * 共通日時ヘッダーの固定高さを取得する。
     *
     * @return ピクセル単位の高さ。
     */
    int getHeight() const {
        return this.height;
    }

    /**
     * 共通日時ヘッダーの専用オブジェクトを削除する。
     */
    void clear() {
        this.destroyObjects();
        DrawChartRedrawBatch::request(this.chartId);
    }

    /**
     * 保存チャートなどに残った別採番の共通日時欄を除去する。
     * 呼び出し側で、初期化後に同系統インジケーターの単独配置を確認すること。
     *
     * @return 旧描画の除去に成功した場合true。
     */
    bool clearOtherInstances() {
        string familyPrefix = Constant::PREFIX_FIXED + "CurrencySnapshot_";
        bool succeeded = true;
        bool changed = false;
        int total = ObjectsTotal(this.chartId, 0, -1);
        if (total < 0) {
            return false;
        }

        for (int i = total - 1; i >= 0; i--) {
            string objectName = ObjectName(this.chartId, i, 0, -1);
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

private:
    /** 描画対象チャートID。 */
    long chartId;

    /** 専用オブジェクト名プレフィックス。 */
    string objectPrefix;

    /** ヘッダー左位置。 */
    int xDistance;

    /** ヘッダー上位置。 */
    int yDistance;

    /** ヘッダー幅。 */
    int width;

    /** 生成済み背景へ反映した幅。失敗時は更新せず次回再試行する。 */
    int appliedWidth;

    /** ヘッダー高さ。 */
    int height;

    /** 描画オブジェクト生成済みの場合true。 */
    bool created;

    /** 次回生成・反映時にも使用する診断説明。 */
    string timingTooltip;

    /** 両オブジェクトへ反映済みの診断説明。 */
    string appliedTimingTooltip;

    /**
     * 固定背景と日時ラベルを生成する。
     *
     * @return 全オブジェクトを生成できた場合true。
     */
    bool create() {
        this.destroyObjects();
        if (this.width <= 0) {
            return false;
        }

        if (!this.createPanel() || !this.createText()) {
            this.destroyObjects();

            return false;
        }

        this.created = true;
        this.appliedWidth = this.width;
        this.appliedTimingTooltip = this.timingTooltip;

        return true;
    }

    /**
     * ヘッダーの背景と枠を生成する。
     *
     * @return 背景を生成できた場合true。
     */
    bool createPanel() {
        string objectName = this.objectPrefix + "Panel";
        if (!ObjectCreate(this.chartId, objectName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
            return false;
        }

        return this.configureObject(objectName, 0)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, this.xDistance)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_XSIZE, this.width)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_YSIZE, this.height)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_BGCOLOR, C'18,18,18')
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_BORDER_TYPE, BORDER_FLAT)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, clrDimGray);
    }

    /**
     * 集計対象日時を表示する文字ラベルを生成する。
     *
     * @return ラベルを生成できた場合true。
     */
    bool createText() {
        string objectName = this.objectPrefix + "Text";
        if (!ObjectCreate(this.chartId, objectName, OBJ_LABEL, 0, 0, 0)) {
            return false;
        }

        return this.configureObject(objectName, 1)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_XDISTANCE, this.xDistance + 14)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_YDISTANCE, this.yDistance + 4)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_FONTSIZE, 10)
            && ObjectSetInteger(this.chartId, objectName, OBJPROP_COLOR, clrYellow)
            && ObjectSetString(this.chartId, objectName, OBJPROP_FONT, "MS Gothic")
            && ObjectSetString(this.chartId, objectName, OBJPROP_TEXT, "集計待ち");
    }

    /**
     * チャートの移動や拡縮から独立したオブジェクト属性を設定する。
     *
     * @param fromObjectName 対象オブジェクト名。
     * @param fromZOrder クリックの優先度。
     * @return 属性を設定できた場合true。
     */
    bool configureObject(const string fromObjectName, const int fromZOrder) {
        return ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_CORNER, CORNER_LEFT_UPPER)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_BACK, false)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTABLE, false)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_SELECTED, false)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_HIDDEN, true)
            && ObjectSetInteger(this.chartId, fromObjectName, OBJPROP_ZORDER, fromZOrder)
            && ObjectSetString(this.chartId, fromObjectName, OBJPROP_TOOLTIP, this.timingTooltip);
    }

    /**
     * 途中生成の失敗時も含めて所有する全オブジェクトを解放する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
        this.appliedWidth = 0;
        this.appliedTimingTooltip = "";
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_SNAPSHOT_HEADER_MQH
