-- Text-to-speech provider integration and workflow handling.

local TTS = {}
local L_cache = {}
local function L(key, ...)
	local cached = L_cache[key]
	if cached and select("#", ...) == 0 then
		return cached
	end

	local locator = AICompanion and AICompanion.GetLocator and AICompanion.GetLocator()
	if locator and locator:has("locale") then
		local locale = locator:get("locale")
		if locale and type(locale.Get) == "function" then
			local str = locale:Get(key)

			if select("#", ...) == 0 then
				L_cache[key] = str
			end

			if select("#", ...) > 0 then
				local ok, result = pcall(string.format, str, ...)
				if ok then
					return result
				end
				return str
			end

			return str
		end
	end

	if select("#", ...) > 0 then
		local ok, result = pcall(string.format, key, ...)
		if ok then
			return result
		end
	end

	return key
end
function TTS:new(utils, config, state)
	local obj = {
		utils = utils,
		config = config,
		state = state,
		_initialized = false,
		_activeRequests = 0,
		_audioCache = nil,
	}
	setmetatable(obj, self)
	self.__index = self
	if utils and utils.LogDebug then
		utils:LogDebug("[TTS] 🔧 Создание нового экземпляра TTS")
	end
	return obj
end
function TTS:init()
	if self._initialized then
		return
	end
	local cacheSize = 50
	local cacheTTL = 300
	if self.config then
		local cacheConfig = self.config:get("Cache")
		if cacheConfig and cacheConfig.TTS then
			cacheSize = cacheConfig.TTS.Size or 50
			cacheTTL = cacheConfig.TTS.TTL or 300
		end
	end
	if self.utils and self.utils.CreateCache then
		self._audioCache = self.utils.CreateCache(cacheSize, cacheTTL)
	else
	end
	if SERVER then
		self:SetupNetMessages()
		self:SetupCommands()
		self:SetupWorkflowCommands()
	else
	end
	self._initialized = true
	if self.utils then
		self.utils.LogInfo("TTS", L("tts_service_initialized"))
	end
end
function TTS:GetSetting(key, default)
	if self.state then
		local val = self.state:getSetting(key)
		if val ~= nil then
			return val
		end
	end
	return default
end
function TTS:GetState(key, default)
	if self.state then
		local val = self.state:getState(key)
		if val ~= nil then
			return val
		end
	end
	return default
end
function TTS:GetMaxConcurrent()
	if self.config and self.config:get("LLM") then
		local val = self.config:get("LLM").MaxTTSConcurrent or 3
		return val
	end
	return 3
end
function TTS:GetDefaultTimeout()
	if self.config and self.config:get("HTTP") then
		local val = self.config:get("HTTP").DefaultTimeout or 30
		return val
	end
	return 30
end
function TTS:GetCacheTTL()
	if self.config and self.config:get("Cache") and self.config:get("Cache").TTS then
		local val = self.config:get("Cache").TTS.TTL or 300
		return val
	end
	return 300
end
function TTS:GetTTSURL()
	local ip = self:GetSetting("TTS_IP", "127.0.0.1")
	local port = self:GetSetting("TTS_Port", 8188)
	ip = string.gsub(tostring(ip), ":%d+$", "")
	local url = string.format("http://%s:%d", ip, port)
	return url
end
local TTSProvider = {}
TTSProvider.__index = TTSProvider
function TTSProvider:new(config, ttsService)
	local obj = {
		config = config or {},
		name = "unknown",
		enabled = true,
		ttsService = ttsService,
		utils = ttsService and ttsService.utils,
	}
	setmetatable(obj, self)
	return obj
end
function TTSProvider:ValidateConfig()
	return true, "OK"
end
function TTSProvider:GetDisplayName()
	return self.name
end
function TTSProvider:GetEndpoint()
	return self.config.endpoint or self.defaultEndpoint
end
function TTSProvider:GetCached(text)
	if not self.ttsService or not self.ttsService._audioCache then
		return nil
	end
	local key = self.ttsService.utils:Hash(text)
	local cached = self.ttsService._audioCache:get(key)
	if cached then
	else
	end
	return cached
end
function TTSProvider:SetCached(text, data)
	if not self.ttsService or not self.ttsService._audioCache then
		return
	end
	local key = self.ttsService.utils:Hash(text)
	self.ttsService._audioCache:set(key, data)
end
function TTSProvider:GenerateAudio(text, callback, player)
	if callback then callback(nil, "Not implemented") end
end
local ComfyUI_TTS = {}
ComfyUI_TTS.__index = ComfyUI_TTS
setmetatable(ComfyUI_TTS, TTSProvider)
function ComfyUI_TTS:new(config, ttsService)
	local obj = TTSProvider:new(config, ttsService)
	obj.name = "comfyui"
	obj.defaultEndpoint = ttsService:GetTTSURL()
	setmetatable(obj, self)
	return obj
end
function ComfyUI_TTS:GetDisplayName()
	return L("tts_provider_comfyui")
end
function ComfyUI_TTS:ValidateConfig()
	local url = self:GetEndpoint()
	if not url or url == "" then
		return false, L("tts_comfyui_url_not_set")
	end
	return true, "OK"
