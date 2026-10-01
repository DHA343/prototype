# CRT parameter ranges and defaults

Resource の初期値は見た目を調整するための出発点。
実機計測から確定した値ではなく、以下の数式上の意味と調整方針を持つ。
Scene に保存された値は初期値を上書きする。

Mask Modelは描画モデル、Mask Patternは配置方式。行のずらし方はPatternの二つのRGB配置で選ぶ。
Cell SamplingはHorizontal 4 / 2x2、出力の明るさ倍率はBrightness Compensationに一本化した。
InspectorではModel / PatternからBrightness Compensationまでを一つのMaskグループへまとめ、内部の小グループは設けない。

| 項目 | 範囲 | 初期値 | step | 意味・根拠 |
| --- | --- | --- | --- | --- |
| Scanline Count | 180〜720 | 360 | 1 | 縦方向の再構成の行数と走査線模様の周期を共用する。1080pで初期値は1行あたり3出力px。範囲は調整用 |
| Signal Prefilter Enabled | OFF / ON | ON | — | 信号の各サンプルが担当する元画像の範囲を平均してから補間する。細線がサンプル間に落ちて消えることを抑える。OFFで従来の点サンプリング。Signal EnabledがOFFなら無効 |
| Sharpness | 0.5〜1.0 | 0.67 | 0.01 | 横方向のkernelを広げるほど低い値。範囲は半径2〜1サンプル間隔に対応 |
| Signal Pitch | 0.5〜3.0 px | 1.5 px | 0.1 | 横方向の信号サンプル間隔。見た目の調整値で、解像度による自動換算なし |
| Vertical Blur | 0〜1 | 1 | 0.01 | 横方向だけ再構成した画像と、縦も再構成した画像の混合比。0で縦処理を無効、1で縦の再構成を完全適用。走査線の濃淡とは独立 |
| Scanline Strength | 0〜1 | 0.15 | 0.01 | 行方向の明るさの濃淡。0で走査線模様を無効。Signal EnabledがOFFでも使用可能。低解像度では自動的に弱める |
| Beam Width | 0.75〜1.25 lines | 0.9 line | 0.01 | 走査線の発光profileのFWHM。現在は模様だけに使用し、縦の補間へ影響しない。1.0では隣接profileの合計が一定になり、濃淡はほぼ生じない |
| Mask Model | Mask Redistribution / Cell Emission | Mask Redistribution | — | 明るさに応じて色成分を配置へ再配分する方式と、apertureの占有面積から発光する方式 |
| Mask Pattern | Staggered RGB / Staggered RGB (Row Pairs) / RGB Pixel Pattern / Green / Magenta Stripes | Staggered RGB | — | 前二つは毎行 / 2行ごとに半triadずらすRGB配置。両Modelで使用可能。後二つはRedistribution専用 |
| Mask Strength | 0〜1 | 0.5 | 0.01 | mask適用前の再構成信号と、完全適用の出力の混合比。両Model共通。0で模様を除去し、Brightness Compensationは維持 |
| Cell Sampling | Horizontal 4 / 2x2 | Horizontal 4 | — | Cell Emissionの入力sampling。横4点はY中心、2x2は両軸±0.25px。両方式でGapを使用可能 |
| Triad Pitch | 2〜6 px | 3 px | 1 | Staggered RGBの横周期。両Model共通。整数pixel単位で調整し、自動換算なし |
| Row Pitch | 1〜4 px | 3 px | 1 | Staggered RGBの整数行周期。両Model共通 |
| Horizontal Gap | 0〜1 px | 0 px | 0.05 | Cell Emissionのみ。Triad両端に等分する非発光総幅。RGB内部にはGapを設けない |
| Gap Alignment | Pixel Boundary / Pixel Center | Pixel Boundary | — | Cell Emissionの横triad全体を0 / 0.5pxへ移す。全samplingで使用可能 |
| Vertical Gap | 0〜1 px | 0 px | 0.05 | Cell Emissionのみ。Cell row上下に等分する非発光総高さ |
| Brightness Compensation | 0.25〜6.0 | 1.0 | 0.01 | 両Model共通のmask混合後のRGB倍率。1は追加補正なし。旧Cell Brightness × Brightness Compensationの全範囲を保持する |
| Optical Spread Strength | 0〜1 | 0.5 | 0.01 | mask適用後の光を隣接pixelへ移す量。0でpassと画面コピーを無効化。Mask Redistribution / Cell Emission共通 |
| Optical Spread Width | 0〜1 px | 0.75 px | 0.05 | 4つのbilinear sampleのfootprint幅。±Width / 2pxを読む。0で無効。GaussianのFWHMではない |
| Near Width | 0.5〜8.0 px @1080p | 4.0 px | 0.1 | すぐ周囲のにじみ。現在のCRT testで使用する調整値を初期値に採用 |
| Far Width | 4.0〜64.0 px @1080p | 32.0 px | 0.1 | 広いhalo。現在のCRT testで使用する調整値を初期値に採用 |
| Near Strength | 0〜0.25 | 0.1 | 0.01 | sourceからNearへ再配分する割合。初期値10%、上限25%は調整用 |
| Far Strength | 0〜0.1 | 0.05 | 0.001 | sourceからFarへ再配分する割合。初期値5%、上限10%は調整用 |
| HDR Limit | 1.0〜32.0 | 16.0 | 0.1 | sourceの最大RGB成分の漸近値。1は意味のある端点、16と上限32は調整用 |
| Noise Enabled | OFF / ON | ON | — | maskとBloomの後へノイズを重ねる。OFFならNoise passの描画と画面コピーを無効にする |
| Noise Luma Strength | 0〜0.25 | 0.08 | 0.001 | 明るさの粒感。0でこの成分を無効。RGB比率を保ちながら明暗を揺らす |
| Noise Chroma Strength | 0〜0.1 | 0.006 | 0.001 | Oklabの赤緑 / 青黄成分を揺らす色の粒感。0でこの成分を無効。明るさにも多少影響する |
| Noise Size | 1〜8 px | 1.5 px | 0.1 | 粒の間隔。出力pixel基準でmaskのTriad Pitch / Row Pitchとは独立。解像度による自動換算なし |
| Noise Softness | 0〜1 | 0.6 | 0.01 | 硬い粒と、隣接する粒を滑らかに補間したノイズの混合比。大きな粒ほど差が見える |
| Noise Rate | 0〜60 Hz | 30 Hz | 1 | 1秒あたりのノイズ更新回数。0で固定された粒になる。描画fps以上にしても見える更新回数は増えない |

