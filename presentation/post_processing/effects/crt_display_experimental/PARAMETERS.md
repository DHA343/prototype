# CRT parameter ranges and defaults

Resource の初期値は見た目を調整するための出発点。
実機計測から確定した値ではなく、以下の数式上の意味と調整方針を持つ。
Scene に保存された値は初期値を上書きする。

| 項目 | 範囲 | 初期値 | step | 意味・根拠 |
| --- | --- | --- | --- | --- |
| Scanline Count | 180〜720 | 360 | 1 | 再構成する信号の行数。1080pで初期値は1行あたり3出力px。範囲は調整用 |
| Sharpness | 0.5〜1.0 | 0.67 | 0.01 | 横方向のkernelを広げるほど低い値。範囲は半径2〜1サンプル間隔に対応 |
| Signal Pitch | 0.5〜3.0 px | 1.5 px | 0.1 | 横方向の信号サンプル間隔。見た目の調整値で、解像度による自動換算なし |
| Beam Width | 0.75〜1.25 lines | 1.0 line | 0.01 | FWHMが走査線間隔と一致し、均一信号の隣接Beam合計が一定になる基準。範囲は光量補正近似に合わせて絞った |
| Legacy Mask Strength | 0〜1 | 0.5 | 0.01 | Legacy Maskなしと完全適用の混合比。Phosphor版では無効・編集不可 |
| Cell Sampling | Reference / Integrated | Integrated | — | 同一shaderで従来描画と解析coverageを比較。Legacy版では編集不可 |
| Cell Scale | 1〜4 | 1 | 1 | Referenceのみ。6px triad基準の整数倍率。Integrated / Legacy版では編集不可 |
| Triad Pitch | 2.0〜6.0 px | 2.5 px | 0.1 | Integratedのみ。RGB triadのoutput pixel幅。高さ2px固定、解像度による自動換算なし |
| Signal Sampling | Two Samples / Four Samples | Two Samples | — | Integratedのみ。pixel内の横方向Signal sampling数。apertureは解析積分 |
| Phosphor Brightness | 0.5〜3.0 | 1.0 | 0.1 | 占有率を補償した後の全RGB共通倍率。Referenceはprofile平均も補償、Integratedは矩形coverageを3倍。Legacy版では編集不可 |
| Brightness Compensation | 0.5〜2.0 | 1.0 | 0.01 | 最終RGBの倍率。1は追加補正なし。範囲は半分〜2倍の調整用 |
| Near Width | 0.5〜8.0 px @1080p | 4.0 px | 0.1 | すぐ周囲のにじみ。現在のCRT testで使用する調整値を初期値に採用 |
| Far Width | 4.0〜64.0 px @1080p | 32.0 px | 0.1 | 広いhalo。現在のCRT testで使用する調整値を初期値に採用 |
| Near Strength | 0〜0.25 | 0.1 | 0.01 | sourceからNearへ再配分する割合。初期値10%、上限25%は調整用 |
| Far Strength | 0〜0.1 | 0.05 | 0.001 | sourceからFarへ再配分する割合。初期値5%、上限10%は調整用 |
| HDR Limit | 1.0〜32.0 | 16.0 | 0.1 | sourceの最大RGB成分の漸近値。1は意味のある端点、16と上限32は調整用 |

step は 1 / 0.1 / 0.01 / 0.001 の10進刻みに統一する。
Far Strength は0.001刻みで微調整する。初期値0.05の2%ずつ調整できる。
初期値・範囲・Scene保存値はstep変更に合わせて丸めない。

## Sharpness

`w(d) = 1 - smoothstep(0, 1, d * sharpness)` を正規化して使用する。
kernelの半径とFWHMは、ともに `1 / sharpness` サンプル間隔となる。
0.67では約1.493間隔、Signal Pitch = 1.5ならkernel自体のFWHMは約2.239出力px。
これはkernelの幅であり、再構成された図形の実測FWHMと常に一致するわけではない。
0.5〜1.0は固定5サンプルの中にkernelを収め、広めから狭めへ調整できる範囲。
0.67に物理的・数学的な必然性はなく、必ず0.67でなければならないわけではない。

## Beam Width

`profile(d) = cos(πd/2)^p`、`p = ln(0.5) / ln(cos(π * width / 4))`。
width = 1ならp = 2で、均一信号では隣接する2本の合計が一定になる基準点。
初期値はこの基準に合わせて1.0とする。光量補正倍率も1となる。
1より細いと走査線の隙間が目立ち、1より太いと重なりが強くなる。

旧Width = 0.42の式では `p = 2 + 0.5 * (1/0.42 - 1/0.55) ≈ 2.281385`。
このprofileのFWHMは約0.943104で、以前の初期値0.94は旧形状をほぼ保つ換算値だった。
現在は旧設定の維持よりも、数学的に意味のある1.0を調整の基準とする。

現在の光量補正はpに対する多項式近似で、旧範囲0.5〜1.25全体での精度は成立しない。
選択範囲を0.75〜1.25に絞り、初期値は1.0を維持する。
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
Beamの式は変更していない。

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
