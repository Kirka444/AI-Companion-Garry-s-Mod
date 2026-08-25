if AI_COMPANION_SETTINGS_LOADED then return end
AI_COMPANION_SETTINGS_LOADED = true
local AC = _G.AI_COMPANION
local DEFAULT_SETTINGS = {
    llm_ip = "127.0.0.1",
    llm_port = 1234,
    llm_model = "local-model",
    comfyui_ip = "127.0.0.1",
    comfyui_port = 8188,
    tts_enabled = false,
    llm_enabled = true,
    debug_mode = false,
    stealth_mode = true,
    defender_mode = true,
    medic_mode = true,
    pacifist_mode = false,
    aggressive_mode = false,
    prefix_text = "[AI]",
    prefix_r = 150,
    prefix_g = 150,
    prefix_b = 150,
    prefix_rainbow = false,
    model_path = "models/player/urban.mdl",
    companion_nick = "AI_Companion",
    combat_weapon = "weapon_smg1",
    melee_weapon = "weapon_crowbar",
    idle_weapon = "weapon_physgun",
    show_sender_name = true,
    llm_mode = "local",
    tts_mode = "local",
    tts_personal = true,
    llm_provider = "openai",
    llm_api_key = "",
    llm_cloud_model = "",
    llm_endpoint = "",
    llm_temperature = 0.7,
    llm_max_tokens = 100,
    llm_timeout = 60,
    tts_timeout = 120,
    tts_provider = "elevenlabs",
    tts_api_key = "",
    tts_voice = "",
    tts_language = "",
    tts_endpoint = "",
    tts_speed = 1.0,
    auto_sync_global = true,
    custom_prompt_enabled = false,
    custom_prompt_text = "",
    allow_custom_prompts = true,
    tts_workflow_enabled = false,
    tts_workflow = nil,
    tts_workflow_filename = "",
}
local SETTINGS_DIR = "ai_companion_settings/"
local PLAYERS_DIR = SETTINGS_DIR .. "players/"
local TEMPLATES_DIR = SETTINGS_DIR .. "templates/"
local GLOBAL_FILE = SETTINGS_DIR .. "global.txt"
local MIGRATION_DONE_FILE = SETTINGS_DIR .. "migration_done.txt"
local BACKUP_DIR = SETTINGS_DIR .. "backups/"
PlayerSettings = PlayerSettings or {}
local function CreateDirectories()
    if not file.Exists(SETTINGS_DIR, "DATA") then
        file.CreateDir(SETTINGS_DIR)
    end
    if not file.Exists(PLAYERS_DIR, "DATA") then
        file.CreateDir(PLAYERS_DIR)
    end
    if not file.Exists(TEMPLATES_DIR, "DATA") then
        file.CreateDir(TEMPLATES_DIR)
    end
    if not file.Exists(BACKUP_DIR, "DATA") then
        file.CreateDir(BACKUP_DIR)
    end
end
CreateDirectories()
local function SyncAllSettingsSources(ply, settings)
    if not settings then return end
    local steamID = ply and IsValid(ply) and ply:SteamID64() or nil
    if AI_SETTINGS then
        for k, v in pairs(settings) do
            AI_SETTINGS[k] = v
        end
    end
    local registry = debug.getregistry()
    local storage = registry["__AI_COMPANION_STORAGE_v2"]
    if storage and storage.Settings then
        for k, v in pairs(settings) do
            storage.Settings[k] = v
        end
    end
    if settings.llm_ip then _G.AI_LLM_IP = settings.llm_ip end
    if settings.llm_port then _G.AI_LLM_PORT = settings.llm_port end
    if settings.llm_model then _G.AI_LLM_MODEL = settings.llm_model end
    if settings.comfyui_ip then _G.AI_COMFYUI_IP = settings.comfyui_ip end
    if settings.comfyui_port then _G.AI_COMFYUI_PORT = settings.comfyui_port end
    if settings.tts_enabled ~= nil then _G.AI_Companion_TTS_Enabled = settings.tts_enabled end
    if settings.llm_enabled ~= nil then _G.AI_Companion_LLM_Enabled = settings.llm_enabled end
    if settings.prefix_text then _G.AI_Companion_PrefixText = settings.prefix_text end
    if settings.prefix_rainbow ~= nil then _G.AI_Companion_PrefixRainbow = settings.prefix_rainbow end
    if settings.prefix_r then _G.AI_Companion_PrefixColorR = settings.prefix_r end
    if settings.prefix_g then _G.AI_Companion_PrefixColorG = settings.prefix_g end
    if settings.prefix_b then _G.AI_Companion_PrefixColorB = settings.prefix_b end
    if AI_CONFIG and AI_CONFIG.Network then
        if settings.llm_ip then AI_CONFIG.Network.LLM.IP = settings.llm_ip end
        if settings.llm_port then AI_CONFIG.Network.LLM.Port = settings.llm_port end
        if settings.llm_model then AI_CONFIG.Network.LLM.Model = settings.llm_model end
        if settings.comfyui_ip then AI_CONFIG.Network.TTS.IP = settings.comfyui_ip end
        if settings.comfyui_port then AI_CONFIG.Network.TTS.Port = settings.comfyui_port end
        if settings.llm_timeout then AI_CONFIG.Network.LLM.Timeout = settings.llm_timeout end
        if settings.tts_timeout then AI_CONFIG.Network.TTS.Timeout = settings.tts_timeout end
    end
    if AC and AC.Settings then
        for k, v in pairs(settings) do
            AC.Settings[k] = v
        end
    end
    if AI_Utils and AI_Utils.LogDebug then
        AI_Utils.LogDebug("Settings", "Все настройки синхронизированы для %s", (IsValid(ply) and ply:Nick() or "Unknown"))
    end