stepは原則1 / 0.1 / 0.01 / 0.001。Cell LayoutのGapは0.05px刻み。
Far Strength は0.001刻みで微調整する。初期値0.05の2%ずつ調整できる。
初期値・範囲・Scene保存値はstep変更に合わせて丸めない。

## Mask ModelとLayout

Mask Redistributionは中心の再構成信号を使用し、各色成分をmask位置へ再配分する。
Cell Emissionはaperture coverageと入力信号の積を近似積分し、占有面積で正規化する。
両Modelの違いはsamplingだけでなく、明るさへの応答にもある。

Staggered RGBは毎Cell row、Staggered RGB (Row Pairs)は2 Cell rowごとに半triadずらす。
Triad Pitchは横周期、Row Pitchは1行の高さで、行をまとめる方式とは独立。
両配置を両Modelで使用する。共通geometryは `rgb_aperture.gdshaderinc`。
RGB Pixel PatternはRGBと黒の4pixel周期、Green / Magenta StripesはG列とR+B列の2pixel周期。
名称はmaskの成分配置を表し、入力や明るさへの再配分により最終pixelが必ず緑・マゼンタになるわけではない。
後二つはMask Redistributionだけで使う。Cell Emissionへ切り替えても対応RGB配置は保ち、未対応配置のみStaggered RGBへ変更する。

Cell EmissionはHorizontal / Vertical GapとGap Alignmentを両samplingで使用する。
Horizontal 4は横4区間に分け、入力のY中心を読む。
2x2は両軸2区間に分け、各区間の中心を読む。aperture coverageは各区間で解析計算する。
Horizontal 2の実装・選択肢とMixed Pixel Patternの4×4配列は削除した。

Gapなしの2x2は、入力のY方向に重み1/8・3/4・1/8の狭い平均を加える。
HorizontalはこのY平均を加えない。2x2は単純な上位互換ではない。
初期Gapは0 / 0。旧SubstrateのSceneは、旧初期値0.5 / 0.5も明示保存して移行した。

