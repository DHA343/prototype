"""Summarize D1 geometry, D2 time search, response and detector timings."""

import json
import math
import statistics
from pathlib import Path


EVIDENCE = Path(__file__).resolve().parents[1] / "evidence"


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8"))


def stats(values):
    values = sorted(values)
    if not values:
        return None
    return {"count": len(values), "median": statistics.median(values),
            "p95": values[math.ceil(len(values) * .95) - 1], "max": values[-1]}


def detector(rows, mode):
    valid = [r for r in rows if not r["ambiguous"] and r["unresolved"] == 0]
    both = [r for r in valid if r[mode]["found"] and r["reference"]["found"]]
    result = {
        "classified": len(valid),
        "extra": sum(r[mode]["found"] and not r["reference"]["found"] for r in valid),
        "missed": sum(not r[mode]["found"] and r["reference"]["found"] for r in valid),
        "false_shots": sum(r[mode]["shot"] and not r["reference"]["shot"] for r in valid),
        "missed_shots": sum(not r[mode]["shot"] and r["reference"]["shot"] for r in valid),
    }
    for key in ("time_error_ms", "point_error_px", "normal_error_deg"):
        if mode == "candidate":
            values = [r[mode][key] for r in both]
        elif key == "time_error_ms":
            values = [abs(r[mode]["time_ms"] - r["reference"]["time_ms"]) for r in both]
        elif key == "point_error_px":
            values = [math.dist(r[mode]["point"], r["reference"]["point"]) for r in both]
        else:
            values = []
            for r in both:
                a, b = r[mode]["normal"], r["reference"]["normal"]
                angle = math.atan2(a[0]*b[1] - a[1]*b[0], a[0]*b[0] + a[1]*b[1])
                values.append(abs(math.degrees(angle)))
        result[key] = stats(values)
    return result


def summarize():
    d1 = read("quad_d1.json")
    d2 = read("continuous_audit.json")
    response = read("continuous_response.json")
    benchmark = read("quad_benchmark.json")
    result = {
        "d1": {"checks": d1["checks"], "failures": d1["failures"], "poses": d1["poses"],
               "reference_errors": len(d1["reference_errors"]), "baseline_differences": len(d1["mismatches"]),
               "tie_differences": sum(r.get("tie", False) for r in d1["mismatches"]),
               "other_differences": [r for r in d1["mismatches"] if not r.get("tie", False)],
               "sweeps": len(d1["sweeps"]),
               "sweep_presence_mismatches": sum(r["baseline"]["found"] != r["candidate"]["found"] for r in d1["sweeps"]),
               "sweep_shot_mismatches": sum(r["baseline"].get("striking") != r["candidate"].get("striking") for r in d1["sweeps"])},
        "d2": {"checks": d2["checks"], "failures": d2["failures"], "inputs": len(d2["cases"]),
               "unresolved": d2["unresolved"], "evaluations": stats([r["evaluations"] for r in d2["cases"]]),
               "baseline": detector(d2["cases"], "baseline"),
               "candidate": detector(d2["cases"], "candidate")},
        "benchmark": {}, "response": {"checks": response["checks"], "failures": response["failures"],
                                      "replay": {}, "near_enemy": {}},
    }
    for group in ("original60", "moving_edges"):
        result["benchmark"][group] = {}
        for mode, name in enumerate(("baseline", "d1", "d2")):
            rows = [r for r in benchmark["rounds"] if r["group"] == group and r["mode"] == mode]
            times = [r["total_us"] / 1000 for r in rows]
            result["benchmark"][group][name] = {
                "queries": rows[0]["queries"], "median_ms": statistics.median(times),
                "min_ms": min(times), "max_ms": max(times),
                "evaluations": rows[0]["evaluations"],
            }
    for rate in (30, 60, 120):
        rows = [r for r in response["replay"] if r["rate"] == rate and not r["ambiguous"]]
        result["response"]["replay"][str(rate)] = {}
        for mode in ("baseline", "continuous"):
            both = [r for r in rows if r["reference"]["found"] and r[mode]["first"]["found"]]
            result["response"]["replay"][str(rate)][mode] = {
                "first_end_error": stats([math.dist(r[mode]["first"]["end"], r["reference"]["end"]) for r in both]),
                "first_max_correction": max(r[mode]["first"]["correction_px"] for r in both),
                "capped_inputs": [int(r["id"]) for r in rows if r[mode]["discarded_ms"] > 0],
                "discarded_ms": sum(r[mode]["discarded_ms"] for r in rows),
                "unresolved": sum(r[mode]["unresolved"] for r in rows),
            }
    for flag, name in ((False, "baseline"), (True, "continuous")):
        rows = [r for r in response["integration"]["near_enemy"] if r["sampled"] == flag]
        valid = [r for r in rows if not r.get("invalid", False)]
        result["response"]["near_enemy"][name] = {
            "inputs": len(rows), "invalid_inputs": len(rows) - len(valid),
            "unresolved": sum(r.get("unresolved", 0) for r in rows),
            "capped_inputs": sum(r["exhausted_updates"] > 0 for r in valid),
            "discarded_ms": sum(r["discarded_ms"] for r in valid),
            "max_correction": max(r["max_correction_px"] for r in valid),
        }
    result["response"]["population"] = response["integration"]["population"]
    result["response"]["ordering"] = response["ordering"]
    (EVIDENCE / "quad_audit_summary.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("D1", result["d1"]["poses"], "reference errors", result["d1"]["reference_errors"])
    print("D2 baseline", result["d2"]["baseline"])
    print("D2 candidate", result["d2"]["candidate"])
    print("near enemy", result["response"]["near_enemy"])
    print("benchmark", result["benchmark"])


if __name__ == "__main__":
    summarize()
