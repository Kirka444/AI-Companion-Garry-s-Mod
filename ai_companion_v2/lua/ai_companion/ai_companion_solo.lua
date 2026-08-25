if game.SinglePlayer() == false then return end
if AI_COMPANION_SOLO_LOADED then return end
AI_COMPANION_SOLO_LOADED = true
_G.AI_SOLO_MODE = true
local AI = _G.AI_COMPANION_DEF
if SERVER then
    util.AddNetworkString("AI_Companion_Chat")
    util.AddNetworkString("AI_Companion_PlayAudio")
    util.AddNetworkString("AI_Companion_Private_Chat")
end
if not AI_Utils then
    include("ai_companion/ai_companion_utils.lua")
end
if not AI_SETTINGS then
    include("ai_companion/ai_companion_shared.lua")
end
if not AI_CONFIG then
    include("ai_companion/ai_config.lua")
end
_G.GetCompanion = function() return nil end
_G.HasCompanion = function() return false end
_G.GetAllCompanions = function() return {} end
_G.GetBotState = function() return "idle" end
_G.SetBotState = function() end
_G.GetBotOwner = function() return nil end
_G.GetAICleanPrefix = function(ply)
    if not IsValid(ply) then return "AI" end
    local prefix = "[AI]"
    if AI_SETTINGS and AI_SETTINGS.prefix_text then
        prefix = AI_SETTINGS.prefix_text
    end
    prefix = string.gsub(prefix, "^%[", "")
    prefix = string.gsub(prefix, "%]$", "")
    if prefix == "" then prefix = "AI" end
    return prefix
end
_G.GetAIPrefixColor = function(ply)
    if not IsValid(ply) then return Color(255, 200, 0) end
    local r, g, b = 255, 200, 0
    if AI_SETTINGS then
        r = AI_SETTINGS.prefix_r or 255
        g = AI_SETTINGS.prefix_g or 200
        b = AI_SETTINGS.prefix_b or 0
        if AI_SETTINGS.prefix_rainbow then
            local hue = (CurTime() * 120) % 360
            return HSVToColor(hue, 1, 1)
        end
    end
    return Color(r, g, b)
end
function GetPlayerSettings(ply)
    if not IsValid(ply) then return nil end
    return AI_SETTINGS
end
function GetPlayerSetting(ply, key)
    if not IsValid(ply) then return nil end
    if AI_SETTINGS and AI_SETTINGS[key] ~= nil then
        return AI_SETTINGS[key]
    end
    return nil
end
function SetPlayerSetting(ply, key, value)
    if not IsValid(ply) then return end
    if not AI_SETTINGS then AI_SETTINGS = {} end
    if AI_SETTINGS[key] == value then return end
    AI_SETTINGS[key] = value
    if key == "tts_enabled" then
        _G.AI_Companion_TTS_Enabled = value
        if AI and AI.TTS then AI.TTS.Enabled = value end
    elseif key == "llm_enabled" then
        _G.AI_Companion_LLM_Enabled = value
        if AI and AI.LLM then AI.LLM.Enabled = value end
    elseif key == "debug_mode" then
        if AI_CONFIG then AI_CONFIG.DEBUG_MODE = value end
    elseif key == "prefix_text" then
        _G.AI_Companion_PrefixText = value
    elseif key == "prefix_r" then
        _G.AI_Companion_PrefixColorR = value
    elseif key == "prefix_g" then
        _G.AI_Companion_PrefixColorG = value
    elseif key == "prefix_b" then
        _G.AI_Companion_PrefixColorB = value
    elseif key == "prefix_rainbow" then
        _G.AI_Companion_PrefixRainbow = value
    elseif key == "llm_ip" then
        _G.AI_LLM_IP = value
    elseif key == "llm_port" then
        _G.AI_LLM_PORT = value
    elseif key == "llm_model" then
        _G.AI_LLM_MODEL = value
    elseif key == "comfyui_ip" then
        _G.AI_COMFYUI_IP = value
    elseif key == "comfyui_port" then
        _G.AI_COMFYUI_PORT = value
    elseif key == "llm_mode" then
        _G.AI_LLM_MODE = value
    elseif key == "tts_mode" then
        _G.AI_TTS_MODE = value
    elseif key == "tts_personal" then
        _G.AI_TTS_PERSONAL = value
    end
    if AI_SaveSettings then AI_SaveSettings() end
end
function GetPlayerSettingSafe(ply, key, default)
    local val = GetPlayerSetting(ply, key)
    if val ~= nil then return val end
    return default
end
function SetPlayerSettingSafe(ply, key, value)
    SetPlayerSetting(ply, key, value)
end
if AI_ApplySettings then
    AI_ApplySettings()
else
    print("[AI Solo] AI_ApplySettings не найдена, пропускаем...")
