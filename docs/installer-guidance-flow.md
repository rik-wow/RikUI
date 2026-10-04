# Local guide installer interface contract

Interface contract for quest/navigation delivery. The native Win32 implementation
and twelve reviewed window states use this contract. Generation, installation
and published artifact verification are recorded separately from visual review.

Use Microsoft's [Fluent design guidelines](https://learn.microsoft.com/en-us/windows/apps/design/guidelines-overview)
for hierarchy, spacing, familiar controls and accessible interactions.
The existing application uses native Win32 controls; apply the visual and
interaction conventions within that architecture. Changing UI frameworks is
not required for this work.

## Primary flow

Show four clearly labeled stages with the current stage emphasized:
**Find your game → Get quest information → Prepare your guide → Ready to play**.
Use a short headline explaining the player's next action and one visually
dominant primary button. Put technical details behind an expandable details
area. Advanced tool paths and raw schema names are not primary user choices.

1. **Find your game.** Discover compatible installations and show the selected
   directory, executable and current Forever version. Browse remains available.
   Confirm compatibility against current publisher metadata before enabling
   the next step. Explain mismatches with a concrete action such as
   “Update Forever in Battle.net, then check again.”
2. **Get quest information.** Explain the separately obtained provider by name,
   publisher and purpose: it supplies quest targets and locations.
   Offer the supported publisher acquisition path and validate the required
   source/contract. An installed provider ZIP must not be presented as
   interchangeable with a source checkout. Show download size and destination
   when known. The player must not install Git, Python, Node or database tools.
3. **Prepare your guide.** Explain that navigation is generated on this computer
   from the player's current game files. Show measured phases and units:
   download bytes, inspected files, completed/total generation jobs, verification,
   then installation. Show an indeterminate indicator only when the total is
   unknown. Do not produce fabricated overall percentages or completion times.
   Show measured elapsed cost; show an estimate only with a defensible model.
4. **Ready to play.** Show verified installed version, quest coverage, built regions,
   remaining unsupported coverage and how updates are checked. The complete
   success state requires verified assembly and installed-byte checks. A partial
   region build must use a visibly different state, **Guide partially prepared**,
   with available and unavailable regions and a clear Resume action.

## Progress, cancellation and recovery

Microsoft's [progress-control guidance](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls)
requires choosing determinate or indeterminate progress to match the available
measurement and using explanatory text when the operation is not self-evident.
Pair progress with a phase label; icons and color supplement explicit text.

- Allow cancellation during acquisition/generation. Explain that verified work
  is retained for resume. Pause scheduling new jobs, stop cancellable workers,
  and preserve the last installed guide.
- During a directory transaction, explain **Finishing safely** and finish or
  recover the transaction before closing. Never interrupt between swaps without
  a recoverable journal.
- Insufficient space states show required and available space and the relevant
  drive. Offer Choose another location and Check again.
- Publisher/network failures offer Retry with the failing publisher named.
  Keep other verified downloads and working installed files.
- Unsupported provider/client/schema states name the missing support, retain
  existing files, and withhold stale guidance for the new build.
- Rollback states show the retained backup, previous version and result.
  Never imply settings or unrelated addons were replaced.

## Interaction acceptance

Verify the actual native window with each meaningful state: selection, mismatch,
provider download, generation, cancellation/resume, disk failure, provider failure,
partial coverage, verification failure, installation/recovery, success and rollback.

All actions need accessible names and keyboard access. Use a predictable tab
order, visible focus, Enter for the primary action and Escape for cancellation
where safe. Error messages must identify the problem and next action together.
Do not rely on color alone. Respect Windows text scaling, contrast settings and
DPI. Verify clipped text and button reachability at supported window sizes.

The user accepts native gameplay behavior. Installer window and automated
interface checks still apply; no gameplay test or user screenshot is required.
