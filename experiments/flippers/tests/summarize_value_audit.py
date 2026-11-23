"""Summarize observations; never infer causal treatment effects from divergent trajectories."""
from pathlib import Path
import collections
import hashlib
import json
import math
import re
import statistics

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "experiments/flippers/evidence"


def read(name):
    return json.loads((OUT / name).read_text(encoding="utf-8"))


def percentile(values, fraction):
    values = sorted(values)
    at = (len(values) - 1) * fraction
    return values[int(at)] + (values[math.ceil(at)] - values[int(at)]) * (at % 1)


def aggregate(rows):
    result = {"episodes": len(rows), "wall_seconds": sum(r["seconds"] for r in rows)}
    keys = ["contacts", "shots", "caps", "large_corrections", "corrections_over_one", "release_inside",
            "respawns", "drops", "occupied_respawns", "blocked_respawn_ticks", "introduced_events",
            "path_crossings", "clock_unknown_ticks", "physical_missing_ms", "cap_physical_missing_ms",
            "missing_ticks", "missing_over_half_tick", "detection_opportunities", "reference_samples",
            "coarse_shot_errors", "refined_shot_errors", "reference_unstable", "ball_damage_events",
            "damage_events", "enemy_ticks_removed", "enemy_overlaps_removed", "spawned", "killed", "escaped"]
    result.update({key: sum(r["stats"].get(key, 0) for r in rows) for key in keys})
    for key in ["correction_max_px", "new_contact_max_px", "release_depth_max_px", "max_cap_run",
                "max_slow_run", "max_jitter_run", "enemy_depth_max_px", "enemy_count_max",
                "max_blocked_respawn_ticks", "respawn_overlap_max_px", "missing_max_ms"]:
        result[key] = max(r["stats"].get(key, 0) for r in rows)
    result["active_seconds"] = sum(r["stats"]["active_ticks"] / r["rate"] for r in rows)
    result["mean_enemy_count"] = sum(r["stats"]["enemy_count_sum"] for r in rows) / sum(r["stats"]["ticks"] for r in rows)
    result["large_per_1000_contacts"] = result["large_corrections"] / result["contacts"] * 1000
    result["caps_per_active_minute"] = result["caps"] * 60 / result["active_seconds"]
    cap_examples = []
    for row in rows:
        for event in row["events"]:
            if not event["tail"][0][7]:
                continue
            tail = event["tail"]
            cap_examples.append({"profile": row["profile"], "seed": row["seed"], "frame": event["frame"],
                                 "missing_ms": event["true_missing_ms"], "recorded_tail_ticks": len(tail),
                                 "active_after_tail": tail[-1][6], "tail_caps": sum(x[7] for x in tail),
                                 "end_position": tail[-1][2:4]})
    result["captured_cap_examples"] = cap_examples
    return result


