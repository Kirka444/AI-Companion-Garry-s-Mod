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
function LLM:GetLocale()
	local locator = AICompanion.GetLocator()
	if locator and locator:has("locale") then
		return locator:get("locale")
	end
	return nil
end
function LLM:GetLocalized(key, ...)
	local locale = self:GetLocale()
	if locale and locale.Get then
		return locale:Get(key, ...)
	end
	return key
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
		return
	end
	content = tostring(content)
	local steamID = ply:SteamID64()
	self._history[steamID] = self._history[steamID] or {}
	local hist = self._history[steamID]
	if role == "user" and #hist > 0 and hist[#hist].role == "user" then
        hist[#hist].content = hist[#hist].content .. "\n" .. content
        hist[#hist].time = CurTime()
    else
        content = self.utils:CleanText(content, self:GetMaxMessageLength())
        table.insert(hist, { role = role, content = content, time = CurTime() })
    end
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
	if llmService.utils and llmService.utils.HTTPQueue then
		llmService.utils:HTTPQueue(params)
	else
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
	local ip = string.Trim(tostring(llmService:GetSetting("LLM_IP", "127.0.0.1")))
	local port = tonumber(string.Trim(tostring(llmService:GetSetting("LLM_Port", 1234))))
	if not port or port < 1 then port = 1234 end
	ip = string.gsub(ip, ":%d+$", "")
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

-- ==================== OPENROUTER ====================
local OpenRouter_LLM = {}
OpenRouter_LLM.__index = OpenRouter_LLM
setmetatable(OpenRouter_LLM, LLMProvider)

function OpenRouter_LLM:new(config, llmService)
    local defaults = {
        model = "meta-llama/llama-3.1-8b-instruct:free",
        endpoint = "https://openrouter.ai/api/v1/chat/completions"
    }
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.openrouter
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
    obj.name = "openrouter"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end

function OpenRouter_LLM:GetDisplayName()
    return "OpenRouter (Free Models)"
end

function OpenRouter_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ OpenRouter не установлен. Получите на openrouter.ai"
    end
    return true, "OK"
end

function OpenRouter_LLM:BuildRequest(messages, systemPrompt, userMessage)
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
        ["Authorization"] = "Bearer " .. self.config.api_key,
        ["HTTP-Referer"] = "https://gmod.one",
        ["X-Title"] = "GMod AI Companion"
    }
end

function OpenRouter_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа OpenRouter"
    end
    if data.error then
        local msg = data.error.message or "неизвестная ошибка"
        if data.error.code == 401 then
            return nil, "Неверный API ключ OpenRouter"
        elseif data.error.code == 402 then
            return nil, "Недостаточно кредитов OpenRouter"
        elseif data.error.code == 429 then
            return nil, "Превышен лимит запросов к OpenRouter"
        end
        return nil, "OpenRouter ошибка: " .. msg
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа OpenRouter"
    end
    return data.choices[1].message.content, nil
end

-- ==================== YANDEX GPT (Алиса) ====================
local YandexGPT_LLM = {}
YandexGPT_LLM.__index = YandexGPT_LLM
setmetatable(YandexGPT_LLM, LLMProvider)

function YandexGPT_LLM:new(config, llmService)
    local defaults = {
        model = "yandexgpt-lite",
        endpoint = "https://llm.api.cloud.yandex.net/foundationModels/v1"
    }
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.yandexgpt
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
    obj.name = "yandexgpt"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end

function YandexGPT_LLM:GetDisplayName()
    return "YandexGPT (Алиса)"
end

function YandexGPT_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "OAuth-токен Яндекс.Облака не установлен"
    end
    if not self.config.folder_id or self.config.folder_id == "" then
        return false, "Folder ID Яндекс.Облака не установлен"
    end
    return true, "OK"
end

function YandexGPT_LLM:BuildRequest(messages, systemPrompt, userMessage)
    local yandexMessages = {}
    if systemPrompt and systemPrompt ~= "" then
        table.insert(yandexMessages, {
            role = "system",
            text = systemPrompt
        })
    end
    for _, msg in ipairs(messages) do
        local role = "user"
        if msg.role == "assistant" then
            role = "assistant"
        elseif msg.role == "system" then
            role = "system"
        end
        table.insert(yandexMessages, {
            role = role,
            text = msg.content
        })
    end
    local body = {
        modelUri = "gpt://" .. self.config.folder_id .. "/" .. (self.config.model or self.defaultModel),
        completionOptions = {
            stream = false,
            temperature = self.llmService:GetTemperature(),
            maxTokens = tostring(self.llmService:GetMaxTokens())
        },
        messages = yandexMessages
    }
    return body, {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. self.config.api_key,
        ["x-folder-id"] = self.config.folder_id
    }
end

function YandexGPT_LLM:GetEndpoint()
    local endpoint = self.config and self.config.endpoint or self.defaultEndpoint
    if endpoint then
        endpoint = string.Trim(endpoint)
        return endpoint .. "/completion"
    end
    return nil
end

function YandexGPT_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа YandexGPT"
    end
    if data.error then
        local msg = data.error.message or "неизвестная ошибка"
        if data.error.code == 16 then
            return nil, "Ошибка аутентификации Яндекс.Облака. Проверьте OAuth-токен"
        elseif data.error.code == 7 then
            return nil, "Недостаточно прав. Проверьте Folder ID"
        end
        return nil, "YandexGPT ошибка: " .. msg
    end
    if not data.result or not data.result.alternatives or not data.result.alternatives[1] then
        return nil, "Неверный формат ответа YandexGPT"
    end
    local alternative = data.result.alternatives[1]
    if not alternative.message or not alternative.message.text then
        return nil, "Пустой ответ от YandexGPT"
    end
    return alternative.message.text, nil
end

-- ==================== GIGACHAT (Сбер) ====================
local GigaChat_LLM = {}
GigaChat_LLM.__index = GigaChat_LLM
setmetatable(GigaChat_LLM, LLMProvider)

function GigaChat_LLM:new(config, llmService)
    local defaults = {
        model = "GigaChat",
        endpoint = "https://gigachat.devices.sberbank.ru/api/v1/chat/completions"
    }
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.gigachat
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
    obj.name = "gigachat"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    obj._accessToken = nil
    obj._tokenExpiry = 0
    setmetatable(obj, self)
    return obj
end

function GigaChat_LLM:GetDisplayName()
    return "GigaChat (Сбер)"
end

function GigaChat_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "Client Secret GigaChat не установлен"
    end
    if not self.config.client_id or self.config.client_id == "" then
        return false, "Client ID GigaChat не установлен"
    end
    return true, "OK"
end

function GigaChat_LLM:GetAccessToken(callback)
    if self._accessToken and CurTime() < self._tokenExpiry then
        callback(self._accessToken, nil)
        return
    end
    local authString = "Basic " .. util.Base64Encode(self.config.client_id .. ":" .. self.config.api_key)
    HTTP({
        url = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = authString,
            ["RqUID"] = util.CRC(tostring(CurTime()) .. tostring(math.random()))
        },
        body = "scope=" .. (self.config.scope or "GIGACHAT_API_PERS"),
        timeout = 10,
        success = function(code, body)
            if code ~= 200 then
                callback(nil, "Ошибка получения токена GigaChat: HTTP " .. code)
                return
            end
            local ok, data = pcall(util.JSONToTable, body)
            if not ok or not data or not data.access_token then
                callback(nil, "Неверный ответ при получении токена GigaChat")
                return
            end
            self._accessToken = data.access_token
            self._tokenExpiry = CurTime() + (data.expires_at or 1800) - 60
            callback(self._accessToken, nil)
        end,
        failed = function(err)
            callback(nil, "Ошибка сети при получении токена GigaChat: " .. tostring(err))
        end
    })
