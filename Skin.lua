-- ============================================================================
-- NPC Info :: Skin.lua
-- Единый стиль интерфейса: тёмная панель, холодный голубой акцент,
-- окна с заголовком и сохранением позиции, кнопки, чекбоксы, ползунки,
-- вкладки, полосы, «таблетки» и строки «название - значение».
-- ============================================================================
local addonName, ns = ...


local _G = _G
local floor, max, min = math.floor, math.max, math.min

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
UI.WHITE = WHITE
UI.BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }

UI.C = {
	bg = { 0.055, 0.055, 0.07, 0.97 },
	bar = { 0.09, 0.09, 0.11, 1 },
	ctrl = { 0.12, 0.12, 0.145, 1 },
	ctrlHover = { 0.16, 0.16, 0.19, 1 },
	border = { 0.22, 0.22, 0.26, 1 },
	accent = { 0.31, 0.70, 0.91, 1 },
	accentDark = { 0.07, 0.17, 0.24, 1 },
	text = { 0.92, 0.92, 0.94 },
	muted = { 0.55, 0.55, 0.6 },
	good = { 0.3, 0.82, 0.35 },
	warn = { 1, 0.78, 0.15 },
	bad = { 0.92, 0.3, 0.3 },
}
UI.HEX = { accent = "4FB3E8", good = "4dd159", warn = "ffc726", bad = "eb4d4d", muted = "8c8c99", text = "ebebf0" }

function UI:Hex(key, text)
	return "|cff" .. (self.HEX[key] or key) .. tostring(text) .. "|r"
end

function UI:Backdrop(f, bg, border)
	bg = bg or self.C.bg
	border = border or self.C.border
	f:SetBackdrop(self.BACKDROP)
	f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function UI:Font(parent, size, color, template, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	if size then
		local file, _, flags = fs:GetFont()
		fs:SetFont(file or STANDARD_TEXT_FONT, size, flags)
	end
	color = color or self.C.text
	fs:SetTextColor(color[1], color[2], color[3])
	if justify then fs:SetJustifyH(justify) end
	return fs
end

function UI:Line(parent, color, alpha)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(WHITE)
	t:SetHeight(1)
	color = color or self.C.border
	t:SetVertexColor(color[1], color[2], color[3], alpha or 1)
	return t
end

-- Мягкая тень вокруг окна (4 полупрозрачные полосы)
local function AddShadow(f)
	local s = CreateFrame("Frame", nil, f)
	s:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
	s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
	s:SetFrameLevel(max(0, f:GetFrameLevel() - 1))
	s:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
	s:SetBackdropBorderColor(0, 0, 0, 0.8)
	return s
end

-- ---------------------------------------------------------------------------
-- Окно: заголовок (перетаскивание), закрытие, Esc, сохранение позиции
-- ---------------------------------------------------------------------------
function UI:Window(name, title, width, height, parent)
	local f = CreateFrame("Frame", name, parent or UIParent)
	f:SetWidth(width)
	f:SetHeight(height)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	self:Backdrop(f)
	AddShadow(f)

	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	bar:SetHeight(26)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetTexture(WHITE)
	barBg:SetAllPoints(bar)
	barBg:SetVertexColor(self.C.bar[1], self.C.bar[2], self.C.bar[3], 1)
	local accent = self:Line(bar, self.C.accent, 0.8)
	accent:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	accent:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)

	local icon = bar:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetWidth(16)
	icon:SetHeight(16)
	icon:SetPoint("LEFT", bar, "LEFT", 7, 0)
	f.icon = icon

	local t = self:Font(bar, 13, self.C.accent, "GameFontNormal", "LEFT")
	t:SetPoint("LEFT", icon, "RIGHT", 7, 0)
	t:SetText(title or "")
	f.title = t

	local close = self:Button(bar, "x", 20, 18)
	close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	close.hoverBorder = self.C.bad
	f.close = close

	-- лёгкий градиент под заголовком
	local glow = f:CreateTexture(nil, "BORDER")
	glow:SetTexture(WHITE)
	glow:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -27)
	glow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -27)
	glow:SetHeight(60)
	if glow.SetGradientAlpha then
		glow:SetGradientAlpha("VERTICAL", self.C.accent[1], self.C.accent[2], self.C.accent[3], 0,
			self.C.accent[1], self.C.accent[2], self.C.accent[3], 0.07)
	else
		glow:SetVertexColor(self.C.accent[1], self.C.accent[2], self.C.accent[3], 0.03)
	end
	f.glow = glow

	local key = name
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		if ns.db and key then
			ns.db.windows = ns.db.windows or {}
			local p, _, rp, x, y = f:GetPoint()
			ns.db.windows[key] = { p, rp, x, y }
		end
	end)
	function f:RestorePosition(dp, drp, dx, dy)
		self:ClearAllPoints()
		local w = ns.db and ns.db.windows and ns.db.windows[key]
		if w then
			self:SetPoint(w[1], UIParent, w[2], w[3], w[4])
		else
			self:SetPoint(dp or "CENTER", UIParent, drp or "CENTER", dx or 0, dy or 0)
		end
	end

	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
	content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
	f.content = content
	f.bar = bar

	if name then tinsert(UISpecialFrames, name) end
	f:Hide()
	return f
