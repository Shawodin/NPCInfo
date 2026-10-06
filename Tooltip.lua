-- ============================================================================
-- NPC Info :: Tooltip.lua
-- Компактный блок в подсказке враждебного NPC: опасность, удар, длительность
-- боя и потеря здоровья, особенности. Подробности - по клавише (Shift).
-- ============================================================================
local addonName, ns = ...

local format, floor, min = string.format, math.floor, math.min

local T = {}
ns.Tooltip = T

local C_GREEN, C_RED, C_GRAY, C_YELLOW, C_ORANGE, C_TEXT = "4dd159", "eb4d4d", "8c8c99", "ffc726", "ff9a3c", "ebebf0"
local function C(hex, text) return "|cff" .. hex .. tostring(text) .. "|r" end

local STATUS = {
	[1] = { C_GREEN, "Безопасно" },
	[2] = { C_YELLOW, "Опасно" },
	[3] = { C_RED, "Смертельно" },
}

local function N(v)
	if not v then return "-" end
	if v >= 10000 then return format("%.1fk", v / 1000) end
	return format("%d", floor(v + 0.5))
end

-- Тонкая градиентная линия над блоком
local function Separator(tt, lineIndex)
	local line = _G[tt:GetName() .. "TextLeft" .. lineIndex]
	if not line then return end
	if not tt.npciSep then
		local cr, cg, cb = 0.31, 0.70, 0.91
		local l = tt:CreateTexture(nil, "ARTWORK")
		l:SetTexture("Interface\\Buttons\\WHITE8X8")
		l:SetHeight(1)
		local r = tt:CreateTexture(nil, "ARTWORK")
		r:SetTexture("Interface\\Buttons\\WHITE8X8")
		r:SetHeight(1)
		if l.SetGradientAlpha then
			l:SetGradientAlpha("HORIZONTAL", cr, cg, cb, 0, cr, cg, cb, 0.9)
			r:SetGradientAlpha("HORIZONTAL", cr, cg, cb, 0.9, cr, cg, cb, 0)
		else
			l:SetVertexColor(cr, cg, cb, 0.6)
			r:SetVertexColor(cr, cg, cb, 0.6)
		end
		tt.npciSep = { l, r }
	end
	local l, r = tt.npciSep[1], tt.npciSep[2]
	local w = math.max(10, (tt:GetWidth() - 22) / 2)
	l:ClearAllPoints()
	l:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 0, 2)
	l:SetWidth(w)
	r:ClearAllPoints()
	r:SetPoint("LEFT", l, "RIGHT", 0, 0)
	r:SetWidth(w)
	l:Show() r:Show()
end

local function HideSeparator(tt)
	if tt.npciSep then tt.npciSep[1]:Hide() tt.npciSep[2]:Hide() end
end

local function IsValidMob(unit)
	return unit and UnitExists(unit) and not UnitIsPlayer(unit) and not UnitPlayerControlled(unit)
		and not UnitIsDead(unit) and UnitCanAttack("player", unit)
end

