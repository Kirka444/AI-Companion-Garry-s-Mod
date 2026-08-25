if AI_COMPANION_SPAWN_LOADED then return end
AI_COMPANION_SPAWN_LOADED = true
local AC = _G.AI_COMPANION
_G.AI_Companion = _G.AI_Companion or {}
if not AI_Utils then
    local ok, err = pcall(include, "ai_companion/ai_companion_utils.lua")
    if not ok then
        ErrorNoHalt("[AI Spawn] ai_companion_utils.lua: " .. tostring(err) .. "\n")
        return
    end
end
if not AI_Companion then
    local ok, err = pcall(include, "ai_companion/ai_companion_core.lua")
    if not ok then
        ErrorNoHalt("[AI Spawn] ai_companion_core.lua: " .. tostring(err) .. "\n")
        return
    end
end
if not AI_CONFIG then
    local ok, err = pcall(include, "ai_companion/ai_config.lua")
    if not ok then
        ErrorNoHalt("[AI Spawn] ai_config.lua: " .. tostring(err) .. "\n")
        return
    end
end
if not GetPlayerSettings then
    local ok, err = pcall(include, "ai_companion/ai_companion_settings.lua")
    if not ok then
        ErrorNoHalt("[AI Spawn] ai_companion_settings.lua: " .. tostring(err) .. "\n")
        return
    end
end
if not BotManager then
    ErrorNoHalt("[AI Spawn] BotManager не загружен! Убедитесь, что ai_companion_botmanager.lua загружен до spawn.lua\n")
    return
end
local FALLBACK_WEAPONS = AI_CONFIG and AI_CONFIG.Weapons or {
    idle = "weapon_physgun",
    combat = "weapon_smg1",
    melee = "weapon_crowbar",
    medkit = "weapon_medkit",
    rpg = "weapon_rpg",
    frag = "weapon_frag"
}
local COMPANION_NAME = AI_CONFIG.COMPANION_NAME or "AI_Companion"
local DEFAULT_MODEL = AI_CONFIG.DEFAULT_MODEL or "models/player/urban.mdl"
local AVAILABLE_MODELS = {
    "models/player/combine_soldier.mdl",
    "models/player/alyx.mdl",
    "models/player/barney.mdl",
    "models/player/kleiner.mdl",
    "models/player/mossman.mdl",
    "models/player/p2_chell.mdl",
    "models/player/urban.mdl"
}
local function IsValidModelPath(path)
    if not path or path == "" then return false end
    if string.find(path, "%.%.") then return false end
    if string.find(path, "\\") then return false end
    if not string.match(path, "%.mdl$") then return false end
    local ok, exists = pcall(util.IsValidModel, path)
    return ok and exists
end
local function SafeGiveWeapon(bot, wepName, fallback)
    if not IsValid(bot) then return false, nil end
    if not wepName or wepName == "" then
        wepName = fallback
        if not wepName or wepName == "" then
            return false, nil
        end
    end
    if not bot:HasWeapon(wepName) then
        bot:Give(wepName)
    end
    return true, wepName
end
local function GetWeaponWithFallback(settings, settingKey, fallback)
    local wep = settings and settings[settingKey]
    if wep and weapons.Get(wep) then
        return wep
    end
    return fallback
end
function FindSafeSpawnPos(ply)
    if not AI_Utils.IsValid(ply) then return Vector(0, 0, 100) end
    local start = ply:GetPos() + ply:GetForward() * 80
    local tr = util.TraceLine({
        start = start + Vector(0, 0, 100),
        endpos = start - Vector(0, 0, 200),
        filter = ply
    })
    if tr.Hit then
        local ground = tr.HitPos + Vector(0, 0, 5)
        local hull = util.TraceHull({
            start = ground + Vector(0, 0, 36),
            endpos = ground + Vector(0, 0, 36),
            mins = Vector(-16, -16, 0),
            maxs = Vector(16, 16, 72),
            filter = ply
        })
        if not hull.Hit then return ground end
    end
    return start + Vector(0, 0, 5)
end
function ForceStandUp(bot)
    if not IsValid(bot) then return end
    bot:RemoveFlags(FL_DUCKING)
    bot:RemoveFlags(FL_ANIMDUCKING)
    pcall(function() bot:ConCommand("-duck") end)
