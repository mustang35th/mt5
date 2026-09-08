# ZigZagElliot

## ZigZagElliotListのH1共通D1条件（v1.33）

H1一覧の全4モードに、選択した「D1条件」およびD1分析方向（`isBuy`）とD1 EMA200方向の一致を共通必須条件としてAND追加します。対象はCHARTモードのH1と、H1＋M5独立2段の上段H1です。

```text
H1表示対象 ＝ 選択したD1条件 ＋ D1 EMA200同方向一致 ＋ 既存H1条件
```

| H1条件 | 共通D1条件に追加する既存条件 |
|---|---|
| D1＝H4＝H1（初期値） | D1・H4・H1の分析方向一致 |
| MN1～H1すべて一致 | MN1・W1・D1・H4・H1の分析方向一致 |
| W1～H1一致 ＋（MN1 または W1 EMA200） | W1・D1・H4・H1一致と、MN1またはW1 EMA200の同方向一致 |
| D1条件 ＋（H4 または H1） | H4・H1の少なくとも片方がD1と同方向 |

D1条件が初期値の「W1＝D1」、H1条件が「D1＝H4＝H1」の場合は、W1・D1・H4・H1の分析方向一致とD1 EMA200の同方向一致が必要です。D1条件を「MN1＝W1＝D1」または「W1＝D1 ＋（MN1 または W1 EMA200）」に変更した場合も、H1全モードで有効になります。

D1 EMA200の照合基準はH1方向ではなくD1方向です。ORモードでは、D1とH4が同方向ならH1が逆方向でも表示対象になり得ます。H4・H1 EMA200の一致は新たな必須条件にはしません。`EMA3`は引き続きH1方向を基準にした参考表示のため、H1がD1と逆方向の行は`EMA3 NG`になります。

H1単独表示の次点候補にもD1共通条件を適用します。D1条件不成立・D1 EMA200のNONEや不一致は表示対象外であり、分析エラーとしては数えません。必要なD1上位足の分析結果が不足している場合は未準備扱いです。タイトルの`&D1[W1+EMA]`などで選択中のD1共通条件を確認できます。

**既存設定への影響：** 新モードやinputは追加せず、既存H1モードの選択値0～3を維持したまま共通条件を必須化します。そのため保存済みset／チャートにも追加条件が適用され、従来表示されていた候補が対象外になる場合があります。「D1条件（D1/H4・全H1モード）」の設定を確認してください。既存のH1側条件を緩める変更ではありません。

D1固定・H4固定・CHARTのH1以外の時間足・下段M5の独立抽出・EA・Alert・DBは今回変更しません。H1＋M5の重複色は上段H1の新しい表示対象に連動します。D1-S／A／Bの意味と既存ソート、波動・Spread条件、評価周期は維持します。「通常候補／H4待ち／H1待ち」の新分類は今回の実装対象外です。

## ZigZagElliotListのD1固定一覧（v1.32）

「一覧モード」＝「D1固定（D1 EMA200一致必須）」では、選択した既存のD1方向一致条件に、D1分析方向（`isBuy`）とD1 EMA200方向の一致をANDで追加します。

| D1条件 | D1固定一覧の表示条件 |
|---|---|
| W1＝D1（初期値） | W1・D1の方向一致 ＋ D1 EMA200も同方向 |
| MN1＝W1＝D1 | MN1・W1・D1の方向一致 ＋ D1 EMA200も同方向 |
| W1＝D1 ＋（MN1 または W1 EMA200） | 既存の上位足条件成立 ＋ D1 EMA200も同方向 |

BUY候補はD1 EMA200がBUY、SELL候補はSELLの場合だけ表示します。NONE・逆方向・BUY/SELL競合・ラベル不整合・時間足不整合は表示対象外です。必要な分析結果が不足している場合も表示しません。EMA200方向は既存の判定をそのまま使用し、距離制限は追加しません。

D1-S／A／Bは従来どおり、D1に対するW1・MN1・W1 EMA200の一致度を表します。D1 EMA200条件とは分離しており、D1-SでもD1 EMA200が不一致なら一覧へは表示しません。件数集計と行抽出は同じ条件を使用し、EMA200の逆方向・NONEは分析エラーとして数えません。タイトル末尾の`&D1EMA`で追加条件の有効化を確認できます。

