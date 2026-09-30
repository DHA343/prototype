# Phosphor Aperture 再実装

開始: 2026-09-30 15:44:11 UTC  
集計: 2026-09-30 16:02:47 UTC  
実測合計: 18分36秒（確認・実装・検証・修正・文書化。報告ファイル保存直前まで）

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 指示・実装確認 | AGENTS.md、関連docs、現行shaderと保存値、対象Godot AI sessionを確認 | なし | mainとCRT testの旧Brightnessを特定 | 0分56秒 |
| 実装 | 6px triad、2×Scaleの高さ、連続sampling、soft rectangle、占有率・profile正規化、Brightness 1.0へ移行 | なし | 粒の寸法、triad単位の映像離散化、均一面のHDR光量低下 | 1分35秒 |
| 機械・実行時検証と評価 | CLI、HDR計測、旧Style/Bloom比較、高解像度Cell、main起動、静止画の評価 | RGB模様・fringeが残る。動画時のちらつき、全CRT+Bloomの1080p/2160p・GPU性能は未確認 | 検証用shaderの予約語名を修正。Scale 3で周期が欠ける測定領域を144×48pxへ修正 | 10分52秒 |
| 文書化・最終確認 | PHOSPHOR_CELLS.md / PARAMETERS.md更新、差分確認、時間・結果記録 | 見た目の全合格条件は未達 | 古い仕様と検証結果を更新。文書保存の失敗後、apply_patchで保存 | 5分13秒 |

## 変更

- 各channelはScale 1で2×2px、RGB triadは6px。両Styleのhalf-triad staggerを維持する。
- Pass 0のHDRを現在fragment位置で参照し、該当channelだけを発光させる。
- 各軸のprofileはScale 1で0.9、Scale 2以上で端1pxが0.8・内部1.0。
- 正規化はRGBの占有率1/3と縦横profile平均を含む共通scalar。HDR Clampやchannel間再配分はしない。
- Resource初期値、main、CRT testのPhosphor Brightnessを1.0に統一。
- Beam、Signal Reconstruction、Legacy Mask、Bloomのソースは変更していない。
- 作業前からあったAGENTS.md編集とmainのStyle 7指定を維持した。

## 検証結果

- Godot CLIのheadless editor起動はexit 0、GDScript parse errorなし。
  OSのroot certificate store読み込みエラーは出たが、今回のshaderやscriptのエラーではない。
- Godot AI経由、Godot 4.7.2 / Forward+ / D3D12 / HDR2Dで実際にshaderをrender。
- 均一白、linear 50% gray、RGB単色、HDR 1/2/4/8/16、両Style × Scale 1〜4の72ケースを測定。
  各channel平均の最大相対誤差は0.048828125%。非選択channelへの漏れは0。
- 入力16のpeakはScale 1で48、Scale 2で59.25。1でClampされていない。
- 空間変化するHDR fieldを両Style × Scale 1〜4の8ケースで測定。
  同じfragment位置の入力から求めた期待値との最大相対誤差は約0.1515%。
- 1920×1080 / 3840×2160の実SubViewportで、両Style × Scale 1/2の8ケースを確認。
  同じoutput pixel座標のCell出力は完全一致。
- CRT testでLegacy Stretched VGA/VGAとPhosphor両Style、Scale 1/2、Bloom ON/OFFを比較。
  細線、文字、gradient、高コントラストedge、HDR矩形、画面端を静止画で確認。
- mainはStyle 7 / Scale 1 / Brightness 1.0で起動。最新runのgame logにエラーなし。
- 最終git diff --checkはexit 0。

## 評価・未確認事項

- 旧12px triadより細かくなり、暗さ・文字の潰れは改善。
- Scale 1でもRGB模様と色の縁取りは見える。Scale 2は粒が目立つため通常表示にはScale 1を基準とする。
- 「粒を意識しない」「強いfringeが出ない」は完全達成として扱わない。
- 完全な周期での均一HDR平均を保存する方式であり、細線や不完全な画面端、SDR表示後の平均輝度の一致は保証しない。
- 埋め込みgameは1500×843pxに固定され、Window.sizeの変更も反映されなかった。
  高解像度検証はCell Pass単体のみ。全CRT+Bloomの1080p/2160p比較とGPU profilingは未実施。
- 動く高コントラスト入力のちらつきは静止画では判定していない。
