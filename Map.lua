local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Map (GUILDON_PLAN.md step 6): guild members with Guildon on the world map and the minimap, a dot in class colour
-- with the level. The game does not give out where guild members are, so every Guildon sends its own position:
--   P:<map>:<x>:<y>:<level>:<class>   x, y in ten-thousandths of the map; "P:0" = hidden now (instance, switched off)
--   W                                 "I show positions": the world map is open (every 60 s while it is)
--   W:m:<map>:<x>:<y>                 "I show minimap dots here" (every 120 s, and after MINI_MOVE yards)
-- Positions go out only while someone watches, at most every 4 s while moving, every 60 s standing; never in instances.
-- (31.10.2026, LEISTUNG_PRUEFUNG A2) A minimap watcher only gets positions from members within MINI_RANGE yards of him;
-- an older Guildon reads every W as "show positions", and a plain W (older Guildon) still means everyone sends.
-- Privacy (decision 2: on by default): off, the guild, or only the own group; hidden while flagged for PvP (default).
---------------------------------------------------------------------------
-- (31.10.2026) standing 60 s (was 30); POS_KEEP 150 (was 90; an older Guildon keeps 90, still above 60)
local SEND_MOVING, SEND_STILL, WATCH_EVERY, WATCH_KEEP, POS_KEEP = 4, 60, 60, 150, 150
local MINI_EVERY, MINI_MOVE, MINI_RANGE = 120, 400, 800 -- yards; range = minimap reach plus how far he may walk between two W
local MOVE_MIN = 0.002
local positions = {}   -- full name -> { map, x, y, level, class, t }
local watchers = {}    -- full name -> { t = time of the last W, c, n, w = his world position (nil: the world map, all) }
local version = 0      -- (31.10.2026, A1) counts every change of the positions; the pins are built anew only then
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

local function WorldNow()
  local map, x, y = ns.PlayerMapPos()
  if not map or not (DonMapAPI and DonMapAPI.WorldPos) then return nil end
  return DonMapAPI.WorldPos(map, x, y)
end

-- someone shows positions: a world map anywhere, or minimap dots near enough
local function Watched()
  local now = GetTime()
  local c0, n0, w0
  for name, v in pairs(watchers) do
    if now - v.t > WATCH_KEEP then watchers[name] = nil
    elseif not v.c then return true
    else
      if c0 == nil then c0, n0, w0 = WorldNow() c0 = c0 or false end
      if c0 and v.c == c0 and (v.n - n0) ^ 2 + (v.w - w0) ^ 2 < MINI_RANGE ^ 2 then return true end
    end
  end
  return false
end

-- tell the guild what this client shows: a plain W while the world map is open, W:m with the place for minimap dots
local function SendWatch(now, db)
  if not ns.InGuild() then return end
  if db.mapWorld and WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
    if last.watchKind ~= "world" or now - last.watchSent >= WATCH_EVERY then
      last.watchKind, last.watchSent = "world", now
      ns.Send("W:", "GUILD")
    end
    return
  end
  if not db.mapMinimap or (InInstance() and not db.mapInstance) then last.watchKind = nil return end
  local map, x, y = ns.PlayerMapPos()
  local c, n, w
  if map and DonMapAPI and DonMapAPI.WorldPos then c, n, w = DonMapAPI.WorldPos(map, x, y) end
  if not (c and n and w) then -- no place known: the old way, everyone sends
    if now - last.watchSent >= WATCH_EVERY then last.watchKind, last.watchSent = "all", now ns.Send("W:", "GUILD") end
    return
  end
  local moved = last.wc ~= c or (n - last.wn) ^ 2 + (w - last.ww) ^ 2 > MINI_MOVE ^ 2
  local switched = last.watchKind ~= "mini" and now - last.watchSent >= 10
  if moved or switched or now - last.watchSent >= MINI_EVERY then
    last.watchKind, last.watchSent, last.wc, last.wn, last.ww = "mini", now, c, n, w
    ns.Send(("W:m:%d:%d:%d"):format(map, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5)), "GUILD")
  end
end

local function Tick()
  local now = GetTime()
  local db = DB()
  -- watching: tell the others while the world map is open or minimap dots are on
  SendWatch(now, db)
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

ns.MSG.W = function(sender, rest)
  local v = watchers[sender]
  if not v then v = {} watchers[sender] = v end
  v.t, v.c, v.n, v.w = GetTime(), nil, nil, nil
  local map, x, y = (rest or ""):match("^m:(%d+):(%d+):(%d+)$")
  if map and DonMapAPI and DonMapAPI.WorldPos then -- an unknown place counts as the world map: everyone sends
    v.c, v.n, v.w = DonMapAPI.WorldPos(tonumber(map), tonumber(x) / 10000, tonumber(y) / 10000)
    if not (v.n and v.w) then v.c = nil end
  end
