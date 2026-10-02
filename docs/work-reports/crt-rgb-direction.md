# RGB分離の左右方向を変更

実施日: 2026-10-03、02:44:41〜02:49頃 JST。Godot 4.7.2。

赤の像を左、青の像を右へずらす設定へ変更した。
Offsetの正のXが右、正のYが下という意味は維持し、X値だけを反転した。

- 共通post_processing.tscn: Red (3, 0.5) → (−3, 0.5) px、Blue (−3, 0) → (3, 0) px。
- CRT Resource / Shaderの初期値: Red (2, 0.5) → (−2, 0.5) px、Blue (−2, −0.5) → (2, −0.5) px。
- PARAMETERS.mdの初期値と説明も更新。
- RGB Strength 1、Ghost Strength 0、上下のOffset、Mask等の他の調整値を保持。
- Main / CRT testは共通Sceneを参照したままにし、各Sceneへの個別設定は追加していない。

## 検証

- Godot CLIのGDScript構文確認を通過。描画式・新機能の追加はなし。
- Editor上の変更前後のプロパティ比較で、差は赤青のOffsetだけだった。
- Mainを実行し、Main / CRT testが同じCRT Resourceを参照し、両方ともRed (−3, 0.5)、Blue (3, 0)であることを確認。
- 新規Resourceの初期値と実Script / Shaderの保存コードとの一致を確認。
- Main起動・実行ログに新しいエラーや警告なし。git diff --check通過。
- [設定と実行確認](artifacts/crt-rgb-direction/settings.json)。

Editorの古いScript bufferによる上書きを避けるため、一時的な@tool Resourceで対象CodeEdit、
実GDScript、Shader Resourceを同期し、既存CRT ResourceのX値だけを変更してSceneを保存した。
反映用Scriptの型推論エラーはString型を明示して修正し、CLI確認後に実行した。
確認用Script / Resource / JSONと生成されたsidecarは削除した。
開始・終了とも共通PostProcessing表示、ゲーム停止。同じsession / PID 19964を使用。
以前の作業報告は当時の記録として保持した。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認 | 規約、現行値、共通Sceneの参照、Editor実値を確認 | なし | 未保存値との区別、変更対象をXだけに限定 | 約55秒 |
| 変更・Editor反映 | Sceneの左右、Resource / Shader初期値、説明を更新 | なし | 反映用Scriptの型指定を修正。Editor bufferを同期し保存 | 約2分10秒 |
| 検証 | CLI、変更前後の比較、Mainとtestの共通Resource・初期値確認 | なし | 保存後・再起動後の値とコード一致を確認 | 約40秒 |
| 整理・報告 | 一時ファイル削除、記録保存 | なし | 確認結果を保存し製品内に補助Scriptを残さず整理 | 約30秒 |