end

-- ---------------------------------------------------------------------------
-- Кнопка (обычная / главная)
-- ---------------------------------------------------------------------------
function UI:Button(parent, label, w, h, primary)
	local C = self.C
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(w or 100)
	b:SetHeight(h or 22)
	local bg = primary and C.accentDark or C.ctrl
	self:Backdrop(b, bg, primary and C.accent or C.border)
	local t = self:Font(b, 11, primary and C.text or C.text, "GameFontHighlightSmall")
	t:SetPoint("CENTER", b, "CENTER", 0, 0)
	t:SetText(label or "")
	b.text = t
	b.primary = primary
	b:SetScript("OnEnter", function(self)
		if self.disabled then return end
		local hb = self.hoverBorder or C.accent
		self:SetBackdropBorderColor(hb[1], hb[2], hb[3], 1)
		if not self.primary and not self.selected then self:SetBackdropColor(C.ctrlHover[1], C.ctrlHover[2], C.ctrlHover[3], 1) end
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(self.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self:RefreshStyle()
		if self.tip then GameTooltip:Hide() end
	end)
	function b:RefreshStyle()
		if self.selected then
			self:SetBackdropColor(C.accentDark[1], C.accentDark[2], C.accentDark[3], 1)
			self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
			self.text:SetTextColor(1, 1, 1)
		elseif self.primary then
			self:SetBackdropColor(C.accentDark[1], C.accentDark[2], C.accentDark[3], 1)
			self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
			self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		else
			self:SetBackdropColor(C.ctrl[1], C.ctrl[2], C.ctrl[3], 1)
			self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
			self.text:SetTextColor(C.muted[1] + 0.25, C.muted[2] + 0.25, C.muted[3] + 0.25)
		end
		self:SetAlpha(self.disabled and 0.45 or 1)
	end
	function b:SetSelected(v) self.selected = v and true or false; self:RefreshStyle() end
	function b:SetDisabledLook(v) self.disabled = v and true or false; self:RefreshStyle() end
	b:RefreshStyle()
	return b
end

-- ---------------------------------------------------------------------------
-- Чекбокс с подписью и необязательным пояснением
-- ---------------------------------------------------------------------------
function UI:Check(parent, label, desc, getter, setter)
	local C = self.C
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(desc and 34 or 20)
	local box = CreateFrame("Frame", nil, f)
	box:SetWidth(14)
	box:SetHeight(14)
	box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
	self:Backdrop(box, C.ctrl, C.border)
	local mark = box:CreateTexture(nil, "OVERLAY")
	mark:SetTexture(WHITE)
	mark:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)

	local t = self:Font(f, 12, C.text, "GameFontHighlight", "LEFT")
	t:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 1)
	t:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	t:SetText(label)
	if desc then
		local d = self:Font(f, 10, C.muted, "GameFontHighlightSmall", "LEFT")
		d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
		d:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		d:SetText(desc)
	end
	function f:Refresh()
		if getter() then mark:Show() else mark:Hide() end
	end
	f:SetScript("OnClick", function(self)
		setter(not getter())
		self:Refresh()
	end)
	f:SetScript("OnEnter", function() box:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
	f:SetScript("OnLeave", function() box:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)
	f:Refresh()
	return f
end

-- ---------------------------------------------------------------------------
-- Ползунок
-- ---------------------------------------------------------------------------
function UI:Slider(parent, width, minV, maxV, step, getter, setter)
	local C = self.C
	local s = CreateFrame("Slider", nil, parent)
	s:EnableMouse(true)
	s:SetOrientation("HORIZONTAL")
	s:SetWidth(width)
	s:SetHeight(10)
	self:Backdrop(s, C.ctrl, C.border)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(WHITE)
	thumb:SetWidth(10)
	thumb:SetHeight(16)
	thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	s:SetThumbTexture(thumb)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta)
		local v = self:GetValue() + delta * step
		self:SetValue(max(minV, min(maxV, v)))
	end)
	s:SetScript("OnValueChanged", function(self, v)
		if self.lock then return end
		v = floor(v / step + 0.5) * step
		setter(v)
		if self.OnLabel then self:OnLabel(v) end
	end)
	function s:Refresh()
		self.lock = true
		self:SetValue(getter())
		self.lock = false
		if self.OnLabel then self:OnLabel(getter()) end
	end
	return s
