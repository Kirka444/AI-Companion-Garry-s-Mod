if AI_COMPANION_LLM_LOADED then return end
AI_COMPANION_LLM_LOADED = true
local AC = _G.AI_COMPANION
if not AI_Utils then
    include("ai_companion/ai_companion_utils.lua")
end
if not AI_Companion then
    include("ai_companion/ai_companion_core.lua")
end
if not AI_CONFIG then
    include("ai_companion/ai_config.lua")
end
local MAX_HISTORY_PAIRS = AI.Config.LLM.MaxHistoryPairs
local MAX_HTTP_RETRIES = AI.Config.HTTP.RetryCount
local HTTP_RETRY_DELAY = AI.Config.HTTP.RetryDelay
local LLM_TIMEOUT = AI.Config.Network.LLM.Timeout
local MAX_TOKENS = AI.Config.Network.LLM.MaxTokens
local TEMPERATURE = AI.Config.Network.LLM.Temperature
if SERVER then
    util.AddNetworkString("AI_Companion_Chat")
    util.AddNetworkString("AI_Companion_Private_Chat")
end
requestCounter = requestCounter or 0
pendingRequests = pendingRequests or {}
companionHistory = {}
LastFallbackResponses = {}
local LLMCache = AI_Utils.CreateCache(AI.Config.Cache.LLM.Size, AI.Config.Cache.LLM.TTL)
local LLMProvider = {}
LLMProvider.__index = LLMProvider
function LLMProvider:new(config)
    local obj = {
        config = config or {},
        name = "unknown",
        enabled = true,
        defaultModel = "",
        defaultEndpoint = "",
    }
    setmetatable(obj, self)
    return obj
end
function LLMProvider:ValidateConfig()
    return true, "OK"
end
function LLMProvider:GetDisplayName()
    return self.name
end
function LLMProvider:GetEndpoint()
    return self.config.endpoint or self.defaultEndpoint
end
function LLMProvider:GetDefaultModel()
    return self.defaultModel
end
function LLMProvider:BuildRequest(messages, systemPrompt, userMessage)
    return {}, {}
end
function LLMProvider:ParseResponse(body)
    return nil, "Not implemented"
