"""Summarize the production-motion A/B measurements without rerunning Godot."""

import json
import math
import statistics
from pathlib import Path


EVIDENCE = Path(__file__).resolve().parents[1] / "evidence"


def distribution(values):
    values = sorted(values)
    if not values:
        return None
    return {
        "count": len(values),
        "median": statistics.median(values),
        "p95": values[math.ceil(len(values) * 0.95) - 1],
        "max": values[-1],
    }


def summarize_method(rows, method):
    both = [r for r in rows if r[method]["found"] and r["reference"]["found"]]
    shots = [r for r in both if r[method]["shot"] and r["reference"]["shot"]]
    extra = [r for r in rows if r[method]["found"] and not r["reference"]["found"]]
    cap_rows = [r for r in rows if r[method]["frame_guard3"]["discarded_ms"] > 0]
    return {
        "extra_candidates": len(extra),
        "missed_contacts": sum(r["reference"]["found"] and not r[method]["found"] for r in rows),
        "noncontact_first_shots": sum(r[method]["shot"] for r in extra),
        "noncontact_first_velocity_changes": sum(r[method]["changed"] for r in extra),
        "noncontact_first_position_only": sum(
            not r[method]["changed"] and r[method]["correction_px"] > 0.001 for r in extra
        ),
        "false_shots": sum(r[method]["shot"] and not r["reference"]["shot"] for r in rows),
        "missed_shots": sum(r["reference"]["shot"] and not r[method]["shot"] for r in rows),
        "both_contacts": len(both),
        "both_shots": len(shots),
        "time_error_ms": distribution([r[method]["time_error_ms"] for r in both]),
        "point_error_px": distribution([r[method]["point_error_px"] for r in both]),
        "end_error_px": distribution([r[method]["end_error_px"] for r in both]),
        "shot_angle_error_deg": distribution([r[method]["angle_error_deg"] for r in shots]),
        "velocity_error_px_s": distribution([r[method]["velocity_error_px_s"] for r in both]),
        "correction_px": distribution([r[method]["correction_px"] for r in both]),
        "position_over_3px": sum(r[method]["end_error_px"] > 3 for r in both),
        "shot_angle_over_half_degree": sum(r[method]["angle_error_deg"] > 0.5 for r in shots),
        "guard3_noncontact_shots": sum(r[method]["frame_guard3"]["frame_shots"] > 0 for r in extra),
        "guard3_noncontact_max_position_error_px": max(
            (r[method]["frame_guard3"]["frame_error_from_free_px"] for r in extra), default=0
        ),
        "guard3_exhausted_inputs": len(cap_rows),
        "guard3_discarded_ms": sum(r[method]["frame_guard3"]["discarded_ms"] for r in rows),
        "guard3_cap_ids": [int(r["id"]) for r in cap_rows],
        "guard3_queries": {
            key: sum(r[method]["frame_guard3"][key] for r in rows)
            for key in ("native_queries", "detection_checks", "separation_checks")
        },
    }


def summarize():
    audit = json.loads((EVIDENCE / "native_audit.json").read_text(encoding="utf-8"))
    result = {"checks": audit["checks"], "failures": audit["failures"], "groups": {}, "benchmark": {}}
    for rate in (60, 30, 120):
        for suite in ("main_336", "previous_540"):
            all_rows = [r for r in audit["cases"] if r["rate"] == rate and r["suite"] == suite]
            rows = [r for r in all_rows if not r["ambiguous"]]
            result["groups"][f"{suite}_{rate}hz"] = {
                "inputs": len(all_rows), "classified": len(rows),
                "ambiguous_ids": [int(r["id"]) for r in all_rows if r["ambiguous"]],
                "clamped_inputs": sum(r["clamped"] for r in all_rows),
                "reference_contacts": sum(r["reference"]["found"] for r in rows),
                "reference_shots": sum(r["reference"]["shot"] for r in rows),
                "native": summarize_method(rows, "native"),
                "sampled": summarize_method(rows, "sampled"),
            }
    for sampled, name in ((False, "native"), (True, "sampled")):
        times = [r["total_us"] / 1000 for r in audit["benchmark"] if r["sampled"] == sampled]
        result["benchmark"][name] = {
            "repetitions": len(times), "batch_inputs": 876,
            "median_batch_ms": statistics.median(times),
            "min_batch_ms": min(times), "max_batch_ms": max(times),
            "mean_us_per_input_at_median_batch": statistics.median(times) * 1000 / 876,
        }
    integration = audit["integration"]
    result["integration"] = {"population": integration["population"], "near_enemy": {}}
    for sampled, name in ((False, "native"), (True, "sampled")):
        rows = [r for r in integration["near_enemy"] if r["sampled"] == sampled]
        result["integration"]["near_enemy"][name] = {
            "placements": len(rows),
            "exhausted_placements": sum(r["exhausted_updates"] > 0 for r in rows),
            "exhausted_updates": sum(r["exhausted_updates"] for r in rows),
            "discarded_ms": sum(r["discarded_ms"] for r in rows),
            "max_correction_px": max(r["max_correction_px"] for r in rows),
        }
    (EVIDENCE / "native_audit_summary.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for key, group in result["groups"].items():
        print(key, "classified", group["classified"])
        for name in ("native", "sampled"):
            row = group[name]
            print(name, "extra/missed", row["extra_candidates"], row["missed_contacts"],
                  "false/lost shots", row["false_shots"], row["missed_shots"],
                  "capped", row["guard3_exhausted_inputs"])
    print("benchmark", result["benchmark"])
    print("near_enemy", result["integration"]["near_enemy"])


if __name__ == "__main__":
    summarize()
