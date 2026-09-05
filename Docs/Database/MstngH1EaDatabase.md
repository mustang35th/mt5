# MstngH1Eaデータベース設計書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象機能 | H1専用EA `MstngH1Ea`の判定・取引永続化 |
| DBMS | MetaTrader 5組み込みSQLite |
| 物理スキーマバージョン | 1 |
| 保存単位 | EA起動、H1判定、H1 ZigZagトレイル、取引ライフサイクル |
| 文書状態 | 初版実装・テスター受入確認前 |
| 最終更新日 | 2026-09-05 |

本書は、`MstngH1Ea`がH1判定、発注、約定および決済を保存し、再起動後にbroker状態と整合するためのSQLite構造を定義します。EA全体の動作は[MstngH1Ea基本設計書](../ExpertAdvisor/MstngH1Ea.md)を参照してください。

## 2. 対象範囲

初版では次を保存します。

- EA起動ごとの環境、設定およびバージョン
- 起動時の進行中バーを含む、評価対象H1バーのBUY、SELLまたはSKIP確定判定
- 判定に使用した主要条件と拒否理由
- 既存H1 `MTF_3in3`のJudge成立回数、初回Entry評価およびEA発注可否の区別
- 発注要求から決済完了までの取引状態
- H1 ZigZagトレイル評価、pending保護SL候補および適用済みSL
- 取引要求、SL変更、broker order、各dealおよびPositionのEvent履歴
- brokerで確認した現在SL、SL設定元およびEA側の決済分類
- 確定損益、commission、swapおよびfee
- 再起動時の回復状態

次は初版の対象外です。

- Tick履歴
- OHLC全履歴
- ZigZag全ポイント
- 注文板情報
- Alert/Observation DBへの外部キー
- 年別または通貨別DB分割
- ViewerからのDB更新
- CSVからの履歴移行

`ZigZag全ポイント`は保存しませんが、トレイル評価で実際に使用した基準点と確認点はTradeおよびEventへ保存します。

取引、現在SLおよびpending保護SL候補の現在状態は`h1_ea_trades`、部分約定、トレイル評価およびSL変更履歴は`h1_ea_trade_events`を正本とします。

## 3. DBファイル

### 3.1 LIVE

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-h1-ea.sqlite
```

### 3.2 Strategy Tester

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-h1-ea-tester.sqlite
```

- Commonフォルダを固定使用します。
- LIVEとTesterを同じ物理ファイルへ混在させません。
- 年別および通貨別には分割しません。
- Strategy Tester最適化ではEA初期化を拒否します。
- DBを自動削除または自動再作成しません。

初版はStrategy Tester最適化を非対応とし、`MQLInfoInteger(MQL_OPTIMIZATION)`がtrueの場合はEA初期化を拒否します。

## 4. 接続設定

Writerは既存の`SqliteDatabase`を再利用し、専用Database Contextから次を設定・確認します。

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
```

- 1 EAインスタンスにつき1接続を保持します。
- schema作成およびmigrationは起動時だけ実行します。
- DDLは再実行可能にします。
- 通常のtickではDDL、migrationおよび長い集計を行いません。
- 保存は1イベント単位の短いtransactionとします。
- Viewerはread-onlyで接続し、migrationしません。
- 複数Writerが同時起動しても、schema確認、DDLおよび`user_version`更新を単一transactionで行います。

物理DB世代は`PRAGMA user_version = 1`で管理します。保存契約の世代は各Runの`schema_version`へも保存し、物理世代と実行データの世代を分離します。

## 5. テーブル関係

```text
h1_ea_runs (1)
  ├─ h1_ea_decisions (N)
  │    └─ h1_ea_trades (0..1)
  └─ h1_ea_trades (N、回復行を含む)
       └─ h1_ea_trade_events (N)
```

- `h1_ea_decisions.run_id`は`h1_ea_runs.id`を参照します。
- `h1_ea_trades.created_run_id`は取引行を作成した`h1_ea_runs.id`を参照します。
- `h1_ea_trades.decision_id`は`h1_ea_decisions.id`を参照します。
- `h1_ea_trade_events.trade_id`は`h1_ea_trades.id`を参照します。
- `h1_ea_trade_events.run_id`はEventを観測・保存した`h1_ea_runs.id`を参照します。
- 親子行は必要な単位で同一transactionへ保存します。
- 運用履歴を意図せず失わないよう、初版では親行の通常削除を提供しません。
- 外部キーの削除動作は`ON DELETE RESTRICT`とします。

## 6. 共通データ表現

| 種別 | SQLite | MQL5 | 備考 |
|---|---|---|---|
| 主キー | `INTEGER` | `long` | `PRIMARY KEY AUTOINCREMENT` |
| broker時刻（秒） | `INTEGER` | `datetime` | `TimeCurrent()`またはバー時刻。UTCへ自動変換しない |
| broker約定時刻（ms） | `INTEGER` | `long` | `DEAL_TIME_MSC`、`ORDER_TIME_*_MSC`などbroker提供値だけ |
| terminal時刻（秒） | `INTEGER` | `datetime` | `TimeLocal()`。Run、heartbeat、作成・更新時刻 |
| 真偽値 | `INTEGER` | `bool`をint化 | 0または1、CHECK制約 |
| 時間足 | `INTEGER` | `ENUM_TIMEFRAMES`をint化 | 初版はH1固定 |
| 価格・pips・損益 | `REAL` | `double` | brokerの値を保持 |
| Magic・ticket・identifier | `TEXT` | `ulong`を文字列化 | 符号付き64bit境界の影響を避ける |
| enum・理由 | `TEXT` | `string` | CHECK制約または定数で管理 |
| 任意値 | `NULL` | 対応型 | 未取得と有効な0を区別 |

`TimeCurrent()`およびH1バー時刻はbroker serverのカレンダー時刻として保存し、UTC Unix秒とは断定しません。`*_msc`列はbrokerがミリ秒値を提供するorder、dealおよびPositionだけに使用します。EA評価や要求時刻を`GetTickCount64()`でUnixミリ秒へ見せかけません。

日時の目視用文字列とJSTはDBへ重複保存しません。将来表示する場合は、接続サーバーに対応するtimezone変換規則とそのversionをViewer側で明示します。

## 7. `h1_ea_runs`

EA起動1回につき1行を保存します。

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `id` | INTEGER | Yes | 主キー |
| `run_uid` | TEXT | Yes | 起動ごとの一意ID |
| `schema_version` | INTEGER | Yes | 保存契約バージョン |
| `source_mode` | TEXT | Yes | `LIVE`または`TESTER` |
| `context_key` | TEXT | Yes | LIVEまたはTesterの実行コンテキストキー |
| `account_server` | TEXT | Yes | 接続サーバー |
| `account_login` | INTEGER | Yes | 口座番号 |
| `symbol_name` | TEXT | Yes | brokerシンボル名 |
| `time_frame` | INTEGER | Yes | `PERIOD_H1` |
| `magic_number` | TEXT | Yes | Magic Number |
| `program_version` | TEXT | Yes | EAバージョン |
| `strategy_version` | TEXT | Yes | エントリーおよびポジション管理ロジック世代 |
| `analysis_version` | TEXT | Yes | 分析計算世代 |
| `analysis_input_text` | TEXT | Yes | 分析結果へ影響する設定のCanonical Text |
| `analysis_input_hash` | TEXT | Yes | `analysis_input_text`のSHA-256 |
| `config_text` | TEXT | Yes | 有効設定のCanonical Text |
| `config_hash` | TEXT | Yes | `config_text`のSHA-256 |
| `started_at` | INTEGER | Yes | `TimeLocal()`による起動時刻 |
| `ended_at` | INTEGER | No | `TimeLocal()`による終了時刻 |
| `heartbeat_at` | INTEGER | Yes | 最終Lease更新時刻 |
| `lease_expires_at` | INTEGER | Yes | Lease失効時刻 |
| `status` | TEXT | Yes | Run状態 |
| `error_text` | TEXT | Yes | 終了または異常理由。通常は空文字 |

`context_key`は実行元によって次のように生成します。

```text
LIVE   : H1_EA_CONTEXT_V1|LIVE|server|login|symbol|H1|magic
TESTER : H1_EA_CONTEXT_V1|TESTER|run_uid|server|login|symbol|H1|magic
```

LIVEは再起動前後で同じキーを使用し、保存済みJudge成立回数、消費済みシグナルおよびactive取引を引き継ぎます。Tradeを持たない消費済みSKIPも引継ぎ対象です。TesterはRunごとにキーを分け、同じ期間を繰り返しテストしても過去RunのDecisionと衝突しないようにします。この`context_key`をDecisionとTradeの重複防止scopeとして使用します。

キー文字列は`H1_EA_CONTEXT_V1`を先頭に、表記どおりの固定順、区切り文字`|`、整数の10進表記で生成します。serverとsymbolに`|`が含まれる場合は初期化を拒否し、暗黙の置換は行いません。`run_uid`は`source_mode|server|login|chart_id|started_at|GetTickCount64`をUTF-8でSHA-256化した64桁小文字16進文字列とします。`GetTickCount64()`はUID生成材料にだけ使用し、日時として保存しません。

分析Profileは既存の`ZigZagElliotAnalysisProfile::createCanonicalText()`と`createHash()`をそのまま使用します。EA設定は次の固定順で生成し、数値の小数桁も固定します。

```text
H1_EA_CONFIG_V1|LOT_SIZE=<8桁>|MAX_INITIAL_SL_PIPS=<1桁>|ZIGZAG_SL_BUFFER_PIPS=10.0|MAX_SPREAD_PIPS=5.0|ANALYSIS_START_TIME_FRAME=MN1|H1_DIRECTION_ALIGNMENT_MODE=H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED|H1_W1_CONFIRMATION_MODE=H1_W1_CONFIRMATION_OBSERVE_ONLY|H1_EMA200_CONFIRMATION_MODE=H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED|H1_DISPLAY_WAVE_ENTRY_LIMIT_ENABLED=0|CURRENCY_STRENGTH_ENTRY_FILTER_ENABLED=0|ENTRY_COUNT=1|LIVE_FIRST_EVALUATION_SECONDS=1|LIVE_EVALUATION_INTERVAL_SECONDS=30|TESTER_EVALUATION_TRIGGER=TICK|TESTER_TRADE_START_TIME=<epoch秒>
```

`ZIGZAG_SL_BUFFER_PIPS`は初期SLとH1 ZigZagトレイルSLに共通する内部固定値です。初版ではinputから変更できません。上記の戦略・評価タイミング設定は現在の`ZigZagElliot` H1の初期設定に合わせた固定値です。W1追加確認は観測のみですが、主条件のW1方向および「MN1方向またはW1 EMA200方向」は必須判定へ使用します。これらの固定値またはシグナル消費規則を変更する場合は`strategy_version`も更新します。

`MAX_SPREAD_PIPS=5.0`は基本設計v0.5のH1上限です。旧3.0 pips仕様との違いはRun設定と戦略バージョンで識別し、保存済みDecisionは新上限で再判定・上書きしません。

`TESTER_TRADE_START_TIME`は有効な`InpTesterTradeStartTime`を`datetime`の秒整数へ変換した値です。Testerの既定入力は`2026.01.01 00:00`、0なら開始日時の制限なし、LIVEの有効値は入力値にかかわらず0です。Tester内のサーバー日時として扱い、UTC/JST変換は行いません。この値を末尾へ追加した`config_text`と、その全体の`config_hash`を既存Run列へ保存します。列追加・スキーマ変更・既存Runの書換えは行いません。

売買開始日時設定はEA `1.01`、安全条件付きの高速ウォームアップはEA `1.02`で導入し、既存の`program_version`列で識別します。高速化用inputや保存列は追加せず、物理スキーマとRunの`schema_version`は1を維持します。

`status`は次に限定します。

```text
RUNNING
STOPPED
FAILED
INTERRUPTED
```

次は`CREATE TABLE h1_ea_runs (...)`内へカンマ区切りで組み込む制約断片です。

```sql
CHECK(source_mode IN ('LIVE', 'TESTER'))
CHECK(status IN ('RUNNING', 'STOPPED', 'FAILED', 'INTERRUPTED'))
CHECK(heartbeat_at > 0)
CHECK(lease_expires_at >= heartbeat_at)
```

一意制約と主な索引は次のとおりです。

```sql
CREATE UNIQUE INDEX idx_h1_ea_runs_run_uid
ON h1_ea_runs(run_uid);

