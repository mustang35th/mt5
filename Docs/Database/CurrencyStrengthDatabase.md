# 通貨強弱データベース仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象機能 | 主要8通貨・28通貨ペアの通貨強弱集計履歴 |
| DBMS | MetaTrader 5組み込みSQLite |
| LIVE集計ルール | `pair-direction-raw-v6` |
| TESTER集計ルール | `pair-direction-closed-v1` |
| 最終更新日 | 2026-07-18 |
| 実装 | `CurrencyStrengthElliot`、`CurrencyStrengthPersistenceService`、3 Entity・3 DAO |

本書は、通貨強弱集計で使用する3テーブル、1ビュー、インデックス、保存処理および既存DB移行処理を定義します。

## 2. データベースファイル

### 2.1 本番用

| 項目 | 既定値 |
|---|---|
| ファイル名 | `mstng-currency-strength.sqlite` |
| DB保存有無 | `databaseEnabled = true` |
| Commonフォルダ使用 | `databaseUseCommonFolder = true` |
| オープンモード | READWRITE、CREATE、Common使用時はCOMMON |

保存場所は次のとおりです。

- Commonフォルダ使用時: `%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-currency-strength.sqlite`
- Commonフォルダ未使用時: 対象ターミナルの`MQL5\Files\mstng-currency-strength.sqlite`

### 2.2 スモークテスト用

| 項目 | 既定値 |
|---|---|
| ファイル名 | `mstng-currency-strength-smoke-test.sqlite` |
| Commonフォルダ使用 | `useCommonFolder = true` |
| DBオブジェクト再作成 | `recreateDatabaseObjects = true` |

`recreateDatabaseObjects = true`では、指定したDB内のビューと3テーブルを削除します。本番DBのファイル名を指定して実行してはいけません。

## 3. 集計仕様

対象通貨は`USD`、`JPY`、`EUR`、`GBP`、`AUD`、`NZD`、`CAD`、`CHF`の8通貨です。28通貨ペアをMN1、W1、D1、H4、H1、M15、M5の7時間足で判定します。時間足の集計順はMN1、W1、D1、H4、H1、M15、M5です。

LIVEでは従来どおり各時間足の現在足を判定し、`calculation_version = pair-direction-raw-v6`、`source_mode = LIVE`として保存します。

TESTERでは新しいM5足の開始時刻をスナップショット基準時刻`T`とし、`calculated_at`と`m5_bar_time`の両方へ`T`を保存します。各時間足について`T`の時点で確定済みの最新足、すなわち開始時刻が`T`より前で、`T`を含む足の1本前にあたる足を判定します。基準チャートシンボルで時間足別の確定足開始時刻を決め、各通貨ペアで同じ開始時刻の足を優先します。実履歴にその足がない場合は、期待時刻より前に存在する直近の確定足へフォールバックし、実際の時刻をPairVoteの`bar_time`へ保存します。TESTERの保存値は`calculation_version = pair-direction-closed-v1`、`source_mode = TESTER`です。

TESTERの`m15_bar_time`には`T`を含むM15足の開始時刻を保存します。一方、PairVoteの`bar_time`には実際に判定した確定足の開始時刻を保存します。このためM5票の`bar_time`は`T`ではなく直前M5足の開始時刻となり、M15票の`bar_time`も`m15_bar_time`より前になります。

1通貨ペア・1時間足につき1票として、次の規則で加算します。

| 判定 | 基軸通貨 | 決済通貨 |
|---|---:|---:|
| BUY | +1 | -1 |
| SELL | -1 | +1 |

集計値は正規化しない整数合計です。完全な集計では次の件数になります。

| DBオブジェクト | 件数 |
|---|---:|
| `currency_strength_runs` | 1 |
| `currency_strength_pair_votes` | 196（28ペア × 7時間足） |
| `currency_strength_results` | 8（通貨数） |
| `currency_strength_contributions` | 392（196票 × BASE/QUOTE） |

各通貨は1時間足につき7ペアへ登場するため、完全な集計における時間足別スコアは-7～+7です。各通貨の全7時間足の票数は49票、総合スコアは-49～+49です。

時間軸ごとの傾向確認用として、指定時間足の未正規化スコアを単純算術平均します。

| 期間 | 対象時間足 | 計算式 |
|---|---|---|
| 長期 | MN1、W1、D1 | `(mn1_score + w1_score + d1_score) / 3.0` |
| 長中期 | MN1、W1、D1、H4、H1 | `(mn1_score + w1_score + d1_score + h4_score + h1_score) / 5.0` |
| 中期 | D1、H4、H1 | `(d1_score + h4_score + h1_score) / 3.0` |
| 中短期 | D1、H4、H1、M15、M5 | `(d1_score + h4_score + h1_score + m15_score + m5_score) / 5.0` |
| 短期 | H1、M15、M5 | `(h1_score + m15_score + m5_score) / 3.0` |

D1やH1などの時間足は複数期間へ重複して使用します。平均値は票数による正規化ではなく、指定した3時間足または5時間足を固定分母3または5で平均した値です。完全な集計における各平均の範囲は-7～+7です。完全な集計では各時間足スコアが7票の奇数合計となるため、3時間足平均は2/3刻み、5時間足平均は0.4刻みになります。最強・最弱判定とTOTALは従来どおり7時間足の未正規化合計を使用します。

長期・長中期・中期・中短期・短期の各平均について、8通貨内の降順順位を記録します。順位は`1 + 対象通貨より平均スコアが高い通貨数`で算出し、同点は同順位、次順位を飛ばす競技順位とします。例としてスコアが5、3、3、1の場合、順位は1、2、2、4です。28通貨ペアが揃った完全Runだけ1～8の順位を保存し、部分Runと平均順位追加前の履歴は0とします。

