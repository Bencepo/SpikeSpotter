-- SpikeSpotter
-- Copyright (c) 2026 Bencepo. All rights reserved.
--
-- Finds the addons behind short FPS drops. Every frame it notes how long the frame took; when one
-- takes much longer than usual, it reads the client's own addon profiler (C_AddOnProfiler, LastTime)
-- and records which addons used that frame and which game events fired just before. The ranking
-- and a copyable log are shown in a window of its own; the log is also kept in SpikeSpotterDB.

local ADDON, ns = ...
local pairs, ipairs, tostring, pcall, wipe = pairs, ipairs, tostring, pcall, wipe
local max = math.max
local tconcat, tsort = table.concat, table.sort
local format, date = format, date

local VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or ""
if VERSION:find("@") then VERSION = "dev" end
local BUG_URL = "https://github.com/Bencepo/SpikeSpotter/issues/new/choose"
local PREFIX = "|cffff8a3dSpikeSpotter:|r "
local ACCENT = { 1, 0.54, 0.24, 1 }

local P = C_AddOnProfiler
local M = Enum and Enum.AddOnProfilerMetric

local LOG_MAX = 1000
local EV_KEEP = 12
local WARMUP = 120        -- frames after login before spikes count (loading)
local LOADING_MS = 250    -- longer frames are loading screens, not spikes
local ROWS = 10

local DEFAULTS = { ms = 40, enabled = true, chat = false, spikes = 0, engine = 0 }

local db
local addons = {}               -- loaded addon names, without SpikeSpotter
local addonSet = {}             -- [name] = true for O(1) ADDON_LOADED append
local prev, cur = {}, {}        -- LastTime per addon index: previous and current frame
local events, evPos = {}, 0
local avg = 16
local warm = 0
local lastWasSpike = false
local lastChat = 0
local monitor, eventFrame, settingsWin, copyFrame
local refreshQueued = false
local rows = {}

local GetAddOnMetric
local LAST_TIME
local issecret = issecretvalue

-- Events that fire constantly in combat and carry no useful spike context.
local IGNORED = {
	COMBAT_LOG_EVENT_UNFILTERED = true,
	UNIT_AURA = true,
	UNIT_POWER_UPDATE = true,
	UNIT_POWER_FREQUENT = true,
	UNIT_POWER_BAR_TIMER_UPDATE = true,
	UNIT_POWER_POINT_CHARGE = true,
}

---------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------

local function AddAddon(name)
	if not name or name == ADDON or addonSet[name] then return end
	if not (GetAddOnMetric and LAST_TIME) then return end
	-- Validate once so OnUpdate can read the metric directly without pcall overhead.
	if not pcall(GetAddOnMetric, name, LAST_TIME) then return end
	addonSet[name] = true
	local idx = #addons + 1
	addons[idx] = name
	prev[idx], cur[idx] = 0, 0
end

local function CollectAddons()
	wipe(addons)
	wipe(addonSet)
	wipe(prev)
	wipe(cur)
	for i = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(i)
		if name and name ~= ADDON and C_AddOns.IsAddOnLoaded(i) then AddAddon(name) end
	end
end