end

function GigaChat_LLM:BuildRequest(messages, systemPrompt, userMessage)
    local gigachatMessages = {}
    if systemPrompt and systemPrompt ~= "" then
        table.insert(gigachatMessages, {
            role = "system",
            content = systemPrompt
        })
    end
    for _, msg in ipairs(messages) do
        table.insert(gigachatMessages, {
            role = msg.role == "assistant" and "assistant" or "user",
            content = msg.content
        })
    end
    local body = {
        model = self.config.model or self.defaultModel,
        messages = gigachatMessages,
        temperature = self.llmService:GetTemperature(),
        max_tokens = self.llmService:GetMaxTokens(),
        stream = false
    }
    return body, {
        ["Content-Type"] = "application/json"
    }
end

function GigaChat_LLM:Request(ply, messages, systemPrompt, userMessage, callback, isPrivate)
    local self_ref = self
    self:GetAccessToken(function(token, err)
        if not token then
            if callback then callback(nil, err) end
            return
        end
        local body, headers = self_ref:BuildRequest(messages, systemPrompt, userMessage)
        headers["Authorization"] = "Bearer " .. token
        local jsonBody = util.TableToJSON(body)
        if not jsonBody then
            if callback then callback(nil, "Failed to serialize request") end
            return
        end
        local llmService = self_ref.llmService
        llmService._requestCounter = llmService._requestCounter + 1
        local requestID = llmService._requestCounter
        local timerID = "LLM_timeout_" .. tostring(requestID)
        if SERVER then
            timer.Create(timerID, llmService:GetLLMTimeout(), 1, function()
                if callback then callback(nil, "Timeout") end
            end)
        end
        local params = {
            url = self_ref:GetEndpoint(),
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
                local response, parseErr = self_ref:ParseResponse(responseBody)
                if callback then callback(response, parseErr) end
            end,
            error = function(err)
                timer.Remove(timerID)
                if callback then callback(nil, tostring(err)) end
            end
        }
        if llmService.utils and llmService.utils.HTTPQueue then
            llmService.utils:HTTPQueue(params)
        else
            HTTP(params)
        end
    end)
