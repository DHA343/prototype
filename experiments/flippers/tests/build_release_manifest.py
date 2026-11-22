"""Build a replayable evidence manifest without changing prior audit bundles."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
paths = {ROOT / "README.md", ROOT / "shot_rules.md"}
for pattern in ("**/*.gd", "**/*.gd.uid", "**/*.tscn"):
    paths.update(ROOT.glob(pattern))
paths.update((ROOT / "evidence").glob("release*"))
paths.discard(ROOT / "evidence/release_manifest.json")
paths.update(Path(__file__).parent / name for name in (
    "summarize_release_audit.py", "build_release_manifest.py", "export_release_evidence.ps1"))
paths.update(ROOT / "evidence" / name for name in (
    "contact_audit.json", "native_audit.json", "continuous_audit.json",
    "separation_response.json", "separation_diagnostics.json", "separation_audit.md"))
manifest = {"scope": "Release recovery experiment: sources, inputs, raw evidence. Run in original project.",
            "files": [{"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size,
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(paths)]}
(ROOT / "evidence/release_manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Release manifest: {len(manifest['files'])} files; {sum(row['bytes'] for row in manifest['files']) / 1024**2:.2f} MiB")
