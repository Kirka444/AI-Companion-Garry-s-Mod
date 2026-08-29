
local Utils = {}

function Utils:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Utils:IsValid(ent)
    if ent == nil then return false end

    if type(ent) == "userdata" then
        if ent.IsValid then
            local ok, result = pcall(function() return ent:IsValid() end)
            if ok then
                return result
            end
        end
        return IsValid(ent)
    end

    return IsValid(ent)
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
local CURRENT_LOG_LEVEL = 1

function Utils.Log(level, module, msg, ...)
    local levelName = string.upper(level)
    local levelNum = LOG_LEVELS[levelName] or LOG_LEVELS.INFO
    if levelNum < CURRENT_LOG_LEVEL then return end

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local formatted = string.format("[%s] [%s] [%s] %s", timestamp, levelName, module, msg)
    if select("#", ...) > 0 then
        formatted = string.format(formatted, ...)
    end

    MsgC(Color(200, 200, 200), formatted, "\n")
end

function Utils.LogInfo(module, msg, ...)
    Utils.Log("INFO", module, msg, ...)
end

function Utils.LogWarn(module, msg, ...)
    Utils.Log("WARN", module, msg, ...)
end

function Utils.LogError(module, msg, ...)
    Utils.Log("ERROR", module, msg, ...)
end

function Utils.LogDebug(module, msg, ...)
    Utils.Log("DEBUG", module, msg, ...)
end

function Utils:ValidateIP(ip)
    if not ip or ip == "" then return false, "IP пустой" end
    if string.match(ip, "^%d+%.%d+%.%d+%.%d+$") then return true end
    if string.match(ip, "^localhost$") then return true end
    if string.match(ip, "^[%w%-%.]+$") and #ip < 256 then return true end
    return false, "Невалидный IP"
end

function Utils:ValidatePort(port)
    port = tonumber(port)
    if not port or port < 1 or port > 65535 then
        return false, "Порт должен быть 1-65535"
    end
    return true, port
end

function Utils:CleanText(str, maxLen)
    print("[CleanText] ВХОД: str =", tostring(str), "maxLen =", maxLen)
    if not str then return "" end
    str = tostring(str)

    str = string.gsub(str, "%s+", " ")
    str = string.gsub(str, "^%s*(.-)%s*$", "%1")
    if maxLen then
        str = string.sub(str, 1, maxLen)
    end
    print("[CleanText] ВЫХОД: str =", tostring(str))
    return str
end

function Utils:CleanForTTS(str)
    print("[CleanForTTS] ВХОД: str =", tostring(str), "тип =", type(str))

    if str == nil then
        print("[CleanForTTS] ⚠️ str = nil, возвращаем пустую строку")
        return ""
    end

    if type(str) ~= "string" then
        print("[CleanForTTS] ⚠️ str не строка, тип:", type(str))
        str = tostring(str) or ""
        print("[CleanForTTS] 🔄 Приведён к строке:", str)
    end

    if not str or str == "" then
        print("[CleanForTTS] ❌ str пустая, возвращаем пустую строку")
        return ""
    end

    str = tostring(str)
    print("[CleanForTTS] После tostring: '" .. str .. "'")

    str = string.gsub(str, "`[^`]*`", " ")
    str = string.gsub(str, "{[^{}]-}", " ")
    str = string.gsub(str, "[<>\"'&]", "")
    str = string.gsub(str, "%s+", " ")
    str = string.gsub(str, "^%s*(.-)%s*$", "%1")

    print("[CleanForTTS] ВЫХОД: str = '" .. tostring(str) .. "', длина =", #str)

    if str == "" and tostring(str) ~= "" and tostring(str) ~= " " then
        print("[CleanForTTS] ⚠️ После очистки строка пуста, возвращаем исходный текст")
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

    return {
        get = function(_, key)
            local now = CurTime()
            for i = #order, 1, -1 do
                local k = order[i]
                if timestamps[k] and (now - timestamps[k]) > ttl then
                    cache[k] = nil
                    timestamps[k] = nil
                    table.remove(order, i)
                end
            end
            return cache[key]
        end,
        set = function(_, key, value)
            local now = CurTime()
            for i, k in ipairs(order) do
                if k == key then
                    table.remove(order, i)
                    break
                end
            end
            table.insert(order, key)
            cache[key] = value
            timestamps[key] = now
            while #order > maxSize do
                local oldest = table.remove(order, 1)
                cache[oldest] = nil
                timestamps[oldest] = nil
            end
        end,
        has = function(_, key)
            return cache[key] ~= nil
        end,
        cleanup = function(_)
            cache = {}
            order = {}
            timestamps = {}
        end,
        size = function(_)
            return #order
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

    local prefix = settings and settings.prefix_text or "[AI]"
    local clean = string.gsub(prefix, "^%[", "")
    clean = string.gsub(clean, "%]$", "")
    clean = string.Trim(clean)
    if clean == "" then clean = "AI" end

    PrefixCache:set(steamID, clean)
    return clean
end

function Utils:InvalidatePrefixCache(ply)
    if not self:IsValid(ply) then return end
    if not PrefixCache then return end
    PrefixCache:set(ply:SteamID64(), nil)
end

local HTTPQueue = {}
local HTTPActive = 0
local MAX_HTTP_CONCURRENT = 3

function Utils:HTTPQueue(params)
    print("[HTTPQueue] ========================================")
    print("[HTTPQueue] params =", params)
    if params then
        print("[HTTPQueue] params.url =", params.url)
        print("[HTTPQueue] params.method =", params.method)
    else
        print("[HTTPQueue] params = nil!")
    end
    print("[HTTPQueue] ========================================")

    if not params or not params.url then
        Utils.LogError("HTTP", "Некорректный запрос: нет URL")
        print("[HTTPQueue] ❌ params.url отсутствует!")
        return
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

    item.success = function(code, body)
        HTTPActive = math.max(0, HTTPActive - 1)
        if origSuccess then
            local ok, err = pcall(origSuccess, code, body)
            if not ok then
                Utils.LogError("HTTP", "В success: %s", tostring(err))
            end
        end
        if Utils.HTTPProcess then
             Utils:HTTPProcess()
        end
    end

    item.error = function(err)
        HTTPActive = math.max(0, HTTPActive - 1)
        if origError then
            local ok, err2 = pcall(origError, err)
            if not ok then
                Utils.LogError("HTTP", "В error: %s", tostring(err2))
            end
        end
        if Utils.HTTPProcess then
             Utils:HTTPProcess()
        end
    end

    if SERVER then
        HTTP(item)
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
