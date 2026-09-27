local ADDON, prg = ...

local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local strmatch, strfind, gsub, format = string.match, string.find, string.gsub, string.format
local wipe, tinsert, tsort = table.wipe, table.insert, table.sort
local max, ceil, random = math.max, math.ceil, math.random
local GetTime = GetTime
local issecretvalue = issecretvalue or function() return false end

local L = prg.L or {}
for k, v in pairs(L) do if type(v) ~= "string" then L[k] = tostring(k) end end
setmetatable(L, { __index = function(_, k) return k end })
local FLG = prg.FLG or {}
local TSL, utf8replace = prg.TSL, prg.utf8replace

local BGT = CreateFrame("Frame", "BattlegroundTargets_Core")
prg.BGT = BGT
BGT.L = L
BGT.VERSION = 100

local SIDES = { "Friend", "Enemy" }
BGT.SIDES = SIDES
local BRACKETS = { 10, 15, 40 }
BGT.BRACKETS = BRACKETS

local HEALER, TANK, DAMAGER, UNKNOWN = 1, 2, 3, 4
BGT.HEALER, BGT.TANK, BGT.DAMAGER, BGT.UNKNOWN = HEALER, TANK, DAMAGER, UNKNOWN
local ROLE_BY_TOKEN = { HEALER = HEALER, TANK = TANK, DAMAGER = DAMAGER }

