//+------------------------------------------------------------------+
//|                                             ConstantCurrency.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef __CONSTANT_CURRENCY_MQH__
#define __CONSTANT_CURRENCY_MQH__

/**
 * 通貨ペア文字列定数を管理するクラス。
 *
 * 個別通貨と主要クロス（JPY/USD/GBP/EUR/AUD/NZD/CAD）を保持する。
 */
class ConstantCurrency {
public:
    /** USD通貨文字列。 */
    static const string USD;
    /** JPY通貨文字列。 */
    static const string JPY;
    /** EUR通貨文字列。 */
    static const string EUR;
    /** GBP通貨文字列。 */
    static const string GBP;
    /** AUD通貨文字列。 */
    static const string AUD;
    /** NZD通貨文字列。 */
    static const string NZD;
    /** CAD通貨文字列。 */
    static const string CAD;
    /** CHF通貨文字列。 */
    static const string CHF;

    // JPYクロス。
    /** USDJPY通貨ペア文字列。 */
    static const string USDJPY;
    /** EURJPY通貨ペア文字列。 */
    static const string EURJPY;
    /** GBPJPY通貨ペア文字列。 */
    static const string GBPJPY;
    /** AUDJPY通貨ペア文字列。 */
    static const string AUDJPY;
    /** NZDJPY通貨ペア文字列。 */
    static const string NZDJPY;
    /** CADJPY通貨ペア文字列。 */
    static const string CADJPY;
    /** CHFJPY通貨ペア文字列。 */
    static const string CHFJPY;

    // USDクロス。
    /** EURUSD通貨ペア文字列。 */
    static const string EURUSD;
    /** GBPUSD通貨ペア文字列。 */
    static const string GBPUSD;
    /** AUDUSD通貨ペア文字列。 */
    static const string AUDUSD;
    /** NZDUSD通貨ペア文字列。 */
    static const string NZDUSD;
    /** USDCAD通貨ペア文字列。 */
    static const string USDCAD;
    /** USDCHF通貨ペア文字列。 */
    static const string USDCHF;

    // GBPクロス。
    /** EURGBP通貨ペア文字列。 */
    static const string EURGBP;
    /** GBPAUD通貨ペア文字列。 */
    static const string GBPAUD;
    /** GBPNZD通貨ペア文字列。 */
    static const string GBPNZD;
    /** GBPCAD通貨ペア文字列。 */
    static const string GBPCAD;
    /** GBPCHF通貨ペア文字列。 */
    static const string GBPCHF;

    // EURクロス。
    /** EURAUD通貨ペア文字列。 */
    static const string EURAUD;
    /** EURNZD通貨ペア文字列。 */
    static const string EURNZD;
    /** EURCAD通貨ペア文字列。 */
    static const string EURCAD;
    /** EURCHF通貨ペア文字列。 */
    static const string EURCHF;

    // AUDクロス。
    /** AUDNZD通貨ペア文字列。 */
    static const string AUDNZD;
    /** AUDCAD通貨ペア文字列。 */
    static const string AUDCAD;
    /** AUDCHF通貨ペア文字列。 */
    static const string AUDCHF;

    // NZDクロス。
    /** NZDCAD通貨ペア文字列。 */
    static const string NZDCAD;
    /** NZDCHF通貨ペア文字列。 */
    static const string NZDCHF;

    // CADクロス。
    /** CADCHF通貨ペア文字列。 */
    static const string CADCHF;

    /**
     * 通貨コードに対応する表示色を取得する。
     *
     * @param fromCurrencyName 通貨コード。
     * @return 通貨の表示色。未知の通貨の場合は白。
     */
    static color getColor(const string fromCurrencyName) {
        string currencyName = fromCurrencyName;
        StringToUpper(currencyName);

        if (currencyName == USD) {
            return clrOrange;
        }

        if (currencyName == JPY) {
            return clrAqua;
        }

        if (currencyName == EUR) {
            return clrRed;
        }

        if (currencyName == GBP) {
            return clrLime;
        }

        if (currencyName == AUD) {
            return clrDodgerBlue;
        }

        if (currencyName == NZD) {
            return clrHotPink;
        }

        if (currencyName == CAD) {
            return clrBlueViolet;
        }

        if (currencyName == CHF) {
            return clrBrown;
        }

        return clrWhite;
    }
};

// 単一通貨。
const string ConstantCurrency::USD = "USD";
const string ConstantCurrency::JPY = "JPY";
const string ConstantCurrency::EUR = "EUR";
const string ConstantCurrency::GBP = "GBP";
const string ConstantCurrency::AUD = "AUD";
const string ConstantCurrency::NZD = "NZD";
const string ConstantCurrency::CAD = "CAD";
const string ConstantCurrency::CHF = "CHF";

// JPYクロス。
const string ConstantCurrency::USDJPY = "USDJPY";
const string ConstantCurrency::EURJPY = "EURJPY";
const string ConstantCurrency::GBPJPY = "GBPJPY";
const string ConstantCurrency::AUDJPY = "AUDJPY";
const string ConstantCurrency::NZDJPY = "NZDJPY";
const string ConstantCurrency::CADJPY = "CADJPY";
const string ConstantCurrency::CHFJPY = "CHFJPY";

// USDクロス。
const string ConstantCurrency::EURUSD = "EURUSD";
const string ConstantCurrency::GBPUSD = "GBPUSD";
const string ConstantCurrency::AUDUSD = "AUDUSD";
const string ConstantCurrency::NZDUSD = "NZDUSD";
const string ConstantCurrency::USDCAD = "USDCAD";
const string ConstantCurrency::USDCHF = "USDCHF";

// GBPクロス。
const string ConstantCurrency::EURGBP = "EURGBP";
const string ConstantCurrency::GBPAUD = "GBPAUD";
const string ConstantCurrency::GBPNZD = "GBPNZD";
const string ConstantCurrency::GBPCAD = "GBPCAD";
const string ConstantCurrency::GBPCHF = "GBPCHF";

// EURクロス。
const string ConstantCurrency::EURAUD = "EURAUD";
const string ConstantCurrency::EURNZD = "EURNZD";
const string ConstantCurrency::EURCAD = "EURCAD";
const string ConstantCurrency::EURCHF = "EURCHF";

// AUDクロス。
const string ConstantCurrency::AUDNZD = "AUDNZD";
const string ConstantCurrency::AUDCAD = "AUDCAD";
const string ConstantCurrency::AUDCHF = "AUDCHF";

// NZDクロス。
const string ConstantCurrency::NZDCAD = "NZDCAD";
const string ConstantCurrency::NZDCHF = "NZDCHF";

// CADクロス。
const string ConstantCurrency::CADCHF = "CADCHF";

#endif // __CONSTANT_CURRENCY_MQH__