CREATE UNIQUE INDEX idx_h1_ea_runs_active_context
ON h1_ea_runs(context_key)
WHERE status = 'RUNNING';

CREATE INDEX idx_h1_ea_runs_source_started
ON h1_ea_runs(source_mode, started_at, id);

CREATE INDEX idx_h1_ea_runs_context_started
ON h1_ea_runs(context_key, started_at, id);
```

EAは1秒間隔の`OnTimer()`内で10秒の経過を確認してheartbeatを更新し、Leaseを更新時点から60秒間有効にします。LIVEの初回1秒後・以降30秒間隔のEntry評価とはスケジュールを分離します。TesterのEntry評価はtickを契機とします。起動時に同一`context_key`の`RUNNING`が存在する場合、有効なLeaseなら二重起動として後発を拒否します。期限切れの場合だけ、transaction内で旧Runを`INTERRUPTED`へ更新して新Runを作成します。通常経路の新規注文、SL変更および候補跨ぎ成行決済では、今回Runの`status = 'RUNNING'`と未失効Leaseを、それぞれの要求Event・Trade更新と同一transactionで確認します。commit直後にbrokerへ送信し、確認と送信の間へ別のDB処理を挟みません。

EA 1.02では、Testerの売買開始前でDB・Lease・排他Lockが正常、取引照合が完了し、他銘柄分を含む口座内のポジション・注文と未保存Decision・Eventなどの未処理状態がない場合だけ、Timer・heartbeatを30秒間隔にします。Leaseは60秒のままです。売買開始時、既存リスクの発見時、DB・Lease異常時には通常のTimer 1秒・heartbeat 10秒へ戻し、高速期間の30秒のDB再確認待ちも解除します。これは処理頻度の切替だけであり、Runの所有確認や失効時の取引停止条件を緩和しません。

DB接続中にLease所有権を失った旧Runは、注文・変更・決済を停止します。DB障害中は、排他Lockを保持し、最後に確認できたLeaseが未失効の間だけ現在Runが既存ポジションのリスク管理を継続します。

### 7.1 DB非依存の排他Lock

DB接続障害中の二重管理を防ぐため、EAはDBを開く前にCommonフォルダのLockファイルを共有指定なしで開き、ファイルハンドルを稼働中保持します。

```text
MstngH1Ea\Locks\<instance_scope_hash>.lock
```

`instance_scope_hash`は`source_mode|server|login|symbol|H1|magic`のSHA-256です。Lockファイルの内容は状態の正本にせず、OSによる排他ハンドルだけを使用します。取得失敗時は後発EAの初期化を拒否し、EA終了時にハンドルを閉じます。異常終了後に空ファイルが残っても、ハンドルが解放されていれば再取得できます。

Run登録とLease取得は別処理にせず、期限切れRunの更新と新しい`RUNNING`行の追加を単一transactionで行います。DBを開けないが排他Lockを取得できた場合は、既存のbroker SLだけを継続する制限状態とし、DB復旧後に同じtransactionでRunを登録してLeaseを取得してからEAの取引操作を許可します。

最後に保存できた`lease_expires_at`へ到達するまでheartbeatを更新できなかった場合、排他Lockを保持していてもEAからの注文、SL変更および成行決済を停止します。起動後に一度もLeaseを取得できない場合は最初からEAの取引操作を禁止し、Lock取得時刻から60秒はDB再接続と初期照合を試す上限にだけ使用します。この60秒はbroker送信権限を与えません。これにより、別RunがLeaseを引き継いだ場合のsplit-brainを防ぎます。brokerへ設定済みのSLは継続します。

## 8. `h1_ea_decisions`

評価対象H1バー1本につき確定Decisionを1行保存します。起動時の進行中バーも、同一コンテキストの保存済みDecisionがなければ対象です。LIVEは初回1秒後・以降30秒間隔の評価機会、Testerはtickで、そのバーの最初の分析成功時にJudge、回数およびEntryを確定します。保有中または条件未達でも確定した結果をSKIPとして保存します。

ただしTesterの売買開始日時より前は履歴準備専用期間とし、Entryとは別の`lastWarmupBar`でH1バーごとに1回だけ`strategy.prepareHistory()`による本数・同期確認を行います。Entry用の完全な波動分析、Judge評価、Entry状態のobserve・finalize、回数加算・初回消費、Decision・新規Entry Tradeの保存、新規注文を行いません。開始前の準備失敗も後から`ANALYSIS_UNAVAILABLE`のDecisionへ補完しません。Run・heartbeatと既存ポジションの保護・監査保存は継続します。開始日時以降の最初のtickから、同じH1バーであっても通常の完全な分析・評価を新たに実行し、ウォームアップ期間のEntry状態・Judge回数は持ち込みません。

分析失敗だけではJudge・回数を更新せず、確定Decisionも作りません。同じH1バー内で再試行し、失敗した試行は運用ログへ残します。成功しないままバーが切り替わった場合は、前バーを`SKIP / ANALYSIS_UNAVAILABLE`、回数0・未消費として確定保存します。最初に確定したDecisionは再評価または上書きしません。稼働していなかった過去バーを推測で補完しません。

Decisionは戦略Entry判定とEA発注可否の正本です。H1新規バー最初のtickで行うH1 ZigZagトレイル評価はTrade Eventへ保存し、Decisionへトレイル状態を混在させません。Entryとトレイルは別の評価契機であり、同一H1バーでも分析・評価時刻が一致するとは限りません。

### 8.1 識別・時刻

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `id` | INTEGER | Yes | 主キー |
| `run_id` | INTEGER | Yes | Run外部キー |
| `context_key` | TEXT | Yes | LIVEでは再起動をまたぐEAコンテキスト |
| `market_signal_key` | TEXT | No | Alert DBとの照合にも使う市場シグナルキー |
| `snapshot_hash` | TEXT | Yes | 保存対象判定値のSHA-256 |
| `h1_bar_time` | INTEGER | Yes | 判定を開始したH1バー時刻 |
| `evaluated_server_time` | INTEGER | Yes | `TimeCurrent()`による判定完了時刻 |
| `created_at` | INTEGER | Yes | `TimeLocal()`による保存時刻 |
| `signal_reference_time` | INTEGER | No | H1の2番目に新しいZigZagポイント時刻 |

`market_signal_key`は既存Alert DBと同じ次の形式を使用します。

```text
server|symbol|time_frame|h1_bar_time|signal_reference_time|MTF_3in3|side
```

このキーは市場候補の比較用であり、一意ではありません。Runまたは分析Profileが異なる行を1件へ統合しません。

### 8.2 判定結果

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `decision` | TEXT | Yes | `SKIP`、`BUY`または`SELL` |
| `reason_code` | TEXT | Yes | 最終判定または対象外理由 |
| `signal_side` | TEXT | No | `BUY`または`SELL` |
| `is_judge_matched` | INTEGER | Yes | 共通Judge成立時1。Entry波動条件とEA発注制限は含めない |
| `signal_count` | INTEGER | Yes | 今回Judge成立時の加算後回数。Judge未成立・分析不能時は0 |
| `entry_count` | INTEGER | Yes | Entry評価対象の成立回数。初版は1固定 |
| `is_entry_evaluated` | INTEGER | Yes | 今回、初回Judge成立により既存相当のEntry判定を実行した場合1 |
| `is_strategy_entry` | INTEGER | Yes | 既存H1戦略のEntry成立時1。EA発注制限によるSKIPとは区別する |
| `is_signal_consumed` | INTEGER | Yes | 同一シグナルの初回Judge成立行だけ1。Entry不成立のSKIPも消費する |
| `spread_pips` | REAL | No | 判定時Spread |
| `requested_volume` | REAL | No | 正規化後の要求ロット |
| `initial_stop_loss` | REAL | No | 注文前に検証した初期SL |
| `initial_risk_pips` | REAL | No | 建値候補から初期SLまでの幅 |
| `max_initial_risk_pips` | REAL | Yes | Runで使用した初期SL最大幅 |

### 8.3 主要条件スナップショット

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `mn1_direction` | TEXT | No | MN1の`BUY`または`SELL` |
| `w1_direction` | TEXT | No | W1の`BUY`または`SELL` |
| `d1_direction` | TEXT | No | D1の`BUY`または`SELL` |
| `h4_direction` | TEXT | No | H4の`BUY`または`SELL` |
| `h1_direction` | TEXT | No | H1の`BUY`または`SELL` |
| `h1_wave_direction` | TEXT | No | H1最新Waveの方向 |
| `h1_elliot_label` | TEXT | No | H1最新Elliottラベル |
| `h4_elliot_label` | TEXT | No | H4最新Elliottラベル |
| `is_h1_wave_accepted` | INTEGER | Yes | H1波動条件通過 |
| `is_h4_wave_accepted` | INTEGER | Yes | H4波動条件通過 |
| `h1_gmma_trend_count` | INTEGER | No | H1 GMMA trend count |
| `h1_gmma_cross_count` | INTEGER | No | H1 GMMA cross count |
| `h1_ema200_direction` | TEXT | No | H1 EMA200方向。`BUY`、`SELL`または`NONE` |
| `h4_ema200_direction` | TEXT | No | H4 EMA200方向。`BUY`、`SELL`または`NONE` |
| `w1_ema200_direction` | TEXT | No | W1 EMA200方向。`BUY`、`SELL`または`NONE` |
| `h1_direction_alignment_mode` | TEXT | Yes | Runの固定方向一致モード |
| `is_h1_direction_alignment_passed` | INTEGER | Yes | W1からH1一致かつMN1方向またはW1 EMA200方向一致の場合1 |
| `analysis_snapshot_text` | TEXT | Yes | 追加診断値のCanonical Text |

主要条件はSQL検索できる個別列へ保存し、補足情報だけを`analysis_snapshot_text`へ保存します。Entry未評価時の`is_h1_wave_accepted`と`is_h4_wave_accepted`は0とし、波動条件NGとは`is_entry_evaluated`で区別します。未取得の方向はNULL、有効なEMA200中立は`NONE`とし、混同しません。判定ロジックの変更時も、既存行を再判定または上書きしません。

`is_strategy_entry = 1`でも、保有中、初期SL不正、SL幅超過など確定保存前の安全条件がNGなら`decision = 'SKIP'`となります。戦略Entry成立と実発注を同じフラグで表さず、安全条件が後から改善しても同じシグナルを再評価しません。BUY/SELL Decisionと`OPEN_PENDING`のcommit後に行う`OrderCheck()`が失敗した場合は、確定DecisionをSKIPへ変更せず、失敗EventとTradeの`OPEN_FAILED`へ記録します。シグナル消費は解除しません。

`analysis_snapshot_text`は`H1_EA_DECISION_V1`を先頭に、8.2と8.3の列（自身の`analysis_snapshot_text`列を除く）を表の順で`|列名=値`として連結します。未取得は`~`です。小数はpipsを1桁、価格を対象シンボルのDigits、ロットを2桁で固定します。`snapshot_hash`は識別子と保存時刻を除くDecision保存値、`analysis_version`および`analysis_input_hash`を同じ順で連結したUTF-8文字列のSHA-256です。

### 8.4 一意性

同一EAコンテキストでは1本のH1バーを1回だけ保存します。

```sql
CREATE UNIQUE INDEX idx_h1_ea_decisions_context_bar
ON h1_ea_decisions(context_key, h1_bar_time);
```

同一シグナルの再起動後の再消費を防ぎます。

```sql
CREATE UNIQUE INDEX idx_h1_ea_decisions_consumed_signal
ON h1_ea_decisions(
    context_key,
    signal_reference_time,
    signal_side
)
WHERE is_signal_consumed = 1;
```

次は`CREATE TABLE h1_ea_decisions (...)`内へ組み込む制約断片です。

```sql
CHECK(decision IN ('SKIP', 'BUY', 'SELL')),
CHECK(is_judge_matched IN (0, 1)),
CHECK(is_entry_evaluated IN (0, 1)),
CHECK(is_strategy_entry IN (0, 1)),
CHECK(is_signal_consumed IN (0, 1)),
CHECK(entry_count = 1),
CHECK(
    (is_judge_matched = 0 AND signal_count = 0)
    OR (is_judge_matched = 1 AND signal_count >= 1)
),
CHECK(
    (signal_count = 1 AND is_signal_consumed = 1 AND is_entry_evaluated = 1)
    OR (signal_count <> 1 AND is_signal_consumed = 0 AND is_entry_evaluated = 0)
),
CHECK(is_strategy_entry = 0 OR is_entry_evaluated = 1),
CHECK(
    is_judge_matched = 0 OR (
        signal_reference_time IS NOT NULL
        AND signal_reference_time > 0
        AND signal_side IS NOT NULL
        AND signal_side IN ('BUY', 'SELL')
    )
),
CHECK(
    decision = 'SKIP' OR (
        is_strategy_entry = 1
        AND is_signal_consumed = 1
        AND decision = signal_side
        AND initial_stop_loss IS NOT NULL
        AND initial_stop_loss > 0.0
    )
)
```

Judge初回成立時に波動条件や発注安全条件がNGなら、`SKIP`でも`is_signal_consumed = 1`として保存します。この行では初期SLのNULLを許可します。後続バーで同じJudgeが成立した場合は回数2以上、`is_signal_consumed = 0`、Entry未評価のSKIPを保存します。

`run_id`と`h1_bar_time`を消費済みシグナルの一意条件へ含めません。含めると、再起動またはバー更新によって同じシグナルを再注文できるためです。Alert照合用の`market_signal_key`を消費済みキーへ流用しません。

LIVEの同じH1バーでEAを再起動した場合、新RunへDecisionを複製しません。最初に保存したDecisionがそのバーの正本です。Run別の全バー件数を集計する場合は、この引継ぎ行が旧Runに所属することを考慮します。Testerは`context_key`へ`run_uid`を含むため、各Runが独立したDecisionを持ちます。

保存済み回数は同一コンテキスト・基準時刻・方向の`is_judge_matched = 1`行から復元します。Judge不成立バーが途中にあってもリセットしません。回数と初回消費は同じDecisionで記録し、確定保存の再試行では再加算しません。未保存状態の存在が分かっている場合は、DB行がないことを回数0の根拠にせず、新規Entryを停止して14章の障害処理を適用します。

検索用索引は次を用意します。

```sql
CREATE INDEX idx_h1_ea_decisions_bar
ON h1_ea_decisions(h1_bar_time, id);

