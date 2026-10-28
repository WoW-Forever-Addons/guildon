local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Tab "Wish list" and the wish form (GUILDON_PLAN.md step 3). Data and rules in Wishes.lua.
-- Left: the wishes (filter: for me, my wishes, I can craft, all), grouped; right: the chosen wish with what the
-- player may do (accept, crafted, sent, give back, received, cancel, delete, whisper).
---------------------------------------------------------------------------
local UI = ns.UI
local PAGE_W, CONTENT_H = ns.PAGE_W, ns.CONTENT_H
local LIST_W = 340
local DETAIL_X = LIST_W + 12
local DETAIL_W = PAGE_W - DETAIL_X
local TOP = 30

ns.WISH_FILTERS = { "me", "mine", "craft", "all" }
local FILTER_TEXT = { me = "For me", mine = "My wishes", craft = "I can craft", all = "All wishes" }
local STATE_KIND = { o = "open", a = "accepted", m = "crafted", s = "sent", d = "done", c = "done", x = "bad", e = "done" }
local PAL = Style.PAL
ns.WISH_STATES = { "all", "o", "a", "m", "s", "d" }

local function Icon(tex, size) return ("|T%s:%d:%d|t"):format(tostring(tex), size or 16, size or 16) end
local function ClassFile(owner)
  local m = ns.Member(owner)
  return m and m.classFile ~= "" and m.classFile or ((ns.InfoOf(owner) or {}).classFile or "")
end
local function Colored(owner) return "|c" .. ns.ClassHex(ClassFile(owner)) .. ns.ShortName(owner) .. "|r" end
local function ClassWho(owner)
  local file = ClassFile(owner)
  local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or ""
  return "|c" .. ns.ClassHex(file) .. (name ~= "" and (name .. " ") or "") .. ns.ShortName(owner) .. "|r"
end
local function RecipeTitle(spell) return ns.SpellName(spell) or L["Recipe %d"]:format(spell) end

-- an input field (numeric fields take digits only); the look is Kit.lua's
function UI.Field(parent, w, numeric, hint, maxLetters)
  return UI.EditBox(parent, w, hint, { numeric = numeric, maxLetters = maxLetters })
end

---------------------------------------------------------------------------
-- Wish form
---------------------------------------------------------------------------
local form
local FORM_W, FORM_H = 400, 336
local BODY_TOP = 76 -- top of the "Amount" row while hint and reagents take one line each

-- grow the form when the hint or the reagents wrap
local function LayoutForm()
  local function H(fs)
    local t = fs:GetText()
    if not t or t == "" then return 0 end
    return tonumber(fs:GetStringHeight()) or 12
  end
  local top = math.max(BODY_TOP, 32 + H(form.sub) + 2 + H(form.reag) + 10)
  form.body:ClearAllPoints()
  form.body:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -top)
  form:SetHeight(FORM_H + top - BODY_TOP)
end

