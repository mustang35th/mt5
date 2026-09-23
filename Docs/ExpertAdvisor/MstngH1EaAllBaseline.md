# MstngH1EaAll 基準バックテスト手順

第8段階、EA v1.06の記録・集計機能です。28通貨を全体上限なしで測定し、後続の上限候補比較に使います。実測結果と推奨上限はまだありません。

## 1. テスター設定

| 項目 | 設定 |
|---|---|
| EA | `MstngH1EaAll` v1.06 |
| チャート銘柄 | 対象28通貨のうち1つ。比較テストでは固定する |
| 時間足 | H1 |
| モデル | リアルティックに基づいた全ティック |
| 最適化 | 無効。EAは最適化非対応 |
| 口座 | ヘッジ口座 |
| 初期証拠金・口座通貨・レバレッジ | テスト前に決め、比較する全テストで固定する |
| 期間 | ウォームアップを含むテスト開始日と終了日を指定 |
| 固定ロット `InpLotSize` | 既定0.01。比較中に変更しない |
| 最大初期SL幅 `InpMaxInitialStopLossPips` | 既定100.0 pips。正の値必須 |
| 売買開始日時 `InpTesterTradeStartTime` | 集計対象の開始日時をサーバー時刻で指定。既定値のままでよいか確認する |
| 基準テスト集計用CSVを出力 `InpExportBaselineReport` | true |
| 28通貨の状態パネルを表示 `InpShowStatusPanel` | 任意。非ビジュアルでは描画せず、CSV出力は継続 |

売買開始日時より前にテスト開始日を置くと、その期間は履歴準備だけを行います。必要なMN1～H1の履歴は28通貨すべてについて用意します。一定の日数を指定しただけで、履歴・指標の準備完了を保証するものではありません。開始直後の履歴待ちや分析待ちは第7段階のパネル・ログで確認します。

`InpTesterTradeStartTime=0`は開始制限なしです。基準比較では、意図した売買開始日時を明示する方が比較しやすくなります。「始値のみ」はこの基準テストの対象外です。

テスト期間、モデル、約定遅延、broker/server、データ品質、初期証拠金、レバレッジ、MT5 build、EA版、inputを保存してください。CSVには取得可能な口座条件・設定hash・buildを残しますが、テストモデルや予定終了日を自動取得したとは扱いません。MT5の設定ファイルと標準レポートを併せて保存します。

## 2. 出力先

```text
Terminal Common Files/
  MstngH1Ea/Backtests/<sessionUid>/
    runs.csv
    samples.csv
    deals.csv
    summary.csv
    status.csv
```

通常のWindows環境では`%APPDATA%\MetaQuotes\Terminal\Common\Files`配下です。端末ログの`BASELINE_REPORT`に相対パスを表示し、正常出力終了時は`BASELINE_EXPORTED`を記録します。失敗時は`BASELINE_INCOMPLETE`です。繰り返しテストしてもsessionごとのフォルダへ分離し、前回結果を上書きしません。既存のLockによる同時起動制約は維持します。

| ファイル | 列数 | 内容 |
|---|---:|---|
| runs.csv | 10 | 28通貨のsymbol/Magic、Run ID/UID、session、EA/戦略版、設定hash/canonical、分析設定hash |
| samples.csv | 15 | サーバー時刻、実保有、未完了注文、対象外件数、口座残高・Equity・証拠金、対象含み損益、SL追加損失の既知合計・不明件数、読取エラー、通貨方向別件数 |
| deals.csv | 12 | 全約定のticket、ミリ秒時刻、position ID、symbol/Magic、type/entry、数量、損益・commission・swap・fee |
| summary.csv | 2 | schema、終了経路、時刻、出力件数、口座条件、MT5標準成績、出力エラー有無 |
| status.csv | 2 | 他ファイル確定後の`exportState=EXPORTED` |

CSVはUTF-8、カンマ区切りです。文字列は引用符をエスケープします。時刻の数値はMT5のサーバー日時を表す秒またはミリ秒で、JSTへの変換は行いません。口座金額は`accountCurrency`単位です。

`currencySlots`は`EUR:買い側件数:売り側件数|USD:買い側件数:売り側件数`形式です。EURUSD BUYはEUR買い側・USD売り側、SELLは逆へ1件ずつ加算します。両側の最大値は別の時点の可能性があるため、最大買い側と最大売り側を足して最大両側合計とはしません。