end
function LoadOldSettings()
    local settings = table.Copy(DEFAULT_SETTINGS)
    local loaded = false
    if file.Exists("ai_companion_settings.txt", "DATA") then
        local data = file.Read("ai_companion_settings.txt", "DATA")
        if data then
            local ok, tbl = pcall(util.JSONToTable, data)
            if ok and tbl then
                for k, v in pairs(tbl) do
                    settings[k] = v
                end
                loaded = true
            end
        end
    end
    if file.Exists("ai_companion_weapons.txt", "DATA") then
        local data = file.Read("ai_companion_weapons.txt", "DATA")
        if data then
            local ok, tbl = pcall(util.JSONToTable, data)
            if ok and tbl then
                if tbl.combat_weapon then settings.combat_weapon = tbl.combat_weapon end
                if tbl.melee_weapon then settings.melee_weapon = tbl.melee_weapon end
                if tbl.idle_weapon then settings.idle_weapon = tbl.idle_weapon end
                loaded = true
            end
        end
    end
    if file.Exists("ai_companion_player_settings.txt", "DATA") then
        local data = file.Read("ai_companion_player_settings.txt", "DATA")
        if data then
            local ok, tbl = pcall(util.JSONToTable, data)
            if ok and tbl then
                for _, playerSettings in pairs(tbl) do
                    if type(playerSettings) == "table" then
                        for k, v in pairs(playerSettings) do
                            if settings[k] == nil then
                                settings[k] = v
                            end
                        end
                    end
                end
                loaded = true
            end
        end
    end
    return settings, loaded
end
function MigrateOldSettings()
    if file.Exists(MIGRATION_DONE_FILE, "DATA") then
        return true
    end
    local oldSettings, loaded = LoadOldSettings()
    if not loaded then
        file.Write(MIGRATION_DONE_FILE, "done")
        return false
    end
    local date = os.date("%Y-%m-%d_%H-%M-%S")
    local backupPath = BACKUP_DIR .. "old_settings_" .. date .. ".txt"
    local backupJson = util.TableToJSON(oldSettings)
    if backupJson then
        file.Write(backupPath, backupJson)
    end
    local globalJson = util.TableToJSON(oldSettings)
    if globalJson then
        file.Write(GLOBAL_FILE, globalJson)
    end
    local templatePath = TEMPLATES_DIR .. "default_" .. date .. ".txt"
    file.Write(templatePath, globalJson)
    for k, v in pairs(oldSettings) do
        DEFAULT_SETTINGS[k] = v
    end
    file.Write(MIGRATION_DONE_FILE, "done")
    return true
end
function GetPlayerSettingsPath(ply)
    if not IsValid(ply) then return nil end
    local steamID = ply:SteamID64()
    steamID = string.gsub(steamID, ":", "_")
    return PLAYERS_DIR .. steamID .. ".txt"
end
function LoadPlayerSettings(ply)
    if not IsValid(ply) then return end
    if ply:IsBot() then return end
    local steamID = ply:SteamID64()
    if PlayerSettings[steamID] then
        return PlayerSettings[steamID]
    end
    local settings = table.Copy(DEFAULT_SETTINGS)
    local playerPath = GetPlayerSettingsPath(ply)
    local hasPersonalSettings = false
    if file.Exists(playerPath, "DATA") then
        local data = file.Read(playerPath, "DATA")
        if data then
            local ok, tbl = pcall(util.JSONToTable, data)
            if ok and tbl then
                for k, v in pairs(tbl) do
                    settings[k] = v
                end
                hasPersonalSettings = true
                if AI_Utils and AI_Utils.LogDebug then
                    AI_Utils.LogDebug("Settings", "Загружены личные настройки для %s", ply:Nick())
                end
            end
        end
    end
    if not hasPersonalSettings then
        if file.Exists(GLOBAL_FILE, "DATA") then
            local data = file.Read(GLOBAL_FILE, "DATA")
            if data then
                local ok, tbl = pcall(util.JSONToTable, data)
                if ok and tbl then
                    for k, v in pairs(tbl) do
                        if settings[k] == nil then
                            settings[k] = v
                        end
                    end
                    if AI_Utils and AI_Utils.LogDebug then
                        AI_Utils.LogDebug("Settings", "Загружены глобальные настройки для %s (личных нет)", ply:Nick())
                    end
                end
            end
        end
    end
    PlayerSettings[steamID] = settings
    if settings.tts_enabled ~= nil then
        ply:SetNWBool("AI_TTS_Enabled", settings.tts_enabled)
        ply.AI_TTS_Enabled = settings.tts_enabled
    end
    ApplyPlayerSettings(ply, settings)
    _G.AI_Companion_TTS_Enabled = settings.tts_enabled or false
    _G.AI_Companion_LLM_Enabled = settings.llm_enabled ~= false
    SyncAllSettingsSources(ply, settings)
    return settings
end
function SavePlayerSettings(ply)
    if not IsValid(ply) then return end
    if ply:IsBot() then return end
    local steamID = ply:SteamID64()
    local settings = PlayerSettings[steamID]
    if not settings then
        settings = LoadPlayerSettings(ply)
        if not settings then return end
    end
    local path = GetPlayerSettingsPath(ply)
    local json = util.TableToJSON(settings)
    if json then
        file.Write(path, json)
        if AI_Utils and AI_Utils.LogDebug then
            AI_Utils.LogDebug("Settings", "Настройки сохранены для %s", ply:Nick())
        end
    end
