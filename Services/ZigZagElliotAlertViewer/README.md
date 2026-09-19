# ZigZagElliot Alert Viewer

`ZigZagElliot`が保存したElliottアラート、`ZigZagElliotH1ObservationAll`のH1 Observation、`ZigZagElliotM5ObservationAll`のM5 Observationを、ローカルブラウザで検索・閲覧する読み取り専用ビューアです。

Python 3.14とSQLAlchemy 2.0を使用します。Viewerの待受先は`127.0.0.1`だけです。付属の起動ファイルは、指定したtailnet内ホストも明示的に許可します。

## 初回セットアップ

PowerShellでこのフォルダーを開き、依存パッケージをインストールします。

```powershell
& "$env:LOCALAPPDATA\Python\bin\python.exe" -m pip install -r requirements.txt
```

SQLAlchemyは既存DBのReflectionと読み取り専用クエリに使用します。

## 起動

1. `start-viewer.cmd`をダブルクリックします。
2. ブラウザで`http://127.0.0.1:5187`が開きます。
3. 終了するときは、起動時に開いた黒い画面を閉じます。

既定ポートでViewerがすでに正常稼働している場合、`start-viewer.cmd`は二重起動せず、既存Viewerをブラウザで開いて正常終了します。`--port`などの引数を明示した起動では、その指定を優先して新しいViewerを起動します。

標準画面は次のURLです。

```text
http://127.0.0.1:5187/
```

画面上部のタブで「アラート一覧」「H1推移」「M5推移」を切り替えられます。アラート一覧は検索、集計、ソート、ページング、CSV出力に加え、H1方向一致診断、判定情報、時間足別Elliott、最新Waveポイントの詳細表示に対応しています。

H1推移は、H1新規足ごとに保存した観測を時系列で表示します。1行に取得時スプレッドと、MN1・W1・D1・H4・H1の分析方向、Elliott、波動状態、EMA200、GMMA、Stochastic、ATRをまとめます。詳細では価格差をpips換算するためのPip sizeも確認できます。`TIMEFRAME COMPARISON`の`ZigZag状態`は、各時間足の最新ポイントを`通常`または`追加ポイント`で表示します。H1推移専用の折りたたみ列`最新ZigZag Point`では、Peak／Bottom、Wave経過本数、価格差、FまたはFE、Depth Zone、数字波／Alphabet波、再分析前後、補正状態およびBar位置を時間足間で比較できます。FとFEは再分析前Elliott番号の偶数／奇数に従って切り替え、Depth ZoneはF対象時だけ表示します。Observation表がまだ作成されていない場合もアラート一覧は通常どおり利用でき、H1推移側だけが未利用表示になります。スプレッド、Pip size、ZigZag状態または最新ポイント詳細追加前の過去行は「未記録」と表示します。

検索条件は見出しのボタンで開閉でき、閉じた状態でも適用中の主要条件と未検索の変更有無を確認できます。検索結果の件数は省スペースな集計帯で表示します。

標準画面はMUIをUI基盤とし、検索結果の現在ページをAG Grid Communityで表示します。検索条件、全体ソート、ページングは既存の読み取り専用APIが管理するため、グリッド内で別の抽出やページ内だけの並べ替えは行いません。

デスクトップではJST日時・通貨・方向を左、詳細を右に固定します。表示列、列順、列幅と標準／コンパクト表示はブラウザに保存され、次回起動時に復元されます。「列を初期化」は列設定だけを既定値へ戻し、検索条件と表示密度は維持します。幅760px以下では表示領域を確保するため固定を自動解除します。

従来画面は障害時の退避先として次のURLに残しています。

```text
http://127.0.0.1:5187/legacy/
```

従来のReact版URL `http://127.0.0.1:5187/react/` も、既存ブックマークとの互換性のため利用できます。

## M5アラートの補正前後比較

「アラート一覧」のM5詳細は全画面グリッドで開きます。補正を採用した記録では「補正後（採用）」を初期表示し、「補正前」「前後比較」へ切り替えられます。前後比較はMN1からM5までの各時間足を補正後・補正前の2行で並べ、変わったセルを黄色で強調します。BUYは青系、SELLは赤系で、Elliott / Subも各分析方向と同じ色です。方向を変更したH4またはH1には「方向補正」を表示します。

