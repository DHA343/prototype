# CRT Mask / Cell統合

実施日：2026-10-02（JST）。2026-10-01 23:59:16〜2026-10-02 00:37:21、合計38分05秒。
対象：Godot 4.7.2 / CRTDisplayExperimental。

## 採用した方針と変更

ユーザーが選んだA「共通Cell配置＋Horizontal 2 / Horizontal 4 / 2x2」を実装した。
Integrated / Substrateのsampling差を残し、Geometry・Gap・正規化・発光計算を共通化した。
Referenceは関数・uniform・Cell Scaleを含めて削除し、内部用の描画方式や互換aliasも残していない。

Mask Styleに混在していた配置と描画モデルを分離した。

| 項目 | 新しい選択肢・意味 |
| --- | --- |
| Mask Model | Mask Redistribution / Cell Emission |
| Mask Pattern | Staggered RGB / RGB Pixel Pattern / Green / Magenta Stripes / Mixed Pixel Pattern |
| Stagger Rows | 毎row / 2rowごとに半triadずらす。旧Stretched VGA / VGAを置き換える |
| Cell Sampling | Horizontal 2 / Horizontal 4 / 2x2 |
| Mask Strength | 両Model共通。0でmaskの模様を除き、1で完全に適用する |
| Cell Brightness | Cell Emission混合後の明るさ倍率。旧Phosphor Brightness |
| Horizontal / Vertical Gap | 全Cell Samplingで使用可能。新規Resourceの初期値は0 / 0 |

旧Dotsは丸い蛍光体ではなくRGBと黒のpixel配置なのでRGB Pixel Patternへ変更した。
旧Aperture Grilleは緑とマゼンタの縦stripeなのでGreen / Magenta Stripesへ変更した。
旧Slot MaskはMixed Pixel Patternへ変更して残した。実際のslot状apertureを計算するモデルではないため、形状を誤認させる名称を外した。
Cell Emissionの対応PatternはStaggered RGB。Modelを切り替えるとそのPatternが選ばれ、非対応Patternは編集できない。

新規のMask Strengthは0.5。既存のCell Resourceには旧出力を維持するため1を保存した。
Strength = 0でもCell BrightnessとBrightness Compensationは維持し、Optical Spread / Bloom / Noiseはそれぞれの設定に従う。
Cellの模様だけを無効にしたとき、共通の明るさ倍率を維持するためCell passの画面コピーは残る。apertureの計算は省略する。

## Samplingの見た目の違い

| Sampling | 入力の採り方 | 判断の目安 |
| --- | --- | --- |
| Horizontal 2 | 横±0.25px、縦はpixel中心 | 縦の細部を維持する基本候補 |
| Horizontal 4 | 横±0.125 / ±0.375px、縦は中心 | 横方向の入力とRGB apertureの積を細かく近似する。単純な追加blurとは異なる |
| 2x2 | 横・縦とも±0.25px | 縦方向にも狭い平均が入り、細い横線や斜め輪郭が少し柔らかくなる |

Geometryのcoverageは矩形との交差を解析計算する。
変化するHDR入力とcoverageの積は区間中心のsamplingで近似する。
Gap = 0・同じ位相なら、Horizontal 2 / 4はそれぞれ旧Integratedの2点 / 4点に、2x2は旧Substrateに相当する。

独立した1px横線の検証では、Horizontal 2 / 4は中心約1、2x2は中心約0.75・上下約0.125となった。
これは走査線の濃淡を増やす変更ではなく、入力の縦平均の差である。

現在のCRT testを複製し、Samplingだけを切り替えた実画像の比較も保存した。
1920×1080出力から同じ500×360領域を切り出した。Noiseは複製側でも無効。
既存のSignal / Optical Spread / Bloomによって入力が既に柔らかくなっているため、この画像での差は小さい。
Horizontal 2 / 4は非常に近く、2x2は輪郭がわずかに柔らかい。
現在のRGB配置が持つ規則的な模様は3方式とも残る。この整理だけでは、その模様を不規則な粒感へ変えない。

| Horizontal 2 | Horizontal 4 | 2x2 |
| --- | --- | --- |
| ![Horizontal 2](C:/GameDev/Projects/prototype/docs/work-reports/crt-mask-cell-unification-images/horizontal-2.png) | ![Horizontal 4](C:/GameDev/Projects/prototype/docs/work-reports/crt-mask-cell-unification-images/horizontal-4.png) | ![2x2](C:/GameDev/Projects/prototype/docs/work-reports/crt-mask-cell-unification-images/area-2x2.png) |

## 保存Resourceの移行

