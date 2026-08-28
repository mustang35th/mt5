//+------------------------------------------------------------------+
//|       ZigZagElliotH1StudyConditionBreakdownExporter.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Arrays\ArrayDouble.mqh>
#include <Mstng\Analysis\ZigZagElliotH1StudyOutcomeCalculator.mqh>
#include <Mstng\Analysis\ZigZagElliotH1StudyQueryService.mqh>
#include <Mstng\Common\File\CsvFileWriter.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/** 参照元H1推移DBファイル名。 */
input string sourceDatabaseFileName =
    "mstng-zigzag-elliot-h1-study-2024-2025-r1.sqlite";

/** 参照元Observation Run ID。0の場合は唯一のRunを自動選択する。 */
input long sourceRunId = 0;

/** 参照元DBをTerminal Common Filesから読み取る場合true。 */
input bool databaseUseCommonFolder = true;

/** 研究対象Episode開始JSTの下限。 */
input datetime studyFromJstTime = D'2024.01.01 00:00:00';

/** 研究対象Episode開始JSTの対象外上限。 */
input datetime studyToJstTime = D'2026.01.01 00:00:00';

/** 出力CSVファイル名。空の場合は参照元DB名とRun IDから生成する。 */
input string outputCsvFileName = "";

/** CSVをTerminal Common Filesへ出力する場合true。 */
input bool outputUseCommonFolder = true;

/** 進捗を出力する候補Entry件数間隔。 */
input int progressInterval = 10000;

/** 条件別集計CSVのスキーマバージョン。 */
const string conditionCsvSchemaVersion =
    "H1_STUDY_CONDITION_BREAKDOWN_V1";

/** 累積条件ルールのバージョン。 */
const string conditionRuleVersion =
    "CUMULATIVE_ALIGNMENT_RULES_V1";

/** ルール固有Episode判定のバージョン。 */
const string conditionEpisodeRuleVersion =
    "RULE_SPECIFIC_SIDE_EPISODE_V1";

/** 必須時間足完全性ポリシー。 */
const string conditionRequiredTimeFramesPolicy =
    "W1_D1_H4_H1_COMPLETE";

/** 研究用エントリー価格モデル。 */
const string conditionEntryPriceModel = "NEXT_H1_OPEN_V1";

/** H1価格評価モデル。 */
const string conditionOutcomePriceModel = "H1_BID_OHLC_V1";

/** Spread控除モデル。 */
const string conditionSpreadModel = "ENTRY_SPREAD_ONCE_V1";

/** 将来成績計算ロジックバージョン。 */
const string conditionEvaluationVersion = "H1_FIXED_HORIZONS_V1";

/** 評価期間一覧のCanonical Text。 */
const string conditionHorizonsText = "6,12,24,48";

/** 損益を同値とみなす許容誤差pips。 */
const double conditionProfitZeroEpsilonPips = 0.00000001;

/** 累積条件ルール数。 */
const int conditionRuleCount = 6;

/** 連続確認本数の種類数。 */
const int conditionConfirmationCount = 3;

/** 評価期間の種類数。 */
const int conditionHorizonCount = 4;

/** 集計方向数。 */
const int conditionSideScopeCount = 3;

/** 条件別集計CSVの列数。 */
const int conditionCsvFieldCount = 55;

/** 条件別集計CSVの期待行数。 */
const int conditionExpectedRowCount = 216;

/** 参照R1で期待する全候補Entry数。 */
const long conditionReferenceCandidateCount = 604365;

/** 参照R1で期待する全Outcome数。 */
const long conditionReferenceOutcomeCount = 2417460;

/** 中央値計算用サンプル配列。 */
CArrayDouble *conditionMedianSamples[];

/** 1条件グループの集計値。 */
struct ZigZagElliotH1StudyConditionBreakdownRow {
    /** 条件の表示順。 */
    int conditionOrder;

    /** 条件名。 */
    string conditionRule;

    /** 条件式。 */
    string conditionExpression;

    /** ALL、BUYまたはSELL。 */
    string sideScope;

    /** 連続確認H1本数。 */
    int confirmationH1Count;

    /** 評価H1本数。 */
    int horizonH1Bars;

    /** 研究対象外を含む候補Entry数。 */
    long candidateEntryCount;

    /** 研究対象外Entry数。 */
    long ineligibleEntryCount;

    /** 研究対象Entry数。 */
    long eligibleEntryCount;

    /** 研究対象Entryに対応するOutcome数。 */
    long eligibleOutcomeCount;

    /** 計算成功Outcome数。 */
    long calculatedOutcomeCount;

    /** 計算不能Outcome数。 */
    long failedOutcomeCount;

    /** 欠損Outcome数。 */
    long missingOutcomeCount;

    /** 将来H1 Gapによる計算不能数。 */
    long futureH1GapCount;

    /** 将来H1 Gap以外の計算不能数。 */
    long otherFailureCount;

    /** 研究対象に対する計算成功率。 */
    double calculationCoveragePercent;

    /** 研究対象に対する将来H1 Gap率。 */
    double dataGapRatePercent;

    /** Spread控除後損益が正の件数。 */
    long winningCount;

    /** Spread控除後損益が負の件数。 */
    long losingCount;

    /** Spread控除後損益が0相当の件数。 */
    long breakevenCount;

    /** 計算成功Outcomeに対する勝率。 */
    double winRatePercent;

    /** 成績統計が利用可能な場合true。 */
    bool isStatisticsAvailable;

    /** Spread控除後損益合計。 */
    double netProfitSumPips;

    /** Spread控除前損益合計。 */
    double grossProfitSumPips;

    /** MFE合計。 */
    double mfeSumPips;

    /** MAE合計。 */
    double maeSumPips;

    /** Spread控除前ATR換算損益合計。 */
    double grossProfitSumAtr;

    /** Spread控除後ATR換算損益合計。 */
    double netProfitSumAtr;

    /** 最大利益到達H1本数合計。 */
    double maxProfitH1BarsSum;

    /** 研究対象Entry Spread合計。 */
    double entrySpreadSumPips;

    /** Spread控除前損益平均。 */
    double averageGrossProfitPips;

    /** Spread控除後損益平均。 */
    double averageNetProfitPips;

    /** Spread控除後損益中央値。 */
    double medianNetProfitPips;

    /** 正のSpread控除後損益合計。 */
    double winningNetProfitSumPips;

    /** 負のSpread控除後損益絶対値合計。 */
    double losingNetProfitAbsSumPips;

    /** Profit Factor。 */
    double profitFactor;

    /** Profit Factorの状態。 */
    string profitFactorStatus;

    /** MFE平均。 */
    double averageMfePips;

    /** MAE平均。 */
    double averageMaePips;

    /** Spread控除前ATR換算損益平均。 */
    double averageGrossProfitAtr;

    /** Spread控除後ATR換算損益平均。 */
    double averageNetProfitAtr;

    /** 最大利益到達H1本数平均。 */
    double averageMaxProfitH1Bars;

