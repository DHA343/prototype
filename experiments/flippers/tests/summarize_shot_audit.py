"""Summarize shot rules and independent response factors with per-rule references."""

import collections
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"
MODES = ("current", "without_angle", "three", "normal_new_only", "split_budgets")
LABELS = ("現行", "60°のみ除外", "3条件", "新接触だけ法線分離", "予算分離")


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8"))


def detection_stats(rows, mode):
    valid = [r for r in rows if not r["ambiguous"]]
    pairs = [(r["methods"][mode], r["references"][mode]) for r in valid]
    return {"classified": len(valid),
            "false_contacts": sum(a["found"] and not b["found"] for a, b in pairs),
            "missed_contacts": sum(not a["found"] and b["found"] for a, b in pairs),
            "false_shots": sum(a["shot"] and not b["shot"] for a, b in pairs),
            "missed_shots": sum(not a["shot"] and b["shot"] for a, b in pairs)}


def response_stats(rows):
    return {"cases": len(rows), "capped_updates": sum(r["discarded_ms"] > 0 for r in rows),
            "discarded_ms": sum(r["discarded_ms"] for r in rows),
            "max_correction_px": max(r["max_correction_px"] for r in rows),
            "contacts": sum(r["contacts"] for r in rows),
            "velocity_contacts": sum(r["velocity_contacts"] for r in rows),
            "recovery_contacts": sum(r["recovery_contacts"] for r in rows),
            "normal_exit_overlaps": sum(e.get("post_separation_overlap", False)
                                        for r in rows for e in r["events"]
                                        if e["separation_policy"] == "normal_new_contact")}