同じサンプル内容は60秒ごとの記録へ圧縮します。観測そのものは売買開始後のTimer/Tick処理後、最短1秒間隔です。SLリスク・証拠金・通貨集中の瞬間的なピークを保証するものではありません。OnTradeTransaction内ではレポート処理をせず、短時間の保有変化は終了時の約定履歴から復元します。

## 3. 集計コマンド

MQL5フォルダで実行します。`<sessionUid>`は出力されたフォルダ名へ置き換えてください。Python標準ライブラリだけで動作します。

```powershell
$baselineFolder = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\MstngH1Ea\Backtests\<sessionUid>'
python -X utf8 -B Scripts/Mstng/Analysis/h1_ea_baseline_report.py $baselineFolder
```

Markdownファイルに保存する場合:

```powershell
python -X utf8 -B Scripts/Mstng/Analysis/h1_ea_baseline_report.py $baselineFolder --output baseline-report.md
```

既存の出力ファイルは上書きしません。異なる名前で再出力してください。元CSV・DBは変更しません。

## 4. 集計値の読み方

- **同時保有数**: position IDごとの約定数量を積み上げ、部分決済では残量0まで1ポジションと数えます。ポジションを開いたMagicで帰属を決め、決済のMagicが変わっても追跡します。
- **時間分布・平均・分位点**: 売買開始以降の経過時間で重み付けします。無保有時間と週末も含みます。約定回数やCSV行数で重み付けしません。
- **同一ミリ秒**: その時刻の全約定処理後の最大と、ticket順の参考最大を分けます。同一ms内の正確な順序は復元できないため、参考最大を確定値とはしません。
- **損益・最大DD**: MT5標準の口座成績です。DD金額最大の時点とDD率最大の時点は同じとは限りません。対象外取引があれば、対象EAだけの成績とはしません。
- **SLリスク**: 現在の決済側価格からbroker設定済みSLまでの追加損失見込です。利益分と相殺せず、損失分だけ合計します。SLなし・計算失敗は不明件数です。手数料・滑り・窓開け・保留SL・未約定注文を含みません。
- **通貨集中**: 金額換算ではなく、各通貨の買い側・売り側に何ポジションが偏ったかを見る件数です。
- **未完了注文数**: brokerの注文一覧で取得できた観測値です。送信結果待ち・不明を含む内部の枠予約数は第9段階の対象です。

## 5. 結果として採用する前の確認

完了マーカー、schema、28通貨・同一session、上限なし設定、CSV列数・行数、約定数量整合、観測保有数と約定復元の最大値を集計ツールで確認します。反転約定INOUTはヘッジ基準テストの対象外としてエラーにします。対象外取引、読取失敗、不明リスク、終了時未決済はレポートに要確認事項として残します。

`OnTester`到達はテスト終了イベントを受けた意味です。途中停止でも予定期間の完走を保証するものではありません。MT5標準レポートとログを確認し、予定期間、データ品質、28通貨の分析可否、DB/Lease/注文失敗の有無を確認してください。出力件数0はエントリーがなかった場合と期間未到達を区別します。期間未到達・サンプルなしは集計エラーです。

観測最大数をそのまま運用上限にせず、損益・DD・リスク・証拠金・通貨集中を併せて候補値を決めます。第9段階で上限inputと発注待ちを含む枠管理を実装し、第10段階で候補ごとに再テスト・別期間検証を行います。基準テストの取引を単純に削除して上限ありの成績とする方法は採りません。

## 6. 根拠と検証範囲

- 口座通貨による損益見積り: [MQL5 OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit)
- 約定識別・時刻・部分決済: [MQL5 Deal Properties](https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties)
- 標準成績: [MQL5 Testing Statistics](https://www.mql5.com/en/docs/constants/environment_state/Statistics)
- 終了イベント: [MQL5 OnTester](https://www.mql5.com/en/docs/event_handlers/ontester)

集計テスト17件、EAの静的契約テスト140件、実装をC#へ構文変換して外部APIをfixtureへ置き換えた観測クラス20項目を確認しました。fixtureが出力したCSVを同じ集計コマンドへ渡してMarkdown生成まで確認しています。通常版・全通貨版のMetaEditorコンパイルはエラー0・警告0です。これは実MT5の市場データによるバックテストではありません。稼働用ex5・運用DBは変更していません。
