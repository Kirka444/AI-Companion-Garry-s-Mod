local Shared = {}

local SENSITIVE_KEYS = {
    ["LLM_API_Key"] = true,
    ["TTS_API_Key"] = true,
    ["Yandex_Folder_ID"] = true,
    ["LLM_Folder_ID"] = true,
    ["LLM_Client_ID"] = true,
}

function Shared:IsSensitiveKey(key)
    return SENSITIVE_KEYS[key] == true
end

function Shared:new(utils, config, state)
	local obj = {
		utils = utils,
		config = config,
		state = state,
		_initialized = false,
		_rateLimiter = {},
		_rateLimiterLastClean = 0,
		_lastSyncedJSON = {},
		_lastSyncedJSONTime = {},
	}
	setmetatable(obj, self)
	self.__index = self
	return obj
end
function Shared:GetLocalized(key, ...)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and locale.Get then
			return locale:Get(key, ...)
		end
	end
	return key
end
function Shared:init()
	if self._initialized then return end
	self:RegisterNetworkMessages()
	if SERVER then
		self:SetupNetReceivers()
	end
	if CLIENT then
		self:SetupClientReceivers()
	end
	self._initialized = true
	if self.utils then
		self.utils.LogInfo("Shared", self:GetLocalized("log_shared_init"))
	end
end
function Shared:RegisterNetworkMessages()
	if not SERVER then return end
	local messages = {
		"gmod.one/ai-companion/settings-sync",
		"gmod.one/ai-companion/settings-sync-chunk",
		"gmod.one/ai-companion/chat-broadcast",
		"gmod.one/ai-companion/private-chat",
		"gmod.one/ai-companion/play-audio",
		"gmod.one/ai-companion/tts-global-status",
		"gmod.one/ai-companion/auto-sync-update",
		"gmod.one/ai-companion/locale-sync",
		"gmod.one/ai-companion/config-sync",
		"gmod.one/ai-companion/request-config",
		"gmod.one/ai-companion/set-setting",
		"gmod.one/ai-companion/mode-sync",
		"gmod.one/ai-companion/owner-sync",
		"gmod.one/ai-companion/color-sync",
		"gmod.one/ai-companion/settings-request",
		"gmod.one/ai-companion/set-global-setting",
		"gmod.one/ai-companion/global-setting-updated",
		"gmod.one/ai-companion/player-settings-sync",
		"gmod.one/ai-companion/request-player-settings",
		"gmod.one/ai-companion/memory-sync",
		"gmod.one/ai-companion/memory-add",
		"gmod.one/ai-companion/memory-clear",
		"gmod.one/ai-companion/memory-request",
	}
	for _, name in ipairs(messages) do
		util.AddNetworkString(name)
	end
end
function Shared:GetSetting(key, default)
	if self.state then
		local val = self.state:getSetting(key)
		if val ~= nil then return val end
	end
	return default
end
function Shared:GetState(key, default)
	if self.state then
		local val = self.state:getState(key)
		if val ~= nil then return val end
	end
	return default
end
function Shared:SanitizeString(str, maxLen)
	if type(str) ~= "string" then return "" end
	if maxLen and #str > maxLen then
		str = string.sub(str, 1, maxLen)
	end
	str = string.gsub(str, "[<>\"'&;`]", "")
	str = string.gsub(str, "[\r\n]", " ")
	return str
end
function Shared:CheckRateLimit(steamID, action, maxRequests, window)
	if not steamID or not action then return false end
	-- Периодическая очистка старых записей (раз в 5 минут)
	local now = CurTime()
	if now - (self._rateLimiterLastClean or 0) > 300 then
		self._rateLimiterLastClean = now
		for k, v in pairs(self._rateLimiter) do
			if now - v.first > 600 then
				self._rateLimiter[k] = nil
			end
		end
	end
	local key = steamID .. "_" .. action
	if not self._rateLimiter[key] then
		self._rateLimiter[key] = { count = 1, first = now }
		return true
	end
	local limit = self._rateLimiter[key]
	if now - limit.first > window then
		limit.count = 1
		limit.first = now
		return true
	end
	if limit.count >= maxRequests then
		return false
	end
	limit.count = limit.count + 1
	return true
