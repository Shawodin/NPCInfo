-- ============================================================================
-- NPC Info :: MobInfo.lua
-- «Досье моба»: окно со всей информацией о цели (здоровье, уровень, урон,
-- скорость атаки, угроза для вас, длительность боя, способности, особенности).
-- Открывается: пункт в меню ПКМ по рамке цели, кнопка у портрета цели,
-- /npci. Окно следует за сменой цели.
-- ============================================================================
local addonName, ns = ...


local _G = _G
local format, floor, max, min = string.format, math.floor, math.max, math.min
local ipairs, pairs = ipairs, pairs

local MI = {}
ns.MobInfo = MI

local UI
local win, stack
local W = 368
local MAX_SPELLS = 6
local PORTRAIT_SIZE = 46

local CLASS_NAMES = {
	normal = "Обычный", elite = "Элита", rare = "Редкий", rareelite = "Редкий элитный",
	worldboss = "Босс", trivial = "Слабый",
}
local DANGER = {
	[1] = { "Безопасно", "good" },
	[2] = { "Опасно", "warn" },
	[3] = { "Смертельно", "bad" },
}

local function N(v)
	if not v then return "-" end
	if v >= 10000 then return format("%.1fk", v / 1000) end
	return format("%d", floor(v + 0.5))
end

local function Pct(v) return format("%.0f%%", (v or 0) * 100) end

local function ValidUnit(unit)
	return unit and UnitExists(unit) and not UnitIsPlayer(unit) and not UnitPlayerControlled(unit)
end

-- ---------------------------------------------------------------------------
-- Подсказки под ваш класс: какие из ваших способностей помогут.
-- Названия берутся из клиента, показываются только изученные (ранг 1 ID -
-- GetSpellInfo(имя) находит любой изученный ранг). Порядок = приоритет.
-- ---------------------------------------------------------------------------
local INTERRUPTS = {
	-- настоящие прерывания
	6552, 72, 1766, 2139, 57994, 47528, 47476, 34490, 15487, 16979, 28730, 25046, 50613,
	-- контроль, который тоже сбивает заклинание
	853, 5211, 12809, 408, 1776, 49576, 19503, 20066, 6789, 30283, 20549, 8122, 5246,
}
local FEARBREAK = { 18499, 7744, 8143, 6346, 59752, 49039, 12292, 642, 31224, 45438 }
local STUNBREAK = { 59752, 1953, 642, 45438, 20594 }
local SLOWS = {
	1715, 12323, 5116, 2974, 13809, 8056, 120, 116, 45524, 15407,
	31589, 18223, 26679, 2484, 20184, 339, 408, 1776, 853, 5211, 20066,
}
local CURE = {
	poison  = { 8946, 2893, 526, 1152, 4987, 51886, 20594 },
	disease = { 528, 552, 526, 1152, 4987, 20594 },
	curse   = { 475, 2782, 51886 },
}
local DEFENSIVE = {
	871, 12975, 20230, 498, 642, 633, 1022, 5277, 1856, 31224, 2983, 45438, 1953, 1463,
	5384, 19263, 781, 47585, 17, 30823, 2645, 22812, 61336, 22842, 1850, 48792, 48707,
	6789, 5484, 6229,
}
local GAPCLOSE = { 100, 20252, 49576, 36554, 16979, 49376 }
local PET_LOCK = { ["Felhunter"] = 19244, ["Охотник Скверны"] = 19244 }
local RANGED = { MAGE = true, WARLOCK = true, PRIEST = true, HUNTER = true }

