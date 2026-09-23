# Proc indicators

The `procoverlay` module replaces stock spell-activation artwork with a compact
gold line at each native overlay position. Left/right cues are vertical; upper,
lower and central cues are horizontal. Multiple native cues remain separate.

The native pool owns show, pulse, fade-out, sound, scale and the overlay-opacity
setting. RikUI changes only texture regions after the native OnEvent callback;
it does not hook object methods or inspect proc spell IDs. Reused overlays
are restyled again when Blizzard reapplies their texture.

The pinned [69913 source](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/SpellActivationOverlay.lua)
provides the container and event path. Event occurrence for a particular
Forever class/spell has not been observed by the agent. Missing containers
are harmless; this is conditional support, not a claim that procs never occur.
Native behavior is accepted under the user's standing policy.

