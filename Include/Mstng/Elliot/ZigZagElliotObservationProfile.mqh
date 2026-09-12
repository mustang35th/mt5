//+------------------------------------------------------------------+
//|                              ZigZagElliotObservationProfile.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_ELLIOT_ZIGZAG_ELLIOT_OBSERVATION_PROFILE_MQH
#define MSTNG_ELLIOT_ZIGZAG_ELLIOT_OBSERVATION_PROFILE_MQH

#include <Mstng\Elliot\ZigZagElliotAnalysisProfile.mqh>

/**
 * H1・M5観測の足構成と保存識別子を保持するクラス。
 *
 * 起動時に基準足を選択し、インスタンスごとに固定する。
 * 共通の分析パラメーターとH1既存Canonical Textは変更しない。
 */
class ZigZagElliotObservationProfile {
public:
    /**
     * 固定の観測Profileを生成する。
     *
     * @param fromAnchorTimeFrame H1またはM5。省略時は既存H1。
     */
    ZigZagElliotObservationProfile(
        const ENUM_TIMEFRAMES fromAnchorTimeFrame = PERIOD_H1
    ) {
        this.anchorTimeFrame = fromAnchorTimeFrame;
    }

    /**
     * @return 対応するH1またはM5の場合true。
     */
    bool isValid() const {
        return this.anchorTimeFrame == PERIOD_H1 || this.isM5();
    }

    /**
     * @return M5専用観測の場合true。
     */
    bool isM5() const { return this.anchorTimeFrame == PERIOD_M5; }

    /**
     * @return 観測基準足。
     */
    ENUM_TIMEFRAMES getAnchorTimeFrame() const {
        return this.anchorTimeFrame;
    }

    /**
     * @return 共通分析の開始足。
     */
    ENUM_TIMEFRAMES getAnalysisStartTimeFrame() const {
        return ZigZagElliotAnalysisProfile::getAnalysisStartTimeFrame();
    }

    /**
     * @return H1は5、M5は7。未対応足は0。
     */
    int getObservationTimeFrameCount() const {
        if (!this.isValid()) {
            return 0;
        }
        if (this.isM5()) {
            return 7;
        }
        return ZigZagElliotAnalysisProfile::getObservationTimeFrameCount();
    }

    /**
     * 固定保存順序の時間足を取得する。
     *
     * @param fromIndex 上位足からの0始まりの順序。
     * @return 対応足。範囲外または未対応ProfileはPERIOD_CURRENT。
     */
    ENUM_TIMEFRAMES getObservationTimeFrame(const int fromIndex) const {
        if (fromIndex < 0 || fromIndex >= this.getObservationTimeFrameCount()) {
            return PERIOD_CURRENT;
        }
        if (fromIndex == 5) {
            return PERIOD_M15;
        }
        if (fromIndex == 6) {
            return PERIOD_M5;
        }
        return ZigZagElliotAnalysisProfile::getObservationTimeFrame(fromIndex);
    }

    /**
     * @return 保存足の固定順序文字列。
     */
    string getObservationTimeFrameOrderText() const {
        string text = "";
        for (int i = 0; i < this.getObservationTimeFrameCount(); i++) {
            if (i > 0) {
                text += ",";
            }
            text += IntegerToString((int)this.getObservationTimeFrame(i));
        }
        return text;
    }

    /**
     * @return Runの収集方式識別子。
     */
    string getStrategy() const {
        if (this.isM5()) {
            return "M5_OBSERVATION_ALL";
        }
        return "H1_OBSERVATION_ALL";
    }

    /**
     * @return Runの収集契約バージョン。
     */
    string getStrategyVersion() const {
        if (this.isM5()) {
            return "M5_OBSERVATION_ALL_V1";
        }
        return "H1_OBSERVATION_ALL_V5";
    }

    /**
     * @return Run保存形式のバージョン。物理DB全体の番号ではない。
     */
    int getSchemaVersion() const {
        if (this.isM5()) {
            return 1;
        }
        return 6;
    }

    /**
     * @return 共通Elliott計算のバージョン。
     */
    string getAnalysisVersion() const {
        return ZigZagElliotAnalysisProfile::getAnalysisVersion();
    }

    /**
     * @return 観測Profileの識別子。
     */
    string getProfileVersion() const {
        if (this.isM5()) {
            return "M5_OBSERVATION_PROFILE_V1";
        }
        return ZigZagElliotAnalysisProfile::getProfileVersion();
    }

    /**
     * @return Snapshot Hashの形式識別子。
     */
    string getSnapshotHashVersion() const {
        if (this.isM5()) {
            return "M5_OBSERVATION_V2";
        }
        return "H1_OBSERVATION_V5";
    }

    /**
     * @return 観測方式。
     */
    string getCapturePhase() const { return "BAR_OPEN_FIRST_SUCCESS"; }

    /**
     * @return 取得品質行を必須とする場合true。
     */
    bool requiresCaptureMetrics() const { return this.isM5(); }

    /**
     * H1互換またはM5専用の分析設定文字列を生成する。
     *
     * @return Canonical Text。未対応Profileは空文字列。
     */
    string createCanonicalText() const {
        if (!this.isValid()) {
            return "";
        }
        if (!this.isM5()) {
            return ZigZagElliotAnalysisProfile::createCanonicalText();
        }
        string text = ZigZagElliotAnalysisProfile::createCanonicalText(
            this.getProfileVersion(),
            this.getAnchorTimeFrame(),
            this.getAnalysisStartTimeFrame(),
            this.getObservationTimeFrameCount(),
            this.getObservationTimeFrameOrderText()
        );
        text += "|CAPTURE_PHASE=" + this.getCapturePhase();
        text += "|SPREAD_QUOTE_RULE=SINGLE_MQL_TICK_AT_ANALYSIS_START";
        return text;
    }

    /**
     * @return 観測Canonical TextのSHA-256。未対応Profileは空文字列。
     */
    string createHash() const {
        if (!this.isValid()) {
            return "";
        }
        return ZigZagElliotAnalysisProfile::createHash(this.createCanonicalText());
    }

private:
    /** 起動時に固定した観測基準足。 */
    ENUM_TIMEFRAMES anchorTimeFrame;
};

#endif // MSTNG_ELLIOT_ZIGZAG_ELLIOT_OBSERVATION_PROFILE_MQH
