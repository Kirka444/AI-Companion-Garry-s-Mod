
local TTS = {}

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
    self.utils:LogDebug("[TTS] 🚀 init() вызван!")

    if self._initialized then
        self.utils:LogDebug("[TTS] ⚠️ Уже инициализирован, пропускаем")
        return
    end

    self.utils:LogDebug("[TTS] 📋 Начинаем инициализацию...")
    self.utils:LogDebug("[TTS] 📋 utils =", self.utils and "есть" or "nil")
    self.utils:LogDebug("[TTS] 📋 config =", self.config and "есть" or "nil")
    self.utils:LogDebug("[TTS] 📋 state =", self.state and "есть" or "nil")

    self.utils:LogDebug("[TTS] 📦 Инициализация кэша...")
    local cacheSize = 50
    local cacheTTL = 300
    if self.config then
        local cacheConfig = self.config:get("Cache")
        if cacheConfig and cacheConfig.TTS then
            cacheSize = cacheConfig.TTS.Size or 50
            cacheTTL = cacheConfig.TTS.TTL or 300
            self.utils:LogDebug("[TTS] 📦 Размер кэша:", cacheSize, "TTL:", cacheTTL)
        end
    end
    if self.utils and self.utils.CreateCache then
        self.utils:LogDebug("[TTS] 📦 Создаём кэш через utils")
        self._audioCache = self.utils.CreateCache(cacheSize, cacheTTL)
    else
        self.utils:LogDebug("[TTS] ⚠️ utils.CreateCache недоступен, кэш будет отключён")
    end

    if SERVER then
        self.utils:LogDebug("[TTS] 🖥️ Серверный режим, настраиваем сетевые сообщения и команды")
        self:SetupNetMessages()
        self:SetupCommands()
        self:SetupWorkflowCommands()
    else
        self.utils:LogDebug("[TTS] 🖥️ Клиентский режим, пропускаем серверные настройки")
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("TTS", "TTS сервис инициализирован")
    end
    self.utils:LogDebug("[TTS] ✅ Инициализация завершена!")
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
        self.utils:LogDebug("[TTS] 🔢 MaxConcurrent:", val)
        return val
    end
    self.utils:LogDebug("[TTS] 🔢 MaxConcurrent: 3 (default)")
    return 3
end

function TTS:GetDefaultTimeout()
    if self.config and self.config:get("HTTP") then
        local val = self.config:get("HTTP").DefaultTimeout or 30
        self.utils:LogDebug("[TTS] ⏱️ DefaultTimeout:", val)
        return val
    end
    self.utils:LogDebug("[TTS] ⏱️ DefaultTimeout: 30 (default)")
    return 30
end

function TTS:GetCacheTTL()
    if self.config and self.config:get("Cache") and self.config:get("Cache").TTS then
        local val = self.config:get("Cache").TTS.TTL or 300
        self.utils:LogDebug("[TTS] ⏱️ CacheTTL:", val)
        return val
    end
    self.utils:LogDebug("[TTS] ⏱️ CacheTTL: 300 (default)")
    return 300
end

function TTS:GetTTSURL()
    local ip = self:GetSetting("TTS_IP", "127.0.0.1")
    local port = self:GetSetting("TTS_Port", 8188)
    local url = string.format("http://%s:%d", ip, port)
    self.utils:LogDebug("[TTS] 🌐 TTS URL:", url)
    return url
end

local TTSProvider = {}
TTSProvider.__index = TTSProvider

function TTSProvider:new(config, ttsService)
    self.utils:LogDebug("[TTSProvider] 🔧 Создание провайдера с конфигом:", config)
    local obj = {
        config = config or {},
        name = "unknown",
        enabled = true,
        ttsService = ttsService,
    }
    setmetatable(obj, self)
    return obj
end

function TTSProvider:ValidateConfig()
    self.utils:LogDebug("[TTSProvider] ✅ ValidateConfig для", self.name)
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
        self.utils:LogDebug("[TTSProvider] ⚠️ Кэш недоступен для", self.name)
        return nil
    end
    local key = self.ttsService.utils:Hash(text)
    local cached = self.ttsService._audioCache:get(key)
    if cached then
        self.utils:LogDebug("[TTSProvider] ✅ Кэш HIT для", self.name, "ключ:", key)
    else
        self.utils:LogDebug("[TTSProvider] ❌ Кэш MISS для", self.name, "ключ:", key)
    end
    return cached
end

function TTSProvider:SetCached(text, data)
    if not self.ttsService or not self.ttsService._audioCache then
        self.utils:LogDebug("[TTSProvider] ⚠️ Кэш недоступен для записи", self.name)
        return
    end
    local key = self.ttsService.utils:Hash(text)
    self.ttsService._audioCache:set(key, data)
    self.utils:LogDebug("[TTSProvider] 💾 Кэш сохранён для", self.name, "ключ:", key)
end

function TTSProvider:GenerateAudio(text, callback, player)
    self.utils:LogDebug("[TTSProvider] ⚠️ GenerateAudio не реализован для", self.name)
    if callback then callback(nil, "Not implemented") end
end

local ComfyUI_TTS = {}
ComfyUI_TTS.__index = ComfyUI_TTS
setmetatable(ComfyUI_TTS, TTSProvider)

function ComfyUI_TTS:new(config, ttsService)
    self.utils:LogDebug("[ComfyUI_TTS] 🔧 Создание ComfyUI провайдера")
    local obj = TTSProvider:new(config, ttsService)
    obj.name = "comfyui"
    obj.defaultEndpoint = ttsService:GetTTSURL()
    self.utils:LogDebug("[ComfyUI_TTS] 📍 Endpoint:", obj.defaultEndpoint)
    setmetatable(obj, self)
    return obj
end

function ComfyUI_TTS:GetDisplayName()
    return "ComfyUI (локальный TTS)"
end

function ComfyUI_TTS:ValidateConfig()
    local url = self:GetEndpoint()
    self.utils:LogDebug("[ComfyUI_TTS] 🔍 Проверка конфига, URL:", url)
    if not url or url == "" then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ URL пустой!")
        return false, "ComfyUI URL не настроен"
    end
    self.utils:LogDebug("[ComfyUI_TTS] ✅ Конфиг валидный")
    return true, "OK"
end

