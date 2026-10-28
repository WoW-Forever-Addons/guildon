local _, ns = ...
local L = ns.L
local Style = ns.Style
local C, B, PAL = Style.COLORS, Style.BOOK, Style.PAL

---------------------------------------------------------------------------
-- The shared widgets of every Guildon window (Daniel 26.10.: "alles die gleiche Style, die Haken konsistent"): button,
-- check box, status chip, tick, status dot, box with a thin line. Pages build their controls only from these, so that a
-- change here changes the whole addon. Own frames and textures only.
---------------------------------------------------------------------------
ns.UI = ns.UI or {}
local UI = ns.UI
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local DOT_ON = "Interface\\FriendsFrame\\StatusIcon-Online"
local DOT_OFF = "Interface\\FriendsFrame\\StatusIcon-Offline"

local function Tint(tex, c, alpha)
  tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end
UI.Tint = Tint

function UI.Color(fs, c)
  c = type(c) == "string" and (C[c] or B[c] or PAL[c]) or c
  fs:SetTextColor(c[1], c[2], c[3])
end
local Color = UI.Color

-- a 1 px line and a dark inside as textures of the frame itself (so that its own texts stay above them);
-- f.edge is the line, f.fill the inside, f:Paint(edge, fill) changes both
function UI.Skin(f, edge, fill)
  f.edge = f:CreateTexture(nil, "BACKGROUND")
  f.edge:SetAllPoints()
  f.fill = f:CreateTexture(nil, "BORDER")
  f.fill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  function f:Paint(e, fl)
    Tint(self.edge, e or PAL.edge)
    Tint(self.fill, fl or PAL.well)
  end
  f:Paint(edge, fill)
  return f
end

-- a new frame with that skin
function UI.Box(parent, edge, fill)
  return UI.Skin(CreateFrame("Frame", nil, parent), edge, fill)
end

