#ifndef MSTNG_DRAW_ELLIOT_TABLE_FORMATTER_MQH
#define MSTNG_DRAW_ELLIOT_TABLE_FORMATTER_MQH

#include <Mstng\Draw\ElliotTableRowData.mqh>

/**
 * 現在値の表と保存波動パネルで共有する、5列と項目別Elliotの文字列・配色規則。
 * 表示元の取得・再分析やオブジェクト描画は行わない。
 */
class ElliotTableFormatter {
public:
    /**
     * 共通5列の見出しを返す。
     *
     * @param fromColumn 時間足からElliotまでの列番号。0から4。
     * @return 列見出し。範囲外は空文字列。
     */
    static string columnName(const int fromColumn) {
        string names[] = {"時間足", "BuySell", "EMA200", "値動き", "Elliot"};
        if (fromColumn < 0 || fromColumn >= ArraySize(names)) {
            return "";
        }

        return names[fromColumn];
    }

    /**
     * 表示文字に依存しない列のオブジェクト名用キーを返す。
     */
    static string columnKey(const int fromColumn) {
        string keys[] = {"TimeFrame", "BuySell", "EMA200", "PriceMovement", "Elliot"};
        if (fromColumn < 0 || fromColumn >= ArraySize(keys)) {
            return "";
        }

        return keys[fromColumn];
    }

    /**
     * 指定列の表示文字列を生成し、未記録と取得済みのゼロを区別する。
     */
    static string cellText(const ElliotTableRowData &fromRow, const int fromColumn,
            const int fromDigits) {
        if (fromColumn == 0) {
            return fromRow.timeFrameLabel;
        }

        if (fromColumn == 1) {
            if (!fromRow.hasData) {
                return "未記録";
            }

            return stateText(fromRow.isBuy, "BUY", "SELL");
        }

        if (fromColumn == 2) {
            return emaText(fromRow);
        }

        if (fromColumn == 3) {
            return movementText(fromRow);
        }

        if (fromColumn == 4) {
            return tableElliotText(fromRow, fromDigits);
        }

        return "";
    }

    /**
     * Elliotを項目別に表示する10列の短い見出しを返す。
     *
     * @param fromColumn 方向から価格までの列番号。0から9。
     * @return 列見出し。範囲外は空文字列。
     */
    static string elliotColumnName(const int fromColumn) {
        string names[] = {"方向", "主波", "副波", "元波", "確定", "補完", "前副", "F／FE", "値幅", "価格"};
        if (fromColumn < 0 || fromColumn >= ArraySize(names)) {
            return "";
        }

        return names[fromColumn];
    }

    /**
     * 分割したElliot列の、表示文字に依存しないオブジェクト名用キーを返す。
     */
    static string elliotColumnKey(const int fromColumn) {
        string keys[] = {"Direction", "MainWave", "SubWave", "OriginalWave", "Confirmed",
            "Added", "PreviousSub", "Fibonacci", "Pips", "Price"};
        if (fromColumn < 0 || fromColumn >= ArraySize(keys)) {
            return "";
        }

        return keys[fromColumn];
    }

