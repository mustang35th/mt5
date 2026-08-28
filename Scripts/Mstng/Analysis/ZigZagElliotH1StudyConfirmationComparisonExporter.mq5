//+------------------------------------------------------------------+
//| ZigZagElliotH1StudyConfirmationComparisonExporter.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

#include <Mstng\Common\File\CsvFileWriter.mqh>
#include <Mstng\Database\SqliteDatabase.mqh>
#include <Mstng\Log\Logger.mqh>

/** H1推移研究Outcome DBファイル名。 */
input string outcomeDatabaseFileName =
    "mstng-zigzag-elliot-h1-study-outcome-2024-2025-r1.sqlite";

/** 比較対象Outcome Run ID。0の場合は完了Runを自動選択する。 */
input long outcomeRunId = 0;

/** Outcome DBをTerminal Common Filesから読み取る場合true。 */
input bool databaseUseCommonFolder = true;

/** Episode明細CSV名。空の場合はDB名とRun IDから自動生成する。 */
input string episodeOutputCsvFileName = "";

/** 集計CSV名。空の場合はDB名とRun IDから自動生成する。 */
input string summaryOutputCsvFileName = "";

/** CSVをTerminal Common Filesへ出力する場合true。 */
input bool outputUseCommonFolder = true;

/** Episode明細CSVのスキーマバージョン。 */
const string comparisonEpisodeCsvSchemaVersion =
    "H1_STUDY_CONFIRMATION_COMPARISON_EPISODE_V1";

/** 集計CSVのスキーマバージョン。 */
const string comparisonSummaryCsvSchemaVersion =
    "H1_STUDY_CONFIRMATION_COMPARISON_SUMMARY_V1";

/** 損益および差分の同値判定に使用するpips許容差。 */
const double comparisonEpsilonPips = 0.00000001;

/** Episode明細CSVの列数。 */
const int comparisonEpisodeCsvFieldCount = 125;

/** 集計CSVの列数。 */
const int comparisonSummaryCsvFieldCount = 169;

/** 比較対象Cohort数。 */
const int comparisonCohortCount = 2;

/** 評価期間数。 */
const int comparisonHorizonCount = 4;

/** 方向範囲数。 */
const int comparisonSideScopeCount = 3;

/** 集計CSVの期待行数。 */
const int comparisonExpectedSummaryRowCount = 24;

/** 1／2本確認を比較するCohort。 */
const string comparisonPairCohort = "PAIR_1_2";

/** 1／2／3本確認を比較する共通Cohort。 */
const string comparisonTripleCohort = "COMMON_1_2_3";

/** 完了済みOutcome Runの比較用情報。 */
struct ZigZagElliotH1StudyComparisonRunInfo {
    /** Outcome Run ID。 */
    long id;

    /** Outcome Runの一意キー。 */
    string runKey;

    /** 参照元H1推移DBファイル名。 */
    string sourceDatabaseFileName;

    /** 参照元H1推移Run ID。 */
    long sourceRunId;

    /** 参照元H1推移Run UID。 */
    string sourceRunUid;

    /** 研究対象開始JST。 */
    datetime studyFromJstTime;

    /** 研究対象終了JSTの対象外境界。 */
    datetime studyToJstTime;

    /** 連続シグナル判定ルールバージョン。 */
    string signalRuleVersion;

    /** 研究用エントリー価格モデル。 */
    string entryPriceModel;

    /** Outcome価格モデル。 */
    string outcomePriceModel;

    /** Spread控除モデル。 */
    string spreadModel;

    /** 将来成績計算ロジックバージョン。 */
    string evaluationVersion;

    /** 評価期間一覧。 */
    string horizonsText;

    /** Run状態。 */
    string status;

    /** Runへ記録されたEntry総数。 */
    long totalEntryCount;

    /** Runへ記録された研究対象Entry数。 */
    long researchEligibleEntryCount;

    /** Runへ記録されたOutcome総数。 */
    long totalOutcomeCount;

    /** Runへ記録された計算成功Outcome数。 */
    long calculatedOutcomeCount;

    /** Runへ記録された計算不能Outcome数。 */
    long failedOutcomeCount;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.id = 0;
        this.runKey = "";
        this.sourceDatabaseFileName = "";
        this.sourceRunId = 0;
        this.sourceRunUid = "";
        this.studyFromJstTime = 0;
        this.studyToJstTime = 0;
        this.signalRuleVersion = "";
        this.entryPriceModel = "";
        this.outcomePriceModel = "";
        this.spreadModel = "";
        this.evaluationVersion = "";
        this.horizonsText = "";
        this.status = "";
        this.totalEntryCount = 0;
        this.researchEligibleEntryCount = 0;
        this.totalOutcomeCount = 0;
        this.calculatedOutcomeCount = 0;
        this.failedOutcomeCount = 0;
    }
};

/** Episode明細に出力する1確認本数分のEntryおよびOutcome。 */
struct ZigZagElliotH1StudyComparisonLeg {
    /** Entryが存在する場合true。 */
    bool isPresent;

    /** Entry ID。 */
    long entryId;

    /** 確認Observation ID。 */
    long confirmationObservationId;

    /** 確認JST。 */
    datetime confirmationJstTime;

    /** Entry JST。 */
    datetime entryJstTime;

    /** Entry時Spread pips。 */
    double spreadPips;

    /** 研究対象Entryの場合1。 */
    int isResearchEligible;

    /** Entryの研究対象状態。 */
    string eligibilityStatus;

    /** Outcome計算成功の場合1。 */
    int isCalculated;

    /** Outcome状態。 */
    string dataStatus;

    /** Spread控除前損益pips。 */
    double grossProfitPips;

    /** Spread控除後損益pips。 */
    double netProfitPips;

    /** Spread控除前損益ATR。 */
    double grossProfitAtr;

    /** Spread控除後損益ATR。 */
    double netProfitAtr;

    /** 最大有利幅pips。 */
    double mfePips;

    /** 最大不利幅pips。 */
    double maePips;

    /** 最大利益へ最初に到達するまでのH1本数。 */
    int maxProfitH1Bars;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.isPresent = false;
        this.entryId = 0;
        this.confirmationObservationId = 0;
        this.confirmationJstTime = 0;
        this.entryJstTime = 0;
        this.spreadPips = 0.0;
        this.isResearchEligible = 0;
        this.eligibilityStatus = "";
        this.isCalculated = 0;
        this.dataStatus = "";
        this.grossProfitPips = 0.0;
        this.netProfitPips = 0.0;
        this.grossProfitAtr = 0.0;
        this.netProfitAtr = 0.0;
        this.mfePips = 0.0;
        this.maePips = 0.0;
        this.maxProfitH1Bars = 0;
    }
};

/** 2つの確認タイミング間の差分。正値は待機側の改善を表す。 */
struct ZigZagElliotH1StudyComparisonDelta {
    /** 共通成績を比較可能な場合true。 */
    bool isAvailable;

    /** 待機側－先行側のSpread控除前損益pips。 */
    double grossProfitPips;

    /** 待機側－先行側のSpread控除後損益pips。 */
    double netProfitPips;

    /** 待機側－先行側のSpread控除前損益ATR。 */
    double grossProfitAtr;

    /** 待機側－先行側のSpread控除後損益ATR。 */
    double netProfitAtr;

    /** 先行側－待機側のSpread pips。正値はSpread縮小。 */
    double spreadReductionPips;

    /** 待機側－先行側のMFE pips。 */
    double mfeImprovementPips;

    /** 先行側－待機側のMAE pips。正値はMAE縮小。 */
    double maeReductionPips;

    /** 最大利益到達本数を比較可能な場合true。 */
    bool isMaxProfitSpeedupAvailable;

    /** 先行側－待機側の最大利益到達本数。正値は高速化。 */
    int maxProfitSpeedupH1Bars;

    /** LATER_BETTER、EARLIER_BETTERまたはUNCHANGED。 */
    string preference;

    /** WIN／LOSS／FLATの先行側から待機側への遷移。 */
    string transition;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.isAvailable = false;
        this.grossProfitPips = 0.0;
        this.netProfitPips = 0.0;
        this.grossProfitAtr = 0.0;
        this.netProfitAtr = 0.0;
        this.spreadReductionPips = 0.0;
        this.mfeImprovementPips = 0.0;
        this.maeReductionPips = 0.0;
        this.isMaxProfitSpeedupAvailable = false;
        this.maxProfitSpeedupH1Bars = 0;
        this.preference = "";
        this.transition = "";
    }
};

/** 同じEpisodeの1／2／3本確認を横持ちした1期間分の明細。 */
struct ZigZagElliotH1StudyComparisonEpisodeRow {
    /** シグナル開始Observation ID。 */
    long signalStartObservationId;

    /** シグナル終了Observation ID。 */
    long signalEndObservationId;

    /** 対象シンボル。 */
    string symbolName;

    /** BUYまたはSELL。 */
    string side;

    /** Episode全体のH1本数。 */
    int episodeH1Count;

    /** シグナル開始サーバー時刻。 */
    datetime signalStartTime;

    /** シグナル開始JST。 */
    datetime signalStartJstTime;

    /** 左端打切りの場合1。 */
    int isLeftCensored;

    /** 右端打切りの場合1。 */
    int isRightCensored;

    /** Episode直前Gapの場合1。 */
    int hasDataGapBefore;

    /** Episode直後Gapの場合1。 */
    int hasDataGapAfter;

    /** 評価H1本数。 */
    int horizonH1Bars;

    /** 1本確認Leg。 */
    ZigZagElliotH1StudyComparisonLeg leg1;

    /** 2本確認Leg。 */
    ZigZagElliotH1StudyComparisonLeg leg2;

    /** 3本確認Leg。 */
    ZigZagElliotH1StudyComparisonLeg leg3;

    /** PAIR_1_2共通研究対象の場合true。 */
    bool isPairResearchEligible;

    /** PAIR_1_2共通計算成功の場合true。 */
    bool isPairCalculated;

    /** PAIR_1_2に将来H1 Gapがある場合true。 */
    bool hasPairFutureH1Gap;

    /** PAIR_1_2比較状態。 */
    string pairComparisonStatus;

    /** 3本確認Entryが存在する場合true。 */
    bool isTripleApplicable;

    /** COMMON_1_2_3共通研究対象の場合true。 */
    bool isTripleResearchEligible;

    /** COMMON_1_2_3共通計算成功の場合true。 */
    bool isTripleCalculated;

    /** COMMON_1_2_3に将来H1 Gapがある場合true。 */
    bool hasTripleFutureH1Gap;

    /** COMMON_1_2_3比較状態。 */
    string tripleComparisonStatus;

    /** 2本確認－1本確認の差分。 */
    ZigZagElliotH1StudyComparisonDelta delta21;

    /** 3本確認－1本確認の差分。 */
    ZigZagElliotH1StudyComparisonDelta delta31;

    /** 3本確認－2本確認の差分。 */
    ZigZagElliotH1StudyComparisonDelta delta32;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.signalStartObservationId = 0;
        this.signalEndObservationId = 0;
        this.symbolName = "";
        this.side = "";
        this.episodeH1Count = 0;
        this.signalStartTime = 0;
        this.signalStartJstTime = 0;
        this.isLeftCensored = 0;
        this.isRightCensored = 0;
        this.hasDataGapBefore = 0;
        this.hasDataGapAfter = 0;
        this.horizonH1Bars = 0;
        this.leg1.reset();
        this.leg2.reset();
        this.leg3.reset();
        this.isPairResearchEligible = false;
        this.isPairCalculated = false;
        this.hasPairFutureH1Gap = false;
        this.pairComparisonStatus = "";
        this.isTripleApplicable = false;
        this.isTripleResearchEligible = false;
        this.isTripleCalculated = false;
        this.hasTripleFutureH1Gap = false;
        this.tripleComparisonStatus = "";
        this.delta21.reset();
        this.delta31.reset();
        this.delta32.reset();
    }
};

/** 共通Cohortにおける1確認本数分の成績。 */
struct ZigZagElliotH1StudyComparisonLegSummary {
    /** Cohortで使用するLegの場合true。 */
    bool isApplicable;

    /** 成績統計を計算可能な場合true。 */
    bool isStatisticsAvailable;

    /** 勝ち件数。 */
    long winningCount;

    /** 負け件数。 */
    long losingCount;

    /** 同値件数。 */
    long flatCount;

    /** 勝率。 */
    double winRatePercent;

    /** Spread控除後損益合計。 */
    double netProfitSumPips;

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

    /** Profit Factor状態。 */
    string profitFactorStatus;

    /** MFE平均。 */
    double averageMfePips;

    /** MAE平均。 */
    double averageMaePips;

    /** Spread控除前損益ATR平均。 */
    double averageGrossProfitAtr;

    /** Spread控除後損益ATR平均。 */
    double averageNetProfitAtr;

    /** Entry Spread平均。 */
    double averageEntrySpreadPips;

    /** 最大利益到達本数平均。 */
    double averageMaxProfitH1Bars;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.isApplicable = false;
        this.isStatisticsAvailable = false;
        this.winningCount = 0;
        this.losingCount = 0;
        this.flatCount = 0;
        this.winRatePercent = 0.0;
        this.netProfitSumPips = 0.0;
        this.averageGrossProfitPips = 0.0;
        this.averageNetProfitPips = 0.0;
        this.medianNetProfitPips = 0.0;
        this.winningNetProfitSumPips = 0.0;
        this.losingNetProfitAbsSumPips = 0.0;
        this.profitFactor = 0.0;
        this.profitFactorStatus = "NOT_APPLICABLE";
        this.averageMfePips = 0.0;
        this.averageMaePips = 0.0;
        this.averageGrossProfitAtr = 0.0;
        this.averageNetProfitAtr = 0.0;
        this.averageEntrySpreadPips = 0.0;
        this.averageMaxProfitH1Bars = 0.0;
    }
};

/** 共通Cohortにおける2確認タイミング間の差分集計。 */
struct ZigZagElliotH1StudyComparisonDeltaSummary {
    /** Cohortで使用する差分の場合true。 */
    bool isApplicable;

    /** 差分統計を計算可能な場合true。 */
    bool isStatisticsAvailable;

    /** 待機側改善件数。 */
    long improvedCount;

    /** 同値件数。 */
    long unchangedCount;

    /** 待機側悪化件数。 */
    long worsenedCount;

    /** 待機側改善率。 */
    double improvementRatePercent;

    /** 同値率。 */
    double unchangedRatePercent;

    /** 待機側悪化率。 */
    double worseningRatePercent;

    /** Spread控除前損益改善幅平均。 */
    double averageGrossProfitPips;

    /** Spread控除後損益改善幅平均。 */
    double averageNetProfitPips;

    /** Spread控除後損益改善幅中央値。 */
    double medianNetProfitPips;

    /** Spread控除前損益ATR改善幅平均。 */
    double averageGrossProfitAtr;

    /** Spread控除後損益ATR改善幅平均。 */
    double averageNetProfitAtr;

    /** Spread縮小幅平均。 */
    double averageSpreadReductionPips;

    /** MFE改善幅平均。 */
    double averageMfeImprovementPips;

    /** MAE縮小幅平均。 */
    double averageMaeReductionPips;

