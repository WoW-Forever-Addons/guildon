local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Guildon's tabs and pages (31.10.2026, out of Window.lua; the frame itself is Shared/Window.lua from GuildShared):
-- Overview as tiles, Members, Options. The map tab is built in MapTab.lua (ns.PAGE_BUILDERS).
-- (31.10.2026, C3) Professions, Recipes, Wish list and Profitable went to Guildon Crafts with their options.
---------------------------------------------------------------------------
local PAGE_W, CONTENT_H, ROW_H = ns.PAGE_W, ns.CONTENT_H, ns.ROW_H
local Text, Color, FlatButton, AgeText = ns.UI.Text, ns.UI.Color, ns.UI.FlatButton, ns.UI.AgeText

ns.TABS = {
  { key = "overview", title = "Overview", icon = "Interface\\Icons\\INV_Misc_Book_09" },
  { key = "members", title = "Members", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
  { key = "map", title = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01" },
  { key = "options", title = "Options", icon = "Interface\\Icons\\Trade_Engineering" },
}

ns.PANEL_NAME = "GuildonPanel"
ns.SHOW_AGAIN = "/gn shows it again."
function ns.TitleText()
  local g = ns.GuildInfo()
  local t = Style.Wordmark("Guil", "don")
  if g then t = t .. "  |c" .. Style.Hex("gold") .. g .. "|r" end
  return t
end

local PAL = Style.PAL
local UI = ns.UI
local TILE_GAP, TILE_H = 12, 70
local TILE_W = math.floor((PAGE_W - TILE_GAP) / 2)
local TILE_TOP = 62

local function Tile(p, col, row, label)
  local t = UI.Box(p, PAL.edge, PAL.well)
  t:SetSize(TILE_W, TILE_H)
  t:SetPoint("TOPLEFT", p, "TOPLEFT", col * (TILE_W + TILE_GAP), -(TILE_TOP + row * (TILE_H + 8)))
  t.col, t.row = col, row
  t.label = Text(t, "GameFontHighlightSmall", 10, -8, TILE_W - 20, "textSecondary")
  t.label:SetText(label)
  t.value = Text(t, "GameFontNormalLarge", 10, -24, TILE_W - 20, "textPrimary")
  t.sub = Text(t, "GameFontHighlightSmall", 10, -48, TILE_W - 20, "textHint")
  return t
end

local function BuildOverview(p)
  p.guild = Text(p, "GameFontNormalLarge", 0, 0, PAGE_W, "gold")
  p.emblem = p:CreateTexture(nil, "ARTWORK")
  p.emblem:SetSize(56, 56)
  p.emblem:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, 0)
  p.emblem:Hide()
  p.rank = Text(p, "GameFontHighlight", 0, -28, PAGE_W, "textSecondary")
  -- guild tiles
  p.tiles = {
    members = Tile(p, 0, 0, L["Members"]),
    guildon = Tile(p, 0, 1, L["With Guildon"]),
    sets = Tile(p, 1, 0, L["Data sets"]),
    last = Tile(p, 1, 1, L["Last data from the guild"]),
    game = Tile(p, 1, 2, L["Game version"]),
  }
  -- (C3) the professions are in Guildon Crafts: a tile that opens its window (or says it is missing)
  p.open = UI.FlatButton(p, TILE_W, TILE_H, "")
  p.open:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(TILE_TOP + 2 * (TILE_H + 8)))
  p.open.label:ClearAllPoints()
  p.open.label:SetPoint("LEFT", p.open, "LEFT", 10, 0)
  p.open.label:SetJustifyH("LEFT")
  p.open.label:SetFontObject(GameFontNormal)
  p.open.keepColor = true
  p.open.caret = p.open:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p.open.caret:SetPoint("RIGHT", p.open, "RIGHT", -10, 0)
  p.open.caret:SetText(">")
  p.open:SetScript("OnClick", ns.Guard("overview crafts", function()
    local open = rawget(_G, "GuildonCrafts_OnAddonCompartmentClick")
    if type(open) == "function" then open() else ns.Print(L["Guildon Crafts is not loaded: professions, recipes and wishes are in it."]) end
  end))
  p.open:SetTip("Guildon Crafts", { L["Professions, recipes, wish list and trade of the guild."] }, L["Click: open Guildon Crafts"])
  -- without a guild: the player's own characters as lines
  p.lines = {}
  for i = 1, 6 do p.lines[i] = Text(p, "GameFontHighlight", 0, -60 - (i - 1) * 22, PAGE_W) end
  -- bottom: a note, and the buttons right
  p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.hint:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 34)
  p.hint:SetWidth(PAGE_W)
  p.hint:SetJustifyH("LEFT")
  Color(p.hint, "textHint")
  p.hint:SetText(L["Every member who has Guildon shows up here."])
  -- the example guild from a button (layout review 25.10.: without a guild the page was empty)
  p.demo = FlatButton(p, 190, 24, "")
  p.demo:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 4)
  p.demo:SetScript("OnClick", ns.Guard("overview demo", function()
    if ns.SetDemo then ns.SetDemo(not ns.demo) end
    if p:IsShown() then p:Refresh() end
  end))
  -- wider window: the two tile columns share the width
  p.OnWidth = function(self, w)
    local tw = math.floor((w - TILE_GAP) / 2)
    for _, t in pairs(self.tiles) do
      t:SetSize(tw, TILE_H)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self, "TOPLEFT", t.col * (tw + TILE_GAP), -(TILE_TOP + t.row * (TILE_H + 8)))
      t.label:SetWidth(tw - 20)
      t.value:SetWidth(tw - 20)
      t.sub:SetWidth(tw - 20)
    end
    self.open:SetWidth(tw)
    self.guild:SetWidth(w)
    self.rank:SetWidth(w)
    self.hint:SetWidth(w)
    for _, l in ipairs(self.lines) do l:SetWidth(w) end
  end
  p.Refresh = function(self)
    local g, rank = ns.GuildInfo()
    self.demo.label:SetText(ns.demo and L["Hide the example guild"] or L["Show an example guild"])
    self.demo:SetShown(ns.demo or not ns.InGuild())
    for _, t in pairs(self.tiles) do t:SetShown(g ~= nil) end
    self.open:SetShown(g ~= nil)
    for _, l in ipairs(self.lines) do l:SetShown(g == nil) end
    if not g then
      self.emblem:Hide()
      self.guild:SetText(L["You are not in a guild."])
      self.rank:SetText(L["Guildon shows your guild once you join one."])
      for _, l in ipairs(self.lines) do l:SetText("") end
      -- own characters of this account with class and level (C3: the professions are shown by Guildon Crafts)
      self.lines[1]:SetText("|c" .. Style.Hex("gold") .. L["Your characters"] .. "|r")
      local n = 1
      local names = {}
      for owner in pairs(ns.db.chars or {}) do names[#names + 1] = owner end
      table.sort(names)
      local classes = LOCALIZED_CLASS_NAMES_MALE or {}
      for _, owner in ipairs(names) do
        if n >= #self.lines then break end
        local c = ns.db.chars[owner]
        n = n + 1
        self.lines[n]:SetText("|c" .. ns.ClassHex(c.class) .. ns.ShortName(owner) .. "|r:  |c" .. Style.Hex("textSecondary")
          .. (classes[c.class] or c.class or "") .. " " .. (c.level or 0) .. "|r")
      end
      self.hint:SetText(L["How it works: 1. Join a guild. 2. Members with Guildon show up by themselves. 3. You see them on the map and in the member list."])
      return
    end
    self.guild:SetText(g)
    local own = ns.OwnEmblemFile and ns.OwnEmblemFile()
    if own then self.emblem:SetTexture(own) self.emblem:Show() else self.emblem:Hide() end
    self.rank:SetText(L["Your rank: %s"]:format(rank or "?"))
    local total, online, guildon, guildonOnline = ns.MemberCounts()
    local sets, newest, mine = 0, nil, nil
    for _, s in pairs(ns.db.sets) do
      sets = sets + 1
      if s.o ~= ns.MyName() then
        if not newest or s.t > newest then newest = s.t end
      elseif not mine or s.t > mine then
        mine = s.t
      end
    end
    local t = self.tiles
    t.members.value:SetText(Style.Number and Style.Number(total) or tostring(total))
    t.members.sub:SetText(L["online: %d"]:format(online))
    t.guildon.value:SetText(Style.Number and Style.Number(guildon) or tostring(guildon))
    t.guildon.sub:SetText(L["online: %d"]:format(guildonOnline))
    t.sets.value:SetText(Style.Number and Style.Number(sets) or tostring(sets))
    t.last.value:SetText(newest and AgeText(newest) or L["No data from the guild yet."])
    -- (Daniel 26.10.: "sollte nicht stehen, dass welche von mir da sind?") the player's own data, so that it does not look as if nothing happened
    t.last.sub:SetText(mine and L["Yours: %s"]:format(AgeText(mine)) or L["Yours: nothing yet"])
    t.game.value:SetText(ns.ERA and L["Classic Era"] or L["WoW Forever"])
    local cd = type(rawget(_G, "GuildonCrafts_OnAddonCompartmentClick")) == "function"
    self.open.label:SetText(cd and L["Professions and wishes: Guildon Crafts"] or L["Professions and wishes: Guildon Crafts is not loaded"])
    Color(self.open.label, cd and "gold" or "textSecondary")
    self.open.strong = cd
    self.open:SetLook("normal")
    if ns.demo then
      self.hint:SetText(L["Example guild is on: the members ending in -Demo are made up and only on your screen. /gn demo off removes them."])
    else
      self.hint:SetText(L["Every member who has Guildon shows up here."])
    end
  end
end

---------------------------------------------------------------------------
-- Members (Daniel 26.10., Gemini draft): search and a filter on top, online first, offline folded away. For 250 members:
-- nobody scrolls through the offline ones unless asked or searching.
---------------------------------------------------------------------------
local MEM_COLS = { { 150, 100, "LEFT" }, { 254, 26, "RIGHT" }, { 288, 16, "LEFT" }, { 312, 130, "LEFT" } }
local MEM_FILTER_TEXT = { all = "All", guildon = "Guildon only" }
local MEM_TOP = 30

local function MemberEntries(search, filter, showOffline)
  local out, online, offline = {}, {}, {}
  for _, m in ipairs(ns.Members()) do
    local peer = ns.db.peers[m.name] or (m.demo and { v = ns.VERSION })
    local hay = (m.short .. " " .. (m.class or "") .. " " .. (m.zone or "") .. " " .. (m.rank or "")):lower()
    if (filter ~= "guildon" or peer) and (search == "" or hay:find(search, 1, true)) then
      local e = { key = m.name, text = "|c" .. ns.ClassHex(m.classFile) .. m.short .. "|r",
        cols = { "|c" .. ns.ClassHex(m.classFile) .. (m.class or "") .. "|r", "|c" .. Style.Hex("textPrimary") .. m.level .. "|r",
          peer and ("|c" .. Style.Hex("gold") .. "G|r") or "", "|c" .. Style.Hex("textSecondary") .. (m.rank or "") .. "|r" },
        value = m.online and (m.zone or "") or L["offline"], valueColor = m.online and "textSecondary" or "textHint",
        color = m.online and nil or "textHint",
        tooltip = function()
          local lines = { m.rank, m.class .. " " .. m.level, peer and L["Guildon %s"]:format(peer.v) or L["without Guildon"] }
          for _, l in ipairs(ns.MemberLines and ns.MemberLines(m) or {}) do lines[#lines + 1] = l end
          if m.demo then lines[#lines + 1] = L["Example member, only on your screen (/gn demo off)."] end
          return m.short, lines, m.name ~= ns.MyName() and L["Click: whisper"] or nil
        end }
      if m.online then online[#online + 1] = e else offline[#offline + 1] = e end
    end
  end
  if #online > 0 then out[#out + 1] = { key = "h_on", text = L["Online (%d)"]:format(#online), header = true } end
  for _, e in ipairs(online) do out[#out + 1] = e end
  if #offline > 0 then
    -- offline members fold away; a search opens them by itself
    local open = showOffline or search ~= ""
    out[#out + 1] = { key = "fold_off", fold = true, topLine = #out > 0, color = "textSecondary",
      text = (open and "- " or "+ ") .. L["Offline (%d)"]:format(#offline) .. (open and "" or (", " .. L["click to show"])) }
    if open then for _, e in ipairs(offline) do out[#out + 1] = e end end
  end
  return out
end

-- (Daniel 26.10., picture "Guild statistics, Members by class") under the member list: one bar per class in its colour,
-- the number above, the class icon below; most members first. The filter "Guildon only" counts only those. Click: search.
local CHART_H = 128
local CLASS_ICONS = "Interface\\WorldStateFrame\\Icons-Classes"
function ns.ClassCounts(filter)
  local n, names, on = {}, {}, {}
  for _, m in ipairs(ns.Members()) do
    local peer = ns.db.peers[m.name] or (m.demo and { v = ns.VERSION })
    if filter ~= "guildon" or peer then
      local c = m.classFile or "?"
      n[c] = (n[c] or 0) + 1
      names[c] = names[c] or m.class or c
      if m.online then on[c] = (on[c] or 0) + 1 end
    end
  end
  local out = {}
  for c, k in pairs(n) do out[#out + 1] = { class = c, name = names[c], n = k, online = on[c] or 0 } end
  table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.class < b.class end)
  return out
end

local function ClassChart(p)
  local c = UI.Box(p)
  c:SetHeight(CHART_H)
  c:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  c:SetWidth(PAGE_W)
  c.title = Text(c, "GameFontNormal", 10, -6, 300, "gold")
  c.title:SetText(L["Members by class"])
  c.bars = {}
  local function Bar(i)
    local b = c.bars[i]
    if b then return b end
    b = CreateFrame("Button", nil, c)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.num = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b:SetScript("OnClick", ns.Guard("class chart", function(self)
      if not self.e then return end
      local t = tostring(p.search:GetText() or "")
      p.search:SetText(t:lower() == self.e.name:lower() and "" or self.e.name)
      p:Refresh()
    end))
    b:SetScript("OnEnter", function(self)
      if not self.e then return end
      Style.Tooltip(self, "|c" .. ns.ClassHex(self.e.class) .. self.e.name .. "|r",
        { L["%d members"]:format(self.e.n), L["online: %d"]:format(self.e.online) }, L["Click: show only this class"])
    end)
    b:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
    c.bars[i] = b
    return b
  end
  -- top 24 px title, 14 px for the number, bars, 22 px for the icons
  function c:Paint(list, w)
    w = w or self:GetWidth() or PAGE_W
    local n = #list
    local slot = n > 0 and (w - 20) / n or 0
    local bw = math.max(6, math.min(44, slot - 8))
    local top = n > 0 and list[1].n or 1
    local maxH = CHART_H - 24 - 14 - 24
    for i, e in ipairs(list) do
      local b = Bar(i)
      b.e = e
      local h = math.max(2, math.floor(maxH * e.n / top + 0.5))
      local x = 10 + (i - 1) * slot + (slot - bw) / 2
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 24)
      b:SetSize(bw, h + 14)
      b.fill:ClearAllPoints()
      b.fill:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
      b.fill:SetSize(bw, h)
      local r, g, bl = ns.ClassRGB(e.class)
      b.fill:SetColorTexture(r or 0.6, g or 0.6, bl or 0.6, 1)
      b.num:ClearAllPoints()
      b.num:SetPoint("BOTTOM", b, "BOTTOM", 0, h + 2)
      b.num:SetText(tostring(e.n))
      b.icon:ClearAllPoints()
      b.icon:SetPoint("TOP", b, "BOTTOM", 0, -4)
      local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]
      if tc then
        b.icon:SetTexture(CLASS_ICONS)
        b.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        b.icon:Show()
      else
        b.icon:Hide()
      end
      b:Show()
    end
    for i = n + 1, #self.bars do self.bars[i]:Hide() self.bars[i].e = nil end
  end
  return c
end

local function BuildMembers(p)
  local function Search()
    local t = p.search and tostring(p.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    return t
  end
  p.search = UI.EditBox(p, 210, L["Search"], { onChange = function() if p:IsShown() then p:Refresh() end end })
  p.search:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.filter = UI.Dropdown(p, 150, {
    title = L["Show"],
    get = function() return ns.db.memberFilter == "guildon" and "guildon" or "all" end,
    options = function() return { { "all", L[MEM_FILTER_TEXT.all] }, { "guildon", L[MEM_FILTER_TEXT.guildon] } } end,
    onPick = function(key) ns.db.memberFilter = key p:Refresh() end,
  })
  p.filter:SetPoint("TOPLEFT", p, "TOPLEFT", 218, 0)
  p.count = Text(p, "GameFontHighlightSmall", PAGE_W - 160, -6, 160, "textHint")
  p.count:SetJustifyH("RIGHT")
  p.list = ns.NewList(p, { x = 0, y = -MEM_TOP, width = PAGE_W, height = CONTENT_H - MEM_TOP - CHART_H - 8, rowHeight = ROW_H,
    columns = MEM_COLS, textRight = 146,
    onSelect = function(e)
      if e.fold then
        ns.db.memberOffline = not ns.db.memberOffline or nil
        p:Refresh()
      elseif e.key and e.key ~= ns.MyName() and ns.WhisperMember then
        ns.WhisperMember(e.key)
      end
    end })
  p.empty = Text(p, "GameFontHighlight", 0, -70, PAGE_W, "textSecondary")
  p.empty:SetJustifyH("CENTER")
  p.chart = ClassChart(p)
  p.OnResize = function(self, h) self.list:SetHeight(h - MEM_TOP - CHART_H - 8) end
  p.OnWidth = function(self, w)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", w - 160, -6)
    self.list:SetWidth(w)
    self.empty:SetWidth(w)
    self.chart:SetWidth(w)
    self.chart:Paint(self.chart.list or {}, w)
  end
  p.Refresh = function(self)
    local data = MemberEntries(Search(), ns.db.memberFilter == "guildon" and "guildon" or "all", ns.db.memberOffline)
    self.filter:Sync()
    self.list:SetData(data)
    local total = ns.MemberCounts()
    self.count:SetText(L["%d members"]:format(total or 0))
    self.chart.list = ns.ClassCounts(ns.db.memberFilter == "guildon" and "guildon" or "all")
    self.chart:Paint(self.chart.list)
    if #data == 0 then
      self.empty:SetText(not ns.InGuild() and L["You are not in a guild."] or (Search() ~= "" and L["Nobody found."] or L["The guild list is loading."]))
      self.empty:Show()
    else
      self.empty:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- Options (Daniel 26.10., Gemini draft): sections with a title, every switch with a line of explanation under it,
-- two columns so that it fits the window
---------------------------------------------------------------------------
local COL_W = math.floor((PAGE_W - 24) / 2)
local TOGGLE_H = 40

local function BuildOptions(p)
  local colY = { [0] = 0, [1] = 0 }
  -- the two columns share the page width (wider window): every part that depends on it is placed by a function that is run again
  local colW = COL_W
  local reflow = {}
  local function Place(fn) fn() reflow[#reflow + 1] = fn end
  local function X(col) return col * (colW + 24) end
  local function Section(col, title)
    if colY[col] ~= 0 then colY[col] = colY[col] - 10 end
    local y = colY[col]
    local fs, line = UI.SectionTitle(p, title, X(col), y, colW)
    Place(function()
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", p, "TOPLEFT", X(col), y)
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", p, "TOPLEFT", X(col), y - 16)
      line:SetPoint("TOPRIGHT", p, "TOPLEFT", X(col) + colW, y - 16)
    end)
    colY[col] = colY[col] - 24
  end
  local function Toggle(col, label, desc, get, set)
    local y = colY[col]
    local b = UI.CheckBox(p, label, get, set, { w = colW })
    local d = Text(p, "GameFontDisableSmall", X(col) + 20, y - 17, colW - 24, "textHint")
    d:SetText(desc)
    Place(function()
      b:SetWidth(colW)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", p, "TOPLEFT", X(col), y)
      d:SetWidth(colW - 24)
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", p, "TOPLEFT", X(col) + 20, y - 17)
    end)
    -- a description that wraps (other languages, narrowest window) pushes the next row down
    local extra = math.max(0, math.ceil(tonumber(d:GetStringHeight()) or 0) - 12)
    colY[col] = colY[col] - TOGGLE_H - extra
    return b
  end
  Section(0, L["Window"])
  p.lock = Toggle(0, L["Lock window"], L["Stops the window from being moved."], function() return ns.db.panelLocked end,
    function(v) ns.db.panelLocked = v local panel = ns.GetPanel() if panel then panel:ApplySettings() end end)
  p.fade = Toggle(0, L["Dim in combat"], L["Makes the window see-through during combat."], function() return ns.db.combatFade end,
    function(v) ns.db.combatFade = v local panel = ns.GetPanel() if panel then panel:ApplySettings() end end)
  p.reset = FlatButton(p, 180, 22, L["Reset window position"])
  p.reset:SetPoint("TOPLEFT", p, "TOPLEFT", X(0), colY[0])
  p.reset:SetScript("OnClick", ns.Guard("options", function()
    ns.db.panel.pos = nil
    local panel = ns.GetPanel() if panel then panel:ResetPosition() end
  end))
  colY[0] = colY[0] - 30
  Section(1, L["Minimap"])
  p.mmb = Toggle(1, L["Minimap button"], L["Shows the Guildon button at the minimap. All Guildon parts share it."],
    function() return ns.db.minimapButton ~= false end,
    function(v) ns.db.minimapButton = v if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end end)
  p.OnWidth = function(_, w)
    colW = math.floor((w - 24) / 2)
    for _, fn in ipairs(reflow) do fn() end
  end
  p.Refresh = function(self)
    self.lock:Sync() self.fade:Sync() self.mmb:Sync()
  end
end

ns.PAGE_BUILDERS.overview = BuildOverview
ns.PAGE_BUILDERS.members = BuildMembers
ns.PAGE_BUILDERS.options = BuildOptions
