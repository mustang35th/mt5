#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_TARGET_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_TARGET_MQH

#include <Mstng\Constant\SymbolNameInfoAll.mqh>

/**
 * 分析・一覧・チャート表示の対象にする通貨ペア集合。
 */
enum ENUM_ZIGZAG_MONITOR_TARGET {
    ZIGZAG_MONITOR_TARGET_ALL = 0, // 全28ペア
    ZIGZAG_MONITOR_TARGET_GMO = 1, // GMO18ペア
    ZIGZAG_MONITOR_TARGET_NON_GMO = 2 // GMO以外10ペア
};

/**
 * 既存の全28通貨とGMO対象フラグから、監視対象を判定する。
 * 非GMOは全28通貨内の補集合とし、未知の通貨名は対象に含めない。
 */
class ZigZagElliotMonitorTarget {
public:
    /**
     * GMO対象フラグを持つ既存28通貨の定義を準備する。
     */
    ZigZagElliotMonitorTarget() {
        this.symbols.setGmo();
    }

    /**
     * 指定値がサポートする対象モードか返す。
     */
    static bool isValid(const ENUM_ZIGZAG_MONITOR_TARGET fromMode) {
        return fromMode == ZIGZAG_MONITOR_TARGET_ALL || fromMode == ZIGZAG_MONITOR_TARGET_GMO
            || fromMode == ZIGZAG_MONITOR_TARGET_NON_GMO;
    }

    /**
     * 正規通貨ペア名が指定モードの対象か返す。
     *
     * @param fromCanonicalSymbolName 接頭辞・接尾辞を含まない既存の通貨ペア名。
     * @param fromMode 選択する通貨ペア集合。
     * @return 既存28通貨のうち指定対象に含まれる場合true。
     */
    bool isSelected(const string fromCanonicalSymbolName, const ENUM_ZIGZAG_MONITOR_TARGET fromMode) {
        if (!ZigZagElliotMonitorTarget::isValid(fromMode)) {
            return false;
        }

        SymbolNameInfo *info = this.symbols.getSymbolNameInfo(fromCanonicalSymbolName);
        if (info == NULL) {
            return false;
        }

        if (fromMode == ZIGZAG_MONITOR_TARGET_ALL) {
            return true;
        }

        if (fromMode == ZIGZAG_MONITOR_TARGET_GMO) {
            return info.isTarget;
        }

        return !info.isTarget;
    }

    /**
     * 選択対象の表示名を返す。
     */
    static string getLabel(const ENUM_ZIGZAG_MONITOR_TARGET fromMode) {
        if (fromMode == ZIGZAG_MONITOR_TARGET_ALL) {
            return "全28ペア";
        }

        if (fromMode == ZIGZAG_MONITOR_TARGET_GMO) {
            return "GMO18ペア";
        }

        if (fromMode == ZIGZAG_MONITOR_TARGET_NON_GMO) {
            return "GMO以外10ペア";
        }

        return "不明";
    }

private:
    /** 全28通貨それぞれのGMO対象フラグ。 */
    SymbolNameInfoAll symbols;
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_TARGET_MQH