追加inputはありません。D1固定モードの既存3条件すべてに自動適用します。v1.32での適用範囲はD1固定だけです。v1.33では上記のとおりH1一覧にもD1共通条件を追加しました。CHARTのD1チャート、H4固定、EA・AlertおよびDBの条件は変更しません。D1固定一覧を確認するときは、「一覧モード」をD1固定へ設定してください。

- [D1固定モードの設定](../../Indicators/ZigZagElliotList.mq5)
- [方向一致とD1 EMA200判定](../../Include/Mstng/Elliot/ElliotDirectionAlignmentDecision.mqh)
- [固定値による回帰テスト](../../Scripts/Mstng/Elliot/ElliotDirectionAlignmentDecisionSmokeTest.mq5)

## H1の方向一致（通常版v1.36）

通常の`ZigZagElliot`では、「方向一致（主条件）」をinputから外し、`h1DirectionAlignmentMode`を`const`定数の`H1_DIRECTION_ALIGNMENT_W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED`に固定します。空になる「H1方向一致（主条件）」グループを削除し、チャート表示グループを「06. チャート表示」に繰り上げます。

H1の分析方向（`isBuy`）を基準に、次の両方を必須とします。

- W1・D1・H4・H1のisBuyが一致すること。
- MN1のisBuy、またはW1 EMA200の方向がH1と一致すること。

MN1だけが逆方向でも、W1 EMA200がH1と同方向なら方向一致条件は通過します。MN1とW1 EMA200が両方とも不一致なら対象外です。これは方向一致の条件だけであり、H1・H4・D1 EMA200、波動、Spread、Signal Countなどの既存条件も引き続き必要です。通貨強弱はフィルタ有効時だけ条件に使用する従来の仕様を維持します。

**既存設定への影響：** v1.36へ更新し、通常の`ZigZagElliot`を再読み込みしてください。旧チャート／setファイルに保存された`h1DirectionAlignmentMode`では固定値を変更できません。従来の初期値（値3）と条件は同じですが、値0・1のD1～H1条件や値2のMN1～H1全足一致を使用していたチャートは、固定条件へ切り替わるため対象が変わる場合があります。別端末には更新版を個別に反映してください。

W1追加確認は`OBSERVE_ONLY`固定、EMA200確認はH1・H4・D1の3足必須固定を維持します。Run設定には実際に使う`h1DirectionAlignmentMode=W1_TO_H1_WITH_MN1_OR_EMA200_REQUIRED`を引き続き保存します。共通の方向一致enum・判定クラス、`ZigZagElliotList`、`MstngEa`、`MstngH1Ea`、DBスキーマおよび過去の保存データは変更しません。

## H1のW1追加確認（通常版v1.35）

通常の`ZigZagElliot`では、「W1確認（追加条件）」をinputから外し、`h1W1ConfirmationMode`を`const`定数の`H1_W1_CONFIRMATION_OBSERVE_ONLY`に固定します。追加確認によるエントリー制限は行わず、W1方向とW1 EMA200の診断処理およびDB保存経路は維持します。Runの設定記録には`h1W1ConfirmationMode=OBSERVE_ONLY`を保存します。

v1.35時点では「方向一致（主条件）」は選択可能で、初期値は「W1・D1・H4・H1のisBuy一致 ＋（MN1方向一致 または W1 EMA200方向一致）」です。W1追加確認を診断専用にしても、主条件側のW1・MN1・W1 EMA200判定は無効になりません。v1.36からは上記のとおり主条件も初期値に固定します。

**既存設定への影響：** v1.35以降へ更新し、通常の`ZigZagElliot`を再読み込みしてください。旧チャート／setファイルに保存された`h1W1ConfirmationMode`では固定値を変更できません。以前OR／ANDを選択していた場合も、更新後は追加確認の制限が外れて診断のみになります。W1追加確認の変更だけでは、従来の初期値`OBSERVE_ONLY`を使っていた場合のエントリー条件は変わりません。v1.35では方向一致（主条件）の保存済み選択値を維持しますが、v1.36では固定条件へ切り替わります。

H1・H4・D1のEMA200一致必須、波動、Spread、Signal Count、通貨強弱および判定タイミングは変更しません。共通のW1確認enum・判定クラスは維持し、`ZigZagElliotList`、`MstngEa`、`MstngH1Ea`の設定・判定には変更を加えません。DBスキーマや過去の保存データも変更しません。

## H1のEMA200確認（通常版v1.34）

