# Phosphor Substrate：絶対Gapへの変更

記録日: 2026-10-01（日本時間）。
計測開始: 2026-10-01 05:35:04 UTC。集計: 2026-10-01 05:52:19 UTC。
実測合計: **17分15秒**（報告保存直前まで。ツール待機・文脈引継ぎを含む経過時間）。

## 工程と所要時間

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 前提確認 | AGENTS.md・関連docs・既存差分・保存値を確認 | なし | mainも既にSubstrateを使用しており、保存値の等価移行が必要と判明 | 1分28秒 |
| 実装 | FillをGapに置換、Row Pitchを4まで拡張、CRT testの基準値を設定 | なし | Gapを周期と独立した絶対幅として扱い、実面積からgainを計算 | 0分55秒 |
| CLI・Runtime検証 | HDR平均・RGB漏れ・信号積分・旧mode一致・画像比較を確認 | motion時の主観評価、GPU時間、全CRTの1080p/2160p比較 | 大きい検証バッチの8秒timeoutを分割で解消。Reference/Integratedとmain移行の一致を確認 | 5分13秒 |
| 仕様更新・追加検証・文脈引継ぎ | PARAMETERS.md / PHOSPHOR_CELLS.md更新、fractional pitchの追加確認、検証結果整理 | RGB色分離と横線として見える傾向は残る | fractional pitchのcoverage・平均光量・単色漏れを追加確認。文脈引継ぎ待機もこの経過時間に含む | 6分59秒 |
| Editor同期・報告 | 開いているmain用PostProcessingとCRT testをdiskから再読込、CRT test再起動、記録作成 | 下記の視覚評価は継続 | 古いFillを含むEditor状態の保存を防止。最終起動にエラーなし | 2分40秒 |

## 実装

- Horizontal Fill / Vertical Fillを廃止し、Horizontal Gap / Vertical Gapへ置換。
- 両Gapは0.0〜1.0 output px、step 0.05、初期値0.50。今回の明示仕様を優先。
- Row Pitchは整数2 / 3 / 4 output px、初期値3。
- Gapを周期両端へ半分ずつ配置。RGB内部にはGapを設けない。
- active_width = triad_pitch − horizontal_gap、active_height = row_pitch − vertical_gap。
- 既存2×2 samplingとX/Yの矩形analytic coverageを維持。
- RGB共通gain = 3 × triad_pitch × row_pitch / (active_width × active_height)。
- 負のGapは0相当、active寸法の下限は0.001pxとして防御。HDR値のclampではない。
- Beam、Signal Reconstruction、Phosphor Bloom、Reference、Integratedの処理は変更しない。
- 光量のchannel間再配分、元画像とのmix、Soft Edge、Optical Spreadは追加しない。

CRT testはStretched VGA Phosphor / Substrate / pitch 2 / row 3 / Gap 0.50・0.50。
作業前のtestはCell SamplingだけSubstrateで、StyleはLegacy初期値だったため、Phosphor passを有効にするStyle 7も明示した。
基準のgainは4.8、Gapなしのgain 3に対する追加補償は1.6倍。

mainは作業前からSubstrate / pitch 4 / row 3 / Fill 1.0・0.75を使用していた。
見た目を保つため、その保存値のみGap 0.0・0.75へ等価換算した。
CRT testの新しい比較条件をmainへ適用したわけではない。
既存のmain Scene変更、testの画像配列・キー操作、ColorGrading / ChromaticAberration / Glowの保存設定は保持。

## 検証

Godot 4.7.2 / Forward+ / D3D12 / HDR2Dで確認。
Runtime数値検証は一時SubViewportを使用し、終了時に解放。恒久的な検証Sceneは追加していない。

- Godot CLIのheadless Editor起動・終了が成功。script / shaderのparse errorなし。OS証明書storeに関する既存警告は残る。
- 均一HDR **540条件**: 両Style × row 2/3/4 × pitch 2/4 × Gap 5組 × 9入力。
  Gapは0.25/0.25、0.50/0.50、0.75/0.75、0/0、1/1。
  入力は白1/2/4/8/16、R/G/B単色、gray 0.5。
  channel平均の最大相対誤差は **0.056964%**。
  独立した矩形交差計算との最大component誤差は **0.080603%**（分母max(1, expected)）。
  単色の別channelへの漏れは0。HDR peakは49.34375。
- Fractional pitch **108条件**: 両Style × row 4 × pitch 2.5/3/6 × Gap 0.25/0.75・0.75/0.25 × 9入力。
  平均誤差は最大 **0.043947%**、矩形交差計算との誤差は最大 **0.073794%**（同じ分母）。
  単色漏れ0。HDR peakは61.625。
- 信号積分 **24条件**: 両Style × row 2/3/4 × pitch 2/4 × Gap 2組。
  X gradient、1pxのY輝度変化、HDR edgeを含む入力を独立CPU bilinear sampling × 矩形交差計算と照合。
  最大誤差は **0.100167%**（同じ分母）。
- Reference / Integrated **24条件**: 変更前shaderと全pixelのRGBが一致、最大差0。
  Referenceは両Style × Scale 1〜4、Integratedは両Style × pitch 2/2.5/3/6 × 2/4 samples。
- mainの旧Fill 1.0・0.75と新Gap 0.0・0.75を両Styleで比較し、gradient / Y stripe / HDR edge入力の全pixel RGBが一致。
- 範囲外のGap 999pxでもRGBはすべて有限。NaN / Infなし。
- 均一入力をCanvas上で(0.375, 0.625)移動しても比較したpixel値の差0。これは動く映像のmoire評価とは別。
- InspectorのGap範囲・step・px表示、Row Pitch上限4、旧Fill propertyの削除をRuntimeで確認。
- 最終CRT test起動は正常。4つの既存effectをすべて保持。
  途中の再読込直後に一時的なnull effect警告が出たが、最終構成では全effectがnonnull、再起動にエラーなし。
- git diff --check成功。

初回の大きい1512条件バッチはgame_evalの8秒制限に達したため、その結果を完了条件には数えていない。
上記の540条件と108条件へ分割して完了した。

## 視覚比較と残る判断

CRT testで基準からpitch 4、row 2/4、各Gap 0.25/0.75、Gap 0、VGA Phosphor、Bloom OFFを比較。
画像モードでも確認した。追加effectは比較中だけRuntimeで外し、保存設定と最終Runtime構成を復元した。

- Pitch 4はPitch 2よりRGB粒と白文字の色分離が強く見える。均一grayにも色むらが目立つ場面がある。
- Row 3/4は緑単色にも明暗を作れるが、Cell輪郭より横線として認識される傾向は残る。
- Pitch 2 / Gap 0.50・0.50の緑単色の範囲は、row 2で1.0一定、row 3で約0.8999〜1.1992、row 4で約0.8569〜1.1426。
- HDRの空間平均を維持しても、SDR出力のclippingや知覚による白の色分離まで消えるとは限らない。
- 光量補償gainは基準で追加1.6倍。pitch 2 / row 2 / Gap 1・1では追加4倍となるため、最大Gapを推奨値とはしない。
- Bloom ON/OFFで比較したが、全設定でCell肥大が起きないことを保証する評価は完了していない。
- motion時のmoire / shimmer、GPU profiling、全CRTの1080p / 2160p比較は未実施。

通常表示を邪魔せず発光面の存在を感じる最終値は、今回の基準から調整して決める段階。

