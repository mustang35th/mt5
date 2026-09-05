# MstngH1Ea基本設計書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象EA | H1専用EA `MstngH1Ea` |
| 実装ファイル | `Experts/MstngH1Ea.mq5` |
| 対象プラットフォーム | MetaTrader 5 |
| 対象時間足 | H1固定 |
| 対象戦略 | `MTF_3in3`固定 |
| 文書状態 | 初版実装・テスター受入確認中 |
| 設計バージョン | 0.6 |
| EAプログラムバージョン | 1.05 |
| 最終更新日 | 2026-09-05 |

本書は、`MstngEa`を基礎として機能をH1運用に限定した新EAの初版仕様を定義します。現行の`MstngEa`を変更する設計ではなく、必要な判定クラスだけを再利用して、制御、発注および永続化を新しく構成します。

エントリー互換性の基準は、2026-09-05時点の通常版`ZigZagElliot`をH1チャートで動かした場合の`MTF_3in3`初期設定です。`ZigZagElliotList`や`MstngEa`側の別設定ではありません。条件だけでなく、分析開始時間足、判定周期およびJudge成立回数の扱いを合わせます。実際の発注には、既定のSL・保有数・DBなどの安全条件を別途適用します。

v0.5では、通常版と共用する`MTF_3in3`のH1 Spread上限を3.0 pipsから5.0 pipsへ拡大します。H1以外と他戦略の上限は変更しません。Spreadは引き続き共通Judgeの成立条件であり、回数消費の順序は変えません。旧3.0 pips仕様とEntry時刻・成立回数が一致することは保証しません。

SQLiteの物理構成、列および制約は[MstngH1Eaデータベース設計書](../Database/MstngH1EaDatabase.md)を参照してください。

## 2. 目的

初版の目的は、H1の`MTF_3in3`条件だけを使用して、次を安全かつ再現可能に実行することです。

- 各H1バーの初回分析成功時のエントリー判定（起動時の進行中バーを含む）
- 固定ロットの成行注文
- 必須のbrokerストップロス
- 確定H1 ZigZagによるSLトレイル
- トレイルSL反映前の候補跨ぎによる全量決済
- 同一シグナルの再起動をまたぐ重複防止
- 判定、注文および決済結果のSQLite保存
- 再起動時のDBとbrokerポジションの整合

多機能化よりも、注文根拠、ポジション状態および決済結果を追跡できる小さな実装を優先します。

## 3. 初版の対象範囲

### 3.1 採用する機能

- H1チャート限定
- `MTF_3in3`戦略限定
- MN1、W1、D1、H4、H1の親子関係を維持した分析
- W1、D1、H4、H1の方向一致と、MN1方向またはW1 EMA200方向の一致
- H1およびH4のElliott波動判定
- H1 GMMA判定
- H1およびH4のEMA200方向判定
- 最大5 pipsのSpread制限
- 1シグナルにつき初回Judge成立時だけ詳細Entry判定（発注試行は最大1回）
- 同一シンボル、同一Magic Numberで1ポジション
- 固定ロットの成行注文
- H1 ZigZag基準点による必須初期SLと最大幅制限
- 確定H1 ZigZagによるSLトレイル
- トレイル候補のSQLite永続化と再起動復旧
- トレイルSL反映前の候補跨ぎによる全量決済
- 専用SQLiteへの判定・取引保存
- 障害調査用のテキスト運用ログ

### 3.2 初版の対象外

- H1以外の時間足
- 戦略選択
- W1追加確認の必須化・モード選択（主条件のW1方向・W1 EMA200は使用する）
- 通貨強弱フィルター
- EMA200との距離制限
- 建値移動
- 利益戻し決済
- 反対GMMAによる戦略決済
- 固定TPおよび分割利確
- 時間切れ、曜日、ロールオーバーによる決済
- チャート上のステータスパネル、シグナル表示およびElliott表示
- メールおよびプッシュ通知
- 取引CSV、決済専用CSVおよび検証CSV
- ViewerのEA取引タブ

対象外機能は、初版の運用結果を確認した後に個別に追加します。

## 4. 基本構成

```text
MstngH1Ea
  ├─ H1専用Controller
  │    ├─ Entry判定済みバー・トレイル評価バーの個別管理
  │    ├─ MN1/W1/D1/H4/H1分析
  │    ├─ 既存H1判定周期でのEntry・新規バーでのH1 ZigZagトレイル
  │    ├─ pending保護SL再試行
  │    ├─ 候補跨ぎ決済
  │    └─ 再起動整合
  ├─ H1 MTF_3in3判定
  │    ├─ W1/D1/H4/H1方向 ＋ MN1方向またはW1 EMA200
  │    ├─ Judge成立回数（初回のみEntryへ）
  │    ├─ H1/H4 Elliott
  │    ├─ H1 GMMA
  │    └─ H1/H4 EMA200
  ├─ H1専用Trade Executor
  │    ├─ OrderCheck
  │    ├─ 成行発注
  │    ├─ 必須SL
  │    ├─ SLTP変更
  │    └─ pending注文・SL確認
  └─ H1 EA SQLite
       ├─ Run
       ├─ H1判定
       ├─ 取引ライフサイクル
       └─ トレイル候補・SL変更履歴
```

既存の`EaController`、`EaConfig`、`StrategyFactory`および`TradeExecutor`は、多時間足、多戦略、CSV、画面表示および利益保護へ依存するため、そのまま流用しません。

## 5. 入力値と固定値

初版のinputは次に限定します。

| input | 既定値 | 内容 |
|---|---:|---|
| `InpLotSize` | `0.01` | 小数8桁に正規化した固定ロット。brokerの最小値、最大値、stepへ正規化 |
| `InpMaxInitialStopLossPips` | `100.0` | 許可する初期リスク幅。利用者指定により既定100.0 pips。0以下は無制限ではなく初期化拒否 |
| `InpTesterTradeStartTime` | `2026.01.01 00:00` | Tester専用の売買開始日時（`datetime`）。0なら開始日時の制限なし |

`InpTesterTradeStartTime`はinput group「テスター設定」へ配置します。Tester内のサーバー日時で指定し、JSTへ自動変換しません。LIVEでは入力値にかかわらず無効とし、有効設定値を0にします。

次は初版の内部固定値とします。

| 項目 | 固定値 |
|---|---:|
| 時間足 | `PERIOD_H1` |
| 戦略 | `MTF_3in3` |
| W1追加確認 | `H1_W1_CONFIRMATION_OBSERVE_ONLY`（診断のみ） |
| 方向一致 | `H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED` |
| EMA200確認 | `H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED` |
| Entry対象回数 | `1`（初回Judge成立時） |
| H1表示波の回数制限 | `false`（既存初期値。H1へ追加ゲートを設けない） |
| 通貨強弱のEntryフィルター | `false` |
| LIVE Entry分析周期 | 初回タイマーから開始、以後30秒間隔（1秒タイマーで管理） |
| Tester Entry分析周期 | 売買開始前はH1ごとの履歴準備確認のみ、開始後はtickごとに未処理H1バーを分析 |
| 最大Spread | 5.0 pips |
| ZigZag SL余白（初期・トレイル） | 10.0 pips |
| 許容deviation | 10 points |
| TP | なし |
| DBフォルダ | Common固定 |
| LIVE DB名 | `mstng-h1-ea.sqlite` |
| Tester DB名 | `mstng-h1-ea-tester.sqlite` |
| heartbeat間隔 | 通常10秒、安全条件を満たすTester高速ウォームアップ中だけ30秒 |
| Timer間隔 | 通常1秒、安全条件を満たすTester高速ウォームアップ中だけ30秒 |
| Lease有効期間 | 60秒 |
| DB再接続・キュー再保存間隔 | 最短5秒 |
| 未保存キュー上限 | Decision 256件、Trade/Event 256件 |

Magic Numberは既存の`MagicNumberUtil`を利用し、EAコード`12`で自動生成します。現行`MstngEa`のEAコード`11`と分離します。

再接続・保護操作の経過時間はLIVEでは`GetTickCount64()`、Testerでは`TimeCurrent()`をミリ秒化したテスト内時刻で測ります。Testerの再試行回数をPCの処理速度に依存させません。broker由来のミリ秒時刻とは区別し、この経過時間をDBの約定日時へ保存しません。

初期化時に、H1以外のチャート、0以下のロット、0以下の最大初期SL幅、ヘッジ口座以外、pip size・tick sizeを取得できないシンボルおよび無効な取引環境を拒否します。

`InpMaxInitialStopLossPips`の既定値は、利用者指定により`100.0` pipsとします。研究DBには初期SL幅の分布を確定できる`risk_pips`の記録がないため、この値は研究分布に基づく上限ではありません。0以下を指定した場合は初期化を拒否します。監査用Canonical Textと実際の上限を一致させるため、小数は1桁まで指定できます。

## 6. イベント処理

### 6.1 初期化

`OnInit()`では次を行います。

1. H1チャートであることを確認する
2. Market Context、Magic Numberおよび分析ハンドルを準備する
3. ポジション取得と注文機能を準備する
4. Commonフォルダの同一コンテキスト用Lockを排他的に取得する
5. 専用SQLiteを開き、接続設定とスキーマを確認する
6. 単一transactionで期限切れRunを処理し、今回Runの登録とLease取得を行う
7. 前回Run、active取引およびpending保護SL候補をbrokerへ照合する
8. broker SLへ未反映の保護SL候補があれば種別とともに復元して再試行対象にする
9. 消費済みSKIPを含むJudge回数と、DBへ確定保存済みのEntry判定バーを復元する
10. Entry未処理なら現在のH1バーを判定対象にする。ただしTesterの売買開始前はEntry状態へ登録しない。トレイル用の新規バー検出は別に初期化する

