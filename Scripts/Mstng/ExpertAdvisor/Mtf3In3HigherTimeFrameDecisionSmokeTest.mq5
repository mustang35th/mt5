#property version "1.01"

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3M5.mqh>
#include <Mstng\ExpertAdvisor\H1DirectionAlignmentDecision.mqh>
#include <Mstng\ExpertAdvisor\H1Ema200ConfirmationDecision.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3HigherTimeFrameDecision.mqh>

/**
 * M5固有の上位足ゲートだけを検証する。
 */
class M5HigherProbe : public ExpertAdvisorMtf3In3M5 {
public:
    /**
     * テスト用市場で初期化する。
     */
    M5HigherProbe(MarketContext &fromContext, bool fromRequireMn1AndW1Ema200 = false,
        bool fromD1ToM5EntryPolicyEnabled = false)
        : ExpertAdvisorMtf3In3M5(fromContext, false, fromRequireMn1AndW1Ema200,
            fromD1ToM5EntryPolicyEnabled) {
    }

    /**
     * 発注やSignal Countを操作せず上位足ゲートを呼ぶ。
     */
    bool evaluate(ElliotAll *fromAll) {
        this.elliotAll = fromAll;
        this.isBuy = true;
        if (fromAll != NULL && fromAll.elliotCurrent != NULL) {
            this.isBuy = fromAll.elliotCurrent.isBuy;
        }

        return this.isTimeFrameDirectionAlignmentConditionMatched();
    }

    /**
     * M5固有のEMA200ゲートを注文なしで呼ぶ。
     */
    bool evaluateEma(ElliotAll *fromAll, const bool fromIsBuy) {
        this.elliotAll = fromAll;
        this.isBuy = fromIsBuy;
        return this.isTimeFrameEma200ConditionMatched();
    }

    /**
     * M5固有の分析方向ゲートを注文なしで呼ぶ。
     */
    bool evaluateDirection(ElliotAll *fromAll, const bool fromIsBuy) {
        this.elliotAll = fromAll;
        this.isBuy = fromIsBuy;

        return this.isTimeFrameAnalysisDirectionConditionMatched();
    }

    /**
     * 本番の分析選択を呼び、元分析を補正せず使用することを検証する。
     */
    ElliotAll *selectOriginal(ElliotAll *fromAll) {
        return this.selectJudgmentElliotAll(fromAll);
    }

    /**
     * 主波条件を回数加算なしで確認する。
     */
    bool evaluateWaves(ElliotAll *fromAll) {
        this.elliotAll = fromAll;
        this.elliotCurrent = NULL;
        if (fromAll != NULL) {
            this.elliotCurrent = fromAll.elliotCurrent;
        }

        return this.isTimeFrameWaveConditionMatched();
    }
};

/**
 * 補正snapshotの選択だけを置き換え、実際のM5判定と回数管理を検証する。
 */
class M5EntryFixtureProbe : public ExpertAdvisorMtf3In3M5 {
public:
    /**
     * AND判定と呼び出し側が所有する補正fixtureを設定する。
     */
    M5EntryFixtureProbe(
        MarketContext &fromContext,
        ElliotAll *fromJudgment = NULL,
        ENUM_TIMEFRAMES fromCorrectionTimeFrame = PERIOD_CURRENT
    ) : ExpertAdvisorMtf3In3M5(fromContext, false, true) {
        this.judgmentFixture = fromJudgment;
        this.correctionTimeFrame = fromCorrectionTimeFrame;
    }

    /**
     * 合成した補正分析を採用した場合だけ補正時間足を返す。
     */
    virtual ENUM_TIMEFRAMES getCorrectionTimeFrame() override {
        if (this.judgmentFixture != NULL && this.elliotAll == this.judgmentFixture) {
            return this.correctionTimeFrame;
        }

        return ExpertAdvisorMtf3In3M5::getCorrectionTimeFrame();
    }

protected:
    /**
     * fixture未指定時は実際の補正前分析選択を使用する。
     */
    virtual ElliotAll *selectJudgmentElliotAll(ElliotAll *fromOriginal) override {
        if (this.judgmentFixture != NULL) {
            return this.judgmentFixture;
        }

        return ExpertAdvisorMtf3In3M5::selectJudgmentElliotAll(fromOriginal);
    }

private:
    /** 呼び出し側が所有する補正後分析。 */
    ElliotAll *judgmentFixture;

    /** 合成した分析で補正した時間足。 */
    ENUM_TIMEFRAMES correctionTimeFrame;
};

/**
 * 分析方向とEMA200方向を設定する。EMAの0はNONE、1はBUY、2はSELL。
 */
