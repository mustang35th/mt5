#ifndef MSTNG_DRAW_ELLIOT_PANEL_SAVED_ADAPTER_MQH
#define MSTNG_DRAW_ELLIOT_PANEL_SAVED_ADAPTER_MQH

#include <Mstng\Database\Query\ZigZagElliotM5ObservationHistoryData.mqh>
#include <Mstng\Draw\ElliotPanelData.mqh>
#include <Mstng\Util\TimeUtil.mqh>

/**
 * 読み取り済みのM5観測履歴を、共通パネルの表示用データへ変換する。
 * DB照会・指標計算・チャート操作を行わず、保存値と欠損状態をそのまま保持する。
 */
class ElliotPanelSavedAdapter {
public:
    /**
     * 一件の保存レコードから、保存対象7時間足と通貨強弱の表示内容を構築する。
     *
     * @param fromRecord 読み取り済みの観測履歴。IDが0以下の場合は記録なしとして扱う。
     * @param fromSymbolName 表示対象の通貨ペア。
     * @param fromDigits 表示価格の小数桁数。
     * @param fromData 出力先。前後移動の可否は呼び出し側で付与する。
     */
    static void build(const M5ObservationHistoryRecord &fromRecord, const string fromSymbolName,
            const int fromDigits, ElliotPanelData &fromData) {
        fromData.clear();
        fromData.symbolName = fromSymbolName;
        fromData.digits = fromDigits;
        fromData.savedTime = fromRecord.barTime;
        fromData.headerTime = "観測 SRV " + timeText(fromRecord.barTime);
        if (fromRecord.jstTime > 0) {
            fromData.headerTime = "観測 JST " + timeText(fromRecord.jstTime);
        }

        fromData.metadata = "取得 SRV " + timeText(fromRecord.captureTime)
            + " / Run " + IntegerToString(fromRecord.runId)
            + " / ID " + IntegerToString(fromRecord.id);
        fromData.hint = "前・次：表示範囲内 / 行選択で詳細 / M1は未収録";
        if (fromRecord.id <= 0) {
            fromData.status = "このM5時刻の記録はありません。";
        } else {
            fromData.rowCount = 7;
            for (int i = 0; i < 7; i++) {
                fillTableRow(fromRecord.frames[i], frameName(i), fromData.frames[i].row);
                fromData.frames[i].timeFrame = fromRecord.frames[i].timeFrame;
                fromData.frames[i].pointTime = fromRecord.frames[i].pointTime;
                fromData.frames[i].pointJstTime = fromRecord.frames[i].pointJstTime;
            }

            fillPanelStrength(fromRecord.strength, fromData.strength);
        }
    }

    /**
     * 保存値を共通表示データへ写し、欠損フラグをそのまま保持する。
     */
    static void fillTableRow(const M5ObservationHistoryFrame &fromFrame, const string fromTimeFrame,
            ElliotTableRowData &fromRow) {
        fromRow.clear();
        fromRow.timeFrameLabel = fromTimeFrame;
        fromRow.hasData = fromFrame.hasData;
        fromRow.mainWave = fromFrame.mainWave;
        fromRow.subWave = fromFrame.subWave;
        fromRow.originalWave = fromFrame.originalWave;
        fromRow.isUptrend = fromFrame.isUptrend;
        fromRow.isBuy = fromFrame.isBuy;
        fromRow.isConfirmed = fromFrame.isConfirmed;
        fromRow.isAdded = fromFrame.isAdded;
        fromRow.isEma200Buy = fromFrame.isEma200Buy;
        fromRow.isEma200Sell = fromFrame.isEma200Sell;
        fromRow.isPriceMovementValid = fromFrame.isPriceMovementValid;
        fromRow.priceMovementLevel = fromFrame.priceMovementLevel;
        fromRow.priceMovementActivityRatio = fromFrame.priceMovementActivityRatio;
        fromRow.hasPriceMovementActivityRatio = fromFrame.hasPriceMovementActivityRatio;
        fromRow.gmmaTrendCount = fromFrame.gmmaTrendCount;
        fromRow.hasGmmaTrendCount = fromFrame.hasGmmaTrendCount;
        fromRow.gmmaCrossCount = fromFrame.gmmaCrossCount;
        fromRow.hasGmmaCrossCount = fromFrame.hasGmmaCrossCount;
        fromRow.originalWaveIndex = fromFrame.originalWaveIndex;
        fromRow.previousMotiveSubElliotIndex = fromFrame.previousMotiveSubElliotIndex;
        fromRow.pointPipsDiff = fromFrame.pointPipsDiff;
        fromRow.hasPointPipsDiff = fromFrame.hasPointPipsDiff;
        fromRow.pointFibonacciPercent = fromFrame.pointFibonacciPercent;
        fromRow.hasPointFibonacciPercent = fromFrame.hasPointFibonacciPercent;
        fromRow.pointFibonacciExpansionPercent = fromFrame.pointFibonacciExpansionPercent;
        fromRow.hasPointFibonacciExpansionPercent = fromFrame.hasPointFibonacciExpansionPercent;
        fromRow.pointRate = fromFrame.pointRate;
        fromRow.hasPointRate = fromFrame.hasPointRate;
    }

