# MstngH1Ea基本設計書

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 対象EA | 新規H1専用EA（仮称：`MstngH1Ea`） |
| 実装予定ファイル | `Experts/MstngH1Ea.mq5` |
| 対象プラットフォーム | MetaTrader 5 |
| 対象時間足 | H1固定 |
| 対象戦略 | `MTF_3in3`固定 |
| 文書状態 | 基本設計・実装前 |
| 設計バージョン | 0.1 |
| 最終更新日 | 2026-09-02 |

本書は、`MstngEa`を基礎として機能をH1運用に限定した新EAの初版仕様を定義します。現行の`MstngEa`を変更する設計ではなく、必要な判定クラスだけを再利用して、制御、発注および永続化を新しく構成します。

SQLiteの物理構成、列および制約は[MstngH1Eaデータベース設計書](../Database/MstngH1EaDatabase.md)を参照してください。

## 2. 目的

初版の目的は、H1の`MTF_3in3`条件だけを使用して、次を安全かつ再現可能に実行することです。

- H1新規バーごとのエントリー判定
- 固定ロットの成行注文
- 必須のbrokerストップロス
- H1反対GMMAによる全量決済
- 同一シグナルの再起動をまたぐ重複防止
- 判定、注文および決済結果のSQLite保存
- 再起動時のDBとbrokerポジションの整合

多機能化よりも、注文根拠、ポジション状態および決済結果を追跡できる小さな実装を優先します。

## 3. 初版の対象範囲

### 3.1 採用する機能

- H1チャート限定
- `MTF_3in3`戦略限定
- D1、H4、H1の方向分析
- H1およびH4のElliott波動判定
- H1 GMMA判定
- H1およびH4のEMA200方向判定
- 最大3 pipsのSpread制限
- 1シグナルにつき1回のエントリー試行
- 同一シンボル、同一Magic Numberで1ポジション
- 固定ロットの成行注文
- H1 ZigZag基準点による必須初期SLと最大幅制限
- H1反対GMMAによる全量決済
- 専用SQLiteへの判定・取引保存
- 障害調査用のテキスト運用ログ

### 3.2 初版の対象外

- H1以外の時間足
- 戦略選択
- W1確認
- 通貨強弱フィルター
- EMA200との距離制限
- 建値移動
- 利益戻し決済
- ZigZagによるSLトレイル
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
  │    ├─ H1新規バー検出
  │    ├─ D1/H4/H1分析
  │    ├─ エントリー・決済判定
  │    └─ 再起動整合
  ├─ H1 MTF_3in3判定
  │    ├─ D1/H4/H1方向
  │    ├─ H1/H4 Elliott
  │    ├─ H1 GMMA
  │    └─ H1/H4 EMA200
  ├─ H1専用Trade Executor
  │    ├─ OrderCheck
  │    ├─ 成行発注
  │    ├─ 必須SL
  │    └─ pending確認
  └─ H1 EA SQLite
       ├─ Run
       ├─ H1判定
       └─ 取引ライフサイクル
