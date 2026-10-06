-- ============================================================================
-- NPC Info :: Core.lua
-- Пространство имён, настройки, шина событий, таймеры, общие утилиты,
-- слэш-команды. Работает для любого класса (WotLK 3.3.5a).
-- ============================================================================
local addonName, ns = ...

local format, floor, max, min = string.format, math.floor, math.max, math.min

ns.name = addonName or "NPCInfo"
ns.version = "1.1.1"
ns.TITLE = "NPC Info"
ns.HEX = "4FB3E8"
ns.ICON = "Interface\\Icons\\Ability_EyeOfTheOwl"

ns.defaults = {
	enabled = true,
	tooltip = true,          -- строка NPC Info в подсказке моба
	tooltipAll = true,       -- показывать и для безопасных мобов
	tooltipDetail = "SHIFT", -- SHIFT / CTRL / ALT / ALWAYS - подробности в подсказке
	menu = true,             -- пункт «Досье NPC» в меню ПКМ по рамке цели
	targetButton = true,     -- кнопка у портрета цели
	followTarget = true,     -- окно досье следует за сменой цели
	model3d = true,          -- объёмный портрет моба в досье
	compact = false,         -- свёрнутое досье (сводка и главные советы)
	calib = true,            -- уточнять урон мобов по журналу боя
	trackDps = true,         -- запоминать ваш урон в секунду по боям
	minimap = { angle = 200, hide = false },
	windows = {},
}

ns.callbacks = {}

function ns:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff" .. self.HEX .. "[NPC Info]|r " .. tostring(msg))
end

local function ReportError(err)
	local h = geterrorhandler and geterrorhandler()
	if h then h(err) end
end
ns.ReportError = ReportError

local function CopyDefaults(src, dst)
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, dst[k])
		elseif dst[k] == nil or type(dst[k]) ~= type(v) then
			dst[k] = v
		end
	end
	return dst
end

