if AI_COMPANION_BOTMANAGER_LOADED then return end
AI_COMPANION_BOTMANAGER_LOADED = true
local AC = _G.AI_COMPANION
_G.AI_Companion = _G.AI_Companion or {}
BotManager = BotManager or {}
local BOTS = {}          
local OWNER_INDEX = {}   
local BOT_INDEX = {}     
local function IsCompanionBot(ent)
    if not IsValid(ent) then return false end
    if not ent:IsPlayer() then return false end
    if not ent:IsBot() then return false end
    if ent:GetNWBool("IsAICompanion", false) == true then return true end
    if ent._aiUUID then return true end
    if BOT_INDEX[ent:EntIndex()] then return true end
    return false
end
function BotManager:GenerateUUID()
    local timePart = string.format("%x", math.floor(SysTime() * 1000000))
    local rand1 = math.random(0, 0xFFFFFFFF)
    local rand2 = math.random(0, 0xFFFFFFFF)
    local rand3 = math.random(0, 0xFFFF)
    local sessionSalt = os.time() .. "_" .. tostring({})
    local uniqueStr = string.format("%s_%x_%x_%x_%s", 
        timePart, rand1, rand2, rand3, sessionSalt)
    local crc = util.CRC(uniqueStr)
    return string.format("%08x-%04x-%04x-%04x-%012x",
        bit.band(crc, 0xFFFFFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFF),
        math.random(0, 0xFFFFFFFFFFFF)
    )
end
local function GetSteamID64(ply)
    if not IsValid(ply) then return nil end
    return ply:SteamID64()
end
local function Internal_AddBot(uuid, bot, data)
    if not uuid then
        return
    end
    if not IsValid(bot) then
        return
    end
    BOTS[uuid] = { bot = bot, data = data }
    BOT_INDEX[bot:EntIndex()] = uuid
    if data and data.owner and IsValid(data.owner) then
        local sid = GetSteamID64(data.owner)
        if sid then
            if not OWNER_INDEX[sid] then
                OWNER_INDEX[sid] = {}
            end
            local found = false
            for _, storedUuid in ipairs(OWNER_INDEX[sid]) do
                if storedUuid == uuid then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(OWNER_INDEX[sid], uuid)
            else
            end
        else
        end
    else
    end
end
local function Internal_RemoveBot(uuid)
    local entry = BOTS[uuid]
    if not entry then return end
    if IsValid(entry.bot) then
        BOT_INDEX[entry.bot:EntIndex()] = nil
    end
    if entry.data and entry.data.owner and IsValid(entry.data.owner) then
        local sid = GetSteamID64(entry.data.owner)
        if sid and OWNER_INDEX[sid] then
            for i, storedUuid in ipairs(OWNER_INDEX[sid]) do
                if storedUuid == uuid then
                    table.remove(OWNER_INDEX[sid], i)
                    break
                end
            end
            if #OWNER_INDEX[sid] == 0 then
                OWNER_INDEX[sid] = nil
            end
        end
    end
    BOTS[uuid] = nil
end
function BotManager:GetData(bot)
    if not IsValid(bot) then return nil end
    if not IsCompanionBot(bot) then return nil end
    local uuid = bot._aiUUID
    if uuid and BOTS[uuid] then
        return BOTS[uuid].data
    end
    local entIndex = bot:EntIndex()
    uuid = BOT_INDEX[entIndex]
    if uuid and BOTS[uuid] then
        bot._aiUUID = uuid
        return BOTS[uuid].data
    end
    for u, entry in pairs(BOTS) do
        if entry.bot == bot then
            bot._aiUUID = u
            BOT_INDEX[bot:EntIndex()] = u
            return entry.data
        end
    end
    return nil
end
function BotManager:GetBotByOwner(owner)
    if not IsValid(owner) then return nil end
    local sid = GetSteamID64(owner)
    if not sid then return nil end
    local uuids = OWNER_INDEX[sid]
    if uuids and #uuids > 0 then
        for _, uuid in ipairs(uuids) do
            if BOTS[uuid] and IsValid(BOTS[uuid].bot) then
                return BOTS[uuid].bot
            end
        end
    end
    for u, entry in pairs(BOTS) do
        if entry.data and entry.data.owner == owner then
            if not OWNER_INDEX[sid] then
                OWNER_INDEX[sid] = {}
            end
            table.insert(OWNER_INDEX[sid], u)
            return entry.bot
        end
    end
    return nil
