if AI_COMPANION_COMMANDS_LOADED then return end
AI_COMPANION_COMMANDS_LOADED = true
local AC = _G.AI_COMPANION
local function SendSystemMessage(ply, text)
    if not IsValid(ply) then return end
    net.Start("AI_Companion_Chat")
    net.WriteString(text)
    net.WriteColor(Color(255, 0, 0))
    net.WriteString("AI")
    net.Send(ply)
end
local function EnsureLoaded(file)
    if not _G.AI_Utils then
        local ok, err = pcall(include, "ai_companion/ai_companion_utils.lua")
        if not ok then return false end
    end
    return true
end
if not EnsureLoaded() then
    ErrorNoHalt("[AI Commands] Не удалось загрузить зависимости\n")
    return
end
local function FindOwnedBot(ply)
    if not IsValid(ply) then return nil, nil end
    if BotManager then
        local bot = BotManager:GetBotByOwner(ply)
        if IsValid(bot) then
            local data = BotManager:GetData(bot)
            if data and data.owner == ply then
                return bot, bot:EntIndex()
            end
        end
    end
    for _, bot in ipairs(player.GetAll()) do
        if IsValid(bot) and bot:IsBot() and bot:GetNWBool("IsAICompanion", false) then
            local owner = bot:GetNWEntity("AICompanionOwnerEnt")
            if IsValid(owner) and owner == ply then
                return bot, bot:EntIndex()
            end
        end
    end
    return nil, nil
end
local function IsBotOwner(bot, ply)
    if not IsValid(bot) or not IsValid(ply) then return false end
    if BotManager then
        local data = BotManager:GetData(bot)
        if data and data.owner == ply then
            return true
        end
    end
    local owner = bot:GetNWEntity("AICompanionOwnerEnt")
    return IsValid(owner) and owner == ply
end
local function GetPlayerSettingSafe(ply, key, default)
    if not IsValid(ply) then return default end
    if GetPlayerSetting then
        local val = GetPlayerSetting(ply, key)
        if val ~= nil then return val end
    end
    if AI_SETTINGS and AI_SETTINGS[key] ~= nil then
        return AI_SETTINGS[key]
    end
    return default
end
function SetBotSetting(ply, key, value)
    if not IsValid(ply) or ply:IsBot() then return false end
    local bot, botID = FindOwnedBot(ply)
    if not IsValid(bot) then
        if IsValid(ply) then
            print("[AI]  У вас нет компаньона")
        end
        return false
    end
    if not IsBotOwner(bot, ply) then
        if IsValid(ply) then
            print("[AI]  Это не ваш компаньон!")
        end
        return false
    end
    local data = BotManager and BotManager:GetData(bot)
    if not data then
        local settings = GetPlayerSettings(ply) or {}
        data = InitBotData(bot, ply, settings)
        if not data then
            AI_Utils.LogError("Commands", "Не удалось инициализировать BotData")
            return false
        end
        if BotManager then
            BotManager:UpdateData(bot, data)
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
    if key == "stealth_mode" or key == "defender_mode" or 
       key == "medic_mode" or key == "pacifist_mode" or key == "aggressive_mode" then
        cfg[key] = boolVal
        data._nw_cache[key] = boolVal
        applied = true
    elseif key == "combat_weapon" or key == "melee_weapon" or key == "idle_weapon" then
        cfg[key] = tostring(value)
        applied = true
    elseif key == "model_path" then
        if AI_Utils.IsValidModel(value) then
            cfg.model_path = value
            pcall(function() bot:SetModel(value) end)
            applied = true
        end
    elseif key == "companion_nick" then
        cfg.companion_nick = value
        pcall(function() bot:SetName(value) end)
        pcall(function() bot:SetNick(value) end)
        applied = true
    elseif key == "show_sender_name" then
        cfg.show_sender_name = boolVal
        applied = true
    else
        applied = true
    end
    if not applied then
        return false
    end
    if BotManager then
        BotManager:UpdateData(bot, data)
        BotManager:SyncToNWVars(bot)
    else
        AI_Companion.BotData[botID] = data
        SyncBotDataToNWVars(bot)
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    return true
end
function FindAnyFreeSeat(bot, radius)
    if not IsValid(bot) then return nil end
    radius = radius or 500
    local botPos = bot:GetPos()
    local best = nil
    local bestDist = radius * radius
    for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
        if IsValid(ent) then
            local class = ent:GetClass()
            if class == "prop_vehicle_jeep" or 
               class == "prop_vehicle_airboat" or
               class == "prop_vehicle_driveable" then
                local driver = ent:GetDriver()
                if not IsValid(driver) then
                    local dist = botPos:Distance(ent:GetPos())
                    if dist < bestDist then
                        bestDist = dist
                        best = ent
                    end
                end
            end
            if class == "prop_vehicle_prisoner_pod" then
                local driver = ent:GetDriver()
                if not IsValid(driver) then
                    local dist = botPos:Distance(ent:GetPos())
                    if dist < bestDist then
                        bestDist = dist
                        best = ent
                    end
                end
            end
        end
    end
    return best