| Scene | Model / Pattern | Stagger | Sampling | Strength | Gap H / V | Cell Brightness |
| --- | --- | --- | --- | --- | --- | --- |
| main/main.tscn | Mask Redistribution / Staggered RGB | 2 | 2x2（このModelでは無効） | 0.8 | 0 / 0.75（無効） | 1 |
| post_processing.tscn | Mask Redistribution / Green / Magenta Stripes | 1（このPatternでは無効） | 2x2（無効） | 1 | 0 / 0.75（無効） | 1 |
| crt_display_test.tscn | Cell Emission / Staggered RGB | 2 | 2x2 | 1 | 0.5 / 0.5 | 0.7 |

CRT testの旧Substrate初期Gap 0.5 / 0.5は明示保存し、新規初期値0 / 0へ変わっても見た目を維持するようにした。
3 Sceneの編集前後を比較し、CRT Resource block以外の内容が一致することを確認した。
プロジェクト内の保存済みCRT Resourceは移行済み。外部に保存した旧Resourceの自動移行機能は追加していない。

Inspectorでは「Mask → Mask Model」を選び、Cell Emissionの場合は「Cell Emission → Sampling」で3方式を比較できる。
SignalのSharpness / Signal Pitch / Vertical Blur、Scanline、Spread、Bloom、Noiseの処理には変更を加えていない。

## 検証

詳細値は[verification.json](C:/GameDev/Projects/prototype/docs/work-reports/crt-mask-cell-unification-images/verification.json)へ保存した。

| 確認 | 結果 |
| --- | --- |
| Godot CLIのGDScript check-only | 終了コード0 |
| 実際のGPU描画で旧方式と比較 | 42条件すべてで全pixel RGB差0、有限値 |
| 比較の内訳 | Redistribution 10条件、旧Integrated 8条件、旧Substrate 24条件 |
| 共通coverage | 72条件を独立したCPU矩形交差計算と比較。最大誤差0.08681%（分母max(1, expected)）、全値有限 |
| 均一HDR入力の光量 | RGB = 4 / 2 / 0.5に対し、周期領域の平均の最大相対差0.05697% |
| 1px横線 | Horizontal 2 / 4：中心0.99988。2x2：中心0.74988、上下0.12498 |
| Strength = 0 | 3方式とも空間変動0。Cell Brightness 0.7 × Compensation 2の光量を維持 |
| 完全なPostProcessing構成でStrength = 0 | Noise無効で空間変動0、Bloom CoreとのRGB差0 |
| Model変更 / 再構築 | pass切替、Shader parameter更新、Bloom側への再適用を確認 |
| Inspector property list | Model別のPattern制限・sampling / Gapの編集可否・Strengthの両Model編集を確認 |
| Sceneの読込 | main / 共通PostProcessing / CRT testの移行値を確認 |
| 最終Runtime | run token 6のgame logにエラーなし |
| 差分 | git diff --check成功。SceneのCRT以外の内容は一致 |

初回確認で、custom export_enumの型とshader関数引数のuniform名衝突を検出し、修正した。
小数Pitchで旧Integratedとの差が半精度の丸め1段階出たため、Gap = 0の正規化を直接3へ変更し、42条件を再確認して差0とした。
Strength = 0の最初のRuntime比較にはNoiseが含まれていたため、Noiseを無効にして再検証した結果を判定に使用した。
Editorの過去の診断履歴は消去していない。最終成功runの結果と区別する必要がある。
検証用SubViewportは解放し、この作業で開始したRuntimeは停止した。Editorはready。

## 残る課題

- 小数Pitchの周期的な色変動、RGBセルの規則性、SDR表示時の局所的なHDR飽和は未改善。
- Noiseの単調さの調整は、ユーザーの指示に従い後工程へ残した。
- sampling間の優劣は素材と出力倍率に依存する。動画・2160p・GPU処理時間の比較は今回実施していない。

## 工程と所要時間

実時間を記録。検証待ち・調査・記録時間を含む。日付はJSTで10月1日から2日へ跨いでいる。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・設計 | 23:59:16〜00:05:35。共通Geometryと3 Sampling、名称・移行内容を決定 | なし | Model / Pattern / Samplingの役割を分離 | 6分19秒 |
| 初期編集 | 00:05:35〜00:06:33。GDScript・Shader・3 Sceneを編集 | 後続検証待ち | Referenceと重複modeを削除、設定を移行 | 0分58秒 |
| 検証・修正・仕様更新 | 00:06:33〜00:26:10。CLI・GPU・Runtime・Inspector確認と説明更新 | 周期的な色変動・Noise調整 | export型、uniform名衝突、丸め差、Strengthの独立調整 | 19分37秒 |
| 実画像・最終確認・記録 | 00:26:10〜00:37:21。3画像比較、Scene差分、ログ、Filesystem scan、Runtime停止、報告保存 | 動画・2160p・性能比較は未実施 | 既存画像への影響、Scene編集範囲、終了状態を確認 | 11分11秒 |
| 合計 | 2026-10-01 23:59:16〜2026-10-02 00:37:21 | 上記の後工程のみ | 今回選択されたAの実装・移行・必要な検証を完了 | 38分05秒 |
