# MstngEa仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象EA | `Experts/MstngEa.mq5` |
| 対象バージョン | `1.06` |
| 対象プラットフォーム | MetaTrader 5 |
| 既定戦略 | `STRATEGY_TYPE_MTF_3IN3` |
| 最終更新日 | 2026-08-22 |

本書は、現行コードを正本として、`MstngEa`の初期化、判定タイミング、エントリー、発注、決済、利益戻し状態の永続化、画面表示およびログ出力をまとめた仕様書です。

特に断りがない限り、「H1エントリー」はH1チャートへEAを設定し、既定の`MTF_3in3`戦略を選択した場合を表します。

## 2. 概要

`MstngEa`は、EAを設定したチャートのシンボルと時間足を対象に、複数時間足のElliott、Stochastic、GMMAおよびEMA200分析から売買を実行します。

主な特徴は次のとおりです。

- チャートの新規バーごとに戦略の決済判定とエントリー判定を行う
- 既定の`LEGACY`モードでは毎ティックで建値移動と利益戻し決済を管理する
- H1・`MTF_3in3`では、任意で確定ZigZagポイントだけを使用するSLトレイル専用モードを選択できる
- 固定ロットの成行注文を使用する
- 初期ストップロスをElliottのロスカット基準から設定する
- 同一シンボル、同一Magic Numberのポジションを1件管理する
- 任意で通貨強弱DBをエントリーフィルタとして使用する
- ライブ運用では利益戻し決済の状態をCommonフォルダへ永続化する

`MTF_3in3`にはH1、M15、M5専用クラスがあり、M1は従来互換の共通クラスで動作します。それ以外の時間足でも初期化を拒否しませんが、M30は分析時間足レジストリに含まれず、H4以上は必要な上位2足を取得できない場合があります。本書で定義する運用対象はH1、M15、M5および従来互換のM1です。

## 3. 処理タイミング

### 3.1 初期化

`OnInit()`で次を初期化します。

- 現在のシンボルと時間足
- D1以下のOscillatorハンドルプール
- シグナル回数管理
- EA設定とMagic Number
- 戦略Adapter
- ポジション取得・発注サービス
- 運用ログ、取引CSV、決済専用CSV
- ステータス、シグナル、決済損益、Elliott情報の各表示
- 利益戻し状態と状態ファイルStore
- 任意の通貨強弱DB Provider
- パネル更新用ミリ秒タイマー

初期化直後の最初のティックは、現在バー時刻を新規バー検出器へ記録するだけで、新規バー分析を行いません。`LEGACY`モードでは、既存ポジションの建値移動と利益戻し管理を最初のティックから開始します。

### 3.2 毎ティック処理

毎ティックの処理順は次のとおりです。

1. 自EAポジションを再取得する
2. 待機中のH1 ZigZagトレイル候補があれば再試行する
3. 利益戻し状態を初回同期または復元する
4. 利益戻し状態を現在価格・損益で更新する
5. 建値移動を判定する
6. ポジションを再取得する
7. 利益戻し決済を判定する
8. 新規バーでなければ、ライブ時の通貨強弱DB待ちだけを再試行して終了する
9. 新規バーなら新規バー処理へ進む

利益戻し条件が成立して決済処理へ入った場合、決済受付後の確認待ちの場合、またはH1 ZigZagトレイル候補跨ぎによる成行決済を開始した場合、そのティックでは後続の新規バー処理を行いません。`ACTIVE`でも戻し条件が未成立なら、新規バー処理へ進みます。`ZIGZAG_TRAIL_ONLY`では建値移動と利益戻し決済を無効化します。

### 3.3 新規バー処理

新規バーでは次の順に処理します。

1. 現在時間足までの`ElliotAll`を分析する
2. H1・`MTF_3in3`の場合はW1確認専用スナップショットを取得する
3. 任意の通貨強弱実行情報を読み込む
4. 既存ポジションの戦略決済を判定する。`ZIGZAG_TRAIL_ONLY`では判定結果を決済に使用しない
5. 決済後のポジションを再取得する
6. `ZIGZAG_TRAIL_ONLY`では、保有中ならH1 ZigZagトレイル候補を判定する
7. ZigZag候補跨ぎによる成行決済を開始していなければエントリーを判定する
8. 注文後のポジションと利益戻し状態を更新する
9. 必要なら同一M5内の通貨強弱DB待ちを予約する
10. ステータスとElliott情報を更新する

`LEGACY`では、戦略決済後に完全なエントリー条件が成立していれば、同じ新規バーで反対方向を含む新規エントリーが成立する可能性があります。`ZIGZAG_TRAIL_ONLY`で候補跨ぎによる成行決済を開始したバーはエントリー判定を行わず、同じバーでは再エントリーしません。

