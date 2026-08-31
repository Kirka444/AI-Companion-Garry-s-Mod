
local Logger = {}

function Logger:new(utils, config)
    local obj = {
        utils = utils,
        config = config,
        _initialized = false,
        _logFile = "ai_companion.log",
        _logLevels = {
            DEBUG = 0,
            INFO = 1,
            WARN = 2,
            ERROR = 3,
            FATAL = 4,
        },
        _currentLevel = 1,
        _maxFileSize = 1048576,
        _backupCount = 3,
        _buffered = {},
        _flushInterval = 5,
        _lastFlush = 0,
        _enabled = false,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Logger:init()
    if self._initialized then return end

    if self.config then
        local debugMode = self.config:get("DEBUG_MODE") or false
        if debugMode then
            self._currentLevel = self._logLevels.DEBUG
            self._enabled = true
        end
    end

    local locator = _G.AI_GetLocator()
    if locator and locator:has("state") then
        local state = locator:get("state")
        if state and state.Settings then
            local debugMode = state:getSetting("Debug_Mode") or false
            if debugMode then
                self._currentLevel = self._logLevels.DEBUG
                self._enabled = true
            end

            local enabled = state:getSetting("Logger_Enabled")
            if enabled ~= nil then
                self._enabled = enabled
            end
        end
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Logger", "Логгер инициализирован (включён: %s, уровень: %s)",
            tostring(self._enabled), self:GetLevel())
    end
end

function Logger:IsEnabled()
    return self._enabled
end

function Logger:SetEnabled(enabled)
    self._enabled = enabled

    local locator = _G.AI_GetLocator()
    if locator and locator:has("state") then
        local state = locator:get("state")
        if state and state.Settings then
            state:setSetting("Logger_Enabled", enabled)
        end
    end

    if self.utils then
        self.utils.LogInfo("Logger", "Логирование %s", enabled and "ВКЛЮЧЕНО" or "ВЫКЛЮЧЕНО")
    end
end

function Logger:Toggle()
    self:SetEnabled(not self._enabled)
    return self._enabled
end

function Logger:SetLevel(level)
    local levelNum = self._logLevels[level]
    if levelNum then
        self._currentLevel = levelNum
        return true
    end
    return false
end

function Logger:GetLevel()
    for name, num in pairs(self._logLevels) do
        if num == self._currentLevel then
            return name
        end
    end
    return "INFO"
end

function Logger:Log(level, module, msg, ...)

    local levelName = string.upper(level)
    local levelNum = self._logLevels[levelName] or self._logLevels.INFO

    if levelNum < self._currentLevel then
        return
    end

    if not self._enabled then

        if levelNum < self._logLevels.ERROR then
            return
        end

    end

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local formatted = string.format("[%s] [%s] [%s] %s", timestamp, levelName, module, msg)
    if select("#", ...) > 0 then
        formatted = string.format(formatted, ...)
    end

    if self._enabled or levelNum >= self._logLevels.ERROR then
        local colors = {
            DEBUG = Color(150, 150, 200),
            INFO = Color(200, 200, 200),
            WARN = Color(255, 200, 100),
            ERROR = Color(255, 100, 100),
            FATAL = Color(255, 0, 0),
        }
        local color = colors[levelName] or Color(200, 200, 200)
        MsgC(color, formatted, "\n")
    end

    if levelNum >= self._logLevels.ERROR then
        self:WriteToFile(formatted)
    end

    return formatted
end

function Logger:Debug(module, msg, ...)
    return self:Log("DEBUG", module, msg, ...)
end

function Logger:Info(module, msg, ...)
    return self:Log("INFO", module, msg, ...)
end

function Logger:Warn(module, msg, ...)
    return self:Log("WARN", module, msg, ...)
end

function Logger:Error(module, msg, ...)
    return self:Log("ERROR", module, msg, ...)
end

function Logger:Fatal(module, msg, ...)
    return self:Log("FATAL", module, msg, ...)
end

function Logger:WriteToFile(text)
    if not text or text == "" then return end

    local size = file.Size(self._logFile, "DATA") or 0
    if size > self._maxFileSize then
        self:RotateLogs()
    end

    file.Append(self._logFile, text .. "\n")
end

function Logger:RotateLogs()
    local backupPath = self._logFile .. "." .. self._backupCount .. ".bak"
    if file.Exists(backupPath, "DATA") then
        file.Delete(backupPath)
    end

    for i = self._backupCount - 1, 1, -1 do
        local oldPath = self._logFile .. "." .. i .. ".bak"
        local newPath = self._logFile .. "." .. (i + 1) .. ".bak"
        if file.Exists(oldPath, "DATA") then
            file.Rename(oldPath, newPath)
        end
    end

    if file.Exists(self._logFile, "DATA") then
        file.Rename(self._logFile, self._logFile .. ".1.bak")
    end
end

function Logger:ClearLogs()
    local files = file.Find(self._logFile .. "*", "DATA")
    for _, f in ipairs(files) do
        if file.Exists(f, "DATA") then
            file.Delete(f)
        end
    end
