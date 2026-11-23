"""Validate complete experiment cohorts and keep unresolved runs out of success counts."""

import collections
import hashlib
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
E = ROOT / "evidence"
METHODS = ("baseline", "state", "clock", "state_clock", "relative", "normal", "nearest",
           "tangent", "bounded", "bounded_tangent", "segmented", "segmented_tangent",
           "finish", "finish_tangent")
VALIDATED = ("baseline", "relative", "normal", "bounded", "bounded_tangent", "segmented",
             "segmented_tangent", "finish", "finish_tangent")


def read(name):
    return json.loads((E / name).read_text(encoding="utf-8-sig"))


def metrics(rows):
    completed = [row for row in rows if not row["unresolved"]]
    return {"cases": len(rows), "completed": len(completed),
            "unresolved": sum(row["unresolved"] for row in rows),
            "capped_cases": sum(row["exhausted_updates"] > 0 for row in rows),
            "capped_updates": sum(row["exhausted_updates"] for row in rows),
            "max_correction_px": max(row["max_correction_px"] for row in rows),
            "introduced_events": sum(row["observed"]["E_introduced"] for row in rows),
            "introduced_depth_max_px": max(row.get("introduced_depth_max_px", 0) for row in rows),
            "introduced_over_margin": sum(row.get("introduced_over_margin", 0) for row in rows),
            "final_overlap_max_px": max(row.get("final_overlap_max_px", 0) for row in completed),
            "clear_tail_updates": sum(row.get("clear_tails", 0) for row in rows),
            "below_reset_cases": sum(any(t["below_reset"] for t in row.get("trajectory", [])) for row in completed),
            "allowed_downward_pass_events": sum(row["below_overdue"] for row in rows),
            "new_guard_deferrals": sum(row.get("max_delay_ms", 0) > 0 for row in rows)}


def groups(rows):
    result = collections.defaultdict(list)
    for row in rows:
        result[f"{row['environment']}:{'ordinary' if row['ordinary'] else 'flippers'}"].append(row)
    return {key: metrics(value) for key, value in result.items()}