local SURNAME_SEP = (Constants and Constants.CharacterNameSeparatorConsts
	and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "

local SCORE_INTERVAL = 2
local SCORE_THROTTLE = 0.8
local RANGE_INTERVAL = 0.25
local CARRIER_INTERVAL = 1

local BG_TEAM_SIZE = {
	[489] = 10, [2996] = 10, [3005] = 10,
	[529] = 15, [566] = 15,
	[30] = 40,
}

local RANGE_SPELLS = {
	Enemy = {
		DRUID = 8921, HUNTER = 75, MAGE = 116, PALADIN = 20271, PRIEST = 589,
		ROGUE = 2764, SHAMAN = 403, WARLOCK = 686, WARRIOR = 100,
	},
	Friend = {
		DRUID = 5185, MAGE = 1459, PALADIN = 635, PRIEST = 2050,
		SHAMAN = 331, WARLOCK = 5697,
	},
}

BGT.inMatch = false
BGT.inCombat = false
BGT.testMode = false
BGT.bracket = 10
BGT.myFaction = 0
BGT.pending = {}
BGT.unitOwner = {}
BGT.classes = {}
BGT.classOrder = {}

local function newSide(name)
	return {
		name = name,
		list = {},
		players = {},
		byName = {},
		byShort = {},
		byFirst = {},
		firstCount = {},
		carrier = nil,
		leader = nil,
	}
end

BGT.sides = { Friend = newSide("Friend"), Enemy = newSide("Enemy") }

-- ---------------------------------------------------------------------------
-- options
-- ---------------------------------------------------------------------------

local function bracketDefaults(side, size)
	local big = size == 40
	return {
		Enable = side == "Enemy",
		Scale = 1,
		Width = big and 100 or 175,
		Height = big and 16 or 20,
		Rows = big and 10 or 0,
		Space = 0,
		SortBy = 1,
		ClassOrder = 3,
		Role = true,
		SpecIcon = false,
		SpecText = not big,
		ClassIcon = false,
		Realm = not big,
		Leader = true,
		TargetCount = true,
		HealthBar = true,
		HealthText = not big,
		HealthColor = true,
		LowGlow = true,
		Range = false,
		Target = true,
		TargetScale = big and 1 or 1.5,
		TargetPos = big and 85 or 100,
		Focus = true,
		FocusScale = 1,
		FocusPos = 70,
		Flag = not big,
		FlagScale = big and 1 or 1.2,
		FlagPos = big and 100 or 60,
		FontSize = big and 10 or 12,
	}
end

local function merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			merge(dst[k], v)
		elseif dst[k] == nil or type(dst[k]) ~= type(v) then
			dst[k] = v
		end
	end
end

function BGT:InitOptions()
	local opt = BattlegroundTargets_Options
	if type(opt) ~= "table" or (opt.version or 0) < self.VERSION then
		opt = { version = self.VERSION }
		BattlegroundTargets_Options = opt
	end
	local defaults = {
		version = self.VERSION,
		MinimapButton = true,
		MinimapButtonPos = -90,
		Transliteration = false,
		LowHealth = 30,
		FramePosition = {},
		Friend = {},
		Enemy = {},
	}
	for _, side in ipairs(SIDES) do
		for _, size in ipairs(BRACKETS) do
			defaults[side][size] = bracketDefaults(side, size)
		end
	end
	merge(opt, defaults)
	self.opt = opt
end

function BGT:Cfg(side, bracket)
	return self.opt[side][bracket or self.bracket]
end

-- ---------------------------------------------------------------------------
-- classes / specs
-- ---------------------------------------------------------------------------

function BGT:BuildClassTable()
	wipe(self.classes)
	wipe(self.classOrder)
	local numSpecsFn = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID or GetNumSpecializationsForClassID
	local specFn = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID or GetSpecializationInfoForClassID
	local numClasses = (GetNumClasses and GetNumClasses()) or 13
	for classID = 1, numClasses do
		local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo(classID)
		if info and info.classFile then
			local token = info.classFile
			local color = (C_ClassColor and C_ClassColor.GetClassColor(token)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
			local cls = {
				id = classID,
				token = token,
				name = info.className,
				color = color or { r = 0.7, g = 0.7, b = 0.7 },
				coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token] or { 0, 1, 0, 1 },
				specs = {},
				specList = {},
			}
			local ok, num = pcall(numSpecsFn, classID)
			if ok and type(num) == "number" then
				for i = 1, num do
					for _, gender in ipairs({ 2, 3 }) do
						local ok2, id, name, _, icon, role = pcall(specFn, classID, i, gender)
						if ok2 and name and name ~= "" then
							local rec = { id = id, name = name, icon = icon, role = ROLE_BY_TOKEN[role] or DAMAGER }
							cls.specs[name] = rec
							if gender == 2 then tinsert(cls.specList, rec) end
						end
					end
				end
			end
			local extra = prg.TLT and prg.TLT[token]
			if extra and extra.spec then
				for _, s in ipairs(extra.spec) do
					if s.specName and not cls.specs[s.specName] then
						cls.specs[s.specName] = { id = s.specID, name = s.specName, icon = s.icon, role = s.role or DAMAGER }
					end
				end
			end
			self.classes[token] = cls
		end
	end
	local order = CLASS_SORT_ORDER or {}
	for i, token in ipairs(order) do self.classOrder[token] = i end
	for token in pairs(self.classes) do
		if not self.classOrder[token] then self.classOrder[token] = 100 end
	end
end

function BGT:ClassInfo(token)
	return self.classes[token] or self.classes.WARRIOR or { color = { r = 0.7, g = 0.7, b = 0.7 }, coords = { 0, 1, 0, 1 }, specs = {}, specList = {} }
end

-- ---------------------------------------------------------------------------
-- names
-- ---------------------------------------------------------------------------

local function stripRealm(name)
	return (gsub(name, "%-[^%-]*$", ""))
end

local function firstName(short)
	return strmatch(short, "^([^" .. SURNAME_SEP .. "]+)") or short
end

function BGT:DisplayName(p, showRealm)
	local name = showRealm and p.name or p.short
	if self.opt.Transliteration and TSL and utf8replace then
		p.trans = p.trans or utf8replace(name, TSL)
		return p.trans
	end
	return name
end

function BGT:MyNameKeys()
	local keys = {}
	local name, second = UnitName("player")
	local _, realm = UnitFullName("player")
	if issecretvalue(name) then return keys end
	if issecretvalue(second) then second = nil end
	if issecretvalue(realm) then realm = nil end
	if second == realm then second = nil end
	keys[name] = true
	if second and second ~= "" then keys[name .. SURNAME_SEP .. second] = true end
	if realm and realm ~= "" then
		keys[name .. "-" .. realm] = true
		if second and second ~= "" then keys[name .. SURNAME_SEP .. second .. "-" .. realm] = true end
	end
	return keys
end

-- ---------------------------------------------------------------------------
-- roster from the score table
-- ---------------------------------------------------------------------------

local function classKey(self, p, detail)
	if detail == 1 then
		return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.class]) or p.class
	elseif detail == 2 then
		return p.class
	end
	return self.classOrder[p.class] or 100
end

