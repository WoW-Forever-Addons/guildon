local _, ns = ...

---------------------------------------------------------------------------
-- Exchange core (GUILDON_PLAN.md "Wie es technisch geht"): no server, addon messages in the guild channel and by
-- whisper. Data comes in sets, key "<kind>:<owner>" (e.g. "info:Dedel-Realm"), each with stamp (time()) and checksum.
-- Only the fingerprints travel through the guild; a missing or older set is fetched by whisper from whoever announced it.
--
-- Messages (prefix ns.PREFIX, fields split by ":", the payload last):
--   H:<version>                            hello: in the guild at login, by whisper as the answer to a new peer
--   S:<kind>:<owner>:<stamp>:<sum>         "I have this set" (in the guild when an own set changes, by whisper after H)
--   G:<kind>:<owner>                       fetch request, by whisper to the one who announced it
--   D:<kind>:<owner>:<stamp>:<sum>:<i>:<n>:<chunk>   one piece of a set, by whisper
-- Received data are data, never code: unknown kinds are ignored, every kind checks its data (ns.RegisterKind).
-- Messages go through a queue with a pace of 4 per second; a throttled message is sent again (up to 5 tries).
---------------------------------------------------------------------------
local PACE, MAX_TRIES, CHUNK, MAX_SET, FETCH_TIMEOUT = 0.25, 5, 200, 16000, 30
local kinds = {}
local queue, sending = {}, false
local pending = {}   -- key -> { stamp, sum, n, parts = {}, got, from, t }
local answered = {}  -- peers answered this session
local stats = { sent = 0, received = 0, retried = 0, dropped = 0, stored = 0, rejected = 0 }

function ns.RegisterKind(kind, def) kinds[kind] = def or {} end
function ns.CommStats() return stats, queue, pending end -- (tests, diag)

local function Key(kind, owner) return kind .. ":" .. owner end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function RawSend(msg, chat, target)
  local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
  if type(fn) ~= "function" then return false end
  local ok, res = pcall(fn, ns.PREFIX, msg, chat, target)
  if not ok then return false end
  -- Forever (Retail) returns Enum.SendAddonMessageResult (0 = success), older clients true/false or nothing
  return res == nil or res == true or res == 0
end

local function Pump()
  local item = table.remove(queue, 1)
  if not item then sending = false return end
  if RawSend(item.msg, item.chat, item.target) then
    stats.sent = stats.sent + 1
  else
    item.tries = item.tries + 1
    if item.tries < MAX_TRIES then
      stats.retried = stats.retried + 1
      table.insert(queue, 1, item)
      ns.After(PACE * 4, Pump)
      return
    end
    stats.dropped = stats.dropped + 1
  end
  ns.After(PACE, Pump)
end