end

function GigaChat_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа GigaChat"
    end
    if data.error then
        local msg = data.error.message or "неизвестная ошибка"
        if data.error.code == "invalid_token" then
            return nil, "Недействительный токен GigaChat"
        end
        return nil, "GigaChat ошибка: " .. msg
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа GigaChat"
    end
    return data.choices[1].message.content, nil
end

-- ==================== MISTRAL AI ====================
local Mistral_LLM = {}
Mistral_LLM.__index = Mistral_LLM
setmetatable(Mistral_LLM, LLMProvider)

function Mistral_LLM:new(config, llmService)
    local defaults = {
        model = "mistral-small-latest",
        endpoint = "https://api.mistral.ai/v1/chat/completions"
    }
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.mistral
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
    obj.name = "mistral"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end

function Mistral_LLM:GetDisplayName()
    return "Mistral AI"
end

function Mistral_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ Mistral AI не установлен"
    end
    return true, "OK"
end

function Mistral_LLM:BuildRequest(messages, systemPrompt, userMessage)
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

function Mistral_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа Mistral"
    end
    if data.error then
        local msg = data.error.message or "неизвестная ошибка"
        if data.error.code == 401 then
            return nil, "Неверный API ключ Mistral"
        elseif data.error.code == 429 then
            return nil, "Превышен лимит запросов к Mistral"
        end
        return nil, "Mistral ошибка: " .. msg
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа Mistral"
    end
    return data.choices[1].message.content, nil
end

-- ==================== TOGETHER AI ====================
local Together_LLM = {}
Together_LLM.__index = Together_LLM
setmetatable(Together_LLM, LLMProvider)

function Together_LLM:new(config, llmService)
    local defaults = {
        model = "meta-llama/Llama-3.2-3B-Instruct-Turbo",
        endpoint = "https://api.together.xyz/v1/chat/completions"
    }
    if llmService.config and llmService.config:get("Providers") then
        local d = llmService.config:get("Providers").LLM.Defaults.together
        if d then defaults = d end
    end
    local obj = LLMProvider:new(config, llmService)
    obj.name = "together"
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = defaults.endpoint
    setmetatable(obj, self)
    return obj
end

function Together_LLM:GetDisplayName()
    return "Together AI"
end

function Together_LLM:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ Together AI не установлен. Получите на together.ai"
    end
    return true, "OK"
end

function Together_LLM:BuildRequest(messages, systemPrompt, userMessage)
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

