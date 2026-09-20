//+------------------------------------------------------------------+
//|                                                         Mail.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>
#include <Mstng\Mail\MailValidationFileWriter.mqh>
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
     */
    static void sendMail(ElliotAll *fromElliotAll, bool isSendMail = false) {
        sendMail(fromElliotAll, isSendMail, NULL, PERIOD_CURRENT, "");
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
     * @param fromCorrectionTimeFrame 補正したH4またはH1。補正なしはPERIOD_CURRENT。
     * @param fromAlertText 補正印を含むチャートと同じアラート文言。補正なしは空文字列。
     */
    static void sendMail(
        ElliotAll *fromSource,
        bool fromIsSendMail,
        ElliotAll *fromJudgment,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame,
        const string fromAlertText
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
            body = getBody(fromSource);
        }

        // 通常版H1メールは、受信一覧の先頭で見分けられるようにする。
        if (MQLInfoString(MQL_PROGRAM_NAME) == "ZigZagElliot"
                && fromSource.marketContext.timeFrame == PERIOD_H1) {
            title = "★【H1】" + title;
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
     * @return メール本文文字列。
     */
    static string getBody(ElliotAll *fromElliotAll) {
        return getCommonBody(fromElliotAll) + getAnalysisBody(fromElliotAll);
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
     * 1つの分析結果から損切り候補と全時間足のElliott本文を生成する。
     *
     * @param fromElliotAll 表示する分析結果。
     * @return 損切り候補とElliott本文。
     */
    static string getAnalysisBody(ElliotAll *fromElliotAll) {
        string text = "";
        // ロスカット。
        text += StringFormat("%s\n", fromElliotAll.lossCut.getText());

        // 市場分析。
        //text += StringFormat("%s\n\n", fromElliotAll.marketActivityAnalyzer.toString());

        // エリオット。
        text += "エリオット\n";
        text += StringFormat("%s\n", fromElliotAll.getText());

        return text;
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
        text += "補正内容\n";
        text += StringFormat("%s：%s → %s\n\n",
            TimeUtil::convertTimeFrameToString(fromCorrectionTimeFrame),
            sourceCorrection.buySellLabel,
            judgmentCorrection.buySellLabel
        );
        text += "【補正後全体：判定・損切りに採用】\n";
        text += getAnalysisBody(fromJudgment);
        text += "\n【補正前全体：比較用】\n";
        text += getAnalysisBody(fromSource);
        return text;
    }

    /**
     * 比較メールの元分析と補正分析が同じ対象・方向補正に対応するか確認する。
     *
     * @param fromSource 補正前の元分析。
     * @param fromJudgment 採用した補正分析。
     * @param fromCorrectionTimeFrame 方向を補正したH4またはH1。
     * @param fromAlertText チャートと同じ件名用文言。
     * @return 完全なM5分析で、指定した片足だけ方向を補正した場合true。
     */
    static bool isCorrectionMailValid(
        ElliotAll *fromSource,
        ElliotAll *fromJudgment,
        const ENUM_TIMEFRAMES fromCorrectionTimeFrame,
        const string fromAlertText
    ) {
        if (fromSource == NULL || fromJudgment == NULL || fromSource == fromJudgment
                || !fromSource.isAnalysisSucceeded || !fromJudgment.isAnalysisSucceeded
                || fromSource.marketContext.timeFrame != PERIOD_M5
                || fromJudgment.marketContext.timeFrame != PERIOD_M5
                || fromSource.marketContext.symbolName == ""
                || fromSource.marketContext.symbolName != fromJudgment.marketContext.symbolName
                || fromSource.tradeTimeInfo.serverTime != fromJudgment.tradeTimeInfo.serverTime
                || fromSource.tradeTimeInfo.jstTime != fromJudgment.tradeTimeInfo.jstTime
                || fromAlertText == ""
                || (fromCorrectionTimeFrame != PERIOD_H4
                    && fromCorrectionTimeFrame != PERIOD_H1)) {
            return false;
        }

        Elliot *sourceCurrent = fromSource.getElliot(PERIOD_M5);
        Elliot *judgmentCurrent = fromJudgment.getElliot(PERIOD_M5);
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
        if (fromSource.elliotList.Total() != ArraySize(timeFrames)
                || fromJudgment.elliotList.Total() != ArraySize(timeFrames)) {
            return false;
        }
        for (int i = 0; i < ArraySize(timeFrames); i++) {
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

            if ((timeFrames[i] == PERIOD_H4 || timeFrames[i] == PERIOD_H1)
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
     * @return 通貨強弱順位。未検索の場合は空文字列。
     */
    static string getCurrencyStrengthText(ElliotAll *fromElliotAll) {
        CurrencyStrengthExecutionInfo executionInfo =
            fromElliotAll.currencyStrengthExecutionInfo;

        if (executionInfo.status
                == CURRENCY_STRENGTH_EXECUTION_STATUS_NOT_QUERIED) {
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
            );
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
            );
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
            );
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

        text += StringFormat(
            "長中期 %s\n",
            formatCurrencyStrengthSignal(longMediumDifference)
        );
        text += formatCurrencyStrengthRankList(executionInfo, true);
        text += "\n";
        text += StringFormat(
            "中短期 %s\n",
            formatCurrencyStrengthSignal(mediumShortDifference)
        );
        text += formatCurrencyStrengthRankList(executionInfo, false);
        text += StringFormat(
            "\nDB M5:%s\n\n",
            formatCurrencyStrengthM5BarTime(executionInfo)
        );

        return text;
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
