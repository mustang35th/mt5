# ZigZagElliotList 仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象 | `Indicators/ZigZagElliotList.mq5` |
| 対象バージョン | 1.34 |
| 作成日 | 2026-09-12 |
| 記述基準 | 作成時点のワークスペース内の実装 |
| 形式 | MetaTrader 5用チャートウィンドウ型インジケーター |

本書は、一覧の抽出・表示・並び替え、入力設定、更新処理および全28通貨Alert DB収集の仕様をまとめる。Elliott波動そのものの分析アルゴリズムとDB物理設計は、関連クラス・既存設計書を参照する。

## 2. 目的と機能範囲

主要28通貨ペアを複数時間足で分析し、方向一致条件を満たす通貨をBUY・SELL別に表示する。各行には波動、EMA方向、Fibonacci比率、表示用優先度を表示する。

- 一覧モードはCHART、D1固定、H4固定、H1＋M5独立2段の4種類。
- 分析および時間足列はMN1から一覧基準足までを使用する。一致条件を調べる範囲とは区別する。
- チャートオブジェクトで描画する。1本の非表示バッファを持ち、描画種別は`DRAW_NONE`。
- 自動発注・決済は行わない。
- DB保存を有効にした場合、テスターのH1で28通貨のMTF_3in3 Alertを収集する。

## 3. 対象通貨と時間足

### 3.1 対象通貨

`SymbolNameInfoAll.setAll()`の次の28通貨を対象とする。入力による通貨選択はない。

| グループ | 通貨ペア |
|---|---|
| JPY | USDJPY、EURJPY、GBPJPY、AUDJPY、NZDJPY、CADJPY、CHFJPY |
| USD | EURUSD、GBPUSD、AUDUSD、NZDUSD、USDCAD、USDCHF |
| GBP | EURGBP、GBPAUD、GBPNZD、GBPCAD、GBPCHF |
| EUR | EURAUD、EURNZD、EURCAD、EURCHF |
| AUD | AUDNZD、AUDCAD、AUDCHF |
| NZD | NZDCAD、NZDCHF |
| CAD | CADCHF |

DB有効時は実シンボル名を解決する。標準名を優先し、存在しない場合は標準名を含み、基軸通貨・決済通貨が一致する候補のうち最短名を選ぶ。全対象を解決できなければ初期化に失敗する。この名前解決はDB無効時には実行しない。

### 3.2 時間足の系列

```text
MN1 → W1 → D1 → H4 → H1 → M15 → M5 → M1
```

上位1足・上位2足とは、この系列内の直上の足を指す。M30やH2などは範囲生成の対象外。CHARTでは一致判定の開始が原則D1なので、対応する一覧基準足はD1・H4・H1・M15・M5・M1。CHARTのW1・MN1はD1からの範囲を生成できず、初期化エラーになる。

## 4. 入力設定

### 4.1 一覧表示・方向一致

| 変数名 | 画面名 | 初期値 | 適用範囲 |
|---|---|---|---|
| `sortType` | 並び順（CHARTのみ） | `ELLIOT_LIST_SORT_M15_ELLIOT_EMA`（1） | CHARTのH1以外。専用ソートは該当足でのみ適用 |
| `listMode` | 一覧モード | CHART（0） | 全体 |
| `d1AlignmentMode` | D1条件（D1/H4・全H1モード） | W1＝D1（0） | D1固定、H4固定、H1一覧 |
| `h1AlignmentMode` | H1条件（CHART・H1／H1＋M5上段） | D1＝H4＝H1（0） | CHARTのH1、独立2段の上段H1 |

`sortType`の値は、0：ENTRY PRIORITY、1：M15 ELLIOTT / EMA200、2：D1 ELLIOTT / EMA200、3：H1 D1 CONDITION / ENTRY。指定値と表示足の組み合わせが専用処理の対象外の場合、ENTRY優先度で比較する。CHARTのH1は入力値にかかわらずH1専用順を使用する。

### 4.2 Alert DBと収集期間

