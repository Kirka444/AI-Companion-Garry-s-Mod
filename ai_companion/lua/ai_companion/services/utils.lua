local Utils = {}

function Utils:new()
	local obj = {}
	setmetatable(obj, self)
	self.__index = function(t, k)
		-- Перехватываем вызовы лог-методов через двоеточие

		if k == "Log" then
			return function(_, level, module, msg, ...)
				Utils.Log(level, module, msg, ...)
			end
		elseif k == "LogInfo" then
			return function(_, module, msg, ...)
				Utils.LogInfo(module, msg, ...)
			end
		elseif k == "LogWarn" then
			return function(_, module, msg, ...)
				Utils.LogWarn(module, msg, ...)
			end
		elseif k == "LogError" then
			return function(_, module, msg, ...)
				Utils.LogError(module, msg, ...)
			end
		elseif k == "LogDebug" then
			return function(_, module, msg, ...)
				Utils.LogDebug(module, msg, ...)
			end
		end
		return rawget(self, k)
	end
	return obj
end

function Utils:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end

function Utils:IsValid(ent)
	if ent == nil then return false end
	if isentity(ent) then return ent:IsValid() end
	return IsValid(ent) -- Fallback для нестандартных объектов
end

function Utils:IsBotSafe(ent)
	if not ent then return false end
	if not self:IsValid(ent) then return false end
	if not ent.IsPlayer then return false end
	local ok, res = pcall(ent.IsPlayer, ent)
	if not ok or not res then return false end
	ok, res = pcall(ent.IsBot, ent)
	return ok and res
end

function Utils:IsPlayerSafe(ent)
	if not ent then return false end
	if not self:IsValid(ent) then return false end
	if not ent.IsPlayer then return false end
	local ok, res = pcall(ent.IsPlayer, ent)
	if not ok or not res then return false end
	ok, res = pcall(ent.IsBot, ent)
	return ok and not res
end

local LOG_LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, FATAL = 4 }
local CURRENT_LOG_LEVEL = 4 -- может пригодится в будущем для логирования ошибок, но сейчас выключен за ненадобностью

function Utils.Log(level, module, msg, ...)
	-- Logging disabled in production
end

function Utils.LogInfo(module, msg, ...)
	-- Logging disabled in production
end

function Utils.LogWarn(module, msg, ...)
	-- Logging disabled in production
end

function Utils.LogError(module, msg, ...)
	-- Logging disabled in production
end

function Utils.LogDebug(module, msg, ...)
	-- Logging disabled in production
end

function Utils:ValidateIP(ip)
	if not ip or ip == "" then
		return false, self:GetLocalized("settings_invalid_ip")
	end

	if string.match(ip, ":%d+$") then
		return false, "IP " .. self:GetLocalized("settings_invalid_ip")
	end
	if string.match(ip, "^%d+%.%d+%.%d+%.%d+$") then return true end
	if string.match(ip, "^localhost$") then return true end
	if string.match(ip, "^[%w%-%.]+$") and #ip < 256 then return true end
	return false, self:GetLocalized("settings_invalid_ip")
end

function Utils:ValidatePort(port)
	port = tonumber(port)
	if not port or port < 1 or port > 65535 then
		return false, self:GetLocalized("settings_invalid_port")
	end
	return true, port
end

function Utils:CleanText(str, maxLen)
	if not str then return "" end
	str = tostring(str)

	str = string.gsub(str, "%s+", " ")
	str = string.gsub(str, "^%s*(.-)%s*$", "%1")
	if maxLen then
		str = string.sub(str, 1, maxLen)
	end
	return str
end

function Utils:CleanForTTS(str)

	if str == nil then
		return ""
	end

	if type(str) ~= "string" then
		str = tostring(str) or ""
	end

	if not str or str == "" then
		return ""
	end

	str = tostring(str)

	str = string.gsub(str, "`[^`]*`", " ")
	str = string.gsub(str, "{[^{}]-}", " ")
	str = string.gsub(str, "[<>\"'&]", "")
	str = string.gsub(str, "%s+", " ")
	str = string.gsub(str, "^%s*(.-)%s*$", "%1")


	if str == "" and tostring(str) ~= "" and tostring(str) ~= " " then
		return tostring(str)
	end

	return str
