if AI_COMPANION_TTS_LOADED then return end
AI_COMPANION_TTS_LOADED = true
local AI = _G.AI_COMPANION_DEF
if not AI_Utils then
    include("ai_companion/ai_companion_utils.lua")
end
if not AI_Companion then
    include("ai_companion/ai_companion_core.lua")
end
if not AI_CONFIG then
    include("ai_companion/ai_config.lua")
end
local CACHE_SIZE = AI.Config.Cache.TTS.Size
local CACHE_TTL = AI.Config.Cache.TTS.TTL
local DEFAULT_TIMEOUT = AI.Config.HTTP.DefaultTimeout
local MAX_TTS_CONCURRENT = AI.Config.LLM.MaxTTSConcurrent
if SERVER then
    util.AddNetworkString("AI_Companion_PlayAudio")
end
_G.AI_TTS_Active = _G.AI_TTS_Active or 0
local TTSAudioCache = AI_Utils.CreateCache(CACHE_SIZE, CACHE_TTL)
local TTSProvider = {}
TTSProvider.__index = TTSProvider
function TTSProvider:new(config)
    local obj = {
        config = config or {},
        name = "unknown",
        enabled = true,
        cache = AI_Utils.CreateCache(CACHE_SIZE, CACHE_TTL),
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
function TTSProvider:GenerateAudio(text, callback, player)
    if callback then callback(nil, "Not implemented") end
end
function TTSProvider:GetCached(text)
    local key = AI_Utils.Hash(text)
    return self.cache:get(key)
end
function TTSProvider:SetCached(text, data)
    local key = AI_Utils.Hash(text)
    self.cache:set(key, data)
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
function ConvertUIWorkflowToAPI(workflow)
    if not workflow then return nil, "Workflow is nil" end
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
            return nil, "Неизвестный формат workflow"
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
        if not node.id then continue end
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
                AI_Utils.LogWarn("TTS", "Нет маппинга виджетов для ноды типа '%s'", nodeType)
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
local ComfyUI_TTS = {}
ComfyUI_TTS.__index = ComfyUI_TTS
setmetatable(ComfyUI_TTS, TTSProvider)
function ComfyUI_TTS:new(config)
    local obj = TTSProvider:new(config)
    obj.name = "comfyui"
    obj.defaultEndpoint = AI.Config.GetTTSURL()
    setmetatable(obj, self)
    return obj
end
function ComfyUI_TTS:GetDisplayName()
    return "ComfyUI (локальный TTS)"
end
function ComfyUI_TTS:ValidateConfig()
    local url = self:GetEndpoint()
    if not url or url == "" then
        return false, "ComfyUI URL не настроен"
    end
    return true, "OK"
end
function ComfyUI_TTS:GenerateAudio(text, callback, player)
    if not text or text == "" then
        if callback then callback(nil, "Пустой текст") end
        return
    end
    if not AI_Utils.IsValid(player) then
        if callback then callback(nil, "Player invalid") end
        return
    end
    if _G.AI_TTS_Active >= MAX_TTS_CONCURRENT then
        if callback then callback(nil, "Слишком много TTS запросов") end
        return
    end
    local cleanText = AI_Utils.CleanForTTS(text)
    if cleanText == "" or cleanText == " " then
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end
    local cacheKey = AI_Utils.Hash(cleanText)
    local cached = self:GetCached(cacheKey)
    if cached then
        if callback then callback(cached, nil) end
        return
    end
    local workflow = GetPlayerTTSWorkflow(player)
    if not workflow then
        if callback then callback(nil, "Кастомный workflow не загружен или отключён") end
        return
    end
    local apiPrompt, err = ConvertUIWorkflowToAPI(workflow)
    if not apiPrompt then
        if callback then callback(nil, "Ошибка конвертации workflow: " .. tostring(err)) end
        return
    end
    local injectedPrompt = InjectTextIntoPrompt(apiPrompt, cleanText)
    if not injectedPrompt then
        if callback then callback(nil, "Ошибка вставки текста в workflow") end
        return
    end
    self:SendToComfyUI(injectedPrompt, player, cacheKey, callback)
end
function ComfyUI_TTS:SendToComfyUI(prompt, player, cacheKey, callback)
    local url = self:GetEndpoint()
    if not url or url == "" then
        if callback then callback(nil, "ComfyUI URL не настроен") end
        return
    end
    _G.AI_TTS_Active = _G.AI_TTS_Active + 1
    if not prompt or next(prompt) == nil then
        _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
        if callback then callback(nil, "Workflow пустой") end
        return
    end
    if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
        local debugJson = util.TableToJSON(prompt)
        if debugJson then
            file.Write("ai_tts_debug_workflow.json", debugJson)
            print("[AI TTS DEBUG] Workflow сохранён в ai_tts_debug_workflow.json")
            print("[AI TTS DEBUG] Размер: " .. #debugJson .. " байт")
        end
    end
    local requestBody = {
        prompt = prompt,
        client_id = "gmod_" .. tostring(player:SteamID64())
    }
    local jsonBody = util.TableToJSON(requestBody)
    if not jsonBody then
        _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
        if callback then callback(nil, "Ошибка формирования запроса") end
        return
    end
    if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
        print("[AI TTS DEBUG] Отправка запроса в ComfyUI")
        print("[AI TTS DEBUG] URL: " .. url .. "/prompt")
        print("[AI TTS DEBUG] Размер JSON: " .. #jsonBody .. " байт")
        print("[AI TTS DEBUG] JSON превью: " .. jsonBody:sub(1, 500))
    end
    local comfyUrl = url .. "/prompt"
    local timerID = "tts_timeout_" .. tostring(player:SteamID64()) .. "_" .. tostring(os.time())
    if SERVER then
        timer.Create(timerID, 60, 1, function()
            _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
            if callback then callback(nil, "Превышено время ожидания ComfyUI") end
        end)
    end
    HTTP({
        url = comfyUrl,
        method = "POST",
        timeout = 60,
        body = jsonBody,
        success = function(code, body)
            timer.Remove(timerID)
            if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                print("[AI TTS DEBUG] Ответ ComfyUI: code=" .. code)
                print("[AI TTS DEBUG] Body: " .. tostring(body):sub(1, 500))
                if code ~= 200 then
                    file.Write("ai_tts_debug_error.json", tostring(body))
                    print("[AI TTS DEBUG] Ошибка сохранена в ai_tts_debug_error.json")
                end
            end
            if code ~= 200 then
                _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
                if callback then callback(nil, "HTTP " .. code) end
                return
            end
            local ok, data = pcall(util.JSONToTable, body)
            if not ok or not data then
                _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
                if callback then callback(nil, "Ошибка парсинга ответа") end
                return
            end
            if data.error then
                _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
                if callback then callback(nil, "ComfyUI ошибка: " .. tostring(data.error)) end
                return
            end
            if not data.prompt_id then
                _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
                if callback then callback(nil, "Нет prompt_id в ответе") end
                return
            end
            local promptId = data.prompt_id
            if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                print("[AI TTS DEBUG] prompt_id: " .. promptId)
            end
            self:WaitForAudio(promptId, player, cacheKey, callback)
        end,
        failed = function(err)
            timer.Remove(timerID)
            _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
            if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                print("[AI TTS DEBUG] HTTP failed: " .. tostring(err))
            end
            if callback then callback(nil, "Ошибка соединения: " .. tostring(err)) end
        end
    })
end
function ComfyUI_TTS:WaitForAudio(promptId, player, cacheKey, callback)
    local url = self:GetEndpoint()
    local attempts = 0
    local maxAttempts = 60
    local completed = false
    local function checkTTS()
        if completed then return end
        if not AI_Utils.IsValid(player) then
            completed = true
            _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
            if callback then callback(nil, "Player disconnected") end
            return
        end
        attempts = attempts + 1
        if attempts > maxAttempts then
            completed = true
            _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
            if callback then callback(nil, "Превышено время ожидания аудио") end
            return
        end
        local historyUrl = url .. "/history/" .. promptId
        HTTP({
            url = historyUrl,
            method = "GET",
            timeout = 10,
            success = function(c, b)
                if completed then return end
                if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                    print("[AI TTS DEBUG] History check: code " .. c)
                end
                local ok, data = pcall(util.JSONToTable, b)
                if ok and data and data[promptId] then
                    local history = data[promptId]
                    if history.outputs then
                        for nodeId, output in pairs(history.outputs) do
                            if output.audio and output.audio[1] then
                                local fileInfo = output.audio[1]
                                if fileInfo and fileInfo.filename then
                                    local audioUrl = url .. "/view"
                                    audioUrl = audioUrl .. "?filename=" .. URLEncode(fileInfo.filename)
                                    if fileInfo.subfolder and fileInfo.subfolder ~= "" then
                                        audioUrl = audioUrl .. "&subfolder=" .. URLEncode(fileInfo.subfolder)
                                    end
                                    if fileInfo.type and fileInfo.type ~= "" then
                                        audioUrl = audioUrl .. "&type=" .. URLEncode(fileInfo.type)
                                    end
                                    if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                                        print("[AI TTS DEBUG] АУДИО ГОТОВО!")
                                        print("[AI TTS DEBUG] URL: " .. audioUrl)
                                    end
                                    self:SetCached(cacheKey, audioUrl)
                                    completed = true
                                    _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
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
                        _G.AI_TTS_Active = math.max(0, _G.AI_TTS_Active - 1)
                        if callback then callback(nil, "Аудио не найдено") end
                        return
                    end
                end
                timer.Simple(1.0, checkTTS)
            end,
            failed = function(err)
                if not completed then
                    timer.Simple(2.0, checkTTS)
                end
            end
        })
    end
    timer.Simple(1.0, checkTTS)
end
function GetPlayerTTSWorkflow(ply)
    if not IsValid(ply) then return nil end
    local enabled = GetPlayerSetting(ply, "tts_workflow_enabled")
    if not enabled then
        return nil
    end
    local workflow = GetPlayerSetting(ply, "tts_workflow")
    if not workflow or type(workflow) ~= "table" then
        return nil
    end
    return workflow
end
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
function FindTextFieldInNode(node, nodeType)
    if not node or not node.inputs then
        return nil, nil
    end
    local specialRule = NODE_SPECIAL_RULES[nodeType]
    if specialRule then
        if specialRule.textField and node.inputs[specialRule.textField] ~= nil then
            return specialRule.textField, "special_rule"
        end
        if specialRule.excludeFields then
            for _, excludeField in ipairs(specialRule.excludeFields) do
                if node.inputs[excludeField] and type(node.inputs[excludeField]) == "string" then
                end
            end
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
function InjectTextIntoPrompt(prompt, text)
    if not prompt then return nil end
    local result = util.TableToJSON(prompt)
    if not result then return nil end
    local ok, injected = pcall(util.JSONToTable, result)
    if not ok or not injected then
        return nil
    end
    local textNodeFound = false
    local injectedCount = 0
    for nodeId, node in pairs(injected) do
        if node.inputs then
            local fieldName, method = FindTextFieldInNode(node, node.class_type)
            if fieldName then
                if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                    print("[AI TTS DEBUG] Вставка текста в ноду " .. nodeId .. " (" .. node.class_type .. ")")
                    print("[AI TTS DEBUG]   Поле: " .. fieldName .. " (метод: " .. method .. ")")
                    print("[AI TTS DEBUG]   Текст: " .. text:sub(1, 50) .. "...")
                end
                node.inputs[fieldName] = text
                textNodeFound = true
                injectedCount = injectedCount + 1
            else
                if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                    print("[AI TTS DEBUG] Нода " .. nodeId .. " (" .. node.class_type .. ") не имеет подходящего текстового поля")
                end
            end
        end
    end
    if not textNodeFound then
        AI_Utils.LogWarn("TTS", "Не найдено подходящее текстовое поле ни в одной ноде")
        return nil
    end
    if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
        print("[AI TTS DEBUG] Текст вставлен в " .. injectedCount .. " нод")
    end
    return injected
end
function InjectTextIntoWorkflow(workflow, text)
    if not workflow then
        return nil
    end
    local apiPrompt, err = ConvertUIWorkflowToAPI(workflow)
    if not apiPrompt then
        return nil
    end
    return InjectTextIntoPrompt(apiPrompt, text)
end
concommand.Add("ai_tts_workflow_load", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы!")
        end
        return
    end
    if #args < 1 then
        ply:ChatPrint("[AI] Использование: ai_tts_workflow_load <путь_к_json>")
        return
    end
    local filePath = args[1]
    local data = file.Read(filePath, "DATA")
    if not data then
        ply:ChatPrint("[AI] Не удалось прочитать файл: " .. filePath)
        return
    end
    local ok, workflow = pcall(util.JSONToTable, data)
    if not ok or not workflow then
        ply:ChatPrint("[AI] Ошибка парсинга JSON")
        return
    end
    local apiPrompt, err = ConvertUIWorkflowToAPI(workflow)
    if not apiPrompt then
        ply:ChatPrint("[AI] Ошибка конвертации workflow: " .. tostring(err))
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
        ply:ChatPrint("[AI] Workflow не содержит OmniVoiceVoiceCloneTTS ноду")
    end
    SetPlayerSetting(ply, "tts_workflow", apiPrompt)
    SetPlayerSetting(ply, "tts_workflow_filename", filePath)
    SetPlayerSetting(ply, "tts_workflow_enabled", true)
    ply:ChatPrint("[AI] Workflow загружен и сконвертирован: " .. filePath)
    ply:ChatPrint("[AI] Используйте ai_tts_workflow_toggle для включения/выключения")
end)
concommand.Add("ai_tts_workflow_toggle", function(ply)
    if not IsValid(ply) then return end
    local current = GetPlayerSetting(ply, "tts_workflow_enabled") or false
    local newValue = not current
    SetPlayerSetting(ply, "tts_workflow_enabled", newValue)
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
    ply:ChatPrint("[AI] Кастомный workflow: " .. state)
end)
concommand.Add("ai_tts_workflow_reset", function(ply)
    if not IsValid(ply) then return end
    SetPlayerSetting(ply, "tts_workflow", nil)
    SetPlayerSetting(ply, "tts_workflow_filename", "")
    SetPlayerSetting(ply, "tts_workflow_enabled", false)
    ply:ChatPrint("[AI] Workflow сброшен")
end)
concommand.Add("ai_tts_workflow_status", function(ply)
    if not IsValid(ply) then return end
    local filename = GetPlayerSetting(ply, "tts_workflow_filename") or "Не загружен"
    local enabled = GetPlayerSetting(ply, "tts_workflow_enabled") or false
    ply:ChatPrint("[AI] === СТАТУС TTS WORKFLOW ===")
    ply:ChatPrint("[AI] Файл: " .. filename)
    ply:ChatPrint("[AI] Включён: " .. (enabled and " Да" or " Нет"))
end)
local ElevenLabs_TTS = {}
ElevenLabs_TTS.__index = ElevenLabs_TTS
setmetatable(ElevenLabs_TTS, TTSProvider)
function ElevenLabs_TTS:new(config)
    local defaults = AI.Config.Providers.TTS.Defaults.elevenlabs
    local obj = TTSProvider:new(config)
    obj.name = "elevenlabs"
    obj.defaultVoice = defaults.voice
    obj.defaultModel = defaults.model
    obj.defaultEndpoint = "https://api.elevenlabs.io/v1/text-to-speech"
    setmetatable(obj, self)
    return obj
end
function ElevenLabs_TTS:GetDisplayName()
    return "ElevenLabs"
end
function ElevenLabs_TTS:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ ElevenLabs не установлен"
    end
    return true, "OK"
end
function ElevenLabs_TTS:GetEndpoint()
    local voice = self.config.voice or self.defaultVoice
    return string.format("%s/%s", self.config.endpoint or self.defaultEndpoint, voice)
end
function ElevenLabs_TTS:GenerateAudio(text, callback, player)
    if not text or text == "" then
        if callback then callback(nil, "Пустой текст") end
        return
    end
    local cleanText = AI_Utils.CleanForTTS(text)
    if cleanText == "" or cleanText == " " then
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end
    local cacheKey = AI_Utils.Hash(cleanText)
    local cached = self:GetCached(cacheKey)
    if cached then
        if callback then callback(cached, nil) end
        return
    end    local url = self:GetEndpoint()
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
    AI_Utils.HTTPQueue({
        url = url,
        method = "POST",
        timeout = DEFAULT_TIMEOUT,
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
function GoogleTTS_TTS:new(config)
    local defaults = AI.Config.Providers.TTS.Defaults.google
    local obj = TTSProvider:new(config)
    obj.name = "google"
    obj.defaultVoice = defaults.voice
    obj.defaultLanguage = defaults.language
    obj.defaultEndpoint = "https://texttospeech.googleapis.com/v1/text:synthesize"
    setmetatable(obj, self)
    return obj
end
function GoogleTTS_TTS:GetDisplayName()
    return "Google Cloud TTS"
end
function GoogleTTS_TTS:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "API ключ Google Cloud не установлен"
    end
    return true, "OK"
end
function GoogleTTS_TTS:GetEndpoint()
    return self.config.endpoint or self.defaultEndpoint
end
function GoogleTTS_TTS:GenerateAudio(text, callback, player)
    if not text or text == "" then
        if callback then callback(nil, "Пустой текст") end
        return
    end
    local cleanText = AI_Utils.CleanForTTS(text)
    if cleanText == "" or cleanText == " " then
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end
    local cacheKey = AI_Utils.Hash(cleanText)
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
    AI_Utils.HTTPQueue({
        url = url,
        method = "POST",
        timeout = DEFAULT_TIMEOUT,
        body = util.TableToJSON(body),
        headers = { ["Content-Type"] = "application/json" },
        success = function(code, responseBody)
            if code ~= 200 then
                if callback then callback(nil, "HTTP " .. code) end
                return
            end
            local ok, data = pcall(util.JSONToTable, responseBody)
            if not ok or not data or not data.audioContent then
                if callback then callback(nil, "Неверный формат ответа") end
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
function YandexTTS:new(config)
    local defaults = AI.Config.Providers.TTS.Defaults.yandex
    local obj = TTSProvider:new(config)
    obj.name = "yandex"
    obj.defaultVoice = defaults.voice
    obj.defaultLang = defaults.language
    obj.defaultEndpoint = "https://tts.api.cloud.yandex.net/speech/v1/tts:synthesize"
    setmetatable(obj, self)
    return obj
end
function YandexTTS:GetDisplayName()
    return "Yandex SpeechKit"
end
function YandexTTS:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "IAM-токен Yandex Cloud не установлен"
    end
    if not self.config.folder_id or self.config.folder_id == "" then
        return false, "Folder ID Yandex Cloud не установлен"
    end
    return true, "OK"
end
function YandexTTS:GetEndpoint()
    return self.config.endpoint or self.defaultEndpoint
end
function YandexTTS:GenerateAudio(text, callback, player)
    if not text or text == "" then
        if callback then callback(nil, "Пустой текст") end
        return
    end
    local cleanText = AI_Utils.CleanForTTS(text)
    if cleanText == "" or cleanText == " " then
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end
    local cacheKey = AI_Utils.Hash(cleanText)
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
        table.insert(bodyParts, k .. "=" .. URLEncode(v))
    end
    local body = table.concat(bodyParts, "&")
    local headers = {
        ["Authorization"] = "Bearer " .. self.config.api_key,
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
    AI_Utils.HTTPQueue({
        url = url,
        method = "POST",
        timeout = DEFAULT_TIMEOUT,
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
function VKTTS:new(config)
    local defaults = AI.Config.Providers.TTS.Defaults.vk
    local obj = TTSProvider:new(config)
    obj.name = "vk"
    obj.defaultVoice = defaults.voice
    obj.defaultEncoder = defaults.encoder
    obj.defaultTempo = defaults.tempo
    obj.defaultEndpoint = "https://voice.mcs.mail.ru/tts"
    setmetatable(obj, self)
    return obj
end
function VKTTS:GetDisplayName()
    return "VK Cloud Voice"
end
function VKTTS:ValidateConfig()
    if not self.config.api_key or self.config.api_key == "" then
        return false, "Токен доступа VK Cloud не установлен"
    end
    return true, "OK"
end
function VKTTS:GetEndpoint()
    return self.config.endpoint or self.defaultEndpoint
end
function VKTTS:GenerateAudio(text, callback, player)
    if not text or text == "" then
        if callback then callback(nil, "Пустой текст") end
        return
    end
    local cleanText = AI_Utils.CleanForTTS(text)
    if cleanText == "" or cleanText == " " then
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end
    local cacheKey = AI_Utils.Hash(cleanText)
    local cached = self:GetCached(cacheKey)
    if cached then
        if callback then callback(cached, nil) end
        return
    end
    local modelName = self.config.voice or self.defaultVoice
    local encoder = self.config.encoder or self.defaultEncoder
    local tempo = self.config.tempo or self.defaultTempo
    local url = self:GetEndpoint() .. "?" .. table.concat({
        "text=" .. URLEncode(cleanText),
        "model_name=" .. URLEncode(modelName),
        "encoder=" .. URLEncode(encoder),
        "tempo=" .. tostring(tempo)
    }, "&")
    local headers = {
        ["Authorization"] = "Bearer " .. self.config.api_key
    }
    AI_Utils.HTTPQueue({
        url = url,
        method = "GET",
        timeout = DEFAULT_TIMEOUT,
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
function CreateTTSProvider(providerType, config)
    local providerClass = TTS_PROVIDERS[providerType]
    if not providerClass then
        return nil, "Неизвестный провайдер TTS: " .. tostring(providerType)
    end
    return providerClass:new(config or {})
end
function GetAvailableTTSProviders()
    return AI.Config.Providers.TTS.List
end
function GetPlayerTTSProvider(ply)
    if not IsValid(ply) then return nil end
    local ttsEnabled = AI_SETTINGS.tts_enabled
    if ttsEnabled == false then
        return nil
    end
    local ttsMode = AI_SETTINGS.tts_mode or "local"
    if ttsMode == "local" then
        local config = {
            endpoint = AI.Config.GetTTSURL(),
        }
        return CreateTTSProvider("comfyui", config)
    end
    if ttsMode == "cloud" then
        local providerType = GetPlayerSetting(ply, "tts_provider") or AI.Config.Providers.TTS.Default
        local config = {
            voice = GetPlayerSetting(ply, "tts_voice"),
            language = GetPlayerSetting(ply, "tts_language"),
            endpoint = GetPlayerSetting(ply, "tts_endpoint"),
            api_key = GetPlayerSetting(ply, "tts_api_key"),
            folder_id = GetPlayerSetting(ply, "yandex_folder_id"),
            encoder = GetPlayerSetting(ply, "vk_encoder") or "mp3",
            tempo = GetPlayerSetting(ply, "vk_tempo") or 1.0
        }
        local provider, err = CreateTTSProvider(providerType, config)
        if not provider then
            AI_Utils.LogError("TTS", "Не удалось создать TTS провайдер: %s", err)
            return nil
        end
        return provider
    end
    return nil
end
function GenerateTTS(ply, text, callback)
    if not IsValid(ply) then
        if callback then callback(nil, "Player invalid") end
        return
    end
    if not text or text == "" then
        if callback then callback(nil, "Пустой текст") end
        return
    end
    if not AI_SETTINGS.tts_enabled then
        if callback then callback(nil, "TTS отключён") end
        return
    end
    local provider = GetPlayerTTSProvider(ply)
    if not provider then
        if callback then callback(nil, "TTS провайдер не найден") end
        return
    end
    local valid, err = provider:ValidateConfig()
    if not valid then
        if callback then callback(nil, err) end
        return
    end
    local cleanText = AI_Utils.CleanForTTS(text)
    if cleanText == "" or cleanText == " " then
        if callback then callback(nil, "Текст пуст после очистки") end
        return
    end
    provider:GenerateAudio(cleanText, function(audioUrl, err)
        if err then
            if callback then callback(nil, err) end
            return
        end
        if audioUrl then
            if callback then
                callback(audioUrl, nil)
            end
        else
            if callback then callback(nil, "Нет аудио данных") end
        end
    end, ply)
end
function RunComfyUIWorkflow(ply, text)
    if not IsValid(ply) then return end
    if not AI_SETTINGS.tts_enabled then
        return
    end
    GenerateTTS(ply, text, function(audioUrl, err)
        if err then
            AI_Utils.LogWarn("TTS", "Ошибка генерации: %s", err)
            return
        end
        if audioUrl then
            net.Start("AI_Companion_PlayAudio")
            net.WriteString(audioUrl)
            net.Send(ply)
            if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
                print("[AI TTS DEBUG] URL отправлен клиенту: " .. audioUrl)
            end
        end
    end)
end
_G.GetPlayerTTSProvider = GetPlayerTTSProvider
_G.GetAvailableTTSProviders = GetAvailableTTSProviders
_G.CreateTTSProvider = CreateTTSProvider
_G.GenerateTTS = GenerateTTS
_G.RunComfyUIWorkflow = RunComfyUIWorkflow
_G.GetPlayerTTSWorkflow = GetPlayerTTSWorkflow
_G.InjectTextIntoWorkflow = InjectTextIntoWorkflow
_G.InjectTextIntoPrompt = InjectTextIntoPrompt
_G.ConvertUIWorkflowToAPI = ConvertUIWorkflowToAPI
AI.API.GetTTSProvider = GetPlayerTTSProvider
AI.API.GetTTSProviders = GetAvailableTTSProviders
AI.API.CreateTTS = CreateTTSProvider
AI.API.GenerateTTS = GenerateTTS
AI.API.RunTTS = RunComfyUIWorkflow
print("[AI TTS] Загружен (только кастомный workflow из JSON)")