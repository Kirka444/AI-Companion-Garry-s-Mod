if AI_COMPANION_UTILS_LOADED then return end
AI_COMPANION_UTILS_LOADED = true
local AC = _G.AI_COMPANION
if not AC or not AC._is_ai_companion then
    ErrorNoHalt("[AI Utils] ОШИБКА: _G.AI_COMPANION не инициализирован!\n")
    ErrorNoHalt("[AI Utils] Убедитесь, что ai_companion_state.lua загружен первым.\n")
    return
end
function AI_DebugPrint(...)
    local debugMode = false
    if AC.Config and AC.Config.DEBUG_MODE then
        debugMode = true
    elseif AC.GetSetting and AC.GetSetting("Debug_Mode") then
        debugMode = true
    elseif AC.Config and AC.Config.Debug then
        debugMode = true
    end
    if debugMode then
        print(...)
    end
end
local function IsValidSafe(ent)
    if ent == nil then return false end
    if type(ent) == "userdata" then
        local ok, result = pcall(function() return ent:IsValid() end)
        if not ok then return false end
        return result
    end
    return IsValid(ent)
end
function SafeCall(func, default, ...)
    if type(func) ~= "function" then return default end
    local args = {...}
    local ok, result = xpcall(
        function() return func(unpack(args)) end,
        function(err)
            AI_Utils.LogError("Utils", "SafeCall error: " .. tostring(err))
        end
    )
    if ok then return result end
    return default
end
function SafeGet(ent, method, default, ...)
    if not IsValidSafe(ent) then return default end
    local ok, result = pcall(function(...) return ent[method](ent, ...) end, ...)
    if ok then return result end
    return default
end
local LOG_LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, FATAL = 4 }
local LOG_FILE = "ai_companion.log"
local CURRENT_LOG_LEVEL = 1
function AI_Log(level, module, msg, ...)
    local levelName = string.upper(level)
    local levelNum = LOG_LEVELS[levelName] or LOG_LEVELS.INFO
    if levelNum < CURRENT_LOG_LEVEL then return end
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local formatted = string.format("[%s] [%s] [%s] %s", timestamp, levelName, module, msg)
    if select("#", ...) > 0 then formatted = string.format(formatted, ...) end
    MsgC(Color(200,200,200), formatted, "\n")
    if levelNum >= LOG_LEVELS.ERROR then
        file.Append(LOG_FILE, formatted .. "\n")
    end
end
function AI_LogInfo(module, msg, ...) AI_Log("INFO", module, msg, ...) end
function AI_LogWarn(module, msg, ...) AI_Log("WARN", module, msg, ...) end
function AI_LogError(module, msg, ...) AI_Log("ERROR", module, msg, ...) end
function AI_LogDebug(module, msg, ...) 
    if AC.GetSetting and AC.GetSetting("Debug_Mode") then
        AI_Log("DEBUG", module, msg, ...)
    end
end
function AI_SafeExecute(module, fn, ...)
    local args = {...}
    return xpcall(
        function() return fn(unpack(args)) end,
        function(err)
            local trace = debug.traceback()
            AI_LogError(module, "Ошибка: %s\n%s", tostring(err), trace)
            return nil, err
        end
    )
end
function AI_ValidateIP(ip)
    if not ip or ip == "" then return false, "IP пустой" end
    return true
end
function AI_ValidatePort(port)
    port = tonumber(port)
    if not port or port < 1 or port > 65535 then 
        return false, "Порт должен быть 1-65535" 
    end
    return true, port
end
local BAD_CHARS_PATTERN = "[<>" .. string.char(39) .. string.char(34) .. "&]"
function AI_SanitizeURL(base, path)
    if not base or base == "" then return "" end
    base = string.gsub(base, BAD_CHARS_PATTERN, "")
    base = string.gsub(base, "/+$", "")
    if path then
        path = string.gsub(path, BAD_CHARS_PATTERN, "")
        path = string.gsub(path, "^/+", "")
        path = string.gsub(path, "/+$", "")
    end
    local url = base
    if path and path ~= "" then url = url .. "/" .. path end
    return url
