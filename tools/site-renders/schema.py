"""Names shared by the capture runner and the gate; no third-party imports so the gate runs anywhere."""
# Tooling whose change means every capture must be rendered again.
FIXTURE_FILES = ("common.lua", "seed.lua", "scenarios.json", "render.py", "validate_capture.py",
                 "wow-ui-sim.patch", "plates.mjs", "schema.py")
# Scenario keys copied into a capture record and compared by the gate.
SCENARIO_KEYS = ("id", "page", "title", "frame", "crop", "lua", "fixtures", "expectText", "assertLua",
                 "delay", "screen", "world", "sequence")
DEFAULT_SCREEN = "2048x1152"

def frames_of(capture):
    """The images a capture record stands for: one, or every frame of a sequence."""
    return capture.get("frames") or [capture]

def frame_id(capture, frame):
    return capture["id"] + ("@" + str(frame["value"]) if "value" in frame and capture.get("frames") else "")