`CurrencyStrengthElliot`の`sortType`では、チャート表示順を`TOTAL`、`LONG`、`LONG-MID`、`MID`、`MID-SHORT`、`SHORT`から選択します。完全な集計では選択スコアの降順、TOTALの降順、通貨コードの昇順で並べ、`#`列はこの表示順を示します。未完全集計ではソートせず、`#`列は従来どおり`-`を表示します。この表示設定はDB保存値とLIVE・TESTERそれぞれの`calculation_version`へ影響しません。

## 4. テーブル関係

```text
currency_strength_runs (1)
├─ currency_strength_pair_votes (N)
│  └─ currency_strength_contributions view (1票をBASE/QUOTEの2行へ展開)
└─ currency_strength_results (N)
```

- `currency_strength_pair_votes.run_id`は`currency_strength_runs.id`を参照します。
- `currency_strength_results.run_id`は`currency_strength_runs.id`を参照します。
- 親Run削除時は、外部キーの`ON DELETE CASCADE`で子レコードを削除します。
- CASCADEを有効にするには、使用するSQLite接続で`PRAGMA foreign_keys = ON`が必要です。

## 5. 共通データ表現

| 種別 | SQLite表現 | MQL5表現 | 備考 |
|---|---|---|---|
| ID | `INTEGER` | `long` | 主キーはAUTOINCREMENT |
| 日時 | `INTEGER` | `datetime` | Unix秒として保存 |
| 日時表示 | `TEXT` | `string` | `YYYY.MM.DD HH:MM:SS` |
| 真偽値 | `INTEGER` | `int` | 0=false、1=true |
| 時間足 | `INTEGER` | `ENUM_TIMEFRAMES`を`int`へ変換 | 表示には対応する`*_text`列を使用 |

タイムゾーンやUTCオフセットを示す列は保存しません。

## 6. `currency_strength_runs`

通貨強弱集計1回を表す親テーブルです。

### 6.1 列定義

| No. | 列名 | SQLite型 | MQL5型 | 制約 | 説明 |
|---:|---|---|---|---|---|
| 1 | `id` | INTEGER | long | PRIMARY KEY, AUTOINCREMENT | 集計ID |
| 2 | `calculated_at` | INTEGER | datetime | NOT NULL | テスターまたはチャート上で集計した市場時刻 |
| 3 | `m5_bar_time` | INTEGER | datetime | NOT NULL, DEFAULT 0 | 集計基準となるチャートシンボルのM5足開始時刻 |
| 4 | `m5_bar_time_text` | TEXT | string | NOT NULL, DEFAULT '' | `m5_bar_time`の目視用文字列 |
| 5 | `m15_bar_time` | INTEGER | datetime | NOT NULL | 同じ集計時点に対応するM15足開始時刻 |
| 6 | `calculation_version` | TEXT | string | NOT NULL | 集計ルール識別子。LIVEは`pair-direction-raw-v6`、TESTERは`pair-direction-closed-v1` |
| 7 | `source_mode` | TEXT | string | NOT NULL, DEFAULT 'LEGACY' | 集計実行モード。新規保存は`LIVE`または`TESTER`、移行前Runは`LEGACY` |
| 8 | `source_server` | TEXT | string | NOT NULL | 集計元の取引サーバー名 |
| 9 | `source_login` | INTEGER | long | NOT NULL | 集計元の口座ログイン番号 |
| 10 | `source_chart_id` | INTEGER | long | NOT NULL | 保存元チャートID。自然キーには含めない |
| 11 | `expected_pair_count` | INTEGER | int | NOT NULL | 期待する通貨ペア数。現行は28 |
| 12 | `valid_pair_count` | INTEGER | int | NOT NULL | 7時間足すべてを取得できた有効通貨ペア数 |
| 13 | `vote_count` | INTEGER | int | NOT NULL | 保存した票数。`valid_pair_count × 7` |
| 14 | `is_complete` | INTEGER | int | NOT NULL | 完全集計の場合1、部分集計の場合0 |
| 15 | `updated_at` | INTEGER | datetime | NOT NULL | スナップショットをINSERTまたはUPDATEした実時刻 |
| 16 | `updated_at_text` | TEXT | string | NOT NULL | `updated_at`のローカル時刻表示文字列 |

`is_complete`にDBのCHECK制約はありません。Serviceが`valid_pair_count == expected_pair_count`の場合に1を設定します。

### 6.2 インデックス

```sql
CREATE INDEX IF NOT EXISTS idx_currency_strength_runs_calculated_at
ON currency_strength_runs(calculated_at);

CREATE UNIQUE INDEX IF NOT EXISTS idx_currency_strength_runs_snapshot_mode_key
ON currency_strength_runs(
    m5_bar_time,
    calculation_version,
    source_mode,
    source_server,
    source_login
)
WHERE m5_bar_time > 0;

CREATE INDEX IF NOT EXISTS idx_currency_strength_runs_source_mode_calculated_at
ON currency_strength_runs(source_mode, calculated_at);
```

`m5_bar_time > 0`のRunは、M5足開始時刻・集計ルール・実行モード・取引サーバー・口座の組み合わせを自然キーとします。同じテストを再実行してもRunを増やさず、既存Runを更新します。`source_mode`を含むため、同じM5時刻・口座でもLIVEとTESTERのRunは別レコードとして共存できます。`m5_bar_time = 0`の旧Runは部分UNIQUEインデックスの対象外です。旧インデックス`idx_currency_strength_runs_snapshot_key`は新しいインデックス作成後に削除します。

## 7. `currency_strength_pair_votes`

通貨ペア・時間足単位の判定票と、その票を反映した直後の累積値を保存します。

### 7.1 列定義

