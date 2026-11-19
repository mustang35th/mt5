#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_CONFIG_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_CONFIG_MQH

#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>

/**
 * GMO通貨のM1監視とチャート表示の設定。
 */
class ZigZagElliotMonitorConfig {
public:
    /** GMO対象だけを監視する初期版の対象選択。 */
    bool gmoOnly;

    /** 起動時から監視を実行する場合true。 */
    bool monitoringEnabled;

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
        this.gmoOnly = true;
        this.monitoringEnabled = true;
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
