/**
 * Package: MstngEa.Config
 * File: EaConfig.mqh
 */

#ifndef MSTNGEA_CONFIG_EACONFIG_MQH
#define MSTNGEA_CONFIG_EACONFIG_MQH

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
    }
};

#endif
