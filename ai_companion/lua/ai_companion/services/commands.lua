
local Commands = {}

function Commands:new(utils, config, state, botmanager, spawn, llm, tts, shared, vehicle)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        botmanager = botmanager,
        spawn = spawn,
        llm = llm,
        tts = tts,
        shared = shared,
        vehicle = vehicle,
        _initialized = false,
        _commandCooldowns = {},
        _globalCooldowns = {},
        _requestCounter = 0,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Commands:init()
    if self._initialized then return end

    if self.utils then
        self.utils:LogDebug("[Commands] init() вызван!")
        self.utils:LogDebug("[Commands] SERVER =", SERVER)
    end

    if SERVER then
        if self.utils then
            self.utils:LogDebug("[Commands] Регистрирую команды...")
        end
        self:RegisterCompanionCommands()
        self:SetupCommands()
        self:SetupChatHook()
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Commands", "Сервис команд инициализирован")
    end
end

function Commands:GetSetting(key, default)
    if self.state then
        local val = self.state:getSetting(key)
        if val ~= nil then return val end
    end
    return default
end

function Commands:GetState(key, default)
    if self.state then
        local val = self.state:getState(key)
        if val ~= nil then return val end
    end
    return default
end

function Commands:FindOwnedBot(ply)
    if not self.utils or not self.utils:IsValid(ply) then return nil, nil end

    if self.botmanager then
        local bot = self.botmanager:GetBotByOwner(ply)
        if self.utils and self.utils:IsValid(bot) then
            local data = self.botmanager:GetData(bot)
            if data and data.owner == ply then
                return bot, bot:EntIndex()
            end
        end
    end

    for _, bot in ipairs(player.GetAll()) do
        if self.utils and self.utils:IsValid(bot) and bot:IsBot() and bot:GetNWBool("IsAICompanion", false) then
            local owner = bot:GetNWEntity("AICompanionOwnerEnt")
            if self.utils and self.utils:IsValid(owner) and owner == ply then
                return bot, bot:EntIndex()
            end
        end
    end

    return nil, nil
end

function Commands:IsBotOwner(bot, ply)
    if not self.utils or not self.utils:IsValid(bot) or not self.utils:IsValid(ply) then return false end

    if self.botmanager then
        local data = self.botmanager:GetData(bot)
        if data and data.owner == ply then
            return true
        end
    end

    local owner = bot:GetNWEntity("AICompanionOwnerEnt")
    return self.utils:IsValid(owner) and owner == ply
end

function Commands:SendSystemMessage(ply, text)
    if not self.utils or not self.utils:IsValid(ply) then return end

    if self.shared then
        self.shared:SendChatMessage(ply, text, Color(255, 0, 0), "AI", ply:Nick(), false)
    end
end

function Commands:CheckCooldown(ply, cmd)
    if not self.utils or not self.utils:IsValid(ply) then return false end

    local key = ply:EntIndex() .. "_" .. cmd
    local last = self._commandCooldowns[key] or 0

    local cooldown = 5
    if self.config and self.config:get("RateLimits") then
        cooldown = self.config:get("RateLimits").CommandCooldown or 5
    end

    if CurTime() - last < cooldown then return false end
    self._commandCooldowns[key] = CurTime()
    return true
end

function Commands:CheckGlobalCooldown(key, duration)
    local last = self._globalCooldowns[key] or 0
    if CurTime() - last < duration then
        return false, math.ceil(duration - (CurTime() - last))
    end
    self._globalCooldowns[key] = CurTime()
    return true, 0
end

local STATE_KEY_MAP = {
    companion_nick = "Companion_Nick",
    model_path = "Model_Path",
    combat_weapon = "Combat_Weapon",
    melee_weapon = "Melee_Weapon",
    idle_weapon = "Idle_Weapon",
    stealth_mode = "Stealth_Mode",
    defender_mode = "Defender_Mode",
    medic_mode = "Medic_Mode",
    pacifist_mode = "Pacifist_Mode",
    aggressive_mode = "Aggressive_Mode",
    show_sender_name = "Show_Sender_Name",
}

local MODE_STATE_MAP = {
    Stealth_Mode = "StealthMode",
    Defender_Mode = "DefenderMode",
    Medic_Mode = "MedicMode",
    Pacifist_Mode = "PacifistMode",
    Aggressive_Mode = "AggressiveMode",
}

