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
| 設計バージョン | 0.3 |
| 最終更新日 | 2026-09-03 |

本書は、`MstngEa`を基礎として機能をH1運用に限定した新EAの初版仕様を定義します。現行の`MstngEa`を変更する設計ではなく、必要な判定クラスだけを再利用して、制御、発注および永続化を新しく構成します。

SQLiteの物理構成、列および制約は[MstngH1Eaデータベース設計書](../Database/MstngH1EaDatabase.md)を参照してください。

## 2. 目的

初版の目的は、H1の`MTF_3in3`条件だけを使用して、次を安全かつ再現可能に実行することです。

- H1新規バーごとのエントリー判定
- 固定ロットの成行注文
- 必須のbrokerストップロス
- 確定H1 ZigZagによるSLトレイル
- トレイルSL反映前の候補跨ぎによる全量決済
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
- 確定H1 ZigZagによるSLトレイル
- トレイル候補のSQLite永続化と再起動復旧
- トレイルSL反映前の候補跨ぎによる全量決済
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
- 反対GMMAによる戦略決済
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
  │    ├─ エントリー・H1 ZigZagトレイル判定
  │    ├─ pending保護SL再試行
  │    ├─ 候補跨ぎ決済
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
  │    ├─ SLTP変更
  │    └─ pending注文・SL確認
  └─ H1 EA SQLite
       ├─ Run
       ├─ H1判定
       ├─ 取引ライフサイクル
       └─ トレイル候補・SL変更履歴
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
| ZigZag SL余白（初期・トレイル） | 10.0 pips |
| 許容deviation | 10 points |
| TP | なし |
| DBフォルダ | Common固定 |
| LIVE DB名 | `mstng-h1-ea.sqlite` |
| Tester DB名 | `mstng-h1-ea-tester.sqlite` |
| heartbeat間隔 | 10秒 |
| Lease有効期間 | 60秒 |

Magic Numberは既存の`MagicNumberUtil`を利用して自動生成します。現行`MstngEa`と衝突しない新しいEAコードは実装開始時に割り当てます。

初期化時に、H1以外のチャート、0以下のロット、0以下の最大初期SL幅、ヘッジ口座以外、pip size・tick sizeを取得できないシンボルおよび無効な取引環境を拒否します。

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
7. 前回Run、active取引およびpending保護SL候補をbrokerへ照合する
8. broker SLへ未反映の保護SL候補があれば種別とともに復元して再試行対象にする
9. 現在のH1バーを新規バー検出の基準として記録する

起動直後の進行中H1バーではエントリー判定しません。次のH1新規バーから処理を開始します。

DBを利用できない場合も、排他Lockを取得できていれば既存の自EAポジションを保護する制限状態で稼働します。起動時からDBを利用できない場合はpending候補を復元できないため、新規エントリーを停止してbroker SLだけを維持します。起動後にDB接続を失った場合は、既にメモリへ復元または登録済みのpending保護SL候補と候補跨ぎ決済だけを安全期限内で継続できます。DBにない候補を価格から推測しません。排他Lockも取得できない場合は初期化を拒否します。

同一接続サーバー、口座、シンボルおよびMagic NumberでLock済み、または有効な別RunのLeaseがある場合、二重起動として初期化を拒否します。期限切れLeaseだけを引き継ぎ、稼働中Runを無条件に`INTERRUPTED`へ変更しません。

### 6.2 毎ティック処理

毎ティックでは次だけを行います。

1. 自EAポジションとpending取引の状態を確認する
2. pending保護SL候補があれば、broker SL反映、候補跨ぎおよび再試行時刻を確認する
3. 必要なSL変更または候補跨ぎ決済を最短1秒間隔で再試行する
4. 未保存の取引結果があればDB再接続と保存を試みる
5. 候補跨ぎ決済を開始した、または`CLOSE_PENDING`・`CLOSE_PARTIAL`なら、そのtickの新規バー分析とEntry処理を行わず終了する
6. 新しいH1バーでなければ終了する
7. 新しいH1バーならH1新規バー処理を実行する

建値移動、利益戻しおよび反対GMMAによる成行決済は行いません。

