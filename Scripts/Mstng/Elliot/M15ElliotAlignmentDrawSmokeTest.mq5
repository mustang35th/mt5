//+------------------------------------------------------------------+
//|                         M15ElliotAlignmentDrawSmokeTest.mq5        |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Mstng\Draw\DrawAlignedElliotAllList.mqh>

/** 失敗した検証件数。 */
int failureCount = 0;

/** 実行した検証件数。 */
int assertionCount = 0;

/** 描画状態の検証画像をFilesへ保存する場合true。 */
input bool saveScreenshot = true;

/**
 * 検証結果を集計する。
 */
void assertCondition(const bool fromSuccess, const string fromCaseName) {
    assertionCount++;
    if (!fromSuccess) {
        failureCount++;
        Print("FAIL ", fromCaseName);
    }
}

/**
 * 計算済みのEMA状態を設定する。0=NONE、1=BUY、-1=SELL。
 */
void setEma(Elliot *fromElliot, const int fromDirection) {
    Ema200 *ema200 = GetPointer(fromElliot.oscillator.ema200);
    ema200.setMarketContext(fromElliot.marketContext);
    ema200.close1 = 1.10;
    ema200.ema200Shift1 = 1.10;
    ema200.ema200Compare = 1.10;
    ema200.slopePips = 0.0;
    ema200.closeEma200DiffPips = 0.0;
    ema200.closePosition = EMA200_POSITION_EQUAL;
    ema200.slopeDirection = EMA200_SLOPE_NONE;
    ema200.upCount = 0;
    ema200.downCount = 0;
    ema200.trendCount = 0;
    ema200.isBuy = fromDirection == 1;
    ema200.isSell = fromDirection == -1;
    ema200.buySellLabel = "NONE";

    if (fromDirection == 1) {
        ema200.close1 = 1.11;
        ema200.ema200Compare = 1.09;
        ema200.slopePips = 100.0;
        ema200.closeEma200DiffPips = 100.0;
        ema200.closePosition = EMA200_POSITION_ABOVE;
        ema200.slopeDirection = EMA200_SLOPE_UP;
        ema200.upCount = 4;
        ema200.trendCount = 4;
        ema200.buySellLabel = "BUY";
    } else if (fromDirection == -1) {
        ema200.close1 = 1.09;
        ema200.ema200Compare = 1.11;
        ema200.slopePips = -100.0;
        ema200.closeEma200DiffPips = -100.0;
        ema200.closePosition = EMA200_POSITION_BELOW;
        ema200.slopeDirection = EMA200_SLOPE_DOWN;
        ema200.downCount = 4;
        ema200.trendCount = -4;
        ema200.buySellLabel = "SELL";
    }
}

/**
 * 1時間足の最小の計算済み分析結果を生成する。
 */
Elliot *createReadyElliot(
    const string fromSymbol,
    const ENUM_TIMEFRAMES fromTimeFrame,
    const bool fromIsBuy
) {
    Elliot *elliot = new Elliot(fromSymbol, fromTimeFrame);
    if (elliot == NULL) {
        return NULL;
    }

    elliot.isBuy = fromIsBuy;
    CArrayObj pointList;
    ZigZagPoint *point = new ZigZagPoint(elliot.marketContext);
    if (point == NULL) {
        delete elliot;

        return NULL;
    }

    point.elliotIndex = 1;
    point.isElliotAlphabet = false;
    point.setElliotLabel();
    if (!pointList.Add(point)) {
        delete point;
        delete elliot;

        return NULL;
    }

    Wave *wave = new Wave(elliot.marketContext, pointList, fromIsBuy, true);
    if (wave == NULL || !elliot.waveList.Add(wave)) {
        if (wave != NULL) {
            delete wave;
        }

        delete elliot;

        return NULL;
    }

    int emaDirection = -1;
    if (fromIsBuy) {
        emaDirection = 1;
    }

    setEma(elliot, emaDirection);

    return elliot;
}

/**
 * MN1～M15の合成結果を一覧へ追加し、不一致の足を設定する。
 */