def main():
    files = read("value_isolated_manifest.json")["runs"]
    assert len(files) == 54
    rows = [read(item["file"]) for item in files]
    assert len({(r["mode"], r["profile"], r["seed"]) for r in rows}) == 54
    assert all(r["seconds"] == 120 and r["rate"] == 60 and r["stats"]["ticks"] == 7200 for r in rows)
    summary = {"scope": "54 fresh-process main-scene episodes. Observational counts, not human rates or causal rankings.",
               "modes": {m: aggregate([r for r in rows if r["mode"] == m]) for m in "ANSBFP"},
               "profiles": {m: {p: aggregate([r for r in rows if r["mode"] == m and r["profile"] == p])
                                   for p in ["alternate", "held", "adaptive"]} for m in "ANSBFP"}}
    summary["observer_pairs"] = []
    for mode in "ANBF":
        for profile in ["held", "adaptive"]:
            a = read(f"value_isolated_{mode}_{profile}_113_60.json")
            b = read(f"value_off_isolated_{mode}_{profile}_113_60.json")
            pairs = list(zip(a["checkpoints"], b["checkpoints"]))
            mismatch = [x["frame"] for x, y in pairs if math.dist(x["position"], y["position"]) >= .001
                        or math.dist(x["velocity"], y["velocity"]) >= .01 or x["active"] != y["active"]
                        or x["enemies"] != y["enemies"] or x["missiles"] != y["missiles"]]
            summary["observer_pairs"].append({"mode": mode, "profile": profile, "matched_checkpoints": not mismatch,
                "first_mismatch_frame": mismatch[0] if mismatch else None,
                "observed_median_us": statistics.median(a["app_us"][600:]),
                "lean_median_us": statistics.median(b["app_us"][600:]),
                "lean_p95_us": percentile(b["app_us"][600:], .95),
                "lean_p99_us": percentile(b["app_us"][600:], .99),
                "lean_max_us": max(b["app_us"][600:]),
                "use_for_observer_overhead": not mismatch})
    summary["repeats"] = []
    for first, second in [("value_repeat_first_A_held_113_60.json", "value_repeat_A_held_113_60.json"),
                          ("value_isolated_A_held_113_60.json", "value_isolated_repeat_A_held_113_60.json")]:
        a, b = read(first), read(second)
        summary["repeats"].append({"files": [first, second], "checkpoints_equal": a["checkpoints"] == b["checkpoints"],
            "stats_equal": a["stats"] == b["stats"], "first_difference_frame": next((x["frame"] for x, y in
            zip(a["checkpoints"], b["checkpoints"]) if x != y), None),
            "caps": [a["stats"]["caps"], b["stats"]["caps"]],
            "large": [a["stats"]["large_corrections"], b["stats"]["large_corrections"]]})
    cost = read("value_cost.json")
    assert len(cost["cases"]) == 4644 * 5 and cost["failures"] == 0
    summary["cost_checks"] = cost["checks"]
    summary["one_step_cost"] = {}
    contact_sets = {}
    for mode in "ANSBF":
        selected = [r for r in cost["cases"] if r["method"] == mode and r["suite"] == "main_336"
                    and r["rate"] == 60 and r["radius"] == 24]
        assert len(selected) == 336
        contact_sets[mode] = {r["id"] for r in selected if r["contacts"] > 0}
        summary["one_step_cost"][mode] = {}
        for name, subset in [("all", selected), ("no_contact", [r for r in selected if r["contacts"] == 0]),
                             ("contact", [r for r in selected if r["contacts"] > 0])]:
            samples = [v for r in subset for v in r["samples_us"]]
            summary["one_step_cost"][mode][name] = {"cases": len(subset), "samples": len(samples),
                "median_us": statistics.median(samples), "p95_us": percentile(samples, .95),
                "p99_us": percentile(samples, .99), "max_us": max(samples)}
    assert all(ids == contact_sets["A"] for ids in contact_sets.values())
    summary["initial_overlap"] = read("value_contracts.json")
    assert summary["initial_overlap"]["failures"] == 0
    summary["focus"] = read("value_focus.json")
    assert summary["focus"]["failures"] == 0
    hashes = read("causal_summary.json")["source_hashes"]
    assert len(hashes) == 13
    summary["production_hashes_match"] = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected
                                            for path, expected in hashes.items()}
    assert all(summary["production_hashes_match"].values())
    summary["regressions"] = {}
    for key, filename, pattern, expected in [
            ("migration", "value_migration.log", r"Migration checks: (\d+); failures: (\d+)", (96, 0)),
            ("enemy", "value_enemy_regression.log", r"Enemy checks: (\d+); failures: (\d+)", (3737, 2))]:
        log = (OUT / filename).read_text(encoding="utf-8-sig")
        found = re.search(pattern, log)
        assert found and tuple(map(int, found.groups())) == expected
        summary["regressions"][key] = {"checks": expected[0], "failures": expected[1]}
    summary["reference_warning"] = ("Main-scene shared-predicate reference flags are candidates only. "
        "A/S held809 tick2447 are false flags rejected by independent scalar convex geometry. "
        "N held809 tick503 is independently confirmed; under three shot conditions it is a speed error, not a shot miss.")
    (OUT / "value_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    for mode, s in summary["modes"].items():
        print(mode, {k: round(s[k], 3) for k in ["active_seconds", "contacts", "caps", "large_corrections",
            "correction_max_px", "new_contact_max_px", "respawns", "occupied_respawns", "introduced_events",
            "max_cap_run", "max_slow_run", "max_jitter_run", "physical_missing_ms", "missing_over_half_tick",
            "mean_enemy_count", "enemy_count_max", "blocked_respawn_ticks", "max_blocked_respawn_ticks"]})
    print("Source hashes unchanged:", len(hashes))


if __name__ == "__main__":
    main()
