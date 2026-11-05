local addonName, ns = ...
local L = ns.L
ns.Style = LibStub("DonCore-1.0"):Get("Style", 4):ForAddon() -- DonCore's Style (Libs/DonCore/Style.lua) for texts: Hex, Number, Wordmark, tooltips; the windows are built from DonCore's Kit (02.11.2026)

---------------------------------------------------------------------------
-- Guildon: one addon for the whole guild (GUILDON_PLAN.md). Step 1: frame, guild roster, exchange core.
-- (31.10.2026, C3, DONCORE_PLAN.md "Craftdon aus Guildon lösen") 0.9.0: professions, recipes, wishes, trade and prices are in
-- Guildon Crafts; Guildon keeps the members, the map, alts, the emblem and the arrow.
-- Own frames only: no hooksecurefunc, no HookScript, no Blizzard frame scripts.
-- Classic.lua (only in Guildon_Vanilla.toc, loaded before this file) sets ns.ERA.
-- (31.10.2026) Error guard, events, saved table and helpers are in Shared/Base.lua (GuildShared/), loaded right after this file.
---------------------------------------------------------------------------
ns.defaults = {
  window = {},         -- (02.11.2026, Don style) place and size of the window (DonCore Kit.Window's store)
  tab = "overview",    -- last open tab
  sets = {},           -- shared data sets, key "<kind>:<owner>" (Comm.lua)
  peers = {},          -- Guildon users seen: full name -> { v = version, t = time() }
}
ns.SCHEMA = 1
ns.WORDMARK = "|cff3fa9f5Guil|rdon"
-- own prefix per game version, so Forever and Era data never mix (like Questdon's QdShareEra)
ns.PREFIX = ns.ERA and "GuildonEra" or "Guildon"

ns.DBNAME = "GuildonDB"
ns.ERROR_HINT = "an error occurred, /gn diag for details"

-- (GuildShared/Base.lua calls this once the saved table is there, before the init callbacks)
function ns.MigrateDB(db)
  -- (Daniel 28.10.) the test switches /gn libra and /gn crest are gone; a saved one from a test package is dropped
  db.testLibra, db.testCrest = nil, nil
  -- (02.11.2026, StyleKit 2 step 4) the window is DonCore's Kit.Window now: the old panel's place, size, lock, scale,
  -- opacity and combat fade are gone (the Don window keeps place and size in db.window)
  db.panel, db.panelWidth, db.panelHeight, db.panelLocked, db.panelScale, db.panelAlpha, db.combatFade, db.darkLook = nil, nil, nil, nil, nil, nil, nil, nil
  if db.memberFilter ~= "guildon" and db.memberFilter ~= "online" then db.memberFilter = nil end
  if db.tab == "options" then db.tab = "overview" end
  -- (04.11.2026, Era-Test) new defaults (Daniel 04.11.: map icon size 60 %, minimap icon size 65 %, hide while flagged for
  -- PvP off). The old defaults were written into GuildonDB, so once only the values still on the old default move to the
  -- new one; what the player set himself stays.
  if not db.defaults1104 then
    if db.mapWorldScale == 1 then db.mapWorldScale = 0.6 end
    if db.mapMiniScale == 1 then db.mapMiniScale = 0.65 end
    if db.mapHidePvP == true then db.mapHidePvP = false end
    db.defaults1104 = true
  end
end

-- Guildon's lines in /gn diag after the exchange numbers (GuildShared/Comm.lua ns.PrintDiag)
ns.ADDON_TITLE = "Guildon"
-- (31.10.2026) one of the Guildon parts: its entry at the shared minimap button (Shared/Launcher.lua)
ns.MODULE = { id = "map", title = "Guildon: Map & Members", icon = "Interface\\Icons\\INV_Misc_Map_01", order = 1 }
function ns.DiagExtra()
  local ws = ns.WorldPinState and ns.WorldPinState()
  if not DonMapAPI then print("  DonMap is missing: no guild members on the maps") end -- (30.10.2026) DonMap draws the pins
  if ws then
    print(("  world map: shown map %s, you on %s, canvas %dx%d, scale %.2f, positions %d, on this map %d, pins %d; first pin visible %s, alpha %s, size %s, level %s (canvas %s)")
      :format(tostring(ws.map), tostring(ws.mine), ws.w or 0, ws.h or 0, ws.scale or 0, ws.have, ws.onMap, ws.pins, tostring(ws.vis),
        tostring(ws.alpha), tostring(ws.size), tostring(ws.level), tostring(ws.canvasLevel)))
    print(("  map levels: explored areas %s, area POI %s"):format(tostring(ws.expl), tostring(ws.poi)))
  else
    print("  world map: not looked at yet (open the world map once, then /gn diag)")
  end
  -- (27.10., Frankston: our pins over Questie and GatherMate) the levels of the other addons' pins, to place ours below
  if ns.ForeignPinLevels then
    for _, line in ipairs(ns.ForeignPinLevels()) do print("  " .. line) end
  end
  if not GuildonCrafts_OnAddonCompartmentClick then print("  Guildon Crafts is missing: no professions, recipes or wishes") end
end

function Guildon_OnAddonCompartmentClick()
  if ns.ToggleWindow then ns.ToggleWindow() end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_GUILDON1 = "/gn"
SLASH_GUILDON2 = "/guildon"
ns.COMMANDS = {
  { "/gn", "show or hide the window" },
  { "/gn members", "the guild members" },
  { "/gn options", "all settings (also the cog in the window)" },
  { "/gn sync", "ask the guild for new data now" },
  { "/gn diag", "state of the exchange and errors" },
  { "/gn layer", "what the layer reading sees (target a creature first)" },
  { "/gn demo", "example guild to try the windows (again: off)" },
  { "/gn help", "this list" },
}

function ns.PrintHelp()
  ns.Print(L["Commands:"])
  for _, c in ipairs(ns.COMMANDS) do print("  |cffebebeb" .. c[1] .. "|r  |cff9ea3ad" .. L[c[2]] .. "|r") end
end

function ns.Slash(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if msg == "" or msg == "show" or msg == "toggle" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif msg == "members" or msg == "mitglieder" then
    if ns.OpenTab then ns.OpenTab("members") end
  elseif msg == "options" or msg == "optionen" or msg == "config" then
    if not (ns.OpenOptions and ns.OpenOptions()) then ns.Print(L["The options window is missing (DonCore)."]) end
  elseif msg == "sync" then
    if ns.Hello then ns.Hello(true) end
    ns.Print(L["Asked the guild for new data."])
  elseif msg == "demo" or msg == "demo on" or msg == "demo off" or msg == "beispiel" then
    if ns.SetDemo then ns.SetDemo(msg == "demo off" and false or (msg == "demo on" and true or not ns.demo)) end
  elseif msg == "diag" then
    if ns.PrintDiag then ns.PrintDiag() end
  elseif msg == "layer" then
    if ns.LayerDiag then ns.LayerDiag() end
  elseif msg == "names" or msg == "namen" then
    ns.NamesDiag()
  elseif msg == "wishes" or msg == "wish" or msg == "wünsche" or msg == "export" or msg == "recipes" or msg == "rezepte" then
    -- (C3) these moved to Guildon Crafts with the professions
    ns.Print(L["This is in Guildon Crafts now: /gnc %s"]:format(msg == "wünsche" and "wishes" or (msg == "rezepte" and "recipes" or msg)))
  elseif msg == "help" or msg == "?" or msg == "hilfe" then
    ns.PrintHelp()
  else
    ns.Print(L["Unknown command: %s"]:format(msg))
    ns.PrintHelp()
  end
end

-- (05.11.2026, WoW Forever's surnames) what the game gives as names: the player, the realm, the first roster rows and
-- the last senders of addon messages; printed and kept in GuildonDB.namesDiag (read after a /reload)
function ns.NamesDiag()
  local function S(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = "[" .. tostring((select(i, ...))) .. "]" end
    return table.concat(t, " ")
  end
  local out = {}
  out[#out + 1] = "UnitName " .. S(ns.Call(UnitName, "player"))
  out[#out + 1] = "UnitFullName " .. S(ns.Call(UnitFullName, "player"))
  out[#out + 1] = "GetRealmName " .. S(ns.Call(GetRealmName)) .. " normalized " .. S(ns.Call(GetNormalizedRealmName))
  out[#out + 1] = "ShouldDisplaySurname " .. S(C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname and ns.Call(C_PlayerInfo.ShouldDisplaySurname))
  out[#out + 1] = "MyName " .. S(ns.MyName())
  local n = ns.Call(GetNumGuildMembers) or 0
  for i = 1, math.min(tonumber(n) or 0, 5) do out[#out + 1] = "roster " .. i .. " " .. S(ns.Call(GetGuildRosterInfo, i)) end
  local raw = ns.rawSenders or { n = 0 }
  for i = 1, raw.n do out[#out + 1] = "sender " .. S(raw[i], raw[raw[i]]) end
  if UnitExists and ns.Call(UnitExists, "target") then out[#out + 1] = "target " .. S(ns.Call(UnitName, "target")) .. " full " .. S(ns.Call(UnitFullName, "target")) end
  for _, line in ipairs(out) do ns.Print(line) end
  if ns.db then ns.db.namesDiag = out end
end

SlashCmdList["GUILDON"] = function(msg) ns.SafeCall("slash", ns.Slash, msg) end
