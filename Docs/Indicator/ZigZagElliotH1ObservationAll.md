# ZigZagElliotH1ObservationAll仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象 | `Indicators/ZigZagElliotH1ObservationAll.mq5` |
| プログラムバージョン | `1.04` |
| 役割 | 全28通貨のH1新規足時点におけるElliott分析結果を時系列保存する |
| 基準時間足 | H1 |
| 保存時間足 | MN1、W1、D1、H4、H1 |
| 保存先 | MetaTrader 5組み込みSQLite |
| 観測タイミング | `BAR_OPEN_FIRST_SUCCESS` |
| 最終更新日 | 2026-08-29 |

本書は、`ZigZagElliotH1ObservationAll`の収集対象、実行ライフサイクル、H1境界の扱い、分析内容、FIFO、DB保存、状態パネルおよび障害時の動作を定義します。

DB全体のAlertテーブル、共通Runおよびデータ表現については、[ZigZagElliotアラートデータベース仕様書](../Database/ZigZagElliotAlertDatabase.md)も参照してください。

## 2. 目的と対象範囲

本インジケーターは、アラートが発生した時点だけではなく、H1新規足ごとの市場状態を継続的に記録するための収集専用プログラムです。

主な用途は次のとおりです。

- H1推移Viewerで28通貨を同じ時系列上に表示する
- MN1からH1までの分析方向、Elliott、Wave、Stochastic、GMMA、ATRおよびEMA200を比較する
- 分析Profile単位で過去状態を検証する
- エントリー成立前後の市場状態をAlert履歴とは独立して調査する
- 将来の判定ルールや予測モデルを、H1時点の逐次データから検証する

本インジケーターは次を行いません。

- 売買注文、決済またはポジション管理
- エントリー可否の判定やアラート送信
- 過去に欠損したH1 Snapshotのバックフィル
- 全ZigZagポイント履歴の保存
- MFE、MAE、SL、TPまたは損益結果の保存（収集インジケーター単体）

収集後のObservationから6／12／24／48H1のMFE、MAEおよび損益を計算する場合は、[ZigZagElliot H1推移 将来成績](../Analysis/ZigZagElliotH1StudyOutcome.md)の後処理Scriptを使用します。結果は参照元とは別の研究用DBへ保存します。

## 3. 全体構成

```text
ZigZagElliotH1ObservationAll.mq5
  ├─ OnTimer（LIVE）/ OnCalculate（TESTER）
  ├─ H1ElliotObservationAllController
  │    ├─ 28通貨のシンボル解決・履歴準備
  │    ├─ 通貨ごとのH1境界検出
  │    ├─ ElliotAllによるMN1→H1分析
  │    ├─ Observation Snapshot生成
  │    ├─ 中央FIFOへ固定
  │    └─ 単一DB接続・単一Runで直列保存
  └─ DrawH1ElliotObservationAllStatus
       └─ 全体状態と28通貨別状態をチャートへ表示

SQLite
  ├─ zigzag_elliot_alert_runs
  ├─ zigzag_elliot_observations
  └─ zigzag_elliot_observation_timeframes
```

| コンポーネント | 主な責務 |
|---|---|
| `ZigZagElliotH1ObservationAll.mq5` | 入力値、MT5イベント、状態パネルの生成と破棄 |
| `H1ElliotObservationAllController` | 28通貨の境界検出、分析、FIFO、DB再接続、状態集約 |
| `ZigZagElliotAnalysisProfile` | 分析パラメーターと固定時間足順序の正本 |
| `ZigZagElliotObservationSnapshotBuilder` | `ElliotAll`を親1行・時間足別5行へ変換 |
| `ZigZagElliotObservationPersistenceService` | 検証、トランザクション、重複制御、親子保存 |
| `DrawH1ElliotObservationAllStatus` | 収集状態の固定パネル表示 |

## 4. 入力パラメーター

| 入力 | 既定値 | 内容 |
|---|---:|---|
| `observationDatabaseFileName` | `mstng-zigzag-elliot-alert.sqlite` | 観測を書き込むSQLiteファイル名 |
| `observationDatabaseUseCommonFolder` | `true` | `Terminal\Common\Files`を使用する場合true |
| `observationTimerSeconds` | `2` | LIVEで28通貨のH1境界を確認する間隔秒 |
| `observationDatabaseRetrySeconds` | `15` | DB接続または保存失敗後の再試行間隔秒 |
| `observationTesterSaveStartTime` | `0` | TESTERでObservation保存を開始する取引サーバー時刻。`0`は従来動作 |
| `observationQueueCapacity` | `672` | 保存待ちSnapshot FIFOの最大件数 |
| `statusPanelVisible` | `true` | 状態パネルを表示する場合true |
| `statusPanelDetailVisible` | `true` | 状態パネルに28通貨の詳細を表示する場合true |
| `statusPanelCorner` | `CORNER_LEFT_UPPER` | パネルの配置基準角 |
| `statusPanelXDistance` | `12` | パネルのX方向距離 |
| `statusPanelYDistance` | `12` | パネルのY方向距離 |

### 4.1 入力値検証

初期化時に次を検証します。

| 条件 | 結果 |
|---|---|
| DBファイル名が空 | `INIT_PARAMETERS_INCORRECT` |
| Timer秒が1未満または60超 | `INIT_PARAMETERS_INCORRECT` |
| DB再試行秒が1未満または3600超 | `INIT_PARAMETERS_INCORRECT` |
| TESTER保存開始時刻が0未満 | `INIT_PARAMETERS_INCORRECT` |
| Queue容量が28未満 | `INIT_PARAMETERS_INCORRECT` |
| `MQL_OPTIMIZATION = true` | `INIT_PARAMETERS_INCORRECT` |
| TESTERの対象時間足がH1より上位 | `INIT_PARAMETERS_INCORRECT` |
| 28通貨のいずれかを解決できない | `INIT_FAILED` |
| 分析ハンドルを準備できない | `INIT_FAILED` |

`observationTesterSaveStartTime`はTESTERだけで動作へ反映します。LIVEでは有効な0以上の入力値を`0`として扱います。状態パネル関連の5入力は表示だけに影響し、DB Runの`input_text`と`input_hash`には含めません。

