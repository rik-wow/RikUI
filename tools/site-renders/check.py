"""Check reviewed Lua renders before UI tests, builds and releases."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from schema import FIXTURE_FILES, frames_of, frame_id

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tools/site-renders"
WORLDS = FIXTURES / "worlds"
BASELINE = ROOT / "web/ui-renders"

def digest(path, normalized=False):
    data = path.read_bytes()
    if normalized and path.suffix.lower() in {".lua", ".xml", ".toc", ".txt", ".svg", ".py", ".md", ".json"}:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()

def verify_inputs(manifest, errors):
    # Tracked and untracked (not ignored) files alike, so the gate sees a new source file before its first commit.
    tracked = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                                       "src", "data", "media", ":(glob)presets/**/*.lua", "RikUI.toc", "Bindings.xml"],
                                      cwd=ROOT, text=True).splitlines()
    if set(tracked) != set(manifest["addonFiles"]):
        errors.append("Addon file inventory changed; render the current addon")
    for name in tracked:
        if not (ROOT / name).is_file() or digest(ROOT / name, True) != manifest["addonFiles"].get(name):
            errors.append("Stale addon input: " + name)
    for name in FIXTURE_FILES:
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

def verify_world(case, frame, name, errors):
    """A world capture names the plate it was composited over; the plate and its record must still match."""
    world = frame.get("plate") or {}
    plate = (case.get("world") or {}).get("plate")
    if world.get("plate") != plate:
        errors.append("World plate changed: " + name)
        return
    record_path, image_path = WORLDS / (plate + ".json"), None
    if not record_path.is_file():
        errors.append("Missing world plate record: " + name)
        return
    record = json.loads(record_path.read_text(encoding="utf-8"))
    image_path = WORLDS / record.get("file", "")
    if record.get("sha256") != world.get("sha256") or not image_path.is_file() or digest(image_path) != record.get("sha256"):
        errors.append("World plate does not match the capture: " + name)

def verify_frame(case, capture, frame, manifest, directory, errors, hashes):
    name = frame_id(capture, frame)
    image = directory / frame["filename"]
    if not image.is_file() or digest(image) != frame["sha256"]:
        errors.append("Missing or changed image: " + name)
    if frame.get("reviewedSha256") != frame["sha256"]:
        errors.append("Image needs visual review: " + name)
    # A capture of icon-only controls legitimately has no text; the diagnostics must still exist.
    if not isinstance(frame.get("diagnostics"), dict) or "visibleTextCount" not in frame["diagnostics"]:
        errors.append("Missing frame diagnostics: " + name)
    if case.get("world") or frame.get("plate"):
        verify_world(case, frame, name, errors)
    key = (case["page"], frame["sha256"])
    if key in hashes:
        errors.append("Identical states: " + hashes[key] + " and " + name)
    hashes[key] = name

def verify_capture(case, capture, manifest, directory, errors, hashes):
    if capture.get("generation") != manifest.get("generation") or not manifest.get("generation"):
        errors.append("Mixed or stale render generation: " + case["id"])
    if any(capture.get(key) != value for key, value in case.items()):
        errors.append("Scenario changed: " + case["id"])
    if capture.get("client", {}).get("foreverCommit") != manifest["client"]["foreverCommit"]:
        errors.append("Mixed client builds: " + case["id"])
    if capture.get("seedSha256") != digest(FIXTURES / "seed.lua"):
        errors.append("Stale character fixture: " + case["id"])
    if bool(case.get("sequence")) != bool(capture.get("frames")):
        errors.append("Sequence frames missing: " + case["id"])
    if case.get("sequence"):
        values = [frame.get("value") for frame in capture["frames"]]
        if values != case["sequence"]["values"]:
            errors.append("Sequence values changed: " + case["id"])
    for frame in frames_of(capture):
        verify_frame(case, capture, frame, manifest, directory, errors, hashes)

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
    images = sum(len(frames_of(capture)) for capture in manifest["renders"])
    print(f"UI render gate passed: {len(cases)} reviewed captures ({images} images); addon inputs and fixtures match.")
    return manifest

if __name__ == "__main__":
    try:
        check()
    except (RuntimeError, KeyError, OSError, ValueError) as error:
        print("UI render gate failed:\n" + str(error), file=sys.stderr)
        sys.exit(1)
