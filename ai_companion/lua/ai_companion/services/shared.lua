
local Shared = {}

function Shared:new(utils, config, state)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        _initialized = false,
        _rateLimiter = {},
		_lastSyncedJSON = {},
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
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
        self.utils.LogInfo("Shared", "Сетевой сервис инициализирован")
    end
end

function Shared:RegisterNetworkMessages()
    local messages = {
        "AI_Settings_Sync",
        "AI_Settings_Sync_Chunk",
        "AI_Companion_Chat",
        "AI_Companion_Private_Chat",
        "AI_Companion_PlayAudio",
        "AI_TTS_Global_Status",
        "AI_AutoSync_Update",
        "AI_Locale_Sync",
        "AICompanion_ConfigSync",
        "AICompanion_RequestConfig",
        "AICompanion_SetSetting",
        "AI_Mode_Sync",
        "AICompanion_OwnerSync",
        "AICompanion_ColorSync",
        "AI_Settings_Request",
        "AICompanion_SetGlobalSetting",
        "AI_GlobalSettingUpdated",
        "AI_PlayerSettings_Sync",
        "AI_RequestPlayerSettings",

		 "AI_Memory_Sync",
		 "AI_Memory_Add",
		 "AI_Memory_Clear",
		 "AI_Memory_Request",
    }
    for _, name in ipairs(messages) do
        if util and util.AddNetworkString then
            util.AddNetworkString(name)
        end
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
    local key = steamID .. "_" .. action
    local now = CurTime()

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
    }

    for key, value in pairs(tbl) do
        local expectedType = ALLOWED_KEYS[key]
        if not expectedType then return false end
        if type(value) ~= expectedType then
            if expectedType == "number" and type(value) == "string" then
                local num = tonumber(value)
                if num then tbl[key] = num value = num else return false end
            else
                return false
            end
        end
        if expectedType == "string" and #value > 500 then return false end
        if expectedType == "number" then
            if value ~= value or value == math.huge or value == -math.huge then
                return false
            end
        end
        if (key == "llm_port" or key == "comfyui_port") then
            local port = tonumber(value)
            if not port or port < 1 or port > 65535 then return false end
        end
    end

    return true
end

