# CRT test 編集可能な画像リストとキー操作

記録日: 2026-10-01。実測合計: **7分7秒**（報告保存直前まで）。
開始: 2026-10-01 05:16:24 UTC。集計: 2026-10-01 05:23:31 UTC。

## 操作

- CRTDisplayTest rootのInspector「Images」はArray[Texture2D]。自由に追加・削除・並べ替えできる。
- 初期値は_tempの既存PNG / JPGの2枚。script内の固定画像配列とIMAGE_ONE / IMAGE_TWO enumは削除。
- パターン表示中に2: 配列の先頭の有効な画像へ切替。
- 画像表示中に2: 次の有効な画像へ進み、末尾から先頭へ戻る。パターンは画像ローテーションへ含めない。
- 画像表示中に1: パターンへ戻る。この操作では背景を変えない。
- パターン表示中に1: Solid / Checkerboard / Gradientを循環。
- 画像は画面全体へ縦横独立に伸縮し、テスト背景・図形・文字を隠す。
- 未設定の配列要素はスキップ。空配列・全要素未設定ならパターン表示を維持。
- 有効画像が1枚の場合は、その画像を維持。画像を選択中に配列の割当で要素が消えた場合はパターンへ戻る。
- 画像表示からパターンへ戻った後の2は、先頭の有効画像から再開する。

## 工程

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認 | 現在のコード・保存Scene・ユーザー調整・規則・対象sessionを確認 | なし | 修正対象と既存調整を特定 | 1分27秒 |
| 実装・CLI・起動 | export画像配列、画像index、1 / 2キー操作、null/空配列対応、Scene初期画像を追加 | なし | 固定2画像制限を除去し、操作を変更 | 0分57秒 |
| Runtime検証 | 実入力イベントでキー操作と画像配列の変更を確認 | なし | 検証用コードの未型付けArray割当をArray[Texture2D]へ修正し、再起動後に検証成功 | 1分17秒 |
| Editor同期・差分確認 | InspectorのImages読込状態、保存済Scene再読込、再起動、既存ファイルhash確認 | なし | Editor内のImagesがnullのままだった状態を、Scene再読込で2枚の配列へ同期 | 2分23秒 |
| 記録 | 操作・検証結果・工程時間を保存 | なし | 作業報告を作成 | 1分3秒 |

## 検証

- Godot CLI --headless --editor --quit: exit 0。script / shader parse errorなし。既存OS certificate store警告のみ。
- Godot AIで保存済CRT testをautosave=falseで起動成功。
- 実入力2 / 2 / 2で画像index 0 / 1 / 0となり、画像だけで循環。
- 続く1でindex -1、UI表示、背景は0を維持。次の1で背景1。次の2で画像index0・UI非表示。
- 配列を[画像1, null, 画像2, 画像1]の4要素へ変更し、2入力でindex 0 / 2 / 3 / 0を確認。
- 空配列、全null、1枚のみ、選択画像の削除を確認。エラーなし。
- Echoキー入力では選択画像が変わらない。
- runtime property listでImagesがTexture2Dの編集可能なexport Arrayであることを確認。
- Editor APIでImagesを確認したところ、追加されたexport項目がnull状態だった。実行停止後、保存済Sceneをforce_reloadして2枚のresource pathが配列として読めることを確認。再起動も成功。
- 実行中のテストで行った配列変更は保存せず、最終起動は初期2枚・パターン表示へ戻した。
- git diff --check成功。
- main/main.tscnとpost_processing.tscnのhashは作業前後で一致。
- 作業前のCRT testのColorGrading、Glow、Triad Pitch 3.0などは維持。旧content=nullの保存項目は削除してImagesへ置換。

変更ファイル:
- presentation/post_processing/test_scenes/crt_display_test/crt_display_test.gd
- presentation/post_processing/test_scenes/crt_display_test/crt_display_test.tscn

