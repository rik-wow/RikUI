# Setup Studio research receipt

Reviewed 2026-10-02. The latest [Forever UI source](https://github.com/Gethe/wow-ui-source/tree/forever) head was 9a789c074b8e73c5d604ef2d6af3bb5b3aefb348; its version and the installed WowB.exe agreed on 1.60.1.70170. These are evidence, not a pinned target.

## Preview architecture

Cloudflare Workers cannot run the Windows GPU simulator or access licensed client inputs. The editor runs trusted RikUI Setup Pack Lua in Fengari and composes reviewed transparent component captures produced by the existing Lua renderer. Geometry, ownership and configuration validation share the addon implementation. Submitted content is decoded as bounded data and never compiled. Static rendered components have explicit appearance/state coverage; unsupported imported appearance stays preserved and is identified rather than depicted inaccurately. Drag feedback shows geometry only. Public builds contain addon code and reviewed screenshots, never extracted client assets or Blizzard source.

## Optional specialist recipe

The current [QuestTogether source](https://github.com/AlexAllocated/QuestTogether) at 58b15fb11a016b74327d567e313fd2cb5697085e identified version 5.16.4. Its [Forever listing](https://www.curseforge.com/wow/addons/questtogether) describes shared quest objectives, nameplate icons and optional progress bubbles. Nameplates.lua augments stock plates; Options.lua offers nameplateQuestHealthColorEnabled and icon-position controls. This supports a compatibility recipe, not an assumed styling or data API.

When QuestTogether is installed, give it stock nameplate ownership and disable RikUI nameplates on reload. Recommend icons Left and quest health tint off, preserving meaningful health colors. Reserve upper-left space for its personal progress bubble and ask the player to place it using its own supported edit controls. No foreign settings are written. Absence or an API failure leaves RikUI ownership unchanged. QuestTogether's chat, comparison and location sharing remain under its own controls.

## Device/activity boundaries

The current Forever GamepadUIDocumentation.lua describes gamepad action storage. Studio reads the supported C_GamePad.IsEnabled and GetBindingKey surfaces only for an optional modifier legend; it does not promise unrestricted controller navigation or assign bindings when changing device presentation. Manual/pinned and group/rest-driven activity selection uses the existing combat queue for geometry and supported display settings. Module and font/theme changes require a reload.

No class-specific spell or rank behavior is added. Existing preset schema/catalogue coverage remains bounded and is reviewed again by the character setup flow before protected operations.

## Acceptance and capacity

The user accepts native/game-client behavior and will report regressions. Automated tests and simulator captures are evidence of their respective environments, not agent-observed native playtests. One installed source and applied baseline are stored separately from personal live settings. Three restore journals use independent verified CVar banks, with the codec's 21,600-byte limit per record. Pack export is bounded to 12,000 bytes. History and libraries are not appended to the existing restart macro backup; portable export remains the recovery path where this beta client cannot retain Studio state across a full restart.