    /** 最大利益到達速度を比較できる件数。 */
    long maxProfitSpeedupComparableCount;

    /** 最大利益到達高速化本数平均。 */
    double averageMaxProfitSpeedupH1Bars;

    /** WINからWINへの遷移件数。 */
    long winToWinCount;

    /** WINからFLATへの遷移件数。 */
    long winToFlatCount;

    /** WINからLOSSへの遷移件数。 */
    long winToLossCount;

    /** FLATからWINへの遷移件数。 */
    long flatToWinCount;

    /** FLATからFLATへの遷移件数。 */
    long flatToFlatCount;

    /** FLATからLOSSへの遷移件数。 */
    long flatToLossCount;

    /** LOSSからWINへの遷移件数。 */
    long lossToWinCount;

    /** LOSSからFLATへの遷移件数。 */
    long lossToFlatCount;

    /** LOSSからLOSSへの遷移件数。 */
    long lossToLossCount;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.isApplicable = false;
        this.isStatisticsAvailable = false;
        this.improvedCount = 0;
        this.unchangedCount = 0;
        this.worsenedCount = 0;
        this.improvementRatePercent = 0.0;
        this.unchangedRatePercent = 0.0;
        this.worseningRatePercent = 0.0;
        this.averageGrossProfitPips = 0.0;
        this.averageNetProfitPips = 0.0;
        this.medianNetProfitPips = 0.0;
        this.averageGrossProfitAtr = 0.0;
        this.averageNetProfitAtr = 0.0;
        this.averageSpreadReductionPips = 0.0;
        this.averageMfeImprovementPips = 0.0;
        this.averageMaeReductionPips = 0.0;
        this.maxProfitSpeedupComparableCount = 0;
        this.averageMaxProfitSpeedupH1Bars = 0.0;
        this.winToWinCount = 0;
        this.winToFlatCount = 0;
        this.winToLossCount = 0;
        this.flatToWinCount = 0;
        this.flatToFlatCount = 0;
        this.flatToLossCount = 0;
        this.lossToWinCount = 0;
        this.lossToFlatCount = 0;
        this.lossToLossCount = 0;
    }
};

/** 1つのCohort・評価期間・方向範囲の公平比較集計。 */
struct ZigZagElliotH1StudyComparisonSummaryRow {
    /** PAIR_1_2またはCOMMON_1_2_3。 */
    string cohortType;

    /** 必要な最大確認H1本数。 */
    int requiredConfirmationH1Count;

    /** ALL、BUYまたはSELL。 */
    string sideScope;

    /** 評価H1本数。 */
    int horizonH1Bars;

    /** Cohort候補Episode数。 */
    long candidateEpisodeCount;

    /** 共通研究対象外Episode数。 */
    long ineligibleEpisodeCount;

    /** 共通研究対象Episode数。 */
    long eligibleEpisodeCount;

    /** 全必要Outcomeを計算できたEpisode数。 */
    long commonCalculatedEpisodeCount;

    /** 共通研究対象だが比較不能のEpisode数。 */
    long failedEpisodeCount;

    /** 将来H1 Gapを持つ比較不能Episode数。 */
    long futureH1GapEpisodeCount;

    /** Gap以外で比較不能のEpisode数。 */
    long otherFailureEpisodeCount;

    /** 共通研究対象に対する計算Coverage。 */
    double calculationCoveragePercent;

    /** 1本確認成績。 */
    ZigZagElliotH1StudyComparisonLegSummary leg1;

    /** 2本確認成績。 */
    ZigZagElliotH1StudyComparisonLegSummary leg2;

    /** 3本確認成績。 */
    ZigZagElliotH1StudyComparisonLegSummary leg3;

    /** 2本確認－1本確認の差分集計。 */
    ZigZagElliotH1StudyComparisonDeltaSummary delta21;

    /** 3本確認－1本確認の差分集計。 */
    ZigZagElliotH1StudyComparisonDeltaSummary delta31;

    /** 3本確認－2本確認の差分集計。 */
    ZigZagElliotH1StudyComparisonDeltaSummary delta32;

    /**
     * 全フィールドを初期化する。
     */
    void reset() {
        this.cohortType = "";
        this.requiredConfirmationH1Count = 0;
        this.sideScope = "";
        this.horizonH1Bars = 0;
        this.candidateEpisodeCount = 0;
        this.ineligibleEpisodeCount = 0;
        this.eligibleEpisodeCount = 0;
        this.commonCalculatedEpisodeCount = 0;
        this.failedEpisodeCount = 0;
        this.futureH1GapEpisodeCount = 0;
        this.otherFailureEpisodeCount = 0;
        this.calculationCoveragePercent = 0.0;
        this.leg1.reset();
        this.leg2.reset();
        this.leg3.reset();
        this.delta21.reset();
        this.delta31.reset();
        this.delta32.reset();
    }
};

/**
 * 配列位置からCohort名を取得する。
 *
 * @param fromIndex 配列位置。
 * @return Cohort名。範囲外は空文字。
 */
string getComparisonCohortType(const int fromIndex) {
    if (fromIndex == 0) {
        return comparisonPairCohort;
    }

    if (fromIndex == 1) {
        return comparisonTripleCohort;
    }

    return "";
}

/**
 * Cohortが必要とする最大確認本数を取得する。
 *
 * @param fromCohortType Cohort名。
 * @return 2または3。対象外は0。
 */
int getComparisonRequiredConfirmationH1Count(
    const string fromCohortType
) {
    if (fromCohortType == comparisonPairCohort) {
        return 2;
    }

    if (fromCohortType == comparisonTripleCohort) {
        return 3;
    }

    return 0;
}

/**
 * 配列位置から評価H1本数を取得する。
 *
 * @param fromIndex 配列位置。
 * @return 6、12、24または48。範囲外は0。
 */
int getComparisonHorizonH1Bars(const int fromIndex) {
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
 * 配列位置から方向範囲を取得する。
 *
 * @param fromIndex 配列位置。
 * @return ALL、BUYまたはSELL。範囲外は空文字。
 */
string getComparisonSideScope(const int fromIndex) {
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
 * 許容差内の値を0へ正規化する。
 *
 * @param fromValue 正規化対象。
 * @return 正規化した値。
 */
double normalizeComparisonDelta(const double fromValue) {
    if (MathAbs(fromValue) <= comparisonEpsilonPips) {
        return 0.0;
    }

    return fromValue;
}

/**
 * Spread控除後損益をWIN、LOSSまたはFLATへ分類する。
 *
 * @param fromNetProfitPips Spread控除後損益pips。
 * @return WIN、LOSSまたはFLAT。
 */
string classifyComparisonProfit(const double fromNetProfitPips) {
    if (fromNetProfitPips > comparisonEpsilonPips) {
        return "WIN";
    }

    if (fromNetProfitPips < -comparisonEpsilonPips) {
        return "LOSS";
    }

    return "FLAT";
}

/**
 * 待機前後のSpread控除後損益差から優劣を取得する。
 *
 * @param fromNetProfitDeltaPips 待機側－先行側の損益pips。
 * @return LATER_BETTER、EARLIER_BETTERまたはUNCHANGED。
 */
string classifyComparisonPreference(
    const double fromNetProfitDeltaPips
) {
    if (fromNetProfitDeltaPips > comparisonEpsilonPips) {
        return "LATER_BETTER";
    }

    if (fromNetProfitDeltaPips < -comparisonEpsilonPips) {
        return "EARLIER_BETTER";
    }

    return "UNCHANGED";
}

/**
 * LegのOutcomeに将来H1 Gapがあるか確認する。
 *
 * @param fromLeg 確認対象Leg。
 * @return FUTURE_H1_GAPの場合true。
 */
bool hasComparisonFutureH1Gap(
    ZigZagElliotH1StudyComparisonLeg &fromLeg
) {
    return fromLeg.isPresent
        && fromLeg.isCalculated == 0
        && fromLeg.dataStatus == "FUTURE_H1_GAP";
}

/**
 * 2つのLegから待機効果の差分を組み立てる。
 *
 * @param fromEarlierLeg 先行側Leg。
 * @param fromLaterLeg 待機側Leg。
 * @param fromIsAvailable 共通成績を比較可能な場合true。
 * @param fromDelta 組み立て先。
 */
void buildComparisonDelta(
    ZigZagElliotH1StudyComparisonLeg &fromEarlierLeg,
    ZigZagElliotH1StudyComparisonLeg &fromLaterLeg,
    const bool fromIsAvailable,
    ZigZagElliotH1StudyComparisonDelta &fromDelta
) {
    fromDelta.reset();

    if (!fromIsAvailable) {
        return;
    }

    fromDelta.isAvailable = true;
    fromDelta.grossProfitPips = normalizeComparisonDelta(
        fromLaterLeg.grossProfitPips - fromEarlierLeg.grossProfitPips
    );
    fromDelta.netProfitPips = normalizeComparisonDelta(
        fromLaterLeg.netProfitPips - fromEarlierLeg.netProfitPips
    );
    fromDelta.grossProfitAtr = normalizeComparisonDelta(
        fromLaterLeg.grossProfitAtr - fromEarlierLeg.grossProfitAtr
    );
    fromDelta.netProfitAtr = normalizeComparisonDelta(
        fromLaterLeg.netProfitAtr - fromEarlierLeg.netProfitAtr
    );
    fromDelta.spreadReductionPips = normalizeComparisonDelta(
        fromEarlierLeg.spreadPips - fromLaterLeg.spreadPips
    );
    fromDelta.mfeImprovementPips = normalizeComparisonDelta(
        fromLaterLeg.mfePips - fromEarlierLeg.mfePips
    );
    fromDelta.maeReductionPips = normalizeComparisonDelta(
        fromEarlierLeg.maePips - fromLaterLeg.maePips
    );

    if (fromEarlierLeg.mfePips > comparisonEpsilonPips
            && fromLaterLeg.mfePips > comparisonEpsilonPips) {
        fromDelta.isMaxProfitSpeedupAvailable = true;
        fromDelta.maxProfitSpeedupH1Bars =
            fromEarlierLeg.maxProfitH1Bars
            - fromLaterLeg.maxProfitH1Bars;
    }

    fromDelta.preference = classifyComparisonPreference(
        fromDelta.netProfitPips
    );
    fromDelta.transition = classifyComparisonProfit(
        fromEarlierLeg.netProfitPips
    ) + "_TO_" + classifyComparisonProfit(fromLaterLeg.netProfitPips);
}

/**
 * Episode行の共通対象状態、監査状態および差分を確定する。
 *
 * @param fromRow 確定対象。
 */
void finalizeComparisonEpisodeRow(
    ZigZagElliotH1StudyComparisonEpisodeRow &fromRow
) {
    fromRow.isPairResearchEligible = fromRow.leg1.isPresent
        && fromRow.leg2.isPresent
        && fromRow.leg1.isResearchEligible == 1
        && fromRow.leg2.isResearchEligible == 1;
    fromRow.isPairCalculated = fromRow.isPairResearchEligible
        && fromRow.leg1.isCalculated == 1
        && fromRow.leg2.isCalculated == 1;
    fromRow.hasPairFutureH1Gap = hasComparisonFutureH1Gap(fromRow.leg1)
        || hasComparisonFutureH1Gap(fromRow.leg2);

    if (!fromRow.isPairResearchEligible) {
        fromRow.pairComparisonStatus = "INELIGIBLE";
    } else if (fromRow.isPairCalculated) {
        fromRow.pairComparisonStatus = "READY";
    } else if (fromRow.hasPairFutureH1Gap) {
        fromRow.pairComparisonStatus = "FUTURE_H1_GAP";
    } else {
        fromRow.pairComparisonStatus = "OTHER_FAILURE";
    }

    fromRow.isTripleApplicable = fromRow.leg3.isPresent;
    fromRow.isTripleResearchEligible = fromRow.isTripleApplicable
        && fromRow.isPairResearchEligible
        && fromRow.leg3.isResearchEligible == 1;
    fromRow.isTripleCalculated = fromRow.isTripleResearchEligible
        && fromRow.leg1.isCalculated == 1
        && fromRow.leg2.isCalculated == 1
        && fromRow.leg3.isCalculated == 1;
    fromRow.hasTripleFutureH1Gap = fromRow.isTripleApplicable
        && (fromRow.hasPairFutureH1Gap
            || hasComparisonFutureH1Gap(fromRow.leg3));

    if (!fromRow.isTripleApplicable) {
        fromRow.tripleComparisonStatus = "NOT_APPLICABLE";
    } else if (!fromRow.isTripleResearchEligible) {
        fromRow.tripleComparisonStatus = "INELIGIBLE";
    } else if (fromRow.isTripleCalculated) {
        fromRow.tripleComparisonStatus = "READY";
    } else if (fromRow.hasTripleFutureH1Gap) {
        fromRow.tripleComparisonStatus = "FUTURE_H1_GAP";
    } else {
        fromRow.tripleComparisonStatus = "OTHER_FAILURE";
    }

    buildComparisonDelta(
        fromRow.leg1,
        fromRow.leg2,
        fromRow.isPairCalculated,
        fromRow.delta21
    );
    buildComparisonDelta(
        fromRow.leg1,
        fromRow.leg3,
        fromRow.isTripleCalculated,
        fromRow.delta31
    );
    buildComparisonDelta(
        fromRow.leg2,
        fromRow.leg3,
        fromRow.isTripleCalculated,
        fromRow.delta32
    );
}

/**
 * ファイル名がCSV拡張子を持つか確認する。
 *
 * @param fromFileName 確認対象。
 * @return 末尾が.csvの場合true。
 */
bool isComparisonCsvFileName(const string fromFileName) {
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
 * DBファイル名から既定CSV名用の識別子を作る。
 *
 * @return ファイル名として使用可能な識別子。
 */
string getComparisonDatabaseToken() {
    string token = outcomeDatabaseFileName;
    StringReplace(token, "mstng-zigzag-elliot-h1-study-outcome-", "");
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
        token = "outcome";
    }

    return token;
}

/**
 * 実際のEpisode明細CSV名を取得する。
 *
 * @param fromRunId Outcome Run ID。
 * @return 入力値または自動生成名。
 */
string getComparisonEpisodeOutputFileName(const long fromRunId) {
    if (episodeOutputCsvFileName != "") {
        return episodeOutputCsvFileName;
    }

    return StringFormat(
        "mstng-zigzag-elliot-h1-study-confirmation-comparison-episodes-%s-run-%I64d.csv",
        getComparisonDatabaseToken(),
        fromRunId
    );
}

/**
 * 実際の集計CSV名を取得する。
 *
 * @param fromRunId Outcome Run ID。
 * @return 入力値または自動生成名。
 */
string getComparisonSummaryOutputFileName(const long fromRunId) {
    if (summaryOutputCsvFileName != "") {
        return summaryOutputCsvFileName;
    }

    return StringFormat(
        "mstng-zigzag-elliot-h1-study-confirmation-comparison-summary-%s-run-%I64d.csv",
        getComparisonDatabaseToken(),
        fromRunId
    );
}

/**
 * Script入力を検証する。
 *
 * @param fromLogger ロガー。
 * @return 実行可能な場合true。
 */
bool validateComparisonInputs(Logger &fromLogger) {
    if (outcomeDatabaseFileName == "") {
        fromLogger.error(__FUNCTION__, "outcomeDatabaseFileName is empty.");

        return false;
    }

    if (outcomeRunId < 0) {
        fromLogger.error(__FUNCTION__, "outcomeRunId must not be negative.");

        return false;
    }

    if (comparisonEpsilonPips <= 0.0) {
        fromLogger.error(__FUNCTION__, "comparisonEpsilonPips is invalid.");

        return false;
    }

    if (episodeOutputCsvFileName != ""
            && !isComparisonCsvFileName(episodeOutputCsvFileName)) {
        fromLogger.error(
            __FUNCTION__,
            "episodeOutputCsvFileName must have a .csv extension."
        );

        return false;
    }

    if (summaryOutputCsvFileName != ""
            && !isComparisonCsvFileName(summaryOutputCsvFileName)) {
        fromLogger.error(
            __FUNCTION__,
            "summaryOutputCsvFileName must have a .csv extension."
        );

        return false;
    }

    if (episodeOutputCsvFileName != ""
            && summaryOutputCsvFileName != ""
            && StringCompare(
                episodeOutputCsvFileName,
                summaryOutputCsvFileName,
                false
            ) == 0) {
        fromLogger.error(
            __FUNCTION__,
            "Episode and summary CSV files must be different."
        );

        return false;
    }

    if (outputUseCommonFolder == databaseUseCommonFolder
            && ((episodeOutputCsvFileName != ""
                    && StringCompare(
                        episodeOutputCsvFileName,
                        outcomeDatabaseFileName,
                        false
                    ) == 0)
                || (summaryOutputCsvFileName != ""
                    && StringCompare(
                        summaryOutputCsvFileName,
                        outcomeDatabaseFileName,
                        false
                    ) == 0))) {
        fromLogger.error(
            __FUNCTION__,
            "Outcome DB and output CSV files must be different."
        );

        return false;
    }

    return true;
}

/**
 * 現在行からRun情報を読み取る。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromRunInfo 読取先。
 * @param fromLogger ロガー。
 * @return 全列を読み取れた場合true。
 */
bool readComparisonRunInfo(
    const int fromRequestHandle,
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    fromRunInfo.reset();
    long studyFromJstTimeValue = 0;
    long studyToJstTimeValue = 0;
    bool isRead = DatabaseColumnLong(fromRequestHandle, 0, fromRunInfo.id);

    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            1,
            fromRunInfo.runKey
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            2,
            fromRunInfo.sourceDatabaseFileName
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            3,
            fromRunInfo.sourceRunId
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            4,
            fromRunInfo.sourceRunUid
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            5,
            studyFromJstTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            6,
            studyToJstTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            7,
            fromRunInfo.signalRuleVersion
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            8,
            fromRunInfo.entryPriceModel
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            9,
            fromRunInfo.spreadModel
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            10,
            fromRunInfo.evaluationVersion
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            11,
            fromRunInfo.horizonsText
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            12,
            fromRunInfo.status
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            13,
            fromRunInfo.totalEntryCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            14,
            fromRunInfo.researchEligibleEntryCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            15,
            fromRunInfo.totalOutcomeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            16,
            fromRunInfo.calculatedOutcomeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            17,
            fromRunInfo.failedOutcomeCount
        );
    }

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "DatabaseColumn read failed. error=%d",
                GetLastError()
            )
        );

        return false;
    }

    fromRunInfo.studyFromJstTime = (datetime)studyFromJstTimeValue;
    fromRunInfo.studyToJstTime = (datetime)studyToJstTimeValue;

    return true;
}