end
function BotManager:GetBotsByOwner(owner)
    if not IsValid(owner) then return {} end
    local result = {}
    local sid = GetSteamID64(owner)
    if sid and OWNER_INDEX[sid] then
        for _, uuid in ipairs(OWNER_INDEX[sid]) do
            if BOTS[uuid] and IsValid(BOTS[uuid].bot) then
                table.insert(result, BOTS[uuid].bot)
            end
        end
        return result
    end
    for u, entry in pairs(BOTS) do
        if entry.data and entry.data.owner == owner then
            table.insert(result, entry.bot)
        end
    end
    return result
end
function BotManager:HasBot(owner)
    if not IsValid(owner) then return false end
    local sid = GetSteamID64(owner)
    if not sid then return false end
    local uuids = OWNER_INDEX[sid]
    if uuids and #uuids > 0 then
        for _, uuid in ipairs(uuids) do
            if BOTS[uuid] and IsValid(BOTS[uuid].bot) then
                return true
            end
        end
    end
    return false
end
function BotManager:GetBotCountByOwner(owner)
    if not IsValid(owner) then return 0 end
    local sid = GetSteamID64(owner)
    if not sid then return 0 end
    local uuids = OWNER_INDEX[sid]
    if not uuids then return 0 end
    local count = 0
    for _, uuid in ipairs(uuids) do
        if BOTS[uuid] and IsValid(BOTS[uuid].bot) then
            count = count + 1
        end
    end
    return count
end
function BotManager:GetAllBots()
    local result = {}
    for u, entry in pairs(BOTS) do
        if IsValid(entry.bot) then
            table.insert(result, entry.bot)
        end
    end
    return result
end
function BotManager:GetBotCount()
    local count = 0
    for u, entry in pairs(BOTS) do
        if IsValid(entry.bot) then
            count = count + 1
        end
    end
    return count
end
function BotManager:GetUUID(bot)
    if not IsValid(bot) then return nil end
    if bot._aiUUID then return bot._aiUUID end
    local uuid = BOT_INDEX[bot:EntIndex()]
    if uuid and BOTS[uuid] then
        bot._aiUUID = uuid
        return uuid
    end
    for u, entry in pairs(BOTS) do
        if entry.bot == bot then
            bot._aiUUID = u
            BOT_INDEX[bot:EntIndex()] = u
            return u
        end
    end
    return nil
end
function BotManager:GetBotByUUID(uuid)
    if not uuid then return nil end
    local entry = BOTS[uuid]
    if entry and IsValid(entry.bot) then
        return entry.bot
    end
    return nil
end
function BotManager:SyncToNWVars(bot)
    if not IsValid(bot) then 
        return 
    end
    if not bot:IsBot() then 
        return 
    end
    local data = self:GetData(bot)
    if not data then 
        return 
    end
    local cache = data._nw_cache or {}
    local cfg = data.config or {}
    local modeKeys = {
        stealth_mode = "AI_StealthMode",
        defender_mode = "AI_DefenderMode",
        medic_mode = "AI_MedicMode",
        pacifist_mode = "AI_PacifistMode",
        aggressive_mode = "AI_AggressiveMode",
    }
    for key, nwKey in pairs(modeKeys) do
        local value = cfg[key] or false
        if cache[key] ~= value then
            bot:SetNWBool(nwKey, value)
            cache[key] = value
        end
    end
    if cache.state ~= data.state then
        bot:SetNWString("BotState", data.state or "idle")
        cache.state = data.state
    end
    if cache.task ~= data.task then
        bot:SetNWString("CurrentTask", data.task or "")
        cache.task = data.task
    end
    if IsValid(data.owner) then
        local ownerName = data.owner:Nick()
        bot:SetNWEntity("AICompanionOwnerEnt", data.owner)
        bot:SetNWString("AICompanionOwner", ownerName)
        cache.owner_name = ownerName
        if not cache.is_ai_companion then
            bot:SetNWBool("IsAICompanion", true)
            cache.is_ai_companion = true
        else
            local current = bot:GetNWBool("IsAICompanion", false)
            if not current then
                bot:SetNWBool("IsAICompanion", true)
            end
        end
    else
        if cache.is_ai_companion then
            bot:SetNWBool("IsAICompanion", false)
            cache.is_ai_companion = false
        end
    end
    data._nw_cache = cache
