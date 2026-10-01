# Phosphor Substrate 試作記録

記録日: 2026-10-01（日本時間）。
計測開始: 12:13:19 JST。集計時刻: 2026-10-01 03:25:08 UTC。
実測合計: **11分49秒**（報告保存直前まで。調査、ツール待機、検証中の修正を含む）。

## 採用条件

- Cell SamplingにSubstrateを追加。同じshaderに既存Reference / Integratedを残す。
- Stretched VGA Phosphor / VGA Phosphorの両方で使用可能。
- Horizontal Fill 0.90 / Vertical Fill 0.85を初期値とし、各0.75〜1.0、step 0.01でInspector調整可能。
- Horizontal FillはTriad全体の発光幅。左右対称の余白を設け、残った領域をRGBへ等分する。RGB内部にはGapを設けない。
- Vertical Fillはrowの発光高さ。上下対称の余白を設ける。矩形・hard edge、soft edgeなし。
- Row Pitchは2 / 3 output pxを比較可能。初期値3。
- CRT testのみSubstrate / Triad Pitch 2.0 / Row Pitch 3 / Fill 0.90・0.85を保存。
- 新方式は2×2 signal samplingを固定使用。各区間の矩形aperture coverageをX・Y両方向で解析積分する。
- gain = 3 / (Horizontal Fill × Vertical Fill)。初期値は約3.9216、従来のgain 3に対する追加倍率は約1.3072。
- HDR clamp、別channelへの光量移動、元画像とのmixは追加しない。
- Beam、Signal Reconstruction、Bloomのshaderや算法は変更しない。恒久的なSubViewportや専用test Sceneも追加しない。

## 工程と所要時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 前提確認 | AGENTS.md・関連docs・現在の差分・対象Godot AI sessionを確認 | なし | mainとCRT testのユーザー調整を特定 | 1分32秒 |
| 実装・CLI検証・起動 | Substrate shader分岐、Inspector項目、CRT test保存値を追加 | なし | uniform row_pitchとReference内ローカル名の衝突を修正。CLIでshader/script確認、CRT test起動成功 | 1分55秒 |
| Runtime数値・画像検証 | 均一HDR、RGB漏れ、2D信号積分、旧方式一致、画面端、移動、Inspector、Bloom ON/OFFを確認 | 白文字のRGB分離。動く信号の主観評価・GPU時間は未評価 | 一時検証コードの型推論エラー2件を明示型で修正し再起動。全検証完了、main保存内容は一致 | 6分19秒 |
| 仕様・報告・差分確認 | PHOSPHOR_CELLS.md / PARAMETERS.mdを更新し検証記録を作成 | 下記の見た目評価は継続 | git diff --check成功、最新game logにエラーなし | 2分3秒 |

## 検証

Godot 4.7.2 / Forward+ / D3D12、HDR2D viewportで実施。検証用SubViewportはruntime内で一時作成し、終了時に解放した。

- **均一入力720条件**: 両Style × row 2/3 × pitch 2/2.5/3/6 × 5組のFill × 9入力。
  Fillは0.90/0.85、0.75/0.75、1/1、0.90/1、1/0.85。
  入力は白1/2/4/8/16、R/G/B単色、gray 0.5。
  各channelの平均誤差は最大0.048828%。単色の別channelへの漏れは0。
  独立した矩形交差計算との最大誤差は0.078125%（分母max(1, expected)）。
  HDR出力peakは85.3125で、1へのclampがないことを確認。
- **2D信号積分32条件**: 両Style × row 2/3 × 4 pitch × 2組のFill。
  X gradient、1pxのY輝度変化、HDR edgeを含む入力を使用。
  入力HDR画像から独立したbilinear samplingと矩形交差を計算し、最大誤差約0.1049%（同じ分母）。
- **Reference / Integrated 24条件**: 変更前shaderと全pixelのRGBを照合し、最大差0。
  Referenceは両Style・Scale 1〜4。Integratedは両Style・4 pitch・2 / 4 samples。
- **全pitch・画面端164条件**: 全41 pitch（2.0〜6.0、0.1刻み）× 両Style × row 2/3。
  幅3840pxの左・中央・右端付近、HDR (16,8,4)、初期Fillで計測。
  最大絶対誤差は0.0422783。最大絶対誤差のpixelはpitch 2.3、row 3、style 7、x3824/y4のRで、期待34.823528に対し実測34.78125（約0.1214%）。
  分母max(1, expected)を用いた最大誤差は約1.0512%。これは上記の最大絶対誤差のpixelとは異なる。
  画面端の小さいcoverageに対する数値誤差は残る。float32の位相計算とHDR画像量子化の寄与が考えられるが、寄与の分離は未実施。
- **小数Canvas移動**: 均一入力で(0.375, 0.625)移動前後の中央pixelを比較し、差0。
- **緑単色の明暗**: pitch 2.0、初期Fill、Stretched VGAで、row 2は約0.9995〜1.0、row 3は約0.9116〜1.1758。
  row 3で、RGB色差に頼らない行方向の明暗構造が現れる。
- **Inspector**: Reference / Integrated / Substrateで使用する項目だけ編集可能。SubstrateのSignal Samplingは編集不可で固定2×2。
- **画像**: CRT testで両Style、既存Integrated、row 2/3、Bloom ON/OFFを比較。
  緑に行方向の明暗が現れる一方、白文字のRGB分離と周期的な模様は残る。
- **CLI / 実行ログ**: shader/scriptの機械的確認とCRT test起動は成功。最新game logはhelper登録のみ。
  OSのroot certificate store警告はCLIに出るが、今回のshader/script変更とは別の既存環境警告。

## 保持した設定

mainのpost_processing.tscnは作業開始前後でSHA256一致:
1D701D5C1E40C27EAE60706B9CDFDC23DC1CDD2E2F3AC1FC0CD1D1536DA3C3FD

作業前のユーザー設定はReference、Triad Pitch保存値4.0。mainは今回のSubstrateへ切り替えていない。
CRT testの既存Triad Pitch 2.0を維持し、新方式と初期Fill・行周期だけを追加した。

## 継続して判断する点

- 素子感が全色で同じになることは保証しない。現状、緑は主に行方向の明暗として見える。
- 平均光量保存は均一入力の完全周期での性質。文字edgeや画面端、変化する入力では入力との平均一致を保証しない。
- HDR補償後の局所peakがBloomやSDR表示のchannel clippingへ与える見た目は、最終採用前に確認が必要。
- 初期Fillでの比較後、必要な場合だけInspectorから調整する。
- 動く高contrast信号のmoire / shimmer、GPU profiling、全CRT + Bloomの1080p / 2160p比較は未実施。
- Optical Spreadは今回追加していない。

参照: [Godot Shading Language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html)。

