if AI_COMPANION_DATA_LOADED then return end
AI_COMPANION_DATA_LOADED = true
local AC = _G.AI_COMPANION
_G.AI_Companion = _G.AI_Companion or {}
local DEFAULT_BOT_DATA = {
    botID = nil,
    owner = nil,
    creationTime = 0,
    uuid = nil,
    config = {
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
    },
    state = "idle",
    task = "",
    flags = {
        is_in_combat = false,
        is_following = false,
        is_pointing = false,
        is_in_vehicle = false,
        is_sitting = false,
        is_medic_healing = false,
    },
    combat = {
        target = nil,
        target_type = nil,
        triggered_by = nil,
        last_attack_time = 0,
        last_combat_end = 0,
        frag_last_throw = 0,
        rpg_last_fire = 0,
        alt_fire_timer = 0,
        weapon_switch_wait = 0,
        weapon_wait_ticks = 0,
        next_strafe_change = 0,
        strafe_dir = 1,
        last_melee_give = 0,
        last_damage_time = 0,
        heal_cooldown_until = 0,
        medic_post_combat_cooldown = 0,
    },
    navigation = {
        path = nil,
        path_index = 1,
        goal_pos = Vector(0,0,0),
        target_key = -1,
        fail_count = 0,
        disabled_until = 0,
        stuck = {
            pos = Vector(0,0,0),
            time = 0,
            unstuck_dir = nil,
            unstuck_until = 0,
            pos_history = {},
            no_progress_time = 0,
            wp_stuck_time = 0,
            wp_stuck_pos = Vector(0,0,0),
            last_dist_to_goal = nil,
            last_dist_to_wp = nil,
            loop_key = nil,
            loop_count = 0,
            loop_reset = 0,
            teleport_fails = 0,
            in_narrow_passage = false,
        },
        repath = {
            force = false,
            next_force = 0,
            last_wall = 0,
            cooldown = 0,
            last_time = 0,
        },
        door_wait = 0,
        slide_time = 0,
        area_cache = {
            pos = Vector(0,0,0),
            area = nil,
            time = 0,
        },
    },
    vehicle = {
        locked_vehicle = nil,
        locked_seat = nil,
        sit_by_command = false,
        is_driver = false,
        was_in_vehicle = false,
        cached_turret = nil,
        cached_weapons = nil,
        path = nil,
        path_time = 0,
        path_index = 1,
        dead_zone_active = false,
        engine_state = "on",
        engine_idle_timer = 0,
    },
    point = {
        pos = nil,
        angle = nil,
    },
    _nw_cache = {
        stealth_mode = false,
        defender_mode = false,
        medic_mode = false,
        pacifist_mode = false,
        aggressive_mode = false,
        state = "idle",
        task = "",
        is_ai_companion = true,
        owner_name = "",
    },
}
local function IsCompanionBot(ent)
    if not IsValid(ent) then return false end
    if not ent:IsPlayer() then return false end
    if not ent:IsBot() then return false end
    if ent:GetNWBool("IsAICompanion", false) == true then return true end
    if ent._aiUUID then return true end
    if BotManager and BotManager.BOT_INDEX then
        if BotManager.BOT_INDEX[ent:EntIndex()] then return true end
    end
    return false