    /** 研究対象Entry Spread平均。 */
    double averageEntrySpreadPips;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.conditionOrder = 0;
        this.conditionRule = "";
        this.conditionExpression = "";
        this.sideScope = "";
        this.confirmationH1Count = 0;
        this.horizonH1Bars = 0;
        this.candidateEntryCount = 0;
        this.ineligibleEntryCount = 0;
        this.eligibleEntryCount = 0;
        this.eligibleOutcomeCount = 0;
        this.calculatedOutcomeCount = 0;
        this.failedOutcomeCount = 0;
        this.missingOutcomeCount = 0;
        this.futureH1GapCount = 0;
        this.otherFailureCount = 0;
        this.calculationCoveragePercent = 0.0;
        this.dataGapRatePercent = 0.0;
        this.winningCount = 0;
        this.losingCount = 0;
        this.breakevenCount = 0;
        this.winRatePercent = 0.0;
        this.isStatisticsAvailable = false;
        this.netProfitSumPips = 0.0;
        this.grossProfitSumPips = 0.0;
        this.mfeSumPips = 0.0;
        this.maeSumPips = 0.0;
        this.grossProfitSumAtr = 0.0;
        this.netProfitSumAtr = 0.0;
        this.maxProfitH1BarsSum = 0.0;
        this.entrySpreadSumPips = 0.0;
        this.averageGrossProfitPips = 0.0;
        this.averageNetProfitPips = 0.0;
        this.medianNetProfitPips = 0.0;
        this.winningNetProfitSumPips = 0.0;
        this.losingNetProfitAbsSumPips = 0.0;
        this.profitFactor = 0.0;
        this.profitFactorStatus = "NO_SAMPLE";
        this.averageMfePips = 0.0;
        this.averageMaePips = 0.0;
        this.averageGrossProfitAtr = 0.0;
        this.averageNetProfitAtr = 0.0;
        this.averageMaxProfitH1Bars = 0.0;
        this.averageEntrySpreadPips = 0.0;
    }
};

/**
 * 配列位置に対応する条件名を取得する。
 *
 * @param fromRuleIndex 条件配列位置。
 * @return 条件名。範囲外の場合は空文字。
 */
string getConditionRuleName(const int fromRuleIndex) {
    if (fromRuleIndex == 0) {
        return "H1_DIRECTION";
    }

    if (fromRuleIndex == 1) {
        return "H4_H1_DIRECTION";
    }

    if (fromRuleIndex == 2) {
        return "D1_H4_H1_DIRECTION";
    }

    if (fromRuleIndex == 3) {
        return "W1_D1_H4_H1_DIRECTION";
    }

    if (fromRuleIndex == 4) {
        return "W1_D1_H4_H1_DIRECTION_H1_EMA200";
    }

    if (fromRuleIndex == 5) {
        return "FULL_ALIGNMENT";
    }

    return "";
}

/**
 * 配列位置に対応する条件式を取得する。
 *
 * @param fromRuleIndex 条件配列位置。
 * @return 条件式。範囲外の場合は空文字。
 */
string getConditionExpression(const int fromRuleIndex) {
    if (fromRuleIndex == 0) {
        return "H1";
    }

    if (fromRuleIndex == 1) {
        return "H4=H1";
    }

    if (fromRuleIndex == 2) {
        return "D1=H4=H1";
    }

    if (fromRuleIndex == 3) {
        return "W1=D1=H4=H1";
    }

    if (fromRuleIndex == 4) {
        return "W1=D1=H4=H1=H1_EMA200";
    }

    if (fromRuleIndex == 5) {
        return "W1=D1=H4=H1=H4_EMA200=H1_EMA200";
    }

    return "";
}

/**
 * 配列位置に対応する集計方向を取得する。
 *
 * @param fromIndex 方向配列位置。
 * @return ALL、BUY、SELLのいずれか。範囲外の場合は空文字。
 */
string getConditionSideScope(const int fromIndex) {
    if (fromIndex == 0) {
        return "ALL";
    }

    if (fromIndex == 1) {
        return "BUY";
    }

    if (fromIndex == 2) {
        return "SELL";
    }

    return "";
}

/**
 * 配列位置に対応する評価H1本数を取得する。
 *
 * @param fromIndex 評価期間配列位置。
 * @return 6、12、24または48。範囲外の場合は0。
 */
int getConditionHorizonH1Bars(const int fromIndex) {
    if (fromIndex == 0) {
        return 6;
    }

    if (fromIndex == 1) {
        return 12;
    }

    if (fromIndex == 2) {
        return 24;
    }

    if (fromIndex == 3) {
        return 48;
    }

    return 0;
}

/**
 * 集計軸から行配列位置を取得する。
 *
 * @param fromRuleIndex 条件配列位置。
 * @param fromConfirmationIndex 確認本数配列位置。
 * @param fromHorizonIndex 評価期間配列位置。
 * @param fromSideScopeIndex 方向配列位置。
 * @return 集計行配列位置。
 */
int getConditionRowIndex(
    const int fromRuleIndex,
    const int fromConfirmationIndex,
    const int fromHorizonIndex,
    const int fromSideScopeIndex
) {
    int index = fromRuleIndex * conditionConfirmationCount;
    index += fromConfirmationIndex;
    index *= conditionHorizonCount;
    index += fromHorizonIndex;
    index *= conditionSideScopeCount;
    index += fromSideScopeIndex;

    return index;
}

/**
 * 参照R1の条件別候補Entry期待値を取得する。
 *
 * @param fromRuleIndex 条件配列位置。
 * @param fromConfirmationIndex 確認本数配列位置。
 * @return 期待件数。範囲外の場合は-1。
 */
long getConditionReferenceCandidateCount(
    const int fromRuleIndex,
    const int fromConfirmationIndex
) {
    if (fromRuleIndex == 0) {
        if (fromConfirmationIndex == 0) {
            return 108344;
        }
        if (fromConfirmationIndex == 1) {
            return 83513;
        }
        if (fromConfirmationIndex == 2) {
            return 56778;
        }
    }

    if (fromRuleIndex == 1) {
        if (fromConfirmationIndex == 0) {
            return 73521;
        }
        if (fromConfirmationIndex == 1) {
            return 51375;
        }
        if (fromConfirmationIndex == 2) {
            return 31948;
        }
    }

    if (fromRuleIndex == 2) {
        if (fromConfirmationIndex == 0) {
            return 41133;
        }
        if (fromConfirmationIndex == 1) {
            return 26886;
        }
        if (fromConfirmationIndex == 2) {
            return 15154;
        }
    }

    if (fromRuleIndex == 3) {
        if (fromConfirmationIndex == 0) {
            return 22543;
        }
        if (fromConfirmationIndex == 1) {
            return 14343;
        }
        if (fromConfirmationIndex == 2) {
            return 7734;
        }
    }

    if (fromRuleIndex == 4) {
        if (fromConfirmationIndex == 0) {
            return 20626;
        }
        if (fromConfirmationIndex == 1) {
            return 12922;
        }
        if (fromConfirmationIndex == 2) {
            return 6873;
        }
    }

    if (fromRuleIndex == 5) {
        if (fromConfirmationIndex == 0) {
            return 15658;
        }
        if (fromConfirmationIndex == 1) {
            return 9823;
        }
        if (fromConfirmationIndex == 2) {
            return 5191;
        }
    }

    return -1;
}

/**
 * 正の有限値か判定する。
 *
 * @param fromValue 判定値。
 * @return 正の有限値の場合true。
 */
bool isPositiveConditionNumber(const double fromValue) {
    return MathIsValidNumber(fromValue)
        && fromValue != EMPTY_VALUE
        && fromValue > 0.0;
}

/**
 * 0以上の有限値か判定する。
 *
 * @param fromValue 判定値。
 * @return 0以上の有限値の場合true。
 */
bool isNonNegativeConditionNumber(const double fromValue) {
    return MathIsValidNumber(fromValue)
        && fromValue != EMPTY_VALUE
        && fromValue >= 0.0;
}

/**
 * ファイル名がCSV拡張子を持つか確認する。
 *
 * @param fromFileName 確認対象。
 * @return 末尾が.csvの場合true。
 */