/**
 * 集計対象の完了Runを選択する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunInfo 選択結果。
 * @param fromLogger ロガー。
 * @return 1件のRunを選択できた場合true。
 */
bool selectComparisonRun(
    const int fromDatabaseHandle,
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    fromRunInfo.reset();
    string sql = "SELECT id, run_key, source_database_file_name,";
    sql += " source_run_id, source_run_uid, study_from_jst_time,";
    sql += " study_to_jst_time, signal_rule_version, entry_price_model,";
    sql += " spread_model, evaluation_version, horizons_text, status,";
    sql += " total_entry_count, research_eligible_entry_count,";
    sql += " total_outcome_count, calculated_outcome_count,";
    sql += " failed_outcome_count ";
    sql += "FROM zigzag_elliot_h1_study_outcome_runs ";
    sql += "WHERE status = 'COMPLETED' AND (?1 = 0 OR id = ?1) ";
    sql += "ORDER BY id ASC";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseBind(requestHandle, 0, outcomeRunId)) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    int runCount = 0;

    while (true) {
        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);

            if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseRead failed. error=%d",
                        readErrorCode
                    )
                );

                return false;
            }

            break;
        }

        runCount++;

        if (runCount > 1) {
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                "outcomeRunId=0 requires exactly one completed Run."
            );

            return false;
        }

        if (!readComparisonRunInfo(
                requestHandle,
                fromRunInfo,
                fromLogger
            )) {
            DatabaseFinalize(requestHandle);

            return false;
        }
    }

    if (runCount != 1) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Completed Outcome Run was not selected. requested=%I64d",
                outcomeRunId
            )
        );

        return false;
    }

    if (fromRunInfo.id <= 0
            || fromRunInfo.runKey == ""
            || fromRunInfo.sourceDatabaseFileName == ""
            || fromRunInfo.sourceRunId <= 0
            || fromRunInfo.sourceRunUid == ""
            || fromRunInfo.studyFromJstTime <= 0
            || fromRunInfo.studyToJstTime <= fromRunInfo.studyFromJstTime
            || fromRunInfo.signalRuleVersion == ""
            || fromRunInfo.entryPriceModel == ""
            || fromRunInfo.spreadModel == ""
            || fromRunInfo.evaluationVersion == ""
            || fromRunInfo.horizonsText != "6,12,24,48"
            || fromRunInfo.status != "COMPLETED") {
        fromLogger.error(
            __FUNCTION__,
            "Selected Outcome Run metadata is invalid."
        );

        return false;
    }

    fromLogger.info(
        __FUNCTION__,
        StringFormat(
            "Completed Outcome Run was selected. outcomeRunId=%I64d sourceRunId=%I64d",
            fromRunInfo.id,
            fromRunInfo.sourceRunId
        )
    );

    return true;
}

/**
 * Runカウンタ、Outcome構成およびEpisode確認本数を検証する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunInfo 選択したRun。
 * @param fromLogger ロガー。
 * @return 公平比較へ使用可能な場合true。
 */
bool validateComparisonRunData(
    const int fromDatabaseHandle,
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    Logger &fromLogger
) {
    string sql = "SELECT ";
    sql += "(SELECT COUNT(*) FROM zigzag_elliot_h1_study_entries ";
    sql += "WHERE outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(SUM(is_research_eligible), 0) ";
    sql += "FROM zigzag_elliot_h1_study_entries ";
    sql += "WHERE outcome_run_id = ?1),";
    sql += "(SELECT COUNT(*) FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(SUM(o.is_calculated), 0) ";
    sql += "FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(SUM(1 - o.is_calculated), 0) ";
    sql += "FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COUNT(*) FROM (SELECT e.id FROM ";
    sql += "zigzag_elliot_h1_study_entries AS e LEFT JOIN ";
    sql += "zigzag_elliot_h1_study_outcomes AS o ON o.entry_id = e.id ";
    sql += "WHERE e.outcome_run_id = ?1 GROUP BY e.id ";
    sql += "HAVING COUNT(o.id) <> 4)),";
    sql += "(SELECT COUNT(*) FROM zigzag_elliot_h1_study_outcomes AS o ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "JOIN zigzag_elliot_h1_study_outcome_runs AS r ";
    sql += "ON r.id = e.outcome_run_id WHERE e.outcome_run_id = ?1 AND (";
    sql += "e.signal_rule_version <> r.signal_rule_version OR ";
    sql += "e.entry_price_model <> r.entry_price_model OR ";
    sql += "e.spread_model <> r.spread_model OR ";
    sql += "e.evaluation_version <> r.evaluation_version OR ";
    sql += "o.spread_model <> r.spread_model OR ";
    sql += "o.evaluation_version <> r.evaluation_version OR ";
    sql += "o.price_model = '' OR ";
    sql += "(o.is_calculated = 1 AND o.data_status <> 'READY') OR ";
    sql += "(o.is_calculated = 0 AND o.data_status = 'READY'))),";
    sql += "(SELECT COUNT(DISTINCT o.price_model) FROM ";
    sql += "zigzag_elliot_h1_study_outcomes AS o JOIN ";
    sql += "zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COALESCE(MIN(o.price_model), '') FROM ";
    sql += "zigzag_elliot_h1_study_outcomes AS o JOIN ";
    sql += "zigzag_elliot_h1_study_entries AS e ON e.id = o.entry_id ";
    sql += "WHERE e.outcome_run_id = ?1),";
    sql += "(SELECT COUNT(*) FROM (SELECT signal_start_observation_id,";
    sql += " MIN(episode_h1_count) AS min_episode_h1_count,";
    sql += " MAX(episode_h1_count) AS max_episode_h1_count,";
    sql += " COUNT(*) AS entry_count,";
    sql += " SUM(CASE WHEN confirmation_h1_count = 1 THEN 1 ELSE 0 END)";
    sql += " AS confirmation1_count,";
    sql += " SUM(CASE WHEN confirmation_h1_count = 2 THEN 1 ELSE 0 END)";
    sql += " AS confirmation2_count,";
    sql += " SUM(CASE WHEN confirmation_h1_count = 3 THEN 1 ELSE 0 END)";
    sql += " AS confirmation3_count,";
    sql += " COUNT(DISTINCT signal_end_observation_id) AS end_count,";
    sql += " COUNT(DISTINCT symbol_name) AS symbol_count,";
    sql += " COUNT(DISTINCT side) AS side_count ";
    sql += "FROM zigzag_elliot_h1_study_entries ";
    sql += "WHERE outcome_run_id = ?1 GROUP BY signal_start_observation_id ";
    sql += "HAVING min_episode_h1_count <> max_episode_h1_count OR ";
    sql += "entry_count <> MIN(min_episode_h1_count, 3) OR ";
    sql += "confirmation1_count <> 1 OR ";
    sql += "confirmation2_count <> CASE WHEN min_episode_h1_count >= 2 ";
    sql += "THEN 1 ELSE 0 END OR ";
    sql += "confirmation3_count <> CASE WHEN min_episode_h1_count >= 3 ";
    sql += "THEN 1 ELSE 0 END OR end_count <> 1 OR symbol_count <> 1 ";
    sql += "OR side_count <> 1))";

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseBind(requestHandle, 0, fromRunInfo.id)) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    long entryCount = 0;
    long eligibleEntryCount = 0;
    long outcomeCount = 0;
    long calculatedCount = 0;
    long failedCount = 0;
    long incompleteEntryCount = 0;
    long metadataMismatchCount = 0;
    long priceModelCount = 0;
    string outcomePriceModel = "";
    long invalidEpisodeCount = 0;
    bool isRead = DatabaseColumnLong(requestHandle, 0, entryCount);

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 1, eligibleEntryCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 2, outcomeCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 3, calculatedCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 4, failedCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 5, incompleteEntryCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 6, metadataMismatchCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 7, priceModelCount);
    }
    if (isRead) {
        isRead = DatabaseColumnText(requestHandle, 8, outcomePriceModel);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 9, invalidEpisodeCount);
    }

    int columnErrorCode = GetLastError();
    DatabaseFinalize(requestHandle);

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumn read failed. error=%d", columnErrorCode)
        );

        return false;
    }

    bool isConsistent = entryCount == fromRunInfo.totalEntryCount
        && eligibleEntryCount == fromRunInfo.researchEligibleEntryCount
        && outcomeCount == fromRunInfo.totalOutcomeCount
        && calculatedCount == fromRunInfo.calculatedOutcomeCount
        && failedCount == fromRunInfo.failedOutcomeCount
        && incompleteEntryCount == 0
        && metadataMismatchCount == 0
        && priceModelCount == 1
        && outcomePriceModel != ""
        && invalidEpisodeCount == 0;

    if (!isConsistent) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Outcome Run data mismatch. entries=%I64d/%I64d eligible=%I64d/%I64d outcomes=%I64d/%I64d calculated=%I64d/%I64d failed=%I64d/%I64d incomplete=%I64d metadata=%I64d priceModels=%I64d invalidEpisodes=%I64d",
                entryCount,
                fromRunInfo.totalEntryCount,
                eligibleEntryCount,
                fromRunInfo.researchEligibleEntryCount,
                outcomeCount,
                fromRunInfo.totalOutcomeCount,
                calculatedCount,
                fromRunInfo.calculatedOutcomeCount,
                failedCount,
                fromRunInfo.failedOutcomeCount,
                incompleteEntryCount,
                metadataMismatchCount,
                priceModelCount,
                invalidEpisodeCount
            )
        );

        return false;
    }

    fromRunInfo.outcomePriceModel = outcomePriceModel;

    return true;
}

/**
 * Episode明細SQLへ1 Leg分の列を追加する。
 *
 * @param fromEntryAlias Entry別名。
 * @param fromOutcomeAlias Outcome別名。
 * @param fromSql 追加先SQL。
 */
void appendComparisonLegSelectSql(
    const string fromEntryAlias,
    const string fromOutcomeAlias,
    string &fromSql
) {
    fromSql += " CASE WHEN " + fromEntryAlias;
    fromSql += ".id IS NULL THEN 0 ELSE 1 END,";
    fromSql += " COALESCE(" + fromEntryAlias + ".id, 0),";
    fromSql += " COALESCE(" + fromEntryAlias;
    fromSql += ".confirmation_observation_id, 0),";
    fromSql += " COALESCE(" + fromEntryAlias;
    fromSql += ".confirmation_jst_time, 0),";
    fromSql += " COALESCE(" + fromEntryAlias + ".entry_jst_time, 0),";
    fromSql += " COALESCE(" + fromEntryAlias + ".spread_pips, 0.0),";
    fromSql += " COALESCE(" + fromEntryAlias;
    fromSql += ".is_research_eligible, 0),";
    fromSql += " COALESCE(" + fromEntryAlias + ".eligibility_status, ''),";
    fromSql += " COALESCE(" + fromOutcomeAlias + ".is_calculated, 0),";
    fromSql += " COALESCE(" + fromOutcomeAlias + ".data_status, ''),";
    fromSql += " COALESCE(" + fromOutcomeAlias;
    fromSql += ".gross_profit_pips, 0.0),";
    fromSql += " COALESCE(" + fromOutcomeAlias;
    fromSql += ".net_profit_pips, 0.0),";
    fromSql += " COALESCE(" + fromOutcomeAlias;
    fromSql += ".gross_profit_atr, 0.0),";
    fromSql += " COALESCE(" + fromOutcomeAlias;
    fromSql += ".net_profit_atr, 0.0),";
    fromSql += " COALESCE(" + fromOutcomeAlias + ".mfe_pips, 0.0),";
    fromSql += " COALESCE(" + fromOutcomeAlias + ".mae_pips, 0.0),";
    fromSql += " COALESCE(" + fromOutcomeAlias;
    fromSql += ".max_profit_h1_bars, 0)";
}