end
function ApplyAllSettingsToBot(bot, settings, owner)
    if not IsValid(bot) or not settings then 
        print("[AI DEBUG] ApplyAllSettingsToBot: невалидный бот или настройки")
        return false 
    end
    if not IsValid(owner) then 
        print("[AI DEBUG] ApplyAllSettingsToBot: невалидный владелец")
        return false 
    end
    local data = BotManager and BotManager:GetData(bot)
    if not data then
        if AI_Utils and AI_Utils.LogDebug then
            AI_Utils.LogDebug("Settings", "Инициализация данных для бота %s", bot:Nick())
        end
        data = InitBotData(bot, owner, settings)
        if not data then
            if AI_Utils and AI_Utils.LogError then
                AI_Utils.LogError("Settings", "Не удалось инициализировать данные для бота %s", bot:Nick())
            end
            return false
        end
        if BotManager and BotManager.UpdateData then
            BotManager:UpdateData(bot, data)
        end
    end
    if not IsValid(data.owner) or data.owner ~= owner then
        if IsValid(owner) then
            data.owner = owner
            if BotManager then
                BotManager:UpdateData(bot, data)
            end
        else
            if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                if AI_Utils and AI_Utils.LogDebug then
                    AI_Utils.LogDebug("Settings", "ОТКАЗ: бот %s не имеет владельца", bot:Nick())
                end
            end
            return false
        end
    end
    local nwOwner = bot:GetNWEntity("AICompanionOwnerEnt")
    if not IsValid(nwOwner) or nwOwner ~= owner then
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            if AI_Utils and AI_Utils.LogDebug then
                AI_Utils.LogDebug("Settings", "NWVar рассинхрон для %s, исправляем", bot:Nick())
            end
        end
        bot:SetNWEntity("AICompanionOwnerEnt", owner)
        bot:SetNWString("AICompanionOwner", owner:Nick())
    end
    data.owner = owner
    local cfg = data.config
    if not cfg then
        cfg = {
            combat_weapon = "weapon_smg1",
            melee_weapon = "weapon_crowbar",
            idle_weapon = "weapon_physgun",
            stealth_mode = false,
            defender_mode = false,
            medic_mode = false,
            pacifist_mode = false,
            aggressive_mode = false,
            model_path = "models/player/urban.mdl",
            companion_nick = "AI_Companion",
            show_sender_name = true,
        }
        data.config = cfg
    end
    if settings.model_path and settings.model_path ~= "" then
        if AI_Utils.IsValidModel(settings.model_path) then
            cfg.model_path = settings.model_path
            pcall(function() bot:SetModel(settings.model_path) end)
        end
    end
    if settings.companion_nick and settings.companion_nick ~= "" then
        cfg.companion_nick = settings.companion_nick
        pcall(function() bot:SetName(settings.companion_nick) end)
        pcall(function() bot:SetNick(settings.companion_nick) end)
    end
    if settings.combat_weapon then cfg.combat_weapon = settings.combat_weapon end
    if settings.melee_weapon  then cfg.melee_weapon  = settings.melee_weapon end
    if settings.idle_weapon   then cfg.idle_weapon   = settings.idle_weapon end
    if settings.stealth_mode  ~= nil then cfg.stealth_mode  = settings.stealth_mode end
    if settings.defender_mode ~= nil then cfg.defender_mode = settings.defender_mode end
    if settings.medic_mode    ~= nil then cfg.medic_mode    = settings.medic_mode end
    if settings.pacifist_mode ~= nil then cfg.pacifist_mode = settings.pacifist_mode end
    if settings.aggressive_mode ~= nil then cfg.aggressive_mode = settings.aggressive_mode end
    data._nw_cache.stealth_mode = cfg.stealth_mode
    data._nw_cache.defender_mode = cfg.defender_mode
    data._nw_cache.medic_mode = cfg.medic_mode
    data._nw_cache.pacifist_mode = cfg.pacifist_mode
    data._nw_cache.aggressive_mode = cfg.aggressive_mode
    data._nw_cache.owner_name = owner:Nick()
    data._nw_cache.is_ai_companion = true
    BotManager:UpdateData(bot, data)
    if SyncBotDataToNWVars then
        SyncBotDataToNWVars(bot)
    end
    if SERVER then
        if not bot:HasWeapon(cfg.combat_weapon) then bot:Give(cfg.combat_weapon) end
        if not bot:HasWeapon(cfg.melee_weapon)  then bot:Give(cfg.melee_weapon) end
        if not bot:HasWeapon(cfg.idle_weapon)   then bot:Give(cfg.idle_weapon) end
        if not bot:HasWeapon("weapon_medkit")   then bot:Give("weapon_medkit") end
        if not bot:HasWeapon("weapon_rpg")      then bot:Give("weapon_rpg") end
    end
    local state = GetBotState(bot)
    if state == "idle" or state == "" or state == "unknown" then
        SetBotState(bot, AI_Companion.States.FOLLOW)
    end
    if state ~= AI_Companion.States.COMBAT then
        if bot:HasWeapon(cfg.idle_weapon) then
            bot:SelectWeapon(cfg.idle_weapon)
        end
    end
    return true
end
_G._PlayerPrefixText = _G._PlayerPrefixText or {}
_G._PlayerPrefixColorR = _G._PlayerPrefixColorR or {}
_G._PlayerPrefixColorG = _G._PlayerPrefixColorG or {}
_G._PlayerPrefixColorB = _G._PlayerPrefixColorB or {}
_G._PlayerPrefixRainbow = _G._PlayerPrefixRainbow or {}
function ApplyPlayerSettings(ply, settings)
    if not IsValid(ply) or not settings then return end
    if ply:IsBot() then return end
    local steamID = ply:SteamID64()
    _G._PlayerPrefixText[steamID] = settings.prefix_text or "[AI]"
    _G._PlayerPrefixColorR[steamID] = settings.prefix_r or 255
    _G._PlayerPrefixColorG[steamID] = settings.prefix_g or 200
    _G._PlayerPrefixColorB[steamID] = settings.prefix_b or 0
    _G._PlayerPrefixRainbow[steamID] = settings.prefix_rainbow or false
    _G.AI_Companion_TTS_Enabled = settings.tts_enabled or false
    _G.AI_Companion_LLM_Enabled = settings.llm_enabled ~= false
    _G.AI_Companion_TTS_Global = settings.tts_enabled or false
    _G.AI_LLM_IP   = settings.llm_ip or "127.0.0.1"
    _G.AI_LLM_PORT = settings.llm_port or 1234
    _G.AI_LLM_MODEL = settings.llm_model or "local-model"
    _G.AI_COMFYUI_IP  = settings.comfyui_ip or "127.0.0.1"
    _G.AI_COMFYUI_PORT = settings.comfyui_port or 8188
    if AI then
        if AI.TTS then AI.TTS.Enabled = settings.tts_enabled or false end
        if AI.LLM then AI.LLM.Enabled = settings.llm_enabled ~= false end
    end
    if settings.debug_mode ~= nil then
        if AI_CONFIG then AI_CONFIG.DEBUG_MODE = settings.debug_mode end
    end
    SyncAllSettingsSources(ply, settings)
    if SERVER then
        local bot = BotManager and BotManager:GetBotByOwner(ply)
        if IsValid(bot) then
            local data = BotManager:GetData(bot)
            if data and IsValid(data.owner) and data.owner == ply then
                ApplyAllSettingsToBot(bot, settings, ply)
            elseif data then
                if AI_Utils and AI_Utils.LogDebug then
                    AI_Utils.LogDebug("Settings", "Исправляем владельца для бота %s", bot:Nick())
                end
                data.owner = ply
                BotManager:UpdateData(bot, data)
                ApplyAllSettingsToBot(bot, settings, ply)
            else
                if AI_Utils and AI_Utils.LogDebug then
                    AI_Utils.LogDebug("Settings", "Инициализация данных для бота %s", bot:Nick())
                end
                data = InitBotData(bot, ply, settings)
                if data and BotManager then
                    BotManager:UpdateData(bot, data)
                    ApplyAllSettingsToBot(bot, settings, ply)
                end
            end
        else
            if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                if AI_Utils and AI_Utils.LogDebug then
                    AI_Utils.LogDebug("Settings", "Игрок %s ещё не создал бота, настройки будут применены позже", ply:Nick())
                end
            end
        end
    end
    if IsValid(_G.AICompanionMenuPanel) then
        _G.AICompanionMenuPanel:RefreshValues()
    end
