"""Separate recorded guard mechanisms, local interventions, and descriptive autoplay counts."""
import collections
import hashlib
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "experiments/flippers/evidence"


def read(name):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def episode_events(episode):
    result = []
    for row in episode["rows"]:
        start = episode.get("start_contact_index", 0) if row["frame"] == episode["shot_frame"] else 0
        end = len(row["contacts"])
        if row["frame"] == episode["release_frame"]:
            end = episode.get("release_contact_index", -1) + 1
        result.extend((row["frame"], e) for e in row["contacts"][start:end])
    return result


def main():
    summary = {"scope": "Fixed 3 shot conditions and new-contact normal separation in every new trial",
               "autoplay": {}, "recorded_current_internal": [], "local": [], "component_cost": []}
    previous = read("value_summary.json")
    summary["previous_18_minutes"] = {mode: {key: previous["modes"][mode][key] for key in
        ["wall_seconds", "active_seconds", "shots", "release_inside", "release_depth_max_px"]} for mode in ["A", "B"]}
    summary["original_B_replay"] = []
    for mode in ["current", "early", "immediate"]:
        runs = [read(f"guard_{mode}_{seed}.json") for seed in [113, 271]]
        assert all(r["stats"]["ticks"] == 7200 for r in runs)
        sums = {key: sum(r["guard_counts"][key] for r in runs) for key in runs[0]["guard_counts"]}
        sums.update({"wall_seconds": 240, "active_seconds": sum(r["stats"]["active_ticks"] / 60 for r in runs),
                     "caps": sum(r["stats"]["caps"] for r in runs),
                     "max_slow_run": max(r["stats"]["max_slow_run"] for r in runs),
                     "release_depth_max_px": max(r["stats"]["release_depth_max_px"] for r in runs),
                     "drops": sum(r["stats"]["drops"] for r in runs),
                     "early_releases": sum(e["release_reason"] == "exit" for r in runs for e in r["guard_episodes"])})
        summary["autoplay"][mode] = sums
        if mode != "current":
            continue
        for run in runs:
            old = read(f"value_isolated_B_held_{run['seed']}_60.json")
            assert old["checkpoints"] == run["checkpoints"]
            old_captures = [r for r in old["events"] if r["release"]]
            episodes_by_frame = {e["release_frame"]: e for e in run["guard_episodes"] if e["internal"]}
            for capture in old_captures:
                final = episodes_by_frame[capture["frame"]]["rows"][-1]
                assert math.dist(capture["events"][0]["velocity"], final["contacts"][0]["velocity"]) < .01
                assert math.dist(capture["events"][0]["position"], final["contacts"][0]["position"]) < .001
            summary["original_B_replay"].append({"seed": run["seed"], "one_second_checkpoints_identical": True,
                                                 "saved_internal_first_contacts_matched": len(old_captures)})
            for episode in run["guard_episodes"]:
                if not episode["internal"]:
                    continue
                final = episode["rows"][-1]
                turns = [{"frame": frame, "kind": e["actor_kind"], "incoming": e["incoming"],
                          "outgoing": e["velocity"], "gap": e["gap"]} for frame, e in episode_events(episode)
                         if e["guard"] and e["actor_kind"] != "flipper" and e["incoming"][1] < 0 < e["velocity"][1]]
                affected = [i for i, gap in enumerate(final["start_gap"]) if gap < 0]
                assert turns and all(t["kind"] == "enemy" for t in turns)
                assert affected == [episode["shot"]["side"]]
                summary["recorded_current_internal"].append({
                    "seed": run["seed"], "shot_frame": episode["shot_frame"], "release_frame": episode["release_frame"],
                    "age_ticks": episode["release_frame"] - episode["shot_frame"],
                    "side": affected[0], "depth_px": -min(final["start_gap"]), "turns": turns,
                    "earlier_clear_tick": any(r["guard_before"] and min(r["start_gap"]) > 0
                                              for r in episode["rows"][1:-1]),
                    "maximum_correction_px": max((e["correction_px"] for e in final["contacts"]), default=0),
                    "powered_shots_on_release_tick": sum(e["shot"] for e in final["contacts"]),
                    "cap_on_release_tick": final["cap"],
                    "guard_after_release_tick": final["guard_after"],
                    "end_gap": final["end_gap"], "unexecuted_path_ms": final["unexecuted_path_ms"],
                    "drop_in_recorded_tail": any(not r.get("ball_active", True) for r in episode["tail"])})
    assert len(summary["recorded_current_internal"]) == summary["autoplay"]["current"]["internal_releases"]
    local = read("guard_cases.json")
    assert not local["failures"] and len(local["cases"]) == 39
    summary["local_checks"] = local["checks"]
    grouped = collections.defaultdict(list)
    for row in local["cases"]:
        events = [e for step in row["steps"] for e in step["contacts"]]
        first_shot = next((e for e in events if e["shot"]), None)
        item = {"name": row["fixture"]["name"], "method": row["method"],
                "shots": sum(e["shot"] for e in events), "caps": sum(t["cap"] for t in row["steps"]),
                "internal_releases": sum(t["guard_before"] and not t["guard_after_refresh"]
                                         and min(t["start_gap"]) < 0 for t in row["steps"]),
                "maximum_correction_px": max((e["correction_px"] for e in events), default=0),
                "ending_y_velocity": row["steps"][-1]["velocity_after"][1],
                "first_shot_velocity": first_shot["velocity"] if first_shot else None}
        if row["fixture"]["kind"] == "recorded" and row["method"] == "current":
            expected = row["fixture"]["expected_after_first"]
            item["first_tick_position_delta_from_source"] = math.dist(row["steps"][0]["position_after"], expected["position"])
            item["first_tick_velocity_delta_from_source"] = math.dist(row["steps"][0]["velocity_after"], expected["velocity"])
            item["complete_first_tick_reproduction"] = item["first_tick_position_delta_from_source"] < .001 \
                and item["first_tick_velocity_delta_from_source"] < .01
        summary["local"].append(item)
        grouped[item["name"]].append((row, item))
    for name, group in grouped.items():
        assert group[0][0]["initial"] == group[1][0]["initial"] == group[2][0]["initial"]
        if name.startswith(("top_", "opposite_raised_")):
            assert all(item["shots"] == 1 and item["caps"] == 0 for _, item in group)
            assert all(item["first_shot_velocity"] == group[0][1]["first_shot_velocity"] for _, item in group)
        if name == "descending_catch":
            assert all(item["ending_y_velocity"] < 0 and item["caps"] == 0 for _, item in group)
        if name == "continuous_3s":
            assert all(item["shots"] == 2 and item["caps"] == 0 for _, item in group)
    for item in read("guard_cost.json")["cases"]:
        summary["component_cost"].append({"position": item["position"], "method": item["method"],
                                           "median_batch_mean_us": statistics.median(item["batch_mean_us"])})
    hashes = read("causal_summary.json")["source_hashes"]
    summary["production_hashes_match"] = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected
                                           for path, expected in hashes.items()}
    assert len(hashes) == 13 and all(summary["production_hashes_match"].values())
    summary["warning"] = ("Long autoplay trajectories diverge, so policy counts are descriptive, not causal improvements. "
        "One-tick live snapshot restoration is explicitly checked; later Enemy commands are held, without route/crowd replay.")
    (DATA / "guard_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Guard episodes:", len(summary["recorded_current_internal"]), "; local checks:", local["checks"],
          "; local trials:", len(local["cases"]), "; production hashes unchanged:", len(hashes))


if __name__ == "__main__":
    main()
