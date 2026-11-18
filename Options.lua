local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Guildon's options in DonCore's shared options window (StyleKit 2 step 4, 02.11.2026; mockup part 6): the settings of the
-- old Map tab and the old Options tab. The cog in the window's header, /gn options and the Blizzard AddOns page open it.
-- Tabs: Map (sharing, pins, sizes, opacity, layer, with a preview of the pins), Window (minimap button, place), Tools
-- (status, example guild, sync, commands).
-- (16.11.2026) With the option blizzLook (on by default) and the game's templates at login the same options are pages in
-- the game's settings (Options > AddOns > Guildon: Map & Members, DonCore Settings 4 fullPages) and every cog and /gn options
-- ends there (DonCore Options spec.redirect); the preview of the pins stays in DonCore's window (a button there).
---------------------------------------------------------------------------
local Opt = LibStub("DonCore-1.0"):Get("Options", 2)

local SHARE_TEXT = { guild = "With the guild", group = "Only with my group", off = "Off" }
-- (Daniel 26.10.) the look of the pins; texts for guildon_keys.py
local PIN_STYLE_TEXT = { emblem = "Guild sign", shield = "Shield only", dot = "Plain dot" }
-- (04.11.2026, Daniel: TomTom too) which arrow leads to a member (Extras.lua ns.ArrowWay); texts for guildon_keys.py
local ARROW_TEXT = { auto = "Automatic", donmap = "DonMap arrow", tomtom = "TomTom", blizzard = "Map pin of the game" }

-- (04.11.2026, Era-Test) Daniel 04.11.: map icon size 60 %, minimap icon size 65 %, hide while flagged for PvP off by default
-- (Core.lua ns.MigrateDB moves saved values still on the old defaults once)
ns.OPTION_DEFAULTS = {
  mapShare = "guild", mapHidePvP = false, mapWorld = true, mapMinimap = true, mapInstance = false, mapLayer = false,
  pinStyle = "emblem", mapWorldScale = 0.6, mapMiniScale = 0.65, mapPinAlpha = 1, minimapButton = true, mapArrow = "auto",
  mapOwnArrow = true, mapAltClick = false, mapShowGroup = false, -- (07.11.2026, a player on Discord) DonMap draws the own arrow above the pins (DonMapAPI 6)
  blizzLook = true, -- (16.11.2026, Daniel: "Sollte Standart sein") the window in the game's look (Core.lua ns.LookKit)
}

local function Percent(v) return ("%d %%"):format(math.floor((tonumber(v) or 0) * 100 + 0.5)) end

local function Pins()
  if ns.UpdateWorldPins then ns.SafeCall("pins", ns.UpdateWorldPins) end
  if ns.UpdateMiniPins then ns.SafeCall("pins", ns.UpdateMiniPins) end
  if ns.ApplyPinMouse then ns.SafeCall("pins", ns.ApplyPinMouse) end
end