| 変数名 | 画面名 | 初期値 |
|---|---|---|
| `mtf3In3AlertDatabaseEnabled` | DB保存を有効化 | `false` |
| `mtf3In3AlertDatabaseFileName` | DBファイル名 | `mstng-zigzag-elliot-alert.sqlite` |
| `mtf3In3AlertDatabaseUseCommonFolder` | Commonフォルダを使用（必須） | `true` |
| `mtf3In3AlertTesterStartTime` | Tester開始時刻 | `0` |
| `mtf3In3AlertTesterEvaluationStartTime` | 連続評価開始（0=Tester開始） | `0` |
| `mtf3In3AlertTesterSaveStartTime` | DB保存開始時刻 | `0` |
| `mtf3In3AlertTesterExpectedLastH1BarTime` | 収集最終H1バー時刻 | `0` |
| `mtf3In3AlertTesterMinimumWarmUpH1Bars` | 保存前WarmUp（H1本数） | `5000` |
| `mtf3In3AlertTesterOneMinuteOhlcConfirmed` | 1 minute OHLC設定確認 | `false` |
| `alertH1DisplayWaveEntryLimitEnabled` | H1表示波の回数制限 | `false` |

収集期間はサーバー時刻で指定する。期間および回数制限の入力はDB有効時に使用する。既定値のままDB保存だけを有効にしても、必須期間・モデル確認が不足するため開始できない。

## 5. 一覧モードと抽出条件

「方向」は原則として各`Elliot.isBuy`の分析方向を指す。最新Waveの上昇・下降方向やEMA方向とは別の値である。以下の「＝」は分析方向の一致を表す。

| 値・モード | 基準足 | 抽出条件 | 実効ソート |
|---|---|---|---|
| 0：CHART | チャート足 | H1以外はD1から基準足まで全方向一致。H1は5.3を適用 | 入力値。ただしH1は専用順 |
| 1：D1固定 | D1 | 選択したD1条件 AND D1 EMA200同方向 | D1専用順 |
| 2：H4固定 | H4 | 選択したD1条件 AND D1＝H4 | ENTRY優先度 |
| 3：H1＋M5独立2段 | 上段H1／下段M5 | 上段は5.3、下段はD1＝H4＝H1＝M15＝M5 | 上段H1専用順／下段ENTRY優先度 |

H4固定には、D1固定のD1 EMA200必須条件を追加しない。CHARTのD1もD1固定とは異なり、W1との一致やD1 EMA200一致を必須にしない。

### 5.1 D1条件

| 値 | 条件名 | 条件 |
|---|---|---|
| 0 | W1＝D1 | W1＝D1 |
| 1 | MN1＝W1＝D1 | MN1＝W1＝D1 |
| 2 | W1＝D1 ＋（MN1 または W1 EMA200） | W1＝D1 AND（MN1＝D1 OR W1 EMA200がD1方向） |

### 5.2 D1 EMA200必須条件

D1固定および全H1一覧では、D1の分析方向とD1 EMA200方向の一致を必須とする。BUYならEMAがBUY、SELLならEMAがSELLであることを要求する。NONE・逆方向・BUY/SELL競合・ラベルや時間足の不整合は通過させない。

この条件はEMA200との距離条件ではない。D1-S/A/Bの表示ランクとも別に判定するため、D1-SでもD1 EMA200が逆方向なら表示対象外となる。

### 5.3 H1条件

すべてのH1モードに次を適用する。

```text
H1表示対象 = 選択したD1条件
           AND D1分析方向とD1 EMA200方向の一致
           AND 下表のH1条件
```

| 値 | 条件名 | 追加条件 |
|---|---|---|
| 0 | D1＝H4＝H1 | D1＝H4＝H1 |
| 1 | MN1～H1すべて一致 | MN1＝W1＝D1＝H4＝H1 |
| 2 | W1～H1一致 ＋（MN1 または W1 EMA200） | W1＝D1＝H4＝H1 AND（MN1＝H1 OR W1 EMA200がH1方向） |
| 3 | D1条件 ＋（H4 または H1） | D1＝H4 OR D1＝H1 |

初期値ではW1・D1・H4・H1の一致と、D1 EMA200同方向が必要となる。値3はD1基準の方向へ分類し、H1が逆方向でもH4がD1と一致すれば表示可能。ENTRY判定はD1とH1が一致する場合H1、そうでなければH4を使用する。

### 5.4 H1＋M5独立表示

上段は`H1 ENVIRONMENT`、下段は`M5 INDEPENDENT`。下段は上段の抽出結果で絞り込まず、独自にD1～M5の一致を判定する。同一通貨が両段で同じBUY/SELL方向の対象となった場合、シンボル欄をBUYは青系、SELLは赤系の背景で強調する。

上段の描画高さに応じて下段を配置する。各描画器の最小パネル幅は900。両段のENTRY凡例および上段H1の次点候補パネルは非表示。

## 6. 画面表示

BUY・SELLを左右のパネルに分け、各方向の件数を表示する。基本色はBUYがAqua、SELLがHotPink。