`OnInit()`内では発注しません。LIVEは最初のタイマー実行、Testerは売買開始日時以降の最初のtickから、その時点の進行中H1バーも判定対象にします。Testerで開始日時が0なら最初のtickから対象です。ただし、同じコンテキスト・H1バーのDecisionがDBにあれば再判定・再加算しません。再起動までの未処理の過去バーを遡って発注しません。

DBを利用できない場合も、排他Lockを取得できていれば既存の自EAポジションを保護する制限状態で稼働します。起動時からDBを利用できない場合はpending候補を復元できないため、新規エントリーを停止してbroker SLだけを維持します。起動後にDB接続を失った場合は、既にメモリへ復元または登録済みのpending保護SL候補と候補跨ぎ決済だけを安全期限内で継続できます。DBにない候補を価格から推測しません。排他Lockも取得できない場合は初期化を拒否します。

同一接続サーバー、口座、シンボルおよびMagic NumberでLock済み、または有効な別RunのLeaseがある場合、二重起動として初期化を拒否します。期限切れLeaseだけを引き継ぎ、稼働中Runを無条件に`INTERRUPTED`へ変更しません。

### 6.2 毎ティック処理

毎ティックでは次を行います。

ただし15.2の高速ウォームアップ安全条件をすべて満たす場合は、tickごとの取引照合・pending処理などを省略し、H1バーごとの履歴準備確認だけを行います。売買開始日時への到達、既存リスクの発見、DB・Lease異常時は通常周期へ戻り、以下の保護処理を続けます。

1. 自EAポジションとpending取引の状態を確認する
2. pending保護SL候補があれば、broker SL反映、候補跨ぎおよび再試行時刻を確認する
3. 必要なSL変更または候補跨ぎ決済を最短1秒間隔で再試行する
4. 未保存の取引結果があればDB再接続と保存を試みる
5. 候補跨ぎ決済を開始した場合は、そのH1バーの新規発注禁止を記録する。`CLOSE_PENDING`・`CLOSE_PARTIAL`中も新規発注とトレイル評価は禁止する
6. 新しいH1バーなら6.3のトレイル処理を実行する
7. Testerの場合は6.3のEntry処理を実行する。LIVEのEntry処理はタイマー側だけで実行する

建値移動、利益戻しおよび反対GMMAによる成行決済は行いません。

`OnTimer()`は通常1秒間隔とし、排他Lock確認、10秒ごとのheartbeat更新およびDB再接続確認を行います。15.2のTester高速ウォームアップ中だけTimer・heartbeatを30秒へ変更し、Leaseは60秒のまま維持します。LIVEでは最初のタイマーから、以後30秒間隔で未処理H1バーのEntry分析・判定・発注も行います。分析失敗でも次の試行は同じ30秒周期です。SL変更・候補跨ぎ決済はtick側に限定し、TesterのタイマーではEntry判定を行いません。

Testerの売買開始前を除き、保有中・決済中でもEntryの戦略判定と回数管理は続け、発注だけを安全条件で止めます。ポジション管理の都合でJudgeの初回を後のバーへ繰り越しません。

最後に確認できた`lease_expires_at`を更新できないまま期限へ到達した場合、split-brainを防ぐためEAからの注文、SL変更および成行決済を停止します。起動後に一度もDB Leaseを取得できない場合は最初からEAの取引操作を禁止し、Lock取得時刻から60秒はDB再接続と初期照合を試す上限にだけ使用します。この60秒はbroker送信権限を与えません。brokerへ設定済みのSLは継続します。

### 6.3 H1バー単位の処理

トレイルとEntryは、評価時刻と処理済みバーを分けて管理します。

#### 6.3.1 トレイル処理

従来の設計どおりH1新規バーの最初のtickで次を行います。Entry用の30秒周期を待ちません。

1. brokerポジションを再取得する
2. MN1、W1、D1、H4、H1を分析する
3. Tradeが`OPEN`かつ`INITIAL_RESTORE`中でなければ、確定H1 ZigZagによるトレイル候補を評価する。`OPEN_PARTIAL`では初期SLと残注文の終端確認を優先する
4. 分析失敗を含むトレイル評価、採用候補および基準点をDBへ保存する
5. 採用候補をpendingへ登録し、broker SLへの反映を試みる
6. 候補跨ぎによる決済を開始した場合は、そのH1バーのエントリーを禁止する

`INITIAL_RESTORE`がpendingの間は新しいトレイル候補を評価せず、`INITIAL_STOP_LOSS_RESTORE_PENDING`として見送ります。初期SLの復元または候補跨ぎ決済を先に完了します。

トレイル評価はTrade Eventへ保存し、分析失敗、Wave不足またはポイント不足も`WAVE_UNAVAILABLE`、`POINTS_UNAVAILABLE`などの見送り理由として記録します。トレイル分析の成功・失敗でEntryバーを処理済みにしません。

#### 6.3.2 Entry処理

LIVEは6.2のタイマー周期、Testerは売買開始日時以降のtickで次を行います。

Testerの売買開始前は`strategy.prepareHistory()`で履歴本数・同期の準備確認だけをH1バーごとに1回実行し、Entryとは別の`lastWarmupBar`で管理します。Entry用の完全な波動分析、Judge評価、`entryState.observe()`・`finalize()`、Judge回数の加算・初回消費、Decisionと新規Entry Tradeの保存、新規注文は行いません。開始前のバーを`ANALYSIS_UNAVAILABLE`のSKIPとして後から保存することもありません。Run・heartbeatと既存ポジションの保護処理は継続し、保護に必要なトレイル分析は別処理として維持します。開始後の最初のtickではウォームアップ期間のEntry処理済み状態・回数を持ち込まず、同じH1バー内で開始日時に到達した場合も、準備済みの履歴から通常の完全な分析・評価を新たに実行します。

1. 現在のH1バーがDBへ確定保存済み、またはメモリに確定判定を保持して保存待ちなら再評価・再加算しない。保存待ちの場合は保持済み結果の保存だけを再試行する
2. 同じ分析Profile・履歴準備条件でMN1からH1を分析する。失敗時はJudge回数を加算せず、同じバーの次の実行で再試行する
3. 分析成功時は、保有・発注可否に関係なく共通Judgeを1回評価する
4. Judge成立なら同一シグナルの回数を加算し、初回だけH1・H4の詳細Entry条件を評価する
5. 戦略Entry成立時だけ、保有数・SL・DBなどの発注安全条件を確認する
6. BUY、SELLまたはSKIP、戦略判定、Judge回数および初回消費をDBへ確定保存する。発注可能なら`OPEN_PENDING`と要求Eventも同一transactionへ含める
7. commit成功後、`OrderCheck()`を通過した注文だけ送信し、受付結果を保存する

分析成功後のJudge NG・Entry NG・発注安全条件NGは、そのH1バーの確定結果です。同じバーで条件が改善しても再判定しません。分析準備中の試行失敗は運用ログへ記録し、確定Decisionを先に作って再試行を妨げないようにします。成功しないまま次のバーへ進んだ場合は、前バーを`ANALYSIS_UNAVAILABLE`のSKIP（回数0・未消費）で確定し、過去バーの分析・発注は再試行しません。

DB保存失敗時は発注せず、その時点の判定・回数をメモリへ保持して保存を再試行します。復旧後に過去のEntryを遅延発注せず、未送信Entryを`DB_UNAVAILABLE`のSKIPへ変更し、Judge結果に応じた回数・消費を保存します。Judge NGまで消費済みにはしません。メモリも失われて未保存回数を復元できない場合は、未消費と推測して再発注せず、整合確認が必要な状態として扱います。

### 6.4 取引イベント

`OnTradeTransaction()`の`TRADE_TRANSACTION_DEAL_ADD`を、実際の約定を保存する正本とします。

- 新規の部分約定は`OPEN_PARTIAL`、全量成立は`OPEN`へ更新する
- SL、EA決済、手動決済および外部決済を同じ経路で検出する
- 決済dealを`POSITION_IDENTIFIER`へ関連付ける
- 取引要求、SL変更要求・結果および各dealを取引Eventとして追記する
- ポジション消滅確認後に履歴を集計して`CLOSED`へ更新する
- 同じdeal通知を再受信しても重複保存しない

`OrderSend()`の戻り値だけでポジション成立、SL変更反映または決済完了とは判断しません。SL変更後は対象Positionを読み直し、候補以上に保護されたことを確認します。

### 6.5 終了処理

`OnDeinit()`では、保存待ちデータの保存を試み、Runを終了状態へ更新し、実行Leaseと排他Lockを解放してリソースを破棄します。保有ポジションを自動決済しません。DB更新に失敗した場合はテキスト運用ログへ記録し、次回起動時にbroker由来の注文・deal・Positionを復旧します。DB障害中のSKIP判定はbroker履歴から復元できません。

## 7. 取引状態

```text
FLAT
  └─ OPEN_PENDING
       ├─ OPEN_FAILED ──> FLAT
       ├─ OPEN_PARTIAL
       │    ├─ OPEN
       │    └─ CLOSE_PENDING
       └─ OPEN
            ├─ [TRAIL_MONITORING / TRAIL_PENDING]
            ├─ broker SL約定 ──> CLOSED ──> FLAT
            └─ 候補跨ぎ ──> CLOSE_PENDING
                 ├─ CLOSE_PARTIAL ──> CLOSE_PENDING
                 ├─ OPEN
                 └─ CLOSED ──> FLAT

不整合検出 ──> RECOVERY_REQUIRED ──> OPEN / CLOSED
```

