# 通貨強弱データベース仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象機能 | 主要8通貨・28通貨ペアの通貨強弱集計履歴 |
| DBMS | MetaTrader 5組み込みSQLite |
| LIVE集計ルール | `pair-direction-closed-v1` |
| TESTER集計ルール | `pair-direction-closed-v1` |
| 最終更新日 | 2026-07-20 |
| 実装 | `CurrencyStrengthElliot`、`CurrencyStrengthYearlyPersistenceService`、`CurrencyStrengthPersistenceService`、`CurrencyStrengthYearlyRankQueryService`、3 Entity・3 DAO |

本書は、通貨強弱集計で使用する3テーブル、1ビュー、インデックス、保存処理および既存DB移行処理を定義します。

## 2. データベースファイル

### 2.1 本番用

| 項目 | 既定値 |
|---|---|
| ベースファイル名 | `mstng-currency-strength.sqlite` |
| 年別分割 | `databaseSplitByYear = true` |
| 実ファイル名 | `mstng-currency-strength-YYYY.sqlite` |
| DB保存有無 | `databaseEnabled = true` |
| Commonフォルダ使用 | `databaseUseCommonFolder = true` |
| オープンモード | READWRITE、CREATE、Common使用時はCOMMON |

既定では、保存対象Runの`m5_bar_time`からブローカー時刻の西暦年を取得し、ベースファイル名の拡張子直前へ`-YYYY`を追加します。たとえば2026年のRunは`mstng-currency-strength-2026.sqlite`へ保存します。`calculated_at`が翌年でも`m5_bar_time`が前年なら前年DBが保存先です。Run、196件のPairVote、8件のResultは必ず同じ年DBへ1トランザクションで保存します。

保存場所は次のとおりです。

- Commonフォルダ使用時: `%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-currency-strength-2026.sqlite`
- Commonフォルダ未使用時: 対象ターミナルの`MQL5\Files\mstng-currency-strength-2026.sqlite`

年が変わる場合は、新年DBのオープンとテーブル準備に成功してから旧年DBを閉じます。同じ年へ再保存する場合は同じDB接続と既存の自然キーUpsertを使用します。`databaseSplitByYear = false`にすると、従来どおり`databaseFileName`をそのまま単一DBとして使用します。

年別DBの`run_id`はファイル内でのみ一意です。複数年を扱う処理では、Runを`年またはDBファイル名 + run_id`で識別します。既存の単一DB`mstng-currency-strength.sqlite`は自動移行しません。年別分割を有効にした後も旧ファイルは残るため、必要な履歴移行は別途実施します。

### 2.2 スモークテスト用

| 項目 | 既定値 |
|---|---|
| ファイル名 | `mstng-currency-strength-smoke-test.sqlite` |
| Commonフォルダ使用 | `useCommonFolder = true` |
| DBオブジェクト再作成 | `recreateDatabaseObjects = true` |

`recreateDatabaseObjects = true`では、指定したDB内のビューと3テーブルを削除します。本番DBのファイル名を指定して実行してはいけません。

## 3. 集計仕様

対象通貨は`USD`、`JPY`、`EUR`、`GBP`、`AUD`、`NZD`、`CAD`、`CHF`の8通貨です。28通貨ペアをMN1、W1、D1、H4、H1、M15、M5の7時間足で判定します。時間足の集計順はMN1、W1、D1、H4、H1、M15、M5です。

LIVEとTESTERは、新しいM5足の開始時刻をスナップショット基準時刻`T`とし、各時間足について`T`の時点で確定済みの最新足、すなわち開始時刻が`T`より前で、`T`を含む足の1本前にあたる足を判定します。基準チャートシンボルで時間足別の確定足開始時刻を決め、各通貨ペアで同じ開始時刻の足を優先します。実履歴にその足がない場合は、期待時刻より前に存在する直近の確定足へフォールバックし、実際の時刻をPairVoteの`bar_time`へ保存します。