void setState(Elliot *fromElliot, const bool fromIsBuy, const int fromEma) {
    fromElliot.isBuy = fromIsBuy;
    fromElliot.oscillator.isBuy = fromIsBuy;
    fromElliot.buySellLabel = "SELL";
    if (fromIsBuy) {
        fromElliot.buySellLabel = "BUY";
    }
    fromElliot.oscillator.ema200.isBuy = fromEma == 1;
    fromElliot.oscillator.ema200.isSell = fromEma == 2;
    fromElliot.oscillator.ema200.buySellLabel = "NONE";
    if (fromEma == 1) {
        fromElliot.oscillator.ema200.buySellLabel = "BUY";
    } else if (fromEma == 2) {
        fromElliot.oscillator.ema200.buySellLabel = "SELL";
    }
}

/**
 * MN1からM5までの最小分析結果を作成する。
 */
ElliotAll *createAll() {
    ElliotAll *elliotAll = new ElliotAll("EURUSD", PERIOD_M5);
    ENUM_TIMEFRAMES frames[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1,
        PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
    for (int i = 0; i < ArraySize(frames); i++) {
        Elliot *elliot = new Elliot("EURUSD", frames[i]);
        setState(elliot, true, 1);
        elliotAll.elliotList.Add(elliot);
    }
    elliotAll.elliotCurrent = elliotAll.getElliot(PERIOD_M5);
    elliotAll.isAnalysisSucceeded = true;
    return elliotAll;
}

/**
 * 失敗を集計し、ケース名と理由を出力する。
 */
void check(const bool fromPassed, const string fromName, int &fromFailures) {
    if (!fromPassed) {
        Print("FAIL " + fromName);
        fromFailures++;
    }
}

/**
 * BUY/SELL、MN1/W1/D1/H4、EMA NONE/BUY/SELLの全組み合わせを確認する。
 * H1の方向・EMA判定を合成した結果と、共通条件の結果を照合する。
 */
void validateCombinations(int &fromFailures) {
    Mtf3In3HigherTimeFrameDecision common;
    H1DirectionAlignmentDecision direction;
    H1Ema200ConfirmationDecision ema;
    MarketContext context("EURUSD", PERIOD_M5);
    M5HigherProbe probe(context);
    M5HigherProbe andProbe(context, true);
    ElliotAll *elliotAll = createAll();
    for (int i = 0; i < 32; i++) {
        bool isBuy = (i & 1) != 0;
        bool isMn1Buy = (i & 2) != 0;
        bool isW1Buy = (i & 4) != 0;
        bool isD1Buy = (i & 8) != 0;
        bool isH4Buy = (i & 16) != 0;
        int matchingEma = 2;
        if (isBuy) {
            matchingEma = 1;
        }
        for (int j = 0; j < 3; j++) {
            for (int k = 0; k < 3; k++) {
                setState(elliotAll.getElliot(PERIOD_MN1), isMn1Buy, 0);
                setState(elliotAll.getElliot(PERIOD_W1), isW1Buy, j);
                setState(elliotAll.getElliot(PERIOD_D1), isD1Buy, k);
                setState(elliotAll.getElliot(PERIOD_H4), isH4Buy, matchingEma);
                setState(elliotAll.getElliot(PERIOD_H1), isBuy, matchingEma);
                setState(elliotAll.getElliot(PERIOD_M5), isBuy, matchingEma);
                elliotAll.elliotCurrent = elliotAll.getElliot(PERIOD_M5);
                string reason;
                bool expected = isW1Buy == isBuy && isD1Buy == isBuy
                    && (isMn1Buy == isBuy || j == matchingEma) && k == matchingEma;
                bool actual = common.evaluate(elliotAll, isBuy, reason);
                string caseName = StringFormat("combination %d/%d/%d %s", i, j, k, reason);
                check(actual == expected, caseName, fromFailures);
                check((reason == "") == actual, caseName + " reason", fromFailures);
                check(probe.evaluate(elliotAll) == expected, caseName + " M5 gate", fromFailures);
                check(andProbe.evaluate(elliotAll)
                    == (expected && isMn1Buy == isBuy && j == matchingEma),
                    caseName + " M5 AND gate", fromFailures);
                elliotAll.elliotCurrent = elliotAll.getElliot(PERIOD_H1);
                elliotAll.marketContext.timeFrame = PERIOD_H1;
                H1DirectionAlignmentResult result;
                bool h1Passed = direction.evaluate(
                    H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
                    elliotAll, result) && ema.evaluate(
                    H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED, isBuy,
                    elliotAll.getElliot(PERIOD_H1), elliotAll.getElliot(PERIOD_H4),
                    elliotAll.getElliot(PERIOD_D1));
                check(h1Passed == (expected && isH4Buy == isBuy), caseName + " H1", fromFailures);
                elliotAll.marketContext.timeFrame = PERIOD_M5;
            }
        }
    }
    delete elliotAll;
}

/**
 * 欠損、不正な時間足・ラベル、両方向成立、0方向を拒否する。
 */
void validateInvalid(int &fromFailures) {
    Mtf3In3HigherTimeFrameDecision common;
    MarketContext context("EURUSD", PERIOD_M5);
    M5HigherProbe andProbe(context, true);
    string reason;
    check(!common.evaluate(NULL, true, reason), "null analysis", fromFailures);
    check(!andProbe.evaluate(NULL), "AND null analysis", fromFailures);
    for (int i = 0; i < 11; i++) {
        ElliotAll *elliotAll = createAll();
        Elliot *elliotW1 = elliotAll.getElliot(PERIOD_W1);
        Elliot *elliotD1 = elliotAll.getElliot(PERIOD_D1);
        if (i == 0) {
            elliotAll.isAnalysisSucceeded = false;
        } else if (i == 1) {
            elliotAll.elliotList.Delete(0);
        } else if (i == 2) {
            elliotW1.oscillator.ema200.isSell = true;
        } else if (i == 3) {
            elliotW1.oscillator.ema200.buySellLabel = "SELL";
        } else if (i == 4) {
            elliotD1.oscillator.ema200.marketContext.timeFrame = PERIOD_H4;
        } else if (i == 5) {
            elliotD1.oscillator.ema200.isSell = true;
        } else if (i == 6) {
            elliotW1.oscillator.isBuy = false;
        } else if (i == 7) {
            elliotAll.getElliot(PERIOD_MN1).buySellLabel = "NONE";
        } else if (i == 8) {
            elliotAll.elliotCurrent = NULL;
        } else if (i == 9) {
            setState(elliotD1, true, 0);
        } else {
            elliotAll.elliotCurrent.buySellLabel = "SELL";
        }
        check(!common.evaluate(elliotAll, true, reason) && reason != "",
            StringFormat("invalid %d", i), fromFailures);
        check(!andProbe.evaluate(elliotAll), StringFormat("AND invalid %d", i), fromFailures);
        delete elliotAll;
    }
}

/**
 * 上位足共通化の回帰テストを実行する。注文・DB更新は行わない。
 */
void validateEma(int &fromFailures) {
    MarketContext context("EURUSD", PERIOD_M5);
    M5HigherProbe probe(context);
    ENUM_TIMEFRAMES frames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        int matchingEma = 2;
        if (isBuy) {
            matchingEma = 1;
        }
        for (int j = 0; j < 243; j++) {
            ElliotAll *elliotAll = createAll();
            int combination = j;
            bool expected = true;
            for (int k = 0; k < ArraySize(frames); k++) {
                int ema = combination % 3;
                combination /= 3;
                setState(elliotAll.getElliot(frames[k]), isBuy, ema);
                expected = expected && ema == matchingEma;
            }
            check(probe.evaluateEma(elliotAll, isBuy) == expected,
                StringFormat("EMA5 %d/%d", i, j), fromFailures);
            delete elliotAll;
        }
    }
    check(!probe.evaluateEma(NULL, true), "EMA5 null analysis", fromFailures);
}