end
concommand.Add("ai_companion_stealth", function(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local current = GetPlayerSettingSafe(ply, "stealth_mode", false)
    local newValue = not current
    if SetBotSetting(ply, "stealth_mode", newValue) then
        local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        if IsValid(ply) then
            print("[AI]  Стелс режим: " .. state)
        end
    end
end)
concommand.Add("ai_companion_defender", function(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local current = GetPlayerSettingSafe(ply, "defender_mode", false)
    local newValue = not current
    if SetBotSetting(ply, "defender_mode", newValue) then
        local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        if IsValid(ply) then
            print("[AI]  Режим защитника: " .. state)
        end
    end
end)
concommand.Add("ai_companion_medic", function(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local current = GetPlayerSettingSafe(ply, "medic_mode", false)
    local newValue = not current
    if SetBotSetting(ply, "medic_mode", newValue) then
        local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        if IsValid(ply) then
            print("[AI]  Режим медика: " .. state)
        end
    end
end)
concommand.Add("ai_companion_pacifist", function(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local current = GetPlayerSettingSafe(ply, "pacifist_mode", false)
    local newValue = not current
    if SetBotSetting(ply, "pacifist_mode", newValue) then
        local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        if IsValid(ply) then
            print("[AI]  Пацифистский режим: " .. state)
        end
    end
end)
concommand.Add("ai_companion_aggressive", function(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local current = GetPlayerSettingSafe(ply, "aggressive_mode", false)
    local newValue = not current
    if SetBotSetting(ply, "aggressive_mode", newValue) then
        local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        if IsValid(ply) then
            print("[AI]  Агрессивный режим: " .. state)
        end
    end
end)
concommand.Add("ai_companion_combat_weapon", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    if #args < 1 then
        if IsValid(ply) then
            print("[AI] Использование: ai_companion_combat_weapon <класс_оружия>")
        end
        return
    end
    local weapon = args[1]
    if not weapons.Get(weapon) then
        if IsValid(ply) then
            print("[AI]  Оружие не найдено: " .. weapon)
        end
        return
    end
    if SetBotSetting(ply, "combat_weapon", weapon) then
        local bot = GetCompanion(ply)
        if IsValid(bot) then
            if not bot:HasWeapon(weapon) then bot:Give(weapon) end
            local state = GetBotState(bot)
            if state == AC.Companion.States.COMBAT then
                bot:SelectWeapon(weapon)
            end
        end
        if IsValid(ply) then
            print("[AI]  Боевое оружие: " .. weapon)
        end
    end
end)
concommand.Add("ai_companion_melee_weapon", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    if #args < 1 then
        if IsValid(ply) then
            print("[AI] Использование: ai_companion_melee_weapon <класс_оружия>")
        end
        return
    end
    local weapon = args[1]
    if not weapons.Get(weapon) then
        if IsValid(ply) then
            print("[AI]  Оружие не найдено: " .. weapon)
        end
        return
    end
    if SetBotSetting(ply, "melee_weapon", weapon) then
        local bot = GetCompanion(ply)
        if IsValid(bot) and not bot:HasWeapon(weapon) then bot:Give(weapon) end
        if IsValid(ply) then
            print("[AI]  Оружие ближнего боя: " .. weapon)
        end
    end
end)
concommand.Add("ai_companion_idle_weapon", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    if #args < 1 then
        if IsValid(ply) then
            print("[AI] Использование: ai_companion_idle_weapon <класс_оружия>")
        end
        return
    end
    local weapon = args[1]
    if not weapons.Get(weapon) then
        if IsValid(ply) then
            print("[AI]  Оружие не найдено: " .. weapon)
        end
        return
    end
    if SetBotSetting(ply, "idle_weapon", weapon) then
        local bot = GetCompanion(ply)
        if IsValid(bot) and not bot:HasWeapon(weapon) then bot:Give(weapon) end
        local state = GetBotState(bot)
        if state ~= AC.Companion.States.COMBAT then
            bot:SelectWeapon(weapon)
        end
        if IsValid(ply) then
            print("[AI]  Мирное оружие: " .. weapon)
        end
    end
end)
concommand.Add("ai_companion_nick", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    if #args < 1 then
        if IsValid(ply) then
            print("[AI] Использование: ai_companion_nick <ник>")
        end
        return
    end
    local nick = table.concat(args, " ")
    nick = string.sub(nick, 1, AI.Config.UI.MaxNickLength or 32)
    nick = string.gsub(nick, "[<>\"'&]", "")
    if #nick < 1 or #nick > (AI.Config.UI.MaxNickLength or 32) then
        if IsValid(ply) then
            print("[AI]  Ник должен быть 1-32 символа")
        end
        return
    end
    if SetBotSetting(ply, "companion_nick", nick) then
        if IsValid(ply) then
            print("[AI]  Ник сохранен: " .. nick)
        end
    end
end)
concommand.Add("ai_companion_model", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    if #args < 1 then
        if IsValid(ply) then
            print("[AI] Использование: ai_companion_model <путь_к_модели>")
        end
        return
    end
    local model = args[1]
    if not AI_Utils.IsValidModel(model) then
        if IsValid(ply) then
            print("[AI]  Недопустимый путь модели")
        end
        return
    end
    if SetBotSetting(ply, "model_path", model) then
        if IsValid(ply) then
            print("[AI]  Модель сохранена: " .. model)
        end
    end
end)
concommand.Add("ai_companion_prefix", function(ply, cmd, args)
    if not IsValid(ply) then return end
    if #args < 1 then
        print("[AI] Использование: ai_companion_prefix <текст>")
        return
    end
    local text = table.concat(args, " ")
    text = string.sub(text, 1, AI.Config.UI.MaxNickLength or 32)
    text = string.gsub(text, "[<>\"'&]", "")
    if #text < 1 then
        print("[AI] Префикс не может быть пустым")
        return
    end
    if SetPlayerSetting then
        SetPlayerSetting(ply, "prefix_text", text)
    end
    if AI_SETTINGS then
        AI_SETTINGS.prefix_text = text
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    print("[AI] Префикс: " .. text)
end)
concommand.Add("ai_companion_prefix_color", function(ply, cmd, args)
    if not IsValid(ply) then return end
    if #args < 2 then
        print("[AI] Использование: ai_companion_prefix_color <r/g/b> <0-255>")
        return
    end
    local channel = string.lower(args[1])
    local value = tonumber(args[2])
    if not value or value < 0 or value > 255 then
        print("[AI] Цвет должен быть 0-255")
        return
    end
    local key = "prefix_" .. channel
    if SetPlayerSetting then
        SetPlayerSetting(ply, key, value)
    end
    if AI_SETTINGS then
        AI_SETTINGS[key] = value
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    print("[AI] Цвет обновлен!")
end)
concommand.Add("ai_companion_prefix_rainbow", function(ply)
    if not IsValid(ply) then return end
    local current = GetPlayerSettingSafe(ply, "prefix_rainbow", false)
    local newValue = not current
    if SetPlayerSetting then
        SetPlayerSetting(ply, "prefix_rainbow", newValue)
    end
    if AI_SETTINGS then
        AI_SETTINGS.prefix_rainbow = newValue
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
    print("[AI] Радужный префикс: " .. state)
end)
concommand.Add("ai_companion_show_name", function(ply)
    if not IsValid(ply) then return end
    local current = GetPlayerSettingSafe(ply, "show_sender_name", true)
    local newValue = not current
    if SetBotSetting(ply, "show_sender_name", newValue) then
        local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
        print("[AI] Показ имени в ответах: " .. state)
    end
end)
concommand.Add("ai_companion_tts", function(ply)
    if not IsValid(ply) then return end
    local current = GetPlayerSettingSafe(ply, "tts_enabled", false)
    local newValue = not current
    if SetPlayerSetting then
        SetPlayerSetting(ply, "tts_enabled", newValue)
    end
    if AI_SETTINGS then
        AI_SETTINGS.tts_enabled = newValue
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    _G.AI_Companion_TTS_Enabled = newValue
    local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
    print("[AI] TTS: " .. state)
end)
concommand.Add("ai_companion_llm", function(ply)
    if not IsValid(ply) then return end
    local current = GetPlayerSettingSafe(ply, "llm_enabled", true)
    local newValue = not current
    if SetPlayerSetting then
        SetPlayerSetting(ply, "llm_enabled", newValue)
    end
    if AI_SETTINGS then
        AI_SETTINGS.llm_enabled = newValue
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    _G.AI_Companion_LLM_Enabled = newValue
    local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
    print("[AI] LLM: " .. state)
end)
concommand.Add("ai_companion_create", function(ply, cmd, args)   
    if game.SinglePlayer() then
        if IsValid(ply) then 
            ply:ChatPrint("[AI] Включен соло-режим, бот недоступен.")
        end
        return
    end
    if not IsValid(ply) or not ply:IsPlayer() then 
        return 
    end
    if ply:IsBot() then 
        return 
    end
    if BotManager and BotManager:HasBot(ply) then
        if IsValid(ply) then
            ply:ChatPrint("[AI] У вас уже есть компаньон!")
            ply:ChatPrint("[AI] Используйте ai_companion_remove чтобы удалить")
        end
        return
    end
    local model = args[1] or _G.CurrentCompanionModel or AI_CONFIG.DEFAULT_MODEL
    local bot = CreateAICompanion(model, nil, ply)
    if IsValid(bot) then
        if IsValid(ply) then
            ply:ChatPrint("[AI]  Компаньон создан!")
        end
        if AI_Utils and AI_Utils.LogInfo then
            AI_Utils.LogInfo("Spawn", "Бот создан для игрока %s", ply:Nick())
        end
    else
        if IsValid(ply) then
            ply:ChatPrint("[AI]  Не удалось создать компаньона")
        end
        if AI_Utils and AI_Utils.LogWarn then
            AI_Utils.LogWarn("Spawn", "Не удалось создать бота для игрока %s", ply:Nick())
        end
    end
end)
concommand.Add("ai_companion_remove", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    local bot, botID = FindOwnedBot(ply)
    if not IsValid(bot) then
        if IsValid(ply) then
            print("[AI]  У вас нет компаньона")
        end
        return
    end
    if BotManager then
        local botNick = bot:Nick() or "компаньон"
        if BotManager:RemoveBot(bot, "Удалён игроком", true) then
            if IsValid(ply) then
                print("[AI]  Компаньон " .. botNick .. " удалён")
            end
        else
            if IsValid(ply) then
                print("[AI]  Не удалось удалить компаньона")
            end
        end
    else
        bot._aiBeingRemoved = true
        if UnregisterCompanionBot then
            UnregisterCompanionBot(bot, "Удалён игроком", true)
            if IsValid(ply) then
                print("[AI]  Компаньон удалён")
            end
        end
    end
end)
concommand.Add("ai_companion_replace", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    local bot, botID = FindOwnedBot(ply)
    if not IsValid(bot) then
        if IsValid(ply) then
            print("[AI]  У вас нет компаньона")
        end
        return
    end
    local model = args[1] or _G.CurrentCompanionModel or AI_CONFIG.DEFAULT_MODEL
    if BotManager then
        BotManager:RemoveBot(bot, "Замена компаньона", true)
    else
        bot._aiBeingRemoved = true
        if UnregisterCompanionBot then
            UnregisterCompanionBot(bot, "Замена компаньона")
        end
    end
    timer.Simple(0.5, function()
        if IsValid(ply) then
            if CreateAICompanion then
                local newBot = CreateAICompanion(model, nil, ply)
                if IsValid(newBot) then
                    print("[AI]  Новый компаньон создан!")
                else
                    print("[AI]  Не удалось создать нового компаньона")
                end
            elseif SpawnNewBot then
                local newBot = SpawnNewBot(model, nil, ply)
                if IsValid(newBot) then
                    print("[AI]  Новый компаньон создан!")
                else
                    print("[AI]  Не удалось создать нового компаньона")
                end
            end
        end
    end)
end)
concommand.Add("ai_companion_teleport", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    local bot, botID = FindOwnedBot(ply)
    if not IsValid(bot) then
        if IsValid(ply) then
            print("[AI]  У вас нет компаньона")
        end
        return
    end
    if not IsBotOwner(bot, ply) then
        if IsValid(ply) then
            print("[AI]  Это не ваш компаньон!")
        end
        return
    end
    local pos = ply:GetPos() + ply:GetForward() * 80
    local tr = util.TraceHull({
        start = pos + Vector(0, 0, 36),
        endpos = pos + Vector(0, 0, 36),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 72),
        filter = {bot, ply}
    })
    if not tr.Hit then
        bot:SetPos(pos)
    else
        bot:SetPos(pos + Vector(0, 0, 50))
    end
    bot:SetLocalVelocity(Vector(0, 0, 0))
    if IsValid(ply) then
        print("[AI]  Компаньон телепортирован.")
    end
end)
concommand.Add("ai_companion_status", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return end
    local function P(msg)
        ply:PrintMessage(HUD_PRINTCONSOLE, msg)
    end
    P("")
    P("═══════════════════════════════════════════════════════")
    P("        СТАТУС КОМПАНЬОНА")
    P("═══════════════════════════════════════════════════════")
    local bot, botID = FindOwnedBot(ply)
    if not IsValid(bot) then
        P("[AI]  У вас нет компаньона")
        P("[AI] Создайте: ai_companion_create")
        P("═══════════════════════════════════════════════════════")
        if IsValid(ply) then
            print("[AI]  У вас нет компаньона")
        end
        return
    end
    if not IsBotOwner(bot, ply) then
        P("[AI]  Внутренняя ошибка: бот не принадлежит вам")
        P("═══════════════════════════════════════════════════════")
        if IsValid(ply) then
            print("[AI]  Внутренняя ошибка: бот не принадлежит вам")
        end
        return
    end
    local data = BotManager and BotManager:GetData(bot)
    local hp = bot:Health() .. "/" .. bot:GetMaxHealth()
    local armor = bot:Armor()
    local state = data and data.state or GetBotState(bot) or "idle"
    local task = data and data.task or bot:GetNWString("CurrentTask", "")
    local inVeh = bot:InVehicle() and "в транспорте" or "пешком"
    local wep = "нет"
    local aw = bot:GetActiveWeapon()
    if IsValid(aw) then wep = aw:GetClass() end
    local uuid = bot._aiUUID or "нет"
    P("[AI] UUID: " .. uuid)
    P("[AI] Имя: " .. bot:Nick())
    P("[AI] Здоровье: " .. hp)
    P("[AI] Броня: " .. armor)
    P("[AI] Состояние: " .. state .. " (" .. task .. ")")
    P("[AI] Движение: " .. inVeh)
    P("[AI] Оружие: " .. wep)
    if data and data.config then
        P("[AI] Режимы: Стелс=" .. tostring(data.config.stealth_mode) ..
          " Защитник=" .. tostring(data.config.defender_mode) ..
          " Медик=" .. tostring(data.config.medic_mode))
        P("[AI] Оружие: " .. data.config.combat_weapon .. " / " .. data.config.melee_weapon .. " / " .. data.config.idle_weapon)
    end
    P("═══════════════════════════════════════════════════════")
    if IsValid(ply) then
        print("[AI]  Статус бота выведен в консоль (~)")
    end
end)
concommand.Add("ai_load_personal", function(ply)
    if not IsValid(ply) then return end
    if not LoadPlayerSettings then
        print("[AI]  Функция не доступна в этом режиме")
        return
    end
    LoadPlayerSettings(ply)
    print("[AI]  Личные настройки загружены!")
end)
concommand.Add("ai_load_global_force", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    if LoadGlobalSettings then
        LoadGlobalSettings(ply)
    end
end)
concommand.Add("ai_settings_status", function(ply)
    if not IsValid(ply) then return end
    local steamID = ply:SteamID64()
    local playerPath = GetPlayerSettingsPath and GetPlayerSettingsPath(ply)
    local hasPersonal = playerPath and file.Exists(playerPath, "DATA")
    local hasGlobal = file.Exists(GLOBAL_FILE, "DATA")
    print("[AI] === СТАТУС НАСТРОЕК ===")
    print("[AI] Личные настройки: " .. (hasPersonal and " есть" or " нет"))
    print("[AI] Глобальные настройки: " .. (hasGlobal and " есть" or " нет"))
end)
concommand.Add("ai_personal_to_global", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    if SaveGlobalSettings then
        SaveGlobalSettings(ply)
    end
end)
concommand.Add("ai_load_settings", function(ply)
    if not IsValid(ply) then return end
    if LoadPlayerSettings then
        LoadPlayerSettings(ply)
    end
end)
concommand.Add("ai_save_settings", function(ply)
    if not IsValid(ply) then return end
    if SavePlayerSettings then
        SavePlayerSettings(ply)
    end
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
        stealth_mode = false,
        defender_mode = false,
        medic_mode = false,
        pacifist_mode = false,
        aggressive_mode = false,
        prefix_text = "[AI]",
        prefix_r = 255,
        prefix_g = 200,
        prefix_b = 0,
        prefix_rainbow = false,
        model_path = "models/player/urban.mdl",
        companion_nick = "AI_Companion",
        combat_weapon = "weapon_smg1",
        melee_weapon = "weapon_crowbar",
        idle_weapon = "weapon_physgun",
        llm_timeout = 60,
        tts_timeout = 120
    }
    for k, v in pairs(defaultSettings) do
        if SetPlayerSetting then
            SetPlayerSetting(ply, k, v)
        end
        if AI_SETTINGS then
            AI_SETTINGS[k] = v
        end
    end
    if AI_SaveSettings then
        AI_SaveSettings()
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    local bot = GetCompanion(ply)
    if IsValid(bot) then
        for k, v in pairs(defaultSettings) do
            SetBotSetting(ply, k, v)
        end
    end
    print("[AI]  Настройки сброшены к стандартным!")
    if IsValid(_G.AICompanionMenuPanel) then
        _G.AICompanionMenuPanel:RefreshValues()
    end
end)
concommand.Add("ai_load_global", function(ply)
    if not IsValid(ply) then return end
    if LoadGlobalSettings then
        LoadGlobalSettings(ply)
    end
end)
concommand.Add("ai_reset_global", function(ply)
    if not IsValid(ply) then return end
    if ResetGlobalSettings then
        ResetGlobalSettings(ply)
    end
end)
concommand.Add("ai_migrate_now", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            print("[AI] Только администраторы могут запускать миграцию")
        end
        return
    end
    if BotManager and BotManager.MigrateFromLegacy then
        local migrated, errors = BotManager:MigrateFromLegacy()
        print("[AI] Миграция выполнена: " .. migrated .. " ботов, " .. errors .. " ошибок")
    else
        print("[AI]  BotManager не загружен")
    end
end)
concommand.Add("ai_admin_force_bot", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            print("[AI]  Только администраторы!")
        end
        return
    end
    if #args < 1 then
        if IsValid(ply) then
            print("[AI] Использование: ai_admin_force_bot <игрок> [модель]")
        end
        return
    end
    local target = nil
    local searchName = string.lower(args[1])
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and not p:IsBot() then
            local nick = string.lower(p:Nick())
            if string.find(nick, searchName) then
                target = p
                break
            end
        end
    end
    if not IsValid(target) then
        if IsValid(ply) then
            print("[AI]  Игрок не найден: " .. args[1])
        end
        return
    end
    local model = args[2] or _G.CurrentCompanionModel or AI_CONFIG.DEFAULT_MODEL
    if BotManager and BotManager:HasBot(target) then
        local existingBot = BotManager:GetBotByOwner(target)
        if IsValid(existingBot) then
            if IsValid(ply) then
                print("[AI] У игрока " .. target:Nick() .. " уже есть бот, удаляю...")
            end
            BotManager:RemoveBot(existingBot, "Принудительная замена админом", true)
            timer.Simple(0.5, function()
                if IsValid(target) then
                    if CreateAICompanion then
                        local newBot = CreateAICompanion(model, nil, target)
                        if IsValid(newBot) then
                            if IsValid(ply) then
                                print("[AI]  Бот создан для " .. target:Nick())
                            end
                            if IsValid(target) then
                                target:ChatPrint("[AI]  Администратор создал для вас компаньона!")
                            end
                        else
                            if IsValid(ply) then
                                print("[AI]  Не удалось создать бота")
                            end
                        end
                    end
                end
            end)
            return
        end
    end
    if CreateAICompanion then
        local newBot = CreateAICompanion(model, nil, target)
        if IsValid(newBot) then
            if IsValid(ply) then
                print("[AI]  Бот создан для " .. target:Nick())
            end
            if IsValid(target) then
                target:ChatPrint("[AI]  Администратор создал для вас компаньона!")
            end
        else
            if IsValid(ply) then
                print("[AI]  Не удалось создать бота")
            end
        end
    end
end)
concommand.Add("ai_admin_remove_bot", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            print("[AI]  Только администраторы!")
        end
        return
    end
    if #args < 1 then
        if IsValid(ply) then
            print("[AI] Использование: ai_admin_remove_bot <игрок>")
        end
        return
    end
    local target = nil
    local searchName = string.lower(args[1])
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and not p:IsBot() then
            local nick = string.lower(p:Nick())
            if string.find(nick, searchName) then
                target = p
                break
            end
        end
    end
    if not IsValid(target) then
        if IsValid(ply) then
            print("[AI]  Игрок не найден: " .. args[1])
        end
        return
    end
    if BotManager then
        local bot = BotManager:GetBotByOwner(target)
        if not IsValid(bot) then
            if IsValid(ply) then
                print("[AI]  У игрока " .. target:Nick() .. " нет бота")
            end
            return
        end
        BotManager:RemoveBot(bot, "Удалён администратором", true)
        if IsValid(ply) then
            print("[AI]  Бот удалён у " .. target:Nick())
        end
        if IsValid(target) then
            target:ChatPrint("[AI]  Ваш компаньон был удалён администратором")
        end
    end
end)
concommand.Add("ai_admin_list_bots", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            print("[AI]  Только администраторы!")
        end
        return
    end
    if BotManager then
        local bots = BotManager:GetAllBots()
        if #bots == 0 then
            if IsValid(ply) then
                print("[AI]  Нет активных ботов")
            end
            return
        end
        if IsValid(ply) then
            print("[AI]  === СПИСОК БОТОВ (" .. #bots .. ") ===")
        end
        for i, bot in ipairs(bots) do
            if IsValid(bot) then
                local data = BotManager:GetData(bot)
                local owner = data and data.owner
                local ownerName = IsValid(owner) and owner:Nick() or " БЕЗ ВЛАДЕЛЬЦА!"
                local hp = math.Round(bot:Health()) .. "/" .. math.Round(bot:GetMaxHealth())
                local state = data and data.state or GetBotState(bot) or "idle"
                local uuid = bot._aiUUID or "нет"
                if IsValid(ply) then
                    print(string.format(
                        "[AI] %d. %s | UUID: %s | Владелец: %s | HP: %s | Состояние: %s",
                        i, bot:Nick(), uuid, ownerName, hp, state
                    ))
                end
            end
        end
    end
end)
concommand.Add("ai_tts_global_on", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    _G.AI_Companion_TTS_Enabled = true
    _G.AI_Companion_TTS_Global = true
    if AI_SETTINGS then
        AI_SETTINGS.tts_enabled = true
        if AI_SaveSettings then AI_SaveSettings() end
    end
    print("[AI] TTS включен глобально")
    if SERVER then
        net.Start("AI_TTS_Global_Status")
        net.WriteBool(true)
        net.Broadcast()
    end
end)
concommand.Add("ai_test_llm", function(ply)
    if not IsValid(ply) then return end
    print("[AI TEST] ═══════════════════════════════════════════")
    print("[AI TEST] ПРОВЕРКА ПОДКЛЮЧЕНИЯ К LLM")
    print("[AI TEST] Игрок: " .. ply:Nick())
    local llmEnabled = AI_SETTINGS.llm_enabled
    if not llmEnabled then
        local msg = " LLM отключён в настройках"
        ply:ChatPrint("[AI] " .. msg)
        print("[AI TEST] " .. msg)
        return
    end
    local ip = AI_SETTINGS.llm_ip or "127.0.0.1"
    local port = AI_SETTINGS.llm_port or 1234
    local url = "http://" .. ip .. ":" .. port
    print("[AI TEST] URL: " .. url)
    ply:ChatPrint("[AI] Проверка LLM (" .. url .. ")...")
    HTTP({
        url = url,
        method = "GET",
        timeout = 3,
        success = function(code, body)
            local msg = " LLM доступен! (HTTP " .. code .. ")"
            ply:ChatPrint("[AI] " .. msg)
            print("[AI TEST] " .. msg)
            print("[AI TEST] ═══════════════════════════════════════════")
        end,
        failed = function(err)
            local msg = " LLM недоступен! Проверьте LM Studio на " .. ip .. ":" .. port
            ply:ChatPrint("[AI] " .. msg)
            print("[AI TEST] " .. msg)
            print("[AI TEST] ═══════════════════════════════════════════")
        end
    })
end)
concommand.Add("ai_test_tts", function(ply)
    if not IsValid(ply) then return end
    print("[AI TTS TEST] ═══════════════════════════════════════════")
    print("[AI TTS TEST] ПРОВЕРКА ПОДКЛЮЧЕНИЯ К TTS")
    print("[AI TTS TEST] Игрок: " .. ply:Nick())
    local ttsEnabled = AI_SETTINGS.tts_enabled
    if not ttsEnabled then
        local msg = " TTS отключён в настройках"
        ply:ChatPrint("[AI] " .. msg)
        print("[AI TTS TEST] " .. msg)
        print("[AI TTS TEST] Включите TTS: ai_tts_global_on")
        print("[AI TTS TEST] ═══════════════════════════════════════════")
        return
    end
    local ip = AI_SETTINGS.comfyui_ip or "127.0.0.1"
    local port = AI_SETTINGS.comfyui_port or 8188
    local url = "http://" .. ip .. ":" .. port
    print("[AI TTS TEST] URL: " .. url)
    ply:ChatPrint("[AI] Проверка TTS (ComfyUI) на " .. url .. "...")
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
                print("[AI TTS TEST] " .. msg)
            else
                local msg = " ComfyUI ответил с кодом: " .. code
                ply:ChatPrint("[AI] " .. msg)
                print("[AI TTS TEST] " .. msg)
            end
            print("[AI TTS TEST] ═══════════════════════════════════════════")
        end,
        failed = function(err)
            local msg = " ComfyUI недоступен! " .. tostring(err)
            ply:ChatPrint("[AI] " .. msg)
            print("[AI TTS TEST] " .. msg)
            print("[AI TTS TEST] Проверьте ComfyUI на " .. ip .. ":" .. port)
            print("[AI TTS TEST] ═══════════════════════════════════════════")
        end
    })
end)
concommand.Add("ai_tts_global_off", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    _G.AI_Companion_TTS_Enabled = false
    _G.AI_Companion_TTS_Global = false
    if AI_SETTINGS then
        AI_SETTINGS.tts_enabled = false
        if AI_SaveSettings then AI_SaveSettings() end
    end
    print("[AI] TTS отключен глобально")
    if SERVER then
        net.Start("AI_TTS_Global_Status")
        net.WriteBool(false)
        net.Broadcast()
    end
end)
concommand.Add("ai_tts_toggle", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    if _G.AI_Companion_TTS_Enabled then
        RunConsoleCommand("ai_tts_global_off")
    else
        RunConsoleCommand("ai_tts_global_on")
    end
end)
concommand.Add("ai_tts_status", function(ply)
    if not IsValid(ply) then return end
    local status = _G.AI_Companion_TTS_Enabled and " ВКЛЮЧЕН" or " ОТКЛЮЧЕН"
    print("[AI] === СТАТУС TTS ===")
    print("[AI] Глобальный TTS: " .. status)
    print("[AI] URL ComfyUI: " .. AI_CONFIG.GetTTSURL())
end)
concommand.Add("ai_tts_personal", function(ply)
    if not IsValid(ply) then return end
    if not _G.AI_Companion_TTS_Enabled then
        print("[AI] TTS отключен администратором!")
        return
    end
    local current = GetPlayerSettingSafe(ply, "tts_personal", true)
    local newValue = not current
    if SetPlayerSetting then
        SetPlayerSetting(ply, "tts_personal", newValue)
    end
    if AI_SETTINGS then
        AI_SETTINGS.tts_personal = newValue
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    local state = newValue and "ВКЛ" or "ВЫКЛ"
    print("[AI] Персональный TTS: " .. state)
end)
concommand.Add("ai_llm_ip", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    if #args < 1 then
        local ip = _G.AI_LLM_IP or AI_CONFIG.Network.LLM.IP or "127.0.0.1"
        local port = _G.AI_LLM_PORT or AI_CONFIG.Network.LLM.Port or 1234
        print("[AI] Текущий LLM IP: " .. ip .. ":" .. port)
        if IsValid(ply) then print("[AI] Текущий LLM IP: " .. ip .. ":" .. port) end
        return
    end
    local input = args[1]
    local ip, portFromInput = input:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
    if not ip then ip = input:match("^(%d+%.%d+%.%d+%.%d+)$") or input end
    local ok, err = AI_Utils.ValidateIP(ip)
    if not ok then
        print("[AI] " .. err)
        if IsValid(ply) then print("[AI] " .. err) end
        return
    end
    local port = portFromInput or (args[2] and tonumber(args[2])) or 1234
    local ok2, portNum = AI_Utils.ValidatePort(port)
    if not ok2 then
        print("[AI] " .. portNum)
        if IsValid(ply) then print("[AI] " .. portNum) end
        return
    end
    _G.AI_LLM_IP = ip
    _G.AI_LLM_PORT = portNum
    if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
        AI_CONFIG.Network.LLM.IP = ip
        AI_CONFIG.Network.LLM.Port = portNum
    end
    if AI_SETTINGS then
        AI_SETTINGS.llm_ip = ip
        AI_SETTINGS.llm_port = portNum
        if AI_SaveSettings then AI_SaveSettings() end
    end
    print("[AI]  LLM IP установлен: " .. ip .. ":" .. portNum)
    if IsValid(ply) then print("[AI]  LLM IP: " .. ip .. ":" .. portNum) end
end)
concommand.Add("ai_llm_port", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    if #args < 1 then
        local port = _G.AI_LLM_PORT or AI_CONFIG.Network.LLM.Port or 1234
        print("[AI] Текущий LLM Port: " .. port)
        if IsValid(ply) then print("[AI] Текущий LLM Port: " .. port) end
        return
    end
    local port = tonumber(args[1])
    local ok, portNum = AI_Utils.ValidatePort(port)
    if not ok then
        print("[AI] " .. portNum)
        if IsValid(ply) then print("[AI] " .. portNum) end
        return
    end
    _G.AI_LLM_PORT = portNum
    if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
        AI_CONFIG.Network.LLM.Port = portNum
    end
    if AI_SETTINGS then
        AI_SETTINGS.llm_port = portNum
        if AI_SaveSettings then AI_SaveSettings() end
    end
    print("[AI]  LLM Port установлен: " .. portNum)
    if IsValid(ply) then print("[AI]  LLM Port: " .. portNum) end
end)
concommand.Add("ai_tts_ip", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    if #args < 1 then
        local ip = _G.AI_COMFYUI_IP or AI_CONFIG.Network.TTS.IP or "127.0.0.1"
        local port = _G.AI_COMFYUI_PORT or AI_CONFIG.Network.TTS.Port or 8188
        print("[AI] Текущий TTS IP: " .. ip .. ":" .. port)
        if IsValid(ply) then print("[AI] Текущий TTS IP: " .. ip .. ":" .. port) end
        return
    end
    local input = args[1]
    local ip, portFromInput = input:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
    if not ip then ip = input:match("^(%d+%.%d+%.%d+%.%d+)$") or input end
    local ok, err = AI_Utils.ValidateIP(ip)
    if not ok then
        print("[AI] " .. err)
        if IsValid(ply) then print("[AI] " .. err) end
        return
    end
    local port = portFromInput or (args[2] and tonumber(args[2])) or 8188
    local ok2, portNum = AI_Utils.ValidatePort(port)
    if not ok2 then
        print("[AI] " .. portNum)
        if IsValid(ply) then print("[AI] " .. portNum) end
        return
    end
    _G.AI_COMFYUI_IP = ip
    _G.AI_COMFYUI_PORT = portNum
    if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.TTS then
        AI_CONFIG.Network.TTS.IP = ip
        AI_CONFIG.Network.TTS.Port = portNum
    end
    if AI_SETTINGS then
        AI_SETTINGS.comfyui_ip = ip
        AI_SETTINGS.comfyui_port = portNum
        if AI_SaveSettings then AI_SaveSettings() end
    end
    print("[AI]  TTS IP установлен: " .. ip .. ":" .. portNum)
    if IsValid(ply) then print("[AI]  TTS IP: " .. ip .. ":" .. portNum) end
end)
concommand.Add("ai_companion_llm_model", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then print("[AI]  Только администраторы!") end
        return
    end
    if #args < 1 then
        local model = _G.AI_LLM_MODEL or AI_CONFIG.Network.LLM.Model or "local-model"
        print("[AI] Текущая LLM модель: " .. model)
        if IsValid(ply) then print("[AI] Текущая LLM модель: " .. model) end
        return
    end
    local model = table.concat(args, " ")
    model = string.sub(model, 1, 100)
    _G.AI_LLM_MODEL = model
    if AI_CONFIG and AI_CONFIG.Network and AI_CONFIG.Network.LLM then
        AI_CONFIG.Network.LLM.Model = model
    end
    if AI_SETTINGS then
        AI_SETTINGS.llm_model = model
        if AI_SaveSettings then AI_SaveSettings() end
    end
    print("[AI]  LLM модель установлена: " .. model)
    if IsValid(ply) then print("[AI]  LLM модель: " .. model) end
end)
concommand.Add("ai_ping_servers", function(ply)
    if not IsValid(ply) then 
        print("[AI PING] Ошибка: игрок не найден")
        return 
    end
    local llmIP = AI_SETTINGS.llm_ip or "127.0.0.1"
    local llmPort = AI_SETTINGS.llm_port or 1234
    local ttsIP = AI_SETTINGS.comfyui_ip or "127.0.0.1"
    local ttsPort = AI_SETTINGS.comfyui_port or 8188
    local llmUrl = "http://" .. llmIP .. ":" .. llmPort
    local ttsUrl = "http://" .. ttsIP .. ":" .. ttsPort
    print("[AI Ping] Пинг LLM: " .. llmUrl)
    print("[AI Ping] Пинг TTS: " .. ttsUrl)
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
            print("[AI PING] Получен ответ от LLM")
            llmChecked = true
            checkBothDone()
        end,
        failed = function(err)
            print("[AI PING] Попытка пинга LLM провалилась")
            llmChecked = true
            checkBothDone()
        end
    })
    HTTP({
        url = ttsUrl,
        method = "GET",
        timeout = 3,
        success = function(code, body)
            print("[AI PING] Получен ответ от TTS")
            ttsChecked = true
            checkBothDone()
        end,
        failed = function(err)
            print("[AI PING] Попытка пинга TTS провалилась")
            ttsChecked = true
            checkBothDone()
        end
    })
    timer.Simple(6, function()
        if checkDone then return end
        checkDone = true
        if not llmChecked then
            print("[AI PING] Попытка пинга LLM провалилась")
        end
        if not ttsChecked then
            print("[AI PING] Попытка пинга TTS провалилась")
        end
    end)
end)
concommand.Add("ai_companion_debug", function(ply)
    if not IsValid(ply) then return end
    if not ply:IsAdmin() then
        print("[AI] Доступно только администраторам.")
        return
    end
    local current = GetPlayerSettingSafe(ply, "debug_mode", false)
    local newValue = not current
    if SetPlayerSetting then
        SetPlayerSetting(ply, "debug_mode", newValue)
    end
    if AI_SETTINGS then
        AI_SETTINGS.debug_mode = newValue
    end
    if SERVER and SyncPlayerSettingsToClient then
        SyncPlayerSettingsToClient(ply)
    end
    if AI_CONFIG then
        AI_CONFIG.DEBUG_MODE = newValue
    end
    local state = newValue and "ВКЛЮЧЕН" or "ОТКЛЮЧЕН"
    print("[AI] Режим разработчика: " .. state)
end)
local settingsRequestCooldowns = {}
concommand.Add("ai_request_settings", function(ply)
    if not IsValid(ply) then return end
    if SERVER then
        SyncPlayerSettingsToClient(ply)
    end
end)
concommand.Add("ai_lang", function(ply, cmd, args)
    if not IsValid(ply) then return end
    if not ply:IsAdmin() then
        print("[AI] Только администраторы!")
        return
    end
    if not _L then
        print("[AI] Локализация не загружена!")
        return
    end
    local lang = args[1]
    if not lang then
        local prefix = _L:Get("ai_prefix")
        local current = _L:GetLang()
        local available = table.concat(_L:GetAvailable(), ", ")
        print(prefix .. " Текущий язык: " .. current)
        print(prefix .. " Доступные языки: " .. available)
        return
    end
    if _L:SetLang(lang) then
        local prefix = _L:Get("ai_prefix")
        print(prefix .. " Язык изменён на: " .. lang)
        if AI_SETTINGS then
            AI_SETTINGS.locale = lang
            if AI_SaveSettings then
                AI_SaveSettings()
            end
        end
    else
        local prefix = _L:Get("ai_prefix")
        print(prefix .. " Язык '" .. lang .. "' не найден")
    end
end)
concommand.Add("ai_sync_botdata", function(ply)
    if not IsValid(ply) then 
        print("[AI Sync] Ошибка: игрок не найден")
        return 
    end
    local bot = GetCompanion(ply)
    if not IsValid(bot) then
        print("[AI]  У вас нет компаньона")
        return
    end
    local settings = GetPlayerSettings(ply)
    local data = BotManager and BotManager:GetData(bot)
    if not data then
        data = InitBotData(bot, ply, settings or {})
        if not data then
            print("[AI]  Не удалось инициализировать данные")
            return
        end
        if BotManager then
            BotManager:UpdateData(bot, data)
        end
    end
    if not settings then
        print("[AI]  Настройки не найдены, используются дефолтные")
        settings = {}
    end
    data.owner = ply
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
    data.config.combat_weapon = settings.combat_weapon or data.config.combat_weapon
    data.config.melee_weapon = settings.melee_weapon or data.config.melee_weapon
    data.config.idle_weapon = settings.idle_weapon or data.config.idle_weapon
    data.config.stealth_mode = settings.stealth_mode or false
    data.config.defender_mode = settings.defender_mode or false
    data.config.medic_mode = settings.medic_mode or false
    data.config.pacifist_mode = settings.pacifist_mode or false
    data.config.aggressive_mode = settings.aggressive_mode or false
    data.config.model_path = settings.model_path or data.config.model_path
    data.config.companion_nick = settings.companion_nick or data.config.companion_nick
    if settings.show_sender_name ~= nil then
        data.config.show_sender_name = settings.show_sender_name
    end
    data._nw_cache.stealth_mode = data.config.stealth_mode
    data._nw_cache.defender_mode = data.config.defender_mode
    data._nw_cache.medic_mode = data.config.medic_mode
    data._nw_cache.pacifist_mode = data.config.pacifist_mode
    data._nw_cache.aggressive_mode = data.config.aggressive_mode
    data._nw_cache.owner_name = ply:Nick()
    data._nw_cache.is_ai_companion = true
    if BotManager then
        BotManager:UpdateData(bot, data)
        BotManager:SyncToNWVars(bot)
    else
        AI_Companion.BotData[bot:EntIndex()] = data
        SyncBotDataToNWVars(bot)
    end
    bot:SetNWBool("IsAICompanion", true)
    bot:SetNWEntity("AICompanionOwnerEnt", ply)
    bot:SetNWString("AICompanionOwner", ply:Nick())
    print("[AI]  Настройки применены к боту")
    if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
        print("[AI Sync] BotData синхронизирована для " .. ply:Nick())
    end
end)
local CommandCooldowns = {}
local GlobalCooldowns = {}
local function CheckCooldown(ply, cmd)
    if not IsValid(ply) then return false end
    local key = ply:EntIndex() .. "_" .. cmd
    local last = CommandCooldowns[key] or 0
    if CurTime() - last < AI.Config.RateLimits.CommandCooldown then return false end
    CommandCooldowns[key] = CurTime()
    return true