end
function SpawnNewBot(model, spawnPos, owner, uuid)
    if game.SinglePlayer() then return nil end
    if not AI_Utils.IsValid(owner) then return nil end
    local settings = GetPlayerSettings(owner) or {}
    local botNick = settings.companion_nick or _G.AI_COMPANION_NICK or AI_CONFIG.COMPANION_NAME or "AI_Companion"
    local originalNick = botNick
    local suffix = 1
    local function IsNameTaken(name)
        for _, p in ipairs(player.GetAll()) do
            if AI_Utils.IsValid(p) and not p:IsBot() and p:Nick() == name then
                return true
            end
        end
        return false
    end
    while IsNameTaken(botNick) do
        botNick = originalNick .. "_" .. suffix
        suffix = suffix + 1
    end
    local bot = player.CreateNextBot(botNick)
    if not AI_Utils.IsValid(bot) then
        if AI_Utils.IsValid(owner) then
            owner:ChatPrint("[AI] Ошибка: не удалось создать бота")
        end
        return nil
    end
    if model and model ~= "" then
        if util.IsValidModel(model) then
            bot:SetModel(model)
        else
            bot:SetModel(settings.model_path or "models/player/urban.mdl")
        end
    else
        if settings.model_path and settings.model_path ~= "" and util.IsValidModel(settings.model_path) then
            bot:SetModel(settings.model_path)
        else
            bot:SetModel("models/player/urban.mdl")
        end
    end
    if uuid and uuid ~= "" then
        bot._aiUUID = uuid
    end
    bot._aiUnregisterDone = false
    bot._aiCleanupDone = false
    bot._aiBeingRemoved = false
    pcall(function() bot:SetName(botNick) end)
    if spawnPos then
        bot:SetPos(spawnPos)
    else
        local safePos = FindSafeSpawnPos(owner or bot)
        bot:SetPos(safePos)
    end
    bot:RemoveFlags(FL_DUCKING)
    bot:RemoveFlags(FL_ANIMDUCKING)
    pcall(function() bot:ConCommand("-duck") end)
    bot._aiSpawnTime = CurTime()
    bot._aiSpawnNoCrouchUntil = CurTime() + AI.Config.Spawn.SpawnGraceDuration
    return bot
end
local SPAWN_STAGES = {
    {
        delay = 0.00,
        fn = function(bot)
            pcall(function() bot:StripWeapons() end)
        end
    },
    {
        delay = 0.05,
        fn = function(bot, ctx)
            local settings = ctx.settings or {}
            pcall(function()
                local combatWep = GetWeaponWithFallback(settings, "combat_weapon", FALLBACK_WEAPONS.combat)
                local meleeWep = GetWeaponWithFallback(settings, "melee_weapon", FALLBACK_WEAPONS.melee)
                local idleWep = GetWeaponWithFallback(settings, "idle_weapon", FALLBACK_WEAPONS.idle)
                local success, actualWep = SafeGiveWeapon(bot, combatWep, FALLBACK_WEAPONS.combat)
                if success and actualWep then
                    local wep = bot:GetWeapon(actualWep)
                    if AI_Utils.IsValid(wep) then
                        local ammoType = wep:GetPrimaryAmmoType()
                        if ammoType and ammoType ~= -1 then bot:GiveAmmo(120, ammoType, true) end
                        if AI_CONFIG.INFINITE_AMMO then
                            wep:SetClip1(wep:GetMaxClip1() or 30)
                        end
                    end
                end
                SafeGiveWeapon(bot, meleeWep, FALLBACK_WEAPONS.melee)
                SafeGiveWeapon(bot, "weapon_frag", FALLBACK_WEAPONS.frag)
                SafeGiveWeapon(bot, "weapon_rpg", FALLBACK_WEAPONS.rpg)
                SafeGiveWeapon(bot, "weapon_medkit", FALLBACK_WEAPONS.medkit)
                if bot:HasWeapon(idleWep) then
                    bot:SelectWeapon(idleWep)
                else
                    local fallbackIdle = FALLBACK_WEAPONS.idle
                    if bot:HasWeapon(fallbackIdle) then
                        bot:SelectWeapon(fallbackIdle)
                    else
                        local weapons = bot:GetWeapons()
                        if #weapons > 0 then
                            bot:SelectWeapon(weapons[1]:GetClass())
                        end
                    end
                end
            end)
        end
    },
}
function CreateAICompanion(modelName, spawnPos, owner)
    if game.SinglePlayer() then
        if AI_Utils.IsValid(owner) then 
            owner:ChatPrint("[AI] Включен соло-режим, бот недоступен.")
        end
        return nil
    end
    if not AI_Utils.IsValid(owner) then
        if AI_Utils and AI_Utils.LogWarn then
            AI_Utils.LogWarn("Spawn", "Попытка создать бота без владельца")
        end
        return nil
    end
    if not BotManager then
        if AI_Utils and AI_Utils.LogError then
            AI_Utils.LogError("Spawn", "BotManager не загружен!")
        end
        return nil
    end
    local settings = GetPlayerSettings(owner) or {}
    local bot, err = BotManager:CreateBot(owner, modelName, spawnPos, settings)
    if not IsValid(bot) then
        if IsValid(owner) then
            owner:ChatPrint("[AI]  Не удалось создать бота" .. (err and ": " .. err or ""))
        end
        if AI_Utils and AI_Utils.LogError then
            AI_Utils.LogError("Spawn", "BotManager:CreateBot вернул ошибку: %s", tostring(err))
        end
        return nil
    end
    local ctx = { modelName = modelName, owner = owner, settings = settings }
    for _, stage in ipairs(SPAWN_STAGES) do
        timer.Simple(stage.delay, function()
            if not AI_Utils.IsValid(bot) then return end
            AI_Utils.SafeExecute("SpawnStage", function() stage.fn(bot, ctx) end)
        end)
    end
    bot._aiForceStandUntil = CurTime() + (AI.Config.Spawn.ForceStandIterations or 200) * 0.05
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Spawn", "Бот %s создан через BotManager:CreateBot", bot:Nick())
    end
    return bot
