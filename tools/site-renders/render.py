"""Capture RikUI's Lua output using verified current client inputs.

By default only stale captures render: those whose recorded inputs (script, seed, addon, validator,
world plate, corpus) or scenario differ from the current tree. Unchanged captures retain their own
simulator and client evidence; every new capture uses verified current inputs.
`--all` renders everything; `--only` names scenario ids or page slugs."""
import argparse
from datetime import datetime, timezone
import json
import shutil
import os
from pathlib import Path
import re
import subprocess
from dependencies import inventory_history, recorded_addon_inputs, addon_inputs, compact_inventories
from schema import CORPUS_DIRS
from fixtures import load_modules, resolve, scenario_script as build_script
from provenance import digest, tree_inputs, environment_inputs, capture_key, stale_reasons, scenario_record, plate_record
from validate_capture import validate_capture, screen_size
from composite import composite_world

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
WORLDS = FIXTURES / "worlds"
ROAD_PATCH_PREFIX = "RikUIQuestRoads_"
KNOWN_STARTUP_ERRORS = (
    'unknown event "GLOBAL_REGION_MOUSE_DOWN"',
    'unknown event "ALERT_AGE_VERIFICATION_RESTRICTED"',
    "attempt to index field 'FrameControlsManager'",
    "generated\\roads/roads.xml",
    "attempt to index field 'ForeverExperiencePreset'",
    "attempt to call method 'GetVariable'",
)
# Set once per run: the fixture modules and the verified client version every script is built from.
MODULES = None
CLIENT_VERSION = None

def addon_digest(path):
    return digest(path, normalized=True)

def checked(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()

def verify_source(source):
    upstream = checked(["git", "ls-remote", "https://github.com/Gethe/wow-ui-source.git",
                        "refs/heads/forever"], timeout=30).split()
    if len(upstream) != 2:
        raise RuntimeError("Cannot resolve the current Forever source head")
    head = checked(["git", "rev-parse", "HEAD"], cwd=source)
    if head != upstream[0]:
        raise RuntimeError("Forever source checkout is stale; refresh it before rendering")
    if checked(["git", "status", "--porcelain", "--untracked-files=no"], cwd=source):
        raise RuntimeError("Forever source checkout has local edits")
    version = checked(["git", "show", "HEAD:version.txt"], cwd=source)
    if not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", version):
        raise RuntimeError("Forever source version is not a full client version")
    return head, version

def installed_version(executable):
    env = {**os.environ, "RIK_RENDER_CLIENT_EXE": str(executable)}
    return checked(["powershell", "-NoProfile", "-NonInteractive", "-Command",
                    "(Get-Item -LiteralPath $env:RIK_RENDER_CLIENT_EXE -ErrorAction Stop)"
                    ".VersionInfo.FileVersion"], env=env, timeout=30)

def verify_cache(sim_root, version):
    cache = Path(os.environ["LOCALAPPDATA"]) / "wow-ui-sim/blizzard-ui/wowforever/AddOns"
    stamp = cache / ".wow-ui-sim-blizzard-ui-provenance"
    fields = dict(line.split("=", 1) for line in stamp.read_text().splitlines() if "=" in line)
    manifest = sim_root / "source/data/blizzard-ui-files/wowforever.txt"
    expected = {"profile": "wowforever", "product": "wow_classic_beta", "version": version,
                "manifest_sha256": digest(manifest), "fallback": "none"}
    if any(fields.get(key) != value for key, value in expected.items()):
        raise RuntimeError("Blizzard UI cache provenance does not match the current client")
    if not (cache / ".wow-ui-sim-blizzard-ui-complete").is_file():
        raise RuntimeError("Blizzard UI cache is incomplete")
    missing = [name for name in manifest.read_text().splitlines() if name and not (cache / name).is_file()]
    if missing:
        raise RuntimeError("Blizzard UI cache is missing: " + missing[0])
    return fields

def verify_client(sim_root, wow_root):
    head, version = verify_source(sim_root / "forever-source")
    executable = wow_root / "_classic_beta_/WowB.exe"
    installed = installed_version(executable)
    if installed != version:
        raise RuntimeError(f"Client/source mismatch: installed {installed}, source {version}")
    return {"version": version, "foreverCommit": head,
            "executableSha256": digest(executable), "cache": verify_cache(sim_root, version),
            "verifiedAt": datetime.now(timezone.utc).isoformat()}

def addon_inventory():
    # Tracked and untracked (not ignored) files alike, so a new source file counts before its first commit.
    return checked(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                    "src", "data", "media", ":(glob)presets/**/*.lua", "RikUI.toc", "Bindings.xml"], cwd=ROOT).splitlines()

