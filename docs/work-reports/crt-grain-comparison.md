# Grainの比較とexport初期値の確認

実施日: 2026-10-02、22:48:48〜23:07頃 JST。Godot 4.7.2。

## 実装

- CRT ResourceのGrainグループにPatternを追加。Enabled / Pattern / Strength / Sizeの4項目。
- Smooth Randomは従来と同じ固定hashとsmoothstep補間。初期選択を維持。
- Dispersed Randomは中心から近傍平均を引いて明暗の塊を抑える。分散を合わせる係数を掛けて範囲を制限。blue-noise textureそのものではない。
- Orderedは4×4 Bayer rankを明暗倍率へ使用。入力色・輝度を量子化せず、階調数や色数を減らさない。
- 全方式で画面固定、RGB共通の乗算、Mask後・Spread/Bloom前。同じSizeとStrengthでPatternだけを切り替えて比較できる。OFFまたはStrength 0が無加工の基準。
- 各方式の実測contrastは厳密に等しくない。Sizeと後段のSpread/Bloomによって弱まり方も違う。
- pass数・SubViewport数・texture数は増加なし。Dispersed Randomは各格子で5回のhashを使う。GPU時間の測定は未実施。

Editor上の調整値ON / Strength 0.18 / Size 1.5とMask Strength 0.7を確認して保持した。
比較の初期選択はSmooth Random。新規ResourceのStrength初期値は引き続き0.2。
Pixel Previewを再追加していない。

## 初期値が0 / nullになる原因

最小の@tool ResourceをGDScriptから作成し、instanceを保持したまま新しいfloat / boolのexportを追加して `reload(true)` した。
新しいfloatの宣言初期値1.5、boolのtrueに対し、既存instanceはどちらもnull、新規instanceは1.5 / trueになった。
既存の調整値0.18は保持された。[再現コード](artifacts/crt-grain-comparison/check_defaults.gd)・[結果](artifacts/crt-grain-comparison/defaults.json)。

実Sceneでも追加したGrain Patternがnullとなり、保存すると `grain_pattern = null` が記録された。
Inspectorでは数値のnullが0相当に見える場合がある。正常に設定した0と、欠損したnullは区別する必要がある。
また、Sceneに保存された調整値は宣言上の初期値を上書きするため、初期値の変更だけでは既存の設定は変わらない。

作業開始時、Editor上のGrainは正常でON / Strength 0.18 / Size 1.5だったが、Sceneの3項目はnullだった。
したがって、ファイルのnullだけでGrainが動いていないとする以前の判断は不適切だった。

調整値を保存してSceneを開き直しても、既存Resource cacheのGrain Patternのnullは残った。
Godot AIで新規CRT Resourceを作り、[確認した全調整値](artifacts/crt-grain-comparison/editor-settings.json)を引き継いでComposite Effects[2]を置換。
他の3つのEffect Resourceは同じ参照を維持した。保存後、Editor上のPattern 0、Strength 0.18、Size 1.5とSceneの非null値を確認。
この対応手順を `docs/gdscript.md` に追記した。エンジンやaddonsは変更していない。

## 検証

- Godot CLIでCRT Resource Scriptの構文検証を通過。git diff --check通過。
- 実ShaderのHDR描画で、黒 / 均一グレー / HDR色 × 3方式 × Size 1 / 1.5 / 4の27ケースを確認。有限値、黒維持、共通RGB倍率、時間を隔てた全byte一致、Strength 0の全byte一致を通過。[描画記録](artifacts/crt-grain-comparison/render-validation.json)。
- Smooth Randomと変更前のShaderの演算経路を同じ入力で描画し、9ケースで全byte一致。
- 実CRT Sceneで3方式を切り替え、mainとBloom Coreのuniform同期、各方式のStrength 0とOFFの一致を確認。[実行記録](artifacts/crt-grain-comparison/runtime.json)。
- 3方式それぞれのResource保存・cacheを使わない再読み込みでPattern / Enabled / Strength / Sizeを確認。[保存記録](artifacts/crt-grain-comparison/defaults.json)。
- 最新ゲームログにエラー・警告なし。Editorの新規ログもなし。作業前からnull Effect警告と、前回の削除済み検証ScriptをEditorが参照したエラーが残っている。
- Godot AIのscript_patchは検証器からerror 43を返したが、CLI構文検証と実ゲームのロード・描画は成功。ツール応答だけでは正常と判定せず、実値を確認した。
- CLIのSceneTree検証では既知のOS root certificate store取得エラーが出るが、検証は終了コード0で完了。

開始時は停止中だった。同じEditor session `prototype@a37e29ab83064025` で検証し、完了時も停止状態へ戻した。
比較用のランタイム変更は保存せず、初期選択Smooth Randomと確認済み調整値を維持。

## 比較画像

SceneはStrength 0.18 / Size 1.5、現在のMask / Spread / Bloomを使用。
均一面はグレー入力、Strength 0.5 / Size 1、Grainのみ、最近傍6倍拡大。質感の構造を強調した比較で、推奨設定ではない。

| 方式 | 実Scene | 均一面の拡大 |
| --- | --- | --- |
| Smooth Random | [現在の方式](artifacts/crt-grain-comparison/scene-0.png) | [均一面](artifacts/crt-grain-comparison/flat-0.png) |
| Dispersed Random | [塊を抑える方式](artifacts/crt-grain-comparison/scene-1.png) | [均一面](artifacts/crt-grain-comparison/flat-1.png) |
| Ordered | [規則的な方式](artifacts/crt-grain-comparison/scene-2.png) | [均一面](artifacts/crt-grain-comparison/flat-2.png) |

## 工程記録

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・設計 | 規約、Grain、保存値、Editor実値、hot reloadの最小再現を確認 | 過去の全追加項目の発生経路は未追跡 | GrainはEditorで正常に動いていることを確認。export追加後の既存instanceのnullを再現 | 7分54秒 |
| 実装・Editor同期 | 3方式selector、Shader分布、調整値保存、新規Resourceへの引き継ぎ | エンジンのhot reload自体は未修正 | cacheを残すScene再読込では不十分と確認し、nullを解消 | 3分24秒 |
| 描画・保存検証 | 27ケース、旧方式一致、実Scene、Bloom同期、保存再読込、比較画像 | GPU時間は未測定。既存Editorログは対象外 | 黒・色比率・強度0・時間固定・旧方式の維持を確認 | 3分56秒 |
| 整理・報告 | 説明と今後の手順更新、報告、停止状態復元、最終差分確認 | なし | 現在の調整値を保持した比較を提供 | 約3分 |
