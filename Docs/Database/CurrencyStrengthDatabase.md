# 通貨強弱データベース仕様書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象機能 | 主要8通貨・28通貨ペアの通貨強弱集計履歴 |
| DBMS | MetaTrader 5組み込みSQLite |
| LIVE集計ルール | `pair-direction-closed-v1`、`pair-direction-weighted-closed-v1` |
| TESTER集計ルール | `pair-direction-closed-v1`、`pair-direction-weighted-closed-v1` |
| 最終更新日 | 2026-07-25 |
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

LIVEとTESTERは同じ集計規則を使用し、選択した`voteWeightMode`に応じて`calculation_version`を分けます。現行方式`UNIFORM`は`pair-direction-closed-v1`、加重方式`WEIGHTED`は`pair-direction-weighted-closed-v1`です。`source_mode`はLIVEとTESTERを区別します。`m5_bar_time`には両環境とも`T`を保存し、`calculated_at`はLIVEでは実際の集計時刻、TESTERでは`T`です。既存Runは移行や再計算を行わず、新方式のRunと併存します。

Runの基準時刻は`m5_bar_time`だけです。PairVoteの`bar_time`には実際に判定した確定足の開始時刻を保存します。このためM5票の`bar_time`は`T`ではなく直前M5足、M15票も`T`より前の確定済みM15足の開始時刻となります。

1通貨ペア・1時間足につき1判定を行います。3本のストキャスのプラス本数に応じた実効票は次のとおりです。

| プラス本数 | 判定 | `oscillator_count` | UNIFORM基軸票 | WEIGHTED基軸票 |
|---:|---|---:|---:|---:|
| 3 | BUY | +3 | +1 | +2 |
| 2 | BUY | +2 | +1 | +1 |
| 1 | SELL | -2 | -1 | -1 |
| 0 | SELL | -3 | -1 | -2 |

決済通貨には基軸通貨と絶対値が同じ反対票を加算します。DBでは売買方向を`base_score = ±1`、一致度を`vote_weight = 1または2`として保持し、実効票を`base_score × vote_weight`で表します。UNIFORMは全判定の`vote_weight`が1、WEIGHTEDは3対0だけ2、2対1は1です。

集計値は正規化しない整数合計です。完全な集計では次の件数になります。

| DBオブジェクト | 件数 |
|---|---:|
| `currency_strength_runs` | 1 |
| `currency_strength_pair_votes` | 196（28ペア × 7時間足） |
| `currency_strength_results` | 8（通貨数） |
| `currency_strength_contributions` | 392（196票 × BASE/QUOTE） |

各通貨は1時間足につき7ペアへ登場し、全7時間足の判定数は49です。スコア範囲は次のとおりです。

| 方式 | 1時間足スコア | 7時間足TOTAL |
|---|---:|---:|
| UNIFORM | -7～+7 | -49～+49 |
| WEIGHTED | -14～+14 | -98～+98 |

時間軸ごとの傾向確認用として、指定時間足の未正規化スコアを単純算術平均します。

| 期間 | 対象時間足 | 計算式 |
|---|---|---|
| 長期 | MN1、W1、D1 | `(mn1_score + w1_score + d1_score) / 3.0` |
| 長中期 | MN1、W1、D1、H4、H1 | `(mn1_score + w1_score + d1_score + h4_score + h1_score) / 5.0` |
| 中期 | D1、H4、H1 | `(d1_score + h4_score + h1_score) / 3.0` |
| 中短期 | D1、H4、H1、M15、M5 | `(d1_score + h4_score + h1_score + m15_score + m5_score) / 5.0` |
| 短期 | H1、M15、M5 | `(h1_score + m15_score + m5_score) / 3.0` |

D1やH1などの時間足は複数期間へ重複して使用します。平均値は票数による正規化ではなく、指定した3時間足または5時間足を固定分母3または5で平均した値です。完全な集計における各平均の範囲はUNIFORMが-7～+7、WEIGHTEDが-14～+14です。UNIFORMでは各時間足スコアが7票の奇数合計となるため、3時間足平均は2/3刻み、5時間足平均は0.4刻みになります。最強・最弱判定とTOTALは7時間足の未正規化合計を使用します。

長期・長中期・中期・中短期・短期の各平均について、8通貨内の降順順位を記録します。順位は`1 + 対象通貨より平均スコアが高い通貨数`で算出し、同点は同順位、次順位を飛ばす競技順位とします。例としてスコアが5、3、3、1の場合、順位は1、2、2、4です。28通貨ペアが揃った完全Runだけ1～8の順位を保存し、部分Runと平均順位追加前の履歴は0とします。

`CurrencyStrengthElliot`の`sortType`では、チャート表示順を`TOTAL`、`LONG`、`LONG-MID`、`MID`、`MID-SHORT`、`SHORT`から選択します。完全な集計では選択スコアの降順、TOTALの降順、通貨コードの昇順で並べ、`#`列はこの表示順を示します。未完全集計ではソートせず、`#`列は従来どおり`-`を表示します。この表示設定はDB保存値とLIVE・TESTERそれぞれの`calculation_version`へ影響しません。

`時間足別スコアを表示（MN1～M5）`（`showTimeFrameScores`、既定`true`）を`false`にすると、MN1・W1・D1・H4・H1・M15・M5の7列を非表示にします。`#`・`CCY`・`LONG`・`LONG-MID`・`MID`・`MID-SHORT`・`SHORT`・`TOTAL`・`N`は残し、左パネルを縮め、右の候補一覧も左へ詰めます。表示列だけの変更で、時間足別の計算・平均・順位・候補抽出・DB保存には影響しません。

右の売買候補一覧は幅680pxです。タイトルを「売買候補一覧」とし、その下に「必要順位差：2以上 ｜ 候補：16件 ｜ 表示：10件」の形式で条件・件数を表示します。候補が0件の場合は「候補なし」、全28ペアが未集計の場合は「集計待ち：27/28ペア」の形式で表示します。`#`・`PAIR`・`SIDE`・`LONG-MID B/Q`・`DIFF`・`MID-SHORT B/Q`・`DIFF`・`MIN`・`TOTAL`・`STATE`の全10列を維持し、文字サイズと色分けを保ったまま列間と右端の余白を詰めます。順位は`1/7`のように表示し、左が基軸通貨、右が決済通貨の順位です。最大表示件数分の行の下に区切り線を置き、「長中期・中短期の両方で強弱方向が一致するペア」「READY：両期間の順位差の大きさが4以上」「WATCH：候補条件を満たすが、どちらかの順位差の大きさが4未満」の3行を灰色で固定表示します。説明は候補なし・集計待ちでも表示し、候補件数によって位置を動かしません。左の時間足別スコアを非表示にした場合、左右パネルの合計幅は間隔12pxを含めて1280px（588px + 12px + 680px）になります。

`順位比較を表示`（`showRankComparison`、既定`true`）を有効にすると、一番左に幅320pxの順位比較パネルを追加します。比較パネル内の左は長中期（LONG-MID、MN1・W1・D1・H4・H1）、右は中短期（MID-SHORT、D1・H4・H1・M15・M5）で、同じ集計時刻の同じ通貨を線で結びます。時間経過による順位推移ではありません。左右で順位ごとの帯を共有し、同順位の通貨は帯の中に通貨名順で並べます。同順位の人数が左右で違う場合は帯を広げ、競技順位（例：1・2・2・4）を保ったまま重なりを防ぎます。同じ順位の接続線も、帯内の並び順によって傾く場合があります。パネルの高さは318～472pxで自動調整します。通貨ラベルのクリックで最大2通貨の線を同時に強調します。選択済みの通貨を再クリックすると、その通貨だけを解除します。3通貨目をクリックした場合は、先に選んだ通貨を外して新しい通貨へ入れ替えます。左右の同じ通貨は同一の選択として扱い、手動選択中は「選択：USD / JPY」、1通貨なら「選択：USD」と表示します。未集計または無効な順位がある場合は線を消し、`WAITING DATA`を表示します。

