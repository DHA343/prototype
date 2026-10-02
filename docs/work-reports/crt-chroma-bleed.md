# CRT Chroma Bleed

実施日: 2026-10-02。19:32:21 JST開始、19:49頃完了。Godot 4.7.2。

この報告は追加時の履歴。Chroma Bleedはその後、ユーザーの指示で削除済み。[削除の作業報告](crt-chroma-bleed-removal.md)を参照。

## 実装

選択された方針に従い、横方向のみ・幅と強度を独立・linear HDR RGBで色差のにじみを追加した。
Signal Reconstruction内に次の2項目を追加。既存Sceneの保存値は変更していない。

| 設定 | 範囲 / 初期値 | 意味 |
| --- | --- | --- |
| Chroma Bleed Width | 0〜8出力px、step 0.1 / 2 | 既存横フィルターの半径へ追加する色差の広がり。FWHMではない |
| Chroma Bleed Strength | 0〜1、step 0.01 / 0 | 元の色差と広げた色差の混合比 |

WidthまたはStrengthが0なら従来の処理経路を使う。初期Strengthは0なので、使用時は値を上げる。
調整の出発点はWidth 2〜4 / Strength 0.5。

明暗を `Y = 0.2126R + 0.7152G + 0.0722B`、色差を `R-G / B-G` として扱う。
同じsample loopで既存の明暗kernelと広い色差kernelを計算し、元の明暗を保ったRGBへ戻す。
Signal有効時の半径は `Signal Pitch / Sharpness + Width`、無効時は `1 + Width`。
両色差成分へ同じフィルターを使い、特定色のoffsetは加えない。

Scanline変調・Mask / Cell Emissionより前に適用し、BloomのCore再描画にも同じ設定を渡す。
追加の縦フィルターは設けず、既存Vertical Blurによる行の再構成は維持する。
Signal EnabledがOFFでもChroma Bleedを使える。

負のRGBが生じる場合は、非負のYを保ちながら灰色方向へ色差を縮める。
これにより黒は黒のままで、極端な飽和色の境界では彩度が下がることがある。
HDRを1へclampしない。Yが負の符号付き入力にはこの圧縮を適用しない。
後段のMask・Bloomまで含めた最終画面の輝度不変を保証するものではない。

pass・BackBufferCopy・SubViewportの追加なし。有効時は幅に応じてtexture readが増える。
GPU時間の定量測定は行っていない。

## 検証

- Godot CLIでResource Scriptの構文検証、2項目のInspectorグループ・範囲・保存/再読み込みを確認。
- 実際のCRT testの1512×850 HDR framebufferで、初期Strength 0の出力が変更前と全byte一致。[結果](artifacts/crt-chroma-bleed/baseline.json)。
- 実Shaderを使った64×48 HDR描画で、Signal ON/OFF × 均一HDR・白黒細線・左右の色境界・上下の色境界・飽和赤と黒を確認。
- 全10入力でWidth 0がStrength 0と完全一致。白黒の細線はChroma Bleed有効時も完全一致。
- 左右の色境界に横の混色が出る。上下の境界はSignal OFFで完全一致、ONでは半精度の丸め相当の差のみ。
- 通常10ケースと範囲端8ケースでNaN / Infなし、非負入力で負の出力なし。HDR peak 4を維持。Coreの最大輝度差は約0.000370。
- 実CRT testで両Mask Model × Strength 0 / 0.5 / 1を描画し、CoreとBloom replayのuniform更新を確認。[結果](artifacts/crt-chroma-bleed/runtime.json)。
- 最新実行のEditor / Gameに警告・エラーなし。実行を停止し、実行前の状態へ戻した。`git diff --check`通過。

機械的検証の数値は[validation.json](artifacts/crt-chroma-bleed/validation.json)、Resource検証は[resource.json](artifacts/crt-chroma-bleed/resource.json)。
比較画像は報告用ファイルで、削除済みのPixel Preview機能は復活させていない。

| 比較 | 無効 | 有効 |
| --- | --- | --- |
| 左右の色境界、Signal OFF | [Strength 0](artifacts/crt-chroma-bleed/test-0-2-off.png) | [Width 2 / Strength 1](artifacts/crt-chroma-bleed/test-0-2-on.png) |
| CRT test、Cell Emission | [Strength 0](artifacts/crt-chroma-bleed/scene-1-0.png) | [Width 4 / Strength 1](artifacts/crt-chroma-bleed/scene-1-100.png) |
| CRT test、Redistribution | [Strength 0](artifacts/crt-chroma-bleed/scene-0-0.png) | [Width 4 / Strength 1](artifacts/crt-chroma-bleed/scene-0-100.png) |

## 工程記録

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・実装 | 規約と既存Signal経路の確認、基準画像保存、Resource / Shaderへ追加 | なし | 既存の明暗とMask設定を維持する処理経路を確定 | 3分53秒（19:32:21〜19:36:14） |
| 検証・調整 | CLI、GPUの色境界・細線・HDR・範囲端、実Sceneの設定伝播、説明追記 | GPU時間の定量測定は未実施 | 白黒の丸め差をなくす色差計算、Signal OFFで小さい幅にも効果を持たせる半径、検証Scriptの構文エラーを修正 | 6分58秒（19:36:14〜19:43:12） |
| 最終確認・報告 | 最終ShaderでScene再検証、画像確認、仮設定復元、実行停止、一時ファイル削除、報告 | なし | 最終コードでも旧出力一致・Bloom反映を確認 | 約6分（19:43:12〜19:49頃） |

CLI起動時のOS証明書ストア読込エラーは環境由来で、今回のScript検証とResource保存は正常終了。
既存のMask整理に伴う未commit変更を保持し、今回の実装変更はCRT Resource・Core Shader・PARAMETERSへ加えた。
