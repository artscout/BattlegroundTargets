local ADDON, prg = ...
local BGT = prg.BGT
local L = BGT.L

local pairs, ipairs, type = pairs, ipairs, type
local floor, cos, sin, atan2, rad, deg = math.floor, math.cos, math.sin, math.atan2, math.rad, math.deg
local tinsert = table.insert

local Options = {}
BGT.Options = Options

local ctx = { side = "Enemy", bracket = 10, page = "bracket" }
local widgets = {}
local frame

local ADDON_ICON = "Interface\\AddOns\\BattlegroundTargets\\Media\\BattlegroundTargets-texture-button"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function cfg()
	return BGT:Cfg(ctx.side, ctx.bracket)
end

local function applyLayout()
	BGT:ApplyLayout()
	BGT.Frames:RefreshAll()
end

local function applySort()
	for _, side in pairs(BGT.sides) do BGT:SortSide(side) end
	BGT:ApplyRoster()
end

local function applyEnable()
	BGT.Frames:SetVisible(true, BGT.testMode)
end

-- ---------------------------------------------------------------------------
-- widgets
-- ---------------------------------------------------------------------------

local function Label(parent, x, y, text, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function Check(parent, x, y, label, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	cb:SetSize(22, 22)
	local text = cb.Text or cb.text
	if text then
		text:SetText(label)
		text:SetFontObject("GameFontHighlightSmall")
	end
	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	cb.Refresh = function(self) self:SetChecked(get() and true or false) end
	tinsert(widgets, cb)
	return cb
end

local function Slider(parent, x, y, width, label, minv, maxv, step, get, set, fmt)
	local s = CreateFrame("Slider", nil, parent, "UISliderTemplate")
	s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 14)
	s:SetSize(width, 14)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(minv, maxv)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s.label = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
	s.label:SetText(label)
	s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 2)
	fmt = fmt or function(v) return tostring(v) end
	s:SetScript("OnValueChanged", function(self, v)
		v = floor(v / step + 0.5) * step
		self.value:SetText(fmt(v))
		if self.refreshing then return end
		if get() ~= v then set(v) end
	end)
	s.Refresh = function(self)
		self.refreshing = true
		self:SetValue(get())
		self.value:SetText(fmt(get()))
		self.refreshing = false
	end
	tinsert(widgets, s)
	return s
end

local function Cycle(parent, x, y, width, label, values, get, set)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 12)
	b:SetSize(width, 22)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.label:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 2, 1)
	b.label:SetText(label)
	local function index()
		local cur = get()
		for i, v in ipairs(values) do if v[1] == cur then return i end end
		return 1
	end
	b:SetScript("OnClick", function(self, button)
		local list = self.values or values
		local i = 1
		local cur = get()
		for k, v in ipairs(list) do if v[1] == cur then i = k end end
		if button == "RightButton" then i = i - 1 else i = i + 1 end
		if i > #list then i = 1 elseif i < 1 then i = #list end
		set(list[i][1])
		self:Refresh()
	end)
	b.Refresh = function(self)
		local list = self.values or values
		local cur = get()
		local text = list[1] and list[1][2] or ""
		for _, v in ipairs(list) do if v[1] == cur then text = v[2] end end
		self:SetText(text)
	end
	tinsert(widgets, b)
	return b
end