end
-- (31.10.2026, A1) one table per member, filled anew; the version only moves when something on the pin changed
ns.MSG.P = function(sender, rest)
  if rest == "0" then
    if positions[sender] then positions[sender] = nil version = version + 1 end
    return
  end
  local map, x, y, lv, cls, layer = rest:match("^(%d+):(%d+):(%d+):(%d+):(%d+):?(%d*):?%d*:?%d*$")
  map, x, y, layer = tonumber(map), tonumber(x), tonumber(y), tonumber(layer)
  if not map or x > 10000 or y > 10000 then return end
  x, y, lv, cls, layer = x / 10000, y / 10000, tonumber(lv), CLASSES[tonumber(cls)] or "", layer and layer > 0 and layer or nil
  local p = positions[sender]
  if not p then p = {} positions[sender] = p end
  if p.map ~= map or p.x ~= x or p.y ~= y or p.level ~= lv or p.class ~= cls or p.layer ~= layer then version = version + 1 end
  p.map, p.x, p.y, p.level, p.class, p.layer, p.t = map, x, y, lv, cls, layer, GetTime()
end

-- old positions and those of members who left go; once a second, without new tables
local function Expire()
  local now = GetTime()
  for name, p in pairs(positions) do
    if now - p.t > POS_KEEP or not ns.IsMember(name) then positions[name] = nil version = version + 1 end
  end
end

-- members on the map (demo members of /gn demo included), old positions dropped
function ns.Positions()
  Expire()
  local out = {}
  for name, p in pairs(positions) do out[name] = p end
  for name, p in pairs(ns.DemoPositions and ns.DemoPositions() or {}) do out[name] = p end
  return out
end

function ns.MapState() return positions, watchers, last end -- (tests)

---------------------------------------------------------------------------
-- Position of a member on another map (the shown world map): DonMap's geometry (DONCORE_PLAN.md "DonMap", 30.10.2026)
---------------------------------------------------------------------------
function ns.PosOnMap(p, shown)
  if not DonMapAPI then return nil end
  return DonMapAPI.PosOnMap(p.map, p.x, p.y, shown)
end

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

ns.PIN_LEVEL = 2012 -- world map: above the tiles, below Questie (2015 lines, 2016 icons); DonMap's layer 2 (Layers.lua)

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
      elseif ns.WhisperMember then ns.WhisperMember(name) end
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
  local arrow = ns.CanArrow and ns.CanArrow()
  if arrow then hint = hint .. "\n" .. L["Right-click: arrow to this member"] end
  f.hint:ClearAllPoints()
  f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30 - n * PICK_ROW - 6)
  f.hint:SetText(hint)
  f:SetHeight(30 + n * PICK_ROW + 6 + (arrow and 39 or 26) + 8)
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
    elseif ns.WhisperMember then ns.WhisperMember(m.name) end
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

