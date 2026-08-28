# ZigZagElliot H1推移 将来成績

## 1. 目的

`ZigZagElliotH1StudyOutcomeBuilder`は、H1推移研究DBに保存済みのObservationから連続シグナルを抽出し、同じ研究用エントリーへ6／12／24／48H1後の成績を付ける後処理Scriptです。

4つの期間は別々のエントリーではありません。1件のEntryに4件のOutcomeを保存します。

参照元DBは読み取り専用で開き、結果は別DBへ保存します。参照元のObservationは更新しません。

## 2. 対象条件

完全一致条件は`FULL_ALIGNMENT_EPISODE_V1`です。

- BUY: W1、D1、H4、H1の`is_buy`がすべて1
- BUY: H4、H1のEMA200が`is_buy=1`かつ`is_sell=0`
- SELL: W1、D1、H4、H1の`is_buy`がすべて0
- SELL: H4、H1のEMA200が`is_buy=0`かつ`is_sell=1`

同じStreamで同方向の完全一致が市場の次H1まで継続している間を、1つのEpisodeとして扱います。通常の1時間差に加え、次の休場跨ぎを連続H1とします。

- 金曜日23:00から月曜日00:00
- 12月24日23:00から12月26日00:00
- 12月31日23:00から1月2日00:00

条件OFF、方向反転、必要時間足の欠損または未知の時刻GapでEpisodeを分割します。

Episodeは全取得期間の行で先に確定し、その後にEpisode開始JSTが`studyFromJstTime`以上かつ`studyToJstTime`未満のものを研究対象にします。これにより期間開始直前から継続していたシグナルを新規シグナルとして数えません。

## 3. 連続確認とエントリー

各Episodeから次の候補を作ります。

- 条件成立1本目を確認した直後のH1始値
- 2本連続を確認した直後のH1始値
- 3本連続を確認した直後のH1始値

Episodeが1本なら1本確認だけ、2本なら1本確認と2本確認だけを作ります。4本以上継続しても確認候補は1／2／3本の3種類です。

候補行を`O0`とした場合の価格対応は次のとおりです。

```text
O0: 条件確認Observation
O1: 研究用Entry。O1.current_openをエントリー価格に使用
O2: 評価1本目の確定OHLCをO2.previous_*から取得
...
O(h+1): h本目の確定OHLCと終了価格をprevious_*から取得
```

次のObservationを飛ばしてEntryを探すことはしません。直後行が欠損または非連続なら、その理由をEntryへ保存して計算対象外にします。

## 4. 保存する将来成績

各Entryへ6、12、24、48H1のOutcomeを必ず1件ずつ保存します。

| 項目 | 計算方法 |
|---|---|
| 終了時の方向別損益 | BUYは`(終了Close - Entry Open) / pipSize`、SELLは符号を反転 |
| Spread控除後損益 | 方向別損益からEntry ObservationのSpreadを1回控除 |
| MFE | 評価期間中の方向別最大有利幅 |
| MAE | 評価期間中の方向別最大不利幅 |
| ATR換算損益 | 損益pipsをEntry ObservationのH1 ATR14 pipsで除算 |
| 最大利益までのH1本数 | MFEへ最初に到達した評価H1の1始まり番号。MFEが0なら0 |

価格モデルは`H1_BID_OHLC_V1`です。SpreadはEntry時点の値を固定で1回控除し、将来のSpread変動やスリッページは再現しません。

`pip_size`が参照元Observationへ保存されている場合はその値を使用し、Entryの`pip_size_source`を`SOURCE_DB`とします。旧研究DBのように列がない、または値がNULLの場合は、シンボル名に`JPY`を含むペアを`0.01`、それ以外を`0.0001`として補完し、`SYMBOL_RULE_V1`を保存します。これにより補完値を実測値と区別できます。

6H1を計算できても48H1を計算できない場合があります。その場合、6H1は`READY`、48H1は欠損理由を持つ未計算Outcomeとして別々に保存されます。

## 5. 完全性フラグ

Entryには次の監査情報を保存します。

