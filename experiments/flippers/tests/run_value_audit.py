"""Run each main-scene episode in a fresh Godot process, without parallel CPU noise."""
from pathlib import Path
import argparse
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "experiments/flippers/evidence"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=r"C:\GameDev\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--tag", default="isolated")
    parser.add_argument("--modes", default="A,N,S,B,F,P")
    parser.add_argument("--profiles", default="alternate,held,adaptive")
    parser.add_argument("--seeds", default="113,271,809")
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--rate", type=int, default=60)
    parser.add_argument("--off", action="store_true")
    args = parser.parse_args()
    manifest = []
    for profile in args.profiles.split(","):
        for seed in args.seeds.split(","):
            for mode in args.modes.split(","):
                label = f"value_{'off_' if args.off else ''}{args.tag}_{mode}_{profile}_{seed}_{args.rate}"
                command = [args.godot, "--headless", "--fixed-fps", str(args.rate), "--path", str(ROOT),
                           "--script", "res://experiments/flippers/tests/value_audit.gd", "--",
                           f"--tag={args.tag}", f"--modes={mode}", f"--profiles={profile}",
                           f"--seeds={seed}", f"--seconds={args.seconds}", f"--rate={args.rate}"]
                if args.off:
                    command.append("--off")
                start = time.monotonic()
                result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=180)
                output = result.stdout.decode("utf-8", errors="replace") + result.stderr.decode("utf-8", errors="replace")
                (EVIDENCE / (label + ".log")).write_text(output, encoding="utf-8")
                if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
                    raise RuntimeError(f"{label}: {output[-4000:]}")
                data = json.loads((EVIDENCE / (label + ".json")).read_text(encoding="utf-8"))
                assert data["stats"]["ticks"] == args.rate * args.seconds
                manifest.append({"file": label + ".json", "wall_seconds": time.monotonic() - start})
                print(f"{len(manifest)} {label}: caps={data['stats']['caps']}, large={data['stats']['large_corrections']}", flush=True)
    (EVIDENCE / f"value_{'off_' if args.off else ''}{args.tag}_manifest.json").write_text(
        json.dumps({"arguments": vars(args), "runs": manifest}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
