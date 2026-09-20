# Social toasts

`src/modules/toasts/toasts.lua` gives the social toasts the flat RikUI look: the Battle.net
"friend came online" toast, the play-time alert, the shard transfer notice and
the two voice chat prompts. Disable the `toasts` module in `/rik config` and
reload for the stock toasts.

These are not covered by [alert toasts](alerts.md). They are
`ContainedAlertFrame`s shown through `ChatAlertFrame`, so they never pass
`AlertFrame_ShowNewAlert`, the hook that module rides on.

## What you see

A flat dark panel with a one-pixel edge. The icon, where a toast has one, is
cropped and framed one pixel outside. The text uses the RikUI typeface at
Blizzard's sizes and keeps Blizzard's colours. The voice prompt's Accept button
is flat through [window controls](controls.md).

The fade-in, the wait and the fade-out are Blizzard's own animation groups on
`SocialToastTemplate`. RikUI adds no tween: a second alpha animation on the
same frame would fight Blizzard's.

## Targets

`BNToastFrame`, `TimeAlertFrame`, `ShardTransferImminentFrame`,
`VoiceChatPromptActivateChannel` and `VoiceChatChannelActivatedNotification`.
One the client lacks is skipped. `QuickJoinToastButton` is not a target: the
[chat module](chat.md) parks it with the other chat side buttons.

## How it works

`SocialToastTemplate` inherits `BackdropTemplate` with the
`BACKDROP_TOAST_12_12` backdrop. The backdrop mixin builds nine keyed pieces
(`Center`, four edges, four corners) and recolours them through vertex colour,
never through `SetAlpha`, so fading them lasts. It is repeated on every show in
case a size change rebuilds a piece. The glow lives on a frame only reachable
by its global name, `<toast>GlowFrame`; Blizzard animates its alpha, so its
texture is emptied, not faded.

Fill, edge, icon crop and typeface are written once per toast. The strings are
listed before the fill exists because `GetRegions` also returns regions an
addon made.

Nothing is moved, resized, reparented, shown, hidden or given a new script, and
Blizzard's click handling, tooltip, timing and stacking are untouched. A toast
that refuses the skin is reported once as `Toasts skin <name>`, not tried again
and still shown.

## Diagnostics

`/rik debug` prints `Toasts hooked=<n> skinned=<n> failed=<n>`.

## Verification

`tests/toasts.test.lua` fakes three toasts with the 69913 keys and Blizzard's
`animIn`. It proves: nothing before the first show; the nine pieces faded, fill
and edge added; the glow blanked; the icon cropped and framed outside; typeface
with size and colour kept; Blizzard's animation played and no RikUI tween,
point or size; restored art removed on the next show with one fill; a text-only
toast; the voice prompt's icon and flat button; a missing toast skipped; the
debug line; one failure report with the toast still shown; the disabled module.
The suite was seen red before the module existed.

The stub cannot show how it looks. Beta checklist:

1. Fully restart the client (new TOC entry). Have a Battle.net friend log in or
   out: the toast should be a flat panel with a cropped icon and readable text,
   fading in and out as before.
2. Click the toast: it should still open the whisper or friends list.
3. If voice chat is available, join a channel with voice and check the prompt
   and its Accept button.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [SocialToast.xml: SocialToastTemplate, its backdropInfo, animation groups, glow frame and close button](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SocialToast/SocialToast.xml)
- [BNet.xml: BNToastFrame's IconTexture and lines, TimeAlertFrame's Text](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_BNet/BNet.xml)
- [VoiceChatPrompt.xml: Icon, Text, Text2 and AcceptButton](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Channels/Mainline/VoiceChatPrompt.xml)
