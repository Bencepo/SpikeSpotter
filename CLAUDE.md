# Notes for Claude

SpikeSpotter: finds the addons behind short FPS drops in WoW Forever (Lua 5.1). Author and rights holder: Bencepo. All rights reserved, no open-source license.

## How it measures

- `OnUpdate` every frame: reads `C_AddOnProfiler.GetAddOnMetric(name, Enum.AddOnProfilerMetric.LastTime)` (ms) for every loaded addon except itself, keeps the previous and current frame.
- A frame is a spike when it is over the threshold (`db.ms`, default 40), under 250 ms (longer = loading screen), after a 120-frame warm-up, and over 2.5x the running average or 2x the threshold.
- It is not certain whether `LastTime` at detection is the spike frame or the one before, so the larger of both counts, except right after a recorded spike.
- Spikes where addons together took under 30% of the frame count as the game's own (`db.engine`).
- `RegisterAllEvents` on a separate frame keeps the last 12 event names (combat log, auras and power skipped) as context.
- Everything stops (no OnUpdate, events unregistered) when "Watch for spikes" is off.

## Saved data

`SpikeSpotterDB`: `ms`, `enabled`, `chat`, `spikes`, `engine`, `byAddon[name] = { n, ms, max }`, `log` (last 1000 spikes: `t, frame, avg, addons, top, events, combat, zone`). Ben lets Claude read the log from `WTF/Account/BALACHNIE/SavedVariables/SpikeSpotter.lua` for analysis.

## Findings so far (Ben's setup, Nov 2026)

- Loot: ForeverFishing ~35 ms and WaylaidHelper ~23 ms (ITEM_DATA_LOAD_RESULT, BAG_UPDATE_DELAYED).
- Combat start/end: ItemRack ~27 ms (quick-access snapshots) -> replaced by TrinketDock.
- Kills with quest progress: QuestieTrace ~20 ms, Guidelime ~10 ms.
- Ace3 often shows up for code of addons using its libraries (AceEvent/AceTimer callbacks).

## Rules

- UI texts in English. Window built with BencepoUI (`Libs/BencepoUI`, bump its LibStub minor on changes).
- CI runs luacheck and LuaLS with the WoW API annotations; LuaLS must report zero diagnostics or the release stops.
- Release: new version heading at the top of `CHANGELOG.md`, push to `main`; the workflow uploads to CurseForge and Wago (secrets `CF_API_KEY`, `WAGO_API_TOKEN`). Test in game before pushing.