end
function ComfyUI_TTS:GenerateAudio(text, callback, player)
	local tts = self.ttsService
	if not tts or not tts.utils then
		if callback then callback(nil, "TTS service not available") end
		return
	end
	if not text or text == "" then
		if callback then callback(nil, L("error")) end
		return
	end
	if not tts.utils:IsValid(player) then
		if callback then callback(nil, "Player invalid") end
		return
	end
	local maxConcurrent = tts:GetMaxConcurrent()
	if tts._activeRequests >= maxConcurrent then
		if callback then callback(nil, L("tts_too_many")) end
		return
	end
	local cleanText = tts.utils:CleanForTTS(text)
	if cleanText == "" or cleanText == " " then
		if callback then callback(nil, L("error")) end
		return
	end
	local cacheKey = tts.utils:Hash(cleanText)
	local cached = self:GetCached(cacheKey)
	if cached then
		if callback then callback(cached, nil) end
		return
	end
	local workflow = tts:GetPlayerWorkflow(player)
	if not workflow then
		if callback then callback(nil, L("tts_workflow_not_loaded")) end
		return
	end
	local apiPrompt, err = tts:ConvertUIWorkflowToAPI(workflow)
	if not apiPrompt then
		if callback then callback(nil, L("tts_workflow_convert_error", tostring(err))) end
		return
	end
	local injectedPrompt = tts:InjectTextIntoPrompt(apiPrompt, cleanText)
	if not injectedPrompt then
		if callback then callback(nil, L("tts_workflow_inject_error")) end
		return
	end
	self:SendToComfyUI(injectedPrompt, player, cacheKey, callback)
end
function ComfyUI_TTS:SendToComfyUI(prompt, player, cacheKey, callback)
	local tts = self.ttsService
	if not tts then
		if callback then callback(nil, "TTS service not available") end
		return
	end
	local url = self:GetEndpoint()
	if not url or url == "" then
		if callback then callback(nil, L("tts_comfyui_url_not_set")) end
		return
	end
	tts._activeRequests = tts._activeRequests + 1
	if not prompt or next(prompt) == nil then
		tts._activeRequests = math.max(0, tts._activeRequests - 1)
		if callback then callback(nil, L("tts_workflow_empty")) end
		return
	end
	if self.config and self.config.debug then
		local debugJson = util.TableToJSON(prompt)
		if debugJson then
			file.Write("ai_tts_debug_workflow.json", debugJson)
		end
	end
	local requestBody = {
		prompt = prompt,
		client_id = "gmod_" .. tostring(player:SteamID64())
	}
	local jsonBody = util.TableToJSON(requestBody)
	if not jsonBody then
		tts._activeRequests = math.max(0, tts._activeRequests - 1)
		if callback then callback(nil, L("tts_request_form_error")) end
		return
	end
	local comfyUrl = url .. "/prompt"
	local timeout = tts:GetDefaultTimeout() * 2
	local timerID = "tts_timeout_" .. tostring(player:SteamID64()) .. "_" .. tostring(os.time())
	if SERVER then
		timer.Create(timerID, timeout, 1, function()
			tts._activeRequests = math.max(0, tts._activeRequests - 1)
			if callback then callback(nil, L("tts_timeout")) end
		end)
	end
	tts.utils:HTTPQueue({
		url = comfyUrl,
		method = "POST",
		timeout = timeout,
		body = jsonBody,
		success = function(code, body)
			timer.Remove(timerID)
			if code ~= 200 then
				tts._activeRequests = math.max(0, tts._activeRequests - 1)
				if callback then callback(nil, "HTTP " .. code) end
				return
			end
			local ok, data = pcall(util.JSONToTable, body)
			if not ok then
				ErrorNoHaltWithStack("[AI Companion TTS] JSON parse error: " .. tostring(data) .. "\n")
				tts._activeRequests = math.max(0, tts._activeRequests - 1)
				if callback then callback(nil, L("tts_parse_error")) end
				return
			end
			if not data then
				tts._activeRequests = math.max(0, tts._activeRequests - 1)
				if callback then callback(nil, L("tts_parse_error")) end
				return
			end
			if data.error then
				tts._activeRequests = math.max(0, tts._activeRequests - 1)
				if callback then callback(nil, L("tts_comfyui_error", tostring(data.error))) end
				return
			end
			if not data.prompt_id then
				tts._activeRequests = math.max(0, tts._activeRequests - 1)
				if callback then callback(nil, L("tts_no_prompt_id")) end
				return
			end
			local promptId = data.prompt_id
			self:WaitForAudio(promptId, player, cacheKey, callback)
		end,
		error = function(err)
			timer.Remove(timerID)
			tts._activeRequests = math.max(0, tts._activeRequests - 1)
			if callback then callback(nil, L("tts_connection_error") .. " " .. tostring(err)) end
		end
	})
end
function ComfyUI_TTS:WaitForAudio(promptId, player, cacheKey, callback)
	local tts = self.ttsService
	if not tts then
		if callback then callback(nil, "TTS service not available") end
		return
	end
	local url = self:GetEndpoint()
	local attempts = 0
	local maxAttempts = 60
	local completed = false
	local function checkTTS()
		if completed then
			return
		end
		if not tts.utils:IsValid(player) then
			completed = true
			tts._activeRequests = math.max(0, tts._activeRequests - 1)
			if callback then callback(nil, "Player disconnected") end
			return
		end
		attempts = attempts + 1
		if attempts > maxAttempts then
			completed = true
			tts._activeRequests = math.max(0, tts._activeRequests - 1)
			if callback then callback(nil, L("tts_timeout")) end
			return
		end
		local historyUrl = url .. "/history/" .. promptId
		tts.utils:HTTPQueue({
			url = historyUrl,
			method = "GET",
			timeout = 10,
			success = function(c, b)
				if completed then
					return
				end
				local ok, data = pcall(util.JSONToTable, b)
				if not ok then
					ErrorNoHaltWithStack("[AI Companion TTS] History JSON parse error: " .. tostring(data) .. "\n")
				end
				if ok and data and data[promptId] then
					local history = data[promptId]
					if history.outputs then
						for nodeId, output in pairs(history.outputs) do
							if output.audio and output.audio[1] then
								local fileInfo = output.audio[1]
								if fileInfo and fileInfo.filename then
									local audioUrl = url .. "/view"
									audioUrl = audioUrl .. "?filename=" .. tts.utils:URLEncode(fileInfo.filename)
									if fileInfo.subfolder and fileInfo.subfolder ~= "" then
										audioUrl = audioUrl .. "&subfolder=" .. tts.utils:URLEncode(fileInfo.subfolder)
									end
									if fileInfo.type and fileInfo.type ~= "" then
										audioUrl = audioUrl .. "&type=" .. tts.utils:URLEncode(fileInfo.type)
									end
									self:SetCached(cacheKey, audioUrl)
									completed = true
									tts._activeRequests = math.max(0, tts._activeRequests - 1)
									if callback then
										callback(audioUrl, nil)
									end
									return
								end
							end
						end
					end
					if history.status and history.status.completed then
						completed = true
						tts._activeRequests = math.max(0, tts._activeRequests - 1)
						if callback then callback(nil, L("tts_no_audio")) end
						return
					end
				else
				end
				timer.Simple(1.0, checkTTS)
			end,
			error = function(err)
				if not completed then
					timer.Simple(2.0, checkTTS)
				end
			end
		})
	end
	timer.Simple(1.0, checkTTS)
