//+------------------------------------------------------------------+
//|                                                   DrawZigZag.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Draw\DrawBase.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>

/**
 * ZigZagラインを描画するクラス。
 */
class DrawZigZag : public DrawBase {
public:

    /**
     * デフォルトコンストラクタ。
     */
    DrawZigZag() {
    }

    /**
     * 市場コンテキストを指定して初期化する。
     *
     * @param fromMarketContext 描画対象の市場コンテキスト。
     */
    DrawZigZag(MarketContext &fromMarketContext) {
        this.initializeMarketContext(fromMarketContext);
    }

    /**
     * デストラクタ。
     */
    ~DrawZigZag() {
    }

    /**
     * Elliot全体のZigZagを描画する。
     *
     * @param fromElliotAll Elliot解析結果。
     */
    void draw(ElliotAll &fromElliotAll) {
        this.initializeMarketContext(fromElliotAll.marketContext);

        Elliot *elliot = fromElliotAll.getElliot(fromElliotAll.marketContext.timeFrame);

        if (elliot != NULL) {
            // 現在足の詳細線を描画した後、メイン波の開始点間を太線で重ねる。
            this.draw(elliot, false, 1);
            this.drawElliotWaveStartLines(elliot, 2);
        }

        // 上位足を最後に作成し、ZigZagラインの最前列へ描画する。
        if (fromElliotAll.marketContext.timeFrame < PERIOD_MN1) {
            Elliot *elliotHigher = fromElliotAll.getElliot(fromElliotAll.marketContext.timeFrame, 1);

            if (elliotHigher != NULL) {
                this.draw(elliotHigher, true, 3, true);
            }
        }
    }

private:
    /**
     * ZigZagポイント間を結ぶラインを描画する。
     *
     * @param elliot 描画対象のElliot。
     * @param isOrg オリジナルZigZagを使う場合true。
     * @param lineSize ライン幅。
     * @param isUpper 上位足描画の場合true。
     */
    void draw(Elliot &elliot, bool isOrg, int lineSize, bool isUpper = false) {
        LogUtil::printMethodStart(this.logger, __FUNCTION__);

        this.logger.debug(__FUNCTION__, StringFormat("elliot = %s", elliot.toString()));
        this.logger.debug(__FUNCTION__, StringFormat("isOrg = %s", (string)isOrg));
        this.logger.debug(__FUNCTION__, StringFormat("lineSize = %d", lineSize));
        this.logger.debug(__FUNCTION__, StringFormat("isUpper = %s", (string)isUpper));

        string preObjectName;
        StringConcatenate(preObjectName, "ZigZag", elliot.marketContext.timeFrameLabel);

        CArrayObj *waveList = &(elliot.waveList);
        int waveListTotal = waveList.Total();

        this.logger.debug(__FUNCTION__, StringFormat("waveListTotal = %d", waveListTotal));

        for (int i = 0; i < waveListTotal; i++) {
            Wave *wave = waveList.At(i);
            CArrayObj *zigZagPointList;

            if (isOrg && elliot.marketContext.timeFrame != PERIOD_MN1) {
                zigZagPointList = &(wave.orgZigZagPointList);
            } else {
                zigZagPointList = &(wave.zigZagPointList);
            }

            LogUtil::printZigZagPointList(this.logger, __FUNCTION__, zigZagPointList);

            int zigZagPointCount = zigZagPointList.Total();

            for (int j = 0; j < zigZagPointCount - 1; j++) {
                string objectName;
                StringConcatenate(
                    objectName,
                    preObjectName,
                    "_i",
                    StringUtil::zeroPadding(i, 2),
                    "_j",
                    StringUtil::zeroPadding(j, 2)
                );

                this.logger.debug(__FUNCTION__, objectName);

                ZigZagPoint *zigZagPointFrom = zigZagPointList.At(j);
                ZigZagPoint *zigZagPointTo = zigZagPointList.At(j + 1);

                double rateFrom = zigZagPointFrom.rate;
                double rateTo = zigZagPointTo.rate;
                bool isBuy = this.isBuy(rateFrom, rateTo);
                color lineColor = this.getLineColor(isBuy, isUpper);
                datetime datetimeFrom = zigZagPointFrom.barTime;
                datetime datetimeTo = zigZagPointTo.barTime;

                if (isUpper) {
                    datetimeFrom = this.getDatetime(elliot.marketContext.timeFrame, datetimeFrom, rateFrom, isBuy, true);
                    datetimeTo = this.getDatetime(elliot.marketContext.timeFrame, datetimeTo, rateTo, isBuy, false);
                }

                DrawUtil::setTrendLine(
                    objectName,
                    datetimeFrom,
                    rateFrom,
                    datetimeTo,
                    rateTo,
                    lineColor,
                    STYLE_SOLID,
                    lineSize,
                    false
                );
            }
        }

        LogUtil::printMethodEnd(this.logger, __FUNCTION__, true);
    }