local function makeSorter(self, mode, detail)
	local function cls(p) return classKey(self, p, detail) end
	if mode == 1 then
		return function(a, b)
			if a.role ~= b.role then return a.role < b.role end
			local ca, cb = cls(a), cls(b)
			if ca ~= cb then return ca < cb end
			return a.name < b.name
		end
	elseif mode == 2 then
		return function(a, b)
			if a.role ~= b.role then return a.role < b.role end
			return a.name < b.name
		end
	elseif mode == 3 then
		return function(a, b)
			local ca, cb = cls(a), cls(b)
			if ca ~= cb then return ca < cb end
			if a.role ~= b.role then return a.role < b.role end
			return a.name < b.name
		end
	elseif mode == 4 then
		return function(a, b)
			local ca, cb = cls(a), cls(b)
			if ca ~= cb then return ca < cb end
			return a.name < b.name
		end
	end
	return function(a, b) return a.name < b.name end
end

function BGT:IndexSide(side)
	wipe(side.byName); wipe(side.byShort); wipe(side.byFirst); wipe(side.firstCount)
	for _, p in ipairs(side.list) do
		side.byName[p.name] = p
		side.byShort[p.short] = side.byShort[p.short] or p
		side.firstCount[p.first] = (side.firstCount[p.first] or 0) + 1
		side.byFirst[p.first] = p
	end
	for first, n in pairs(side.firstCount) do
		if n > 1 then side.byFirst[first] = nil end
	end
end

function BGT:SortSide(side)
	local cfg = self:Cfg(side.name)
	tsort(side.list, makeSorter(self, cfg.SortBy, cfg.ClassOrder))
	for i, p in ipairs(side.list) do p.index = i end
	self:IndexSide(side)
end

local function newPlayer(side, name, class)
	local short = stripRealm(name)
	return {
		side = side,
		name = name,
		short = short,
		first = firstName(short),
		class = class,
		role = UNKNOWN,
		units = {},
		unitCount = 0,
		targetedBy = 0,
	}
end

function BGT:ResolveSpec(p, spec, secret)
	p.specSecret = secret
	p.specText = spec
	p.specIcon = nil
	p.role = UNKNOWN
	if secret or not spec or spec == "" then return end
	local rec = self:ClassInfo(p.class).specs[spec]
	if rec then
		p.role = rec.role
		p.specIcon = rec.icon
	end
end

function BGT:UpdateRoster()
	if self.testMode then return end
	local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
	if n == 0 then return end
	local rows = {}
	local mine = self:MyNameKeys()
	local myFaction
	for i = 1, n do
		local info = C_PvP.GetScoreInfo(i)
		if info then
			local name, faction, class = info.name, info.faction, info.classToken
			if name and name ~= "" and not issecretvalue(name) and not issecretvalue(faction) and not issecretvalue(class) then
				local spec = info.talentSpec
				local secret = issecretvalue(spec)
				tinsert(rows, { name = name, faction = faction, class = class or "WARRIOR", spec = spec, secret = secret })
				if (mine[name] or mine[stripRealm(name)]) and type(faction) == "number" then
					myFaction = faction
				end
			end
		end
	end
	if #rows == 0 then return end
	if myFaction ~= nil then self.myFaction = myFaction end

	for _, side in pairs(self.sides) do
		wipe(side.list)
		for _, p in pairs(side.players) do p.seen = false end
	end
	for _, row in ipairs(rows) do
		local sideName = (row.faction == self.myFaction) and "Friend" or "Enemy"
		local side = self.sides[sideName]
		local p = side.players[row.name]
		if p and p.class ~= row.class then
			self:ReleasePlayer(p)
			p = nil
		end
		if not p then
			p = newPlayer(sideName, row.name, row.class)
			side.players[row.name] = p
		end
		p.seen = true
		self:ResolveSpec(p, row.spec, row.secret)
		tinsert(side.list, p)
	end
	for _, side in pairs(self.sides) do
		for name, p in pairs(side.players) do
			if not p.seen then
				self:ReleasePlayer(p)
				side.players[name] = nil
			end
		end
		self:SortSide(side)
	end
	self:UpdateBracket()
	self:RebindAll()
	self:ApplyRoster()
end

function BGT:ReleasePlayer(p)
	for unit in pairs(p.units) do
		if self.unitOwner[unit] == p then self.unitOwner[unit] = nil end
	end
	wipe(p.units)
	p.unitCount = 0
	for _, side in pairs(self.sides) do
		if side.carrier == p then side.carrier = nil end
		if side.leader == p then side.leader = nil end
	end
	if self.Frames then self.Frames:ReleasePlayer(p) end
end

