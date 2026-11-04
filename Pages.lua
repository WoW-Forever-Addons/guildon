local _, ns = ...
local L = ns.L
local Kit = ns.Kit

---------------------------------------------------------------------------
-- Guildon's tabs and pages in the Don style (StyleKit 2 step 4, 02.11.2026, docs/layout_2026-11-02/guildon/): Overview
-- (hero and tiles), Members (sortable columns, census on the right, under 960 px over the list), Map (MapTab.lua). Every
-- option is in DonCore's options window (Options.lua), the cog in the header opens it.
-- (31.10.2026, C3) Professions, recipes, wishes and prices are in Guildon Crafts.
---------------------------------------------------------------------------
local S = Kit.SIZE
local AgeText = ns.UI.AgeText

ns.TABS = {
  { key = "overview", title = "Overview", icon = "Interface\\Icons\\INV_Misc_Book_09" },
  { key = "members", title = "Members", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
  { key = "map", title = "Map", icon = "Interface\\Icons\\INV_Misc_Map_01" },
}

ns.PANEL_NAME = "GuildonPanel"
ns.OPTIONS_ID = "Guildon"
ns.SLASH = "/gn options"
function ns.TitleText() return "Guildon" end

local function N(v) return ns.Style.Number and ns.Style.Number(v) or tostring(v or 0) end

---------------------------------------------------------------------------
-- Overview: the guild as a hero, the numbers as tiles that share the width (more width = more tiles per row)
---------------------------------------------------------------------------
local TILE_MIN, TILE_H = 210, 72

local function OpenCrafts()
  local open = rawget(_G, "GuildonCrafts_OnAddonCompartmentClick")
  if type(open) == "function" then open() else ns.Print(L["Guildon Crafts is not loaded: professions, recipes and wishes are in it."]) end
end

local function BuildOverview(p)
  p.hero = Kit.Hero(p, { height = 72 })
  p.hero:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.tiles = {
    members = Kit.Tile(p, { label = L["Members"] }),
    guildon = Kit.Tile(p, { label = L["With Guildon"] }),
    sets = Kit.Tile(p, { label = L["Data sets"] }),
    last = Kit.Tile(p, { label = L["Last data from the guild"] }),
    game = Kit.Tile(p, { label = L["Game version"] }),
    crafts = Kit.Tile(p, { label = L["Professions and wishes"], onClick = OpenCrafts }),
  }
  p.order = { "members", "guildon", "sets", "last", "game", "crafts" }
  p.tiles.crafts:SetTooltip(L["Guildon: Crafts & Recipes"], { L["Professions, recipes, wish list and trade of the guild."] }, L["Click: open Guildon Crafts"])
  -- without a guild: the player's own characters
  p.chars = Kit.List(p, { zebra = true })
  p.chars:Hide()
  -- bottom: a note and the example guild (layout review 25.10.: without a guild the page was empty)
  p.note = Kit.Text(p, "sub", Kit.C.muted)
  p.demo = Kit.Button(p, "", { small = true, onClick = function()
    if ns.SetDemo then ns.SetDemo(not ns.demo) end
    if p:IsShown() then p:Refresh() p:Layout(p._w, p._h, p._mode) end
  end })
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    local x0, inner = S.pad, w - 2 * S.pad
    self.hero:ClearAllPoints()
    self.hero:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.hero:Layout(w)
    local y = 72 + S.pad
    local cols = math.max(1, math.min(3, math.floor((inner + S.gap) / (TILE_MIN + S.gap))))
    local tw = math.floor((inner - (cols - 1) * S.gap) / cols)
    local i = 0
    for _, k in ipairs(self.order) do
      local t = self.tiles[k]
      if t:IsShown() then
        local c, r = i % cols, math.floor(i / cols)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self, "TOPLEFT", x0 + c * (tw + S.gap), -(y + r * (TILE_H + S.gap)))
        t:Layout(tw)
        i = i + 1
      end
    end
    self.chars:ClearAllPoints()
    self.chars:SetPoint("TOPLEFT", self, "TOPLEFT", x0, -y)
    self.chars:Resize(inner, math.max(40, h - y - 44))
    self.demo:ClearAllPoints()
    self.demo:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -S.pad, S.gap)
    self.note:ClearAllPoints()
    self.note:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x0, S.gap + 6)
    Kit.Fit(self.note, inner - (self.demo:IsShown() and self.demo:GetWidth() + S.gap or 0))
  end
  p.Refresh = function(self)
    local g, rank = ns.GuildInfo()
    self.demo:SetText(ns.demo and L["Hide the example guild"] or L["Show an example guild"])
    self.demo:SetShown(ns.demo or not ns.InGuild())
    for _, t in pairs(self.tiles) do t:SetShown(g ~= nil) end
    self.chars:SetShown(g == nil)
    if not g then
      self.hero:SetData({ kicker = L["Your guild"], title = L["You are not in a guild."] })
      -- own characters of this account with class and level (C3: the professions are shown by Guildon Crafts)
      local names, items = {}, { { kind = "group", static = true, text = L["Your characters"] } }
      for owner in pairs(ns.db.chars or {}) do names[#names + 1] = owner end
      table.sort(names)
      local classes = LOCALIZED_CLASS_NAMES_MALE or {}
      for _, owner in ipairs(names) do
        local c = ns.db.chars[owner]
        items[#items + 1] = { kind = "table", class = c.class, cells = { "|c" .. ns.ClassHex(c.class) .. ns.ShortName(owner) .. "|r",
          classes[c.class] or c.class or "", tostring(c.level or 0) } }
      end
      self.chars.columns = { { width = 140, grow = true }, { width = 120 }, { width = 36, justify = "RIGHT" } }
      self.chars.tableIcon = true
      self.chars:SetItems(items, true)
      self.note:SetText(L["How it works: 1. Join a guild. 2. Members with Guildon show up by themselves. 3. You see them on the map and in the member list."])
      return
    end
    local total, online, guildon, guildonOnline = ns.MemberCounts()
    self.hero:SetData({ kicker = L["Your guild"], title = g, value = N(total), label = L["online: %d"]:format(online),
      progress = total > 0 and online / total or nil })
    self.hero._tipFn = function() return g, { L["Your rank: %s"]:format(rank or "?") } end
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
    t.members:SetData(L["Members"], N(total), L["online: %d"]:format(online))
    t.guildon:SetData(L["With Guildon"], N(guildon), L["online: %d"]:format(guildonOnline))
    t.sets:SetData(L["Data sets"], N(sets), L["Your rank: %s"]:format(rank or "?"))
    t.last:SetData(L["Last data from the guild"], newest and AgeText(newest) or L["No data from the guild yet."],
      -- (Daniel 26.10.: "sollte nicht stehen, dass welche von mir da sind?") the player's own data
      mine and L["Yours: %s"]:format(AgeText(mine)) or L["Yours: nothing yet"])
    t.game:SetData(L["Game version"], ns.ERA and L["Classic Era"] or L["WoW Forever"], "Guildon " .. tostring(ns.VERSION or ""))
    local cd = type(rawget(_G, "GuildonCrafts_OnAddonCompartmentClick")) == "function"
    t.crafts:SetData(L["Professions and wishes"], cd and L["Crafts & Recipes"] or L["not loaded"],
      cd and L["Click: open Guildon Crafts"] or L["Guildon Crafts is not loaded: professions, recipes and wishes are in it."],
      cd and Kit.C.txGold or Kit.C.muted)
    t.crafts:SetDisabled(not cd)
    if ns.demo then
      self.note:SetText(L["Example guild is on: the members ending in -Demo are made up and only on your screen. /gn demo off removes them."])
    else
      self.note:SetText(L["Every member who has Guildon shows up here."])
    end
  end