def verify_addon(addon):
    checked_files = {}
    for name in addon_inventory():
        source, installed = ROOT / name, addon / name
        if not installed.is_file() or addon_digest(source) != addon_digest(installed):
            raise RuntimeError("Renderer addon is stale: " + name)
        checked_files[name] = addon_digest(source)
    return checked_files

def cvar_store(sim_root):
    return sim_root / "WTF/render-cvars.json"

def environment(sim_root, wow_root, case):
    env = {**os.environ, "WOW_INSTALL_PATH": str(wow_root), "WOW_SIM_WOW_PATH": str(wow_root),
           "WOW_SIM_ADDONS_PATH": str(sim_root / "addons"),
           "WOW_SIM_ADDONS_TXT": str(sim_root / "AddOns.txt"),
           "WOW_SIM_WTF_PATH": str(sim_root / "WTF"), "WOW_SIM_WTF_ACCOUNT": "RENDER",
           "WOW_SIM_WTF_REALM": "Preview", "WOW_SIM_WTF_CHARACTER": "Rikui",
           # The simulator persists cvar overrides across runs, and RikUI mirrors its settings into cvars;
           # each capture starts from an empty store of its own (render_frame removes it).
           "WOW_SIM_CVARS_PATH": str(cvar_store(sim_root))}
    # A world scenario renders RikUI alone on a transparent layer; the plate goes underneath afterwards.
    env["WOW_SIM_TRANSPARENT_BACKGROUND" if case.get("world") else "WOW_SIM_PLAIN_BACKGROUND"] = "1"
    return env

def scenario_script(case, value=None):
    return build_script(case, MODULES, CLIENT_VERSION, value)

def render_command(case, binary, script, image):
    width, height = screen_size(case)
    command = [str(binary), "--no-saved-vars", "--exec-lua", "@" + str(script),
               "screenshot", "--width", str(width), "--height", str(height), "--filter", case["frame"],
               "--crop", case["crop"], "--output", str(image), "--dump-tree", case["frame"]]
    if case.get("delay"):
        command[1:1] = ["--delay", str(case["delay"])]
    return command

def verify_log(case, result, text, log):
    errors = [line for line in text.splitlines() if "Lua error:" in line
              and not any(allowed in line for allowed in KNOWN_STARTUP_ERRORS)]
    if result.returncode or "[exec-lua] error:" in text or "RIK_RENDER_OK" not in text or errors:
        details = "\n".join(errors[:5] or [line for line in text.splitlines() if "[exec-lua] error:" in line])
        raise RuntimeError(f"Render failed: {case['id']}; {details}; inspect {log}")

def plate_provenance(case):
    """The world plate a scenario composites over, with the provenance written by plates.mjs."""
    name = case["world"]["plate"]
    record = plate_record(name)
    image = WORLDS / record["file"]
    if not image.is_file() or digest(image) != record["sha256"]:
        raise RuntimeError("World plate does not match its record: " + name)
    return {"plate": name, "sha256": record["sha256"], "appCommit": record["app"]["commit"],
            "camera": record["camera"], "captured": record["capturedAt"]}, image

