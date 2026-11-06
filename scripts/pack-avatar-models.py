"""Verify and export the five generated folders as stored LivLiv model archives."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "packages/avatar"
OUTPUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "local/avatar-authoring/dist"
OUTPUT.mkdir(parents=True, exist_ok=True)
results = []
for folder in sorted((PACKAGE / "models").iterdir()):
    manifest = json.loads((folder / "manifest.json").read_text())
    model = json.loads((folder / "model.json").read_text())
    for file, expected in manifest["files"].items():
        if hashlib.sha256((folder / file).read_bytes()).hexdigest() != expected:
            raise ValueError("Changed generated asset: " + folder.name + "/" + file)
    archive = OUTPUT / ("dafeiyu-" + folder.name + ".livliv")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED, allowZip64=False) as bundle:
        for file in sorted(folder.rglob("*")):
            if file.is_file():
                bundle.write(file, file.relative_to(folder).as_posix())
        for name in ["LICENSE", "THIRD_PARTY_NOTICES.md"]:
            bundle.write(PACKAGE / name, name)
        bundle.writestr("README.md", f"# {model['name']}\n\nLivLiv v4 model.\n\n"
                        "Head, gaze and expressions use LivLiv Player. Shoulder/elbow/wrist controls require the "
                        "DaFeiYu Player joint extension and stage.json from the accompanying avatar MCP package. "
                        "No independent fingers; not a Cubism MOC or VTube Studio model.\n\n"
                        f"Artwork license: {model['meta']['license']['id']}. See THIRD_PARTY_NOTICES.md for attribution and terms.\n")
    results.append({"model": folder.name, "archive": archive.name, "bytes": archive.stat().st_size,
                    "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "artwork_license": model["meta"]["license"]["id"]})
(OUTPUT / "models-manifest.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
print(f"Verified and packaged {len(results)} LivLiv models")
