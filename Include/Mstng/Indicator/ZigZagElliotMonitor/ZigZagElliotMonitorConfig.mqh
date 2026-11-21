#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_CONFIG_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_CONFIG_MQH

#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorNotification.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorTarget.mqh>

/**
 * 選択した通貨ペアのM1監視とチャート表示の設定。
 */
class ZigZagElliotMonitorConfig {
public:
    /** 分析・一覧・チャート表示の対象にする通貨ペア集合。 */
    ENUM_ZIGZAG_MONITOR_TARGET targetMode;

    /** 起動時から監視を実行する場合true。 */
    bool monitoringEnabled;

    /** 新規M1エントリーの通知方法。 */
    ENUM_ZIGZAG_MONITOR_NOTIFY entryNotificationMode;

    /** 新規成立時にチャートを自動表示する場合true。 */
    bool autoOpenEnabled;

    /** この監視機能が開いて保持するチャート数の上限。 */
    int maxOpenCharts;

    /** 開いたチャートに適用するテンプレート。空文字は適用なし。 */
    string templateName;

    /** チャートを前面へ切り替える場合true。 */
    bool bringToFront;

    /** 不足データを再確認する最短間隔秒。 */
    int retrySeconds;

    /** 一覧文字のフォントサイズ。 */
    int fontSize;

    /** 既存のM1判定と通貨強弱取得に使用する設定。 */
    ZigZagElliotConfig entryConfig;

    /**
     * 通常版M1の初期条件と、最小構成の表示設定を準備する。
     */
    ZigZagElliotMonitorConfig() {
        this.targetMode = ZIGZAG_MONITOR_TARGET_GMO;
        this.monitoringEnabled = true;
        this.entryNotificationMode = ZIGZAG_MONITOR_NOTIFY_POPUP;
        this.autoOpenEnabled = true;
        this.maxOpenCharts = 18;
        this.templateName = "";
        this.bringToFront = true;
        this.retrySeconds = 5;
        this.fontSize = 10;
        this.entryConfig.m1DirectionCorrectionEnabled = true;
        this.entryConfig.currencyStrengthEnabled = true;
        this.entryConfig.currencyStrengthEntryFilterEnabled = true;
        this.entryConfig.m1CurrencyStrengthGapDirectionMode = M1_CURRENCY_STRENGTH_GAP_BOTH;
        this.entryConfig.currencyStrengthRankVisible = false;
        this.entryConfig.currencyStrengthGapMailEnabled = false;
        this.entryConfig.mtf3In3AlertCsvEnabled = false;
        this.entryConfig.mtf3In3AlertDatabaseEnabled = false;
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_CONFIG_MQH