| 項目 | 内容 |
|---|---|
| タイトル | 一覧基準足、対象・分析・エラー等の集計、時刻情報 |
| シンボル | 通貨名。独立2段では同方向重複を背景で強調 |
| ENTRY／D1条件 | 表示足とソート方式に応じた優先度またはD1-S/A/B等 |
| 時間足列 | MN1から基準足までの各足の波動、EMA方向、Fibonacci比率 |
| H1のEMA3 | H1方向に対するH1・H4・D1のEMA200一致の参考表示 |

波動は方向ラベルとElliottラベルを連結する。未確定Waveは先頭に`【未】`、補完ポイントは末尾に`★`を付ける。取得できない波動は`-`。

Fibonacciは元の波番号が1以下なら表示せず、偶数は`F`、奇数は`FE`を付けて小数1桁で表示する。不正な値は表示しない。時間足セルのツールチップには波動・ポイント・比率・値幅・バー数・時刻・価格等の詳細を表示する。

`EMA3 OK`は3足一致、`EMA3 NG`は不成立、`EMA3 ?`は分析結果不足を表す。これは一覧の追加フィルタではない。H1条件の値3でH1がD1と逆方向なら、表示対象でも`EMA3 NG`になり得る。

H1単独表示でH1条件が値2の場合、`NEXT H1 4/5`にあと1条件で方向一致する次点候補を表示する。次点候補にも共通D1条件とD1 EMA200条件を要求する。独立2段では次点候補を表示しない。

## 7. 並び替えと表示用優先度

### 7.1 ENTRY優先度

`Mtf3In3EntryPriorityDecision`が副作用なしで計算する表示用の順位である。

| 優先順 | 表示 | 条件 |
|---|---|---|
| 1 | READY | 対象波動が揃い、副条件9項目すべて成立 |
| 2 | NEAR | 対象波動が揃い、副条件が1項目だけ未達 |
| 3 | SETUP | 対象波動が揃い、副条件が2項目以上未達 |
| 4 | ALIGN | 対象波動が未完成 |
| 5 | ERROR | 判定に必要な分析結果が不足 |

対象波動は最新ポイントのElliottラベルが`1`または`3`。H1はH1だけ、H1以外は現在足と上位2足の計3足を確認する。同順位では波動一致数、副条件一致数の多い順とし、完全同順位では元の順序を維持する。

副条件9項目は次のとおり。

1. 現在足の最新Wave方向が分析方向と一致。
2. 現在足のポイントが補完ポイントでない。H1は成立扱い。
3. GMMA Trend CountがBUYで2以上、SELLで−2以下。
4. GMMA Cross CountがBUYで2以上、SELLで−2以下。
5. 現在足EMA200が分析方向と一致。
6. 上位2足目EMA200が分析方向またはNONE。H1は成立扱い。
7. 上位1足目EMA200が分析方向と一致。H1は成立扱い。
8. M5第3波のFEが有効な正数で、小数1桁に丸めて161.8%以下。それ以外は成立扱い。
9. Close[1]とEMA200[1]の絶対距離がH1で50 pips以下、それ以外で25 pips以下。

READYはAlert発生や発注の保証ではない。この表示用判定ではSpread・Signal Countなど実際のエントリー判定全体を評価しておらず、H1の上位EMA条件も上記のとおり成立扱いにしている。

### 7.2 D1条件ランク

| ランク | 条件 |
|---|---|
| D1-S | W1＝D1に加え、MN1とW1 EMA200の両方がD1方向 |
| D1-A | W1＝D1に加え、MN1またはW1 EMA200の片方がD1方向 |
| D1-B | W1＝D1だが、MN1・W1 EMA200はともにD1方向に不一致 |
| NG | W1とD1が不一致 |

D1専用ソートでは、評価済みを優先し、D1条件ランク、D1最新Wave、D1 EMA、W1最新Wave、W1 EMA、MN1最新Waveの順に方向一致ランクを比較する。その後ENTRY優先度で比較する。Waveは一致を優先、EMAは一致、NONE、逆方向の順。

### 7.3 H1専用ソート

評価済みを優先し、次の順に比較する。

1. D1条件ランク（S → A → B → NG）。
2. ENTRY判定足（H1直接一致 → H4代替）。
3. ENTRY優先度。
4. 波動一致数の降順。
5. 副条件一致数の降順。
6. D1最新Waveの方向一致ランク。
7. D1 EMAの方向一致ランク。

そのため、D1-AのREADYよりD1-SのNEARが上位になる場合がある。表示はD1条件ランクに加え、`H1 READY`や`H4 NEAR`等の判定足・状態を付記する。