通常の`ZigZagElliot`では、`h1Ema200ConfirmationMode`をinputから外し、`const`定数の`H1_EMA200_CONFIRMATION_H1_AND_H4_AND_D1_REQUIRED`に固定します。「EMA200確認（追加条件）」はinput一覧に表示しません。

H1エントリーでは、H1・H4・D1のEMA200がすべて同方向であることを必須とします。通常版ではH1のみ／H1・H4のみへ切り替えることはできません。

基準はH1の分析方向（`isBuy`）です。BUYなら対象足のEMA200がすべてBUY、SELLならすべてSELLであることを要求します。対象足のNONE・BUY/SELL両方向成立・方向不一致・取得不能・時間足不整合はNGです。D1の分析方向とD1のEMA200方向は別条件です。

固定値はv1.33の初期値と同じです。共通クラスの従来2モードと値0・1は、他プログラム向けに維持します。H1のEMA200距離制限は引き続き無効です。W1・MN1の方向条件、波動条件、Spread、Signal Countおよび判定タイミングは変更しません。

### 既存チャートへの適用

v1.34へ更新し、通常の`ZigZagElliot`を再読み込みしてください。旧チャート／setファイルに保存された`h1Ema200ConfirmationMode`では固定値を変更できません。以前H1のみ／H1・H4のみを選択していた場合も、更新後はH1・H4・D1の3足必須になります。

`ZigZagElliotList` v1.31のH1アラートと`MstngEa` v1.08のH1・`MTF_3in3`も3足必須を初期値にします。保存済みinputを使う場合は各EMA200確認モードを明示的に変更してください。従来の2モードも選択できます。`MstngH1Ea` v1.07は、v1.06で導入した3足必須固定と戦略バージョン`H1_MTF3IN3_EMA3_SPREAD5_ZIGZAG10_V2`を維持します。EMA200以外の各プログラム固有の判定・評価周期は変更しません。

`ZigZagElliotList`のH1主一覧には、H1方向を基準とした3足一致の参考表示`EMA3 OK`・`EMA3 NG`・`EMA3 ?`を追加します。H1＋M5モードでは上段H1が対象です。一覧の表示対象、D1優先ソート、READY順位、M5独立判定は変更しません。この参考表示はアラートの確認モード選択とは独立します。

Runの設定記録には実際に使用するEMA200確認モードを保存します。通常版v1.34では固定値の`H1_AND_H4_AND_D1_REQUIRED`を記録します。既存Alert／H1 Observation DBのスキーマ変更や保存済み判定結果の更新は行いません。H1 Observationの検索でEMA200 D1を指定すると観測の絞り込みを確認できますが、Signal Countに関わる実際のエントリー時刻の変化はテスターで確認してください。

`MstngH1Ea`の専用DBだけは、v1.07のRun登録前の初期接続フェーズ（失敗時の再試行を含む）に物理v2へ移行し、Decision末尾へD1 EMA200方向の個別列を追加します。正しい保存済み診断からD1列だけを補完し、未記録・`~`はNULL、`NONE`は評価済み中立として残します。診断テキスト・hash・過去のJudge判定は変更しません。DB内に未失効`RUNNING` LeaseやDecisionの独自triggerがある場合、またはschema・診断が不正な場合は移行を拒否します。Run登録後の再接続ではDDLを実行しません。更新前に同じDBを使う旧版EA・テスターをすべて停止してください。TesterのLeaseはテスト内時刻のため、異なるテスト期間間のWriter停止をLease比較だけでは保証しません。今回の実装作業で運用／Tester DBを直接変更するものではありません。詳細は[MstngH1Eaデータベース設計書](../Database/MstngH1EaDatabase.md)を参照してください。

Viewerの`H1 ENTRY CHECK`は保存時のRun設定を使い、H4・D1を必須／対象外に分けます。設定が未記録・不正の場合やH1 Observationでは参考表示とし、現在の初期値から過去のモードを推測しません。保存済みENTRY結果と研究用FULL・Episodeの定義は変更しません。

### 実装と検証

- [EMA200確認モード](../../Include/Mstng/ExpertAdvisor/H1Ema200ConfirmationMode.mqh)
- [EMA200方向判定](../../Include/Mstng/ExpertAdvisor/H1Ema200ConfirmationDecision.mqh)
- [H1判定からの呼び出し](../../Include/Mstng/ExpertAdvisor/ExpertAdvisorMtf3In3H1.mqh)
- [固定値による回帰テスト](../../Scripts/Mstng/ExpertAdvisor/H1Ema200ConfirmationDecisionSmokeTest.mq5)