function BGT:ApplyRoster()
	if InCombatLockdown() then
		self.pending.roster = true
		return
	end
	self.pending.roster = nil
	for _, sideName in ipairs(SIDES) do
		self.Frames:AssignButtons(self.sides[sideName])
	end
	self:UpdateTargetCounts()
	self:UpdateLeader()
end

-- ---------------------------------------------------------------------------
-- player lookup by unit / name
-- ---------------------------------------------------------------------------

function BGT:FindPlayerByName(name, preferSide)
	if not name or issecretvalue(name) then return end
	local order = preferSide == "Friend" and { "Friend", "Enemy" } or { "Enemy", "Friend" }
	for _, key in ipairs({ "byName", "byShort" }) do
		for _, sideName in ipairs(order) do
			local p = self.sides[sideName][key][name]
			if p then return p end
		end
	end
	local short = stripRealm(name)
	for _, sideName in ipairs(order) do
		local side = self.sides[sideName]
		local p = side.byShort[short] or side.byFirst[firstName(short)]
		if p then return p end
	end
end

function BGT:FindPlayerByUnit(unit)
	local name, second = UnitName(unit)
	if not name or issecretvalue(name) then return end
	local _, realm = UnitFullName(unit)
	if issecretvalue(second) then second = nil end
	if issecretvalue(realm) then realm = nil end
	if second == realm then second = nil end
	local preferSide = (strfind(unit, "^raid%d+$") or strfind(unit, "^party%d+$") or unit == "player") and "Friend" or "Enemy"
	local p
	if second and second ~= "" then
		local full = name .. SURNAME_SEP .. second
		p = self:FindPlayerByName(full, preferSide)
		if not p and realm and realm ~= "" then p = self:FindPlayerByName(full .. "-" .. realm, preferSide) end
		if p then return p end
	end
	p = self:FindPlayerByName(name, preferSide)
	if not p and realm and realm ~= "" then p = self:FindPlayerByName(name .. "-" .. realm, preferSide) end
	return p
end

-- ---------------------------------------------------------------------------
-- unit binding
-- ---------------------------------------------------------------------------

local bindDirty, healthDirty = {}, {}
local targetDirty, rosterDirty = false, false

function BGT:AnyUnit(p)
	for unit in pairs(p.units) do
		if UnitExists(unit) then return unit end
	end
end

function BGT:BindUnit(unit)
	local old = self.unitOwner[unit]
	local p
	if UnitExists(unit) and UnitIsPlayer(unit) then
		p = self:FindPlayerByUnit(unit)
	end
	if old ~= p then
		if old then
			old.units[unit] = nil
			old.unitCount = old.unitCount - 1
			self:OnUnitsChanged(old)
		end
		self.unitOwner[unit] = p
		if p then
			p.units[unit] = true
			p.unitCount = p.unitCount + 1
			self:OnUnitsChanged(p)
		end
	end
	if p then
		self.Frames:RefreshHealth(p, unit)
		self:CheckCarrierUnit(p, unit)
	end
	if unit == "target" or unit == "focus" then
		if old then self.Frames:RefreshIndicators(old) end
		if p then self.Frames:RefreshIndicators(p) end
	end
end

function BGT:OnUnitsChanged(p)
	self.Frames:RefreshBound(p)
end

function BGT:RebindAll()
	wipe(self.unitOwner)
	for _, side in pairs(self.sides) do
		for _, p in pairs(side.players) do
			wipe(p.units)
			p.unitCount = 0
			p.targetedBy = 0
			p.carrier = nil
			p.inRange = nil
		end
	end
	bindDirty.target = true
	bindDirty.focus = true
	bindDirty.mouseover = true
	bindDirty.player = true
	for i = 1, 40 do
		bindDirty["raid" .. i] = true
		bindDirty["raid" .. i .. "target"] = true
		bindDirty["nameplate" .. i] = true
	end
	targetDirty = true
end

function BGT:IsPlayerTarget(p) return self.unitOwner.target == p end
function BGT:IsPlayerFocus(p) return self.unitOwner.focus == p end

-- ---------------------------------------------------------------------------
-- target counts / leader / carrier / range
-- ---------------------------------------------------------------------------

