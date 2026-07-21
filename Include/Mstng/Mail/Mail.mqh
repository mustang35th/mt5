//+------------------------------------------------------------------+
//|                                                         Mail.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\AbstractExpertAdvisor.mqh>

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
        string title = getTitle(fromElliotAll);
        string body = getBody(fromElliotAll);
        
        /*if (fromElliotAll.isTimer && fromElliotAll.marketContext.timeFrame == PERIOD_M1) {
            Print(__FUNCTION__, " title = ", title);
        } else {*/
            Print(__FUNCTION__, " isSendMail = ", isSendMail);
            Print(__FUNCTION__, " title = ", title);
            Print(__FUNCTION__, " body = ", body);
        //}
        
        if (isSendMail) {
            if (fromElliotAll.isTimer) {
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
        
        string mark = "";
        
        if (fromElliotAll.marketContext.timeFrame == PERIOD_M5) {
            mark = "*";
        }
        
        return StringFormat("%s%s:%s:%s", mark, symbolName, buySellLabel, mailTitile);
    }
    
    /**
     * メール本文を生成する。
     *
     * @param fromElliotAll 解析結果を保持するインスタンス。
     * @return メール本文文字列。
     */
    static string getBody(ElliotAll *fromElliotAll) {
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

        if (executionInfo.status
                != CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND) {
            return StringFormat(
                "通貨強弱 SOURCE:%s\n状態:%s\n\n",
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
                "通貨強弱 SOURCE:%s%s\n状態:通貨ペア順位不正\n"
                    + "DB M5:%s\n\n",
                sourceMode,
                stateSuffix,
                formatCurrencyStrengthM5BarTime(executionInfo)
            );
        }

        if (!executionInfo.hasAllCurrencyRanks()) {
            return StringFormat(
                "通貨強弱 SOURCE:%s%s\n状態:順位データ不完全 %d/8\n"
                    + "DB M5:%s\n\n",
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
            "通貨強弱 %s SOURCE:%s%s\n\n",
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
