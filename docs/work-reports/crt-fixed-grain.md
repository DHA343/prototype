# 固定Grainへの置き換え

実施日: 2026-10-02、21:41:41〜21:56頃 JST。Godot 4.7.2。

ユーザーが選択した「旧Noiseを置換」「Spread / Bloomより前」「細かな粒のみ」を実装した。

## 結果

- NoiseをGrainへ置き換え、Enabled / Strength / Sizeの3項目に整理。
- RGB共通の倍率 `1 + Strength × grain` をMask後のlinear HDR出力へ乗算する。
- grainは画面座標に固定したhashを、単一サイズの格子上でsmoothstep補間した-1〜1の値。時間更新、色ノイズ、複数サイズの合成は含めない。
- Strengthは0〜0.5、初期値0.2。Sizeは1〜4出力px、初期値1.5。Sizeは格子間隔で、実測の粒径ではない。
- 順序はSignal / Scanline、Mask / Cell、Grain、Optical Spread、Bloom。Bloom Coreにも同じ順序・設定でGrainを再描画する。
- Enabled OFFまたはStrength 0で、メインとBloom CoreのGrain描画・BackBufferCopyを無効にする。
- 純黒は黒のまま、HDRを1へclampせず、RGB共通倍率で色比率を維持する。後段のSpread / Bloomによる色や明るさの変化は残る。
- 倍率の期待値は1。有限の画面範囲や画像内容との相関により、画面の平均輝度が厳密に一定になるわけではない。
- CRT testの旧Noise OFFをGrain OFFへ移行。他の保存値は維持した。試す場合はGrain EnabledをONにする。

旧Luma / Chroma / Softness / Rateと、加算応答・Oklab往復変換・時間hashを実装から削除した。
Shaderを `crt_noise.gdshader` から `crt_grain.gdshader` へ移し、UIDは維持。
メインpass数は従来と同じ5。Bloom CoreではGrainが新たに再描画される。新しいSubViewportやtextureは追加していない。
GPU時間の定量測定は未実施。

## 検証

- Godot CLIでResource Scriptの構文検証を通過。削除したNoise設定・Shader・TIME参照が対象コードに残っていないことを確認。git diff --check通過。
- 実Shaderを使った128×96 HDR描画で、黒・グレー・HDR色 × Size 1 / 1.5 / 4 × Strength 0 / 0.2 / 0.5の27ケースを検証。全ケースで有限値、時間を隔てた全byte一致、強度0の全byte一致、倍率の範囲、RGB比率を確認。[数値](artifacts/crt-fixed-grain/validation.json)。
- 1512×850のCRT testで、変更直後のGrain OFFが変更前のNoise OFFと全byte一致。検証途中でViewportが1336×752へ変わったため、最後の旧画像との比較値は採用していない。[記録](artifacts/crt-fixed-grain/baseline.json)。
- 両Mask ModelでOFF、強度0、0.2、0.5を確認。強度0とOFFが一致し、メインとBloom CoreのGrain描画・画面コピーの有効状態が同期。Coreの順序も確認。[記録](artifacts/crt-fixed-grain/runtime.json)。
- InspectorのGrainグループに3項目があり、旧noiseプロパティが存在しないことを確認。Enabled / Strength / Sizeの保存・再読み込みも通過。[記録](artifacts/crt-fixed-grain/resource.json)。
- 最新のゲーム実行ログにエラー・警告なし。Editorには既存のCompositeEffects[3]のnull要素警告が1件残る。

開始時はCRT test実行中。同じEditor sessionで検証のため再起動し、終了時も実行中に戻した。
検証用に変更したMask ModelとGrain設定はScene保存値へ戻し、一時Script・Resource・raw画像は削除した。
以下の画像は報告用で、製品内のPixel Previewは追加していない。

| 比較 | 画像 |
| --- | --- |
| 固定粒、Size 1.5、Strength 0.5、最近傍4倍拡大 | [粒の拡大](artifacts/crt-fixed-grain/grain-size-1.5.png) |
| Cell Emission、Grain強度0 | [無効](artifacts/crt-fixed-grain/scene-1-0.png) |
| Cell Emission、Grain強度0.2 | [標準](artifacts/crt-fixed-grain/scene-1-20.png) |
| Cell Emission、Grain強度0.5 | [強め](artifacts/crt-fixed-grain/scene-1-50.png) |

## 工程記録

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認・設計 | 規約・既存処理・Bloom Core・保存値の確認、基準描画保存 | なし | 適用位置と設定の役割を確定 | 3分39秒 |
| 実装・機械的検証 | 固定乗算Shader、Grain設定、pass順序、保存値移行、説明更新、CLI検証 | なし | 旧Noiseを撤去し、Core再描画にもGrainを含めた | 2分09秒 |
| 描画検証 | 27ケース、実Sceneでの切り替え、Core同期、保存/再読込、画像確認 | GPU時間は未測定。既存Editorのnull要素警告は対象外 | 検証用Color uniformの自動色変換をVector4で避けた。検証Scriptの古いcacheによる取得エラーはゲーム再起動で解消。サイズの異なる画像比較を除外 | 7分43秒 |
| 整理・報告 | 一時ファイル削除、状態復元、最終参照確認、報告 | なし | 削除対象の設定・時間処理が残っていないことを確認 | 約1分30秒 |
