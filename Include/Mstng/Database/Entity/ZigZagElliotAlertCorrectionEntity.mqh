#ifndef MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_CORRECTION_ENTITY_MQH
#define MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_CORRECTION_ENTITY_MQH

/**
 * アラート時点の補正採用結果と補正前後の比較値を保持する。
 *
 * 行がない過去アラートは未記録であり、NONEとして補完しない。
 */
struct ZigZagElliotAlertCorrectionEntity {
    /** アラートID。親と1対1。 */
    long alertId;

    /** 補正状態。NONEまたはAPPLIED。 */
    string correctionStatus;

    /** 補正した時間足。補正なしは0。 */
    int correctionTimeFrame;

    /** 補正対象足の元方向。補正なしは空。 */
    string originalDirection;

    /** 補正対象足の採用方向。補正なしは空。 */
    string correctedDirection;

    /** 採用分析。ORIGINALまたはCORRECTED。 */
    string selectedAnalysis;

    /** 採用分析のチャートアラート文字。 */
    string selectedAlertText;

    /** 採用した現在足の主波ラベル。 */
    string selectedCurrentElliotLabel;

    /** 採用分析の全時間足波動概要。 */
    string selectedWaveSummaryText;

    /** 判定時の参照価格。元アラートと同じ値。 */
    double referencePrice;

    /** 採用SL候補が利用できる場合1。 */
    int isSelectedStopLossAvailable;

    /** 新規エントリーに採用したSL候補。 */
    double selectedStopLoss;

    /** 参照価格から採用SL候補までのpips。 */
    double selectedRiskPips;

    /** 元分析の基準SL。 */
    double originalLc0;

    /** 元分析の5 pips余裕のSL。 */
    double originalLc5;

    /** 元分析の10 pips余裕のSL。 */
    double originalLc10;

    /** 元分析の15 pips余裕のSL。 */
    double originalLc15;

    /** 元分析の基準SLまでのpips。 */
    double originalLossCutDiffPips;

    /** 元分析の基準SLまでの参考円換算額。 */
    double originalLossCutDiffJpy;

    /** 補正分析の基準SL。 */
    double correctedLc0;

    /** 補正分析の5 pips余裕のSL。 */
    double correctedLc5;

    /** 補正分析の10 pips余裕のSL。 */
    double correctedLc10;

    /** 補正分析の15 pips余裕のSL。 */
    double correctedLc15;

    /** 補正分析の基準SLまでのpips。 */
    double correctedLossCutDiffPips;

    /** 補正分析の基準SLまでの参考円換算額。 */
    double correctedLossCutDiffJpy;

    /** 補正後のSL基準ポイント時刻。元シグナル識別キーとは別。 */
    datetime correctedReferencePointTime;

    /** 元分析の全時間足表示テキスト。 */
    string originalAnalysisText;

    /** 補正分析の全時間足表示テキスト。補正なしは空。 */
    string correctedAnalysisText;

    /** 補正分析の詳細CSV。補正なしは空。 */
    string correctedElliotCsvText;

    /** 元分析と補正情報をまとめた比較ハッシュ。 */
    string comparisonHash;

    /** レコード生成時刻。 */
    datetime createdAt;

    /** レコード生成時刻表示文字列。 */
    string createdAtText;

};

#endif // MSTNG_DATABASE_ENTITY_ZIGZAG_ELLIOT_ALERT_CORRECTION_ENTITY_MQH