end
local function CheckGlobalCooldown(key, duration)
    local last = GlobalCooldowns[key] or 0
    if CurTime() - last < duration then
        return false, math.ceil(duration - (CurTime() - last))
    end
    GlobalCooldowns[key] = CurTime()
    return true, 0
end
hook.Add("PlayerSay", "AICompanion_Commands_Secure_v7", function(ply, text)
    if not IsValid(ply) then return end
    if ply:IsBot() then return end
    if ply:GetNWBool("IsAICompanion", false) then return end
    if #text > AI.Config.Chat.MaxMessageLength then
        print("[AI] Сообщение слишком длинное (макс." .. AI.Config.Chat.MaxMessageLength .. " символов)")
        return ""
    end
    local lowerText = string.lower(text)
    local cleanPrefix = AI.Utils.GetCleanPrefix(ply)
    if string.find(lowerText, "^" .. string.lower(cleanPrefix)) then
        return "" 
    end
    if string.find(lowerText, "%[" .. string.lower(cleanPrefix) .. "%]") then
        return "" 
    end
    if string.find(lowerText, string.lower(cleanPrefix) .. "%s*->") then
        return "" 
    end
    local statusWords = {"думаю", "думает", "thinking", "печата", "typing", "обрабатыв", "processing", "генер", "generating"}
    for _, word in ipairs(statusWords) do
        if string.find(lowerText, word) then
            local wordCount = 0
            for _ in string.gmatch(lowerText, "%S+") do 
                wordCount = wordCount + 1
            end
            if wordCount <= 3 then
                return "" 
            end
        end
    end
    if string.find(text, "->") and (string.find(text, "%[") or string.find(text, "%]")) then
        return "" 
    end
    if _G._AI_LastMessageTime and CurTime() - _G._AI_LastMessageTime < 2 then
        if string.find(lowerText, "думаю") or string.find(lowerText, "thinking") then
            return ""
        end
    end
    if string.StartWith(lowerText, "!ai ") then
        if not CheckCooldown(ply, "ai") then
            SendSystemMessage(ply, "Подождите 5 секунд перед следующим запросом.")
            return ""
        end
        local ok, remaining = CheckGlobalCooldown("llm_request", 3)
        if not ok then
            SendSystemMessage(ply, "Слишком много запросов LLM, пожалуйста, подождите")
            return ""
        end
        local msg = string.Trim(string.sub(text, 5))
        if msg == "" then
            print("[AI] Введите текст после !ai")
            return ""
        end
        msg = string.sub(msg, 1, AI.Config.Chat.MaxPrivateMessageLength or 300)
        local isPrivate = true
        local prefixColor = Color(
            AI_Companion_PrefixColorR or 255,
            AI_Companion_PrefixColorG or 200,
            AI_Companion_PrefixColorB or 0
        )
        if AI_Companion_PrefixRainbow then
            local hue = (CurTime() * 120) % 360
            prefixColor = HSVToColor(hue, 1, 1)
        end
        net.Start("AI_Companion_Private_Chat")
        net.WriteString(msg)
        net.WriteColor(prefixColor)
        net.WriteString(ply:Nick() or "Игрок")
        net.WriteString("AI")
        net.WriteString(ply:SteamID64())
        net.Send(ply)
        local reqID = requestCounter or 0
        requestCounter = reqID + 1
        xpcall(
            function() 
                if AskLMStudioAndRespond then
                    AskLMStudioAndRespond(ply, msg, requestCounter, isPrivate)
                end
            end,
            function(err)
                AI_Utils.LogError("Commands", "Ошибка LLM: %s", tostring(err))
                print("[AI] Ошибка при обращении к LLM")
            end
        )
        return ""
    end
	if string.StartWith(lowerText, "!companion") then
		local afterCommand = string.sub(text, string.len("!companion") + 1)
		local cmd = string.Trim(afterCommand)
		if cmd == "" then
			print("[AI] Использование: !companion <команда>")
			print("[AI] Доступно: follow, stop, sit, standup, attack, point, spawn, help, status")
			return ""
		end
		local args = {}
		for word in string.gmatch(cmd, "[^%s]+") do 
			table.insert(args, word) 
		end
		local command = args[1]
		local bot = FindOwnedBot(ply)
		if command ~= "spawn" then
			if not IsValid(bot) then
				print("[AI] У вас нет компаньона! Создайте: ai_companion_create")
				return ""
			end
			if not IsBotOwner(bot, ply) then
				print("[AI]  Это не ваш компаньон!")
				return ""
			end
		end
		local botID = bot and bot:EntIndex() or nil
		if command == "follow" then
			_G.AI_Companion_Disabled = false
			if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
			bot:SetNWEntity("AI_Glide_TargetVehicle", nil)
			SetBotState(bot, AC.Companion.States.FOLLOW)
			if IsValid(bot) then 
				bot:ChatPrint("[AI] Следую за " .. ply:Nick())
			end
			print("[AI] Компаньон следует за вами.")
			return ""
		end
		if command == "stop" then
			local data = BotManager and BotManager:GetData(bot)
			if data and data.combat then
				data.combat.target = nil
				if BotManager then BotManager:UpdateData(bot, data) end
			end
			if SetCombatTarget then
				SetCombatTarget(bot, nil, "none", "command")
			end
			SetBotState(bot, AC.Companion.States.IDLE)
			if IsValid(bot) then 
				bot:ChatPrint("[AI] Остановлен.")
				pcall(function() bot:SetLocalVelocity(Vector(0, 0, 0)) end)
			end
			print("[AI] Компаньон остановлен.")
			return ""
		end
		if command == "point" then
			local data = BotManager and BotManager:GetData(bot)
			if data and data.combat then
				data.combat.target = nil
				if BotManager then BotManager:UpdateData(bot, data) end
			end
			if SetCombatTarget then
				SetCombatTarget(bot, nil, "none", "command")
			end
			if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
			bot:SetNWEntity("AI_Glide_TargetVehicle", nil)
			if not data then
				data = GetBotData(bot) or {}
			end
			data.point = data.point or {}
			data.point.pos = bot:GetPos()
			data.point.angle = bot:EyeAngles()
			if BotManager then
				BotManager:UpdateData(bot, data)
			else
				AI_Companion.BotData[botID] = data
			end
			SetBotState(bot, AC.Companion.States.POINTING)
			if IsValid(bot) then 
				bot:ChatPrint("[AI] Держу точку.")
			end
			print("[AI] Компаньон поставлен на точку.")
			return ""
		end
		if command == "sit" then
			_G.AI_Companion_Disabled = false
			if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
			local seat = nil
			if FindNearestVehicle then
				local vehicle = FindNearestVehicle(bot, 500)
				if IsValid(vehicle) then
					seat = vehicle
				end
			end
			if not IsValid(seat) then
				if FindAnyFreeSeat then
					seat = FindAnyFreeSeat(bot, 500)
				end
			end
			if IsValid(seat) then
				local success = pcall(function() bot:EnterVehicle(seat) end)
				if success and bot:InVehicle() then
					SetBotState(bot, AC.Companion.States.SITTING)
					if IsValid(bot) then 
						bot:ChatPrint("[AI] Сижу.")
					end
					print("[AI] Компаньон сел.")
				else
					print("[AI] Не удалось сесть.")
				end
			else
				print("[AI] Поблизости нет свободных мест.")
				if IsValid(bot) then 
					bot:ChatPrint("[AI] Поблизости нет свободных мест.")
				end
			end
			return ""
		end
		if command == "standup" then
			_G.AI_Companion_Disabled = false
			if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
			bot:SetNWEntity("AI_Glide_TargetVehicle", nil)
			SetBotState(bot, AC.Companion.States.FOLLOW)
			if IsValid(bot) then 
				bot:ChatPrint("[AI] Вышел и следую за " .. ply:Nick())
			end
			print("[AI] Компаньон вышел и следует за вами.")
			return ""
		end
		if command == "attack" then
			if AI_Utils.IsPassenger(bot) then
				return ""
			end
			local botPos = bot:GetPos()
			local nearestEnemy = nil
			local nearestDist = AI.Config.Combat.CommandAttackRadius or 2000
			for _, ent in ipairs(AI_Utils.FindInSphere(botPos, AI.Config.Combat.CommandAttackRadius or 2000)) do
				if not IsValid(ent) then continue end
				if not ent:Alive() then continue end
				if ent == bot or ent == ply then continue end
				if IsHostileEntity(ent) or ent:IsPlayer() then
					local dist = botPos:Distance(ent:GetPos())
					if dist < nearestDist then
						nearestDist = dist
						nearestEnemy = ent
					end
				end
			end
			if IsValid(nearestEnemy) then
				if SetCombatTarget then
					SetCombatTarget(bot, nearestEnemy, "npc", "command")
				end
				local combatWep = GetBotCombatWeapon(bot)
				if not bot:HasWeapon(combatWep) then bot:Give(combatWep) end
				bot:SelectWeapon(combatWep)
				if IsValid(bot) then
					local name = nearestEnemy:IsPlayer() and nearestEnemy:Nick() or nearestEnemy:GetClass()
					bot:ChatPrint("[AI] Атакую " .. name)
				end
				print("[AI] Атака начата.")
			else
				if IsValid(bot) then 
					bot:ChatPrint("[AI] Врагов поблизости нет.")
				end
				print("[AI] Врагов поблизости нет.")
			end
			return ""
		end
		if command == "status" then
			local hp = math.Round(bot:Health()) .. "/" .. math.Round(bot:GetMaxHealth())
			local armor = math.Round(bot:Armor())
			local state = GetBotState(bot) or "idle"
			local task = bot:GetNWString("CurrentTask", "")
			local inVeh = bot:InVehicle() and " в транспорте" or " пешком"
			print("[AI] === Статус компаньона ===")
			print("[AI]  Имя: " .. (bot:Nick() or "неизвестно"))
			print("[AI]  Здоровье: " .. hp)
			print("[AI]  Броня: " .. armor)
			print("[AI]  Состояние: " .. state .. " (" .. task .. ")")
			print("[AI]  Движение: " .. inVeh)
			return ""
		end
		if command == "help" then
			print("[AI] === ДОСТУПНЫЕ КОМАНДЫ ===")
			print("[AI] !companion follow   - Следовать за игроком")
			print("[AI] !companion point    - Держать текущую позицию")
			print("[AI] !companion stop     - Полная остановка")
			print("[AI] !companion sit      - Сесть в транспорт")
			print("[AI] !companion standup  - Выйти и следовать")
			print("[AI] !companion attack   - Атаковать ближайшего врага")
			print("[AI] !companion spawn    - Создать объект (chair, zombie, healthkit...)")
			print("[AI] !companion status   - Статус компаньона")
			print("[AI] !companion help     - Эта справка")
			print("[AI] !ai <вопрос>        - Быстрый вопрос LLM")
			print("[AI]")
			print("[AI] Консольные команды:")
			print("[AI] ai_companion_create  - Создать бота")
			print("[AI] ai_companion_remove  - Удалить бота")
			print("[AI] ai_companion_replace - Заменить бота")
			return ""
		end
		print("[AI] Неизвестная команда: " .. command)
		print("[AI] Используйте !companion help для справки")
		return ""
	end
    if not string.StartWith(lowerText, "!") and not string.StartWith(lowerText, "/") then
        local msg = string.Trim(text)
        if msg == "" then return "" end
        local settings = GetPlayerSettings(ply)
        if not settings or not settings.llm_enabled then
            return nil
        end
        if not CheckCooldown(ply, "ai") then
            SendSystemMessage(ply, "Подождите 5 секунд перед следующим запросом.")
            return nil
        end
        local ok, remaining = CheckGlobalCooldown("llm_request", 3)
        if not ok then
            SendSystemMessage(ply, "Слишком много запросов к LLM. Подождите " .. remaining .. " сек.")
            return nil
        end
        msg = string.sub(msg, 1, AI.Config.Chat.MaxPrivateMessageLength or 300)
        local reqID = requestCounter or 0
        requestCounter = reqID + 1
        xpcall(
            function() 
                if AskLMStudioAndRespond then
                    AskLMStudioAndRespond(ply, msg, requestCounter)
                end
            end,
            function(err)
                AI_Utils.LogError("Commands", "Ошибка LLM: %s", tostring(err))
                print("[AI] Ошибка при обращении к LLM")
            end
        )
        return nil
    end
end)
_G.FindOwnedBot = FindOwnedBot
_G.FindAnyFreeSeat = FindAnyFreeSeat
print("[AI Commands] v2 загружен (интеграция с BotManager)")
MsgC(Color(100, 200, 255), "[AI Commands] v2 загружен\n")