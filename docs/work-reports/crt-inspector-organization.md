# CRT Inspectorの整理

このUI変更はユーザーの意図と異なったため、2026-10-02に撤回済み。以下は当時の実施記録であり、現在のUI仕様ではない。[撤回記録](C:/GameDev/Projects/prototype/docs/work-reports/crt-inspector-revert.md)を参照。

実施日：2026-10-02（JST）。2026-10-02 00:46:44〜2026-10-02 01:10:25、合計23分41秒。

## 変更

実装方式やsampling数が前面に出ていた設定を、見た目の目的から調整できる日本語UIへ整理した。
Shader、保存値の名前・初期値・範囲、描画pass、Sceneファイルは変更していない。

| Inspectorのまとまり | 何を調整するか |
| --- | --- |
| 調整画面 | CRT全体の有効、詳細設定の表示 |
| 映像のボケ | 横の鮮明さ、縦のボケ量 |
| 走査線 | 映像・走査線の行数、横線の濃さ、発光する横線の太さ |
| 蛍光体・マスク | 規則的な色の配列、模様の濃さ、RGB1組の横幅、粒の行の高さ |
| マスクの隙間 | RGB発光セルの左右・上下の非発光部分 |
| 光の混ざり | 隣のpixelへ移るごく狭い光。RGBの硬さや輪郭を和らげる |
| 光のにじみ | 直近のにじみと広いhaloの強さ・幅 |
| ノイズ | 不規則な明暗・色の粒、大きさ、更新の速さ |
| 明るさ | 全体の明るさ倍率 |

無効な設定を灰色で残す方式をやめ、選択したModel / Patternに必要な項目だけを表示する。
RGB発光セルのPatternは1つなので、Pattern選択欄は出さない。
固定pixel Patternでは横幅・行の高さを隠す。RGB発光セル以外ではGapを隠す。
Signal、Bloom、NoiseをOFFにした場合、その効果の細かい設定を隠す。値は保持する。

「調整画面 → 詳細設定を表示」をONにすると、信号間隔、面積平均、RGB配列のずらし方、
Cell Sampling、0.5px位置合わせ、Cellの追加明るさ、Bloom上限、Noiseの柔らかさを表示する。
詳細設定の表示状態は画面用であり、Resourceには保存しない。

| 旧UIの表示 | 新UIの表示 |
| --- | --- |
| Mask Redistribution | カラーパターン |
| Cell Emission | RGB発光セル |
| Staggered RGB | 交互に並ぶRGB |
| RGB Pixel Pattern | RGBと黒の粒 |
| Green / Magenta Stripes | 緑とマゼンタの縦縞 |
| Mixed Pixel Pattern | 混色の格子 |
| Horizontal 2 | 縦の細部を維持 |
| Horizontal 4 | 縦を維持・横を精密に |
| 2x2 | 縦も少し平均 |

[見た目から探す調整ガイド](C:/GameDev/Projects/prototype/presentation/post_processing/effects/crt_display_experimental/PARAMETERS.md)を更新した。
Guideには「どの見た目を変えたいか」「どの項目を触るか」「増減で何が起きるか」を記載している。

## 実装と確認

保存用exportには既存の名前を維持し、Inspectorには別の日本語property名を表示する。
日本語propertyのget / setは既存setterへ転送する。範囲やstepはScript metadataから引き継ぐ。
このため、Sceneを移行したり別の描画実装を追加したりする必要がない。
Godotの[Object property list API](https://docs.godotengine.org/en/stable/classes/class_object.html)と
[Scriptのproperty metadata / default API](https://docs.godotengine.org/en/stable/classes/class_script.html)を使用した。

詳細値は[verification.json](C:/GameDev/Projects/prototype/docs/work-reports/crt-inspector-organization-data/verification.json)に保存した。

| 検証 | 結果 |
| --- | --- |
| Godot CLI check-only | 終了コード0 |
| 36項目の日本語表示と内部値の対応 | getter / setter / 初期値への戻しを全項目確認。最終失敗0 |
| property list | 既存の英語exportは保存対象として維持し、Editor側には重複表示なし |
| 表示切替 | 固定Patternのサイズ設定、OFF効果の詳細を非表示。切替4回でproperty list更新4回 |
| 保存・再読込 | model / strength / Noise状態を保持。日本語表示用propertyや詳細表示状態を保存しない |
| Resource複製 | 描画値を保持。詳細表示状態は複製へ持ち込まない |
| Resource.changed | 日本語UIからの描画値の編集で1回通知 |
| Scene読込 | main / 共通PostProcessing / CRT testの保存Resourceが正常に読込可能 |
| 描画コード | Shader選択、pass数、parameter転送、pass有効判定、Bloom生成を含む8関数が変更前と一致 |
| 最終Runtime | run token 12の起動エラーなし、game logはhelper登録のみ |
| 差分 | git diff --check成功 |

最初の36項目の確認で、保存しない「詳細設定を表示」の初期値取得がnullになることを検出した。
この項目のみ初期値falseを明示し、全36項目を再検証して失敗0とした。

EditorログにはPostProcessingのshader解放時のversion null 2件とnull effect警告1件が記録されていた。
発生時点の特定は今回実施していない。最終Runtimeでは再現せず、この整理で関連する処理は変更していない。
前回のexport_enum型エラーの履歴も残っている。診断履歴は消去していない。
Inspectorの画面pixelを撮影した確認は未実施。Godotが生成するgroup / property名・編集可否・値の動作を確認した。
検証用Resource保存ファイルは削除し、この作業で起動したRuntimeは停止した。Editorはready。

## 工程と所要時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・UI設計 | 00:46:44〜00:54:56。現設定・Godot property APIを確認し、役割別の日本語UIを設計 | なし | 実装分類と調整画面の役割を分離 | 8分12秒 |
| 初期実装 | 00:54:56〜00:55:55。表示用propertyと条件付き表示を追加、CLI確認 | 後続確認待ち | 保存値を維持した日本語表示 | 0分59秒 |
| 検証・修正・Guide更新 | 00:55:55〜01:07:16。全項目・保存・複製・表示切替・Scene読込を確認 | Editor解放時ログの発生時点は未特定 | 詳細表示のrevert、重複項目と無効設定、調整目的の説明 | 11分21秒 |
| 最終確認・記録 | 01:07:16〜01:10:25。最終ログ・差分・終了状態、検証データと報告を保存 | Inspector画面pixelの確認は未実施 | 最終Runtimeの動作と検証記録 | 3分09秒 |
| 合計 | 2026-10-02 00:46:44〜2026-10-02 01:10:25 | 上記の確認限界のみ | Inspector整理を完了 | 23分41秒 |