`OnTimer()`は画面描画には使用せず、排他Lockの有効性確認、実行Leaseのheartbeat更新と、tickがない時間帯のDB再接続確認だけに使用します。注文、SL変更、分析および決済判定は行いません。

最後に確認できた`lease_expires_at`を更新できないまま期限へ到達した場合、split-brainを防ぐためEAからの注文、SL変更および成行決済を停止します。起動後に一度もDB Leaseを取得できない場合は最初からEAの取引操作を禁止し、Lock取得時刻から60秒はDB再接続と初期照合を試す上限にだけ使用します。この60秒はbroker送信権限を与えません。brokerへ設定済みのSLは継続します。

### 6.3 H1新規バー処理

処理順は次のとおりです。

1. brokerポジションを再取得する
2. D1、H4、H1を分析する
3. Tradeが`OPEN`かつ`INITIAL_RESTORE`中でなければ、確定H1 ZigZagによるトレイル候補を評価する。`OPEN_PARTIAL`では初期SLと残注文の終端確認を優先する
4. 分析失敗を含むトレイル評価、採用候補および基準点をDBへ保存する
5. 採用候補をpendingへ登録し、broker SLへの反映を試みる
6. 候補跨ぎによる決済を開始した場合は、そのH1バーのエントリーを禁止する
7. 未保有なら全エントリー条件を評価する
8. BUY、SELLまたはSKIPの判定をDBへ保存する
9. エントリー成立時は`OPEN_PENDING`をDBへ保存する
10. `OrderCheck()`後に注文を送信する
11. 受付結果をDBと運用ログへ反映する

`INITIAL_RESTORE`がpendingの間は新しいトレイル候補を評価せず、`INITIAL_STOP_LOSS_RESTORE_PENDING`として見送ります。初期SLの復元または候補跨ぎ決済を先に完了します。

分析不能、保有中、Spread超過などの場合も、Entry判定として理由コード付きのSKIPを1行保存します。保有中のトレイル評価はTrade Eventへ別に保存し、分析失敗、Wave不足またはポイント不足も`WAVE_UNAVAILABLE`、`POINTS_UNAVAILABLE`などの見送り理由として記録します。

### 6.4 取引イベント

`OnTradeTransaction()`の`TRADE_TRANSACTION_DEAL_ADD`を、実際の約定を保存する正本とします。

- 新規の部分約定は`OPEN_PARTIAL`、全量成立は`OPEN`へ更新する
- SL、EA決済、手動決済および外部決済を同じ経路で検出する
- 決済dealを`POSITION_IDENTIFIER`へ関連付ける
- 取引要求、SL変更要求・結果および各dealを取引Eventとして追記する
- ポジション消滅確認後に履歴を集計して`CLOSED`へ更新する
- 同じdeal通知を再受信しても重複保存しない

`OrderSend()`の戻り値だけでポジション成立、SL変更反映または決済完了とは判断しません。SL変更後は対象Positionを読み直し、候補以上に保護されたことを確認します。

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
            ├─ [TRAIL_MONITORING / TRAIL_PENDING]
            ├─ broker SL約定 ──> CLOSED ──> FLAT
            └─ 候補跨ぎ ──> CLOSE_PENDING
                 ├─ CLOSE_PARTIAL ──> CLOSE_PENDING
                 ├─ OPEN
                 └─ CLOSED ──> FLAT