「要点のみ／すべて表示」で列の範囲を切り替え、比較時の「差がある列のみ」で差がある列へ絞り込めます。時間足・分析区分などの識別列は残します。波動・FE・ポイント価格などは同じアラートに保存された前後の値を使い、表示時の相場取得や再分析は行いません。最新Waveのポイント・保存本文・通貨強弱も展開して確認できます。直前推進波の副次波はAlert DBに独立した数値列がないため、保存本文で確認します。

ENTRY等の判定結果と採用SL候補は、補正前表示へ切り替えても保存済みの採用結果を保持します。損切り欄は採用候補と元分析の比較用候補を区別し、価格・距離pips・LC0/5/10/15を表示します。注文やポジションに実際に設定されたSLではありません。M5詳細ではH1用の条件を再計算しません。

| 保存状態 | 詳細画面の扱い |
|---|---|
| `APPLIED` | 補正後を初期表示し、補正前・前後比較へ切り替え可能 |
| `NONE` | 元分析を採用。補正後・前後比較は利用不可 |
| `UNRECORDED` | 補正情報未記録。元の保存分析だけを表示し、補正の有無や採用SLを推測しない |
| `INCOMPLETE` | 補正情報の不足・不整合を明示。元分析は比較用として閲覧できるが、補正後として代用しない |

補正情報は既存の`GET /api/alerts/{id}`の`correction`で返します。追加3テーブルは任意対応とし、旧DBへテーブルや値を作成しません。M5推移の観測DBとは独立した機能です。既存一覧の集計・検索・CSVおよびH1詳細の表示は従来どおりです。

## Tailscaleから起動

Tailscale Serveが`http://127.0.0.1:5187`へ転送済みの環境では、通常どおり`start-viewer.cmd`をダブルクリックします。tailnet内の端末から次のURLを開きます。

```text
https://steelers.tail9d1d2a.ts.net/
```

起動ファイルはViewerだけを起動し、Tailscale Serveの設定は変更しません。すでに上記URLでJSONエラーが返る環境では、Serveの再設定は不要です。

付属の起動ファイルでは`steelers.tail9d1d2a.ts.net`と`:443`付きのHostだけを完全一致で追加許可します。Viewerの待受先は引き続き`127.0.0.1:5187`で、LANや全インターフェースへ直接公開しません。

Viewer自体にユーザー認証はありません。Tailscale ACLで閲覧端末を制限し、インターネット公開用のFunnelは使用しないでください。

既定では次のDBを参照します。

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-zigzag-elliot-alert.sqlite
```

DBは読み取り専用で開きます。MT5が使用中のWALを含む最新状態を、元ファイルの場所で参照します。

## M5推移の起動・使い方

**簡単な起動方法：このフォルダーの`start-m5-viewer.cmd`をダブルクリックします。** LIVE収集先の`mstng-zigzag-elliot-m5-observation.sqlite`を指定して起動し、「M5推移」タブを実行モードLIVEで開きます。毎回コマンドを入力する必要はありません。

通常の`start-viewer.cmd`は従来どおり残しています。どちらも既定ポートは5187なので、Viewerが起動中ならその黒い起動画面を閉じてから起動してください。既存Viewerを自動停止・設定変更する処理はありません。

M5用の起動ファイルは、下記の指定を代わりに行います。`--database`と既定のAlert／H1接続先は変わりません。M5 DBの自動探索や作成は行いません。

```powershell
.\start-viewer.cmd --m5-database "$env:APPDATA\MetaQuotes\Terminal\Common\Files\mstng-zigzag-elliot-m5-observation.sqlite" --open-tab m5 --open-source-mode LIVE
```

Viewerがすでに動いている場合は、そのViewerを終了してから上記で起動し直してください。別プロセスで確認したい場合は`--port 5188`など未使用のポートを追加します。既存プロセスの接続先は起動引数で変更されません。

LIVEを直接開く場合は`http://127.0.0.1:5187/?tab=m5&sourceMode=LIVE`です。M5画面の接続DB名を確認してください。`--open-tab m5`と`--open-source-mode LIVE`は最初に開くタブと検索モードを指定するだけで、DBやCollectorの実行モードは変更しません。Alert／H1タブも利用できます。省略時は従来の初期表示を維持します。M5だけが利用可能な場合もViewerを起動でき、タブ未指定の初期表示はM5になります。M5の未設定・接続エラーはAlert／H1とは別に表示します。`/legacy/`にはM5機能を追加していません。

