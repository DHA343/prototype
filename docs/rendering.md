# 描画と合成

mainとポストプロセスtestbedは、同じ合成段階を使用する。
WorldやUIといった内容の種類ではなく、画面へ重ねる段階で分類する。
Layer1 / Layer2の1・2は論理的な描画順を表し、CanvasLayer.layerの実際の値とは区別する。

| 段階 | CanvasLayer | 内容 |
| --- | ---: | --- |
| Layer1 | 0 | 先に描くグループ。内容の種類は限定しない |
| Layer 1 Effects | 50 | この時点までの画面を加工する |
| Layer2 | 100 | Layer 1 Effectsの後に描くグループ。内容の種類は限定しない |
| Layer 2 Effects | 150 | Layer2までに描かれた画面全体を加工する |
| Overlay | 200 | Layer 2 Effectsの後へ重ねる要素 |

番号の定義は `presentation/render_layers.gd` に集約する。
エフェクト設定はPostProcessingの `layer_1_effects` / `layer_2_effects` 配列。
InspectorではLayer 1 Effects / Layer 2 Effectsとして表示され、配列順に適用する。

適用範囲はCanvasLayerの描画順で決まり、ノード名やWorld・UIという種類で判定しない。
各エフェクトはBackBufferCopyでそれまでの画面をコピーし、ShaderMaterial付きの
全画面ColorRectへ描く。同じ配列内の次のエフェクトは前の加工結果を入力にする。
シーンツリーの並びは読みやすさのために合成段階へ揃えるが、描画順を決めるのはlayerの値。

## main

- Layer1はActorsを保持するPixelationLayer。物理・入力・Z順はメインViewportのまま、
  キャンバスだけを別のSubViewportへ描き、Layer 1 Effects直前の49へ出力する。
- CheckerboardBackgroundはルートの背景として維持する。Layer 1 Effectsの対象には含むが、
  Actors専用のPixelationには含めない。背景をLayer1の子へ移すとこの範囲が変わる。
- Layer2にはDamageNumberSpawnerを配置する。従来のカメラ追従を維持する。
- Overlayは追加描画の配置先。現在は空。UIに限定せず、画像や文字なども置ける。

## testbed

- Layer1/Contentはパターン・任意画像を描画する。main表示時はこのLayer1だけを非表示にする。
- Layer2/Labels/UIにはパターンの説明と文字サンプルを生成する。
  Labelsはパターン時だけ表示し、main・画像では非表示にする。
- Labelsの描画倍率・位置だけをパターンの1280×720実画素配置へ合わせる。
  Layer2自体の表示や変換は切り替えないため、別の子として追加した要素を
  main・パターン・画像の全てで共通表示できる。
- Overlayも入力切替で非表示にしない。全エフェクトを避ける確認要素の配置先。
- mainは元のPackedSceneを実行時に生成し、そのインスタンスのPostProcessingを空にする。
  main側の保存ファイルへ書き戻さず、testbedのエフェクトを一度だけ適用する。
- mainのLayer1にあるPixelationはその設定を保持し、testbedのPostProcessingの全体ON/OFFへ接続する。

プリセット作成・画像追加・入力切替は
`experiments/post_processing/README.md` を参照する。