function BGT:UpdateTargetCounts()
	local counts = {}
	local n = GetNumGroupMembers() or 0
	local prefix = IsInRaid() and "raid" or "party"
	if not IsInRaid() then
		local p = self.unitOwner["target"]
		if p then counts[p] = (counts[p] or 0) + 1 end
	end
	for i = 1, n do
		local p = self.unitOwner[prefix .. i .. "target"]
		if p then counts[p] = (counts[p] or 0) + 1 end
	end
	for _, side in pairs(self.sides) do
		for _, p in ipairs(side.list) do
			local c = counts[p] or 0
			if c ~= p.targetedBy then
				p.targetedBy = c
				self.Frames:RefreshCount(p)
			end
		end
	end
end

function BGT:UpdateLeader()
	local side = self.sides.Friend
	local leader
	local n = GetNumGroupMembers() or 0
	local prefix = IsInRaid() and "raid" or "party"
	for i = 1, n do
		local unit = prefix .. i
		if UnitExists(unit) and UnitIsGroupLeader(unit) then
			leader = self.unitOwner[unit] or self:FindPlayerByUnit(unit)
			break
		end
	end
	if not leader and UnitIsGroupLeader("player") then leader = self.unitOwner.player end
	if side.leader ~= leader then
		local old = side.leader
		side.leader = leader
		if old then self.Frames:RefreshIndicators(old) end
		if leader then self.Frames:RefreshIndicators(leader) end
	end
end

function BGT:SetCarrier(side, p)
	if side.carrier == p then return end
	local old = side.carrier
	side.carrier = p
	if old then old.carrier = nil; self.Frames:RefreshIndicators(old) end
	if p then p.carrier = true; self.Frames:RefreshIndicators(p) end
end

function BGT:CheckCarrierUnit(p, unit)
	if not UnitPvpClassification then return end
	local ok, cls = pcall(UnitPvpClassification, unit)
	if not ok or issecretvalue(cls) then return end
	local side = self.sides[p.side]
	if cls ~= nil and cls <= 2 then
		self:SetCarrier(side, p)
	elseif side.carrier == p then
		self:SetCarrier(side, nil)
	end
end

function BGT:OnBGSystemMessage(msg, faction)
	if type(msg) ~= "string" or issecretvalue(msg) then return end
	local sideName = (faction == self.myFaction) and "Friend" or "Enemy"
	local side = self.sides[sideName]
	local name = (FLG.WG_TP_DG_PATTERN_PICKED1 and strmatch(msg, FLG.WG_TP_DG_PATTERN_PICKED1))
		or (FLG.WG_TP_DG_PATTERN_PICKED2 and strmatch(msg, FLG.WG_TP_DG_PATTERN_PICKED2))
		or (FLG.EOTS_PATTERN_PICKED and strmatch(msg, FLG.EOTS_PATTERN_PICKED))
	if name then
		local p = self:FindPlayerByName(name, sideName)
		if p then self:SetCarrier(self.sides[p.side], p) end
		return
	end
	if (FLG.WG_TP_DG_MATCH_DROPPED and strfind(msg, FLG.WG_TP_DG_MATCH_DROPPED, 1, true))
		or (FLG.WG_TP_DG_MATCH_CAPTURED and strfind(msg, FLG.WG_TP_DG_MATCH_CAPTURED, 1, true))
		or (FLG.EOTS_STRING_DROPPED and msg == FLG.EOTS_STRING_DROPPED)
		or (FLG.EOTS_PATTERN_CAPTURED and strmatch(msg, FLG.EOTS_PATTERN_CAPTURED)) then
		self:SetCarrier(side, nil)
	end
end

function BGT:CheckRange(p)
	local unit = self:AnyUnit(p)
	if not unit then return nil end
	local spells = RANGE_SPELLS[p.side]
	local spellID = spells and spells[self.myClass]
	local result
	if spellID then
		local ok, r = pcall(C_Spell and C_Spell.IsSpellInRange or IsSpellInRange, spellID, unit)
		if ok and not issecretvalue(r) and r ~= nil then result = r and true or false end
	end
	if result == nil then
		local ok, r = pcall(CheckInteractDistance, unit, 1)
		if ok and not issecretvalue(r) and r ~= nil then result = r and true or false end
	end
	return result
end

function BGT:RangeTick()
	for _, sideName in ipairs(SIDES) do
		local side = self.sides[sideName]
		if self:Cfg(sideName).Range then
			for _, p in ipairs(side.list) do
				local r = self:CheckRange(p)
				if r ~= p.inRange then
					p.inRange = r
					self.Frames:RefreshRange(p)
				end
			end
		end
	end
end

function BGT:CarrierTick()
	for unit, p in pairs(self.unitOwner) do
		if UnitExists(unit) then self:CheckCarrierUnit(p, unit) end
	end
