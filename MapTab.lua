local _, ns = ...
local L = ns.L
local Kit = ns.Kit

---------------------------------------------------------------------------
-- Tab "Map" (GUILDON_PLAN.md step 6; Don style 02.11.2026, mockup docs/layout_2026-11-02/guildon/ part 2): where the members
-- with Guildon are, grouped by zone, over the whole height; right the picked member with its actions (under 960 px over the
-- list). The settings (sharing, pins, sizes, opacity, layer) are in DonCore's options window; the status button on top says
-- how the player shares and opens that option (Daniel 02.11.2026: "Statusknopf bleibt").
---------------------------------------------------------------------------
local S = Kit.SIZE
local DETAIL_W = 280
local SHARE_TEXT = { guild = "With the guild", group = "Only with my group", off = "Off" }
local MAP_FILTER_TEXT = { all = "All", here = "My zone" }
local SHARE_COLOR = { guild = "green", group = "yellow", off = "grey" }

local function ZoneName(map)
  local info = C_Map and C_Map.GetMapInfo and ns.Call(C_Map.GetMapInfo, map)
  return type(info) == "table" and ns.Str(info.name) or ("#" .. tostring(map))
end
ns.ZoneName = ZoneName

local function Ago(p) return L["%d s ago"]:format(math.max(0, math.floor(GetTime() - (p.t or GetTime())))) end

-- Who is where (Daniel 26.10., Gemini draft): grouped by zone, the zone you are in open, the others folded (a click opens
-- them, a search opens the zones with a hit). Rows: name, class, level, layer, age. ns.db.mapZone[map] = true / false is
-- what the player chose for a zone.
function ns.MapEntries(search, filter)
  search = search or ""
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
  local layer = ns.ShowLayer()
  for _, z in ipairs(order) do
    table.sort(z.list, function(a, b) return a.name < b.name end)
    local open = chosen[z.map]
    if open == nil then open = z.map == here or #order == 1 or search ~= "" end
    out[#out + 1] = { kind = "group", key = "z:" .. tostring(z.map), fold = z.map, count = #z.list, collapsed = not open,
      plainCase = true, text = z.name, right = z.map == here and L["your zone"] or nil }
    if open then
      for _, m in ipairs(z.list) do
        local p, name = m.p, m.name
        local cls = ns.ClassHex(p.class)
        out[#out + 1] = { kind = "table", key = name, name = name, p = p, zone = z.name, class = p.class, status = "green",
          cells = { "|c" .. cls .. m.short .. "|r", { text = m.class, color = Kit.C.muted }, { text = tostring(p.level or 0), color = Kit.C.title },
            { text = layer and ns.LayerLine(p) or "", color = Kit.C.muted }, { text = Ago(p), color = Kit.C.quiet } },
          tooltipFn = function()
            return "|c" .. cls .. m.short .. "|r", { z.name, layer and ns.LayerLine(p) or nil,
              ns.CanArrow and ns.CanArrow() and L["Right-click: arrow to this member"] or nil },
              L["Click: show on the world map"]
          end }
      end
    end
  end
  return out, #order
end

local function OpenShareOption()
  local Opt = LibStub("DonCore-1.0"):Get("Options", 1)
  if Opt and Opt.Open then Opt.Open(ns.OPTIONS_ID, "map") end
end

