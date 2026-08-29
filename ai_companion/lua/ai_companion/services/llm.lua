
local LLM = {}

function LLM:new(utils, config, state)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        _initialized = false,
        _history = {},
        _pendingRequests = {},
        _requestCounter = 0,
        _providerCache = {},
        _cacheTTL = 60,
        _llmCache = nil,
        _lastFallbackResponses = {},
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function LLM:init()
    if self._initialized then return end

    if SERVER then
        self:SetupNetMessages()
        self:SetupCommands()
        self:SetupChatHook()
    end

    local cacheSize = 50
    local cacheTTL = 3600
    if self.config then
        local cacheConfig = self.config:get("Cache")
        if cacheConfig and cacheConfig.LLM then
            cacheSize = cacheConfig.LLM.Size or 50
            cacheTTL = cacheConfig.LLM.TTL or 3600
        end
    end
    if self.utils and self.utils.CreateCache then
        self._llmCache = self.utils.CreateCache(cacheSize, cacheTTL)
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("LLM", "LLM сервис инициализирован")
    end
end

function LLM:GetSetting(key, default)
    if self.state then
        local val = self.state:getSetting(key)
        if val ~= nil then
            return val
        end
    end
    return default
end

function LLM:GetState(key, default)
    if self.state then
        local val = self.state:getState(key)
        if val ~= nil then
            return val
        end
    end
    return default
end

function LLM:GetMaxHistoryPairs()
    return self:GetSetting("MaxHistoryPairs", 5)
end

function LLM:GetMaxMessageLength()
    local maxLen = 500
    if self.config and self.config:get("Chat") then
        maxLen = self.config:get("Chat").MaxMessageLength or 500
    end
    return maxLen
end

function LLM:GetLLMTimeout()
    return self:GetSetting("LLM_Timeout", 60)
end

function LLM:GetTemperature()
    return self:GetSetting("LLM_Temperature", 0.7)
end

function LLM:GetMaxTokens()
    return self:GetSetting("LLM_Max_Tokens", 150)
end

function LLM:GetHistory(ply)
    if not self.utils or not self.utils:IsValid(ply) then return {} end
    local steamID = ply:SteamID64()
    self._history[steamID] = self._history[steamID] or {}
    return self._history[steamID]
end

function LLM:AddHistory(ply, role, content)
    if not self.utils or not self.utils:IsValid(ply) then return end

    if content == nil then
        self.utils:LogDebug("[AI LLM DEBUG] AddHistory: content = nil, пропускаю")
        return
    end
    content = tostring(content)

    local steamID = ply:SteamID64()
    self._history[steamID] = self._history[steamID] or {}
    local hist = self._history[steamID]

    content = self.utils:CleanText(content, self:GetMaxMessageLength())
    table.insert(hist, { role = role, content = content, time = CurTime() })

    local maxPairs = self:GetMaxHistoryPairs()
    local maxMessages = maxPairs * 2
    while #hist > maxMessages do
        table.remove(hist, 1)
    end

    local maxAge = 3600
    if self.config and self.config:get("Chat") then
        maxAge = self.config:get("Chat").MaxHistoryAge or 3600
    end
    local now = CurTime()
    for i = #hist, 1, -1 do
        if now - (hist[i].time or 0) > maxAge then
            table.remove(hist, i)
        end
    end
end

function LLM:ClearHistory(ply)
    if not self.utils or not self.utils:IsValid(ply) then return end
    local steamID = ply:SteamID64()
    self._history[steamID] = {}
end

local LLMProvider = {}
LLMProvider.__index = LLMProvider

