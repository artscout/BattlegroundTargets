local ADDON, prg = ...
local BGT = prg.BGT
local L = BGT.L

local pairs, ipairs, unpack, type = pairs, ipairs, unpack, type
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local tremove, tinsert = table.remove, table.insert
local issecretvalue = issecretvalue or function() return false end

local Frames = {}
BGT.Frames = Frames

local MAX = 40
local ICONS = "Interface\\AddOns\\BattlegroundTargets\\Media\\BattlegroundTargets-texture-icons"
local ROLE_COORDS = {
	[1] = { 0.75, 1, 0, 0.25 },
	[2] = { 0.75, 1, 0.25, 0.5 },
	[3] = { 0.75, 1, 0.5, 0.75 },
	[4] = { 0.75, 1, 0.75, 1 },
}
local CLASS_ICONS = "Interface\\WorldStateFrame\\Icons-Classes"
local TARGET_ICON = "Interface\\Minimap\\Tracking\\Target"
local FOCUS_ICON = "Interface\\Minimap\\Tracking\\Focus"
local LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local FLAG_ICON = { [0] = "Interface\\WorldStateFrame\\HordeFlag", [1] = "Interface\\WorldStateFrame\\AllianceFlag" }
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local DEFAULT_POS = {
	Friend = { "TOPRIGHT", "CENTER", -220, 160 },
	Enemy = { "TOPLEFT", "CENTER", 220, 160 },
}

Frames.sides = {}
local curves = {}
local widgetPool = {}

-- ---------------------------------------------------------------------------
-- curves / health helpers
-- ---------------------------------------------------------------------------

function Frames:BuildCurves()
	if not C_CurveUtil then return end
	curves.pct = C_CurveUtil.CreateCurve()
	curves.pct:AddPoint(0, 0)
	curves.pct:AddPoint(1, 100)
	curves.color = C_CurveUtil.CreateColorCurve()
	curves.color:AddPoint(0, CreateColor(0.9, 0.1, 0.1, 1))
	curves.color:AddPoint(0.5, CreateColor(0.9, 0.9, 0.1, 1))
	curves.color:AddPoint(1, CreateColor(0.1, 0.8, 0.1, 1))
	self:SetLowThreshold(BGT.opt.LowHealth)
end

function Frames:SetLowThreshold(percent)
	if not C_CurveUtil then return end
	local t = max(0.01, min(0.99, (percent or 30) / 100))
	curves.low = C_CurveUtil.CreateCurve()
	if Enum.LuaCurveType then curves.low:SetType(Enum.LuaCurveType.Step) end
	curves.low:AddPoint(0, 1)
	curves.low:AddPoint(t, 0)
end

local function plainPercent(unit)
	local ok, hp = pcall(UnitHealth, unit)
	local ok2, hpMax = pcall(UnitHealthMax, unit)
	if ok and ok2 and not issecretvalue(hp) and not issecretvalue(hpMax) and hpMax and hpMax > 0 then
		return hp / hpMax
	end
	return 1
end

local function gradientColor(v)
	if v <= 0.5 then
		return 0.9, 0.1 + 1.6 * v, 0.1
	end
	return 0.9 - 1.6 * (v - 0.5), 0.85, 0.1
end

-- ---------------------------------------------------------------------------
-- health widgets (one per player, survives re-sorting)
-- ---------------------------------------------------------------------------

local function createWidget()
	local w = CreateFrame("Frame", nil, UIParent)
	w:Hide()
	w.bar = CreateFrame("StatusBar", nil, w)
	w.bar:SetAllPoints()
	w.bar:SetStatusBarTexture(BAR_TEXTURE)
	w.bar:SetMinMaxValues(0, 1)
	w.bar:SetValue(1)
	w.glow = w.bar:CreateTexture(nil, "OVERLAY")
	w.glow:SetAllPoints()
	w.glow:SetColorTexture(1, 0.1, 0.1, 0.45)
	w.glow:SetAlpha(0)
	w.pct = w.bar:CreateFontString(nil, "OVERLAY")
	w.pct:SetFont(FONT, 10, "OUTLINE")
	w.pct:SetPoint("RIGHT", w.bar, "RIGHT", -2, 0)
	w.pct:SetJustifyH("RIGHT")
	return w