bool isConditionCsvFileName(const string fromFileName) {
    int fileNameLength = StringLen(fromFileName);

    if (fileNameLength < 5) {
        return false;
    }

    return StringCompare(
        StringSubstr(fromFileName, fileNameLength - 4),
        ".csv",
        false
    ) == 0;
}

/**
 * Script入力を検証する。
 *
 * @param fromLogger ロガー。
 * @return 実行可能な場合true。
 */
bool validateConditionInputs(Logger &fromLogger) {
    if (sourceDatabaseFileName == "") {
        fromLogger.error(__FUNCTION__, "sourceDatabaseFileName is empty.");

        return false;
    }

    if (sourceRunId < 0) {
        fromLogger.error(__FUNCTION__, "sourceRunId must not be negative.");

        return false;
    }

    if (studyFromJstTime <= 0
            || studyToJstTime <= studyFromJstTime) {
        fromLogger.error(__FUNCTION__, "Study JST range is invalid.");

        return false;
    }

    if (outputCsvFileName != ""
            && !isConditionCsvFileName(outputCsvFileName)) {
        fromLogger.error(
            __FUNCTION__,
            "outputCsvFileName must have a .csv extension."
        );

        return false;
    }

    if (progressInterval <= 0) {
        fromLogger.error(__FUNCTION__, "progressInterval must be positive.");

        return false;
    }

    return true;
}

/**
 * 入力値に従って参照元Runを選択する。
 *
 * @param fromQueryService 参照元DB Query Service。
 * @param fromRunInfo 選択したRun情報。
 * @param fromLogger ロガー。
 * @return Runを選択できた場合true。
 */
bool selectConditionSourceRun(
    ZigZagElliotH1StudyQueryService &fromQueryService,
    ZigZagElliotH1StudySourceRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    fromRunInfo.reset();

    if (sourceRunId > 0) {
        bool isFound = false;

        if (!fromQueryService.findRun(sourceRunId, fromRunInfo, isFound)) {
            fromLogger.error(__FUNCTION__, "Source Run read failed.");

            return false;
        }

        if (!isFound) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Source Run was not found. runId=%I64d",
                    sourceRunId
                )
            );

            return false;
        }

        return true;
    }

    ZigZagElliotH1StudySourceRunInfo runInfos[];

    if (!fromQueryService.findRuns(runInfos)) {
        fromLogger.error(__FUNCTION__, "Source Run list read failed.");

        return false;
    }

    int runCount = ArraySize(runInfos);

    if (runCount != 1) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "sourceRunId=0 requires exactly one Run. count=%d",
                runCount
            )
        );

        return false;
    }

    fromRunInfo = runInfos[0];

    return true;
}

/**
 * 集計に必要な参照元Run項目を検証する。
 *
 * @param fromRunInfo 参照元Run情報。
 * @param fromLogger ロガー。
 * @return 必須項目が利用可能な場合true。
 */
bool validateConditionSourceRun(
    ZigZagElliotH1StudySourceRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    if (fromRunInfo.runId <= 0
            || fromRunInfo.runUid == ""
            || fromRunInfo.sourceMode == ""
            || fromRunInfo.sourceServer == ""
            || fromRunInfo.analysisVersion == "") {
        fromLogger.error(
            __FUNCTION__,
            "Source Run metadata required by condition breakdown is incomplete."
        );

        return false;
    }

    if (fromRunInfo.status != "LEGACY"
            && fromRunInfo.status != "COMPLETED") {
        fromLogger.error(
            __FUNCTION__,
            "Source Run status is not eligible. status=" + fromRunInfo.status
        );

        return false;
    }

    return true;
}

/**
 * 全required時間足が取得済みか判定する。
 *
 * @param fromRow Observation行。
 * @return W1、D1、H4、H1がすべて利用可能な場合true。
 */
bool isConditionRequiredTimeFramesComplete(
    const ZigZagElliotH1StudyObservationRow &fromRow
) {
    return fromRow.isRequiredTimeFramesComplete == 1
        && fromRow.isW1Available == 1
        && fromRow.isD1Available == 1
        && fromRow.isH4Available == 1
        && fromRow.isH1Available == 1;
}

/**
 * EMA200のBUY・SELLフラグが指定方向へ厳密一致するか判定する。
 *
 * (0,0)は方向なしとしてSELLへ分類しない。
 *
 * @param fromSide BUYまたはSELL。
 * @param fromIsBuy EMA200 BUYフラグ。
 * @param fromIsSell EMA200 SELLフラグ。
 * @return 指定方向へone-hot一致する場合true。
 */
bool isConditionEmaAligned(
    const string fromSide,
    const int fromIsBuy,
    const int fromIsSell
) {
    if (fromSide == "BUY") {
        return fromIsBuy == 1 && fromIsSell == 0;
    }

    if (fromSide == "SELL") {
        return fromIsBuy == 0 && fromIsSell == 1;
    }

    return false;
}

/**
 * 指定した累積条件に一致する方向を取得する。
 *
 * @param fromRow Observation行。
 * @param fromRuleIndex 条件配列位置。
 * @return BUY、SELLまたは不一致時の空文字。
 */
string classifyConditionSide(
    const ZigZagElliotH1StudyObservationRow &fromRow,
    const int fromRuleIndex
) {
    if (!isConditionRequiredTimeFramesComplete(fromRow)) {
        return "";
    }

    if (fromRuleIndex == 5) {
        return ZigZagElliotH1StudyOutcomeCalculator::
            classifyFullAlignmentSide(fromRow);
    }

    string side = "";

    if (fromRow.h1IsBuy == 1) {
        side = "BUY";
    } else if (fromRow.h1IsBuy == 0) {
        side = "SELL";
    } else {
        return "";
    }

    int sideValue = 0;

    if (side == "BUY") {
        sideValue = 1;
    }

    if (fromRuleIndex >= 1 && fromRow.h4IsBuy != sideValue) {
        return "";
    }

    if (fromRuleIndex >= 2 && fromRow.d1IsBuy != sideValue) {
        return "";
    }

    if (fromRuleIndex >= 3 && fromRow.w1IsBuy != sideValue) {
        return "";
    }

    if (fromRuleIndex >= 4
            && !isConditionEmaAligned(
                side,
                fromRow.h1IsEma200Buy,
                fromRow.h1IsEma200Sell
            )) {
        return "";
    }

    return side;
}

/**
 * Episode直前のObservationにデータGapがあるか判定する。
 *
 * @param fromRows 同一Streamの時系列昇順行。
 * @param fromEpisodeStartIndex Episode開始位置。
 * @return 非連続またはrequired時間足欠損の場合true。
 */
bool hasConditionDataGapBefore(
    const ZigZagElliotH1StudyObservationRow &fromRows[],
    const int fromEpisodeStartIndex
) {
    if (fromEpisodeStartIndex <= 0) {
        return false;
    }

    ZigZagElliotH1StudyObservationRow previousRow =
        fromRows[fromEpisodeStartIndex - 1];
    ZigZagElliotH1StudyObservationRow startRow =
        fromRows[fromEpisodeStartIndex];

    return !ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
            previousRow.anchorBarTime,
            startRow.anchorBarTime
        ) || previousRow.isRequiredTimeFramesComplete != 1;
}

/**
 * 研究用Entry行が計算可能な観測値を持つか判定する。
 *
 * @param fromRow Entry行。
 * @return Entry価格、Spread、pip size、ATRが利用可能な場合true。
 */
