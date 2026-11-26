# Changelog

## Unreleased

- Lower profiling overhead: the per-frame profiler reads metrics directly into indexed arrays without per-frame `pcall` or string hashing, `RegisterAllEvents` filters noisy events via a lookup table instead of pattern matching, and `ADDON_LOADED` appends newly loaded addons directly instead of rescanning the full addon list.
- Fixed: loading-screen frames no longer carry their huge profiler numbers into the next normal frame and skew the first post-load spike.
- The window now refreshes when new spikes arrive instead of re-sorting every second while idle, log trimming runs in batches, and the report copy dialog stays clamped to the screen.
- Shared settings window updated to BencepoUI 5.

## 1.0.2

- Addons loaded on demand (when their window opens, for example) are measured too: the list of addons is updated whenever one loads. Before, only the addons loaded at login counted.
- The shared settings window (BencepoUI) is now one version for all Bencepo addons: "Report a bug" sits in a footer of its own, and the hint in the title row no longer runs into the title.

## 1.0.1

- New icon in the addon list and in the addon menu at the minimap, part of the new Bencepo logo family.

## 1.0.0

- Detects frame-time spikes and names the addons that used those frames (client addon profiler).
- Ranking by total time, count and worst frame; spikes without a notable addon share are counted as the game's own.
- Every spike logged with the game events that fired just before it.
- Copy report: ranking and the last 100 spikes as text.
- Optional chat message per spike, adjustable threshold, one switch to turn all measuring off.
- Window of its own with a "Report a bug" button.