| No. | 列名 | SQLite型 | MQL5型 | 制約 | 説明 |
|---:|---|---|---|---|---|
| 1 | `id` | INTEGER | long | PRIMARY KEY, AUTOINCREMENT | 票ID |
| 2 | `run_id` | INTEGER | long | NOT NULL, FK | `currency_strength_runs.id` |
| 3 | `pair_order` | INTEGER | int | NOT NULL | 28通貨ペア内の集計順。先頭は0 |
| 4 | `time_frame_order` | INTEGER | int | NOT NULL | 0=MN1、1=W1、2=D1、3=H4、4=H1、5=M15、6=M5 |
| 5 | `canonical_symbol_name` | TEXT | string | NOT NULL | 標準通貨ペア名。例: `USDJPY` |
| 6 | `resolved_symbol_name` | TEXT | string | NOT NULL | ブローカー環境で解決した実シンボル名 |
| 7 | `time_frame` | INTEGER | int | NOT NULL | `ENUM_TIMEFRAMES`の数値 |
| 8 | `time_frame_text` | TEXT | string | NOT NULL | 時間足表示文字列。`MN1`、`W1`、`D1`、`H4`、`H1`、`M15`、`M5` |
| 9 | `bar_time` | INTEGER | datetime | NOT NULL | 判定に使用した足の開始時刻。LIVEは現在足、TESTERは基準時刻`T`より前の確定足 |
| 10 | `bar_time_text` | TEXT | string | NOT NULL | `bar_time`の目視用文字列 |
| 11 | `base_currency` | TEXT | string | NOT NULL | 基軸通貨コード |
| 12 | `quote_currency` | TEXT | string | NOT NULL | 決済通貨コード |
| 13 | `is_buy` | INTEGER | int | NOT NULL, CHECK(is_buy IN (0, 1)) | BUYの場合1、SELLの場合0 |
| 14 | `oscillator_count` | INTEGER | int | NOT NULL | 判定元のオシレーター総合値 |
| 15 | `base_score` | INTEGER | int | NOT NULL, CHECK(base_score IN (-1, 1)) | 基軸通貨へ加算した票。BUY=+1、SELL=-1 |
| 16 | `base_score_after` | INTEGER | int | NOT NULL | 票反映後の基軸通貨・時間足別累積値 |
| 17 | `quote_score_after` | INTEGER | int | NOT NULL | 票反映後の決済通貨・時間足別累積値 |
| 18 | `updated_at` | INTEGER | datetime | NOT NULL | スナップショットのDB保存時刻 |
| 19 | `updated_at_text` | TEXT | string | NOT NULL | `updated_at`の目視用文字列 |

### 7.2 制約

```sql
FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ON DELETE CASCADE
UNIQUE(run_id, pair_order, time_frame_order)
CHECK(is_buy IN (0, 1))
CHECK(base_score IN (-1, 1))
```

### 7.3 インデックス

```sql
CREATE INDEX IF NOT EXISTS idx_currency_strength_votes_run_order
ON currency_strength_pair_votes(run_id, pair_order, time_frame_order);
```

新規CREATEしたDBでは、この明示インデックスと、同じ列を持つUNIQUE制約由来のSQLite自動インデックスが実質的に重複します。

## 8. `currency_strength_results`

1回の集計における通貨別の最終結果を保存します。

### 8.1 列定義

| No. | 列名 | SQLite型 | MQL5型 | 制約 | 説明 |
|---:|---|---|---|---|---|
| 1 | `id` | INTEGER | long | PRIMARY KEY, AUTOINCREMENT | 集計結果ID |
| 2 | `run_id` | INTEGER | long | NOT NULL, FK | `currency_strength_runs.id` |
| 3 | `currency_name` | TEXT | string | NOT NULL | 通貨コード |
| 4 | `mn1_score` | INTEGER | int | NOT NULL | MN1の未正規化合計 |
| 5 | `w1_score` | INTEGER | int | NOT NULL | W1の未正規化合計 |
| 6 | `d1_score` | INTEGER | int | NOT NULL | D1の未正規化合計 |
| 7 | `h4_score` | INTEGER | int | NOT NULL | H4の未正規化合計 |
| 8 | `h1_score` | INTEGER | int | NOT NULL | H1の未正規化合計 |
| 9 | `m15_score` | INTEGER | int | NOT NULL | M15の未正規化合計 |
| 10 | `m5_score` | INTEGER | int | NOT NULL | M5の未正規化合計 |
| 11 | `total_score` | INTEGER | int | NOT NULL | 7時間足の未正規化合計 |
| 12 | `mn1_sample_count` | INTEGER | int | NOT NULL | MN1の票数 |
| 13 | `w1_sample_count` | INTEGER | int | NOT NULL | W1の票数 |
| 14 | `d1_sample_count` | INTEGER | int | NOT NULL | D1の票数 |
| 15 | `h4_sample_count` | INTEGER | int | NOT NULL | H4の票数 |
| 16 | `h1_sample_count` | INTEGER | int | NOT NULL | H1の票数 |
| 17 | `m15_sample_count` | INTEGER | int | NOT NULL | M15の票数 |
| 18 | `m5_sample_count` | INTEGER | int | NOT NULL | M5の票数 |
| 19 | `total_sample_count` | INTEGER | int | NOT NULL | 7時間足の合計票数。完全な集計では49 |
| 20 | `long_term_average_score` | REAL | double | NOT NULL | MN1、W1、D1のスコア平均 |
| 21 | `long_term_average_rank` | INTEGER | int | NOT NULL | 長期平均の競技順位。未確定は0 |
| 22 | `long_medium_term_average_score` | REAL | double | NOT NULL | MN1、W1、D1、H4、H1のスコア平均 |
| 23 | `long_medium_term_average_rank` | INTEGER | int | NOT NULL | 長中期平均の競技順位。未確定は0 |
| 24 | `medium_term_average_score` | REAL | double | NOT NULL | D1、H4、H1のスコア平均 |
| 25 | `medium_term_average_rank` | INTEGER | int | NOT NULL | 中期平均の競技順位。未確定は0 |
| 26 | `medium_short_term_average_score` | REAL | double | NOT NULL | D1、H4、H1、M15、M5のスコア平均 |
| 27 | `medium_short_term_average_rank` | INTEGER | int | NOT NULL | 中短期平均の競技順位。未確定は0 |
| 28 | `short_term_average_score` | REAL | double | NOT NULL | H1、M15、M5のスコア平均 |
| 29 | `short_term_average_rank` | INTEGER | int | NOT NULL | 短期平均の競技順位。未確定は0 |
| 30 | `updated_at` | INTEGER | datetime | NOT NULL | スナップショットのDB保存時刻 |
| 31 | `updated_at_text` | TEXT | string | NOT NULL | `updated_at`の目視用文字列 |

