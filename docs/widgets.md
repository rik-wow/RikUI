# UI widgets

`src/modules/widgets/widgets.lua` gives the bars Blizzard's UI widget system draws the flat RikUI
frame: the score and resource bars at the top of the screen in battlegrounds,
capture bars at world PvP towers and flags, and progress bars in scripted
events. The widgets stay Blizzard's. Where they appear, what they show and how
they fill is untouched. Disable the `widgets` module in `/rik config` and
reload for the stock look.

## What you see

Each bar sits on a flat dark backing with a one-pixel edge in place of the
metal frame art, and its labels use the RikUI typeface at Blizzard's sizes and
colours. The fill keeps Blizzard's texture and colour, because that colour is
the information: blue and red for the factions, yellow for a neutral point. The
spark, the pulsing state glow and the capture bar's direction arrows stay too.

## How it works

Three widget types are covered, each through a post-hook on its mixin's
`Setup`, which Blizzard runs on every update of the widget:

| Mixin | Art faded | Flat backing on |
|-------|-----------|-----------------|
| `UIWidgetTemplateStatusBarMixin` | `Bar.BGLeft/BGRight/BGCenter`, `Bar.BorderLeft/Right/Center`, `Bar.BackgroundGlow` | `Bar` |
| `UIWidgetTemplateDoubleStatusBarMixin` | `BG`, `BorderLeft/Right/Center` on `LeftBar` and `RightBar` | each of the two bars |
| `UIWidgetTemplateCaptureBarMixin` | `BarBackground`, `LeftLine`, `RightLine`, `Divider` | the span from `LeftBar` to `RightBar` |

On every `Setup` the art is faded again and the typeface is written again,
because `Setup` re-applies the labels' font objects. The fill and edge are made
once per frame.

A capture bar's zones are textures on the widget itself, not status bars. Its
fill is a texture on the widget anchored from `LeftBar`'s top left to
`RightBar`'s bottom right, and its edge lines frame an empty child frame
anchored the same way.

A frame copies its mixin's functions when it is created. The hooks go in at
login, so a widget the client created before login keeps the stock `Setup`
until a reload. In practice that is a login inside a battleground.

Nothing is moved, shown or hidden, no value, colour or fill texture is read or
written, and none of the writes is protected, so a widget that appears in
combat is safe. A skin that raises prints one `Widgets skin: <reason>` line and
that frame is left alone afterwards.

## Not covered

The other widget types (icon and text rows, state icons, spell displays, text
with state, the scenario headers) keep Blizzard's look. Most are plain text or
icons with no frame art.

## Diagnostics

`/rik debug` prints `Widgets hooked=<n> skinned=<n> failed=<n>`. `hooked` is 3
when all three mixins exist.

## Verification

`tests/widgets.test.lua` builds the three mixins with a `Setup` that restores
label fonts, and frames that copy `Setup` at creation. It proves: Blizzard's
`Setup` still running; the status bar's art faded with a flat fill and edge;
fill texture, colour, spark and value unwritten; both labels in the typeface
with size and colour kept; one fill across updates with restored art faded and
the typeface rewritten; both sides of a double bar; the capture bar's art faded
with zones and glows kept; its fill and edge spanning the two zones; nothing
moved or printed; a widget in combat; the debug line; a widget made before the
hook staying stock; a refused write reported once and not retried with
Blizzard's `Setup` still running; a widget without a bar; a missing mixin; the
disabled module.

The stub cannot settle these: whether post-hooking the mixin tables taints
widget updates, whether the status bar's `Bar` bounds match its visible fill,
and whether the capture bar zones' atlas art has transparent margins that leave
the edge floating. Beta checklist:

1. Fully restart the client (new TOC entry). Enter a battleground: the score
   bars at the top should be flat with the RikUI typeface and faction colours.
2. Stand on a capture point or a world PvP tower: flat frame around the zones,
   spark moving, arrows showing direction.
3. `/reload` inside the battleground and check the bars again.
4. `/rik debug` should print `Widgets hooked=3` with `failed=0`.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_UIWidgetTemplateStatusBar.xml and .lua: the Bar keys, Setup and the state glow](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateStatusBar.xml)
- [Blizzard_UIWidgetTemplateDoubleStatusBar.xml: the two status bars and their border pieces](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateDoubleStatusBar.xml)
- [Blizzard_UIWidgetTemplateCaptureBar.xml and .lua: zone textures, frame art, glows and arrows](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIWidgets/Blizzard_UIWidgetTemplateCaptureBar.xml)
