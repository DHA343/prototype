# Effect catalog

共通testbedから追加・並べ替え・調整できる27グループ、130モード。
各行のフォルダにあるpreview.tscnをF6で実行すると、そのグループを適用したmainで起動する。

| フォルダ | モード | 数 |
| --- | --- | ---: |
| [color_grading](effects/color_grading/preview.tscn) | Exposure / Temperature / Tint / Vibrance / Shadows / Midtones / Highlights / Channel Mixer / Brightness / Contrast / Saturation / Hue / Gamma | 11 |
| [color_transform](effects/color_transform/preview.tscn) | Monochrome / Sepia / Negative / Duotone / Gradient Map / LUT / Solarization / Selective Color / Thermal / Night Vision | 10 |
| [dithering](effects/dithering/preview.tscn) | Posterize / Palette / Bayer / Random / Blue Noise | 5 |
| [pixelation](effects/pixelation/preview.tscn) | Rectangular Mosaic / Hexagonal Mosaic / LED Dots / Low Resolution Nearest / Low Resolution Bilinear | 5 |
| [print](effects/print/preview.tscn) | Halftone / CMYK Screens / Crosshatch / Paper / Misregistration | 5 |
| [detail](effects/detail/preview.tscn) | Sharpen / Unsharp Mask / Sobel / Outline / Emboss | 5 |
| [painting](effects/painting/preview.tscn) | Kuwahara / Bilateral / Color Planes / Comic | 4 |
| [blur](effects/blur/preview.tscn) | Gaussian / Dual Kawase / Directional / Radial / Zoom / Tilt Shift | 6 |
| [lens](effects/lens/preview.tscn) | Multi-scale Bloom / Soft Focus / Halation / Anamorphic Streak / Starburst / Lens Ghosts / Lens Dirt | 7 |
| [distortion](effects/distortion/preview.tscn) | Barrel / Pincushion / Fisheye / Ripple / Waves / Heat Haze / Swirl / Kaleidoscope | 8 |
| [film](effects/film/preview.tscn) | Film Grain / Color Noise / Monochrome Noise / Dust and Scratches / Flicker / Film Weave | 6 |
| [vhs](effects/vhs/preview.tscn) | VHS Composite / Color Bleed / Tape Tearing / Tracking Noise / Interlace / Vertical Roll | 6 |
| [glitch](effects/glitch/preview.tscn) | Block Displacement / Horizontal Bands / Channel Dropout / Local Inversion / Compression Damage | 5 |
| [display](effects/display/preview.tscn) | CRT Glass / LCD Grid / Dot Matrix / Glass Reflection | 4 |
| [overlay](effects/overlay/preview.tscn) | Flash / Colored Edge / Letterbox / Circular Mask / Wipe / Dissolve | 6 |
| [temporal](effects/temporal/preview.tscn) | Afterimage / Frame Blend / LCD Response / Phosphor Persistence / Feedback / Frame Hold / Temporal AA | 7 |
| [auto_exposure](effects/auto_exposure/preview.tscn) | Auto Exposure | 1 |
| [target](effects/target/preview.tscn) | Target Outline / Target Glow / Target Distortion | 3 |
| [motion_blur](effects/motion_blur/preview.tscn) | Object Motion Blur | 1 |
| [crt](effects/crt/preview.tscn) | CRT | 1 |
| [pseudo_3d](effects/pseudo_3d/preview.tscn) | Depth of Field / Bokeh / Depth Fog / SSAO (pseudo) / SSR (pseudo) / Contact Shadows / Light Shafts / Normal Lighting / Depth Outline / SSIL (pseudo) / Volumetric Fog (pseudo) | 11 |
| [antialiasing](effects/antialiasing/preview.tscn) | FXAA / Morphological AA | 2 |
| [vignette](effects/vignette/preview.tscn) | Vignette | 1 |
| [chromatic_aberration](effects/chromatic_aberration/preview.tscn) | Chromatic Aberration | 1 |
| [display_texture](effects/display_texture/preview.tscn) | Texture Overlay | 1 |
| [glow](effects/glow/preview.tscn) | Glow (existing) | 1 |
| [tone_mapping](effects/tone_mapping/preview.tscn) | Linear Clamp / Reinhard / Extended Reinhard / ACES Approximation / Hable / Filmic / Logarithmic | 7 |

方式の名前が同じでも映画機材や実機の完全再現を意味しない。VHS・圧縮劣化・LCD等は画面加工による近似。
FXAAとMorphological AAは実験的な画面エッジ平滑化。Morphological AAはSMAAの専用検索テーブルを使わない。
ACES Approximationは近似曲線であり、正式なACES全体の色管理パイプラインではない。
SSAO / SSR等の擬似3Dと時間フィルタの条件は[README](README.md)を参照。

モードを変更するuniformはmode。Resourceのparameters辞書に初期値との差分を保存する。
新規追加時はcatalog.jsonにも登録し、preview.tscnを共通testbedから継承する。