### 8.2 制約

```sql
FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ON DELETE CASCADE
UNIQUE(run_id, currency_name)
```

### 8.3 インデックス

```sql
CREATE INDEX IF NOT EXISTS idx_currency_strength_results_run_currency
ON currency_strength_results(run_id, currency_name);
```

新規CREATEしたDBでは、この明示インデックスと、同じ列を持つUNIQUE制約由来のSQLite自動インデックスが実質的に重複します。

## 9. `currency_strength_contributions`ビュー

1票を基軸通貨と決済通貨の2行へ展開し、通貨別の加算経過を確認するためのビューです。`currency_strength_pair_votes`と`currency_strength_runs`をINNER JOINし、BASE行とQUOTE行を`UNION ALL`します。ビュー自体に並び順はありません。

### 9.1 出力列

| No. | 列名 | 元データ・計算式 |
|---:|---|---|
| 1 | `vote_id` | `pair_votes.id` |
| 2 | `run_id` | `pair_votes.run_id` |
| 3 | `calculated_at` | `runs.calculated_at` |
| 4 | `m5_bar_time` | `runs.m5_bar_time` |
| 5 | `m5_bar_time_text` | `runs.m5_bar_time_text` |
| 6 | `m15_bar_time` | `runs.m15_bar_time` |
| 7 | `source_mode` | `runs.source_mode` |
| 8 | `pair_order` | `pair_votes.pair_order` |
| 9 | `time_frame_order` | `pair_votes.time_frame_order` |
| 10 | `canonical_symbol_name` | `pair_votes.canonical_symbol_name` |
| 11 | `resolved_symbol_name` | `pair_votes.resolved_symbol_name` |
| 12 | `time_frame` | `pair_votes.time_frame` |
| 13 | `time_frame_text` | `pair_votes.time_frame_text` |
| 14 | `bar_time` | `pair_votes.bar_time` |
| 15 | `bar_time_text` | `pair_votes.bar_time_text` |
| 16 | `updated_at` | `pair_votes.updated_at` |
| 17 | `updated_at_text` | `pair_votes.updated_at_text` |
| 18 | `currency_side` | `BASE`または`QUOTE` |
| 19 | `currency_name` | BASE行は`base_currency`、QUOTE行は`quote_currency` |
| 20 | `score` | BASE行は`base_score`、QUOTE行は`0 - base_score` |
| 21 | `score_after` | BASE行は`base_score_after`、QUOTE行は`quote_score_after` |
| 22 | `is_buy` | `pair_votes.is_buy` |
| 23 | `oscillator_count` | `pair_votes.oscillator_count` |

## 10. 保存処理

### 10.1 保存条件

本番インジケーターの既定値は次のとおりです。

| 入力 | 既定値 | 動作 |
|---|---:|---|
| `refreshSeconds` | 60 | 初期化直後と60秒ごとに再集計 |
| `databaseSaveEveryRefresh` | false | 同じM15足では保存しない |
| `databaseSavePartialRuns` | false | 28ペアすべて有効な場合だけ保存 |
| `databaseSaveStartTime` | `2026.07.16 00:00` | TESTERのDB保存開始時刻。0はテスト開始時刻から保存 |
| `databaseRetentionDays` | 30 | 30日より古いLIVE Runを削除 |

- 通常チャートでは従来どおりタイマーで再集計し、現在のM15足が最後に保存成功したM15足と異なる場合に保存します。LIVEの保存失敗時は保存済みM15時刻を更新せず、次回タイマーで再試行します。
- ストラテジーテスターではタイマーを使用せず、`OnCalculate()`で新しいM5足を検出して集計・保存します。未処理のM5足が複数ある場合は古い時刻から順に追いつき処理を行います。
- TESTERでは同じM5足の全ティックで再計算せず、新しいM5足を検出した時だけ処理します。28ペア未準備の現在足は保留し、次のM5足で旧足として1回だけ再確認します。再確認後も未準備の場合は、M5時刻、ペア数、票数、および最初に検出した準備不足理由をログへ出力してその足をスキップし、後続時刻へ進みます。
- TESTERのDB保存失敗は未準備スキップと区別し、処理済みM5時刻を進めません。次のM5足で同じ基準時刻`T`から再試行し、後続時刻を先に保存しません。
- `databaseSavePartialRuns = false`では28ペアが揃った完全Runだけを保存します。`true`では部分Runを同じ自然キーへ保存し、保存成功後はその時刻を処理済みとします。
- `databaseSaveStartTime > 0`の場合、その時刻より前のM5足はDB保存対象および追いつき処理対象に含めません。保存開始前に一度だけ全28ペアのM5系列同期を開始し、同期済みペアのストキャスハンドルを初期化します。その後はテスター時刻を進めて履歴をウォームアップします。
- テスターを同じ期間・口座・集計ルールで再実行した場合、実行モードを含むM5自然キーが一致するRunをUPDATEし、PairVoteとResultを現在の集計結果で置き換えます。Run IDと自然キー該当件数は増えません。
- 部分保存を有効にした場合も、有効な1通貨ペアは必ず7票です。
- Serviceは保存前に`vote_count == valid_pair_count × 7`を検証します。
- DB初期化に失敗した場合、LIVEはインジケーターを継続してそのセッションのDB保存を無効化します。TESTERはDB記録を欠落させないため`INIT_FAILED`で開始を中止します。