end
local ElevenLabs_TTS = {}
ElevenLabs_TTS.__index = ElevenLabs_TTS
setmetatable(ElevenLabs_TTS, TTSProvider)
function ElevenLabs_TTS:new(config, ttsService)
	local obj = TTSProvider:new(config, ttsService)
	obj.name = "elevenlabs"
	obj.defaultVoice = "21m00Tcm4TlvDq8ikWAM"
	obj.defaultModel = "eleven_monolingual_v1"
	obj.defaultEndpoint = "https://api.elevenlabs.io/v1/text-to-speech"
	if ttsService.config and ttsService.config:get("Providers") then
		local d = ttsService.config:get("Providers").TTS.Defaults.elevenlabs
		if d then
			obj.defaultVoice = d.voice or obj.defaultVoice
			obj.defaultModel = d.model or obj.defaultModel
		end
	end
	setmetatable(obj, self)
	return obj
end
function ElevenLabs_TTS:GetDisplayName()
	return "ElevenLabs"
end
function ElevenLabs_TTS:ValidateConfig()
	if not self.config.api_key or self.config.api_key == "" then
		return false, L("tts_elevenlabs_key_missing")
	end
	return true, "OK"
end
function ElevenLabs_TTS:GetEndpoint()
	local voice = self.config.voice or self.defaultVoice
	local endpoint = string.format("%s/%s", self.config.endpoint or self.defaultEndpoint, voice)
	return endpoint
end
function ElevenLabs_TTS:GenerateAudio(text, callback, player)
	local tts = self.ttsService
	if not tts or not tts.utils then
		if callback then callback(nil, "TTS service not available") end
		return
	end
	if not text or text == "" then
		if callback then callback(nil, L("error")) end
		return
	end
	local cleanText = tts.utils:CleanForTTS(text)
	if cleanText == "" or cleanText == " " then
		if callback then callback(nil, L("error")) end
		return
	end
	local cacheKey = tts.utils:Hash(cleanText)
	local cached = self:GetCached(cacheKey)
	if cached then
		if callback then callback(cached, nil) end
		return
	end
	local url = self:GetEndpoint()
	local body = {
		text = cleanText,
		model_id = self.config.model or self.defaultModel,
		voice_settings = {
			stability = 0.5,
			similarity_boost = 0.5
		}
	}
	local headers = {
		["xi-api-key"] = self.config.api_key,
		["Content-Type"] = "application/json"
	}
	local timeout = tts:GetDefaultTimeout()
	tts.utils:HTTPQueue({
		url = url,
		method = "POST",
		timeout = timeout,
		body = util.TableToJSON(body),
		headers = headers,
		success = function(code, responseBody)
			if code ~= 200 then
				if callback then callback(nil, "HTTP " .. code) end
				return
			end
			self:SetCached(cacheKey, responseBody)
			if callback then callback(responseBody, nil) end
		end,
		error = function(err)
			if callback then callback(nil, tostring(err)) end
		end
	})
end
local GoogleTTS_TTS = {}
GoogleTTS_TTS.__index = GoogleTTS_TTS
setmetatable(GoogleTTS_TTS, TTSProvider)
function GoogleTTS_TTS:new(config, ttsService)
	local obj = TTSProvider:new(config, ttsService)
	obj.name = "google"
	obj.defaultVoice = "ru-RU-Wavenet-D"
	obj.defaultLanguage = "ru-RU"
	obj.defaultEndpoint = "https://texttospeech.googleapis.com/v1/text:synthesize"
	if ttsService.config and ttsService.config:get("Providers") then
		local d = ttsService.config:get("Providers").TTS.Defaults.google
		if d then
			obj.defaultVoice = d.voice or obj.defaultVoice
			obj.defaultLanguage = d.language or obj.defaultLanguage
		end
	end
	setmetatable(obj, self)
	return obj
end
function GoogleTTS_TTS:GetDisplayName()
	return "Google Cloud TTS"
end
function GoogleTTS_TTS:ValidateConfig()
	if not self.config.api_key or self.config.api_key == "" then
		return false, L("tts_google_key_missing")
	end
	return true, "OK"
end
function GoogleTTS_TTS:GetEndpoint()
	return self.config.endpoint or self.defaultEndpoint
end
function GoogleTTS_TTS:GenerateAudio(text, callback, player)
	local tts = self.ttsService
	if not tts or not tts.utils then
		if callback then callback(nil, "TTS service not available") end
		return
	end
	if not text or text == "" then
		if callback then callback(nil, L("error")) end
		return
	end
	local cleanText = tts.utils:CleanForTTS(text)
	if cleanText == "" or cleanText == " " then
		if callback then callback(nil, L("error")) end
		return
	end
	local cacheKey = tts.utils:Hash(cleanText)
	local cached = self:GetCached(cacheKey)
	if cached then
		if callback then callback(cached, nil) end
		return
	end
	local body = {
		input = { text = cleanText },
		voice = {
			languageCode = self.config.language or self.defaultLanguage,
			name = self.config.voice or self.defaultVoice
		},
		audioConfig = {
			audioEncoding = "MP3"
		}
	}
	local url = self:GetEndpoint() .. "?key=" .. self.config.api_key
	local timeout = tts:GetDefaultTimeout()
	tts.utils:HTTPQueue({
		url = url,
		method = "POST",
		timeout = timeout,
		body = util.TableToJSON(body),
		headers = { ["Content-Type"] = "application/json" },
		success = function(code, responseBody)
			if code ~= 200 then
				if callback then callback(nil, "HTTP " .. code) end
				return
			end
			local ok, data = pcall(util.JSONToTable, responseBody)
			if not ok then
				ErrorNoHaltWithStack("[AI Companion TTS] Google TTS JSON parse error: " .. tostring(data) .. "\n")
				if callback then callback(nil, L("tts_invalid_response")) end
				return
			end
			if not data or not data.audioContent then
				if callback then callback(nil, L("tts_invalid_response")) end
				return
			end
			local audioData = util.Base64Decode(data.audioContent)
			self:SetCached(cacheKey, audioData)
			if callback then callback(audioData, nil) end
		end,
		error = function(err)
			if callback then callback(nil, tostring(err)) end
		end
	})