-- ---------------------------------------------------------------------------
-- Шина событий
-- ---------------------------------------------------------------------------
function ns:On(event, fn)
	if type(fn) ~= "function" then return end
	local list = self.callbacks[event]
	if not list then list = {}; self.callbacks[event] = list end
	list[#list + 1] = fn
end

function ns:Fire(event, ...)
	local list = self.callbacks[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then ReportError(err) end
	end
end

-- ---------------------------------------------------------------------------
-- Таймеры (в 3.3.5 нет C_Timer)
-- ---------------------------------------------------------------------------
local timers = {}
function ns:After(delay, fn)
	if type(fn) ~= "function" then return end
	timers[#timers + 1] = { at = GetTime() + (delay or 0), fn = fn }
end

-- Одно отложенное выполнение на серию вызовов
local debounced = {}
function ns:Debounce(key, delay, fn)
	if debounced[key] then return end
	debounced[key] = true
	self:After(delay, function()
		debounced[key] = nil
		fn()
	end)
end

-- ---------------------------------------------------------------------------
-- Общая математика
-- ---------------------------------------------------------------------------
-- Снижение физического урона бронёй против атакующего уровня L (3.3.5)
function ns:ArmorDR(armor, L)
	armor = max(0, armor or 0)
	L = L or 1
	local K = (L < 60) and (400 + 85 * L) or (467.5 * L - 22167.5)
	return min(0.75, max(0, armor / (armor + K)))
end

-- Множитель входящего урона от формы/стойки игрока
function ns:StanceMult()
	local _, class = UnitClass("player")
	if class ~= "WARRIOR" then return 1 end
	local idx = GetShapeshiftForm and GetShapeshiftForm() or 0
	if idx and idx > 0 and GetShapeshiftFormInfo then
		local icon = GetShapeshiftFormInfo(idx)
		if type(icon) == "string" and icon:lower():find("defensivestance", 1, true) then
			return 0.9
		end
	end
	return 1
end

-- Известно ли игроку заклинание (по ID; имя берётся на языке клиента)
function ns:Knows(id)
	local name = GetSpellInfo(id)
	return name and GetSpellInfo(name) and name or nil
end

-- Русское склонение: 1 бой, 2 боя, 5 боёв
function ns:Plural(n, one, few, many)
	local m10, m100 = n % 10, n % 100
	local w = many
	if m10 == 1 and m100 ~= 11 then w = one
	elseif m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then w = few end
	return n .. " " .. w
end

function ns:Fights(n) return self:Plural(n, "бой", "боя", "боёв") end

function ns:DetailActive()
	local m = self.db and self.db.tooltipDetail or "SHIFT"
	if m == "ALWAYS" then return true
	elseif m == "CTRL" then return IsControlKeyDown() and true or false
	elseif m == "ALT" then return IsAltKeyDown() and true or false end
	return IsShiftKeyDown() and true or false
end

function ns:DetailKeyName()
	local m = self.db and self.db.tooltipDetail or "SHIFT"
	return ({ SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt" })[m]
end

-- ---------------------------------------------------------------------------
-- События
-- ---------------------------------------------------------------------------
local core = CreateFrame("Frame", "NPCInfoCoreFrame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("PLAYER_REGEN_DISABLED")
core:RegisterEvent("PLAYER_REGEN_ENABLED")
core:RegisterEvent("MODIFIER_STATE_CHANGED")
core:RegisterEvent("PLAYER_LEVEL_UP")

core:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			NPCInfoDB = CopyDefaults(ns.defaults, NPCInfoDB)
			ns.db = NPCInfoDB
			ns:Fire("DB_READY")
		end
	elseif event == "PLAYER_LOGIN" then
		if not ns.db then
			NPCInfoDB = CopyDefaults(ns.defaults, NPCInfoDB)
			ns.db = NPCInfoDB
		end
		ns:Fire("LOGIN")
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns:Fire("COMBAT_START")
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns:Fire("COMBAT_END")
	elseif event == "MODIFIER_STATE_CHANGED" then
		ns:Fire("MODIFIER")
	elseif event == "PLAYER_LEVEL_UP" then
		ns:After(1, function() ns:Fire("DATA_CHANGED") end)
	end
end)

core:SetScript("OnUpdate", function()
	if #timers == 0 then return end
	local now = GetTime()
	local due
	for i = #timers, 1, -1 do
		if timers[i].at <= now then
			due = due or {}
			due[#due + 1] = timers[i].fn
			table.remove(timers, i)
		end
	end
	if due then
		for i = #due, 1, -1 do
			local ok, err = pcall(due[i])
			if not ok then ReportError(err) end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Слэш-команды
-- ---------------------------------------------------------------------------
local function HandleSlash(msg)
	if not ns.db then return end
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	if cmd == "" or cmd == "info" or cmd == "show" then
		if ns.MobInfo then ns.MobInfo:Toggle("target") end
	elseif cmd == "config" or cmd == "options" or cmd == "opt" then
		if ns.GUI then ns.GUI:Toggle() end
	elseif cmd == "on" or cmd == "off" then
		ns.db.enabled = (cmd == "on")
		ns:Fire("SETTINGS_CHANGED")
		ns:Print(ns.db.enabled and "Включено." or "Выключено.")
	elseif cmd == "minimap" then
		ns.db.minimap.hide = not ns.db.minimap.hide
		if ns.GUI then ns.GUI:UpdateMinimapButton() end
	elseif cmd == "stats" then
		local mobs, hits = ns.MobDB:Stats()
		local dps, n = ns.DPS:Get()
		ns:Print(format("Калибровка: %s, %s. Ваш урон: ~%.0f в сек. (%s).",
			ns:Plural(mobs, "моб", "моба", "мобов"), ns:Plural(hits, "удар", "удара", "ударов"),
			dps, n > 0 and ns:Fights(n) or "оценка"))
	elseif cmd == "reset" then
		if arg == "calib" then
			ns.MobDB:Reset()
			ns:Print("Калибровка урона мобов сброшена.")
		elseif arg == "dps" then
			ns.DPS:Reset()
			ns:Print("Статистика вашего урона сброшена.")
		else
			NPCInfoDB = CopyDefaults(ns.defaults, {})
			ns.db = NPCInfoDB
			ns:Print("Настройки сброшены.")
		end
		ns:Fire("SETTINGS_CHANGED")
		ns:Fire("DATA_CHANGED")
	else
		ns:Print("Команды: /npci [info | config | on | off | minimap | stats | reset [calib | dps]]")
	end
end

SLASH_NPCINFO1 = "/npcinfo"
SLASH_NPCINFO2 = "/npci"
SlashCmdList["NPCINFO"] = function(msg)
	local ok, err = pcall(HandleSlash, msg)
	if not ok then ReportError(err) end
end