end

function Frames:AttachWidget(p, button)
	local w = p.widget
	if not w then
		w = tremove(widgetPool) or createWidget()
		p.widget = w
		w.bar:SetValue(1)
		w.glow:SetAlpha(0)
		w.pct:SetText("")
	end
	w:SetParent(button)
	w:SetFrameLevel(button:GetFrameLevel() + 1)
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", button.classBg, "TOPLEFT")
	w:SetPoint("BOTTOMRIGHT", button.classBg, "BOTTOMRIGHT")
	w:Show()
end

function Frames:ReleasePlayer(p)
	local w = p.widget
	if w then
		w:Hide()
		w:ClearAllPoints()
		w:SetParent(UIParent)
		tinsert(widgetPool, w)
		p.widget = nil
	end
	if p.button then
		p.button.player = nil
		p.button = nil
	end
end

function Frames:RefreshHealth(p, unit)
	local w = p.widget
	if not w then return end
	local cfg = BGT:Cfg(p.side)
	local color = BGT:ClassInfo(p.class).color
	w.bar:SetShown(cfg.HealthBar)
	w.pct:SetShown(cfg.HealthBar and cfg.HealthText)
	if not cfg.HealthBar then return end
	if p.test then
		local v = p.test.health
		w.bar:SetValue(v)
		if cfg.HealthColor then
			w.bar:SetStatusBarColor(gradientColor(v))
		else
			w.bar:SetStatusBarColor(color.r, color.g, color.b)
		end
		w.pct:SetFormattedText("%d%%", floor(v * 100))
		w.glow:SetAlpha((cfg.LowGlow and v < (BGT.opt.LowHealth or 30) / 100) and 1 or 0)
		return
	end
	unit = unit or BGT:AnyUnit(p)
	if not unit or not UnitExists(unit) then return end
	if UnitHealthPercent then
		local pct = UnitHealthPercent(unit, false)
		w.bar:SetValue(pct)
		if cfg.HealthColor and curves.color then
			local ok, c = pcall(UnitHealthPercent, unit, false, curves.color)
			if ok and c and c.GetRGBA then
				local ok2 = pcall(w.bar.SetStatusBarColor, w.bar, c:GetRGBA())
				if not ok2 then w.bar:SetStatusBarColor(color.r, color.g, color.b) end
			else
				w.bar:SetStatusBarColor(color.r, color.g, color.b)
			end
		else
			w.bar:SetStatusBarColor(color.r, color.g, color.b)
		end
		if cfg.HealthText then
			if curves.pct then
				w.pct:SetFormattedText("%.0f%%", UnitHealthPercent(unit, false, curves.pct))
			else
				w.pct:SetFormattedText("%.0f%%", pct * 100)
			end
		end
		if cfg.LowGlow and curves.low then
			w.glow:SetAlpha(UnitHealthPercent(unit, false, curves.low))
		else
			w.glow:SetAlpha(0)
		end
	else
		local v = plainPercent(unit)
		w.bar:SetValue(v)
		if cfg.HealthColor then w.bar:SetStatusBarColor(gradientColor(v)) else w.bar:SetStatusBarColor(color.r, color.g, color.b) end
		w.pct:SetFormattedText("%d%%", floor(v * 100))
		w.glow:SetAlpha((cfg.LowGlow and v < (BGT.opt.LowHealth or 30) / 100) and 1 or 0)
	end
end

function Frames:RefreshBound(p)
	local w = p.widget
	if not w then return end
	w:SetAlpha((p.test or p.unitCount > 0) and 1 or 0.5)
end

-- ---------------------------------------------------------------------------
-- buttons
-- ---------------------------------------------------------------------------

local function setBorder(b, r, g, bl, a)
	for _, t in ipairs(b.hl) do t:SetColorTexture(r, g, bl, a) end
end

