# ZigZagElliot Alert Viewer

`ZigZagElliot`が保存したElliottアラートDBを、ローカルブラウザで検索・閲覧する読み取り専用ビューアです。

Python 3.14を使用し、追加パッケージは必要ありません。通信先は`127.0.0.1`だけで、インターネットや外部PCへ公開しません。

## 起動

1. `start-viewer.cmd`をダブルクリックします。
2. ブラウザで`http://127.0.0.1:5187`が開きます。
3. 終了するときは、起動時に開いた黒い画面を閉じます。

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
python app.py --database "C:\path\to\database.sqlite" --port 5187 --open-browser
```

オプションを省略した場合、待受先は`127.0.0.1`、ポートは`5187`です。外部ネットワークへは公開しません。
