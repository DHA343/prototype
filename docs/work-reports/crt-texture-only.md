# TextureをDispersed Randomに固定

実施日: 2026-10-03、00:01:12〜00:12頃 JST。Godot 4.7.2。

TextureからSmooth RandomとOrderedを削除し、Dispersed Randomだけを残した。
InspectorはEnabled / Strength / Sizeの3項目。Patternのexport・enum・Shader uniform・分岐・Scene保存値も削除した。
固定hashから近傍平均を引く式、補正係数、smoothstep補間、適用位置、無効化条件は維持。
新たなexport項目・pass・textureは追加していない。

共通PostProcessingのEditor上の未保存Size 1.9を確認し、ON / Strength 0.2 / Size 1.9を引き継いで保存した。
CRT testはStrength 0.25 / Size 1.8を維持し、保存されたPatternだけを削除した。
Maskを含む他の描画処理は変更していない。

## 検証

- Godot CLIのResource Script構文検証を通過。
- 実Shaderの128×96 HDR描画で、変更前のDispersed Randomと変更後を比較。Size 1 / 1.9 / 4 × Strength 0 / 0.2 / 0.5の9ケースで全byte一致。[記録](artifacts/crt-texture-only/validation.json)。
- Strength 0でpassを無効化することを確認。
- 実ResourceのTexture exportがEnabled / Strength / Sizeの3項目だけで、TexturePattern enumが存在しないことを確認。
- Editor上の3項目の実値と保存値を確認。nullなし。[設定記録](artifacts/crt-texture-only/settings.json)。
- 現行製品コード・Scene・説明からtexture_pattern、TexturePattern、Smooth Random、Orderedの参照を撤去。
- 最新のゲームログにエラー・警告なし。既存Editorログは今回の対象外。
- 最終再起動で実Shaderと保存ファイルのcode一致、Pattern / Ordered削除、Dispersed固定、ON / Strength 0.2 / Size 1.9を確認。[最終記録](artifacts/crt-texture-only/final-runtime.json)。
- git diff --check通過。

Editorの古いResource表示が残ったため、スクリプトの更新と実値を再確認した。
Godot AIの検証器はerror 43を返したが、実ResourceではPatternが消え、CLIと実ゲームで正常にロード・描画できた。
ツール更新時の一時的なpreloadパス変更は元に戻し、最終ソースをCLIで検証した。
最終確認でShaderファイルに旧コードが戻ったため、Editorが保持する同じShader Resourceのcodeを更新し、ResourceSaverで保存した。
一時的な@tool ResourceをGodot AI経由で生成して更新し、Scene保存後・ゲーム再起動後に旧コードが復帰しないことを確認。
[Editor上の更新記録](artifacts/crt-texture-only/editor-shader.json)。更新用のScript / Resourceと比較用の旧Shaderは削除した。
最終確認用evalの型推論エラーはShaderの型を明示して修正し、再起動して確認した。製品Scriptのエラーではない。
以前の作業報告は当時の記録として保持した。

開始時はMain実行中、Editorでは共通PostProcessingを表示。同じsessionを使用。
検証中にゲームが停止されたため、最後の確認実行も停止し、完了時は共通PostProcessingの表示・停止状態とした。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認 | 規約、保存値、Editorの調整値、元Shader、実行Sceneを確認 | なし | 未保存Size 1.9と保存Size 1.8を区別 | 54秒 |
| 実装・Editor反映 | 不要方式・選択項目・保存値・説明を削除、Editorの実値を確認して保存 | Godot AI検証器のerror 43は未修正 | Resource上のPattern削除を確認し、調整値を保持 | 2分48秒 |
| 描画・構文確認 | 9ケースの旧方式一致、設定一覧、無効化、CLI検証 | なし | Dispersed Randomの描画が変わらないことを確認 | 54秒 |
| 同期修正・整理・報告 | EditorのShader更新、保存・再起動確認、設定記録、ログ、参照検索、一時ファイル削除、報告 | なし | 旧Shaderが復帰する問題を解消。確認用evalの型を修正。製品内に不要方式を残さず整理 | 約6分30秒 |
