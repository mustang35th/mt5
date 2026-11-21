#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_EVALUATOR_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_EVALUATOR_MQH

#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorConfig.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorEvaluationObserver.mqh>
#include <Mstng\Indicator\ZigZagElliotMonitor\ZigZagElliotMonitorSymbolState.mqh>

/**
 * 1通貨ずつ通常版M1条件を評価し、分析資源への参照を残さず結果を返す。
 * 判定中の足交代・気配不足は破棄し、同じ足で確認できた判定だけ回数へ反映する。
 */
class ZigZagElliotMonitorEvaluator {
public:
    /**
     * 未初期化状態で作成する。
     */
    ZigZagElliotMonitorEvaluator() {
        this.initialized = false;
        this.evaluationStartedMicros = 0;
    }

    /**
     * M1初期条件の監視設定を保持する。
     *
     * @return 対応する設定で初期化できた場合true。
     */
    bool initialize(ZigZagElliotMonitorConfig &fromConfig) {
        this.destroy();
        if (fromConfig.retrySeconds < 1 || !fromConfig.entryConfig.m1DirectionCorrectionEnabled
                || !fromConfig.entryConfig.currencyStrengthEnabled
                || !fromConfig.entryConfig.currencyStrengthEntryFilterEnabled
                || fromConfig.entryConfig.m1CurrencyStrengthGapDirectionMode
                    != M1_CURRENCY_STRENGTH_GAP_BOTH) {
            return false;
        }

        this.config = fromConfig;
        this.initialized = true;

        return true;
    }

