-- ============================================================================
-- NPC Info :: MobDB.lua
-- Прогноз урона мобов: база AzerothCore (MobData.lua) + личная калибровка
-- по журналу боя (обычные удары ближнего боя по игроку).
--   Прогноз = База(уровень, класс, дополнение) * DamageModifier * интервал * K
--   K - поправка калибровки: сначала по конкретному мобу (NPC ID),
--   затем по группе «тип моба + диапазон 5 уровней», иначе 1.0.
-- Калибровка общая для всех персонажей аккаунта (NPCInfoCalib).
-- ============================================================================
local addonName, ns = ...


local type, tonumber, pairs, select, floor, max, min = type, tonumber, pairs, select, math.floor, math.max, math.min
local GetTime, UnitGUID = GetTime, UnitGUID

local M = {}
ns.MobDB = M

local DATA = ns.MobData or { BASE = {}, NPC = {} }
local MAX_LEVEL = 83

-- Модификаторы урона по классификации, если моба нет в базе
-- (нижний квартиль AzerothCore - типичные элиты открытого мира).
local function FallbackMod(class, L)
	if class == "elite" then
		if L <= 30 then return 1.7 elseif L <= 40 then return 2.4 elseif L <= 70 then return 3.5 end
		return 4.6
	elseif class == "rareelite" then
		if L <= 30 then return 1.7 elseif L <= 40 then return 2.4 end
		return 3.5
	elseif class == "worldboss" then
		return 10
	end
	return 1.0
end

-- Группа для калибровки: обычные (normal/rare/trivial) и элитные
local function Bucket(class)
	if class == "elite" or class == "rareelite" or class == "worldboss" then
		return "e"
	end
	return "n"
end

local function DefaultExp(L)
	if L <= 60 then return 0 elseif L <= 70 then return 1 end
	return 2
end

local PRIOR_BAND = 10   -- «вес» базы против калибровки группы (в ударах)
local PRIOR_NPC = 4     -- «вес» группы против калибровки конкретного моба
local MAX_N = 60        -- после стольких ударов среднее становится скользящим

-- ---------------------------------------------------------------------------
-- Сохранённые данные
-- ---------------------------------------------------------------------------
local calib

local function DB()
	if calib then return calib end
	if type(NPCInfoCalib) ~= "table" or NPCInfoCalib.version ~= 1 then
		NPCInfoCalib = { version = 1, npc = {}, band = {}, hits = 0 }
	end
	calib = NPCInfoCalib
	calib.npc = calib.npc or {}
	calib.band = calib.band or {}
	calib.hits = calib.hits or 0
	calib.spells = calib.spells or {}
	return calib
end

function M:Reset()
	NPCInfoCalib = nil
	calib = nil
	DB()
	self.dirty = true
end

function M:Stats()
	local d = DB()
	local mobs = 0
	for _ in pairs(d.npc) do mobs = mobs + 1 end
	return mobs, d.hits or 0
end

-- ---------------------------------------------------------------------------
-- GUID -> NPC ID (3.3.5: 0xF130 EEEEEE CCCCCC, существо / техника)
-- ---------------------------------------------------------------------------
function M:NpcID(guid)
	if type(guid) ~= "string" or #guid < 12 then return nil end
	local hi = guid:sub(3, 6):upper()
	if hi ~= "F130" and hi ~= "F150" then return nil end
	return tonumber(guid:sub(7, 12), 16)
end

local npcCache = {}
local function NpcInfo(id)
	if not id then return nil end
	local c = npcCache[id]
	if c ~= nil then return c or nil end
	local v = DATA.NPC and DATA.NPC[id]
	if v == nil then
		npcCache[id] = false
		return nil
	end
	local info
	if type(v) == "number" then
		info = { mod = v, cls = 1 }
	else
		local mod, cls, t, e = v:match("^([^,]*),([^,]*),([^,]*),?(.*)$")
		info = {
			mod = tonumber(mod) or 1,
			cls = tonumber(cls) or 1,
			swing = tonumber(t),
			exp = tonumber(e),
		}
	end
	npcCache[id] = info
	return info