テスター利用時は、テスト時間足をM5、最適化を無効、DB保存を行う場合は`databaseUseCommonFolder = true`に設定する必要があります。M5以外、最適化中、またはDB有効かつCommonフォルダ未使用の場合は初期化に失敗します。DB更新はローカルテストエージェントでの単一テストを前提とし、複数エージェントが同じCommon DBを同時更新する最適化には対応しません。

テストモデルは`Open prices only`（始値のみ）を使用します。始値モデルでは、シンボルごとに最初に参照した時間足より下位の時間足を後から参照できないため、系列準備、ストキャスハンドル生成、および売買判定はM5、M15、H1、H4、D1、W1、MN1の順で実行します。集計配列とDBの`time_frame_order`は従来どおり0=MN1、1=W1、2=D1、3=H4、4=H1、5=M15、6=M5です。

他シンボルの対象足がまだ確定していない場合は、そのM5スナップショットを現在足として保留します。次のM5足で1回再確認し、確定していれば保存します。まだ未確定の場合は準備不足としてスキップします。

保存開始直後からMN1の長期ストキャス`21,5,5`を利用する場合は、ストラテジーテスターの開始日を`databaseSaveStartTime`より十分前へ設定してください。目安として保存開始までに32本以上のMN1履歴が進む期間をウォームアップへ割り当てます。`databaseSaveStartTime = 0`ではテスト開始時刻から保存を試みるため、初期履歴が不足しているM5足は再確認後にスキップされます。

### 10.2 トランザクション

保存は次の順序で1トランザクションとして実行します。

1. SQLiteの現在時刻を1回取得し、Run、PairVote、Resultの全Entityへ同一の`updated_at`を設定
2. Runの`id`を0、`vote_count`を票配列件数へ設定
3. `BEGIN`
4. M5足開始時刻・集計ルール・実行モード・サーバー・口座の自然キーで既存Run IDを検索
5. 未登録の場合はRunをINSERTし、`last_insert_rowid()`を取得
6. 登録済みの場合は同じRun IDをUPDATEし、既存PairVoteとResultを削除
7. PairVoteとResultへ確定した`run_id`を設定
8. PairVoteを一括INSERT
9. Resultを一括INSERT
10. `COMMIT`

INSERT、UPDATE、子削除またはCOMMITに失敗した場合はROLLBACKし、Runの`id`と子Entityの`run_id`を0へ戻します。既存スナップショットの親子はトランザクション開始前の状態を維持します。

### 10.3 レコード更新時刻

- `updated_at`は1スナップショットにつき1回だけ取得し、3テーブルの全レコードへ同じ値を設定します。
- 市場時刻の`calculated_at`とは分離し、`updated_at`にはSQLite `strftime('%s', 'now')`による実際のDB保存時刻をUnix秒で保存します。
- `updated_at_text`は同じSQLite呼び出しの`strftime('%Y.%m.%d %H:%M:%S', 'now', 'localtime')`で生成します。
- 同じ自然キーを再保存した場合、Runの更新と再作成した全子レコードへ2回目の同一更新時刻を設定します。
- 外部ツールからレコードを更新しても、`updated_at`と`updated_at_text`は自動更新されません。

### 10.4 保持期間

- DB有効なLIVEでは、その更新が保存対象かどうかにかかわらず、初回の計算成功後と、前回の削除成功から24時間以上経過した場合に削除を実行します。
- `source_mode = LIVE`かつ`calculated_at < 現在時刻 - databaseRetentionDays × 86400`のRunだけが対象です。TESTERとLEGACYのRunは保持期間削除の対象外です。
- 境界時刻と同値のRunは削除しません。
- `databaseRetentionDays = 0`で自動削除を無効化します。
- 子レコードは`ON DELETE CASCADE`で削除します。
- ストラテジーテスターでは過去データをテスト終了まで保持するため、自動削除を実行しません。

## 11. 初期化と既存DB移行

`CurrencyStrengthPersistenceService.createTables()`は次の順序で実行します。

1. `PRAGMA foreign_keys = ON`を設定し、有効化を確認
2. `currency_strength_runs`を作成・移行
3. `currency_strength_pair_votes`を作成・移行
4. `currency_strength_results`を作成・移行
5. `currency_strength_contributions`をDROP/CREATE

### 11.1 RunのM5基準時刻列、実行モードと自然キー

既存の`currency_strength_runs`に列がない場合は、次の3列を追加します。

```sql
m5_bar_time INTEGER NOT NULL DEFAULT 0
m5_bar_time_text TEXT NOT NULL DEFAULT ''
source_mode TEXT NOT NULL DEFAULT 'LEGACY'
```

M5基準時刻列を持たない旧DBでは、移行前のRunがどのM5足で集計されたか確定できないため、追加後も`m5_bar_time = 0`、`m5_bar_time_text = ''`のまま維持します。履歴の`m15_bar_time`からM5時刻を推測して補完しません。`source_mode`追加前のRunは、M5基準時刻の有無にかかわらずLIVEとTESTERを判別できないため`source_mode = LEGACY`とし、既存のM5基準時刻値は変更しません。

移行後は`source_mode`を含む部分UNIQUEインデックス`idx_currency_strength_runs_snapshot_mode_key`を作成し、旧インデックス`idx_currency_strength_runs_snapshot_key`を削除します。`m5_bar_time = 0`の旧Runは部分UNIQUEインデックスの対象外であるため、旧Run同士の重複は移行を妨げません。

