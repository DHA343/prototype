# Phosphor Envelope 試作

記録日: 2026-10-01（日本時間）。
計測開始: 2026-10-01 07:27:13 UTC。集計: 2026-10-01 07:38:53 UTC。
実測合計: **11分40秒**（報告保存直前まで。調査・検証コードの修正・ツール待機を含む）。

## 工程と時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 方針・前提確認 | AGENTS.md、関連docs、既存変更、session、profileの色偏り条件を確認 | 最終的な見た目の選定 | 単一cosineと4/6px周期なら、2px RGB apertureとの相関によるchannel平均の偏りを避けられる | 2分53秒 |
| 実装 | 同じshaderにEnvelope mode、Cell Pitch、Envelope Strengthを追加。CRT testだけ選択 | GPU計測は未実施 | RGB周期とCell輪郭の周期を分離。旧modeのenum ID・保存値を維持 | 0分20秒 |
| CLI・Runtime・画像検証 | 均一HDR、信号積分、旧mode一致、Inspector、両Style・画像・Bloom比較 | grayの周期的模様、moving signalのmoire / shimmer | 一時検証codeの予約語signalをsignal_rgbへ修正、再起動で復帰。screenshot通信失敗は状態確認後にgame framebuffer保存で代替 | 4分58秒 |
| 仕様・報告・差分確認 | PARAMETERS.md / PHOSPHOR_CELLS.md更新、時間・結果を整理 | 視覚評価は継続 | mainと画像入力scriptのhash一致、比較中のeffect構成を復元、git diff --check成功 | 3分29秒 |

## 採用した試作条件

ユーザー選択A「なだらかな発光面」を実装した。
従来のhard edge Substrateは変更せず、Cell SamplingにEnvelopeを追加した。

- Reference 0 / Integrated 1 / Substrate 2を保持、Envelope 3を追加。
- RGB triadは2 output px固定。channel幅は2/3px、内部Gapなし。
- Cell PitchはFour Pixels / Six Pixels。初期値4px。任意のfractional周期を許可しない。
- Row Pitchは既存の2 / 3 / 4pxを共有。初期値3。
- Envelope Strengthは0〜1、step 0.1、初期値0.5。
- X / Yの形状はそれぞれ `1 − strength × cos(2π × position / period)`。
- 各軸の周期平均は1。strength 0では平坦、1では境界0・中央2。
- 初期値の連続2D profileは0.25〜2.25。これはpixel積分前の点での値。
- Stretched VGAでは毎row、VGAでは2rowごとにphaseを変更。RGBは1px、EnvelopeはCell Pitchの半分ずらす。
- output座標へ固定し、Cameraや入力映像と一緒に形状を移動させない。
- RGB apertureと横cosineの積、および縦cosineを解析積分する。pixel中心にprofileを後掛けする処理ではない。
- Signal + Beamは2×2区間中心でsampling。信号とgeometryの積は区間内で信号一定とする近似。
- 共通RGB gainは占有率補償の3のみ。profileの平均を1にしたため、追加のFill補償は不要。
- RGB clamp、別channelへの光量移動、channel別gain、画像とのmix、Optical Spreadを追加していない。
- Envelope中はCell Scale / Triad Pitch / Signal Sampling / Horizontal Gap / Vertical Gapを編集不可にする。
- 旧modeへ戻せば従来の保存値を使う。ユーザー調整のVertical Gap 0.85も保持した。
- Resource全体のCell Sampling初期値はIntegratedのまま。CRT testのみEnvelope / Cell Pitch 4 / Row Pitch 3 / Strength 0.5にした。

Signal Reconstruction / Beam / Phosphor Bloomの算法と、mainのScene設定は変更していない。
testのColorGrading・ChromaticAberration・画像配列・1/2キー操作も変更していない。
今回の前から存在するGlow削除、ChromaticAberrationの設定変更、Vertical Gap調整を維持した。

## channel平均が偏らない理由

各RGB apertureの周期は2pxで、非定数成分の空間周波数は1/2 cycles/pxの整数倍。
Envelopeの非定数成分は1/4または1/6 cycles/pxの単一cosine。
周波数が一致しないため、完全な4/6px周期では各channelのapertureとcosineの積の平均が0になる。
RGBの占有率1/3だけを共通gain 3で補償すれば、均一入力の各RGB平均を保存できる。