function Together_LLM:ParseResponse(body)
    local ok, data = pcall(util.JSONToTable, body)
    if not ok or not data then
        return nil, "Ошибка парсинга ответа Together AI"
    end
    if data.error then
        local msg = data.error.message or "неизвестная ошибка"
        if data.error.code == "invalid_api_key" then
            return nil, "Неверный API ключ Together AI"
        elseif data.error.code == "rate_limit_exceeded" then
            return nil, "Превышен лимит запросов к Together AI"
        elseif data.error.code == "insufficient_credits" then
            return nil, "Недостаточно кредитов Together AI"
        end
        return nil, "Together AI ошибка: " .. msg
    end
    if not data.choices or not data.choices[1] or not data.choices[1].message then
        return nil, "Неверный формат ответа Together AI"
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
	openrouter = OpenRouter_LLM,
	yandexgpt = YandexGPT_LLM,
	gigachat = GigaChat_LLM,
	mistral = Mistral_LLM,
	together = Together_LLM,
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
			{ id = "openrouter", name = "OpenRouter (Free)", needsKey = true },
			{ id = "yandexgpt", name = "YandexGPT (Алиса)", needsKey = true, extraFields = { "folder_id" } },
			{ id = "gigachat", name = "GigaChat (Сбер)", needsKey = true, extraFields = { "client_id" } },
			{ id = "mistral", name = "Mistral AI", needsKey = true },
			{ id = "together", name = "Together AI", needsKey = true },
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
			folder_id = string.Trim(self:GetSetting("LLM_Folder_ID", "")),
			client_id = string.Trim(self:GetSetting("LLM_Client_ID", "")),
			scope = string.Trim(self:GetSetting("LLM_Scope", "GIGACHAT_API_PERS")),
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
			playerName = self:GetLocalized("unknown"),
			playerHealth = "?",
			playerMaxHealth = "?",
			playerArmor = "?",
			playerModel = self:GetLocalized("unknown"),
			playerAlive = false,
			playerStatus = self:GetLocalized("unknown"),
			playerWeapon = self:GetLocalized("unknown"),
			mapName = self:GetLocalized("unknown"),
			serverTime = os.date("%H:%M"),
			playerCount = 0,
			humanCount = 0,
			botCount = 0,
			npcCount = 0,
			npcTypes = {},
			botModel = self:GetLocalized("unknown"),
			botHealth = "?",
			botMaxHealth = "?",
			botArmor = "?",
			botTask = self:GetLocalized("unknown"),
			botAlive = false,
			botWeapon = self:GetLocalized("unknown"),
			botState = self:GetLocalized("unknown"),
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
	context.playerModel = ply:GetModel() or self:GetLocalized("unknown")
	context.playerAlive = ply:Alive()
	if ply:InVehicle() then
		local veh = ply:GetVehicle()
		local vehName = self.utils:IsValid(veh)
			and (veh:GetClass() or self:GetLocalized("vehicle_enter_driver"))
			or self:GetLocalized("vehicle_enter_driver")
		local isDriver = false
		if self.utils:IsValid(veh) and veh.GetDriver then
			isDriver = veh:GetDriver() == ply
		end
		local statusKey = isDriver and "vehicle_enter_driver" or "vehicle_enter_passenger"
		context.playerStatus = self:GetLocalized(statusKey) .. " (" .. vehName .. ")"
	else
		context.playerStatus = self:GetLocalized("status_on_foot")
	end
	local weapon = ply:GetActiveWeapon()
	context.playerWeapon = self.utils:IsValid(weapon) and weapon:GetClass() or self:GetLocalized("status_no_weapon")
	context.mapName = game.GetMap() or self:GetLocalized("unknown")
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
	local locator = AICompanion.GetLocator()
	if locator and locator:has("botmanager") then
		bot = locator:get("botmanager"):GetBotByOwner(ply)
	end
	if self.utils:IsValid(bot) then
		context.botModel = bot:GetModel() or self:GetLocalized("unknown")
		context.botHealth = math.Round(bot:Health())
		context.botMaxHealth = math.Round(bot:GetMaxHealth())
		context.botArmor = math.Round(bot:Armor())
		context.botTask = bot:GetNWString("CurrentTask", "") or "idle"
		context.botAlive = bot:Alive()
		context.botState = bot:GetNWString("BotState", "idle")
		context.botWeapon = self:GetLocalized("status_no_weapon")
		local aw = bot:GetActiveWeapon()
		if self.utils:IsValid(aw) then context.botWeapon = aw:GetClass() end
		local dist = bot:GetPos():Distance(ply:GetPos())
		context.botDistToPlayer = math.Round(dist)
		local target = bot:GetNWEntity("CombatTarget", nil)
		if IsValid(target) then
			context.botCombatTarget = target:GetClass() or target:Nick() or self:GetLocalized("unknown")
			context.botCombatTargetType = target:IsPlayer() and "player" or "npc"
		else
			context.botCombatTarget = nil
			context.botCombatTargetType = nil
		end
	else
		context.botModel = self:GetLocalized("unknown")
		context.botHealth = "?"
		context.botMaxHealth = "?"
		context.botArmor = "?"
		context.botTask = self:GetLocalized("unknown")
		context.botAlive = false
		context.botWeapon = self:GetLocalized("unknown")
		context.botState = self:GetLocalized("unknown")
		context.botDistToPlayer = "?"
		context.botCombatTarget = nil
		context.botCombatTargetType = nil
	end
	return context
end
function LLM:GetCustomPrompt(ply)
	if not self.utils or not self.utils:IsValid(ply) then return nil, false end
	local steamID = ply:SteamID64()

	-- Проверяем разрешение для не-админов
	local isAdmin = ply:IsAdmin()
	local allowCustom = self:GetSetting("Allow_Custom_Prompts", true)
	if not isAdmin and not allowCustom then
		return nil, false
	end

	-- Читаем ТОЛЬКО персональные настройки
	local customEnabled = self.state:getPlayerSetting(steamID, "Custom_Prompt_Enabled", false)
	if not customEnabled then return nil, false end

	local customText = self.state:getPlayerSetting(steamID, "Custom_Prompt_Text", "")
	if customText == "" then return nil, false end

	return customText, true