function LLMProvider:new(config, llmService)
    local obj = {
        config = config or {},
        name = "unknown",
        enabled = true,
        defaultModel = "",
        defaultEndpoint = "",
        llmService = llmService,
        utils = llmService and llmService.utils,
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
    local endpoint = self.config and self.config.endpoint or self.defaultEndpoint
    if endpoint then
        endpoint = string.Trim(endpoint)
    end
    return endpoint
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

    self.utils:LogDebug("[AI LLM REQUEST] ========================================")
    self.utils:LogDebug("[AI LLM REQUEST] Вызов Request!")
    self.utils:LogDebug("[AI LLM REQUEST] self.name =", self.name)
    self.utils:LogDebug("[AI LLM REQUEST] endpoint =", endpoint)
    self.utils:LogDebug("[AI LLM REQUEST] ========================================")

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

    local llmService = self.llmService
    if not llmService then
        if callback then callback(nil, "LLM service not available") end
        return
    end

    llmService._requestCounter = llmService._requestCounter + 1
    local requestID = llmService._requestCounter
    local timerID = "LLM_timeout_" .. tostring(requestID)

    if SERVER then
        timer.Create(timerID, llmService:GetLLMTimeout(), 1, function()
            if callback then
                callback(nil, "Timeout")
            end
        end)
    end

    local params = {
        url = endpoint,
        method = "POST",
        timeout = llmService:GetLLMTimeout(),
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
    }

    self.utils:LogDebug("[AI HTTP] ========================================")
    self.utils:LogDebug("[AI HTTP] endpoint =", endpoint)
    self.utils:LogDebug("[AI HTTP] method = POST")
    self.utils:LogDebug("[AI HTTP] timeout =", llmService:GetLLMTimeout())
    self.utils:LogDebug("[AI HTTP] body length =", #jsonBody)
    self.utils:LogDebug("[AI HTTP] ========================================")

    if llmService.utils and llmService.utils.HTTPQueue then
        self.utils:LogDebug("[AI HTTP] Вызов utils:HTTPQueue() через двоеточие")
        llmService.utils:HTTPQueue(params)
    else
        self.utils:LogDebug("[AI HTTP] Fallback на глобальный HTTP")
        HTTP(params)
    end
end

local LocalLLM = {}
LocalLLM.__index = LocalLLM
setmetatable(LocalLLM, LLMProvider)

function LocalLLM:new(config, llmService)
    local obj = LLMProvider:new(config, llmService)
    obj.name = "local"

    local model = string.Trim(llmService:GetSetting("LLM_Model", "local-model"))
    obj.defaultModel = model

    local ip = string.Trim(llmService:GetSetting("LLM_IP", "127.0.0.1"))
    local port = tonumber(string.Trim(tostring(llmService:GetSetting("LLM_Port", 1234))))

    if not port or port < 1 then port = 1234 end

    obj.defaultEndpoint = string.format("http://%s:%d/v1/chat/completions", ip, port)

    if llmService.utils then
        llmService.utils.LogDebug("LLM", "=== LOCAL LLM ПРОВАЙДЕР ===")
        llmService.utils.LogDebug("LLM", "  IP: '%s'", ip)
        llmService.utils.LogDebug("LLM", "  Port: %d", port)
        llmService.utils.LogDebug("LLM", "  Model: '%s'", model)
        llmService.utils.LogDebug("LLM", "  Endpoint: '%s'", obj.defaultEndpoint)
        llmService.utils.LogDebug("LLM", "===========================")
    end

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
        temperature = self.llmService:GetTemperature(),
        max_tokens = self.llmService:GetMaxTokens(),
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

function OpenAI_LLM:new(config, llmService)
    local defaults = {model = "gpt-4o-mini", endpoint = "https://api.openai.com/v1/chat/completions"}
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.openai
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
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
        temperature = self.llmService:GetTemperature(),
        max_tokens = self.llmService:GetMaxTokens(),
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

function DeepSeek_LLM:new(config, llmService)
    local defaults = {model = "deepseek-chat", endpoint = "https://api.deepseek.com/v1/chat/completions"}
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.deepseek
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
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
        temperature = self.llmService:GetTemperature(),
        max_tokens = self.llmService:GetMaxTokens(),
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

function Anthropic_LLM:new(config, llmService)
    local defaults = {model = "claude-3-haiku-20240307", endpoint = "https://api.anthropic.com/v1/messages"}
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.anthropic
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
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
        max_tokens = self.llmService:GetMaxTokens(),
        temperature = self.llmService:GetTemperature(),
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

function Google_LLM:new(config, llmService)
    local defaults = {model = "gemini-1.5-flash", endpoint = "https://generativelanguage.googleapis.com/v1beta/models"}
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.google
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
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
            temperature = self.llmService:GetTemperature(),
            maxOutputTokens = self.llmService:GetMaxTokens()
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
    local endpoint = self.config and self.config.endpoint or self.defaultEndpoint
    local model = self.config and self.config.model or self.defaultModel
    if endpoint and model then
        endpoint = string.Trim(endpoint)
        return string.format("%s/%s:generateContent", endpoint, model)
    end
    return nil
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

function Grok_LLM:new(config, llmService)
    local defaults = {model = "grok-2-1212", endpoint = "https://api.x.ai/v1/chat/completions"}
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.grok
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
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
        temperature = self.llmService:GetTemperature(),
        max_tokens = self.llmService:GetMaxTokens(),
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

function LLM:CreateProvider(providerType, config)
    local providerClass = LLM_PROVIDERS[providerType]
    if not providerClass then
        return nil, "Неизвестный провайдер LLM: " .. tostring(providerType)
    end
    return providerClass:new(config or {}, self)
end

function LLM:GetAvailableProviders()
    local list = {}
    if self.config and self.config:get("Providers") then
        list = self.config:get("Providers").LLM.List or {}
    else
        list = {
            { id = "local", name = "Локальный (LM Studio / Ollama)", needsKey = false },
            { id = "openai", name = "OpenAI (ChatGPT)", needsKey = true },
            { id = "deepseek", name = "DeepSeek", needsKey = true },
            { id = "anthropic", name = "Anthropic (Claude)", needsKey = true },
            { id = "google", name = "Google Gemini", needsKey = true },
            { id = "grok", name = "Grok (xAI)", needsKey = true },
        }
    end
    return list
end

function LLM:GetProvider(ply)
    if not self.utils or not self.utils:IsValid(ply) then return nil end

    local steamID = ply:SteamID64()

    local cached = self._providerCache[steamID]
    if cached and cached.provider and (CurTime() - cached.time) < self._cacheTTL then
        if cached.config and cached.config.model == self:GetSetting("LLM_Model", "local-model") then
            return cached.provider
        end
    end

    local llmMode = self:GetSetting("LLM_Mode", "local")
    local llmEnabled = self:GetState("LLM_Enabled", true)

    if not llmEnabled or llmMode == "disabled" then
        return nil
    end

    local provider, err
    self.utils:LogDebug("[LLM:GetProvider] self.utils =", tostring(self.utils))
    self.utils:LogDebug("[LLM:GetProvider] self.utils type =", type(self.utils))
    if llmMode == "local" then
        local config = {
            model = string.Trim(self:GetSetting("LLM_Model", "local-model")),
        }
        provider, err = self:CreateProvider("local", config)

    elseif llmMode == "cloud" then
        local providerType = self:GetSetting("LLM_Provider", "openai")
        local config = {
            model = string.Trim(self:GetSetting("LLM_Cloud_Model", "")),
            endpoint = string.Trim(self:GetSetting("LLM_Endpoint", "")),
            api_key = string.Trim(self:GetSetting("LLM_API_Key", "")),
            temperature = self:GetSetting("LLM_Temperature", 0.7),
            max_tokens = self:GetSetting("LLM_Max_Tokens", 150)
        }
        provider, err = self:CreateProvider(providerType, config)
    end

    if not provider then
        if err and self.utils then
            self.utils.LogError("LLM", "Не удалось создать LLM провайдер: %s", err)
        end
        return nil
    end

    self._providerCache[steamID] = {
        provider = provider,
        config = {
            model = self:GetSetting("LLM_Model", "local-model")
        },
        time = CurTime()
    }

    return provider
end

function LLM:InvalidateProviderCache(ply)
    if not self.utils or not self.utils:IsValid(ply) then return end
    local steamID = ply:SteamID64()
    self._providerCache[steamID] = nil
end

function LLM:GetContextInfo(ply)
    if not self.utils or not self.utils:IsValid(ply) then
        return {
            playerName = "неизвестно",
            playerHealth = "?",
            playerMaxHealth = "?",
            playerArmor = "?",
            playerModel = "неизвестно",
            playerAlive = false,
            playerStatus = "неизвестно",
            playerWeapon = "неизвестно",
            mapName = "неизвестно",
            serverTime = os.date("%H:%M"),
            playerCount = 0,
            humanCount = 0,
            botCount = 0,
            npcCount = 0,
            npcTypes = {},
            botModel = "не создан",
            botHealth = "?",
            botMaxHealth = "?",
            botArmor = "?",
            botTask = "нет",
            botAlive = false,
            botWeapon = "нет",
            botState = "нет",
            botDistToPlayer = "?",
            botCombatTarget = nil,
            botCombatTargetType = nil,
        }
    end

    local context = {}
    context.ply = ply
    context.playerName = ply:Nick()
    context.playerHealth = math.Round(ply:Health())
    context.playerMaxHealth = math.Round(ply:GetMaxHealth())
    context.playerArmor = math.Round(ply:Armor())
    context.playerModel = ply:GetModel() or "неизвестно"
    context.playerAlive = ply:Alive()

    if ply:InVehicle() then
        local veh = ply:GetVehicle()
        local vehName = self.utils:IsValid(veh) and (veh:GetClass() or "транспорт") or "транспорт"
        local isDriver = false
        if self.utils:IsValid(veh) and veh.GetDriver then
            isDriver = veh:GetDriver() == ply
        end
        context.playerStatus = (isDriver and "водитель" or "пассажир") .. " (" .. vehName .. ")"
    else
        context.playerStatus = "пешком"
    end

    local weapon = ply:GetActiveWeapon()
    context.playerWeapon = self.utils:IsValid(weapon) and weapon:GetClass() or "нет оружия"
    context.mapName = game.GetMap() or "неизвестно"
    context.serverTime = os.date("%H:%M")
    context.playerCount = #player.GetAll()
    context.humanCount = #player.GetHumans()
    context.botCount = #player.GetBots()

    local npcCount = 0
    local npcTypes = {}
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if self.utils:IsValid(ent) and ent:Alive() then
            npcCount = npcCount + 1
            local class = ent:GetClass()
            npcTypes[class] = (npcTypes[class] or 0) + 1
        end
    end
    context.npcCount = npcCount
    context.npcTypes = npcTypes

    local bot = nil
    local locator = _G.AI_GetLocator()
    if locator and locator:has("botmanager") then
        bot = locator:get("botmanager"):GetBotByOwner(ply)
    end

    if self.utils:IsValid(bot) then
        context.botModel = bot:GetModel() or "неизвестно"
        context.botHealth = math.Round(bot:Health())
        context.botMaxHealth = math.Round(bot:GetMaxHealth())
        context.botArmor = math.Round(bot:Armor())
        context.botTask = bot:GetNWString("CurrentTask", "") or "idle"
        context.botAlive = bot:Alive()
        context.botState = bot:GetNWString("BotState", "idle")
        context.botWeapon = "нет"
        local aw = bot:GetActiveWeapon()
        if self.utils:IsValid(aw) then context.botWeapon = aw:GetClass() end

        local dist = bot:GetPos():Distance(ply:GetPos())
        context.botDistToPlayer = math.Round(dist)

        local target = bot:GetNWEntity("CombatTarget", nil)
        if IsValid(target) then
            context.botCombatTarget = target:GetClass() or target:Nick() or "неизвестно"
            context.botCombatTargetType = target:IsPlayer() and "player" or "npc"
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

function LLM:GetCustomPrompt(ply)
    if not self.utils or not self.utils:IsValid(ply) then return nil, false end

    local steamID = ply:SteamID64()

    local customEnabled = self.state:getPlayerSetting(steamID, "Custom_Prompt_Enabled", false)
    if not customEnabled then return nil, false end

    local customText = self.state:getPlayerSetting(steamID, "Custom_Prompt_Text", "")
    if customText == "" then return nil, false end

    local isAdmin = ply:IsAdmin()
    local allowCustom = self:GetSetting("Allow_Custom_Prompts", true)

    if not isAdmin and not allowCustom then
        return nil, false
    end

    return customText, true
end

function LLM:BuildSystemPrompt(ply)
    if not self.utils or not self.utils:IsValid(ply) then
        return "Ты — AI Компаньон. Отвечай кратко. Обращайся на 'ты'."
    end

    local customPrompt, enabled = self:GetCustomPrompt(ply)
    if enabled and customPrompt and customPrompt ~= "" then
        return customPrompt
    end

    local ctx = self:GetContextInfo(ply)
    local botNick = self:GetSetting("Companion_Nick", "Компаньон")
    local playerName = ctx.playerName or ply:Nick() or "Игрок"

    local currentTime = os.date("%H:%M")

    local playerStatus = ctx.playerAlive and "жив" or "мёртв"
    if ctx.playerStatus and ctx.playerStatus ~= "" then
        playerStatus = playerStatus .. " (" .. ctx.playerStatus .. ")"
    end

    local botStatus = ctx.botAlive and "жив" or "мёртв"
    if ctx.botState and ctx.botState ~= "" then
        botStatus = botStatus .. " (" .. ctx.botState .. ")"
    end

    local npcInfo = ""
    if ctx.npcCount and ctx.npcCount > 0 then
        local npcList = {}
        for class, count in pairs(ctx.npcTypes or {}) do
            table.insert(npcList, class .. " x" .. count)
        end
        npcInfo = "NPC: " .. ctx.npcCount .. " (" .. table.concat(npcList, ", ") .. ")"
    else
        npcInfo = "NPC: нет"
    end

    local prompt = string.format([[Ты — %s. Отвечай кратко (1-2 предложения). Обращайся на "ты".
=== ИНФОРМАЦИЯ ОБ ИГРОКЕ ===
Ник: %s
Здоровье: %s / %s HP
Броня: %s
Статус: %s
Оружие: %s
Позиция: %s
=== ИНФОРМАЦИЯ О МИРЕ ===
Карта: %s
Время: %s
Игроков: %d (людей: %d, ботов: %d)
%s
=== ИНФОРМАЦИЯ О ТЕБЕ (КОМПАНЬОНЕ) ===
Твоё имя: %s
Здоровье: %s / %s HP
Броня: %s
Статус: %s
Оружие: %s
Задание: %s
Дистанция до игрока: %s м
=== КОМАНДЫ ===
Команды выполняются строго по запросу игрока. Никогда не предлагай команды первым.
!companion follow     — идти за игроком
!companion stop       — остановиться
!companion point      — указать направление
!companion sit        — сесть
!companion standup    — встать
!companion attack     — атаковать ближайшего врага
!companion spawn <тип> — создать объект (chair, table, zombie, healthkit, ammo)
!companion status     — показать статус
!companion help       — справка
=== ПРАВИЛА ===
Если игрок просит действие — ОБЯЗАТЕЛЬНО добавь !companion с новой строки
Никогда не добавляй команды без явной просьбы игрока
На обычные вопросы отвечай без команд
=== ПРИМЕРЫ ===
Игрок: "Создай стул"
Ты: "Сделаю тебе стул."
!companion spawn chair
Игрок: "Иди за мной"
Ты: "Иду."
!companion follow
Игрок: "Как у меня здоровье?"
Ты: "У тебя %s HP из %s."
Игрок: "Что тут за карта?"
Ты: "Мы на карте %s."
Игрок: "Как тебя зовут?"
Ты: "Меня зовут %s."
Игрок: "Что ты умеешь?"
Ты: "Я умею следовать, останавливаться, создавать объекты и атаковать врагов."]],
    botNick,
    playerName,
    ctx.playerHealth or "?",
    ctx.playerMaxHealth or "?",
    ctx.playerArmor or "0",
    playerStatus,
    ctx.playerWeapon or "нет оружия",
    ctx.playerAlive and "в игре" or "мёртв",
    ctx.mapName or "неизвестно",
    currentTime,
    ctx.playerCount or 0,
    ctx.humanCount or 0,
    ctx.botCount or 0,
    npcInfo,
    botNick,
    ctx.botHealth or "?",
    ctx.botMaxHealth or "?",
    ctx.botArmor or "0",
    botStatus,
    ctx.botWeapon or "нет оружия",
    ctx.botTask or "ожидание",
    ctx.botDistToPlayer or "?",
    ctx.playerHealth or "?",
    ctx.playerMaxHealth or "?",
    ctx.mapName or "неизвестно",
    botNick
    )

    -- 🔥 ИСПРАВЛЕННОЕ ВНЕДРЕНИЕ ПАМЯТИ
    local memoryContext = "" -- ✅ ОБЪЯВЛЯЕМ ПЕРЕМЕННУЮ
    local locator = _G.AI_GetLocator()
    if locator and locator:has("llm_remember") then
        local remember = locator:get("llm_remember")
        memoryContext = remember:GetMemoryContext(ply)
    end

    if memoryContext and memoryContext ~= "" then
        prompt = prompt .. "\n\n" .. memoryContext
    end

    return prompt
end

-- ============================================================
-- 8. ОСНОВНОЙ МЕТОД ОТПРАВКИ ЗАПРОСА
-- ============================================================

function LLM:Ask(ply, message, isPrivate, callback)
    self.utils:LogDebug("[AI LLM DEBUG] === Ask вызван ===")
    self.utils:LogDebug("[AI LLM DEBUG] ply: " .. (IsValid(ply) and ply:Nick() or "INVALID"))
    self.utils:LogDebug("[AI LLM DEBUG] message: " .. message)
    self.utils:LogDebug("[AI LLM DEBUG] isPrivate: " .. tostring(isPrivate))

    -- 🔥 ИСПРАВЛЕНИЕ: проверяем флаг с защитой от гонки
    if ply._llm_processing then
        self.utils:LogDebug("[AI LLM DEBUG] Уже обрабатывается запрос, пропускаю")
        if callback then callback(nil, "Уже обрабатывается запрос") end
        return
    end
    ply._llm_processing = true

    -- 🔥 ИСПРАВЛЕНИЕ: используем pcall для гарантированного сброса флага
    local function cleanup()
        if IsValid(ply) then
            ply._llm_processing = false
        end
    end

    if not self.utils or not self.utils:IsValid(ply) then
        self.utils:LogDebug("[AI LLM DEBUG] Игрок невалиден, выход")
        cleanup()
        if callback then callback(nil, "Player invalid") end
        return
    end

    if not self:GetState("LLM_Enabled", true) then
        self.utils:LogDebug("[AI LLM DEBUG] LLM отключен")
        local msg = "LLM отключён в настройках"
        self:SendThinkingMessage(ply, msg, isPrivate)
        cleanup()
        if callback then callback(nil, msg) end
        return
    end

    message = tostring(message or "")
    message = self.utils:CleanText(message, self:GetMaxMessageLength())

    if message == "" then
        self.utils:LogDebug("[AI LLM DEBUG] Пустое сообщение")
        cleanup()
        if callback then callback(nil, "Пустой запрос") end
        return
    end

    local provider = self:GetProvider(ply)
    self.utils:LogDebug("[AI LLM DEBUG] Провайдер: " .. tostring(provider and provider.name or "NIL"))

    if not provider then
        self.utils:LogDebug("[AI LLM DEBUG] Провайдер не найден!")
        local msg = "LLM провайдер не найден. Проверьте настройки."
        self:SendThinkingMessage(ply, msg, isPrivate)
        cleanup()
        if callback then callback(nil, msg) end
        return
    end

    local valid, err = provider:ValidateConfig()
    self.utils:LogDebug("[AI LLM DEBUG] ValidateConfig: valid=" .. tostring(valid) .. " err=" .. tostring(err))
    if not valid then
        self.utils:LogDebug("[AI LLM DEBUG] Конфиг невалиден")
        self:SendThinkingMessage(ply, "Ошибка: " .. err, isPrivate)
        cleanup()
        if callback then callback(nil, err) end
        return
    end

    self.utils:LogDebug("[AI LLM DEBUG] Отправка 'Думаю...'")
    self:SendThinkingMessage(ply, "Думаю...", isPrivate)

    self.utils:LogDebug("[AI LLM DEBUG] Добавление в историю")
    self:AddHistory(ply, "user", message)

    -- Добавляем в память
    local locator = _G.AI_GetLocator()
    if locator and locator:has("llm_remember") then
        local remember = locator:get("llm_remember")
        local playerName = remember:GetSafePlayerName(ply)
        remember:AddMessage(playerName, "player", message)
    end

    local history = self:GetHistory(ply)
    local systemPrompt = self:BuildSystemPrompt(ply)

    self.utils:LogDebug("[AI LLM DEBUG] История: " .. #history .. " сообщений")
    self.utils:LogDebug("[AI LLM DEBUG] Отправка запроса провайдеру...")

    -- 🔥 ИСПРАВЛЕНИЕ: callback обёрнут в pcall для гарантированного сброса
    local function safeCallback(response, err)
        local cleanupCalled = false

        -- Защита от двойного вызова
        if cleanupCalled then return end
        cleanupCalled = true

        self.utils:LogDebug("[AI LLM DEBUG] === Callback вызван ===")
        self.utils:LogDebug("[AI LLM DEBUG] response: " .. tostring(response and "ЕСТЬ (" .. #response .. " символов)" or "NIL"))
        self.utils:LogDebug("[AI LLM DEBUG] err: " .. tostring(err))

        -- 🔥 ГАРАНТИРОВАННЫЙ СБРОС ФЛАГА
        cleanup()

        if not self.utils or not self.utils:IsValid(ply) then
            self.utils:LogDebug("[AI LLM DEBUG] Игрок стал невалиден в callback")
            if callback then callback(nil, "Player disconnected") end
            return
        end

        if err then
            self.utils:LogDebug("[AI LLM DEBUG] Ошибка в ответе: " .. err)
            self:SendThinkingMessage(ply, "Ошибка: " .. err, isPrivate)
            if callback then callback(nil, err) end
            return
        end

        if not response or response == "" then
            self.utils:LogDebug("[AI LLM DEBUG] Пустой ответ")
            self:SendThinkingMessage(ply, "Пустой ответ от LLM", isPrivate)
            if callback then callback(nil, "Пустой ответ") end
            return
        end

        self.utils:LogDebug("[AI LLM DEBUG] response до очистки: '" .. string.sub(tostring(response), 1, 100) .. "'")
        response = self.utils:CleanText(response, self:GetMaxMessageLength())

        self.utils:LogDebug("[AI LLM DEBUG] После CleanText: " .. string.sub(tostring(response), 1, 100))

        if self.ProcessResponse then
            self.utils:LogDebug("[AI LLM DEBUG] Вызываю ProcessResponse")
            local processed = LLM.ProcessResponse(self, ply, response)
            self.utils:LogDebug("[AI LLM DEBUG] ProcessResponse вернул: '" .. tostring(processed) .. "'")
            response = processed
        end

        if not response or response == "" then
            self.utils:LogDebug("[AI LLM DEBUG] response стал пустым после ProcessResponse!")
            self:SendThinkingMessage(ply, "Ответ от LLM пустой после обработки", isPrivate)
            if callback then callback(nil, "Пустой ответ после обработки") end
            return
        end

        self.utils:LogDebug("[AI LLM DEBUG] Добавляю в историю и отправляю ответ")
        self:AddHistory(ply, "assistant", response)
        self:SendResponse(ply, response, isPrivate)

        if self:GetState("TTS_Enabled", false) then
            self.utils:LogDebug("[AI LLM DEBUG] TTS включен, отправляю на генерацию")
            if locator and locator:has("tts") then
                local tts = locator:get("tts")
                if tts.Generate then
                    tts:Generate(ply, response)
                end
            end
        end

        if callback then callback(response, nil) end
    end

    provider:Request(ply, history, systemPrompt, message, safeCallback, isPrivate)

    -- 🔥 ТАЙМЕР-СТРАХОВКА: если ответ не пришёл через 300 сек, сбрасываем флаг
    timer.Simple(300, function()
        if IsValid(ply) and ply._llm_processing then
            self.utils:LogWarn("LLM", "Таймаут LLM запроса для %s, принудительный сброс флага", ply:Nick())
            ply._llm_processing = false
        end
    end)

    self.utils:LogDebug("[AI LLM DEBUG] === Ask завершён (запрос отправлен) ===")
end
-- ============================================================
-- 9. ОБРАБОТКА ОТВЕТА (КОМАНДЫ)
-- ============================================================

-- ============================================================
-- 9. ОБРАБОТКА ОТВЕТА (КОМАНДЫ) - УПРОЩЁННАЯ ВЕРСИЯ
-- ============================================================

function LLM:ProcessResponse(ply, response)
    if not response then return response end

    -- Используем llm_actions для обработки команд
    local locator = _G.AI_GetLocator()
    if locator and locator:has("llm_actions") then
        local llm_actions = locator:get("llm_actions")
        return llm_actions:ProcessResponse(ply, response)
    end

    -- Fallback: старая обработка (если llm_actions нет)
    local lines = {}
    for line in string.gmatch(response, "[^\r\n]+") do
        table.insert(lines, line)
    end

    local cleanResponse = {}
    local commands = {}

    for _, line in ipairs(lines) do
        local cmd = string.match(line, "^%s*!companion%s+(.+)$")
        if cmd then
            table.insert(commands, string.Trim(cmd))
        else
            table.insert(cleanResponse, line)
        end
    end

    for _, cmd in ipairs(commands) do
        self:ExecuteCommand(ply, cmd)
    end

    return table.concat(cleanResponse, "\n")
end

function LLM:ExecuteCommand(ply, cmd)
    if not self.utils or not self.utils:IsValid(ply) then return end

    -- Используем llm_actions для выполнения команд
    local locator = _G.AI_GetLocator()
    if locator and locator:has("llm_actions") then
        local llm_actions = locator:get("llm_actions")
        -- Разбиваем cmd на команду и аргументы
        local args = string.Explode(" ", cmd)
        local command = args[1] or ""
        local arg = args[2] or ""
        llm_actions:ExecuteCommand(ply, command, arg)
    else
		local locator = _G.AI_GetLocator()
		if not locator or not locator:has("botmanager") then return end

		local bot = locator:get("botmanager"):GetBotByOwner(ply)
		if not self.utils:IsValid(bot) then return end

		local args = string.Explode(" ", cmd)
		local action = args[1] or ""

		if action == "follow" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Следую за тобой.", Color(255,200,0), "AI", ply:Nick(), false)
			end
		elseif action == "stop" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Остановился.", Color(255,200,0), "AI", ply:Nick(), false)
			end
		elseif action == "sit" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Сажусь.", Color(255,200,0), "AI", ply:Nick(), false)
			end
		elseif action == "standup" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Встаю.", Color(255,200,0), "AI", ply:Nick(), false)
			end
		elseif action == "point" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Указываю направление.", Color(255,200,0), "AI", ply:Nick(), false)
			end
		elseif action == "attack" and args[2] then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Атакую " .. args[2], Color(255,200,0), "AI", ply:Nick(), false)
			end
		elseif action == "spawn" and args[2] then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Создаю " .. args[2], Color(255,200,0), "AI", ply:Nick(), false)
			end
		elseif action == "status" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply, "Показываю статус.", Color(255,200,0), "AI", ply:Nick(), false)
			end
		end
	end
end
-- ============================================================
-- 10. ОТПРАВКА СООБЩЕНИЙ
-- ============================================================

-- llm.lua, замените функцию SendThinkingMessage:

function LLM:SendThinkingMessage(ply, text, isPrivate)
    self.utils:LogDebug("[AI LLM DEBUG] SendThinkingMessage: text='" .. text .. "' isPrivate=" .. tostring(isPrivate))

    if not self.utils or not self.utils:IsValid(ply) then
        self.utils:LogDebug("[AI LLM DEBUG] SendThinkingMessage: игрок невалиден")
        return
    end

    -- 🔥 ПЕРСОНАЛЬНЫЕ НАСТРОЙКИ
    local steamID = ply:SteamID64()
    local cleanPrefix = self.state:getPlayerSetting(steamID, "Prefix_Text", "[AI]")
    if not cleanPrefix or cleanPrefix == "" then
        cleanPrefix = "[AI]"
    end

    local cleanPrefixClean = string.gsub(cleanPrefix, "^%[", "")
    cleanPrefixClean = string.gsub(cleanPrefixClean, "%]$", "")
    if cleanPrefixClean == "" then
        cleanPrefixClean = "AI"
    end

    -- 🔥 ЦВЕТ ДЛЯ "ДУМАЮ..." - СЕРЫЙ
    local thinkingColor = Color(150, 150, 150)
    local senderName = cleanPrefixClean or "AI"

    -- ДЛЯ ПРИВАТНЫХ СООБЩЕНИЙ ВСЕГДА ПОКАЗЫВАЕМ ИМЯ
    local receiverName
    if isPrivate then
        receiverName = ply:Nick() or "Игрок"
    else
        local showName = self.state:getPlayerSetting(steamID, "Show_Sender_Name", true)
        receiverName = showName and (ply:Nick() or "Игрок") or ""
    end

    self.utils:LogDebug("[AI LLM DEBUG] SendThinkingMessage: sender=" .. senderName .. " receiver=" .. receiverName)

    local locator = _G.AI_GetLocator()
    if locator and locator:has("shared") then
        local shared = locator:get("shared")
        if isPrivate then
            shared:SendChatMessage(ply, text, thinkingColor, senderName, receiverName, true)
        else
            shared:SendChatMessage(ply, text, thinkingColor, senderName, receiverName, false)
        end
    end
end

-- llm.lua, полностью замените функцию SendResponse:

function LLM:SendResponse(ply, text, isPrivate)
    if not text then
        self.utils:LogDebug("[AI LLM DEBUG] SendResponse: text = nil, пропускаем")
        return
    end

    self.utils:LogDebug("[AI LLM DEBUG] SendResponse: text='" .. string.sub(text, 1, 50) .. "...' isPrivate=" .. tostring(isPrivate))

    if not self.utils or not self.utils:IsValid(ply) then
        self.utils:LogDebug("[AI LLM DEBUG] SendResponse: игрок невалиден")
        return
    end

    -- 🔥 ПЕРСОНАЛЬНЫЕ НАСТРОЙКИ
    local steamID = ply:SteamID64()

    -- 🔥 ПОЛУЧАЕМ ПРЕФИКС
    local cleanPrefix = self.state:getPlayerSetting(steamID, "Prefix_Text", "[AI]")
    if not cleanPrefix or cleanPrefix == "" then
        cleanPrefix = "[AI]"
    end

    -- 🔥 ОЧИЩАЕМ ПРЕФИКС ОТ СКОБОК
    local cleanPrefixClean = string.gsub(cleanPrefix, "^%[", "")
    cleanPrefixClean = string.gsub(cleanPrefixClean, "%]$", "")
    if cleanPrefixClean == "" then
        cleanPrefixClean = "AI"
    end

    -- 🔥 ЦВЕТ ПРЕФИКСА - ИЗ ПЕРСОНАЛЬНЫХ НАСТРОЕК
    local prefixColor
    local rainbow = self.state:getPlayerSetting(steamID, "Prefix_Rainbow", false)
    if rainbow then
        local hue = (CurTime() * 120) % 360
        prefixColor = HSVToColor(hue, 1, 1)
    else
        prefixColor = Color(
            self.state:getPlayerSetting(steamID, "Prefix_Color_R", 255),
            self.state:getPlayerSetting(steamID, "Prefix_Color_G", 200),
            self.state:getPlayerSetting(steamID, "Prefix_Color_B", 0)
        )
    end

    -- 🔥 ГАРАНТИРУЕМ, ЧТО senderName НЕ NIL
    local senderName = cleanPrefixClean or "AI"
    local locator = _G.AI_GetLocator()
    if locator and locator:has("llm_remember") then
        local remember = locator:get("llm_remember")
        local botNick = self:GetSetting("Companion_Nick", "Бот")
        -- 🔥 Передаём ник игрока вместо SteamID
        local playerName = remember:GetSafePlayerName(ply)
        remember:AddMessage(playerName, "bot", text)
    end
    -- ДЛЯ ПРИВАТНЫХ СООБЩЕНИЙ ВСЕГДА ПОКАЗЫВАЕМ ИМЯ
    local receiverName
    if isPrivate then
        receiverName = ply:Nick() or "Игрок"
    else
        local showName = self.state:getPlayerSetting(steamID, "Show_Sender_Name", true)
        receiverName = showName and (ply:Nick() or "Игрок") or ""
    end

    self.utils:LogDebug("[AI LLM DEBUG] SendResponse: sender=" .. senderName .. " receiver=" .. receiverName .. " color=" .. tostring(prefixColor))

    local locator = _G.AI_GetLocator()
    if locator and locator:has("shared") then
        local shared = locator:get("shared")
        if isPrivate then
            shared:SendChatMessage(ply, text, prefixColor, senderName, receiverName, true)
        else
            shared:SendChatMessage(ply, text, prefixColor, senderName, receiverName, false)
        end
    else
        self.utils:LogDebug("[AI LLM DEBUG] SendResponse: shared НЕ найден!")
    end
end

-- ============================================================
-- 11. ХУК НА ЧАТ (PlayerSay)
-- ============================================================

function LLM:SetupChatHook()
    if not SERVER then return end

    hook.Add("PlayerSay", "AICompanion_LLMChat", function(ply, text, teamChat)
        if not self.utils or not self.utils:IsValid(ply) then return end
        if ply:IsBot() then return end
        if string.find(text, "^!") then return end
        if string.find(text, "^%[AI%]") then return end

        -- Всегда отвечаем:
        self:Ask(ply, text, false)

        return nil
    end)
end

-- ============================================================
-- 12. СЕТЕВЫЕ СООБЩЕНИЯ
-- ============================================================

function LLM:SetupNetMessages()
    if not SERVER then return end

    util.AddNetworkString("AI_LLM_Request")

    net.Receive("AI_LLM_Request", function(len, ply)
        if not self.utils or not self.utils:IsValid(ply) then return end

        local message = net.ReadString()
        local isPrivate = net.ReadBool()

        if not message or message == "" then return end

        self:Ask(ply, message, isPrivate)
    end)
end

-- ============================================================
-- 13. КОНСОЛЬНЫЕ КОМАНДЫ
-- ============================================================

function LLM:SetupCommands()
    if not SERVER then return end

	concommand.Add("ai_test_llm", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] Только администраторы!")
			return
		end

		local ip = self:GetSetting("LLM_IP", "127.0.0.1")
		local port = self:GetSetting("LLM_Port", 1234)
		local model = self:GetSetting("LLM_Model", "local-model")
		local url = "http://" .. ip .. ":" .. port

		self.utils:LogDebug("[AI TEST] ═══════════════════════════════════════════")
		self.utils:LogDebug("[AI TEST] ТЕКУЩИЕ НАСТРОЙКИ:")
		self.utils:LogDebug("[AI TEST]   IP: '" .. ip .. "'")
		self.utils:LogDebug("[AI TEST]   Port: " .. port)
		self.utils:LogDebug("[AI TEST]   Model: '" .. model .. "'")
		self.utils:LogDebug("[AI TEST]   URL: " .. url)
		self.utils:LogDebug("[AI TEST] ПРОВЕРКА ПОДКЛЮЧЕНИЯ К LLM")
		ply:ChatPrint("[AI] Проверка LLM (" .. url .. ")...")
		self.utils:LogDebug("[AI TEST] ═══════════════════════════════════════════")

		HTTP({
			url = url,
			method = "GET",
			timeout = 3,
			success = function(code, body)
				local msg = "LLM доступен! (HTTP " .. code .. ")"
				ply:ChatPrint("[AI] " .. msg)
				self.utils:LogDebug("[AI TEST] " .. msg)
				self.utils:LogDebug("[AI TEST] ═══════════════════════════════════════")
			end,
			failed = function(err)
				local msg = "LLM недоступен! Проверьте LM Studio на " .. ip .. ":" .. port
				ply:ChatPrint("[AI] " .. msg)
				self.utils:LogDebug("[AI TEST] " .. msg)
				self.utils:LogDebug("[AI TEST] ═══════════════════════════════════════")
			end
		})
	end)

    concommand.Add("ai_llm_history", function(ply)
        if not self.utils or not self.utils:IsValid(ply) then return end
        if not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end

        local hist = self:GetHistory(ply)
        self.utils:LogDebug(tostring("[AI] История сообщений для " .. ply:Nick() .. ":"))
        for i, msg in ipairs(hist) do
            -- print(string.format("  %d. [%s] %s", i, msg.role, msg.content))
        end
        self.utils:LogDebug("Всего: " .. #hist .. " сообщений")
    end)

    concommand.Add("ai_llm_clear", function(ply)
        if not self.utils or not self.utils:IsValid(ply) then return end
        if not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end

        self:ClearHistory(ply)
        ply:ChatPrint("[AI] История очищена")
    end)
end

-- ============================================================
-- 14. API ДЛЯ ДРУГИХ СЕРВИСОВ
-- ============================================================

function LLM:GetAPI()
    return {
        Ask = function(ply, message, isPrivate) return self:Ask(ply, message, isPrivate) end,
        AddHistory = function(ply, role, content) return self:AddHistory(ply, role, content) end,
        GetHistory = function(ply) return self:GetHistory(ply) end,
        ClearHistory = function(ply) return self:ClearHistory(ply) end,
        GetProvider = function(ply) return self:GetProvider(ply) end,
        GetProviders = function() return self:GetAvailableProviders() end,
        CreateProvider = function(type, config) return self:CreateProvider(type, config) end,
        GetContext = function(ply) return self:GetContextInfo(ply) end,
        BuildPrompt = function(ply) return self:BuildSystemPrompt(ply) end,
    }
end

-- ============================================================
-- 15. НЕТ ГЛОБАЛЬНЫХ ПЕРЕМЕННЫХ!
-- ============================================================
-- Все функции доступны только через локатор:
--   local locator = _G.AI_GetLocator()
--   local llm = locator:get("llm")
--   llm:Ask(ply, message, true)
-- ============================================================

-- ============================================================
-- 16. ВОЗВРАЩАЕМ МОДУЛЬ
-- ============================================================

return LLM