### 11.2 更新時刻列

既存テーブルに列がない場合は、次の定義で末尾へ追加します。

```sql
updated_at INTEGER NOT NULL DEFAULT 0
updated_at_text TEXT NOT NULL DEFAULT ''
```

補完規則は次のとおりです。

| テーブル | `updated_at = 0`の補完元 |
|---|---|
| Run | `calculated_at`。0以下の場合はSQLite現在時刻 |
| PairVote | 親Runの`updated_at`、非0の`bar_time`、SQLite現在時刻の順 |
| Result | 親Runの`updated_at`、SQLite現在時刻の順 |

空の`updated_at_text`は`strftime('%Y.%m.%d %H:%M:%S', updated_at, 'unixepoch', 'localtime')`で補完します。

### 11.3 ResultのMN1・W1・M5列

既存の`currency_strength_results`に列がない場合は、次の6列を追加します。

```sql
mn1_score INTEGER NOT NULL DEFAULT 0
w1_score INTEGER NOT NULL DEFAULT 0
mn1_sample_count INTEGER NOT NULL DEFAULT 0
w1_sample_count INTEGER NOT NULL DEFAULT 0
m5_score INTEGER NOT NULL DEFAULT 0
m5_sample_count INTEGER NOT NULL DEFAULT 0
```

既存の`pair-direction-raw-v1`はMN1とW1を集計していないため、対応する4列は0のままとします。v1と`pair-direction-raw-v2`はM5を集計していないため、M5の2列は0のままとします。既存行の`total_score`と`total_sample_count`は当時の時間足数の値を維持し、再計算しません。`pair-direction-raw-v3`以降では7時間足すべてを保存し、完全な集計の`total_sample_count`は49です。

新規CREATE時は論理的な時間足順にMN1・W1列をD1列より前、M5列をM15列の後へ配置します。ALTER TABLEは列を末尾へ追加するため、既存DBの物理列順は新規DBと異なります。DAOはINSERT列名を明示して保存します。

### 11.4 Resultの長期・中期・短期平均スコア列

既存の`currency_strength_results`に列がない場合は、次の3列を追加します。

```sql
long_term_average_score REAL NOT NULL DEFAULT 0.0
medium_term_average_score REAL NOT NULL DEFAULT 0.0
short_term_average_score REAL NOT NULL DEFAULT 0.0
```

既存のv1～v3行は期間別平均を保存していないため、追加した3列は0のままとし、履歴値を再計算しません。新規の`pair-direction-raw-v4`から3平均を保存します。新規CREATE時は`total_sample_count`の後へ配置します。ALTER TABLEでは物理的に末尾へ追加されますが、DAOはINSERT列名を明示して保存します。

### 11.5 Resultの長期・中期・短期平均スコア順位列

既存の`currency_strength_results`に列がない場合は、次の3列を追加します。

```sql
long_term_average_rank INTEGER NOT NULL DEFAULT 0
medium_term_average_rank INTEGER NOT NULL DEFAULT 0
short_term_average_rank INTEGER NOT NULL DEFAULT 0
```

既存のv1～v4行は期間別平均順位を保存していないため、追加した3列は0のままとし、履歴順位を再計算しません。新規の`pair-direction-raw-v5`から完全Runの競技順位を保存します。部分Runでは3列すべて0です。新規CREATE時は各平均スコア列の隣へ配置します。ALTER TABLEでは物理的に末尾へ追加されますが、DAOはINSERT列名を明示して保存します。

### 11.6 Resultの長中期・中短期平均列

既存の`currency_strength_results`に列がない場合は、次の4列を追加します。

```sql
long_medium_term_average_score REAL NOT NULL DEFAULT 0.0
long_medium_term_average_rank INTEGER NOT NULL DEFAULT 0
medium_short_term_average_score REAL NOT NULL DEFAULT 0.0
medium_short_term_average_rank INTEGER NOT NULL DEFAULT 0
```

既存のv1～v5行は長中期・中短期平均を保存していないため、追加した4列は0のままとし、履歴値を再計算しません。新規の`pair-direction-raw-v6`から2平均と完全Runの競技順位を保存します。部分Runでは2順位を0とします。新規CREATE時は長中期を長期の後、中短期を中期の後へ配置します。ALTER TABLEでは物理的に末尾へ追加されますが、DAOはINSERT列名を明示して保存します。

### 11.7 PairVote表示列

既存テーブルに列がない場合は、`time_frame_text`と`bar_time_text`を`TEXT NOT NULL DEFAULT ''`で追加します。

- 空の`time_frame_text`はMN1、W1、D1、H4、H1、M15、M5へ変換し、その他の値は時間足数値の文字列にします。
- 空の`bar_time_text`は`bar_time`からSQLiteの`strftime`で生成します。

### 11.8 旧PairVote順序の二段階移行

`pair-direction-raw-v1`の`time_frame_order`は0=D1、1=H4、2=H1、3=M15です。共通の7時間足順へ合わせるため、既存v1票を2=D1、3=H4、4=H1、5=M15へ移行します。履歴Runの`calculation_version`は`pair-direction-raw-v1`のまま維持し、MN1・W1・M5票は追加しません。v2票の順序は変更せず、v3以降のM5は6=M5で保存します。

`UNIQUE(run_id, pair_order, time_frame_order)`との一時的な衝突を避けるため、移行は同一トランザクション内で次の二段階で実行します。

1. 旧orderと`time_frame`の組み合わせが一致する行を、`-100 - 旧order`で-100～-103へ退避
2. `time_frame`を基準に-100→2、-101→3、-102→4、-103→5へ確定

概念SQLは次のとおりです。`{PERIOD_*}`にはMQL5の`ENUM_TIMEFRAMES`数値を設定します。