### 3.4 タイマーと取引イベント

- `OnTimer()`はステータスパネルを再描画します。分析・発注は行いません。
- `OnTradeTransaction()`は`TradeExecutor`へ取引イベントを渡し、主にストップロス約定の記録と表示に使用します。

## 4. 入力パラメータ

実運用の既定値は`EaConfig`のコンストラクタではなく、`Experts/MstngEa.mq5`のinput値です。

| 入力値 | 既定値 | 内容 |
|---|---:|---|
| `InpStrategyType` | `STRATEGY_TYPE_MTF_3IN3` | 使用する戦略 |
| `InpLotSize` | `0.01` | 発注ロット。ブローカーの最小・最大・stepへ補正 |
| `InpPanelRefreshMilliseconds` | `1000` | ステータスパネル更新間隔（ms） |
| `InpUseProfitRetracementExit` | `true` | 利益戻し決済（画面表示：`TrailExit`）を使用 |
| `InpProfitRetracementStartR` | `1.5` | 利益戻し監視を開始する初期リスク倍率 |
| `InpProfitRetracementRate` | `0.30` | 最大含み益から許容する戻し率 |
| `InpUseBreakEven` | `true` | 建値移動（画面表示：`BreakEven`）を使用 |
| `InpBreakEvenTriggerR` | `1.0` | 建値移動の発動R倍率 |
| `InpBreakEvenPlusPips` | `1.0` | 建値から利益側へ移動するpips |
| `InpUseCurrencyStrength` | `false` | 通貨強弱DBフィルタを使用 |
| `InpCurrencyStrengthDatabaseProfile` | `AUTO` | 実行環境に応じてLIVE／TESTERを選択する参照Profile |
| `InpCurrencyStrengthDatabaseFileName` | `mstng-currency-strength.sqlite` | 年付与前のDBファイル名 |
| `InpCurrencyStrengthDatabaseSplitByYear` | `true` | 年別DBを使用 |
| `InpCurrencyStrengthDatabaseUseCommonFolder` | `true` | CommonフォルダのDBを使用 |
| `InpCurrencyStrengthRefreshSeconds` | `15` | 同一M5データの再取得間隔（秒） |
| `InpCurrencyStrengthVoteWeightMode` | `WEIGHTED` | 参照する票ウェイト方式 |
| `InpMtf3In3AlertCsvEnabled` | `false` | `MTF_3in3`アラート検証CSVを出力 |
| `InpH1DisplayWaveEntryLimitEnabled` | `false` | M5で同一H1表示波への重複エントリーを制限 |
| `InpH1PositionManagementMode` | `H1_POSITION_MANAGEMENT_LEGACY` | H1ポジションの決済管理モード |
| `InpH1ZigZagTrailBufferPips` | `5.0` | H1 ZigZag基準点からSLを離すpips |
| `InpH1W1ConfirmationMode` | `OBSERVE_ONLY` | H1エントリーのW1確認モード |
| `InpH1Ema200ConfirmationMode` | `H1_AND_H4_REQUIRED` | H1エントリーのEMA200方向確認モード |

初期化時に明示検証するのは、H1ポジション管理モード、W1確認モード、H1 EMA200確認モード、通貨強弱DBファイル名、通貨強弱更新秒、票ウェイト方式、およびTesterでのCommonフォルダ使用です。`ZIGZAG_TRAIL_ONLY`はH1・`STRATEGY_TYPE_MTF_3IN3`だけを許可し、バッファーが0未満の場合も初期化を拒否します。`InpStrategyType`の無効値は明示検証されず、戦略Factoryが`NULL`を返した後に実行時の必須依存チェックで処理を停止します。

ロット、パネル更新間隔、R倍率、戻し率には専用の入力範囲検証がありません。例えば0以下のロットは入力時に拒否されず、発注時のロット正規化で最小ロットになる可能性があります。

## 5. 戦略

### 5.1 戦略一覧

| input値 | 表示名 | 主な判定 |
|---|---|---|
| `STRATEGY_TYPE_MTF_3IN3` | `MTF_3in3` | 複数時間足の方向、波、GMMA、EMA200を組み合わせる既定戦略 |
| `STRATEGY_TYPE_MTF_3IN3_BUY_SELL_D1` | `MTF_3in3_BuySellD1` | D1までの方向一致、D1のStochastic中立、現在足GMMAを使用 |
| `STRATEGY_TYPE_MTF_BUY_SELL_COUNT3` | `MTF_BuySellCount3` | 現在足からH4までのOscillatorがすべて`+3`または`-3`、現在足推進波、GMMAを使用 |