テスト結果のr3を確認する場合は、上のコマンドのDB名を`mstng-zigzag-elliot-m5-short-20260908-r3.sqlite`、`--open-source-mode`を`TESTER`に変更して起動してください。LIVE DBへの切替でr3を移動・削除・上書きすることはありません。

- 専用起動ファイルではLIVE・観測がある最新LIVE Run・保存済み最新M5から24時間を開きます。URLに実行モードの指定がないM5画面の既定はTESTERのままです。期間の基準はPCの現在日時ではありません。
- Runを1件選び、通貨、開始／終了JST、5分刻みのJST時刻で検索します。開始を含み、終了を含みません。
- 幅1280px以上では「左：検索条件／右：一覧」、それ未満では上下配置です。見出しの「閉じる／開く」で検索欄全体を切り替えられ、閉じると一覧が全幅になります。入力途中の条件は維持し、開閉だけでは検索しません。Runの件数・保存期間は選択欄の下に表示します。
- 50／100／200件表示、日時／通貨の全体ソート、ページ番号の直接入力に対応します。列設定・表示密度・更新間隔はM5専用に保存します。
- 詳細はMN1／W1／D1／H4／H1／M15／M5の7足、取得品質、保存情報を表示します。前後移動は同一Run・通貨・分析Profileの保存済み観測で、一覧の期間外へ移る場合があります。
- 品質の未記録と有効な0を区別します。「取得時間」は初検出からSnapshot確定までで、DB保存待ちは含みません。「現在足OHLC」は取得時点の途中経過です。
- TESTERは手動更新、LIVEは既定15秒更新です。非表示中は停止し、手動期間・過去ページ参照では最新追従を解除します。新Runへは自動切替しません。

M5の分析方向はM5自身を基準に表示します。H1と逆方向の観測も表示し、FULL・H1 ENTRY CHECK・通貨強弱によるEntry・将来成績の判定は追加しません。品質表示だけで収集の完了や完全性を判定しません。

DBは`mode=ro`・`query_only`で元ファイルのWALを含めて読みます。テーブル・索引の追加やcheckpointは行いません。対応用途は`M5_OBSERVATION_ALL_V1`・M5アンカーで、H1混在DBや未対応形式は理由付きで拒否します。品質テーブル・行・列がない場合も、観測本体は「未記録」表示で閲覧できます。

読み取りAPIは`/api/m5/metadata`、`/api/m5/observations`、`/api/m5/observations/{id}`です。一覧にはRunと日時範囲が必須です。H1専用パラメータの流用は400、DB識別の不一致は409、一時的な読取失敗は503として返します。検索がタイムアウトした場合は期間を狭めて再試行してください。詳しくは[M5 Viewer設計書](../../Docs/Indicator/ZigZagElliotM5ObservationViewer.md)を参照してください。

## 検索できる項目（Alert／H1）

- 実行モード（LIVE／TESTER／すべて）
- Run
- 通貨、時間足
- JST日時範囲
- BUY／SELL
- H1構造ランク
- W1分析方向とアラート方向の一致／不一致
- Elliottラベル、各時間足のWaveポイント、アラートタイトル・本文、シグナルキーの部分一致

一覧からアラートを選択すると、判定情報、MN1から現在足までの時間足別スナップショット、最新Waveを構成するポイントを確認できます。

アラート詳細およびH1推移詳細の`TIMEFRAME COMPARISON`には、折りたたみ式の`H1 ENTRY CHECK`を表示します。Spread、方向、H1 Wave、Elliott、GMMA、EMA200、W1確認、Signal CountおよびEMA200距離を実行順で確認できます。現行H1のEMA200距離は参考表示とし、制限廃止前の保存済み`EMA200_DISTANCE_REJECTED`は当時のNG判定として表示します。H1アラートは保存済みEntry結果を総合判定の正本とし、H1推移はObservation Snapshotから判定できる項目だけを参考評価します。実行時mode、通貨強弱またはCountが未記録の場合は`不明`とし、Snapshotだけで総合OKを断定しません。アラート側には保存時点の通貨強弱を常時表示し、基軸・決済通貨の長中期／中短期順位、順位差、方向、Entry使用状態、取得元およびM5時刻の`EXACT`／`STALE`を確認できます。H1推移DBには通貨強弱Snapshotがないため、このカードはアラート詳細だけに表示します。