- `OPEN_PENDING`は注文要求をDBへ保存済みで、ポジション成立を確認していない状態です。
- `OPEN_PARTIAL`は一部約定済みで、残注文または未成立数量がある状態です。
- `[TRAIL_MONITORING / TRAIL_PENDING]`はDBの取引`status`ではなく、`OPEN`中の内部管理状態です。
- `TRAIL_PENDING`は候補をDBへ保存済みで、broker SLへの反映を確認していない状態です。SL変更だけでは`CLOSE_PENDING`へ移行しません。
- `CLOSE_PENDING`は決済要求済みで、同じ`POSITION_IDENTIFIER`の消滅を確認していない状態です。
- `CLOSE_PARTIAL`は一部決済後も同じPositionが残っている状態です。
- `RECOVERY_REQUIRED`では新規注文、SL変更および成行決済を停止し、brokerとの照合だけを行います。brokerへ設定済みのSLは継続します。照合で状態を一意に確定し、必要なら初期SL・適用済みトレイルSLから構造上有効なpendingを再構成して、Tradeを`OPEN`へ戻したtransactionのcommit後にだけ送信を再開します。

## 8. エントリー判定

### 8.1 分析時間足

H1単独ではなく、既存`ZigZagElliot`と同じMN1 → W1 → D1 → H4 → H1の親子関係で分析します。`ZigZagElliotAnalysisProfile`を共通の正本とし、`OscillatorHandlePool.setTimeframesFromMn1To()`と`ElliotAll.setAnalysisStartTimeFrame(PERIOD_MN1)`を使用します。D1開始へ短縮すると親Waveに依存するH1・H4の波動判定も変わるため、短縮しません。

Stochastic方向とGMMAは既存H1戦略と同じくshift 0を使用し、判定時点の進行中H1および上位足を含みます。確定足のshift 1へ置換しません。履歴準備条件も既存Controllerに合わせ、分析不能と戦略条件NGを区別します。

### 8.2 BUY条件

既存の`AbstractExpertAdvisor.analyze()`と同じく、次の順で評価します。全条件を一括で評価してから回数を加算する方式にはしません。

まず、共通Judgeでは次を要求します。

1. MN1、W1、D1、H4、H1の分析に成功し、参照値が有効
2. Spreadが5.0 pips以下
3. H1のStochastic多数決方向がBUY
4. H1最新Wave方向が上昇
5. W1、D1、H4、H1のStochastic多数決方向がすべてBUY
6. MN1のStochastic多数決方向がBUY、またはW1 EMA200方向がBUY
7. H1 GMMA trend countが`+2`以上
8. H1 GMMA cross countが`+2`以上
9. H1とH4のEMA200方向がともにBUY

W1 EMA200の`NONE`は有効な診断状態ですが、方向一致の代替条件は満たしません。この場合でもMN1がBUYなら6を満たします。MN1やW1 EMA200の取得不能・不正値は、既存の`H1DirectionAlignmentDecision`と同じく通過させません。別項目のW1追加確認は`OBSERVE_ONLY`であり、主条件に加えてOR/ANDゲートを追加しません。

Judge成立時にシグナル回数を加算し、回数が`1`の場合だけH1とH4が第1波、第3波、または有効な第5波かを確認します。通過した場合を戦略上のBUY Entryとします。

実際の発注では、自EAポジション・pending新規注文・同一バー決済後の発注禁止がないこと、有効な初期SL、`InpMaxInitialStopLossPips`以下の初期SL幅および9章の安全条件を追加確認します。安全条件NGでも初回Judgeの消費は取り消しません。

### 8.3 SELL条件

BUY条件の方向と符号を反転します。

- W1、D1、H4、H1の方向がすべてSELL
- MN1方向がSELL、またはW1 EMA200方向がSELL
- H1最新Wave方向が下降
- H1 GMMA trend countが`-2`以下
- H1 GMMA cross countが`-2`以下
- H1とH4のEMA200方向がSELL

### 8.4 Elliott波動条件

H1とH4はそれぞれ次のいずれかを要求します。

- 第1波
- 第3波
- 第5波かつ、同じ推進Waveの第3波に副次波番号・副次波ラベルがない

第5波は、同じ推進Wave内の数字の第3波が存在し、その第3波に副次波番号および副次波ラベルが設定されていない場合に許可します。第3波の値幅や時間を使った短さの判定は行いません。最新ZigZagポイントの確定・未確定はエントリー条件に使用しません。保有後のH1 ZigZagトレイルでは、別途11.2の確定ポイント条件を使用します。

### 8.5 使用しない判定値

初版では次をエントリー条件に使用しません。H1 ZigZagトレイルに必要なポイント情報はこの一覧の対象外です。

- MN1 EMA200
- D1 EMA200
- H1またはH4のEMA200距離
- H1構造ランク
- 通貨強弱
- ZigZag最新点の確定状態

### 8.6 シグナル識別と消費

シグナルは、既存`SignalCount`と同じくH1の2番目に新しいZigZagポイント時刻と売買方向で識別します。DBの消費一意キーは`context_key + signal_reference_time + signal_side`です。現在のH1バー時刻やLIVEのRun IDを含めません。別途、Alert DBとの比較用に、接続サーバー、シンボル、時間足、H1バー時刻、シグナル基準時刻、戦略および方向から`market_signal_key`を生成します。比較用キーを消費の一意判定へ流用しません。

消費順序は次に固定します。

1. 分析失敗またはJudge NGなら回数を加算しない
2. Judge成立なら同じキーの回数を加算する。初回成立時点でEntryの機会を消費する
3. 回数`1`のみH1・H4波動の詳細Entry判定へ進む。回数`2`以上はEntryを評価しない
4. 初回でも波動NG・保有中・SL不正などなら、消費済みSKIPとして保存する。Trade行は作らない
5. 初回かつ発注可能なら、消費済みDecision、`OPEN_PENDING`および要求Eventを同一transactionで保存してから送信する

途中でJudgeがOFFになっても回数をリセットしません。同じ基準時刻でもBUYとSELLは別キーです。2回目以降のJudge成立も回数へ記録しますが、`is_signal_consumed = 1`を付けるのは初回のDecisionだけです。初回の波動NGが後のバーでOKになっても、同じシグナルでは入りません。brokerの拒否後も再送しません。

判定結果は、Judge成立・回数・詳細Entry評価有無・戦略Entry可否と、実際の発注可否を分離して保存します。初回消費は発注の有無にかかわらずDBへ保存し、再起動後も復元します。

### 8.7 既存との一致範囲

同じシンボル・履歴・分析Profile・設定・評価時点・Judge回数を入力した場合に、既存H1判定と戦略Entry可否・対象H1バーが一致することを目標とします。LIVEのタイマーは別々に起動すると実行時刻がずれ、shift 0の値も変わり得るため、秒単位の同時発注や同じ約定価格までは保証しません。受入検証では同じ分析スナップショットの時系列を使用します。

既存インジケータは再初期化でメモリの回数が消えますが、本EAは保存済み消費を引き継ぎます。再起動後の重複防止とSL・保有数・DB等の発注安全条件は、意図して残す追加仕様です。安全条件で見送った候補を後から発注して、既存にない遅延Entryを作りません。

## 9. 発注仕様

### 9.1 注文前検証

注文前に次を確認します。

- ロットがbrokerの最小値、最大値およびstepへ正規化できる
- 取引可能状態である
- 同一シンボル、同一Magic Numberのポジションがない
- 同一コンテキストの`OPEN_PENDING`がない
- 口座がヘッジ方式である
- 初期SLが有効
- 初期SL幅が`InpMaxInitialStopLossPips`以下
- 注文直前も今回Runが実行Leaseを保持している
- `OrderCheck()`が成功する

いずれかに失敗した場合は注文せず、判定理由または発注失敗理由をDBと運用ログへ保存します。

この見送りによってJudge回数を戻したり、同じシグナルの次回発注を予約したりしません。

commit前の安全条件NGはSKIP Decisionとして保存します。commit後の`OrderCheck()`失敗は保存済みBUY/SELL Decisionを上書きせず、Tradeを`OPEN_FAILED`へ更新して理由をEventへ保存します。

### 9.2 成行注文

- 固定ロット
- 成行注文
- broker対応のfilling mode
- 許容deviationは10 points
- 固定TPなし
- 注文コメントはEA名と戦略バージョンを識別できる短い値

`DONE_PARTIAL`または`PLACED`を受け取っても即座に`OPEN`とはせず、`OnTradeTransaction()`とbrokerポジションで成立を確認します。

新規注文が部分約定した場合は、未約定の残注文を取消要求し、同じシグナルで不足数量を再発注しません。残注文が有効な間は`OPEN_PARTIAL`、残注文が終端となりPosition数量が正なら、その実数量を採用して`OPEN`へ移行します。残注文の終端後にPositionがなければ`OPEN_FAILED`とします。

残注文の取消中でも、約定済みPositionの初期SLが消失・緩和されていれば保護を放置しません。`OPEN_PARTIAL`では例外的に`INITIAL_RESTORE`だけを保持・処理でき、初期SLの復元または跨ぎ決済を行います。新しいトレイル候補と`TRAIL_RESTORE`は許可しません。

### 9.3 初期ストップロス

H1のシグナル基準ZigZagポイントから10.0 pipsを損失側へ離します。

```text
BUY  : 基準の谷 - 10.0 pips
SELL : 基準の山 + 10.0 pips
```

次の場合は発注しません。

- 基準点、pip sizeまたは価格を取得できない
- SLが0以下
- BUYでSLが現在価格以上
- SELLでSLが現在価格以下
- 建値からSLまでの幅が`InpMaxInitialStopLossPips`を超える
- brokerの`SYMBOL_TRADE_STOPS_LEVEL`を満たさない
- 最小価格刻みに正しく丸められない

SLなしの注文は許可しません。TPは設定しません。

初期SLとH1 ZigZagトレイルは、どちらもZigZag基準点から損失側へ10.0 pips離します。初版では10.0 pipsを内部固定値とし、inputでは変更できません。トレイル開始後も、有効なbroker SLが存在することを必須とします。

## 10. ポジション管理範囲

初版は`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`の口座だけを対象とします。ネッティング口座では手動・他EAのdealが同じPositionへ混在し得るため、初期化を拒否します。