local function Known(list, n)
	local out, seen = {}, {}
	for _, id in ipairs(list) do
		local name = ns:Knows(id)
		if name and not seen[name] then
			seen[name] = true
			out[#out + 1] = name
			if #out >= (n or 2) then break end
		end
	end
	return (#out > 0) and table.concat(out, " / ") or nil
end

-- Прерывания с учётом питомца (Охотник Скверны - «Запрет чар»)
local function KnownInterrupts(n)
	local s = Known(INTERRUPTS, n)
	if UnitExists("pet") and not UnitIsDead("pet") then
		local id = PET_LOCK[UnitCreatureFamily("pet") or ""]
		local pn = id and GetSpellInfo(id)
		if pn then
			pn = pn .. " (питомец)"
			s = s and (s .. " / " .. pn) or pn
		end
	end
	return s
end

-- ---------------------------------------------------------------------------
-- Сбор данных
-- ---------------------------------------------------------------------------
function MI:Collect(unit)
	if not ValidUnit(unit) then return nil end
	local d = {}
	local pLevel = UnitLevel("player") or 1
	d.name = UnitName(unit) or "?"
	d.level = UnitLevel(unit) or 0
	d.skull = d.level <= 0
	d.mLevel = d.skull and (pLevel + 10) or d.level
	d.class = UnitClassification(unit) or "normal"
	d.ctype = UnitCreatureType(unit)
	d.family = UnitCreatureFamily and UnitCreatureFamily(unit)
	d.reaction = UnitReaction(unit, "player") or 4
	d.attackable = UnitCanAttack("player", unit) and true or false
	d.hp, d.hpMax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
	d.power, d.powerMax = UnitPower(unit) or 0, UnitPowerMax(unit) or 0
	d.powerType = UnitPowerType(unit)
	d.guid = UnitGUID(unit)

	local M = ns.MobDB
	d.npcID = M and M:NpcID(d.guid)
	local ok, liveSwing = pcall(UnitAttackSpeed, unit)
	if not ok or type(liveSwing) ~= "number" or liveSwing <= 0.5 or liveSwing > 6 then liveSwing = nil end
	if M then
		d.minHit, d.maxHit, d.avgHit, d.swing, d.src = M:DamageRange(d.mLevel, d.class, d.npcID, liveSwing)
		d.swing = liveSwing or d.swing or 2.0
		d.abilities, d.flags = M:Abilities(d.npcID)
		d.npcClass = M:NpcClass(d.npcID)
		d.armor = M:BaseArmor(d.mLevel, d.npcID)
		d.observed = M:Observed(d.npcID)
	end

	if d.attackable then
		d.eval = ns:EvaluateMob(unit)
		local e = d.eval
		if e then
			d.myDps, d.ttk, d.loss, d.hpPercent, d.dpsSamples = e.myDps, e.ttk, e.loss, e.hpPercent, e.dpsSamples
			d.armor = e.armor or d.armor
		end
	end
	return d
end

-- ---------------------------------------------------------------------------
-- Разбор заклинаний моба: описание из подсказки, время применения,
-- школа магии (цвет рамки иконки) и смысловые метки (оглушение, лечение...).
-- Ключевые слова ruRU + enUS, без учёта регистра первой буквы.
-- ---------------------------------------------------------------------------
local SCHOOLS = {
	{ { "от огня", "огнем", "огнём", "fire" }, { 1, 0.45, 0.15 }, "Огонь" },
	{ { "от льда", "холод", "frost" }, { 0.4, 0.75, 1 }, "Лёд" },
	{ { "тайной магии", "arcane" }, { 0.85, 0.5, 1 }, "Тайная магия" },
	{ { "сил природы", "nature" }, { 0.35, 0.85, 0.3 }, "Природа" },
	{ { "темной магии", "тёмной магии", "shadow" }, { 0.6, 0.35, 0.85 }, "Тьма" },
	{ { "светлой магии", "holy" }, { 1, 0.9, 0.5 }, "Свет" },
}
-- { ключевые слова, текст метки, цвет, код }
local CATS = {
	{ { "оглуш", "stun" }, "Оглушение", "bad", "stun" },
	{ { "страх", "ужас", "fear", "flee in terror" }, "Страх", "bad", "fear" },
	{ { "исцел", "восполняет", "восстанавливает", "heal" }, "Лечение", "good", "heal" },
	{ { "немот", "безмолв", "silence" }, "Немота", "warn", "silence" },
	{ { "обезоруж", "disarm" }, "Обезоружить", "warn", "disarm" },
	{ { "опутыв", "обездвиж", "immobil", "root" }, "Обездвиживание", "warn", "root" },
	{ { "замедл", "slow" }, "Замедление", "warn", "slow" },
	{ { "отбрасыв", "knock" }, "Отбрасывание", "warn", "knock" },
	{ { "отравл", "яд ", "яда", "ядом", "poison" }, "Яд", "warn", "poison" },
	{ { "болезн", "disease" }, "Болезнь", "warn", "disease" },
	{ { "прокля", "curse" }, "Проклятие", "warn", "curse" },
	{ { "брони", "armor" }, "Броня", "warn", "armor" },
	{ { "всех противник", "в радиусе", "ближайших", "nearby", "all enemies" }, "По области", "warn", "aoe" },
	{ { "каждые", "every " }, "Урон со временем", "muted", "dot" },
	{ { "призыв", "summon" }, "Призыв", "warn", "summon" },
}

local scanTip
local spellCache = {}

local function Lower(t)
	-- string.lower не трогает кириллицу - поэтому ключевые слова без заглавных
	return (t or ""):lower()
end

function MI:SpellInfo(id)
	if spellCache[id] then return spellCache[id] end
	local name, _, icon, cost, _, _, castTime, minRange, maxRange = GetSpellInfo(id)
	if not name then return nil end
	local info = { id = id, name = name, icon = icon, cast = (castTime or 0) / 1000, range = maxRange or 0, cats = {}, has = {} }

	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "NPCInfoSpellScan", nil, "GameTooltipTemplate")
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	end
	scanTip:ClearLines()
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	local ok = pcall(scanTip.SetHyperlink, scanTip, "spell:" .. id)
	local desc
	if ok then
		for i = (scanTip:NumLines() or 0), 2, -1 do
			local fs = _G["NPCInfoSpellScanTextLeft" .. i]
			local t = fs and fs:GetText()
			if t and #t > 12 then desc = t break end
		end
	end
	info.desc = desc
	local low = Lower(desc) .. " " .. Lower(name)
	for _, sc in ipairs(SCHOOLS) do
		for _, k in ipairs(sc[1]) do
			if low:find(k, 1, true) then info.school, info.schoolName = sc[2], sc[3] break end
		end
		if info.school then break end
	end
	for _, c in ipairs(CATS) do
		for _, k in ipairs(c[1]) do
			if low:find(k, 1, true) then
				if not info.has[c[4]] then
					info.has[c[4]] = true
					info.cats[#info.cats + 1] = { c[2], c[3] }
				end
				break
			end
		end
	end
	spellCache[id] = info
	return info
end

-- Обрезать описание по словам (UTF-8 безопасно)
local function Shorten(t, maxBytes)
	if not t then return "" end
	t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " "):gsub("%s+", " ")
	if #t <= maxBytes then return t end
	local cut = t:sub(1, maxBytes)
	local sp = cut:match("^.*() ")
	if sp and sp > maxBytes * 0.6 then cut = cut:sub(1, sp - 1) end
	-- не оставлять половину многобайтового символа
	while #cut > 0 do
		local b = cut:byte(#cut)
		if b < 128 then break end
		if b >= 192 then cut = cut:sub(1, -2) break end
		local i = #cut
		while i > 0 and cut:byte(i) >= 128 and cut:byte(i) < 192 do i = i - 1 end
		local lead = cut:byte(i) or 0
		local need = (lead >= 240) and 4 or ((lead >= 224) and 3 or 2)
		if #cut - i + 1 < need then cut = cut:sub(1, i - 1) end
		break
	end
	return cut .. "..."
end

-- ---------------------------------------------------------------------------
-- Окно
-- ---------------------------------------------------------------------------
local w = {}   -- виджеты
local spellRows = {}

local ROW_SP = 40
local function SpellRow(i)
	if spellRows[i] then return spellRows[i] end
	local r = CreateFrame("Button", nil, win.content)
	r:SetHeight(ROW_SP)
	local hl = r:CreateTexture(nil, "BACKGROUND")
	hl:SetTexture(UI.WHITE)
	hl:SetAllPoints(r)
	r.bgA = (i % 2 == 0) and 0.035 or 0.015
	hl:SetVertexColor(1, 1, 1, r.bgA)
	r.bg = hl
	local icon = UI:Icon(r, 30)
	icon:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -5)
	r.icon = icon
	local name = UI:Font(r, 12, UI.C.text, "GameFontHighlight", "LEFT")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 1)
	r.name = name
	local tag = UI:Font(r, 10, UI.C.muted, "GameFontHighlightSmall", "RIGHT")
	tag:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -4)
	tag:SetPoint("LEFT", name, "RIGHT", 6, 0)
	r.tag = tag
	local desc = UI:Font(r, 10, UI.C.muted, "GameFontHighlightSmall", "LEFT")
	desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	desc:SetPoint("RIGHT", r, "RIGHT", -4, 0)
	desc:SetHeight(24)
	desc:SetJustifyV("TOP")
	r.desc = desc
	r:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(UI.C.accent[1], UI.C.accent[2], UI.C.accent[3], 0.12)
		if self.spellId then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("spell:" .. self.spellId)
			if self.extra then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(self.extra, 0.78, 0.61, 0.43, true)
			end
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(1, 1, 1, self.bgA)
		GameTooltip:Hide()
	end)
	spellRows[i] = r
	return r
