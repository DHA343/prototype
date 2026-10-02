# Cell Emissionの横位相をCenterへ固定

実施日：2026-10-02。計測区間13:51:01〜13:52:33（JST）。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認・実装 | 参照と保存設定を確認。GapAlignment enum、export、uniform、parameter転送と分岐を削除し、Cellの横offsetを0.5px固定へ変更。仕様更新 | なし | Boundaryの選択肢と内部の切替を除去 | 1分03秒 |
| 検証 | CLI構文確認、CRT testのheadless起動、旧Center式とのソース比較、参照漏れの検索 | OS root certificate store読込エラー（既存、変更対象外）。GPU画面比較は未実施 | 構文確認・起動とも終了コード0。旧Centerと同じ式、削除propertyのコード参照なしを確認 | 29秒 |

## 変更

- Cell EmissionのRGB配置全体の横位相をPixel Center（0.5px）に固定した。Gapが0でも同じ位相を使用する。
- Horizontal Gap / Vertical Gapは維持。Mask内のグループ構成は変更していない。
- Gap Alignmentの設定とBoundary分岐は内部にも残さない。
- CRT testに保存されていた `gap_alignment = 1` を削除。旧Centerと新しい固定処理は同じ式のため、現在の保存設定の描画計算を維持する。
- 旧Boundaryを使うCell設定は、今後Centerの位相で描画される。Mask Redistributionには元々この設定が作用しておらず、今回も変更していない。

## 検証

- Godot 4.7.2 CLI check-only成功。
- CRT testをCLIでheadless起動し、3frame後に終了。Sceneとscriptの読込エラーなし、終了コード0。
- 変更前Cell shaderからAlignment uniformを除き、旧Center条件の結果を0.5へ置き換えた文字列が変更後と一致。その他の描画式は変更していない。
- presentation / mainのGDScript、shader、Scene、ResourceでGapAlignment / gap_alignmentの参照なし。
- Godot AI sessionは開始時に存在せず、Editor操作を要さない直接編集とCLIの機械的確認で完了した。Editorは起動していない。
- CLI起動時に既存のOS証明書store読込エラーが出た。証明書設定は変更していない。画面のGPU比較を実施したという扱いにはしない。
