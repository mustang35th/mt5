# MstngM15Ea

## 対象と構成

`Experts/MstngM15Ea.mq5` はM15チャートで動作する単一通貨EAです。既存の `ExpertAdvisorMtf3In3M15` の判定を使い、発注・broker照合・SL保護・取引状態復元を `EaTradeExecutor`、初期SLを `EaInitialStopLossDecision`、判定回数を `EaEntryState` へ接続します。

H1・M15 EA専用の共通処理は `Include/MstngEaCommon/Runtime` に配置します。インジケーターでも使う分析・判定は `Include/Mstng`、M15固有の設定・Controller・保存処理は `Include/MstngM15Ea` に置き、旧EA専用の `Include/MstngEa` とは分けます。

H1版と同様にhedging口座を必要とし、最適化は受け付けません。H1 EAの入力・保存形式・売買条件は変更しません。M15 All版やViewerのM15取引表示は今回の対象に含みません。

## 入力と初期値

| 入力 | 初期値 | 意味 |
|---|---:|---|
| `InpLotSize` | 0.01 | 固定ロット。brokerの最小・最大・stepへ正規化 |
| `InpMaxInitialStopLossPips` | 100.0 | 許容する初期SL幅。正値・小数1桁が必要 |
| `InpDirectionCorrectionEnabled` | true | D1・H4・H1のうち逆方向が1足の場合だけ補正 |
| `InpH4MaxFibonacciExpansionPercent` | 161.8 | M15判定で使うH4のFE上限。0は無効 |
| `InpH1MaxFibonacciExpansionPercent` | 161.8 | M15判定で使うH1のFE上限。0は無効 |
| `InpTesterTradeStartTime` | 2026.01.01 00:00 | Testerの売買開始日時。0は制限なし、LIVEでは無効 |

補正・FE上限の初期値は通常版 `ZigZagElliot.mq5` のM15初期設定に合わせています。初期SLとトレイルの余白10pips、最大Spread 5pips、初回シグナルだけのEntryは固定です。

## 判定と保護

- 分析範囲はMN1→W1→D1→H4→H1→M15。EAからメール・CSV・矢印描画は行いません。通貨強弱によるEntry制限は無効です。
- 既存M15判定の方向一致、D1/H4/H1/M15 EMA200、H4/H1/M15波動、M15 GMMA、最新ZigZag確定、H4/H1 FE制限をそのまま使用します。H1 GMMAを追加条件にはしません。
- 元のM15第2ポイント時刻と方向で回数を管理します。方向補正後の採用M15第2ポイントを初期SLへ使い、回数キーとSL基準点を分離します。元分析・採用分析・補正足・FEなどは判定の監査文字列へ保存します。
- LIVEは開始1秒後、以後30秒ごとに判定を試行します。TesterはTick起点です。各M15バーで最初の分析成功後の判定だけを確定します。Judge条件待ちでは回数を増やさず、次バーで再評価します。分析不能、分析中のバー変更・気配失効は確定前に戻ります。
- 初回成立後の保有制限・初期SL・DB障害によるSKIPも消費回数として記録します。Decision・Trade・ENTRY_REQUESTを同じtransactionで保存し、成功した場合だけ共通Executorへ送信を依頼します。保存失敗後の監査再保存を遅延発注へ変換しません。
- TickではDB保守→broker照合→pending SL保護→新M15バーのトレイル→Tester Entryの順に処理します。トレイルは通常のM15分析の確定スイングを使用し、Entry補正・回数とは独立しています。
- Tester開始前も保護とLease更新を継続し、Entry側は履歴準備だけを行います。履歴・ハンドル準備はM15より下へ降りません。
- 終了時は未保存監査と約定を確認してRunを終了します。保有ポジションとbrokerへ設定済みのSLは残します。

## 保存と再起動

| 項目 | M15の識別子 |
|---|---|
| LIVE DB | Common Filesの `mstng-m15-ea.sqlite` |
| Tester DB | Common Filesの `mstng-m15-ea-tester.sqlite` |
| DBテーブル | `m15_ea_runs`・`m15_ea_decisions`・`m15_ea_trades`・`m15_ea_trade_events` |
| 物理schema | v1、Runの時間足は15固定 |
| Magic | EAコード13＋シンボル＋M15＋MTF_3in3 |
| 排他ファイル | `MstngM15Ea/Locks` |
| 運用ログ | `MstngM15Ea/Logs` |
| 復元context | `M15_EA_CONTEXT_V1`。LIVEは口座・通貨・Magicごと、TesterはRunごと |

M15保存サービスが `IEaTradeStore` を実装し、共通のTrade/Event型を直接保存します。H1 DBには接続せず、既存の異なるschema・索引欠落・未知versionは変更せず拒否します。RunのLease、要求UID、決済後の遅延約定監査、保存キューの再試行はH1で使用している整合性ルールを維持します。

再起動時は消費回数・当該M15バーの確定判定・未完了取引・pending SL・決済意図を復元します。同バーの再入場禁止は900秒単位で復元します。設定や保存情報の準備だけでは送信を許可せず、排他・Lease・broker照合と送信直前確認を必要とします。

## 検証方法

専用のMQL SmokeTestで、設定、既存戦略との一致、H1/M15トレイル、履歴準備、原子的保存・復元、Controllerから共通処理への接続を確認します。保存テストは一意な専用一時DBを使い、終了時に自身の生成物だけを削除します。発注境界のテストはfixtureへ差し替え、実注文は送りません。

2026-10-04の確認結果:

- `MstngM15Ea`・`MstngH1Ea`・`MstngH1EaAll` と以下の7スクリプトは、MetaEditorでエラー0・警告0。
- 隔離MT5で `MstngM15StrategySmokeTest`・`MstngM15EaConfigSmokeTest`・`M15EaTradePolicySmokeTest`・`H1ZigZagTrailDecisionSmokeTest`・`ElliotHistoryPreparationSmokeTest`・`M15EaPersistenceSmokeTest`・`M15EaControllerSmokeTest` を実行し、すべて成功。保存55項目、Controller接続19項目、履歴準備1,224項目を含みます。
- Controller接続では、保存成功後だけ送信する順序、保存失敗後のSKIP再保存、当該バー・消費回数の復元、採用分析のSL基準点、補正評価中に気配が失効した後の未消費再試行を確認しました。
- PythonはEA関連182件・DB関連165件・Elliot関連19件の計366件成功。旧M15 Factoryテストの2引数固定という期待を、既存の方向補正・FE引数へ追従しました。Factory本体の判定は変更していません。

コンパイル成果物と実行ログは一時ディレクトリへ出力します。運用先のex5更新・EAのチャートへの設置・実口座での発注・Strategy Testerによる売買成績比較は別途行う作業です。
