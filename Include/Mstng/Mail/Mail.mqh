//+------------------------------------------------------------------+
//|                                                         Mail.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>
#include <Mstng\Mail\Ema200DistanceMailPolicy.mqh>
#include <Mstng\Mail\MailValidationFileWriter.mqh>
#include <Mstng\Oscillator\PriceMovementInfo.mqh>
#include <Mstng\Strength\CurrencyStrengthCalculationProfile.mqh>

/**
 * Elliott分析結果を元にメールタイトルと本文を生成して送信するクラス。
 */
class Mail {
public:
    /**
     * メール内容を作成して送信する。
     *
     * @param fromElliotAll 解析結果を保持するインスタンス。
     * @param isSendMail 送信する場合true。
     * @param fromIsEntry エントリー成立時の本文を生成する場合true。
     */
    static void sendMail(ElliotAll *fromElliotAll, bool isSendMail = false, const bool fromIsEntry = false) {
        sendMail(fromElliotAll, isSendMail, NULL, PERIOD_CURRENT, "", fromIsEntry);
    }

    /**
     * 元分析の送信設定を使用し、必要な場合は補正前後の比較メールを送信する。
     *
     * 分析結果の所有権やメール設定は変更しない。検証ファイルにも同じ件名・本文を保存する。
     * 補正情報が不整合な場合は、元分析への代替送信を行わない。
     *
     * @param fromSource 送信設定と共通情報を保持する元分析。
     * @param fromIsSendMail 送信する場合true。
     * @param fromJudgment 採用した補正分析。補正なしの場合はNULL。
     * @param fromCorrectionTimeFrame 補正したD1・H4・H1・M15のいずれか。補正なしはPERIOD_CURRENT。
     * @param fromAlertText 補正印を含むチャートと同じアラート文言。補正なしは空文字列。
     * @param fromIsEntry エントリー成立時の本文を生成する場合true。
     */
    static void sendMail(
        ElliotAll *fromSource,
        bool fromIsSendMail,
        ElliotAll *fromJudgment,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame,
        const string fromAlertText,
        const bool fromIsEntry = false
    ) {
        if (fromSource == NULL || fromSource.elliotCurrent == NULL) {
            Print(__FUNCTION__, " mail skipped: source analysis is unavailable.");
            return;
        }

        bool hasCorrection = fromJudgment != NULL
            || fromCorrectionTimeFrame != PERIOD_CURRENT || fromAlertText != "";
        string title;
        string body;
        if (hasCorrection) {
            if (!isCorrectionMailValid(
                    fromSource, fromJudgment, fromCorrectionTimeFrame, fromAlertText)) {
                Print(__FUNCTION__, " corrected mail skipped: correction analysis is invalid.");
                return;
            }

            title = StringFormat("%s:%s:【%s】",
                fromSource.marketContext.symbolName,
                fromJudgment.elliotCurrent.buySellLabel,
                fromAlertText
            );
            body = getCorrectionBody(fromSource, fromJudgment, fromCorrectionTimeFrame);
        } else {
            title = getTitle(fromSource);
            body = getBody(fromSource, fromIsEntry);
        }

        ElliotAll *selectedAnalysis = fromSource;
        if (hasCorrection) {
            selectedAnalysis = fromJudgment;
        }

        // GMO対象の通貨名の直前に、通常・補正共通の目印を付ける。
        title = getGmoTitlePrefix(fromSource.marketContext.symbolName) + title;

        // 通常版はM15だけ時間足を先頭に置き、M5・M15の追加の方向・EMA距離の目印を省く。
        bool isSimpleTimeFrameTitle = MQLInfoString(MQL_PROGRAM_NAME) == "ZigZagElliot"
            && (selectedAnalysis.marketContext.timeFrame == PERIOD_M5
                || selectedAnalysis.marketContext.timeFrame == PERIOD_M15);
        if (isSimpleTimeFrameTitle) {
            if (selectedAnalysis.marketContext.timeFrame == PERIOD_M15) {
                title = "[M15] " + title;
            }
        } else {
            if (MQLInfoString(MQL_PROGRAM_NAME) == "ZigZagElliot") {
                title = getTitlePrefix(selectedAnalysis) + title;
            }

            title = getEma200DistancePrefix(selectedAnalysis) + title;
        }

        Print(__FUNCTION__, " isSendMail = ", fromIsSendMail);
        Print(__FUNCTION__, " title = ", title);
        Print(__FUNCTION__, " body = ", body);

        if (fromSource.isMailValidationFileEnabled) {
            MailValidationFileWriter::write(
                fromSource.tradeTimeInfo.jstTime,
                fromSource.tradeTimeInfo.serverTime,
                fromSource.marketContext.symbolName,
                fromSource.marketContext.timeFrame,
                fromSource.isTimer,
                fromIsSendMail,
                title,
                body
            );
        }

        if (fromIsSendMail) {
            if (fromSource.isTimer) {
                SendMail(title, body);
            }
        }
    }

private:
    /**
     * Viewerと同じGMO対象通貨にだけ件名の目印を付ける。
     *
     * 大文字・小文字、接頭辞・接尾辞を許容する。既知の通貨ペアが複数含まれる場合は付けない。
     * @param fromSymbolName 元分析のシンボル名。
     * @return GMO対象は[G]。対象外・未登録・曖昧なシンボル名は空文字列。
     */
    static string getGmoTitlePrefix(const string fromSymbolName) {
        SymbolNameInfoAll symbolNameInfoAll;
        symbolNameInfoAll.setGmo();
        if (!symbolNameInfoAll.isUniqueTarget(fromSymbolName)) {
            return "";
        }

        return "[G]";
    }