既定の`LEGACY`では、全戦略が共通してスプレッド上限、同一シグナル回数、初期SL、ポジション管理および反対GMMAによる戦略決済を使用します。H1・`MTF_3in3`で`ZIGZAG_TRAIL_ONLY`を選択した場合だけ、決済管理を11.5の仕様へ切り替えます。

### 5.2 `MTF_3in3_BuySellD1`

候補判定では次をすべて要求します。

- スプレッドが3 pips以下
- 現在足からD1までのBUY/SELL方向が一致
- D1の短・中・長Stochastic countについて、値がちょうど`+1`の系列が2本、またはちょうど`-1`の系列が2本という非中立状態ではない
- 現在足のGMMAクロス継続が、BUYなら`+2`以上、SELLなら`-2`以下

エントリー確定時は、上位1足と現在足の最新Elliottラベルが`1`、`3`、`5`のいずれかであることを要求します。

### 5.3 `MTF_BuySellCount3`

候補判定では次をすべて要求します。

- スプレッドが3 pips以下
- 現在足からH4までの各足で、Stochastic 3本がすべてBUYならOscillator countが`+3`、すべてSELLなら`-3`
- 現在足が推進波
- 現在足のGMMAクロス継続が、BUYなら`+2`以上、SELLなら`-2`以下

エントリー確定時は、現在足の最新Elliottラベルが`1`、`3`、`5`のいずれかであることを要求します。

## 6. `MTF_3in3`の共通方向

各時間足のBUY/SELL方向は、短期・中期・長期Stochasticの3本で決定します。

- 各Stochasticは`Main >= Signal`ならプラス方向
- 3本中2本以上がプラスならBUY
- それ以外はSELL
- GMMAはこのBUY/SELL多数決には含めない
- Stochasticの参照shiftは0で、形成中バーを含む

`MTF_3in3`の候補判定では、現在足のこの方向を基準に上位足、Wave、GMMAおよびEMA200を照合します。

## 7. H1・`MTF_3in3`エントリー仕様

H1の新規バーで、自EAポジションがない場合に次をすべて満たすとエントリー候補になります。

1. 全時間足分析に成功する
2. 通貨強弱フィルタが有効なら、対象M5データを取得でき、方向が一致する
3. スプレッドが3 pips以下
4. H1のBUY/SELL方向とH1最新Wave方向が一致する
5. H1、H4、D1のBUY/SELL方向が一致する
6. H1最新Elliottラベルが`1`、`3`、`5`のいずれか
7. H1 GMMA trend countがBUYなら`+2`以上、SELLなら`-2`以下
8. H1 GMMA cross countがBUYなら`+2`以上、SELLなら`-2`以下
9. H1 EMA200判定がエントリー方向と一致する
10. `Close[1]`とH1 EMA200[1]の絶対距離が50.0 pips以下
11. 選択したW1確認モードのゲートを通過する
12. 同一シグナルの対象回数と一致する。通常は初回の1回だけ

同一シグナルは、H1の2番目に新しいZigZagポイント時刻と売買方向で識別します。候補成立時に回数を加算するため、ブローカーが注文を拒否しても同一シグナルを自動再発注しません。この回数とM5のH1表示波使用済み情報はメモリ内だけで、EA再起動後には引き継ぎません。

### 7.1 H1 EMA200判定

BUYは次の3条件をすべて満たす場合です。

- `Close[1] > EMA200[1]`
- `EMA200[1] - EMA200[4] > 0`
- 直近4区間のEMA200比較で上昇が優勢し、trend countが正

SELLは上下・符号を反転した3条件です。いずれにも該当しない場合は`NONE`です。

EMA200方向確認モードは次のとおりです。

| モード | エントリーゲート |
|---|---|
| `H1_ONLY` | H1 EMA200方向だけをエントリー方向と照合する |
| `H1_AND_H4_REQUIRED` | H1とH4のEMA200方向が両方ともエントリー方向と一致することを要求する |

実運用の既定値は`H1_AND_H4_REQUIRED`です。D1 EMA200方向は使用しません。

方向確認モードとは独立して、`abs(Close[1] - H1 EMA200[1]) <= 50.0 pips`を要求します。50.0 pipsちょうどは通過し、超過時は`EMA200_DISTANCE_REJECTED`になります。この距離条件は両方の方向確認モードに適用し、H4のEMA200距離は判定しません。

### 7.2 H1で条件に使用しない表示値

次は表示・診断には使用しますが、H1エントリーの可否を直接制限しません。

- H1最新ZigZagポイントの確定・未確定
- H1構造ランク`S`、`A`、`B`、`C`、`EXCEPTION`
- 構造表示の`LATE`、`DIR`
- D1 EMA200方向
- H4のCloseとEMA200の距離