---------------------------------------------------------------------------
-- (DonMap M1, 30.10.2026) DonMap draws the pins: Guildon registers the source "guildon" with its own pin (NewPin) and
-- look (Paint), its sizes and grouping distance (PIN_LOOK times the player's pin size), and hands over the positions.
-- DonMap places them on the world map and the minimap, groups them, keeps them on whole pixels and on their level.
-- Sending, privacy, tooltip, pick list and the look stay here.
---------------------------------------------------------------------------
local src

local function Source()
  if src or not DonMapAPI then return src end
  src = DonMapAPI.Register("guildon", {
    title = "Guildon",
    layer = 2, -- world map 2012 (ns.PIN_LEVEL)
    world = function() return DB().mapWorld end,
    -- (Daniel 26.10.) dungeons and raids: minimap off by default, on with the switch
    minimap = function() local db = DB() return db.mapMinimap and not (InInstance() and not db.mapInstance) end,
    -- (Daniel 26.10.) everyone sets the pin size himself, the groups grow with it
    size = function(where)
      local look, db = ns.PIN_LOOK, DB()
      if where == "world" then local m = Mult(db.mapWorldScale) return look.world * m, look.groupWorld * m end
      local m = Mult(db.mapMiniScale)
      return look.mini * m, look.groupMini * m
    end,
    group = function(where)
      local db = DB()
      if where == "world" then return ns.PIN_LOOK.near.world * Mult(db.mapWorldScale) end
      return ns.PIN_LOOK.near.mini * Mult(db.mapMiniScale)
    end,
    newPin = function(parent, size) return NewPin(parent, size) end,
    paint = function(b, members, size, groupSize) Paint(b, members, size, groupSize) end,
  })
  return src
end

-- the members on the map as DonMap points (the member's own data stays on the point: name, p); not myself on the minimap
local function Points()
  local list, me = {}, ns.MyName()
  for name, p in pairs(ns.Positions()) do
    list[#list + 1] = { mapID = p.map, x = p.x, y = p.y, key = name, name = name, p = p, minimap = name ~= me,
      sig = (p.level or 0) .. (p.class or "") .. (p.layer or "") }
  end
  return list
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

-- (27.10.) /gn diag: frame levels of the pins of Questie and GatherMate2 next to ours, and the world map's own levels
function ns.ForeignPinLevels() return DonMapAPI and DonMapAPI.ForeignPinLevels() or {} end
function ns.MapLevels() if DonMapAPI then return DonMapAPI.MapLevels() end end

-- (31.10.2026) filled in place while the world map is open (was a new table five times a second)
local function NoteWorld(s, n)
  local info = s:Info("world")
  if not info then return end
  local ws = worldState or {}
  worldState = ws
  local first = s:Pins("world")[1]
  ws.map, ws.mine, ws.w, ws.h, ws.scale, ws.have, ws.onMap = info.map, ns.PlayerMapPos(), info.w, info.h, info.scale, info.have, info.onMap
  ws.pins, ws.vis, ws.alpha = n or s.n.world, first and Ask(first, "IsVisible"), first and Ask(first, "GetEffectiveAlpha")
  ws.size, ws.level, ws.canvasLevel = first and Ask(first, "GetWidth"), first and Ask(first, "GetFrameLevel"), info.canvasLevel
  ws.expl, ws.poi = ns.MapLevels()
end

-- (31.10.2026, A1) what the pins were last built from: the positions' version and the look; the stamp is the points'
-- signature for DonMap (version 3: no long string of all points)
local built = { stamp = 0 }
local function WorldShown()
  local db = DB()
  return db.mapWorld and WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
end

-- hand the points over when they or the look changed (the example guild's travellers always); true then
local function Hand(s)
  local style, alpha, demo = ns.PinStyle(), ns.PinAlpha(), ns.demo and true or false
  if built.version == version and built.style == style and built.alpha == alpha and built.demo == demo and not demo then return false end
  built.version, built.style, built.alpha, built.demo, built.stamp = version, style, alpha, demo, built.stamp + 1
  CrestNow()
  if (DonMapAPI.version or 0) >= 3 then s:SetPoints(Points(), built.stamp) else s:SetPoints(Points()) end
  return true
end

-- draw now, whatever changed (options, tests)
function ns.UpdateWorldPins()
  if not WorldShown() then HidePicker() end
  local s = Source()
  if not s then return 0 end
  built.version = nil
  Hand(s)
  local n = s:Update("world")
  if WorldShown() then NoteWorld(s, n) end
  return n
end

function ns.UpdateMiniPins()
  local s = Source()
  if not s then return 0 end
  built.version = nil
  Hand(s)
  return s:Update("minimap")
end

-- the clock: draws only when something changed; DonMap's own clock follows the map and the player
local function RefreshPins()
  local shown = WorldShown()
  if not shown then HidePicker() end
  local s = Source()
  if not s then return end
  if Hand(s) then
    if (DonMapAPI.version or 0) >= 3 then s:Refresh() else s:Update() end
  end
  if shown then NoteWorld(s) end
end

local NONE = {}
function ns.MapPins() -- (tests)
  local s = Source()
  if not s then return NONE, NONE end
  return s:Pins("world"), s:Pins("minimap")
end

-- one frame of our own drives sending and old positions (1 s) and the pins (0.5 s, only when something changed; was
-- 0.2 s with a full rebuild, LEISTUNG_PRUEFUNG A1)
local driver = CreateFrame("Frame")
local acc, accSend = 0, 0
driver:SetScript("OnUpdate", function(_, dt)
  if not ns.db then return end
  acc, accSend = acc + dt, accSend + dt
  if accSend >= 1 then
    accSend = 0
    ns.SafeCall("map send", Tick)
    Expire()
  end
  if acc >= 0.5 then
    acc = 0
    ns.SafeCall("map pins", RefreshPins)
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

ns.OnInit(function() DB() Source() end)
