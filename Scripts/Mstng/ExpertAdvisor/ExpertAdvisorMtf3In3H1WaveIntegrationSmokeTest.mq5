//+------------------------------------------------------------------+
//|       ExpertAdvisorMtf3In3H1WaveIntegrationSmokeTest.mq5        |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3H1.mqh>

/** 失敗した検証項目数。 */
int gFailureCount = 0;

/**
 * H1 Entry固有の波動判定をテスト用に公開するアダプター。
 */
class ExpertAdvisorMtf3In3H1WaveTestAdapter : public ExpertAdvisorMtf3In3H1 {
public:
    /**
     * H1市場コンテキストで初期化する。
     *
     * @param fromMarketContext H1市場コンテキスト。
     */
    ExpertAdvisorMtf3In3H1WaveTestAdapter(
        MarketContext &fromMarketContext
    ) : ExpertAdvisorMtf3In3H1(fromMarketContext, false) {
    }

    /**
     * テスト用のH1およびH4分析結果を設定する。
     *
     * @param fromElliotH1 H1分析結果。
     * @param fromElliotH4 H4分析結果。
     */
    void setTestElliots(
        Elliot *fromElliotH1,
        Elliot *fromElliotH4
    ) {
        this.elliotCurrent = fromElliotH1;
        this.elliotH1 = fromElliotH1;
        this.elliotH4 = fromElliotH4;
    }

    /**
     * 共通setEntry()が先に確認するH1対象ラベルを判定する。
     *
     * @return H1最新ラベルがEntry側の判定対象の場合true。
     */
    bool evaluateCurrentEntryWave() {
        return this.isEntryWave(this.elliotCurrent);
    }

    /**
     * H1 Entry固有のH1/H4波動条件を判定する。
     *
     * @param fromRejectReason 条件未達時の結果コード。
     * @return H1およびH4の波動条件を満たす場合true。
     */
    bool evaluateWaveEntry(string &fromRejectReason) {
        return this.isTimeFrameEntryConditionMatched(fromRejectReason);
    }
};

/**
 * 条件を検証する。
 *
 * @param fromCaseName 検証名。
 * @param fromCondition 期待する条件。
 */
void assertCondition(
    const string fromCaseName,
    const bool fromCondition
) {
    if (fromCondition) {
        return;
    }

    gFailureCount++;
    Print("FAIL " + fromCaseName);
}

/**
 * 数字Elliottポイントを一覧へ追加する。
 *
 * @param fromPointList 追加先ポイント一覧。
 * @param fromMarketContext 市場コンテキスト。
 * @param fromElliotIndex Elliott波動番号。
 * @param fromSubElliotIndex 副次波番号。
 * @param fromSubElliotLabel 副次波ラベル。
 * @return 追加に成功した場合true。
 */
bool addPoint(
    CArrayObj &fromPointList,
    MarketContext &fromMarketContext,
    const int fromElliotIndex,
    const int fromSubElliotIndex,
    const string fromSubElliotLabel
) {
    ZigZagPoint *point = new ZigZagPoint(fromMarketContext);

    if (point == NULL) {
        return false;
    }

    point.elliotIndex = fromElliotIndex;
    point.isElliotAlphabet = false;
    point.setElliotLabel();
    point.subElliotIndex = fromSubElliotIndex;
    point.subElliotLabel = fromSubElliotLabel;

    if (!fromPointList.Add(point)) {
        delete point;

        return false;
    }

    return true;
}

/**
 * 数字の第3波と第5波を持つ推進Waveを生成する。
 *
 * @param fromTimeFrame 対象時間足。
 * @param fromWave3SubElliotIndex 第3波の副次波番号。
 * @param fromWave3SubElliotLabel 第3波の副次波ラベル。
 * @return 呼び出し側が所有するテスト用Elliot。生成失敗時NULL。
 */