構造ランクの正常構造判定はH1第1波・第3波を前提としているため、第5波エントリーは表示上`EXCEPTION`になる場合があります。構造表示が`EXCEPTION`でも、上記の実エントリー条件を満たせばエントリーできます。

## 8. H1のW1確認

### 8.1 確認対象

W1確認は、D1以下の親子Elliott解析へW1を混入させず、W1のOscillatorだけを独立して更新します。

- W1方向：形成中W1バーの短・中・長Stochastic 3本の多数決
- W1 EMA200：確定足の終値位置、EMA200傾き、上昇・下降優勢の複合判定

W1方向はElliott Waveの上昇・下降方向ではありません。

### 8.2 モード

| モード | エントリーゲート | 診断結果`isPassed` |
|---|---|---|
| `OFF` | W1確認を行わず通過 | `true` |
| `OBSERVE_ONLY` | 常に通過 | OR条件の結果を記録 |
| `DIRECTION_OR_EMA200` | W1方向またはW1 EMA200方向のどちらか一致 | OR条件 |
| `DIRECTION_AND_EMA200` | W1方向とW1 EMA200方向の両方が一致 | AND条件 |

既定の`OBSERVE_ONLY`は記録専用であり、W1不一致、取得不能、不正値でもH1エントリーを制限しません。

強制モードではW1取得不能または不正値をfail-closedで拒否します。W1確認は同一シグナル回数を加算する前に実行するため、不一致の判定だけで初回シグナル回数を消費しません。

### 8.3 診断状態

| 状態 | 意味 |
|---|---|
| `STRONG` | W1方向とW1 EMA200が両方一致 |
| `DIRECTION_ONLY` | W1方向が一致し、W1 EMA200が`NONE` |
| `EMA_CONFLICT` | W1方向が一致し、W1 EMA200が反対 |
| `EMA_ONLY` | W1方向が反対で、W1 EMA200だけ一致 |
| `REJECT_NONE` | W1方向が反対で、W1 EMA200が`NONE` |
| `REJECT` | W1方向とW1 EMA200がともに不一致 |
| `UNAVAILABLE` | W1スナップショットを取得できない |
| `INVALID` | W1方向またはEMA200フラグが不整合 |
| `OFF` | W1確認を無効化 |
| `NOT_APPLICABLE` | H1以外など未適用 |

保存列とViewer表示の詳細は[ZigZagElliotアラートデータベース仕様書](../Database/ZigZagElliotAlertDatabase.md)を参照してください。

## 9. M15・M5の`MTF_3in3`差分

| 項目 | M15 | M5 |
|---|---|---|
| 対象波 | H4、H1、M15が`1`または`3` | H1、M15、M5が`1`または`3` |
| ZigZag確定 | 現在足の確定を要求 | 現在足の確定を要求 |
| EMA200 | 上位2足・上位1足・現在足の共通条件 | 上位2足・上位1足・現在足の共通条件 |
| EMA200距離 | 25 pips以内 | 25 pips以内 |
| 追加条件 | なし | M5第3波のFEが161.8%以下 |
| 表示波重複制限 | なし | input有効時、同一H1表示波へ1回 |
| `isSendMail`判定値 | `false` | `false` |

H1のEMA200距離上限は50 pips、M15・M5は従来どおり25 pipsです。

共通EMA200条件では、上位2足はエントリー方向または`NONE`、上位1足と現在足はエントリー方向を要求します。

`InpH1DisplayWaveEntryLimitEnabled`は名称にH1を含みますが、現在の実装で重複制限するのはM5エントリーです。

## 10. 発注仕様

### 10.1 新規注文

- 成行注文
- 既定ロット`0.01`
- ロットは`SYMBOL_VOLUME_MIN`、`MAX`、`STEP`へ正規化
- 許容deviationは10 points固定
- brokerのfilling modeに合わせる
- 固定TPは設定しない
- 注文コメントには戦略名を使用

### 10.2 初期ストップロス

初期SLは、現在足の1つ前のZigZag基準点から損失側へ5 pipsの`lossCut.lc5`です。

- BUY：基準点から5 pips下
- SELL：基準点から5 pips上

正のSLが市場価格の反対側にない、またはbrokerの`SYMBOL_TRADE_STOPS_LEVEL`を満たさない場合は注文を拒否します。SL値が0以下の場合は、現行実装ではSLなしの注文を許可します。

### 10.3 Magic Numberとポジション範囲

Magic Numberは次を連結して生成します。

- EAコード`11`
- 基軸通貨コード
- 決済通貨コード
- 時間足コード
- 戦略コード

自EAポジションは「同一シンボルかつ同一Magic Number」で判定します。他Magicの手動・他EAポジションはMstngEaの保有判定に含めません。

ヘッジ口座で同じシンボル・Magic Numberのポジションが複数ある場合、最初に見つかった1件だけを管理します。この構成で複数ポジションを同時保有する運用は非対応です。

