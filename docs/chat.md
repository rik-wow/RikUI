# Chat

`src/modules/chat/chat.lua` and `src/modules/chat/chat-copy.lua` keep Blizzard's chat frames (the client owns
message routing, tabs, docking and the edit box logic) and clean up what is
around them: the RikUI font, no side buttons, a flat edit box, timestamps, a
copy button on every window and clickable web addresses. Disable the `chat`
module in `/rik config` and reload to get the stock chat back.

`src/modules/chat/chat-copy.lua` is a new TOC entry. **Fully exit and restart the client after
updating**, a `/reload` does not pick up new files.

## One look

`src/modules/chat/chat-skin.lua` (a new TOC entry, so restart the client once) puts the chat
on the same flat style as the bags, tooltips and minimap. Every piece draws
from one palette in `chat.Colors` through one helper, `chat.Flat`: dark fill,
one-pixel border.

- Each chat window sits on a flat bordered panel four pixels larger than the
  text area. The Chat options page can turn the panel off.
- Blizzard's own window background and rounded border are hidden. They are
  hidden rather than faded because `FCF_FadeInChatFrame` fades every shown
  texture back in on hover and skips hidden ones.
- Tabs are flat boxes with the label centred; the selected tab has a gold
  border (post-hook on `FCFTab_UpdateColors`). They still fade out with the
  window.
- The edit box hangs two pixels under the panel with the same left and right
  edge and the same fill and border.
- The copy and padlock buttons are 16-pixel flat buttons side by side in the
  top-right corner, dim until hovered.

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