/**
 * 相場取得、メール送信、共有ファイル出力をせずM5公開ENTRY経路のfixtureを作る。
 */
ElliotAll *createEntryAll(const bool fromIsBuy, const string fromLabel = "3") {
    ElliotAll *analysis = createAll();
    if (analysis == NULL) {
        return NULL;
    }

    int matchingEma = 2;
    int gmmaCount = -2;
    if (fromIsBuy) {
        matchingEma = 1;
        gmmaCount = 2;
    }

    for (int i = 0; i < analysis.elliotList.Total(); i++) {
        Elliot *elliot = analysis.elliotList.At(i);
        setState(elliot, fromIsBuy, matchingEma);
        elliot.oscillator.gmmaTrendCount = gmmaCount;
        elliot.oscillator.gmmaCrossCount = gmmaCount;
        CArrayObj points;
        for (int j = 0; j <= 3; j++) {
            ZigZagPoint *point = new ZigZagPoint(elliot.marketContext);
            if (point == NULL || !points.Add(point)) {
                if (point != NULL) {
                    delete point;
                }

                delete analysis;

                return NULL;
            }

            point.elliotIndex = j;
            point.isElliotAlphabet = false;
            point.setElliotLabel();
            point.isAddedPoint = false;
            point.barTime = D'2026.10.01 00:00' + j * 300;
            point.fibonacciExpansionPercent = 140.0;
        }

        Wave *wave = new Wave(elliot.marketContext, points, true, fromIsBuy);
        if (wave == NULL || !elliot.waveList.Add(wave)) {
            if (wave != NULL) {
                delete wave;
            }

            delete analysis;

            return NULL;
        }
    }

    if (fromLabel == "C") {
        analysis.elliotCurrent.getLatestPoint().isElliotAlphabet = true;
        analysis.elliotCurrent.getLatestPoint().setElliotLabel();
        analysis.elliotCurrent.getLatestWave().isMotive = false;
    }

    analysis.isTimer = false;
    analysis.isSendMail = false;
    analysis.isMailValidationFileEnabled = false;
    analysis.isCurrencyStrengthEntryFilterEnabled = false;
    analysis.isH1DisplayWaveEntryLimitEnabled = false;
    analysis.todayRate.spread = 5.0;

    return analysis;
}

