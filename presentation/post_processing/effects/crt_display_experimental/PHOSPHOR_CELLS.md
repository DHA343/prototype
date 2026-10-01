# Phosphor Cell

## 構成

StyleはStretched VGA Phosphor（7）とVGA Phosphor（8）。Legacy ID 0〜6は維持する。
Signal Reconstruction → Beam → Phosphor Cell → Phosphor Bloomの順序は変更しない。
同じCell shader内のCell SamplingでReference / Integrated / Substrateを比較する。追加SubViewportやOptical Spreadは使用しない。

## Reference

従来の描画を保持する。Cell Scale 1でtriad幅6px、各channelの幅2px・高さ2px。
Cell Scale 1〜4で横・縦・half-triad staggerを整数倍する。
現在fragmentの入力から1channelだけを発光させ、占有率と縦横profile平均を正規化する。
Scale 1の各軸profileは0.9。Scale 2以上は端1pxが0.8、内部が1.0。
Triad PitchとSignal SamplingはReferenceでは使用しない。

## Integrated geometry

- Triad Pitchは2.0〜6.0 output px、step 0.1、初期値2.5。解像度による自動換算はしない。
- 各R/G/B apertureの幅はpitch / 3。高さは2px固定。Gap用pixelやsoft edgeは設けない。
- Stretched VGAはCell rowごと、VGAは2 Cell rowごとにhalf-triad staggerする。
- Staggerはpitch / 2で、fractionalな位相を許容する。
- Cellはoutput座標に固定する。Cameraやworld移動でpatternを移動させない。
- Cell ScaleはIntegratedでは使用しない。縦のrow境界は整数pixelに一致するため、今回Y方向の積分は追加しない。

## CoverageとSignal

1 output pixelの横footprintを2または4個の小区間に分割する。
小区間ごとに各channelの矩形apertureとの重なり長を解析的に積分し、区間中央でSignal + Beam後のHDRをsampleする。

`emission = 3 * sum(input_rgb(sample_i) * aperture_integral(interval_i))`

Coverageには小区間幅が含まれるため、sample数で再度割らない。
周期を跨ぐ区間と画面左側の負の位相を扱い、画面右側では巨大な累積積分同士の差を取らず、局所の1周期へ換算して計算する。
Signalのsamplingは横方向のbilinear 2 / 4 sampleで、4×4 supersamplingやtriad単位の共通RGB・area samplingは使用しない。
Aperture積分は解析的だが、入力映像との積の積分は小区間ごとの近似となる。

各channelの占有率1/3を共通scalar 3で補償する。
Phosphor BrightnessとOutput Brightness Compensationはその後に掛ける。
均一入力の完全な周期で各RGB平均を保ち、HDR Clamp・channel間の光量再配分はしない。
同じpixelに複数channelが現れるのはcoverageによるもので、別channelの入力を流用しない。
Alphaは中心の入力sampleを維持する。

## Inspectorと保存値

Cell Samplingの初期値はIntegrated、Signal Samplingの初期値はTwo Samples。
ReferenceではCell Scaleを編集でき、Triad Pitch / Signal Samplingは編集不可。
Integratedでは逆にCell Scaleが編集不可。LegacyではCell関連項目をすべて編集不可とする。
SubstrateではCell Scale / Signal Samplingが編集不可で、2×2 samplingを固定使用する。
Row Pitch / Horizontal Gap / Vertical GapはSubstrateのみ編集可能。旧Fillの公開parameterは廃止した。
Legacy Mask StrengthはPhosphor選択中に編集不可。元画像とのmixは追加しない。

今回の比較条件はCRT testのみSubstrate / pitch 2.0 / row 3 / Gap 0.50・0.50を保存した。
mainは作業前に既にSubstrate / pitch 4.0 / row 3 / Fill 1.0・0.75を使用していた。
mainの見た目を保つため、保存値だけをGap 0.0・0.75へ等価換算した。CRT testの比較条件はmainへ適用しない。
Phosphor BrightnessのResource初期値は1.0。
CRT testはResource初期値1.0を使用する。mainの設定は作業前のまま維持する。

## Substrate geometry

- Triad全体とCell rowの周囲に、左右上下対称の非発光領域を設ける。
- Triadの発光幅はpitch − Horizontal Gap。これを等幅のR/G/Bへ分割し、channel内部境界にはGapを設けない。
- 高さはRow Pitch − Vertical Gap。Row Pitchは2 / 3 / 4 output px、初期値3。
- 両Gapは0.0〜1.0 output px、step 0.05。初期値はHorizontal 0.50 / Vertical 0.50。
- Gapは周期両端へ半分ずつ配置。pitchを変更してもGapの絶対幅は変わらない。小数境界を整数pixelへ丸めない。
- Inspector範囲外の値にも対応するため、負のGapは0、発光幅・高さの下限は0.001pxとして防御する。RGB値をclampする処理ではない。
- 矩形・hard edgeで、soft edgeは追加しない。
- Stretched VGAは毎row、VGAは2row単位でhalf-triad staggerする。Gapもstaggerに追従する。
- output pixelを2×2の4区間に分割し、各区間のX coverage × Y coverageを解析計算。その区間中心から入力信号をbilinear samplingする。
- Row Pitchが整数でpixel境界に整列するため、1区間内で異なるrow phaseを跨がない。
- 共通scalar gainは3 × pitch × row / (active_width × active_height)。比較基準pitch 2 / row 3 / Gap 0.50・0.50では4.8、Integratedの3に対する追加補償は1.6倍。
- 完全な周期の均一入力で各RGB平均を維持する。HDR clamp・別channelへの再配分・元画像mixはしない。
- pitch 2 / row 2 / Gap 1・1では追加補償が4倍となる。Gapを広げる場合は局所peakとBloomも確認する。
- Alphaは中心の入力sampleを維持する。

