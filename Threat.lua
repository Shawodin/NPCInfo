-- ============================================================================
-- NPC Info :: Threat.lua
-- Оценка угрозы моба для текущего персонажа (любой класс):
-- таблица атаки моба 3.3.5 против ваших брони, Защиты, уклонения,
-- парирования и блока; сколько ударов вы выдержите, сколько длится бой
-- (по вашему реальному урону) и сколько здоровья вы потеряете.
-- ============================================================================
local addonName, ns = ...

local max, min = math.max, math.min

local function IsShieldEquipped()
	local link = GetInventoryItemLink("player", 17)
	if not link then return false end
	local _, _, _, _, _, _, _, _, loc = GetItemInfo(link)
	return loc == "INVTYPE_SHIELD"
end

-- Защитные показатели игрока
function ns:PlayerDefense()
	local p = {}
	p.level = UnitLevel("player") or 1
	p.hpMax = max(1, UnitHealthMax("player") or 1)
	p.hp = UnitHealth("player") or p.hpMax
	local _, armor = UnitArmor("player")
	p.armor = armor or 0
	local base, mod = UnitDefense("player")
	p.def = (base or 5 * p.level) + (mod or 0)
	p.dodge = (GetDodgeChance and GetDodgeChance() or 0) / 100
	p.parry = (GetParryChance and GetParryChance() or 0) / 100
	p.shield = IsShieldEquipped()
	p.block = p.shield and ((GetBlockChance and GetBlockChance() or 0) / 100) or 0
	p.bv = p.shield and (GetShieldBlock and GetShieldBlock() or 0) or 0
	p.stance = ns:StanceMult()
	return p
end

-- info: { level, class, npcID, swing (живая скорость) }
function ns:EvaluateMob(unit)
	if type(unit) ~= "string" or not UnitExists(unit) then return nil end
	local M = self.MobDB
	if not M then return nil end
	local p = self:PlayerDefense()
	local pl = p.level

	local L = UnitLevel(unit)
	local skull = false
	if not L or L <= 0 then skull = true; L = pl + 10 end
	local class = UnitClassification(unit) or "normal"
	local elite = (class == "elite" or class == "rareelite" or class == "worldboss")

	local liveSwing
	local ok, mh = pcall(UnitAttackSpeed, unit)
	if ok and type(mh) == "number" and mh > 0.5 and mh < 6 then liveSwing = mh end

	M:CacheUnit(unit)
	local npcID = M:NpcID(UnitGUID(unit))
	local rawHit, swing, src = M:Predict(L, class, npcID, liveSwing)
	swing = liveSwing or swing or 2.0

	local dr = self:ArmorDR(p.armor, L)
	local h = rawHit * (1 - dr) * p.stance

	-- Таблица атаки моба: промах/уклонение/парирование -> блок -> крит -> сокрушение -> удар
	local defGap = 5 * L - p.def                         -- навык моба против вашей Защиты
	local miss = max(0, min(0.6, 0.05 - defGap * 0.0004))
	local cut = max(0, 0.002 * (L - pl))                 -- моб выше уровнем режет избегание
	local dodge = max(0, p.dodge - cut)
	local parry = max(0, p.parry - cut)
	local block = max(0, p.block - cut)
	local crit = max(0, 0.05 + defGap * 0.0004)
	local crush = 0
	if L - pl >= 4 then crush = min(0.6, max(0, 5 * (L - pl) * 0.02 - 0.15)) end

	local rest = 1 - min(1, miss + dodge + parry)
	local pBlock = min(rest, block); rest = rest - pBlock
	local pCrit = min(rest, crit); rest = rest - pCrit
	local pCrush = min(rest, crush); rest = rest - pCrush
	local pHit = max(0, rest)
	local avg = pHit * h + pCrit * 2 * h + pCrush * 1.5 * h + pBlock * max(0, h - p.bv)
	avg = max(h * 0.05, avg)

	local r = {
		level = L, skull = skull, class = class, elite = elite, diff = L - pl,
		rawHit = rawHit, swing = swing, src = src, hit = h, avg = avg, dr = dr,
		hits = p.hp / avg, avoid = min(1, miss + dodge + parry),
		pBlock = pBlock, pCrit = pCrit, pCrush = pCrush, crush = crush,
	}
	r.seconds = r.hits * swing
	local worst = (crush > 0) and 1.5 * h or 2 * h
	r.burstLethal = 3 * worst >= p.hp
	r.hpPct = p.hp / p.hpMax

	-- Длительность боя по вашему реальному урону. Если сервер отдаёт здоровье
	-- NPC в процентах (макс. 100), для мобов от 8 ур. время боя не считается.
	local mobHp, mobHpMax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
	r.hpPercent = (mobHpMax == 100 and L >= 8)
	r.armor = M:BaseArmor(L, npcID)
	local dps, n = self.DPS:Get(pl)
	-- оценка без боёв не учитывает броню моба; реальные бои её уже содержат
	if n == 0 then dps = dps * (1 - self:ArmorDR(r.armor, pl)) end
	r.myDps, r.dpsSamples = dps, n
	if dps > 0 and mobHp > 0 and not r.hpPercent then
		r.ttk = mobHp / dps
		r.loss = r.ttk * avg / swing / max(1, p.hp)
	end

	if skull or class == "worldboss" or r.hits < 4 or r.burstLethal or (r.loss and r.loss >= 1.0) then
		r.danger = 3
	elseif r.hits < 8 or elite or r.diff >= 3 or crush > 0 or r.hpPct < 0.5 or (r.loss and r.loss >= 0.6) then
		r.danger = 2
	else
		r.danger = 1
	end
	return r
end
