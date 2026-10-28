-- Guildon on WoW Classic Era (1.15.x), loaded only by Guildon_Vanilla.toc, before Core.lua.
-- Guild roster, addon messages and the guild calls exist on Era under the same names (Guild.lua tries
-- C_GuildInfo.GuildRoster first, then the old GuildRoster). Professions use the old calls (GUILDON_PLAN.md
-- "Entscheidungen" 5): skill lines from GetSkillLineInfo, recipes from the trade skill window (GetTradeSkillInfo)
-- and, for enchanting, the craft window (GetCraftInfo). Called by Professions.lua through ns.ReadSkillsEra and
-- ns.ReadWindowEra; data come from DataEra/Recipes.lua (CMaNGOS).
local _, ns = ...

ns.ERA = true

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g end
end

-- skill lines: name, isHeader, isExpanded, rank, temp points, modifier, max
function ns.ReadSkillsEra()
  local n = tonumber(Call(GetNumSkillLines)) or 0
  if n == 0 then return nil end
  local list = {}
  for i = 1, math.min(n, 100) do
    local name, header, _, rank, _, _, max = Call(GetSkillLineInfo, i)
    if name and not header then
      local id = ns.ProfOfName(name)
      if id then list[#list + 1] = { id = id, rank = tonumber(rank) or 0, max = tonumber(max) or 0 } end
    end
  end
  return list
end

-- spell ID of a recipe link ("|Henchant:2330|h"; Era names trade skill recipes this way)
local function SpellOfLink(link)
  return type(link) == "string" and tonumber(link:match("enchant:(%d+)")) or nil
end

-- created item -> spell (for lines without a recipe link); only items one recipe makes
local byItem
local function SpellOfItem(link)
  local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
  if not item then return nil end
  if not byItem then
    byItem = {}
    for id, r in pairs(ns.RECIPES) do
      local it = r[5]
      if it and it > 0 then byItem[it] = byItem[it] == nil and id or false end
    end
  end
  return byItem[item] or nil
end

local function ReadTradeSkill()
  local name, rank, max = Call(GetTradeSkillLine)
  local n = tonumber(Call(GetNumTradeSkills)) or 0
  local spells = {}
  for i = 1, math.min(n, 1000) do
    local _, kind = Call(GetTradeSkillInfo, i)
    if kind and kind ~= "header" and kind ~= "subheader" then
      local id = SpellOfLink(Call(GetTradeSkillRecipeLink, i)) or SpellOfItem(Call(GetTradeSkillItemLink, i))
      if id then spells[#spells + 1] = id end
    end
  end
  return name, rank, max, spells
end

local function ReadCraft()
  local name, rank, max = Call(GetCraftDisplaySkillLine)
  local n = tonumber(Call(GetNumCrafts)) or 0
  local spells = {}
  for i = 1, math.min(n, 1000) do
    local _, _, kind = Call(GetCraftInfo, i)
    if kind and kind ~= "header" then
      local id = SpellOfLink(Call(GetCraftRecipeLink, i)) or SpellOfLink(Call(GetCraftItemLink, i))
      if id then spells[#spells + 1] = id end
    end
  end
  return name, rank, max, spells
end

-- (Daniel 26.10.: "kann man die Rezepte nicht einlesen lassen, wenn man Guildon öffnet?") the recipes of the own professions without the
-- profession window: a learned recipe is a spell of the character, so the game's spell check says whether it is known. Only the
-- recipes of the data file are looked at (for every profession the character has). Unverified in the game: /gn prices shows what it finds.
local function KnownSpell(id)
  return (Call(IsPlayerSpell, id) or Call(IsSpellKnown, id)) and true or false
end

function ns.ReadKnownEra()
  local out = {}
  for _, s in ipairs(ns.ReadSkillsEra() or {}) do
    local spells = {}
    for id, r in pairs(ns.RECIPES) do
      if r[1] == s.id and KnownSpell(id) then spells[#spells + 1] = id end
    end
    if #spells > 0 then
      table.sort(spells)
      out[#out + 1] = { skill = s.id, rank = s.rank, max = s.max, spells = spells }
    end
  end
  return out
end

-- kind "tradeskill" or "craft". The hunter's Beast Training also uses the craft window: its spells are no
-- recipes, so no profession is found and nothing is stored.
function ns.ReadWindowEra(kind)
  local name, rank, max, spells
  if kind == "craft" then name, rank, max, spells = ReadCraft() else name, rank, max, spells = ReadTradeSkill() end
  if not spells or #spells == 0 then return nil end
  local skill = ns.ProfOfSpells(spells) or ns.ProfOfName(name)
  if not skill then return nil end
  -- Era hides lines under folded headers and by filters: merge into what is known
  return { skill = skill, rank = tonumber(rank), max = tonumber(max), spells = spells, full = false }
end
