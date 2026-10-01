# CRT：mask適用後の狭い光の広がり

実装日：2026-10-01（工程時刻はUTC）。
対象：CRTDisplayExperimental。ノイズの単調さの調整は後回しにし、mask周辺の狭い光の広がりを追加した。

## 見た目と調整

CRT Resourceの **Optical Spread** に次の2項目を追加した。

| 項目 | 範囲 | 初期値 | 調整するもの |
| --- | --- | --- | --- |
| Strength | 0〜1 | 0.5 | 元画像から周囲へ光を移す量 |
| Width | 0〜1出力px | 0.75px | 周囲を読む範囲の幅。GaussianのFWHMではない |

StrengthまたはWidthを0にすると、描画と画面コピーを無効化する。Legacy / Phosphorのどちらでも使える。現在のCRT testの実行中Resourceでも初期値0.5 / 0.75pxの適用を確認した。

実画像では、RGBの細かな分離やセルの隙間の硬さが弱まり、元の映像を読み取りやすくなった。強くするとmaskの粒感そのものも減る。現在のLegacy設定では最大値で模様がかなり弱まり、Phosphorでは最大値でもセルの配置が比較的残る。

処理はmask適用後の画像への狭い対称ブラーなので、映像の輪郭にも作用する。細線の位置や総光量を保ちつつ、中心の明るさは下がる。粒の周期や配置、不規則さを変える機能ではない。

## 処理の変更

- 順序をSignal / Scanline / Legacy Mask → Phosphor Cell → Optical Spread → Bloom → Noiseの5passにした。Mask Styleに応じてLegacyまたはPhosphorを使う。
- 新しいshaderでは4つの対角位置をbilinear samplingして平均し、中心RGBと混合する。HDR上限clamp、加算gain、輝度thresholdは設けない。
- Widthの上限は1px。最も細かいpixel周期の模様を反転させない範囲に限定した。
- Bloom Coreにも同じ広がりを再描画する。無効時はCore側のColorRectとBackBufferCopyも止める。
- Bloom filterへのparameter送信を、固定pass index 1から実際のBloom pass indexに修正した。従来はCellのparameterを送っていたため、HDR Limitがfilterへ反映されていなかった。
- Noiseは最後に重ねるため、この広がりでぼかされない。

有効時はメイン描画と、Bloom有効時のCore再描画に各1passと1画面コピーを追加する。新しいSubViewportは作らない。Bloom用の6枚は従来と同じ。

## 検証

Godot 4.7.2 / HDR 2Dで確認。数値の詳細は[verification.json](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/verification.json)に保存した。

| 検証 | 結果 |
| --- | --- |
| Godot CLIのcheck-only | CRT ResourceとBloom helperの2スクリプトとも成功 |
| Strength = 0 / Width = 0 | 単独shaderの出力は未処理と全pixel完全一致。メインとBloom Coreの描画・コピーも無効 |
| 単独1px水平・垂直線 | 初期値で中心0.8125、周囲を含む合計1。最大値では中心0.5、合計1 |
| HDR 4の単一輝点 | 初期値の中心2.78125、総光量4。最大値の中心1、総光量4 |
| 均一HDR面 | ON / OFFとも同じ値。有限値を維持 |
| Legacy 5 Style、Phosphor 2 Style × 3 Sampling | 11構成で模様のRGB振幅が減少。整数周期の領域で平均RGBの変化は最大約0.051% |
| Signalと併用した1px水平線 | 1080px高さ、Sharpness 0.5、Pitch 2、Vertical Blur 0.5、Prefilter ON。6つの行位相で線が残る。中心付近の最小ピークはOFF約0.625、初期値ON約0.527 |
| Bloom HDR Limit変更 | 5枚のfilterに2 → 1の変更が反映され、sourceの最大RGBも約1.950 → 1へ変化 |
| CRT testの実行状態 | 5pass、新shader、Strength 0.5 / Width 0.75を確認。最後のgame / editor logにerrorなし |
| git diff --check | 成功。Gitの改行変換に関する警告のみ |