Tabs stay visible as a flat strip by default (see [Controls](#controls)). With
that option off they are invisible until the cursor rests over the chat window,
then fade in the way Blizzard's tabs always have. A tab with an unread whisper keeps
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

## Lines

`src/modules/chat/chat-lines.lua` (a new TOC entry, so restart the client once) changes what a
line looks like. Each piece has a checkbox on the Chat options page and
applies without a reload.

- **Class-coloured names.** RikUI writes `0` to the client's own
  `chatClassColorOverride` setting, which makes Blizzard colour every sender by
  class. The value you had before is kept in the profile and written back when
  you switch the option off. If class colours were already on, RikUI leaves
  the setting alone in both directions.
- **Short channel tags.** `[Guild]` becomes `[G]`, `[Officer]` `[O]`,
  `[Party]` `[P]`, `[Party Leader]` `[PL]`, `[Raid]` `[R]`, `[Raid Leader]`
  `[RL]`, `[Instance]` `[I]`, `[Instance Leader]` `[IL]` and `[2. Trade - City]`
  `[2]`. The tag stays a clickable channel link. Only the first channel link
  in a line is touched, so a player typing `[Guild]` changes nothing.
- **Mention highlight.** Your character's name, in any letter case and as a
  whole word, turns gold in say, yell, emote, group, guild, officer, channel
  and whisper lines from other players. A soft sound plays at most once every
  five seconds and once per line; whispers keep Blizzard's own sound and get
  no second one. Names inside item or player links are never recoloured.
- **Collapsed repeats.** The same text from the same sender in a numbered
  channel, say, yell or an emote shows once per ten seconds. Guild, group and
  whisper lines and your own lines are never dropped. The window does not
  slide: a line repeated forever still shows every ten seconds.

How it hooks in. Blizzard's handler runs the message filters first, then
builds the sender name, then the channel tag, then calls `AddMessage` with the
event name as the eighth argument. Mentions and repeats are message filters,
the same sanctioned route as the address links; a filter is called once per
window showing the line, which is why both use the line id to tell a second
window from a second message. The tag exists only in the finished text, and
shortening the channel argument in a filter would make the handler drop the
line, so short tags wrap each window's `AddMessage`. The wrapper hands secret
or non-string text to Blizzard untouched and runs the rewrite under `pcall`.
It is the one place the chat module replaces a Blizzard method: it is only
installed while the option is on, and once installed it stays until a reload,
passing text through when the option is off. If a chat error ever names RikUI,
switch short tags off and reload.

## Scrolling, history and typing

`src/modules/chat/chat-scroll.lua`, `src/modules/chat/chat-history.lua`, `src/modules/chat/chat-input.lua` and `src/modules/chat/chat-size.lua` are
new TOC entries, so restart the client once. Each feature has a checkbox on
the Chat options page and applies without a reload.

- **Jump button.** Scroll a window up and a small flat `v` button fades in at
  its bottom-right corner. Lines that arrive while you read are counted on it
  (`v 12`). Click it to return to the newest line. It follows post-hooks on
  the window's own scroll methods, so key bindings keep it in step.
- **Wheel modifiers.** Blizzard's wheel handler scrolls one line. Ctrl-wheel
  jumps to the oldest or newest line and Shift-wheel pages.
- **Scrollback and history.** Every window except the combat log keeps 1000
  lines instead of Blizzard's default. At logout the last 200 readable lines
  of each window are saved per character; after a reload or relog they come
  back at 60% brightness above a `- earlier messages -` line. Secret lines are
  never saved. Links in restored lines still work, except player links whose
  line id the client has forgotten. Restored lines go through Blizzard's own
  `AddMessage`, so they are not re-tagged and not counted as unread. Raising
  the scrollback clears a window, which happens at login before anything is
  restored; lines the client printed earlier in the login are lost. Switching
  the option off deletes what was saved.
- **Arrow-key history.** Up and Down in the edit box recall lines you sent,
  without holding Alt (`SetAltArrowKeyMode(false)`).
- **Sticky channels.** Party, raid, instance, guild, officer, whisper,
  Battle.net whisper and numbered channels stay selected after you send a
  line, by setting `ChatTypeInfo[type].sticky`. Blizzard's values are kept and
  written back when the option is switched off.

## Controls

`src/modules/chat/chat-strip.lua`, `src/modules/chat/chat-tabs.lua` and `src/modules/chat/chat-clicks.lua` are new TOC entries, so
restart the client once. Each feature has a checkbox on the Chat options page
and applies without a reload.

- **Channel strip.** A row of 20x18 flat buttons hangs under the chat panel:
  `S` say, `Y` yell, `P` party, `R` raid, `G` guild, `O` officer, `W` reply and
  one numbered button per joined channel, each lettered in its channel's
  colour. Party and raid show only in a group or raid, guild only in a guild,
  officer only for officers; the row is rebuilt on roster, guild and channel
  notice events. A click opens the edit box on that channel. With the edit box
  already open it switches channel and keeps what you typed. The button of the
  channel you are typing in has the gold border. The strip replaces the chat
  menu button RikUI parks. The main window's edit box, and those of windows
  docked to it, sit under the strip.
- **Visible tabs with unread dots.** Tabs no longer fade out: the selected tab
  rests at full strength and the others at 60%. A docked window that receives
  a line while another tab is showing gets a small gold dot on its tab. A
  whisper makes the dot pulse. Opening the tab clears it. The combat log tab
  never gets a dot.
- **Channel-coloured edit box.** The edit box border takes the colour of the
  channel you are typing in, and the box flashes in that colour for 0.3s when
  the channel changes. A header refresh on the same channel does not flash.
- **Name clicks.** Alt-click a name in chat to invite, Ctrl-click to run a who
  on it. Blizzard's plain click on a name opens a whisper, which also happens
  with Alt or Ctrl held; RikUI closes that edit box again when nothing has
  been typed in it. Shift-click and right-click stay Blizzard's.

How it hooks in. A strip click calls `ChatFrameUtil.OpenChat(nil, window)`,
which activates the right edit box without touching its text and returns it,
then the edit box's own `SetChatType`, `SetChannelTarget` and `UpdateHeader`.
Blizzard's `UpdateHeader` keeps its rules: party becomes instance chat inside
an instance group, and a numbered channel's colour comes from `ChatTypeInfo`.
Reply is `ChatFrameUtil.ReplyTell`. RikUI never sends a chat line. A post-hook
on each edit box's `UpdateHeader` drives the border colour and the selected
button, because every channel change ends there. The target window is the
dock's selected window (`FCFDock_GetSelectedWindow`), falling back to
`ChatFrame1`. Docked windows hide each other, so the strip is parented to the
screen and only anchored to the main window's panel. Dots come from an
`AddMessage` post-hook (the event name is the eighth argument, which is how a
whisper is told apart) and an `OnShow` hook. Name clicks are a post-hook on
`SetItemRef`; invites go through `C_PartyInfo.InviteUnit` and who queries
through `C_FriendList.SendWho` as `n-"Name"`. A client without `OpenChat` gets
no strip and keeps its edit boxes where they were.

## The input bar and the window's motion

`src/modules/chat/chat-editbox.lua` draws the input bar. Readable comes first: the typing area is
an opaque dark field (`0.03, 0.035, 0.045` at 0.97) and nothing light ever spans
it. The channel you are typing on shows in the one-pixel border and in a
two-pixel accent bar on the left edge, which pulses once when the channel
changes and not on every header refresh. Taking the focus fades a one-pixel
glow in around the box in the channel's colour; opening the box fades its art
in. All of that lives on a child frame of RikUI's own (`box.rikArt`), because
Blizzard writes the edit box's own alpha when chat activates and deactivates
(an unfocused IM-style box rests at 0.35), and a tween there would fight it.
`src/modules/chat/chat-strip.lua` only tells it which channel the box is on
(`chat.PaintEditBox(box, color, key, animate)`). The "Edit box border in the
channel's colour" option switches border, accent and glow to the neutral grey.

The window itself: the panel behind it fades in once at login; a tab fades a
soft blue highlight in under the cursor; the selected tab carries a two-pixel
gold underline that fades in when the tab becomes selected, beside its gold
border; the copy and padlock buttons fade to full brightness under the cursor
instead of snapping. RikUI only tweens regions and frames of its own: Blizzard
fades the tabs and its own window textures itself.

Found in game on 2026-09-20: the bar was washed pale and typed text was nearly
unreadable. The old channel flash was a full-size white texture hidden with
`SetAlpha(0)` and then coloured with `SetVertexColor(r, g, b, 1)`. On this
client the fourth component of `SetVertexColor` is the region's alpha, so the
colour write made the flash fully visible again; in Say the colour is white,
and an unfocused box at 0.35 showed it as a pale wash. Colours on regions whose
alpha matters are now written with three components, the full-size flash is
gone, and `tests/widget_stub.lua` models the fourth component as alpha so a
suite can see a texture that was meant to stay invisible.

## Moving and resizing the chat window

The main chat window (`ChatFrame1`, with every tab docked to it) is a member of
RikUI's [frame arrangement](layout.md) like every other frame, from the first
login on. On this client it is an Edit Mode system: Blizzard's tab drag handler
returns early for it, its resize button is hidden, and Edit Mode writes its own
place and size whenever it applies a layout. RikUI takes the window over
instead and Edit Mode has no say in where it is or how big it is.

- Hold the lock key (or Ctrl+Alt+Shift) and click the Chat tag, or use
  `/rik move`: the chat gets the same overlay as every frame. Drag the overlay
  to move it; it snaps and cannot be dropped on another frame.
- Drag the grip in the overlay's bottom right corner to resize it between
  250x120 and 1200x800. The top left corner stays where it is, and the window
  stops flush against the first frame in the way.
- The small padlock in the window's top right corner, left of the copy button,
  is a shortcut to the same lock: click it to unlock only the chat (it turns
  gold with an open shackle and rises above the overlay so it can be clicked
  again), drag it or the first tab to move the window, click it to lock.
  `/rik chat unlock`, `/rik chat lock` and the "Lock the main chat window"
  checkbox do the same. Like every unlock it lasts until you lock it, log out or
  enter combat.
- `/rik chat reset` forgets the saved place and size: the window goes back to
  the default layout's place and the width that fits this screen.
- A [whole-screen layout](layout.md) places and sizes the chat with everything
  else; `/rik layout undo` brings your own size back.

A new profile starts with the Centered layout's place (bottom left) and the
fitted width (413x170 on 16:9). Place and size live in the profile
(`positions.chat`, `chat.size`) and survive reloads and relogs.

How it works: the window hangs by its top left corner inside `RikUIChatHolder`,
and the holder is the layout group. The holder is the size of everything you
see of the chat, not only the message area: `Layouts.ChatFootprint` adds the
panel's border left and right (4), the tabs above (28) and the channel strip
and input bar below (50). So the overlay covers the whole chat, other frames
snap against its tabs and its input bar and cannot be dropped on them, and the
resize grip sizes the whole rectangle while the message area takes what is left
inside it. The saved size (`chat.size`) stays the message area's.

Blizzard also clamps the window to the screen, and Edit Mode sets that clamp's
insets from its own selection box (`EditModeSystemMixin:UpdateClampOffsets`),
which reserves the hidden button column on the left, the tabs and the edit
box. The client then keeps the window that far from the screen edge: it could
not be dragged to the left margin, and it no longer stood where its holder and
overlay were (seen in game on 2026-09-20). `src/modules/chat/chat-move.lua` sets the insets to
zero, switches the window's screen clamping off altogether and answers every
later write of either; the layout engine keeps the chat on screen itself. Zero
insets alone were not enough: in game, a chat dragged flush into the bottom left
corner came back about a margin away from it after a reload, although the saved
position was intact (the stub reproduces the save and the reload correctly, so
the client moved the window, not RikUI). `/rik debug` prints
`Chat place holder=x,y window=x,y offset=dx,dy saved=... clamped=... insets=...`:
the offset should be the footprint's left and bottom (4,50); anything else means
the client holds the window somewhere other than on its holder. A `SetPoint` post-hook on `ChatFrame1` puts the
window back on the holder whenever Edit Mode re-anchors it; post-hooks on
`SetSize`, `SetWidth` and `SetHeight` answer any foreign size with the saved
one ([Edit Mode guard](editmode.md)). A size chosen inside Edit Mode is adopted
as the saved size instead of being fought, so nothing is lost if you do resize
there. Nothing here is protected, so all of it also works in combat except
unlocking, which the arrangement system refuses there.

Windows you have undocked are not Edit Mode systems. They keep Blizzard's own
behaviour: right-click their tab, Unlock Window, drag the tab, Lock Window,
and the client saves their position itself.

How it works: the window is centred on a small RikUI holder, and the holder
is what moves and what the layout saves. Edit Mode re-anchors its systems
whenever a layout is applied; a `SetPoint` post-hook on `ChatFrame1` puts the
window back on the holder. Entering Edit Mode while RikUI holds the window
may show it in the wrong place there or raise a taint complaint; move the
chat with RikUI or with Edit Mode, not both.

## Options

The Chat page of `/rik config` has these settings, all saved per profile. The
four line options are described under [Lines](#lines).

- Lock the main chat window, see above.

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

`tests/chat-lines.test.lua` delivers lines the way the handler does (filters,
then a composed tag and sender, then `AddMessage` with the event name). It
proves: the class colour setting written, restored and re-applied; the guild,
party leader and numbered channel tags; a line without a channel link left
alone; secret and missing text passed through; short tags off without a
reload; the mention highlight in any case, the sound once per line and per
five seconds, longer words and hyperlinks skipped, own lines skipped, a
whisper highlighted silently and mentions off; a repeat dropped, the same line
in a second window kept, another sender kept, the line back after ten seconds,
guild lines and own lines never collapsed and collapsing off; nothing wrapped
or written with both options off; a client without message filters; a disabled
module. Beta check for this part: watch guild and trade chat for a few
minutes, have someone say your name, and confirm `/reload` in combat raises no
chat error.

`tests/chat-nav.test.lua` models a window's scroll offset and its clearing
`SetMaxLines`. It proves: the jump button hidden at the newest line, faded in
once when scrolled up, counting arrivals, returning on click and counting from
zero again; Ctrl-wheel, Shift-wheel and a plain wheel left alone; the button
option off and on; the grip hidden while locked, shown when unlocked, sizing
from the corner within bounds, the size saved and the window re-centred on its
holder with the position saved, hidden again on lock and the size forgotten on
reset; scrollback raised except on the combat log; readable lines saved with
colours and secrets skipped; lines restored dimmed above the separator and not
counted as unread; a second logout keeping original colours; the 200-line cap;
history off deleting the store; arrow keys and sticky types on and off with
Blizzard's values restored; a saved size applied and a damaged one ignored; a
disabled module. Beta check for this part: scroll up in a busy channel and
watch the count, resize and `/reload`, confirm the dimmed lines return, and
open Edit Mode once to see whether the size holds.

`tests/chat-controls.test.lua` fakes `OpenChat`, `ReplyTell`, the edit box
methods, the dock's selected window, the channel list, group and guild state
and the invite and who calls. It proves: the strip's parent, anchor and height;
the buttons for a solo guildless character and for a raiding officer; button
look and channel colours; a click opening the selected window's edit box on the
channel with no text sent; a numbered channel's target; reply; the edit box
border colour and a single flash per real change; the selected button border;
both options off and on, with the edit boxes returning under their panels;
visible tab alphas; a dot for a hidden window, a pulse for a whisper, both
cleared on show, no dot for a shown window or the combat log, and the option
off restoring the fade; Alt-click invite closing an empty whisper box,
Ctrl-click who leaving a box with text open, right clicks and item links
ignored and the option off; a client without `OpenChat` or the invite call; a
disabled module. Beta check for this part: click every strip button in and out
of a group, type half a line and switch channel, get whispered on a background
tab, and Alt-click a name in combat to see whether the invite is allowed.

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
7. Click the padlock in the chat window's corner and drag it: the whole chat
   moves. Click it again to lock, `/reload`, relog: the position is kept. Open and close Edit Mode
   once and note whether the window stays put and whether an error appears.
   `/rik chat reset`, `/reload`: back at Blizzard's position.
8. Change the font size on the Chat page of `/rik config`, reload and
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
