#ifndef MSTNG_DRAW_ELLIOT_PANEL_LIVE_ADAPTER_MQH
#define MSTNG_DRAW_ELLIOT_PANEL_LIVE_ADAPTER_MQH

#include <Mstng\Draw\ElliotPanelData.mqh>
#include <Mstng\Draw\ElliotTableFormatter.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Strength\CurrencyStrengthExecutionInfo.mqh>
#include <Mstng\Util\StringUtil.mqh>
#include <Mstng\Util\TimeJapanUtil.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 計算済みの現在波動と通貨強弱を、共通パネルの表示用データへ変換する。
 * DB照会・指標計算を行わず、分析時点の値と取得状態をそのまま保持する。
 */
class ElliotPanelLiveAdapter {
public:
    /**
     * 現在の全分析時間足と、取得済みの通貨強弱からパネル一枚分を構築する。
     *
     * @param fromElliotAll 計算済みの全時間足。所有権は取得しない。
     * @param fromStrength 現在の通貨強弱キャッシュ。
     * @param fromStrengthEnabled 通貨強弱の表示元設定が有効な場合true。
     * @param fromWeightLabel 使用中の投票方式表示名。
     * @param fromData 出力先の中立な表示用データ。
     * @return 一時間足以上の分析対象が存在する場合true。
     */
    static bool build(ElliotAll *fromElliotAll, const CurrencyStrengthExecutionInfo &fromStrength,
            const bool fromStrengthEnabled, const string fromWeightLabel, ElliotPanelData &fromData) {
        fromData.clear();
        if (fromElliotAll == NULL) {
            fromData.status = "分析データの準備待ち";

            return false;
        }

        fromData.symbolName = fromElliotAll.marketContext.symbolName;
        fromData.digits = fromElliotAll.marketContext.digits;
        fromData.headerTime = "分析時刻 未取得";
        if (fromElliotAll.tradeTimeInfo.jstTime > 0) {
            fromData.headerTime = "分析 JST "
                + TimeUtil::formatYyyymmddhhmiss(fromElliotAll.tradeTimeInfo.jstTime);
        } else if (fromElliotAll.tradeTimeInfo.serverTime > 0) {
            fromData.headerTime = "分析 SRV "
                + TimeUtil::formatYyyymmddhhmiss(fromElliotAll.tradeTimeInfo.serverTime);
        }

        fromData.metadata = "チャート " + fromElliotAll.marketContext.timeFrameLabel;
        if (fromElliotAll.tradeTimeInfo.serverTime > 0) {
            fromData.metadata += " / SRV "
                + TimeUtil::formatYyyymmddhhmiss(fromElliotAll.tradeTimeInfo.serverTime);
        }

        fromData.hint = "現在の分析結果 / 行選択で詳細 / 保存マーカーで過去を表示";
        for (int i = fromElliotAll.elliotList.Total() - 1; i >= 0 && fromData.rowCount < 8; i--) {
            Elliot *elliot = fromElliotAll.elliotList.At(i);
            if (elliot == NULL) {
                continue;
            }

            fillFrame(elliot, fromData.frames[fromData.rowCount], fromData.palette);
            fromData.rowCount++;
        }

        fillStrength(fromStrength, fromStrengthEnabled, fromWeightLabel,
            fromElliotAll.symbolNameLeft, fromElliotAll.symbolNameRight, fromData.strength);
        if (fromData.rowCount == 0) {
            fromData.status = "分析データの準備待ち";

            return false;
        }

        return true;
    }

    /**
     * 計算済みの最新波動を、チャート表とパネル共通の五列データへ写す。
     */
    static bool fillTableRow(Elliot &fromElliot, Wave *fromWave, ElliotTableRowData &fromRow) {
        fromRow.clear();
        fromRow.timeFrameLabel = fromElliot.marketContext.timeFrameLabel;
        if (fromWave == NULL) {
            return false;
        }

        ZigZagPoint *point = fromWave.getLatestPoint();
        if (point == NULL) {
            return false;
        }

        fromRow.hasData = true;
        fromRow.isBuy = (int)fromElliot.isBuy;
        fromRow.isUptrend = (int)fromWave.isUptrend;
        fromRow.isConfirmed = (int)fromWave.isConfirmed;
        fromRow.isAdded = (int)point.isAddedPoint;
        fromRow.mainWave = point.elliotLabel;
        fromRow.subWave = point.subElliotLabel;
        fromRow.originalWave = point.orgElliotLabel;
        fromRow.originalWaveIndex = point.orgElliotIndex;
        fromRow.previousMotiveSubElliotIndex = fromWave.getPreviousMotiveSubElliotIndex();

        fromRow.pointPipsDiff = point.pipsDiff;
        fromRow.hasPointPipsDiff = true;
        fromRow.pointFibonacciPercent = point.fibonacciPercent;
        fromRow.hasPointFibonacciPercent = true;
        fromRow.pointFibonacciExpansionPercent = point.fibonacciExpansionPercent;
        fromRow.hasPointFibonacciExpansionPercent = true;
        fromRow.pointRate = point.rate;
        fromRow.hasPointRate = true;

        fromRow.isEma200Buy = (int)fromElliot.oscillator.ema200.isBuy;
        fromRow.isEma200Sell = (int)fromElliot.oscillator.ema200.isSell;
        fillPriceMovementRow(fromElliot.oscillator.priceMovement, fromRow);

        return true;
    }

