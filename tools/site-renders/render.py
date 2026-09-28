"""Capture RikUI's Lua output using verified current client inputs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from schema import FIXTURE_FILES
from validate_capture import validate_capture, composite_world, screen_size

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
WORLDS = FIXTURES / "worlds"
KNOWN_STARTUP_ERRORS = (
    'unknown event "GLOBAL_REGION_MOUSE_DOWN"',
    'unknown event "ALERT_AGE_VERIFICATION_RESTRICTED"',
    "attempt to index field 'FrameControlsManager'",
    "generated\\roads/roads.xml",
    "attempt to index field 'ForeverExperiencePreset'",
    "attempt to call method 'GetVariable'",
)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def addon_digest(path):
    data = path.read_bytes()
    if path.suffix.lower() in {".lua", ".xml", ".toc", ".txt", ".svg", ".py", ".md", ".json"}:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()

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

def verify_addon(addon):
    # Tracked and untracked (not ignored) files alike, so a new source file counts before its first commit.
    files = checked(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                     "src", "data", "media", ":(glob)presets/**/*.lua", "RikUI.toc", "Bindings.xml"], cwd=ROOT).splitlines()
    checked_files = {}
    for name in files:
        source, installed = ROOT / name, addon / name
        if not installed.is_file() or addon_digest(source) != addon_digest(installed):
            raise RuntimeError("Renderer addon is stale: " + name)
        checked_files[name] = addon_digest(source)
    return checked_files

def environment(sim_root, wow_root, case):
    env = {**os.environ, "WOW_INSTALL_PATH": str(wow_root), "WOW_SIM_WOW_PATH": str(wow_root),
           "WOW_SIM_ADDONS_PATH": str(sim_root / "addons"),
           "WOW_SIM_ADDONS_TXT": str(sim_root / "AddOns.txt"),
           "WOW_SIM_WTF_PATH": str(sim_root / "WTF"), "WOW_SIM_WTF_ACCOUNT": "RENDER",
           "WOW_SIM_WTF_REALM": "Preview", "WOW_SIM_WTF_CHARACTER": "Rikui"}
    # A world scenario renders RikUI alone on a transparent layer; the plate goes underneath afterwards.
    env["WOW_SIM_TRANSPARENT_BACKGROUND" if case.get("world") else "WOW_SIM_PLAIN_BACKGROUND"] = "1"
    return env

def lua_literal(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'

def scenario_script(case, common, value=None):
    fixtures = "\n".join(case.get("fixtures", []))
    body = case.get("lua", "")
    # The setting is applied first, so the scenario composes its frame the way a player would see it.
    if value is not None:
        body = case["sequence"]["apply"].replace("VALUE", lua_literal(value)) + "\n" + body
    checks = case.get("assertLua", "") + "\nRikRenderCheck(" + case["frame"] + ")\n"
    return common + "\n" + fixtures + "\n" + body + "\nC_Timer.After(0, function()\n" + checks + "end)\n"

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

def plate_record(case):
    """The world plate a scenario composites over, with the provenance written by plates.mjs."""
    name = case["world"]["plate"]
    record = json.loads((WORLDS / (name + ".json")).read_text(encoding="utf-8"))
    image = WORLDS / record["file"]
    if not image.is_file() or digest(image) != record["sha256"]:
        raise RuntimeError("World plate does not match its record: " + name)
    return {"plate": name, "sha256": record["sha256"], "appCommit": record["app"]["commit"],
            "camera": record["camera"], "captured": record["capturedAt"]}, image

def render_frame(case, binary, env, output, common, value=None, stem=None):
    """Render one image for a scenario (or one frame of a sequence) and validate it."""
    stem = stem or case["id"]
    script, log = output / (stem + ".lua"), output / (stem + ".log")
    image = output / (stem + ".webp")
    layer = output / (stem + ".layer.webp") if case.get("world") else image
    script.write_text(scenario_script(case, common, value), encoding="utf-8")
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
        plate, plate_image = plate_record(case)
        composite_world(layer, plate_image, case, image)
    dimensions = case["crop"].split("+", 1)[0].split("x")
    frame = {"diagnostics": diagnostics, "sha256": digest(image), "bytes": image.stat().st_size,
             "fixtureSha256": digest(script), "filename": image.name,
             "width": int(dimensions[0]), "height": int(dimensions[1])}
    if plate:
        frame["plate"] = plate  # provenance of the world underneath; the scenario's own "world" key stays as written
    return frame

def render_case(case, binary, env, output, common):
    if not case.get("sequence"):
        return {**case, **render_frame(case, binary, env, output, common)}
    sequence = case["sequence"]
    frames = []
    for value in sequence["values"]:
        frame = render_frame(case, binary, env, output, common, value, case["id"] + "@" + str(value))
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

def create_manifest(sim_root, binary, client, addon_files):
    manifest = {"capturedAt": datetime.now(timezone.utc).isoformat(),
                "addonCommit": checked(["git", "rev-parse", "HEAD"], cwd=ROOT),
                "addonFiles": addon_files, "client": client,
                "fixtureFiles": {name: digest(FIXTURES / name) for name in FIXTURE_FILES},
                "rendererCommit": checked(["git", "rev-parse", "HEAD"], cwd=sim_root / "source"),
                "rendererBinarySha256": digest(binary), "rendererPatchSha256": digest(FIXTURES / "wow-ui-sim.patch"),
                "renders": []}
    provenance = {key: manifest[key] for key in ("addonFiles", "fixtureFiles", "rendererBinarySha256", "rendererCommit")}
    provenance["client"] = {key: client[key] for key in ("version", "foreverCommit", "executableSha256", "cache")}
    manifest["generation"] = hashlib.sha256(json.dumps(provenance, sort_keys=True).encode()).hexdigest()
    return manifest

def capture_cases(cases, binary, sim_root, wow_root, output, manifest):
    manifest_path = output / "manifest.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    renders = {r["id"]: r for r in previous.get("renders", [])}
    common = (FIXTURES / "common.lua").read_text(encoding="utf-8")
    for case in cases:
        capture = render_case(case, binary, environment(sim_root, wow_root, case), output, common)
        capture.update(client=manifest["client"], seedSha256=digest(FIXTURES / "seed.lua"),
                       generation=manifest["generation"])
        renders[case["id"]] = capture
        manifest["renders"] = list(renders.values())
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print("Rendered " + case["id"] + (f" ({len(capture['frames'])} frames)" if capture.get("frames") else ""), flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim-root", type=Path, required=True)
    parser.add_argument("--wow-root", type=Path, required=True)
    parser.add_argument("--only", default="", help="Comma-separated scenario IDs or page slugs")
    args = parser.parse_args()
    sim_root, wow_root = args.sim_root.resolve(), args.wow_root.resolve()
    binary = sim_root / "source/target/debug/wow-sim.exe"
    if not binary.is_file():
        raise RuntimeError("Build wow-ui-sim with gui,client-wowforever first")
    client = verify_client(sim_root, wow_root)
    print("Verified current Forever client " + client["version"], flush=True)
    addon_files = verify_addon(sim_root / "addons/RikUI")
    install_seed(sim_root)
    output = ROOT / "dist/ui-renders"
    output.mkdir(parents=True, exist_ok=True)
    scenarios = json.loads((FIXTURES / "scenarios.json").read_text(encoding="utf-8"))
    selected = set(args.only.split(",")) if args.only else None
    cases = [s for s in scenarios if not selected or s["id"] in selected or s["page"] in selected]
    if not cases:
        raise RuntimeError("No matching render scenarios")
    capture_cases(cases, binary, sim_root, wow_root, output,
                  create_manifest(sim_root, binary, client, addon_files))
    print(f"{len(cases)} captures saved in {output}", flush=True)

if __name__ == "__main__":
    main()
