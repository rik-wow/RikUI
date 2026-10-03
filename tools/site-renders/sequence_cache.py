"""Reuse unchanged sequence pixels with their original authenticated inputs."""
import copy
from dependencies import addon_inputs, recorded_addon_inputs
from fixtures import scenario_script
from provenance import digest, capture_key, scenario_record, tree_inputs, TREE_FIELDS, text_digest

def matches_fixture(frame, script):
    # Path.write_text uses host line endings. Authenticate original LF or CRLF bytes;
    # do not rewrite their recorded hash when reusing a Windows capture.
    return frame.get("fixtureSha256") in {text_digest(script), text_digest(script.replace("\n", "\r\n"))}

def value_case(case, value):
    return {**case, "_captureValue": value}

def reusable_frame(case, value, previous, manifest, modules, addon_files, directory):
    if not previous or scenario_record(previous) != scenario_record(case):
        return None
    old = next((frame for frame in previous.get("frames", []) if frame.get("value") == value), None)
    if not old:
        return None
    inputs = old.get("inputs", previous.get("inputs", {}))
    key = old.get("key", previous.get("key"))
    if key != capture_key(inputs):
        return None
    client = inputs.get("client", {}).get("version")
    if not all(inputs.get("client", {}).get(k) for k in ("version", "foreverCommit", "executableSha256")) or not all(inputs.get("renderer", {}).get(k) for k in ("binary", "patch")):
        return None
    scoped = value_case(case, value)
    script = scenario_script(case, modules, client)
    expected = tree_inputs(scoped, script, addon_files)
    try:
        if recorded_addon_inputs(scoped, {"inputs": inputs}, manifest) != addon_inputs(scoped, addon_files):
            return None
    except RuntimeError:
        return None
    if any(inputs.get(k) != expected.get(k) for k in TREE_FIELDS if k != "addon"):
        return None
    # A sequence's original parent script omitted VALUE, but each actual Lua fixture is also hashed.
    if not matches_fixture(old, scenario_script(case, modules, client, value)):
        return None
    image = directory / old["filename"]
    if not image.is_file() or digest(image) != old.get("sha256"):
        return None
    frame = copy.deepcopy(old)
    frame["inputs"], frame["key"] = copy.deepcopy(inputs), key
    return frame