end
function BotManager:SyncAllBots()
    local bots = self:GetAllBots()
    for _, bot in ipairs(bots) do
        if IsValid(bot) then
            self:SyncToNWVars(bot)
        end
    end
end
function BotManager:CleanupBotTimers(bot)
    if not IsValid(bot) then return end
    local botID = bot:EntIndex()
    local steamID = bot:SteamID64()
    timer.Remove("AIArmor_" .. botID)
    timer.Remove("AI_TankFire_" .. botID)
    timer.Remove("AI_MedkitSpawn_" .. botID)
    timer.Remove("AI_HeliWeapon_" .. botID)
    timer.Remove("AI_SpawnCleanup_" .. botID)
    timer.Remove("AI_Core_Cleanup_" .. botID)
    timer.Remove("AI_Combat_State_" .. botID)
    timer.Remove("AI_ExitVehicle_" .. botID)
    timer.Remove("AI_Tank_Attack_" .. botID)
    timer.Remove("AI_Heli_Attack_" .. botID)
    timer.Remove("AI_Strafe_Change_" .. botID)
    timer.Remove("AI_Medkit_Check_" .. botID)
    if steamID then
        timer.Remove("tts_timeout_" .. steamID)
        timer.Remove("LLM_timeout_" .. steamID)
        timer.Remove("AI_LLM_Timeout_" .. steamID)
        timer.Remove("AI_TTS_Timeout_" .. steamID)
        timer.Remove("AI_HTTP_Timeout_" .. steamID)
        timer.Remove("AI_Request_Timeout_" .. steamID)
    end
    timer.Remove("AI_CacheCleanup")
    timer.Remove("AI_GlobalSync_Delay")
    timer.Remove("BotManager_Cleanup")
    timer.Remove("BotManager_Sync")
    if bot._aiPendingRequests then
        for _, requestID in ipairs(bot._aiPendingRequests) do
            timer.Remove("LLM_timeout_" .. tostring(requestID))
        end
        bot._aiPendingRequests = nil
    end
    if bot._aiPendingTTS then
        for _, ttsID in ipairs(bot._aiPendingTTS) do
            timer.Remove("TTS_timeout_" .. tostring(ttsID))
        end
        bot._aiPendingTTS = nil
    end
    if AI_Utils and AI_Utils.LogDebug then
        AI_Utils.LogDebug("BotManager", "Таймеры очищены для бота %s (ID: %d)", bot:Nick(), botID)
    end
end
function BotManager:GetBotState(bot)
    if not IsValid(bot) then return "idle" end
    if not bot:IsBot() then return "idle" end
    local data = self:GetData(bot)
    if data and data.state then
        return data.state
    end
    return bot:GetNWString("BotState", "idle")
end
function BotManager:SetBotState(bot, newState)
    if not IsValid(bot) then return false end
    if not bot:IsBot() then return false end
    local data = self:GetData(bot)
    if not data then return false end
    data.state = newState
    data.task = newState
    self:UpdateData(bot, data)
    self:SyncToNWVars(bot)
    return true
end
function BotManager:GetCompanion(ply)
    if not IsValid(ply) then return nil end
    return self:GetBotByOwner(ply)
end
function BotManager:HasCompanion(ply)
    if not IsValid(ply) then return false end
    return self:HasBot(ply)
end
function BotManager:GetAllCompanions()
    return self:GetAllBots()
