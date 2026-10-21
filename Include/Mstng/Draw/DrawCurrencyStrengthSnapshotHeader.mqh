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
#include <Mstng\Util\TimeJapanUtil.mqh>

/**
 * 通貨強弱の各パネルで共通する集計対象時刻を固定位置に表示する。
 * 同一のサーバー時刻をJSTとSERVERの1行で表示する。
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
        this.height = 24;
        this.created = false;

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
                displayText = "集計待ち：日時未取得";
                if (fromSnapshotTime > 0) {
                    displayText = "集計対象：JST "
                        + TimeToString(
                            TimeJapanUtil::getJapanTime(fromSnapshotTime),
                            TIME_DATE | TIME_MINUTES
                        )
                        + " ｜ SERVER "
                        + TimeToString(fromSnapshotTime, TIME_DATE | TIME_MINUTES);
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

        ChartRedraw(this.chartId);

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
        ChartRedraw(this.chartId);
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

    /** ヘッダー高さ。 */
    int height;

    /** 描画オブジェクト生成済みの場合true。 */
    bool created;

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
            && ObjectSetString(this.chartId, fromObjectName, OBJPROP_TOOLTIP, "\n");
    }

    /**
     * 途中生成の失敗時も含めて所有する全オブジェクトを解放する。
     */
    void destroyObjects() {
        ObjectsDeleteAll(this.chartId, this.objectPrefix, 0, -1);
        this.created = false;
    }
};

#endif // MSTNG_DRAW_CURRENCY_STRENGTH_SNAPSHOT_HEADER_MQH
