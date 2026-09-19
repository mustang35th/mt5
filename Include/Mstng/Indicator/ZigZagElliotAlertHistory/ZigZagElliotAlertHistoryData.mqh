#ifndef MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_DATA_MQH
#define MSTNG_ZIGZAG_ELLIOT_ALERT_HISTORY_DATA_MQH

#include <Mstng\Database\Entity\ZigZagElliotAlertCorrectionEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertPointEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertTimeFrameEntity.mqh>

/**
 * 保存分析の表示モード。
 */
enum ZigZagElliotAlertHistoryView {
    ALERT_HISTORY_SELECTED = 0,
    ALERT_HISTORY_ORIGINAL = 1,
    ALERT_HISTORY_COMPARISON = 2
};

/**
 * 全件表示に必要な保存ラベルだけを保持する。詳細分析は選択時に読み取る。
 */
struct ZigZagElliotAlertHistoryMarker {
    /** 保存アラートID。 */
    long alertId;
    /** 発生足のサーバー時刻。 */
    datetime barTime;
    /** 判定サーバー時刻。 */
    datetime serverTime;
    /** 保存された判定JST。 */
    datetime jstTime;
    /** 元分析M5の保存始値。 */
    double price;
    /** 保存されたBUYまたはSELL。 */
    string side;
    /** 保存されたENTRY成立フラグ。 */
    int isEntry;
    /** 保存されたENTRY結果。 */
    string entryResult;
    /** 保存された採用文字、未記録時は元文字。 */
    string text;
    /** 保存された補正内容の説明。 */
    string correctionText;
    /** ラベル表示に必要な保存値を確認できた場合true。 */
    bool available;
};

/**
 * 一つのアラートに保存された元分析と補正分析を保持する。
 * 現在の相場から再分析した値は保持しない。
 */
class ZigZagElliotAlertHistorySnapshot {
public:
    /** 保存されたアラートと最終判定。 */
    ZigZagElliotAlertEntity alert;
    /** 保存元Run。 */
    ZigZagElliotAlertRunEntity run;
    /** 補正メタデータ。 */
    ZigZagElliotAlertCorrectionEntity correction;
    /** APPLIED、NONE、UNRECORDED、INCOMPLETE。 */
    string correctionStatus;
    /** 補正情報を利用できない理由。 */
    string correctionReason;
    /** 元の保存分析を描画できる場合true。 */
    bool originalAvailable;
    /** 元分析を利用できない理由。 */
    string originalReason;
    /** 元分析の時間足。 */
    ZigZagElliotAlertTimeFrameEntity originalTimeFrames[];
    /** 元分析の最新Waveポイント。 */
    ZigZagElliotAlertPointEntity originalPoints[];
    /** 補正分析の時間足。 */
    ZigZagElliotAlertTimeFrameEntity correctedTimeFrames[];
    /** 補正分析の最新Waveポイント。 */
    ZigZagElliotAlertPointEntity correctedPoints[];

    /**
     * 空の保存分析を初期化する。
     */
    ZigZagElliotAlertHistorySnapshot() {
        this.clear();
    }

    /**
     * 前に選択したアラートの情報をすべて解放する。
     */
    void clear() {
        ZeroMemory(this.alert);
        ZeroMemory(this.run);
        ZeroMemory(this.correction);
        this.correctionStatus = "UNRECORDED";
        this.correctionReason = "";
        this.originalAvailable = false;
        this.originalReason = "";
        ArrayFree(this.originalTimeFrames);
        ArrayFree(this.originalPoints);
        ArrayFree(this.correctedTimeFrames);
        ArrayFree(this.correctedPoints);
    }
};

#endif