H1アラートの`H1 ENTRY CHECK`は、保存時Runの`input_text`からEMA200確認modeを表示します。`H1_ONLY`はH1だけ、`H1_AND_H4_REQUIRED`はH1・H4、`H1_AND_H4_AND_D1_REQUIRED`はH1・H4・D1を必須とし、対象外足は`対象外`です。必須のH4／D1 EMA200はH1方向と排他的に一致すれば`OK`、反対方向・NONE・両方向成立は`NG`、Snapshot欠損・NULL・旧DBのEMA未記録は`不明`とします。pipe区切りの`h1Ema200ConfirmationMode`が正確なキーと既知の値で1件だけ保存されている場合に限り採用し、重複・不正値・旧Runの未記録はmode不明です。Observationはmode不明の参考表示にとどめ、保存済みAlertの総合Entry判定や検索のFULL／Episode定義を変更しません。既存Run列を使用するためDB変更は不要です。

H1推移タブでは、実行モード、Run、通貨、JST日時範囲、`H1方向との一致`および`W1～H1＋EMA200一致`で検索します。一覧はJST日時を主表示とし、H1新規足と最新点のServer日時も併記します。

`H1方向との一致`では、分析方向（MN1・W1・D1・H4）とEMA200（W1・D1・H4・H1）を独立して複数選択できます。選択した条件すべてがH1の分析方向（`is_buy`）に一致する観測を抽出します。例えば「分析方向 D1」と「EMA200 W1・H4」なら、D1の分析方向とW1・H4のEMA200判定が、すべてH1の分析方向に一致する条件です。EMA200のBUYはBUY=1・SELL=0、SELLはBUY=0・SELL=1だけを一致とし、NONE、両方向成立、未記録およびH1分析方向の欠損・不正値は除外します。現行Profileで取得対象外のMN1 EMA200は選択できません。既存の保存項目を使うため、DBの変更や再収集は不要です。

分析方向は既存の反復URLパラメータ`syncTimeFrame`、EMA200は反復パラメータ`emaSyncTimeFrame`で保持します。EMA200未指定の旧URLは従来どおり動作し、検索・集計・ページ移動にも適用中の条件を引き継ぎます。

H1推移（連続H1シグナル表示を含む）の一覧下部では、ページ番号を入力し、Enterまたは「移動」で指定ページへ移動できます。入力途中では検索せず、1～最終ページの整数だけを受け付けます。適用中の検索条件とソート順を維持し、検索・ソート変更時は1ページ目へ戻ります。0件・読み込み中はページ移動を無効にします。アラート一覧のページ表示は従来どおりです。

`W1～H1＋EMA200一致`は、W1・D1・H4・H1の分析方向が一致し、H4・H1のEMA200判定も同じ分析方向へ明示的に一致する観測だけを抽出します。方向を問わない完全一致、完全BUYおよび完全SELLを選択できます。EMA200のNONE、BUY・SELL同時成立または対象時間足の欠損は一致に含めません。一覧では該当行を`FULL BUY`または`FULL SELL`で表示します。この固定条件は従来どおりで、`H1方向との一致`も指定した場合は両方を満たす観測を抽出します。

`表示単位`で`連続FULLを1シグナル`を選ぶと、同一Run・通貨・分析Profile・方向の連続するFULL H1を1行にまとめます。行には開始／終了JST、継続H1数、左右の打切りおよび観測欠損境界を表示し、詳細はシグナル開始H1のSnapshotを開きます。検索期間、JST時刻、`H1方向との一致`（分析方向・EMA200）および部分一致は、シグナル境界を確定した後に開始H1へ適用するため、検索条件で1つのシグナルが分断されたり、継続H1数が短くなったりすることはありません。

連続判定`FULL_ALIGNMENT_EPISODE_V1`はServer時刻の1時間進行、OANDA形式の週末（金曜23:00→月曜00:00）、Christmas休場（12月24日23:00→26日00:00）、年末年始休場（12月31日23:00→1月2日00:00）を連続とします。対象通貨のObservationが間にある場合、W1／D1／H4／H1子行が欠ける場合、またはその他の時間ギャップは安全側で分断します。別のBroker時間を使うDBでは、未知の休場パターンも分断されます。