local function Button(parent, x, y, width, text, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function pct(v) return v .. "%" end
local function px(v) return v .. " px" end

-- ---------------------------------------------------------------------------
-- pages
-- ---------------------------------------------------------------------------

local function buildBracketPage(page)
	local function key(k)
		return function() return cfg()[k] end, function(v) cfg()[k] = v end
	end
	local function keyLayout(k)
		local get, set = key(k)
		return get, function(v) set(v); applyLayout() end
	end
	local function keySort(k)
		local get, set = key(k)
		return get, function(v) set(v); applySort() end
	end

	local x, y = 10, -10
	local getE, setE = key("Enable")
	Check(page, x, y, L["Enable"], getE, function(v) setE(v); applyEnable() end)
	y = y - 30
	Slider(page, x, y, 250, L["Scale"], 50, 250, 5,
		function() return floor(cfg().Scale * 100 + 0.5) end,
		function(v) cfg().Scale = v / 100; applyLayout() end, pct)
	y = y - 40
	Slider(page, x, y, 250, L["Width"], 50, 300, 5, keyLayout("Width"))
	y = y - 40
	Slider(page, x, y, 250, L["Height"], 10, 50, 1, keyLayout("Height"))
	y = y - 40
	Slider(page, x, y, 250, L["Text"] .. ": " .. L["Name"], 6, 20, 1, keyLayout("FontSize"))
	y = y - 40
	local rowsBtn = Cycle(page, x, y, 120, L["Layout"], {}, keyLayout("Rows"))
	rowsBtn.RefreshValues = function(self)
		local list = { { 0, L["Layout"] .. ": 1" } }
		if ctx.bracket == 40 then
			tinsert(list, { 20, "2 x 20" }); tinsert(list, { 10, "4 x 10" }); tinsert(list, { 5, "8 x 5" })
		elseif ctx.bracket == 15 then
			tinsert(list, { 5, "3 x 5" })
		else
			tinsert(list, { 5, "2 x 5" })
		end
		self.values = list
	end
	local getSpace, setSpace = keyLayout("Space")
	Slider(page, x + 130, y, 120, L["Layout"] .. " " .. L["Width"], 0, 100, 1, getSpace, setSpace, px)
	y = y - 45
	Cycle(page, x, y, 250, L["Sort By"], {
		{ 1, L["Role"] .. " / " .. L["Class"] .. " / " .. L["Name"] },
		{ 2, L["Role"] .. " / " .. L["Name"] },
		{ 3, L["Class"] .. " / " .. L["Role"] .. " / " .. L["Name"] },
		{ 4, L["Class"] .. " / " .. L["Name"] },
		{ 5, L["Name"] },
	}, keySort("SortBy"))
	y = y - 45
	Cycle(page, x, y, 250, L["Sort By"] .. ": " .. L["Class"], {
		{ 3, "Blizzard" }, { 1, GetLocale() }, { 2, "enUS" },
	}, keySort("ClassOrder"))

	x, y = 290, -10
	local checks = {
		{ "Role", L["Role"] }, { "SpecIcon", L["Specialization"] }, { "SpecText", L["Specialization"] .. " (" .. L["Text"] .. ")" },
		{ "ClassIcon", L["Class Icon"] }, { "Realm", L["Realm"] }, { "Leader", L["Leader"] },
		{ "TargetCount", L["Target Count"] }, { "HealthBar", L["Health Bar"] }, { "HealthText", L["Percent"] },
		{ "HealthColor", L["Health Bar"] .. ": " .. L["Mode"] }, { "LowGlow", L["Health Bar"] .. ": !" }, { "Range", L["Range"] },
	}
	for i, c in ipairs(checks) do
		local col = (i - 1) % 2
		local row = floor((i - 1) / 2)
		Check(page, x + col * 150, y - row * 22, c[2], keyLayout(c[1]))
	end
	y = y - 6 * 22 - 10
	for _, group in ipairs({ { "Target", L["Target"] }, { "Focus", L["Focus"] }, { "Flag", L["Flag"] } }) do
		Check(page, x, y, group[2], keyLayout(group[1]))
		Slider(page, x + 110, y - 4, 90, L["Scale"], 50, 200, 10,
			function() return floor(cfg()[group[1] .. "Scale"] * 100 + 0.5) end,
			function(v) cfg()[group[1] .. "Scale"] = v / 100; applyLayout() end, pct)
		local getPos, setPos = keyLayout(group[1] .. "Pos")
		Slider(page, x + 210, y - 4, 90, L["Number"], 0, 100, 5, getPos, setPos, pct)
		y = y - 48
	end
	Button(page, x, y - 4, 200, L["Test"] .. " / " .. L["Mode"], function() BGT:ShuffleTest() end)
end

local function buildGeneralPage(page)
	local x, y = 10, -10
	Check(page, x, y, L["Show Minimap-Button"],
		function() return BGT.opt.MinimapButton end,
		function(v) BGT.opt.MinimapButton = v; Options:UpdateMinimapButton() end)
	y = y - 26
	Check(page, x, y, "Cyrillic -> Latin",
		function() return BGT.opt.Transliteration end,
		function(v)
			BGT.opt.Transliteration = v
			for _, side in pairs(BGT.sides) do for _, p in pairs(side.players) do p.trans = nil end end
			BGT.Frames:RefreshAll()
		end)
	y = y - 40
	Slider(page, x, y, 250, L["Health Bar"] .. " !  <", 5, 70, 5,
		function() return BGT.opt.LowHealth end,
		function(v) BGT.opt.LowHealth = v; BGT.Frames:SetLowThreshold(v); BGT.Frames:RefreshAll() end, pct)
	y = y - 50
	local info = Label(page, x, y, "/bgt  -  " .. L["Open Configuration"] .. "\n/bgt diag", "GameFontHighlightSmall")
	info:SetJustifyH("LEFT")
end

-- ---------------------------------------------------------------------------
-- frame
-- ---------------------------------------------------------------------------

local tabs = {}

local function selectTab(name)
	for _, t in ipairs(tabs) do
		if t.name == name then t:Disable() else t:Enable() end
	end
end

function Options:Refresh()
	for _, w in ipairs(widgets) do
		if w.RefreshValues then w:RefreshValues() end
		w:Refresh()
	end
	frame.pages.bracket:SetShown(ctx.page == "bracket")
	frame.pages.general:SetShown(ctx.page == "general")
	frame.sideTabs:SetShown(ctx.page == "bracket")
	selectTab(ctx.page == "general" and "general" or ("b" .. ctx.bracket))
	for _, t in ipairs(frame.sideTabs.buttons) do
		if t.side == ctx.side then t:Disable() else t:Enable() end
	end
	frame.title:SetText("BattlegroundTargets  -  " .. (ctx.page == "general" and L["General Settings"]
		or (L[ctx.bracket .. "v" .. ctx.bracket] .. "  " .. (ctx.side == "Friend" and L["Friendly Players"] or L["Enemy Players"]))))
end

local function setBracket(b)
	ctx.page = "bracket"
	if ctx.bracket ~= b then
		ctx.bracket = b
		if frame:IsShown() then BGT:SetTestMode(true, b) end
	end
	Options:Refresh()
end

function Options:Init()
	frame = CreateFrame("Frame", "BattlegroundTargets_OptionsFrame", UIParent, "BackdropTemplate")
	frame:SetSize(600, 470)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:Hide()
	tinsert(UISpecialFrames, "BattlegroundTargets_OptionsFrame")

	local drag = CreateFrame("Frame", nil, frame)
	drag:SetPoint("TOPLEFT", 0, 0)
	drag:SetPoint("TOPRIGHT", 0, 0)
	drag:SetHeight(28)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function() frame:StartMoving() end)
	drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", frame, "TOP", 0, -10)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

	local x = 12
	for _, b in ipairs(BGT.BRACKETS) do
		local t = Button(frame, x, -30, 90, L[b .. "v" .. b], function() setBracket(b) end)
		t.name = "b" .. b
		tinsert(tabs, t)
		x = x + 95
	end
	local g = Button(frame, x + 20, -30, 120, L["General Settings"], function()
		ctx.page = "general"
		Options:Refresh()
	end)
	g.name = "general"
	tinsert(tabs, g)

	frame.sideTabs = CreateFrame("Frame", nil, frame)
	frame.sideTabs:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -56)
	frame.sideTabs:SetSize(300, 24)
	frame.sideTabs.buttons = {}
	for i, side in ipairs(BGT.SIDES) do
		local t = Button(frame.sideTabs, (i - 1) * 135, 0, 130, side == "Friend" and L["Friendly Players"] or L["Enemy Players"], function()
			ctx.side = side
			Options:Refresh()
		end)
		t.side = side
		tinsert(frame.sideTabs.buttons, t)
	end

	frame.pages = {}
	for _, name in ipairs({ "bracket", "general" }) do
		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -84)
		page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
		page:Hide()
		frame.pages[name] = page
	end
	buildBracketPage(frame.pages.bracket)
	buildGeneralPage(frame.pages.general)

	frame:SetScript("OnShow", function()
		BGT:SetTestMode(true, ctx.bracket)
		Options:Refresh()
	end)
	frame:SetScript("OnHide", function()
		BGT:SetTestMode(false)
	end)

	self:InitSettingsPanel()
	self:InitMinimapButton()