    /**
     * 値動きの取得状態を保持し、計算済みのゼロを欠損と区別する。
     */
    static void fillPriceMovementRow(PriceMovementInfo &fromPriceMovement, ElliotTableRowData &fromRow) {
        fromRow.isPriceMovementValid = (int)fromPriceMovement.isValid;
        fromRow.priceMovementLevel = (int)fromPriceMovement.level;
        fromRow.priceMovementActivityRatio = fromPriceMovement.activityRatio;
        fromRow.hasPriceMovementActivityRatio = fromPriceMovement.isValid;
    }

    /**
     * 計算済みの値動き詳細を、従来表と共通パネルのツールチップへ渡す。
     */
    static string getPriceMovementTooltip(PriceMovementInfo &fromPriceMovement) {
        ElliotTableRowData row;
        row.hasData = true;
        fillPriceMovementRow(fromPriceMovement, row);
        string text = "値動き：" + ElliotTableFormatter::movementLevelText(row);
        if (!fromPriceMovement.isValid) {
            return text + "\n計算に必要なデータを取得できません。";
        }

        text += StringFormat("\n直近3本の平均値幅：%.1f pips", fromPriceMovement.averageRangePips);
        text += StringFormat("\n基準ATR14（直近3本より前）：%.1f pips", fromPriceMovement.referenceAtrPips);
        text += StringFormat("\n活動度：%.2f倍", fromPriceMovement.activityRatio);
        if (fromPriceMovement.isSpreadValid) {
            text += StringFormat("\n値幅／スプレッド：%.2f倍", fromPriceMovement.rangeSpreadRatio);
        } else {
            text += "\n値幅／スプレッド：取得不能";
        }

        text += "\n最新確定足 SRV："
            + TimeUtil::formatYyyymmddhhmiss(fromPriceMovement.referenceBarTime);

        return text;
    }

private:
    /**
     * 一時間足の波動詳細と、従来の追加オシレーター項目を構築する。
     */
    static void fillFrame(Elliot &fromElliot, ElliotPanelFrame &fromFrame,
            const ElliotTablePalette &fromPalette) {
        fromFrame.clear();
        fromFrame.timeFrame = (int)fromElliot.marketContext.timeFrame;
        Wave *wave = fromElliot.getLatestWave();
        if (!fillTableRow(fromElliot, wave, fromFrame.row)) {
            return;
        }

        fromFrame.movementTooltip = getPriceMovementTooltip(fromElliot.oscillator.priceMovement);
        ZigZagPoint *point = wave.getLatestPoint();
        fromFrame.pointTime = point.barTime;
        if (point.barTime > 0) {
            fromFrame.pointJstTime = TimeJapanUtil::getJapanTime(point.barTime);
        }

        setExtra(fromFrame, 0, "SMO", fromElliot.oscillator.getStochasticMainOrderText(),
            fromElliot.oscillator.getStochasticMainOrderColor());
        setCountExtra(fromFrame, 1, "Stoch 短期", fromElliot.oscillator.stochasticShort.count, fromPalette);
        setCountExtra(fromFrame, 2, "Stoch 中期", fromElliot.oscillator.stochasticMiddle.count, fromPalette);
        setCountExtra(fromFrame, 3, "Stoch 長期", fromElliot.oscillator.stochasticLong.count, fromPalette);
        setCountExtra(fromFrame, 4, "GMMA Trend", fromElliot.oscillator.gmmaTrendCount, fromPalette);
        setCountExtra(fromFrame, 5, "GMMA Cross", fromElliot.oscillator.gmmaCrossCount, fromPalette);
        string previousLabel = wave.previousLastElliotLabel;
        color previousColor = fromPalette.downColor;
        if (fromElliot.isBuy) {
            previousColor = fromPalette.upColor;
        }
        if (StringLen(previousLabel) == 0) {
            previousLabel = "なし";
        }
        if (previousLabel == "A" || previousLabel == "E") {
            previousColor = fromPalette.neutralColor;
        }

        setExtra(fromFrame, 6, "PLE", previousLabel, previousColor);
        fromFrame.extraCount = 7;
    }

    /**
     * 追加項目一つの表示値を格納する。
     */
    static void setExtra(ElliotPanelFrame &fromFrame, const int fromIndex,
            const string fromLabel, const string fromValue, const color fromColor) {
        fromFrame.extraLabels[fromIndex] = fromLabel;
        fromFrame.extraValues[fromIndex] = fromValue;
        fromFrame.extraColors[fromIndex] = fromColor;
    }