これは単一cosine・固定2px triad・4/6px Cell Pitchを使う条件に依存する。
cosineを強く非線形変形したり、hard Gapを後掛けしたり、周期の自由度を増やした場合にも成立するとは限らない。
任意profileを追加する際は再検証が必要。

## 数値検証

Godot 4.7.2 / Forward+ / D3D12 / HDR2Dで実施。
一時SubViewportは検証後に解放。恒久的な検証Sceneや画像資産は追加していない。

- CLI headless Editorの起動・終了成功、script / shaderのparse errorなし。
  OS root certificate storeの既存エラーは出るが、今回のscript / shaderとは無関係。
- 均一HDR **324条件**: 両Style × Row Pitch 2/3/4 × Cell Pitch 4/6 × Strength 0/0.5/1 × 9入力。
  入力は白1/2/4/8/16、R/G/B単色、gray 0.5。
  channel平均の最大相対誤差 **0.048828%**。
  独立CPUの区間交差・cosine積分との最大component誤差 **0.079891%**（分母max(1, expected)）。
  単色の別channelへの漏れ **0**。HDR peak **106.8125**。
- 非均一信号 **24条件**: 両Style × Row Pitch 2/3/4 × Cell Pitch 4/6 × Strength 0.5/1。
  X gradient、1pxのY変化、HDR edgeを含む入力を独立CPUのbilinear sampling × weighted aperture積分と照合。
  最大誤差 **0.095273%**（同じ分母）。
  この検証は実装した2×2 quadratureの照合で、連続入力との厳密な積分誤差の計測ではない。
- 既存mode **60条件**: 変更前shaderと全pixelのRGBを比較し、最大差 **0**。
  Referenceは両Style × Scale 1〜4（8条件）。
  Integratedは両Style × pitch 2/2.5/3/6 × Signal samples 2/4（16条件）。
  Substrateは両Style × Row Pitch 2/3/4 × pitch 2/4 × Gap 0/0・0.5/0.5・0.25/0.75（36条件）。
- Inspectorのmode ID、Cell Pitch、Strength範囲・step、modeごとの編集可否をRuntimeで確認。
- main/main.tscn、main用post_processing.tscn、CRT test画像入力scriptのSHA256は作業前後で一致。
- 最終game logはhelper登録のみ。比較中に外したColorGrading / ChromaticAberrationを復元し、3 effectの構成を維持。
- git diff --check成功。

## 見た目と残る評価

CRT testでCell Pitch 4/6、Strength 0/0.5/1、Substrate、VGA Phosphor、Bloom ON/OFF、画像モードを比較。
数値検証と視覚比較のためのeffect除外はRuntimeだけで行い、最後に元の構成へ戻した。
比較画像は一時保存先のGodotディレクトリへ保存し、projectの資産には追加していない。

- 従来は横方向に一定だった緑単色にも、横4/6px周期の明暗が残る。
- Strength 0.5、Row Pitch 3の中央rowでは、緑の横方向の値が4pxで約1.2324〜1.5938、6pxで約0.9614〜2.1055。
  平均1の確認は中央rowだけではなく、縦も含む完全な周期で行う。
- 4pxは細かいCell感、6pxは発光面が大きく明瞭。ただし6pxは粒や模様も強く見える。
- Cellの2D構造は出たが、gray / gradientに周期的模様が見える。均一HDRの平均保存だけでは、SDRのclipping・知覚・Beamとの干渉を解消できない。
- Row Pitch 2では縦profileがpixel平均で消える。最初の2D比較には3/4を使用する。
- Strength 1は点で最大4倍の2D profileとなる。強さを上げれば素子の主張・local peak・Bloomへの入力も増えるため、最終推奨値とはしない。
- moving signalのmoire / shimmer、GPU profiling、全CRTの1080p/2160p比較は未実施。
- 「画面を邪魔せず素子感だけ残る」最終値が確定したわけではない。今回の成果は、横方向にも効果がある比較方式を用意し、RGB平均の偏りを防ぐ条件を検証したこと。

Shader構文は[Godot公式Shading language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html)を参照。

