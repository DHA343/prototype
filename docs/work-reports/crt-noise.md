# CRT: 独立したノイズの追加

作業日: 2026-10-01（JST。時間記録はUTC）
対象: `CRTDisplayExperimental` / `crt_display_test`

この報告の画像・画素統計はノイズ追加直後のChroma式を記録している。
その後、色ごとの振幅の偏りを修正した。現在の仕様と変更前後の検証は [Chroma修正報告](crt-chroma-balance.md) を参照。

## 変更

maskの規則的な配置とは別に粒感を作るため、signal・mask・Bloomの後へノイズのpassを追加した。
明るさと色のノイズを独立して調整でき、粒の間隔・柔らかさ・更新速度も変更できる。
今回の変更はノイズのまとまりで、signal・走査線・maskの式は変更していない。

| CRT ResourceのNoise項目 | 初期値 | 調整 |
| --- | --- | --- |
| Enabled | ON | OFFでNoise passとBackBufferCopyの描画を無効化 |
| Luma Strength | 0.08 | 0〜0.25。明るさの粒感。0でこの成分を無効化 |
| Chroma Strength | 0.006 | 0〜0.1。色の粒感。0でこの成分を無効化 |
| Size | 1.5 px | 1〜8出力px。大きくすると粒が粗くなる |
| Softness | 0.6 | 0〜1。大きくすると粒の境界と振幅が和らぐ |
| Rate | 30 Hz | 0〜60 Hz。0なら粒が静止する |

Luma / Chroma Strengthが両方0の場合もpassと画面コピーを無効化する。
独立した整数hashを画面上の格子へ割り当て、時間tickで更新する。
ノイズtextureや追加SubViewportは使用しない。有効時に全画面passと画面コピーが1つ増える。

明るさのノイズはlinear RGBの輝度へ `sqrt(Y) + 0.02` の応答で加え、元のRGB比率を保つ。
色のノイズは独立したRGB乱数から輝度成分を引いて加える。
HDR値を1でclampしない。ノイズはBloomのCoreへ再描画しない。

## 見た目と調整

初期値は、小さく柔らかい明暗の粒を主に見せ、色の粒を弱く足す設定。
実画像の暗い服や輪郭付近にも粒が加わり、maskだけでは得られなかった不規則さを作れる。
粒を大きくした比較では粗さが強まり、Softnessを上げても大きな塊の存在は残る。

まずEnabledで比較し、Luma Strengthで量を決める。
Sizeを大きくするとmaskを拡大しなくても粒感を増やせるが、粗い加工感も強まる。
その場合はSoftnessとStrengthを合わせて調整する。
Rate = 0は静止画で原因を見分けるためにも使える。

| 比較 | 設定 | 全体 | 顔の切り出し | 暗部の切り出し |
| --- | --- | --- | --- | --- |
| 無効 | Enabled = OFF | [画像](crt-noise-images/image-off.png) | [画像](crt-noise-images/detail-off.png) | [画像](crt-noise-images/dark-off.png) |
| 初期値 | Luma 0.08 / Chroma 0.006 / Size 1.5 / Softness 0.6 | [画像](crt-noise-images/image-default.png) | [画像](crt-noise-images/detail-default.png) | [画像](crt-noise-images/dark-default.png) |
| 大きな粒 | Luma 0.14 / Chroma 0.006 / Size 3 / Softness 0.85 | [画像](crt-noise-images/image-larger.png) | [画像](crt-noise-images/detail-larger.png) | [画像](crt-noise-images/dark-larger.png) |

比較画像はRate = 0に固定した。最終表示は1920×1080。
縮小プレビューではmaskの細かな周期が干渉するため、粒の比較には切り出し画像を原寸で見る。

## 検証

Godot 4.7.2 / Forward Plus / Direct3D 12 / HDR 2Dで確認した。
Godot CLIのGDScript check-onlyは成功。実描画で新しいshaderのcompileと実行を確認した。
再起動後の現在runには新しいgame errorがなく、editorのLoggerにも新しいentryはなかった。
既存のDebugger履歴は消去していない。