end
function ApplySingleSettingToBot(bot, key, value, owner)
    if not IsValid(bot) or not key then return false end
    if not IsValid(owner) then return false end
    local data = BotManager and BotManager:GetData(bot)
    if not data then 
        if AI_Utils and AI_Utils.LogDebug then
            AI_Utils.LogDebug("Settings", "Инициализация данных для применения настройки %s", key)
        end
        data = InitBotData(bot, owner, {})
        if not data then
            return false
        end
        if BotManager then
            BotManager:UpdateData(bot, data)
        end
    end
    if not IsValid(data.owner) or data.owner ~= owner then
        return false
    end
    local cfg = data.config
    if not cfg then return false end
    local applied = false
    local boolKeys = {
        stealth_mode = true,
        defender_mode = true,
        medic_mode = true,
        pacifist_mode = true,
        aggressive_mode = true,
    }
    if boolKeys[key] then
        cfg[key] = tobool(value)
        data._nw_cache[key] = cfg[key]
        applied = true
    elseif key == "combat_weapon" or key == "melee_weapon" or key == "idle_weapon" then
        cfg[key] = tostring(value)
        if SERVER then
            if not bot:HasWeapon(tostring(value)) then
                bot:Give(tostring(value))
            end
        end
        applied = true
    elseif key == "model_path" then
        if AI_Utils.IsValidModel(value) then
            cfg.model_path = value
            pcall(function() bot:SetModel(value) end)
            applied = true
        end
    elseif key == "companion_nick" then
        cfg.companion_nick = value
        pcall(function() bot:SetName(value) end)
        pcall(function() bot:SetNick(value) end)
        applied = true
    elseif key == "show_sender_name" then
        cfg.show_sender_name = tobool(value)
        applied = true
	elseif key == "custom_prompt_enabled" or key == "custom_prompt_text" or key == "allow_custom_prompts" then
		AI_SETTINGS = AI_SETTINGS or {}
		AI_SETTINGS[key] = actualValue
    end
    if applied then
        BotManager:UpdateData(bot, data)
        if SyncBotDataToNWVars then
            SyncBotDataToNWVars(bot)
        end
        return true
    end
    return false
