local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Tab "Profitable" (GUILDON_PLAN.md step 5, "Bedienung"): recipes by profit per craft. Columns revenue (auction
-- price minus 5 percent fee), reagent cost, profit, age of the prices; crafters in the guild in the detail.
-- Switches: only my recipes, count my stock (reagents in bags and bank cost nothing). Prices from Prices.lua.
---------------------------------------------------------------------------
local UI = ns.UI
local PAGE_W, CONTENT_H = ns.PAGE_W, ns.CONTENT_H
local LIST_W = 440
local DETAIL_X = LIST_W + 12
local DETAIL_W = PAGE_W - DETAIL_X
local TOP = 30
local FEE = 0.05
local COLS = { { 196, 58 }, { 258, 58 }, { 320, 64 }, { 390, 40 } }
local PAL = Style.PAL
local HEAD_H = 20
-- sortable columns: key, x, width, justify (the list columns are right aligned)
local HEADS = { { "name", 0, 190, "LEFT", "Recipe" }, { "revenue", 196, 58, "RIGHT", "Revenue" }, { "cost", 258, 58, "RIGHT", "Reagents" },
  { "profit", 320, 64, "RIGHT", "Profit" }, { "age", 390, 40, "RIGHT", "Age" } }

local function Icon(tex, size) return ("|T%s:%d:%d|t"):format(tostring(tex), size or 14, size or 14) end

-- short money text for the columns: 12.3g, 45s, 7c
function ns.ShortMoney(c)
  if not c then return "?" end
  local neg = c < 0
  c = math.abs(c)
  local t
  if c >= 100000 then t = ("%dg"):format(math.floor(c / 10000 + 0.5))
  elseif c >= 10000 then t = ("%.1fg"):format(c / 10000)
  elseif c >= 100 then t = ("%ds"):format(math.floor(c / 100 + 0.5))
  else t = ("%dc"):format(c) end
  return (neg and "-" or "") .. t
end

local function AgeShort(t)
  if not t then return "" end
  local age = math.max(0, time() - t)
  if age < 3600 then return L["now"] end
  if age < 86400 then return ("%dh"):format(math.floor(age / 3600)) end
  return ("%dd"):format(math.floor(age / 86400))
end

local function State()
  local db = ns.db
  db.profitProf = tonumber(db.profitProf) or 0
  -- "only my recipes" is on by default (Daniel 26.10.); a value saved before that is replaced once
  if db.profitMine == nil or not db.profitMineDefault then db.profitMine = true db.profitMineDefault = true end
  if db.profitStock == nil then db.profitStock = false end
  return db
end

-- all recipes with a price for the result and the reagents: list sorted by profit, and how many have no prices
function ns.ProfitRows()
  local db = State()
  local me = ns.MyName()
  local mine = ns.MyCrafts and ns.MyCrafts() or {}
  local rows, missing = {}, 0
  local idx = ns.CraftIndex()
  for spell, crafters in pairs(idx.crafters) do
    local info = ns.RecipeInfo(spell)
    local prof = info.prof
    if (db.profitProf == 0 or prof == db.profitProf) and (not db.profitMine or mine[spell]) and info.item and info.item > 0 then
      local p, tp = ns.Price(info.item)
      local cost, tc = ns.ReagentCost(spell, 1, db.profitStock)
      if p and cost then
        local revenue = math.floor(p * (info.count or 1) * (1 - FEE))
        rows[#rows + 1] = { spell = spell, info = info, revenue = revenue, cost = cost, profit = revenue - cost,
          oldest = math.min(tp or time(), tc or time()), crafters = ns.CraftersOf(spell) }
      else
        missing = missing + 1
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.spell < b.spell
  end)
  return rows, missing
end

local page

local function SortRows(rows, key, desc)
  local function Val(r)
    if key == "name" then return (ns.SpellName(r.spell) or ""):lower() end
    if key == "revenue" then return r.revenue end
    if key == "cost" then return r.cost end
    if key == "age" then return r.oldest end
    return r.profit
  end
  table.sort(rows, function(a, b)
    local x, y = Val(a), Val(b)
    if x ~= y then if desc then return x > y end return x < y end
    return a.spell < b.spell
  end)
end