### 7.4 M15専用ソート

M15表示時に使用する。評価済みを優先し、M15最新Wave、M15 EMA、H1最新Wave、H1 EMA、H4最新Wave、H4 EMA、D1 EMAの順にM15分析方向との一致ランクを比較する。同順位ではENTRY優先度を使用する。

## 8. 更新・再試行・終了処理

| 実行環境 | 更新基準足 | 呼び出し |
|---|---|---|
| 通常チャート | M5 | `OnCalculate`および2秒間隔の`OnTimer` |
| テスター・一覧基準足がM5より上位 | 一覧基準足 | `OnCalculate` |
| テスター・一覧基準足がM5以下 | M5 | `OnCalculate` |

更新判定はホストシンボルの更新基準足の`iTime(..., 0)`を使用する。初回および新規バーで全対象を分析し、同一バーで毎ティック全分析は行わない。H1＋M5独立表示ではM5基準で両段を更新する。

分析が未完了の場合は、通常チャートではタイマー、テスターでは後続`OnCalculate`で同一バー最大3回再試行する。新規バーで再試行回数をリセットする。履歴準備待ちは分析バッチの再試行とは別に処理する。多重実行は`executing`で抑止する。

初期化時に対象シンボル・履歴を準備し、分析ハンドル管理器・判定器・描画器を作成する。タイマー設定失敗はERRORログへ記録するが、その理由だけでは初期化失敗にしない。

終了時はコントローラーを削除し、タイマー、描画オブジェクト、ハンドル管理器、判定器およびAlertコントローラー等を解放する。

## 9. テスター制約とAlert DB収集

### 9.1 一覧のテスター制約

| モード | テスト対象チャート足の制約 |
|---|---|
| D1固定 | D1以下 |
| H4固定 | H4以下 |
| H1＋M5独立2段 | M5以下 |

上表に違反する設定は`INIT_PARAMETERS_INCORRECT`。D1固定、H4固定、独立2段、およびDB有効のH1ではテスター履歴準備チェックを有効にする。分析用の必要履歴本数はMN1が61本、W1以下が206本を基準とする。これはAlert保存前に必要な連続評価5000本とは別の条件である。

### 9.2 DB収集の開始条件

DB収集はCHARTモードのH1・Strategy Testerのみで使用できる。最適化では使用不可。全28通貨を解決でき、ホストもその対象通貨であることを要求する。

- DBファイル名が空でなく、Commonフォルダ使用が`true`。
- Tester開始時刻が正の時刻。
- 連続評価開始がTester開始以降、DB保存開始より前。入力0はTester開始へ置換。
- DB保存開始がTester開始より後。
- 評価開始から保存開始までの経過時間が、最低WarmUp本数×1時間以上。
- 最終H1バー時刻がDB保存開始以降。
- 最低WarmUp本数は1～100000。
- 4種類の時刻がH1開始時刻として妥当。
- テスターモデルを`1 minute OHLC`に設定し、確認入力を`true`にする。

確認入力はテスターモデルを切り替える機能ではない。実際のモデル設定はテスター側で行う。単なる経過時間に加え、保存開始前の実際の連続評価本数もチェックするため、週末等を含む期間では余裕が必要になる。

### 9.3 一覧とAlertの条件の違い

一覧用の`d1AlignmentMode`・`h1AlignmentMode`・ソート指定でAlert条件は変更しない。Alertは`ZigZagElliotConfig.applyH1EntryPolicy()`を通して共通の`Mtf3In3H1Policy`を適用する。

| 項目 | Alertの共通固定設定 |
|---|---|
| 方向一致 | W1＝D1＝H4＝H1 AND（MN1＝H1 OR W1 EMA200がH1方向） |
| EMA確認 | H1・H4・D1のEMA200がH1方向に一致 |
| W1追加確認 | `OBSERVE_ONLY`。追加制限をせず診断記録 |
| 分析開始足 | MN1 |

波動・Spread・Signal Count等は実際の戦略判定に従う。`alertH1DisplayWaveEntryLimitEnabled`はH1表示波ごとのエントリー回数制限を切り替える。Listでは通貨強弱計算・エントリーフィルタ・順位表示を無効にする。また、メール検証ファイルとMTF_3in3 Alert CSV出力を無効にする。

28通貨を共通Runとして収集し、Alert発生時の情報を保存する。全時刻・全非成立候補を記録するObservation収集とは用途が異なる。重大な収集エラーまたは収集完了時は`TesterStop()`で停止する。保存テーブル等は[Alertデータベース仕様書](../Database/ZigZagElliotAlertDatabase.md)を参照する。