    /**
     * 採用分析のM5・M15・H1がメール用距離上限を超えた場合に件名接頭辞を作る。
     *
     * @param fromSelected 判定に採用した分析。補正時は補正後の分析。
     * @return 超過時は【EMA 距離/上限p】。未取得・対象外・上限以内は空文字列。
     */
    static string getEma200DistancePrefix(ElliotAll *fromSelected) {
        if (fromSelected == NULL || fromSelected.elliotCurrent == NULL
                || (fromSelected.marketContext.timeFrame != PERIOD_M5
                    && fromSelected.marketContext.timeFrame != PERIOD_M15
                    && fromSelected.marketContext.timeFrame != PERIOD_H1)) {
            return "";
        }

        double close1 = fromSelected.elliotCurrent.oscillator.ema200.close1;
        double ema200Shift1 = fromSelected.elliotCurrent.oscillator.ema200.ema200Shift1;
        if (!MathIsValidNumber(close1) || close1 <= 0.0 || close1 == EMPTY_VALUE
                || !MathIsValidNumber(ema200Shift1) || ema200Shift1 <= 0.0
                || ema200Shift1 == EMPTY_VALUE) {
            return "";
        }

        string quoteCurrency = SymbolInfoString(
            fromSelected.marketContext.symbolName, SYMBOL_CURRENCY_PROFIT);
        double distancePips = fromSelected.elliotCurrent.oscillator.ema200.closeEma200DiffPips;
        if (!Ema200DistanceMailPolicy::isExceeded(quoteCurrency, distancePips)) {
            return "";
        }

        double maxDistancePips = Ema200DistanceMailPolicy::getMaxDistancePips(quoteCurrency);
        string distanceText = formatEma200Distance(MathAbs(distancePips), maxDistancePips);

        return StringFormat("【EMA %s/%sp】", distanceText, DoubleToString(maxDistancePips, 0));
    }

    /**
     * 距離を短く表示し、丸めによって超過が上限と同値に見えることを防ぐ。
     *
     * @param fromDistancePips 上限を超えた絶対距離pips。
     * @param fromMaxDistancePips メール用上限pips。
     * @return 通常は整数。境界付近は小数、8桁でも区別できない場合は上限超過記号。
     */
    static string formatEma200Distance(const double fromDistancePips, const double fromMaxDistancePips) {
        for (int i = 0; i <= 8; i++) {
            if (NormalizeDouble(fromDistancePips, i) > fromMaxDistancePips) {
                return DoubleToString(fromDistancePips, i);
            }
        }

        return ">" + DoubleToString(fromMaxDistancePips, 0);
    }

    /**
     * H1の星と、H1・M5のW1 EMA200・MN1同方向を示す件名接頭辞を作る。
     *
     * 補正時は採用した分析を渡す。W1未取得・方向なし・両方向成立は一致扱いにしない。
     * MN1の目印はW1 EMA200一致時だけ追加し、単独では付けない。
     * @param fromSelected 判定に採用した分析。
     * @return 目印がある場合は末尾に半角スペースを含む接頭辞。
     */
    static string getTitlePrefix(ElliotAll *fromSelected) {
        if (fromSelected == NULL || fromSelected.elliotCurrent == NULL
                || (fromSelected.marketContext.timeFrame != PERIOD_H1
                    && fromSelected.marketContext.timeFrame != PERIOD_M5)) {
            return "";
        }

        string prefix = "";
        if (fromSelected.marketContext.timeFrame == PERIOD_H1) {
            prefix = "★";
        }
        Elliot *elliotW1 = fromSelected.getElliot(PERIOD_W1);
        if (elliotW1 != NULL) {
            bool emaBuy = elliotW1.oscillator.ema200.isBuy;
            bool emaSell = elliotW1.oscillator.ema200.isSell;
            bool isBuy = fromSelected.elliotCurrent.isBuy;
            if ((isBuy && emaBuy && !emaSell) || (!isBuy && emaSell && !emaBuy)) {
                prefix += "[WE]";
                Elliot *elliotMn1 = fromSelected.getElliot(PERIOD_MN1);
                if (elliotMn1 != NULL && elliotMn1.isBuy == isBuy) {
                    prefix += "[M]";
                }
            }
        }
        if (StringLen(prefix) > 0) {
            prefix += " ";
        }

        return prefix;
    }

    /**
     * メールタイトルを生成する。
     *
     * @param fromElliotAll 解析結果を保持するインスタンス。
     * @return メールタイトル文字列。
     */
    static string getTitle(ElliotAll *fromElliotAll) {
        string symbolName = fromElliotAll.marketContext.symbolName;
        string buySellLabel = fromElliotAll.elliotCurrent.buySellLabel;
        string mailTitile = fromElliotAll.mailTitile;
        
        return StringFormat("%s:%s:%s", symbolName, buySellLabel, mailTitile);
    }
    
