local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- /gn demo (Daniel 25.10.2026: "testen, ohne in einer Gilde zu sein"): an example guild of made-up members with
-- professions and real recipes from the data, to try the windows alone. Only on this screen and only for this
-- session: nothing is saved, sent or served, names end in "-Demo" (no real realm), whispers to them are refused
-- (Professions.lua) and the exchange ignores these names (Comm.lua).
---------------------------------------------------------------------------
local REALM = "Demo"
-- name, class, level, online, zone, { { skill, rank, max }, ... }
local PEOPLE = {
  { "Thorwin", "WARRIOR", 60, true, "Ironforge", { { 164, 300, 300 }, { 186, 300, 300 }, { 185, 150, 225 } } },
  { "Elowen", "PRIEST", 55, true, "Stormwind", { { 171, 275, 300 }, { 182, 290, 300 }, { 129, 225, 225 } } },
  { "Mirela", "MAGE", 42, true, "Stranglethorn", { { 197, 225, 225 }, { 333, 200, 225 } } },
  { "Krag", "HUNTER", 35, false, "", { { 165, 175, 225 }, { 393, 180, 225 } } },
  { "Fizzle", "ROGUE", 28, false, "", { { 202, 140, 150 }, { 186, 130, 150 } } },
}

local members, sets, wishStamp