## 11. 決済・利益保護

### 11.1 優先順位

既定の`LEGACY`設定での優先順位は次のとおりです。

1. broker側の初期SLまたは移動後SL
2. 毎ティックの建値移動
3. 毎ティックの利益戻し決済
4. 新規バー時の戦略決済

EAは固定TP、時間切れ、金曜クローズ、EMA200反転、Elliott完了だけを理由とする決済を行いません。

### 11.2 建値移動

本項は`LEGACY`の仕様です。`ZIGZAG_TRAIL_ONLY`ではinput値にかかわらず無効化します。

初期リスクを`R = |建値 - 初期SL|`として判定します。

- BUYはBid、SELLはAskで到達を判定
- 既定では`1.0R`到達で発動
- BUYはSLを建値`+1 pip`へ移動
- SELLはSLを建値`-1 pip`へ移動
- すでに同等以上に保護されている場合は変更しない

利益戻し決済を併用するライブ運用では、初期状態を永続化できるまで建値移動を保留します。先にSLを建値へ移動して初期リスクを失うことを防ぐためです。Testerでは状態Storeが無効でも保存成功相当として扱い、メモリ状態の初期化後に建値移動を管理します。

### 11.3 利益戻し決済

本項は`LEGACY`の仕様です。`ZIGZAG_TRAIL_ONLY`ではinput値にかかわらず無効化します。

利益戻し決済は価格幅ではなく、`POSITION_PROFIT`の最大値に対する戻し率で判定します。

- 既定では価格が`1.5R`へ到達すると監視を有効化
- 有効化後も最大含み益を更新
- `最大含み益 - 現在含み益 >= 最大含み益 × 30%`で全量成行決済を要求
- 決済理由は`PROFIT_RETRACEMENT`
- 部分利確を能動的には行わない

brokerが決済を受け付けても同一`POSITION_IDENTIFIER`が残っている場合は状態を削除せず、1秒後以降に決済確認・再試行を行います。部分約定や外部部分決済で数量が減った場合は、最大含み益を残存数量比で補正します。

### 11.4 戦略決済

新規バー時に、現在足のGMMAクロス継続が保有方向と反対へ2段階以上進んだ場合に全量成行決済を要求します。

- BUY保有：GMMA cross countが`-2`以下
- SELL保有：GMMA cross countが`+2`以上
- GMMA参照shiftは0で、形成中の新規バーを含む

H1では、W1確認、EMA200、Elliottラベル、D1・H4方向、通貨強弱を決済時に再判定しません。決済CSVのreasonは戦略名で、既定戦略では`MTF_3in3`です。

`ZIGZAG_TRAIL_ONLY`では、反対GMMAを含む戦略決済の判定結果を成行決済に使用しません。

### 11.5 H1 ZigZagトレイル専用モード

`InpH1PositionManagementMode=H1_POSITION_MANAGEMENT_ZIGZAG_TRAIL_ONLY`は、H1チャートかつ`STRATEGY_TYPE_MTF_3IN3`だけで使用できます。他の時間足または戦略で選択すると初期化を拒否します。既定の`H1_POSITION_MANAGEMENT_LEGACY`および他の時間足・戦略の動作は変更しません。

このモードでは、エントリー時の現行初期SLを維持し、建値移動、利益戻し決済および反対GMMAによる成行決済を無効化します。その後は、新しいH1バーごとに次の条件をすべて満たす場合だけSL候補を作成します。

- 最新点と1つ前の点が取得でき、価格と時刻が有効
- 両ポイントが`isAddedPoint=false`
- 両ポイントが確定H1上にあり、`barIndex>=1`
- 1つ前の点が最新点より古く、ポジションのエントリー時刻より後
- BUYは「1つ前が谷、最新が山」、SELLは「1つ前が山、最新が谷」
- 候補SLが現在SLより最小価格刻み1tick以上利益側

最新点は1つ前のポイントが確定したことの確認にだけ使い、実際のSL基準には1つ前のポイントを使用します。既定バッファーは5 pipsです。

```text
BUY  : 1つ前の谷 - 5 pips
SELL : 1つ前の山 + 5 pips
```

候補SLはBUYでは下方向、SELLでは上方向へbrokerの最小価格刻みにそろえます。一度登録したSL候補は利益側にだけ更新し、損失側へ戻しません。

候補が`SYMBOL_TRADE_STOPS_LEVEL`と`SYMBOL_TRADE_FREEZE_LEVEL`の大きい方に1tickを加えた距離を満たさない場合、候補をpendingとして保持し、毎ティック、最短1秒間隔で再試行します。SL変更要求が失敗した場合も同様に再試行します。SLをbrokerへ設定する前に現在価格が候補を跨いだ場合は、reason=`H1_ZIGZAG_TRAIL_CROSSED`で全量成行決済を要求します。この成行決済を開始したH1バーではエントリー判定をスキップするため、同じバーで再エントリーしません。

