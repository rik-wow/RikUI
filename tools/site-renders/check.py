"""Check reviewed Lua renders before UI tests, builds and releases.

Every capture records the inputs its pixels came from. The gate rebuilds the tree inputs (script, seed,
addon files, validator, world plate and compositing code) from the repository and names the capture and
the input that no longer match, authenticates each capture's original environment and addon inventory,
and requires every image to be the one that was reviewed."""
import json
import math
from pathlib import Path
import subprocess
import sys
from dependencies import addon_inputs, recorded_addon_inputs
from schema import frames_of, frame_id, SCENARIO_KEYS
from fixtures import load_modules, scenario_script
from provenance import digest, tree_inputs, scenario_record, TREE_FIELDS, plate_record, WORLDS, capture_key

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
BASELINE = ROOT / "web/ui-renders"

def addon_inventory():
    # Tracked and untracked (not ignored) files alike, so the gate sees a new source file before its first commit.
    return subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                                    "src", "data", "media", ":(glob)presets/**/*.lua", "RikUI.toc", "Bindings.xml"],
                                   cwd=ROOT, text=True).splitlines()

def current_addon_files(manifest, errors):
    """Read current files; per-capture checks compare only the relevant dependencies."""
    files = {name: digest(ROOT / name, normalized=True) for name in addon_inventory() if (ROOT / name).is_file()}
    return files

def verify_environment(manifest, errors):
    """Historical captures keep their environment; new runs verify the latest client separately."""
    captures = [record for parent in manifest.get("renders", []) for record in [parent, *[f for f in parent.get("frames", []) if "inputs" in f]]]
    for capture in captures:
        inputs = capture.get("inputs") or {}
        renderer, client = inputs.get("renderer") or {}, inputs.get("client") or {}
        if not all(renderer.get(key) for key in ("binary", "patch")) or not all(
                client.get(key) for key in ("version", "foreverCommit", "executableSha256")):
            errors.append("Missing render environment: " + capture.get("id", str(capture.get("value"))))
        if capture.get("key") != capture_key(inputs):
            errors.append("Changed capture provenance: " + capture.get("id", str(capture.get("value"))))

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

def verify_components(case, frame, name, errors):
    components = frame.get("components") or {}
    value = str(frame.get("value"))
    grids = case.get("frame") == "RikRenderStudioGrids" and case.get("sequence", {}).get("apply") == "RikRenderStudioGrids(VALUE)"
    keys = ("main", "bar2", "bar3", "bar4", "bar5", "stance", "pet") if grids else (value,)
    if set(components) != set(keys) or (not grids and not case.get("sequence", {}).get("frames", {}).get(value)):
        errors.append("Missing native component identity: " + name)
        return
    for geometry in components.values():
        if any(type(geometry.get(k)) not in (int, float) or not math.isfinite(geometry[k]) for k in ("x", "y", "width", "height")) or geometry["width"] <= 0 or geometry["height"] <= 0 or geometry["x"] < 0 or geometry["y"] < 0 or geometry["x"] + geometry["width"] > frame["width"] + 0.002 or geometry["y"] + geometry["height"] > frame["height"] + 0.002:
            errors.append("Invalid native component geometry: " + name)
            return
    if grids:
        size = frame.get("value")
        if size not in (30, 36, 42, 48):
            errors.append("Unsupported native grid size: " + name)
            return
        top = 8
        for key in keys:
            count = 3 if key == "stance" else 10 if key == "pet" else 12
            columns, rows = min(4, count), math.ceil(count / 4)
            width, height = columns * size + (columns - 1) * 6, rows * size + (rows - 1) * 6
            expected = {"x": 8, "y": frame["height"] - top - height, "width": width, "height": height}
            if any(abs(components[key][field] - expected[field]) > 0.002 for field in expected):
                errors.append("Native grid cells disagree: " + name + ":" + key)
            top += height + 16

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
    if case["page"] == "studio-atlas":
        # Distinct native roots can legitimately draw identical empty slots; authenticate
        # their individual component geometry rather than inventing decorative differences.
        value = str(frame.get("value"))
        verify_components(case, frame, name, errors)
        key = (case["page"], case["id"], value, frame["sha256"])
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

def expected_tree_inputs(case, manifest, modules, addon_files, capture=None):
    if capture is None:
        capture = next(c for c in manifest["renders"] if c["id"] == case["id"])
    script = scenario_script(case, modules, capture["inputs"]["client"]["version"])
    expected = tree_inputs(case, script, addon_files)
    recorded = recorded_addon_inputs(case, capture, manifest)
    # Legacy captures hashed the entire addon. Authenticate the original inventory
    # before comparing only the relevant files; do not relabel old pixels.
    if recorded == addon_inputs(case, addon_files):
        expected["addon"] = capture["inputs"]["addon"]
    return expected

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
            capture = renders[case["id"]]
            verify_capture(case, capture, expected, directory, errors, hashes)
            for frame in capture.get("frames", []):
                if "inputs" not in frame:
                    continue  # Original sequences remain authenticated by their parent.
                from sequence_cache import value_case, matches_fixture
                scoped = value_case(case, frame["value"])
                try:
                    expected_frame = expected_tree_inputs(scoped, manifest, modules, addon_files, frame)
                    reasons = [k for k in TREE_FIELDS if frame["inputs"].get(k) != expected_frame.get(k)]
                    if reasons:
                        errors.append("Stale sequence frame " + frame_id(capture, frame) + ": " + ", ".join(reasons))
                    from provenance import text_digest
                    script = scenario_script(case, modules, frame["inputs"]["client"]["version"], frame["value"])
                    if not matches_fixture(frame, script):
                        errors.append("Changed sequence fixture: " + frame_id(capture, frame))
                except RuntimeError as error:
                    errors.append(str(error))

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
