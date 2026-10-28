local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Map (GUILDON_PLAN.md step 6): guild members with Guildon on the world map and the minimap, a dot in class colour
-- with the level. The game does not give out where guild members are, so every Guildon sends its own position:
--   P:<map>:<x>:<y>:<level>:<class>   x, y in ten-thousandths of the map; "P:0" = hidden now (instance, switched off)
--   W                                 "I show positions" (every 60 s while the world map is open or minimap dots are on)
-- Positions go out only while someone watches, at most every 4 s while moving, every 30 s standing; never in instances.
-- Privacy (decision 2: on by default): off, the guild, or only the own group; hidden while flagged for PvP (default).
---------------------------------------------------------------------------
local SEND_MOVING, SEND_STILL, WATCH_EVERY, WATCH_KEEP, POS_KEEP = 4, 30, 60, 150, 90
local MOVE_MIN = 0.002
local positions = {}   -- full name -> { map, x, y, level, class, t }
local watchers = {}    -- full name -> time of the last W
local last = { t = -100, map = nil, x = nil, y = nil, hidden = false, watchSent = -100 }

local function Mult(v) return math.max(0.25, math.min(2, tonumber(v) or 1)) end
local function DB()
  local db = ns.db
  if db.mapShare == nil then db.mapShare = "guild" end   -- "guild", "group", "off"
  if db.mapHidePvP == nil then db.mapHidePvP = true end
  if db.mapWorld == nil then db.mapWorld = true end
  if db.mapMinimap == nil then db.mapMinimap = true end
  if db.mapWorldScale == nil then db.mapWorldScale = 1 end -- (Daniel 26.10.) own size of the pins, 25 to 200 %
  db.mapFaces = nil -- (27.10.) the face pins are gone
  if db.mapMiniScale == nil then db.mapMiniScale = 1 end
  return db
end

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local CLASS_IDX = {}
for i, c in ipairs(CLASSES) do CLASS_IDX[c] = i end

---------------------------------------------------------------------------
-- Own position
---------------------------------------------------------------------------
function ns.PlayerMapPos()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = ns.Num(ns.Call(C_Map.GetBestMapForUnit, "player"))
  if not map then return nil end
  local pos = ns.Call(C_Map.GetPlayerMapPosition, map, "player")
  if type(pos) ~= "table" or not pos.GetXY then return nil end
  local ok, x, y = pcall(pos.GetXY, pos)
  if not ok or not (ns.Num(x) and ns.Num(y)) or (x == 0 and y == 0) then return nil end
  return map, x, y
end

local function InInstance()
  local inside, kind = ns.Call(IsInInstance)
  return inside == true or (kind ~= nil and kind ~= "none")
end

local function Hidden()
  local db = DB()
  if db.mapShare == "off" then return true end
  -- (Daniel 26.10.: "im Raid oder Dungeon standardmäßig aus, optional an") inside only with the switch
  if InInstance() and not db.mapInstance then return true end
  if db.mapHidePvP and ns.Call(UnitIsPVP, "player") == true then return true end
  return false
end

local function Channel()
  local db = DB()
  if db.mapShare == "group" then
    if ns.Call(IsInRaid) then return "RAID" end
    if ns.Call(IsInGroup) then return "PARTY" end
    return nil
  end
  return ns.InGuild() and "GUILD" or nil
end

local function Watched()
  local now = GetTime()
  for name, t in pairs(watchers) do
    if now - t > WATCH_KEEP then watchers[name] = nil else return true end
  end
  return false
end

local function Tick()
  local now = GetTime()
  local db = DB()
  -- watching: tell the others while the world map is open or minimap dots are on
  local want = (db.mapMinimap or (WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown())) and ns.InGuild()
  if want and now - last.watchSent >= WATCH_EVERY then
    last.watchSent = now
    ns.Send("W:", "GUILD")
  end
  local chat = Channel()
  if not chat or not Watched() then return end
  if Hidden() then
    if not last.hidden then
      last.hidden = true
      ns.Send("P:0", chat)
    end
    return
  end
  local map, x, y = ns.PlayerMapPos()
  if not map then return end
  local lay = ns.MyLayer and ns.MyLayer() or 0
  local moved = last.layer ~= lay or last.map ~= map or not last.x or math.abs(x - last.x) > MOVE_MIN or math.abs(y - last.y) > MOVE_MIN
  local due = (moved and now - last.t >= SEND_MOVING) or now - last.t >= SEND_STILL or last.hidden
  if not due then return end
  last.t, last.map, last.x, last.y, last.hidden, last.layer = now, map, x, y, false, lay
  local _, cls = ns.Call(UnitClass, "player")
  -- (27.10., Daniel: "das mit den Köpfen nehmen wir komplett heraus") no race and sex any more; messages of 0.7.0 that still
  -- carry them are read as before
  ns.Send(("P:%d:%d:%d:%d:%d:%d"):format(map, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5),
    ns.Num(ns.Call(UnitLevel, "player")) or 0, CLASS_IDX[cls or ""] or 0, ns.MyLayer and ns.MyLayer() or 0), chat)
