# CRT共通配置とEnvelope削除

2026-10-01。計測18:27:15〜18:41:05 JST、13分50秒。
記録作成と最終確認までを含む。最終メッセージ送信直前の数秒は含まない。
Referenceの設定統一だけは選択待ち。現在は旧配置とCell Scaleを保持する。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・確認 | AGENTS、関連docs、shader、保存Resource、対象Godot sessionを確認 | Referenceを共通pitchへ移行するか質問中 | Shape変更後の名前は配置系統のラベルとして維持する方針 | 1分42秒 |
| Envelope削除 | mode、CellPitch enum、専用export/uniform、shader関数、テストSceneの不要保存値を削除 | なし | 既存Reference / Integrated / SubstrateのIDは維持 | 1分15秒 |
| 共通配置実装 | vga_aperture.gdshaderincへ横coverageとstaggerを共通化。Mask Layoutへpitch項目を集約 | Referenceは現時点で共通設定対象外 | Legacy VGA系とIntegrated / Substrateで同じ幾何関数を使用 | 2分14秒 |
| 検証 | CLI、CRT test起動、GPU比較40条件、既存出力比較28条件、Inspector/API確認 | 全CRTの視覚的優劣・motionの模様・GPU profilingは未判定 | 共通配置の画素差0、既存条件の画素差0、設定がshaderへ渡ることを確認 | 4分46秒 |
| ドキュメント整理 | PARAMETERS / PHOSPHOR_CELLSを現仕様へ更新、Envelopeは過去の記録へリンク | Referenceの移行方針は確認待ち | 現在の設定と過去の実験を区別 | 1分51秒 |
| 記録・最終確認 | 実測表の保存、runtime状態・ログ・diffの確認 | Referenceの移行方針は確認待ち | CRT test実行中、現在runのエラーなし、diffの空白エラーなし | 2分02秒 |
| 合計 | この段階の実測経過時間 | Referenceの統一は未実施 | Envelope削除と共通配置実装を完了 | 13分50秒 |

## 実装

- 共通Triad Pitchは2.0〜6.0px / step 0.1、初期値2.5。共通Row Pitchは1〜4px / step 1、初期値3。
- Legacy Stretched VGA（0）/ VGA（1）とPhosphor Integrated / Substrateで使用する。
- Stretched VGAは毎row、VGAは2rowごとにhalf-triad staggerする。横coverageは周期矩形との交差長を解析計算する。
- SubstrateだけGapとGap Alignmentを追加する。共通geometryの抽出でSubstrateの配置・光量補償は変更しない。
- Legacyの元の6px固定周期、1px row、pixel原点は、共通設定とPhosphor側の原点へ変更された。
- Integratedの固定2px rowは共通Row Pitchへ変更された。Row Pitch 2で旧出力を保持する。
- Referenceは固定6px triad・2px rowをCell Scaleで拡大する従来方式を保持。共通設定は編集不可。
- Dots / Aperture Grille / Slot Maskは変更していない。共通pitchは編集不可。
- Legacyの光量再配分、Phosphorの直接channel割り当ては保持。Signal Reconstruction / Beam / Bloomは変更しない。
- Legacyはpixel中心の入力、Integratedは横2/4点、Substrateは2×2点を使用するため、変化する映像ではsamplingの差も残る。
- 小数pitchの周期的色変動とSDR表示のHDR飽和を解決する変更ではない。新しい発光方式のvariantは追加していない。
- Style名とIDは維持。名称は比較用の配置系統を示し、任意pitchで以前の固定形状を再現する保証はない。

## 検証の根拠

- Godot 4.7.2、HDR2D SubViewport 120×24。
- 両配置×pitch 2 / 2.5 / 3 / 4 / 6×row 1 / 2 / 3 / 4の40条件。均一白1/6、Legacy Mask Strength 1、Phosphor Brightness 1でLegacyとIntegratedを比較。全pixel RGB差0。
- 均一白1/6の各channel平均の最大絶対誤差0.0001017302（相対約0.0610%）。
- HDR gradient、1px周期の輝度変化、HDR 16 edgeを含む入力で、旧Reference Scale 1〜4、旧IntegratedのRow Pitch 2・2/4点、Substrate pitch 2/4・両Alignmentを比較。28条件で全pixel RGB差0。
- 7StyleのResourceを生成してInspectorのread-only状態とCoreへのpitch/rowの受け渡しを確認。Cell SamplingにEnvelopeなし。
- CLI終了コード0、script/shader parse errorなし。OSのroot certificate storeエラーは既存の環境エラー。
- CRT testはautosave falseで起動。GPU比較用ノードは終了時にqueue_free。
- 最初のruntime読取はgame loopが進んでおらず失敗。debug_statusと再読取で回復を確認。ユーザーのmain実行が停止した後、検証用CRT testを起動した。
- mainのScene・PostProcessing設定にはユーザーによる並行変更があり、その内容を変更・巻き戻ししていない。CRT testはEnvelope専用の保存値だけを削除した。