不整合検出 ──> RECOVERY_REQUIRED ──> OPEN / CLOSED
```

- `OPEN_PENDING`は注文要求をDBへ保存済みで、ポジション成立を確認していない状態です。
- `OPEN_PARTIAL`は一部約定済みで、残注文または未成立数量がある状態です。
- `[TRAIL_MONITORING / TRAIL_PENDING]`はDBの取引`status`ではなく、`OPEN`中の内部管理状態です。
- `TRAIL_PENDING`は候補をDBへ保存済みで、broker SLへの反映を確認していない状態です。SL変更だけでは`CLOSE_PENDING`へ移行しません。
- `CLOSE_PENDING`は決済要求済みで、同じ`POSITION_IDENTIFIER`の消滅を確認していない状態です。
- `CLOSE_PARTIAL`は一部決済後も同じPositionが残っている状態です。
- `RECOVERY_REQUIRED`では新規注文、SL変更および成行決済を停止し、brokerとの照合だけを行います。brokerへ設定済みのSLは継続します。照合で状態を一意に確定し、必要なら初期SL・適用済みトレイルSLから構造上有効なpendingを再構成して、Tradeを`OPEN`へ戻したtransactionのcommit後にだけ送信を再開します。

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

第5波は「同じ推進Wave内の数字の第3波に、副次波番号および副次波ラベルが設定されていない」ことだけで判定します。第3波の値幅や時間を使った短さの判定は行いません。最新ZigZagポイントの確定・未確定はエントリー条件に使用しません。保有後のH1 ZigZagトレイルでは、別途11.2の確定ポイント条件を使用します。

### 8.5 使用しない判定値

初版では次をエントリー条件に使用しません。H1 ZigZagトレイルに必要なポイント情報はこの一覧の対象外です。

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

H1のシグナル基準ZigZagポイントから10.0 pipsを損失側へ離します。

```text
BUY  : 基準の谷 - 10.0 pips
SELL : 基準の山 + 10.0 pips
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

初期SLとH1 ZigZagトレイルは、どちらもZigZag基準点から損失側へ10.0 pips離します。初版では10.0 pipsを内部固定値とし、inputでは変更できません。トレイル開始後も、有効なbroker SLが存在することを必須とします。

## 10. ポジション管理範囲

初版は`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`の口座だけを対象とします。ネッティング口座では手動・他EAのdealが同じPositionへ混在し得るため、初期化を拒否します。

管理対象は同一接続サーバー、口座、シンボルおよびMagic Numberのポジションです。ポジションの安定識別には`POSITION_IDENTIFIER`と`DEAL_POSITION_ID`を使用し、変化し得るPosition Ticketだけに依存しません。

初版で正常に扱う自EAポジションは1件です。複数検出時は異常として新規エントリーを停止し、自動で統合・一括決済せず運用ログへ記録します。各ポジションにbroker SLが存在することを確認します。

保有中はpending保護SL候補を最大1件管理します。種別は、新しいH1 ZigZag候補の`TRAIL_CANDIDATE`、初期SL復元の`INITIAL_RESTORE`、最後に適用済みのトレイルSL復元の`TRAIL_RESTORE`です。`INITIAL_RESTORE`中は新しいトレイル候補を評価しません。それ以外は、新しい候補が現在broker SLより保護側であり、かつpendingがある場合はそのpendingよりも1tick以上保護側の場合だけ置き換え、SLを損失側へ戻しません。

## 11. 決済仕様

### 11.1 brokerストップロス

初期SLは注文と同時にbrokerへ設定します。EA停止中も有効な最低限の損失制限です。Position成立後は、確定H1 ZigZagの進行に応じて同じbroker SLを保護側へ更新します。初期SLまたは更新後SLの約定は`OnTradeTransaction()`から取得します。

### 11.2 H1 ZigZagトレイル候補

新しいH1バーでTradeが`OPEN`の場合、H1 Elliott分析の最新Waveから最新点と1つ前の点を取得します。最新点は1つ前の点が確定したことの確認にだけ使用し、実際のSL基準には1つ前の点を使用します。`OPEN_PARTIAL`ではトレイルを開始しません。

次をすべて満たす場合だけ候補を作成します。

- Position開始時刻、建値および現在SLが有効
- 固定余白10.0 pips、pip sizeおよびtick sizeが有効
- H1の最新Waveを取得できる
- 最新点と1つ前の点の価格および時刻が有効
- 両ポイントが`isAddedPoint = false`
- 両ポイントが確定H1上にあり、`barIndex >= 1`
- 1つ前の点が最新点より古い
- 1つ前の点がPosition開始時刻より後
- BUYは「1つ前が谷、最新が山」
- SELLは「1つ前が山、最新が谷」
- 丸め後の候補SLが0より大きい

候補SLは次のとおりです。