end

---------------------------------------------------------------------------
-- Members (Daniel 26.10., mockup 02.11.2026): search and chips on top, sortable columns, online first, offline folded away
-- (for 250 members nobody scrolls through the offline ones unless asked or searching). Right the census: numbers, classes
-- (all and online), levels, online by zone; it follows the filter. Under 960 px the census opens over the list.
---------------------------------------------------------------------------
local MEM_FILTER_TEXT = { all = "All", online = "Online", guildon = "With Guildon" }
local CENSUS_W = 280
local LEVEL_BANDS = { { 1, 9 }, { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 59 }, { 60, 60 } }

local function Peer(m) return ns.db.peers[m.name] or (m.demo and { v = ns.VERSION }) end

-- the members that pass search, chip and class filter (the census counts the same ones)
function ns.FilteredMembers(search, filter, class)
  local out = {}
  for _, m in ipairs(ns.Members()) do
    local peer = Peer(m)
    local hay = (m.short .. " " .. (m.class or "") .. " " .. (m.zone or "") .. " " .. (m.rank or "")):lower()
    if (filter ~= "guildon" or peer) and (filter ~= "online" or m.online) and (not class or m.classFile == class)
      and (search == "" or hay:find(search, 1, true)) then
      out[#out + 1] = m
    end
  end
  return out
end

local SORTERS = {
  name = function(m) return m.short:lower() end,
  class = function(m) return (m.class or ""):lower() end,
  level = function(m) return m.level or 0 end,
  rank = function(m) return m.rankIndex or 99 end,
  zone = function(m) return m.online and (m.zone or ""):lower() or ("~" .. string.format("%05d", m.lastOnline or 99999)) end,
}

local function Sorted(list, key, desc)
  local get = SORTERS[key] or SORTERS.name
  local out = {}
  for i, m in ipairs(list) do out[i] = m end
  table.sort(out, function(a, b)
    local x, y = get(a), get(b)
    if x ~= y then if desc then return x > y end return x < y end
    return a.short < b.short
  end)
  return out
end

local function LastSeen(m)
  if m.online then return m.zone or "" end
  if m.lastOnline then return m.lastOnline < 1 and L["today"] or L["%d days ago"]:format(m.lastOnline) end
  return L["offline"]
end

-- the list items: group "Online", the online members, group "Offline" (folded unless asked or searching), the offline ones
function ns.MemberEntries(search, filter, showOffline, class, sortKey, desc)
  local list = Sorted(ns.FilteredMembers(search or "", filter, class), sortKey or "name", desc)
  local online, offline = {}, {}
  for _, m in ipairs(list) do
    local peer = Peer(m)
    local cls = ns.ClassHex(m.classFile)
    local e = { kind = "table", key = m.name, member = m, class = m.classFile, status = m.online and "green" or nil, dim = not m.online,
      cells = { "|c" .. cls .. m.short .. "|r", { text = m.class or "", color = Kit.C.muted }, { text = tostring(m.level or 0), color = Kit.C.title },
        { text = peer and "G" or "", color = Kit.C.txGold }, m.rank or "", { text = LastSeen(m), color = m.online and Kit.C.muted or Kit.C.quiet } },
      tooltipFn = function()
        local lines = { m.rank, (m.class or "") .. " " .. (m.level or 0), peer and L["Guildon %s"]:format(peer.v) or L["without Guildon"] }
        for _, l in ipairs(ns.MemberLines and ns.MemberLines(m) or {}) do lines[#lines + 1] = l end
        if m.demo then lines[#lines + 1] = L["Example member, only on your screen (/gn demo off)."] end
        return "|c" .. cls .. m.short .. "|r", lines, m.name ~= ns.MyName() and (L["Click: whisper"] .. "\n" .. L["Right-click: invite to your group"]) or nil
      end }
    if m.online then online[#online + 1] = e else offline[#offline + 1] = e end
  end
  local out = {}
  if #online > 0 then
    out[#out + 1] = { kind = "group", key = "h_on", static = true, text = L["Online"], count = #online }
    for _, e in ipairs(online) do out[#out + 1] = e end
  end
  if #offline > 0 then
    -- offline members fold away; a search opens them by itself
    local open = showOffline or (search or "") ~= ""
    out[#out + 1] = { kind = "group", key = "fold_off", fold = true, text = L["Offline"], count = #offline, collapsed = not open,
      right = open and "" or L["click to show"] }
    if open then for _, e in ipairs(offline) do out[#out + 1] = e end end
  end
  return out, #list
end

-- (Daniel 26.10., picture "Guild statistics, Members by class") the census: members per class (all and online), most first
function ns.ClassCounts(filter, search)
  local n, names, on = {}, {}, {}
  for _, m in ipairs(ns.FilteredMembers(search or "", filter)) do
    local c = m.classFile or "?"
    n[c] = (n[c] or 0) + 1
    names[c] = names[c] or m.class or c
    if m.online then on[c] = (on[c] or 0) + 1 end
  end
  local out = {}
  for c, k in pairs(n) do out[#out + 1] = { class = c, name = names[c], n = k, online = on[c] or 0 } end
  table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.class < b.class end)
  return out
end

local function Census(p)
  local d = Kit.Detail(p, { onClose = function() p.censusOpen = nil ns.Relayout() end })
  d.nums = CreateFrame("Frame", nil, d)
  d.nums:SetHeight(40)
  d.nums.cells = {}
  for i = 1, 3 do
    local v = Kit.Text(d.nums, "hero", Kit.C.hero)
    local l = Kit.Text(d.nums, "sub", Kit.C.muted)
    d.nums.cells[i] = { v, l }
  end
  function d.nums:Set(list) for i, c in ipairs(self.cells) do c[1]:SetText(list[i][1]) c[2]:SetText(list[i][2]) end end
  function d.nums:Layout(w)
    self:SetWidth(w)
    local each = math.floor(w / 3)
    for i, c in ipairs(self.cells) do
      c[1]:ClearAllPoints() c[1]:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * each, 0)
      c[2]:ClearAllPoints() c[2]:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * each, -24)
      Kit.Fit(c[1], each - 6) Kit.Fit(c[2], each - 6)
    end
  end
  d.classes = Kit.BarList(d, { onClick = function(e)
    p.classFilter = p.classFilter ~= e.key and e.key or nil
    p:Refresh()
  end })
  d.levels = Kit.Columns(d, #LEVEL_BANDS)
  d.levelNames = CreateFrame("Frame", nil, d)
  d.levelNames:SetHeight(14)
  d.levelNames.texts = {}
  for i, band in ipairs(LEVEL_BANDS) do
    local t = Kit.Text(d.levelNames, "mono", Kit.C.quiet, "CENTER")
    t:SetText(band[1] == band[2] and tostring(band[1]) or (band[1] .. "-" .. band[2]))
    d.levelNames.texts[i] = t
  end
  function d.levelNames:Layout(w)
    self:SetWidth(w)
    local n = #self.texts
    local cw = (w - 3 * (n - 1)) / n
    for i, t in ipairs(self.texts) do
      t:ClearAllPoints() t:SetPoint("LEFT", self, "LEFT", (i - 1) * (cw + 3), 0)
      Kit.Fit(t, math.max(8, cw))
    end
  end
  d.zones = Kit.BarList(d, {})
  return d
end

local function FillCensus(p, d)
  local search, filter = p:Search(), p:Filter()
  local list = ns.FilteredMembers(search, filter)
  local online, withG = 0, 0
  local bands, zones = {}, {}
  for i = 1, #LEVEL_BANDS do bands[i] = 0 end
  for _, m in ipairs(list) do
    if m.online then
      online = online + 1
      local z = m.zone ~= "" and m.zone or "?"
      zones[z] = (zones[z] or 0) + 1
    end
    if Peer(m) then withG = withG + 1 end
    for i, b in ipairs(LEVEL_BANDS) do if (m.level or 0) >= b[1] and (m.level or 0) <= b[2] then bands[i] = bands[i] + 1 end end
  end
  d:SetHead({ title = L["Census"], meta = L["follows the filter"] })
  d.nums:Set({ { N(#list), L["Members"] }, { N(online), L["Online"] }, { N(withG), L["With Guildon"] } })
  local cls = {}
  for _, c in ipairs(ns.ClassCounts(filter, search)) do
    cls[#cls + 1] = { key = c.class, class = c.class, text = c.name, value = c.n, value2 = c.online, right = c.n .. " · " .. c.online,
      tooltip = { "|c" .. ns.ClassHex(c.class) .. c.name .. "|r", { L["%d members"]:format(c.n), L["online: %d"]:format(c.online) },
        p.classFilter == c.class and L["Click: show all classes again"] or L["Click: show only this class"] } }
  end
  d.classes:SetEntries(cls)
  local labels = {}
  for i, b in ipairs(LEVEL_BANDS) do labels[i] = L["Level %s"]:format(b[1] == b[2] and tostring(b[1]) or (b[1] .. "-" .. b[2])) end
  d.levels:SetValues(bands, labels)
  local zl = {}
  for z, n in pairs(zones) do zl[#zl + 1] = { key = z, text = z, value = n } end
  table.sort(zl, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.text < b.text end)
  for i = #zl, 7, -1 do zl[i] = nil end
  d.zones:SetEntries(zl)
  -- the body: numbers, classes, levels, zones
  local w = math.max(40, (d._w or CENSUS_W) - 2 * S.pad - 6)
  d:Begin()
  d:Block(d.nums, 40)
  d:Section(L["By class"], L["all · online"])
  d:Block(d.classes, math.max(1, #cls * 18))
  d:Section(L["By level"])
  d:Block(d.levels, 48)
  d:Block(d.levelNames, 14)
  if #zl > 0 then
    d:Section(L["Online by zone"])
    d:Block(d.zones, #zl * 18)
  end
  d:End()
  d.classes:Layout(w) d.zones:Layout(w)
end

local function BuildMembers(p)
  p.search = Kit.SearchBox(p, { placeholder = L["Name, class, zone, rank"], onChange = function() if p:IsShown() then p:Refresh() end end })
  p.chips = Kit.ChipBar(p, { onChange = function(key)
    if key == "class" then p.classFilter = nil
    else ns.db.memberFilter = key ~= "all" and key or nil end
    p:Refresh()
  end })
  for _, k in ipairs({ "all", "online", "guildon" }) do p.chips:Add(k, L[MEM_FILTER_TEXT[k]]) end
  p.classChip = p.chips:Add("class", "")
  p.censusBtn = Kit.Button(p, L["Census"], { small = true, onClick = function()
    p.censusOpen = not p.censusOpen or nil
    ns.Relayout()
  end })
  p.count = Kit.Text(p, "sub", Kit.C.muted, "RIGHT")
  local function Head(narrow)
    local cols = { { key = "name", text = L["Name"], width = 110, grow = true, sort = true } }
    if not narrow then cols[#cols + 1] = { key = "class", text = L["Class"], width = 96, sort = true } end
    cols[#cols + 1] = { key = "level", text = L["Lvl"], width = 30, justify = "RIGHT", sort = true, desc = true }
    cols[#cols + 1] = { key = "guildon", text = "", width = 12, tooltip = { "Guildon", { L["G: has Guildon"] } } }
    cols[#cols + 1] = { key = "rank", text = L["Rank"], width = narrow and 72 or 100, sort = true }
    cols[#cols + 1] = { key = "zone", text = L["Zone / last seen"], width = narrow and 104 or 150, justify = "RIGHT", sort = true }
    local h = Kit.TableHead(p, { icon = true, columns = cols, onSort = function(key, desc)
      ns.db.memberSort = { key, desc }
      p.headWide:SetSort(key, desc) p.headNarrow:SetSort(key, desc)
      p:Refresh()
    end })
    h.narrow = narrow
    return h
  end
  p.headWide, p.headNarrow = Head(false), Head(true)
  p.list = Kit.List(p, {
    -- the group "Offline" folds (the list turns item.collapsed, the choice is kept)
    onToggle = function(e)
      if e.fold then ns.db.memberOffline = not e.collapsed or nil end
      p:Refresh()
    end,
    onClick = function(e, button)
      if e.key and e.member and e.key ~= ns.MyName() then
        if button == "RightButton" then ns.InviteMember(e.key) elseif ns.WhisperMember then ns.WhisperMember(e.key) end
      end
    end,
  })
  p.census = Census(p)
  p.Search = function(self) return tostring(self.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
  p.Filter = function() local f = ns.db.memberFilter return (f == "online" or f == "guildon") and f or "all" end
  p.Hint = function() return L["Click: whisper"] .. "   " .. L["Right-click: invite to your group"] end
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    local narrow = mode ~= "full"
    local side = narrow and 0 or CENSUS_W + S.pad
    local lw = w - 2 * S.pad - side
    local y = S.gap
    self.search:ClearAllPoints()
    self.search:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    local sw = math.min(220, math.floor(lw * 0.34))
    self.search:Layout(sw)
    self.censusBtn:SetShown(narrow)
    self.censusBtn:SetSelected(self.censusOpen and true or false)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPRIGHT", self, "TOPLEFT", S.pad + lw, -y - 7)
    Kit.Fit(self.count, 110)
    local cw = math.min(Kit.TextWidth(self.count), 110)
    local bx = S.pad + lw - cw - S.gap
    if narrow then
      self.censusBtn:ClearAllPoints()
      self.censusBtn:SetPoint("TOPRIGHT", self, "TOPLEFT", bx, -y - 2)
      bx = bx - self.censusBtn:GetWidth() - S.gap
    end
    self.chips:ClearAllPoints()
    self.chips:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad + sw + S.gap, -y - 2)
    self.chips:Layout(math.max(40, bx - (S.pad + sw + S.gap)))
    y = y + S.button + S.gap
    local head = narrow and self.headNarrow or self.headWide
    self.headWide:SetShown(not narrow) self.headNarrow:SetShown(narrow)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    head:Bind(self.list)
    head:Layout(lw)
    y = y + S.chip
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.list:Resize(lw, math.max(40, h - y - S.gap))
    -- the census: a column of its own from 960 px, else over the list when opened
    local showCensus = not narrow or self.censusOpen
    self.census:SetShown(showCensus and true or false)
    if showCensus then
      local cwid = narrow and math.min(CENSUS_W, w - 2 * S.pad) or CENSUS_W
      self.census:ClearAllPoints()
      self.census:SetPoint("TOPRIGHT", self, "TOPRIGHT", -S.pad, -S.gap)
      if narrow then self.census.close:Show() else self.census.close:Hide() end
      self.census:Layout(cwid, h - 2 * S.gap)
      if narrow then pcall(self.census.SetFrameLevel, self.census, (self.list:GetFrameLevel() or 1) + 20) end
      FillCensus(self, self.census)
    end
  end
  p.Refresh = function(self)
    local sort = type(ns.db.memberSort) == "table" and ns.db.memberSort or { "name", false }
    if self.headWide.sortKey ~= sort[1] or self.headWide.desc ~= (sort[2] and true or false) then
      self.headWide:SetSort(sort[1], sort[2]) self.headNarrow:SetSort(sort[1], sort[2])
    end
    local filter = self:Filter()
    self.chips:SetActive(filter)
    local cf = self.classFilter
    if cf then
      local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf]) or cf
      self.classChip:SetText("|c" .. ns.ClassHex(cf) .. name .. "|r  x")
      self.classChip:Show()
      self.classChip:SetSelected(true)
    else
      self.classChip:Hide()
    end
    self.chips:Place()
    local data, n = ns.MemberEntries(self:Search(), filter, ns.db.memberOffline, cf, sort[1], sort[2])
    self.list:SetItems(data)
    self.list:SetEmpty(not ns.InGuild() and not ns.demo and L["You are not in a guild."] or (self:Search() ~= "" and L["Nobody found."] or L["The guild list is loading."]))
    local total = ns.MemberCounts()
    self.count:SetText(n == total and L["%d members"]:format(total or 0) or L["%d of %d"]:format(n, total or 0))
    if self.census:IsShown() then FillCensus(self, self.census) end
  end
end

ns.PAGE_BUILDERS.overview = BuildOverview
ns.PAGE_BUILDERS.members = BuildMembers