end
function RemoveAICompanion(bot, reason, skipMessage)
    if not IsValid(bot) then return false end
    if BotManager then
        return BotManager:RemoveBot(bot, reason or "Удалён", skipMessage)
    end
    return false
end
hook.Add("CalcMainActivity", "AICompanionAnimFix", function(ply, velocity)
    if not AI_Utils.IsValid(ply) then return end
    if not ply:IsBot() or ply:Nick() ~= AI_CONFIG.COMPANION_NAME then return end
    local cmd = ply:GetCurrentCommand()
    if cmd and (cmd:GetForwardMove() ~= 0 or cmd:GetSideMove() ~= 0) then
        return
    end
    local speed = velocity:Length2D()
    if speed > 200 then
        return ACT_MP_RUN, -1
    elseif speed > 10 then
        return ACT_MP_WALK, -1
    else
        return ACT_MP_STAND_IDLE, -1
    end
end)
hook.Add("PlayerInitialSpawn", "AICompanion_RegisterBot", function(ply)
    if IsBotSafe(ply) and ply:GetNWBool("IsAICompanion", false) then
        if BotManager and not BotManager:GetData(ply) then
            local owner = ply:GetNWEntity("AICompanionOwnerEnt")
            local settings = IsValid(owner) and GetPlayerSettings(owner) or {}
            local data = InitBotData(ply, owner, settings)
            if data then
                BotManager:UpdateData(ply, data)
            end
        end
        ply._aiSpawnNoCrouchUntil = CurTime() + AI.Config.Spawn.SpawnGraceDuration
        ply:RemoveFlags(FL_DUCKING)
        ply:RemoveFlags(FL_ANIMDUCKING)
        pcall(function() ply:ConCommand("-duck") end)
    end
end)
hook.Add("PlayerInitialSpawn", "AICompanion_ArmorFix", function(ply)
    if not ply:IsBot() then return end
    local botID = ply:EntIndex()
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        local isCompanion = ply:GetNWBool("IsAICompanion", false)
        local hasOwner = false
        if BotManager then
            local data = BotManager:GetData(ply)
            if data and IsValid(data.owner) then
                hasOwner = true
            end
        end
        if not isCompanion and not hasOwner then return end
        ply:SetMaxArmor(100)
        ply:SetArmor(100)
        local tname = "AIArmor_" .. botID
        timer.Create(tname, 0.1, 30, function()
            if not IsValid(ply) then
                timer.Remove(tname)
                return
            end
            if ply:Armor() < 100 then
                ply:SetArmor(100)
            else
                timer.Remove(tname)
            end
        end)
    end)