end

function Utils:CreateCache(maxSize, ttl)
	maxSize = maxSize or 50
	ttl = ttl or 3600

	local cache = {}
	local order = {}
	local timestamps = {}
	local head = 1  -- Кольцевой буфер: индекс начала
	local count = 0

	return {
		get = function(_, key)
			local now = CurTime()
			-- Очистка протухших (инкрементальный проход, не каждый раз)
			if count > 0 and timestamps[order[head]] and (now - timestamps[order[head]]) > ttl then
				local newHead = head
				local newCount = count
				while newCount > 0 and timestamps[order[newHead]] and (now - timestamps[order[newHead]]) > ttl do
					cache[order[newHead]] = nil
					timestamps[order[newHead]] = nil
					order[newHead] = nil
					newHead = newHead + 1
					newCount = newCount - 1
				end
				head = newHead
				count = newCount
			end
			return cache[key]
		end,
		set = function(_, key, value)
			local now = CurTime()
			-- Удаляем старый ключ если есть (помечаем nil, не сдвигаем)
			if cache[key] ~= nil then
				timestamps[key] = now
				cache[key] = value
				return
			end
			-- Добавляем новый
			local tail = head + count
			order[tail] = key
			cache[key] = value
			timestamps[key] = now
			count = count + 1
			-- Удаляем старые при превышении maxSize
			while count > maxSize do
				cache[order[head]] = nil
				timestamps[order[head]] = nil
				order[head] = nil
				head = head + 1
				count = count - 1
			end
		end,
		has = function(_, key)
			return cache[key] ~= nil
		end,
		cleanup = function(_)
			cache = {}
			order = {}
			timestamps = {}
			head = 1
			count = 0
		end,
		size = function(_)
			return count
		end,
	}
end

function Utils:Hash(str)
	if not str or str == "" then return "empty" end
	local crc = 0
	for i = 1, #str do
		crc = crc + string.byte(str, i) * i
		crc = crc % 16777216
	end
	return string.format("%06x", crc)
end

function Utils:FindInSphere(pos, radius)
	local result = {}
	local ok, ents = pcall(ents.FindInSphere, pos, radius)
	if ok and ents then
		for _, ent in ipairs(ents) do
			if self:IsValid(ent) then table.insert(result, ent) end
		end
	end
	return result
end

function Utils:IsValidModel(path)
	if not path or path == "" then return false end
	if string.find(path, "%.%.") then return false end
	if string.find(path, "\\") then return false end
	if not string.match(path, "%.mdl$") then return false end
	local ok, exists = pcall(util.IsValidModel, path)
	return ok and exists
end