    /**
     * 現在足のElliott波動について、隣接するメイン波の開始点間を描画する。
     *
     * 1の開始点から2の開始点、2の開始点から3の開始点のように結ぶ。
     * 内部波動がある場合は、1.iや2.iで終わる線分の始点を使用する。
     * 最後の開始点から最新ポイントまでは、進行中のメイン波として描画する。
     *
     * @param elliot 描画対象のElliot。
     * @param lineSize ライン幅。
     */
    void drawElliotWaveStartLines(Elliot &elliot, int lineSize) {
        string preObjectName;
        StringConcatenate(preObjectName, "ZigZagMain", elliot.marketContext.timeFrameLabel);

        CArrayObj *waveList = &(elliot.waveList);

        for (int i = 0; i < waveList.Total(); i++) {
            Wave *wave = waveList.At(i);
            CArrayObj *zigZagPointList = &(wave.zigZagPointList);
            ZigZagPoint *waveStartPoint = NULL;
            int lineIndex = 0;

            for (int j = 0; j < zigZagPointList.Total() - 1; j++) {
                ZigZagPoint *zigZagPointFrom = zigZagPointList.At(j);
                ZigZagPoint *zigZagPointTo = zigZagPointList.At(j + 1);

                if (!this.isElliotWaveStart(zigZagPointTo)) {
                    continue;
                }

                if (waveStartPoint != NULL) {
                    this.drawElliotWaveStartLine(
                        preObjectName,
                        i,
                        lineIndex,
                        waveStartPoint,
                        zigZagPointFrom,
                        lineSize
                    );

                    lineIndex++;
                }

                waveStartPoint = zigZagPointFrom;
            }

            if (waveStartPoint != NULL && zigZagPointList.Total() > 0) {
                ZigZagPoint *latestPoint = zigZagPointList.At(zigZagPointList.Total() - 1);

                if (latestPoint != NULL
                        && (latestPoint.barTime != waveStartPoint.barTime
                            || latestPoint.rate != waveStartPoint.rate)) {
                    this.drawElliotWaveStartLine(
                        preObjectName,
                        i,
                        lineIndex,
                        waveStartPoint,
                        latestPoint,
                        lineSize
                    );
                }
            }
        }
    }

    /**
     * 2つのElliottメイン波ポイント間を描画する。
     *
     * @param fromPreObjectName オブジェクト名プレフィックス。
     * @param fromWaveIndex Wave一覧内のインデックス。
     * @param fromLineIndex Wave内のラインインデックス。
     * @param fromStartPoint ライン始点。
     * @param fromEndPoint ライン終点。
     * @param fromLineSize ライン幅。
     */
    void drawElliotWaveStartLine(
            string fromPreObjectName,
            int fromWaveIndex,
            int fromLineIndex,
            ZigZagPoint &fromStartPoint,
            ZigZagPoint &fromEndPoint,
            int fromLineSize
    ) {
        string objectName;
        StringConcatenate(
            objectName,
            fromPreObjectName,
            "_i",
            StringUtil::zeroPadding(fromWaveIndex, 2),
            "_j",
            StringUtil::zeroPadding(fromLineIndex, 2)
        );

        bool isBuy = this.isBuy(fromStartPoint.rate, fromEndPoint.rate);
        color lineColor = this.getLineColor(isBuy, false);

        DrawUtil::setTrendLine(
            objectName,
            fromStartPoint.barTime,
            fromStartPoint.rate,
            fromEndPoint.barTime,
            fromEndPoint.rate,
            lineColor,
            STYLE_SOLID,
            fromLineSize,
            false
        );
    }

    /**
     * 指定ポイントで終わる線分がElliott波動の先頭か判定する。
     *
     * 未分割の1、2、3など、または分割された1.i、3.iなどを先頭とする。
     *
     * @param fromZigZagPoint 判定対象ポイント。
     * @return Elliott波動の先頭の場合true。
     */
    bool isElliotWaveStart(ZigZagPoint &fromZigZagPoint) {
        if (fromZigZagPoint.elliotIndex == Constant::DELETE_FLG) {
            return false;
        }

        if (fromZigZagPoint.subElliotIndex == 0 || fromZigZagPoint.subElliotIndex == 1) {
            return true;
        }

        return false;
    }

    /**
     * 描画色を取得する。
     *
     * @param isBuy 上昇波の場合true。
     * @param isUpper 上位足描画の場合true。
     * @return 描画色。
     */
    color getLineColor(bool isBuy, bool isUpper) {
        if (isBuy) {
            if (isUpper) {
                return clrBlue;
            }

            return clrDodgerBlue;
        }

        if (isUpper) {
            return clrRed;
        }

        return clrMagenta;
    }

};
