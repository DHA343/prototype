"""Validate and summarize the five contact-time methods from saved Godot results."""

import collections
import json
import math
import statistics
from pathlib import Path

EVIDENCE = Path(__file__).resolve().parents[1] / "evidence"
MODES = ("B", "B+2", "B+4", "B+8", "D2")


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8"))


def stats(values):
    values = sorted(values)
    if not values:
        return None
    return {"count": len(values), "median": statistics.median(values),
            "p95": values[math.ceil(len(values) * .95) - 1], "max": max(values)}


def angle(a, b):
    return abs(math.degrees(math.atan2(a[0]*b[1] - a[1]*b[0], a[0]*b[0] + a[1]*b[1])))


def classification(rows, mode, first=False):
    valid = [r for r in rows if not r["ambiguous"]]
    pairs = [(r, r["methods"][mode]["first"] if first else r["methods"][mode]) for r in valid]
    return {
        "classified": len(valid),
        "false_contacts": sum(v["found"] and not r["reference"]["found"] for r, v in pairs),
        "missed_contacts": sum(not v["found"] and r["reference"]["found"] for r, v in pairs),
        "false_shots": sum(v["shot"] and not r["reference"]["shot"] for r, v in pairs),
        "missed_shots": sum(not v["shot"] and r["reference"]["shot"] for r, v in pairs),
    }


def response_stats(rows, mode):
    pairs = [(r["methods"][mode]["first"], r["reference"]) for r in rows
             if not r["ambiguous"] and r["methods"][mode]["first"]["found"] and r["reference"]["found"]]
    return {"first_end_error_px": stats([math.dist(a["end"], b["end"]) for a, b in pairs]),
            "first_velocity_error_px_s": stats([math.dist(a["velocity"], b["velocity"]) for a, b in pairs]),
            "first_speed_error_px_s": stats([abs(math.hypot(*a["velocity"]) - math.hypot(*b["velocity"]))
                                               for a, b in pairs]),
            "first_angle_error_deg": stats([angle(a["velocity"], b["velocity"]) for a, b in pairs]),
            "first_angle_error_speed30_deg": stats([angle(a["velocity"], b["velocity"]) for a, b in pairs
                                                     if min(math.hypot(*a["velocity"]),
                                                            math.hypot(*b["velocity"])) >= 30]),
            "capped_updates": sum(r["methods"][mode]["discarded_ms"] > 0 for r in rows),
            "discarded_ms": sum(r["methods"][mode]["discarded_ms"] for r in rows),
            "max_correction_px": max(r["methods"][mode]["max_correction"] for r in rows),
            "unresolved": sum(r["methods"][mode]["unresolved"] for r in rows)}