end
function LLM:BuildSystemPrompt(ply)
    if not self.utils or not self.utils:IsValid(ply) then
        return "Ты — AI Компаньон в Garry's Mod. Отвечай кратко. Обращайся на 'ты'."
    end

    -- === КАСТОМНЫЙ ПРОМПТ ===
    local customText, hasCustom = self:GetCustomPrompt(ply)
    if hasCustom and customText and customText ~= "" then
        local prompt = customText

        -- Добавляем контекст мира (урезанный)
        local ctx = self:GetContextInfo(ply)
        local botNick = self:GetLocalized("ai_name")
        if self.state then
            local steamID = ply:SteamID64()
            botNick = self.state:getPlayerSetting(steamID, "Companion_Nick", nil)
                or self.state:getSetting("Companion_Nick")
                or self:GetLocalized("ai_name")
        end

        local worldContext = string.format([[
=== КОНТЕКСТ МИРА ===
Игрок: %s
Здоровье игрока: %s/%s HP, Броня: %s
Статус игрока: %s
Оружие игрока: %s
Карта: %s, Время: %s
Игроков: %s, NPC: %s
--- Твой компаньон ---
Имя: %s
Здоровье: %s/%s HP, Броня: %s
Состояние: %s
Оружие: %s
Расстояние до игрока: %s м
]],
            ctx.playerName or ply:Nick(),
            ctx.playerHealth or "?", ctx.playerMaxHealth or "?",
            ctx.playerArmor or "0",
            ctx.playerStatus or self:GetLocalized("unknown"),
            ctx.playerWeapon or self:GetLocalized("status_no_weapon"),
            ctx.mapName or self:GetLocalized("unknown"),
            ctx.serverTime or os.date("%H:%M"),
            ctx.playerCount or 0, ctx.npcCount or 0,
            botNick,
            ctx.botHealth or "?", ctx.botMaxHealth or "?",
            ctx.botArmor or "0",
            ctx.botState or "idle",
            ctx.botWeapon or self:GetLocalized("status_no_weapon"),
            ctx.botDistToPlayer or "?"
        )

        prompt = prompt .. "\n\n" .. worldContext

        -- Контекст памяти
        local locator = AICompanion.GetLocator()
        if locator and locator:has("llm_remember") then
            local remember = locator:get("llm_remember")
            local memoryContext = remember:GetMemoryContext(ply)
            if memoryContext and memoryContext ~= "" then
                prompt = prompt .. "\n\n" .. memoryContext
            end
        end

        return prompt
    end
	-- === СТАНДАРТНЫЙ ПРОМПТ (если кастомный не активен) ===
	local ctx = self:GetContextInfo(ply)
	local botNick = self:GetLocalized("ai_name")
	if self.state then
		if self.utils and self.utils:IsValid(ply) then
			local steamID = ply:SteamID64()
			botNick = self.state:getPlayerSetting(steamID, "Companion_Nick", nil)
				or self.state:getSetting("Companion_Nick")
				or self:GetLocalized("ai_name")
		else
			botNick = self.state:getSetting("Companion_Nick") or self:GetLocalized("ai_name")
		end
	end
	local playerName = ctx.playerName or ply:Nick() or "Игрок"
	local currentTime = os.date("%H:%M")
	local prompt = [[
=== РОЛЬ ===
Ты — ]] .. botNick .. [[, AI-компаньон в игре Garry's Mod. Ты помогаешь игроку ]] .. playerName .. [[ в игровом мире.
=== ИНФОРМАЦИЯ ОБ ИГРОКЕ ===
Ник: ]] .. playerName .. [[
Здоровье: ]] .. (ctx.playerHealth or "?") .. [[/]] .. (ctx.playerMaxHealth or "?") .. [[ HP
Броня: ]] .. (ctx.playerArmor or "0") .. [[
Статус: ]] .. (ctx.playerStatus or self:GetLocalized("unknown")) .. [[
Оружие: ]] .. (ctx.playerWeapon or self:GetLocalized("status_no_weapon")) .. [[
=== ИНФОРМАЦИЯ О МИРЕ ===
Карта: ]] .. (ctx.mapName or self:GetLocalized("unknown")) .. [[
Время: ]] .. currentTime .. [[
Игроков на сервере: ]] .. (ctx.playerCount or 0) .. [[
NPC на карте: ]] .. (ctx.npcCount or 0) .. [[
=== ТВОИ ХАРАКТЕРИСТИКИ ===
Имя: ]] .. botNick .. [[
Здоровье: ]] .. (ctx.botHealth or "?") .. [[/]] .. (ctx.botMaxHealth or "?") .. [[ HP
Броня: ]] .. (ctx.botArmor or "0") .. [[
Состояние: ]] .. (ctx.botState or "idle") .. [[
Оружие: ]] .. (ctx.botWeapon or self:GetLocalized("status_no_weapon")) .. [[
Расстояние до игрока: ]] .. (ctx.botDistToPlayer or "?") .. [[ м
=== КОМАНДЫ КОМПАНЬОНА ===
Ты можешь выполнять команды, начиная строку с "!companion ".
Команды выполняются ТОЛЬКО когда игрок явно просит действие.
НИКОГДА не добавляй команды без просьбы игрока.
!companion follow — ]] .. self:GetLocalized("bot_following") .. [[
!companion stop — ]] .. self:GetLocalized("bot_stopped") .. [[
!companion point — ]] .. self:GetLocalized("bot_pointing") .. [[
!companion sit — ]] .. self:GetLocalized("bot_sitting") .. [[
!companion standup — ]] .. self:GetLocalized("bot_standup") .. [[
!companion attack — ]] .. self:GetLocalized("bot_attacking") .. [[
!companion spawn <тип> — ]] .. self:GetLocalized("log_llm_actions_spawn_success") .. [[
=== ПРАВИЛА ===
1. Отвечай кратко: 1-2 предложения максимум.
2. Обращайся на "ты".
3. Если игрок просит ДЕЙСТВИЕ — ОБЯЗАТЕЛЬНО добавь команду !companion с новой строки ПОСЛЕ текста ответа.
4. На обычные вопросы отвечай БЕЗ команд.
5. НИКОГДА не предлагай команды первым и не спрашивай "выполнить?". Просто делай.
6. При атаке игрока используй его точный ник.
=== КОНТЕКСТ ПАМЯТИ ===
]]
	local locator = AICompanion.GetLocator()
	if locator and locator:has("llm_remember") then
		local remember = locator:get("llm_remember")
		local memoryContext = remember:GetMemoryContext(ply)
		if memoryContext and memoryContext ~= "" then
			prompt = prompt .. "\n" .. memoryContext .. "\n"
		end
	end
	return prompt
