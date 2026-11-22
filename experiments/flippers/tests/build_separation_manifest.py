"""List the experiment sources, replay inputs and evidence for a verified export."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
paths = {ROOT / "README.md", ROOT / "shot_rules.md"}
for pattern in ("**/*.gd", "**/*.gd.uid", "**/*.tscn"):
    paths.update(ROOT.glob(pattern))
paths.update((ROOT / "evidence").glob("separation*"))
paths.discard(ROOT / "evidence/separation_manifest.json")
paths.update(Path(__file__).parent / name for name in (
    "summarize_separation_audit.py", "build_separation_manifest.py", "export_separation_evidence.ps1"))
paths.update(ROOT / "evidence" / name for name in (
    "contact_audit.json", "native_audit.json", "continuous_audit.json", "shot_detection.json",
    "shot_response.json", "shot_diagnostics.json", "shot_precision.json", "shot_runtime.json",
    "shot_audit.md", "shot_audit_summary.json"))
files = [{"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size,
          "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(paths)]
manifest = {"scope": "Four-way separation audit; experiment sources and replay inputs. Requires original project to run.",
            "files": files}
(ROOT / "evidence/separation_manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Manifest: {len(files)} files; {sum(row['bytes'] for row in files) / 1024**2:.2f} MiB")
