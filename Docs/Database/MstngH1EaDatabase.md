# MstngH1Eaデータベース設計書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象機能 | 新規H1専用EA（仮称：`MstngH1Ea`）の判定・取引永続化 |
| DBMS | MetaTrader 5組み込みSQLite |
| 物理スキーマバージョン | 1 |
| 保存単位 | EA起動、H1判定、取引ライフサイクル |
| 文書状態 | 基本設計・実装前 |
| 最終更新日 | 2026-09-02 |

本書は、`MstngH1Ea`がH1判定、発注、約定および決済を保存し、再起動後にbroker状態と整合するためのSQLite構造を定義します。EA全体の動作は[MstngH1Ea基本設計書](../ExpertAdvisor/MstngH1Ea.md)を参照してください。

## 2. 対象範囲

初版では次を保存します。

- EA起動ごとの環境、設定およびバージョン
- すべてのH1新規バーのBUY、SELLまたはSKIP判定
- 判定に使用した主要条件と拒否理由
- 発注要求から決済完了までの取引状態
- 取引要求、結果、broker order、各dealおよびPositionのEvent履歴
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

取引の現在状態は`h1_ea_trades`、部分約定を含む変更履歴は`h1_ea_trade_events`を正本とします。

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
| `strategy_version` | TEXT | Yes | エントリーロジック世代 |
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

LIVEは再起動前後で同じキーを使用し、消費済みシグナルとactive取引を引き継ぎます。TesterはRunごとにキーを分け、同じ期間を繰り返しテストしても過去RunのDecisionと衝突しないようにします。この`context_key`をDecisionとTradeの重複防止scopeとして使用します。

キー文字列は`H1_EA_CONTEXT_V1`を先頭に、表記どおりの固定順、区切り文字`|`、整数の10進表記で生成します。serverとsymbolに`|`が含まれる場合は初期化を拒否し、暗黙の置換は行いません。`run_uid`は`source_mode|server|login|chart_id|started_at|GetTickCount64`をUTF-8でSHA-256化した64桁小文字16進文字列とします。`GetTickCount64()`はUID生成材料にだけ使用し、日時として保存しません。

分析Profileは既存の`ZigZagElliotAnalysisProfile::createCanonicalText()`と`createHash()`をそのまま使用します。EA設定は次の固定順で生成し、数値の小数桁も固定します。

```text
H1_EA_CONFIG_V1|LOT_SIZE=<8桁>|MAX_INITIAL_SL_PIPS=<1桁>
```

`status`は次に限定します。

```text
RUNNING
STOPPED
FAILED
INTERRUPTED
```

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

EAは10秒間隔の`OnTimer()`でheartbeatを更新し、Leaseを更新時点から60秒間有効にします。起動時に同一`context_key`の`RUNNING`が存在する場合、有効なLeaseなら二重起動として後発を拒否します。期限切れの場合だけ、transaction内で旧Runを`INTERRUPTED`へ更新して新Runを作成します。注文前にも今回Runが有効なLeaseを保持していることを同じtransaction内で確認します。

DB接続中にLease所有権を失った旧Runは、注文・変更・決済を停止します。DB障害中は、排他Lockを保持し、最後に確認できたLeaseが未失効の間だけ現在Runが既存ポジションのリスク管理を継続します。

### 7.1 DB非依存の排他Lock

DB接続障害中の二重管理を防ぐため、EAはDBを開く前にCommonフォルダのLockファイルを共有指定なしで開き、ファイルハンドルを稼働中保持します。

```text
MstngH1Ea\Locks\<instance_scope_hash>.lock
```

`instance_scope_hash`は`source_mode|server|login|symbol|H1|magic`のSHA-256です。Lockファイルの内容は状態の正本にせず、OSによる排他ハンドルだけを使用します。取得失敗時は後発EAの初期化を拒否し、EA終了時にハンドルを閉じます。異常終了後に空ファイルが残っても、ハンドルが解放されていれば再取得できます。

Run登録とLease取得は別処理にせず、期限切れRunの更新と新しい`RUNNING`行の追加を単一transactionで行います。DBを開けないが排他Lockを取得できた場合は制限状態で既存ポジションだけを管理し、DB復旧後に同じtransactionでRunを登録します。

