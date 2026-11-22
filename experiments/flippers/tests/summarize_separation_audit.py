"""Validate the four independent factors and publish their measured effects."""

import collections
import hashlib
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"
MODES = ("current", "three", "normal_new_only", "combined")
LABELS = ("現行", "3条件のみ", "法線分離のみ", "3条件＋法線分離")


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8-sig"))


def write(name, document):
    (EVIDENCE / name).write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n",
                                 encoding="utf-8")


def states(rows):
    counts = collections.Counter()
    for row in rows:
        counts.update(row["states"])
    return dict(counts)


def response_stats(rows):
    events = [event for row in rows for event in row["events"]]
    normal = [event for event in events if event["separation_policy"] == "normal_new_contact"]
    return {"cases": len(rows), "contacts": len(events),
            "capped_updates": sum(row["discarded_ms"] > 0 for row in rows),
            "discarded_ms": sum(row["discarded_ms"] for row in rows),
            "max_correction_px": max(row["max_correction_px"] for row in rows),
            "shots": sum(row["shots"] for row in rows), "states": states(rows),
            "repeat_A": sum(row["repeat_A"] for row in rows),
            "normal_events": len(normal),
            "normal_residual_contact": sum(event["post_separation_overlap"] for event in normal),
            "positive_geometric_depth": sum(event.get("geometric_contact_depth_px", 0) > 0 for event in events),
            "zero_geometric_depth": sum(event.get("geometric_contact_found", False)
                                         and event["geometric_contact_depth_px"] == 0 for event in events),
            "margin_only": sum(event.get("geometric_contact_found") is False for event in events)}


def percentile(values, fraction):
    return sorted(values)[math.ceil(len(values) * fraction) - 1]


def cpu_stats(values):
    return {"samples": len(values), "mean_us": statistics.mean(values),
            "median_us": statistics.median(values), "p95_us": percentile(values, .95),
            "p99_us": percentile(values, .99), "max_us": max(values)}