    /**
     * 表示順に対応する固定の時間足名を返す。
     */
    static string frameName(const int fromIndex) {
        string names[] = {"MN1", "W1", "D1", "H4", "H1", "M15", "M5"};
        if (fromIndex < 0 || fromIndex >= ArraySize(names)) {
            return "—";
        }

        return names[fromIndex];
    }

    /**
     * 同時刻の別DB履歴であることと、実際の参照方式・モードを示す。
     */
    static string strengthTitle(const M5ObservationHistoryStrength &fromStrength) {
        string text = "同M5の通貨強弱履歴";
        if (fromStrength.weightLabel != "") {
            text += " / " + fromStrength.weightLabel;
        }
        if (fromStrength.sourceMode != "") {
            text += " / " + fromStrength.sourceMode;
        }

        return text;
    }

    /**
     * 強弱取得の失敗・設定OFF・未記録を、成功した順位表と区別する。
     */
    static string strengthStatusText(const M5ObservationHistoryStrength &fromStrength) {
        if (!fromStrength.enabled) {
            return "通貨強弱OFF";
        }
        if (fromStrength.status == "取得済み") {
            return "";
        }
        if (fromStrength.status == "") {
            return "未記録";
        }

        return fromStrength.status;
    }

    /**
     * 保存時刻をチャート共通のyyyy/MM/dd HH:mm:ss形式で表示し、時刻0は未記録として扱う。
     */
    static string timeText(const datetime fromTime) {
        if (fromTime <= 0) {
            return "未記録";
        }

        return TimeUtil::formatYyyymmddhhmiss(fromTime);
    }

private:
    /**
     * 同M5の強弱を、取得元の説明とともに共通表示へ渡す。
     */
    static void fillPanelStrength(const M5ObservationHistoryStrength &fromStrength,
            ElliotPanelStrength &fromTarget) {
        fromTarget.clear();
        fromTarget.enabled = fromStrength.enabled;
        fromTarget.title = strengthTitle(fromStrength);
        fromTarget.tooltip = "同じM5時刻の通貨強弱DB履歴です。観測保存時点の値とは限りません。";
        fromTarget.status = strengthStatusText(fromStrength);
        fromTarget.baseCurrency = fromStrength.baseCurrency;
        fromTarget.quoteCurrency = fromStrength.quoteCurrency;
        fillPanelStrengthPeriod(fromStrength.longMedium, fromTarget.longMedium);
        fillPanelStrengthPeriod(fromStrength.mediumShort, fromTarget.mediumShort);
    }

    /**
     * 順位と前M5比の取得状態をそのままコピーする。
     */
    static void fillPanelStrengthPeriod(const M5ObservationHistoryStrengthPeriod &fromPeriod,
            ElliotPanelStrengthPeriod &fromTarget) {
        fromTarget.valid = fromPeriod.valid;
        fromTarget.comparable = fromPeriod.comparable;
        fromTarget.baseRank = fromPeriod.baseRank;
        fromTarget.quoteRank = fromPeriod.quoteRank;
        fromTarget.gap = fromPeriod.gap;
        fromTarget.delta = fromPeriod.delta;
    }
};

#endif // MSTNG_DRAW_ELLIOT_PANEL_SAVED_ADAPTER_MQH