bool isConditionEntryRowReady(
    const ZigZagElliotH1StudyObservationRow &fromRow
) {
    return fromRow.isH1Available == 1
        && isPositiveConditionNumber(fromRow.currentOpen)
        && fromRow.isSpreadAvailable == 1
        && isNonNegativeConditionNumber(fromRow.spreadPips)
        && isPositiveConditionNumber(fromRow.pipSize)
        && fromRow.pipSizeSource != ""
        && fromRow.isAtr14Available == 1
        && isPositiveConditionNumber(fromRow.atr14Pips);
}

/**
 * 確認位置から次H1始値Entryの研究対象可否を判定する。
 *
 * @param fromRows 同一Streamの時系列昇順行。
 * @param fromEpisodeStartIndex Episode開始位置。
 * @param fromConfirmationIndex 確認Observation位置。
 * @param fromEntryIndex Entry行位置。利用不能時は-1。
 * @return Step 5と同じ研究対象条件を満たす場合true。
 */
bool findConditionEligibleEntryIndex(
    const ZigZagElliotH1StudyObservationRow &fromRows[],
    const int fromEpisodeStartIndex,
    const int fromConfirmationIndex,
    int &fromEntryIndex
) {
    fromEntryIndex = -1;

    if (fromEpisodeStartIndex == 0
            || hasConditionDataGapBefore(
                fromRows,
                fromEpisodeStartIndex
            )) {
        return false;
    }

    int nextIndex = fromConfirmationIndex + 1;
    int rowCount = ArraySize(fromRows);

    if (nextIndex >= rowCount) {
        return false;
    }

    ZigZagElliotH1StudyObservationRow confirmationRow =
        fromRows[fromConfirmationIndex];
    ZigZagElliotH1StudyObservationRow entryRow = fromRows[nextIndex];

    if (!ZigZagElliotH1StudyOutcomeCalculator::isConsecutiveMarketH1(
            confirmationRow.anchorBarTime,
            entryRow.anchorBarTime
        ) || !isConditionEntryRowReady(entryRow)) {
        return false;
    }

    fromEntryIndex = nextIndex;

    return true;
}

/**
 * 全集計行と中央値サンプル領域を初期化する。
 *
 * @param fromRows 集計行配列。
 * @param fromLogger ロガー。
 * @return 初期化できた場合true。
 */
bool initializeConditionRows(
    ZigZagElliotH1StudyConditionBreakdownRow &fromRows[],
    Logger &fromLogger
) {
    if (ArrayResize(fromRows, conditionExpectedRowCount)
            != conditionExpectedRowCount
            || ArrayResize(
                conditionMedianSamples,
                conditionExpectedRowCount
            ) != conditionExpectedRowCount) {
        fromLogger.error(__FUNCTION__, "Aggregation array allocation failed.");

        return false;
    }

    for (int i = 0; i < conditionExpectedRowCount; i++) {
        conditionMedianSamples[i] = NULL;
    }

    for (int i = 0; i < conditionRuleCount; i++) {
        for (int j = 0; j < conditionConfirmationCount; j++) {
            for (int k = 0; k < conditionHorizonCount; k++) {
                for (int sideIndex = 0;
                        sideIndex < conditionSideScopeCount;
                        sideIndex++) {
                    int rowIndex = getConditionRowIndex(
                        i,
                        j,
                        k,
                        sideIndex
                    );
                    fromRows[rowIndex].reset();
                    fromRows[rowIndex].conditionOrder = i + 1;
                    fromRows[rowIndex].conditionRule =
                        getConditionRuleName(i);
                    fromRows[rowIndex].conditionExpression =
                        getConditionExpression(i);
                    fromRows[rowIndex].sideScope =
                        getConditionSideScope(sideIndex);
                    fromRows[rowIndex].confirmationH1Count = j + 1;
                    fromRows[rowIndex].horizonH1Bars =
                        getConditionHorizonH1Bars(k);
                    conditionMedianSamples[rowIndex] = new CArrayDouble;

                    if (CheckPointer(conditionMedianSamples[rowIndex])
                            != POINTER_DYNAMIC
                            || !conditionMedianSamples[rowIndex].Step(1024)) {
                        fromLogger.error(
                            __FUNCTION__,
                            StringFormat(
                                "Median sample allocation failed. row=%d",
                                rowIndex
                            )
                        );

                        return false;
                    }
                }
            }
        }
    }

    return true;
}

/**
 * 中央値サンプル領域を解放する。
 */
void releaseConditionMedianSamples() {
    int sampleCount = ArraySize(conditionMedianSamples);

    for (int i = 0; i < sampleCount; i++) {
        if (CheckPointer(conditionMedianSamples[i]) == POINTER_DYNAMIC) {
            delete conditionMedianSamples[i];
        }

        conditionMedianSamples[i] = NULL;
    }

    ArrayResize(conditionMedianSamples, 0);
}

/**
 * 1方向範囲の候補とOutcomeを集計する。
 *
 * @param fromRowIndex 集計行配列位置。
 * @param fromIsEligible 研究対象の場合true。
 * @param fromEntrySpreadPips Entry Spread。
 * @param fromResult Outcome計算結果。
 * @param fromRows 集計行配列。
 * @param fromLogger ロガー。
 * @return 集計できた場合true。
 */
bool addConditionOutcome(
    const int fromRowIndex,
    const bool fromIsEligible,
    const double fromEntrySpreadPips,
    ZigZagElliotH1StudyOutcomeCalculationResult &fromResult,
    ZigZagElliotH1StudyConditionBreakdownRow &fromRows[],
    Logger &fromLogger
) {
    ZigZagElliotH1StudyConditionBreakdownRow row = fromRows[fromRowIndex];
    row.candidateEntryCount++;

    if (!fromIsEligible) {
        row.ineligibleEntryCount++;
        fromRows[fromRowIndex] = row;

        return true;
    }

    row.eligibleEntryCount++;
    row.eligibleOutcomeCount++;
    row.entrySpreadSumPips += fromEntrySpreadPips;

    if (fromResult.isCalculated != 1) {
        row.failedOutcomeCount++;

        if (fromResult.dataStatus == "FUTURE_H1_GAP") {
            row.futureH1GapCount++;
        } else {
            row.otherFailureCount++;
        }

        fromRows[fromRowIndex] = row;

        return true;
    }

    row.calculatedOutcomeCount++;
    row.netProfitSumPips += fromResult.spreadAdjustedProfitPips;
    row.grossProfitSumPips += fromResult.grossProfitPips;
    row.mfeSumPips += fromResult.mfePips;
    row.maeSumPips += fromResult.maePips;
    row.grossProfitSumAtr += fromResult.grossProfitAtr;
    row.netProfitSumAtr += fromResult.spreadAdjustedProfitAtr;
    row.maxProfitH1BarsSum += (double)fromResult.maxProfitH1Bars;

    if (fromResult.spreadAdjustedProfitPips
            > conditionProfitZeroEpsilonPips) {
        row.winningCount++;
        row.winningNetProfitSumPips +=
            fromResult.spreadAdjustedProfitPips;
    } else if (fromResult.spreadAdjustedProfitPips
            < -conditionProfitZeroEpsilonPips) {
        row.losingCount++;
        row.losingNetProfitAbsSumPips -=
            fromResult.spreadAdjustedProfitPips;
    } else {
        row.breakevenCount++;
    }

    if (CheckPointer(conditionMedianSamples[fromRowIndex])
            != POINTER_DYNAMIC
            || !conditionMedianSamples[fromRowIndex].Add(
                fromResult.spreadAdjustedProfitPips
            )) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Median sample append failed. row=%d count=%I64d",
                fromRowIndex,
                row.calculatedOutcomeCount
            )
        );

        return false;
    }

    fromRows[fromRowIndex] = row;

    return true;
}