end
function SetPlayerSetting(ply, key, value)
    if not IsValid(ply) or ply:IsBot() then return end
    local steamID = ply:SteamID64()
    if not PlayerSettings[steamID] then
        LoadPlayerSettings(ply)
    end
    local actualValue = value
    if type(value) == "string" then
        local num = tonumber(value)
        if num then
            actualValue = num
        elseif value == "true" then
            actualValue = true
        elseif value == "false" then
            actualValue = false
        end
    end
    PlayerSettings[steamID][key] = actualValue
    local BOT_RELATED_KEYS = {
        model_path = true,
        companion_nick = true,
        combat_weapon = true,
        melee_weapon = true,
        idle_weapon = true,
        stealth_mode = true,
        defender_mode = true,
        medic_mode = true,
        pacifist_mode = true,
        aggressive_mode = true,
        show_sender_name = true,
    }
    if BOT_RELATED_KEYS[key] then
        if SERVER then
            local bot = BotManager and BotManager:GetBotByOwner(ply)
            if IsValid(bot) then
                ApplySingleSettingToBot(bot, key, actualValue, ply)
            elseif AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                if AI_Utils and AI_Utils.LogDebug then
                    AI_Utils.LogDebug("Settings", "Нет бота для применения '%s'", key)
                end
            end
        end
    end
    if key == "tts_enabled" then
        ply:SetNWBool("AI_TTS_Enabled", actualValue)
        ply.AI_TTS_Enabled = actualValue
        _G.AI_Companion_TTS_Enabled = actualValue
        _G.AI_Companion_TTS_Global = actualValue
        if AI and AI.TTS then
            AI.TTS.Enabled = actualValue
        end
    elseif key == "llm_enabled" then
        _G.AI_Companion_LLM_Enabled = actualValue
        if AI and AI.LLM then
            AI.LLM.Enabled = actualValue
        end
    elseif key == "llm_ip" then
        _G.AI_LLM_IP = actualValue
        if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
            AI_CONFIG.Network.LLM.IP = actualValue
        end
    elseif key == "llm_port" then
        _G.AI_LLM_PORT = actualValue
        if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
            AI_CONFIG.Network.LLM.Port = actualValue
        end
    elseif key == "llm_model" then
        _G.AI_LLM_MODEL = actualValue
        if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
            AI_CONFIG.Network.LLM.Model = actualValue
        end
    elseif key == "comfyui_ip" then
        _G.AI_COMFYUI_IP = actualValue
        if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.TTS then
            AI_CONFIG.Network.TTS.IP = actualValue
        end
    elseif key == "comfyui_port" then
        _G.AI_COMFYUI_PORT = actualValue
        if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.TTS then
            AI_CONFIG.Network.TTS.Port = actualValue
        end
    elseif key == "debug_mode" then
        if AI_CONFIG then
            AI_CONFIG.DEBUG_MODE = actualValue
        end
    elseif key == "prefix_text" then
        _G.AI_Companion_PrefixText = actualValue
        if AI_Utils and AI_Utils.InvalidatePrefixCache then
            AI_Utils.InvalidatePrefixCache(ply)
        end
    elseif key == "prefix_r" then
        _G.AI_Companion_PrefixColorR = actualValue
        if AI and AI.Appearance and AI.Appearance.Prefix and AI.Appearance.Prefix.Color then
            AI.Appearance.Prefix.Color.R = actualValue
        end
    elseif key == "prefix_g" then
        _G.AI_Companion_PrefixColorG = actualValue
        if AI and AI.Appearance and AI.Appearance.Prefix and AI.Appearance.Prefix.Color then
            AI.Appearance.Prefix.Color.G = actualValue
        end
    elseif key == "prefix_b" then
        _G.AI_Companion_PrefixColorB = actualValue
        if AI and AI.Appearance and AI.Appearance.Prefix and AI.Appearance.Prefix.Color then
            AI.Appearance.Prefix.Color.B = actualValue
        end
    elseif key == "prefix_rainbow" then
        _G.AI_Companion_PrefixRainbow = actualValue
        if AI and AI.Appearance and AI.Appearance.Prefix then
            AI.Appearance.Prefix.Rainbow = actualValue
        end
    elseif key == "show_sender_name" then
        if AI_SETTINGS then
            AI_SETTINGS.show_sender_name = actualValue
        end
    elseif key == "llm_mode" or key == "tts_mode" or key == "tts_personal" then
        AI_SETTINGS = AI_SETTINGS or {}
        AI_SETTINGS[key] = actualValue
    elseif key == "llm_timeout" then
        AI_SETTINGS = AI_SETTINGS or {}
        AI_SETTINGS[key] = actualValue
        if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
            AI_CONFIG.Network.LLM.Timeout = actualValue
        end
    elseif key == "tts_timeout" then
        AI_SETTINGS = AI_SETTINGS or {}
        AI_SETTINGS[key] = actualValue
        if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.TTS then
            AI_CONFIG.Network.TTS.Timeout = actualValue
        end
    elseif key == "llm_provider" or key == "llm_api_key" or key == "llm_cloud_model" or
           key == "llm_endpoint" or key == "llm_temperature" or key == "llm_max_tokens" or
           key == "llm_timeout" or key == "tts_timeout" or
           key == "tts_provider" or key == "tts_api_key" or key == "tts_voice" or
           key == "tts_language" or key == "tts_endpoint" or key == "tts_speed" or
           key == "yandex_folder_id" or key == "yandex_voice" or key == "yandex_lang" or
           key == "vk_voice" or key == "vk_tempo" or
           key == "custom_prompt_enabled" or key == "custom_prompt_text" or
           key == "allow_custom_prompts" or
           key == "tts_workflow_enabled" or key == "tts_workflow" or key == "tts_workflow_filename" then
        AI_SETTINGS = AI_SETTINGS or {}
        AI_SETTINGS[key] = actualValue
    end
    SyncAllSettingsSources(ply, PlayerSettings[steamID])
    SavePlayerSettings(ply)
    if IsValid(_G.AICompanionMenuPanel) then
        _G.AICompanionMenuPanel:RefreshValues()
    end
end
function SyncPlayerSettingsToClient(ply)
    if not SERVER then return end
    if not IsValid(ply) then return end
    if ply:IsBot() then return end
    local steamID = ply:SteamID64()
    local settings = PlayerSettings[steamID]
    if not settings then 
        return 
    end
    local syncData = table.Copy(settings)
    syncData.tts_enabled = _G.AI_Companion_TTS_Enabled or false
    syncData.llm_enabled = _G.AI_Companion_LLM_Enabled or true
    local json = util.TableToJSON(syncData)
    if json and #json <= 65535 then
        net.Start("AI_Settings_Sync")
        net.WriteString(json)
        net.Send(ply)
    end
end
function GetPlayerSetting(ply, key)
    if not IsValid(ply) then return nil end
    if ply:IsBot() then return nil end
    local steamID = ply:SteamID64()
    if not PlayerSettings[steamID] then
        LoadPlayerSettings(ply)
    end
    return PlayerSettings[steamID][key]
end
function GetPlayerSettings(ply)
    if not IsValid(ply) then return table.Copy(DEFAULT_SETTINGS) end
    if ply:IsBot() then return table.Copy(DEFAULT_SETTINGS) end
    local steamID = ply:SteamID64()
    if PlayerSettings[steamID] then
        return PlayerSettings[steamID]
    end
    return LoadPlayerSettings(ply)
