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