    /**
     * メール本文を生成する。
     *
     * @param fromElliotAll 解析結果を保持するインスタンス。
     * @param fromIsEntry エントリーが成立した場合true。
     * @return メール本文文字列。
     */
    static string getBody(ElliotAll *fromElliotAll, const bool fromIsEntry) {
        string text = getCommonBody(fromElliotAll);
        if (fromIsEntry && fromElliotAll.marketContext.timeFrame == PERIOD_M1
                && fromElliotAll.isCurrencyStrengthEntryFilterEnabled
                && fromElliotAll.currencyStrengthExecutionInfo.isM1LongMediumPullbackApplied(fromElliotAll.elliotCurrent.isBuy)) {
            text += fromElliotAll.currencyStrengthExecutionInfo.longMediumGapDirection.getM1LongMediumPullbackText() + "\n\n";
        }

        return text + getAnalysisBody(fromElliotAll);
    }

    /**
     * 日時・レート・スプレッド・通貨強弱の共通部分を生成する。
     *
     * @param fromElliotAll 共通情報を保持する元分析。
     * @return メール本文の共通部分。
     */
    static string getCommonBody(ElliotAll *fromElliotAll) {
        string text = "";

        text += StringFormat("%s\n", TimeUtil::formatYyyymmddhhmiss(fromElliotAll.tradeTimeInfo.jstTime));

        // レート。
        TodayRate todayRate = fromElliotAll.todayRate;

        text += StringFormat("Bid:%s Ask:%s spread:%spips\n", todayRate.bidLabel, todayRate.askLabel, todayRate.spreadLabel);
        text += StringFormat("H:%s L:%s\n", todayRate.highLabel, todayRate.lowLabel);
        text += StringFormat("D:%spips", todayRate.diffLabel);

        if (todayRate.diffJpy > 0) {
            text += StringFormat(" D Jpy:%spips", todayRate.diffJpyLabel);
        }

        text += "\n\n";

        text += StringFormat("GMT:%s\n\n", TimeUtil::formatYyyymmddhhmiss(fromElliotAll.tradeTimeInfo.serverTime));

        // 通貨強弱。
        text += getCurrencyStrengthText(fromElliotAll);

        return text;
    }

    /**
     * 1つの分析結果から損切り候補、値動きおよび全時間足Elliott本文を生成する。
     *
     * @param fromElliotAll 表示する分析結果。
     * @param fromIncludePriceMovement 値動き一覧と通知対象足の詳細を掲載する場合true。
     * @return 損切り候補と再カウント前ラベル付きElliott本文。
     */
    static string getAnalysisBody(
        ElliotAll *fromElliotAll,
        const bool fromIncludePriceMovement = true
    ) {
        string text = "";
        // ロスカット。
        text += StringFormat("%s\n", fromElliotAll.lossCut.getText());

        if (fromIncludePriceMovement) {
            text += getPriceMovementBody(fromElliotAll);
        }

        // エリオット。
        text += "エリオット\n";
        text += StringFormat("%s\n", fromElliotAll.getText(true));

        return text;
    }

    /**
     * 保存済みの値動き結果から時間足別一覧と通知対象足の詳細を生成する。
     *
     * @param fromElliotAll 掲載する分析結果。補正メールでは採用した補正後の分析。
     * @return 値動きの本文。分析結果がない場合は空文字列。
     */
    static string getPriceMovementBody(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL) {
            return "";
        }

        string text = "値動き（確定足）\n";
        for (int i = fromElliotAll.elliotList.Total() - 1; i >= 0; i--) {
            Elliot *elliot = fromElliotAll.elliotList.At(i);
            if (elliot == NULL) {
                continue;
            }

            text += elliot.marketContext.timeFrameLabel + "："
                + getPriceMovementSummary(elliot.oscillator.priceMovement);
            if (elliot.marketContext.timeFrame == fromElliotAll.marketContext.timeFrame) {
                text += "［通知対象］";
            }

            text += "\n";
        }

        Elliot *currentElliot = fromElliotAll.elliotCurrent;
        if (currentElliot != NULL) {
            text += "\n" + currentElliot.marketContext.timeFrameLabel + "詳細\n";
            PriceMovementInfo priceMovement = currentElliot.oscillator.priceMovement;
            if (priceMovement.isValid) {
                text += StringFormat("平均値幅：%.1fpips\n", priceMovement.averageRangePips);
                text += StringFormat("基準ATR14：%.1fpips\n", priceMovement.referenceAtrPips);
                if (priceMovement.isSpreadValid) {
                    text += StringFormat("値幅／スプレッド：%.2f倍\n", priceMovement.rangeSpreadRatio);
                } else {
                    text += "値幅／スプレッド：取得不能\n";
                }
            } else {
                text += "判定不能\n";
            }
        }

        text += "\n";