end
function AI_CleanText(str, maxLen)
    if not str then return "" end
    str = tostring(str)
    str = string.gsub(str, "%s+", " ")
    str = string.gsub(str, "^%s*(.-)%s*$", "%1")
    if maxLen then str = string.sub(str, 1, maxLen) end
    return str
end
local TTS_BAD_CHARS = "[" .. string.char(39) .. string.char(34) .. "<>]"
function AI_CleanForTTS(str)
    str = AI_CleanText(str, 500)
    str = string.gsub(str, "`[^`]*`", " ")
    str = string.gsub(str, "{[^{}]-}", " ")
    str = string.gsub(str, TTS_BAD_CHARS, "")
    return str
end
function AI_CreateCache(maxSize, ttl)
    maxSize = maxSize or 50
    ttl = ttl or 3600
    local cache = {}
    local order = {}
    local timestamps = {}
    local function cleanup()
        local now = CurTime()
        for i = #order, 1, -1 do
            local key = order[i]
            if timestamps[key] and (now - timestamps[key]) > ttl then
                cache[key] = nil
                timestamps[key] = nil
                table.remove(order, i)
            end
        end
    end
    return {
        get = function(self, key)
            cleanup()
            return cache[key]
        end,
        set = function(self, key, value)
            cleanup()
            for i, k in ipairs(order) do
                if k == key then 
                    table.remove(order, i) 
                    break 
                end
            end
            table.insert(order, key)
            cache[key] = value
            timestamps[key] = CurTime()
            while #order > maxSize do
                local oldest = table.remove(order, 1)
                cache[oldest] = nil
                timestamps[oldest] = nil
            end
        end,
        has = function(self, key) 
            cleanup()
            return cache[key] ~= nil 
        end,
        cleanup = function(self) 
            cache = {} 
            order = {} 
            timestamps = {}
        end,
        size = function(self) 
            cleanup()
            return #order 
        end,
    }
end
function GetPlayerDisplayPrefix(ply)
    if not IsValid(ply) then return "[AI]" end
    local steamID = ply:SteamID64()
    local prefix = AC.Players and AC.Players.PrefixText and AC.Players.PrefixText[steamID]
    if not prefix then
        local settings = GetPlayerSettings(ply)
        prefix = settings and settings.prefix_text or AC.GetSetting("Prefix_Text") or "[AI]"
    end
    local clean = string.gsub(prefix, "^%[", "")
    clean = string.gsub(clean, "%]$", "")
    clean = string.Trim(clean)
    if clean == "" then clean = "AI" end
    return clean
end
function GetPlayerDisplayPrefixColor(ply)
    if not IsValid(ply) then return Color(255, 200, 0) end
    local steamID = ply:SteamID64()
    local rainbow = AC.Players and AC.Players.PrefixRainbow and AC.Players.PrefixRainbow[steamID]
    if rainbow then
        local hue = (CurTime() * 120) % 360
        return HSVToColor(hue, 1, 1)
    end
    local r = (AC.Players and AC.Players.PrefixColorR and AC.Players.PrefixColorR[steamID]) or 
              AC.GetSetting("Prefix_Color_R") or 255
    local g = (AC.Players and AC.Players.PrefixColorG and AC.Players.PrefixColorG[steamID]) or 
              AC.GetSetting("Prefix_Color_G") or 200
    local b = (AC.Players and AC.Players.PrefixColorB and AC.Players.PrefixColorB[steamID]) or 
              AC.GetSetting("Prefix_Color_B") or 0
    return Color(r, g, b)
