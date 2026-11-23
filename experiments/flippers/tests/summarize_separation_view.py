"""Check the visual fixtures against their CLI and rendered first-contact results."""
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "experiments/flippers/evidence"


def read(name):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def main():
    cli = read("separation_view.json")
    live = read("separation_view_runtime.json")
    assert cli["checks"] == 130 and not cli["failures"]
    assert len(cli["cases"]) == 20 and len(live["cases"]) == 16
    comparisons = []
    for row in live["cases"]:
        saved = next(r for r in cli["cases"] if r["scene"] == row["scene"]
                     and r["mode"] == row["mode"] and r["variant"] == 0)
        assert saved["initial"] == row["initial"]
        a, b = saved["events"][0], row["first"]
        position_delta = math.dist(a["position"], b["position"])
        velocity_delta = math.dist(a["velocity"], b["velocity"])
        correction_delta = abs(a["correction_px"] - b["correction_px"])
        assert position_delta < .001 and velocity_delta < .01 and correction_delta < .003
        assert a["shot"] == b["shot"] and a["new_contact"] == b["new_contact"]
        comparisons.append({"scene": row["scene"], "mode": row["mode"],
                            "position_delta_px": position_delta, "velocity_delta_px_s": velocity_delta,
                            "correction_delta_px": correction_delta})
    hashes = read("causal_summary.json")["source_hashes"]
    matches = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected
               for path, expected in hashes.items()}
    assert len(matches) == 13 and all(matches.values())
    summary = {"cli_checks": cli["checks"], "cli_failures": cli["failures"],
               "visual_cases": len(live["cases"]), "comparisons": comparisons,
               "production_hashes_match": matches,
               "scope": "Same initial state and first contact checked; long trajectories need not remain identical"}
    (DATA / "separation_view_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print("CLI checks:", cli["checks"], "; live comparisons:", len(comparisons), "; production hashes:", len(matches))


if __name__ == "__main__":
    main()