管理対象は同一接続サーバー、口座、シンボルおよびMagic Numberのポジションです。ポジションの安定識別には`POSITION_IDENTIFIER`と`DEAL_POSITION_ID`を使用し、変化し得るPosition Ticketだけに依存しません。

初版で正常に扱う自EAポジションは1件です。複数検出時は異常として新規エントリーを停止し、自動で統合・一括決済せず運用ログへ記録します。各ポジションにbroker SLが存在することを確認します。

保有中はpending保護SL候補を最大1件管理します。種別は、新しいH1 ZigZag候補の`TRAIL_CANDIDATE`、初期SL復元の`INITIAL_RESTORE`、最後に適用済みのトレイルSL復元の`TRAIL_RESTORE`です。`INITIAL_RESTORE`中は新しいトレイル候補を評価しません。それ以外は、新しい候補が現在broker SLより保護側であり、かつpendingがある場合はそのpendingよりも1tick以上保護側の場合だけ置き換え、SLを損失側へ戻しません。

## 11. 決済仕様

### 11.1 brokerストップロス

初期SLは注文と同時にbrokerへ設定します。EA停止中も有効な最低限の損失制限です。Position成立後は、確定H1 ZigZagの進行に応じて同じbroker SLを保護側へ更新します。初期SLまたは更新後SLの約定は`OnTradeTransaction()`から取得します。

### 11.2 H1 ZigZagトレイル候補

新しいH1バーでTradeが`OPEN`の場合、H1 Elliott分析の最新Waveから最新点と1つ前の点を取得します。最新点は1つ前の点が確定したことの確認にだけ使用し、実際のSL基準には1つ前の点を使用します。`OPEN_PARTIAL`ではトレイルを開始しません。

次をすべて満たす場合だけ候補を作成します。

- Position開始時刻、建値および現在SLが有効
- 固定余白10.0 pips、pip sizeおよびtick sizeが有効
- H1の最新Waveを取得できる
- 最新点と1つ前の点の価格および時刻が有効
- 両ポイントが`isAddedPoint = false`
- 両ポイントが確定H1上にあり、`barIndex >= 1`
- 1つ前の点が最新点より古い
- 1つ前の点がPosition開始時刻より後
- BUYは「1つ前が谷、最新が山」
- SELLは「1つ前が山、最新が谷」
- 丸め後の候補SLが0より大きい

候補SLは次のとおりです。

```text
BUY  : 1つ前の谷 - 10.0 pips
SELL : 1つ前の山 + 10.0 pips
```

BUYはbrokerの最小価格刻みへ下方向、SELLは上方向へ丸めます。候補が建値より損失側に残っていても、現在SLより1tick以上保護側なら採用します。`INITIAL_RESTORE`中はこの評価へ進みません。それ以外のpendingがある場合は、その候補よりも1tick以上保護側であることも要求します。条件を満たさない候補は見送り、SLを損失側へ戻しません。

反対GMMA、W1、D1・H4方向、EMA200、ElliottラベルおよびSpreadは決済条件に使用しません。GMMAはエントリー条件にだけ使用します。

### 11.3 pending保護SL候補とSL変更

この節の採用フローと手順1は、新しい`TRAIL_CANDIDATE`だけを対象とします。`TRAIL_EVALUATION`自体はH1バーごとの採用または見送りを保存するため、`INITIAL_RESTORE`中も`INITIAL_STOP_LOSS_RESTORE_PENDING`の見送りEventを作成できます。採用候補は、基準点、確認点および評価H1バーとともにDBへ保存してからSL変更を開始します。`INITIAL_RESTORE`と`TRAIL_RESTORE`の登録は11.4のbroker整合処理で、Recovery EventとTrade更新を同一transactionへ保存してから、手順2以降と同じ再試行処理へ渡します。復元登録そのものを`TRAIL_EVALUATION`として保存しません。

1. pending候補とトレイル評価Eventをtransactionで保存する
2. 現在のPosition Ticket、現在SL、BidまたはAskを再取得する
3. broker SLが候補以上に保護済みなら、実SLと設定元を保存し、SL変更を送信せずpendingを解除する
4. BUYのBidまたはSELLのAskが候補を跨いでいれば、候補跨ぎ決済へ移行する
5. Stops/Freeze距離を満たさなければ、送信せずpendingを維持する
6. 有効Leaseの確認とSL変更要求Eventを同一transactionで保存する
7. 対象Position Ticketを明示してSLTP変更を送信する
8. Positionを再取得し、候補以上に保護されたことを確認する
9. broker再確認結果に応じてSL変更結果とTrade状態を保存する

候補が`SYMBOL_TRADE_STOPS_LEVEL`と`SYMBOL_TRADE_FREEZE_LEVEL`の大きい方に1tickを加えた距離を満たさない場合、またはSL変更に失敗した場合はpendingを維持します。毎ティック確認し、実際の再送は最短1秒間隔とします。pendingが`TRAIL_CANDIDATE`または`TRAIL_RESTORE`の場合だけ、より保護的な新規トレイル候補で置き換えられます。`INITIAL_RESTORE`は置き換えません。

この節の`TRAIL_CANDIDATE`について、SL反映前にBUYのBidが候補以下、またはSELLのAskが候補以上になった場合、SLを過去価格へ設定できないため、`H1_ZIGZAG_TRAIL_CROSSED`で全量成行決済を開始します。復元候補のcross理由は11.4に従います。Spread超過はSL変更およびこのリスク低減決済を妨げません。

broker SLが候補以上に保護されたかは、BUYでは`broker SL >= 候補 - 0.5 tick`、SELLでは`broker SL <= 候補 + 0.5 tick`で確認します。より保護的なSLで候補を満たした場合も、broker実SLを保存してpendingを解除しますが、自EAのSL変更要求と対応付けられなければ`H1_ZIGZAG_TRAIL`とは記録しません。broker transactionや取得済みの変更元情報から手動・他EAを積極的に確認できた場合だけ`EXTERNAL`、自EAの未保存actionを含め由来を証明できない場合は`UNKNOWN`とします。

自EAの変更actionとbroker SLが一致し、pending種別が`TRAIL_CANDIDATE`または`TRAIL_RESTORE`の場合だけ適用済みトレイル候補を更新します。`INITIAL_RESTORE`の成功は設定元を`INITIAL_STOP_LOSS`へ戻します。より保護的な外部・由来不明SLの場合は適用済み候補を変更せずpendingだけを解除します。変更失敗または未反映を確認できた場合は、「SLあり」と「SLなし」を区別できるbroker確認結果をResult Eventへ保存してpendingを維持します。broker Positionまたは実SLの有無を取得できず結果を断定できない場合はResult Eventを作らず、未完了actionを保持して`RECOVERY_REQUIRED`へ移行します。

TIMEOUT・接続断・受付中など応答が未確定の場合、直後に旧SLまたはSLなしを正常取得しても「要求が終端した」証明にはしません。実SLと要求値が0.5 tick以内で一致する、または今回要求へ対応する終端応答を確認するまでactionを保持し、新しい候補・再送を禁止します。より保護的な外部SLを見つけたことだけでも未完了要求は解除しません。遅れて到着した古いSL要求が、次の保護水準を緩める競合を防ぎます。

通常経路はDBへの要求Event commit後にSL変更または成行決済を送信します。DB障害中だけ、排他Lockと未失効Leaseを条件に、意図とEventをメモリキューおよび運用ログへ記録してリスク低減操作を許可します。未保存情報は再起動で失われる可能性があります。

### 11.4 broker SLとの整合

broker SLがEAの保存済み保護水準より保護側にある場合は、手動または外部設定を尊重し、EAから緩めません。broker SLが削除または緩和された場合は、未完了SL actionを先に照合し、初期SL、最後に自EAが適用したトレイルSLおよび有効なpending候補のうち最も保護側の水準を復元対象とします。初期SLなら`INITIAL_RESTORE`、適用済みトレイルSLなら`TRAIL_RESTORE`、既存pending自身ならその種別のまま、Controllerのbroker整合処理からpendingへ設定します。初期SL復元には架空のZigZag情報を設定しません。新しいZigZag候補として再判定せず、復元前に価格が水準を跨いでいれば`INITIAL_RESTORE`は`INITIAL_STOP_LOSS_CROSSED`、トレイル由来の2種は`H1_ZIGZAG_TRAIL_CROSSED`で全量成行決済へ移行します。

broker SLの価格だけから基準ZigZag点や設定元を推測しません。`EXTERNAL`はbroker transactionまたは保存済み変更元情報から手動・他EAを積極的に確認できた場合だけ使用し、自EA actionとの不一致や要求履歴の欠落だけでは外部と断定しません。由来を証明できない場合は`UNKNOWN`として保存します。H1分析に失敗した場合は新しい候補を作成せず、既存のbroker SLと復元済みpending候補を維持します。

### 11.5 決済確認と理由

broker SL約定では明示的な成行決済要求がないため、Position消滅とdealを確認した後、`OPEN`から直接`CLOSED`へ更新できます。候補跨ぎ成行決済では、Lease所有確認、`CLOSE_PENDING`、pending種別に対応するcross理由、決済要求Eventおよびpending候補の解除を同一transactionで保存してから送信します。候補情報は決済要求Eventへ残します。`CLOSE_PENDING`または`CLOSE_PARTIAL`ではトレイル評価とSL変更を行いません。

候補跨ぎ成行決済が部分約定となった場合は`CLOSE_PARTIAL`として残存数量と有効注文を確認します。有効な決済注文がなければ、最短1秒間隔で残存全量の成行決済を再試行します。Positionが消滅するまで同じ内部決済理由を維持します。

決済理由はEA側の分類とbroker事実を分けて保存します。