## Gap版の比較と検証

- 基準はpitch 2 / row 3 / Gap 0.50・0.50。pitch 4、row 2/4、H Gap 0.25/0.75、V Gap 0.25/0.75を一項目ずつ変更して比較する。
- 均一入力540条件で、平均誤差は最大約0.0570%、単色の別channelへの漏れ0。独立した矩形交差計算との最大誤差は約0.0806%（分母max(1, expected)）。
- 2D信号積分24条件の最大誤差は約0.1002%（同じ分母）。
- Reference / Integratedは24条件で変更前と完全一致。mainのFillからGapへの換算も両Styleで全pixel一致。
- Inspector範囲外のGap 999pxでも、発光面積の防御によりRGBが有限であることを確認。
- CRT testの比較画像ではpitch 4の方がRGB粒・色分離が強い。Row 3/4で緑にも明暗が出るが、行方向の構造として認識される傾向が残る。
- ChromaticAberrationなどの追加effectは比較中だけruntimeで外し、終了時に復元。保存値は維持した。
- HDRの空間平均保存はSDR表示での色相保存を保証しない。motion時のmoire / shimmer、GPU時間、全CRTの1080p / 2160p比較は未確定。

詳細はdocs/work-reports/phosphor-substrate-gap.mdを参照。

## 変更前Fill版の検証記録

- 均一入力720条件（両Style、row 2/3、pitch 2/2.5/3/6、5組のFill、白/HDR 2/4/8/16/R/G/B/gray）で平均光量の最大誤差約0.0488%、別channelへの漏れ0。
- 独立した矩形交差計算との最大誤差約0.0781%（分母max(1, expected)）。
- Gradient、1pxのY方向輝度変化、HDR edgeを含む32条件で2×2 quadratureを照合。最大誤差約0.1049%（同じ分母）。
- 変更前shaderとReference / Integratedを24条件で比較し、全pixelのRGBが完全一致。
- 初期Fill・pitch 2の緑単色で、row 2は約0.9995〜1.0、row 3は約0.9116〜1.1758。row 3で明暗構造が現れることを確認。
- 全41 pitch × 両Style × row 2/3の164条件を幅3840pxの左・中央・右端付近で確認。近ゼロcoverageの誤差を含むため、詳細数値は今回の作業記録を参照。
- 小数Canvas移動で、中央の均一入力の画素値は差0。
- CRT testで両Style・旧Integrated・row 2/3、Bloom ON/OFFを比較。緑にも行方向の構造が現れるが、白文字のRGB分離は残る。
- 全色で同じ素子感になることや、moving signalのmoire / shimmerがなくなることは保証しない。GPU profilingとCRT全体の1080p / 2160p比較は未実施。

上記より下の検証は、Substrate追加前のReference / Integrated実装時の記録。

## 検証

Godot 4.7.2 / Forward+ / D3D12 / HDR2Dで確認。専用test Sceneは追加していない。

- 両Style × pitch 6/3/2.5/2 × 2/4 sample × 白・linear 50% gray・RGB単色・HDR 2/4/8/16の144ケースを測定。
- 完全な周期を含む120×16pxのHDR画像で、各channel平均の最大相対誤差は約0.0326%。
  単色の他channelへの漏れは0。独立な区間交差計算との最大誤差は約0.0781%（分母はmax(1, expected)）。
- HDR 16のpeakはpitch 6/3で48、2.5で40、2で32。1でClampされていない。
- Referenceの両Style × Scale 1〜4の8ケースは、変更前shaderの全pixelと完全一致。
- GradientとHDR edge・1px周期線の2種類の入力で32ケースを測定。
  SourceのHDR画像からbilinear samplingと区間交差を独立計算し、最大誤差は約0.1034%（同じ分母）。
- 全41 pitch × 両Style × 2/4 sampleの164ケースを、幅3840pxのHDR画像で確認。
  x=0/1900/3800付近で解析式と比較し、RGB各成分の最大絶対誤差は約0.002344。
  均一白のRGB合計3に対する最大絶対誤差は約0.002442。
- 均一入力を小数Canvas transform（0.375, 0.625）で移動しても、Cellの画素値は完全一致。
- InspectorのReference / Integrated / Legacyのread-only切替を実際のResourceで確認。
- CRT testで両Styleの各pitch、Reference、2/4 sample、Bloom ON/OFFを比較。
- mainはIntegrated / pitch 2.5 / Two Samples / Brightness 0.8で起動。最新runにエラーなし。
- CLIの最終確認にshader/script parse errorなし。Signal、Beam、Legacy Mask、Bloomのソースは変更していない。

## 見た目と制約

6pxより白文字のRGB分離と粒の粗さが減り、小さい文字は読みやすくなった。
2.0pxはRGB構造をさらに抑え、2.5pxは素子感を多く残す。
Fractional coverageでも周期的な色変動は消えず、grayに斜めの色むらが見える。
SDR表示でHDR各成分が飽和すると、空間平均のlinear HDR保存だけでは見かけの色相を保証できない。

画面端の不完全な周期と変化する入力では、入力との平均一致を保証しない。
動く高コントラスト入力のmoire / shimmerと、2 / 4 sampleの主観的な優劣は未確定。
高解像度検証は幅3840pxのCell Pass単体。全CRT + Bloomの1080p/2160p比較とGPU profilingは未実施。