bool addFixture(
    ElliotAllList &fromList,
    const string fromSymbol,
    const bool fromIsBuy,
    const ENUM_TIMEFRAMES fromAnalysisOpposite = PERIOD_CURRENT,
    const ENUM_TIMEFRAMES fromEmaMismatch = PERIOD_CURRENT,
    const bool fromIsEmaNone = false
) {
    ElliotAll *elliotAll = new ElliotAll(fromSymbol, PERIOD_M15);
    if (elliotAll == NULL) {
        return false;
    }

    ENUM_TIMEFRAMES timeFrames[] = {
        PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15
    };
    for (int i = 0; i < ArraySize(timeFrames); i++) {
        Elliot *elliot = createReadyElliot(fromSymbol, timeFrames[i], fromIsBuy);
        if (elliot == NULL || !elliotAll.elliotList.Add(elliot)) {
            if (elliot != NULL) {
                delete elliot;
            }

            delete elliotAll;

            return false;
        }

        if (timeFrames[i] == fromAnalysisOpposite) {
            elliot.isBuy = !fromIsBuy;
        }

        if (timeFrames[i] == fromEmaMismatch) {
            int emaDirection = 1;
            if (fromIsBuy) {
                emaDirection = -1;
            }

            if (fromIsEmaNone) {
                emaDirection = 0;
            }

            setEma(elliot, emaDirection);
        }
    }

    elliotAll.elliotCurrent = elliotAll.getElliot(PERIOD_M15);
    elliotAll.isAnalysisSucceeded = true;
    if (!fromList.elliotAllList.Add(elliotAll)) {
        delete elliotAll;

        return false;
    }

    fromList.targetCount++;

    return true;
}

/**
 * 実際に生成されたタイトルから検証対象描画の専用接頭辞を取得する。
 */
string findPrefix(const int fromInstanceIndex) {
    string prefix = Constant::PREFIX_FIXED + "ZzElList_"
        + IntegerToString(fromInstanceIndex) + "_";
    int total = ObjectsTotal(0, 0, -1);
    for (int i = 0; i < total; i++) {
        string objectName = ObjectName(0, i, 0, -1);
        int nameLength = StringLen(objectName);
        if (StringFind(objectName, prefix) == 0
                && StringSubstr(objectName, nameLength - 5) == "Title") {
            return StringSubstr(objectName, 0, nameLength - 5);
        }
    }

    return "";
}

/**
 * 指定セルのオブジェクト名を返す。
 */
string cellName(
    const string fromPrefix,
    const int fromRow,
    const int fromColumn,
    const bool fromEma = false
) {
    string columnText = "_Column_";
    if (fromEma) {
        columnText = "_EmaColumn_";
    }

    return fromPrefix + "Row_" + IntegerToString(fromRow)
        + columnText + IntegerToString(fromColumn);
}

/**
 * 表示済みシンボルの行番号を探す。GMOの付記は照合から除く。
 */
int findSymbolRow(const string fromPrefix, const string fromSymbol) {
    for (int i = 0; i < 10; i++) {
        string objectName = cellName(fromPrefix, i, 0);
        if (ObjectFind(0, objectName) >= 0
                && StringSubstr(ObjectGetString(0, objectName, OBJPROP_TEXT), 0, 6)
                    == fromSymbol) {
            return i;
        }
    }

    return -1;
}

/**
 * セル文字列が期待値と一致することを確認する。
 */
void assertCell(
    const string fromPrefix,
    const int fromRow,
    const int fromColumn,
    const bool fromEma,
    const string fromExpected
) {
    string objectName = cellName(fromPrefix, fromRow, fromColumn, fromEma);
    assertCondition(ObjectFind(0, objectName) >= 0
        && ObjectGetString(0, objectName, OBJPROP_TEXT) == fromExpected,
        "cell " + objectName + " = " + fromExpected);
}

/**
 * 実オブジェクトを調べて分類、方向、表示内容、並びを検証する。
 */
