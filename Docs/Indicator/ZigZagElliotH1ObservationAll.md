# ZigZagElliotH1ObservationAll仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象 | `Indicators/ZigZagElliotH1ObservationAll.mq5` |
| プログラムバージョン | `1.00` |
| 役割 | 全28通貨のH1新規足時点におけるElliott分析結果を時系列保存する |
| 基準時間足 | H1 |
| 保存時間足 | MN1、W1、D1、H4、H1 |
| 保存先 | MetaTrader 5組み込みSQLite |
| 観測タイミング | `BAR_OPEN_FIRST_SUCCESS` |
| 最終更新日 | 2026-08-14 |

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
- MFE、MAE、SL、TPまたは損益結果の保存

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
| Queue容量が28未満 | `INIT_PARAMETERS_INCORRECT` |
| `MQL_OPTIMIZATION = true` | `INIT_PARAMETERS_INCORRECT` |
| TESTERの対象時間足がH1より上位 | `INIT_PARAMETERS_INCORRECT` |
| 28通貨のいずれかを解決できない | `INIT_FAILED` |
| 分析ハンドルを準備できない | `INIT_FAILED` |

状態パネル関連の5入力は表示だけに影響し、DB Runの`input_text`と`input_hash`には含めません。

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

DB接続やRun保存の一時的な失敗だけでは初期化を失敗させません。Controllerは稼働を継続し、設定した再試行間隔でDBを再準備します。最初のDB接続も初期化直後ではなく、`observationDatabaseRetrySeconds`経過後に試行します。それまでに生成できたSnapshotはFIFOへ保持します。

### 6.2 LIVEとTESTERの違い

| 項目 | LIVE | TESTER |
|---|---|---|
| 実行イベント | `OnTimer` | `OnCalculate` |
| 境界確認頻度 | `observationTimerSeconds` | 価格更新ごと |
| Timer登録 | あり | なし |
| 起動直後の現在H1 | baselineとして設定し保存しない | 履歴準備後の最初の成功時に保存する |
| `source_mode` | `LIVE` | `TESTER` |
| 最適化 | 対象外 | 使用不可 |

LIVEでは、インジケーターを有効にした時点の進行中H1をbaselineにします。最初の保存対象は、その次に検出したH1新規足です。

