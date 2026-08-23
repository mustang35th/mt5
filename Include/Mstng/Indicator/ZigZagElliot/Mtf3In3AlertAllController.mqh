//+------------------------------------------------------------------+
//|                                    Mtf3In3AlertAllController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_ALL_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_ALL_CONTROLLER_MQH

#include <Arrays\ArrayObj.mqh>
#include <Object.mqh>
#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\SymbolNameInfoAll.mqh>
#include <Mstng\Database\Entity\ZigZagElliotAlertRunEntity.mqh>
#include <Mstng\Database\ZigZagElliotAlertDatabaseContext.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ElliotAllList.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertResult.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertSnapshot.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertSnapshotBuilder.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Signal\SignalCount.mqh>
#include <Mstng\Util\TimeUtil.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * Result of the pre-analysis all-symbol H1 anchor check.
 */
enum Mtf3In3AlertAllAnchorStatus {
    MTF3_IN3_ALERT_ALL_ANCHOR_FATAL = -1,
    MTF3_IN3_ALERT_ALL_ANCHOR_SKIPPED = 0,
    MTF3_IN3_ALERT_ALL_ANCHOR_READY = 1,
    MTF3_IN3_ALERT_ALL_ANCHOR_COMPLETED = 2
};

/**
 * Persistent MTF_3in3 decision state for one symbol.
 */
class Mtf3In3AlertSymbolState : public CObject {
public:
    /** Broker symbol name. */
    string symbolName;

    /** Per-symbol MTF_3in3 decision engine. */
    ExpertAdvisorMTF_3in3 *expertAdvisor;

    /** Per-symbol signal occurrence state. */
    SignalCount *signalCount;

    /** Last evaluated H1 bar open time. */
    datetime lastEvaluatedH1BarTime;

    /** Last saved H1 bar open time. */
    datetime lastSavedH1BarTime;

    /** Snapshot staged until the common Run save phase. */
    Mtf3In3AlertSnapshot pendingSnapshot;

    /** True when pendingSnapshot contains an Alert to save. */
    bool hasPendingSnapshot;

    /**
     * Initializes pointers and timestamps.
     */
    Mtf3In3AlertSymbolState() {
        this.symbolName = "";
        this.expertAdvisor = NULL;
        this.signalCount = NULL;
        this.lastEvaluatedH1BarTime = 0;
        this.lastSavedH1BarTime = 0;
        this.hasPendingSnapshot = false;
    }

    /**
     * Releases owned resources.
     */
    ~Mtf3In3AlertSymbolState() {
        this.destroy();
    }

    /**
     * Creates the decision state for one symbol.
     *
     * @param fromSymbolName Broker symbol name.
     * @param fromConfig Alert decision configuration.
     * @return True when both state objects were created.
     */
    bool initialize(
        const string fromSymbolName,
        ZigZagElliotConfig &fromConfig
    ) {
        this.destroy();
        this.symbolName = fromSymbolName;
        MarketContext context(this.symbolName, PERIOD_H1);
        this.expertAdvisor = ExpertAdvisorMtf3In3Factory::create(
            context,
            false,
            fromConfig.h1W1ConfirmationMode,
            fromConfig.h1DirectionAlignmentMode,
            fromConfig.h1Ema200ConfirmationMode
        );
        this.signalCount = new SignalCount(context);

        if (this.expertAdvisor == NULL || this.signalCount == NULL) {
            this.destroy();

            return false;
        }

        return true;
    }

    /**
     * Clears the staged database snapshot.
     */
    void clearPendingSnapshot() {
        this.pendingSnapshot.clear();
        this.hasPendingSnapshot = false;
    }

    /**
     * Releases the per-symbol decision state.
     */
    void destroy() {
        this.clearPendingSnapshot();

        if (this.expertAdvisor != NULL) {
            delete this.expertAdvisor;
            this.expertAdvisor = NULL;
        }

        if (this.signalCount != NULL) {
            delete this.signalCount;
            this.signalCount = NULL;
        }

        this.symbolName = "";
        this.lastEvaluatedH1BarTime = 0;
        this.lastSavedH1BarTime = 0;
    }
};

/**
 * Evaluates 28 symbols with per-symbol state and one shared Alert DB Run.
 *
 * ElliotAll objects are reused from ZigZagElliotList. Only the MTF_3in3 EA
 * and SignalCount are retained separately for each symbol. Evaluation is
 * accepted only at the actual H1 open so delayed analysis cannot look ahead.
 */
class Mtf3In3AlertAllController {
public:
    /**
     * Initializes owned pointers and execution state.
     */
    Mtf3In3AlertAllController() {
        this.databaseContext = NULL;
        this.databaseReady = false;
        this.initialized = false;
        this.fatalError = false;
        this.testerMode = false;
        this.oneMinuteOhlcConfirmed = false;
        this.hostSymbolName = "";
        this.testerStartTime = 0;
        this.testerSaveStartTime = 0;
        this.testerExpectedLastH1BarTime = 0;
        this.testerMinimumWarmUpH1Bars = 0;
        this.firstObservedH1BarTime = 0;
        this.lastSkippedH1BarTime = 0;
        this.evaluationStartedH1BarTime = 0;
        this.lastCompletedH1BarTime = 0;
        this.evaluatedH1Count = 0;
        this.totalSavedCount = 0;
        this.fatalErrorText = "";
        ZeroMemory(this.databaseRun);
    }

    /**
     * Releases owned resources.
     */
    ~Mtf3In3AlertAllController() {
        this.destroy();
    }

