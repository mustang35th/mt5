//+------------------------------------------------------------------+
//|                                      CurrencyStrengthInfo.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property strict

#ifndef MSTNG_CURRENCY_STRENGTH_INFO_MQH
#define MSTNG_CURRENCY_STRENGTH_INFO_MQH

#include <Object.mqh>

/**
 * 1通貨分の時間足別強弱スコアを保持する。
 */
class CurrencyStrengthInfo : public CObject {
public:
    /** 通貨コード。 */
    string currencyName;

    /**
     * 通貨コードを指定して初期化する。
     *
     * @param fromCurrencyName 通貨コード。
     */
    CurrencyStrengthInfo(string fromCurrencyName) {
        this.currencyName = fromCurrencyName;
        this.reset();
    }

    /**
     * 時間足別の集計値を初期化する。
     */
    void reset() {
        for (int i = 0; i < 7; i++) {
            this.rawScores[i] = 0;
            this.sampleCounts[i] = 0;
        }
    }

    /**
     * 指定時間足へ強弱値を加算する。
     *
     * @param fromTimeFrameIndex 時間足番号。
     * @param fromScore 加算する強弱値。
     */
    void addScore(int fromTimeFrameIndex, int fromScore) {
        if (fromTimeFrameIndex < 0 || fromTimeFrameIndex >= 7) {
            return;
        }

        this.rawScores[fromTimeFrameIndex] += fromScore;
        this.sampleCounts[fromTimeFrameIndex]++;
    }

    /**
     * 指定時間足の未正規化スコアを取得する。
     *
     * @param fromTimeFrameIndex 時間足番号。
     * @return 指定時間足の有効票合計。
     */
    double getScore(int fromTimeFrameIndex) {
        if (fromTimeFrameIndex < 0 || fromTimeFrameIndex >= 7) {
            return 0.0;
        }

        int sampleCount = this.sampleCounts[fromTimeFrameIndex];

        if (sampleCount <= 0) {
            return 0.0;
        }

        return (double)this.rawScores[fromTimeFrameIndex];
    }

    /**
     * 長期スコア平均を取得する。
     *
     * @return MN1、W1、D1の未正規化スコア平均。
     */
    double getLongTermAverageScore() {
        return (
            this.getScore(0)
            + this.getScore(1)
            + this.getScore(2)
        ) / 3.0;
    }

    /**
     * 長中期スコア平均を取得する。
     *
     * @return MN1、W1、D1、H4、H1の未正規化スコア平均。
     */
    double getLongMediumTermAverageScore() {
        return (
            this.getScore(0)
            + this.getScore(1)
            + this.getScore(2)
            + this.getScore(3)
            + this.getScore(4)
        ) / 5.0;
    }

    /**
     * 中期スコア平均を取得する。
     *
     * @return D1、H4、H1の未正規化スコア平均。
     */
    double getMediumTermAverageScore() {
        return (
            this.getScore(2)
            + this.getScore(3)
            + this.getScore(4)
        ) / 3.0;
    }

    /**
     * 中短期スコア平均を取得する。
     *
     * @return D1、H4、H1、M15、M5の未正規化スコア平均。
     */
    double getMediumShortTermAverageScore() {
        return (
            this.getScore(2)
            + this.getScore(3)
            + this.getScore(4)
            + this.getScore(5)
            + this.getScore(6)
        ) / 5.0;
    }

    /**
     * 短期スコア平均を取得する。
     *
     * @return H1、M15、M5の未正規化スコア平均。
     */
    double getShortTermAverageScore() {
        return (
            this.getScore(4)
            + this.getScore(5)
            + this.getScore(6)
        ) / 3.0;
    }

    /**
     * 指定時間足の有効票数を取得する。
     *
     * @param fromTimeFrameIndex 時間足番号。
     * @return 有効票数。
     */
    int getSampleCount(int fromTimeFrameIndex) {
        if (fromTimeFrameIndex < 0 || fromTimeFrameIndex >= 7) {
            return 0;
        }

        return this.sampleCounts[fromTimeFrameIndex];
    }

    /**
     * 全時間足の未正規化総合スコアを取得する。
     *
     * @return 全時間足の有効票合計。
     */
    double getTotalScore() {
        int rawScore = 0;
        int sampleCount = 0;

        for (int i = 0; i < 7; i++) {
            rawScore += this.rawScores[i];
            sampleCount += this.sampleCounts[i];
        }

        if (sampleCount <= 0) {
            return 0.0;
        }

        return (double)rawScore;
    }

    /**
     * 全時間足の有効票数を取得する。
     *
     * @return 有効票数。
     */
    int getTotalSampleCount() {
        int sampleCount = 0;

        for (int i = 0; i < 7; i++) {
            sampleCount += this.sampleCounts[i];
        }

        return sampleCount;
    }

private:
    /** 時間足別の未正規化スコア。 */
    int rawScores[7];

    /** 時間足別の有効票数。 */
    int sampleCounts[7];
};

#endif