/**
 * ANDの片側不成立では回数を消費せず、同一起点の回復時に初回ENTRYする。
 */
void validateAndWaitAndRetry(int &fromFailures) {
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        int matchingEma = 2;
        if (isBuy) {
            matchingEma = 1;
        }

        for (int j = 0; j < 2; j++) {
            string caseName = StringFormat("M5 AND wait %d/%d", i, j);
            ElliotAll *analysis = createEntryAll(isBuy);
            if (analysis == NULL) {
                check(false, caseName + " fixture", fromFailures);
                continue;
            }

            if (j == 0) {
                setState(analysis.getElliot(PERIOD_MN1), !isBuy, matchingEma);
            } else {
                setState(analysis.getElliot(PERIOD_W1), isBuy, 3 - matchingEma);
            }

            MarketContext context("EURUSD", PERIOD_M5);
            SignalCount signalCount(context);
            M5EntryFixtureProbe probe(context);
            probe.analyze(analysis, GetPointer(signalCount));
            Mtf3In3AlertResult result = probe.getAlertResult();
            check(!result.isJudge && result.signalCount == 0,
                caseName + " no count", fromFailures);
            setState(analysis.getElliot(PERIOD_MN1), isBuy, matchingEma);
            setState(analysis.getElliot(PERIOD_W1), isBuy, matchingEma);
            probe.analyze(analysis, GetPointer(signalCount));
            result = probe.getAlertResult();
            check(result.isEntry && result.signalCount == 1,
                caseName + " first entry", fromFailures);
            probe.analyze(analysis, GetPointer(signalCount));
            check(!probe.isEntry, caseName + " duplicate", fromFailures);
            delete analysis;
        }
    }
}

/**
 * H4・H1補正snapshotでもANDを判定し、上位条件の復旧後だけ初回ENTRYする。
 */
void validateCorrectedAndWait(int &fromFailures) {
    ENUM_TIMEFRAMES correctionFrames[] = {PERIOD_H4, PERIOD_H1};
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        int matchingEma = 2;
        if (isBuy) {
            matchingEma = 1;
        }

        for (int j = 0; j < ArraySize(correctionFrames); j++) {
            string caseName = StringFormat("M5 corrected AND %d/%d", i, j);
            ElliotAll *original = createEntryAll(isBuy);
            ElliotAll *selected = createEntryAll(isBuy);
            if (original == NULL || selected == NULL) {
                check(false, caseName + " fixture", fromFailures);
                delete original;
                delete selected;
                continue;
            }

            setState(original.getElliot(correctionFrames[j]), !isBuy, matchingEma);
            selected.getElliot(correctionFrames[j]).oscillator.isBuy = !isBuy;
            setState(selected.getElliot(PERIOD_MN1), !isBuy, matchingEma);
            MarketContext context("EURUSD", PERIOD_M5);
            SignalCount signalCount(context);
            M5EntryFixtureProbe probe(context, selected, correctionFrames[j]);
            probe.analyze(original, GetPointer(signalCount));
            Mtf3In3AlertResult result = probe.getAlertResult();
            check(!result.isJudge && result.signalCount == 0,
                caseName + " MN1 wait", fromFailures);
            setState(selected.getElliot(PERIOD_MN1), isBuy, matchingEma);
            setState(selected.getElliot(PERIOD_W1), isBuy, 3 - matchingEma);
            probe.analyze(original, GetPointer(signalCount));
            result = probe.getAlertResult();
            check(!result.isJudge && result.signalCount == 0,
                caseName + " W1 EMA wait", fromFailures);
            setState(selected.getElliot(PERIOD_W1), isBuy, matchingEma);
            probe.analyze(original, GetPointer(signalCount));
            result = probe.getAlertResult();
            check(result.isEntry && result.signalCount == 1,
                caseName + " first entry", fromFailures);
            check(probe.getCorrectionTimeFrame() == correctionFrames[j]
                && probe.getJudgmentElliotAll() == selected,
                caseName + " selected snapshot", fromFailures);
            delete original;
            delete selected;
        }
    }
}