```text
BUY  : 1つ前の谷 - 10.0 pips
SELL : 1つ前の山 + 10.0 pips
```

BUYはbrokerの最小価格刻みへ下方向、SELLは上方向へ丸めます。候補が建値より損失側に残っていても、現在SLより1tick以上保護側なら採用します。`INITIAL_RESTORE`中はこの評価へ進みません。それ以外のpendingがある場合は、その候補よりも1tick以上保護側であることも要求します。条件を満たさない候補は見送り、SLを損失側へ戻しません。

反対GMMA、W1、D1・H4方向、EMA200、ElliottラベルおよびSpreadは決済条件に使用しません。GMMAはエントリー条件にだけ使用します。

### 11.3 pending保護SL候補とSL変更

この節の採用フローと手順1は、新しい`TRAIL_CANDIDATE`だけを対象とします。`TRAIL_EVALUATION`自体はH1バーごとの採用または見送りを保存するため、`INITIAL_RESTORE`中も`INITIAL_STOP_LOSS_RESTORE_PENDING`の見送りEventを作成できます。採用候補は、基準点、確認点および評価H1バーとともにDBへ保存してからSL変更を開始します。`INITIAL_RESTORE`と`TRAIL_RESTORE`の登録は11.4のbroker整合処理で、Recovery EventとTrade更新を同一transactionへ保存してから、手順2以降と同じ再試行処理へ渡します。復元登録そのものを`TRAIL_EVALUATION`として保存しません。

1. pending候補とトレイル評価Eventをtransactionで保存する
2. 現在のPosition Ticket、現在SL、BidまたはAskを再取得する
3. broker SLが候補以上に保護済みなら、実SLと設定元を保存し、SL変更を送信せずpendingを解除する
4. BUYのBidまたはSELLのAskが候補を跨いでいれば、候補跨ぎ決済へ移行する
5. Stops/Freeze距離を満たさなければ、送信せずpendingを維持する
6. 有効Leaseの確認とSL変更要求Eventを同一transactionで保存する
7. 対象Position Ticketを明示してSLTP変更を送信する
8. Positionを再取得し、候補以上に保護されたことを確認する
9. broker再確認結果に応じてSL変更結果とTrade状態を保存する

候補が`SYMBOL_TRADE_STOPS_LEVEL`と`SYMBOL_TRADE_FREEZE_LEVEL`の大きい方に1tickを加えた距離を満たさない場合、またはSL変更に失敗した場合はpendingを維持します。毎ティック確認し、実際の再送は最短1秒間隔とします。pendingが`TRAIL_CANDIDATE`または`TRAIL_RESTORE`の場合だけ、より保護的な新規トレイル候補で置き換えられます。`INITIAL_RESTORE`は置き換えません。

この節の`TRAIL_CANDIDATE`について、SL反映前にBUYのBidが候補以下、またはSELLのAskが候補以上になった場合、SLを過去価格へ設定できないため、`H1_ZIGZAG_TRAIL_CROSSED`で全量成行決済を開始します。復元候補のcross理由は11.4に従います。Spread超過はSL変更およびこのリスク低減決済を妨げません。

broker SLが候補以上に保護されたかは、BUYでは`broker SL >= 候補 - 0.5 tick`、SELLでは`broker SL <= 候補 + 0.5 tick`で確認します。より保護的なSLで候補を満たした場合も、broker実SLを保存してpendingを解除しますが、自EAのSL変更要求と対応付けられなければ`H1_ZIGZAG_TRAIL`とは記録しません。broker transactionや取得済みの変更元情報から手動・他EAを積極的に確認できた場合だけ`EXTERNAL`、自EAの未保存actionを含め由来を証明できない場合は`UNKNOWN`とします。

自EAの変更actionとbroker SLが一致し、pending種別が`TRAIL_CANDIDATE`または`TRAIL_RESTORE`の場合だけ適用済みトレイル候補を更新します。`INITIAL_RESTORE`の成功は設定元を`INITIAL_STOP_LOSS`へ戻します。より保護的な外部・由来不明SLの場合は適用済み候補を変更せずpendingだけを解除します。変更失敗または未反映を確認できた場合は、「SLあり」と「SLなし」を区別できるbroker確認結果をResult Eventへ保存してpendingを維持します。broker Positionまたは実SLの有無を取得できず結果を断定できない場合はResult Eventを作らず、未完了actionを保持して`RECOVERY_REQUIRED`へ移行します。