TESTERでは、各通貨についてH1境界ごとに履歴準備を確認します。準備できたH1を分析待ちに設定し、その場で分析に成功した場合に最初のSnapshotとして保存します。初回準備中の詳しい再試行制約は[19. 既知の制約](#19-既知の制約)を参照してください。

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

### 7.2 履歴準備条件

各通貨について5時間足すべての系列同期を確認します。

| 時間足 | 最低バー数 |
|---|---:|
| MN1 | 61 |
| W1 | 206 |
| D1 | 206 |
| H4 | 206 |
| H1 | 206 |

初期の履歴取得要求では各時間足500本をwarm-upします。LIVEでpendingとなった観測は、履歴が不足または未同期の場合も同じH1内でTimerごとに再試行します。TESTERで初回履歴準備中の場合は挙動が異なるため、[19. 既知の制約](#19-既知の制約)を参照してください。

### 7.3 Snapshotの時点

1つのSnapshotは、対象H1バーの分析に最初に成功した時点を固定します。

- `anchor_bar_time`はH1バー開始のサーバー時刻
- `anchor_jst_time`は同時刻を`TimeJapanUtil`でJSTへ変換した値
- `capture_phase`は常に`BAR_OPEN_FIRST_SUCCESS`
- `created_at`は実際にSnapshotを生成した時刻
- 履歴準備や分析再試行により、`created_at`がH1開始時刻より遅れる場合がある
- Snapshot生成後に市場値が変化しても、Queue内の内容を再分析または更新しない

これにより、DB障害中でも分析成功時点の内容を維持したまま後から保存できます。

### 7.4 境界変化と欠損

LIVEでpendingとなった観測、およびTESTERで最初のSnapshotへ成功した後の観測は、同じH1内で履歴準備、Elliott分析またはSnapshot生成に失敗しても再試行します。TESTERの初回Snapshotより前だけは、H1境界単位で再試行します。

LIVEおよびTESTERで最初のSnapshotへ成功した後は、次のH1へ移るまでに成功しなかった前のpendingを`gapCount`へ加算し、新しいH1を分析対象にします。過去H1を現在値から再構築しません。

TESTERで最初のSnapshotへ成功する前は専用の初回準備分岐を通るため、履歴待ち、またはH1境界が変わらないまま分析失敗となったH1を保存しない一方、`gapCount`にも加算しません。

分析処理中にH1境界が変わった場合も、旧H1を欠損として現在H1へ進みます。

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
| `analysis_version` | `ELLIOT_MN1_V2` |
| Profile version | `ZIGZAG_ELLIOT_ANALYSIS_PROFILE_V1` |
| Analysis start | MN1 |
| Anchor | H1 |
| Run `strategy` | `H1_OBSERVATION_ALL` |
| Run `strategy_version` | `H1_OBSERVATION_ALL_V1` |
| Run `schema_version` | `2` |

ここでいう`schema_version = 2`は、本インジケーターが作成するRun行のメタデータです。共有DBの現行Alert仕様で使用するRunの`schema_version = 3`や、物理DB全体の世代を表す値ではありません。物理DBには全体を一括判定する`PRAGMA user_version`などを使用していません。

計算式へ影響するStochastic、GMMA、ATR、EMA200、ZigZag、Elliott再分析などの設定は、固定順序のCanonical TextとSHA-256 `analysis_input_hash`としてRunへ保存します。

インジケーター運用入力は別の`input_text`へ保存し、FNV-1aによる`input_hash`を生成します。運用入力にはDB名、Common使用有無、Timer秒、DB再試行秒、Queue容量および解決後の28実シンボル名を含めます。

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

`zigzag_elliot_observations`は、1通貨・1つのH1開始時刻・1分析Profileの観測本体です。`id`を含めて18列あります。

| グループ | 主な項目 |
|---|---|
| Run | `run_id` |
| 実行元 | `source_mode`、`source_server` |
| 市場 | `symbol_name`、H1のanchor時間足 |
| 時刻 | Server/JSTのH1開始時刻と表示文字列 |
| 取得方法 | `capture_phase` |
| 分析Profile | `analysis_version`、`analysis_input_hash` |
| 完全性 | `snapshot_hash`、`time_frame_count` |
| 作成 | `created_at`と表示文字列 |

### 9.3 時間足別Observation

`zigzag_elliot_observation_timeframes`は、親1行につき固定5行を保存します。`id`を含めて1行74列あります。

| グループ | 主な項目 |
|---|---|
| 時間足 | 時間足、固定順序、H1アンカーフラグ |
| 分析方向 | BUY・SELL、Oscillator方向 |
| Wave | Wave数、最新Wave、確定、推進・修正、上昇・下降 |
| Elliott | 直前ラベル、最新ラベル、Subラベル、最新点時刻・価格 |
| OHLC | 1本前の確定足と現在形成足のOHLC |
| Fibonacci Expansion | 利用可否、61.8～200.0%、現在価格との距離 |
| Stochastic | 3本の継続数、Main、Signal、Main並び順 |
| GMMA | trend count、cross count、EMA30、EMA60、差pips |
| Volatility | ATR14 pips |
| EMA200 | Close、比較EMA、傾き、距離、位置・傾きcode、上下回数、BUY・SELL判定 |

全ZigZagポイント配列は保存せず、最新Waveと最新点の構造化スカラーだけを保存します。

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

`snapshot_hash`は、親の取得元・自然キー相当値と5時間足の構造化値から生成する16桁の大文字16進文字列です。ID、Run ID、作成日時、JSTおよび表示用日時文字列は含めません。暗号学的Hashではなく、Snapshot内容の比較用です。分析設定を識別する`analysis_input_hash`とは目的が異なります。

- `analysis_input_hash`: どの計算設定を使用したか
- `snapshot_hash`: その時点でどの分析結果を保存したか

## 11. 保存、重複および複数Writer

### 11.1 トランザクション

親1行と子5行を1トランザクションで保存します。

- 親または子の検証・INSERTに失敗した場合はROLLBACKする
- 失敗時はEntityへ一時設定したIDを消去する
- 親だけ、または子の一部だけを残さない
- 成功時だけCOMMITする

Run行の準備はこのSnapshotトランザクションより前に行うため、DB障害や分析待ちの状況では、Runだけが存在してObservationが0行の状態も正常に起こり得ます。

### 11.2 First-write wins

自然キーが既に存在する場合は、最初のSnapshotを維持します。

- 同じhashなら既存Observation IDを返す
- 異なるhashでも既存行と子5行を変更しない
- hash差異はINFOログへ記録する

### 11.3 別Writerの検出

既存Observationの`run_id`が現在の単一Runと異なる場合、Controllerは別Writerによる競合と判定します。

競合検出後は次の動作になります。

- `Writer PASSIVE`相当の状態になる
- 全体処理を停止し、新しい分析と保存を進めない
- 対象通貨を`ERR`にする
- 「別Writerを停止して再起動してください」と表示する

同じDB・Server・実行モード・分析Profileに対して、複数の`ZigZagElliotH1ObservationAll`を同時稼働させないでください。

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

LIVEおよびTESTER初回成功後の同じH1内の分析失敗は通貨単位で再試行しますが、過去H1へ移った後の分析欠損は再生成しません。

DB接続・保存および通貨別分析の再試行回数に上限はありません。インジケーターが稼働し、対象H1またはQueue容量に余裕がある間は再試行を継続します。

## 13. 状態パネル

### 13.1 全体表示

パネルは次を表示します。

- 全体状態とRun ID
- LIVEまたはTESTER
- Writer ACTIVE・PASSIVE
- DB OK・WAIT
- Ready通貨数。LIVEでは系列準備済み、TESTERでは初回Snapshot生成済みの通貨数
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

### 13.2 通貨別状態

| 状態 | 意味 |
|---|---|
| `BASE` | 初期化中、または現在H1をbaselineへ設定した |
| `WAIT` | 次のH1新規足待ち |
| `RUN` | Elliott分析中 |
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
- MN1、W1、D1、H4、H1の一覧比較
- 詳細カードとTIMEFRAME COMPARISON
- Elliott、Wave、Stochastic、GMMA、ATRおよびEMA200の表示

Viewerは読取専用です。Observationの生成、再分析、欠損補完またはDB更新は行いません。

Viewer READMEにある`h1ElliotObservationDatabaseEnabled`は、通常の`ZigZagElliot`内にある別の収集経路の設定です。本スタンドアロンインジケーターには有効化Toggleがなく、起動中は`observationDatabase*`入力に従って常に収集します。

通常の`ZigZagElliot`で`h1ElliotObservationDatabaseEnabled = true`にした収集経路と、本インジケーターを同じDB・Server・実行モード・分析Profileで同時稼働させないでください。同じ自然キーを別Runから保存すると、first-write後に本インジケーターが別Writer競合を検出して停止します。

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
- 比較時は`source_mode`、`analysis_version`および`analysis_input_hash`を分ける

## 16. 障害対応

| 表示・事象 | 主な原因 | 対応 |
|---|---|---|
| `Ready`が28未満 | LIVEではMN1～H1履歴の不足・同期待ち。TESTERでは初回分析またはSnapshot生成の未成功も含む | Terminal接続、各シンボルの履歴および詳細メッセージを確認する |
| `DB WAIT` | DB接続、WAL、table作成またはRun保存待ち | DBファイル、権限、他プロセスのlockを確認する |
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
- 旧JST列なしSchemaからのMigration
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
- 分析失敗が次のH1まで続いた場合、欠損を自動バックフィルしない
- FIFOはメモリのみで、終了時の未保存Snapshotは失われる
- 28通貨はコードで固定され、入力から増減できない
- 1インスタンスが28通貨を順番に処理するため、処理時間中にH1境界が変わると欠損になり得る
- 形成中の上位足とshift 0指標を含むため、後の確定値とは一致しない場合がある
- 全ZigZagポイントを保存しないため、DBだけからWaveを完全再構築できない
- 自然キーが同じ別Runとの同時書込みを検出すると、再起動まで処理を停止する
- DB障害がQueue容量を超えて続くと、新しい観測を保持できない
- Status Panelの表示設定はRun比較用の入力Hashへ含まれない
- TESTERでその通貨の初回履歴準備が未完了の場合、同じH1内の後続`OnCalculate`では準備状態を再確認せず、次のH1境界で再確認する
- TESTERで初回履歴準備後の分析が失敗した場合も、分析準備完了フラグが立つまでは同じH1内で再試行せず、次のH1境界へ進む。最初のSnapshotが成功した後は通常のpending再試行へ移行する
- TESTERで最初のSnapshotへ成功する前に保存できなかったH1は、DB上では欠損するがStatus Panelの`Gap`へ加算されない
- 状態パネルの現在バッチ時刻は28通貨の現在H1開始時刻の最大値であり、ブローカー側で通貨ごとの開始時刻が一時的にずれた場合、Detect・Analyze・Save件数はその最大時刻と一致する通貨だけを集計する

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
- [ZigZagElliotアラートデータベース仕様書](../Database/ZigZagElliotAlertDatabase.md)
- [ZigZagElliot Alert Viewer README](../../Services/ZigZagElliotAlertViewer/README.md)
