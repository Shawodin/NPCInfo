-- ============================================================================
-- NPC Info :: DPS.lua
-- Ваш реальный урон в секунду по журналу боя (вы + питомец), по уровням.
-- Нужен, чтобы оценить длительность боя с мобом для ЛЮБОГО класса.
-- Пока боёв нет - грубая оценка по оружию / уровню.
-- ============================================================================
local addonName, ns = ...

local max, min, floor = math.max, math.min, math.floor
local band = bit and bit.band

local D = {}
ns.DPS = D

local MIN_FIGHT = 6        -- сек.: короче - не учитывается
local MAX_SAMPLES = 20     -- после стольких боёв среднее становится скользящим

local function Char()
	if type(NPCInfoChar) ~= "table" then NPCInfoChar = {} end
	NPCInfoChar.dps = NPCInfoChar.dps or {}
	return NPCInfoChar
end

function D:Reset()
	NPCInfoChar = { dps = {} }
	ns:Fire("DATA_CHANGED")
end

-- Грубая оценка без данных: белый урон оружия, но не меньше 2.2 * уровень
local function Estimate(L)
	local est = 0
	local ok, lo, hi = pcall(UnitDamage, "player")
	local ok2, speed = pcall(UnitAttackSpeed, "player")
	if ok and ok2 and lo and hi and speed and speed > 0 then
		est = (lo + hi) / 2 / speed
	end
	return max(est, 2.2 * L + 3)
end

-- Возвращает: урон в секунду, число учтённых боёв, уровень данных
function D:Get(L)
	L = L or UnitLevel("player") or 1
	local t = Char().dps
	local e = t[L]
	if e and e.n > 0 then return e.m, e.n, L end
	-- ближайший уровень ниже (до 5), масштабирование пропорционально уровню
	for l = L - 1, max(1, L - 5), -1 do
		local p = t[l]
		if p and p.n > 0 then return p.m * L / l, p.n, l end
	end
	return Estimate(L), 0, nil
end

-- ---------------------------------------------------------------------------
-- Журнал боя
-- ---------------------------------------------------------------------------
local playerGUID, petGUID
local fightStart, fightDamage = nil, 0

local DAMAGE_12 = { SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, RANGE_DAMAGE = true, DAMAGE_SHIELD = true }

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(_, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not fightStart then return end
		local _, sub, src, _, _, _, _, dstFlags = ...
		if src ~= playerGUID and (not petGUID or src ~= petGUID) then return end
		if band and type(dstFlags) == "number" and band(dstFlags, 0x40) == 0 then return end -- не враг
		local amount
		if sub == "SWING_DAMAGE" then
			amount = select(9, ...)
		elseif DAMAGE_12[sub] then
			amount = select(12, ...)
		end
		if type(amount) == "number" and amount > 0 then
			fightDamage = fightDamage + amount
		end
	elseif event == "PLAYER_LOGIN" then
		playerGUID = UnitGUID("player")
		petGUID = UnitGUID("pet")
		Char()
	elseif event == "UNIT_PET" then
		petGUID = UnitGUID("pet")
	end
end)

ns:On("COMBAT_START", function()
	fightStart = GetTime()
	fightDamage = 0
end)

ns:On("COMBAT_END", function()
	if not fightStart then return end
	local dur = GetTime() - fightStart
	fightStart = nil
	if not ns.db or not ns.db.trackDps then return end
	if dur < MIN_FIGHT or fightDamage <= 0 then return end
	local sample = fightDamage / dur
	local L = UnitLevel("player") or 1
	local t = Char().dps
	local e = t[L]
	if not e then e = { n = 0, m = sample }; t[L] = e end
	e.n = e.n + 1
	e.m = e.m + (sample - e.m) / min(e.n, MAX_SAMPLES)
	ns:Fire("DATA_CHANGED")
end)