end
function Shared:ValidateSettings(tbl)
	if type(tbl) ~= "table" then return false end
	local ALLOWED_KEYS = {
		llm_ip = "string", llm_port = "number", llm_model = "string",
		comfyui_ip = "string", comfyui_port = "number",
		tts_ip = "string", tts_port = "number",
		debug_mode = "boolean", prefix_text = "string",
		prefix_r = "number", prefix_g = "number", prefix_b = "number",
		prefix_rainbow = "boolean", tts_enabled = "boolean",
		llm_enabled = "boolean", stealth_mode = "boolean",
		defender_mode = "boolean", medic_mode = "boolean",
		pacifist_mode = "boolean", aggressive_mode = "boolean",
		companion_nick = "string", model_path = "string",
		combat_weapon = "string", melee_weapon = "string",
		idle_weapon = "string", show_sender_name = "boolean",
		tts_personal = "boolean", locale = "string",
		llm_timeout = "number", tts_timeout = "number",
		llm_mode = "string", tts_mode = "string",
		llm_provider = "string", llm_api_key = "string",
		llm_cloud_model = "string", llm_endpoint = "string",
		llm_folder_id = "string", llm_client_id = "string", llm_scope = "string",
		llm_temperature = "number", llm_max_tokens = "number",
		tts_provider = "string", tts_api_key = "string",
		tts_voice = "string", tts_language = "string",
		tts_endpoint = "string", tts_speed = "number",
		yandex_folder_id = "string", yandex_voice = "string",
		yandex_lang = "string", vk_voice = "string",
		vk_tempo = "number", auto_sync_global = "boolean",
		custom_prompt_enabled = "boolean",
		custom_prompt_text = "string",
		allow_custom_prompts = "boolean",
		tts_workflow_enabled = "boolean",
		tts_workflow = "table",
		tts_workflow_filename = "string",
		global_tts_enabled = "boolean",
		global_llm_enabled = "boolean",
		memory_enabled = "boolean",
		menu_active_tab = "string",
	}
	for key, value in pairs(tbl) do
		local keyLower = string.lower(tostring(key))
		local expectedType = ALLOWED_KEYS[keyLower]
		if not expectedType then return false end
		if type(value) ~= expectedType then
			if expectedType == "number" and type(value) == "string" then
				local num = tonumber(value)
				if num then
					tbl[key] = num
					value = num
				else
					return false
				end
			else
				return false
			end
		end
		if expectedType == "string" and #value > 8000 then return false end
		if expectedType == "number" then
			if value ~= value or value == math.huge or value == -math.huge then
				return false
			end
		end
		if keyLower == "llm_port" or keyLower == "comfyui_port" or keyLower == "tts_port" then
			local port = tonumber(value)
			if not port or port < 1 or port > 65535 then return false end
		end
	end
	return true