end
local YandexTTS = {}
YandexTTS.__index = YandexTTS
setmetatable(YandexTTS, TTSProvider)
function YandexTTS:new(config, ttsService)
	local obj = TTSProvider:new(config, ttsService)
	obj.name = "yandex"
	obj.defaultVoice = "oksana"
	obj.defaultLang = "ru-RU"
	obj.defaultEndpoint = "https://tts.api.cloud.yandex.net/speech/v1/tts:synthesize"
	if ttsService.config and ttsService.config:get("Providers") then
		local d = ttsService.config:get("Providers").TTS.Defaults.yandex
		if d then
			obj.defaultVoice = d.voice or obj.defaultVoice
			obj.defaultLang = d.language or obj.defaultLang
		end
	end
	setmetatable(obj, self)
	return obj
end
function YandexTTS:GetDisplayName()
	return "Yandex SpeechKit"
end
function YandexTTS:ValidateConfig()
	if not self.config.api_key or self.config.api_key == "" then
		return false, L("tts_yandex_iam_missing")
	end
	if not self.config.folder_id or self.config.folder_id == "" then
		return false, L("tts_yandex_folder_missing")
	end
	return true, "OK"
end
function YandexTTS:GetEndpoint()
	return self.config.endpoint or self.defaultEndpoint
end
function YandexTTS:GenerateAudio(text, callback, player)
	local tts = self.ttsService
	if not tts or not tts.utils then
		if callback then callback(nil, "TTS service not available") end
		return
	end
	if not text or text == "" then
		if callback then callback(nil, L("error")) end
		return
	end
	local cleanText = tts.utils:CleanForTTS(text)
	if cleanText == "" or cleanText == " " then
		if callback then callback(nil, L("error")) end
		return
	end
	local cacheKey = tts.utils:Hash(cleanText)
	local cached = self:GetCached(cacheKey)
	if cached then
		if callback then callback(cached, nil) end
		return
	end
	local url = self:GetEndpoint()
	local voice = self.config.voice or self.defaultVoice
	local lang = self.config.language or self.defaultLang
	local folderId = self.config.folder_id
	local params = {
		text = cleanText,
		lang = lang,
		voice = voice,
		folderId = folderId,
		format = "mp3"
	}
	local bodyParts = {}
	for k, v in pairs(params) do
		table.insert(bodyParts, k .. "=" .. tts.utils.URLEncode(v))
	end
	local body = table.concat(bodyParts, "&")
	local headers = {
		["Authorization"] = "Bearer " .. self.config.api_key,
		["Content-Type"] = "application/x-www-form-urlencoded"
	}
	local timeout = tts:GetDefaultTimeout()
	tts.utils:HTTPQueue({
		url = url,
		method = "POST",
		timeout = timeout,
		body = body,
		headers = headers,
		success = function(code, responseBody)
			if code ~= 200 then
				if callback then callback(nil, "HTTP " .. code) end
				return
			end
			self:SetCached(cacheKey, responseBody)
			if callback then callback(responseBody, nil) end
		end,
		error = function(err)
			if callback then callback(nil, tostring(err)) end
		end
	})
end
local VKTTS = {}
VKTTS.__index = VKTTS
setmetatable(VKTTS, TTSProvider)
function VKTTS:new(config, ttsService)
	local obj = TTSProvider:new(config, ttsService)
	obj.name = "vk"
	obj.defaultVoice = "katherine"
	obj.defaultEncoder = "mp3"
	obj.defaultTempo = 1.0
	obj.defaultEndpoint = "https://voice.mcs.mail.ru/tts"
	if ttsService.config and ttsService.config:get("Providers") then
		local d = ttsService.config:get("Providers").TTS.Defaults.vk
		if d then
			obj.defaultVoice = d.voice or obj.defaultVoice
			obj.defaultEncoder = d.encoder or obj.defaultEncoder
			obj.defaultTempo = d.tempo or obj.defaultTempo
		end
	end
	setmetatable(obj, self)
	return obj
end
function VKTTS:GetDisplayName()
	return "VK Cloud Voice"
end
function VKTTS:ValidateConfig()
	if not self.config.api_key or self.config.api_key == "" then
		return false, L("tts_vk_token_missing")
	end
	return true, "OK"
end
function VKTTS:GetEndpoint()
	return self.config.endpoint or self.defaultEndpoint
