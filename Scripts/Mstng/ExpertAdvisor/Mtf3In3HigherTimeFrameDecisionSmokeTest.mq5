#property version "1.00"

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
    M5HigherProbe(MarketContext &fromContext) : ExpertAdvisorMtf3In3M5(fromContext, false) {
    }

    /**
     * 発注やSignal Countを操作せず上位足ゲートを呼ぶ。
     */
    bool evaluate(ElliotAll *fromAll) {
        this.elliotAll = fromAll;
        this.isBuy = fromAll.elliotCurrent.isBuy;
        return this.isTimeFrameDirectionAlignmentConditionMatched();
    }
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
                elliotAll.elliotCurrent = elliotAll.getElliot(PERIOD_H1);
                H1DirectionAlignmentResult result;
                bool h1Passed = direction.evaluate(
                    H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED,
                    elliotAll, result) && ema.evaluate(
                    H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED, isBuy,
                    elliotAll.getElliot(PERIOD_H1), elliotAll.getElliot(PERIOD_H4),
                    elliotAll.getElliot(PERIOD_D1));
                check(h1Passed == (expected && isH4Buy == isBuy), caseName + " H1", fromFailures);
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
    string reason;
    check(!common.evaluate(NULL, true, reason), "null analysis", fromFailures);
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
        delete elliotAll;
    }
}

/**
 * 上位足共通化の回帰テストを実行する。注文・DB更新は行わない。
 */
void OnStart() {
    int failures = 0;
    validateCombinations(failures);
    validateInvalid(failures);
    PrintFormat("Mtf3In3HigherTimeFrameDecisionSmokeTest failures=%d", failures);
}
