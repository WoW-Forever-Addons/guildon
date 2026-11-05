local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Guildon's options in DonCore's shared options window (StyleKit 2 step 4, 02.11.2026; mockup part 6): the settings of the
-- old Map tab and the old Options tab. The cog in the window's header, /gn options and the Blizzard AddOns page open it.
-- Tabs: Map (sharing, pins, sizes, opacity, layer, with a preview of the pins), Window (minimap button, place), Tools
-- (status, example guild, sync, commands).
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
}

local function Percent(v) return ("%d %%"):format(math.floor((tonumber(v) or 0) * 100 + 0.5)) end

local function Pins()
  if ns.UpdateWorldPins then ns.SafeCall("pins", ns.UpdateWorldPins) end
  if ns.UpdateMiniPins then ns.SafeCall("pins", ns.UpdateMiniPins) end
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
        main = { "header:Sharing", "mapShare", "mapHidePvP", "mapInstance", "header:Pins", "mapWorld", "mapMinimap", "pinStyle",
          "mapWorldScale", "mapMiniScale", "mapPinAlpha" }, more = { "mapArrow", "mapLayer" } },
      { key = "window", title = "Window", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
        text = "The minimap button of all Guildon parts and the place of the window.",
        main = { "minimapButton", "button:resetWindow" } },
      { key = "tools", title = "Tools", text = "Status", status = true, tools = { "Example guild", "Sync" } },
    },
    pages = function() return { { items = ITEMS } } end,
    tools = function() return {
      { "Example guild", "On / off", function() if ns.SetDemo then ns.SetDemo(not ns.demo) end end,
        "Made-up members to try the windows, only on your screen.", state = function() return ns.demo and true or false end },
      { "Sync", "Ask now", function() if ns.Hello then ns.Hello(true) end ns.Print(L["Asked the guild for new data."]) end,
        "Asks the guild for new data now." },
    } end,
    db = function() return ns.db end,
    default = function(key) return ns.OPTION_DEFAULTS[key] end,
    changed = function(key)
      if key == "mapArrow" and ns.ArrowStop then ns.ArrowStop() end -- the next right-click uses the new arrow
      if key == "minimapButton" then if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
      elseif key and key:find("^map") or key == "pinStyle" then Pins() end
      if ns.Refresh then ns.Refresh() end
    end,
    status = function()
      local total, online, guildon = ns.MemberCounts()
      return { ("Guildon %s"):format(tostring(ns.VERSION or "")),
        ns.InGuild() and L["%d members"]:format(total) .. ", " .. L["online: %d"]:format(online) .. ", " .. L["With Guildon"] .. ": " .. guildon
          or L["You are not in a guild."] }
    end,
    help = function()
      local lines = {}
      for _, c in ipairs(ns.COMMANDS or {}) do lines[#lines + 1] = c[1] .. "  " .. L[c[2]] end
      return table.concat(lines, "\n")
    end,
    T = function(s) return L[s] end,
    labels = function(s) return L[s] end,
  })
end

function ns.OpenOptions(tab)
  if Opt and Opt.Open then Opt.Open(ns.OPTIONS_ID, tab) return true end
end

ns.OnInit(function() ns.SafeCall("options", Register) end)