## 5. 対象28通貨

`SymbolNameInfoAll.setAll()`が定義する次の28通貨をすべて収集します。GMO取引対象かどうかは収集可否へ使用しません。

| グループ | 通貨ペア |
|---|---|
| JPY | USDJPY、EURJPY、GBPJPY、AUDJPY、NZDJPY、CADJPY、CHFJPY |
| USD | EURUSD、GBPUSD、AUDUSD、NZDUSD、USDCAD、USDCHF |
| EUR・GBP Cross | EURGBP、GBPAUD、GBPNZD、GBPCAD、GBPCHF |
| EUR Cross | EURAUD、EURNZD、EURCAD、EURCHF |
| AUD・NZD・CAD Cross | AUDNZD、AUDCAD、AUDCHF、NZDCAD、NZDCHF、CADCHF |

### 5.1 ブローカーシンボルの解決

各標準名は次の順でブローカーの実シンボルへ解決します。

1. `USDJPY`などの完全一致を優先する
2. 完全一致がなければ標準名を含む選択可能シンボルを走査する
3. `SYMBOL_CURRENCY_BASE`と`SYMBOL_CURRENCY_PROFIT`が標準名と一致する候補だけを残す
4. 接頭辞・接尾辞付き候補が複数ある場合は最短名を選ぶ

28通貨のうち1つでも解決できない場合、インジケーター全体を開始しません。

## 6. 初期化とイベント

### 6.1 初期化順序

`OnInit()`は次の順で準備します。

1. `DRAW_NONE`の非表示Bufferを登録する
2. TESTERの対象時間足を検証する
3. 全通貨Controllerを生成する
4. 入力値を検証する
5. 28通貨の実シンボル名を解決し、Market Watchへ選択する
6. MN1、W1、D1、H4、H1の履歴取得を要求する
7. 28通貨分のOscillatorハンドルプールを準備する
8. 起動単位のDB Run情報を構築する
9. LIVEではTimerを開始する
10. 1回目の収集処理を実行する
11. 状態パネルを生成する

DB接続やRun保存の一時的な失敗だけでは初期化を失敗させません。Controllerは稼働を継続し、設定した再試行間隔でDBを再準備します。LIVEおよび`observationTesterSaveStartTime = 0`のTESTERでは、最初のDB接続を初期化直後ではなく`observationDatabaseRetrySeconds`経過後に試行します。それまでに生成できたSnapshotはFIFOへ保持します。

`observationTesterSaveStartTime > 0`のTESTERでは、全28通貨の保存ゲートが開くまでDB接続、Run保存およびFIFO保存を開始しません。ゲートが開いた実行でDB接続を直ちに試行します。

### 6.2 LIVEとTESTERの違い

| 項目 | LIVE | TESTER |
|---|---|---|
| 実行イベント | `OnTimer` | `OnCalculate` |
| 境界確認頻度 | `observationTimerSeconds` | 価格更新ごと |
| Timer登録 | あり | なし |
| 起動直後の現在H1 | baselineとして設定し保存しない | 保存開始時刻が`0`なら従来どおり通貨別の初回成功時に保存する |
| 保存開始時刻が0より大きい場合 | 使用しない | 保存開始前の事前分析と、全28通貨の保存ゲートを使用する |
| `source_mode` | `LIVE` | `TESTER` |
| 最適化 | 対象外 | 使用不可 |

LIVEでは、インジケーターを有効にした時点の進行中H1をbaselineにします。最初の保存対象は、その次に検出したH1新規足です。

`observationTesterSaveStartTime = 0`のTESTERでは、各通貨についてH1境界ごとに履歴準備を確認します。準備できたH1を分析待ちに設定し、その場で分析に成功した場合に最初のSnapshotとして保存します。この設定は追加の保存ゲートを使用せず、従来のTESTER初回処理を維持します。