/**
 * M5第3波・C波のFE拒否は初回を消費し、同一起点のFE回復ではENTRYしない。
 */
void validateFibonacciConsumesFirstCount(int &fromFailures) {
    string labels[] = {"3", "C"};
    double rejectedValues[] = {200.0, 0.0, EMPTY_VALUE};
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < ArraySize(labels); j++) {
            for (int k = 0; k < ArraySize(rejectedValues); k++) {
                string caseName = StringFormat("M5 FE count %d/%d/%d", i, j, k);
                ElliotAll *analysis = createEntryAll(i == 0, labels[j]);
                if (analysis == NULL) {
                    check(false, caseName + " fixture", fromFailures);
                    continue;
                }

                ZigZagPoint *point = analysis.elliotCurrent.getLatestPoint();
                point.fibonacciExpansionPercent = rejectedValues[k];
                MarketContext context("EURUSD", PERIOD_M5);
                SignalCount signalCount(context);
                M5EntryFixtureProbe probe(context);
                probe.analyze(analysis, GetPointer(signalCount));
                Mtf3In3AlertResult result = probe.getAlertResult();
                check(result.isJudge && result.isEntryEvaluated && !result.isEntry
                    && result.signalCount == 1,
                    caseName + " first consumed", fromFailures);
                string expectedReason = "M5_ELLIOT" + labels[j] + "_FE_REJECTED";
                check(result.entryResult == expectedReason, caseName + " FE reason", fromFailures);
                point.fibonacciExpansionPercent = 140.0;
                probe.analyze(analysis, GetPointer(signalCount));
                result = probe.getAlertResult();
                check(!result.isEntry && !result.isEntryEvaluated && result.signalCount == 2,
                    caseName + " same origin blocked", fromFailures);
                analysis.elliotCurrent.getLatestPoint2().barTime += 300;
                probe.analyze(analysis, GetPointer(signalCount));
                result = probe.getAlertResult();
                check(result.isEntry && result.signalCount == 1,
                    caseName + " new origin entry", fromFailures);
                delete analysis;
            }
        }
    }
}

/**
 * D1～M5の方向一致とH1～M5のEMA200一致を、BUY/SELL両方向で検証する。
 * MN1/W1およびD1/H4のEMA200は逆方向・NONEでも判定対象外とする。
 */
void validateD1ToM5Policy(int &fromFailures) {
    MarketContext context("EURUSD", PERIOD_M5);
    M5HigherProbe probe(context, true, true);
    ENUM_TIMEFRAMES frames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
    check(!probe.evaluateDirection(NULL, true), "D1-M5 null direction", fromFailures);
    check(!probe.evaluateEma(NULL, true), "EMA3 null analysis", fromFailures);
    check(probe.selectOriginal(NULL) == NULL, "D1-M5 null selection", fromFailures);
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        int matchingEma = 2;
        if (isBuy) {
            matchingEma = 1;
        }

        for (int j = 0; j < ArraySize(frames); j++) {
            ElliotAll *analysis = createEntryAll(isBuy);
            Elliot *changed = analysis.getElliot(frames[j]);
            string caseName = StringFormat("D1-M5 direction %d/%d", i, j);
            check(probe.evaluateDirection(analysis, isBuy), caseName + " aligned", fromFailures);
            setState(changed, !isBuy, matchingEma);
            check(probe.selectOriginal(analysis) == analysis
                && probe.getCorrectionTimeFrame() == PERIOD_CURRENT,
                caseName + " original selected without correction", fromFailures);
            check(!probe.evaluateDirection(analysis, isBuy), caseName + " opposite rejected", fromFailures);
            setState(changed, isBuy, matchingEma);
            changed.oscillator.isBuy = !isBuy;
            check(!probe.evaluateDirection(analysis, isBuy), caseName + " inconsistent rejected", fromFailures);
            setState(changed, isBuy, matchingEma);
            changed.buySellLabel = "NONE";
            check(!probe.evaluateDirection(analysis, isBuy), caseName + " NONE rejected", fromFailures);
            if (frames[j] == PERIOD_M5) {
                analysis.elliotCurrent = NULL;
            }

            analysis.elliotList.Delete(j + 2);
            check(!probe.evaluateDirection(analysis, isBuy), caseName + " missing rejected", fromFailures);
            if (j >= 2) {
                check(!probe.evaluateEma(analysis, isBuy), caseName + " missing EMA rejected", fromFailures);
            }

            delete analysis;
        }

        for (int j = 0; j < 243; j++) {
            ElliotAll *analysis = createEntryAll(isBuy);
            int combination = j;
            bool expected = true;
            for (int k = 0; k < ArraySize(frames); k++) {
                int ema = combination % 3;
                combination /= 3;
                setState(analysis.getElliot(frames[k]), isBuy, ema);
                if (k >= 2) {
                    expected = expected && ema == matchingEma;
                }
            }

            setState(analysis.getElliot(PERIOD_MN1), !isBuy, 0);
            setState(analysis.getElliot(PERIOD_W1), !isBuy, 3 - matchingEma);
            check(probe.evaluateEma(analysis, isBuy) == expected,
                StringFormat("EMA3 %d/%d", i, j), fromFailures);
            check(probe.evaluate(analysis), "D1-M5 bypass old AND gate", fromFailures);
            delete analysis;
        }
    }
}

