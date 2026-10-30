local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Extras (GUILDON_PLAN.md "Durchgang 5", Daniel's decision 4: all of them in the first version)
--  1 cooldowns of the guild (transmute, Mooncloth, Salt Shaker): kind "cd"
--  3 recipe wanted: members mark recipes they want ("want"); a recipe item's tooltip says who could learn it
--  4 shopping list of the missing reagents (Auctionator list when it is there, else a text to copy)
--  6 notes when a member who can craft my wish comes online (the wish notes are in WishList.lua)
--  7 alts: own characters of one account linked ("alts"), whispers go to the one who is online
--  8 member tooltip: professions with skill, last seen, Guildon version, alts, orders crafted
--  9 guild emblem next to the window title (Forever: C_GuildInfo.GetGuildTabardInfo)
-- 10 thanks counter: orders received per crafter ("thx"), no ranking, no gold
-- 11 Questdon's arrow to a member on the map; item tooltips name who in the guild crafts the item
-- (2 wishes for gathered items: Wishes.lua, 5 cash on delivery: Trade.lua)
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- 1 Cooldowns
---------------------------------------------------------------------------
-- key, label, spells (one shared cooldown), item (cooldown of an item), profession
ns.COOLDOWNS = {
  { key = "t", label = "Transmute", prof = 171, spells = { 11479, 11480, 17187, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566 } },
  { key = "m", label = "Mooncloth", prof = 197, spells = { 18560 } },
  { key = "s", label = "Salt Shaker", prof = 165, item = 15846 },
}

local function Known(spell)
  local entry = (ns.db.prof or {})[ns.MyName() or ""]
  for _, e in pairs(entry or {}) do if e.recipes and e.recipes[spell] then return true end end
  return false
end

-- seconds until ready (0 = ready), nil when unknown
local function SpellLeft(spell)
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = ns.Call(C_Spell.GetSpellCooldown, spell)
    if type(info) == "table" then start, duration = ns.Num(info.startTime), ns.Num(info.duration) end
  elseif GetSpellCooldown then
    start, duration = ns.Call(GetSpellCooldown, spell)
    start, duration = ns.Num(start), ns.Num(duration)
  end
  if not start or not duration then return nil end
  if duration <= 2 then return 0 end -- the global cooldown
  return math.max(0, start + duration - GetTime())
end

local function ItemLeft(item)
  local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  local start, duration = ns.Call(fn, item)
  start, duration = ns.Num(start), ns.Num(duration)
  if not start or not duration then return nil end
  if duration <= 2 then return 0 end
  return math.max(0, start + duration - GetTime())
end

function ns.ReadCooldowns()
  local parts, now = { "1" }, time()
  for _, cd in ipairs(ns.COOLDOWNS) do
    local left
    if cd.item then
      if ns.ItemCount(cd.item) > 0 then left = ItemLeft(cd.item) end
    else
      for _, sp in ipairs(cd.spells) do
        if Known(sp) then left = SpellLeft(sp) break end
      end
    end
    if left then parts[#parts + 1] = cd.key .. "," .. ns.B36(left > 0 and math.floor(now + left) or 0) end
  end
  if #parts == 1 then return false end
  return ns.SetOwn("cd", table.concat(parts, ";"))
end

function ns.DecodeCooldowns(d)
  if type(d) ~= "string" or #d > 200 or d:sub(1, 1) ~= "1" then return nil end
  local out, first = {}, true
  for piece in (d .. ";"):gmatch("([^;]*);") do
    if first then
      if piece ~= "1" then return nil end
      first = false
    else
      local key, t = piece:match("^(%l),(%w+)$")
      if not key then return nil end
      out[key] = ns.UnB36(t)
    end
  end
  return out
end

ns.RegisterKind("cd", { validate = function(d) return ns.DecodeCooldowns(d) ~= nil end })

-- list for the professions tab: { cd, owner, ready (unix, 0 = now) }
function ns.GuildCooldowns()
  local out = {}
  for _, set in ipairs(ns.SetsOf("cd")) do
    for key, t in pairs(ns.DecodeCooldowns(set.d) or {}) do
      for _, cd in ipairs(ns.COOLDOWNS) do
        if cd.key == key then out[#out + 1] = { cd = cd, owner = set.o, ready = t } end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.cd.key ~= b.cd.key then return a.cd.key > b.cd.key end
    if a.ready ~= b.ready then return a.ready < b.ready end
    return a.owner < b.owner
  end)
  return out
end

local cdPending = false
local function CooldownsSoon()
  if cdPending then return end
  cdPending = true
  ns.After(5, function() cdPending = false ns.ReadCooldowns() end)
end
ns.On("PLAYER_LOGIN", function() ns.After(12, ns.ReadCooldowns) end)
ns.On("SPELL_UPDATE_COOLDOWN", CooldownsSoon)
ns.On("BAG_UPDATE_COOLDOWN", CooldownsSoon)
ns.OnInit(function() ns.NewTicker(300, ns.ReadCooldowns) end)

---------------------------------------------------------------------------
-- 3 Recipes wanted
---------------------------------------------------------------------------
local function DB()
  ns.db.wants = type(ns.db.wants) == "table" and ns.db.wants or {}
  ns.db.thanks = type(ns.db.thanks) == "table" and ns.db.thanks or {}
  return ns.db
end

local function ShareWants()
  local list = {}
  for spell in pairs(DB().wants) do list[#list + 1] = spell end
  table.sort(list)
  for i, s in ipairs(list) do list[i] = ns.B36(s) end
  ns.SetOwn("want", "1;" .. table.concat(list, ","))
end

function ns.SetWanted(spell, on)
  DB().wants[spell] = on and true or nil
  ShareWants()
  if ns.OnDataChanged then ns.OnDataChanged("want", ns.MyName()) end
end
function ns.IsWanted(spell) return DB().wants[spell] == true end

ns.RegisterKind("want", { validate = function(d) return d:match("^1;[%w,]*$") ~= nil and #d < 4000 end })

-- members who want a recipe (the player too)
function ns.WantedBy(spell)
  local out = {}
  for _, set in ipairs(ns.SetsOf("want")) do
    for code in set.d:sub(3):gmatch("%w+") do if ns.UnB36(code) == spell then out[#out + 1] = set.o break end end
  end
  if ns.IsWanted(spell) then
    local me, have = ns.MyName(), false
    for _, o in ipairs(out) do if o == me then have = true end end
    if not have then out[#out + 1] = me end
  end
  return out
end

-- members who have the profession with enough skill and do not know the recipe yet
function ns.CouldLearn(spell)
  local info = ns.RecipeInfo(spell)
  local out = {}
  if not info.prof then return out end
  for owner, p in pairs(ns.CraftIndex().owners) do
    local e = p.skills[info.prof]
    if e and not e.recipes[spell] then out[#out + 1] = { owner = owner, ok = (e.rank or 0) >= (info.skill or 0), rank = e.rank } end
  end
  table.sort(out, function(a, b) if a.ok ~= b.ok then return a.ok end return a.owner < b.owner end)
  return out
end

---------------------------------------------------------------------------
-- 10 Thanks: the wisher counts received orders per crafter
---------------------------------------------------------------------------
function ns.CountThanks(crafter)
  if not crafter or crafter == ns.MyName() then return end
  local db = DB()
  db.thanks[crafter] = (db.thanks[crafter] or 0) + 1
  local parts = { "1" }
  local names = {}
  for name in pairs(db.thanks) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do parts[#parts + 1] = name .. "," .. db.thanks[name] end
  ns.SetOwn("thx", table.concat(parts, ";"))
end

ns.RegisterKind("thx", { validate = function(d) return d:match("^1[^|]*$") ~= nil and #d < 4000 end })

function ns.ThanksOf(crafter)
  local n = 0
  for _, set in ipairs(ns.SetsOf("thx")) do
    for name, c in set.d:gmatch(";([^,;]+),(%d+)") do if name == crafter then n = n + tonumber(c) end end
  end
  return n -- the own set is among the sets
end

---------------------------------------------------------------------------
-- 7 Alts: the characters of this account (all that ran Guildon), shared by each of them
---------------------------------------------------------------------------
local function ShareAlts()
  local me = ns.MyName()
  if not me then return end
  local names, seen = {}, {}
  for owner in pairs(ns.db.chars or {}) do if not seen[owner] then seen[owner] = true names[#names + 1] = owner end end
  for owner in pairs(ns.db.prof or {}) do if not seen[owner] then seen[owner] = true names[#names + 1] = owner end end
  if #names < 2 then return end
  table.sort(names)
  ns.SetOwn("alts", "1;" .. table.concat(names, ";"))
end
ns.RegisterKind("alts", { validate = function(d) return d:match("^1;[^|,]+$") ~= nil and #d < 2000 end })
ns.On("PLAYER_LOGIN", function() ns.After(14, ShareAlts) end)

-- the characters linked with this one (not itself)
function ns.AltsOf(name)
  local out, seen = {}, { [name] = true }
  for _, set in ipairs(ns.SetsOf("alts")) do
    local has = false
    for n in set.d:sub(3):gmatch("[^;]+") do if n == name then has = true end end
    if has then for n in set.d:sub(3):gmatch("[^;]+") do if not seen[n] then seen[n] = true out[#out + 1] = n end end end
  end
  table.sort(out)
  return out
end

-- whom to whisper: the character itself when online, else an alt of the same account that is online
function ns.ReachableName(name)
  if ns.IsOnline(name) then return name end
  for _, alt in ipairs(ns.AltsOf(name)) do if ns.IsOnline(alt) and ns.IsMember(alt) then return alt, true end end
  return name
end

---------------------------------------------------------------------------
-- 8 Member tooltip lines
---------------------------------------------------------------------------
function ns.MemberLines(m)
  local lines = {}
  local p = ns.CraftIndex().owners[m.name]
  if p then
    local parts = {}
    for _, pr in ipairs(ns.PROFS) do
      local e = p.skills[pr.id]
      if e then parts[#parts + 1] = ("%s %d/%d"):format(ns.ProfName(pr.id), e.rank or 0, e.max or 0) end
    end
    if #parts > 0 then lines[#lines + 1] = table.concat(parts, ", ") end
  end
  if not m.online and m.lastOnline then
    lines[#lines + 1] = L["Last seen: %s"]:format(m.lastOnline < 1 and L["today"] or L["%d days ago"]:format(m.lastOnline))
  end
  local alts = ns.AltsOf(m.name)
  if #alts > 0 then
    local short = {}
    for i, a in ipairs(alts) do short[i] = ns.ShortName(a) end
    lines[#lines + 1] = L["Alts: %s"]:format(table.concat(short, ", "))
  end
  local thx = ns.ThanksOf(m.name)
  if thx > 0 then lines[#lines + 1] = L["Orders crafted for the guild: %d"]:format(thx) end
  return lines
end

---------------------------------------------------------------------------
-- 6 A member comes online who can craft one of my open wishes or works on one
---------------------------------------------------------------------------
function ns.OnMemberOnline(name)
  if ns.db.notifyWishes == false or not ns.Wishes then return end
  local me = ns.MyName()
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == me and (e.state == "o" or e.state == "a" or e.state == "m") then
      local can = e.crafter == name
      if not can and e.state == "o" and e.spell then
        for _, o in ipairs(ns.CraftIndex().crafters[e.spell] or {}) do if o == name then can = true end end
      end
      if can and (not e.target or e.target == name) then
        ns.Print(L["%s is online and can craft your wish %s."]:format(ns.ShortName(name), ns.WishInfo(e).title))
        return
      end
    end
  end
end

---------------------------------------------------------------------------
-- 4 Shopping list
---------------------------------------------------------------------------
-- the reagents still missing for a recipe x count: { { item, pieces } }
function ns.MissingReagents(spell, count)
  local out = {}
  for _, r in ipairs(ns.RecipeInfo(spell).reagents or {}) do
    local miss = r[2] * (count or 1) - ns.ItemCount(r[1])
    if miss > 0 then out[#out + 1] = { r[1], miss } end
  end
  return out
end

function ns.ShoppingList(spell, count)
  local miss = ns.MissingReagents(spell, count)
  if #miss == 0 then ns.Print(L["You have all reagents."]) return "none" end
  local title = (ns.SpellName(spell) or L["Recipe %d"]:format(spell)) .. (count and count > 1 and (" x" .. count) or "")
  -- Auctionator's shopping list (API v1), when it is there
  local api = type(Auctionator) == "table" and type(Auctionator.API) == "table" and Auctionator.API.v1
  if api and type(api.CreateShoppingList) == "function" then
    local terms = {}
    for _, m in ipairs(miss) do
      local name = ns.ItemName(m[1])
      if name then terms[#terms + 1] = name end
    end
    if #terms == #miss and pcall(api.CreateShoppingList, "Guildon", "Guildon: " .. title, terms) then
      ns.Print(L["Auctionator shopping list made: %s."]:format("Guildon: " .. title))
      return "auctionator"
    end
  end
  local lines, total = {}, 0
  for _, m in ipairs(miss) do
    local p = ns.Price and ns.Price(m[1])
    if p then total = total + p * m[2] end
    lines[#lines + 1] = ("%d x %s%s"):format(m[2], ns.ItemName(m[1]) or L["Item %d"]:format(m[1]),
      p and ("  (" .. ns.ShortMoney(p * m[2]) .. ")") or "")
  end
  ns.ShowCopyBox(L["Shopping list: %s"]:format(title), total > 0 and L["About %s at the auction house."]:format(ns.ShortMoney(total)) or "",
    table.concat(lines, "\n"))
  return "text"
end

---------------------------------------------------------------------------
-- 9 Guild emblem (Forever's C_GuildInfo.GetGuildTabardInfo; Era has no call for it)
---------------------------------------------------------------------------
-- Daniel's guild Libra Vivendi has its own emblem in the addon (art/guildon, tools/make_guildon_pins.py)
ns.OWN_EMBLEMS = { ["libra vivendi"] = "Interface\\AddOns\\Guildon\\Media\\Emblem" }

-- the addon's own emblem for the guild you are in
function ns.OwnEmblemFile()
  local g = ns.GuildInfo()
  return type(g) == "string" and ns.OWN_EMBLEMS[g:lower()] or nil
end

-- what the game says about the guild's tabard (Forever and, per the wiki, Era 1.14+ too): emblem file, emblem colour, background colour;
-- nil without a guild, without the call or for a guild that never designed one (file 0)
-- (Daniel 26.10.: "tabard call: yes, in a guild: no") without a guild there is nothing to look at: the example guild (/gn demo) gets
-- a stand-in crest, a white star (tools/make_example_crest.py) in gold on dark blue
ns.EXAMPLE_CREST = { file = "Interface\\AddOns\\Guildon\\Media\\ExampleCrest", r = 1, g = 0.82, b = 0.25, br = 0.10, bg = 0.17, bb = 0.40 }

function ns.GameEmblem()
  if ns.demo and not ns.InGuild() then
    local e = ns.EXAMPLE_CREST
    return e.file, e.r, e.g, e.b, e.br, e.bg, e.bb
  end
  if not (C_GuildInfo and C_GuildInfo.GetGuildTabardInfo) or not ns.InGuild() then return nil end
  local t = ns.Call(C_GuildInfo.GetGuildTabardInfo, "player")
  if type(t) ~= "table" then return nil end
  local id = ns.Num(t.emblemFileID)
  if not id or id <= 0 then return nil end
  local c = t.emblemColor
  local r, g, b = 1, 1, 1
  if type(c) == "table" then
    if c.GetRGB then local ok, a1, a2, a3 = pcall(c.GetRGB, c) if ok then r, g, b = a1, a2, a3 end
    elseif c.r then r, g, b = c.r, c.g, c.b end
  end
  local bg = t.backgroundColor
  local br, bgc, bb
  if type(bg) == "table" then
    if bg.GetRGB then local ok, a1, a2, a3 = pcall(bg.GetRGB, bg) if ok then br, bgc, bb = a1, a2, a3 end
    elseif bg.r then br, bgc, bb = bg.r, bg.g, bg.b end
  end
  return id, r, g, b, br, bgc, bb
end

function ns.GuildEmblem()
  local own = ns.OwnEmblemFile()
  if own then return own, 1, 1, 1 end
  return ns.GameEmblem()
end

---------------------------------------------------------------------------
-- 11 Item tooltips: who in the guild crafts the item, who could learn a recipe item, who wants it
-- (TooltipDataProcessor, no hooks; where the client lacks it there are no lines)
---------------------------------------------------------------------------
local byResult, byRecipeItem

local function Lookups()
  if byResult then return end
  byResult, byRecipeItem = {}, {}
  for id, r in pairs(ns.RECIPES) do
    if r[5] and r[5] > 0 then byResult[r[5]] = byResult[r[5]] or {} table.insert(byResult[r[5]], id) end
    if r[4] and r[4] > 0 then byRecipeItem[r[4]] = id end
  end
end

local function Names(list, max)
  local out = {}
  for i = 1, math.min(#list, max) do
    local o = type(list[i]) == "table" and list[i].owner or list[i]
    out[#out + 1] = (ns.IsOnline(o) and "|cff4fd16a" or "|cff9ea3ad") .. ns.ShortName(o) .. "|r"
  end
  local s = table.concat(out, ", ")
  if #list > max then s = s .. " " .. L["and %d more"]:format(#list - max) end
  return s
end

-- lines for an item: { text, ... }
function ns.ItemTooltipLines(item)
  if ns.db.tooltips == false or not item then return {} end
  Lookups()
  local lines = {}
  local crafters, seen = {}, {}
  for _, spell in ipairs(byResult[item] or {}) do
    for _, o in ipairs(ns.CraftersOf(spell)) do if not seen[o] then seen[o] = true crafters[#crafters + 1] = o end end
  end
  if #crafters > 0 then lines[#lines + 1] = L["Crafted in the guild by %s"]:format(Names(crafters, 4)) end
  local spell = byRecipeItem[item]
  if spell then
    local known = ns.CraftIndex().crafters[spell] or {}
    if #known > 0 then lines[#lines + 1] = L["Known by %s"]:format(Names(known, 4)) end
    local could = {}
    for _, c in ipairs(ns.CouldLearn(spell)) do if c.ok then could[#could + 1] = c end end
    if #could > 0 then lines[#lines + 1] = L["Could learn it: %s"]:format(Names(could, 4)) end
    local want = ns.WantedBy(spell)
    if #want > 0 then lines[#lines + 1] = L["Wanted by %s"]:format(Names(want, 4)) end
  end
  return lines
end

-- (30.10.2026, Daniel: "die Meldung kommt nur, wenn es droppt", "zusätzlich zum Tooltip") a recipe someone in the guild
-- wants drops for you: a chat line names who wants it (a click on the name whispers), and the guild hears "R:<item>",
-- so the ones who want it read who found it. Only your own loot (the game's "You receive loot" lines), not quest
-- rewards, purchases or crafting.
function ns.RecipeSpellForItem(item)
  Lookups()
  return item and byRecipeItem[item] or nil
end
local function PlayerLink(full)
  return "|Hplayer:" .. full .. "|h[" .. ns.ShortName(full) .. "]|h"
end
local lootPatterns
local function LootPatterns()
  if lootPatterns then return lootPatterns end
  local list = {}
  for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF" }) do -- the longer one first ("...x3.")
    local f = rawget(_G, g)
    if type(f) == "string" then
      local p = "^" .. f:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d", "%%d+") .. "$"
      list[#list + 1] = p
    end
  end
  if #list > 0 then lootPatterns = list end -- kept once the game's texts are there
  return list
end
-- the item of an own loot line, or nil
function ns.OwnLootItem(text)
  if type(text) ~= "string" then return nil end
  for _, p in ipairs(LootPatterns()) do
    local link = text:match(p)
    if link then return tonumber(link:match("|Hitem:(%d+)")) end
  end
  return nil
end
function ns.OnRecipeDrop(item)
  local spell = ns.RecipeSpellForItem(item)
  if not spell then return false end
  local me, others = ns.MyName(), {}
  for _, o in ipairs(ns.WantedBy(spell)) do if o ~= me then others[#others + 1] = PlayerLink(o) end end
  if #others == 0 then return false end
  ns.Print(L["%s is wanted by %s."]:format(ns.ItemName(item) or ("#" .. item), table.concat(others, ", ")))
  ns.Send("R:" .. ns.B36(item), "GUILD")
  return true
end
ns.On("CHAT_MSG_LOOT", function(_, text)
  local item = ns.OwnLootItem(text)
  if item then ns.OnRecipeDrop(item) end
end)
-- a member found a recipe: those who want it read it
ns.MSG = ns.MSG or {}
ns.MSG.R = function(sender, rest, chat)
  if chat ~= "GUILD" then return end
  local item = rest and rest:match("^(%w+)$") and ns.UnB36(rest)
  local spell = item and ns.RecipeSpellForItem(item)
  if not (spell and ns.IsWanted(spell)) then return end
  ns.Print(L["%s found %s, the recipe you want."]:format(PlayerLink(sender), ns.ItemName(item) or ("#" .. item)))
end

local function OnTooltip(tooltip, data)
  if not tooltip or not tooltip.AddLine or type(data) ~= "table" then return end
  local id = ns.Num(data.id)
  if not id then return end
  local lines = ns.ItemTooltipLines(id)
  if #lines == 0 then return end
  tooltip:AddLine(Style.Wordmark("Guil", "don"))
  for _, l in ipairs(lines) do tooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
end

ns.OnInit(function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    ns.Call(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, ns.Guard("tooltip", OnTooltip))
  end
end)

---------------------------------------------------------------------------
-- 11 Questdon's arrow to a member
---------------------------------------------------------------------------
function ns.ArrowTo(name)
  local api = QuestdonAPI
  local p = ns.Positions and ns.Positions()[name]
  if type(api) ~= "table" or type(api.SetArrowTarget) ~= "function" or not p then return false end
  return pcall(api.SetArrowTarget, { mapID = p.map, x = p.x, y = p.y, label = ns.ShortName(name) })
end

ns.On("PLAYER_LOGIN", function() ns.After(15, function() DB() if next(ns.db.wants) then ShareWants() end end) end)