---------------------------------------------------------------------------
-- Tick and dot as text (for list rows): one tick everywhere, green for "yes", grey for "only offline"
---------------------------------------------------------------------------
local TICK = { good = { 102, 204, 115 }, dim = { 140, 146, 158 } }
function UI.Tick(size, kind)
  local c = TICK[kind or "good"] or TICK.good
  size = size or 14
  return ("|T%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(CHECK, size, size, c[1], c[2], c[3])
end

function UI.Dot(on, size)
  return ("|T%s:%d:%d|t"):format(on and DOT_ON or DOT_OFF, size or 12, size or 12)
end

---------------------------------------------------------------------------
-- Button. b.edge, b.fill, b.label as before. b:SetLook("active") paints it blue (chosen), "normal" back.
-- b:SetTip(title, lines, hint) shows a tooltip on mouse over (title may be a function returning title, lines, hint).
---------------------------------------------------------------------------
local function PaintButton(b)
  local active, hot = b.look == "active", b.hot
  if active then
    Tint(b.edge, PAL.blue, hot and 1 or 0.9)
    Tint(b.fill, PAL.blue, hot and 0.50 or 0.40)
  else
    Tint(b.edge, (hot or b.strong) and PAL.edgeHot or PAL.edge)
    Tint(b.fill, hot and PAL.btnHot or PAL.btn)
  end
  if b.label and not b.keepColor then
    Color(b.label, active and "textPrimary" or (hot and "goldLight" or "textPrimary"))
  end
end

function UI.FlatButton(parent, w, h, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetAllPoints()
  b.fill = b:CreateTexture(nil, "BORDER")
  b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER")
  b.label:SetText(label or "")
  b.look = "normal"
  function b:SetLook(look)
    self.look = look
    PaintButton(self)
  end
  function b:SetTip(title, lines, hint) self._tip = { title, lines, hint } end
  b:SetScript("OnEnter", function(self)
    self.hot = true
    PaintButton(self)
    local t = self._tip
    if t then
      if type(t[1]) == "function" then
        local title, lines, hint = t[1]()
        if title then Style.Tooltip(self, title, lines, hint) end
      else
        Style.Tooltip(self, t[1], t[2], t[3])
      end
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.hot = false
    PaintButton(self)
    if self._tip then Style.HideTooltip(self) end
  end)
  PaintButton(b)
  return b
end

---------------------------------------------------------------------------
-- Check box, one look for every on/off switch and every "choose one" row (Options, Map, Profitable, Want, wish form).
-- get() -> boolean, set(boolean); b:Sync() repaints from get(). opts.w, opts.h, opts.font.
---------------------------------------------------------------------------
function UI.CheckBox(parent, label, get, set, opts)
  opts = opts or {}
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(opts.w or 200, opts.h or 20)
  b.box = UI.Box(b, PAL.edgeHot, PAL.well)
  b.box:SetSize(14, 14)
  b.box:SetPoint("LEFT", b, "LEFT", 0, 0)
  -- (Daniel 26.10.: "bei den Optionen fehlt überall der goldene gelbe Haken") the tick is a texture of the box itself: a texture of the
  -- button would lie below the box, which is a child frame. Untinted, the game's own check is gold yellow.
  b.tick = b.box:CreateTexture(nil, "OVERLAY")
  b.tick:SetTexture(CHECK)
  b.tick:SetSize(22, 22)
  b.tick:SetPoint("CENTER", b.box, "CENTER", 0, 0)
  b.label = b:CreateFontString(nil, "OVERLAY", opts.font or "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", b.box, "RIGHT", 6, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.label:SetJustifyH("LEFT")
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end
  b.label:SetText(label or "")
  function b:Sync()
    local on = get() and true or false
    self.on = on
    self.tick:SetShown(on)
    self.box:Paint(on and PAL.edgeHot or PAL.edge, PAL.well)
    Color(self.label, self.hot and "goldLight" or "textPrimary")
  end
  function b:SetTip(title, lines, hint) self._tip = { title, lines, hint } end
  b:SetScript("OnClick", ns.Guard("check box", function(self)
    if self.disabled then return end
    set(not get())
    self:Sync()
  end))
  b:SetScript("OnEnter", function(self)
    self.hot = true
    self:Sync()
    local t = self._tip
    if t then Style.Tooltip(self, t[1], t[2], t[3]) end
  end)
  b:SetScript("OnLeave", function(self)
    self.hot = false
    self:Sync()
    if self._tip then Style.HideTooltip(self) end
  end)
  b:Sync()
  return b
end

---------------------------------------------------------------------------
-- Slider (Daniel 26.10.: pin sizes "dass jeder die selber skalieren kann"): label, a thin track with a gold fill and a
-- handle, the value on the right. Click or drag on the track, mouse wheel steps. opts = { w, labelW, min, max, step,
-- get, set, format }; s:Sync() reads get() again.
---------------------------------------------------------------------------
function UI.Slider(parent, label, opts)
  local min, max, step = opts.min or 0, opts.max or 1, opts.step or 0.05
  local fmt = opts.format or function(v) return ("%d %%"):format(math.floor(v * 100 + 0.5)) end
  local s = CreateFrame("Button", nil, parent)
  s:SetSize(opts.w or 300, 20)
  local lw = opts.labelW or 130
  s.label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.label:SetPoint("LEFT", s, "LEFT", 0, 0)
  s.label:SetWidth(lw)
  s.label:SetJustifyH("LEFT")
  if s.label.SetWordWrap then s.label:SetWordWrap(false) end
  s.label:SetText(label or "")
  Color(s.label, "textPrimary")
  s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  s.value:SetPoint("RIGHT", s, "RIGHT", 0, 0)
  s.value:SetWidth(44)
  s.value:SetJustifyH("RIGHT")
  s.track = UI.Box(s, PAL.edge, PAL.well)
  s.track:SetHeight(6)
  s.track:SetPoint("LEFT", s, "LEFT", lw + 6, 0)
  s.track:SetPoint("RIGHT", s, "RIGHT", -50, 0)
  s.bar = s.track:CreateTexture(nil, "ARTWORK")
  s.bar:SetPoint("TOPLEFT", s.track, "TOPLEFT", 1, -1)
  s.bar:SetPoint("BOTTOMLEFT", s.track, "BOTTOMLEFT", 1, 1)
  Tint(s.bar, PAL.edgeHot, 0.55)
  s.knob = UI.Box(s.track, PAL.edgeHot, PAL.btnHot)
  s.knob:SetSize(8, 14)
  local function Clamp(v)
    v = math.floor((v - min) / step + 0.5) * step + min
    return math.max(min, math.min(max, v))
  end
  function s:Sync()
    local v = Clamp(tonumber(opts.get()) or min)
    self.v = v
    local w = (self.track:GetWidth() or 0) - 2
    if w <= 0 then w = (opts.w or 300) - lw - 58 end
    local x = (v - min) / (max - min) * w
    self.bar:SetWidth(math.max(0.01, x))
    self.knob:ClearAllPoints()
    self.knob:SetPoint("CENTER", self.track, "LEFT", x + 1, 0)
    self.value:SetText(fmt(v))
    Color(self.value, self.hot and "goldLight" or "textSecondary")
  end
  local function Put(self, v)
    v = Clamp(v)
    if v ~= self.v then opts.set(v) end
    self:Sync()
  end
  function s:SetTo(v) Put(self, v) end -- (tests, and code that sets a value)
  -- the cursor's place on the track as a value
  local function FromCursor(self)
    local left, w = self.track:GetLeft(), self.track:GetWidth()
    local cx = GetCursorPosition and GetCursorPosition()
    local sc = self.track.GetEffectiveScale and self.track:GetEffectiveScale() or 1
    if not (left and w and w > 0 and cx) then return end
    return min + (cx / sc - left) / w * (max - min)
  end
  s:SetScript("OnMouseDown", ns.Guard("slider", function(self)
    self.drag = true
    local v = FromCursor(self)
    if v then Put(self, v) end
  end))
  s:SetScript("OnMouseUp", function(self) self.drag = nil end)
  s:SetScript("OnUpdate", function(self)
    if not self.drag then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.drag = nil return end
    local v = FromCursor(self)
    if v then Put(self, v) end
  end)
  if s.EnableMouseWheel then s:EnableMouseWheel(true) end
  s:SetScript("OnMouseWheel", ns.Guard("slider", function(self, d) Put(self, (self.v or min) + (d > 0 and step or -step)) end))
  function s:SetTip(title, lines, hint) self._tip = { title, lines, hint } end
  s:SetScript("OnEnter", function(self)
    self.hot = true
    self:Sync()
    local t = self._tip
    if t then Style.Tooltip(self, t[1], t[2], t[3]) end
  end)
  s:SetScript("OnLeave", function(self)
    self.hot = false
    self:Sync()
    if self._tip then Style.HideTooltip(self) end
  end)
  s:Sync()
  return s
end

---------------------------------------------------------------------------
-- Status chip: a small coloured label (wish states). c:Set(text, kind), kind = a key of CHIP.
---------------------------------------------------------------------------
local CHIP = {
  open     = { 0.33, 0.43, 0.58 },
  accepted = { 0.80, 0.52, 0.10 },
  crafted  = { 0.22, 0.58, 0.30 },
  sent     = { 0.20, 0.50, 0.82 },
  done     = { 0.40, 0.42, 0.47 },
  bad      = { 0.72, 0.28, 0.25 },
}
UI.CHIP = CHIP
function UI.Chip(parent, h)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(56, h or 16)
  c.fill = c:CreateTexture(nil, "BACKGROUND")
  c.fill:SetAllPoints()
  c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.text:SetPoint("CENTER")
  c.text:SetTextColor(1, 1, 1)
  function c:Set(text, kind)
    local col = CHIP[kind] or CHIP.open
    Tint(self.fill, col, 0.92)
    self.text:SetText(text or "")
    local w = self.text.GetStringWidth and self.text:GetStringWidth()
    self:SetWidth(math.max(40, (tonumber(w) or 36) + 14))
  end
  return c
end

-- the same chip as text for list rows (a list row has no room for a frame)
function UI.ChipText(text, kind)
  local col = CHIP[kind] or CHIP.open
  return ("|cff%02x%02x%02x[%s]|r"):format(math.floor(col[1] * 255 + 0.5), math.floor(col[2] * 255 + 0.5), math.floor(col[3] * 255 + 0.5), text)
end

-- a section title with a thin line under it (Options, detail panels)
function UI.SectionTitle(parent, text, x, y, w)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  Color(fs, "gold")
  fs:SetText(text)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
  line:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + (w or 100), y - 16)
  Tint(line, PAL.edge, 0.35)
  return fs, line
end

-- a thin line (detail panels)
function UI.Line(parent)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  Tint(line, PAL.edge, 0.35)
  return line
end

---------------------------------------------------------------------------
-- Input field: line and dark inside like the other controls, a hint while empty, a small x that empties a text field,
-- Tab to the next field (e.nextField / e.prevField). opts.numeric, opts.maxLetters, opts.onChange(e).
---------------------------------------------------------------------------
function UI.EditBox(parent, w, hint, opts)
  opts = opts or {}
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, 22)
  e:SetAutoFocus(false)
  e:SetFontObject(GameFontHighlightSmall)
  e:SetTextInsets(6, opts.numeric and 6 or 22, 0, 0)
  e.edge = e:CreateTexture(nil, "BACKGROUND")
  e.edge:SetAllPoints()
  e.fill = e:CreateTexture(nil, "BORDER")
  e.fill:SetPoint("TOPLEFT", e, "TOPLEFT", 1, -1)
  e.fill:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -1, 1)
  Tint(e.edge, PAL.edge)
  Tint(e.fill, PAL.well)
  if opts.numeric then e:SetNumeric(true) end
  if opts.maxLetters or opts.numeric then e:SetMaxLetters(opts.maxLetters or 3) end
  e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  e.hint:SetPoint("LEFT", e, "LEFT", 6, 0)
  e.hint:SetText(hint or "")
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusGained", function(self) Tint(self.edge, PAL.blue, 0.9) end)
  e:SetScript("OnEditFocusLost", function(self) Tint(self.edge, PAL.edge) end)
  -- Tab jumps to the next field, Shift+Tab back
  e:SetScript("OnTabPressed", function(self)
    local back = IsShiftKeyDown and IsShiftKeyDown()
    local to = back and self.prevField or self.nextField
    if to then to:SetFocus() if to.HighlightText then to:HighlightText() end end
  end)
  if not opts.numeric then
    local x = CreateFrame("Button", nil, e)
    x:SetSize(14, 14)
    x:SetPoint("RIGHT", e, "RIGHT", -4, 0)
    x.tex = x:CreateTexture(nil, "ARTWORK")
    x.tex:SetAllPoints()
    x.tex:SetTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    x.tex:SetAlpha(0.6)
    x:SetScript("OnEnter", function(self) self.tex:SetAlpha(1) end)
    x:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.6) end)
    x:SetScript("OnClick", ns.Guard("clear field", function()
      e:SetText("")
      e:ClearFocus()
      e._changed(e)
    end))
    x:Hide()
    e.clear = x
  end
  local function Changed(self)
    local t = self:GetText() or ""
    self.hint:SetShown(t == "")
    if self.clear then self.clear:SetShown(t ~= "") end
    if opts.onChange then opts.onChange(self) end
  end
  e:SetScript("OnTextChanged", ns.Guard("edit box", Changed))
  e._changed = Changed
  return e
end

-- empty a field without waiting for the game's text event (tests and page changes)
function UI.ClearField(e)
  if not e then return end
  e:SetText("")
  if e.hint then e.hint:Show() end
  if e.clear then e.clear:Hide() end
  if e.ClearFocus then e:ClearFocus() end
end