3パネルの共通日時欄を最上部へ置き、「集計対象：JST 2026.10.22 02:00 ｜ SERVER 2026.10.21 20:00」の形式で同じM5足の日時を1行に表示します。JSTへの変換には共通の`TimeJapanUtil::getJapanTime()`を使用します。各パネル内の日付表示は共通欄へ集約し、パネル本体は共通欄24pxと余白4pxの分だけ下げます。日時欄の幅は表示中パネルの合計幅に合わせ、順位比較や売買候補を非表示にしても表示します。集計が未完了の場合は日時を消して「集計待ち：27/28ペア」、日時未取得の場合は「集計待ち：日時未取得」を表示します。

3パネルの順序は「順位比較・強弱スコア・売買候補」で、間隔は各12pxです。`panelXDistance`と`panelYDistance`は全体の左上位置です。順位比較を無効にすると強弱スコアが全体左端へ戻ります。順位比較と売買候補が有効な場合、時間足別スコア非表示時の合計幅は1612px（320 + 12 + 588 + 12 + 680）、全列表示時は2024pxです。比較パネルは既存の平均順位を参照し、集計・候補抽出・DB保存条件を変更しません。

順位比較の通常時の通貨名と接続線には、他の通貨順位表示と同じ`ConstantCurrency::getColor()`の共通色を使用します。クリック選択時は選択通貨名を白、他の通貨名を灰色にし、選択した接続線を太く表示します。

比較パネルの選択表示の右側には「解除」ボタンを常時表示します。クリックすると手動選択の1～2通貨、候補ペアから選んだ2通貨、READY強調のいずれも一括解除し、8通貨の線と文字を通常表示へ戻します。売買候補一覧の選択行の背景色も解除します。ボタン文字は選択中またはREADY強調ONが白、未選択・集計待ちは灰色で、解除後は集計状態を表示します。未選択時のクリックは状態を変えず、集計待ちの間は線を表示しません。

売買候補一覧の`PAIR`をクリックすると、そのペアの2通貨を同時に強調します。例えば`USDJPY`ではUSDとJPYの接続線を共通の通貨色のまま太線にし、残り6通貨を薄く表示します。比較パネルに「選択：USDJPY」を表示し、候補一覧の選択行に薄い背景色を付けます。同じペアの再クリックで解除し、別のペアでは選択を切り替えます。候補ペアを選択した後に順位比較の通貨名をクリックすると、手動選択へ切り替え、同じ追加・解除・入れ替えのルールを適用します。このとき候補一覧の背景色は解除します。例えばUSDJPYからUSDをクリックするとJPYだけを残し、EURをクリックするとJPYとEURを選択します。下部の操作説明は「2通貨まで選択・再クリックで解除」とし、3通貨目の入れ替えルールは通貨名のツールチップにも表示します。

定期更新では行番号ではなくペア名で選択を維持します。候補の並び順が変わった場合は背景色も追従し、表示件数の上限より下へ移動しただけなら線の強調を維持します。全候補から選択ペアが外れた場合、集計待ち、または候補更新失敗時はペア選択を解除します。通貨名から手動で選んだ1～2通貨は、候補の増減や候補更新失敗では解除しません。通常更新とパネル高さの変更でも手動選択を維持し、比較用の順位が未取得・無効になった場合やパネルのクリア時には解除します。順位比較を非表示にした場合、候補一覧のPAIRクリックと操作案内は無効です。

売買候補一覧のタイトル右側に「READY強調：OFF / ON」ボタンを表示します。初期状態はOFFで、ONにすると現在表示中のREADYペアに含まれる通貨を、通貨順位比較でまとめて太線にします。例えばUSDJPYとEURUSDならUSD・JPY・EURの3通貨が対象です。重複通貨は1通貨として扱い、共通の通貨色を保ったまま対象の線を太く、対象外を薄く表示します。対象の通貨名は白、対象外は灰色にし、比較パネルに「READY：3通貨」の形式で表示します。手動選択の2通貨制限は適用せず、最大8通貨を強調します。WATCHと表示上限より下のREADY候補は含めません。

READY強調ONでは手動・候補ペアの選択を解除し、候補一覧の選択背景も解除します。ボタンをOFFにすると通常表示へ戻ります。通貨名・候補PAIRをクリックした場合はREADY強調をOFFにして通常の選択操作へ切り替え、「解除」でもOFFに戻します。定期更新では表示中のREADYペアから対象通貨を入れ替え、パネル高さの変更でもONを維持します。表示中にREADYが0件の場合はONのまま「READY対象なし」と表示し、8通貨を通常表示します。集計待ち・候補更新失敗・比較描画失敗ではOFFに戻します。順位比較が非表示の場合はボタンを灰色にして操作を無効にし、再装着時にはOFFから始めます。

パネルのタイトルは左から「通貨順位比較」「通貨強弱スコア」「売買候補一覧」です。順位比較と強弱スコアでは、計算方式を`WEIGHTED`なら「重み付き」、`UNIFORM`なら「均等」として角括弧内に表示します。中央タイトルの並び順は「合計順・長期順・長中期順・中期順・中短期順・短期順」の日本語で表示します。例：`通貨強弱スコア［重み付き］ 28/28 長中期順`。列名・計算方式の識別子・並び替え処理は従来どおりです。

強弱スコアパネルでは、最強・最弱の要約行の下に区切り線を置き、「＋は相対的に強い、－は弱い、0は均衡」「長期～短期：対象時間足の平均 ／ TOTAL：7時間足の合計」「長中期：MN1・W1・D1・H4・H1」「中短期：D1・H4・H1・M15・M5」の4行を灰色で固定表示します。時間足別スコアを非表示にした場合や集計待ちでも説明は表示します。

### 3.1 CurrencyStrengthElliotの入力設定

入力設定は次の5グループに分けて表示します。表示名と配置を変更しても、入力変数名・型・初期値および列挙値の数値は維持します。真偽値の設定は`true`が有効、`false`が無効です。

| グループ | 表示名 | 入力変数 | 初期値 |
|---|---|---|---|
| 01. 画面表示 | 順位比較を表示 | `showRankComparison` | `true` |
| 01. 画面表示 | 時間足別スコアを表示（MN1～M5） | `showTimeFrameScores` | `true` |
| 01. 画面表示 | ランキングの並び順 | `sortType` | 合計（TOTAL） |
| 01. 画面表示 | 表示位置：左から（px） | `panelXDistance` | `12` |
| 01. 画面表示 | 表示位置：上から（px） | `panelYDistance` | `32` |
| 02. 候補一覧 | 売買候補一覧を表示 | `showEntryCandidates` | `true` |
| 02. 候補一覧 | 候補の最大表示件数 | `entryCandidateMaxCount` | `10` |
| 02. 候補一覧 | 候補に必要な順位差（1～7） | `entryCandidateMinRankDifference` | `2` |
| 03. 計算・更新 | スコアの計算方式 | `voteWeightMode` | 加重（3対0は2点・2対1は1点） |
| 03. 計算・更新 | 通常チャートの更新間隔（秒） | `refreshSeconds` | `60` |
| 04. DB保存 | 集計結果をDBに保存 | `databaseEnabled` | `true` |
| 04. DB保存 | DBファイル名 | `databaseFileName` | `mstng-currency-strength.sqlite` |
| 04. DB保存 | DBファイルを年ごとに分ける | `databaseSplitByYear` | `true` |
| 04. DB保存 | MT5共通フォルダに保存 | `databaseUseCommonFolder` | `true` |
| 05. DB詳細設定 | 同じM5足も再保存（LIVE） | `databaseSaveEveryRefresh` | `false` |
| 05. DB詳細設定 | 一部ペアが未取得でも保存 | `databaseSavePartialRuns` | `false` |
| 05. DB詳細設定 | テスター保存開始日時（サーバー時刻） | `databaseSaveStartTime` | `2026.07.16 00:00` |
| 05. DB詳細設定 | LIVEデータの保持日数（0＝削除なし） | `databaseRetentionDays` | `0` |