- 左端／右端でEpisodeが打ち切られたか
- Episode直前／直後にデータGapがあるか
- 次H1 Entryを確定できたか
- Spread、pip size、Entry時H1 ATR14を取得できたか
- 基本研究集計へ使用可能か

左端打切り、Episode直前のGapまたはEntry不成立は`is_research_eligible=0`です。行自体は削除せず、`eligibility_status`、`entry_status`および`calculation_note`に理由を残します。

Outcomeも計算不能行を削除しません。数値列はSQL `NULL`、`is_calculated=0`、`data_status`に`FUTURE_INCOMPLETE`、`FUTURE_H1_GAP`などの理由を保存します。

## 6. DB構成

既定の参照元DB:

```text
mstng-zigzag-elliot-h1-study-2024-2025-r1.sqlite
```

既定の結果DB:

```text
mstng-zigzag-elliot-h1-study-outcome-2024-2025-r1.sqlite
```

結果DBには次の3テーブルを作成します。

| テーブル | 内容 |
|---|---|
| `zigzag_elliot_h1_study_outcome_runs` | 参照元Run、研究期間、ルールVersion、総件数 |
| `zigzag_elliot_h1_study_entries` | Episodeと1／2／3本確認ごとの研究用Entry |
| `zigzag_elliot_h1_study_outcomes` | Entryごとの6／12／24／48H1成績 |

同じ参照元Run、研究期間および計算Versionで再実行すると同じOutcome Runを再利用し、EntryとOutcomeを作り直します。処理全体を1トランザクションにするため、途中で失敗した場合は直前の完成結果を保持します。

## 7. 実行方法

1. MetaEditorで`Scripts/Mstng/Analysis/ZigZagElliotH1StudyOutcomeBuilder.mq5`をコンパイルします。
2. MT5のNavigatorからScriptをチャートへ実行します。
3. `sourceDatabaseFileName`と`outcomeDatabaseFileName`が別名であることを確認します。
4. 参照元にRunが1件だけなら`sourceRunId=0`で自動選択できます。複数Runがある場合は対象IDを明示します。参照元Runの状態は`LEGACY`または`COMPLETED`である必要があり、更新途中の`RUNNING`や失敗した`FAILED`は処理しません。
5. Journalの`COMPLETED`ログとRunテーブルの件数を確認します。

既定の研究期間はJSTの`2024-01-01 00:00:00`以上、`2026-01-01 00:00:00`未満です。期間終了後のObservationは、対象候補の48H1成績を確定するための将来バッファとして読み取ります。

基本集計では、Entryの`is_research_eligible=1`かつOutcomeの`is_calculated=1`を使用します。

```sql
SELECT
    e.symbol_name,
    e.side,
    e.confirmation_h1_count,
    o.horizon_h1_bars,
    o.net_profit_pips,
    o.mfe_pips,
    o.mae_pips,
    o.max_profit_h1_bars
FROM zigzag_elliot_h1_study_entries AS e
JOIN zigzag_elliot_h1_study_outcomes AS o
  ON o.entry_id = e.id
WHERE e.is_research_eligible = 1
  AND o.is_calculated = 1
  AND e.outcome_run_id = :outcome_run_id;
```

`:outcome_run_id`には、`zigzag_elliot_h1_study_outcome_runs.status = 'COMPLETED'`を確認した対象Run IDを指定します。異なる参照元Run、研究期間または計算Versionを混在させて集計しないでください。

## 8. r1受入期待値

既定の参照元DBを読み取り専用で同じ規則に通した受入監査値は次のとおりです。Builder実行後のRun件数を照合する基準として使用できます。

| 対象 | 期待件数 |
|---|---:|
| Stream | 28 |
| Observation | 350,713 |
| Signal Episode | 15,658 |
| Entry | 30,672 |
| Eligible Entry | 30,657 |
| Outcome | 122,688 |
| READY Outcome | 122,334 |
| `FUTURE_H1_GAP` Outcome | 354 |

確認本数別Entryは1本確認15,658件、2本確認9,823件、3本確認5,191件です。Outcome失敗は6H1が34件、12H1が53件、24H1が88件、48H1が179件で、すべて`FUTURE_H1_GAP`です。

