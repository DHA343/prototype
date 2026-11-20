"""Summarize the saved Godot measurements; uses only the Python standard library."""

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
        "min": values[0],
        "median": statistics.median(values),
        "p95": values[math.ceil(len(values) * 0.95) - 1],
        "max": values[-1],
    }


def summarize():
    audit = json.loads((EVIDENCE / "contact_audit.json").read_text(encoding="utf-8"))
    limits = json.loads((EVIDENCE / "contact_limits.json").read_text(encoding="utf-8"))
    result = {"suites": {}, "limits": [], "chord": audit["chord"]}
    for name in ("previous_540", "main_336"):
        all_rows = [row for row in audit["cases"] if row["suite"] == name]
        rows = [row for row in all_rows if not row["ambiguous"]]
        suite = {
            "inputs": len(all_rows), "classified": len(rows),
            "ambiguous": len(all_rows) - len(rows),
            "reference_contacts": sum(row["reference"]["found"] for row in rows),
            "reference_shots": sum(row["reference"]["shot"] for row in rows),
            "methods": {},
        }
        for method in ("frozen", "frozen_timed", "sampled", "refined4", "refined"):
            extra = [r for r in rows if r[method]["found"] and not r["reference"]["found"]]
            both = [r for r in rows if r[method]["found"] and r["reference"]["found"]]
            powered = [r for r in both if r[method]["shot"] and r["reference"]["shot"]]
            metrics = {
                "extra_contacts": len(extra),
                "missed_contacts": sum(r["reference"]["found"] and not r[method]["found"] for r in rows),
                "noncontact_shots": sum(r[method]["shot"] for r in extra),
                "noncontact_unchanged_velocity": sum(not r[method]["changed"] for r in extra),
                "false_shots": sum(r[method]["shot"] and not r["reference"]["shot"] for r in rows),
                "missed_shots": sum(r["reference"]["shot"] and not r[method]["shot"] for r in rows),
                "extra_min_gap_px": distribution([r["min_gap_px"] for r in extra]),
                "powered_angle_error_deg": distribution([r[method]["angle_delta_deg"] for r in powered]),
                "both_contacts": {},
            }
            for key in ("time_delta_ms", "contact_point_delta_px", "ratio_delta_percent",
                        "angle_delta_deg", "speed_delta_px_s", "velocity_delta_px_s",
                        "end_delta_px", "correction_px"):
                metrics["both_contacts"][key] = distribution([abs(r[method][key]) for r in both])
            if method in ("frozen", "sampled"):
                frame_method = f"{method}_frame"
                metrics["extra_full_frame"] = {
                    "shots": sum(r[frame_method]["shot"] for r in extra),
                    "max_position_error_px": max((r[frame_method]["deviation_from_free_end_px"] for r in extra), default=0),
                    "max_no_shot_position_error_px": max((r[frame_method]["deviation_from_free_end_px"]
                        for r in extra if not r[frame_method]["shot"]), default=0),
                }
            suite["methods"][method] = metrics
        result["suites"][name] = suite
    for run in range(4):
        rows = [r for r in limits["near_enemy"] if r["run"] == run]
        result["limits"].append({
            "run": run, "limit": rows[0]["limit"], "cases": len(rows),
            "exhausted_cases": sum(r["exhausted_updates"] > 0 for r in rows),
            "exhausted_updates": sum(r["exhausted_updates"] for r in rows),
            "discarded_ms_sum": sum(r["discarded_ms"] for r in rows),
            "zero_time_contacts": sum(r["zero_time_contacts"] for r in rows),
            "no_progress_contacts": sum(r["no_progress_contacts"] for r in rows),
            "below_flipper": sum(r["below_flipper"] for r in rows),
        })
    (EVIDENCE / "contact_audit_summary.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for name, suite in result["suites"].items():
        print(name, "inputs", suite["inputs"], "classified", suite["classified"])
        for name, metrics in suite["methods"].items():
            print(name, "extra", metrics["extra_contacts"], "false/missed shots",
                  metrics["false_shots"], metrics["missed_shots"], "max endpoint error",
                  round(metrics["both_contacts"]["end_delta_px"]["max"], 4))


if __name__ == "__main__":
    summarize()