並び順の選択肢は合計（TOTAL）・長期（LONG）・長中期（LONG-MID）・中期（MID）・中短期（MID-SHORT）・短期（SHORT）です。計算方式は均等（すべて1点）と加重（3対0は2点・2対1は1点）から選択します。共通の計算方式列挙型を使用する他のインジケーターやスクリプトも、再コンパイル後は同じ選択肢名になります。

候補の順位差は長中期と中短期の両方に適用します。通常チャートは指定秒数のタイマーに加えてM5新足でも更新します。同じM5足の再保存は既存記録の更新で、件数を増やす設定ではありません。テスター保存開始日時はLIVEには適用せず、`0`では開始日時を制限しません。保持日数による削除はLIVEデータだけが対象です。

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
| 6 | `calculation_version` | TEXT | string | NOT NULL | 集計ルール識別子。UNIFORMまたはWEIGHTEDを区別 |
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
| 14 | `base_score` | INTEGER | int | NOT NULL, CHECK(base_score IN (-1, 1)) | 基軸通貨の方向票。BUY=+1、SELL=-1 |
| 15 | `vote_weight` | INTEGER | int | NOT NULL, DEFAULT 1, CHECK(vote_weight IN (1, 2)) | 方向票へ適用するウェイト |
| 16 | `base_score_after` | INTEGER | int | NOT NULL | 加重票反映後の基軸通貨・時間足別累積値 |
| 17 | `quote_currency` | TEXT | string | NOT NULL | 決済通貨コード |
| 18 | `quote_score_after` | INTEGER | int | NOT NULL | 加重票反映後の決済通貨・時間足別累積値 |
| 19 | `updated_at` | INTEGER | datetime | NOT NULL | スナップショットのDB保存時刻 |
| 20 | `updated_at_text` | TEXT | string | NOT NULL | `updated_at`の目視用文字列 |

### 7.2 制約