/**
 * Episode明細取得SQLを構築する。
 *
 * @return 同じEpisodeの1／2／3本確認を横持ちするSQL。
 */
string buildComparisonEpisodeSql() {
    string sql = "SELECT e1.signal_start_observation_id,";
    sql += " e1.signal_end_observation_id, e1.symbol_name, e1.side,";
    sql += " e1.episode_h1_count, e1.signal_start_time,";
    sql += " e1.signal_start_jst_time, e1.is_left_censored,";
    sql += " e1.is_right_censored, e1.has_data_gap_before,";
    sql += " e1.has_data_gap_after, o1.horizon_h1_bars,";
    appendComparisonLegSelectSql("e1", "o1", sql);
    sql += ",";
    appendComparisonLegSelectSql("e2", "o2", sql);
    sql += ",";
    appendComparisonLegSelectSql("e3", "o3", sql);
    sql += " FROM zigzag_elliot_h1_study_entries AS e1 ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e2 ";
    sql += "ON e2.outcome_run_id = e1.outcome_run_id ";
    sql += "AND e2.signal_start_observation_id ";
    sql += "= e1.signal_start_observation_id ";
    sql += "AND e2.confirmation_h1_count = 2 ";
    sql += "LEFT JOIN zigzag_elliot_h1_study_entries AS e3 ";
    sql += "ON e3.outcome_run_id = e1.outcome_run_id ";
    sql += "AND e3.signal_start_observation_id ";
    sql += "= e1.signal_start_observation_id ";
    sql += "AND e3.confirmation_h1_count = 3 ";
    sql += "JOIN zigzag_elliot_h1_study_outcomes AS o1 ";
    sql += "ON o1.entry_id = e1.id ";
    sql += "JOIN zigzag_elliot_h1_study_outcomes AS o2 ";
    sql += "ON o2.entry_id = e2.id ";
    sql += "AND o2.horizon_h1_bars = o1.horizon_h1_bars ";
    sql += "LEFT JOIN zigzag_elliot_h1_study_outcomes AS o3 ";
    sql += "ON o3.entry_id = e3.id ";
    sql += "AND o3.horizon_h1_bars = o1.horizon_h1_bars ";
    sql += "WHERE e1.outcome_run_id = ?1 ";
    sql += "AND e1.confirmation_h1_count = 1 ";
    sql += "ORDER BY e1.signal_start_jst_time ASC,";
    sql += " e1.symbol_name ASC, o1.horizon_h1_bars ASC";

    return sql;
}

/**
 * SQL現在行から1 Leg分を読み取る。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromColumnIndex 読取開始列。読取後は次列へ進める。
 * @param fromLeg 読取先。
 * @return 全列を読み取れた場合true。
 */
bool readComparisonLeg(
    const int fromRequestHandle,
    int &fromColumnIndex,
    ZigZagElliotH1StudyComparisonLeg &fromLeg
) {
    fromLeg.reset();
    int isPresentValue = 0;
    long confirmationJstTimeValue = 0;
    long entryJstTimeValue = 0;
    bool isRead = DatabaseColumnInteger(
        fromRequestHandle,
        fromColumnIndex++,
        isPresentValue
    );

    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.entryId
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.confirmationObservationId
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            fromColumnIndex++,
            confirmationJstTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            fromColumnIndex++,
            entryJstTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.spreadPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.isResearchEligible
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.eligibilityStatus
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.isCalculated
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.dataStatus
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.grossProfitPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.netProfitPips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.grossProfitAtr
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.netProfitAtr
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.mfePips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.maePips
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            fromColumnIndex++,
            fromLeg.maxProfitH1Bars
        );
    }

    fromLeg.isPresent = isPresentValue == 1;
    fromLeg.confirmationJstTime = (datetime)confirmationJstTimeValue;
    fromLeg.entryJstTime = (datetime)entryJstTimeValue;

    return isRead;
}

/**
 * SQL現在行からEpisode明細を読み取る。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromRow 読取先。
 * @param fromLogger ロガー。
 * @return 全列を読み取れた場合true。
 */
bool readComparisonEpisodeRow(
    const int fromRequestHandle,
    ZigZagElliotH1StudyComparisonEpisodeRow &fromRow,
    Logger &fromLogger
) {
    fromRow.reset();
    int columnIndex = 0;
    long signalStartTimeValue = 0;
    long signalStartJstTimeValue = 0;
    bool isRead = DatabaseColumnLong(
        fromRequestHandle,
        columnIndex++,
        fromRow.signalStartObservationId
    );

    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            columnIndex++,
            fromRow.signalEndObservationId
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            columnIndex++,
            fromRow.symbolName
        );
    }
    if (isRead) {
        isRead = DatabaseColumnText(
            fromRequestHandle,
            columnIndex++,
            fromRow.side
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            columnIndex++,
            fromRow.episodeH1Count
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            columnIndex++,
            signalStartTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            fromRequestHandle,
            columnIndex++,
            signalStartJstTimeValue
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            columnIndex++,
            fromRow.isLeftCensored
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            columnIndex++,
            fromRow.isRightCensored
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            columnIndex++,
            fromRow.hasDataGapBefore
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            columnIndex++,
            fromRow.hasDataGapAfter
        );
    }
    if (isRead) {
        isRead = DatabaseColumnInteger(
            fromRequestHandle,
            columnIndex++,
            fromRow.horizonH1Bars
        );
    }
    if (isRead) {
        isRead = readComparisonLeg(
            fromRequestHandle,
            columnIndex,
            fromRow.leg1
        );
    }
    if (isRead) {
        isRead = readComparisonLeg(
            fromRequestHandle,
            columnIndex,
            fromRow.leg2
        );
    }
    if (isRead) {
        isRead = readComparisonLeg(
            fromRequestHandle,
            columnIndex,
            fromRow.leg3
        );
    }

    if (!isRead || columnIndex != 63) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Episode DatabaseColumn read failed. column=%d error=%d",
                columnIndex,
                GetLastError()
            )
        );

        return false;
    }

    fromRow.signalStartTime = (datetime)signalStartTimeValue;
    fromRow.signalStartJstTime = (datetime)signalStartJstTimeValue;
    finalizeComparisonEpisodeRow(fromRow);

    return true;
}

/**
 * Episode明細の期待行数を取得する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromExpectedCount 期待行数。
 * @param fromLogger ロガー。
 * @return 取得できた場合true。
 */
bool findComparisonExpectedEpisodeRowCount(
    const int fromDatabaseHandle,
    const long fromRunId,
    long &fromExpectedCount,
    Logger &fromLogger
) {
    fromExpectedCount = 0;
    string sql = "SELECT COUNT(*) * 4 FROM ";
    sql += "zigzag_elliot_h1_study_entries ";
    sql += "WHERE outcome_run_id = ?1 AND confirmation_h1_count = 2";
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseBind(requestHandle, 0, fromRunId)
            || !DatabaseRead(requestHandle)
            || !DatabaseColumnLong(requestHandle, 0, fromExpectedCount)) {
        int errorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("Episode row count read failed. error=%d", errorCode)
        );

        return false;
    }

    DatabaseFinalize(requestHandle);

    return fromExpectedCount > 0;
}

/**
 * 任意double値をCSV文字列へ変換する。
 *
 * @param fromValue 数値。
 * @param fromIsAvailable 利用可能な場合true。
 * @param fromDigits 小数桁数。
 * @return 利用不能時は空文字、それ以外は数値文字列。
 */