def main():
    result = {"scope": "Experimental only; no complete production candidate selected",
              "methods": {}, "rates": {}, "validation": {}, "benchmark": [], "pairs": []}
    baseline_integration = read("stable_baseline.json")["cases"]
    result["common_completed"] = {}
    for name in METHODS:
        rows = read(f"stable_{name}.json")["cases"]
        assert len(rows) == 504
        result["methods"][name] = groups(rows)
        common = [(old, new) for old, new in zip(baseline_integration, rows, strict=True)
                  if not old["unresolved"] and not new["unresolved"]]
        for old, new in common:
            assert (old["environment"], old["ordinary"], old["ratio"], old["gap"], old["offset"]) == (
                    new["environment"], new["ordinary"], new["ratio"], new["gap"], new["offset"])
        result["common_completed"][name] = {"baseline": groups([a for a, _ in common]),
                                            "candidate": groups([b for _, b in common])}
    baseline = read("stable_response_baseline.json")["cases"]
    for name in VALIDATED:
        rows = read(f"stable_response_{name}.json")["cases"]
        overlaps = read(f"stable_overlap_{name}.json")
        assert len(rows) == 4644 and len(overlaps["overlaps"]) == 288
        assert len(overlaps["releases"]) == 1728
        positions = [math.dist(a["result"]["position"], b["result"]["position"])
                     for a, b in zip(rows, baseline, strict=True)]
        velocities = [math.dist(a["result"]["velocity"], b["result"]["velocity"])
                      for a, b in zip(rows, baseline, strict=True)]
        result["validation"][name] = {"normal_cases": len(rows),
            "max_position_delta_px": max(positions), "max_velocity_delta_px_s": max(velocities),
            "normal_capped": sum(row["result"]["discarded_ms"] > 0 for row in rows),
            "overlap_capped": sum(row["result"]["discarded_ms"] > 0 for row in overlaps["overlaps"]),
            "overlap_max_correction_px": max(row["result"]["max_correction_px"] for row in overlaps["overlaps"]),
            "deep_release_unresolved": sum(row["result"]["unresolved"] for row in overlaps["releases"]),
            "known_30hz": [{"id": row["id"], "result": {key: row["result"][key]
                            for key in ("discarded_ms", "shots", "position", "velocity")}}
                           for row in rows if row["rate"] == 30 and row["id"] in (405, 465, 525)]}
        assert max(positions) < .001 and max(velocities) < .01
        assert result["validation"][name]["normal_capped"] == 0
    for rate in (30, 120):
        result["rates"][rate] = {}
        for name in ("baseline", "normal", "bounded_tangent", "segmented_tangent", "finish_tangent"):
            rows = read(f"stable_rate_{rate}_{name}.json")["cases"]
            assert len(rows) == 336 and all(row["rate"] == rate for row in rows)
            result["rates"][rate][name] = groups(rows)
    bench = read("stable_benchmark.json")
    assert bench["failures"] == 0
    benchmark_groups = collections.defaultdict(list)
    for row in bench["cases"]:
        assert len(row["samples_us"]) == row["completed_samples"] == 100
        benchmark_groups[row["method"], row["scenario"]].append(row)
    for (method, scenario), rows in benchmark_groups.items():
        assert len(rows) == 4
        samples = sorted(value for row in rows for value in row["samples_us"])
        for row in rows:
            assert math.dist(row["position"], rows[0]["position"]) < .001
            assert math.dist(row["velocity"], rows[0]["velocity"]) < .01
        result["benchmark"].append({"method": method, "scenario": scenario,
            "median_us": statistics.median(samples), "p95_us": samples[379], "p99_us": samples[395],
            "max_us": samples[-1], "pass_medians_us": [statistics.median(row["samples_us"]) for row in rows],
            "position": rows[0]["position"], "velocity": rows[0]["velocity"]})
    pairs = read("stable_pairs.json")
    paired = collections.defaultdict(list)
    for row in pairs["cases"]:
        paired[round(row["ratio"], 2), row["gap"], row["offset"]].append(row)
    assert len(pairs["cases"]) == 54
    for key, rows in paired.items():
        assert len(rows) == 6 and all(row["initial"] == rows[0]["initial"] for row in rows)
        result["pairs"].append({"fixture": key, "methods": [{"method": row["policy"],
            "first_release_correction_px": row["first"]["release_correction_px"],
            "capped_updates": row["exhausted_updates"], "unresolved": row["unresolved"]} for row in rows]})
    checks = {}
    for filename in ("stable_audit.json", "stable_validation.json", "stable_validation_segmented.json",
                     "stable_validation_finish.json", "stable_contracts.json", "stable_pairs.json",
                     "stable_benchmark.json", "stable_rate_30.json", "stable_rate_120.json",
                     "stable_rate_30_segmented.json", "stable_rate_120_segmented.json",
                     "stable_rate_30_finish.json", "stable_rate_120_finish.json"):
        data = read(filename)
        assert data["failures"] == 0, filename
        checks[filename] = data["checks"]
    result["checks_by_run"] = checks
    result["note"] = "Per-run checks cover that invocation, not all method definitions; scenario totals are derived from complete case files."
    production = read("causal_summary.json")["source_hashes"]
    for name, digest in production.items():
        assert hashlib.sha256((ROOT.parents[1] / name).read_bytes()).hexdigest() == digest, name
    result["production_sha256"] = production
    logs = ("stable_audit", "stable_validation", "stable_segmented", "stable_validation_segmented",
            "stable_finish", "stable_validation_finish", "stable_rate_30", "stable_rate_120",
            "stable_rate_30_segmented", "stable_rate_120_segmented", "stable_rate_30_finish",
            "stable_rate_120_finish", "stable_contracts", "stable_pairs", "stable_benchmark")
    for name in logs:
        log = (E / (name + ".log")).read_text(encoding="utf-8-sig")
        assert "SCRIPT ERROR" not in log and "ERROR:" not in log, name
    assert "Migration checks: 96; failures: 0" in (E / "stable_migration.log").read_text(encoding="utf-8-sig")
    enemy_log = (E / "stable_enemy.log").read_text(encoding="utf-8-sig")
    assert "Enemy checks: 3737; failures: 2" in enemy_log
    assert enemy_log.count("FAIL:") == 2
    result["legacy_enemy_failures"] = 2
    (E / "stable_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Validated: 14 x 504 integration cases; 9 x 4644 normal cases; 9 x 288 initial overlaps.")
    print("Validated: 30/120 Hz, paired snapshots, repeated timings, and 13 unchanged production files.")
    print("No complete stable candidate: blocked release, repeated real impacts, and legacy limitations remain.")


if __name__ == "__main__":
    main()