/**
 * 1候補を4期間およびALL・売買方向へ集計する。
 *
 * @param fromRows 同一Streamの時系列昇順行。
 * @param fromRuleIndex 条件配列位置。
 * @param fromConfirmationIndex 確認本数配列位置。
 * @param fromEpisodeStartIndex Episode開始位置。
 * @param fromConfirmationRowIndex 確認Observation位置。
 * @param fromSide BUYまたはSELL。
 * @param fromSummaryRows 集計行配列。
 * @param fromLogger ロガー。
 * @return 集計できた場合true。
 */
bool aggregateConditionCandidate(
    const ZigZagElliotH1StudyObservationRow &fromRows[],
    const int fromRuleIndex,
    const int fromConfirmationIndex,
    const int fromEpisodeStartIndex,
    const int fromConfirmationRowIndex,
    const string fromSide,
    ZigZagElliotH1StudyConditionBreakdownRow &fromSummaryRows[],
    Logger &fromLogger
) {
    int entryIndex = -1;
    bool isEligible = findConditionEligibleEntryIndex(
        fromRows,
        fromEpisodeStartIndex,
        fromConfirmationRowIndex,
        entryIndex
    );
    double entrySpreadPips = 0.0;

    if (isEligible) {
        entrySpreadPips = fromRows[entryIndex].spreadPips;
    }

    int sideScopeIndex = 2;

    if (fromSide == "BUY") {
        sideScopeIndex = 1;
    }

    for (int i = 0; i < conditionHorizonCount; i++) {
        ZigZagElliotH1StudyOutcomeCalculationResult result;
        result.reset();

        if (isEligible) {
            ZigZagElliotH1StudyOutcomeCalculator::calculate(
                fromRows,
                entryIndex,
                fromSide,
                getConditionHorizonH1Bars(i),
                result
            );
        }

        int allRowIndex = getConditionRowIndex(
            fromRuleIndex,
            fromConfirmationIndex,
            i,
            0
        );
        int sideRowIndex = getConditionRowIndex(
            fromRuleIndex,
            fromConfirmationIndex,
            i,
            sideScopeIndex
        );

        if (!addConditionOutcome(
                allRowIndex,
                isEligible,
                entrySpreadPips,
                result,
                fromSummaryRows,
                fromLogger
            ) || !addConditionOutcome(
                sideRowIndex,
                isEligible,
                entrySpreadPips,
                result,
                fromSummaryRows,
                fromLogger
            )) {
            return false;
        }
    }

    return true;
}

/**
 * 1Streamを6条件のルール固有Episodeへ分解して集計する。
 *
 * @param fromStream 取得対象Stream。
 * @param fromQueryService 参照元DB Query Service。
 * @param fromSummaryRows 集計行配列。
 * @param fromCandidateCount 処理済み候補Entry数。
 * @param fromLogger ロガー。
 * @return Streamを集計できた場合true。
 */
bool processConditionStream(
    ZigZagElliotH1StudyStreamKey &fromStream,
    ZigZagElliotH1StudyQueryService &fromQueryService,
    ZigZagElliotH1StudyConditionBreakdownRow &fromSummaryRows[],
    long &fromCandidateCount,
    Logger &fromLogger
) {
    ZigZagElliotH1StudyObservationRow rows[];

    if (!fromQueryService.findObservations(fromStream, rows)) {
        fromLogger.error(
            __FUNCTION__,
            "Observation read failed. symbol=" + fromStream.symbolName
        );

        return false;
    }

    int rowCount = ArraySize(rows);

    for (int i = 0; i < conditionRuleCount; i++) {
        int rowIndex = 0;

        while (rowIndex < rowCount) {
            if (IsStopped()) {
                fromLogger.error(__FUNCTION__, "Condition export was stopped.");

                return false;
            }

            string side = classifyConditionSide(rows[rowIndex], i);

            if (side == "") {
                rowIndex++;
                continue;
            }

            int episodeStartIndex = rowIndex;
            int episodeEndIndex = rowIndex;

            while (episodeEndIndex + 1 < rowCount) {
                int nextIndex = episodeEndIndex + 1;
                string nextSide = classifyConditionSide(rows[nextIndex], i);

                if (nextSide != side
                        || !ZigZagElliotH1StudyOutcomeCalculator::
                            isConsecutiveMarketH1(
                                rows[episodeEndIndex].anchorBarTime,
                                rows[nextIndex].anchorBarTime
                            )) {
                    break;
                }

                episodeEndIndex = nextIndex;
            }

            datetime episodeStartJstTime =
                rows[episodeStartIndex].anchorJstTime;

            if (episodeStartJstTime >= studyFromJstTime
                    && episodeStartJstTime < studyToJstTime) {
                int confirmationLimit = episodeEndIndex
                    - episodeStartIndex + 1;

                if (confirmationLimit > conditionConfirmationCount) {
                    confirmationLimit = conditionConfirmationCount;
                }

                for (int j = 0; j < confirmationLimit; j++) {
                    int confirmationRowIndex = episodeStartIndex + j;

                    if (!aggregateConditionCandidate(
                            rows,
                            i,
                            j,
                            episodeStartIndex,
                            confirmationRowIndex,
                            side,
                            fromSummaryRows,
                            fromLogger
                        )) {
                        return false;
                    }

                    fromCandidateCount++;

                    if (fromCandidateCount % (long)progressInterval == 0) {
                        fromLogger.info(
                            __FUNCTION__,
                            StringFormat(
                                "Condition aggregation progress. candidates=%I64d symbol=%s rule=%s",
                                fromCandidateCount,
                                fromStream.symbolName,
                                getConditionRuleName(i)
                            )
                        );
                    }
                }
            }

            rowIndex = episodeEndIndex + 1;
        }
    }

    return true;
}

/**
 * 中央値と平均値を確定する。
 *
 * @param fromRows 集計行配列。
 * @param fromLogger ロガー。
 * @return 全集計値を確定できた場合true。
 */
bool finalizeConditionRows(
    ZigZagElliotH1StudyConditionBreakdownRow &fromRows[],
    Logger &fromLogger
) {
    int rowCount = ArraySize(fromRows);

    for (int i = 0; i < rowCount; i++) {
        ZigZagElliotH1StudyConditionBreakdownRow row = fromRows[i];

        if (row.eligibleEntryCount > 0) {
            row.calculationCoveragePercent = 100.0
                * (double)row.calculatedOutcomeCount
                / (double)row.eligibleEntryCount;
            row.dataGapRatePercent = 100.0
                * (double)row.futureH1GapCount
                / (double)row.eligibleEntryCount;
            row.averageEntrySpreadPips = row.entrySpreadSumPips
                / (double)row.eligibleEntryCount;
        }

        row.isStatisticsAvailable = row.calculatedOutcomeCount > 0;

        if (row.isStatisticsAvailable) {
            double calculatedCount = (double)row.calculatedOutcomeCount;
            row.winRatePercent = 100.0
                * (double)row.winningCount / calculatedCount;
            row.averageGrossProfitPips = row.grossProfitSumPips
                / calculatedCount;
            row.averageNetProfitPips = row.netProfitSumPips
                / calculatedCount;
            row.averageMfePips = row.mfeSumPips / calculatedCount;
            row.averageMaePips = row.maeSumPips / calculatedCount;
            row.averageGrossProfitAtr = row.grossProfitSumAtr
                / calculatedCount;
            row.averageNetProfitAtr = row.netProfitSumAtr
                / calculatedCount;
            row.averageMaxProfitH1Bars = row.maxProfitH1BarsSum
                / calculatedCount;

            if (CheckPointer(conditionMedianSamples[i]) != POINTER_DYNAMIC
                    || conditionMedianSamples[i].Total()
                        != (int)row.calculatedOutcomeCount) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "Median sample count mismatch. row=%d expected=%I64d actual=%d",
                        i,
                        row.calculatedOutcomeCount,
                        conditionMedianSamples[i].Total()
                    )
                );

                return false;
            }

            conditionMedianSamples[i].Sort();
            int sampleCount = conditionMedianSamples[i].Total();
            int medianIndex = sampleCount / 2;

            if (sampleCount % 2 == 0) {
                row.medianNetProfitPips = 0.5
                    * (conditionMedianSamples[i].At(medianIndex - 1)
                        + conditionMedianSamples[i].At(medianIndex));
            } else {
                row.medianNetProfitPips =
                    conditionMedianSamples[i].At(medianIndex);
            }
        }

        if (row.calculatedOutcomeCount <= 0) {
            row.profitFactorStatus = "NO_SAMPLE";
        } else if (row.losingNetProfitAbsSumPips > 0.0) {
            row.profitFactorStatus = "AVAILABLE";
            row.profitFactor = row.winningNetProfitSumPips
                / row.losingNetProfitAbsSumPips;
        } else if (row.winningNetProfitSumPips > 0.0) {
            row.profitFactorStatus = "INFINITE_NO_LOSS";
        } else {
            row.profitFactorStatus = "NO_VARIATION";
        }

        fromRows[i] = row;
    }

    return true;
}