end
local HTTPQueue = {}
local HTTPActive = 0
local MAX_HTTP_CONCURRENT = 3
function AI_HTTP_Queue(params)
    if not params or not params.url then
        AI_LogError("HTTP", "Некорректный запрос: нет URL")
        return
    end
    table.insert(HTTPQueue, params)
    AI_HTTP_Process()
end
function AI_HTTP_Process()
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
            xpcall(function() origSuccess(code, body) end, function(err)
                AI_LogError("HTTP", "В success: %s", tostring(err))
            end)
        end
        AI_HTTP_Process()
    end
    item.error = function(err)
        HTTPActive = math.max(0, HTTPActive - 1)
        if origError then
            xpcall(function() origError(err) end, function(err2)
                AI_LogError("HTTP", "В error: %s", tostring(err2))
            end)
        end
        AI_HTTP_Process()
    end
    if SERVER then
        HTTP(item)
    else
        AI_LogDebug("HTTP", "Клиент: запрос пропущен: %s", item.url)
        HTTPActive = math.max(0, HTTPActive - 1)
        if origSuccess then
            origSuccess(200, "{}")
        end
        AI_HTTP_Process()
    end
end
function AI_Timer(name, delay, repetitions, fn, module)
    module = module or "Timer"
    timer.Create(name, delay, repetitions, function()
        AI_SafeExecute(module, fn)
    end)
end
function AI_TimerSimple(delay, fn, module, ...)
    module = module or "Timer"
    local args = {...}
    timer.Simple(delay, function()
        AI_SafeExecute(module, function() fn(unpack(args)) end)
    end)
end
function AI_FindInSphere(pos, radius)
    local result = {}
    local ok, ents = pcall(ents.FindInSphere, pos, radius)
    if ok and ents then
        for _, ent in ipairs(ents) do
            if IsValidSafe(ent) then table.insert(result, ent) end
        end
    end
    return result
end
function AI_GetAllCompanions()
    if _G.BotManager and _G.BotManager.GetAllBots then
        return _G.BotManager:GetAllBots()
    end
    local result = {}
    if AC.Companion and AC.Companion.RegisteredBots then
        for _, bot in pairs(AC.Companion.RegisteredBots) do
            if IsValidSafe(bot) then table.insert(result, bot) end
        end
    end
    return result
end
function AI_Hash(str)
    if not str or str == "" then return "empty" end
    local crc = 0
    for i = 1, #str do
        crc = crc + string.byte(str, i) * i
        crc = crc % 16777216
    end
    return string.format("%06x", crc)
end
function AI_IsValidModel(path)
    if not path or path == "" then return false end
    if string.find(path, "%.%.") then return false end
    if string.find(path, "\\") then return false end
    if not string.match(path, "%.mdl$") then return false end
    local ok, exists = pcall(util.IsValidModel, path)
    return ok and exists
end
function AI_IsPassenger(bot)
    if not IsValidSafe(bot) then return false end
    if not bot:InVehicle() then return false end
    local vehicle = bot:GetVehicle()
    if not IsValidSafe(vehicle) then return false end
    if vehicle.IsGlideVehicle and vehicle.seats then
        local driverSeat = vehicle.seats[1]
        if IsValidSafe(driverSeat) then
            local driver = driverSeat:GetDriver()
            if IsValidSafe(driver) and driver ~= bot then
                return true 
            end
        end
        for i = 2, #vehicle.seats do
            local seat = vehicle.seats[i]
            if IsValidSafe(seat) then
                local occupant = seat:GetDriver()
                if occupant == bot then
                    return true 
                end
            end
        end
        return false
    end
    local class = SafeGet(vehicle, "GetClass", "")
    if class == "prop_vehicle_jeep" or class == "prop_vehicle_airboat" or 
       string.find(class, "prop_vehicle_") then
        local driver = SafeGet(vehicle, "GetDriver", nil)
        if IsValidSafe(driver) and driver ~= bot then
            return true
        end
    end
    local driver = SafeGet(vehicle, "GetDriver", nil)
    if IsValidSafe(driver) and driver ~= bot then
        return true
    end
    return false
