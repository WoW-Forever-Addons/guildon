local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- Export for the guild website (Daniel 25.10.2026, Frankston's libra-vivendi page): one line per own character with
-- its professions, skill and learned recipes as spell IDs. Addons cannot reach the web, so the player copies the
-- text (Ctrl+C) and pastes it on the website. Format (docs/guildon-export/FORMAT.md, version 1):
--   GNX1;<game F|E>;<name>;<realm>;<faction A|H|N>;<CLASS>;<level>;<stamp>;<profs>;<checksum>
--   profs: <skill line>:<rank>:<max>:<spell IDs base 36, comma> joined by "/" (gathering professions with an empty list)
--   checksum: ns.Checksum of everything before the last ";" (8 hex digits)
-- No "|" anywhere: the game's edit boxes read it as an escape.
---------------------------------------------------------------------------
ns.EXPORT_VERSION = 1

-- own characters: class, level, faction (only the character itself can read them, kept for the export)
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

local function Clean(s) return (tostring(s or ""):gsub("[;|/:,%c]", "")) end

-- the export line of one own character, nil without professions
function ns.ExportLine(owner)
  local entry = ns.db.prof and ns.db.prof[owner]
  if not entry then return nil end
  local ids = {}
  for skill in pairs(entry) do if ns.PROF_BY_ID[skill] then ids[#ids + 1] = skill end end
  if #ids == 0 then return nil end
  table.sort(ids)
  local stamp, profs = 0, {}
  for _, skill in ipairs(ids) do
    local e = entry[skill]
    local spells = {}
    for id in pairs(e.recipes or {}) do spells[#spells + 1] = id end
    table.sort(spells)
    for i, id in ipairs(spells) do spells[i] = ns.B36(id) end
    profs[#profs + 1] = ("%d:%d:%d:%s"):format(skill, e.rank or 0, e.max or 0, table.concat(spells, ","))
    if (e.read or 0) > stamp then stamp = e.read end
  end
  local name, realm = owner:match("^(.-)%-(.+)$")
  local c = (ns.db.chars or {})[owner] or {}
  local head = ("GNX%d;%s;%s;%s;%s;%s;%d;%d;%s"):format(ns.EXPORT_VERSION, ns.ERA and "E" or "F", Clean(name or owner),
    Clean(realm or ""), c.faction or "N", c.class or "", c.level or 0, stamp > 0 and stamp or time(), table.concat(profs, "/"))
  return head .. ";" .. ns.Checksum(head)
end

-- all own characters, the current one first
function ns.ExportText()
  local me, names = ns.MyName(), {}
  for owner in pairs(ns.db.prof or {}) do if owner ~= me then names[#names + 1] = owner end end
  table.sort(names)
  table.insert(names, 1, me)
  local lines = {}
  for _, owner in ipairs(names) do
    local l = owner and ns.ExportLine(owner)
    if l then lines[#lines + 1] = l end
  end
  return table.concat(lines, "\n"), #lines
end

-- parse one line (tests, and the reference for the website): table or nil, reason
function ns.ParseExport(line)
  local head, sum = tostring(line or ""):match("^(.*);(%x%x%x%x%x%x%x%x)$")
  if not head then return nil, "format" end
  if ns.Checksum(head) ~= sum then return nil, "checksum" end
  local v, game, name, realm, fac, cls, lv, stamp, profs = head:match("^GNX(%d+);([FE]);([^;]*);([^;]*);([AHN]);(%u*);(%d+);(%d+);(.*)$")
  if not v then return nil, "format" end
  local out = { version = tonumber(v), game = game, name = name, realm = realm, faction = fac, class = cls,
    level = tonumber(lv), stamp = tonumber(stamp), profs = {} }
  for piece in (profs .. "/"):gmatch("([^/]*)/") do
    if piece ~= "" then
      local skill, rank, max, list = piece:match("^(%d+):(%d+):(%d+):([%w,]*)$")
      if not skill then return nil, "format" end
      local p = { skill = tonumber(skill), rank = tonumber(rank), max = tonumber(max), spells = {} }
      for code in list:gmatch("%w+") do p.spells[#p.spells + 1] = ns.UnB36(code) end
      out.profs[#out.profs + 1] = p
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Copy box: a dialog with a text the player selects and copies (Ctrl+C). Also used by other parts of Guildon.
---------------------------------------------------------------------------
local box
local function BuildBox()
  box = CreateFrame("Frame", "GuildonCopyBox", UIParent)
  box:SetSize(520, 260)
  box:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  box:SetFrameStrata("DIALOG")
  box:EnableMouse(true)
  box:SetMovable(true)
  box:RegisterForDrag("LeftButton")
  box:SetScript("OnDragStart", function(self) self:StartMoving() end)
  box:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  ns.UI.Skin(box, Style.PAL.popup, { C.background[1], C.background[2], C.background[3], 0.97 })
  box.title = ns.UI.Text(box, "GameFontNormal", 12, -10, 496, "gold")
  box.hint = ns.UI.Text(box, "GameFontHighlightSmall", 12, -30, 496, "textSecondary")
  local scroll = CreateFrame("ScrollFrame", nil, box)
  scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -56)
  scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 44)
  local sbg = scroll:CreateTexture(nil, "BACKGROUND")
  sbg:SetAllPoints()
  sbg:SetColorTexture(1, 1, 1, 0.06)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(GameFontHighlightSmall)
  edit:SetWidth(490)
  edit:SetTextInsets(4, 4, 4, 4)
  edit:SetScript("OnEscapePressed", function() box:Hide() end)
  -- the text is fixed: typing restores it, so a slip of the keyboard cannot spoil the copy
  edit:SetScript("OnTextChanged", function(self, user)
    if user and box.text and self:GetText() ~= box.text then self:SetText(box.text) self:HighlightText() end
  end)
  edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  scroll:SetScrollChild(edit)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = self:GetVerticalScrollRange() or 0
    local cur = (self:GetVerticalScroll() or 0) - delta * 20
    self:SetVerticalScroll(math.max(0, math.min(max, cur)))
  end)
  scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
  box.edit = edit
  box.close = ns.UI.FlatButton(box, 100, 24, L["Close"])
  box.close:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
  box.close:SetScript("OnClick", function() box:Hide() end)
  box.select = ns.UI.FlatButton(box, 140, 24, L["Select all"])
  box.select:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
  box.select:SetScript("OnClick", function() edit:SetFocus() edit:HighlightText() end)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "GuildonCopyBox") end
  box:Hide()
end

function ns.ShowCopyBox(title, hint, text)
  if not box then BuildBox() end
  box.text = text or ""
  box.title:SetText(title or "")
  box.hint:SetText(hint or "")
  box.edit:SetText(box.text)
  box:Show()
  box.edit:SetFocus()
  box.edit:HighlightText()
  return box
end

function ns.CopyBox() return box end -- (tests)

function ns.ShowExport()
  local text, n = ns.ExportText()
  if n == 0 then
    ns.Print(L["Nothing to export yet: open your profession window once."])
    return false
  end
  ns.ShowCopyBox(L["Export for the guild website"],
    L["%d characters. Press Ctrl+C to copy, then paste the text on the guild website."]:format(n), text)
  return true
end