local function BuildForm()
  form = CreateFrame("Frame", "GuildonWishForm", UIParent)
  form:SetSize(FORM_W, FORM_H)
  form:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  form:SetFrameStrata("DIALOG")
  form:EnableMouse(true)
  form:SetMovable(true)
  form:RegisterForDrag("LeftButton")
  form:SetScript("OnDragStart", function(self) self:StartMoving() end)
  form:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  ns.UI.Skin(form, Style.PAL.popup, { C.background[1], C.background[2], C.background[3], 0.97 })
  form.icon = form:CreateTexture(nil, "ARTWORK")
  form.icon:SetSize(32, 32)
  form.icon:SetPoint("TOPLEFT", form, "TOPLEFT", 12, -12)
  form.title = UI.Text(form, "GameFontNormal", 52, -14, FORM_W - 64, "gold")
  form.sub = UI.Text(form, "GameFontHighlightSmall", 52, -32, FORM_W - 64, "textSecondary")
  form.reag = UI.Text(form, "GameFontDisableSmall", 52, -48, FORM_W - 64, "textHint")
  -- the hint can wrap (longer in other languages): the reagents sit under it
  -- and the rows below move down with them (LayoutForm)
  form.reag:ClearAllPoints()
  form.reag:SetPoint("TOPLEFT", form.sub, "BOTTOMLEFT", 0, -2)
  form.body = CreateFrame("Frame", nil, form)
  form.body:SetSize(FORM_W, FORM_H - BODY_TOP - 40)
  form.body:SetPoint("TOPLEFT", form, "TOPLEFT", 0, -BODY_TOP)
  local body = form.body
  local y = 0
  local function Label(text, yy) return UI.Text(body, "GameFontHighlightSmall", 12, yy - 4, 110, "textSecondary"):SetText(text) end
  Label(L["Amount"], y)
  form.count = UI.Field(body, 60, true, "1", 3)
  form.count:SetPoint("TOPLEFT", body, "TOPLEFT", 126, y)
  y = y - 30
  Label(L["Payment"], y)
  form.pay = {}
  for i, key in ipairs(ns.PAY) do
    local b = UI.CheckBox(body, L[ns.PAY_TEXT[key]], function() return form.payKey == key end,
      function() form.payKey = key form:SyncPay() end, { w = FORM_W - 138, h = 20 })
    b:SetPoint("TOPLEFT", body, "TOPLEFT", 126, y - (i - 1) * 22)
    b.key = key
    form.pay[i] = b
  end
  function form:SyncPay()
    for _, b in ipairs(self.pay) do b:Sync() end
  end
  y = y - 3 * 22 - 8
  Label(L["Tip (gold)"], y)
  form.tip = UI.Field(body, 60, true, "0", 4)
  form.tip:SetPoint("TOPLEFT", body, "TOPLEFT", 126, y)
  form.estimate = UI.Text(body, "GameFontHighlightSmall", 196, y - 4, FORM_W - 208, "textHint")
  y = y - 30
  Label(L["Note"], y)
  form.note = UI.Field(body, FORM_W - 138, false, L["optional"], 60)
  form.note:SetPoint("TOPLEFT", body, "TOPLEFT", 126, y)
  y = y - 30
  Label(L["For"], y)
  form.target = UI.Dropdown(body, FORM_W - 138, {
    title = L["Who should craft it"],
    get = function() return form.targetKey or "" end,
    options = function()
      local out = { { "", L["Everyone who can craft it"] } }
      for _, o in ipairs(form.spell and ns.CraftersOf(form.spell) or {}) do
        if o ~= ns.MyName() then out[#out + 1] = { o, ns.ShortName(o) .. (ns.IsOnline(o) and "" or ("  (" .. L["offline"] .. ")")) } end
      end
      return out
    end,
    onPick = function(key) form.targetKey = key end,
  })
  form.target:SetPoint("TOPLEFT", body, "TOPLEFT", 126, y)
  form.count.nextField, form.tip.nextField, form.note.nextField = form.tip, form.note, form.count
  form.count.prevField, form.tip.prevField, form.note.prevField = form.note, form.count, form.tip
  form.err = UI.Text(form, "GameFontHighlightSmall", 12, -FORM_H + 52, FORM_W - 24, "critical")
  form.err:ClearAllPoints()
  form.err:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 12, 40) -- moves with the height
  form.send = UI.FlatButton(form, 120, 24, L["Make the wish"])
  form.send:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 12, 12)
  form.send:SetScript("OnClick", ns.Guard("wish send", function()
    local count = tonumber(form.count:GetText() or "") or 1
    local tip = (tonumber(form.tip:GetText() or "") or 0) * 10000
    local w, why = ns.AddWish(form.spell, count, form.payKey, tip, form.note:GetText(), form.targetKey ~= "" and form.targetKey or nil, form.item)
    if not w then
      form.err:SetText(why == "full" and L["You have too many open wishes."] or L["Please check the amount."])
      return
    end
    form:Hide()
    ns.Print(L["Wish made: %s. Crafters in the guild see it in their wish list."]:format(ns.WishInfo(w).title))
    ns.OpenTab("wishes")
    if ns.SelectWish then ns.SelectWish((ns.MyName() or "") .. "#" .. w.id) end
  end))
  form.cancel = UI.FlatButton(form, 100, 24, L["Cancel"])
  form.cancel:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -12, 12)
  form.cancel:SetScript("OnClick", function() form:Hide() end)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildonWishForm") end
  form:Hide()