    /**
     * 波動情報を一項目ずつ返し、未知の「?」と該当なしの「—」を区別する。
     * F・FEの選択と数値の精度は、既存のElliot複合表示と同じ規則を使用する。
     *
     * @param fromRow 表示元の波動情報。
     * @param fromColumn 方向から価格までの列番号。0から9。
     * @param fromDigits ポイント価格の小数桁数。
     * @return 省略前のセル文字列。範囲外は空文字列。
     */
    static string elliotCellText(const ElliotTableRowData &fromRow, const int fromColumn,
            const int fromDigits) {
        if (fromColumn < 0 || fromColumn >= 10) {
            return "";
        }

        if (!fromRow.hasData) {
            return "?";
        }

        if (fromColumn == 0) {
            return compactText(stateText(fromRow.isUptrend, "▲", "▼"));
        }

        if (fromColumn == 1) {
            if (StringLen(fromRow.mainWave) == 0) {
                return "?";
            }

            return fromRow.mainWave;
        }

        if (fromColumn == 2) {
            if (StringLen(fromRow.subWave) == 0) {
                return "—";
            }

            return fromRow.subWave;
        }

        if (fromColumn == 3) {
            if (StringLen(fromRow.originalWave) == 0) {
                return "?";
            }

            return fromRow.originalWave;
        }

        if (fromColumn == 4) {
            return compactText(stateText(fromRow.isConfirmed, "確定", "未確定"));
        }

        if (fromColumn == 5) {
            return compactText(stateText(fromRow.isAdded, "★", "—"));
        }

        if (fromColumn == 6) {
            if (fromRow.previousMotiveSubElliotIndex < 0) {
                return "?";
            }

            if (fromRow.previousMotiveSubElliotIndex == 0) {
                return "—";
            }

            return IntegerToString(fromRow.previousMotiveSubElliotIndex);
        }

        if (fromColumn == 7) {
            if (fromRow.originalWaveIndex < 0) {
                return "?";
            }

            if (fromRow.originalWaveIndex <= 1) {
                return "—";
            }

            if (fromRow.originalWaveIndex % 2 == 0) {
                return "F " + compactText(numberText(fromRow.pointFibonacciPercent,
                    fromRow.hasPointFibonacciPercent, 1, "%"));
            }

            return "FE " + compactText(numberText(fromRow.pointFibonacciExpansionPercent,
                fromRow.hasPointFibonacciExpansionPercent, 1, "%"));
        }

        if (fromColumn == 8) {
            return compactText(numberText(fromRow.pointPipsDiff, fromRow.hasPointPipsDiff, 1, "p"));
        }

        return compactText(numberText(fromRow.pointRate, fromRow.hasPointRate, fromDigits));
    }

    /**
     * 正式項目名と省略前の値、短縮記号の意味をセルの補足として返す。
     */
    static string elliotCellTooltip(const ElliotTableRowData &fromRow, const int fromColumn,
            const int fromDigits) {
        string names[] = {"波動方向", "主波", "副次波", "元波（再分析前の主波）", "確定状態",
            "補完状態", "前推進波の副次波", "F／FE", "値幅（pips）", "ポイント価格"};
        if (fromColumn < 0 || fromColumn >= ArraySize(names)) {
            return "";
        }

        string value = elliotCellText(fromRow, fromColumn, fromDigits);
        string text = names[fromColumn] + "：" + value;
        if (value == "?" || StringFind(value, " ?") >= 0) {
            text += "（未記録・不明）";
        } else if (value == "—") {
            text += "（該当なし）";
        } else if (fromColumn == 0 && value == "▲") {
            text += "（上昇）";
        } else if (fromColumn == 0 && value == "▼") {
            text += "（下降）";
        } else if (fromColumn == 5 && value == "★") {
            text += "（補完ポイント）";
        }

        if (fromColumn == 7) {
            text += "\nF：リトレースメント / FE：エクスパンション";
        }

        return text;
    }

    /**
     * 指定列の判定結果と表示先の配色から文字色を返す。
     */
    static color cellColor(const ElliotTableRowData &fromRow, const int fromColumn,
            const ElliotTablePalette &fromPalette) {
        if (!fromRow.hasData) {
            return fromPalette.unknownColor;
        }

        if (fromColumn == 0 || fromColumn == 1) {
            return analysisColor(fromRow.isBuy, fromPalette);
        }

        if (fromColumn == 2) {
            return emaColor(fromRow, fromPalette);
        }

        if (fromColumn == 3) {
            return movementColor(fromRow, fromPalette);
        }

        if (fromColumn == 4) {
            return elliotColor(fromRow, fromPalette);
        }

        return fromPalette.unknownColor;
    }