end
local function SyncSoloSettings()
    if AI_LoadSettings then
        AI_LoadSettings()
    end
    if AI_ApplySettings then
        AI_ApplySettings()
    end
    if AI_SETTINGS then
        if AC and AC.Settings then
            for k, v in pairs(AI_SETTINGS) do
                AC.Settings[k] = v
            end
        end
        _G.AI_Companion_PrefixText = AI_SETTINGS.prefix_text or "[AI]"
        _G.AI_Companion_PrefixColorR = AI_SETTINGS.prefix_r or 255
        _G.AI_Companion_PrefixColorG = AI_SETTINGS.prefix_g or 200
        _G.AI_Companion_PrefixColorB = AI_SETTINGS.prefix_b or 0
        _G.AI_Companion_PrefixRainbow = AI_SETTINGS.prefix_rainbow or false
        _G.AI_LLM_IP = AI_SETTINGS.llm_ip or "127.0.0.1"
        _G.AI_LLM_PORT = AI_SETTINGS.llm_port or 1234
        _G.AI_LLM_MODEL = AI_SETTINGS.llm_model or "local-model"
        _G.AI_COMFYUI_IP = AI_SETTINGS.comfyui_ip or "127.0.0.1"
        _G.AI_COMFYUI_PORT = AI_SETTINGS.comfyui_port or 8188
        _G.AI_Companion_TTS_Enabled = AI_SETTINGS.tts_enabled or false
        _G.AI_Companion_LLM_Enabled = AI_SETTINGS.llm_enabled ~= false
    end
    if AI_Utils and AI_Utils.LogDebug then
        AI_Utils.LogDebug("Solo", "Настройки синхронизированы для соло-режима")
    end
end
SyncSoloSettings()
hook.Add("AICompanion_MenuOpened", "AI_Solo_SyncOnMenuOpen", function()
    if game.SinglePlayer() then
        SyncSoloSettings()
    end
end)
local soloHistory = {}
local cooldowns = {}
local globalLLMCooldown = 0
local reqCounter = 0
local pending = {}
local function GetSoloHistory(ply)
    if not IsValid(ply) then return {} end
    local steamID = ply:SteamID64()
    soloHistory[steamID] = soloHistory[steamID] or {}
    return soloHistory[steamID]
end
local function AddToSoloHistory(ply, role, content)
    if not IsValid(ply) then return end
    local steamID = ply:SteamID64()
    soloHistory[steamID] = soloHistory[steamID] or {}
    content = AI_Utils.CleanText(content, AI_CONFIG.Chat.MaxMessageLength or 500)
    table.insert(soloHistory[steamID], {role = role, content = content, time = CurTime()})
    local maxPairs = (AI.Config and AI.Config.LLM and AI.Config.LLM.MaxHistoryPairs) or 5
    local maxMessages = maxPairs * 2
    while #soloHistory[steamID] > maxMessages do
        table.remove(soloHistory[steamID], 1)
    end
end
local function GetSoloContext(ply)
    local context = {}
    context.ply = ply
    if AI_Utils.IsValid(ply) then
        context.playerName = ply:Nick()
        context.playerHealth = math.Round(ply:Health())
        context.playerMaxHealth = math.Round(ply:GetMaxHealth())
        context.playerArmor = math.Round(ply:Armor())
        context.playerModel = ply:GetModel() or "неизвестно"
        context.playerAlive = ply:Alive()
        if ply:InVehicle() then
            local veh = ply:GetVehicle()
            local vehName = AI_Utils.IsValid(veh) and (veh:GetClass() or "транспорт") or "транспорт"
            context.playerStatus = "в транспорте (" .. vehName .. ")"
        else
            context.playerStatus = "пешком"
        end
        local weapon = ply:GetActiveWeapon()
        context.playerWeapon = AI_Utils.IsValid(weapon) and weapon:GetClass() or "нет оружия"
    else
        context.playerName = "неизвестно"
        context.playerHealth = "?"
        context.playerMaxHealth = "?"
        context.playerArmor = "?"
        context.playerModel = "неизвестно"
        context.playerStatus = "неизвестно"
        context.playerWeapon = "неизвестно"
        context.playerAlive = false
    end
    context.mapName = game.GetMap() or "неизвестно"
    context.serverTime = os.date("%H:%M")
    context.playerCount = #player.GetAll()
    context.humanCount = #player.GetHumans()
    context.botCount = #player.GetBots()
    local npcCount = 0
    local npcTypes = {}
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if AI_Utils.IsValid(ent) and ent:Alive() then
            npcCount = npcCount + 1
            local class = ent:GetClass()
            npcTypes[class] = (npcTypes[class] or 0) + 1
        end
    end
    context.npcCount = npcCount
    context.npcTypes = npcTypes
    context.botModel = "не создан"
    context.botHealth = "?"
    context.botMaxHealth = "?"
    context.botArmor = "?"
    context.botTask = "нет"
    context.botStatus = "нет"
    context.botAlive = false
    context.botWeapon = "нет"
    context.botCrouching = "?"
    context.botState = "нет"
    context.botDistToPlayer = "?"
    context.botCombatTarget = nil
    context.botCombatTargetType = nil
    return context
