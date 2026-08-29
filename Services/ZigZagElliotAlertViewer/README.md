# ZigZagElliot Alert Viewer

`ZigZagElliot`が保存したElliottアラートと、`ZigZagElliotH1ObservationAll`が保存したH1 Observationを、ローカルブラウザで検索・閲覧する読み取り専用ビューアです。

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

画面上部のタブで「アラート一覧」と「H1推移」を切り替えられます。アラート一覧は検索、集計、ソート、ページング、CSV出力に加え、H1方向一致診断、判定情報、時間足別Elliott、最新Waveポイントの詳細表示に対応しています。

H1推移は、H1新規足ごとに保存した観測を時系列で表示します。1行に取得時スプレッドと、MN1・W1・D1・H4・H1の分析方向、Elliott、波動状態、EMA200、GMMA、Stochastic、ATRをまとめます。詳細では価格差をpips換算するためのPip sizeも確認できます。`TIMEFRAME COMPARISON`の`ZigZag状態`は、各時間足の最新ポイントを`通常`または`追加ポイント`で表示します。H1推移専用の折りたたみ列`最新ZigZag Point`では、Peak／Bottom、Wave経過本数、価格差、FまたはFE、Depth Zone、数字波／Alphabet波、再分析前後、補正状態およびBar位置を時間足間で比較できます。FとFEは再分析前Elliott番号の偶数／奇数に従って切り替え、Depth ZoneはF対象時だけ表示します。Observation表がまだ作成されていない場合もアラート一覧は通常どおり利用でき、H1推移側だけが未利用表示になります。スプレッド、Pip size、ZigZag状態または最新ポイント詳細追加前の過去行は「未記録」と表示します。

検索条件は見出しのボタンで開閉でき、閉じた状態でも適用中の主要条件と未検索の変更有無を確認できます。検索結果の件数は省スペースな集計帯で表示します。

標準画面はMUIをUI基盤とし、検索結果の現在ページをAG Grid Communityで表示します。検索条件、全体ソート、ページングは既存の読み取り専用APIが管理するため、グリッド内で別の抽出やページ内だけの並べ替えは行いません。

デスクトップではJST日時・通貨・方向を左、詳細を右に固定します。表示列、列順、列幅と標準／コンパクト表示はブラウザに保存され、次回起動時に復元されます。「列を初期化」は列設定だけを既定値へ戻し、検索条件と表示密度は維持します。幅760px以下では表示領域を確保するため固定を自動解除します。

従来画面は障害時の退避先として次のURLに残しています。

```text
http://127.0.0.1:5187/legacy/
```

従来のReact版URL `http://127.0.0.1:5187/react/` も、既存ブックマークとの互換性のため利用できます。

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

## 検索できる項目

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

H1推移タブでは、実行モード、Run、通貨、JST日時範囲、上位足同期および`W1～H1＋EMA200一致`で検索します。一覧はJST日時を主表示とし、H1新規足と最新点のServer日時も併記します。

`W1～H1＋EMA200一致`は、W1・D1・H4・H1の分析方向が一致し、H4・H1のEMA200判定も同じ分析方向へ明示的に一致する観測だけを抽出します。方向を問わない完全一致、完全BUYおよび完全SELLを選択できます。EMA200のNONE、BUY・SELL同時成立または対象時間足の欠損は一致に含めません。一覧では該当行を`FULL BUY`または`FULL SELL`で表示します。

`表示単位`で`連続FULLを1シグナル`を選ぶと、同一Run・通貨・分析Profile・方向の連続するFULL H1を1行にまとめます。行には開始／終了JST、継続H1数、左右の打切りおよび観測欠損境界を表示し、詳細はシグナル開始H1のSnapshotを開きます。検索期間、JST時刻、上位足同期および部分一致は、シグナル境界を確定した後に開始H1へ適用するため、検索条件で1つのシグナルが分断されることはありません。

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