    /**
     * Initializes all per-symbol states and creates one shared DB Run.
     *
     * @param fromMarketContext Host List market context.
     * @param fromConfig Alert and database configuration.
     * @param fromSymbolNameInfoAll Resolved 28-symbol list.
     * @param fromTesterStartTime Configured tester start time.
     * @param fromTesterSaveStartTime First H1 open eligible for saving.
     * @param fromTesterExpectedLastH1BarTime Required final H1 open.
     * @param fromTesterMinimumWarmUpH1Bars Required pre-save evaluations.
     * @param fromOneMinuteOhlcConfirmed True when tester model is 1 minute OHLC.
     * @return MQL initialization result.
     */
    int initialize(
        MarketContext &fromMarketContext,
        ZigZagElliotConfig &fromConfig,
        SymbolNameInfoAll &fromSymbolNameInfoAll,
        const datetime fromTesterStartTime,
        const datetime fromTesterSaveStartTime,
        const datetime fromTesterExpectedLastH1BarTime,
        const int fromTesterMinimumWarmUpH1Bars,
        const bool fromOneMinuteOhlcConfirmed
    ) {
        this.destroy();
        this.config = fromConfig;
        this.testerMode = Util::isStrategyTester();
        this.oneMinuteOhlcConfirmed = fromOneMinuteOhlcConfirmed;
        this.hostSymbolName = fromMarketContext.symbolName;
        this.testerStartTime = fromTesterStartTime;
        this.testerSaveStartTime = fromTesterSaveStartTime;
        this.testerExpectedLastH1BarTime =
            fromTesterExpectedLastH1BarTime;
        this.testerMinimumWarmUpH1Bars =
            fromTesterMinimumWarmUpH1Bars;
        MarketContext allContext(
            "ALL",
            PERIOD_H1,
            TimeUtil::convertTimeFrameToString(PERIOD_H1),
            0
        );
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(allContext);

        if (!this.validateInputs(
                fromMarketContext,
                fromSymbolNameInfoAll
            )) {
            this.destroy();

            return INIT_PARAMETERS_INCORRECT;
        }

        int total = fromSymbolNameInfoAll.size();

        for (int i = 0; i < total; i++) {
            SymbolNameInfo *info =
                fromSymbolNameInfoAll.getSymbolNameInfo(i);

            if (info == NULL || !info.isTarget) {
                this.logger.error(
                    __FUNCTION__,
                    "target symbol state is invalid"
                );
                this.destroy();

                return INIT_FAILED;
            }

            Mtf3In3AlertSymbolState *state =
                new Mtf3In3AlertSymbolState();

            if (state == NULL
                    || !state.initialize(info.symbolName, this.config)
                    || !this.symbolStates.Add(state)) {
                if (state != NULL) {
                    delete state;
                }

                this.logger.error(
                    __FUNCTION__,
                    "failed to create symbol alert state symbol="
                        + info.symbolName
                );
                this.destroy();

                return INIT_FAILED;
            }
        }

        if (this.symbolStates.Total() != requiredTargetSymbolCount
                || !this.initializeDatabase()) {
            this.destroy();

            return INIT_FAILED;
        }

        this.initialized = true;
        this.logger.info(
            __FUNCTION__,
            StringFormat(
                "MTF_3in3 all-symbol alert is ready. runId=%I64d symbols=%d testerStart=%s saveStart=%s expectedLast=%s warmUpH1=%d model=1_MINUTE_OHLC",
                this.databaseRun.id,
                this.symbolStates.Total(),
                this.formatDateTime(this.testerStartTime),
                this.formatDateTime(this.testerSaveStartTime),
                this.formatDateTime(this.testerExpectedLastH1BarTime),
                this.testerMinimumWarmUpH1Bars
            )
        );

        return INIT_SUCCEEDED;
    }