end
function BotManager:CreateBot(owner, model, spawnPos, settings)
    if not IsValid(owner) then return nil, "Невалидный владелец" end
    if self:HasBot(owner) then return nil, "У владельца уже есть бот" end
    local maxBots = AI_CONFIG and AI_CONFIG.Spawn and AI_CONFIG.Spawn.MaxBotsTotal or 10
    if self:GetBotCount() >= maxBots then
        if IsValid(owner) then
            owner:ChatPrint("[AI] Достигнут лимит ботов на сервере (" .. maxBots .. ")")
        end
        return nil, "Достигнут лимит ботов"
    end
    local uuid = self:GenerateUUID()
    if not uuid then
        if AI_Utils and AI_Utils.LogError then
            AI_Utils.LogError("BotManager", "CreateBot: не удалось сгенерировать UUID")
        else
            print("[AI BotManager] CreateBot: не удалось сгенерировать UUID")
        end
        return nil, "Ошибка генерации UUID"
    end
    if not model and settings and settings.model_path then
        model = settings.model_path
    end
    local bot = SpawnNewBot(model, spawnPos, owner, uuid)
    if not IsValid(bot) then
        return nil, "Ошибка создания бота"
    end
    if not bot._aiUUID then
        bot._aiUUID = uuid
    end
    bot._aiPendingRequests = {}
    bot._aiPendingTTS = {}
    local existingData = self:GetData(bot)
    if existingData then
        if AI_Utils and AI_Utils.LogWarn then
            AI_Utils.LogWarn("BotManager", "CreateBot: бот %s уже имеет данные, используем существующие", bot:Nick())
        end
        existingData.owner = owner
        existingData.uuid = uuid
        existingData.botID = bot:EntIndex()
        Internal_AddBot(uuid, bot, existingData)
        self:SyncToNWVars(bot)
    else
        local data = GetBotData(bot)
        if not data then
            data = InitBotData(bot, owner, settings or {})
            if not data then
                pcall(function() bot:Kick("Ошибка инициализации данных") end)
                return nil, "Ошибка инициализации данных"
            end
        end
        data.owner = owner
        data.uuid = uuid
        data.botID = bot:EntIndex()
        Internal_AddBot(uuid, bot, data)
        self:SyncToNWVars(bot)
    end
    if AI_Companion and AI_Companion.States and AI_Companion.States.FOLLOW then
        SetBotState(bot, AI_Companion.States.FOLLOW)
    else
        local data = self:GetData(bot)
        if data then
            data.state = "follow"
            data.task = "follow"
            data.flags.is_following = true
            self:UpdateData(bot, data)
        end
    end
    if settings and ApplyPlayerSettingsToBot then
        ApplyPlayerSettingsToBot(bot, settings, owner)
        if AI_CONFIG and AI_CONFIG.DEBUG_MODE then
            if AI_Utils and AI_Utils.LogDebug then
                AI_Utils.LogDebug("BotManager", "Настройки применены к боту %s", bot:Nick())
            end
        end
    end
    pcall(function()
        local weaponColor = owner:GetWeaponColor()
        if bot.SetWeaponColor then
            bot:SetWeaponColor(weaponColor)
        end
        local playerColor = owner:GetPlayerColor()
        if bot.SetPlayerColor then
            bot:SetPlayerColor(playerColor)
            bot:SetNWVector("PlayerColor", playerColor)
        end
    end)
    if SERVER then
        net.Start("AICompanion_OwnerSync")
        net.WriteEntity(bot)
        net.WriteEntity(owner)
        net.Broadcast()
        net.Start("AICompanion_ColorSync")
        net.WriteEntity(bot)
        net.WriteVector(owner:GetWeaponColor() or Vector(1, 1, 1))
        net.Broadcast()
    end
    if AI_Utils and AI_Utils.IsValid(bot) then
        bot:ChatPrint("[AI Компаньон] Готов.")
    end
    bot._aiSpawnNoCrouchUntil = CurTime() + (AI.Config.Spawn.SpawnGraceDuration or 5)
    ForceStandUp(bot)
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("BotManager", "Бот %s (ID: %d) создан для игрока %s", 
            uuid, bot:EntIndex(), owner:Nick())
    end
    return bot, nil