```

既存の`EaController`、`EaConfig`、`StrategyFactory`および`TradeExecutor`は、多時間足、多戦略、CSV、画面表示および利益保護へ依存するため、そのまま流用しません。

## 5. 入力値と固定値

初版のinputは次に限定します。

| input | 既定値 | 内容 |
|---|---:|---|
| `InpLotSize` | `0.01` | 固定ロット。brokerの最小値、最大値、stepへ正規化 |
| `InpMaxInitialStopLossPips` | 未決 | 許可する初期リスク幅。H1研究DBの分布から実装前に決定 |

次は初版の内部固定値とします。

| 項目 | 固定値 |
|---|---:|
| 時間足 | `PERIOD_H1` |
| 戦略 | `MTF_3in3` |
| W1確認 | `H1_W1_CONFIRMATION_OFF` |
| 方向一致 | `H1_DIRECTION_ALIGNMENT_D1_TO_H1` |
| EMA200確認 | `H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED` |
| 最大Spread | 3.0 pips |
| 初期SL余白 | 5.0 pips |
| 許容deviation | 10 points |
| TP | なし |
| DBフォルダ | Common固定 |
| LIVE DB名 | `mstng-h1-ea.sqlite` |
| Tester DB名 | `mstng-h1-ea-tester.sqlite` |
| heartbeat間隔 | 10秒 |
| Lease有効期間 | 60秒 |

Magic Numberは既存の`MagicNumberUtil`を利用して自動生成します。現行`MstngEa`と衝突しない新しいEAコードは実装開始時に割り当てます。

初期化時に、H1以外のチャート、0以下のロット、0以下の最大初期SL幅、ヘッジ口座以外および無効な取引環境を拒否します。

`InpMaxInitialStopLossPips`の既定値は未決事項です。実装着手前にH1研究DBの`risk_pips`分布を確認し、外れ値を除外できる値を決定します。

## 6. イベント処理

### 6.1 初期化

`OnInit()`では次を行います。

1. H1チャートであることを確認する
2. Market Context、Magic Numberおよび分析ハンドルを準備する
3. ポジション取得と注文機能を準備する
4. Commonフォルダの同一コンテキスト用Lockを排他的に取得する
5. 専用SQLiteを開き、接続設定とスキーマを確認する
6. 単一transactionで期限切れRunを処理し、今回Runの登録とLease取得を行う
7. 前回Runと自EAポジションをbroker履歴へ照合する
8. 現在のH1バーを新規バー検出の基準として記録する

起動直後の進行中H1バーではエントリー判定しません。次のH1新規バーから処理を開始します。

DBを利用できない場合も、排他Lockを取得できていれば既存の自EAポジションを保護する制限状態で稼働します。この状態では新規エントリーを停止し、既存ポジションの確認、broker SLおよび決済管理だけを継続します。排他Lockも取得できない場合は初期化を拒否します。

同一接続サーバー、口座、シンボルおよびMagic NumberでLock済み、または有効な別RunのLeaseがある場合、二重起動として初期化を拒否します。期限切れLeaseだけを引き継ぎ、稼働中Runを無条件に`INTERRUPTED`へ変更しません。

### 6.2 毎ティック処理

毎ティックでは次だけを行います。

1. 自EAポジションとpending取引の状態を確認する
2. 未保存の取引結果があればDB再接続と保存を試みる
3. 新しいH1バーでなければ終了する
4. 新しいH1バーならH1新規バー処理を実行する

建値移動、利益戻しおよびZigZagトレイルは行いません。

`OnTimer()`は画面描画には使用せず、排他Lockの有効性確認、実行Leaseのheartbeat更新と、tickがない時間帯のDB再接続確認だけに使用します。注文・分析・決済判定は行いません。

最後に確認できた`lease_expires_at`を更新できないまま期限へ到達した場合、split-brainを防ぐためEAからの注文、SL変更および成行決済を停止します。起動後に一度もDB Leaseを取得できない場合は、Lock取得時刻から60秒を同じ安全期限として使用します。brokerへ設定済みのSLは継続します。

### 6.3 H1新規バー処理

処理順は次のとおりです。

1. brokerポジションを再取得する
2. D1、H4、H1を分析する
3. 保有中なら反対GMMA決済を判定する
4. 決済を開始した場合は、そのH1バーのエントリーを禁止する
5. 未保有なら全エントリー条件を評価する
6. BUY、SELLまたはSKIPの判定をDBへ保存する
7. エントリー成立時は`OPEN_PENDING`をDBへ保存する
8. `OrderCheck()`後に注文を送信する
9. 受付結果をDBと運用ログへ反映する

分析不能、保有中、Spread超過などの場合も、理由コード付きのSKIP判定を1行保存します。

### 6.4 取引イベント

`OnTradeTransaction()`の`TRADE_TRANSACTION_DEAL_ADD`を、実際の約定を保存する正本とします。

- 新規の部分約定は`OPEN_PARTIAL`、全量成立は`OPEN`へ更新する
- SL、EA決済、手動決済および外部決済を同じ経路で検出する
- 決済dealを`POSITION_IDENTIFIER`へ関連付ける
- 取引要求、結果および各dealを取引Eventとして追記する
- ポジション消滅確認後に履歴を集計して`CLOSED`へ更新する
- 同じdeal通知を再受信しても重複保存しない

`OrderSend()`の戻り値だけでポジション成立または決済完了とは判断しません。

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
            └─ CLOSE_PENDING
                 ├─ CLOSE_PARTIAL ──> CLOSE_PENDING
                 ├─ OPEN
                 └─ CLOSED ──> FLAT

不整合検出 ──> RECOVERY_REQUIRED ──> OPEN / CLOSED
```