```sql
FOREIGN KEY(run_id) REFERENCES currency_strength_runs(id) ON DELETE CASCADE
UNIQUE(run_id, pair_order, time_frame_order)
CHECK(is_buy IN (0, 1))
CHECK(base_score IN (-1, 1))
CHECK(vote_weight IN (1, 2))
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
| 7 | `score` | BASE行は`base_score × vote_weight`、QUOTE行はその反対票 |
| 8 | `vote_weight` | `pair_votes.vote_weight` |
| 9 | `score_after` | BASE行は`base_score_after`、QUOTE行は`quote_score_after` |
| 10 | `canonical_symbol_name` | `pair_votes.canonical_symbol_name` |
| 11 | `resolved_symbol_name` | `pair_votes.resolved_symbol_name` |
| 12 | `time_frame` | `pair_votes.time_frame` |
| 13 | `time_frame_text` | `pair_votes.time_frame_text` |
| 14 | `bar_time` | `pair_votes.bar_time` |
| 15 | `bar_time_text` | `pair_votes.bar_time_text` |
| 16 | `is_buy` | `pair_votes.is_buy` |
| 17 | `oscillator_count` | `pair_votes.oscillator_count` |
| 18 | `pair_order` | `pair_votes.pair_order` |
| 19 | `time_frame_order` | `pair_votes.time_frame_order` |
| 20 | `vote_id` | `pair_votes.id` |
| 21 | `calculated_at` | `runs.calculated_at` |
| 22 | `updated_at` | `pair_votes.updated_at` |
| 23 | `updated_at_text` | `pair_votes.updated_at_text` |

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
| `databaseRetentionDays` | 0 | 自動削除を無効化 |
| `voteWeightMode` | `WEIGHTED` | 現行方式または加重方式の選択 |

- 通常チャートでは`OnCalculate()`でM5バー時刻の変化を検出し、新規M5足の最初のティックで集計・保存を開始します。同じM5足の後続ティックでは再集計しません。タイマーは同じM5足の定期表示更新と、系列準備またはDB保存失敗時の再試行に使用します。
- ストラテジーテスターではタイマーを使用せず、`OnCalculate()`で新しいM5足を検出して集計・保存します。未処理のM5足が複数ある場合は古い時刻から順に追いつき処理を行います。
- TESTERでは同じM5足の全ティックで再計算せず、新しいM5足を検出した時だけ処理します。28ペア未準備の現在足は保留し、次のM5足で旧足として再確認します。再確認後も未準備の場合は処理済みM5時刻を進めず、M5時刻、ペア数、票数、および最初に検出した準備不足理由をログへ出力して追いつき処理を停止します。次の新規M5足で同じ基準時刻`T`から再試行し、後続時刻を先に保存しません。
- TESTERのDB保存失敗でも処理済みM5時刻を進めません。次のM5足で同じ基準時刻`T`から再試行し、後続時刻を先に保存しません。
- TESTER終了時のサマリーログでは、未処理の再試行対象を`pendingM5`へ出力します。`NONE`以外の場合は、そのM5時刻で追いつき処理が停止しています。
- `databaseSavePartialRuns = false`では28ペアが揃った完全Runだけを保存します。`true`では部分Runを同じ自然キーへ保存し、保存成功後はその時刻を処理済みとします。
- `databaseSaveStartTime > 0`の場合、その時刻より前のM5足はDB保存対象および追いつき処理対象に含めません。基準シンボルはZigZagElliotと同じくMN1を61本、W1以下を206本までウォームアップし、最も低い時間足別達成率が変化した場合だけ進捗をINFOへ出力します。100%到達後は全28ペアの系列同期とストキャスハンドル準備を既存の再試行処理で完了させ、その後も保存開始時刻までテスター時刻を進めます。
- テスターを同じ期間・口座・集計ルールで再実行した場合、実行モードを含むM5自然キーが一致するRunをUPDATEし、PairVoteとResultを現在の集計結果で置き換えます。Run IDと自然キー該当件数は増えません。
- 部分保存を有効にした場合も、有効な1通貨ペアは必ず7票です。
- Serviceは保存前に`vote_count == valid_pair_count × 7`を検証します。
- DB初期化に失敗した場合、LIVEはインジケーターを継続してそのセッションのDB保存を無効化します。TESTERはDB記録を欠落させないため`INIT_FAILED`で開始を中止します。
- 同じM5時刻・サーバー・口座でも`calculation_version`が異なるUNIFORM RunとWEIGHTED Runは別自然キーとなり、同じDBへ共存します。
- 比較期間は`CurrencyStrengthElliot`を2インスタンス起動し、一方を`UNIFORM`、他方を`WEIGHTED`に設定します。同一チャートではインスタンス別の描画オブジェクト名を使用します。パネルが重ならないよう、一方の`panelYDistance`を変更してください。
- 既存DBへ初めて導入する場合は、UNIFORMインスタンスを先に起動して`vote_weight`列の追加完了を確認してからWEIGHTEDインスタンスを起動します。

テスター利用時は、テスト時間足をM5、最適化を無効、DB保存を行う場合は`databaseUseCommonFolder = true`に設定する必要があります。M5以外、最適化中、またはDB有効かつCommonフォルダ未使用の場合は初期化に失敗します。DB更新はローカルテストエージェントでの単一テストを前提とし、複数エージェントが同じCommon DBを同時更新する最適化には対応しません。

テストモデルは`Open prices only`（始値のみ）を使用します。始値モデルでは、シンボルごとに最初に参照した時間足より下位の時間足を後から参照できないため、系列準備、ストキャスハンドル生成、および売買判定はM5、M15、H1、H4、D1、W1、MN1の順で実行します。集計配列とDBの`time_frame_order`は従来どおり0=MN1、1=W1、2=D1、3=H4、4=H1、5=M15、6=M5です。

他シンボルの対象足がまだ確定していない場合は、そのM5スナップショットを現在足として保留します。次のM5足で再確認し、確定していれば保存します。まだ未確定の場合は処理済みにせず、後続時刻の保存を止めて次の新規M5足で再試行します。

保存開始直後からMN1の長期ストキャス`21,5,5`を利用する場合は、ストラテジーテスターの開始日を`databaseSaveStartTime`より十分前へ設定してください。長期ストキャス単体は32本が目安ですが、テスターの履歴ゲートはZigZagElliotと開始条件を揃えるため、基準シンボルのMN1を61本、W1以下を206本必要とします。`databaseSaveStartTime = 0`でも履歴ゲート完了前は保存を開始せず、完了した最初のM5足から処理します。

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

既存のv1～v5行は長中期・中短期平均を保存していないため、追加した4列は0のままとし、履歴値を再計算しません。`pair-direction-raw-v6`以降（`pair-direction-closed-v1`と`pair-direction-weighted-closed-v1`を含む）は2平均と完全Runの競技順位を保存します。部分Runでは2順位を0とします。新規CREATE時の平均列は、長中期、中短期、長期、中期、短期の順とし、各スコアの直後に順位を配置します。ALTER TABLEでは物理的に末尾へ追加されますが、DAOはINSERT列名を明示して保存します。

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

### 11.9 PairVoteの票ウェイト列

既存の`currency_strength_pair_votes`に列がない場合は、次の列を追加します。

```sql
vote_weight INTEGER NOT NULL DEFAULT 1 CHECK(vote_weight IN (1, 2))
```

既存票はすべて現行方式の1票として保存されているため、追加時の既定値1を維持します。`base_score`は従来どおりBUY=+1、SELL=-1の方向票を保持します。加重方式の実効票は`base_score × vote_weight`で算出し、`base_score_after`、`quote_score_after`およびResultの各スコアには加重後の累積値を保存します。Contributionビューは実効票を`score`として返す定義へ自動更新します。

### 11.10 移行上の注意

- RunのM5基準時刻2列、`source_mode`、PairVoteの`vote_weight`には、新規CREATE・ALTER TABLEのどちらもDEFAULT句があります。それ以外は、新規CREATEしたDBの列にDEFAULT句がなく、ALTER TABLEで追加した更新時刻・表示列にはDEFAULT 0または空文字が残ります。
- ALTER TABLEで追加したMN1・W1・M5の6列には`DEFAULT 0`が残ります。
- ALTER TABLEで追加した期間別平均の5列には`DEFAULT 0.0`が残ります。
- ALTER TABLEで追加した期間別平均順位の5列には`DEFAULT 0`が残ります。
- ALTER TABLEは列を末尾へ追加するため、古いDBでは新規CREATE時と物理列順が異なる場合があります。INSERTは列名を指定するため保存処理には影響しません。
- 自動移行の対象はRunのM5基準時刻列、`source_mode`、表示列、更新時刻列、PairVoteの`vote_weight`、MN1・W1・M5・期間別平均・平均順位のResult列、および旧PairVote順序です。それ以外の列や制約の差異は自動再構築しません。
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

`pair-direction-raw-v6`、`pair-direction-closed-v1`または`pair-direction-weighted-closed-v1`の完全なRunでは、`vote_count`と実票数が196、Resultが8、Contributionが392になります。

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

`pair-direction-raw-v3`～`pair-direction-raw-v6`、`pair-direction-closed-v1`および`pair-direction-weighted-closed-v1`の完全なRunでは、0～6が各28票になります。

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

`Scripts/Mstng/Database/CurrencyStrengthDatabaseSmokeTest.mq5`は、`source_mode = TESTER`を含む同じM5自然キーへ、内容の異なるスナップショットを2回保存した後、同じM15区間内の次のM5時刻へ3回目を保存します。さらに最初と同じM5時刻へ別`calculation_version`の加重Runを4回目として保存します。

- 自然キー該当Run: 1件。Run全件数も1件となるのは`recreateDatabaseObjects = true`の場合だけ
- 1回目のUSDJPY票: MN1、W1、D1、H4、M15はBUY、H1、M5はSELLの7件
- 2回目のUSDJPY票: MN1、W1、D1、H4、M15はSELL、H1、M5はBUYの7件
- Result: USD、JPYの2件
- Contributionsビュー: 14件。`source_mode`列は親Runを参照
- 2回目の長中期平均: USDは-0.60・順位2、JPYは+0.60・順位1
- 2回目の中短期平均: USDは-0.20・順位2、JPYは+0.20・順位1
- 3回目のRun: 最初のRunから5分後の別Run。M15区間が同じでもM5時刻が異なれば保存
- 4回目のRun: 最初と同じM5時刻でも別`calculation_version`として別Run IDで共存
- 加重Contribution: 先頭BUY票のBASEは`score = +2`、QUOTEは`score = -2`、両方の`vote_weight = 2`
- 新規DBの列順: Run、PairVote、Result、およびContributionビューが本仕様書どおりで、Runに`m15_bar_time`がないこと
- 順位検索: 指定M5時刻以前の同一RunからUSD・JPYの長中期・中短期順位を取得し、未来のRunを参照しないこと

2回目もRun IDが変わらないこと、自然キー該当件数が1であること、子件数が増えないこと、2回目のRun・先頭票・Result値へ置換されたことを検証します。続いて3回目が別M5 Run、4回目が別`calculation_version` Runとなり、各自然キーの該当件数が1であることを検証します。Run全件数が3件であることと新規DBの物理列順は、実行前に3テーブルを削除する`recreateDatabaseObjects = true`の場合だけ検証します。また、`source_mode = TESTER`、`updated_at`が2回目保存時の実時刻であり、3テーブルの`updated_at`と`updated_at_text`が一致することを確認します。DBファイルと保存したテストレコードは実行後も残ります。

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

`Scripts/Mstng/Strength/CurrencyStrengthCalculationSmokeTest.mq5`は、UNIFORMとWEIGHTEDの4種類の一致度ウェイトおよび集計ルール識別子を固定値で検証します。その後、選択した`voteWeightMode`について、開始時に固定したM5基準時刻より前の確定足を使って28通貨ペアを実判定します。5種類の平均を時間足別スコアから再計算し、8通貨内の競技順位、全通貨の平均合計0、部分集計時の順位0、および選択方式の`calculation_version / LIVE`を渡したDB保存を検証します。このスクリプトはオンラインチャート用であり、TESTERのM5追いつき処理は検証しません。

## 15. ZigZagElliotの順位表示

`ZigZagElliot`は表示中シンボルの基軸通貨と決済通貨をシンボルプロパティから取得し、右中央のパネルへ長中期順位と中短期順位を表示します。取得元のM5時刻も併記します。

DBは対象M5時刻の年別ファイルをREADONLYで開き、ファイル作成、テーブル作成、既存DB移行を行いません。対象年に該当Runがない場合は前年DBも検索します。基軸通貨と決済通貨は必ず同じ完全Runから取得します。`currencyStrengthVoteWeightMode`に対応する`calculation_version`、取引サーバー、およびログイン番号が一致するLIVEとTESTERをそれぞれ検索し、M5時刻が新しい候補を表示します。同じM5時刻に両方ある場合はLIVEを優先し、一方にレコードがなければ他方を使用します。

既存DBへ順位検索用インデックスを追加する場合は、保存側の`CurrencyStrengthElliot`を一度起動してDB初期化を実行します。`ZigZagElliot`のREADONLY接続だけではインデックスを追加しません。

検索上限は現在時刻をM5間隔へ切り下げた時刻です。SQL条件を`m5_bar_time <= 検索上限`とするため、ストラテジーテスターで未来の集計結果を参照しません。対象DBまたはレコードが存在しない場合は順位を`-`とし、インジケーター本体の処理は継続します。

主な入力値は次のとおりです。

| 入力値 | 既定値 | 内容 |
|---|---:|---|
| `currencyStrengthRankVisible` | `true` | 順位パネルの表示有無 |
| `currencyStrengthRankPanelXDistance` | `48` | チャート右端からの距離 |
| `currencyStrengthVoteWeightMode` | `WEIGHTED` | 参照する現行方式または加重方式 |
| `currencyStrengthDatabaseFileName` | `mstng-currency-strength.sqlite` | 年付与前のDBファイル名 |
| `currencyStrengthDatabaseSplitByYear` | `true` | 年別DBを使用する場合true |
| `currencyStrengthDatabaseUseCommonFolder` | `true` | Commonフォルダを使用する場合true |

## 16. 通貨強弱順位履歴

v1.06では「通常チャートの再読込間隔（秒）」の入力設定を廃止し、内部定数で60秒に固定します。M5新足時の再読込とテスターの更新条件は維持します。更新したインジケーターを読み直すと、既存チャート・テンプレートに保存された旧入力値にかかわらず60秒が適用されます。

### v1.38 最新順位ラベルの座標変換失敗後も再試行

最新順位ラベルの基軸通貨・決済通貨それぞれの座標変換結果を保持し、片方でも変換できなかった場合は、代替位置への描画が成功しても更新待ちを維持します。通常ティックまたは通常チャートの10秒タイマーで再試行し、両方の配置とラベル描画に成功した時点で更新待ちを解除します。同じ横位置で成功した配置時刻の共用、順位未取得時のラベル消去、順位・帯の判定条件は維持します。

### v1.37 選択期間の順位が同じ場合は線の再計算を省略

同じM5時刻の履歴を再取得したとき、選択していない期間の順位だけが変わった場合は、順位線・塗り・履歴シグナルの再計算と最新順位ラベルの探索・再配置を省きます。帯の判定結果が変わった場合は帯だけを更新します。取得元だけの変更では、表示中の最新順位に対応する`SOURCE`ラベルだけを更新します。初回描画・新足・表示範囲の変更・履歴の追加や削除・時刻変更・期限切れは従来どおり更新し、失敗したラベル描画の再試行も維持します。

### v1.36 帯の判定結果が同じ場合は再描画を省略

同じM5時刻の履歴を再取得したとき、順位や取得元が変わっても、帯のデータ有効性と待機・BUY／SELLの準備・成立状態が同じなら、帯への変更通知を省きます。順位線・塗り・最新順位ラベルには変更を反映します。H1以上は描画時と同じく長中期のみで帯の状態を比較します。有効な待機状態と無効順位は区別し、開始の白色判定を維持します。履歴の追加・削除・時刻変更・期限切れ、および画面や使用可能時刻の変更による更新条件は維持します。

### v1.35 LIVE／TESTERの片側だけなら統合コピーを省略

`CurrencyStrengthRankHistory`の通貨ペア順位をLIVE優先／TESTER補完で取得するとき、両方の検索が正常に完了し、片側だけに履歴がある場合は、その配列を`ArraySwap`で結果へ引き継ぎます。統合先の配列確保と全件コピーを省き、両側に履歴がある場合は従来どおり同時刻のLIVEを優先して統合します。引き継ぎ前の上限確認、両側が空の場合のDBなし・レコードなしの区別は維持します。一方の取得または配列の引き継ぎに失敗した場合は検索全体をエラーとし、結果を空にします。

### v1.34 同一年の通貨ペア順位履歴を結果配列へ直接取得

`CurrencyStrengthRankHistory`の通貨ペア順位取得では、検索開始と終了が同じ年の場合、年別DBを使用していても結果配列へ直接取得します。年別の一時配列と、そこから結果配列への全件コピーを省きます。LIVE優先／TESTER補完では各取得側に適用し、統合条件は維持します。年またぎは従来どおり各年の結果を連結し、取得上限超過・DBなし・レコードなし・取得エラーの区別と、失敗時に空の結果を返す仕様も維持します。

### v1.33 帯の足時刻配列を再利用

下部帯の`CopyTime`取得先を描画クラスの作業配列として保持し、描画ごとの配列生成・破棄を省きます。帯の消去・取得失敗時も配列は保持し、インジケーター終了時に解放します。必要なサイズ調整は`CopyTime`に任せ、今回取得した件数だけを座標計算・帯判定・画面変更判定に使用します。部分取得や取得件数の減少時も前回の残りを参照せず、古い足から判定する順序・白色開始・欠損時の表示は維持します。

### v1.32 画面外の履歴変更では帯の再描画を省略

下部帯は、DB再取得による変更範囲と期限切れで削除する範囲を確認し、前回描画した参照範囲と重ならなければ再描画を省略します。参照範囲には、開始の白色を判定するための左隣1足も含めます。過去へスクロール中に最新側の履歴だけが更新された場合などは、画面条件が同じなら足時刻の取得・順位判定・Canvas更新を省きます。

新しいチャート足によりバー番号が変わった場合も、取得した足の両端時刻・件数・実際の座標・足幅・表示設定が同じならCanvas更新を省きます。表示中の履歴変更や期限切れ、使用可能なM5時刻の上限が参照範囲を横切る変化、スクロール・拡大縮小・色など描画結果に影響する変更は反映します。初回・全再構築・オブジェクト削除後・描画失敗後は描き直します。順位線・ラベルの更新条件と、帯の判定・白色開始の仕様は維持します。

### v1.31 順位検索で前回の位置を再利用

順位線・塗りのバッファ更新と下部帯の判定では、M5時刻が切り替わったときに前回検索位置の隣を確認し、時刻が完全一致すれば二分探索を省きます。順位線は新しい足から古い足へ、帯は古い足から新しい足へ進む順序に合わせて隣を参照します。一致しない場合は従来の二分探索へ戻し、欠損を別時刻の順位で補うことはありません。検索位置は各更新・描画の開始時にリセットし、DB更新や期限切れ削除をまたいで保持しません。同じM5内の結果再利用と、順位・帯の判定条件は維持します。

### v1.30 管理情報だけの変更では再描画を省略

DB再取得時、集計ID（`runId`）・更新日時（`updatedAt`）だけが変わった場合は履歴キャッシュのみ更新し、その変更を理由にした順位線・塗り・最新順位ラベルの更新と帯の強制再描画を省略します。M5時刻、長中期・中短期の基軸通貨／決済通貨の順位、取得元（`sourceMode`）の変更や履歴の追加・削除は表示へ反映します。初回、新しいチャート足、表示範囲・画面の変更、描画失敗後の再試行による更新は継続します。

### v1.29 M5時刻変換の秒数を共用

M5の秒数をインジケーター初期化時に一度取得し、時刻の切り下げとDB履歴の取得上限計算で共用します。各足の時刻を変換するたびに`PeriodSeconds(PERIOD_M5)`を呼ぶ処理を省きます。初期化時に正の秒数を確認し、変換結果・表示期間・取得範囲は維持します。

### v1.28 LIVE／TESTER統合時の配列確保を抑制

LIVE優先／TESTER補完の統合先配列は、LIVE件数とTESTER件数の合計、および取得上限の小さい方まで確保します。同じ時刻の履歴が両方にある場合などに、取得上限を超える一時的な配列確保を抑えます。LIVE優先、時刻の昇順、上限超過時のエラー検出は維持し、上限に収まらない結果を途中で切り捨てて返すことはありません。通貨ペア用と全8通貨用の両方に適用します。

### v1.27 右上ラベルの固定座標を初期設定へ移動

期間名・売買方向・取得元ラベルの固定X・Y座標は、作成・再作成時と設定失敗後の再試行時に設定します。文字・色だけが変わった場合は同じ座標を再設定しません。位置は従来どおり右端から48px、上端から期間名8px・売買方向27px・取得元68pxです。共通描画クラスを使用する`CurrencyStrengthAllRankHistory`の期間名・取得元ラベルにも適用されます。

### v1.26 最新順位ラベルの変更項目だけを反映

順位線の右側に表示する最新順位ラベルは、基軸通貨・決済通貨それぞれで位置・文字・色の変更を判定します。時刻だけが変わった場合は移動だけ、色だけが変わった場合は色だけを設定し、文字列の生成も順位または通貨名が変わった場合に限ります。順位の変更時は縦位置と文字を更新します。

初回・オブジェクトの再作成・表示先変更時は全項目を設定します。変更時は両通貨のオブジェクトの有無を確認する処理を維持し、片方の設定に失敗した場合は従来どおり削除・状態リセットして次回に再試行します。両通貨とも全項目が同じ場合の更新省略も維持します。

### v1.25 新規足と変更範囲の重複更新を省略

通常の差分更新では、新規・再計算対象の足を先に更新し、DB履歴の変更範囲はその更新済み件数の続きから処理します。両範囲が重なる足の順位検索・判定・バッファ設定を二重に行わず、変更範囲が新規足より過去まで続く場合も残りの足を更新します。全履歴の再計算、期限切れのクリア、各更新処理内でのM5単位の再利用は維持します。

### v1.24 M1の順位線・塗り判定をM5単位で再利用

全履歴・新規足・変更範囲の各バッファ更新では、同じM5時刻の連続した足に計算済みの表示値を再利用します。M1では最大5足分の順位検索・有効順位の確認・色と塗りの判定を1回にまとめ、順位線・実順位・信号・塗りの8本のバッファへ同じ値を反映します。欠損や無効順位の空値と、塗りを表示しない0も再利用します。

再利用する位置と時刻は更新処理ごとにリセットするため、DB履歴の修正・欠損補完やキャッシュの前詰め後も次の更新で計算し直します。M5以上では通常は足ごとに参照時刻が異なり、従来どおり各足を計算します。表示期間・順位差・色・塗りの条件は変更しません。

### v1.23 履歴配列の予備容量をまとめて確保

順位履歴キャッシュのサイズ変更では、メモリ確保時に288件（M5足の1日分）の予備容量を追加します。予約済みの容量内で履歴が増える間はメモリの再確保を省きます。予備容量は履歴件数に含めず、検索・描画対象にも含めません。期限切れ履歴の前詰め、全件失効時の配列解放、確保失敗時に既存履歴を維持する処理は変更しません。

### v1.22 期限切れ履歴の前詰めをまとめる

表示期間より古い履歴は、有効な先頭位置を進めて検索・比較・描画対象から外します。残り全件を前へコピーする処理は毎回行わず、期限切れの先頭部分が288件（M5足の1日分）以上、または残りの有効件数以上になったときにまとめて行います。全件が期限切れになった場合は配列を解放します。前詰め時の配列縮小に失敗した場合は、有効履歴を元の位置へ戻し、次回に再試行します。

順位線・最新順位ラベル・下部の帯は有効範囲だけを参照し、表示期限は従来どおりです。表示開始時刻が過去へ戻った場合は、無効化した先頭部分を再利用せずDBから対象期間を取り直します。DB取得失敗時は既存のキャッシュを維持し、DBの保存・削除条件は変更しません。

### v1.21 帯の描画担当の判定結果を保持

通常チャートでは、帯を描画する担当かどうかの判定結果を保持し、新足・履歴更新時は再利用します。構成変更を含むチャート変更イベントと10秒ごとの定期確認で結果を無効化し、次の帯更新時に調べ直します。担当から外れた場合は自身の帯を消去し、担当になった場合は再作成します。初回・対象未検出・取得失敗時は未確定のまま再試行します。タイマーを使用しないテスターでは従来の都度判定を維持し、最上段の対象インジケーターが帯を担当する条件は変わりません。

### v1.20 比較・描画判定用の一時コピーを省略

履歴の変更比較と帯判定では、順位データ1件を一時変数へコピーせず、配列要素を読み取り専用の参照として渡します。表示バッファへ反映する順位も、配列から必要な数値だけを読み取ります。比較する項目、有効順位・準備／成立の判定条件、履歴の更新方法は維持します。

### v1.19 M1の帯判定をM5単位で再利用

帯の描画中、同じM5時刻を参照する連続した足では、順位検索と準備・成立の判定結果を再利用します。M1では同じM5内の最大5足分の検索・判定を1回にまとめ、欠損の結果も再利用します。結果の保持は描画1回の中だけとし、次回描画では更新された履歴を参照します。帯の座標・時刻の連続性・色の切り替え・開始を示す白色は従来どおり各チャート足で処理します。M5以上では足ごとに参照M5時刻が異なるため、それぞれ検索・判定します。

### v1.18 帯の位置・説明文の同値更新を省略

帯のY座標と説明文は、前回設定に成功した値と異なる場合だけ反映します。Canvas作成時に設定済みのY座標も重ねて設定しません。チャートの高さや説明文が変われば更新し、帯の消去・再作成時は記録をリセットします。位置・説明文の設定に失敗した場合は帯を消去し、次回に再作成・再設定します。帯の描画内容と再描画要求の集約は維持します。

### v1.17 最新順位ラベルの横位置計算を共通化

基軸・決済通貨の最新順位ラベルを同じ18px右へ配置する場合、基軸側の座標変換が成功した配置時刻を両通貨で共用し、座標変換を通常4回から2回へ減らします。同順位で決済通貨を66px右へずらす場合や、基軸側の変換が失敗した場合は、決済側も従来どおり個別に計算します。変換先サブウィンドウと配置時刻の検証、取得できない場合は最新順位の足から1足分先へ配置する処理を維持します。

### v1.16 最新順位の探索範囲を限定

最新順位ラベルの元になる有効順位を探す際、設定した表示日数の開始時刻より古い足に到達したら探索を終了します。開始時刻ちょうどの足は対象に含め、期間内の欠損は飛ばして基軸・決済通貨の両順位が有効な最新の足を採用します。期間内に有効順位がなければ、従来どおり順位ラベルを消去し、売買方向と取得元を未取得表示にします。履歴の欠損が多い場合に、表示期間より古い全バーを走査する処理を省きます。

### v1.15 帯の文字幅計算を共通化

帯を描き直す際、タイトル描画後に帯用フォントへ切り替え、`BUY`と`SELL`の文字幅を各1回だけ計測して全区間で使い回します。区間ごとの明示的なフォント設定と文字幅計算を省略し、文字サイズ・中央配置・狭い区間では文字を表示しない条件は維持します。フォント設定や文字幅の取得に失敗した場合は帯を消去し、次回に再試行します。

### v1.14 ラベルと帯の再描画要求を集約

`CurrencyStrengthRankHistory`の最新順位・期間名・売買方向・取得元ラベルと帯の再描画要求を集約し、計算・タイマー・チャート変更イベントの終了時に、このインスタンスから最大1回だけ`ChartRedraw()`を呼びます。表示内容が変わらず更新を省略した場合は要求を追加しません。設定途中の失敗やオブジェクト削除・初回清掃も対象とし、早期終了時とインジケーター終了時にも未反映の要求を処理します。集約先を指定しない描画クラスは従来の動作を維持するため、共通クラスを使用する`CurrencyStrengthAllRankHistory`の再描画方式は変わりません。

### v1.13 消去済みの帯オブジェクトの探索を省略

帯を担当しないインスタンスなどで帯を消去する際、Canvas解放後にオブジェクトの不在を確認したら、その後の消去呼び出しでは解放・探索・再描画要求を省略します。初回は残存オブジェクトを確認し、削除を依頼した場合も不在を確認するまでは再確認を続けます。Canvas作成を試す直前に消去済み状態を解除するため、作成途中の失敗時も後始末を行えます。描画担当の判定は継続し、担当が戻れば帯を再作成します。

### v1.12 ラベルの固定設定を作成時に集約

最新順位・期間名・売買方向・取得元の各ラベルは、フォント・文字サイズ・選択可否・アンカーなどの固定設定を作成時に適用し、通常更新では位置・文字・色だけを反映します。同じ表示内容なら更新を省略する処理も維持します。再作成や設定失敗後の再試行では固定設定も適用し直し、設定が成功した場合だけ前回表示のキャッシュを確定します。最新順位ラベルは通貨名・色だけの変更も更新対象に含めます。共通描画クラスを使用する`CurrencyStrengthAllRankHistory`の期間名・取得元ラベルにも適用されます。

### v1.11 同じ期間名ラベルの更新を省略

「長中期 / WEIGHTED」などの期間名ラベルは、オブジェクトが存在し、前回設定したサブウィンドウと文字列が同じ場合、文字・表示設定の再反映と再描画要求を省略します。削除された場合や表示先・文字列が変わった場合は再設定し、設定に失敗した場合も次回に再試行します。共通描画クラスを使用する`CurrencyStrengthAllRankHistory`にも適用されます。

### v1.10 帯の座標計算を共通化

帯を描き直す際の座標変換を基準となる隣接2足だけで行い、各足のX座標は基準位置と足幅から求めます。時間差ではなく取得した足の並びを使用するため、週末などで時刻が飛んでもチャート上の足位置に合わせます。時間足の秒数とH1以上かの判定も描画1回につき1回だけ行います。スクロール・拡大縮小時は基準位置と足幅を取り直し、順位欠損・時刻の連続性・準備／成立色・帯の開始を示す白色の判定は維持します。

### v1.09 DB取得時のメモリ確保を軽量化

順位履歴の取得上限を、表示日数全体ではなく実際の検索開始～終了時刻のM5足数から求めます。両端のM5足と従来の余裕1件を含めるため、同じM5足だけの再取得は上限2件、隣のM5足までの取得は上限3件となり、DAOの配列予約容量も小さくなります。DAOの上限超過検出用の追加1件は維持します。初回の全期間取得、欠損・遅延時の追いつき取得、年またぎの取得、LIVE優先／TESTER補完の条件は維持します。

### v1.08 変更された履歴だけをコピー

DB再取得範囲より前の履歴を一時配列へコピーする処理を廃止し、変更・追加された履歴点だけをキャッシュへ反映します。再取得した行の内容が同じ場合は代入も省略します。保持範囲の境界は時刻の昇順を利用した二分探索で求めます。配列サイズの変更が必要な場合は、成功してから履歴点を反映し、確保失敗時は既存履歴を維持します。取得結果から消えた末尾の削除と、表示期限を過ぎた履歴の削除・先頭詰めは従来どおり行います。

### v1.07 待機中の表示確認を軽量化

通常チャートの表示確認タイマーを1秒から10秒へ変更し、内部定数で固定します。帯の表示位置・描画担当の確認と、失敗したラベル描画の再試行を10秒間隔に減らします。スクロール・拡大縮小などの画面変更、新しいチャート足、順位履歴の変更時は従来どおり各イベントで更新します。ティックや画面変更がない場合も、帯の担当引き継ぎや描画失敗からの復旧を定期的に確認します。DB再読込は60秒固定・M5新足時に即時、テスターはタイマーを使用しない仕様を維持します。

### v1.04 描画・履歴更新の軽量化

`CurrencyStrengthRankHistory`は初回、順位履歴の変更、新しいチャート足、表示期間の境界変更時に表示バッファと最新順位ラベルを更新します。変更のない通常ティックでは更新を省略し、DB再読込で同じ履歴を取得した場合もキャッシュ全体のコピーと帯の強制再描画を省略します。表示期間から外れた履歴・バッファの削除は継続します。

スクロール・拡大縮小などの画面変更時は、保持した最新順位からラベルを再配置し、帯は既存の画面変更判定に従って描き直します。通常チャートの表示確認タイマーは帯の表示位置・描画担当の確認と、失敗したラベル描画の再試行に使用します（v1.04では1秒、v1.07から10秒）。DB読込間隔、LIVE優先／TESTER補完、順位・塗り・帯の判定条件は変更しません。

`CurrencyStrengthRankHistory`は表示中シンボルの基軸通貨と決済通貨について、DBに保存された長中期または中短期の順位をサブウィンドウへ時系列表示します。描画値は1位を`-1`、8位を`-8`として、1位が上になる向きで表示します。Data Window用の非表示バッファには実順位の1から8を保持します。

サブパネル右上には選択期間と票ウェイト方式を`長中期 / WEIGHTED`のように表示し、その下へ最新順位による売買方向を表示します。基軸通貨の順位が決済通貨より上なら`BUY +5`、決済通貨の順位が基軸通貨より上なら`SELL -3`のように、売買方向と「決済通貨順位 - 基軸通貨順位」を表示します。同順位または未取得なら`-`とします。`BUY`は水色、`SELL`はピンクで表示します。

その下には長中期と中短期の方向一致状態を表示します。両方がBUY方向なら`STRONG BUY`、両方がSELL方向なら`STRONG SELL`、方向が一致しない場合は`MIXED`、未取得の場合は`-`とします。

さらに最新順位点の実際の取得元を`SOURCE: LIVE`または`SOURCE: TESTER`として表示します。`LIVE_THEN_TESTER`の場合も設定名ではなく、LIVE優先マージ後にそのM5時刻で採用されたレコードの`source_mode`を表示します。順位点を未取得の場合は`SOURCE: -`とします。

`databaseProfile`の既定値は`LIVE_THEN_TESTER`です。このプロファイルは指定期間のLIVEとTESTERを取得し、M5時刻単位でマージします。同じM5時刻に両方ある場合はLIVEを採用し、LIVEがないM5時刻はTESTERで補完します。結果はM5時刻の昇順で描画します。`LIVE`、`TESTER`、`AUTO`を指定した場合は、従来どおり選択された単一の`source_mode`だけを参照します。

最新1件を取得する`ZigZagElliot`では、LIVEとTESTERのうちM5時刻が新しい候補を採用し、同時刻の場合はLIVEを採用します。履歴の範囲取得では、各M5時刻のLIVEをTESTERへ上書きする形でマージします。DBやレコードが一方に存在しないことはエラーとせず、存在する側だけを使用します。ただし、SQL準備、バインド、読み取りなどのDB処理エラーが一方で発生した場合は、他方の結果へフォールバックせず検索全体をエラーとします。これによりDB破損やスキーマ不一致を欠損レコードとして隠しません。

主な入力値は次のとおりです。

| 入力値 | 既定値 | 内容 |
|---|---:|---|
| `rankPeriod` | `LONG_MEDIUM` | 長中期順位または中短期順位の選択 |
| `historyDays` | `30` | 表示する過去日数 |
| `subPanelHeight` | `120` | サブパネルの固定高さ（px）。0の場合は固定しない |
| `databaseProfile` | `LIVE_THEN_TESTER` | LIVE優先・TESTER補完、または単一参照元の選択 |
| `voteWeightMode` | `WEIGHTED` | 参照する現行方式または加重方式 |
| `databaseFileName` | `mstng-currency-strength.sqlite` | 年付与前のDBファイル名 |
| `databaseSplitByYear` | `true` | 年別DBを使用する場合true |
| `databaseUseCommonFolder` | `true` | Commonフォルダを使用する場合true |

`CurrencyStrengthAllRankHistory`にも同じ`voteWeightMode`があり、選択した方式の全8通貨順位だけを表示します。右上の期間ラベルにも`長中期 / WEIGHTED`の形式で方式を併記し、UNIFORMとWEIGHTEDのRunを1つの表示内で混在させません。

### CurrencyStrengthAllRankHistory v1.12 最新順位の探索を表示期間内に限定

全通貨版の最新順位ラベルは、表示開始時刻より古い足に達した時点で探索を終了し、保持する履歴が0件の場合は探索自体を省きます。表示開始時刻はM5境界に揃っているため足時刻と直接比較し、開始時刻ちょうどの足は対象に含めます。データ未取得や欠損が続く場合に、チャート全履歴を走査する処理を減らします。全8通貨の実順位が揃う最新足を使う条件と、該当する足がない場合のラベル消去・概要表示・描画再試行は維持します。

### CurrencyStrengthAllRankHistory v1.11 管理情報だけの変更では順位再計算を省略

全通貨版は履歴キャッシュの変更と表示に使う内容の変更を分けて判定します。M5時刻・全16順位・取得元・履歴の有効性が同じで、集計ID（`runId`）や更新時刻（`updatedAt`）だけが変わった場合は、キャッシュだけを更新し、その変更による順位バッファ再計算・最新順位ラベル更新を省きます。集計IDの正値／非正値の切り替えなどで履歴の有効性が変わる場合や、順位・取得元・件数が変わる場合は更新します。管理情報だけが変わった行の後にも比較を続け、後続行の順位変更を検出します。初回取得、新しいチャート足、表示期間の変更、期限切れ削除、描画失敗後の再試行は従来どおり処理します。

### CurrencyStrengthAllRankHistory v1.10 順位検索で前回の位置を再利用

全通貨版の全更新・新規足更新・変更範囲更新は、同じ処理内で前回検索した履歴位置を保持します。新しい足から古い足へ処理する際、1件前の履歴が対象M5時刻と完全一致すればその位置を使い、二分探索を省きます。一致しない場合や初回・欠損後は従来の二分探索を行い、期限切れの先頭部分は参照しません。位置は各更新処理の開始時にリセットし、再取得・前詰め後の位置を持ち越さず、順位訂正・欠損補完と全16バッファの有効性判定を維持します。

### CurrencyStrengthAllRankHistory v1.09 新しい足と変更範囲の重複更新を省略

全通貨版は新規・再計算対象の足を先に更新し、DB履歴の変更範囲はその更新済み件数の次から処理します。同じ足の順位計算と16本のバッファへの書き込みを繰り返さず、新しい足がない場合も先頭1本の重複更新を省きます。更新済み件数には表示期限切れで空値にした足も含め、変更範囲・表示期間の境界、M5単位の計算結果再利用、欠損・無効順位・未来時刻の空値処理は維持します。

### CurrencyStrengthAllRankHistory v1.08 履歴配列の容量をまとめて確保

全通貨版の履歴キャッシュを拡張するときは、`ArrayResize`の予備容量として288件（M5の1日分）を指定し、少量ずつの履歴追加によるメモリ再確保を減らします。配列の件数は実際の格納件数のままとし、予備容量を検索・表示の対象には含めません。期限切れ履歴の参照開始位置とまとめて行う前詰め、全件期限切れ時の解放、配列確保失敗時の既存履歴維持は継続します。

### CurrencyStrengthAllRankHistory v1.07 期限切れ履歴の前詰めをまとめる

全通貨版の期限切れ履歴は参照開始位置を進めて除外し、残り全件を毎回前へコピーする処理を省きます。除外済みの先頭部分が288件（M5の1日分）以上、または残る履歴件数以上になった時点でまとめて前詰めし、全件が期限切れの場合は配列を解放します。検索・比較・置換・件数判定は参照対象の履歴だけで行い、期限切れ時の表示更新も維持します。前詰め後の配列縮小に失敗した場合は履歴を元の位置へ戻し、参照開始位置を保持して次回に再試行します。

### CurrencyStrengthAllRankHistory v1.06 DB取得・LIVE／TESTER統合のコピーを削減

全通貨順位の検索開始と終了が同じ年の場合は、年別DBを使用していても結果配列へ直接取得し、年別作業配列からのコピーを省きます。LIVE優先／TESTER補完の両検索が正常終了し、片側だけに履歴がある場合は、上限確認後に`ArraySwap`で結果配列へ引き継ぎ、統合用配列の確保と全件コピーを省きます。年またぎ・両側に履歴がある場合のLIVE優先統合・DBなしとレコードなしの区別は維持します。取得・配列引き継ぎの失敗や上限超過はエラーとし、結果を空にします。

### CurrencyStrengthAllRankHistory v1.05 M1の順位計算をM5単位で再利用

全通貨版の全更新・新規足更新・変更範囲更新では、同じM5時刻を参照する足が続く場合、最初の足で計算した16本のバッファ値を後続の足へコピーします。M1表示の連続5本が同じM5順位を参照する場合、順位履歴の検索・有効性判定・8通貨分の順位計算は各更新処理内で1回になります。欠損・無効順位・使用可能時刻より未来の空値も再利用します。キャッシュは更新処理ごとに初期化し、後からの順位訂正・欠損補完を反映します。表示期間・変更範囲・全順位の有効性判定は維持します。

### CurrencyStrengthAllRankHistory v1.04 ラベル差分更新と再描画要求の集約

全通貨版の最新順位ラベルは、通貨ごとに変更された位置・文字だけを更新します。時刻だけの変更では位置だけを移動し、順位が変わった場合は位置と文字を更新します。フォント・文字サイズ・色・選択可否などの固定設定は作成・再作成時に適用します。右上の概要ラベルも文字・色の変更項目だけを反映し、固定座標と表示設定は作成時にまとめます。設定失敗時は次のイベントで再試行します。

最新順位・概要・期間名・取得元ラベルと初回清掃の再描画要求を集約し、このインスタンスからの`ChartRedraw()`は計算・画面変更・終了処理ごとに最大1回とします。同じ内容で更新を省いた場合は要求を追加せず、途中で失敗した変更・削除の要求もイベント終了時に処理します。集約先を指定しない描画クラスの呼び出し方も維持します。

### CurrencyStrengthAllRankHistory v1.03 DB取得時のメモリ確保を軽量化

全通貨版の取得上限を、表示日数全体ではなく実際の検索開始～終了時刻のM5足数から求めます。両端のM5足と従来の余裕1件を含め、同じM5時刻だけの再取得は上限2件、次のM5時刻までの取得は上限3件となり、DAOの配列予約容量も小さくなります。初回の全期間取得は従来と同じ上限とし、遅延時の追いつき取得・年またぎ・LIVE優先／TESTER補完・DAOの上限超過検出用の追加1件を維持します。表示内容と再読込間隔は変更しません。

### CurrencyStrengthAllRankHistory v1.02 変更された履歴だけコピー

全通貨版は再取得した履歴が同じ場合、キャッシュの置換を省きます。変更がある場合も再取得範囲より前の履歴は保持し、一時配列へ全件コピーせず、変更・追加された行だけをキャッシュへ反映します。再取得範囲内の同一行は代入も省略し、比較は配列要素を直接参照します。保持範囲の境界は時刻の昇順を利用した二分探索で求めます。配列サイズの変更が必要な場合は成功してから行を更新し、確保失敗時は既存履歴を維持します。取得結果から消えた末尾と表示期限切れ履歴の削除、更新頻度・表示条件は維持します。

### CurrencyStrengthAllRankHistory v1.01 変更時だけ計算・描画

全通貨版は初回、履歴の変更、新しいチャート足、表示期間の境界変更時に16本の表示・実順位バッファと最新順位ラベルを更新します。変更のないティックや、同じ履歴を再取得した場合はバッファ更新・最新順位の探索・8通貨分のラベル座標計算を省きます。最新有効バーの時刻・8通貨順位・取得元を保持し、画面変更時はその値からラベルを再配置します。描画や座標変換に失敗した場合は、次のティックまたは画面変更で再試行します。DB再読込の入力設定と既定15秒、M5更新時の取得、LIVE優先／TESTER補完、全順位の有効性判定は維持します。

## 17. EAの通貨強弱参照

`MstngEa`の`InpUseCurrencyStrength`は既定で`false`、`InpCurrencyStrengthVoteWeightMode`は既定で`WEIGHTED`です。`UNIFORM`では`pair-direction-closed-v1`、`WEIGHTED`では`pair-direction-weighted-closed-v1`を完全一致検索します。保存側`CurrencyStrengthElliot`とEAで同じ方式を選択する必要があり、選択方式の同一M5 Runがない場合は別方式へフォールバックせず通貨強弱フィルタを不通過とします。

`Mail::getCurrencyStrengthText()`を使用する分析結果メールの通貨強弱ヘッダーには、参照した`calculation_version`に対応する票ウェイト方式を`MODE:WEIGHTED`または`MODE:UNIFORM`として表示します。DBなし、データなし、取得エラーの場合も、検索を試みた方式を同じ形式で表示します。現行`MstngEa`本体には実メール送信経路がなく、この記述はメール本文フォーマットの仕様です。
