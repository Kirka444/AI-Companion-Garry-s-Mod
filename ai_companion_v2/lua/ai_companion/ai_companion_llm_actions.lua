if AI_COMPANION_LLM_ACTIONS_LOADED then return end
AI_COMPANION_LLM_ACTIONS_LOADED = true
local AC = _G.AI_COMPANION
if not AI_Utils then include("ai_companion/ai_companion_utils.lua") end
if not AI_CONFIG then include("ai_companion/ai_config.lua") end
if not BotManager then include("ai_companion/ai_companion_botmanager.lua") end
local SPAWN_TABLE = {
    chair = { 
        model = "models/props_c17/chair02a.mdl", 
        type = "prop",
        fallback = "models/props_c17/furniturechair001a.mdl"
    },
    table = { 
        model = "models/props_c17/table01a.mdl", 
        type = "prop",
        fallback = "models/props_c17/furnituredesk01a.mdl"
    },
    crate = { 
        model = "models/props_c17/crate01a.mdl", 
        type = "prop",
        fallback = "models/props_junk/wood_crate001a.mdl"
    },
    barrel = { 
        model = "models/props_c17/barrel01a.mdl", 
        type = "prop",
        fallback = "models/props_junk/barrel001a.mdl"
    },
    box = { 
        model = "models/props_c17/crate01a.mdl", 
        type = "prop",
        fallback = "models/props_junk/wood_crate001a.mdl"
    },
    pallet = { 
        model = "models/props_c17/pallet01a.mdl", 
        type = "prop" 
    },
    shelf = { 
        model = "models/props_c17/shelf01a.mdl", 
        type = "prop",
        fallback = "models/props_c17/shelf02a.mdl"
    },
    lamp = { 
        model = "models/props_c17/lamp01a.mdl", 
        type = "prop" 
    },
    computer = { 
        model = "models/props_c17/computer01a.mdl", 
        type = "prop" 
    },
    monitor = { 
        model = "models/props_c17/monitor01a.mdl", 
        type = "prop" 
    },
    tv = { 
        model = "models/props_c17/tv01a.mdl", 
        type = "prop" 
    },
    toilet = { 
        model = "models/props_c17/toilet01a.mdl", 
        type = "prop" 
    },
    sink = { 
        model = "models/props_c17/sink01a.mdl", 
        type = "prop" 
    },
    bathtub = { 
        model = "models/props_c17/bathtub01a.mdl", 
        type = "prop" 
    },
    bed = { 
        model = "models/props_c17/bed01a.mdl", 
        type = "prop" 
    },
    couch = { 
        model = "models/props_c17/couch01a.mdl", 
        type = "prop" 
    },
    fridge = { 
        model = "models/props_c17/fridge01a.mdl", 
        type = "prop" 
    },
    stove = { 
        model = "models/props_c17/stove01a.mdl", 
        type = "prop" 
    },
    microwave = { 
        model = "models/props_c17/microwave01a.mdl", 
        type = "prop" 
    },
    crate_metal = { 
        model = "models/props_junk/metal_crate001a.mdl", 
        type = "prop" 
    },
    crate_wood = { 
        model = "models/props_junk/wood_crate001a.mdl", 
        type = "prop" 
    },
    dumpster = { 
        model = "models/props_c17/dumpster01a.mdl", 
        type = "prop" 
    },
    trashcan = { 
        model = "models/props_c17/trashcan01a.mdl", 
        type = "prop" 
    },
    bench = { 
        model = "models/props_c17/bench01a.mdl", 
        type = "prop" 
    },
    zombie = { class = "npc_zombie", type = "npc" },
    zombie_fast = { class = "npc_fastzombie", type = "npc" },
    zombie_poison = { class = "npc_poisonzombie", type = "npc" },
    combine = { class = "npc_combine_s", type = "npc" },
    combine_elite = { class = "npc_combine_elite", type = "npc" },
    citizen = { class = "npc_citizen", type = "npc" },
    dog = { class = "npc_dog", type = "npc" },
    headcrab = { class = "npc_headcrab", type = "npc" },
    headcrab_fast = { class = "npc_headcrab_fast", type = "npc" },
    headcrab_poison = { class = "npc_headcrab_poison", type = "npc" },
    antlion = { class = "npc_antlion", type = "npc" },
    antlion_guard = { class = "npc_antlion_guard", type = "npc" },
    vortigaunt = { class = "npc_vortigaunt", type = "npc" },
    strider = { class = "npc_strider", type = "npc" },
    gunship = { class = "npc_combinegunship", type = "npc" },
    helicopter = { class = "npc_helicopter", type = "npc" },
    manhack = { class = "npc_manhack", type = "npc" },
    rollermine = { class = "npc_rollermine", type = "npc" },
    healthkit = { class = "item_healthkit", type = "item" },
    healthvial = { class = "item_healthvial", type = "item" },
    battery = { class = "item_battery", type = "item" },
    ammo = { class = "item_ammo_smg1", type = "item" },
    ammo_pistol = { class = "item_ammo_pistol", type = "item" },
    ammo_ar2 = { class = "item_ammo_ar2", type = "item" },
    ammo_buckshot = { class = "item_ammo_buckshot", type = "item" },
    ammo_357 = { class = "item_ammo_357", type = "item" },
    ammo_rpg = { class = "item_ammo_rpg_round", type = "item" },
    grenade = { class = "weapon_frag", type = "weapon" },
    rpg = { class = "weapon_rpg", type = "weapon" },
    smg1 = { class = "weapon_smg1", type = "weapon" },
    shotgun = { class = "weapon_shotgun", type = "weapon" },
    pistol = { class = "weapon_pistol", type = "weapon" },
    crowbar = { class = "weapon_crowbar", type = "weapon" },
    stunstick = { class = "weapon_stunstick", type = "weapon" },
    jeep = { class = "prop_vehicle_jeep", type = "vehicle" },
    airboat = { class = "prop_vehicle_airboat", type = "vehicle" },
    car = { class = "prop_vehicle_driveable", type = "vehicle" },
}
function SpawnEntity(ply, keyword, customModel)
    if not IsValid(ply) then return false, "Игрок не валиден" end
    local synonyms = {
        chair = "chair",
        table = "table", desk = "table",
        crate = "crate", box = "crate", crate_wood = "crate",
        barrel = "barrel", drum = "barrel",
        zombie = "zombie", z = "zombie",
        combine = "combine", soldier = "combine",
        citizen = "citizen",
        health = "healthkit", medkit = "healthkit", item_healthkit = "healthkit",
        healthvial = "healthvial", vial = "healthvial",
        battery = "battery", item_battery = "battery", bat = "battery",
        ammo = "ammo", item_ammo = "ammo", ammo_smg1 = "ammo",
        ammo_pistol = "ammo_pistol", pistol_ammo = "ammo_pistol",
        ammo_ar2 = "ammo_ar2", ar2_ammo = "ammo_ar2",
        ammo_buckshot = "ammo_buckshot", buckshot = "ammo_buckshot",
        ammo_357 = "ammo_357", magnum_ammo = "ammo_357",
        ammo_rpg = "ammo_rpg", rpg_ammo = "ammo_rpg",
        grenade = "grenade", frag = "grenade",
        rpg = "rpg", rocket = "rpg",
        smg1 = "smg1", smg = "smg1",
        shotgun = "shotgun",
        pistol = "pistol",
        crowbar = "crowbar",
        stunstick = "stunstick",
        jeep = "jeep", car = "car", vehicle = "car",
        airboat = "airboat", boat = "airboat",
        couch = "couch", sofa = "couch",
        bed = "bed",
        lamp = "lamp",
        tv = "tv", monitor = "monitor",
        computer = "computer", pc = "computer",
        toilet = "toilet",
        sink = "sink",
        bathtub = "bathtub", tub = "bathtub",
        fridge = "fridge", refrigerator = "fridge",
        stove = "stove", oven = "stove",
        microwave = "microwave",
        dumpster = "dumpster", trash = "dumpster",
        bench = "bench",
        pallet = "pallet",
        shelf = "shelf",
    }
    local entry = SPAWN_TABLE[keyword]
    if not entry then
        local realKeyword = synonyms[keyword]
        if realKeyword then
            entry = SPAWN_TABLE[realKeyword]
        end
    end
    if not entry then
        local found = nil
        local bestScore = 0
        for k, v in pairs(SPAWN_TABLE) do
            if string.find(k, keyword, 1, true) then
                local score = #keyword / #k
                if score > bestScore then
                    bestScore = score
                    found = v
                end
            end
            if v.class and string.find(v.class, keyword, 1, true) then
                local score = #keyword / #v.class
                if score > bestScore then
                    bestScore = score
                    found = v
                end
            end
        end
        entry = found
        if not entry then
            if customModel and customModel ~= "" then
                entry = { model = customModel, type = "prop" }
            else
                return false, "Неизвестный тип: " .. keyword
            end
        end
    end
    local spawnPos = ply:GetPos() + ply:GetForward() * 150 + Vector(0, 0, 10)
    local tr = util.TraceHull({
        start = spawnPos + Vector(0, 0, 36),
        endpos = spawnPos + Vector(0, 0, 36),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 72),
        filter = ply
    })
    if tr.Hit then
        spawnPos = ply:GetPos() + ply:GetForward() * 100 + Vector(0, 0, 10)
    end
    local ent
    if entry.type == "prop" then
        local model = entry.model or customModel
        if not model then return false, "Нет модели" end
        local function IsModelValid(mdl)
            return util.IsValidModel(mdl)
        end
        local modelsToTry = { model }
        if entry.fallback then table.insert(modelsToTry, entry.fallback) end
        if keyword == "barrel" or keyword == "drum" then
            table.insert(modelsToTry, "models/props_c17/oildrum001.mdl")
            table.insert(modelsToTry, "models/props_junk/barrel001a.mdl")
        end
        local chosenModel = nil
        for _, mdl in ipairs(modelsToTry) do
            if IsModelValid(mdl) then
                chosenModel = mdl
                break
            end
        end
        if not chosenModel then
            return false, "Модель не найдена: " .. model .. " (пробовали: " .. table.concat(modelsToTry, ", ") .. ")"
        end
        ent = ents.Create("prop_physics")
        if not IsValid(ent) then return false, "Не удалось создать prop" end
        ent:SetModel(chosenModel)
        ent:SetPos(spawnPos)
        ent:Spawn()
        ent:Activate()
        if IsValid(ent) then
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then phys:Wake() end
        end
    elseif entry.type == "npc" then
        local class = entry.class
        if not class then return false, "Нет класса NPC" end
        ent = ents.Create(class)
        if not IsValid(ent) then return false, "Не удалось создать NPC" end
        ent:SetPos(spawnPos)
        ent:Spawn()
        ent:Activate()
        if class == "npc_zombie" or class == "npc_combine_s" or class == "npc_antlion" then
            ent:SetKeyValue("spawnflags", "1")
        end
    elseif entry.type == "item" or entry.type == "weapon" then
        local class = entry.class
        if not class then return false, "Нет класса предмета" end
        ent = ents.Create(class)
        if not IsValid(ent) then return false, "Не удалось создать предмет" end
        ent:SetPos(spawnPos)
        ent:Spawn()
        if entry.type == "weapon" and ent:IsWeapon() then
            local ammoType = ent:GetPrimaryAmmoType()
            if ammoType and ammoType ~= -1 then
                ent:SetClip1(ent:GetMaxClip1() or 30)
                ply:GiveAmmo(120, ammoType, true)
            end
        end
    elseif entry.type == "vehicle" then
        local class = entry.class
        if not class then return false, "Нет класса транспорта" end
        ent = ents.Create(class)
        if not IsValid(ent) then return false, "Не удалось создать транспорт" end
        ent:SetPos(spawnPos)
        ent:Spawn()
        ent:Activate()
        if class == "prop_vehicle_jeep" then
            ent:SetKeyValue("vehiclescript", "scripts/vehicles/jeep_test.txt")
        end
    else
        return false, "Неизвестный тип объекта"
    end
    return true, ent
