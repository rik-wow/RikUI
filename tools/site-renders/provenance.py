"""What a capture's pixels depend on, recorded per capture and rebuilt by the gate; standard library only.

Tree inputs can be recomputed from the repository at any time: the script, the character seed, the
addon files, the validator, and for a world capture its plate and the compositing code. Environment
inputs (simulator, client, installer-written corpus) retain each capture's original provenance.
Unrelated historical captures are not relabeled when another surface is refreshed."""
from dependencies import addon_inputs
import hashlib
import json
from pathlib import Path
from schema import SCENARIO_KEYS

FIXTURES = Path(__file__).resolve().parent
WORLDS = FIXTURES / "worlds"
TEXT_SUFFIXES = {".lua", ".xml", ".toc", ".txt", ".svg", ".py", ".md", ".json"}
TREE_FIELDS = ("script", "seed", "addon", "validator", "world")
ENVIRONMENT_FIELDS = ("renderer", "client")

def digest(path, normalized=False):
    data = Path(path).read_bytes()
    if normalized and Path(path).suffix.lower() in TEXT_SUFFIXES:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()

def text_digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def json_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode("utf-8")).hexdigest()

def plate_record(name):
    return json.loads((WORLDS / (name + ".json")).read_text(encoding="utf-8"))

def tree_inputs(case, script, addon_files):
    """The inputs the gate can rebuild: `script` is the capture's Lua text, `addon_files` the addon inventory digests."""
    addon_files = addon_inputs(case, addon_files)
    inputs = {"script": text_digest(script), "seed": digest(FIXTURES / "seed.lua"),
              "addon": json_digest(addon_files), "addonFiles": addon_files,
              "validator": digest(FIXTURES / "validate_capture.py")}
    if case.get("world"):
        name = case["world"]["plate"]
        inputs["world"] = {"plate": name, "sha256": plate_record(name)["sha256"],
                           "composite": digest(FIXTURES / "composite.py")}
    return inputs

def environment_inputs(renderer, client, corpus=None):
    inputs = {"renderer": renderer, "client": {key: client[key] for key in ("version", "foreverCommit", "executableSha256")}}
    if corpus is not None:
        inputs["corpus"] = corpus
    return inputs

def capture_key(inputs):
    return json_digest(inputs)

def scenario_record(case):
    return {key: case[key] for key in SCENARIO_KEYS if key in case}

def stale_reasons(case, capture, inputs):
    """Why a recorded capture no longer stands for the scenario: differing input names, or 'scenario'."""
    if not capture:
        return ["missing"]
    reasons = [name for name in sorted(set(inputs) | set(capture.get("inputs", {})))
               if capture.get("inputs", {}).get(name) != inputs.get(name)]
    if any(capture.get(key) != value for key, value in scenario_record(case).items()) \
            or any(key in capture for key in SCENARIO_KEYS if key not in case):
        reasons.append("scenario")
    return reasons