最後に保存できた`lease_expires_at`へ到達するまでheartbeatを更新できなかった場合、排他Lockを保持していてもEAからの注文、SL変更および成行決済を停止します。起動後に一度もLeaseを取得できない場合は、Lock取得時刻から60秒を同じ安全期限とします。これにより、別RunがLeaseを引き継いだ場合のsplit-brainを防ぎます。brokerへ設定済みのSLは継続します。

## 8. `h1_ea_decisions`

H1新規バー1本につき1行を保存します。エントリー成立時だけでなく、保有中、分析不能および条件未達もSKIPとして保存します。

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
| `is_signal_consumed` | INTEGER | Yes | 同一シグナルを消費した場合1 |
| `spread_pips` | REAL | No | 判定時Spread |
| `requested_volume` | REAL | No | 正規化後の要求ロット |
| `initial_stop_loss` | REAL | No | 注文前に検証した初期SL |
| `initial_risk_pips` | REAL | No | 建値候補から初期SLまでの幅 |
| `max_initial_risk_pips` | REAL | Yes | Runで使用した初期SL最大幅 |

### 8.3 主要条件スナップショット

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
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
| `h1_ema200_direction` | TEXT | No | H1 EMA200方向 |
| `h4_ema200_direction` | TEXT | No | H4 EMA200方向 |
| `analysis_snapshot_text` | TEXT | Yes | 追加診断値のCanonical Text |

主要条件はSQL検索できる個別列へ保存し、補足情報だけを`analysis_snapshot_text`へ保存します。判定ロジックの変更時も、既存行を再判定または上書きしません。

`analysis_snapshot_text`は`H1_EA_DECISION_V1`を先頭に、8.2と8.3の列を表の順で`|列名=値`として連結します。小数はpipsを1桁、価格を対象シンボルのDigits、ロットを2桁で固定します。`snapshot_hash`は識別子と保存時刻を除くDecision保存値、`analysis_version`および`analysis_input_hash`を同じ順で連結したUTF-8文字列のSHA-256です。

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

CHECK(
    is_signal_consumed = 0 OR (
        decision IN ('BUY', 'SELL')
        AND signal_reference_time IS NOT NULL
        AND signal_reference_time > 0
        AND signal_side IN ('BUY', 'SELL')
        AND initial_stop_loss IS NOT NULL
        AND initial_stop_loss > 0.0
    )
)
```

`run_id`を消費済みシグナルの一意条件へ含めません。Runを含めると、EA再起動後に同じシグナルを再注文できるためです。

LIVEの同じH1バーでEAを再起動した場合、新RunへDecisionを複製しません。最初に保存したDecisionがそのバーの正本です。Run別の全バー件数を集計する場合は、この引継ぎ行が旧Runに所属することを考慮します。Testerは`context_key`へ`run_uid`を含むため、各Runが独立したDecisionを持ちます。

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

1回のエントリー試行から決済完了までを1行で表します。エントリー条件が成立したDecisionだけが0または1行を持ちます。

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
| `exit_requested_server_time` | INTEGER | No | `TimeCurrent()`による決済要求時刻 |
| `exit_order_ticket` | TEXT | No | 決済注文ticket |
| `exit_deal_ticket` | TEXT | No | 最後に確認した決済deal ticket |
| `exit_retcode` | INTEGER | No | 決済注文retcode |
| `closed_at_msc` | INTEGER | No | 最後のexit dealの`DEAL_TIME_MSC` |
| `close_price` | REAL | No | broker履歴から求めた決済平均価格 |
| `remaining_position_volume` | REAL | No | 部分決済後の残存数量 |
| `exit_intent_reason` | TEXT | No | EAが決済要求した理由。例：`OPPOSITE_GMMA` |
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

```sql
CHECK(origin IN ('NORMAL', 'RECOVERED'))
CHECK(side IN ('BUY', 'SELL'))
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
```

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
```

`RECOVERY_REQUIRED`は同一コンテキストのactive枠を維持します。broker Positionを発見しても別の回復行を追加せず、既存のactive行へ再結合します。既存行へ安全に結合できない場合は`RECOVERY_REQUIRED`を維持して新規注文を停止します。

## 10. `h1_ea_trade_events`

注文要求、受付結果、各deal、決済要求および回復処理を追記型で保存します。`h1_ea_trades`は現在状態、Eventは監査履歴です。

### 10.1 列

