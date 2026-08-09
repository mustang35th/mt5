# ZigZagElliot Alert Viewer

`ZigZagElliot`が保存したElliottアラートDBを、ローカルブラウザで検索・閲覧する読み取り専用ビューアです。

Python 3.14とSQLAlchemy 2.0を使用します。通信先は`127.0.0.1`だけで、インターネットや外部PCへ公開しません。

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

標準画面は次のURLです。

```text
http://127.0.0.1:5187/
```

検索、集計、一覧、ソート、ページング、CSV出力に加え、判定情報、時間足別Elliott、最新Waveポイントの詳細表示に対応しています。

標準画面はMUIをUI基盤とし、検索結果の現在ページをAG Grid Communityで表示します。検索条件、全体ソート、ページングは既存の読み取り専用APIが管理するため、グリッド内で別の抽出やページ内だけの並べ替えは行いません。

従来画面は障害時の退避先として次のURLに残しています。

```text
http://127.0.0.1:5187/legacy/
```

従来のReact版URL `http://127.0.0.1:5187/react/` も、既存ブックマークとの互換性のため利用できます。

既定では次のDBを参照します。

```text
%APPDATA%\MetaQuotes\Terminal\Common\Files\mstng-zigzag-elliot-alert.sqlite
```

DBは読み取り専用で開きます。MT5が使用中のWALを含む最新状態を、元ファイルの場所で参照します。

## 検索できる項目

- Run
- 通貨、時間足
- JST日時範囲
- BUY／SELL
- H1構造ランク
- W1分析方向とアラート方向の一致／不一致
- Elliottラベル、各時間足のWaveポイント、アラートタイトル・本文、シグナルキーの部分一致

一覧からアラートを選択すると、判定情報、MN1から現在足までの時間足別スナップショット、最新Waveを構成するポイントを確認できます。

初期表示はアラートを持つ最新Runです。「すべてのRun」を選ぶと、別Runで再検出された同じ市場シグナルも別レコードとして表示されます。

## CSV出力

現在の検索条件をCSVとして保存できます。波動ラベルはExcelに日付と誤認されにくいよう、`wave:`を付けて出力します。

## 詳細な起動方法

```powershell
& "$env:LOCALAPPDATA\Python\bin\python.exe" app.py --database "C:\path\to\database.sqlite" --port 5187 --open-browser
```

オプションを省略した場合、待受先は`127.0.0.1`、ポートは`5187`です。外部ネットワークへは公開しません。

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
