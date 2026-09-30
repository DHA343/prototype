# Phosphor Bloom

Core の Signal Reconstruction → Beam → Phosphor Mask の後に適用する。
Near/Far の Gaussian と光量再配分は共通で、A/B で変わるのは source の HDR 応答だけ。

## 初期値

| 項目 | 値 |
| --- | --- |
| Mode | Limited (A) |
| Near Width | 2.0 px FWHM @1080p |
| Far Width | 16.0 px FWHM @1080p |
| Near Strength | 0.06 |
| Far Strength | 0.01 |
| Bloom HDR Limit | 2.0 |

Width は Viewport の高さ / 1080 を掛けて pixel 幅に換算する。
Gaussian は σ = FWHM / √(8 ln 2)、片側 3σ までの離散 kernel を正規化する。
画面端は反射境界を使用し、均一面と端の輝点の光量を保つ。

## A/B

- Linear (B): `S = original.rgb`。HDR Limit を無視する。
- Limited (A): 最大 RGB 成分を代表強度 I とし、I ≤ 1 はそのまま通す。
  I > 1 では `I' = 1 + (L - 1) * (1 - exp(-(I - 1) / (L - 1)))`。
  `S = original.rgb * (I' / I)` として RGB 比率を保つ。

L は Bloom HDR Limit。白付近の傾きは 1、強度が上がると L に漸近する。
調整項目は Limit のみに絞り、Threshold と Response は持たせていない。
Core 自体の HDR RGB は変更しない。

合成は `original + n * (near(S) - S) + f * (far(S) - S)`。
指定された再配分式と等価で、均一面での相殺誤差を抑える。
Gaussian も中心との差分で計算し、合成ではぼかしに使った同じ S を参照する。

## 比較シーン

`res://presentation/post_processing/test_scenes/crt_display_test/phosphor_bloom_test.tscn`

- `1`: Limited / Linear
- `2`: Bloom ON / OFF
- `3`: 輝点の移動を一時停止 / 再開

線形 HDR 1x / 2x / 4x / 8x / 16x、1px 線、10 / 12 / 16px の文字、
白い輝点、RGB 単色、均一な明部、移動する輝点、Viewport の左右端を含む。
CanvasItem の描画色を linear_to_srgb() で渡し、HDR バッファの値が意図した倍率になるようにする。
1px の横線は走査線に対する複数の位相で比較する。

## 検証記録

Godot 4.7.2 / Forward+ / D3D12 / HDR 2D、上記初期値で確認。
数値検証では Signal と Mask を無効にした独立 Viewport も使用した。

| 検証 | 結果 |
| --- | --- |
| 均一な RGB 比率 1:0.3:0.1、線形 HDR 1 / 2 / 4 / 8 / 16 | A/B とも OFF と画像データが完全一致。端も一致 |
| 16x の単一輝点、中央 / 端 / 角 | 最終画像の総光量誤差は 0.06% 未満 |
| 単色 R / G / B | source・halo に他チャンネルの混入なし |
| Limited の HDR source | 最大成分は 1 / 約1.63 / 約1.95 / 約2 / 約2。RGB 比率を維持 |
| Linear で Limit を 1.01 / 16 に変更 | 画像データが完全一致 |
| 540 / 720 / 1080 / 2160p | Near/Far 幅を高さに比例して換算。Far 実測は1080p換算で約16.03px |
| 移動する 8x 輝点 | 現在位置と同じフレームで source / Bloom 更新。旧位置に残像なし |
| World / Composite の前段処理 | Bloom source の Core 画像と OFF の最終画像が完全一致 |
| 強度ゼロ、Resource 変更後の PostProcessing 再構築 | Bloom pass と中間描画の停止、再構築後の正常動作を確認 |

Near は低解像度で 1px 前後になるため離散化の影響があり、
実測 FWHM の1080p換算は約1.90〜2.13px。
線形 HDR 16x の比較では Linear でも図形の輪郭は保たれた。
Limited は周辺光を抑えるが、必須とは判断していない。両方を残して比較する。

## 描画構成と負荷

全解像度の HDR SubViewport を 6 枚使用する。
Core を前段処理ごと再描画した Emission、共通 Source、Near の縦横、Far の縦横で構成する。
元画像に戻る循環依存を作らず、同じフレームの Core 出力を取得する。
無効時は中間 Viewport の描画を止める。確保したテクスチャは保持する。
比較の正確さを優先した初期版で、メモリと描画負荷の最適化は未実施。

既存 Beam shader、Glow、共通 PostProcessing の構造は変更していない。
比較後の mode 削除は source 関数と Resource の mode / Limit の項目に集約できる。