end
function ProcessLLMResponse(ply, response)
    if not IsValid(ply) then return response end
    if not response or response == "" then return response end
    local hasCommand = string.find(response, "!companion", 1, true)
    if not hasCommand then return response end
    local processedResponse = response
    local commandsExecuted = false
    local pattern = "!companion%s+([%a_]+)%s*(.-)%s*$"
    for i = 1, 5 do
        local cmdStart, cmdEnd, cmd, arg = string.find(processedResponse, pattern)
        if not cmdStart then break end
        local beforeCmd = string.sub(processedResponse, 1, cmdStart - 1)
        beforeCmd = string.Trim(beforeCmd)
        ExecuteCompanionCommand(ply, cmd, arg or "")
        commandsExecuted = true
        local afterCmd = string.sub(processedResponse, cmdEnd + 1)
        processedResponse = string.Trim(beforeCmd .. " " .. afterCmd)
    end
    if commandsExecuted and string.Trim(processedResponse) == "" then
        return ""
    end
    return processedResponse
end
function ExecuteCompanionCommand(ply, cmd, args)
    if not IsValid(ply) then return end
    if not cmd or cmd == "" then return end
    cmd = string.lower(cmd)
    local bot = FindOwnedBot(ply)
    if not IsValid(bot) and cmd ~= "spawn" then
        SendAIMessage(ply, " У вас нет компаньона!")
        return
    end
    if cmd == "follow" then
        _G.AI_Companion_Disabled = false
        if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
        bot:SetNWEntity("AI_Glide_TargetVehicle", nil)
        if SetBotState then SetBotState(bot, AC.Companion.States.FOLLOW) end
    elseif cmd == "stop" then
        _G.AI_Companion_Disabled = true
        if SetBotState then 
            SetBotState(bot, AC.Companion.States.IDLE) 
        end
        if IsValid(bot) then 
            bot:SetLocalVelocity(Vector(0, 0, 0))
            bot:SetNWString("CurrentTask", "idle")
            if bot.SetSchedule then
                bot:SetSchedule(SCHED_IDLE_STAND)
            end
        end
        SendAIMessage(ply, " Компаньон остановлен.")
    elseif cmd == "point" then
        _G.AI_Companion_Disabled = false
        if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
        bot:SetNWEntity("AI_Glide_TargetVehicle", nil)
        local data = BotManager and BotManager:GetData(bot) or GetBotData(bot) or {}
        data.point = data.point or {}
        data.point.pos = bot:GetPos()
        data.point.angle = bot:EyeAngles()
        if BotManager then 
            BotManager:UpdateData(bot, data) 
        end
        if SetBotState then 
            SetBotState(bot, AC.Companion.States.POINTING)
        end
    elseif cmd == "sit" then
        _G.AI_Companion_Disabled = false
        if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
        local seat = nil
        if FindAnyFreeSeat then
            seat = FindAnyFreeSeat(bot, 500)
        end
        if IsValid(seat) then
            local success = pcall(function() bot:EnterVehicle(seat) end)
            if success and bot:InVehicle() then
                if SetBotState then SetBotState(bot, AC.Companion.States.SITTING) end
            end
        else
            SendAIMessage(ply, " Поблизости нет свободных мест.")
        end
    elseif cmd == "standup" then
        _G.AI_Companion_Disabled = false
        if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
        bot:SetNWEntity("AI_Glide_TargetVehicle", nil)
        if SetBotState then SetBotState(bot, AC.Companion.States.FOLLOW) end
    elseif cmd == "attack" then
        if AI_Utils.IsPassenger and AI_Utils.IsPassenger(bot) then return end
        if args and args ~= "" then
            local targetName = args
            if targetName == "1" or string.lower(targetName) == "me" or string.lower(targetName) == "меня" then
                targetName = ply:Nick()
            end
            local target = FindPlayerByName(targetName)
            if IsValid(target) then
                local data = BotManager and BotManager:GetData(bot) or GetBotData(bot) or {}
                if not data.combat then data.combat = {} end
                data.combat.target = target
                data.combat.target_type = "player"
                data.combat.triggered_by = "command_llm"
                data.combat.last_attack_time = CurTime()
                if SetBotState then SetBotState(bot, AC.Companion.States.COMBAT) end
                local combatWep = GetBotCombatWeapon and GetBotCombatWeapon(bot) or "weapon_smg1"
                if not bot:HasWeapon(combatWep) then bot:Give(combatWep) end
                bot:SelectWeapon(combatWep)
                if BotManager then BotManager:UpdateData(bot, data) end
                SendAIMessage(ply, "Атакую " .. target:Nick())
            else
                SendAIMessage(ply, " Игрок не найден: " .. targetName)
            end
        else
            local botPos = bot:GetPos()
            local nearestEnemy = nil
            local nearestDist = AI.Config.Combat.CommandAttackRadius or 2000
            for _, ent in ipairs(AI_Utils.FindInSphere(botPos, nearestDist)) do
                if IsValid(ent) and ent:Alive() and ent ~= bot and ent ~= ply then
                    if (IsHostileEntity and IsHostileEntity(ent)) or ent:IsPlayer() then
                        local dist = botPos:Distance(ent:GetPos())
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestEnemy = ent
                        end
                    end
                end
            end
            if IsValid(nearestEnemy) then
                if SetCombatTarget then SetCombatTarget(bot, nearestEnemy, "npc", "command") end
                local combatWep = GetBotCombatWeapon and GetBotCombatWeapon(bot) or "weapon_smg1"
                if not bot:HasWeapon(combatWep) then bot:Give(combatWep) end
                bot:SelectWeapon(combatWep)
                local name = nearestEnemy:IsPlayer() and nearestEnemy:Nick() or nearestEnemy:GetClass()
                SendAIMessage(ply, "Атакую " .. name)
            else
                SendAIMessage(ply, " Врагов поблизости нет.")
            end
        end
    elseif cmd == "spawn" then
        if SpawnEntity then
            local success, result = SpawnEntity(ply, args, "")
            if success and IsValid(result) then
                SendAIMessage(ply, " Создан: " .. (result:GetClass() or "объект"))
            else
                SendAIMessage(ply, " Ошибка: " .. tostring(result))
            end
        end
    elseif cmd == "status" then
        local hp = math.Round(bot:Health()) .. "/" .. math.Round(bot:GetMaxHealth())
        local armor = math.Round(bot:Armor())
        local state = GetBotState and GetBotState(bot) or "idle"
        local inVeh = bot:InVehicle() and " в транспорте" or " пешком"
        SendAIMessage(ply, "=== Статус ===\n " .. (bot:Nick() or "неизвестно") .. "\n " .. hp .. " |  " .. armor .. "\n " .. state .. " | " .. inVeh)
    else
        SendAIMessage(ply, " Неизвестная команда: !companion " .. cmd)
    end
end
function SendAIMessage(ply, msg)
    if not IsValid(ply) or not SERVER then return end
    local prefixColor = Color(255, 200, 0)
    if AI_Utils and AI_Utils.GetPrefixColor then
        prefixColor = AI_Utils.GetPrefixColor(ply)
    end
    local cleanPrefix = "AI"
    if AI_Utils and AI_Utils.GetCleanPrefix then
        cleanPrefix = AI_Utils.GetCleanPrefix(ply)
    end
    net.Start("AI_Companion_Chat")
    net.WriteString(msg)
    net.WriteColor(prefixColor)
    net.WriteString(cleanPrefix)
    net.WriteString(ply:Nick())
    net.WriteString(ply:SteamID64())
    net.Send(ply)
end
function FindPlayerByName(name)
    if not name or name == "" then return nil end
    name = string.lower(name)
    local bestMatch = nil
    local bestScore = 0
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and not ply:IsBot() then
            local nick = string.lower(ply:Nick())
            if nick == name then return ply end
            if string.find(nick, name, 1, true) then
                local score = #name / #nick
                if score > bestScore then
                    bestScore = score
                    bestMatch = ply
                end
            end
        end
    end
    return bestMatch
end