end
function InitBotData(bot, owner, settings)
    if not IsValid(bot) or not bot:IsBot() then 
        AI_Utils.LogError("Data", "InitBotData: невалидный бот")
        return nil 
    end
    local existingData = BotManager and BotManager:GetData(bot)
    if existingData then
        if IsValid(owner) then
            existingData.owner = owner
            BotManager:UpdateData(bot, existingData)
        end
        return existingData
    end
    local uuid = bot._aiUUID
    if not uuid then
        if BotManager and BotManager.GenerateUUID then
            uuid = BotManager:GenerateUUID()
        else
            uuid = string.format("%08x-%04x-%04x-%04x-%012x",
                bit.band(util.CRC("bot_" .. os.time() .. "_" .. math.random(1, 9999999)), 0xFFFFFFFF),
                math.random(0, 0xFFFF),
                math.random(0, 0xFFFF),
                math.random(0, 0xFFFF),
                math.random(0, 0xFFFFFFFFFFFF)
            )
        end
        bot._aiUUID = uuid
    end
    local data = table.Copy(DEFAULT_BOT_DATA)
    data.botID = bot:EntIndex()
    data.owner = owner
    data.creationTime = CurTime()
    data.uuid = uuid
    if settings then
        local cfg = data.config
        if settings.combat_weapon then cfg.combat_weapon = settings.combat_weapon end
        if settings.melee_weapon then cfg.melee_weapon = settings.melee_weapon end
        if settings.idle_weapon then cfg.idle_weapon = settings.idle_weapon end
        if settings.stealth_mode ~= nil then cfg.stealth_mode = settings.stealth_mode end
        if settings.defender_mode ~= nil then cfg.defender_mode = settings.defender_mode end
        if settings.medic_mode ~= nil then cfg.medic_mode = settings.medic_mode end
        if settings.pacifist_mode ~= nil then cfg.pacifist_mode = settings.pacifist_mode end
        if settings.aggressive_mode ~= nil then cfg.aggressive_mode = settings.aggressive_mode end
        if settings.model_path then cfg.model_path = settings.model_path end
        if settings.companion_nick then cfg.companion_nick = settings.companion_nick end
        if settings.show_sender_name ~= nil then cfg.show_sender_name = settings.show_sender_name end
        data._nw_cache.stealth_mode = cfg.stealth_mode
        data._nw_cache.defender_mode = cfg.defender_mode
        data._nw_cache.medic_mode = cfg.medic_mode
        data._nw_cache.pacifist_mode = cfg.pacifist_mode
        data._nw_cache.aggressive_mode = cfg.aggressive_mode
        if IsValid(owner) then
            data._nw_cache.owner_name = owner:Nick()
        end
        data._nw_cache.is_ai_companion = true
    end
    return data
end
function ValidateBotOwnership(bot, ply)
    if not IsValid(bot) or not IsValid(ply) then 
        AI_Utils.LogDebug("Data", "ValidateBotOwnership: невалидные аргументы")
        return false 
    end
    if not IsCompanionBot(bot) then 
        AI_Utils.LogDebug("Data", "ValidateBotOwnership: сущность не является ботом-компаньоном")
        return false 
    end
    local data = GetBotData(bot)
    if not data then 
        AI_Utils.LogDebug("Data", "ValidateBotOwnership: данные не найдены")
        return false 
    end
    if IsValid(data.owner) and data.owner == ply then
        return true
    end
    local nwOwner = bot:GetNWEntity("AICompanionOwnerEnt")
    if IsValid(nwOwner) and nwOwner == ply then
        data.owner = ply
        if BotManager then
            BotManager:UpdateData(bot, data)
        end
        return true
    end
    return false
end
function UpdateBotData(bot, newData)
    if not IsValid(bot) then return false end
    if BotManager and BotManager.UpdateData then
        return BotManager:UpdateData(bot, newData)
    end
    if AC.Companion then
        AC.Companion.BotData = AC.Companion.BotData or {}
        AC.Companion.BotData[bot:EntIndex()] = newData
        return true
    end
    return false