end

function Logger:GetStats()
    local stats = {
        currentLevel = self:GetLevel(),
        logFile = self._logFile,
        fileSize = file.Size(self._logFile, "DATA") or 0,
        backupCount = self._backupCount,
        maxFileSize = self._maxFileSize,
        enabled = self._enabled,
    }

    stats.backups = {}
    for i = 1, self._backupCount do
        local path = self._logFile .. "." .. i .. ".bak"
        if file.Exists(path, "DATA") then
            table.insert(stats.backups, {
                name = path,
                size = file.Size(path, "DATA") or 0,
            })
        end
    end

    return stats
end

function Logger:DebugPrint()
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI COMPANION - ЛОГГЕР")
    print("═══════════════════════════════════════════════════════")
    print("")
    local stats = self:GetStats()
    print("  Логирование: " .. (stats.enabled and "✅ ВКЛЮЧЕНО" or "❌ ВЫКЛЮЧЕНО"))
    print("  Уровень логирования: " .. stats.currentLevel)
    print("  Файл лога: " .. stats.logFile)
    print("  Размер: " .. math.Round(stats.fileSize / 1024, 2) .. " KB")
    print("  Бэкапов: " .. #stats.backups)
    print("")
    if #stats.backups > 0 then
        print("  Бэкапы:")
        for _, b in ipairs(stats.backups) do
            print("     " .. b.name .. " (" .. math.Round(b.size / 1024, 2) .. " KB)")
        end
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("")
end

concommand.Add("ai_logger_debug", function(ply)
    local locator = _G.AI_GetLocator()
    if not locator or not locator:has("logger") then
        print("[AI] Логгер не найден!")
        return
    end

    local logger = locator:get("logger")

    if logger.utils and logger.utils:IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end

    logger:DebugPrint()

    if logger.utils and logger.utils:IsValid(ply) then
        ply:ChatPrint("[AI] Статус логгера выведен в консоль")
    end
end)

concommand.Add("ai_logger_level", function(ply, cmd, args)
    local locator = _G.AI_GetLocator()
    if not locator or not locator:has("logger") then
        print("[AI] Логгер не найден!")
        return
    end

    local logger = locator:get("logger")

    if logger.utils and logger.utils:IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end

    if #args < 1 then
        print("[AI] Использование: ai_logger_level <DEBUG|INFO|WARN|ERROR|FATAL>")
        return
    end

    local level = string.upper(args[1])
    if logger:SetLevel(level) then
        print("[AI] Уровень логирования установлен: " .. level)
        if logger.utils and logger.utils:IsValid(ply) then
            ply:ChatPrint("[AI] Уровень логирования: " .. level)
        end
    else
        print("[AI] Неизвестный уровень: " .. level)
    end
end)

concommand.Add("ai_logger_clear", function(ply)
    local locator = _G.AI_GetLocator()
    if not locator or not locator:has("logger") then
        print("[AI] Логгер не найден!")
        return
    end

    local logger = locator:get("logger")

    if logger.utils and logger.utils:IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end

    logger:ClearLogs()
    print("[AI] Логи очищены")

    if logger.utils and logger.utils:IsValid(ply) then
        ply:ChatPrint("[AI] Логи очищены")
    end
end)

concommand.Add("ai_logger_toggle", function(ply, cmd, args)
    local locator = _G.AI_GetLocator()
    if not locator or not locator:has("logger") then
        print("[AI] Логгер не найден!")
        return
    end

    local logger = locator:get("logger")

    if logger.utils and logger.utils:IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы могут использовать эту команду!")
        return
    end

    local newState = logger:Toggle()
    local stateText = newState and "ВКЛЮЧЕН" or "ВЫКЛЮЧЕН"

    local msg = "[AI] Логирование " .. stateText
    print(msg)

    if logger.utils and logger.utils:IsValid(ply) then
        ply:ChatPrint(msg)
    end

    if newState then
        local level = logger:GetLevel()
        print("[AI] Текущий уровень логирования: " .. level)
        if logger.utils and logger.utils:IsValid(ply) then
            ply:ChatPrint("[AI] Уровень логирования: " .. level)
        end
    end
end)

function Logger:GetAPI()
    return {
        Debug = function(module, msg, ...) return self:Debug(module, msg, ...) end,
        Info = function(module, msg, ...) return self:Info(module, msg, ...) end,
        Warn = function(module, msg, ...) return self:Warn(module, msg, ...) end,
        Error = function(module, msg, ...) return self:Error(module, msg, ...) end,
        Fatal = function(module, msg, ...) return self:Fatal(module, msg, ...) end,
        SetLevel = function(level) return self:SetLevel(level) end,
        GetLevel = function() return self:GetLevel() end,
        GetStats = function() return self:GetStats() end,
        IsEnabled = function() return self:IsEnabled() end,
        SetEnabled = function(enabled) return self:SetEnabled(enabled) end,
        Toggle = function() return self:Toggle() end,
    }
end

return Logger