function Shared:SetupNetReceivers()
    if not SERVER then return end

	net.Receive("AICompanion_SetSetting", function(len, ply)
		if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
		local steamID = ply:SteamID64()
		if not self:CheckRateLimit(steamID, "set_setting", 15, 60) then return end

		local key = self:SanitizeString(net.ReadString(), 64)
		if key == "" then return end
		local valueStr = self:SanitizeString(net.ReadString(), 500)

		self.utils:LogDebug("[Shared] 🔥 Получена настройка: key=" .. key .. ", value=" .. valueStr)

		if self.state and self.state:IsGlobalKey(key) then
			self.utils:LogDebug("[Shared] ⚠️ Ключ " .. key .. " глобальный, игнорируем в SetSetting")
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
			self.utils:LogDebug("[Shared] 💾 Сохраняем в PlayerSettings: " .. key .. " = " .. tostring(value) .. " для " .. steamID)
			self.state:setPlayerSetting(steamID, key, value)

		end

		local keyLower = string.lower(key)
		local locator = _G.AI_GetLocator()

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
						self.utils:LogDebug("[Shared] ✅ Настройка " .. key .. " применена к боту " .. bot:Nick())
					end
				end
			end
		end
	end)

    net.Receive("AICompanion_SetGlobalSetting", function(len, ply)
        if not self.utils or not self.utils:IsValid(ply) then return end
        if not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администратор может менять глобальные настройки.")
            return
        end

        local key = self:SanitizeString(net.ReadString(), 64)
        if key == "" then return end
        local valueStr = self:SanitizeString(net.ReadString(), 500)

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

            net.Start("AI_GlobalSettingUpdated")
            net.WriteString(key)
            net.WriteString(tostring(value))
            net.Broadcast()
        end
    end)

    net.Receive("AI_Settings_Request", function(len, ply)
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

    net.Receive("AI_RequestPlayerSettings", function(len, ply)
        if not self.utils or not self.utils:IsValid(ply) then return end
        if not self:CheckRateLimit(ply:SteamID64(), "request_player_settings", 1, 5) then return end
        self:SyncPlayerSettingsToClient(ply)
    end)

    net.Receive("AICompanion_RequestConfig", function(len, ply)
        if not self.utils or not self.utils:IsValid(ply) then return end
        if not self:CheckRateLimit(ply:SteamID64(), "request_config", 5, 30) then return end
        self:SyncConfigToClient(ply)
    end)

    net.Receive("AI_Locale_Sync", function(len, ply)
        if not self.utils or not self.utils:IsValid(ply) then return end
        local lang = self:SanitizeString(net.ReadString(), 10)
        if lang then
            local locale = _G.AI_GetLocale()
            if locale and locale.SetLang then
                locale:SetLang(lang)
                if self.state then
                    self.state:setSetting("Locale", lang)
                end
                net.Start("AI_Locale_Sync")
                net.WriteString(lang)
                net.Send(ply)
            end
        end
    end)

	hook.Add("PlayerInitialSpawn", "AI_SetAdminStatus", function(ply)
		if not SERVER then return end
		timer.Simple(0.5, function()
			if IsValid(ply) then
				ply:SetNWBool("AI_IsAdmin", ply:IsAdmin())

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

    hook.Add("PlayerChangedTeam", "AI_UpdateAdminStatus", function(ply)
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
            "TTS_IP", "TTS_Port", "TTS_Mode",
            "Prefix_Text", "Locale",
            "Companion_Nick", "Model_Path",
            "Debug_Mode",
        }

        for _, key in ipairs(importantKeys) do
            if global[key] ~= nil then
                settings[key] = global[key]
            end
            if playerSettings[key] ~= nil then
                settings[key] = playerSettings[key]
            end
        end

        local state = self.state:getRaw("State") or {}
        settings.tts_enabled = state.TTS_Enabled or false
        settings.llm_enabled = state.LLM_Enabled or true
    end

    local json = util.TableToJSON(settings)
    if json and #json <= 8000 then
        net.Start("AI_Settings_Sync")
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

        net.Start("AI_Settings_Sync_Chunk")
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

    if self._lastSyncedJSON[steamID] == json then return end
    self._lastSyncedJSON[steamID] = json

    net.Start("AI_PlayerSettings_Sync")
    net.WriteString(json)
    net.Send(ply)
end

function Shared:SyncConfigToClient(ply)
    if not SERVER or not self.utils or not self.utils:IsValid(ply) then return end
    if ply:IsBot() then return end

    local bot = nil
    local botData = nil
    local locator = _G.AI_GetLocator()
    if locator and locator:has("botmanager") then
        bot = locator:get("botmanager"):GetBotByOwner(ply)
        if bot then
            botData = locator:get("botmanager"):GetData(bot)
        end
    end

    local configData = {
        version = 1,
        companion_nick = self:GetSetting("Companion_Nick", "AI_Companion"),
        model_path = self:GetSetting("Model_Path", "models/player/urban.mdl"),
        combat_weapon = self:GetSetting("Combat_Weapon", "weapon_smg1"),
        melee_weapon = self:GetSetting("Melee_Weapon", "weapon_crowbar"),
        idle_weapon = self:GetSetting("Idle_Weapon", "weapon_physgun"),
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
        prefix_text = self:GetSetting("Prefix_Text", "[AI]"),
        prefix_r = self:GetSetting("Prefix_Color_R", 255),
        prefix_g = self:GetSetting("Prefix_Color_G", 200),
        prefix_b = self:GetSetting("Prefix_Color_B", 0),
        prefix_rainbow = self:GetSetting("Prefix_Rainbow", false),
        tts_workflow_enabled = self:GetSetting("TTS_Workflow_Enabled", false),
        auto_sync_global = self:GetSetting("Auto_Sync_Global", true),
        show_sender_name = self:GetSetting("Show_Sender_Name", true),
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

    local json = util.TableToJSON(configData)
    if json and #json <= 65535 then
        net.Start("AICompanion_ConfigSync")
        net.WriteString(json)
        net.Send(ply)
    end
end

function Shared:SyncTTStatus(status)
    if not SERVER then return end
    net.Start("AI_TTS_Global_Status")
    net.WriteBool(status)
    net.Broadcast()
end

function Shared:SyncAutoSyncState(state)
    if not SERVER then return end
    net.Start("AI_AutoSync_Update")
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

    self.utils:LogDebug("[Shared] SendChatMessage: " .. senderName .. " -> " .. (receiverName ~= "" and receiverName or "все") .. ": " .. cleanText)

    if isPrivate then
        net.Start("AI_Companion_Private_Chat")
        net.WriteString(cleanText)
        net.WriteColor(prefixColor)
        net.WriteString(senderName)
        net.WriteString(receiverName ~= "" and receiverName or "Игрок")
        net.WriteString(receiverSteamID)
        net.Send(ply)
    else
        net.Start("AI_Companion_Chat")
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
    net.Start("AI_Companion_PlayAudio")
    net.WriteString(url)
    net.Send(ply)
end

function Shared:SendOwnerSync(bot, owner)
    if not SERVER then return end
    if not self.utils or not self.utils:IsValid(bot) then return end
    if not self.utils or not self.utils:IsValid(owner) then return end
    net.Start("AICompanion_OwnerSync")
    net.WriteEntity(bot)
    net.WriteEntity(owner)
    net.Broadcast()
end

function Shared:SendColorSync(bot, color)
    if not SERVER then return end
    if not self.utils or not self.utils:IsValid(bot) then return end
    net.Start("AICompanion_ColorSync")
    net.WriteEntity(bot)
    net.WriteVector(color or Vector(1, 1, 1))
    net.Broadcast()
end

function Shared:SetupClientReceivers()
    if not CLIENT then return end

    local selfRef = self

    net.Receive("AI_Settings_Sync_Chunk", function()
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
                    local locator = _G.AI_GetLocator()
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

    net.Receive("AI_GlobalSettingUpdated", function()
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
        end
        local locator = _G.AI_GetLocator()
        if locator and locator:has("menu") then
            local menu = locator:get("menu")
            if menu.RefreshValues then
                menu:RefreshValues()
            end
        end
    end)

    net.Receive("AI_Settings_Sync", function()
        local jsonString = net.ReadString()
        if not jsonString or #jsonString == 0 or #jsonString > 65535 then return end
        local ok, tbl = pcall(util.JSONToTable, jsonString)
        if not ok or not tbl or type(tbl) ~= "table" then return end
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
            local locator = _G.AI_GetLocator()
            if locator and locator:has("menu") then
                local menu = locator:get("menu")
                if menu.RefreshValues then
                    menu:RefreshValues()
                end
            end
        end
    end)

    net.Receive("AICompanion_ConfigSync", function()
        local jsonString = net.ReadString()
        if not jsonString or #jsonString == 0 or #jsonString > 65535 then return end
        local ok, configData = pcall(util.JSONToTable, jsonString)
        if not ok or not configData or type(configData) ~= "table" then return end
        if configData.version ~= 1 then return end

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

        local locator = _G.AI_GetLocator()
        if locator and locator:has("menu") then
            local menu = locator:get("menu")
            if menu.RefreshValues then
                menu:RefreshValues()
            end
        end
    end)

    net.Receive("AI_TTS_Global_Status", function()
        local status = net.ReadBool()
        if selfRef.state then
            selfRef.state:setState("TTS_Enabled", status)
        end
        local locator = _G.AI_GetLocator()
        if locator and locator:has("menu") then
            local menu = locator:get("menu")
            if menu.RefreshValues then
                menu:RefreshValues()
            end
        end
    end)

    net.Receive("AI_AutoSync_Update", function()
        local state = net.ReadBool()
        if selfRef.state then
            selfRef.state:setSetting("Auto_Sync_Global", state)
        end
        local locator = _G.AI_GetLocator()
        if locator and locator:has("menu") then
            local menu = locator:get("menu")
            if menu.RefreshValues then
                menu:RefreshValues()
            end
        end
    end)

    net.Receive("AI_Locale_Sync", function()
        local lang = net.ReadString()
        if lang and _G.AI_GetLocale then
            local locale = _G.AI_GetLocale()
            if locale.SetLang then
                locale:SetLang(lang)
            end
            if selfRef.state then
                selfRef.state:setSetting("Locale", lang)
            end
        end
    end)

    net.Receive("AI_Mode_Sync", function()
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

        local locator = _G.AI_GetLocator()
        if locator and locator:has("menu") then
            local menu = locator:get("menu")
            if menu.RefreshValues then
                menu:RefreshValues()
            end
        end
    end)

    net.Receive("AICompanion_OwnerSync", function()
        local bot = net.ReadEntity()
        local owner = net.ReadEntity()
        if selfRef.utils and selfRef.utils:IsValid(bot) and selfRef.utils:IsValid(owner) then
            bot:SetNWEntity("AICompanionOwnerEnt", owner)
            bot:SetNWString("AICompanionOwner", owner:Nick())
        end
    end)

    net.Receive("AICompanion_ColorSync", function()
        local bot = net.ReadEntity()
        local color = net.ReadVector()
        if selfRef.utils and selfRef.utils:IsValid(bot) then
            pcall(function()
                if bot.SetWeaponColor then
                    bot:SetWeaponColor(color)
                end
            end)
        end
    end)
end

function Shared:SafeGiveWeapon(bot, weaponClass)
    if not self.utils or not self.utils:IsValid(bot) then return false end
    if not weaponClass or weaponClass == "" then return false end

    if bot:HasWeapon(weaponClass) then
        return true
    end

    local success = pcall(function()
        bot:Give(weaponClass)
    end)

    if success then
        return true
    end

    local weapon = ents.Create(weaponClass)
    if self.utils:IsValid(weapon) then
        weapon:SetOwner(bot)
        weapon:Spawn()
        pcall(function()
            bot:Give(weaponClass)
        end)
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

return Shared
