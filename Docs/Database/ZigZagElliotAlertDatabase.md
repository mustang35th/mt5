# ZigZagElliotアラートデータベース仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象機能 | `ZigZagElliot`の`MTF_3in3`アラート履歴 |
| DBMS | MetaTrader 5組み込みSQLite |
| スキーマバージョン | 2 |
| 保存単位 | 実行、アラート、時間足別分析、最新Waveポイント |
| 重複時の動作 | 最初に保存したスナップショットを維持 |
| 最終更新日 | 2026-08-12 |

本書は、ZigZagElliotがアラートを出した時点の判定情報とElliott波動を、後からSQLで検索および再構成できる形式で保存する第1段階の仕様を定義します。

## 2. 第1段階の範囲

第1段階では次を保存します。

- 1回のインジケーターまたはテスター実行を識別する情報
- `isAlert = true`になった`MTF_3in3`アラート本体
- アラート判定に使用したMN1から現在時間足までの時間足別分析
- 各時間足の最新Waveを構成する全ZigZagポイント
- 既存CSVと照合するためのアラート本文、波動要約、CSV形式の生データ

次は第1段階の対象外です。

- `isAlert = false`の候補保存
- アラート後のMFE、MAE、SL、TPおよび決済結果
- 同じアラートの時間経過による再カウント履歴
- 年別データベース分割
- 既存CSVまたは既存DBからの履歴移行

## 3. データベースファイル

| 入力値 | 既定値 | 内容 |
|---|---:|---|
| `mtf3In3AlertDatabaseEnabled` | `false` | アラートDB保存を有効にする場合true |
| `mtf3In3AlertDatabaseFileName` | `mstng-zigzag-elliot-alert.sqlite` | DBファイル名 |
| `mtf3In3AlertDatabaseUseCommonFolder` | `true` | Commonフォルダを使用する場合true |

Commonフォルダ使用時の保存先は次のとおりです。

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-zigzag-elliot-alert.sqlite
```

ストラテジーテスターでDBを有効にする場合はCommonフォルダを使用します。通常チャートではCommonフォルダを無効にすると、対象ターミナルの`MQL5\Files`へ保存します。

第1段階では年別ファイル名へ変換せず、指定した1ファイルを使用します。

## 4. テーブル関係

```text
zigzag_elliot_alert_runs (1)
  └─ zigzag_elliot_alerts (N)
       └─ zigzag_elliot_alert_timeframes (N)
            └─ zigzag_elliot_alert_points (N)
```

- `zigzag_elliot_alerts.run_id`は`zigzag_elliot_alert_runs.id`を参照します。
- `zigzag_elliot_alert_timeframes.alert_id`は`zigzag_elliot_alerts.id`を参照します。
- `zigzag_elliot_alert_points.alert_timeframe_id`は`zigzag_elliot_alert_timeframes.id`を参照します。
- すべての外部キーは`ON DELETE CASCADE`です。
- 接続作成時に`PRAGMA foreign_keys = ON`を実行し、有効化を確認します。

## 5. 共通データ表現

| 種別 | SQLite | MQL5 | 備考 |
|---|---|---|---|
| 主キー | `INTEGER` | `long` | `PRIMARY KEY AUTOINCREMENT` |
| 日時 | `INTEGER` | `datetime` | Unix秒 |
| 日時表示 | `TEXT` | `string` | `YYYY.MM.DD HH:MM:SS` |
| 真偽値 | `INTEGER` | `int` | 0または1、CHECK制約あり |
| 時間足 | `INTEGER` | `ENUM_TIMEFRAMES`をint化 | 表示用`*_text`も保存 |
| 価格・pips・% | `REAL` | `double` | 小数値を保持 |
| 利用不能値 | 0または空文字 | 対応型 | `is_*_available`と組み合わせる |

第1段階では暗黙のSQL NULLを使用しません。任意情報は利用可能フラグと0または空文字で表現します。これにより、未取得と有効な0をフラグで区別します。

### 5.1 分析ProfileとHash

| 項目 | 役割 |
|---|---|
| `analysis_version` | 計算式・判定ロジックの世代を識別する値 |
| `analysis_input_text` | 分析結果へ影響する設定一式を固定順序で表したCanonical Text。Runに保存 |
| `analysis_input_hash` | `analysis_input_text`のSHA-256（64桁の小文字16進数） |
| `snapshot_hash` | AlertまたはObservationへ保存した分析結果の完全性を確認するHash |

分析Profileは`analysis_version`、`analysis_input_hash`および`analysis_profile_kind`の組み合わせで識別します。`analysis_profile_kind`は、RunのCanonical TextとHashが空でなく、RunとObservationの分析バージョンおよびHashが一致する行を`profile`、それ以外を`legacy`として区別するViewer上の分類です。同じHashでも分析バージョンまたは分類が異なる行は別Profileとして検索します。

H1 Observationの`analysis_version`と`analysis_input_hash`には、保存元Runの値をそのまま複製します。Canonical TextはRunを正本とし、Observationへ重複保存しません。

既存Runへ追加された`analysis_input_text`と`analysis_input_hash`は空文字のまま保持し、推測によるバックフィルは行いません。これらのRunとObservationはLegacyとして参照できます。

## 6. `zigzag_elliot_alert_runs`

インジケーター起動またはテスター実行1回を表します。同じ`run_uid`を再保存した場合は既存IDを返し、行を追加しません。

### 6.1 列グループ

| グループ | 列 |
|---|---|
| 識別 | `id`, `run_uid`, `schema_version` |
| 実行元 | `source_mode`, `source`, `program_name`, `program_version` |
| ロジック | `strategy`, `strategy_version`, `analysis_version` |
| 分析Profile | `analysis_input_text`, `analysis_input_hash` |
| 環境 | `source_server`, `source_login`, `source_chart_id`, `terminal_build` |
| テスター | `tester_from`, `tester_to`, `tester_model` |
| 入力値 | `input_text`, `input_hash` |
| 時刻 | `started_at`, `started_at_text`, `market_started_at`, `market_started_at_text`, `created_at`, `created_at_text` |

### 6.2 インデックス

```sql
CREATE UNIQUE INDEX idx_zigzag_elliot_alert_runs_run_uid
ON zigzag_elliot_alert_runs(run_uid);

