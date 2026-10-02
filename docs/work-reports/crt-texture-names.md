# MaskとTextureの名称整理

実施日: 2026-10-02、23:35:53〜23:45頃 JST。Godot 4.7.2。

## 変更

| 対象 | 旧名 | 新名 |
| --- | --- | --- |
| Mask Pattern | RGB Grain | Staggered RGB |
| Maskの段の高さ | Grain Height / grain_height | Row Height / row_height |
| 明暗の質感グループ | Grain | Texture |
| 質感の設定 | grain_enabled / pattern / strength / size | texture_enabled / pattern / strength / size |
| 質感Shader | crt_grain.gdshader | crt_texture.gdshader |

Staggered RGBはRow Heightごとに横位相を半周期ずらす配置。Textureは映像へ明暗倍率を乗せる処理。
Mask内のRow Heightは同じグループに置き、Staggered RGB以外では従来どおり読取専用にする。
描画式、整数step、初期値、設定範囲、enumの数値、pass順序、無効化条件は変更していない。

Resource、Shader uniform、enum、保存Scene、説明文を新名に揃えた。ShaderのUIDは維持。
旧名aliasや新たな調整項目は追加していない。過去の作業記録は当時の名称のまま保持した。

## 保存値とEditor

変更前にEditor上のResource実値と、別プロセスのゲームで読み込んだSceneの値を確認。
CRT testのRow Height 2、Mask Strength 0.7、Texture ON / Dispersed Random / Strength 0.25 / Size 1.8を保持した。
共通PostProcessingの保存ファイルも旧名だけを移行した。

作業開始時のMain固有Resourceには旧Grain項目のnullが残っていた。
実ゲームで読み込まれる値を確認して新名へ移行したが、検証中にMainが共通PostProcessingを参照する保存状態へ変わった。
その変更を戻さず、Editorでも共通Resourceの参照を確認した。
共通ResourceのEditor上の未保存のTexture調整は、保存済みの値へ巻き戻していない。

## 検証

- Godot CLIでCRT Resource Scriptの構文検証を通過。
- CRT testを同じ1512×850のHDR出力で描画。変更前後の画像全byte一致。[検証記録](artifacts/crt-texture-names/validation.json)。
- Row Height 2、Texture Pattern 1、Strength 0.25、Size 1.8を描画側で確認。[変更前の保存値](artifacts/crt-texture-names/before.json)。
- Inspector対象でMaskのRow HeightとTextureのEnabled / Pattern / Strength / Sizeを確認。CRT testに新しいnull項目なし。
- MainのComposite Effectsが共通PostProcessing Resourceを参照することを確認。
- 現行の製品コードとSceneに旧grain_*設定・RGB_GRAIN・crt_grain参照が残っていないことを確認。
- 最新のゲームログにエラー・警告なし。Editorには作業前からのnull Effect警告等が残るが、最後の検証後に新規ログなし。
- git diff --check通過。

既存の同じEditor sessionを使用。検証用のゲームは停止し、検証中にユーザーが開いた共通PostProcessing Sceneへ戻した。
一時的なraw画像とPNGは確認後に削除した。

## 工程記録

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認・基準保存 | 規約、Scene参照、Editorと実ゲームの調整値、HDR画像を確認 | なし | 現在のCRT調整値とMainの既存nullを特定 | 3分 |
| 名称変更・機械的検証 | Resource、Shader、保存値、説明文、ファイル名を整理 | なし | Mask配置と明暗の質感の名称の重複を解消 | 1分 |
| Editor・描画確認 | Inspector実値、参照、画像一致、最新ログを確認 | 既存Editor警告は対象外 | CRT testの見た目と調整値の維持を確認。作業中のScene変更を保持 | 3分20秒 |
| 整理・報告 | 説明更新、一時画像削除、停止、Scene表示復元、報告 | なし | 旧名の参照が製品コードに残っていないことを確認 | 約1分40秒 |