function ns.Send(msg, chat, target)
  if type(msg) ~= "string" or #msg > 255 then return false end
  if chat == "GUILD" and not ns.InGuild() then return false end
  -- positions only: one queue, but never more than one waiting position (the newest counts)
  if msg:sub(1, 2) == "P:" then
    for i = #queue, 1, -1 do if queue[i].msg:sub(1, 2) == "P:" and queue[i].chat == chat then table.remove(queue, i) end end
  end
  queue[#queue + 1] = { msg = msg, chat = chat, target = target, tries = 0 }
  if not sending then sending = true ns.After(0, Pump) end
  return true
end

local function Announce(set, chat, target)
  ns.Send(("S:%s:%s:%d:%s"):format(set.k, set.o, set.t, set.s), chat, target)
end

---------------------------------------------------------------------------
-- Own data
---------------------------------------------------------------------------
-- Store an own set; announced in the guild when it changed.
function ns.SetOwn(kind, data)
  local me = ns.MyName()
  if not me or not kinds[kind] or type(data) ~= "string" or #data > MAX_SET then return false end
  local key, sum = Key(kind, me), ns.Checksum(data)
  local old = ns.db.sets[key]
  if old and old.s == sum then return false end
  local set = { k = kind, o = me, t = time(), s = sum, d = data }
  if old and old.t >= set.t then set.t = old.t + 1 end
  ns.db.sets[key] = set
  Announce(set, "GUILD")
  return true
end

function ns.GetSet(kind, owner) return ns.db.sets[Key(kind, owner)] end

function ns.SetsOf(kind)
  local out = {}
  for _, s in pairs(ns.db.sets) do if s.k == kind then out[#out + 1] = s end end
  for _, s in ipairs(ns.DemoSets and ns.DemoSets(kind) or {}) do out[#out + 1] = s end
  return out
end

-- Hello in the guild; force = also when already greeted (/gn sync)
local greeted = false
function ns.Hello(force)
  if not ns.InGuild() or (greeted and not force) then return end
  greeted = true
  local me = ns.MyName()
  if me then ns.db.peers[me] = { v = ns.VERSION, t = time() } end
  ns.Send("H:" .. ns.VERSION, "GUILD")
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Fetch(kind, owner, stamp, sum, from)
  local key = Key(kind, owner)
  local p = pending[key]
  if p and p.stamp >= stamp and GetTime() - p.t < FETCH_TIMEOUT then return end
  pending[key] = { stamp = stamp, sum = sum, parts = {}, got = 0, from = from, t = GetTime() }
  ns.Send("G:" .. key, "WHISPER", from)
end

local function OnHello(sender, version, chat)
  ns.db.peers[sender] = { v = version:sub(1, 20), t = time() }
  if answered[sender] then return end
  answered[sender] = true
  -- answer by whisper after a short, spread delay: own version and the sets we hold (own ones, and those whose owner
  -- is offline, so that a newcomer also gets them)
  local delay = chat == "GUILD" and (1 + math.random() * 3) or 0.5
  ns.After(delay, function()
    if chat == "GUILD" then ns.Send("H:" .. ns.VERSION, "WHISPER", sender) end
    local me = ns.MyName()
    for _, set in pairs(ns.db.sets) do
      local def = kinds[set.k]
      if def and set.o ~= sender and (set.o == me or (not def.direct and not ns.IsOnline(set.o))) then Announce(set, "WHISPER", sender) end
    end
  end)
end

local function OnAnnounce(sender, kind, owner, stamp, sum)
  if not kinds[kind] or owner == ns.MyName() or not ns.IsMember(owner) or ns.IsDemo(owner) then return end
  -- kinds that carry rights (guild master's settings, officers' deletions) only come from their owner in person
  if kinds[kind].direct and sender ~= owner then return end
  local have = ns.db.sets[Key(kind, owner)]
  if have and (have.t > stamp or (have.t == stamp and have.s == sum)) then return end
  Fetch(kind, owner, stamp, sum, sender)
end

local function OnRequest(sender, kind, owner)
  local set = ns.db.sets[Key(kind, owner)]
  if not set or not set.d then return end
  local n = math.max(1, math.ceil(#set.d / CHUNK))
  for i = 1, n do
    ns.Send(("D:%s:%s:%d:%s:%d:%d:%s"):format(kind, owner, set.t, set.s, i, n, set.d:sub((i - 1) * CHUNK + 1, i * CHUNK)),
      "WHISPER", sender)
  end
end

local function OnPiece(sender, kind, owner, stamp, sum, i, n, chunk)
  local key = Key(kind, owner)
  local p = pending[key]
  if not p or p.from ~= sender or p.stamp ~= stamp or p.sum ~= sum then return end
  if n < 1 or n > math.ceil(MAX_SET / CHUNK) or i < 1 or i > n or (p.n and p.n ~= n) then return end
  p.n = n
  if not p.parts[i] then p.parts[i] = chunk p.got = p.got + 1 end
  p.t = GetTime()
  if p.got < n then return end
  pending[key] = nil
  local data = table.concat(p.parts, "", 1, n)
  local def = kinds[kind]
  if ns.Checksum(data) ~= sum or (def.validate and not def.validate(data, owner)) then
    stats.rejected = stats.rejected + 1
    return
  end
  local old = ns.db.sets[key]
  if old and old.t > stamp then return end
  ns.db.sets[key] = { k = kind, o = owner, t = stamp, s = sum, d = data }
  stats.stored = stats.stored + 1
  if def.onUpdate then ns.SafeCall("set " .. kind, def.onUpdate, owner) end
  if ns.OnDataChanged then ns.OnDataChanged(kind, owner) end
end

local function N(v) return tonumber(v) end

-- short messages of other parts (map positions): ns.MSG[tag] = function(sender, rest, chat); they may also come by
-- PARTY or RAID (positions shared only with the group)
ns.MSG = ns.MSG or {}
local CHATS = { GUILD = true, WHISPER = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

function ns.Receive(prefix, text, chat, sender)
  if prefix ~= ns.PREFIX or type(text) ~= "string" or #text > 255 then return end
  if not CHATS[chat] then return end
  local group = chat ~= "GUILD" and chat ~= "WHISPER"
  sender = ns.FullName(sender)
  if not sender or sender == ns.MyName() or not ns.IsMember(sender) or ns.IsDemo(sender) then return end
  stats.received = stats.received + 1
  local tag, rest = text:match("^(%u):(.*)$")
  if group then
    if tag and ns.MSG[tag] then ns.SafeCall("msg " .. tag, ns.MSG[tag], sender, rest, chat) end
    return
  end
  if tag == "H" then
    local v = rest:match("^([%w%.%-]+)$")
    if v then OnHello(sender, v, chat) end
  elseif tag == "S" then
    local kind, owner, stamp, sum = rest:match("^(%l+):([^:]+):(%d+):(%x+)$")
    if kind then OnAnnounce(sender, kind, owner, N(stamp), sum) end
  elseif tag == "G" and chat == "WHISPER" then
    local kind, owner = rest:match("^(%l+):([^:]+)$")
    if kind then OnRequest(sender, kind, owner) end
  elseif tag == "D" and chat == "WHISPER" then
    local kind, owner, stamp, sum, i, n, chunk = rest:match("^(%l+):([^:]+):(%d+):(%x+):(%d+):(%d+):(.*)$")
    if kind then OnPiece(sender, kind, owner, N(stamp), sum, N(i), N(n), chunk) end
  elseif tag and ns.MSG[tag] then
    ns.SafeCall("msg " .. tag, ns.MSG[tag], sender, rest, chat)
  end
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, chat, sender) ns.Receive(prefix, text, chat, sender) end)

---------------------------------------------------------------------------
-- Start: register the prefix, own info set, hello a few seconds after login
---------------------------------------------------------------------------
-- "info": the character's card (Guildon version, level, class). First kind; more follow in step 2 (professions).
ns.RegisterKind("info", {
  validate = function(d) return #d <= 100 and d:match("^[%w%.%-]+;%d+;%u*$") ~= nil end,
})

function ns.InfoOf(owner)
  local set = ns.GetSet("info", owner)
  if not set then return nil end
  local v, lv, cls = set.d:match("^([^;]*);(%d+);(%u*)$")
  return { version = v, level = tonumber(lv), classFile = cls, stamp = set.t }
end

local function UpdateInfo()
  local lv = ns.Num(ns.Call(UnitLevel, "player")) or 0
  local _, cls = ns.Call(UnitClass, "player")
  ns.SetOwn("info", ("%s;%d;%s"):format(ns.VERSION, lv, ns.Str(cls) and cls:match("^%u+$") or ""))
end

ns.OnInit(function()
  local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
  ns.Call(reg, ns.PREFIX)
end)

ns.On("PLAYER_LOGIN", function()
  ns.After(8, function()
    ns.Hello()
    UpdateInfo()
  end)
end)
ns.On("PLAYER_LEVEL_UP", function() ns.After(2, UpdateInfo) end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.After(3, function() ns.Hello() UpdateInfo() end) end)

-- old fetches that never finished are forgotten
ns.OnInit(function()
  ns.NewTicker(10, function()
    local now = GetTime()
    for key, p in pairs(pending) do if now - p.t > FETCH_TIMEOUT then pending[key] = nil end end
  end)
end)

function ns.PrintDiag()
  local total, online, guildon, guildonOnline = ns.MemberCounts()
  local sets = 0
  for _ in pairs(ns.db.sets) do sets = sets + 1 end
  local npend = 0
  for _ in pairs(pending) do npend = npend + 1 end
  ns.Print(("v%s %s, prefix %s"):format(ns.VERSION, ns.ERA and "Era" or "Forever", ns.PREFIX))
  print(("  members %d, online %d, with Guildon %d (online %d)"):format(total, online, guildon, guildonOnline))
  print(("  sets %d, pending %d, queue %d; sent %d, received %d, retried %d, dropped %d, stored %d, rejected %d")
    :format(sets, npend, #queue, stats.sent, stats.received, stats.retried, stats.dropped, stats.stored, stats.rejected))
  local ws = ns.WorldPinState and ns.WorldPinState()
  if ws then
    print(("  world map: shown map %s, you on %s, canvas %dx%d, scale %.2f, positions %d, on this map %d, pins %d; first pin visible %s, alpha %s, size %s, level %s (canvas %s)")
      :format(tostring(ws.map), tostring(ws.mine), ws.w or 0, ws.h or 0, ws.scale or 0, ws.have, ws.onMap, ws.pins, tostring(ws.vis),
        tostring(ws.alpha), tostring(ws.size), tostring(ws.level), tostring(ws.canvasLevel)))
    print(("  map levels: explored areas %s, area POI %s"):format(tostring(ws.expl), tostring(ws.poi)))
  else
    print("  world map: not looked at yet (open the world map once, then /gn diag)")
  end
  -- (27.10., Frankston: our pins over Questie and GatherMate) the levels of the other addons' pins, to place ours below
  if ns.ForeignPinLevels then
    for _, line in ipairs(ns.ForeignPinLevels()) do print("  " .. line) end
  end
  if ns.RecipeReport then print(("  recipes the data lacks or knows without reagents: %d (/gn recipes)"):format(select(2, ns.RecipeReport()))) end
  for _, e in ipairs(ns.Errors()) do print(("  error [%s] x%d: %s"):format(e.context, e.count, e.msg)) end
end
