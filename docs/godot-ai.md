# Godot AI

Godot Editorの操作、状態確認、実行時の確認にはGodot AIを適宜使用する。

## 使用する場合

- Scene・Node・Resourceなど、Godot Editor上の操作や状態確認には優先して使用する。

## 使用しない場合

- GDScriptとShaderの作成・編集は、直接編集を優先する。
- 一括置換など、Editorを必要としない処理は直接編集を優先する。

## Editorセッション

- Godot AIを使用する際は、現在の作業ディレクトリに対応するEditorセッションを使用する。
- 対応するEditorセッションが存在しない場合は、`godot --editor --path .` で現在のプロジェクトを起動する。
- 複数のEditorセッションが存在する場合は、プロジェクトパスが現在の作業ディレクトリと一致するものを使用する。
