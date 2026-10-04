# Effect catalog

共通testbedから追加・並べ替え・調整できる27グループ、130モード。
各行はエフェクトResourceのスクリプト。組み合わせと調整値はpresets/の継承シーンに保存する。
作成方法は[README](README.md#プリセットの作成)を参照。

| Resource | モード | 数 |
| --- | --- | ---: |
| [color_grading](effects/color_grading/color_grading.gd) | Exposure / Temperature / Tint / Vibrance / Shadows / Midtones / Highlights / Channel Mixer / Brightness / Contrast / Saturation / Hue / Gamma | 11 |
| [color_transform](effects/color_transform/color_transform.gd) | Monochrome / Sepia / Negative / Duotone / Gradient Map / LUT / Solarization / Selective Color / Thermal / Night Vision | 10 |
| [dithering](effects/dithering/dithering.gd) | Posterize / Palette / Bayer / Random / Blue Noise | 5 |
| [pixelation](effects/pixelation/pixelation.gd) | Rectangular Mosaic / Hexagonal Mosaic / LED Dots / Low Resolution Nearest / Low Resolution Bilinear | 5 |
| [print](effects/print/print.gd) | Halftone / CMYK Screens / Crosshatch / Paper / Misregistration | 5 |
| [detail](effects/detail/detail.gd) | Sharpen / Unsharp Mask / Sobel / Outline / Emboss | 5 |
| [painting](effects/painting/painting.gd) | Kuwahara / Bilateral / Color Planes / Comic | 4 |
| [blur](effects/blur/blur.gd) | Gaussian / Dual Kawase / Directional / Radial / Zoom / Tilt Shift | 6 |
| [lens](effects/lens/lens.gd) | Multi-scale Bloom / Soft Focus / Halation / Anamorphic Streak / Starburst / Lens Ghosts / Lens Dirt | 7 |
| [distortion](effects/distortion/distortion.gd) | Barrel / Pincushion / Fisheye / Ripple / Waves / Heat Haze / Swirl / Kaleidoscope | 8 |
| [film](effects/film/film.gd) | Film Grain / Color Noise / Monochrome Noise / Dust and Scratches / Flicker / Film Weave | 6 |
| [vhs](effects/vhs/vhs.gd) | VHS Composite / Color Bleed / Tape Tearing / Tracking Noise / Interlace / Vertical Roll | 6 |
| [glitch](effects/glitch/glitch.gd) | Block Displacement / Horizontal Bands / Channel Dropout / Local Inversion / Compression Damage | 5 |
| [display](effects/display/display.gd) | CRT Glass / LCD Grid / Dot Matrix / Glass Reflection | 4 |
| [overlay](effects/overlay/overlay.gd) | Flash / Colored Edge / Letterbox / Circular Mask / Wipe / Dissolve | 6 |
| [temporal](effects/temporal/temporal.gd) | Afterimage / Frame Blend / LCD Response / Phosphor Persistence / Feedback / Frame Hold / Temporal AA | 7 |
| [auto_exposure](effects/auto_exposure/auto_exposure.gd) | Auto Exposure | 1 |
| [target](effects/target/target.gd) | Target Outline / Target Glow / Target Distortion | 3 |
| [motion_blur](effects/motion_blur/motion_blur.gd) | Object Motion Blur | 1 |
| [crt](effects/crt/crt.gd) | CRT | 1 |
| [pseudo_3d](effects/pseudo_3d/pseudo_3d.gd) | Depth of Field / Bokeh / Depth Fog / SSAO (pseudo) / SSR (pseudo) / Contact Shadows / Light Shafts / Normal Lighting / Depth Outline / SSIL (pseudo) / Volumetric Fog (pseudo) | 11 |
| [antialiasing](effects/antialiasing/antialiasing.gd) | FXAA / Morphological AA | 2 |
| [vignette](effects/vignette/vignette.gd) | Vignette | 1 |
| [chromatic_aberration](effects/chromatic_aberration/chromatic_aberration.gd) | Chromatic Aberration | 1 |
| [display_texture](effects/display_texture/display_texture.gd) | Texture Overlay | 1 |
| [glow](effects/glow/glow.gd) | Glow (existing) | 1 |
| [tone_mapping](effects/tone_mapping/tone_mapping.gd) | Linear Clamp / Reinhard / Extended Reinhard / ACES Approximation / Hable / Filmic / Logarithmic | 7 |

方式の名前が同じでも映画機材や実機の完全再現を意味しない。VHS・圧縮劣化・LCD等は画面加工による近似。
FXAAとMorphological AAは実験的な画面エッジ平滑化。Morphological AAはSMAAの専用検索テーブルを使わない。
ACES Approximationは近似曲線であり、正式なACES全体の色管理パイプラインではない。
SSAO / SSR等の擬似3Dと時間フィルタの条件は[README](README.md)を参照。

モードを変更するuniformはmode。Resourceのparameters辞書に初期値との差分を保存する。
新しいエフェクトはcatalog.jsonにも登録する。確認用シーンが必要な組み合わせだけ、
共通testbedを継承してpresets/に保存する。
