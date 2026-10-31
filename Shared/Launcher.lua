local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (31.10.2026, Daniel: "alle Addons von Guildon: einen Minimap button teilen", "modulares System") One minimap button for every
-- Guildon module (Guildon: Map & Members, Guildon: Crafts & Recipes, later more). Each module carries this file (GuildShared/),
-- the first copy that loads makes the global GuildonLauncher, the others only sign in with their entry
-- (ns.MODULE = { id, title, icon, order }; open = ns.ToggleWindow; tip = ns.LauncherTip). A click shows the modules to choose
-- from; with one module it opens that one at once. Drag moves the button. Place and on/off are kept in every module's saved
-- table (minimapAngle, minimapButton) so that it stays when a module is switched off; the module with the lowest order leads.
---------------------------------------------------------------------------
local MINOR = 1
local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local DEFAULT_ANGLE = 200
local ROW_H = 24

local G = rawget(_G, "GuildonLauncher")
if not G or (G.minor or 0) < MINOR then
  G = G or { modules = {} }
  G.minor = MINOR
  GuildonLauncher = G
  local C = Style.COLORS

  local function Sorted()
    local list = {}
    for _, m in pairs(G.modules) do list[#list + 1] = m end
    table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
    return list
  end
  G.Sorted = Sorted

  local function Lead() return Sorted()[1] end
  local function Get(key)
    local m = Lead()
    return m and m.db and m.db[key]
  end
  -- a setting goes to every module, so that it holds whichever modules are on
  local function SetAll(key, v)
    for _, m in pairs(G.modules) do if type(m.db) == "table" then m.db[key] = v end end
  end
  G.SetAll = SetAll

  local function Shape()
    local s = ns.Call(GetMinimapShape)
    return type(s) == "string" and s or "ROUND"
  end

  local function Place()
    local button = G.button
    if not button or not Minimap then return end
    local angle = math.rad(tonumber(Get("minimapAngle")) or DEFAULT_ANGLE)
    local w = (ns.Num(ns.Call(Minimap.GetWidth, Minimap)) or 140) / 2 + 8
    local h = (ns.Num(ns.Call(Minimap.GetHeight, Minimap)) or 140) / 2 + 8
    local x, y = math.cos(angle), math.sin(angle)
    if Shape() == "SQUARE" then
      local m = math.max(math.abs(x), math.abs(y))
      if m > 0 then x, y = x / m, y / m end
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
  end

  local function Open(m)
    if m and type(m.open) == "function" then ns.SafeCall("launcher " .. m.id, m.open) end
  end

  -- the choice: one row per module, closes on a choice, a second click or a click beside it
  local function Menu()
    if G.menu then return G.menu end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:Hide()
    local menu = CreateFrame("Frame", "GuildonLauncherMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel((catcher:GetFrameLevel() or 1) + 5)
    menu:EnableMouse(true)
    local edge = menu:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    local fill = menu:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    local low = Style.BOOK and Style.BOOK.cardLow or C.background
    fill:SetColorTexture(low[1], low[2], low[3], 0.99)
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -6)
    menu.title:SetText(ns.Style.Wordmark("Guil", "don"))
    menu.rows = {}
    menu.catcher = catcher
    function menu:Close() self:Hide() catcher:Hide() end
    catcher:SetScript("OnClick", function() menu:Close() end)
    menu:Hide()
    G.menu = menu
    return menu
  end

  function G.ShowMenu()
    local menu = Menu()
    if menu:IsShown() then menu:Close() return end
    local list = Sorted()
    local w = 200
    for i, m in ipairs(list) do
      local r = menu.rows[i]
      if not r then
        r = CreateFrame("Button", nil, menu)
        r:SetHeight(ROW_H)
        r.hover = r:CreateTexture(nil, "BORDER")
        r.hover:SetAllPoints()
        r.hover:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4] or 1)
        r.hover:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r, "LEFT", 30, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r:SetScript("OnEnter", function(self) self.hover:Show() end)
        r:SetScript("OnLeave", function(self) self.hover:Hide() end)
        r:SetScript("OnClick", ns.Guard("launcher menu", function(self) menu:Close() Open(self.m) end))
        menu.rows[i] = r
      end
      r.m = m
      r.icon:SetTexture(m.icon)
      r.text:SetText(m.title)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -20 - (i - 1) * ROW_H)
      r:SetWidth(w - 6)
      r:Show()
    end
    for i = #list + 1, #menu.rows do menu.rows[i]:Hide() menu.rows[i].m = nil end
    menu:SetSize(w, 23 + #list * ROW_H + 3)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", G.button or UIParent, "BOTTOMLEFT", 8, 8)
    menu.catcher:Show()
    menu:Show()
  end

  -- a click: the only module at once, else the choice
  function G.Click()
    local list = Sorted()
    if #list == 1 then Open(list[1]) elseif #list > 1 then G.ShowMenu() end
  end

  local function Tip(self)
    local list = Sorted()
    local lines = {}
    for _, m in ipairs(list) do
      lines[#lines + 1] = "|c" .. Style.Hex("gold") .. m.title .. "|r"
      if type(m.tip) == "function" then
        local ok, extra = pcall(m.tip)
        if ok and type(extra) == "table" then for _, l in ipairs(extra) do if type(l) == "string" then lines[#lines + 1] = "  " .. l end end end
      end
    end
    Style.Tooltip(self, Style.Wordmark("Guil", "don"), lines,
      #list > 1 and L["Click: choose a part. Drag: move."] or L["Click: open the window. Drag: move."], "ANCHOR_LEFT")
  end

  local function Create()
    if G.button or not Minimap then return end
    local button = CreateFrame("Button", "GuildonMinimapButton", Minimap)
    G.button = button
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    local lvl = ns.Num(ns.Call(Minimap.GetFrameLevel, Minimap))
    if lvl and button.SetFrameLevel then button:SetFrameLevel(lvl + 8) end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(22, 22)
    bg:SetPoint("CENTER", button, "CENTER", 0, 0)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexture(ICON)
    if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(24, 24)
    hl:SetPoint("CENTER", button, "CENTER", 0, 0)
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    button:SetScript("OnClick", ns.Guard("minimap button", function(self)
      Style.HideTooltip(self)
      G.Click()
    end))
    button:SetScript("OnEnter", Tip)
    button:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
    button:SetScript("OnDragStart", function(self)
      Style.HideTooltip(self)
      if G.menu then G.menu:Close() end
      self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = ns.Num(ns.Call(Minimap.GetEffectiveScale, Minimap)) or 1
        if not (mx and cx) then return end
        local a = math.deg(math.atan2 and math.atan2(cy / scale - my, cx / scale - mx) or math.atan(cy / scale - my, cx / scale - mx))
        SetAll("minimapAngle", math.floor((a % 360) + 0.5))
        Place()
      end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    Place()
  end

  -- shown when the leading module has it on; before PLAYER_LOGIN nothing is built (the other modules sign in first)
  function G.Refresh()
    if not G.ready or not next(G.modules) then return end
    if Get("minimapButton") == false then
      if G.button then G.button:Hide() end
      if G.menu then G.menu:Close() end
      return
    end
    if not G.button then Create() end
    if G.button then Place() G.button:Show() end
  end

  function G.Register(m)
    if type(m) ~= "table" or type(m.id) ~= "string" then return false end
    m.order = tonumber(m.order) or 9
    m.title = m.title or m.id
    G.modules[m.id] = m
    if G.ready then G.Refresh() end
    return true
  end

  function G.SetShown(on)
    SetAll("minimapButton", on ~= false and true or false)
    G.Refresh()
  end
end

-- every copy: sign in this module, build the button once all are in
local mod = ns.MODULE or {}
ns.OnInit(function()
  G.Register({ id = mod.id or ns.ADDON_TITLE or "?", title = mod.title or ns.ADDON_TITLE, icon = mod.icon or ICON, order = mod.order,
    db = ns.db, open = function() if ns.ToggleWindow then ns.ToggleWindow() end end,
    tip = function() return ns.LauncherTip and ns.LauncherTip() or nil end })
end)
ns.On("PLAYER_LOGIN", function()
  G.ready = true
  ns.SafeCall("minimap button", G.Refresh)
end)

-- the module's own option "Minimap button" switches the shared one
function ns.RefreshMinimapButton() G.SetShown(ns.db.minimapButton ~= false) end
function ns.MinimapButton() return G.button end -- (tests)