local function borderForPlayer(b)
	local p = b.player
	if p and ((BGT.testMode and BGT.testTarget == p) or (not BGT.testMode and BGT:IsPlayerTarget(p))) then
		setBorder(b, 0.5, 0.5, 0.5, 1)
	else
		setBorder(b, 0, 0, 0, 1)
	end
end

local function createButton(sideName, i, main)
	local b = CreateFrame("Button", "BattlegroundTargets_" .. sideName .. "Button" .. i, main, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetAttribute("type1", "macro")
	b:SetAttribute("type2", "macro")
	b:SetAttribute("macrotext1", "")
	b:SetAttribute("macrotext2", "")
	b:Hide()

	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0, 0, 0, 1)

	b.hl = {}
	for k = 1, 4 do
		local t = b:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0, 0, 0, 1)
		b.hl[k] = t
	end
	b.hl[1]:SetPoint("TOPLEFT"); b.hl[1]:SetPoint("TOPRIGHT"); b.hl[1]:SetHeight(1)
	b.hl[2]:SetPoint("BOTTOMLEFT"); b.hl[2]:SetPoint("BOTTOMRIGHT"); b.hl[2]:SetHeight(1)
	b.hl[3]:SetPoint("TOPLEFT"); b.hl[3]:SetPoint("BOTTOMLEFT"); b.hl[3]:SetWidth(1)
	b.hl[4]:SetPoint("TOPRIGHT"); b.hl[4]:SetPoint("BOTTOMRIGHT"); b.hl[4]:SetWidth(1)

	b.range = b:CreateTexture(nil, "BORDER")
	b.role = b:CreateTexture(nil, "ARTWORK")
	b.role:SetTexture(ICONS)
	b.spec = b:CreateTexture(nil, "ARTWORK")
	b.spec:SetTexCoord(5 / 64, 59 / 64, 5 / 64, 59 / 64)
	b.classIcon = b:CreateTexture(nil, "ARTWORK")
	b.classIcon:SetTexture(CLASS_ICONS)
	b.classBg = b:CreateTexture(nil, "BORDER")

	b.text = CreateFrame("Frame", nil, b)
	b.text:SetAllPoints()
	b.name = b.text:CreateFontString(nil, "OVERLAY")
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(false)
	b.specText = b.text:CreateFontString(nil, "OVERLAY")
	b.specText:SetJustifyH("RIGHT")
	b.specText:SetWordWrap(false)
	b.count = b.text:CreateFontString(nil, "OVERLAY")
	b.count:SetJustifyH("CENTER")

	b.ind = CreateFrame("Frame", nil, b)
	b.ind:SetAllPoints()
	b.ind.target = b.ind:CreateTexture(nil, "OVERLAY")
	b.ind.target:SetTexture(TARGET_ICON)
	b.ind.focus = b.ind:CreateTexture(nil, "OVERLAY")
	b.ind.focus:SetTexture(FOCUS_ICON)
	b.ind.flag = b.ind:CreateTexture(nil, "OVERLAY")
	b.ind.flag:SetTexCoord(5 / 32, 27 / 32, 5 / 32, 27 / 32)
	b.ind.leader = b.ind:CreateTexture(nil, "OVERLAY")
	b.ind.leader:SetTexture(LEADER_ICON)
	for _, t in pairs({ b.ind.target, b.ind.focus, b.ind.flag, b.ind.leader }) do t:Hide() end

	b:SetScript("OnEnter", function(self) setBorder(self, 1, 1, 0.49, 1) end)
	b:SetScript("OnLeave", function(self) borderForPlayer(self) end)
	return b
end

local function createSide(sideName)
	local main = CreateFrame("Frame", "BattlegroundTargets_" .. sideName .. "MainFrame", UIParent)
	main:SetSize(175, 20)
	main:SetMovable(true)
	main:SetClampedToScreen(true)
	main:Hide()
	local S = { name = sideName, main = main, buttons = {} }
	for i = 1, MAX do S.buttons[i] = createButton(sideName, i, main) end

	local mover = CreateFrame("Button", nil, main)
	mover:SetAllPoints()
	mover:SetFrameLevel(main:GetFrameLevel() + 10)
	mover:RegisterForDrag("LeftButton")
	mover.bg = mover:CreateTexture(nil, "OVERLAY")
	mover.bg:SetAllPoints()
	mover.bg:SetColorTexture(0.2, 0.6, 0.2, 0.35)
	mover.text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mover.text:SetPoint("CENTER")
	mover.text:SetText((sideName == "Friend" and L["Friendly Players"] or L["Enemy Players"]) .. "\n" .. L["click & move"])
	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		main:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		main:StopMovingOrSizing()
		Frames:SavePosition(sideName)
	end)
	mover:Hide()
	S.mover = mover
	return S