Mask Strength = 0はSignal / Scanline後の信号、1は完全なmask出力、中間は両者の混合。
Brightness Compensationは両Modelの混合後に一度だけ適用する。
0ではCell geometryの計算を省くが、gainを維持するためCell passと画面コピーは残す。
Mask RedistributionのBrightness Compensationも混合後に適用する。
Optical Spread、Bloom、NoiseはMask Strengthが0でも独立して使用可能。

詳細は[Cell Emissionの仕様](PHOSPHOR_CELLS.md)を参照。

## Signal Prefilter

横幅は `max(1, Signal Pitch)` 出力px、縦幅は `max(1, Viewport高さ / Scanline Count)` 出力px。
この矩形と元画像の各pixelとの重なりを重みにして平均する。
隣接pixelの重みをbilinear samplingへまとめ、2×2 pixelを最大1回のtexture readで取得する。
入力のRGB / HDR値をclampせず、画面の外側は端のpixelを延長する。

サンプル間の細線を拾うための処理であり、輪郭を強調する処理ではない。
ボケで線が広がり、ピークの明るさが下がることは残る。
均一な色は維持するが、細線や細かな模様は従来より柔らかく、安定した見え方になる。
現在のScene保存値を変えず、Resource / Shaderの初期値ONで適用する。
比較時はSignal ReconstructionのSignal Prefilter EnabledをOFFにする。

追加passは使用しない。texture read数はサンプル範囲に応じて増える。
高解像度でScanline Countを低くすると縦の範囲が広くなり、描画負荷も増える。
同じshaderを使うBloomのCore再描画にも設定が反映される。

## Sharpness

`w(d) = 1 - smoothstep(0, 1, d * sharpness)` を正規化して使用する。
kernelの半径とFWHMは、ともに `1 / sharpness` サンプル間隔となる。
0.67では約1.493間隔、Signal Pitch = 1.5ならkernel自体のFWHMは約2.239出力px。
これはkernelの幅であり、再構成された図形の実測FWHMと常に一致するわけではない。
0.5〜1.0は固定5サンプルの中にkernelを収め、広めから狭めへ調整できる範囲。
0.67に物理的・数学的な必然性はなく、必ず0.67でなければならないわけではない。

## Vertical BlurとScanline Strength

Signal Enabledは横・縦の信号再構成を切り替える。
Vertical Blur = 0なら、元の縦座標から横方向だけ再構成する。
1なら、隣接する信号行の面積平均をcosineの重みで補間する。
中間値は両者の混合。縦の柔らかさの量を調整する値で、ブラーのFWHMではない。
0と1は必要な経路だけを描画し、中間値は両方を読み取るため追加負荷がある。

縦の補間の重みは `lower = 0.5 - 0.5 * cos(π * row_phase)`、`upper = 1 - lower`。
以前のBeam Width = 1と同じ補間の形を基準にし、Beam Widthから独立させた。
Scanline Strengthを0にしても、この補間とPrefilterは残る。
Vertical Blurを0にしても、走査線の濃淡は残せる。

走査線の明るさは `mix(1, 平均光量を補正したprofile, Strength × Visibility)` を掛ける。
profileを出力pixel内の縦4点で平均し、狭い帯の輪郭を柔らかくする。
Visibilityは1pixelあたり0.4〜0.5行でなだらかに弱くなり、0.5行以上では模様を適用しない。
2px以下の周期で現れるaliasingを抑えるための実用的な制限。
Scanline Countは信号行と模様の周期で共用し、密度を変えると両方に影響する。
maskのrow patternやCell EmissionのVertical Gapは別の処理なので、Scanline Strength = 0でも残る。

初期値はVertical Blur = 1、Scanline Strength = 0.15、Beam Width = 0.9。
横線を強く見せず、弱い行方向の質感を足す出発点。
既存の保存済みBeam Widthは優先されるが、現在は縦の補間には使わない。
Beam Width = 1の保存値では、Strengthを上げてもほぼ濃淡は出ない。

## Beam Width