    /**
     * 正負付き回数と従来の方向色を追加項目へ格納する。
     */
    static void setCountExtra(ElliotPanelFrame &fromFrame, const int fromIndex,
            const string fromLabel, const int fromCount, const ElliotTablePalette &fromPalette) {
        color textColor = fromPalette.neutralColor;
        if (fromCount > 0) {
            textColor = fromPalette.upColor;
        } else if (fromCount < 0) {
            textColor = fromPalette.downColor;
        }

        setExtra(fromFrame, fromIndex, fromLabel, StringUtil::addSign(fromCount), textColor);
    }

    /**
     * 現在の順位キャッシュを表示用へ写し、参照方式・時刻を明示する。
     */
    static void fillStrength(const CurrencyStrengthExecutionInfo &fromInfo, const bool fromEnabled,
            const string fromWeightLabel, const string fromBaseCurrency, const string fromQuoteCurrency,
            ElliotPanelStrength &fromStrength) {
        fromStrength.clear();
        fromStrength.enabled = fromEnabled;
        fromStrength.baseCurrency = fromBaseCurrency;
        fromStrength.quoteCurrency = fromQuoteCurrency;
        fromStrength.title = "現在の通貨強弱 / " + fromWeightLabel;
        if (StringLen(fromInfo.sourceMode) > 0) {
            fromStrength.title += " / " + fromInfo.sourceMode;
        }

        fromStrength.tooltip = "現在の通貨強弱取得値です。";
        if (!fromEnabled) {
            fromStrength.status = "通貨強弱OFF";

            return;
        }

        if (fromInfo.status == CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR) {
            fromStrength.status = "読取失敗";
        } else if (fromInfo.status == CURRENCY_STRENGTH_EXECUTION_STATUS_NOT_QUERIED) {
            fromStrength.status = "取得待ち";
        } else if (fromInfo.status == CURRENCY_STRENGTH_EXECUTION_STATUS_DATABASE_NOT_FOUND) {
            fromStrength.status = "DBなし";
        } else if (fromInfo.status == CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND) {
            fromStrength.status = "未記録";
        } else if (!fromInfo.isAvailable()) {
            fromStrength.status = "順位データ不正";
        } else if (!fromInfo.isExactM5Bar()) {
            fromStrength.status = "対象M5と不一致";
        } else {
            fromStrength.status = "";
            fromStrength.baseCurrency = fromInfo.pairRankInfo.baseCurrency;
            fromStrength.quoteCurrency = fromInfo.pairRankInfo.quoteCurrency;
            fromStrength.tooltip += "\n参照 SRV "
                + TimeUtil::formatYyyymmddhhmiss(fromInfo.pairRankInfo.m5BarTime)
                + " / Run " + IntegerToString(fromInfo.pairRankInfo.runId);
            fillStrengthPeriod(fromInfo.pairRankInfo.baseLongMediumTermAverageRank,
                fromInfo.pairRankInfo.quoteLongMediumTermAverageRank, fromInfo.targetM5BarTime,
                fromInfo.longMediumGapDirection, fromStrength.longMedium);
            fillStrengthPeriod(fromInfo.pairRankInfo.baseMediumShortTermAverageRank,
                fromInfo.pairRankInfo.quoteMediumShortTermAverageRank, fromInfo.targetM5BarTime,
                fromInfo.mediumShortGapDirection, fromStrength.mediumShort);
        }
    }

    /**
     * 順位差を保持し、同じ現在M5に対応する直前M5値がある場合だけ比較する。
     */
    static void fillStrengthPeriod(const int fromBaseRank, const int fromQuoteRank,
            const datetime fromTargetTime, const CurrencyStrengthRankGapDirectionInfo &fromDirection,
            ElliotPanelStrengthPeriod &fromPeriod) {
        fromPeriod.clear();
        fromPeriod.valid = fromBaseRank >= 1 && fromBaseRank <= 8
            && fromQuoteRank >= 1 && fromQuoteRank <= 8;
        if (!fromPeriod.valid) {
            return;
        }

        fromPeriod.baseRank = fromBaseRank;
        fromPeriod.quoteRank = fromQuoteRank;
        fromPeriod.gap = fromQuoteRank - fromBaseRank;
        fromPeriod.comparable = fromDirection.enabled && !fromDirection.waiting
            && fromDirection.currentAvailable && fromDirection.hasPrevious
            && fromTargetTime > 0 && fromDirection.targetM5BarTime == fromTargetTime
            && fromDirection.currentGap == fromPeriod.gap
            && fromDirection.previousGap >= -7 && fromDirection.previousGap <= 7;
        if (fromPeriod.comparable) {
            fromPeriod.delta = fromDirection.currentGap - fromDirection.previousGap;
        }
    }
};

#endif // MSTNG_DRAW_ELLIOT_PANEL_LIVE_ADAPTER_MQH