function Commands:SetBotSetting(ply, key, value)
    if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return false end

    local bot, botID = self:FindOwnedBot(ply)
    if not self.utils or not self.utils:IsValid(bot) then
        return false
    end

    if not self:IsBotOwner(bot, ply) then
        return false
    end

    local data = nil
    if self.botmanager then
        data = self.botmanager:GetData(bot)
    end

    if not data then
        local settings = self:GetPlayerSettings(ply) or {}
        if self.spawn and self.spawn.data then
            data = self.spawn.data:InitBotData(bot, ply, settings)
        end
        if not data then
            if self.utils then
                self.utils.LogError("Commands", "Не удалось инициализировать BotData")
            end
            return false
        end
        if self.botmanager then
            self.botmanager:UpdateData(bot, data)
        end
    end

    if not data.config then
        data.config = {
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
    end

    local cfg = data.config
    local boolVal = tobool(value)
    local applied = false

    local booleanKeys = {
        stealth_mode = true,
        defender_mode = true,
        medic_mode = true,
        pacifist_mode = true,
        aggressive_mode = true,
        show_sender_name = true,
    }

    if booleanKeys[key] then
        cfg[key] = boolVal
        data._nw_cache[key] = boolVal
        applied = true
    elseif key == "combat_weapon" or key == "melee_weapon" or key == "idle_weapon" then
        cfg[key] = tostring(value)
        applied = true
        local wepClass = tostring(value)
        pcall(function()
            bot:Give(wepClass)
        end)
        local botState = self.botmanager:GetBotState(bot)
        if key == "combat_weapon" and botState == "combat" then
            pcall(function() bot:SelectWeapon(wepClass) end)
        elseif key == "idle_weapon" and botState ~= "combat" then
            pcall(function() bot:SelectWeapon(wepClass) end)
        end
    elseif key == "model_path" then
        if self.utils and self.utils:IsValidModel(value) then
            cfg.model_path = value
            pcall(function() bot:SetModel(value) end)
            applied = true
        end
    elseif key == "companion_nick" then
        cfg.companion_nick = value
        pcall(function() bot:SetName(value) end)
        pcall(function() bot:SetNick(value) end)
        applied = true
    else
        applied = true
    end

    if not applied then
        return false
    end

    local stateKey = STATE_KEY_MAP[key]
    if stateKey and self.state then
        local steamID = ply:SteamID64()
        local valToSave = booleanKeys[key] and boolVal or value

        if self.state:IsGlobalKey(stateKey) then
            self.state:setSetting(stateKey, valToSave)
        else
            self.state:setPlayerSetting(steamID, stateKey, valToSave)
        end

        if booleanKeys[key] and MODE_STATE_MAP[stateKey] then
            self.state:setState(MODE_STATE_MAP[stateKey], boolVal)
        end

        if self.utils then
            self.utils.LogDebug("Commands", "Синхронизировано State[%s] = %s", stateKey, tostring(valToSave))
        end
    end

    if self.botmanager then
        self.botmanager:UpdateData(bot, data)
        self.botmanager:SyncToNWVars(bot)
    end

    return true
end

function Commands:GetPlayerSettings(ply)
    if not self.utils or not self.utils:IsValid(ply) then return nil end
    local settings = {}
    if self.state then
        local rawSettings = self.state:getRaw("Settings") or {}
        for k, v in pairs(rawSettings) do
            settings[k] = v
        end
    end
    return settings
end

function Commands:GetPlayerSettingSafe(ply, key, default)
    if not self.utils or not self.utils:IsValid(ply) then return default end
    local val = self:GetSetting(key, nil)
    if val ~= nil then return val end
    return default
end

-- ========== Реестр команд !companion (быстрая диспетчеризация) ==========

function Commands:RegisterCompanionCommand(name, desc, fn, aliases, needsBot)
    self._companionCommands[name] = {
        fn = fn,
        desc = desc,
        needsBot = needsBot ~= false, -- по умолчанию бот обязателен
    }
    if aliases then
        for _, a in ipairs(aliases) do
            self._companionAliases[a] = name
        end
    end
end

function Commands:RegisterCompanionCommands()
    self._companionCommands = {}
    self._companionAliases = {}

    local s = self

    self:RegisterCompanionCommand("follow", "Следовать за владельцем", function(bot, ply, args, states)
        if s.state then s.state:setState("Disabled", false) end
        if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
        if s.botmanager then
            s.botmanager:SetBotState(bot, states.FOLLOW or "following")
            bot:ChatPrint("[AI] Следую за " .. ply:Nick())
        end
        ply:ChatPrint("[AI] Компаньон следует за вами.")
    end, {"следуй", "за мной", "иди"}, true)

    self:RegisterCompanionCommand("stop", "Полная остановка", function(bot, ply, args, states)
        if s.botmanager then
            local data = s.botmanager:GetData(bot)
            if data and data.combat then data.combat.target = nil end
            s.botmanager:SetBotState(bot, states.IDLE or "idle")
        end
        pcall(function() bot:SetLocalVelocity(Vector(0, 0, 0)) end)
        bot:ChatPrint("[AI] Остановлен.")
        ply:ChatPrint("[AI] Компаньон остановлен.")
    end, {"стой", "стоп"}, true)

    self:RegisterCompanionCommand("status", "Статус компаньона", function(bot, ply)
        local hp = math.Round(bot:Health()) .. "/" .. math.Round(bot:GetMaxHealth())
        local armor = math.Round(bot:Armor())
        local state = s.botmanager:GetBotState(bot) or "idle"
        local inVeh = bot:InVehicle() and "в транспорте" or "пешком"
        ply:ChatPrint("[AI] === Статус ===")
        ply:ChatPrint("[AI] Имя: " .. bot:Nick())
        ply:ChatPrint("[AI] Здоровье: " .. hp)
        ply:ChatPrint("[AI] Броня: " .. armor)
        ply:ChatPrint("[AI] Состояние: " .. state)
        ply:ChatPrint("[AI] Движение: " .. inVeh)
    end, {"статус", "инфа", "состояние"}, true)

    self:RegisterCompanionCommand("help", "Справка по командам", function(bot, ply)
        ply:ChatPrint("[AI] === ДОСТУПНЫЕ КОМАНДЫ ===")
        for _, line in ipairs(s._companionHelp) do
            ply:ChatPrint("[AI] " .. line)
        end
        ply:ChatPrint("[AI] !ai <вопрос>   - Быстрый вопрос LLM")
        ply:ChatPrint("[AI] Остальные команды (spawn, teleport, give, heal, mode и т.д.) обрабатывает LLM.")
    end, {"помощь", "помоги", "h", "?"}, false)

    -- Автоматическая сборка справки из реестра
    self._companionHelp = {}
    local names = {}
    for name in pairs(self._companionCommands) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        table.insert(self._companionHelp,
            string.format("!companion %-8s - %s", name, self._companionCommands[name].desc))
    end
end

function Commands:SetupCommands()
    if not SERVER then return end
	concommand.Add("ai_companion_replace", function(ply, cmd, args)
		if game.SinglePlayer() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] Включен соло-режим, бот недоступен.")
			end
			return
		end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if not self.botmanager or not self.spawn then
			ply:ChatPrint("[AI] Необходимые сервисы не загружены")
			return
		end
		if not self:CheckCooldown(ply, "replace") then
			ply:ChatPrint("[AI] Подождите перед повторной заменой")
			return
		end

		local bot = self.botmanager:GetBotByOwner(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			ply:ChatPrint("[AI] У вас нет компаньона")
			return
		end

		-- Модель: аргумент -> персональная настройка -> глобальная -> дефолт
		local model = args[1]
		if not model or model == "" then
			model = self.state and self.state:getPlayerSetting(ply:SteamID64(), "Model_Path", nil) or nil
		end
		if not model or model == "" then
			model = self:GetSetting("Model_Path", "models/player/urban.mdl")
		end

		local oldNick = bot:Nick() or "компаньон"
		self.botmanager:RemoveBot(bot, "Замена компаньона", true)
		ply:ChatPrint("[AI] Компаньон " .. oldNick .. " удаляется, создаём нового...")

		timer.Simple(0.6, function()
			if not self.utils or not self.utils:IsValid(ply) then return end
			local newBot = self.spawn:CreateAICompanion(model, nil, ply)
			if newBot and newBot:IsValid() and newBot:IsPlayer() then
				ply:ChatPrint("[AI] Компаньон заменён!")
				if self.utils then
					self.utils.LogInfo("Commands", "Компаньон заменён для игрока %s", ply:Nick())
				end
			else
				ply:ChatPrint("[AI] Не удалось создать нового компаньона")
			end
		end)
	end)

	concommand.Add("ai_companion_teleport", function(ply)
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if not self:CheckCooldown(ply, "teleport") then
			ply:ChatPrint("[AI] Подождите перед повторным телепортом")
			return
		end

		local bot = self:FindOwnedBot(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			ply:ChatPrint("[AI] У вас нет компаньона")
			return
		end

		if bot:InVehicle() then
			pcall(function() bot:ExitVehicle() end)
		end

		-- Ищем свободную точку вокруг владельца (сзади, справа, слева, спереди, в упор)
		local basePos = ply:GetPos()
		local aim = ply:GetAimVector()
		aim.z = 0
		if aim:Length() > 0 then aim:Normalize() end
		local right = aim:Angle():Right()

		local candidates = {
			basePos - aim * 80,
			basePos + right * 80,
			basePos - right * 80,
			basePos + aim * 120,
			basePos,
		}

		local mins, maxs = bot:GetHull()
		for _, pos in ipairs(candidates) do
			local checkPos = pos + Vector(0, 0, 2)
			local tr = util.TraceHull({
				start = checkPos,
				endpos = checkPos,
				mins = mins,
				maxs = maxs,
				filter = {bot, ply},
			})
			if not tr.Hit then
				bot:SetPos(checkPos)

				-- Сбрасываем навигацию/бой и возвращаем в режим следования
				if self.botmanager then
					local data = self.botmanager:GetData(bot)
					if data then
						if data.navigation then
							data.navigation.path = nil
							data.navigation.path_index = 1
							data.navigation.goal_pos = Vector(0, 0, 0)
						end
						if data.combat then
							data.combat.target = nil
						end
						self.botmanager:UpdateData(bot, data)
					end
					local states = (self.state and self.state:GetStates()) or {}
					self.botmanager:SetBotState(bot, states.FOLLOW or "following")
				end

				ply:ChatPrint("[AI] Компаньон телепортирован к вам")
				return
			end
		end

		ply:ChatPrint("[AI] Рядом нет свободного места для телепорта")
	end)
    concommand.Add("ai_companion_stealth", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
        local current = self:GetPlayerSettingSafe(ply, "stealth_mode", false)
        local newValue = not current
        if self:SetBotSetting(ply, "stealth_mode", newValue) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Стелс режим: " .. (newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"))
            end
        end
    end)

    concommand.Add("ai_companion_defender", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
        local current = self:GetPlayerSettingSafe(ply, "defender_mode", false)
        local newValue = not current
        if self:SetBotSetting(ply, "defender_mode", newValue) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Режим защитника: " .. (newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"))
            end
        end
    end)

    concommand.Add("ai_companion_medic", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
        local current = self:GetPlayerSettingSafe(ply, "medic_mode", false)
        local newValue = not current
        if self:SetBotSetting(ply, "medic_mode", newValue) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Режим медика: " .. (newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"))
            end
        end
    end)

    concommand.Add("ai_companion_pacifist", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
        local current = self:GetPlayerSettingSafe(ply, "pacifist_mode", false)
        local newValue = not current
        if self:SetBotSetting(ply, "pacifist_mode", newValue) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Пацифистский режим: " .. (newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"))
            end
        end
    end)

    concommand.Add("ai_companion_aggressive", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or ply:IsBot() then return end
        local current = self:GetPlayerSettingSafe(ply, "aggressive_mode", false)
        local newValue = not current
        if self:SetBotSetting(ply, "aggressive_mode", newValue) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Агрессивный режим: " .. (newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"))
            end
        end
    end)

    concommand.Add("ai_companion_combat_weapon", function(ply, cmd, args)
        if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() then return end
        if ply:IsBot() then return end
        if #args < 1 then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Использование: ai_companion_combat_weapon <класс_оружия>")
            end
            return
        end

        local weapon = args[1]
        if self:SetBotSetting(ply, "combat_weapon", weapon) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Боевое оружие: " .. weapon)
            end
        end
    end)

    concommand.Add("ai_companion_melee_weapon", function(ply, cmd, args)
        if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() then return end
        if ply:IsBot() then return end
        if #args < 1 then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Использование: ai_companion_melee_weapon <класс_оружия>")
            end
            return
        end

        local weapon = args[1]
        if self:SetBotSetting(ply, "melee_weapon", weapon) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Оружие ближнего боя: " .. weapon)
            end
        end
    end)

    concommand.Add("ai_companion_idle_weapon", function(ply, cmd, args)
        if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() then return end
        if ply:IsBot() then return end
        if #args < 1 then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Использование: ai_companion_idle_weapon <класс_оружия>")
            end
            return
        end

        local weapon = args[1]
        if self:SetBotSetting(ply, "idle_weapon", weapon) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Мирное оружие: " .. weapon)
            end
        end
    end)

    concommand.Add("ai_companion_create", function(ply, cmd, args)
        if game.SinglePlayer() then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Включен соло-режим, бот недоступен.")
            end
            return
        end

        if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end

        if self.botmanager and self.botmanager:HasBot(ply) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] У вас уже есть компаньон!")
                ply:ChatPrint("[AI] Используйте ai_companion_remove чтобы удалить")
            end
            return
        end

        if not self.spawn then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Сервис спавна не загружен!")
            end
            return
        end

        local model = args[1] or "models/player/urban.mdl"
        local bot = self.spawn:CreateAICompanion(model, nil, ply)

        if bot and bot:IsValid() and bot:IsPlayer() then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Компаньон создан!")
            end
            if self.utils then
                self.utils.LogInfo("Commands", "Бот создан для игрока %s", ply:Nick())
            end
        else
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Не удалось создать компаньона")
            end
        end
    end)

    concommand.Add("ai_companion_remove", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
        if not self.botmanager then return end

        local bot = self.botmanager:GetBotByOwner(ply)
        if not self.utils or not self.utils:IsValid(bot) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] У вас нет компаньона")
            end
            return
        end

        local botNick = bot:Nick() or "компаньон"
        if self.botmanager:RemoveBot(bot, "Удалён игроком", true) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Компаньон " .. botNick .. " удалён")
            end
        else
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Не удалось удалить компаньона")
            end
        end
    end)


	concommand.Add("ai_companion_replace", function(ply, cmd, args)
		if game.SinglePlayer() then
			if self.utils and self.utils:IsValid(ply) then
				ply:ChatPrint("[AI] Включен соло-режим, бот недоступен.")
			end
			return
		end
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if not self.botmanager or not self.spawn then
			ply:ChatPrint("[AI] Необходимые сервисы не загружены")
			return
		end
		if not self:CheckCooldown(ply, "replace") then
			ply:ChatPrint("[AI] Подождите перед повторной заменой")
			return
		end

		local bot = self.botmanager:GetBotByOwner(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			ply:ChatPrint("[AI] У вас нет компаньона")
			return
		end

		-- Модель: аргумент -> персональная настройка -> глобальная -> дефолт
		local model = args[1]
		if not model or model == "" then
			model = self.state and self.state:getPlayerSetting(ply:SteamID64(), "Model_Path", nil) or nil
		end
		if not model or model == "" then
			model = self:GetSetting("Model_Path", "models/player/urban.mdl")
		end

		local oldNick = bot:Nick() or "компаньон"
		self.botmanager:RemoveBot(bot, "Замена компаньона", true)
		ply:ChatPrint("[AI] Компаньон " .. oldNick .. " удаляется, создаём нового...")

		timer.Simple(0.6, function()
			if not self.utils or not self.utils:IsValid(ply) then return end
			local newBot = self.spawn:CreateAICompanion(model, nil, ply)
			if newBot and newBot:IsValid() and newBot:IsPlayer() then
				ply:ChatPrint("[AI] Компаньон заменён!")
				if self.utils then
					self.utils.LogInfo("Commands", "Компаньон заменён для игрока %s", ply:Nick())
				end
			else
				ply:ChatPrint("[AI] Не удалось создать нового компаньона")
			end
		end)
	end)

	concommand.Add("ai_companion_teleport", function(ply)
		if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
		if not self:CheckCooldown(ply, "teleport") then
			ply:ChatPrint("[AI] Подождите перед повторным телепортом")
			return
		end

		local bot = self:FindOwnedBot(ply)
		if not self.utils or not self.utils:IsValid(bot) then
			ply:ChatPrint("[AI] У вас нет компаньона")
			return
		end

		if bot:InVehicle() then
			pcall(function() bot:ExitVehicle() end)
		end

		-- Ищем свободную точку вокруг владельца (сзади, справа, слева, спереди, в упор)
		local basePos = ply:GetPos()
		local aim = ply:GetAimVector()
		aim.z = 0
		if aim:Length() > 0 then aim:Normalize() end
		local right = aim:Angle():Right()

		local candidates = {
			basePos - aim * 80,
			basePos + right * 80,
			basePos - right * 80,
			basePos + aim * 120,
			basePos,
		}

		local mins, maxs = bot:GetHull()
		for _, pos in ipairs(candidates) do
			local checkPos = pos + Vector(0, 0, 2)
			local tr = util.TraceHull({
				start = checkPos,
				endpos = checkPos,
				mins = mins,
				maxs = maxs,
				filter = {bot, ply},
			})
			if not tr.Hit then
				bot:SetPos(checkPos)

				-- Сбрасываем навигацию/бой и возвращаем в режим следования
				if self.botmanager then
					local data = self.botmanager:GetData(bot)
					if data then
						if data.navigation then
							data.navigation.path = nil
							data.navigation.path_index = 1
							data.navigation.goal_pos = Vector(0, 0, 0)
						end
						if data.combat then
							data.combat.target = nil
						end
						self.botmanager:UpdateData(bot, data)
					end
					local states = (self.state and self.state:GetStates()) or {}
					self.botmanager:SetBotState(bot, states.FOLLOW or "following")
				end

				ply:ChatPrint("[AI] Компаньон телепортирован к вам")
				return
			end
		end

		ply:ChatPrint("[AI] Рядом нет свободного места для телепорта")
	end)

    concommand.Add("ai_companion_status", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end

        local bot = self:FindOwnedBot(ply)
        if not self.utils or not self.utils:IsValid(bot) then
            ply:ChatPrint("[AI] У вас нет компаньона")
            return
        end

        local data = self.botmanager:GetData(bot)
        local hp = bot:Health() .. "/" .. bot:GetMaxHealth()
        local armor = bot:Armor()
        local state = data and data.state or "idle"
        local task = data and data.task or bot:GetNWString("CurrentTask", "")

        ply:ChatPrint("[AI] === СТАТУС КОМПАНЬОНА ===")
        ply:ChatPrint("[AI] Имя: " .. bot:Nick())
        ply:ChatPrint("[AI] Здоровье: " .. hp)
        ply:ChatPrint("[AI] Броня: " .. armor)
        ply:ChatPrint("[AI] Состояние: " .. state .. " (" .. task .. ")")
        if data and data.config then
            ply:ChatPrint("[AI] Режимы: Стелс=" .. tostring(data.config.stealth_mode) ..
                " Защитник=" .. tostring(data.config.defender_mode) ..
                " Медик=" .. tostring(data.config.medic_mode))
        end
    end)

    concommand.Add("ai_reset_settings", function(ply)
        if not self.utils or not self.utils:IsValid(ply) then return end

        local defaultSettings = {
            LLM_IP = "127.0.0.1",
            LLM_Port = 1234,
            LLM_Model = "local-model",
            TTS_IP = "127.0.0.1",
            TTS_Port = 8188,
            TTS_Enabled = false,
            LLM_Enabled = true,
            Debug_Mode = false,
            Stealth_Mode = false,
            Defender_Mode = false,
            Medic_Mode = false,
            Pacifist_Mode = false,
            Aggressive_Mode = false,
            Prefix_Text = "[AI]",
            Prefix_Color_R = 255,
            Prefix_Color_G = 200,
            Prefix_Color_B = 0,
            Prefix_Rainbow = false,
            Model_Path = "models/player/urban.mdl",
            Companion_Nick = "AI_Companion",
            Combat_Weapon = "weapon_smg1",
            Melee_Weapon = "weapon_crowbar",
            Idle_Weapon = "weapon_physgun",
            LLM_Timeout = 60,
            TTS_Timeout = 120,
        }

        if self.state then
            for k, v in pairs(defaultSettings) do
                self.state:setSetting(k, v)
            end
            self.state:setState("TTS_Enabled", defaultSettings.TTS_Enabled)
            self.state:setState("LLM_Enabled", defaultSettings.LLM_Enabled)
        end

        local bot = nil
        if self.botmanager then
            bot = self.botmanager:GetBotByOwner(ply)
        end
        if self.utils and self.utils:IsValid(bot) then
            for k, v in pairs(defaultSettings) do
                self:SetBotSetting(ply, k, v)
            end
        end

        if self.utils and self.utils:IsValid(ply) then
            ply:ChatPrint("[AI] Настройки сброшены к стандартным!")
        end
    end)

    concommand.Add("ai_admin_list_bots", function(ply)
        if not self.utils or not self.utils:IsValid(ply) or not ply:IsAdmin() then return end
        if not self.botmanager then return end

        local bots = self.botmanager:GetAllBots()
        if #bots == 0 then
            ply:ChatPrint("[AI] Нет активных ботов")
            return
        end

        ply:ChatPrint("[AI] === СПИСОК БОТОВ (" .. #bots .. ") ===")
        for i, bot in ipairs(bots) do
            if self.utils and self.utils:IsValid(bot) then
                local data = self.botmanager:GetData(bot)
                local owner = data and data.owner
                local ownerName = self.utils:IsValid(owner) and owner:Nick() or "БЕЗ ВЛАДЕЛЬЦА!"
                ply:ChatPrint(string.format("[AI] %d. %s | Владелец: %s | HP: %s/%s | Состояние: %s",
                    i, bot:Nick(), ownerName, bot:Health(), bot:GetMaxHealth(), data and data.state or "idle"))
            end
        end
    end)

	concommand.Add("ai_auto_sync", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] Только администраторы!")
			return
		end

		if self.state then
			local current = self.state:getSetting("Auto_Sync_Global", true)
			local newVal = not current
			self.state:setSetting("Auto_Sync_Global", newVal)
			self.state:SaveToFile()
			local state = newVal and "ВКЛ" or "ВЫКЛ"
			ply:ChatPrint("[AI] Авто-синхронизация: " .. state)
			
			if self.utils then
				self.utils.LogInfo("Commands", "Авто-синхронизация установлена в %s администратором %s", state, ply:Nick())
			end
			
			
			net.Start("AI_GlobalSettingUpdated")  
			net.WriteString("Auto_Sync_Global")
			net.WriteString(tostring(newVal))
			net.Broadcast()
		else
			ply:ChatPrint("[AI] State не доступен")
		end
	end)

	concommand.Add("ai_sync_global", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] Только администраторы!")
			return
		end

		if self.state then
			self.state:SaveToFile()
			
			
			local settings = self.state:getRaw("Settings") or {}
			for key, value in pairs(settings) do
				if self.state:IsGlobalKey(key) then
					self.state:SyncSingleSettingToAll(key, value)
				end
			end
			
			ply:ChatPrint("[AI] Глобальные настройки синхронизированы")
			if self.utils then
				self.utils.LogInfo("Commands", "Глобальные настройки синхронизированы администратором %s", ply:Nick())
			end
		else
			ply:ChatPrint("[AI] State не доступен")
		end
	end)

	concommand.Add("ai_debug_mode", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] Только администраторы!")
			return
		end

		if self.state then
			local current = self.state:getSetting("Debug_Mode", false)
			local newVal = not current
			self.state:setSetting("Debug_Mode", newVal)
			self.state:SaveToFile()
			local state = newVal and "ВКЛ" or "ВЫКЛ"
			ply:ChatPrint("[AI] Режим отладки: " .. state)
			if self.utils then
				self.utils.LogInfo("Commands", "Режим отладки установлен в %s администратором %s", state, ply:Nick())
			end
			
			net.Start("AI_DebugMode_Updated")
			net.WriteBool(newVal)
			net.Broadcast()
		else
			ply:ChatPrint("[AI] State не доступен")
		end
	end)
    concommand.Add("ai_admin_force_bot", function(ply, cmd, args)
        if not self.utils or not self.utils:IsValid(ply) or not ply:IsAdmin() then return end

        if #args < 1 then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Использование: ai_admin_force_bot <игрок> [модель]")
            end
            return
        end

        local target = nil
        local searchName = string.lower(args[1])
        for _, p in ipairs(player.GetAll()) do
            if self.utils and self.utils:IsValid(p) and not p:IsBot() then
                local nick = string.lower(p:Nick())
                if string.find(nick, searchName) then
                    target = p
                    break
                end
            end
        end

        if not self.utils or not self.utils:IsValid(target) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Игрок не найден: " .. args[1])
            end
            return
        end

        if not self.botmanager or not self.spawn then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Необходимые сервисы не загружены")
            end
            return
        end

        local defaultModel = "models/player/urban.mdl"
        if self.state then
            defaultModel = self.state:getSetting("Model_Path") or defaultModel
        end
        local model = args[2] or defaultModel

        if self.botmanager:HasBot(target) then
            local existingBot = self.botmanager:GetBotByOwner(target)
            if self.utils and self.utils:IsValid(existingBot) then
                self.botmanager:RemoveBot(existingBot, "Принудительная замена админом", true)
                timer.Simple(0.5, function()
                    if self.utils and self.utils:IsValid(target) then
                        local newBot = self.spawn:CreateAICompanion(model, nil, target)
                        if self.utils and self.utils:IsValid(newBot) then
                            if self.utils and self.utils:IsValid(ply) then
                                ply:ChatPrint("[AI] Бот создан для " .. target:Nick())
                            end
                            target:ChatPrint("[AI] Администратор создал для вас компаньона!")
                        end
                    end
                end)
                return
            end
        end

        local newBot = self.spawn:CreateAICompanion(model, nil, target)
        if self.utils and self.utils:IsValid(newBot) then
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Бот создан для " .. target:Nick())
            end
            target:ChatPrint("[AI] Администратор создал для вас компаньона!")
        else
            if self.utils and self.utils:IsValid(ply) then
                ply:ChatPrint("[AI] Не удалось создать бота")
            end
        end
    end)

	concommand.Add("ai_ping_servers", function(ply)
		if not self.utils or not self.utils:IsValid(ply) then return end
		if not ply:IsAdmin() then
			ply:ChatPrint("[AI] Доступно только администраторам.")
			return
		end

		local llmIP = self:GetSetting("LLM_IP", "127.0.0.1")
		local llmPort = self:GetSetting("LLM_Port", 1234)
		local ttsIP = self:GetSetting("TTS_IP", "127.0.0.1")
		local ttsPort = self:GetSetting("TTS_Port", 8188)

		
		llmIP = string.gsub(tostring(llmIP), ":%d+$", "")
		ttsIP = string.gsub(tostring(ttsIP), ":%d+$", "")

		local llmUrl = "http://" .. llmIP .. ":" .. llmPort
		local ttsUrl = "http://" .. ttsIP .. ":" .. ttsPort

		
		local function printBoth(msg, color)
			print("[AI PING] " .. msg)  
			if IsValid(ply) then
				ply:ChatPrint("[AI PING] " .. msg)  
			end
		end

		printBoth("Проверка LLM: " .. llmUrl)
		printBoth("Проверка TTS: " .. ttsUrl)

		local llmChecked = false
		local ttsChecked = false
		local checkDone = false

		local function checkBothDone()
			if checkDone then return end
			if llmChecked and ttsChecked then
				checkDone = true
				printBoth("Проверка завершена")
			end
		end

		HTTP({
			url = llmUrl,
			method = "GET",
			timeout = 3,
			success = function(code, body)
				printBoth("✅ LLM доступен! (HTTP " .. code .. ")")
				llmChecked = true
				checkBothDone()
			end,
			failed = function(err)
				printBoth("❌ LLM недоступен! Проверьте LM Studio на " .. llmIP .. ":" .. llmPort)
				llmChecked = true
				checkBothDone()
			end
		})

		local checkUrl = ttsUrl
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
					printBoth("✅ TTS (ComfyUI) доступен! (HTTP " .. code .. ")")
				else
					printBoth("⚠️ TTS ответил с кодом: " .. code)
				end
				ttsChecked = true
				checkBothDone()
			end,
			failed = function(err)
				printBoth("❌ TTS недоступен! Проверьте ComfyUI на " .. ttsIP .. ":" .. ttsPort)
				ttsChecked = true
				checkBothDone()
			end
		})

		timer.Simple(6, function()
			if checkDone then return end
			checkDone = true
			if not llmChecked then
				printBoth("⏰ Таймаут LLM")
			end
			if not ttsChecked then
				printBoth("⏰ Таймаут TTS")
			end
			printBoth("Проверка завершена")
		end)
	end)
