local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Tabs "Professions" and "Recipe book" (GUILDON_PLAN.md step 2, "Bedienung").
-- Professions: every profession with who in the guild has it (skill, online); click a profession opens the
-- recipe book on it, click a member opens a whisper.
-- Recipe book: profession buttons, search, filter (all / someone can / nobody can / I can / online now),
-- skill from and to, recipes grouped by category (fold by click), marker who can craft, detail on the right
-- with result, reagents (own count in bags and bank), crafters with online state and a whisper button.
---------------------------------------------------------------------------
local UI = ns.UI
local PAGE_W, CONTENT_H = ns.PAGE_W, ns.CONTENT_H
local LIST_W = 320
local DETAIL_X = LIST_W + 12
local DETAIL_W = PAGE_W - DETAIL_X
local TOP = 58

ns.BOOK_FILTERS = { "all", "someone", "nobody", "mine", "online" }
local FILTER_TEXT = { all = "All recipes", someone = "Someone can", nobody = "Nobody can", mine = "I can", online = "Online now" }
local SRC_TEXT = { t = "Trainer", i = "Recipe item", q = "Quest", s = "Learned with the profession", c = "Trainer or recipe (classic data)",
  f = "New in Forever (client data)", p = "Seen in the game (player report)" }

local function Hex(classFile) return ns.ClassHex(classFile) end
local function ClassOf(owner)
  local m = ns.Member(owner)
  if m and m.classFile ~= "" then return m.classFile end
  local info = ns.InfoOf(owner)
  return info and info.classFile or ""
end
local function Colored(owner) return "|c" .. Hex(ClassOf(owner)) .. ns.ShortName(owner) .. "|r" end
local function Icon(tex, size) return ("|T%s:%d:%d|t"):format(tostring(tex), size or 16, size or 16) end

local function ItemText(id)
  local name = ns.ItemName(id)
  return name or L["Item %d"]:format(id)
end

-- the picture the game shows for a recipe: the created item, else the spell (enchantments), else the profession
function ns.RecipeIcon(spell, info)
  info = info or ns.RecipeInfo(spell)
  return (info.item and info.item > 0 and ns.ItemIcon(info.item)) or ns.SpellIcon(spell) or ns.ProfIcon(info.prof or 0)
end

-- the link of a recipe for the chat: the crafted item, else the spell
function ns.LinkRecipe(spell)
  local info = ns.RecipeInfo(spell)
  local link
  if info.item and info.item > 0 then link = select(2, ns.ItemName(info.item)) end
  if not link then
    local fn = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
    link = ns.Str((ns.Call(fn, spell)))
  end
  local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
  if link and insert then return ns.Call(insert, link) end
end

local function RecipeName(spell)
  return ns.SpellName(spell) or L["Recipe %d"]:format(spell)
end

-- Type of the crafted good (Daniel 25.10.: "nach Art des herzustellenden Gutes, Rüstung nach Platz"): from the game
-- (GetItemInfoInstant needs no cache): armour by slot, weapons by kind, everything else by item subclass; enchantments
-- without an item; the static class/subclass as fallback. Returns key, label, sort order.
local SLOT_ORDER = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY",
  "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER",
  "INVTYPE_TRINKET", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }
local SLOT_RANK, SLOT_SAME = {}, { INVTYPE_ROBE = "INVTYPE_CHEST" }
for i, k in ipairs(SLOT_ORDER) do SLOT_RANK[k] = i end
local typeCache = {}

local function Instant(item)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil end
  local ok, id, typeName, subName, equipLoc, _, classID, subID = pcall(fn, item)
  if not ok or not id then return nil end
  return ns.Str(typeName), ns.Str(subName), ns.Str(equipLoc), ns.Num(classID), ns.Num(subID)
end

-- cooking by what the food gives (Daniel 25.10.: "agi food, stärke food, ap food"), from the data (build_recipes.py)
local BUFF_TEXT = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", ap = "Attack power",
  sp = "Spell power", heal = "Healing", mp5 = "Mana regeneration", hp5 = "Health regeneration" }