## 10. エラーと表示対象外の扱い

| 状態 | 処理 |
|---|---|
| バッファ設定失敗、必要オブジェクト生成失敗等 | 初期化失敗 |
| 非対応時間足、適用対象の不正な方向条件値、DB設定不正 | パラメーターエラー |
| 更新基準足の時刻が0 | その呼び出しでは処理しない |
| 必要な分析結果の不足 | 未準備として扱い、表示から除外・再試行対象とする |
| 方向一致条件の不成立 | 正常な表示対象外 |
| 必須D1 EMA200のNONE・不一致 | 正常な表示対象外。分析エラーとして数えない |
| 一覧描画失敗 | ERRORログを記録。DB無効時は再試行対象にする |
| Alert収集の重大エラー | テスター停止 |

表示対象数が0でも、28通貨の分析が正常に完了していれば異常ではない。分析完了判定は対象数28、分析済み件数が対象数と一致、エラー数0を使用する。

## 11. 確認項目

以下は仕様変更時の確認観点であり、本書作成時に実機テストを実施した記録ではない。

| 観点 | 期待結果 |
|---|---|
| CHART・H1を初期値で起動 | W1・D1・H4・H1一致とD1 EMA一致を要求 |
| D1固定でD1 EMAが逆方向 | D1-Sでも表示対象外 |
| CHART・D1とD1固定の比較 | W1・EMA条件の適用範囲に差がある |
| H1条件3でD1＝H4、H1逆方向 | D1方向へ分類しH4 ENTRYを表示可能、EMA3はNG |
| H1＋M5で下段のみ条件成立 | M5行を独立表示。重複色は付かない |
| H1＋M5で同方向の両段条件成立 | 両段のシンボル背景を強調 |
| H1条件2の次点候補 | 共通D1条件を満たした4/5候補だけを単独表示に掲載 |
| 同じ更新バー内の通常呼び出し | 完了済み分析を繰り返さない |
| 未完了分析 | 同一バー最大3回再試行 |
| DB有効で期間未指定／Common無効／最適化 | 初期化を拒否 |
| DBの保存前評価不足／重大エラー | 収集を継続せずテスター停止 |

## 12. 実装参照

| ファイル | 主な責務・確認箇所 |
|---|---|
| [ZigZagElliotList.mq5](../../Indicators/ZigZagElliotList.mq5) | 入力、OnInitの実効設定、イベント転送 |
| [ZigZagElliotListController.mqh](../../Include/Mstng/Indicator/ZigZagElliot/ZigZagElliotListController.mqh) | initialize、execute、履歴準備、シンボル解決、destroy |
| [ElliotDirectionAlignmentDecision.mqh](../../Include/Mstng/Elliot/ElliotDirectionAlignmentDecision.mqh) | isReady、getAlignType、D1共通条件、H1次点候補 |
| [DrawAlignedElliotAllList.mqh](../../Include/Mstng/Draw/DrawAlignedElliotAllList.mqh) | 描画、件数集計、行抽出・ソート、EMA3、重複強調 |
| [Mtf3In3EntryPriorityDecision.mqh](../../Include/Mstng/ExpertAdvisor/Mtf3In3EntryPriorityDecision.mqh) | 表示用READY／NEAR等の判定 |
| [D1ElliotEmaSortDecision.mqh](../../Include/Mstng/Elliot/D1ElliotEmaSortDecision.mqh) | D1条件ランクとD1ソート |
| [H1D1EntrySortDecision.mqh](../../Include/Mstng/Elliot/H1D1EntrySortDecision.mqh) | H1のD1環境優先ソート |
| [M15ElliotEmaSortDecision.mqh](../../Include/Mstng/Elliot/M15ElliotEmaSortDecision.mqh) | M15専用ソート |
| [Mtf3In3AlertAllController.mqh](../../Include/Mstng/Indicator/ZigZagElliot/Mtf3In3AlertAllController.mqh) | 全28通貨Alert収集、入力検証、評価期間管理 |
| [Mtf3In3H1Policy.mqh](../../Include/Mstng/ExpertAdvisor/Mtf3In3H1Policy.mqh) | H1 Alert／エントリーの共通固定設定 |
| [ZigZagElliot関連仕様](ZigZagElliot.md) | 共通設定および過去の変更説明 |

本書作成ではプログラムのメソッド・ロジックは変更していない。確認範囲はソースとの照合および文書の参照先確認とし、MetaEditorでの再コンパイル・チャート表示・テスター収集は実施していない。
