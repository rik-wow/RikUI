"""Check reviewed Lua renders before UI tests, builds and releases.

Every capture records the inputs its pixels came from. The gate rebuilds the tree inputs (script, seed,
addon files, validator, world plate and compositing code) from the repository and names the capture and
the input that no longer match, requires one environment (simulator, client) across the set with the
simulator patch matching the fixture's copy, and requires every image to be the one that was reviewed."""
import json
from pathlib import Path
import subprocess
import sys
from schema import frames_of, frame_id, SCENARIO_KEYS
from fixtures import load_modules, scenario_script
from provenance import digest, tree_inputs, scenario_record, TREE_FIELDS, plate_record, WORLDS

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
BASELINE = ROOT / "web/ui-renders"

def addon_inventory():
    # Tracked and untracked (not ignored) files alike, so the gate sees a new source file before its first commit.
    return subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                                    "src", "data", "media", ":(glob)presets/**/*.lua", "RikUI.toc", "Bindings.xml"],
                                   cwd=ROOT, text=True).splitlines()

def current_addon_files(manifest, errors):
    """The addon inventory as it is now; the manifest's copy must describe the same files."""
    files = {name: digest(ROOT / name, normalized=True) for name in addon_inventory() if (ROOT / name).is_file()}
    if set(files) != set(manifest.get("addonFiles", {})):
        errors.append("Addon file inventory changed; render the current addon")
    for name, value in files.items():
        if manifest.get("addonFiles", {}).get(name) != value:
            errors.append("Stale addon input: " + name)
    return files

def verify_environment(manifest, errors):
    """One simulator and one client across the set, and the simulator patch the fixture carries."""
    renderer = manifest.get("renderer") or {}
    if renderer.get("patch") != digest(FIXTURES / "wow-ui-sim.patch"):
        errors.append("Renderer patch provenance does not match the fixture")
    for capture in manifest.get("renders", []):
        inputs = capture.get("inputs") or {}
        if inputs.get("renderer") != renderer or inputs.get("client") != {key: manifest["client"].get(key) for key in ("version", "foreverCommit", "executableSha256")}:
            errors.append("Mixed render environment: " + capture["id"])

def verify_world(case, frame, name, errors):
    """A world capture names the plate it was composited over; the plate and its record must still match."""
    world = frame.get("plate") or {}
    plate = (case.get("world") or {}).get("plate")
    if world.get("plate") != plate:
        errors.append("World plate changed: " + name)
        return
    if not (WORLDS / (plate + ".json")).is_file():
        errors.append("Missing world plate record: " + name)
        return
    record = plate_record(plate)
    image_path = WORLDS / record.get("file", "")
    if record.get("sha256") != world.get("sha256") or not image_path.is_file() or digest(image_path) != record.get("sha256"):
        errors.append("World plate does not match the capture: " + name)

def verify_frame(case, capture, frame, directory, errors, hashes):
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

def verify_capture(case, capture, expected, directory, errors, hashes):
    """`expected` is the tree part of the inputs rebuilt from the repository for this scenario."""
    recorded = capture.get("inputs") or {}
    reasons = [name for name in TREE_FIELDS if recorded.get(name) != expected.get(name)]
    if any(capture.get(key) != value for key, value in scenario_record(case).items()) \
            or any(key in capture for key in SCENARIO_KEYS if key not in case):
        reasons.append("scenario")
    if reasons:
        errors.append(f"Stale capture {case['id']}: " + ", ".join(reasons))
    if bool(case.get("sequence")) != bool(capture.get("frames")):
        errors.append("Sequence frames missing: " + case["id"])
    if case.get("sequence"):
        values = [frame.get("value") for frame in capture["frames"]]
        if values != case["sequence"]["values"]:
            errors.append("Sequence values changed: " + case["id"])
    for frame in frames_of(capture):
        verify_frame(case, capture, frame, directory, errors, hashes)

def expected_tree_inputs(case, manifest, modules, addon_files):
    script = scenario_script(case, modules, manifest["client"]["version"])
    return tree_inputs(case, script, addon_files)

def verify_captures(manifest, cases, directory, errors, addon_files):
    renders = {r["id"]: r for r in manifest["renders"]}
    if len(renders) != len(manifest["renders"]) or set(renders) != {c["id"] for c in cases}:
        errors.append("Every scenario must have exactly one reviewed capture")
    modules = load_modules()
    hashes = {}
    for case in cases:
        if case["id"] in renders:
            try:
                expected = expected_tree_inputs(case, manifest, modules, addon_files)
            except RuntimeError as error:
                errors.append(str(error))
                continue
            verify_capture(case, renders[case["id"]], expected, directory, errors, hashes)

def check(directory=BASELINE):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    cases = json.loads((FIXTURES / "scenarios.json").read_text(encoding="utf-8"))
    errors = []
    addon_files = current_addon_files(manifest, errors)
    verify_environment(manifest, errors)
    verify_captures(manifest, cases, directory, errors, addon_files)
    if errors:
        raise RuntimeError("\n".join(errors))
    images = sum(len(frames_of(capture)) for capture in manifest["renders"])
    print(f"UI render gate passed: {len(cases)} reviewed captures ({images} images); every capture's inputs match the tree.")
    return manifest

if __name__ == "__main__":
    try:
        check()
    except (RuntimeError, KeyError, OSError, ValueError) as error:
        print("UI render gate failed:\n" + str(error), file=sys.stderr)
        sys.exit(1)