local ITEMS = {
  { header = "Sharing" },
  { key = "mapShare", name = "Share my position", kind = "dropdown",
    tip = "Who sees you on the map: the whole guild, only your group, or nobody.",
    options = function() return { { "guild", L[SHARE_TEXT.guild] }, { "group", L[SHARE_TEXT.group] }, { "off", L[SHARE_TEXT.off] } } end },
  { key = "mapHidePvP", name = "Hide while flagged for PvP", tip = "While you are flagged for PvP your position is not sent." },
  { key = "mapInstance", name = "Minimap in dungeons and raids",
    tip = "Off by default. On: inside a dungeon or raid you share your place and see the members with Guildon on the minimap, as far as the game gives positions there." },
  { header = "Pins" },
  { key = "mapWorld", name = "Members on the world map", tip = "Guild members with Guildon as pins on the world map." },
  { key = "mapMinimap", name = "Members on the minimap", tip = "Guild members with Guildon as pins on the minimap." },
  { key = "mapShowGroup", name = "Group members as pins",
    tip = "Off by default: members of your party or raid get no guild pin, the game already shows them. On: they get one as well." },
  { key = "mapOwnArrow", name = "My arrow above the pins",
    tip = "Your own arrow on the minimap stays visible when a member's pin lies on it, so the pins can stay fully visible." },
  { key = "pinStyle", name = "Pin look", kind = "dropdown", tip = "The look of the pins, always in the class colour.",
    options = function()
      local out = {}
      for _, k in ipairs(ns.PIN_STYLES or { "emblem", "shield", "dot" }) do out[#out + 1] = { k, L[PIN_STYLE_TEXT[k]] } end
      return out
    end },
  { key = "mapWorldScale", name = "Map icon size", kind = "slider", min = 0.25, max = 2, step = 0.05, format = Percent,
    tip = "Size of the guild pins on the world map. 100 % is the normal size." },
  { key = "mapMiniScale", name = "Minimap icon size", kind = "slider", min = 0.25, max = 2, step = 0.05, format = Percent,
    tip = "Size of the guild pins on the minimap. 100 % is the normal size." },
  { key = "mapPinAlpha", name = "Opacity", kind = "slider", min = 0.2, max = 1, step = 0.05, format = Percent,
    tip = "How see-through the guild pins on the world map and the minimap are. 100 % is fully visible." },
  { key = "mapAltClick", name = "Pins only clickable with Alt",
    tip = "On: clicks and the mouse go through the guild pins to the map and the quest pins below. Hold Alt to see a member's tooltip, whisper him or set the arrow. Off by default." },
  { key = "mapLayer", name = "Show the layer",
    tip = "The layer (server copy of the zone) of each member in the tooltips and lists, compared with yours. Off by default." },
  { key = "mapArrow", name = "Arrow to a member", kind = "dropdown",
    tip = "Right-click on a member on the map: this arrow leads you to him and follows him while he moves. Automatic: DonMap's arrow while it is on, otherwise TomTom, otherwise the map pin of the game.",
    options = function()
      local out = {}
      for _, k in ipairs(ns.ARROW_WAYS or { "auto" }) do
        if k == "auto" or k == "donmap" or (ns.ArrowHas and ns.ArrowHas(k)) then out[#out + 1] = { k, L[ARROW_TEXT[k]] } end
      end
      return out
    end },
  { header = "Window" },
  -- (16.11.2026, Daniel: the Blizzard look of Profitdon and Luredon for all Don addons, on by default) the window is built
  -- again in the other look (GuildShared/Window.lua ns.WindowReset)
  { key = "blizzLook", name = "Windows in the game's look",
    tip = "Guildon's window looks like the game's own: the game's frame, tabs, buttons and lists. Off: the Don look. Where the game lacks its templates (Classic Era) the window keeps the Don look. The options then open in the game's settings (Options > AddOns > Guildon: Map & Members) after a /reload." },
  { key = "minimapButton", name = "Minimap button", tip = "Shows the Guildon button at the minimap. All Guildon parts share it." },
  { kind = "button", optKey = "button:resetWindow", name = "Reset window position", button = "Reset",
    tip = "Puts the Guildon window back in the middle of the screen at its first size.", onClick = function() if ns.ResetWindow then ns.ResetWindow() end end },
}

-- the preview of the pins: four classes in the chosen look, size and opacity (Daniel 27.10.: the group example left out)
local PREVIEW = { { "WARRIOR", 34 }, { "MAGE", 60 }, { "PRIEST", 21 }, { "HUNTER", 12 } }
local function Preview(f, w, h)
  if not ns.PreviewPin then return end
  if not f.guildon then
    local box = CreateFrame("Frame", nil, f)
    box.pins = {}
    for i, c in ipairs(PREVIEW) do
      local b = ns.PreviewPin(box, 22)
      b.previewMembers = { { name = "", p = { class = c[1], level = c[2] } } }
      box.pins[i] = b
    end
    f.guildon = box
  end
  local box = f.guildon
  box:SetAllPoints(f)
  box:Show()
  local size = math.floor(22 * (tonumber(ns.db.mapWorldScale) or 1) + 0.5)
  local step = math.floor(w / (#PREVIEW + 1))
  for i, b in ipairs(box.pins) do
    ns.PaintPreview(b, b.previewMembers, size, math.floor(size * 1.25))
    b:ClearAllPoints()
    b:SetPoint("CENTER", box, "TOPLEFT", step * i, -math.floor(h / 2))
    b:Show()
  end
end

-- the tabs of DonCore's window; the game's settings get the same lists as pages
local MAP_MAIN = { "header:Sharing", "mapShare", "mapHidePvP", "mapInstance", "header:Pins", "mapWorld", "mapMinimap", "mapShowGroup",
  "mapOwnArrow", "pinStyle", "mapWorldScale", "mapMiniScale", "mapPinAlpha", "mapAltClick" }
local MAP_MORE = { "mapArrow", "mapLayer" }
local WINDOW_MAIN = { "blizzLook", "minimapButton", "button:resetWindow" }

-- one change, from DonCore's window or the game's settings
local function Changed(key)
  if key == "mapArrow" and ns.ArrowStop then ns.ArrowStop() end -- the next right-click uses the new arrow
  if key == "blizzLook" then
    if ns.WindowReset then ns.WindowReset() end -- the window in the other look
  else
    if key == "minimapButton" then if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
    elseif key and key:find("^map") or key == "pinStyle" then Pins() end
    if ns.Refresh then ns.Refresh() end
  end
  if ns.RefreshSettingsUI then ns.SafeCall("settings", ns.RefreshSettingsUI) end -- the game's settings show the new value
end

local function Status()
  local total, online, guildon = ns.MemberCounts()
  return { ("Guildon %s"):format(tostring(ns.VERSION or "")),
    ns.InGuild() and L["%d members"]:format(total) .. ", " .. L["online: %d"]:format(online) .. ", " .. L["With Guildon"] .. ": " .. guildon
      or L["You are not in a guild."] }
end

local function Tools()
  return {
    { "Example guild", "On / off", function() if ns.SetDemo then ns.SetDemo(not ns.demo) end end,
      "Made-up members to try the windows, only on your screen.", state = function() return ns.demo and true or false end },
    { "Sync", "Ask now", function() if ns.Hello then ns.Hello(true) end ns.Print(L["Asked the guild for new data."]) end,
      "Asks the guild for new data now." },
  }
end

local direct = false -- (16.11.2026) DonCore's window on purpose (the preview), not the game's settings
local function Register()
  if not (Opt and Opt.Register) then return end
  local db = ns.db
  -- (04.11.2026, Era-Test) the minimap switch is DonCore's MinimapButton option (minor 3) through the shared button
  -- (Shared/Launcher.lua): our name and tip, switching the one button for every Guildon part
  if ns.MinimapOption then
    for i, it in ipairs(ITEMS) do
      if it.key == "minimapButton" and not it.donCommon then ITEMS[i] = ns.MinimapOption({ name = it.name, tip = it.tip }) end
    end
  end
  for k, v in pairs(ns.OPTION_DEFAULTS) do if db[k] == nil then db[k] = v end end
  Opt.Register(ns.OPTIONS_ID, {
    name = "Guildon: Map & Members", order = 30, addon = "Guildon",
    tabs = {
      { key = "map", title = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01", preview = Preview,
        text = "Who sees you on the map, and how the guild members look on the world map and the minimap.",
        main = MAP_MAIN, more = MAP_MORE },
      { key = "window", title = "Window", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
        text = "The minimap button of all Guildon parts and the place of the window.",
        main = WINDOW_MAIN },
      { key = "tools", title = "Tools", text = "Status", status = true, tools = { "Example guild", "Sync" } },
    },
    pages = function() return { { items = ITEMS } } end,
    tools = Tools,
    db = function() return ns.db end,
    default = function(key) return ns.OPTION_DEFAULTS[key] end,
    changed = Changed,
    status = Status,
    help = function()
      local lines = {}
      for _, c in ipairs(ns.COMMANDS or {}) do lines[#lines + 1] = c[1] .. "  " .. L[c[2]] end
      return table.concat(lines, "\n")
    end,
    T = function(s) return L[s] end,
    labels = function(s) return L[s] end,
    -- (16.11.2026, DonCore Options 6) with the option blizzLook every cog and /gn options ends in the game's settings
    redirect = function() if direct then return false end return ns.OpenGameOptions and ns.OpenGameOptions() or false end,
  })
end

---------------------------------------------------------------------------
-- (16.11.2026) The game's settings: the same items as pages, built at login when the option blizzLook is on and the client
-- has the game's templates (else nothing there, as before). A change of the option works for the options after a /reload.
---------------------------------------------------------------------------
local category, fullPages = nil, false

local function ItemOf(key)
  for _, it in ipairs(ITEMS) do if it.key == key or it.optKey == key then return it end end
end
local function PageItems(...)
  local out = {}
  for _, keys in ipairs({ ... }) do
    for _, k in ipairs(keys) do
      local head = k:match("^header:(.+)$")
      if head then out[#out + 1] = { header = head } else out[#out + 1] = ItemOf(k) end
    end
  end
  return out
end

local function GamePages()
  local map = PageItems(MAP_MAIN, MAP_MORE)
  -- the preview of the pins has no place in the game's settings: DonCore's window shows it
  map[#map + 1] = { kind = "button", name = "Preview of the pins", button = "Show",
    tip = "Shows the pins in the chosen look, size and opacity in DonCore's options window.",
    onClick = function() if ns.OpenDonWindow then ns.OpenDonWindow("map") end end }
  return {
    { title = "Map", tip = "Who sees you on the map, and how the guild members look on the world map and the minimap.", items = map },
    { title = "Window", tip = "The minimap button of all Guildon parts and the place of the window.", items = PageItems(WINDOW_MAIN) },
  }
end
ns.GameOptionPages = GamePages -- (tests)

local function BuildGameOptions()
  category, fullPages = nil, false
  if not (ns.BuildSettings and ns.db and ns.db.blizzLook ~= false and ns.LookKit and select(2, ns.LookKit())) then return end
  category = ns.BuildSettings({ name = "Guildon: Map & Members", ownWindow = true, fullPages = true,
    status = Status, tools = Tools(), pages = GamePages(),
    db = function() return ns.db end, default = function(key) return ns.OPTION_DEFAULTS[key] end, changed = Changed,
    T = function(s) return L[s] end })
  fullPages = category ~= nil
end
ns.BuildGameOptions = BuildGameOptions -- (tests)

-- true when the game's settings were opened at Guildon (option blizzLook, pages built at login, not in combat)
function ns.OpenGameOptions()
  if not (ns.db and ns.db.blizzLook ~= false and fullPages and category and Settings and Settings.OpenToCategory) then return false end
  if InCombatLockdown and InCombatLockdown() then ns.Print(L["Not in combat."]) return true end
  Settings.OpenToCategory(category:GetID())
  return true
end
function ns.OptionsLook() return fullPages and "game settings" or "don window" end

-- DonCore's window at Guildon although the options are the game's (the preview of the pins)
function ns.OpenDonWindow(tab)
  if not (Opt and Opt.Open) then return nil end
  direct = true
  local win = ns.SafeCall("options window", Opt.OpenFromBlizzard or Opt.Open, ns.OPTIONS_ID, tab)
  direct = false
  return win
end

function ns.OpenOptions(tab)
  if Opt and Opt.Open then Opt.Open(ns.OPTIONS_ID, tab) return true end
end

ns.OnInit(function()
  ns.SafeCall("options", Register)
  ns.SafeCall("game options", BuildGameOptions)
end)