def render_frame(case, binary, env, output, value=None, stem=None):
    """Render one image for a scenario (or one frame of a sequence) and validate it."""
    stem = stem or case["id"]
    script, log = output / (stem + ".lua"), output / (stem + ".log")
    image = output / (stem + ".webp")
    layer = output / (stem + ".layer.webp") if case.get("world") else image
    script.write_text(scenario_script(case, value), encoding="utf-8")
    store = Path(env["WOW_SIM_CVARS_PATH"])
    if store.exists():
        store.unlink()
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(render_command(case, binary, script, layer), env=env,
                                stdout=stream, stderr=subprocess.STDOUT, timeout=90, cwd=binary.parent)
    text = log.read_text(encoding="utf-8")
    verify_log(case, result, text, log)
    if not layer.is_file():
        raise RuntimeError("Renderer did not produce " + str(layer))
    diagnostics = validate_capture(case, layer, text)
    plate = None
    if case.get("world"):
        plate, plate_image = plate_provenance(case)
        composite_world(layer, plate_image, case, image)
    dimensions = case["crop"].split("+", 1)[0].split("x")
    frame = {"diagnostics": diagnostics, "sha256": digest(image), "bytes": image.stat().st_size,
             "fixtureSha256": digest(script), "filename": image.name,
             "width": int(dimensions[0]), "height": int(dimensions[1])}
    if plate:
        frame["plate"] = plate  # provenance of the world underneath; the scenario's own "world" key stays as written
    return frame

def render_case(case, binary, env, output):
    if not case.get("sequence"):
        return {**case, **render_frame(case, binary, env, output)}
    sequence = case["sequence"]
    frames = []
    for value in sequence["values"]:
        frame = render_frame(case, binary, env, output, value, case["id"] + "@" + str(value))
        frames.append({"value": value, **frame})
    default = next((frame for frame in frames if frame["value"] == sequence.get("default", frames[0]["value"])), frames[0])
    # The record carries the default frame's image like any capture, plus every frame.
    return {**case, **{key: default[key] for key in default if key != "value"}, "frames": frames}

def install_seed(sim_root):
    seed = sim_root / "addons/A_RikUIPreview"
    seed.mkdir(parents=True, exist_ok=True)
    (seed / "seed.lua").write_bytes((FIXTURES / "seed.lua").read_bytes())
    (seed / "A_RikUIPreview.toc").write_text(
        "## Interface: 16001\n## Title: RikUI render inputs\n## LoadFirst: 1\nseed.lua\n", encoding="utf-8")

def renderer_provenance(sim_root, binary):
    return {"binary": digest(binary), "patch": digest(FIXTURES / "wow-ui-sim.patch"),
            "commit": checked(["git", "rev-parse", "HEAD"], cwd=sim_root / "source")}

def corpus_digest():
    """The quest corpus is installer-written and ignored by git; its catalogue names every part."""
    catalog = ROOT / "generated/corpus/catalog.lua"
    return digest(catalog) if catalog.is_file() else None

def road_patch_sources(wow_root):
    """The installer-written road patch addons beside the client's RikUI: LoadOnDemand cell packs the
    road router loads for the player's region. They ship with the same revision as generated/roads."""
    addons = wow_root / "_classic_beta_/Interface/AddOns"
    return sorted(p for p in addons.iterdir() if p.is_dir() and p.name.startswith(ROAD_PATCH_PREFIX)) if addons.is_dir() else []

def set_addon_state(sim_root, names, enabled):
    """Mark addons enabled or disabled in the simulator's AddOns.txt; a disabled LoadOnDemand addon refuses to load."""
    path = sim_root / "AddOns.txt"
    lines = [line for line in (path.read_text(encoding="utf-8").splitlines() if path.is_file() else [])
             if line.split(":", 1)[0].strip() not in names]
    lines.extend(f"{name}: {'enabled' if enabled else 'disabled'}" for name in names)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