end
local function BuildSoloPrompt(ctx)
    local npcInfo = ""
    if ctx.npcCount and ctx.npcCount > 0 then
        npcInfo = "\n  - Всего NPC: " .. ctx.npcCount
        if ctx.npcTypes then
            local count = 0
            for class, num in pairs(ctx.npcTypes) do
                if count < 5 then
                    npcInfo = npcInfo .. "\n    * " .. class .. ": " .. num
                    count = count + 1
                end
            end
        end
    else
        npcInfo = "\n  - Врагов поблизости нет"
    end
    local lines = {
        "Ты — AI Компаньон, помощник для игрока",
        "Твоя роль — помогать игроку",
        "Стиль общения:",
        "- Деловой, уверенный, но не сухой. Дружелюбный официальный тон.",
        "- Отвечай кратко (2-3 предложения), по делу, без воды.",
        "- Без эмодзи, без форматирования, без markdown.",
        "- Всегда отвечай на языке игрока.",
        '- Обращайся к игроку напрямую ("ты"), используй его имя только если нужно привлечь внимание.',
        '- Не описывай игрока со стороны — говори с ним, а не о нём.',
        "",
        "ТЕКУЩАЯ ОБСТАНОВКА:",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "ИГРОК (твой подопечный):",
        "  - Имя: " .. (ctx.playerName or "неизвестно"),
        "  - Здоровье: " .. (ctx.playerHealth or "?") .. "/" .. (ctx.playerMaxHealth or "?") .. " HP",
        "  - Броня: " .. (ctx.playerArmor or "?"),
        "  - Статус: " .. (ctx.playerAlive and "жив" or "МЁРТВ — предупреди, что нужно возродиться"),
        "  - Передвижение: " .. (ctx.playerStatus or "неизвестно"),
        "  - Оружие в руках: " .. (ctx.playerWeapon or "неизвестно"),
        "",
        "МИР:",
        "  - Карта: " .. (ctx.mapName or "неизвестно"),
        "  - Время на сервере: " .. (ctx.serverTime or "??:??"),
        "  - Игроков на сервере: " .. (ctx.playerCount or 1) .. " (реальных: " .. (ctx.humanCount or 1) .. ", ботов: " .. (ctx.botCount or 0) .. ")" .. npcInfo,
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "",
        "Сейчас ответь на сообщение игрока, используя контекст выше."
    }
    return table.concat(lines, "\n")
end
if game.SinglePlayer() then
    GetContextInfo = GetSoloContext
    BuildSystemPrompt = BuildSoloPrompt
end
local function CheckCooldown(ply)
    local key = ply:EntIndex()
    local last = cooldowns[key] or 0
    if CurTime() - last < (AI_CONFIG.RateLimits.CommandCooldown or 2) then
        net.Start("AI_Companion_Chat")
        net.WriteString(L:Get("cmd_llm_cooldown") or "Подождите перед следующим запросом...")
        net.WriteColor(Color(255, 0, 0))
        net.WriteString(GetAICleanPrefix(ply))
        net.Send(ply)
        return false
    end
    cooldowns[key] = CurTime()
    return true
end
local function CheckGlobalCooldown()
    if CurTime() - globalLLMCooldown < (AI_CONFIG.RateLimits.GlobalLLMCooldown or 1) then
        return false, math.ceil((AI_CONFIG.RateLimits.GlobalLLMCooldown or 1) - (CurTime() - globalLLMCooldown))
    end
    globalLLMCooldown = CurTime()
    return true, 0
end
local function SendSoloError(ply, text)
    if not IsValid(ply) then return end
    net.Start("AI_Companion_Chat")
    net.WriteString(text or "Ошибка")
    net.WriteColor(Color(255, 0, 0))
    net.WriteString(GetAICleanPrefix(ply))
    net.Send(ply)
