# crt_test の見た目の評価

評価日: 2026-10-01（日本時間）。対象: `crt_display_test.tscn` と `CRTDisplayExperimental`。
計測区間: 08:59:21〜09:15:31 UTC。実測合計: **16分10秒**（この記録の保存直前まで）。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 前提・実装調査 | AGENTS.md、Shader/GDScript/Godot AI docs、Scene、各Pass、一次資料を確認 | 再現対象の機種は未指定 | 機能の数ではなく、通常の画面で見える差を評価軸に設定 | 2分41秒 |
| Runtime確認・比較方法 | 対象session、実行中の値、HDR framebuffer、保存済み値を確認 | Runtimeの設定は評価中にも変わった | 保存済み設定を比較基準として固定。HDR画像をsRGBへ変換して取得 | 3分34秒 |
| 比較・分析 | 複製Resourceと一時SubViewportで既存設定の比較。原寸crop、白領域の画素、暗部を確認 | 動画・実機との一致・2160p・表示機器ごとの差は未評価 | オフスクリーン描画をUPDATE_ALWAYSへ修正。黒つぶれと模様の周期を確認。一時Viewportを全解放 | 8分31秒 |
| 整理・報告 | 見た目への影響、改善優先度、代替方針、評価限界を整理 | 最終的な見た目の採用判断 | 実装ファイルと既存Runtime effectは変更せずに評価 | 1分24秒 |

**評価: 静止画のCRT表現に必要な主要部品は揃っている。一方、現在は蛍光体の模様、色ずれ、強い黒つぶれが目立ち、発光面として自然にまとまる部分に改善の余地が大きい。**

数値の総合点は付けない。家庭用TV、RGBモニター、VGAモニターで、適切な走査線・マスク・ぼけの強さが変わるため。

## 評価した設定

保存済みSceneを基準に、次の値で比較した。

- Stretched VGA Phosphor / Substrate。
- Triad Pitch 2px、Row Pitch 3px、Horizontal Gap 0.5px、Vertical Gap 1px。
- Gap AlignmentはPixel Boundary相当。Sceneの保存表記はnullだが、比較では0を明示。
- Phosphor Brightness 0.5、Beam Width 1.0、Scanline Count 360。
- Sharpness 0.5、Signal Pitch 2px。
- Bloom: Near 4px / 0.1、Far 32px / 0.05、HDR Limit 16。
- 前段ColorGrading: Brightness -0.06、Contrast 1.11、Saturation 1.08、Gamma 1。
- 前段ChromaticAberration: Horizontal、Amount 2px。

接続したsessionは `prototype@ac44aa013f38c16e`、Godot 4.7.2 / D3D12 / HDR2D。実行画面は1515×852px。
Runtimeは当初Wide Grille / Legacy Mask Strength 1、その後Stretched VGA Phosphor / Reference / Brightness 1へ変わっており、保存済みSubstrate設定とは異なる。評価中の変更をこちらからSceneへ保存していない。

比較入力はSceneの画像配列の最初の画像。元のRuntimeに対してパラメータの書き換えやキー入力は行わず、独立したWorld2D、一時SubViewport、複製したeffectで比較した。
1515×852の各比較と1920×1080の基準設定を描画。1080pは描画成立の確認に留まり、解像度間の見た目の一致を保証する比較ではない。

## 主要要素と見た目

| 要素 | 現状 | 見た目としての評価 |
| --- | --- | --- |
| 横方向の信号のぼけ・補間 | あり | デジタルな輪郭を柔らかくする役割は満たす。現在のkernelのFWHMは約4出力pxで、小さい文字・細線にはかなり効く。RGB/輝度/色差を区別する帯域制限はない |
| 走査線・ビーム | あり。ただし固定幅 | Beam Width 1では均一信号に対する隣接ビームの合計が一定になる。ベタ面の横縞は主にSubstrateの行構造であり、信号の走査線の明暗とは分けて評価する必要がある |
| RGB蛍光体・非発光部 | あり | 素子感は強い。Triad 2pxの各発光channel幅は0.5pxで、個々のRGB形状をそのまま分離表示できる密度ではない。細部の形状追加より、画素へ混ざった最終色の安定性が重要 |
| 周囲へ広がる光 | Near/Far Bloomあり | 輪郭のにじみ、明るい部分のhaloは表現できている。大きな半径を増やすより、素子の局所的な色分離をどう混ぜるかの方が今は重要 |
| 階調・明るさの応答 | 色補正とBloom sourceのHDR制限あり | 暗部の損失が大きい。BloomのHDR LimitはCore全体の最終出力を圧縮するものではなく、局所peakのSDR飽和も残る |
| 明るさに応じたビームの太さ | なし | 暗い線が細く、明るい線が太くなる変化が不足。単に黒い横線を増やすより、立体感と発光感を改善できる余地がある |
| ガラス面・曲面・端の形状 | なし | TVという物体を感じさせる効果は出せる。ただし平面CRTや画面部分だけを表現する場合は必須ではない |
| 残光などの時間変化 | 履歴を使った処理なし | 動く輝点などで差が出る候補。今回の入力は静止画なので、追加効果の大きさと動作中のちらつきは未評価 |

