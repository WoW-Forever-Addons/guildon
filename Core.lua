local addonName, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Guildon: one addon for the whole guild (GUILDON_PLAN.md). Step 1: frame, guild roster, exchange core.
-- Own frames only: no hooksecurefunc, no HookScript, no Blizzard frame scripts.
-- Classic.lua (only in Guildon_Vanilla.toc, loaded before this file) sets ns.ERA.
---------------------------------------------------------------------------
ns.defaults = {
  panel = {},          -- window position and collapsed state (Style.Panel get/set)
  tab = "overview",    -- last open tab
  sets = {},           -- shared data sets, key "<kind>:<owner>" (Comm.lua)
  peers = {},          -- Guildon users seen: full name -> { v = version, t = time() }
  panelLocked = false,
  panelScale = 1,
  panelAlpha = 0.93,
  combatFade = false,
}
ns.SCHEMA = 1
ns.WORDMARK = "|cff3fa9f5Guil|rdon"
-- own prefix per game version, so Forever and Era data never mix (like Questdon's QdShareEra)
ns.PREFIX = ns.ERA and "GuildonEra" or "Guildon"

do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or function() end, addonName, "Version")
  ns.VERSION = (ok and type(v) == "string" and v ~= "") and v or "0"
end

---------------------------------------------------------------------------
-- Error guard: handlers, timers and UI callbacks run protected.
---------------------------------------------------------------------------
local MAX_ERRORS, MAX_MSG = 10, 160
local errors, warned = {}, false

local function Shorten(msg)
  msg = tostring(msg or "?"):gsub("\\", "/")
  msg = msg:gsub("[^%s:]*/([%w_]+%.[lx][um][al])", "%1")
  if #msg > MAX_MSG then msg = msg:sub(1, MAX_MSG) .. "..." end
  return msg
end

local function Record(context, err)
  if type(err) ~= "string" then err = "(unreadable error)" end
  local ok, msg = pcall(Shorten, err)
  if not ok then msg = "(unreadable error)" end
  for _, e in ipairs(errors) do
    if e.msg == msg and e.context == context then e.count = e.count + 1 return end
  end
  if #errors < MAX_ERRORS then errors[#errors + 1] = { context = context, msg = msg, count = 1 } end
  if not warned then
    warned = true
    print(ns.WORDMARK .. ": " .. L["an error occurred, /gn diag for details"])
  end
end

function ns.Errors() return errors end

function ns.SafeCall(context, fn, ...)
  local args, n = { ... }, select("#", ...)
  local ok, a, b, c = xpcall(function() return fn(unpack(args, 1, n)) end, function(err)
    pcall(Record, context, err)
    return err
  end)
  if ok then return a, b, c end
end

function ns.Guard(context, fn)
  return function(...) return ns.SafeCall(context, fn, ...) end
end

function ns.After(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, ns.Guard("timer", fn)) end
end

function ns.NewTicker(delay, fn)
  if C_Timer and C_Timer.NewTicker then return C_Timer.NewTicker(delay, ns.Guard("ticker", fn)) end
end

---------------------------------------------------------------------------
-- Events on our own frame. Several modules may listen to one event.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local listeners, initCallbacks = {}, {}

function ns.On(event, fn)
  if not listeners[event] then
    listeners[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event) -- unknown events throw
    if not ok then listeners[event] = nil return false end
  end
  table.insert(listeners[event], fn)
  return true
end

function ns.OnInit(fn) table.insert(initCallbacks, fn) end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    GuildonDB = type(GuildonDB) == "table" and GuildonDB or {}
    for k, v in pairs(ns.defaults) do
      if type(GuildonDB[k]) ~= type(v) then GuildonDB[k] = type(v) == "table" and {} or v end
    end
    GuildonDB.schema = ns.SCHEMA
    -- (Daniel 26.10.: the darker look of the Gemini drafts) the old default opacity 0.82 moves to the new one once; a value he chose stays
    if not GuildonDB.darkLook then
      if GuildonDB.panelAlpha == 0.82 then GuildonDB.panelAlpha = 0.93 end
      GuildonDB.darkLook = true
    end
    -- (Daniel 28.10.) the test switches /gn libra and /gn crest are gone; a saved one from a test package is dropped
    GuildonDB.testLibra, GuildonDB.testCrest = nil, nil
    ns.db = GuildonDB
    for _, fn in ipairs(initCallbacks) do ns.SafeCall("init", fn) end
    return
  end
  if not ns.db then return end
  local list = listeners[event]
  if list then
    for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
  end
end)

---------------------------------------------------------------------------
-- Window settings for Style.Panel
---------------------------------------------------------------------------
local SHARED = { locked = "panelLocked", scale = "panelScale", alpha = "panelAlpha", combatFade = "combatFade" }
function ns.PanelGet(tableName)
  return function(key)
    local flat = SHARED[key]
    if flat then return ns.db[flat] end
    return ns.db[tableName][key]
  end
end
function ns.PanelSet(tableName)
  return function(key, value)
    local flat = SHARED[key]
    if flat then ns.db[flat] = value else ns.db[tableName][key] = value end
  end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(msg) print(ns.WORDMARK .. ": " .. tostring(msg)) end

-- Secret values (Midnight rules) never reach comparisons or table keys in our code.
function ns.Usable(v)
  if type(v) == "nil" then return false end
  if canaccessvalue then
    local ok, r = pcall(canaccessvalue, v)
    if ok then return r and true or false end
    return false
  end
  if issecretvalue then
    local ok, r = pcall(issecretvalue, v)
    if ok then return not r end
    return false
  end
  return true
end

function ns.Num(v)
  if type(v) == "number" and ns.Usable(v) then return v end
  return nil
end

function ns.Str(v)
  if type(v) == "string" and ns.Usable(v) and v ~= "" then return v end
  return nil
end

function ns.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

-- 32 bit checksum of a string as 8 hex digits (same result on every client; Lua numbers are doubles)
function ns.Checksum(s)
  local h = 2166136261
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
  return ("%08x"):format(h)
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
  { "/gn wishes", "the wish list" },
  { "/gn sync", "ask the guild for new data now" },
  { "/gn diag", "state of the exchange and errors" },
  { "/gn demo", "example guild to try the windows (again: off)" },
  { "/gn export", "your professions as text for the guild website" },
  { "/gn recipes", "recipes the game showed that Guildon does not know yet, to send to the authors" },
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
  elseif msg == "wishes" or msg == "wish" or msg == "wünsche" then
    if ns.OpenTab then ns.OpenTab("wishes") end
  elseif msg == "sync" then
    if ns.Hello then ns.Hello(true) end
    ns.Print(L["Asked the guild for new data."])
  elseif msg == "demo" or msg == "demo on" or msg == "demo off" or msg == "beispiel" then
    if ns.SetDemo then ns.SetDemo(msg == "demo off" and false or (msg == "demo on" and true or not ns.demo)) end
  elseif msg == "export" then
    if ns.ShowExport then ns.ShowExport() end
  elseif msg == "recipes" or msg == "rezepte" then
    if ns.ShowRecipeReport then ns.ShowRecipeReport() end
  elseif msg == "diag" then
    if ns.PrintDiag then ns.PrintDiag() end
  elseif msg == "help" or msg == "?" or msg == "hilfe" then
    ns.PrintHelp()
  else
    ns.Print(L["Unknown command: %s"]:format(msg))
    ns.PrintHelp()
  end
end

SlashCmdList["GUILDON"] = function(msg) ns.SafeCall("slash", ns.Slash, msg) end