end
function BotManager:RemoveBot(bot, reason, skipMessage)
    if not IsValid(bot) then return false end
    if not IsCompanionBot(bot) then return false end
    if bot._aiUnregistering then return false end
    bot._aiUnregistering = true
    local uuid = bot._aiUUID
    local entry = uuid and BOTS[uuid]
    local owner = entry and entry.data and entry.data.owner
    local botID = bot:EntIndex()
    local name = bot:Nick() or "компаньон"
    self:CleanupBotTimers(bot)
    if uuid then
        Internal_RemoveBot(uuid)
    else
        for u, e in pairs(BOTS) do
            if e.bot == bot then
                Internal_RemoveBot(u)
                break
            end
        end
    end
    bot:SetNWBool("IsAICompanion", false)
    bot:SetNWEntity("AICompanionOwnerEnt", NULL)
    bot:SetNWString("AICompanionOwner", "")
    bot:SetNWString("BotState", "")
    bot:SetNWString("CurrentTask", "")
    if AC and AC.Companion then
        if AC.Companion.BotData then
            AC.Companion.BotData[botID] = nil
        end
        if AC.Companion.BotOwners then
            AC.Companion.BotOwners[botID] = nil
        end
        if AC.Companion.OwnerToBot then
            for ownerKey, b in pairs(AC.Companion.OwnerToBot) do
                if b == bot then
                    AC.Companion.OwnerToBot[ownerKey] = nil
                    break
                end
            end
        end
        if AC.Companion.RegisteredBots then
            AC.Companion.RegisteredBots[botID] = nil
        end
    end
    if not skipMessage then
        local msg = "Компаньон " .. name .. " удалён" .. (reason and " (" .. reason .. ")" or "")
        if AI_Utils and AI_Utils.LogInfo then
            AI_Utils.LogInfo("BotManager", msg)
        end
        if IsValid(owner) then
            owner:ChatPrint("[AI] Ваш компаньон " .. name .. " удалён" .. (reason and " (" .. reason .. ")" or ""))
        end
    end
    local botRef = bot
    if botRef:IsPlayer() and botRef:IsBot() then
        local kickReason = reason or "Companion removed"
        pcall(function() botRef:Kick(kickReason) end)
        timer.Simple(0.1, function()
            if IsValid(botRef) then
                botRef._aiUnregistering = nil
            end
        end)
    else
        timer.Simple(0.5, function()
            if IsValid(botRef) then
                pcall(function() botRef:Remove() end)
                botRef._aiUnregistering = nil
            end
        end)
    end
    return true
end
function UnregisterCompanionBot(bot, reason, skipMessage)
    if not IsValid(bot) then return false end
    if bot._aiUnregistering then return false end
    return BotManager:RemoveBot(bot, reason, skipMessage)
end
function BotManager:RemoveAllBots(owner, reason)
    if not IsValid(owner) then return 0 end
    local bots = self:GetBotsByOwner(owner)
    local count = 0
    for _, bot in ipairs(bots) do
        if self:RemoveBot(bot, reason or "Удалены владельцем", true) then
            count = count + 1
        end
    end
    return count
end
function BotManager:CanCreateBot(owner)
    if not IsValid(owner) then return false, "Невалидный владелец" end
    if self:HasBot(owner) then return false, "У владельца уже есть бот" end
    local maxBots = AI_CONFIG and AI_CONFIG.Spawn and AI_CONFIG.Spawn.MaxBotsTotal or 10
    if self:GetBotCount() >= maxBots then
        return false, "Достигнут лимит ботов на сервере (" .. maxBots .. ")"
    end
    return true, "OK"
end
function BotManager:UpdateData(bot, newData)
    if not IsValid(bot) then return false end
    local uuid = bot._aiUUID
    if not uuid then
        uuid = BOT_INDEX[bot:EntIndex()]
    end
    if not uuid or not BOTS[uuid] then return false end
    local oldData = BOTS[uuid].data
    BOTS[uuid].data = newData
    local oldOwner = oldData and oldData.owner
    local newOwner = newData.owner
    if oldOwner ~= newOwner then
        if IsValid(oldOwner) then
            local sid = GetSteamID64(oldOwner)
            if sid and OWNER_INDEX[sid] then
                for i, storedUuid in ipairs(OWNER_INDEX[sid]) do
                    if storedUuid == uuid then
                        table.remove(OWNER_INDEX[sid], i)
                        break
                    end
                end
                if #OWNER_INDEX[sid] == 0 then
                    OWNER_INDEX[sid] = nil
                end
            end
        end
        if IsValid(newOwner) then
            local sid = GetSteamID64(newOwner)
            if sid then
                if not OWNER_INDEX[sid] then
                    OWNER_INDEX[sid] = {}
                end
                table.insert(OWNER_INDEX[sid], uuid)
            end
        end
    end
    self:SyncToNWVars(bot)
    return true