end
function VKTTS:GenerateAudio(text, callback, player)
	local tts = self.ttsService
	if not tts or not tts.utils then
		if callback then callback(nil, "TTS service not available") end
		return
	end
	if not text or text == "" then
		if callback then callback(nil, L("error")) end
		return
	end
	local cleanText = tts.utils:CleanForTTS(text)
	if cleanText == "" or cleanText == " " then
		if callback then callback(nil, L("error")) end
		return
	end
	local cacheKey = tts.utils:Hash(cleanText)
	local cached = self:GetCached(cacheKey)
	if cached then
		if callback then callback(cached, nil) end
		return
	end
	local modelName = self.config.voice or self.defaultVoice
	local encoder = self.config.encoder or self.defaultEncoder
	local tempo = self.config.tempo or self.defaultTempo
	local url = self:GetEndpoint() .. "?" .. table.concat({
		"text=" .. tts.utils.URLEncode(cleanText),
		"model_name=" .. tts.utils.URLEncode(modelName),
		"encoder=" .. tts.utils.URLEncode(encoder),
		"tempo=" .. tostring(tempo)
	}, "&")
	local headers = {
		["Authorization"] = "Bearer " .. self.config.api_key
	}
	local timeout = tts:GetDefaultTimeout()
	tts.utils:HTTPQueue({
		url = url,
		method = "GET",
		timeout = timeout,
		headers = headers,
		success = function(code, responseBody)
			if code ~= 200 then
				if callback then callback(nil, "HTTP " .. code) end
				return
			end
			self:SetCached(cacheKey, responseBody)
			if callback then callback(responseBody, nil) end
		end,
		error = function(err)
			if callback then callback(nil, tostring(err)) end
		end
	})
end
local TTS_PROVIDERS = {
	comfyui = ComfyUI_TTS,
	elevenlabs = ElevenLabs_TTS,
	google = GoogleTTS_TTS,
	yandex = YandexTTS,
	vk = VKTTS,
}
function TTS:CreateProvider(providerType, config)
	local providerClass = TTS_PROVIDERS[providerType]
	if not providerClass then
		return nil, L("tts_unknown_provider", tostring(providerType))
	end
	local provider = providerClass:new(config or {}, self)
	return provider
end
function TTS:GetAvailableProviders()
	local list = {}
	if self.config and self.config:get("Providers") then
		list = self.config:get("Providers").TTS.List or {}
	else
		list = {
			{ id = "comfyui", name = L("tts_provider_comfyui_short"), needsKey = false },
			{ id = "elevenlabs", name = "ElevenLabs", needsKey = true },
			{ id = "google", name = "Google Cloud TTS", needsKey = true },
			{ id = "yandex", name = "Yandex SpeechKit", needsKey = true, needsFolder = true },
			{ id = "vk", name = "VK Cloud Voice", needsKey = true },
		}
	end
	return list
end
function TTS:GetProvider(ply)
	if not self.utils or not self.utils:IsValid(ply) then
		return nil
	end
	local ttsEnabled = self:GetState("TTS_Enabled", false)
	if not ttsEnabled then
		return nil
	end
	local ttsMode = self:GetSetting("TTS_Mode", "local")
	if ttsMode == "local" then
		local config = {
			endpoint = self:GetTTSURL(),
			debug = self:GetSetting("Debug_Mode", false),
		}
		return self:CreateProvider("comfyui", config)
	elseif ttsMode == "cloud" then
		local providerType = self:GetSetting("TTS_Provider", "elevenlabs")
		local config = {
			voice = self:GetSetting("TTS_Voice", ""),
			language = self:GetSetting("TTS_Language", ""),
			endpoint = self:GetSetting("TTS_Endpoint", ""),
			api_key = self:GetSetting("TTS_API_Key", ""),
			folder_id = self:GetSetting("Yandex_Folder_ID", ""),
			encoder = self:GetSetting("VK_Encoder", "mp3"),
			tempo = self:GetSetting("VK_Tempo", 1.0),
			debug = self:GetSetting("Debug_Mode", false),
		}
		return self:CreateProvider(providerType, config)
	end
	return nil
end
function TTS:Generate(ply, text, callback)
	if SERVER then
		local locator = AICompanion.GetLocator()
		if locator and locator:has("commands") then
			local commands = locator:get("commands")
			if commands and commands.CheckTTSRateLimit then
				local ok, err = commands:CheckTTSRateLimit(ply)
				if not ok then
					if callback then callback(nil, err) end
					return
				end
			end
		end
	end

	if not self.utils or not self.utils:IsValid(ply) then
		if callback then callback(nil, "Player invalid") end
		return
	end
	local ttsEnabled = self:GetState("TTS_Enabled", false)
	local ttsMode = self:GetSetting("TTS_Mode", "local")
	if not ttsEnabled or ttsMode == "disabled" then
		if callback then callback(nil, "TTS disabled") end
		return
	end
	local personalTTS = self:GetSetting("TTS_Personal", true)
	if not personalTTS then
		if callback then callback(nil, "Personal TTS disabled") end
		return
	end
	if not text or text == "" then
		if callback then callback(nil, L("error")) end
		return
	end
	if type(text) ~= "string" then
		text = tostring(text) or ""
	end
	local originalText = text
	if not self:GetState("TTS_Enabled", false) then
		if callback then callback(nil, L("tts_disabled")) end
		return
	end
	local provider = self:GetProvider(ply)
	if not provider then
		if callback then callback(nil, L("tts_error_no_url")) end
		return
	end
	local valid, err = provider:ValidateConfig()
	if not valid then
		if callback then callback(nil, err) end
		return
	end
	local cleanText = self.utils:CleanForTTS(originalText)
	if not cleanText or cleanText == "" or cleanText == " " then
		if callback then callback(nil, L("error")) end
		return
	end
	provider:GenerateAudio(cleanText, function(audioData, err)
		if err then
			if callback then callback(nil, err) end
			return
		end
		if audioData then
			self:SendAudio(ply, audioData)
			if callback then callback(audioData, nil) end
		else
			if callback then callback(nil, L("tts_no_audio_data")) end
		end
	end, ply)
end
function TTS:SendAudio(ply, audioUrl)
	if not self.utils or not self.utils:IsValid(ply) then
		return
	end
	if not audioUrl or audioUrl == "" then
		return
	end
	local locator = AICompanion.GetLocator()
	if locator and locator:has("shared") then
		local shared = locator:get("shared")
		shared:SendAudioURL(ply, audioUrl)
	else
		net.Start("gmod.one/ai-companion/play-audio")
		net.WriteString(audioUrl)
		net.Send(ply)
	end
