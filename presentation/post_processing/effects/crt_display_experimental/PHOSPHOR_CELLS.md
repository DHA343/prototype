# Phosphor Cell

## 構成

既存試作を独立Passへ置き換えた。StyleはStretched VGA Phosphor（7）とVGA Phosphor（8）。
LegacyのID 0〜6は維持する。Gap系3 Style、Gap Strength、Gap用処理・ドキュメントは削除する。

- Pass 0: Signal Reconstruction → Beam → Legacy Mask（Legacyのみ）。
- Pass 1: Phosphor Cell（Phosphorのみ）。Pass 0のlinear HDRをsampleし、Beamは再計算しない。
- Pass 2: Phosphor Bloom。既存Gaussian、HDR source制限、光量再配分の式は維持する。

Cell Scaleはint 1〜4、初期値1。ViewportやCameraからは自動変更しない。
Scale 1のsubpixel pitchは4px、発光幅3px、非発光幅1px、row pitchは3px、triad幅は12px。
Staggerは正確なhalf-triadの6pxで、Scaleを全寸法へ整数倍する。
Stretched VGAはrowごと、VGAは2 rowごとにphaseを切り替える。

## Excitationとprofile

各triad / rowの中心から、X方向±triad幅/4、Y方向±row pitch/4の4点を等重みで平均する。
同一triadのR/G/Bが、この共通RGBを使う。現在fragmentのRGBへmaskを掛けない。
Source座標だけpixel centerの範囲へClampし、HDR RGBはClampしない。

発光領域の横・縦profileはsin(π * local_pixel_center / emission_size)の積。
Scale 1では各軸が0.5 / 1 / 0.5、非発光幅は厳密に0となる。
Emissionは励起値の選択channel × profile × Phosphor Brightness。
Phosphor Brightnessは0.5〜3.0、step 0.1、初期値1.5。自動光量補償は行わない。
既存Output Brightness CompensationはLegacyではPass 0、PhosphorではPass 1の出力に適用する。

Legacy Mask StrengthはLegacy専用とし、Phosphor選択時はInspectorで編集不可。
Cell Scale / Phosphor BrightnessはLegacy選択時に編集不可。元画像とのmixは使用しない。

## 保存値の移行

mask_strengthをlegacy_mask_strengthへ改名し、保存済みのmain用ResourceとCRT testを移行した。
mainはLegacy VGA / Strength 0.6を維持。CRT testの旧Aperture Grille GapはLegacy Aperture Grilleへ移行する。
既存試作のShaderIncludeは削除し、phosphor_cells.gdshaderへ置き換える。

## 検証結果

Godot 4.7.2 / Forward+ / D3D12 / HDR2Dで検証。専用test Sceneは追加していない。

- Legacy 7 Style × Strength 0 / 0.5 / 1の21ケースは、変更前shaderと全画素が完全一致。
- Cell Scale 1 / 2、両Styleで白、linear 50% gray、RGB単色、HDR 1 / 2 / 4 / 8 / 16を確認。
- RGB gradient、高コントラストRGB edge、画面端で、Pass 0 HDR画像から独立に計算した
  4点samplingとCell profileを比較。最大相対誤差は約0.10%。
- Bloom OFFの非選択channelと固定非発光領域は厳密に0。
  HDR 16の最大EmissionはScale 1で24、Scale 2で約22.39。1でClampされていない。
- 共通scalarとprofileから求めた均一面平均の最大相対誤差は約0.049%。
  初期Brightnessでの入力に対する平均倍率はScale 1で1/6、Scale 2で約0.1555。
  平均光量保存は要求せず、旧方式より暗くなることは仕様通り。
- 両Style × Scale 1 / 2の4ケースで、Cell出力とBloom用Emission画像が全画素完全一致。
- fractional Camera transform変更と1080p→1440pリサイズ後も、均一面のCell画像は全画素完全一致。
  Scaleは1のままで、自動倍率変更やgeometryのphase移動はない。
- CRT testで旧VGA系との比較、Scale 1 / 2、Bloom ON / OFF、細線、小さい文字、HDR矩形を確認。
  拡大表示で中心が明るく端が弱いCellと非発光領域が識別できる。
- mainの起動と保存値0.6、Cell Pass無効・Bloom有効を確認し、最終起動のgame logにエラーなし。

## 合格条件の評価

Cell形状、共通RGB sampling、HDR維持、固定integer grid、Bloomの処理順は確認できた。
可読性は未達。12px幅のtriadに共通励起値を1つ割り当てるため、細線や文字が量子化される。
特に12px〜18px文字は大きく潰れ、Scale 2ではさらに悪化する。Bloomは細部を復元しない。
白・grayの空間平均に強い色偏りはないが、通常表示ではCell模様と色の縁取りが目立つ。
現段階でLegacyよりゲーム画面に適しているとは判断しない。

ユーザー指定に従い今回の寸法は維持し、縮小やsampling変更は比較結果を見て別途判断する。
Legacy StyleとLegacy luminance preservationは保持する。
