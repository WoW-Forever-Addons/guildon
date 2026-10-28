local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Trade and mail for wishes (GUILDON_PLAN.md step 4). A bar below the game's trade window or mailbox shows the
-- orders with the other player and puts in what belongs to them: the wisher's reagents ("mats there"), the
-- crafter's goods. One stack per click (the game wants a click of the player for every item it moves; GUILDON_PLAN.md
-- "Grenzen"), never in combat. Accepting a trade and sending a letter stay with the player.
-- Mail: name, subject and the goods are filled in; cash on delivery for "I pay for the reagents" when Guildon knows
-- prices (Durchgang 5 Nr. 5, can be switched off). A completed trade or sent letter with the goods marks the job sent.
-- No hooks into the game's frames: our own frame, placed next to theirs.
---------------------------------------------------------------------------
local TRADE_SLOTS, MAIL_SLOTS = 6, 12

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = ns.Call(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then return ns.Num(info.itemID), ns.Num(info.stackCount) or 1, info.isLocked end
    return nil
  end
  if GetContainerItemInfo then
    local ok, _, count, locked, _, _, _, link, _, _, id = pcall(GetContainerItemInfo, bag, slot)
    if not ok then return nil end
    id = ns.Num(id) or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
    if id then return id, ns.Num(count) or 1, locked end
  end
end

local function NumSlots(bag)
  local fn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  return ns.Num(ns.Call(fn, bag)) or 0
end

-- the best stack of an item for "need" pieces: an exact stack, else the smallest bigger one, else the biggest
function ns.FindStack(item, need)
  local best
  for bag = 0, 4 do
    for slot = 1, NumSlots(bag) do
      local id, count, locked = SlotInfo(bag, slot)
      if id == item and not locked then
        local s = { bag = bag, slot = slot, count = count }
        if count == need then return s end
        if not best then best = s
        elseif count > need and (best.count < need or count < best.count) then best = s
        elseif best.count < need and count > best.count then best = s end
      end
    end
  end
  return best
end

-- take n pieces of a stack to the cursor (split when the stack is bigger)
local function Pick(stack, n)
  local C_ = C_Container
  if n < stack.count then
    local fn = (C_ and C_.SplitContainerItem) or SplitContainerItem
    return ns.Call(fn, stack.bag, stack.slot, n) ~= false
  end
  local fn = (C_ and C_.PickupContainerItem) or PickupContainerItem
  return ns.Call(fn, stack.bag, stack.slot) ~= false
end

local function CursorHasItem()
  local fn = CursorHasItem
  if type(fn) == "function" then return ns.Call(fn) and true or false end
  return false
end

---------------------------------------------------------------------------
-- Orders with a partner
---------------------------------------------------------------------------
-- what goes from me to the partner: { wish, kind = "mats" | "goods" | "enchant", items = { { item, n }, ... } }
function ns.OrdersWith(partner)
  local out = {}
  if not partner then return out end
  local me = ns.MyName()
  for _, e in ipairs(ns.Wishes()) do
    local info = ns.WishInfo(e)
    local enchant = not (info.item and info.item > 0)
    if e.owner == me and e.crafter == partner and e.state == "a" then
      local items = {}
      if e.pay == "m" then
        for _, rg in ipairs(info.reagents or {}) do items[#items + 1] = { rg[1], rg[2] * e.count } end
      end
      if #items > 0 then out[#out + 1] = { wish = e, kind = "mats", items = items, enchant = enchant }
      elseif enchant then out[#out + 1] = { wish = e, kind = "enchant", items = {} } end
    elseif e.crafter == me and e.owner == partner and (e.state == "a" or e.state == "m") then
      if enchant then out[#out + 1] = { wish = e, kind = "enchant", items = {} }
      else out[#out + 1] = { wish = e, kind = "goods", items = { { info.item, (info.count or 1) * e.count } } } end
    end
  end
  return out
end

-- how many of an item already sit in the trade / mail slots
local function TradeHas(item)
  local n = 0
  for i = 1, TRADE_SLOTS do
    local link = ns.Call(GetTradePlayerItemLink, i)
    if type(link) == "string" and tonumber(link:match("item:(%d+)")) == item then
      local _, _, qty = ns.Call(GetTradePlayerItemInfo, i)
      n = n + (ns.Num(qty) or 1)
    end
  end
  return n
end

local function TradeFree()
  for i = 1, TRADE_SLOTS do
    local name = ns.Call(GetTradePlayerItemInfo, i)
    if not ns.Str(name) then return i end
  end
end

local function MailHas(item)
  local n = 0
  for i = 1, MAIL_SLOTS do
    local _, id, _, count = ns.Call(GetSendMailItem, i)
    if ns.Num(id) == item then n = n + (ns.Num(count) or 1) end
  end
  return n
end

local function MailFree()
  for i = 1, MAIL_SLOTS do
    local name = ns.Call(GetSendMailItem, i)
    if not ns.Str(name) then return i end
  end
end

-- what is still missing of an order in the window: item, pieces (nil when everything is in)
local function Missing(order, has)
  for _, it in ipairs(order.items) do
    local left = it[2] - has(it[1])
    if left > 0 then return it[1], left end
  end
end
ns.OrderMissing = Missing

-- put the next stack of an order into the window. Returns "done", "put", "none" (not in the bags), "full", "combat"
local function PutNext(order, has, free, click)
  if InCombatLockdown and InCombatLockdown() then return "combat" end
  local item, left = Missing(order, has)
  if not item then return "done" end
  local slot = free()
  if not slot then return "full" end
  local stack = ns.FindStack(item, left)
  if not stack then return "none", item end
  if CursorHasItem() then ns.Call(ClearCursor) end
  if not Pick(stack, math.min(left, stack.count)) then return "none", item end
  ns.Call(click, slot)
  if CursorHasItem() then ns.Call(ClearCursor) end -- never leave an item at the cursor
  return "put", item
end

function ns.PutIntoTrade(order) return PutNext(order, TradeHas, TradeFree, ClickTradeButton) end
function ns.PutIntoMail(order) return PutNext(order, MailHas, MailFree, ClickSendMailItemButton) end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local bar, Watch
local state = { mode = nil, partner = nil, orders = {}, index = 1, gave = {} }

local function OrderTitle(o)
  local e = o.wish
  return ns.WishInfo(e).title .. (e.count > 1 and (" x" .. e.count) or "")
end

local BAR_W, PAD, GAP, BTN_H = 340, 10, 6, 22

local function BuildBar()
  bar = CreateFrame("Frame", "GuildonTradeBar", UIParent)
  bar:SetSize(BAR_W, 76)
  bar:SetFrameStrata("DIALOG")
  bar:EnableMouse(true)
  -- the same look as the main window: thin gold line, dark blue inside, a darker band for the title (Daniel 26.10.)
  ns.UI.Skin(bar, Style.PAL.popup, { C.background[1], C.background[2], C.background[3], 0.95 })
  local band = bar:CreateTexture(nil, "ARTWORK")
  band:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
  band:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -1)
  band:SetHeight(24)
  band:SetColorTexture(Style.BOOK.header[1], Style.BOOK.header[2], Style.BOOK.header[3], 1)
  bar.title = ns.UI.Text(bar, "GameFontNormalSmall", PAD, -8, BAR_W - 2 * PAD, "gold")
  local line = ns.UI.Line(bar)
  line:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -25)
  line:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -25)
  bar.info = ns.UI.Text(bar, "GameFontHighlightSmall", PAD, -31, BAR_W - 2 * PAD, "textSecondary")
  bar.info:SetWordWrap(true)
  bar.info:SetJustifyV("TOP")
  -- the buttons share the width evenly (Layout)
  bar.put = ns.UI.FlatButton(bar, 100, BTN_H, "")
  bar.put:SetScript("OnClick", ns.Guard("trade put", function() ns.BarPut() end))
  bar.fill = ns.UI.FlatButton(bar, 100, BTN_H, L["Fill in letter"])
  bar.fill:SetScript("OnClick", ns.Guard("mail fill", function() ns.FillLetter() end))
  bar.next = ns.UI.FlatButton(bar, 100, BTN_H, L["next"])
  bar.next:SetScript("OnClick", ns.Guard("trade next", function()
    state.index = state.index % math.max(1, #state.orders) + 1
    ns.PaintBar()
  end))
  bar:Hide()
end

-- the visible buttons in one row, all the same width over the whole bar; the bar is as high as its text needs
local function Layout()
  local list = {}
  for _, b in ipairs({ bar.put, bar.fill, bar.next }) do if b:IsShown() then list[#list + 1] = b end end
  local n = #list
  if n > 0 then
    local w = math.floor((BAR_W - 2 * PAD - GAP * (n - 1)) / n)
    for i, b in ipairs(list) do
      b:SetWidth(w)
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", PAD + (i - 1) * (w + GAP), 8)
    end
  end
  local th = tonumber(bar.info:GetStringHeight()) or 12
  local lines = math.max(1, math.min(3, math.floor(th / 12 + 0.5)))
  bar.info:SetHeight(lines * 12)
  bar:SetHeight(31 + lines * 12 + 8 + (n > 0 and BTN_H + 8 or 0))
end

local function Anchor()
  bar:ClearAllPoints()
  local host = state.mode == "trade" and _G.TradeFrame or _G.MailFrame
  if host and host.IsShown and host:IsShown() then
    bar:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -4)
  else
    bar:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
end

function ns.PaintBar()
  if not bar then return end
  local o = state.orders[state.index]
  if not o or not ns.BarWanted() then bar:Hide() return end
  Anchor()
  local e = o.wish
  local who = ns.ShortName(state.partner or "?")
  bar.title:SetText(Style.Wordmark("Guil", "don") .. "  " .. L["Order: %s"]:format(OrderTitle(o)) ..
    (#state.orders > 1 and ("  (" .. state.index .. "/" .. #state.orders .. ")") or ""))
  local has = state.mode == "trade" and TradeHas or MailHas
  local item, left = Missing(o, has)
  -- a letter counts as the delivery only when all goods are attached
  if state.mode == "mail" and o.kind == "goods" then state.complete = item == nil and o.wish.key or nil end
  local label, info
  if o.kind == "mats" then
    label = L["Put in reagents"]
    info = item and L["For %s: %d x %s still missing."]:format(who, left, ns.ItemName(item) or ("#" .. item))
      or L["All reagents are in. Accept the trade yourself."]
    if o.enchant and state.mode == "trade" then info = info .. " " .. L["Put the item to enchant into the bottom slot."] end
  elseif o.kind == "goods" then
    label = L["Put in goods"]
    info = item and L["For %s: %d x %s still missing."]:format(who, left, ns.ItemName(item) or ("#" .. item))
      or (state.mode == "trade" and L["Everything is in. Accept the trade yourself."] or L["Everything is in. Send the letter yourself."])
  else
    label = nil
    info = e.crafter == ns.MyName() and L["An enchantment: the other player puts the item into the bottom slot (will not be traded)."]
      or L["An enchantment: put your item into the bottom slot (will not be traded)."]
  end
  bar.info:SetText(info)
  bar.put:SetShown(label ~= nil and item ~= nil)
  if label then bar.put.label:SetText(label) end
  bar.fill:SetShown(state.mode == "mail")
  bar.next:SetShown(#state.orders > 1)
  Layout()
  bar:Show()
end

function ns.BarPut()
  local o = state.orders[state.index]
  if not o then return end
  local r, item
  if state.mode == "trade" then r, item = ns.PutIntoTrade(o) else r, item = ns.PutIntoMail(o) end
  if r == "put" and o.kind == "goods" then state.gave[o.wish.key] = true end
  if r == "none" then ns.Print(L["Not in your bags: %s."]:format(ns.ItemName(item) or ("#" .. tostring(item))))
  elseif r == "full" then ns.Print(state.mode == "trade" and L["The trade window is full: trade this part first."] or L["The letter is full: send this part first."])
  elseif r == "combat" then ns.Print(L["Not in combat."]) end
  ns.After(0.2, ns.PaintBar)
  return r
end

local function Open(mode, partner)
  if not ns.Wishes then return end
  ns.InvalidateWishes()
  state.mode, state.partner, state.index, state.gave = mode, partner, 1, {}
  state.orders = ns.OrdersWith(partner)
  if not bar then BuildBar() end
  if #state.orders == 0 then bar:Hide() return end
  Watch(true)
  ns.PaintBar()
end

function ns.TradeBarState() return bar, state end -- (tests)

local function Close()
  if bar then bar:Hide() end
  state.mode, state.partner, state.orders = nil, nil, {}
  Watch(false)
end

-- Where the bar belongs (Daniel 26.10.): at the trade window; at the mailbox only on the Send tab, not in the inbox.
-- A frame the client does not have counts as open, so that nothing depends on Blizzard's names.
local function IsOpen(f) if not f or not f.IsShown then return true end return f:IsShown() and true or false end

function ns.HostOpen()
  return IsOpen(state.mode == "trade" and _G.TradeFrame or _G.MailFrame)
end

function ns.BarWanted()
  if state.mode == "mail" then return ns.HostOpen() and IsOpen(_G.SendMailFrame) end
  return state.mode ~= nil and ns.HostOpen()
end

-- Our own frame looks five times a second while the window is open (no hooks on Blizzard's frames): the bar comes with the
-- Send tab and goes with the window however it was closed (Cancel, Esc, walking away), also when no event says so.
local watch
local gone = 0
function Watch(on)
  if not watch then watch = CreateFrame("Frame") end
  if not on then watch:SetScript("OnUpdate", nil) return end
  local acc = 0
  gone = 0
  watch:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    if not state.mode then return end
    if not ns.HostOpen() then
      gone = gone + 1
      if gone >= 2 then Close() end -- two looks in a row: the window may only be opening
      return
    end
    gone = 0
    if not bar then return end
    local want = ns.BarWanted() and #state.orders > 0
    if want and not bar:IsShown() then ns.PaintBar()
    elseif not want and bar:IsShown() then bar:Hide() end
  end)
end

-- trade: the partner is the "NPC" unit while the trade window is open
ns.On("TRADE_SHOW", function()
  local name, realm = ns.Call(UnitName, "NPC")
  name = ns.Str(name)
  if not name then return end
  local full = ns.FullName(realm and ns.Str(realm) and (name .. "-" .. realm) or name)
  Open("trade", full)
end)
ns.On("TRADE_PLAYER_ITEM_CHANGED", function() if state.mode == "trade" then ns.After(0.1, ns.PaintBar) end end)
ns.On("TRADE_CLOSED", function() if state.mode == "trade" then Close() end end)
---------------------------------------------------------------------------
-- The wisher's side (Daniel 26.10.: "Verschickte Wünsche nach dem Öffnen als erledigt, gleiches bei direktem Handel",
-- with 200 members the list would fill up): a wish counts as received when its goods come in a trade from the crafter,
-- or when the wisher opens a letter from the crafter with the goods (or with Guildon's subject after a sent order).
---------------------------------------------------------------------------
local function ItemIdOf(link)
  link = ns.Str(link)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

-- my open wishes the partner works on; sentOnly: only those the crafter marked sent
local function MyWishesFrom(partner, sentOnly)
  local out, me = {}, ns.MyName()
  if not partner or not ns.Wishes then return out end
  local short = ns.ShortName(partner)
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == me and e.crafter and (e.crafter == partner or ns.ShortName(e.crafter) == short)
      and (e.state == "s" or (not sentOnly and (e.state == "a" or e.state == "m"))) then
      out[#out + 1] = e
    end
  end
  return out
end

local function Received(e, how)
  if not ns.SetWishState(e.id, "d") then return false end
  if ns.CountThanks then ns.CountThanks(e.crafter) end
  local info = ns.WishInfo and ns.WishInfo(e) or {}
  ns.Print(L["Wish done (%s): %s from %s."]:format(how, info.title or "?", ns.ShortName(e.crafter)))
  return true
end

-- trade: what the partner hands over, noted while the window is open (the slots are empty once it closes)
local tradeGot, tradePartner = {}, nil
local function NoteTrade()
  tradeGot = {}
  local partner = tradePartner
  if not partner then return end
  local offered = {}
  for i = 1, 6 do
    local id = ItemIdOf(ns.Call(GetTradeTargetItemLink, i))
    if id then offered[id] = true end
  end
  -- an enchant: my item lies in the slot that is not traded
  local myItem = ItemIdOf(ns.Call(GetTradePlayerItemLink, 7))
  for _, e in ipairs(MyWishesFrom(partner)) do
    local info = ns.WishInfo(e)
    if info.item and info.item > 0 then
      if offered[info.item] then tradeGot[e.key] = e end
    elseif myItem then
      tradeGot[e.key] = e
    end
  end
end
ns.On("TRADE_SHOW", function()
  local name, realm = ns.Call(UnitName, "NPC")
  name = ns.Str(name)
  tradePartner = name and ns.FullName(realm and ns.Str(realm) and (name .. "-" .. realm) or name) or nil
  tradeGot = {}
end)
ns.On("TRADE_TARGET_ITEM_CHANGED", NoteTrade)
ns.On("TRADE_PLAYER_ITEM_CHANGED", NoteTrade)
ns.On("TRADE_ACCEPT_UPDATE", NoteTrade)

-- a finished trade: the goods I gave mark my jobs sent, the goods I got mark my wishes received
ns.On("UI_INFO_MESSAGE", function(_, _, msg)
  if msg ~= ERR_TRADE_COMPLETE and msg ~= "ERR_TRADE_COMPLETE" then return end
  if state.mode == "trade" and next(state.gave) then
    for key in pairs(state.gave) do
      local e = ns.Wish(key)
      if e and e.crafter == ns.MyName() then ns.SetJob(e.owner, e.id, "s") end
    end
    state.gave = {}
  end
  for _, e in pairs(tradeGot) do Received(e, L["by trade"]) end
  tradeGot = {}
end)

-- mail: a letter from the crafter that I have opened
function ns.CheckInbox()
  local n = ns.Num(ns.Call(GetInboxNumItems)) or 0
  if n == 0 or type(GetInboxHeaderInfo) ~= "function" then return 0 end
  local done = 0
  local maxAtt = ATTACHMENTS_MAX_RECEIVE or 16
  for i = 1, n do
    -- direct pcall: ns.Call hands back only four values, wasRead is the ninth
    local ok, _, _, sender, subject, _, _, _, hasItem, wasRead = pcall(GetInboxHeaderInfo, i)
    if not ok then sender = nil end
    sender = ns.Str(sender)
    if sender and wasRead then
      local items = {}
      if hasItem then
        for j = 1, maxAtt do
          local id = ItemIdOf(ns.Call(GetInboxItemLink, i, j))
          if id then items[id] = true end
        end
      end
      local guildon = ns.Str(subject) and ns.Str(subject):find("^Guildon: ") and true
      for _, e in ipairs(MyWishesFrom(sender)) do
        local info = ns.WishInfo(e)
        local hit = (info.item and items[info.item]) or (guildon and e.state == "s")
        if hit and Received(e, L["by mail"]) then done = done + 1 end
      end
    end
  end
  return done
end
ns.On("MAIL_INBOX_UPDATE", function() if ns.Wishes then ns.CheckInbox() end end)

---------------------------------------------------------------------------
-- Mail: orders with the player whose name is in the "To" field, or all my crafted orders
---------------------------------------------------------------------------
local function MailOrders()
  local out, me = {}, ns.MyName()
  ns.InvalidateWishes()
  for _, e in ipairs(ns.Wishes()) do
    if e.crafter == me and (e.state == "m" or e.state == "a") then
      local partner = e.owner
      for _, o in ipairs(ns.OrdersWith(partner)) do if o.wish.key == e.key then out[#out + 1] = o end end
    end
  end
  return out
end

function ns.FillLetter()
  local o = state.orders[state.index]
  if not o then return false end
  local e = o.wish
  local to = o.kind == "mats" and e.crafter or e.owner
  local name = ns.Str(SendMailNameEditBox and ns.Call(SendMailNameEditBox.GetText, SendMailNameEditBox))
  if SendMailNameEditBox then ns.Call(SendMailNameEditBox.SetText, SendMailNameEditBox, ns.ShortName(to)) end
  if SendMailSubjectEditBox then
    ns.Call(SendMailSubjectEditBox.SetText, SendMailSubjectEditBox, ("Guildon: %s"):format(OrderTitle(o)):sub(1, 64))
  end
  -- cash on delivery: the wisher pays for the reagents (estimate from the prices) plus the tip
  if o.kind == "goods" and e.pay == "p" and ns.db.mailCOD ~= false and ns.ReagentCost then
    local cost
    if e.item then cost = ns.Price and ns.Price(e.item) and ns.Price(e.item) * e.count else cost = ns.ReagentCost(e.spell, e.count) end
    if cost and cost > 0 then ns.Call(SetSendMailCOD, cost + (e.tip or 0)) end
  end
  state.partner = to
  state.letter = e.key
  ns.PaintBar()
  return name ~= ns.ShortName(to)
end

ns.On("MAIL_SHOW", function()
  if not ns.Wishes then return end
  state.mode, state.index, state.gave = "mail", 1, {}
  state.orders = MailOrders()
  -- the wisher's reagents by mail when the crafter is not around
  for _, e in ipairs(ns.Wishes()) do
    if e.owner == ns.MyName() and e.crafter and e.state == "a" and e.pay == "m" then
      for _, o in ipairs(ns.OrdersWith(e.crafter)) do if o.wish.key == e.key then state.orders[#state.orders + 1] = o end end
    end
  end
  if not bar then BuildBar() end
  if #state.orders == 0 then bar:Hide() return end
  Watch(true) -- the bar itself waits for the Send tab (PaintBar)
  ns.PaintBar()
end)
ns.On("MAIL_CLOSED", function() if state.mode == "mail" then Close() end end)
ns.On("MAIL_SEND_INFO_UPDATE", function() if state.mode == "mail" then ns.After(0.1, ns.PaintBar) end end)
ns.On("MAIL_SEND_SUCCESS", function()
  if state.mode ~= "mail" or not state.letter then return end
  local e = ns.Wish(state.letter)
  if e and e.crafter == ns.MyName() and state.complete == state.letter then ns.SetJob(e.owner, e.id, "s") end
  state.complete = nil
  state.letter = nil
  ns.After(0.5, function() if state.mode == "mail" then state.orders = MailOrders() state.index = 1 ns.PaintBar() end end)
end)