local function Entries()
  local rows, missing = ns.ProfitRows()
  local db = State()
  local key = db.profitSort or "profit"
  local desc = db.profitDesc ~= false
  if key ~= "profit" or not desc then SortRows(rows, key, desc) end
  local out = {}
  for i = 1, math.min(#rows, 300) do
    local r = rows[i]
    local name = ns.SpellName(r.spell) or L["Recipe %d"]:format(r.spell)
    local good = r.profit > 0
    out[#out + 1] = { key = r.spell, row = r,
      text = Icon(ns.RecipeIcon(r.spell, r.info)) .. " " .. name,
      color = #r.crafters > 0 and "textPrimary" or "textHint",
      cols = { ns.ShortMoney(r.revenue), ns.ShortMoney(r.cost),
        ("|c%s%s|r"):format(Style.Hex(good and "good" or "critical"), ns.ShortMoney(r.profit)),
        ("|c%s%s|r"):format(Style.Hex("textHint"), AgeShort(r.oldest)) } }
  end
  return out, #rows, missing
end

local function ShowDetail(spell)
  local d = page.detail
  page.selected = spell
  for _, r in ipairs(d.rows) do r:Hide() end
  if not spell then
    d.title:SetText("")
    d.icon:Hide()
    d.sub:SetText(L["Choose a recipe on the left."])
    d.head:Hide() d.crafters:SetText("") d.wish:Hide() d.whisper:Hide()
    return
  end
  local info = ns.RecipeInfo(spell)
  d.icon:Show()
  d.icon.tex:SetTexture(ns.RecipeIcon(spell, info))
  d.icon.item, d.icon.spell = info.item, spell
  d.title:SetText(ns.SpellName(spell) or L["Recipe %d"]:format(spell))
  local p, t, who, flagged = ns.Price(info.item)
  local sale = p and (ns.MoneyText(p) .. ((info.count or 1) > 1 and (" x" .. info.count) or "")) or "?"
  d.sub:SetText(L["Sells for %s"]:format(sale) .. (t and ("  |c" .. Style.Hex("textHint") .. ns.UI.AgeText(t) .. "|r") or "")
    .. (flagged and ("  |c" .. Style.Hex("warning") .. L["(odd price)"] .. "|r") or ""))
  local y = -52
  d.head:Show()
  d.head:ClearAllPoints()
  d.head:SetPoint("TOPLEFT", d, "TOPLEFT", 8, y)
  y = y - 18
  for i, rg in ipairs(info.reagents or {}) do
    local r = d.rows[i]
    if not r then break end
    local rp = ns.Price(rg[1])
    local have = ns.ItemCount(rg[1])
    r.item = rg[1]
    r.tex:SetTexture(ns.ItemIcon(rg[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.name:SetText(rg[2] .. " x " .. (ns.ItemName(rg[1]) or ("#" .. rg[1])))
    r.count:SetText((rp and ns.ShortMoney(rp * rg[2]) or "?") .. "  |c" .. Style.Hex(have >= rg[2] and "good" or "critical") .. have .. "/" .. rg[2] .. "|r")
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", d, "TOPLEFT", 8, y)
    r:Show()
    y = y - 18
  end
  local cr = ns.CraftersOf(spell)
  local names = {}
  for i = 1, math.min(#cr, 6) do
    local o = cr[i]
    names[#names + 1] = (ns.IsOnline(o) and "|cff4fd16a" or "|c" .. Style.Hex("textHint")) .. ns.ShortName(o) .. "|r"
  end
  d.crafters:ClearAllPoints()
  d.crafters:SetPoint("TOPLEFT", d, "TOPLEFT", 8, y - 8)
  d.crafters:SetText(#cr > 0 and (L["Crafters: %s"]:format(table.concat(names, ", ")) .. (#cr > 6 and (" " .. L["and %d more"]:format(#cr - 6)) or ""))
    or L["Nobody in the guild knows this recipe yet."])
  page.crafter = nil
  for _, o in ipairs(cr) do if o ~= ns.MyName() and ns.IsOnline(o) then page.crafter = o break end end
  d.whisper:SetShown(page.crafter ~= nil)
  if page.crafter then d.whisper.label:SetText(L["Whisper %s"]:format(ns.ShortName(page.crafter))) end
  d.wish:Show()
end

local function PaintHeads(p)
  local db = State()
  local key, desc = db.profitSort or "profit", db.profitDesc ~= false
  for _, h in ipairs(p.heads) do
    local on = h.key == key
    UI.Color(h.label, on and "blue" or "textSecondary")
    h.arrow:SetShown(on)
    if on then h.arrow:SetTexCoord(0, 1, desc and 0 or 1, desc and 1 or 0) end
  end
end

local function Refresh()
  if not page then return end
  ns.InvalidatePrices()
  local db = State()
  page.prof:Sync()
  PaintHeads(page)
  page.mine:Sync()
  page.stock:Sync()
  local data, n, missing = Entries()
  page.list:SetData(data)
  local addons = {}
  for _, a in ipairs(ns.PriceAddons()) do addons[#addons + 1] = a.name end
  page.info:SetText(L["%d recipes with prices, %d without."]:format(n, missing) .. "  " ..
    (#addons > 0 and L["Prices from: %s and the guild"]:format(table.concat(addons, ", ")) or L["Prices from the guild and your own scans"]))
  page.scan:SetShown(ns.AuctionHouseOpen and ns.AuctionHouseOpen())
  page.empty:SetShown(n == 0)
  local sel = page.selected
  if sel and not ns.RECIPES[sel] and not ns.CraftIndex().crafters[sel] then sel = nil end
  page.list:SetSelected(sel, true)
  ShowDetail(sel)
end
ns.RefreshProfit = Refresh

local function Toggle(p, x, w, label, key)
  local b = UI.CheckBox(p, label, function() return ns.db[key] end, function(v) ns.db[key] = v Refresh() end, { w = w })
  b:SetPoint("TOPLEFT", p, "TOPLEFT", x, -1)
  return b
end

ns.PAGE_BUILDERS.profit = function(p)
  page = p
  State()
  p.prof = UI.Dropdown(p, 160, {
    title = L["Profession"],
    get = function() return State().profitProf end,
    options = function()
      local out = { { 0, L["All professions"] } }
      for _, pr in ipairs(ns.PROFS) do if pr.craft then out[#out + 1] = { pr.id, ns.ProfName(pr.id) } end end
      return out
    end,
    onPick = function(key) State().profitProf = key p.selected = nil Refresh() end,
  })
  p.prof:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  p.mine = Toggle(p, 176, 150, L["Only my recipes"], "profitMine")
  p.stock = Toggle(p, 336, 150, L["Count my stock"], "profitStock")
  -- the table header: a click sorts by that column, a second click turns the order round, a small arrow marks it
  p.heads = {}
  for _, h in ipairs(HEADS) do
    local b = CreateFrame("Button", nil, p)
    b:SetSize(h[3], HEAD_H)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", h[2], -TOP)
    b.key = h[1]
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetText(L[h[5]])
    b.label:SetJustifyH(h[4])
    if h[4] == "LEFT" then b.label:SetPoint("LEFT", b, "LEFT", 8, 0) else b.label:SetPoint("RIGHT", b, "RIGHT", -2, 0) end
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(10, 10)
    b.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    b.arrow:SetPoint("RIGHT", b.label, "LEFT", -2, 0)
    b.arrow:Hide()
    b:SetScript("OnClick", ns.Guard("profit sort", function(self)
      local db = State()
      if (db.profitSort or "profit") == self.key then db.profitDesc = not (db.profitDesc ~= false)
      else db.profitSort = self.key db.profitDesc = self.key ~= "name" end
      Refresh()
    end))
    p.heads[#p.heads + 1] = b
  end
  local line = UI.Line(p)
  p.headLine = line
  line:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(TOP + HEAD_H))
  line:SetPoint("TOPRIGHT", p, "TOPLEFT", LIST_W, -(TOP + HEAD_H))
  p.scan = UI.FlatButton(p, 120, 22, L["Scan prices"])
  p.scan:SetPoint("TOPRIGHT", p, "TOPLEFT", PAGE_W, 0)
  p.scan:SetScript("OnClick", ns.Guard("profit scan", function()
    -- the reagents and results of the shown recipes whose price is older than a day or missing, up to 80
    local items, now = {}, time()
    for _, id in ipairs(ns.RelevantItems()) do
      local pr, t = ns.Price(id)
      if not pr or now - (t or 0) > 86400 then items[#items + 1] = id end
      if #items >= 80 then break end
    end
    ns.ScanPrices(items)
  end))
  p.scan:SetTip(L["Scan prices"], { L["Asks the auction house for missing or old prices, one item after the other (up to 80)."] })
  p.list = ns.NewList(p, { x = 0, y = -(TOP + HEAD_H + 2), width = LIST_W, height = CONTENT_H - TOP - HEAD_H - 22, rowHeight = 20,
    columns = COLS, textRight = 192, growText = true,
    onSelect = function(e) if e.row then p.list:SetSelected(e.key) ShowDetail(e.key) end end })
  p.info = UI.Text(p, "GameFontHighlightSmall", 0, -(CONTENT_H - 16), PAGE_W, "textHint")
  p.empty = UI.Text(p, "GameFontHighlight", 0, -TOP - 50, LIST_W, "textSecondary")
  p.empty:SetJustifyH("CENTER")
  p.empty:SetText(L["No prices yet. With Auctionator, Auctioneer or aux: scan at the auction house; Guildon shares the prices with the guild. Without: \"Scan prices\" at the auction house."])

  local d = CreateFrame("Frame", nil, p)
  d:SetSize(DETAIL_W, CONTENT_H - TOP - 20)
  d:SetPoint("TOPLEFT", p, "TOPLEFT", DETAIL_X, -TOP)
  UI.Skin(d, PAL.edge, PAL.well)
  p.detail = d
  d.icon = CreateFrame("Button", nil, d)
  d.icon:SetSize(36, 36)
  d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -8)
  d.icon.tex = d.icon:CreateTexture(nil, "ARTWORK")
  d.icon.tex:SetAllPoints()
  d.icon:SetScript("OnEnter", function(self)
    if not GameTooltip or not self.item then return end
    ns.Call(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
    ns.Call(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item)
    ns.Call(GameTooltip.Show, GameTooltip)
  end)
  d.icon:SetScript("OnLeave", function() if GameTooltip then ns.Call(GameTooltip.Hide, GameTooltip) end end)
  d.title = UI.Text(d, "GameFontNormal", 52, -10, DETAIL_W - 60, "gold")
  d.sub = UI.Text(d, "GameFontHighlightSmall", 52, -28, DETAIL_W - 60, "textSecondary")
  d.head = UI.Text(d, "GameFontNormalSmall", 8, -52, DETAIL_W - 16, "gold")
  d.head:SetText(L["Reagents: price and in your bags"])
  d.rows = {}
  for i = 1, 8 do
    local r = CreateFrame("Button", nil, d)
    r:SetSize(DETAIL_W - 16, 18)
    r.tex = r:CreateTexture(nil, "ARTWORK")
    r.tex:SetSize(16, 16)
    r.tex:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.tex, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r:Hide()
    d.rows[i] = r
  end
  d.crafters = UI.Text(d, "GameFontHighlightSmall", 8, -220, DETAIL_W - 16, "textSecondary")
  local BW = math.floor((DETAIL_W - 16 - 6) / 2)
  d.wish = UI.FlatButton(d, BW, 24, L["Wish"])
  d.wish:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 8, 8)
  d.wish:SetScript("OnClick", ns.Guard("profit wish", function() if page.selected then ns.ShowWishForm(page.selected) end end))
  d.whisper = UI.FlatButton(d, BW, 24, "")
  d.whisper:SetPoint("LEFT", d.wish, "RIGHT", 6, 0)
  d.whisper:SetScript("OnClick", ns.Guard("profit whisper", function()
    if page.crafter and page.selected then ns.WhisperCrafter(page.crafter, page.selected) end
  end))
  -- wider window: the recipe column takes the extra width, the other columns and the detail box move right
  p.OnWidth = function(self, w)
    local dw = w - PAGE_W
    for i, h in ipairs(HEADS) do
      local b = self.heads[i]
      if i == 1 then
        b:SetWidth(h[3] + dw)
      else
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self, "TOPLEFT", h[2] + dw, -TOP)
      end
    end
    self.headLine:ClearAllPoints()
    self.headLine:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(TOP + HEAD_H))
    self.headLine:SetPoint("TOPRIGHT", self, "TOPLEFT", LIST_W + dw, -(TOP + HEAD_H))
    self.scan:ClearAllPoints()
    self.scan:SetPoint("TOPRIGHT", self, "TOPLEFT", w, 0)
    self.list:SetWidth(LIST_W + dw)
    self.info:SetWidth(w)
    self.empty:SetWidth(LIST_W + dw)
    self.detail:ClearAllPoints()
    self.detail:SetPoint("TOPLEFT", self, "TOPLEFT", DETAIL_X + dw, -TOP)
  end
  p.OnResize = function(self, h)
    self.list:SetHeight(h - TOP - HEAD_H - 22)
    self.detail:SetHeight(h - TOP - 20)
    self.info:ClearAllPoints()
    self.info:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(h - 16))
  end
  p.Refresh = function() Refresh() end
end

ns.On("AUCTION_HOUSE_SHOW", function() if page and page:IsVisible() then ns.After(0.3, Refresh) end end)
ns.On("AUCTION_HOUSE_CLOSED", function() if page and page:IsVisible() then ns.After(0.3, Refresh) end end)
