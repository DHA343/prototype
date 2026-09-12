# Godot Shading Language

## 基本原則

- 使用可能な構文・組み込み関数・組み込み変数を [Godot Shader Language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html) で確認する。

## 実装上の注意

- Godot Shader Languageの予約語、組み込み変数、組み込み関数、uniformヒントを、ローカル変数名・関数名・uniform名として使用してはならない。
	- `source_color` は色空間を指定するuniformヒントであるため、変数名には使用しない。画面テクスチャから取得した色には、`screen_color` など用途を表す名前を使用する。

## エントリ関数の制約

`vertex()`、`fragment()`、`light()` は、Godotが呼び出す `void` のエントリ関数である。

- エントリ関数内で早期 `return` を使用してはならない。Godot Shader Languageではコンパイルエラーになる。
- 条件によって処理を打ち切りたい場合は、`if / else` で分岐し、各分岐で出力変数を代入する。

```glsl
void fragment() {
	if (is_outside_screen) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = texture(screen_texture, SCREEN_UV);
	}
}
```