end

-- ---------------------------------------------------------------------------
-- battlefield state
-- ---------------------------------------------------------------------------

function BGT:DetectFaction()
	local ok, f = pcall(GetBattlefieldArenaFaction)
	if ok and type(f) == "number" and not issecretvalue(f) and (f == 0 or f == 1) then
		self.myFaction = f
		return
	end
	local group = UnitFactionGroup("player")
	if not issecretvalue(group) and PLAYER_FACTION_GROUP and PLAYER_FACTION_GROUP[group] then
		self.myFaction = PLAYER_FACTION_GROUP[group]
	end
end

function BGT:DetectTeamSize()
	local size = 0
	if C_PvP.GetTeamInfo then
		for i = 0, 1 do
			local ok, t = pcall(C_PvP.GetTeamInfo, i)
			if ok and type(t) == "table" and type(t.size) == "number" and not issecretvalue(t.size) then
				size = max(size, t.size)
			end
		end
	end
	if size == 0 then
		local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
		if not issecretvalue(n) and n > 0 then size = ceil(n / 2) end
	end
	if size == 0 then
		local mapID = select(8, GetInstanceInfo())
		size = BG_TEAM_SIZE[mapID] or 0
	end
	return size
end

function BGT:UpdateBracket(force)
	local size = self:DetectTeamSize()
	local bracket = (size <= 10 and 10) or (size <= 15 and 15) or 40
	if size == 0 then bracket = self.bracket end
	if force or bracket ~= self.bracket then
		self.bracket = bracket
		for _, side in pairs(self.sides) do self:SortSide(side) end
		self:ApplyLayout()
	end
end

function BGT:ApplyLayout()
	if InCombatLockdown() then
		self.pending.layout = true
		return
	end
	self.pending.layout = nil
	for _, sideName in ipairs(SIDES) do
		self.Frames:Layout(sideName)
		self.Frames:RestorePosition(sideName)
	end
end

function BGT:InBattleground()
	local ok, r = pcall(C_PvP.IsBattleground)
	if ok and r then return true end
	local _, itype = IsInInstance()
	return itype == "pvp"
end

function BGT:CheckBattlefield()
	if self.testMode then return end
	if self:InBattleground() then
		if not self.inMatch then self:EnterMatch() end
	elseif self.inMatch then
		self:LeaveMatch()
	end
end

function BGT:RequestScore()
	if PVPMatchScoreboard and PVPMatchScoreboard:IsShown() then return end
	pcall(SetBattlefieldScoreFaction, -1)
	pcall(RequestBattlefieldScoreData)
end

function BGT:EnterMatch()
	self.inMatch = true
	self:DetectFaction()
	self:UpdateBracket(true)
	self.Frames:SetVisible(true)
	self:RebindAll()
	self.scoreLast = 0
	if not self.scoreTicker then
		self.scoreTicker = C_Timer.NewTicker(SCORE_INTERVAL, function() BGT:RequestScore() end)
	end
	self:RequestScore()
	self.unitFrame:Show()
end

function BGT:LeaveMatch()
	self.inMatch = false
	if self.scoreTicker then self.scoreTicker:Cancel(); self.scoreTicker = nil end
	self.unitFrame:Hide()
	wipe(self.unitOwner)
	for _, side in pairs(self.sides) do
		for name, p in pairs(side.players) do
			self:ReleasePlayer(p)
			side.players[name] = nil
		end
		wipe(side.list)
		self:IndexSide(side)
		side.carrier = nil
		side.leader = nil
	end
	self.Frames:SetVisible(false)
	if not InCombatLockdown() then
		for _, sideName in ipairs(SIDES) do self.Frames:AssignButtons(self.sides[sideName]) end
	else
		self.pending.roster = true
	end
end

function BGT:OnRegenEnabled()
	self.inCombat = false
	self.Frames:OnRegenEnabled()
	if self.pending.layout then self:ApplyLayout() end
	if self.pending.roster then self:ApplyRoster() end
	if self.pending.position then self.pending.position = nil; self.Frames:SaveAllPositions() end
	if self.Options then self.Options:OnCombatChanged(false) end
end

-- ---------------------------------------------------------------------------
-- test mode
-- ---------------------------------------------------------------------------

local TEST_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

