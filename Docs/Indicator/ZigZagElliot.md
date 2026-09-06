# ZigZagElliot

## H1のEMA200確認（v1.33）

通常の`ZigZagElliot`をH1チャートで使用する場合、inputの「03. H1エントリー追加条件」→「EMA200確認（追加条件）」で確認対象を選択します。

| 選択値 | 必須のEMA200方向 |
|---|---|
| `H1_EMA200_CONFIRMATION_H1_ONLY` | H1 |
| `H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED` | H1・H4 |
| `H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED`（初期値） | H1・H4・D1 |

基準はH1の分析方向（`isBuy`）です。BUYなら対象足のEMA200がすべてBUY、SELLならすべてSELLであることを要求します。対象足のNONE・BUY/SELL両方向成立・方向不一致・取得不能・時間足不整合はNGです。D1の分析方向とD1のEMA200方向は別条件です。

新モードでは既存のH1・H4確認にD1をANDで追加します。従来の2モードはD1を参照せず、既存の値0・1も維持します。H1のEMA200距離制限は引き続き無効です。W1・MN1の方向条件、波動条件、Spread、Signal Countおよび判定タイミングは変更しません。

### 既存チャートへの適用

コンパイル済みのv1.33へ更新しても、チャートや保存済みsetファイルのinput値が残る場合があります。既存チャートでは「EMA200確認（追加条件）」で`H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED`を明示的に選択してください。従来条件へ戻す場合は`H1_EMA200_CONFIRMATION_H1_AND_H4_REQUIRED`を選びます。

`ZigZagElliotList` v1.31のH1アラートと`MstngEa` v1.08のH1・`MTF_3in3`も3足必須を初期値にします。保存済みinputを使う場合は各EMA200確認モードを明示的に変更してください。従来の2モードも選択できます。`MstngH1Ea` v1.06は3足必須を固定して使用し、戦略バージョンを`H1_MTF3IN3_EMA3_SPREAD5_ZIGZAG10_V2`へ更新します。EMA200以外の各プログラム固有の判定・評価周期は変更しません。

`ZigZagElliotList`のH1主一覧には、H1方向を基準とした3足一致の参考表示`EMA3 OK`・`EMA3 NG`・`EMA3 ?`を追加します。H1＋M5モードでは上段H1が対象です。一覧の表示対象、D1優先ソート、READY順位、M5独立判定は変更しません。この参考表示はアラートの確認モード選択とは独立します。

Runの設定記録には選択したEMA200確認モードを保存します。既存DBのスキーマ変更や保存済み判定結果の更新は行いません。H1 Observationの検索でEMA200 D1を指定すると観測の絞り込みを確認できますが、Signal Countに関わる実際のエントリー時刻の変化はテスターで確認してください。

Viewerの`H1 ENTRY CHECK`は保存時のRun設定を使い、H4・D1を必須／対象外に分けます。設定が未記録・不正の場合やH1 Observationでは参考表示とし、現在の初期値から過去のモードを推測しません。保存済みENTRY結果と研究用FULL・Episodeの定義は変更しません。

### 実装と検証

- [EMA200確認モード](../../Include/Mstng/ExpertAdvisor/H1Ema200ConfirmationMode.mqh)
- [EMA200方向判定](../../Include/Mstng/ExpertAdvisor/H1Ema200ConfirmationDecision.mqh)
- [H1判定からの呼び出し](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3H1.mqh)
- [固定値による回帰テスト](../../Scripts/Mstng/ExpertAdvisor/H1Ema200ConfirmationDecisionSmokeTest.mq5)
