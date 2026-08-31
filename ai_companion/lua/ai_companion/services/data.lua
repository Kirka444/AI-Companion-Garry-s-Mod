
local Data = {}

function Data:new(state, config, utils)
    local obj = {
        state = state,
        config = config,
        utils = utils,
        botData = {},
        _initialized = false,
        _defaultData = nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Data:init()
    if self._initialized then return end
    self._defaultData = self:CreateDefaultData()
    self._initialized = true
    if self.utils then
        self.utils:LogInfo("Data", "Сервис данных инициализирован")
    end
end

function Data:CreateDefaultData()
    return {
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
            goal_pos = Vector(0, 0, 0),
            target_key = -1,
            fail_count = 0,
            disabled_until = 0,
            stuck = {
                pos = Vector(0, 0, 0),
                time = 0,
                unstuck_dir = nil,
                unstuck_until = 0,
                pos_history = {},
                no_progress_time = 0,
                wp_stuck_time = 0,
                wp_stuck_pos = Vector(0, 0, 0),
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
                pos = Vector(0, 0, 0),
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
end

function Data:IsCompanionBot(ent)
    if not ent or not ent:IsValid() or not ent:IsPlayer() then
        return false
    end
    if ent:GetNWBool("IsAICompanion", false) == true then return true end
    if ent._aiUUID then return true end
    return false
end

function Data:InitBotData(bot, owner, settings)

    if self.utils then
        self.utils:LogDebug("Data", "InitBotData: НАЧАЛО")
        self.utils:LogDebug("Data", "  bot = %s", tostring(bot))
        self.utils:LogDebug("Data", "  bot._aiUUID = %s", bot and bot._aiUUID or "nil")
    end

    if not bot or not bot:IsValid() or not bot:IsPlayer() then
        if self.utils then
            self.utils:LogError("Data", "InitBotData: невалидный бот")
        end
        return nil
    end

    local existingData = self:GetBotData(bot)
    if self.utils then
        self.utils:LogDebug("Data", "  existingData = %s", tostring(existingData))
    end

    if existingData then
        if self.utils and self.utils:IsValid(owner) then
            existingData.owner = owner
            self:SetBotData(bot, existingData)
        end
        return existingData
    end

    local uuid = bot._aiUUID
    if not uuid then
        uuid = string.format("%08x-%04x-%04x-%04x-%012x",
            bit.band(util.CRC("bot_" .. os.time() .. "_" .. math.random(1, 9999999)), 0xFFFFFFFF),
            math.random(0, 0xFFFF),
            math.random(0, 0xFFFF),
            math.random(0, 0xFFFF),
            math.random(0, 0xFFFFFFFFFFFF)
        )
        bot._aiUUID = uuid
    end

    local data = table.Copy(self._defaultData)
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
        if self.utils and self.utils:IsValid(owner) then
            data._nw_cache.owner_name = owner:Nick()
        end
        data._nw_cache.is_ai_companion = true
    end

    self:SetBotData(bot, data)
    return data
end

function Data:GetBotData(bot)
    if not bot or not bot:IsValid() or not bot:IsPlayer() then
        return nil
    end
    if not self:IsCompanionBot(bot) then return nil end

    local uuid = bot._aiUUID
    if uuid and self.botData[uuid] then
        return self.botData[uuid]
    end

    local entIndex = bot:EntIndex()
    for u, data in pairs(self.botData) do
        if data.botID == entIndex then
            bot._aiUUID = u
            return data
        end
    end

    return nil
end

function Data:SetBotData(bot, data)

    if self.utils then
        self.utils:LogDebug("Data", "SetBotData: НАЧАЛО")
        self.utils:LogDebug("Data", "  bot = %s", tostring(bot))
        self.utils:LogDebug("Data", "  bot:IsValid() = %s", bot and bot:IsValid() or false)
        self.utils:LogDebug("Data", "  bot:IsPlayer() = %s", bot and bot:IsPlayer() or false)
        self.utils:LogDebug("Data", "  bot:IsBot() = %s", bot and bot:IsBot() or false)
        self.utils:LogDebug("Data", "  bot._aiUUID = %s", bot and bot._aiUUID or "nil")
    end

    if not self.utils or not self.utils:IsValid(bot) then
        if self.utils then
            self.utils:LogWarn("Data", "  ❌ bot невалиден (по utils)")
        end
        return false
    end
    if not self:IsCompanionBot(bot) then
        if self.utils then
            self.utils:LogWarn("Data", "  ❌ не является компаньоном")
        end
        return false
    end

    local uuid = bot._aiUUID
    if not uuid then
        uuid = self:GenerateUUID()
        bot._aiUUID = uuid
    end

    data.botID = bot:EntIndex()
    self.botData[uuid] = data
    if self.utils then
        self.utils:LogDebug("Data", "  ✅ Данные сохранены, UUID: %s", uuid)
    end
    return true
end

function Data:UpdateBotData(bot, newData)
    if not self.utils or not self.utils:IsValid(bot) then return false end

    local data = self:GetBotData(bot)
    if not data then return false end

    for k, v in pairs(newData) do
        if type(v) == "table" and type(data[k]) == "table" then
            for subK, subV in pairs(v) do
                data[k][subK] = subV
            end
        else
            data[k] = v
        end
    end

    self:SetBotData(bot, data)
    return true
end

function Data:RemoveBotData(bot)
    if not self.utils or not self.utils:IsValid(bot) then return false end

    local uuid = bot._aiUUID
    if uuid then
        self.botData[uuid] = nil
        return true
    end

    local entIndex = bot:EntIndex()
    for u, data in pairs(self.botData) do
        if data.botID == entIndex then
            self.botData[u] = nil
            return true
        end
    end

    return false
end

function Data:GenerateUUID()
    return string.format("%08x-%04x-%04x-%04x-%012x",
        math.random(0, 0xFFFFFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFFFFFFFFFF)
    )
end

function Data:GetAllBotData()
    local result = {}
    for uuid, data in pairs(self.botData) do
        local bot = Entity(data.botID)
        if self.utils and self.utils:IsValid(bot) then
            result[uuid] = {
                bot = bot,
                data = data,
                uuid = uuid,
            }
        end
    end
    return result
end

function Data:GetBotCount()
    local count = 0
    for uuid, data in pairs(self.botData) do
        local bot = Entity(data.botID)
        if self.utils and self.utils:IsValid(bot) then
            count = count + 1
        end
    end
    return count
end

function Data:GetBotConfig(bot)
    local data = self:GetBotData(bot)
    return data and data.config or nil
end

function Data:GetBotCombatWeapon(bot)
    local data = self:GetBotData(bot)
    return data and data.config.combat_weapon or "weapon_smg1"
end

function Data:GetBotMeleeWeapon(bot)
    local data = self:GetBotData(bot)
    return data and data.config.melee_weapon or "weapon_crowbar"
end

function Data:GetBotIdleWeapon(bot)
    local data = self:GetBotData(bot)
    return data and data.config.idle_weapon or "weapon_physgun"
end

function Data:GetBotStealthMode(bot)
    local data = self:GetBotData(bot)
    return data and data.config.stealth_mode or false
end

function Data:GetBotDefenderMode(bot)
    local data = self:GetBotData(bot)
    return data and data.config.defender_mode or false
end

function Data:GetBotMedicMode(bot)
    local data = self:GetBotData(bot)
    return data and data.config.medic_mode or false
end

function Data:GetBotPacifistMode(bot)
    local data = self:GetBotData(bot)
    return data and data.config.pacifist_mode or false
end

function Data:GetBotAggressiveMode(bot)
    local data = self:GetBotData(bot)
    return data and data.config.aggressive_mode or false
end

function Data:GetBotState(bot)
    local data = self:GetBotData(bot)
    return data and data.state or "idle"
end

function Data:SetBotState(bot, state)
    local data = self:GetBotData(bot)
    if not data then return false end
    data.state = state
    data.task = state
    self:SetBotData(bot, data)
    return true
end

function Data:DebugPrint()

    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI COMPANION - ДАННЫЕ БОТОВ")
    print("═══════════════════════════════════════════════════════")
    print("")

    local allData = self:GetAllBotData()
    if next(allData) == nil then
        print("  Нет активных ботов-компаньонов")
        print("")
        return
    end

    for uuid, entry in pairs(allData) do
        local bot = entry.bot
        local data = entry.data
        local owner = data and data.owner
        print("  БОТ " .. data.botID .. ": " .. (self.utils and self.utils:IsValid(bot) and bot:Nick() or "НЕАКТИВЕН"))
        print("    UUID: " .. uuid)
        print("    Владелец: " .. (self.utils and self.utils:IsValid(owner) and owner:Nick() or "НЕТ ВЛАДЕЛЬЦА!"))
        print("    Состояние: " .. (data and data.state or "idle"))
        print("    Режимы: Стелс=" .. tostring(data and data.config.stealth_mode or false) ..
              " Защитник=" .. tostring(data and data.config.defender_mode or false) ..
              " Медик=" .. tostring(data and data.config.medic_mode or false))
        if data and data.combat and self.utils and self.utils:IsValid(data.combat.target) then
            print("    Цель боя: " .. tostring(data.combat.target:Nick() or data.combat.target:GetClass()))
        end
        print("")
    end

    print("  Всего ботов: " .. self:GetBotCount())
    print("═══════════════════════════════════════════════════════")
    print("")
end

if SERVER then
    concommand.Add("ai_data_debug", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы!")
            return
        end

        local locator = _G.AI_GetLocator()
        if locator and locator:has("data") then
            local data = locator:get("data")
            data:DebugPrint()
        else
            print("[AI] Data не найден!")
        end

        if IsValid(ply) then
            ply:ChatPrint("[AI] Данные ботов выведены в консоль")
        end
    end)
end

return Data