/**
 * 現在の入力が既知の2024-2025 R1条件か判定する。
 *
 * @param fromRunId Source Run ID。
 * @return 参照DB名、Run ID、研究期間が一致する場合true。
 */
bool isConditionReferenceConfiguration(const long fromRunId) {
    return StringCompare(
            sourceDatabaseFileName,
            "mstng-zigzag-elliot-h1-study-2024-2025-r1.sqlite",
            false
        ) == 0
        && fromRunId == 1
        && studyFromJstTime == D'2024.01.01 00:00:00'
        && studyToJstTime == D'2026.01.01 00:00:00';
}

/**
 * 集計件数と方向分解の整合性を検証する。
 *
 * @param fromRows 集計行配列。
 * @param fromRunId Source Run ID。
 * @param fromProcessedCandidateCount 処理した候補Entry総数。
 * @param fromLogger ロガー。
 * @return 全検証に成功した場合true。
 */
bool validateConditionRows(
    ZigZagElliotH1StudyConditionBreakdownRow &fromRows[],
    const long fromRunId,
    const long fromProcessedCandidateCount,
    Logger &fromLogger
) {
    if (ArraySize(fromRows) != conditionExpectedRowCount) {
        fromLogger.error(__FUNCTION__, "Condition row count mismatch.");

        return false;
    }

    long firstHorizonCandidateCount = 0;

    for (int i = 0; i < conditionRuleCount; i++) {
        for (int j = 0; j < conditionConfirmationCount; j++) {
            int baselineIndex = getConditionRowIndex(i, j, 0, 0);
            long candidateCount = fromRows[baselineIndex].candidateEntryCount;
            firstHorizonCandidateCount += candidateCount;

            if (isConditionReferenceConfiguration(fromRunId)) {
                long expectedCount = getConditionReferenceCandidateCount(i, j);

                if (candidateCount != expectedCount) {
                    fromLogger.error(
                        __FUNCTION__,
                        StringFormat(
                            "Reference candidate count mismatch. rule=%s confirmation=%d expected=%I64d actual=%I64d",
                            getConditionRuleName(i),
                            j + 1,
                            expectedCount,
                            candidateCount
                        )
                    );

                    return false;
                }
            }

            for (int k = 0; k < conditionHorizonCount; k++) {
                int allIndex = getConditionRowIndex(i, j, k, 0);
                int buyIndex = getConditionRowIndex(i, j, k, 1);
                int sellIndex = getConditionRowIndex(i, j, k, 2);
                ZigZagElliotH1StudyConditionBreakdownRow allRow =
                    fromRows[allIndex];
                ZigZagElliotH1StudyConditionBreakdownRow buyRow =
                    fromRows[buyIndex];
                ZigZagElliotH1StudyConditionBreakdownRow sellRow =
                    fromRows[sellIndex];
                bool isConsistent = allRow.candidateEntryCount
                        == candidateCount
                    && allRow.candidateEntryCount
                        == allRow.ineligibleEntryCount
                            + allRow.eligibleEntryCount
                    && allRow.eligibleOutcomeCount
                        == allRow.calculatedOutcomeCount
                            + allRow.failedOutcomeCount
                    && allRow.missingOutcomeCount == 0
                    && allRow.failedOutcomeCount
                        == allRow.futureH1GapCount
                            + allRow.otherFailureCount
                    && allRow.calculatedOutcomeCount
                        == allRow.winningCount
                            + allRow.losingCount
                            + allRow.breakevenCount
                    && allRow.candidateEntryCount
                        == buyRow.candidateEntryCount
                            + sellRow.candidateEntryCount
                    && allRow.ineligibleEntryCount
                        == buyRow.ineligibleEntryCount
                            + sellRow.ineligibleEntryCount
                    && allRow.eligibleEntryCount
                        == buyRow.eligibleEntryCount
                            + sellRow.eligibleEntryCount
                    && allRow.calculatedOutcomeCount
                        == buyRow.calculatedOutcomeCount
                            + sellRow.calculatedOutcomeCount
                    && allRow.failedOutcomeCount
                        == buyRow.failedOutcomeCount
                            + sellRow.failedOutcomeCount
                    && allRow.winningCount
                        == buyRow.winningCount + sellRow.winningCount
                    && allRow.losingCount
                        == buyRow.losingCount + sellRow.losingCount
                    && allRow.breakevenCount
                        == buyRow.breakevenCount
                            + sellRow.breakevenCount;

                if (!isConsistent) {
                    fromLogger.error(
                        __FUNCTION__,
                        StringFormat(
                            "Condition group count mismatch. rule=%s confirmation=%d horizon=%d",
                            getConditionRuleName(i),
                            j + 1,
                            getConditionHorizonH1Bars(k)
                        )
                    );

                    return false;
                }
            }
        }
    }

    if (fromProcessedCandidateCount != firstHorizonCandidateCount) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Processed candidate count mismatch. processed=%I64d grouped=%I64d",
                fromProcessedCandidateCount,
                firstHorizonCandidateCount
            )
        );

        return false;
    }

    if (isConditionReferenceConfiguration(fromRunId)
            && (firstHorizonCandidateCount
                    != conditionReferenceCandidateCount
                || firstHorizonCandidateCount * conditionHorizonCount
                    != conditionReferenceOutcomeCount)) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Reference total count mismatch. candidates=%I64d outcomes=%I64d",
                firstHorizonCandidateCount,
                firstHorizonCandidateCount * conditionHorizonCount
            )
        );

        return false;
    }

    return true;
}

/**
 * DBファイル名から自動CSV名用の識別子を作る。
 *
 * @return ファイル名として利用可能な識別子。
 */
string getConditionDatabaseToken() {
    string token = sourceDatabaseFileName;
    StringReplace(token, "mstng-zigzag-elliot-h1-study-", "");
    StringReplace(token, ".sqlite", "");
    StringReplace(token, ".db", "");
    StringReplace(token, "\\", "-");
    StringReplace(token, "/", "-");
    StringReplace(token, ":", "-");
    StringReplace(token, "*", "-");
    StringReplace(token, "?", "-");
    StringReplace(token, "\"", "-");
    StringReplace(token, "<", "-");
    StringReplace(token, ">", "-");
    StringReplace(token, "|", "-");
    StringReplace(token, ".", "-");

    if (StringLen(token) > 80) {
        token = StringSubstr(token, 0, 80);
    }

    if (token == "") {
        token = "source";
    }

    return token;
}

