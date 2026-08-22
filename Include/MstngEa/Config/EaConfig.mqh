//+------------------------------------------------------------------+
//|                                                     EaConfig.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/**
 * Package: MstngEa.Config
 * File: EaConfig.mqh
 */

#ifndef MSTNGEA_CONFIG_EACONFIG_MQH
#define MSTNGEA_CONFIG_EACONFIG_MQH

#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationMode.mqh>
#include <Mstng\ExpertAdvisor\H1W1ConfirmationMode.mqh>
#include <MstngEa\Config\H1PositionManagementMode.mqh>
#include <MstngEa\Config\StrategyType.mqh>

/**
 * EA設定
 */
class EaConfig {
public:
    /** 戦略種別 */
    StrategyType strategyType;

    /** ロット */
    double lotSize;

    /** スリッページ */
    int slippage;

    /** ラベル名 */
    string statusLabelName;

    /** 利益戻し決済使用 */
    bool useProfitRetracementExit;

    /** 利益戻し決済開始R倍率 */
    double profitRetracementStartR;

    /** 利益戻し決済戻し率 */
    double profitRetracementRate;

    /** 建値移動使用 */
    bool useBreakEven;

    /** 建値移動発動R倍率 */
    double breakEvenTriggerR;

    /** 建値移動加算pips */
    double breakEvenPlusPips;

    /** 通貨強弱利用 */
    bool useCurrencyStrength;

    /** MTF_3in3アラート検証CSV出力 */
    bool mtf3In3AlertCsvEnabled;

    /** H1表示波ごとのエントリー回数制限を使用する場合true。 */
    bool h1DisplayWaveEntryLimitEnabled;

    /** H1ポジションの決済管理モード。 */
    H1PositionManagementMode h1PositionManagementMode;

    /** H1 ZigZagトレイルのSLバッファー（pips）。 */
    double h1ZigZagTrailBufferPips;

    /** H1エントリーで使用するW1確認モード。 */
    H1W1ConfirmationMode h1W1ConfirmationMode;

    /** H1エントリーで使用するEMA200確認モード。 */
    H1Ema200ConfirmationMode h1Ema200ConfirmationMode;

    /**
     * コンストラクタ
     */
    EaConfig() {
        // デフォルト値を設定
        this.strategyType = STRATEGY_TYPE_MTF_3IN3;
        this.lotSize = 0.10;
        this.slippage = 10;
        this.statusLabelName = "MstngEa_StatusLabel";
        this.useProfitRetracementExit = true;
        this.profitRetracementStartR = 1.5;
        this.profitRetracementRate = 0.30;
        this.useBreakEven = true;
        this.breakEvenTriggerR = 1.0;
        this.breakEvenPlusPips = 1.0;
        this.useCurrencyStrength = false;
        this.mtf3In3AlertCsvEnabled = false;
        this.h1DisplayWaveEntryLimitEnabled = false;
        this.h1PositionManagementMode = H1_POSITION_MANAGEMENT_LEGACY;
        this.h1ZigZagTrailBufferPips = 5.0;
        this.h1W1ConfirmationMode = H1_W1_CONFIRMATION_OBSERVE_ONLY;
        this.h1Ema200ConfirmationMode =
            H1_EMA200_CONFIRMATION_H1_ONLY;
    }
};

#endif