end
function AskLLM_Solo(ply, msg)
    if not IsValid(ply) then return end
    if not AI_SETTINGS.llm_enabled then
        net.Start("AI_Companion_Chat")
        net.WriteString(L:Get("llm_disabled") or "LLM отключён в настройках")
        net.WriteColor(Color(255, 0, 0))
        net.WriteString(GetAICleanPrefix(ply))
        net.Send(ply)
        return
    end
    msg = AI_Utils.CleanText(msg, AI_CONFIG.Chat.MaxMessageLength or 500)
    if msg == "" then return end
    if not CheckCooldown(ply) then return end
    local ok, remaining = CheckGlobalCooldown()
    if not ok then
        net.Start("AI_Companion_Chat")
        net.WriteString(L:Get("cmd_llm_cooldown") or "Подождите...")
        net.WriteColor(Color(255, 0, 0))
        net.WriteString(GetAICleanPrefix(ply))
        net.Send(ply)
        return
    end
    local playerName = ply:Nick() or "Игрок"
    local fullMsg = "[Игрок " .. playerName .. "] " .. msg
    AddToSoloHistory(ply, "user", fullMsg)
    local context = GetSoloContext(ply)
    local systemPrompt = BuildSoloPrompt(context)
    local history = GetSoloHistory(ply)
    local maxTokens = (AI.Config and AI.Config.Network and AI.Config.Network.LLM and AI.Config.Network.LLM.MaxTokens) or 150
    local temperature = (AI.Config and AI.Config.Network and AI.Config.Network.LLM and AI.Config.Network.LLM.Temperature) or 0.7
    local llmTimeout = (AI.Config and AI.Config.Network and AI.Config.Network.LLM and AI.Config.Network.LLM.Timeout) or 60
    local body = {
        model = AI_SETTINGS.llm_model or "local-model",
        messages = {},
        temperature = temperature,
        max_tokens = maxTokens,
        stream = false
    }
    if systemPrompt and systemPrompt ~= "" then
        table.insert(body.messages, { role = "system", content = systemPrompt })
    end
    for _, hmsg in ipairs(history) do
        table.insert(body.messages, { role = hmsg.role, content = hmsg.content })
    end
    local jsonBody = util.TableToJSON(body)
    if not jsonBody then
        SendSoloError(ply, "Ошибка формирования JSON запроса")
        return
    end
    local cleanPrefix = GetAICleanPrefix(ply)
    local thinkingColor = Color(150, 150, 150)
    net.Start("AI_Companion_Chat")
    net.WriteString("Думаю...")
    net.WriteColor(thinkingColor)
    net.WriteString(cleanPrefix)
    net.Send(ply)
    reqCounter = reqCounter + 1
    local reqID = reqCounter
    pending[reqID] = ply
    local ip = AI_SETTINGS.llm_ip or "127.0.0.1"
    local port = AI_SETTINGS.llm_port or 1234
    local endpoint = "http://" .. ip .. ":" .. port .. "/v1/chat/completions"
    local timerID = "SoloLLM_timeout_" .. tostring(reqID)
    timer.Create(timerID, llmTimeout, 1, function()
        if pending[reqID] then
            pending[reqID] = nil
            if IsValid(ply) then
                SendSoloError(ply, "Превышено время ожидания от LLM, попробуйте позже")
            end
        end
    end)
    HTTP({
        url = endpoint,
        method = "POST",
        timeout = llmTimeout,
        body = jsonBody,
        headers = { ["Content-Type"] = "application/json" },
        success = function(code, responseBody)
            timer.Remove(timerID)
            pending[reqID] = nil
            if not IsValid(ply) then return end
            if code ~= 200 then
                ply:ChatPrint("[AI] Ошибка LLM: HTTP " .. code)
                return
            end
            local ok, data = pcall(util.JSONToTable, responseBody)
            if not ok or not data then
                ply:ChatPrint("[AI] Ошибка парсинга ответа LLM")
                return
            end
            if not data.choices or not data.choices[1] or not data.choices[1].message then
                ply:ChatPrint("[AI] Некорректный ответ от LLM")
                return
            end
            local response = data.choices[1].message.content or ""
            if response == "" then
                ply:ChatPrint("[AI] Пустой ответ от LLM")
                return
            end
            response = AI_Utils.CleanText(response, AI_CONFIG.Chat.MaxMessageLength or 500)
            local prefixColor = GetAIPrefixColor(ply)
            net.Start("AI_Companion_Chat")
            net.WriteString(response)
            net.WriteColor(prefixColor)
            net.WriteString(cleanPrefix)
            net.WriteString(ply:Nick())
            net.WriteString(ply:SteamID64())
            net.Send(ply)
            AddToSoloHistory(ply, "assistant", response)
            if AI_SETTINGS.tts_enabled and _G.AI_Companion_TTS_Enabled then
                if _G.RunComfyUIWorkflow then
                    _G.RunComfyUIWorkflow(ply, response)
                end
            end
        end,
        failed = function(err)
            timer.Remove(timerID)
            pending[reqID] = nil
            if IsValid(ply) then
                SendSoloError(ply, "Ошибка соединения: " .. tostring(err))
            end
        end
    })
end
_G.AskLLM = AskLLM_Solo
function GetPlayerLLMProvider(ply)
    if not IsValid(ply) then return nil end
    local llmEnabled = AI_SETTINGS.llm_enabled
    if llmEnabled == false then return nil end
    local llmMode = AI_SETTINGS.llm_mode or "local"
    if llmMode ~= "cloud" then return nil end
    local providerType = GetPlayerSetting(ply, "llm_provider") or "openai"
    local config = {
        model = GetPlayerSetting(ply, "llm_cloud_model"),
        endpoint = GetPlayerSetting(ply, "llm_endpoint"),
        api_key = GetPlayerSetting(ply, "llm_api_key"),
        temperature = GetPlayerSetting(ply, "llm_temperature") or 0.7,
        max_tokens = GetPlayerSetting(ply, "llm_max_tokens") or 100
    }
    if _G.CreateLLMProvider then
        local provider, err = _G.CreateLLMProvider(providerType, config)
        if provider then return provider end
        return nil
    end
    return nil, "Провайдер не найден"