Elliot *createWave5Elliot(
    const ENUM_TIMEFRAMES fromTimeFrame,
    const int fromWave3SubElliotIndex,
    const string fromWave3SubElliotLabel
) {
    Elliot *elliot = new Elliot("EURUSD", fromTimeFrame);

    if (elliot == NULL) {
        return NULL;
    }

    CArrayObj pointList;
    bool isCreated = addPoint(
        pointList,
        elliot.marketContext,
        3,
        fromWave3SubElliotIndex,
        fromWave3SubElliotLabel
    );
    isCreated = isCreated && addPoint(
        pointList,
        elliot.marketContext,
        5,
        0,
        ""
    );

    if (!isCreated) {
        delete elliot;

        return NULL;
    }

    Wave *wave = new Wave(
        elliot.marketContext,
        pointList,
        true,
        true
    );

    if (wave == NULL || !elliot.waveList.Add(wave)) {
        if (wave != NULL) {
            delete wave;
        }

        delete elliot;

        return NULL;
    }

    return elliot;
}

/**
 * H1 Entry固有の波動条件と対象外理由を検証する。
 *
 * @param fromCaseName 検証名。
 * @param fromH1Wave3SubElliotIndex H1第3波の副次波番号。
 * @param fromH1Wave3SubElliotLabel H1第3波の副次波ラベル。
 * @param fromH4Wave3SubElliotIndex H4第3波の副次波番号。
 * @param fromH4Wave3SubElliotLabel H4第3波の副次波ラベル。
 * @param fromExpectedResult 期待する判定結果。
 * @param fromExpectedRejectReason 期待する対象外理由。
 */
void validateEntryCase(
    const string fromCaseName,
    const int fromH1Wave3SubElliotIndex,
    const string fromH1Wave3SubElliotLabel,
    const int fromH4Wave3SubElliotIndex,
    const string fromH4Wave3SubElliotLabel,
    const bool fromExpectedResult,
    const string fromExpectedRejectReason
) {
    Elliot *elliotH1 = createWave5Elliot(
        PERIOD_H1,
        fromH1Wave3SubElliotIndex,
        fromH1Wave3SubElliotLabel
    );
    Elliot *elliotH4 = createWave5Elliot(
        PERIOD_H4,
        fromH4Wave3SubElliotIndex,
        fromH4Wave3SubElliotLabel
    );

    if (elliotH1 == NULL || elliotH4 == NULL) {
        assertCondition(fromCaseName + " fixture", false);

        if (elliotH1 != NULL) {
            delete elliotH1;
        }

        if (elliotH4 != NULL) {
            delete elliotH4;
        }

        return;
    }

    MarketContext context("EURUSD", PERIOD_H1);
    ExpertAdvisorMtf3In3H1WaveTestAdapter expertAdvisor(context);
    expertAdvisor.setTestElliots(elliotH1, elliotH4);
    bool isEntryWave = expertAdvisor.evaluateCurrentEntryWave();
    string rejectReason = "NOT_EVALUATED";
    bool result = expertAdvisor.evaluateWaveEntry(rejectReason);

    assertCondition(fromCaseName + " H1 entry label", isEntryWave);
    assertCondition(
        fromCaseName + " result",
        result == fromExpectedResult
    );
    assertCondition(
        fromCaseName + " reason",
        rejectReason == fromExpectedRejectReason
    );

    expertAdvisor.setTestElliots(NULL, NULL);
    delete elliotH1;
    delete elliotH4;
}

/**
 * H1 Entry波動条件の実配線Smoke Testを実行する。
 */
void OnStart() {
    gFailureCount = 0;

    validateEntryCase(
        "VALID H1/H4 WAVE5",
        0,
        "",
        0,
        "",
        true,
        ""
    );
    validateEntryCase(
        "H1 SUB ELLIOT PRECEDENCE",
        1,
        "",
        2,
        "",
        false,
        "H1_WAVE3_SUB_ELLIOT_PRESENT_REJECTED"
    );
    validateEntryCase(
        "H4 SUB ELLIOT",
        0,
        "",
        0,
        "iii",
        false,
        "H4_WAVE3_SUB_ELLIOT_PRESENT_REJECTED"
    );

    if (gFailureCount == 0) {
        Print(
            "ExpertAdvisorMtf3In3H1WaveIntegrationSmokeTest PASS"
        );

        return;
    }

    PrintFormat(
        "ExpertAdvisorMtf3In3H1WaveIntegrationSmokeTest FAIL count=%d",
        gFailureCount
    );
}
