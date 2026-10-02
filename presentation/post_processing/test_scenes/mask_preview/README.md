# Mask Pixel Preview

`mask_preview.tscn`をGodot Editorで開き、F6で実行する。

- 左にMask前のテスト画像、右に実際のCRT shaderのMask出力を表示する。1マスは1出力pixel。
- Model / Pattern / 段のずれ / Pitch / Row / Sampling / Gap / Strength / Brightnessを切り替える。
- 左右に同じ幅を割り当て、「幅に合わせる」がONなら収まる最大の整数倍率で拡大する。端数の余白は左右に均等に置く。高さが足りない場合は縦にスクロールする。
- 「幅に合わせる」をOFFにすると、表示倍率を4〜64倍で指定できる。最近傍で拡大し、倍率変更では32×24pxの描画解像度を変えない。pixel格子はON / OFF可能。
- pixelにカーソルを合わせると、下部に入力と出力のlinear HDR RGB値を表示する。クリック後は矢印キーでも選択できる。
- 各画像の下には等倍の表示もある。拡大で強く見える規則性が等倍でどう見えるかを確認する。
- 入力は均一なグレー、縦の境界、1px水平線、1px垂直線、RGBの帯、グラデーション。強度0〜2を調整できる。

「入力」はMask処理前の画像を指す。均一なグレーで配置そのものを、細線や境界でMaskによる色の分離・混ざり方を確認する。

RGB Rowsは毎段、RGB Row Pairsは2段ごとに位相を切り替える。「段のずれ」はずれなし／半周期／整数pxの半周期。
整数版は半周期を切り捨てる。Pitch 3なら半周期1.5px、整数版1px。偶数Pitchでは両者が同じになる。
整数版はRGB素子の幅やCellの0.5px開始位相を丸めないため、CMYが必ず消える設定ではない。
RGB Pixel PatternとGreen / Magenta Stripesでは「段のずれ」は無効。

初期Mask設定は、起動時にディスク上のCRT test SceneからResourceを複製して読み込む。
変更はこのプレビュー内だけに反映し、CRT testのResourceやSceneには保存しない。

Mask単体を確認するためSignal / Scanline / Optical Spread / Bloom / Noiseは適用しない。
Maskの式を別実装へ移植せず、`CRTDisplayExperimental`のCore / Cell shaderとparameter転送を直接使用する。

CellではCenterの固定位相を使う。RedistributionとCellは明るさへの応答が異なる。
Redistributionは均一入力のlinear RGBが1になると模様が消えるため、初期の入力強度は0.2。
色の粒を強くしたいときも、まず入力強度0.1〜0.3で比較すると配置の違いを見やすい。
RGB > 1は表示で飽和するが、下部の値では1より大きい発光も確認できる。

32×24pxの領域はすべてのPitchの整数周期を含むとは限らない。領域全体の色の平均を画面全体の色バランスと同一視しない。
