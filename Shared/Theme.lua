local _, ns = ...
local Style = ns.Style

---------------------------------------------------------------------------
-- Look of Questdon's quest book (18.10., Daniel): dark blue panel, gold lines, warm text.
-- Loaded right after Style.lua: the shared colour table is changed in place, so every window,
-- list, tile and the small window follow.
---------------------------------------------------------------------------
local C, B = Style.COLORS, Style.BOOK
-- (Daniel 26.10.: "das dunklere UI von Gemini möchte ich gerne haben") darker and less violet, the colours measured in his Gemini
-- drafts: body (17,21,24), title bar (13,19,33), buttons and tabs (30,34,44); the gold stays. Style.lua keeps the quest book's values
-- for the other addons, only Guildon's copy is changed here, before anything takes them over.
local function Dark(key, r, g, b)
  local c = B[key]
  c[1], c[2], c[3] = r, g, b
  c.hex = string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
Dark("background", 0.062, 0.078, 0.092)
Dark("backgroundLow", 0.045, 0.056, 0.082)   -- the bottom of the window: a little darker, no violet
Dark("header", 0.048, 0.074, 0.128)
Dark("card", 0.115, 0.132, 0.172)
Dark("cardLow", 0.082, 0.094, 0.125)
Dark("textHint", 0.60, 0.62, 0.68)
Style.DEFAULT_ALPHA = 0.93                  -- the draft's window is nearly opaque
local function Take(key, src)
  local c = C[key]
  for i = 1, 4 do c[i] = src[i] end
  c.hex = src.hex
end
for _, key in ipairs({ "background", "header", "textPrimary", "textSecondary", "textHint", "rowHover", "rowActive" }) do
  Take(key, B[key])
end
Take("accent", B.gold)
C.border = { B.gold[1], B.gold[2], B.gold[3], 0.30, hex = B.gold.hex }
ns.BOOK = B

---------------------------------------------------------------------------
-- One look for every window (Daniel 26.10.: "die Farbauswahl gefällt mir außerordentlich gut ... es ist wichtig, dass alles
-- die gleiche style hat"): gold lines and headings on the dark blue book, blue for what is chosen (tab, row), green / amber /
-- red for states. Kit.lua builds the shared widgets (button, check box, chip, bar) from these.
---------------------------------------------------------------------------
local G, GL = B.gold, B.goldLight
Style.PAL = {
  blue    = { 0.25, 0.66, 0.96, hex = "ff3fa9f5" },
  edge    = { G[1], G[2], G[3], 0.38 },          -- thin line round buttons, boxes, tiles
  edgeHot = { GL[1], GL[2], GL[3], 0.85 },       -- the same under the mouse
  popup   = { G[1], G[2], G[3], 0.70 },          -- line round the small windows (wish form, trade bar, export, pick list)
  well    = { 0.030, 0.040, 0.055, 0.62 },       -- dark inset: list background, tiles
  btn     = { 0.118, 0.133, 0.172, 0.97 },       -- button fill (Gemini: 30, 34, 44)
  btnHot  = { 0.180, 0.205, 0.265, 0.98 },
  amber   = { 0.93, 0.58, 0.16 },                -- a skill bar that is not full
}
for _, c in pairs(Style.PAL) do
  if not c.hex then
    c.hex = string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
  end
end
do -- the chosen row is blue everywhere (lists, dropdown menus)
  local a, bl = C.rowActive, Style.PAL.blue
  a[1], a[2], a[3], a[4] = bl[1], bl[2], bl[3], 0.34
end