end
function Shared:SetupNetReceivers()
	if not SERVER then return end
	net.Receive("gmod.one/ai-companion/set-setting", function(len, ply)
		if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
		local steamID = ply:SteamID64()
		if not self:CheckRateLimit(steamID, "set_setting", 15, 60) then return end
		local key = self:SanitizeString(net.ReadString(), 64)
		if key == "" then return end
		local valueStr = self:SanitizeString(net.ReadString(), key == "Custom_Prompt_Text" and 8000 or 500)

		-- Кастомный промпт теперь ВСЕГДА персональный
		local isPersonalPrompt = key == "Custom_Prompt_Enabled" or key == "Custom_Prompt_Text"

		if self.state and self.state:IsGlobalKey(key) and not isPersonalPrompt then
			return
		end

		local value
		if valueStr == "true" then value = true
		elseif valueStr == "false" then value = false
		else
			local num = tonumber(valueStr)
			if num and num == num and num ~= math.huge and num ~= -math.huge then
				value = num
			else
				value = valueStr
			end
		end
		if self.state then
			self.state:setPlayerSetting(steamID, key, value)
			if self.utils and self.utils.InvalidatePrefixCache then
				self.utils:InvalidatePrefixCache(ply)
			end
			-- Принудительно сохраняем настройки игрока на диск
			self.state:SavePlayerSettingsToFile()
		end
		local keyLower = string.lower(key)
		local locator = AICompanion.GetLocator()
		if locator and locator:has("botmanager") then
			local botmanager = locator:get("botmanager")
			local bot = botmanager:GetBotByOwner(ply)
			if bot and bot:IsValid() then
				local data = botmanager:GetData(bot)
				if data and data.config then
					local keyMap = {
						["combat_weapon"] = "combat_weapon",
						["melee_weapon"] = "melee_weapon",
						["idle_weapon"] = "idle_weapon",
						["stealth_mode"] = "stealth_mode",
						["defender_mode"] = "defender_mode",
						["medic_mode"] = "medic_mode",
						["pacifist_mode"] = "pacifist_mode",
						["aggressive_mode"] = "aggressive_mode",
						["show_sender_name"] = "show_sender_name",
						["companion_nick"] = "companion_nick",
						["model_path"] = "model_path",
						["prefix_color_r"] = nil,
						["prefix_color_g"] = nil,
						["prefix_color_b"] = nil,
						["prefix_text"] = nil,
						["prefix_rainbow"] = nil,
					}
					local botKey = keyMap[keyLower]
					if botKey then
						data.config[botKey] = value
						botmanager:UpdateData(bot, data)
						if self.utils then
						end
					end
				end
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/set-global-setting", function(len, ply)
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("settings_admin_only"))
			return
		end
		local key = self:SanitizeString(net.ReadString(), 64)
		if key == "" then return end
		local valueStr = self:SanitizeString(net.ReadString(), key == "Custom_Prompt_Text" and 8000 or 500)
		local value
		if valueStr == "true" then value = true
		elseif valueStr == "false" then value = false
		else
			local num = tonumber(valueStr)
			if num and num == num and num ~= math.huge and num ~= -math.huge then
				value = num
			else
				value = valueStr
			end
		end
		if self.state then
			self.state:setSetting(key, value)
			if key == "LLM_Enabled" or key == "TTS_Enabled" then
				self.state:setState(key, value)
				if self.utils then
				end
			end
			net.Start("gmod.one/ai-companion/global-setting-updated")
			net.WriteString(key)
			net.WriteString(tostring(value))
			net.Broadcast()
		end
	end)
	net.Receive("gmod.one/ai-companion/settings-request", function(len, ply)
		if not self:CheckRateLimit(ply:SteamID64(), "request_settings", 1, 5) then
			return
		end
		timer.Simple(0.5, function()
			if self.utils:IsValid(ply) then
				self:SyncSettingsToClient(ply)
				self:SyncPlayerSettingsToClient(ply)
			end
		end)
	end)
	net.Receive("gmod.one/ai-companion/request-player-settings", function(len, ply)
		if not self:CheckRateLimit(ply:SteamID64(), "request_player_settings", 1, 5) then return end
		self:SyncPlayerSettingsToClient(ply)
	end)
	net.Receive("gmod.one/ai-companion/request-config", function(len, ply)
		if not self:CheckRateLimit(ply:SteamID64(), "request_config", 5, 30) then return end
		self:SyncConfigToClient(ply)
	end)
	net.Receive("gmod.one/ai-companion/locale-sync", function(len, ply)
		local lang = self:SanitizeString(net.ReadString(), 10)
		if lang then
			local locale = AICompanion.GetLocale()
			if locale and locale.SetLang then
				locale:SetLang(lang)
				-- Сохраняем как ПЕРСОНАЛЬНУЮ настройку игрока
				if self.state then
					local steamID = ply:SteamID64()
					self.state:setPlayerSetting(steamID, "Locale", lang)
					-- Принудительно сохраняем настройки игрока на диск сразу
					self.state:SavePlayerSettingsToFile()
				end
				-- Отправляем подтверждение только этому игроку
				net.Start("gmod.one/ai-companion/locale-sync")
				net.WriteString(lang)
				net.Send(ply)
			end
		end
	end)
	hook.Add("PlayerInitialSpawn", "gmod.one/ai-companion/set-admin-status", function(ply)
		if not SERVER then return end
		timer.Simple(0.5, function()
			if IsValid(ply) then
				ply:SetNWBool("AI_IsAdmin", ply:IsAdmin())
				-- Отправляем персональный язык игрока при входе
				local steamID = ply:SteamID64()
				local playerLang = self.state and self.state:getPlayerSetting(steamID, "Locale")
				if playerLang then
					net.Start("gmod.one/ai-companion/locale-sync")
					net.WriteString(playerLang)
					net.Send(ply)
				end
				timer.Simple(1, function()
					if IsValid(ply) then
						self:SyncPlayerSettingsToClient(ply)
						timer.Simple(1, function()
							if IsValid(ply) then
								self:SyncPlayerSettingsToClient(ply)
							end
						end)
					end
				end)
			end
		end)
	end)
	hook.Add("PlayerChangedTeam", "gmod.one/ai-companion/update-admin-status", function(ply)
		if not SERVER then return end
		if IsValid(ply) then
			ply:SetNWBool("AI_IsAdmin", ply:IsAdmin())
		end
	end)
end
function Shared:SyncSettingsToClient(ply)
	if not SERVER or not self.utils or not self.utils:IsValid(ply) then return end
	if ply:IsBot() then return end
	local settings = {}
	if self.state then
		local global = self.state:getRaw("Settings") or {}
		local playerSettings = self.state:getPlayerSettings(ply:SteamID64()) or {}
		local importantKeys = {
			"LLM_IP", "LLM_Port", "LLM_Model", "LLM_Mode",
			"LLM_Timeout",
			"LLM_Folder_ID", "LLM_Client_ID", "LLM_Scope",
			"TTS_IP", "TTS_Port", "TTS_Mode",
			"TTS_Timeout",
			"Prefix_Text", "Locale",
			"Companion_Nick", "Model_Path",
			"Debug_Mode",
		}
		for _, key in ipairs(importantKeys) do
			if not self:IsSensitiveKey(key) then
				if global[key] ~= nil then
					settings[key] = global[key]
				end
				if playerSettings[key] ~= nil then
					settings[key] = playerSettings[key]
				end
			end
		end

		-- Кастомный промпт — ТОЛЬКО персональные настройки
		settings["Custom_Prompt_Enabled"] = playerSettings["Custom_Prompt_Enabled"] or false
		settings["Custom_Prompt_Text"] = playerSettings["Custom_Prompt_Text"] or ""
		local state = self.state:getRaw("State") or {}
		if state.TTS_Enabled ~= nil then
			settings.tts_enabled = state.TTS_Enabled
		else
			settings.tts_enabled = false
		end
		if state.LLM_Enabled ~= nil then
			settings.llm_enabled = state.LLM_Enabled
		else
			settings.llm_enabled = true
		end
	end
	local json = util.TableToJSON(settings)
	if json and #json <= 8000 then
		net.Start("gmod.one/ai-companion/settings-sync")
		net.WriteString(json)
		net.Send(ply)
	elseif json then
		self:SyncSettingsChunked(ply, settings)
	end
