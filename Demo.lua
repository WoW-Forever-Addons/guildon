local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- /gn demo (Daniel 25.10.2026: "testen, ohne in einer Gilde zu sein"): an example guild of made-up members, to try the
-- windows alone. (31.10.2026, C3) their professions, recipes and wishes are Guildon Crafts's example guild now (/gnc demo). Only on this screen and only for this
-- session: nothing is saved, sent or served, names end in "-Demo" (no real realm), whispers to them are refused
-- (Extras.lua) and the exchange ignores these names (Comm.lua).
---------------------------------------------------------------------------
local REALM = "Demo"
-- name, class, level, online, zone (the same five as in Guildon Crafts's example guild)
local PEOPLE = {
  { "Thorwin", "WARRIOR", 60, true, "Ironforge" },
  { "Elowen", "PRIEST", 55, true, "Stormwind" },
  { "Mirela", "MAGE", 42, true, "Stranglethorn" },
  { "Krag", "HUNTER", 35, false, "" },
  { "Fizzle", "ROGUE", 28, false, "" },
}

local members

function ns.IsDemo(name) return type(name) == "string" and name:sub(-#REALM - 1) == "-" .. REALM end

local function Build()
  members = {}
  for _, p in ipairs(PEOPLE) do
    local name = p[1] .. "-" .. REALM
    local classes = LOCALIZED_CLASS_NAMES_MALE or {}
    members[#members + 1] = { name = name, short = name, rank = L["Example member"], rankIndex = 3, level = p[3],
      class = classes[p[2]] or p[2], classFile = p[2], zone = p[5], online = p[4], demo = true }
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

function ns.SetDemo(on)
  ns.demo = on and true or nil
  if ns.demo then Build() else members = nil end
  ns.RebuildRoster()
  if ns.demo then
    ns.Print(L["Example guild on: %d made-up members ending in -Demo, only on your screen. /gn demo off removes them."]:format(#PEOPLE))
    if ns.ToggleWindow and ns.OpenTab then ns.OpenTab("members") end
  else
    ns.Print(L["Example guild off."])
  end
  if ns.Refresh then ns.Refresh() end
end
