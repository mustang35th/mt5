//+------------------------------------------------------------------+
//|                                                     RateUtil.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Common\MarketContext.mqh>

/**
 * レート・ポイント・pips の変換など、
 * 市場コンテキストに依存する価格単位計算を提供するユーティリティです。
 */
class RateUtil {
public:
    /**
     * 市場コンテキストの小数点桁数を取得する。
     *
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return 小数点桁数。
     */
    static int getDigits(MarketContext &fromMarketContext) {
        return fromMarketContext.digits;
    }

    /**
     * シンボル名から小数点桁数を取得する。
     *
     * @param fromSymbolName 対象シンボル名
     * @return 小数点桁数。
     */
    static int getDigits(const string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return RateUtil::getDigits(context);
    }

    /**
     * 市場コンテキストの1ポイント値を取得する。
     *
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return 1ポイント値。
     */
    static double getPoint(MarketContext &fromMarketContext) {
        return fromMarketContext.getPoint();
    }

    /**
     * シンボル名から1ポイント値を取得する。
     *
     * @param fromSymbolName 対象シンボル名
     * @return 1ポイント値。
     */
    static double getPoint(const string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return RateUtil::getPoint(context);
    }

    /**
     * 市場コンテキストの1pipあたりのポイント数を取得する。
     *
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return 1pipあたりのポイント数（3桁/5桁は10、その他は1）
     */
    static double getPipInPoints(MarketContext &fromMarketContext) {
        int digits = RateUtil::getDigits(fromMarketContext);

        if (digits == 5 || digits == 3) {
            return 10.0;
        }

        return 1.0;
    }

    /**
     * シンボル名から1pipあたりのポイント数を取得する。
     *
     * @param fromSymbolName 対象シンボル名
     * @return 1pipあたりのポイント数。
     */
    static double getPipInPoints(const string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return RateUtil::getPipInPoints(context);
    }

    /**
     * 市場コンテキストを使ってpipsを価格差へ変換する。
     *
     * @param fromPips         pips
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return 価格差。ポイント取得失敗時は0。
     */
    static double pipsToPrice(const double fromPips, MarketContext &fromMarketContext) {
        double point = RateUtil::getPoint(fromMarketContext);

        if (point <= 0) {
            return 0;
        }

        double priceDiff = fromPips * RateUtil::getPipInPoints(fromMarketContext) * point;
        return NormalizeDouble(priceDiff, RateUtil::getDigits(fromMarketContext));
    }

    /**
     * シンボル名からpipsを価格差へ変換する。
     *
     * @param fromPips     pips
     * @param fromSymbolName 対象シンボル名
     * @return 価格差。ポイント取得失敗時は0。
     */
    static double pipsToPrice(const double fromPips, const string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return RateUtil::pipsToPrice(fromPips, context);
    }

    /**
     * 市場コンテキストを使って価格差をpipsへ変換する。
     *
     * @param fromPriceDiff    価格差
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return pips。ポイント取得失敗時は0。
     */
    static double priceToPips(const double fromPriceDiff, MarketContext &fromMarketContext) {
        double point = RateUtil::getPoint(fromMarketContext);

        if (point <= 0) {
            return 0;
        }

        double pips = fromPriceDiff / (RateUtil::getPipInPoints(fromMarketContext) * point);
        return NormalizeDouble(pips, 1);
    }

    /**
     * シンボル名から価格差をpipsへ変換する。
     *
     * @param fromPriceDiff 価格差
     * @param fromSymbolName 対象シンボル名
     * @return pips。ポイント取得失敗時は0。
     */
    static double priceToPips(const double fromPriceDiff, const string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return RateUtil::priceToPips(fromPriceDiff, context);
    }

    /**
     * 売買方向に応じた価格オフセットを取得する。
     *
     * @param fromIsBuy BUY方向の場合true、SELL方向の場合false
     * @param fromPips pips
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return 価格オフセット。
     */
    static double getOffset(bool fromIsBuy, double fromPips, MarketContext &fromMarketContext) {
        double offset = RateUtil::pipsToPrice(fromPips, fromMarketContext);

        if (fromIsBuy) {
            offset = 0 - offset;
        }

        return offset;
    }

    /**
     * シンボル名と売買方向から価格オフセットを取得する。
     *
     * @param fromIsBuy BUY方向の場合true、SELL方向の場合false
     * @param fromPips pips
     * @param fromSymbolName 対象シンボル名
     * @return 価格オフセット。
     */
    static double getOffset(bool fromIsBuy, double fromPips, string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return RateUtil::getOffset(fromIsBuy, fromPips, context);
    }

    /**
     * 2つのレート差をpipsで取得する（絶対値）。
     *
     * @param fromRate       基準レート
     * @param toRate         比較先レート
     * @param fromMarketContext 変換対象の市場コンテキスト
     * @return レート差の絶対値。
     */
    static double getDiffPips(const double fromRate, const double toRate, MarketContext &fromMarketContext) {
        const double diffPrice = toRate - fromRate;

        return MathAbs(RateUtil::priceToPips(diffPrice, fromMarketContext));
    }

    /**
     * シンボル名で2レート差をpipsで取得する。
     *
     * @param fromRate       基準レート
     * @param toRate         比較先レート
     * @param fromSymbolName シンボル名
     * @return レート差の絶対値。
     */
    static double getDiffPips(const double fromRate, const double toRate, const string fromSymbolName) {
        MarketContext context(fromSymbolName, PERIOD_CURRENT);

        return RateUtil::getDiffPips(fromRate, toRate, context);
    }
};