```sql
UPDATE currency_strength_pair_votes
SET time_frame_order = -100 - time_frame_order
WHERE (time_frame_order = 0 AND time_frame = {PERIOD_D1})
   OR (time_frame_order = 1 AND time_frame = {PERIOD_H4})
   OR (time_frame_order = 2 AND time_frame = {PERIOD_H1})
   OR (time_frame_order = 3 AND time_frame = {PERIOD_M15});

UPDATE currency_strength_pair_votes
SET time_frame_order = CASE time_frame
    WHEN {PERIOD_D1} THEN 2
    WHEN {PERIOD_H4} THEN 3
    WHEN {PERIOD_H1} THEN 4
    WHEN {PERIOD_M15} THEN 5
    ELSE time_frame_order
END
WHERE (time_frame_order = -100 AND time_frame = {PERIOD_D1})
   OR (time_frame_order = -101 AND time_frame = {PERIOD_H4})
   OR (time_frame_order = -102 AND time_frame = {PERIOD_H1})
   OR (time_frame_order = -103 AND time_frame = {PERIOD_M15});
```

対象は`calculation_version`ではなく、旧orderと実際の`time_frame`の一致で限定します。このため移行済み行や新規v2以降の行は再実行しても変更されません。二段階の途中で失敗した場合はトランザクションをROLLBACKします。移行後のv1 Runは112票のまま、v2の完全なRunは168票、v3以降の完全なRunは196票です。

### 11.9 移行上の注意

- RunのM5基準時刻2列と`source_mode`には、新規CREATE・ALTER TABLEのどちらもDEFAULT句があります。それ以外は、新規CREATEしたDBの列にDEFAULT句がなく、ALTER TABLEで追加した更新時刻・表示列にはDEFAULT 0または空文字が残ります。
- ALTER TABLEで追加したMN1・W1・M5の6列には`DEFAULT 0`が残ります。
- ALTER TABLEで追加した期間別平均の5列には`DEFAULT 0.0`が残ります。
- ALTER TABLEで追加した期間別平均順位の5列には`DEFAULT 0`が残ります。
- ALTER TABLEは列を末尾へ追加するため、古いDBでは新規CREATE時と物理列順が異なる場合があります。INSERTは列名を指定するため保存処理には影響しません。
- 自動移行の対象はRunのM5基準時刻列、`source_mode`、表示列、更新時刻列、MN1・W1・M5・期間別平均・平均順位のResult列、および旧PairVote順序です。それ以外の列や制約の差異は自動再構築しません。
- 補完対象は数値0または空文字のレコードだけです。非空の誤値は修正しません。
- M5基準時刻とPairVoteの日時文字列はMQL5で生成し、更新時刻文字列と既存データ移行時の補完文字列はSQLiteで生成します。

## 12. Entity・DAO対応

| テーブル | Entity | DAO |
|---|---|---|
| `currency_strength_runs` | [CurrencyStrengthRunEntity](../../Include/Mstng/Database/Entity/CurrencyStrengthRunEntity.mqh) | [CurrencyStrengthRunDao](../../Include/Mstng/Database/Dao/CurrencyStrengthRunDao.mqh) |
| `currency_strength_pair_votes` | [CurrencyStrengthPairVoteEntity](../../Include/Mstng/Database/Entity/CurrencyStrengthPairVoteEntity.mqh) | [CurrencyStrengthPairVoteDao](../../Include/Mstng/Database/Dao/CurrencyStrengthPairVoteDao.mqh) |
| `currency_strength_results` | [CurrencyStrengthResultEntity](../../Include/Mstng/Database/Entity/CurrencyStrengthResultEntity.mqh) | [CurrencyStrengthResultDao](../../Include/Mstng/Database/Dao/CurrencyStrengthResultDao.mqh) |

関連実装:

- [CurrencyStrengthPersistenceService](../../Include/Mstng/Database/Service/CurrencyStrengthPersistenceService.mqh)
- [CurrencyStrengthCalculator](../../Include/Mstng/Strength/CurrencyStrengthCalculator.mqh)
- [CurrencyStrengthElliot](../../Indicators/CurrencyStrengthElliot.mq5)
- [CurrencyStrengthDatabaseSmokeTest](../../Scripts/Mstng/Database/CurrencyStrengthDatabaseSmokeTest.mq5)

## 13. 確認用SQL

### 13.1 最新Run

```sql
SELECT *
FROM currency_strength_runs
ORDER BY id DESC
LIMIT 20;
```

### 13.2 最新Runの票内訳

```sql
SELECT *
FROM currency_strength_pair_votes
WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)
ORDER BY pair_order, time_frame_order;
```

### 13.3 最新Runの通貨別結果

```sql
SELECT currency_name,
       mn1_score,
       w1_score,
       d1_score,
       h4_score,
       h1_score,
       m15_score,
       m5_score,
       total_score,
       mn1_sample_count,
       w1_sample_count,
       d1_sample_count,
       h4_sample_count,
       h1_sample_count,
       m15_sample_count,
       m5_sample_count,
       total_sample_count,
       long_term_average_score,
       long_term_average_rank,
       long_medium_term_average_score,
       long_medium_term_average_rank,
       medium_term_average_score,
       medium_term_average_rank,
       medium_short_term_average_score,
       medium_short_term_average_rank,
       short_term_average_score,
       short_term_average_rank,
       updated_at_text
FROM currency_strength_results
WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)
ORDER BY total_score DESC, currency_name;
```

### 13.4 時間足・通貨別の再集計

```sql
SELECT time_frame_order,
       time_frame_text,
       currency_name,
       SUM(score) AS score
FROM currency_strength_contributions
WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)
GROUP BY time_frame_order, time_frame_text, currency_name
ORDER BY time_frame_order, score DESC, currency_name;
```

### 13.5 全時間足の再集計