end
local PrefixCache = AI_CreateCache(32, 60)
function AI_GetCleanPrefix(ply)
    if not IsValidSafe(ply) then return "AI" end
    local steamID = ply:SteamID64()
    local cached = PrefixCache:get(steamID)
    if cached then return cached end
    local settings = nil
    if GetPlayerSettings then
        settings = GetPlayerSettings(ply)
    elseif AC.Settings then
        settings = AC.Settings
    end
    if not settings then
        PrefixCache:set(steamID, "AI")
        return "AI"
    end
    local prefix = settings.prefix_text or AC.GetSetting("Prefix_Text") or "[AI]"
    local clean = string.gsub(prefix, "^%[", "")
    clean = string.gsub(clean, "%]$", "")
    clean = string.Trim(clean)
    if clean == "" then clean = "AI" end
    PrefixCache:set(steamID, clean)
    return clean
end
function AI_InvalidatePrefixCache(ply)
    if not IsValidSafe(ply) then return end
    PrefixCache:set(ply:SteamID64(), nil)
end
function AI_GetPrefixColor(ply)
    if not IsValidSafe(ply) then return Color(255, 200, 0) end
    local settings = nil
    if GetPlayerSettings then
        settings = GetPlayerSettings(ply)
    elseif AC.Settings then
        settings = AC.Settings
    end
    if not settings then return Color(255, 200, 0) end
    if settings.prefix_rainbow or AC.GetSetting("Prefix_Rainbow") then
        local hue = (CurTime() * 120) % 360
        return HSVToColor(hue, 1, 1)
    end
    return Color(
        settings.prefix_r or AC.GetSetting("Prefix_Color_R") or 255,
        settings.prefix_g or AC.GetSetting("Prefix_Color_G") or 200,
        settings.prefix_b or AC.GetSetting("Prefix_Color_B") or 0
    )
end
function SafeGiveWeapon(ent, weaponClass)
    if not AI_Utils.IsValid(ent) then return false end
    if not weaponClass or weaponClass == "" then return false end
    if ent:HasWeapon(weaponClass) then return true end
    local ok, err = pcall(function() ent:Give(weaponClass) end)
    if not ok then
        AI_Utils.LogError("Utils", "Не удалось выдать оружие %s: %s", weaponClass, tostring(err))
        return false
    end
    return true
end
function AI_GetBotIDSafe(ent)
    if not IsValid(ent) then 
        AI_Utils.LogError("Utils", "GetBotIDSafe: ent невалиден")
        return nil 
    end
    if _G.BotManager then
        local uuid = ent._aiUUID
        if uuid then
            local bot = _G.BotManager:GetBotByUUID(uuid)
            if IsValid(bot) and bot == ent then
                return ent:EntIndex()
            end
        end
        local data = _G.BotManager:GetData(ent)
        if data and data.botID then
            return data.botID
        end
        local bots = _G.BotManager:GetAllBots()
        for _, bot in ipairs(bots) do
            if bot == ent then
                return ent:EntIndex()
            end
        end
    end
    if AC.Companion and AC.Companion.RegisteredBots then
        for botID, bot in pairs(AC.Companion.RegisteredBots) do
            if bot == ent then
                AI_Utils.LogWarn("Utils", "GetBotIDSafe: найден в RegisteredBots (устаревший метод)")
                return botID
            end
        end
    end
    local id = ent:EntIndex()
    AI_Utils.LogDebug("Utils", "GetBotIDSafe: возвращаем EntIndex %d (не найден в BotManager)", id)
    return id
end
function GetPlayerSettings(ply)
    if not IsValid(ply) then return nil end
    if _G.GetPlayerSettings then
        return _G.GetPlayerSettings(ply)
    end
    return AC.Settings