end
function BotManager:MigrateFromLegacy()
    local migrated = 0
    local errors = 0
    local processed = {}
    local sources = {}
    if AI_Companion.BotData then
        for id, data in pairs(AI_Companion.BotData) do
            local bot = Entity(id)
            if IsValid(bot) and IsCompanionBot(bot) then
                table.insert(sources, { bot = bot, data = data, source = "BotData" })
            end
        end
    end
    if AI_Companion.RegisteredBots then
        for id, bot in pairs(AI_Companion.RegisteredBots) do
            if IsValid(bot) and IsCompanionBot(bot) and not processed[bot] then
                local data = GetBotData(bot)
                if data then
                    table.insert(sources, { bot = bot, data = data, source = "RegisteredBots" })
                    processed[bot] = true
                end
            end
        end
    end
    if AI_Companion.OwnerToBot then
        for owner, bot in pairs(AI_Companion.OwnerToBot) do
            if IsValid(bot) and IsCompanionBot(bot) and IsValid(owner) and not processed[bot] then
                local data = GetBotData(bot)
                if not data then
                    data = InitBotData(bot, owner, {})
                end
                if data then
                    data.owner = owner
                    table.insert(sources, { bot = bot, data = data, source = "OwnerToBot" })
                    processed[bot] = true
                end
            end
        end
    end
    for _, entry in ipairs(sources) do
        local bot = entry.bot
        local data = entry.data
        local alreadyExists = false
        local existingUuid = nil
        if bot._aiUUID and BOTS[bot._aiUUID] then
            alreadyExists = true
            existingUuid = bot._aiUUID
        end
        if not alreadyExists then
            local uuid = BOT_INDEX[bot:EntIndex()]
            if uuid and BOTS[uuid] then
                alreadyExists = true
                existingUuid = uuid
                bot._aiUUID = uuid
            end
        end
        if alreadyExists then
            if existingUuid and BOTS[existingUuid] then
                if data and data.owner and IsValid(data.owner) then
                    data._nw_cache.owner_name = data.owner:Nick()
                    data._nw_cache.is_ai_companion = true
                end
                BOTS[existingUuid].data = data
                migrated = migrated + 1
            end
        else
            local uuid = self:GenerateUUID()
            if not uuid then
                errors = errors + 1
            else
                bot._aiUUID = uuid
                if data and not IsValid(data.owner) then
                    data.owner = bot:GetNWEntity("AICompanionOwnerEnt")
                    if IsValid(data.owner) then
                        data._nw_cache.owner_name = data.owner:Nick()
                    end
                end
                Internal_AddBot(uuid, bot, data)
                migrated = migrated + 1
            end
        end
    end
    if migrated > 0 then
        if AI_Companion.BotData then
            for k in pairs(AI_Companion.BotData) do
                AI_Companion.BotData[k] = nil
            end
        end
        if AI_Companion.RegisteredBots then
            for k in pairs(AI_Companion.RegisteredBots) do
                AI_Companion.RegisteredBots[k] = nil
            end
        end
        if AI_Companion.OwnerToBot then
            for k in pairs(AI_Companion.OwnerToBot) do
                AI_Companion.OwnerToBot[k] = nil
            end
        end
        if AI_Companion.BotOwners then
            for k in pairs(AI_Companion.BotOwners) do
                AI_Companion.BotOwners[k] = nil
            end
        end
    end
    if migrated > 0 or errors > 0 then
        if AI_Utils and AI_Utils.LogInfo then
            AI_Utils.LogInfo("BotManager", "Миграция завершена:")
            AI_Utils.LogInfo("BotManager", "  - Успешно мигрировано: %d ботов", migrated)
            if errors > 0 then
                AI_Utils.LogWarn("BotManager", "  - Ошибок: %d", errors)
            end
        end
    end
    return migrated, errors
end
function BotManager:Cleanup()
    local removed = 0
    for uuid, entry in pairs(BOTS) do
        if not IsValid(entry.bot) then
            Internal_RemoveBot(uuid)
            removed = removed + 1
        elseif entry.bot:IsBot() and not entry.bot:Alive() then
            Internal_RemoveBot(uuid)
            removed = removed + 1
        elseif not IsCompanionBot(entry.bot) then
            Internal_RemoveBot(uuid)
            removed = removed + 1
        end
    end
    for _, bot in ipairs(player.GetAll()) do
        if IsValid(bot) and bot:IsBot() then
            if bot:GetNWBool("IsAICompanion", false) and not bot:Alive() then
                pcall(function() bot:Kick("Dead companion") end)
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        if AI_Utils and AI_Utils.LogInfo then
            AI_Utils.LogInfo("BotManager", "Очистка: удалено %d мёртвых записей", removed)
        end
    end
    return removed