local BUFF_RANK = { str = 1, agi = 2, ap = 3, sta = 4, int = 5, spi = 6, sp = 7, heal = 8, mp5 = 9, hp5 = 10 }
local function FoodType(buff)
  if buff == "food" then return "food", L["Food without a buff"], 50 end
  if buff == "drink" then return "drink", L["Drinks"], 51 end
  if buff == "special" then return "special", L["Special effects"], 52 end
  local parts, first = {}, nil
  for tag in buff:gmatch("[^+]+") do
    if not BUFF_TEXT[tag] then return "other", L["Other"], 999 end
    parts[#parts + 1] = L[BUFF_TEXT[tag]]
    first = first or BUFF_RANK[tag]
  end
  return "buff:" .. buff, L["Food: %s"]:format(table.concat(parts, L[" and "])), first + #parts / 10
end

function ns.RecipeType(info)
  if info.prof == 185 and info.buff and info.buff ~= "" then return FoodType(info.buff) end
  local item = info.item or 0
  if item == 0 then
    if info.prof == 333 then return "ench", L["Enchantments"], 900 end
    return "other", L["Other"], 999
  end
  local hit = typeCache[item]
  if hit then return hit[1], hit[2], hit[3] end
  local typeName, subName, equipLoc, cls, sub = Instant(item)
  cls, sub = cls or info.cls, sub or info.sub
  local key, label, order
  equipLoc = SLOT_SAME[equipLoc or ""] or equipLoc
  if cls == 4 and equipLoc and SLOT_RANK[equipLoc] then
    key, label, order = "slot:" .. equipLoc, ns.Str(_G[equipLoc]) or equipLoc, SLOT_RANK[equipLoc]
  elseif cls == 2 then
    key, order = "weapon:" .. tostring(sub), 100
    label = subName or ns.Str((ns.Call((C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo, 2, sub))) or L["Weapons"]
  elseif cls and cls >= 0 then
    key, order = "c:" .. cls .. ":" .. tostring(sub), 200 + cls
    label = subName or ns.Str((ns.Call((C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo, cls, sub)))
      or typeName or ns.Str((ns.Call((C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo, cls))) or L["Other"]
  else
    key, label, order = "other", L["Other"], 999
  end
  if typeName or subName then typeCache[item] = { key, label, order } end -- only answers from the game are kept
  return key, label, order
end

---------------------------------------------------------------------------
-- Professions tab
---------------------------------------------------------------------------
-- Master and detail (Daniel 26.10., Gemini draft): the professions in a column on the left (online / in the guild), on the
-- right the best crafters of the chosen one with a skill bar, online first. A big guild shows the first TOP_CRAFTERS and
-- the rest opens with a click on the last line (ns.db.profOpen).
local TOP_CRAFTERS = 10
local PROF_W = 224
local PD_X = PROF_W + 12
local PD_W = PAGE_W - PD_X
local PD_TOP = 36
local PAL = Style.PAL

local function ClassName(owner)
  local m = ns.Member(owner)
  if m and m.class and m.class ~= "" then return m.class end
  local file = ClassOf(owner)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or ""
end

local function CooldownEntries()
  local out = {}
  local now = time()
  for _, c in ipairs(ns.GuildCooldowns and ns.GuildCooldowns() or {}) do
    local left = (c.ready or 0) - now
    local on = ns.IsOnline(c.owner)
    out[#out + 1] = { key = "cd:" .. c.cd.key .. ":" .. c.owner, owner = c.owner,
      text = UI.Dot(on) .. " " .. Colored(c.owner),
      cols = { "|c" .. Style.Hex("textSecondary") .. L[c.cd.label] .. "|r" },
      value = left <= 0 and ("|c" .. Style.Hex("good") .. L["ready"] .. "|r") or L["in %s"]:format(left >= 86400 and
        L["%d days"]:format(math.ceil(left / 86400)) or L["%d h"]:format(math.ceil(left / 3600))) }
  end
  return out
end

-- every profession with its crafters (online first, then skill, then name): most members first, the empty ones last
local function ProfessionData()
  local idx = ns.CraftIndex()
  local recs, byId, active, empty = {}, {}, {}, {}
  for _, p in ipairs(ns.PROFS) do
    local list = {}
    for _, e in ipairs(idx.skills[p.id] or {}) do list[#list + 1] = e end
    local online = 0
    for _, e in ipairs(list) do e.on = ns.IsOnline(e.owner) and true or false if e.on then online = online + 1 end end
    table.sort(list, function(x, y)
      if x.on ~= y.on then return x.on end
      if (x.rank or 0) ~= (y.rank or 0) then return (x.rank or 0) > (y.rank or 0) end
      return x.owner < y.owner
    end)
    local rec = { p = p, list = list, online = online }
    byId[p.id] = rec
    if #list > 0 then active[#active + 1] = rec else empty[#empty + 1] = rec end
  end
  table.sort(active, function(a, b)
    if #a.list ~= #b.list then return #a.list > #b.list end
    return a.p.order < b.p.order
  end)
  for _, r in ipairs(active) do recs[#recs + 1] = r end
  for _, r in ipairs(empty) do recs[#recs + 1] = r end
  return recs, byId
end

local function ProfessionRows(recs, cds)
  local out = {}
  if #cds > 0 then
    out[#out + 1] = { key = "cd", sel = "cd", text = Icon("Interface\\Icons\\INV_Misc_PocketWatch_01", 18) .. "  " .. L["Cooldowns"],
      value = tostring(#cds), tooltip = function() return L["Cooldowns"], { L["Transmute, Mooncloth and Salt Shaker of the members with Guildon."] } end }
  end
  for _, r in ipairs(recs) do
    local has = #r.list > 0
    out[#out + 1] = { key = "p:" .. r.p.id, sel = r.p.id,
      text = Icon(ns.ProfIcon(r.p.id), 18) .. "  " .. ns.ProfName(r.p.id), color = has and "textPrimary" or "textHint",
      value = ("%d / %d"):format(r.online, #r.list), valueColor = has and "textSecondary" or "textHint" }
  end
  return out
end

local function CrafterRows(rec)
  local p, list, me = rec.p, rec.list, ns.MyName()
  local out = {}
  local open = ns.db.profOpen and ns.db.profOpen[p.id]
  local cut = #list > TOP_CRAFTERS and not open
  for i, e in ipairs(list) do
    if not (cut and i > TOP_CRAFTERS) then
      local hint
      if p.craft and not p.gather and e.n == 0 then
        hint = e.owner == me and L["Open your profession window once so that Guildon can read your recipes."]
          or L["Recipes not read yet."]
      end
      local full = (e.max or 0) > 0 and (e.rank or 0) >= e.max
      out[#out + 1] = { key = "m:" .. p.id .. ":" .. e.owner, owner = e.owner, prof = p.id,
        text = UI.Dot(e.on) .. " " .. Colored(e.owner) .. (e.on and "" or ("  |c" .. Style.Hex("textHint") .. L["offline"] .. "|r")),
        cols = { "|c" .. ns.ClassHex(ClassOf(e.owner)) .. ClassName(e.owner) .. "|r" },
        value = ("%d / %d"):format(e.rank or 0, e.max or 0) .. ((p.craft and not p.gather and e.n == 0) and " *" or ""),
        meter = { e.rank or 0, e.max or 0, full and C.good or nil },
        tooltip = function()
          local lines = { L["Skill %d of %d"]:format(e.rank or 0, e.max or 0) }
          if p.craft then lines[#lines + 1] = L["Recipes: %d"]:format(e.n) end
          lines[#lines + 1] = L["Data from %s"]:format(UI.AgeText(e.t))
          if hint then lines[#lines + 1] = hint end
          return ns.ShortName(e.owner), lines, e.owner ~= me and L["Click: whisper"] or nil
        end }
    end
  end
  if #list > TOP_CRAFTERS then
    out[#out + 1] = { key = "more:" .. p.id, more = p.id, color = "textSecondary", topLine = true,
      text = open and L["Show only the first %d, click"]:format(TOP_CRAFTERS) or L["%d more, click to show"]:format(#list - TOP_CRAFTERS) }
  end
  if #list == 0 then
    out[#out + 1] = { key = "none", color = "textHint", text = L["Nobody in the guild yet"] }
  end
  return out
end

ns.PAGE_BUILDERS.professions = function(p)
  p.left = ns.NewList(p, { x = 0, y = 0, width = PROF_W, height = CONTENT_H, rowHeight = 26,
    onSelect = function(e)
      if e.sel then ns.db.profSel = e.sel p:Refresh() end
    end })
  p.box = UI.Box(p, PAL.edge, PAL.well)
  p.box:SetSize(PD_W, CONTENT_H)
  p.box:SetPoint("TOPLEFT", p, "TOPLEFT", PD_X, 0)
  p.title = UI.Text(p.box, "GameFontNormalLarge", 10, -8, PD_W - 330, "gold")
  p.stats = UI.Text(p.box, "GameFontHighlightSmall", PD_W - 8 - 100 - 8 - 190, -12, 190, "textSecondary")
  p.stats:SetJustifyH("RIGHT")
  p.recipes = UI.FlatButton(p.box, 100, 20, L["Recipes"])
  p.recipes:SetPoint("TOPLEFT", p.box, "TOPLEFT", PD_W - 8 - 100, -7)
  p.recipes:SetTip(L["Recipes"], nil, L["Click: open the recipes of this profession."])
  p.recipes:SetScript("OnClick", ns.Guard("professions recipes", function()
    local sel = ns.db.profSel
    if type(sel) == "number" and ns.PROF_BY_ID[sel] and ns.PROF_BY_ID[sel].craft then ns.OpenRecipes(sel) end
  end))
  p.list = ns.NewList(p, { x = PD_X + 4, y = -PD_TOP, width = PD_W - 8, height = CONTENT_H - PD_TOP - 4, rowHeight = ns.ROW_H,
    columns = { { 176, 90, "LEFT" } }, textRight = 168, meterWidth = 170, growText = true,
    onSelect = function(e)
      if e.more then
        ns.db.profOpen = type(ns.db.profOpen) == "table" and ns.db.profOpen or {}
        ns.db.profOpen[e.more] = not ns.db.profOpen[e.more] or nil
        p:Refresh()
      elseif e.owner then
        if e.owner ~= ns.MyName() then ns.WhisperCrafter(e.owner) end
      end
    end })
  p.OnResize = function(self, h)
    self.left:SetHeight(h)
    self.box:SetHeight(h)
    self.list:SetHeight(h - PD_TOP - 4)
  end
  -- wider window: the crafter box takes the extra width, the profession list at the left stays
  p.OnWidth = function(self, w)
    local pw = PD_W + (w - PAGE_W)
    self.box:SetWidth(pw)
    self.title:SetWidth(pw - 330)
    self.stats:ClearAllPoints()
    self.stats:SetPoint("TOPLEFT", self.box, "TOPLEFT", pw - 8 - 100 - 8 - 190, -12)
    self.recipes:ClearAllPoints()
    self.recipes:SetPoint("TOPLEFT", self.box, "TOPLEFT", pw - 8 - 100, -7)
    self.list:SetWidth(pw - 8)
  end
  p.Refresh = function(self)
    local recs, byId = ProfessionData()
    local cds = ns.GuildCooldowns and ns.GuildCooldowns() or {}
    local sel = ns.db.profSel
    if not (sel == "cd" and #cds > 0) and not byId[sel] then
      sel = nil
      for _, r in ipairs(recs) do if #r.list > 0 then sel = r.p.id break end end
      sel = sel or (recs[1] and recs[1].p.id)
      ns.db.profSel = sel
    end
    self.left:SetData(ProfessionRows(recs, cds))
    self.left:SetSelected(sel == "cd" and "cd" or ("p:" .. tostring(sel)))
    if sel == "cd" then
      self.title:SetText(L["Cooldowns"])
      self.stats:SetText("")
      self.recipes:Hide()
      self.list:SetData(CooldownEntries())
    else
      local rec = byId[sel]
      self.title:SetText(rec and ns.ProfName(rec.p.id) or "")
      self.stats:SetText(rec and L["%d in the guild, %d online"]:format(#rec.list, rec.online) or "")
      self.recipes:SetShown(rec and rec.p.craft and true or false)
      self.list:SetData(rec and CrafterRows(rec) or {})
    end
  end
end

---------------------------------------------------------------------------
-- Recipe book
---------------------------------------------------------------------------
local book -- the page

local function BookState()
  local db = ns.db
  if not ns.PROF_BY_ID[db.bookProf or 0] or not ns.PROF_BY_ID[db.bookProf].craft then
    db.bookProf = 171
    local mine = db.prof[ns.MyName() or ""]
    if mine then
      for _, pr in ipairs(ns.PROFS) do if pr.craft and mine[pr.id] then db.bookProf = pr.id break end end
    end
  end
  db.bookFilter = FILTER_TEXT[db.bookFilter or ""] and db.bookFilter or "all"
  -- groups are closed by default (Daniel 25.10.); bookOpen holds the ones the player opened (bookFold was the old,
  -- open-by-default table and is dropped)
  db.bookOpen = type(db.bookOpen) == "table" and db.bookOpen or {}
  db.bookFold = nil
  db.bookType = type(db.bookType) == "string" and db.bookType or "all"
  return db
end

-- the level from which the crafted item can be worn or used: the game's own item data first (Forever changes some),
-- else the data file (CMaNGOS RequiredLevel, -1 = unknown); nil when nothing says
function ns.WearLevel(info)
  local item = info.item
  if not item or item == 0 then return nil end
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if fn then
    local ok, _, _, _, _, minLevel = pcall(fn, item)
    minLevel = ok and ns.Num(minLevel) or nil
    if minLevel then return minLevel end
  end
  local d = info.wear
  if d and d >= 0 then return d end
  return nil
end

local function Passes(db, spell, info, crafters, search, from, to)
  local f = db.bookFilter
  if f == "someone" and #crafters == 0 then return false end
  if f == "nobody" and #crafters > 0 then return false end
  if f == "mine" or f == "online" then
    local me, ok = ns.MyName(), false
    for _, o in ipairs(crafters) do
      if (f == "mine" and o == me) or (f == "online" and ns.IsOnline(o)) then ok = true break end
    end
    if not ok then return false end
  end
  -- level range: from which character level the crafted item can be used; recipes without an item or without a known level stay
  if from or to then
    local lvl = ns.WearLevel(info)
    if lvl then
      lvl = math.max(lvl, 1) -- 0 = no requirement = from level 1
      if (from and lvl < from) or (to and lvl > to) then return false end
    end
  end
  if search ~= "" then
    local hay = RecipeName(spell):lower()
    if info.item and info.item > 0 then hay = hay .. " " .. (ns.ItemName(info.item) or ""):lower() end
    if not hay:find(search, 1, true) then return false end
  end
  return true
end

-- marker: one tick everywhere (Daniel 26.10.): green when a crafter is online, grey when only offline crafters know it;
-- a number in front for several
local function Marker(crafters)
  if #crafters == 0 then return "" end
  local online = false
  for _, o in ipairs(crafters) do if ns.IsOnline(o) then online = true break end end
  local mark = UI.Tick(14, online and "good" or "dim")
  if #crafters > 1 then mark = ("|c%s%d|r "):format(Style.Hex(online and "good" or "textSecondary"), #crafters) .. mark end
  return mark
end

function ns.BookEntries()
  local db = BookState()
  local search = book and book.search and tostring(book.search:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
  local from = book and book.from and tonumber(book.from:GetText() or "")
  local to = book and book.to and tonumber(book.to:GetText() or "")
  local groups, order, labels, rank = {}, {}, {}, {}
  local types, typeSeen = {}, {}
  local total, shown = 0, 0
  for _, spell in ipairs(ns.RecipesOf(db.bookProf)) do
    local info = ns.RecipeInfo(spell)
    info.prof = info.prof or db.bookProf
    local tkey, tlabel, tord = ns.RecipeType(info)
    if not typeSeen[tkey] then typeSeen[tkey] = true types[#types + 1] = { key = tkey, label = tlabel, order = tord } end
    local crafters = ns.CraftersOf(spell)
    total = total + 1
    if (db.bookType == "all" or db.bookType == tkey) and Passes(db, spell, info, crafters, search, from, to) then
      shown = shown + 1
      if not groups[tkey] then groups[tkey] = {} order[#order + 1] = tkey labels[tkey] = tlabel rank[tkey] = tord end
      table.insert(groups[tkey], { spell = spell, info = info, crafters = crafters, name = RecipeName(spell) })
    end
  end
  local function ByOrder(a, b)
    local ra, rb = rank[a] or a.order, rank[b] or b.order
    if type(a) == "table" then ra, rb = a.order, b.order end
    if ra ~= rb then return ra < rb end
    if type(a) == "table" then return a.label < b.label end
    return labels[a] < labels[b]
  end
  table.sort(order, ByOrder)
  -- groups open by themselves while searching or filtering, and when only one group is left
  local auto = search ~= "" or from ~= nil or to ~= nil or db.bookFilter ~= "all" or #order == 1
  local autoClosed = book and book.autoClosed or {}
  if book and not auto then book.autoClosed = {} end
  table.sort(types, ByOrder)
  ns.bookTypes = types
  local out = {}
  for _, tkey in ipairs(order) do
    local cat = labels[tkey]
    local g = groups[tkey]
    table.sort(g, function(a, b)
      if (a.info.skill or 0) ~= (b.info.skill or 0) then return (a.info.skill or 0) < (b.info.skill or 0) end
      return a.name < b.name
    end)
    local foldKey = db.bookProf .. ":" .. cat
    local folded
    if auto then folded = autoClosed[foldKey] == true else folded = not db.bookOpen[foldKey] end
    out[#out + 1] = { key = "c:" .. cat, fold = foldKey, auto = auto, topLine = #out > 0, color = "textSecondary",
      text = (folded and "+ " or "- ") .. cat, value = tostring(#g), valueColor = "textHint" }
    if not folded then
      for _, r in ipairs(g) do
        local skill = (r.info.skill or 0) > 0 and ("  |c%s%d|r"):format(Style.Hex("textHint"), r.info.skill) or ""
        out[#out + 1] = { key = r.spell, spell = r.spell, text = Icon(ns.RecipeIcon(r.spell, r.info), 14) .. " " .. r.name .. skill,
          value = Marker(r.crafters),
          color = #r.crafters > 0 and "textPrimary" or "textHint" }
      end
    end
  end
  return out, total, shown
end

-- detail on the right
-- the detail on the right is one stack from the top (layout review 25.10.): title, source, result when it says more
-- than the title, reagents with icons and have/need, a thin line, the crafters as far as there is room, buttons at the bottom
local DETAIL_H = CONTENT_H - TOP
local BUTTONS_H = 40

local function Place(region, y, h)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", book.detail, "TOPLEFT", 8, y)
  return y - (h or 16)
end

local function ShowDetail(spell)
  local d = book.detail
  book.selected = spell
  ns.db.bookSpell = spell
  for _, r in ipairs(d.rows) do r:Hide() end
  for _, b in ipairs(d.crafters) do b:Hide() end
  if not spell then
    d.icon:Hide()
    d.title:SetText("")
    d.sub:SetText(L["Choose a recipe on the left."])
    for _, f in ipairs({ d.src, d.makes, d.rhead, d.line, d.head, d.more, d.whisper, d.wish }) do f:Hide() end
    return
  end
  local info = ns.RecipeInfo(spell)
  local prof = info.prof or ns.db.bookProf
  local title = RecipeName(spell)
  d.icon:Show()
  d.icon.tex:SetTexture(ns.RecipeIcon(spell, info))
  d.icon.spell, d.icon.item = spell, info.item
  d.title:SetText(title)
  -- recipe wanted (Durchgang 5 Nr. 3): a toggle for recipes the player cannot craft yet
  local mineCan = false
  for _, o in ipairs(ns.CraftIndex().crafters[spell] or {}) do if o == ns.MyName() then mineCan = true end end
  d.want:SetShown(not mineCan and ns.SetWanted ~= nil)
  d.want.spell = spell
  d.want:Sync()
  local sub = ns.ProfName(prof)
  if (info.skill or 0) > 0 then sub = sub .. "  " .. L["from skill %d"]:format(info.skill) end
  d.sub:SetText(sub)
  local y = -52
  if info.src then
    local src = L[SRC_TEXT[info.src] or "Other"]
    if info.recipeItem and info.recipeItem > 0 then src = src .. ": " .. ItemText(info.recipeItem) end
    d.src:SetText(L["Source: %s"]:format(src))
    d.src:Show()
    y = Place(d.src, y, 16)
  else
    d.src:Hide()
  end
  -- who wants it, and who could learn it when nobody knows it
  local wanted = ns.WantedBy and ns.WantedBy(spell) or {}
  if #wanted > 0 then
    local names = {}
    for i = 1, math.min(#wanted, 4) do names[i] = ns.ShortName(wanted[i]) end
    d.wanted:SetText(L["Wanted by %s"]:format(table.concat(names, ", ")) .. (#wanted > 4 and (" " .. L["and %d more"]:format(#wanted - 4)) or ""))
    d.wanted:Show()
    y = Place(d.wanted, y, 16)
  else
    d.wanted:Hide()
  end
  -- "Makes" only when it says more than the title (another name or several pieces)
  local made = info.item and info.item > 0 and ItemText(info.item)
  if made and (made ~= title or (info.count or 1) > 1) then
    d.makes:SetText(L["Makes: %s"]:format(made .. ((info.count or 1) > 1 and (" x" .. info.count) or "")))
    d.makes:Show()
    y = Place(d.makes, y, 16)
  else
    d.makes:Hide()
  end
  y = y - 6
  d.rhead:Show()
  y = Place(d.rhead, y, 18)
  if info.reagents and #info.reagents > 0 then
    d.rhead:SetText(L["Reagents"])
    for i, rg in ipairs(info.reagents) do
      local r = d.rows[i]
      if not r then break end
      local have = ns.ItemCount(rg[1])
      r.item = rg[1]
      r.tex:SetTexture(ns.ItemIcon(rg[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
      r.name:SetText(ItemText(rg[1]))
      r.count:SetText(("%d/%d"):format(have, rg[2]))
      UI.Color(r.count, have >= rg[2] and "good" or "critical")
      UI.Color(r.name, have >= rg[2] and "textPrimary" or "critical")
      r:Show()
      y = Place(r, y, 18)
    end
  else
    d.rhead:SetText(L["Reagents unknown until a crafter opens the window."])
  end
  y = y - 6
  d.line:ClearAllPoints()
  d.line:SetPoint("TOPLEFT", d, "TOPLEFT", 8, y)
  d.line:SetPoint("TOPRIGHT", d, "TOPRIGHT", -8, y)
  d.line:Show()
  y = y - 8
  d.head:Show()
  y = Place(d.head, y, 18)
  local crafters = ns.CraftersOf(spell)
  book.crafter = nil
  -- as many crafter rows as fit above the buttons; the last one says how many more there are
  local room = math.max(1, math.floor(((d:GetHeight() or DETAIL_H) - BUTTONS_H + y) / 20))
  local shownN = math.min(#crafters, room, #d.crafters)
  if #crafters > shownN then shownN = math.max(1, shownN - 1) end
  for i = 1, shownN do
    local o, b = crafters[i], d.crafters[i]
    b.owner = o
    local on = ns.IsOnline(o)
    b.label:SetText(UI.Dot(on) .. " " .. Colored(o) .. "  |c" .. Style.Hex(on and "good" or "textHint") .. (on and L["online"] or L["offline"]) .. "|r")
    b:Show()
    y = Place(b, y, 20)
    if not book.crafter and on and o ~= ns.MyName() then book.crafter = o end
  end
  if #crafters == 0 then
    local b = d.crafters[1]
    b.owner = nil
    b.label:SetText("|c" .. Style.Hex("textHint") .. L["Nobody in the guild knows this recipe yet."] .. "|r")
    b:Show()
    y = Place(b, y, 20)
  end
  if #crafters > shownN then
    d.more:SetText(L["and %d more"]:format(#crafters - shownN))
    d.more:Show()
    Place(d.more, y - 2, 16)
  else
    d.more:Hide()
  end
  if not book.crafter then
    for _, o in ipairs(crafters) do if o ~= ns.MyName() then book.crafter = o break end end
  end
  d.whisper:SetShown(book.crafter ~= nil)
  if book.crafter then d.whisper.label:SetText(L["Whisper %s"]:format(ns.ShortName(book.crafter))) end
  d.wish:ClearAllPoints()
  d.wish:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", book.crafter and (8 + math.floor((DETAIL_W - 16 - 6) / 2) + 6) or 8, 8)
  d.wish:Show()
end

local function RefreshBook()
  if not book then return end
  local db = BookState()
  for _, b in ipairs(book.profButtons) do
    -- (Daniel 26.10.) the chosen profession simply in full colour; the others grey and dim, no box around it
    b.on = b.prof == db.bookProf
    b.tex:SetDesaturated(not b.on)
    local v = b.on and 1 or 0.5
    b.tex:SetVertexColor(v, v, v)
  end
  book.profTitle:SetText(ns.ProfName(db.bookProf))
  local data, total, shown = ns.BookEntries()
  if db.bookType ~= "all" then
    local found = false
    for _, t in ipairs(ns.bookTypes or {}) do if t.key == db.bookType then found = true end end
    if not found then db.bookType = "all" data, total, shown = ns.BookEntries() end
  end
  book.filter:Sync()
  book.kind:Sync()
  book.list:SetData(data)
  book.count:SetText(L["%d of %d"]:format(shown, total))
  local sel = book.selected
  if sel then
    local r = ns.RECIPES[sel]
    if r and r[1] ~= db.bookProf then sel = nil end
  end
  book.list:SetSelected(sel, true)
  ShowDetail(sel)
end
ns.RefreshBook = RefreshBook

function ns.RecipeBookShow(prof, spell)
  local db = BookState()
  if prof and ns.PROF_BY_ID[prof] and ns.PROF_BY_ID[prof].craft then db.bookProf = prof end
  if book then book.selected = spell end
  db.bookSpell = spell
end

-- A dropdown field: own frames (pattern of Dropdon's slot choice), closes on a choice, a second click or a click beside it.
-- opts: get() -> key, options() -> { { key, label }, ... }, onPick(key), title (tooltip). Long lists open in columns.
local MENU_ROW, MENU_MAX = 18, 18
function ns.UI.Dropdown(parent, w, opts)
  local b = UI.FlatButton(parent, w, 22, "")
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", -18, 0)
  b.label:SetJustifyH("LEFT")
  b.caret = b:CreateTexture(nil, "OVERLAY")
  b.caret:SetSize(10, 10)
  b.caret:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.caret:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  b.caret:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
  local catcher = CreateFrame("Button", nil, parent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("DIALOG")
  catcher:Hide()
  local menu = CreateFrame("Frame", nil, parent)
  menu:SetFrameStrata("DIALOG")
  menu:SetFrameLevel((catcher:GetFrameLevel() or 1) + 5)
  menu:EnableMouse(true)
  menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
  local edge = menu:CreateTexture(nil, "BACKGROUND")
  edge:SetAllPoints()
  edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
  local fill = menu:CreateTexture(nil, "BORDER")
  fill:SetPoint("TOPLEFT", 1, -1)
  fill:SetPoint("BOTTOMRIGHT", -1, 1)
  local low = Style.BOOK and Style.BOOK.cardLow or C.background
  fill:SetColorTexture(low[1], low[2], low[3], 0.99)
  menu:Hide()
  menu.rows = {}
  b.menu = menu
  local function Close() menu:Hide() catcher:Hide() end
  b.Close = Close
  function b:Sync()
    local cur = opts.get()
    for _, o in ipairs(opts.options()) do if o[1] == cur then self.label:SetText(o[2]) return end end
    self.label:SetText("")
  end
  local function Open()
    local list, cur = opts.options(), opts.get()
    local cols = math.max(1, math.ceil(#list / MENU_MAX))
    local perCol = math.ceil(#list / cols)
    local colW = math.max(w, 170)
    menu:SetSize(cols * colW + 6, perCol * MENU_ROW + 6)
    for i, o in ipairs(list) do
      local r = menu.rows[i]
      if not r then
        r = CreateFrame("Button", nil, menu)
        r:SetHeight(MENU_ROW)
        r.active = r:CreateTexture(nil, "BACKGROUND")
        r.active:SetAllPoints()
        r.active:SetColorTexture(C.rowActive[1], C.rowActive[2], C.rowActive[3], C.rowActive[4] or 1)
        r.hover = r:CreateTexture(nil, "BORDER")
        r.hover:SetAllPoints()
        r.hover:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4] or 1)
        r.hover:Hide()
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r:SetScript("OnEnter", function(self) self.hover:Show() end)
        r:SetScript("OnLeave", function(self) self.hover:Hide() end)
        r:SetScript("OnClick", ns.Guard("dropdown", function(self)
          Close()
          opts.onPick(self.key)
          b:Sync()
        end))
        menu.rows[i] = r
      end
      local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", menu, "TOPLEFT", 3 + col * colW, -3 - row * MENU_ROW)
      r:SetWidth(colW)
      r.key = o[1]
      r.text:SetText(o[2])
      UI.Color(r.text, o[1] == cur and "accent" or "textPrimary")
      r.active:SetShown(o[1] == cur)
      r:Show()
    end
    for i = #list + 1, #menu.rows do menu.rows[i]:Hide() end
    catcher:Show()
    menu:Show()
  end
  catcher:SetScript("OnClick", Close)
  b:SetScript("OnClick", ns.Guard("dropdown", function() if menu:IsShown() then Close() else Open() end end))
  b:SetScript("OnHide", Close)
  b:SetTip(opts.title, nil, L["Click: choose"])
  b.Open = Open
  return b
end

local function EditBox(parent, x, y, w, numeric, tip)
  local e = UI.EditBox(parent, w, tip, { numeric = numeric, onChange = function() RefreshBook() end })
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  return e
end

ns.PAGE_BUILDERS.recipes = function(p)
  book = p
  BookState()
  p.profButtons = {}
  local x = 0
  for _, pr in ipairs(ns.PROFS) do
    if pr.craft then
      local b = CreateFrame("Button", nil, p)
      b:SetSize(24, 24)
      b:SetPoint("TOPLEFT", p, "TOPLEFT", x, 0)
      b.prof = pr.id
      b.tex = b:CreateTexture(nil, "ARTWORK")
      b.tex:SetAllPoints()
      b.tex:SetTexture(ns.ProfIcon(pr.id))
      b:SetScript("OnClick", ns.Guard("book prof", function(self)
        ns.db.bookProf = self.prof
        ns.db.bookType = "all"
        book.selected = nil
        -- a new profession starts with empty search and skill fields (Daniel 25.10.)
        for _, f in ipairs({ book.search, book.from, book.to }) do
          f:SetText("")
          if f.hint then f.hint:Show() end
          if f.clear then f.clear:Hide() end
          if f.ClearFocus then f:ClearFocus() end
        end
        RefreshBook()
      end))
      b:SetScript("OnEnter", function(self)
        if not self.on then self.tex:SetVertexColor(0.85, 0.85, 0.85) end
        Style.Tooltip(self, ns.ProfName(self.prof))
      end)
      b:SetScript("OnLeave", function(self)
        if not self.on then self.tex:SetVertexColor(0.5, 0.5, 0.5) end
        Style.HideTooltip(self)
      end)
      p.profButtons[#p.profButtons + 1] = b
      x = x + 28
    end
  end
  p.filter = UI.Dropdown(p, 160, {
    title = L["Filter"],
    get = function() return BookState().bookFilter end,
    options = function()
      local out = {}
      for _, f in ipairs(ns.BOOK_FILTERS) do out[#out + 1] = { f, L[FILTER_TEXT[f]] } end
      return out
    end,
    onPick = function(key) BookState().bookFilter = key RefreshBook() end,
  })
  p.filter:SetPoint("TOPRIGHT", p, "TOPLEFT", PAGE_W, 0)
  -- (Daniel 26.10.: "in dem rot markierten Bereich noch das ausgewählte Handwerk reinschreiben") the chosen profession's name in the free
  -- space between the profession buttons and the filter
  local titleX = x + 8
  p.profTitle = UI.Text(p, "GameFontNormalLarge", titleX, -4, math.max(60, PAGE_W - 160 - 12 - titleX), "gold")
  p.search = EditBox(p, 206, -30, 220, false, L["Search"])
  -- from and to: the level from which the crafted item can be worn or used (Daniel 26.10.), not the skill
  p.from = EditBox(p, 432, -30, 44, true, L["from"])
  p.to = EditBox(p, 480, -30, 44, true, L["to"])
  for _, f in ipairs({ p.from, p.to }) do
    f:HookScript("OnEnter", function(self)
      Style.Tooltip(self, L["Wearable from level"], { L["Shows recipes whose item can be worn or used from this character level up to that level."] })
    end)
    f:HookScript("OnLeave", function(self) Style.HideTooltip(self) end)
  end
  p.search.nextField, p.from.nextField, p.to.nextField = p.from, p.to, p.search
  p.search.prevField, p.from.prevField, p.to.prevField = p.to, p.search, p.from
  p.kind = UI.Dropdown(p, 200, {
    title = L["Type"],
    get = function() return BookState().bookType end,
    options = function()
      local out = { { "all", L["All types"] } }
      for _, t in ipairs(ns.bookTypes or {}) do out[#out + 1] = { t.key, t.label } end
      return out
    end,
    onPick = function(key) BookState().bookType = key book.selected = nil RefreshBook() end,
  })
  p.kind:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -29)
  p.count = UI.Text(p, "GameFontHighlightSmall", PAGE_W - 120, -34, 120, "textHint")
  p.count:SetJustifyH("RIGHT")
  p.list = ns.NewList(p, { x = 0, y = -TOP, width = LIST_W, height = CONTENT_H - TOP, rowHeight = 20,
    onSelect = function(e)
      if e.fold then
        local db = BookState()
        if e.auto then
          book.autoClosed = book.autoClosed or {}
          book.autoClosed[e.fold] = not book.autoClosed[e.fold] or nil
        else
          db.bookOpen[e.fold] = not db.bookOpen[e.fold] or nil
        end
        RefreshBook()
      elseif e.spell then
        -- shift-click puts the link into the open chat line, like in the game's profession window
        if IsShiftKeyDown and IsShiftKeyDown() and ns.LinkRecipe(e.spell) then return end
        book.selected = e.spell
        book.list:SetSelected(e.spell)
        ShowDetail(e.spell)
      end
    end })

  -- detail
  local d = CreateFrame("Frame", nil, p)
  d:SetSize(DETAIL_W, CONTENT_H - TOP)
  d:SetPoint("TOPLEFT", p, "TOPLEFT", DETAIL_X, -TOP)
  UI.Skin(d, Style.PAL.edge, Style.PAL.well)
  p.detail = d
  d.icon = CreateFrame("Button", nil, d)
  d.icon:SetSize(36, 36)
  d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -8)
  d.icon.tex = d.icon:CreateTexture(nil, "ARTWORK")
  d.icon.tex:SetAllPoints()
  d.icon:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    ns.Call(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
    if self.item and self.item > 0 then
      if GameTooltip.SetItemByID then ns.Call(GameTooltip.SetItemByID, GameTooltip, self.item)
      else ns.Call(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item) end
    elseif self.spell then
      ns.Call(GameTooltip.SetSpellByID, GameTooltip, self.spell)
    end
    ns.Call(GameTooltip.Show, GameTooltip)
  end)
  d.icon:SetScript("OnLeave", function() if GameTooltip then ns.Call(GameTooltip.Hide, GameTooltip) end end)
  d.title = UI.Text(d, "GameFontNormal", 52, -10, DETAIL_W - 140, "gold")
  local want
  want = UI.CheckBox(d, L["Want"], function() return want and want.spell and ns.IsWanted and ns.IsWanted(want.spell) end,
    function()
      local sp = want and want.spell
      if not sp then return end
      ns.SetWanted(sp, not ns.IsWanted(sp))
      ShowDetail(sp)
    end, { w = 70 })
  d.want = want
  d.want:SetPoint("TOPRIGHT", d, "TOPRIGHT", -8, -10)
  d.want:SetTip(L["Want"], { L["Tell the guild you want to learn this recipe. Recipe items then name you in their tooltip."] })
  d.want:Hide()
  d.sub = UI.Text(d, "GameFontHighlightSmall", 52, -28, DETAIL_W - 60, "textSecondary")
  d.src = UI.Text(d, "GameFontHighlightSmall", 8, -52, DETAIL_W - 16, "textHint")
  d.makes = UI.Text(d, "GameFontHighlightSmall", 8, -68, DETAIL_W - 16, "textPrimary")
  d.wanted = UI.Text(d, "GameFontHighlightSmall", 8, -68, DETAIL_W - 16, "accent")
  d.rhead = UI.Text(d, "GameFontNormalSmall", 8, -84, DETAIL_W - 16, "gold")
  d.rhead:SetText(L["Reagents"])
  -- reagent rows: 16 px icon, name, have/need right aligned; mouse over shows the item
  d.rows = {}
  for i = 1, 8 do
    local r = CreateFrame("Button", nil, d)
    r:SetSize(DETAIL_W - 16, 18)
    r.tex = r:CreateTexture(nil, "ARTWORK")
    r.tex:SetSize(16, 16)
    r.tex:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.count:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.tex, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r:SetScript("OnEnter", function(self)
      if not GameTooltip or not self.item then return end
      ns.Call(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then ns.Call(GameTooltip.SetItemByID, GameTooltip, self.item)
      else ns.Call(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item) end
      ns.Call(GameTooltip.AddLine, GameTooltip, L["Click: wish it from the guild's gatherers"], 0.25, 0.66, 0.96)
      ns.Call(GameTooltip.Show, GameTooltip)
    end)
    r:SetScript("OnLeave", function() if GameTooltip then ns.Call(GameTooltip.Hide, GameTooltip) end end)
    -- click: wish this reagent from the guild's gatherers (Durchgang 5 Nr. 2)
    r:SetScript("OnClick", ns.Guard("book reagent", function(self)
      if self.item and ns.ShowWishForm then ns.ShowWishForm(nil, self.item) end
    end))
    r:Hide()
    d.rows[i] = r
  end
  d.line = d:CreateTexture(nil, "ARTWORK")
  d.line:SetHeight(1)
  d.line:SetColorTexture(Style.PAL.edge[1], Style.PAL.edge[2], Style.PAL.edge[3], 0.35)
  d.head = UI.Text(d, "GameFontNormalSmall", 8, -212, DETAIL_W - 16, "gold")
  d.head:SetText(L["Who can craft it"])
  d.crafters = {}
  for i = 1, 30 do
    local b = CreateFrame("Button", nil, d)
    b:SetSize(DETAIL_W - 16, 18)
    b.hover = b:CreateTexture(nil, "BACKGROUND")
    b.hover:SetAllPoints()
    b.hover:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4] or 0.05)
    b.hover:Hide()
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "LEFT", 6, 0)
    b.label:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", ns.Guard("book crafter", function(self)
      if not self.owner or self.owner == ns.MyName() then return end
      book.crafter = self.owner
      d.whisper.label:SetText(L["Whisper %s"]:format(ns.ShortName(self.owner)))
      d.whisper:Show()
    end))
    b:Hide()
    d.crafters[i] = b
  end
  d.more = UI.Text(d, "GameFontHighlightSmall", 8, -332, DETAIL_W - 16, "textHint")
  local BW = math.floor((DETAIL_W - 16 - 6) / 2)
  d.whisper = UI.FlatButton(d, BW, 24, "")
  d.whisper:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 8, 8)
  d.whisper:SetScript("OnClick", ns.Guard("book whisper", function()
    if book.crafter and book.selected then ns.WhisperCrafter(book.crafter, book.selected) end
  end))
  d.wish = UI.FlatButton(d, BW, 24, L["Wish"])
  d.wish:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 8 + BW + 6, 8)
  d.wish:SetScript("OnClick", ns.Guard("book wish", function() if book.selected and ns.ShowWishForm then ns.ShowWishForm(book.selected) end end))
  d.wish:SetTip(L["Wish"], { L["Ask the guild for this recipe: crafters see your wish in their wish list."] })

  p.selected = ns.db.bookSpell
  p.OnResize = function(self, h)
    self.list:SetHeight(h - TOP)
    self.detail:SetHeight(h - TOP)
  end
  -- wider window: the recipe list takes the extra width, the detail box keeps its size and moves right
  p.OnWidth = function(self, w)
    local dw = w - PAGE_W
    self.filter:ClearAllPoints()
    self.filter:SetPoint("TOPRIGHT", self, "TOPLEFT", w, 0)
    self.profTitle:SetWidth(math.max(60, w - 160 - 12 - titleX))
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", w - 120, -34)
    self.list:SetWidth(LIST_W + dw)
    self.detail:ClearAllPoints()
    self.detail:SetPoint("TOPLEFT", self, "TOPLEFT", DETAIL_X + dw, -TOP)
  end
  p.Refresh = function() RefreshBook() end
end

-- item names arrive later from the server: repaint the open book once
local itemQueued = false
function ns.OnItemInfo()
  if ns.WishFormItemInfo then ns.WishFormItemInfo() end
  if itemQueued or not book or not book:IsVisible() then return end
  itemQueued = true
  ns.After(0.5, function() itemQueued = false RefreshBook() end)
end