end

function Commands:SetupChatHook()
    if not SERVER then return end

    hook.Add("PlayerSay", "AICompanion_Commands_Secure", function(ply, text)
        if not self.utils or not self.utils:IsValid(ply) then return end
        if ply:IsBot() then return end
        if ply:GetNWBool("IsAICompanion", false) then return end

        local lowerText = string.lower(text)

        if string.StartWith(lowerText, "!ai ") then
            if not self:CheckCooldown(ply, "ai") then
                self:SendSystemMessage(ply, "Подождите 5 секунд перед следующим запросом.")
                return ""
            end

            local ok, remaining = self:CheckGlobalCooldown("llm_request", 3)
            if not ok then
                self:SendSystemMessage(ply, "Слишком много запросов LLM, подождите")
                return ""
            end

            local msg = string.Trim(string.sub(text, 5))
            if msg == "" then
                ply:ChatPrint("[AI] Введите текст после !ai")
                return ""
            end

            local maxPrivateLen = 300
            if self.config and self.config:get("Chat") then
                maxPrivateLen = self.config:get("Chat").MaxPrivateMessageLength or 300
            end
            msg = string.sub(msg, 1, maxPrivateLen)

            
            if self:GetState("LLM_Enabled", true) == false or self:GetSetting("LLM_Mode", "local") == "disabled" then
                ply:ChatPrint("[AI] LLM сейчас отключён.")
                return ""
            end
if self.llm then
                self.llm:Ask(ply, msg, true)
            else
                self:SendSystemMessage(ply, "LLM сервис не загружен")
            end
            return ""
        end

        if string.StartWith(lowerText, "!companion") and not game.SinglePlayer() then
            -- Ленивая защита, если реестр вдруг не создан
            if not self._companionCommands then
                self:RegisterCompanionCommands()
            end

            local afterCommand = string.sub(text, string.len("!companion") + 1)
            local cmd = string.Trim(afterCommand)
            if cmd == "" then
                ply:ChatPrint("[AI] Используйте !companion help для справки")
                return ""
            end

            local args = {}
            for word in string.gmatch(cmd, "[^%s]+") do
                table.insert(args, word)
            end
            local command = string.lower(args[1] or "")

            -- O(1)-поиск: сначала точное имя команды, потом алиас
            local entry = self._companionCommands[command]
            if not entry then
                local canonical = self._companionAliases[command]
                if canonical then entry = self._companionCommands[canonical] end
            end

            -- Неизвестная команда -> делегируем в сервис расширенных действий (LLMActions)
            if not entry then
                return nil
            end

            local bot = nil
            if entry.needsBot then
                bot = self:FindOwnedBot(ply)
                if not self.utils or not self.utils:IsValid(bot) then
                    ply:ChatPrint("[AI] У вас нет компаньона! Создайте: ai_companion_create")
                    return ""
                end
                if not self:IsBotOwner(bot, ply) then
                    ply:ChatPrint("[AI] Это не ваш компаньон!")
                    return ""
                end
            else
                -- Для команд без бота (help) бот не обязателен
                bot = self:FindOwnedBot(ply)
            end

            local states = self.state and self.state:GetStates() or {}
            local ok, err = pcall(entry.fn, bot, ply, args, states)
            if not ok then
                if self.utils then
                    self.utils.LogError("Commands", "Ошибка команды !companion %s: %s", command, tostring(err))
                end
                ply:ChatPrint("[AI] Ошибка при выполнении команды")
            end
            return ""
        end

        if not string.StartWith(lowerText, "!") and not string.StartWith(lowerText, "/") then
            local msg = string.Trim(text)
            if msg == "" then return nil end

            if self:GetState("LLM_Enabled", true) == false or self:GetSetting("LLM_Mode", "local") == "disabled" then
                return nil
            end

            if not self:CheckCooldown(ply, "ai") then
                self:SendSystemMessage(ply, "Подождите 5 секунд перед следующим запросом.")
                return nil
            end

            local ok, remaining = self:CheckGlobalCooldown("llm_request", 3)
            if not ok then
                self:SendSystemMessage(ply, "Слишком много запросов к LLM. Подождите " .. remaining .. " сек.")
                return nil
            end

            local maxLen = 300
            if self.config and self.config:get("Chat") then
                maxLen = self.config:get("Chat").MaxPrivateMessageLength or 300
            end
            msg = string.sub(msg, 1, maxLen)

            if self.llm then
                self.llm:Ask(ply, msg, false)
            end

            return nil
        end
    end)
