# Post-processing experiments

このフォルダは実験用ポストプロセスと確認シーンの保存先。正式採用済みの実装を示すものではない。
現在は27グループ、130モードを収録。うち既存実装を参照する5グループを含む。
一覧は [CATALOG.md](CATALOG.md)、実行時メニューの定義は `catalog.json`。

## 起動と入力

`testbed/testbed.tscn` を開いてF6で実行する。起動時は実際の `main/main.tscn` を表示する。

- `1`: main。シミュレーションを再開する。
- `2`: 共通テストパターン。表示中にもう一度押すと背景を単色・市松・グラデーションで切り替える。
- `3`: 登録画像を順番に表示する。nullの項目はスキップする。
- `Ctrl+O`: PC上の任意の画像を読み込み、登録画像に追加して表示する。
- `F1`: 操作パネルの表示切替。数値・文字入力欄の操作中は入力切替キーを無効にする。
- 画像は画面全体へ引き伸ばす。パターンは1280×720を画面中央に等倍配置する。
- パターンには細線、階調、色、半透明の重なり、文字、線形HDRの1x/2x/4x/8x/16xを含む。

mainは複製した専用シーンではなく元のPackedSceneを生成するため、mainの保存済み変更は
testbedの次回起動に反映される。mainのシーン・スクリプト・正式側のポストプロセスは変更しない。
入力切替時は同じmainインスタンスを保持し、非表示中は処理・カメラ・CanvasLayerを止める。

二重適用を避けるため、生成したmainインスタンスのPostProcessingは空にして無効化する。
mainのWorldLayerが持つPixelation設定は維持し、実験側の全体ON/OFFに接続する。
エフェクトの構成や調整値はtestbed側で設定する。実験の調整値は正式シーンへ書き戻さない。

## エフェクトの組み合わせ

右のパネルでグループを選び、Add effectで追加する。Modeで方式を切り替え、
数値・色・テクスチャを調整する。複数回追加すれば同じグループの異なるModeも併用できる。

- Composite: 文字・ゲーム内UIを含む画面に適用する。
- World: ゲーム内の文字・UIの前に適用する。
- Up / Down: 同じ段階の適用順を変更する。
- Remove / Reset: 選択したエフェクトの削除・初期化。
- Effect enabled: 個別のON/OFF。Effects enabled: 全体のON/OFF。
- Save preset / Load preset: WorldとCompositeの構成・順序・パラメータを`.tres`で保存・復元する。
- Load texture / Clear texture: 任意の画像の割り当て・解除。

操作パネルはCanvasLayer 1000なので、エフェクトの処理や履歴には含まれない。
プリセットの既定保存先はGodotのuserデータフォルダ。履歴テクスチャや統計値は保存しない。
読み込んだ外部画像はImageTextureとしてプリセット内に保存されるので、ファイルが大きくなる場合がある。

## 配置と共通基盤

`effects/<group>/` にResourceスクリプト、シェーダー、`preview.tscn`を置く。
同じ役割の方式はModeにまとめる。各previewは共通testbedを継承する。
例外としてCRTは従来の複数パス・仕様書を同じフォルダ内に保持する。
既存のVignette、Chromatic Aberration、Display Texture、Glowは参照する薄いResourceを置く。

`effects/_shared/` はシェーダー関数、動的パラメータ、履歴、縮小・拡大処理を共有する。
新しいResourceはShaderのuniformからInspectorと実行時パネルを生成する。
RenderLayersとPostProcessingは正式側の共通基盤を参照し、実験用の入力・補助バッファ・UIはtestbed側に置く。

`testbed/patterns/reference_set.tscn` は追加の図形・グラデーション・文字の素材。
`testbed/images/` は共通確認画像。testbedルートのimagesで表示順を設定する。

## 擬似3D

Pseudo 3Dは2D入力から高さ場を作る。実際の3Dシーンの深度や形状を復元する処理ではない。

- Depth source: 輝度、縦方向の平面、ドーム形状、任意の深度画像を選択する。
- 深度は黒=近、白=遠。Invert depthとDepth scaleで調整する。
- Custom depth: データ画像のRチャンネルを読む。Depth sourceをCustom Depth Mapに設定する。
- 法線は深度の周辺差分から作る。Custom normalを指定し、Use custom normalをONにするとRGB法線を使う。
- 法線画像はRGBを[-1,1]へ変換する。正面はRGB=(0.5,0.5,1)、Yの正方向は画面下。

SSAOは高さ場の近傍遮蔽、SSRは高さ場に対する画面内レイマーチ、接触影は光方向への深度比較。
SSILは深度が近い周辺の色を間接光として加算する。Volumetric Fogは画面上の仮の視線に沿って
ノイズ密度を積分する。実際の3D空間の遮蔽・間接照明・体積を取得するものではない。
画面外の反射や隠れている形状は描画できない。結果は入力の明るさや指定した高さ場に依存する。
被写界深度とボケはフォーカス深度に応じた円盤サンプリング。フォグや法線ライティングも同じ深度を使う。

## 対象マスク・速度・履歴

Target EffectsとMotion Blur用に、mainのOrb・Enemyの円形Visualからマスクと画面速度を描く。
汎用の全ノード自動認識ではない。testbedルートのMask orb / Mask enemiesで対象を選ぶ。
パターンではHDR色パッチ、画像では中央の円を仮の対象とする。
Custom maskはR=対象の重み。Custom velocityはRG=0.5+UV移動量×8、B=対象の重み。
ルートのMask image / Velocity imageは自動生成バッファ全体の上書き用。

時間効果はフレームの履歴を保持する。入力切替、Mode・パラメータ変更、再有効化、解像度変更時に履歴をリセットする。
Frame Holdは指定fpsで入力を更新する。Auto Exposureは入力を縮小して平均対数輝度を求め、露出を追従させる。
Temporal AAは速度で履歴を移動して近傍の色範囲へ制限する実験的な時間フィルタで、投影ジッターは使わない。

履歴・露出は現段階ではGPU画像をCPUへ読み戻すため、複数併用・高解像度では重くなりやすい。
Dual KawaseとMulti-scale BloomはHDR SubViewportの4段の縮小・拡大を使う。
重いサンプリングを行う方式も含むため、最終的なゲーム向けの最適化・品質調整は別途行う。

## LUTとディザ

標準のFilm LUTとBlue Noiseを同梱する。
LUTはN×N×Nの立方体をN²×Nの横長画像に配置し、Bのスライスを左から右に並べる。
各スライスのX=R、Y=G。Lut sizeをNに合わせる。HDR入力は0〜1へ制限して変換する。

## CRT

`effects/crt/preview.tscn` は旧crt_display_testの後継。
従来の色調補正・CRT・ビネットと保存済み調整値を保持し、起動時はmainに適用する。
個別ON/OFFとパラメータ変更は正式側の調整から独立している。

CRTのスクリプト・シェーダー・UID・仕様書は前の移行でここへ移動済み。
正式側で使用中のCRT参照も移行先を指す。旧phosphor_bloom_testは参照先スクリプトが
削除済みだったため整理済み。CRT内部のBloomの仕様は
[PHOSPHOR_BLOOM.md](effects/crt/PHOSPHOR_BLOOM.md)を参照する。