function T:Render(tt)
	if not ns.db or not ns.db.enabled or not ns.db.tooltip then return end
	local _, unit = tt:GetUnit()
	if not unit and UnitExists("mouseover") then unit = "mouseover" end
	if not IsValidMob(unit) then return end
	local guid = UnitGUID(unit) or "?"
	if tt.npciDone == guid then return end

	local r = ns:EvaluateMob(unit)
	if not r then return end
	tt.npciDone = guid
	local detail = ns:DetailActive()
	if r.danger < 2 and not ns.db.tooltipAll and not detail then return end

	local M = ns.MobDB
	local npcID = M:NpcID(guid)
	local st = STATUS[r.danger] or STATUS[2]
	local hits = floor(r.hits)
	tt:AddDoubleLine("|T" .. ns.ICON .. ":12:12:0:0|t |cff" .. ns.HEX .. "NPC Info|r",
		C(st[1], format("~%s ударов - %s", (hits > 99) and "99+" or hits, st[2])), 1, 1, 1, 1, 1, 1)
	tt.npciSepLine = tt:NumLines()

	local lo, hi = M:DamageRange(r.level, r.class, npcID, r.swing)
	local left = format("Удар %s-%s  (%.1f с)", N(lo), N(hi), r.swing or 2)
	local right
	if r.ttk and r.loss then
		local lc = (r.loss >= 1) and C_RED or ((r.loss >= 0.6) and C_YELLOW or C_GREEN)
		local lossText = (r.loss > 9.99) and "999%+" or format("%.0f%%", r.loss * 100)
		right = format("бой ~%.0f с, ", min(999, r.ttk)) .. C(lc, "-" .. lossText .. " здоровья")
	else
		right = C(C_GRAY, "длительность боя неизвестна")
	end
	tt:AddDoubleLine(C(C_TEXT, left), right, 1, 1, 1, 1, 1, 1)

	local _, flags = M:Abilities(npcID)
	local fl = {}
	if flags and flags.flee then fl[#fl + 1] = "убегает за помощью" end
	if flags and flags.help then fl[#fl + 1] = "зовёт на помощь" end
	if (r.crush or 0) > 0 then fl[#fl + 1] = format("сокрушающие удары ~%d%%", floor(r.crush * 100 + 0.5)) end
	if #fl > 0 then tt:AddLine(C(C_ORANGE, table.concat(fl, ", "))) end

	if detail then
		-- способности
		if ns.MobInfo then
			local list = M:Abilities(npcID)
			local seen, names, casts = {}, {}, false
			for i = 1, min(#list, 8) do
				local si = ns.MobInfo:SpellInfo(list[i].id)
				if si then
					if si.cast > 0 then casts = true end
					for _, c in ipairs(si.cats) do
						if not seen[c[1]] and #names < 4 then
							seen[c[1]] = true
							names[#names + 1] = c[1]
						end
					end
				end
			end
			if casts then table.insert(names, 1, "касты") end
			if #names > 0 then
				tt:AddDoubleLine(C(C_GRAY, "Способности"), C(C_ORANGE, table.concat(names, ", ")), 1, 1, 1, 1, 1, 1)
			end
		end
		tt:AddDoubleLine(C(C_GRAY, "Средний удар по вам"), C(C_TEXT, "~" .. N(r.avg)), 1, 1, 1, 1, 1, 1)
		tt:AddDoubleLine(C(C_GRAY, "Избегание / блок"), C(C_TEXT, format("%.0f%% / %.0f%%", r.avoid * 100, r.pBlock * 100)), 1, 1, 1, 1, 1, 1)
		local src = r.src or {}
		local how
		if (src.n or 0) > 0 then how = format("калибровка, %d уд.", src.n)
		elseif src.db then how = (src.band or 0) > 0 and "база + калибровка" or "база AzerothCore"
		else how = "оценка по типу моба" end
		tt:AddDoubleLine(C(C_GRAY, "Данные"), C(C_GRAY, how .. (npcID and (", NPC " .. npcID) or "")), 1, 1, 1, 1, 1, 1)
	elseif ns:DetailKeyName() then
		tt:AddLine(C("5c5c66", ns:DetailKeyName() .. " - подробнее"))
	end
	tt:Show()
	Separator(tt, tt.npciSepLine)
end

local function Clear(tt)
	tt.npciDone = nil
	tt.npciSepLine = nil
	HideSeparator(tt)
end

GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
	local ok, err = pcall(T.Render, T, tt)
	if not ok and ns.ReportError then ns.ReportError(err) end
end)
GameTooltip:HookScript("OnTooltipCleared", Clear)
GameTooltip:HookScript("OnHide", Clear)
GameTooltip:HookScript("OnSizeChanged", function(tt)
	if tt.npciSepLine then pcall(Separator, tt, tt.npciSepLine) end
end)

ns:On("MODIFIER", function()
	if GameTooltip:IsShown() and GameTooltip:GetUnit() and UnitExists("mouseover") then
		GameTooltip:SetUnit("mouseover")
	end
end)
