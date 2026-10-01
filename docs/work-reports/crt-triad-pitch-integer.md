# Triad Pitchの整数化

実施日：2026-10-02（JST）。計測区間03:18:44〜03:21:43。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 調査・実装 | 保存Resourceを確認。Triad Pitchをint型・2〜6px・1px刻みに変更。両shaderのhintと初期値、仕様を同期 | なし | 小数での調整を除去。新規Resourceの初期値を3pxへ変更 | 1分01秒 |
| 検証・整理 | CLI構文確認、Resource型・range・両shaderへの値伝播・Scene保存値の機械的確認。確認用scriptを削除 | CLI起動時のOS root certificate store読込エラー（今回の変更外） | 整数2〜6が両passへfloatとして渡ること、保存値4 / 4 / 2の維持を確認 | 1分58秒 |

## 変更

- Maskグループ内のTriad Pitchを整数型、2〜6px、1px刻みとした。
- 新規Resourceと両shaderの初期値は3px。旧初期値2.5から近い整数へ変更し、GapなしでRGB各色が1px幅になる基準とした。
- shader内の計算は従来どおりfloat。Resourceからの設定時にfloatへ明示変換する。
- main、共通PostProcessing、CRT testの保存値は4 / 4 / 2。小数部分のある保存値はなく、値は維持して保存表記だけ整数へ合わせた。
- shaderのgeometry計算、Mask内のグループ構成、その他の設定は変更していない。

## 検証

- Godot 4.7.2 CLI check-only成功。
- 一時的なCLI確認scriptでTriad PitchのTYPE_INT、range 2 / 6 / 1、初期値3を確認。
- 整数2〜6がCoreとCellの両ShaderMaterialへ正しく反映されることを確認。
- PackedSceneからmain / 共通PostProcessing / CRT testのResourceを読み、保存値4 / 4 / 2を確認。CLI終了コード0。
- 初回の確認scriptはrange hintの文字列を整数表記と仮定してassertが失敗した。Godotの実値は `2.0,6.0,1.0,suffix:px`。数値として確認するよう修正し、再確認は成功。これらの確認scriptとプロセスは残していない。
- CLI確認中にOSのroot certificate store読込エラーが出たが、ResourceとMaterialの確認は完了した。証明書設定は変更していない。
- 現在のCRT testは保存値2pxを維持。今回は描画式を変更していないため、GPU画面比較は再実施していない。

新規Resourceなど旧初期値2.5に依存する箇所は3pxへ変わるため、模様の密度も変わる。
