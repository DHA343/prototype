# Phosphor Cell Mask prototype

`Stretched VGA Phosphor` / `VGA Phosphor` を追加する。
既存StyleのID 0〜9を維持し、追加Styleは10と11とする。
ResourceとSceneの初期Styleは変更しない。CRT testのShadow Mask / Styleで比較する。

## 処理

Signal Reconstruction → Beam → Phosphor Cell → Phosphor Bloom。
新Styleだけ `phosphor_cells.gdshaderinc` の独立した処理へ分岐する。
既存の `generate_mask()` / `apply_phosphor_mask()` とGap版の補償は使用しない。
Beam、Signal Reconstruction、Bloomの式・設定は変更しない。

- 1080pでは各channelの発光幅2出力px、separator幅1出力px、triad幅9出力px。
- 矩形profileのweight合計はchannelごとに2。共通gainはgeometryから9/2 = 4.5。
- 出力は `input.rgb * one_hot_cell_profile * gain`。非選択channelとGapは0。
- RGB間の光量移動、HDR clamp、primary / secondaryへの分割は行わない。
- Mask Strength / Gap Strengthは無視し、Cell出力を常に100%使用する。
- 既存Brightness Compensationは従来通りCore出力全体へ適用される。
- Bloom sourceはCell適用後のCore HDR出力。Gapへ直接光を足さず、Bloomによる散乱だけが入る。

## 整数geometryとstagger

倍率は `max(1, floor(viewport_height / 1080 + 0.5))`。
1080pでは1倍、2160pでは2倍となり、発光幅4px / separator幅2px / triad幅18pxになる。
rowの高さも同じ倍率で拡大する。1440pは1倍で、倍率切替は整数単位となる。
形状調整parameterやfractional pixelは使用しない。

Stretched VGAはcell rowごとにphase 0 / 4を交互に使用する。
VGAは同じphaseを連続2 cell rowで共有する。
4pxは9px triadの半周期4.5pxを整数化した試作用のstagger。
3pxずつのwhole-cell移動ではseparator列が揃うため使用しない。
Gapもrowのoffsetと一緒に移動し、画面固定の黒い縦線にならない。
画面端ではcellが切れることがあり、phaseをずらしたrowでは先頭の完全なRGB cellはBとなる。

## 検証

Godot 4.7.2 / Forward+ / D3D12でHDR bufferを読み戻して確認した。
検証Nodeと比較用shaderは一時的に生成し、専用test Sceneは追加していない。

- 既存10 Style × Mask Strength 0 / 0.5 / 1 × Gap Strength 0 / 0.5 / 1の90ケースは、
  変更前shaderと全画素のデータが完全一致。Signal / Beamも有効にして比較。
- 1920×1080と3840×2160で白・R / G / Bのlinear HDR 1 / 2 / 4 / 8 / 16、SDR 0.18を確認。
  全セルが独立に計算した整数geometryと一致し、channel平均の最大相対誤差は約0.087%。
- Bloom OFFではGapと非選択channelは厳密に0。HDR 16の発光セルは72まで出力される。
- 新2 Style × Mask Strength 0 / 0.5 / 1 × Gap Strength 0 / 0.5 / 1の18ケースは、
  各Styleの出力と完全一致。両Strengthが新方式に影響しないことを確認。
- Bloom ONでも両解像度で白・R / G / BのHDR 1 / 2 / 4 / 8 / 16を確認。
  channel平均の最大相対誤差は約0.156%。単色入力の他channelは厳密に0。
- 初期Bloom設定で均一な白のGap / 発光cellのRGB合計比は、1xで約9.6%、16xで約2.23%。
  Gapに散乱光が入る一方、Cellとの差は維持される。
- CRT testで旧VGA系との比較を行い、HDR矩形、暗い背景、1px / 2px線、小さい文字を表示確認。
  1080pと2160pではCRT testをHDR SubViewport内でも描画して整数倍率を確認。

## 比較上の制約

平均光量の保存はlinear HDRと、triadの整数周期を含む均一領域についての結果。
SDR表示でのclippingやsRGB変換後の明るさの平均を保存するという意味ではない。
小さい図形や色が変化する領域ではCellの位置と信号の相関があり、同じ平均にはならない。

実表示では旧方式よりRGB CellとGapが強く見え、細線と小さい文字に欠けや色の縁取りが出る。
2160pで文字の出力pixelサイズを拡大しない場合、2倍のCellと既存Beamに対して文字が小さくなり、
12px文字などの読みやすさは特に低下する。Bloomはこの細部損失を完全には補わない。
試作段階では元画像とのmix、Beamの変更、他Styleへの展開で補正せず、方式の比較対象として残す。

Gap系Styleと実装を共有しないため、Gap版は後から別に削除できる。