string formatComparisonOptionalDouble(
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
 * 任意int値をCSV文字列へ変換する。
 *
 * @param fromValue 数値。
 * @param fromIsAvailable 利用可能な場合true。
 * @return 利用不能時は空文字、それ以外は数値文字列。
 */
string formatComparisonOptionalInt(
    const int fromValue,
    const bool fromIsAvailable
) {
    if (!fromIsAvailable) {
        return "";
    }

    return IntegerToString(fromValue);
}

/**
 * 任意long値をCSV文字列へ変換する。
 *
 * @param fromValue 数値。
 * @param fromIsAvailable 利用可能な場合true。
 * @return 利用不能時は空文字、それ以外は数値文字列。
 */
string formatComparisonOptionalLong(
    const long fromValue,
    const bool fromIsAvailable
) {
    if (!fromIsAvailable) {
        return "";
    }

    return StringFormat("%I64d", fromValue);
}

/**
 * 任意文字列をCSV値へ変換する。
 *
 * @param fromValue 文字列。
 * @param fromIsAvailable 利用可能な場合true。
 * @return 利用不能時は空文字、それ以外は元の文字列。
 */
string formatComparisonOptionalText(
    const string fromValue,
    const bool fromIsAvailable
) {
    if (!fromIsAvailable) {
        return "";
    }

    return fromValue;
}

/**
 * 任意日時をCSV文字列へ変換する。
 *
 * @param fromValue 日時。
 * @param fromIsAvailable 利用可能な場合true。
 * @return 利用不能時は空文字、それ以外は日時文字列。
 */
string formatComparisonOptionalDateTime(
    const datetime fromValue,
    const bool fromIsAvailable
) {
    if (!fromIsAvailable || fromValue <= 0) {
        return "";
    }

    return TimeToString(fromValue, TIME_DATE | TIME_SECONDS);
}

/**
 * 共通メタデータのCSVヘッダーを追加する。
 *
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonCommonHeaderValues(
    string &fromValues[],
    int &fromIndex
) {
    fromValues[fromIndex++] = "csv_schema_version";
    fromValues[fromIndex++] = "outcome_database_file_name";
    fromValues[fromIndex++] = "outcome_run_id";
    fromValues[fromIndex++] = "run_key";
    fromValues[fromIndex++] = "source_database_file_name";
    fromValues[fromIndex++] = "source_run_id";
    fromValues[fromIndex++] = "source_run_uid";
    fromValues[fromIndex++] = "study_from_jst_time";
    fromValues[fromIndex++] = "study_to_jst_time";
    fromValues[fromIndex++] = "signal_rule_version";
    fromValues[fromIndex++] = "entry_price_model";
    fromValues[fromIndex++] = "outcome_price_model";
    fromValues[fromIndex++] = "spread_model";
    fromValues[fromIndex++] = "evaluation_version";
    fromValues[fromIndex++] = "horizons_text";
    fromValues[fromIndex++] = "profit_zero_epsilon_pips";
}

/**
 * 共通メタデータのCSV値を追加する。
 *
 * @param fromSchemaVersion CSVスキーマバージョン。
 * @param fromRunInfo Outcome Run情報。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonCommonRowValues(
    const string fromSchemaVersion,
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    string &fromValues[],
    int &fromIndex
) {
    fromValues[fromIndex++] = fromSchemaVersion;
    fromValues[fromIndex++] = outcomeDatabaseFileName;
    fromValues[fromIndex++] = StringFormat("%I64d", fromRunInfo.id);
    fromValues[fromIndex++] = fromRunInfo.runKey;
    fromValues[fromIndex++] = fromRunInfo.sourceDatabaseFileName;
    fromValues[fromIndex++] = StringFormat(
        "%I64d",
        fromRunInfo.sourceRunId
    );
    fromValues[fromIndex++] = fromRunInfo.sourceRunUid;
    fromValues[fromIndex++] = TimeToString(
        fromRunInfo.studyFromJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[fromIndex++] = TimeToString(
        fromRunInfo.studyToJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[fromIndex++] = fromRunInfo.signalRuleVersion;
    fromValues[fromIndex++] = fromRunInfo.entryPriceModel;
    fromValues[fromIndex++] = fromRunInfo.outcomePriceModel;
    fromValues[fromIndex++] = fromRunInfo.spreadModel;
    fromValues[fromIndex++] = fromRunInfo.evaluationVersion;
    fromValues[fromIndex++] = fromRunInfo.horizonsText;
    fromValues[fromIndex++] = DoubleToString(comparisonEpsilonPips, 8);
}

/**
 * 1 Leg分のEpisode明細ヘッダーを追加する。
 *
 * @param fromPrefix 列名Prefix。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonEpisodeLegHeaderValues(
    const string fromPrefix,
    string &fromValues[],
    int &fromIndex
) {
    fromValues[fromIndex++] = fromPrefix + "_is_present";
    fromValues[fromIndex++] = fromPrefix + "_entry_id";
    fromValues[fromIndex++] = fromPrefix + "_confirmation_observation_id";
    fromValues[fromIndex++] = fromPrefix + "_confirmation_jst_time";
    fromValues[fromIndex++] = fromPrefix + "_entry_jst_time";
    fromValues[fromIndex++] = fromPrefix + "_entry_spread_pips";
    fromValues[fromIndex++] = fromPrefix + "_is_research_eligible";
    fromValues[fromIndex++] = fromPrefix + "_eligibility_status";
    fromValues[fromIndex++] = fromPrefix + "_is_calculated";
    fromValues[fromIndex++] = fromPrefix + "_data_status";
    fromValues[fromIndex++] = fromPrefix + "_gross_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_net_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_gross_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_net_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_mfe_pips";
    fromValues[fromIndex++] = fromPrefix + "_mae_pips";
    fromValues[fromIndex++] = fromPrefix + "_max_profit_h1_bars";
}

/**
 * 1 Leg分のEpisode明細値を追加する。
 *
 * @param fromLeg 出力対象Leg。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonEpisodeLegRowValues(
    ZigZagElliotH1StudyComparisonLeg &fromLeg,
    string &fromValues[],
    int &fromIndex
) {
    bool hasOutcome = fromLeg.isPresent && fromLeg.isCalculated == 1;
    fromValues[fromIndex++] = IntegerToString((int)fromLeg.isPresent);
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromLeg.entryId,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromLeg.confirmationObservationId,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalDateTime(
        fromLeg.confirmationJstTime,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalDateTime(
        fromLeg.entryJstTime,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromLeg.spreadPips,
        fromLeg.isPresent,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalInt(
        fromLeg.isResearchEligible,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalText(
        fromLeg.eligibilityStatus,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalInt(
        fromLeg.isCalculated,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalText(
        fromLeg.dataStatus,
        fromLeg.isPresent
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromLeg.grossProfitPips,
        hasOutcome,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromLeg.netProfitPips,
        hasOutcome,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromLeg.grossProfitAtr,
        hasOutcome,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromLeg.netProfitAtr,
        hasOutcome,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromLeg.mfePips,
        hasOutcome,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromLeg.maePips,
        hasOutcome,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalInt(
        fromLeg.maxProfitH1Bars,
        hasOutcome
    );
}

/**
 * 1差分分のEpisode明細ヘッダーを追加する。
 *
 * @param fromPrefix 列名Prefix。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonEpisodeDeltaHeaderValues(
    const string fromPrefix,
    string &fromValues[],
    int &fromIndex
) {
    fromValues[fromIndex++] = fromPrefix + "_is_available";
    fromValues[fromIndex++] = fromPrefix + "_gross_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_net_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_gross_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_net_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_spread_reduction_pips";
    fromValues[fromIndex++] = fromPrefix + "_mfe_improvement_pips";
    fromValues[fromIndex++] = fromPrefix + "_mae_reduction_pips";
    fromValues[fromIndex++] = fromPrefix
        + "_is_max_profit_speedup_available";
    fromValues[fromIndex++] = fromPrefix + "_max_profit_speedup_h1_bars";
    fromValues[fromIndex++] = fromPrefix + "_preference";
    fromValues[fromIndex++] = fromPrefix + "_transition";
}

/**
 * 1差分分のEpisode明細値を追加する。
 *
 * @param fromDelta 出力対象差分。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonEpisodeDeltaRowValues(
    ZigZagElliotH1StudyComparisonDelta &fromDelta,
    string &fromValues[],
    int &fromIndex
) {
    fromValues[fromIndex++] = IntegerToString((int)fromDelta.isAvailable);
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromDelta.grossProfitPips,
        fromDelta.isAvailable,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromDelta.netProfitPips,
        fromDelta.isAvailable,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromDelta.grossProfitAtr,
        fromDelta.isAvailable,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromDelta.netProfitAtr,
        fromDelta.isAvailable,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromDelta.spreadReductionPips,
        fromDelta.isAvailable,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromDelta.mfeImprovementPips,
        fromDelta.isAvailable,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromDelta.maeReductionPips,
        fromDelta.isAvailable,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalInt(
        (int)fromDelta.isMaxProfitSpeedupAvailable,
        fromDelta.isAvailable
    );
    fromValues[fromIndex++] = formatComparisonOptionalInt(
        fromDelta.maxProfitSpeedupH1Bars,
        fromDelta.isAvailable && fromDelta.isMaxProfitSpeedupAvailable
    );
    fromValues[fromIndex++] = formatComparisonOptionalText(
        fromDelta.preference,
        fromDelta.isAvailable
    );
    fromValues[fromIndex++] = formatComparisonOptionalText(
        fromDelta.transition,
        fromDelta.isAvailable
    );
}

/**
 * Episode明細CSVヘッダーを構築する。
 *
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setComparisonEpisodeHeaderValues(
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, comparisonEpisodeCsvFieldCount);
    int index = 0;
    appendComparisonCommonHeaderValues(fromValues, index);
    fromValues[index++] = "episode_key";
    fromValues[index++] = "signal_start_observation_id";
    fromValues[index++] = "signal_end_observation_id";
    fromValues[index++] = "symbol";
    fromValues[index++] = "side";
    fromValues[index++] = "episode_h1_count";
    fromValues[index++] = "signal_start_time";
    fromValues[index++] = "signal_start_jst_time";
    fromValues[index++] = "is_left_censored";
    fromValues[index++] = "is_right_censored";
    fromValues[index++] = "has_data_gap_before";
    fromValues[index++] = "has_data_gap_after";
    fromValues[index++] = "horizon_h1_bars";
    fromValues[index++] = "pair_is_research_eligible";
    fromValues[index++] = "pair_is_calculated";
    fromValues[index++] = "pair_future_h1_gap";
    fromValues[index++] = "pair_comparison_status";
    fromValues[index++] = "triple_is_applicable";
    fromValues[index++] = "triple_is_research_eligible";
    fromValues[index++] = "triple_is_calculated";
    fromValues[index++] = "triple_future_h1_gap";
    fromValues[index++] = "triple_comparison_status";
    appendComparisonEpisodeLegHeaderValues(
        "confirmation_1",
        fromValues,
        index
    );
    appendComparisonEpisodeLegHeaderValues(
        "confirmation_2",
        fromValues,
        index
    );
    appendComparisonEpisodeLegHeaderValues(
        "confirmation_3",
        fromValues,
        index
    );
    appendComparisonEpisodeDeltaHeaderValues("delta_2_minus_1", fromValues, index);
    appendComparisonEpisodeDeltaHeaderValues("delta_3_minus_1", fromValues, index);
    appendComparisonEpisodeDeltaHeaderValues("delta_3_minus_2", fromValues, index);

    if (index == comparisonEpisodeCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Episode CSV header field count mismatch. expected=%d actual=%d",
            comparisonEpisodeCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * Episode明細CSV行を構築する。
 *
 * @param fromRunInfo Outcome Run情報。
 * @param fromRow Episode明細。
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setComparisonEpisodeRowValues(
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    ZigZagElliotH1StudyComparisonEpisodeRow &fromRow,
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, comparisonEpisodeCsvFieldCount);
    int index = 0;
    appendComparisonCommonRowValues(
        comparisonEpisodeCsvSchemaVersion,
        fromRunInfo,
        fromValues,
        index
    );
    fromValues[index++] = StringFormat(
        "%I64d:%I64d",
        fromRunInfo.id,
        fromRow.signalStartObservationId
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.signalStartObservationId
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.signalEndObservationId
    );
    fromValues[index++] = fromRow.symbolName;
    fromValues[index++] = fromRow.side;
    fromValues[index++] = IntegerToString(fromRow.episodeH1Count);
    fromValues[index++] = TimeToString(
        fromRow.signalStartTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[index++] = TimeToString(
        fromRow.signalStartJstTime,
        TIME_DATE | TIME_SECONDS
    );
    fromValues[index++] = IntegerToString(fromRow.isLeftCensored);
    fromValues[index++] = IntegerToString(fromRow.isRightCensored);
    fromValues[index++] = IntegerToString(fromRow.hasDataGapBefore);
    fromValues[index++] = IntegerToString(fromRow.hasDataGapAfter);
    fromValues[index++] = IntegerToString(fromRow.horizonH1Bars);
    fromValues[index++] = IntegerToString((int)fromRow.isPairResearchEligible);
    fromValues[index++] = IntegerToString((int)fromRow.isPairCalculated);
    fromValues[index++] = IntegerToString((int)fromRow.hasPairFutureH1Gap);
    fromValues[index++] = fromRow.pairComparisonStatus;
    fromValues[index++] = IntegerToString((int)fromRow.isTripleApplicable);
    fromValues[index++] = IntegerToString((int)fromRow.isTripleResearchEligible);
    fromValues[index++] = IntegerToString((int)fromRow.isTripleCalculated);
    fromValues[index++] = IntegerToString((int)fromRow.hasTripleFutureH1Gap);
    fromValues[index++] = fromRow.tripleComparisonStatus;
    appendComparisonEpisodeLegRowValues(fromRow.leg1, fromValues, index);
    appendComparisonEpisodeLegRowValues(fromRow.leg2, fromValues, index);
    appendComparisonEpisodeLegRowValues(fromRow.leg3, fromValues, index);
    appendComparisonEpisodeDeltaRowValues(fromRow.delta21, fromValues, index);
    appendComparisonEpisodeDeltaRowValues(fromRow.delta31, fromValues, index);
    appendComparisonEpisodeDeltaRowValues(fromRow.delta32, fromValues, index);

    if (index == comparisonEpisodeCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Episode CSV data field count mismatch. expected=%d actual=%d",
            comparisonEpisodeCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * Episode明細をCSVへ逐次上書き出力する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunInfo Outcome Run情報。
 * @param fromWrittenCount 出力行数。
 * @param fromLogger ロガー。
 * @return 全行を出力できた場合true。
 */
bool writeComparisonEpisodeCsv(
    const int fromDatabaseHandle,
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    long &fromWrittenCount,
    Logger &fromLogger
) {
    fromWrittenCount = 0;
    long expectedCount = 0;

    if (!findComparisonExpectedEpisodeRowCount(
            fromDatabaseHandle,
            fromRunInfo.id,
            expectedCount,
            fromLogger
        )) {
        return false;
    }

    string headerValues[];

    if (!setComparisonEpisodeHeaderValues(headerValues, fromLogger)) {
        return false;
    }

    string fileName = getComparisonEpisodeOutputFileName(fromRunInfo.id);
    CsvFileWriter fileWriter(
        fileName,
        outputUseCommonFolder,
        ",",
        false,
        true,
        "",
        CSV_FILE_WRITE_MODE_OVERWRITE
    );

    if (!fileWriter.writeHeader(headerValues, false)) {
        fileWriter.close();
        fromLogger.error(
            __FUNCTION__,
            "Episode CSV header write failed. file=" + fileName
        );

        return false;
    }

    ResetLastError();
    int requestHandle = DatabasePrepare(
        fromDatabaseHandle,
        buildComparisonEpisodeSql()
    );

    if (requestHandle == INVALID_HANDLE) {
        fileWriter.close();
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    ResetLastError();

    if (!DatabaseBind(requestHandle, 0, fromRunInfo.id)) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fileWriter.close();
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    while (true) {
        if (IsStopped()) {
            DatabaseFinalize(requestHandle);
            fileWriter.close();
            fromLogger.error(__FUNCTION__, "Episode export was stopped.");

            return false;
        }

        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fileWriter.close();

            if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat(
                        "DatabaseRead failed. error=%d",
                        readErrorCode
                    )
                );

                return false;
            }

            break;
        }

        ZigZagElliotH1StudyComparisonEpisodeRow row;
        string rowValues[];

        if (!readComparisonEpisodeRow(requestHandle, row, fromLogger)
                || !setComparisonEpisodeRowValues(
                    fromRunInfo,
                    row,
                    rowValues,
                    fromLogger
                )
                || !fileWriter.writeRow(rowValues)) {
            DatabaseFinalize(requestHandle);
            fileWriter.close();
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Episode CSV row write failed. row=%I64d",
                    fromWrittenCount
                )
            );

            return false;
        }

        fromWrittenCount++;
    }

    if (fromWrittenCount != expectedCount) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Episode CSV row count mismatch. expected=%I64d actual=%I64d",
                expectedCount,
                fromWrittenCount
            )
        );

        return false;
    }

    return true;
}

/**
 * CohortのEntryおよびOutcome結合SQLを構築する。
 *
 * @param fromCohortType Cohort名。
 * @return FROM句以降の共通SQL。対象外は空文字。
 */
string buildComparisonSummaryBaseSql(const string fromCohortType) {
    string sql = " FROM zigzag_elliot_h1_study_entries AS e1 ";
    sql += "JOIN zigzag_elliot_h1_study_entries AS e2 ";
    sql += "ON e2.outcome_run_id = e1.outcome_run_id ";
    sql += "AND e2.signal_start_observation_id ";
    sql += "= e1.signal_start_observation_id ";
    sql += "AND e2.confirmation_h1_count = 2 ";

    if (fromCohortType == comparisonTripleCohort) {
        sql += "JOIN zigzag_elliot_h1_study_entries AS e3 ";
        sql += "ON e3.outcome_run_id = e1.outcome_run_id ";
        sql += "AND e3.signal_start_observation_id ";
        sql += "= e1.signal_start_observation_id ";
        sql += "AND e3.confirmation_h1_count = 3 ";
    }

    sql += "JOIN zigzag_elliot_h1_study_outcomes AS o1 ";
    sql += "ON o1.entry_id = e1.id ";
    sql += "JOIN zigzag_elliot_h1_study_outcomes AS o2 ";
    sql += "ON o2.entry_id = e2.id ";
    sql += "AND o2.horizon_h1_bars = o1.horizon_h1_bars ";

    if (fromCohortType == comparisonTripleCohort) {
        sql += "JOIN zigzag_elliot_h1_study_outcomes AS o3 ";
        sql += "ON o3.entry_id = e3.id ";
        sql += "AND o3.horizon_h1_bars = o1.horizon_h1_bars ";
    }

    sql += "WHERE e1.outcome_run_id = ?1 ";
    sql += "AND e1.confirmation_h1_count = 1 ";
    sql += "AND o1.horizon_h1_bars = ?2 ";
    sql += "AND (?3 = 'ALL' OR e1.side = ?3) ";

    return sql;
}

/**
 * Cohortの全必要Entryが研究対象となるSQL条件を取得する。
 *
 * @param fromCohortType Cohort名。
 * @return SQL条件。
 */
string getComparisonEligibleCondition(const string fromCohortType) {
    string condition = "e1.is_research_eligible = 1 ";
    condition += "AND e2.is_research_eligible = 1";

    if (fromCohortType == comparisonTripleCohort) {
        condition += " AND e3.is_research_eligible = 1";
    }

    return condition;
}

/**
 * Cohortの全必要Outcomeが計算済みとなるSQL条件を取得する。
 *
 * @param fromCohortType Cohort名。
 * @return SQL条件。
 */
string getComparisonCalculatedCondition(const string fromCohortType) {
    string condition = "o1.is_calculated = 1 AND o2.is_calculated = 1";

    if (fromCohortType == comparisonTripleCohort) {
        condition += " AND o3.is_calculated = 1";
    }

    return condition;
}

/**
 * Cohortの必要Outcomeに将来H1 GapがあるSQL条件を取得する。
 *
 * @param fromCohortType Cohort名。
 * @return SQL条件。
 */
string getComparisonFutureGapCondition(const string fromCohortType) {
    string condition = "(o1.data_status = 'FUTURE_H1_GAP' ";
    condition += "OR o2.data_status = 'FUTURE_H1_GAP'";

    if (fromCohortType == comparisonTripleCohort) {
        condition += " OR o3.data_status = 'FUTURE_H1_GAP'";
    }

    condition += ")";

    return condition;
}

/**
 * 集計SQLの共通パラメーターを設定する。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromHorizonH1Bars 評価H1本数。
 * @param fromSideScope 方向範囲。
 * @param fromLogger ロガー。
 * @param fromMethodName 呼び出し元メソッド名。
 * @return 設定できた場合true。
 */
bool bindComparisonSummaryInputs(
    const int fromRequestHandle,
    const long fromRunId,
    const int fromHorizonH1Bars,
    const string fromSideScope,
    Logger &fromLogger,
    const string fromMethodName
) {
    ResetLastError();
    bool isBound = DatabaseBind(fromRequestHandle, 0, fromRunId);

    if (isBound) {
        isBound = DatabaseBind(fromRequestHandle, 1, fromHorizonH1Bars);
    }
    if (isBound) {
        isBound = DatabaseBind(fromRequestHandle, 2, fromSideScope);
    }

    if (isBound) {
        return true;
    }

    int errorCode = GetLastError();
    DatabaseFinalize(fromRequestHandle);
    fromLogger.error(
        fromMethodName,
        StringFormat("DatabaseBind failed. error=%d", errorCode)
    );

    return false;
}

/**
 * 1つのCohort・評価期間・方向範囲の母数を集計する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromRow 集計先。
 * @param fromLogger ロガー。
 * @return 集計できた場合true。
 */
