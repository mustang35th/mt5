#property strict
#property version "1.02"
#property description "テスター専用 / D1方向一致なし / その他はMstngM5Eaと共通"

#include <MstngM5Ea\Strategy\M5EaD1RelaxedFactory.mqh>

#define MSTNG_M5_D1_RELAXED_COMPARISON
#define ExpertAdvisorMtf3In3Factory M5EaD1RelaxedFactory
#define OnInit initializeD1ComparisonBase
#include "..\MstngM5Ea.mq5"
#undef OnInit
#undef ExpertAdvisorMtf3In3Factory
#undef MSTNG_M5_D1_RELAXED_COMPARISON

/**
 * 通常チャートではControllerやDBを作成せず終了する。
 * 検証スクリプトは同じ関数本体を通常メソッド名で読み込む。
 */
#ifndef MSTNG_M5_D1_COMPARISON_ENTRY_POINT
#define MSTNG_M5_D1_COMPARISON_ENTRY_POINT OnInit
#endif
int MSTNG_M5_D1_COMPARISON_ENTRY_POINT() {
    if (!M5EaD1RelaxedFactory::isRuntimeAllowed()) {
        Print("[ERROR] MstngM5D1Relaxed: strategy tester only");

        return INIT_FAILED;
    }

    return initializeD1ComparisonBase();
}
#undef MSTNG_M5_D1_COMPARISON_ENTRY_POINT
