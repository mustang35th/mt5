//+------------------------------------------------------------------+
//|                                           ZigZagElliotConfig.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_CONFIG_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_CONFIG_MQH

#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>
#include <Mstng\Strength\CurrencyStrengthRankDatabaseProfile.mqh>

/**
 * ZigZagElliotインジケータの設定を保持するクラス。
 */
class ZigZagElliotConfig {
public:
    /** Mail内容を検証用ファイルへ出力する場合true。 */
    bool mailValidationFileEnabled;
    /** MTF_3in3アラート検証CSVを出力する場合true。 */
    bool mtf3In3AlertCsvEnabled;
    /** MTF_3in3アラートをデータベースへ保存する場合true。 */
    bool mtf3In3AlertDatabaseEnabled;
    /** MTF_3in3アラートデータベースファイル名。 */
    string mtf3In3AlertDatabaseFileName;
    /** MTF_3in3アラートデータベースで共通フォルダを使用する場合true。 */
    bool mtf3In3AlertDatabaseUseCommonFolder;
    /** H1表示波ごとのエントリー回数制限を使用する場合true。 */
    bool h1DisplayWaveEntryLimitEnabled;
    /** 通貨強弱を利用する場合true。 */
    bool currencyStrengthEnabled;
    /** 通貨強弱をエントリー条件として使用する場合true。 */
    bool currencyStrengthEntryFilterEnabled;
    /** 通貨強弱順位パネルを表示する場合true。 */
    bool currencyStrengthRankVisible;
    /** 通貨強弱順位パネルの右端からの距離。 */
    int currencyStrengthRankPanelXDistance;
    /** 通貨強弱情報の再取得間隔秒。 */
    int currencyStrengthRefreshSeconds;
    /** 通貨強弱DB参照プロファイル。 */
    CurrencyStrengthRankDatabaseProfile currencyStrengthDatabaseProfile;
    /** 通貨強弱の投票ウェイト方式。 */
    CurrencyStrengthVoteWeightMode currencyStrengthVoteWeightMode;
    /** 通貨強弱DBファイル名。 */
    string currencyStrengthDatabaseFileName;
    /** 通貨強弱DBを年単位で分割する場合true。 */
    bool currencyStrengthDatabaseSplitByYear;
    /** 通貨強弱DBで共通フォルダを使用する場合true。 */
    bool currencyStrengthDatabaseUseCommonFolder;
    /** H1新規足のElliott観測情報をデータベースへ保存する場合true。 */
    bool h1ElliotObservationDatabaseEnabled;

    /**
     * デフォルト設定で初期化する。
     */
    ZigZagElliotConfig() {
        this.mailValidationFileEnabled = false;
        this.mtf3In3AlertCsvEnabled = true;
        this.mtf3In3AlertDatabaseEnabled = false;
        this.mtf3In3AlertDatabaseFileName =
            "mstng-zigzag-elliot-alert.sqlite";
        this.mtf3In3AlertDatabaseUseCommonFolder = true;
        this.h1DisplayWaveEntryLimitEnabled = false;
        this.currencyStrengthEnabled = true;
        this.currencyStrengthEntryFilterEnabled = false;
        this.currencyStrengthRankVisible = true;
        this.currencyStrengthRankPanelXDistance = 48;
        this.currencyStrengthRefreshSeconds = 15;
        this.currencyStrengthDatabaseProfile =
            CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
        this.currencyStrengthVoteWeightMode =
            CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;
        this.currencyStrengthDatabaseFileName =
            "mstng-currency-strength.sqlite";
        this.currencyStrengthDatabaseSplitByYear = true;
        this.currencyStrengthDatabaseUseCommonFolder = true;
        this.h1ElliotObservationDatabaseEnabled = false;
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_CONFIG_MQH