| 状況 | EA側の決済分類 | broker理由 |
|---|---|---|
| 初期SL約定 | `INITIAL_STOP_LOSS` | `SL` |
| 初期SL復元前の水準跨ぎ | `INITIAL_STOP_LOSS_CROSSED` | 通常`EXPERT` |
| H1 ZigZagトレイルSL約定 | `H1_ZIGZAG_TRAIL` | `SL` |
| 外部設定SL約定 | `EXTERNAL_STOP_LOSS` | `SL` |
| 由来不明SL約定 | `UNKNOWN_STOP_LOSS` | `SL` |
| 候補跨ぎ成行決済 | `H1_ZIGZAG_TRAIL_CROSSED` | 通常`EXPERT` |

候補跨ぎ決済を開始したH1バーでは、同じバー内で完了しても新規エントリーしません。初版は同一バーのドテンを禁止します。

## 12. SQLite永続化

### 12.1 DBファイル

LIVEではCommonフォルダの次の専用DBを使用します。

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-h1-ea.sqlite
```

既存の`mstng-zigzag-elliot-alert.sqlite`、`mstng-currency-strength.sqlite`とは分離します。年別、通貨別には分割せず、全チャートが同じ取引DBを使用します。

### 12.2 保存対象

```text
h1_ea_runs (1)
  └─ h1_ea_decisions (N)
       └─ h1_ea_trades (0..1)
            └─ h1_ea_trade_events (N)