def main():
    detection = read("refinement_audit.json")
    response = read("refinement_response.json")
    edges = read("refinement_edges_response.json")
    benchmark = read("refinement_benchmark.json")
    guards = read("refinement_guards.json")
    previous = read("continuous_audit.json")
    assert len(detection["cases"]) == 4500
    assert len(response["replay"]) == 2628 and len(edges["cases"]) == 2016
    for document in (detection, response, edges, guards):
        assert document["failures"] == 0
    assert [(r["suite"], r["id"], r["rate"], r["ambiguous"], r["reference"])
            for r in detection["cases"]] == [(r["suite"], r["id"], r["rate"], r["ambiguous"], r["reference"])
                                             for r in previous["cases"]]
    for row in detection["cases"]:
        for mode, count in (("B+2", 2), ("B+4", 4), ("B+8", 8)):
            values = row["methods"][mode]["counts"]
            assert values["extra_checks"] == (count + 1) * values["eligible"]
            assert values["final_invalid"] == 0 and values["eligible"] == values["refined"]
            assert values["coarse_checks"] == row["methods"]["B"]["counts"]["coarse_checks"]
    result = {"checks": {"detection": detection["checks"], "response": response["checks"],
                         "edges_response": edges["checks"], "guards": guards["checks"]},
              "failures": 0, "detection": {}, "response": {}, "integration": {},
              "benchmark": {}, "known_17": [], "ordering": {}, "guards": guards}
    valid = [r for r in detection["cases"] if not r["ambiguous"]]
    result["boundary_cases"] = len(detection["cases"]) - len(valid)
    for mode in MODES:
        detector = classification(detection["cases"], mode)
        both = [r for r in valid if r["reference"]["found"] and r["methods"][mode]["found"]]
        for key in ("time_error_ms", "point_error_px", "normal_error_deg"):
            detector[key] = stats([r["methods"][mode][key] for r in both])
        counts = collections.Counter()
        for row in detection["cases"]:
            counts.update(row["methods"][mode]["counts"])
        detector["counts_all4500"] = dict(counts)
        detector["by_rate"] = {str(rate): classification([r for r in detection["cases"] if r["rate"] == rate], mode)
                               for rate in (30, 60, 120)}
        result["detection"][mode] = detector
        all_response = response["replay"] + edges["cases"]
        result["response"][mode] = {
            "first_classification": classification(all_response, mode, first=True),
            "by_rate": {str(rate): response_stats([r for r in all_response if r["rate"] == rate], mode)
                        for rate in (30, 60, 120)},
            "all": response_stats(all_response, mode),
            "original60": response_stats([r for r in response["replay"]
                                           if r["rate"] == 60], mode),
            "edges": response_stats(edges["cases"], mode),
            "caps": [{"id": r["id"], "rate": r["rate"], "discarded_ms": r["methods"][mode]["discarded_ms"]}
                     for r in response["replay"] if r["methods"][mode]["discarded_ms"] > 0]}
        near = response["integration"][mode]["near_enemy"]
        assert len(near) == 84
        result["integration"][mode] = {
            "population": response["integration"][mode]["population"],
            "near_enemy": {"capped_inputs": sum(r["exhausted_updates"] > 0 for r in near),
                           "capped_updates": sum(r["exhausted_updates"] for r in near),
                           "discarded_ms": sum(r["discarded_ms"] for r in near),
                           "max_correction_px": max(r["max_correction_px"] for r in near),
                           "unresolved": sum(r.get("unresolved", 0) for r in near),
                           "caps": [{k: r[k] for k in ("ratio", "gap", "offset", "discarded_ms")}
                                    for r in near if r["exhausted_updates"] > 0]}}
        order = [r for r in response["ordering"] if r["mode"] == mode]
        assert len(order) == 10
        result["ordering"][mode] = {
            "clear_cases": len([r for r in order if not r["tie_band"]]),
            "clear_mismatches": [r for r in order if not r["tie_band"] and r["first"] != r["reference_first"]],
            "ties": [{k: r[k] for k in ("kind", "difference_ms", "first", "reference_first")}
                     for r in order if r["tie_band"]]}
        assert not result["ordering"][mode]["clear_mismatches"]
    for row in valid:
        if row["methods"]["B"]["shot"] != row["reference"]["shot"]:
            result["known_17"].append({"suite": row["suite"], "id": row["id"], "rate": row["rate"],
                                       "reference_shot": row["reference"]["shot"],
                                       "methods": {m: row["methods"][m]["shot"] for m in MODES}})
    assert len(result["known_17"]) == 17
    for group in ("original60", "moving_edges"):
        result["benchmark"][group] = {}
        for mode in MODES:
            rows = [r for r in benchmark["rounds"] if r["group"] == group and r["mode"] == mode]
            assert len(rows) == 7
            result["benchmark"][group][mode] = {
                "queries": rows[0]["queries"], "time_ms": stats([r["total_us"] / 1000 for r in rows]),
                "min_ms": min(r["total_us"] / 1000 for r in rows), "counts": rows[0]["counts"]}
    runtime = read("refinement_runtime.json")
    for live in runtime["results"]:
        mode = "D2" if live["mode"] < 0 else ("B" if live["mode"] == 0 else f"B+{int(live['mode'])}")
        saved = next(r for r in edges["cases"] if r["id"] == 87)["methods"][mode]
        assert math.dist(live["position"], saved["position"]) < .001
        assert math.dist(live["velocity"], saved["velocity"]) < .01
        assert live["first"]["shot"] == saved["first"]["shot"]
    result["runtime_matches_cli"] = True
    result["response_separation_examples"] = [
        {"id": row["id"], "rate": row["rate"], "case": row["case"],
         "reference": row["reference"], "methods": row["methods"]}
        for row in edges["cases"] if row["id"] in (1465, 1885, 1944)]
    (EVIDENCE / "refinement_audit_summary.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_report(result)
    for mode in MODES:
        print(mode, result["detection"][mode], result["response"][mode]["all"])
    print("All saved-data validation passed.")


def write_report(result):
    lines = [
        "# Bへの接触時刻絞り込みの比較（2026-11-21）", "",
        "## 結論", "",
        "本番は現行Bを維持する。B＋4は今回比較した回数の中で既知17件をすべて解消する最少の構成だが、"
        "30 Hzで新たな移動打ち切りが3条件発生し、近接Enemyでも打ち切りと位置補正が増えたため採用保留。"
        "B＋8も精度はよいが安定性の問題が残る。B＋2は誤打球2件が残る。D2も引き続き保留。", "",
        "main、PinballMotion、TableFlipper、Enemy、停止中のGodot標準判定、返球計算、③、"
        "上向き分離16回、接触反復上限8回は変更していない。追加コードは experiments/flippers/ 以下のみ。", "",
        "## 条件と実装", "",
        "- Godot 4.7.2 stable / Windows / headless。形状は左右・下端固定、上辺だけ動く単一四角形、厚み48 px。",
        "- 検出は既存と同じ4,500条件。元の876入力×3更新周波数のうち回転計画がある2,484条件と、"
        "左右・4辺・4角・半径6/24/36 pxを含む移動条件2,016件。30/60/120 Hzを比較。",
        "- 高精度参照と境界区分は continuous_audit.json のものをそのまま再利用。"
        "4,096時刻＋22回絞り込みによる参照で、2,048時刻との安定性確認済み。候補側からこの参照は使わない。",
        "- 境界35条件を別枠にし、分類4,465条件、両者接触2,206条件で誤差を集計。"
        "境界条件も実行・生データ保存・計算回数集計の対象。",
        "- B＋NはBの約4 px走査を維持。直前の点が幾何的に非接触、最初の採用点が幾何的に接触の"
        "場合だけN回二分探索し、接触側の時刻で接触情報を全部再計算する。半径の膨張や参照用判定は使わない。",
        "- 開始時の重なり、直前も重なっていたが応答条件で不採用だった場合は絞らない。"
        "再計算後にacceptが拒否した場合は元のB接触へ戻し、final_invalidへ記録する。",
        "- 支点距離による候補除外、回転終了での区間分割、残り時間の再検査を維持。"
        "最終接触の表面速度・打球状態はその時刻の回転／停止状態で再計算。",
        "- Bの計数版は本来のBと接触有無・時刻・打球状態が一致。検出中に球の位置・速度を変更しないことも確認。", "",
        "実装：[refined_swing.gd](../refined_swing.gd)、[応答アダプタ](../refined_motion.gd)。"
        "本番からは参照しない。", "",
        "## 検出結果", "",
        "| 方式 | 誤接触 / 漏れ | 誤打球 / 打球漏れ | 最大時刻差 ms | 最大接触点差 px | 最大法線差 ° |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for mode in MODES:
        d = result["detection"][mode]
        lines.append(f"| {mode} | {d['false_contacts']} / {d['missed_contacts']} | "
                     f"{d['false_shots']} / {d['missed_shots']} | {d['time_error_ms']['max']:.6f} | "
                     f"{d['point_error_px']['max']:.6f} | {d['normal_error_deg']['max']:.6f} |")
    lines += ["", "B＋4・B＋8・D2は30/60/120 Hzそれぞれでも離散分類の不一致0。"
              "B＋2に残る2件は追加条件id79（30 Hz）とid87（60 Hz）の小半径・上側の角の誤打球。"
              "既知17件の個別結果は集計JSONの known_17 に保存。", "",
              "| 方式 | 時刻差p95 ms | 接触点差p95 px | 法線差p95 ° |",
              "| --- | ---: | ---: | ---: |"]
    for mode in MODES:
        d = result["detection"][mode]
        lines.append(f"| {mode} | {d['time_error_ms']['p95']:.6f} | {d['point_error_px']['p95']:.6f} | "
                     f"{d['normal_error_deg']['p95']:.6f} |")
    lines += ["", "### 絞り込みの件数と追加計算", "",
              "4,500条件中2,226件が幾何的な区間を持ち、全件で絞り込みに成功した（境界20件を含む）。"
              "この単独検出群では開始重なり・直前重なり・最終不採用・停止状態の再計算差はいずれも0。"
              "開始重なり等は別の4件の検査で通過し、統合時のスキップ数も生データに保存。", "",
              "| 方式 | 元の検査回数 | 追加検査回数 | 幾何的な絞り込み可能件数 |",
              "| --- | ---: | ---: | ---: |"]
    for mode in MODES[:-1]:
        c = result["detection"][mode]["counts_all4500"]
        lines.append(f"| {mode} | {c['coarse_checks']:,} | {c['extra_checks']:,} | {c['eligible']:,} |")
    lines += ["", "追加回数はN回の二分探索＋最終再計算1回。B＋4なら5×2,226＝11,130回。"
              "D2の距離評価は合計166,314回、未解決0。ただしD2の距離評価1回とBの多角形接触1回の"
              "処理内容は異なるため、回数だけで負荷を比較しない。", "",
              "## 処理時間", "",
              "準備・入力読込・計画のコピー・応答・参照計算を除いた検出のみ。ウォームアップ1回を除き7回、"
              "方式の実行順を交代。Bは計数コピーでなく本番のsweepを直接使用。"
              "候補の補助関数・カウンタの負荷は含む。各セルは入力群全体の中央値で、1更新の処理時間ではない。", "",
              "| 方式 | 元の60 Hz・828計画 ms | 辺・角2,016条件 ms |",
              "| --- | ---: | ---: |"]
    for mode in MODES:
        b = result["benchmark"]
        lines.append(f"| {mode} | {b['original60'][mode]['time_ms']['median']:.3f} | "
                     f"{b['moving_edges'][mode]['time_ms']['median']:.3f} |")
    lines += ["", "B＋4はB比で元入力群約1.40倍、辺・角群約1.48倍。辺・角群ではD2より約58.5%短いが、"
              "元入力群ではD2の方が速い。『B＋少回数が常にD2より軽い』とは結論できない。"
              "値はこの実装・同一環境での測定で、描画や通常プレイ全体のFPSは比較していない。", "",
              "## 同じ応答への接続", "",
              "元の2,628条件と追加2,016条件の合計4,644条件で一更新を実行。③を有効にし、"
              "Bと同じ返球・上向き分離・反復を使用。停止中の標準判定も維持。"
              "元2,628条件のBは保存済みの更新終了位置・終了速度と一致。"
              "既知17件は実際の最初の応答でもB＋4・B＋8・D2で解消し、B＋2には2件残った。", "",
              "| 方式 | 一更新の打ち切り件数 | 破棄時間の合計 ms | 元入力60 Hzの最初の応答後終了位置差・最大 px |",
              "| --- | ---: | ---: | ---: |"]
    for mode in MODES:
        r = result["response"][mode]
        lines.append(f"| {mode} | {r['all']['capped_updates']} | {r['all']['discarded_ms']:.6f} | "
                     f"{r['original60']['first_end_error_px']['max']:.6f} |")
    lines += ["", "打ち切りはB＋4・B＋8・D2とも元入力id405/465/525の30 Hzのみ。"
              "追加辺・角2,016条件には打ち切りなし。B＋4では各0.400353 ms、B＋8では各0.694646 ms、"
              "D2では各0.751808 msを破棄した。8回の時刻・速度・法線・補正の履歴をcap_traceに保存。"
              "正確化による再接触を含むため、検出の誤判定とは断定しない。", "",
              "### 返球誤差と位置補正の区別", "",
              "| 方式 | 最初の返球速度ベクトル差・最大 px/s | 返球方向差・最大 °（両速度30 px/s以上） |",
              "| --- | ---: | ---: |"]
    for mode in MODES:
        r = result["response"][mode]["all"]
        lines.append(f"| {mode} | {r['first_velocity_error_px_s']['max']:.6f} | "
                     f"{r['first_angle_error_speed30_deg']['max']:.6f} |")
    lines += ["", "30 px/s未満のほぼ停止した返球は方向角が不安定になるので別集計。"
              "速度制限なしの最大角度はB＋4で8.681°だが、該当id1944の返球速度は約0.25 px/s"
              "（参照約0.21 px/s）で、速度差約0.06 px/sの事例。生データにはこの角度も残す。", "",
              "上向き分離の問題は未解決。追加した下面・下側の角ではBでも約203 px、B＋4で約204.23 pxの"
              "補正を確認した。微小な食い込みの有無により『0.15 pxのみ』と『板上方まで移動』が切り替わる。"
              "そのため全4,644条件の最初の応答後終了位置差には約200 pxの値が残る。"
              "これは接触点誤差0.235 px等と混同しない。", "",
              "参照は最初の接触の応答だけで、二回目以降を含む完全な正解軌跡ではない。"
              "さらに参照接触の表現には半径＋0.0005 pxを使用しており、境界での分離分岐自体は数値に敏感。"
              "全体の位置差をそのまま検出器の誤差・ゲーム上の正解からの距離として採点しない。"
              "id1465/1885の補正の切り替わりを集計JSON response_separation_examples に保存。", "",
              "## main配置での統合", "",
              "左右フリッパー・壁・バンパー・③を使用。1球／20球は各6秒、同じ初期シード、"
              "球同士の接触なし。近接Enemyは既存の84配置を各1秒、Enemy本来の独立移動のまま比較。", "",
              "| 方式 | 近接Enemyの打ち切り配置 / 84 | 破棄時間合計 ms | 最大位置補正 px |",
              "| --- | ---: | ---: | ---: |"]
    for mode in MODES:
        n = result["integration"][mode]["near_enemy"]
        lines.append(f"| {mode} | {n['capped_inputs']} | {n['discarded_ms']:.6f} | {n['max_correction_px']:.6f} |")
    lines += ["", "B＋8の打ち切り件数はBと同じ3配置だが、内訳は同じではない。"
              "Bではratio0.70/gap36/offset0、B＋8ではratio0.90/gap12/offset0が含まれる。"
              "件数が同じというだけで安定性が同等とはしない。全方式の未解決検出0。", "",
              "1球／20球試験は全方式で反復上限0、検査範囲内の有効状態での下抜け0。"
              "20球の最大補正はB58.55 px、B＋2 57.48 px、B＋4 56.53 px、B＋8 55.53 px、D2 0.15 px。"
              "長い軌跡は早期の微小な差で分岐するため、打球数や最大補正の差をそのまま検出の正誤にしない。", "",
              "### 壁・Enemyとの接触順序", "",
              "各方式で壁5条件＋Enemy5条件。独立参照の回転板との接触時刻から障害物への接触予定を"
              "−2 / −0.1 / 0 / ＋0.1 / ＋2 msずらした。同じ更新開始を時刻0とする。"
              "壁は矩形、Enemyは半径30 pxの実体を静止配置し、試験更新中にはEnemyを別途動かさない。", "",
              "±2 msの明確な順序は全方式4/4一致（計20/20）。±0.1/0 msは標準余裕0.03 pxと"
              "各方式の時刻精度を含む近接条件として別枠に保存し、正誤の結論には用いない。"
              "これで移動中のEnemyとの同時刻連成全般まで保証したとは扱わない。", "",
              "## 許容範囲と採否", "",
              "この有限な入力群から普遍的な許容誤差は確定しない。次段階の比較用の暫定目安として、"
              "誤接触・漏れ・誤打球・打球漏れ0、接触点差0.25 px以下、法線差1°以下、"
              "返球方向差1°以下（両返球速度30 px/s以上）を置くとB＋4が通過する。"
              "接触時刻は最大0.554 ms／p95 0.0545 msだったが、時間だけを許容条件にせず、"
              "位置・打球状態・返球結果を合わせて評価する。", "",
              "これは測定後の候補選定用の目安であり、事前に定めて合格した製品仕様ではない。"
              "0.25 pxと1°をゲームの見た目として許容するかは、安定性改善後の代表プレイ確認が必要。"
              "位置補正や残り時間破棄はこの許容枠に含めない。", "",
              "- B＋2：不採用候補。既知の誤打球を2件残す。",
              "- B＋4：検出精度と簡単さでは候補。今回試した回数のうち最少で17件を解消するが、統合の悪化により本番採用保留。",
              "- B＋8：精度の比較基準として保持。B＋4より負荷が増え、反復問題も残るため現時点では採用しない。",
              "- D2：精度の比較基準として保持。辺・角の負荷と既知の反復問題から引き続き保留。",
              "- 本番B：維持。既知17件は解決済みとはせず残件として保持する。", "",
              "次の独立課題は、接触後の上向き分離の不連続、大きな補正、再接触時の残り時間の扱い。"
              "検出器や反復上限をさらに増やす作業には進んでいない。", "",
              "## 検証記録・再実行", "",
              "- 検出＋統合の実装検査34,958件、追加辺・角の応答13,172件、区間ガード4件、いずれも失敗0。"
              "（検出ファイルの15,727件は34,958件の内数。）",
              "- 既存の共通移動回帰検査 migration_test.gd：96件、失敗0。",
              "- Godot AIでmainの実行中にもid87を5方式で再現しCLI結果と一致。B/B＋2は誤打球、"
              "B＋4/B＋8/D2は通常反射。確認後は実行停止、シーン保存なし。",
              "- JSONと既存参照の同一性、件数、N＋1の追加回数、元のBとの一致、RuntimeとCLIの一致を"
              "Python集計で検証済み。CLIには既存ポストプロセスのUID警告が3件あり、パスで読み込まれた。"
              "今回のスクリプトエラーは最終実行0。", "",
              "```powershell",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/refinement_audit.gd",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/refinement_edges_response.gd",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/refinement_benchmark.gd",
              "godot --headless --path . --script res://experiments/flippers/tests/refinement_guards.gd",
              "godot --headless --path . --script res://pinball/tests/migration_test.gd",
              "python experiments/flippers/tests/summarize_refinement_audit.py", "```", "",
              "集計では保存済み refinement_runtime.json も照合する。これを作り直す場合はGodot AIで"
              "mainをautosave=falseで起動し、game_evalで次を実行後、実行停止する。", "",
              "```gdscript",
              'return load("res://experiments/flippers/tests/refinement_runtime.gd").run(get_tree().current_scene)',
              "```", "",
              "### 詳細データ", "",
              "- [4,500条件の検出結果](refinement_audit.json)",
              "- [2,628条件の応答・近接Enemy・複数球・接触順序](refinement_response.json)",
              "- [追加2,016条件の応答](refinement_edges_response.json)",
              "- [7回の処理時間](refinement_benchmark.json)",
              "- [ガード検査](refinement_guards.json)",
              "- [Godot AIの実行時確認](refinement_runtime.json)",
              "- [分布・個別17件・採点集計](refinement_audit_summary.json)",
              "- [検証スクリプト](../tests/refinement_audit.gd)",
              "- [集計スクリプト](../tests/summarize_refinement_audit.py)", ""]
    (EVIDENCE / "refinement_audit.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