end
function GetPlayerTTSProvider(ply)
    if not IsValid(ply) then return nil end
    local ttsEnabled = AI_SETTINGS.tts_enabled
    if ttsEnabled == false then return nil end
    local ttsMode = AI_SETTINGS.tts_mode or "local"
    if ttsMode ~= "cloud" then return nil end
    local providerType = GetPlayerSetting(ply, "tts_provider") or "elevenlabs"
    local config = {
        voice = GetPlayerSetting(ply, "tts_voice"),
        language = GetPlayerSetting(ply, "tts_language"),
        endpoint = GetPlayerSetting(ply, "tts_endpoint"),
        api_key = GetPlayerSetting(ply, "tts_api_key")
    }
    if _G.CreateTTSProvider then
        local provider, err = _G.CreateTTSProvider(providerType, config)
        if provider then return provider end
        return nil
    end
    return nil, "TTS провайдер не найден"
end
_G.GetPlayerLLMProvider = GetPlayerLLMProvider
_G.GetPlayerTTSProvider = GetPlayerTTSProvider
hook.Remove("PlayerSay", "AI_Solo_ChatCommands")
hook.Add("PlayerSay", "AI_Solo_ChatCommands", function(ply, text)
    if not AI_Utils.IsValid(ply) then return end
    if ply:IsBot() then return end
    local lowerText = string.lower(text)
    local cleanPrefix = GetAICleanPrefix(ply)
    if string.find(lowerText, "^" .. string.lower(cleanPrefix)) then return end
    if string.find(lowerText, "%[" .. string.lower(cleanPrefix) .. "%]") then return end
    if string.find(lowerText, string.lower(cleanPrefix) .. "%s*->") then return end
    local statusWords = {"думаю", "думает", "thinking", "печата", "typing", "обрабатыв", "processing", "генер", "generating"}
    for _, word in ipairs(statusWords) do
        if string.find(lowerText, word) then
            local wordCount = 0
            for _ in string.gmatch(lowerText, "%S+") do wordCount = wordCount + 1 end
            if wordCount <= 3 then return end
        end
    end
    if string.find(text, "->") and (string.find(text, "%[") or string.find(text, "%]")) then return end
    if string.StartWith(lowerText, "!") then return end
    if string.StartWith(lowerText, "/") then return end
    if string.StartWith(lowerText, "\\") then return end
    if not AI_SETTINGS.llm_enabled then return end
    local msg = string.Trim(text)
    if msg == "" then return end
    AskLLM_Solo(ply, msg)
end)
hook.Add("PlayerDisconnected", "AI_Solo_Cleanup", function(ply)
    if not AI_Utils.IsValid(ply) then return end
    for id, p in pairs(pending) do
        if p == ply then
            timer.Remove("Solo_Cleanup_" .. id)
            timer.Remove("LLM_timeout_" .. tostring(id))
            pending[id] = nil
        end
    end
end)
concommand.Add("ai_llm_ip", function(ply, cmd, args)
    if #args < 1 then
        print("Использование: ai_llm_ip <ip> [port]")
        print("Текущий: " .. AI_CONFIG.GetLLMURL())
        return
    end
    local input = args[1]
    local ip, portFromInput = input:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
    if not ip then ip = input:match("^(%d+%.%d+%.%d+%.%d+)$") or input end
    local ok, err = AI_Utils.ValidateIP(ip)
    if not ok then
        AI_DebugPrint("[AI] " .. err)
        if IsValid(ply) then ply:ChatPrint("[AI] " .. err) end
        return
    end
    local port = portFromInput or (args[2] and tonumber(args[2])) or 1234
    local ok2, portNum = AI_Utils.ValidatePort(port)
    if not ok2 then
        AI_DebugPrint("[AI] " .. portNum)
        if IsValid(ply) then ply:ChatPrint("[AI] " .. portNum) end
        return
    end
    if AI_SETTINGS then
        AI_SETTINGS.llm_ip = ip
        AI_SETTINGS.llm_port = portNum
        if AI_SaveSettings then AI_SaveSettings() end
    end
    _G.AI_LLM_IP = ip
    _G.AI_LLM_PORT = portNum
    AI_DebugPrint("[AI] LLM IP установлен: " .. ip .. ":" .. portNum)
    if IsValid(ply) then ply:ChatPrint("[AI] LLM IP: " .. ip .. ":" .. portNum) end
end)
concommand.Add("ai_tts_ip", function(ply, cmd, args)
    if #args < 1 then
        print("Использование: ai_tts_ip <ip> [port]")
        print("Текущий: " .. AI_CONFIG.GetTTSURL())
        return
    end
    local input = args[1]
    local ip, portFromInput = input:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
    if not ip then ip = input:match("^(%d+%.%d+%.%d+%.%d+)$") or input end
    local ok, err = AI_Utils.ValidateIP(ip)
    if not ok then
        AI_DebugPrint("[AI] " .. err)
        if IsValid(ply) then ply:ChatPrint("[AI] " .. err) end
        return
    end
    local port = portFromInput or (args[2] and tonumber(args[2])) or 8188
    local ok2, portNum = AI_Utils.ValidatePort(port)
    if not ok2 then
        AI_DebugPrint("[AI] " .. portNum)
        if IsValid(ply) then ply:ChatPrint("[AI] " .. portNum) end
        return
    end
    if AI_SETTINGS then
        AI_SETTINGS.comfyui_ip = ip
        AI_SETTINGS.comfyui_port = portNum
        if AI_SaveSettings then AI_SaveSettings() end
    end
    _G.AI_COMFYUI_IP = ip
    _G.AI_COMFYUI_PORT = portNum
    AI_DebugPrint("[AI] ComfyUI IP установлен: " .. ip .. ":" .. portNum)
    if IsValid(ply) then ply:ChatPrint("[AI] ComfyUI IP: " .. ip .. ":" .. portNum) end
end)
concommand.Add("ai_tts_status", function(ply)
    if not IsValid(ply) then return end
    local status = _G.AI_Companion_TTS_Enabled and " ВКЛЮЧЕН" or " ОТКЛЮЧЕН"
    ply:ChatPrint("[AI] === СТАТУС TTS ===")
    ply:ChatPrint("[AI] Глобальный TTS: " .. status)
    ply:ChatPrint("[AI] URL ComfyUI: " .. AI_CONFIG.GetTTSURL())
    if ply:IsAdmin() then
        ply:ChatPrint("[AI] Админ-команды:")
        ply:ChatPrint("[AI]   ai_tts_global_on  - включить TTS")
        ply:ChatPrint("[AI]   ai_tts_global_off - отключить TTS")
        ply:ChatPrint("[AI]   ai_tts_toggle     - переключить TTS")
    end
end)
concommand.Add("ai_companion_llm_model", function(ply, cmd, args)
    if not IsValid(ply) then return end
    if #args < 1 then
        print(L:Get("cmd_usage_llm_model"))
        print(L:Get("cmd_current_llm_model") .. (AI_SETTINGS.llm_model or "local-model"))
        return
    end
    local model = table.concat(args, " ")
    model = string.sub(model, 1, 100)
    AI_SETTINGS.llm_model = model
    _G.AI_LLM_MODEL = model
    AI_SaveSettings()
    print("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_llm_model"):format(model))