`observationTesterSaveStartTime > 0`の場合は、入力時刻より前を事前分析期間として利用します。保存開始候補H1では全28通貨が同じH1について実分析に成功した場合だけ保存ゲートを開き、その実行内の2回目の全通貨処理で同じH1をSnapshot化します。詳しいフローと再試行制約は[7. H1観測フロー](#7-h1観測フロー)および[19. 既知の制約](#19-既知の制約)を参照してください。

保存開始判定は、各通貨の`iTime(symbol, PERIOD_H1, 0)`が返すH1開始の取引サーバー時刻で行います。ローカル時刻またはJSTではありません。入力がH1境界と一致しない場合は、その時刻以上となる次のH1が最初の候補です。例えば`18:30`を指定すると`18:00`は対象外となり、`19:00`が最初の候補です。

### 6.3 終了処理

`OnDeinit()`では次を破棄します。

- Timer
- 状態パネルのチャートオブジェクト
- 保存待ちFIFO
- DB接続とPersistence Service
- 28通貨分の分析ハンドル
- シンボル一覧と通貨別状態

FIFOはメモリだけに存在します。終了時に未保存Snapshotをディスクへ退避しないため、DB障害中にインジケーターやTerminalを終了するとQueue内のデータは失われます。

## 7. H1観測フロー

### 7.1 通常フロー

```text
各通貨のiTime(H1, 0)を取得
  ↓
前回検出時刻より新しいか
  ├─ いいえ: WAIT、RETRYまたはDB保存待ちを継続
  └─ はい: 新しいH1をpendingへ設定
             ↓
          MN1→H1系列の同期と必要本数を確認
             ↓
          分析前のH1開始時刻を再確認
             ↓
          ElliotAllをMN1からH1まで分析
             ↓
          分析後のH1開始時刻を再確認
             ↓
          Snapshotを生成してFIFO末尾へ固定
             ↓
          FIFO先頭からSQLiteへ直列保存
```

`observationTesterSaveStartTime > 0`のTESTERでは、通常フローへ入る前に次の二段階事前分析を行います。

```text
第1段階: 保存開始時刻より前
  各通貨の系列準備を確認し、各H1で最大1回Elliottを実分析
  ├─ 失敗: 結果を保存せず、次のH1で再試行
  └─ 成功: 結果を保存せず、以後は保存開始時刻までH1時刻だけ追従
             ↓
第2段階: 保存開始時刻以上の候補H1
  同じH1について全28通貨を改めて各1回実分析
  ├─ 28通貨のいずれかが失敗: 全体ゲートを閉じたまま次のH1で再試行
  └─ 28/28成功: 全体ゲートを開く
                    ↓
                 同じ実行内の第2 passで同じH1をSnapshot化
                    ↓
                 以後は通常フロー
```

保存開始候補では、28通貨すべての現在H1が同じであり、そのH1が保存開始時刻以上で、全通貨がそのH1の事前分析に成功する必要があります。pass途中で準備できた一部通貨だけを先に保存しません。

この全体ゲートは収集開始時点をそろえるためのものです。ゲート後の28 Snapshotを単一トランザクションで一括保存する機能ではなく、Snapshot生成、FIFO追加およびDB保存は通常どおり通貨別に処理します。

### 7.2 履歴準備条件

各通貨について5時間足すべての系列同期を確認します。次の最低バー数は、通常分析とTESTER事前分析の両方で使用します。

| 時間足 | 最低バー数 |
|---|---:|
| MN1 | 61 |
| W1 | 206 |
| D1 | 206 |
| H4 | 206 |
| H1 | 206 |

最低バー数への到達は必要条件であり、それだけではTESTER事前分析成功になりません。系列同期、最低バー数および実際の`ElliotAll`分析成功をすべて確認します。`observationTesterSaveStartTime > 0`では、保存開始候補H1についてこの実分析が28通貨すべて成功した場合だけ全体ゲートを開きます。

本数には次の異なる役割があります。

| 本数 | 役割 |
|---:|---|
| 61 | MN1の分析開始に必要な最低バー数 |
| 206 | W1、D1、H4、H1の分析開始に必要な最低バー数 |
| 300 | 最上位足ZigZagの最大計算範囲、および上位足Waveを取得できない場合の分析範囲 |
| 500 | 初期の履歴取得で各系列へ要求するwarm-up本数 |

`300`は全時間足に一律要求する履歴ゲート本数ではありません。反対に、61本または206本を満たしても実分析が失敗した場合は準備完了になりません。`300`の分析設定は`analysis_input_hash`へ含まれますが、今回追加する保存開始時刻は運用入力の`input_hash`へ含まれます。

LIVEでpendingとなった観測は、履歴が不足または未同期の場合も同じH1内でTimerごとに再試行します。TESTERの初回処理および事前分析では挙動が異なるため、[19. 既知の制約](#19-既知の制約)を参照してください。

### 7.3 Snapshotの時点

1つのSnapshotは、対象H1バーの分析に最初に成功した時点を固定します。

TESTERの事前分析結果は準備確認だけに使用して破棄し、Snapshot、FIFOまたはDB行を生成しません。全体ゲートが開いた後の第2 passで成功した分析が、最初のSnapshotの取得時点になります。

- `anchor_bar_time`はH1バー開始のサーバー時刻
- `anchor_jst_time`は同時刻を`TimeJapanUtil`でJSTへ変換した値
- `capture_phase`は常に`BAR_OPEN_FIRST_SUCCESS`
- `created_at`は実際にSnapshotを生成した時刻
- 履歴準備や分析再試行により、`created_at`がH1開始時刻より遅れる場合がある
- Snapshot生成後に市場値が変化しても、Queue内の内容を再分析または更新しない

これにより、DB障害中でも分析成功時点の内容を維持したまま後から保存できます。

### 7.4 境界変化と欠損

LIVEでpendingとなった観測、およびTESTERで最初のSnapshotへ成功した後の観測は、同じH1内で履歴準備、Elliott分析またはSnapshot生成に失敗しても再試行します。

LIVEおよびTESTERで最初のSnapshotへ成功した後は、次のH1へ移るまでに成功しなかった前のpendingを`gapCount`へ加算し、新しいH1を分析対象にします。過去H1を現在値から再構築しません。

`observationTesterSaveStartTime = 0`のTESTERでは、最初のSnapshotへ成功する前だけ専用の初回準備分岐を通ります。履歴待ちまたは分析失敗となったH1を保存せず、`gapCount`にも加算しません。

`observationTesterSaveStartTime > 0`のTESTERでは、全体ゲートが開くまで検出時刻へ追従しますが、pending、SnapshotおよびFIFOを残さず、`gapCount`にも加算しません。保存開始時刻へ到達した後でも、同じH1の全28通貨事前分析がそろわずゲートが閉じている間は同じ扱いです。ゲートが開いた後から通常の欠損判定へ移ります。

通常の分析処理中にH1境界が変わった場合は、旧H1を欠損として現在H1へ進みます。TESTER事前分析中の境界変化だけは欠損とせず、現在H1へ追従して次のH1で再試行します。

中間H1の欠損数は`CopyTime`で実在バーを数えます。週末などH1バーが存在しない時間は欠損数に含めません。

## 8. 分析仕様

### 8.1 固定時間足順序

| `time_frame_order` | 時間足 | 用途 |
|---:|---|---|
| 0 | MN1 | 分析開始となる最上位足。MN1はMonthlyを表す |
| 1 | W1 | 週足 |
| 2 | D1 | 日足 |
| 3 | H4 | 4時間足 |
| 4 | H1 | 観測基準足。`is_anchor_time_frame = 1` |

親1行には必ずこの順序の子5行を保存します。順序、件数またはH1アンカーが不正なSnapshotは保存しません。

### 8.2 分析Profile

現行の識別値は次のとおりです。

| 項目 | 値 |
|---|---|
| `analysis_version` | `ELLIOT_MN1_V5` |
| Profile version | `ZIGZAG_ELLIOT_ANALYSIS_PROFILE_V4` |
| 親修正区間規則 | `STRICT_CONFIRMED_FOUR_POINT_OR_NESTED_ABC_AB_V2` |
| Wave分割終了規則 | `POSITION_PROGRESS_TO_POINT_COUNT_V1` |
| Analysis start | MN1 |
| Anchor | H1 |
| Run `strategy` | `H1_OBSERVATION_ALL` |
| Run `strategy_version` | `H1_OBSERVATION_ALL_V5` |
| Run `schema_version` | `6` |

ここでいう`schema_version = 6`は、本インジケーターが作成するRun行のメタデータです。共有DBのAlert Runや、物理DB全体の世代を表す値ではありません。物理DBには全体を一括判定する`PRAGMA user_version`などを使用していません。現行Runの`program_version`は`1.04`です。

計算式へ影響するStochastic、GMMA、ATR、EMA200、ZigZag、Elliott再分析などの設定は、固定順序のCanonical TextとSHA-256 `analysis_input_hash`としてRunへ保存します。

`STRICT_CONFIRMED_FOUR_POINT_OR_NESTED_ABC_AB_V2`は、隣接する親子時間足の確定済み修正区間を対象とします。下位足の通常分析と再分析を完了した後、その親区間で追加されたWave群から重複境界と区間外の文脈点を除きます。親区間の左右境界に対応するポイント間が、補完ポイントを含まない4点の有効な山谷列となる場合は、従来どおり親区間の方向を持つ単一の修正Waveへ置換します。

4点にならない場合でも、親方向の修正`A-B-C`（4点）に逆方向の修正`A-B`（3点）が連続する6点構成は、古い修正の終点を新しい`A`、続く逆方向修正の`A`を新しい`B`、同`B`を新しい`C`として、親方向の単一修正`A-B-C`へ統合します。上昇・下降の両方向およびすべての隣接時間足に同じ規則を適用します。形成中の親区間、補完ポイントを含む構成、Wave数・点数・方向が一致しない構成または境界を一意に検証できない構成は置換せず、既存の分析結果を使用します。

インジケーター運用入力は別の`input_text`へ保存し、FNV-1aによる`input_hash`を生成します。運用入力にはDB名、Common使用有無、Timer秒、DB再試行秒、TESTER保存開始時刻、Queue容量および解決後の28実シンボル名を含めます。

TESTER保存開始時刻は、次の固定形式でMQL5の`datetime`整数値を10進表現して保存します。

```text
observationTesterSaveStartTime=<epoch秒>
```

LIVEでは有効な0以上の入力値にかかわらず`0`を保存します。TESTERでは指定値を保存するため、異なる保存開始時刻は異なる`input_hash`になります。また、新しいRunは`0`の場合もこのキーを追加するため、本対応前のRunとは`input_hash`が変わります。

保存開始時刻は分析計算式を変更しないため、`analysis_input_hash`には含めません。Observationの自然キーにも運用用`input_hash`は含まれないため、保存開始時刻だけが異なるRunで同じ市場時点・同じ分析Profileを保存しても別Observationにはなりません。

### 8.3 BUY・SELLの意味

時間足別の`is_buy`と`buy_sell_label`は、最新Waveの上昇・下降方向ではありません。

短期・中期・長期の3本のStochasticについて、`Main >= Signal`をBUY票として数え、2本以上がBUY票ならBUY、それ以外はSELLです。参照shiftは0なので、各時間足の形成中バーにより判定が変化します。

| フィールド | 意味 |
|---|---|
| `is_buy` / `buy_sell_label` | 3本Stochastic多数決によるElliott分析方向 |
| `is_wave_uptrend` / `wave_trend_label` | 最新Wave自体の上昇・下降方向 |
| `is_oscillator_buy` | Oscillatorへ保存した方向 |

これらを同じ「方向」として扱わないでください。

### 8.4 形成足と確定足

| 指標 | 主な参照 |
|---|---|
| Stochastic方向・継続数 | shift 0 |
| GMMA trend・cross | shift 0 |
| ATR14 | shift 0 |
| EMA200終値位置 | Close shift 1とEMA200 shift 1 |
| EMA200傾き | EMA200 shift 1とshift 4 |

H1境界時点でも、MN1、W1、D1およびH4のcurrent OHLCやshift 0指標は形成中です。Observationはその時点の逐次Snapshotであり、後から完成した上位足の値へ置き換えません。

MN1のEMA200計算はProfileで省略します。

## 9. 保存データ

### 9.1 テーブル関係

```text
zigzag_elliot_alert_runs (1)
  └─ zigzag_elliot_observations (N)
       └─ zigzag_elliot_observation_timeframes (5)
```

1つのH1境界ですべての通貨が成功した場合、親Observationを28行、時間足別データを140行保存します。

### 9.2 親Observation

`zigzag_elliot_observations`は、1通貨・1つのH1開始時刻・1分析Profileの観測本体です。`id`を含めて20列あります。

| グループ | 主な項目 |
|---|---|
| Run | `run_id` |
| 実行元 | `source_mode`、`source_server` |
| 市場 | `symbol_name`、H1のanchor時間足、`spread_pips`、`pip_size` |
| 時刻 | Server/JSTのH1開始時刻と表示文字列 |
| 取得方法 | `capture_phase` |
| 分析Profile | `analysis_version`、`analysis_input_hash` |
| 完全性 | `snapshot_hash`、`time_frame_count` |
| 作成 | `created_at`と表示文字列 |

`spread_pips`には、各通貨のElliott分析開始時に取得したBidとAskの差をpips換算して保存します。エントリーのスプレッド判定およびAlert DBと同じ`todayRate.spread`を使用し、Snapshot生成時やDB保存時には再取得しません。高スプレッドも観測値として上限を設けず保存します。

`pip_size`には、対象ブローカー実シンボルの`SYMBOL_POINT`と`SYMBOL_DIGITS`から取得した1pip相当の価格幅を保存します。3桁・5桁シンボルはPoint×10、それ以外はPointです。`schema_version = 4`以降の新しいRunでは、Snapshot生成時のMT5実測値を使用します。

既存DBには`spread_pips`と`pip_size`をnullable列として非破壊で追加します。`spread_pips`の過去行は推測で補完せず、`NULL`を「未記録」、保存済みの`0.0`を有効なゼロスプレッドとして区別します。`pip_size`は、列追加前の28通貨ペアについて、`symbol_name`に`JPY`を含む7ペアを`0.01`、残る21ペアを`0.0001`としてmigration時に補完します。旧Runには保存当時のPointとDigitsがないため、この値は対象28ペアの既知のpip規則に基づく推定値です。

この値は28通貨Collectorが対象通貨を順次分析した時点のSnapshotです。別チャートで動く実エントリー判定と完全に同一時刻であることは保証しないため、厳密なReject証跡ではなく観測時点の近接値として扱います。

### 9.3 時間足別Observation

`zigzag_elliot_observation_timeframes`は、親1行につき固定5行を保存します。`id`を含めて1行88列あります。

| グループ | 主な項目 |
|---|---|
| 時間足 | 時間足、固定順序、H1アンカーフラグ |
| 分析方向 | BUY・SELL、Oscillator方向 |
| Wave | Wave数、最新Wave、確定、推進・修正、上昇・下降 |
| Elliott | 直前ラベル、最新ラベル、Subラベル、最新点の時刻・価格・補完／山谷／補正フラグ、再分析前ラベル |
| 最新ZigZagPoint | バー位置、次バー時刻、経過本数、pips差、F、深度ゾーン、FE、数字・アルファベット種別 |
| OHLC | 1本前の確定足と現在形成足のOHLC |
| Fibonacci Expansion | 利用可否、61.8～200.0%、現在価格との距離 |
| Stochastic | 3本の継続数、Main、Signal、Main並び順 |
| GMMA | trend count、cross count、EMA30、EMA60、差pips |
| Volatility | ATR14 pips |
| EMA200 | Close、比較EMA、傾き、距離、位置・傾きcode、上下回数、BUY・SELL判定 |

全ZigZagポイント配列は保存せず、最新Waveと最新点の構造化スカラーだけを保存します。

最新ポイント詳細13列を追加しても保存対象は1時間足につき最新点1件です。現在が第5波のときに過去の第3波の副次波、FまたはFEをDBから復元するには、全ポイント子テーブルまたは第3波専用の集約列が別途必要です。

`latest_point_is_added`は、各時間足の`Elliot.getLatestPoint()`が指す`ZigZagPoint.isAddedPoint`を保存します。新規行は通常ポイントを0、補完ポイントを1とします。既存DBへはnullable列を非破壊で追加し、保存当時の値を推測できない過去行は`NULL`の「未記録」として保持します。

同じ最新ポイントについて、`barIndex`、`barTimeNext`、`waveBarsFromStart`、`isPeak`、`pipsDiff`、`fibonacciPercent`、Fibonacci深度ゾーン、`fibonacciExpansionPercent`、`isElliotAlphabet`、再分析前Elliott番号・ラベルおよび`isCorrect`も保存します。既存DBへ追加した13列は過去値を復元せず`NULL`とし、新規Observationから実測値を保存します。

ViewerのH1推移詳細では、`TIMEFRAME COMPARISON`の折りたたみ列`最新ZigZag Point`に13項目をまとめて表示します。Fは再分析前Elliott番号が偶数、FEは奇数の場合に表示し、Depth ZoneはF対象時だけ表示します。アラート詳細は別データ経路のため、この列を表示しません。旧DBの項目なしとMigration済み既存行の`NULL`はいずれも未記録として扱い、`false`と`0`は有効値として表示します。

## 10. DBファイルとRun

### 10.1 保存先

既定値ではAlertと同じDBファイルをCommonフォルダへ保存します。

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-zigzag-elliot-alert.sqlite
```

`observationDatabaseUseCommonFolder = false`の場合は、実行Terminal側の`MQL5\Files`を使用します。

SQLite接続には次を設定します。

- `PRAGMA foreign_keys = ON`
- `PRAGMA journal_mode = WAL`
- 通常の`busy_timeout = 5000`ミリ秒
- Observationテーブル作成時だけ最大60000ミリ秒へ延長し、その後5000ミリ秒へ戻す

### 10.2 単一Run

1回のインジケーター起動中は、28通貨すべてを同じRunへ関連付けます。

`run_uid`は起動ローカル時刻、`GetTickCount64()`およびChart IDから生成します。DB再接続後も同じRun Entityを再利用します。

`observationTesterSaveStartTime > 0`のTESTERでは、全体ゲートが閉じている間はDBを開かず、Run行も保存しません。全28通貨が同じ保存開始候補H1の事前分析に成功してゲートが開いた後、起動時に構築した同じRun EntityをDBへ保存します。

### 10.3 自然キー

Observationの一意性は次で決まります。

```text
source_mode
+ source_server
+ symbol_name
+ anchor_time_frame
+ anchor_bar_time
+ capture_phase
+ analysis_version
+ analysis_input_hash
```

`run_id`は自然キーに含みません。同じ市場時点・同じ分析Profileを別Runから保存しても、新しいObservationへ置き換えません。

### 10.4 Snapshot Hash

`snapshot_hash`は、親の取得元・自然キー相当値、取得時スプレッド、`pip_size`および5時間足の構造化値から生成する16桁の大文字16進文字列です。最新ポイント詳細13項目追加後のHash payloadは`H1_OBSERVATION_V5`です。ID、Run ID、作成日時、JSTおよび表示用日時文字列は含めません。暗号学的Hashではなく、Snapshot内容の比較用です。分析設定を識別する`analysis_input_hash`とは目的が異なります。migrationで列追加や`pip_size`補完を行う既存行のHashは再計算しません。

- `analysis_input_hash`: どの計算設定を使用したか
- `snapshot_hash`: その時点でどの分析結果を保存したか

## 11. 保存、重複および単一Writer

### 11.1 トランザクション

親1行と子5行を1トランザクションで保存します。

- 親または子の検証・INSERTに失敗した場合はROLLBACKする
- 失敗時はEntityへ一時設定したIDを消去する
- 親だけ、または子の一部だけを残さない
- 成功時だけCOMMITする

Run行の準備はこのSnapshotトランザクションより前に行うため、DB障害や通常分析待ちの状況では、Runだけが存在してObservationが0行の状態も正常に起こり得ます。ただし、`observationTesterSaveStartTime > 0`の全体ゲートが閉じている間はRun行自体を保存しません。

### 11.2 First-write wins

自然キーが既に存在する場合は、最初のSnapshotを維持します。

- 同じhashなら既存Observation IDを返す
- 異なるhashでも既存行と子5行を変更しない
- hash差異はINFOログへ記録する

### 11.3 Writer競合の検出

既存Observationの`run_id`が現在の単一Runと異なる場合、Controllerは別Writerによる競合と判定します。

競合検出後は次の動作になります。

- `Writer PASSIVE`相当の状態になる
- 全体処理を停止し、新しい分析と保存を進めない
- 対象通貨を`ERR`にする
- 「別Writerを停止して再起動してください」と表示する

H1 Observationの現行Writerは`ZigZagElliotH1ObservationAll`だけです。同じDB・Server・実行モード・分析Profileに対して、本インジケーターを複数同時稼働させないでください。

通常の`ZigZagElliot`からH1 Observation Writerは撤去されています。ただし、撤去前にコンパイルした`ZigZagElliot.ex5`は、削除済みの入力`h1ElliotObservationDatabaseEnabled=true`で書込みを継続する可能性があります。この旧インスタンスは、本インジケーターを起動する前に停止してください。

## 12. FIFOとDB再試行

### 12.1 FIFO

生成済みSnapshotは中央FIFOへ追加し、古い順に直列保存します。

既定容量672は、28通貨×24 H1本に相当します。容量は親Snapshot件数であり、時間足別子行の件数ではありません。

Queueが満杯の場合は新しいSnapshotを生成せず、対象H1をpendingのまま維持します。次のH1までに空きができなければ、そのpendingは欠損になります。

### 12.2 DB障害

DB接続または保存に失敗した場合は次の順で処理します。

1. FIFO先頭のSnapshotを削除しない
2. その時点でDrainを停止して順序を維持する
3. DB接続を解放する
4. `observationDatabaseRetrySeconds`後にDBと同じRunを再準備する
5. FIFO先頭から保存を再開する

`observationTesterSaveStartTime > 0`で全体ゲートが閉じている状態はDB障害ではありません。この期間はDB接続と再試行を意図的に行わず、FIFOにもSnapshotを追加しません。

LIVEおよびTESTER初回成功後の同じH1内の分析失敗は通貨単位で再試行しますが、過去H1へ移った後の分析欠損は再生成しません。

DB接続・保存および通貨別分析の再試行回数に上限はありません。インジケーターが稼働し、対象H1またはQueue容量に余裕がある間は再試行を継続します。

## 13. 状態パネル

### 13.1 全体表示

パネルは次を表示します。

- 全体状態とRun ID
- LIVEまたはTESTER
- Writer ACTIVE・PASSIVE
- DB OK・WAIT
- Ready通貨数。LIVEでは系列準備済み、保存開始時刻が`0`のTESTERでは初回Snapshot生成済み、保存開始時刻が0より大きいTESTERでは事前分析成功済みの通貨数
- 現在H1のJST
- Detect、Analyze、Save件数
- Queue使用数と容量
- 起動後Gap数
- 最終保存JST
- 直近処理時間ミリ秒
- 各状態にある通貨数

正常な定常状態の目安は次です。

```text
[ACTIVE]
Writer ACTIVE
DB OK
Ready 28/28
Queue 0/672
Gap 0
```

H1境界直後は一時的に`ANALYZING`または`WAITING`になります。

`observationTesterSaveStartTime > 0`で全体ゲートが閉じている間は、`Writer PASSIVE`、`DB WAIT`、`Run 0`、`Detect 0`、`Analyze 0`、`Save 0/0`、`Queue 0`および`Gap 0`が正常です。事前分析は実行しますが、`Analyze`はSnapshot生成数を表すためゲート前は0のままです。`Ready`だけが事前分析の進捗を示します。

保存開始候補H1では同じH1について全28通貨を再度確認するため、保存開始前に`Ready 28/28`へ到達していても再評価されます。候補H1で28/28がそろうとゲートが開き、WriterとDB保存処理が開始します。

### 13.2 通貨別状態

| 状態 | 意味 |
|---|---|
| `BASE` | 初期化中、または現在H1をbaselineへ設定した |
| `WAIT` | 次のH1新規足、TESTER保存開始時刻または全通貨事前分析成功待ち |
| `RUN` | 通常のElliott分析またはTESTER事前分析中 |
| `RETRY` | 履歴、Server情報、分析またはSnapshot生成を再試行中 |
| `DB` | Snapshot生成済み、DB保存待ちまたは保存再試行中 |
| `OK` | 対象H1のDB保存完了 |
| `ERR` | シンボル、ハンドル、領域確保または別Writerなどのエラー |
| `GAP` | 対象H1を保存できず欠損が確定した |

通貨名の後ろに`Qn`がある場合はその通貨のQueue件数、`Rn`がある場合は再試行回数を表します。

## 14. Viewerとの関係

[ZigZagElliot Alert Viewer](../../Services/ZigZagElliotAlertViewer/README.md)の「H1推移」は、Observation親子テーブルを読み取って表示します。

Viewerは次を行います。

- Run、分析Profile、LIVE・TESTER、通貨、JST期間などによる検索
- W1・D1・H4・H1の分析方向とH4・H1 EMA200方向による完全一致検索
- MN1、W1、D1、H4、H1の一覧比較
- 詳細カードとTIMEFRAME COMPARISON
- Elliott、Wave、Stochastic、GMMA、ATRおよびEMA200の表示

Viewerは読取専用です。Observationの生成、再分析、欠損補完またはDB更新は行いません。

H1 Observationの生成は`ZigZagElliotH1ObservationAll`へ一本化されています。通常の`ZigZagElliot`はElliottアラートを保存しますが、H1 Observationは保存しません。本インジケーターには有効化Toggleがなく、起動中は`observationDatabase*`入力に従って収集します。

撤去前の`ZigZagElliot.ex5`を使用している場合は、削除済みの入力`h1ElliotObservationDatabaseEnabled=true`で動作している旧インスタンスを停止してください。旧Writerが保存したObservation行はそのまま維持され、Viewerから引き続き参照できます。Writer撤去に伴うDB移行や既存行の削除は不要です。

## 15. 運用手順

### 15.1 LIVE収集

1. `Indicators/ZigZagElliotH1ObservationAll.mq5`をMetaEditorでコンパイルする
2. 28通貨を提供する取引口座へ接続する
3. 1つのチャートへインジケーターを適用する
4. DB名とCommon使用有無を確認する
5. パネルが`Ready 28/28`、`Writer ACTIVE`、`DB OK`になるまで待つ
6. 次のH1境界後に`Detect 28`、`Analyze 28`、`Save 28/28`を確認する
7. `Queue 0`と`Gap 0`を継続監視する

LIVEのチャート時間足にはH1制限を設けていませんが、用途を明確にするためH1チャートへの適用を推奨します。

同じDBへ書き込む本インジケーターは1つだけ起動してください。

### 15.2 TESTER

- 対象時間足はH1以下を使用する
- Optimizationでは使用しない
- 28通貨すべての履歴とシンボルを利用できる環境を使用する
- 既定ではCommon DBを使用するため、既存LIVEデータとの混在に注意する
- 同じ自然キーを含むTESTER期間を再実行する場合は、専用DBを使用するか、対象となる既存TESTERデータを事前に整理する
- 比較時は`source_mode`、`analysis_version`、`analysis_input_hash`および`input_hash`を分ける

`observationTesterSaveStartTime = 0`は従来互換設定です。追加の二段階事前分析と全通貨ゲートを使用せず、通貨ごとに初回分析へ成功したH1から保存します。28通貨の収集開始H1をそろえたい場合は、0より大きい保存開始時刻を指定してください。

次は、保存対象期間の前に約6年の事前分析期間を置く設定例です。日時はすべて接続先ブローカーの取引サーバー時刻で指定します。

| 設定 | 例 |
|---|---|
| TESTER開始 | `2019.01.01 00:00` |
| `observationTesterSaveStartTime` | `D'2025.07.01 00:00'` |
| TESTER終了 | `2025.12.31 23:59` |

この例では、2025年7月1日より前のH1を履歴および実分析の準備に使用しますが、ObservationとRun行を生成せず、FIFOへの追加およびGapの加算も行いません。保存開始候補H1で全28通貨が同じH1の事前分析に成功するとゲートが開き、そのH1から通常収集へ移ります。1通貨でも失敗した場合は全体を保存せず、次のH1を新しい候補にします。

MN1の最低61本には約5年1か月が必要です。休日、履歴配信範囲およびブローカー差を考慮し、TESTER開始は保存開始時刻より余裕を持って前へ設定してください。61本と206本を満たしても、全28通貨の実分析が成功するまでは保存を開始しません。

保存開始時刻がH1境界と一致しない例は次のとおりです。

| 入力 | 判定 |
|---|---|
| `D'2025.07.01 18:00'` | `18:00`のH1が最初の保存候補 |
| `D'2025.07.01 18:30'` | `18:00`は事前分析扱い、`19:00`のH1が最初の保存候補 |

再現性を高めるため、通常はH1境界に一致する時刻を指定してください。入力値はJSTへ自動解釈されません。

共有DBで同じTESTER期間・Server・分析Profileを再実行すると、前回Runが保存した自然キーと重複し、Writer競合として停止します。新しいRunを開始するだけでは重複を回避できません。過去行を維持する場合は別DBを使用し、共有DBへ書き直す場合はバックアップ後に対象TESTERデータを整理してから実行してください。

## 16. 障害対応

| 表示・事象 | 主な原因 | 対応 |
|---|---|---|
| `Ready`が28未満 | LIVEではMN1～H1履歴の不足・同期待ち。TESTERでは初回分析、事前分析またはSnapshot生成の未成功も含む | Terminal接続、各シンボルの履歴および詳細メッセージを確認する |
| `DB WAIT` | DB接続、WAL、table作成またはRun保存待ち。保存開始ゲートが閉じている期間も正常に表示する | 保存ゲート中でなければDBファイル、権限、他プロセスのlockを確認する |
| `RETRY` | H1系列、Server情報、Elliott分析またはSnapshot生成待ち | 詳細メッセージとExpertsログを確認する |
| `DB`が継続 | Queue保存中または保存失敗後の再試行 | Queue増加とDB接続を確認する |
| `Queue`が増加 | DBの書込み速度低下または接続障害 | DB Writer、disk、lock、retry設定を確認する |
| `GAP` | 次のH1までに前H1を分析できなかった | 原因を修正する。失われたH1は自動復元されない |
| 別Writerエラー | 同じ自然キーを別Runが先に保存した | 重複インスタンスを停止し、本インジケーターを再起動する |
| 初期化失敗 | 入力不正、28通貨解決失敗、ハンドル生成失敗 | Inputs、Market Watch、ブローカー銘柄を確認する |

## 17. DBスモークテスト

DB親子保存は次のScriptで検証します。

[ZigZagElliotH1ObservationDatabaseSmokeTest.mq5](../../Scripts/Mstng/Database/ZigZagElliotH1ObservationDatabaseSmokeTest.mq5)

既定の専用DBは次です。

```text
mstng-zigzag-elliot-h1-observation-smoke-test.sqlite
```

主な検証内容は次のとおりです。

- Runの分析Profile Canonical TextとHash
- 親1行とMN1～H1の子5行
- 同一hashの冪等保存
- hashが異なる重複でもfirst-writeを維持すること
- Server時刻とJSTの整合
- 旧JST列なしSchema、旧`pip_size`列なしSchema、旧`latest_point_is_added`列なしSchemaおよび最新ポイント詳細13列なしSchemaからのMigration
- JPY・非JPY既存行の`pip_size`推定補完と新規行のMT5実測値保存
- `latest_point_is_added`の既存行NULL維持と新規行0・1保存
- 最新ポイント詳細13列の既存行NULL維持、Migration再実行および新規行の値保存
- 親・子の不正値拒否
- 子INSERT失敗時のTransaction ROLLBACK
- 必須Indexの存在とQuery Plan
- `foreign_keys`、`foreign_key_check`、`integrity_check`

`recreateDatabaseObjects = true`でテーブルを再作成できるのは、誤操作防止のため既定の専用DB名だけです。本番DBをSmokeへ指定しないでください。

このSmokeはDB契約を検証するものであり、28通貨のH1境界検出やLIVEの長時間運転までは検証しません。

## 18. 確認用SQL

最新のH1境界で通貨数と子行数を確認します。`?1`から順に実行モード、接続Server、分析Version、分析入力Hashを指定し、別の収集母集団を混在させないでください。

```sql
SELECT observation.anchor_jst_time_text,
       COUNT(DISTINCT observation.symbol_name) AS symbol_count,
       COUNT(time_frame.id) AS time_frame_count
FROM zigzag_elliot_observations AS observation
INNER JOIN zigzag_elliot_observation_timeframes AS time_frame
        ON time_frame.observation_id = observation.id
WHERE observation.source_mode = ?1
  AND observation.source_server = ?2
  AND observation.analysis_version = ?3
  AND observation.analysis_input_hash = ?4
GROUP BY observation.anchor_jst_time, observation.anchor_jst_time_text
ORDER BY observation.anchor_jst_time DESC
LIMIT 24;
```

すべて成功したH1では`symbol_count = 28`、`time_frame_count = 140`になります。

子時間足が5行でないObservationを確認します。0行が正常です。

```sql
SELECT observation.id,
       observation.symbol_name,
       observation.anchor_jst_time_text,
       COUNT(time_frame.id) AS time_frame_count
FROM zigzag_elliot_observations AS observation
LEFT JOIN zigzag_elliot_observation_timeframes AS time_frame
       ON time_frame.observation_id = observation.id
GROUP BY observation.id,
         observation.symbol_name,
         observation.anchor_jst_time_text
HAVING COUNT(time_frame.id) <> 5;
```

## 19. 既知の制約

- 起動前または停止中のH1は収集しない
- 保存ゲートが開いた後に分析失敗が次のH1まで続いた場合、欠損を自動バックフィルしない
- FIFOはメモリのみで、終了時の未保存Snapshotは失われる
- 28通貨はコードで固定され、入力から増減できない
- 1インスタンスが28通貨を順番に処理するため、処理時間中にH1境界が変わると欠損になり得る
- 形成中の上位足とshift 0指標を含むため、後の確定値とは一致しない場合がある
- 全ZigZagポイントを保存しないため、DBだけからWaveを完全再構築できない
- 自然キーが同じ別Runとの同時書込みを検出すると、再起動まで処理を停止する
- DB障害がQueue容量を超えて続くと、新しい観測を保持できない
- Status Panelの表示設定はRun比較用の入力Hashへ含まれない
- `observationTesterSaveStartTime = 0`のTESTERでその通貨の初回履歴準備が未完了の場合、同じH1内の後続`OnCalculate`では準備状態を再確認せず、次のH1境界で再確認する
- `observationTesterSaveStartTime = 0`のTESTERで初回履歴準備後の分析が失敗した場合も、分析準備完了フラグが立つまでは同じH1内で再試行せず、次のH1境界へ進む。最初のSnapshotが成功した後は通常のpending再試行へ移行する
- `observationTesterSaveStartTime = 0`のTESTERで最初のSnapshotへ成功する前に保存できなかったH1は、DB上では欠損するがStatus Panelの`Gap`へ加算されない
- `observationTesterSaveStartTime > 0`の事前分析は、通貨ごとに各H1で最大1回だけ実行する。履歴準備または分析に失敗しても同じH1内では再試行せず、Gapを加算しないまま次のH1で再試行する
- `observationTesterSaveStartTime > 0`では、保存開始時刻以上でも全28通貨が同じH1の事前分析に成功するまでObservation、FIFO、DB RunおよびGapを生成しない。除外したH1を後からバックフィルしない
- 保存開始候補で28通貨の現在H1が一致しない場合は全体ゲートを開かない。ゲート後に一時的な時刻差が発生した場合、状態パネルのDetect・Analyze・Save件数は現在バッチ時刻と一致する通貨だけを集計する

## 20. 関連実装

- [ZigZagElliotH1ObservationAll.mq5](../../Indicators/ZigZagElliotH1ObservationAll.mq5)
- [H1ElliotObservationAllController.mqh](../../Include/Mstng/Indicator/ZigZagElliot/H1ElliotObservationAllController.mqh)
- [H1ElliotObservationAllStatus.mqh](../../Include/Mstng/Indicator/ZigZagElliot/H1ElliotObservationAllStatus.mqh)
- [DrawH1ElliotObservationAllStatus.mqh](../../Include/Mstng/Draw/DrawH1ElliotObservationAllStatus.mqh)
- [ZigZagElliotAnalysisProfile.mqh](../../Include/Mstng/Elliot/ZigZagElliotAnalysisProfile.mqh)
- [ZigZagElliotObservationSnapshotBuilder.mqh](../../Include/Mstng/ExpertAdvisor/ZigZagElliotObservationSnapshotBuilder.mqh)
- [ZigZagElliotObservationPersistenceService.mqh](../../Include/Mstng/Database/Service/ZigZagElliotObservationPersistenceService.mqh)
- [ZigZagElliotObservationDao.mqh](../../Include/Mstng/Database/Dao/ZigZagElliotObservationDao.mqh)
- [ZigZagElliotObservationTimeFrameDao.mqh](../../Include/Mstng/Database/Dao/ZigZagElliotObservationTimeFrameDao.mqh)
- [ZigZagElliotObservationAddedPointMigration.mqh](../../Include/Mstng/Database/Dao/ZigZagElliotObservationAddedPointMigration.mqh)
- [ZigZagElliotObservationPointDetailsMigration.mqh](../../Include/Mstng/Database/Dao/ZigZagElliotObservationPointDetailsMigration.mqh)
- [ZigZagElliotアラートデータベース仕様書](../Database/ZigZagElliotAlertDatabase.md)
- [ZigZagElliot Alert Viewer README](../../Services/ZigZagElliotAlertViewer/README.md)