end

-- Средний удар за 1 сек. интервала атаки (до брони и стойки)
function M:BasePerSec(L, cls, exp)
	L = max(1, min(MAX_LEVEL, floor(L or 1)))
	local byClass = DATA.BASE and (DATA.BASE[cls or 1] or DATA.BASE[1])
	local arr = byClass and (byClass[exp or DefaultExp(L)] or byClass[0])
	local v = arr and arr[L]
	if v then return v end
	return 2.5 * L / 0.603 / 2   -- запасная формула (старая модель)
end

local function BandKey(class, L)
	return Bucket(class) .. floor((L or 1) / 5)
end

local function BandRatio(class, L)
	local b = DB().band[BandKey(class, L)]
	if not b or not b.n or b.n <= 0 then return 1, 0 end
	return (b.n * b.m + PRIOR_BAND * 1) / (b.n + PRIOR_BAND), b.n
end

-- Прогноз «сырого» удара конкретного моба.
-- Возвращает: удар (до брони/стойки), интервал атаки, описание источника.
function M:Predict(L, class, npcID, liveSwing)
	L = max(1, L or 1)
	local info = NpcInfo(npcID)
	local mod, cls, exp, swing
	if info then
		mod, cls, exp, swing = info.mod, info.cls, info.exp, info.swing
	else
		mod, cls = FallbackMod(class, L), 1
	end
	swing = swing or liveSwing or 2.0
	local seed = self:BasePerSec(L, cls, exp) * mod * swing

	local k, bandN = BandRatio(class, L)
	local src = { db = info and true or false, n = 0, band = bandN }
	local e = npcID and DB().npc[npcID]
	if e and e.n and e.n > 0 then
		k = (e.n * e.m + PRIOR_NPC * k) / (e.n + PRIOR_NPC)
		src.n = e.n
	end
	src.k = k
	return seed * k, swing, src, seed
end

-- Разброс урона за удар (мин, макс) с учётом калибровки
function M:DamageRange(L, class, npcID, liveSwing)
	local hit, swing, src, seed = self:Predict(L, class, npcID, liveSwing)
	local info = NpcInfo(npcID)
	local cls, exp, mod = 1, nil, FallbackMod(class, L)
	if info then cls, exp, mod = info.cls, info.exp, info.mod end
	L = max(1, min(MAX_LEVEL, floor(L or 1)))
	local byClass = DATA.SPREAD and (DATA.SPREAD[cls] or DATA.SPREAD[1])
	local arr = byClass and (byClass[exp or DefaultExp(L)] or byClass[0])
	local spreadPerSec = (arr and arr[L]) or 0
	local k = (seed and seed > 0) and (hit / seed) or 1
	local half = spreadPerSec * mod * swing * k
	return max(0, hit - half), hit + half, hit, swing, src
end

-- Базовая броня моба (без модификатора конкретного существа)
function M:BaseArmor(L, npcID)
	local info = NpcInfo(npcID)
	local cls = info and info.cls or 1
	L = max(1, min(MAX_LEVEL, floor(L or 1)))
	local arr = DATA.ARMOR and (DATA.ARMOR[cls] or DATA.ARMOR[1])
	return (arr and arr[L]) or (L * 50)
end

function M:NpcClass(npcID)
	local info = NpcInfo(npcID)
	return info and info.cls or 1
end