function BGT:BuildTestData(bracket)
	local tokens = {}
	for token in pairs(self.classes) do tinsert(tokens, token) end
	tsort(tokens)
	if #tokens == 0 then tokens = { "WARRIOR", "MAGE", "PRIEST" } end
	for _, sideName in ipairs(SIDES) do
		local side = self.sides[sideName]
		for name, p in pairs(side.players) do
			self:ReleasePlayer(p)
			side.players[name] = nil
		end
		wipe(side.list)
		for i = 1, bracket do
			local token = tokens[random(#tokens)]
			local name = L["Target"] .. "_" .. TEST_LETTERS:sub(i % 26 + 1, i % 26 + 1) .. string.char(96 + random(15)) .. "-Realm"
			local p = newPlayer(sideName, name, token)
			local specs = self:ClassInfo(token).specList
			local spec = specs[random(max(#specs, 1))]
			if spec then
				self:ResolveSpec(p, spec.name, sideName == "Enemy" and i % 3 == 0)
			end
			p.test = { health = random(), count = random(0, 3) > 1 and random(1, 4) or 0, range = random() > 0.5 }
			p.targetedBy = p.test.count
			p.inRange = p.test.range
			side.players[name] = p
			tinsert(side.list, p)
		end
		self:SortSide(side)
		side.carrier = side.list[random(#side.list)]
		side.carrier.carrier = true
		if sideName == "Friend" then side.leader = side.list[random(#side.list)] end
	end
	self.testTarget = self.sides.Enemy.list[random(bracket)]
	self.testFocus = self.sides.Enemy.list[random(bracket)]
end

function BGT:SetTestMode(on, bracket)
	if on then
		if self.inMatch then self:LeaveMatch() end
		self.testMode = true
		self.bracket = bracket or self.bracket
		self:BuildTestData(self.bracket)
		self:ApplyLayout()
		self:ApplyRoster()
		self.Frames:SetVisible(true, true)
		self.Frames:SetMover(true)
	else
		self.testMode = false
		self.Frames:SetMover(false)
		for _, side in pairs(self.sides) do
			for name, p in pairs(side.players) do
				self:ReleasePlayer(p)
				side.players[name] = nil
			end
			wipe(side.list)
			self:IndexSide(side)
			side.carrier = nil
			side.leader = nil
		end
		self.testTarget, self.testFocus = nil, nil
		self.Frames:SetVisible(false)
		self:ApplyRoster()
		self:CheckBattlefield()
	end
end

function BGT:ShuffleTest()
	if not self.testMode then return end
	for _, side in pairs(self.sides) do
		for _, p in ipairs(side.list) do
			p.test.health = random()
			p.test.count = random(0, 3) > 1 and random(1, 4) or 0
			p.test.range = random() > 0.5
			p.targetedBy = p.test.count
			p.inRange = p.test.range
			self.Frames:RefreshHealth(p)
			self.Frames:RefreshCount(p)
			self.Frames:RefreshRange(p)
		end
		local old = side.carrier
		side.carrier = side.list[random(#side.list)]
		if old then old.carrier = nil end
		side.carrier.carrier = true
		if side.name == "Friend" then side.leader = side.list[random(#side.list)] end
	end
	self.testTarget = self.sides.Enemy.list[random(#self.sides.Enemy.list)]
	self.testFocus = self.sides.Enemy.list[random(#self.sides.Enemy.list)]
	for _, side in pairs(self.sides) do
		for _, p in ipairs(side.list) do self.Frames:RefreshIndicators(p) end
	end
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

local unitFrame = CreateFrame("Frame")
BGT.unitFrame = unitFrame
unitFrame:Hide()

unitFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "UNIT_HEALTH" then
		if BGT.unitOwner[arg1] then healthDirty[arg1] = true end
	elseif event == "UNIT_TARGET" then
		if type(arg1) == "string" and (strfind(arg1, "^raid%d+$") or strfind(arg1, "^party%d+$") or arg1 == "player") then
			bindDirty[arg1 .. "target"] = true
			targetDirty = true
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		bindDirty.target = true
		targetDirty = true
	elseif event == "PLAYER_FOCUS_CHANGED" then
		bindDirty.focus = true
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		bindDirty.mouseover = true
	elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
		if type(arg1) == "string" then bindDirty[arg1] = true end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
		for i = 1, 40 do
			bindDirty["raid" .. i] = true
			bindDirty["raid" .. i .. "target"] = true
		end
		for i = 1, 4 do
			bindDirty["party" .. i] = true
			bindDirty["party" .. i .. "target"] = true
		end
		bindDirty.player = true
		targetDirty = true
		rosterDirty = true
	elseif event == "CHAT_MSG_BG_SYSTEM_HORDE" then
		BGT:OnBGSystemMessage(arg1, 0)
	elseif event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then
		BGT:OnBGSystemMessage(arg1, 1)
	end
end)

local rangeElapsed, carrierElapsed = 0, 0
unitFrame:SetScript("OnUpdate", function(_, elapsed)
	if next(bindDirty) then
		for unit in pairs(bindDirty) do BGT:BindUnit(unit) end
		wipe(bindDirty)
	end
	if next(healthDirty) then
		for unit in pairs(healthDirty) do
			local p = BGT.unitOwner[unit]
			if p then BGT.Frames:RefreshHealth(p, unit) end
		end
		wipe(healthDirty)
	end
	if targetDirty then
		targetDirty = false
		BGT:UpdateTargetCounts()
	end
	if rosterDirty then
		rosterDirty = false
		BGT:UpdateLeader()
	end
	rangeElapsed = rangeElapsed + elapsed
	if rangeElapsed >= RANGE_INTERVAL then
		rangeElapsed = 0
		BGT:RangeTick()
	end
	carrierElapsed = carrierElapsed + elapsed
	if carrierElapsed >= CARRIER_INTERVAL then
		carrierElapsed = 0
		BGT:CarrierTick()
	end
end)

for _, ev in ipairs({
	"UNIT_HEALTH", "UNIT_TARGET", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
	"CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_ALLIANCE",
}) do
	pcall(unitFrame.RegisterEvent, unitFrame, ev)
end

BGT:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		self:InitOptions()
		self:BuildClassTable()
		local _, class = UnitClass("player")
		self.myClass = not issecretvalue(class) and class or nil
		self.Frames:Init()
		if self.Options then self.Options:Init() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(1, function() BGT:CheckBattlefield() end)
	elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PVP_MATCH_STATE_CHANGED"
		or event == "PVP_MATCH_ACTIVE" or event == "PVP_MATCH_INACTIVE" then
		self:CheckBattlefield()
	elseif event == "UPDATE_BATTLEFIELD_SCORE" then
		if not self.inMatch then return end
		local now = GetTime()
		if now - (self.scoreLast or 0) < SCORE_THROTTLE then return end
		self.scoreLast = now
		self:UpdateRoster()
	elseif event == "PLAYER_REGEN_DISABLED" then
		self.inCombat = true
		if self.Options then self.Options:OnCombatChanged(true) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:OnRegenEnabled()
	end
end)

for _, ev in ipairs({
	"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UPDATE_BATTLEFIELD_SCORE",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PVP_MATCH_STATE_CHANGED", "PVP_MATCH_ACTIVE", "PVP_MATCH_INACTIVE",
}) do
	pcall(BGT.RegisterEvent, BGT, ev)
end

SLASH_BGTARGETS1 = "/bgt"
SLASH_BGTARGETS2 = "/bgtargets"
SLASH_BGTARGETS3 = "/battlegroundtargets"
SlashCmdList.BGTARGETS = function(msg)
	msg = strtrim(msg or "")
	if msg == "diag" then
		BGT:Diag()
	elseif BGT.Options then
		BGT.Options:Toggle()
	end
end

function BGT:Diag()
	local P = function(...) print("|cffffff7fBGT:|r", ...) end
	P("inMatch", self.inMatch, "bracket", self.bracket, "faction", self.myFaction, "test", self.testMode)
	local ok, state = pcall(C_PvP.GetActiveMatchState)
	P("matchState", ok and state, "scores", GetNumBattlefieldScores and GetNumBattlefieldScores())
	if C_RestrictedActions and Enum.AddOnRestrictionType then
		P("restriction pvp", C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.PvPMatch),
			"combat", C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat))
	end
	for _, sideName in ipairs(SIDES) do
		local side = self.sides[sideName]
		P(sideName, #side.list, "carrier", side.carrier and side.carrier.name, "leader", side.leader and side.leader.name)
		for i, p in ipairs(side.list) do
			if i <= 5 then
				P(" ", i, p.name, p.class, p.specText and (p.specSecret and "spec:secret" or p.specText), "role", p.role, "units", p.unitCount, "tb", p.targetedBy)
			end
		end
	end
	local bound = 0
	for _ in pairs(self.unitOwner) do bound = bound + 1 end
	P("bound units", bound)
end