def main():
    response = read("separation_response.json")
    diagnostics = read("separation_diagnostics.json")
    benchmark = read("separation_benchmark.json")
    previous = read("shot_response.json")
    detection = read("shot_detection.json")
    runtime = read("separation_runtime.json")
    for document in (response, diagnostics, benchmark):
        assert document["failures"] == 0
    assert len(response["cases"]) == 4644 and len(diagnostics["overlaps"]) == 288
    assert len(diagnostics["focused"]) == 5 and len(diagnostics["transitions"]) == 20
    assert len(benchmark["rounds"]) == 8 and benchmark["rounds"][0]["warmup"]
    assert benchmark["fixtures"] == 4644
    for path, digest in diagnostics["production_sha256"].items():
        assert hashlib.sha256((ROOT.parents[1] / path).read_bytes()).hexdigest() == digest
        assert benchmark["production_sha256"][path] == digest
    for row, old in zip(response["cases"], previous["cases"], strict=True):
        assert (row["suite"], row["id"], row["rate"]) == (old["suite"], old["id"], old["rate"])
        for mode in MODES[:3]:
            for key, tolerance in (("position", .001), ("velocity", .01)):
                assert math.dist(row["methods"][mode][key], old["methods"][mode][key]) < tolerance
        for before, after in (("current", "normal_new_only"), ("three", "combined")):
            left, right = row["methods"][before]["events"], row["methods"][after]["events"]
            assert bool(left) == bool(right)
            if left:
                assert abs(left[0]["time_ms"] - right[0]["time_ms"]) < 1e-6
                assert left[0]["shot"] == right[0]["shot"]
                for key, tolerance in (("point", .001), ("normal", .001), ("velocity", .01)):
                    assert math.dist(left[0][key], right[0][key]) < tolerance
    for row in diagnostics["overlaps"]:
        for before, after in (("current", "normal_new_only"), ("three", "combined")):
            for key, tolerance in (("position", .001), ("velocity", .01)):
                assert math.dist(row["methods"][before][key], row["methods"][after][key]) < tolerance
    for live in runtime["results"]:
        row = next(row for row in response["cases"] if row["suite"] == "moving_edges" and row["id"] == live["id"])
        expected = row["methods"][MODES[int(live["mode"])]]
        assert math.dist(expected["position"], live["position"]) < .001
        assert math.dist(expected["velocity"], live["velocity"]) < .01 and live["exceptions"] == 0
    for row in runtime["controls"]:
        rule = 2 if row["mode"] in (1, 3) else 0
        assert row["flippers"] == [rule, rule]
        assert row["motion"] == ("res://experiments/flippers/separation.gd" if row["mode"] >= 2 else "res://pinball/motion.gd")
    summary = {"failures": 0, "audit_checks": diagnostics["checks"],
               "benchmark_checks": benchmark["checks"], "response": {}, "overlaps": {},
               "integration": {}, "cpu": {}, "focused": diagnostics["focused"],
               "transitions": diagnostics["transitions"], "runtime_matches_cli": True,
               "production_sha256": diagnostics["production_sha256"]}
    for mode in MODES:
        summary["response"][mode] = response_stats([row["methods"][mode] for row in response["cases"]])
        summary["overlaps"][mode] = response_stats([row["methods"][mode] for row in diagnostics["overlaps"]])
        integration = diagnostics["integration"][mode]
        near = integration["near_enemy"]
        assert len(near) == 84 and len(integration["population"]) == 2
        counts = collections.Counter()
        state_counts = collections.Counter()
        introduced = collections.Counter()
        for row in near:
            state_counts.update(row["observed"]["states"])
            counts.update({key: value for key, value in row["observed"].items() if key != "states"})
            introduced.update(f'{event["state_class"]}:{event["separation_policy"]}'
                              for event in row.get("E_events", []) if event["environment"]["introduced"])
        summary["integration"][mode] = {
            "near": {"capped_inputs": sum(row["exhausted_updates"] > 0 for row in near),
                     "capped_updates": sum(row["exhausted_updates"] for row in near),
                     "discarded_ms": sum(row["discarded_ms"] for row in near),
                     "max_correction_px": max(row["max_correction_px"] for row in near),
                     "states": dict(state_counts), "observed": dict(counts),
                     "introduced_policies": dict(introduced)},
            "population": integration["population"],
            "caps": [row for row in near if row["exhausted_updates"]],
            "largest": max(near, key=lambda row: row["max_correction_px"])}
        rounds = [round_["times_us"][mode] for round_ in benchmark["rounds"] if not round_["warmup"]]
        assert all(len(values) == 4644 for values in rounds)
        values = [value for round_ in rounds for value in round_]
        summary["cpu"][mode] = cpu_stats(values)
        summary["cpu"][mode]["round_mean_us"] = [statistics.mean(values) for values in rounds]
        for label, contact in (("noncontact", False), ("contact", True)):
            indices = [i for i, row in enumerate(response["cases"])
                       if bool(row["methods"]["current"]["contacts"]) == contact]
            summary["cpu"][mode][label] = cpu_stats([values[i] for values in rounds for i in indices])
            summary["cpu"][mode][label]["fixtures"] = len(indices)
    summary["bottom_example"] = next(row for row in response["cases"]
                                     if row["suite"] == "moving_edges" and row["id"] == 1885)
    summary["remaining_first_shot_mismatches"] = [row for row in detection["cases"]
        if not row["ambiguous"] and row["methods"]["three"]["shot"] != row["references"]["three"]["shot"]]
    assert [int(row["id"]) for row in summary["remaining_first_shot_mismatches"]] == [615, 623]
    assert all(value["normal_residual_contact"] == 0 for value in summary["response"].values())
    assert all(row["observed"]["E_limited"] == 0
               for mode in MODES for row in diagnostics["integration"][mode]["near_enemy"])
    write("separation_audit_summary.json", summary)
    report(summary)
    print("Four-mode saved-data validation passed; first contact/velocity unchanged by separation.")
    for mode in MODES:
        print(mode, "single", summary["response"][mode]["max_correction_px"],
              "near", summary["integration"][mode]["near"], "mean_us", summary["cpu"][mode]["mean_us"])