end
function Shared:SyncSettingsChunked(ply, settings)
	if not SERVER then return end
	local json = util.TableToJSON(settings)
	if not json then return end
	local chunkSize = 4000
	local totalLen = #json
	local numChunks = math.ceil(totalLen / chunkSize)
	if numChunks > 10 then
		local minimal = {}
		local essential = {"LLM_IP", "LLM_Port", "TTS_IP", "TTS_Port", "Prefix_Text"}
		for _, k in ipairs(essential) do
			if settings[k] ~= nil then
				minimal[k] = settings[k]
			end
		end
		json = util.TableToJSON(minimal)
		if not json then return end
		totalLen = #json
		numChunks = math.ceil(totalLen / chunkSize)
	end
	for i = 1, numChunks do
		local startPos = (i - 1) * chunkSize + 1
		local endPos = math.min(i * chunkSize, totalLen)
		local chunk = string.sub(json, startPos, endPos)
		net.Start("gmod.one/ai-companion/settings-sync-chunk")
		net.WriteUInt(numChunks, 16)
		net.WriteUInt(i, 16)
		net.WriteString(chunk)
		net.Send(ply)
		if i < numChunks then
			timer.Simple(0.02, function() end)
		end
	end
end
function Shared:SyncPlayerSettingsToClient(ply)
	if not SERVER or not self.utils or not self.utils:IsValid(ply) then return end
	if ply:IsBot() then return end
	local steamID = ply:SteamID64()
	local settings = self.state:getPlayerSettings(steamID) or {}
	local requiredKeys = {
		Prefix_Text = "[AI]", Prefix_Color_R = 255, Prefix_Color_G = 200,
		Prefix_Color_B = 0, Prefix_Rainbow = false, Show_Sender_Name = true
	}
	for key, def in pairs(requiredKeys) do
		if settings[key] == nil then settings[key] = def end
	end
	local json = util.TableToJSON(settings)
	if not json then return end
	-- TTL-кэш: не шлём одни и те же данные чаще чем раз в 2 секунды
	local now = CurTime()
	local lastTime = self._lastSyncedJSONTime[steamID] or 0
	if self._lastSyncedJSON[steamID] == json and (now - lastTime) < 2 then
		return
	end
	self._lastSyncedJSON[steamID] = json
	self._lastSyncedJSONTime[steamID] = now
	net.Start("gmod.one/ai-companion/player-settings-sync")
	net.WriteString(json)
	net.Send(ply)