    /**
     * 主波・副次波を省略上限に収め、波動方向を前へ付ける。
     *
     * @param fromLimit 波動ラベルの文字数上限。0以下は全文を表示する。
     */
    static string waveText(const ElliotTableRowData &fromRow, const int fromLimit) {
        if (!fromRow.hasData) {
            return "未記録";
        }

        string direction = "?";
        if (fromRow.isUptrend == 1) {
            direction = "▲";
        } else if (fromRow.isUptrend == 0) {
            direction = "▼";
        }

        string wave = fromRow.mainWave;
        if (StringLen(wave) == 0) {
            wave = "—";
        }

        if (StringLen(fromRow.subWave) > 0) {
            wave += "." + fromRow.subWave;
        }

        return direction + shorten(wave, fromLimit);
    }

    /**
     * ホバー用の波動方向色を返す。表の分析方向色とは独立して扱う。
     */
    static color waveColor(const ElliotTableRowData &fromRow, const ElliotTablePalette &fromPalette) {
        if (fromRow.hasData && fromRow.isUptrend == 1) {
            return fromPalette.waveUpColor;
        }

        if (fromRow.hasData && fromRow.isUptrend == 0) {
            return fromPalette.waveDownColor;
        }

        return fromPalette.unknownColor;
    }

    /**
     * 値動きの取得状態とレベルを表示名へ変換する。
     */
    static string movementLevelText(const ElliotTableRowData &fromRow) {
        if (!fromRow.hasData || fromRow.isPriceMovementValid < 0) {
            return "未記録";
        }

        if (fromRow.isPriceMovementValid == 0) {
            return "判定不能";
        }

        if (fromRow.priceMovementLevel < 0) {
            return "未記録";
        }

        if (fromRow.priceMovementLevel == 1) {
            return "静か";
        }

        if (fromRow.priceMovementLevel == 2) {
            return "通常";
        }

        if (fromRow.priceMovementLevel == 3) {
            return "活発";
        }

        return "判定不能";
    }

private:
    /**
     * 既存の数値・状態整形を再利用し、未記録表示だけを狭いセル向けに短縮する。
     */
    static string compactText(const string fromText) {
        if (fromText == "未記録") {
            return "?";
        }

        return fromText;
    }

    /**
     * 前推進波の副次波・確定状態・波動・F／FE・値幅・価格を同じ順序で整形する。
     */
    static string tableElliotText(const ElliotTableRowData &fromRow, const int fromDigits) {
        if (!fromRow.hasData) {
            return "未記録";
        }

        string text = "";
        if (fromRow.previousMotiveSubElliotIndex > 0) {
            text += "[" + IntegerToString(fromRow.previousMotiveSubElliotIndex) + "副] ";
        }

        if (fromRow.isConfirmed == 0) {
            text += "【未】";
        }

        if (fromRow.isAdded == 1) {
            text += "★";
        }

        text += waveText(fromRow, 0);
        if (StringLen(fromRow.originalWave) > 0 && fromRow.originalWave != fromRow.mainWave) {
            text += "[" + fromRow.originalWave + "]";
        }

        if (fromRow.originalWaveIndex > 1) {
            if (fromRow.originalWaveIndex % 2 == 0) {
                text += "[F" + numberText(fromRow.pointFibonacciPercent,
                    fromRow.hasPointFibonacciPercent, 1, "%") + "]";
            } else {
                text += "[FE" + numberText(fromRow.pointFibonacciExpansionPercent,
                    fromRow.hasPointFibonacciExpansionPercent, 1, "%") + "]";
            }
        } else if (fromRow.originalWaveIndex < 0) {
            text += "[F/FE未記録]";
        }

        text += "<" + numberText(fromRow.pointPipsDiff, fromRow.hasPointPipsDiff, 1, "p") + ">";
        text += numberText(fromRow.pointRate, fromRow.hasPointRate, fromDigits);

        return text;
    }

    /**
     * 分析方向の表示色を返す。
     */
    static color analysisColor(const int fromIsBuy, const ElliotTablePalette &fromPalette) {
        if (fromIsBuy == 1) {
            return fromPalette.upColor;
        }

        if (fromIsBuy == 0) {
            return fromPalette.downColor;
        }

        return fromPalette.unknownColor;
    }

