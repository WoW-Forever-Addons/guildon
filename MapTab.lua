local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Tab "Map" (GUILDON_PLAN.md step 6): who shares where to see the guild, and where the members with Guildon are.
---------------------------------------------------------------------------
local UI = ns.UI
local PAL = Style.PAL
local PAGE_W, CONTENT_H = ns.PAGE_W, ns.CONTENT_H
local TOP = 180
local SHARE_TEXT = { guild = "With the guild", group = "Only with my group", off = "Off" }
local MAP_FILTER_TEXT = { all = "All", here = "My zone" }
-- (Daniel 26.10.) the look of the pins; texts for guildon_keys.py
local PIN_STYLE_TEXT = { emblem = "Guild sign", shield = "Shield only", dot = "Plain dot" }

local function ZoneName(map)
  local info = C_Map and C_Map.GetMapInfo and ns.Call(C_Map.GetMapInfo, map)
  return type(info) == "table" and ns.Str(info.name) or ("#" .. tostring(map))
end

-- Who is where (Daniel 26.10., Gemini draft): grouped by zone, the zone you are in open, the others folded (a click opens
-- them, a search opens the zones with a hit). Rows: name, class, level, layer, age. ns.db.mapZone[map] = true / false is
-- what the player chose for a zone.
function ns.MapEntries(search, filter)
  search = search or ""
  local now = GetTime()
  local here = ns.PlayerMapPos and ns.PlayerMapPos() or nil
  local zones, order = {}, {}
  for name, p in pairs(ns.Positions()) do
    local short = ns.ShortName(name)
    local class = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.class or ""]) or ""
    local zone = ZoneName(p.map)
    local hay = (short .. " " .. class .. " " .. zone):lower()
    if (filter ~= "here" or p.map == here) and (search == "" or hay:find(search, 1, true)) then
      local z = zones[p.map]
      if not z then z = { map = p.map, name = zone, list = {} } zones[p.map] = z order[#order + 1] = z end
      z.list[#z.list + 1] = { name = name, p = p, short = short, class = class }
    end
  end
  table.sort(order, function(a, b)
    if #a.list ~= #b.list then return #a.list > #b.list end
    return a.name < b.name
  end)
  local out = {}
  local chosen = type(ns.db.mapZone) == "table" and ns.db.mapZone or {}
  for _, z in ipairs(order) do
    table.sort(z.list, function(a, b) return a.name < b.name end)
    local open = chosen[z.map]
    if open == nil then open = z.map == here or #order == 1 or search ~= "" end
    out[#out + 1] = { key = "z:" .. tostring(z.map), fold = z.map, count = #z.list, open = open, topLine = #out > 0, color = "gold",
      text = (open and "- " or "+ ") .. z.name, value = tostring(#z.list), valueColor = "textHint" }
    if open then
      for _, m in ipairs(z.list) do
        local p, name = m.p, m.name
        out[#out + 1] = { key = name, name = name, p = p,
          text = "|c" .. ns.ClassHex(p.class) .. m.short .. "|r",
          cols = { "|c" .. ns.ClassHex(p.class) .. m.class .. "|r", "|c" .. Style.Hex("textPrimary") .. (p.level or 0) .. "|r",
            ns.ShowLayer() and ("|c" .. Style.Hex("textSecondary") .. ns.LayerLine(p) .. "|r") or "" },
          value = L["%d s ago"]:format(math.max(0, math.floor(now - p.t))), valueColor = "textHint",
          tooltip = function()
            return "|c" .. ns.ClassHex(p.class) .. m.short .. "|r", { z.name, ns.ShowLayer() and ns.LayerLine(p) or nil,
              ns.CanArrow and ns.CanArrow() and L["Right-click: arrow to this member"] or nil },
              L["Click: show on the world map"]
          end }
      end
    end
  end
  return out, #order
end

ns.PAGE_BUILDERS.map = function(p)
  local label = UI.Text(p, "GameFontHighlightSmall", 0, -5, 160, "textSecondary")
  label:SetText(L["Share my position"])
  p.share = UI.Dropdown(p, 200, {
    title = L["Share my position"],
    get = function() return ns.db.mapShare or "guild" end,
    options = function() return { { "guild", L[SHARE_TEXT.guild] }, { "group", L[SHARE_TEXT.group] }, { "off", L[SHARE_TEXT.off] } } end,
    onPick = function(key) ns.db.mapShare = key p:Refresh() end,
  })
  p.share:SetPoint("TOPLEFT", p, "TOPLEFT", 150, 0)
  -- (Daniel 27.10.) the layer in tooltips, the list and the pick list: off by default
  p.layer = UI.CheckBox(p, L["Show the layer"], function() return ns.db.mapLayer end,
    function(v) ns.db.mapLayer = v or nil p:Refresh() end, { w = 300 })
  p.layer:SetPoint("TOPLEFT", p, "TOPLEFT", 380, -2)
  p.layer:SetTip(L["Show the layer"], { L["The layer (server copy of the zone) of each member in the tooltips and lists, compared with yours. Off by default."] })
  local function Toggle(x, text, key)
    local b = UI.CheckBox(p, text, function() return ns.db[key] end, function(v) ns.db[key] = v end, { w = 226 })
    b:SetPoint("TOPLEFT", p, "TOPLEFT", x, -32)
    return b
  end
  p.pvp = Toggle(0, L["Hide while flagged for PvP"], "mapHidePvP")
  p.world = Toggle(232, L["Members on the world map"], "mapWorld")
  p.mini = Toggle(464, L["Members on the minimap"], "mapMinimap")
  -- (Daniel 26.10.) everyone sets the size of the pins on the world map and the minimap himself, 25 to 200 %
  local function Size(x, text, key, tip)
    local sl = UI.Slider(p, text, { w = 340, labelW = 140, min = 0.25, max = 2, step = 0.05,
      get = function() return ns.db[key] or 1 end,
      set = function(v) ns.db[key] = v if ns.UpdateWorldPins then ns.UpdateWorldPins() end if ns.UpdateMiniPins then ns.UpdateMiniPins() end end })
    sl:SetPoint("TOPLEFT", p, "TOPLEFT", x, -58)
    sl:SetTip(text, { L[tip] })
    return sl
  end
  p.worldSize = Size(0, L["Map icon size"], "mapWorldScale", "Size of the guild pins on the world map. 100 % is the normal size.")
  p.miniSize = Size(360, L["Minimap icon size"], "mapMiniScale", "Size of the guild pins on the minimap. 100 % is the normal size.")
  -- (Daniel 26.10.) dungeons and raids: off by default, on with this switch (share your place there and see the others)
  p.inst = UI.CheckBox(p, L["Minimap in dungeons and raids"], function() return ns.db.mapInstance end,
    function(v) ns.db.mapInstance = v or nil if ns.UpdateMiniPins then ns.UpdateMiniPins() end end, { w = 380 })
  p.inst:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -82)
  p.inst:SetTip(L["Minimap in dungeons and raids"], { L["Off by default. On: inside a dungeon or raid you share your place and see the members with Guildon on the minimap, as far as the game gives positions there."] })
  -- (Daniel 26.10., after the Discord feedback) the look of the pins with a preview in the class colours
  local styleLabel = UI.Text(p, "GameFontHighlightSmall", 0, -113, 140, "textSecondary")
  styleLabel:SetText(L["Pin look"])
  p.pinStyle = UI.Dropdown(p, 170, {
    title = L["Pin look"],
    get = function() return ns.PinStyle() end,
    options = function()
      local out = {}
      for _, k in ipairs(ns.PIN_STYLES) do out[#out + 1] = { k, L[PIN_STYLE_TEXT[k]] } end
      return out
    end,
    onPick = function(key)
      ns.db.pinStyle = key ~= "emblem" and key or nil
      if ns.UpdateWorldPins then ns.UpdateWorldPins() end
      if ns.UpdateMiniPins then ns.UpdateMiniPins() end
      p:Refresh()
    end,
  })
  p.pinStyle:SetPoint("TOPLEFT", p, "TOPLEFT", 150, -108)
  -- preview: four classes at the size the world map shows them (Daniel 27.10.: the group example left out)
  p.preview = {}
  local PREVIEW = { { "WARRIOR", 34 }, { "MAGE", 60 }, { "PRIEST", 21 }, { "HUNTER", 12 } }
  for i, c in ipairs(PREVIEW) do
    local b = ns.PreviewPin(p, 22)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 335 + (i - 1) * 29, -104)
    b.previewMembers = { { name = "", p = { class = c[1], level = c[2] } } }
    p.preview[i] = b
  end
  -- (Daniel 27.10.: "einen Transparenzregler ähnlich wie den Größenregler") the opacity of the pins on both maps, 20 to 100 %
  -- (Daniel 27.10.: "in der kleinsten Breite passt es gerade so nicht") it ends at the page's right edge
  local alphaX = 335 + #PREVIEW * 29 + 6
  p.pinAlpha = UI.Slider(p, L["Opacity"], { w = PAGE_W - alphaX, labelW = 74, min = 0.2, max = 1, step = 0.05,
    get = function() return ns.db.mapPinAlpha or 1 end,
    set = function(v)
      ns.db.mapPinAlpha = v < 0.999 and v or nil
      if ns.UpdateWorldPins then ns.UpdateWorldPins() end
      if ns.UpdateMiniPins then ns.UpdateMiniPins() end
      for _, b in ipairs(p.preview) do b:SetAlpha(ns.PinAlpha()) end
    end })
  p.pinAlpha:SetPoint("TOPLEFT", p, "TOPLEFT", alphaX, -110)
  p.pinAlpha:SetTip(L["Opacity"], { L["How see-through the guild pins on the world map and the minimap are. 100 % is fully visible."] })
  p.note = UI.Text(p, "GameFontDisableSmall", 0, -136, PAGE_W, "textHint")
  p.note:SetText(L["Only members with Guildon can be shown; in dungeons and raids only with the switch above."])
  p.search = UI.EditBox(p, 210, L["Search"], { onChange = function() if p:IsShown() then p:Refresh() end end })
  p.search:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -150)
  p.filter = UI.Dropdown(p, 150, {
    title = L["Show"],
    get = function() return ns.db.mapFilter == "here" and "here" or "all" end,
    options = function() return { { "all", L[MAP_FILTER_TEXT.all] }, { "here", L[MAP_FILTER_TEXT.here] } } end,
    onPick = function(key) ns.db.mapFilter = key p:Refresh() end,
  })
  p.filter:SetPoint("TOPLEFT", p, "TOPLEFT", 218, -150)
  p.count = UI.Text(p, "GameFontHighlightSmall", PAGE_W - 160, -156, 160, "textHint")
  p.count:SetJustifyH("RIGHT")
  p.list = ns.NewList(p, { x = 0, y = -TOP, width = PAGE_W, height = CONTENT_H - TOP, rowHeight = ns.ROW_H,
    columns = { { 150, 100, "LEFT" }, { 254, 26, "RIGHT" }, { 296, 190, "LEFT", "grow" } }, textRight = 146,
    onSelect = function(e, button)
      if e.fold then
        ns.db.mapZone = type(ns.db.mapZone) == "table" and ns.db.mapZone or {}
        ns.db.mapZone[e.fold] = not e.open
        p:Refresh()
        return
      end
      if not e.name then return end
      if button == "RightButton" and ns.ArrowTo and ns.ArrowTo(e.name) then return end
      ns.ShowOnMap(e.name)
    end })
  p.empty = UI.Text(p, "GameFontHighlight", 0, -TOP - 30, PAGE_W, "textSecondary")
  p.empty:SetJustifyH("CENTER")
  p.empty:SetText(L["No member with Guildon is sharing a position right now."])
  p.OnResize = function(self, h) self.list:SetHeight(h - TOP) end
  -- wider window: the list and the zone column take the extra width
  p.OnWidth = function(self, w)
    self.note:SetWidth(w)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", w - 160, -156)
    self.list:SetWidth(w)
    self.empty:SetWidth(w)
  end
  p.Refresh = function(self)
    self.share:Sync() self.filter:Sync() self.pvp:Sync() self.world:Sync() self.mini:Sync() self.worldSize:Sync() self.miniSize:Sync() self.inst:Sync()
    self.pinStyle:Sync() self.pinAlpha:Sync() self.layer:Sync()
    for _, b in ipairs(self.preview) do
      ns.PaintPreview(b, b.previewMembers, 22, 27)
      b:Show()
    end
    local search = tostring(self.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local data = ns.MapEntries(search, ns.db.mapFilter)
    self.list:SetData(data)
    -- count from the zone rows: members of a closed zone have no row of their own
    local n = 0
    for _, e in ipairs(data) do if e.fold then n = n + (e.count or 0) end end
    self.count:SetText(L["%d members"]:format(n))
    self.empty:SetShown(#data == 0)
  end
  -- the ages count up while the page is open
  p.tick = 0
  p:SetScript("OnUpdate", function(self, dt)
    self.tick = self.tick + dt
    if self.tick >= 2 then self.tick = 0 self:Refresh() end
  end)
end
