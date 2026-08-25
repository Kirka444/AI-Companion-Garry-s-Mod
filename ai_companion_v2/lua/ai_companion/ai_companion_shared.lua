if AI_COMPANION_SHARED_LOADED then return end
AI_COMPANION_SHARED_LOADED = true
local AC = _G.AI_COMPANION
if SERVER then
    util.AddNetworkString("AI_Settings_Sync")
    util.AddNetworkString("AI_Settings_Request")
    util.AddNetworkString("AI_Mode_Sync")
    util.AddNetworkString("AICompanion_SetSetting")
    util.AddNetworkString("AI_Companion_Chat")
    util.AddNetworkString("AI_Companion_PlayAudio")
    util.AddNetworkString("AI_TTS_Global_Status")
    util.AddNetworkString("AI_Companion_Private_Chat")
    util.AddNetworkString("AI_AutoSync_Update")
    util.AddNetworkString("AI_Locale_Sync")
    util.AddNetworkString("AICompanion_ConfigSync")
    util.AddNetworkString("AICompanion_RequestConfig")
end
local RateLimiter = {
    limits = {},
}
function RateLimiter:Check(steamID, action, maxRequests, window)
    if not steamID or not action then return false end
    local key = steamID .. "_" .. action
    local now = CurTime()
    if not self.limits[key] then
        self.limits[key] = { count = 1, first = now }
        return true
    end
    local limit = self.limits[key]
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
local function IsValidIP(ip)
    if type(ip) ~= "string" then return false end
    if #ip > 45 then return false end
    return true
end
local function IsValidPort(port)
    if type(port) ~= "number" then return false end
    if port ~= math.floor(port) then return false end
    return port >= 1 and port <= 65535
end
local function SanitizeString(str, maxLen)
    if type(str) ~= "string" then return "" end
    if maxLen and #str > maxLen then
        str = string.sub(str, 1, maxLen)
    end
    str = string.gsub(str, "[<>\"'&;`]", "")
    str = string.gsub(str, "[\r\n]", " ")
    return str
end
local function ValidateSettingsTable(tbl)
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
        llm_timeout = "number",
        tts_timeout = "number",
        llm_mode = "string",
        tts_mode = "string",
        llm_provider = "string",
        llm_api_key = "string",
        llm_cloud_model = "string",
        llm_endpoint = "string",
        llm_temperature = "number",
        llm_max_tokens = "number",
        tts_provider = "string",
        tts_api_key = "string",
        tts_voice = "string",
        tts_language = "string",
        tts_endpoint = "string",
        tts_speed = "number",
        yandex_folder_id = "string",
        yandex_voice = "string",
        yandex_lang = "string",
        vk_voice = "string",
        vk_tempo = "number",
        auto_sync_global = "boolean",
        custom_prompt_enabled = "boolean",
        custom_prompt_text = "string",
        allow_custom_prompts = "boolean",
        tts_workflow_enabled = "boolean",
        tts_workflow = "table",      
        tts_workflow_filename = "string",
    }
    for key, value in pairs(tbl) do
        local expectedType = ALLOWED_KEYS[key]
        if not expectedType then
            continue
        end
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
        if expectedType == "string" then
            if #value > 500 then
                return false  
            end
            if string.find(value, "[<>\"'&;`]") then
                return false
            end
        end
        if expectedType == "number" then
            if value ~= value or value == math.huge or value == -math.huge then
                return false  
            end
        end
        if (key == "llm_port" or key == "comfyui_port") and not IsValidPort(value) then
            return false
        end
        if key == "prefix_text" and #value > 32 then
            return false
        end
        if key == "locale" and #value > 10 then
            return false
        end
    end
    return true
end
local function ValidateBotConfig(config)
    if type(config) ~= "table" then return false end
    local ALLOWED_CONFIG_KEYS = {
        companion_nick = "string",
        model_path = "string",
        combat_weapon = "string",
        melee_weapon = "string",
        idle_weapon = "string",
        stealth_mode = "boolean",
        defender_mode = "boolean",
        medic_mode = "boolean",
        pacifist_mode = "boolean",
        aggressive_mode = "boolean",
        show_sender_name = "boolean",
    }
    for key, value in pairs(config) do
        local expectedType = ALLOWED_CONFIG_KEYS[key]
        if not expectedType then return false end
        if type(value) ~= expectedType then return false end
        if key == "companion_nick" and #value > 32 then return false end
        if key == "model_path" and #value > 256 then return false end
        if not string.match(value, "%.mdl$") then return false end
    end
    return true