両環境とも`calculation_version = pair-direction-closed-v1`を使用し、`source_mode`だけをLIVEとTESTERに分けます。`m5_bar_time`には両環境とも`T`を保存します。`calculated_at`はLIVEでは実際の集計時刻、TESTERでは`T`です。既存の`pair-direction-raw-v6 / LIVE`行は移行せず、新しい確定足基準の行と併存します。

Runの基準時刻は`m5_bar_time`だけです。PairVoteの`bar_time`には実際に判定した確定足の開始時刻を保存します。このためM5票の`bar_time`は`T`ではなく直前M5足、M15票も`T`より前の確定済みM15足の開始時刻となります。

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
| 2 | `m5_bar_time` | INTEGER | datetime | NOT NULL, DEFAULT 0 | 集計基準となるチャートシンボルのM5足開始時刻 |
| 3 | `m5_bar_time_text` | TEXT | string | NOT NULL, DEFAULT '' | `m5_bar_time`の目視用文字列 |
| 4 | `calculated_at` | INTEGER | datetime | NOT NULL | テスターまたはチャート上で集計した市場時刻 |
| 5 | `source_mode` | TEXT | string | NOT NULL, DEFAULT 'LEGACY' | 集計実行モード。新規保存は`LIVE`または`TESTER`、移行前Runは`LEGACY` |
| 6 | `calculation_version` | TEXT | string | NOT NULL | 集計ルール識別子。LIVE・TESTERとも`pair-direction-closed-v1` |
| 7 | `is_complete` | INTEGER | int | NOT NULL | 完全集計の場合1、部分集計の場合0 |
| 8 | `valid_pair_count` | INTEGER | int | NOT NULL | 7時間足すべてを取得できた有効通貨ペア数 |
| 9 | `expected_pair_count` | INTEGER | int | NOT NULL | 期待する通貨ペア数。現行は28 |
| 10 | `vote_count` | INTEGER | int | NOT NULL | 保存した票数。`valid_pair_count × 7` |
| 11 | `source_server` | TEXT | string | NOT NULL | 集計元の取引サーバー名 |
| 12 | `source_login` | INTEGER | long | NOT NULL | 集計元の口座ログイン番号 |
| 13 | `source_chart_id` | INTEGER | long | NOT NULL | 保存元チャートID。自然キーには含めない |
| 14 | `updated_at` | INTEGER | datetime | NOT NULL | スナップショットをINSERTまたはUPDATEした実時刻 |
| 15 | `updated_at_text` | TEXT | string | NOT NULL | `updated_at`のローカル時刻表示文字列 |

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

CREATE INDEX IF NOT EXISTS idx_currency_strength_runs_rank_lookup
ON currency_strength_runs(
    calculation_version,
    source_mode,
    source_server,
    source_login,
    m5_bar_time DESC
)
WHERE is_complete = 1 AND m5_bar_time > 0;

