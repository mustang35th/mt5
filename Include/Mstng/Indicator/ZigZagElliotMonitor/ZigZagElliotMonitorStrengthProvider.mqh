#ifndef MSTNG_ZIGZAG_ELLIOT_MONITOR_STRENGTH_PROVIDER_MQH
#define MSTNG_ZIGZAG_ELLIOT_MONITOR_STRENGTH_PROVIDER_MQH

#include <Mstng\Common\MarketContext.mqh>
#include <Mstng\Database\Service\CurrencyStrengthExecutionInfoProvider.mqh>
#include <Mstng\Indicator\ZigZagElliot\ZigZagElliotConfig.mqh>
#include <Mstng\Strength\CurrencyStrengthRankGapDirectionProvider.mqh>
#include <Mstng\Util\Util.mqh>

/**
 * 1通貨の現在順位と両期間の増減を、既存の取得方式で読み取る。
 * 描画、DB作成・保存、メール送信は行わない。
 */
class ZigZagElliotMonitorStrengthProvider {
public:
    /**
     * 所有する取得先を未作成状態にする。
     */
    ZigZagElliotMonitorStrengthProvider() {
        this.executionProvider = NULL;
        this.gapProvider = NULL;
    }

    /**
     * 所有する接続と履歴キャッシュを解放する。
     */
    ~ZigZagElliotMonitorStrengthProvider() {
        this.close();
    }

    /**
     * 実際のシンボルの通貨属性と、通常版のDB設定を保持する。
     *
     * @return 必要な取得先を作成できた場合true。
     */
    bool initialize(MarketContext &fromMarketContext, ZigZagElliotConfig &fromConfig) {
        this.close();
        this.marketContext = fromMarketContext;
        string baseCurrency = SymbolInfoString(fromMarketContext.symbolName, SYMBOL_CURRENCY_BASE);
        string quoteCurrency = SymbolInfoString(fromMarketContext.symbolName, SYMBOL_CURRENCY_PROFIT);
        if (fromMarketContext.symbolName == "" || baseCurrency == "" || quoteCurrency == ""
                || baseCurrency == quoteCurrency || fromConfig.currencyStrengthDatabaseFileName == "") {
            return false;
        }

        this.executionProvider = new CurrencyStrengthExecutionInfoProvider(
            fromConfig.currencyStrengthDatabaseFileName,
            fromConfig.currencyStrengthDatabaseSplitByYear,
            fromConfig.currencyStrengthDatabaseUseCommonFolder,
            fromConfig.currencyStrengthDatabaseProfile,
            CURRENCY_STRENGTH_RANK_QUERY_MODE_EXACT,
            fromConfig.currencyStrengthRefreshSeconds,
            fromConfig.currencyStrengthVoteWeightMode
        );
        this.gapProvider = new CurrencyStrengthRankGapDirectionProvider(
            fromConfig.currencyStrengthDatabaseFileName,
            fromConfig.currencyStrengthDatabaseSplitByYear,
            fromConfig.currencyStrengthDatabaseUseCommonFolder,
            fromConfig.currencyStrengthDatabaseProfile,
            fromConfig.currencyStrengthVoteWeightMode,
            Util::isStrategyTester(), baseCurrency, quoteCurrency,
            fromConfig.currencyStrengthRefreshSeconds
        );
        if (this.executionProvider == NULL || this.gapProvider == NULL) {
            this.close();

            return false;
        }

        return true;
    }

    /**
     * 固定したM5時刻の順位を取得し、1回の履歴取得で両期間の増減を付加する。
     * 方向不明は取得完了として返し、取得待ちとは分けて判定側へ渡す。
     *
     * @param fromTargetM5BarTime 今回のM1評価に固定したM5開始時刻。
     * @param fromInfo 取得状態を含む結果の値コピー。
     * @return 現在順位と両期間の履歴確認が完了した場合true。
     */
    bool load(const datetime fromTargetM5BarTime, CurrencyStrengthExecutionInfo &fromInfo) {
        fromInfo.reset();
        fromInfo.targetM5BarTime = fromTargetM5BarTime;
        if (this.executionProvider == NULL || this.gapProvider == NULL
                || fromTargetM5BarTime <= 0 || fromTargetM5BarTime % 300 != 0) {
            fromInfo.status = CURRENCY_STRENGTH_EXECUTION_STATUS_ERROR;

            return false;
        }

        this.executionProvider.load(this.marketContext, fromTargetM5BarTime, fromInfo);
        fromInfo.longMediumGapDirectionFilterEnabled = true;
        fromInfo.mediumShortGapDirectionFilterEnabled = true;
        fromInfo.gapDirectionMailEnabled = false;
        if (!fromInfo.isExactM5Bar() || fromInfo.targetM5BarTime != fromTargetM5BarTime) {
            return false;
        }

        CurrencyStrengthRankGapDirectionInfo longMedium;
        CurrencyStrengthRankGapDirectionInfo mediumShort;
        this.gapProvider.load(fromInfo, longMedium, mediumShort);
        fromInfo.longMediumGapDirection = longMedium;
        fromInfo.mediumShortGapDirection = mediumShort;

        return longMedium.enabled && mediumShort.enabled
            && longMedium.targetM5BarTime == fromTargetM5BarTime
            && mediumShort.targetM5BarTime == fromTargetM5BarTime
            && !longMedium.waiting && !mediumShort.waiting;
    }

    /**
     * 作成済みの取得先だけを解放する。
     */
    void close() {
        if (this.gapProvider != NULL) {
            delete this.gapProvider;
            this.gapProvider = NULL;
        }

        if (this.executionProvider != NULL) {
            delete this.executionProvider;
            this.executionProvider = NULL;
        }
    }

private:
    /** 通貨属性の参照と現在順位取得に使う市場コンテキスト。 */
    MarketContext marketContext;

    /** 現在順位の読み取り専用取得先。 */
    CurrencyStrengthExecutionInfoProvider *executionProvider;

    /** 両期間で共用する増減履歴の読み取り先。 */
    CurrencyStrengthRankGapDirectionProvider *gapProvider;
};

#endif // MSTNG_ZIGZAG_ELLIOT_MONITOR_STRENGTH_PROVIDER_MQH
