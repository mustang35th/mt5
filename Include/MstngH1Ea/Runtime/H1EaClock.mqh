#ifndef MSTNGH1EA_RUNTIME_CLOCK_MQH
#define MSTNGH1EA_RUNTIME_CLOCK_MQH

/**
 * LIVEの単調経過時間とTesterの再現可能な経過時間を提供する。
 */
class H1EaClock {
public:
    /**
     * 再試行間隔専用のミリ秒値。DBへ日時として保存しない。
     * Testerではテスト実行速度で再試行回数が変わらないようserver時刻を使う。
     */
    static ulong milliseconds() {
        if (MQLInfoInteger(MQL_TESTER)) {
            return (ulong)TimeCurrent() * 1000;
        }
        return GetTickCount64();
    }
};

#endif
