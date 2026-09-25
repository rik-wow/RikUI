"""Explicit build pins. Unknown build overrides fail instead of reusing old terrain."""
import os

BUILD = os.environ.get("RIKUI_TERRAIN_BUILD", "1.60.1.69913")
CONFIGS = {
    "1.60.1.69913": ("6c0df97e8e481a9a41600e373367c200", "5525ea1ce6668e895569c89c2d6a154c"),
    "1.60.1.70009": ("05215079e3905ef5922ae0b03ffefb73", "9b3c456dbb837d133a026d380c7c13e9"),
}
if BUILD not in CONFIGS:
    raise ValueError("unsupported terrain build: " + BUILD)
IDENTITY = dict(product="wow_classic_beta", edition="Forever", build=BUILD, locale="enUS",
                buildConfig=CONFIGS[BUILD][0], cdnConfig=CONFIGS[BUILD][1])
RUNTIME_IDENTITY = dict(product="forever", build=BUILD, locale="enUS")
PROJECTION_HASHES = {
    "1.60.1.69913": {
        "Map": "fdd6a598e4263ce106371ccb0d2bd8eca6842c4580feabce1f8f8e9cbc27344c",
        "UiMap": "4c5ede52826ef48808aa7c0cd9d63fb3d028df88de1b2041148b164bb42328b2",
    },
    "1.60.1.70009": {
        "Map": "97f83110f7f040868bc804aa1dce14a4691d3b8007abd11f4b4f7746009b6e89",
        "UiMap": "1f4aac70eaac015b1d2d0ea0faf6e3d7fb2cf7afdf45e5bb6772d9b80a72346b",
    },
}
SOURCE_HASHES = dict(PROJECTION_HASHES[BUILD],
    UiMapAssignment="79267e8be8034e47daab14350411b3acc0b1f64e86efc9d821a217497254ca0a")

