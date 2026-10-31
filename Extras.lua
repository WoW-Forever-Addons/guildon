local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Extras (GUILDON_PLAN.md "Durchgang 5"). (31.10.2026, C3) Cooldowns, recipes wanted, shopping list, thanks, wish notes and
-- the item tooltips went to Guildon Crafts with the professions. Left here:
--  7 alts: own characters of one account linked ("alts"), whispers go to the one who is online
--  8 member tooltip: last seen, alts; Guildon Crafts adds the professions through GuildonAPI.AddMemberLines
--  9 guild emblem next to the window title (Forever: C_GuildInfo.GetGuildTabardInfo)
-- 11 the arrow to a member on the map (DonMap, Questdon with an older DonMap)
-- whisper and invite a member (were in Professions.lua)
---------------------------------------------------------------------------

-- own characters: class, level, faction (only the character itself can read them; were kept by Export.lua for the export)
local function NoteMe()
  local me = ns.MyName()
  if not me then return end
  ns.db.chars = type(ns.db.chars) == "table" and ns.db.chars or {}
  local _, cls = ns.Call(UnitClass, "player")
  local fac = ns.Str(ns.Call(UnitFactionGroup, "player"))
  ns.db.chars[me] = {
    class = ns.Str(cls) and cls:match("^%u+$") or "",
    level = ns.Num(ns.Call(UnitLevel, "player")) or 0,
    faction = fac == "Alliance" and "A" or (fac == "Horde" and "H" or "N"),
  }
end
ns.On("PLAYER_LOGIN", function() ns.After(2, NoteMe) end)
ns.On("PLAYER_LEVEL_UP", function() ns.After(2, NoteMe) end)

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
-- 8 Member tooltip lines; other addons add theirs (Guildon Crafts: professions, orders crafted)
---------------------------------------------------------------------------
local lineSources = {}
GuildonAPI = GuildonAPI or {}
GuildonAPI.version = 1
-- fn(member) returns a list of text lines for the member's tooltip; member = { name, short, online, level, class, classFile, zone, rank }
function GuildonAPI.AddMemberLines(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(lineSources) do if f == fn then return true end end
  lineSources[#lineSources + 1] = fn
  return true
end

function ns.MemberLines(m)
  local lines = {}
  for _, fn in ipairs(lineSources) do
    local ok, extra = pcall(fn, { name = m.name, short = m.short, online = m.online, level = m.level, class = m.class,
      classFile = m.classFile, zone = m.zone, rank = m.rank })
    if ok and type(extra) == "table" then
      for i = 1, math.min(#extra, 6) do if type(extra[i]) == "string" then lines[#lines + 1] = extra[i] end end
    end
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
  return lines
end

---------------------------------------------------------------------------
-- Whisper and invite a member (map, member list)
---------------------------------------------------------------------------
function ns.InviteMember(owner)
  if not owner or owner == ns.MyName() then return false end
  if ns.IsDemo(owner) then ns.Print(L["%s is an example member and cannot be invited."]:format(ns.ShortName(owner))) return false end
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  if not fn then return false end
  return (pcall(fn, ns.ShortName(owner)))
end

function ns.WhisperMember(owner)
  if not owner then return end
  if ns.IsDemo(owner) then ns.Print(L["%s is an example member and cannot be whispered."]:format(ns.ShortName(owner))) return end
  local reach, alt = ns.ReachableName(owner)
  if alt then ns.Print(L["%s is offline; whispering the alt %s."]:format(ns.ShortName(owner), ns.ShortName(reach))) end
  local target = ns.ShortName(reach)
  local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
  if open then ns.Call(open, ("/w %s "):format(target)) return true end
  local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
  if tell then ns.Call(tell, target) return true end
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
-- 11 The arrow to a member: DonMap's (M2, a click wins over a guide's step), Questdon's with an older DonMap
---------------------------------------------------------------------------
local function DonMapArrow()
  local api = DonMapAPI
  return type(api) == "table" and (tonumber(api.version) or 0) >= 2 and type(api.SetArrowTarget) == "function" and api or nil
end
function ns.CanArrow()
  return DonMapArrow() ~= nil or (type(QuestdonAPI) == "table" and type(QuestdonAPI.SetArrowTarget) == "function")
end
function ns.ArrowTo(name)
  local p = ns.Positions and ns.Positions()[name]
  if not p then return false end
  local target = { mapID = p.map, x = p.x, y = p.y, label = ns.ShortName(name) }
  local dm = DonMapArrow()
  if dm then return (pcall(dm.SetArrowTarget, "guildon", target, dm.PRIO and dm.PRIO.click or 3)) end
  local api = QuestdonAPI
  if type(api) ~= "table" or type(api.SetArrowTarget) ~= "function" then return false end
  return pcall(api.SetArrowTarget, target)
end