end
local function SafeReadString(maxLen, default)
    maxLen = maxLen or 500
    local str = net.ReadString()
    if not str then return default or "" end
    if #str > maxLen then
        str = string.sub(str, 1, maxLen)
    end
    return SanitizeString(str, maxLen)
end
local function SafeReadTable(maxSize)
    maxSize = maxSize or 65535  
    local jsonString = net.ReadString()
    if not jsonString or #jsonString == 0 then
        return nil, "Пустой JSON"
    end
    if #jsonString > maxSize then
        return nil, string.format("Слишком большой JSON: %d байт", #jsonString)
    end
    local ok, data = pcall(util.JSONToTable, jsonString)
    if not ok or not data then
        return nil, "Ошибка парсинга JSON"
    end
    return data, nil
end
local SETTINGS_FILE = "ai_companion_settings.txt"
if not AC.Config or not AC.Config.Weapons then
    AC.Config = AC.Config or {}
    AC.Config.Network = AC.Config.Network or {
        LLM = { IP = "127.0.0.1", Port = 1234, Model = "local-model", Timeout = 60 },
        TTS = { IP = "127.0.0.1", Port = 8188, Timeout = 120 }
    }
    AC.Config.Weapons = AC.Config.Weapons or {
        COMBAT = "weapon_smg1", 
        MELEE = "weapon_crowbar", 
        IDLE = "weapon_physgun"
    }
    AC.Config.COMPANION_NAME = AC.Config.COMPANION_NAME or "AI_Companion"
    AC.Config.DEFAULT_MODEL = AC.Config.DEFAULT_MODEL or "models/player/urban.mdl"
end
local DEFAULTS = {
    llm_ip = AC.Config.Network.LLM.IP or "127.0.0.1",
    llm_port = AC.Config.Network.LLM.Port or 1234,
    llm_model = AC.Config.Network.LLM.Model or "local-model",
    comfyui_ip = AC.Config.Network.TTS.IP or "127.0.0.1",
    comfyui_port = AC.Config.Network.TTS.Port or 8188,
    tts_enabled = false,
    llm_enabled = true,
    debug_mode = false,
    prefix_text = "[AI]",
    show_sender_name = true,
    locale = "ru",
    prefix_r = 255,
    prefix_g = 200,
    prefix_b = 0,
    prefix_rainbow = false,
    stealth_mode = false,
    defender_mode = false,
    medic_mode = false,
    pacifist_mode = false,
    aggressive_mode = false,
    companion_nick = AC.Config.COMPANION_NAME or "AI_Companion",
    model_path = AC.Config.DEFAULT_MODEL or "models/player/urban.mdl",
    combat_weapon = AC.Config.Weapons.COMBAT or "weapon_smg1",
    melee_weapon = AC.Config.Weapons.MELEE or "weapon_crowbar",
    idle_weapon = AC.Config.Weapons.IDLE or "weapon_physgun",
    llm_timeout = AC.Config.Network.LLM.Timeout or 60,
    tts_timeout = AC.Config.Network.TTS.Timeout or 120,
}
AI_SETTINGS = AI_SETTINGS or {}
function AI_LoadSettings()
    if file.Exists("ai_companion_settings/global.txt", "DATA") then
        local data = file.Read("ai_companion_settings/global.txt", "DATA")
        if data then
            local ok, tbl = pcall(util.JSONToTable, data)
            if ok and tbl and type(tbl) == "table" then
                if _G.AI_SOLO_MODE then
                    AI_SETTINGS = tbl
                    return AI_SETTINGS
                end
                if ValidateSettingsTable(tbl) then
                    AI_SETTINGS = tbl
                    return AI_SETTINGS
                else
                    print("[AI Shared]  Невалидные настройки в файле, используем дефолтные")
                end
            end
        end
    end
    AI_SETTINGS = table.Copy(DEFAULTS)
    return AI_SETTINGS
end
function AI_SaveSettings()
    if not AI_SETTINGS then return end
    local json = util.TableToJSON(AI_SETTINGS)
    if json then
        if not file.Exists("ai_companion_settings", "DATA") then
            file.CreateDir("ai_companion_settings")
        end
        file.Write("ai_companion_settings/global.txt", json)
    end
end
function AI_ApplySettings()
    if not AI_SETTINGS then return end
    if not ValidateSettingsTable(AI_SETTINGS) then
        print("[AI Shared] Невалидные настройки, используем дефолтные")
        AI_SETTINGS = table.Copy(DEFAULTS)
    end
    _G.AI_LLM_IP = AI_SETTINGS.llm_ip or "127.0.0.1"
    _G.AI_LLM_PORT = AI_SETTINGS.llm_port or 1234
    _G.AI_LLM_MODEL = AI_SETTINGS.llm_model or "local-model"
    _G.AI_COMFYUI_IP = AI_SETTINGS.comfyui_ip or "127.0.0.1"
    _G.AI_COMFYUI_PORT = AI_SETTINGS.comfyui_port or 8188
    _G.AI_Companion_TTS_Enabled = AI_SETTINGS.tts_enabled or false
    _G.AI_Companion_LLM_Enabled = AI_SETTINGS.llm_enabled ~= false
    if AC.Config then
        AC.Config.DEBUG_MODE = AI_SETTINGS.debug_mode or false
    end
    if _G.AI_COMPANION_DEF then
        local AINS = _G.AI_COMPANION_DEF
        if AINS.LLM then
            AINS.LLM.IP = _G.AI_LLM_IP
            AINS.LLM.Port = _G.AI_LLM_PORT
            AINS.LLM.Model = _G.AI_LLM_MODEL
        end
        if AINS.TTS then
            AINS.TTS.IP = _G.AI_COMFYUI_IP
            AINS.TTS.Port = _G.AI_COMFYUI_PORT
            AINS.TTS.Enabled = _G.AI_Companion_TTS_Enabled
        end
        if AINS.Appearance and AINS.Appearance.Prefix then
            AINS.Appearance.Prefix.Text = AI_SETTINGS.prefix_text or "[AI]"
            AINS.Appearance.Prefix.Rainbow = AI_SETTINGS.prefix_rainbow or false
            if AINS.Appearance.Prefix.Color then
                AINS.Appearance.Prefix.Color.R = AI_SETTINGS.prefix_r or 255
                AINS.Appearance.Prefix.Color.G = AI_SETTINGS.prefix_g or 200
                AINS.Appearance.Prefix.Color.B = AI_SETTINGS.prefix_b or 0
            end
        end
    end
end
function AI_SyncToClients()
    if not SERVER then return end
    if game.SinglePlayer() then return end
    if not AI_SETTINGS then return end
    local json = util.TableToJSON(AI_SETTINGS)
    if #json <= 65535 then
        net.Start("AI_Settings_Sync")
        net.WriteString(json)
        net.Broadcast()
    end
end
function AI_SyncModeToClients()
    if not SERVER then return end
    if game.SinglePlayer() then return end
    local bots = BotManager and BotManager:GetAllBots() or {}
    local stealth, aggressive, pacifist, defender, medic = false, false, false, false, false
    for _, bot in ipairs(bots) do
        if IsValid(bot) then
            local data = GetBotData(bot)
            if data and data.config then
                stealth = stealth or data.config.stealth_mode or false
                aggressive = aggressive or data.config.aggressive_mode or false
                pacifist = pacifist or data.config.pacifist_mode or false
                defender = defender or data.config.defender_mode or false
                medic = medic or data.config.medic_mode or false
            end
        end
    end
    net.Start("AI_Mode_Sync")
    net.WriteBool(stealth)
    net.WriteBool(aggressive)
    net.WriteBool(pacifist)
    net.WriteBool(defender)
    net.WriteBool(medic)
    net.Broadcast()
end
function AI_RequestSettings(ply)
    if not SERVER then return end
    if not AI_SETTINGS then AI_LoadSettings() end
    if not IsValid(ply) then return end
    local json = util.TableToJSON(AI_SETTINGS)
    if json and #json <= 65535 then
        net.Start("AI_Settings_Sync")
        net.WriteString(json)
        net.Send(ply)
    end
end
function SyncBotDataToNWVars(bot)
    if not IsValid(bot) then return end
    if not bot:IsBot() then return end
    local data = nil
    if BotManager and BotManager.GetData then
        data = BotManager:GetData(bot)
    end
    if not data then
        local botID = bot:EntIndex()
        data = AI_Companion.BotData and AI_Companion.BotData[botID]
    end
    if not data then return end
    local cache = data._nw_cache or {}
    local cfg = data.config or {}
    local modeKeys = {
        stealth_mode = "AI_StealthMode",
        defender_mode = "AI_DefenderMode",
        medic_mode = "AI_MedicMode",
        pacifist_mode = "AI_PacifistMode",
        aggressive_mode = "AI_AggressiveMode",
    }
    for key, nwKey in pairs(modeKeys) do
        local value = cfg[key] or false
        if cache[key] ~= value then
            bot:SetNWBool(nwKey, value)
            cache[key] = value
        end
    end
    if cache.state ~= data.state then
        bot:SetNWString("BotState", data.state or "idle")
        cache.state = data.state
    end
    if cache.task ~= data.task then
        bot:SetNWString("CurrentTask", data.task or "")
        cache.task = data.task
    end
    if IsValid(data.owner) then
        local ownerName = data.owner:Nick()
        if cache.owner_name ~= ownerName then
            bot:SetNWEntity("AICompanionOwnerEnt", data.owner)
            bot:SetNWString("AICompanionOwner", ownerName)
            cache.owner_name = ownerName
        end
        if not cache.is_ai_companion then
            bot:SetNWBool("IsAICompanion", true)
            cache.is_ai_companion = true
        end
    else
        if cache.is_ai_companion then
            bot:SetNWBool("IsAICompanion", false)
            cache.is_ai_companion = false
        end
    end
    data._nw_cache = cache
end
function SyncAllBots()
    if BotManager and BotManager.GetAllBots then
        local bots = BotManager:GetAllBots()
        for _, bot in ipairs(bots) do
            if IsValid(bot) then
                SyncBotDataToNWVars(bot)
            end
        end
    end
end
function NotifyBotDataChanged(bot)
    if IsValid(bot) then
        SyncBotDataToNWVars(bot)
        hook.Call("AICompanion_DataChanged", nil, bot)
    end
end
if SERVER then
    net.Receive("AI_Locale_Sync", function(len, ply)
        if not IsValid(ply) then return end
        local steamID = ply:SteamID64()
        if not RateLimiter:Check(steamID, "locale", 5, 60) then
            return
        end
        local lang = SafeReadString(10)
        if lang and _L and _L:SetLang(lang) then
            if SetPlayerSetting then
                SetPlayerSetting(ply, "locale", lang)
            end
            net.Start("AI_Locale_Sync")
            net.WriteString(lang)
            net.Send(ply)
        end
    end)
end
if CLIENT then
    net.Receive("AI_Locale_Sync", function()
        local lang = net.ReadString()
        if lang and _L then
            _L:SetLang(lang)
            if IsValid(_G.AICompanionMenuPanel) then
                _G.AICompanionMenuPanel:RefreshAllTabs()
            end
        end
    end)
end
if SERVER then
    net.Receive("AICompanion_SetSetting", function(len, ply)
        if not IsValid(ply) or ply:IsBot() then
            if AC.Config and AC.Config.DEBUG_MODE then
                print("[AI SERVER] Отклонён запрос от бота или невалидного игрока")
            end
            return
        end
        local steamID = ply:SteamID64()
        if not RateLimiter:Check(steamID, "set_setting", 15, 60) then
            if AC.Config and AC.Config.DEBUG_MODE then
                print("[AI SERVER] Rate limit превышен для " .. ply:Nick().. "пожалуйста подождите")
            end
            return
        end
        local key = SafeReadString(64)
        if key == "" then
            if AC.Config and AC.Config.DEBUG_MODE then
                print("[AI SERVER] Пустой ключ от " .. ply:Nick())
            end
            return
        end
        local valueStr = SafeReadString(500)
		local ALLOWED_KEYS = {
			llm_ip = true, llm_port = true, llm_model = true,
			comfyui_ip = true, comfyui_port = true,
			llm_mode = true, tts_mode = true,
			llm_enabled = true, tts_enabled = true,
			tts_personal = true,
			stealth_mode = true, defender_mode = true,
			medic_mode = true, pacifist_mode = true,
			aggressive_mode = true,
			companion_nick = true, model_path = true,
			combat_weapon = true, melee_weapon = true,
			idle_weapon = true, show_sender_name = true,
			llm_provider = true, llm_api_key = true,
			llm_cloud_model = true, llm_endpoint = true,
			llm_temperature = true, llm_max_tokens = true,
			llm_timeout = true,
			tts_provider = true, tts_api_key = true,
			tts_voice = true, tts_language = true,
			tts_endpoint = true, tts_timeout = true,
			tts_speed = true,
			yandex_folder_id = true, yandex_voice = true,
			yandex_lang = true,
			vk_voice = true, vk_tempo = true,
			prefix_text = true, prefix_rainbow = true,
			prefix_r = true, prefix_g = true, prefix_b = true,
			custom_prompt_enabled = true,
			custom_prompt_text = true,
			allow_custom_prompts = true,
			tts_workflow_enabled = true,
			tts_workflow = true,
			tts_workflow_filename = true,
			debug_mode = true, locale = true,
			auto_sync_global = true,
		}
        if not ALLOWED_KEYS[key] then
            if AC.Config and AC.Config.DEBUG_MODE then
                print("[AI SERVER] Отклонён неизвестный ключ: " .. key)
            end
            return
        end
        local value
        if valueStr == "true" then
            value = true
        elseif valueStr == "false" then
            value = false
        else
            local num = tonumber(valueStr)
            if num and num == num and num ~= math.huge and num ~= -math.huge then
                if key == "llm_port" or key == "comfyui_port" then
                    if not IsValidPort(num) then
                        if AC.Config and AC.Config.DEBUG_MODE then
                            print("[AI SERVER] Невалидный порт от " .. ply:Nick())
                        end
                        return
                    end
                end
                value = num
            else
                value = valueStr
            end
        end
        local GLOBAL_KEYS = {
            llm_ip = true, llm_port = true, llm_model = true,
            comfyui_ip = true, comfyui_port = true,
            debug_mode = true,
        }
        if GLOBAL_KEYS[key] and not ply:IsAdmin() then
            if AC.Config and AC.Config.DEBUG_MODE then
                print("[AI SERVER] Отклонён запрос от не-админа: " .. key)
            end
            return
        end
        if SetPlayerSetting then
            SetPlayerSetting(ply, key, value)
        end
    end)
    net.Receive("AICompanion_RequestConfig", function(len, ply)
        if not IsValid(ply) then return end
        local steamID = ply:SteamID64()
        if not RateLimiter:Check(steamID, "request_config", 5, 30) then
            return
        end
        local settings = nil
        if GetPlayerSettings then
            settings = GetPlayerSettings(ply)
        end
        if not settings then
            settings = AI_SETTINGS or {}
        end
        local bot = GetCompanion(ply)
        local botData = IsValid(bot) and GetBotData(bot) or nil
        local configData = {
            version = 1,
            companion_nick = settings.companion_nick or "AI_Companion",
            model_path = settings.model_path or "models/player/urban.mdl",
            combat_weapon = botData and botData.config.combat_weapon or settings.combat_weapon or "weapon_smg1",
            melee_weapon = botData and botData.config.melee_weapon or settings.melee_weapon or "weapon_crowbar",
            idle_weapon = botData and botData.config.idle_weapon or settings.idle_weapon or "weapon_physgun",
            stealth_mode = botData and botData.config.stealth_mode or settings.stealth_mode or false,
            defender_mode = botData and botData.config.defender_mode or settings.defender_mode or false,
            medic_mode = botData and botData.config.medic_mode or settings.medic_mode or false,
            pacifist_mode = botData and botData.config.pacifist_mode or settings.pacifist_mode or false,
            aggressive_mode = botData and botData.config.aggressive_mode or settings.aggressive_mode or false,
            debug_mode = AC.Config.DEBUG_MODE or false,
            tts_enabled = _G.AI_Companion_TTS_Enabled or false,
            llm_enabled = _G.AI_Companion_LLM_Enabled or true,
            llm_ip = _G.AI_LLM_IP or "localhost",
            llm_port = _G.AI_LLM_PORT or 1234,
            llm_model = _G.AI_LLM_MODEL or "local-model",
            tts_ip = _G.AI_COMFYUI_IP or "localhost",
            tts_port = _G.AI_COMFYUI_PORT or 8188,
            prefix_text = settings.prefix_text or "[AI]",
            prefix_r = settings.prefix_r or 255,
            prefix_g = settings.prefix_g or 200,
            prefix_b = settings.prefix_b or 0,
            prefix_rainbow = settings.prefix_rainbow or false,
        }
        if not ValidateBotConfig(configData) then
            if AC.Config and AC.Config.DEBUG_MODE then
                print("[AI SERVER] Ошибка валидации конфига для " .. ply:Nick())
            end
            return
        end
        local json = util.TableToJSON(configData)
        if json and #json <= 65535 then
            net.Start("AICompanion_ConfigSync")
            net.WriteString(json)
            net.Send(ply)
        end
    end)
end
if CLIENT then
	net.Receive("AI_Settings_Sync", function()
		if game.SinglePlayer() then return end
		local jsonString = net.ReadString()
		if not jsonString or #jsonString == 0 or #jsonString > 65535 then
			if AI_Utils and AI_Utils.LogWarn then
				AI_Utils.LogWarn("Client", "Невалидный JSON настроек")
			end
			return
		end
		local ok, tbl = pcall(util.JSONToTable, jsonString)
		if not ok or not tbl or type(tbl) ~= "table" then
			if AI_Utils and AI_Utils.LogWarn then
				AI_Utils.LogWarn("Client", "Ошибка парсинга настроек")
			end
			return
		end
		if ValidateSettingsTable(tbl) then
			AI_SETTINGS = tbl
			AI_ApplySettings()
			if AC and AC.Settings then
				for k, v in pairs(tbl) do
					AC.Settings[k] = v
				end
			end
			if IsValid(_G.AICompanionMenuPanel) then
				_G.AICompanionMenuPanel:RefreshValues()
			end
		else
			if AI_Utils and AI_Utils.LogWarn then
				AI_Utils.LogWarn("Client", "Невалидные настройки от сервера")
			end
		end
	end)
    net.Receive("AICompanion_ConfigSync", function()
        local jsonString = net.ReadString()
        if not jsonString or #jsonString == 0 or #jsonString > 65535 then
            if AI_Utils and AI_Utils.LogWarn then
                AI_Utils.LogWarn("Client", "Невалидный JSON конфига")
            end
            return
        end
        local ok, configData = pcall(util.JSONToTable, jsonString)
        if not ok or not configData or type(configData) ~= "table" then
            if AI_Utils and AI_Utils.LogWarn then
                AI_Utils.LogWarn("Client", "Ошибка парсинга конфига")
            end
            return
        end
        if configData.version ~= 1 then
            if AI_Utils and AI_Utils.LogWarn then
                AI_Utils.LogWarn("Client", "Неизвестная версия протокола: %d", configData.version or 0)
            end
            return
        end
        if not ValidateBotConfig(configData) then
            if AI_Utils and AI_Utils.LogWarn then
                AI_Utils.LogWarn("Client", "Невалидный конфиг от сервера")
            end
            return
        end
        if not IsValid(_G.AICompanionMenuPanel) then return end
        _G.CurrentCompanionModel = configData.model_path
        _G.AI_COMPANION_NICK = configData.companion_nick
        _G.AI_Companion_TTS_Enabled = configData.tts_enabled
        _G.AI_Companion_LLM_Enabled = configData.llm_enabled
        _G.AI_LLM_IP = configData.llm_ip
        _G.AI_LLM_PORT = configData.llm_port
        _G.AI_LLM_MODEL = configData.llm_model
        _G.AI_COMFYUI_IP = configData.tts_ip
        _G.AI_COMFYUI_PORT = configData.tts_port
        _G.AI_Companion_PrefixText = configData.prefix_text
        _G.AI_Companion_PrefixColorR = configData.prefix_r
        _G.AI_Companion_PrefixColorG = configData.prefix_g
        _G.AI_Companion_PrefixColorB = configData.prefix_b
        _G.AI_Companion_PrefixRainbow = configData.prefix_rainbow
        if AC.Config then
            AC.Config.DEBUG_MODE = configData.debug_mode
        end
        if AI_SETTINGS then
            AI_SETTINGS.companion_nick = configData.companion_nick
            AI_SETTINGS.model_path = configData.model_path
            AI_SETTINGS.combat_weapon = configData.combat_weapon
            AI_SETTINGS.melee_weapon = configData.melee_weapon
            AI_SETTINGS.idle_weapon = configData.idle_weapon
            AI_SETTINGS.stealth_mode = configData.stealth_mode
            AI_SETTINGS.defender_mode = configData.defender_mode
            AI_SETTINGS.medic_mode = configData.medic_mode
            AI_SETTINGS.pacifist_mode = configData.pacifist_mode
            AI_SETTINGS.aggressive_mode = configData.aggressive_mode
            AI_SETTINGS.llm_ip = configData.llm_ip
            AI_SETTINGS.llm_port = configData.llm_port
            AI_SETTINGS.llm_model = configData.llm_model
            AI_SETTINGS.comfyui_ip = configData.tts_ip
            AI_SETTINGS.comfyui_port = configData.tts_port
            AI_SETTINGS.tts_enabled = configData.tts_enabled
            AI_SETTINGS.llm_enabled = configData.llm_enabled
            AI_SETTINGS.debug_mode = configData.debug_mode
            AI_SETTINGS.prefix_text = configData.prefix_text
            AI_SETTINGS.prefix_r = configData.prefix_r
            AI_SETTINGS.prefix_g = configData.prefix_g
            AI_SETTINGS.prefix_b = configData.prefix_b
            AI_SETTINGS.prefix_rainbow = configData.prefix_rainbow
        end
        _G.AICompanionMenuPanel:RefreshValues()
    end)
    net.Receive("AI_Mode_Sync", function()
        if game.SinglePlayer() then return end
        AI_Companion_StealthMode = net.ReadBool()
        AI_Companion_AggressiveMode = net.ReadBool()
        AI_Companion_PacifistMode = net.ReadBool()
        AI_Companion_DefenderMode = net.ReadBool()
        AI_Companion_MedicMode = net.ReadBool()
        if IsValid(_G.AICompanionMenuPanel) then
            _G.AICompanionMenuPanel:RefreshValues()
        end
    end)
    net.Receive("AI_AutoSync_Update", function()
        local state = net.ReadBool()
        if AI_SETTINGS then
            AI_SETTINGS.auto_sync_global = state
        end
        if IsValid(_G.AICompanionMenuPanel) then
            if _G.AICompanionMenuPanel.RefreshValues then
                _G.AICompanionMenuPanel:RefreshValues()
            end
        end
    end)
    net.Receive("AI_TTS_Global_Status", function()
        local status = net.ReadBool()
        _G.AI_Companion_TTS_Enabled = status
        if IsValid(_G.AICompanionMenuPanel) then
            _G.AICompanionMenuPanel:RefreshValues()
        end
        chat.AddText(Color(100, 200, 255), "[AI] TTS " .. (status and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН") .. " глобально")
    end)
end
AI_LoadSettings()
AI_ApplySettings()
timer.Simple(1, function()
    if AI_SETTINGS and AI_SETTINGS.tts_enabled ~= nil then
        _G.AI_Companion_TTS_Enabled = AI_SETTINGS.tts_enabled
        _G.AI_Companion_TTS_Global = AI_SETTINGS.tts_enabled
    end
end)
_G.SyncBotDataToNWVars = SyncBotDataToNWVars
_G.SyncAllBots = SyncAllBots
_G.NotifyBotDataChanged = NotifyBotDataChanged
AI_DebugPrint("[AI Shared] v2 загружен (безопасная версия с валидацией)")