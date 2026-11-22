"""Freeze this distance-gate experiment, including excluded diagnostic measurements."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
paths = {ROOT / "README.md", ROOT / "shot_rules.md"}
for pattern in ("**/*.gd", "**/*.gd.uid", "**/*.tscn"):
    paths.update(ROOT.glob(pattern))
paths.update((ROOT / "evidence").glob("unlimited*"))
paths = {path for path in paths if path.is_file() and path.suffix != ".import"}
paths.discard(ROOT / "evidence/unlimited_manifest.json")
paths.update(Path(__file__).parent / name for name in (
    "summarize_unlimited_audit.py", "build_unlimited_manifest.py", "export_unlimited_evidence.ps1"))
paths.update(ROOT / "evidence" / name for name in (
    "contact_audit.json", "native_audit.json", "continuous_audit.json",
    "separation_response.json", "release_audit.json", "release_grid.json", "release_audit.md"))
files = [{"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size,
          "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(paths)]
(ROOT / "evidence/unlimited_manifest.json").write_text(json.dumps({
    "scope": "Unlimited separation sources, replay inputs and evidence; long-trajectory CPU probe is explicitly excluded from performance conclusions.",
    "files": files}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Unlimited manifest: {len(files)} files; {sum(row['bytes'] for row in files)/1024**2:.2f} MiB")
