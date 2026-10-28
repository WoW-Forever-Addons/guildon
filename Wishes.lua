local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Wish list (GUILDON_PLAN.md step 3): a member wishes a recipe instead of whispering around; crafters see the
-- wishes they can craft, accept one, craft it and send it; the wisher marks it received.
-- Every set has one owner who alone writes it (Comm.lua), so a wish lives in two kinds of sets:
--   "wish" (the wisher):  2;<id>,<r|i>,<spell or item>,<count>,<pay>,<tip>,<target>,<state>,<note>;...
--       id = creation time (base 36, unique per wisher), r = a recipe (spell base 36), i = an item from gatherers
--       ("Mats besorgen", Durchgang 5 Nr. 2; item base 36), pay m (mats there) / p (I pay the mats) /
--       b (short of money), tip in copper, target "" = everyone who can craft it, else the crafter's full name,
--       state o (open) / d (received) / c (cancelled), note up to 60 characters without separators.
--   "job" (the crafter):  1;<wisher>,<id>,<state>,<stamp>;...   state a (accepted) / m (crafted) / s (sent), stamp base 36
-- Two crafters accept at once: the earlier stamp wins, the later one sees "already accepted by X" and drops his job.
-- Officers may delete other members' wishes ("mod", only from its owner in person, GUILDON_PLAN.md decision 3);
-- which ranks count as officers the guild master sets ("cfg", also only in person; without it ranks 0 and 1).
-- Open wishes run out after ns.db.wishDays (14), wishes in progress after twice that, finished ones after 3 days.
---------------------------------------------------------------------------
local MAX_WISHES, MAX_NOTE, MAX_COUNT, MAX_TIP = 30, 60, 200, 99990000
ns.PAY = { "m", "p", "b" }
ns.PAY_TEXT = { m = "I bring the reagents", p = "I pay for the reagents", b = "Short of money" }
ns.STATE_TEXT = { o = "open", a = "accepted", m = "crafted", s = "sent", d = "received", c = "cancelled", x = "deleted", e = "expired" }

local function DB()
  local db = ns.db
  db.wishes = type(db.wishes) == "table" and db.wishes or {}  -- own wishes of this character, list
  db.jobs = type(db.jobs) == "table" and db.jobs or {}        -- own jobs: list of { owner, id, state, t }
  db.mods = type(db.mods) == "table" and db.mods or {}        -- own deletions as officer: list of { owner, id, t }
  db.wishDays = tonumber(db.wishDays) or 14
  return db
end

function ns.CleanNote(s)
  s = tostring(s or ""):gsub("|", ""):gsub("[%c;,:#~]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if #s > MAX_NOTE then
    s = s:sub(1, MAX_NOTE)
    -- never cut a UTF-8 character in half
    while #s > 0 and s:byte(#s) >= 128 and s:byte(#s) < 192 do s = s:sub(1, -2) end
    if #s > 0 and s:byte(#s) >= 192 then s = s:sub(1, -2) end
  end
  return s
end

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------
local B36, UnB36 = ns.B36, ns.UnB36

function ns.EncodeWishes(list)
  local parts = { "2" }
  for _, w in ipairs(list) do
    parts[#parts + 1] = table.concat({ B36(w.id), w.item and "i" or "r", B36(w.item or w.spell), w.count, w.pay, w.tip or 0,
      w.target or "", w.state or "o", ns.CleanNote(w.note) }, ",")
  end
  return table.concat(parts, ";")
end