end
function BotManager:GetStats()
    local stats = {
        totalBots = self:GetBotCount(),
        totalOwners = 0,
        botsPerOwner = {},
        uuidCount = table.Count(BOTS),
        indexCount = table.Count(BOT_INDEX),
    }
    for sid, uuids in pairs(OWNER_INDEX) do
        stats.totalOwners = stats.totalOwners + 1
        stats.botsPerOwner[sid] = #uuids
    end
    return stats
end
function BotManager:DebugPrint()
    self:Cleanup()
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        BOT MANAGER v5 - ВСЕ БОТЫ")
    print("═══════════════════════════════════════════════════════")
    print("")
    local count = 0
    for uuid, entry in pairs(BOTS) do
        if IsValid(entry.bot) then
            count = count + 1
            local bot = entry.bot
            local data = entry.data
            local owner = data and data.owner
            print("  [" .. uuid .. "] " .. bot:Nick() .. " (ID: " .. bot:EntIndex() .. ")")
            print("    Владелец: " .. (IsValid(owner) and owner:Nick() or "НЕТ"))
            print("    Состояние: " .. (data and data.state or "нет данных"))
            print("    Режимы: Стелс=" .. tostring(data and data.config.stealth_mode or false) ..
                  " Защитник=" .. tostring(data and data.config.defender_mode or false) ..
                  " Медик=" .. tostring(data and data.config.medic_mode or false))
            if data and data.combat and data.combat.target then
                print("    Цель боя: " .. tostring(data.combat.target))
            end
            print("")
        end
    end
    local stats = self:GetStats()
    print("  Всего ботов: " .. stats.totalBots)
    print("  Всего владельцев: " .. stats.totalOwners)
    print("  UUID в кэше: " .. stats.uuidCount)
    print("  Индексов EntIndex: " .. stats.indexCount)
    print("═══════════════════════════════════════════════════════")
    print("")
end
concommand.Add("ai_manager_debug", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end
    BotManager:DebugPrint()
end)
concommand.Add("ai_manager_cleanup", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end
    local removed = BotManager:Cleanup()
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("BotManager", "Очистка выполнена, удалено %d записей", removed)
    end
    if IsValid(ply) then
        ply:ChatPrint("[AI] Очистка выполнена, удалено " .. removed .. " записей")
    end
end)
concommand.Add("ai_manager_migrate", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("BotManager", "Запуск миграции...")
    end
    local migrated, errors = BotManager:MigrateFromLegacy()
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("BotManager", "Миграция завершена: %d ботов, %d ошибок", migrated, errors)
    end
    if IsValid(ply) then
        ply:ChatPrint("[AI] Миграция завершена: " .. migrated .. " ботов")
        if errors > 0 then
            ply:ChatPrint("[AI] Ошибок: " .. errors .. " (см. консоль)")
        end
    end
end)
concommand.Add("ai_manager_stats", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[AI] Только администраторы!")
        return
    end
    local stats = BotManager:GetStats()
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("BotManager", "Статистика:")
        AI_Utils.LogInfo("BotManager", "  Всего ботов: %d", stats.totalBots)
        AI_Utils.LogInfo("BotManager", "  Всего владельцев: %d", stats.totalOwners)
        AI_Utils.LogInfo("BotManager", "  UUID в кэше: %d", stats.uuidCount)
        AI_Utils.LogInfo("BotManager", "  Индексов EntIndex: %d", stats.indexCount)
    end
    if IsValid(ply) then
        ply:ChatPrint("[AI] Статистика выведена в консоль")
    end
end)
_G.GetBotData = function(bot)
    return BotManager:GetData(bot)
end
_G.SetBotState = function(bot, newState)
    return BotManager:SetBotState(bot, newState)
end
_G.GetBotState = function(bot)
    return BotManager:GetBotState(bot)
end
_G.GetCompanion = function(ply)
    return BotManager:GetCompanion(ply)
end
_G.HasCompanion = function(ply)
    return BotManager:HasCompanion(ply)
end
_G.GetAllCompanions = function()
    return BotManager:GetAllCompanions()
