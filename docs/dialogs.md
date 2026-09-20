# Small dialogs

`dialogs.lua` gives the small dialogs the same flat look as the
[static popups](popups.md): the ready check, the role poll, the stack split
box, the queue-ready dialogs, the ticket status box, the name autocomplete
list, old-style dropdown lists, the colour picker, the add-friend box and the
report dialog. Disable the `dialogs` module in `/rik config` and reload for
the stock look.

It is its own module and not part of `popups` on purpose. The popup skin is
the first suspect if item deletion ever gets blocked, and switching it off
should not take the ready check with it.

## What you see

A flat dark panel with a one-pixel edge and a 0.15s fade-in. Titles are gold
in the RikUI font. The dialog's own text takes the RikUI typeface at
Blizzard's size and keeps Blizzard's colour. Close buttons are the flat `x`
from the [panel skin](panels.md) and push buttons, edit boxes, sliders and
check boxes come from [window controls](controls.md).

## Targets

| Dialog | Frame | Art removed |
| --- | --- | --- |
| Ready check | `ReadyCheckListenerFrame` | `NineSlice`, `Bg`, `PortraitContainer` |
| Role poll | `RolePollPopup` | `Border` child |
| Stack split | `StackSplitFrame` (Camelot variant) | `SingleItemSplitBackground`, `MultiItemSplitBackground` |
| Queue ready | `LFGDungeonReadyDialog`, `LFGDungeonReadyStatus`, `LFGInvitePopup`, `PVPReadyDialog` | `Border`, `background`, `filigree`, `bottomArt` |
| Ticket status | `TicketStatusFrame` | `NineSlice` |
| Autocomplete | `AutoCompleteBox` | `NineSlice` |
| Old dropdown lists | `DropDownList1` to `3` | `Border` child and the global `<name>MenuBackdrop` child |
| Colour picker | `ColorPickerFrame` | `Border`, `Header` art |
| Add friend, report | `AddFriendFrame`, `ReportFrame` | `Border` |

Only the first three and the dropdown list were read key by key in the 69913
source. The rest are driven by the same key list; a key a dialog lacks is
skipped, so the worst case there is a dialog that keeps part of its art.

The last audit added 27 more, from their declarations only:

| Family | Frames | Art removed |
| --- | --- | --- |
| Translucent template | `GuildInviteFrame`, `CommunitiesGuildTextEditFrame`, `CommunitiesGuildLogFrame`, `CommunitiesGuildNewsFiltersFrame` | `Bg`, the corner and border pieces |
| Backdrop mixin | `CreateChannelPopup`, `OpacityFrame` | `Center`, four edges, four corners |
| Border child or nine-slice | `FriendsFriendsFrame`, `BattleNetInviteFrame`, `LFDRoleCheckPopup`, `LFGReadyCheckPopup`, `LFGListApplicationDialog`, `LFGListInviteDialog`, `PVPRoleCheckPopup`, `QuickJoinRoleSelectionFrame`, `ReportCheatingDialog`, `CommunitiesAvatarPickerDialog`, `CommunitiesSettingsDialog`, `CommunitiesTicketManagerDialog`, the three `ClassTalentLoadout*Dialog`, `BankCleanUpConfirmationPopup`, `GuildRenameFrame`, `EditModeImportLayoutLinkDialog`, `EditModeSystemSettingsDialog`, `RatingMenuFrame`, `CurrencyTransferMenu` | whatever of the key list they carry |

Left alone: `CommunitiesAddDialog` and `CommunitiesCreateDialog` (defined in
`Blizzard_CommunitiesSecure`) and `SecureTransferDialog`. Addon code may not
be allowed to index those frames.

A dialog the client does not have is skipped silently. Load-on-demand ones
are picked up on `ADDON_LOADED`.

## How it stays safe

Nothing is moved, resized, reparented, shown, hidden or given a new script.
The module writes region alpha, fonts and new child regions, none of which is
protected, so a first show in combat is fine. Art is faded first: a client
that refuses that write has had nothing added. A dialog that fails is
reported once as `Dialogs skin <name>` and not tried again.

The old dropdown lists are the piece to watch. RikUI's keys on `DropDownList1`
(`rikFill`, `rikBorder`, `rikFade`) are not read by Blizzard code, but these
lists sit under right-click actions such as Set Focus. On 69913 most menus use
the new Menu system ([menus](menus.md)), so they are rare. If a menu entry
reports "action blocked", drop the three `DropDownList` targets first.

## Diagnostics

`/rik debug` prints `Dialogs hooked=<n> skinned=<n> failed=<n>`.

## Verification

`tests/dialogs.test.lua` fakes the ready check, role poll, stack split and a
dropdown list with their 69913 keys. It proves: nothing happens before the
first show; art removed, fill and edge added; gold title, own text at
Blizzard's size with its colour kept; the push button flat through the
controls walk; fade on every show with one fill; the global-named close
button and backdrop child; a missing dialog skipped; the debug line; a first
show in combat; one failure report; the disabled module. This suite was
written before the module but first run after it, so it was never seen red.

The stub cannot show how any of this looks. Beta checklist:

1. Fully restart the client (new TOC entry). Shift-click a stack in your bags:
   the split box should be flat with flat buttons and working arrows.
2. In a group, start a ready check and a role poll.
3. Type `/w ` and two letters of a friend's name: the autocomplete list.
4. Open `/rik config`, pick a colour: the colour picker.
5. Right-click things that still open an old-style dropdown and watch for
   "action blocked".

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [ReadyCheck.xml: ReadyCheckListenerFrame's Bg, NineSlice, TitleContainer and PortraitContainer](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/ReadyCheck.xml)
- [RolePoll.xml: the Border child and the global-named close button](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/RolePoll.xml)
- [Camelot/StackSplitFrame.xml: the two backgrounds and the buttons](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Camelot/StackSplitFrame.xml)
- [UIDropDownMenuTemplates.xml: UIDropDownListTemplate's Border and MenuBackdrop](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/Mainline/UIDropDownMenuTemplates.xml)
