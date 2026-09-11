local Logger = {}
function Logger:new(utils, config)
	local obj = {
		utils = utils,
		config = config,
		_initialized = false,
		_logLevels = {
			DEBUG = 0,
			INFO = 1,
			WARN = 2,
			ERROR = 3,
			FATAL = 4,
		},
		_currentLevel = 4, -- FATAL по умолчанию
		_enabled = false,  -- Отключено по умолчанию
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
function Logger:init()
	if self._initialized then return end
	-- Базовая проверка конфига (если передан напрямую)
	if self.config then
		local debugMode = self.config:get("DEBUG_MODE") or false
		if debugMode then
			self._currentLevel = self._logLevels.DEBUG
			self._enabled = true
		end
	end
	-- Проверка через State (с защитой от порядка инициализации)
	local getLocator = AICompanion.GetLocator
	if getLocator then
		local ok, loc = pcall(getLocator)
		if not ok then
			ErrorNoHaltWithStack("[Logger] Ошибка получения локатора: " .. tostring(loc) .. "\n")
			return
		end
		if loc and loc.has and loc:has("state") then
			local state = loc:get("state")
			-- ✅ Проверяем МЕТОД, а не таблицу
			if state and state.getSetting then
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
	end
	self._initialized = true
end
function Logger:IsEnabled()
	return self._enabled
end
function Logger:SetEnabled(enabled)
	self._enabled = enabled
	-- ИСПРАВЛЕНО: добавлены скобки () для вызова функции
	local getLocator = AICompanion.GetLocator
	if getLocator then
		local ok, loc = pcall(getLocator)
		if not ok then
			ErrorNoHaltWithStack("[Logger] Ошибка получения локатора: " .. tostring(loc) .. "\n")
			return
		end
		if loc and loc.has and loc:has("state") then
			local state = loc:get("state")
			if state and state.setSetting then
				state:setSetting("Logger_Enabled", enabled)
			end
		end
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
	return "FATAL"
end
function Logger:Log(level, module, msg, ...)
	local levelName = string.upper(level)
	local levelNum = self._logLevels[levelName] or self._logLevels.FATAL
	-- Жесткая фильтрация по уровню
	if levelNum < self._currentLevel then
		return
	end
	-- Если логирование выключено глобально, пропускаем всё, кроме FATAL
	if not self._enabled and levelNum < self._logLevels.FATAL then
		return
	end
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local formatted = string.format("[%s] [%s] [%s] %s", timestamp, levelName, module, msg)
	if select("#", ...) > 0 then
		formatted = string.format(formatted, ...)
	end
	local colors = {
		DEBUG = Color(150, 150, 200),
		INFO = Color(200, 200, 200),
		WARN = Color(255, 200, 100),
		ERROR = Color(255, 100, 100),
		FATAL = Color(255, 0, 0),
	}
	local color = colors[levelName] or Color(200, 200, 200)
	MsgC(color, formatted, "\n")
	return formatted
end
function Logger:Debug(module, msg, ...) return self:Log("DEBUG", module, msg, ...) end
function Logger:Info(module, msg, ...) return self:Log("INFO", module, msg, ...) end
function Logger:Warn(module, msg, ...) return self:Log("WARN", module, msg, ...) end
function Logger:Error(module, msg, ...) return self:Log("ERROR", module, msg, ...) end
function Logger:Fatal(module, msg, ...) return self:Log("FATAL", module, msg, ...) end
function Logger:GetStats()
	return {
		currentLevel = self:GetLevel(),
		enabled = self._enabled,
	}
end
function Logger:DebugPrint()
	print(" ")
	print("═══════════════════════════════════════════════════════")
	print("        AI COMPANION - ЛОГГЕР")
	print("═══════════════════════════════════════════════════════")
	print(" ")
	local stats = self:GetStats()
	print("  Логирование: " .. (stats.enabled and "✅ ВКЛЮЧЕНО" or "❌ ВЫКЛЮЧЕНО"))
	print("  Уровень логирования: " .. stats.currentLevel)
	print("  Сохранение в файл: ОТКЛЮЧЕНО")
	print(" ")
	print("═══════════════════════════════════════════════════════")
	print(" ")
end
if SERVER then
concommand.Add("ai_companion_logger_debug", function(ply)
	local locator = AICompanion.GetLocator()
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
concommand.Add("ai_companion_logger_level", function(ply, cmd, args)
	local locator = AICompanion.GetLocator()
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
concommand.Add("ai_companion_logger_toggle", function(ply, cmd, args)
	local locator = AICompanion.GetLocator()
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
end

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