end
function Shared:SyncConfigToClient(ply)
	if not SERVER or not self.utils or not self.utils:IsValid(ply) then return end
	if ply:IsBot() then return end
	local bot = nil
	local botData = nil
	local locator = AICompanion.GetLocator()
	if locator and locator:has("botmanager") then
		bot = locator:get("botmanager"):GetBotByOwner(ply)
		if bot then
			botData = locator:get("botmanager"):GetData(bot)
		end
	end
	-- Персональные настройки берём из PlayerSettings конкретного игрока,
	-- глобальные — из Settings. Иначе config-sync перезаписывает
	-- персональные значения глобальными дефолтами.
	local steamID = ply:SteamID64()
	local playerSettings = self.state:getPlayerSettings(steamID) or {}
	local pGet = function(key, default)
		local v = playerSettings[key]
		if v == nil and self.state then
			v = self.state:getPlayerSetting(steamID, key, nil)
		end
		if v == nil then return default end
		return v
	end
	local configData = {
		version = 1,
		companion_nick = pGet("Companion_Nick", "AI_Companion"),
		model_path = pGet("Model_Path", "models/player/urban.mdl"),
		combat_weapon = pGet("Combat_Weapon", "weapon_smg1"),
		melee_weapon = pGet("Melee_Weapon", "weapon_crowbar"),
		idle_weapon = pGet("Idle_Weapon", "weapon_physgun"),
		stealth_mode = false,
		defender_mode = false,
		medic_mode = false,
		pacifist_mode = false,
		aggressive_mode = false,
		debug_mode = self:GetSetting("Debug_Mode", false),
		tts_enabled = self:GetState("TTS_Enabled", false),
		llm_enabled = self:GetState("LLM_Enabled", true),
		llm_ip = self:GetSetting("LLM_IP", "localhost"),
		llm_port = self:GetSetting("LLM_Port", 1234),
		llm_model = self:GetSetting("LLM_Model", "local-model"),
		tts_ip = self:GetSetting("TTS_IP", "localhost"),
		tts_port = self:GetSetting("TTS_Port", 8188),
		prefix_text = pGet("Prefix_Text", "[AI]"),
		prefix_r = pGet("Prefix_Color_R", 255),
		prefix_g = pGet("Prefix_Color_G", 200),
		prefix_b = pGet("Prefix_Color_B", 0),
		prefix_rainbow = pGet("Prefix_Rainbow", false),
		tts_workflow_enabled = self:GetSetting("TTS_Workflow_Enabled", false),
		auto_sync_global = self:GetSetting("Auto_Sync_Global", true),
		show_sender_name = pGet("Show_Sender_Name", true),
	}
	if botData and botData.config then
		configData.combat_weapon = botData.config.combat_weapon or configData.combat_weapon
		configData.melee_weapon = botData.config.melee_weapon or configData.melee_weapon
		configData.idle_weapon = botData.config.idle_weapon or configData.idle_weapon
		configData.stealth_mode = botData.config.stealth_mode or false
		configData.defender_mode = botData.config.defender_mode or false
		configData.medic_mode = botData.config.medic_mode or false
		configData.pacifist_mode = botData.config.pacifist_mode or false
		configData.aggressive_mode = botData.config.aggressive_mode or false
	end
	-- Не отправляем секреты на клиент
	configData.llm_api_key = nil
	configData.tts_api_key = nil
	configData.yandex_folder_id = nil

	local json = util.TableToJSON(configData)
	if json and #json <= 65535 then
		net.Start("gmod.one/ai-companion/config-sync")
		net.WriteString(json)
		net.Send(ply)
	end
end
function Shared:SyncTTStatus(status)
	if not SERVER then return end
	net.Start("gmod.one/ai-companion/tts-global-status")
	net.WriteBool(status)
	net.Broadcast()
end
function Shared:SyncAutoSyncState(state)
	if not SERVER then return end
	net.Start("gmod.one/ai-companion/auto-sync-update")
	net.WriteBool(state)
	net.Broadcast()
end
function Shared:SendChatMessage(ply, text, color, sender, receiver, isPrivate)
	if not self.utils or not self.utils:IsValid(ply) then return end
	local cleanText = self:SanitizeString(text, 500)
	if cleanText == "" then return end
	local prefixColor = color or Color(255, 200, 0)
	local senderName = sender or "AI"
	local receiverName = receiver or ""
	local receiverSteamID = isPrivate and ply:SteamID64() or ""
	if self.utils then
	end
	if isPrivate then
		net.Start("gmod.one/ai-companion/private-chat")
		net.WriteString(cleanText)
		net.WriteColor(prefixColor)
		net.WriteString(senderName)
		net.WriteString(receiverName ~= "" and receiverName or self:GetLocalized("ai_prefix"))
		net.WriteString(receiverSteamID)
		net.Send(ply)
	else
		net.Start("gmod.one/ai-companion/chat-broadcast")
		net.WriteString(cleanText)
		net.WriteColor(prefixColor)
		net.WriteString(senderName)
		net.WriteString(receiverName)
		net.WriteString(receiverSteamID)
		net.Broadcast()
	end
end
function Shared:SendAudioURL(ply, url)
	if not self.utils or not self.utils:IsValid(ply) then return end
	if not url or url == "" then return end
	net.Start("gmod.one/ai-companion/play-audio")
	net.WriteString(url)
	net.Send(ply)
end
function Shared:SendOwnerSync(bot, owner)
	if not SERVER then return end
	if not self.utils or not self.utils:IsValid(bot) then return end
	if not self.utils or not self.utils:IsValid(owner) then return end
	net.Start("gmod.one/ai-companion/owner-sync")
	net.WriteEntity(bot)
	net.WriteEntity(owner)
	net.Broadcast()
end
function Shared:SendColorSync(bot, color)
	if not SERVER then return end
	if not self.utils or not self.utils:IsValid(bot) then return end
	net.Start("gmod.one/ai-companion/color-sync")
	net.WriteEntity(bot)
	net.WriteVector(color or Vector(1, 1, 1))
	net.Broadcast()