end
_G.AI_Utils = {
    IsValid = IsValidSafe,
    SafeCall = SafeCall,
    SafeGet = SafeGet,
    LogInfo = AI_LogInfo,
    LogWarn = AI_LogWarn,
    LogError = AI_LogError,
    LogDebug = AI_LogDebug,
    SafeExecute = AI_SafeExecute,
    ValidateIP = AI_ValidateIP,
    ValidatePort = AI_ValidatePort,
    SanitizeURL = AI_SanitizeURL,
    CleanText = AI_CleanText,
    CleanForTTS = AI_CleanForTTS,
    CreateCache = AI_CreateCache,
    HTTPQueue = AI_HTTP_Queue,
    Timer = AI_Timer,
    TimerSimple = AI_TimerSimple,
    FindInSphere = AI_FindInSphere,
    GetAllCompanions = AI_GetAllCompanions,
    Hash = AI_Hash,
    IsValidModel = AI_IsValidModel,
    IsPassenger = AI_IsPassenger,
    GetCleanPrefix = AI_GetCleanPrefix,
    GetPrefixColor = AI_GetPrefixColor,
    SafeGiveWeapon = SafeGiveWeapon,
    InvalidatePrefixCache = AI_InvalidatePrefixCache,
    GetBotIDSafe = AI_GetBotIDSafe,
}
_G.GetAICleanPrefix = AI_GetCleanPrefix
_G.GetAIPrefixColor = AI_GetPrefixColor
AC.Utils = {
    IsValid = IsValidSafe,
    SafeCall = SafeCall,
    SafeGet = SafeGet,
    LogInfo = AI_LogInfo,
    LogWarn = AI_LogWarn,
    LogError = AI_LogError,
    LogDebug = AI_LogDebug,
    SafeExecute = AI_SafeExecute,
    ValidateIP = AI_ValidateIP,
    ValidatePort = AI_ValidatePort,
    SanitizeURL = AI_SanitizeURL,
    CleanText = AI_CleanText,
    CleanForTTS = AI_CleanForTTS,
    CreateCache = AI_CreateCache,
    HTTPQueue = AI_HTTP_Queue,
    Timer = AI_Timer,
    TimerSimple = AI_TimerSimple,
    FindInSphere = AI_FindInSphere,
    GetAllCompanions = AI_GetAllCompanions,
    Hash = AI_Hash,
    IsValidModel = AI_IsValidModel,
    IsPassenger = AI_IsPassenger,
    GetCleanPrefix = AI_GetCleanPrefix,
    GetPrefixColor = AI_GetPrefixColor,
    InvalidatePrefixCache = AI_InvalidatePrefixCache,
    SafeGiveWeapon = SafeGiveWeapon,
    GetBotIDSafe = AI_GetBotIDSafe,
}
concommand.Add("ai_utils_test", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы!")
        end
        return
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI UTILS - ТЕСТ")
    print("═══════════════════════════════════════════════════════")
    print("")
    print("  AC._is_ai_companion: " .. tostring(AC._is_ai_companion))
    print("  AC._version: " .. tostring(AC._version))
    print("  AC.Settings.Prefix_Text: " .. tostring(AC.GetSetting("Prefix_Text")))
    print("  AC.Settings.Debug_Mode: " .. tostring(AC.GetSetting("Debug_Mode")))
    print("")
    print("  AI_Utils.IsValid(ply): " .. tostring(AI_Utils.IsValid(ply)))
    print("  AI_Utils.ValidateIP('127.0.0.1'): " .. tostring(AI_Utils.ValidateIP("127.0.0.1")))
    print("  AI_Utils.ValidatePort(1234): " .. tostring(AI_Utils.ValidatePort(1234)))
    print("")
    print("═══════════════════════════════════════════════════════")
    print("")
    if IsValid(ply) then
        ply:ChatPrint("[AI] Тест утилит завершён, результат в консоли")
    end
end)
AI_DebugPrint("[AI Utils] загружен")