        return text;
    }

    /**
     * チャートと同じ状態名と小数2桁のATR比をメール用に整形する。
     *
     * @param fromPriceMovement 保存済みの値動き結果。
     * @return 状態名とATR比。未取得の場合は判定不能。
     */
    static string getPriceMovementSummary(PriceMovementInfo &fromPriceMovement) {
        if (!fromPriceMovement.isValid) {
            return "判定不能";
        }

        string levelText = "";
        switch (fromPriceMovement.level) {
            case PRICE_MOVEMENT_CALM:
                levelText = "静か";
                break;
            case PRICE_MOVEMENT_NORMAL:
                levelText = "通常";
                break;
            case PRICE_MOVEMENT_ACTIVE:
                levelText = "活発";
                break;
            default:
                return "判定不能";
        }

        return StringFormat("%s %.2f倍", levelText, fromPriceMovement.activityRatio);
    }

    /**
     * 共通情報を1回だけ表示し、補正後全体と補正前全体を順に生成する。
     *
     * @param fromSource 補正前の元分析。
     * @param fromJudgment 判定と損切りに採用した補正分析。
     * @param fromCorrectionTimeFrame 方向を補正した時間足。
     * @return 補正内容と前後比較を含むメール本文。
     */
    static string getCorrectionBody(
        ElliotAll *fromSource,
        ElliotAll *fromJudgment,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame
    ) {
        Elliot *sourceCorrection = fromSource.getElliot(fromCorrectionTimeFrame);
        Elliot *judgmentCorrection = fromJudgment.getElliot(fromCorrectionTimeFrame);

        string text = getCommonBody(fromSource);
        text += getPriceMovementBody(fromJudgment);
        text += "補正内容\n";
        text += StringFormat("%s：%s → %s\n\n",
            TimeUtil::convertTimeFrameToString(fromCorrectionTimeFrame),
            sourceCorrection.buySellLabel,
            judgmentCorrection.buySellLabel
        );
        text += "【補正後全体：判定・損切りに採用】\n";
        text += getAnalysisBody(fromJudgment, false);
        text += "\n【補正前全体：比較用】\n";
        text += getAnalysisBody(fromSource, false);

        return text;
    }

    /**
     * 比較メールの元分析と補正分析が同じ対象・方向補正に対応するか確認する。
     *
     * @param fromSource 補正前の元分析。
     * @param fromJudgment 採用した補正分析。
     * @param fromCorrectionTimeFrame 方向を補正したD1・H4・H1・M15のいずれか。
     * @param fromAlertText チャートと同じ件名用文言。
     * @return 完全なH1・M15・M5分析で、対象上位足の1足だけ現在足方向へ補正した場合true。
     */
    static bool isCorrectionMailValid(
        ElliotAll *fromSource,
        ElliotAll *fromJudgment,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame,
        const string fromAlertText
    ) {
        if (fromSource == NULL || fromJudgment == NULL || fromSource == fromJudgment
                || !fromSource.isAnalysisSucceeded || !fromJudgment.isAnalysisSucceeded
                || (fromSource.marketContext.timeFrame != PERIOD_M5
                    && fromSource.marketContext.timeFrame != PERIOD_M15
                    && fromSource.marketContext.timeFrame != PERIOD_H1)
                || fromJudgment.marketContext.timeFrame != fromSource.marketContext.timeFrame
                || fromSource.marketContext.symbolName == ""
                || fromSource.marketContext.symbolName != fromJudgment.marketContext.symbolName
                || fromSource.tradeTimeInfo.serverTime != fromJudgment.tradeTimeInfo.serverTime
                || fromSource.tradeTimeInfo.jstTime != fromJudgment.tradeTimeInfo.jstTime
                || fromAlertText == "") {
            return false;
        }

        ENUM_TIMEFRAMES currentTimeFrame = fromSource.marketContext.timeFrame;
        ENUM_TIMEFRAMES higherTimeFrame = PERIOD_H4;
        ENUM_TIMEFRAMES lowerTimeFrame = PERIOD_H1;
        int expectedCount = 7;
        if (currentTimeFrame == PERIOD_H1 || currentTimeFrame == PERIOD_M15) {
            higherTimeFrame = PERIOD_D1;
            lowerTimeFrame = PERIOD_H4;
            expectedCount = 5;
            if (currentTimeFrame == PERIOD_M15) {
                expectedCount = 6;
            }
        }

        if (fromCorrectionTimeFrame != higherTimeFrame
                && fromCorrectionTimeFrame != lowerTimeFrame
                && (currentTimeFrame != PERIOD_M15 || fromCorrectionTimeFrame != PERIOD_H1)
                && (currentTimeFrame != PERIOD_M5 || fromCorrectionTimeFrame != PERIOD_M15)) {
            return false;
        }

        Elliot *sourceCurrent = fromSource.getElliot(currentTimeFrame);
        Elliot *judgmentCurrent = fromJudgment.getElliot(currentTimeFrame);
        if (sourceCurrent == NULL || judgmentCurrent == NULL
                || sourceCurrent != fromSource.elliotCurrent
                || judgmentCurrent != fromJudgment.elliotCurrent
                || sourceCurrent.isBuy != judgmentCurrent.isBuy) {
            return false;
        }

        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4,
            PERIOD_H1, PERIOD_M15, PERIOD_M5
        };
        if (fromSource.elliotList.Total() != expectedCount
                || fromJudgment.elliotList.Total() != expectedCount) {
            return false;
        }

        for (int i = 0; i < expectedCount; i++) {
            Elliot *sourceElliot = fromSource.getElliot(timeFrames[i]);
            Elliot *judgmentElliot = fromJudgment.getElliot(timeFrames[i]);
            if (sourceElliot == NULL || judgmentElliot == NULL
                    || sourceElliot.marketContext.symbolName != fromSource.marketContext.symbolName
                    || judgmentElliot.marketContext.symbolName != fromSource.marketContext.symbolName
                    || sourceElliot.marketContext.timeFrame != timeFrames[i]
                    || judgmentElliot.marketContext.timeFrame != timeFrames[i]
                    || sourceElliot.getLatestWave() == NULL || sourceElliot.getLatestPoint() == NULL
                    || judgmentElliot.getLatestWave() == NULL || judgmentElliot.getLatestPoint() == NULL
                    || sourceElliot.buySellLabel != Constant::getBuySell(sourceElliot.isBuy)
                    || judgmentElliot.buySellLabel != Constant::getBuySell(judgmentElliot.isBuy)) {
                return false;
            }

            if (timeFrames[i] == fromCorrectionTimeFrame) {
                if (sourceElliot.isBuy == sourceCurrent.isBuy
                        || judgmentElliot.isBuy != sourceCurrent.isBuy) {
                    return false;
                }
            } else if (sourceElliot.isBuy != judgmentElliot.isBuy) {
                return false;
            }

            if ((timeFrames[i] == higherTimeFrame || timeFrames[i] == lowerTimeFrame
                    || (currentTimeFrame == PERIOD_M15 && timeFrames[i] == PERIOD_H1)
                    || (currentTimeFrame == PERIOD_M5 && timeFrames[i] == PERIOD_M15))
                    && timeFrames[i] != fromCorrectionTimeFrame
                    && sourceElliot.isBuy != sourceCurrent.isBuy) {
                return false;
            }
        }

        return true;
    }

    /**
     * 実行時に参照した通貨強弱順位をメール本文へ変換する。
     *
     * @param fromElliotAll 解析結果を保持するインスタンス。
     * @return 通貨強弱順位。未検索かつ増減表示OFFの場合は空文字列。
     */
    static string getCurrencyStrengthText(ElliotAll *fromElliotAll) {
        CurrencyStrengthExecutionInfo executionInfo =
            fromElliotAll.currencyStrengthExecutionInfo;

        if (executionInfo.status
                == CURRENCY_STRENGTH_EXECUTION_STATUS_NOT_QUERIED
                && !executionInfo.gapDirectionMailEnabled) {
            return "";
        }

        string sourceMode = executionInfo.sourceMode;

        if (sourceMode == "") {
            sourceMode = "-";
        } else {
            StringToUpper(sourceMode);
        }

        string voteWeightMode =
            formatCurrencyStrengthVoteWeightMode(
                executionInfo.calculationVersion
            );

        if (executionInfo.status
                != CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND) {
            return StringFormat(
                "通貨強弱 MODE:%s SOURCE:%s\n状態:%s\n\n",
                voteWeightMode,
                sourceMode,
                formatCurrencyStrengthStatus(executionInfo.status)
            ) + formatCurrencyStrengthGapPeriods(executionInfo);
        }

        string stateSuffix = "";

        if (executionInfo.targetM5BarTime > 0
                && executionInfo.pairRankInfo.m5BarTime > 0
                && executionInfo.targetM5BarTime
                    != executionInfo.pairRankInfo.m5BarTime) {
            stateSuffix = " STALE";
        }

        if (!executionInfo.isAvailable()) {
            return StringFormat(
                "通貨強弱 MODE:%s SOURCE:%s%s\n状態:通貨ペア順位不正\n"
                    + "DB M5:%s\n\n",
                voteWeightMode,
                sourceMode,
                stateSuffix,
                formatCurrencyStrengthM5BarTime(executionInfo)
            ) + formatCurrencyStrengthGapPeriods(executionInfo);
        }

        if (!executionInfo.hasAllCurrencyRanks()) {
            return StringFormat(
                "通貨強弱 MODE:%s SOURCE:%s%s\n"
                    + "状態:順位データ不完全 %d/8\n"
                    + "DB M5:%s\n\n",
                voteWeightMode,
                sourceMode,
                stateSuffix,
                executionInfo.currencyRankCount,
                formatCurrencyStrengthM5BarTime(executionInfo)
            ) + formatCurrencyStrengthGapPeriods(executionInfo);
        }

        int longMediumDifference =
            executionInfo.getLongMediumRankDifference();
        int mediumShortDifference =
            executionInfo.getMediumShortRankDifference();

        string text = StringFormat(
            "通貨強弱 MODE:%s %s SOURCE:%s%s\n\n",
            voteWeightMode,
            formatCurrencyStrengthDecision(
                longMediumDifference,
                mediumShortDifference
            ),
            sourceMode,
            stateSuffix
        );

        text += formatCurrencyStrengthPeriod(executionInfo, true, true);
        text += "\n";
        text += formatCurrencyStrengthPeriod(executionInfo, false, true);
        text += StringFormat(
            "\nDB M5:%s\n\n",
            formatCurrencyStrengthM5BarTime(executionInfo)
        );

        return text;
    }

    /**
     * 全8通貨を表示できない場合も、メール表示が有効なら両期間の増減欄を追加する。
     */
    static string formatCurrencyStrengthGapPeriods(CurrencyStrengthExecutionInfo &fromInfo) {
        if (!fromInfo.gapDirectionMailEnabled) {
            return "";
        }

        return formatCurrencyStrengthPeriod(fromInfo, true, false) + "\n"
            + formatCurrencyStrengthPeriod(fromInfo, false, false) + "\n";
    }

    /**
     * 1期間の見出し・増減・任意の全通貨順位を生成する。表示OFF時は従来書式を保つ。
     */
    static string formatCurrencyStrengthPeriod(CurrencyStrengthExecutionInfo &fromInfo,
            const bool fromIsLongMedium, const bool fromShowRanks) {
        string periodText = "中短期";
        int difference = fromInfo.getMediumShortRankDifference();
        if (fromIsLongMedium) {
            periodText = "長中期";
            difference = fromInfo.getLongMediumRankDifference();
        }

        string signal = formatCurrencyStrengthSignal(difference);
        string suffix = "";
        if (fromInfo.gapDirectionMailEnabled) {
            if (!fromInfo.isExactM5Bar()) {
                signal = "--";
            }

            suffix = "【参考】";
            if (fromIsLongMedium) {
                suffix = "【参考：増減フィルタOFF】";
                if (fromInfo.longMediumGapDirectionFilterEnabled) {
                    suffix = "【判定ON】";
                }
            }
        }

        string text = periodText + " " + signal + suffix + "\n";
        if (fromInfo.gapDirectionMailEnabled) {
            if (fromIsLongMedium) {
                text += formatCurrencyStrengthGapText(fromInfo, fromInfo.longMediumGapDirection, difference);
            } else {
                text += formatCurrencyStrengthGapText(fromInfo, fromInfo.mediumShortGapDirection, difference);
            }
        }

        if (fromShowRanks) {
            text += formatCurrencyStrengthRankList(fromInfo, fromIsLongMedium);
        }

        return text;
    }

    /**
     * 分析と同じM5の増減値だけを本文へ出す。不足・古い値を0として表示しない。
     */
    static string formatCurrencyStrengthGapText(const CurrencyStrengthExecutionInfo &fromInfo,
            const CurrencyStrengthRankGapDirectionInfo &fromDirection, const int fromCurrentGap) {
        if (!fromInfo.isExactM5Bar() || !fromDirection.enabled || fromDirection.waiting
                || !fromDirection.currentAvailable || !fromDirection.hasPrevious
                || fromDirection.targetM5BarTime != fromInfo.targetM5BarTime
                || fromDirection.currentGap != fromCurrentGap
                || fromDirection.previousGap < -7 || fromDirection.previousGap > 7) {
            return "増減（M5）：--\n直近方向：不明（データ不足・未評価）\n直近増減：--\n";
        }

        int change = fromDirection.currentGap - fromDirection.previousGap;
        bool directionAvailable = (fromDirection.direction == 1 || fromDirection.direction == -1)
            && fromDirection.directionChangedAt > 0
            && fromDirection.directionChangedAt <= fromDirection.targetM5BarTime;
        string directionText = "横ばい／方向不明";
        if (change != 0) {
            directionText = formatCurrencyStrengthGapChange(fromDirection.previousGap,
                fromDirection.currentGap);
        } else if (directionAvailable && fromDirection.direction == 1) {
            directionText = "横ばい／上昇方向を維持";
        } else if (directionAvailable && fromDirection.direction == -1) {
            directionText = "横ばい／下降方向を維持";
        }

        string changedAt = "--";
        if (directionAvailable) {
            changedAt = TimeUtil::formatYyyymmddhhmiss(fromDirection.directionChangedAt) + " SRV";
        }

        return StringFormat("増減（M5）：%s → %s（%s）\n直近方向：%s\n直近増減：%s\n",
            formatCurrencyStrengthGapValue(fromDirection.previousGap),
            formatCurrencyStrengthGapValue(fromDirection.currentGap),
            formatCurrencyStrengthGapValue(change), directionText, changedAt);
    }

    /**
     * 正の順位差・増減には+を付け、横ばいの0は符号を付けずに表示する。
     */
    static string formatCurrencyStrengthGapValue(const int fromValue) {
        if (fromValue == 0) {
            return "0";
        }

        return StringFormat("%+d", fromValue);
    }

    /**
     * 増減の符号と売買方向の拡大・縮小・転換を区別して説明する。
     */
    static string formatCurrencyStrengthGapChange(const int fromPreviousGap, const int fromCurrentGap) {
        string directionText = "上昇／";
        if (fromCurrentGap < fromPreviousGap) {
            directionText = "下降／";
        }

        if (fromPreviousGap < 0 && fromCurrentGap > 0) {
            return directionText + "SELL→BUYへ転換";
        }

        if (fromPreviousGap > 0 && fromCurrentGap < 0) {
            return directionText + "BUY→SELLへ転換";
        }

        if (fromCurrentGap == 0) {
            return directionText + "同順位へ";
        }

        if (fromPreviousGap == 0) {
            if (fromCurrentGap > 0) {
                return directionText + "同順位からBUY方向へ";
            }

            return directionText + "同順位からSELL方向へ";
        }

        if (fromCurrentGap > 0) {
            if (fromCurrentGap > fromPreviousGap) {
                return directionText + "BUY方向へ拡大";
            }

            return directionText + "BUY方向の差が縮小";
        }

        if (fromCurrentGap < fromPreviousGap) {
            return directionText + "SELL方向へ拡大";
        }

        return directionText + "SELL方向の差が縮小";
    }

    /**
     * 集計ルール識別子を票ウェイト方式の表示文字列へ変換する。
     *
     * @param fromCalculationVersion 集計ルール識別子。
     * @return WEIGHTED、UNIFORMまたはハイフン。
     */
    static string formatCurrencyStrengthVoteWeightMode(
        const string fromCalculationVersion
    ) {
        string weightedCalculationVersion =
            CurrencyStrengthCalculationProfile::getCalculationVersion(
                false,
                CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED
            );

        if (fromCalculationVersion == weightedCalculationVersion) {
            return CurrencyStrengthCalculationProfile::getVoteWeightModeText(
                CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED
            );
        }

        string uniformCalculationVersion =
            CurrencyStrengthCalculationProfile::getCalculationVersion(
                false,
                CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM
            );

        if (fromCalculationVersion == uniformCalculationVersion) {
            return CurrencyStrengthCalculationProfile::getVoteWeightModeText(
                CURRENCY_STRENGTH_VOTE_WEIGHT_UNIFORM
            );
        }

        return "-";
    }

    /**
     * 通貨強弱の取得状態を表示文字列へ変換する。
     *
     * @param fromStatus 通貨強弱の取得状態。
     * @return 取得状態表示文字列。
     */
    static string formatCurrencyStrengthStatus(
        const ENUM_CURRENCY_STRENGTH_EXECUTION_STATUS fromStatus
    ) {
        if (fromStatus
                == CURRENCY_STRENGTH_EXECUTION_STATUS_DATABASE_NOT_FOUND) {
            return "DBなし";
        }

        if (fromStatus
                == CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND) {
            return "データなし";
        }

        if (fromStatus == CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR) {
            return "取得エラー";
        }

        return "未取得";
    }

    /**
     * 長中期と中短期の順位方向一致状態を表示文字列へ変換する。
     *
     * @param fromLongMediumDifference 長中期順位差。
     * @param fromMediumShortDifference 中短期順位差。
     * @return BUY一致、SELL一致またはMIXED。
     */
    static string formatCurrencyStrengthDecision(
        const int fromLongMediumDifference,
        const int fromMediumShortDifference
    ) {
        if (fromLongMediumDifference > 0
                && fromMediumShortDifference > 0) {
            return "BUY一致";
        }

        if (fromLongMediumDifference < 0
                && fromMediumShortDifference < 0) {
            return "SELL一致";
        }

        return "MIXED";
    }

    /**
     * 順位差を売買方向表示へ変換する。
     *
     * @param fromDifference 決済通貨順位から基軸通貨順位を引いた値。
     * @return BUY、SELLまたはFLATと順位差。
     */
    static string formatCurrencyStrengthSignal(const int fromDifference) {
        if (fromDifference > 0) {
            return StringFormat("BUY +%d", fromDifference);
        }

        if (fromDifference < 0) {
            return StringFormat("SELL %d", fromDifference);
        }

        return "FLAT 0";
    }

    /**
     * 指定期間の全通貨順位を縦1列の表示文字列へ変換する。
     *
     * @param fromInfo 実行時通貨強弱情報。
     * @param fromIsLongMedium 長中期順位の場合true。
     * @return 順位昇順の全通貨順位。
     */
    static string formatCurrencyStrengthRankList(
        CurrencyStrengthExecutionInfo &fromInfo,
        const bool fromIsLongMedium
    ) {
        int rankIndexes[8];

        for (int i = 0; i < fromInfo.currencyRankCount; i++) {
            rankIndexes[i] = i;
        }

        sortCurrencyStrengthRankIndexes(
            fromInfo,
            fromIsLongMedium,
            rankIndexes
        );

        string text = "";

        for (int i = 0; i < fromInfo.currencyRankCount; i++) {
            int rankInfoIndex = rankIndexes[i];
            int rank = getCurrencyStrengthRank(
                fromInfo,
                rankInfoIndex,
                fromIsLongMedium
            );
            string currency =
                fromInfo.currencyRankInfos[rankInfoIndex].currencyName;

            text += StringFormat(
                "%d位 %s\n",
                rank,
                formatCurrencyStrengthCurrencyMark(fromInfo, currency)
            );
        }

        return text;
    }

    /**
     * 全通貨順位の配列番号を順位と通貨コードの昇順へ並べ替える。
     *
     * @param fromInfo 実行時通貨強弱情報。
     * @param fromIsLongMedium 長中期順位の場合true。
     * @param fromRankIndexes 並べ替える配列番号一覧。
     */
    static void sortCurrencyStrengthRankIndexes(
        CurrencyStrengthExecutionInfo &fromInfo,
        const bool fromIsLongMedium,
        int &fromRankIndexes[]
    ) {
        int rankCount = ArraySize(fromRankIndexes);

        for (int i = 0; i < rankCount - 1; i++) {
            for (int j = i + 1; j < rankCount; j++) {
                int leftIndex = fromRankIndexes[i];
                int rightIndex = fromRankIndexes[j];
                int leftRank = getCurrencyStrengthRank(
                    fromInfo,
                    leftIndex,
                    fromIsLongMedium
                );
                int rightRank = getCurrencyStrengthRank(
                    fromInfo,
                    rightIndex,
                    fromIsLongMedium
                );
                string leftCurrency =
                    fromInfo.currencyRankInfos[leftIndex].currencyName;
                string rightCurrency =
                    fromInfo.currencyRankInfos[rightIndex].currencyName;
                bool shouldSwap = leftRank > rightRank;

                if (leftRank == rightRank
                        && StringCompare(leftCurrency, rightCurrency) > 0) {
                    shouldSwap = true;
                }

                if (shouldSwap) {
                    fromRankIndexes[i] = rightIndex;
                    fromRankIndexes[j] = leftIndex;
                }
            }
        }
    }

    /**
     * 指定した通貨の期間別順位を取得する。
     *
     * @param fromInfo 実行時通貨強弱情報。
     * @param fromIndex 通貨順位情報の配列番号。
     * @param fromIsLongMedium 長中期順位の場合true。
     * @return 期間別順位。
     */
    static int getCurrencyStrengthRank(
        CurrencyStrengthExecutionInfo &fromInfo,
        const int fromIndex,
        const bool fromIsLongMedium
    ) {
        if (fromIsLongMedium) {
            return fromInfo.currencyRankInfos[fromIndex]
                .longMediumTermAverageRank;
        }

        return fromInfo.currencyRankInfos[fromIndex]
            .mediumShortTermAverageRank;
    }

    /**
     * 通貨コードの右側へ基軸通貨または決済通貨の印を付ける。
     *
     * @param fromInfo 実行時通貨強弱情報。
     * @param fromCurrency 通貨コード。
     * @return 通貨コードと対象通貨の印。
     */
    static string formatCurrencyStrengthCurrencyMark(
        CurrencyStrengthExecutionInfo &fromInfo,
        const string fromCurrency
    ) {
        string text = fromCurrency;

        if (fromCurrency == fromInfo.pairRankInfo.baseCurrency) {
            text += " [B]";
        }

        if (fromCurrency == fromInfo.pairRankInfo.quoteCurrency) {
            text += " [Q]";
        }

        return text;
    }

    /**
     * 取得した通貨強弱レコードのM5バー時刻を表示文字列へ変換する。
     *
     * @param fromInfo 実行時通貨強弱情報。
     * @return M5バー時刻。未取得の場合はハイフン。
     */
    static string formatCurrencyStrengthM5BarTime(
        CurrencyStrengthExecutionInfo &fromInfo
    ) {
        if (fromInfo.pairRankInfo.m5BarTimeText != "") {
            return fromInfo.pairRankInfo.m5BarTimeText;
        }

        if (fromInfo.pairRankInfo.m5BarTime > 0) {
            return TimeToString(
                fromInfo.pairRankInfo.m5BarTime,
                TIME_DATE | TIME_MINUTES
            );
        }

        return "-";
    }

};