end

ns.MSG.W = function(sender) watchers[sender] = GetTime() end
ns.MSG.P = function(sender, rest)
  if rest == "0" then positions[sender] = nil return end
  local map, x, y, lv, cls, layer = rest:match("^(%d+):(%d+):(%d+):(%d+):(%d+):?(%d*):?%d*:?%d*$")
  map, x, y, layer = tonumber(map), tonumber(x), tonumber(y), tonumber(layer)
  if not map or x > 10000 or y > 10000 then return end
  positions[sender] = { map = map, x = x / 10000, y = y / 10000, level = tonumber(lv), class = CLASSES[tonumber(cls)] or "", t = GetTime(),
    layer = layer and layer > 0 and layer or nil }
end

-- members on the map (demo members of /gn demo included), old positions dropped
function ns.Positions()
  local now = GetTime()
  local out = {}
  for name, p in pairs(positions) do
    if now - p.t > POS_KEEP or not ns.IsMember(name) then positions[name] = nil else out[name] = p end
  end
  for name, p in pairs(ns.DemoPositions and ns.DemoPositions() or {}) do out[name] = p end
  return out
end

function ns.MapState() return positions, watchers, last end -- (tests)

---------------------------------------------------------------------------
-- Position of a member on another map (the shown world map, the player's zone for the minimap)
---------------------------------------------------------------------------
local function WorldPos(map, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if not ok or not ns.Num(continent) or type(pos) ~= "table" or not pos.GetXY then return nil end
  local ok2, a, b = pcall(pos.GetXY, pos)
  if not ok2 or not (ns.Num(a) and ns.Num(b)) then return nil end
  return continent, a, b, pos
end
ns.MemberWorldPos = WorldPos

function ns.PosOnMap(p, shown)
  if p.map == shown then return p.x, p.y end
  local continent, _, _, pos = WorldPos(p.map, p.x, p.y)
  if not continent or not (C_Map and C_Map.GetMapPosFromWorldPos) then return nil end
  local ok, _, mp = pcall(C_Map.GetMapPosFromWorldPos, continent, pos, shown)
  if not ok or type(mp) ~= "table" or not mp.GetXY then return nil end
  local ok2, x, y = pcall(mp.GetXY, mp)
  if not ok2 or not (ns.Num(x) and ns.Num(y)) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end

---------------------------------------------------------------------------
-- Pins (own buttons): on the world map's canvas and on the minimap
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Layer (Daniel 25.10.): the zone part of a creature's GUID tells the layer (Creature-0-<server>-<instance>-<zoneUID>-
-- <npc>-<spawn>), read from target, mouse-over and name plates; kept per map, sent with the position. Layers are
-- numbered by sorting the IDs Guildon has seen on that map (own and the guild's), so "layer 2" means the same for all.
---------------------------------------------------------------------------
local myLayer = { map = nil, id = nil }
local layersSeen = {} -- map -> { [id] = true }

local function SeeLayer(map, id)
  if not map or not id then return end
  layersSeen[map] = layersSeen[map] or {}
  layersSeen[map][id] = true
end

function ns.ReadLayer(unit)
  local g = ns.Str(ns.Call(UnitGUID, unit))
  if not g then return nil end
  local kind, _, _, _, zone = g:match("^(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  zone = tonumber(zone)
  if not zone or zone == 0 then return nil end
  local map = ns.PlayerMapPos()
  if not map then return nil end
  myLayer.map, myLayer.id = map, zone
  SeeLayer(map, zone)
  return zone
end

function ns.MyLayer()
  local map = ns.PlayerMapPos()
  if map and myLayer.map == map then return myLayer.id end
end

-- number of a layer on a map (1, 2, ...), nil when unknown
function ns.LayerNumber(map, id)
  if not map or not id or not layersSeen[map] or not layersSeen[map][id] then return nil end
  local ids = {}
  for k in pairs(layersSeen[map]) do ids[#ids + 1] = k end
  table.sort(ids)
  for i, k in ipairs(ids) do if k == id then return i end end
end

ns.On("PLAYER_TARGET_CHANGED", function() ns.ReadLayer("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() ns.ReadLayer("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) ns.ReadLayer(unit) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() myLayer.map, myLayer.id = nil, nil end)

-- (Daniel 27.10.: "Option, ob das Layer mit angezeigt werden soll im Tooltip etc., Standard aus")
function ns.ShowLayer() return ns.db and ns.db.mapLayer and true or false end

local function LayerLine(p)
  if not p.layer then return "|cff9ea3ad" .. L["Layer: unknown"] .. "|r" end
  SeeLayer(p.map, p.layer)
  local n = ns.LayerNumber(p.map, p.layer)
  local mine = ns.MyLayer()
  local text = n and L["Layer %d"]:format(n) or L["Layer: unknown"]
  if mine and myLayer.map == p.map then
    if mine == p.layer then return "|cff4fd16a" .. text .. "  " .. L["(same as yours)"] .. "|r" end
    return "|cffff9a3c" .. text .. "  " .. L["(not yours)"] .. "|r"
  end
  return text
end
ns.LayerLine = LayerLine

---------------------------------------------------------------------------
-- Pins: a dot in the class colour with a dark rim and the level below; several members close together become one
-- pin with their number (Daniel 25.10.: "anders, wenn mehrere auf einem Haufen"). The look sits in PIN_LOOK, to be
-- tuned (Daniel asks Gemini).
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\Guildon\\Media\\"
ns.PIN_LOOK = {
  -- (25.10. abends, Daniel: "da soll das Map- und Minimap-Symbol werden") the guild's scales from his picture
  -- (tools/make_guildon_pins.py): PinFrame = scales, ring and spikes, PinDisk = the disk behind, tinted in the class colour
  frame = MEDIA .. "PinFrame", disk = MEDIA .. "PinDisk",
  -- (Daniel 25.10.: the scales only for Libra Vivendi) every other guild: a shield in the class colour with a black rim
  shieldFrame = MEDIA .. "ShieldFrame", shieldDisk = MEDIA .. "ShieldDisk",
  -- (26.10., Discord: Ari "zu wenig Klassenfarbe", Frankston "plain marker"; Daniel: "3 Optionen ... mit Klassenfarben und
  -- Vorschau in den Optionen") the scales as a sketch on a round disk, and a plain round dot (tools/make_guildon_pins.py)
  sketchFrame = MEDIA .. "SketchFrame", sketchDisk = MEDIA .. "SketchDisk",
  -- (27.10., Daniel: "dort vielleicht das Gildenzeichen in weiß drauf?") the dark pin of a mixed group: rim and white scales apart
  sketchRim = MEDIA .. "SketchRim", sketchMarks = MEDIA .. "SketchMarks",
  dotFrame = MEDIA .. "DotFrame", dotDisk = MEDIA .. "DotDisk",
  -- (Daniel 27.10.: "das Braun sieht wie vom Krieger aus, es darf sich nicht mit einer Klassenfarbe ähneln") a mixed group:
  -- dark anthracite with a white number; no class of Classic or Forever is dark (was gold, too close to the warrior)
  groupFill = { 0.17, 0.18, 0.20 },
  -- (Daniel 26.10.) the guild's own crest small in the middle of the shield, the class colour stays as the ring around it:
  -- crestSize = share of the pin, crestUp = how far it sits above the middle (the shield is wider at the top)
  crestSize = 0.52, crestUp = 0.05,
  -- (Daniel 26.10.: "die Pins einen Tick kleiner") was 26, 22, 32, 26; (27.10.: "der Pin kann dann gleich groß wie die anderen
  -- sein") a group as large as one member, its number "3x" below it like the level
  world = 22, mini = 19, groupWorld = 22, groupMini = 19,
  near = { world = 18, mini = 14 },                               -- pixels: closer than this is one group
}

ns.PIN_LEVEL = 2012 -- world map: above the tiles, below Questie (2015 lines, 2016 icons); see UpdateWorldPins

local function ColoredName(name, p)
  return "|c" .. ns.ClassHex(p.class) .. ns.ShortName(name) .. "|r"
end

local function Tooltip(self)
  local list = self.members
  if not list or #list == 0 then return end
  if #list == 1 then
    local m = list[1]
    local zone = C_Map and C_Map.GetMapInfo and ns.Call(C_Map.GetMapInfo, m.p.map)
    local lines = { L["Level %d"]:format(m.p.level or 0) }
    if type(zone) == "table" and ns.Str(zone.name) then lines[#lines + 1] = ns.Str(zone.name) end
    if ns.ShowLayer() then lines[#lines + 1] = LayerLine(m.p) end
    if m.name ~= ns.MyName() then lines[#lines + 1] = L["Shift-click: invite to your group"] end
    Style.Tooltip(self, ColoredName(m.name, m.p), lines, m.name ~= ns.MyName() and L["Click: whisper"] or nil)
    return
  end
  local lines = {}
  for _, m in ipairs(list) do lines[#lines + 1] = ns.MemberText(m) end
  Style.Tooltip(self, L["%d guild members here"]:format(#list), lines, L["Click: choose"])
end

function ns.MemberText(m)
  return ColoredName(m.name, m.p) .. "  |cff9ea3ad" .. (m.p.level or 0) .. "|r" .. (ns.ShowLayer() and ("  " .. LayerLine(m.p)) or "")
end

---------------------------------------------------------------------------
-- The pick list of a group pin (Daniel 26.10.: "wenn mehrere auf dem Haufen sind, nicht nur den 1. anwhispern, sondern eine
-- Auswahl"): a click on a group opens it, a click on a name whispers, a right-click shows Questdon's arrow. Own frame; a
-- see-through button behind it closes it by a click anywhere else, Esc closes it too.
---------------------------------------------------------------------------
local PICK_W, PICK_ROW, PICK_MAX = 270, 20, 20
local picker

local function HidePicker() if picker then picker:Hide() end end
ns.HidePicker = HidePicker

local function BuildPicker()
  local f = CreateFrame("Frame", "GuildonPinPicker", UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(20)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetWidth(PICK_W)
  ns.UI.Skin(f, Style.PAL.popup, { Style.COLORS.background[1], Style.COLORS.background[2], Style.COLORS.background[3], 0.97 })
  f.title = ns.UI.Text(f, "GameFontNormalSmall", 10, -8, PICK_W - 20, "gold")
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -25)
  line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -25)
  line:SetHeight(1)
  line:SetColorTexture(1, 1, 1, 0.08)
  f.rows = {}
  f.hint = ns.UI.Text(f, "GameFontHighlightSmall", 10, 0, PICK_W - 20, "textHint")
  f.hint:SetWordWrap(true)
  f.catcher = CreateFrame("Button", nil, UIParent)
  f.catcher:SetAllPoints(UIParent)
  f.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  f.catcher:SetFrameLevel(10)
  f.catcher:SetScript("OnClick", HidePicker)
  f.catcher:Hide()
  f:SetScript("OnShow", function(self) self.catcher:Show() end)
  f:SetScript("OnHide", function(self) self.catcher:Hide() end)
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildonPinPicker") end
  return f
end

local function PickRow(f, i)
  local r = f.rows[i]
  if r then return r end
  r = ns.UI.FlatButton(f, PICK_W - 20, PICK_ROW, "")
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.label:ClearAllPoints()
  r.label:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.label:SetWidth(PICK_W - 32)
  r.label:SetJustifyH("LEFT")
  r:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30 - (i - 1) * PICK_ROW)
  r:SetScript("OnClick", function(self, button)
    local name = self.member
    if not name or name == ns.MyName() then return end
    if button == "RightButton" then
      if ns.ArrowTo and ns.ArrowTo(name) then HidePicker() end
    else
      if IsShiftKeyDown and IsShiftKeyDown() then ns.InviteMember(name)
      elseif ns.WhisperCrafter then ns.WhisperCrafter(name) end
      HidePicker()
    end
  end)
  f.rows[i] = r
  return r
end

function ns.ShowPicker(pin)
  local list = pin and pin.members
  if not list or #list < 2 then return end
  if not picker then picker = BuildPicker() end
  local f = picker
  local n = math.min(#list, PICK_MAX)
  f.title:SetText(L["%d guild members here"]:format(#list))
  for i = 1, n do
    local r = PickRow(f, i)
    r.member = list[i].name
    r.label:SetText(ns.MemberText(list[i]))
    r:SetAlpha(list[i].name == ns.MyName() and 0.5 or 1)
    r:Show()
  end
  for i = n + 1, #f.rows do f.rows[i]:Hide() end
  local hint = L["Click: whisper"] .. "\n" .. L["Shift-click: invite to your group"]
  if QuestdonAPI then hint = hint .. "\n" .. L["Right-click: Questdon's arrow to this member"] end
  f.hint:ClearAllPoints()
  f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30 - n * PICK_ROW - 6)
  f.hint:SetText(hint)
  f:SetHeight(30 + n * PICK_ROW + 6 + (QuestdonAPI and 39 or 26) + 8)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", pin, "BOTTOMRIGHT", 2, 2)
  f:Show()
end


local function NewPin(parent, size)
  local look = ns.PIN_LOOK
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.dot = b:CreateTexture(nil, "ARTWORK")
  b.dot:SetAllPoints()
  b.dot:SetTexture(look.disk)
  -- the guild's crest on top of the disk (background colour tile, then the emblem), below the rim
  b.crestBg = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.crestBg:Hide()
  b.crest = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.crest:Hide()
  b.rim = b:CreateTexture(nil, "OVERLAY")
  b.rim:SetAllPoints()
  b.rim:SetTexture(look.frame)
  -- the guild sign in white on the dark pin of a mixed group (27.10.)
  b.mark = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.mark:SetAllPoints()
  b.mark:SetTexture(look.sketchMarks)
  b.mark:SetVertexColor(1, 1, 1)
  b.mark:Hide()
  b.level = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.level:SetPoint("TOP", b, "BOTTOM", 0, 2)
  -- (Daniel 26.10.: "die Levelzahl vielleicht noch schwarz umranden?") a black outline, readable on every map
  -- (Daniel 27.10.: "wieso ist die Levelzahl so krumm und schief") a whole font size, the outline plus a shadow, and
  -- the pins themselves on whole pixels (UpdateWorldPins, UpdateMiniPins): half pixels made the outline uneven
  local okF, path, size = pcall(b.level.GetFont, b.level)
  if okF and path and size then pcall(b.level.SetFont, b.level, path, math.max(10, math.floor(size + 0.5)), "OUTLINE") end
  if b.level.SetShadowColor then pcall(b.level.SetShadowColor, b.level, 0, 0, 0, 1) pcall(b.level.SetShadowOffset, b.level, 1, -1) end
  -- a small dark badge with the number of a group, bottom right
  b.badge = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.badge:SetColorTexture(0.08, 0.07, 0.06, 0.9)
  b.badge:SetSize(14, 12)
  b.badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -2)
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.count:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
  b:SetScript("OnEnter", Tooltip)
  b:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  b:SetScript("OnClick", function(self)
    local list = self.members
    if list and #list > 1 then Style.HideTooltip(self) ns.ShowPicker(self) return end -- a group: choose
    local m = list and list[1]
    if not m or m.name == ns.MyName() then return end
    if IsShiftKeyDown and IsShiftKeyDown() then ns.InviteMember(m.name) -- Shift: invite to the group
    elseif ns.WhisperCrafter then ns.WhisperCrafter(m.name) end
  end)
  return b
end

-- the scales for the guild whose emblem they are, the shield for all others
-- (Daniel 26.10.) the player picks the look in the Map tab (ns.db.pinStyle): "emblem" = the guild's sign (the scales as a
-- sketch in Libra Vivendi, the shield with the game's crest in every other guild; default), "shield" = only the shield,
-- "dot" = a plain dot. Every look is tinted in the class colour.
ns.PIN_STYLES = { "emblem", "shield", "dot" }
function ns.PinStyle()
  local v = ns.db and ns.db.pinStyle
  if v == "shield" or v == "dot" then return v end
  return "emblem"
end
function ns.PinTextures(style)
  local look = ns.PIN_LOOK
  style = style or ns.PinStyle()
  if style == "dot" then return look.dotFrame, look.dotDisk, "dot" end
  if style == "shield" then return look.shieldFrame, look.shieldDisk, "plain" end
  if ns.OwnEmblemFile and ns.OwnEmblemFile() then return look.sketchFrame, look.sketchDisk, "libra" end
  return look.shieldFrame, look.shieldDisk, "shield"
end

-- the crest for the pins of this round: the game's tabard of your guild (emblem file, emblem colour, background colour), only on
-- the shield; nil where the scales are or the game has no tabard for the guild. Looked up once per update, not once per pin.
local crest
local function CrestNow(style)
  crest = nil
  if select(3, ns.PinTextures(style)) ~= "shield" or not ns.GameEmblem then return end
  local file, r, g, b, br, bgc, bb = ns.GameEmblem()
  if file then crest = { file = file, r = r, g = g, b = b, br = br, bg = bgc, bb = bb } end
end

-- paint a pin for one member or a group; size = the pin's base size
-- (Daniel 27.10.) the opacity of the pins, from the Map tab (20 to 100 %)
function ns.PinAlpha()
  local v = ns.db and tonumber(ns.db.mapPinAlpha)
  if not v then return 1 end
  return math.max(0.2, math.min(1, v))
end

local function Paint(b, members, size, groupSize, opts)
  local look = ns.PIN_LOOK
  b:SetAlpha(ns.PinAlpha())
  local frame, disk, style = ns.PinTextures(opts and opts.style)
  if b.style ~= style then
    b.dot:SetTexture(disk)
    b.style = style
    b.rimFile = nil
  end
  b.members = members
  local one = members[1]
  b.name, b.pos = one.name, one.p -- (tests, single pins)
  if #members == 1 then
    b.dark = false
    b:SetSize(size, size)
    local r, g, bl = ns.ClassRGB(one.p.class)
    b.dot:SetVertexColor(r or 0.9, g or 0.9, bl or 0.9)
    b.level:SetText(one.p.level and one.p.level > 0 and tostring(one.p.level) or "")
    b.count:SetText("")
    b.badge:Hide()
  else
    b:SetSize(groupSize, groupSize)
    -- one class: its colour; mixed: anthracite
    local same = true
    for _, m in ipairs(members) do if m.p.class ~= one.p.class then same = false end end
    local r, g, bl = ns.ClassRGB(one.p.class)
    if same and r then b.dot:SetVertexColor(r, g, bl) else b.dot:SetVertexColor(look.groupFill[1], look.groupFill[2], look.groupFill[3]) end
    b.dark = not (same and r) -- (27.10.) the sign shows white on it
    -- (Daniel 27.10.: "den schwarzen Kasten weg, vielleicht einfach die Zahl mit x dahinter, also 3x für 3 Spieler") below the
    -- pin where a member's level stands
    b.count:SetText("")
    b.badge:Hide()
    b.level:SetText(L["%dx"]:format(#members))
  end
  -- (27.10.) on the dark pin of a mixed group the guild's sign is white: the scales of Libra Vivendi as white strokes on a
  -- black rim, the game's crest of any other guild white without its background
  local dark = #members > 1 and b.dark
  local rimFile = (dark and style == "libra") and look.sketchRim or frame
  if b.rimFile ~= rimFile then b.rim:SetTexture(rimFile) b.rimFile = rimFile end
  b.mark:SetShown(dark and style == "libra" or false)
  if crest and style == "shield" then
    local s = (#members == 1 and size or groupSize) * look.crestSize
    for _, t in ipairs({ b.crestBg, b.crest }) do
      t:SetSize(s, s)
      t:ClearAllPoints()
      t:SetPoint("CENTER", b, "CENTER", 0, s * look.crestUp / look.crestSize)
    end
    b.crest:SetTexture(crest.file)
    if dark then b.crest:SetVertexColor(1, 1, 1) else b.crest:SetVertexColor(crest.r, crest.g, crest.b) end
    b.crest:Show()
    if crest.br and not dark then b.crestBg:SetColorTexture(crest.br, crest.bg, crest.bb, 0.95) b.crestBg:Show() else b.crestBg:Hide() end
  else
    b.crest:Hide()
    b.crestBg:Hide()
  end
end

-- (Daniel 26.10.: "Vorschau in den Optionen") a pin that only shows a look: no tooltip, no click. members as in Paint,
-- opts.style picks the look (nil = the chosen one)
function ns.PreviewPin(parent, size)
  local b = NewPin(parent, size)
  b:SetScript("OnEnter", nil)
  b:SetScript("OnLeave", nil)
  b:SetScript("OnClick", nil)
  if b.EnableMouse then b:EnableMouse(false) end
  return b
end
function ns.PaintPreview(b, members, size, groupSize, style)
  CrestNow(style)
  Paint(b, members, size, groupSize, { style = style })
end

-- members closer than "near" pixels become one group; input { { name, p, x, y } } in pixels
function ns.GroupPins(points, near)
  table.sort(points, function(a, b) return a.name < b.name end)
  local groups = {}
  for _, pt in ipairs(points) do
    local hit
    for _, g in ipairs(groups) do
      if (g.x - pt.x) ^ 2 + (g.y - pt.y) ^ 2 <= near * near then hit = g break end
    end
    if hit then
      table.insert(hit.members, pt)
      local n = #hit.members
      hit.x, hit.y = hit.x + (pt.x - hit.x) / n, hit.y + (pt.y - hit.y) / n
    else
      groups[#groups + 1] = { x = pt.x, y = pt.y, members = { pt } }
    end
  end
  return groups
end

local worldPins, miniPins = {}, {}

local function Canvas()
  local f = WorldMapFrame
  local sc = f and f.ScrollContainer
  return sc and sc.Child, sc
end

-- what the last look at the open world map found, for /gn diag ("members on the minimap but not on the world map")
local worldState
function ns.WorldPinState() return worldState end

local function Ask(f, method)
  if f and f[method] then
    local ok, v = pcall(f[method], f)
    if ok then return v end
  end
end

-- (27.10.) /gn diag: frame levels of the pins of Questie (HereBeDragons) and GatherMate2 on the open world map and on the
-- minimap, next to ours. Read only.
local function Range(lo, hi, n, lv)
  if not lv then return lo, hi, n end
  return (lo and math.min(lo, lv) or lv), (hi and math.max(hi, lv) or lv), n + 1
end
function ns.ForeignPinLevels()
  local out = {}
  local wm = WorldMapFrame
  if wm and wm.EnumeratePinsByTemplate and wm.IsShown and wm:IsShown() then
    for _, tpl in ipairs({ "HereBeDragonsPinsTemplateQuestie", "HereBeDragonsPinsTemplate", "GatherMate2WorldMapPinTemplate" }) do
      local lo, hi, n, clo, chi, cn = nil, nil, 0, nil, nil, 0
      local ok = pcall(function()
        for pin in wm:EnumeratePinsByTemplate(tpl) do
          lo, hi, n = Range(lo, hi, n, Ask(pin, "GetFrameLevel"))
          if pin.icon then clo, chi, cn = Range(clo, chi, cn, Ask(pin.icon, "GetFrameLevel")) end
        end
      end)
      if ok and n > 0 then
        out[#out + 1] = ("world %s: %d pins, level %s to %s%s"):format(tpl, n, tostring(lo), tostring(hi),
          cn > 0 and (", icons %s to %s"):format(tostring(clo), tostring(chi)) or "")
      end
    end
  end
  if Minimap and Minimap.GetChildren then
    local lo, hi, n, glo, ghi, gn = nil, nil, 0, nil, nil, 0
    for _, c in ipairs({ Minimap:GetChildren() }) do
      local name = Ask(c, "GetName")
      if type(name) == "string" and name:find("^GatherMatePin") and Ask(c, "IsShown") then
        glo, ghi, gn = Range(glo, ghi, gn, Ask(c, "GetFrameLevel"))
      elseif c.data or c.miniMapIcon then -- Questie's icon frames carry their data
        if Ask(c, "IsShown") then lo, hi, n = Range(lo, hi, n, Ask(c, "GetFrameLevel")) end
      end
    end
    local mine = miniPins and miniPins[1] and Ask(miniPins[1], "GetFrameLevel")
    out[#out + 1] = ("minimap level %s, ours %s, Questie %d (%s to %s), GatherMate %d (%s to %s)"):format(
      tostring(Ask(Minimap, "GetFrameLevel")), tostring(mine), n, tostring(lo), tostring(hi), gn, tostring(glo), tostring(ghi))
  end
  return out
end

-- (27.10., Daniel's /gn diag on Era: canvas level 3, Questie's icons 2021, GatherMate on the minimap at minimap + 5)
-- The world map hands out pin levels itself (its frame level manager); GatherMate and Questie's HereBeDragons frames use
-- the type PIN_FRAME_LEVEL_AREA_POI on the world map (GatherMate only uses the minimap).
local function TypeLevel(mgr, t)
  if not mgr or type(mgr.GetValidFrameLevel) ~= "function" then return nil end
  local ok, v = pcall(mgr.GetValidFrameLevel, mgr, t)
  return ok and type(v) == "number" and v or nil
end
function ns.MapLevels()
  local wm = WorldMapFrame
  local mgr = wm and type(wm.GetPinFrameLevelsManager) == "function" and select(2, pcall(wm.GetPinFrameLevelsManager, wm)) or nil
  if type(mgr) ~= "table" then mgr = nil end
  return TypeLevel(mgr, "PIN_FRAME_LEVEL_MAP_EXPLORATION"), TypeLevel(mgr, "PIN_FRAME_LEVEL_AREA_POI")
end
-- (27.10., Daniel: "gathermate nimmt die weltkarte nicht, so passt das schon gut") the tested fixed level stays;
-- the manager's levels are only shown in /gn diag
function ns.WorldPinLevel(canvasLevel)
  return math.max(ns.PIN_LEVEL, (canvasLevel or 0) + 1)
end

function ns.UpdateWorldPins()
  local db = DB()
  CrestNow()
  local look = ns.PIN_LOOK
  local canvas, sc = Canvas()
  local shown = db.mapWorld and WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
  if not shown or not canvas then for _, b in ipairs(worldPins) do b:Hide() end HidePicker() return 0 end
  local map = ns.Num(ns.Call(WorldMapFrame.GetMapID, WorldMapFrame))
  local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
  local scale = math.max(0.2, sc and sc.GetCanvasScale and ns.Num(ns.Call(sc.GetCanvasScale, sc)) or 1)
  local ps = scale / Mult(db.mapWorldScale) -- (Daniel 26.10.) the player's own pin size, the groups grow with it
  local n = 0
  local have, onMap = 0, 0
  if map and w > 0 then
    local points = {}
    for name, p in pairs(ns.Positions()) do
      have = have + 1
      local x, y = ns.PosOnMap(p, map)
      if x then points[#points + 1] = { name = name, p = p, x = x * w, y = y * h } end
    end
    onMap = #points
    -- whole screen pixels: the canvas is drawn at "scale", so a size or place of k / scale is k pixels on the screen
    local function Px(v) return math.floor(v * scale + 0.5) / scale end
    local sizeW, sizeG = Px(look.world / ps), Px(look.groupWorld / ps)
    for _, g in ipairs(ns.GroupPins(points, look.near.world / ps)) do
      n = n + 1
      local b = worldPins[n] or NewPin(canvas, sizeW)
      worldPins[n] = b
      -- (27.10., Frankston: our pins hid Questie's and Gatherer's marks) above the map's tiles, below the other addons:
      -- Questie puts its icons at the fixed level 2016 and up and its lines at 2015 (it counts the scroll container from
      -- 2000); our pins sit just below at PIN_LEVEL, or one above the canvas if that is higher already. Before 27.10. canvas
      -- plus 2000, which was above everything. To be checked in the game with /gn diag (Elwynn zone map).
      local lv = Ask(canvas, "GetFrameLevel")
      local want = ns.WorldPinLevel(lv)
      if lv and b.lvl ~= want and b.SetFrameLevel then
        b.lvl = want
        if b.SetFixedFrameLevel then pcall(b.SetFixedFrameLevel, b, false) end
        pcall(b.SetFrameLevel, b, want)
        if b.SetFixedFrameLevel then pcall(b.SetFixedFrameLevel, b, true) end
      end
      Paint(b, g.members, sizeW, sizeG)
      b:ClearAllPoints()
      b:SetPoint("CENTER", canvas, "TOPLEFT", Px(g.x), -Px(g.y))
      b:Show()
    end
  end
  for i = n + 1, #worldPins do worldPins[i]:Hide() end
  local first = worldPins[1]
  local mine = ns.PlayerMapPos()
  worldState = { map = map, mine = mine, w = w, h = h, scale = scale, have = have, onMap = onMap, pins = n,
    vis = first and Ask(first, "IsVisible"), alpha = first and Ask(first, "GetEffectiveAlpha"), size = first and Ask(first, "GetWidth"),
    level = first and Ask(first, "GetFrameLevel"), canvasLevel = Ask(canvas, "GetFrameLevel") }
  worldState.expl, worldState.poi = ns.MapLevels()
  return n
end

local function Facing()
  local v
  if C_CVar and C_CVar.GetCVar then v = ns.Call(C_CVar.GetCVar, "rotateMinimap") elseif GetCVar then v = ns.Call(GetCVar, "rotateMinimap") end
  if v ~= "1" and v ~= 1 and v ~= true then return nil end
  return ns.Num(ns.Call(GetPlayerFacing))
end

local DIAMETER = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local function Radius()
  if C_Minimap and C_Minimap.GetViewRadius then
    local r = ns.Num(ns.Call(C_Minimap.GetViewRadius))
    if r and r > 0 then return r end
  end
  local zoom = Minimap and ns.Num(ns.Call(Minimap.GetZoom, Minimap)) or 0
  return DIAMETER[math.max(0, math.min(5, math.floor(zoom)))] / 2
end

function ns.UpdateMiniPins()
  local db = DB()
  CrestNow()
  if not db.mapMinimap or not Minimap or (Minimap.IsVisible and not Minimap:IsVisible()) or (InInstance() and not db.mapInstance) then
    for _, b in ipairs(miniPins) do b:Hide() end
    return 0
  end
  local map, mx, my = ns.PlayerMapPos()
  local c0, n0, w0 = nil, nil, nil
  if map then c0, n0, w0 = WorldPos(map, mx, my) end
  local n = 0
  if c0 then
    local radius = Radius()
    local half = (Minimap:GetWidth() or 140) / 2
    local facing = Facing()
    local points = {}
    for name, p in pairs(ns.Positions()) do
      if name ~= ns.MyName() then
        local c, pn, pw = WorldPos(p.map, p.x, p.y)
        if c == c0 then
          local dNorth, dEast = pn - n0, -(pw - w0)
          local x, y = dEast, dNorth
          if facing then
            local cs, sn = math.cos(facing), math.sin(facing)
            x, y = dEast * cs + dNorth * sn, -dEast * sn + dNorth * cs
          end
          x, y = x * half / radius, y * half / radius
          if x * x + y * y <= (half - 4) ^ 2 then points[#points + 1] = { name = name, p = p, x = x, y = y } end
        end
      end
    end
    local look = ns.PIN_LOOK
    local m = Mult(db.mapMiniScale) -- (Daniel 26.10.) the player's own pin size on the minimap
    for _, g in ipairs(ns.GroupPins(points, look.near.mini * m)) do
      n = n + 1
      local sizeM, sizeMG = math.floor(look.mini * m + 0.5), math.floor(look.groupMini * m + 0.5)
      local b = miniPins[n] or NewPin(Minimap, sizeM)
      miniPins[n] = b
      Paint(b, g.members, sizeM, sizeMG)
      b:ClearAllPoints()
      b:SetPoint("CENTER", Minimap, "CENTER", math.floor(g.x + 0.5), math.floor(g.y + 0.5))
      b:Show()
    end
  end
  for i = n + 1, #miniPins do miniPins[i]:Hide() end
  return n
end

function ns.MapPins() return worldPins, miniPins end -- (tests)

-- one frame of our own drives sending (1 s) and the pins (0.2 s)
local driver = CreateFrame("Frame")
local acc, accSend = 0, 0
driver:SetScript("OnUpdate", function(_, dt)
  if not ns.db then return end
  acc, accSend = acc + dt, accSend + dt
  if accSend >= 1 then accSend = 0 ns.SafeCall("map send", Tick) end
  if acc >= 0.2 then
    acc = 0
    ns.SafeCall("world pins", ns.UpdateWorldPins)
    ns.SafeCall("minimap pins", ns.UpdateMiniPins)
  end
end)

-- open the world map on a member's zone
function ns.ShowOnMap(name)
  local p = ns.Positions()[name]
  if not p then return false end
  if OpenWorldMap then ns.Call(OpenWorldMap, p.map) return true end
  if WorldMapFrame and WorldMapFrame.SetMapID then
    if not WorldMapFrame:IsShown() and ToggleWorldMap then ns.Call(ToggleWorldMap) end
    ns.Call(WorldMapFrame.SetMapID, WorldMapFrame, p.map)
    return true
  end
end

ns.OnInit(function() DB() end)
