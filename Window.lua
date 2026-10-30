local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Main window in the quest book look (Theme.lua): tabs on the left like Questdon's options, the guild name in the
-- title. Step 1 fills Overview, Members and Options; the other tabs say which version brings them.
---------------------------------------------------------------------------
local PAD = Style.SPACING.padX
local WIDTH = 720
local INNER_W = WIDTH - 2 * PAD
-- tabs in one row across the top (Daniel 25.10.), the page uses the full width below them
local HOLDER_H = 420
local NAV_H = 26
local NAV_GAP = 4
local NAV_W = math.floor((INNER_W - 7 * NAV_GAP) / 8)
local PAGE_Y = -(NAV_H + 10)
local CONTENT_H = HOLDER_H + PAGE_Y
local PAGE_X = 0
local PAGE_W = INNER_W
local ROW_H = 22

ns.TABS = {
  { key = "overview", title = "Overview", icon = "Interface\\Icons\\INV_Misc_Book_09" },
  { key = "professions", title = "Professions", icon = "Interface\\Icons\\Trade_BlackSmithing" },
  { key = "recipes", title = "Recipes", icon = "Interface\\Icons\\INV_Scroll_03" },
  { key = "wishes", title = "Wish list", icon = "Interface\\Icons\\INV_Letter_15" },
  -- (Discord 30.10.: "warum muss das in einem Gildenaddon sein?") off by default, switched on in the options
  { key = "profit", title = "Profitable", icon = "Interface\\Icons\\INV_Misc_Coin_02", optional = "showProfit" },
  { key = "members", title = "Members", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
  { key = "map", title = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01" },
  { key = "options", title = "Options", icon = "Interface\\Icons\\Trade_Engineering" },
}

local panel, holder
local PaintEmblem
local NavLayout
local nav, pages = {}, {}
local current

-- height of the content (Daniel 25.10.: dragging the grip shows more lines instead of only scaling the window)
local MIN_H, MAX_H = 360, 900
local function HolderH()
  local h = tonumber(ns.db and ns.db.panelHeight) or HOLDER_H
  return math.max(MIN_H, math.min(MAX_H, math.floor(h)))
end
function ns.ContentHeight() return HolderH() + PAGE_Y end

-- width of the window (Daniel 26.10.: "Breite auch ziehbar machen"): 720 is the minimum and what the pages are built for; wider gives
-- the lists and the tabs more room. Each page can have p.OnWidth(self, pageWidth) to place its parts.
local MIN_W, MAX_W = WIDTH, 1100
local function PanelW()
  local w = tonumber(ns.db and ns.db.panelWidth) or MIN_W
  return math.max(MIN_W, math.min(MAX_W, math.floor(w)))
end
function ns.PageWidth() return PanelW() - 2 * PAD end

local function ResizePages()
  local ch, pw = ns.ContentHeight(), ns.PageWidth()
  for _, p in pairs(pages) do
    p:SetSize(pw, ch)
    if p.OnWidth then ns.SafeCall("width", p.OnWidth, p, pw) end
    if p.OnResize then ns.SafeCall("resize", p.OnResize, p, ch) end
  end
end

-- one call for both (the grip changes width and height together): the pages are laid out once
function ns.SetPanelSize(w, h)
  if w then ns.db.panelWidth = math.max(MIN_W, math.min(MAX_W, math.floor(w))) end
  if h then ns.db.panelHeight = math.max(MIN_H, math.min(MAX_H, math.floor(h))) end
  if panel and holder then
    if w then panel:SetPanelWidth(PanelW()) NavLayout() end
    if h then Style.Content(panel, holder, HolderH()) end
    ResizePages()
  end
end
function ns.SetPanelHeight(h) ns.SetPanelSize(nil, h) end

local function Color(fs, c)
  c = type(c) == "string" and (C[c] or Style.BOOK[c]) or c
  fs:SetTextColor(c[1], c[2], c[3])
end

local function Text(parent, font, x, y, w, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if w then fs:SetWidth(w) end
  fs:SetJustifyH("LEFT")
  Color(fs, color or "textPrimary")
  return fs
end

local FlatButton = ns.UI.FlatButton

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function TitleText()
  local g = ns.GuildInfo()
  local t = Style.Wordmark("Guil", "don")
  if g then t = t .. "  |c" .. Style.Hex("gold") .. g .. "|r" end
  return t
end

ns.PAGE_W, ns.CONTENT_H, ns.ROW_H = PAGE_W, CONTENT_H, ROW_H
ns.UI.Text = Text
ns.PAGE_BUILDERS = ns.PAGE_BUILDERS or {}

local function AgeText(stamp)
  local age = math.max(0, time() - (stamp or 0))
  if age < 3600 then return L["%d min ago"]:format(math.floor(age / 60)) end
  if age < 86400 then return L["%d h ago"]:format(math.floor(age / 3600)) end
  return L["%d days ago"]:format(math.floor(age / 86400))
end
ns.UI.AgeText = AgeText

-- Overview as tiles (Daniel 26.10., Gemini draft): guild and rank on top, two columns of tiles below
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
  -- the wishes the player can craft: a tile that opens the wish list
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
  p.open:SetScript("OnClick", ns.Guard("overview wishes", function() ns.OpenTab("wishes") end))
  p.open:SetTip(L["Wish list"], nil, L["Click: open the wish list"])
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
  p.export = FlatButton(p, 190, 24, L["Export for the guild website"])
  p.export:SetScript("OnClick", ns.Guard("overview export", function() if ns.ShowExport then ns.ShowExport() end end))
  p.export:SetTip(L["Export for the guild website"], { L["Your characters' professions and recipes as one text to copy."] }, L["Also: /gn export"])
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
    self.export:ClearAllPoints()
    if self.demo:IsShown() then self.export:SetPoint("RIGHT", self.demo, "LEFT", -8, 0)
    else self.export:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 4) end
    for _, t in pairs(self.tiles) do t:SetShown(g ~= nil) end
    self.open:SetShown(g ~= nil)
    for _, l in ipairs(self.lines) do l:SetShown(g == nil) end
    if not g then
      self.emblem:Hide()
      self.guild:SetText(L["You are not in a guild."])
      self.rank:SetText(L["Guildon shows your guild once you join one."])
      for _, l in ipairs(self.lines) do l:SetText("") end
      -- own characters of this account with their professions
      self.lines[1]:SetText("|c" .. Style.Hex("gold") .. L["Your characters"] .. "|r")
      local n = 1
      local names = {}
      for owner in pairs(ns.db.prof or {}) do names[#names + 1] = owner end
      table.sort(names)
      for _, owner in ipairs(names) do
        if n >= #self.lines then break end
        local parts = {}
        for _, pr in ipairs(ns.PROFS) do
          local e = ns.db.prof[owner][pr.id]
          if e then parts[#parts + 1] = ("%s %d/%d"):format(ns.ProfName(pr.id), e.rank or 0, e.max or 0) end
        end
        if #parts > 0 then
          n = n + 1
          self.lines[n]:SetText(ns.ShortName(owner) .. ":  |c" .. Style.Hex("textSecondary") .. table.concat(parts, ", ") .. "|r")
        end
      end
      if n == 1 then self.lines[2]:SetText("|c" .. Style.Hex("textHint") .. L["Open your profession window once so that Guildon can read your recipes."] .. "|r") end
      self.hint:SetText(L["How it works: 1. Join a guild. 2. Members with Guildon show up by themselves. 3. Open your profession window once, then the guild sees your recipes."])
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
    local open = ns.OpenWishesForMe and ns.OpenWishesForMe() or 0
    self.open.label:SetText(L["Open wishes you can craft: %d"]:format(open))
    Color(self.open.label, open > 0 and "gold" or "textSecondary")
    self.open.strong = open > 0
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
      elseif e.key and e.key ~= ns.MyName() and ns.WhisperCrafter then
        ns.WhisperCrafter(e.key)
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
    function(v) ns.db.panelLocked = v if panel then panel:ApplySettings() end end)
  p.fade = Toggle(0, L["Dim in combat"], L["Makes the window see-through during combat."], function() return ns.db.combatFade end,
    function(v) ns.db.combatFade = v if panel then panel:ApplySettings() end end)
  p.reset = FlatButton(p, 180, 22, L["Reset window position"])
  p.reset:SetPoint("TOPLEFT", p, "TOPLEFT", X(0), colY[0])
  p.reset:SetScript("OnClick", ns.Guard("options", function()
    ns.db.panel.pos = nil
    if panel then panel:ResetPosition() end
  end))
  colY[0] = colY[0] - 30
  Section(0, L["Notifications"])
  p.notify = Toggle(0, L["Tell me about new wishes and my crafters"], L["A chat message when someone wishes for something you can make, or a crafter for your wish comes online."],
    function() return ns.db.notifyWishes ~= false end, function(v) ns.db.notifyWishes = v end)
  -- how long open wishes stay
  local daysLabel = Text(p, "GameFontHighlightSmall", X(0), colY[0] - 4, 170, "textPrimary")
  daysLabel:SetText(L["Open wishes run out after"])
  p.days = UI.Dropdown and UI.Dropdown(p, 110, {
    title = L["Open wishes run out after"],
    get = function() return ns.db.wishDays or 14 end,
    options = function() return { { 7, L["%d days"]:format(7) }, { 14, L["%d days"]:format(14) }, { 30, L["%d days"]:format(30) } } end,
    onPick = function(v) ns.db.wishDays = v if ns.InvalidateWishes then ns.InvalidateWishes() end end,
  })
  if p.days then p.days:SetPoint("TOPLEFT", p, "TOPLEFT", X(0) + 180, colY[0]) end
  local dd = Text(p, "GameFontDisableSmall", X(0), colY[0] - 26, colW, "textHint")
  dd:SetText(L["Old wishes disappear from the list after this time."])
  Place(function() dd:SetWidth(colW) end)
  colY[0] = colY[0] - 44
  Section(1, L["Tooltips and trade"])
  p.tips = Toggle(1, L["Guild lines in item tooltips (who crafts it, who wants a recipe)"], L["Adds the guild to the game's item tooltips."],
    function() return ns.db.tooltips ~= false end, function(v) ns.db.tooltips = v end)
  p.cod = Toggle(1, L["Cash on delivery when the wisher pays for the reagents"], L["The mail to the wisher asks for the price of the reagents on delivery."],
    function() return ns.db.mailCOD ~= false end, function(v) ns.db.mailCOD = v end)
  Section(1, L["Minimap"])
  p.mmb = Toggle(1, L["Minimap button"], L["Shows the Guildon button at the minimap."],
    function() return ns.db.minimapButton ~= false end,
    function(v) ns.db.minimapButton = v if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end end)
  Section(1, L["Tabs"])
  p.profit = Toggle(1, L["Tab Profitable"], L["Recipes by profit per craft from auction prices. Off by default."],
    function() return ns.db.showProfit == true end, function(v) ns.db.showProfit = v and true or false ns.RefreshTabs() end)
  -- officer ranks (GUILDON_PLAN.md decision 3): the guild master chooses, everyone else sees the choice
  Section(1, L["Ranks that may delete other members' wishes"])
  local noteY = colY[1] + 2
  p.rankNote = Text(p, "GameFontDisableSmall", X(1), noteY, colW, "textHint")
  Place(function()
    p.rankNote:SetWidth(colW)
    p.rankNote:ClearAllPoints()
    p.rankNote:SetPoint("TOPLEFT", p, "TOPLEFT", X(1), noteY)
  end)
  local rankTop = colY[1] - 14
  p.ranks = {}
  local officerNow = {}
  for i = 0, 9 do
    local b = UI.CheckBox(p, "", function() return officerNow[i] end, function()
      if not ns.IsGuildMaster(ns.MyName()) then return end
      local cur = {}
      for r in pairs(ns.OfficerRanks()) do cur[r] = true end
      cur[i] = not cur[i] or nil
      if i == 0 then cur[0] = true end -- the guild master always may
      ns.SetOfficerRanks(cur)
      p:Refresh()
    end, { w = math.floor(COL_W / 2) - 4 })
    Place(function()
      b:SetWidth(math.floor(colW / 2) - 4)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", p, "TOPLEFT", X(1) + (i % 2) * (math.floor(colW / 2)), rankTop - math.floor(i / 2) * 22)
    end)
    b:Hide()
    p.ranks[i] = b
  end
  p.OnWidth = function(_, w)
    colW = math.floor((w - 24) / 2)
    for _, fn in ipairs(reflow) do fn() end
  end
  p.Refresh = function(self)
    self.lock:Sync() self.fade:Sync() self.notify:Sync() self.tips:Sync() self.cod:Sync() self.mmb:Sync() self.profit:Sync()
    if self.days then self.days:Sync() end
    local names, n = ns.RankNames()
    local officer, set = ns.OfficerRanks()
    local gm = ns.IsGuildMaster(ns.MyName())
    for k in pairs(officerNow) do officerNow[k] = nil end
    for r in pairs(officer) do officerNow[r] = true end
    self.rankNote:SetText(n == 0 and "" or (gm and L["You are the guild master: click a rank to switch it."]
      or (set and L["Set by the guild master."] or L["The guild master has not chosen yet: ranks 1 and 2 of the list."])))
    for i = 0, 9 do
      local b = self.ranks[i]
      if i < n then
        b.label:SetText(names[i] or "?")
        b:Show()
        b:Sync()
      else
        b:Hide()
      end
    end
  end
end

local function BuildLater(p, tab)
  local t = Text(p, "GameFontNormalLarge", 0, 0, PAGE_W, "gold")
  t:SetText(L[tab.title])
  local s = Text(p, "GameFontHighlight", 0, -32, PAGE_W, "textSecondary")
  s:SetText(L["Coming in a later version of Guildon."])
end

local BUILDERS = { overview = BuildOverview, members = BuildMembers, options = BuildOptions }

local function Page(key)
  if pages[key] then return pages[key] end
  local tab
  for _, t in ipairs(ns.TABS) do if t.key == key then tab = t end end
  if not tab then return nil end
  local p = CreateFrame("Frame", nil, holder)
  p:SetSize(PAGE_W, CONTENT_H)
  p:SetPoint("TOPLEFT", holder, "TOPLEFT", PAGE_X, PAGE_Y)
  p:Hide()
  local build = BUILDERS[key] or ns.PAGE_BUILDERS[key]
  if build then build(p) else BuildLater(p, tab) end
  pages[key] = p
  -- the pages are built for the minimum size; a taller or wider window is applied afterwards
  if ns.PageWidth() ~= PAGE_W then
    p:SetSize(ns.PageWidth(), CONTENT_H)
    if p.OnWidth then ns.SafeCall("width", p.OnWidth, p, ns.PageWidth()) end
  end
  if ns.ContentHeight() ~= CONTENT_H then
    p:SetSize(ns.PageWidth(), ns.ContentHeight())
    if p.OnResize then ns.SafeCall("resize", p.OnResize, p, ns.ContentHeight()) end
  end
  return p
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
local function PaintNav()
  for _, b in ipairs(nav) do b:SetLook(b.key == current and "active" or "normal") end
end

-- (Daniel 26.10.: "kann man die UI nach vorne holen, wenn sie über Questdon liegt?") the window comes to the front of its strata
-- (Questdon's tracker panel is in the same one) when it opens and when a tab is chosen; a click inside it does the same (SetToplevel)
local function Front()
  if panel and panel.Raise then panel:Raise() end
end

local function TabShown(key)
  for _, t in ipairs(ns.TABS) do
    if t.key == key then return not t.optional or ns.db[t.optional] == true end
  end
  return false
end

local function Select(key)
  if not TabShown(key) or not Page(key) then key = "overview" end
  Front()
  current = key
  ns.db.tab = key
  for k, p in pairs(pages) do if k ~= key then p:Hide() end end
  local p = Page(key)
  p:Show()
  if p.Refresh then p:Refresh() end
  PaintNav()
end

-- the shown tabs share the width of the page (an optional tab that is off is hidden)
function NavLayout()
  local shown = {}
  for _, b in ipairs(nav) do
    if TabShown(b.key) then shown[#shown + 1] = b b:Show() else b:Hide() end
  end
  local n = math.max(1, #shown)
  local w = math.floor((ns.PageWidth() - (n - 1) * NAV_GAP) / n)
  for i, b in ipairs(shown) do
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (w + NAV_GAP), 0)
  end
end

-- switching an optional tab on or off (Options)
function ns.RefreshTabs()
  if not panel then return end
  NavLayout()
  if current and not TabShown(current) then Select("overview") end
end

local function NavButton(tab, i)
  local b = UI.FlatButton(holder, NAV_W, NAV_H, L[tab.title])
  b:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (NAV_W + NAV_GAP), 0)
  b.key, b.later = tab.key, tab.later
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", b, "LEFT", 5, 0)
  b.icon:SetTexture(tab.icon)
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", -2, 0)
  b.label:SetJustifyH("LEFT")
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end
  b:SetTip(function() if b.label.IsTruncated and b.label:IsTruncated() then return L[tab.title] end end)
  b:SetScript("OnClick", ns.Guard("tab", function(self) Select(self.key) end))
  return b
end

local function Build()
  panel = Style.Panel("GuildonPanel", UIParent, {
    title = TitleText(),
    width = PanelW(),
    look = "book",
    close = true,
    collapse = false,
    get = ns.PanelGet("panel"),
    set = ns.PanelSet("panel"),
    defaultPoint = { "CENTER", "CENTER", 0, 20 },
    closeTooltip = { L["Hide window"], nil, L["/gn shows it again."] },
  })
  if panel.SetToplevel then panel:SetToplevel(true) end
  holder = CreateFrame("Frame", nil, UIParent)
  Style.Content(panel, holder, HolderH())
  local back = holder:CreateTexture(nil, "BACKGROUND", nil, -2)
  back:SetAllPoints(holder)
  back:SetColorTexture(C.background[1], C.background[2], C.background[3], 0.88) -- the world must not shine through (layout review 25.10.)
  for i, tab in ipairs(ns.TABS) do nav[i] = NavButton(tab, i) end
  NavLayout()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildonPanel") end
  -- size grip at the bottom right (Daniel 25.10.): dragging makes the window taller or shorter, the lists show more
  -- or fewer lines; with Shift it scales the whole window as before. The top left corner stays where it is.
  local grip = CreateFrame("Button", nil, panel)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:EnableMouse(true)
  grip:SetScript("OnEnter", function(self) Style.Tooltip(self, L["Window size"], { L["Drag: wider or narrower, more or fewer lines."], L["Shift and drag: make everything bigger or smaller."] }) end)
  grip:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  local function Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
  end
  grip:SetScript("OnMouseDown", function(self)
    if ns.db.panelLocked then return end
    local s0 = panel._scale or panel:GetScale() or 1
    local l, t = panel:GetLeft(), panel:GetTop()
    if not (l and t) then return end
    local cx, cy = Cursor()
    local scaleMode = IsShiftKeyDown and IsShiftKeyDown() and true or false
    self._drag = { s0 = s0, left = l * s0, top = t * s0, x = cx, y = cy, w = panel:GetWidth() * s0, h0 = HolderH(), w0 = PanelW(), scaleMode = scaleMode }
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    self:SetScript("OnUpdate", function()
      local d = self._drag
      if not d then return end
      local nx, ny = Cursor()
      if d.scaleMode then
        local s = math.max(Style.SCALE_MIN, math.min(Style.SCALE_MAX, d.s0 * (d.w + nx - d.x) / d.w))
        s = math.floor(s * 100 + 0.5) / 100
        if s ~= panel._scale then
          panel:SetPanelScale(s)
          panel:ClearAllPoints()
          panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left / s, d.top / s)
        end
      else
        local h = math.floor(d.h0 + (d.y - ny) / d.s0 + 0.5)
        h = math.max(MIN_H, math.min(MAX_H, h))
        -- wider only as far as the screen reaches from the window's left edge
        local w = math.floor(d.w0 + (nx - d.x) / d.s0 + 0.5)
        local screen = UIParent.GetWidth and tonumber(UIParent:GetWidth())
        if screen and screen > 0 then w = math.min(w, math.floor((screen - d.left) / d.s0)) end
        w = math.max(MIN_W, math.min(MAX_W, w))
        if w ~= PanelW() or h ~= HolderH() then ns.SetPanelSize(w ~= PanelW() and w or nil, h ~= HolderH() and h or nil) end
      end
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    local d = self._drag
    self._drag = nil
    if d then
      local s = panel._scale or d.s0
      ns.db.panel.pos = { "TOPLEFT", "BOTTOMLEFT", math.floor(d.left / s + 0.5), math.floor(d.top / s + 0.5) }
    end
  end)
  panel.grip = grip
  if panel.SetGrip then panel:SetGrip(grip) end -- its own space under the content
  Select(ns.db.tab)
  PaintEmblem()
end

-- the guild's emblem left of the close button (Forever; Era has none)
function PaintEmblem()
  if not panel then return end
  -- (an "a and f()" would keep only the first value: no colours, and the game refuses SetVertexColor(nil))
  local file, r, g, b, br, bgc, bb
  if ns.GuildEmblem then file, r, g, b, br, bgc, bb = ns.GuildEmblem() end
  if not file then if panel.emblem then panel.emblem:Hide() end return end
  if not panel.emblem then
    local f = CreateFrame("Frame", nil, panel)
    -- (Daniel 26.10.: "das Wappen sitzt schlecht") as high as the header and centred on the close button's line, not hanging
    -- below the header; the header is 20 high, the emblem 18 so that it touches neither edge
    f:SetSize(18, 18)
    local close = panel.GetButton and panel:GetButton("close")
    if close then f:SetPoint("RIGHT", close, "LEFT", -6, 0) else f:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, 0) end
    f:SetFrameLevel((panel:GetFrameLevel() or 1) + 5)
    f.bg = f:CreateTexture(nil, "ARTWORK")
    f.bg:SetAllPoints()
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    panel.emblem = f
  end
  local f = panel.emblem
  f.tex:SetTexture(file)
  f.tex:SetVertexColor(r, g, b)
  if br then f.bg:SetColorTexture(br, bgc, bb, 0.9) f.bg:Show() else f.bg:Hide() end
  f:Show()
end

function ns.Refresh()
  if not panel then return end
  panel:SetTitle(TitleText())
  PaintEmblem()
  local p = current and pages[current]
  if p and p:IsShown() and p.Refresh then p:Refresh() end
end

function ns.ToggleWindow()
  if (not panel or not panel:IsShown()) and ns.ReadKnown then ns.ReadKnown() end -- Era: the recipes the character knows, without the profession window
  if not panel then Build() panel:FadeIn() Front() ns.RequestRoster() return end
  if panel:IsShown() then panel:FadeOut() else panel:FadeIn() Front() ns.RequestRoster() ns.Refresh() end
end

function ns.OpenTab(key)
  if ns.ReadKnown and (not panel or not panel:IsShown()) then ns.ReadKnown() end
  if not panel then Build() end
  if not panel:IsShown() then panel:FadeIn() end
  Front()
  Select(key)
  ns.RequestRoster()
end

-- open the recipe book (optionally on one profession)
function ns.OpenRecipes(prof, spell)
  if ns.RecipeBookShow then ns.RecipeBookShow(prof, spell) end
  ns.OpenTab("recipes")
end

function ns.WindowState() return panel, current, pages, nav end -- (tests)

-- roster or data changed: repaint the open page (once per half second at most)
local queued = false
local function Later()
  if queued or not panel or not panel:IsShown() then return end
  queued = true
  ns.After(0.5, function() queued = false ns.Refresh() end)
end
ns.OnRosterChanged = Later
ns.OnDataChanged = Later

-- while the window is open, the roster is asked for every 60 s (online states)
ns.OnInit(function()
  ns.NewTicker(60, function() if panel and panel:IsShown() then ns.RequestRoster() end end)
end)