local function RecentEvents()
	local out, seen = {}, {}
	for k = 0, EV_KEEP - 1 do
		local e = events[((evPos - k - 1) % EV_KEEP) + 1]
		if e and not seen[e] then
			seen[e] = true
			out[#out + 1] = e
		end
	end
	return table.concat(out, ", ")
end

local function Round(v) return math.floor(v * 10 + 0.5) / 10 end

local function SortByT(a, b) return a.t > b.t end
local function SortByMs(a, b) return a.s.ms > b.s.ms end

local function FlushRefresh()
	refreshQueued = false
	if settingsWin and settingsWin:IsShown() then settingsWin:Refresh() end
end

local function ScheduleRefresh()
	if refreshQueued or not (settingsWin and settingsWin:IsShown()) then return end
	refreshQueued = true
	C_Timer.After(0.5, FlushRefresh)
end

local function Record(frameMs)
	-- The profiler's "last frame" may still be the frame before: the larger of both counts,
	-- except right after a recorded spike or loading screen, whose numbers must not carry over.
	local list, sum = {}, 0
	for i = 1, #addons do
		local t = cur[i] or 0
		if not lastWasSpike then
			local p = prev[i] or 0
			if p > t then t = p end
		end
		if t >= 1 then
			list[#list + 1] = { name = addons[i], t = t }
			sum = sum + t
		end
	end
	table.sort(list, SortByT)

	db.spikes = db.spikes + 1
	if sum < frameMs * 0.3 then db.engine = db.engine + 1 end
	for i = 1, #list do
		local e = list[i]
		local s = db.byAddon[e.name]
		if not s then
			s = { n = 0, ms = 0, max = 0 }
			db.byAddon[e.name] = s
		end
		s.n, s.ms, s.max = s.n + 1, s.ms + e.t, math.max(s.max, e.t)
	end

	local top = {}
	for i = 1, math.min(8, #list) do top[#top + 1] = ("%s=%.1f"):format(list[i].name, list[i].t) end
	local log = db.log
	log[#log + 1] = {
		t = date("%Y-%m-%d %H:%M:%S"),
		frame = Round(frameMs),
		avg = Round(avg),
		addons = Round(sum),
		top = table.concat(top, " "),
		events = RecentEvents(),
		combat = InCombatLockdown() and 1 or 0,
		zone = GetRealZoneText and GetRealZoneText() or "",
	}
	-- Trim in batches so individual spikes do not pay an O(N) shift on every entry.
	if #log > LOG_MAX + 100 then
		local trimmed, start = {}, #log - LOG_MAX + 1
		for i = start, #log do trimmed[#trimmed + 1] = log[i] end
		db.log = trimmed
	end

	if db.chat and GetTime() - lastChat > 0.5 then
		lastChat = GetTime()
		local parts = {}
		for i = 1, math.min(3, #list) do parts[#parts + 1] = ("%s %.0f ms"):format(list[i].name, list[i].t) end
		print(PREFIX .. ("%.0f ms frame: %s"):format(frameMs, #parts > 0 and table.concat(parts, ", ") or "no addon (game)"))
	end

	ScheduleRefresh()
end

local function OnUpdate(_, elapsed)
	prev, cur = cur, prev
	for i = 1, #addons do
		local v = GetAddOnMetric(addons[i], LAST_TIME)
		cur[i] = (type(v) == "number" and (not issecret or not issecret(v))) and v or 0
	end
	local ms = elapsed * 1000
	warm = warm + 1
	if ms >= LOADING_MS then
		-- Prevent huge loading-screen metric values in cur from carrying into the next frame via prev.
		lastWasSpike = true
	else
		local spike = warm > WARMUP and ms > db.ms and (ms > avg * 2.5 or ms > db.ms * 2)
		if spike then Record(ms) end
		lastWasSpike = spike and true or false
	end
	avg = avg * 0.95 + math.min(ms, 100) * 0.05
end

local function OnEvent(_, e, arg1)
	if IGNORED[e] then return end
	if e:byte(1) == 85 and e:find("UNIT_POWER", 1, true) == 1 then
		IGNORED[e] = true
		return
	end
	-- an addon loaded on demand later (e.g. with its window): measure it from now on
	if e == "ADDON_LOADED" and arg1 then AddAddon(arg1) end
	evPos = evPos + 1
	if evPos > EV_KEEP then evPos = 1 end
	events[evPos] = e
end

local function Apply()
	if not monitor then return end
	if db.enabled then
		CollectAddons()
		warm = 0
		lastWasSpike = false
		monitor:SetScript("OnUpdate", OnUpdate)
		eventFrame:RegisterAllEvents()
	else
		monitor:SetScript("OnUpdate", nil)
		eventFrame:UnregisterAllEvents()
	end
end

local function Reset()
	db.spikes, db.engine, db.byAddon, db.log = 0, 0, {}, {}
end

---------------------------------------------------------------------------
-- Copyable report
---------------------------------------------------------------------------

local rankList, rankPool = {}, {}

local function Ranking()
	wipe(rankList)
	local n = 0
	for name, s in pairs(db.byAddon) do
		n = n + 1
		local e = rankPool[n]
		if not e then
			e = {}
			rankPool[n] = e
		end
		e.name, e.s = name, s
		rankList[n] = e
	end
	tsort(rankList, SortByMs)
	return rankList
end

local reportLines = {}

local function ReportText()
	wipe(reportLines)
	local build = GetBuildInfo and (GetBuildInfo()) or ""
	reportLines[#reportLines + 1] = format("SpikeSpotter %s, client %s, %s", VERSION, build, date("%Y-%m-%d %H:%M"))
	reportLines[#reportLines + 1] = format("%d spikes over %d ms, %d without a notable addon share (game)", db.spikes, db.ms, db.engine)
	reportLines[#reportLines + 1] = ""
	reportLines[#reportLines + 1] = "Addon: total ms / spikes / worst ms"
	for i, e in ipairs(Ranking()) do
		if i > 20 then break end
		reportLines[#reportLines + 1] = format("%d. %s: %.0f / %d / %.0f", i, e.name, e.s.ms, e.s.n, e.s.max)
	end
	reportLines[#reportLines + 1] = ""
	reportLines[#reportLines + 1] = "Last spikes (time, frame ms, addon ms, combat, addons, events)"
	for i = max(1, #db.log - 99), #db.log do
		local r = db.log[i]
		reportLines[#reportLines + 1] = format("%s | %s | %s | %s | %s | %s", r.t, r.frame, r.addons, r.combat == 1 and "combat" or "-", r.top ~= "" and r.top or "-", r.events)
	end
	return tconcat(reportLines, "\n")
end

local WHITE = "Interface\\Buttons\\WHITE8x8"

local function ShowCopy()
	if not copyFrame then
		local f = CreateFrame("Frame", "SpikeSpotterCopyFrame", UIParent, "BackdropTemplate")
		f:SetSize(560, 360)
		f:SetPoint("CENTER")
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetToplevel(true)
		f:SetClampedToScreen(true)
		f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		f:SetBackdropColor(0.059, 0.075, 0.094, 0.97)
		f:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		tinsert(UISpecialFrames, "SpikeSpotterCopyFrame")
		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 12, -10)
		title:SetText("SpikeSpotter report: Ctrl+C to copy")
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -32)
		scroll:SetPoint("BOTTOMRIGHT", -32, 12)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(510)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit
		copyFrame = f
	end
	copyFrame.edit:SetText(ReportText())
	copyFrame:Show()
	copyFrame.edit:SetFocus()
	copyFrame.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local COLUMNS = { { 0, "Addon" }, { 250, "total ms" }, { 340, "spikes" }, { 410, "worst ms" } }

local function BuildSettings()
	local UI = LibStub("BencepoUI-1.0")
	settingsWin = UI:CreateWindow({
		name = "SpikeSpotterFrame", title = "SpikeSpotter", subtitle = VERSION,
		width = 520, height = 440, accent = ACCENT, db = db, posKey = "settingsPoint", bugUrl = BUG_URL,
	})
	local w = settingsWin
	local X = 16
	w:Header(X, -48, "Monitoring")
	w:Check(X, -72, "Watch for spikes", "Off: SpikeSpotter does nothing at all. Turn it off when you are done.",
		function() return db.enabled end, function(v) db.enabled = v and true or false Apply() end)
	w:Check(X, -96, "Chat message per spike", "Prints the addons behind each spike to the chat as it happens.",
		function() return db.chat end, function(v) db.chat = v and true or false end)
	w:Slider(260, -72, "Spike threshold", 20, 150, 5, function() return db.ms end,
		function(v) db.ms = v end, "A frame counts as a spike when it takes at least this long and much longer than usual.", 220,
		function(v) return v .. " ms" end)

	local reset = w:Button("Reset", 110, Reset, "Clears the ranking and the log. Do this before a test.")
	reset:SetPoint("TOPLEFT", X, -130)
	local copy = w:Button("Copy report", 130, ShowCopy, "Ranking and the last 100 spikes as text, to paste into a bug report or a forum post.")
	copy:SetPoint("LEFT", reset, "RIGHT", 8, 0)

	w:Header(X, -172, "Addons behind the spikes")
	local status = w:Text(X, -194, "", 488)
	for _, h in ipairs(COLUMNS) do
		w:Text(X + h[1], -216, "|cff8d97a5" .. h[2] .. "|r", 120)
	end
	for i = 1, ROWS do
		local y = -216 - i * 17
		local name = w:Text(X, y, "", 300)
		local total = w:Text(X + 250, y, "", 80)
		local count = w:Text(X + 340, y, "", 60)
		local worst = w:Text(X + 410, y, "", 70)
		rows[i] = { name, total, count, worst }
	end
	w:OnRefresh(function()
		local list = Ranking()
		status:SetText(format("%d spikes recorded, %d of them without a notable addon share (the game itself).%s",
			db.spikes, db.engine, db.enabled and "" or " |cffff8a3dMonitoring is off.|r"))
		for i, r in ipairs(rows) do
			local e = list[i]
			r[1]:SetText(e and (i .. ". " .. e.name) or "")
			r[2]:SetText(e and format("%.0f", e.s.ms) or "")
			r[3]:SetText(e and tostring(e.s.n) or "")
			r[4]:SetText(e and format("%.0f", e.s.max) or "")
		end
		if not list[1] then rows[1][1]:SetText("|cff8d97a5Nothing yet. Play as usual: kill, loot, fight.|r") end
	end)
end

local function EnsureSettings()
	if not settingsWin then BuildSettings() end
	return settingsWin
end

local function ToggleSettings()
	if not db then return end
	EnsureSettings():Toggle()
end

function SpikeSpotter_OnCompartmentClick()
	ToggleSettings()
end

local function RegisterSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local category, layout = Settings.RegisterVerticalLayoutCategory("SpikeSpotter")
	if layout and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("SpikeSpotter has its own window", "Open", function()
			if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
			if not db then return end
			EnsureSettings():Show()
		end, "The window can be dragged anywhere and stays open while you play.", true))
	end
	Settings.RegisterAddOnCategory(category)
end

SLASH_SPIKESPOTTER1 = "/spike"
SLASH_SPIKESPOTTER2 = "/spikespotter"
SlashCmdList.SPIKESPOTTER = ToggleSettings

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	SpikeSpotterDB = SpikeSpotterDB or {}
	db = SpikeSpotterDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end
	db.byAddon = db.byAddon or {}
	db.log = db.log or {}
	db.quiet = nil
	pcall(RegisterSettings)
	if not (P and M and P.GetAddOnMetric and M.LastTime) then
		print(PREFIX .. "this client has no addon profiler (C_AddOnProfiler), SpikeSpotter cannot measure.")
		return
	end
	GetAddOnMetric = P.GetAddOnMetric
	LAST_TIME = M.LastTime
	issecret = issecretvalue
	monitor = CreateFrame("Frame")
	eventFrame = CreateFrame("Frame")
	eventFrame:SetScript("OnEvent", OnEvent)
	Apply()
end)

ns.ToggleSettings = ToggleSettings
