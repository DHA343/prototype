# Phosphor Cell

## 構成

StyleはStretched VGA Phosphor（7）とVGA Phosphor（8）。Legacy ID 0〜6は比較用に維持する。
Gap Style、Gap Strength、Gap専用処理は使用しない。

- Pass 0: Signal Reconstruction → Beam → Legacy Mask（Legacyのみ）。
- Pass 1: Phosphor Aperture（Phosphorのみ）。現在fragment位置でPass 0のlinear HDRを参照する。
- Pass 2: Phosphor Bloom。既存Gaussian、HDR source制限、光量再配分の式を維持する。

## Geometryとsampling

- Scale 1の各channelは幅2px・高さ2px、RGB triadは6px。
- Cell Scaleは整数1〜4、初期値1。横・縦・staggerを整数倍し、解像度による自動変更はしない。
- Stretched VGAはCell rowごと、VGAは2 Cell rowごとにhalf-triad staggerする。Scale 1のstaggerは3px。
- Gridは `floor(FRAGCOORD.xy)` から求め、Cameraやworld移動には連動しない。
- `SCREEN_UV` のRGBから該当channelだけを発光させる。triad単位の共通RGB・area samplingは廃止する。
- 非選択channelは0。Gap用pixelは確保せず、HDR Clampやchannel間の光量再配分は行わない。

## Profileと正規化

横・縦とも同じ離散soft rectangleとし、両軸のweightを掛ける。
Scale 1は両pixelを0.9とする。Scale 2以上は各軸の端1pxを0.8、内部を1.0とする。
sin/cosでCell全体を減衰させない。

各軸のpixel数をsize、端のweightをedgeとすると、
`average = 1 - 2 * (1 - edge) / size`。
各channelの占有率1/3と両軸のprofile平均から、RGB共通scalarを計算する。

`normalization = 3 / (horizontal_average * vertical_average)`

`emission[channel] = input[channel] * profile * normalization * phosphor_brightness * brightness_compensation`

Brightness = 1.0 / Brightness Compensation = 1.0で、均一入力の完全なpattern周期の各channel平均を入力に一致させる。
画面端の不完全な周期や変化する入力では平均一致を保証しない。
HDR平均の保存は、SDR画面での見かけの明るさの一致を保証しない。

Scale 1の発光倍率は3.0、Scale 2の中心は約3.704。
入力16の局所値48以上は占有率の補償に必要なHDR値として許容し、Clampしない。

## Inspectorと保存値

Phosphor Brightnessは0.5〜3.0、step 0.1、初期値1.0。
mainとCRT testの保存値も1.0へ更新した。
Legacy Mask StrengthはPhosphor選択中、Cell ScaleとBrightnessはLegacy選択中に編集不可。
元画像とのmixは使用しない。既存Output Brightness CompensationはLegacyのPass 0、PhosphorのPass 1に適用する。

## 検証

Godot 4.7.2 / Forward+ / D3D12 / HDR2Dで確認。専用test Sceneは追加していない。

- 両Style × Scale 1〜4 × 白・linear 50% gray・RGB単色・HDR 2/4/8/16の72ケースを測定。
- 完全なpattern周期を含む144×48pxのHDR画像で、各channel平均の最大相対誤差は約0.049%。
- RGB単色の非選択channelの最大値は厳密に0。
- 入力16のpeakはScale 1で48、Scale 2で59.25。HDRが1でClampされていない。
- 両Style × Scale 1〜4で空間変化するHDR fieldを検証。現在位置の入力とgeometryから独立に求めた値との差は最大約0.152%。
- 実SubViewportの1920×1080 / 3840×2160、両Style × Scale 1/2で、同じpixel座標のCell出力は完全一致。
- CRT testでLegacy Stretched VGA/VGAとPhosphor両Style、Scale 1/2、Bloom ON/OFFを比較。
  1px/2px輪郭、小さい文字、gradient、高コントラストedge、HDR矩形を確認。
- mainはStyle 7 / Scale 1 / Brightness 1.0で起動し、最新runのgame logにエラーなし。
- Signal Reconstruction、Beam、Legacy Mask、Bloomのソースは変更していない。

## 見た目と残る制約

旧12px triad + 共通area samplingより粒が細かくなり、暗さと文字の潰れは改善した。
Scale 1でもRGB模様・色の縁取りは見える。Scale 2では粒が目立つため、通常表示の初期値は1とする。
「通常表示で粒を意識しない」「強いRGB fringeが出ない」は完全達成としない。
入力の細線とCell配置の干渉、動く高コントラスト入力のちらつきは残る評価項目。

高解像度の検証はCell Pass単体で実施した。埋め込みgameは1500×843pxに固定されていたため、
1080p/2160pでの全CRT + Bloomの見た目・GPU性能は未確認。
