# Totem row

Four fixed 28px element slots (fire, earth, water, air) show cropped icons,
native cooldown sweeps and countdowns. New totems fade in; empty slots are
invisible. Hover shows the native tooltip. Right-click an active slot to dismiss
that totem. Move the row with `/rik move`, key `totems`.

Each click target is a secure button configured out of combat with
`type2=destroytotem` and its `totem-slot`. It remains at a fixed position.
The visual frame is an unprotected sibling, so combat updates can show and hide
it without changing the secure button. Empty positions remain click targets;
right-clicking an empty slot has no totem to dismiss. No insecure OnClick calls
DestroyTotem. Combat login defers construction until combat ends.

Readable GetTotemInfo values decide presence. Secret values pass directly to
the icon/cooldown widgets, with no arithmetic or comparison; exact secrecy on
the target client remains unknown. Failed reads hide visual slots and report
once. Disable the module and reload to remove both visuals and click targets.

Tests cover stable geometry, secure attributes, visual removal and reappearance,
tooltip, secret forwarding, failing reads, combat construction and updates,
disabled and absent API cases. Native behavior is accepted by the user;
no agent-observed client run is claimed.

Source: [Forever secure action handler](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)
and Mainline TotemFrame.lua at the same pinned revision.