end
function LLM:Ask(ply, message, isPrivate, callback)
	if ply._llm_processing then
		if callback then callback(nil, self:GetLocalized("llm_error")) end
		return
	end
	ply._llm_processing = true
	local function cleanup()
		if IsValid(ply) then
			ply._llm_processing = false
		end
	end
	if not self.utils or not self.utils:IsValid(ply) then
		cleanup()
		if callback then callback(nil, "Player invalid") end
		return
	end
	if not self:GetState("LLM_Enabled", true) then
		local msg = self:GetLocalized("llm_disabled")
		self:SendThinkingMessage(ply, msg, isPrivate)
		cleanup()
		if callback then callback(nil, msg) end
		return
	end
	message = tostring(message or "")
	message = self.utils:CleanText(message, self:GetMaxMessageLength())
	if message == "" then
		cleanup()
		if callback then callback(nil, self:GetLocalized("cmd_empty_message")) end
		return
	end
	local provider = self:GetProvider(ply)
	if not provider then
		local msg = self:GetLocalized("llm_provider_not_found")
		self:SendThinkingMessage(ply, msg, isPrivate)
		cleanup()
		if callback then callback(nil, msg) end
		return
	end
	local valid, err = provider:ValidateConfig()
	if not valid then
		local msg = self:GetLocalized("llm_provider_error"):format(err)
		self:SendThinkingMessage(ply, msg, isPrivate)
		cleanup()
		if callback then callback(nil, err) end
		return
	end
	self:SendThinkingMessage(ply, self:GetLocalized("llm_thinking"), isPrivate)
	self:AddHistory(ply, "user", message)
	local locator = AICompanion.GetLocator()
	if locator and locator:has("llm_remember") then
		local remember = locator:get("llm_remember")
		local playerName = remember:GetSafePlayerName(ply)
		remember:AddMessage(playerName, "player", message)
	end
	local history = self:GetHistory(ply)
	local systemPrompt = self:BuildSystemPrompt(ply)
	local function safeCallback(response, err)
		local cleanupCalled = false
		if cleanupCalled then return end
		cleanupCalled = true
		cleanup()
		if not self.utils or not self.utils:IsValid(ply) then
			if callback then callback(nil, "Player disconnected") end
			return
		end
		if err then
			local msg = self:GetLocalized("llm_error") .. " " .. err
			self:SendThinkingMessage(ply, msg, isPrivate)
			if callback then callback(nil, err) end
			return
		end
		if not response or response == "" then
			self:SendThinkingMessage(ply, self:GetLocalized("llm_empty"), isPrivate)
			if callback then callback(nil, self:GetLocalized("llm_empty")) end
			return
		end
		response = self.utils:CleanText(response, self:GetMaxMessageLength())
		if self.ProcessResponse then
			local processed = LLM.ProcessResponse(self, ply, response)
			response = processed
		end
		if not response or response == "" then
			self:SendThinkingMessage(ply, self:GetLocalized("llm_empty"), isPrivate)
			if callback then callback(nil, self:GetLocalized("llm_empty")) end
			return
		end
		self:AddHistory(ply, "assistant", response)
		self:SendResponse(ply, response, isPrivate)
		if self:GetState("TTS_Enabled", false) then
			if locator then
				if locator:has("tts") then
					local tts = locator:get("tts")
					if tts and tts.Generate then
						tts:Generate(ply, response)
					end
				end
			end
		end
		if callback then callback(response, nil) end
	end
	provider:Request(ply, history, systemPrompt, message, safeCallback, isPrivate)
	timer.Simple(300, function()
		if IsValid(ply) and ply._llm_processing then
			self.utils:LogWarn("LLM", "Таймаут LLM запроса для %s, принудительный сброс флага", ply:Nick())
			ply._llm_processing = false
		end
	end)