end

local tipRows = {}
local function TipRow(i)
	if tipRows[i] then return tipRows[i] end
	local f = CreateFrame("Frame", nil, win.content)
	local dot = f:CreateTexture(nil, "ARTWORK")
	dot:SetTexture(UI.WHITE)
	dot:SetWidth(4)
	dot:SetHeight(4)
	dot:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -5)
	f.dot = dot
	local t = UI:Font(f, 11, UI.C.text, "GameFontHighlightSmall", "LEFT")
	t:SetPoint("TOPLEFT", f, "TOPLEFT", 12, 0)
	t:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	t:SetJustifyV("TOP")
	f.text = t
	tipRows[i] = f
	return f
end

local function Create()
	if win then return win end
	UI = ns.UI
	win = UI:Window("NPCInfoFrame", "Досье NPC", W, 400)
	win:RestorePosition("LEFT", "LEFT", 260, 40)
	local c = win.content

	-- Шапка: портрет, имя, подпись, опасность
	-- Рамка портрета: отдельный фрейм фиксированного размера. Текстура и модель
	-- привязаны к нему двумя точками, поэтому клиент 3.3.5 не растягивает
	-- портрет до родного размера файла (64x64) после SetPortraitTexture.
	local PS = PORTRAIT_SIZE
	local pFrame = CreateFrame("Frame", nil, c)
	pFrame:SetWidth(PS)
	pFrame:SetHeight(PS)
	pFrame:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
	UI:Backdrop(pFrame, { 0.04, 0.05, 0.07, 1 }, UI.C.border)
	w.pFrame = pFrame
	local portrait = pFrame:CreateTexture(nil, "ARTWORK")
	portrait:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 1, -1)
	portrait:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", -1, 1)
	w.portrait = portrait
	-- 3D-портрет (если модель не загрузилась - остаётся обычный 2D)
	local model = CreateFrame("PlayerModel", nil, pFrame)
	model:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 1, -1)
	model:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", -1, 1)
	model:SetFrameLevel(pFrame:GetFrameLevel() + 1)
	model:Hide()
	w.model = model
	-- рамка поверх модели, чтобы модель не перекрывала край
	local pBorder = CreateFrame("Frame", nil, pFrame)
	pBorder:SetAllPoints(pFrame)
	pBorder:SetFrameLevel(pFrame:GetFrameLevel() + 2)
	pBorder:SetBackdrop({ edgeFile = UI.WHITE, edgeSize = 1 })
	pBorder:SetBackdropBorderColor(UI.C.border[1], UI.C.border[2], UI.C.border[3], 1)
	w.pBorder = pBorder

	w.name = UI:Font(c, 15, UI.C.text, "GameFontNormalLarge", "LEFT")
	w.name:SetPoint("TOPLEFT", pFrame, "TOPRIGHT", 10, -2)
	w.name:SetPoint("RIGHT", c, "RIGHT", -90, 0)
	w.sub = UI:Font(c, 11, UI.C.muted, "GameFontHighlightSmall", "LEFT")
	w.sub:SetPoint("TOPLEFT", w.name, "BOTTOMLEFT", 0, -4)
	w.sub:SetPoint("RIGHT", c, "RIGHT", 0, 0)
	w.sub2 = UI:Font(c, 10, UI.C.muted, "GameFontHighlightSmall", "LEFT")
	w.sub2:SetPoint("TOPLEFT", w.sub, "BOTTOMLEFT", 0, -3)
	w.danger = UI:Pill(c)
	w.danger:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
	w.skull = c:CreateTexture(nil, "OVERLAY")
	w.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	w.skull:SetWidth(16)
	w.skull:SetHeight(16)
	w.skull:SetPoint("RIGHT", w.danger, "LEFT", -3, 0)
	w.skull:Hide()

	-- Кнопка «свернуть / развернуть» в заголовке
	local cb = UI:Button(win.bar, "-", 20, 18)
	cb:SetPoint("RIGHT", win.close, "LEFT", -3, 0)
	cb.tip = "Свернуть / развернуть досье"
	cb:SetScript("OnClick", function()
		ns.db.compact = not ns.db.compact
		MI:Refresh()
	end)
	w.compactBtn = cb

	-- Плавное появление окна
	local fader = CreateFrame("Frame", nil, win)
	fader:Hide()
	fader:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + (elapsed or 0)
		local a = min(1, self.t / 0.15)
		win:SetAlpha(a)
		if a >= 1 then self:Hide() end
	end)
	win:HookScript("OnShow", function()
		win:SetAlpha(0)
		fader.t = 0
		fader:Show()
	end)

	-- Полосы
	w.hp = UI:Bar(c, 16)
	w.mp = UI:Bar(c, 10)

	-- Сводка: три плитки
	w.tiles = CreateFrame("Frame", nil, c)
	w.tile = {}
	for i = 1, 3 do
		local t = UI:Tile(w.tiles)
		w.tile[i] = t
	end

	-- Запас здоровья после боя
	w.surv = UI:Bar(c, 12)

	-- Разделы
	w.secAtk = UI:Section(c, "АТАКА МОБА")
	w.hit = UI:KV(c, "Удар (до вашей брони)")
	w.speed = UI:KV(c, "Скорость атаки")
	w.mdps = UI:KV(c, "Урон в секунду")
	w.marmor = UI:KV(c, "Броня (база для уровня)")

	w.secYou = UI:Section(c, "ПРОТИВ ВАС")
	w.avg = UI:KV(c, "Средний удар по вам")
	w.hits = UI:KV(c, "Ударов до смерти")
	w.avoid = UI:KV(c, "Избегание / блок")
	w.crit = UI:KV(c, "Крит / сокрушение по вам")
	w.ttk = UI:KV(c, "Бой займёт")
	w.loss = UI:KV(c, "Потеря здоровья за бой")

	w.secTips = UI:Section(c, "СОВЕТЫ")

	w.secFlags = UI:Section(c, "ОСОБЕННОСТИ")
	w.flags = CreateFrame("Frame", nil, c)
	w.pills = {}

	w.secSp = UI:Section(c, "СПОСОБНОСТИ")
	w.noSp = UI:Font(c, 11, UI.C.muted, "GameFontHighlightSmall", "LEFT")
	w.more = UI:Font(c, 10, UI.C.muted, "GameFontHighlightSmall", "LEFT")

	w.foot = UI:Font(win, 10, UI.C.muted, "GameFontHighlightSmall", "LEFT")
	w.foot:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 9)
	w.foot:SetPoint("RIGHT", win, "RIGHT", -12, 0)

	win:SetScript("OnHide", function() MI.unitGUID = nil; w.modelGUID = nil end)
	return win
