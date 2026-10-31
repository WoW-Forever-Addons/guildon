local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Main window in the quest book look (Theme.lua): a row of tabs on top, the page below. GuildShared (31.10.2026): the frame,
-- tabs, size grip and emblem; the addon sets ns.TABS, ns.TitleText(), ns.PANEL_NAME, ns.SHOW_AGAIN (the locale key of the
-- close button's third line) and registers its pages in ns.PAGE_BUILDERS[key] = function(page) ... end.
---------------------------------------------------------------------------
local PAD = Style.SPACING.padX
local WIDTH = 720
local INNER_W = WIDTH - 2 * PAD
-- tabs in one row across the top (Daniel 25.10.), the page uses the full width below them
local HOLDER_H = 420
local NAV_H = 26
local NAV_GAP = 4
local NAV_W = math.floor((INNER_W - 7 * NAV_GAP) / 8)
local PAGE_Y = -(NAV_H + 10)
local CONTENT_H = HOLDER_H + PAGE_Y
local PAGE_X = 0
local PAGE_W = INNER_W
local ROW_H = 22

local panel, holder
local PaintEmblem
local NavLayout
local nav, pages = {}, {}
local current

-- height of the content (Daniel 25.10.: dragging the grip shows more lines instead of only scaling the window)
local MIN_H, MAX_H = 360, 900
local function HolderH()
  local h = tonumber(ns.db and ns.db.panelHeight) or HOLDER_H
  return math.max(MIN_H, math.min(MAX_H, math.floor(h)))
end
function ns.ContentHeight() return HolderH() + PAGE_Y end

-- width of the window (Daniel 26.10.: "Breite auch ziehbar machen"): 720 is the minimum and what the pages are built for; wider gives
-- the lists and the tabs more room. Each page can have p.OnWidth(self, pageWidth) to place its parts.
local MIN_W, MAX_W = WIDTH, 1100
local function PanelW()
  local w = tonumber(ns.db and ns.db.panelWidth) or MIN_W
  return math.max(MIN_W, math.min(MAX_W, math.floor(w)))
end
function ns.PageWidth() return PanelW() - 2 * PAD end

local function ResizePages()
  local ch, pw = ns.ContentHeight(), ns.PageWidth()
  for _, p in pairs(pages) do
    p:SetSize(pw, ch)
    if p.OnWidth then ns.SafeCall("width", p.OnWidth, p, pw) end
    if p.OnResize then ns.SafeCall("resize", p.OnResize, p, ch) end
  end
end

-- one call for both (the grip changes width and height together): the pages are laid out once
function ns.SetPanelSize(w, h)
  if w then ns.db.panelWidth = math.max(MIN_W, math.min(MAX_W, math.floor(w))) end
  if h then ns.db.panelHeight = math.max(MIN_H, math.min(MAX_H, math.floor(h))) end
  if panel and holder then
    if w then panel:SetPanelWidth(PanelW()) NavLayout() end
    if h then Style.Content(panel, holder, HolderH()) end
    ResizePages()
  end
end
function ns.SetPanelHeight(h) ns.SetPanelSize(nil, h) end

local function Color(fs, c)
  c = type(c) == "string" and (C[c] or Style.BOOK[c]) or c
  fs:SetTextColor(c[1], c[2], c[3])
end

local function Text(parent, font, x, y, w, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if w then fs:SetWidth(w) end
  fs:SetJustifyH("LEFT")
  Color(fs, color or "textPrimary")
  return fs
end

local FlatButton = ns.UI.FlatButton
local UI = ns.UI

ns.PAGE_W, ns.CONTENT_H, ns.ROW_H = PAGE_W, CONTENT_H, ROW_H
ns.UI.Text = Text
ns.PAGE_BUILDERS = ns.PAGE_BUILDERS or {}
function ns.GetPanel() return panel end

local function AgeText(stamp)
  local age = math.max(0, time() - (stamp or 0))
  if age < 3600 then return L["%d min ago"]:format(math.floor(age / 60)) end
  if age < 86400 then return L["%d h ago"]:format(math.floor(age / 3600)) end
  return L["%d days ago"]:format(math.floor(age / 86400))
end
ns.UI.AgeText = AgeText

local function BuildLater(p, tab)
  local t = Text(p, "GameFontNormalLarge", 0, 0, PAGE_W, "gold")
  t:SetText(L[tab.title])
  local s = Text(p, "GameFontHighlight", 0, -32, PAGE_W, "textSecondary")
  s:SetText(L["Coming in a later version of %s."]:format(ns.ADDON_TITLE or ""))
end

local function Page(key)
  if pages[key] then return pages[key] end
  local tab
  for _, t in ipairs(ns.TABS) do if t.key == key then tab = t end end
  if not tab then return nil end
  local p = CreateFrame("Frame", nil, holder)
  p:SetSize(PAGE_W, CONTENT_H)
  p:SetPoint("TOPLEFT", holder, "TOPLEFT", PAGE_X, PAGE_Y)
  p:Hide()
  local build = ns.PAGE_BUILDERS[key]
  if build then build(p) else BuildLater(p, tab) end
  pages[key] = p
  -- the pages are built for the minimum size; a taller or wider window is applied afterwards
  if ns.PageWidth() ~= PAGE_W then
    p:SetSize(ns.PageWidth(), CONTENT_H)
    if p.OnWidth then ns.SafeCall("width", p.OnWidth, p, ns.PageWidth()) end
  end
  if ns.ContentHeight() ~= CONTENT_H then
    p:SetSize(ns.PageWidth(), ns.ContentHeight())
    if p.OnResize then ns.SafeCall("resize", p.OnResize, p, ns.ContentHeight()) end
  end
  return p
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------
local function PaintNav()
  for _, b in ipairs(nav) do b:SetLook(b.key == current and "active" or "normal") end
end

-- (Daniel 26.10.: "kann man die UI nach vorne holen, wenn sie über Questdon liegt?") the window comes to the front of its strata
-- (Questdon's tracker panel is in the same one) when it opens and when a tab is chosen; a click inside it does the same (SetToplevel)
local function Front()
  if panel and panel.Raise then panel:Raise() end
end

local function TabShown(key)
  for _, t in ipairs(ns.TABS) do
    if t.key == key then return not t.optional or ns.db[t.optional] == true end
  end
  return false
end

local function Select(key)
  if not TabShown(key) or not Page(key) then key = "overview" end
  Front()
  current = key
  ns.db.tab = key
  for k, p in pairs(pages) do if k ~= key then p:Hide() end end
  local p = Page(key)
  p:Show()
  if p.Refresh then p:Refresh() end
  PaintNav()
end

-- the shown tabs share the width of the page (an optional tab that is off is hidden)
function NavLayout()
  local shown = {}
  for _, b in ipairs(nav) do
    if TabShown(b.key) then shown[#shown + 1] = b b:Show() else b:Hide() end
  end
  local n = math.max(1, #shown)
  local w = math.floor((ns.PageWidth() - (n - 1) * NAV_GAP) / n)
  for i, b in ipairs(shown) do
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (w + NAV_GAP), 0)
  end
end

-- switching an optional tab on or off (Options)
function ns.RefreshTabs()
  if not panel then return end
  NavLayout()
  if current and not TabShown(current) then Select("overview") end
end

local function NavButton(tab, i)
  local b = UI.FlatButton(holder, NAV_W, NAV_H, L[tab.title])
  b:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (NAV_W + NAV_GAP), 0)
  b.key, b.later = tab.key, tab.later
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", b, "LEFT", 5, 0)
  b.icon:SetTexture(tab.icon)
  b.label:ClearAllPoints()
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", -2, 0)
  b.label:SetJustifyH("LEFT")
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end
  b:SetTip(function() if b.label.IsTruncated and b.label:IsTruncated() then return L[tab.title] end end)
  b:SetScript("OnClick", ns.Guard("tab", function(self) Select(self.key) end))
  return b
end

local function Build()
  panel = Style.Panel(ns.PANEL_NAME, UIParent, {
    title = ns.TitleText(),
    width = PanelW(),
    look = "book",
    close = true,
    collapse = false,
    get = ns.PanelGet("panel"),
    set = ns.PanelSet("panel"),
    defaultPoint = { "CENTER", "CENTER", 0, 20 },
    closeTooltip = { L["Hide window"], nil, L[ns.SHOW_AGAIN] },
  })
  if panel.SetToplevel then panel:SetToplevel(true) end
  holder = CreateFrame("Frame", nil, UIParent)
  Style.Content(panel, holder, HolderH())
  local back = holder:CreateTexture(nil, "BACKGROUND", nil, -2)
  back:SetAllPoints(holder)
  back:SetColorTexture(C.background[1], C.background[2], C.background[3], 0.88) -- the world must not shine through (layout review 25.10.)
  for i, tab in ipairs(ns.TABS) do nav[i] = NavButton(tab, i) end
  NavLayout()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, ns.PANEL_NAME) end
  -- size grip at the bottom right (Daniel 25.10.): dragging makes the window taller or shorter, the lists show more
  -- or fewer lines; with Shift it scales the whole window as before. The top left corner stays where it is.
  local grip = CreateFrame("Button", nil, panel)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:EnableMouse(true)
  grip:SetScript("OnEnter", function(self) Style.Tooltip(self, L["Window size"], { L["Drag: wider or narrower, more or fewer lines."], L["Shift and drag: make everything bigger or smaller."] }) end)
  grip:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  local function Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
  end
  grip:SetScript("OnMouseDown", function(self)
    if ns.db.panelLocked then return end
    local s0 = panel._scale or panel:GetScale() or 1
    local l, t = panel:GetLeft(), panel:GetTop()
    if not (l and t) then return end
    local cx, cy = Cursor()
    local scaleMode = IsShiftKeyDown and IsShiftKeyDown() and true or false
    self._drag = { s0 = s0, left = l * s0, top = t * s0, x = cx, y = cy, w = panel:GetWidth() * s0, h0 = HolderH(), w0 = PanelW(), scaleMode = scaleMode }
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    self:SetScript("OnUpdate", function()
      local d = self._drag
      if not d then return end
      local nx, ny = Cursor()
      if d.scaleMode then
        local s = math.max(Style.SCALE_MIN, math.min(Style.SCALE_MAX, d.s0 * (d.w + nx - d.x) / d.w))
        s = math.floor(s * 100 + 0.5) / 100
        if s ~= panel._scale then
          panel:SetPanelScale(s)
          panel:ClearAllPoints()
          panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left / s, d.top / s)
        end
      else
        local h = math.floor(d.h0 + (d.y - ny) / d.s0 + 0.5)
        h = math.max(MIN_H, math.min(MAX_H, h))
        -- wider only as far as the screen reaches from the window's left edge
        local w = math.floor(d.w0 + (nx - d.x) / d.s0 + 0.5)
        local screen = UIParent.GetWidth and tonumber(UIParent:GetWidth())
        if screen and screen > 0 then w = math.min(w, math.floor((screen - d.left) / d.s0)) end
        w = math.max(MIN_W, math.min(MAX_W, w))
        if w ~= PanelW() or h ~= HolderH() then ns.SetPanelSize(w ~= PanelW() and w or nil, h ~= HolderH() and h or nil) end
      end
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    local d = self._drag
    self._drag = nil
    if d then
      local s = panel._scale or d.s0
      ns.db.panel.pos = { "TOPLEFT", "BOTTOMLEFT", math.floor(d.left / s + 0.5), math.floor(d.top / s + 0.5) }
    end
  end)
  panel.grip = grip
  if panel.SetGrip then panel:SetGrip(grip) end -- its own space under the content
  Select(ns.db.tab)
  PaintEmblem()
end

-- the guild's emblem left of the close button (Forever; Era has none)
function PaintEmblem()
  if not panel then return end
  -- (an "a and f()" would keep only the first value: no colours, and the game refuses SetVertexColor(nil))
  local file, r, g, b, br, bgc, bb
  if ns.GuildEmblem then file, r, g, b, br, bgc, bb = ns.GuildEmblem() end
  if not file then if panel.emblem then panel.emblem:Hide() end return end
  if not panel.emblem then
    local f = CreateFrame("Frame", nil, panel)
    -- (Daniel 26.10.: "das Wappen sitzt schlecht") as high as the header and centred on the close button's line, not hanging
    -- below the header; the header is 20 high, the emblem 18 so that it touches neither edge
    f:SetSize(18, 18)
    local close = panel.GetButton and panel:GetButton("close")
    if close then f:SetPoint("RIGHT", close, "LEFT", -6, 0) else f:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, 0) end
    f:SetFrameLevel((panel:GetFrameLevel() or 1) + 5)
    f.bg = f:CreateTexture(nil, "ARTWORK")
    f.bg:SetAllPoints()
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    panel.emblem = f
  end
  local f = panel.emblem
  f.tex:SetTexture(file)
  f.tex:SetVertexColor(r, g, b)
  if br then f.bg:SetColorTexture(br, bgc, bb, 0.9) f.bg:Show() else f.bg:Hide() end
  f:Show()
end

function ns.Refresh()
  if not panel then return end
  panel:SetTitle(ns.TitleText())
  PaintEmblem()
  local p = current and pages[current]
  if p and p:IsShown() and p.Refresh then p:Refresh() end
end

function ns.ToggleWindow()
  if (not panel or not panel:IsShown()) and ns.ReadKnown then ns.ReadKnown() end -- Era: the recipes the character knows, without the profession window
  if not panel then Build() panel:FadeIn() Front() ns.RequestRoster() return end
  if panel:IsShown() then panel:FadeOut() else panel:FadeIn() Front() ns.RequestRoster() ns.Refresh() end
end

function ns.OpenTab(key)
  if ns.ReadKnown and (not panel or not panel:IsShown()) then ns.ReadKnown() end
  if not panel then Build() end
  if not panel:IsShown() then panel:FadeIn() end
  Front()
  Select(key)
  ns.RequestRoster()
end

function ns.WindowState() return panel, current, pages, nav end -- (tests)
function ns.WindowOpen() return panel ~= nil and panel:IsShown() end

-- roster or data changed: repaint the open page (once per half second at most)
local queued = false
local function Later()
  if queued or not panel or not panel:IsShown() then return end
  queued = true
  ns.After(0.5, function() queued = false ns.Refresh() end)
end
ns.OnRosterChanged = Later
ns.OnDataChanged = Later

-- while the window is open, the roster is asked for every 60 s (online states)
ns.OnInit(function()
  ns.NewTicker(60, function() if panel and panel:IsShown() then ns.RequestRoster() end end)
end)