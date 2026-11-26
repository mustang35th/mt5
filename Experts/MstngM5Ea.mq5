//+------------------------------------------------------------------+
//|                                                    MstngM5Ea.mq5 |
//|                                            Copyright 2026, Mstng |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Mstng"
#property version "1.01"
#property strict
#property description "通常版ZigZagElliot M5判定 / 通貨強弱 / ZigZag SL / 専用SQLite"

#include <MstngM5Ea\M5EaController.mqh>

input group "取引設定"
input(name="固定ロット") double lotSize = 0.01;
input(name="最大初期SL幅（pips）") double maxInitialStopLossPips = 100.0;
input(name="初期SLの余白（pips）") double initialStopLossBufferPips = 10.0;
input(name="M5トレーリングの余白（pips）") double trailStopLossBufferPips = 10.0;

input group "M5通貨強弱"
input(name="通貨強弱をエントリー条件に使用") bool currencyStrengthEnabled = true;
input(name="順位差基準（1～7、各期間は端順位でも可）")
int currencyStrengthMinimumRankDifference = 4;
input(name="長中期の増減方向を条件に追加（横ばいは維持）")
bool longMediumGapDirectionEnabled = true;
input(name="通貨強弱DB名") string currencyStrengthDatabaseFileName = "mstng-currency-strength.sqlite";
input(name="通貨強弱DBを年別に参照") bool currencyStrengthDatabaseSplitByYear = true;
input(name="通貨強弱DBでCommonフォルダを使用") bool currencyStrengthDatabaseUseCommonFolder = true;
input(name="通貨強弱の参照元")
CurrencyStrengthRankDatabaseProfile currencyStrengthDatabaseProfile = CURRENCY_STRENGTH_RANK_DATABASE_PROFILE_LIVE_THEN_TESTER;
input(name="通貨強弱の集計方式")
CurrencyStrengthVoteWeightMode currencyStrengthVoteWeightMode = CURRENCY_STRENGTH_VOTE_WEIGHT_WEIGHTED;

input group "テスター設定"
input(name="売買開始日時（サーバー時刻、0=制限なし）")
datetime testerTradeStartTime = D'2026.01.01 00:00';

/** M5単一通貨の制御本体。 */
M5EaController *controller = NULL;

/**
 * 設定と保存状態を準備し、エントリーはイベントへ委ねる。
 */
int OnInit() {
    if (controller != NULL) {
        return INIT_FAILED;
    }

    M5EaSettings settings;
    settings.lotSize = lotSize;
    settings.maxInitialStopLossPips = maxInitialStopLossPips;
    settings.initialStopLossBufferPips = initialStopLossBufferPips;
    settings.trailStopLossBufferPips = trailStopLossBufferPips;
    settings.testerTradeStartTime = testerTradeStartTime;
    settings.currencyStrengthEnabled = currencyStrengthEnabled;
    settings.currencyStrengthMinimumRankDifference = currencyStrengthMinimumRankDifference;
    settings.longMediumGapDirectionEnabled = longMediumGapDirectionEnabled;
    settings.currencyStrengthDatabaseFileName = currencyStrengthDatabaseFileName;
    settings.currencyStrengthDatabaseSplitByYear = currencyStrengthDatabaseSplitByYear;
    settings.currencyStrengthDatabaseUseCommonFolder = currencyStrengthDatabaseUseCommonFolder;
    settings.currencyStrengthDatabaseProfile = currencyStrengthDatabaseProfile;
    settings.currencyStrengthVoteWeightMode = currencyStrengthVoteWeightMode;

    controller = new M5EaController();
    if (controller == NULL) {
        return INIT_FAILED;
    }

    if (!controller.initialize(_Symbol, settings) || !controller.startTimer()) {
        controller.shutdown(REASON_INITFAILED);
        delete controller;
        controller = NULL;

        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}

/**
 * ポジションとbroker SLを残し、EAのリソースを解放する。
 */
void OnDeinit(const int fromReason) {
    EventKillTimer();
    if (controller != NULL) {
        controller.shutdown(fromReason);
        delete controller;
        controller = NULL;
    }
}

/**
 * 保護処理とTesterのエントリーを実行する。
 */
void OnTick() {
    if (controller != NULL) {
        controller.onTick();
    }
}

/**
 * Lease保守とLIVEのエントリーを実行する。
 */
void OnTimer() {
    if (controller != NULL) {
        controller.onTimer();
    }
}

/**
 * broker通知を共通の照合処理へ渡す。
 */
void OnTradeTransaction(const MqlTradeTransaction &fromTransaction,
        const MqlTradeRequest &fromRequest, const MqlTradeResult &fromResult) {
    if (controller != NULL) {
        controller.onTradeTransaction(fromTransaction, fromRequest, fromResult);
    }
}
