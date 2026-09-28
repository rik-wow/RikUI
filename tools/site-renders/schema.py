"""Names shared by the capture runner and the gate; no third-party imports so the gate runs anywhere."""
# Scenario keys copied into a capture record and compared by the gate.
SCENARIO_KEYS = ("id", "page", "title", "frame", "crop", "lua", "fixtures", "expectText", "assertLua",
                 "delay", "screen", "world", "sequence", "corpus")
# The installer-written quest corpus and road data, staged into the render copy only for scenarios that ask.
CORPUS_DIRS = ("corpus", "roads")
DEFAULT_SCREEN = "2048x1152"

def frames_of(capture):
    """The images a capture record stands for: one, or every frame of a sequence."""
    return capture.get("frames") or [capture]

def frame_id(capture, frame):
    return capture["id"] + ("@" + str(frame["value"]) if "value" in frame and capture.get("frames") else "")
