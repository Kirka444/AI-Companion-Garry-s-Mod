
local LLMRemember = {}

function LLMRemember:new(utils, config, state, llm, shared)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        llm = llm,
        shared = shared,
        _initialized = false,
        _savePath = "ai_companion_data/ai_companion_remember.txt",
        _data = {
            enabled = true,
            players = {}
        },
        _dirty = false
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function LLMRemember:init()
    if self._initialized then return end

    if SERVER then
        if not file.Exists("ai_companion_data", "DATA") then
            file.CreateDir("ai_companion_data")
        end

        self:LoadFromFile()

        self:SetupNetReceivers()
        self:SetupHooks()

        timer.Create("AI_Remember_AutoSave", 60, 0, function()
            if self._dirty then
                self:SaveToFile()
            end
        end)
    end

    self._initialized = true
    print("[LLMRemember] ✅ Сервис памяти инициализирован")
end

function LLMRemember:SanitizeString(str)
    if not str or type(str) ~= "string" then return "" end

    str = string.gsub(str, "\r\n", " ")
    str = string.gsub(str, "\n", " ")
    str = string.gsub(str, "\r", " ")

    str = string.gsub(str, "\t", " ")

    str = string.gsub(str, "%s+", " ")
    str = string.Trim(str)

    if #str > 500 then
        str = string.sub(str, 1, 500)
    end

    return str
end

function LLMRemember:GetSafePlayerName(ply)
    if not ply or not self.utils:IsValid(ply) then return "Unknown" end

    local name = ply:Nick()
    if not name or name == "" then
        name = "Player_" .. ply:EntIndex()
    end

    name = self:SanitizeString(name)

    if #name > 32 then
        name = string.sub(name, 1, 32)
    end

    return name
end

function LLMRemember:LoadFromFile()
    if not file.Exists(self._savePath, "DATA") then
        print("[LLMRemember] Файл памяти не найден, создаем новый")
        self._data = { enabled = true, players = {} }
        self:SaveToFile()
        return
    end

    local json = file.Read(self._savePath, "DATA")
    if not json or json == "" then
        print("[LLMRemember] Файл памяти пустой")
        self._data = { enabled = true, players = {} }
        return
    end

    local ok, data = pcall(util.JSONToTable, json)
    if not ok then
        print("[LLMRemember] ❌ Ошибка парсинга JSON: " .. tostring(data))
        self._data = { enabled = true, players = {} }
        return
    end

    if not data or type(data) ~= "table" then
        print("[LLMRemember] ⚠️ Неверный формат данных")
        self._data = { enabled = true, players = {} }
        return
    end

    self._data = data

    if not self._data.players then
        self._data.players = {}
    end

    print("[LLMRemember] ✅ Память загружена из файла (" .. table.Count(self._data.players) .. " игроков)")

    if self.state then
        local settings = self.state:getRaw("Settings")
        if settings then
            settings["Memory_Enabled"] = self._data.enabled
        end
    end
end