CREATE INDEX idx_h1_ea_decisions_run_bar
ON h1_ea_decisions(run_id, h1_bar_time, id);

CREATE INDEX idx_h1_ea_decisions_result_bar
ON h1_ea_decisions(decision, h1_bar_time, id);

CREATE INDEX idx_h1_ea_decisions_reason_bar
ON h1_ea_decisions(reason_code, h1_bar_time, id);
```

## 9. `h1_ea_trades`

1回のエントリー試行から決済完了までを1行で表します。戦略Entryと確定保存前の安全条件を満たしたBUY/SELL Decisionだけが0または1行を持ちます。初回Judgeを消費しただけのSKIPにはTradeを作成しません。commit後の`OrderCheck()`失敗はTradeを`OPEN_FAILED`へ更新して保存します。

### 9.1 列

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `id` | INTEGER | Yes | 主キー |
| `created_run_id` | INTEGER | Yes | 取引行を作成したRunの外部キー |
| `decision_id` | INTEGER | No | Decision外部キー。回復行ではNULL可 |
| `context_key` | TEXT | Yes | EAコンテキスト |
| `origin` | TEXT | Yes | `NORMAL`または`RECOVERED` |
| `status` | TEXT | Yes | 取引状態 |
| `side` | TEXT | Yes | `BUY`または`SELL` |
| `requested_volume` | REAL | No | 発注要求ロット。回復行はNULL可 |
| `requested_stop_loss` | REAL | No | 発注要求SL。回復行はNULL可 |
| `entry_requested_server_time` | INTEGER | No | `TimeCurrent()`による発注要求時刻。回復行はNULL可 |
| `entry_order_ticket` | TEXT | No | 新規注文ticket |
| `entry_deal_ticket` | TEXT | No | 最初に確認した新規deal ticket |
| `entry_retcode` | INTEGER | No | 新規注文retcode |
| `position_identifier` | TEXT | No | 安定したPosition ID |
| `position_ticket` | TEXT | No | 現在のPosition Ticket |
| `opened_at_msc` | INTEGER | No | 最初のentry dealの`DEAL_TIME_MSC` |
| `open_price` | REAL | No | broker約定平均価格 |
| `opened_volume` | REAL | No | 成立数量 |
| `remaining_entry_volume` | REAL | No | 未約定の新規注文数量 |
| `current_stop_loss` | REAL | No | brokerで最後に確認したSL。Position消滅後も決済直前値を保持 |
| `stop_loss_source` | TEXT | Yes | `NONE`、`INITIAL_STOP_LOSS`、`H1_ZIGZAG_TRAIL`、`EXTERNAL`または`UNKNOWN` |
| `last_trail_evaluated_h1_bar_time` | INTEGER | No | 最後にトレイル評価を完了したH1バー時刻 |
| `pending_stop_loss_kind` | TEXT | No | `TRAIL_CANDIDATE`、`INITIAL_RESTORE`または`TRAIL_RESTORE` |
| `pending_stop_loss_h1_bar_time` | INTEGER | No | トレイル候補を登録・復元した評価H1バー時刻。初期SL復元ではNULL |
| `pending_stop_loss` | REAL | No | broker反映を未確認の保護SL候補 |
| `pending_stop_loss_pivot_time` | INTEGER | No | トレイル候補の基準にした1つ前の確定ZigZag点時刻。初期SL復元ではNULL |
| `pending_stop_loss_pivot_rate` | REAL | No | トレイル候補の基準にしたZigZag点価格。初期SL復元ではNULL |
| `pending_stop_loss_latest_time` | INTEGER | No | 基準点の確定確認に使用した最新点時刻。初期SL復元ではNULL |
| `pending_stop_loss_action_uid` | TEXT | No | broker結果を未確定のSL変更action。未送信時はNULL |
| `last_applied_trail_h1_bar_time` | INTEGER | No | 自EA actionで最後に反映確認した候補の評価H1バー時刻 |
| `last_applied_trail_stop_loss` | REAL | No | 自EA actionで最後に反映確認したトレイルSL |
| `last_applied_trail_pivot_time` | INTEGER | No | 自EAが最後に適用した候補の基準点時刻 |
| `last_applied_trail_pivot_rate` | REAL | No | 自EAが最後に適用した候補の基準点価格 |
| `last_applied_trail_latest_time` | INTEGER | No | 自EAが最後に適用した候補の確認点時刻 |
| `exit_requested_server_time` | INTEGER | No | `TimeCurrent()`による決済要求時刻 |
| `exit_order_ticket` | TEXT | No | 決済注文ticket |
| `exit_deal_ticket` | TEXT | No | 最後に確認した決済deal ticket |
| `exit_retcode` | INTEGER | No | 決済注文retcode |
| `closed_at_msc` | INTEGER | No | 最後のexit dealの`DEAL_TIME_MSC` |
| `close_price` | REAL | No | broker履歴から求めた決済平均価格 |
| `remaining_position_volume` | REAL | No | 部分決済後の残存数量 |
| `exit_intent_reason` | TEXT | No | EAが保護水準跨ぎの成行決済を要求した理由 |
| `close_reason` | TEXT | No | EA側で正規化した最終決済分類 |
| `broker_close_reason` | TEXT | No | broker deal理由。例：`SL`、`EXPERT`、`CLIENT` |
| `profit` | REAL | No | deal履歴の確定profit合計 |
| `commission` | REAL | No | commission合計 |
| `swap` | REAL | No | swap合計 |
| `fee` | REAL | No | fee合計 |
| `last_error` | TEXT | Yes | 最後の処理エラー。通常は空文字 |
| `created_at` | INTEGER | Yes | `TimeLocal()`による取引行作成時刻 |
| `updated_at` | INTEGER | Yes | `TimeLocal()`による最終更新時刻 |

### 9.2 状態

```text
OPEN_PENDING
OPEN_PARTIAL
OPEN
CLOSE_PENDING
CLOSE_PARTIAL
CLOSED
OPEN_FAILED
RECOVERY_REQUIRED
```

次は`CREATE TABLE h1_ea_trades (...)`内へカンマ区切りで組み込む制約断片です。

```sql
CHECK(origin IN ('NORMAL', 'RECOVERED'))
CHECK(side IN ('BUY', 'SELL'))
CHECK(stop_loss_source IN (
    'NONE',
    'INITIAL_STOP_LOSS',
    'H1_ZIGZAG_TRAIL',
    'EXTERNAL',
    'UNKNOWN'
))
CHECK(
    (
        current_stop_loss IS NULL
        AND stop_loss_source IN ('NONE', 'UNKNOWN')
    )
    OR (
        current_stop_loss IS NOT NULL
        AND current_stop_loss > 0.0
        AND stop_loss_source <> 'NONE'
    )
)
CHECK(last_trail_evaluated_h1_bar_time IS NULL
    OR last_trail_evaluated_h1_bar_time > 0)