void validatePopulatedGroups(const string &fromPrefixes[]) {
    string symbols[] = {
        "EURUSD", "USDJPY", "AUDUSD", "USDCHF", "GBPUSD", "NZDUSD",
        "CADJPY", "EURJPY", "GBPJPY", "GBPCHF"
    };
    int expectedGroups[] = {0, 0, 1, 1, 2, 2, 2, 3, 3, -1};
    bool expectedBuys[] = {true, false, true, false, true, true, false, true, false, true};
    int expectedBuyCounts[] = {1, 1, 2, 1};
    int expectedSellCounts[] = {1, 1, 1, 1};

    for (int i = 0; i < ArraySize(symbols); i++) {
        int appearances = 0;
        for (int j = 0; j < ArraySize(fromPrefixes); j++) {
            int row = findSymbolRow(fromPrefixes[j], symbols[i]);
            if (row < 0) {
                continue;
            }

            appearances++;
            assertCondition(j == expectedGroups[i], "exclusive group " + symbols[i]);
            bool isBuyPanel = row < expectedBuyCounts[j];
            assertCondition(isBuyPanel == expectedBuys[i], "majority panel " + symbols[i]);
            string panelName = fromPrefixes[j] + "PanelBuy";
            if (!expectedBuys[i]) {
                panelName = fromPrefixes[j] + "PanelSell";
            }

            long cellLeft = ObjectGetInteger(0, cellName(fromPrefixes[j], row, 0), OBJPROP_XDISTANCE);
            long panelLeft = ObjectGetInteger(0, panelName, OBJPROP_XDISTANCE);
            long panelWidth = ObjectGetInteger(0, panelName, OBJPROP_XSIZE);
            assertCondition(cellLeft >= panelLeft && cellLeft < panelLeft + panelWidth,
                "left/right coordinates " + symbols[i]);
            assertCell(fromPrefixes[j], row, 2, true, "-");
        }

        int expectedAppearances = 1;
        if (expectedGroups[i] < 0) {
            expectedAppearances = 0;
        }

        assertCondition(appearances == expectedAppearances, "one table per symbol " + symbols[i]);
    }

    for (int i = 0; i < ArraySize(fromPrefixes); i++) {
        string expectedCount = StringFormat("基準BUY %d・SELL %d", expectedBuyCounts[i], expectedSellCounts[i]);
        string title = ObjectGetString(0, fromPrefixes[i] + "Title", OBJPROP_TEXT);
        assertCondition(StringFind(title, expectedCount) >= 0, "title counts group " + IntegerToString(i));
        assertCondition(ObjectGetString(0, fromPrefixes[i] + "HeaderBuy_1", OBJPROP_TEXT) == "不一致",
            "mismatch column header " + IntegerToString(i));
        assertCondition(ObjectFind(0, fromPrefixes[i] + "EntryLegendPanel") < 0
            && ObjectFind(0, fromPrefixes[i] + "H1RunnerUpTitle") < 0, "no extra panels " + IntegerToString(i));
        assertCondition((ObjectFind(0, fromPrefixes[i] + "TitleTime") >= 0) == (i == 0),
            "one shared update legend " + IntegerToString(i));
        assertCondition((ObjectFind(0, fromPrefixes[i] + "M15Legend") >= 0) == (i == 0),
            "one shared classification legend " + IntegerToString(i));
        if (i == 0) {
            string legend = ObjectGetString(0, fromPrefixes[i] + "M15Legend", OBJPROP_TEXT);
            assertCondition(legend == "基準=isBuy多数派 / 上:波動 下:EMA / *=逆 NONE=方向なし -=対象外",
                "complete NONE and excluded legend");
            string schedule = ObjectGetString(0, fromPrefixes[i] + "TitleTime", OBJPROP_TEXT);
            assertCondition(StringFind(schedule, "更新：5分ごと") >= 0
                && StringFind(schedule, "基準=") < 0 && StringFind(schedule, "NONE") < 0,
                "schedule separate from classification legend");
        }

        int rowCount = expectedBuyCounts[i] + expectedSellCounts[i];
        assertCondition(ObjectFind(0, cellName(fromPrefixes[i], rowCount, 0)) < 0,
            "no unexpected row " + IntegerToString(i));
        for (int j = 0; j < rowCount; j++) {
            string detail = ObjectGetString(0, cellName(fromPrefixes[i], j, 1), OBJPROP_TEXT);
            assertCondition(StringFind(detail, "isBuy") == 0 && detail != "READY",
                "classification replaces entry rank");
        }
    }

    int reverseM15Row = findSymbolRow(fromPrefixes[1], "AUDUSD");
    assertCell(fromPrefixes[1], reverseM15Row, 1, false, "isBuy逆:M15");
    assertCell(fromPrefixes[1], reverseM15Row, 0, true, "M15 SELL");
    assertCondition(StringFind(ObjectGetString(0, cellName(fromPrefixes[1], reverseM15Row, 7), OBJPROP_TEXT), "*") == 0,
        "reversed M15 wave highlighted");
    int noneRow = findSymbolRow(fromPrefixes[2], "NZDUSD");
    int oppositeRow = findSymbolRow(fromPrefixes[2], "GBPUSD");
    assertCondition(noneRow >= 0 && oppositeRow > noneRow, "NONE before reverse on BUY panel");
    assertCell(fromPrefixes[2], noneRow, 3, true, "NONE");
    assertCell(fromPrefixes[2], noneRow, 1, true, "EMA NONE:W1");
    assertCell(fromPrefixes[2], oppositeRow, 6, true, "*SELL");
    assertCell(fromPrefixes[2], oppositeRow, 1, true, "EMA逆:H1");
    assertCondition(ObjectGetInteger(0, cellName(fromPrefixes[2], noneRow, 3, true), OBJPROP_COLOR)
        != ObjectGetInteger(0, cellName(fromPrefixes[2], oppositeRow, 6, true), OBJPROP_COLOR),
        "NONE muted and reverse highlighted colors differ");
    int sameFootRow = findSymbolRow(fromPrefixes[3], "EURJPY");
    assertCell(fromPrefixes[3], sameFootRow, 1, false, "isBuy逆:H4");
    assertCell(fromPrefixes[3], sameFootRow, 1, true, "EMA逆:H4");
    int separateFeetRow = findSymbolRow(fromPrefixes[3], "GBPJPY");
    assertCell(fromPrefixes[3], separateFeetRow, 1, false, "isBuy逆:MN1");
    assertCell(fromPrefixes[3], separateFeetRow, 1, true, "EMA NONE:M15");
}