    /**
     * Checks whether the current H1 can be analyzed without look-ahead.
     *
     * @param fromH1BarTime Host H1 bar open time.
     * @return Anchor status.
     */
    Mtf3In3AlertAllAnchorStatus prepareAnchor(
        const datetime fromH1BarTime
    ) {
        if (!this.initialized || this.fatalError) {
            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        if (!this.validateFirstObservedH1BarTime(fromH1BarTime)) {
            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        if (this.lastCompletedH1BarTime == fromH1BarTime) {
            return MTF3_IN3_ALERT_ALL_ANCHOR_COMPLETED;
        }

        if (this.lastCompletedH1BarTime
                == this.testerExpectedLastH1BarTime
                && fromH1BarTime
                    > this.testerExpectedLastH1BarTime) {
            return MTF3_IN3_ALERT_ALL_ANCHOR_COMPLETED;
        }

        if (fromH1BarTime <= 0) {
            this.setFatalError(__FUNCTION__, "H1 anchor is invalid");

            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        if (fromH1BarTime > this.testerExpectedLastH1BarTime) {
            this.setFatalError(
                __FUNCTION__,
                "expected final H1 was not completed before anchor="
                    + this.formatDateTime(fromH1BarTime)
            );

            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        if (fromH1BarTime >= this.testerSaveStartTime
                && this.evaluatedH1Count
                    < this.testerMinimumWarmUpH1Bars) {
            this.setFatalError(
                __FUNCTION__,
                StringFormat(
                    "insufficient Alert state warm-up before saveStart anchor=%s actualH1=%d requiredH1=%d",
                    this.formatDateTime(fromH1BarTime),
                    this.evaluatedH1Count,
                    this.testerMinimumWarmUpH1Bars
                )
            );

            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        if (this.evaluationStartedH1BarTime > 0
                && !this.isNextHostH1Bar(fromH1BarTime)) {
            this.setFatalError(
                __FUNCTION__,
                "H1 evaluation gap detected previous="
                    + this.formatDateTime(this.lastCompletedH1BarTime)
                    + " current=" + this.formatDateTime(fromH1BarTime)
            );

            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        datetime actualDecisionTime = TimeCurrent();

        if (actualDecisionTime != fromH1BarTime) {
            return this.handleUnavailableAnchor(
                fromH1BarTime,
                "decision is not at H1 open actual="
                    + this.formatDateTime(actualDecisionTime)
            );
        }

        for (int i = 0; i < this.symbolStates.Total(); i++) {
            Mtf3In3AlertSymbolState *state = this.symbolStates.At(i);

            if (state == NULL
                    || !this.isSymbolAnchorExact(
                        state.symbolName,
                        fromH1BarTime
                    )) {
                string symbolName = "NULL";

                if (state != NULL) {
                    symbolName = state.symbolName;
                }

                return this.handleUnavailableAnchor(
                    fromH1BarTime,
                    "all-symbol H1 anchor is unavailable symbol="
                        + symbolName
                );
            }
        }

        return MTF3_IN3_ALERT_ALL_ANCHOR_READY;
    }

    /**
     * Records an incomplete List batch for the current H1.
     *
     * @param fromH1BarTime Host H1 bar open time.
     * @param fromReason Failure reason.
     * @return Resulting anchor status.
     */
    Mtf3In3AlertAllAnchorStatus handleUnavailableAnalysis(
        const datetime fromH1BarTime,
        const string fromReason
    ) {
        return this.handleUnavailableAnchor(fromH1BarTime, fromReason);
    }

    /**
     * Reuses the List batch and evaluates all per-symbol Alert states.
     *
     * @param fromElliotAllList Complete 28-symbol List analysis.
     * @param fromH1BarTime Host H1 bar open time.
     * @return True when evaluation, saving, and Run update succeeded.
     */
    bool execute(
        ElliotAllList *fromElliotAllList,
        const datetime fromH1BarTime
    ) {
        Mtf3In3AlertAllAnchorStatus anchorStatus =
            this.prepareAnchor(fromH1BarTime);

        if (anchorStatus == MTF3_IN3_ALERT_ALL_ANCHOR_COMPLETED) {
            return true;
        }

        if (anchorStatus != MTF3_IN3_ALERT_ALL_ANCHOR_READY) {
            return false;
        }

        if (!this.isBatchReady(fromElliotAllList, fromH1BarTime)) {
            this.handleUnavailableAnchor(
                fromH1BarTime,
                "List analysis batch is incomplete"
            );

            return false;
        }

        if (this.hasPendingSnapshots()) {
            this.setFatalError(
                __FUNCTION__,
                "pending snapshot remained before H1 evaluation"
            );

            return false;
        }

        if (this.evaluationStartedH1BarTime == 0) {
            this.evaluationStartedH1BarTime = fromH1BarTime;
            this.databaseRun.evaluationStartedAt = fromH1BarTime;
        }

        bool persistenceAllowed = this.isPersistenceAllowed(
            fromH1BarTime
        );
        int total = this.symbolStates.Total();

        for (int i = 0; i < total; i++) {
            Mtf3In3AlertSymbolState *state = this.symbolStates.At(i);
            ElliotAll *elliotAll = NULL;

            if (state != NULL) {
                elliotAll = this.findElliotAll(
                    fromElliotAllList,
                    state.symbolName
                );
            }

            if (!this.isSymbolStateReady(
                    state,
                    elliotAll,
                    fromH1BarTime
                )) {
                string symbolName = "NULL";

                if (state != NULL) {
                    symbolName = state.symbolName;
                }

                this.setFatalError(
                    __FUNCTION__,
                    "invalid symbol state before alert analysis symbol="
                        + symbolName
                );

                return false;
            }

            elliotAll.isH1DisplayWaveEntryLimitEnabled =
                this.config.h1DisplayWaveEntryLimitEnabled;
            elliotAll.isCurrencyStrengthEntryFilterEnabled = false;
            state.expertAdvisor.analyze(
                elliotAll,
                state.signalCount
            );

            if (TimeCurrent() != fromH1BarTime
                    || elliotAll.tradeTimeInfo.serverTime
                        != fromH1BarTime
                    || !this.isSymbolAnchorExact(
                        state.symbolName,
                        fromH1BarTime
                    )) {
                this.setFatalError(
                    __FUNCTION__,
                    "H1 boundary changed during alert analysis symbol="
                        + state.symbolName
                );

                return false;
            }

            state.lastEvaluatedH1BarTime = fromH1BarTime;

            if (!state.expertAdvisor.isAlert
                    || !persistenceAllowed) {
                continue;
            }

            Mtf3In3AlertResult alertResult =
                state.expertAdvisor.getAlertResult();
            state.pendingSnapshot.clear();
            bool isBuilt = Mtf3In3AlertSnapshotBuilder::build(
                elliotAll,
                alertResult,
                this.databaseRun.runUid,
                "ZIGZAG_ELLIOT",
                0,
                state.expertAdvisor.alertText,
                state.pendingSnapshot
            );

            if (!isBuilt
                    || state.pendingSnapshot.alert.serverTime
                        != fromH1BarTime
                    || state.pendingSnapshot.alert.currentBarTime
                        != fromH1BarTime
                    || !this.isSymbolAnchorExact(
                        state.symbolName,
                        fromH1BarTime
                    )) {
                state.pendingSnapshot.clear();
                this.setFatalError(
                    __FUNCTION__,
                    "failed to build exact-anchor snapshot symbol="
                        + state.symbolName
                );

                return false;
            }

            state.pendingSnapshot.alert.runId = this.databaseRun.id;
            state.hasPendingSnapshot = true;
        }

        if (!this.savePendingSnapshots()) {
            this.setFatalError(
                __FUNCTION__,
                "all-symbol Alert snapshot save failed"
            );

            return false;
        }

        this.lastCompletedH1BarTime = fromH1BarTime;
        this.evaluatedH1Count++;
        this.databaseRun.lastCompletedH1BarTime = fromH1BarTime;
        this.databaseRun.evaluatedH1Count = this.evaluatedH1Count;
        this.databaseRun.savedAlertCount = this.totalSavedCount;
        this.databaseRun.status = "RUNNING";
        this.databaseRun.completedAt = 0;
        this.databaseRun.errorText = "";

        if (!this.persistRunProgress()) {
            this.setFatalError(
                __FUNCTION__,
                "failed to update common Alert Run progress"
            );

            return false;
        }

        if (this.evaluatedH1Count == 1
                || this.evaluatedH1Count % 100 == 0
                || fromH1BarTime == this.testerSaveStartTime) {
            this.logger.info(
                __FUNCTION__,
                StringFormat(
                    "all-symbol H1 evaluation completed. runId=%I64d anchor=%s evaluated=%d saved=%d",
                    this.databaseRun.id,
                    this.formatDateTime(fromH1BarTime),
                    this.evaluatedH1Count,
                    this.totalSavedCount
                )
            );
        }

        return true;
    }

    /**
     * Returns true after an unrecoverable Run integrity failure.
     *
     * @return True when the common Run is invalid.
     */
    bool hasFatalError() const {
        return this.fatalError;
    }

    /**
     * Returns true after the configured final H1 completed.
     *
     * @return True when the collection range is complete.
     */
    bool isCollectionCompleted() const {
        return this.lastCompletedH1BarTime > 0
            && this.lastCompletedH1BarTime
                == this.testerExpectedLastH1BarTime;
    }

    /**
     * Returns the shared Alert Run ID.
     *
     * @return Run ID, or zero before database initialization.
     */
    long getRunId() const {
        return this.databaseRun.id;
    }

    /**
     * Finalizes the common Run and releases all owned resources.
     */
    void destroy() {
        this.finalizeRun();
        this.releaseDatabase();

        this.symbolStates.Clear();
        this.initialized = false;
        this.fatalError = false;
        this.testerMode = false;
        this.oneMinuteOhlcConfirmed = false;
        this.hostSymbolName = "";
        this.testerStartTime = 0;
        this.testerSaveStartTime = 0;
        this.testerExpectedLastH1BarTime = 0;
        this.testerMinimumWarmUpH1Bars = 0;
        this.firstObservedH1BarTime = 0;
        this.lastSkippedH1BarTime = 0;
        this.evaluationStartedH1BarTime = 0;
        this.lastCompletedH1BarTime = 0;
        this.evaluatedH1Count = 0;
        this.totalSavedCount = 0;
        this.fatalErrorText = "";
    }

private:
    enum TargetSymbolCount {
        /** Required number of FX symbols. */
        requiredTargetSymbolCount = 28
    };

    /** Alert decision and database configuration. */
    ZigZagElliotConfig config;

    /** Per-symbol MTF_3in3 states. */
    CArrayObj symbolStates;

    /** Shared Alert database context. */
    ZigZagElliotAlertDatabaseContext *databaseContext;

    /** Shared Run for all 28 symbols. */
    ZigZagElliotAlertRunEntity databaseRun;

    /** Execution logger. */
    Logger logger;

    /** True while the database can persist records. */
    bool databaseReady;

    /** True after successful controller initialization. */
    bool initialized;

    /** True after an unrecoverable Run integrity failure. */
    bool fatalError;

    /** True in Strategy Tester. */
    bool testerMode;

    /** Explicit user confirmation of the required tester model. */
    bool oneMinuteOhlcConfirmed;

    /** Host symbol used as the common H1 clock. */
    string hostSymbolName;

    /** Configured Strategy Tester start time. */
    datetime testerStartTime;

    /** First H1 open eligible for Alert persistence. */
    datetime testerSaveStartTime;

    /** Required final H1 open for a COMPLETED Run. */
    datetime testerExpectedLastH1BarTime;

    /** Required continuous H1 evaluations before saveStart. */
    int testerMinimumWarmUpH1Bars;

    /** First H1 open observed by the running Strategy Tester. */
    datetime firstObservedH1BarTime;

    /** Last preflight H1 logged as skipped. */
    datetime lastSkippedH1BarTime;

    /** First H1 evaluated by all 28 per-symbol states. */
    datetime evaluationStartedH1BarTime;

    /** Last continuously completed H1 open. */
    datetime lastCompletedH1BarTime;

    /** Number of continuously evaluated H1 bars. */
    int evaluatedH1Count;

    /** Number of Alert snapshots saved to the shared Run. */
    int totalSavedCount;

    /** First unrecoverable error recorded for the Run. */
    string fatalErrorText;

    /**
     * Validates tester mode, H1 scope, symbols, and Alert settings.
     *
     * @param fromMarketContext Host List market context.
     * @param fromSymbolNameInfoAll Resolved target symbols.
     * @return True when all inputs are safe for collection.
     */
    bool validateInputs(
        MarketContext &fromMarketContext,
        SymbolNameInfoAll &fromSymbolNameInfoAll
    ) {
        if (!this.testerMode) {
            this.logger.error(
                __FUNCTION__,
                "all-symbol Alert collection is available in Strategy Tester only"
            );

            return false;
        }

        if (MQLInfoInteger(MQL_OPTIMIZATION)) {
            this.logger.error(
                __FUNCTION__,
                "all-symbol Alert collection is unavailable during optimization"
            );

            return false;
        }

        if (fromMarketContext.timeFrame != PERIOD_H1
                || fromSymbolNameInfoAll.size()
                    != requiredTargetSymbolCount
                || !this.isHostTarget(fromSymbolNameInfoAll)
                || this.testerStartTime <= 0
                || this.testerSaveStartTime <= this.testerStartTime
                || this.testerExpectedLastH1BarTime
                    < this.testerSaveStartTime
                || this.testerMinimumWarmUpH1Bars < 1
                || this.testerMinimumWarmUpH1Bars > 100000
                || !this.isH1OpenTime(this.testerStartTime)
                || !this.isH1OpenTime(this.testerSaveStartTime)
                || !this.isH1OpenTime(
                    this.testerExpectedLastH1BarTime
                )
                || !this.oneMinuteOhlcConfirmed
                || !this.config.mtf3In3AlertDatabaseEnabled
                || this.config.mtf3In3AlertDatabaseFileName == ""
                || !this.config.mtf3In3AlertDatabaseUseCommonFolder
                || this.config.currencyStrengthEntryFilterEnabled
                || !isH1W1ConfirmationModeValid(
                    this.config.h1W1ConfirmationMode
                )
                || !isH1DirectionAlignmentModeValid(
                    this.config.h1DirectionAlignmentMode
                )
                || !isH1Ema200ConfirmationModeValid(
                    this.config.h1Ema200ConfirmationMode
                )) {
            this.logger.error(
                __FUNCTION__,
                "all-symbol Alert input is invalid; tester start/saveStart/expectedLast, warm-up count, H1 target FX, and 1 minute OHLC confirmation are required"
            );

            return false;
        }

        return true;
    }

    /**
     * Checks whether the host is one of the resolved 28 targets.
     *
     * @param fromSymbolNameInfoAll Resolved target symbols.
     * @return True when the host belongs to the target set.
     */
    bool isHostTarget(SymbolNameInfoAll &fromSymbolNameInfoAll) {
        for (int i = 0; i < fromSymbolNameInfoAll.size(); i++) {
            SymbolNameInfo *info =
                fromSymbolNameInfoAll.getSymbolNameInfo(i);

            if (info != NULL
                    && info.isTarget
                    && info.symbolName == this.hostSymbolName) {
                return true;
            }
        }

        return false;
    }

    /**
     * Checks whether a configured datetime is aligned to an H1 open.
     *
     * @param fromTime Configured server time.
     * @return True when minutes and seconds are zero.
     */
    bool isH1OpenTime(const datetime fromTime) {
        MqlDateTime dateTime;
        ZeroMemory(dateTime);

        if (!TimeToStruct(fromTime, dateTime)) {
            return false;
        }

        return dateTime.min == 0 && dateTime.sec == 0;
    }

    /**
     * Verifies that the declared tester start is the actual first H1.
     *
     * @param fromH1BarTime First or subsequent observed H1 open.
     * @return True when the first observed H1 matches testerStartTime.
     */
    bool validateFirstObservedH1BarTime(
        const datetime fromH1BarTime
    ) {
        if (this.firstObservedH1BarTime == 0) {
            this.firstObservedH1BarTime = fromH1BarTime;
            datetime firstObservedServerTime = TimeCurrent();

            if (this.firstObservedH1BarTime != this.testerStartTime
                    || firstObservedServerTime
                        != this.testerStartTime) {
                this.setFatalError(
                    __FUNCTION__,
                    "tester start does not match first observation expected="
                        + this.formatDateTime(this.testerStartTime)
                        + " actualH1="
                        + this.formatDateTime(
                            this.firstObservedH1BarTime
                        )
                        + " actualServer="
                        + this.formatDateTime(
                            firstObservedServerTime
                        )
                );

                return false;
            }
        }

        return this.firstObservedH1BarTime == this.testerStartTime;
    }

    /**
     * Converts an unavailable H1 into preflight skip or fatal failure.
     *
     * @param fromH1BarTime Host H1 bar open time.
     * @param fromReason Failure reason.
     * @return Skipped before state start, otherwise fatal.
     */
    Mtf3In3AlertAllAnchorStatus handleUnavailableAnchor(
        const datetime fromH1BarTime,
        const string fromReason
    ) {
        if (!this.validateFirstObservedH1BarTime(fromH1BarTime)) {
            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        if (this.evaluationStartedH1BarTime > 0
                || (this.testerSaveStartTime > 0
                    && fromH1BarTime >= this.testerSaveStartTime)) {
            this.setFatalError(
                __FUNCTION__,
                fromReason + " anchor="
                    + this.formatDateTime(fromH1BarTime)
            );

            return MTF3_IN3_ALERT_ALL_ANCHOR_FATAL;
        }

        if (this.lastSkippedH1BarTime != fromH1BarTime) {
            this.logger.info(
                __FUNCTION__,
                "all-symbol preflight H1 skipped. anchor="
                    + this.formatDateTime(fromH1BarTime)
                    + " reason=" + fromReason
            );
            this.lastSkippedH1BarTime = fromH1BarTime;
        }

        return MTF3_IN3_ALERT_ALL_ANCHOR_SKIPPED;
    }

    /**
     * Checks continuity against actual host H1 bars, including weekends.
     *
     * @param fromH1BarTime Candidate current H1 open.
     * @return True when the previous completed H1 is shift 1.
     */
    bool isNextHostH1Bar(const datetime fromH1BarTime) {
        if (this.lastCompletedH1BarTime <= 0
                || fromH1BarTime <= this.lastCompletedH1BarTime
                || iTime(this.hostSymbolName, PERIOD_H1, 0)
                    != fromH1BarTime) {
            return false;
        }

        int previousShift = iBarShift(
            this.hostSymbolName,
            PERIOD_H1,
            this.lastCompletedH1BarTime,
            true
        );

        return previousShift == 1;
    }

    /**
     * Checks one symbol for an exact H1-open bar and tick timestamp.
     *
     * @param fromSymbolName Broker symbol name.
     * @param fromH1BarTime Expected H1 open.
     * @return True only for an exact common anchor.
     */
    bool isSymbolAnchorExact(
        const string fromSymbolName,
        const datetime fromH1BarTime
    ) {
        if (fromSymbolName == ""
                || iTime(fromSymbolName, PERIOD_H1, 0)
                    != fromH1BarTime) {
            return false;
        }

        MqlTick tick;
        ZeroMemory(tick);

        if (!SymbolInfoTick(fromSymbolName, tick)) {
            return false;
        }

        return tick.time == fromH1BarTime;
    }

    /**
     * Checks that the List batch has one successful result per state.
     *
     * @param fromElliotAllList List analysis batch.
     * @param fromH1BarTime Expected H1 open.
     * @return True when all 28 results are usable at the exact anchor.
     */
    bool isBatchReady(
        ElliotAllList *fromElliotAllList,
        const datetime fromH1BarTime
    ) {
        if (fromElliotAllList == NULL
                || fromElliotAllList.targetCount
                    != requiredTargetSymbolCount
                || fromElliotAllList.elliotAllList.Total()
                    != requiredTargetSymbolCount) {
            return false;
        }

        for (int i = 0; i < this.symbolStates.Total(); i++) {
            Mtf3In3AlertSymbolState *state = this.symbolStates.At(i);

            if (state == NULL) {
                return false;
            }

            ElliotAll *elliotAll = this.findElliotAll(
                fromElliotAllList,
                state.symbolName
            );

            if (elliotAll == NULL
                    || !elliotAll.isAnalysisSucceeded
                    || elliotAll.marketContext.timeFrame != PERIOD_H1
                    || !this.areAlertElliotsReady(elliotAll)
                    || elliotAll.tradeTimeInfo.serverTime
                        != fromH1BarTime
                    || !this.isSymbolAnchorExact(
                        state.symbolName,
                        fromH1BarTime
                    )) {
                return false;
            }
        }

        return true;
    }

    /**
     * Checks Elliott objects dereferenced by the H1 MTF_3in3 engine.
     *
     * @param fromElliotAll Reused List analysis.
     * @return True when MN1 through H1 and two current points are available.
     */
    bool areAlertElliotsReady(ElliotAll *fromElliotAll) {
        if (fromElliotAll == NULL
                || fromElliotAll.elliotCurrent == NULL
                || fromElliotAll.elliotCurrent.getLatestPoint2()
                    == NULL) {
            return false;
        }

        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1,
            PERIOD_W1,
            PERIOD_D1,
            PERIOD_H4,
            PERIOD_H1
        };

        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = fromElliotAll.getElliot(timeFrames[i]);

            if (elliot == NULL
                    || elliot.getLatestWave() == NULL
                    || elliot.getLatestPoint() == NULL) {
                return false;
            }
        }

        return true;
    }

    /**
     * Checks per-symbol continuity immediately before EA evaluation.
     *
     * @param fromState Per-symbol state.
     * @param fromElliotAll Reused List analysis.
     * @param fromH1BarTime Expected H1 open.
     * @return True when the state can be advanced once.
     */
    bool isSymbolStateReady(
        Mtf3In3AlertSymbolState *fromState,
        ElliotAll *fromElliotAll,
        const datetime fromH1BarTime
    ) {
        if (fromState == NULL
                || fromState.expertAdvisor == NULL
                || fromState.signalCount == NULL
                || fromElliotAll == NULL
                || fromState.hasPendingSnapshot
                || fromState.lastEvaluatedH1BarTime
                    == fromH1BarTime
                || fromState.lastEvaluatedH1BarTime
                    > fromH1BarTime) {
            return false;
        }

        if (this.lastCompletedH1BarTime == 0) {
            if (fromState.lastEvaluatedH1BarTime != 0) {
                return false;
            }
        } else if (fromState.lastEvaluatedH1BarTime
                != this.lastCompletedH1BarTime) {
            return false;
        }

        return fromElliotAll.tradeTimeInfo.serverTime
                == fromH1BarTime
            && this.isSymbolAnchorExact(
                fromState.symbolName,
                fromH1BarTime
            );
    }

    /**
     * Finds one symbol result in the reused List batch.
     *
     * @param fromElliotAllList List analysis batch.
     * @param fromSymbolName Broker symbol name.
     * @return Matching result, or NULL.
     */
    ElliotAll *findElliotAll(
        ElliotAllList *fromElliotAllList,
        const string fromSymbolName
    ) {
        if (fromElliotAllList == NULL) {
            return NULL;
        }

        int total = fromElliotAllList.elliotAllList.Total();

        for (int i = 0; i < total; i++) {
            ElliotAll *elliotAll =
                fromElliotAllList.elliotAllList.At(i);

            if (elliotAll != NULL
                    && elliotAll.marketContext.symbolName
                        == fromSymbolName) {
                return elliotAll;
            }
        }

        return NULL;
    }

    /**
     * Checks whether the current H1 belongs to the save period.
     *
     * @param fromH1BarTime Current H1 open.
     * @return True when Alerts may be saved.
     */
    bool isPersistenceAllowed(const datetime fromH1BarTime) {
        if (!this.testerMode || this.testerSaveStartTime <= 0) {
            return true;
        }

        return fromH1BarTime >= this.testerSaveStartTime;
    }

    /**
     * Returns true when at least one staged snapshot exists.
     *
     * @return True when a staged snapshot exists.
     */
    bool hasPendingSnapshots() {
        for (int i = 0; i < this.symbolStates.Total(); i++) {
            Mtf3In3AlertSymbolState *state = this.symbolStates.At(i);

            if (state != NULL && state.hasPendingSnapshot) {
                return true;
            }
        }

        return false;
    }

    /**
     * Saves all staged Alerts under the same Run ID.
     *
     * @return True when every staged snapshot was saved.
     */
    bool savePendingSnapshots() {
        if (!this.databaseReady || this.databaseContext == NULL) {
            return false;
        }

        ZigZagElliotAlertPersistenceService *persistenceService =
            this.databaseContext.getPersistenceService();

        if (persistenceService == NULL) {
            return false;
        }

        for (int i = 0; i < this.symbolStates.Total(); i++) {
            Mtf3In3AlertSymbolState *state = this.symbolStates.At(i);

            if (state == NULL || !state.hasPendingSnapshot) {
                continue;
            }

            if (!persistenceService.saveSnapshot(
                    state.pendingSnapshot.alert,
                    state.pendingSnapshot.timeFrames,
                    state.pendingSnapshot.points
                )) {
                this.logger.error(
                    __FUNCTION__,
                    "all-symbol Alert database save failed symbol="
                        + state.symbolName
                );

                return false;
            }

            state.lastSavedH1BarTime =
                state.pendingSnapshot.alert.currentBarTime;
            state.clearPendingSnapshot();
            this.totalSavedCount++;
        }

        return true;
    }

    /**
     * Opens the shared database and creates one RUNNING Run.
     *
     * @return True when the Run is ready for persistence.
     */
    bool initializeDatabase() {
        this.databaseContext = new ZigZagElliotAlertDatabaseContext(
            this.config.mtf3In3AlertDatabaseFileName,
            this.config.mtf3In3AlertDatabaseUseCommonFolder
        );

        if (this.databaseContext == NULL
                || !this.databaseContext.open()) {
            this.logger.error(
                __FUNCTION__,
                "all-symbol Alert database initialization failed"
            );
            this.releaseDatabase();

            return false;
        }

        this.setDatabaseRun();
        ZigZagElliotAlertPersistenceService *persistenceService =
            this.databaseContext.getPersistenceService();

        if (persistenceService == NULL
                || !persistenceService.saveRun(this.databaseRun)) {
            this.logger.error(
                __FUNCTION__,
                "all-symbol Alert database Run save failed"
            );
            this.releaseDatabase();

            return false;
        }

        this.databaseReady = true;

        return true;
    }

    /**
     * Builds metadata for the common 28-symbol Run.
     */
    void setDatabaseRun() {
        ZeroMemory(this.databaseRun);
        datetime localTime = TimeLocal();
        datetime marketTime = TimeCurrent();
        string inputText = this.createInputText();
        this.databaseRun.runUid = StringFormat(
            "%s_%I64u_%I64d",
            TimeUtil::formatYyyymmddhhmiss(localTime),
            GetTickCount64(),
            ChartID()
        );
        this.databaseRun.schemaVersion = 6;
        this.databaseRun.sourceMode = "TESTER";
        this.databaseRun.source = "ZIGZAG_ELLIOT";
        this.databaseRun.programName = MQLInfoString(MQL_PROGRAM_NAME);
        this.databaseRun.programVersion = "1.20";
        this.databaseRun.strategy = "MTF_3in3";
        this.databaseRun.strategyVersion = "MTF3IN3_V5";
        this.databaseRun.analysisVersion =
            ZigZagElliotAnalysisProfile::getAnalysisVersion();
        this.databaseRun.analysisInputText =
            ZigZagElliotAnalysisProfile::createCanonicalText();
        this.databaseRun.analysisInputHash =
            ZigZagElliotAnalysisProfile::createHash();
        this.databaseRun.sourceServer = AccountInfoString(ACCOUNT_SERVER);
        this.databaseRun.sourceLogin =
            (long)AccountInfoInteger(ACCOUNT_LOGIN);
        this.databaseRun.sourceChartId = ChartID();
        this.databaseRun.terminalBuild =
            (int)TerminalInfoInteger(TERMINAL_BUILD);
        this.databaseRun.testerFrom = this.testerStartTime;
        this.databaseRun.testerTo =
            this.testerExpectedLastH1BarTime
                + PeriodSeconds(PERIOD_H1);
        this.databaseRun.testerModel = "1_MINUTE_OHLC";
        this.databaseRun.inputText = inputText;
        this.databaseRun.inputHash = this.createTextHash(inputText);
        this.databaseRun.startedAt = localTime;
        this.databaseRun.startedAtText =
            TimeUtil::formatYyyymmddhhmiss(localTime);
        this.databaseRun.marketStartedAt = marketTime;
        this.databaseRun.marketStartedAtText =
            TimeUtil::formatYyyymmddhhmiss(marketTime);
        this.databaseRun.createdAt = localTime;
        this.databaseRun.createdAtText =
            TimeUtil::formatYyyymmddhhmiss(localTime);
        this.databaseRun.status = "RUNNING";
        this.databaseRun.evaluationStartedAt = 0;
        this.databaseRun.lastCompletedH1BarTime = 0;
        this.databaseRun.evaluatedH1Count = 0;
        this.databaseRun.savedAlertCount = 0;
        this.databaseRun.completedAt = 0;
        this.databaseRun.errorText = "";
    }

    /**
     * Creates canonical execution settings for Run comparison.
     *
     * @return Alert settings, tester model, scope, and symbols.
     */
    string createInputText() {
        string inputText = "h1DisplayWaveEntryLimitEnabled="
            + (string)this.config.h1DisplayWaveEntryLimitEnabled;
        inputText += "|h1W1ConfirmationMode="
            + getH1W1ConfirmationModeText(
                this.config.h1W1ConfirmationMode
            );
        inputText += "|h1DirectionAlignmentMode="
            + getH1DirectionAlignmentModeText(
                this.config.h1DirectionAlignmentMode
            );
        inputText += "|h1Ema200ConfirmationMode="
            + getH1Ema200ConfirmationModeText(
                this.config.h1Ema200ConfirmationMode
            );
        inputText += "|currencyStrengthEnabled="
            + (string)this.config.currencyStrengthEnabled;
        inputText += "|currencyStrengthEntryFilterEnabled="
            + (string)this.config.currencyStrengthEntryFilterEnabled;
        inputText += "|currencyStrengthDatabaseProfile="
            + IntegerToString(
                (int)this.config.currencyStrengthDatabaseProfile
            );
        inputText += "|currencyStrengthVoteWeightMode="
            + IntegerToString(
                (int)this.config.currencyStrengthVoteWeightMode
            );
        inputText += "|executionScope=ALL_28";
        inputText += "|testerModel=1_MINUTE_OHLC";
        inputText += "|oneMinuteOhlcConfirmed="
            + (string)this.oneMinuteOhlcConfirmed;
        inputText += "|testerStartTime="
            + StringFormat("%I64d", (long)this.testerStartTime);
        inputText += "|testerSaveStartTime="
            + StringFormat("%I64d", (long)this.testerSaveStartTime);
        inputText += "|testerExpectedLastH1BarTime="
            + StringFormat(
                "%I64d",
                (long)this.testerExpectedLastH1BarTime
            );
        inputText += "|testerMinimumWarmUpH1Bars="
            + IntegerToString(this.testerMinimumWarmUpH1Bars);
        inputText += "|hostSymbol=" + this.hostSymbolName;

        for (int i = 0; i < this.symbolStates.Total(); i++) {
            Mtf3In3AlertSymbolState *state = this.symbolStates.At(i);
            inputText += "|symbol" + IntegerToString(i) + "=";

            if (state != NULL) {
                inputText += state.symbolName;
            }
        }

        return inputText;
    }

    /**
     * Updates mutable execution progress for the shared Run.
     *
     * @return True when the database row was updated.
     */
    bool persistRunProgress() {
        if (!this.databaseReady
                || this.databaseContext == NULL
                || this.databaseRun.id <= 0) {
            return false;
        }

        ZigZagElliotAlertPersistenceService *persistenceService =
            this.databaseContext.getPersistenceService();

        if (persistenceService == NULL) {
            return false;
        }

        return persistenceService.updateRunExecutionProgress(
            this.databaseRun
        );
    }

    /**
     * Marks the shared Run COMPLETED or FAILED before closing the DB.
     */
    void finalizeRun() {
        if (!this.databaseReady
                || this.databaseContext == NULL
                || this.databaseRun.id <= 0) {
            return;
        }

        if (!this.fatalError && this.hasPendingSnapshots()) {
            this.setFatalError(
                __FUNCTION__,
                "pending Alert snapshot remained at shutdown"
            );
        }

        if (!this.fatalError && this.evaluatedH1Count <= 0) {
            this.setFatalError(
                __FUNCTION__,
                "no all-symbol H1 evaluation completed"
            );
        }

        if (!this.fatalError
                && this.lastCompletedH1BarTime
                    != this.testerExpectedLastH1BarTime) {
            this.setFatalError(
                __FUNCTION__,
                "expected final H1 was not reached expected="
                    + this.formatDateTime(
                        this.testerExpectedLastH1BarTime
                    )
                    + " actual="
                    + this.formatDateTime(this.lastCompletedH1BarTime)
            );
        }

        if (!this.fatalError) {
            this.databaseRun.status = "COMPLETED";
            this.databaseRun.completedAt = TimeLocal();
            this.databaseRun.errorText = "";
        } else {
            this.databaseRun.status = "FAILED";

            if (this.databaseRun.completedAt <= 0) {
                this.databaseRun.completedAt = TimeLocal();
            }

            this.databaseRun.errorText = this.fatalErrorText;
        }

        this.databaseRun.evaluationStartedAt =
            this.evaluationStartedH1BarTime;
        this.databaseRun.lastCompletedH1BarTime =
            this.lastCompletedH1BarTime;
        this.databaseRun.evaluatedH1Count = this.evaluatedH1Count;
        this.databaseRun.savedAlertCount = this.totalSavedCount;
        bool isPersisted = this.persistRunProgress();
        string summary = StringFormat(
            "all-symbol Alert Run finalized. runId=%I64d status=%s evaluationStart=%s lastCompleted=%s expectedLast=%s evaluated=%d saved=%d pending=%d persisted=%d",
            this.databaseRun.id,
            this.databaseRun.status,
            this.formatDateTime(this.evaluationStartedH1BarTime),
            this.formatDateTime(this.lastCompletedH1BarTime),
            this.formatDateTime(this.testerExpectedLastH1BarTime),
            this.evaluatedH1Count,
            this.totalSavedCount,
            this.countPendingSnapshots(),
            (int)isPersisted
        );

        if (this.fatalError || !isPersisted) {
            this.logger.error(__FUNCTION__, summary);
        } else {
            this.logger.info(__FUNCTION__, summary);
        }
    }

    /**
     * Counts staged snapshots that were not saved.
     *
     * @return Number of pending snapshots.
     */
    int countPendingSnapshots() {
        int pendingCount = 0;

        for (int i = 0; i < this.symbolStates.Total(); i++) {
            Mtf3In3AlertSymbolState *state = this.symbolStates.At(i);

            if (state != NULL && state.hasPendingSnapshot) {
                pendingCount++;
            }
        }

        return pendingCount;
    }

    /**
     * Records the first unrecoverable Run integrity error.
     *
     * @param fromMethodName Calling method.
     * @param fromMessage Error detail.
     */
    void setFatalError(
        const string fromMethodName,
        const string fromMessage
    ) {
        if (this.fatalError) {
            return;
        }

        this.fatalError = true;
        this.fatalErrorText = fromMessage;
        this.logger.error(fromMethodName, fromMessage);

        if (this.databaseReady && this.databaseRun.id > 0) {
            this.databaseRun.status = "FAILED";
            this.databaseRun.evaluationStartedAt =
                this.evaluationStartedH1BarTime;
            this.databaseRun.lastCompletedH1BarTime =
                this.lastCompletedH1BarTime;
            this.databaseRun.evaluatedH1Count = this.evaluatedH1Count;
            this.databaseRun.savedAlertCount = this.totalSavedCount;
            this.databaseRun.completedAt = TimeLocal();
            this.databaseRun.errorText = this.fatalErrorText;

            if (!this.persistRunProgress()) {
                this.logger.error(
                    __FUNCTION__,
                    "failed to persist FAILED Run status"
                );
            }
        }
    }

    /**
     * Creates an FNV-1a hash for execution settings.
     *
     * @param fromText Source text.
     * @return Unsigned 64-bit decimal text.
     */
    string createTextHash(const string fromText) {
        ulong hashValue = 14695981039346656037;

        for (int i = 0; i < StringLen(fromText); i++) {
            hashValue ^= (ulong)StringGetCharacter(fromText, i);
            hashValue *= 1099511628211;
        }

        return StringFormat("%I64u", hashValue);
    }

    /**
     * Formats a datetime for logs.
     *
     * @param fromTime Datetime value.
     * @return NONE for zero, otherwise date and seconds.
     */
    string formatDateTime(const datetime fromTime) {
        if (fromTime <= 0) {
            return "NONE";
        }

        return TimeToString(
            fromTime,
            TIME_DATE | TIME_MINUTES | TIME_SECONDS
        );
    }

    /**
     * Releases shared Alert database resources.
     */
    void releaseDatabase() {
        this.databaseReady = false;
        ZeroMemory(this.databaseRun);

        if (this.databaseContext != NULL) {
            this.databaseContext.close();
            delete this.databaseContext;
            this.databaseContext = NULL;
        }
    }
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_ALL_CONTROLLER_MQH
