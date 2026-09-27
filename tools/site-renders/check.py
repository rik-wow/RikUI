"""Check reviewed Lua renders before UI tests, builds and releases."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tools/site-renders"
BASELINE = ROOT / "web/ui-renders"

def digest(path, normalized=False):
    data = path.read_bytes()
    if normalized and path.suffix.lower() in {".lua", ".xml", ".toc", ".txt", ".svg", ".py", ".md", ".json"}:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()

def verify_inputs(manifest, errors):
    tracked = subprocess.check_output(["git", "ls-files", "src", "data", "media", ":(glob)presets/**/*.lua", "RikUI.toc", "Bindings.xml"],
                                      cwd=ROOT, text=True).splitlines()
    if set(tracked) != set(manifest["addonFiles"]):
        errors.append("Addon file inventory changed; render the current addon")
    for name in tracked:
        if not (ROOT / name).is_file() or digest(ROOT / name, True) != manifest["addonFiles"].get(name):
            errors.append("Stale addon input: " + name)
    for name in ("common.lua", "seed.lua", "scenarios.json", "render.py", "validate_capture.py", "wow-ui-sim.patch"):
        if digest(FIXTURES / name) != manifest.get("fixtureFiles", {}).get(name):
            errors.append("Stale capture tooling: " + name)

def verify_generation(manifest, errors):
    provenance = {key: manifest[key] for key in
                  ("addonFiles", "fixtureFiles", "rendererBinarySha256", "rendererCommit")}
    provenance["client"] = {key: manifest["client"][key] for key in
                            ("version", "foreverCommit", "executableSha256", "cache")}
    expected = hashlib.sha256(json.dumps(provenance, sort_keys=True).encode()).hexdigest()
    if manifest.get("generation") != expected:
        errors.append("Render provenance changed after capture")
    if manifest.get("rendererPatchSha256") != manifest["fixtureFiles"].get("wow-ui-sim.patch"):
        errors.append("Renderer patch provenance does not match the fixture")

def verify_capture(case, capture, manifest, directory, errors, hashes):
    if capture.get("generation") != manifest.get("generation") or not manifest.get("generation"):
        errors.append("Mixed or stale render generation: " + case["id"])
    if any(capture.get(key) != value for key, value in case.items()):
        errors.append("Scenario changed: " + case["id"])
    image = directory / capture["filename"]
    if not image.is_file() or digest(image) != capture["sha256"]:
        errors.append("Missing or changed image: " + case["id"])
    if capture.get("reviewedSha256") != capture["sha256"]:
        errors.append("Image needs visual review: " + case["id"])
    if capture.get("client", {}).get("foreverCommit") != manifest["client"]["foreverCommit"]:
        errors.append("Mixed client builds: " + case["id"])
    if capture.get("seedSha256") != digest(FIXTURES / "seed.lua"):
        errors.append("Stale character fixture: " + case["id"])
    if not capture.get("diagnostics", {}).get("visibleTextCount"):
        errors.append("Missing frame diagnostics: " + case["id"])
    key = (case["page"], capture["sha256"])
    if key in hashes:
        errors.append("Identical states: " + hashes[key] + " and " + case["id"])
    hashes[key] = case["id"]

def verify_captures(manifest, cases, directory, errors):
    renders = {r["id"]: r for r in manifest["renders"]}
    if len(renders) != len(manifest["renders"]) or set(renders) != {c["id"] for c in cases}:
        errors.append("Every scenario must have exactly one reviewed capture")
    hashes = {}
    for case in cases:
        if case["id"] in renders:
            verify_capture(case, renders[case["id"]], manifest, directory, errors, hashes)

def check(directory=BASELINE):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    cases = json.loads((FIXTURES / "scenarios.json").read_text(encoding="utf-8"))
    errors = []
    verify_inputs(manifest, errors)
    verify_generation(manifest, errors)
    verify_captures(manifest, cases, directory, errors)
    if errors:
        raise RuntimeError("\n".join(errors))
    print(f"UI render gate passed: {len(cases)} reviewed captures; addon inputs and fixtures match.")
    return manifest

if __name__ == "__main__":
    try:
        check()
    except (RuntimeError, KeyError, OSError, ValueError) as error:
        print("UI render gate failed:\n" + str(error), file=sys.stderr)
        sys.exit(1)

