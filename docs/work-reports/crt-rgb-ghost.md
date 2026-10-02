# CRT内部のRGB SeparationとGhost

実施日: 2026-10-03、01:07:04〜01:25頃 JST。Godot 4.7.2。

元の像を残し、赤・青それぞれのXY Offsetと共通Strength、フルカラーのGhost OffsetとStrengthを追加した。
CRT Resource内のRGB Separation / Ghostグループに計5項目を置く。
既存のChromaticAberrationのScript / Shaderは保持し、CRTテストシーンのResource配置・参照だけを除去した。

## 描画と設定

- Pass 0: RGB Separation / Ghost。元の入力を線形補間して読む。
- Pass 1: 既存Signal / Scanline / Mask Redistribution。
- Pass 2: 既存Cell Emission。
- Pass 3 / 4 / 5: Texture / Optical Spread / Phosphor Bloom。

追加パスはSignalより前に置き、既存の再構成で副像もなじませる。
Mask / Textureは出力座標に固定し、その模様を移動しない。
Bloom Coreにも同じパスを再描画する。Bloom sourceのindexを5へ変更し、filterへ送る設定も同じindexを使用する。
既存のSignal / Mask / Texture / Spread / Bloom Shaderの描画式は変更していない。

合成は `(original + RGB Strength * separated + Ghost Strength * ghost) / (1 + RGB Strength + Ghost Strength)`。
二つの副像は同じ元画像から作る。緑は元位置を保ち、赤青だけを別々にずらす。
元画像の重みは常に1で、各Strengthは0〜1。両方最大でも元の像の重みが3分の1残る。
均一面のRGB / HDR値を維持し、alphaは元pixelの値を使う。
Strength 0または対応Offsetが全て0なら、その項と重みを除外する。
両機能が無効なら追加パスとBackBufferCopyを非表示にし、読み取り・合成を行わない。

| 設定 | 初期値 | 範囲 |
| --- | --- | --- |
| RGB Red Offset | (2, 0.5) px | 各軸 −8〜8、0.1刻み |
| RGB Blue Offset | (−2, −0.5) px | 各軸 −8〜8、0.1刻み |
| RGB Strength | 0.3 | 0〜1、0.01刻み |
| Ghost Offset | (5, 1) px | 各軸 −16〜16、0.1刻み |
| Ghost Strength | 0.2 | 0〜1、0.01刻み |

Offsetの正のXは副像を右、正のYは下へ動かす。画面外は端のpixelを延長する。
追加ブラー・Radial・時間変化は実装しない。範囲・初期値は演出の調整用で、実機計測値ではない。
通常SceneとCRT testの既存調整値は、Editorで取得した変更前の値を新規Resourceへ引き継いだ。
両Sceneで新しい項目に正常な初期値が入り、nullがないことを確認した。
[変更前](artifacts/crt-rgb-ghost/before-settings.json)と[変更後](artifacts/crt-rgb-ghost/editor-settings.json)で既存項目の差はなし。

## 検証

- Godot CLIのGDScript構文確認を通過。
- Godot AI経由で96×72のHDR SubViewportを実GPU描画し、14ケースを確認。[結果](artifacts/crt-rgb-ghost/validation.json)。
- 両Strength 0で、変更前の5パスResourceと比較。Mask Redistribution / Cell Emission × Signal OFF / ONの4ケースで全byte一致。Texture / Spread / Bloomも含む。
- 均一なRGB (0.2, 0.4, 0.7)とHDR (4, 1.5, 0.5)で、追加機能の前後の最大誤差0。
- 赤・緑・青それぞれの単色で、フルカラーGhostの元像・副像の重みが一致することを確認。
- RGB分離では赤・青の元像が残り、緑は元の位置を保つことを確認。
- 4.25pxのOffsetで境界の部分的な明るさを確認。整数未満の調整が効く。
- Strength全て0 / Offset全て0で追加パスを無効化することを確認。
- CRT testとMainをEditorから実行。修正後の起動・ゲームログに新しいエラーや警告なし。
- Mainの再起動後、実Script / Shaderと保存ファイルのcode一致、6パス、初期値、既存Mask / Textureの値を確認。[記録](artifacts/crt-rgb-ghost/final-runtime.json)。
- Mainの実描画を取得して視覚確認。[画像](artifacts/crt-rgb-ghost/main.png)。
- テストシーンにChromaticAberrationの参照がなく、元のファイルは存在することを確認。
- git diff --check通過。確認用の一時Script / Resource / 出力は削除。

## 検証中の修正

Godot AIのScript更新時の検証器はerror 43を返した。
一時的な@tool Resourceから実パスを持つGDScriptをreloadするとOKで、新規Resourceも正常だった。
Editorの開いているCodeEditが古いソースを保存して変更を戻す現象を確認したため、
対象のCodeEditとGDScriptを同じ新ソースへ更新して保存した。[同期結果](artifacts/crt-rgb-ghost/editor-sync.json)。
既存Resourceの新exportがnullになったため、調整済み値を保った新規Resourceへ置き換えた。
最初のResource作成では基底ResourceへScriptを割り当てた後のプロパティ検証が失敗したため、
CRTDisplayExperimentalを直接生成する方式へ修正した。最終Sceneにnullはない。

初回描画で、補助関数から直接SCREEN_UVを参照するShaderエラーを検出した。
SCREEN_UV / SCREEN_PIXEL_SIZEをfragmentから引数として渡す形へ修正し、再実行とGPU検証を通過した。
editor_screenshotの画像応答がtransport失敗したため、Godot AIのgame_evalで実Viewport画像を保存して確認した。
これらの一時的な失敗は製品側では解消済み。Godot AI検証器自体は変更していない。
GPU時間の計測は行っていない。

同じsession prototype@a37e29ab83064025 / PID 19964を使用。
開始・終了ともEditorは共通PostProcessing表示、ゲーム停止状態。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認 | 規約、現在のScript、Editor調整値、テスト配置、APIを確認 | なし | 保存値とEditor値を確認、既存値を記録 | 1分53秒 |
| 実装 | 追加Shader、5項目、6パス構成、無効化条件を実装 | なし | 元の像を残し、独立した副像を正規化合成 | 1分19秒 |
| Editor同期・Scene更新 | Script更新、Resource置換、テストの旧色収差を除去 | Godot AI検証器のerror 43自体は未修正 | 古いCodeEditの上書き、新exportのnull、Resource生成方法を修正 | 6分59秒 |
| Shader修正・実描画検証 | 関数引数を修正、14ケースのGPU検証、CRT test実行 | なし | Shaderコンパイル、単色の元像維持、HDR維持、旧描画一致を確認 | 2分25秒 |
| 通常Scene・設定確認 | Main実行、画像確認、実コード一致、説明更新 | GPU時間は未計測 | 正常な初期値と既存値の維持、ログを確認 | 3分23秒 |
| 整理・報告 | 最終Editor値の比較、参照検索、一時ファイル削除、記録保存 | なし | 不要な検証ファイルを除去し、結果のみ保存 | 約2分40秒 |