-- Способности из базы + замеченные в бою.
-- Возвращает список { id, tag, seen, maxHit } и флаги { flee, help }.
local TAGS = { a = "при агро", d = "при смерти", o = "вне боя", i = "прерывание", r = "на дистанции" }
function M:Abilities(npcID)
	local list, flags, index = {}, { flee = false, help = false }, {}
	local raw = npcID and ns.MobSpells and ns.MobSpells[npcID]
	if raw then
		local f, spells = raw:match("^(.-)|(.*)$")
		f = f or ""
		flags.flee = f:find("F", 1, true) and true or false
		flags.help = f:find("C", 1, true) and true or false
		for entry in (spells or ""):gmatch("[^,]+") do
			local id, tag = entry:match("^(%d+):?(.*)$")
			id = tonumber(id)
			if id and not index[id] then
				local label = TAGS[tag]
				if not label and tag and tag:sub(1, 1) == "h" then
					label = "при здоровье <= " .. tag:sub(2) .. "%"
				end
				local e = { id = id, tag = label }
				list[#list + 1] = e
				index[id] = e
			end
		end
	end
	local seen = npcID and DB().spells and DB().spells[npcID]
	if seen then
		for id, maxHit in pairs(seen) do
			local e = index[id]
			if not e then
				e = { id = id }
				list[#list + 1] = e
				index[id] = e
			end
			e.seen = true
			if type(maxHit) == "number" and maxHit > 0 then e.maxHit = maxHit end
		end
	end
	return list, flags
end

function M:Observed(npcID)
	local e = npcID and DB().npc[npcID]
	return e and e.n or 0
end

-- Типичный моб своего уровня (для оценки экипировки)
function M:GenericRawHit(L)
	local k = BandRatio("normal", L)
	return self:BasePerSec(L, 1, nil) * 2.0 * k
end

-- ---------------------------------------------------------------------------
-- Калибровка по журналу боя
-- ---------------------------------------------------------------------------
local units = {}        -- guid -> { level, class, swing }
local unitCount = 0
local disarmed = {}     -- guid -> true
local playerGUID
local shielded = 0      -- активные сильные снижения урона на игроке

local DR_AURAS = {
	[871] = true,     -- Глухая оборона
	[33206] = true,   -- Подавление боли
	[6940] = true,    -- Длань жертвенности
	[64205] = true,   -- Священная жертва
	[47788] = true,   -- Оберегающий дух
}
local DISARMS = { [676] = true, [51722] = true, [41062] = true }

local UNIT_TOKENS = { "target", "focus", "mouseover", "targettarget", "pettarget",
	"party1target", "party2target", "party3target", "party4target" }

local function CacheUnit(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) then return nil end
	local guid = UnitGUID(unit)
	if not guid then return nil end
	local L = UnitLevel(unit)
	if not L or L <= 0 then return nil end
	local e = units[guid]
	if not e then
		if unitCount > 400 then
			units = {}
			unitCount = 0
		end
		e = {}
		units[guid] = e
		unitCount = unitCount + 1
	end
	e.level = L
	e.class = UnitClassification(unit) or "normal"
	local ok, mh = pcall(UnitAttackSpeed, unit)
	if ok and type(mh) == "number" and mh > 0.5 and mh < 6 then
		e.swing = mh
	end
	return e
end
M.CacheUnit = function(_, unit) return CacheUnit(unit) end

local function FindUnit(guid)
	local e = units[guid]
	if e then return e end
	for i = 1, #UNIT_TOKENS do
		local u = UNIT_TOKENS[i]
		if UnitGUID(u) == guid then
			return CacheUnit(u)
		end
	end
	return nil
end

local function StanceMult()
	return ns:StanceMult()
end

local function Record(srcGUID, total)
	local e = FindUnit(srcGUID)
	if not e then return end
	local id = M:NpcID(srcGUID)
	if not id then return end
	local _, armor = UnitArmor("player")
	local dr = ns:ArmorDR(armor or 0, e.level)
	local raw = total / max(0.05, (1 - dr) * StanceMult())

	local info = NpcInfo(id)
	local mod, cls, exp, swing
	if info then
		mod, cls, exp, swing = info.mod, info.cls, info.exp, info.swing
	else
		mod, cls = FallbackMod(e.class, e.level), 1
	end
	swing = swing or e.swing or 2.0
	local seed = M:BasePerSec(e.level, cls, exp) * mod * swing
	if seed <= 0 then return end
	local ratio = max(0.2, min(5, raw / seed))

	local d = DB()
	local n = d.npc[id]
	if not n then
		n = { n = 0, m = 1 }
		d.npc[id] = n
	end
	n.n = n.n + 1
	n.m = n.m + (ratio - n.m) / min(n.n, MAX_N)

	local key = BandKey(e.class, e.level)
	local b = d.band[key]
	if not b then
		b = { n = 0, m = 1 }
		d.band[key] = b
	end
	b.n = b.n + 1
	b.m = b.m + (ratio - b.m) / min(b.n, MAX_N * 5)

	d.hits = (d.hits or 0) + 1
	M.dirty = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
frame:RegisterEvent("UNIT_TARGET")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

frame:SetScript("OnEvent", function(self, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if not ns.db or not ns.db.calib then return end
		local _, sub, srcGUID, _, srcFlags, dstGUID = ...
		if sub == "SWING_DAMAGE" then
			if dstGUID ~= playerGUID or shielded > 0 or disarmed[srcGUID] then return end
			local amount, _, school, resisted, blocked, absorbed, critical, glancing, crushing = select(9, ...)
			if critical or crushing or glancing then return end
			if school and school ~= 1 then return end
			local total = (amount or 0) + (resisted or 0) + (blocked or 0) + (absorbed or 0)
			if total > 0 then
				local ok, err = pcall(Record, srcGUID, total)
				if not ok and ns.ReportError then ns.ReportError(err) end
			end
		elseif sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_CAST_START" or sub == "SPELL_DAMAGE" then
			local id = M:NpcID(srcGUID)
			local spellId = select(9, ...)
			-- только враждебные NPC (0x40) или то, что прилетело в игрока:
			-- заклинания стражников и дружественных NPC в досье не нужны
			local hostile = (dstGUID == playerGUID) or (type(srcFlags) == "number" and bit and bit.band(srcFlags, 0x40) ~= 0)
			if id and spellId and hostile then
				local d = DB()
				local t = d.spells[id]
				if not t then
					t = {}
					d.spells[id] = t
				end
				local cur = t[spellId]
				if cur == nil then
					local count = 0
					for _ in pairs(t) do count = count + 1 end
					if count < 24 then t[spellId] = 0 end
					cur = t[spellId]
				end
				if cur and sub == "SPELL_DAMAGE" and dstGUID == playerGUID then
					local amount = select(12, ...) or 0
					if amount > cur then t[spellId] = amount end
				end
			end
			if sub ~= "SPELL_DAMAGE" then return end
		elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REMOVED" then
			local spellId = select(9, ...)
			if dstGUID == playerGUID and DR_AURAS[spellId] then
				shielded = max(0, shielded + ((sub == "SPELL_AURA_APPLIED") and 1 or -1))
			elseif DISARMS[spellId] then
				disarmed[dstGUID] = (sub == "SPELL_AURA_APPLIED") or nil
			end
		elseif sub == "UNIT_DIED" then
			disarmed[dstGUID] = nil
			if dstGUID == playerGUID then shielded = 0 end
		end
		return
	end
	if event == "PLAYER_LOGIN" then
		playerGUID = UnitGUID("player")
		DB()
	elseif event == "PLAYER_TARGET_CHANGED" then
		CacheUnit("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		CacheUnit("mouseover")
	elseif event == "PLAYER_FOCUS_CHANGED" then
		CacheUnit("focus")
	elseif event == "UNIT_TARGET" then
		local unit = ...
		if unit and unit ~= "player" then CacheUnit(unit .. "target") end
	end
end)

-- После боя: если калибровка заметно изменилась - пересчитать оценки
-- (оценки экипировки зависят от типичного моба своего уровня).
local lastGeneric
ns:On("COMBAT_END", function()
	shielded = 0
	if not M.dirty then return end
	M.dirty = false
	local L = UnitLevel("player") or 1
	local g = M:GenericRawHit(L)
	if not lastGeneric or math.abs(g / lastGeneric - 1) > 0.02 then
		lastGeneric = g
		ns:Fire("DATA_CHANGED")
	end
end)