end

function Frames:Init()
	self:BuildCurves()
	for _, sideName in ipairs(BGT.SIDES) do
		self.sides[sideName] = createSide(sideName)
		self:Layout(sideName)
		self:RestorePosition(sideName)
	end
end

-- ---------------------------------------------------------------------------
-- positions
-- ---------------------------------------------------------------------------

function Frames:PosKey(sideName)
	return sideName .. BGT.bracket
end

function Frames:SavePosition(sideName)
	if InCombatLockdown() then
		BGT.pending.position = true
		return
	end
	local S = self.sides[sideName]
	local point, _, relPoint, x, y = S.main:GetPoint(1)
	if not point then return end
	BGT.opt.FramePosition[self:PosKey(sideName)] = { point = point, rel = relPoint, x = x, y = y }
end

function Frames:SaveAllPositions()
	for _, sideName in ipairs(BGT.SIDES) do self:SavePosition(sideName) end
end

function Frames:RestorePosition(sideName)
	if InCombatLockdown() then
		BGT.pending.layout = true
		return
	end
	local S = self.sides[sideName]
	local pos = BGT.opt.FramePosition[self:PosKey(sideName)]
	S.main:ClearAllPoints()
	if pos then
		S.main:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x, pos.y)
	else
		local d = DEFAULT_POS[sideName]
		S.main:SetPoint(d[1], UIParent, d[2], d[3], d[4])
	end
end

-- ---------------------------------------------------------------------------
-- layout
-- ---------------------------------------------------------------------------

local function indicatorLeft(quad, width, pos)
	if pos <= 0 then return -quad end
	if pos >= 100 then return width end
	return ((quad + width) * pos / 100) - quad
end

