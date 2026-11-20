# SpikeSpotter

Your game stutters for a split second when you kill a mob, loot or pull? SpikeSpotter finds the addon behind it. It watches the frame time, and whenever a frame takes much longer than usual it asks the game's own addon profiler which addons used that frame.

**Website:** https://bencepo.github.io/spikespotter/

- **Ranking of the culprits.** Every addon that took part in a spike, with its total time, how often and its worst frame. The window refreshes live while you play.
- **Game or addon?** Spikes where no addon took a notable share are counted apart: then the game itself is the cause, and disabling addons will not help.
- **Context.** Each spike is logged with the game events that fired just before (loot window, quest log update, combat start ...), so you see *when* an addon gets expensive.
- **Copy report.** Ranking and the last 100 spikes as text, to paste into a bug report for the addon at fault or a forum post.
- **Chat message per spike** (optional) and an adjustable spike threshold.
- **Off when you are done.** One switch turns all measuring off; then SpikeSpotter costs nothing.

**How to use it:** open the window (`/spike` or the addon menu at the minimap), click Reset, play a few minutes the way the stutter happens, then look at the ranking. Disable the top addon and test again.

## Feedback and bug reports

Found a bug or have an idea? [Open an issue](https://github.com/Bencepo/SpikeSpotter/issues/new/choose), it takes a minute. No GitHub account? Comment on [CurseForge](https://www.curseforge.com/wow/addons/spikespotter#comments). Every report gets read.

## More addons by Bencepo

All addons, live demos and the web pages: **https://bencepo.github.io**

Like the addons? Support them on Ko-fi: **https://ko-fi.com/bencepo**

## AI disclosure

The code was written with the help of an AI assistant (Claude). Bencepo designed the features, tests everything in game and maintains the addon.

## License

All rights reserved, see [LICENSE](LICENSE).
