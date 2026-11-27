# ボールの残像プレビュー

`tests/ball/preview/aura_preview.tscn` を Godot で開き、F6 で実行する。**A / D**（または **← / →**）で全台の左右フリッパーを操作し、**R** で初期位置に戻す。打球を揃えるため、プレビューでは敵の出現とミサイルの発射を止めている。

左が **Flat**、右が根元から末尾と円の中心から外側のグラデーションを合わせた表示。両方で同じ設定を使い、打球を揃えて色の乗り方を比べる。

`AuraPreview` ノードのインスペクターの **Afterimage Style** 欄に各項目が並ぶ。**Color Gradient** の左端が根元と Flat の色、右端が末尾と外縁の色。**Lifetime** は尾の長さ、**Width Scale** は根元の太さ、**Opacity** は全体の濃さを変える。**Root Color Hold** を上げると根元色が長く残り、**Edge Color Strength** を下げると外縁の色の変化が弱くなる。編集後は保存して F6 で確認する。

**Width Hold** は円の半径を保つ時間（秒）。残りの寿命で直線的に縮む。0 秒ではすぐに縮み始め、**Lifetime** 以上では消えるまで半径を保つ。

`ball.tscn` の直下に `CollisionShape2D`、`Aura`、`Outline`、`Sphere` を置く。`Aura` は速度に追従する形状で、`Aura Enabled` で表示する。先細りの残像はプレビューシーンから追加する。

`Ball` は `PinballBall` を継承する。移動区間を `PinballMotion` から取得し、`Sphere` の姿勢へ反映する。輪郭とオーラは球面の回転と独立している。
