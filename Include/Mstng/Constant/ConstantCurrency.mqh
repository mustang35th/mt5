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
    static const string JPY;
    static const string EUR;
    static const string GBP;
    static const string AUD;
    static const string NZD;
    static const string CAD;
    static const string CHF;

    /** JPY クロス */
    static const string USDJPY;
    static const string EURJPY;
    static const string GBPJPY;
    static const string AUDJPY;
    static const string NZDJPY;
    static const string CADJPY;
    static const string CHFJPY;

    /** USD クロス */
    static const string EURUSD;
    static const string GBPUSD;
    static const string AUDUSD;
    static const string NZDUSD;
    static const string USDCAD;
    static const string USDCHF;

    /** GBP クロス */
    static const string EURGBP;
    static const string GBPAUD;
    static const string GBPNZD;
    static const string GBPCAD;
    static const string GBPCHF;

    /** EUR クロス */
    static const string EURAUD;
    static const string EURNZD;
    static const string EURCAD;
    static const string EURCHF;

    /** AUD クロス */
    static const string AUDNZD;
    static const string AUDCAD;
    static const string AUDCHF;

    /** NZD クロス */
    static const string NZDCAD;
    static const string NZDCHF;

    /** CAD クロス */
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