end
function UpdateBotConfig(bot, settings)
    if not IsValid(bot) then 
        AI_Utils.LogError("Data", "UpdateBotConfig: невалидный бот")
        return false 
    end
    if not IsCompanionBot(bot) then 
        AI_Utils.LogError("Data", "UpdateBotConfig: сущность не является ботом-компаньоном")
        return false 
    end
    local data = GetBotData(bot)
    if not data then 
        AI_Utils.LogError("Data", "UpdateBotConfig: данные не найдены для %s", bot:Nick())
        return false 
    end
    local cfg = data.config
    local changed = false
    local syncFields = {
        "combat_weapon", "melee_weapon", "idle_weapon",
        "model_path", "companion_nick"
    }
    local boolFields = {
        "stealth_mode", "defender_mode", "medic_mode",
        "pacifist_mode", "aggressive_mode", "show_sender_name"
    }
    for _, field in ipairs(syncFields) do
        if settings[field] and cfg[field] ~= settings[field] then
            cfg[field] = settings[field]
            changed = true
        end
    end
    for _, field in ipairs(boolFields) do
        local val = settings[field] or false
        if cfg[field] ~= val then
            cfg[field] = val
            changed = true
        end
    end
    if changed then
        data._nw_cache.stealth_mode = cfg.stealth_mode
        data._nw_cache.defender_mode = cfg.defender_mode
        data._nw_cache.medic_mode = cfg.medic_mode
        data._nw_cache.pacifist_mode = cfg.pacifist_mode
        data._nw_cache.aggressive_mode = cfg.aggressive_mode
        if IsValid(data.owner) then
            data._nw_cache.owner_name = data.owner:Nick()
        end
        data._nw_cache.is_ai_companion = true
        UpdateBotData(bot, data)
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            print("[AI Data] Обновлена конфигурация для " .. bot:Nick())
        end
        return true
    end
    return false
