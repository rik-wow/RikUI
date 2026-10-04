"""Current navigation identity from verified acquisition; no historical defaults.

RIKUI_CURRENT_INPUTS names the freshly acquired current-inputs.json receipt.
Orchestration must re-resolve publisher/client metadata before each operation.
Pure decoder fixtures may import without a receipt; source admission cannot.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import forever_inputs

if os.environ.get("RIKUI_TERRAIN_BUILD"):
    raise ValueError("Historical build override removed; acquire current inputs and set RIKUI_CURRENT_INPUTS")

RECEIPT_PATH = os.environ.get("RIKUI_CURRENT_INPUTS")
RECEIPT = {}
IDENTITY = {}
SOURCE_HASHES = {}
WDT_PINS = {}
TILE_WORKLIST_SHA256 = ""
LIQUID_KINDS = {}


def checked(path, expected):
    path = forever_inputs.regular(path)
    if not re.fullmatch("[0-9a-f]{64}", expected):
        raise ValueError("Invalid current input digest")
    if path.stat().st_size > 16*1024*1024:
        raise ValueError("Current metadata byte bound")
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError("Current input hash mismatch: " + str(path))
    return raw


if RECEIPT_PATH:
    raw = forever_inputs.read_metadata(RECEIPT_PATH)
    RECEIPT = json.loads(raw)
    if RECEIPT.get("format") != "rikui-current-navigation-inputs-v1":
        raise ValueError("Unsupported current navigation receipt")
    resolution = forever_inputs.validate_resolution(RECEIPT["resolution"])
    IDENTITY = RECEIPT["identity"]
    if IDENTITY != dict(resolution["inputs"]["identity"],locale="enUS"):
        raise ValueError("Navigation identity differs from current resolution")
    directory = Path(RECEIPT["sourceDirectory"])
    for name in ("Map","UiMap","UiMapAssignment","LiquidType","QuestV2"):
        digest = RECEIPT["sourceHashes"][name]
        checked(directory/(name+"-"+IDENTITY["build"]+".csv"),digest)
        SOURCE_HASHES[name] = digest
    TILE_WORKLIST_SHA256 = RECEIPT["tileWorklistSHA256"]
    checked(directory/"all-projected-world-tile-worklist.csv",TILE_WORKLIST_SHA256)
    LIQUID_KINDS = json.loads(checked(directory/"liquid-kinds.json",RECEIPT["liquidKindsSHA256"]))["kinds"]
    if not LIQUID_KINDS or any(not str(key).isdigit() or value not in ("water","ocean","magma","slime","unknown")
                               for key,value in LIQUID_KINDS.items()):
        raise ValueError("Unsupported current liquid classification")
    proof=RECEIPT["m2Proof"]
    document=json.loads(checked(proof["path"],proof["sha256"]))
    if (document.get("format")!="rikui-current-m2-proof-v1"
            or document.get("sourceProfileSHA256")!=RECEIPT["profileSHA256"]
            or not isinstance(document.get("records"),list) or not 0<len(document["records"])<=32768):
        raise ValueError("Current model proof identity/inventory")
    WDT_PINS = {int(world):(int(value[0]),value[1]) for world,value in RECEIPT["topology"].items()}
    if not WDT_PINS or len(WDT_PINS)>256:
        raise ValueError("Unsupported current topology inventory")

BUILD = IDENTITY.get("build","")
RUNTIME_IDENTITY = dict(product="forever",build=BUILD,locale="enUS") if IDENTITY else {}


def require_current():
    if not RECEIPT:
        raise ValueError("Current acquisition receipt required: set RIKUI_CURRENT_INPUTS")
    return RECEIPT