通常経路はDBへの要求Event commit後にSL変更または成行決済を送信します。DB障害中だけ、排他Lockと未失効Leaseを条件に、意図とEventをメモリキューおよび運用ログへ記録してリスク低減操作を許可します。未保存情報は再起動で失われる可能性があります。

### 11.4 broker SLとの整合

broker SLがEAの保存済み保護水準より保護側にある場合は、手動または外部設定を尊重し、EAから緩めません。broker SLが削除または緩和された場合は、未完了SL actionを先に照合し、初期SL、最後に自EAが適用したトレイルSLおよび有効なpending候補のうち最も保護側の水準を復元対象とします。初期SLなら`INITIAL_RESTORE`、適用済みトレイルSLなら`TRAIL_RESTORE`、既存pending自身ならその種別のまま、Controllerのbroker整合処理からpendingへ設定します。初期SL復元には架空のZigZag情報を設定しません。新しいZigZag候補として再判定せず、復元前に価格が水準を跨いでいれば`INITIAL_RESTORE`は`INITIAL_STOP_LOSS_CROSSED`、トレイル由来の2種は`H1_ZIGZAG_TRAIL_CROSSED`で全量成行決済へ移行します。

broker SLの価格だけから基準ZigZag点や設定元を推測しません。`EXTERNAL`はbroker transactionまたは保存済み変更元情報から手動・他EAを積極的に確認できた場合だけ使用し、自EA actionとの不一致や要求履歴の欠落だけでは外部と断定しません。由来を証明できない場合は`UNKNOWN`として保存します。H1分析に失敗した場合は新しい候補を作成せず、既存のbroker SLと復元済みpending候補を維持します。

### 11.5 決済確認と理由

broker SL約定では明示的な成行決済要求がないため、Position消滅とdealを確認した後、`OPEN`から直接`CLOSED`へ更新できます。候補跨ぎ成行決済では、Lease所有確認、`CLOSE_PENDING`、pending種別に対応するcross理由、決済要求Eventおよびpending候補の解除を同一transactionで保存してから送信します。候補情報は決済要求Eventへ残します。`CLOSE_PENDING`または`CLOSE_PARTIAL`ではトレイル評価とSL変更を行いません。

候補跨ぎ成行決済が部分約定となった場合は`CLOSE_PARTIAL`として残存数量と有効注文を確認します。有効な決済注文がなければ、最短1秒間隔で残存全量の成行決済を再試行します。Positionが消滅するまで同じ内部決済理由を維持します。

決済理由はEA側の分類とbroker事実を分けて保存します。

| 状況 | EA側の決済分類 | broker理由 |
|---|---|---|
| 初期SL約定 | `INITIAL_STOP_LOSS` | `SL` |
| 初期SL復元前の水準跨ぎ | `INITIAL_STOP_LOSS_CROSSED` | 通常`EXPERT` |
| H1 ZigZagトレイルSL約定 | `H1_ZIGZAG_TRAIL` | `SL` |
| 外部設定SL約定 | `EXTERNAL_STOP_LOSS` | `SL` |
| 由来不明SL約定 | `UNKNOWN_STOP_LOSS` | `SL` |
| 候補跨ぎ成行決済 | `H1_ZIGZAG_TRAIL_CROSSED` | 通常`EXPERT` |