end
local WIDGET_MAPPINGS = {
	["OmniVoiceVoiceCloneTTS"] = {
		"model", "text", "ref_text", "steps", "guidance_scale", "t_shift",
		"speed", "duration", "device", "dtype", "attention", "seed",
		"control_after_generate", "position_temperature", "class_temperature",
		"layer_penalty_factor", "denoise", "preprocess_prompt", "postprocess_output",
		"keep_model_loaded", "instruct"
	},
	["SET_AudioResampler"] = {
		"target_sample_rate"
	},
	["SaveAudioMP3"] = {
		"filename_prefix", "quality"
	},
	["SaveAudio"] = {
		"filename_prefix"
	},
	["LoadAudio"] = {
		"audio", "upload"
	},
	["PreviewAudio"] = {},
}
local SKIP_WIDGETS = {
	["control_after_generate"] = true,
	["upload"] = true,
}
local TEXT_FIELD_SCORES = {
	["text"] = 100,
	["prompt"] = 95,
	["tts_text"] = 90,
	["input_text"] = 85,
	["synthesis_text"] = 85,
	["target_text"] = 80,
	["ref_text"] = -100,
	["prompt_text"] = -50,
	["instruct_text"] = -50,
	["ref_prompt"] = -50,
	["reference_text"] = -80,
	["words"] = 70,
	["content"] = 60,
	["message"] = 60,
	["utterance"] = 60,
	["dialogue"] = 55,
	["speech"] = 55,
	["description"] = 30,
	["caption"] = 25,
	["label"] = 20,
}
local NODE_SPECIAL_RULES = {
	["OmniVoiceVoiceCloneTTS"] = {
		textField = "text",
		excludeFields = {"ref_text", "instruct"}
	},
	["CosyVoiceNode"] = {
		textField = "tts_text",
		excludeFields = {"prompt_text", "instruct_text"}
	},
	["Qwen3VoiceClone"] = {
		textField = "prompt",
		excludeFields = {"ref_text"}
	},
	["MeloTTS"] = {
		textField = "text",
		excludeFields = {"ref_text", "speaker"}
	},
	["KandinskyTTS"] = {
		textField = "text",
		excludeFields = {"ref_text"}
	},
	["RVC"] = {
		textField = "text",
		excludeFields = {"ref_text", "pitch"}
	},
	["XTTS"] = {
		textField = "text",
		excludeFields = {"ref_text", "language"}
	},
	["F5TTS"] = {
		textField = "text",
		excludeFields = {"ref_text"}
	},
}
function TTS:GetPlayerWorkflow(ply)
	if not self.utils or not self.utils:IsValid(ply) then
		return nil
	end
	local enabled = self:GetSetting("TTS_Workflow_Enabled", false)
	if not enabled then
		return nil
	end
	local workflow = self:GetSetting("TTS_Workflow", nil)
	if not workflow or type(workflow) ~= "table" then
		return nil
	end
	return workflow
end
function TTS:ConvertUIWorkflowToAPI(workflow)
	if not workflow then
		return nil, "Workflow is nil"
	end
	if not workflow.nodes then
		local isApiFormat = false
		for k, v in pairs(workflow) do
			if type(v) == "table" and v.class_type then
				isApiFormat = true
				break
			end
		end
		if isApiFormat then
			return workflow, nil
		else
			return nil, L("tts_unknown_workflow_format")
		end
	end
	local apiPrompt = {}
	local links = {}
	if workflow.links and type(workflow.links) == "table" then
		for _, link in ipairs(workflow.links) do
			if #link >= 5 then
				local linkId = link[1]
				local fromNode = tostring(link[2])
				local fromSlot = link[3]
				local toNode = tostring(link[4])
				local toSlot = link[5]
				links[linkId] = {
					from = fromNode,
					fromSlot = fromSlot,
					to = toNode,
					toSlot = toSlot,
				}
			end
		end
	end
	for _, node in ipairs(workflow.nodes) do
		if not node.id then
			continue
		end
		local nodeId = tostring(node.id)
		local nodeType = node.type or "Unknown"
		local apiNode = {
			class_type = nodeType,
			_meta = {
				title = nodeType
			}
		}
		if node._meta and type(node._meta) == "table" then
			apiNode._meta = table.Copy(node._meta)
		end
		local inputs = {}
		if node.widgets_values_named and type(node.widgets_values_named) == "table" then
			for k, v in pairs(node.widgets_values_named) do
				if not SKIP_WIDGETS[k] then
					inputs[k] = v
				end
			end
		elseif node.widgets_values and type(node.widgets_values) == "table" then
			local mapping = WIDGET_MAPPINGS[nodeType]
			if mapping then
				for i, widgetName in ipairs(mapping) do
					if not SKIP_WIDGETS[widgetName] and node.widgets_values[i] ~= nil then
						inputs[widgetName] = node.widgets_values[i]
					end
				end
			else
				if self.utils then
					self.utils.LogWarn("TTS", L("tts_no_widget_mapping"), nodeType)
				end
				for i, v in ipairs(node.widgets_values) do
					inputs["widget_" .. i] = v
				end
			end
		end
		if node.inputs and type(node.inputs) == "table" then
			for _, inp in ipairs(node.inputs) do
				if inp.link then
					local linkData = links[inp.link]
					if linkData and linkData.to == nodeId then
						inputs[inp.name] = { linkData.from, linkData.fromSlot }
					end
				end
			end
		end
		apiNode.inputs = inputs
		apiPrompt[nodeId] = apiNode
	end
	return apiPrompt, nil