この値は既定期間と現行Versionの期待値です。参照元DB、研究期間または判定・計算Versionを変更したRunへ流用しないでください。

## 9. 基準成績CSV

`ZigZagElliotH1StudyBaselineExporter`は、完了済みOutcome Runを読み取り専用で集計し、Step 5の基準成績CSVを作成します。参照DBは更新しません。

集計軸は次の36グループです。

- 連続確認: 1本、2本、3本
- 評価期間: 6、12、24、48H1
- 方向範囲: `ALL`、`BUY`、`SELL`

`ALL`は同じ確認本数・評価期間のBUYとSELLを合算した監査行です。BUY／SELLの件数合計とALLが一致することを確認できます。

Entryの母数と成績の母数は分けて保存します。

| 項目 | 定義 |
|---|---|
| `candidate_entry_count` | 研究対象外を含むグループ内の全Entry |
| `eligible_entry_count` | `is_research_eligible = 1`のEntry |
| `calculated_outcome_count` | 研究対象Entryかつ`is_calculated = 1`のOutcome |
| `failed_outcome_count` | 研究対象Entryかつ`is_calculated = 0`のOutcome |
| 勝ち／負け／同値 | 計算成功した`net_profit_pips`が`+1e-8`超／`-1e-8`未満／絶対値`1e-8`以下 |
| 勝率 | 勝ち件数 ÷ 計算成功件数 |
| Profit Factor | 正の`net_profit_pips`合計 ÷ 負の`net_profit_pips`絶対値合計 |
| 平均・中央値 | 計算成功した`net_profit_pips`だけを使用 |
| MFE／MAE平均 | 計算成功した保存値の平均 |
| ATR換算平均 | 各OutcomeのATR換算値を先に計算してから平均 |
| Entry Spread平均 | Outcomeの成否を問わない研究対象EntryのSpread平均 |
| Gap率 | `FUTURE_H1_GAP`件数 ÷ 研究対象Entry数 |

損失合計が0の場合、有限のProfit Factorを作りません。正の損益が存在する場合は`INFINITE_NO_LOSS`、損益変動がない場合は`NO_VARIATION`、計算標本がない場合は`NO_SAMPLE`を`profit_factor_status`へ出力し、`profit_factor`は空欄にします。

浮動小数計算による数学的な0の微小誤差を勝ち／負けへ分類しないため、`1e-8 pips`を許容誤差として使用します。使用値は`profit_zero_epsilon_pips`列へ出力し、許容誤差内の値はProfit Factorの正負合計からも除外します。

実行手順は次のとおりです。

1. Outcome Builderが完了していることを確認します。集計中は同じOutcome DBへBuilderを同時実行しません。
2. MetaEditorで`Scripts/Mstng/Analysis/ZigZagElliotH1StudyBaselineExporter.mq5`をコンパイルします。
3. MT5のNavigatorからScriptをチャートへ実行します。
4. `outcomeRunId = 0`の場合、`COMPLETED`のRunが1件だけなら自動選択します。複数ある場合はRun IDを明示します。
5. 既定ではTerminal Common Filesへ次のCSVを上書きします。

```text
mstng-zigzag-elliot-h1-study-baseline-2024-2025-r1-run-1.csv
```

既定r1では、研究対象30,657 Entryに4期間を付けた122,628 Outcomeのうち、122,274件が計算成功、354件が`FUTURE_H1_GAP`です。Run全体の計算成功122,334件には研究対象外15 Entryの60 Outcomeが含まれるため、基準成績の母数には使用しません。

このCSVは母集団の異なる1本／2本／3本確認をそのまま比較する基準集計です。同じEpisodeに限定した公平比較は次のStepで別集計します。

## 10. 同一Episodeの確認本数比較

`ZigZagElliotH1StudyConfirmationComparisonExporter`は、同じSignal Episodeに属する1本／2本／3本確認Entryを比較し、確認を待つことによる成績差を出力します。Outcome DBは読み取り専用で開き、参照DBを更新しません。

Episodeの結合キーは`outcome_run_id`と`signal_start_observation_id`です。評価期間は各Entryを起点とする6／12／24／48H1であり、同じ決済時刻を比較するものではありません。

