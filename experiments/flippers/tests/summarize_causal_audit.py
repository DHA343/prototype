"""Validate paired interventions and summarize causes without testing a proposed fix."""

import collections
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
E = ROOT / "evidence"


def read(name):
    return json.loads((E / name).read_text(encoding="utf-8-sig"))


def key(row):
    return (round(row["ratio"], 2), row["gap"], row["offset"])


def metrics(rows):
    return {"cases": len(rows), "capped_cases": sum(row["exhausted_updates"] > 0 for row in rows),
            "capped_updates": sum(row["exhausted_updates"] for row in rows),
            "unresolved": sum(row["unresolved"] for row in rows),
            "max_correction_px": max(row["max_correction_px"] for row in rows),
            "introduced_events": sum(row["observed"]["E_introduced"] for row in rows),
            "enemy_budget_updates": sum(row["enemy_budget_updates"] for row in rows),
            "enemy_residual_max_px": max(row["enemy_residual_max_px"] for row in rows),
            "initial_ball_overlaps": sum(bool(row["initial_ball_overlap"]) for row in rows),
            "initial_enemy_world_overlaps": sum(any(row["initial_enemy_overlap"]) for row in rows)}


def same_snapshot(a, b):
    for field, tolerance in (("ball_position", .001), ("ball_velocity", .01)):
        assert math.dist(a[field], b[field]) < tolerance
    assert a["guard"] == b["guard"] and len(a["enemies"]) == len(b["enemies"])
    for left, right in zip(a["enemies"], b["enemies"], strict=True):
        assert math.dist(left["position"], right["position"]) < .001
        assert math.dist(left["velocity"], right["velocity"]) < .01


