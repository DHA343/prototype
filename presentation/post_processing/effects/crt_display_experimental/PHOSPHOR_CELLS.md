# Cell Emission

## 構成

CRT ResourceのMask ModelをCell Emissionへ設定して使用する。対応PatternはStaggered RGBとStaggered RGB (Row Pairs)。
Signal / Scanline（pass 0）→ Cell Emission（pass 1）→ Optical Spread（pass 2）→ Phosphor Bloom（pass 3）→ Noise（pass 4）の順。

Mask Redistributionはpass 0でmaskを適用し、pass 1を止める。
Cell Emissionではpass 0は再構成信号をそのまま渡し、pass 1でaperture発光を計算する。
同じ配置でも、入力samplingと明るさへの応答は両Modelで異なる。
Cell専用のSubViewportは追加しない。Optical SpreadとBloom Coreにも同じ設定が反映される。

## Geometry

- Triad Pitch：2.0〜6.0出力px、初期値2.5。各R/G/Bの発光幅は等しい。
- Row Pitch：1〜4出力px、初期値3。整数pixel境界に整列する。
- Mask Pattern：Staggered RGBは毎row、Staggered RGB (Row Pairs)は2rowごとに半triadずらす。配置計算は共通。
- Horizontal Gap：0〜1出力px、初期値0。triad両端へ等分し、RGB内部には隙間を作らない。
- Vertical Gap：0〜1出力px、初期値0。row上下へ等分する。
- Gap Alignment：Pixel Boundary / Pixel Center。横triad全体を0 / 0.5pxへ移す。
- 共通関数は `rgb_aperture.gdshaderinc`。出力座標に固定し、解像度で自動換算しない。
- 小数境界を整数へ丸めない。矩形のcoverageを解析計算し、soft edgeは後段のOptical Spreadで調整する。

全samplingが同じGeometryを使う。横samplingでも両GapとAlignmentを編集できる。
Row Pitchが整数なので、各output pixelの範囲は1つのCell row内に収まる。
Inspector範囲外のGapは負値を0、発光幅・高さの下限を0.001pxとして扱う。

## Sampling

| Cell Sampling | 入力位置 | coverageの区間 | 見た目への影響 |
| --- | --- | --- | --- |
| Horizontal 4 | X ±0.125 / ±0.375px、Y中心 | 横4 × 縦1 | 横方向の信号とapertureの積を細かく近似する |
| 2x2 | 両軸±0.25px | 横2 × 縦2 | Y方向にも狭い入力平均が入る |

各区間のX coverage × Y coverageを解析計算し、区間中心からHDR信号をbilinear samplingする。
発光は `sum(input_rgb(sample) × coverage)`。coverageに区間面積が含まれるためsample数で再度割らない。
apertureは解析積分だが、変化する入力との積は区間中心を使った近似となる。

2x2では入力に縦平均1/8・3/4・1/8が加わり、Horizontal 4には加わらない。
横方向に均一な1px水平線はHorizontal 4で中心約1、2x2で中心約0.75・上下約0.125になる（Gap 0、入力平均の作用、HDR丸めあり）。
この差はCellとSignalのsamplingに関するもので、走査線の濃淡やOptical Spreadの強度ではない。

## 光量と強度

共通gainは `3 × pitch × row / ((pitch − H Gap) × (row − V Gap))`。
各RGBの同じ占有面積を補償する。Gapが両方0なら数学上の倍率は3となる。
完全な周期の均一入力で平均RGBを保つ。HDR clampや別channelへの光量再配分はしない。

Mask Strengthは再構成信号と、正規化したCell emissionの混合比。
0はmask適用前のSignal / Scanline出力、1はCell emission。中間は両者をmixする。
Brightness Compensationを混合後に一度だけ掛け、Strength = 0でも維持する。
範囲0.25〜6、初期値1。初期Mask Strengthは0.5。

Strength = 0ではaperture samplingを省く。共通gainを出力するためColorRectとBackBufferCopyは維持する。
入力のHDR RGBは1でclampせず、画面テクスチャの中心alphaを保持する。
透明Sceneのalphaは画面コピー側の制約がある。

## 整理・移行

Reference、旧Integrated / Substrateの別mode、旧propertyの読取aliasは残さない。
Horizontal 2とMixed Pixel Patternも実装ごと削除した。

| 整理前の設定 | 現在の設定 |
| --- | --- |
| Staggered RGB＋Stagger Rows 1 | Staggered RGB（ID 0） |
| Staggered RGB＋Stagger Rows 2 | Staggered RGB (Row Pairs)（ID 1） |
| Horizontal 2（ID 0、旧初期値） | Horizontal 4（ID 1、現初期値） |
| Horizontal 4 / 2x2 | 同じID 1 / 2を維持 |
| Cell Brightness＋Brightness Compensation、Cell使用中 | 積をBrightness Compensationへ保存 |
| Cell Brightness、Redistribution使用中 | 使用されていなかったため削除し、Brightness Compensationを維持 |
| Mixed Pixel Pattern | 削除。プロジェクト内の保存Resourceには使用箇所なし |

プロジェクト内の保存Resourceを確認し、mainのStagger Rows 2をPattern ID 1へ移した。
二つの明るさ倍率を非初期値で使う保存Resourceはなかった。
CRT testはCell Emission / Staggered RGB / 2x2、pitch 2 / row 3、Gap 0 / 0、Alignment 0.5px、Mask Strength 1。
現在のScene保存値を優先している。別途保存した旧Resourceは上表に沿った移行が必要。
Horizontal 2→4は同一出力ではなく、横方向に変化する入力とapertureの積の近似精度を変える。

## 検証と制約

今回の検証は[Mask設定整理の作業報告](C:/GameDev/Projects/prototype/docs/work-reports/crt-mask-parameter-simplification.md)を参照。
旧Integrated / Substrateの実装時の検証は過去の作業報告に保存されている。現在のUI仕様ではない。

小数pitchの周期的な色変動やSDR表示での局所HDR飽和は、この整理で解決していない。
Geometryを大きくするとRGBの分離と規則性が増える。Gapを広げると局所peakとBloomへの入力も増える。
sampling選択は最終使用時の解像度・倍率で確認する。2x2が全ての入力で優れるという扱いはしない。