def isolate_addons(sim_root, wow_root, source=None):
    """The simulator discovers installed/bundled addons even with an override path."""
    source = source or sim_root / "source"
    roots = (sim_root / "addons", wow_root / "_classic_beta_/Interface/AddOns",
             source / "Interface/AddOns", source / "target/debug/Interface/AddOns")
    names = {"Admin", "SimCommands", "TestFramework"}
    for root in roots:
        if root.is_dir():
            names.update(path.name for path in root.iterdir()
                         if path.is_dir() and not path.name.startswith("Blizzard_"))
    set_addon_state(sim_root, sorted(names), False)
    set_addon_state(sim_root, ["RikUI", "A_RikUIPreview"], True)

def stage_corpus(sim_root, wow_root, wanted):
    """Copy the generated corpus, road data and road patch addons into the render copy for scenarios
    that need them, and take them out again for the rest, so ordinary captures keep the short startup."""
    addon = sim_root / "addons/RikUI/generated"
    staged_patches = sorted(p for p in (sim_root / "addons").iterdir() if p.name.startswith(ROAD_PATCH_PREFIX))
    present = all((addon / name).is_dir() for name in CORPUS_DIRS) and bool(staged_patches)
    if wanted == present:
        return
    for name in CORPUS_DIRS:
        target = addon / name
        if target.exists():
            shutil.rmtree(target)
        if wanted:
            source = ROOT / "generated" / name
            if not source.is_dir():
                raise RuntimeError("Quest corpus missing: " + str(source))
            shutil.copytree(source, target)
    for patch in staged_patches:
        shutil.rmtree(patch)
    set_addon_state(sim_root, [p.name for p in staged_patches], False)
    if wanted:
        sources = road_patch_sources(wow_root)
        if not sources:
            raise RuntimeError("Road patch addons missing beside the client's RikUI")
        for source in sources:
            shutil.copytree(source, sim_root / "addons" / source.name)
        set_addon_state(sim_root, [p.name for p in sources], True)

def capture_inputs(case, addon_files, renderer, client):
    corpus = corpus_digest() if case.get("corpus") is True else None
    return {**tree_inputs(case, scenario_script(case), addon_files), **environment_inputs(renderer, client, corpus)}

def select_stale(cases, renders, addon_files, renderer, client, manifest=None):
    """Cases whose recorded capture no longer stands, with the reasons, and the inputs for each case."""
    stale, inputs, reasons = [], {}, {}
    for case in cases:
        inputs[case["id"]] = capture_inputs(case, addon_files, renderer, client)
        capture = renders.get(case["id"])
        comparison = dict(inputs[case["id"]])
        if capture:
            # Compare the tree in the capture's recorded environment. Any recapture
            # still uses inputs built above from the verified latest client.
            old = capture.get("inputs", {})
            comparison["renderer"], comparison["client"] = old.get("renderer"), old.get("client")
            comparison["script"] = tree_inputs(case, build_script(case, MODULES, (old.get("client") or {}).get("version")), addon_files)["script"]
            try:
                if recorded_addon_inputs(case, capture, manifest or {}) == addon_inputs(case, addon_files):
                    comparison["addon"] = old["addon"]
                comparison["addonFiles"] = old.get("addonFiles")
                if "addonFiles" not in old:
                    comparison.pop("addonFiles", None)
            except RuntimeError:
                pass
        why = stale_reasons(case, capture, comparison)
        if capture and (not all((capture.get("inputs", {}).get("client") or {}).get(k)
                               for k in ("version", "foreverCommit", "executableSha256"))
                        or not all((capture.get("inputs", {}).get("renderer") or {}).get(k)
                                   for k in ("binary", "patch"))):
            why.append("environment")
        if capture and capture.get("key") != capture_key(capture.get("inputs", {})):
            why.append("provenance")
        if why:
            stale.append(case)
            reasons[case["id"]] = why
    return stale, inputs, reasons