CREATE INDEX idx_zigzag_elliot_alert_runs_started_at
ON zigzag_elliot_alert_runs(started_at);
```

`run_uid`は1回の実行中に変化しません。テスターを再実行した場合は新しいRunとして扱います。

## 7. `zigzag_elliot_alerts`

1回の`MTF_3in3`アラート判定を表す親テーブルです。既存64列CSVの主要値に、DB用識別子、リスク、本文および波動要約を加えます。

### 7.1 列グループ

| グループ | 主な列 |
|---|---|
| 識別 | `id`, `run_id`, `event_uid`, `market_signal_key`, `snapshot_hash` |
| 時刻 | `server_time`, `jst_time`, `current_bar_time`, `signal_reference_point_time`と各`*_text` |
| 市場 | `symbol_name`, `time_frame`, `time_frame_text`, `magic_number`, `strategy`, `side` |
| 判定 | `is_judge`, `signal_count`, `entry_count`, `is_entry_count_match`, `is_entry_evaluated`, `is_alert`, `is_entry`, `entry_result`, `is_send_mail` |
| 現在波 | `current_elliot_label`, `is_entry_wave` |
| EMA・Spread | `close_ema200_diff_pips`, `max_close_ema200_diff_pips`, `is_ema200_distance_within`, `spread_pips` |
| 通貨強弱 | 有効・取得状態、計算バージョン、Run ID、M5時刻、基軸／決済通貨順位と順位差 |
| 価格・リスク | `reference_price`, `is_stop_loss_available`, `stop_loss`, `risk_pips` |
| H1構造 | `h1_structure_rank`, `is_h1_structure_valid`, `is_h1_structure_late`, `is_h1_direction_exception` |
| 監査用テキスト | `alert_title`, `alert_text`, `wave_summary_text`, `elliot_csv_text` |
| 保存時刻 | `created_at`, `created_at_text` |

`signal_reference_point_time`は現在時間足の`getLatestPoint2()`の時刻です。確定済みを保証する名称ではありません。

### 7.2 自然キー

実行内の一意性は次の組み合わせで保証します。

```sql
UNIQUE(
    run_id,
    symbol_name,
    time_frame,
    magic_number,
    strategy,
    current_bar_time,
    signal_reference_point_time,
    side
)
```

さらに`UNIQUE(run_id, event_uid)`を設定します。

`market_signal_key`はRunをまたいだ同一市場シグナルの比較用であり、一意ではありません。接続サーバー、シンボル、時間足、現在バー時刻、シグナル基準ポイント時刻、戦略、売買方向から生成します。テスターを設定違いで実行した場合も、それぞれのRunへ同じ市場シグナルを保存できます。

### 7.3 重複方針

同一自然キーが存在する場合は次のように処理します。

1. 既存Alert IDと`snapshot_hash`を読みます。
2. hashが同じ場合は保存済みとして成功を返します。
3. hashが異なる場合も既存行と子行を更新しません。
4. hash差異をINFOへ記録し、最初のスナップショットを維持します。

Alertの`snapshot_hash`はアラート判定、時間足別分析および保存対象となる最新Wave全ポイントから生成します。H1 Observationの`snapshot_hash`も、保存した観測結果から生成します。いずれも分析設定を識別する`analysis_input_hash`とは用途が異なります。

同一シグナルの再カウント推移が必要になった場合は、第2段階以降でRevisionテーブルを追加します。

## 8. `zigzag_elliot_alert_timeframes`

1アラートに対する時間足別Elliott分析を保存します。H1チャートではMN1、W1、D1、H4、H1の5行です。

### 8.1 一意性と順序

```sql
UNIQUE(alert_id, time_frame)
UNIQUE(alert_id, time_frame_order)
```

`time_frame_order`は上位足から0始まりです。

```text
0=MN1, 1=W1, 2=D1, 3=H4, 4=H1
```

### 8.2 列グループ

| グループ | 主な列 |
|---|---|
| 識別 | `id`, `alert_id`, `time_frame`, `time_frame_text`, `time_frame_order`, `is_current_time_frame` |
| Elliott方向 | `is_buy`, `buy_sell_label` |
| 最新Wave | `wave_count`, `latest_wave_index`, `is_wave_confirmed`, `is_wave_motive`, `is_wave_uptrend`, `wave_trend_label`, `previous_last_elliot_label` |
| 最新ポイント要約 | `point_count`, 最新Elliott番号・ラベル、最新下位波番号・ラベル |
| OHLC | 1本前確定足と現在足のOHLC |
| FE価格 | 利用可能フラグ、61.8～200.0%価格、FE200距離 |
| Oscillator | 総合方向、3本ストキャスの並び・値・継続数 |
| GMMA | trend count、cross count、EMA30、EMA60、距離 |
| ATR・EMA200 | ATR14、EMA200価格・傾き・方向・継続数 |
| 監査 | `raw_csv_text`, `created_at`, `created_at_text` |

`point_count`は同じ時間足行に紐づくPoint実件数と一致しなければなりません。

## 9. `zigzag_elliot_alert_points`

各時間足の最新Waveを構成する全ポイントを、古い順に保存します。

### 9.1 一意性と順序

```sql
UNIQUE(alert_timeframe_id, point_order)
```

`point_order = 0`が最新Wave内の最古ポイントです。各時間足で次を保証します。

- `is_latest = 1`は末尾の1点
- 現在時間足の`getLatestPoint2()`だけ`is_signal_reference = 1`
- `bar_index`は保存時点の値であり、後から再計算しない

### 9.2 列グループ

| グループ | 主な列 |
|---|---|
| 識別 | `id`, `alert_timeframe_id`, `point_order`, `is_latest`, `is_signal_reference` |
| 価格・足 | `rate`, `bar_index`, `bar_time`, `bar_time_text`, 次バー利用可能フラグ・時刻 |
| Wave位置 | `wave_bars_from_start`, `is_peak`, `is_added_point`, `pips_diff` |
| Fibonacci | retracement利用可能フラグ・%、depth zone、expansion利用可能フラグ・% |
| Elliott | alphabetフラグ、Elliott番号・ラベル、下位波利用可能フラグ・番号・ラベル、補正前波利用可能フラグ・番号・ラベル |
| 補正・保存 | `is_correct`, `created_at`, `created_at_text` |

MQL5 Entityの`timeFrame`は、保存時に対応する時間足親IDを割り当てるための論理フィールドです。Pointテーブルには保存しません。

## 10. 保存処理

### 10.1 初期化

1. `ZigZagElliotAlertDatabaseContext`でDBを開きます。
2. 外部キーを有効化します。
3. Run、Alert、TimeFrame、Pointの順にテーブルとインデックスを準備します。
4. 実行開始時に`saveRun()`を呼び、Run IDを保持します。

### 10.2 アラート保存

```text
isAlert=true
  → Snapshot生成
  → BEGIN
  → 自然キー検索
      ├─ 既存: 最初のSnapshotを維持してCOMMIT
      └─ 新規: Alert → TimeFrame → Pointを保存
  → 件数・対応時間足を確認
  → COMMIT
