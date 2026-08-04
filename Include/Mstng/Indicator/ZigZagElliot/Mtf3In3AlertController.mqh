//+------------------------------------------------------------------+
//|                         Mtf3In3AlertController.mqh |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH
#define MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Constant\Constant.mqh>
#include <Mstng\Elliot\ElliotAll.mqh>
#include <Mstng\ExpertAdvisor\ExpertAdvisorMtf3In3Factory.mqh>
#include <Mstng\ExpertAdvisor\Mtf3In3AlertCsvWriter.mqh>
#include <Mstng\Log\Logger.mqh>
#include <Mstng\Signal\SignalCount.mqh>

/**
 * MTF_3in3アラート判定、シグナル回数および検証CSVを管理するクラス。
 */
class Mtf3In3AlertController {
public:
    /**
     * 保持リソースを初期化する。
     */
    Mtf3In3AlertController() {
        this.expertAdvisorMtf3In3 = NULL;
        this.signalCount = NULL;
        this.alertCsvEnabled = true;
    }

    /**
     * 保持リソースを解放する。
     */
    ~Mtf3In3AlertController() {
        this.destroy();
    }

    /**
     * 市場コンテキストと検証CSV設定を使用して初期化する。
     *
     * @param fromMarketContext 市場コンテキスト
     * @param fromAlertCsvEnabled 検証CSVを出力する場合true
     * @return 初期化に成功した場合true
     */
    bool initialize(
        MarketContext &fromMarketContext,
        bool fromAlertCsvEnabled
    ) {
        this.destroy();

        this.marketContext = fromMarketContext;
        this.alertCsvEnabled = fromAlertCsvEnabled;
        this.logger.setLevel(LOG_INFO);
        this.logger.setMarketContext(this.marketContext);
        this.signalCount = new SignalCount(this.marketContext);

        if (this.signalCount == NULL) {
            this.logger.error(
                __FUNCTION__,
                "signal count allocation failed"
            );

            return false;
        }

        this.expertAdvisorMtf3In3 = ExpertAdvisorMtf3In3Factory::create(
            this.marketContext
        );

        if (this.expertAdvisorMtf3In3 == NULL) {
            this.logger.error(
                __FUNCTION__,
                "MTF_3in3 expert advisor allocation failed"
            );
            delete this.signalCount;
            this.signalCount = NULL;

            return false;
        }

        return true;
    }

    /**
     * MTF_3in3アラートを分析し、必要に応じて検証CSVを出力する。
     *
     * @param fromElliotAll Elliott分析結果
     */
    void execute(ElliotAll *fromElliotAll) {
        if (
            fromElliotAll == NULL
            || this.expertAdvisorMtf3In3 == NULL
            || this.signalCount == NULL
        ) {
            return;
        }

        if (this.marketContext.timeFrame > PERIOD_H1) {
            return;
        }

        this.expertAdvisorMtf3In3.analyze(fromElliotAll, this.signalCount);

        if (!this.alertCsvEnabled || !this.expertAdvisorMtf3In3.isAlert) {
            return;
        }

        Mtf3In3AlertResult alertResult =
            this.expertAdvisorMtf3In3.getAlertResult();
        bool isWritten = Mtf3In3AlertCsvWriter::write(
            fromElliotAll,
            alertResult,
            "ZIGZAG_ELLIOT"
        );

        if (!isWritten) {
            this.logger.error(
                __FUNCTION__,
                "MTF_3in3 alert validation CSV write failed"
            );
        }
    }

    /**
     * シグナル回数とMTF_3in3固定描画オブジェクトを解放する。
     */
    void destroy() {
        if (this.expertAdvisorMtf3In3 != NULL) {
            delete this.expertAdvisorMtf3In3;
            this.expertAdvisorMtf3In3 = NULL;
        }

        if (this.signalCount != NULL) {
            delete this.signalCount;
            this.signalCount = NULL;
        }

        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "ArrowMTF_3in3",
            0,
            -1
        );
        ObjectsDeleteAll(
            0,
            Constant::PREFIX_FIXED + "TextMTF_3in3",
            0,
            -1
        );
    }

private:
    /** 市場コンテキスト。 */
    MarketContext marketContext;
    /** MTF_3in3外部戦略。 */
    ExpertAdvisorMTF_3in3 *expertAdvisorMtf3In3;
    /** ロガー。 */
    Logger logger;
    /** シグナル回数。 */
    SignalCount *signalCount;
    /** 検証CSVを出力する場合true。 */
    bool alertCsvEnabled;
};

#endif // MSTNG_INDICATOR_ZIGZAG_ELLIOT_MTF3_IN3_ALERT_CONTROLLER_MQH