- Noise OFFと両Strength = 0でNoiseのColorRectとBackBufferCopyが非表示になる。
- shaderに両Strength = 0を渡した画像と、ノイズを通さない画像のRGB最大差は0。
- Rate = 0の画像は150ms後も最大差0。Rate = 60では粒が更新される。
- Resourceの変更が実行中のshaderへ反映され、Luma / Chroma / Size / Softness / Rateを更新できる。
- Lumaだけの灰色はRGB一致を維持。暖色のRGB比率の差は半精度の丸め程度。
- Chromaだけの灰色は輝度の標準偏差が約0.000045で、明暗の変化が小さい。
- Size = 4でSoftnessを0から1へ変えると、隣接pixel差の平均が約0.01014から0.00827へ減少した。
- HDR色は1を超える値を維持し、検査したpixelにNaN / Infはなかった。
- 1080px高さで6つの位相の1px横線を比較。Noise OFFのピークは約0.333、初期値ONの最小ピークは約0.288。粒による明暗の変化は加わるが、今回の条件で線が消える状態はなかった。
- 一時検証ノードは全て解放し、元のtest sceneの画像選択は-1のまま。元Resourceにも初期値6項目が反映された。

画素統計・pass制御・HDR・alphaの検証値は [verification.json](crt-noise-images/verification.json) に保存した。

### 描画時間

1920×1080の実画像と既存のColorGrading・Chromatic Aberration・CRT・Bloomを組み合わせ、
root / Bloom Core / filterを含む7つのViewportのGPU時間を合計した。
20frameのwarmup後、20frame平均。3条件を同時に描画した短い比較で、端末や設定を変えた性能は保証しない。

| 設定 | GPU平均 |
| --- | --- |
| Noise OFF | 1.900 ms |
| 初期値 | 2.009 ms |
| 大きな粒の比較値 | 2.219 ms |

初期値の増分は約0.109 ms。全条件でViewport数は7のまま、BloomのCoreにNoiseは含まれなかった。
以前の工程とはmask設定等が異なるため、過去の報告値とは直接比較しない。

## 制約

- 負方向の粒を0で止めるので、黒や非常に暗い部分の平均明るさは少し上がる。初期値の黒の平均輝度は約0.000322だった。
- 暗部や飽和色ではChromaもRGBのclampにより輝度へ影響する。
- 最終表示で白く飽和した部分ではノイズの差が見えにくい。
- Softnessは粒の境界だけでなく振幅も弱める。Size = 1で格子とpixel中心が一致するとSoftnessの差は小さい。
- 画面テクスチャのalphaをコピーする。ただし透明HDR SubViewportで元alpha 0.5を描いた検証では、最小の画面コピーshaderだけでもalphaが1になった。既存CRTのNoise OFF / ONもどちらも1で、元Sceneの透明度を保証する機能ではない。
- 今回は画面の最後に加える粒を実装した。信号へ入ってボケるノイズ、時間方向の残光、cell付近の光の広がりは別のまとまりとして残る。

## 変更ファイル

- `presentation/post_processing/effects/crt_display_experimental/crt_noise.gdshader`：ノイズ描画。
- `presentation/post_processing/effects/crt_display_experimental/crt_display_experimental.gd`：独立した6設定、4番目のpassと無効化条件。
- `presentation/post_processing/effects/crt_display_experimental/PARAMETERS.md`：調整方法・式・制約。
- `crt_noise.gdshader.uid`：Godotが生成したshader UID。
- この報告と比較画像・検証値。

## 工程と所要時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・設計 | 既存pass / Bloomとの関係、ノイズの配置・輝度応答・調整項目を整理 | mask再設計・色差にじみ・周辺変化は後続工程 | maskの粒度から独立してノイズを調整する方針を決定 | 10分20秒（12:13:28〜12:23:48 UTC） |
| 実装 | shader、Resourceの6設定、pass制御、parameter説明を追加 | なし | 量・粒度・柔らかさ・静止の比較と実質無効化が可能 | 2分22秒（12:23:48〜12:26:10 UTC） |
| 検証 | CLI、HDR画素統計、細線、切り替え、実画像、GPU計測 | 透明SubViewportの画面コピーalphaは既存pipelineの制約 | 検証scriptの型推論エラーを型指定と再起動で解消。本実装のCLI・描画検証成功 | 14分11秒（12:26:10〜12:40:21 UTC） |
| 記録・片付け | 比較画像・検証値・作業報告を保存し、検証用ゲームを停止 | なし | 一時ノードを解放、開始時の停止状態へ復帰 | 2分19秒（12:40:21〜12:42:40 UTC） |

合計: 29分12秒（12:13:28〜12:42:40 UTC）。