    /**
     * 補完・未確定・分析方向の優先順でElliot列の色を選ぶ。
     */
    static color elliotColor(const ElliotTableRowData &fromRow, const ElliotTablePalette &fromPalette) {
        if (fromRow.isAdded == 1) {
            return fromPalette.addedColor;
        }

        if (fromRow.isAdded < 0 || fromRow.isConfirmed < 0 || fromRow.isBuy < 0) {
            return fromPalette.unknownColor;
        }

        if (fromRow.isConfirmed == 0) {
            if (fromRow.isBuy == 1) {
                return fromPalette.unconfirmedUpColor;
            }

            return fromPalette.unconfirmedDownColor;
        }

        return analysisColor(fromRow.isBuy, fromPalette);
    }

    /**
     * EMA200のフラグをBUY・SELL・NONEへ変換する。
     */
    static string emaText(const ElliotTableRowData &fromRow) {
        if (!fromRow.hasData || fromRow.isEma200Buy < 0 || fromRow.isEma200Sell < 0) {
            return "未記録";
        }

        if (fromRow.isEma200Buy == 1 && fromRow.isEma200Sell == 0) {
            return "BUY";
        }

        if (fromRow.isEma200Sell == 1 && fromRow.isEma200Buy == 0) {
            return "SELL";
        }

        if (fromRow.isEma200Buy == 0 && fromRow.isEma200Sell == 0) {
            return "NONE";
        }

        return "判定不能";
    }

    /**
     * EMA200独自の方向に対応する色を返す。
     */
    static color emaColor(const ElliotTableRowData &fromRow, const ElliotTablePalette &fromPalette) {
        string direction = emaText(fromRow);
        if (direction == "BUY") {
            return fromPalette.upColor;
        }

        if (direction == "SELL") {
            return fromPalette.downColor;
        }

        if (direction == "NONE") {
            return fromPalette.neutralColor;
        }

        return fromPalette.unknownColor;
    }

    /**
     * 値動きの状態と活動度を共通書式へ変換する。
     */
    static string movementText(const ElliotTableRowData &fromRow) {
        string text = movementLevelText(fromRow);
        if (!fromRow.hasData || fromRow.isPriceMovementValid <= 0 || fromRow.priceMovementLevel < 0) {
            return text;
        }

        return text + " " + numberText(fromRow.priceMovementActivityRatio,
            fromRow.hasPriceMovementActivityRatio, 2);
    }

    /**
     * 値動きの静か・通常・活発に対応する色を返す。
     */
    static color movementColor(const ElliotTableRowData &fromRow, const ElliotTablePalette &fromPalette) {
        if (fromRow.isPriceMovementValid == 1) {
            if (fromRow.priceMovementLevel == 2) {
                return fromPalette.neutralColor;
            }

            if (fromRow.priceMovementLevel == 3) {
                return fromPalette.movementActiveColor;
            }
        }

        return fromPalette.unknownColor;
    }

    /**
     * 取得済みのゼロを保ち、欠損した数値は未記録として表示する。
     */
    static string numberText(const double fromValue, const bool fromHasValue,
            const int fromDigits, const string fromSuffix = "") {
        if (!fromHasValue) {
            return "未記録";
        }

        return DoubleToString(fromValue, MathMax(0, MathMin(8, fromDigits))) + fromSuffix;
    }

    /**
     * 0・1・未記録の状態を表示文字列へ変換する。
     */
    static string stateText(const int fromState, const string fromTrue, const string fromFalse) {
        if (fromState == 1) {
            return fromTrue;
        }

        if (fromState == 0) {
            return fromFalse;
        }

        return "未記録";
    }

    /**
     * 上限を超えたラベルを省略記号付きで短縮する。0以下は全文を保持する。
     */
    static string shorten(const string fromText, const int fromLimit) {
        if (fromLimit <= 0 || StringLen(fromText) <= fromLimit) {
            return fromText;
        }

        return StringSubstr(fromText, 0, fromLimit - 1) + "…";
    }
};

#endif // MSTNG_DRAW_ELLIOT_TABLE_FORMATTER_MQH
