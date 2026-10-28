local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Professions and recipes (GUILDON_PLAN.md step 2).
-- Static data: ns.RECIPES (Data/Recipes.lua for Forever, DataEra/Recipes.lua for Era, tools/build_recipes.py):
--   [spell] = { prof, minSkill, src, recipeItem, createdItem, count, "reagent:n,...", itemClass, itemSubClass, spec }
-- Own professions: skill levels at login, learned recipes whenever the own profession window opens
-- (Forever: C_TradeSkillUI, Era: the old trade skill and craft calls in Classic.lua). Shared as kind "prof".
-- Set format (only digits, letters, ":", ",", "|", "#", ";", "=", "x", "."):
--   1|<skill>:<rank>:<max>:<spells base 36, comma>|...[#<spell>=<item>x<count>.<reagent>x<n>.<reagent>x<n>;...]
-- The part after # carries result and reagents the game showed for recipes the static data does not know.
---------------------------------------------------------------------------
ns.RECIPES = ns.RECIPES or {}

-- skill line, rank spell (name and icon from the game), fallback icon; craft = has recipes
ns.PROFS = {
  { id = 171, spell = 2259, icon = "Interface\\Icons\\Trade_Alchemy", name = "Alchemy", craft = true },
  { id = 164, spell = 2018, icon = "Interface\\Icons\\Trade_BlackSmithing", name = "Blacksmithing", craft = true },
  { id = 333, spell = 7411, icon = "Interface\\Icons\\Trade_Engraving", name = "Enchanting", craft = true },
  { id = 202, spell = 4036, icon = "Interface\\Icons\\Trade_Engineering", name = "Engineering", craft = true },
  { id = 165, spell = 2108, icon = "Interface\\Icons\\INV_Misc_ArmorKit_17", name = "Leatherworking", craft = true },
  { id = 197, spell = 3908, icon = "Interface\\Icons\\Trade_Tailoring", name = "Tailoring", craft = true },
  { id = 185, spell = 2550, icon = "Interface\\Icons\\INV_Misc_Food_15", name = "Cooking", craft = true },
  { id = 129, spell = 3273, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", name = "First Aid", craft = true },
  { id = 186, spell = 2575, icon = "Interface\\Icons\\Trade_Mining", name = "Mining", craft = true },
  { id = 182, spell = 2366, icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow", name = "Herbalism" },
  { id = 393, spell = 8613, icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", name = "Skinning" },
  { id = 356, spell = 7620, icon = "Interface\\Icons\\Trade_Fishing", name = "Fishing" },
}
ns.PROF_BY_ID = {}
for i, p in ipairs(ns.PROFS) do p.order = i ns.PROF_BY_ID[p.id] = p end

---------------------------------------------------------------------------
-- Game lookups (Forever has the C_ calls, Era the old ones)
---------------------------------------------------------------------------
function ns.SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local n = ns.Str(ns.Call(C_Spell.GetSpellName, id))
    if n then return n end
  end
  if GetSpellInfo then return ns.Str((ns.Call(GetSpellInfo, id))) end
end

function ns.SpellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local t = ns.Call(C_Spell.GetSpellTexture, id)
    if t then return t end
  end
  if GetSpellTexture then return ns.Call(GetSpellTexture, id) end
end

function ns.ItemName(id)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, link = ns.Call(fn, id)
  name = ns.Str(name)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then ns.Call(C_Item.RequestLoadItemDataByID, id) end
  return name, ns.Str(link)
end

function ns.ItemIcon(id)
  local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  return ns.Call(fn, id)
end

function ns.ItemCount(id)
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  return ns.Num(ns.Call(fn, id, true)) or 0
end

function ns.ProfName(id)
  local p = ns.PROF_BY_ID[id]
  if not p then return "?" end
  if p.id ~= 182 then -- the herbalism rank spell is "Herb Gathering"
    local n = ns.SpellName(p.spell)
    if n then return n end
  end
  return L[p.name]
end

function ns.ProfIcon(id)
  local p = ns.PROF_BY_ID[id]
  if not p then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  return ns.SpellIcon(p.spell) or p.icon
end

-- profession of a localized skill line name (Era skill list, window titles)
function ns.ProfOfName(name)
  name = ns.Str(name)
  if not name then return nil end
  for _, p in ipairs(ns.PROFS) do
    if name == ns.ProfName(p.id) or name == L[p.name] or name == p.name then return p.id end
  end
end

---------------------------------------------------------------------------
-- Base 36
---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function ns.B36(n)
  n = math.floor(n)
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  end
  return s
end
function ns.UnB36(s) return tonumber(s, 36) end

---------------------------------------------------------------------------
-- Own professions: ns.db.prof[<char>] = { [skill] = { rank, max, recipes = { [spell] = true }, read = time } },
-- ns.db.learned[spell] = { item, count, { reagent, n, ... } } for recipes the static data lacks.
---------------------------------------------------------------------------
local function Mine()
  local me = ns.MyName()
  if not me then return nil end
  ns.db.prof[me] = ns.db.prof[me] or {}
  return ns.db.prof[me]
end

-- skill levels of all professions (also gathering); professions no longer there are dropped
function ns.SetSkills(list)
  local mine = Mine()
  if not mine or type(list) ~= "table" then return end
  local seen = {}
  for _, s in ipairs(list) do
    if ns.PROF_BY_ID[s.id] then
      seen[s.id] = true
      local e = mine[s.id] or { recipes = {} }
      e.rank, e.max = s.rank or e.rank or 0, s.max or e.max or 0
      mine[s.id] = e
    end
  end
  for id in pairs(mine) do if not seen[id] then mine[id] = nil end end
end

-- recipes read from the own window. full = the list is complete (Forever: all recipe IDs); otherwise the read is
-- merged into what is known (Era hides lines under folded headers and by filters).
function ns.SetRecipes(skill, rank, max, spells, full, details)
  local mine = Mine()
  if not mine or not ns.PROF_BY_ID[skill] then return end
  local e = mine[skill] or { recipes = {} }
  if full or (e.rank and rank and rank < e.rank) then e.recipes = {} end
  for _, id in ipairs(spells) do e.recipes[id] = true end
  e.rank, e.max, e.read = rank or e.rank or 0, max or e.max or 0, time()
  mine[skill] = e
  if details then
    for id, d in pairs(details) do
      if not ns.RECIPES[id] then ns.db.learned[id] = d end
    end
  end
end

-- the "prof" set of the current character
function ns.EncodeProf(entry)
  local parts, ids = { "1" }, {}
  for skill, e in pairs(entry or {}) do ids[#ids + 1] = skill end
  table.sort(ids)
  local extra = {}
  for _, skill in ipairs(ids) do
    local e = entry[skill]
    local spells = {}
    for id in pairs(e.recipes or {}) do spells[#spells + 1] = id end
    table.sort(spells)
    local enc = {}
    for i, id in ipairs(spells) do
      enc[i] = ns.B36(id)
      local d = ns.db.learned[id]
      if d and not ns.RECIPES[id] and d[1] then
        local r = { ns.B36(id) .. "=" .. ns.B36(d[1]) .. "x" .. (d[2] or 1) }
        for j = 1, #(d[3] or {}), 2 do r[#r + 1] = ns.B36(d[3][j]) .. "x" .. d[3][j + 1] end
        extra[#extra + 1] = table.concat(r, ".")
      end
    end
    parts[#parts + 1] = ("%d:%d:%d:%s"):format(skill, e.rank or 0, e.max or 0, table.concat(enc, ","))
  end
  local s = table.concat(parts, "|")
  if #extra > 0 then s = s .. "#" .. table.concat(extra, ";") end
  return s
end

-- parse a "prof" set; nil when it is not valid
function ns.DecodeProf(d)
  if type(d) ~= "string" or #d > 16000 then return nil end
  local main, extra = d:match("^([^#]*)#?(.*)$")
  if not main or main:sub(1, 1) ~= "1" then return nil end
  local out = { skills = {}, details = {} }
  local first = true
  for piece in (main .. "|"):gmatch("([^|]*)|") do
    if first then
      if piece ~= "1" then return nil end
      first = false
    else
      local skill, rank, max, list = piece:match("^(%d+):(%d+):(%d+):([%w,]*)$")
      if not skill then return nil end
      local e = { id = tonumber(skill), rank = tonumber(rank), max = tonumber(max), recipes = {} }
      for code in list:gmatch("[%w]+") do
        local id = ns.UnB36(code)
        if not id then return nil end
        e.recipes[id] = true
      end
      out.skills[e.id] = e
    end
  end
  if extra ~= "" then
    for rec in (extra .. ";"):gmatch("([^;]*);") do
      local head, rest = rec:match("^([%w]+=[%w]+x%d+)(.*)$")
      if not head then return nil end
      local id, item, n = head:match("^(%w+)=(%w+)x(%d+)$")
      local reag = {}
      for r, c in rest:gmatch("%.(%w+)x(%d+)") do reag[#reag + 1] = ns.UnB36(r) reag[#reag + 1] = tonumber(c) end
      out.details[ns.UnB36(id)] = { ns.UnB36(item), tonumber(n), reag }
    end
  end
  return out
end

function ns.ShareProf()
  local mine = Mine()
  if not mine then return end
  ns.SetOwn("prof", ns.EncodeProf(mine))
end

ns.RegisterKind("prof", {
  validate = function(d) return d:match("^[%w:,|#;=x%.]+$") ~= nil and ns.DecodeProf(d) ~= nil end,
  onUpdate = function() ns.InvalidateCrafters() end,
})

---------------------------------------------------------------------------
-- Who can craft what: index over all "prof" sets (own characters included), rebuilt on demand
---------------------------------------------------------------------------
local index -- { crafters = { [spell] = { owner, ... } }, skills = { [prof] = { { owner, rank, max, n } } }, details }

function ns.InvalidateCrafters() index = nil end

local function BuildIndex()
  index = { crafters = {}, skills = {}, details = {}, owners = {} }
  for _, set in ipairs(ns.SetsOf("prof")) do
    local p = ns.DecodeProf(set.d)
    if p then
      index.owners[set.o] = p
      for skill, e in pairs(p.skills) do
        local n = 0
        for id in pairs(e.recipes) do
          n = n + 1
          local c = index.crafters[id]
          if not c then c = {} index.crafters[id] = c end
          c[#c + 1] = set.o
        end
        index.skills[skill] = index.skills[skill] or {}
        table.insert(index.skills[skill], { owner = set.o, rank = e.rank, max = e.max, n = n, t = set.t })
      end
      for id, det in pairs(p.details) do if not index.details[id] then index.details[id] = det end end
    end
  end
  for id, d in pairs(ns.db.learned) do index.details[id] = d end
  return index
end

function ns.CraftIndex() return index or BuildIndex() end

-- (the rank filter of 25.10. is gone, 26.10.: the lists show the first 10 of a profession instead) drop the old saved choice
ns.OnInit(function() if ns.db then ns.db.rankFilter = nil end end)

-- crafters of a spell, online first, then by name
function ns.CraftersOf(spell)
  local list = ns.CraftIndex().crafters[spell] or {}
  table.sort(list, function(a, b)
    local oa, ob = ns.IsOnline(a) and true or false, ns.IsOnline(b) and true or false
    if oa ~= ob then return oa end
    return a < b
  end)
  return list
end

-- recipe details: static data first, then what the game showed (own or shared)
function ns.RecipeInfo(spell)
  local r = ns.RECIPES[spell]
  local out = { spell = spell }
  if r then
    out.prof, out.skill, out.src, out.recipeItem, out.item, out.count = r[1], r[2], r[3], r[4], r[5], r[6]
    out.cls, out.sub, out.spec, out.buff = r[8], r[9], r[10], r[11]
    out.wear = r[12] -- RequiredLevel of the crafted item (0 none, -1 unknown), RecipeBook ns.WearLevel
    out.reagents = {}
    for item, n in tostring(r[7] or ""):gmatch("(%d+):(%d+)") do out.reagents[#out.reagents + 1] = { tonumber(item), tonumber(n) } end
  end
  local d = ns.CraftIndex().details[spell]
  if d and (not out.item or out.item == 0) then
    out.item, out.count = d[1], d[2]
    out.reagents = {}
    for j = 1, #(d[3] or {}), 2 do out.reagents[#out.reagents + 1] = { d[3][j], d[3][j + 1] } end
  end
  return out
end

-- all spells of a profession: static data plus everything any guild member knows
function ns.RecipesOf(prof)
  local out, seen = {}, {}
  for id, r in pairs(ns.RECIPES) do
    if r[1] == prof then out[#out + 1] = id seen[id] = true end
  end
  for _, p in pairs(ns.CraftIndex().owners) do
    local e = p.skills[prof]
    if e then for id in pairs(e.recipes) do if not seen[id] then seen[id] = true out[#out + 1] = id end end end
  end
  return out
end

---------------------------------------------------------------------------
-- Reading the own professions (Forever: Retail calls; Era: Classic.lua sets ns.ReadSkillsEra / ns.ReadWindowEra)
---------------------------------------------------------------------------
-- most frequent profession of a list of spells (identifies a window without relying on its localized title)
function ns.ProfOfSpells(spells)
  local count, best, bestN = {}, nil, 0
  for _, id in ipairs(spells) do
    local r = ns.RECIPES[id]
    if r then
      count[r[1]] = (count[r[1]] or 0) + 1
      if count[r[1]] > bestN then best, bestN = r[1], count[r[1]] end
    end
  end
  return best
end

local function ReadSkillsRetail()
  if type(GetProfessions) ~= "function" then return nil end
  local list = {}
  local idx = { ns.Call(GetProfessions) }
  for i = 1, 5 do
    local k = idx[i]
    if k then
      local ok, _, _, rank, max, _, _, skillLine = pcall(GetProfessionInfo, k)
      if not ok then rank, max, skillLine = nil, nil, nil end
      skillLine = ns.Num(skillLine)
      if skillLine and ns.PROF_BY_ID[skillLine] then
        list[#list + 1] = { id = skillLine, rank = ns.Num(rank) or 0, max = ns.Num(max) or 0 }
      end
    end
  end
  return list
end

-- the open profession window on Forever; nil when it shows someone else's or an NPC's list
local function ReadWindowRetail()
  local T = C_TradeSkillUI
  if not T or type(T.GetAllRecipeIDs) ~= "function" then return nil end
  if ns.Call(T.IsTradeSkillLinked) or ns.Call(T.IsTradeSkillGuild) or ns.Call(T.IsNPCCrafting) then return nil end
  local info = ns.Call(T.GetBaseProfessionInfo)
  local ids = ns.Call(T.GetAllRecipeIDs)
  if type(ids) ~= "table" then return nil end
  local spells, details = {}, {}
  for _, id in ipairs(ids) do
    local ri = ns.Call(T.GetRecipeInfo, id)
    if type(ri) == "table" and ri.learned == true and ns.Num(id) then
      spells[#spells + 1] = id
      if not ns.RECIPES[id] then
        local sch = ns.Call(T.GetRecipeSchematic, id, false)
        if type(sch) == "table" and ns.Num(sch.outputItemID) then
          local reag = {}
          for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
            local r = slot.reagents and slot.reagents[1]
            if r and ns.Num(r.itemID) and ns.Num(slot.quantityRequired) then
              reag[#reag + 1] = r.itemID
              reag[#reag + 1] = slot.quantityRequired
            end
          end
          details[id] = { sch.outputItemID, ns.Num(sch.quantityMin) or 1, reag }
        end
      end
    end
  end
  local skill = type(info) == "table" and ns.Num(info.professionID)
  if not (skill and ns.PROF_BY_ID[skill]) then skill = ns.ProfOfSpells(spells) end
  if not skill then return nil end
  return { skill = skill, rank = type(info) == "table" and ns.Num(info.skillLevel) or nil,
    max = type(info) == "table" and ns.Num(info.maxSkillLevel) or nil, spells = spells, full = true, details = details }
end

function ns.ReadSkills()
  local list
  if ns.ERA then list = ns.ReadSkillsEra and ns.ReadSkillsEra() else list = ReadSkillsRetail() end
  if list then ns.SetSkills(list) ns.ShareProf() ns.InvalidateCrafters() end
end

function ns.ReadWindow(kind)
  local r
  if ns.ERA then r = ns.ReadWindowEra and ns.ReadWindowEra(kind) else r = ReadWindowRetail() end
  if not r or #r.spells == 0 then return false end
  ns.SetRecipes(r.skill, r.rank, r.max, r.spells, r.full, r.details)
  ns.ShareProf()
  ns.InvalidateCrafters()
  if ns.OnDataChanged then ns.OnDataChanged("prof", ns.MyName()) end
  return true
end

-- the recipes without a profession window (Era; see ns.ReadKnownEra): at login, when the skills change and when Guildon's window opens.
-- At most every 20 seconds; stored like a window with folded lines (merged), shared when it changed. Returns how many recipes it found.
local lastKnown = 0
function ns.ReadKnown(force)
  if not ns.ERA or not ns.ReadKnownEra or not ns.MyName() then return 0 end
  if not force and GetTime() - lastKnown < 20 then return 0 end
  lastKnown = GetTime()
  local n, changed = 0, false
  for _, r in ipairs(ns.ReadKnownEra()) do
    local e = ns.db.prof[ns.MyName()] and ns.db.prof[ns.MyName()][r.skill]
    for _, id in ipairs(r.spells) do
      n = n + 1
      if not (e and e.recipes and e.recipes[id]) then changed = true end
    end
    ns.SetRecipes(r.skill, r.rank, r.max, r.spells, false)
  end
  if changed then
    ns.ShareProf()
    ns.InvalidateCrafters()
    if ns.OnDataChanged then ns.OnDataChanged("prof", ns.MyName()) end
  end
  return n
end

-- reads are bundled: the window fires several updates while it fills
local readPending = {}
local function ReadSoon(kind)
  if readPending[kind] then return end
  readPending[kind] = true
  ns.After(0.6, function() readPending[kind] = nil ns.ReadWindow(kind) end)
end

ns.OnInit(function()
  ns.db.prof = type(ns.db.prof) == "table" and ns.db.prof or {}
  ns.db.learned = type(ns.db.learned) == "table" and ns.db.learned or {}
end)
ns.On("PLAYER_LOGIN", function() ns.After(9, ns.ReadSkills) ns.After(11, ns.ReadKnown) end)
ns.On("SKILL_LINES_CHANGED", function() ns.After(1, ns.ReadSkills) ns.After(2, ns.ReadKnown) end)
ns.On("TRADE_SKILL_SHOW", function() ReadSoon("tradeskill") end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() ReadSoon("tradeskill") end)
ns.On("TRADE_SKILL_UPDATE", function() ReadSoon("tradeskill") end)
ns.On("NEW_RECIPE_LEARNED", function() ReadSoon("tradeskill") end)
ns.On("CRAFT_SHOW", function() ReadSoon("craft") end)
ns.On("CRAFT_UPDATE", function() ReadSoon("craft") end)
ns.On("GET_ITEM_INFO_RECEIVED", function() if ns.OnItemInfo then ns.OnItemInfo() end end)

---------------------------------------------------------------------------
-- Whisper a crafter (opens the chat line, the player sends it)
---------------------------------------------------------------------------
-- group invitation (Daniel 26.10.: "Gruppeneinladung über die Punkte der Gildenmember"): C_PartyInfo.InviteUnit (older clients:
-- InviteUnit) is not protected; the game itself says when the group is full or the player already is in one
function ns.InviteMember(owner)
  if not owner or owner == ns.MyName() then return false end
  if ns.IsDemo(owner) then ns.Print(L["%s is an example member and cannot be invited."]:format(ns.ShortName(owner))) return false end
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  if not fn then return false end
  return (pcall(fn, ns.ShortName(owner)))
end

function ns.WhisperCrafter(owner, spell)
  if not owner then return end
  if ns.IsDemo(owner) then ns.Print(L["%s is an example member and cannot be whispered."]:format(ns.ShortName(owner))) return end
  local reach, alt = owner, false
  if ns.ReachableName then reach, alt = ns.ReachableName(owner) end
  if alt then ns.Print(L["%s is offline; whispering the alt %s."]:format(ns.ShortName(owner), ns.ShortName(reach))) end
  local target = ns.ShortName(reach)
  local info = spell and ns.RecipeInfo(spell)
  local what
  if info and info.item and info.item > 0 then
    local name, link = ns.ItemName(info.item)
    what = link or name
  end
  what = what or (spell and ns.SpellName(spell)) or ""
  local text = ("/w %s %s"):format(target, spell and L["Hi, could you craft %s for me?"]:format(what) or "")
  local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
  if open then ns.Call(open, text) return true end
  local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
  if tell then ns.Call(tell, target) return true end
end