Signal併用の細線検証ではmask・走査線模様・Bloom・Noiseを無効にし、追加した広がりの影響を切り分けた。細線が見えることを確認した範囲はこの条件であり、極端なmask設定や低い表示解像度まで保証するものではない。

## 比較画像

1920×1080で実画像を描画し、同じ領域を原寸cropした。比較用の複製ResourceだけNoiseをOFFにして原因を切り分けた。Legacyは検証時のCRT test設定。PhosphorはVGA Phosphor / Substrate / Row Pitch 3へ変更した比較設定。

| 対象 | OFF（Strength 0） | 初期値（0.5 / 0.75） | 最大（1 / 1） |
| --- | --- | --- | --- |
| Legacy・細部 | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/detail-legacy-off.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/detail-legacy-default.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/detail-legacy-full.png) |
| Legacy・暗部 | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/dark-legacy-off.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/dark-legacy-default.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/dark-legacy-full.png) |
| Phosphor・細部 | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/detail-phosphor-off.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/detail-phosphor-default.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/detail-phosphor-full.png) |
| Phosphor・暗部 | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/dark-phosphor-off.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/dark-phosphor-default.png) | [画像](C:/GameDev/Projects/prototype/docs/work-reports/crt-optical-spread-images/dark-phosphor-full.png) |

縮小表示はmaskの周期と干渉するため、粒や色の分離は原寸画像で比較する。

短時間のGPU計測は各条件20frameの準備後に20frame平均を取得し、メインとBloom用6 Viewportの合計が約2.90〜3.01msだった。条件間の差は測定の揺れと同程度で、追加passの正確な負荷差や性能改善はこの測定から判断しない。

## 残る調整

- maskの規則性や大きな周期は残る。今回の処理だけで不規則な質感にはならない。
- ノイズの単調さはユーザー指定により後で調整する。
- 色差のにじみ、周辺の弱いボケ・明るさ変化は未実装。独立した次の工程で扱える。
- mask全体の方式変更は今回行っていない。光の広がりの見た目を確認してから判断する。

## 工程と所要時間

検証中にEditorが再起動され、元sessionが消失した。旧sessionへの接続を確認した後、ユーザーの「再起動した」という回答を受け、同じproject_pathの新しいsessionを特定して最終確認を続行した。仮の検証Viewportは解放し、再起動後にユーザーが実行していたCRT testは実行中のまま維持した。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・設計・実装 | 2026-10-01 13:29:38 UTC〜2026-10-01 13:37:48 UTC。mask後の光の再配分、操作項目、Bloom連携を実装 | 周期・不規則さは対象外 | 狭い広がりをmaskの大きさと独立に調整可能 | 8分10秒 |
| 初回検証・説明更新 | 2026-10-01 13:37:48 UTC〜2026-10-01 13:52:36 UTC。CLI、単独pixel、11mask構成、Bloom、実画像を確認 | Signal併用の最終確認が中断 | 光量、無効化、HDR Limit反映を確認 | 14分48秒 |
| 接続確認 | 2026-10-01 13:52:36〜14:01:03 UTC。旧session確認とEditor再起動の確認 | 確認中は実行検証を保留 | ユーザー回答により対象Editorを再特定 | 8分27秒 |
| 最終実行確認 | 2026-10-01 14:01:03〜14:03:20 UTC。細線6位相、現行Resource、ログを確認 | なし | 中断していた細線検証を完了 | 2分17秒 |
| 記録・差分確認 | 2026-10-01 14:03:20 UTC〜2026-10-01 14:06:22 UTC。数値・画像・本報告を保存 | ノイズ等の今後の調整 | 差分の空白エラーなし、比較記録を保存 | 3分2秒 |
| 合計 | 接続確認と回答待ちを含む | 上記の今後の調整 | 今回の追加と必要な検証は完了 | 36分44秒 |