```

Alert、TimeFrame、Pointは1トランザクションです。途中で1件でも失敗した場合はROLLBACKし、Entityへ一時設定したIDを0へ戻します。

Pointの論理`timeFrame`とTimeFrameの`time_frame`を照合して、`alert_timeframe_id`を割り当てます。対応しないPointが1件でも残った場合は保存全体を失敗させます。

## 11. CSVとの関係

DB保存と既存CSV保存は独立した設定です。

| DB | CSV | 動作 |
|---|---|---|
| ON | ON | DBとCSVへ保存 |
| ON | OFF | DBだけ保存 |
| OFF | ON | CSVだけ保存 |
| OFF | OFF | 保存しない |

DBでは検索しやすい正規化列を使用し、既存CSV形式は`elliot_csv_text`と時間足別`raw_csv_text`へ監査用として残します。

## 12. 失敗時の動作

- DB初期化失敗時はERRORを出してDB保存だけを無効化し、既存アラート処理を継続します。
- Snapshot保存失敗時はERRORを出して部分レコードを残さず、CSVと既存アラート処理を継続します。
- DB保存結果はElliott分析結果やアラート条件を書き換えません。
- 最適化中は複数エージェントの同一ファイル書き込みを避けるため、DB保存対象外とします。

## 13. スモークテスト

`Scripts/Mstng/Database/ZigZagElliotAlertDatabaseSmokeTest.mq5`は専用ファイルを使用します。

```text
mstng-zigzag-elliot-alert-smoke-test.sqlite
```

既定FixtureはGBPAUD、H1、BUYです。

| 時間足 | ポイント数 |
|---|---:|
| MN1 | 2 |
| W1 | 3 |
| D1 | 4 |
| H4 | 5 |
| H1 | 6 |
| 合計 | 20 |

次を自動検証します。

- Run、Alert、5時間足、20ポイントを保存できること
- 同じRunとSnapshotを再保存してIDと件数が増えないこと
- `point_order`合計が35で、ポイント順が欠落していないこと
- 各時間足の`point_count`と子Point件数が一致すること
- 最新ポイントが時間足ごとに1件、シグナル基準ポイントが全体で1件であること
- 対応する時間足がないPointを混ぜた保存が失敗し、親子行とEntity IDを残さないこと
- `PRAGMA foreign_keys = 1`
- `PRAGMA foreign_key_check`が0行
- `PRAGMA integrity_check`が`ok`

ROLLBACK検証では意図的に対応時間足のないPointを渡すため、永続化サービスのERRORが1回出た後にスモークテストの成功INFOが出ます。このERRORは検証用に期待される出力です。

`recreateDatabaseObjects = true`でテーブルを削除できるのは、誤操作防止のため既定の`mstng-zigzag-elliot-alert-smoke-test.sqlite`だけです。別名を検証する場合は`recreateDatabaseObjects = false`を使用します。本番DBファイル名を指定して実行してはいけません。

## 14. 確認用SQL

アラート件数を確認します。

```sql
SELECT symbol_name,
       time_frame_text,
       side,
       COUNT(*) AS alert_count
