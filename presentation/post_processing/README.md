# ポストプロセス

- `post_processing.tscn` は旧mainが参照していたエフェクト順と設定値を維持する。
- Layer 2 EffectsにColorGrading → CRT → Vignetteを適用する。
- `main/main.tscn` のPlayfieldのゲーム座標は1920×1080基準。PixelationLayerで640×360固定描画し、最近傍拡大する。追加のピクセル化は無効。CRTは拡大後の解像度へ適用する。
- 調整環境ではPostProcessingを初期状態で無効にする。F2で切り替えられる。
- エフェクトの適用範囲はCanvasLayerの描画順で決まる。描画段階の値は `../render_layers.gd` にまとめる。

| 段階 | layer |
| --- | ---: |
| Playfield / 出力 | 0 / 49 |
| Layer 1 Effects | 50 |
| Layer 2 Effects | 150 |
| Overlay | 200 |

CRTの実装は [effects/crt/](effects/crt/) に移植し、実験フォルダへの依存を除いている。
