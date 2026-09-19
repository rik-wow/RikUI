# Chat

`chat.lua` and `chat-copy.lua` keep Blizzard's chat frames (the client owns
message routing, tabs, docking and the edit box logic) and clean up what is
around them: the RikUI font, no side buttons, a flat edit box, timestamps, a
copy button on every window and clickable web addresses. Disable the `chat`
module in `/rik config` and reload to get the stock chat back.

`chat-copy.lua` is a new TOC entry. **Fully exit and restart the client after
updating**, a `/reload` does not pick up new files.

## What you see

Every chat window uses the RikUI font without an outline, with a one-pixel
shadow, at the profile size (14 by default). The edit box is a flat dark bar
with a one-pixel border, docked four pixels under its chat window across the
full width; the rounded Blizzard art and its focus glow are gone. The header
(`Say:`, `Party:`) and the text you type use the same font.

The button column beside the chat window is gone: the chat menu button, the
minimize button, the channel button, the voice deafen and mute buttons, the
text-to-speech button and the quick-join toast button. So are the scroll bar
and the scroll-to-bottom arrow; the mouse wheel still scrolls. Slash commands
(`/p`, `/g`, `/w name`) replace the chat menu, and the social and channel
windows keep their key bindings.

Tabs are invisible until the cursor rests over the chat window, then fade in
the way Blizzard's tabs always have. A tab with an unread whisper keeps
flashing at full strength. The tab art is hidden; the labels use the RikUI
font.

Chat lines carry a 24-hour `HH:MM` timestamp. If you already picked another
format in Blizzard's chat options, that format stays.

A small two-square button sits in the top-right corner of every chat window,
dim until hovered. Clicking it opens a window with that chat window's current
lines as plain text, already selected: press Ctrl+C, then Escape. Icons,
colours and link codes are stripped, so `[Bob]` and `[Thunderfury]` stay as
bracketed text.

Web addresses (`http://`, `https://` or a bare `www.`) in say, yell, emote,
party, raid, instance, guild, officer, whisper, Battle.net whisper, channel,
community and system messages turn into light-blue links. Clicking one opens
the same window holding just the address, selected. The client cannot open a
browser for addons, so copying is the whole feature.

## Options

The Chat page of `/rik config` has two settings, both saved per profile:

- Font size, 10 to 24. The change goes through Blizzard's own
  `FCF_SetChatWindowFontSize`, so the client saves it with the chat window
  too. Changing the size from a tab's right-click menu lands in the profile
  the same way.
- Timestamps on chat lines. Off writes `none` to `showTimestamps`; on writes
  `%H:%M ` unless a format is already set.

## Hidden frames

These are parked with `RikUI.Hide.Frame(frame, false)` whenever they exist.
Parent writes are protected, so at a combat login they wait in the combat
queue until `PLAYER_REGEN_ENABLED`; everything else here (fonts, alpha,
anchors) is unprotected and applies at once.

- Per chat window: `buttonFrame` (`ChatFrameNButtonFrame`, which holds the
  minimize button and, on window 1, `ChatFrameMenuButton`), `ScrollBar` and
  `ScrollToBottomButton`
- `ChatFrameChannelButton`, `ChatFrameToggleVoiceDeafenButton`,
  `ChatFrameToggleVoiceMuteButton`, `TextToSpeechButtonFrame`,
  `QuickJoinToastButton`

The edit box textures (`ChatFrameNEditBoxLeft`, `Mid`, `Right` and the
`focusLeft`, `focusMid`, `focusRight` keys) and the nine tab art textures are
set to alpha zero instead. Blizzard toggles the focus art with `SetShown` on
every activation, so a hide would not last; an alpha write does.

## How the links work

The 69913 client has two extension points that make this safe:

- `ChatFrameUtil.AddMessageEventFilter(event, callback)` (the old
  `ChatFrame_AddMessageEventFilter` is an alias in
  `Blizzard_DeprecatedChatInfo`). The registry only calls an addon filter when
  `canaccessvalue(...)` holds for every argument, so secret messages never
  reach RikUI; the filter re-checks anyway. A filter returns the discard flag,
  then the whole replacement argument list. RikUI returns only `false` when a
  message has no address, which keeps the arguments untouched.
- The `addon` hyperlink type. `SetItemRef` routes every link through
  `LinkUtil.ProcessLink`; the `addon` handler fires the `SetItemRef` event on
  `EventRegistry` and reports the link as handled, so the item tooltip never
  opens. RikUI's links are `|Haddon:RikUI:<address>|h[<address>]|h` and its
  callback ignores every other addon's prefix.