end
function LLMProvider:Request(ply, messages, systemPrompt, userMessage, callback, isPrivate)
    if not IsValid(ply) then
        if callback then callback(nil, "Player is invalid") end
        return
    end
    local valid, err = self:ValidateConfig()
    if not valid then
        if callback then callback(nil, err) end
        return
    end
    local body, headers = self:BuildRequest(messages, systemPrompt, userMessage)
    local endpoint = self:GetEndpoint()
    if not endpoint or endpoint == "" then
        if callback then callback(nil, "Endpoint is empty") end
        return
    end
    local jsonBody = util.TableToJSON(body)
    if not jsonBody then
        if callback then callback(nil, "Failed to serialize request") end
        return
    end
    if #jsonBody > 100000 then
        if messages and #messages > 4 then
            local trimmedMessages = {}
            if systemPrompt and systemPrompt ~= "" then
                table.insert(trimmedMessages, { role = "system", content = systemPrompt })
            end
            for i = math.max(1, #messages - 3), #messages do
                table.insert(trimmedMessages, messages[i])
            end
            body.messages = trimmedMessages
            jsonBody = util.TableToJSON(body)
        end
    end
    local requestID = requestCounter + 1
    requestCounter = requestID
    local timerID = "LLM_timeout_" .. tostring(requestID)
    if SERVER then
        timer.Create(timerID, LLM_TIMEOUT, 1, function()
            if callback then
                callback(nil, "Timeout")
            end
        end)
    end
    AI_Utils.HTTPQueue({
        url = endpoint,
        method = "POST",
        timeout = LLM_TIMEOUT,
        body = jsonBody,
        headers = headers,
        success = function(code, responseBody)
            timer.Remove(timerID)
            if code ~= 200 then
                if callback then callback(nil, "HTTP " .. code) end
                return
            end
            local response, err = self:ParseResponse(responseBody)
            if callback then callback(response, err) end
        end,
        error = function(err)
            timer.Remove(timerID)
            if callback then callback(nil, tostring(err)) end
        end
    })
end
local LocalLLM = {}
LocalLLM.__index = LocalLLM
setmetatable(LocalLLM, LLMProvider)
function LocalLLM:new(config)
    local obj = LLMProvider:new(config)
    obj.name = "local"
    obj.defaultModel = AI.Config.Network.LLM.Model or "local-model"
    local ip = AI_CONFIG.Network.LLM.IP or "127.0.0.1"
    local port = AI_CONFIG.Network.LLM.Port or 1234
    obj.defaultEndpoint = "http://" .. ip .. ":" .. port .. "/v1/chat/completions"
    setmetatable(obj, self)
    return obj
end
function LocalLLM:GetDisplayName()
    return "Локальный LLM (LM Studio)"
end
function LocalLLM:ValidateConfig()
    return true, "OK"
end
function LocalLLM:BuildRequest(messages, systemPrompt, userMessage)
    local body = {
        model = self.config.model or self.defaultModel,
        messages = {},
        temperature = TEMPERATURE,
        max_tokens = MAX_TOKENS,
        stream = false
    }
    if systemPrompt and systemPrompt ~= "" then
        table.insert(body.messages, { role = "system", content = systemPrompt })
    end
    for _, msg in ipairs(messages) do
        table.insert(body.messages, { role = msg.role, content = msg.content })
    end
    return body, {
        ["Content-Type"] = "application/json"
    }
end
function LocalLLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа"
    end
    if data.error then
        return nil, "Ошибка: " .. tostring(data.error.message or "неизвестная ошибка")
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа"
    end
    return data.choices[1].message.content, nil
end
local OpenAI_LLM = {}
OpenAI_LLM.__index = OpenAI_LLM
setmetatable(OpenAI_LLM, LLMProvider)
function OpenAI_LLM:new(config)
    local defaults = AI.Config.Providers.LLM.Defaults.openai
    local obj = LLMProvider:new(config)
    obj.name = "openai"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end
function OpenAI_LLM:GetDisplayName()
    return "OpenAI (ChatGPT)"
end
function OpenAI_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ OpenAI не установлен"
    end
    return true, "OK"
end
function OpenAI_LLM:BuildRequest(messages, systemPrompt, userMessage)
    local body = {
        model = self.config.model or self.defaultModel,
        messages = {},
        temperature = TEMPERATURE,
        max_tokens = MAX_TOKENS,
        stream = false
    }
    if systemPrompt and systemPrompt ~= "" then
        table.insert(body.messages, { role = "system", content = systemPrompt })
    end
    for _, msg in ipairs(messages) do
        table.insert(body.messages, { role = msg.role, content = msg.content })
    end
    return body, {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. self.config.api_key
    }
end
function OpenAI_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа OpenAI"
    end
    if data.error then
        return nil, "OpenAI ошибка: " .. tostring(data.error.message or "неизвестная ошибка")
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа OpenAI"
    end
    return data.choices[1].message.content, nil
end
local DeepSeek_LLM = {}
DeepSeek_LLM.__index = DeepSeek_LLM
setmetatable(DeepSeek_LLM, LLMProvider)
function DeepSeek_LLM:new(config)
    local defaults = AI.Config.Providers.LLM.Defaults.deepseek
    local obj = LLMProvider:new(config)
    obj.name = "deepseek"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end
function DeepSeek_LLM:GetDisplayName()
    return "DeepSeek"
end
function DeepSeek_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ DeepSeek не установлен"
    end
    return true, "OK"
end
function DeepSeek_LLM:BuildRequest(messages, systemPrompt, userMessage)
    local body = {
        model = self.config.model or self.defaultModel,
        messages = {},
        temperature = TEMPERATURE,
        max_tokens = MAX_TOKENS,
        stream = false
    }
    if systemPrompt and systemPrompt ~= "" then
        table.insert(body.messages, { role = "system", content = systemPrompt })
    end
    for _, msg in ipairs(messages) do
        table.insert(body.messages, { role = msg.role, content = msg.content })
    end
    return body, {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. self.config.api_key
    }
end
function DeepSeek_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа DeepSeek"
    end
    if data.error then
        return nil, "DeepSeek ошибка: " .. tostring(data.error.message or "неизвестная ошибка")
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа DeepSeek"
    end
    return data.choices[1].message.content, nil
end
local Anthropic_LLM = {}
Anthropic_LLM.__index = Anthropic_LLM
setmetatable(Anthropic_LLM, LLMProvider)
function Anthropic_LLM:new(config)
    local defaults = AI.Config.Providers.LLM.Defaults.anthropic
    local obj = LLMProvider:new(config)
    obj.name = "anthropic"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end
function Anthropic_LLM:GetDisplayName()
    return "Anthropic (Claude)"
end
function Anthropic_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ Anthropic не установлен"
    end
    return true, "OK"
end
function Anthropic_LLM:BuildRequest(messages, systemPrompt, userMessage)
    local body = {
        model = self.config.model or self.defaultModel,
        max_tokens = MAX_TOKENS,
        temperature = TEMPERATURE,
        messages = {}
    }
    if systemPrompt and systemPrompt ~= "" then
        body.system = systemPrompt
    end
    local anthropicMessages = {}
    for _, msg in ipairs(messages) do
        if msg.role ~= "system" then
            table.insert(anthropicMessages, { 
                role = msg.role == "assistant" and "assistant" or "user", 
                content = msg.content 
            })
        end
    end
    body.messages = anthropicMessages
    return body, {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = self.config.api_key,
        ["anthropic-version"] = "2023-06-01"
    }
end
function Anthropic_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа Anthropic"
    end
    if data.error then
        return nil, "Anthropic ошибка: " .. tostring(data.error.message or "неизвестная ошибка")
    end
    if not data.content or not data.content[1] or not data.content[1].text then
        return nil, "Неверный формат ответа Anthropic"
    end
    return data.content[1].text, nil
end
local Google_LLM = {}
Google_LLM.__index = Google_LLM
setmetatable(Google_LLM, LLMProvider)
function Google_LLM:new(config)
    local defaults = AI.Config.Providers.LLM.Defaults.google
    local obj = LLMProvider:new(config)
    obj.name = "google"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end
function Google_LLM:GetDisplayName()
    return "Google Gemini"
end
function Google_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ Google Gemini не установлен"
    end
    return true, "OK"
end
function Google_LLM:BuildRequest(messages, systemPrompt, userMessage)
    local contents = {}
    for _, msg in ipairs(messages) do
        if msg.role ~= "system" then
            local role = msg.role == "assistant" and "model" or "user"
            table.insert(contents, {
                role = role,
                parts = { { text = msg.content } }
            })
        end
    end
    if userMessage and userMessage ~= "" then
        table.insert(contents, {
            role = "user",
            parts = { { text = userMessage } }
        })
    end
    local body = {
        contents = contents,
        generationConfig = {
            temperature = TEMPERATURE,
            maxOutputTokens = MAX_TOKENS
        }
    }
    if systemPrompt and systemPrompt ~= "" then
        body.systemInstruction = {
            parts = { { text = systemPrompt } }
        }
    end
    return body, {
        ["Content-Type"] = "application/json",
        ["x-goog-api-key"] = self.config.api_key
    }
end
function Google_LLM:GetEndpoint()
    local endpoint = self.config.endpoint or self.defaultEndpoint
    local model = self.config.model or self.defaultModel
    return string.format("%s/%s:generateContent", endpoint, model)
end
function Google_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа Google Gemini"
    end
    if data.error then
        local msg = data.error.message or "неизвестная ошибка"
        if data.error.code == 403 then
            return nil, "Ошибка доступа: неверный API ключ или недостаточно прав"
        elseif data.error.code == 429 then
            return nil, "Превышен лимит запросов к Gemini"
        end
        return nil, "Google ошибка: " .. msg
    end
    if not data.candidates or #data.candidates == 0 then
        return nil, "Нет ответа от Gemini"
    end
    local candidate = data.candidates[1]
    if candidate.finishReason == "SAFETY" then
        return nil, "Ответ заблокирован политиками безопасности Google"
    end
    if not candidate.content or not candidate.content.parts or not candidate.content.parts[1] then
        return nil, "Неверный формат ответа Gemini"
    end
    return candidate.content.parts[1].text, nil
end
local Grok_LLM = {}
Grok_LLM.__index = Grok_LLM
setmetatable(Grok_LLM, LLMProvider)
function Grok_LLM:new(config)
    local defaults = AI.Config.Providers.LLM.Defaults.grok
    local obj = LLMProvider:new(config)
    obj.name = "grok"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end
function Grok_LLM:GetDisplayName()
    return "Grok (xAI)"
end
function Grok_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ xAI (Grok) не установлен"
    end
    return true, "OK"
end
function Grok_LLM:BuildRequest(messages, systemPrompt, userMessage)
    local body = {
        model = self.config.model or self.defaultModel,
        messages = {},
        temperature = TEMPERATURE,
        max_tokens = MAX_TOKENS,
        stream = false
    }
    if systemPrompt and systemPrompt ~= "" then
        table.insert(body.messages, { role = "system", content = systemPrompt })
    end
    for _, msg in ipairs(messages) do
        table.insert(body.messages, { role = msg.role, content = msg.content })
    end
    return body, {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. self.config.api_key
    }
end
function Grok_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа Grok"
    end
    if data.error then
        local msg = data.error.message or "неизвестная ошибка"
        if data.error.code == "invalid_api_key" then
            return nil, "Неверный API ключ xAI"
        elseif data.error.code == "rate_limit_exceeded" then
            return nil, "Превышен лимит запросов к Grok"
        end
        return nil, "Grok ошибка: " .. msg
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа Grok"
    end
    return data.choices[1].message.content, nil
end
local LLM_PROVIDERS = {
    ["local"] = LocalLLM,
    openai = OpenAI_LLM,
    deepseek = DeepSeek_LLM,
    anthropic = Anthropic_LLM,
    google = Google_LLM,
    grok = Grok_LLM,
}
function CreateLLMProvider(providerType, config)
    local providerClass = LLM_PROVIDERS[providerType]
    if not providerClass then
        return nil, "Неизвестный провайдер LLM: " .. tostring(providerType)
    end
    return providerClass:new(config or {})
end
function GetAvailableLLMProviders()
    return AI.Config.Providers.LLM.List
end
local PROVIDER_CACHE = {}
local PROVIDER_CACHE_TTL = 60 
function GetPlayerLLMProvider(ply)
    if not IsValid(ply) then return nil end
    local steamID = ply:SteamID64()
    local llmMode = AI_SETTINGS.llm_mode or "local"
    local cacheKey = steamID .. "_" .. llmMode
    local cached = PROVIDER_CACHE[cacheKey]
    if cached and cached.provider and (CurTime() - cached.time) < PROVIDER_CACHE_TTL then
        if cached.config and cached.config.model == (AI_SETTINGS.llm_model or "local-model") then
            return cached.provider
        end
    end
    local provider, err
    if llmMode == "local" then
        local config = {
            model = AI_SETTINGS.llm_model or "local-model",
            endpoint = "http://" .. (AI_SETTINGS.llm_ip or "127.0.0.1") .. ":" .. (AI_SETTINGS.llm_port or 1234) .. "/v1/chat/completions"
        }
        provider, err = CreateLLMProvider("local", config)
    elseif llmMode == "cloud" then
        local providerType = GetPlayerSetting(ply, "llm_provider") or AI.Config.Providers.LLM.Default
        local config = {
            model = GetPlayerSetting(ply, "llm_cloud_model"),
            endpoint = GetPlayerSetting(ply, "llm_endpoint"),
            api_key = GetPlayerSetting(ply, "llm_api_key"),
            temperature = GetPlayerSetting(ply, "llm_temperature") or TEMPERATURE,
            max_tokens = GetPlayerSetting(ply, "llm_max_tokens") or MAX_TOKENS
        }
        provider, err = CreateLLMProvider(providerType, config)
    else
        return nil
    end
    if not provider then
        AI_Utils.LogError("LLM", "Не удалось создать LLM провайдер: %s", err)
        return nil
    end
    PROVIDER_CACHE[cacheKey] = {
        provider = provider,
        config = {
            model = AI_SETTINGS.llm_model or "local-model"
        },
        time = CurTime()
    }
    return provider
end
hook.Add("AI_GlobalSettingChanged", "AI_LLM_InvalidateCache", function(ply, key, value)
    if key == "llm_mode" or key == "llm_model" or key == "llm_ip" or key == "llm_port" then
        PROVIDER_CACHE = {}
    end
end)
function GetHistory(ply)
    if not AI_Utils.IsValid(ply) then return {} end
    local steamID = ply:SteamID64()
    companionHistory[steamID] = companionHistory[steamID] or {}
    return companionHistory[steamID]
end
function AddToHistory(ply, role, content)
    if not AI_Utils.IsValid(ply) then return end
    local steamID = ply:SteamID64()
    companionHistory[steamID] = companionHistory[steamID] or {}
    local hist = companionHistory[steamID]
    content = AI_Utils.CleanText(content, AI.Config.Chat.MaxMessageLength)
    table.insert(hist, {role = role, content = content, time = CurTime()})
    local maxPairs = AI.Config.LLM.MaxHistoryPairs or 5
    local maxMessages = maxPairs * 2
    while #hist > maxMessages do
        table.remove(hist, 1)
    end
    local now = CurTime()
    local maxAge = AI.Config.Chat.MaxHistoryAge or 3600
    for i = #hist, 1, -1 do
        if now - (hist[i].time or 0) > maxAge then
            table.remove(hist, i)
        end
    end
end
function GetCustomPrompt(ply)
    if not IsValid(ply) then return nil, false end
    local steamID = ply:SteamID64()
    local settings = GetPlayerSettings(ply)
    if not settings then return nil, false end
    local customEnabled = settings.custom_prompt_enabled or false
    if not customEnabled then return nil, false end
    local customText = settings.custom_prompt_text or ""
    if customText == "" then return nil, false end
    local isAdmin = ply:IsAdmin()
    local allowCustom = settings.allow_custom_prompts or true
    if not isAdmin and not allowCustom then
        return nil, false
    end
    return customText, true
end
function GetContextInfo(ply)
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
            local isDriver = false
            if AI_Utils.IsValid(veh) and veh.GetDriver then
                isDriver = veh:GetDriver() == ply
            end
            context.playerStatus = (isDriver and "водитель" or "пассажир") .. " (" .. vehName .. ")"
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
    local bot = GetCompanion(ply)
    if AI_Utils.IsValid(bot) then
        context.botModel = bot:GetModel() or "неизвестно"
        context.botHealth = math.Round(bot:Health())
        context.botMaxHealth = math.Round(bot:GetMaxHealth())
        context.botArmor = math.Round(bot:Armor())
        context.botTask = bot:GetNWString("CurrentTask", "") or "idle"
        context.botAlive = bot:Alive()
        context.botState = GetBotState(bot) or "unknown"
        context.botWeapon = "нет"
        local aw = bot:GetActiveWeapon()
        if AI_Utils.IsValid(aw) then context.botWeapon = aw:GetClass() end
        context.botCombatWeapon = GetBotCombatWeapon(bot)
        context.botMeleeWeapon = GetBotMeleeWeapon(bot)
        context.botIdleWeapon = GetBotIdleWeapon(bot)
        if AI_Utils.IsValid(ply) then
            local dist = bot:GetPos():Distance(ply:GetPos())
            context.botDistToPlayer = math.Round(dist)
        else
            context.botDistToPlayer = "?"
        end
        local botID = bot:EntIndex()
        local data = GetBotData(bot)
        if data and data.combat and AI_Utils.IsValid(data.combat.target) then
            local target = data.combat.target
            context.botCombatTarget = IsValid(target) and (target:GetClass() or target:Nick() or "неизвестно") or nil
            context.botCombatTargetType = data.combat.target_type or "npc"
        else
            context.botCombatTarget = nil
            context.botCombatTargetType = nil
        end
    else
        context.botModel = "не создан"
        context.botHealth = "?"
        context.botMaxHealth = "?"
        context.botArmor = "?"
        context.botTask = "нет"
        context.botAlive = false
        context.botWeapon = "нет"
        context.botState = "нет"
        context.botDistToPlayer = "?"
        context.botCombatTarget = nil
        context.botCombatTargetType = nil
    end
    return context
end
function BuildSystemPrompt(ctx, ply)
    local customPrompt, enabled = GetCustomPrompt(ply)
    if enabled and customPrompt and customPrompt ~= "" then
        return customPrompt
    end
    local botNick = AI.Core.Nick or "AI Компаньон"
    if ctx and ctx.ply and AI_Utils.IsValid(ctx.ply) then
        local settings = GetPlayerSettings(ctx.ply)
        if settings and settings.companion_nick and settings.companion_nick ~= "" then
            botNick = settings.companion_nick
        end
    end
    return string.format([[
ТЫ - %s, живой ИИ-компаньон в игре Garry's Mod.
═══════════════════════════════════════════════
!!! ВАЖНЕЙШЕЕ ПРАВИЛО !!!
═══════════════════════════════════════════════
ЕСЛИ ИГРОК ПРОСИТ ТЕБЯ СДЕЛАТЬ ДЕЙСТВИЕ - ТЫ ОБЯЗАН ДОБАВИТЬ КОМАНДУ!
НЕ ПРОСТО ГОВОРИ "Я СЯДУ" - НАПИШИ КОМАНДУ!
НЕ ПРОСТО ГОВОРИ "ПОЙДУ ЗА ТОБОЙ" - НАПИШИ КОМАНДУ!
НЕ ПРОСТО ГОВОРИ "АТАКУЮ" - НАПИШИ КОМАНДУ!
═══════════════════════════════════════════════
КАК ПИСАТЬ КОМАНДЫ
═══════════════════════════════════════════════
1. Сначала напиши ОТВЕТ (что ты делаешь)
2. Затем с НОВОЙ СТРОКИ напиши !companion [команда]
3. Команда ВСЕГДА начинается с !companion
═══════════════════════════════════════════════
ПРИМЕРЫ ПРАВИЛЬНЫХ ОТВЕТОВ
═══════════════════════════════════════════════
Игрок: "Сядь"
Ты: "Хорошо, присяду."
!companion sit
Игрок: "Иди за мной"
Ты: "Иду за тобой."
!companion follow
Игрок: "Атакуй этого NPC"
Ты: "Сейчас разберусь с ним."
!companion attack combine
Игрок: "Создай стул"
Ты: "Сделаю тебе стул."
!companion spawn chair
Игрок: "Остановись"
Ты: "Ок, стою."
!companion stop
Игрок: "Покажи статус"
Ты: "Вот мой статус."
!companion status
Игрок: "Укажи направление"
Ты: "Смотри туда."
!companion point
Игрок: "Встань"
Ты: "Встаю."
!companion standup
═══════════════════════════════════════════════
ПРИМЕРЫ НЕПРАВИЛЬНЫХ ОТВЕТОВ (ТАК НЕЛЬЗЯ!)
═══════════════════════════════════════════════
 "Я сяду" - НЕТ КОМАНДЫ!
 "Иду за тобой" - НЕТ КОМАНДЫ!
 "Атакую" - НЕТ КОМАНДЫ!
 "Сделаю стул" - НЕТ КОМАНДЫ!
 "Останавливаюсь" - НЕТ КОМАНДЫ!
═══════════════════════════════════════════════
КОГДА НЕ НУЖНО ПИСАТЬ КОМАНДЫ
═══════════════════════════════════════════════
- Когда игрок просто общается (без просьб)
- Когда игрок не просит тебя ничего сделать
- В обычном диалоге
Примеры:
Игрок: "Привет"
Ты: "Привет! Как дела?" (без команды)
Игрок: "Как погода?"
Ты: "Солнечно, наверное." (без команды)
═══════════════════════════════════════════════
ДОСТУПНЫЕ КОМАНДЫ
═══════════════════════════════════════════════
!companion follow     - идти за игроком
!companion stop       - остановиться
!companion point      - указать направление
!companion sit        - сесть
!companion standup    - встать
!companion attack [имя] - атаковать
!companion spawn [тип]  - создать объект
!companion status     - показать статус
Типы для spawn: chair, table, crate, barrel, zombie, combine, citizen, dog, healthkit, ammo, grenade, jeep
═══════════════════════════════════════════════
ЗАПОМНИ!
═══════════════════════════════════════════════
ЕСЛИ ИГРОК ПРОСИТ ДЕЙСТВИЕ → ВСЕГДА ДОБАВЛЯЙ КОМАНДУ!
ГОВОРИ КРАТКО (1-2 предложения)
МАТ РАЗРЕШЁН
ОБРАЩАЙСЯ НА "ТЫ"
КОНТЕКСТ:
Игрок: %s (HP:%s/%s, Броня:%s, %s)
Оружие игрока: %s
Карта: %s
Компаньон: %s (HP:%s/%s, Состояние:%s)
]],
        botNick,
        ctx.playerName or "?",
        ctx.playerHealth or "?",
        ctx.playerMaxHealth or "?",
        ctx.playerArmor or "?",
        ctx.playerAlive and "жив" or "мёртв",
        ctx.playerWeapon or "нет",
        ctx.mapName or "?",
        ctx.botAlive and "жив" or "мёртв",
        ctx.botHealth or "?",
        ctx.botMaxHealth or "?",
        ctx.botState or "idle"
    )
end
function AskLLM(ply, message, isPrivate)
    if not IsValid(ply) then return end
    local llmEnabled = AI_SETTINGS.llm_enabled
    if not llmEnabled then
        ply:ChatPrint("[AI] LLM отключён в настройках")
        return
    end
    message = AI_Utils.CleanText(message, AI.Config.Chat.MaxMessageLength)
    if message == "" then
        ply:ChatPrint("[AI] Пустой запрос.")
        return
    end
    local cleanPrefix = AI.Utils.GetCleanPrefix(ply)
    if not cleanPrefix or cleanPrefix == "" then
        cleanPrefix = "AI"
    end
    local thinkingColor = Color(150, 150, 150)
    if isPrivate then
        net.Start("AI_Companion_Private_Chat")
        net.WriteString("Думаю...")
        net.WriteColor(thinkingColor)
        net.WriteString(cleanPrefix)
        net.WriteString(ply:Nick())
        net.WriteString(ply:SteamID64())
        net.Send(ply)
    else
        net.Start("AI_Companion_Chat")
        net.WriteString("Думаю...")
        net.WriteColor(thinkingColor)
        net.WriteString(cleanPrefix)
        net.WriteString(ply:Nick())
        net.WriteString("")
        net.Broadcast()
    end
    AddToHistory(ply, "user", message)
    local provider = GetPlayerLLMProvider(ply)
    if not provider then
        ply:ChatPrint("[AI] Не удалось получить провайдера LLM")
        return
    end
    local context = GetContextInfo(ply)
    local systemPrompt = BuildSystemPrompt(context, ply)
    local history = GetHistory(ply)
    provider:Request(ply, history, systemPrompt, message, function(response, err)
        if not IsValid(ply) then return end
        if err then
            ply:ChatPrint("[AI] Ошибка: " .. err)
            return
        end
        if not response or response == "" then
            ply:ChatPrint("[AI] Пустой ответ от LLM")
            return
        end
        response = AI_Utils.CleanText(response, AI.Config.Chat.MaxMessageLength)
		if ProcessLLMResponse then
			response = ProcessLLMResponse(ply, response)
		end
        local prefixColor = Color(
            AI.Appearance.Prefix.Color.R or 255,
            AI.Appearance.Prefix.Color.G or 200,
            AI.Appearance.Prefix.Color.B or 0
        )
        local settings = GetPlayerSettings(ply)
        if settings and settings.prefix_rainbow then
            local hue = (CurTime() * 120) % 360
            prefixColor = HSVToColor(hue, 1, 1)
        end
        local cleanPrefix = AI.Utils.GetCleanPrefix(ply)
        if not cleanPrefix or cleanPrefix == "" then
            cleanPrefix = "AI"
        end
        if isPrivate then
            net.Start("AI_Companion_Private_Chat")
            net.WriteString(response)
            net.WriteColor(prefixColor)
            net.WriteString(cleanPrefix)
            net.WriteString(ply:Nick())
            net.WriteString(ply:SteamID64())
            net.Send(ply)
        else
            net.Start("AI_Companion_Chat")
            net.WriteString(response)
            net.WriteColor(prefixColor)
            net.WriteString(cleanPrefix)
            net.WriteString(ply:Nick())
            net.WriteString("")
            net.Broadcast()
        end
        AddToHistory(ply, "assistant", response)
        if AI.TTS and AI.TTS.Enabled then
            if _G.RunComfyUIWorkflow then
                _G.RunComfyUIWorkflow(ply, response)
            end
        end
    end, isPrivate)
end
function AskLMStudioAndRespond(ply, message, requestID, isPrivate)
    AskLLM(ply, message, isPrivate)
end
_G.AskLMStudioAndRespond = AskLMStudioAndRespond
_G.AddToHistory = AddToHistory
_G.GetPlayerLLMProvider = GetPlayerLLMProvider
_G.GetAvailableLLMProviders = GetAvailableLLMProviders
_G.CreateLLMProvider = CreateLLMProvider
_G.GetCustomPrompt = GetCustomPrompt
AI.API.AskLLM = AskLLM
AI.API.AddHistory = AddToHistory
AI.API.GetLLMProvider = GetPlayerLLMProvider
AI.API.GetLLMProviders = GetAvailableLLMProviders
AI.API.CreateLLM = CreateLLMProvider
AI_DebugPrint("[AI LLM] Загружен (поддержка кастомного промта)")