- `OPEN_PENDING`は注文要求をDBへ保存済みで、ポジション成立を確認していない状態です。
- `OPEN_PARTIAL`は一部約定済みで、残注文または未成立数量がある状態です。
- `CLOSE_PENDING`は決済要求済みで、同じ`POSITION_IDENTIFIER`の消滅を確認していない状態です。
- `CLOSE_PARTIAL`は一部決済後も同じPositionが残っている状態です。
- `RECOVERY_REQUIRED`では新規注文を停止し、brokerとの照合を優先します。

## 8. エントリー判定

### 8.1 分析時間足

H1単独ではなく、親子関係を維持してD1、H4、H1を分析します。Oscillatorハンドルは`OscillatorHandlePool.setTimeframesFromD1To()`で準備します。

Stochastic方向とGMMAは既存H1戦略と同じくshift 0を使用するため、新しく開始したH1バーおよび進行中の上位足を含みます。

### 8.2 BUY条件

次をすべて満たす場合にBUY候補とします。

1. D1、H4、H1の分析に成功する
2. Spreadが3.0 pips以下
3. H1のStochastic多数決方向がBUY
4. H1最新Wave方向が上昇
5. D1、H4、H1のStochastic多数決方向がすべてBUY
6. H1とH4が第1波、第3波、または有効な第5波
7. H1 GMMA trend countが`+2`以上
8. H1 GMMA cross countが`+2`以上
9. H1 EMA200方向がBUY
10. H4 EMA200方向がBUY
11. 同じ市場シグナルを未消費
12. 自EAポジションおよびpending新規注文がない
13. 有効な初期SLを計算できる
14. 初期SL幅が`InpMaxInitialStopLossPips`以下

### 8.3 SELL条件

BUY条件の方向と符号を反転します。

- D1、H4、H1の方向がすべてSELL
- H1最新Wave方向が下降
- H1 GMMA trend countが`-2`以下
- H1 GMMA cross countが`-2`以下
- H1とH4のEMA200方向がSELL

### 8.4 Elliott波動条件

H1とH4はそれぞれ次のいずれかを要求します。

- 第1波
- 第3波
- 第5波かつ、同じ推進Waveの第3波に副次波番号・副次波ラベルがない

第5波は「同じ推進Wave内の数字の第3波に、副次波番号および副次波ラベルが設定されていない」ことだけで判定します。第3波の値幅や時間を使った短さの判定は行いません。最新ZigZagポイントの確定・未確定はエントリー条件に使用しません。

### 8.5 使用しない判定値

初版では次を記録・表示目的の条件にも使用しません。

- W1方向およびW1 EMA200
- D1 EMA200
- H1またはH4のEMA200距離
- H1構造ランク
- 通貨強弱
- ZigZag最新点の確定状態

### 8.6 シグナル識別と消費

シグナルは、H1の2番目に新しいZigZagポイント時刻と売買方向で識別します。市場をまたぐ衝突を防ぐため、DBでは既存Alert DBと同じく、接続サーバー、シンボル、時間足、H1バー時刻、シグナル基準時刻、戦略および方向から`market_signal_key`を生成します。

完全なエントリー条件が成立した時点で、判定と`OPEN_PENDING`を同一DBトランザクションへ保存してシグナルを消費します。brokerが注文を拒否しても同じシグナルを再送しません。DBの一意制約により、EA再起動後も同じシグナルを消費済みとして扱います。

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

### 9.2 成行注文

- 固定ロット
- 成行注文
- broker対応のfilling mode
- 許容deviationは10 points
- 固定TPなし
- 注文コメントはEA名と戦略バージョンを識別できる短い値

`DONE_PARTIAL`または`PLACED`を受け取っても即座に`OPEN`とはせず、`OnTradeTransaction()`とbrokerポジションで成立を確認します。

新規注文が部分約定した場合は、未約定の残注文を取消要求し、同じシグナルで不足数量を再発注しません。残注文が有効な間は`OPEN_PARTIAL`、残注文が終端となりPosition数量が正なら、その実数量を採用して`OPEN`へ移行します。残注文の終端後にPositionがなければ`OPEN_FAILED`とします。

### 9.3 初期ストップロス

H1のシグナル基準ZigZagポイントから5.0 pipsを損失側へ離します。