end

-- ---------------------------------------------------------------------------
-- Заголовок раздела: «ТЕКСТ ─────────»
-- ---------------------------------------------------------------------------
function UI:Section(parent, text)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(18)
	local t = self:Font(f, 11, self.C.accent, "GameFontNormalSmall", "LEFT")
	t:SetPoint("LEFT", f, "LEFT", 0, 0)
	t:SetText(text)
	local l = self:Line(f, self.C.border)
	l:SetPoint("LEFT", t, "RIGHT", 8, 0)
	l:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.text = t
	return f
end

-- ---------------------------------------------------------------------------
-- Полоса (здоровье / мана) с текстом
-- ---------------------------------------------------------------------------
function UI:Bar(parent, height)
	local C = self.C
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetHeight(height or 16)
	b:SetStatusBarTexture(WHITE)
	b:SetMinMaxValues(0, 1)
	local bg = CreateFrame("Frame", nil, b)
	bg:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	bg:SetFrameLevel(max(0, b:GetFrameLevel() - 1))
	self:Backdrop(bg, C.ctrl, C.border)
	local t = self:Font(b, 11, C.text, "GameFontHighlightSmall")
	t:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.text = t
	function b:SetColor(c) self:SetStatusBarColor(c[1], c[2], c[3], 0.85) end
	return b
end

-- ---------------------------------------------------------------------------
-- «Таблетка» - короткий цветной ярлык
-- ---------------------------------------------------------------------------
function UI:Pill(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetHeight(18)
	self:Backdrop(p, self.C.ctrl, self.C.border)
	local t = self:Font(p, 11, self.C.text, "GameFontHighlightSmall")
	t:SetPoint("CENTER", p, "CENTER", 0, 0)
	p.text = t
	function p:Set(text, color)
		self.text:SetText(text)
		color = color or UI.C.border
		self:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		self.text:SetTextColor(color[1] + (1 - color[1]) * 0.35, color[2] + (1 - color[2]) * 0.35, color[3] + (1 - color[3]) * 0.35)
		self:SetWidth(self.text:GetStringWidth() + 14)
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Строка «название ........ значение»
-- ---------------------------------------------------------------------------
function UI:KV(parent, label)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(16)
	local l = self:Font(f, 11, self.C.muted, "GameFontHighlightSmall", "LEFT")
	l:SetPoint("LEFT", f, "LEFT", 0, 0)
	l:SetText(label or "")
	local v = self:Font(f, 11, self.C.text, "GameFontHighlightSmall", "RIGHT")
	v:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	v:SetPoint("LEFT", l, "RIGHT", 6, 0)
	f.label, f.value = l, v
	function f:Set(text, labelText)
		if labelText then self.label:SetText(labelText) end
		self.value:SetText(text or "")
	end
	return f
end

-- ---------------------------------------------------------------------------
-- Вертикальная раскладка: stack:Add(widget, height, gap)
-- ---------------------------------------------------------------------------
function UI:Stack(parent, inset)
	local st = { parent = parent, y = 0, inset = inset or 0 }
	function st:Add(w, h, gap)
		self.y = self.y + (gap or 6)
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.inset, -self.y)
		w:SetPoint("RIGHT", self.parent, "RIGHT", -self.inset, 0)
		if h then w:SetHeight(h) end
		self.y = self.y + (h or w:GetHeight() or 16)
		return w
	end
	function st:Space(px) self.y = self.y + px end
	return st
