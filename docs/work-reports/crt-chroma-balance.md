# CRT Chromaの色の偏りを修正

作業日: 2026-10-01（JST。時間記録はUTC）
対象: `CRTDisplayExperimental` のNoise / Chroma

この報告はRGBの振幅を揃える修正の記録。
その後、ユーザーから「赤と緑が目立ち、青いノイズが見えない」と指摘があり、数値上の釣り合いだけでは見た目の問題を解決できていないと確認した。
現在の仕様と実際の設定での比較は [Oklabでの再修正](crt-chroma-perceptual.md) を参照。

## 変更と理由

旧式はRGBノイズから輝度の重み（0.2126 / 0.7152 / 0.0722）で求めた値を全色へ引いていた。
この式はpixelごとの輝度を保つが、緑の振幅が小さくなり、赤・青の粒が強く見える。
さらに暗部で負のRGBを0へ切ると、赤・青の増加が強く残って平均の色も赤紫へ寄りやすい。

新式は3色の単純平均を引く。

`chroma = noise.rgb - (noise.r + noise.g + noise.b) / 3`

共通のRGB成分を取り除き、RGB各色の振幅を統計的に揃える。
pixelごとの輝度維持は強制せず、色の粒による明るさの変動を許容する。
Chroma Strengthの初期値・範囲はそのままで、以前より緑の揺れが大きくなる。

変更はChromaの生成式と説明に限定した。
Noiseの有効化、Size / Softness / Rate、Lumaの式、pass配置は維持する。

## 検証

Godot 4.7.2 / Forward Plus / Direct3D 12 / HDR 2Dで旧式と新式を同じ粒の配置で描画した。
比較設定はLuma = 0、Chroma = 0.1、Size = 1.5、Softness = 0.6、Rate = 0。
512×512の4区画で描画し、各区画の192×192pixelを集計した。

| 測定 | 旧式 R / G / B | 新式 R / G / B |
| --- | --- | --- |
| linear灰色0.25のRGB標準偏差 | 0.02570 / 0.00875 / 0.02906 | 0.01970 / 0.01978 / 0.01991 |
| 黒の平均RGB | 0.000404 / 0.000138 / 0.000442 | 0.000314 / 0.000313 / 0.000304 |
| HDR色4 / 2 / 0.5のRGB標準偏差 | 0.07608 / 0.02584 / 0.08544 | 0.05812 / 0.05845 / 0.05853 |

灰色での最大・最小振幅比は約3.32から約1.01へ減少した。
黒でも各色の平均が近づいた。有限範囲の乱数なので完全には一致しない。
灰色の輝度標準偏差は約0.000045から約0.01161へ増えた。これはChroma = 0.1での値。

- Godot CLIのGDScript check-only成功。実描画でshaderのcompileと実行を確認。
- HDR値が1を超える状態を維持し、検査したpixelは全て有限値だった。
- 両Strength = 0のshaderと、Noiseを通さない画像のRGB最大差は0。
- Rate = 0は150ms後もRGB最大差0。
- Resourceの変更は遅延signalの反映後に確認。両Strength = 0とEnabled OFFでColorRect / BackBufferCopyを無効化でき、Chromaだけ再有効化して強さ0.02も反映できた。
- 実際のCRT test sceneに新shaderが適用されていることを確認し、同じ実画像・既存の複合効果で比較画像を保存した。
- 一時検証ノードを全て解放。元Sceneの画像選択は-1のまま。開始時の停止状態へ戻した。
- 最終の再起動runは起動エラーとgame logのerrorがなく、editor Loggerにも新しいentryがなかった。既存Debugger履歴は消去していない。

### 比較画像

| 対象 | 旧式 | 新式 |
| --- | --- | --- |
| テスト色。左上: 灰色 / 右上: 黒 / 左下: HDR / 右下: 緑 | [画像](crt-chroma-balance-images/panels-old.png) | [画像](crt-chroma-balance-images/panels-new.png) |
| 実画像の顔周辺 | [画像](crt-chroma-balance-images/detail-old.png) | [画像](crt-chroma-balance-images/detail-new.png) |
| 実画像の暗部 | [画像](crt-chroma-balance-images/dark-old.png) | [画像](crt-chroma-balance-images/dark-new.png) |

実画像の比較は1920×1080の描画から原寸で切り出した。
maskとBloom等も有効なので、ノイズの色の釣り合いには灰色・黒のテスト色と統計を併用する。
画像はHDR画素をColor単位でsRGBへ変換してRGBA8へ保存した。
全画素統計と切り替え検証は [verification.json](crt-chroma-balance-images/verification.json) に保存した。

## 残る性質

- Chromaは明るさにも影響する。LumaとChromaは個別に0で切り替えられるが、Chromaの見た目が輝度から完全に独立するわけではない。
- 暗部は負の値のclampにより平均明るさが上がる。今回の修正はRGB間の釣り合いを改善する。
- 元のRGBが非対称な飽和色では、clampされる成分も非対称なので色味が変わる場合がある。
- RGBの振幅を揃える方式であり、人間の知覚上で全ての色相が同じ強さになることを保証する方式ではない。

## 変更ファイル

- `presentation/post_processing/effects/crt_display_experimental/crt_noise.gdshader`：Chromaの重みを各色1/3に変更、理由をコメント。
- `presentation/post_processing/effects/crt_display_experimental/crt_display_experimental.gd`：Chromaの説明を更新。
- `presentation/post_processing/effects/crt_display_experimental/PARAMETERS.md`：新式と明るさへの影響を記載。
- `docs/work-reports/crt-noise.md`：旧式の記録であることと本報告へのリンクを追記。
- 本報告と比較画像・検証値。

## 工程と所要時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・変更 | 前回答で確認した偏りを踏まえ、単純平均の式へ変更。説明を更新 | なし | RGB各色の振幅を揃える仕様を実装 | 2分22秒（12:52:14〜12:54:36 UTC） |
| 検証 | CLI、同一配置の旧新比較、RGB統計、HDR、無効化、実画像、起動確認 | 非対称な元RGBではclampによる色味変化が残る | 比較画像のHDR形式変換ミスを修正。遅延signalの反映前に判定した検証を修正。統計の集計をscalar floatへ変更して丸め誤差を抑えた | 8分57秒（12:54:36〜13:03:33 UTC） |
| 記録・片付け | 比較画像・検証値・作業報告を保存、ゲーム停止 | なし | 一時ノード解放、開始時の停止状態へ復帰 | 1分58秒（13:03:33〜13:05:31 UTC） |

合計: 13分17秒（12:52:14〜13:05:31 UTC）。