end
function GetBotCombatWeapon(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then 
        return "weapon_smg1" 
    end
    local data = GetBotData(bot)
    return data and data.config.combat_weapon or "weapon_smg1"
end
function GetBotMeleeWeapon(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then 
        return "weapon_crowbar" 
    end
    local data = GetBotData(bot)
    return data and data.config.melee_weapon or "weapon_crowbar"
end
function GetBotIdleWeapon(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then 
        return "weapon_physgun" 
    end
    local data = GetBotData(bot)
    return data and data.config.idle_weapon or "weapon_physgun"
end
function GetBotStealthMode(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then return false end
    local data = GetBotData(bot)
    return data and data.config.stealth_mode or false
end
function GetBotDefenderMode(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then return false end
    local data = GetBotData(bot)
    return data and data.config.defender_mode or false
end
function GetBotMedicMode(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then return false end
    local data = GetBotData(bot)
    return data and data.config.medic_mode or false
end
function GetBotPacifistMode(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then return false end
    local data = GetBotData(bot)
    return data and data.config.pacifist_mode or false
end
function GetBotAggressiveMode(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then return false end
    local data = GetBotData(bot)
    return data and data.config.aggressive_mode or false
end
function GetBotTask(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then return "" end
    local data = GetBotData(bot)
    return data and data.task or ""
end
function SetBotTask(bot, task)
    if not IsValid(bot) then 
        AI_Utils.LogError("Data", "SetBotTask: невалидный бот")
        return 
    end
    if not IsCompanionBot(bot) then 
        AI_Utils.LogError("Data", "SetBotTask: сущность не является ботом-компаньоном")
        return 
    end
    local data = GetBotData(bot)
    if not data then 
        AI_Utils.LogError("Data", "SetBotTask: данные не найдены для %s", bot:Nick())
        return 
    end
    data.task = task
    UpdateBotData(bot, data)
end
function SetBotWeapon(bot, weaponType, weaponClass, ply)
    if not IsValid(bot) or not IsValid(ply) then 
        AI_Utils.LogError("Data", "SetBotWeapon: невалидные аргументы")
        return false 
    end
    if not IsCompanionBot(bot) then 
        AI_Utils.LogError("Data", "SetBotWeapon: сущность не является ботом-компаньоном")
        return false 
    end
    local data = GetBotData(bot)
    if not data then 
        AI_Utils.LogError("Data", "SetBotWeapon: данные не найдены для %s", bot:Nick())
        return false 
    end
    if data.owner ~= ply then
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            AI_Utils.LogWarn("Data", "SetBotWeapon: игрок %s не владеет ботом", ply:Nick())
        end
        return false
    end
    if weaponType == "combat" then
        data.config.combat_weapon = weaponClass
    elseif weaponType == "melee" then
        data.config.melee_weapon = weaponClass
    elseif weaponType == "idle" then
        data.config.idle_weapon = weaponClass
    else
        return false
    end
    if SERVER then
        if not bot:HasWeapon(weaponClass) then
            bot:Give(weaponClass)
        end
    end
    UpdateBotData(bot, data)
    return true
end
function ApplyPlayerSettingsToBot(bot, settings, ply)
    if not IsValid(bot) or not IsValid(ply) then 
        AI_Utils.LogError("Data", "ApplyPlayerSettingsToBot: невалидные аргументы")
        return false 
    end
    if not IsCompanionBot(bot) then 
        AI_Utils.LogError("Data", "ApplyPlayerSettingsToBot: сущность не является ботом-компаньоном")
        return false 
    end
    if not ValidateBotOwnership(bot, ply) then
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            AI_Utils.LogWarn("Data", "ApplyPlayerSettingsToBot: игрок %s не владеет ботом", ply:Nick())
        end
        return false
    end
    UpdateBotConfig(bot, settings)
    if settings.model_path and settings.model_path ~= "" then
        if util.IsValidModel(settings.model_path) then
            bot:SetModel(settings.model_path)
        end
    end
    if settings.companion_nick and settings.companion_nick ~= "" then
        pcall(function() bot:SetName(settings.companion_nick) end)
        pcall(function() bot:SetNick(settings.companion_nick) end)
    end
    if SERVER then
        local data = GetBotData(bot)
        if data then
            local cfg = data.config
            if not bot:HasWeapon(cfg.combat_weapon) then bot:Give(cfg.combat_weapon) end
            if not bot:HasWeapon(cfg.melee_weapon)  then bot:Give(cfg.melee_weapon) end
            if not bot:HasWeapon(cfg.idle_weapon)   then bot:Give(cfg.idle_weapon) end
            if not bot:HasWeapon("weapon_medkit")   then bot:Give("weapon_medkit") end
            if not bot:HasWeapon("weapon_rpg")      then bot:Give("weapon_rpg") end
        end
    end
    return true
end
function ClearBotData(bot)
    if not IsValid(bot) then 
        AI_Utils.LogDebug("Data", "ClearBotData: невалидный бот")
        return 
    end
    if not IsCompanionBot(bot) then 
        AI_Utils.LogDebug("Data", "ClearBotData: сущность не является ботом-компаньоном")
        return 
    end
    if BotManager and BotManager.RemoveBot then
        BotManager:RemoveBot(bot, "Очистка данных", true)
    elseif AI_Companion and AI_Companion.BotData then
        AI_Companion.BotData[bot:EntIndex()] = nil
    end
end
function GetAllBotData()
    local result = {}
    if BotManager and BotManager.GetAllBots then
        local bots = BotManager:GetAllBots()
        for _, bot in ipairs(bots) do
            if IsValid(bot) then
                local data = BotManager:GetData(bot)
                if data then
                    result[bot:EntIndex()] = {
                        bot = bot,
                        name = bot:Nick(),
                        data = data,
                        uuid = bot._aiUUID
                    }
                end
            end
        end
    elseif AI_Companion and AI_Companion.BotData then
        for botID, data in pairs(AI_Companion.BotData) do
            local bot = Entity(botID)
            if IsValid(bot) then
                result[botID] = {
                    bot = bot,
                    name = bot:Nick(),
                    data = data,
                    uuid = bot._aiUUID
                }
            end
        end
    end
    return result
end
function SetCombatTarget(bot, target, targetType, triggeredBy)
    if not IsValid(bot) or not IsCompanionBot(bot) then 
        AI_Utils.LogError("Data", "SetCombatTarget: невалидный бот")
        return false 
    end
    if not IsValid(target) then 
        AI_Utils.LogError("Data", "SetCombatTarget: невалидная цель")
        return false 
    end
    local data = GetBotData(bot)
    if not data then 
        AI_Utils.LogError("Data", "SetCombatTarget: данные не найдены для %s", bot:Nick())
        return false 
    end
    data.combat.target = target
    data.combat.target_type = targetType or "npc"
    data.combat.triggered_by = triggeredBy or "unknown"
    data.combat.last_attack_time = CurTime()
    data.flags.is_in_combat = true
    local combatState = "combat"
    if AI_Companion and AI_Companion.States and AI_Companion.States.COMBAT then
        combatState = AI_Companion.States.COMBAT
    end
    SetBotState(bot, combatState)
    UpdateBotData(bot, data)
    return true
end
function ClearCombatTarget(bot)
    if not IsValid(bot) or not IsCompanionBot(bot) then 
        AI_Utils.LogDebug("Data", "ClearCombatTarget: невалидный бот")
        return 
    end
    local data = GetBotData(bot)
    if not data then 
        AI_Utils.LogDebug("Data", "ClearCombatTarget: данные не найдены для %s", bot:Nick())
        return 
    end
    data.combat.target = nil
    data.combat.target_type = nil
    data.combat.triggered_by = nil
    data.combat.last_combat_end = CurTime()
    data.flags.is_in_combat = false
    local idleState = "idle"
    if AI_Companion and AI_Companion.States and AI_Companion.States.IDLE then
        idleState = AI_Companion.States.IDLE
    end
    SetBotState(bot, idleState)
    UpdateBotData(bot, data)
end
function MigrateLegacyBotData()
    if BotManager and BotManager.MigrateFromLegacy then
        return BotManager:MigrateFromLegacy()
    end
    AI_Utils.LogWarn("Data", "BotManager:MigrateFromLegacy не найден, миграция невозможна")
    return 0
end
timer.Simple(1.0, function()
    if BotManager and BotManager.MigrateFromLegacy then
        local migrated, errors = BotManager:MigrateFromLegacy()
    end
end)
concommand.Add("ai_debug_data", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы!")
        end
        return
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI COMPANION - ДАННЫЕ БОТОВ")
    print("═══════════════════════════════════════════════════════")
    print("")
    local allData = GetAllBotData()
    if next(allData) == nil then
        print("  Нет активных ботов-компаньонов")
        print("")
        return
    end
    for botID, entry in pairs(allData) do
        local bot = entry.bot
        local data = entry.data
        local owner = data and data.owner
        print("  БОТ " .. botID .. ": " .. entry.name)
        print("    UUID: " .. (entry.uuid or "НЕТ"))
        print("    Владелец: " .. (IsValid(owner) and owner:Nick() or "НЕТ ВЛАДЕЛЬЦА!"))
        print("    Состояние: " .. (data and data.state or "idle"))
        print("    Режимы: Стелс=" .. tostring(data and data.config.stealth_mode or false) ..
              " Защитник=" .. tostring(data and data.config.defender_mode or false) ..
              " Медик=" .. tostring(data and data.config.medic_mode or false))
        if data and data.combat and data.combat.target then
            print("    Цель боя: " .. tostring(data.combat.target))
        end
        print("")
    end
    print("═══════════════════════════════════════════════════════")
    print("")
end)
_G.GetBotCombatWeapon = GetBotCombatWeapon
_G.GetBotMeleeWeapon = GetBotMeleeWeapon
_G.GetBotIdleWeapon = GetBotIdleWeapon
_G.GetBotStealthMode = GetBotStealthMode
_G.GetBotDefenderMode = GetBotDefenderMode
_G.GetBotMedicMode = GetBotMedicMode
_G.GetBotPacifistMode = GetBotPacifistMode
_G.GetBotAggressiveMode = GetBotAggressiveMode
_G.SetBotTask = SetBotTask
_G.SetBotWeapon = SetBotWeapon
_G.ApplyPlayerSettingsToBot = ApplyPlayerSettingsToBot
_G.ClearBotData = ClearBotData
_G.InitBotData = InitBotData
_G.UpdateBotConfig = UpdateBotConfig
_G.SetCombatTarget = SetCombatTarget
_G.ClearCombatTarget = ClearCombatTarget
_G.MigrateLegacyBotData = MigrateLegacyBotData
_G.ValidateBotOwnership = ValidateBotOwnership
print("[AI Data] загружен")