CHECK(exit_intent_reason IS NULL OR exit_intent_reason IN (
    'INITIAL_STOP_LOSS_CROSSED',
    'H1_ZIGZAG_TRAIL_CROSSED'
))
CHECK(close_reason IS NULL OR close_reason IN (
    'INITIAL_STOP_LOSS',
    'INITIAL_STOP_LOSS_CROSSED',
    'H1_ZIGZAG_TRAIL',
    'EXTERNAL_STOP_LOSS',
    'UNKNOWN_STOP_LOSS',
    'H1_ZIGZAG_TRAIL_CROSSED',
    'EXTERNAL_CLOSE',
    'UNKNOWN_CLOSE'
))
CHECK(status IN (
    'OPEN_PENDING',
    'OPEN_PARTIAL',
    'OPEN',
    'CLOSE_PENDING',
    'CLOSE_PARTIAL',
    'CLOSED',
    'OPEN_FAILED',
    'RECOVERY_REQUIRED'
))
CHECK(pending_stop_loss_kind IS NULL OR pending_stop_loss_kind IN (
    'TRAIL_CANDIDATE',
    'INITIAL_RESTORE',
    'TRAIL_RESTORE'
))
CHECK(pending_stop_loss IS NULL
    OR pending_stop_loss_kind IS NOT NULL)
CHECK(
    (
        pending_stop_loss_kind IS NULL
        AND pending_stop_loss_h1_bar_time IS NULL
        AND pending_stop_loss IS NULL
        AND pending_stop_loss_pivot_time IS NULL
        AND pending_stop_loss_pivot_rate IS NULL
        AND pending_stop_loss_latest_time IS NULL
        AND pending_stop_loss_action_uid IS NULL
    )
    OR (
        pending_stop_loss_kind = 'INITIAL_RESTORE'
        AND pending_stop_loss_h1_bar_time IS NULL
        AND pending_stop_loss IS NOT NULL
        AND pending_stop_loss > 0.0
        AND pending_stop_loss_pivot_time IS NULL
        AND pending_stop_loss_pivot_rate IS NULL
        AND pending_stop_loss_latest_time IS NULL
    )
    OR (
        pending_stop_loss_kind IN ('TRAIL_CANDIDATE', 'TRAIL_RESTORE')
        AND pending_stop_loss_h1_bar_time IS NOT NULL
        AND pending_stop_loss_h1_bar_time > 0
        AND pending_stop_loss IS NOT NULL
        AND pending_stop_loss > 0.0
        AND pending_stop_loss_pivot_time IS NOT NULL
        AND pending_stop_loss_pivot_time > 0
        AND pending_stop_loss_pivot_rate IS NOT NULL
        AND pending_stop_loss_pivot_rate > 0.0
        AND pending_stop_loss_latest_time IS NOT NULL
        AND pending_stop_loss_latest_time > pending_stop_loss_pivot_time
    )
)
CHECK(
    (
        last_applied_trail_h1_bar_time IS NULL
        AND last_applied_trail_stop_loss IS NULL
        AND last_applied_trail_pivot_time IS NULL
        AND last_applied_trail_pivot_rate IS NULL
        AND last_applied_trail_latest_time IS NULL
    )
    OR (
        last_applied_trail_h1_bar_time IS NOT NULL
        AND last_applied_trail_h1_bar_time > 0
        AND last_applied_trail_stop_loss IS NOT NULL
        AND last_applied_trail_stop_loss > 0.0
        AND last_applied_trail_pivot_time IS NOT NULL
        AND last_applied_trail_pivot_time > 0
        AND last_applied_trail_pivot_rate IS NOT NULL
        AND last_applied_trail_pivot_rate > 0.0
        AND last_applied_trail_latest_time IS NOT NULL
        AND last_applied_trail_latest_time
            > last_applied_trail_pivot_time
    )
)
CHECK(pending_stop_loss_action_uid IS NULL
    OR (
        LENGTH(pending_stop_loss_action_uid) > 0
        AND pending_stop_loss IS NOT NULL
    ))
CHECK(pending_stop_loss IS NULL
    OR status IN ('OPEN', 'RECOVERY_REQUIRED')
    OR (status = 'OPEN_PARTIAL' AND pending_stop_loss_kind = 'INITIAL_RESTORE'))
CHECK(status <> 'CLOSED' OR (
    closed_at_msc IS NOT NULL
    AND closed_at_msc > 0
    AND close_reason IS NOT NULL
    AND LENGTH(close_reason) > 0
    AND broker_close_reason IS NOT NULL
    AND LENGTH(broker_close_reason) > 0
    AND pending_stop_loss IS NULL
))
```

pending保護SL候補は、未登録なら全列NULL、登録済みなら`pending_stop_loss_kind`と`pending_stop_loss`を必須とします。トレイル由来の2種はH1バーとZigZag情報も必須、初期SL復元はそれらを全列NULLとします。`OPEN_PARTIAL`は約定済み数量の初期保護を維持するため`INITIAL_RESTORE`だけを例外的に許可し、トレイル候補は許可しません。`pending_stop_loss_action_uid`は送信要求を確定してから結果を解決するまでだけ設定します。適用済みトレイル情報は全列NULLまたは全列有効のまとまりとして保存します。再試行時刻はプロセス内制御値（LIVEは`GetTickCount64()`、Testerは`TimeCurrent()`をミリ秒化したテスト内経過時間）のため保存せず、再起動時はbroker照合後に即時再試行できます。

正常なトレイル評価中とpending処理中はTradeの`status`を`OPEN`とします。例外は部分約定中の初期SL復元で、この場合だけ`OPEN_PARTIAL`を維持します。pendingまたは未完了actionを安全に断定できない場合は`RECOVERY_REQUIRED`へ移行し、新規注文、SL変更および成行決済を停止してbroker照合だけを行います。照合で状態を一意に確定し、必要なら保存済み初期SL・適用済みトレイルSLから構造上有効なpendingを再構成して、Tradeを`OPEN`または初期SL復元中の`OPEN_PARTIAL`へ戻すtransactionをcommitした後だけ送信を再開します。通常のbroker SL約定は明示的な成行決済要求を伴わないため、`OPEN`から直接`CLOSED`へ更新できます。候補跨ぎ成行決済を送信する場合だけ`CLOSE_PENDING`へ移行します。

### 9.3 制約と索引

```sql
CREATE UNIQUE INDEX idx_h1_ea_trades_decision
ON h1_ea_trades(decision_id)
WHERE decision_id IS NOT NULL;

CREATE UNIQUE INDEX idx_h1_ea_trades_active_context
ON h1_ea_trades(context_key)
WHERE status IN (
    'OPEN_PENDING',
    'OPEN_PARTIAL',
    'OPEN',
    'CLOSE_PENDING',
    'CLOSE_PARTIAL',
    'RECOVERY_REQUIRED'
);

CREATE UNIQUE INDEX idx_h1_ea_trades_position_identifier
ON h1_ea_trades(context_key, position_identifier)
WHERE position_identifier IS NOT NULL;
```

検索用索引は次を用意します。

```sql
CREATE INDEX idx_h1_ea_trades_status_updated
ON h1_ea_trades(status, updated_at, id);

CREATE INDEX idx_h1_ea_trades_context_updated
ON h1_ea_trades(context_key, updated_at, id);

CREATE INDEX idx_h1_ea_trades_closed
ON h1_ea_trades(closed_at_msc, id);

