# Phosphor Substrate シーン復元

記録日: 2026-10-01。実測合計: **2分35秒**（報告保存直前まで）。
開始: 2026-10-01 03:40:19 UTC。集計: 2026-10-01 03:42:54 UTC。

## 確認した問題

SubstrateのGDScript・shader・仕様書は前回実装のまま残っていた。
CRT testのSceneだけがPostProcessingをrootにした構成へ変わり、テスト描画scriptとUIがなくなっていた。
ColorGrading / Vignetteが追加され、Substrate選択が消え、Row Pitch / Horizontal Fill / Vertical Fillはnullになっていた。
どのEditor操作でこの状態になったかは確認できていない。

## 復元

- commit fe58935の元Scene構造と、前回作業開始前のユーザー調整・完成時の記録を照合。
- CRTDisplayTest Node2D、テストscript、PostProcessing、WorldUILayer/UIを復元。
- CRT効果1個、mask style 7、legacy mask strength 0.75、Substrate、Triad Pitch 2.0、Row Pitch 3、Fill 0.90 / 0.85を復元。
- Brightness / Compensationは前回完成時と同じResource初期値1.0を使用。
- HEADに残っていた古いbrightness 0.5 / compensation 1.5は、前回実装前にユーザーが削除した設定なので復活させていない。
- mainの保存内容は前回作業開始時からSHA256一致。今回変更していない。
- 現在実行中のorb previewは止めず、Godot AIで復元Sceneを別にload / instantiateして確認後に解放。

## 工程

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・照合 | Git差分、前回記録、コード、Editor sessionを確認 | 上書きに至った操作原因は未特定 | 消失範囲をCRT testのSceneに特定 | 0分31秒 |
| 復元 | Scene構造とSubstrate設定を前回完成時へ戻す | なし | テスト描画・UI、mode選択、null値を復元 | 1分10秒 |
| 検証・報告 | CLI起動、Godot AIによるload / instantiate、差分・main hash確認 | なし | Sceneと設定を確認、記録を作成 | 0分54秒 |

## 検証結果

- Godot CLIによるCRT testのheadless起動成功、exit code 0。既存のOS certificate store警告のみ。
- Godot AIのResourceLoaderで保存Sceneを再読込し、root CRTDisplayTest / Node2D、テストscriptあり、UIあり、効果数1を確認。
- RuntimeでSubstrate = 2、Triad Pitch = 2.0、Row Pitch = 3、Horizontal Fill = 0.90、Vertical Fill = 0.85、Brightness / Compensation = 1.0を確認。
- git diff --check成功。
- main SHA256: 1D701D5C1E40C27EAE60706B9CDFDC23DC1CDD2E2F3AC1FC0CD1D1536DA3C3FD。
- shader / 算法は消失しておらず変更していないため、前回の全数値検証は再実施していない。

