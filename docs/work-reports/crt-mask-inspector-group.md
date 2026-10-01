# Mask設定のグループ統合

実施日：2026-10-02（JST）。計測区間03:14:36〜03:15:17。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認・編集 | 現在のexportとRGB geometryを確認。Mask Layout、Cell Emission、Cell Layout、Outputのグループ注釈を削除 | Triad Pitchの値域変更は未実施 | Model / Pattern / Strength / Pitch / Sampling / Gap / 明るさをMask内へ統合 | 38秒 |
| 検証 | Godot CLI check-only、グループ境界と対象propertyのソース確認 | なし | 構文確認成功。Mask内部に別グループ・サブグループなし | 3秒 |

描画処理、property名、保存Scene、値、初期値は変更していない。Optical Spread、Bloom、Noiseはそれぞれ独立した画像処理として既存グループを維持する。

Triad PitchはRGB一組の横周期。小数値は粒の密度を連続調整できるが、pixel格子と周期が一致せず、場所ごとのRGB coverageの変化や周期的な色変動を生む。
2 / 4 / 6では横周期と半triadのrow shiftが整数pixelになり、配置が繰り返しやすい。ただしRGB各成分の幅はGap 0でpitch / 3なので、2 / 4でも小数coverageを使用する。6では各成分2pxとなる。
整数の3 / 5も使用可能だが、row shiftは半pixelを含む。偶数値に数学的な必須条件はない。
2 / 4 / 6への限定は、粒の大きさの微調整を減らす代わりに設定と配置を単純化する選択として合理的。今回の質問では妥当性の説明までとし、値域や既存2.5の初期値は変更していない。