```sql
SELECT currency_name,
       SUM(score) AS calculated_total
FROM currency_strength_contributions
WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)
GROUP BY currency_name
ORDER BY calculated_total DESC, currency_name;
```

### 13.6 完全集計件数の確認

`pair-direction-raw-v6`または`pair-direction-closed-v1`の完全なRunでは、`vote_count`と実票数が196、Resultが8、Contributionが392になります。

```sql
SELECT
    (SELECT calculation_version
     FROM currency_strength_runs
     WHERE id = (SELECT MAX(id) FROM currency_strength_runs)) AS calculation_version,
    (SELECT vote_count
     FROM currency_strength_runs
     WHERE id = (SELECT MAX(id) FROM currency_strength_runs)) AS saved_vote_count,
    (SELECT COUNT(*)
     FROM currency_strength_pair_votes
     WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)) AS actual_vote_count,
    (SELECT COUNT(*)
     FROM currency_strength_results
     WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)) AS actual_result_count,
    (SELECT COUNT(*)
     FROM currency_strength_contributions
     WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)) AS contribution_count;
```

### 13.7 時間足順序の確認

`pair-direction-raw-v3`～`pair-direction-raw-v6`および`pair-direction-closed-v1`の完全なRunでは、0～6が各28票になります。

```sql
SELECT time_frame_order,
       time_frame_text,
       COUNT(*) AS vote_count
FROM currency_strength_pair_votes
WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)
GROUP BY time_frame_order, time_frame_text
ORDER BY time_frame_order;
```

期待順は0=MN1、1=W1、2=D1、3=H4、4=H1、5=M15、6=M5です。

### 13.8 長中期・中短期平均と順位の確認

最新Runについて、保存した平均、時間足別スコアから再計算した期待値、保存順位、競技順位の期待値を並べて確認します。平均の保存値と期待値の差が0で、保存順位と期待順位が一致すれば正常です。

```sql
WITH latest_results AS (
    SELECT *
    FROM currency_strength_results
    WHERE run_id = (SELECT MAX(id) FROM currency_strength_runs)
)
SELECT result.currency_name,
       result.long_medium_term_average_score,
       (result.mn1_score + result.w1_score + result.d1_score
        + result.h4_score + result.h1_score) / 5.0
           AS expected_long_medium_term_average_score,
       result.long_medium_term_average_rank,
       1 + (
           SELECT COUNT(*)
           FROM latest_results higher
           WHERE higher.long_medium_term_average_score
               - result.long_medium_term_average_score > 0.000001
       ) AS expected_long_medium_term_average_rank,
       result.medium_short_term_average_score,
       (result.d1_score + result.h4_score + result.h1_score
        + result.m15_score + result.m5_score) / 5.0
           AS expected_medium_short_term_average_score,
       result.medium_short_term_average_rank,
       1 + (
           SELECT COUNT(*)
           FROM latest_results higher
           WHERE higher.medium_short_term_average_score
               - result.medium_short_term_average_score > 0.000001
       ) AS expected_medium_short_term_average_rank
FROM latest_results result
ORDER BY result.total_score DESC, result.currency_name;
```

### 13.9 外部キー確認

外部ツールでは接続ごとに外部キーを有効化してから確認します。

```sql
PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;
```

### 13.10 M5自然キーの重複確認

`m5_bar_time > 0`の新規Runについて、次のSQLが0行なら自然キーの重複はありません。`m5_bar_time = 0`の移行前Runは対象外です。

```sql
SELECT m5_bar_time,
       calculation_version,
       source_mode,
       source_server,
       source_login,
       COUNT(*) AS run_count
FROM currency_strength_runs
WHERE m5_bar_time > 0
GROUP BY m5_bar_time,
         calculation_version,
         source_mode,
         source_server,
         source_login
HAVING COUNT(*) > 1;
```

## 14. スモークテスト

`Scripts/Mstng/Database/CurrencyStrengthDatabaseSmokeTest.mq5`は、`source_mode = TESTER`を含む同じM5自然キーへ、内容の異なるスナップショットを2回保存します。

- 自然キー該当Run: 1件。Run全件数も1件となるのは`recreateDatabaseObjects = true`の場合だけ
- 1回目のUSDJPY票: MN1、W1、D1、H4、M15はBUY、H1、M5はSELLの7件
- 2回目のUSDJPY票: MN1、W1、D1、H4、M15はSELL、H1、M5はBUYの7件
- Result: USD、JPYの2件
- Contributionsビュー: 14件。`source_mode`列は親Runを参照
- 2回目の長中期平均: USDは-0.60・順位2、JPYは+0.60・順位1
- 2回目の中短期平均: USDは-0.20・順位2、JPYは+0.20・順位1

2回目もRun IDが変わらないこと、自然キー該当件数が1であること、子件数が増えないこと、2回目のRun・先頭票・Result値へ置換されたことを検証します。Run全件数が1であることは、実行前に3テーブルを削除する`recreateDatabaseObjects = true`の場合だけ検証します。また、`source_mode = TESTER`、`updated_at`が2回目保存時の実時刻であり、3テーブルの`updated_at`と`updated_at_text`が一致することを確認します。DBファイルと保存したテストレコードは実行後も残ります。

このテストはCalculatorからEntityへの通常変換、保存条件、保持期間削除、ROLLBACK、および既定の`recreateDatabaseObjects = true`では既存DBのALTER TABLE経路を直接検証しません。

`Scripts/Mstng/Strength/CurrencyStrengthCalculationSmokeTest.mq5`は28通貨ペアの実判定について、5種類の平均を時間足別スコアから再計算し、8通貨内の競技順位、全通貨の平均合計0、部分集計時の順位0、およびM5・M15基準時刻と`source_mode = LIVE`を渡したDB保存を検証します。このスクリプトはオンラインチャート用であり、TESTERの確定足集計やM5追いつき処理は検証しません。