比較Cohortは次の2種類です。

| Cohort | 候補 | 成績集計対象 |
|---|---|---|
| `PAIR_1_2` | 同じEpisodeに1本・2本確認Entryが存在 | 両Entryが研究対象で、同じ評価期間の両Outcomeを計算できるEpisode |
| `COMMON_1_2_3` | 同じEpisodeに1本・2本・3本確認Entryが存在 | 3 Entryが研究対象で、同じ評価期間の3 Outcomeをすべて計算できるEpisode |

既定ではTerminal Common Filesへ次の2ファイルを上書きします。

```text
mstng-zigzag-elliot-h1-study-confirmation-comparison-episodes-2024-2025-r1-run-1.csv
mstng-zigzag-elliot-h1-study-confirmation-comparison-summary-2024-2025-r1-run-1.csv
```

実行時は`ZigZagElliotH1StudyConfirmationComparisonExporter.mq5`をコンパイルし、スクリプトとして実行します。`outcomeRunId = 0`の場合、`COMPLETED`のOutcome Runが1件だけなら自動選択します。複数ある場合は比較対象のRun IDを明示します。

Episode明細CSVは、1本・2本確認Entryが存在するEpisodeを評価期間ごとに1行出力します。研究対象外、Outcome計算不能、3本確認が存在しない行も監査できるように残します。各確認本数のEntry時刻、Spread、gross／net損益、ATR換算、MFE、MAE、最大利益到達本数と、`2 - 1`、`3 - 1`、`3 - 2`の差を保存します。

差分は正の値を「確認を待った側の改善」と読めるように統一します。gross／net損益、MFE、ATR損益は待機側から先行側を引き、MAE、Spread、最大利益到達本数は先行側から待機側を引きます。最大利益到達本数の短縮は両OutcomeのMFEが正の場合だけ集計します。ATR損益差は各Entry固有のATRで換算した値同士の差であり、同一ATRを分母にした比較ではありません。

集計CSVは、Cohort 2種類、評価期間4種類、方向`ALL`／`BUY`／`SELL`の24行です。候補・研究対象・比較可能・Gap件数、Coverage、各確認本数の勝率・平均・中央値・Profit Factor、各差分の改善／同値／悪化件数を保存します。

損益の勝ち／負け／同値および差分の改善／悪化／同値は、`1e-8 pips`を許容誤差として判定します。絶対値が許容誤差以下の損益は同値、差分は0へ正規化します。使用値は`profit_zero_epsilon_pips`列へ出力します。

既定r1の受入件数は次のとおりです。

| Cohort | 候補 | 共通研究対象 | 6H1 | 12H1 | 24H1 | 48H1 |
|---|---:|---:|---:|---:|---:|---:|
| `PAIR_1_2` | 9,823 | 9,819 | 9,806 | 9,800 | 9,792 | 9,758 |
| `COMMON_1_2_3` | 5,191 | 5,189 | 5,185 | 5,183 | 5,178 | 5,161 |

Episode明細は39,292行、集計は24行です。集計中は同じOutcome DBへOutcome Builderを同時実行しません。

共通Cohortは、後から2本または3本まで条件が継続したEpisodeへ事後的に限定した比較です。確認を待つことによるEntry位置の差を調べる用途には使えますが、ライブ時点の無条件期待値ではありません。実運用母集団の判断ではStep 5の基準成績も併記してください。

## 11. 条件ファネル別の成績分解

`ZigZagElliotH1StudyConditionBreakdownExporter`は、参照元H1推移DBを読み取り専用で開き、方向条件を段階的に追加したときのシグナル数と将来成績を比較します。参照元DBと既存Outcome DBは更新しません。

現行Outcome Runは、W1／D1／H4／H1方向とH4／H1 EMA200が完全一致したObservationだけを候補化しています。そのため、既存Outcomeへ条件列を追加して集計しても全Entryが同じ条件を満たし、条件差を検証できません。Step 7では参照元の全Observationから、次の累積ルールごとにEpisodeと将来成績を再計算します。