end)
concommand.Add("ai_save_settings", function(ply)
    if not IsValid(ply) then return end
    if AI_SaveSettings then AI_SaveSettings() end
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_saved")) end
end)
concommand.Add("ai_tts_global_on", function(ply)
    if not IsValid(ply) then return end
    AI_SETTINGS.tts_enabled = true
    _G.AI_Companion_TTS_Enabled = true
    if AI and AI.TTS then AI.TTS.Enabled = true end
    AI_SaveSettings()
    print("[AI] TTS включен")
end)
concommand.Add("ai_tts_global_off", function(ply)
    if not IsValid(ply) then return end
    AI_SETTINGS.tts_enabled = false
    _G.AI_Companion_TTS_Enabled = false
    if AI and AI.TTS then AI.TTS.Enabled = false end
    AI_SaveSettings()
    print("[AI] TTS отключен")
end)
concommand.Add("ai_tts_toggle", function(ply)
    if not IsValid(ply) then return end
    if AI_SETTINGS.tts_enabled then
        RunConsoleCommand("ai_tts_global_off")
    else
        RunConsoleCommand("ai_tts_global_on")
    end
end)
concommand.Add("ai_companion_debug", function(ply)
    if not IsValid(ply) then return end
    if not AI_CONFIG then
        ply:PrintMessage(HUD_PRINTTALK, "[" .. L:Get("ai_prefix") .. "] " .. L:Get("error_config_not_found"))
        return
    end
    AI_CONFIG.DEBUG_MODE = not AI_CONFIG.DEBUG_MODE
    AI_SETTINGS.debug_mode = AI_CONFIG.DEBUG_MODE
    if AI_SaveSettings then AI_SaveSettings() end
    local state = AI_CONFIG.DEBUG_MODE and L:Get("mode_on") or L:Get("mode_off")
    print("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_debug"):format(state))
    ply:PrintMessage(HUD_PRINTTALK, "[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_debug"):format(state))