end

local function GetPill(i)
	if w.pills[i] then return w.pills[i] end
	local p = UI:Pill(w.flags)
	w.pills[i] = p
	return p
end

local function ReactionColor(r)
	if r <= 2 then return UI.C.bad elseif r == 3 then return { 1, 0.5, 0.25 } elseif r == 4 then return UI.C.warn end
	return UI.C.good
end

function MI:Render(d)
	Create()
	local C = UI.C
	stack = UI:Stack(win.content, 0)

	-- Шапка
	local compact = ns.db and ns.db.compact
	w.compactBtn.text:SetText(compact and "+" or "-")
	local unit = self.unit
	if unit and UnitExists(unit) then
		SetPortraitTexture(w.portrait, unit)
		local use3d = ns.db and ns.db.model3d and (not UnitIsVisible or UnitIsVisible(unit))
		if use3d then
			if w.modelGUID ~= d.guid or not w.model:IsShown() then
				w.model:Show()
				w.model:SetUnit(unit)
				w.model:SetCamera(0)
				w.modelGUID = d.guid
			end
			local path = w.model.GetModel and w.model:GetModel()
			if path == "" then use3d = false end
		end
		if use3d then
			w.portrait:Hide()
		else
			w.model:Hide()
			w.modelGUID = nil
			w.portrait:Show()
		end
	end
	local rc = ReactionColor(d.reaction)
	w.name:SetText(d.name)
	w.name:SetTextColor(rc[1], rc[2], rc[3])
	local lvl
	if d.skull then
		lvl = UI:Hex("bad", "??")
	else
		local qc = GetQuestDifficultyColor and GetQuestDifficultyColor(d.level)
		lvl = qc and format("|cff%02x%02x%02x%d|r", floor(qc.r * 255), floor(qc.g * 255), floor(qc.b * 255), d.level) or tostring(d.level)
	end
	local parts = { "Уровень " .. lvl, CLASS_NAMES[d.class] or d.class }
	if d.ctype then parts[#parts + 1] = d.ctype end
	w.sub:SetText(table.concat(parts, "  |cff555560/|r  "))
	w.sub2:SetText(d.family and ("Семейство: " .. d.family) or "")
	if d.eval then
		local dg = DANGER[d.eval.danger] or DANGER[2]
		w.danger:Set(dg[1], C[dg[2]])
		w.danger:Show()
		if d.eval.danger == 3 or d.skull then w.skull:Show() else w.skull:Hide() end
	else
		w.danger:Hide()
		w.skull:Hide()
	end
	stack:Space(PORTRAIT_SIZE + 2)

	-- Здоровье и ресурс
	stack:Add(w.hp, 16, 6)
	if d.hpMax > 0 then
		local f = d.hp / d.hpMax
		w.hp:SetMinMaxValues(0, d.hpMax)
		w.hp:SetValue(d.hp)
		w.hp:SetColor({ 0.85 - 0.55 * f, 0.25 + 0.5 * f, 0.25 })
		if d.hpMax == 100 then
			w.hp.text:SetText(format("Здоровье %d%%", d.hp))
		else
			w.hp.text:SetText(format("Здоровье %s / %s", N(d.hp), N(d.hpMax)))
		end
	end
	if d.powerMax and d.powerMax > 0 then
		stack:Add(w.mp, 10, 4)
		w.mp:SetMinMaxValues(0, d.powerMax)
		w.mp:SetValue(d.power)
		local pc = (PowerBarColor and PowerBarColor[d.powerType]) or { r = 0.2, g = 0.4, b = 1 }
		w.mp:SetColor({ pc.r, pc.g, pc.b })
		w.mp.text:SetText(format("%s / %s", N(d.power), N(d.powerMax)))
		w.mp:Show()
	else
		w.mp:Hide()
	end

	-- Сводка
	local e = d.eval
	if e then
		stack:Add(w.tiles, 42, 10)
		local tw = floor((W - 24 - 8) / 3)
		for i, t in ipairs(w.tile) do
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", w.tiles, "TOPLEFT", (i - 1) * (tw + 4), 0)
			t:SetWidth(tw)
		end
		local hc = (e.hits < 4) and C.bad or ((e.hits < 8) and C.warn or C.good)
		w.tile[1]:Set((e.hits > 99) and "99+" or tostring(floor(e.hits)), "ударов до смерти", hc)
		if d.ttk then
			w.tile[2]:Set(d.ttk > 999 and "999+ с" or format("%.0f с", d.ttk), "бой займёт", C.accent)
			local lc = (d.loss >= 1.0) and C.bad or ((d.loss >= 0.6) and C.warn or C.good)
			w.tile[3]:Set((d.loss > 9.99) and "999%+" or Pct(d.loss), "потеря здоровья", lc)
		else
			w.tile[2]:Set("?", d.hpPercent and "здоровье моба в %" or "бой займёт", C.muted)
			w.tile[3]:Set("?", "потеря здоровья", C.muted)
		end
		w.tiles:Show()
	else
		w.tiles:Hide()
	end
	if e and d.loss then
		local left = max(0, 1 - d.loss)
		stack:Add(w.surv, 12, 6)
		w.surv:SetMinMaxValues(0, 1)
		w.surv:SetValue(left)
		w.surv:SetColor((d.loss >= 1) and C.bad or ((d.loss >= 0.6) and C.warn or C.good))
		if d.loss >= 1 then
			w.surv.text:SetText(format("Здоровья не хватит: бой съест ~%s", (d.loss > 9.99) and "999%+" or Pct(d.loss)))
		else
			w.surv.text:SetText(format("После боя останется ~%s здоровья", Pct(left)))
		end
		w.surv:Show()
	else
		w.surv:Hide()
	end

	local atkWidgets = { w.secAtk, w.hit, w.speed, w.mdps, w.marmor }
	if compact then
		for _, x in ipairs(atkWidgets) do x:Hide() end
	end
	if not compact then
		-- Атака моба
		stack:Add(w.secAtk, 18, 12)
		for _, x in ipairs(atkWidgets) do x:Show() end
		if d.avgHit then
			w.hit:Set(format("%s - %s  |cff8c8c99(сред. %s)|r", N(d.minHit), N(d.maxHit), N(d.avgHit)))
			w.speed:Set(format("%.2f с", d.swing or 2))
			w.mdps:Set(N(d.avgHit / (d.swing or 2)))
		else
			w.hit:Set("-") w.speed:Set("-") w.mdps:Set("-")
		end
		stack:Add(w.hit, 16, 4)
		stack:Add(w.speed, 16, 2)
		stack:Add(w.mdps, 16, 2)
		w.marmor:Set(d.armor and N(d.armor) or "-")
		stack:Add(w.marmor, 16, 2)
	end

	-- Против вас
	local youWidgets = { w.secYou, w.avg, w.avoid, w.crit, w.ttk }
	w.hits:Hide() w.loss:Hide()
	if e and not compact then
		stack:Add(w.secYou, 18, 12)
		w.avg:Set(N(e.avg) .. format("  |cff8c8c99(серия ударов ~%s с)|r", (e.seconds > 999) and "999+" or format("%.0f", e.seconds)))
		w.avoid:Set(format("%s / %s", Pct(e.avoid), Pct(e.pBlock)))
		w.crit:Set(format("%s / %s", Pct(e.pCrit), Pct(e.pCrush)))
		if d.myDps then
			local how = (d.dpsSamples or 0) > 0 and "по " .. ns:Plural(d.dpsSamples, "бою", "боям", "боям") or "оценка, данных ещё нет"
			w.ttk:Set(format("~%s/с  |cff8c8c99(%s)|r", N(d.myDps), how), "Ваш урон в секунду")
		else
			w.ttk:Set("-", "Ваш урон в секунду")
		end
		for i = 2, #youWidgets do stack:Add(youWidgets[i], 16, (i == 2) and 4 or 2) end
		for _, x in ipairs(youWidgets) do x:Show() end
	else
		for _, x in ipairs(youWidgets) do x:Hide() end
	end

	-- Разбор способностей (нужен и для советов)
	local spells, has = {}, {}
	for _, a in ipairs(d.abilities or {}) do
		local si = self:SpellInfo(a.id)
		if si then
			spells[#spells + 1] = { a = a, si = si }
			for k in pairs(si.has) do has[k] = true end
			if si.cast > 0 and not si.has.heal then has.cast = true end
			if si.cast > 0 and si.has.heal then has.castHeal = true end
		end
	end
	local fl = d.flags or {}

	-- Советы (с учётом изученных способностей вашего класса и питомца)
	local tips = {}
	local function Tip(text, col) tips[#tips + 1] = { text, col or C.accent } end
	local _, myClass = UnitClass("player")
	local hasPet = UnitExists("pet") and not UnitIsDead("pet")
	if e and e.danger == 3 then
		local df = Known(DEFENSIVE, 2)
		Tip("Смертельно для вас: обойдите или берите группу." .. (df and (" Если бой неизбежен: " .. df .. ", зелья.") or " Если бой неизбежен - зелья и защитные способности наготове."), C.bad)
	elseif e and e.danger == 2 then
		Tip("Опасно: начинайте с полным здоровьем, зелье держите под рукой.", C.warn)
	end
	if d.loss and d.loss >= 1.0 then
		local df = (not e or e.danger ~= 3) and Known(DEFENSIVE, 2)
		Tip("Здоровья может не хватить на весь бой" .. (df and (" - приберегите " .. df) or " - продумайте путь отхода") .. ".", C.bad)
	end
	if hasPet and e and e.danger >= 2 and (myClass == "HUNTER" or myClass == "WARLOCK" or myClass == "DEATHKNIGHT") then
		Tip("Пусть питомец примет моба на себя, а вы держите дистанцию.", C.accent)
	end
	local intr = (has.castHeal or has.cast) and KnownInterrupts(2)
	if has.castHeal then Tip("Лечит себя - сбивайте лечение" .. (intr and (": " .. intr) or ", иначе бой затянется") .. ".", C.good) end
	if has.cast then Tip("Есть заклинания с подготовкой - их можно сбить" .. (intr and (": " .. intr) or " или прервать оглушением") .. ".", C.warn) end
	if has.fear then
		local fb = Known(FEARBREAK, 2)
		Tip("Насылает страх" .. (fb and (" - защита/снятие: " .. fb) or " - убедитесь, что рядом нет других мобов") .. ".", C.warn)
	end
	if has.stun then
		local sb = Known(STUNBREAK, 1)
		Tip("Оглушает: не начинайте бой на низком здоровье" .. (sb and (" - выход из оглушения: " .. sb) or " - оглушение и серия ударов опасны") .. ".", C.bad)
	end
	if has.silence then
		Tip(RANGED[myClass] and "Накладывает немоту: держите здоровье с запасом - несколько секунд вы не сможете колдовать." or "Накладывает немоту: лечение и заклинания будут недоступны несколько секунд.", C.warn)
	end
	if has.disarm then
		Tip((myClass == "WARRIOR" or myClass == "ROGUE" or myClass == "DEATHKNIGHT" or myClass == "PALADIN") and "Обезоруживает: ваш урон ненадолго упадёт." or "Обезоруживает (для вас почти не опасно).", C.warn)
	end
	if has.armor then Tip("Снижает броню: входящий урон к концу боя растёт.", C.warn) end
	local cures, missing = {}, {}
	for _, k in ipairs({ "poison", "disease", "curse" }) do
		if has[k] then
			local n = Known(CURE[k], 1)
			local label = (k == "poison" and "яд") or (k == "disease" and "болезнь") or "проклятие"
			if n then cures[#cures + 1] = label .. " - " .. n else missing[#missing + 1] = label end
		end
	end
	if #cures > 0 then Tip("Снимайте ослабления: " .. table.concat(cures, ", ") .. ".", C.good) end
	if #missing > 0 then Tip("Накладывает " .. table.concat(missing, ", ") .. " - снять нечем: пригодятся зелья, бинты и запас здоровья.", C.muted) end
	if fl.flee then
		local sl = Known(SLOWS, 2)
		Tip("Убегает при низком здоровье" .. (sl and (" - держите замедление: " .. sl) or " - добивайте быстро, иначе приведёт помощь") .. ".", C.warn)
	end
	if fl.help then Tip("Зовёт помощь - отведите его от других мобов перед боем.", C.warn) end
	if d.npcClass == 8 and not has.cast then
		if RANGED[myClass] then
			Tip("Заклинатель: бой на дистанции - выгодно сбивать его заклинания.", { 0.45, 0.6, 1 })
		else
			local gc = Known(GAPCLOSE, 2)
			Tip("Заклинатель держит дистанцию: " .. (gc and ("сближайтесь - " .. gc) or "встаньте за укрытие, чтобы он подошёл") .. ".", { 0.45, 0.6, 1 })
		end
	end
	if e and e.crush and e.crush > 0 then Tip("Сокрушающие удары (моб на 4+ уровня выше) - урон заметно выше обычного.", C.bad) end
	if #tips == 0 and e then Tip("Обычный бой - можно нападать без подготовки.", C.good) end
	if compact then
		for i = #tips, 4, -1 do tips[i] = nil end
	end
	if #tips > 0 then
		stack:Add(w.secTips, 18, 12)
		w.secTips:Show()
		for i, t in ipairs(tips) do
			local r = TipRow(i)
			r.text:SetText(t[1])
			r.dot:SetVertexColor(t[2][1], t[2][2], t[2][3], 1)
			r:SetWidth(W - 24)
			local lines = math.ceil(max(1, r.text:GetStringWidth() or 1) / (W - 40))
			local h = max(14, lines * 13)
			stack:Add(r, h + 2, (i == 1) and 5 or 3)
			r:Show()
		end
		for i = #tips + 1, #tipRows do tipRows[i]:Hide() end
		w.secTips:Show()
	else
		w.secTips:Hide()
		for _, r in ipairs(tipRows) do r:Hide() end
	end

	-- Особенности
	local tags = {}
	if fl.flee then tags[#tags + 1] = { "Убегает за помощью", C.warn } end
	if fl.help then tags[#tags + 1] = { "Зовёт на помощь", C.warn } end
	if d.npcClass == 8 then tags[#tags + 1] = { "Заклинатель", { 0.45, 0.6, 1 } } end
	if d.class == "elite" or d.class == "rareelite" or d.class == "worldboss" then tags[#tags + 1] = { "Элита", C.accent } end
	if d.class == "rare" or d.class == "rareelite" then tags[#tags + 1] = { "Редкий", { 0.7, 0.7, 0.8 } } end
	if e and e.crush and e.crush > 0 then tags[#tags + 1] = { "Сокрушающие удары", C.bad } end
	if e and e.burstLethal then tags[#tags + 1] = { "Опасная серия ударов", C.bad } end
	if has.heal then tags[#tags + 1] = { "Лечится", C.good } end
	if has.aoe then tags[#tags + 1] = { "Урон по области", C.warn } end
	if #tags > 0 and not compact then
		stack:Add(w.secFlags, 18, 12)
		local x, y, rowH = 0, 0, 22
		for i, t in ipairs(tags) do
			local p = GetPill(i)
			p:Set(t[1], t[2])
			if x > 0 and x + p:GetWidth() > W - 24 then x = 0; y = y + rowH end
			p:ClearAllPoints()
			p:SetPoint("TOPLEFT", w.flags, "TOPLEFT", x, -y)
			p:Show()
			x = x + p:GetWidth() + 4
		end
		for i = #tags + 1, #w.pills do w.pills[i]:Hide() end
		stack:Add(w.flags, y + rowH, 4)
		w.secFlags:Show() w.flags:Show()
	else
		w.secFlags:Hide() w.flags:Hide()
		for _, p in ipairs(w.pills) do p:Hide() end
	end

	if compact then
		w.secSp:Hide() w.noSp:Hide() w.more:Hide()
		for _, r in ipairs(spellRows) do r:Hide() end
	else
		-- Способности
		stack:Add(w.secSp, 18, 12)
		w.secSp:Show()
		w.secSp.text:SetText(#spells > 0 and format("СПОСОБНОСТИ  |cff8c8c99%d|r", #spells) or "СПОСОБНОСТИ")
		local shown = 0
		for _, x in ipairs(spells) do
			if shown >= MAX_SPELLS then break end
			shown = shown + 1
			local a, si = x.a, x.si
			local r = SpellRow(shown)
			r.spellId = a.id
			r.icon:SetIcon(si.icon)
			r.icon:SetBorder(si.school or (si.has.heal and C.good) or C.border)
			r.name:SetText(si.name)
			local tg = {}
			if si.cast > 0 then
				tg[#tg + 1] = UI:Hex("warn", format("%.1f с", si.cast))
			else
				tg[#tg + 1] = UI:Hex("muted", "мгновенно")
			end
			for k, c in ipairs(si.cats) do
				if k <= 2 then tg[#tg + 1] = UI:Hex(c[2], c[1]) end
			end
			if a.maxHit then tg[#tg + 1] = UI:Hex("bad", "до " .. N(a.maxHit)) end
			r.tag:SetText(table.concat(tg, "  "))
			local dl = {}
			if a.tag then dl[#dl + 1] = UI:Hex("accent", a.tag:gsub("^%l", string.upper)) .. ": " end
			dl[#dl + 1] = Shorten(si.desc, a.tag and 150 or 180)
			r.desc:SetText(table.concat(dl))
			local ex = {}
			if a.tag then ex[#ex + 1] = "Применяет: " .. a.tag end
			if a.seen then ex[#ex + 1] = a.maxHit and ("Замечено в бою, максимум по вам: " .. N(a.maxHit)) or "Замечено в бою" end
			if si.schoolName then ex[#ex + 1] = "Школа: " .. si.schoolName end
			if si.cast > 0 then
				local intr = KnownInterrupts(2)
				ex[#ex + 1] = intr and ("Можно сбить: " .. intr) or "Есть время подготовки - можно прервать"
			end
			if si.has.heal then ex[#ex + 1] = "Сбивайте: лечение затягивает бой" end
			r.extra = (#ex > 0) and table.concat(ex, "\n") or nil
			stack:Add(r, ROW_SP, (shown == 1) and 4 or 2)
			r:Show()
		end
		for i = shown + 1, #spellRows do spellRows[i]:Hide() end
		if shown == 0 then
			w.noSp:SetText("Нет данных о способностях - моб, скорее всего, только бьёт в ближнем бою.")
			stack:Add(w.noSp, 16, 4)
			w.noSp:Show()
		else
			w.noSp:Hide()
		end
		if #spells > shown then
			w.more:SetText(format("и ещё %d", #spells - shown))
			stack:Add(w.more, 14, 2)
			w.more:Show()
		else
			w.more:Hide()
		end
	end

	-- Подвал
	local src = {}
	if d.src and (d.src.n or 0) > 0 then
		src[#src + 1] = format("калибровка: %d уд.", d.src.n)
	elseif d.src and d.src.db then
		src[#src + 1] = "база AzerothCore 3.3.5"
	else
		src[#src + 1] = "оценка по типу моба"
	end
	if d.npcID then src[#src + 1] = "NPC " .. d.npcID end
	w.foot:SetText(table.concat(src, "  |cff555560/|r  "))

	win:SetHeight(stack.y + 36 + 34)
	win:Show()
end

function MI:Open(unit)
	unit = unit or "target"
	if not ValidUnit(unit) then
		ns:Print("Выберите NPC (не игрока), чтобы открыть досье.")
		return
	end
	local d = self:Collect(unit)
	if not d then return end
	self.unit = unit
	self.unitGUID = d.guid
	self:Render(d)
end

function MI:Refresh()
	if win and win:IsShown() and self.unit and ValidUnit(self.unit) then self:Open(self.unit) end
end

function MI:Toggle(unit)
	if win and win:IsShown() then win:Hide() else self:Open(unit) end
end

-- Обновление: смена цели, здоровье
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("UNIT_LEVEL")
local throttle = 0
ev:SetScript("OnEvent", function(_, event, unit)
	if not win or not win:IsShown() then return end
	if event == "PLAYER_TARGET_CHANGED" then
		if ns.db and ns.db.followTarget and ValidUnit("target") then
			MI:Open("target")
		end
		return
	end
	if unit and MI.unit == unit and UnitGUID(unit) == MI.unitGUID then
		local now = GetTime()
		if now - throttle < 0.25 then return end
		throttle = now
		local ok, d = pcall(MI.Collect, MI, unit)
		if ok and d then MI:Render(d) end
	end
end)

-- ---------------------------------------------------------------------------
-- Пункт в меню ПКМ по рамке цели / фокуса
-- ---------------------------------------------------------------------------
local MENUS = { TARGET = true, FOCUS = true, BOSS = true }
if type(UnitPopup_ShowMenu) == "function" then
	hooksecurefunc("UnitPopup_ShowMenu", function(dropdownMenu, which, unit)
		if not ns.db or not ns.db.enabled or not ns.db.menu then return end
		if (UIDROPDOWNMENU_MENU_LEVEL or 1) ~= 1 or not MENUS[which or ""] then return end
		unit = unit or (dropdownMenu and dropdownMenu.unit)
		if not ValidUnit(unit) then return end
		local info = UIDropDownMenu_CreateInfo()
		info.text = "|T" .. ns.ICON .. ":14:14:0:0|t |cff" .. ns.HEX .. "Досье NPC|r"
		info.notCheckable = true
		info.func = function() MI:Open(unit) end
		UIDropDownMenu_AddButton(info, 1)
	end)
end

-- ---------------------------------------------------------------------------
-- Кнопка у портрета цели (рамка окрашена по опасности)
-- ---------------------------------------------------------------------------
local tb
local function CreateTargetButton()
	if tb or not TargetFrame then return end
	UI = ns.UI
	tb = CreateFrame("Button", "NPCInfoTargetButton", TargetFrame)
	tb:SetWidth(20)
	tb:SetHeight(20)
	local anchor = TargetFramePortrait or TargetFrame
	tb:SetPoint("CENTER", anchor, "BOTTOMLEFT", 4, 4)   -- не пересекается с кнопкой ProtHC
	tb:SetFrameLevel(TargetFrame:GetFrameLevel() + 10)
	UI:Backdrop(tb, UI.C.bg, UI.C.border)
	local ic = tb:CreateTexture(nil, "ARTWORK")
	ic:SetTexture(ns.ICON)
	ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ic:SetPoint("TOPLEFT", tb, "TOPLEFT", 2, -2)
	ic:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", -2, 2)
	tb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tb:SetScript("OnClick", function() MI:Toggle("target") end)
	tb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("|cff" .. ns.HEX .. "NPC Info|r: досье")
		GameTooltip:AddLine("Здоровье, урон, способности и угроза для вас", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	tb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tb:Hide()
end

function MI:UpdateTargetButton()
	CreateTargetButton()
	if not tb then return end
	if not ns.db or not ns.db.enabled or not ns.db.targetButton or not ValidUnit("target") then
		tb:Hide()
		return
	end
	local col = UI.C.border
	if UnitCanAttack("player", "target") then
		local ok, r = pcall(ns.EvaluateMob, ns, "target")
		if ok and r then
			col = (r.danger == 3) and UI.C.bad or ((r.danger == 2) and UI.C.warn or UI.C.good)
		end
	end
	tb:SetBackdropBorderColor(col[1], col[2], col[3], 1)
	tb:Show()
end

local tev = CreateFrame("Frame")
tev:RegisterEvent("PLAYER_TARGET_CHANGED")
tev:SetScript("OnEvent", function()
	local ok, err = pcall(MI.UpdateTargetButton, MI)
	if not ok and ns.ReportError then ns.ReportError(err) end
end)
ns:On("LOGIN", function() CreateTargetButton() end)
ns:On("SETTINGS_CHANGED", function() MI:UpdateTargetButton(); MI:Refresh() end)
ns:On("DATA_CHANGED", function()
	if tb and tb:IsShown() then MI:UpdateTargetButton() end
	if win and win:IsShown() and MI.unit and UnitGUID(MI.unit) == MI.unitGUID then MI:Open(MI.unit) end
end)
