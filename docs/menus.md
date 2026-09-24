# Menus

Context menus, dropdown lists and submenus use flat dark backings with a
one-pixel edge and a short entrance fade. Rows use the bundled RikUI typeface;
check marks, radio marks and submenu arrows use flat assets. Native disabled,
selection and class colours, row actions, sizing and scrolling remain native.

The Menu compositor forbids SetFont and creating regions on its frames.
RikUI instead copies each source FontObject into a private font and binds it
with SetFontObject, which the pinned compositor permits. It replaces existing
selection textures and named arrow/highlight regions without adding native
fields, input scripts or method hooks. Generic Blizzard font objects are never
modified. Compositor reset restores the original objects for their next user.

An owned backing frame is pooled under each open menu. Its bounded 0.1-second
refresh covers regenerated rows while open. Hide stops its fade, clears the
menu reference and returns the backing to the pool. Concurrent submenus have
separate backings. Closed dropdown buttons belong to the controls module.

Missing variant glyphs retain native art; a refused operation prints its actual
error once as `Menus rows client limit`. No failure is invented from the stub.
Native actions such as Set Focus remain Blizzard handlers; native acceptance
is supplied by the user, not an agent-observed client test.

Tests exercise the compositor bans, private-font reuse, source font preservation,
disabled colour, pooled reset, combat click preservation, refusal reporting,
backing pooling and module disabling. `/rik debug` reports shown/active/pooled menus.

Source: pinned Forever [Compositor.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Menu/Compositor.lua),
MenuTemplates.lua and Mainline/MenuVariants.lua at the same revision.