```text
BUY  : 基準の谷 - 5.0 pips
SELL : 基準の山 + 5.0 pips
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

## 10. ポジション管理範囲

初版は`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`の口座だけを対象とします。ネッティング口座では手動・他EAのdealが同じPositionへ混在し得るため、初期化を拒否します。

管理対象は同一接続サーバー、口座、シンボルおよびMagic Numberのポジションです。ポジションの安定識別には`POSITION_IDENTIFIER`と`DEAL_POSITION_ID`を使用し、変化し得るPosition Ticketだけに依存しません。

初版で正常に扱う自EAポジションは1件です。複数検出時は異常として新規エントリーを停止し、自動で統合・一括決済せず運用ログへ記録します。各ポジションにbroker SLが存在することを確認します。

## 11. 決済仕様

### 11.1 brokerストップロス

初期SLは注文と同時にbrokerへ設定します。EA停止中も有効な最低限の損失制限です。SL約定は`OnTradeTransaction()`から取得し、決済理由`STOP_LOSS`として保存します。

### 11.2 H1反対GMMA決済

新しいH1バーで次を満たす場合、保有ポジションを全量成行決済します。

- BUY保有：H1 GMMA cross countが`-2`以下
- SELL保有：H1 GMMA cross countが`+2`以上

W1、D1・H4方向、EMA200、ElliottおよびSpreadは決済条件に使用しません。

### 11.3 決済確認

通常は決済要求前に`CLOSE_PENDING`と内部決済理由を保存します。DB障害中でも、排他Lockを保持し、最後に確認したLeaseが未失効ならリスク低減を優先して決済を送信し、broker履歴と運用ログから復旧します。注文受付後も同じ`POSITION_IDENTIFIER`が残る限り決済完了としません。

部分決済後は`CLOSE_PARTIAL`として残存数量と有効注文を確認します。有効な決済注文があれば待機し、注文が終端でPositionが残る場合は最短1秒間隔で残存全量の成行決済を再試行します。Positionが消滅するまで同じ内部決済理由を維持し、同じH1バーの再エントリーを禁止します。

決済を開始したH1バーでは、決済が同じバー内で完了しても新規エントリーしません。初版は同一バーのドテンを禁止します。

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
- `h1_ea_decisions`：H1バーごとのBUY、SELLまたはSKIPと条件スナップショット
- `h1_ea_trades`：発注から決済までの取引状態と確定損益
- `h1_ea_trade_events`：取引要求、結果、部分約定、決済および回復履歴

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
既存CLOSE : 排他Lock保持中かつ既知Leaseの安全期限内だけ継続
broker SL : DB・Lease状態にかかわらず継続
```

- 注文前の判定または`OPEN_PENDING`を保存できなければ発注しない
- 保有中の一時的なDB障害では、排他Lockと未失効Leaseを確認できる間だけ反対GMMA決済を継続する
- 保存失敗した取引Eventは同一プロセス内のメモリへ一時保持し、再接続後にFIFOで再保存する
- brokerのposition、orderおよびdealに存在する事実だけを正本として冪等に補完する
- メモリ上限到達時は新規注文を停止し、保存できないEventを運用ログへ明示する
- DB障害中のSKIP判定や内部状態は再起動後に完全復元できるとは扱わない
- 最後に確認したLeaseが失効した後はEAから取引操作せず、broker SLだけを残す
- DBを自動削除または空DBへ置換しない
- Viewerの停止や障害はEA動作へ影響させない

## 13. 再起動時の整合

起動時はDBだけを信用せず、brokerの現在ポジション、注文およびdeal履歴と照合します。

| DB状態 | broker状態 | 動作 |
|---|---|---|
| active取引あり | 同じPositionあり | 不足情報を補完して管理継続 |
| `OPEN_PENDING` | Positionなし | 現在・履歴orderとdealを確認。orderが終端かつdealなしの場合だけ`OPEN_FAILED` |
| `CLOSE_PENDING` | Positionなし | 決済履歴を集計して`CLOSED` |
| active取引あり | Position・履歴なし | `RECOVERY_REQUIRED`、新規注文停止 |
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

LIVEとTesterのデータを同じ物理ファイルへ混在させません。DB名は初版では固定し、inputへ公開しません。`MQLInfoInteger(MQL_OPTIMIZATION)`がtrueの場合は、DB必須の状態遷移を省略せず初期化を拒否します。将来最適化へ対応する場合は、同じRepository契約を持つ別実装を設計します。

「始値のみ」で下位足を参照しません。H1、H4、D1だけを使用しますが、shift 0の判定結果はTesterのモデルとtick生成方法に依存します。

## 16. Viewer