def main():
    audit = read("causal_audit.json")
    index = read("causal_environments.json")
    raw = read("causal_time.json")
    guard_off = read("causal_no_guard.json")
    legacy = read("causal_legacy.json")
    route = read("causal_route.json")
    focus = read("causal_focus.json")
    replay = read("causal_replay.json")
    previous = read("unlimited_audit.json")
    for document in (audit, index, raw, guard_off, focus, replay):
        assert document["failures"] == 0
    assert len(audit["normal"]) == 504 and len(audit["checkpoints"]) == 90
    assert len(audit["normal_pairs"]) == 12 and audit["enemy_conformance"]["cases"] == 48
    assert audit["regression"] == {"cases": 4644, "trials": 3}
    assert len(legacy["failures"]) == 2
    for name, digest in audit["production_sha256"].items():
        assert hashlib.sha256((ROOT.parents[1] / name).read_bytes()).hexdigest() == digest
    result = {"failures": 0, "mechanical_checks": audit["checks"], "guard_off_checks": guard_off["checks"],
              "environments": {}, "normal": {}, "guard_off": {}, "paired": [], "clock": [],
              "source_hashes": audit["production_sha256"], "legacy": legacy,
              "route": route, "raw_query_target_matches": 0, "raw_query_cases": len(raw["cases"])}
    for mode, environments in index["matrix"].items():
        result["environments"][mode] = {}
        for name, filename in environments.items():
            rows = read(filename)["cases"]
            assert len(rows) == 84
            result["environments"][mode][name] = metrics(rows)
    for name in sorted({row["environment"] for row in audit["normal"]}):
        result["normal"][name] = metrics([row for row in audit["normal"] if row["environment"] == name])
    for name, filename in guard_off["matrix"].items():
        rows = read(filename)["cases"]
        assert len(rows) == 84 and all(not row["guard_enabled"] for row in rows)
        result["guard_off"][name] = metrics(rows)
    groups = collections.defaultdict(list)
    for row in audit["checkpoints"]:
        groups[row["policy"], key(row)].append(row)
    for (mode, fixture), rows in groups.items():
        assert len(rows) == 5
        for row in rows:
            same_snapshot(rows[0]["paired_before_intervention"], row["paired_before_intervention"])
        result["paired"].append({"mode": mode, "fixture": fixture,
            "results": [{"environment": row["environment"], "capped_updates": row["exhausted_updates"],
                         "unresolved": row["unresolved"], "max_correction_px": row["max_correction_px"]} for row in rows]})
    groups.clear()
    for row in audit["normal_pairs"]:
        groups[row["environment"].split(":")[0], key(row)].append(row)
    for rows in groups.values():
        assert len(rows) == 3
        for row in rows:
            same_snapshot(rows[0]["paired_before_intervention"], row["paired_before_intervention"])
        assert rows[0]["exhausted_updates"] == 1
        assert rows[1]["exhausted_updates"] == rows[2]["exhausted_updates"] == 0
    for row in raw["cases"]:
        candidates = audit["normal_pairs"] if row["ordinary"] else audit["checkpoints"]
        name = row["environment"] + ":control" if row["ordinary"] else row["environment"]
        peer = next(item for item in candidates if item["environment"] == name
                    and key(item) == key(row) and item["policy"] == row["policy"])
        assert math.dist(row["position"], peer["position"]) < .001
        assert math.dist(row["velocity"], peer["velocity"]) < .01
        for tick in row["important"]:
            for event in tick["native_geometry"]:
                if "raw_query" not in event:
                    continue
                query = event["raw_query"]
                assert query["same_collider"]
                result["raw_query_target_matches"] += 1
                motion = event["requested_motion"]
                length2 = sum(value * value for value in motion)
                projected = sum(a * b for a, b in zip(event["travel"], motion)) / length2 if length2 > 1e-6 else 0
                current = min(1, max(0, projected))
                bias = (current - query["safe_fraction"]) * (1000/60 - event["before_time_ms"])
                if abs(bias) > .01:
                    result["clock"].append({"fixture": key(row), "policy": row["policy"],
                        "ordinary": row["ordinary"], "target": event["target"], "iteration": event["iteration"],
                        "current_fraction": current, "raw_safe_fraction": query["safe_fraction"], "difference_ms": bias})
    assert result["raw_query_target_matches"] == 72
    assert any(row["raw_safe_fraction"] == 0 and row["difference_ms"] > 1 for row in result["clock"])
    snapshots = legacy["snapshots"]
    assert snapshots[0]["actors"][0]["move_speed"] == 30
    assert route["exit_s"] > 20 and route["exit_s"] < 60
    result["legacy_comparison"] = {}
    for mode in ("baseline", "unlimited"):
        old_rows = previous["integration"][mode]["near_enemy"]
        new_rows = read(f"causal_{mode}_full_reference.json")["cases"]
        for old, new in zip(old_rows, new_rows, strict=True):
            assert abs(old["max_correction_px"] - new["max_correction_px"]) < .001
            assert old["exhausted_updates"] == new["exhausted_updates"]
            assert old["unresolved"] == new["unresolved"]
        result["legacy_comparison"][mode] = {
            "correction_cap_unresolved_match": True,
            "old_introduced_events": sum(row["observed"]["E_introduced"] for row in old_rows),
            "new_introduced_events": sum(row["observed"]["E_introduced"] for row in new_rows),
            "final_position_max_difference_px": max(math.dist(a["position"], b["position"])
                                                    for a, b in zip(old_rows, new_rows, strict=True))}
    for row in replay["cases"]:
        assert row["old_metric_differences"] == row["observer_metric_differences"] == 0
    result["legacy_replay"] = replay
    result["stage_safety_note"] = "Times in response traces are current code estimates. Raw safe fractions expose recovery included in current time accounting; no corrected trajectory is applied."
    (E / "causal_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Causal paired snapshots, raw-query equivalence, observer conformance and production hashes validated.")
    print("Environment cases:", sum(value["cases"] for modes in result["environments"].values() for value in modes.values()))
    print("Ordinary isolated cases:", len(audit["normal"]), "; same-input guard-off:", sum(value["cases"] for value in result["guard_off"].values()))
    print("Legacy tests retain two reported failures; these are not counted as passing.")


if __name__ == "__main__":
    main()