    /**
     * M1新バーまたは同じ足のデータ待機を評価する。
     *
     * @param fromState 呼び出し元が所有する通貨ごとの継続状態。
     * @param fromResult 分析オブジェクトに依存しない今回の結果。
     * @param fromObserver 実際の確認開始を通知する表示担当。省略時は通知しない。
     * @return 今回確認を試みた場合true。完了済み・再試行間隔内はfalse。
     */
    bool evaluate(ZigZagElliotMonitorSymbolState &fromState,
            ZigZagElliotMonitorResult &fromResult,
            ZigZagElliotMonitorEvaluationObserver *fromObserver = NULL) {
        if (!this.initialized) {
            return false;
        }

        ulong nowTick = GetTickCount64();
        datetime currentBarTime = 0;
        if (fromState.symbolName != "") {
            currentBarTime = iTime(fromState.symbolName, PERIOD_M1, 0);
        }

        if (currentBarTime > 0 && currentBarTime == fromState.lastProcessedBarTime) {
            return false;
        }

        bool isNewEvaluationBar = currentBarTime > 0 && currentBarTime != fromState.evaluationBarTime;
        if (!isNewEvaluationBar && nowTick < fromState.nextRetryTick) {
            return false;
        }

        fromState.nextRetryTick = nowTick + (ulong)this.config.retrySeconds * 1000;
        if (isNewEvaluationBar) {
            fromState.evaluationBarTime = currentBarTime;
            fromState.targetM5BarTime = (datetime)((long)currentBarTime - (long)currentBarTime % 300);
        }

        if (fromObserver != NULL) {
            fromObserver.onEvaluationStarted(fromState);
        }

        // 開始表示の描画と後続のチャート起動を、確認処理の計測へ含めない。
        this.evaluationStartedMicros = GetMicrosecondCount();
        fromResult.reset();
        fromResult.barTime = currentBarTime;
        fromResult.targetM5BarTime = fromState.targetM5BarTime;
        if (fromState.symbolName == "") {
            fromResult.status = ZIGZAG_MONITOR_ERROR;
            fromResult.message = "銘柄を解決できません";
            fromResult.shortMessage = "銘柄不明";

            return this.finish(fromState, fromResult);
        }

        if (currentBarTime <= 0) {
            fromResult.message = "M1価格履歴の取得待ち";
            fromResult.shortMessage = "履歴待ち";

            return this.finish(fromState, fromResult);
        }

        MqlTick quote;
        if (!this.getFreshQuote(fromState, quote)) {
            fromResult.message = "最新気配・現在足の更新待ち";
            fromResult.shortMessage = "気配待ち";

            return this.finish(fromState, fromResult);
        }

        if (!this.prepareStrengthProvider(fromState)) {
            fromResult.status = ZIGZAG_MONITOR_ERROR;
            fromResult.message = "通貨属性・順位取得設定を確認してください";
            fromResult.shortMessage = "設定エラー";

            return this.finish(fromState, fromResult);
        }

        CurrencyStrengthExecutionInfo executionInfo;
        bool strengthReady = fromState.strengthProvider.load(fromState.targetM5BarTime, executionInfo);
        // 増減履歴が待機中でも、今回取得できた現在順位は表示へ渡す。
        fromResult.strength.capture(executionInfo, fromState.targetM5BarTime);
        if (!strengthReady) {
            fromResult.message = "同じM5時刻の通貨順位・増減履歴の取得待ち";
            fromResult.shortMessage = "順位待ち";
            if (executionInfo.status == CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR) {
                fromResult.status = ZIGZAG_MONITOR_ERROR;
                fromResult.message = "通貨順位の読み取りエラー（再確認待ち）";
                fromResult.shortMessage = "順位エラー";
            }

            return this.finish(fromState, fromResult);
        }

        // データ取得中に別のM1へ移った場合は、古い順位で確定させない。
        if (!this.getFreshQuote(fromState, quote)) {
            fromResult.message = "取得中に足が更新されました";
            fromResult.shortMessage = "足更新待ち";

            return this.finish(fromState, fromResult);
        }

        if (!fromResult.details.checkStrength(executionInfo)) {
            fromResult.status = ZIGZAG_MONITOR_NOT_MATCHED;
            fromResult.completed = true;
            fromResult.message = "通貨強弱・両期間増減の条件未達";
            fromResult.shortMessage = "強弱未達";

            return this.finish(fromState, fromResult);
        }

        if (!this.prepareHistory(fromState)) {
            fromResult.message = "MN1～M1の分析履歴の準備待ち";
            fromResult.shortMessage = "履歴待ち";

            return this.finish(fromState, fromResult);
        }

        if (!this.prepareAnalysisResources(fromState)) {
            fromResult.status = ZIGZAG_MONITOR_ERROR;
            fromResult.message = "分析資源の作成に失敗しました";
            fromResult.shortMessage = "分析エラー";

            return this.finish(fromState, fromResult);
        }

        string oscillatorWaitingMessage = "";
        if (!this.prepareOscillatorData(fromState, oscillatorWaitingMessage)) {
            fromResult.message = oscillatorWaitingMessage;
            fromResult.shortMessage = "指標待ち";

            return this.finish(fromState, fromResult);
        }

        if (!this.getFreshQuote(fromState, quote)) {
            fromResult.message = "分析開始時の気配・足更新待ち";
            fromResult.shortMessage = "気配待ち";

            return this.finish(fromState, fromResult);
        }

        this.evaluateAnalysis(fromState, executionInfo, quote, fromResult);

        return this.finish(fromState, fromResult);
    }

    /**
     * 評価の受付を停止する。通貨資源はStateが所有する。
     */
    void destroy() {
        this.initialized = false;
        this.evaluationStartedMicros = 0;
    }

private:
    /** 初期化が完了している場合true。 */
    bool initialized;

    /** 開始表示の更新後に記録した、現在の確認処理の開始時刻。 */
    ulong evaluationStartedMicros;

    /** 通常版M1条件と監視の再確認間隔。 */
    ZigZagElliotMonitorConfig config;

    /**
     * 今回の結果を値で確定し、完了したM1だけ処理済みにする。
     */
    bool finish(ZigZagElliotMonitorSymbolState &fromState,
            ZigZagElliotMonitorResult &fromResult) {
        fromResult.evaluatedAtSrv = TimeCurrent();
        fromResult.durationMs = (double)(GetMicrosecondCount() - this.evaluationStartedMicros) / 1000.0;
        if (fromResult.completed && fromResult.barTime > 0) {
            fromState.lastProcessedBarTime = fromResult.barTime;
        }

        return true;
    }