end

function Options:Toggle()
	if not frame then return end
	if frame:IsShown() then
		frame:Hide()
	elseif InCombatLockdown() then
		print("|cffffff7fBattlegroundTargets:|r " .. ERR_NOT_IN_COMBAT)
	else
		frame:Show()
	end
end

function Options:OnCombatChanged(inCombat)
	if inCombat and frame and frame:IsShown() then frame:Hide() end
end

-- ---------------------------------------------------------------------------
-- Blizzard settings panel
-- ---------------------------------------------------------------------------

function Options:InitSettingsPanel()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local canvas = CreateFrame("Frame")
	local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("BattlegroundTargets")
	local b = Button(canvas, 16, -50, 200, L["Open Configuration"], function() Options:Toggle() end)
	local info = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", 16, -84)
	info:SetText("/bgt")
	local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, canvas, "BattlegroundTargets")
	if ok and category then
		pcall(Settings.RegisterAddOnCategory, category)
		self.categoryID = category.GetID and category:GetID()
	end
end

-- ---------------------------------------------------------------------------
-- minimap button
-- ---------------------------------------------------------------------------

local MINIMAP_SHAPES = {
	["ROUND"] = { true, true, true, true },
	["SQUARE"] = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function minimapPosition(btn)
	local angle = rad(BGT.opt.MinimapButtonPos or -90)
	local x, y, q = cos(angle), sin(angle), 1
	if x < 0 then q = q + 1 end
	if y > 0 then q = q + 2 end
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local quads = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES.ROUND
	local w = Minimap:GetWidth() / 2 + 5
	local h = Minimap:GetHeight() / 2 + 5
	if quads[q] then
		x, y = x * w, y * h
	else
		local dw = math.sqrt(2 * w * w) - 10
		local dh = math.sqrt(2 * h * h) - 10
		x = math.max(-w, math.min(x * dw, w))
		y = math.max(-h, math.min(y * dh, h))
	end
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function Options:InitMinimapButton()
	local btn = CreateFrame("Button", "BattlegroundTargets_MinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("AnyUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local overlay = btn:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")
	local icon = btn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetTexture(ADDON_ICON)
	icon:SetTexCoord(2 / 16, 14 / 16, 1 / 16, 15 / 16)
	icon:SetPoint("TOPLEFT", 6, -6)
	btn:SetScript("OnClick", function() Options:Toggle() end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function(self)
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			cx, cy = cx / scale, cy / scale
			BGT.opt.MinimapButtonPos = deg(atan2(cy - my, cx - mx)) % 360
			minimapPosition(self)
		end)
	end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("BattlegroundTargets")
		GameTooltip:AddLine(L["Open Configuration"], 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.minimapButton = btn
	self:UpdateMinimapButton()
	C_Timer.After(1, function() Options:UpdateMinimapButton() end)
end

function Options:UpdateMinimapButton()
	local btn = self.minimapButton
	if not btn then return end
	minimapPosition(btn)
	btn:SetShown(BGT.opt.MinimapButton)
end