CREATE INDEX idx_h1_ea_trades_pending_stop_loss
ON h1_ea_trades(context_key, pending_stop_loss_h1_bar_time, id)
WHERE pending_stop_loss IS NOT NULL;
```

`RECOVERY_REQUIRED`は同一コンテキストのactive枠を維持します。broker Positionを発見しても別の回復行を追加せず、現在SL、SL設定元、pending候補および適用済み候補を既存のactive行へ再結合します。既存行へ安全に結合できない場合は`RECOVERY_REQUIRED`を維持し、新規注文、SL変更および成行決済を停止してbroker照合だけを行います。

## 10. `h1_ea_trade_events`

注文要求、受付結果、H1 ZigZagトレイル評価、SL変更、各deal、決済要求および回復処理を追記型で保存します。`h1_ea_trades`は現在状態、Eventは監査履歴です。

### 10.1 列

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `id` | INTEGER | Yes | 主キー |
| `trade_id` | INTEGER | Yes | Trade外部キー |
| `run_id` | INTEGER | Yes | Eventを保存したRunの外部キー |
| `event_uid` | TEXT | Yes | 冪等保存用の一意ID |
| `action_uid` | TEXT | No | 同じEntry、ExitまたはSL変更試行の要求と結果を関連付けるID |
| `sequence` | INTEGER | Yes | 同一Trade内の1始まり連番 |
| `event_type` | TEXT | Yes | Event種別 |
| `event_source` | TEXT | Yes | `EA`、`CALLBACK`または`RECONCILIATION` |
| `server_time` | INTEGER | No | 要求時などのbroker server時刻 |
| `broker_time_msc` | INTEGER | No | brokerが提供したorder/deal時刻 |
| `recorded_at` | INTEGER | Yes | `TimeLocal()`による保存時刻 |
| `transaction_type` | INTEGER | No | `MqlTradeTransaction.type` |
| `order_ticket` | TEXT | No | Order Ticket |
| `deal_ticket` | TEXT | No | Deal Ticket |
| `deal_scope_key` | TEXT | No | 実行scopeを含むDeal一意キー |
| `position_identifier` | TEXT | No | Position ID |
| `position_ticket` | TEXT | No | SL変更またはEvent対象のPosition Ticket |
| `side` | TEXT | No | `BUY`または`SELL` |
| `volume` | REAL | No | 要求または約定数量 |
| `price` | REAL | No | 要求または約定価格 |
| `h1_bar_time` | INTEGER | No | トレイル評価対象H1バー時刻 |
| `pivot_bar_time` | INTEGER | No | トレイル基準ZigZag点時刻 |
| `pivot_rate` | REAL | No | トレイル基準ZigZag点価格 |
| `latest_point_bar_time` | INTEGER | No | 基準点の確定確認に使用した最新点時刻 |
| `previous_stop_loss` | REAL | No | SL変更前にbrokerで確認したSL |
| `stop_loss` | REAL | No | トレイル評価候補または保護SL変更要求値 |
| `confirmed_stop_loss` | REAL | No | `SL_MODIFY_RESULT`でbrokerから再取得した実SL |
| `is_confirmed_stop_loss_present` | INTEGER | No | `SL_MODIFY_RESULT`でSLありなら1、SLなしを正常取得した場合は0 |
| `stop_loss_action_kind` | TEXT | No | SL変更要求・結果の`TRAIL_CANDIDATE`、`INITIAL_RESTORE`または`TRAIL_RESTORE` |
| `stop_loss_source` | TEXT | No | Event時点のSL設定元 |
| `trail_skip_reason` | TEXT | No | トレイル非採用理由。採用時はNULL |
| `retcode` | INTEGER | No | 注文結果retcode |
| `exit_intent_reason` | TEXT | No | EA内部の決済理由 |
| `close_reason` | TEXT | No | EA側で正規化した最終決済分類 |
| `broker_reason` | TEXT | No | `DEAL_REASON`またはorder理由 |
| `recovery_issue_code` | TEXT | No | Recoveryで検出した不整合コード |
| `quarantined_pending_text` | TEXT | No | 構造不正pendingのclear前Canonical Text |
| `message` | TEXT | Yes | 補足。通常は空文字 |

`event_type`は初版で次を使用します。

```text
ENTRY_REQUEST
ENTRY_RESULT
TRAIL_EVALUATION
SL_MODIFY_REQUEST
SL_MODIFY_RESULT
DEAL_ADD
EXIT_REQUEST
EXIT_RESULT
RECOVERY
ERROR
```

次は`CREATE TABLE h1_ea_trade_events (...)`内へカンマ区切りで組み込む制約断片です。

```sql
CHECK(event_type IN (
    'ENTRY_REQUEST',
    'ENTRY_RESULT',
    'TRAIL_EVALUATION',
    'SL_MODIFY_REQUEST',
    'SL_MODIFY_RESULT',
    'DEAL_ADD',
    'EXIT_REQUEST',
    'EXIT_RESULT',
    'RECOVERY',
    'ERROR'
))
CHECK(event_source IN ('EA', 'CALLBACK', 'RECONCILIATION'))
CHECK(LENGTH(event_uid) > 0)
CHECK(sequence > 0)
CHECK(recorded_at > 0)
CHECK(side IS NULL OR side IN ('BUY', 'SELL'))
CHECK(stop_loss_source IS NULL OR stop_loss_source IN (
    'NONE',
    'INITIAL_STOP_LOSS',
    'H1_ZIGZAG_TRAIL',
    'EXTERNAL',
    'UNKNOWN'
))
CHECK(stop_loss_action_kind IS NULL OR stop_loss_action_kind IN (
    'TRAIL_CANDIDATE',
    'INITIAL_RESTORE',
    'TRAIL_RESTORE'
))
CHECK(
    (
        pivot_bar_time IS NULL
        AND pivot_rate IS NULL
        AND latest_point_bar_time IS NULL
    )
    OR (
        pivot_bar_time IS NOT NULL
        AND pivot_bar_time > 0
        AND pivot_rate IS NOT NULL
        AND pivot_rate > 0.0
        AND latest_point_bar_time IS NOT NULL
        AND latest_point_bar_time > pivot_bar_time
    )
)
CHECK(exit_intent_reason IS NULL OR exit_intent_reason IN (
    'INITIAL_STOP_LOSS_CROSSED',
    'H1_ZIGZAG_TRAIL_CROSSED'
))
CHECK(close_reason IS NULL OR close_reason IN (
    'INITIAL_STOP_LOSS',
    'INITIAL_STOP_LOSS_CROSSED',
    'H1_ZIGZAG_TRAIL',
    'EXTERNAL_STOP_LOSS',
    'UNKNOWN_STOP_LOSS',
    'H1_ZIGZAG_TRAIL_CROSSED',
    'EXTERNAL_CLOSE',
    'UNKNOWN_CLOSE'
))
CHECK(event_type <> 'TRAIL_EVALUATION' OR (
    h1_bar_time IS NOT NULL
    AND h1_bar_time > 0
    AND (
        (
            trail_skip_reason IS NULL
            AND stop_loss IS NOT NULL
            AND stop_loss > 0.0
            AND pivot_bar_time IS NOT NULL
            AND pivot_bar_time > 0
            AND pivot_rate IS NOT NULL
            AND pivot_rate > 0.0
            AND latest_point_bar_time IS NOT NULL
            AND latest_point_bar_time > pivot_bar_time
        )
        OR (
            trail_skip_reason IS NOT NULL
            AND LENGTH(trail_skip_reason) > 0
        )
    )
))
CHECK(event_type NOT IN (
    'ENTRY_REQUEST',
    'ENTRY_RESULT',
    'SL_MODIFY_REQUEST',
    'SL_MODIFY_RESULT',
    'EXIT_REQUEST',
    'EXIT_RESULT'
) OR (
    action_uid IS NOT NULL
    AND LENGTH(action_uid) > 0
))
CHECK(action_uid IS NULL OR event_type IN (
    'ENTRY_REQUEST',
    'ENTRY_RESULT',
    'SL_MODIFY_REQUEST',
    'SL_MODIFY_RESULT',
    'EXIT_REQUEST',
    'EXIT_RESULT'
))
CHECK(event_type NOT IN ('SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT') OR (
    action_uid IS NOT NULL
    AND LENGTH(action_uid) > 0
    AND position_identifier IS NOT NULL
    AND LENGTH(position_identifier) > 0
    AND position_ticket IS NOT NULL
    AND LENGTH(position_ticket) > 0
    AND stop_loss IS NOT NULL
    AND stop_loss > 0.0
    AND stop_loss_action_kind IS NOT NULL
))
CHECK(event_type NOT IN ('SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT') OR (
    (
        stop_loss_action_kind = 'INITIAL_RESTORE'
        AND h1_bar_time IS NULL
        AND pivot_bar_time IS NULL
        AND pivot_rate IS NULL
        AND latest_point_bar_time IS NULL
    )
    OR (
        stop_loss_action_kind IN ('TRAIL_CANDIDATE', 'TRAIL_RESTORE')
        AND h1_bar_time IS NOT NULL
        AND h1_bar_time > 0
        AND pivot_bar_time IS NOT NULL
        AND pivot_bar_time > 0
        AND pivot_rate IS NOT NULL
        AND pivot_rate > 0.0
        AND latest_point_bar_time IS NOT NULL
        AND latest_point_bar_time > pivot_bar_time
    )
))
CHECK(event_type = 'SL_MODIFY_RESULT' OR (
    confirmed_stop_loss IS NULL
    AND is_confirmed_stop_loss_present IS NULL
))
CHECK(event_type <> 'SL_MODIFY_RESULT' OR (
    is_confirmed_stop_loss_present IS NOT NULL
    AND (
        (
            is_confirmed_stop_loss_present = 1
            AND confirmed_stop_loss IS NOT NULL
            AND confirmed_stop_loss > 0.0
        )
        OR (
            is_confirmed_stop_loss_present = 0
            AND confirmed_stop_loss IS NULL
        )
    )
))
CHECK(event_type IN ('SL_MODIFY_REQUEST', 'SL_MODIFY_RESULT')
    OR stop_loss_action_kind IS NULL)
CHECK(
    (
        recovery_issue_code IS NULL
        AND quarantined_pending_text IS NULL
    )
    OR (
        event_type = 'RECOVERY'
        AND recovery_issue_code IS NOT NULL
        AND LENGTH(recovery_issue_code) > 0
        AND quarantined_pending_text IS NOT NULL
        AND LENGTH(quarantined_pending_text) > 0
    )
)
CHECK(event_type <> 'DEAL_ADD' OR (
    deal_ticket IS NOT NULL
    AND LENGTH(deal_ticket) > 0
    AND deal_scope_key IS NOT NULL
    AND LENGTH(deal_scope_key) > 0
    AND broker_time_msc IS NOT NULL
    AND broker_time_msc > 0
    AND position_identifier IS NOT NULL
    AND LENGTH(position_identifier) > 0
    AND side IS NOT NULL
    AND broker_reason IS NOT NULL
    AND LENGTH(broker_reason) > 0
))
```

`SL_MODIFY_REQUEST`では`stop_loss`へ要求候補、`stop_loss_action_kind`へ要求種別を保存し、確認結果2列はNULLとします。`SL_MODIFY_RESULT`では同じ要求候補・種別に加え、broker照合でSLありを確認した場合は`is_confirmed_stop_loss_present = 1`と実SL、SLなしを確認した場合は`is_confirmed_stop_loss_present = 0`と`confirmed_stop_loss = NULL`を保存します。要求の成功・失敗とSLの有無を正常取得できた場合だけResultを作成します。broker照合自体が失敗した場合はResultを作らず、actionを未完了のまま`RECOVERY_REQUIRED`として再照合します。

応答不明・受付中のSL要求では、旧SLを読み取れた事実だけを失敗Resultにしません。遅延反映を否定できないため、候補の反映または当該要求への終端応答を確認するまで未完了actionを維持します。

### 10.2 一意性と索引

```sql
CREATE UNIQUE INDEX idx_h1_ea_trade_events_event_uid
ON h1_ea_trade_events(event_uid);

CREATE UNIQUE INDEX idx_h1_ea_trade_events_trade_sequence
ON h1_ea_trade_events(trade_id, sequence);

CREATE UNIQUE INDEX idx_h1_ea_trade_events_deal_scope
ON h1_ea_trade_events(deal_scope_key)
WHERE deal_scope_key IS NOT NULL;

CREATE UNIQUE INDEX idx_h1_ea_trade_events_action_type
ON h1_ea_trade_events(action_uid, event_type)
WHERE action_uid IS NOT NULL;

CREATE UNIQUE INDEX idx_h1_ea_trade_events_trail_bar
ON h1_ea_trade_events(trade_id, event_type, h1_bar_time)
WHERE event_type = 'TRAIL_EVALUATION';

CREATE INDEX idx_h1_ea_trade_events_trade_time
ON h1_ea_trade_events(trade_id, broker_time_msc, id);

CREATE INDEX idx_h1_ea_trade_events_run_recorded
ON h1_ea_trade_events(run_id, recorded_at, id);
```

Dealのscopeは次のとおりです。

```text
LIVE   : LIVE|server|login|deal_ticket
TESTER : TESTER|run_uid|deal_ticket
```

`DEAL_ADD`の`event_uid`は`deal_scope_key`と同じ値にし、callbackと再起動照合で共通化します。

`TRAIL_EVALUATION`は`H1_EA_TRAIL_EVALUATION_V1|context_key|trade_id|h1_bar_time`を`event_uid`とします。同じTradeとH1バーの評価を再実行してもEventを重複追加しません。

Entry、ExitおよびSL変更は、送信前に`H1_EA_ACTION_V1|run_uid|trade_id|action_type|local_action_sequence`を`action_uid`として確定します。`local_action_sequence`は同一Runのプロセス内で1から単調増加させ、DB障害時もメモリキューへ同じ値を保持します。要求Eventの`event_uid`は`action_uid|REQUEST`、結果Eventは`action_uid|RESULT`とし、再試行保存でも同じUIDを使用します。

通常経路では、有効Leaseの確認、要求Eventの追加およびTrade snapshot更新を同一transactionでcommitした後だけbrokerへ送信します。DB障害時の制限経路では、新しく確定した`action_uid`、要求Eventおよび意図をメモリキューと運用ログへ保持し、排他Lockと最後に確認したLeaseの安全期限内だけリスク低減操作を許可します。プロセスが終了すると未保存actionは失われ、次回起動時はbroker現在SLを復旧しても設定元を断定できなければ`UNKNOWN`とします。

`RECOVERY`は、照合対象の現在order、履歴order、deal、Position、現在SL、SL設定元、pending・適用済み候補、最終評価バーおよび未完了`action_uid`を固定順で連結した`snapshot_hash`を作り、`H1_EA_RECOVERY_V1|context_key|trade_id|snapshot_hash`を`event_uid`とします。同じbroker・Trade状態の再照合は重複保存せず、状態が変化した場合だけ新しいEventになります。

Recovery snapshotは`H1_EA_RECOVERY_SNAPSHOT_V1`を先頭に、次の順で連結します。

```text
context_key, trade_id, status,
position_identifier, position_ticket, side, position_volume,
current_stop_loss, stop_loss_source,
pending_stop_loss_kind, pending_stop_loss_h1_bar_time,
pending_stop_loss, pending_stop_loss_pivot_time,
pending_stop_loss_pivot_rate, pending_stop_loss_latest_time,
pending_stop_loss_action_uid,
last_applied_trail_h1_bar_time, last_applied_trail_stop_loss,
last_applied_trail_pivot_time, last_applied_trail_pivot_rate,
last_applied_trail_latest_time, last_trail_evaluated_h1_bar_time,
active_orders, history_orders, deals, unresolved_actions,
recovery_issue_code, quarantined_pending_text
```

各値は`|field#<UTF-8 byte length>=<value>`形式とし、NULLは`~`、真偽値と整数は10進、価格はsymbolのDigits、volumeは8桁で固定します。orderとdealはticket昇順、未完了actionは`action_uid`昇順で並べ、各要素も同じlength prefix形式にします。構造不正なpendingを隔離する場合は、clear前の各列名・SQLite型・値を固定列順の`quarantined_pending_text`へ入れます。`quarantined_pending_text`は上記Recovery snapshotを構成する1フィールドであり、単独ではハッシュしません。`snapshot_hash`は、`H1_EA_RECOVERY_SNAPSHOT_V1`から最後の`quarantined_pending_text`までを含むRecovery snapshot全体のCanonical TextをUTF-8化したSHA-256です。

