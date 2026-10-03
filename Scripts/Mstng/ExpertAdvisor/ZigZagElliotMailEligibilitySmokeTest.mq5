//+------------------------------------------------------------------+
//|                          ZigZagElliotMailEligibilitySmokeTest.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3H1.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3M15.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3M5.mqh>

/**
 * H1の送信対象判定だけを公開し、実送信せず検証する。
 */
class H1MailEligibilityProbe : public ExpertAdvisorMtf3In3H1 {
public:
    /**
     * 描画しないH1戦略を初期化する。
     */
    H1MailEligibilityProbe(MarketContext &fromMarketContext)
        : ExpertAdvisorMtf3In3H1(fromMarketContext, false) {
    }

    /**
     * H1のメール送信対象判定を取得する。
     */
    bool isMailEligible() {
        return this.shouldSendMail();
    }
};

/**
 * M15の送信対象判定だけを公開し、実送信せず検証する。
 */
class M15MailEligibilityProbe : public ExpertAdvisorMtf3In3M15 {
public:
    /**
     * 描画しないM15戦略を初期化する。
     */
    M15MailEligibilityProbe(MarketContext &fromMarketContext)
        : ExpertAdvisorMtf3In3M15(fromMarketContext, false) {
    }

    /**
     * M15のメール送信対象判定を取得する。
     */
    bool isMailEligible() {
        return this.shouldSendMail();
    }
};

/**
 * M5の送信対象判定だけを公開し、実送信せず検証する。
 */
class M5MailEligibilityProbe : public ExpertAdvisorMtf3In3M5 {
public:
    /**
     * 描画しないM5戦略を初期化する。
     */
    M5MailEligibilityProbe(MarketContext &fromMarketContext)
        : ExpertAdvisorMtf3In3M5(fromMarketContext, false) {
    }

    /**
     * M5のメール送信対象判定を取得する。
     */
    bool isMailEligible() {
        return this.shouldSendMail();
    }
};

/**
 * その他の時間足の共通判定だけを公開し、実送信せず検証する。
 */
class OtherMailEligibilityProbe : public ExpertAdvisorMTF_3in3 {
public:
    /**
     * 描画しない共通戦略を初期化する。
     */
    OtherMailEligibilityProbe(MarketContext &fromMarketContext)
        : ExpertAdvisorMTF_3in3(fromMarketContext, false) {
    }

    /**
     * 共通戦略のメール送信対象判定を取得する。
     */
    bool isMailEligible() {
        return this.shouldSendMail();
    }
};

/**
 * ZigZagElliot名と通常のテスト名の両方で実行し、送信対象の切り替えを検証する。
 * 相場の分析、メール生成、SendMailは一切呼び出さない。
 */
void OnStart() {
    string programName = MQLInfoString(MQL_PROGRAM_NAME);
    bool isZigZagElliot = programName == "ZigZagElliot";
    int failureCount = 0;
    MarketContext contextH1("EURUSD", PERIOD_H1);
    MarketContext contextM15("EURUSD", PERIOD_M15);
    MarketContext contextM5("EURUSD", PERIOD_M5);
    H1MailEligibilityProbe h1Probe(contextH1);
    M15MailEligibilityProbe m15Probe(contextM15);
    M5MailEligibilityProbe m5Probe(contextM5);
    if (h1Probe.isMailEligible() != !isZigZagElliot) {
        Print("FAIL H1 mail eligibility");
        failureCount++;
    }
    if (m15Probe.isMailEligible() != isZigZagElliot) {
        Print("FAIL M15 mail eligibility");
        failureCount++;
    }
    if (m5Probe.isMailEligible() != !isZigZagElliot) {
        Print("FAIL M5 mail eligibility");
        failureCount++;
    }

    ENUM_TIMEFRAMES otherFrames[] = {
        PERIOD_M1, PERIOD_M30, PERIOD_H4, PERIOD_D1, PERIOD_W1, PERIOD_MN1
    };
    for (int i = 0; i < ArraySize(otherFrames); i++) {
        MarketContext context("EURUSD", otherFrames[i]);
        OtherMailEligibilityProbe probe(context);
        if (probe.isMailEligible()) {
            Print("FAIL other mail eligibility ", EnumToString(otherFrames[i]));
            failureCount++;
        }
    }
    if (failureCount == 0) {
        Print("ZigZagElliotMailEligibilitySmokeTest PASS program=", programName);
        return;
    }
    Print("ZigZagElliotMailEligibilitySmokeTest FAIL program=", programName,
        " count=", failureCount);
}