CREATE INDEX IF NOT EXISTS idx_currency_strength_runs_source_mode_calculated_at
ON currency_strength_runs(source_mode, calculated_at);
```

`m5_bar_time > 0`のRunは、M5足開始時刻・集計ルール・実行モード・取引サーバー・口座の組み合わせを自然キーとします。同じテストを再実行してもRunを増やさず、既存Runを更新します。`source_mode`を含むため、同じM5時刻・口座でもLIVEとTESTERのRunは別レコードとして共存できます。`m5_bar_time = 0`の旧Runは部分UNIQUEインデックスの対象外です。`idx_currency_strength_runs_rank_lookup`は完全Runの順位検索で等価条件を先に絞り、指定M5時刻以前を新しい順に取得するために使用します。旧インデックス`idx_currency_strength_runs_snapshot_key`は新しいインデックス作成後に削除します。

## 7. `currency_strength_pair_votes`

通貨ペア・時間足単位の判定票と、その票を反映した直後の累積値を保存します。

### 7.1 列定義

| No. | 列名 | SQLite型 | MQL5型 | 制約 | 説明 |
|---:|---|---|---|---|---|
| 1 | `id` | INTEGER | long | PRIMARY KEY, AUTOINCREMENT | 票ID |
| 2 | `run_id` | INTEGER | long | NOT NULL, FK | `currency_strength_runs.id` |
| 3 | `canonical_symbol_name` | TEXT | string | NOT NULL | 標準通貨ペア名。例: `USDJPY` |
| 4 | `resolved_symbol_name` | TEXT | string | NOT NULL | ブローカー環境で解決した実シンボル名 |
| 5 | `pair_order` | INTEGER | int | NOT NULL | 28通貨ペア内の集計順。先頭は0 |
| 6 | `time_frame` | INTEGER | int | NOT NULL | `ENUM_TIMEFRAMES`の数値 |
| 7 | `time_frame_text` | TEXT | string | NOT NULL | 時間足表示文字列。`MN1`、`W1`、`D1`、`H4`、`H1`、`M15`、`M5` |
| 8 | `time_frame_order` | INTEGER | int | NOT NULL | 0=MN1、1=W1、2=D1、3=H4、4=H1、5=M15、6=M5 |
| 9 | `bar_time` | INTEGER | datetime | NOT NULL | 判定に使用した、基準時刻`T`より前の確定足開始時刻 |
| 10 | `bar_time_text` | TEXT | string | NOT NULL | `bar_time`の目視用文字列 |
| 11 | `is_buy` | INTEGER | int | NOT NULL, CHECK(is_buy IN (0, 1)) | BUYの場合1、SELLの場合0 |
| 12 | `oscillator_count` | INTEGER | int | NOT NULL | 判定元のオシレーター総合値 |
| 13 | `base_currency` | TEXT | string | NOT NULL | 基軸通貨コード |
| 14 | `base_score` | INTEGER | int | NOT NULL, CHECK(base_score IN (-1, 1)) | 基軸通貨へ加算した票。BUY=+1、SELL=-1 |
| 15 | `base_score_after` | INTEGER | int | NOT NULL | 票反映後の基軸通貨・時間足別累積値 |
| 16 | `quote_currency` | TEXT | string | NOT NULL | 決済通貨コード |
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
| 4 | `total_score` | INTEGER | int | NOT NULL | 7時間足の未正規化合計 |
| 5 | `total_sample_count` | INTEGER | int | NOT NULL | 7時間足の合計票数。完全な集計では49 |
| 6 | `long_medium_term_average_score` | REAL | double | NOT NULL | MN1、W1、D1、H4、H1のスコア平均 |
| 7 | `long_medium_term_average_rank` | INTEGER | int | NOT NULL | 長中期平均の競技順位。未確定は0 |
| 8 | `medium_short_term_average_score` | REAL | double | NOT NULL | D1、H4、H1、M15、M5のスコア平均 |
| 9 | `medium_short_term_average_rank` | INTEGER | int | NOT NULL | 中短期平均の競技順位。未確定は0 |
| 10 | `long_term_average_score` | REAL | double | NOT NULL | MN1、W1、D1のスコア平均 |
| 11 | `long_term_average_rank` | INTEGER | int | NOT NULL | 長期平均の競技順位。未確定は0 |
| 12 | `medium_term_average_score` | REAL | double | NOT NULL | D1、H4、H1のスコア平均 |
| 13 | `medium_term_average_rank` | INTEGER | int | NOT NULL | 中期平均の競技順位。未確定は0 |
| 14 | `short_term_average_score` | REAL | double | NOT NULL | H1、M15、M5のスコア平均 |
| 15 | `short_term_average_rank` | INTEGER | int | NOT NULL | 短期平均の競技順位。未確定は0 |
| 16 | `mn1_score` | INTEGER | int | NOT NULL | MN1の未正規化合計 |
| 17 | `w1_score` | INTEGER | int | NOT NULL | W1の未正規化合計 |
| 18 | `d1_score` | INTEGER | int | NOT NULL | D1の未正規化合計 |
| 19 | `h4_score` | INTEGER | int | NOT NULL | H4の未正規化合計 |
| 20 | `h1_score` | INTEGER | int | NOT NULL | H1の未正規化合計 |
| 21 | `m15_score` | INTEGER | int | NOT NULL | M15の未正規化合計 |
| 22 | `m5_score` | INTEGER | int | NOT NULL | M5の未正規化合計 |
| 23 | `mn1_sample_count` | INTEGER | int | NOT NULL | MN1の票数 |
| 24 | `w1_sample_count` | INTEGER | int | NOT NULL | W1の票数 |
| 25 | `d1_sample_count` | INTEGER | int | NOT NULL | D1の票数 |
| 26 | `h4_sample_count` | INTEGER | int | NOT NULL | H4の票数 |
| 27 | `h1_sample_count` | INTEGER | int | NOT NULL | H1の票数 |
| 28 | `m15_sample_count` | INTEGER | int | NOT NULL | M15の票数 |
| 29 | `m5_sample_count` | INTEGER | int | NOT NULL | M5の票数 |
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

1票を基軸通貨と決済通貨の2行へ展開し、通貨別の加算経過を確認するためのビューです。`currency_strength_pair_votes`と`currency_strength_runs`をINNER JOINし、BASE行とQUOTE行を`UNION ALL`します。ビュー自体に並び順はありません。既存ビューの定義が現行SQLと一致する場合は再作成せず、定義が異なる場合だけDROP/CREATEします。

### 9.1 出力列

| No. | 列名 | 元データ・計算式 |
|---:|---|---|
| 1 | `run_id` | `pair_votes.run_id` |
| 2 | `m5_bar_time` | `runs.m5_bar_time` |
| 3 | `m5_bar_time_text` | `runs.m5_bar_time_text` |
| 4 | `source_mode` | `runs.source_mode` |
| 5 | `currency_name` | BASE行は`base_currency`、QUOTE行は`quote_currency` |
| 6 | `currency_side` | `BASE`または`QUOTE` |
| 7 | `score` | BASE行は`base_score`、QUOTE行は`0 - base_score` |
| 8 | `score_after` | BASE行は`base_score_after`、QUOTE行は`quote_score_after` |
| 9 | `canonical_symbol_name` | `pair_votes.canonical_symbol_name` |
| 10 | `resolved_symbol_name` | `pair_votes.resolved_symbol_name` |
| 11 | `time_frame` | `pair_votes.time_frame` |
| 12 | `time_frame_text` | `pair_votes.time_frame_text` |
| 13 | `bar_time` | `pair_votes.bar_time` |
| 14 | `bar_time_text` | `pair_votes.bar_time_text` |
| 15 | `is_buy` | `pair_votes.is_buy` |
| 16 | `oscillator_count` | `pair_votes.oscillator_count` |
| 17 | `pair_order` | `pair_votes.pair_order` |
| 18 | `time_frame_order` | `pair_votes.time_frame_order` |
| 19 | `vote_id` | `pair_votes.id` |
| 20 | `calculated_at` | `runs.calculated_at` |
| 21 | `updated_at` | `pair_votes.updated_at` |
| 22 | `updated_at_text` | `pair_votes.updated_at_text` |

## 10. 保存処理

### 10.1 保存条件

本番インジケーターの既定値は次のとおりです。

| 入力 | 既定値 | 動作 |
|---|---:|---|
| `refreshSeconds` | 60 | 初期化直後と60秒ごとに定期再集計 |
| `databaseSplitByYear` | true | `m5_bar_time`の年ごとにDBファイルを分割 |
| `databaseSaveEveryRefresh` | false | 同じM5足では保存しない |
| `databaseSavePartialRuns` | false | 28ペアすべて有効な場合だけ保存 |
| `databaseSaveStartTime` | `2026.07.16 00:00` | TESTERのDB保存開始時刻。0はテスト開始時刻から保存 |
| `databaseRetentionDays` | 30 | 30日より古いLIVE Runを削除 |

- 通常チャートでは`OnCalculate()`でM5バー時刻の変化を検出し、新規M5足の最初のティックで集計・保存を開始します。同じM5足の後続ティックでは再集計しません。タイマーは同じM5足の定期表示更新と、系列準備またはDB保存失敗時の再試行に使用します。
- ストラテジーテスターではタイマーを使用せず、`OnCalculate()`で新しいM5足を検出して集計・保存します。未処理のM5足が複数ある場合は古い時刻から順に追いつき処理を行います。
- TESTERでは同じM5足の全ティックで再計算せず、新しいM5足を検出した時だけ処理します。28ペア未準備の現在足は保留し、次のM5足で旧足として再確認します。再確認後も未準備の場合は処理済みM5時刻を進めず、M5時刻、ペア数、票数、および最初に検出した準備不足理由をログへ出力して追いつき処理を停止します。次の新規M5足で同じ基準時刻`T`から再試行し、後続時刻を先に保存しません。
- TESTERのDB保存失敗でも処理済みM5時刻を進めません。次のM5足で同じ基準時刻`T`から再試行し、後続時刻を先に保存しません。
- TESTER終了時のサマリーログでは、未処理の再試行対象を`pendingM5`へ出力します。`NONE`以外の場合は、そのM5時刻で追いつき処理が停止しています。
- `databaseSavePartialRuns = false`では28ペアが揃った完全Runだけを保存します。`true`では部分Runを同じ自然キーへ保存し、保存成功後はその時刻を処理済みとします。
- `databaseSaveStartTime > 0`の場合、その時刻より前のM5足はDB保存対象および追いつき処理対象に含めません。保存開始前に一度だけ全28ペアのM5系列同期を開始し、同期済みペアのストキャスハンドルを初期化します。その後はテスター時刻を進めて履歴をウォームアップします。
- テスターを同じ期間・口座・集計ルールで再実行した場合、実行モードを含むM5自然キーが一致するRunをUPDATEし、PairVoteとResultを現在の集計結果で置き換えます。Run IDと自然キー該当件数は増えません。
- 部分保存を有効にした場合も、有効な1通貨ペアは必ず7票です。
- Serviceは保存前に`vote_count == valid_pair_count × 7`を検証します。
- DB初期化に失敗した場合、LIVEはインジケーターを継続してそのセッションのDB保存を無効化します。TESTERはDB記録を欠落させないため`INIT_FAILED`で開始を中止します。

テスター利用時は、テスト時間足をM5、最適化を無効、DB保存を行う場合は`databaseUseCommonFolder = true`に設定する必要があります。M5以外、最適化中、またはDB有効かつCommonフォルダ未使用の場合は初期化に失敗します。DB更新はローカルテストエージェントでの単一テストを前提とし、複数エージェントが同じCommon DBを同時更新する最適化には対応しません。

テストモデルは`Open prices only`（始値のみ）を使用します。始値モデルでは、シンボルごとに最初に参照した時間足より下位の時間足を後から参照できないため、系列準備、ストキャスハンドル生成、および売買判定はM5、M15、H1、H4、D1、W1、MN1の順で実行します。集計配列とDBの`time_frame_order`は従来どおり0=MN1、1=W1、2=D1、3=H4、4=H1、5=M15、6=M5です。

他シンボルの対象足がまだ確定していない場合は、そのM5スナップショットを現在足として保留します。次のM5足で再確認し、確定していれば保存します。まだ未確定の場合は処理済みにせず、後続時刻の保存を止めて次の新規M5足で再試行します。

保存開始直後からMN1の長期ストキャス`21,5,5`を利用する場合は、ストラテジーテスターの開始日を`databaseSaveStartTime`より十分前へ設定してください。目安として保存開始までに32本以上のMN1履歴が進む期間をウォームアップへ割り当てます。`databaseSaveStartTime = 0`ではテスト開始時刻から保存を試みるため、初期履歴が不足しているM5足は準備完了まで再試行待ちとなり、後続時刻も保存されません。

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
- 年別分割時は、存在する年別DBを確認し、現在選択中の年を含む各DBへ同じ削除条件を適用します。存在しない年の空DBは作成しません。
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
5. `currency_strength_contributions`の定義を確認し、未作成または定義変更時だけ作成・再作成

### 11.1 RunのM5基準時刻列、実行モードと自然キー

既存の`currency_strength_runs`に列がない場合は、次の3列を追加します。

```sql
m5_bar_time INTEGER NOT NULL DEFAULT 0
m5_bar_time_text TEXT NOT NULL DEFAULT ''
source_mode TEXT NOT NULL DEFAULT 'LEGACY'
```

M5基準時刻列を持たない旧DBでは、移行前のRunがどのM5足で集計されたか確定できないため、追加後も`m5_bar_time = 0`、`m5_bar_time_text = ''`のまま維持します。`source_mode`追加前のRunは、M5基準時刻の有無にかかわらずLIVEとTESTERを判別できないため`source_mode = LEGACY`とし、既存のM5基準時刻値は変更しません。

新規CREATEするRunテーブルには`m15_bar_time`を作成しません。旧スキーマに同列がある場合も、テーブル再構築や列削除は行わず物理列を残します。DAOは旧列の有無を検出し、旧DBへの保存時だけ`m5_bar_time`を15分境界へ丸めた互換値を設定して、旧列の`NOT NULL`制約を満たします。この互換値はEntity、保存間隔判定、自然キー、およびContributionビューでは使用しません。

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

新規CREATE時は、合計、期間別平均・順位を前方に配置し、その後の時間足別詳細をMN1、W1、D1、H4、H1、M15、M5の順に配置します。ALTER TABLEは列を末尾へ追加するため、既存DBの物理列順は新規DBと異なります。DAOはINSERT列名を明示して保存します。

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

既存のv1～v5行は長中期・中短期平均を保存していないため、追加した4列は0のままとし、履歴値を再計算しません。`pair-direction-raw-v6`以降（`pair-direction-closed-v1`を含む）は2平均と完全Runの競技順位を保存します。部分Runでは2順位を0とします。新規CREATE時の平均列は、長中期、中短期、長期、中期、短期の順とし、各スコアの直後に順位を配置します。ALTER TABLEでは物理的に末尾へ追加されますが、DAOはINSERT列名を明示して保存します。

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
       total_score,
       total_sample_count,
       long_medium_term_average_score,
       long_medium_term_average_rank,
       medium_short_term_average_score,
       medium_short_term_average_rank,
       long_term_average_score,
       long_term_average_rank,
       medium_term_average_score,
       medium_term_average_rank,
       short_term_average_score,
       short_term_average_rank,
       mn1_score,
       w1_score,
       d1_score,
       h4_score,
       h1_score,
       m15_score,
       m5_score,
       mn1_sample_count,
       w1_sample_count,
       d1_sample_count,
       h4_sample_count,
       h1_sample_count,
       m15_sample_count,
       m5_sample_count,
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

`Scripts/Mstng/Database/CurrencyStrengthDatabaseSmokeTest.mq5`は、`source_mode = TESTER`を含む同じM5自然キーへ、内容の異なるスナップショットを2回保存した後、同じM15区間内の次のM5時刻へ3回目を保存します。

- 自然キー該当Run: 1件。Run全件数も1件となるのは`recreateDatabaseObjects = true`の場合だけ
- 1回目のUSDJPY票: MN1、W1、D1、H4、M15はBUY、H1、M5はSELLの7件
- 2回目のUSDJPY票: MN1、W1、D1、H4、M15はSELL、H1、M5はBUYの7件
- Result: USD、JPYの2件
- Contributionsビュー: 14件。`source_mode`列は親Runを参照
- 2回目の長中期平均: USDは-0.60・順位2、JPYは+0.60・順位1
- 2回目の中短期平均: USDは-0.20・順位2、JPYは+0.20・順位1
- 3回目のRun: 最初のRunから5分後の別Run。M15区間が同じでもM5時刻が異なれば保存
- 新規DBの列順: Run、PairVote、Result、およびContributionビューが本仕様書どおりで、Runに`m15_bar_time`がないこと
- 順位検索: 指定M5時刻以前の同一RunからUSD・JPYの長中期・中短期順位を取得し、未来のRunを参照しないこと

2回目もRun IDが変わらないこと、自然キー該当件数が1であること、子件数が増えないこと、2回目のRun・先頭票・Result値へ置換されたことを検証します。続いて3回目が別Runとなり、自然キー該当件数が各1件であることを検証します。Run全件数が2件であることと新規DBの物理列順は、実行前に3テーブルを削除する`recreateDatabaseObjects = true`の場合だけ検証します。また、`source_mode = TESTER`、`updated_at`が2回目保存時の実時刻であり、3テーブルの`updated_at`と`updated_at_text`が一致することを確認します。DBファイルと保存したテストレコードは実行後も残ります。

このテストはCalculatorからEntityへの通常変換、保存条件、保持期間削除、ROLLBACK、および既定の`recreateDatabaseObjects = true`では既存DBのALTER TABLE経路を直接検証しません。

`Scripts/Mstng/Database/CurrencyStrengthYearlyDatabaseSmokeTest.mq5`は、2025年12月31日23:55と2026年1月1日00:00のTESTERスナップショットを別ファイルへ保存し、2025年分を再保存します。さらに、2025年の同じM5時刻へ順位が異なるLIVEスナップショットを保存します。

- `calculated_at`を2026年にした2025年M5 Runが2025年DBへ保存されること
- 2025年DBと2026年DBが別ファイルになること
- 2025年DBがRun 2件、PairVote 14件、Result 4件、Contribution 28件、2026年DBがRun 1件、PairVote 7件、Result 2件、Contribution 14件になること
- 2025年分の再保存でRun IDと件数を維持し、Run値と子レコードを更新すること
- 更新後の2025年先頭票とUSD結果がSELL値、2026年側がBUY値のまま維持されること
- 順位検索で対象年のRunを優先し、2027年DBがない場合は2026年Runへフォールバックすること
- LIVE優先検索で同じM5時刻のLIVEを選び、LIVEより新しいTESTERはTESTERを選ぶこと
- LIVE優先の範囲検索で2025年のLIVEと2026年のTESTERを時刻順にマージすること
- READONLYの2027年照会前後で2027年DBファイルが作成されないこと

既定のテストファイルは`mstng-currency-strength-yearly-smoke-test-2025.sqlite`と`mstng-currency-strength-yearly-smoke-test-2026.sqlite`です。実行前にこの2ファイルを削除し、実行後は確認用として残します。本番DBのベースファイル名を指定して実行してはいけません。

`Scripts/Mstng/Strength/CurrencyStrengthCalculationSmokeTest.mq5`は、開始時に固定したM5基準時刻より前の確定足を使って28通貨ペアを実判定します。5種類の平均を時間足別スコアから再計算し、8通貨内の競技順位、全通貨の平均合計0、部分集計時の順位0、および同じM5基準時刻と`pair-direction-closed-v1 / LIVE`を渡したDB保存を検証します。このスクリプトはオンラインチャート用であり、TESTERのM5追いつき処理は検証しません。

## 15. ZigZagElliotの順位表示

`ZigZagElliot`は表示中シンボルの基軸通貨と決済通貨をシンボルプロパティから取得し、右中央のパネルへ長中期順位と中短期順位を表示します。取得元のM5時刻も併記します。

DBは対象M5時刻の年別ファイルをREADONLYで開き、ファイル作成、テーブル作成、既存DB移行を行いません。対象年に該当Runがない場合は前年DBも検索します。基軸通貨と決済通貨は必ず同じ完全Runから取得します。`pair-direction-closed-v1`、取引サーバー、およびログイン番号が一致するLIVEとTESTERをそれぞれ検索し、M5時刻が新しい候補を表示します。同じM5時刻に両方ある場合はLIVEを優先し、一方にレコードがなければ他方を使用します。

既存DBへ順位検索用インデックスを追加する場合は、保存側の`CurrencyStrengthElliot`を一度起動してDB初期化を実行します。`ZigZagElliot`のREADONLY接続だけではインデックスを追加しません。

検索上限は現在時刻をM5間隔へ切り下げた時刻です。SQL条件を`m5_bar_time <= 検索上限`とするため、ストラテジーテスターで未来の集計結果を参照しません。対象DBまたはレコードが存在しない場合は順位を`-`とし、インジケーター本体の処理は継続します。

主な入力値は次のとおりです。

| 入力値 | 既定値 | 内容 |
|---|---:|---|
| `currencyStrengthRankVisible` | `true` | 順位パネルの表示有無 |
| `currencyStrengthRankPanelXDistance` | `12` | チャート右端からの距離 |
| `currencyStrengthDatabaseFileName` | `mstng-currency-strength.sqlite` | 年付与前のDBファイル名 |
| `currencyStrengthDatabaseSplitByYear` | `true` | 年別DBを使用する場合true |
| `currencyStrengthDatabaseUseCommonFolder` | `true` | Commonフォルダを使用する場合true |

## 16. 通貨強弱順位履歴

`CurrencyStrengthRankHistory`は表示中シンボルの基軸通貨と決済通貨について、DBに保存された長中期または中短期の順位をサブウィンドウへ時系列表示します。描画値は1位を`-1`、8位を`-8`として、1位が上になる向きで表示します。Data Window用の非表示バッファには実順位の1から8を保持します。

サブパネル右上には選択期間と最新順位による売買方向を表示します。基軸通貨の順位が決済通貨より上なら`BUY +5`、決済通貨の順位が基軸通貨より上なら`SELL -3`のように、売買方向と「決済通貨順位 - 基軸通貨順位」を表示します。同順位または未取得なら`-`とします。`BUY`は水色、`SELL`はピンクで表示します。

その下には長中期と中短期の方向一致状態を表示します。両方がBUY方向なら`STRONG BUY`、両方がSELL方向なら`STRONG SELL`、方向が一致しない場合は`MIXED`、未取得の場合は`-`とします。

さらに最新順位点の実際の取得元を`SOURCE: LIVE`または`SOURCE: TESTER`として表示します。`LIVE_THEN_TESTER`の場合も設定名ではなく、LIVE優先マージ後にそのM5時刻で採用されたレコードの`source_mode`を表示します。順位点を未取得の場合は`SOURCE: -`とします。

`databaseProfile`の既定値は`LIVE_THEN_TESTER`です。このプロファイルは指定期間のLIVEとTESTERを取得し、M5時刻単位でマージします。同じM5時刻に両方ある場合はLIVEを採用し、LIVEがないM5時刻はTESTERで補完します。結果はM5時刻の昇順で描画します。`LIVE`、`TESTER`、`AUTO`を指定した場合は、従来どおり選択された単一の`source_mode`だけを参照します。

最新1件を取得する`ZigZagElliot`では、LIVEとTESTERのうちM5時刻が新しい候補を採用し、同時刻の場合はLIVEを採用します。履歴の範囲取得では、各M5時刻のLIVEをTESTERへ上書きする形でマージします。DBやレコードが一方に存在しないことはエラーとせず、存在する側だけを使用します。ただし、SQL準備、バインド、読み取りなどのDB処理エラーが一方で発生した場合は、他方の結果へフォールバックせず検索全体をエラーとします。これによりDB破損やスキーマ不一致を欠損レコードとして隠しません。

主な入力値は次のとおりです。

| 入力値 | 既定値 | 内容 |
|---|---:|---|
| `rankPeriod` | `LONG_MEDIUM` | 長中期順位または中短期順位の選択 |
| `historyDays` | `30` | 表示する過去日数 |
| `refreshSeconds` | `15` | LIVEで同じM5足を再照会する間隔（秒） |
| `subPanelHeight` | `120` | サブパネルの固定高さ（px）。0の場合は固定しない |
| `databaseProfile` | `LIVE_THEN_TESTER` | LIVE優先・TESTER補完、または単一参照元の選択 |
| `databaseFileName` | `mstng-currency-strength.sqlite` | 年付与前のDBファイル名 |
| `databaseSplitByYear` | `true` | 年別DBを使用する場合true |
| `databaseUseCommonFolder` | `true` | Commonフォルダを使用する場合true |