| 列 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `id` | INTEGER | Yes | 主キー |
| `trade_id` | INTEGER | Yes | Trade外部キー |
| `run_id` | INTEGER | Yes | Eventを保存したRunの外部キー |
| `event_uid` | TEXT | Yes | 冪等保存用の一意ID |
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
| `side` | TEXT | No | `BUY`または`SELL` |
| `volume` | REAL | No | 要求または約定数量 |
| `price` | REAL | No | 要求または約定価格 |
| `stop_loss` | REAL | No | Event時点のSL |
| `retcode` | INTEGER | No | 注文結果retcode |
| `exit_intent_reason` | TEXT | No | EA内部の決済理由 |
| `broker_reason` | TEXT | No | `DEAL_REASON`またはorder理由 |
| `message` | TEXT | Yes | 補足。通常は空文字 |

`event_type`は初版で次を使用します。

```text
ENTRY_REQUEST
ENTRY_RESULT
DEAL_ADD
EXIT_REQUEST
EXIT_RESULT
RECOVERY
ERROR
```

```sql
CHECK(event_type IN (
    'ENTRY_REQUEST',
    'ENTRY_RESULT',
    'DEAL_ADD',
    'EXIT_REQUEST',
    'EXIT_RESULT',
    'RECOVERY',
    'ERROR'
))
CHECK(event_source IN ('EA', 'CALLBACK', 'RECONCILIATION'))
CHECK(sequence > 0)
CHECK(recorded_at > 0)
CHECK(side IS NULL OR side IN ('BUY', 'SELL'))
CHECK(event_type <> 'DEAL_ADD' OR (
    deal_ticket IS NOT NULL
    AND deal_scope_key IS NOT NULL
    AND broker_time_msc IS NOT NULL
))
```

### 10.2 一意性と索引

