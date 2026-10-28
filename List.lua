local _, ns = ...
local Style = ns.Style
local C = Style.COLORS
local WHITE = "Interface\\Buttons\\WHITE8x8"
local METER_W = 90
local PAL = Style.PAL

---------------------------------------------------------------------------
-- A small scrolling list of fixed rows (own frames, mouse wheel, no Blizzard
-- templates). Entries: { key, text, value, valueColor, color, header, topLine, tooltip }.
-- header entries are section titles and cannot be clicked. topLine draws a thin divider line at the top of the row.
-- Wider window (list:SetWidth): what sits at the right edge (value, meter, chip) follows by itself. opts.growText = true gives the
-- extra width to the first text (its right edge and the columns move right); a column { x, w, justify, "grow" } gets wider instead.
---------------------------------------------------------------------------
local function Tint(tex, c, alpha)
  c = type(c) == "string" and C[c] or c or C.textPrimary
  tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function SetFontColor(fs, c)
  if type(c) == "string" then c = C[c] or (Style.BOOK and Style.BOOK[c]) or C.textPrimary end
  c = c or C.textPrimary
  if c.r then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(c[1], c[2], c[3]) end
end

function ns.NewList(parent, opts)
  local list = { rowH = opts.rowHeight or 22, w = opts.width, h = opts.height, offset = 0, data = {}, rows = {},
    selected = nil, onSelect = opts.onSelect, textRight = opts.textRight, meterW = opts.meterWidth or METER_W, twoLine = opts.twoLine,
    iconSize = opts.twoLine and 28 or 16, baseW = opts.width, baseTextRight = opts.textRight, growText = opts.growText }
  local nVis = math.max(1, math.floor(list.h / list.rowH))
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(list.w, list.h)
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, opts.y or 0)
  frame:EnableMouseWheel(true)
  list.frame = frame

  local thumb = frame:CreateTexture(nil, "OVERLAY")
  thumb:SetWidth(3)
  Tint(thumb, "textHint", 0.5)
  thumb:Hide()

  local function MaxOffset() return math.max(0, #list.data - nVis) end

  local function Paint(row, entry)
    row.entry = entry
    if not entry then row:Hide() return end
    row:Show()
    row.line:SetShown(entry.topLine and true or false)
    row.text:SetText(entry.text or "")
    if entry.header then
      for c, fs in ipairs(row.cols) do fs:SetText(entry.cols and entry.cols[c] or "") end
      row.meterBg:Hide()
      row.meterFill:Hide()
      row.text:SetFontObject(GameFontNormalSmall)
      SetFontColor(row.text, entry.color or "gold")
      row.value:SetText("")
      row.active:Hide()
      row.bar:Hide()
      row.icon:Hide()
      row.sub:Hide()
      if row.chip then row.chip:Hide() end
      row:EnableMouse(false)
      return
    end
    row:EnableMouse(true)
    for c, fs in ipairs(row.cols) do fs:SetText(entry.cols and entry.cols[c] or "") end
    -- icon at the left, second line, status chip at the right (wish list rows)
    local left = 8
    row.icon:SetShown(entry.icon ~= nil)
    if entry.icon then
      row.icon:SetTexture(entry.icon)
      left = 8 + list.iconSize + 6
    end
    row.sub:SetText(entry.sub or "")
    row.sub:SetShown(entry.sub ~= nil)
    SetFontColor(row.sub, entry.subColor or "textSecondary")
    if row.chip then row.chip:SetShown(entry.chip ~= nil) end
    if entry.chip then
      if not row.chip then
        row.chip = ns.UI.Chip(row, 16)
        row.chip:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      end
      row.chip:Set(entry.chip[1], entry.chip[2])
      row.chip:Show()
    end
    -- a small bar right (skill of a member, Daniel's layout review 25.10.): entry.meter = { current, max, color }
    local m = entry.meter
    row.meterBg:SetShown(m ~= nil)
    row.meterFill:SetShown(m ~= nil)
    row.value:ClearAllPoints()
    row.text:ClearAllPoints()
    if entry.sub then
      row.text:SetPoint("TOPLEFT", row, "TOPLEFT", left, -4)
      row.sub:ClearAllPoints()
      row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", left, -19)
      row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    else
      row.text:SetPoint("LEFT", row, "LEFT", left, 0)
    end
    if entry.chip then
      row.text:SetPoint("RIGHT", row.chip, "LEFT", -6, 0)
    elseif m then
      local f = (m[2] or 0) > 0 and math.max(0.02, math.min(1, (m[1] or 0) / m[2])) or 0.02
      row.meterFill:SetWidth((list.meterW - 2) * f)
      Tint(row.meterFill, m[3] or PAL.amber, 0.9)
      row.value:SetPoint("CENTER", row.meterBg, "CENTER", 0, 0)
      if list.textRight then row.text:SetPoint("RIGHT", row, "LEFT", list.textRight, 0)
      else row.text:SetPoint("RIGHT", row.meterBg, "LEFT", -8, 0) end
    else
      row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      if list.textRight then row.text:SetPoint("RIGHT", row, "LEFT", list.textRight, 0)
      else row.text:SetPoint("RIGHT", row.value, "LEFT", -6, 0) end
    end
    row.text:SetFontObject(GameFontHighlightSmall)
    SetFontColor(row.text, entry.color or "textPrimary")
    row.value:SetText(entry.value or "")
    SetFontColor(row.value, entry.valueColor or "textSecondary")
    local on = entry.key ~= nil and entry.key == list.selected
    row.active:SetShown(on)
    row.bar:SetShown(on)
  end

  function list:Refresh()
    self.offset = math.max(0, math.min(self.offset, MaxOffset()))
    for i = 1, nVis do Paint(self.rows[i], self.data[self.offset + i]) end
    if #self.data > nVis then
      local frac = nVis / #self.data
      local th = math.max(12, self.h * frac)
      local travel = self.h - th
      local pos = MaxOffset() > 0 and (self.offset / MaxOffset()) or 0
      thumb:ClearAllPoints()
      thumb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -travel * pos)
      thumb:SetHeight(th)
      thumb:Show()
    else
      thumb:Hide()
    end
  end

  local function PlaceCols(row)
    local dw = list.w - list.baseW
    for c, col in ipairs(opts.columns or {}) do
      local fs = row.cols[c]
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", col[1] + (list.growText and dw or 0), 0)
      fs:SetWidth(col[2] + (col[4] == "grow" and dw or 0))
    end
  end

  local function MakeRow(i)
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(list.w - 6, list.rowH)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * list.rowH)
    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    Tint(hover, C.rowHover)
    hover:Hide()
    row.hover = hover
    local active = row:CreateTexture(nil, "BACKGROUND")
    active:SetAllPoints()
    Tint(active, C.rowActive)
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(2)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    Tint(bar, PAL.blue)
    row.active, row.bar = active, bar
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(list.iconSize, list.iconSize)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:Hide()
    row.icon = icon
    local sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetJustifyH("LEFT")
    if sub.SetWordWrap then sub:SetWordWrap(false) end
    sub:Hide()
    row.sub = sub
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", row, "TOPLEFT", 6, 0)
    line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, 0)
    Tint(line, Style.BOOK and Style.BOOK.gold or "textHint", 0.22) -- thin gold divider (layout review 25.10.)
    line:Hide()
    row.line = line
    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    value:SetJustifyH("RIGHT")
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", row, "LEFT", 8, 0)
    text:SetPoint("RIGHT", value, "LEFT", -6, 0)
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    row.text, row.value = text, value
    local meterBg = row:CreateTexture(nil, "ARTWORK")
    meterBg:SetSize(list.meterW, 14)
    meterBg:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    Tint(meterBg, PAL.well, 0.9)
    meterBg:Hide()
    local meterFill = row:CreateTexture(nil, "ARTWORK", nil, 1)
    meterFill:SetHeight(12)
    meterFill:SetPoint("LEFT", meterBg, "LEFT", 1, 0)
    meterFill:Hide()
    row.meterBg, row.meterFill = meterBg, meterFill
    -- extra columns (opts.columns = { { x, w, justify }, ... }, entry.cols = { text, ... }), right of the text
    row.cols = {}
    for c, col in ipairs(opts.columns or {}) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetJustifyH(col[3] or "RIGHT")
      if fs.SetWordWrap then fs:SetWordWrap(false) end
      row.cols[c] = fs
    end
    PlaceCols(row)
    row:SetScript("OnEnter", function(self)
      if not self.entry or self.entry.header then return end
      self.hover:Show()
      local e = self.entry
      local truncated = self.text.IsTruncated and self.text:IsTruncated()
      if e.tooltip then
        local title, lines, hint = e.tooltip(e)
        Style.Tooltip(self, title, lines, hint)
      elseif truncated then
        Style.Tooltip(self, e.text)
      end
    end)
    row:SetScript("OnLeave", function(self)
      self.hover:Hide()
      Style.HideTooltip(self)
    end)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnClick", function(self, button)
      local e = self.entry
      if not e or e.header or e.key == nil then return end
      if list.onSelect then ns.SafeCall("list select", list.onSelect, e, button) end
    end)
    list.rows[i] = row
  end

  for i = 1, nVis do MakeRow(i) end

  frame:SetScript("OnMouseWheel", function(_, delta)
    list.offset = list.offset - delta * 3
    list:Refresh()
  end)

  function list:SetHeight(h)
    h = math.max(self.rowH, math.floor(h))
    if h == self.h then return end
    self.h = h
    frame:SetHeight(h)
    nVis = math.max(1, math.floor(h / self.rowH))
    for i = #self.rows + 1, nVis do MakeRow(i) end
    for i = nVis + 1, #self.rows do self.rows[i]:Hide() end
    self:Refresh()
  end
  function list:VisibleRows() return nVis end

  -- (Daniel 26.10.: the window can be dragged wider) a new width: the rows and the columns follow
  function list:SetWidth(w)
    w = math.max(60, math.floor(w))
    if w == self.w then return end
    self.w = w
    frame:SetWidth(w)
    if self.baseTextRight then self.textRight = self.baseTextRight + (self.growText and (w - self.baseW) or 0) end
    for _, row in ipairs(self.rows) do
      row:SetWidth(w - 6)
      PlaceCols(row)
    end
    self:Refresh()
  end

  function list:SetData(entries)
    self.data = entries or {}
    self:Refresh()
  end

  function list:SetSelected(key, scroll)
    self.selected = key
    if scroll then
      for i, e in ipairs(self.data) do
        if e.key == key then
          if i <= self.offset then self.offset = i - 1
          elseif i > self.offset + nVis then self.offset = i - nVis end
          break
        end
      end
    end
    self:Refresh()
  end

  return list
end
