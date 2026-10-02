# Chroma Bleedの削除

実施日: 2026-10-02、21:12:54〜21:14頃 JST。

Signalによるボケと比べて追加効果の用途が限られるため、ユーザーの指示でChroma Bleedを削除した。

- ResourceからWidth / StrengthとShaderへの設定送信を削除。
- Core Shaderから専用uniform、色差の再構成・混合・色域圧縮、適用分岐、専用定数を削除。
- CRT testに保存されていたWidth 8 / Strength 1を削除。他のScene設定は維持。
- PARAMETERSから2項目と専用説明を削除。追加時の報告と比較画像は履歴として保持。
- 既存Signalのsampling / prefilter / reconstruction、Scanline、Maskの関数本体が変更されていないことを削除前のソースと比較確認。Chroma Bleed無効時の既存経路へ戻した。

| 工程 | 内容 | 未解決の問題 | 解決済みの問題 | 所要時間 |
| --- | --- | --- | --- | --- |
| 確認・削除 | 規約・参照箇所を確認し、実装・設定・保存値・説明を削除 | なし | Chroma Bleedの機能と調整項目を撤去 | 1分04秒 |
| 機械的検証 | Godot CLIでScript構文検証とCRT testのheadless読み込み、参照検索、diff確認 | 起動時の既存OS証明書ストア読み込みエラー | Script検証とScene起動は終了コード0。製品コードに専用参照なし。git diff --check通過 | 15秒 |
| 最終確認・報告 | 既存Shader関数のソース比較、履歴への注記、報告作成 | GPUによる描画比較は今回未実施 | Signal・Scanline・Maskの既存関数本体を維持していることを確認 | 約1分 |

今回の検証は機械的な読み込みとソース比較。Editorの実行状態を操作していない。
