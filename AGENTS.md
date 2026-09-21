# AGENTS.md

## 前提

- ゲームエンジン: Godot 4.7
- スクリプト言語: GDScript
- シェーダー言語: Godot Shader Language

### プラグイン

- [Godot AI](https://github.com/hi-godot/godot-ai)

## ドキュメント

作業前に、次の対応するファイルを参照すること。

- GDScript関連: `docs/gdscript.md`
- Shader関連: `docs/shader.md`
- Godot AIを使用する場合: `docs/godot-ai.md`

## 基本方針

実装に影響する情報が不足している場合は、推測せず確認してから実装する。

複数の規則が競合する場合は、次の優先順位に従う。

1. ユーザーからの明示的な指示
2. 参照ドキュメント
3. 既存実装

ただし、規則の適用を理由に、指示にない既存実装の変更をしない。

ノード、クラス名の命名は次に従う。

- 抽象的になりすぎない範囲でシンプルな名前をつける。
- 機能を機械的に説明するような名前ではなく、役割に基づいた名前をつける。

### 注意事項

- `.godot/` 以下のファイルは編集しない。ただし、Godotによるインポートや検証で自動的に生成、更新されることは許容する。
- `addons/` 以下のファイルは編集しない。

## 操作手段

- 内容がファイル上で明確で、Godot Editorの現在の状態やGodot側のAPIを介した処理を必要としない変更は、直接編集を優先する。
- Godot EditorやRuntimeの現在の状態を扱う場合、Godot側で解釈されたScene・Node・Resourceの構造を確認する場合、またはGodot Editor APIを介した操作が変更の安全性や正確性に必要な場合は、Godot AIを使用する。
- Godot CLIで確認可能な機械的検証は、Godot CLIを優先する。
- Computer Useは明示的な指示がない限り使用しない。

## 検証

変更内容に応じて、必要な範囲のみ検証する。

- 機械的な検証には、Godot CLIを使用する。
- Godot Editorや実行時の確認には、Godot AIを使用する。