/*
ZigZagElliot NZDUSD.oj1m,M15: MailAbstractExpertAdvisor::sendMail isSendMail=true
ZigZagElliot NZDUSD.oj1m,M15: MailAbstractExpertAdvisor::sendMail mailTitle=NZDUSD:BUY[▲3-<IF>5-3-<F>3]:
ZigZagElliot NZDUSD.oj1m,M15: MailAbstractExpertAdvisor::sendMail mailBody=2026/02/10 11:15:00
Bid:0.60499 Ask:0.60513 spread:1.4pips
H:0.60555 L:0.60305 D:25pips

LC M15
diff:20.8pips
0->0.60305
5->0.60255
10->0.60205
15->0.60155

エリオット最新
MN1:★▼4[F71.1%]<635.2p>0.61198
BUY/ S/+3/ M/+3/+9/ H/+1/ G/0/0/
 -> +3

W1:未▲C[FE81.4%]<517.0p>0.60920
BUY/ S/+4/ M/+5/+10/ H/+4/ G/0/0/
 -> +3

D1:▲3[FE137.4%]<381.5p>0.60920
BUY/ S/+2/ M/+2/-4/ H/+16/ G/0/0/
 -> +3

H4:IMP:FRA:未▲5[FE35.9%]<131.8p>0.60594
BUY/ S/-1/ M/+13/+10/ H/+10/ G/0/0/
 -> +2

H1:▲3[FE59.5%]<63.0p>0.60594
BUY/ S/+1/ M/-6/-3/ H/+15/ G/+16/+28/
 -> +2

M15:FRA:★▲3[FE39.7%]<25.0p>0.60555
BUY/ S/+7/ M/+3/+1/ H/+1/ G/+3/+171/
 -> +3

*/