Existing hyperlinks in a message pass through whole; only the text between
them is searched. Trailing `. , ; : ! ? ) ]` stays outside the link. The
patterns start with `%f[%w]` rather than `%f[%S]`: Lua treats the start of a
string as a NUL byte, which `%S` matches, so `%f[%S]` never fires on an
address that opens the message.

## Secret rules

The copy window reads `GetNumMessages` and `GetMessageInfo` under `pcall`. A
failure prints one `Chat copy` line and leaves the box empty. A secret line
is skipped without printing. Whisper tabs can carry a secret name; the window
title falls back to the frame name then.

## Diagnostics

`/rik debug` prints `Chat frames=<n> parked=<n> links=<bool>` and the secrecy
of `C_CVar.GetCVar("showTimestamps")`. A missing filter registry prints one
`Chat links` line and a missing `EventRegistry` one `Chat clicks` line; the
rest of the module still applies.

## Verification

`tests/chat.test.lua` runs against `tests/chat_stub.lua`, a fake of the 69913
chat surface: three chat windows with their scroll bar, scroll-to-bottom
button, button frame, edit box art and tab art, the five side buttons,
`ChatFontNormal`, `FCF_SetChatWindowFontSize`, `FCFTab_UpdateAlpha` with the
tab alpha globals, a filter registry that skips secret arguments, an
`EventRegistry`, a `SetItemRef` with the `addon` route and an item tooltip
recorder, and the `showTimestamps` setting. It proves: fonts on frames, edit
boxes and `ChatFontNormal` at the profile size; a Blizzard size change kept
in the profile; the size setter's range; the fourteen parked frames with the
chat windows and dock left alone; invisible edit box art, the flat skin and
the dock anchors; zeroed tab alphas with alerting tabs untouched; the copy
button, plain-text lines, the skipped secret line, selection, Escape, the
close button and a failing read reported once; link wrapping, trailing
punctuation, existing hyperlinks, argument pass-through, secret messages;
the link click opening the address without the item tooltip, other addons'
links ignored and item links still reaching the tooltip; timestamps on, off
and a player's own format left alone; the options page; the debug line; a
combat login queueing the parent writes; missing link APIs; a client without
`ChatFrame1`; a disabled module touching nothing.

The stub cannot show how the flat edit box renders, when the tabs fade, or
whether the voice and text-to-speech buttons exist on Forever. Beta
checklist on the Warrior, after a full client restart:

1. The chat window should show the RikUI font, no button column on its left
   and no scroll bar. Run `/rik debug` and confirm
   `Chat frames=10 parked=<n> links=true` with no `Chat ...` error line.
   Note the parked count: 35 means every side button exists.
2. Press Enter: a flat bar under the chat window, no rounded art, no glow.
   Type `/s www.example.com` and send it. The line should start with a
   timestamp and the address should be light blue.
3. Click the address: a box with the address selected, no item tooltip.
   Ctrl+C, Escape. Shift-click an item link in chat: the item tooltip should
   still open.
4. Move the cursor off the chat window and wait: the tabs should fade out
   completely. Rest it over the window: they fade back in.
5. Click the two-square button in the chat window's top-right corner: the
   recent lines as plain text, selected. Scroll the box with the wheel.
6. Enter combat and `/reload`: no "action blocked" error; the button column
   disappears when combat ends.
7. Change the font size on the Chat page of `/rik config`, reload and
   confirm it stuck. Disable the module, reload and confirm the stock chat
   returns.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [FloatingChatFrame.xml: the chat window template, its parent keys, the tab template and ChatFrameMenuButton](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.xml)
- [FloatingChatFrame.lua: FCF_SetChatWindowFontSize, the tab alpha globals, FCFTab_UpdateAlpha and the fade loop](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua)
- [ChatFrameEditBox.xml: the edit box art and focus textures](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameEditBox.xml)
- [ChatFrameEditBoxOverrides.lua: SetFocusRegionsShown](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/ChatFrameEditBoxOverrides.lua)
- [ChatFrameFilters.lua: the filter registry, canaccessvalue and the return contract](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua)
- [ChatFrameUtil.lua: GetTimestampFormat and PopOutChat's GetMessageInfo loop](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua)
- [Deprecated_ChatFrame.lua: the ChatFrame_AddMessageEventFilter alias](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_DeprecatedChatInfo/Deprecated_ChatFrame.lua)
- [ItemRef.lua: SetItemRef through LinkUtil.ProcessLink](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ItemRef.lua)
- [ItemRefHandlersShared.lua: the addon link handler](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua)
- [LinkUtil.lua: link types and handler dispatch](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/LinkUtil.lua)