候補跨ぎ決済を開始したH1バーでは、同じバー内で完了しても新規エントリーしません。初版は同一バーのドテンを禁止します。

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
- `h1_ea_trades`：発注から決済までの取引状態、現在SL、pending保護SL候補および確定損益
- `h1_ea_trade_events`：取引要求、トレイル評価、SL変更、部分約定、決済および回復履歴

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
SL変更・既存CLOSE : 排他Lock保持中かつ既知Leaseの安全期限内だけ継続
broker SL : DB・Lease状態にかかわらず継続
```

- 注文前の判定または`OPEN_PENDING`を保存できなければ発注しない
- 保有中の一時的なDB障害では、排他Lockと未失効Leaseを確認できる間だけH1 ZigZag SL変更と候補跨ぎ決済を継続する
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
| `CLOSE_PENDING`・`CLOSE_PARTIAL` | Positionなし | 決済履歴を集計して`CLOSED` |
| `CLOSE_PENDING`・`CLOSE_PARTIAL` | 同じPositionあり | 有効な決済注文を確認し、終端済みで残Positionがあれば再決済 |
| `OPEN`またはpendingあり | Positionなし、決済dealあり | 決済履歴を集計し、pendingを解除して`CLOSED` |
| `OPEN`＋pending保護SLあり | 同じPosition、broker SLが候補以上に保護側 | 実SLを保存してpending解除。自EA要求と一致するトレイル種別だけ適用済みへ更新し、外部・不明なら`EXTERNAL`または`UNKNOWN` |
| `OPEN`＋pending保護SLあり | 同じPosition、broker SLが候補未達 | 種別を含めてpendingを復元し、Lease確認後に再試行 |
| `OPEN`＋pending保護SLあり | 同じPosition、broker SLが削除・緩和 | 初期SL・適用済みSL・pendingの最も保護側を適切な復元種別で保持し、価格通過済みなら種別対応の理由で決済開始 |
| `OPEN`＋pending保護SLあり | 同じPosition、価格が候補を通過済み | 初期SL復元は`INITIAL_STOP_LOSS_CROSSED`、トレイル由来は`H1_ZIGZAG_TRAIL_CROSSED`で決済開始 |
| pending保護SLあり | Position識別子・方向が不一致 | stale候補を送信せず、断定不能ならpendingを保持して`RECOVERY_REQUIRED` |
| pending保護SLが構造不正 | 種別と必須項目の組合せ不正、価格単位不正または複数候補 | 生の値をRecovery Eventへ隔離し、構造化pendingを全NULLにして`RECOVERY_REQUIRED`。broker照合以外の送信を停止 |
| active取引あり | Position・履歴なし | `RECOVERY_REQUIRED`、broker照合以外の送信を停止 |
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
- H1トレイル評価、基準点、候補SLおよび見送り理由
- Stops/Freeze待ち、SL変更要求・結果および候補跨ぎ決済
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

「始値のみ」で下位足を参照しません。H1、H4、D1だけを使用しますが、shift 0の判定結果はTesterのモデルとtick生成方法に依存します。pending保護SLの反映可否、候補跨ぎおよび最短1秒の再試行は生成tickに依存するため、「始値のみ」と実tickでは決済価格や決済時刻が異なる可能性があります。

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
| H1 ZigZag点取得不能 | 新しいトレイル候補を作成せず、既存broker SLを維持 |
| トレイル候補が非改善 | 見送り理由を保存し、現在SLとpendingを維持 |
| Stops/Freeze距離不足 | pendingを維持し、最短1秒間隔で再試行 |
| SL変更拒否・受付不明 | broker SLを再取得し、未反映ならpendingを維持 |
| トレイル候補を価格が通過 | `H1_ZIGZAG_TRAIL_CROSSED`で全量成行決済 |
| 初期SL復元前に価格が通過 | `INITIAL_STOP_LOSS_CROSSED`で全量成行決済 |
| 有効pendingのbroker照合不能 | pendingと未完了actionを保持して`RECOVERY_REQUIRED`、broker SLを維持 |
| pendingの構造不正 | 生の値をRecovery Eventへ隔離し、構造化pendingを解除して`RECOVERY_REQUIRED` |
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
9. 確定H1 ZigZagの谷・山からBUY・SELLのトレイル候補を正しく計算できる
10. Wave不足、非H1 Wave、無効な価格・時刻・価格単位、0以下候補、補完点、形成中足、Entry前pivotおよび方向不一致を見送れる
11. トレイルSLを現在SLより、かつpendingがある場合はpendingより1tick以上保護側へだけ更新し、損失側へ戻さない
12. Stops/Freeze距離不足またはSL変更失敗をpendingとして保持し、最短1秒間隔で再試行できる
13. SL反映前の候補跨ぎで全量決済し、同じH1バーで再エントリーしない
14. pending候補を再起動後にbroker SLと照合し、適用済みまたは再試行へ復旧できる
15. 初期SL、初期SL復元前の跨ぎ、H1 ZigZagトレイルSLおよびトレイル候補跨ぎをbroker理由と分けて保存できる
16. SL変更、SL約定、EA決済および外部決済をEvent履歴から追跡できる
17. DB障害時に新規注文を停止し、排他LockとLease安全期限内だけ既存ポジションのSL変更・決済管理を継続する
18. EA再起動後にDBとbrokerポジションを整合できる
19. LIVEとTesterのDBが分離される
20. 対象EAと新規DB SmokeTestがMetaEditorでコンパイル成功する
21. 同一コンテキストの二重起動をLeaseで拒否できる
22. ヘッジ口座だけで動作し、ネッティング口座を拒否する
23. 部分Entryの残注文を取消し、不足数量を再発注しない
24. 候補跨ぎの部分決済後、残存数量を最短1秒間隔で再決済できる
25. Strategy Tester最適化では初期化を拒否する
26. 反対GMMA条件だけでは保有ポジションを決済しない
27. broker SLが候補以上に保護済みなら実SLと設定元を保存し、SL変更を送信せずpendingを解除できる
28. より保護的なSLを緩めず、手動・他EAを積極的に確認できた場合だけ`EXTERNAL`、由来を証明できない場合は`UNKNOWN`とし、要求履歴なしに`H1_ZIGZAG_TRAIL`と誤分類しない
29. broker SLの削除・緩和時に、初期SL・適用済みトレイルSL・有効pendingの最も保護側を適切な種別で復元できる
30. DB正常時のcommit先行経路と、Lock・Lease安全期限内だけ許可するDB障害時の制限経路を検証できる
31. broker SL約定で`OPEN`から`CLOSED`へ更新できる
32. 再起動時にPosition消滅、識別子不一致および決済途中の残Positionを安全に整合できる
33. pending候補跨ぎ決済を開始したtickでは新規バー分析とEntry処理へ進まない
34. 初期SL復元ではZigZag情報を作らず、トレイル由来pendingと区別して保存・復旧できる
35. broker実SLを取得できないSL変更actionでは結果を断定せず、pendingとactionを保持して`RECOVERY_REQUIRED`へ移行できる
36. `RECOVERY_REQUIRED`中はbroker照合以外の新しい注文、SL変更および成行決済を送信しない
37. `INITIAL_RESTORE`がpendingの間は新しいトレイル評価を見送り、初期SL復元または跨ぎ決済を優先する
38. 構造不正なpendingの生データをRecovery Eventへ隔離し、CHECK制約を満たす状態で`RECOVERY_REQUIRED`へ移行できる
39. SL変更後に「SLなし」を正常取得した場合と、broker取得不能を区別して保存・復旧できる
40. 初期SLとH1 ZigZagトレイル候補を、BUYは基準の谷から10.0 pips下、SELLは基準の山から10.0 pips上へ計算できる

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
| H1 ZigZagトレイル判定 | [H1ZigZagTrailDecision.mqh](../../Include/MstngEa/Strategy/H1ZigZagTrailDecision.mqh) |
| H1新規バー | [NewBarDetector.mqh](../../Include/MstngEa/Market/NewBarDetector.mqh) |
| ポジション取得 | [PositionService.mqh](../../Include/MstngEa/Trade/PositionService.mqh) |
| Magic Number | [MagicNumberUtil.mqh](../../Include/MstngEa/Trade/MagicNumberUtil.mqh) |
| SQLite接続 | [SqliteDatabase.mqh](../../Include/Mstng/Database/SqliteDatabase.mqh) |

### 19.2 新設する主な責務

- H1専用Controller
- H1専用Config
- H1専用Trade Executor
- pending保護SL候補の種別付き永続化・復旧
- SL変更と候補跨ぎ決済の制御
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