`sequence`は同じTrade内で`MAX(sequence) + 1`をtransaction内で採番します。Event追加とTrade更新を同一transactionで行います。

## 11. 保存処理

### 11.1 起動

1. DB接続とスキーマを確認する
2. 単一transactionで同一コンテキストのLeaseを確認する
3. 同じtransactionで期限切れRunだけを`INTERRUPTED`へ更新し、今回Runを`RUNNING`で追加してLeaseを取得する
4. brokerとactive取引をPosition Ticket単位で照合する
5. brokerの現在SLとpending・適用済みトレイル候補を照合する
6. 現在H1バーの確定Decisionと、保存済みJudge回数・消費済みシグナルを復元する。Tradeを持たないSKIPも対象とする

現在H1バーが保存済みならEntryを再評価しません。未保存かつ未保存状態の欠落が疑われない場合は、次の既存互換の評価機会から進行中バーを対象にします。旧Runが終了したことを理由にJudge回数を0へ戻しません。この再起動永続化は既存インジケータのメモリ内`SignalCount`に対する安全上の拡張であり、再起動を挟んだ動作まで完全一致させる仕様ではありません。

`OPEN_PENDING`でPositionがない場合、現在order、履歴orderおよびdealを確認します。orderが有効なら`OPEN_PENDING`を維持し、orderが終端状態かつdealもPositionもない場合だけ`OPEN_FAILED`へ更新します。判定不能なら`RECOVERY_REQUIRED`へ移行します。

active Positionとpending保護SL候補がある場合は次のように照合します。

- 未完了`pending_stop_loss_action_uid`があれば、そのbroker結果の確定を新しいH1評価より先に行う
- broker SLが候補以上に保護側で自EAのSL変更actionと一致する場合、pending種別が`TRAIL_CANDIDATE`または`TRAIL_RESTORE`なら適用済み候補と`stop_loss_source = 'H1_ZIGZAG_TRAIL'`を更新し、`INITIAL_RESTORE`なら`stop_loss_source = 'INITIAL_STOP_LOSS'`を更新する
- broker SLが候補以上に保護側でも自EA actionと結び付かない場合は、`current_stop_loss`へ実SLを保存してpendingだけを解除し、適用済み候補は更新しない。broker transactionや保存済み変更元情報から手動・他EAを積極的に確認できた場合だけ`EXTERNAL`、由来を証明できない場合は`UNKNOWN`とする
- broker SLが候補未達または未設定ならpendingを維持し、Lease確認後に再試行する
- BUYのBidまたはSELLのAskが候補を既に跨いでいれば、`INITIAL_RESTORE`は`INITIAL_STOP_LOSS_CROSSED`、トレイル由来の2種は`H1_ZIGZAG_TRAIL_CROSSED`の決済へ移行する

候補以上の判定は、BUYで`broker SL >= 候補 - 0.5 tick`、SELLで`broker SL <= 候補 + 0.5 tick`とします。自EA actionとの価格一致も同じ許容差を使用します。

再起動時の再試行時刻は保存値から復元せず、broker照合後に即時実行できます。未完了のSL変更要求は、broker PositionとSLの有無を正常取得して成功または未反映を断定できる場合だけ、`SL_MODIFY_RESULT`を`RECONCILIATION`として補完します。SLなしを確認した場合も`is_confirmed_stop_loss_present = 0`としてResultを作成できます。broker照合自体が失敗した場合はactionを未完了のまま`RECOVERY_REQUIRED`とし、再照合します。

`CLOSE_PENDING`または`CLOSE_PARTIAL`でPositionが残る場合は、有効な決済注文があれば待機し、注文が終端済みで残Positionがあれば最短1秒後に再決済します。`OPEN`またはpendingありでPositionが消滅し、決済dealを確認できる場合は履歴を集計してpendingを解除し`CLOSED`へ更新します。

pending候補のPosition Identifierまたは方向が現在Positionと一致しない場合は送信しません。構造上は有効でもbroker照合を断定できないpendingは保持して`RECOVERY_REQUIRED`とします。種別と必須項目の組合せ不正、価格単位不正または複数のpending相当状態を検出した場合は、生の列名・型・値をCanonical TextとしてRecovery Eventの`recovery_issue_code`と`quarantined_pending_text`へ隔離し、構造化pending列を全NULLにする処理と`RECOVERY_REQUIRED`への移行を同一transactionで保存します。どちらも新規注文、SL変更および成行決済を停止し、broker照合だけを行います。

### 11.2 H1判定

- Testerの`TESTER_TRADE_START_TIME`より前はH1バーごとに1回の履歴準備確認だけを行い、Entry用の完全分析および以下のJudge・Decision・新規Entry保存処理へ進みません。0ならこの制限はなく、LIVEにも適用しません。履歴不足はTF別の本数・同期・最古日時をINFOログへ初回に出し、状態変化時は最短1時間間隔、状態不変の再通知は24時間間隔、分析再開時は1回とします。不足系列への履歴再取得要求は最短60秒間隔です。MN1の61本／W1からH1の各206本の準備条件は変えません。
- LIVEは起動1秒後を初回とし、以降30秒間隔の評価機会でEntry用分析を行います。Testerではtickを契機とします。すでに確定DecisionがDBにある、または同一プロセスのメモリに保存待ちの確定判定があるH1バーは、再分析・再評価・Judge回数の再加算をしません。
- 対象H1バーの最初の分析成功時に、保有・注文待ちの有無にかかわらずJudgeを評価します。Judge成立時は基準時刻・方向ごとの回数を加算し、初回だけH1/H4のEntry波動条件を評価します。
- 初回Judge成立は波動条件NGまたはEA発注安全条件NGでも消費します。最終Decisionは`SKIP`として、拒否理由、回数1、`is_entry_evaluated = 1`および`is_signal_consumed = 1`を保存します。既存戦略だけは成立していた場合、`is_strategy_entry = 1`を残します。
- 同じシグナルのJudge成立2回目以降は回数だけを加算し、`SKIP / SIGNAL_ALREADY_CONSUMED`、Entry未評価・`is_signal_consumed = 0`として保存します。途中のJudge不成立で回数をリセットしません。
- Judge未成立は回数0・未消費の`SKIP`と理由コードを保存します。分析失敗時はまだ確定Decisionを作らず同じバーを再試行し、失敗を運用ログへ残します。成功せずバーが変わった場合だけ前バーを`SKIP / ANALYSIS_UNAVAILABLE`で確定し、過去バーのEntryは実行しません。
- 保有、pending取引、候補跨ぎ決済中またはその他の安全条件NGは発注を禁止しますが、成功した分析からの戦略判定と初回消費を取り消しません。安全条件が改善しても後続の評価機会へ注文を繰り延べません。
- Judge回数・初回消費を含む確定Decisionは、Lease所有確認と同一transactionで保存します。発注可能な初回Entryの場合だけ、Tradeの`OPEN_PENDING`、`ENTRY_REQUEST`および`action_uid`も同じtransactionへ含めます。SKIPにはTrade/Eventを作成しません。
- transactionをcommitできるまで`OrderSend()`を実行しません。commit前の保存失敗はrollbackし、同一プロセスでは確定判定を再加算せず保持します。復旧後に保存できても、失った評価機会の注文を遅延送信しません。

トレイル評価はEntryの評価待ちと独立して次のように保存します。

- H1新規バー最初のtickを契機に分析し、Entryポーリング完了を待たずにトレイルを評価します。同一H1バーの分析時刻が異なる場合もそれぞれの判定時刻を保持します。
- Tradeが`OPEN`の場合だけH1 ZigZagトレイルを評価します。`OPEN_PARTIAL`では初期SLを維持し、残注文の終端確認を優先します。
- `pending_stop_loss_kind = 'INITIAL_RESTORE'`の間は新しいトレイル候補を作らず、`INITIAL_STOP_LOSS_RESTORE_PENDING`として見送ります。
- トレイル評価を1 Trade・H1バーにつき1件の`TRAIL_EVALUATION`として保存します。トレイル側の分析失敗も見送り理由を保存しますが、これだけでEntry側のバーを処理済みにしません。
- H1バーごとの採用または見送りをトレイル評価Eventへ保存し、`last_trail_evaluated_h1_bar_time`を更新します。新しい`TRAIL_CANDIDATE`を採用した場合だけpending候補も同一transactionで登録します。`INITIAL_RESTORE`と`TRAIL_RESTORE`の登録そのものには`TRAIL_EVALUATION`を作成しません。
- `INITIAL_RESTORE`以外では、現在broker SLより1tick以上保護側であり、かつpendingがある場合はそのpendingよりも1tick以上保護側の候補だけでpendingを置き換えます。`INITIAL_RESTORE`は新規トレイル候補で置き換えません。
- `pending_stop_loss_action_uid`が未完了の場合は新候補へ置き換えず、`SL_MODIFY_ACTION_PENDING`として見送ります。

### 11.3 新規約定

- `OnTradeTransaction()`のdeal追加を契機にします。
- brokerのorder、dealおよびpositionを読み直します。
- Event追加とTrade snapshot更新を同一transactionで行います。
- 一部約定と残注文がある場合は`OPEN_PARTIAL`、全量成立後は`OPEN`へ更新します。
- Entryが部分約定した場合は残注文を取消要求し、不足数量を同じシグナルで再発注しません。
- 残注文が終端となりPositionが残る場合は実約定数量を採用して`OPEN`、Positionがなければ`OPEN_FAILED`へ更新します。
- 同じ通知を再処理しても結果が変わらないようにします。

Position成立を確認した時点で、対象Position Ticketからbroker SLを読み直します。要求した初期SLと0.5 tick以内で一致し、Entry actionへ対応付けられる場合は`current_stop_loss`と`stop_loss_source = 'INITIAL_STOP_LOSS'`を、Deal EventおよびTrade snapshotと同一transactionで保存します。より保護的なSLでも、broker transactionや保存済み変更元情報から手動・他EAを積極的に確認できた場合だけ`EXTERNAL`とし、由来を証明できなければ`UNKNOWN`とします。broker SLが未設定または保存済み初期SLより緩い場合は、ZigZag情報を持たない`INITIAL_RESTORE`のpending保護SL候補として初期SLを登録し、その復元を優先してトレイル評価を開始しません。回復Entryも同じ規則で分類します。

### 11.4 H1 ZigZagトレイル

`TRAIL_EVALUATION`はH1バーごとの採用・見送りを保存します。broker整合で`INITIAL_RESTORE`または`TRAIL_RESTORE`を登録する場合は、Recovery EventとTradeのpending更新を同一transactionで保存し、復元登録を理由に`TRAIL_EVALUATION`を追加しません。同じH1バーに通常の見送りEventが存在しても、復元Eventとは別の監査事実です。