```

- `h1_ea_runs`：EA起動、環境、設定およびバージョン
- `h1_ea_decisions`：H1バーごとのBUY、SELLまたはSKIP、Judge回数・消費、戦略Entry可否と条件スナップショット
- `h1_ea_trades`：発注から決済までの取引状態、現在SL、pending保護SL候補および確定損益
- `h1_ea_trade_events`：取引要求、トレイル評価、SL変更、部分約定、決済および回復履歴

取引CSVと決済専用CSVは作成しません。決済専用一覧は`h1_ea_trades.status = 'CLOSED'`の検索で取得します。

### 12.3 接続設定

- `DATABASE_OPEN_COMMON`
- `PRAGMA foreign_keys = ON`
- `PRAGMA journal_mode = WAL`
- `PRAGMA busy_timeout = 5000`
- 起動時に設定結果を読み戻して確認
- 1イベント単位の短いトランザクション
- 通常tick中にDDLまたは長い集計を実行しない

### 12.4 DB障害時の原則

```text
新規OPEN : fail-closedで停止
SL変更・既存CLOSE : 排他Lock保持中かつ既知Leaseの安全期限内だけ継続
broker SL : DB・Lease状態にかかわらず継続
```

- 注文前の判定または`OPEN_PENDING`を保存できなければ発注しない
- 保有中の一時的なDB障害では、排他Lockと未失効Leaseを確認できる間だけH1 ZigZag SL変更と候補跨ぎ決済を継続する
- 保存失敗した取引Eventは同一プロセス内のメモリへ一時保持し、再接続後にFIFOで再保存する
- brokerのposition、orderおよびdealに存在する事実だけを正本として冪等に補完する
- メモリ上限到達時は新規注文を停止し、保存できないEventを運用ログへ明示する
- DB障害中のSKIP判定や内部状態は再起動後に完全復元できるとは扱わない
- 最後に確認したLeaseが失効した後はEAから取引操作せず、broker SLだけを残す
- DBを自動削除または空DBへ置換しない
- Viewerの停止や障害はEA動作へ影響させない

### 12.5 約定明細の保存確認と再試行（EA 1.04）

取引全体の`CLOSED`・損益と、個々の`DEAL_ADD`の保存完了は別に確認します。Entry条件・初期SL・H1 ZigZagトレイル・決済の送信条件・DBスキーマは変更しません。

- Positionの履歴ticketを全件退避してから各約定を再選択し、bool版getterで取得成否を確認する。取得済みスナップショットだけで集計とEvent作成を行い、保存途中の履歴選択変更に依存しない。
- 取得失敗・必須値の欠損・Positionや通貨の不一致は、ticket・項目・エラーコードを運用ログへ残す。0値を約定事実として保存せず、再照合を続ける。
- 決済が確認できた場合は`CLOSED`と`last_error='DEAL_EVENTS_PENDING'`を先に保存し、その後に全約定Eventを保存する。保存または既存FIFOへの受理がすべて成功した後、後続の完了スナップショットで印を解除する。キューが残る間は保存完了とは扱わない。
- 起動時は現contextの全CLOSEDを一度走査し、メモリにしか残っていなかった中間約定も履歴から再確認する。active取引も初回は全履歴を再集計する。その後の通常照合では上記の印またはEntry／Exit ticketのEvent欠落を検索する。候補は全broker約定、Entry／Exit ticket、Entry／Exit数量と既存の約定数量を照合し、全件追記成功後にだけ監査待ちを解除する。
- 遅延した中間の部分約定も、通知ticketを最大256件のメモリキューへ保持し、`context_key + position_identifier`で元CLOSEDへ追記する。履歴やDBの一時的な取得失敗ではキューから削除せず、通常は最短1秒間隔で再試行する。
- 過去CLOSEDへの追記はEventだけを保存し、現在保有中のTradeや過去Tradeの損益・SL・状態を上書きしない。同じ`deal_scope_key`／`event_uid`は二重登録しない。
- 明細の再確認待ち・未保存・キュー上限超過中は新規Entryを停止する。既存の保護処理は従来の権限条件に従うが、後発Runによる所有権喪失を確認した場合は権限を解除する。監査の再試行で決済注文を再送しない。
- 終了時にも注文を送らない最終照合を行い、明細未確認が残ればRunを`FAILED`・`DEAL_AUDIT_PENDING`として記録する。未保存FIFOの喪失は従来どおり`AUDIT_STATE_LOST`で区別する。

Testerのcontextと約定一意キーはRun固有です。新しいテストの履歴を使って古いRun 5を自動補完しません。LIVE再起動時の補完は同contextのbroker履歴を取得できることが前提です。起動時の全件確認は1回の照合呼出しにつきCLOSED一件ずつ進め、完了するまで新規Entryを停止します。過去履歴が提供されない場合は、値を推測して完了扱いにせずログに残して待機します。

## 13. 再起動時の整合

起動時はDBだけを信用せず、brokerの現在ポジション、注文およびdeal履歴と照合します。

Entry回数の正本はDecisionです。Tradeがない消費済みSKIPも復元対象とし、注文履歴の有無から未消費と判断しません。DB未保存の回数はbroker履歴から推測しません。

| DB状態 | broker状態 | 動作 |
|---|---|---|
| active取引あり | 同じPositionあり | 不足情報を補完して管理継続 |
| `OPEN_PENDING` | Positionなし | 現在・履歴orderとdealを確認。orderが終端かつdealなしの場合だけ`OPEN_FAILED` |
| `CLOSE_PENDING`・`CLOSE_PARTIAL` | Positionなし | 決済履歴を集計して`CLOSED` |
| `CLOSE_PENDING`・`CLOSE_PARTIAL` | 同じPositionあり | 有効な決済注文を確認し、終端済みで残Positionがあれば再決済 |
| `OPEN`またはpendingあり | Positionなし、決済dealあり | 決済履歴を集計し、pendingを解除して`CLOSED` |
| `OPEN`＋pending保護SLあり | 同じPosition、broker SLが候補以上に保護側 | 実SLを保存してpending解除。自EA要求と一致するトレイル種別だけ適用済みへ更新し、外部・不明なら`EXTERNAL`または`UNKNOWN` |
| `OPEN`＋pending保護SLあり | 同じPosition、broker SLが候補未達 | 種別を含めてpendingを復元し、Lease確認後に再試行 |
| `OPEN`＋pending保護SLあり | 同じPosition、broker SLが削除・緩和 | 初期SL・適用済みSL・pendingの最も保護側を適切な復元種別で保持し、価格通過済みなら種別対応の理由で決済開始 |
| `OPEN`＋pending保護SLあり | 同じPosition、価格が候補を通過済み | 初期SL復元は`INITIAL_STOP_LOSS_CROSSED`、トレイル由来は`H1_ZIGZAG_TRAIL_CROSSED`で決済開始 |
| pending保護SLあり | Position識別子・方向が不一致 | stale候補を送信せず、断定不能ならpendingを保持して`RECOVERY_REQUIRED` |
| pending保護SLが構造不正 | 種別と必須項目の組合せ不正、価格単位不正または複数候補 | 生の値をRecovery Eventへ隔離し、構造化pendingを全NULLにして`RECOVERY_REQUIRED`。broker照合以外の送信を停止 |
| active取引あり | Position・履歴なし | `RECOVERY_REQUIRED`、broker照合以外の送信を停止 |
| active取引なし | 自EA Positionあり | 回復用取引行を作成して管理継続 |
| 任意 | 自EA Positionが複数 | 異常状態、新規注文停止 |

同一コンテキストの前回Runが`RUNNING`でも、有効なLeaseがある場合は変更せず二重起動として拒否します。Leaseが期限切れの場合だけ前回Runを`INTERRUPTED`へ更新して引き継ぎます。

## 14. 運用ログ

DBとは別に、障害調査用テキストログをCommonフォルダへ保存します。

```text
MstngH1Ea\Logs\MstngH1Ea_<server>_<login>_<symbol>_<magic>.log
```

最低限、次を記録します。

- 初期化、終了および制限状態
- H1判定結果と理由コード
- OrderCheck、発注、約定および決済結果
- H1トレイル評価、基準点、候補SLおよび見送り理由
- Stops/Freeze待ち、SL変更要求・結果および候補跨ぎ決済
- DB接続、transaction、再試行および復旧結果
- brokerとDBの不整合

DB自身の接続障害を記録できるよう、運用ログはSQLiteへ統合しません。

## 15. Strategy Tester

| 項目 | LIVE | Strategy Tester |
|---|---|---|
| DB | `mstng-h1-ea.sqlite` | `mstng-h1-ea-tester.sqlite` |
| `source_mode` | `LIVE` | `TESTER` |
| 保存先 | Common | Common |
| 最適化 | 通常運用 | 初版は非対応。初期化を拒否 |
| 同一シグナル管理 | DB＋メモリ | 単独RunだけDB＋メモリ |
| Entry分析 | 初回タイマー、以後30秒周期 | 未処理H1バーをtickで確認 |
| 売買開始日時 | 無効（有効値0） | `InpTesterTradeStartTime`。既定2026.01.01 00:00、0なら制限なし |

LIVEとTesterのデータを同じ物理ファイルへ混在させません。DB名は初版では固定し、inputへ公開しません。`MQLInfoInteger(MQL_OPTIMIZATION)`がtrueの場合は、DB必須の状態遷移を省略せず初期化を拒否します。将来最適化へ対応する場合は、同じRepository契約を持つ別実装を設計します。

「始値のみ」で下位足を参照しません。MN1、W1、D1、H4、H1を使用しますが、shift 0の判定結果はTesterのモデルとtick生成方法に依存します。履歴準備は既存Controllerと同じく、MN1は61本以上、W1からH1は各206本以上および各seriesの同期を確認します。TesterのEntry分析失敗時は、同じH1バー内では`TimeCurrent()`で最短1秒後のtickから再試行します。新しいH1バーでは待機を持ち越さず最初のtickで試行し、分析成功後のJudge NG・Entry NGを再試行対象にしません。LIVEの初回1秒・以後30秒周期は変更しません。pending保護SLの反映可否、候補跨ぎおよび最短1秒の再試行は生成tickに依存するため、「始値のみ」と実tickでは決済価格や決済時刻が異なる可能性があります。

EA 1.05ではEMA200の`copyEmaValues()`で`BarsCalculated()`を取得前の中断条件にせず、先に`CopyBuffer()`で計算・値の取得を要求します。必要本数を完全取得でき、全要素が有限値かつ`EMPTY_VALUE`でない場合だけ成功とします。非ビジュアルTesterの要求時計算に対応する変更であり、取得失敗を成功扱いにするものではありません。EMAの期間・参照shift・売買条件は変更しません。

H1 EAのTester分析中だけ、内部Loggerの同一INFO/ERROR（レベル・銘柄・時間足・メソッド・本文の完全一致）を同じH1内で抑制します。初回・異なる内容は出力し、H1切替または分析成功後に抑制履歴を解除します。抑制の履歴は固定上限を持ち、分析区間外のログやLIVEには適用しません。MT5自身のログや直接`Print()`するログは対象外です。Entry分析の再試行制限は、tick側の照合・pending保護SL・トレイル評価の周期を変えません。分析失敗後の復帰タイミングだけは待機と次のtickに依存するため、売買結果の一致は再テストで確認します。

履歴不足時は、時間足別の取得本数・必要本数・同期状態・最古日時をINFOログへ出します。初回に出力し、以降の状態変化通知は最短1時間間隔、状態不変の再通知は24時間間隔に抑制します。準備だけが整った時は`HISTORY_READY`、通常の完全分析を再開できた時は`ANALYSIS_READY`を1回INFOで出し、両者を区別します。不足系列への履歴再取得要求は最短60秒間隔です。売買開始日時へ到達しても61本／206本の条件は緩和せず、準備できるまで分析を再試行します。

### 15.1 2026年から売買を確認する設定例

1. Strategy TesterのEAを`MstngH1Ea`、時間足をH1、テスト期間の開始日を`2021.01.01`にする。これはウォームアップを含む実行開始日です。
2. EAの「テスター設定」で`InpTesterTradeStartTime = 2026.01.01 00:00`を指定する。こちらが新規売買の評価を始める日時です。
3. 最適化をOFFにし、SL管理の確認にはティックを含むモデルを使用してテストを実行する。
4. 2026年より前もRun・heartbeatと履歴準備ログは継続し、新規EntryのDecision／Tradeがないことを確認する。2026年以降の最初のtickから、履歴準備を満たした場合に通常のJudge・Entry評価が始まることを確認する。

2021年から実行しても、broker側に必要な履歴がなければ準備完了を保証しません。ログでMN1の61本以上、W1・D1・H4・H1の各206本以上と同期を確認してください。

テスターの表示期間にはウォームアップ期間も含まれます。2026年の売買成績は取引日時で区切って確認し、通常版と比較する場合は履歴をそろえるためテスターの実行開始日も合わせてください。

### 15.2 安全時だけの高速ウォームアップ（EA 1.03）

追加inputは設けず、Testerの売買開始日時より前で、DB・Lease・排他Lockが正常、取引照合が完了した空状態の場合だけ高速化します。他銘柄分を含む口座内のポジション・注文がなく、未保存Decision・Eventや復旧待ちなどの未処理状態もないことを確認します。Timerを1秒から30秒、heartbeatを10秒から30秒へ変更し、tickごとの取引照合などを省略します。Leaseの有効期間60秒、MN1の61本／W1からH1の各206本、履歴不足時のログ・再取得抑制条件は変えません。

H1バーごとには履歴準備だけを確認し、完全な波動分析やJudgeを繰り返しません。売買開始日時へ到達した場合、既存リスクがある場合、またはDB・Leaseが正常でない場合は通常のTimer 1秒・heartbeat 10秒へ戻し、照合と保護を続けます。通常復帰時は高速期間の30秒のDB再確認待ちも解除し、復旧確認を繰り延べません。開始後は新しく完全な分析を行うため、準備確認だけの古いスナップショットをEntryへ流用しません。高速化のためにLeaseなしの保護操作や新規注文を許可することはありません。

EA 1.02で追加したこの機能は、`H1EaTradeExecutor`の`entryActionUid`初期化漏れにより、新規起動の空状態でも高速化条件を満たしませんでした。MQL5の未初期化stringはNULLであり、空文字`""`と同一ではないためです。EA 1.03ではコンストラクタで空文字を明示し、拒否条件の確認に加えて、正常な空状態が高速化対象になる陽性テストを追加しました。DBスキーマ・input・Entry条件・Leaseと既存保護の安全条件は変更しません。

再現確認は15.1と同じ設定で行い、次を確認します。

1. DB・Lease正常かつ既存リスクと未処理状態がないウォームアップ中に、運用ログへ`TIMER_SECONDS=30`が出る。
2. 売買開始日時への到達後は`TIMER_SECONDS=1`へ戻り、完全な分析・通常評価が始まる。初回の1秒ログだけで高速化成功とは判定しない。
3. 開始前のDecision・新規Entry Trade・新規注文がなく、既存リスクやDB・Lease異常時は高速化を解除して従来の安全条件と保護処理を維持する。
4. 実行時間は同じテスト期間・モデル・ビジュアル設定で比較する。30秒への切替確認と、速度改善の実測は別々に記録する。

## 16. Viewer

現行Viewerの`--database`はAlert/Observation DB用のまま変更しません。EA取引表示は初版の対象外です。

Viewer連携の起動引数と画面構成は、EA初版の実装後に別途設計します。Alert DBとの`market_signal_key`一致は候補抽出にだけ使用でき、Runをまたぐ一意キーとは扱いません。

## 17. 異常時の基本方針

| 異常 | 動作 |
|---|---|
| 分析データ取得失敗 | 売買開始後は回数を加算せず同一H1バー内で再試行。バー終了まで失敗した場合はSKIP確定、新規注文しない。Testerの売買開始前は分析のみでSKIPを作らない |
| DB接続・schema失敗 | 新規注文停止、既存ポジション管理継続 |
| Spread取得不能 | 新規注文しない |
| 初期SL不正 | 新規注文しない |
| 初期SL最大幅超過 | 新規注文しない |
| H1 ZigZag点取得不能 | 新しいトレイル候補を作成せず、既存broker SLを維持 |
| トレイル候補が非改善 | 見送り理由を保存し、現在SLとpendingを維持 |
| Stops/Freeze距離不足 | pendingを維持し、最短1秒間隔で再試行 |
| SL変更拒否・受付不明 | broker SLを再取得し、未反映ならpendingを維持 |
| トレイル候補を価格が通過 | `H1_ZIGZAG_TRAIL_CROSSED`で全量成行決済 |
| 初期SL復元前に価格が通過 | `INITIAL_STOP_LOSS_CROSSED`で全量成行決済 |
| 有効pendingのbroker照合不能 | pendingと未完了actionを保持して`RECOVERY_REQUIRED`、broker SLを維持 |
| pendingの構造不正 | 生の値をRecovery Eventへ隔離し、構造化pendingを解除して`RECOVERY_REQUIRED` |
| OrderCheck失敗 | `OPEN_FAILED`、同一シグナル再送なし |
| OrderSend受付不明 | `OPEN_PENDING`のままbroker照合 |
| 部分約定 | 残存数量をbrokerで確認 |
| 複数自EAポジション | 新規注文停止、異常ログ |
| 同一コンテキスト二重起動 | 後発EAの初期化を拒否 |
| 排他Lock取得失敗 | 初期化を拒否 |
| DB停止中に既知Leaseが失効 | EAからの取引操作停止、broker SLのみ継続 |
| ネッティング口座 | 初期化を拒否 |
| DBとbrokerの不一致 | brokerを正本として回復、断定不能なら`RECOVERY_REQUIRED` |

## 18. 受入条件

初版は次をすべて確認できた場合に完了とします。

1. H1以外では初期化を拒否する
2. 売買開始の対象となった進行中H1バーも初回分析成功時に判定し、DBへ保存済みのバーは再判定しない
3. BUY、SELLおよび各主要SKIP理由をDBへ保存できる
4. 通常版ZigZagElliotのH1初期設定と同じ分析スナップショット・回数の時系列で戦略Entry可否と対象H1バーが一致する。発注安全条件のSKIPは別に比較する
5. H1とH4の条件付き第5波を正しく判定する
6. 不正、設定不能または最大幅を超えるSLでは注文しない
7. 同じシグナルを再起動後も再注文しない
8. `OrderCheck()`、発注、部分約定および決済を状態遷移とEvent履歴で追跡できる
9. 確定H1 ZigZagの谷・山からBUY・SELLのトレイル候補を正しく計算できる
10. Wave不足、非H1 Wave、無効な価格・時刻・価格単位、0以下候補、補完点、形成中足、Entry前pivotおよび方向不一致を見送れる
11. トレイルSLを現在SLより、かつpendingがある場合はpendingより1tick以上保護側へだけ更新し、損失側へ戻さない
12. Stops/Freeze距離不足またはSL変更失敗をpendingとして保持し、最短1秒間隔で再試行できる
13. SL反映前の候補跨ぎで全量決済し、同じH1バーで再エントリーしない
14. pending候補を再起動後にbroker SLと照合し、適用済みまたは再試行へ復旧できる
15. 初期SL、初期SL復元前の跨ぎ、H1 ZigZagトレイルSLおよびトレイル候補跨ぎをbroker理由と分けて保存できる
16. SL変更、SL約定、EA決済および外部決済をEvent履歴から追跡できる
17. DB障害時に新規注文を停止し、排他LockとLease安全期限内だけ既存ポジションのSL変更・決済管理を継続する
18. EA再起動後にDBとbrokerポジションを整合できる
19. LIVEとTesterのDBが分離される
20. 対象EAと新規DB SmokeTestがMetaEditorでコンパイル成功する
21. 同一コンテキストの二重起動をLeaseで拒否できる
22. ヘッジ口座だけで動作し、ネッティング口座を拒否する
23. 部分Entryの残注文を取消し、不足数量を再発注しない
24. 候補跨ぎの部分決済後、残存数量を最短1秒間隔で再決済できる
25. Strategy Tester最適化では初期化を拒否する
26. 反対GMMA条件だけでは保有ポジションを決済しない
27. broker SLが候補以上に保護済みなら実SLと設定元を保存し、SL変更を送信せずpendingを解除できる
28. より保護的なSLを緩めず、手動・他EAを積極的に確認できた場合だけ`EXTERNAL`、由来を証明できない場合は`UNKNOWN`とし、要求履歴なしに`H1_ZIGZAG_TRAIL`と誤分類しない
29. broker SLの削除・緩和時に、初期SL・適用済みトレイルSL・有効pendingの最も保護側を適切な種別で復元できる
30. DB正常時のcommit先行経路と、Lock・Lease安全期限内だけ許可するDB障害時の制限経路を検証できる
31. broker SL約定で`OPEN`から`CLOSED`へ更新できる
32. 再起動時にPosition消滅、識別子不一致および決済途中の残Positionを安全に整合できる
33. pending候補跨ぎ決済を開始したH1バーでは新規発注せず、Entry周期でのJudge回数管理は継続する
34. 初期SL復元ではZigZag情報を作らず、トレイル由来pendingと区別して保存・復旧できる
35. broker実SLを取得できないSL変更actionでは結果を断定せず、pendingとactionを保持して`RECOVERY_REQUIRED`へ移行できる
36. `RECOVERY_REQUIRED`中はbroker照合以外の新しい注文、SL変更および成行決済を送信しない
37. `INITIAL_RESTORE`がpendingの間は新しいトレイル評価を見送り、初期SL復元または跨ぎ決済を優先する
38. 構造不正なpendingの生データをRecovery Eventへ隔離し、CHECK制約を満たす状態で`RECOVERY_REQUIRED`へ移行できる
39. SL変更後に「SLなし」を正常取得した場合と、broker取得不能を区別して保存・復旧できる
40. 初期SLとH1 ZigZagトレイル候補を、BUYは基準の谷から10.0 pips下、SELLは基準の山から10.0 pips上へ計算できる
41. W1からH1の一致が必須で、MN1不一致でもW1 EMA200一致なら通過し、両方不一致なら拒否する（BUY・SELL両方）
42. 初回Judge成立時に波動NGだったシグナルは、後のH1バーで波動OKになってもEntryしない
43. JudgeがOFFになっても同じキーの回数を戻さず、方向変更は別キーとして扱える
44. LIVEの初回タイマー・30秒周期とTesterのtick処理を分離し、成功したH1バーは1回だけ判定する
45. 分析準備・分析失敗だけは同じバーで再試行でき、成功後のJudge NG・Entry NGは再試行しない
46. 保有中・SL不正・DB障害などの見送りで初回を後のバーへ繰り越さず、復旧後の遅延発注をしない
47. 消費済みSKIPと回数をDBから復元し、再起動・同一バー再実行で重複加算しない
48. トレイル評価用の分析・処理済みバーが、Entryの評価時点・処理済みバーへ干渉しない
49. H1のSpreadは5.0 pipsまで通過し、5.0 pips超過は拒否する。H1以外と他戦略の3.0 pips上限は変わらない
50. Testerの売買開始前は別管理の履歴準備確認だけをH1バーごとに1回進め、Entry用の完全分析・Entry状態・Judge回数・初回消費を進めず、Decision・新規Entry Trade・新規注文を作らない。Run・heartbeatと既存保護処理は継続する
51. 売買開始後の最初のtickでは同じH1バーでも通常分析・評価をやり直し、ウォームアップ期間のバーをSKIPとして後から確定しない。開始日時0は制限なし、LIVEでは設定値にかかわらず無効となる
52. Runの`config_text`・`config_hash`に有効な`TESTER_TRADE_START_TIME`を保存する。履歴不足の時間足別INFOは初回・状態変化時（最短1時間）・24時間ごと、分析再開時は1回とし、不足系列の再取得は最短60秒間隔に抑制する。61本／206本の準備条件は維持する
53. 高速ウォームアップはTesterの開始前・DB/Lease正常・既存リスクと未処理状態なしの場合だけ有効となり、Timer/heartbeatは30秒、Leaseは60秒を維持する。開始時・リスク発見・DB異常時には通常の1秒/10秒へ戻り、保護処理を継続する

## 19. 実装方針と参照

### 19.1 直接再利用する実装

| 領域 | 実装 |
|---|---|
| 市場コンテキスト | [MarketContext.mqh](../../Include/Mstng/Common/MarketContext.mqh) |
| 分析ハンドル | [OscillatorHandlePool.mqh](../../Include/Mstng/Oscillator/OscillatorHandlePool.mqh) |
| 親子Elliott分析 | [ElliotAll.mqh](../../Include/Mstng/Elliot/ElliotAll.mqh) |
| H1判定生成 | [ExpertAdvisorMtf3In3Factory.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3Factory.mqh) |
| H1判定 | [ExpertAdvisorMtf3In3H1.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3H1.mqh) |
| Judge・Entryの呼出し順 | [AbstractExpertAdvisor.mqh](../../Include/Mstng/ExpertAdvisor/AbstractExpertAdvisor.mqh) |
| 方向一致 | [H1DirectionAlignmentDecision.mqh](../../Include/Mstng/ExpertAdvisor/H1DirectionAlignmentDecision.mqh) |
| シグナル回数の参照実装 | [SignalCount.mqh](../../Include/Mstng/Signal/SignalCount.mqh) |
| H1・H4波動判定 | [H1EntryWaveDecision.mqh](../../Include/Mstng/ExpertAdvisor/H1EntryWaveDecision.mqh) |
| H1・H4 EMA200 | [H1Ema200ConfirmationDecision.mqh](../../Include/Mstng/ExpertAdvisor/H1Ema200ConfirmationDecision.mqh) |
| H1 ZigZagトレイル判定 | [H1ZigZagTrailDecision.mqh](../../Include/MstngEa/Strategy/H1ZigZagTrailDecision.mqh) |
| H1新規バー | [NewBarDetector.mqh](../../Include/MstngEa/Market/NewBarDetector.mqh) |
| ポジション取得 | [PositionService.mqh](../../Include/MstngEa/Trade/PositionService.mqh) |
| Magic Number | [MagicNumberUtil.mqh](../../Include/MstngEa/Trade/MagicNumberUtil.mqh) |
| SQLite接続 | [SqliteDatabase.mqh](../../Include/Mstng/Database/SqliteDatabase.mqh) |

既存の[ExpertAdvisorMtf3In3Adapter.mqh](../../Include/MstngEa/Strategy/ExpertAdvisorMtf3In3Adapter.mqh)は内部で方向一致を`D1_TO_H1`に固定しているため、そのまま使用しません。新EA専用AdapterでFactoryへ5章の各モードを明示し、既存H1判定の順序を維持しつつDBの回数・消費を復元します。既存EAやインジケータの判定コードは変更しません。

判定周期・初期バー・同一バー再試行の参照元は[ZigZagElliotController.mqh](../../Include/Mstng/Indicator/ZigZagElliot/ZigZagElliotController.mqh)、設定の基準は[ZigZagElliot.mq5](../../Indicators/ZigZagElliot.mq5)です。

### 19.2 新設する主な責務

- H1専用Controller
- H1専用Config
- 既存モードを明示するH1専用Strategy Adapterと、Judge回数・消費の永続化復元
- H1専用Trade Executor
- pending保護SL候補の種別付き永続化・復旧
- SL変更と候補跨ぎ決済の制御
- H1 EA Database Context
- Run、Decision、Trade、Trade EventのEntity、DAOおよびPersistence Service
- H1 EA Database SmokeTest
- 再起動整合処理

既存`MstngEa`の詳細は[MstngEa仕様書](MstngEa.md)を参照してください。

## 20. 実装前に確定した事項

2026-09-05に次の3点を確定しました。

1. 正式名称は`MstngH1Ea`、ファイルは`Experts/MstngH1Ea.mq5`
2. Magic Number用EAコードは`12`（現行`MstngEa`は`11`）
3. `InpMaxInitialStopLossPips`の既定値は利用者指定の`100.0` pips。研究分布由来ではなく、0以下の指定は初期化を拒否する

## 21. 初版実装と確認手順

実装の入口は[Experts/MstngH1Ea.mq5](../../Experts/MstngH1Ea.mq5)、制御本体は[H1EaController.mqh](../../Include/MstngH1Ea/H1EaController.mqh)です。判定、発注・保護、DB保存は別クラスとし、通常版インジケータや既存`MstngEa`は置き換えません。

運用ログはCommonフォルダの`MstngH1Ea/Logs/<run_uid>.log`へ追記します。チャート通貨・時間足などの再初期化ではControllerを作り直し、旧Run・旧シンボルのメモリ状態を流用しません。

初回の確認は次の順で行います。

1. 対象EAをMetaEditorでコンパイルする。
2. `InpMaxInitialStopLossPips`の既定値が`100.0` pipsであること、および0以下を指定すると初期化が拒否されることを確認する。
3. 15.1の設定でテスター実行開始日と売買開始日時を分け、H1・ヘッジ口座のStrategy TesterでEntry候補を照合する。比較対象の通常版H1も同じ分析履歴・評価時点・売買開始後のJudge回数を使用し、SL管理の受入確認ではティックを含むモデルを使用する。
4. Tester用DBのRun、Decision、Trade、Eventで、初回消費・SL設定・決済理由を確認する。
5. 再起動、部分約定、DB保存失敗、SL削除・緩和、SL候補跨ぎをデモ環境で確認してから運用判断する。

SQL回帰テストは`Scripts/Mstng/Database/test_h1_ea_database_contract.py`です。MQL5の検証スクリプトは`H1EaDatabaseSmokeTest`、`MstngH1StrategySmokeTest`、`MstngH1InitialStopLossSmokeTest`、`MstngH1EaConfigSmokeTest`、`MstngH1EaEntryStateSmokeTest`、`H1EaProtectionPolicySmokeTest`、`H1EaTradeExecutorSmokeTest`です。コンパイル確認・SQL制約テストと、MT5での約定を含む実行時検証は区別します。コンパイル成功だけで実運用の受入完了とはしません。

テスター売買開始日時の追加前の確認記録（2026-09-05）は、上記7スクリプト・新EA・既存`MstngEa`・通常版`ZigZagElliot`・`ZigZagElliotList`がコンパイルエラー0・警告0、実装のCREATE文を使用するSQLite回帰テスト22件が成功です。この記録の時点では、MQL5スクリプトの実行、Strategy Testerによる取引確認、実口座への起動・売買は行っていません。

売買開始日時追加後の確認記録（2026-09-05、EA 1.01）は次のとおりです。

- `MstngH1Ea`、`MstngH1StrategySmokeTest`、`MstngH1EaConfigSmokeTest`、`MstngH1EaEntryStateSmokeTest`をコンパイルし、すべてエラー0・警告0。
- SQLite回帰テスト22件が成功。
- `Scripts/Mstng/ExpertAdvisor/test_h1_ea_tester_warmup_contract.py`の静的配線チェック10件が成功。入力値の受け渡し、LIVE無効化、開始前のEntry状態・保存への到達防止、履歴条件とログ抑制の配線を検査。
- 開始直前・同時・直後、0の無制限、H1途中の開始、Judge未消費、Config Hash差分を確認するMQL5 SmokeTestを追加。コンパイルのみであり、MQL5でのテスト実行・EA 1.01のStrategy Testerによる期間跨ぎと約定の確認は未実施。

EA 1.02の高速ウォームアップ追加直後の確認記録（実テスター確認前）は次のとおりです。

- `MstngH1Ea`、`MstngH1StrategySmokeTest`、`MstngH1EaConfigSmokeTest`、`MstngH1EaEntryStateSmokeTest`、`H1EaTradeExecutorSmokeTest`をコンパイルし、すべてエラー0・警告0。
- SQLite回帰テスト22件、実ソースを対象とした静的配線チェック19件が成功。高速化の安全条件、Timer/heartbeat切替、通常復帰時のDB待ち解除、履歴準備と完全分析の分離を確認。
- この時点ではMT5でのMQL5実行、期間跨ぎ・約定を伴うStrategy Tester確認、速度の実測は未実施。コンパイルと静的/SQLiteテストの成功を、実行時の安全性や処理速度の実証とは扱わない。

その後のEA 1.02実テスター確認（2026-09-05、Tester DBのRun 5、Run UID `a3315cfba40d9e2b2d4762fb8caf8ba341c3d567ce872b48c666d76324c07d26`）では、次が判明しました。

- 設定はGBPUSD・H1、テスト期間2021.01.01～2026.09.05、リアルティック・ビジュアル有効、売買開始2026.01.01。最終テスト内時刻は2026.09.04 23:59:58。
- 実時間は全体1時間50分36秒、売買開始後の最初の評価（テスト内2026.01.02 00:00）まで1時間25分34秒。運用ログは`TIMER_SECONDS=1`のみで、30秒への切替は実行されていなかった。
- 原因は15.2の`entryActionUid`初期化漏れ。既存のコンパイル・静的配線チェックと、未準備状態を拒否するテストだけでは、正常な空状態が実際に高速化条件を通過することを確認できていなかった。
- Runは`STOPPED`、開始前Decisionは0件、Decision 4,224件、14取引すべて決済済み。4勝10敗、純損益−287円で、残高10,000円→9,713円と整合した。これは売買開始制限と取引結果の確認であり、高速化成功の根拠ではない。
- 決済結果はTradeとRECOVERYに保存されているが、決済側のDEAL_ADD単体イベントがない理由は未確定。この内訳はEA 1.03の初期化漏れ修正の対象外とし、別途確認を要する。

EA 1.03の初期化漏れ対策後の確認記録（2026-09-05）は次のとおりです。

- `MstngH1Ea`、`H1EaTradeExecutorSmokeTest`、`MstngH1EaConfigSmokeTest`をコンパイルし、すべてエラー0・警告0。
- 静的配線チェック20件、SQLite回帰テスト22件が成功。新しい初期化検査は修正前の`entryActionUid`で失敗し、コンストラクタ修正後に成功した。他の静的19件は修正前後とも成功。
- MQL5 SmokeTestへ、専用DBのロードと空口座の照合後に高速化対象となる陽性経路、および未ロード・Lock解除・期限無効で拒否する経路を追加した。実注文を送らない検証スクリプトであり、今回の確認はコンパイルまで。
- MQL5 SmokeTestの実行、EA 1.03のStrategy Tester再実行・速度測定は未実施。30秒→1秒切替と速度改善の実証は、15.2の再現確認が済むまで未確認とする。

EA 1.04の決済約定監査対策（2026-09-05）は12.5のとおりです。

- `MstngH1Ea`、`H1EaDealHistorySmokeTest`、`H1EaTradeExecutorSmokeTest`、`H1EaDealAuditSmokeTest`、`H1EaDatabaseSmokeTest`、`MstngH1EaConfigSmokeTest`をコンパイルし、すべてエラー0・警告0。
- `H1EaDealHistorySmokeTest`は履歴APIだけをfixtureへ差し替え、選択失敗・全getterの失敗・値0と欠損の区別・ticket先退避・途中失敗で部分結果を返さないことを検証する。`H1EaDealAuditSmokeTest`は専用新規DBで、重複、CLOSED状態不変、保存失敗のrollbackと再試行、context制約、全件監査を検証する。いずれも実注文を送らないスクリプトであり、この記録ではコンパイルまで。
- 新しい`Scripts/Mstng/ExpertAdvisor/test_h1_ea_deal_audit_contract.py`は実CREATE文・実検索WHEREを使うSQLiteテストと、MQLソースの静的配線チェックを区別する。MQL Service／Executorそのものの実行テストとは扱わない。
- Python回帰テストは新規約定監査29件、既存ウォームアップ20件、既存DB制約22件の計71件が成功。
- EA 1.04での実約定を伴うStrategy Tester確認は未実施。次回テストでは初期SL・H1トレイルSL・部分約定の全ticketと`DEAL_ADD`を突合し、重複なし、数量・価格・時刻・理由一致、終了時の未保存・未確認なしを確認する。今回、既存の運用／Tester DBは直接変更していない。

EA 1.05の非ビジュアル分析対策（2026-09-05）は15.1のとおりです。

- EA 1.04の非ビジュアル実テスト（Run 9）は2時間7分40秒、取引0件、保存されたDecision 4,223件すべてが`ANALYSIS_UNAVAILABLE`だった。W1のEMA200が`calculatedCount=-1`のまま取得前に中断し、内部エラーを毎tick繰り返していた。Runが`STOPPED`でも正常な売買検証の成功とは扱わない。
- EMA200の取得要求を先行させ、完全本数・有限値・`EMPTY_VALUE`を検証する。TesterのEntry分析失敗時だけ最短1秒の再試行とし、内部の同一INFO/ERRORをH1単位で抑制する。売買条件、LIVEの評価周期、照合・pending保護SL・トレイルの周期は変更しない。
- `MstngH1Ea`、`ZigZagElliot`、`ZigZagElliotList`、`MstngEa`、`MstngH1EaConfigSmokeTest`をコンパイルし、すべてエラー0・警告0。
- `Scripts/Mstng/ExpertAdvisor/test_h1_ea_analysis_retry_contract.py`は実MQLソースの静的検査であり、MQLの実行・指標値・実行速度を検証したものではない。
- 今回追加の静的検査21件、既存のウォームアップ20件・約定監査29件・DB制約22件の計92件が成功した。CopyBufferの取得順序・失敗伝播、Tester限定の待機・H1切替・Judge未消費、保護処理の順序、分析区間限定のログ抑制と固定上限を確認した。
- EA 1.05のStrategy Testerは未実行。まず売買開始後の終了日を短くした非ビジュアルテストでW1分析の再開、取引および決済`DEAL_ADD`の保存を確認し、その後に全期間で正常実行時の14取引と比較する。既存の運用／Tester DBおよび大量出力された運用ログは変更・削除していない。
