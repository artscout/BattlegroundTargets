local MAP, _, prg = {}, ...
prg.MAP = MAP

local locale = GetLocale()
local AV, WG, AB

if locale == "enUS" then
	AV = "Alterac Valley"
	WG = "Warsong Gulch"
	AB = "Arathi Basin"
elseif locale == "koKR" then
	AV = "알터랙 계곡"
	WG = "전쟁노래 협곡"
	AB = "아라시 분지"
elseif locale == "ruRU" then
	AV = "Альтеракская долина"
	WG = "Ущелье Песни Войны"
	AB = "Низина Арати"
elseif locale == "zhCN" then
	AV = "奥特兰克山谷"
	WG = "战歌峡谷"
	AB = "阿拉希盆地"
elseif locale == "deDE" then
	AV = "Alteractal"
	WG = "Warsongschlucht"
	AB = "Arathibecken"
elseif locale == "frFR" then
	AV = "Vallée d'alterac"
	WG = "Goulet des warsong"
	AB = "Bassin d'Arathi"
--[[
elseif locale == "zhTW" then
elseif locale == "esES" then
elseif locale == "esMX" then
elseif locale == "ptBR" then
elseif locale == "itIT" then]]
else
	AV = "Alterac Valley"
	WG = "Warsong Gulch"
	AB = "Arathi Basin"
end

MAP.AV = AV
MAP.WG = WG
MAP.AB = AB