end
_G.GetAllBots = function()
    return BotManager:GetAllBots()
end
_G.GetPlayerCompanions = function(ply)
    return BotManager:GetBotsByOwner(ply)
end
_G.RegisterCompanionBot = function(bot, owner)
    if not IsValid(bot) or not IsValid(owner) then return false end
    if not IsCompanionBot(bot) then return false end
    local data = GetBotData(bot)
    if not data then
        data = InitBotData(bot, owner, {})
        if not data then return false end
    end
    data.owner = owner
    local uuid = bot._aiUUID or BotManager:GenerateUUID()
    if uuid then
        bot._aiUUID = uuid
        if not BOTS[uuid] then
            Internal_AddBot(uuid, bot, data)
            BotManager:SyncToNWVars(bot)
            return true
        end
    end
    return false
end
_G.UnregisterCompanionBot = function(bot, reason, skipMessage)
    return BotManager:RemoveBot(bot, reason, skipMessage)
end
timer.Simple(0.5, function()
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("BotManager", "Инициализация...")
    end
    BotManager:Cleanup()
    local hasOldData = false
    if AI_Companion.BotData and next(AI_Companion.BotData) then
        hasOldData = true
    end
    if AI_Companion.RegisteredBots and next(AI_Companion.RegisteredBots) then
        hasOldData = true
    end
    if AI_Companion.OwnerToBot and next(AI_Companion.OwnerToBot) then
        hasOldData = true
    end
    if hasOldData then
        if AI_Utils and AI_Utils.LogWarn then
            AI_Utils.LogWarn("BotManager", "Обнаружены старые данные, запуск миграции...")
        end
        local migrated, errors = BotManager:MigrateFromLegacy()
        if migrated > 0 or errors > 0 then
            if AI_Utils and AI_Utils.LogInfo then
                AI_Utils.LogInfo("BotManager", "Миграция завершена: %d ботов, %d ошибок", migrated, errors)
            end
        end
    end
    BotManager:SyncAllBots()
    if AI_Utils and AI_Utils.LogInfo then
        AI_Utils.LogInfo("BotManager", "Инициализация завершена, ботов: %d", BotManager:GetBotCount())
    end
end)
timer.Create("BotManager_Cleanup", 60, 0, function()
    BotManager:Cleanup()
end)
timer.Create("BotManager_Sync", 30, 0, function()
    BotManager:SyncAllBots()
end)
hook.Add("PlayerInitialSpawn", "BotManager_OnPlayerSpawn", function(ply)
    if not IsValid(ply) then return end
    if not ply:IsBot() then return end
    if IsCompanionBot(ply) then
        timer.Simple(0.5, function()
            if IsValid(ply) then
                BotManager:SyncToNWVars(ply)
            end
        end)
    end
end)
hook.Add("EntityRemoved", "BotManager_EntityRemoved", function(ent)
    if not IsValid(ent) then return end
    if not ent:IsPlayer() then return end
    if not ent:IsBot() then return end
    if IsCompanionBot(ent) then
        BotManager:CleanupBotTimers(ent)
        local uuid = ent._aiUUID
        if uuid and BOTS[uuid] then
            Internal_RemoveBot(uuid)
        end
    end
end)
hook.Add("PlayerDisconnected", "BotManager_PlayerDisconnected", function(ply)
    if not IsValid(ply) then return end
    if not ply:IsBot() then return end
    if IsCompanionBot(ply) then
        BotManager:CleanupBotTimers(ply)
    end
end)
hook.Add("PlayerDeath", "BotManager_BotDeath", function(victim, inflictor, attacker)
    if not IsValid(victim) then return end
    if victim:IsBot() then
        if IsCompanionBot(victim) then
            if AI_Utils and AI_Utils.LogInfo then
                AI_Utils.LogInfo("BotManager", "Бот-компаньон %s умер, удаляем...", victim:Nick())
            end
            local result = BotManager:RemoveBot(victim, "Бот погиб", false)
            if not result then
                pcall(function() victim:Kick("Bot died") end)
                local uuid = victim._aiUUID
                if uuid then Internal_RemoveBot(uuid) end
            end
        end
        return
    end
end)
_G.BotManager = BotManager
if AI_Utils and AI_Utils.LogInfo then
    AI_Utils.LogInfo("BotManager", "загружен")
end