pending保護SL候補がある場合は次の順で処理します。

1. Tradeが`OPEN`、または初期SL復元に限り`OPEN_PARTIAL`で、`pending_stop_loss_action_uid`が未完了でないことを確認する
2. brokerの現在SL、Position Ticket、BUYのBidまたはSELLのAskを再取得する
3. broker SLが候補以上に保護済みなら、実SLと設定元を保存してSL変更を送信せずpendingを解除する
4. 候補を価格が跨いでいれば、pending種別に対応するcross理由、Lease確認、`CLOSE_PENDING`、`EXIT_REQUEST`、Exit用`action_uid`およびpending解除を同一transactionで保存し、commit後に成行決済する
5. Stops/Freeze距離を満たさなければpendingを維持する
6. 有効Leaseの確認、`SL_MODIFY_REQUEST`、`action_uid`および`pending_stop_loss_action_uid`を同一transactionで保存してcommitする
7. 対象Position Ticketを明示してSL変更を送信する
8. broker Positionを再取得し、候補以上に保護されたことを確認する
9. 確定した結果に応じて`SL_MODIFY_RESULT`とTrade snapshotを同一transactionで保存する

`OrderSend()`の戻り値だけでSL反映済みとはしません。結果確定時は次のように更新します。

- broker SLが候補以上で、自EA actionと一致する場合は`current_stop_loss`を更新する。`TRAIL_CANDIDATE`または`TRAIL_RESTORE`なら`stop_loss_source = 'H1_ZIGZAG_TRAIL'`と適用済み候補も更新し、`INITIAL_RESTORE`なら`stop_loss_source = 'INITIAL_STOP_LOSS'`だけを更新して、pendingと`pending_stop_loss_action_uid`を解除する
- より保護的な外部・由来不明SLで候補を満たした場合は、`current_stop_loss`と判定可能な設定元だけを更新し、適用済み候補を変更せずpendingとactionを解除する。`EXTERNAL`と`UNKNOWN`の判定は11.1と11.3の規則に従う
- 送信失敗またはbroker再確認で未反映を確定できた場合は、失敗ResultへSLあり・なしと実SLを保存し、actionだけを解除してpendingを維持する。SLなしなら`current_stop_loss = NULL`、`stop_loss_source = 'NONE'`とする
- broker PositionまたはSLの有無を取得できず結果を断定できない場合は、Resultを作らずactionを未完了のまま`RECOVERY_REQUIRED`とする

Stops/Freeze距離不足または確定した変更失敗ではpendingを維持し、毎ティック確認して最短1秒間隔で再試行します。より保護的な外部SLが存在する場合は維持し、EAから緩めません。

broker SLが削除された、または保存済み保護水準より緩い場合は、未完了actionを先に照合し、初期SL、最後に適用したトレイルSLおよび既存の有効なpending候補から最も保護側の水準を選びます。初期SLなら`INITIAL_RESTORE`、適用済みトレイルSLなら`TRAIL_RESTORE`、既存pending自身ならその種別のままpending保護SL候補として保持・復元します。新規または変更した復元pendingはRecovery Eventと同一transactionで保存します。価格が復元水準を既に跨いでいる場合は成行決済へ移行します。

### 11.5 決済

- broker SL約定は明示的なExit要求なしで検出し、Position消滅後にpending候補と未完了SL actionを解除して`OPEN`から`CLOSED`へ更新できます。未完了actionのEvent履歴は削除せず、遅れて到着した結果でCLOSED Tradeを再度変更しません。
- 候補跨ぎ成行決済は、有効Leaseの確認、pending種別に対応する`exit_intent_reason`、`CLOSE_PENDING`、`EXIT_REQUEST`、Exit用`action_uid`、pending候補と`pending_stop_loss_action_uid`の解除を同一transactionで保存し、commit後に送信します。候補情報は`EXIT_REQUEST`へ保持します。
- `CLOSE_PENDING`または`CLOSE_PARTIAL`ではトレイル評価とSL変更を実行しません。
- DB保存失敗時でも、排他Lockを保持し、既知Leaseの安全期限内なら保有リスクを減らすSL変更または決済要求を継続します。
- Position消滅後、`HistorySelect()`と`DEAL_POSITION_ID`で全dealを取得します。
- 候補跨ぎ成行決済の一部約定後にPositionが残る場合は`CLOSE_PARTIAL`へ更新します。
- 有効な決済注文がなければ、最短1秒間隔で残存全量の成行決済を再試行します。
- 決済価格、profit、commission、swapおよびfeeを再集計し、Position消滅後に`CLOSED`へ更新します。

最終`close_reason`は、決済直前に永続化した`stop_loss_source`、`exit_intent_reason`およびbroker deal理由から次の優先順で決定します。

1. `exit_intent_reason = 'INITIAL_STOP_LOSS_CROSSED'`なら`INITIAL_STOP_LOSS_CROSSED`
2. `exit_intent_reason = 'H1_ZIGZAG_TRAIL_CROSSED'`なら`H1_ZIGZAG_TRAIL_CROSSED`
3. broker理由が`SL`かつ設定元が`INITIAL_STOP_LOSS`なら`INITIAL_STOP_LOSS`
4. broker理由が`SL`かつ設定元が`H1_ZIGZAG_TRAIL`なら`H1_ZIGZAG_TRAIL`
5. broker理由が`SL`かつ設定元が`EXTERNAL`なら`EXTERNAL_STOP_LOSS`
6. broker理由が`SL`かつ設定元を断定できなければ`UNKNOWN_STOP_LOSS`
7. その他の外部決済は`EXTERNAL_CLOSE`、断定不能は`UNKNOWN_CLOSE`

gapを含む約定価格だけからSL設定元を推測しません。

Tradeの`close_reason`と`broker_close_reason`は、Positionを消滅させた最後のExit dealの分類を保存します。手動部分決済後にトレイルSLで残量が閉じるなど、複数の決済理由がある場合も、すべての理由と数量は各`DEAL_ADD` Eventへ保持します。

### 11.6 終了

- 正常終了はRunを`STOPPED`へ更新します。
- 初期化途中の失敗は可能なら`FAILED`へ更新します。
- DB更新不能の場合はテキスト運用ログへ残します。

## 12. Transaction

次は必ず単一transactionで保存します。

- Lease所有確認と、Judge成立回数・初回消費を含む確定Decision。初回波動NGまたはEA安全条件NGのSKIPも消費する
- 発注可能な初回Entryでは、上記Decisionに加え`OPEN_PENDING`、`ENTRY_REQUEST`およびaction確定
- H1バーの`TRAIL_EVALUATION`、最終評価バーおよび、採用時だけ`TRAIL_CANDIDATE`の登録・置換
- Recovery Eventと、`INITIAL_RESTORE`・`TRAIL_RESTORE`の登録または構造不正pendingの隔離・解除
- Lease所有確認、`SL_MODIFY_REQUEST`、一意な`action_uid`およびpending actionの確定
- `SL_MODIFY_RESULT`、brokerで確認したSL有無・実SL、SL設定元およびpending actionの解決。適用成功時だけ適用済み候補とpending解除を含む
- Lease所有確認、候補跨ぎの`CLOSE_PENDING`・`EXIT_REQUEST`、pending候補・action解除
- Trade Event追加とTrade snapshot更新
- broker照合によるTradeと回復Eventの更新
- 決済履歴集計、決済理由、決済Eventと`CLOSED`更新
- schema migrationの全処理

途中で失敗した場合はrollbackし、部分的な状態を残しません。`SQLITE_BUSY`相当の失敗では接続を再確認し、注文前なら新規注文を停止します。

## 13. 冪等性とbroker照合

- 市場シグナルの初回Judge消費は`context_key`、`signal_reference_time`および`signal_side`で一意にします。回数2以上の確定Decisionは後続H1バーへ保存できますが、Entryは再評価しません。
- Positionは`POSITION_IDENTIFIER`および`DEAL_POSITION_ID`で関連付けます。
- ticketとMagicはTEXTで保存します。
- broker由来の約定結果はbroker履歴を正本とします。
- 同じH1バー、同じトレイル評価、同じSL変更結果、同じdeal通知および同じ再起動照合を複数回実行しても、行を重複追加しません。
- brokerをPosition、現在SL、orderおよびdealの正本とし、DBをpending候補、基準点、SL設定元およびEA内部意図の正本とします。
- DBとbrokerが矛盾する場合はbrokerの取引事実を優先し、DB固有情報を価格から推測せず、補完不能なら`RECOVERY_REQUIRED`にします。

`OnTradeTransaction()`で差分金額を単純加算しません。通知ごとに`DEAL_POSITION_ID`へ紐づく全dealを再取得し、Tradeの集約値を置換します。Entry、Exit、`DEAL_ENTRY_INOUT`および`DEAL_ENTRY_OUT_BY`をEventへ保持し、open・close価格は該当数量による加重平均、profit、commission、swapおよびfeeはPositionに属する全dealの合計とします。

手動決済のdealでMagicが変わっていても、初版はヘッジ口座に限定し、既知の`POSITION_IDENTIFIER`を正本として同じTradeへ関連付けます。broker transactionまたは保存済み変更元情報から手動・他EAを積極的に確認できた保護側SLだけを`EXTERNAL`とし、由来を証明できない保護側SLは`UNKNOWN`として、どちらもEAから緩めません。自EA actionとの不一致または要求履歴の欠落だけで`EXTERNAL`とは断定しません。保存済み水準より緩い、または削除された場合は保存済み水準の復元対象とします。

brokerに存在しないSKIP判定、Judge成立回数・初回消費、EA内部の決済意図、未送信要求、トレイル基準点およびSL設定元はbroker履歴だけから完全復元できません。

## 14. DB障害時

```text
新規OPENは停止する。
既存のSL変更とCLOSEは排他Lock保持中かつ既知Leaseの安全期限内だけ継続する。
broker SLはDB・Lease状態にかかわらず継続する。
```

- 接続不能、破損、schema不一致またはmigration失敗時にDBを削除しません。
- 新規OPENの事前保存に失敗した場合は発注しません。
- Judge判定の保存に失敗した場合も新規OPENを停止し、同一プロセス内では確定済みの判定・回数・消費をメモリへ保持します。再保存で再加算せず、復旧後にその判定の注文を遅延送信しません。未送信のEntry候補は`SKIP / DB_UNAVAILABLE`として監査情報を保持します。
- 保有中の保存失敗ではtransactionをrollbackします。排他Lockと既知Leaseの安全期限内ならpending候補をメモリへ保持し、リスク低減のSL変更または候補跨ぎ決済を継続できます。
- 未保存Eventは同一プロセス内のメモリキューへ保持し、復旧後にFIFOで保存します。
- メモリキューは再起動をまたぐ永続性を保証しません。
- 上限到達時は新規注文を停止し、追加Eventの識別値を運用ログへ明示します。
- broker SLは常に継続し、H1 ZigZag SL変更と候補跨ぎ成行決済は排他Lockと既知Leaseの安全期限内ならDB復旧を待ちません。
- 起動後に一度もLeaseを取得できていないRunは、Lockを保持していてもbroker SL以外の注文、SL変更および成行決済を送信しません。
- 次回起動時にbroker履歴からorder、deal、Positionおよび適用済みSLの事実だけを補完します。
- DB障害中に未保存のSKIP判定、Judge回数・初回消費、基準点、pending候補およびSL設定元は完全補完できず、断定不能な設定元は`UNKNOWN`とします。
- 保存前に異常終了したメモリ内のJudge状態は、DBとbrokerだけでは完全な欠落検出・復元を保証できません。未保存状態の存在を検出した場合は、DB行がないことを「Judge初回」と読み替えず、新規Entry停止を維持します。保存済みの回数・消費についてだけ再起動後の重複防止を保証します。
- 未反映のメモリ内pending候補は再起動で失われる可能性がありますが、最後にbrokerへ設定済みのSLは残ります。