/**
 * 通常M5の公開ENTRY経路で補正しないことと、条件回復時の初回ENTRYを検証する。
 */
void validateD1ToM5Entry(int &fromFailures) {
    ENUM_TIMEFRAMES frames[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
    for (int i = 0; i < 2; i++) {
        bool isBuy = i == 0;
        int matchingEma = 2;
        if (isBuy) {
            matchingEma = 1;
        }

        for (int j = 0; j < 11; j++) {
            ElliotAll *analysis = createEntryAll(isBuy);
            string caseName = StringFormat("D1-M5 ENTRY %d/%d", i, j);
            setState(analysis.getElliot(PERIOD_MN1), !isBuy, 0);
            setState(analysis.getElliot(PERIOD_W1), !isBuy, 3 - matchingEma);
            setState(analysis.getElliot(PERIOD_D1), isBuy, 3 - matchingEma);
            setState(analysis.getElliot(PERIOD_H4), isBuy, 0);
            MarketContext context("EURUSD", PERIOD_M5);
            SignalCount signalCount(context);
            ExpertAdvisorMtf3In3M5 probe(context, false, false, true);
            if (j < 4) {
                setState(analysis.getElliot(frames[j]), !isBuy, matchingEma);
            } else if (j < 10) {
                int ema = 0;
                if (j < 7) {
                    ema = 3 - matchingEma;
                }

                setState(analysis.getElliot(frames[2 + (j - 4) % 3]), isBuy, ema);
            }

            if (j < 10) {
                probe.analyze(analysis, GetPointer(signalCount));
                Mtf3In3AlertResult rejected = probe.getAlertResult();
                check(!rejected.isJudge && rejected.signalCount == 0,
                    caseName + " rejected without consuming count", fromFailures);
                check(probe.getJudgmentElliotAll() == analysis
                    && probe.getCorrectionTimeFrame() == PERIOD_CURRENT,
                    caseName + " no correction", fromFailures);
                for (int k = 0; k < ArraySize(frames); k++) {
                    setState(analysis.getElliot(frames[k]), isBuy, matchingEma);
                }
            }

            probe.analyze(analysis, GetPointer(signalCount));
            Mtf3In3AlertResult accepted = probe.getAlertResult();
            check(accepted.isEntry && accepted.signalCount == 1,
                caseName + " first entry despite upper disagreements", fromFailures);
            check(probe.getJudgmentElliotAll() == analysis
                && probe.getCorrectionTimeFrame() == PERIOD_CURRENT,
                caseName + " original used", fromFailures);
            probe.analyze(analysis, GetPointer(signalCount));
            check(!probe.isEntry, caseName + " duplicate blocked", fromFailures);
            delete analysis;
        }
    }
}

/**
 * 主波の全4通り、対象外ラベルでの待機・回復、FE境界と従来ポリシーを確認する。
 */
void validateM15AndM5MainWaves(int &fromFailures) {
    MarketContext context("EURUSD", PERIOD_M5);
    M5HigherProbe waveProbe(context, false, true);
    M5HigherProbe legacyProbe(context);
    check(!waveProbe.evaluateWaves(NULL), "main waves null analysis", fromFailures);
    ElliotAll *missingWaves = createAll();
    check(!waveProbe.evaluateWaves(missingWaves), "main waves missing points", fromFailures);
    delete missingWaves;

    string rejectedLabels[] = {"", "0", "2", "4", "5", "A", "B", "C"};
    ENUM_TIMEFRAMES frames[] = {PERIOD_M15, PERIOD_M5};
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 4; j++) {
            ElliotAll *analysis = createEntryAll(i == 0);
            ZigZagPoint *m15Point = analysis.getElliot(PERIOD_M15).getLatestPoint();
            ZigZagPoint *m5Point = analysis.elliotCurrent.getLatestPoint();
            if (j < 2) {
                m15Point.elliotLabel = "1";
            }
            if (j % 2 == 0) {
                m5Point.elliotLabel = "1";
            }

            m15Point.subElliotLabel = "2";
            m5Point.subElliotLabel = "2";
            m15Point.fibonacciExpansionPercent = 200.0;
            m5Point.fibonacciExpansionPercent = 161.8;
            if (m5Point.elliotLabel == "1") {
                m5Point.fibonacciExpansionPercent = 200.0;
            }

            SignalCount signalCount(context);
            ExpertAdvisorMtf3In3M5 probe(context, false, false, true);
            probe.analyze(analysis, GetPointer(signalCount));
            Mtf3In3AlertResult result = probe.getAlertResult();
            check(result.isEntry && result.signalCount == 1,
                StringFormat("main wave combination %d/%d", i, j), fromFailures);
            delete analysis;
        }

        for (int j = 0; j < ArraySize(frames); j++) {
            for (int k = 0; k < ArraySize(rejectedLabels); k++) {
                ElliotAll *analysis = createEntryAll(i == 0);
                ZigZagPoint *point = analysis.getElliot(frames[j]).getLatestPoint();
                point.elliotLabel = rejectedLabels[k];
                point.subElliotLabel = "3";
                SignalCount signalCount(context);
                ExpertAdvisorMtf3In3M5 probe(context, false, false, true);
                probe.analyze(analysis, GetPointer(signalCount));
                Mtf3In3AlertResult result = probe.getAlertResult();
                string caseName = StringFormat("main wave wait %d/%d/%d", i, j, k);
                check(!result.isJudge && result.signalCount == 0,
                    caseName + " rejected without count", fromFailures);
                point.elliotLabel = "3";
                probe.analyze(analysis, GetPointer(signalCount));
                result = probe.getAlertResult();
                check(result.isEntry && result.signalCount == 1,
                    caseName + " first entry after recovery", fromFailures);
                probe.analyze(analysis, GetPointer(signalCount));
                check(!probe.isEntry, caseName + " duplicate blocked", fromFailures);
                delete analysis;
            }
        }

        ElliotAll *analysis = createEntryAll(i == 0);
        analysis.getElliot(PERIOD_M15).waveList.Clear();
        check(!waveProbe.evaluateWaves(analysis), "M15 missing latest point", fromFailures);
        analysis.elliotCurrent.getLatestPoint().elliotLabel = "A";
        check(legacyProbe.evaluateWaves(analysis), "legacy A preserved", fromFailures);
        analysis.elliotCurrent.getLatestPoint().elliotLabel = "C";
        check(legacyProbe.evaluateWaves(analysis), "legacy C preserved", fromFailures);
        delete analysis;

        analysis = createEntryAll(i == 0);
        analysis.elliotCurrent.getLatestPoint().fibonacciExpansionPercent = 161.9;
        SignalCount signalCount(context);
        ExpertAdvisorMtf3In3M5 probe(context, false, false, true);
        probe.analyze(analysis, GetPointer(signalCount));
        Mtf3In3AlertResult result = probe.getAlertResult();
        check(result.isJudge && !result.isEntry && result.signalCount == 1
            && result.entryResult == "M5_ELLIOT3_FE_REJECTED",
            "main wave 3 FE above boundary", fromFailures);
        delete analysis;
    }
}

