# CRT test 画像切替

記録日: 2026-10-01。実測合計: **4分23秒**（報告保存直前まで）。
開始: 2026-10-01 05:01:59 UTC。集計: 2026-10-01 05:06:22 UTC。

## 変更

- CRT testの2キーで通常テスト / 画像1 / 画像2を循環する。
- 画像1: res://_temp/0040997d99e7fc8ecebb4518ae97c9e9.png（1920×1064）。
- 画像2: res://_temp/img_art2.jpg（1088×612）。
- 画像表示中は既存背景・図形・captionの描画を行わず、UIの全Labelも非表示。
- 画像はviewport全体へ縦横独立に伸縮。縦横比による余白やcropは設けない。
- resize通知で再描画し、通常テストの中央配置offsetを相殺して画面端まで画像を描く。
- 1キーの背景切替は維持。2キーの押しっぱなしによるrepeatは無視する。
- 起動時は通常テスト。InspectorのContentからも切替可能。
- 画像は既存のCRT PostProcessingを通して表示する。

## 工程

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認 | _tempの画像2枚、CRT test、規則、Godot AI sessionを確認 | なし | 対象画像と描画位置を特定 | 1分1秒 |
| 実装・CLI・起動 | Content選択、画像描画、UI非表示、2キー、resize再描画を追加 | なし | 画像中のテスト描画除去と全画面伸縮を実装 | 0分53秒 |
| Runtime・画像検証 | キー入力、repeat、通常テスト復帰、CRT画像表示、6条件のresizeを確認 | なし | 縦長・横長でも四隅まで表示、UIなしを確認 | 1分22秒 |
| 差分・報告 | 差分、実行ログ、既存Sceneのhashを確認し記録 | なし | 作業前のユーザー変更を維持 | 1分7秒 |

## 検証

- Godot CLI --headless --editor --quitはexit 0、GDScript / shader parse errorなし。既存のOS certificate store警告あり。
- Godot AIでCRT testをautosave=falseで起動、helper live、起動エラーなし。
- Input.parse_input_eventで2キーを3回入力し、Content 1 / 2 / 0を確認。画像1・2ではUI非表示、通常テストへ戻るとUI表示。
- Echo eventではContentが変わらないこと、1キーで背景が切り替わることを確認。
- 実行画面1515×852で両画像をcapture。画像1のCRT適用後の表示を確認。
- 画像描画のみを一時SubViewportで確認。2画像 × 640×360 / 240×480 / 1200×400の6条件で、UI非表示、四隅への描画を確認。240×480の画像2を目視して余白・test overlayなしを確認。
- 検証用SubViewport / Scene instanceは終了時に解放。恒久的なtestファイルは追加しない。
- 最新game logにエラーなし、git diff --check成功。
- main/main.tscn、post_processing.tscn、crt_display_test.tscnのSHA256は作業前後で一致。既存のCRT設定とユーザー変更は維持。

変更した実装ファイル:
presentation/post_processing/test_scenes/crt_display_test/crt_display_test.gd

