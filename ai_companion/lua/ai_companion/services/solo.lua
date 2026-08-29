```lua

local Solo = {}

function Solo:new(utils, config, state, llm, tts, llm_actions, shared)
    local obj = {

        utils = utils,
        config = config,
        state = state,
        llm = llm,
        tts = tts,
        llm_actions = llm_actions,
        shared = shared,

        _initialized = false,
        _history = {},
        _cooldowns = {},
        _pending = {},
        _requestCounter = 0,
        _globalLLMCooldown = 0,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Solo:init()
    if self._initialized then return end

    if not game.SinglePlayer() then
        if self.utils then
            self.utils.LogInfo("Solo", "Соло-режим не активен, сервис не инициализирован")
        end
        self._initialized = true
        return
    end

    if SERVER then
        self:SetupNetMessages()
    end

    self:SetupHooks()
    self:SetupCommands()

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Solo", "Соло-режим инициализирован")
    end
end

function Solo:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Solo:GetSetting(key, default)
    if self.state then
        local val = self.state:getSetting(key)
        if val ~= nil then return val end
    end
    return default
end

function Solo:GetState(key, default)
    if self.state then
        local val = self.state:getState(key)
        if val ~= nil then return val
    end
    return default
end

function Solo:SetSetting(key, value)
    if self.state then
        self.state:setSetting(key, value)
    end
end

function Solo:SetState(key, value)
    if self.state then
        self.state:setState(key, value)
    end
end

function Solo:SendMessage(ply, text, color, sender, receiver, isPrivate)
    if not self:IsValid(ply) then return end
    if not self.shared then

        local prefixColor = color or Color(255, 200, 0)
        local senderName = sender or "AI"
        local receiverName = receiver or "Игрок"
        local receiverSteamID = isPrivate and ply:SteamID64() or ""

        net.Start("AI_Companion_Chat")
        net.WriteString(text)
        net.WriteColor(prefixColor)
        net.WriteString(senderName)
        net.WriteString(receiverName)
        net.WriteString(receiverSteamID)
        net.Send(ply)
        return
    end

    self.shared:SendChatMessage(ply, text, color, sender, receiver, isPrivate)
end

function Solo:GetHistory(ply)
    if not self:IsValid(ply) then return {} end
    local steamID = ply:SteamID64()
    self._history[steamID] = self._history[steamID] or {}
    return self._history[steamID]
end

function Solo:AddHistory(ply, role, content)
    if not self:IsValid(ply) then return
    local steamID = ply:SteamID64()
    self._history[steamID] = self._history[steamID] or {}
    content = self.utils.CleanText(content, self:GetSetting("MaxMessageLength", 500))
    table.insert(self._history[steamID], { role = role, content = content, time = CurTime() })

    local maxPairs = self:GetSetting("MaxHistoryPairs", 5)
    local maxMessages = maxPairs * 2
    while #self._history[steamID] > maxMessages do
        table.remove(self._history[steamID], 1)
    end

    local maxAge = 3600
    if self.config then
        maxAge = self.config:get("Chat").MaxHistoryAge or 3600
    end
    local now = CurTime()
    local hist = self._history[steamID]
    for i = #hist, 1, -1 do
        if now - (hist[i].time or 0) > maxAge then
            table.remove(hist, i)
        end
    end
end

function Solo:GetContext(ply)
    if not self:IsValid(ply) then
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
        }
    end

    local ctx = {}
    ctx.ply = ply
    ctx.playerName = ply:Nick()
    ctx.playerHealth = math.Round(ply:Health())
    ctx.playerMaxHealth = math.Round(ply:GetMaxHealth())
    ctx.playerArmor = math.Round(ply:Armor())
    ctx.playerModel = ply:GetModel() or "неизвестно"
    ctx.playerAlive = ply:Alive()

    if ply:InVehicle() then
        local veh = ply:GetVehicle()
        local vehName = self:IsValid(veh) and (veh:GetClass() or "транспорт") or "транспорт"
        local isDriver = self:IsValid(veh) and veh.GetDriver and veh:GetDriver() == ply
        ctx.playerStatus = (isDriver and "водитель" or "пассажир") .. " (" .. vehName .. ")"
    else
        ctx.playerStatus = "пешком"
    end

    local weapon = ply:GetActiveWeapon()
    ctx.playerWeapon = self:IsValid(weapon) and weapon:GetClass() or "нет оружия"
    ctx.mapName = game.GetMap() or "неизвестно"
    ctx.serverTime = os.date("%H:%M")
    ctx.playerCount = #player.GetAll()
    ctx.humanCount = #player.GetHumans()
    ctx.botCount = #player.GetBots()

    local npcCount = 0
    local npcTypes = {}
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if self:IsValid(ent) and ent:Alive() then
            npcCount = npcCount + 1
            local class = ent:GetClass()
            npcTypes[class] = (npcTypes[class] or 0) + 1
        end
    end
    ctx.npcCount = npcCount
    ctx.npcTypes = npcTypes

    return ctx
end

function Solo:BuildPrompt(ctx)
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
        "📦 КОМАНДЫ ДЛЯ СОЗДАНИЯ ПРЕДМЕТОВ:",
        "Если игрок просит создать предмет, напиши команду в ответе:",
        "  !companion spawn <тип> [модель]",
        "",
        "Доступные типы:",
        "  - Предметы (спавнятся у игрока): healthkit, healthvial, battery,",
        "    ammo, ammo_pistol, ammo_ar2, ammo_buckshot, ammo_357, ammo_rpg",
        "  - Оружие: grenade, rpg, smg1, shotgun, pistol, crowbar, stunstick",
        "  - Пропы: chair, table, crate, barrel, box, pallet, shelf, lamp,",
        "    computer, monitor, tv, toilet, sink, bathtub, bed, couch,",
        "    fridge, stove, microwave, dumpster, bench",
        "  - NPC: zombie, combine, citizen, dog, headcrab, antlion, vortigaunt",
        "  - Транспорт: jeep, airboat, car",
        "",
        "📝 ПРИМЕРЫ:",
        "Игрок: \"Дай мне аптечку\"",
        "Ты: \"Держи аптечку.\"",
        "!companion spawn healthkit",
        "",
        "Игрок: \"Создай стул\"",
        "Ты: \"Стул готов.\"",
        "!companion spawn chair",
        "",
        "Игрок: \"Поставь ящик\"",
        "Ты: \"Ящик перед тобой.\"",
        "!companion spawn crate",
        "",
        "ВАЖНО: КОМАНДА ВСЕГДА ИДЁТ С НОВОЙ СТРОКИ ПОСЛЕ ОТВЕТА!",
        "Если команда есть - она будет выполнена, но текст ответа тоже покажется игроку.",
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

function Solo:CheckCooldown(ply)
    if not self:IsValid(ply) then return false end
    local key = ply:EntIndex()
    local last = self._cooldowns[key] or 0
    local cooldown = self:GetSetting("SoloCooldown", 5)
    if CurTime() - last < cooldown then
        self:SendMessage(ply, "Подождите перед следующим запросом...", Color(255,0,0), "AI", ply:Nick(), false)
        return false
    end
    self._cooldowns[key] = CurTime()
    return true
end

function Solo:CheckGlobalCooldown()
    local cooldown = self:GetSetting("GlobalLLMCooldown", 3)
    if CurTime() - self._globalLLMCooldown < cooldown then
        return false, math.ceil(cooldown - (CurTime() - self._globalLLMCooldown))
    end
    self._globalLLMCooldown = CurTime()
    return true, 0
end

function Solo:ProcessResponse(ply, response)
    if not self:IsValid(ply) then return response, false end
    if not response or response == "" then return response, false end

    local processedResponse = response
    local commandsExecuted = false

    local pattern = "!companion%s+spawn%s+(%S+)%s*(.-)%s*$"
    for i = 1, 3 do
        local cmdStart, cmdEnd, keyword, customModel = string.find(processedResponse, pattern)
        if not cmdStart then break end

        local beforeCmd = string.sub(processedResponse, 1, cmdStart - 1)
        beforeCmd = string.Trim(beforeCmd)

        if self.llm_actions then
            local success, result = self.llm_actions:SpawnEntity(ply, keyword, customModel or "")
            if success and self:IsValid(result) then
                self:SendMessage(ply, "Создан: " .. (result:GetClass() or "объект"), Color(255,200,0), "AI", ply:Nick(), false)
            else
                self:SendMessage(ply, "Ошибка спавна: " .. tostring(result), Color(255,0,0), "AI", ply:Nick(), false)
            end
        else
            self:SendMessage(ply, "Функция SpawnEntity не загружена", Color(255,0,0), "AI", ply:Nick(), false)
        end
        commandsExecuted = true

        local afterCmd = string.sub(processedResponse, cmdEnd + 1)
        processedResponse = string.Trim(beforeCmd .. " " .. afterCmd)
    end

    return processedResponse, commandsExecuted
end

function Solo:Ask(ply, msg)
    if not self:IsValid(ply) then return end

    local llmEnabled = self:GetState("LLM_Enabled", true)
    if not llmEnabled then
        self:SendMessage(ply, "LLM отключён в настройках", Color(255,0,0), "AI", ply:Nick(), false)
        return
    end

    msg = self.utils.CleanText(msg, self:GetSetting("MaxMessageLength", 500))
    if msg == "" then return end

    if not self:CheckCooldown(ply) then return end

    local ok, remaining = self:CheckGlobalCooldown()
    if not ok then
        self:SendMessage(ply, "Слишком много запросов, подождите " .. remaining .. " сек.", Color(255,0,0), "AI", ply:Nick(), false)
        return
    end

    local playerName = ply:Nick() or "Игрок"
    local fullMsg = "[Игрок " .. playerName .. "] " .. msg
    self:AddHistory(ply, "user", fullMsg)

    local context = self:GetContext(ply)
    local systemPrompt = self:BuildPrompt(context)
    local history = self:GetHistory(ply)

    local maxTokens = self:GetSetting("MaxTokens", 150)
    local temperature = self:GetSetting("Temperature", 0.7)
    local llmTimeout = self:GetSetting("LLM_Timeout", 60)
    local ip = self:GetSetting("LLM_IP", "127.0.0.1")
    local port = self:GetSetting("LLM_Port", 1234)
    local model = self:GetSetting("LLM_Model", "local-model")

    local body = {
        model = model,
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
        self:SendMessage(ply, "Ошибка формирования JSON запроса", Color(255,0,0), "AI", ply:Nick(), false)
        return
    end

    self:SendMessage(ply, "Думаю...", Color(150,150,150), "AI", ply:Nick(), false)

    self._requestCounter = self._requestCounter + 1
    local reqID = self._requestCounter
    self._pending[reqID] = ply

    local endpoint = "http://" .. ip .. ":" .. port .. "/v1/chat/completions"
    local timerID = "SoloLLM_timeout_" .. tostring(reqID)

    timer.Create(timerID, llmTimeout, 1, function()
        if self._pending[reqID] then
            self._pending[reqID] = nil
            if self:IsValid(ply) then
                self:SendMessage(ply, "Превышено время ожидания от LLM, попробуйте позже", Color(255,0,0), "AI", ply:Nick(), false)
            end
        end
    end)

    self.utils.HTTPQueue({
        url = endpoint,
        method = "POST",
        timeout = llmTimeout,
        body = jsonBody,
        headers = { ["Content-Type"] = "application/json" },
        success = function(code, responseBody)
            timer.Remove(timerID)
            self._pending[reqID] = nil

            if not self:IsValid(ply) then return end

            if code ~= 200 then
                self:SendMessage(ply, "Ошибка LLM: HTTP " .. code, Color(255,0,0), "AI", ply:Nick(), false)
                return
            end

            local ok, data = pcall(util.JSONToTable, responseBody)
            if not ok or not data then
                self:SendMessage(ply, "Ошибка парсинга ответа LLM", Color(255,0,0), "AI", ply:Nick(), false)
                return
            end

            if not data.choices or not data.choices[1] or not data.choices[1].message then
                self:SendMessage(ply, "Некорректный ответ от LLM", Color(255,0,0), "AI", ply:Nick(), false)
                return
            end

            local response = data.choices[1].message.content or ""
            if response == "" then
                self:SendMessage(ply, "Пустой ответ от LLM", Color(255,0,0), "AI", ply:Nick(), false)
                return
            end

            response = self.utils.CleanText(response, self:GetSetting("MaxMessageLength", 500))

            local processedResponse, commandExecuted = self:ProcessResponse(ply, response)

            if commandExecuted and processedResponse == "" then
                return
            end

            if processedResponse ~= "" then
                local prefixColor = self:GetPrefixColor(ply)
                local cleanPrefix = self:GetCleanPrefix(ply)
                self:SendMessage(ply, processedResponse, prefixColor, cleanPrefix, ply:Nick(), false)
                self:AddHistory(ply, "assistant", processedResponse)
            end

            if self:GetState("TTS_Enabled", false) and self.tts then
                self.tts:Generate(ply, processedResponse)
            end
        end,
        error = function(err)
            timer.Remove(timerID)
            self._pending[reqID] = nil
            if self:IsValid(ply) then
                self:SendMessage(ply, "Ошибка соединения: " .. tostring(err), Color(255,0,0), "AI", ply:Nick(), false)
            end
        end
    })
end

function Solo:GetPrefixColor(ply)
    if not self:IsValid(ply) then return Color(255, 200, 0) end

    local settings = {}
    if self.state then
        settings = self.state:getRaw("Settings") or {}
    end

    if settings.prefix_rainbow then
        local hue = (CurTime() * 120) % 360
        return HSVToColor(hue, 1, 1)
    end

    return Color(
        settings.prefix_r or 255,
        settings.prefix_g or 200,
        settings.prefix_b or 0
    )
end

function Solo:GetCleanPrefix(ply)
    if not self:IsValid(ply) then return "AI" end

    local settings = {}
    if self.state then
        settings = self.state:getRaw("Settings") or {}
    end

    local prefix = settings.prefix_text or "[AI]"
    local clean = string.gsub(prefix, "^%[", "")
    clean = string.gsub(clean, "%]$", "")
    clean = string.Trim(clean)
    if clean == "" then clean = "AI" end
    return clean
end

function Solo:SetupHooks()
    if not SERVER then return end

    local selfRef = self

    hook.Remove("PlayerSay", "AI_Solo_ChatCommands")
    hook.Add("PlayerSay", "AI_Solo_ChatCommands", function(ply, text)
        if not selfRef:IsValid(ply) or ply:IsBot() then return end

        local lowerText = string.lower(text)
        local cleanPrefix = selfRef:GetCleanPrefix(ply)

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

        if string.StartWith(lowerText, "!companion spawn") then
            local afterCommand = string.sub(text, string.len("!companion") + 1)
            local cmd = string.Trim(afterCommand)
            local args = {}
            for word in string.gmatch(cmd, "[^%s]+") do
                table.insert(args, word)
            end
            if #args < 2 then
                selfRef:SendMessage(ply, "Использование: !companion spawn <тип> [модель]", Color(255,200,0), "AI", ply:Nick(), false)
                return ""
            end
            local keyword = args[2]
            local customModel = args[3] or ""
            if selfRef.llm_actions then
                local success, result = selfRef.llm_actions:SpawnEntity(ply, keyword, customModel)
                if success and selfRef:IsValid(result) then
                    selfRef:SendMessage(ply, "Создан: " .. (result:GetClass() or "объект"), Color(255,200,0), "AI", ply:Nick(), false)
                else
                    selfRef:SendMessage(ply, "Ошибка: " .. tostring(result), Color(255,0,0), "AI", ply:Nick(), false)
                end
            else
                selfRef:SendMessage(ply, "Функция SpawnEntity не загружена", Color(255,0,0), "AI", ply:Nick(), false)
            end
            return ""
        end

        if string.StartWith(lowerText, "!companion") then
            selfRef:SendMessage(ply, "В одиночном режиме доступна только !companion spawn", Color(255,200,0), "AI", ply:Nick(), false)
            return ""
        end

        if not selfRef:GetState("LLM_Enabled", true) then return end
        local msg = string.Trim(text)
        if msg == "" then return end
        selfRef:Ask(ply, msg)
    end)

    hook.Add("PlayerDisconnected", "AI_Solo_Cleanup", function(ply)
        if not selfRef:IsValid(ply) then return end
        for id, p in pairs(selfRef._pending) do
            if p == ply then
                timer.Remove("Solo_Cleanup_" .. id)
                timer.Remove("LLM_timeout_" .. tostring(id))
                selfRef._pending[id] = nil
            end
        end
    end)
end

function Solo:SetupNetMessages()
    if not SERVER then return end
    util.AddNetworkString("AI_Companion_Chat")
    util.AddNetworkString("AI_Companion_PlayAudio")
    util.AddNetworkString("AI_Companion_Private_Chat")
end

function Solo:SetupCommands()
    if not SERVER then return end

    local selfRef = self

    concommand.Add("ai_llm_ip", function(ply, cmd, args)
        if not selfRef:IsValid(ply) then return end
        if #args < 1 then
            print("Использование: ai_llm_ip <ip> [port]")
            print("Текущий: " .. selfRef:GetSetting("LLM_IP", "127.0.0.1") .. ":" .. selfRef:GetSetting("LLM_Port", 1234))
            return
        end
        local input = args[1]
        local ip, portFromInput = input:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
        if not ip then ip = input:match("^(%d+%.%d+%.%d+%.%d+)$") or input end
        local ok, err = selfRef.utils.ValidateIP(ip)
        if not ok then
            selfRef:SendMessage(ply, err, Color(255,0,0), "AI", ply:Nick(), false)
            return
        end
        local port = portFromInput or (args[2] and tonumber(args[2])) or 1234
        local ok2, portNum = selfRef.utils.ValidatePort(port)
        if not ok2 then
            selfRef:SendMessage(ply, portNum, Color(255,0,0), "AI", ply:Nick(), false)
            return
        end
        selfRef:SetSetting("LLM_IP", ip)
        selfRef:SetSetting("LLM_Port", portNum)
        selfRef:SendMessage(ply, "LLM IP установлен: " .. ip .. ":" .. portNum, Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI] LLM IP установлен: " .. ip .. ":" .. portNum)
    end)

    concommand.Add("ai_tts_ip", function(ply, cmd, args)
        if not selfRef:IsValid(ply) then return end
        if #args < 1 then
            print("Использование: ai_tts_ip <ip> [port]")
            print("Текущий: " .. selfRef:GetSetting("TTS_IP", "127.0.0.1") .. ":" .. selfRef:GetSetting("TTS_Port", 8188))
            return
        end
        local input = args[1]
        local ip, portFromInput = input:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
        if not ip then ip = input:match("^(%d+%.%d+%.%d+%.%d+)$") or input end
        local ok, err = selfRef.utils.ValidateIP(ip)
        if not ok then
            selfRef:SendMessage(ply, err, Color(255,0,0), "AI", ply:Nick(), false)
            return
        end
        local port = portFromInput or (args[2] and tonumber(args[2])) or 8188
        local ok2, portNum = selfRef.utils.ValidatePort(port)
        if not ok2 then
            selfRef:SendMessage(ply, portNum, Color(255,0,0), "AI", ply:Nick(), false)
            return
        end
        selfRef:SetSetting("TTS_IP", ip)
        selfRef:SetSetting("TTS_Port", portNum)
        selfRef:SendMessage(ply, "ComfyUI IP установлен: " .. ip .. ":" .. portNum, Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI] ComfyUI IP установлен: " .. ip .. ":" .. portNum)
    end)

    concommand.Add("ai_tts_status", function(ply)
        if not selfRef:IsValid(ply) then return end
        local status = selfRef:GetState("TTS_Enabled", false) and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        selfRef:SendMessage(ply, "=== СТАТУС TTS ===", Color(255,200,0), "AI", ply:Nick(), false)
        selfRef:SendMessage(ply, "Глобальный TTS: " .. status, Color(255,200,0), "AI", ply:Nick(), false)
        selfRef:SendMessage(ply, "URL ComfyUI: " .. selfRef:GetSetting("TTS_IP", "127.0.0.1") .. ":" .. selfRef:GetSetting("TTS_Port", 8188), Color(255,200,0), "AI", ply:Nick(), false)
        if ply:IsAdmin() then
            selfRef:SendMessage(ply, "Админ-команды: ai_tts_global_on, ai_tts_global_off, ai_tts_toggle", Color(255,200,0), "AI", ply:Nick(), false)
        end
    end)

    concommand.Add("ai_companion_llm_model", function(ply, cmd, args)
        if not selfRef:IsValid(ply) then return end
        if #args < 1 then
            selfRef:SendMessage(ply, "Использование: ai_companion_llm_model <model>", Color(255,200,0), "AI", ply:Nick(), false)
            selfRef:SendMessage(ply, "Текущий: " .. selfRef:GetSetting("LLM_Model", "local-model"), Color(255,200,0), "AI", ply:Nick(), false)
            return
        end
        local model = table.concat(args, " ")
        model = string.sub(model, 1, 100)
        selfRef:SetSetting("LLM_Model", model)
        selfRef:SendMessage(ply, "Модель LLM установлена: " .. model, Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI] Модель LLM: " .. model)
    end)

    concommand.Add("ai_save_settings", function(ply)
        if not selfRef:IsValid(ply) then return end
        if selfRef.state and selfRef.state.SaveToFile then
            selfRef.state:SaveToFile()
        end
        selfRef:SendMessage(ply, "Настройки сохранены", Color(255,200,0), "AI", ply:Nick(), false)
    end)

    concommand.Add("ai_tts_global_on", function(ply)
        if not selfRef:IsValid(ply) then return end
        selfRef:SetState("TTS_Enabled", true)
        selfRef:SendMessage(ply, "TTS включен", Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI] TTS включен")
    end)

    concommand.Add("ai_tts_global_off", function(ply)
        if not selfRef:IsValid(ply) then return end
        selfRef:SetState("TTS_Enabled", false)
        selfRef:SendMessage(ply, "TTS отключен", Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI] TTS отключен")
    end)

    concommand.Add("ai_tts_toggle", function(ply)
        if not selfRef:IsValid(ply) then return end
        local current = selfRef:GetState("TTS_Enabled", false)
        selfRef:SetState("TTS_Enabled", not current)
        local state = not current and "включен" or "отключен"
        selfRef:SendMessage(ply, "TTS " .. state, Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI] TTS " .. state)
    end)

    concommand.Add("ai_companion_debug", function(ply)
        if not selfRef:IsValid(ply) then return end
        local current = selfRef:GetSetting("Debug_Mode", false)
        selfRef:SetSetting("Debug_Mode", not current)
        local state = not current and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        selfRef:SendMessage(ply, "Режим отладки: " .. state, Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI] Debug: " .. state)
    end)

    concommand.Add("ai_reset_settings", function(ply)
        if not selfRef:IsValid(ply) then return end
        local defaultSettings = {
            LLM_IP = "127.0.0.1",
            LLM_Port = 1234,
            LLM_Model = "local-model",
            TTS_IP = "127.0.0.1",
            TTS_Port = 8188,
            TTS_Enabled = false,
            LLM_Enabled = true,
            Debug_Mode = false,
            Prefix_Text = "[AI]",
            Prefix_Color_R = 255,
            Prefix_Color_G = 200,
            Prefix_Color_B = 0,
            Prefix_Rainbow = false,
            LLM_Timeout = 60,
            TTS_Timeout = 120,
        }
        for k, v in pairs(defaultSettings) do
            selfRef:SetSetting(k, v)
        end
        selfRef:SetState("TTS_Enabled", false)
        selfRef:SetState("LLM_Enabled", true)
        selfRef:SendMessage(ply, "Настройки сброшены к стандартным", Color(255,200,0), "AI", ply:Nick(), false)
    end)

    concommand.Add("ai_companion_status", function(ply)
        if not selfRef:IsValid(ply) then return end
        selfRef:SendMessage(ply, "Соло-режим активен. Используйте !ai <вопрос> или !companion spawn", Color(255,200,0), "AI", ply:Nick(), false)
    end)

    concommand.Add("ai_lang", function(ply, cmd, args)
        if not selfRef:IsValid(ply) then return end
        if not ply:IsAdmin() then
            selfRef:SendMessage(ply, "Только администраторы!", Color(255,0,0), "AI", ply:Nick(), false)
            return
        end
        local locale = _G.AI_GetLocale and _G.AI_GetLocale()
        if not locale then
            selfRef:SendMessage(ply, "Локализация не загружена", Color(255,0,0), "AI", ply:Nick(), false)
            return
        end
        local lang = args[1]
        if not lang then
            local current = locale:GetLang()
            local available = table.concat(locale:GetAvailable(), ", ")
            selfRef:SendMessage(ply, "Текущий язык: " .. current, Color(255,200,0), "AI", ply:Nick(), false)
            selfRef:SendMessage(ply, "Доступно: " .. available, Color(255,200,0), "AI", ply:Nick(), false)
            return
        end
        if locale:SetLang(lang) then
            selfRef:SetSetting("locale", lang)
            selfRef:SendMessage(ply, "Язык изменён на: " .. lang, Color(255,200,0), "AI", ply:Nick(), false)
        else
            selfRef:SendMessage(ply, "Язык не найден: " .. lang, Color(255,0,0), "AI", ply:Nick(), false)
        end
    end)

    concommand.Add("ai_request_settings", function(ply)
        if not selfRef:IsValid(ply) then return end
        if SERVER then
            net.Start("AI_Settings_Sync")
            net.WriteTable(selfRef.state:getRaw("Settings") or {})
            net.Send(ply)
        end
    end)

    concommand.Add("ai_test_llm", function(ply)
        if not selfRef:IsValid(ply) then return end
        local ip = selfRef:GetSetting("LLM_IP", "127.0.0.1")
        local port = selfRef:GetSetting("LLM_Port", 1234)
        local url = "http://" .. ip .. ":" .. port
        selfRef:SendMessage(ply, "Проверка LLM (" .. url .. ")...", Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI TEST] Проверка LLM: " .. url)
        HTTP({
            url = url,
            method = "GET",
            timeout = 3,
            success = function(code)
                selfRef:SendMessage(ply, "LLM доступен! (HTTP " .. code .. ")", Color(100,255,100), "AI", ply:Nick(), false)
                print("[AI TEST] LLM доступен (HTTP " .. code .. ")")
            end,
            failed = function(err)
                selfRef:SendMessage(ply, "LLM недоступен! Проверьте LM Studio на " .. ip .. ":" .. port, Color(255,0,0), "AI", ply:Nick(), false)
                print("[AI TEST] LLM недоступен: " .. tostring(err))
            end
        })
    end)

    concommand.Add("ai_test_tts", function(ply)
        if not selfRef:IsValid(ply) then return end
        local ip = selfRef:GetSetting("TTS_IP", "127.0.0.1")
        local port = selfRef:GetSetting("TTS_Port", 8188)
        local url = "http://" .. ip .. ":" .. port
        selfRef:SendMessage(ply, "Проверка TTS (ComfyUI) на " .. url .. "...", Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI TTS TEST] Проверка TTS: " .. url)
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
                    selfRef:SendMessage(ply, "ComfyUI доступен! (HTTP " .. code .. ")", Color(100,255,100), "AI", ply:Nick(), false)
                    print("[AI TTS TEST] ComfyUI доступен (HTTP " .. code .. ")")
                else
                    selfRef:SendMessage(ply, "ComfyUI ответил с кодом: " .. code, Color(255,200,0), "AI", ply:Nick(), false)
                    print("[AI TTS TEST] ComfyUI ответил с кодом " .. code)
                end
            end,
            failed = function(err)
                selfRef:SendMessage(ply, "ComfyUI недоступен! " .. tostring(err), Color(255,0,0), "AI", ply:Nick(), false)
                print("[AI TTS TEST] ComfyUI недоступен: " .. tostring(err))
            end
        })
    end)

    concommand.Add("ai_ping_servers", function(ply)
        if not selfRef:IsValid(ply) then return end
        local llmIP = selfRef:GetSetting("LLM_IP", "127.0.0.1")
        local llmPort = selfRef:GetSetting("LLM_Port", 1234)
        local ttsIP = selfRef:GetSetting("TTS_IP", "127.0.0.1")
        local ttsPort = selfRef:GetSetting("TTS_Port", 8188)
        local llmUrl = "http://" .. llmIP .. ":" .. llmPort
        local ttsUrl = "http://" .. ttsIP .. ":" .. ttsPort
        selfRef:SendMessage(ply, "Пинг LLM: " .. llmUrl, Color(255,200,0), "AI", ply:Nick(), false)
        selfRef:SendMessage(ply, "Пинг TTS: " .. ttsUrl, Color(255,200,0), "AI", ply:Nick(), false)
        print("[AI PING] LLM: " .. llmUrl .. ", TTS: " .. ttsUrl)

        local llmChecked = false
        local ttsChecked = false
        local function checkBothDone()
            if llmChecked and ttsChecked then
                print("[AI PING] Оба сервера отвечают")
            end
        end

        HTTP({
            url = llmUrl,
            method = "GET",
            timeout = 3,
            success = function()
                llmChecked = true
                checkBothDone()
            end,
            failed = function()
                llmChecked = true
                checkBothDone()
            end
        })

        HTTP({
            url = ttsUrl,
            method = "GET",
            timeout = 3,
            success = function()
                ttsChecked = true
                checkBothDone()
            end,
            failed = function()
                ttsChecked = true
                checkBothDone()
            end
        })

        timer.Simple(6, function()
            if not llmChecked then
                print("[AI PING] LLM не ответил")
            end
            if not ttsChecked then
                print("[AI PING] TTS не ответил")
            end
        end)
    end)
end

function Solo:GetAPI()
    return {
        Ask = function(ply, msg) return self:Ask(ply, msg) end,
        GetContext = function(ply) return self:GetContext(ply) end,
        BuildPrompt = function(ctx) return self:BuildPrompt(ctx) end,
    }
end

return Solo
```