function Frames:Layout(sideName)
	if InCombatLockdown() then
		BGT.pending.layout = true
		return
	end
	local S = self.sides[sideName]
	local cfg = BGT:Cfg(sideName)
	local W, H = cfg.Width, cfg.Height
	local h2 = H - 2
	local n = BGT.bracket
	local rows = (cfg.Rows > 0) and min(cfg.Rows, n) or n
	local cols = ceil(n / rows)
	local rangeW = cfg.Range and max(3, floor(h2 / 3)) or 0
	local countW = cfg.TargetCount and (cfg.FontSize * 1.5) or 0
	local fontSize = cfg.FontSize

	S.main:SetScale(cfg.Scale)
	S.main:SetSize(cols * W + (cols - 1) * cfg.Space, rows * H)

	for i = 1, MAX do
		local b = S.buttons[i]
		b:SetSize(W, H)
		b:ClearAllPoints()
		local col = floor((i - 1) / rows)
		local row = (i - 1) % rows
		if row == 0 then
			b:SetPoint("TOPLEFT", S.main, "TOPLEFT", col * (W + cfg.Space), 0)
		else
			b:SetPoint("TOPLEFT", S.buttons[i - 1], "BOTTOMLEFT", 0, 0)
		end

		local x = 1
		b.range:ClearAllPoints()
		if cfg.Range then
			b.range:SetPoint("TOPLEFT", b, "TOPLEFT", x, -1)
			b.range:SetSize(rangeW, h2)
			b.range:Show()
			x = x + rangeW
		else
			b.range:Hide()
		end
		for _, key in ipairs({ "role", "spec", "classIcon" }) do
			local on = (key == "role" and cfg.Role) or (key == "spec" and cfg.SpecIcon) or (key == "classIcon" and cfg.ClassIcon)
			local t = b[key]
			t:ClearAllPoints()
			if on then
				t:SetPoint("TOPLEFT", b, "TOPLEFT", x, -1)
				t:SetSize(h2, h2)
				t:Show()
				x = x + h2
			else
				t:Hide()
			end
		end
		b.classBg:ClearAllPoints()
		b.classBg:SetPoint("TOPLEFT", b, "TOPLEFT", x, -1)
		b.classBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)

		b.count:ClearAllPoints()
		b.count:SetFont(FONT, max(6, fontSize - 1), "OUTLINE")
		if cfg.TargetCount then
			b.count:SetPoint("RIGHT", b, "RIGHT", -2, 0)
			b.count:SetWidth(countW)
			b.count:Show()
		else
			b.count:Hide()
		end
		b.specText:ClearAllPoints()
		b.specText:SetFont(FONT, max(6, fontSize - 2), "")
		b.specText:SetPoint("RIGHT", b, "RIGHT", -2 - countW, 0)
		b.specText:SetShown(cfg.SpecText)
		b.name:ClearAllPoints()
		b.name:SetFont(FONT, fontSize, "")
		b.name:SetPoint("LEFT", b.classBg, "LEFT", 2, 0)
		b.name:SetPoint("RIGHT", b, "RIGHT", -2 - countW - (cfg.SpecText and W * 0.3 or 0), 0)
		if b.player and b.player.widget then
			b.player.widget.pct:SetFont(FONT, max(6, fontSize - 2), "OUTLINE")
		end

		local quad = h2 * cfg.TargetScale
		b.ind.target:ClearAllPoints()
		b.ind.target:SetSize(quad, quad)
		b.ind.target:SetPoint("LEFT", b, "LEFT", indicatorLeft(quad, W, cfg.TargetPos), 0)
		quad = h2 * cfg.FocusScale
		b.ind.focus:ClearAllPoints()
		b.ind.focus:SetSize(quad, quad)
		b.ind.focus:SetPoint("LEFT", b, "LEFT", indicatorLeft(quad, W, cfg.FocusPos), 0)
		quad = h2 * cfg.FlagScale
		b.ind.flag:ClearAllPoints()
		b.ind.flag:SetSize(quad, quad)
		b.ind.flag:SetPoint("LEFT", b, "LEFT", indicatorLeft(quad, W, cfg.FlagPos), 0)
		local lsize = h2 / 1.25
		b.ind.leader:ClearAllPoints()
		b.ind.leader:SetSize(lsize, lsize)
		b.ind.leader:SetPoint("CENTER", b, "LEFT", 0, 0)
	end
	for _, w in ipairs(widgetPool) do w.pct:SetFont(FONT, max(6, fontSize - 2), "OUTLINE") end
end

-- ---------------------------------------------------------------------------
-- assignment / refresh
-- ---------------------------------------------------------------------------

function Frames:SetMacro(b, p)
	if InCombatLockdown() then return end
	if not p then
		b:SetAttribute("macrotext1", "")
		b:SetAttribute("macrotext2", "")
		return
	end
	b:SetAttribute("macrotext1", "/targetexact " .. p.name)
	local isFocus = (not BGT.testMode) and BGT:IsPlayerFocus(p)
	b:SetAttribute("macrotext2", "/targetexact " .. p.name .. (isFocus and "\n/clearfocus" or "\n/focus") .. "\n/targetlasttarget")
end

function Frames:AssignButtons(side)
	local S = self.sides[side.name]
	if not S then return end
	for i = 1, MAX do
		local b = S.buttons[i]
		local p = side.list[i]
		if p then
			if b.player ~= p then
				if b.player then b.player.button = nil end
				b.player = p
				p.button = b
			end
			self:AttachWidget(p, b)
			self:SetMacro(b, p)
			self:RefreshPlayer(p)
			b:Show()
		else
			if b.player then
				b.player.button = nil
				b.player = nil
			end
			self:SetMacro(b, nil)
			b:Hide()
		end
	end
end