end
function Shared:SetupClientReceivers()
	if not CLIENT then return end
	local selfRef = self
	net.Receive("gmod.one/ai-companion/settings-sync-chunk", function()
		local totalChunks = net.ReadUInt(16)
		local chunkIndex = net.ReadUInt(16)
		local chunkData = net.ReadString()
		if not selfRef._chunkBuffer then
			selfRef._chunkBuffer = {}
		end
		selfRef._chunkBuffer[chunkIndex] = chunkData
		if table.Count(selfRef._chunkBuffer) == totalChunks then
			local fullJson = table.concat(selfRef._chunkBuffer)
			selfRef._chunkBuffer = nil
			local ok, tbl = pcall(util.JSONToTable, fullJson)
			if not ok then
				ErrorNoHaltWithStack("[AI Companion Shared] Chunk JSON error: " .. tostring(tbl) .. "\n")
			end
			if ok and tbl and type(tbl) == "table" then
				if selfRef:ValidateSettings(tbl) then
					if selfRef.state then
						for k, v in pairs(tbl) do
							selfRef.state:setSetting(k, v)
						end
						if tbl.tts_enabled ~= nil then
							selfRef.state:setState("TTS_Enabled", tbl.tts_enabled)
						end
						if tbl.llm_enabled ~= nil then
							selfRef.state:setState("LLM_Enabled", tbl.llm_enabled)
						end
					end
					local locator = AICompanion.GetLocator()
					if locator and locator:has("menu") then
						local menu = locator:get("menu")
						if menu.RefreshValues then
							menu:RefreshValues()
						end
					end
				end
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/global-setting-updated", function()
		local key = net.ReadString()
		local valueStr = net.ReadString()
		local value
		if valueStr == "true" then value = true
		elseif valueStr == "false" then value = false
		else
			local num = tonumber(valueStr)
			if num then value = num else value = valueStr end
		end
		if selfRef.state then
			selfRef.state:getRaw("Settings")[key] = value
			if key == "LLM_Enabled" or key == "TTS_Enabled" then
				local st = selfRef.state:getRaw("State")
				if st then st[key] = value end
			end
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("menu") then
			local menu = locator:get("menu")
			if menu.RefreshValues then
				menu:RefreshValues()
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/settings-sync", function()
		local jsonString = net.ReadString()
		if not jsonString or #jsonString == 0 or #jsonString > 65535 then return end
		local ok, tbl = pcall(util.JSONToTable, jsonString)
		if not ok then
			ErrorNoHaltWithStack("[AI Companion Shared] Settings JSON error: " .. tostring(tbl) .. "\n")
			return
		end
		if not tbl or type(tbl) ~= "table" then return end
		if selfRef:ValidateSettings(tbl) then
			if selfRef.state then
				for k, v in pairs(tbl) do
					selfRef.state:setSetting(k, v)
				end
				if tbl.tts_enabled ~= nil then
					selfRef.state:setState("TTS_Enabled", tbl.tts_enabled)
				end
				if tbl.llm_enabled ~= nil then
					selfRef.state:setState("LLM_Enabled", tbl.llm_enabled)
				end
			end
			local locator = AICompanion.GetLocator()
			if locator and locator:has("menu") then
				local menu = locator:get("menu")
				if menu.RefreshValues then
					menu:RefreshValues()
				end
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/config-sync", function()
		local jsonString = net.ReadString()
		if not jsonString or #jsonString == 0 or #jsonString > 65535 then return end
		local ok, configData = pcall(util.JSONToTable, jsonString)
		if not ok then
			ErrorNoHaltWithStack("[AI Companion Shared] Config JSON error: " .. tostring(configData) .. "\n")
			return
		end
		if not configData or type(configData) ~= "table" then return end
		if configData.version ~= 1 then return end

		-- Не принимаем секреты от клиента (только сервер может их менять)
		configData.llm_api_key = nil
		configData.tts_api_key = nil
		configData.yandex_folder_id = nil

		if selfRef.state then
			selfRef.state:setSetting("LLM_IP", configData.llm_ip)
			selfRef.state:setSetting("LLM_Port", configData.llm_port)
			selfRef.state:setSetting("LLM_Model", configData.llm_model)
			selfRef.state:setSetting("TTS_IP", configData.tts_ip)
			selfRef.state:setSetting("TTS_Port", configData.tts_port)
			selfRef.state:setState("TTS_Enabled", configData.tts_enabled)
			selfRef.state:setState("LLM_Enabled", configData.llm_enabled)
			selfRef.state:setSetting("Debug_Mode", configData.debug_mode)
			selfRef.state:setSetting("TTS_Workflow_Enabled", configData.tts_workflow_enabled)
			selfRef.state:setSetting("Auto_Sync_Global", configData.auto_sync_global)
			local steamID = LocalPlayer():SteamID64()
			selfRef.state:setPlayerSetting(steamID, "Companion_Nick", configData.companion_nick)
			selfRef.state:setPlayerSetting(steamID, "Model_Path", configData.model_path)
			selfRef.state:setPlayerSetting(steamID, "Combat_Weapon", configData.combat_weapon)
			selfRef.state:setPlayerSetting(steamID, "Melee_Weapon", configData.melee_weapon)
			selfRef.state:setPlayerSetting(steamID, "Idle_Weapon", configData.idle_weapon)
			selfRef.state:setPlayerSetting(steamID, "Stealth_Mode", configData.stealth_mode)
			selfRef.state:setPlayerSetting(steamID, "Defender_Mode", configData.defender_mode)
			selfRef.state:setPlayerSetting(steamID, "Medic_Mode", configData.medic_mode)
			selfRef.state:setPlayerSetting(steamID, "Pacifist_Mode", configData.pacifist_mode)
			selfRef.state:setPlayerSetting(steamID, "Aggressive_Mode", configData.aggressive_mode)
			selfRef.state:setPlayerSetting(steamID, "Prefix_Text", configData.prefix_text)
			selfRef.state:setPlayerSetting(steamID, "Prefix_Color_R", configData.prefix_r)
			selfRef.state:setPlayerSetting(steamID, "Prefix_Color_G", configData.prefix_g)
			selfRef.state:setPlayerSetting(steamID, "Prefix_Color_B", configData.prefix_b)
			selfRef.state:setPlayerSetting(steamID, "Prefix_Rainbow", configData.prefix_rainbow)
			selfRef.state:setPlayerSetting(steamID, "Show_Sender_Name", configData.show_sender_name)
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("menu") then
			local menu = locator:get("menu")
			if menu.RefreshValues then
				menu:RefreshValues()
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/tts-global-status", function()
		local status = net.ReadBool()
		if selfRef.state then
			local st = selfRef.state:getRaw("State")
			if st then st.TTS_Enabled = status end
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("menu") then
			local menu = locator:get("menu")
			if menu.RefreshValues then
				menu:RefreshValues()
			end
		end
		local ttsStateText = status
			and self:GetLocalized("mode_on")
			or self:GetLocalized("mode_off")
		chat.AddText(Color(100, 200, 255),
			"[AI] " .. self:GetLocalized("tts_status") .. ttsStateText
				.. " (" .. self:GetLocalized("tts_global_status") .. ")")
	end)
	net.Receive("gmod.one/ai-companion/auto-sync-update", function()
		local state = net.ReadBool()
		if selfRef.state then
			selfRef.state:setSetting("Auto_Sync_Global", state)
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("menu") then
			local menu = locator:get("menu")
			if menu.RefreshValues then
				menu:RefreshValues()
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/locale-sync", function()
		local lang = net.ReadString()
		if lang and AICompanion and AICompanion.GetLocale then
			local locale = AICompanion.GetLocale()
			if locale.SetLang then
				locale:SetLang(lang)
			end
			-- Сохраняем в персональные настройки клиента
			if selfRef.state then
				local ply = LocalPlayer()
				if IsValid(ply) then
					local steamID = ply:SteamID64()
					selfRef.state:setPlayerSetting(steamID, "Locale", lang)
				end
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/mode-sync", function()
		local stealth = net.ReadBool()
		local aggressive = net.ReadBool()
		local pacifist = net.ReadBool()
		local defender = net.ReadBool()
		local medic = net.ReadBool()
		if selfRef.state then
			selfRef.state:setSetting("Stealth_Mode", stealth)
			selfRef.state:setSetting("Aggressive_Mode", aggressive)
			selfRef.state:setSetting("Pacifist_Mode", pacifist)
			selfRef.state:setSetting("Defender_Mode", defender)
			selfRef.state:setSetting("Medic_Mode", medic)
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("menu") then
			local menu = locator:get("menu")
			if menu.RefreshValues then
				menu:RefreshValues()
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/owner-sync", function()
		local bot = net.ReadEntity()
		local owner = net.ReadEntity()
		if selfRef.utils and selfRef.utils:IsValid(bot) and selfRef.utils:IsValid(owner) then
			bot:SetNWEntity("AICompanionOwnerEnt", owner)
			bot:SetNWString("AICompanionOwner", owner:Nick())
		end
	end)
	net.Receive("gmod.one/ai-companion/color-sync", function()
		local bot = net.ReadEntity()
		local color = net.ReadVector()
		if selfRef.utils and selfRef.utils:IsValid(bot) then
			local okColor, errColor = pcall(function()
				if bot.SetWeaponColor then
					bot:SetWeaponColor(color)
				end
			end)
			if not okColor then
				ErrorNoHaltWithStack("[AI Companion Shared] SetWeaponColor error: " .. tostring(errColor) .. "\n")
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/chat-broadcast", function()
		local text = net.ReadString()
		local color = net.ReadColor()
		local sender = net.ReadString()
		local receiver = net.ReadString()
		
		local prefix
		if receiver and receiver ~= "" then
			prefix = "[" .. sender .. " -> " .. receiver .. "] "
		else
			prefix = "[" .. sender .. "] "
		end
		
		-- Префикс — кастомный цвет, текст — белый
		chat.AddText(color, prefix, Color(255, 255, 255), text)
	end)

	net.Receive("gmod.one/ai-companion/private-chat", function()
		local text = net.ReadString()
		local color = net.ReadColor()
		local sender = net.ReadString()
		local receiver = net.ReadString()
		
		local prefix = "[" .. sender .. " -> " .. (receiver or self:GetLocalized("ai_prefix")) .. " (личное)] "
		
		-- Префикс — кастомный цвет, текст — белый
		chat.AddText(color, prefix, Color(255, 255, 255), text)
	end)
	net.Receive("gmod.one/ai-companion/play-audio", function()
		local url = net.ReadString()
		if url and url ~= "" then
			surface.PlayURL(url, function() end)
		end
	end)
	net.Receive("gmod.one/ai-companion/player-settings-sync", function()
		local jsonString = net.ReadString()
		if not jsonString or #jsonString == 0 or #jsonString > 65535 then return end
		local ok, settings = pcall(util.JSONToTable, jsonString)
		if not ok then
			ErrorNoHaltWithStack("[AI Companion Shared] PlayerSettings JSON error: " .. tostring(settings) .. "\n")
			return
		end
		if not settings or type(settings) ~= "table" then return end
		if selfRef.state then
			local steamID = LocalPlayer():SteamID64()
			for key, value in pairs(settings) do
				selfRef.state:setPlayerSetting(steamID, key, value)
			end
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("menu") then
			local menu = locator:get("menu")
			if menu.RefreshValues then
				menu:RefreshValues()
			end
		end
	end)
	net.Receive("gmod.one/ai-companion/afk-sync", function()
		local enabled = net.ReadBool()
		if selfRef.state then
			selfRef.state:setSetting("AFK_Enabled", enabled)
			local raw = selfRef.state:getRaw("AFK") or {}
			raw.Enabled = enabled
			selfRef.state:setRaw("AFK", raw)
		end
		chat.AddText(Color(100, 200, 255), "[AI] AFK: " .. (enabled and "ВКЛЮЧЕН" or "ВЫКЛЮЧЕН"))
	end)