/**
 * 4分類の実描画と空テーブルへの遷移、破棄を検証する。
 */
void validateDrawing() {
    ElliotAllList fixtures(PERIOD_M15, false);
    assertCondition(addFixture(fixtures, "EURUSD", true), "all BUY fixture");
    assertCondition(addFixture(fixtures, "USDJPY", false), "all SELL fixture");
    assertCondition(addFixture(fixtures, "AUDUSD", true, PERIOD_M15), "M15 reverse fixture");
    assertCondition(addFixture(fixtures, "USDCHF", false, PERIOD_MN1), "MN1 reverse fixture");
    assertCondition(addFixture(fixtures, "GBPUSD", true, PERIOD_CURRENT, PERIOD_H1), "EMA reverse fixture");
    assertCondition(addFixture(fixtures, "NZDUSD", true, PERIOD_CURRENT, PERIOD_W1, true), "EMA NONE fixture");
    assertCondition(addFixture(fixtures, "CADJPY", false, PERIOD_CURRENT, PERIOD_M15, true), "SELL NONE fixture");
    assertCondition(addFixture(fixtures, "EURJPY", true, PERIOD_H4, PERIOD_H4), "same-foot both fixture");
    assertCondition(addFixture(fixtures, "GBPJPY", false, PERIOD_MN1, PERIOD_M15, true), "different-foot both fixture");
    assertCondition(addFixture(fixtures, "GBPCHF", true, PERIOD_CURRENT, PERIOD_H1, true), "excluded fixture");
    if (fixtures.elliotAllList.Total() != 10) {
        return;
    }

    ElliotAll *excluded = fixtures.elliotAllList.At(9);
    setEma(excluded.getElliot(PERIOD_H4), -1);
    ElliotDirectionAlignmentDecision decision(PERIOD_MN1, ELLIOT_DIRECTION_ALIGNMENT_RULE_M15_MN1_WITH_EMA200);
    DrawAlignedElliotAllList *drawers[4];
    string prefixes[4];
    int populatedHeights[4];
    int nextY = 12;
    for (int i = 0; i < ArraySize(drawers); i++) {
        drawers[i] = new DrawAlignedElliotAllList(0, 9400 + i, ELLIOT_LIST_SORT_M15_ELLIOT_EMA);
        assertCondition(drawers[i] != NULL, "drawer allocation " + IntegerToString(i));
        if (drawers[i] == NULL) {
            continue;
        }

        drawers[i].setM15AlignmentGroup((M15ElliotAlignmentGroup)i, i == 0);
        drawers[i].setYDistance(nextY);
        drawers[i].setUpdateSchedule(PERIOD_M5, D'2026.10.13 12:00:00');
        assertCondition(drawers[i].draw(GetPointer(fixtures), GetPointer(decision), PERIOD_M15),
            "draw populated group " + IntegerToString(i));
        prefixes[i] = findPrefix(9400 + i);
        assertCondition(prefixes[i] != "", "find owned prefix " + IntegerToString(i));
        assertCondition(ObjectGetInteger(0, prefixes[i] + "PanelBuy", OBJPROP_YDISTANCE) == nextY,
            "vertical placement " + IntegerToString(i));
        populatedHeights[i] = drawers[i].getRenderedHeight();
        nextY += populatedHeights[i] + 8;
    }

    validatePopulatedGroups(prefixes);
    ElliotAllList emptyFixtures(PERIOD_M15, false);
    for (int i = 0; i < ArraySize(drawers); i++) {
        if (drawers[i] == NULL) {
            continue;
        }

        assertCondition(drawers[i].draw(GetPointer(emptyFixtures), GetPointer(decision), PERIOD_M15),
            "nonempty to empty " + IntegerToString(i));
        int expectedEmptyHeight = 27;
        if (i == 0) {
            expectedEmptyHeight = 47;
        }

        assertCondition(drawers[i].getRenderedHeight() == expectedEmptyHeight
            && drawers[i].getRenderedHeight() < populatedHeights[i], "compact empty header " + IntegerToString(i));
        assertCondition(ObjectFind(0, cellName(prefixes[i], 0, 0)) < 0
            && ObjectFind(0, prefixes[i] + "HeaderBuy_0") < 0
            && ObjectFind(0, prefixes[i] + "GroupBuy") < 0, "old rows removed " + IntegerToString(i));
        assertCondition(StringFind(ObjectGetString(0, prefixes[i] + "Title", OBJPROP_TEXT), "基準BUY 0・SELL 0") >= 0,
            "empty title counts " + IntegerToString(i));
        assertCondition(drawers[i].draw(GetPointer(fixtures), GetPointer(decision), PERIOD_M15),
            "empty to populated " + IntegerToString(i));
        assertCondition(drawers[i].getRenderedHeight() == populatedHeights[i], "restored height " + IntegerToString(i));
    }

    validatePopulatedGroups(prefixes);
    ChartRedraw();
    if (saveScreenshot) {
        assertCondition(ChartScreenShot(0, "M15ElliotAlignmentDrawSmokeTest.png", 1920, 1080, ALIGN_LEFT),
            "save four-table screenshot");
    }

    for (int i = 0; i < ArraySize(drawers); i++) {
        if (drawers[i] != NULL) {
            delete drawers[i];
            drawers[i] = NULL;
        }

        if (prefixes[i] != "") {
            int remainingCount = 0;
            int total = ObjectsTotal(0, 0, -1);
            for (int j = 0; j < total; j++) {
                if (StringFind(ObjectName(0, j, 0, -1), prefixes[i]) == 0) {
                    remainingCount++;
                }
            }

            assertCondition(remainingCount == 0, "all owned objects deleted " + IntegerToString(i));
        }
    }
}

/**
 * 市場データや注文を使わず合成結果だけで描画を検証する。
 */
void OnStart() {
    failureCount = 0;
    assertionCount = 0;
    validateDrawing();
    if (failureCount == 0) {
        PrintFormat("M15ElliotAlignmentDrawSmokeTest PASS assertions=%d", assertionCount);

        return;
    }

    PrintFormat("M15ElliotAlignmentDrawSmokeTest FAIL count=%d assertions=%d",
        failureCount, assertionCount);
}
