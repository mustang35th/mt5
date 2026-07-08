//+------------------------------------------------------------------+
//|                                                FiboDepthZone.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

/**
 * フィボナッチ深さゾーン。
 */
enum ENUM_FIBO_DEPTH_ZONE {
    FIBO_DEPTH_UNKNOWN   = 0,  // 未判定
    FIBO_DEPTH_SHALLOW   = 1,  // 23.6未満
    FIBO_DEPTH_LIGHT     = 2,  // 23.6以上 38.2未満
    FIBO_DEPTH_NORMAL    = 3,  // 38.2以上 61.8未満
    FIBO_DEPTH_DEEP      = 4,  // 61.8以上 78.6未満
    FIBO_DEPTH_VERY_DEEP = 5,  // 78.6以上 100.0以下
    FIBO_DEPTH_INVALID   = 6   // 100.0超え
};

/**
 * フィボナッチ深さからゾーン判定や分類名を取得するユーティリティ。
 */
class FiboDepthZone {
public:
    /**
     * フィボナッチ深さからゾーンを取得する。
     *
     * @param fiboDepthValue フィボナッチ深さ
     * @return フィボナッチ深さゾーン
     */
    static ENUM_FIBO_DEPTH_ZONE getZone(const double fiboDepthValue) {
        // 未判定

        if (fiboDepthValue < 0.0) {
            return FIBO_DEPTH_UNKNOWN;
        }

        // 23.6未満

        if (fiboDepthValue < 23.6) {
            return FIBO_DEPTH_SHALLOW;
        }

        // 23.6以上 38.2未満

        if (fiboDepthValue < 38.2) {
            return FIBO_DEPTH_LIGHT;
        }

        // 38.2以上 61.8未満

        if (fiboDepthValue < 61.8) {
            return FIBO_DEPTH_NORMAL;
        }

        // 61.8以上 78.6未満

        if (fiboDepthValue < 78.6) {
            return FIBO_DEPTH_DEEP;
        }

        // 78.6以上 100.0以下

        if (fiboDepthValue <= 100.0) {
            return FIBO_DEPTH_VERY_DEEP;
        }

        return FIBO_DEPTH_INVALID;
    }

    /**
     * フィボナッチ深さゾーン名を取得する。
     *
     * @param zoneValue フィボナッチ深さゾーン
     * @return ゾーン名
     */
    static string toString(const ENUM_FIBO_DEPTH_ZONE zoneValue) {
        switch (zoneValue) {
            case FIBO_DEPTH_SHALLOW:
                return "SHALLOW";

            case FIBO_DEPTH_LIGHT:
                return "LIGHT";

            case FIBO_DEPTH_NORMAL:
                return "NORMAL";

            case FIBO_DEPTH_DEEP:
                return "DEEP";

            case FIBO_DEPTH_VERY_DEEP:
                return "VERY_DEEP";

            case FIBO_DEPTH_INVALID:
                return "INVALID";

            case FIBO_DEPTH_UNKNOWN:
            default:
                return "UNKNOWN";
        }
    }

    /**
     * フィボナッチ深さからゾーン名を取得する。
     *
     * @param fiboDepthValue フィボナッチ深さ
     * @return ゾーン名
     */
    static string toStringByDepth(const double fiboDepthValue) {
        // ゾーン取得
        ENUM_FIBO_DEPTH_ZONE zone = getZone(fiboDepthValue);

        return toString(zone);
    }

    /**
     * 3波エントリーに適した深さか判定する。
     *
     * @param fiboDepthValue フィボナッチ深さ
     * @return 適した深さの場合true
     */
    static bool isValidThirdWaveDepth(const double fiboDepthValue) {
        // ゾーン取得
        ENUM_FIBO_DEPTH_ZONE zone = getZone(fiboDepthValue);

        if (zone == FIBO_DEPTH_NORMAL) {
            return true;
        }

        if (zone == FIBO_DEPTH_DEEP) {
            return true;
        }

        return false;
    }

    /**
     * 有効なフィボナッチ深さか判定する。
     *
     * @param fiboDepthValue フィボナッチ深さ
     * @return 有効な深さの場合true
     */
    static bool isValidDepth(const double fiboDepthValue) {
        // ゾーン取得
        ENUM_FIBO_DEPTH_ZONE zone = getZone(fiboDepthValue);

        if (zone == FIBO_DEPTH_UNKNOWN) {
            return false;
        }

        if (zone == FIBO_DEPTH_INVALID) {
            return false;
        }

        return true;
    }

    /**
     * 浅い押し戻りか判定する。
     *
     * @param fiboDepthValue フィボナッチ深さ
     * @return 浅い押し戻りの場合true
     */
    static bool isShallow(const double fiboDepthValue) {
        // ゾーン取得
        ENUM_FIBO_DEPTH_ZONE zone = getZone(fiboDepthValue);

        if (zone == FIBO_DEPTH_SHALLOW) {
            return true;
        }

        if (zone == FIBO_DEPTH_LIGHT) {
            return true;
        }

        return false;
    }

    /**
     * 深い押し戻りか判定する。
     *
     * @param fiboDepthValue フィボナッチ深さ
     * @return 深い押し戻りの場合true
     */
    static bool isDeep(const double fiboDepthValue) {
        // ゾーン取得
        ENUM_FIBO_DEPTH_ZONE zone = getZone(fiboDepthValue);

        if (zone == FIBO_DEPTH_DEEP) {
            return true;
        }

        if (zone == FIBO_DEPTH_VERY_DEEP) {
            return true;
        }

        return false;
    }
};