end

-- ---------------------------------------------------------------------------
-- Вкладки под заголовком окна
-- ---------------------------------------------------------------------------
function UI:Tabs(win, labels, onSelect)
	local tabs = { buttons = {}, pages = {} }
	local x = 12
	for i, label in ipairs(labels) do
		local b = self:Button(win, label, 0, 22)
		local w = 0
		b.text:SetText(label)
		w = b.text:GetStringWidth() + 24
		b:SetWidth(max(70, w))
		b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -34)
		x = x + b:GetWidth() + 4
		b:SetScript("OnClick", function() tabs:Select(i) end)
		tabs.buttons[i] = b
		local page = CreateFrame("Frame", nil, win)
		page:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -66)
		page:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -14, 34)
		page:Hide()
		tabs.pages[i] = page
	end
	function tabs:Select(i)
		self.current = i
		for k, b in ipairs(self.buttons) do
			b:SetSelected(k == i)
			if k == i then self.pages[k]:Show() else self.pages[k]:Hide() end
		end
		if onSelect then onSelect(i, self.pages[i]) end
	end
	return tabs
end

-- ---------------------------------------------------------------------------
-- Иконка в тонкой рамке (рамка красится: качество предмета, школа магии...)
-- ---------------------------------------------------------------------------
function UI:Icon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(size)
	f:SetHeight(size)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
	f:SetBackdropColor(0, 0, 0, 1)
	f:SetBackdropBorderColor(self.C.border[1], self.C.border[2], self.C.border[3], 1)
	local t = f:CreateTexture(nil, "ARTWORK")
	t:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.tex = t
	function f:SetIcon(path) self.tex:SetTexture(path or "Interface\\Icons\\INV_Misc_QuestionMark") end
	function f:SetBorder(c)
		c = c or UI.C.border
		self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	end
	return f
end

-- ---------------------------------------------------------------------------
-- «Плитка» - крупное число с подписью (сводка)
-- ---------------------------------------------------------------------------
function UI:Tile(parent)
	local C = self.C
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(42)
	self:Backdrop(f, C.bar, C.border)
	local top = f:CreateTexture(nil, "ARTWORK")
	top:SetTexture(WHITE)
	top:SetHeight(2)
	top:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	f.top = top
	local v = self:Font(f, 15, C.text, "GameFontNormalLarge")
	v:SetPoint("TOP", f, "TOP", 0, -7)
	local l = self:Font(f, 9, C.muted, "GameFontHighlightSmall")
	l:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
	f.value, f.label = v, l
	function f:Set(value, label, color)
		color = color or C.accent
		self.value:SetText(value or "-")
		self.value:SetTextColor(color[1], color[2], color[3])
		if label then self.label:SetText(label) end
		self.top:SetVertexColor(color[1], color[2], color[3], 0.9)
	end
	return f
end

-- Цвет качества предмета
function UI:QualityColor(q)
	if q and GetItemQualityColor then
		local r, g, b = GetItemQualityColor(q)
		if r then return { r, g, b } end
	end
	return self.C.border
end
