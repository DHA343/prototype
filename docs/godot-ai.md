# Godot AI

Godot Editorの操作、状態確認、実行時の確認にはGodot AIを使用する。

## 利用方針

- Editorの状態確認や、Scene・Node・ResourceなどEditor上の操作には優先して使用する。
- Scene構造、instance、ownership、NodePath、Resource参照など、直接編集では整合性を崩す可能性がある操作にはGodot AIを使用する。
- 複数の関連するEditor操作は、可能であれば `batch_execute` でまとめて行う。
- Godot AIを使用する利点が明確であれば、以下の方針に限定しない。

## 直接編集

- GDScript、shader、Markdownなどのテキストファイルは通常のファイル編集を優先する。
- 複数ファイルの変更、リファクタリング、一括置換、検索などEditorを必要としない処理にはGodot AIを使用しない。
- `.tscn` や `.tres` の単純な値変更は直接編集してよい。構造や参照関係に影響する場合はGodot AIを優先する。
- `filesystem_manage` は通常の読み書きや検索には使用せず、scanやreimportなどGodot側の処理が必要な場合に使用する。

## 確認・検証

- 必要に応じて `editor_state`、`project_run`、`logs_read` でEditor状態、実行結果、エラーを確認する。
- 見た目の確認には `editor_screenshot`、実行中の状態や入力に対する挙動の確認には `game_manage` を使用する。

## Editor session

- Godot AIを使用する際は、現在の作業ディレクトリに対応するEditor sessionを使用する。
- 対応するEditor sessionが存在しない場合は、Sandbox外で `godot --editor --path .` を実行して現在のプロジェクトを起動する。
- 複数のEditor sessionが存在する場合は、プロジェクトパスが現在の作業ディレクトリと一致するものを使用する。