## 12. 利益戻し状態の永続化

本章は`LEGACY`で利益戻し決済を有効にした場合の仕様です。`ZIGZAG_TRAIL_ONLY`では利益戻し状態を使用しません。

### 12.1 有効範囲

永続化はライブ運用で有効です。Strategy Testerでは無効化し、メモリ上だけで利益戻しと建値移動を管理します。

保存先はCommonフォルダです。

```text
MstngEa\Trades\State\ProfitRetracement\
  MstngEa_<server>_<login>_<symbol>_<timeframe>_<magic>_profitRetracementV1.state
```

ファイルはアカウントサーバ、ログイン、シンボル、時間足、Magic Numberごとに分離します。スキーマバージョンは`1`です。

### 12.2 保存内容

| 項目 | 用途 |
|---|---|
| `position_identifier` | ポジションの安定識別子 |
| `position_ticket` | 現在チケットの診断・更新 |
| `open_time_msc` | ポジション開始時刻 |
| `is_buy` | 売買方向 |
| `open_price` | 建値 |
| `initial_stop_loss` | 初期SL |
| `position_volume` | 最終確認数量 |
| `best_price` | BUYの最高BidまたはSELLの最安Ask |
| `max_floating_profit` | 最大含み益 |
| `initial_risk_distance` | 初期Rの価格幅 |
| `initial_risk_available` | 初期Rを利用できるか |
| `activated` | 利益戻し監視開始済みか |
| `configured_start_r` | 状態保存時の開始R |
| `configured_rate` | 状態保存時の戻し率 |

ファイルにはaccount、server、symbol、timeframe、magicおよび更新サーバ時刻も保存し、復元時にスコープと形式を検証します。

### 12.3 書き込み方式

- UTF-16の一時ファイルへ全量を書き込む
- `FileFlush()`後に書込バイト数を確認する
- 一時ファイルを確定ファイルへ置換する
- 最大利益だけの高頻度更新は通常1秒以内の連続書込を抑制する
- 初期化、ticket・数量・有効化状態の変更、設定変更、EA終了時は強制保存する

### 12.4 復元と整合

復元状態は次を満たす場合だけ現在ポジションへ適用します。

- `POSITION_IDENTIFIER`が一致
- BUY/SELL方向が一致
- 建値差が2 points以内
- ファイルのschema、スコープ、数値、真偽値、初期リスクが有効

ticketだけが変わった場合は同じ状態を継続します。数量が減った場合は最大含み益を数量比で縮小し、数量が増えた場合は別状態として初期化します。保存時と現在の開始Rが異なる場合は、保存済み最良価格で`activated`を再判定します。

通常の決済処理では、ポジション消滅を確認してからメモリ状態、確定ファイル、一時ファイルを削除します。利益戻し機能をOFFにした場合は保有中でも状態を削除し、復元ファイルが現在ポジションと一致しない場合は旧ファイルを削除して現在ポジションの状態を再初期化します。EA終了時は状態を削除せず、最終状態を強制保存します。

### 12.5 エラー時の動作

- 既存ファイルの一時的な読込失敗時は、そのファイルを現在SLの値で上書きしない
- 同期できるまで建値移動と利益戻し決済を保留する
- 戦略の新規バー処理とGMMA決済は継続する
- 初期状態を一度も保存・復元できていない間は建値移動を保留する。初期状態がすでに永続化済みなら、後続の保存失敗後も建値移動は動作し得る
- 初回同期後の保存失敗では、メモリ内の初期Rが有効なら利益戻し決済自体は継続し得る
- 状態ファイルがなく、SLなし、またはSLが正しい損失側にない場合（BUYは`SL < 建値`、SELLは`SL > 建値`を満たさない場合）は、初期Rを推測せず`UNAVAILABLE`にする
- 保存・復元エラーはパネルの`Error`と運用ログへ出力する

パネルの`TrailExit`状態は主に次を表示します。

| 表示 | 意味 |
|---|---|
| `OFF` | 利益戻し決済を無効化 |
| `READY` | 初期Rを保持し、開始R待ち |
| `ACTIVE` | 開始R到達後、戻しを監視中 |
| `PERSIST ERROR` | 初期状態を保存できていない |
| `UNAVAILABLE` | 初期Rを復元できない |

### 12.6 永続化の限界

- EAまたはターミナル停止中に到達した最大価格・最大含み益は観測できない
- FILE_COMMONの同一状態ファイルに対する複数EAインスタンスの同時書込は想定しない
- 状態ファイルは利益戻し管理用であり、取引履歴DBではない