end
function Shared:SafeGiveWeapon(bot, weaponClass)
	if not self.utils or not self.utils:IsValid(bot) then return false end
	if not weaponClass or weaponClass == "" then return false end
	if bot:HasWeapon(weaponClass) then
		return true
	end
	local success, giveErr = pcall(function()
		bot:Give(weaponClass)
	end)
	if success then
		return true
	end
	ErrorNoHaltWithStack("[AI Companion Shared] Give weapon error: " .. tostring(giveErr) .. "\n")
	local weapon = ents.Create(weaponClass)
	if self.utils:IsValid(weapon) then
		weapon:SetOwner(bot)
		weapon:Spawn()
		local okGive, errGive = pcall(function()
			bot:Give(weaponClass)
		end)
		if not okGive then
			ErrorNoHaltWithStack("[AI Companion Shared] Give weapon (fallback) error: " .. tostring(errGive) .. "\n")
		end
		return true
	end
	return false
end
function Shared:SafeGiveAmmo(bot, weapon, amount)
	if not self.utils or not self.utils:IsValid(bot) then return false end
	if not self.utils:IsValid(weapon) then return false end
	local ammoType = weapon:GetPrimaryAmmoType()
	if ammoType and ammoType ~= -1 then
		bot:GiveAmmo(amount or 100, ammoType, true)
		return true
	end
	return false