function LLMRemember:SaveToFile()
    if not SERVER then return end

    local json = util.TableToJSON(self._data, false)
    if not json then
        print("[LLMRemember] ❌ Ошибка сериализации JSON")
        return
    end

    file.Write(self._savePath, json)
    self._dirty = false
    print("[LLMRemember] 💾 Память сохранена в файл (" .. #json .. " байт)")
end

function LLMRemember:MarkDirty()
    self._dirty = true
end

function LLMRemember:IsEnabled()
    if self.state then
        return self.state:getSetting("Memory_Enabled", true)
    end
    return self._data.enabled
end

function LLMRemember:AddMessage(playerName, role, text)
    if not self:IsEnabled() then return end

    playerName = self:SanitizeString(playerName)
    if playerName == "" then
        playerName = "Unknown"
    end

    if not self._data.players[playerName] then
        self._data.players[playerName] = { messages = {}, events = {} }
    end

    local pData = self._data.players[playerName]

    local sanitizedText = self:SanitizeString(text)

    table.insert(pData.messages, {
        role = role,
        text = sanitizedText,
        time = os.time()
    })

    local playerMsgs = {}
    local botMsgs = {}
    for _, msg in ipairs(pData.messages) do
        if msg.role == "player" then
            table.insert(playerMsgs, msg)
        else
            table.insert(botMsgs, msg)
        end
    end

    while #playerMsgs > 5 do table.remove(playerMsgs, 1) end
    while #botMsgs > 5 do table.remove(botMsgs, 1) end

    pData.messages = {}
    for _, msg in ipairs(playerMsgs) do table.insert(pData.messages, msg) end
    for _, msg in ipairs(botMsgs) do table.insert(pData.messages, msg) end

    self:MarkDirty()
    print("[LLMRemember] 💬 Добавлено сообщение от " .. role .. " (" .. playerName .. "): " .. string.sub(sanitizedText, 1, 50))
end

function LLMRemember:AddEvent(playerName, eventType, text)
    if not self:IsEnabled() then return end

    playerName = self:SanitizeString(playerName)
    if playerName == "" then
        playerName = "Unknown"
    end

    if not self._data.players[playerName] then
        self._data.players[playerName] = { messages = {}, events = {} }
    end

    local pData = self._data.players[playerName]

    local sanitizedText = self:SanitizeString(text)

    table.insert(pData.events, {
        type = eventType,
        text = sanitizedText,
        time = os.time()
    })

    while #pData.events > 5 do table.remove(pData.events, 1) end

    self:MarkDirty()
    print("[LLMRemember] ⚡ Добавлено событие для " .. playerName .. ": " .. sanitizedText)
end

function LLMRemember:GetMemoryContext(ply)
    if not self:IsEnabled() then return "" end
    if not self.utils or not self.utils:IsValid(ply) then return "" end

    local playerName = self:GetSafePlayerName(ply)

    local pData = self._data.players[playerName]
    if not pData then return "" end

    local lines = {}
    table.insert(lines, "=== ПАМЯТЬ БОТА ===")

    if pData.messages and #pData.messages > 0 then
        table.insert(lines, "Последние сообщения:")
        for _, msg in ipairs(pData.messages) do
            local roleName = msg.role == "player" and "Игрок" or "Бот"
            table.insert(lines, string.format("[%s] %s", roleName, msg.text or ""))
        end
    end

    if pData.events and #pData.events > 0 then
        table.insert(lines, "Последние события:")
        for _, ev in ipairs(pData.events) do
            table.insert(lines, string.format("- %s", ev.text or ""))
        end
    end

    table.insert(lines, "==================")
    return table.concat(lines, "\n")
end

function LLMRemember:SetupHooks()
    hook.Add("PlayerDeath", "AI_Remember_Death", function(victim, attacker, inflictor)
        if not self:IsEnabled() then return end

        if victim:IsPlayer() and not victim:IsBot() then
            local victimName = self:GetSafePlayerName(victim)

            local attackerName = "Мир"
            if attacker:IsPlayer() then
                attackerName = self:GetSafePlayerName(attacker)
            elseif attacker:IsValid() then
                attackerName = attacker:GetClass()
            end

            self:AddEvent(victimName, "death", string.format("Игрок %s убит %s", victimName, attackerName))
        end
    end)

    hook.Add("PlayerSpawn", "AI_Remember_Spawn", function(ply)
        if not self:IsEnabled() then return end
        if not ply:IsPlayer() or ply:IsBot() then return end

        local playerName = self:GetSafePlayerName(ply)
        self:AddEvent(playerName, "spawn", string.format("Заспавнился на карте %s", game.GetMap()))
    end)
end

function LLMRemember:SetupNetReceivers()
    if SERVER then
        util.AddNetworkString("AI_Remember_RequestLog")
        util.AddNetworkString("AI_Remember_SendLog")
        util.AddNetworkString("AI_Remember_Clear")
        util.AddNetworkString("AI_Remember_Toggle")

        net.Receive("AI_Remember_RequestLog", function(len, ply)
            if not self.utils:IsValid(ply) or not ply:IsAdmin() then return end
            local logText = self:GetReadableLog()
            net.Start("AI_Remember_SendLog")
            net.WriteString(logText)
            net.Send(ply)
        end)

        net.Receive("AI_Remember_Clear", function(len, ply)
            if not self.utils:IsValid(ply) or not ply:IsAdmin() then return end
            self._data.players = {}
            self:SaveToFile()
            print("[LLMRemember] 🗑️ Память очищена администратором " .. ply:Nick())
        end)

        net.Receive("AI_Remember_Toggle", function(len, ply)
            if not self.utils:IsValid(ply) or not ply:IsAdmin() then return end
            local val = net.ReadBool()
            self._data.enabled = val
            if self.state then
                self.state:setSetting("Memory_Enabled", val)
            end
            self:SaveToFile()
            print("[LLMRemember] 🔘 Память " .. (val and "включена" or "выключена"))
        end)
    end
end

function LLMRemember:GetReadableLog()
    local lines = {}
    table.insert(lines, "=== ГЛОБАЛЬНАЯ ПАМЯТЬ БОТА ===")
    table.insert(lines, "Статус: " .. (self._data.enabled and "ВКЛЮЧЕНА" or "ВЫКЛЮЧЕНА"))
    table.insert(lines, "Всего игроков в базе: " .. table.Count(self._data.players or {}))
    table.insert(lines, "================================\n")

    for playerName, pData in pairs(self._data.players or {}) do
        table.insert(lines, "👤 Игрок: " .. playerName)

        if pData.events and #pData.events > 0 then
            table.insert(lines, "  📌 События:")
            for _, ev in ipairs(pData.events) do
                local timeStr = ev.time and os.date("%H:%M:%S", ev.time) or "??:??:??"
                table.insert(lines, "    [" .. timeStr .. "] " .. ev.text)
            end
        end

        if pData.messages and #pData.messages > 0 then
            table.insert(lines, "  💬 Диалог:")
            for _, msg in ipairs(pData.messages) do
                local timeStr = msg.time and os.date("%H:%M:%S", msg.time) or "??:??:??"
                local icon = msg.role == "player" and "🗣" or "🤖"
                table.insert(lines, "    [" .. timeStr .. "] " .. icon .. " " .. msg.text)
            end
        end
    end

    if table.Count(self._data.players or {}) == 0 then
        table.insert(lines, "(Память пуста)")
    end

    return table.concat(lines, "\n")
end

function LLMRemember:GetAPI()
    return {
        AddMessage = function(playerName, role, text) return self:AddMessage(playerName, role, text) end,
        AddEvent = function(playerName, eventType, text) return self:AddEvent(playerName, eventType, text) end,
        GetMemoryContext = function(ply) return self:GetMemoryContext(ply) end,
        GetSafePlayerName = function(ply) return self:GetSafePlayerName(ply) end,
        IsEnabled = function() return self:IsEnabled() end,
    }
end

return LLMRemember
