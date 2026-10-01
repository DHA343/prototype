# CRT Chroma: 青い粒の見え方を再修正

作業日: 2026-10-01（JST。時間記録はUTC）
対象: `CRTDisplayExperimental` のNoise / Chroma

## 問題と確認

前回はlinear RGBの数値の振幅を揃えたが、ユーザーから
「ノイズの赤と緑が目立って、青っぽい色が見えない」と指摘された。
数値の釣り合いを直したことだけでは、見た目の問題を解決したとは言えなかった。

現在の実行中Materialのshader codeを調べ、前回の修正済みの式が使用されていることを確認した。
古いshaderがそのまま使われている状態ではなかった。
実際の設定はLuma = 0.08、Chroma = 0.1、Size = 8、Softness = 0.6、Rate = 30。
以前のSize = 1.5の検証だけで、この設定での粒の色の見え方を十分に評価できていなかった。

## 変更

Chromaをlinear RGBへの加算から、Oklab色空間のa / b成分への加算へ変更した。
aは赤緑、bは青黄の変化を扱い、Lは知覚上の明度を表す。
変換式は [Oklab作者の公開実装](https://bottosson.github.io/posts/oklab/) を使用した。

`Lab.ab += grain.yz × Chroma Strength × (Lab.L + 0.02)`

Luma適用後のRGBをOklabへ変換し、a / bへ同じ強さの独立したノイズを加え、linear RGBへ戻す。
Lそのものにはノイズを加えない。
ノイズの柔らかさはa / bに対応するベクトルの補間で表現し、色相角度を補間して特定の色へ偏らせる処理は加えない。

Chroma = 0では変換を行わない。EnabledとStrengthの無効化条件、Lumaの式、Size / Softness / Rateの役割、pass数は維持した。
Sceneへ保存されたユーザーの設定は変更していない。

## 見た目の比較

今回の比較はLuma = 0.08、Chroma = 0.1、Size = 8、Softness = 0.6。
粒の配置を揃えるためRateだけ0に固定して取得した。

| 比較 | 前回のRGB方式 | 今回のOklab方式 |
| --- | --- | --- |
| 単独ノイズ。左上: linear灰色0.25 / 右上: 灰色0.005 / 左下: 灰色0.0008 / 右下: HDR灰色2 | [画像](crt-chroma-perceptual-images/panels-rgb.png) | [画像](crt-chroma-perceptual-images/panels-oklab.png) |
| 現在のCRT testの灰色とmask。1515×852描画から原寸で切り出し | [画像](crt-chroma-perceptual-images/gray-current-rgb.png) | [画像](crt-chroma-perceptual-images/gray-current-oklab.png) |
| 現在のCRT testの暗い背景とmask | [画像](crt-chroma-perceptual-images/dark-current-rgb.png) | [画像](crt-chroma-perceptual-images/dark-current-oklab.png) |

単独ノイズの灰色では、青・青紫・水色側の粒の変化が見える。
現在のmaskを有効にした白〜灰色の領域でも、以前より大きな青側の粒を確認できた。
全色の見え方が完全に均一になる保証はしない。特にmaskのRGB配置と最終表示の飽和も影響する。
暗部では色ノイズの量が以前より弱くなる場合がある。

## 検証

- Godot CLIのGDScript check-only成功。
- 実描画で新しいshaderをcompile・実行し、再起動した実際のSceneのMaterialがOklab処理を使用することを確認した。
- Chroma = 0、Luma = 0.08で、前回のshaderとRGB最大差0。Lumaの見え方は維持した。
- 全Strength = 0のshaderと、ノイズを通さない画像のRGB最大差0。
- Rate = 0は120ms後もRGB最大差0。
- 全Strength = 0 / Enabled OFFでNoise passが無効になる条件を確認した。
- 黒・灰色・HDR色を検査し、全pixelの値が有限だった。HDR最大RGBは約6.098で、1へのclampは行われていない。
- 一時検証ノードは全て解放。検証用ゲームを停止し、開始時の停止状態へ戻した。
- 現在runのgame logにはerrorがなく、editor Loggerにも新しいentryはなかった。

画素・runtime・GPU計測結果は [verification.json](crt-chroma-perceptual-images/verification.json) に保存した。

### 負荷の参考

現在の1515×852のtest sceneでroot Viewportを測定した。
20frameのwarmup後、20frame平均でRGB方式は約0.825ms、Oklab試作は約0.817msだった。
短い計測のばらつきの範囲であり、負荷が下がったという結論には使わない。
Bloomの補助Viewportはこの数字に含めていない。
Chroma有効時は色空間の往復変換の演算が増えるが、追加pass・画面コピー・SubViewportは増やしていない。

## 残る性質

- OklabのLを保つ処理であり、RGBの輝度を厳密に保つ処理ではない。
- RGBへ戻した結果の負成分は既存の出力処理で0へ止める。飽和色や暗部では色相・明度にも影響する。
- 同じStrengthでも以前のRGB方式と見え方は異なる。暗部の色ノイズは弱くなる場合がある。
- Chromaの振幅はLuma適用後のLに応じるため、Lumaの量にも多少影響される。
- 最終表示で白く飽和した部分では色の差が見えにくい。

## 変更ファイル

- `presentation/post_processing/effects/crt_display_experimental/crt_noise.gdshader`：Oklab変換とa / bノイズ。
- `presentation/post_processing/effects/crt_display_experimental/crt_display_experimental.gd`：Chroma tooltip。
- `presentation/post_processing/effects/crt_display_experimental/PARAMETERS.md`：新式、処理順、制約を更新。
- `docs/work-reports/crt-chroma-balance.md`：前回の修正が見た目には不十分だった点と本報告へのリンク。
- 本報告、比較画像、検証値。

## 工程と所要時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 再調査・試作 | ユーザーの見えている色を確認。runtimeの式と現在設定を確認。Oklab試作を単独ノイズ / 現在maskで比較 | 色の見え方を全条件で完全に揃える保証はない | 修正の未反映ではなく、linear RGBの振幅だけの評価が不十分だったと確認。青側の粒が見える試作を確認 | 12分17秒（13:07:51〜13:20:08 UTC） |
| 反映・検証 | shader / 説明を更新。CLI・実描画・0比較・HDR・runtime反映・logを確認 | clampや表示の飽和による変化は残る | 新方式の反映を確認。Chroma無効時のLumaと全無効時のRGB一致を確認 | 2分35秒（13:20:08〜13:22:43 UTC） |
| 記録・片付け | 比較画像・検証値・作業報告を保存、ゲーム停止 | なし | 一時ノード解放、ユーザーのScene保存設定を保持 | 2分59秒（13:22:43〜13:25:42 UTC） |

合計: 17分51秒（13:07:51〜13:25:42 UTC）。