    /**
     * 対象M1・M5が現在枠のままで、30秒以内の有効な気配があるか確認する。
     */
    bool getFreshQuote(ZigZagElliotMonitorSymbolState &fromState, MqlTick &fromQuote) {
        datetime serverTime = TimeTradeServer();
        if (serverTime <= 0) {
            serverTime = TimeCurrent();
        }

        if (fromState.evaluationBarTime <= 0 || serverTime < fromState.evaluationBarTime
                || serverTime >= fromState.evaluationBarTime + 60
                || (datetime)((long)serverTime - (long)serverTime % 300) != fromState.targetM5BarTime
                || iTime(fromState.symbolName, PERIOD_M1, 0) != fromState.evaluationBarTime
                || iTime(fromState.symbolName, PERIOD_M5, 0) != fromState.targetM5BarTime
                || !SymbolInfoTick(fromState.symbolName, fromQuote)) {
            return false;
        }

        return MathIsValidNumber(fromQuote.bid) && MathIsValidNumber(fromQuote.ask)
            && fromQuote.bid > 0.0 && fromQuote.ask >= fromQuote.bid
            && fromQuote.time >= fromState.evaluationBarTime
            && fromQuote.time < fromState.evaluationBarTime + 60
            && fromQuote.time <= serverTime + 2 && serverTime - fromQuote.time <= 30;
    }

    /**
     * 対象に選ばれた通貨の取得先だけを遅延生成する。
     */
    bool prepareStrengthProvider(ZigZagElliotMonitorSymbolState &fromState) {
        if (fromState.strengthProvider != NULL) {
            return true;
        }

        fromState.strengthProvider = new ZigZagElliotMonitorStrengthProvider();
        if (fromState.strengthProvider == NULL) {
            return false;
        }

        if (!fromState.strengthProvider.initialize(fromState.marketContext, this.config.entryConfig)) {
            delete fromState.strengthProvider;
            fromState.strengthProvider = NULL;

            return false;
        }

        return true;
    }

    /**
     * 不足している系列だけ履歴取得を要求し、不完全な分析を開始しない。
     */
    bool prepareHistory(ZigZagElliotMonitorSymbolState &fromState) {
        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1
        };
        bool ready = true;
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            int requiredBars = 206;
            if (timeFrames[i] == PERIOD_MN1) {
                requiredBars = 61;
            }

            if (SeriesInfoInteger(fromState.symbolName, timeFrames[i], SERIES_SYNCHRONIZED)
                    && Bars(fromState.symbolName, timeFrames[i]) >= requiredBars) {
                continue;
            }

