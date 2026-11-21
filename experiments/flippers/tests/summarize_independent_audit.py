"""Aggregate B/Bprime detection, recovery and response separately."""

import json
import math
import statistics
from pathlib import Path


EVIDENCE = Path(__file__).resolve().parents[1] / "evidence"


def stats(values):
    values = sorted(values)
    if not values:
        return None
    return {"count": len(values), "median": statistics.median(values),
            "p95": values[math.ceil(len(values) * 0.95) - 1], "max": max(values)}


def detection(rows, mode):
    classified = [r for r in rows if not r["ambiguous"]]
    missed = [r for r in classified if r["reference"]["state"] != "none" and r[mode]["state"] == "none"]
    extra = [r for r in classified if r["reference"]["state"] == "none" and r[mode]["state"] != "none"]
    both = [r for r in classified if r["reference"]["state"] != "none" and r[mode]["state"] != "none"]
    return {"classified": len(classified), "missed": len(missed), "extra": len(extra),
            "missed_indices": [rows.index(r) for r in missed],
            "time_error_ms": stats([r[mode]["time_error_ms"] for r in both]),
            "point_error_px": stats([r[mode]["point_error_px"] for r in both]),
            "normal_error_deg": stats([r[mode]["normal_error_deg"] for r in both])}


def summarize():
    audit = json.loads((EVIDENCE / "independent_audit.json").read_text(encoding="utf-8"))
    result = {"checks": audit["checks"], "failures": audit["failures"],
              "detection": {}, "recovery": {}, "replay": {}, "integration": {}, "benchmark": {}}
    for mode in ("mixed", "custom"):
        result["detection"][mode] = detection(audit["detection"], mode)
        result["detection"][mode]["by_rate"] = {
            str(rate): detection([r for r in audit["detection"] if r["rate"] == rate], mode)
            for rate in (30, 60, 120)
        }
    result["detection"]["inputs"] = len(audit["detection"])
    result["detection"]["initial_overlap_classification"] = {
        mode: sum(r[mode]["state"] == "initial_overlap" for r in audit["recovery"])
        for mode in ("mixed", "custom")
    }
    for mode in ("native", "upward"):
        rows = [r["recovery"][mode] for r in audit["recovery"]]
        result["recovery"][mode] = {
            "inputs": len(rows), "first_distance": stats([r["first_distance"] for r in rows]),
            "total_distance": stats([r["distance"] for r in rows]),
            "iterations": stats([len(r["steps"]) for r in rows]),
            "strict_remaining": sum(r["remaining_overlap"] for r in rows),
            "remaining_over_margin": sum(r["steps"][-1]["gap_after"] < -0.03 for r in rows),
            "worst_final_gap": min(r["steps"][-1]["gap_after"] for r in rows),
            "by_feature": {
                str(feature): stats([r["recovery"][mode]["distance"]
                                     for r in audit["recovery"] if r["feature"] == feature])
                for feature in range(8)
            },
        }
    result["recovery"]["flag_false_moved"] = sum(
        math.hypot(*r["flag_false_offset"]) > 0.0001 for r in audit["recovery"]
    )
    for rate in (30, 60, 120):
        rows = [r for r in audit["replay"] if r["rate"] == rate and not r["ambiguous"]]
        result["replay"][str(rate)] = {}
        for moving in (True, False):
            subset = [r for r in rows if r["moving"] == moving]
            result["replay"][str(rate)]["moving" if moving else "stationary"] = {
                "inputs": len(subset), "position_delta": stats([r["position_delta"] for r in subset]),
                "velocity_delta": stats([r["velocity_delta"] for r in subset]),
                "differing_positions": sum(r["position_delta"] > 0.001 for r in subset),
                "mixed_caps": sum(r["mixed"]["discarded_ms"] > 0 for r in subset),
                "custom_caps": sum(r["custom"]["discarded_ms"] > 0 for r in subset),
            }
    result["integration"]["population"] = audit["integration"]["population"]
    for custom, mode in ((False, "mixed"), (True, "custom")):
        rows = [r for r in audit["integration"]["near_enemy"] if r["sampled"] == custom]
        result["integration"][mode] = {
            "placements": len(rows), "capped_placements": sum(r["exhausted_updates"] > 0 for r in rows),
            "capped_updates": sum(r["exhausted_updates"] for r in rows),
            "discarded_ms": sum(r["discarded_ms"] for r in rows),
            "max_correction": max(r["max_correction_px"] for r in rows),
        }
        times = [r["total_us"] / 1000 for r in audit["benchmark"] if r["custom"] == custom]
        result["benchmark"][mode] = {
            "batch_inputs": 876, "repetitions": len(times), "median_ms": statistics.median(times),
            "min_ms": min(times), "max_ms": max(times),
        }
    result["ordering"] = audit["ordering"]
    result["transitions"] = audit["transitions"]
    (EVIDENCE / "independent_audit_summary.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("checks", result["checks"], "failures", result["failures"])
    for mode in ("mixed", "custom"):
        row = result["detection"][mode]
        print(mode, "classified", row["classified"], "missed", row["missed"], "extra", row["extra"])
        print("near_enemy", result["integration"][mode])
        print("benchmark", result["benchmark"][mode])
    for mode in ("native", "upward"):
        print("recovery", mode, result["recovery"][mode])


if __name__ == "__main__":
    summarize()