end)
concommand.Add("ai_companion_create", function(ply, cmd, args)
    if game.SinglePlayer() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Включен соло-режим, бот недоступен.")
        end
        return
    end
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
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
    if BotManager then
        local bot = BotManager:GetBotByOwner(ply)
        if not IsValid(bot) then
            if IsValid(ply) then
                ply:ChatPrint("[AI]  У вас нет компаньона")
            end
            return
        end
        local botNick = bot:Nick() or "компаньон"
        if BotManager:RemoveBot(bot, "Удалён игроком", true) then
            if IsValid(ply) then
                ply:ChatPrint("[AI]  Компаньон " .. botNick .. " удалён")
            end
            if AI_Utils and AI_Utils.LogInfo then
                AI_Utils.LogInfo("Spawn", "Бот %s удалён игроком %s", botNick, ply:Nick())
            end
        else
            if IsValid(ply) then
                ply:ChatPrint("[AI]  Не удалось удалить компаньона")
            end
            if AI_Utils and AI_Utils.LogWarn then
                AI_Utils.LogWarn("Spawn", "Не удалось удалить бота для игрока %s", ply:Nick())
            end
        end
    end
end)
concommand.Add("ai_companion_replace", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    if BotManager then
        local bot = BotManager:GetBotByOwner(ply)
        if not IsValid(bot) then
            if IsValid(ply) then
                ply:ChatPrint("[AI]  У вас нет компаньона")
            end
            return
        end
        local model = args[1] or _G.CurrentCompanionModel or AI_CONFIG.DEFAULT_MODEL
        BotManager:RemoveBot(bot, "Замена компаньона", true)
        timer.Simple(0.5, function()
            if IsValid(ply) then
                local newBot = CreateAICompanion(model, nil, ply)
                if IsValid(newBot) then
                    ply:ChatPrint("[AI]  Новый компаньон создан!")
                    if AI_Utils and AI_Utils.LogInfo then
                        AI_Utils.LogInfo("Spawn", "Бот заменён для игрока %s", ply:Nick())
                    end
                else
                    ply:ChatPrint("[AI]  Не удалось создать нового компаньона")
                    if AI_Utils and AI_Utils.LogWarn then
                        AI_Utils.LogWarn("Spawn", "Не удалось заменить бота для игрока %s", ply:Nick())
                    end
                end
            end
        end)
    end
end)
concommand.Add("ai_companion_teleport", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:IsBot() then return end
    if BotManager then
        local bot = BotManager:GetBotByOwner(ply)
        if not IsValid(bot) then
            if IsValid(ply) then
                ply:ChatPrint("[AI]  У вас нет компаньона")
            end
            return
        end
        local data = BotManager:GetData(bot)
        if not data or data.owner ~= ply then
            if IsValid(ply) then
                ply:ChatPrint("[AI]  Это не ваш компаньон!")
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
        local data2 = BotManager:GetData(bot)
        if data2 then
            data2.navigation.path = nil
            data2.navigation.path_index = 1
            BotManager:UpdateData(bot, data2)
        end
        if IsValid(ply) then
            ply:ChatPrint("[AI]  Компаньон телепортирован.")
        end
    end
end)
concommand.Add("ai_spawn_debug", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы!")
        end
        return
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AI SPAWN - ОТЛАДОЧНАЯ ИНФОРМАЦИЯ")
    print("═══════════════════════════════════════════════════════")
    print("")
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("Spawn", "BotManager загружен: %s", tostring(BotManager ~= nil))
        AI_Utils.LogInfo("Spawn", "Solo режим: %s", tostring(game.SinglePlayer()))
        AI_Utils.LogInfo("Spawn", "Ботов в BotManager: %d", BotManager and BotManager:GetBotCount() or 0)
    else
        print("  BotManager загружен: " .. tostring(BotManager ~= nil))
        print("  Solo режим: " .. tostring(game.SinglePlayer()))
        print("  Ботов в BotManager: " .. (BotManager and BotManager:GetBotCount() or 0))
    end
    print("")
    if BotManager then
        local bots = BotManager:GetAllBots()
        if #bots > 0 then
            print("  Список ботов:")
            for i, bot in ipairs(bots) do
                if IsValid(bot) then
                    local data = BotManager:GetData(bot)
                    local owner = data and data.owner
                    print("    " .. i .. ". " .. bot:Nick() ..
                          " (UUID: " .. (bot._aiUUID or "НЕТ") .. ")" ..
                          " Владелец: " .. (IsValid(owner) and owner:Nick() or "НЕТ"))
                end
            end
        else
            print("  Нет зарегистрированных ботов")
        end
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("")
end)
print("[AI Spawn] Экспортирую глобальные функции...")
_G.FindSafeSpawnPos = FindSafeSpawnPos
_G.SpawnNewBot = SpawnNewBot
_G.ForceStandUp = ForceStandUp
_G.RemoveAICompanion = RemoveAICompanion
_G.CreateAICompanion = CreateAICompanion
print("[AI Spawn] CreateAICompanion экспортирована:", _G.CreateAICompanion ~= nil)
print("[AI Spawn] Тип CreateAICompanion:", type(_G.CreateAICompanion))
if AI_Utils and AI_Utils.LogInfo then
    AI_Utils.LogInfo("Spawn", "v5.6 загружен (единый путь через BotManager:CreateBot, SpawnNewBot только спавн сущности)")
else
    print("[AI Spawn] v5.6 загружен (единый путь через BotManager:CreateBot, SpawnNewBot только спавн сущности)")
end