/**
 * 有効な同一M5時刻の順位を設定する。差は決済通貨順位から基軸通貨順位を引く。
 */
void setStrengthRanks(ElliotAll *fromAnalysis, int fromLongMedium, int fromMediumShort) {
    fromAnalysis.isCurrencyStrengthEntryFilterEnabled = true;
    CurrencyStrengthExecutionInfo info;
    info.reset();
    info.status = CURRENCY_STRENGTH_EXECUTION_STATUS_FOUND;
    info.targetM5BarTime = D'2026.10.01 00:00';
    info.pairRankInfo.m5BarTime = info.targetM5BarTime;
    info.pairRankInfo.baseCurrency = "EUR";
    info.pairRankInfo.quoteCurrency = "USD";
    int longMediumBase = 1;
    int mediumShortBase = 1;
    if (fromLongMedium < 0) {
        longMediumBase = 8;
    }
    if (fromMediumShort < 0) {
        mediumShortBase = 8;
    }

    info.pairRankInfo.baseLongMediumTermAverageRank = longMediumBase;
    info.pairRankInfo.quoteLongMediumTermAverageRank = longMediumBase + fromLongMedium;
    info.pairRankInfo.baseMediumShortTermAverageRank = mediumShortBase;
    info.pairRankInfo.quoteMediumShortTermAverageRank = mediumShortBase + fromMediumShort;
    fromAnalysis.currencyStrengthExecutionInfo = info;
}