function Frames:RefreshPlayer(p)
	local b = p.button
	if not b then return end
	local cfg = BGT:Cfg(p.side)
	local cls = BGT:ClassInfo(p.class)
	local c = cls.color
	b.classBg:SetColorTexture(c.r * 0.5, c.g * 0.5, c.b * 0.5, 1)
	b.name:SetText(BGT:DisplayName(p, cfg.Realm))
	b.name:SetTextColor(1, 1, 1)
	b.role:SetTexCoord(unpack(ROLE_COORDS[p.role] or ROLE_COORDS[4]))
	if cfg.SpecIcon then
		if p.specIcon then
			b.spec:SetTexture(p.specIcon)
			b.spec:Show()
		else
			b.spec:Hide()
		end
	end
	b.classIcon:SetTexCoord(unpack(cls.coords))
	if cfg.SpecText then
		if p.specText and (p.specSecret or p.specText ~= "") then
			b.specText:SetText(p.specText)
		else
			b.specText:SetText("")
		end
		b.specText:SetTextColor(0.8, 0.8, 0.8)
	end
	self:RefreshCount(p)
	self:RefreshRange(p)
	self:RefreshIndicators(p)
	self:RefreshBound(p)
	self:RefreshHealth(p)
	local w = p.widget
	if w then w.pct:SetFont(FONT, max(6, cfg.FontSize - 2), "OUTLINE") end
end

function Frames:RefreshCount(p)
	local b = p.button
	if not b then return end
	if p.targetedBy > 0 then
		b.count:SetText(p.targetedBy)
		b.count:SetTextColor(p.side == "Enemy" and 0.4 or 1, 1, p.side == "Enemy" and 0.4 or 1)
	else
		b.count:SetText("")
	end
end

function Frames:RefreshRange(p)
	local b = p.button
	if not b then return end
	if not BGT:Cfg(p.side).Range then return end
	if p.inRange then
		local c = BGT:ClassInfo(p.class).color
		b.range:SetColorTexture(c.r, c.g, c.b, 1)
	elseif p.inRange == false then
		b.range:SetColorTexture(0.15, 0.15, 0.15, 1)
	else
		b.range:SetColorTexture(0, 0, 0, 1)
	end
end

function Frames:RefreshIndicators(p)
	local b = p.button
	if not b then return end
	local cfg = BGT:Cfg(p.side)
	local side = BGT.sides[p.side]
	local isTarget, isFocus
	if BGT.testMode then
		isTarget = BGT.testTarget == p
		isFocus = BGT.testFocus == p
	else
		isTarget = BGT:IsPlayerTarget(p)
		isFocus = BGT:IsPlayerFocus(p)
	end
	b.ind.target:SetShown(cfg.Target and isTarget)
	b.ind.focus:SetShown(cfg.Focus and isFocus)
	if cfg.Flag and side.carrier == p then
		local faction = p.side == "Enemy" and BGT.myFaction or (1 - BGT.myFaction)
		b.ind.flag:SetTexture(FLAG_ICON[faction] or FLAG_ICON[0])
		b.ind.flag:Show()
	else
		b.ind.flag:Hide()
	end
	b.ind.leader:SetShown(cfg.Leader and side.leader == p)
	borderForPlayer(b)
	if not BGT.testMode then self:SetMacro(b, p) end
end

function Frames:RefreshAll()
	for _, sideName in ipairs(BGT.SIDES) do
		for _, p in ipairs(BGT.sides[sideName].list) do self:RefreshPlayer(p) end
	end
end

-- ---------------------------------------------------------------------------
-- visibility / mover
-- ---------------------------------------------------------------------------

function Frames:SetVisible(on, force)
	if InCombatLockdown() then
		self.pendingVisible = { on, force }
		return
	end
	self.pendingVisible = nil
	for _, sideName in ipairs(BGT.SIDES) do
		local S = self.sides[sideName]
		local show = on and (force or BGT:Cfg(sideName).Enable)
		S.main:SetShown(show)
	end
end

function Frames:OnRegenEnabled()
	if self.pendingVisible then
		local v = self.pendingVisible
		self:SetVisible(v[1], v[2])
	end
end

function Frames:SetMover(on)
	for _, sideName in ipairs(BGT.SIDES) do
		self.sides[sideName].mover:SetShown(on)
	end
end