一般的なCRT shaderでも、走査線・蛍光体マスク・ぼけが中心で、曲面やhaloは選択する特性として扱われる。[LibretroのCRT shader解説](https://docs.libretro.com/shader/crt/)

## 改善の優先順位

1. **暗部の階調を戻す — 見た目への影響: 大。**
   現在のColorGradingでは、無彩色のlinear入力Lは `1.11L - 0.1216` になり、約0.10955以下が黒へ潰れる。sRGB入力換算では約0.365以下の範囲に相当する。これはCRTの必須特性ではなく現在の調整の結果。Brightness 0 / Contrast 1 / Saturation 1の比較では服の陰影が戻った。まず中立値を出発点にし、黒の締まりを階調を残すカーブで調整するのが有効。

2. **蛍光体を自然に混ぜ、SDRでの色とpeakを安定させる — 大。**
   現在のSubstrateは、細かいRGB構造と行構造が強く出る。白領域でも隣接画素の色差が大きい。占有率補償でlinear HDRの平均を保っても、最終SDRで高いchannelが飽和すれば見かけの色は保てない。Phosphor Brightness 0.5でも、設定上の局所peakは白入力に対して最大約1.5倍となり得る。Near/Far Bloomだけに任せず、Cell全体へのごく狭い光学的な広がり、最終出力の緩やかなpeak圧縮、Gap・mask contrastの抑制を候補とする。追加実装案は今回未検証。

3. **輝度によってビーム幅を変える — 中〜大、期待値。**
   暗部は細く、明部は太くすることで、明るさと発光面の面積が連動する。現状の固定Beam Width 1→0.85だけの変更は、強いSubstrate模様の中では差が比較的小さかった。固定値の調整だけで大幅な改善が得られるとは評価しない。こうした輝度依存の幅は[MAMEのScanline Variation](https://docs.mamedev.org/advanced/hlsl.html)や[CRT-beansのspot size](https://github.com/libretro/slang-shaders/blob/master/crt/shaders/crt-beans/docs/parameters.md)でも扱われる。

4. **解像度・表示倍率に対する安定性を整える — 条件によって大。**
   Scanline Countは画面全体で360本、Cellは2×3出力px、信号の横幅も出力px基準。解像度を変えた際、すべてが同じ比率では変化しない。360本への縦samplingにはbilinear補間があるが、縮小footprint全体を平均するprefilterはないため、細い横線などはaliasingの候補。動く細線、gradient、非整数表示倍率を最終的な使用サイズで確認する必要がある。

5. **色ずれを控えめにする — 中以下、局所的。**
   現在はR/G/Bが画面全域で水平にずれ、赤と青の相対距離は4px。Amount 2→0.5では目や輪郭の分離が減るが、画面全体の差はCell方式の変更より小さい。状態のよいCRTを狙うなら0〜0.5pxから検討し、必要なら端だけ弱くずれる形を候補とする。大きな全域ずれは劣化した画面の演出としては使える。

## 比較結果と既存の代替案

| 比較 | 見た目の差 | 判断 |
| --- | --- | --- |
| ColorGradingを中立へ | 暗い服の階調が戻る | 優先度が高い |
| Substrate → Integrated | Cellの横方向の細かさを保ちつつ、行のGapによる模様が弱まる | 現行の構成を活かす比較候補 |
| Amount 2 → 0.5 | 輪郭の色分離が減る | 全体を大きく変える変更ではない |
| Beam Width 1 → 0.85 | 一部に走査線の明暗が加わる | 現在のCell模様が強く、単独での差は小さめ |
| Bloom OFF | 素子の分離と輪郭が硬くなる | 今のBloomには有効な役割がある。さらに広くすることは第一候補ではない |
| Aperture Grille / Strength 0.5 / Beam 0.85 / Amount 0.5 | 模様の主張が弱く、画像の形が読み取りやすくなる | 複数項目を変えた方向性の比較。明るさも変わるため純粋なmask形状だけの比較ではない |

方向性としては次の三つがある。

- **RGB接続のきれいなCRT**: 輝度依存ビーム、控えめなgrille、狭いにじみ、素直な階調。現在より絵が読みやすい方向。[CRT-aperture](https://docs.libretro.com/shader/crt/#crt-aperture)が見た目の参照候補。
- **細かい蛍光体が見えるVGAモニター**: 現行Cellを活かし、強い黒線よりも細かい粒と色のまとまりを優先。Integratedや弱いEnvelopeを比較する価値がある。Envelopeを弱めた画像の比較は今回は未実施。
- **家庭用TVの柔らかい画**: 輝度より色差を広くぼかす信号モデルを組み合わせる。色の境界が柔らかくなり、pixelやditherが混ざる。これは接続方式を含む見た目で、CRT本体だけの必須要素ではない。[GTUの解説](https://docs.libretro.com/shader/crt/#gtu)が参照候補。CRT-Royaleもbeam・mask・光の広がりを組み合わせる参照になるが、移植だけで自動的に理想の見た目になるとは評価しない。

曲面、vignette、反射はTVとしての雰囲気を強めるが、現在の画質上の問題の解決にはならない。ノイズ、揺れ、長い残像は劣化や接続条件の演出として扱い、必須項目には数えない。

## 原寸の比較画像

チャットやブラウザーでの縮小表示は、細かい周期模様にmoireを発生させる場合がある。以下のcropは原寸360×240px、暗部は280×240px。白領域の画素を確認すると横2px・縦3pxの周期が中心で、プレビューに見える広い斜め縞をそのままshaderが出力したと断定しない。

元画像:

![元画像crop](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/source-crop.png)

保存済み設定:

![Substrate基準crop](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/saved-baseline-crop.png)

Integrated:

![Integrated crop](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/integrated-crop.png)

控えめなAperture Grille案:

![Aperture Grille crop](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/simpler-grille-crop.png)

現在の暗部:

![現在の暗部](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/saved-baseline-dark-crop.png)

ColorGradingを中立にした暗部:

![中立補正の暗部](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/neutral-grading-dark-crop.png)

その他の比較: [色ずれ0.5px](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/ca-reduced-crop.png)、[Beam 0.85](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/beam-085-crop.png)、[Bloom OFF](C:/GameDev/Projects/prototype/docs/work-reports/crt-visual-evaluation-images/bloom-off-crop.png)。

## 評価の限界

- フレーム履歴を使う残光、moving signalのmoire / shimmer、実機の動きの見え方は今回評価していない。
- 実機写真との撮影条件を合わせた比較はしていない。画像の印象とソースからの評価であり、特定機種の再現精度の測定ではない。
- PNGはGodot AIのcaptureと同じくHDR readbackをRGBA8へ変換してsRGB化。1を超える値のclipと暗部の量子化を含み、表示装置のHDR出力を測る資料ではない。
- 評価用PNGをImage.load_from_fileで読んだ際にexport時の読み込み方法に関する警告が出た。恒久的なゲーム用loadコードは追加していない。スクリーンショットはGodot importの対象外にする。
- 一時SubViewportはすべて解放済み。実装の変更・保存、元のeffectへのパラメータ書き込みは行っていない。

参照コード: [Beamと信号](C:/GameDev/Projects/prototype/presentation/post_processing/effects/crt_display_experimental/crt_display_experimental.gdshader:155)、[Substrate](C:/GameDev/Projects/prototype/presentation/post_processing/effects/crt_display_experimental/phosphor_cells.gdshader:124)、[Bloom合成](C:/GameDev/Projects/prototype/presentation/post_processing/effects/crt_display_experimental/phosphor_bloom.gdshader:89)、[色補正](C:/GameDev/Projects/prototype/presentation/post_processing/effects/color_grading/color_grading.gdshader:26)。
