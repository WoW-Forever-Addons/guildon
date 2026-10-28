local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Minimap button (like Dropdon's): left click opens the window, right click the wish list, drag moves it around
-- the minimap. The tooltip says how many open wishes the player could craft.
---------------------------------------------------------------------------
local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local DEFAULT_ANGLE = 200
local button

local function Shape()
  local s = ns.Call(GetMinimapShape)
  return type(s) == "string" and s or "ROUND"
end

local function Place()
  if not button or not Minimap then return end
  local angle = math.rad(tonumber(ns.db.minimapAngle) or DEFAULT_ANGLE)
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

local function Create()
  if button or not Minimap then return end
  button = CreateFrame("Button", "GuildonMinimapButton", Minimap)
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
  button:SetScript("OnClick", ns.Guard("minimap button", function(self, which)
    Style.HideTooltip(self)
    if which == "RightButton" then ns.OpenTab("wishes") else ns.ToggleWindow() end
  end))
  button:SetScript("OnEnter", function(self)
    local n = ns.OpenWishesForMe and ns.OpenWishesForMe() or 0
    Style.Tooltip(self, ns.WORDMARK, n > 0 and { L["Open wishes you can craft: %d"]:format(n) } or nil,
      L["Left click: window. Right click: wish list. Drag: move."], "ANCHOR_LEFT")
  end)
  button:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  button:SetScript("OnDragStart", function(self)
    Style.HideTooltip(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = ns.Num(ns.Call(Minimap.GetEffectiveScale, Minimap)) or 1
      if not (mx and cx) then return end
      local a = math.deg(math.atan2 and math.atan2(cy / scale - my, cx / scale - mx) or math.atan(cy / scale - my, cx / scale - mx))
      ns.db.minimapAngle = math.floor((a % 360) + 0.5)
      Place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  Place()
end

function ns.RefreshMinimapButton()
  if ns.db.minimapButton == false then
    if button then button:Hide() end
    return
  end
  if not button then Create() end
  if button then Place() button:Show() end
end

function ns.MinimapButton() return button end -- (tests)

ns.OnInit(function() ns.SafeCall("minimap button", ns.RefreshMinimapButton) end)