| 順序 | `condition_rule` | 必須条件 | 今回追加する条件 |
|---:|---|---|---|
| 1 | `H1_DIRECTION` | H1方向 | H1方向 |
| 2 | `H4_H1_DIRECTION` | H4、H1方向一致 | H4方向 |
| 3 | `D1_H4_H1_DIRECTION` | D1、H4、H1方向一致 | D1方向 |
| 4 | `W1_D1_H4_H1_DIRECTION` | W1、D1、H4、H1方向一致 | W1方向 |
| 5 | `W1_D1_H4_H1_DIRECTION_H1_EMA200` | 4方向＋H1 EMA200一致 | H1 EMA200 |
| 6 | `FULL_ALIGNMENT` | 4方向＋H1／H4 EMA200一致 | H4 EMA200 |

方向はH1を基準にBUYまたはSELLとします。EMA200はBUY時に`is_ema200_buy = 1`かつ`is_ema200_sell = 0`、SELL時に`is_ema200_buy = 0`かつ`is_ema200_sell = 1`を要求します。両方0の`NONE`をSELLへ含めません。全ルールでW1／D1／H4／H1の子Observationがそろっていることを要求し、欠損による母集団差を防ぎます。

各ルールを個別にON／OFF判定し、同じ方向で連続するH1を1つのEpisodeへまとめます。各Episodeについて1本目、2本連続確認後、3本連続確認後を候補にし、研究用Entryは確認完了の次H1始値です。評価期間と価格モデルはStep 4と同じ6／12／24／48H1、`H1_BID_OHLC_V1`、`ENTRY_SPREAD_ONCE_V1`です。

出力は既定でTerminal Common Filesの次のCSVです。

```text
mstng-zigzag-elliot-h1-study-condition-breakdown-2024-2025-r1-run-1.csv
```

集計軸は6ルール、3確認本数、4評価期間、方向`ALL`／`BUY`／`SELL`の216行です。候補・研究対象・計算成功・Gap件数、勝ち／負け／同値、勝率、平均・中央値、Profit Factor、MFE、MAE、ATR換算損益、Entry Spread、最大利益到達本数をStep 5と同じ定義で出力します。勝敗とProfit Factorには`1e-8 pips`の許容誤差を使用します。

既定r1の候補Entry件数は次のとおりです。

| 条件ルール | 1本確認 | 2本確認 | 3本確認 |
|---|---:|---:|---:|
| `H1_DIRECTION` | 108,344 | 83,513 | 56,778 |
| `H4_H1_DIRECTION` | 73,521 | 51,375 | 31,948 |
| `D1_H4_H1_DIRECTION` | 41,133 | 26,886 | 15,154 |
| `W1_D1_H4_H1_DIRECTION` | 22,543 | 14,343 | 7,734 |
| `W1_D1_H4_H1_DIRECTION_H1_EMA200` | 20,626 | 12,922 | 6,873 |
| `FULL_ALIGNMENT` | 15,658 | 9,823 | 5,191 |

`FULL_ALIGNMENT`の36行はStep 5の基準成績と一致することを回帰条件とします。隣接ルールでは条件追加によりEpisodeの区切りとEntry時刻も変わるため、成績差は条件単体の固定母集団における因果効果ではありません。「その条件を実運用ルールへ追加した場合のシグナル頻度と成績の変化」として解釈します。

## 12. 時期・通貨ペア別の安定性確認

`ZigZagElliotH1StudyConditionStabilityExporter`は、Step 7と同じ条件Episodeと将来成績を期間・通貨ペア別に分解します。参照元H1推移DBは読み取り専用で開き、参照元DBと既存Outcome DBは更新しません。

目的は、Step 7の全体成績が特定の年、四半期または少数通貨ペアだけに依存していないかを確認することです。良い区分を探して条件を追加するための最適化ツールではありません。

出力行には`dimension_type`と`dimension_value`を追加し、次の4種類を出力します。

| `dimension_type` | `dimension_value` | 既定r1の区分数 | 内容 |
|---|---|---:|---|
| `OVERALL` | `ALL` | 1 | Step 7と同じ全体集計 |
| `YEAR` | `2024`、`2025` | 2 | Episode開始JSTの年 |
| `QUARTER` | `2024-Q1`～`2025-Q4` | 8 | Episode開始JSTの年・四半期 |
| `SYMBOL` | `AUDUSD`など | 28 | 参照元Streamの通貨ペア |

