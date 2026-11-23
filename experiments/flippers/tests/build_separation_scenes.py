"""Curate eight small visual fixtures from existing evidence; no long autoplay replay."""
import json
from pathlib import Path

EVIDENCE = Path(__file__).resolve().parents[1] / "evidence"


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8"))


def main():
    response = read("separation_response.json")
    underside = next(r for r in response["cases"] if r["suite"] == "moving_edges" and r["id"] == 1885)
    overlaps = read("separation_diagnostics.json")["overlaps"]
    overlap = max(overlaps, key=lambda r: r["methods"]["three"]["max_correction_px"])
    deep = next(r for r in overlaps if r["case"]["side"] == 0 and r["case"]["angle"] == 18
                and r["case"]["radius"] == 36 and r["case"]["feature"] == 2 and r["case"]["depth"] == 48)
    causal = read("causal_audit.json")["checkpoints"]
    side = next(r for r in causal if abs(r["ratio"] - .9) < .00001 and r["gap"] == 3
                and r["offset"] == 0 and r["policy"] == "baseline" and r["environment"] == "full_reference")
    live = read("value_isolated_A_held_113_60.json")["events"]
    right = next(r for r in live if r["frame"] == 2853)
    respawn = next(r for r in live if r["frame"] == 4902)["events"][0]
    enemy_center = [respawn["point"][i] - respawn["normal"][i] * 30 for i in range(2)]
    cases = [
        {"title": "1 右側面への新接触", "kind": "right", "hz": 60, "radius": 24,
         "gravity": 1500, "angle": 10, "start": right["before"][-1][2:4],
         "velocity": right["before"][-1][4:6], "focus": [990, 1035],
         "fidelity": "局所再構築：球・板の直前状態。周囲18体と長時間履歴は未復元",
         "source": "value_isolated_A_held_113_60.json / A・frame2853（参考93.41 px）"},
        {"title": "2 下面への新接触", "kind": "isolated", "hz": 30, "radius": 36,
         "gravity": 0, "angle": 18, "side": 1, "pressed": False,
         "start": underside["case"]["start"], "velocity": underside["case"]["velocity"],
         "focus": [1132, 1050], "fidelity": "保存された単独更新条件を再利用。壁なし・半径36・重力0",
         "source": "separation_response.json / moving_edges id1885・30 Hz",
         "expected": {m: underside["methods"][k]["max_correction_px"] for m, k in [("S", "three"), ("B", "combined")]}},
        {"title": "3 開始時の重なりと大補正", "kind": "isolated", "hz": 60, "radius": 36,
         "gravity": 0, "angle": 18, "side": 0, "pressed": False,
         "start": overlap["case"]["start"], "velocity": [0, 0], "focus": [788, 1050],
         "fidelity": "保存条件を再利用。食い込みは約0.20 px、上向きの移動距離が約204 px",
         "source": "separation_diagnostics.json / side0・bottom・18°・r36・depth0.2",
         "expected": {m: overlap["methods"][k]["max_correction_px"] for m, k in [("S", "three"), ("B", "combined")]}},
        {"title": "4 ③解除・停止板内部", "kind": "near", "hz": 60, "radius": 24,
         "gravity": 1500, "angle": 0, "focus": [820, 1030],
         "fidelity": "既存の近接条件を初期状態から実行。深さは解除時に表示",
         "source": "causal_audit / ratio0.5 または0.7・gap36・offset0。旧深さ28.49/40.59 px"},
        {"title": "5 ③解除・回転板の側面", "kind": "snapshot", "hz": 60, "radius": 24,
         "gravity": 1500, "angle": 10, "focus": [930, 1020], "enemies": False,
         "snapshot": side["paired_before_intervention"],
         "fidelity": "解除直前の局所状態を復元。Enemyを除外し、分離方向を観察",
         "source": "causal_audit / (.9,3,0)・更新1直前。旧深さ24.49・補正60.61 px"},
        {"title": "6 ③解除後のEnemyへの押し込み", "kind": "snapshot", "hz": 60, "radius": 24,
         "gravity": 1500, "angle": 10, "focus": [920, 990], "enemies": True,
         "snapshot": side["paired_before_intervention"],
         "fidelity": "同じ解除直前状態とEnemyを復元。衝突照会の履歴は完全再現しない",
         "source": "causal_audit / (.9,3,0)・上向き補正がEnemyとの新規干渉を作る例"},
        {"title": "7 再生成位置とEnemyの重なり", "kind": "respawn", "hz": 60, "radius": 24,
         "gravity": 1500, "angle": 0, "start": [780, 540], "velocity": [0, 0],
         "enemy_center": enemy_center, "focus": [780, 540],
         "fidelity": "近似：Enemy中心を接触点・法線・半径から推定。実際の移動履歴は未復元",
         "source": "value_isolated_A_held_113_60.json / frame4902（旧標準回復20.51 px）"},
        {"title": "8 通常の上辺打球", "kind": "top", "hz": 60, "radius": 24,
         "gravity": 1500, "angle": 0, "focus": [790, 990],
         "fidelity": "対照：既存の球＋板条件、上辺中央へ下降。Enemyなし",
         "source": "causal / flipper_onlyと同じ上面から28 px・初速下向き300"},
    ]
    cases[2]["deep"] = {
        "start": deep["case"]["start"],
        "fidelity": "保存された深さ48 pxの開始重なり。新接触ではないためBも上向き分離",
        "source": "separation_diagnostics.json / side0・bottom・18°・r36・depth48",
        "expected": {m: deep["methods"][k]["max_correction_px"] for m, k in [("S", "three"), ("B", "combined")]}}
    (EVIDENCE / "separation_scenes.json").write_text(
        json.dumps({"cases": cases}, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Curated visual fixtures:", len(cases))


if __name__ == "__main__":
    main()