local function FillDetail(p, d, e)
  local name, pos = e.name, e.p
  local m = ns.Member and ns.Member(name)
  local cls = ns.ClassHex(pos.class)
  d:SetHead({ level = pos.level, levelStatus = "grey", title = "|c" .. cls .. ns.ShortName(name) .. "|r",
    meta = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[pos.class or ""]) or "" })
  local acts = { { text = L["On the map"], kind = "primary", onClick = function() ns.ShowOnMap(name) end } }
  if ns.CanArrow and ns.CanArrow() then acts[#acts + 1] = { text = L["Arrow"], onClick = function() ns.ArrowTo(name) end } end
  if name ~= ns.MyName() then acts[#acts + 1] = { text = L["Whisper"], onClick = function() ns.WhisperMember(name) end } end
  d:SetActions(acts)
  d:Begin()
  d:Line(L["Zone"], Kit.C.muted, e.zone, Kit.C.title)
  if ns.ShowLayer() then d:Line(L["Layer"], Kit.C.muted, ns.LayerLine(pos), Kit.C.title) end
  d:Line(L["Reported"], Kit.C.muted, Ago(pos), Kit.C.title)
  if m and m.rank and m.rank ~= "" then d:Line(L["Rank"], Kit.C.muted, m.rank, Kit.C.title) end
  local lines = m and ns.MemberLines and ns.MemberLines(m) or {}
  if #lines > 0 then
    d:Section(L["More"])
    for _, l in ipairs(lines) do d:Line(l) end
  end
  d:Section(L["Clicks"])
  d:Line(L["Click: show on the world map"], Kit.C.muted)
  if ns.CanArrow and ns.CanArrow() then d:Line(L["Right-click: arrow to this member"], Kit.C.muted) end
  d:End()
end

ns.PAGE_BUILDERS.map = function(p)
  p.search = Kit.SearchBox(p, { placeholder = L["Name, zone"], onChange = function() if p:IsShown() then p:Refresh() end end })
  p.chips = Kit.ChipBar(p, { onChange = function(key) ns.db.mapFilter = key ~= "all" and key or nil p:Refresh() end })
  for _, k in ipairs({ "all", "here" }) do p.chips:Add(k, L[MAP_FILTER_TEXT[k]]) end
  p.count = Kit.Text(p, "sub", Kit.C.muted, "RIGHT")
  -- (Daniel 02.11.2026) the status of sharing; a click opens the option
  p.share = Kit.Button(p, "", { small = true, onClick = OpenShareOption })
  p.share.dot = p.share:CreateTexture(nil, "OVERLAY")
  p.share.dot:SetTexture("Interface\\Buttons\\WHITE8x8")
  p.share.dot:SetSize(6, 6)
  p.share.dot:SetPoint("LEFT", p.share, "LEFT", 8, 0)
  p.share:SetTooltip(L["Share my position"], { L["Who sees you on the map. Click: change it in the options."] })
  p.head = Kit.TableHead(p, { icon = true, columns = {
    { key = "name", text = L["Name"], width = 110, grow = true },
    { key = "class", text = L["Class"], width = 96 },
    { key = "level", text = L["Lvl"], width = 30, justify = "RIGHT" },
    { key = "layer", text = L["Layer"], width = 48 },
    { key = "age", text = L["Reported"], width = 70, justify = "RIGHT" } } })
  p.list = Kit.List(p, {
    onToggle = function(e)
      ns.db.mapZone = type(ns.db.mapZone) == "table" and ns.db.mapZone or {}
      ns.db.mapZone[e.fold] = not e.collapsed
      p:Refresh()
    end,
    onClick = function(e, button)
      if not e.name then return end
      if button == "RightButton" then if ns.ArrowTo then ns.ArrowTo(e.name) end return end
      p.picked = e.name
      p.list:Select(e)
      ns.Relayout()
      -- a second click on the picked member shows it on the world map
      if p.lastClick == e.name then ns.ShowOnMap(e.name) end
      p.lastClick = e.name
    end,
  })
  p.list:SetEmpty(L["No member with Guildon is sharing a position right now."])
  p.detail = Kit.Detail(p, { onClose = function() p.picked, p.lastClick = nil, nil p.list:Select(nil) ns.Relayout() end })
  p.Search = function(self) return tostring(self.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
  p.Hint = function() return L["Only members with Guildon can be shown; in dungeons and raids only with the option."] end
  p.Picked = function(self)
    for _, e in ipairs(self.list.items or {}) do if e.name and e.name == self.picked then return e end end
  end
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    local narrow = mode ~= "full"
    local side = narrow and 0 or DETAIL_W + S.pad
    local lw = w - 2 * S.pad - side
    local y = S.gap
    self.search:ClearAllPoints()
    self.search:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    local sw = math.min(200, math.floor(lw * 0.3))
    self.search:Layout(sw)
    -- right: the share button (its text cut to what is left), the count left of it
    local shareMax = math.min(230, math.floor(lw * 0.36))
    self.share:Layout(math.min(self.share.natural or shareMax, shareMax))
    self.share:ClearAllPoints()
    self.share:SetPoint("TOPRIGHT", self, "TOPLEFT", S.pad + lw, -y - 2)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPRIGHT", self.share, "TOPLEFT", -S.gap, -5)
    Kit.Fit(self.count, 120)
    local cx = S.pad + lw - self.share:GetWidth() - S.gap - math.min(Kit.TextWidth(self.count), 120) - S.gap
    self.chips:ClearAllPoints()
    self.chips:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad + sw + S.gap, -y - 2)
    self.chips:Layout(math.max(40, cx - (S.pad + sw + S.gap)))
    y = y + S.button + S.gap
    self.head:ClearAllPoints()
    self.head:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.head:Bind(self.list)
    self.head:Layout(lw)
    y = y + S.chip
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.list:Resize(lw, math.max(40, h - y - S.gap))
    local e = self:Picked()
    local show = e and true or (not narrow and true) or false
    self.detail:SetShown(show)
    if show then
      local dw = narrow and math.min(DETAIL_W, w - 2 * S.pad) or DETAIL_W
      self.detail:ClearAllPoints()
      self.detail:SetPoint("TOPRIGHT", self, "TOPRIGHT", -S.pad, -S.gap)
      self.detail:Layout(dw, h - 2 * S.gap)
      if narrow then pcall(self.detail.SetFrameLevel, self.detail, (self.list:GetFrameLevel() or 1) + 20) end
      if e then
        self.detail.close:Show()
        FillDetail(self, self.detail, e)
      else
        -- nobody picked: the card says what to do
        self.detail.close:Hide()
        self.detail:SetHead({ title = L["Map"], meta = L["Pick a member in the list."] })
        self.detail:SetActions({ { text = L["Options"], onClick = OpenShareOption } })
        self.detail:Begin()
        self.detail:Para(L["Members with Guildon who share their position are listed here by zone. Click a member to see more, right-click for the arrow."], Kit.C.muted)
        self.detail:End()
      end
    end
  end
  p.Refresh = function(self)
    local share = ns.db.mapShare or "guild"
    local st = Kit.STATUS[SHARE_COLOR[share] or "grey"]
    self.share:SetText("   " .. L["You share: %s"]:format(L[SHARE_TEXT[share] or SHARE_TEXT.guild]))
    self.share.dot:SetVertexColor(st.fg[1], st.fg[2], st.fg[3], 1)
    self.chips:SetActive(ns.db.mapFilter == "here" and "here" or "all")
    local data = ns.MapEntries(self:Search(), ns.db.mapFilter)
    self.head.cells[4]:SetShown(ns.ShowLayer())
    self.list:SetItems(data)
    local picked = self:Picked()
    self.list.selected = picked
    self.list:Draw()
    -- count from the zone rows: members of a closed zone have no row of their own
    local n = 0
    for _, e in ipairs(data) do if e.fold then n = n + (e.count or 0) end end
    self.count:SetText(L["%d members"]:format(n))
    if self._w then self:Layout(self._w, self._h, self._mode) end
  end
  -- the ages count up while the page is open
  p.tick = 0
  p:SetScript("OnUpdate", function(self, dt)
    self.tick = self.tick + dt
    if self.tick >= 2 then self.tick = 0 self:Refresh() end
  end)
end