function Utils:URLEncode(str)
	if not str then return "" end
	return string.gsub(str, "([^%w%-_%.%!%*%'%(%)])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

function Utils:SanitizeURL(base, path)
	if not base or base == "" then return "" end
	base = string.gsub(base, "[<>\"'&]", "")
	base = string.gsub(base, "/+$", "")
	if path then
		path = string.gsub(path, "[<>\"'&]", "")
		path = string.gsub(path, "^/+", "")
		path = string.gsub(path, "/+$", "")
	end
	local url = base
	if path and path ~= "" then url = url .. "/" .. path end
	return url
end

local PrefixCache = nil

function Utils:GetCleanPrefix(ply, settings)
	if not self:IsValid(ply) then return "AI" end

	if not PrefixCache then
		PrefixCache = self:CreateCache(32, 60)
	end

	local steamID = ply:SteamID64()
	local cached = PrefixCache:get(steamID)
	if cached then return cached end

	-- Поддержка обоих форматов ключей
	local prefix = settings.prefix_text or settings.Prefix_Text or "[AI]"
	local clean = string.gsub(prefix, "^%[", "")
	clean = string.gsub(clean, "%]$", "")
	clean = string.Trim(clean)
	if clean == "" then clean = "AI" end

	PrefixCache:set(steamID, clean)
	return clean
end

local PrefixColorCache = nil

function Utils:GetPrefixColor(ply, settings)
	if not self:IsValid(ply) then return Color(255, 200, 0) end

	-- Rainbow не кэшируем — цвет меняется каждый кадр
	if settings and (settings.prefix_rainbow or settings.Prefix_Rainbow) then
		local hue = (CurTime() * 120) % 360
		return HSVToColor(hue, 1, 1)
	end

	if not PrefixColorCache then
		PrefixColorCache = self:CreateCache(32, 60)
	end

	local steamID = ply:SteamID64()
	local cached = PrefixColorCache:get(steamID)
	if cached then return cached end

	-- Поддержка обоих форматов ключей
	local r = settings.prefix_r or settings.Prefix_Color_R or 255
	local g = settings.prefix_g or settings.Prefix_Color_G or 200
	local b = settings.prefix_b or settings.Prefix_Color_B or 0

	local color = Color(r, g, b)

	PrefixColorCache:set(steamID, color)
	return color
end

function Utils:InvalidatePrefixCache(ply)
	if not self:IsValid(ply) then return end
	local steamID = ply:SteamID64()
	if PrefixCache then
		PrefixCache:set(steamID, nil)
	end
	if PrefixColorCache then
		PrefixColorCache:set(steamID, nil)
	end
end

local HTTPQueue = {}
local HTTPActive = 0
local MAX_HTTP_CONCURRENT = 3

local MAX_HTTP_QUEUE_SIZE = 20

function Utils:HTTPQueue(params)
	if not params or not params.url then
		Utils.LogError("HTTP", "Некорректный запрос: нет URL")
		Utils.Log(self:GetLocalized("log_http_queue_miss"))
		return
	end
	-- Ограничение размера очереди: выкидываем самые старые
	while #HTTPQueue >= MAX_HTTP_QUEUE_SIZE do
		table.remove(HTTPQueue, 1)
		Utils.LogWarn("HTTP", "Очередь HTTP переполнена, удалён старый запрос")
	end
	table.insert(HTTPQueue, params)
	self:HTTPProcess()
end

function Utils:HTTPProcess()
	if #HTTPQueue == 0 then return end
	if HTTPActive >= MAX_HTTP_CONCURRENT then return end

	local item = table.remove(HTTPQueue, 1)
	HTTPActive = HTTPActive + 1

	local origSuccess = item.success
	local origError = item.error
	item.timeout = item.timeout or 10
	item._retries = item._retries or 0
	local maxRetries = 3

	local function doRequest()
		local params = {
			url = item.url,
			method = item.method or "GET",
			timeout = item.timeout,
			body = item.body,
			headers = item.headers,
			success = function(code, body)
				HTTPActive = math.max(0, HTTPActive - 1)
				if origSuccess then
					local ok, err = pcall(origSuccess, code, body)
					if not ok then
						Utils.LogError("HTTP", "В success: %s", tostring(err))
					end
				end
				Utils:HTTPProcess()
			end,
			error = function(err)
				HTTPActive = math.max(0, HTTPActive - 1)
				item._retries = item._retries + 1
				if item._retries < maxRetries then
					Utils.LogWarn("HTTP", "Retry %d/%d for %s", item._retries, maxRetries, item.url)
					timer.Simple(0.5 * item._retries, function()
						HTTPActive = HTTPActive + 1
						doRequest()
					end)
				else
					if origError then
						local ok, err2 = pcall(origError, err)
						if not ok then
							Utils.LogError("HTTP", "В error: %s", tostring(err2))
						end
					end
					Utils:HTTPProcess()
				end
			end
		}
		HTTP(params)
	end

	if SERVER then
		doRequest()
	else
		Utils.LogDebug("HTTP", "Клиент: запрос пропущен: %s", item.url)
		HTTPActive = math.max(0, HTTPActive - 1)
		if origSuccess then
			origSuccess(200, "{}")
		end
		if Utils.HTTPProcess then
			Utils:HTTPProcess()
		end
	end
end

return Utils