function ComfyUI_TTS:GenerateAudio(text, callback, player)
    self.utils:LogDebug("[ComfyUI_TTS] 🎵 GenerateAudio вызван!")
    self.utils:LogDebug("[ComfyUI_TTS] 📝 Текст:", text and string.sub(text, 1, 50) or "nil")
    self.utils:LogDebug("[ComfyUI_TTS] 👤 Игрок:", player and player:Nick() or "nil")

    local tts = self.ttsService
    if not tts or not tts.utils then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ TTS service или utils недоступны!")
        if callback then callback(nil, "TTS service not available") end
        return
    end

    if not text or text == "" then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Пустой текст!")
        if callback then callback(nil, "Пустой текст") end
        return
    end

    if not tts.utils:IsValid(player) then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Player invalid!")
        if callback then callback(nil, "Player invalid") end
        return
    end

    local maxConcurrent = tts:GetMaxConcurrent()
    self.utils:LogDebug("[ComfyUI_TTS] 📊 Активных запросов:", tts._activeRequests, "Максимум:", maxConcurrent)
    if tts._activeRequests >= maxConcurrent then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Слишком много запросов!")
        if callback then callback(nil, "Слишком много TTS запросов") end
        return
    end

    local cleanText = tts.utils:CleanForTTS(text)
    self.utils:LogDebug("[ComfyUI_TTS] 🧹 Очищенный текст:", cleanText and string.sub(cleanText, 1, 50) or "nil")
    if cleanText == "" or cleanText == " " then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Текст пуст после очистки!")
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end

    local cacheKey = tts.utils:Hash(cleanText)
    self.utils:LogDebug("[ComfyUI_TTS] 🔑 Ключ кэша:", cacheKey)
    local cached = self:GetCached(cacheKey)
    if cached then
        self.utils:LogDebug("[ComfyUI_TTS] ✅ Найдено в кэше!")
        if callback then callback(cached, nil) end
        return
    end

    self.utils:LogDebug("[ComfyUI_TTS] 📋 Получение workflow для игрока...")
    local workflow = tts:GetPlayerWorkflow(player)
    if not workflow then
        self.utils:LogDebug("[ComfyUI_TTS] ⚠️ Кастомный workflow не загружен или отключён")
        if callback then callback(nil, "Кастомный workflow не загружен или отключён") end
        return
    end
    self.utils:LogDebug("[ComfyUI_TTS] 📋 Workflow получен, тип:", type(workflow))

    self.utils:LogDebug("[ComfyUI_TTS] 🔄 Конвертация UI workflow в API формат...")
    local apiPrompt, err = tts:ConvertUIWorkflowToAPI(workflow)
    if not apiPrompt then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Ошибка конвертации workflow:", err or "неизвестная ошибка")
        if callback then callback(nil, "Ошибка конвертации workflow: " .. tostring(err)) end
        return
    end
    self.utils:LogDebug("[ComfyUI_TTS] ✅ Конвертация успешна, нод в API:", table.Count(apiPrompt))

    self.utils:LogDebug("[ComfyUI_TTS] 📝 Вставка текста в workflow...")
    local injectedPrompt = tts:InjectTextIntoPrompt(apiPrompt, cleanText)
    if not injectedPrompt then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Ошибка вставки текста в workflow")
        if callback then callback(nil, "Ошибка вставки текста в workflow") end
        return
    end
    self.utils:LogDebug("[ComfyUI_TTS] ✅ Текст вставлен успешно")

    self:SendToComfyUI(injectedPrompt, player, cacheKey, callback)
end