            MqlRates rates[];
            if (CopyRates(fromState.symbolName, timeFrames[i], 0, requiredBars, rates) < requiredBars
                    || !SeriesInfoInteger(fromState.symbolName, timeFrames[i], SERIES_SYNCHRONIZED)) {
                ready = false;
            }
        }

        return ready;
    }

    /**
     * 条件候補に限って通貨別の回数管理とハンドルを生成する。
     */
    bool prepareAnalysisResources(ZigZagElliotMonitorSymbolState &fromState) {
        if (fromState.signalCount == NULL) {
            fromState.signalCount = new SignalCount(fromState.marketContext);
        }

        if (fromState.oscillatorHandlePool == NULL) {
            fromState.oscillatorHandlePool = new OscillatorHandlePool(fromState.marketContext);
            if (fromState.oscillatorHandlePool != NULL) {
                fromState.oscillatorHandlePool.setTimeframesFromMn1To();
            }
        }

        return fromState.signalCount != NULL && fromState.oscillatorHandlePool != NULL;
    }

    /**
     * 全分析時間足の指標計算を確認し、未準備ならハンドルを保持して次回へ待つ。
     * 価格履歴の同期だけでは指標バッファの計算完了を保証できない。
     */
    bool prepareOscillatorData(ZigZagElliotMonitorSymbolState &fromState, string &fromWaitingMessage) {
        fromWaitingMessage = "";
        OscillatorHandlePool *pool = fromState.oscillatorHandlePool;
        if (pool == NULL) {
            fromWaitingMessage = "指標ハンドルの準備待ち";

            return false;
        }

        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1
        };
        string labels[] = {"Stochastic短期", "Stochastic中期", "Stochastic長期", "GMMA30", "GMMA60", "ATR", "EMA200"};
        bool ready = true;
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            int bars = Bars(fromState.symbolName, timeFrames[i]);
            if (bars <= 0) {
                if (fromWaitingMessage == "") {
                    fromWaitingMessage = TimeUtil::convertTimeFrameToString(timeFrames[i]) + " 価格履歴の準備待ち";
                }

                ready = false;
                continue;
            }

            int stochasticBars = (int)MathMin(bars, ZigZagElliotAnalysisProfile::getStochasticLookback() + 1);
            int gmmaLookback = (int)MathMax(ZigZagElliotAnalysisProfile::getGmmaTrendLookback(),
                ZigZagElliotAnalysisProfile::getGmmaCrossLookback());
            int gmmaBars = (int)MathMin(bars, gmmaLookback + 1);
            int emaBars = (int)MathMax(ZigZagElliotAnalysisProfile::getEma200CompareBarIndex(),
                ZigZagElliotAnalysisProfile::getEma200CloseShift() + ZigZagElliotAnalysisProfile::getEma200CountBars()) + 1;
            bool skipEma = timeFrames[i] == PERIOD_MN1 && ZigZagElliotAnalysisProfile::isEma200SkippedForMn1();
            int handles[7];
            handles[0] = pool.getStochasticShortHandlePool().getHandle(timeFrames[i]);
            handles[1] = pool.getStochasticMiddleHandlePool().getHandle(timeFrames[i]);
            handles[2] = pool.getStochasticLongHandlePool().getHandle(timeFrames[i]);
            handles[3] = pool.getGmmaHandlePool().getEma30Handle(timeFrames[i]);
            handles[4] = pool.getGmmaHandlePool().getEma60Handle(timeFrames[i]);
            handles[5] = pool.getAverageTrueRangeHandlePool().getHandle(timeFrames[i]);
            handles[6] = INVALID_HANDLE;
            if (!skipEma) {
                handles[6] = pool.getEma200HandlePool().getEma200Handle(timeFrames[i]);
            }

            // 最初の未準備で終了せず、他のハンドルも同じ回で計算を促す。
            for (int j = 0; j < ArraySize(handles); j++) {
                if (j == 6 && skipEma) {
                    continue;
                }

                int requiredBars = 1;
                int bufferCount = 1;
                if (j < 3) {
                    requiredBars = stochasticBars;
                    bufferCount = 2;
                } else if (j < 5) {
                    requiredBars = gmmaBars;
                } else if (j == 6) {
                    requiredBars = emaBars;
                }

                string detail = "";
                if (!this.isIndicatorDataReady(handles[j], bufferCount, requiredBars, detail)) {
                    if (fromWaitingMessage == "") {
                        fromWaitingMessage = TimeUtil::convertTimeFrameToString(timeFrames[i])
                            + " " + labels[j] + " " + detail;
                    }

                    ready = false;
                }
            }
        }

        return ready;
    }

    /**
     * 必要範囲の計算済み本数と、各バッファの最新値を確認する。
     * 計算不足は1本の取得で非同期計算を促し、同じイベントでは待ち続けない。
     */
    bool isIndicatorDataReady(const int fromHandle, const int fromBufferCount,
            const int fromRequiredBars, string &fromDetail) {
        fromDetail = "";
        if (fromHandle == INVALID_HANDLE || fromRequiredBars <= 0) {
            fromDetail = "ハンドルの準備待ち";

            return false;
        }

        int calculatedBars = BarsCalculated(fromHandle);
        double probe[1];
        if (calculatedBars < fromRequiredBars) {
            ResetLastError();
            if (CopyBuffer(fromHandle, 0, 0, 1, probe) != 1) {
                fromDetail = "計算準備待ち code=" + IntegerToString(GetLastError());

                return false;
            }

            fromDetail = "計算準備待ち " + IntegerToString(calculatedBars) + "/" + IntegerToString(fromRequiredBars);

            return false;
        }

        for (int i = 0; i < fromBufferCount; i++) {
            ResetLastError();
            if (CopyBuffer(fromHandle, i, 0, 1, probe) != 1) {
                fromDetail = "データ取得待ち code=" + IntegerToString(GetLastError());

                return false;
            }

            if (!MathIsValidNumber(probe[0]) || probe[0] == EMPTY_VALUE) {
                fromDetail = "有効値の計算待ち";

                return false;
            }
        }

        return true;
    }

    /**
     * 通常版と同じM1専用クラスを、描画・メール経路なしで生成する。
     */
    ExpertAdvisorMTF_3in3 *createStrategy(MarketContext &fromMarketContext) {
        return ExpertAdvisorMtf3In3Factory::create(
            fromMarketContext, false,
            this.config.entryConfig.h1W1ConfirmationMode,
            this.config.entryConfig.h1DirectionAlignmentMode,
            this.config.entryConfig.h1Ema200ConfirmationMode,
            this.config.entryConfig.h1DirectionCorrectionEnabled,
            this.config.entryConfig.m15H4MaxFibonacciExpansionPercent,
            this.config.entryConfig.m15H1MaxFibonacciExpansionPercent,
            this.config.entryConfig.h1Mn1AndW1Ema200Required,
            this.config.entryConfig.h1H4WaveRestrictionEnabled,
            this.config.entryConfig.m5Mn1AndW1Ema200Required,
            this.config.entryConfig.m5D1ToM5EntryPolicyEnabled,
            this.config.entryConfig.m5CurrencyStrengthMinimumRankDifference,
            this.config.entryConfig.m15CurrencyEma200DistanceEnabled,
            this.config.entryConfig.m15LongMediumCurrencyStrengthEnabled,
            true, this.config.entryConfig.m1DirectionCorrectionEnabled
        );
    }

    /**
     * 元分析と補正分析を評価中だけ保持し、対象足が変わっていない結果だけ採用する。
     */
    void evaluateAnalysis(ZigZagElliotMonitorSymbolState &fromState,
            CurrencyStrengthExecutionInfo &fromExecutionInfo, const MqlTick &fromQuote,
            ZigZagElliotMonitorResult &fromResult) {
        ElliotAll *original = new ElliotAll(fromState.marketContext);
        ExpertAdvisorMTF_3in3 *strategy = this.createStrategy(fromState.marketContext);
        if (original == NULL || strategy == NULL) {
            if (strategy != NULL) {
                delete strategy;
            }

            if (original != NULL) {
                delete original;
            }

            fromResult.status = ZIGZAG_MONITOR_ERROR;
            fromResult.message = "M1判定の作成に失敗しました";
            fromResult.shortMessage = "分析エラー";
            return;
        }

        original.isTimer = true;
        original.timerSeconds = this.config.retrySeconds;
        original.isSendMail = false;
        original.isMailValidationFileEnabled = false;
        original.isH1DisplayWaveEntryLimitEnabled = false;
        original.isCurrencyStrengthEntryFilterEnabled = true;
        original.setAnalysisStartTimeFrame(ZigZagElliotAnalysisProfile::getAnalysisStartTimeFrame());
        original.setOscillatorHandlePool(fromState.oscillatorHandlePool);
        original.setCurrencyStrengthExecutionInfo(fromExecutionInfo);

        if (!original.analyze(fromQuote) || original.elliotCurrent == NULL
                || original.elliotCurrent.getLatestPoint2() == NULL) {
            fromResult.message = "波動・オシレーターの分析準備待ち";
            fromResult.shortMessage = "分析待ち";
        } else if (!this.isEvaluationStable(fromState, original)) {
            fromResult.message = "分析対象の足・気配の再確認待ち";
            fromResult.shortMessage = "再確認待ち";
        } else {
            datetime signalTime = original.elliotCurrent.getLatestPoint2().barTime;
            bool signalIsBuy = original.elliotCurrent.isBuy;
            SignalCount provisionalCount(fromState.marketContext);
            strategy.analyze(original, GetPointer(provisionalCount));
            Mtf3In3AlertResult alertResult = strategy.getAlertResult();

            // 補正再分析も終了してから確認し、破棄する評価は本物の回数を消費しない。
            if (!this.isEvaluationStable(fromState, original)) {
                fromResult.message = "判定中の足交代・気配不足（再確認待ち）";
                fromResult.shortMessage = "再確認待ち";
            } else if (strategy.isJudgmentPreparationPending()) {
                fromResult.status = ZIGZAG_MONITOR_WAITING;
                fromResult.completed = false;
                fromResult.message = "補正分析の準備待ち（再確認します）";
                fromResult.shortMessage = "補正待ち";
            } else {
                fromResult.directions.capture(original, strategy.getJudgmentElliotAll(), fromResult.barTime,
                    strategy.getCorrectionTimeFrame());
                fromResult.waves.capture(strategy.getJudgmentElliotAll(), fromResult.barTime,
                    strategy.getCorrectionTimeFrame());

                fromResult.details.capture(strategy.getJudgmentElliotAll(), strategy.getJudgeStep(),
                    fromExecutionInfo.isDirectionAligned(signalIsBuy));
                fromResult.signalTime = signalTime;
                fromResult.isBuy = signalIsBuy;
                fromResult.status = ZIGZAG_MONITOR_NOT_MATCHED;
                fromResult.completed = true;
                fromResult.message = "M1エントリー条件未達";
                fromResult.shortMessage = "M1未達";
                if (alertResult.isJudge) {
                    int signalCount = fromState.signalCount.addCount(signalTime, signalIsBuy);
                    fromResult.details.signalCount = signalCount;
                    if (signalCount == 1 && alertResult.isEntry) {
                        fromResult.status = ZIGZAG_MONITOR_ENTRY;
                        fromResult.message = strategy.getJudgmentAlertText();
                        fromResult.shortMessage = "ENTRY";
                    } else if (signalCount > 1) {
                        fromResult.message = "同一シグナルは確認済み";
                        fromResult.shortMessage = "確認済み";
                    }
                }
            }
        }

        // 補正分析を先に解放し、元分析と借用ハンドルの寿命を守る。
        delete strategy;
        delete original;
    }

    /**
     * 対象M1・M5枠、最新気配の鮮度と元分析の参照・時刻を確認する。
     * 同じ足の通常のティック変動は許容し、採用した開始時気配で判定する。
     * 補正再分析の内部にある元OHLC照合は、既存クラスの規則を維持する。
     */
    bool isEvaluationStable(ZigZagElliotMonitorSymbolState &fromState,
            ElliotAll *fromOriginal) {
        MqlTick currentQuote;
        if (fromOriginal == NULL || !fromOriginal.isAnalysisSucceeded
                || fromOriginal.marketContext.symbolName != fromState.symbolName
                || fromOriginal.marketContext.timeFrame != PERIOD_M1
                || fromOriginal.elliotCurrent == NULL
                || fromOriginal.elliotCurrent != fromOriginal.getElliot(PERIOD_M1)
                || !this.getFreshQuote(fromState, currentQuote)) {
            return false;
        }

        ENUM_TIMEFRAMES timeFrames[] = {
            PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5, PERIOD_M1
        };
        for (int i = 0; i < ArraySize(timeFrames); i++) {
            Elliot *elliot = fromOriginal.getElliot(timeFrames[i]);
            if (elliot == NULL || elliot.getLatestPoint() == NULL || elliot.getLatestWave() == NULL
                    || elliot.marketContext.symbolName != fromState.symbolName
                    || elliot.marketContext.timeFrame != timeFrames[i]
                    || elliot.currentOhlcBarTime <= 0 || elliot.previousOhlcBarTime <= 0
                    || elliot.previousOhlcBarTime >= elliot.currentOhlcBarTime) {
                return false;
            }

            if ((timeFrames[i] == PERIOD_M1 && elliot.currentOhlcBarTime != fromState.evaluationBarTime)
                    || (timeFrames[i] == PERIOD_M5 && elliot.currentOhlcBarTime != fromState.targetM5BarTime)) {
                return false;
            }
        }

        return this.getFreshQuote(fromState, currentQuote);
    }
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_EVALUATOR_MQH