end

function Commands:GetCleanPrefix(ply)
    if not self.utils or not self.utils:IsValid(ply) then return "AI" end
    local prefix = self:GetSetting("Prefix_Text", "[AI]")
    local clean = string.gsub(prefix, "^%[", "")
    clean = string.gsub(clean, "%]$", "")
    clean = string.Trim(clean)
    if clean == "" then clean = "AI" end
    return clean
end

function Commands:DoSitCommand(bot, ply, states)

    if not self.utils or not self.utils:IsValid(bot) then return end

    local vehicleService = self.vehicle
    if not vehicleService then
        local locator = _G.AI_GetLocator()
        if locator then
            vehicleService = locator:get("vehicle")
        end
    end

    if not vehicleService then
        bot:ChatPrint("[AI] Сервис транспорта не загружен!")
        return
    end

    if bot:InVehicle() then
        pcall(function() bot:ExitVehicle() end)
        return
    end

    local radius = 500
    local nearestVehicle = vehicleService:FindNearestVehicle(bot, radius)
    if not self.utils or not self.utils:IsValid(nearestVehicle) then
        bot:ChatPrint("[AI] Поблизости нет свободного транспорта.")
        return
    end

    local bestSeat = vehicleService:GetDriverSeat(nearestVehicle)
    if self.utils and self.utils:IsValid(bestSeat) then
        local success = pcall(function() bot:EnterVehicle(bestSeat) end)
        if success and bot:InVehicle() then
            local data = self.botmanager:GetData(bot)
            if data then
                data.vehicle = data.vehicle or {}
                data.vehicle.sit_by_command = true
                self.botmanager:UpdateData(bot, data)
            end
            self.botmanager:SetBotState(bot, states.SITTING or "sitting")
            bot:ChatPrint("[AI] Сел в транспорт.")
        end
    end
end

function Commands:FindPlayerByName(name)
    if not name or name == "" then return nil end
    name = string.lower(name)

    for _, ply in ipairs(player.GetAll()) do
        if self.utils and self.utils:IsValid(ply) and not ply:IsBot() then
            if string.lower(ply:Nick()) == name then return ply end
        end
    end
    return nil
end

function Commands:IsHostileEntity(ent)
    if not self.utils or not self.utils:IsValid(ent) then return false end
    if not ent:Alive() then return false end

    local class = ent:GetClass()
    if self.state and self.state:IsFriendlyNPC(class) then return false end

    if ent:IsPlayer() and not ent:IsBot() then return true end
    if ent:IsNPC() or ent:IsNextBot() then return true end

    return false
end

return Commands