/**
 * BUY/SELLの全順位差、境界、欠損・古いデータ、待機後の初回成立と設定を確認する。
 */
void validateM5StrengthEntry(int &fromFailures) {
    MarketContext context("EURUSD", PERIOD_M5);
    for (int i = 0; i < 2; i++) {
        for (int j = -7; j <= 7; j++) {
            for (int k = -7; k <= 7; k++) {
                ElliotAll *analysis = createEntryAll(i == 0);
                setStrengthRanks(analysis, j, k);
                SignalCount signalCount(context);
                ExpertAdvisorMtf3In3M5 probe(context, false, false, true);
                probe.analyze(analysis, GetPointer(signalCount));
                bool expected = j >= 4 && k >= 4;
                if (i == 1) {
                    expected = j <= -4 && k <= -4;
                }

                Mtf3In3AlertResult result = probe.getAlertResult();
                string caseName = StringFormat("M5 strength %d/%d/%d", i, j, k);
                check(result.isEntry == expected && result.isJudge == expected,
                    caseName + " AND direction and threshold", fromFailures);
                if (!expected) {
                    check(result.signalCount == 0, caseName + " no count consumed", fromFailures);
                    int matchingDifference = 4;
                    if (i == 1) {
                        matchingDifference = -4;
                    }

                    setStrengthRanks(analysis, matchingDifference, matchingDifference);
                    probe.analyze(analysis, GetPointer(signalCount));
                    result = probe.getAlertResult();
                    check(result.isEntry && result.signalCount == 1,
                        caseName + " first entry on recovery", fromFailures);
                }

                probe.analyze(analysis, GetPointer(signalCount));
                check(!probe.isEntry, caseName + " duplicate blocked", fromFailures);
                delete analysis;
            }
        }
    }

    for (int i = 0; i < 10; i++) {
        ElliotAll *analysis = createEntryAll(true);
        setStrengthRanks(analysis, 4, 4);
        int minimumDifference = 4;
        bool expected = false;
        if (i == 0) {
            analysis.currencyStrengthExecutionInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_RECORD_NOT_FOUND;
        } else if (i == 1) {
            analysis.currencyStrengthExecutionInfo.pairRankInfo.m5BarTime -= 300;
        } else if (i == 2) {
            analysis.currencyStrengthExecutionInfo.pairRankInfo.baseCurrency = "";
        } else if (i == 3) {
            analysis.currencyStrengthExecutionInfo.pairRankInfo.quoteMediumShortTermAverageRank = 9;
        } else if (i == 4) {
            analysis.currencyStrengthExecutionInfo.reset();
            analysis.isCurrencyStrengthEntryFilterEnabled = false;
            expected = true;
        } else if (i == 5) {
            minimumDifference = 5;
        } else if (i == 6) {
            minimumDifference = 0;
        } else if (i == 7) {
            minimumDifference = 8;
        } else if (i == 8) {
            minimumDifference = 1;
            setStrengthRanks(analysis, 1, 1);
            expected = true;
        } else {
            minimumDifference = 7;
            setStrengthRanks(analysis, 7, 7);
            expected = true;
        }

        SignalCount signalCount(context);
        ExpertAdvisorMtf3In3M5 probe(context, false, false, true, minimumDifference);
        probe.analyze(analysis, GetPointer(signalCount));
        Mtf3In3AlertResult result = probe.getAlertResult();
        check(result.isEntry == expected, StringFormat("M5 strength setting %d", i), fromFailures);
        if (!expected) {
            check(result.signalCount == 0, "invalid strength does not consume count", fromFailures);
        }

        delete analysis;
    }

    ElliotAll *legacyAnalysis = createEntryAll(true);
    setStrengthRanks(legacyAnalysis, 1, 1);
    SignalCount legacyCount(context);
    ExpertAdvisorMtf3In3M5 legacyProbe(context, false);
    legacyProbe.analyze(legacyAnalysis, GetPointer(legacyCount));
    check(legacyProbe.isEntry, "legacy strength remains direction only", fromFailures);
    delete legacyAnalysis;
}

/**
 * 通常M5と従来ポリシーの判定を検証する。注文・DB更新は行わない。
 */
void OnStart() {
    int failures = 0;
    validateCombinations(failures);
    validateInvalid(failures);
    validateEma(failures);
    validateAndWaitAndRetry(failures);
    validateCorrectedAndWait(failures);
    validateFibonacciConsumesFirstCount(failures);
    validateD1ToM5Policy(failures);
    validateD1ToM5Entry(failures);
    validateM15AndM5MainWaves(failures);
    validateM5StrengthEntry(failures);
    PrintFormat("Mtf3In3HigherTimeFrameDecisionSmokeTest failures=%d", failures);
}
