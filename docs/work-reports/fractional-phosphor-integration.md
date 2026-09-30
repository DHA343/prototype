# Fractional Phosphor Integration 実装記録

記録日: 2026-10-01（日本時間）。計測開始: 01:35:58。集計時刻: 16:57:08 UTC。
実測合計: **21分10秒**（報告保存直前まで。調査、ツール待機、修正、検証、記録作成を含む）。

## 採用した仕様

- Stretched VGA Phosphor / VGA Phosphorに、同一shader内のReference / Integrated切替を追加。
- Integratedは高さ2 output pixelsの矩形aperture。Triad Pitchは2.0〜6.0 output px、step 0.1。
- 各pixelの横方向footprintを2または4区間に分け、区間ごとのaperture coverageを解析的に積分。入力信号は各区間の中点から取得する。
- 区間の積分値を足して、RGB共通のscalar gain 3を適用。HDR clampや別channelへの再配分はしない。
- Referenceは旧6px方式を維持し、既存Cell Scaleを使用する。
- main / CRT testはIntegrated、Triad Pitch 2.5、Signal Sampling 2で開始する。mainの既存Phosphor Brightness 0.8は維持する。
- Beam、Signal Reconstruction、Phosphor Bloomの計算は変更しない。Integration用のSubViewportやOptical Spreadは追加しない。

## 工程と所要時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 前提確認・仕様整理 | AGENTS.md、関連docs、既存shader、保存設定を確認。回答A / A / Bを実装条件へ反映 | なし | 既存設定との区別、変更範囲を確定 | 1分59秒 |
| 実装・CLI検証 | 共通shaderへcoverage積分、2 / 4 samples、Inspector切替を追加。mainとCRT testを更新 | なし | shader組込み変数をhelper内で直接参照した初回エラーを、fragmentから引数で渡す形へ修正。再検証で成功 | 3分8秒 |
| Runtime検証・見た目比較 | HDR平均、RGB漏れ、Reference一致、入力信号積分、全pitch範囲、Canvas移動、CRT test画像、mainを確認 | 灰色の周期的な色むら。移動映像のshimmer、GPU時間、2 / 4 samplesの最終選択は未確定 | aperture積分、平均光量、Reference維持、mainへの反映を確認 | 8分22秒 |
| 仕様更新・差分確認・報告 | PARAMETERS.md / PHOSPHOR_CELLS.mdを更新。差分と実行ログを確認し、工程記録を作成 | 上記の見た目・性能評価は継続項目 | git diff --check成功。mainの実行ログにproject由来のエラーなし | 7分41秒 |

## 検証結果

- **均一HDR入力144ケース**: 2 Style × 4 pitch × 2 sampling × 9入力。白、gray、RGB単色、HDR 2x / 4x / 8x / 16xを検証。各channelの空間平均誤差は最大約0.0326%。単色入力の別channelへの漏れは0。
- **Reference 8ケース**: 2 Style × Cell Scale 1〜4。変更前shaderと全pixelのRGBAを比較し、最大差0。
- **信号積分32ケース**: gradient、HDR edge、1px stripeを用い、独立したbilinear samplingとcoverage計算に比較。最大誤差は約0.1034%（分母をmax(1, expected)とした値）。
- **全pitch範囲164ケース**: 2.0〜6.0の41段階 × 2 Style × 2 sampling。幅3840pxの左側、中央、右端付近で確認。最大component絶対誤差0.002344。均一白のRGB合計3に対する最大絶対誤差0.002442。
- **Canvasの小数移動**: 均一入力で移動前後の同一output pixelを比較し、差0。Phosphor patternがoutput pixelに固定されることを確認。
- **CRT testの画像比較**: Reference、pitch 6.0 / 3.0 / 2.5 / 2.0、2 / 4 samples、Bloom ON / OFFを比較。2.5pxで粗いRGB粒と白文字の色分離は減少。2.0pxではさらにRGB構造が目立ちにくい。
- **main**: 保存設定とRuntimeでIntegrated / 2.5px / 2 samples / Brightness 0.8を確認。
- **Godot CLI**: shader / GDScriptの機械的検証成功。OSのroot certificate store警告は残るが、今回のproject変更によるshader / scriptエラーではない。

## 見た目と検証の限界

- aperture geometryの積分は解析的だが、入力信号とapertureの積の積分は少数点の近似である。
- fractional pitchでも灰色やgradientに周期的な色むらが残る。RGB構造やmoireが完全に消える実装ではない。
- linear HDRの空間平均を維持しても、表示時のchannel clippingを含むSDRの見かけの色まで一致するとは限らない。
- 2 samplesと4 samplesの数値検証は完了したが、4 samplesにする視覚的な利点は最終判断していない。
- Canvas移動の数値検証はpattern固定の確認であり、高contrastの移動映像におけるshimmerの主観評価を完了したものではない。
- 高解像度の数値検証はCell pass単体で実施。CRT全体とBloomを含む1080p / 2160p比較、GPU profilingは今回未実施。