def capture_cases(cases, inputs, binary, sim_root, wow_root, output, manifest, renders, keep_going=False):
    """Render each case; with keep_going a failed capture is reported and the rest still render."""
    manifest_path = output / "manifest.json"
    failures = []
    try:
        for case in cases:
            stage_corpus(sim_root, wow_root, case.get("corpus") is True)
            try:
                capture = render_case(case, binary, environment(sim_root, wow_root, case), output)
            except RuntimeError as error:
                if not keep_going:
                    raise
                failures.append(f"{case['id']}: {error}")
                print("FAILED " + case["id"] + ": " + str(error).splitlines()[0][:200], flush=True)
                continue
            capture.update(inputs=inputs[case["id"]], key=capture_key(inputs[case["id"]]),
                           modules=resolve(case, MODULES))
            renders[case["id"]] = capture
            manifest["renders"] = list(renders.values())
            compact_inventories(manifest)
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
            print("Rendered " + case["id"] + (f" ({len(capture['frames'])} frames)" if capture.get("frames") else ""), flush=True)
    finally:
        stage_corpus(sim_root, wow_root, False)
    if failures:
        raise RuntimeError(f"{len(failures)} captures failed:\n" + "\n".join(failures))

def summarize(reasons):
    counts = {}
    for why in reasons.values():
        for name in why:
            counts[name] = counts.get(name, 0) + 1
    return ", ".join(f"{name}={count}" for name, count in sorted(counts.items(), key=lambda item: -item[1]))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim-root", type=Path, required=True)
    parser.add_argument("--wow-root", type=Path, required=True)
    parser.add_argument("--only", default="", help="Comma-separated scenario IDs or page slugs")
    parser.add_argument("--all", action="store_true", help="Render every selected scenario, stale or not")
    parser.add_argument("--keep-going", action="store_true", help="Report failed captures at the end instead of stopping at the first")
    args = parser.parse_args()
    sim_root, wow_root = args.sim_root.resolve(), args.wow_root.resolve()
    binary = sim_root / "source/target/debug/wow-sim.exe"
    if not binary.is_file():
        raise RuntimeError("Build wow-ui-sim with gui,client-wowforever first")
    client = verify_client(sim_root, wow_root)
    global CLIENT_VERSION, MODULES
    CLIENT_VERSION = client["version"]
    MODULES = load_modules()
    print("Verified current Forever client " + client["version"], flush=True)
    addon_files = verify_addon(sim_root / "addons/RikUI")
    install_seed(sim_root)
    isolate_addons(sim_root, wow_root)
    output = ROOT / "dist/ui-renders"
    output.mkdir(parents=True, exist_ok=True)
    scenarios = json.loads((FIXTURES / "scenarios.json").read_text(encoding="utf-8"))
    selected = set(args.only.split(",")) if args.only else None
    cases = [s for s in scenarios if not selected or s["id"] in selected or s["page"] in selected]
    if not cases:
        raise RuntimeError("No matching render scenarios")
    manifest_path = output / "manifest.json"
    previous = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    known = {c["id"] for c in scenarios}
    renders = {r["id"]: r for r in previous.get("renders", []) if r["id"] in known}
    history = inventory_history(previous)
    baseline_path = ROOT / "web/ui-renders/manifest.json"
    if baseline_path.is_file():
        history.update(inventory_history(json.loads(baseline_path.read_text(encoding="utf-8"))))
    previous["addonInventories"] = history
    renderer = renderer_provenance(sim_root, binary)
    stale, inputs, reasons = select_stale(cases, renders, addon_files, renderer, client, previous)
    todo = cases if args.all else stale
    print(f"{len(stale)} of {len(cases)} selected captures stale ({summarize(reasons) or 'none'}); rendering {len(todo)}", flush=True)
    manifest = {"capturedAt": datetime.now(timezone.utc).isoformat(),
                "addonCommit": checked(["git", "rev-parse", "HEAD"], cwd=ROOT),
                "addonFiles": addon_files, "addonInventories": history,
                "client": client, "renderer": renderer, "renders": list(renders.values())}
    if not todo:
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print("Nothing to render", flush=True)
        return
    capture_cases(todo, inputs, binary, sim_root, wow_root, output, manifest, renders, args.keep_going)
    print(f"{len(todo)} captures saved in {output}", flush=True)

if __name__ == "__main__":
    main()