FROM zigzag_elliot_alerts
GROUP BY symbol_name, time_frame_text, side
ORDER BY symbol_name, time_frame_text, side;
```

H1アラートの時間足別最新Waveを確認します。

```sql
SELECT alert.id,
       alert.symbol_name,
       alert.current_bar_time_text,
       time_frame.time_frame_text,
       time_frame.buy_sell_label,
       time_frame.latest_elliot_label,
       time_frame.point_count
FROM zigzag_elliot_alerts AS alert
INNER JOIN zigzag_elliot_alert_timeframes AS time_frame
        ON time_frame.alert_id = alert.id
WHERE alert.time_frame_text = 'H1'
ORDER BY alert.current_bar_time, time_frame.time_frame_order;
```

1アラートの波動ポイントを復元します。

```sql
SELECT time_frame.time_frame_text,
       point.point_order,
       point.bar_time_text,
       point.rate,
       point.elliot_label,
       point.sub_elliot_label,
       point.fibonacci_percent,
       point.fibonacci_expansion_percent,
       point.is_latest,
       point.is_signal_reference
FROM zigzag_elliot_alert_timeframes AS time_frame
INNER JOIN zigzag_elliot_alert_points AS point
        ON point.alert_timeframe_id = time_frame.id
WHERE time_frame.alert_id = ?1
ORDER BY time_frame.time_frame_order, point.point_order;
```

自然キー重複を確認します。0行が正常です。

```sql
SELECT run_id,
       symbol_name,
       time_frame,
       magic_number,
       strategy,
       current_bar_time,
       signal_reference_point_time,
       side,
       COUNT(*) AS record_count
FROM zigzag_elliot_alerts
GROUP BY run_id,
         symbol_name,
         time_frame,
         magic_number,
         strategy,
         current_bar_time,
         signal_reference_point_time,
         side
HAVING COUNT(*) > 1;
```