def report(s):
    lines = ["# 3条件＋新接触だけ法線分離の組み合わせ検証（2026-11-22）", "",
             "## 結果と判断", "",
             "ユーザーが操作感の同等性を確認した3条件を、実験上の打球仕様として固定した。"
             "新接触だけを法線方向に分離する処理との組み合わせを、4構成で比較した。"
             "組み合わせ案は新接触の大きな補正を減らし、今回の範囲で打ち切りを増やさなかった。"
             "一方、③解除時の重なり・Enemyへの補正後の食い込み・残り時間破棄が残る。本番への反映は行っていない。", "",
             "| 構成 | 単独4,644条件の最大補正 px | 単独打ち切り | 近接Enemyの打ち切り配置 / 84 | 近接最大補正 px |",
             "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row, near = s["response"][mode], s["integration"][mode]["near"]
        lines.append(f'| {label} | {row["max_correction_px"]:.5f} | {row["capped_updates"]} | {near["capped_inputs"]} | {near["max_correction_px"]:.5f} |')
    lines += ["", "法線分離の効果は、打球条件を現行・3条件のどちらにした場合でも確認できた。"
              "3条件だけでは大きな位置補正や打ち切りは改善しない。"
              "全更新の打球総数は軌道と再接触回数に依存するため、打球仕様の正否の指標にはしない。", "",
              "**次の優先対象は③解除時の回復と周囲との干渉である。** 3条件＋新接触の法線分離は実験上の候補として残す。"
              "B＋4／D2の採用、回復方向の変更、反復上限の拡大は今回決めていない。", "",
              "## 固定条件と比較方法", "",
              "4構成は現行打球＋従来分離、3条件＋従来分離、現行打球＋新接触の法線分離、3条件＋新接触の法線分離。"
              "検出B（約4 px走査と回転終了での区切り）、停止中のGodot標準判定・回復、返球計算、③、"
              "上向き分離の探索16回、分離余裕0.15 px、共有の最大8接触を維持した。予算分離は使っていない。", "",
              "法線分離は回転中の独自接触のうち、同じ球と同じ板について物理更新開始時・移動区間開始時の"
              "両方で幾何的に非接触だったものだけに適用する。補正は `normal * (max(depth, 0) + 0.15)`。"
              "それ以外の独自接触は現行の上向き分離、標準接触はGodot回復のままである。"
              "したがってB・C・Dをすべて上向き独自処理へ変えたわけではない。", "",
              "3条件は上昇・上辺と両端への接触・物理表面速度に対する相対接近。60°制限と根元X除外は選別に使わない。"
              "側面・下面・保持・下降では通常反射を維持する。端点は隣接面と共有され得るため、"
              "『側面扱いなら端点でも必ず打球禁止』という追加仕様は設けていない。面分類の許容差約0.002 pxは固定。", "",
              "| 試験 | 条件数・範囲 |", "| --- | --- |",
              "| 単独更新 | 既存2,628＋辺・角2,016＝4,644条件 × 4構成。半径6/24/36、30/60/120 Hz |",
              "| 開始重なり | 288条件 × 4構成。左右、上面・側面・下面・角、浅い／深い重なり |",
              "| ③解除／停止境界 | 5状態 × 4構成＝20実行 |",
              "| 近接Enemy | 84配置 × 4構成、各60更新。Enemyは既存独立移動のまま |",
              "| 複数球 | 各構成1球・20球、各360更新。左右・壁・バンパー・③あり、球同士の衝突なし |",
              "| 重点再現 | 戻り板30 Hzの405/465/525、打球漏れ615/623。4構成 × B/B＋4/D2 |",
              "| CPU | 同じ4,644入力の1更新、8巡中1巡ウォームアップ、7巡測定。構成順を巡回 |", "",
              "今回新しい検出方式は作っていない。重点再現のB＋4／D2は原因切り分け用に既存実験を呼び出した。", "",
              "## A〜Dの分類と再接触履歴", "",
              "A＝更新開始・区間開始とも非接触。B＝更新開始時に接触。C＝更新開始は非接触だが区間開始で接触。"
              "D＝③がこの更新で解除され、更新開始時に板と接触している。E＝周囲への干渉でA〜Dと独立。"
              "接触には深さ0の境界を含み、実際の深さも別項目で保存する。"
              "同じ板への接触回数・先行接触で速度が変わったかも保存し、A〜Dとは混同しない。", "",
              "| 構成 | 単独Aイベント | うち同板への再接触 | 近接A | B | C | D | その他の物体 |",
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row = s["response"][mode]
        near = s["integration"][mode]["near"]["states"]
        lines.append(f'| {label} | {row["states"]["A"]} | {row["repeat_A"]} | {near["A"]} | {near["B"]} | {near["C"]} | {near["D"]} | {near["other"]} |')
    lines += ["", "単独条件はすべて開始非接触だが、同じ更新内の本当の再接触もAになり得る。"
              "組み合わせ案でもAのうち155イベントは同じ板への再接触で、Aを『初回接触だけ』と解釈しない。"
              "近接のCは1イベント。ratio=0.05/gap=72/offset=0の更新23で、先行反射後に上面へ再接触し、"
              "標準回復後の幾何的深さは約0.00634 px、速度差は約0.36983 px/sだった。"
              "この事例を深い埋まりや反復上限の原因とはしない。", "",
              "独自接触の深さ、標準接触のGodot報告深さ、同時刻の幾何的深さは別項目で保持した。"
              "特に標準の報告深さを、そのまま分離後に残った幾何的食い込み量とは扱わない。", "",
              "## 新接触で改善したもの", "",
              "組み合わせ案で法線分離を適用した2,381イベントは、補正直後・同じ接触時刻の対象板との"
              "幾何判定で残存接触0。これは後の再接触や他物体への非干渉を保証するものではない。", "",
              "代表例はmoving_edgesのid=1885、30 Hz、右板下面、半径36 px。検出時刻0.617284 ms、"
              "深さ2.022217 px、最初の反射速度は両案とも同じ。上向き201.7132 pxが下向き2.172217 pxへ変わった。"
              "4,644条件すべてで、分離だけを変えたペアの最初の接触時刻・位置・法線・打球状態・応答速度が一致した。"
              "以後の接触と最終軌道が変わるのは、補正位置の違いによる。", "",
              "開始重なり288条件では、法線分離の有無で最終位置0.001 px未満・速度0.01 px/s未満の一致を確認。"
              "最大204.17963 pxの上向き補正は4構成すべてに残る。ここを改善したという結果ではない。", "",
              "③解除／停止境界20実行は打ち切り0。③解除の停止板ではGodot回復、回転中では既存の上向き回復が使われ、"
              "解除時の補正は約31.18〜36.56 px。組み合わせ案でも同じ。", "",
              "## 残った近接Enemyの問題", "",
              "| 組み合わせ案の配置 | 最初の上限到達更新（0起算） | 8イベントの速度変化 | 破棄時間 ms |",
              "| --- | ---: | --- | ---: |"]
    for row in s["integration"]["combined"]["caps"]:
        tick = next(tick for tick in row["diagnostics"] if tick["discarded_ms"] > 0)
        changed = sum(event["changed"] for event in tick["events"])
        lines.append(f'| ratio={row["ratio"]}, gap={row["gap"]:g}, offset={row["offset"]:g} | {tick["update_index"]} | {changed}回変化・{len(tick["events"])-changed}回不変 | {tick["discarded_ms"]:.6f} |')
    lines += ["", "両方とも③解除時のDで、8イベントすべて標準のLeftFlipper接触。"
              "接触時刻と残り時間は進んでおり、同じ時刻・同じ状態を無限反復しているわけではない。"
              "`changed`は速度差0.01 px/s超という既存Recorderの区分で、物理的な衝突／回復の厳密な分類ではない。"
              "この事実から、8回を増やすだけで解決すると判断しない。", "",
              "最大60.60965 pxはratio=0.9/gap=3/offset=0。③解除時に右側面へ24.49072 px重なり、"
              "上向き分離を行った。対象板の重なりは解消したが、補正前にはなかったEnemyへの重なりを補正後に作った。"
              "この接触で速度は変わらず、接触時刻0、残り16.66667 msのままだった。"
              "法線分離対象のAではないため、今回の変更では残る。", "",
              "## E：補正と周囲の干渉", "",
              "| 構成 | 補正前に他物体と接触 | 補正後に接触 | 新規に接触相手を作ったイベント | 経路のみ接触 |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        observed = s["integration"][mode]["near"]["observed"]
        lines.append(f'| {label} | {observed["E_before"]} | {observed["E_after"]} | {observed["E_introduced"]} | {observed["E_path_only"]} |')
    lines += ["", "件数の単位は近接84配置における補正イベントで、配置数や被衝突物体数ではない。"
              "組み合わせ案の新規24イベントはすべてDで、上向き独自回復13、Godot回復11。"
              "今回のAの法線分離が新規干渉を作った事例は、この近接試験ではなかった。"
              "ただし新規干渉は現行23→組み合わせ24で、総数が減ったとは言えない。"
              "軌道の分岐を含むため、差1件を直ちに新接触分離の誤動作とも断定しない。", "",
              "観測は球を動かさず、補正前・補正後の円形照会と補正ベクトルのスイープを実施した。"
              "補正後だけの確認では見落とす薄壁通過を専用ケースで検出し、前後とも非接触でも経路接触を記録できることを確認。"
              "`cast_motion()`は開始重なりを無視するため、前後の`intersect_shape()`を併用する。"
              "[Godot公式 PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)。", "",
              "別フリッパーは物理世界の更新終了姿勢から除外し、接触時刻の四角形を構成して"
              "`Shape2D.collide()`／`collide_with_motion()`で検査した。別板がすでに終了姿勢にある専用ケースで時刻の整合も確認。"
              "[Godot公式 Shape2D](https://docs.godotengine.org/en/stable/classes/class_shape2d.html)。"
              "他物体はBが標準照会する時点の物理世界を使う。Enemyの過去姿勢を復元する連続判定ではない。", "",
              "観測余裕は0 px。Godot接触の余裕0.03 pxとは別。接触対象自身・既存例外・③の対象を適切に除外した。"
              "前後照会の128結果上限へ到達した事例は0。接触の存在から挟み込みが必ず持続するとまでは判断しない。"
              "観測結果で補正方向・速度・接触順序は変えていない。", "",
              "## 重点条件と検出誤差", "",
              "30 Hzの405/465/525は、組み合わせ案のB・B＋4・D2とも7イベントで完走し、打ち切り0。"
              "従来分離のB＋4／D2で8回へ達した既知事例は、新接触の法線分離で再現しなかった。"
              "ただし、これで精度向上方式を本番採用したわけではない。", "",
              "3条件の参照に対するBの打球漏れ615（60 Hz）・623（120 Hz）は組み合わせ案でも残る。"
              "両方とも最初の接触で打球せず、B＋4／D2では打球する。分離は検出後の処理なので、"
              "最初の接触時刻の遅れと相対接近の符号反転を直さない。"
              "従来ルールの誤打球3＋打球漏れ14と、新ルール自身の残存2件は別の基準である。", "",
              "## CPU負荷", "",
              "headless、Godot 4.7.2、60固定フレームの進行。同じ4,644入力を毎回リセットし1更新だけ計測。"
              "設定・リセット・JSON保存は計測外、`ball.advance()`内を計測した。"
              "履歴・幾何診断・周囲観測を行わない実験部品を使い、法線分離のための開始接触照会は計測に含めた。"
              "全18,576組で診断版と最終位置・速度が一致し、例外解除も確認した。", "",
              "| 構成 | 平均 µs | 中央値 µs | p95 µs | p99 µs | 最大 µs |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row = s["cpu"][mode]
        lines.append(f'| {label} | {row["mean_us"]:.2f} | {row["median_us"]:g} | {row["p95_us"]:g} | {row["p99_us"]:g} | {row["max_us"]:g} |')
    lines += ["", "各構成32,508サンプル。1巡をウォームアップとして除外し、7巡の全サンプルを集計。"
              "順番を巡回して連続測定の偏りを抑えたが、同一PCでの局所計測でありゲーム全体のFPS保証ではない。"
              "最大値はOS等の影響を含むため、一つの最大値だけで優劣を決めない。", "",
              "| 同じ入力群（現行の初回試験で分類） | 条件数 | 現行の平均 µs | 組み合わせの平均 µs |",
              "| --- | ---: | ---: | ---: |"]
    for key, label in (("noncontact", "接触なし"), ("contact", "接触あり")):
        left, right = s["cpu"]["current"][key], s["cpu"]["combined"][key]
        lines.append(f'| {label} | {left["fixtures"]} | {left["mean_us"]:.2f} | {right["mean_us"]:.2f} |')
    lines += ["", "接触ありでは上向き探索・再接触の削減が効いた一方、接触なしでは更新開始の照会が追加コストとなった。"
              "今回の構成比での平均改善を、常に無条件に軽いという結論にはしない。"
              "3条件の部品は親の旧判定を一度計算してから選別を上書きする実験実装なので、最小演算数の本番実装ではない。", "",
              "## 実行確認・再現手順", "",
              f'機械検査は監査{s["audit_checks"]:,}件、診断なし版との照合等{s["benchmark_checks"]:,}件、'
              '既存の移行回帰96件で失敗0。Pythonで既存3構成の4,644出力、本番8ファイルのSHA-256、'
              '最初の接触の一致、開始重なり、描画実行の結果も検証した。', "",
              "Godot AIで`separation_preview.tscn`の描画付き起動と4方式のキー処理を実行。"
              "id=96と1885を各方式で再現し、診断を持たない実験部品の終了位置・速度がCLIと一致した。"
              "手触りの確認は今回ユーザーが示した『同等』という評価を使用し、自動試験だけで操作感の同等性を断定していない。"
              "確認後のEditorは停止状態へ戻した。", "",
              "```powershell",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/separation_audit.gd",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/separation_benchmark.gd",
              "godot --headless --path . --script res://pinball/tests/migration_test.gd",
              "python experiments/flippers/tests/summarize_separation_audit.py",
              "```", "",
              "実験シーンは`experiments/flippers/separation_preview.tscn`。初期値は組み合わせ案。"
              "1＝現行、2＝3条件のみ、3＝法線分離のみ、4＝組み合わせ、R＝球リセット。A/D/Spaceは既存操作。"
              "本番のmainシーン・起動設定は変更していない。", "",
              "## 保存データ", "",
              "- [単独応答](separation_response.json)：全4,644条件×4、接触時刻・面・速度・残り時間・補正・前後の干渉。",
              "- [統合診断](separation_diagnostics.json)：初期288、重点5、近接84×4、複数球、遷移20。"
              "`state_events`はB/C/Dと同板再接触、`E_events`は周囲干渉、`diagnostics`は大補正・上限到達の更新。",
              "- [CPU生データ](separation_benchmark.json)：ウォームアップ含む8巡・入力順を維持したµs値。",
              "- [描画付き実行](separation_runtime.json)、[集計](separation_audit_summary.json)。",
              "- [打球仕様と履歴](../shot_rules.md)、[前回の独立比較](shot_audit.md)。", "",
              "詳細と再実行用ソースは、SHA-256付きの同一一式をDesktopにも保存する。"
              "測定の対象は指定した再現集合で、通常プレイの発生率やあらゆる配置の非干渉を証明するものではない。", ""]
    (EVIDENCE / "separation_audit.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