状態Storeの単体検証用Scriptは[ProfitRetracementStateStoreSmokeTest.mq5](../../Scripts/Mstng/ExpertAdvisor/ProfitRetracementStateStoreSmokeTest.mq5)です。

## 13. 通貨強弱フィルタ

通貨強弱フィルタは既定で無効です。有効にすると、Elliott候補判定の前に次を要求します。

- 指定されたDB・Profile・票ウェイト方式のレコードを取得できる
- レコードの対象M5時刻が今回の判定対象M5時刻と完全一致する
- BUYは長中期と中短期の順位差がともに正
- SELLは長中期と中短期の順位差がともに負
- 同順位、方向混在、欠損、古い時刻、取得エラーは不通過

ライブでは、新規バーの分析時点で対象M5レコードがまだ保存されていない場合、同じチャートバー・同じM5内だけ再取得を試みます。Testerではこの保存待ち再試行を行いません。

通貨強弱DBのファイル分割、Profile、Run検索および計算方式は[通貨強弱データベース仕様書](../Database/CurrencyStrengthDatabase.md)を参照してください。

## 14. 表示・メール・ログ

### 14.1 チャート表示

ステータスパネルには次を表示します。

- 稼働状態、シンボル、時間足、戦略、ロット
- スプレッド、Magic Number、ポジション、SL、含み益
- JST、サーバ時刻
- `BreakEven`の設定と`READY`／`DONE`
- `TrailExit`の設定、状態、最大含み益、現在含み益
- 最終ActionとError

`ZIGZAG_TRAIL_ONLY`では、`BreakEven`へ`OFF / H1 ZIGZAG ONLY`を表示します。`TrailExit`は`ZIGZAG ONLY / <buffer>p`に続けて、未保有の`WAIT POSITION`、候補待ちの`MONITORING`、SL反映待ちの`PENDING`を表示します。

Elliott情報パネルには、戦略が保持する時間足別の方向、Oscillator、Stochastic、GMMAおよびElliottラベルを表示します。エントリー判定成立時は、発注前にチャートへシグナルテキストを描画します。注文が拒否された場合も描画は残ります。

### 14.2 メール

H1戦略のエントリー判定成立時には`isSendMail = true`、M5では成立時も`false`が設定されます。ただしMstngEaの戦略Adapterは内部戦略を描画・メール実行なしで生成し、MstngEa自身にも`Mail::sendMail()`呼び出しがありません。

したがって、現行MstngEaは実メールを送信しません。`isSendMail`は検証結果上の診断フラグです。

### 14.3 運用ログと取引CSV

すべてCommonフォルダへ保存します。

| 種別 | 相対パス |
|---|---|
| 運用ログ | `MstngEa\Logs\MstngEa_<symbol>_<timeframe>.log` |
| 取引CSV | `MstngEa\Trades\MstngEa_<symbol>_<timeframe>_<magic>.csv` |
| 決済専用CSV | `MstngEa\Trades\MstngEa_<symbol>_<timeframe>_<magic>_close_only.csv` |
| 保有中entry CSV | `MstngEa\Trades\State\MstngEa_<symbol>_<timeframe>_<magic>_entryCsvText.txt` |

取引CSVと決済専用CSVの列は次のとおりです。

```text
jst_time,server_time,symbol,timeframe,magic,strategy,action,side,
volume,price,position_ticket,deal_ticket,profit,reason,entry_csv_text
```

`profit`はEA成行決済では発注直前の`POSITION_PROFIT`です。broker約定後の手数料、swap、feeを含む確定net損益とは限りません。

### 14.4 `MTF_3in3`検証CSV

`InpMtf3In3AlertCsvEnabled = true`の場合、`isAlert = true`の候補を80列の検証CSVへ保存します。V4でH1方向一致診断8列を追加しています。

```text
Logs\Mtf3In3AlertValidation\MTF3IN3_ALERT_V4\<date>_<symbol>_<timeframe>.csv
```

Strategy Testerの最適化中は複数Agentの同時書込を避けるため出力しません。

## 15. Strategy Testerとの差異

| 項目 | ライブ | Strategy Tester |
|---|---|---|
| 利益戻し状態ファイル | Commonへ保存・復元 | 無効。メモリ内のみ |
| 通貨強弱DB待ち再試行 | 同一M5内で実施 | 実施しない |
| 通貨強弱DBフォルダ | inputに従う | 有効時はCommon必須 |
| `MTF_3in3`検証CSV | input有効時に出力 | 単独runでは出力、最適化では省略 |
| 建値移動・利益戻し | 毎ティック | Testerが生成したティックごと |