bool aggregateComparisonSummaryCounts(
    const int fromDatabaseHandle,
    const long fromRunId,
    ZigZagElliotH1StudyComparisonSummaryRow &fromRow,
    Logger &fromLogger
) {
    string eligibleCondition = getComparisonEligibleCondition(
        fromRow.cohortType
    );
    string calculatedCondition = getComparisonCalculatedCondition(
        fromRow.cohortType
    );
    string futureGapCondition = getComparisonFutureGapCondition(
        fromRow.cohortType
    );
    string sql = "SELECT COUNT(*),";
    sql += " SUM(CASE WHEN " + eligibleCondition;
    sql += " THEN 1 ELSE 0 END),";
    sql += " SUM(CASE WHEN " + eligibleCondition + " AND ";
    sql += calculatedCondition + " THEN 1 ELSE 0 END),";
    sql += " SUM(CASE WHEN " + eligibleCondition + " AND NOT (";
    sql += calculatedCondition + ") AND " + futureGapCondition;
    sql += " THEN 1 ELSE 0 END)";
    sql += buildComparisonSummaryBaseSql(fromRow.cohortType);

    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    if (!bindComparisonSummaryInputs(
            requestHandle,
            fromRunId,
            fromRow.horizonH1Bars,
            fromRow.sideScope,
            fromLogger,
            __FUNCTION__
        )) {
        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    bool isRead = DatabaseColumnLong(
        requestHandle,
        0,
        fromRow.candidateEpisodeCount
    );

    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            1,
            fromRow.eligibleEpisodeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            2,
            fromRow.commonCalculatedEpisodeCount
        );
    }
    if (isRead) {
        isRead = DatabaseColumnLong(
            requestHandle,
            3,
            fromRow.futureH1GapEpisodeCount
        );
    }

    int columnErrorCode = GetLastError();
    DatabaseFinalize(requestHandle);

    if (!isRead) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseColumn read failed. error=%d", columnErrorCode)
        );

        return false;
    }

    fromRow.ineligibleEpisodeCount = fromRow.candidateEpisodeCount
        - fromRow.eligibleEpisodeCount;
    fromRow.failedEpisodeCount = fromRow.eligibleEpisodeCount
        - fromRow.commonCalculatedEpisodeCount;
    fromRow.otherFailureEpisodeCount = fromRow.failedEpisodeCount
        - fromRow.futureH1GapEpisodeCount;

    if (fromRow.eligibleEpisodeCount > 0) {
        fromRow.calculationCoveragePercent = 100.0
            * (double)fromRow.commonCalculatedEpisodeCount
            / (double)fromRow.eligibleEpisodeCount;
    }

    return fromRow.ineligibleEpisodeCount >= 0
        && fromRow.failedEpisodeCount >= 0
        && fromRow.otherFailureEpisodeCount >= 0;
}

/**
 * 確認本数に対応するEntry SQL別名を取得する。
 *
 * @param fromConfirmationH1Count 確認本数。
 * @return e1、e2またはe3。対象外は空文字。
 */
string getComparisonEntryAlias(const int fromConfirmationH1Count) {
    if (fromConfirmationH1Count == 1) {
        return "e1";
    }

    if (fromConfirmationH1Count == 2) {
        return "e2";
    }

    if (fromConfirmationH1Count == 3) {
        return "e3";
    }

    return "";
}

/**
 * 確認本数に対応するOutcome SQL別名を取得する。
 *
 * @param fromConfirmationH1Count 確認本数。
 * @return o1、o2またはo3。対象外は空文字。
 */
string getComparisonOutcomeAlias(const int fromConfirmationH1Count) {
    if (fromConfirmationH1Count == 1) {
        return "o1";
    }

    if (fromConfirmationH1Count == 2) {
        return "o2";
    }

    if (fromConfirmationH1Count == 3) {
        return "o3";
    }

    return "";
}

/**
 * SQL数値式を許容差内で0へ正規化する式へ変換する。
 *
 * @param fromExpression 元の数値式。
 * @return CASE式。
 */
string buildComparisonNormalizedSql(const string fromExpression) {
    return "CASE WHEN ABS(" + fromExpression
        + ") <= ?4 THEN 0.0 ELSE " + fromExpression + " END";
}

/**
 * 集計SQLへ許容差を含む全パラメーターを設定する。
 *
 * @param fromRequestHandle SQL要求ハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromHorizonH1Bars 評価H1本数。
 * @param fromSideScope 方向範囲。
 * @param fromLogger ロガー。
 * @param fromMethodName 呼び出し元メソッド名。
 * @return 設定できた場合true。
 */
bool bindComparisonStatisticsInputs(
    const int fromRequestHandle,
    const long fromRunId,
    const int fromHorizonH1Bars,
    const string fromSideScope,
    Logger &fromLogger,
    const string fromMethodName
) {
    ResetLastError();
    bool isBound = DatabaseBind(fromRequestHandle, 0, fromRunId);

    if (isBound) {
        isBound = DatabaseBind(fromRequestHandle, 1, fromHorizonH1Bars);
    }
    if (isBound) {
        isBound = DatabaseBind(fromRequestHandle, 2, fromSideScope);
    }
    if (isBound) {
        isBound = DatabaseBind(
            fromRequestHandle,
            3,
            comparisonEpsilonPips
        );
    }

    if (isBound) {
        return true;
    }

    int errorCode = GetLastError();
    DatabaseFinalize(fromRequestHandle);
    fromLogger.error(
        fromMethodName,
        StringFormat("DatabaseBind failed. error=%d", errorCode)
    );

    return false;
}

/**
 * 共通Cohort内の指定式の中央値を取得する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromRow 集計条件。
 * @param fromExpression 中央値対象SQL式。
 * @param fromOrderIdExpression 同値時の順序を確定するID式。
 * @param fromSampleCount 共通計算成功件数。
 * @param fromMedian 取得結果。
 * @param fromLogger ロガー。
 * @return 取得できた場合true。
 */
bool findComparisonMedian(
    const int fromDatabaseHandle,
    const long fromRunId,
    ZigZagElliotH1StudyComparisonSummaryRow &fromRow,
    const string fromExpression,
    const string fromOrderIdExpression,
    const long fromSampleCount,
    double &fromMedian,
    Logger &fromLogger
) {
    fromMedian = 0.0;

    if (fromSampleCount <= 0) {
        return true;
    }

    long limitCount = 1;
    long offsetCount = fromSampleCount / 2;

    if (fromSampleCount % 2 == 0) {
        limitCount = 2;
        offsetCount = fromSampleCount / 2 - 1;
    }

    string normalizedExpression = buildComparisonNormalizedSql(
        fromExpression
    );
    string sql = "SELECT " + normalizedExpression;
    sql += buildComparisonSummaryBaseSql(fromRow.cohortType);
    sql += "AND " + getComparisonEligibleCondition(fromRow.cohortType);
    sql += " AND " + getComparisonCalculatedCondition(fromRow.cohortType);
    sql += " ORDER BY " + normalizedExpression + " ASC,";
    sql += " " + fromOrderIdExpression + " ASC LIMIT ?5 OFFSET ?6";
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    if (!bindComparisonStatisticsInputs(
            requestHandle,
            fromRunId,
            fromRow.horizonH1Bars,
            fromRow.sideScope,
            fromLogger,
            __FUNCTION__
        )) {
        return false;
    }

    ResetLastError();
    bool isBound = DatabaseBind(requestHandle, 4, limitCount);

    if (isBound) {
        isBound = DatabaseBind(requestHandle, 5, offsetCount);
    }
    if (!isBound) {
        int bindErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseBind failed. error=%d", bindErrorCode)
        );

        return false;
    }

    double sum = 0.0;
    long readCount = 0;

    while (true) {
        ResetLastError();

        if (!DatabaseRead(requestHandle)) {
            int readErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);

            if (readErrorCode != ERR_DATABASE_NO_MORE_DATA) {
                fromLogger.error(
                    __FUNCTION__,
                    StringFormat("DatabaseRead failed. error=%d", readErrorCode)
                );

                return false;
            }

            break;
        }

        double value = 0.0;

        if (!DatabaseColumnDouble(requestHandle, 0, value)) {
            int columnErrorCode = GetLastError();
            DatabaseFinalize(requestHandle);
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "DatabaseColumn read failed. error=%d",
                    columnErrorCode
                )
            );

            return false;
        }

        sum += value;
        readCount++;
    }

    if (readCount != limitCount) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Median row count mismatch. expected=%I64d actual=%I64d",
                limitCount,
                readCount
            )
        );

        return false;
    }

    fromMedian = sum / (double)readCount;

    return true;
}

/**
 * 共通Cohortの1確認本数分の成績を集計する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromConfirmationH1Count 確認本数。
 * @param fromRow 集計条件。
 * @param fromSummary 集計先。
 * @param fromLogger ロガー。
 * @return 集計できた場合true。
 */
bool aggregateComparisonLegSummary(
    const int fromDatabaseHandle,
    const long fromRunId,
    const int fromConfirmationH1Count,
    ZigZagElliotH1StudyComparisonSummaryRow &fromRow,
    ZigZagElliotH1StudyComparisonLegSummary &fromSummary,
    Logger &fromLogger
) {
    fromSummary.reset();
    fromSummary.isApplicable = fromConfirmationH1Count
        <= fromRow.requiredConfirmationH1Count;

    if (!fromSummary.isApplicable) {
        return true;
    }

    string entryAlias = getComparisonEntryAlias(fromConfirmationH1Count);
    string outcomeAlias = getComparisonOutcomeAlias(
        fromConfirmationH1Count
    );
    string netExpression = outcomeAlias + ".net_profit_pips";
    string normalizedNetExpression = buildComparisonNormalizedSql(
        netExpression
    );
    string sql = "SELECT COUNT(*),";
    sql += " SUM(CASE WHEN " + netExpression + " > ?4";
    sql += " THEN 1 ELSE 0 END),";
    sql += " SUM(CASE WHEN " + netExpression + " < -?4";
    sql += " THEN 1 ELSE 0 END),";
    sql += " SUM(CASE WHEN ABS(" + netExpression + ") <= ?4";
    sql += " THEN 1 ELSE 0 END),";
    sql += " COALESCE(SUM(" + normalizedNetExpression + "), 0.0),";
    sql += " COALESCE(AVG(" + outcomeAlias + ".gross_profit_pips), 0.0),";
    sql += " COALESCE(AVG(" + normalizedNetExpression + "), 0.0),";
    sql += " COALESCE(SUM(CASE WHEN " + netExpression + " > ?4 THEN ";
    sql += netExpression + " ELSE 0.0 END), 0.0),";
    sql += " COALESCE(SUM(CASE WHEN " + netExpression + " < -?4 THEN -";
    sql += netExpression + " ELSE 0.0 END), 0.0),";
    sql += " COALESCE(AVG(" + outcomeAlias + ".mfe_pips), 0.0),";
    sql += " COALESCE(AVG(" + outcomeAlias + ".mae_pips), 0.0),";
    sql += " COALESCE(AVG(" + outcomeAlias + ".gross_profit_atr), 0.0),";
    sql += " COALESCE(AVG(" + outcomeAlias + ".net_profit_atr), 0.0),";
    sql += " COALESCE(AVG(" + entryAlias + ".spread_pips), 0.0),";
    sql += " COALESCE(AVG(" + outcomeAlias;
    sql += ".max_profit_h1_bars), 0.0)";
    sql += buildComparisonSummaryBaseSql(fromRow.cohortType);
    sql += "AND " + getComparisonEligibleCondition(fromRow.cohortType);
    sql += " AND " + getComparisonCalculatedCondition(fromRow.cohortType);
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    if (!bindComparisonStatisticsInputs(
            requestHandle,
            fromRunId,
            fromRow.horizonH1Bars,
            fromRow.sideScope,
            fromLogger,
            __FUNCTION__
        )) {
        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    long sampleCount = 0;
    bool isRead = DatabaseColumnLong(requestHandle, 0, sampleCount);

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 1, fromSummary.winningCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 2, fromSummary.losingCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 3, fromSummary.flatCount);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 4, fromSummary.netProfitSumPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 5, fromSummary.averageGrossProfitPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 6, fromSummary.averageNetProfitPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 7, fromSummary.winningNetProfitSumPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 8, fromSummary.losingNetProfitAbsSumPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 9, fromSummary.averageMfePips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 10, fromSummary.averageMaePips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 11, fromSummary.averageGrossProfitAtr);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 12, fromSummary.averageNetProfitAtr);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 13, fromSummary.averageEntrySpreadPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 14, fromSummary.averageMaxProfitH1Bars);
    }

    int columnErrorCode = GetLastError();
    DatabaseFinalize(requestHandle);

    if (!isRead
            || sampleCount != fromRow.commonCalculatedEpisodeCount
            || sampleCount != fromSummary.winningCount
                + fromSummary.losingCount + fromSummary.flatCount) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Leg summary mismatch. confirmation=%d sample=%I64d common=%I64d error=%d",
                fromConfirmationH1Count,
                sampleCount,
                fromRow.commonCalculatedEpisodeCount,
                columnErrorCode
            )
        );

        return false;
    }

    fromSummary.isStatisticsAvailable = sampleCount > 0;

    if (sampleCount > 0) {
        fromSummary.winRatePercent = 100.0
            * (double)fromSummary.winningCount / (double)sampleCount;
    }

    if (sampleCount <= 0) {
        fromSummary.profitFactorStatus = "NO_SAMPLE";
    } else if (fromSummary.losingNetProfitAbsSumPips > 0.0) {
        fromSummary.profitFactorStatus = "AVAILABLE";
        fromSummary.profitFactor = fromSummary.winningNetProfitSumPips
            / fromSummary.losingNetProfitAbsSumPips;
    } else if (fromSummary.winningNetProfitSumPips > 0.0) {
        fromSummary.profitFactorStatus = "INFINITE_NO_LOSS";
    } else {
        fromSummary.profitFactorStatus = "NO_VARIATION";
    }

    return findComparisonMedian(
        fromDatabaseHandle,
        fromRunId,
        fromRow,
        netExpression,
        outcomeAlias + ".id",
        sampleCount,
        fromSummary.medianNetProfitPips,
        fromLogger
    );
}

/**
 * 損益状態のSQL条件を構築する。
 *
 * @param fromExpression Spread控除後損益式。
 * @param fromState WIN、LOSSまたはFLAT。
 * @return SQL条件。対象外は常に偽の条件。
 */
string buildComparisonProfitStateCondition(
    const string fromExpression,
    const string fromState
) {
    if (fromState == "WIN") {
        return fromExpression + " > ?4";
    }

    if (fromState == "LOSS") {
        return fromExpression + " < -?4";
    }

    if (fromState == "FLAT") {
        return "ABS(" + fromExpression + ") <= ?4";
    }

    return "1 = 0";
}

/**
 * 1つの損益遷移件数列をSQLへ追加する。
 *
 * @param fromEarlierExpression 先行側損益式。
 * @param fromLaterExpression 待機側損益式。
 * @param fromEarlierState 先行側状態。
 * @param fromLaterState 待機側状態。
 * @param fromSql 追加先SQL。
 */
void appendComparisonTransitionSql(
    const string fromEarlierExpression,
    const string fromLaterExpression,
    const string fromEarlierState,
    const string fromLaterState,
    string &fromSql
) {
    fromSql += " SUM(CASE WHEN ";
    fromSql += buildComparisonProfitStateCondition(
        fromEarlierExpression,
        fromEarlierState
    );
    fromSql += " AND ";
    fromSql += buildComparisonProfitStateCondition(
        fromLaterExpression,
        fromLaterState
    );
    fromSql += " THEN 1 ELSE 0 END)";
}

/**
 * 共通Cohortの2確認タイミング間の差分を集計する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromEarlierConfirmationH1Count 先行側確認本数。
 * @param fromLaterConfirmationH1Count 待機側確認本数。
 * @param fromRow 集計条件。
 * @param fromSummary 集計先。
 * @param fromLogger ロガー。
 * @return 集計できた場合true。
 */