/**
 * 実際のCSV出力ファイル名を取得する。
 *
 * @param fromRunId Source Run ID。
 * @return 入力値または自動生成名。
 */
string getConditionOutputFileName(const long fromRunId) {
    if (outputCsvFileName != "") {
        return outputCsvFileName;
    }

    return StringFormat(
        "mstng-zigzag-elliot-h1-study-condition-breakdown-%s-run-%I64d.csv",
        getConditionDatabaseToken(),
        fromRunId
    );
}

/**
 * CSVヘッダーを構築する。
 *
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setConditionHeaderValues(
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, conditionCsvFieldCount);
    int index = 0;
    fromValues[index++] = "csv_schema_version";
    fromValues[index++] = "source_database_file_name";
    fromValues[index++] = "source_run_id";
    fromValues[index++] = "source_run_uid";
    fromValues[index++] = "source_mode";
    fromValues[index++] = "source_server";
    fromValues[index++] = "source_analysis_version";
    fromValues[index++] = "source_analysis_input_hash";
    fromValues[index++] = "study_from_jst_time";
    fromValues[index++] = "study_to_jst_time";
    fromValues[index++] = "condition_rule_version";
    fromValues[index++] = "episode_rule_version";
    fromValues[index++] = "required_time_frames_policy";
    fromValues[index++] = "entry_price_model";
    fromValues[index++] = "outcome_price_model";
    fromValues[index++] = "spread_model";
    fromValues[index++] = "evaluation_version";
    fromValues[index++] = "horizons_text";
    fromValues[index++] = "profit_zero_epsilon_pips";
    fromValues[index++] = "condition_order";
    fromValues[index++] = "condition_rule";
    fromValues[index++] = "condition_expression";
    fromValues[index++] = "side_scope";
    fromValues[index++] = "confirmation_h1_count";
    fromValues[index++] = "horizon_h1_bars";
    fromValues[index++] = "candidate_entry_count";
    fromValues[index++] = "ineligible_entry_count";
    fromValues[index++] = "eligible_entry_count";
    fromValues[index++] = "eligible_outcome_count";
    fromValues[index++] = "calculated_outcome_count";
    fromValues[index++] = "failed_outcome_count";
    fromValues[index++] = "missing_outcome_count";
    fromValues[index++] = "future_h1_gap_count";
    fromValues[index++] = "other_failure_count";
    fromValues[index++] = "calculation_coverage_percent";
    fromValues[index++] = "data_gap_rate_percent";
    fromValues[index++] = "winning_count";
    fromValues[index++] = "losing_count";
    fromValues[index++] = "breakeven_count";
    fromValues[index++] = "win_rate_percent";
    fromValues[index++] = "is_statistics_available";
    fromValues[index++] = "net_profit_sum_pips";
    fromValues[index++] = "average_gross_profit_pips";
    fromValues[index++] = "average_net_profit_pips";
    fromValues[index++] = "median_net_profit_pips";
    fromValues[index++] = "winning_net_profit_sum_pips";
    fromValues[index++] = "losing_net_profit_abs_sum_pips";
    fromValues[index++] = "profit_factor";
    fromValues[index++] = "profit_factor_status";
    fromValues[index++] = "average_mfe_pips";
    fromValues[index++] = "average_mae_pips";
    fromValues[index++] = "average_gross_profit_atr";
    fromValues[index++] = "average_net_profit_atr";
    fromValues[index++] = "average_max_profit_h1_bars";
    fromValues[index++] = "average_entry_spread_pips";

    if (index == conditionCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "CSV header field count mismatch. expected=%d actual=%d",
            conditionCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 利用可能なdouble値をCSV文字列へ変換する。
 *
 * @param fromValue 数値。
 * @param fromIsAvailable 利用可能な場合true。
 * @param fromDigits 小数桁数。
 * @return 利用不能時は空文字、それ以外は数値文字列。
 */
string formatConditionOptionalDouble(
    const double fromValue,
    const bool fromIsAvailable,
    const int fromDigits
) {
    if (!fromIsAvailable) {
        return "";
    }

    return DoubleToString(fromValue, fromDigits);
}

/**
 * CSVデータ行を構築する。
 *
 * @param fromRunInfo Source Run情報。
 * @param fromRow 集計行。
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setConditionRowValues(
    ZigZagElliotH1StudySourceRunInfo &fromRunInfo,
    ZigZagElliotH1StudyConditionBreakdownRow &fromRow,
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, conditionCsvFieldCount);
    int index = 0;
    bool isRateAvailable = fromRow.eligibleEntryCount > 0;
    bool isProfitFactorAvailable =
        fromRow.profitFactorStatus == "AVAILABLE";
    fromValues[index++] = conditionCsvSchemaVersion;
    fromValues[index++] = sourceDatabaseFileName;
    fromValues[index++] = StringFormat("%I64d", fromRunInfo.runId);
    fromValues[index++] = fromRunInfo.runUid;
    fromValues[index++] = fromRunInfo.sourceMode;
    fromValues[index++] = fromRunInfo.sourceServer;
    fromValues[index++] = fromRunInfo.analysisVersion;
    fromValues[index++] = fromRunInfo.analysisInputHash;
    fromValues[index++] = TimeToString(
        studyFromJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[index++] = TimeToString(
        studyToJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[index++] = conditionRuleVersion;
    fromValues[index++] = conditionEpisodeRuleVersion;
    fromValues[index++] = conditionRequiredTimeFramesPolicy;
    fromValues[index++] = conditionEntryPriceModel;
    fromValues[index++] = conditionOutcomePriceModel;
    fromValues[index++] = conditionSpreadModel;
    fromValues[index++] = conditionEvaluationVersion;
    fromValues[index++] = conditionHorizonsText;
    fromValues[index++] = DoubleToString(
        conditionProfitZeroEpsilonPips,
        10
    );
    fromValues[index++] = IntegerToString(fromRow.conditionOrder);
    fromValues[index++] = fromRow.conditionRule;
    fromValues[index++] = fromRow.conditionExpression;
    fromValues[index++] = fromRow.sideScope;
    fromValues[index++] = IntegerToString(fromRow.confirmationH1Count);
    fromValues[index++] = IntegerToString(fromRow.horizonH1Bars);
    fromValues[index++] = StringFormat("%I64d", fromRow.candidateEntryCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.ineligibleEntryCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.eligibleEntryCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.eligibleOutcomeCount);
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.calculatedOutcomeCount
    );
    fromValues[index++] = StringFormat("%I64d", fromRow.failedOutcomeCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.missingOutcomeCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.futureH1GapCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.otherFailureCount);
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.calculationCoveragePercent,
        isRateAvailable,
        6
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.dataGapRatePercent,
        isRateAvailable,
        6
    );
    fromValues[index++] = StringFormat("%I64d", fromRow.winningCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.losingCount);
    fromValues[index++] = StringFormat("%I64d", fromRow.breakevenCount);
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.winRatePercent,
        fromRow.isStatisticsAvailable,
        6
    );
    fromValues[index++] = IntegerToString(
        (int)fromRow.isStatisticsAvailable
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.netProfitSumPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageGrossProfitPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageNetProfitPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.medianNetProfitPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.winningNetProfitSumPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.losingNetProfitAbsSumPips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.profitFactor,
        isProfitFactorAvailable,
        8
    );
    fromValues[index++] = fromRow.profitFactorStatus;
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageMfePips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageMaePips,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageGrossProfitAtr,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageNetProfitAtr,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageMaxProfitH1Bars,
        fromRow.isStatisticsAvailable,
        8
    );
    fromValues[index++] = formatConditionOptionalDouble(
        fromRow.averageEntrySpreadPips,
        isRateAvailable,
        8
    );

    if (index == conditionCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "CSV data field count mismatch. expected=%d actual=%d",
            conditionCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 一時CSVを削除する。
 *
 * @param fromTemporaryFileName 一時ファイル名。
 */