function ns.IsDemo(name) return type(name) == "string" and name:sub(-#REALM - 1) == "-" .. REALM end

-- recipes a member of this skill would know: everything up to the skill, a few left out so that the book shows
-- "only one can" and "nobody can" too
local function Recipes(skill, rank)
  local out = {}
  for id, r in pairs(ns.RECIPES) do
    if r[1] == skill then
      local need = r[2] or 0
      if (need > 0 and need <= rank and id % 3 ~= 0) or (need == 0 and rank >= 150 and id % 4 == 0) then out[id] = true end
    end
  end
  return out
end

local function Build()
  members, sets = {}, {}
  local stamp = time() - 3600
  for i, p in ipairs(PEOPLE) do
    local name = p[1] .. "-" .. REALM
    local classes = LOCALIZED_CLASS_NAMES_MALE or {}
    members[#members + 1] = { name = name, short = name, rank = L["Example member"], rankIndex = 3, level = p[3],
      class = classes[p[2]] or p[2], classFile = p[2], zone = p[5], online = p[4], demo = true }
    local entry = {}
    for _, s in ipairs(p[6]) do
      entry[s[1]] = { rank = s[2], max = s[3], recipes = ns.PROF_BY_ID[s[1]].craft and Recipes(s[1], s[2]) or {} }
    end
    local d = ns.EncodeProf(entry)
    sets[#sets + 1] = { k = "prof", o = name, t = stamp - i * 600, s = ns.Checksum(d), d = d }
  end
end

-- map only travellers (Daniel 26.10.: "kannst du in der demo überall welche verteilen?"): not in the member list, they only
-- stand on the map, in many zones, two of them close together in Elwynn and in Stormwind (a group pin), so that every zone
-- map and both continent maps show dots. { name, class, level, map, x, y }; the map numbers are the Classic zone maps
-- (a number the game does not know is skipped)
local TRAVELLERS = {
  { "Aldric", "PALADIN", 58, 1453, 0.55, 0.62 }, { "Brenna", "DRUID", 47, 1453, 0.56, 0.61 },       -- Stormwind
  { "Corwin", "WARRIOR", 33, 1429, 0.43, 0.65 }, { "Dessa", "MAGE", 29, 1429, 0.44, 0.66 },         -- Elwynn Forest
  { "Evander", "ROGUE", 22, 1436, 0.55, 0.50 },                                                     -- Westfall
  { "Fenwick", "HUNTER", 41, 1431, 0.45, 0.45 },                                                    -- Duskwood
  { "Gwyn", "PRIEST", 38, 1434, 0.40, 0.50 },                                                       -- Stranglethorn
  { "Hale", "WARLOCK", 52, 1455, 0.50, 0.48 },                                                      -- Ironforge
  { "Isolde", "SHAMAN", 44, 1426, 0.45, 0.55 },                                                     -- Dun Morogh
  { "Joren", "WARRIOR", 60, 1454, 0.50, 0.50 },                                                     -- Orgrimmar
  { "Kestra", "ROGUE", 31, 1411, 0.50, 0.55 },                                                      -- Durotar
  { "Lorcan", "SHAMAN", 36, 1413, 0.50, 0.45 },                                                     -- The Barrens
  { "Maren", "DRUID", 27, 1412, 0.45, 0.55 },                                                       -- Mulgore
  { "Nolan", "HUNTER", 19, 1438, 0.55, 0.60 },                                                      -- Teldrassil
  { "Orla", "PRIEST", 49, 1440, 0.50, 0.50 },                                                       -- Ashenvale
  { "Perrin", "MAGE", 55, 1446, 0.50, 0.50 },                                                       -- Tanaris
  { "Quill", "WARLOCK", 24, 1420, 0.50, 0.50 },                                                     -- Tirisfal Glades
  { "Rowan", "PALADIN", 57, 1423, 0.50, 0.50 },                                                     -- Eastern Plaguelands
  { "Sable", "MAGE", 46, 1452, 0.50, 0.50 },                                                        -- Winterspring
}
local knownMap = {}
local function MapKnown(id)
  if knownMap[id] == nil then
    local ok, info = true, true
    if C_Map and C_Map.GetMapInfo then ok, info = pcall(C_Map.GetMapInfo, id) end
    knownMap[id] = ok and type(info) == "table" and true or false
  end
  return knownMap[id]
end

-- only the travellers stand on the map, in many zones; the members of the list no longer walk along with the player
-- (Daniel 28.10.: "die 3 demo pins spieler, die mit mir mitlaufen wegnehmen")
function ns.DemoPositions()
  if not ns.demo or not members then return {} end
  local out = {}
  local now = GetTime()
  for k, t in ipairs(TRAVELLERS) do
    if MapKnown(t[4]) then
      out[t[1] .. "-" .. REALM] = { map = t[4], x = t[5], y = t[6], level = t[3], class = t[2], t = now }
    end
  end
  return out
end

function ns.DemoMembers() return ns.demo and members or {} end

-- wishes of the example members: two for recipes the player can craft (so "For me to craft" shows something),
-- one for a recipe of an example member
function ns.DemoWishes()
  if not ns.demo or not members then return {} end
  local out, mine = {}, {}
  for id in pairs(ns.MyCrafts and ns.MyCrafts() or {}) do if ns.RECIPES[id] then mine[#mine + 1] = id end end
  table.sort(mine)
  local stamp = (wishStamp or time()) - 7200
  local function Add(owner, spell, count, pay, tip, note)
    out[#out + 1] = { owner = owner, id = stamp - #out * 900, spell = spell, count = count, pay = pay, tip = tip, note = note,
      state = "o", demo = true }
  end
  if mine[1] then Add("Krag-Demo", mine[1], 2, "m", 0, L["for my alt, thanks!"]) end
  if mine[2] then Add("Fizzle-Demo", mine[#mine], 1, "b", 0, "") end
  local other
  for id in pairs(ns.CraftIndex().crafters) do if ns.RECIPES[id] and (not other or id < other) then other = id end end
  if other then Add("Mirela-Demo", other, 5, "p", 50000, "") end
  return out
end

-- example crafters take the player's wishes: accepted after 5 s, crafted after 30 s, sent after 60 s
local function DemoJobs()
  local me = ns.MyName()
  local byCrafter = {}
  for _, w in ipairs(ns.db.wishes or {}) do
    if w.state == "o" then
      for _, o in ipairs(w.spell and ns.CraftIndex().crafters[w.spell] or {}) do
        if ns.IsDemo(o) and (not w.target or w.target == o) then
          local age = time() - w.id
          local state = age >= 60 and "s" or (age >= 30 and "m" or (age >= 5 and "a" or nil))
          if state then
            byCrafter[o] = byCrafter[o] or {}
            table.insert(byCrafter[o], { owner = me, id = w.id, state = state, t = w.id + 5 })
          end
          break
        end
      end
    end
  end
  local out = {}
  for o, list in pairs(byCrafter) do
    local d = ns.EncodeJobs(list)
    out[#out + 1] = { k = "job", o = o, t = time(), s = ns.Checksum(d), d = d }
  end
  return out
end

function ns.DemoSets(kind)
  if not ns.demo or not sets then return {} end
  if kind == "job" then return DemoJobs() end
  local out = {}
  for _, s in ipairs(sets) do if s.k == kind then out[#out + 1] = s end end
  return out
end

function ns.SetDemo(on)
  ns.demo = on and true or nil
  if ns.demo then Build() wishStamp = time() else members, sets = nil, nil end
  if ns.InvalidateWishes then ns.InvalidateWishes() end
  ns.RebuildRoster()
  ns.InvalidateCrafters()
  if ns.demo then
    ns.Print(L["Example guild on: %d made-up members ending in -Demo, only on your screen. /gn demo off removes them."]:format(#PEOPLE))
    if ns.ToggleWindow and ns.OpenTab then ns.OpenTab("professions") end
  else
    ns.Print(L["Example guild off."])
  end
  if ns.Refresh then ns.Refresh() end
end