function ns.DecodeWishes(d)
  if type(d) ~= "string" or #d > 16000 or d:sub(1, 1) ~= "2" then return nil end
  local out, first = {}, true
  for piece in (d .. ";"):gmatch("([^;]*);") do
    if first then
      if piece ~= "2" then return nil end
      first = false
    else
      local id, kind, what, count, pay, tip, target, state, note =
        piece:match("^(%w+),([ri]),(%w+),(%d+),([mpb]),(%d+),([^,]*),([odc]),(.*)$")
      if not id or #note > MAX_NOTE or note:find("[,;|]") or #target > 64 then return nil end
      count, tip = tonumber(count), tonumber(tip)
      if count < 1 or count > (kind == "i" and 1000 or MAX_COUNT) or tip > MAX_TIP then return nil end
      out[#out + 1] = { id = UnB36(id), spell = kind == "r" and UnB36(what) or nil, item = kind == "i" and UnB36(what) or nil,
        count = count, pay = pay, tip = tip, target = target ~= "" and target or nil, state = state, note = note }
      if #out > MAX_WISHES * 2 then return nil end
    end
  end
  return out
end

function ns.EncodeJobs(list)
  local parts = { "1" }
  for _, j in ipairs(list) do parts[#parts + 1] = table.concat({ j.owner, B36(j.id), j.state, B36(j.t) }, ",") end
  return table.concat(parts, ";")
end

function ns.DecodeJobs(d)
  if type(d) ~= "string" or #d > 16000 or d:sub(1, 1) ~= "1" then return nil end
  local out, first = {}, true
  for piece in (d .. ";"):gmatch("([^;]*);") do
    if first then
      if piece ~= "1" then return nil end
      first = false
    else
      local owner, id, state, t = piece:match("^([^,]+),(%w+),([ams]),(%w+)$")
      if not owner or #owner > 64 then return nil end
      out[#out + 1] = { owner = owner, id = UnB36(id), state = state, t = UnB36(t) }
    end
  end
  return out
end

function ns.EncodeMods(list)
  local parts = { "1" }
  for _, m in ipairs(list) do parts[#parts + 1] = table.concat({ m.owner, B36(m.id), B36(m.t) }, ",") end
  return table.concat(parts, ";")
end

function ns.DecodeMods(d)
  if type(d) ~= "string" or #d > 16000 or d:sub(1, 1) ~= "1" then return nil end
  local out, first = {}, true
  for piece in (d .. ";"):gmatch("([^;]*);") do
    if first then
      if piece ~= "1" then return nil end
      first = false
    else
      local owner, id, t = piece:match("^([^,]+),(%w+),(%w+)$")
      if not owner or #owner > 64 then return nil end
      out[#out + 1] = { owner = owner, id = UnB36(id), t = UnB36(t) }
    end
  end
  return out
end

-- guild master's settings: 1;<officer ranks 0-based, joined by ".">
function ns.DecodeCfg(d)
  if type(d) ~= "string" then return nil end
  local ranks = d:match("^1;([%d%.]*)$")
  if not ranks then return nil end
  local out = { ranks = {} }
  for r in ranks:gmatch("%d+") do out.ranks[tonumber(r)] = true end
  return out
end

---------------------------------------------------------------------------
-- Rights: officers and the guild master
---------------------------------------------------------------------------
local function GuildMaster()
  for _, m in ipairs(ns.Members()) do if m.rankIndex == 0 and not m.demo then return m.name end end
end

-- officer ranks: from the guild master's "cfg" set; fallback ranks 0 and 1
function ns.OfficerRanks()
  local gm = GuildMaster()
  local set
  if gm == ns.MyName() then set = ns.GetSet("cfg", gm) elseif gm then set = ns.GetSet("cfg", gm) end
  local cfg = set and ns.DecodeCfg(set.d)
  if cfg and next(cfg.ranks) then return cfg.ranks, true end
  return { [0] = true, [1] = true }, false
end

local function RankOf(full)
  local m = ns.Member(full)
  if m then return m.rankIndex end
  if full == ns.MyName() then
    local _, _, idx = ns.GuildInfo()
    return idx
  end
end

function ns.IsOfficer(full)
  local r = RankOf(full)
  return r ~= nil and ns.OfficerRanks()[r] == true
end

function ns.IsGuildMaster(full) return RankOf(full) == 0 end

function ns.SetOfficerRanks(ranks)
  if not ns.IsGuildMaster(ns.MyName()) then return false end
  local list = {}
  for r in pairs(ranks) do if type(r) == "number" and r >= 0 and r < 10 then list[#list + 1] = r end end
  table.sort(list)
  return ns.SetOwn("cfg", "1;" .. table.concat(list, "."))
end

-- the guild's rank names (index 0 = guild master)
function ns.RankNames()
  local out = {}
  local n = ns.Num(ns.Call(GuildControlGetNumRanks)) or 0
  for i = 1, math.min(n, 10) do out[i - 1] = ns.Str(ns.Call(GuildControlGetRankName, i)) or ("#" .. (i - 1)) end
  return out, n
end

---------------------------------------------------------------------------
-- Own sets
---------------------------------------------------------------------------
local function ShareWishes() ns.SetOwn("wish", ns.EncodeWishes(DB().wishes)) end
local function ShareJobs() ns.SetOwn("job", ns.EncodeJobs(DB().jobs)) end
local function ShareMods() ns.SetOwn("mod", ns.EncodeMods(DB().mods)) end

local function Changed()
  ns.InvalidateWishes()
  if ns.OnDataChanged then ns.OnDataChanged("wish", ns.MyName()) end
end

-- new wish; returns the wish or nil, reason. item: a wish for an item from gatherers instead of a recipe (spell nil)
function ns.AddWish(spell, count, pay, tip, note, target, item)
  local db = DB()
  spell, item, count, tip = tonumber(spell), tonumber(item), math.floor(tonumber(count) or 1), math.floor(tonumber(tip) or 0)
  if item then spell = nil if item <= 0 then return nil, "spell" end
  elseif not spell or spell <= 0 then return nil, "spell" end
  if count < 1 or count > (item and 1000 or MAX_COUNT) then return nil, "count" end
  if tip < 0 or tip > MAX_TIP then return nil, "tip" end
  if not ns.PAY_TEXT[pay] then pay = "m" end
  local open = 0
  for _, w in ipairs(db.wishes) do if w.state == "o" then open = open + 1 end end
  if open >= MAX_WISHES then return nil, "full" end
  if target and (target == ns.MyName() or not ns.IsMember(target)) then target = nil end
  local id = time()
  for _, w in ipairs(db.wishes) do if w.id >= id then id = w.id + 1 end end
  local w = { id = id, spell = spell, item = item, count = count, pay = pay, tip = tip, target = target, state = "o", note = ns.CleanNote(note) }
  table.insert(db.wishes, w)
  ShareWishes()
  Changed()
  return w
end

local function OwnWish(id)
  for i, w in ipairs(DB().wishes) do if w.id == id then return w, i end end
end

-- wisher: received (done) or cancelled
function ns.SetWishState(id, state)
  local w = OwnWish(id)
  if not w or (state ~= "d" and state ~= "c" and state ~= "o") then return false end
  w.state = state
  w.changed = time()
  ShareWishes()
  Changed()
  return true
end

local function OwnJob(owner, id)
  for i, j in ipairs(DB().jobs) do if j.owner == owner and j.id == id then return j, i end end
end

-- crafter: accept, crafted, sent, or nil to give it back
function ns.SetJob(owner, id, state)
  local db = DB()
  local j, i = OwnJob(owner, id)
  if state == nil then
    if not j then return false end
    table.remove(db.jobs, i)
  elseif state == "a" then
    if j then return false end
    db.jobs[#db.jobs + 1] = { owner = owner, id = id, state = "a", t = time() }
  else
    if not j then return false end
    j.state = state
  end
  ShareJobs()
  Changed()
  return true
end

-- officer (or the wisher): delete a wish
function ns.DeleteWish(owner, id)
  if owner == ns.MyName() then
    local _, i = OwnWish(id)
    if not i then return false end
    table.remove(DB().wishes, i)
    ShareWishes()
    Changed()
    return true
  end
  if not ns.IsOfficer(ns.MyName()) then return false end
  local db = DB()
  for _, m in ipairs(db.mods) do if m.owner == owner and m.id == id then return false end end
  db.mods[#db.mods + 1] = { owner = owner, id = id, t = time() }
  ShareMods()
  Changed()
  return true
end

ns.RegisterKind("wish", {
  validate = function(d) return ns.DecodeWishes(d) ~= nil end,
  onUpdate = function(owner) ns.InvalidateWishes() if ns.OnWishesArrived then ns.OnWishesArrived(owner) end end,
})
ns.RegisterKind("job", {
  validate = function(d) return ns.DecodeJobs(d) ~= nil end,
  onUpdate = function(owner) ns.InvalidateWishes() if ns.OnJobsArrived then ns.OnJobsArrived(owner) end end,
})
ns.RegisterKind("mod", { direct = true, validate = function(d) return ns.DecodeMods(d) ~= nil end,
  onUpdate = function() ns.InvalidateWishes() end })
ns.RegisterKind("cfg", { direct = true, validate = function(d) return ns.DecodeCfg(d) ~= nil end,
  onUpdate = function() ns.InvalidateWishes() end })

---------------------------------------------------------------------------
-- All wishes of the guild with their combined state
---------------------------------------------------------------------------
local cache

function ns.InvalidateWishes() cache = nil end

-- spells the own characters can craft: spell -> list of own character names
local function MyCrafts()
  local out = {}
  for owner, entry in pairs(ns.db.prof or {}) do
    for _, e in pairs(entry) do
      for id in pairs(e.recipes or {}) do
        out[id] = out[id] or {}
        table.insert(out[id], owner)
      end
    end
  end
  return out
end
ns.MyCrafts = MyCrafts

local function Build()
  local db = DB()
  local now, days = time(), db.wishDays * 86400
  local me = ns.MyName()
  -- deletions by officers (checked now: the deleter must be an officer today)
  local deleted = {}
  for _, s in ipairs(ns.SetsOf("mod")) do
    if ns.IsOfficer(s.o) then
      for _, m in ipairs(ns.DecodeMods(s.d) or {}) do deleted[m.owner .. "#" .. m.id] = s.o end
    end
  end
  if ns.IsOfficer(me) then for _, m in ipairs(db.mods) do deleted[m.owner .. "#" .. m.id] = me end end
  -- jobs: earliest accept wins
  local jobs = {}
  local function AddJob(crafter, j)
    local k = j.owner .. "#" .. j.id
    jobs[k] = jobs[k] or {}
    table.insert(jobs[k], { crafter = crafter, state = j.state, t = j.t })
  end
  for _, s in ipairs(ns.SetsOf("job")) do
    if s.o ~= me then for _, j in ipairs(ns.DecodeJobs(s.d) or {}) do AddJob(s.o, j) end end
  end
  for _, j in ipairs(db.jobs) do AddJob(me, j) end
  local list, byKey = {}, {}
  local function Add(owner, w)
    local k = owner .. "#" .. w.id
    if byKey[k] then return end
    local e = { key = k, owner = owner, id = w.id, spell = w.spell, item = w.item, count = w.count, pay = w.pay, tip = w.tip or 0,
      target = w.target, note = w.note or "", created = w.id, ownState = w.state, demo = w.demo }
    local js = jobs[k] or {}
    table.sort(js, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.crafter < b.crafter end)
    e.jobs = js
    local winner = js[1]
    if deleted[k] then e.state, e.by = "x", deleted[k]
    elseif w.state == "d" or w.state == "c" then e.state = w.state
    elseif winner then e.state, e.crafter, e.stateTime = winner.state, winner.crafter, winner.t
    else e.state = "o" end
    -- running out
    local life = (e.state == "o") and days or ((e.state == "d" or e.state == "c" or e.state == "x") and 3 * 86400 or 2 * days)
    e.expires = w.id + life
    if e.state ~= "d" and e.state ~= "c" and e.state ~= "x" and now > e.expires then e.state = "e" end
    byKey[k] = e
    list[#list + 1] = e
  end
  for _, w in ipairs(db.wishes) do if me then Add(me, w) end end
  for _, s in ipairs(ns.SetsOf("wish")) do
    if s.o ~= me then for _, w in ipairs(ns.DecodeWishes(s.d) or {}) do Add(s.o, w) end end
  end
  for _, w in ipairs(ns.DemoWishes and ns.DemoWishes() or {}) do Add(w.owner, w) end
  cache = { list = list, byKey = byKey, mine = MyCrafts() }
  return cache
end

function ns.Wishes() return (cache or Build()).list end
function ns.Wish(key) return (cache or Build()).byKey[key] end

-- what the player may do with a wish
function ns.WishRole(e)
  local me = ns.MyName()
  local c = cache or Build()
  local r = { mine = e.owner == me, crafter = e.crafter == me }
  if e.item then r.canCraft = ns.CanGather(e.item) else r.canCraft = c.mine[e.spell] ~= nil end
  r.forMe = not r.mine and r.canCraft and (not e.target or e.target == me)
  r.myJob = false
  for _, j in ipairs(e.jobs or {}) do if j.crafter == me then r.myJob = j end end
  r.lost = r.myJob and e.crafter ~= me -- I accepted, someone else was earlier
  r.officer = not r.mine and ns.IsOfficer(me)
  return r
end

-- visible wishes for the list filter: "me" (mine and the ones I can craft), "mine", "craft", "all"
function ns.VisibleWishes(filter)
  local out = {}
  for _, e in ipairs(ns.Wishes()) do
    local r = ns.WishRole(e)
    local gone = e.state == "x" or e.state == "e"
    -- a wish for crafters: open, or in my hands
    local work = r.forMe and not gone and (e.state == "o" or r.crafter or r.myJob ~= false)
    local show
    if filter == "mine" then show = r.mine and e.state ~= "x"
    elseif filter == "craft" then show = work
    elseif filter == "all" then show = e.state ~= "e" or r.mine
    else show = (r.mine and e.state ~= "x") or work or r.crafter end
    if show then out[#out + 1] = e end
  end
  return out
end

-- open wishes that I could craft (overview, notifications)
function ns.OpenWishesForMe()
  local n = 0
  for _, e in ipairs(ns.Wishes()) do
    if e.state == "o" and ns.WishRole(e).forMe then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------
-- Housekeeping: drop finished and run out own wishes, drop jobs that lost or whose wish is gone
---------------------------------------------------------------------------
function ns.TidyWishes()
  local db = DB()
  local now, days = time(), db.wishDays * 86400
  local changedW, changedJ, changedM = false, false, false
  for i = #db.wishes, 1, -1 do
    local w = db.wishes[i]
    local e = ns.Wish((ns.MyName() or "") .. "#" .. w.id)
    -- (Daniel 26.10.: "Der kann dann doch direkt weg? Oder maximal einen Tag") received: gone at the next round (every 5 min,
    -- so the crafter's client sees "received" once and closes the job), cancelled: one day
    local life = (w.state == "o" and not (e and e.crafter)) and days or (w.state == "c" and 86400 or 2 * days)
    if (e and e.state == "x") or w.state == "d" or now > w.id + life then
      table.remove(db.wishes, i)
      changedW = true
    end
  end
  for i = #db.jobs, 1, -1 do
    local j = db.jobs[i]
    local e = ns.Wish(j.owner .. "#" .. j.id)
    local ownerSet = ns.GetSet("wish", j.owner)
    local gone = not e and ownerSet and ownerSet.t > j.t
    local lost = e and e.crafter and e.crafter ~= ns.MyName()
    local over = e and (e.state == "d" or e.state == "c" or e.state == "x" or e.state == "e")
    if gone or lost or over or now > j.t + 2 * days then
      table.remove(db.jobs, i)
      changedJ = true
    end
  end
  for i = #db.mods, 1, -1 do
    if now > db.mods[i].t + 30 * 86400 then table.remove(db.mods, i) changedM = true end
  end
  if changedW then ShareWishes() end
  if changedJ then ShareJobs() end
  if changedM then ShareMods() end
  if changedW or changedJ or changedM then Changed() end
  return changedW, changedJ
end

ns.OnInit(function() DB() end)
ns.On("PLAYER_LOGIN", function()
  ns.After(10, function()
    ns.InvalidateWishes()
    ns.TidyWishes()
    ShareWishes()
    ShareJobs()
    if #DB().mods > 0 then ShareMods() end
  end)
end)
ns.OnInit(function() ns.NewTicker(300, function() ns.InvalidateWishes() ns.TidyWishes() end) end)

---------------------------------------------------------------------------
-- Wishes for gathered items (Durchgang 5 Nr. 2): who may fetch them
---------------------------------------------------------------------------
-- gathering profession of an item from its kind (trade goods: herbs, metal and stone, leather), nil = anyone
local GATHER_SUB = { [9] = 182, [7] = 186, [6] = 393 }
function ns.GatherProf(item)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil end
  local ok, id, _, _, _, _, cls, sub = pcall(fn, item)
  if ok and id and cls == 7 then return GATHER_SUB[sub] end
end

-- can one of my characters fetch it: the matching gathering profession, or it is in my bags already
function ns.CanGather(item)
  if ns.ItemCount(item) > 0 then return true end
  local prof = ns.GatherProf(item)
  for _, entry in pairs(ns.db.prof or {}) do
    for skill in pairs(entry) do
      local p = ns.PROF_BY_ID[skill]
      if p and not p.craft or skill == 186 then
        if not prof or prof == skill then return true end
      end
    end
  end
  return false
end

-- what a wish is about: title, icon, item, pieces per craft, reagents, profession
function ns.WishInfo(e)
  if e.item then
    local name = ns.ItemName(e.item)
    return { title = name or L["Item %d"]:format(e.item), icon = ns.ItemIcon(e.item), item = e.item, count = 1, reagents = {},
      prof = ns.GatherProf(e.item), gather = true }
  end
  local info = ns.RecipeInfo(e.spell)
  info.title = ns.SpellName(e.spell) or L["Recipe %d"]:format(e.spell)
  info.icon = ns.RecipeIcon and ns.RecipeIcon(e.spell, info) or ns.SpellIcon(e.spell)
  return info
end

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
function ns.WishStateText(e)
  local s = L[ns.STATE_TEXT[e.state] or "open"]
  if (e.state == "a" or e.state == "m" or e.state == "s") and e.crafter then
    s = s .. " " .. L["by %s"]:format(ns.ShortName(e.crafter))
  elseif e.state == "x" and e.by then
    s = s .. " " .. L["by %s"]:format(ns.ShortName(e.by))
  end
  return s
end

function ns.MoneyText(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "|cffffd700" .. L["g"] .. "|r" end
  if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cf" .. L["s"] .. "|r" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|cffeda55f" .. L["c"] .. "|r" end
  return table.concat(parts, " ")
end

-- whisper the other side of a wish (opens the chat line)
function ns.WhisperAbout(target, e)
  if not target then return end
  if ns.IsDemo(target) then ns.Print(L["%s is an example member and cannot be whispered."]:format(ns.ShortName(target))) return end
  local info = ns.WishInfo(e)
  local what
  if info.item and info.item > 0 then
    local name, link = ns.ItemName(info.item)
    what = link or name
  end
  what = (what or info.title or "?") .. (e.count > 1 and (" x" .. e.count) or "")
  local text
  if target == e.owner then
    text = L["Hi, about your wish %s:"]:format(what)
  else
    text = L["Hi, about my wish %s:"]:format(what)
  end
  if ns.ReachableName then target = ns.ReachableName(target) end
  local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
  if open then ns.Call(open, ("/w %s %s "):format(ns.ShortName(target), text)) return true end
end
