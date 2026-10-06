-- ============================================================================
-- NPC Info :: GUI.lua
-- Окно настроек (вкладки) и кнопка у миникарты.
-- ============================================================================
local addonName, ns = ...

local format, floor, cos, sin, rad, deg, atan2 = string.format, math.floor, math.cos, math.sin, math.rad, math.deg, math.atan2
local ipairs = ipairs

local GUI = {}
ns.GUI = GUI

local controls = {}

local function Changed() ns:Fire("SETTINGS_CHANGED") end

local function AddCheck(UI, st, page, key, label, desc)
	local c = UI:Check(page, label, desc,
		function() return ns.db[key] end,
		function(v) ns.db[key] = v and true or false; Changed() end)
	st:Add(c, desc and 34 or 20, 6)
	controls[#controls + 1] = c
	return c
end

local function Choice(UI, st, page, key, defs, hintText)
	local row = CreateFrame("Frame", nil, page)
	st:Add(row, 22, 8)
	local list = {}
	for i, d in ipairs(defs) do
		local b = UI:Button(row, d[2], 92, 22)
		b:SetPoint("LEFT", row, "LEFT", (i - 1) * 98, 0)
		b.key = d[1]
		b:SetScript("OnClick", function(self)
			ns.db[key] = self.key
			Changed()
			GUI:RefreshControls()
		end)
		list[i] = b
	end
	controls[#controls + 1] = { Refresh = function()
		for _, b in ipairs(list) do b:SetSelected(b.key == ns.db[key]) end
	end }
	if hintText then
		local h = UI:Font(page, 10, UI.C.muted, "GameFontHighlightSmall", "LEFT")
		h:SetText(hintText)
		st:Add(h, 14, 4)
	end
end

function GUI:Create()
	if self.frame then return self.frame end
	if not ns.db or not ns.UI then return nil end
	local UI = ns.UI
	local f = UI:Window("NPCInfoConfigFrame", "NPC Info  |cff8c8c99v" .. ns.version .. "|r", 440, 440)
	f:RestorePosition("CENTER", "CENTER", 0, 40)
	f:SetScript("OnShow", function() GUI:RefreshControls() end)

	local fl = UI:Line(f, UI.C.border)
	fl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 28)
	fl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 28)
	local foot = UI:Font(f, 10, UI.C.muted, "GameFontHighlightSmall", "LEFT")
	foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
	foot:SetText("/npci - досье цели   /npci config - настройки   /npci stats")
	f.status = UI:Font(f, 10, UI.C.muted, "GameFontHighlightSmall", "RIGHT")
	f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)

	local tabs = UI:Tabs(f, { "Общее", "Подсказка", "Данные" }, function() GUI:RefreshControls() end)
	self.tabs = tabs

	do -- 1. Общее
		local page = tabs.pages[1]
		local st = UI:Stack(page)
		st:Add(UI:Section(page, "ОСНОВНОЕ"), 18, 0)
		AddCheck(UI, st, page, "enabled", "Включить NPC Info", "Подсказки, кнопка у портрета и пункт меню.")
		local mm = UI:Check(page, "Кнопка у миникарты", "ЛКМ - настройки, Shift+ЛКМ - досье цели, ПКМ - перемещение.",
			function() return not ns.db.minimap.hide end,
			function(v) ns.db.minimap.hide = not v; GUI:UpdateMinimapButton() end)
		st:Add(mm, 34, 6)
		controls[#controls + 1] = mm

		st:Add(UI:Section(page, "ДОСЬЕ NPC"), 18, 14)
		AddCheck(UI, st, page, "menu", "Пункт «Досье NPC» в меню ПКМ по цели",
			"Если стандартное меню начнёт ругаться (например, на «Фокус») - выключите.")
		AddCheck(UI, st, page, "targetButton", "Кнопка у портрета цели", "Цвет рамки - уровень опасности моба.")
		AddCheck(UI, st, page, "followTarget", "Окно досье следует за сменой цели")
		AddCheck(UI, st, page, "model3d", "Объёмный портрет моба", "Если модель не загрузилась - показывается обычный портрет.")
		AddCheck(UI, st, page, "compact", "Свёрнутое досье", "Только сводка и главные советы. Переключается и кнопкой «-» в заголовке.")
	end

	do -- 2. Подсказка
		local page = tabs.pages[2]
		local st = UI:Stack(page)
		st:Add(UI:Section(page, "ПОДСКАЗКА МОБА"), 18, 0)
		AddCheck(UI, st, page, "tooltip", "Блок NPC Info в подсказке враждебного NPC")
		AddCheck(UI, st, page, "tooltipAll", "Показывать и для безопасных мобов", "Иначе - только «Опасно» и «Смертельно».")
		st:Add(UI:Section(page, "ПОДРОБНОСТИ ПО КЛАВИШЕ"), 18, 14)
		Choice(UI, st, page, "tooltipDetail",
			{ { "SHIFT", "Shift" }, { "CTRL", "Ctrl" }, { "ALT", "Alt" }, { "ALWAYS", "Всегда" } },
			"Способности, средний удар по вам, избегание и источник данных.")
	end

	do -- 3. Данные
		local page = tabs.pages[3]
		local st = UI:Stack(page)
		st:Add(UI:Section(page, "КАЛИБРОВКА УРОНА МОБОВ"), 18, 0)
		AddCheck(UI, st, page, "calib", "Уточнять урон мобов по журналу боя",
			"База - AzerothCore 3.3.5; реальные удары по вам поправляют прогноз.")
		local kv = {}
		kv.mobs = st:Add(UI:KV(page, "Мобов с данными / ударов"), 16, 6)
		kv.typ = st:Add(UI:KV(page, "Типичный моб вашего уровня: удар"), 16, 4)
		st:Add(UI:Section(page, "ВАШ УРОН"), 18, 14)
		AddCheck(UI, st, page, "trackDps", "Запоминать ваш урон в секунду по боям",
			"Нужен, чтобы оценить длительность боя и потерю здоровья.")
		kv.dps = st:Add(UI:KV(page, "Ваш урон в секунду"), 16, 6)
		self.kv = kv

		local row = CreateFrame("Frame", nil, page)
		st:Add(row, 22, 14)
		local b1 = UI:Button(row, "Сбросить калибровку", 160, 22)
		b1:SetPoint("LEFT", row, "LEFT", 0, 0)
		b1.hoverBorder = UI.C.bad
		b1:SetScript("OnClick", function() ns.MobDB:Reset(); ns:Fire("DATA_CHANGED"); GUI:RefreshControls() end)
		local b2 = UI:Button(row, "Сбросить урон", 130, 22)
		b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
		b2.hoverBorder = UI.C.bad
		b2:SetScript("OnClick", function() ns.DPS:Reset(); GUI:RefreshControls() end)
	end

	tabs:Select(1)
	self.frame = f
	return f
end

function GUI:RefreshControls()
	if not self.frame or not ns.db then return end
	for _, c in ipairs(controls) do if c.Refresh then c:Refresh() end end
	local kv, UI = self.kv, ns.UI
	if kv then
		local mobs, hits = ns.MobDB:Stats()
		local L = UnitLevel("player") or 1
		kv.mobs:Set(format("%d / %d", mobs, hits))
		kv.typ:Set(format("~%.0f до брони (база %.0f)", ns.MobDB:GenericRawHit(L), ns.MobDB:BasePerSec(L, 1) * 2))
		local dps, n = ns.DPS:Get(L)
		kv.dps:Set(format("~%.0f  |cff8c8c99(%s)|r", dps, n > 0 and ns:Fights(n) or "оценка, боёв ещё нет"))
	end
	self.frame.status:SetText(ns.db.enabled and UI:Hex("good", "включено") or UI:Hex("bad", "выключено"))
end

function GUI:Toggle()
	local f = self:Create()
	if not f then return end
	if f:IsShown() then f:Hide() else f:Show() end
end

-- ---------------------------------------------------------------------------
-- Кнопка у миникарты
-- ---------------------------------------------------------------------------
local MINIMAP_RADIUS = 80

function GUI:UpdateMinimapPosition()
	local mb = self.minimapButton
	if not mb or not ns.db then return end
	local a = rad(ns.db.minimap.angle or 215)
	mb:ClearAllPoints()
	mb:SetPoint("CENTER", Minimap, "CENTER", cos(a) * MINIMAP_RADIUS, sin(a) * MINIMAP_RADIUS)
end

function GUI:UpdateMinimapButton()
	local mb = self.minimapButton
	if not mb or not ns.db then return end
	if ns.db.minimap.hide then
		mb:Hide()
	else
		mb:Show()
		self:UpdateMinimapPosition()
	end
end

function GUI:CreateMinimapButton()
	if self.minimapButton then return self.minimapButton end

	local mb = CreateFrame("Button", "NPCInfoMinimapButton", Minimap)
	mb:SetWidth(31)
	mb:SetHeight(31)
	mb:SetFrameStrata("MEDIUM")
	mb:SetFrameLevel(8)
	mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mb:RegisterForDrag("RightButton")

	local bg = mb:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetWidth(20)
	bg:SetHeight(20)
	bg:SetPoint("TOPLEFT", mb, "TOPLEFT", 7, -5)
	bg:SetVertexColor(0, 0, 0, 0.8)

	local icon = mb:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.ICON)
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("TOPLEFT", mb, "TOPLEFT", 7, -5)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = mb:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)
	border:SetVertexColor(0.35, 0.35, 0.38, 1)

	local function DragUpdate()
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		px, py = px / scale, py / scale
		ns.db.minimap.angle = deg(atan2(py - my, px - mx))
		GUI:UpdateMinimapPosition()
	end

	mb:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:LockHighlight()
		self:SetScript("OnUpdate", DragUpdate)
	end)
	mb:SetScript("OnDragStop", function(self)
		self.dragging = false
		self:UnlockHighlight()
		self:SetScript("OnUpdate", nil)
		GUI:UpdateMinimapPosition()
	end)

	mb:SetScript("OnClick", function(self, button)
		if button == "LeftButton" then
			if IsShiftKeyDown() and ns.MobInfo then ns.MobInfo:Toggle("target") else GUI:Toggle() end
		end
	end)

	mb:SetScript("OnEnter", function(self)
		if self.dragging then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("|cff" .. ns.HEX .. "NPC Info|r  |cff8c8c99v" .. ns.version .. "|r")
		GameTooltip:AddLine("|cffffffffЛКМ:|r настройки", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffffffShift+ЛКМ:|r досье текущей цели", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("|cffffffffПКМ (удерживать):|r переместить", 0.8, 0.8, 0.8)
		if ns.MobDB and ns.DPS then
			local mobs, hits = ns.MobDB:Stats()
			local dps, n = ns.DPS:Get()
			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine("Калибровка", ns:Plural(mobs, "моб", "моба", "мобов") .. ", " .. ns:Plural(hits, "удар", "удара", "ударов"), 0.55, 0.55, 0.6, 1, 1, 1)
			GameTooltip:AddDoubleLine("Ваш урон", format("~%.0f/с (%s)", dps, n > 0 and ns:Fights(n) or "оценка"), 0.55, 0.55, 0.6, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	mb:SetScript("OnLeave", function() GameTooltip:Hide() end)

	self.minimapButton = mb
	self:UpdateMinimapButton()
	return mb
end

-- ---------------------------------------------------------------------------
-- Инициализация
-- ---------------------------------------------------------------------------
ns:On("LOGIN", function()
	GUI:CreateMinimapButton()
	GUI:Create()
end)

local function Soon()
	if GUI.frame and GUI.frame:IsShown() then
		ns:Debounce("gui", 0.2, function() GUI:RefreshControls() end)
	end
end
ns:On("SETTINGS_CHANGED", Soon)
ns:On("DATA_CHANGED", Soon)