end
function LLM:ProcessResponse(ply, response)
	if not response then return response end
	local locator = AICompanion.GetLocator()
	if locator and locator:has("llm_actions") then
		local llm_actions = locator:get("llm_actions")
		return llm_actions:ProcessResponse(ply, response)
	end
	local lines = {}
	for line in string.gmatch(response, "[^\r\n]+") do
		table.insert(lines, line)
	end
	local cleanResponse = {}
	local commands = {}
	for _, line in ipairs(lines) do
		local cmd, arg = string.match(line, "^%s*!companion%s+([%w_%-]+)%s*(.-)%s*$")
		if cmd then
			table.insert(commands, { cmd = cmd, arg = string.Trim(arg or "") })
		else
			table.insert(cleanResponse, line)
		end
	end
	for _, cmdData in ipairs(commands) do
		self:ExecuteCommand(ply, cmdData.cmd, cmdData.arg)
	end
	return table.concat(cleanResponse, "\n")
end
function LLM:ExecuteCommand(ply, cmd)
	if not self.utils or not self.utils:IsValid(ply) then return end
	local locator = AICompanion.GetLocator()
	if locator and locator:has("llm_actions") then
		local llm_actions = locator:get("llm_actions")
		local args = string.Explode(" ", cmd)
		local command = args[1] or ""
		local arg = args[2] or ""
		llm_actions:ExecuteCommand(ply, command, arg)
	else
		local locator = AICompanion.GetLocator()
		if not locator or not locator:has("botmanager") then return end
		local bot = locator:get("botmanager"):GetBotByOwner(ply)
		if not self.utils:IsValid(bot) then return end
		local args = string.Explode(" ", cmd)
		local action = args[1] or ""
		if action == "follow" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("bot_following_you"),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		elseif action == "stop" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("bot_stopped"),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		elseif action == "sit" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("bot_sitting"),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		elseif action == "standup" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("bot_standup"),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		elseif action == "point" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("bot_pointing"),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		elseif action == "attack" and args[2] then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("bot_attacking"):format(args[2]),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		elseif action == "spawn" and args[2] then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("log_llm_actions_spawn_success"):format(args[2]),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		elseif action == "status" then
			if locator:has("shared") then
				locator:get("shared"):SendChatMessage(ply,
					self:GetLocalized("cmd_help_status"),
					Color(255, 200, 0),
					"AI",
					ply:Nick(),
					false)
			end
		end
	end
end
function LLM:SendThinkingMessage(ply, text, isPrivate)
	if not self.utils or not self.utils:IsValid(ply) then
		return
	end
	local steamID = ply:SteamID64()
	local cleanPrefix = self.state:getPlayerSetting(steamID, "Prefix_Text", "[AI]")
	if not cleanPrefix or cleanPrefix == "" then cleanPrefix = "[AI]" end
	local cleanPrefixClean = string.gsub(cleanPrefix, "^%[", "")
	cleanPrefixClean = string.gsub(cleanPrefixClean, "%]$", "")
	if cleanPrefixClean == "" then cleanPrefixClean = "AI" end
	local senderName = cleanPrefixClean or "AI"
	local receiverName
	if isPrivate then
		receiverName = ply:Nick() or "Игрок"
	else
		local showName = self.state:getPlayerSetting(steamID, "Show_Sender_Name", true)
		if showName == nil then
			showName = self.state:getPlayerSetting(steamID, "show_sender_name", true)
		end
		receiverName = showName and (ply:Nick() or "Игрок") or ""
	end
	local prefixColor
	local rainbow = self.state:getPlayerSetting(steamID, "Prefix_Rainbow", false)
	if rainbow then
		local hue = (CurTime() * 120) % 360
		prefixColor = HSVToColor(hue, 1, 1)
	else
		prefixColor = Color(self.state:getPlayerSetting(steamID, "Prefix_Color_R", 255),
			self.state:getPlayerSetting(steamID, "Prefix_Color_G", 200),
			self.state:getPlayerSetting(steamID, "Prefix_Color_B", 0))
	end
	local locator = AICompanion.GetLocator()
	if locator and locator:has("shared") then
		local shared = locator:get("shared")
		shared:SendChatMessage(ply, text, prefixColor, senderName, receiverName, isPrivate)
	end