bool aggregateComparisonDeltaSummary(
    const int fromDatabaseHandle,
    const long fromRunId,
    const int fromEarlierConfirmationH1Count,
    const int fromLaterConfirmationH1Count,
    ZigZagElliotH1StudyComparisonSummaryRow &fromRow,
    ZigZagElliotH1StudyComparisonDeltaSummary &fromSummary,
    Logger &fromLogger
) {
    fromSummary.reset();
    fromSummary.isApplicable = fromLaterConfirmationH1Count
        <= fromRow.requiredConfirmationH1Count;

    if (!fromSummary.isApplicable) {
        return true;
    }

    string earlierEntryAlias = getComparisonEntryAlias(
        fromEarlierConfirmationH1Count
    );
    string laterEntryAlias = getComparisonEntryAlias(
        fromLaterConfirmationH1Count
    );
    string earlierOutcomeAlias = getComparisonOutcomeAlias(
        fromEarlierConfirmationH1Count
    );
    string laterOutcomeAlias = getComparisonOutcomeAlias(
        fromLaterConfirmationH1Count
    );
    string earlierNetExpression = earlierOutcomeAlias + ".net_profit_pips";
    string laterNetExpression = laterOutcomeAlias + ".net_profit_pips";
    string grossExpression = laterOutcomeAlias + ".gross_profit_pips - ";
    grossExpression += earlierOutcomeAlias + ".gross_profit_pips";
    string netExpression = laterNetExpression + " - " + earlierNetExpression;
    string grossAtrExpression = laterOutcomeAlias + ".gross_profit_atr - ";
    grossAtrExpression += earlierOutcomeAlias + ".gross_profit_atr";
    string netAtrExpression = laterOutcomeAlias + ".net_profit_atr - ";
    netAtrExpression += earlierOutcomeAlias + ".net_profit_atr";
    string spreadExpression = earlierEntryAlias + ".spread_pips - ";
    spreadExpression += laterEntryAlias + ".spread_pips";
    string mfeExpression = laterOutcomeAlias + ".mfe_pips - ";
    mfeExpression += earlierOutcomeAlias + ".mfe_pips";
    string maeExpression = earlierOutcomeAlias + ".mae_pips - ";
    maeExpression += laterOutcomeAlias + ".mae_pips";
    string speedupCondition = earlierOutcomeAlias + ".mfe_pips > ?4 ";
    speedupCondition += "AND " + laterOutcomeAlias + ".mfe_pips > ?4";
    string speedupExpression = earlierOutcomeAlias;
    speedupExpression += ".max_profit_h1_bars - ";
    speedupExpression += laterOutcomeAlias + ".max_profit_h1_bars";
    string normalizedNetExpression = buildComparisonNormalizedSql(
        netExpression
    );
    string sql = "SELECT COUNT(*),";
    sql += " SUM(CASE WHEN (" + netExpression + ") > ?4";
    sql += " THEN 1 ELSE 0 END),";
    sql += " SUM(CASE WHEN ABS(" + netExpression + ") <= ?4";
    sql += " THEN 1 ELSE 0 END),";
    sql += " SUM(CASE WHEN (" + netExpression + ") < -?4";
    sql += " THEN 1 ELSE 0 END),";
    sql += " COALESCE(AVG(" + buildComparisonNormalizedSql(grossExpression);
    sql += "), 0.0),";
    sql += " COALESCE(AVG(" + normalizedNetExpression + "), 0.0),";
    sql += " COALESCE(AVG(" + buildComparisonNormalizedSql(grossAtrExpression);
    sql += "), 0.0),";
    sql += " COALESCE(AVG(" + buildComparisonNormalizedSql(netAtrExpression);
    sql += "), 0.0),";
    sql += " COALESCE(AVG(" + buildComparisonNormalizedSql(spreadExpression);
    sql += "), 0.0),";
    sql += " COALESCE(AVG(" + buildComparisonNormalizedSql(mfeExpression);
    sql += "), 0.0),";
    sql += " COALESCE(AVG(" + buildComparisonNormalizedSql(maeExpression);
    sql += "), 0.0),";
    sql += " SUM(CASE WHEN " + speedupCondition + " THEN 1 ELSE 0 END),";
    sql += " COALESCE(AVG(CASE WHEN " + speedupCondition + " THEN ";
    sql += speedupExpression + " ELSE NULL END), 0.0),";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "WIN",
        "WIN",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "WIN",
        "FLAT",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "WIN",
        "LOSS",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "FLAT",
        "WIN",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "FLAT",
        "FLAT",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "FLAT",
        "LOSS",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "LOSS",
        "WIN",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "LOSS",
        "FLAT",
        sql
    );
    sql += ",";
    appendComparisonTransitionSql(
        earlierNetExpression,
        laterNetExpression,
        "LOSS",
        "LOSS",
        sql
    );
    sql += buildComparisonSummaryBaseSql(fromRow.cohortType);
    sql += "AND " + getComparisonEligibleCondition(fromRow.cohortType);
    sql += " AND " + getComparisonCalculatedCondition(fromRow.cohortType);
    ResetLastError();
    int requestHandle = DatabasePrepare(fromDatabaseHandle, sql);

    if (requestHandle == INVALID_HANDLE) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabasePrepare failed. error=%d", GetLastError())
        );

        return false;
    }

    if (!bindComparisonStatisticsInputs(
            requestHandle,
            fromRunId,
            fromRow.horizonH1Bars,
            fromRow.sideScope,
            fromLogger,
            __FUNCTION__
        )) {
        return false;
    }

    ResetLastError();

    if (!DatabaseRead(requestHandle)) {
        int readErrorCode = GetLastError();
        DatabaseFinalize(requestHandle);
        fromLogger.error(
            __FUNCTION__,
            StringFormat("DatabaseRead failed. error=%d", readErrorCode)
        );

        return false;
    }

    long sampleCount = 0;
    bool isRead = DatabaseColumnLong(requestHandle, 0, sampleCount);

    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 1, fromSummary.improvedCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 2, fromSummary.unchangedCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 3, fromSummary.worsenedCount);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 4, fromSummary.averageGrossProfitPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 5, fromSummary.averageNetProfitPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 6, fromSummary.averageGrossProfitAtr);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 7, fromSummary.averageNetProfitAtr);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 8, fromSummary.averageSpreadReductionPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 9, fromSummary.averageMfeImprovementPips);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 10, fromSummary.averageMaeReductionPips);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 11, fromSummary.maxProfitSpeedupComparableCount);
    }
    if (isRead) {
        isRead = DatabaseColumnDouble(requestHandle, 12, fromSummary.averageMaxProfitSpeedupH1Bars);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 13, fromSummary.winToWinCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 14, fromSummary.winToFlatCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 15, fromSummary.winToLossCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 16, fromSummary.flatToWinCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 17, fromSummary.flatToFlatCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 18, fromSummary.flatToLossCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 19, fromSummary.lossToWinCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 20, fromSummary.lossToFlatCount);
    }
    if (isRead) {
        isRead = DatabaseColumnLong(requestHandle, 21, fromSummary.lossToLossCount);
    }

    int columnErrorCode = GetLastError();
    DatabaseFinalize(requestHandle);
    long preferenceCount = fromSummary.improvedCount
        + fromSummary.unchangedCount + fromSummary.worsenedCount;
    long transitionCount = fromSummary.winToWinCount
        + fromSummary.winToFlatCount + fromSummary.winToLossCount
        + fromSummary.flatToWinCount + fromSummary.flatToFlatCount
        + fromSummary.flatToLossCount + fromSummary.lossToWinCount
        + fromSummary.lossToFlatCount + fromSummary.lossToLossCount;

    if (!isRead
            || sampleCount != fromRow.commonCalculatedEpisodeCount
            || preferenceCount != sampleCount
            || transitionCount != sampleCount
            || fromSummary.maxProfitSpeedupComparableCount > sampleCount) {
        fromLogger.error(
            __FUNCTION__,
            StringFormat(
                "Delta summary mismatch. from=%d to=%d sample=%I64d common=%I64d preference=%I64d transition=%I64d error=%d",
                fromEarlierConfirmationH1Count,
                fromLaterConfirmationH1Count,
                sampleCount,
                fromRow.commonCalculatedEpisodeCount,
                preferenceCount,
                transitionCount,
                columnErrorCode
            )
        );

        return false;
    }

    fromSummary.isStatisticsAvailable = sampleCount > 0;

    if (sampleCount > 0) {
        fromSummary.improvementRatePercent = 100.0
            * (double)fromSummary.improvedCount / (double)sampleCount;
        fromSummary.unchangedRatePercent = 100.0
            * (double)fromSummary.unchangedCount / (double)sampleCount;
        fromSummary.worseningRatePercent = 100.0
            * (double)fromSummary.worsenedCount / (double)sampleCount;
    }

    return findComparisonMedian(
        fromDatabaseHandle,
        fromRunId,
        fromRow,
        netExpression,
        laterOutcomeAlias + ".id",
        sampleCount,
        fromSummary.medianNetProfitPips,
        fromLogger
    );
}

/**
 * 24グループの共通Cohort母数を構築する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromRunId Outcome Run ID。
 * @param fromRows 構築結果。
 * @param fromLogger ロガー。
 * @return 全グループを構築できた場合true。
 */
bool buildComparisonSummaryRows(
    const int fromDatabaseHandle,
    const long fromRunId,
    ZigZagElliotH1StudyComparisonSummaryRow &fromRows[],
    Logger &fromLogger
) {
    ArrayResize(fromRows, comparisonExpectedSummaryRowCount);
    int rowIndex = 0;

    for (int i = 0; i < comparisonCohortCount; i++) {
        string cohortType = getComparisonCohortType(i);

        for (int j = 0; j < comparisonHorizonCount; j++) {
            int horizonH1Bars = getComparisonHorizonH1Bars(j);

            for (int k = 0; k < comparisonSideScopeCount; k++) {
                fromRows[rowIndex].reset();
                fromRows[rowIndex].cohortType = cohortType;
                fromRows[rowIndex].requiredConfirmationH1Count =
                    getComparisonRequiredConfirmationH1Count(cohortType);
                fromRows[rowIndex].horizonH1Bars = horizonH1Bars;
                fromRows[rowIndex].sideScope = getComparisonSideScope(k);

                if (!aggregateComparisonSummaryCounts(
                        fromDatabaseHandle,
                        fromRunId,
                        fromRows[rowIndex],
                        fromLogger
                    ) || !aggregateComparisonLegSummary(
                        fromDatabaseHandle,
                        fromRunId,
                        1,
                        fromRows[rowIndex],
                        fromRows[rowIndex].leg1,
                        fromLogger
                    ) || !aggregateComparisonLegSummary(
                        fromDatabaseHandle,
                        fromRunId,
                        2,
                        fromRows[rowIndex],
                        fromRows[rowIndex].leg2,
                        fromLogger
                    ) || !aggregateComparisonLegSummary(
                        fromDatabaseHandle,
                        fromRunId,
                        3,
                        fromRows[rowIndex],
                        fromRows[rowIndex].leg3,
                        fromLogger
                    ) || !aggregateComparisonDeltaSummary(
                        fromDatabaseHandle,
                        fromRunId,
                        1,
                        2,
                        fromRows[rowIndex],
                        fromRows[rowIndex].delta21,
                        fromLogger
                    ) || !aggregateComparisonDeltaSummary(
                        fromDatabaseHandle,
                        fromRunId,
                        1,
                        3,
                        fromRows[rowIndex],
                        fromRows[rowIndex].delta31,
                        fromLogger
                    ) || !aggregateComparisonDeltaSummary(
                        fromDatabaseHandle,
                        fromRunId,
                        2,
                        3,
                        fromRows[rowIndex],
                        fromRows[rowIndex].delta32,
                        fromLogger
                    )) {
                    return false;
                }

                rowIndex++;
            }
        }
    }

    return rowIndex == comparisonExpectedSummaryRowCount;
}

/**
 * ALL行とBUY／SELL行の件数を照合する。
 *
 * @param fromRows 集計行。
 * @param fromLogger ロガー。
 * @return 全件数が一致する場合true。
 */
bool validateComparisonSummaryScopeCounts(
    ZigZagElliotH1StudyComparisonSummaryRow &fromRows[],
    Logger &fromLogger
) {
    if (ArraySize(fromRows) != comparisonExpectedSummaryRowCount) {
        fromLogger.error(__FUNCTION__, "Summary row count is invalid.");

        return false;
    }

    for (int i = 0; i < comparisonExpectedSummaryRowCount; i += 3) {
        ZigZagElliotH1StudyComparisonSummaryRow allRow = fromRows[i];
        ZigZagElliotH1StudyComparisonSummaryRow buyRow = fromRows[i + 1];
        ZigZagElliotH1StudyComparisonSummaryRow sellRow = fromRows[i + 2];
        bool isConsistent = allRow.sideScope == "ALL"
            && buyRow.sideScope == "BUY"
            && sellRow.sideScope == "SELL"
            && allRow.cohortType == buyRow.cohortType
            && allRow.cohortType == sellRow.cohortType
            && allRow.horizonH1Bars == buyRow.horizonH1Bars
            && allRow.horizonH1Bars == sellRow.horizonH1Bars
            && allRow.candidateEpisodeCount
                == buyRow.candidateEpisodeCount
                    + sellRow.candidateEpisodeCount
            && allRow.ineligibleEpisodeCount
                == buyRow.ineligibleEpisodeCount
                    + sellRow.ineligibleEpisodeCount
            && allRow.eligibleEpisodeCount
                == buyRow.eligibleEpisodeCount
                    + sellRow.eligibleEpisodeCount
            && allRow.commonCalculatedEpisodeCount
                == buyRow.commonCalculatedEpisodeCount
                    + sellRow.commonCalculatedEpisodeCount
            && allRow.failedEpisodeCount
                == buyRow.failedEpisodeCount
                    + sellRow.failedEpisodeCount
            && allRow.futureH1GapEpisodeCount
                == buyRow.futureH1GapEpisodeCount
                    + sellRow.futureH1GapEpisodeCount
            && allRow.otherFailureEpisodeCount
                == buyRow.otherFailureEpisodeCount
                    + sellRow.otherFailureEpisodeCount;

        if (!isConsistent) {
            fromLogger.error(
                __FUNCTION__,
                StringFormat(
                    "Summary ALL scope mismatch. cohort=%s horizon=%d",
                    allRow.cohortType,
                    allRow.horizonH1Bars
                )
            );

            return false;
        }
    }

    return true;
}