end)
concommand.Add("ai_reset_settings", function(ply)
    if not IsValid(ply) then return end
    local defaultSettings = {
        llm_ip = "127.0.0.1",
        llm_port = 1234,
        llm_model = "local-model",
        comfyui_ip = "127.0.0.1",
        comfyui_port = 8188,
        tts_enabled = false,
        llm_enabled = true,
        debug_mode = false,
        prefix_text = "[AI]",
        prefix_r = 255,
        prefix_g = 200,
        prefix_b = 0,
        prefix_rainbow = false,
        llm_timeout = 60,
        tts_timeout = 120
    }
    for k, v in pairs(defaultSettings) do
        AI_SETTINGS[k] = v
    end
    _G.AI_Companion_TTS_Enabled = false
    _G.AI_Companion_LLM_Enabled = true
    if AI then
        if AI.TTS then AI.TTS.Enabled = false end
        if AI.LLM then AI.LLM.Enabled = true end
    end
    _G.AI_Companion_PrefixText = "[AI]"
    _G.AI_Companion_PrefixColorR = 255
    _G.AI_Companion_PrefixColorG = 200
    _G.AI_Companion_PrefixColorB = 0
    _G.AI_Companion_PrefixRainbow = false
    _G.AI_LLM_TIMEOUT = 60
    _G.AI_TTS_TIMEOUT = 120
    _G.AI_LLM_IP = "127.0.0.1"
    _G.AI_LLM_PORT = 1234
    _G.AI_LLM_MODEL = "local-model"
    _G.AI_COMFYUI_IP = "127.0.0.1"
    _G.AI_COMFYUI_PORT = 8188
    if AI_CONFIG then AI_CONFIG.DEBUG_MODE = false end
    if AI_SaveSettings then AI_SaveSettings() end
    ply:PrintMessage(HUD_PRINTTALK, "[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_reset"))
end)
concommand.Add("ai_companion_status", function(ply)
    if not IsValid(ply) then return end
    print(HUD_PRINTTALK, "[" .. L:Get("ai_prefix") .. "] " .. L:Get("status_multiplayer_only"))
end)
concommand.Add("ai_lang", function(ply, cmd, args)
    if not IsValid(ply) then return end
    if not ply:IsAdmin() then
        ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("settings_admin_only"))
        return
    end
    if not _L then
        ply:ChatPrint("[" .. L:Get("ai_prefix") .. "] " .. L:Get("locale_not_loaded"))
        return
    end
    local lang = args[1]
    if not lang then
        local prefix = _L:Get("ai_prefix")
        local current = _L:GetLang()
        local available = table.concat(_L:GetAvailable(), ", ")
        ply:ChatPrint(prefix .. " " .. L:Get("locale_current") .. current)
        ply:ChatPrint(prefix .. " " .. L:Get("locale_available") .. available)
        return
    end
    if _L:SetLang(lang) then
        local prefix = _L:Get("ai_prefix")
        local msg = prefix .. " " .. L:Get("locale_changed"):format(lang)
        ply:ChatPrint(msg)
        if AI_SETTINGS then
            AI_SETTINGS.locale = lang
            if AI_SaveSettings then AI_SaveSettings() end
        end
    else
        local prefix = _L:Get("ai_prefix")
        ply:ChatPrint(prefix .. " " .. L:Get("locale_not_found"):format(lang))
    end