未保存キューはDecision 256件、Trade/Event 256件を上限とし、DB再接続・FIFO再保存は最短5秒間隔とします。inputにはしません。

## 15. スキーマ移行

- 初版は新規DBとして`user_version = 1`を作成します。
- H1 ZigZagトレイルおよび既存H1 Entry互換のJudge回数・初回消費はEA・DB実装前の初版定義へ取り込むため、物理`user_version = 1`とRunの`schema_version = 1`を維持し、version 2 migrationは作成しません。
- 4テーブルの初回CREATE定義、Entity、DAOおよびSmokeTestの期待列へトレイル列とJudge・Entry診断列を含めます。
- 将来の変更は専用Migrationクラスで実施します。
- `PRAGMA table_info`と`sqlite_schema`で変更前後を確認します。
- migrationは起動時にtransactionで書込み権を取得したWriterだけが実行し、schema再確認後に開始します。
- 全DDLと検証に成功した後だけ`user_version`を更新します。
- Viewerは古い・新しいスキーマを検出するだけで変更しません。
- 対応不能な新しいスキーマでは新規取引を停止します。

## 16. Viewer連携

Viewer連携はEA初版の対象外です。将来設計では、少なくとも次を維持します。

- EA DBはread-onlyで参照する
- ViewerはDDLおよびmigrationを実行しない
- EA DBが利用不能でも既存Alert/Observation Viewerを停止しない
- `market_signal_key`は候補抽出に使用し、1対1の一意キーとは扱わない
- LIVEとTesterは別ファイルであることを接続設計へ反映する

## 17. SmokeTest

専用Database SmokeTestで最低限、次を確認します。

1. 新規DBと4テーブルを作成できる
2. `foreign_keys`、WALおよび`busy_timeout`が有効
3. Run、SKIP Decision、Entry DecisionおよびTradeを保存できる
4. 同じH1バーを重複保存できない
5. 同じ消費済みシグナルをRun変更後も重複保存できない
6. 同一DecisionへTradeを2行作成できない
7. 同一コンテキストへactive取引を2行作成できない
8. transaction失敗時にDecision、TradeおよびEventが部分保存されない
9. `OPEN_PENDING`、`OPEN_PARTIAL`、`OPEN`、`CLOSE_PENDING`、`CLOSE_PARTIAL`、`CLOSED`へ更新できる
10. 再起動照合用のactive取引を検索できる
11. profit、commission、swapおよびfeeを保存・再読込できる
12. DBをread-onlyで参照できる
13. 同一コンテキストの有効Leaseがある場合に後発Runを拒否できる
14. 期限切れLeaseだけを`INTERRUPTED`へ変更できる
15. 同じdealをcallbackと再起動照合から保存してもEventが重複しない
16. 同じRecovery snapshotを再照合してもEventが重複せず、状態変更時だけ追加される
17. Common Lockを保持中は同じscopeの2本目を取得できない
18. Canonical Configへ固定`ZIGZAG_SL_BUFFER_PIPS=10.0`を保存できる
19. pending・適用済み候補を保存・再読込でき、pending種別ごとの必須列および適用済み候補の部分NULLをCHECK制約で拒否できる
20. 現在broker SLより、かつpendingがある場合はpendingより保護側の候補だけへ置き換えられる
21. 同じTradeとH1バーの`TRAIL_EVALUATION`を重複保存できない
22. SL変更要求と結果を同じ`action_uid`で関連付け、再保存しても重複しない
23. SL変更要求EventとTrade snapshotのtransaction失敗時にどちらも残らない
24. 再起動時、broker SLがpending候補以上なら実SLと設定元を保存し、自EA actionと一致するトレイル候補だけを適用済みへ更新し、未達ならpendingを維持できる
25. broker SL、pending候補および未完了actionを含むRecovery snapshotが冪等である
26. `INITIAL_STOP_LOSS`、`INITIAL_STOP_LOSS_CROSSED`、`H1_ZIGZAG_TRAIL`および`H1_ZIGZAG_TRAIL_CROSSED`をbroker理由と分けて保存できる
27. トレイル適用後もTradeが`OPEN`を維持し、broker SL約定後に`CLOSED`へ更新できる
28. Position成立時に要求初期SLとの一致から`INITIAL_STOP_LOSS`を保存し、不一致を`EXTERNAL`または`UNKNOWN`へ分類できる
29. SL変更失敗または未反映では、brokerで確認したSLあり・なしをResultへ保存してactionだけを解除し、pendingを維持できる
30. より保護的な外部SLではpendingだけを解除し、適用済み候補を更新しない
31. Lease確認と各要求Event・Trade更新が同一transactionで成功しない限り、通常経路でbrokerへ送信しない
32. 候補跨ぎ時にpendingと未完了actionを解除して`CLOSE_PENDING`へ移行し、以後SL変更を送信しない
33. `(trade_id, sequence)`、`event_uid`および`(action_uid, event_type)`の重複を拒否できる
34. 未完了action中は新候補へ置き換えず、古いResultで新しいpendingを解除しない
35. brokerのSL有無を取得できない未完了actionをResultへ断定せず、`RECOVERY_REQUIRED`で再照合できる
36. `CLOSED`行で決済時刻、EA側分類、broker理由およびpending解除を必須にできる
37. `OPEN_PARTIAL`ではトレイルを開始せず、残注文の終端処理を優先できる
38. DB障害キューを再保存しても、最初に確定したaction/event UIDにより要求・結果が重複しない
39. `INITIAL_RESTORE`ではZigZag項目をNULL、トレイル由来pendingではZigZag項目を必須として保存できる
40. pendingを保持したまま`RECOVERY_REQUIRED`へ移行し、照合が完了するまでbrokerへの新しい送信を禁止できる
41. SL変更ResultはbrokerのSL有無を正常取得できた場合だけ保存し、SLなしと取得不能を区別できる
42. `INITIAL_RESTORE`と`TRAIL_RESTORE`の登録自体では`TRAIL_EVALUATION`を作らず、Recovery EventとTradeを同一transactionで更新し、H1バーの見送りEventとは区別できる
43. 構造不正なpendingをRecovery Eventへ隔離して構造化列を全NULLにし、`RECOVERY_REQUIRED`へ移行できる
44. 手動・他EAを積極的に確認できたSLだけを`EXTERNAL`、由来を証明できないSLを`UNKNOWN`へ分類できる
45. `INITIAL_RESTORE`中は新しいトレイル候補を作成しない
46. 初回Judge成立時の波動NGを`SKIP`・消費済み・SLなしで保存でき、Tradeを作成しない
47. 初回波動NGの後、同じシグナルの波動条件がOKになっても回数2以上・Entry未評価として注文しない
48. 同じシグナルのJudge不成立バーを挟んでも回数をリセットせず、初回消費を解除しない
49. 保有中または初期SL不正でもJudge初回を消費し、戦略Entry成立なら`is_strategy_entry = 1`のSKIPを保存できる
50. 消費済みSKIPをLIVEの再起動後にも復元し、H1バー変更後も同じシグナルを再消費しない
51. 同じH1バーの再評価・再保存・再起動でJudge回数を重複加算せず、確定Decisionを上書きしない
52. 未消費、Entry未評価、戦略Entry不成立またはSLなしのBUY/SELL DecisionをCHECK制約で拒否できる
53. 初回JudgeのSKIP保存失敗、およびEntry Decision・Trade・Eventの保存失敗で部分保存やbroker送信が発生しない
54. RunのCanonical ConfigへMN1分析開始、主方向一致・W1追加確認・EMA200確認モード、表示波制限OFF、通貨強弱フィルターOFF、entry count 1および評価タイミングを固定順で保存できる
55. MN1・W1方向とW1 EMA200の`NONE`、未取得NULL、主条件通過結果を区別して保存できる
56. LIVEの起動1秒後・以降30秒ごと、Testerのtickを評価契機とし、未保存の起動時進行中H1バーも判定できる
57. 同一H1バーで分析失敗後に成功した場合、失敗で回数を消費せず、成功時のDecisionだけを確定できる
58. 分析が成功しないままH1バーが切り替わった場合、前バーを`ANALYSIS_UNAVAILABLE`・回数0・未消費で確定し、過去バーの注文を送らない
59. H1最初のtickのトレイル評価とEntryポーリングを独立保存し、一方の分析失敗・評価済み状態で他方を処理済みにしない
60. DB復旧時にメモリ内のJudge回数を再加算せず保存し、失った評価機会のOPENを遅延送信しない
61. 未保存Judge状態の欠落を検出した場合、回数0へ推定復元して新規注文しない
62. Runの`config_text`と`config_hash`へ有効な`TESTER_TRADE_START_TIME`を保存し、Testerの指定日時・0の制限なし・LIVEの有効値0を区別できる。既存スキーマとRun行を変更しない
63. Testerの開始前にはDecision・新規Entry Tradeを保存せず、Run・heartbeatと既存保護処理の監査は継続できる。開始前バーのSKIP補完・Judge回数の消費も行わない
64. 開始後の最初のtickで通常評価を始め、ウォームアップ期間の処理済みバー・回数を持ち込まずに初回消費を保存できる
65. 安全条件を満たすTester高速ウォームアップ時だけheartbeatを30秒へ切り替え、Leaseの60秒とRun所有確認を維持する。開始時・リスク発見時・DB異常時は通常10秒へ戻し、Decision・新規Entryの保存抑止と既存保護を両立できる

## 18. 実装ファイル

初版では次を新設しました。

```text
Include/Mstng/Database/H1EaDatabaseContext.mqh
Include/Mstng/Database/Entity/H1EaRunEntity.mqh
Include/Mstng/Database/Entity/H1EaDecisionEntity.mqh
Include/Mstng/Database/Entity/H1EaTradeEntity.mqh
Include/Mstng/Database/Entity/H1EaTradeEventEntity.mqh
Include/Mstng/Database/Dao/H1EaRunDao.mqh
Include/Mstng/Database/Dao/H1EaDecisionDao.mqh
Include/Mstng/Database/Dao/H1EaTradeDao.mqh
Include/Mstng/Database/Dao/H1EaTradeEventDao.mqh
Include/Mstng/Database/Dao/H1EaSql.mqh
Include/Mstng/Database/Service/H1EaPersistenceService.mqh
Scripts/Mstng/Database/H1EaDatabaseSmokeTest.mq5
Scripts/Mstng/Database/test_h1_ea_database_contract.py
```

接続管理は[SqliteDatabase.mqh](../../Include/Mstng/Database/SqliteDatabase.mqh)を再利用し、複数Writer向け設定は[ZigZagElliotAlertDatabaseContext.mqh](../../Include/Mstng/Database/ZigZagElliotAlertDatabaseContext.mqh)の方式を踏襲します。

H1 ZigZagトレイル用の新テーブルは追加せず、`H1EaTradeEntity`、`H1EaTradeEventEntity`、各DAO、Persistence ServiceおよびDatabase SmokeTestの責務を拡張します。