end

local function ReagentText(info)
  local parts = {}
  for i, rg in ipairs(info.reagents or {}) do
    if i > 4 then parts[#parts + 1] = "..." break end
    parts[#parts + 1] = rg[2] .. " " .. (ns.ItemName(rg[1]) or L["Item %d"]:format(rg[1]))
  end
  return #parts > 0 and L["Reagents: %s"]:format(table.concat(parts, ", ")) or ""
end

-- item names arrive later from the server ("Item 2835" until then): fill them in when the form is open
function ns.WishFormItemInfo()
  if not form or not form:IsShown() then return end
  if form.item then
    form.title:SetText(L["Wish: %s"]:format(ns.ItemName(form.item) or L["Item %d"]:format(form.item)))
  elseif form.spell then
    form.reag:SetText(ReagentText(ns.RecipeInfo(form.spell)))
  end
  LayoutForm()
end

-- item: a wish for a gathered item (reagent) instead of a recipe
function ns.ShowWishForm(spell, item)
  if not spell and not item then return end
  if not form then BuildForm() end
  form.spell, form.item = not item and spell or nil, item
  if item then
    form.icon:SetTexture(ns.ItemIcon(item))
    form.title:SetText(L["Wish: %s"]:format(ns.ItemName(item) or L["Item %d"]:format(item)))
    local prof = ns.GatherProf(item)
    form.sub:SetText(prof and L["Members with %s see it."]:format(ns.ProfName(prof)) or L["Gatherers in the guild see it."])
    form.count:SetMaxLetters(4)
    form.reag:SetText("")
  else
    local info = ns.RecipeInfo(spell)
    form.icon:SetTexture(ns.RecipeIcon and ns.RecipeIcon(spell, info) or ns.SpellIcon(spell))
    form.title:SetText(L["Wish: %s"]:format(RecipeTitle(spell)))
    local n = #ns.CraftersOf(spell)
    local mine = 0
    for _, o in ipairs(ns.CraftersOf(spell)) do if o == ns.MyName() then mine = 1 end end
    form.sub:SetText(n - mine > 0 and L["%d in the guild can craft it."]:format(n - mine) or L["Nobody in the guild knows it yet; the wish waits for someone who learns it."])
    form.count:SetMaxLetters(3)
    form.reag:SetText(ReagentText(info))
  end
  form.count:SetText("1")
  form.tip:SetText("")
  form.note:SetText("")
  form.payKey = "m"
  form.targetKey = ""
  form:SyncPay()
  form.target:Sync()
  form.err:SetText("")
  LayoutForm()
  local est = item and ns.Price and ns.Price(item) or (not item and ns.ReagentCost and ns.ReagentCost(spell, 1))
  form.estimate:SetText(est and (item and L["AH price about %s each"] or L["reagents about %s"]):format(ns.MoneyText(est)) or "")
  form:Show()
  return form
end

function ns.WishForm() return form end -- (tests)

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local page

local function State()
  local db = ns.db
  db.wishFilter = FILTER_TEXT[db.wishFilter or ""] and db.wishFilter or "me"
  if db.wishState and not ns.STATE_TEXT[db.wishState] then db.wishState = nil end
  return db
end

local function Entry(e)
  local info = ns.WishInfo(e)
  local r = ns.WishRole(e)
  local whoName = r.mine and e.crafter or e.owner
  local count = e.count > 1 and ("  |c%sx%d|r"):format(Style.Hex("textSecondary"), e.count) or ""
  local chip = { L[ns.STATE_TEXT[e.state] or "open"], STATE_KIND[e.state] or "open" }
  if r.lost then chip = { L["taken"], "bad" } end
  return { key = e.key, wish = e, icon = info.icon, text = info.title .. count,
    sub = whoName and ClassWho(whoName) or nil, chip = chip,
    color = (e.state == "o" or e.state == "a" or e.state == "m" or e.state == "s") and "textPrimary" or "textHint" }
end

function ns.WishEntries()
  local db = State()
  local mine, craft, other = {}, {}, {}
  for _, e in ipairs(ns.VisibleWishes(db.wishFilter)) do
    if not db.wishState or e.state == db.wishState then
      local r = ns.WishRole(e)
      if r.mine then mine[#mine + 1] = e elseif r.forMe or r.crafter or r.myJob then craft[#craft + 1] = e else other[#other + 1] = e end
    end
  end
  local ORDER = { o = 1, a = 2, m = 3, s = 4, d = 5, c = 6, e = 7, x = 8 }
  local function Sort(a, b)
    if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
    return a.created > b.created
  end
  local out = {}
  local closed = type(db.wishFold) == "table" and db.wishFold or {}
  -- sections fold with a click (a big guild has many wishes)
  local function Group(list, key, title)
    if #list == 0 then return end
    table.sort(list, Sort)
    out[#out + 1] = { key = "h:" .. key, fold = key, color = "gold", topLine = #out > 0,
      text = (closed[key] and "+ " or "- ") .. title .. " (" .. #list .. ")" }
    if not closed[key] then for _, e in ipairs(list) do out[#out + 1] = Entry(e) end end
  end
  Group(craft, "craft", L["For me to craft"])
  Group(mine, "mine", L["My wishes"])
  Group(other, "other", L["Other wishes"])
  return out, #mine + #craft + #other
end

-- buttons at the bottom of the detail: label, colour, action
local function Actions(e)
  local r = ns.WishRole(e)
  local me = ns.MyName()
  local out = {}
  local function Add(label, fn, color) out[#out + 1] = { label = label, fn = fn, color = color } end
  if r.mine then
    if e.state == "a" or e.state == "m" or e.state == "s" then
      Add(L["Received"], function() ns.SetWishState(e.id, "d") if ns.CountThanks then ns.CountThanks(e.crafter) end end, "good")
      Add(L["Whisper %s"]:format(ns.ShortName(e.crafter)), function() ns.WhisperAbout(e.crafter, e) end)
    end
    if e.spell and e.pay == "m" and (e.state == "o" or e.state == "a") and ns.ShoppingList then
      Add(L["Shopping list"], function() ns.ShoppingList(e.spell, e.count) end)
    end
    if e.state == "o" or e.state == "a" or e.state == "m" or e.state == "s" then
      Add(L["Cancel wish"], function() ns.SetWishState(e.id, "c") end, "textSecondary")
    else
      Add(L["Remove"], function() ns.DeleteWish(me, e.id) end, "textSecondary")
    end
    return out
  end
  if r.lost then
    Add(L["Give back"], function() ns.SetJob(e.owner, e.id, nil) end, "textSecondary")
  elseif r.crafter then
    if e.state == "a" then Add(L["Crafted"], function() ns.SetJob(e.owner, e.id, "m") end, "good") end
    if e.state == "m" then Add(L["Sent"], function() ns.SetJob(e.owner, e.id, "s") end, "good") end
    if e.state ~= "s" then Add(L["Give back"], function() ns.SetJob(e.owner, e.id, nil) end, "textSecondary") end
  elseif e.state == "o" and r.forMe then
    Add(L["Accept"], function() ns.SetJob(e.owner, e.id, "a") end, "good")
  end
  if e.state ~= "d" and e.state ~= "c" and e.state ~= "x" then
    Add(L["Whisper %s"]:format(ns.ShortName(e.owner)), function() ns.WhisperAbout(e.owner, e) end)
  end
  if r.officer and e.state ~= "x" then Add(L["Delete"], function() ns.DeleteWish(e.owner, e.id) end, "critical") end
  return out
end
ns.WishActions = Actions

local function Line(d, i, label, text, chip)
  local l = d.lines[i]
  l.label:SetText(label)
  l.text:SetText(chip and "" or (text or ""))
  if chip then l.chip:Set(chip[1], chip[2]) l.chip:Show() else l.chip:Hide() end
  l:Show()
end

local function ShowDetail(key)
  local d = page.detail
  page.selected = key
  local e = key and ns.Wish(key)
  for _, l in ipairs(d.lines) do l:Hide() end
  for _, b in ipairs(d.buttons) do b:Hide() end
  for _, r in ipairs(d.rows) do r:Hide() end
  if not e then
    d.icon:Hide()
    d.title:SetText("")
    d.sub:SetText(L["Choose a wish on the left. New wishes start in the recipes: choose a recipe, then \"Wish\"."])
    d.rhead:Hide()
    return
  end
  local info = ns.WishInfo(e)
  d.icon:Show()
  d.icon.tex:SetTexture(info.icon)
  d.icon.item, d.icon.spell = info.item, e.spell
  d.title:SetText(info.title .. (e.count > 1 and (" x" .. e.count) or ""))
  d.sub:SetText(info.gather and (info.prof and L["To gather: %s"]:format(ns.ProfName(info.prof)) or L["To gather"]) or ns.ProfName(info.prof or 0))
  local i = 0
  local function Next(label, text, chip) i = i + 1 Line(d, i, label, text, chip) end
  local on = ns.IsOnline(e.owner)
  Next(L["From"], Colored(e.owner) .. "  |c" .. Style.Hex(on and "good" or "textHint") .. (on and L["online"] or L["offline"]) .. "|r")
  Next(L["State"], nil, { ns.WishStateText(e), STATE_KIND[e.state] or "open" })
  local r = ns.WishRole(e)
  if r.lost then Next("", "|c" .. Style.Hex("critical") .. L["Already accepted by %s."]:format(ns.ShortName(e.crafter)) .. "|r") end
  Next(L["Payment"], L[ns.PAY_TEXT[e.pay] or "I bring the reagents"])
  if (e.tip or 0) > 0 then Next(L["Tip"], ns.MoneyText(e.tip)) end
  if e.target then Next(L["For"], Colored(e.target)) end
  if e.note ~= "" then Next(L["Note"], e.note) end
  local left = math.max(0, e.expires - time())
  Next(L["Made"], ns.UI.AgeText(e.created) .. ((e.state == "o") and ("  |c" .. Style.Hex("textHint") .. L["runs out in %d days"]:format(math.ceil(left / 86400)) .. "|r") or ""))
  -- reagents for the whole amount, with what the player has
  local y = -60 - i * 20 - 6
  d.rhead:ClearAllPoints()
  d.rhead:SetPoint("TOPLEFT", d, "TOPLEFT", 8, y)
  d.rhead:Show()
  d.rhead:SetText(L["Reagents for %d"]:format(e.count))
  y = y - 18
  for k, rg in ipairs(info.reagents or {}) do
    local row = d.rows[k]
    if not row or y < -(d:GetHeight() or (CONTENT_H - TOP)) + 60 then break end
    local need, have = rg[2] * e.count, ns.ItemCount(rg[1])
    row.item = rg[1]
    row.tex:SetTexture(ns.ItemIcon(rg[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(ns.ItemName(rg[1]) or L["Item %d"]:format(rg[1]))
    row.count:SetText(("%d/%d"):format(have, need))
    UI.Color(row.count, have >= need and "good" or "critical")
    UI.Color(row.name, have >= need and "textPrimary" or "critical")
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", d, "TOPLEFT", 8, y)
    row:Show()
    y = y - 18
  end
  if info.gather then d.rhead:SetText(L["In your bags: %d of %d"]:format(ns.ItemCount(e.item), e.count))
  elseif not info.reagents or #info.reagents == 0 then d.rhead:SetText(L["Reagents unknown until a crafter opens the window."]) end
  -- buttons
  local acts = Actions(e)
  local x = 8
  for k, a in ipairs(acts) do
    local b = d.buttons[k]
    if not b then break end
    b.label:SetText(a.label)
    b.keepColor = true
    UI.Color(b.label, a.color or "textPrimary")
    b.action = a.fn
    local w = math.max(70, math.min(150, (b.label:GetStringWidth() or 60) + 20))
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", x, 8)
    x = x + w + 6
    b:Show()
  end
end

local function Refresh()
  if not page then return end
  ns.InvalidateWishes()
  local data, n = ns.WishEntries()
  page.filter:Sync()
  page.list:SetData(data)
  page.count:SetText(L["%d wishes"]:format(n))
  page.empty:SetShown(n == 0)
  local sel = page.selected
  if sel and not ns.Wish(sel) then sel = nil end
  if not sel then for _, e in ipairs(data) do if e.wish then sel = e.key break end end end
  page.list:SetSelected(sel, true)
  ShowDetail(sel)
end
ns.RefreshWishes = Refresh

function ns.SelectWish(key)
  if not page then return end
  page.selected = key
  Refresh()
end

ns.PAGE_BUILDERS.wishes = function(p)
  page = p
  State()
  p.filter = UI.Dropdown(p, 140, {
    title = L["Filter"],
    get = function() return State().wishFilter end,
    options = function()
      local out = {}
      for _, f in ipairs(ns.WISH_FILTERS) do out[#out + 1] = { f, L[FILTER_TEXT[f]] } end
      return out
    end,
    onPick = function(key) State().wishFilter = key p.selected = nil Refresh() end,
  })
  p.filter:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  -- a small filter by state (Daniel 26.10., Gemini draft)
  p.state = UI.Dropdown(p, 130, {
    title = L["State"],
    get = function() return State().wishState or "all" end,
    options = function()
      local out = { { "all", L["All states"] } }
      for _, k in ipairs(ns.WISH_STATES) do if k ~= "all" then out[#out + 1] = { k, L[ns.STATE_TEXT[k]] } end end
      return out
    end,
    onPick = function(key) State().wishState = key ~= "all" and key or nil p.selected = nil Refresh() end,
  })
  p.state:SetPoint("TOPLEFT", p, "TOPLEFT", 148, 0)
  p.new = UI.FlatButton(p, 110, 22, L["New wish"])
  p.new:SetPoint("TOPLEFT", p, "TOPLEFT", 286, 0)
  p.new:SetScript("OnClick", ns.Guard("wish new", function()
    ns.Print(L["Choose a recipe, then click \"Wish\" below its details."])
    ns.OpenTab("recipes")
  end))
  p.count = UI.Text(p, "GameFontHighlightSmall", PAGE_W - 160, -6, 160, "textHint")
  p.count:SetJustifyH("RIGHT")
  p.list = ns.NewList(p, { x = 0, y = -TOP, width = LIST_W, height = CONTENT_H - TOP, rowHeight = 38, twoLine = true,
    onSelect = function(e)
      if e.fold then
        local db = State()
        db.wishFold = type(db.wishFold) == "table" and db.wishFold or {}
        db.wishFold[e.fold] = not db.wishFold[e.fold] or nil
        Refresh()
      elseif e.wish then
        p.list:SetSelected(e.key)
        ShowDetail(e.key)
      end
    end })
  p.empty = UI.Text(p, "GameFontHighlight", 0, -TOP - 40, LIST_W, "textSecondary")
  p.empty:SetJustifyH("CENTER")
  p.empty:SetText(L["No wishes here. Wishes start in the recipes."])

  local d = CreateFrame("Frame", nil, p)
  d:SetSize(DETAIL_W, CONTENT_H - TOP)
  d:SetPoint("TOPLEFT", p, "TOPLEFT", DETAIL_X, -TOP)
  UI.Skin(d, PAL.edge, PAL.well)
  p.detail = d
  d.icon = CreateFrame("Button", nil, d)
  d.icon:SetSize(36, 36)
  d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -8)
  d.icon.tex = d.icon:CreateTexture(nil, "ARTWORK")
  d.icon.tex:SetAllPoints()
  d.icon:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    ns.Call(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
    if self.item and self.item > 0 then ns.Call(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item)
    elseif self.spell then ns.Call(GameTooltip.SetSpellByID, GameTooltip, self.spell) end
    ns.Call(GameTooltip.Show, GameTooltip)
  end)
  d.icon:SetScript("OnLeave", function() if GameTooltip then ns.Call(GameTooltip.Hide, GameTooltip) end end)
  d.sub = UI.Text(d, "GameFontHighlightSmall", 52, -9, DETAIL_W - 60, "gold")
  d.title = UI.Text(d, "GameFontNormalLarge", 52, -23, DETAIL_W - 60, "textPrimary")
  d.lines = {}
  for i = 1, 9 do
    local l = CreateFrame("Frame", nil, d)
    l:SetSize(DETAIL_W - 16, 20)
    l:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -60 - (i - 1) * 20)
    l.label = UI.Text(l, "GameFontHighlightSmall", 4, -4, 76, "textSecondary")
    l.text = UI.Text(l, "GameFontHighlightSmall", 84, -4, DETAIL_W - 104, "textPrimary")
    l.chip = UI.Chip(l, 16)
    l.chip:SetPoint("LEFT", l, "LEFT", 84, 0)
    l.chip:Hide()
    l.line = UI.Line(l)
    l.line:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 0, 0)
    l.line:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", 0, 0)
    l:Hide()
    d.lines[i] = l
  end
  d.rhead = UI.Text(d, "GameFontNormalSmall", 8, -200, DETAIL_W - 16, "gold")
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
    r:SetScript("OnEnter", function(self)
      if not GameTooltip or not self.item then return end
      ns.Call(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
      ns.Call(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item)
      ns.Call(GameTooltip.Show, GameTooltip)
    end)
    r:SetScript("OnLeave", function() if GameTooltip then ns.Call(GameTooltip.Hide, GameTooltip) end end)
    r:Hide()
    d.rows[i] = r
  end
  d.buttons = {}
  for i = 1, 4 do
    local b = UI.FlatButton(d, 100, 24, "")
    b:SetScript("OnClick", ns.Guard("wish action", function(self)
      if self.action then self.action() end
      Refresh()
    end))
    b:Hide()
    d.buttons[i] = b
  end
  p.OnResize = function(self, h)
    self.list:SetHeight(h - TOP)
    self.detail:SetHeight(h - TOP)
    if self:IsShown() and self.selected then ShowDetail(self.selected) end
  end
  -- wider window: the wish list takes the extra width, the detail box keeps its size and moves right
  p.OnWidth = function(self, w)
    local dw = w - PAGE_W
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", w - 160, -6)
    self.list:SetWidth(LIST_W + dw)
    self.empty:SetWidth(LIST_W + dw)
    self.detail:ClearAllPoints()
    self.detail:SetPoint("TOPLEFT", self, "TOPLEFT", DETAIL_X + dw, -TOP)
  end
  p.Refresh = function() Refresh() end
end

---------------------------------------------------------------------------
-- A short note when a new wish for my recipes arrives (Durchgang 5, Nr. 6), once per wish
---------------------------------------------------------------------------
function ns.OnWishesArrived(owner)
  if ns.db.notifyWishes == false then return end
  ns.db.wishSeen = type(ns.db.wishSeen) == "table" and ns.db.wishSeen or {}
  ns.InvalidateWishes()
  local now = time()
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == owner and e.state == "o" and not ns.db.wishSeen[e.key] and ns.WishRole(e).forMe then
      ns.db.wishSeen[e.key] = now
      ns.Print(L["New wish for you: %s from %s (/gn wishes)."]:format(ns.WishInfo(e).title .. (e.count > 1 and (" x" .. e.count) or ""),
        ns.ShortName(owner)))
    end
  end
  for k, t in pairs(ns.db.wishSeen) do if now - t > 60 * 86400 then ns.db.wishSeen[k] = nil end end
end

-- the wisher hears when his wish was accepted or crafted
function ns.OnJobsArrived(crafter)
  if ns.db.notifyWishes == false then return end
  ns.db.jobSeen = type(ns.db.jobSeen) == "table" and ns.db.jobSeen or {}
  ns.InvalidateWishes()
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == ns.MyName() and e.crafter == crafter then
      local k = e.key .. ":" .. e.state
      if not ns.db.jobSeen[k] and (e.state == "a" or e.state == "m" or e.state == "s") then
        ns.db.jobSeen[k] = time()
        ns.Print(L["Your wish %s: %s."]:format(ns.WishInfo(e).title, ns.WishStateText(e)))
      end
    end
  end
end