end)
concommand.Add("ai_request_settings", function(ply)
    if not IsValid(ply) then return end
    if SERVER then
        net.Start("AI_Settings_Sync")
        net.WriteTable(AI_SETTINGS or {})
        net.Send(ply)
    end
end)
concommand.Add("ai_test_llm", function(ply)
    if not IsValid(ply) then return end
    AI_DebugPrint("[AI TEST] ═══════════════════════════════════════")
    AI_DebugPrint("[AI TEST] ПРОВЕРКА ПОДКЛЮЧЕНИЯ К LLM (СОЛО)")
    AI_DebugPrint("[AI TEST] Игрок: " .. ply:Nick())
    local llmEnabled = AI_SETTINGS.llm_enabled
    if not llmEnabled then
        local msg = " LLM отключён в настройках"
        ply:ChatPrint("[AI] " .. msg)
        AI_DebugPrint("[AI TEST] " .. msg)
        return
    end
    local ip = AI_SETTINGS.llm_ip or "127.0.0.1"
    local port = AI_SETTINGS.llm_port or 1234
    local url = "http://" .. ip .. ":" .. port
    AI_DebugPrint("[AI TEST] URL: " .. url)
    ply:ChatPrint("[AI]  Проверка LLM (" .. url .. ")...")
    HTTP({
        url = url,
        method = "GET",
        timeout = 3,
        success = function(code, body)
            local msg = " LLM доступен! (HTTP " .. code .. ")"
            ply:ChatPrint("[AI] " .. msg)
            AI_DebugPrint("[AI TEST] " .. msg)
            AI_DebugPrint("[AI TEST] ═══════════════════════════════════════")
        end,
        failed = function(err)
            local msg = " LLM недоступен!"
            ply:ChatPrint("[AI] " .. msg)
            AI_DebugPrint("[AI TEST] " .. msg)
            AI_DebugPrint("[AI TEST] Проверьте LM Studio на " .. ip .. ":" .. port)
            AI_DebugPrint("[AI TEST] ═══════════════════════════════════════")
        end
    })
end)
concommand.Add("ai_test_tts", function(ply)
    if not IsValid(ply) then return end
    AI_DebugPrint("[AI TTS TEST] ═══════════════════════════════════════")
    AI_DebugPrint("[AI TTS TEST] ПРОВЕРКА ПОДКЛЮЧЕНИЯ К TTS (СОЛО)")
    AI_DebugPrint("[AI TTS TEST] Игрок: " .. ply:Nick())
    local ttsEnabled = AI_SETTINGS.tts_enabled
    if not ttsEnabled then
        local msg = " TTS отключён в настройках"
        ply:ChatPrint("[AI] " .. msg)
        AI_DebugPrint("[AI TTS TEST] " .. msg)
        AI_DebugPrint("[AI TTS TEST] Включите TTS: ai_tts_global_on")
        AI_DebugPrint("[AI TTS TEST] ═══════════════════════════════════════")
        return
    end
    local ip = AI_SETTINGS.comfyui_ip or "127.0.0.1"
    local port = AI_SETTINGS.comfyui_port or 8188
    local url = "http://" .. ip .. ":" .. port
    AI_DebugPrint("[AI TTS TEST] URL: " .. url)
    ply:ChatPrint("[AI]  Проверка TTS (ComfyUI) на " .. url .. "...")
    local checkUrl = url
    if string.sub(checkUrl, -1) ~= "/" then
        checkUrl = checkUrl .. "/"
    end
    checkUrl = checkUrl .. "system_stats"
    HTTP({
        url = checkUrl,
        method = "GET",
        timeout = 5,
        success = function(code, body)
            if code == 200 then
                local msg = " ComfyUI доступен! (HTTP " .. code .. ")"
                ply:ChatPrint("[AI] " .. msg)
                AI_DebugPrint("[AI TTS TEST] " .. msg)
            else
                local msg = " ComfyUI ответил с кодом: " .. code
                ply:ChatPrint("[AI] " .. msg)
                AI_DebugPrint("[AI TTS TEST] " .. msg)
            end
            AI_DebugPrint("[AI TTS TEST] ═══════════════════════════════════════")
        end,
        failed = function(err)
            local msg = " ComfyUI недоступен! " .. tostring(err)
            ply:ChatPrint("[AI] " .. msg)
            AI_DebugPrint("[AI TTS TEST] " .. msg)
            AI_DebugPrint("[AI TTS TEST] Проверьте ComfyUI на " .. ip .. ":" .. port)
            AI_DebugPrint("[AI TTS TEST] ═══════════════════════════════════════")
        end
    })
end)
concommand.Add("ai_ping_servers", function(ply)
    if not IsValid(ply) then return end
    local llmIP = AI_SETTINGS.llm_ip or "127.0.0.1"
    local llmPort = AI_SETTINGS.llm_port or 1234
    local ttsIP = AI_SETTINGS.comfyui_ip or "127.0.0.1"
    local ttsPort = AI_SETTINGS.comfyui_port or 8188
    local llmUrl = "http://" .. llmIP .. ":" .. llmPort
    local ttsUrl = "http://" .. ttsIP .. ":" .. ttsPort
    AI_DebugPrint("[AI Ping] Пинг LLM: " .. llmUrl)
    AI_DebugPrint("[AI Ping] Пинг TTS: " .. ttsUrl)
    local llmChecked = false
    local ttsChecked = false
    local checkDone = false
    local function checkBothDone()
        if checkDone then return end
        if llmChecked and ttsChecked then
            checkDone = true
        end
    end
    HTTP({
        url = llmUrl,
        method = "GET",
        timeout = 3,
        success = function(code, body)
            AI_DebugPrint("[AI PING] Получен ответ от LLM")
            llmChecked = true
            checkBothDone()
        end,
        failed = function(err)
            AI_DebugPrint("[AI PING] Попытка пинга LLM провалилась")
            llmChecked = true
            checkBothDone()
        end
    })
    HTTP({
        url = ttsUrl,
        method = "GET",
        timeout = 3,
        success = function(code, body)
            AI_DebugPrint("[AI PING] Получен ответ от TTS")
            ttsChecked = true
            checkBothDone()
        end,
        failed = function(err)
            AI_DebugPrint("[AI PING] Попытка пинга TTS провалилась")
            ttsChecked = true
            checkBothDone()
        end
    })
    timer.Simple(6, function()
        if checkDone then return end
        checkDone = true
        if not llmChecked then
            AI_DebugPrint("[AI PING] Попытка пинга LLM провалилась")
        end
        if not ttsChecked then
            AI_DebugPrint("[AI PING] Попытка пинга TTS провалилась")
        end
    end)
end)
print("[" .. (L:Get("ai_prefix")) .. "] " .. L:Get("console_solo_loaded"))