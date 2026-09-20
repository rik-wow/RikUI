# Chat bubbles

`src/modules/chatbubbles/chatbubbles.lua` gives the speech bubbles over characters and NPCs the flat
RikUI look. The engine still creates, places, sizes and removes every bubble.
Disable the `chatbubbles` module in `/rik config` and reload for the stock
bubbles.

## What you see

A flat dark panel with a one-pixel edge around the text, 10px of padding, no
rounded parchment and no tail. The text uses the RikUI font with an outline at
Blizzard's size and keeps the colour of its chat type (white say, red yell,
blue party). A bubble fades in over 0.15s, also when the engine reuses it for
the next line.

Bubbles inside dungeons, raids and battlegrounds are forbidden to addons and
stay stock. That is a client rule, not a choice.

## How it works

- Font. `ChatBubbleTemplate`'s `String` inherits the `ChatBubbleFont` object.
  The module writes the RikUI font to that object once at login, at the size
  the object reports (14 when it reports none). No bubble string is written,
  so the colour the client sets per message survives.
- Finding bubbles. There is no event for a bubble. It appears a frame or more
  after its chat event, so `CHAT_MSG_SAY`, `YELL`, `PARTY`, `PARTY_LEADER`,
  `MONSTER_SAY`, `MONSTER_YELL` and `MONSTER_PARTY` each open a one-second
  burst in which `C_ChatBubbles.GetAllChatBubbles()` is read every 0.1s. With
  nobody talking nothing runs.
- Skinning. The list call leaves forbidden bubbles out; each bubble and its
  first child are checked with `IsForbidden` anyway. On the child, the nine
  `NineSlicePanelTemplate` pieces and `Tail` are faded, a fill and four edge
  lines are added 6px inside the frame (the template reaches 16px past the
  string), and a fade tween is created and replayed from an `OnShow` hook.
- Once. A bubble is visited one time, kept in a weak table. A skin that raises
  prints one `Chat bubbles skin: <reason>` line and that bubble is not retried.

## Not covered

Bubble position, size, word wrap and lifetime are the engine's. There is no
tail, so with several speakers close together you match a bubble to its
speaker by position alone.

## Diagnostics

`/rik debug` prints `Chat bubbles skinned=<n> font=<true|false>`.

## Verification

`tests/chatbubbles.test.lua` builds fake bubbles with the 69913 template keys
and drives the scanner's `OnUpdate` by hand. It proves: the font object
restyled at Blizzard's size; no scan before a chat event; the 0.1s interval;
the faded art with an inset fill and edge; the fade-in with the string
unwritten; one skin per bubble; the fade replayed on a reused bubble; a
forbidden bubble untouched; the burst ending after a second and restarting on
a monster yell; the debug line; a refused write reported once and not retried;
a bubble missing art keys; a bubble without a child; a client without the
bubble API; the disabled module.

The stub cannot settle these: whether the template's piece keys match the
engine-made bubbles on 69913, whether a font object write reaches bubbles
already created, whether the engine's own alpha fade fights the tween, and
whether 6px matches the visible art. Beta checklist:

1. Fully restart the client (new TOC entry). `/say test` in a city: flat panel,
   RikUI font, white text, fade-in.
2. `/yell test` and a party message: red and blue text.
3. Stand near a talking NPC (a city crier or a quest NPC with say lines).
4. Enter a dungeon and have someone speak: the stock bubble and no error.
5. `/rik debug` should print the `Chat bubbles` line with a growing count.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_ChatBubble.toc: no game type gating, not load on demand](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatBubble/Blizzard_ChatBubble.toc)
- [ChatBubbleTemplates.xml: the NineSlice panel, String on ChatBubbleFont, Tail and the 16px inset](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatBubble/ChatBubbleTemplates.xml)