end
function TTS:FindTextFieldInNode(node, nodeType)
	if not node or not node.inputs then
		return nil, nil
	end
	local specialRule = NODE_SPECIAL_RULES[nodeType]
	if specialRule then
		if specialRule.textField and node.inputs[specialRule.textField] ~= nil then
			return specialRule.textField, "special_rule"
		end
	end
	local candidates = {}
	for fieldName, value in pairs(node.inputs) do
		if type(value) == "string" then
			local score = TEXT_FIELD_SCORES[fieldName] or 0
			if string.find(string.lower(fieldName), "ref") or string.find(string.lower(fieldName), "reference") then
				score = score - 80
			end
			if value and #value > 0 then
				if #value < 5 then
					score = score - 20
				end
				if string.find(string.lower(value), "инструкц") or
				   string.find(string.lower(value), "instruction") or
				   string.find(string.lower(value), "настройк") then
					score = score - 50
				end
			end
			table.insert(candidates, {
				name = fieldName,
				value = value,
				score = score
			})
		end
	end
	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)
	for _, candidate in ipairs(candidates) do
		if candidate.score > 0 then
			return candidate.name, "auto"
		end
	end
	for fieldName, value in pairs(node.inputs) do
		if type(value) == "string" and
		   string.find(string.lower(fieldName), "text") and
		   not string.find(string.lower(fieldName), "ref") then
			return fieldName, "fallback_text"
		end
	end
	return nil, nil
end
function TTS:InjectTextIntoPrompt(prompt, text)
	if not prompt then
		return nil
	end
	local result = util.TableToJSON(prompt)
	if not result then
		return nil
	end
	local ok, injected = pcall(util.JSONToTable, result)
	if not ok then
		ErrorNoHaltWithStack("[AI Companion TTS] Workflow inject JSON error: " .. tostring(injected) .. "\n")
		return nil
	end
	if not injected then
		return nil
	end
	local textNodeFound = false
	local injectedCount = 0
	for nodeId, node in pairs(injected) do
		if node.inputs then
			local fieldName, method = self:FindTextFieldInNode(node, node.class_type)
			if fieldName then
				node.inputs[fieldName] = text
				textNodeFound = true
				injectedCount = injectedCount + 1
			end
		end
	end
	if not textNodeFound then
		if self.utils then
			self.utils.LogWarn("TTS", L("tts_no_text_field"))
		end
		return nil
	end
	return injected
end
function TTS:InjectTextIntoWorkflow(workflow, text)
	if not workflow then
		return nil
	end
	local apiPrompt, err = self:ConvertUIWorkflowToAPI(workflow)
	if not apiPrompt then
		return nil
	end
	return self:InjectTextIntoPrompt(apiPrompt, text)
end
function TTS:SetupNetMessages()
	if not SERVER then return end
	util.AddNetworkString("gmod.one/ai-companion/play-audio")
	util.AddNetworkString("gmod.one/ai-companion/tts-request")
end
function TTS:SetupCommands()
	if not SERVER then return end
	concommand.Add("ai_test_tts", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then
			return
		end
		if not ply:IsAdmin() then
			ply:ChatPrint(L("settings_admin_only"))
			return
		end
		local ip = self:GetSetting("TTS_IP", "127.0.0.1")
		local port = self:GetSetting("TTS_Port", 8188)
		ip = string.gsub(tostring(ip), ":%d+$", "")
		local url = "http://" .. ip .. ":" .. port
		ply:ChatPrint(L("tts_test_connection", url))
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
					local msg = L("tts_comfyui_available", code)
					ply:ChatPrint("[AI] " .. msg)
				else
					local msg = L("tts_comfyui_response_code", code)
					ply:ChatPrint("[AI] " .. msg)
				end
			end,
			failed = function(err)
				local msg = L("tts_comfyui_unavailable", tostring(err))
				ply:ChatPrint("[AI] " .. msg)
			end
		})
	end)
	concommand.Add("ai_tts_status", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		local ttsEnabled = self:GetState("TTS_Enabled", false)
		local globalTTS = self:GetSetting("Global_TTS_Enabled", false)
		local ttsMode = self:GetSetting("TTS_Mode", "local")
		local url = self:GetTTSURL()
		local provider = self:GetSetting("TTS_Provider", "elevenlabs")
		ply:ChatPrint(L("tts_status_header"))
		ply:ChatPrint(L("tts_global_status_label", ttsEnabled and L("mode_on") or L("mode_off")))
		local modeLabel = ttsMode == "local"
			and L("tts_mode_local_comfyui")
			or L("tts_mode_cloud_prefix", provider)
		ply:ChatPrint(L("tts_mode_label", modeLabel))
		ply:ChatPrint("[AI] URL: " .. url)
	end)
	concommand.Add("ai_tts_global_on", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then
			return
		end
		if not ply:IsAdmin() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint(L("settings_admin_only"))
			end
			return
		end
		if self.state then
			self.state:setState("TTS_Enabled", true)
			self.state:setSetting("Global_TTS_Enabled", true)
			self.state:setSetting("TTS_Enabled", true)
			self.state:setState("Global_TTS_Enabled", true)
			self.state:MarkDirty()
			if self.state.SaveToFile then
				self.state:SaveToFile()
			end
		end
		if self.utils and self.utils:IsValid(ply) then
			ply:ChatPrint(L("tts_global_on_msg"))
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("shared") then
			local shared = locator:get("shared")
			shared:SyncTTStatus(true)
		else
			if SERVER then
				net.Start("gmod.one/ai-companion/tts-global-status")
				net.WriteBool(true)
				net.Broadcast()
			end
		end
		if SERVER then
			for _, p in ipairs(player.GetAll()) do
				if self.utils and self.utils:IsValid(p) and not p:IsBot() then
					if locator and locator:has("shared") then
						locator:get("shared"):SyncConfigToClient(p)
					end
				end
			end
		end
	end)
	concommand.Add("ai_tts_global_off", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then
			return
		end
		if not ply:IsAdmin() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint(L("settings_admin_only"))
			end
			return
		end
		if self.state then
			self.state:setState("TTS_Enabled", false)
			self.state:setSetting("Global_TTS_Enabled", false)
			self.state:setSetting("TTS_Enabled", false)
			self.state:setState("Global_TTS_Enabled", false)
			self.state:MarkDirty()
			if self.state.SaveToFile then
				self.state:SaveToFile()
			end
		end
		if self.utils and self.utils:IsValid(ply) then
			ply:ChatPrint(L("tts_global_off_msg"))
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("shared") then
			local shared = locator:get("shared")
			shared:SyncTTStatus(false)
		else
			if SERVER then
				net.Start("gmod.one/ai-companion/tts-global-status")
				net.WriteBool(false)
				net.Broadcast()
			end
		end
		if SERVER then
			for _, p in ipairs(player.GetAll()) do
				if self.utils and self.utils:IsValid(p) and not p:IsBot() then
					if locator and locator:has("shared") then
						locator:get("shared"):SyncConfigToClient(p)
					end
				end
			end
		end
	end)
	concommand.Add("ai_tts_toggle", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then
			return
		end
		if not ply:IsAdmin() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint(L("settings_admin_only"))
			end
			return
		end
		local currentState = self:GetState("TTS_Enabled", false)
		if currentState then
			RunConsoleCommand("ai_tts_global_off")
		else
			RunConsoleCommand("ai_tts_global_on")
		end
	end)
	concommand.Add("ai_tts_personal", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		local globalEnabled = self:GetState("TTS_Enabled", false)
		if not globalEnabled then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint(L("tts_admin_disabled"))
			end
			return
		end
		local current = self:GetSetting("TTS_Personal", true)
		local newValue = not current
		if self.state then
			self.state:setSetting("TTS_Personal", newValue)
			self.state:MarkDirty()
			if self.state.SaveToFile then
				self.state:SaveToFile()
			end
		end
		local locator = AICompanion.GetLocator()
		if locator and locator:has("shared") and self.utils and self.utils:IsValid(ply) then
			locator:get("shared"):SyncConfigToClient(ply)
		end
		local state = newValue and L("mode_on") or L("mode_off")
		if self.utils and self.utils:IsValid(ply) then
			ply:ChatPrint(L("tts_personal_label", state))
		end
	end)