end
function LLM:SendResponse(ply, text, isPrivate)
	if not text then
		return
	end
	if not self.utils or not self.utils:IsValid(ply) then
		return
	end
	local steamID = ply:SteamID64()
	local cleanPrefix = self.state:getPlayerSetting(steamID, "Prefix_Text", "[AI]")
	if not cleanPrefix or cleanPrefix == "" then cleanPrefix = "[AI]" end
	local cleanPrefixClean = string.gsub(cleanPrefix, "^%[", "")
	cleanPrefixClean = string.gsub(cleanPrefixClean, "%]$", "")
	if cleanPrefixClean == "" then cleanPrefixClean = "AI" end
	local prefixColor
	local rainbow = self.state:getPlayerSetting(steamID, "Prefix_Rainbow", false)
	if rainbow then
		local hue = (CurTime() * 120) % 360
		prefixColor = HSVToColor(hue, 1, 1)
	else
		prefixColor = Color(self.state:getPlayerSetting(steamID, "Prefix_Color_R", 255),
			self.state:getPlayerSetting(steamID, "Prefix_Color_G", 200),
			self.state:getPlayerSetting(steamID, "Prefix_Color_B", 0))
	end
	local senderName = cleanPrefixClean or "AI"
	local receiverName
	if isPrivate then
		receiverName = ply:Nick() or "Игрок"
	else
		local showName = self.state:getPlayerSetting(steamID, "Show_Sender_Name", true)
		if showName == nil then
			showName = self.state:getPlayerSetting(steamID, "show_sender_name", true)
		end
		receiverName = showName and (ply:Nick() or "Игрок") or ""
	end
	local locator = AICompanion.GetLocator()
	if locator and locator:has("shared") then
		local shared = locator:get("shared")
		shared:SendChatMessage(ply, text, prefixColor, senderName, receiverName, isPrivate)
	end
end
function LLM:SetupChatHook()
	if not SERVER then return end
	hook.Add("PlayerSay", "gmod.one/ai-companion/llm-chat", function(ply, text, teamChat)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if ply:IsBot() then return end
		local llmEnabled = self:GetState("LLM_Enabled", true)
		local llmMode = self:GetSetting("LLM_Mode", "local")
		if not llmEnabled or llmMode == "disabled" then
			return nil
		end
		if string.find(text, "^!") then return end
		if string.find(text, "^%[AI%]") then return end
		self:Ask(ply, text, false)
		return nil
	end)
end
function LLM:SetupNetMessages()
    if not SERVER then return end
    util.AddNetworkString("gmod.one/ai-companion/llm-request")
    net.Receive("gmod.one/ai-companion/llm-request", function(len, ply)
        local llmEnabled = self:GetState("LLM_Enabled", true)
        local llmMode = self:GetSetting("LLM_Mode", "local")
        if not llmEnabled or llmMode == "disabled" then
            return
        end
        local message = net.ReadString()
        local isPrivate = net.ReadBool()
        if not message or message == "" then return end
        
        if isPrivate then
            local steamID = ply:SteamID64()
            local cleanPrefix = self.state:getPlayerSetting(steamID, "Prefix_Text", "[AI]")
            local cleanPrefixClean = string.gsub(cleanPrefix, "^%[", "")
            cleanPrefixClean = string.gsub(cleanPrefixClean, "%]$", "")
            if cleanPrefixClean == "" then cleanPrefixClean = "AI" end
            
            local locator = AICompanion.GetLocator()
            if locator and locator:has("shared") then
                local shared = locator:get("shared")
                -- Отправляем как [Игрок -> AI]
                shared:SendChatMessage(ply, message, Color(255, 255, 255), ply:Nick(), cleanPrefixClean, true)
            end
        end
        
        self:Ask(ply, message, isPrivate)
    end)
end
function LLM:SetupCommands()
	if not SERVER then return end
	concommand.Add("ai_test_llm", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("settings_admin_only"))
			return
		end
		local ip = self:GetSetting("LLM_IP", "127.0.0.1")
		local port = self:GetSetting("LLM_Port", 1234)
		local model = self:GetSetting("LLM_Model", "local-model")
		ip = string.gsub(tostring(ip), ":%d+$", "")
		local url = "http://" .. ip .. ":" .. port
		ply:ChatPrint("[AI] " .. self:GetLocalized("llm_testing"):format(url))
		HTTP({
			url = url,
			method = "GET",
			timeout = 3,
			success = function(code, body)
				local msg = self:GetLocalized("llm_test_success") .. " (HTTP " .. code .. ")"
				ply:ChatPrint("[AI] " .. msg)
			end,
			failed = function(err)
				local msg = self:GetLocalized("llm_test_fail"):format("Проверьте LM Studio на " .. ip .. ":" .. port)
				ply:ChatPrint("[AI] " .. msg)
			end
		})
	end)
	concommand.Add("ai_llm_history", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("settings_admin_only"))
			return
		end
		local hist = self:GetHistory(ply)
		for i, msg in ipairs(hist) do
		end
	end)
	concommand.Add("ai_llm_clear", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] " .. self:GetLocalized("settings_admin_only"))
			return
		end
		self:ClearHistory(ply)
		ply:ChatPrint("[AI] История очищена")
	end)
end
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
return LLM