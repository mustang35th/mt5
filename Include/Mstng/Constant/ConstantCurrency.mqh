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
 * 個別通貨と主要クロス（JPY/USD/GBP/EUR/AUD/NZD/CAD）を保持する。
 */
class ConstantCurrency {
public:
    /** 単一通貨 */
    static const string USD;
    /** JPY 通貨文字列。 */
    static const string JPY;
    /** EUR 通貨文字列。 */
    static const string EUR;
    /** GBP 通貨文字列。 */
    static const string GBP;
    /** AUD 通貨文字列。 */
    static const string AUD;
    /** NZD 通貨文字列。 */
    static const string NZD;
    /** CAD 通貨文字列。 */
    static const string CAD;
    /** CHF 通貨文字列。 */
    static const string CHF;

    /** JPY クロス */
    /** USDJPY 通貨ペア文字列。 */
    static const string USDJPY;
    /** EURJPY 通貨ペア文字列。 */
    static const string EURJPY;
    /** GBPJPY 通貨ペア文字列。 */
    static const string GBPJPY;
    /** AUDJPY 通貨ペア文字列。 */
    static const string AUDJPY;
    /** NZDJPY 通貨ペア文字列。 */
    static const string NZDJPY;
    /** CADJPY 通貨ペア文字列。 */
    static const string CADJPY;
    /** CHFJPY 通貨ペア文字列。 */
    static const string CHFJPY;

    /** USD クロス */
    /** EURUSD 通貨ペア文字列。 */
    static const string EURUSD;
    /** GBPUSD 通貨ペア文字列。 */
    static const string GBPUSD;
    /** AUDUSD 通貨ペア文字列。 */
    static const string AUDUSD;
    /** NZDUSD 通貨ペア文字列。 */
    static const string NZDUSD;
    /** USDCAD 通貨ペア文字列。 */
    static const string USDCAD;
    /** USDCHF 通貨ペア文字列。 */
    static const string USDCHF;

    /** GBP クロス */
    /** EURGBP 通貨ペア文字列。 */
    static const string EURGBP;
    /** GBPAUD 通貨ペア文字列。 */
    static const string GBPAUD;
    /** GBPNZD 通貨ペア文字列。 */
    static const string GBPNZD;
    /** GBPCAD 通貨ペア文字列。 */
    static const string GBPCAD;
    /** GBPCHF 通貨ペア文字列。 */
    static const string GBPCHF;

    /** EUR クロス */
    /** EURAUD 通貨ペア文字列。 */
    static const string EURAUD;
    /** EURNZD 通貨ペア文字列。 */
    static const string EURNZD;
    /** EURCAD 通貨ペア文字列。 */
    static const string EURCAD;
    /** EURCHF 通貨ペア文字列。 */
    static const string EURCHF;

    /** AUD クロス */
    /** AUDNZD 通貨ペア文字列。 */
    static const string AUDNZD;
    /** AUDCAD 通貨ペア文字列。 */
    static const string AUDCAD;
    /** AUDCHF 通貨ペア文字列。 */
    static const string AUDCHF;

    /** NZD クロス */
    /** NZDCAD 通貨ペア文字列。 */
    static const string NZDCAD;
    /** NZDCHF 通貨ペア文字列。 */
    static const string NZDCHF;

    /** CAD クロス */
    /** CADCHF 通貨ペア文字列。 */
    static const string CADCHF;
};

/** 単一通貨 */
const string ConstantCurrency::USD = "USD";
const string ConstantCurrency::JPY = "JPY";
const string ConstantCurrency::EUR = "EUR";
const string ConstantCurrency::GBP = "GBP";
const string ConstantCurrency::AUD = "AUD";
const string ConstantCurrency::NZD = "NZD";
const string ConstantCurrency::CAD = "CAD";
const string ConstantCurrency::CHF = "CHF";

/** JPY クロス */
const string ConstantCurrency::USDJPY = "USDJPY";
const string ConstantCurrency::EURJPY = "EURJPY";
const string ConstantCurrency::GBPJPY = "GBPJPY";
const string ConstantCurrency::AUDJPY = "AUDJPY";
const string ConstantCurrency::NZDJPY = "NZDJPY";
const string ConstantCurrency::CADJPY = "CADJPY";
const string ConstantCurrency::CHFJPY = "CHFJPY";

/** USD クロス */
const string ConstantCurrency::EURUSD = "EURUSD";
const string ConstantCurrency::GBPUSD = "GBPUSD";
const string ConstantCurrency::AUDUSD = "AUDUSD";
const string ConstantCurrency::NZDUSD = "NZDUSD";
const string ConstantCurrency::USDCAD = "USDCAD";
const string ConstantCurrency::USDCHF = "USDCHF";

/** GBP クロス */
const string ConstantCurrency::EURGBP = "EURGBP";
const string ConstantCurrency::GBPAUD = "GBPAUD";
const string ConstantCurrency::GBPNZD = "GBPNZD";
const string ConstantCurrency::GBPCAD = "GBPCAD";
const string ConstantCurrency::GBPCHF = "GBPCHF";

/** EUR クロス */
const string ConstantCurrency::EURAUD = "EURAUD";
const string ConstantCurrency::EURNZD = "EURNZD";
const string ConstantCurrency::EURCAD = "EURCAD";
const string ConstantCurrency::EURCHF = "EURCHF";

/** AUD クロス */
const string ConstantCurrency::AUDNZD = "AUDNZD";
const string ConstantCurrency::AUDCAD = "AUDCAD";
const string ConstantCurrency::AUDCHF = "AUDCHF";

/** NZD クロス */
const string ConstantCurrency::NZDCAD = "NZDCAD";
const string ConstantCurrency::NZDCHF = "NZDCHF";

/** CAD クロス */
const string ConstantCurrency::CADCHF = "CADCHF";

#endif // __CONSTANT_CURRENCY_MQH__
