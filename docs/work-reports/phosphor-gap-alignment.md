# Phosphor Gap Alignment

記録日: 2026-10-01（日本時間）。
計測開始: 2026-10-01 08:35:25 UTC。集計: 2026-10-01 08:43:28 UTC。
実測合計: **8分3秒**（報告保存直前まで。調査・ツール待機を含む）。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 前提確認 | AGENTS.md・関連docs・session・既存変更・実行中設定を確認 | なし | 保存値Brightness 0.7と実行中0.5の違いを確認し、Runtime値を控えた | 1分10秒 |
| 実装 | SubstrateにGap Alignmentを追加。横triadの位相を0/0.5pxで切り替える | なし | 既存配置を初期値にして、GapとRGB全体をstaggerごとずらせるようにした | 0分30秒 |
| 検証 | CLI、均一HDR、信号積分、変更前一致、Inspector、画像比較 | 部分Gapの色分離、SDR飽和、motion時の主観評価 | 両Styleで黒pixelとRGB平均を確認。既存配置・他modeは完全一致 | 3分38秒 |
| 仕様・記録 | PARAMETERS.md / PHOSPHOR_CELLS.md更新、比較後のRuntime設定復元、差分確認 | 最終的な配置の採用判断 | Brightness 0.5・Gap 0.5・画像index 0まで復元。保存Sceneは編集しない | 2分45秒 |

## 使い方と範囲

CRT ResourceのPhosphor CellでCell SamplingをSubstrateにし、Gap Alignmentを選ぶ。

- Pixel Boundary: 既存配置。初期値。
- Pixel Center: 横triad全体へ0.5 output pxの位相を加える。
- Horizontal Gapの幅は従来どおり0〜1px、step 0.05。
- pitch 2/4/6ではGap中心がpixel中央に一致する。fractional pitchでは全Gapがpixel中央に一致する保証はない。
- Gapだけを独立移動せず、RGB apertureを含むtriad全体を移動する。
- rowごとのhalf-triad staggerは維持。Vertical Gap、Row Pitch、光量補償、Signal samplingは変更しない。
- Legacy / Reference / Integrated / Envelopeでは編集不可で、描画への影響なし。
- mainとCRT testの保存Sceneは今回編集していない。既存のユーザー調整を維持。
- Beam / Signal Reconstruction / Phosphor Bloomの算法を変更しない。

## 検証結果

Godot 4.7.2 / Forward+ / D3D12 / HDR2D。

- Godot CLIのheadless Editor起動・終了成功。script / shader parse errorなし。OS root certificate storeに関する既存エラーは出る。
- **均一HDR 216条件**: 両Style × pitch 2/4/6 × 両Alignment × H Gap 0.5/1 × 9入力。Row Pitch 3、V Gap 1、Brightness 1。
  入力は白1/2/4/8/16、R/G/B単色、gray 0.5。
  RGB平均の最大相対誤差 **0.065106%**、別channel漏れ **0**。
  独立した矩形交差計算との最大component誤差 **0.086806%**（分母max(1, expected)）。
  Pixel Center・H Gap 1の黒pixelは、HDR 16を含め最大残差 **0.000020564**。
- **非均一信号12条件**: 両Style × pitch 2/4/6 × 両Alignment。
  X gradient、1pxのY輝度変化、HDR edgeを含む入力で、独立CPUのbilinear sampling × 矩形coverageと照合。
  最大誤差 **0.089046%**（同じ分母）。
- **変更前一致28条件**: Pixel BoundaryのSubstrate 12条件、Reference 4、Integrated 8、Envelope 4。
  変更前shaderと全pixel RGBが完全一致、最大差 **0**。
  他modeではGap AlignmentをPixel Centerにしても影響しないことを確認。
- Inspectorの表示はPixel Boundary:0 / Pixel Center:1。Substrateのみ編集可能で、他3modeはread-only。
- 画像モードでBoundary・Gap 0.5、Center・Gap 0.5、Center・Gap 1を比較。
  一時画像はGodotのユーザーディレクトリへ保存し、project資産には追加していない。
- 比較後、実行中の3effect、Brightness 0.5、Gap 0.5、Pixel Boundary、画像index 0を保持。
  保存SceneのBrightnessは作業前からの0.7のまま。Runtime調整をSceneへ勝手に保存していない。
- 一時検証SubViewportは終了時に解放。
- 最新game logはhelper登録のみ。git diff --check成功。

## 判断が残る点

- Gap 1・Pixel Centerでは黒い境界が明確になる一方、細線・文字や発光面積にも影響する。
- Pitch 2・Gap 0.5・Pixel Centerでは、白の局所的な緑／マゼンタ色差が強くなる。
- Bloom前に黒くても、Bloom ONでは周辺光がGapへ入る。これは今回変更していない。
- HDR平均の保存は、SDR出力時の色飽和が解決したことを意味しない。
- 全CRTの1080p/2160p比較、motion時のmoire / shimmer、GPU profilingは未実施。
- 今回は比較切替を用意した段階で、Pixel Centerを最終採用したわけではない。