end
function SaveGlobalSettings(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы могут сохранять глобальные настройки")
        end
        return false
    end
    local steamID = ply:SteamID64()
    local settings = PlayerSettings[steamID]
    if not settings then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Сначала загрузите или настройте свои параметры")
        end
        return false
    end
    if file.Exists(GLOBAL_FILE, "DATA") then
        local oldData = file.Read(GLOBAL_FILE, "DATA")
        if oldData then
            local date = os.date("%Y-%m-%d_%H-%M-%S")
            local backupPath = BACKUP_DIR .. "global_backup_" .. date .. ".txt"
            file.Write(backupPath, oldData)
        end
    end
    local json = util.TableToJSON(settings)
    if not json then return false end
    file.Write(GLOBAL_FILE, json)
    SyncAllSettingsSources(ply, settings)
    if IsValid(ply) then
        ply:ChatPrint("[AI] Глобальные настройки сохранены!")
    end
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Settings", "Глобальные настройки сохранены администратором %s", ply:Nick())
    end
    return true
end
function LoadGlobalSettings(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы могут загружать глобальные настройки")
        end
        return false
    end
    if not file.Exists(GLOBAL_FILE, "DATA") then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Глобальные настройки не найдены")
        end
        return false
    end
    local data = file.Read(GLOBAL_FILE, "DATA")
    if not data then return false end
    local ok, globalSettings = pcall(util.JSONToTable, data)
    if not ok or not globalSettings then return false end
    local steamID = ply:SteamID64()
    PlayerSettings[steamID] = globalSettings
    ApplyPlayerSettings(ply, globalSettings)
    SavePlayerSettings(ply)
    SyncAllSettingsSources(ply, globalSettings)
    if IsValid(ply) then
        ply:ChatPrint("[AI] Глобальные настройки загружены и применены!")
    end
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Settings", "Глобальные настройки загружены администратором %s", ply:Nick())
    end
    return true
end
function ResetGlobalSettings(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы могут сбрасывать глобальные настройки")
        end
        return
    end
    if file.Exists(GLOBAL_FILE, "DATA") then
        file.Delete(GLOBAL_FILE)
    end
    if IsValid(ply) then
        ply:ChatPrint("[AI] Глобальные настройки удалены")
    end
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Settings", "Глобальные настройки сброшены администратором %s", ply:Nick())
    end
end
function SaveTemplate(ply, templateName)
    if not IsValid(ply) then return false end
    if not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы могут сохранять шаблоны")
        return false
    end
    if not templateName or templateName == "" then
        templateName = "template_" .. os.date("%Y-%m-%d_%H-%M-%S")
    end
    templateName = string.gsub(templateName, "[^%w_%-]", "_")
    local steamID = ply:SteamID64()
    local settings = PlayerSettings[steamID]
    if not settings then
        ply:ChatPrint("[AI] Сначала загрузите настройки")
        return false
    end
    local path = TEMPLATES_DIR .. templateName .. ".txt"
    local json = util.TableToJSON(settings)
    if not json then return false end
    file.Write(path, json)
    ply:ChatPrint("[AI] Шаблон '" .. templateName .. "' сохранён!")
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Settings", "Шаблон %s сохранён администратором %s", templateName, ply:Nick())
    end
    return true
end
function LoadTemplate(ply, templateName)
    if not IsValid(ply) then return false end
    if not templateName or templateName == "" then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Укажите имя шаблона")
        end
        return false
    end
    templateName = string.gsub(templateName, "[^%w_%-]", "_")
    local path = TEMPLATES_DIR .. templateName .. ".txt"
    if not file.Exists(path, "DATA") then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Шаблон '" .. templateName .. "' не найден")
        end
        return false
    end
    local data = file.Read(path, "DATA")
    if not data then return false end
    local ok, templateSettings = pcall(util.JSONToTable, data)
    if not ok or not templateSettings then return false end
    local steamID = ply:SteamID64()
    PlayerSettings[steamID] = templateSettings
    ApplyPlayerSettings(ply, templateSettings)
    SavePlayerSettings(ply)
    SyncAllSettingsSources(ply, templateSettings)
    if IsValid(ply) then
        ply:ChatPrint("[AI] Шаблон '" .. templateName .. "' загружен!")
    end
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Settings", "Шаблон %s загружен игроком %s", templateName, ply:Nick())
    end
    return true
end
function ListTemplates(ply)
    if not IsValid(ply) then return end
    local templates = file.Find(TEMPLATES_DIR .. "*.txt", "DATA")
    if #templates == 0 then
        ply:ChatPrint("[AI] Нет сохранённых шаблонов")
        return
    end
    ply:ChatPrint("[AI] Доступные шаблоны:")
    for i, t in ipairs(templates) do
        local name = string.gsub(t, "%.txt$", "")
        ply:ChatPrint("[AI] " .. i .. ". " .. name)
    end
end
hook.Add("PlayerInitialSpawn", "AI_Settings_LoadPlayer", function(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    timer.Simple(1, function()
        if IsValid(ply) then
            LoadPlayerSettings(ply)
            timer.Simple(0.5, function()
                if IsValid(ply) then
                    local bot = BotManager and BotManager:GetBotByOwner(ply)
                    if IsValid(bot) then
                        local settings = GetPlayerSettings(ply)
                        if settings then
                            local data = BotManager:GetData(bot)
                            if data and IsValid(data.owner) and data.owner == ply then
                                ApplyAllSettingsToBot(bot, settings, ply)
                            else
                                if AI_Utils and AI_Utils.LogDebug then
                                    AI_Utils.LogDebug("Settings", "Отложенная инициализация для бота %s", bot:Nick())
                                end
                                data = InitBotData(bot, ply, settings)
                                if data and BotManager then
                                    BotManager:UpdateData(bot, data)
                                    ApplyAllSettingsToBot(bot, settings, ply)
                                end
                            end
                        end
                    else
                        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                            if AI_Utils and AI_Utils.LogDebug then
                                AI_Utils.LogDebug("Settings", "Бот для %s ещё не создан, отложенное применение", ply:Nick())
                            end
                        end
                    end
                end
            end)
        end
    end)
end)
hook.Add("PlayerDisconnected", "AI_Settings_SavePlayer", function(ply)
    if not IsValid(ply) then return end
    if ply:IsBot() then return end
    SavePlayerSettings(ply)
    local steamID = ply:SteamID64()
    PlayerSettings[steamID] = nil
end)
function GetBotSettings(bot)
    if not IsValid(bot) then return table.Copy(DEFAULT_SETTINGS) end
    if not bot:GetNWBool("IsAICompanion", false) then
        return table.Copy(DEFAULT_SETTINGS)
    end
    local data = BotManager and BotManager:GetData(bot)
    local owner = data and data.owner
    if not IsValid(owner) then
        owner = bot:GetNWEntity("AICompanionOwnerEnt")
    end
    if IsValid(owner) then
        return GetPlayerSettings(owner)
    end
    return table.Copy(DEFAULT_SETTINGS)
end
function GetPlayerPrefixColor(ply)
    if not IsValid(ply) then return Color(150, 150, 150) end
    if ply:IsBot() then return Color(150, 150, 150) end
    local settings = GetPlayerSettings(ply)
    if settings.prefix_rainbow then
        local hue = (CurTime() * (AI.Config and AI.Config.Appearance and AI.Config.Appearance.RainbowSpeed or 120)) % 360
        return HSVToColor(hue, 1, 1)
    end
    return Color(
        settings.prefix_r or 150,
        settings.prefix_g or 150,
        settings.prefix_b or 150
    )
end
function GetPlayerPrefix(ply)
    if not IsValid(ply) then return "[AI]" end
    if ply:IsBot() then return "[AI]" end
    local settings = GetPlayerSettings(ply)
    return settings.prefix_text or "[AI]"
end
local GLOBAL_SETTING_KEYS = {
    llm_ip = true, llm_port = true, llm_model = true,
    comfyui_ip = true, comfyui_port = true,
    llm_mode = true, tts_mode = true,
    llm_enabled = true, tts_enabled = true,
    llm_provider = true, llm_api_key = true,
    llm_cloud_model = true, llm_endpoint = true,
    llm_temperature = true, llm_max_tokens = true,
    tts_provider = true, tts_api_key = true,
    tts_voice = true, tts_language = true,
    tts_endpoint = true, tts_speed = true,
    yandex_folder_id = true, yandex_voice = true, yandex_lang = true,
    vk_voice = true, vk_tempo = true,
    debug_mode = true, locale = true,
    custom_prompt_enabled = true,
    custom_prompt_text = true,
    allow_custom_prompts = true,
    tts_workflow_enabled = true,
    tts_workflow = true,
    tts_workflow_filename = true,
}
function SyncGlobalSettingsToAllPlayers(adminPly)
    if not SERVER then return end
    local adminSteamID = IsValid(adminPly) and adminPly:SteamID64()
    local adminSettings = adminSteamID and PlayerSettings[adminSteamID]
    if not adminSettings then
        if IsValid(adminPly) then 
            adminPly:ChatPrint("[AI] Нет настроек для синхронизации")
        end
        return false
    end
    local globalSettingsToSave = {}
    for key, _ in pairs(GLOBAL_SETTING_KEYS) do
        if adminSettings[key] ~= nil then globalSettingsToSave[key] = adminSettings[key] end
    end
    local globalJson = util.TableToJSON(globalSettingsToSave)
    if globalJson then
        if file.Exists(GLOBAL_FILE, "DATA") then
            local oldData = file.Read(GLOBAL_FILE, "DATA")
            if oldData then
                local date = os.date("%Y-%m-%d_%H-%M-%S")
                file.Write(BACKUP_DIR .. "global_sync_" .. date .. ".txt", oldData)
            end
        end
        file.Write(GLOBAL_FILE, globalJson)
    end
    local syncCount, skippedCount = 0, 0
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and not ply:IsBot() then
            local steamID = ply:SteamID64()
            if steamID ~= adminSteamID then
                if not PlayerSettings[steamID] then LoadPlayerSettings(ply) end
                if not PlayerSettings[steamID] then PlayerSettings[steamID] = table.Copy(DEFAULT_SETTINGS) end
                local playerSettings = PlayerSettings[steamID]
                local wasChanged = false
                for key, _ in pairs(GLOBAL_SETTING_KEYS) do
                    if adminSettings[key] ~= nil and playerSettings[key] ~= adminSettings[key] then
                        playerSettings[key] = adminSettings[key]
                        wasChanged = true
                    end
                end
                if wasChanged then
                    ApplyPlayerSettings(ply, playerSettings)
                    SavePlayerSettings(ply)
                    SyncPlayerSettingsToClient(ply)
                    syncCount = syncCount + 1
                else
                    skippedCount = skippedCount + 1
                end
            end
        end
    end
    if IsValid(adminPly) then
        if syncCount > 0 then 
            adminPly:ChatPrint("[AI] Синхронизировано с " .. syncCount .. " игроком(ами)")
        end
        if skippedCount > 0 then 
            adminPly:ChatPrint("[AI] " .. skippedCount .. " игрок(ов) уже имели актуальные настройки")
        end
        adminPly:ChatPrint("[AI] Глобальные настройки сохранены")
    end
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Settings", "Глобальная синхронизация выполнена администратором %s: %d игроков обновлено, %d пропущено", 
            IsValid(adminPly) and adminPly:Nick() or "Unknown", syncCount, skippedCount)
    end
    return true
end
local SETTING_HANDLERS = {}
SETTING_HANDLERS.bot = {
    keys = {
        model_path = true,
        companion_nick = true,
        combat_weapon = true,
        melee_weapon = true,
        idle_weapon = true,
        stealth_mode = true,
        defender_mode = true,
        medic_mode = true,
        pacifist_mode = true,
        aggressive_mode = true,
        show_sender_name = true,
    },
    apply = function(ply, key, value)
        if SERVER then
            local bot = BotManager and BotManager:GetBotByOwner(ply)
            if IsValid(bot) then
                ApplySingleSettingToBot(bot, key, value, ply)
            end
        end
    end
}
SETTING_HANDLERS.tts = {
    keys = {
        tts_enabled = true,
        tts_mode = true,
        tts_personal = true,
        tts_provider = true,
        tts_api_key = true,
        tts_voice = true,
        tts_language = true,
        tts_endpoint = true,
        tts_speed = true,
        yandex_folder_id = true,
        yandex_voice = true,
        yandex_lang = true,
        vk_voice = true,
        vk_tempo = true,
    },
    apply = function(ply, key, value)
        if key == "tts_enabled" then
            _G.AI_Companion_TTS_Enabled = value
            _G.AI_Companion_TTS_Global = value
            if AI and AI.TTS then AI.TTS.Enabled = value end
            ply:SetNWBool("AI_TTS_Enabled", value)
            ply.AI_TTS_Enabled = value
        end
    end
}
SETTING_HANDLERS.llm = {
    keys = {
        llm_enabled = true,
        llm_mode = true,
        llm_provider = true,
        llm_api_key = true,
        llm_cloud_model = true,
        llm_endpoint = true,
        llm_temperature = true,
        llm_max_tokens = true,
        llm_ip = true,
        llm_port = true,
        llm_model = true,
    },
    apply = function(ply, key, value)
        if key == "llm_enabled" then
            _G.AI_Companion_LLM_Enabled = value
            if AI and AI.LLM then AI.LLM.Enabled = value end
        elseif key == "llm_ip" then
            _G.AI_LLM_IP = value
            if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
                AI_CONFIG.Network.LLM.IP = value
            end
        elseif key == "llm_port" then
            _G.AI_LLM_PORT = value
            if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
                AI_CONFIG.Network.LLM.Port = value
            end
        elseif key == "llm_model" then
            _G.AI_LLM_MODEL = value
            if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
                AI_CONFIG.Network.LLM.Model = value
            end
        end
    end
}
SETTING_HANDLERS.appearance = {
    keys = {
        prefix_text = true,
        prefix_r = true,
        prefix_g = true,
        prefix_b = true,
        prefix_rainbow = true,
    },
    apply = function(ply, key, value)
        local steamID = ply:SteamID64()
        if key == "prefix_text" then
            _G._PlayerPrefixText[steamID] = value
            if AI_Utils and AI_Utils.InvalidatePrefixCache then
                AI_Utils.InvalidatePrefixCache(ply)
            end
        elseif key == "prefix_r" then
            _G._PlayerPrefixColorR[steamID] = value
            if AI and AI.Appearance and AI.Appearance.Prefix and AI.Appearance.Prefix.Color then
                AI.Appearance.Prefix.Color.R = value
            end
        elseif key == "prefix_g" then
            _G._PlayerPrefixColorG[steamID] = value
            if AI and AI.Appearance and AI.Appearance.Prefix and AI.Appearance.Prefix.Color then
                AI.Appearance.Prefix.Color.G = value
            end
        elseif key == "prefix_b" then
            _G._PlayerPrefixColorB[steamID] = value
            if AI and AI.Appearance and AI.Appearance.Prefix and AI.Appearance.Prefix.Color then
                AI.Appearance.Prefix.Color.B = value
            end
        elseif key == "prefix_rainbow" then
            _G._PlayerPrefixRainbow[steamID] = value
            if AI and AI.Appearance and AI.Appearance.Prefix then
                AI.Appearance.Prefix.Rainbow = value
            end
        end
    end
}
SETTING_HANDLERS.cloud = {
    keys = {
        llm_timeout = true,
        tts_timeout = true,
        debug_mode = true,
        auto_sync_global = true,
        comfyui_ip = true,
        comfyui_port = true,
    },
    apply = function(ply, key, value)
        if key == "debug_mode" then
            if AI_CONFIG then AI_CONFIG.DEBUG_MODE = value end
        elseif key == "comfyui_ip" then
            _G.AI_COMFYUI_IP = value
            if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.TTS then
                AI_CONFIG.Network.TTS.IP = value
            end
        elseif key == "comfyui_port" then
            _G.AI_COMFYUI_PORT = value
            if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.TTS then
                AI_CONFIG.Network.TTS.Port = value
            end
        end
    end
}
concommand.Add("ai_sync_global", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then ply:ChatPrint("[AI] Только администраторы!") end
        return
    end
    SyncGlobalSettingsToAllPlayers(ply)
end)
concommand.Add("ai_auto_sync", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then ply:ChatPrint("[AI] Только администраторы!") end
        return
    end
    local steamID = ply:SteamID64()
    if not PlayerSettings[steamID] then LoadPlayerSettings(ply) end
    local settings = PlayerSettings[steamID] or {}
    local current = settings.auto_sync_global
    if current == nil then current = true end
    local newValue = not current
    settings.auto_sync_global = newValue
    SavePlayerSettings(ply)
    if AI_SETTINGS then
        AI_SETTINGS.auto_sync_global = newValue
    end
    local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
    ply:ChatPrint("[AI] Авто-синхронизация: " .. state)
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Settings", "Авто-синхронизация установлена в %s администратором %s", state, ply:Nick())
    end
    if SERVER then
        net.Start("AI_AutoSync_Update")
        net.WriteBool(newValue)
        net.Broadcast()
    end
end)
hook.Add("AI_GlobalSettingChanged", "AI_Settings_AutoSync", function(ply, key, value)
    if not SERVER then return end
    if not IsValid(ply) or not ply:IsAdmin() then return end
    if not GLOBAL_SETTING_KEYS[key] then return end
    local steamID = ply:SteamID64()
    local settings = PlayerSettings[steamID]
    if settings and settings.auto_sync_global ~= false then
        timer.Remove("AI_GlobalSync_Delay")
        timer.Create("AI_GlobalSync_Delay", 1.0, 1, function()
            if IsValid(ply) then SyncGlobalSettingsToAllPlayers(ply) end
        end)
    end
end)
_G.GetPlayerSettingsPath = GetPlayerSettingsPath
_G.LoadPlayerSettings = LoadPlayerSettings
_G.SavePlayerSettings = SavePlayerSettings
_G.ApplyAllSettingsToBot = ApplyAllSettingsToBot
_G.ApplyPlayerSettings = ApplyPlayerSettings
_G.ApplySingleSettingToBot = ApplySingleSettingToBot
_G.SetPlayerSetting = SetPlayerSetting
_G.GetPlayerSetting = GetPlayerSetting
_G.GetPlayerSettings = GetPlayerSettings
_G.SaveGlobalSettings = SaveGlobalSettings
_G.LoadGlobalSettings = LoadGlobalSettings
_G.ResetGlobalSettings = ResetGlobalSettings
_G.SaveTemplate = SaveTemplate
_G.LoadTemplate = LoadTemplate
_G.ListTemplates = ListTemplates
_G.GetBotSettings = GetBotSettings
_G.GetPlayerPrefixColor = GetPlayerPrefixColor
_G.GetPlayerPrefix = GetPlayerPrefix
_G.SyncPlayerSettingsToClient = SyncPlayerSettingsToClient
_G.SyncGlobalSettingsToAllPlayers = SyncGlobalSettingsToAllPlayers
_G.SyncAllSettingsSources = SyncAllSettingsSources
if AI_Utils and AI_Utils.LogInfo then
    AI_Utils.LogInfo("Settings", "загружен")
else
    AI_DebugPrint("[AI Settings] загружен")
end