/**
 * 1 Leg分の集計CSVヘッダーを追加する。
 *
 * @param fromPrefix 列名Prefix。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonLegSummaryHeaderValues(
    const string fromPrefix,
    string &fromValues[],
    int &fromIndex
) {
    fromValues[fromIndex++] = fromPrefix + "_is_applicable";
    fromValues[fromIndex++] = fromPrefix + "_is_statistics_available";
    fromValues[fromIndex++] = fromPrefix + "_winning_count";
    fromValues[fromIndex++] = fromPrefix + "_losing_count";
    fromValues[fromIndex++] = fromPrefix + "_flat_count";
    fromValues[fromIndex++] = fromPrefix + "_win_rate_percent";
    fromValues[fromIndex++] = fromPrefix + "_net_profit_sum_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_gross_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_net_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_median_net_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_winning_net_profit_sum_pips";
    fromValues[fromIndex++] = fromPrefix + "_losing_net_profit_abs_sum_pips";
    fromValues[fromIndex++] = fromPrefix + "_profit_factor";
    fromValues[fromIndex++] = fromPrefix + "_profit_factor_status";
    fromValues[fromIndex++] = fromPrefix + "_average_mfe_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_mae_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_gross_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_average_net_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_average_entry_spread_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_max_profit_h1_bars";
}

/**
 * 1 Leg分の集計CSV値を追加する。
 *
 * @param fromSummary 出力対象。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonLegSummaryRowValues(
    ZigZagElliotH1StudyComparisonLegSummary &fromSummary,
    string &fromValues[],
    int &fromIndex
) {
    bool hasStatistics = fromSummary.isApplicable
        && fromSummary.isStatisticsAvailable;
    bool hasProfitFactor = fromSummary.profitFactorStatus == "AVAILABLE";
    fromValues[fromIndex++] = IntegerToString((int)fromSummary.isApplicable);
    fromValues[fromIndex++] = formatComparisonOptionalInt(
        (int)fromSummary.isStatisticsAvailable,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.winningCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.losingCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.flatCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.winRatePercent,
        hasStatistics,
        6
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.netProfitSumPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageGrossProfitPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageNetProfitPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.medianNetProfitPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.winningNetProfitSumPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.losingNetProfitAbsSumPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.profitFactor,
        hasProfitFactor,
        8
    );
    fromValues[fromIndex++] = fromSummary.profitFactorStatus;
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageMfePips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageMaePips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageGrossProfitAtr,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageNetProfitAtr,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageEntrySpreadPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageMaxProfitH1Bars,
        hasStatistics,
        8
    );
}

/**
 * 1差分分の集計CSVヘッダーを追加する。
 *
 * @param fromPrefix 列名Prefix。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonDeltaSummaryHeaderValues(
    const string fromPrefix,
    string &fromValues[],
    int &fromIndex
) {
    fromValues[fromIndex++] = fromPrefix + "_is_applicable";
    fromValues[fromIndex++] = fromPrefix + "_is_statistics_available";
    fromValues[fromIndex++] = fromPrefix + "_improved_count";
    fromValues[fromIndex++] = fromPrefix + "_unchanged_count";
    fromValues[fromIndex++] = fromPrefix + "_worsened_count";
    fromValues[fromIndex++] = fromPrefix + "_improvement_rate_percent";
    fromValues[fromIndex++] = fromPrefix + "_unchanged_rate_percent";
    fromValues[fromIndex++] = fromPrefix + "_worsening_rate_percent";
    fromValues[fromIndex++] = fromPrefix + "_average_gross_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_net_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_median_net_profit_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_gross_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_average_net_profit_atr";
    fromValues[fromIndex++] = fromPrefix + "_average_spread_reduction_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_mfe_improvement_pips";
    fromValues[fromIndex++] = fromPrefix + "_average_mae_reduction_pips";
    fromValues[fromIndex++] = fromPrefix
        + "_max_profit_speedup_comparable_count";
    fromValues[fromIndex++] = fromPrefix
        + "_average_max_profit_speedup_h1_bars";
    fromValues[fromIndex++] = fromPrefix + "_win_to_win_count";
    fromValues[fromIndex++] = fromPrefix + "_win_to_flat_count";
    fromValues[fromIndex++] = fromPrefix + "_win_to_loss_count";
    fromValues[fromIndex++] = fromPrefix + "_flat_to_win_count";
    fromValues[fromIndex++] = fromPrefix + "_flat_to_flat_count";
    fromValues[fromIndex++] = fromPrefix + "_flat_to_loss_count";
    fromValues[fromIndex++] = fromPrefix + "_loss_to_win_count";
    fromValues[fromIndex++] = fromPrefix + "_loss_to_flat_count";
    fromValues[fromIndex++] = fromPrefix + "_loss_to_loss_count";
}

/**
 * 1差分分の集計CSV値を追加する。
 *
 * @param fromSummary 出力対象。
 * @param fromValues 追加先。
 * @param fromIndex 追加位置。追加後は次位置へ進める。
 */
void appendComparisonDeltaSummaryRowValues(
    ZigZagElliotH1StudyComparisonDeltaSummary &fromSummary,
    string &fromValues[],
    int &fromIndex
) {
    bool hasStatistics = fromSummary.isApplicable
        && fromSummary.isStatisticsAvailable;
    fromValues[fromIndex++] = IntegerToString((int)fromSummary.isApplicable);
    fromValues[fromIndex++] = formatComparisonOptionalInt(
        (int)fromSummary.isStatisticsAvailable,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.improvedCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.unchangedCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.worsenedCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.improvementRatePercent,
        hasStatistics,
        6
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.unchangedRatePercent,
        hasStatistics,
        6
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.worseningRatePercent,
        hasStatistics,
        6
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageGrossProfitPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageNetProfitPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.medianNetProfitPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageGrossProfitAtr,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageNetProfitAtr,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageSpreadReductionPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageMfeImprovementPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageMaeReductionPips,
        hasStatistics,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.maxProfitSpeedupComparableCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalDouble(
        fromSummary.averageMaxProfitSpeedupH1Bars,
        hasStatistics && fromSummary.maxProfitSpeedupComparableCount > 0,
        8
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.winToWinCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.winToFlatCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.winToLossCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.flatToWinCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.flatToFlatCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.flatToLossCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.lossToWinCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.lossToFlatCount,
        fromSummary.isApplicable
    );
    fromValues[fromIndex++] = formatComparisonOptionalLong(
        fromSummary.lossToLossCount,
        fromSummary.isApplicable
    );
}

/**
 * 集計CSVヘッダーを構築する。
 *
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setComparisonSummaryHeaderValues(
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, comparisonSummaryCsvFieldCount);
    int index = 0;
    appendComparisonCommonHeaderValues(fromValues, index);
    fromValues[index++] = "cohort_type";
    fromValues[index++] = "required_confirmation_h1_count";
    fromValues[index++] = "side_scope";
    fromValues[index++] = "horizon_h1_bars";
    fromValues[index++] = "candidate_episode_count";
    fromValues[index++] = "ineligible_episode_count";
    fromValues[index++] = "eligible_episode_count";
    fromValues[index++] = "common_calculated_episode_count";
    fromValues[index++] = "failed_episode_count";
    fromValues[index++] = "future_h1_gap_episode_count";
    fromValues[index++] = "other_failure_episode_count";
    fromValues[index++] = "calculation_coverage_percent";
    appendComparisonLegSummaryHeaderValues(
        "confirmation_1",
        fromValues,
        index
    );
    appendComparisonLegSummaryHeaderValues(
        "confirmation_2",
        fromValues,
        index
    );
    appendComparisonLegSummaryHeaderValues(
        "confirmation_3",
        fromValues,
        index
    );
    appendComparisonDeltaSummaryHeaderValues(
        "delta_2_minus_1",
        fromValues,
        index
    );
    appendComparisonDeltaSummaryHeaderValues(
        "delta_3_minus_1",
        fromValues,
        index
    );
    appendComparisonDeltaSummaryHeaderValues(
        "delta_3_minus_2",
        fromValues,
        index
    );

    if (index == comparisonSummaryCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Summary CSV header field count mismatch. expected=%d actual=%d",
            comparisonSummaryCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 集計CSV行を構築する。
 *
 * @param fromRunInfo Outcome Run情報。
 * @param fromRow 集計行。
 * @param fromValues 構築結果。
 * @param fromLogger ロガー。
 * @return 列数が正しい場合true。
 */
bool setComparisonSummaryRowValues(
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    ZigZagElliotH1StudyComparisonSummaryRow &fromRow,
    string &fromValues[],
    Logger &fromLogger
) {
    ArrayResize(fromValues, comparisonSummaryCsvFieldCount);
    int index = 0;
    appendComparisonCommonRowValues(
        comparisonSummaryCsvSchemaVersion,
        fromRunInfo,
        fromValues,
        index
    );
    fromValues[index++] = fromRow.cohortType;
    fromValues[index++] = IntegerToString(
        fromRow.requiredConfirmationH1Count
    );
    fromValues[index++] = fromRow.sideScope;
    fromValues[index++] = IntegerToString(fromRow.horizonH1Bars);
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.candidateEpisodeCount
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.ineligibleEpisodeCount
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.eligibleEpisodeCount
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.commonCalculatedEpisodeCount
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.failedEpisodeCount
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.futureH1GapEpisodeCount
    );
    fromValues[index++] = StringFormat(
        "%I64d",
        fromRow.otherFailureEpisodeCount
    );
    fromValues[index++] = formatComparisonOptionalDouble(
        fromRow.calculationCoveragePercent,
        fromRow.eligibleEpisodeCount > 0,
        6
    );
    appendComparisonLegSummaryRowValues(fromRow.leg1, fromValues, index);
    appendComparisonLegSummaryRowValues(fromRow.leg2, fromValues, index);
    appendComparisonLegSummaryRowValues(fromRow.leg3, fromValues, index);
    appendComparisonDeltaSummaryRowValues(fromRow.delta21, fromValues, index);
    appendComparisonDeltaSummaryRowValues(fromRow.delta31, fromValues, index);
    appendComparisonDeltaSummaryRowValues(fromRow.delta32, fromValues, index);

    if (index == comparisonSummaryCsvFieldCount) {
        return true;
    }

    fromLogger.error(
        __FUNCTION__,
        StringFormat(
            "Summary CSV data field count mismatch. expected=%d actual=%d",
            comparisonSummaryCsvFieldCount,
            index
        )
    );

    return false;
}

/**
 * 24グループの集計CSVを上書き出力する。
 *
 * @param fromRunInfo Outcome Run情報。
 * @param fromRows 集計行。
 * @param fromLogger ロガー。
 * @return 全行を出力できた場合true。
 */
bool writeComparisonSummaryCsv(
    ZigZagElliotH1StudyComparisonRunInfo &fromRunInfo,
    ZigZagElliotH1StudyComparisonSummaryRow &fromRows[],
    Logger &fromLogger
) {
    string headerValues[];

    if (!setComparisonSummaryHeaderValues(headerValues, fromLogger)) {
        return false;
    }

    string fileName = getComparisonSummaryOutputFileName(fromRunInfo.id);
    CsvFileWriter fileWriter(
        fileName,
        outputUseCommonFolder,
        ",",
        false,
        true,
        "",
        CSV_FILE_WRITE_MODE_OVERWRITE
    );

    if (!fileWriter.writeHeader(headerValues, false)) {
        fileWriter.close();
        fromLogger.error(
            __FUNCTION__,
            "Summary CSV header write failed. file=" + fileName
        );

        return false;
    }

    int rowCount = ArraySize(fromRows);

    for (int i = 0; i < rowCount; i++) {
        string rowValues[];

        if (!setComparisonSummaryRowValues(
                fromRunInfo,
                fromRows[i],
                rowValues,
                fromLogger
            ) || !fileWriter.writeRow(rowValues)) {
            fileWriter.close();
            fromLogger.error(
                __FUNCTION__,
                StringFormat("Summary CSV row write failed. index=%d", i)
            );

            return false;
        }
    }

    fileWriter.close();

    return rowCount == comparisonExpectedSummaryRowCount;
}

/**
 * 読み取りSnapshot内でEpisode明細と共通Cohort集計を出力する。
 *
 * @param fromDatabaseHandle Outcome DBハンドル。
 * @param fromLogger ロガー。
 * @return 全処理に成功した場合true。
 */
bool executeComparisonExport(
    const int fromDatabaseHandle,
    Logger &fromLogger
) {
    ZigZagElliotH1StudyComparisonRunInfo runInfo;

    if (!selectComparisonRun(fromDatabaseHandle, runInfo, fromLogger)
            || !validateComparisonRunData(
                fromDatabaseHandle,
                runInfo,
                fromLogger
            )) {
        return false;
    }

    string episodeFileName = getComparisonEpisodeOutputFileName(runInfo.id);
    string summaryFileName = getComparisonSummaryOutputFileName(runInfo.id);

    if (!isComparisonCsvFileName(episodeFileName)
            || !isComparisonCsvFileName(summaryFileName)
            || StringCompare(episodeFileName, summaryFileName, false) == 0
            || (outputUseCommonFolder == databaseUseCommonFolder
                && (StringCompare(
                        episodeFileName,
                        outcomeDatabaseFileName,
                        false
                    ) == 0
                    || StringCompare(
                        summaryFileName,
                        outcomeDatabaseFileName,
                        false
                    ) == 0))) {
        fromLogger.error(__FUNCTION__, "Resolved output file names are invalid.");

        return false;
    }

    ZigZagElliotH1StudyComparisonSummaryRow summaryRows[];

    if (!buildComparisonSummaryRows(
            fromDatabaseHandle,
            runInfo.id,
            summaryRows,
            fromLogger
        ) || !validateComparisonSummaryScopeCounts(
            summaryRows,
            fromLogger
        )) {
        return false;
    }

    long episodeRowCount = 0;

    if (!writeComparisonEpisodeCsv(
            fromDatabaseHandle,
            runInfo,
            episodeRowCount,
            fromLogger
        ) || !writeComparisonSummaryCsv(runInfo, summaryRows, fromLogger)) {
        return false;
    }

    fromLogger.info(
        __FUNCTION__,
        StringFormat(
            "Confirmation comparison export finished. outcomeRunId=%I64d episodeFile=%s episodeRows=%I64d summaryFile=%s summaryRows=%d",
            runInfo.id,
            episodeFileName,
            episodeRowCount,
            summaryFileName,
            ArraySize(summaryRows)
        )
    );

    return true;
}

/**
 * 同じEpisodeの1／2本および1／2／3本確認を公平比較する。
 */
void OnStart() {
    Logger logger(LOG_INFO);

    if (!validateComparisonInputs(logger)) {
        return;
    }

    SqliteDatabase outcomeDatabase(
        outcomeDatabaseFileName,
        databaseUseCommonFolder
    );

    if (!outcomeDatabase.openReadOnly()) {
        logger.error(__FUNCTION__, "Outcome DB could not be opened read-only.");

        return;
    }

    int databaseHandle = outcomeDatabase.getHandle();
    ResetLastError();

    if (!DatabaseTransactionBegin(databaseHandle)) {
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Read transaction could not be started. error=%d",
                GetLastError()
            )
        );

        return;
    }

    if (!executeComparisonExport(databaseHandle, logger)) {
        ResetLastError();

        if (!DatabaseTransactionRollback(databaseHandle)) {
            logger.error(
                __FUNCTION__,
                StringFormat(
                    "Read transaction rollback failed. error=%d",
                    GetLastError()
                )
            );
        }

        return;
    }

    ResetLastError();

    if (!DatabaseTransactionCommit(databaseHandle)) {
        int commitErrorCode = GetLastError();
        DatabaseTransactionRollback(databaseHandle);
        logger.error(
            __FUNCTION__,
            StringFormat(
                "Read transaction commit failed. error=%d",
                commitErrorCode
            )
        );
    }
}
//+------------------------------------------------------------------+
