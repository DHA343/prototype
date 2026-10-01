# CRT Mask整理（確認待ち）

2026-10-01。実測開始18:06:17 JST、今回の検証・回答整理まで18:10:51 JST。
Wide Grille / Wide Soft Grilleの削除を完了。Phosphor Cellの削減とStretched VGA改良variantは未実装。
Referenceを残すかの質問への返答が説明要求だったため、方式の違いを確認し、削除範囲を改めて質問した。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・説明 | AGENTSと関連docs、全参照、実行中Resource、ReferenceとLegacyの式を確認 | Phosphorの削除範囲は未確定 | 保存Resourceに削除対象ID 4 / 5の使用なし。Referenceは純RGBセル方式と確認 | 1分25秒 |
| 削除・検証・回答整理 | Wideのenum項目とshader分岐を削除。残るenum IDを明示。CLIとHDR runtime比較、docs更新 | Phosphor削減と改良variantは確認後に実施 | 既存7Style×Signal ON/OFFの14条件で変更前後の全pixel RGB差0。CLIにscript/shader parse errorなし | 3分09秒 |
| 合計 | この確認段階の実測時間。記録ファイル作成時間を含まない | 全依頼の完了ではない | Wide 2種類の削除完了 | 4分34秒 |

## 検証

- Godot 4.7.2、HDR2D SubViewport 48×24。RGB gradient、HDR最大16、edgeを含む入力を使用。
- 残るStyle ID 0 / 1 / 2 / 3 / 6 / 7 / 8について、変更前Core shaderと変更後を比較。Mask Strength 0.75、Signal ON/OFF。
- Style 7 / 8はCoreの通過出力だけを比較。Phosphor Cell shader自体は今回変更していない。
- CLI終了コード0。OSのroot certificate store読み取りエラーは既存の環境エラー。
- Editorの警告2件は以前の一時evalによる画像ファイル読み込み。今回の比較で新しいshader/scriptエラーは確認されなかった。
- Scene保存値・実行中effect設定を変更していない。ユーザーによる並行編集を保持した。

## Referenceの説明

Referenceは6px triadの整数pixelセルへ入力の対応channelだけを割り当て、平均占有率を共通scalarで補償する。
Scale 1ではprofileと補償が相殺され、選択channelは入力の3倍、非選択channelは0。
Legacy Stretched VGAはselected componentを1まで割り当て、余剰をその同じcomponentの非選択セル位置へ配置する。
別の入力channelへ色を変換する処理ではない。白1ではLegacyが全pixel白1、Referenceが各セルR/G/Bの3となる。
Referenceで色差が小さく見えた原因は未確定。Bloomと最終表示の飽和を含めた見た目の検証が必要。