def main():
    d = read("shot_detection.json")
    r = read("shot_response.json")
    x = read("shot_diagnostics.json")
    precision = read("shot_precision.json")
    for document in (d, r, x, precision):
        assert document["failures"] == 0
    assert len(d["cases"]) == 4500 and len(r["cases"]) == 4644 and len(x["overlaps"]) == 288
    assert len(x["focused"]) == 3 and len(precision["cases"]) == 2
    for path, expected in x["production_sha256"].items():
        assert hashlib.sha256((ROOT.parents[1] / path).read_bytes()).hexdigest() == expected
    original_edges = read("refinement_edges_response.json")
    expected_edges = {row["id"]: row for row in original_edges["cases"]}
    for row in r["cases"]:
        if row["suite"] == "moving_edges":
            expected = expected_edges[row["id"]]["methods"]["B"]
            assert math.dist(row["methods"]["current"]["position"], expected["position"]) < .001
            assert math.dist(row["methods"]["current"]["velocity"], expected["velocity"]) < .01
    result = {"checks": x["checks"], "failures": 0, "detection": {}, "response": {},
              "integration": {}, "new_mismatches": [], "focused": x["focused"],
              "precision": precision, "transitions": x["transitions"],
              "production_sha256": x["production_sha256"], "overlaps": {},
              "classification_note": "Each rule has its own reference; previous 17 are not new-rule defect counts"}
    for mode in MODES[:3]:
        result["detection"][mode] = detection_stats(d["cases"], mode)
    assert result["detection"]["current"]["false_shots"] == 3
    assert result["detection"]["current"]["missed_shots"] == 14
    for row in d["cases"]:
        if not row["ambiguous"] and row["methods"]["three"]["shot"] != row["references"]["three"]["shot"]:
            result["new_mismatches"].append(row)
    for mode in MODES:
        result["response"][mode] = response_stats([row["methods"][mode] for row in r["cases"]])
        result["overlaps"][mode] = response_stats([row["methods"][mode] for row in x["overlaps"]])
        near = x["integration"][mode]["near_enemy"]
        assert len(near) == 84 and len(x["integration"][mode]["population"]) == 2
        categories = collections.Counter()
        for row in near:
            categories.update(row["categories"])
        result["integration"][mode] = {
            "population": x["integration"][mode]["population"],
            "near_enemy": {"capped_inputs": sum(row["exhausted_updates"] > 0 for row in near),
                           "capped_updates": sum(row["exhausted_updates"] for row in near),
                           "discarded_ms": sum(row["discarded_ms"] for row in near),
                           "max_correction_px": max(row["max_correction_px"] for row in near),
                           "categories": dict(categories),
                           "caps": [{"ratio": row["ratio"], "gap": row["gap"], "offset": row["offset"],
                                     "diagnostics": row.get("diagnostics", [])}
                                    for row in near if row["exhausted_updates"] > 0]}}
    # Compare the common prefix at the first capped tick, before trajectories can diverge.
    near_current = x["integration"]["current"]["near_enemy"]
    near_split = x["integration"]["split_budgets"]["near_enemy"]
    prefixes = []
    for a, b in zip(near_current, near_split):
        if not a["exhausted_updates"]:
            continue
        first = next(v for v in a["diagnostics"] if v["discarded_ms"] > 0)
        peers = [v for v in b.get("diagnostics", []) if v["update_index"] == first["update_index"]]
        assert peers, "Missing separate-budget trace at the control's first cap"
        peer = peers[0]
        assert len(peer["events"]) >= len(first["events"])
        for before, after in zip(first["events"], peer["events"]):
            assert abs(before["time_ms"] - after["time_ms"]) < .000001
            assert math.dist(before["velocity"], after["velocity"]) < .01
            assert math.dist(before["point"], after["point"]) < .001
            assert math.dist(before["separation_vector"], after["separation_vector"]) < .001
        prefixes.append({"ratio": a["ratio"], "gap": a["gap"], "offset": a["offset"],
                         "control": first, "candidate": peer})
    result["budget_prefix_comparisons"] = prefixes
    bottom = next(row for row in r["cases"] if row["suite"] == "moving_edges" and row["id"] == 1885)
    result["bottom_example"] = bottom
    runtime = read("shot_runtime.json")
    runtime_case = next(row for row in r["cases"] if row["suite"] == "moving_edges" and row["id"] == 96)
    for live in runtime["results"]:
        expected = runtime_case["methods"][MODES[int(live["rule"])]]
        assert live["first"]["shot"] == expected["events"][0]["shot"]
        assert math.dist(live["position"], expected["position"]) < .001
        assert math.dist(live["velocity"], expected["velocity"]) < .01
    assert all(row["flippers"] == [row["rule"], row["rule"]] for row in runtime["controls"])
    result["runtime_matches_cli"] = True
    (EVIDENCE / "shot_audit_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_report(result)
    print("Shot saved-data validation passed.")
    print("Detection:", result["detection"])
    print("Responses:", result["response"])
    print("Near enemy:", {m: {k: v for k, v in result["integration"][m]["near_enemy"].items()
                             if k not in ("categories", "caps")} for m in MODES})


def write_report(s):
    lines = ["# 打球3条件の適用・分離と反復の独立比較（2026-11-22）", "",
             "## 実施範囲と状態", "",
             "3条件（打ち上げ方向へ移動／上辺と両端への接触／球と面の相対接近）を実験部品に適用した。"
             "通常の物理表面速度・返球計算・③は維持。60°制限と根元Xによる除外を打球選別から外し、"
             "強化用表面速度も新しい判定で計算し直した。停止中・下降中・側面・下面は通常反射。", "",
             "本番のB・③・上向き分離16回・最大8接触は変更していない。分離・予算の候補はそれぞれ現行条件から"
             "一要因だけ変え、3条件との統合はしていない。本番採用は全て未決定。", "",
             "条件としきい値の分類・導入根拠は [shot_rules.md](../shot_rules.md)。"
             "検査間隔4 pxと回転終了での区間分割も今回は維持した。", "",
             "| 構成 | 打球条件 | 新接触の分離 | 反復予算 |",
             "| --- | --- | --- | --- |",
             "| current | 現行 | 上向き | 共有8 |",
             "| without_angle | 60°のみ除外、根元Xは残す | 上向き | 共有8 |",
             "| three | 3条件、60°・根元X除外なし | 上向き | 共有8 |",
             "| normal_new_only | 現行 | 区間開始非接触なら法線、開始重なりなら上向き | 共有8 |",
             "| split_budgets | 現行 | 上向き | 速度変化8／変化なし8を別計数 |", "",
             "## 第1段階：打球条件だけの比較", "",
             "既存4,500条件を使用。境界35条件は別枠、分類4,465条件。接触有無・時刻は3構成で完全一致した。"
             "参照接触の有無と高精度時刻は再利用し、打球の正解ラベルは各ルールから計算し直した。"
             "旧ルールの17件を新仕様の不具合件数として引き継いでいない。", "",
             "| 構成 | 誤接触 | 接触漏れ | 誤打球 | 打球漏れ |",
             "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES[:3], LABELS[:3]):
        d = s["detection"][mode]
        lines.append(f"| {label} | {d['false_contacts']} | {d['missed_contacts']} | {d['false_shots']} | {d['missed_shots']} |")
    lines += ["", "新ルールの残る2件はmoving_edges id615（60 Hz）・623（120 Hz）、右側の根元寄り上端、半径6 px。"
              "高精度の接触時刻では接近しているが、Bが採用する遅い時刻では既に離れる相対法線速度となる。"
              "両時刻とも上辺・上昇のフラグはtrueなので、60°の条件ではなく接触時刻による接近条件の違い。", "",
              "without_angleとthreeはこの4,500条件では分類が一致した。これだけで根元X条件が常に無影響とはしない。"
              "上端の浅い角度の接触、左右・上昇／停止／下降・接近／離反、標準と独自の述語一致、"
              "強化用速度の再計算、打球時だけ③が始まることは追加の機械検査で確認した。", "",
              "2件は既存B＋4／D2の接触時刻でも診断用に再生した。これは組み合わせ採用の決定ではない。", "",
              "| id / Hz | B・3条件の打球 | B＋4・3条件の打球 | D2・3条件の打球 |",
              "| --- | --- | --- | --- |"]
    for row in s["precision"]["cases"]:
        flags = [row["methods"][m]["events"][0]["shot"] for m in ("B", "B+4", "D2")]
        lines.append(f"| {int(row['id'])} / {int(row['rate'])} | " + " | ".join(str(v) for v in flags) + " |")
    lines += ["", "D2は内部の四角形部品が旧打球フラグを作るため、この診断では接触幾何を変えず、応答前に実験ルールを適用し直している。", "",
              "## 第2段階：大きな補正と打ち切りの原因", "",
              "全2,628従来条件＋辺・角2,016条件＝4,644一更新、開始重なり288条件、③解除・停止移行25条件を実行。"
              "さらに近接Enemy84配置と1/20球各6秒を各構成で再生した。現行の終了位置・速度は従来保存データと一致する。", "",
              "### 下面から約200 px動く例", ""]
    example = s["bottom_example"]
    for mode, label in (("current", "現行"), ("normal_new_only", "新接触だけ法線分離")):
        e = example["methods"][mode]["events"][0]
        lines.append(f"- {label}：接触{e['time_ms']:.6f} ms、下面、食い込み{e['depth_px']:.6f} px、"
                     f"分離{e['correction_px']:.6f} px、方向{e['separation_vector']}。分離後重なり={e.get('post_separation_overlap')}。")
    lines += ["", "moving_edges id1885、右、半径36、30 Hz。両方式の最初の接触時刻・法線・速度変化は同じ。"
              "約200 pxは侵入深さではなく、下面から真上へ抜ける経路の長さで生じる。"
              "16回の探索回数を減らすだけでは、この方向の問題を解消できない。", "",
              "### 再接触による上限到達は一種類ではない", "",
              "- 近接Enemyの現行3配置では、上限に達する最初の更新は速度変化1回＋速度を変えない処理7回。"
              "位置補正・時刻は変わるため、全部を無処理の重複とは呼ばない。",
              "- 既知id405/465/525の30 Hz・戻る板では、B＋4／D2の全8接触で速度が変わる。"
              "こちらは回復だけを別予算にしても同じ8回で打ち切る。",
              "- ③解除時に既に内部へ入っている条件も再現した。新接触の法線分離を適用しないこの群では、"
              "上向き分離の大きな補正が残る。", "",
              "各イベントに接触時刻、対象・面、深さ、更新／区間開始の重なり、③解除、分離方向・距離、"
              "分離後の重なり、相対法線速度、前後速度、残り時間を保存した。標準側の深さはGodotのget_depthであり、"
              "独自側の幾何的深さとは由来が違う。数値を同一の精度基準とみなさない。", "",
              "開始接触・重なりフラグは深さ0の境界接触も含む保守的な判定。実際の食い込み量はdepth_pxを別に読む。"
              "非接触が明確な区間だけを法線分離案の対象にしている。", "",
              "## 第3段階：分離・反復を個別に変えた結果", "",
              "| 構成 | 単独4,644条件の最大補正px | 単独の打ち切り | 近接敵の最大補正px | 近接敵の打ち切り配置 / 84 | 破棄時間合計ms |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        a, b = s["response"][mode], s["integration"][mode]["near_enemy"]
        lines.append(f"| {label} | {a['max_correction_px']:.6f} | {a['capped_updates']} | "
                     f"{b['max_correction_px']:.6f} | {b['capped_inputs']} | {b['discarded_ms']:.6f} |")
    lines += ["", "法線分離案では、開始重なり288条件の結果が現行と一致。初期重なりを上向きに戻す方針を変えず、"
              "移動途中の初回接触だけを分けられることを確認した。ただし近接Enemyの内部解除では最大約60.61 pxが残り、"
              "打ち切り2配置も残る。採用決定にはしない。", "",
              "予算分離案は、近接Enemyの1配置で打ち切りを回避したが、残る2配置では速度変化1回＋回復側8回の"
              "計9処理で再び上限になる。無限反復を解決したわけではなく、大きな補正も残る。"
              "同じ更新の最初の8接触が現行と一致することを照合し、接触を無視していないことを確認した。", "",
              "### 既知30 Hzの詳細", "",
              "id405/465/525は共通の戻り局面。代表405の結果：", "",
              "| 構成・検出器 | 接触数 | 速度変化 / 変化なし | 破棄ms |",
              "| --- | ---: | ---: | ---: |"]
    for mode, value in s["focused"][0]["methods"].items():
        lines.append(f"| {mode} | {value['contacts']} | {value['velocity_contacts']} / {value['recovery_contacts']} | {value['discarded_ms']:.6f} |")
    lines += ["", "初回だけの法線分離で今回の3条件の打ち切りは回避したが、検出器を含むあらゆる条件で安全とは結論しない。"
              "予算分離だけでは8回全ての速度変化がある事例は改善しない。分離の方向・補正後の再接触が重要な切り分けになった。", "",
              "## 判断と残る確認", "",
              "- 3条件は実験に適用済み。仕様として少ない条件で比較できるが、新基準でもBの接触時刻による2件の取りこぼしが残る。",
              "- 上辺の端を含む自然さ・打球の手触りは、実験プレビューでユーザーが確認する段階。今回の数値だけで自然さを合格にしない。",
              "- 分離は『移動途中の新接触』と『最初からの重なり／内部解除』を分ける方向が候補。ただし内部からの復帰と残る打ち切りは未解決。",
              "- 反復は単に上限を増やす／同じ接触を捨てる方針にはしない。今回の別予算は診断用の比較で、採用仕様ではない。",
              "- 3条件・分離・反復の改善案はまだ統合していない。次の統合検証や本番反映はユーザーの仕様確認後に行う。", "",
              "CPU時間は重い履歴計測を含む補助値としてのみ保存した。前回の性能監査と直接比較せず、"
              "今回を高速化の証明にしない。検出精度、返球ルール、回復、反復、自然さ、負荷を別に評価した。", "",
              "## 確認・再実行", "",
              f"CLIの機械検査{s['checks']:,}件、残る2件の精度診断7件、既存migration回帰96件は失敗0。"
              "別の保存データ照合も通過。本番8ファイルのSHA-256を実行前後で照合した。"
              "通常のプレビューはmainを保存せずインスタンス化する。", "",
              "Godot AIで実験プレビューの起動、初期3条件、1/2/3の切替を確認した。角のid96では現行が通常反射、"
              "候補が打球＋③開始となり、各構成の終了位置・速度はCLIと一致した。確認後に実行停止、シーン保存なし。"
              "Godot AIのgame_evalではshot_runtime.gdのrun(get_tree().current_scene)を呼んで再現できる。", "",
              "CLIには既存ポストプロセスのUID警告3件があるが、パスで読み込まれた。最終実行のスクリプトエラーは0。", "",
              "```powershell",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/shot_audit.gd",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/shot_precision.gd",
              "python experiments/flippers/tests/summarize_shot_audit.py", "```", "",
              "- [4,500条件・各仕様の参照分類](shot_detection.json)",
              "- [4,644条件・全イベント履歴](shot_response.json)",
              "- [開始重なり・近接Enemy・複数球・③解除・30Hz](shot_diagnostics.json)",
              "- [新基準で残る2件の時刻診断](shot_precision.json)",
              "- [集計と代表事例](shot_audit_summary.json)",
              "- [実行時の再現と切替](shot_runtime.json)",
              "- [条件と根拠の分類](../shot_rules.md)",
              "- [操作できる実験シーン](../shot_preview.tscn)",
              "- [CLI実行ログ](shot_audit.log)", ""]
    (EVIDENCE / "shot_audit.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
