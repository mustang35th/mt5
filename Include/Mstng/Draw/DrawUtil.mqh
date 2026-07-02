//+------------------------------------------------------------------+
//|                                                     DrawUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#ifndef MSTNG_DRAW_UTIL_MQH
#define MSTNG_DRAW_UTIL_MQH

#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Log\LogUtil.mqh>
//#include <Mstng\Util\UtilAll.mqh>

/**
 * チャート上の描画処理を行うユーティリティクラスです。
 * トレンドラインなど、価格と時間を指定してオブジェクトを描画する機能を提供します。
 */
class DrawUtil {
public:
    /**
     * 矢印を描画します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックス付与前）
     * @param fontColor      色
     * @param arrowCode      矢印コード
     * @param arrowWidth     幅
     * @param position       バーシフト位置
     * @param offset         価格補正
     * @param chartId        描画対象チャートID（0の場合はカレント）
     */
    static void setArrow(string fromObjectName, color fontColor,  int arrowCode, int arrowWidth, int position, double offset, int chartId = 0) {
        //string objectName = Constant::PREFIX + fromObjectName;
        string objectName = Constant::PREFIX_FIXED + fromObjectName;
        
        datetime drawDatetime = iTime(NULL, NULL, position);
        
        objectName += IntegerToString((int)drawDatetime);
        
        double drawPrice = iOpen(NULL, NULL, position) + offset;
        
        ObjectCreate(chartId, objectName, OBJ_ARROW, 0, drawDatetime, drawPrice);
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, fontColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, arrowWidth);
    }
    
    /**
     * チャート背景色を設定します。
     *
     * @param bgColor 背景色
     */
    static void setBgColor(color bgColor, int chartId = 0) {
        ChartSetInteger(chartId, CHART_COLOR_BACKGROUND, bgColor);
    }

    /**
     * 水平ラインを描画します。
     * 既に同名のオブジェクトが存在する場合は一度削除し、新たに作成します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param rate            ラインの価格
     * @param lineColor       ラインの色
     * @param lineStyle       ラインのスタイル（スタイル定数）
     * @param lineSize        ラインの太さ（ピクセル）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setHLine(string fromObjectName, double rate, color lineColor, int lineStyle, int lineSize, int chartId = 0) {
        // チャートオブジェクト名（共通プレフィックスを付与）
        string objectName = Constant::PREFIX + fromObjectName;

        // 既存の同名オブジェクトを削除してから作成
        ObjectDelete(chartId, objectName);
        ObjectCreate(chartId, objectName, OBJ_HLINE, 0, 0, rate);

        // ラインの色・スタイル・太さなどのプロパティを設定
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, lineColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_STYLE, lineStyle);
        ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, lineSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_BACK, false);
    }
    
    /**
     * ラベルを描画します。
     * 既に同名のオブジェクトが存在する場合は一度削除し、新たに作成します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param objX            X座標（ピクセル）
     * @param objY            Y座標（ピクセル）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setLabel(string fromObjectName, string fontFace, color fontColor, int fontSize, string text, int objX, int objY, int chartId = 0) {
        // チャートオブジェクト名（共通プレフィックスを付与）
        string objectName = Constant::PREFIX + fromObjectName;
        
        setLabelCommon(objectName, fontFace, fontColor, fontSize, text, objX, objY, chartId);
        
        // 既存の同名オブジェクトを削除してから作成
        /*ObjectDelete(chartId, objectName);
        ObjectCreate(chartId, objectName, OBJ_LABEL, 0, 0, 0);

        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, fontColor);
        ObjectSetString(chartId, objectName, OBJPROP_TEXT, text);
        ObjectSetString(chartId, objectName, OBJPROP_FONT, fontFace);
        ObjectSetInteger(chartId, objectName, OBJPROP_FONTSIZE, fontSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_XDISTANCE, objX);
        ObjectSetInteger(chartId, objectName, OBJPROP_YDISTANCE, objY);*/
    }
    
    /**
     * 固定プレフィックス付きでラベルを描画します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックス付与前）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param objX            X座標（px）
     * @param objY            Y座標（px）
     * @param chartId         描画対象チャートID（0の場合はカレント）
     */
    static void setLabelFixed(string fromObjectName, string fontFace, color fontColor, int fontSize, string text, int objX, int objY, int chartId = 0) {
        // チャートオブジェクト名（共通プレフィックスを付与）
        string objectName = Constant::PREFIX_FIXED + fromObjectName;
        
        setLabelCommon(objectName, fontFace, fontColor, fontSize, text, objX, objY, chartId);
    }
    
    /**
     * 固定プレフィックス付きオブジェクトを削除します。
     *
     * @param fromObjectName  削除するオブジェクト名（プレフィックスを付与する前の名称）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void deleteFixedObject(string fromObjectName, int chartId = 0) {
        string objectName = Constant::PREFIX_FIXED + fromObjectName;

        ObjectDelete(chartId, objectName);
    }
    
    /**
     * ラベル描画処理を共通化します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックス付与前）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param objX            X座標（px）
     * @param objY            Y座標（px）
     * @param chartId         描画対象チャートID（0の場合はカレント）
     */
    static void setLabelCommon(string fromObjectName, string fontFace, color fontColor, int fontSize, string text, int objX, int objY, int chartId) {
        string objectName = fromObjectName;

        // 既存の同名オブジェクトを削除してから作成
        ObjectDelete(chartId, objectName);
        ObjectCreate(chartId, objectName, OBJ_LABEL, 0, 0, 0);

        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, fontColor);
        ObjectSetString(chartId, objectName, OBJPROP_TEXT, text);
        ObjectSetString(chartId, objectName, OBJPROP_FONT, fontFace);
        ObjectSetInteger(chartId, objectName, OBJPROP_FONTSIZE, fontSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_XDISTANCE, objX);
        ObjectSetInteger(chartId, objectName, OBJPROP_YDISTANCE, objY);
    }
    
    /**
     * 矩形を描画します。
     * 既に同名のオブジェクトが存在する場合は一度削除し、新たに作成します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param time1           始点の時間
     * @param rate1           始点の価格
     * @param time2           終点の時間
     * @param rate2           終点の価格
     * @param lineColor       ラインの色
     * @param lineStyle       ラインのスタイル（スタイル定数）
     * @param lineSize        ラインの太さ（ピクセル）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setRectangle(string fromObjectName, datetime time1, double rate1, datetime time2, double rate2,
                                color lineColor, int lineStyle, int lineSize, bool isPrefix = true, int chartId = 0) {
        string objectName = "";
        
        if (isPrefix) {
            objectName += Constant::PREFIX;
        }
        
        objectName += fromObjectName;
        
        // 既存の同名オブジェクトを削除してから作成
        ObjectDelete(chartId, objectName);
        ObjectCreate(chartId, objectName, OBJ_RECTANGLE, 0, time1, rate1, time2, rate2);

        // ラインの色・スタイル・太さなどのプロパティを設定
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, lineColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_STYLE, lineStyle);
        ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, lineSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_BACK, true);
        ObjectSetInteger(chartId, objectName, OBJPROP_FILL, true);
    }

    /**
     * 指定時刻・価格にラベルを設定します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックス付与前）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param drawDatetime    表示位置の時間
     * @param drawPrice       表示位置の価格
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setText(string fromObjectName, string fontFace, color fontColor, int fontSize, string text, 
                    datetime drawDatetime, double drawPrice, int chartId = 0) {        
        string objectName = Constant::PREFIX + fromObjectName;
        
        setTextCommon(objectName, fontFace, fontColor, fontSize, text, drawDatetime, drawPrice, chartId);
    }
    
    /**
     * 固定プレフィックス付きで時刻・価格にラベルを設定します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックス付与前）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param drawDatetime    表示位置の時間
     * @param drawPrice       表示位置の価格
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setTextFixed(string fromObjectName, string fontFace, color fontColor, int fontSize, string text, 
                    datetime drawDatetime, double drawPrice, int chartId = 0) {        
        string objectName = Constant::PREFIX_FIXED + fromObjectName;
        
        setTextCommon(objectName, fontFace, fontColor, fontSize, text, drawDatetime, drawPrice, chartId);
    }
    
    /**
     * テキストを再配置して描画します。
     * 既に同名のオブジェクトが存在する場合は一度削除し、時間と価格を更新します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param drawDatetime    表示位置の時間
     * @param drawPrice       表示位置の価格
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setTextMove(string fromObjectName, string fontFace, color fontColor, int fontSize, string text,
                    datetime drawDatetime, double drawPrice, int chartId = 0) {
        string objectName = Constant::PREFIX + fromObjectName;

        setTextMoveCommon(objectName, fontFace, fontColor, fontSize, text, drawDatetime, drawPrice, chartId);
    }

    /**
     * 固定プレフィックスでテキストを再配置して描画します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param drawDatetime    表示位置の時間
     * @param drawPrice       表示位置の価格
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setTextMoveFixed(string fromObjectName, string fontFace, color fontColor, int fontSize, string text,
                    datetime drawDatetime, double drawPrice, int chartId = 0) {
        string objectName = Constant::PREFIX_FIXED + fromObjectName;

        setTextMoveCommon(objectName, fontFace, fontColor, fontSize, text, drawDatetime, drawPrice, chartId);
    }

    /**
     * テキストを再配置して描画します。
     *
     * @param objectName      プレフィックス付与後のオブジェクト名
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param drawDatetime    表示位置の時間
     * @param drawPrice       表示位置の価格
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setTextMoveCommon(string objectName, string fontFace, color fontColor, int fontSize, string text,
                    datetime drawDatetime, double drawPrice, int chartId) {
        ObjectDelete(chartId, objectName);
        ObjectCreate(chartId, objectName, OBJ_TEXT, 0, drawDatetime, drawPrice);

        ObjectSetString(chartId, objectName, OBJPROP_TEXT, text);
        ObjectSetString(chartId, objectName, OBJPROP_FONT, fontFace);
        ObjectSetInteger(chartId, objectName, OBJPROP_FONTSIZE, fontSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, fontColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(chartId, objectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(chartId, objectName, OBJPROP_ANCHOR, ANCHOR_LEFT);
    }
    
    /**
     * OBJ_TEXT を作成して共通的な文字設定を適用します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックス付与済み）
     * @param fontFace        フォント名
     * @param fontColor       文字色
     * @param fontSize        フォントサイズ
     * @param text            表示テキスト
     * @param drawDatetime    表示位置の時間
     * @param drawPrice       表示位置の価格
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setTextCommon(string fromObjectName, string fontFace, color fontColor, int fontSize, string text, 
                    datetime drawDatetime, double drawPrice, int chartId) {        
        string objectName = fromObjectName;
        
        ObjectCreate(chartId, objectName, OBJ_TEXT, 0, drawDatetime, drawPrice);
            
        ObjectSetString(chartId, objectName, OBJPROP_TEXT, text);
        ObjectSetString(chartId, objectName, OBJPROP_FONT, fontFace);
        ObjectSetInteger(chartId, objectName, OBJPROP_FONTSIZE, fontSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, fontColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(chartId, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
    }
        
    /**
     * トレンドラインを描画します。
     * 既に同名のオブジェクトが存在する場合は一度削除し、新たに作成します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param time1           始点の時間
     * @param rate1           始点の価格
     * @param time2           終点の時間
     * @param rate2           終点の価格
     * @param lineColor       ラインの色
     * @param lineStyle       ラインのスタイル（スタイル定数）
     * @param lineSize        ラインの太さ（ピクセル）
     * @param isRayRight      true の場合、右方向に延長する（レイ表示）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setTrendLine(string fromObjectName, datetime time1, double rate1, datetime time2, double rate2, 
                                color lineColor, int lineStyle, int lineSize, bool isRayRight, int chartId = 0) {
        // チャートオブジェクト名（共通プレフィックスを付与）
        string objectName = Constant::PREFIX + fromObjectName;

        // 既存の同名オブジェクトを削除してから作成
        ObjectDelete(chartId, objectName);
        ObjectCreate(chartId, objectName, OBJ_TREND, 0, time1, rate1, time2, rate2);

        // ラインの色・スタイル・太さなどのプロパティを設定
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, lineColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_STYLE, lineStyle);
        ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, lineSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_BACK, true);
        ObjectSetInteger(chartId, objectName, OBJPROP_RAY_RIGHT, isRayRight);
    }
    

    /**
     * フィボナッチエクスパンションを描画します。
     * 既に同名のオブジェクトが存在する場合は一度削除し、新たに作成します。
     * レベルは 61.8 / 100.0 / 127.2 / 161.8 / 200.0 を設定します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param time1           1点目の時間
     * @param rate1           1点目の価格
     * @param time2           2点目の時間
     * @param rate2           2点目の価格
     * @param time3           3点目の時間
     * @param rate3           3点目の価格
     * @param lineColor       ラインの色
     * @param lineStyle       ラインのスタイル（スタイル定数）
     * @param lineSize        ラインの太さ（ピクセル）
     * @param isRayRight      true の場合、右方向に延長する（レイ表示）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     * @return                作成に成功した場合 true
     */
    static bool setFibonacciExpansion(string fromObjectName, datetime time1, double rate1, datetime time2, double rate2,
                                        datetime time3, double rate3, color lineColor, int lineStyle, int lineSize,
                                        bool isRayRight = false, int chartId = 0) {
        // チャートオブジェクト名（共通プレフィックスを付与）
        string objectName = Constant::PREFIX + fromObjectName;

        // 既存の同名オブジェクトを削除してから作成
        ObjectDelete(chartId, objectName);
        ResetLastError();

        if (!ObjectCreate(chartId, objectName, OBJ_EXPANSION, 0, time1, rate1, time2, rate2, time3, rate3)) {
            Print(__FUNCTION__, ": failed to create Fibonacci Expansion. Error code = ", GetLastError());
            return false;
        }

        // ラインの色・スタイル・太さなどのプロパティを設定
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, lineColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_STYLE, lineStyle);
        ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, lineSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_BACK, false);
        ObjectSetInteger(chartId, objectName, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(chartId, objectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(chartId, objectName, OBJPROP_RAY_LEFT, false);
        ObjectSetInteger(chartId, objectName, OBJPROP_RAY_RIGHT, isRayRight);

        setFibonacciExpansionDefaultLevels(objectName, lineColor, lineStyle, lineSize, chartId);

        return true;
    }
    
    /**
     * 垂直ラインを描画します。
     * 既に同名のオブジェクトが存在する場合は一度削除し、新たに作成します。
     *
     * @param fromObjectName  描画するオブジェクト名（プレフィックスを付与する前の名称）
     * @param time            ラインの時間
     * @param lineColor       ラインの色
     * @param lineStyle       ラインのスタイル（スタイル定数）
     * @param lineSize        ラインの太さ（ピクセル）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setVLine(string fromObjectName, datetime time, color lineColor, int lineStyle, int lineSize, int chartId = 0) {
        // チャートオブジェクト名（共通プレフィックスを付与）
        string objectName = Constant::PREFIX + fromObjectName;

        // 既存の同名オブジェクトを削除してから作成
        ObjectDelete(chartId, objectName);
        ObjectCreate(chartId, objectName, OBJ_VLINE, 0, time, 0);

        // ラインの色・スタイル・太さなどのプロパティを設定
        ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, lineColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_STYLE, lineStyle);
        ObjectSetInteger(chartId, objectName, OBJPROP_WIDTH, lineSize);
        ObjectSetInteger(chartId, objectName, OBJPROP_BACK, false);
    }


private:
    /**
     * フィボナッチエクスパンションの標準レベルを設定します。
     *
     * @param objectName      プレフィックス付与後のオブジェクト名
     * @param lineColor       ラインの色
     * @param lineStyle       ラインのスタイル（スタイル定数）
     * @param lineSize        ラインの太さ（ピクセル）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setFibonacciExpansionDefaultLevels(string objectName, color lineColor, int lineStyle, int lineSize, int chartId) {
        ObjectSetInteger(chartId, objectName, OBJPROP_LEVELS, 5);

        setFibonacciExpansionLevel(objectName, 0, 0.618, "FE 61.8", lineColor, lineStyle, lineSize, chartId);
        setFibonacciExpansionLevel(objectName, 1, 1.000, "FE 100.0", lineColor, lineStyle, lineSize, chartId);
        setFibonacciExpansionLevel(objectName, 2, 1.272, "FE 127.2", lineColor, lineStyle, lineSize, chartId);
        setFibonacciExpansionLevel(objectName, 3, 1.618, "FE 161.8", lineColor, lineStyle, lineSize, chartId);
        setFibonacciExpansionLevel(objectName, 4, 2.000, "FE 200.0", lineColor, lineStyle, lineSize, chartId);
    }
    
    /**
     * フィボナッチエクスパンションのレベルを設定します。
     *
     * @param objectName      プレフィックス付与後のオブジェクト名
     * @param levelIndex      レベル番号
     * @param levelValue      レベル値
     * @param levelText       レベル表示名
     * @param lineColor       ラインの色
     * @param lineStyle       ラインのスタイル（スタイル定数）
     * @param lineSize        ラインの太さ（ピクセル）
     * @param chartId         描画対象のチャートID（0 の場合はカレントチャート）
     */
    static void setFibonacciExpansionLevel(string objectName, int levelIndex, double levelValue, string levelText,
                                            color lineColor, int lineStyle, int lineSize, int chartId) {
        ObjectSetDouble(chartId, objectName, OBJPROP_LEVELVALUE, levelIndex, levelValue);
        ObjectSetInteger(chartId, objectName, OBJPROP_LEVELCOLOR, levelIndex, lineColor);
        ObjectSetInteger(chartId, objectName, OBJPROP_LEVELSTYLE, levelIndex, lineStyle);
        ObjectSetInteger(chartId, objectName, OBJPROP_LEVELWIDTH, levelIndex, lineSize);
        ObjectSetString(chartId, objectName, OBJPROP_LEVELTEXT, levelIndex, levelText);
    }

};

#endif // MSTNG_DRAW_UTIL_MQH