初期表示はすべてのLIVE Runです。LIVEアラートがまだない場合もTESTERへ自動的に切り替えず、0件と表示します。実行モードをTESTERまたは「すべて」に切り替えると、既存のテスト結果を確認できます。

LIVE表示中は一覧を自動更新します。間隔は`OFF／5秒／15秒／30秒／60秒`から選択でき、既定は15秒です。選択値はブラウザに保存されます。TESTER・すべての表示中とブラウザのタブが非表示の間は自動更新を停止し、タブへ戻ったときは直ちに確認します。「今すぐ更新」は実行モードに関係なく使用できます。

最新順の1ページ目では新しい行を一覧へ反映して一時的に強調します。別ページまたは別の並び順を見ている場合は表示位置を勝手に動かさず、新着件数と「最新を表示」を案内します。

H1推移の現行Writerは`ZigZagElliotH1ObservationAll`だけです。通常の`ZigZagElliot`はH1 Observationを保存しません。LIVEでは`ZigZagElliotH1ObservationAll`の起動直後に進行中H1足を基準値として扱い、次のH1新規足から保存します。

旧版の`ZigZagElliot.ex5`を使用している場合は、削除済みの入力`h1ElliotObservationDatabaseEnabled=true`で動作しているインスタンスを停止してから`ZigZagElliotH1ObservationAll`を起動してください。旧Writerが保存した既存のObservationは削除されず、引き続きViewerで参照できます。

Runを指定しない場合は、選択した実行モードに属する複数Runをまとめて表示します。同じ市場シグナルが別Runで再検出されている場合は、別レコードとして表示されます。CSV出力にも現在の実行モードとRunの条件が適用されます。

## CSV出力

現在の検索条件をCSVとして保存できます。波動ラベルはExcelに日付と誤認されにくいよう、`wave:`を付けて出力します。

## 詳細な起動方法

```powershell
& "$env:LOCALAPPDATA\Python\bin\python.exe" app.py --database "C:\path\to\database.sqlite" --port 5187 --open-browser
```

`app.py`を直接実行してオプションを省略した場合、待受先は`127.0.0.1`、ポートは`5187`です。外部ネットワークへは公開しません。

信頼するローカルリバースプロキシのHostは、完全一致で追加できます。`--allowed-host`は複数回指定できます。URLやワイルドカードは指定できません。

```powershell
& "$env:LOCALAPPDATA\Python\bin\python.exe" app.py --allowed-host "steelers.tail9d1d2a.ts.net" --allowed-host "steelers.tail9d1d2a.ts.net:443"
```

## React版の開発とビルド

Node.jsは開発・ビルド時だけ必要です。利用時はビルド済みファイルをPythonが配信するため不要です。

配信ルートはビューアフォルダーで次のテストを実行します。

```powershell
& "$env:LOCALAPPDATA\Python\bin\python.exe" -m unittest -v test_app.py
```

React画面は次の手順でテスト・ビルドします。

```powershell
cd frontend
npm install
npm run test
npm run build
```

開発時はPythonサーバーを`5187`番で起動したうえで、別のPowerShellから`npm run dev`を実行します。Viteは`http://127.0.0.1:5173/react/`で起動し、`/api`をPythonへ転送します。生成物は`static/react/`へ出力されます。

### M5詳細の通貨強弱（別DB参照）

M5詳細では、観測と同じServer M5時刻の長中期・中短期順位を読み取り専用で参照します。標準のM5専用起動では、観測DBと同じCommon Files内の`mstng-currency-strength-2026.sqlite`（観測年に追従）を使用します。Viewer再起動後に有効になります。Collectorや観測DBの変更は不要です。

計算方式の初期値はWEIGHTEDです。UNIFORMを使用する場合、またはDBを別フォルダに置いた場合は以下のように指定できます。

```bat
start-m5-viewer.cmd --currency-strength-database "D:\Data\mstng-currency-strength-2026.sqlite" --currency-strength-calculation UNIFORM
```

時刻・LIVE/TESTER・サーバー・口座・計算方式が一致する完全集計だけ表示します。一致しなければ「該当なし」と表示し、別時刻・別方式へ自動代替しません。口座番号は画面・APIに公開しません。参照元DB名・方式・取得時刻・Runはパネルの「参照元」で確認できます。過去観測にも対応しますが、表示値は閲覧時に別DBから取得した参考値であり、M5観測DBに固定保存された値ではありません。