end
function TTS:SetupWorkflowCommands()
	if not SERVER then return end
	concommand.Add("ai_tts_workflow_load", function(ply, cmd, args)
		if not self.utils or not self.utils:IsValid(ply) then
			return
		end
		if not ply:IsAdmin() then
			ply:ChatPrint(L("settings_admin_only"))
			return
		end
		if #args < 1 then
			ply:ChatPrint(L("tts_workflow_usage"))
			return
		end
		local filePath = args[1]
		local data = file.Read(filePath, "DATA")
		if not data then
			ply:ChatPrint(L("tts_file_read_error", filePath))
			return
		end
		local ok, workflow = pcall(util.JSONToTable, data)
		if not ok then
			ErrorNoHaltWithStack("[AI Companion TTS] Workflow file JSON error: " .. tostring(workflow) .. "\n")
			ply:ChatPrint(L("tts_json_parse_error"))
			return
		end
		if not workflow then
			ply:ChatPrint(L("tts_json_parse_error"))
			return
		end
		local apiPrompt, err = self:ConvertUIWorkflowToAPI(workflow)
		if not apiPrompt then
			ply:ChatPrint(L("tts_workflow_convert_error", tostring(err)))
			return
		end
		local hasTTSNode = false
		for nodeId, node in pairs(apiPrompt) do
			if node.class_type == "OmniVoiceVoiceCloneTTS" then
				hasTTSNode = true
				break
			end
		end
		if not hasTTSNode then
			ply:ChatPrint(L("tts_workflow_no_tts_node"))
		end
		if self.state then
			self.state:setSetting("TTS_Workflow", apiPrompt)
			self.state:setSetting("TTS_Workflow_Filename", filePath)
			self.state:setSetting("TTS_Workflow_Enabled", true)
		end
		ply:ChatPrint(L("tts_workflow_loaded", filePath))
		ply:ChatPrint(L("tts_workflow_toggle_hint"))
	end)
	concommand.Add("ai_tts_workflow_toggle", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		local current = self:GetSetting("TTS_Workflow_Enabled", false)
		local newValue = not current
		if self.state then
			self.state:setSetting("TTS_Workflow_Enabled", newValue)
			self.state:SyncSingleSettingToAll("TTS_Workflow_Enabled", newValue)
		end
		local state = newValue and L("mode_on") or L("mode_off")
		ply:ChatPrint(L("tts_workflow_custom_label", state))
	end)
	concommand.Add("ai_tts_workflow_reset", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if self.state then
			self.state:setSetting("TTS_Workflow", nil)
			self.state:setSetting("TTS_Workflow_Filename", "")
			self.state:setSetting("TTS_Workflow_Enabled", false)
		end
		ply:ChatPrint(L("tts_workflow_reset_msg"))
	end)
	concommand.Add("ai_tts_workflow_status", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		local filename = self:GetSetting("TTS_Workflow_Filename", L("tts_not_loaded"))
		local enabled = self:GetSetting("TTS_Workflow_Enabled", false)
		ply:ChatPrint(L("tts_workflow_status_header"))
		ply:ChatPrint(L("tts_file_label", filename))
		ply:ChatPrint(L("tts_enabled_label", enabled and L("yes") or L("no")))
	end)
end
function TTS:GetAPI()
	return {
		Generate = function(ply, text, callback) return self:Generate(ply, text, callback) end,
		GetProvider = function(ply) return self:GetProvider(ply) end,
		GetProviders = function() return self:GetAvailableProviders() end,
		CreateProvider = function(type, config) return self:CreateProvider(type, config) end,
		GetPlayerWorkflow = function(ply) return self:GetPlayerWorkflow(ply) end,
		InjectTextIntoWorkflow = function(workflow, text) return self:InjectTextIntoWorkflow(workflow, text) end,
		InjectTextIntoPrompt = function(prompt, text) return self:InjectTextIntoPrompt(prompt, text) end,
		ConvertUIWorkflowToAPI = function(workflow) return self:ConvertUIWorkflowToAPI(workflow) end,
	}
end
return TTS
