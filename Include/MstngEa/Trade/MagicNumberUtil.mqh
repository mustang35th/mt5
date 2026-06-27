/**
 * Package: MstngEa.Trade
 * File: MagicNumberUtil.mqh
 */

#ifndef MSTNGEA_TRADE_MAGICNUMBERUTIL_MQH
#define MSTNGEA_TRADE_MAGICNUMBERUTIL_MQH

#include <MstngEa\Config\StrategyType.mqh>

/**
 * マジックナンバー生成
 */
class MagicNumberUtil {
public:
    /**
     * マジックナンバー生成
     *
     * @param eaCodeValue EAコード
     * @param symbolNameValue シンボル名
     * @param timeFrameValue 時間足
     * @param strategyTypeValue 戦略種別
     * @return マジックナンバー
     */
    static ulong build(
        int eaCodeValue,
        string symbolNameValue,
        ENUM_TIMEFRAMES timeFrameValue,
        StrategyType strategyTypeValue
    ) {
        // コードを分解
        int leftCode = MagicNumberUtil::getCurrencyCode(StringSubstr(symbolNameValue, 0, 3));
        int rightCode = MagicNumberUtil::getCurrencyCode(StringSubstr(symbolNameValue, 3, 3));
        int timeFrameCode = MagicNumberUtil::getTimeFrameCode(timeFrameValue);
        int strategyCode = MagicNumberUtil::getStrategyCode(strategyTypeValue);

        string valueText = IntegerToString(eaCodeValue);
        valueText += MagicNumberUtil::pad2(leftCode);
        valueText += MagicNumberUtil::pad2(rightCode);
        valueText += MagicNumberUtil::pad2(timeFrameCode);
        valueText += MagicNumberUtil::pad2(strategyCode);

        return (ulong)StringToInteger(valueText);
    }

private:
    /**
     * 通貨コード変換
     *
     * @param currencyValue 通貨コード
     * @return 数値コード
     */
    static int getCurrencyCode(string currencyValue) {

        if (currencyValue == "USD") {
            return 1;
        }

        if (currencyValue == "JPY") {
            return 2;
        }

        if (currencyValue == "EUR") {
            return 3;
        }

        if (currencyValue == "GBP") {
            return 4;
        }

        if (currencyValue == "AUD") {
            return 5;
        }

        if (currencyValue == "NZD") {
            return 6;
        }

        if (currencyValue == "CAD") {
            return 7;
        }

        if (currencyValue == "CHF") {
            return 8;
        }

        return 0;
    }

    /**
     * 時間足コード変換
     *
     * @param timeFrameValue 時間足
     * @return 数値コード
     */
    static int getTimeFrameCode(ENUM_TIMEFRAMES timeFrameValue) {

        if (timeFrameValue == PERIOD_M1) {
            return 1;
        }

        if (timeFrameValue == PERIOD_M5) {
            return 2;
        }

        if (timeFrameValue == PERIOD_M15) {
            return 3;
        }

        if (timeFrameValue == PERIOD_M30) {
            return 4;
        }

        if (timeFrameValue == PERIOD_H1) {
            return 5;
        }

        if (timeFrameValue == PERIOD_H4) {
            return 6;
        }

        if (timeFrameValue == PERIOD_D1) {
            return 7;
        }

        if (timeFrameValue == PERIOD_W1) {
            return 8;
        }

        if (timeFrameValue == PERIOD_MN1) {
            return 9;
        }

        return 0;
    }

    /**
     * 戦略コード変換
     *
     * @param strategyTypeValue 戦略種別
     * @return 数値コード
     */
    static int getStrategyCode(StrategyType strategyTypeValue) {

        if (strategyTypeValue == STRATEGY_TYPE_MTF_3IN3) {
            return 1;
        }

        if (strategyTypeValue == STRATEGY_TYPE_MTF_3IN3_BUY_SELL_D1) {
            return 2;
        }

        if (strategyTypeValue == STRATEGY_TYPE_MTF_BUY_SELL_COUNT3) {
            return 3;
        }

        return 0;
    }

    /**
     * 2桁文字列化
     *
     * @param valueValue 数値
     * @return 2桁文字列
     */
    static string pad2(int valueValue) {

        if (valueValue < 10) {
            return "0" + IntegerToString(valueValue);
        }

        return IntegerToString(valueValue);
    }
};

#endif