function ComfyUI_TTS:SendToComfyUI(prompt, player, cacheKey, callback)
    self.utils:LogDebug("[ComfyUI_TTS] 📤 SendToComfyUI вызван!")

    local tts = self.ttsService
    if not tts then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ TTS service не доступен!")
        if callback then callback(nil, "TTS service not available") end
        return
    end

    local url = self:GetEndpoint()
    self.utils:LogDebug("[ComfyUI_TTS] 🌐 URL:", url)
    if not url or url == "" then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ URL пустой!")
        if callback then callback(nil, "ComfyUI URL не настроен") end
        return
    end

    tts._activeRequests = tts._activeRequests + 1
    self.utils:LogDebug("[ComfyUI_TTS] 📊 Активных запросов теперь:", tts._activeRequests)

    if not prompt or next(prompt) == nil then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Workflow пустой!")
        tts._activeRequests = math.max(0, tts._activeRequests - 1)
        if callback then callback(nil, "Workflow пустой") end
        return
    end

    if self.config and self.config.debug then
        self.utils:LogDebug("[ComfyUI_TTS] 🐞 Режим отладки включён, сохраняем workflow в файл")
        local debugJson = util.TableToJSON(prompt)
        if debugJson then
            file.Write("ai_tts_debug_workflow.json", debugJson)
            self.utils:LogDebug("[ComfyUI_TTS] 📁 Workflow сохранён в ai_tts_debug_workflow.json")
        end
    end

    local requestBody = {
        prompt = prompt,
        client_id = "gmod_" .. tostring(player:SteamID64())
    }
    local jsonBody = util.TableToJSON(requestBody)

    if not jsonBody then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ Ошибка формирования JSON запроса!")
        tts._activeRequests = math.max(0, tts._activeRequests - 1)
        if callback then callback(nil, "Ошибка формирования запроса") end
        return
    end
    self.utils:LogDebug("[ComfyUI_TTS] 📝 JSON запроса сформирован, размер:", #jsonBody)

    local comfyUrl = url .. "/prompt"
    local timeout = tts:GetDefaultTimeout() * 2
    self.utils:LogDebug("[ComfyUI_TTS] ⏱️ Таймаут:", timeout)

    local timerID = "tts_timeout_" .. tostring(player:SteamID64()) .. "_" .. tostring(os.time())
    self.utils:LogDebug("[ComfyUI_TTS] ⏱️ Таймер ID:", timerID)

    if SERVER then
        timer.Create(timerID, timeout, 1, function()
            self.utils:LogDebug("[ComfyUI_TTS] ⏰ Таймаут! Превышено время ожидания ComfyUI")
            tts._activeRequests = math.max(0, tts._activeRequests - 1)
            if callback then callback(nil, "Превышено время ожидания ComfyUI") end
        end)
    end

    self.utils:LogDebug("[ComfyUI_TTS] 📤 Отправка запроса в ComfyUI...")
    tts.utils:HTTPQueue({
        url = comfyUrl,
        method = "POST",
        timeout = timeout,
        body = jsonBody,
        success = function(code, body)
            self.utils:LogDebug("[ComfyUI_TTS] ✅ Ответ от ComfyUI, код:", code)
            timer.Remove(timerID)

            if code ~= 200 then
                self.utils:LogDebug("[ComfyUI_TTS] ❌ HTTP код:", code)
                tts._activeRequests = math.max(0, tts._activeRequests - 1)
                if callback then callback(nil, "HTTP " .. code) end
                return
            end

            local ok, data = pcall(util.JSONToTable, body)
            if not ok or not data then
                self.utils:LogDebug("[ComfyUI_TTS] ❌ Ошибка парсинга ответа!")
                tts._activeRequests = math.max(0, tts._activeRequests - 1)
                if callback then callback(nil, "Ошибка парсинга ответа") end
                return
            end

            if data.error then
                self.utils:LogDebug("[ComfyUI_TTS] ❌ ComfyUI ошибка:", data.error)
                tts._activeRequests = math.max(0, tts._activeRequests - 1)
                if callback then callback(nil, "ComfyUI ошибка: " .. tostring(data.error)) end
                return
            end

            if not data.prompt_id then
                self.utils:LogDebug("[ComfyUI_TTS] ❌ Нет prompt_id в ответе!")
                tts._activeRequests = math.max(0, tts._activeRequests - 1)
                if callback then callback(nil, "Нет prompt_id в ответе") end
                return
            end

            local promptId = data.prompt_id
            self.utils:LogDebug("[ComfyUI_TTS] 📝 prompt_id:", promptId)
            self:WaitForAudio(promptId, player, cacheKey, callback)
        end,
        error = function(err)
            self.utils:LogDebug("[ComfyUI_TTS] ❌ Ошибка соединения:", err)
            timer.Remove(timerID)
            tts._activeRequests = math.max(0, tts._activeRequests - 1)
            if callback then callback(nil, "Ошибка соединения: " .. tostring(err)) end
        end
    })
end

function ComfyUI_TTS:WaitForAudio(promptId, player, cacheKey, callback)
    self.utils:LogDebug("[ComfyUI_TTS] ⏳ WaitForAudio вызван для prompt_id:", promptId)

    local tts = self.ttsService
    if not tts then
        self.utils:LogDebug("[ComfyUI_TTS] ❌ TTS service не доступен!")
        if callback then callback(nil, "TTS service not available") end
        return
    end

    local url = self:GetEndpoint()
    local attempts = 0
    local maxAttempts = 60
    local completed = false

    local function checkTTS()
        if completed then
            self.utils:LogDebug("[ComfyUI_TTS] ⏳ checkTTS: уже завершено, пропускаем")
            return
        end

        if not tts.utils:IsValid(player) then
            self.utils:LogDebug("[ComfyUI_TTS] ❌ Player disconnected!")
            completed = true
            tts._activeRequests = math.max(0, tts._activeRequests - 1)
            if callback then callback(nil, "Player disconnected") end
            return
        end

        attempts = attempts + 1
        self.utils:LogDebug("[ComfyUI_TTS] ⏳ Попытка #" .. attempts .. " из " .. maxAttempts)

        if attempts > maxAttempts then
            self.utils:LogDebug("[ComfyUI_TTS] ❌ Превышено время ожидания аудио!")
            completed = true
            tts._activeRequests = math.max(0, tts._activeRequests - 1)
            if callback then callback(nil, "Превышено время ожидания аудио") end
            return
        end

        local historyUrl = url .. "/history/" .. promptId
        self.utils:LogDebug("[ComfyUI_TTS] 🔍 Запрос истории:", historyUrl)

        tts.utils:HTTPQueue({
            url = historyUrl,
            method = "GET",
            timeout = 10,
            success = function(c, b)
                if completed then
                    self.utils:LogDebug("[ComfyUI_TTS] ⏳ Уже завершено, пропускаем ответ")
                    return
                end

                self.utils:LogDebug("[ComfyUI_TTS] ✅ Ответ истории, код:", c)
                local ok, data = pcall(util.JSONToTable, b)
                if ok and data and data[promptId] then
                    local history = data[promptId]
                    if history.outputs then
                        for nodeId, output in pairs(history.outputs) do
                            if output.audio and output.audio[1] then
                                local fileInfo = output.audio[1]
                                if fileInfo and fileInfo.filename then
                                    self.utils:LogDebug("[ComfyUI_TTS] 🎵 Найден аудиофайл:", fileInfo.filename)
                                    local audioUrl = url .. "/view"
									audioUrl = audioUrl .. "?filename=" .. tts.utils:URLEncode(fileInfo.filename)
									if fileInfo.subfolder and fileInfo.subfolder ~= "" then
										audioUrl = audioUrl .. "&subfolder=" .. tts.utils:URLEncode(fileInfo.subfolder)
									end
									if fileInfo.type and fileInfo.type ~= "" then
										audioUrl = audioUrl .. "&type=" .. tts.utils:URLEncode(fileInfo.type)
									end

                                    self.utils:LogDebug("[ComfyUI_TTS] 🎵 URL аудио:", audioUrl)
                                    self:SetCached(cacheKey, audioUrl)
                                    completed = true
                                    tts._activeRequests = math.max(0, tts._activeRequests - 1)
                                    self.utils:LogDebug("[ComfyUI_TTS] 📊 Активных запросов теперь:", tts._activeRequests)
                                    if callback then
                                        callback(audioUrl, nil)
                                    end
                                    return
                                end
                            end
                        end
                    end
                    if history.status and history.status.completed then
                        self.utils:LogDebug("[ComfyUI_TTS] ℹ️ Статус completed, но аудио не найдено")
                        completed = true
                        tts._activeRequests = math.max(0, tts._activeRequests - 1)
                        if callback then callback(nil, "Аудио не найдено") end
                        return
                    end
                else
                    self.utils:LogDebug("[ComfyUI_TTS] ⚠️ Нет данных в истории")
                end
                timer.Simple(1.0, checkTTS)
            end,
            error = function(err)
                if not completed then
                    self.utils:LogDebug("[ComfyUI_TTS] ❌ Ошибка запроса истории:", err)
                    timer.Simple(2.0, checkTTS)
                end
            end
        })
    end

    timer.Simple(1.0, checkTTS)
    self.utils:LogDebug("[ComfyUI_TTS] ⏳ Первая проверка запланирована через 1 секунду")
end

local ElevenLabs_TTS = {}
ElevenLabs_TTS.__index = ElevenLabs_TTS
setmetatable(ElevenLabs_TTS, TTSProvider)

function ElevenLabs_TTS:new(config, ttsService)
    self.utils:LogDebug("[ElevenLabs_TTS] 🔧 Создание ElevenLabs провайдера")
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
            self.utils:LogDebug("[ElevenLabs_TTS] 📍 Голос:", obj.defaultVoice, "Модель:", obj.defaultModel)
        end
    end

    setmetatable(obj, self)
    return obj
end

function ElevenLabs_TTS:GetDisplayName()
    return "ElevenLabs"
end

function ElevenLabs_TTS:ValidateConfig()
    self.utils:LogDebug("[ElevenLabs_TTS] 🔍 Проверка конфига...")
    if not self.config.api_key or self.config.api_key == "" then
        self.utils:LogDebug("[ElevenLabs_TTS] ❌ API ключ отсутствует!")
        return false, "API ключ ElevenLabs не установлен"
    end
    self.utils:LogDebug("[ElevenLabs_TTS] ✅ Конфиг валидный")
    return true, "OK"
end

function ElevenLabs_TTS:GetEndpoint()
    local voice = self.config.voice or self.defaultVoice
    local endpoint = string.format("%s/%s", self.config.endpoint or self.defaultEndpoint, voice)
    self.utils:LogDebug("[ElevenLabs_TTS] 🌐 Endpoint:", endpoint)
    return endpoint
end

function ElevenLabs_TTS:GenerateAudio(text, callback, player)
    self.utils:LogDebug("[ElevenLabs_TTS] 🎵 GenerateAudio вызван!")
    self.utils:LogDebug("[ElevenLabs_TTS] 📝 Текст:", text and string.sub(text, 1, 50) or "nil")

    local tts = self.ttsService
    if not tts or not tts.utils then
        self.utils:LogDebug("[ElevenLabs_TTS] ❌ TTS service или utils недоступны!")
        if callback then callback(nil, "TTS service not available") end
        return
    end

    if not text or text == "" then
        self.utils:LogDebug("[ElevenLabs_TTS] ❌ Пустой текст!")
        if callback then callback(nil, "Пустой текст") end
        return
    end

    local cleanText = tts.utils:CleanForTTS(text)
    self.utils:LogDebug("[ElevenLabs_TTS] 🧹 Очищенный текст:", cleanText and string.sub(cleanText, 1, 50) or "nil")
    if cleanText == "" or cleanText == " " then
        self.utils:LogDebug("[ElevenLabs_TTS] ❌ Текст пуст после очистки!")
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end

    local cacheKey = tts.utils:Hash(cleanText)
    self.utils:LogDebug("[ElevenLabs_TTS] 🔑 Ключ кэша:", cacheKey)
    local cached = self:GetCached(cacheKey)
    if cached then
        self.utils:LogDebug("[ElevenLabs_TTS] ✅ Найдено в кэше!")
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
    self.utils:LogDebug("[ElevenLabs_TTS] ⏱️ Таймаут:", timeout)

    tts.utils:HTTPQueue({
        url = url,
        method = "POST",
        timeout = timeout,
        body = util.TableToJSON(body),
        headers = headers,
        success = function(code, responseBody)
            self.utils:LogDebug("[ElevenLabs_TTS] ✅ Ответ, код:", code)
            if code ~= 200 then
                self.utils:LogDebug("[ElevenLabs_TTS] ❌ HTTP код:", code)
                if callback then callback(nil, "HTTP " .. code) end
                return
            end
            self:SetCached(cacheKey, responseBody)
            if callback then callback(responseBody, nil) end
        end,
        error = function(err)
            self.utils:LogDebug("[ElevenLabs_TTS] ❌ Ошибка соединения:", err)
            if callback then callback(nil, tostring(err)) end
        end
    })
end

local GoogleTTS_TTS = {}
GoogleTTS_TTS.__index = GoogleTTS_TTS
setmetatable(GoogleTTS_TTS, TTSProvider)

function GoogleTTS_TTS:new(config, ttsService)
    self.utils:LogDebug("[GoogleTTS_TTS] 🔧 Создание Google Cloud TTS провайдера")
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
            self.utils:LogDebug("[GoogleTTS_TTS] 📍 Голос:", obj.defaultVoice, "Язык:", obj.defaultLanguage)
        end
    end

    setmetatable(obj, self)
    return obj
end

function GoogleTTS_TTS:GetDisplayName()
    return "Google Cloud TTS"
end

function GoogleTTS_TTS:ValidateConfig()
    self.utils:LogDebug("[GoogleTTS_TTS] 🔍 Проверка конфига...")
    if not self.config.api_key or self.config.api_key == "" then
        self.utils:LogDebug("[GoogleTTS_TTS] ❌ API ключ отсутствует!")
        return false, "API ключ Google Cloud не установлен"
    end
    self.utils:LogDebug("[GoogleTTS_TTS] ✅ Конфиг валидный")
    return true, "OK"
end

function GoogleTTS_TTS:GetEndpoint()
    return self.config.endpoint or self.defaultEndpoint
end

function GoogleTTS_TTS:GenerateAudio(text, callback, player)
    self.utils:LogDebug("[GoogleTTS_TTS] 🎵 GenerateAudio вызван!")
    self.utils:LogDebug("[GoogleTTS_TTS] 📝 Текст:", text and string.sub(text, 1, 50) or "nil")

    local tts = self.ttsService
    if not tts or not tts.utils then
        self.utils:LogDebug("[GoogleTTS_TTS] ❌ TTS service или utils недоступны!")
        if callback then callback(nil, "TTS service not available") end
        return
    end

    if not text or text == "" then
        self.utils:LogDebug("[GoogleTTS_TTS] ❌ Пустой текст!")
        if callback then callback(nil, "Пустой текст") end
        return
    end

    local cleanText = tts.utils:CleanForTTS(text)
    self.utils:LogDebug("[GoogleTTS_TTS] 🧹 Очищенный текст:", cleanText and string.sub(cleanText, 1, 50) or "nil")
    if cleanText == "" or cleanText == " " then
        self.utils:LogDebug("[GoogleTTS_TTS] ❌ Текст пуст после очистки!")
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end

    local cacheKey = tts.utils:Hash(cleanText)
    self.utils:LogDebug("[GoogleTTS_TTS] 🔑 Ключ кэша:", cacheKey)
    local cached = self:GetCached(cacheKey)
    if cached then
        self.utils:LogDebug("[GoogleTTS_TTS] ✅ Найдено в кэше!")
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
    self.utils:LogDebug("[GoogleTTS_TTS] ⏱️ Таймаут:", timeout)

    tts.utils:HTTPQueue({
        url = url,
        method = "POST",
        timeout = timeout,
        body = util.TableToJSON(body),
        headers = { ["Content-Type"] = "application/json" },
        success = function(code, responseBody)
            self.utils:LogDebug("[GoogleTTS_TTS] ✅ Ответ, код:", code)
            if code ~= 200 then
                self.utils:LogDebug("[GoogleTTS_TTS] ❌ HTTP код:", code)
                if callback then callback(nil, "HTTP " .. code) end
                return
            end
            local ok, data = pcall(util.JSONToTable, responseBody)
            if not ok or not data or not data.audioContent then
                self.utils:LogDebug("[GoogleTTS_TTS] ❌ Неверный формат ответа")
                if callback then callback(nil, "Неверный формат ответа") end
                return
            end
            local audioData = util.Base64Decode(data.audioContent)
            self.utils:LogDebug("[GoogleTTS_TTS] ✅ Аудио декодировано, размер:", #audioData)
            self:SetCached(cacheKey, audioData)
            if callback then callback(audioData, nil) end
        end,
        error = function(err)
            self.utils:LogDebug("[GoogleTTS_TTS] ❌ Ошибка соединения:", err)
            if callback then callback(nil, tostring(err)) end
        end
    })
end

local YandexTTS = {}
YandexTTS.__index = YandexTTS
setmetatable(YandexTTS, TTSProvider)

function YandexTTS:new(config, ttsService)
    self.utils:LogDebug("[YandexTTS] 🔧 Создание Yandex SpeechKit провайдера")
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
            self.utils:LogDebug("[YandexTTS] 📍 Голос:", obj.defaultVoice, "Язык:", obj.defaultLang)
        end
    end

    setmetatable(obj, self)
    return obj
end

function YandexTTS:GetDisplayName()
    return "Yandex SpeechKit"
end

function YandexTTS:ValidateConfig()
    self.utils:LogDebug("[YandexTTS] 🔍 Проверка конфига...")
    if not self.config.api_key or self.config.api_key == "" then
        self.utils:LogDebug("[YandexTTS] ❌ IAM-токен отсутствует!")
        return false, "IAM-токен Yandex Cloud не установлен"
    end
    if not self.config.folder_id or self.config.folder_id == "" then
        self.utils:LogDebug("[YandexTTS] ❌ Folder ID отсутствует!")
        return false, "Folder ID Yandex Cloud не установлен"
    end
    self.utils:LogDebug("[YandexTTS] ✅ Конфиг валидный")
    return true, "OK"
end

function YandexTTS:GetEndpoint()
    return self.config.endpoint or self.defaultEndpoint
end

function YandexTTS:GenerateAudio(text, callback, player)
    self.utils:LogDebug("[YandexTTS] 🎵 GenerateAudio вызван!")
    self.utils:LogDebug("[YandexTTS] 📝 Текст:", text and string.sub(text, 1, 50) or "nil")

    local tts = self.ttsService
    if not tts or not tts.utils then
        self.utils:LogDebug("[YandexTTS] ❌ TTS service или utils недоступны!")
        if callback then callback(nil, "TTS service not available") end
        return
    end

    if not text or text == "" then
        self.utils:LogDebug("[YandexTTS] ❌ Пустой текст!")
        if callback then callback(nil, "Пустой текст") end
        return
    end

    local cleanText = tts.utils:CleanForTTS(text)
    self.utils:LogDebug("[YandexTTS] 🧹 Очищенный текст:", cleanText and string.sub(cleanText, 1, 50) or "nil")
    if cleanText == "" or cleanText == " " then
        self.utils:LogDebug("[YandexTTS] ❌ Текст пуст после очистки!")
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end

    local cacheKey = tts.utils:Hash(cleanText)
    self.utils:LogDebug("[YandexTTS] 🔑 Ключ кэша:", cacheKey)
    local cached = self:GetCached(cacheKey)
    if cached then
        self.utils:LogDebug("[YandexTTS] ✅ Найдено в кэше!")
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
    self.utils:LogDebug("[YandexTTS] ⏱️ Таймаут:", timeout)

    tts.utils:HTTPQueue({
        url = url,
        method = "POST",
        timeout = timeout,
        body = body,
        headers = headers,
        success = function(code, responseBody)
            self.utils:LogDebug("[YandexTTS] ✅ Ответ, код:", code)
            if code ~= 200 then
                self.utils:LogDebug("[YandexTTS] ❌ HTTP код:", code)
                if callback then callback(nil, "HTTP " .. code) end
                return
            end
            self.utils:LogDebug("[YandexTTS] ✅ Аудио получено, размер:", #responseBody)
            self:SetCached(cacheKey, responseBody)
            if callback then callback(responseBody, nil) end
        end,
        error = function(err)
            self.utils:LogDebug("[YandexTTS] ❌ Ошибка соединения:", err)
            if callback then callback(nil, tostring(err)) end
        end
    })
end

local VKTTS = {}
VKTTS.__index = VKTTS
setmetatable(VKTTS, TTSProvider)

function VKTTS:new(config, ttsService)
    self.utils:LogDebug("[VKTTS] 🔧 Создание VK Cloud Voice провайдера")
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
            self.utils:LogDebug("[VKTTS] 📍 Голос:", obj.defaultVoice, "Encoder:", obj.defaultEncoder)
        end
    end

    setmetatable(obj, self)
    return obj
end

function VKTTS:GetDisplayName()
    return "VK Cloud Voice"
end

function VKTTS:ValidateConfig()
    self.utils:LogDebug("[VKTTS] 🔍 Проверка конфига...")
    if not self.config.api_key or self.config.api_key == "" then
        self.utils:LogDebug("[VKTTS] ❌ Токен доступа отсутствует!")
        return false, "Токен доступа VK Cloud не установлен"
    end
    self.utils:LogDebug("[VKTTS] ✅ Конфиг валидный")
    return true, "OK"
end

function VKTTS:GetEndpoint()
    return self.config.endpoint or self.defaultEndpoint
end

function VKTTS:GenerateAudio(text, callback, player)
    self.utils:LogDebug("[VKTTS] 🎵 GenerateAudio вызван!")
    self.utils:LogDebug("[VKTTS] 📝 Текст:", text and string.sub(text, 1, 50) or "nil")

    local tts = self.ttsService
    if not tts or not tts.utils then
        self.utils:LogDebug("[VKTTS] ❌ TTS service или utils недоступны!")
        if callback then callback(nil, "TTS service not available") end
        return
    end

    if not text or text == "" then
        self.utils:LogDebug("[VKTTS] ❌ Пустой текст!")
        if callback then callback(nil, "Пустой текст") end
        return
    end

    local cleanText = tts.utils:CleanForTTS(text)
    self.utils:LogDebug("[VKTTS] 🧹 Очищенный текст:", cleanText and string.sub(cleanText, 1, 50) or "nil")
    if cleanText == "" or cleanText == " " then
        self.utils:LogDebug("[VKTTS] ❌ Текст пуст после очистки!")
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end

    local cacheKey = tts.utils:Hash(cleanText)
    self.utils:LogDebug("[VKTTS] 🔑 Ключ кэша:", cacheKey)
    local cached = self:GetCached(cacheKey)
    if cached then
        self.utils:LogDebug("[VKTTS] ✅ Найдено в кэше!")
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
    self.utils:LogDebug("[VKTTS] ⏱️ Таймаут:", timeout)

    tts.utils:HTTPQueue({
        url = url,
        method = "GET",
        timeout = timeout,
        headers = headers,
        success = function(code, responseBody)
            self.utils:LogDebug("[VKTTS] ✅ Ответ, код:", code)
            if code ~= 200 then
                self.utils:LogDebug("[VKTTS] ❌ HTTP код:", code)
                if callback then callback(nil, "HTTP " .. code) end
                return
            end
            self.utils:LogDebug("[VKTTS] ✅ Аудио получено, размер:", #responseBody)
            self:SetCached(cacheKey, responseBody)
            if callback then callback(responseBody, nil) end
        end,
        error = function(err)
            self.utils:LogDebug("[VKTTS] ❌ Ошибка соединения:", err)
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
    self.utils:LogDebug("[TTS] 🔧 CreateProvider вызван: providerType=", providerType)
    local providerClass = TTS_PROVIDERS[providerType]
    if not providerClass then
        self.utils:LogDebug("[TTS] ❌ Неизвестный провайдер:", providerType)
        return nil, "Неизвестный провайдер TTS: " .. tostring(providerType)
    end
    local provider = providerClass:new(config or {}, self)
    self.utils:LogDebug("[TTS] ✅ Провайдер создан:", provider:GetDisplayName())
    return provider
end

function TTS:GetAvailableProviders()
    self.utils:LogDebug("[TTS] 📋 GetAvailableProviders вызван")
    local list = {}
    if self.config and self.config:get("Providers") then
        list = self.config:get("Providers").TTS.List or {}
    else
        list = {
            { id = "comfyui", name = "ComfyUI (локальный)", needsKey = false },
            { id = "elevenlabs", name = "ElevenLabs", needsKey = true },
            { id = "google", name = "Google Cloud TTS", needsKey = true },
            { id = "yandex", name = "Yandex SpeechKit", needsKey = true, needsFolder = true },
            { id = "vk", name = "VK Cloud Voice", needsKey = true },
        }
    end
    self.utils:LogDebug("[TTS] 📋 Доступно провайдеров:", #list)
    return list
end

function TTS:GetProvider(ply)
    self.utils:LogDebug("[TTS] 🔍 GetProvider вызван для игрока:", ply and ply:Nick() or "nil")

    if not self.utils or not self.utils:IsValid(ply) then
        self.utils:LogDebug("[TTS] ❌ Игрок невалидный!")
        return nil
    end

    local ttsEnabled = self:GetState("TTS_Enabled", false)
    self.utils:LogDebug("[TTS] 🔍 TTS_Enabled:", ttsEnabled)
    if not ttsEnabled then
        self.utils:LogDebug("[TTS] ❌ TTS отключён!")
        return nil
    end

    local ttsMode = self:GetSetting("TTS_Mode", "local")
    self.utils:LogDebug("[TTS] 🔍 TTS_Mode:", ttsMode)

    if ttsMode == "local" then
        self.utils:LogDebug("[TTS] 🔧 Создаём локальный провайдер (ComfyUI)")
        local config = {
            endpoint = self:GetTTSURL(),
            debug = self:GetSetting("Debug_Mode", false),
        }
        return self:CreateProvider("comfyui", config)

    elseif ttsMode == "cloud" then
        local providerType = self:GetSetting("TTS_Provider", "elevenlabs")
        self.utils:LogDebug("[TTS] 🔧 Создаём облачный провайдер:", providerType)
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

    self.utils:LogDebug("[TTS] ❌ Неизвестный режим TTS:", ttsMode)
    return nil
end

function TTS:Generate(ply, text, callback)
    self.utils:LogDebug("[TTS] 🚀 Generate вызван!")
    self.utils:LogDebug("[TTS] 👤 Игрок:", ply and ply:Nick() or "nil")
    self.utils:LogDebug("[TTS] 📝 Текст:", text and string.sub(text, 1, 50) or "nil")
    self.utils:LogDebug("[TTS] 📝 Тип текста:", type(text))
    self.utils:LogDebug("[TTS] 📝 Адрес текста в памяти:", text)

    if not self.utils or not self.utils:IsValid(ply) then
        self.utils:LogDebug("[TTS] ❌ Player invalid!")
        if callback then callback(nil, "Player invalid") end
        return
    end

    if not text or text == "" then
        self.utils:LogDebug("[TTS] ❌ Пустой текст!")
        if callback then callback(nil, "Пустой текст") end
        return
    end

    if type(text) ~= "string" then
        self.utils:LogDebug("[TTS] ❌ Текст не строка! Тип:", type(text))
        text = tostring(text) or ""
        self.utils:LogDebug("[TTS] 🔄 Приведён к строке:", text)
    end

    local originalText = text
    self.utils:LogDebug("[TTS] 📝 originalText:", originalText)

    if not self:GetState("TTS_Enabled", false) then
        self.utils:LogDebug("[TTS] ❌ TTS отключён в state!")
        if callback then callback(nil, "TTS отключён") end
        return
    end

    local provider = self:GetProvider(ply)
    if not provider then
        self.utils:LogDebug("[TTS] ❌ TTS провайдер не найден!")
        if callback then callback(nil, "TTS провайдер не найден") end
        return
    end

    local valid, err = provider:ValidateConfig()
    if not valid then
        self.utils:LogDebug("[TTS] ❌ Конфиг провайдера невалидный:", err)
        if callback then callback(nil, err) end
        return
    end

    self.utils:LogDebug("[TTS] 🧹 Вызов CleanForTTS с текстом:", originalText)
    local cleanText = self.utils:CleanForTTS(originalText)
    self.utils:LogDebug(tostring("[TTS] 🧹 Очищенный текст: '" .. (cleanText or "nil") .. "'"))
    self.utils:LogDebug("[TTS] 🧹 Длина очищенного текста:", cleanText and #cleanText or 0)
    self.utils:LogDebug("[TTS] 🧹 Тип очищенного текста:", type(cleanText))

    if not cleanText or cleanText == "" or cleanText == " " then
        self.utils:LogDebug("[TTS] ❌ Текст пуст после очистки!")
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end

    self.utils:LogDebug("[TTS] 🎵 Вызов provider:GenerateAudio с текстом:", cleanText)
    provider:GenerateAudio(cleanText, function(audioData, err)
        if err then
            self.utils:LogDebug("[TTS] ❌ Ошибка генерации аудио:", err)
            if callback then callback(nil, err) end
            return
        end

        if audioData then
            self.utils:LogDebug("[TTS] ✅ Аудио получено, отправка клиенту")
            self:SendAudio(ply, audioData)
            if callback then callback(audioData, nil) end
        else
            self.utils:LogDebug("[TTS] ❌ Нет аудио данных")
            if callback then callback(nil, "Нет аудио данных") end
        end
    end, ply)
end

function TTS:SendAudio(ply, audioUrl)
    self.utils:LogDebug("[TTS] 📤 SendAudio вызван для:", ply and ply:Nick() or "nil")
    self.utils:LogDebug("[TTS] 📤 URL:", audioUrl)

    if not self.utils or not self.utils:IsValid(ply) then
        self.utils:LogDebug("[TTS] ❌ Player invalid!")
        return
    end
    if not audioUrl or audioUrl == "" then
        self.utils:LogDebug("[TTS] ❌ URL пустой!")
        return
    end

    local locator = _G.AI_GetLocator()
    if locator and locator:has("shared") then
        local shared = locator:get("shared")
        self.utils:LogDebug("[TTS] 📤 Отправка через shared сервис")
        shared:SendAudioURL(ply, audioUrl)
    else
        self.utils:LogDebug("[TTS] ⚠️ Shared сервис не найден, отправляем напрямую")
        net.Start("AI_Companion_PlayAudio")
        net.WriteString(audioUrl)
        net.Send(ply)
    end
    self.utils:LogDebug("[TTS] ✅ Аудио отправлено")
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
    self.utils:LogDebug("[TTS] 📋 GetPlayerWorkflow вызван для:", ply and ply:Nick() or "nil")

    if not self.utils or not self.utils:IsValid(ply) then
        self.utils:LogDebug("[TTS] ❌ Игрок невалидный!")
        return nil
    end

    local enabled = self:GetSetting("TTS_Workflow_Enabled", false)
    self.utils:LogDebug("[TTS] 📋 TTS_Workflow_Enabled:", enabled)
    if not enabled then
        self.utils:LogDebug("[TTS] 📋 Workflow отключён")
        return nil
    end

    local workflow = self:GetSetting("TTS_Workflow", nil)
    if not workflow or type(workflow) ~= "table" then
        self.utils:LogDebug("[TTS] ⚠️ Workflow не загружен или не таблица")
        return nil
    end

    self.utils:LogDebug("[TTS] ✅ Workflow загружен, размер:", table.Count(workflow))
    return workflow
end

function TTS:ConvertUIWorkflowToAPI(workflow)
    self.utils:LogDebug("[TTS] 🔄 ConvertUIWorkflowToAPI вызван")

    if not workflow then
        self.utils:LogDebug("[TTS] ❌ Workflow is nil")
        return nil, "Workflow is nil"
    end

    if not workflow.nodes then
        self.utils:LogDebug("[TTS] 🔍 Workflow без nodes, проверяем API формат")

        local isApiFormat = false
        for k, v in pairs(workflow) do
            if type(v) == "table" and v.class_type then
                isApiFormat = true
                break
            end
        end
        if isApiFormat then
            self.utils:LogDebug("[TTS] ✅ Workflow уже в API формате")
            return workflow, nil
        else
            self.utils:LogDebug("[TTS] ❌ Неизвестный формат workflow")
            return nil, "Неизвестный формат workflow"
        end
    end

    self.utils:LogDebug("[TTS] 📋 Количество нод:", #workflow.nodes)
    local apiPrompt = {}
    local links = {}

    if workflow.links and type(workflow.links) == "table" then
        self.utils:LogDebug("[TTS] 🔗 Количество связей:", #workflow.links)
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
        self.utils:LogDebug("[TTS] 🔗 Связей обработано:", table.Count(links))
    end

    for _, node in ipairs(workflow.nodes) do
        if not node.id then
            self.utils:LogDebug("[TTS] ⚠️ Нода без id, пропускаем")
            continue
        end
        local nodeId = tostring(node.id)
        local nodeType = node.type or "Unknown"
        self.utils:LogDebug(tostring("[TTS] 📦 Нода #" .. nodeId .. ": " .. nodeType))

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
                    self.utils.LogWarn("TTS", "Нет маппинга виджетов для ноды типа '%s'", nodeType)
                end
                self.utils:LogDebug("[TTS] ⚠️ Нет маппинга виджетов для типа:", nodeType)
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

    self.utils:LogDebug("[TTS] ✅ Конвертация завершена, нод в API:", table.Count(apiPrompt))
    return apiPrompt, nil
end

function TTS:FindTextFieldInNode(node, nodeType)
    self.utils:LogDebug("[TTS] 🔍 FindTextFieldInNode для типа:", nodeType)

    if not node or not node.inputs then
        self.utils:LogDebug("[TTS] ⚠️ Нет inputs")
        return nil, nil
    end

    local specialRule = NODE_SPECIAL_RULES[nodeType]
    if specialRule then
        if specialRule.textField and node.inputs[specialRule.textField] ~= nil then
            self.utils:LogDebug("[TTS] ✅ Найдено по спецправилу:", specialRule.textField)
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
            self.utils:LogDebug("[TTS] ✅ Найдено по скору:", candidate.name, "скор:", candidate.score)
            return candidate.name, "auto"
        end
    end

    for fieldName, value in pairs(node.inputs) do
        if type(value) == "string" and
           string.find(string.lower(fieldName), "text") and
           not string.find(string.lower(fieldName), "ref") then
            self.utils:LogDebug("[TTS] ✅ Найдено по fallback:", fieldName)
            return fieldName, "fallback_text"
        end
    end

    self.utils:LogDebug("[TTS] ❌ Не найдено подходящее поле")
    return nil, nil
end

function TTS:InjectTextIntoPrompt(prompt, text)
    self.utils:LogDebug("[TTS] 📝 InjectTextIntoPrompt вызван")
    self.utils:LogDebug("[TTS] 📝 Текст:", text and string.sub(text, 1, 50) or "nil")

    if not prompt then
        self.utils:LogDebug("[TTS] ❌ Prompt is nil")
        return nil
    end

    local result = util.TableToJSON(prompt)
    if not result then
        self.utils:LogDebug("[TTS] ❌ Ошибка сериализации prompt")
        return nil
    end

    local ok, injected = pcall(util.JSONToTable, result)
    if not ok or not injected then
        self.utils:LogDebug("[TTS] ❌ Ошибка десериализации prompt")
        return nil
    end

    local textNodeFound = false
    local injectedCount = 0

    for nodeId, node in pairs(injected) do
        if node.inputs then
            local fieldName, method = self:FindTextFieldInNode(node, node.class_type)
            if fieldName then
                self.utils:LogDebug("[TTS] 📝 Вставляем текст в ноду", nodeId, "поле:", fieldName)
                node.inputs[fieldName] = text
                textNodeFound = true
                injectedCount = injectedCount + 1
            end
        end
    end

    if not textNodeFound then
        self.utils:LogDebug("[TTS] ❌ Не найдено подходящее текстовое поле ни в одной ноде")
        if self.utils then
            self.utils.LogWarn("TTS", "Не найдено подходящее текстовое поле ни в одной ноде")
        end
        return nil
    end

    self.utils:LogDebug("[TTS] ✅ Текст вставлен в", injectedCount, "нод")
    return injected
end

function TTS:InjectTextIntoWorkflow(workflow, text)
    self.utils:LogDebug("[TTS] 📝 InjectTextIntoWorkflow вызван")

    if not workflow then
        self.utils:LogDebug("[TTS] ❌ Workflow is nil")
        return nil
    end

    local apiPrompt, err = self:ConvertUIWorkflowToAPI(workflow)
    if not apiPrompt then
        self.utils:LogDebug("[TTS] ❌ Ошибка конвертации workflow:", err)
        return nil
    end

    return self:InjectTextIntoPrompt(apiPrompt, text)
end

function TTS:SetupNetMessages()
    if not SERVER then return end
    self.utils:LogDebug("[TTS] 📡 Регистрация сетевых сообщений")
    util.AddNetworkString("AI_Companion_PlayAudio")
    util.AddNetworkString("AI_TTS_Request")
    self.utils:LogDebug("[TTS] ✅ Сетевые сообщения зарегистрированы")
end

function TTS:SetupCommands()
    if not SERVER then return end
    self.utils:LogDebug("[TTS] 🖥️ Регистрация консольных команд")

	concommand.Add("ai_test_tts", function(ply)
		self.utils:LogDebug("[TTS] ⚡ ai_test_tts вызвана!")
		if not self.utils or not self.utils:IsValid(ply) then
			self.utils:LogDebug("[TTS] ❌ Player invalid!")
			return
		end
		if not ply:IsAdmin() then
			self.utils:LogDebug("[TTS] ❌ Не админ!")
			ply:ChatPrint("[AI] Только администраторы!")
			return
		end

		local ip = self:GetSetting("TTS_IP", "127.0.0.1")
		local port = self:GetSetting("TTS_Port", 8188)
		local url = "http://" .. ip .. ":" .. port

		self.utils:LogDebug("[AI TTS TEST] ═══════════════════════════════════════════")
		self.utils:LogDebug("[AI TTS TEST] ПРОВЕРКА ПОДКЛЮЧЕНИЯ К TTS (ComfyUI)")
		self.utils:LogDebug("[AI TTS TEST] URL: " .. url)
		ply:ChatPrint("[AI] Проверка TTS (ComfyUI) на " .. url .. "...")

		local checkUrl = url
		if string.sub(checkUrl, -1) ~= "/" then
			checkUrl = checkUrl .. "/"
		end
		checkUrl = checkUrl .. "system_stats"
		self.utils:LogDebug("[AI TTS TEST] Проверка URL:", checkUrl)

		HTTP({
			url = checkUrl,
			method = "GET",
			timeout = 5,
			success = function(code, body)
				self.utils:LogDebug("[AI TTS TEST] ✅ Ответ, код:", code)
				if code == 200 then
					local msg = "ComfyUI доступен! (HTTP " .. code .. ")"
					ply:ChatPrint("[AI] " .. msg)
					self.utils:LogDebug("[AI TTS TEST] " .. msg)
				else
					local msg = "ComfyUI ответил с кодом: " .. code
					ply:ChatPrint("[AI] " .. msg)
					self.utils:LogDebug("[AI TTS TEST] " .. msg)
				end
				self.utils:LogDebug("[AI TTS TEST] ═══════════════════════════════════════")
			end,
			failed = function(err)
				self.utils:LogDebug("[AI TTS TEST] ❌ Ошибка:", err)
				local msg = "ComfyUI недоступен! " .. tostring(err)
				ply:ChatPrint("[AI] " .. msg)
				self.utils:LogDebug("[AI TTS TEST] " .. msg)
				self.utils:LogDebug("[AI TTS TEST] Проверьте ComfyUI на " .. ip .. ":" .. port)
				self.utils:LogDebug("[AI TTS TEST] ═══════════════════════════════════════")
			end
		})
	end)

    concommand.Add("ai_tts_status", function(ply)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_status вызвана!")
        if not self.utils or not self.utils:IsValid(ply) then return end

        local ttsEnabled = self:GetState("TTS_Enabled", false)
        local globalTTS = self:GetSetting("Global_TTS_Enabled", false)
        local ttsMode = self:GetSetting("TTS_Mode", "local")
        local url = self:GetTTSURL()
        local provider = self:GetSetting("TTS_Provider", "elevenlabs")

        self.utils:LogDebug("[AI] === СТАТУС TTS ===")
        self.utils:LogDebug("[AI] Глобальный TTS:", ttsEnabled and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН")
        self.utils:LogDebug("[AI] Global_TTS_Enabled:", globalTTS and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН")
        self.utils:LogDebug("[AI] Режим:", ttsMode == "local" and "Локальный (ComfyUI)" or "Облачный (" .. provider .. ")")
        self.utils:LogDebug("[AI] URL:", url)

        ply:ChatPrint("[AI] === СТАТУС TTS ===")
        ply:ChatPrint("[AI] Глобальный TTS: " .. (ttsEnabled and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"))
        ply:ChatPrint("[AI] Режим: " .. (ttsMode == "local" and "Локальный (ComfyUI)" or "Облачный (" .. provider .. ")"))
        ply:ChatPrint("[AI] URL: " .. url)
    end)

    concommand.Add("ai_tts_global_on", function(ply)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_global_on вызвана!")

        if not self.utils or not self.utils:IsValid(ply) then
            self.utils:LogDebug("[TTS] ❌ Player invalid!")
            return
        end

        if not ply:IsAdmin() then
            self.utils:LogDebug("[TTS] ❌ Не админ!")
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Только администраторы!")
            end
            return
        end

        if self.state then
            self.utils:LogDebug("[TTS] 📝 Установка TTS_Enabled = true в state")
            self.state:setState("TTS_Enabled", true)
            self.state:setSetting("Global_TTS_Enabled", true)
            self.state:setSetting("TTS_Enabled", true)
            self.state:setState("Global_TTS_Enabled", true)

            self.state:MarkDirty()
            if self.state.SaveToFile then
                self.state:SaveToFile()
            end
        end

        self.utils:LogDebug("[AI] TTS включен глобально")
        if self.utils and self.utils:IsValid(ply) then
            ply:ChatPrint("[AI] TTS включен глобально")
        end

        local locator = _G.AI_GetLocator()
        if locator and locator:has("shared") then
            local shared = locator:get("shared")
            shared:SyncTTStatus(true)
            self.utils:LogDebug("[TTS] 📡 Статус разослан всем клиентам")
        else

            if SERVER then
                net.Start("AI_TTS_Global_Status")
                net.WriteBool(true)
                net.Broadcast()
                self.utils:LogDebug("[TTS] 📡 Статус разослан через net")
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

        self.utils:LogDebug("[TTS] ✅ TTS глобально включён")
    end)

    concommand.Add("ai_tts_global_off", function(ply)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_global_off вызвана!")

        if not self.utils or not self.utils:IsValid(ply) then
            self.utils:LogDebug("[TTS] ❌ Player invalid!")
            return
        end

        if not ply:IsAdmin() then
            self.utils:LogDebug("[TTS] ❌ Не админ!")
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Только администраторы!")
            end
            return
        end

        if self.state then
            self.utils:LogDebug("[TTS] 📝 Установка TTS_Enabled = false в state")
            self.state:setState("TTS_Enabled", false)
            self.state:setSetting("Global_TTS_Enabled", false)
            self.state:setSetting("TTS_Enabled", false)
            self.state:setState("Global_TTS_Enabled", false)

            self.state:MarkDirty()
            if self.state.SaveToFile then
                self.state:SaveToFile()
            end
        end

        self.utils:LogDebug("[AI] TTS отключен глобально")
        if self.utils and self.utils:IsValid(ply) then
            ply:ChatPrint("[AI] TTS отключен глобально")
        end

        local locator = _G.AI_GetLocator()
        if locator and locator:has("shared") then
            local shared = locator:get("shared")
            shared:SyncTTStatus(false)
            self.utils:LogDebug("[TTS] 📡 Статус разослан всем клиентам")
        else

            if SERVER then
                net.Start("AI_TTS_Global_Status")
                net.WriteBool(false)
                net.Broadcast()
                self.utils:LogDebug("[TTS] 📡 Статус разослан через net")
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

        self.utils:LogDebug("[TTS] ✅ TTS глобально отключён")
    end)

    concommand.Add("ai_tts_toggle", function(ply)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_toggle вызвана!")

        if not self.utils or not self.utils:IsValid(ply) then
            self.utils:LogDebug("[TTS] ❌ Player invalid!")
            return
        end

        if not ply:IsAdmin() then
            self.utils:LogDebug("[TTS] ❌ Не админ!")
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Только администраторы!")
            end
            return
        end

        local currentState = self:GetState("TTS_Enabled", false)
        self.utils:LogDebug("[TTS] 🔄 Текущее состояние TTS:", currentState)

        if currentState then
            RunConsoleCommand("ai_tts_global_off")
        else
            RunConsoleCommand("ai_tts_global_on")
        end
    end)

    concommand.Add("ai_tts_personal", function(ply)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_personal вызвана!")
        if not self.utils or not self.utils:IsValid(ply) then return end

        local globalEnabled = self:GetState("TTS_Enabled", false)
        if not globalEnabled then
            self.utils:LogDebug("[TTS] ❌ TTS отключен администратором!")
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] TTS отключен администратором!")
            end
            return
        end

        local current = self:GetSetting("TTS_Personal", true)
        local newValue = not current
        self.utils:LogDebug("[TTS] 🔄 TTS_Personal:", current, "->", newValue)

        if self.state then
            self.state:setSetting("TTS_Personal", newValue)
            self.state:MarkDirty()
            if self.state.SaveToFile then
                self.state:SaveToFile()
            end
        end

        local locator = _G.AI_GetLocator()
        if locator and locator:has("shared") and self.utils and self.utils:IsValid(ply) then
            locator:get("shared"):SyncConfigToClient(ply)
        end

        local state = newValue and "ВКЛ" or "ВЫКЛ"
        if self.utils and self.utils:IsValid(ply) then
            ply:ChatPrint("[AI] Персональный TTS: " .. state)
        end
        self.utils:LogDebug("[TTS] ✅ Персональный TTS:", state)
    end)

    self.utils:LogDebug("[TTS] ✅ Консольные команды зарегистрированы")
end

function TTS:SetupWorkflowCommands()
    if not SERVER then return end
    self.utils:LogDebug("[TTS] 🖥️ Регистрация workflow команд")

    concommand.Add("ai_tts_workflow_load", function(ply, cmd, args)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_workflow_load вызвана!")
        if not self.utils or not self.utils:IsValid(ply) then
            self.utils:LogDebug("[TTS] ❌ Player invalid!")
            return
        end
        if not ply:IsAdmin() then
            self.utils:LogDebug("[TTS] ❌ Не админ!")
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end

        if #args < 1 then
            self.utils:LogDebug("[TTS] ❌ Нет аргументов!")
            ply:ChatPrint("[AI] Использование: ai_tts_workflow_load <путь_к_json>")
            return
        end

        local filePath = args[1]
        self.utils:LogDebug("[TTS] 📁 Путь к файлу:", filePath)
        local data = file.Read(filePath, "DATA")
        if not data then
            self.utils:LogDebug("[TTS] ❌ Не удалось прочитать файл!")
            ply:ChatPrint("[AI] Не удалось прочитать файл: " .. filePath)
            return
        end
        self.utils:LogDebug("[TTS] 📁 Файл прочитан, размер:", #data)

        local ok, workflow = pcall(util.JSONToTable, data)
        if not ok or not workflow then
            self.utils:LogDebug("[TTS] ❌ Ошибка парсинга JSON!")
            ply:ChatPrint("[AI] Ошибка парсинга JSON")
            return
        end
        self.utils:LogDebug("[TTS] ✅ JSON распарсен")

        local apiPrompt, err = self:ConvertUIWorkflowToAPI(workflow)
        if not apiPrompt then
            self.utils:LogDebug("[TTS] ❌ Ошибка конвертации workflow:", err)
            ply:ChatPrint("[AI] Ошибка конвертации workflow: " .. tostring(err))
            return
        end
        self.utils:LogDebug("[TTS] ✅ Workflow сконвертирован, нод:", table.Count(apiPrompt))

        local hasTTSNode = false
        for nodeId, node in pairs(apiPrompt) do
            if node.class_type == "OmniVoiceVoiceCloneTTS" then
                hasTTSNode = true
                self.utils:LogDebug("[TTS] 🎵 Найдена TTS нода:", nodeId)
                break
            end
        end
        if not hasTTSNode then
            self.utils:LogDebug("[TTS] ⚠️ Workflow не содержит OmniVoiceVoiceCloneTTS ноду")
            ply:ChatPrint("[AI] Workflow не содержит OmniVoiceVoiceCloneTTS ноду")
        end

        if self.state then
            self.utils:LogDebug("[TTS] 💾 Сохранение workflow в state")
            self.state:setSetting("TTS_Workflow", apiPrompt)
            self.state:setSetting("TTS_Workflow_Filename", filePath)
            self.state:setSetting("TTS_Workflow_Enabled", true)
            self.utils:LogDebug("[TTS] ✅ Workflow сохранён в state")
        end

        ply:ChatPrint("[AI] Workflow загружен и сконвертирован: " .. filePath)
        ply:ChatPrint("[AI] Используйте ai_tts_workflow_toggle для включения/выключения")
    end)

	concommand.Add("ai_tts_workflow_toggle", function(ply)
		self.utils:LogDebug("[TTS] ⚡ ai_tts_workflow_toggle вызвана!")
		if not self.utils or not self.utils:IsValid(ply) then return end

		local current = self:GetSetting("TTS_Workflow_Enabled", false)
		local newValue = not current
		self.utils:LogDebug("[TTS] 🔄 TTS_Workflow_Enabled:", current, "->", newValue)

		if self.state then
			self.state:setSetting("TTS_Workflow_Enabled", newValue)

			self.state:SyncSingleSettingToAll("TTS_Workflow_Enabled", newValue)
		end

		local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
		ply:ChatPrint("[AI] Кастомный workflow: " .. state)
		self.utils:LogDebug("[TTS] ✅ Workflow", state)
	end)

    concommand.Add("ai_tts_workflow_reset", function(ply)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_workflow_reset вызвана!")
        if not self.utils or not self.utils:IsValid(ply) then return end

        if self.state then
            self.utils:LogDebug("[TTS] 🗑️ Сброс workflow")
            self.state:setSetting("TTS_Workflow", nil)
            self.state:setSetting("TTS_Workflow_Filename", "")
            self.state:setSetting("TTS_Workflow_Enabled", false)
        end

        ply:ChatPrint("[AI] Workflow сброшен")
        self.utils:LogDebug("[TTS] ✅ Workflow сброшен")
    end)

    concommand.Add("ai_tts_workflow_status", function(ply)
        self.utils:LogDebug("[TTS] ⚡ ai_tts_workflow_status вызвана!")
        if not self.utils or not self.utils:IsValid(ply) then return end

        local filename = self:GetSetting("TTS_Workflow_Filename", "Не загружен")
        local enabled = self:GetSetting("TTS_Workflow_Enabled", false)

        self.utils:LogDebug("[AI] === СТАТУС TTS WORKFLOW ===")
        self.utils:LogDebug("[AI] Файл:", filename)
        self.utils:LogDebug("[AI] Включён:", enabled and "Да" or "Нет")

        ply:ChatPrint("[AI] === СТАТУС TTS WORKFLOW ===")
        ply:ChatPrint("[AI] Файл: " .. filename)
        ply:ChatPrint("[AI] Включён: " .. (enabled and "Да" or "Нет"))
    end)

    self.utils:LogDebug("[TTS] ✅ Workflow команды зарегистрированы")
end

function TTS:GetAPI()
    self.utils:LogDebug("[TTS] 📦 GetAPI вызван")
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
