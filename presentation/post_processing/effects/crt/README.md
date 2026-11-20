# CRT

- 旧実験のCRT実装を移植。色ずれ、信号再構成・走査線、マスク、Texture、Optical Spread、Phosphor Bloomを処理する。
- mainで使う値は `../../post_processing.tscn` に保存する。
- マスクの幅・高さと色ずれは出力pixel単位。Bloomの幅は1080pを基準にViewportの高さで換算する。
- Bloomは同じフレームの前段処理を再描画する。CanvasLayerの変換にカメラ追従を二重に適用しない。
- Bloom有効時は全解像度のSubViewportを6枚使用する。描画負荷の最適化は未実施。
- canvas_itemsの拡大率をBloom用画像の寸法と変換にも適用し、元の画面と再描画の位置・マスク周期を揃える。