期間bucketはEntry時刻ではなく、`period_bucket_policy = EPISODE_START_JST_V1`としてEpisode開始JSTから決定します。Step 7の研究期間判定と基準をそろえ、次H1 Entryが成立しない研究対象外候補も必ず1つの年と1つの四半期へ配分できるようにするためです。このポリシーはCSVの全行へ出力します。

各区分について、Step 7と同じ6条件ルール、3確認本数、4評価期間、3方向範囲を組み合わせます。既定r1の行数は次のとおりです。

| 対象 | 計算 | 行数 |
|---|---:|---:|
| `OVERALL` | 1 × 6 × 3 × 4 × 3 | 216 |
| `YEAR` | 2 × 6 × 3 × 4 × 3 | 432 |
| `QUARTER` | 8 × 6 × 3 × 4 × 3 | 1,728 |
| `SYMBOL` | 28 × 6 × 3 × 4 × 3 | 6,048 |
| 合計 | 39 × 6 × 3 × 4 × 3 | 8,424 |

完全な比較cubeにするため、候補が0件の組み合わせも行を出力します。CSVはStep 7の55列に`period_bucket_policy`、`dimension_type`、`dimension_value`を追加した58列です。勝敗、Profit Factor、MFE、MAE、ATR換算、SpreadおよびGapの定義はStep 7と変えません。

期間bucketの終端で将来成績を打ち切りません。例えば2024年12月に開始したEpisodeの48H1 Outcomeが2025年に入っても、そのOutcomeは`YEAR = 2024`に集計します。四半期も同様です。年・四半期の境界を越えただけで`FUTURE_H1_GAP`にしません。

研究期間の終了後にあるObservationも、48H1成績を確定するための将来バッファとして使用します。実際に将来H1が非連続または不足している場合は、Step 7と同じく評価期間ごとに計算不能とし、`future_h1_gap_count`またはその他の失敗件数へ残します。6H1を計算できて48H1を計算できない候補を行ごと除外しません。

出力後は次の再合算条件を確認します。

- `OVERALL`の216行がStep 7の対応行と一致すること
- 同じ条件ルール・確認本数・評価期間・方向において、`YEAR`、`QUARTER`、`SYMBOL`それぞれの件数合計が`OVERALL`と一致すること
- 各`YEAR`に属する4四半期の件数合計がその`YEAR`と一致すること
- 各bucketで`BUY + SELL = ALL`が候補、研究対象、計算成功、失敗、Gap、勝ち、負け、同値の全件数について成立すること
- 加算可能な損益合計も同様に再合算でき、率、平均、Profit Factorを件数と損益合計から再計算できること

中央値は子bucketの中央値を足したり平均したりして復元できません。`OVERALL`の中央値は全個別Outcomeから直接計算し、Step 7との一致で検証します。

実行手順は次のとおりです。

1. MetaEditorで`Scripts/Mstng/Analysis/ZigZagElliotH1StudyConditionStabilityExporter.mq5`をコンパイルします。
2. MT5のNavigatorからScriptをチャートへ実行します。
3. `sourceRunId = 0`の場合、対象にできるSource Runが1件だけなら自動選択します。複数ある場合はRun IDを明示します。
4. 既定ではTerminal Common Filesへ次のCSVを上書きします。

```text
mstng-zigzag-elliot-h1-study-condition-stability-2024-2025-r1-run-1.csv
```

5. CSVが8,424行・58列であること、Journalの完了ログ、上記の再合算条件を確認します。

同じ候補は`OVERALL`、`YEAR`、`QUARTER`、`SYMBOL`へそれぞれ1回ずつ表現されるため、異なる`dimension_type`の行を足してシグナル件数と解釈しません。28通貨ペア×6ルール×3確認本数×4期間×3方向の多数比較になるため、少数標本の極端な勝率やProfit Factorをそのまま採用条件にしません。最低標本数と、年・四半期・通貨ペアにまたがる一貫性基準を先に固定してから判定します。