`profile(d) = cos(πd/2)^p`、`p = ln(0.5) / ln(cos(π * width / 4))`。
width = 1ならp = 2で、均一信号では隣接する2本の合計が一定になる基準点。
width = 1の光量補正倍率も1となる。初期値は弱い模様を作れる0.9とする。
1より細いと走査線の隙間が目立ち、1より太いと重なりが強くなる。

旧Width = 0.42の式では `p = 2 + 0.5 * (1/0.42 - 1/0.55) ≈ 2.281385`。
このprofileのFWHMは約0.943104で、以前の初期値0.94は旧形状をほぼ保つ換算値だった。
1.0は走査線の濃淡がほぼなくなる比較の基準として使用できる。

現在の光量補正はpに対する多項式近似で、旧範囲0.5〜1.25全体での精度は成立しない。
選択範囲は0.75〜1.25を維持する。
shader式の連続profileを数値積分すると、補正後の均一信号の平均倍率は以下となる。
表示解像度・走査線位相による離散化は、この計算に含まない。

| Beam Width | 補正後の平均倍率 |
| --- | --- |
| 0.50 | 約0.188 |
| 0.60 | 約0.799 |
| 0.70 | 約0.992 |
| 0.75 | 約0.9994 |
| 0.94 | 約1.0000 |
| 1.00 | 1.0000 |
| 1.25 | 約1.0027 |

TODO: 将来幅0.5付近まで広げるなら自動補正方式を見直す。
光量補正の調整項目は追加せず、見た目の明るさ調整にはBrightness Compensationを使用する。
Beamのprofileと光量補正の式は変更していない。出力pixelでの平均とStrengthの混合を追加した。

## Optical Spread

Signal / Scanline → Mask RedistributionまたはCell Emission → Optical Spread → Bloom → Noiseの順。
maskを大きくせず、セル周辺のごく狭い光の広がりを加える。
全mask方式で使用でき、maskやsignalを無効にしても使用可能。
処理としては、mask適用後の画像への狭い対称ブラー。maskだけでなく映像の輪郭にも作用する。

4つの対角位置、`(±Width / 2, ±Width / 2)` 出力pxでbilinear samplingしたRGBを平均する。
出力は `mix(中心RGB, 平均RGB, Strength)`。HDRの上限clamp、加算gain、輝度thresholdは設けない。
Widthが0〜1の場合、各軸の離散kernelは `[Width / 4, 1 - Width / 2, Width / 4]`。
Width = 1は3×3のbinomial kernelに相当する。これを超えてpixel周期の模様を反転させないため上限を1にする。
初期値はStrength = 0.5、Width = 0.75。単独1px線の中心の明るさは0.8125、周囲を含む合計は1になる。
光を移す量を増やすとmaskのRGB分離・Gapの硬さが減り、細線のピークも下がる。
強くするとmaskの粒感そのものが弱くなる。周期や配置を変える設定ではない。

画面端は端のpixelを延長する。入力RGBの符号と画面テクスチャの中心alphaを維持する。
透明Sceneのalphaについては、Noiseと同じ画面コピー側の制約がある。
出力pixel単位で、表示解像度による自動換算はしない。

StrengthまたはWidthが0の場合、メイン描画とBloom Core再描画のpass / BackBufferCopyを非表示にする。
有効時は全画面passと画面コピーが各1つ増える。追加SubViewportは作らない。
Bloomが有効ならCoreにも同じ広がりを適用してからBloom sourceを生成する。
Near / Far BloomのGaussianやHDR応答制限とは独立した、狭い光の再配分。
Noiseは後に重ねるため、この処理でぼかされない。

## Noise

NoiseはCRT Resourceの最終passで、signal、mask、Optical Spread、Bloomの後に重ねる。
maskのセル形状やsignalのボケに頼らず、不規則な画面の質感を調整するための配置。
ノイズを信号の前へ入れる方式は今回の対象に含めない。

Luma / Chroma Strengthはそれぞれ0で無効。
両方0、またはNoise EnabledがOFFの場合はNoise passとBackBufferCopyを非表示にする。
Signal、Scanline、mask、Bloomの有効状態とは独立し、Mask Redistribution / Cell Emissionの両方で使える。