```sql
CREATE UNIQUE INDEX idx_h1_ea_trade_events_event_uid
ON h1_ea_trade_events(event_uid);

CREATE UNIQUE INDEX idx_h1_ea_trade_events_deal_scope
ON h1_ea_trade_events(deal_scope_key)
WHERE deal_scope_key IS NOT NULL;

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

`DEAL_ADD`の`event_uid`は`deal_scope_key`と同じ値にし、callbackと再起動照合で共通化します。要求・結果Eventの`event_uid`は`run_uid|trade_id|event_type|sequence`とします。

`RECOVERY`は、照合対象の現在order、履歴order、deal、PositionおよびTrade更新後状態を固定順で連結した`snapshot_hash`を作り、`H1_EA_RECOVERY_V1|context_key|trade_id|snapshot_hash`を`event_uid`とします。同じbroker状態の再照合は重複保存せず、状態が変化した場合だけ新しいEventになります。

`sequence`は同じTrade内で`MAX(sequence) + 1`をtransaction内で採番します。Event追加とTrade更新を同一transactionで行います。

## 11. 保存処理

### 11.1 起動

1. DB接続とスキーマを確認する
2. 単一transactionで同一コンテキストのLeaseを確認する
3. 同じtransactionで期限切れRunだけを`INTERRUPTED`へ更新し、今回Runを`RUNNING`で追加してLeaseを取得する
4. brokerとactive取引を照合する

`OPEN_PENDING`でPositionがない場合、現在order、履歴orderおよびdealを確認します。orderが有効なら`OPEN_PENDING`を維持し、orderが終端状態かつdealもPositionもない場合だけ`OPEN_FAILED`へ更新します。判定不能なら`RECOVERY_REQUIRED`へ移行します。

### 11.2 H1判定

- H1新規バーごとにDecisionを1行保存します。
- 条件未達は`decision = 'SKIP'`と理由コードを保存します。
- 完全なエントリー条件成立時は、Decisionのシグナル消費とTradeの`OPEN_PENDING`を同一transactionで保存します。
- transactionをcommitできるまで`OrderSend()`を実行しません。

### 11.3 新規約定

- `OnTradeTransaction()`のdeal追加を契機にします。
- brokerのorder、dealおよびpositionを読み直します。
- Event追加とTrade snapshot更新を同一transactionで行います。
- 一部約定と残注文がある場合は`OPEN_PARTIAL`、全量成立後は`OPEN`へ更新します。
- Entryが部分約定した場合は残注文を取消要求し、不足数量を同じシグナルで再発注しません。
- 残注文が終端となりPositionが残る場合は実約定数量を採用して`OPEN`、Positionがなければ`OPEN_FAILED`へ更新します。
- 同じ通知を再処理しても結果が変わらないようにします。

### 11.4 決済

- 決済要求前に`CLOSE_PENDING`と理由を保存します。
- DB保存失敗時でも、排他Lockを保持し、既知Leaseの安全期限内なら保有リスクを減らす決済要求を継続します。
- Position消滅後、`HistorySelect()`と`DEAL_POSITION_ID`で全dealを取得します。
- 一部決済後にPositionが残る場合は`CLOSE_PARTIAL`へ更新します。
- 有効な決済注文がなければ、最短1秒間隔で残存全量の成行決済を再試行します。
- 決済価格、profit、commission、swapおよびfeeを再集計し、Position消滅後に`CLOSED`へ更新します。

### 11.5 終了

- 正常終了はRunを`STOPPED`へ更新します。
- 初期化途中の失敗は可能なら`FAILED`へ更新します。
- DB更新不能の場合はテキスト運用ログへ残します。

## 12. Transaction

次は必ず単一transactionで保存します。

- エントリーDecisionの消費と`OPEN_PENDING`作成
- Trade Event追加とTrade snapshot更新
- broker照合によるTradeと回復Eventの更新
- 決済履歴集計、決済Eventと`CLOSED`更新
- schema migrationの全処理

途中で失敗した場合はrollbackし、部分的な状態を残しません。`SQLITE_BUSY`相当の失敗では接続を再確認し、注文前なら新規注文を停止します。

## 13. 冪等性とbroker照合

- 市場シグナルは`context_key`、`signal_reference_time`および`signal_side`で一意にします。
- Positionは`POSITION_IDENTIFIER`および`DEAL_POSITION_ID`で関連付けます。
- ticketとMagicはTEXTで保存します。
- broker由来の約定結果はbroker履歴を正本とします。
- 同じH1バー、同じdeal通知および同じ再起動照合を複数回実行しても、行を重複追加しません。
- DBとbrokerが矛盾する場合はbrokerを優先し、補完不能なら`RECOVERY_REQUIRED`にします。

`OnTradeTransaction()`で差分金額を単純加算しません。通知ごとに`DEAL_POSITION_ID`へ紐づく全dealを再取得し、Tradeの集約値を置換します。Entry、Exit、`DEAL_ENTRY_INOUT`および`DEAL_ENTRY_OUT_BY`をEventへ保持し、open・close価格は該当数量による加重平均、profit、commission、swapおよびfeeはPositionに属する全dealの合計とします。

手動決済のdealでMagicが変わっていても、初版はヘッジ口座に限定し、既知の`POSITION_IDENTIFIER`を正本として同じTradeへ関連付けます。brokerに存在しないSKIP判定、EA内部の決済意図および未送信要求は履歴から復元できません。

## 14. DB障害時

```text
新規OPENは停止する。
既存CLOSEは排他Lock保持中かつ既知Leaseの安全期限内だけ継続する。
broker SLはDB・Lease状態にかかわらず継続する。
```

- 接続不能、破損、schema不一致またはmigration失敗時にDBを削除しません。
- 注文前のDB保存失敗では注文しません。
- 保有中の保存失敗ではtransactionをrollbackし、再接続待ちにします。
- 未保存Eventは同一プロセス内のメモリキューへ保持し、復旧後にFIFOで保存します。
- メモリキューは再起動をまたぐ永続性を保証しません。
- 上限到達時は新規注文を停止し、追加Eventの識別値を運用ログへ明示します。
- broker SLは常に継続し、反対GMMA決済は排他Lockと既知Leaseの安全期限内ならDB復旧を待ちません。
- 次回起動時にbroker履歴からorder、dealおよびPositionの事実だけを補完します。
- DB障害中のSKIP判定とEA内部状態は完全補完できません。

未保存キューの上限値と再接続間隔は実装設計時に固定定数として定義し、inputにはしません。

## 15. スキーマ移行

- 初版は新規DBとして`user_version = 1`を作成します。
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

## 18. 実装予定

初版では次を新設します。名称は実装時に既存パッケージ構成へ合わせて確定します。

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
Include/Mstng/Database/Service/H1EaPersistenceService.mqh
Scripts/Mstng/Database/H1EaDatabaseSmokeTest.mq5
```

接続管理は[SqliteDatabase.mqh](../../Include/Mstng/Database/SqliteDatabase.mqh)を再利用し、複数Writer向け設定は[ZigZagElliotAlertDatabaseContext.mqh](../../Include/Mstng/Database/ZigZagElliotAlertDatabaseContext.mqh)の方式を踏襲します。