建値移動と利益戻し決済はティック依存です。「始値のみ」などティックの少ないモードでは、ライブまたは「実ティックに基づく全ティック」と結果が変わる可能性があります。

## 16. 運用上の注意

- EA装着直後は次の新規バーまでエントリー・戦略決済を行わない
- 同一シグナルは通常1回だけ評価され、注文拒否後の自動再発注はない
- 同一シグナル回数とM5表示波の重複情報は再起動でリセットされる
- 固定TPはないため、EA停止中に機能する利益保護は最後にbrokerへ設定済みのSLだけ
- H1 ZigZagトレイルのpending候補はメモリ内だけに保持する。EAを再起動すると未反映候補を失い、既にbrokerへ設定済みのSLは残るが、失った候補は次の新規H1バーまで再評価されない
- H1 ZigZagトレイルで設定したSLがbroker側で約定した場合、取引CSVと決済専用CSVのreasonは`H1_ZIGZAG_TRAIL`ではなく`STOP_LOSS`になる
- 利益戻し決済はEA稼働中の観測値に依存する
- `LEGACY`のGMMA戦略決済はshift 0のため、新規バーの形成中値を含む
- 入力R倍率、戻し率、ロットには十分な範囲検証がない
- 同一シンボル・Magic Numberの複数ポジションは管理しない
- ネッティング口座で同一シンボルに他Magicの手動・他EAポジションがある場合、新規成行によって既存ポジションを増減・相殺・反転させる可能性がある。MstngEaは口座モードや他Magicポジションを発注前に拒否しない
- 発注結果の`DONE_PARTIAL`と`PLACED`も受付成功として扱う。利益戻し決済は残存ポジションを再確認するが、通常の戦略決済は同じpending管理を持たない
- 手動決済や他EAによる決済は、`DEAL_REASON_SL`以外では決済CSVとチャート損益表示の対象にならない
- Magic Numberの通貨コード対象外通貨はコード0となり、組み合わせによっては衝突する可能性がある
- JST表示はOANDAのサーバUTC+2／+3と夏時間規則を前提とする
- `TradeTimeInfo`の時刻情報は分析・ログに含まれるが、現行MstngEaには金曜やロールオーバーの強制決済条件がない

## 17. 実装参照

| 領域 | 実装 |
|---|---|
| EAエントリーポイント・input | [MstngEa.mq5](../../Experts/MstngEa.mq5) |
| ティック・新規バー・決済制御 | [EaController.mqh](../../Include/MstngEa/App/EaController.mqh) |
| 設定 | [EaConfig.mqh](../../Include/MstngEa/Config/EaConfig.mqh) |
| 戦略生成 | [StrategyFactory.mqh](../../Include/MstngEa/App/StrategyFactory.mqh) |
| 既定戦略Adapter | [ExpertAdvisorMtf3In3Adapter.mqh](../../Include/MstngEa/Strategy/ExpertAdvisorMtf3In3Adapter.mqh) |
| H1 `MTF_3in3` | [ExpertAdvisorMtf3In3H1.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3H1.mqh) |
| M15 `MTF_3in3` | [ExpertAdvisorMtf3In3M15.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3M15.mqh) |
| M5 `MTF_3in3` | [ExpertAdvisorMtf3In3M5.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3M5.mqh) |
| D1方向一致戦略 | [ExpertAdvisorMTF_3in3_BuySellD1.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMTF_3in3_BuySellD1.mqh) |
| Oscillator `±3`戦略 | [ExpertAdvisorMTF_BuySellCount3.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMTF_BuySellCount3.mqh) |
| W1確認判定 | [H1W1ConfirmationDecision.mqh](../../Include/Mstng/ExpertAdvisor/H1W1ConfirmationDecision.mqh) |
| H1ポジション管理モード | [H1PositionManagementMode.mqh](../../Include/MstngEa/Config/H1PositionManagementMode.mqh) |
| H1 ZigZagトレイル判定 | [H1ZigZagTrailDecision.mqh](../../Include/MstngEa/Strategy/H1ZigZagTrailDecision.mqh) |
| 共通エントリー・決済判定 | [AbstractExpertAdvisor.mqh](../../Include/Mstng/ExpertAdvisor/AbstractExpertAdvisor.mqh) |
| 発注 | [TradeExecutor.mqh](../../Include/MstngEa/Trade/TradeExecutor.mqh) |
| ポジション取得 | [PositionService.mqh](../../Include/MstngEa/Trade/PositionService.mqh) |
| 利益戻し状態 | [ProfitRetracementState.mqh](../../Include/MstngEa/Domain/ProfitRetracementState.mqh) |
| 利益戻し状態Store | [ProfitRetracementStateStore.mqh](../../Include/MstngEa/Persistence/ProfitRetracementStateStore.mqh) |