出力pixel座標と `floor(TIME × Rate)` を整数hashへ渡してノイズを生成する。
Rate = 0ならtickは0に固定され、時間が経っても同じ粒を描画する。
画面に固定された格子であり、画像の内容を移動しても粒の位置は画像へ追従しない。
Sizeは格子の間隔。Softnessは硬い格子とsmoothstep補間を混合する。
補間を強くすると粒の境界と振幅も和らぐため、必要に応じてStrengthを合わせて調整する。
Size = 1でpixel中心と格子が一致する場合は、Softnessの差がほとんど出ない。

明るさはlinear RGBの `Y = dot(max(RGB, 0), (0.2126, 0.7152, 0.0722))` を使う。
ノイズの応答を `sqrt(Y) + 0.02` とし、中間調で粒を見せつつ高いHDR値で過度に強くなることを抑える。
Lumaは `max(Y + noise × Strength × 応答, 0)` を目標明るさにして、元のRGBへ共通倍率を掛ける。
ほぼ黒の領域には無彩色の粒を加える。負方向を0で止めるため、黒や非常に暗い部分では平均明るさが少し上がる。
Strengthは単純な不透明度やdisplay RGBの変化量ではなく、この応答に掛ける係数。

ChromaはLuma処理後のRGBをOklabへ変換し、赤緑を表すaと青黄を表すbへ独立したノイズを加える。
式は `Lab.ab += noise.yz × Strength × (Lab.L + 0.02)`。Lを変更せずlinear RGBへ戻す。
linear RGBの振幅を揃えても、青の粒の見え方が赤・緑と揃わなかったため、知覚上の色差を扱う方式へ変更した。
Oklabの明度Lを保つが、RGBへ戻す際のclampや最終表示によって明るさや色味は変わり得る。
粒の補間は色差のベクトルへ適用する。角度の補間による特定の色相への偏りは加えない。
Luma処理後のLに応じた量なので、Lumaの強さによってChromaの振幅も変わる。
同じStrengthでも以前のRGB方式と色・量の見え方は異なる。暗部では色の粒が弱くなる場合がある。
負のRGBを0で止めるため、暗部は平均明るさが少し上がり、飽和色では色味も変わる場合がある。
入力のHDR値を1でclampせず、画面テクスチャのalphaと元の負のRGB成分を保持する。
透明SubViewportではGodotの画面コピーでalphaが1になる場合があり、元Sceneの透明度を保証する機能ではない。
最終表示で白く飽和する部分ではノイズが見えにくい場合がある。

Noise有効時は全画面passと画面コピーを1つ追加する。追加のSubViewportやノイズtextureは作らない。
Chroma > 0の場合はOklabとの往復変換を行う。Chroma = 0ならこの変換は行わずLumaの式だけを使用する。
NoiseはBloomの後なので、BloomのCoreに再描画されず、ノイズ自身の発光の広がりも加えない。

## Bloom

Near/FarのWidthはGaussianのFWHMで、Viewport高さ / 1080を掛けて換算する。
初期値4pxと32pxは、CRT testで調整した発光感を採用した値。
以前の2pxと16pxより広く、Nearは直近の発光としてやや広め、Farは広いhaloとなる。
下限・上限はアルゴリズムの厳密な限界ではなく、役割と調整しやすさに合わせて決めた。
Near/Farは独立なので、設定次第ではNearの方が広くなることも許容する。
Farの64px上限は幅に応じて増えるGaussianの描画負荷にも関係する。

StrengthはCore全体ではなく、HDR応答制限後のsourceに対する再配分率。
Near/Farの合計は設定範囲内で最大0.35となり、sourceの全部を周辺へ移すことはない。
現在の初期値はNearが0.1、Farが0.05で、合計15%のsourceを再配分する。
以前の0.06 / 0.01より周辺光を強く出す設定で、FarはNearより弱くする。
上限0.25と0.1自体に必然性はなく、見た目を確定した後に範囲を絞る余地がある。

HDR Limitは1のときsourceの最大成分を1に制限する。
初期値16では高輝度sourceが16へ漸近する。32は入力HDRの上限ではない。
以前の初期値2より制限が弱く、入力16のsource代表強度は約10.48になる。
式と過去の数値検証は [PHOSPHOR_BLOOM.md](PHOSPHOR_BLOOM.md) を参照。