現行Viewerの`--database`はAlert/Observation DB用のまま変更しません。EA取引表示は初版の対象外です。

Viewer連携の起動引数と画面構成は、EA初版の実装後に別途設計します。Alert DBとの`market_signal_key`一致は候補抽出にだけ使用でき、Runをまたぐ一意キーとは扱いません。

## 17. 異常時の基本方針

| 異常 | 動作 |
|---|---|
| 分析データ取得失敗 | SKIP保存、新規注文しない |
| DB接続・schema失敗 | 新規注文停止、既存ポジション管理継続 |
| Spread取得不能 | 新規注文しない |
| 初期SL不正 | 新規注文しない |
| 初期SL最大幅超過 | 新規注文しない |
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
2. 起動中のH1バーでは判定せず、次のH1から開始する
3. BUY、SELLおよび各主要SKIP理由をDBへ保存できる
4. 現行H1判定と同じ条件でEntry可否が一致する
5. H1とH4の条件付き第5波を正しく判定する
6. 不正、設定不能または最大幅を超えるSLでは注文しない
7. 同じシグナルを再起動後も再注文しない
8. `OrderCheck()`、発注、部分約定および決済を状態遷移とEvent履歴で追跡できる
9. 反対GMMAで全量決済し、同じH1バーで再エントリーしない
10. SL、EA決済および外部決済を`OnTradeTransaction()`から保存できる
11. DB障害時に新規注文を停止し、排他LockとLease安全期限内だけ既存ポジションの決済管理を継続する
12. EA再起動後にDBとbrokerポジションを整合できる
13. LIVEとTesterのDBが分離される
14. 対象EAと新規DB SmokeTestがMetaEditorでコンパイル成功する
15. 同一コンテキストの二重起動をLeaseで拒否できる
16. ヘッジ口座だけで動作し、ネッティング口座を拒否する
17. 部分Entryの残注文を取消し、不足数量を再発注しない
18. 部分決済後の残存数量を最短1秒間隔で再決済できる
19. Strategy Tester最適化では初期化を拒否する

## 19. 実装方針と参照

### 19.1 直接再利用する実装

| 領域 | 実装 |
|---|---|
| 市場コンテキスト | [MarketContext.mqh](../../Include/Mstng/Common/MarketContext.mqh) |
| 分析ハンドル | [OscillatorHandlePool.mqh](../../Include/Mstng/Oscillator/OscillatorHandlePool.mqh) |
| 親子Elliott分析 | [ElliotAll.mqh](../../Include/Mstng/Elliot/ElliotAll.mqh) |
| H1戦略Adapter | [ExpertAdvisorMtf3In3Adapter.mqh](../../Include/MstngEa/Strategy/ExpertAdvisorMtf3In3Adapter.mqh) |
| H1判定 | [ExpertAdvisorMtf3In3H1.mqh](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3H1.mqh) |
| H1・H4波動判定 | [H1EntryWaveDecision.mqh](../../Include/Mstng/ExpertAdvisor/H1EntryWaveDecision.mqh) |
| H1・H4 EMA200 | [H1Ema200ConfirmationDecision.mqh](../../Include/Mstng/ExpertAdvisor/H1Ema200ConfirmationDecision.mqh) |
| H1新規バー | [NewBarDetector.mqh](../../Include/MstngEa/Market/NewBarDetector.mqh) |
| ポジション取得 | [PositionService.mqh](../../Include/MstngEa/Trade/PositionService.mqh) |
| Magic Number | [MagicNumberUtil.mqh](../../Include/MstngEa/Trade/MagicNumberUtil.mqh) |
| SQLite接続 | [SqliteDatabase.mqh](../../Include/Mstng/Database/SqliteDatabase.mqh) |

### 19.2 新設する主な責務

- H1専用Controller
- H1専用Config
- H1専用Trade Executor
- H1 EA Database Context
- Run、Decision、Trade、Trade EventのEntity、DAOおよびPersistence Service
- H1 EA Database SmokeTest
- 再起動整合処理

既存`MstngEa`の詳細は[MstngEa仕様書](MstngEa.md)を参照してください。

## 20. 実装前の未決事項

次の3点は仕様本文へ仮称または未決として記載しており、実装開始前に確定します。

1. EAの正式名称と実装ファイル名
2. 現行`MstngEa`と衝突しないMagic Number用EAコード
3. H1研究DBの初期リスク分布から決める`InpMaxInitialStopLossPips`の既定値