end
function Shared:ApplyWeaponHotSwap(bot, botKey, wepClass, botmanager)
	if not self.utils or not self.utils:IsValid(bot) then return end
	if not wepClass or wepClass == "" then return end
	if not self:SafeGiveWeapon(bot, wepClass) then
	end
	local wep = bot:GetWeapon(wepClass)
	if self.utils:IsValid(wep) then
		self:SafeGiveAmmo(bot, wep, 100)
	end
	local botState = "idle"
	if botmanager then
		botState = botmanager:GetBotState(bot) or "idle"
	end
	local shouldSelect = false
	if botKey == "combat_weapon" and botState == "combat" then
		shouldSelect = true
	elseif botKey == "idle_weapon" and botState ~= "combat" then
		shouldSelect = true
	elseif botKey == "melee_weapon" and botState == "combat" then
		local active = bot:GetActiveWeapon()
		if not self.utils:IsValid(active) then
			shouldSelect = true
		end
	end
	if shouldSelect then
		timer.Simple(0.2, function()
			if self.utils:IsValid(bot) and bot:HasWeapon(wepClass) then
				local okSel, errSel = pcall(function() bot:SelectWeapon(wepClass) end)
				if not okSel then
					ErrorNoHaltWithStack("[AI Companion Shared] SelectWeapon error: " .. tostring(errSel) .. "\n")
				end
			end
		end)
	end
end
return Shared