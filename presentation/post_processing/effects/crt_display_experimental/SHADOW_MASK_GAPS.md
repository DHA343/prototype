# Shadow Mask Gap variants

既存Style 0〜6は変更せず、末尾に以下を追加する。

| Style | 値 | 固定pattern |
| --- | --- | --- |
| Stretched VGA Gap | 7 | 既存6px周期の各2px蛍光体の片側をseparatorにする。行ごとのphase shiftを維持 |
| VGA Gap | 8 | 同じ6px周期。既存VGAの2-row配置を維持 |
| Aperture Grille Gap | 9 | 4px周期の前半2pxがG、後半2pxがR+B。各後半pixelがseparator |

Gap Strengthは0〜1、step 0.01、初期値1。既存Styleでは無視する。
Gap Widthは公開せず、separatorは整数出力pixel単位で固定する。
VGA系のseparatorは列の偶奇ではなく、staggerを含むphaseの偶奇で選ぶ。
Aperture Grille Gapは縦stripeのみで、行によって変化しない。

## 平均光量とHDR

`g = 1 - mask_gap_strength` とする。
`generate_mask()` のRGBにseparatorの減衰を含め、alphaにchannel平均を返す。
VGA系は `(1 + g) / 6`、Aperture Grille Gapは `(1 + g) / 4`。

既存の輝度補正は、選択channelを1まで発光させ、それ以上の光を非選択channelへ配る。
その式をGapへそのまま使うと、明るい入力で黒いseparatorも発光する。
Gap版だけ、一次光と余剰光の両方を発光するcell内で補正する。

- `a`: Gapを含むchannel平均
- `a0`: 元patternのchannel平均。VGA系は1/3、Grilleは1/2
- `d = a / a0`: 発光領域の平均減衰
- `m`: Gapを含むmask RGB
- `h = max(m.r, m.g, m.b)`: cellの発光量。1またはg
- `t = max(input.rgb, 0) / a`
- `p = clamp(t, 0, 1 / d)`
- `s = (t - p) / (1 / a0 - 1)`
- `phosphor = p * m + s * (h - m)`

各channelの平均は `a * p + (d - a) * s = input` となる。
Gap Strength 0ではd=h=1となり、元の輝度補正式に一致する。
Aperture Grille Gapのpitchは4pxで、元の2px pitchを横に2倍した配置に対応する。

Mask Strengthは従来通り、入力とphosphorを混合する。
Mask Strength 0ではGapを含めて影響しない。
Mask Strength 1・Gap Strength 1・Bloom OFFではseparatorが非発光となる。
Bloom ONでは周囲の蛍光体からの散乱光がseparatorにも入る。
Beam、Signal Reconstruction、Phosphor Bloomの式は変更しない。

## 検証

Godot 4.7.2 / Forward+ / D3D12のHDR描画を読み戻して確認した。
検証用のNodeは実行中だけ生成し、専用test Sceneは追加していない。

- 既存7 Style × Gap Strength 0 / 0.5 / 1の21ケースは、変更前shaderと画素データが完全一致。
- Gap Strength 0の3 Styleは元patternの輝度応答と完全一致。
  Aperture Grilleの参照patternは指定通り横方向を2倍にして比較。
- 新3 Style × Mask Strength 0 × Gap Strength 0 / 0.5 / 1の9ケースは、Maskなしと完全一致。
- 1920×1080 / 2560×1440 / 3840×2160で、新3 Style × Gap Strength 0 / 0.5 / 1を確認。
  VGA系のstaggerと、Grilleの縦stripeは独立に計算した整数patternと一致。
- 白・RGB単色のlinear HDR 1 / 2 / 4 / 8 / 16とSDR 0.18の均一領域を測定。
  Bloom OFF時のchannel平均の相対誤差は最大約0.086%。
- Gap Strength 1・Mask Strength 1・Bloom OFFでは、HDR 16を含めseparatorのRGBは厳密に0。
- Bloom ONで均一な白HDR 16のchannel平均誤差は最大約0.099%。
  Gap Strength 1のseparator / 発光cellの明るさ比は、測定したHDR panelで最大約8.1%。
- 2160pの均一な赤・緑・青HDR 16では、Bloom ONでも他の2channelは厳密に0。
- CRT testの1px / 2px線、12px文字、gradient、HDR矩形を各新Styleで表示確認。
  Grilleに横方向のseparatorはなく、Dots状の格子は追加していない。

誤差の数値はlinear HDR bufferでの測定で、ディスプレイ上のsRGB平均ではない。
固定pixel patternなので、表示側で縮小・拡大するとモアレが出る場合がある。