void deleteConditionTemporaryCsv(const string fromTemporaryFileName) {
    int commonFlag = 0;

    if (outputUseCommonFolder) {
        commonFlag = FILE_COMMON;
    }

    if (FileIsExist(fromTemporaryFileName, commonFlag)) {
        FileDelete(fromTemporaryFileName, commonFlag);
    }
}

/**
 * 216集計行を一時CSVへ完書後、最終ファイルへ置換する。
 *
 * @param fromRunInfo Source Run情報。
 * @param fromRows 集計行配列。
 * @param fromLogger ロガー。
 * @return 原子的な置換まで成功した場合true。
 */
bool writeConditionCsvAtomically(
    ZigZagElliotH1StudySourceRunInfo &fromRunInfo,
    ZigZagElliotH1StudyConditionBreakdownRow &fromRows[],
    Logger &fromLogger
) {
    string headerValues[];

    if (!setConditionHeaderValues(headerValues, fromLogger)) {
        return false;
    }

    string fileName = getConditionOutputFileName(fromRunInfo.runId);
    string temporaryFileName = fileName + ".tmp";
    deleteConditionTemporaryCsv(temporaryFileName);
    CsvFileWriter fileWriter(
        temporaryFileName,
        outputUseCommonFolder,
        ",",
        false,
        true,
        "",
        CSV_FILE_WRITE_MODE_OVERWRITE
    );

    if (!fileWriter.writeHeader(headerValues, false)) {
        fileWriter.close();
        deleteConditionTemporaryCsv(temporaryFileName);
        fromLogger.error(
            __FUNCTION__,
            "Temporary CSV header write failed. file=" + temporaryFileName
        );

        return false;
    }

    int rowCount = ArraySize(fromRows);

    for (int i = 0; i < rowCount; i++) {
        string rowValues[];

        if (!setConditionRowValues(
                fromRunInfo,
                fromRows[i],
                rowValues,
                fromLogger
            ) || !fileWriter.writeRow(rowValues)) {
            fileWriter.close();
            deleteConditionTemporaryCsv(temporaryFileName);
            fromLogger.error(
                __FUNCTION__,
                StringFormat("Temporary CSV row write failed. index=%d", i)
            );

            return false;
        }
    }

    fileWriter.close();
    int commonFlag = 0;

    if (outputUseCommonFolder) {
        commonFlag = FILE_COMMON;
    }

    ResetLastError();

    if (!FileMove(
            temporaryFileName,
            commonFlag,
            fileName,
            FILE_REWRITE | commonFlag
        )) {
        int moveErrorCode = GetLastError();
        deleteConditionTemporaryCsv(temporaryFileName);
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "CSV atomic replace failed. file=%s error=%d",
                fileName,
                moveErrorCode
            )
        );

        return false;
    }

    return true;
}

/**
 * 読み取りTransactionを安全にRollbackする。
 *
 * @param fromDatabaseHandle DBハンドル。
 * @param fromLogger ロガー。
 */
void rollbackConditionReadTransaction(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    if (!DatabaseTransactionRollback(fromDatabaseHandle)) {
        fromLogger.error(__FUNCTION__, "Read transaction rollback failed.");
    }
}

/**
 * 6累積条件・1/2/3本確認・4期間・ALL/BUY/SELLを集計する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!validateConditionInputs(logger)) {
        return;
    }

    SqliteDatabase sourceDatabase(
        sourceDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!sourceDatabase.openReadOnly()) {
        logger.error(__FUNCTION__, "Source DB could not be opened read-only.");

        return;
    }

    ZigZagElliotH1StudyQueryService queryService(sourceDatabase.getHandle());
    int databaseHandle = sourceDatabase.getHandle();

    if (!DatabaseTransactionBegin(databaseHandle)) {
        logger.error(__FUNCTION__, "Read transaction could not be started.");

        return;
    }

    ZigZagElliotH1StudySourceRunInfo runInfo;

    if (!selectConditionSourceRun(queryService, runInfo, logger)
            || !validateConditionSourceRun(runInfo, logger)) {
        rollbackConditionReadTransaction(databaseHandle, logger);

        return;
    }

    ZigZagElliotH1StudyStreamKey streams[];

    if (!queryService.findStreams(runInfo.runId, streams)) {
        logger.error(__FUNCTION__, "Observation Stream list read failed.");
        rollbackConditionReadTransaction(databaseHandle, logger);

        return;
    }

    int streamCount = ArraySize(streams);

    if (streamCount <= 0) {
        logger.error(__FUNCTION__, "Source Run has no Observation Stream.");
        rollbackConditionReadTransaction(databaseHandle, logger);

        return;
    }

    for (int i = 0; i < streamCount; i++) {
        if (streams[i].anchorTimeFrame != PERIOD_H1) {
            logger.error(
                __FUNCTION__,
                StringFormat(
                    "Non-H1 Stream is not supported. symbol=%s timeFrame=%d",
                    streams[i].symbolName,
                    streams[i].anchorTimeFrame
                )
            );
            rollbackConditionReadTransaction(databaseHandle, logger);

            return;
        }
    }

    ZigZagElliotH1StudyConditionBreakdownRow rows[];

    if (!initializeConditionRows(rows, logger)) {
        releaseConditionMedianSamples();
        rollbackConditionReadTransaction(databaseHandle, logger);

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Condition aggregation started. sourceRunId=%I64d streams=%d JST=[%s,%s) rules=%d",
            runInfo.runId,
            streamCount,
            TimeToString(studyFromJstTime, TIME_DATE | TIME_SECONDS),
            TimeToString(studyToJstTime, TIME_DATE | TIME_SECONDS),
            conditionRuleCount
        )
    );

    long candidateCount = 0;

    for (int i = 0; i < streamCount; i++) {
        if (!processConditionStream(
                streams[i],
                queryService,
                rows,
                candidateCount,
                logger
            )) {
            releaseConditionMedianSamples();
            rollbackConditionReadTransaction(databaseHandle, logger);

            return;
        }
    }

    if (!finalizeConditionRows(rows, logger)
            || !validateConditionRows(
                rows,
                runInfo.runId,
                candidateCount,
                logger
            )) {
        releaseConditionMedianSamples();
        rollbackConditionReadTransaction(databaseHandle, logger);

        return;
    }

    if (!DatabaseTransactionCommit(databaseHandle)) {
        logger.error(__FUNCTION__, "Read transaction commit failed.");
        rollbackConditionReadTransaction(databaseHandle, logger);
        releaseConditionMedianSamples();

        return;
    }

    releaseConditionMedianSamples();

    if (!writeConditionCsvAtomically(runInfo, rows, logger)) {
        logger.error(__FUNCTION__, "Condition breakdown CSV export failed.");

        return;
    }

    logger.info(
        __FUNCTION__,
        StringFormat(
            "Condition breakdown export finished. file=%s rows=%d candidates=%I64d outcomes=%I64d",
            getConditionOutputFileName(runInfo.runId),
            ArraySize(rows),
            candidateCount,
            candidateCount * conditionHorizonCount
        )
    );
}
//+------------------------------------------------------------------+
