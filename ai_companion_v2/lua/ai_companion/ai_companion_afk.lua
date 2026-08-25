if AI_COMPANION_AFK_LOADED then return end
AI_COMPANION_AFK_LOADED = true
local AC = _G.AI_COMPANION
local AFK_CFG = {
    InactivityTimeout = 30,
    CheckInterval = 5,
    ActionInterval = {
        min = 5,
        max = 40,
    },
    ActionWeights = {
        sit = 25,
        wait = 5,
        fight_zombie = 20,
        fight_zombine = 10,
        fight_poisonzombie = 8,
        fight_fastzombie = 8,
        fight_antlion = 10,
        fight_combine = 10,
        fight_metropolice = 8,
        fight_hunter = 5,
        dance = 15,
        point = 10,
    },
    ZombieLifetime = 15,
    DanceDuration = 5,
    SpawnDistance = {
        default = 150,
        npc_hunter = 250,
        npc_combine_s = 150,
        npc_metropolice = 150,
        npc_zombine = 150,
        npc_poisonzombie = 150,
        npc_fastzombie = 150,
        npc_zombie = 150,
    },
    ChairHeight = 18,  
}
if AI_CONFIG and AI_CONFIG.Magic then
    AI_CONFIG.Magic.AFK = AI_CONFIG.Magic.AFK or AFK_CFG
    AFK_CFG = AI_CONFIG.Magic.AFK
end
local AFK_State = {}
local function GetAFKState(bot)
    if not IsValid(bot) then return nil end
    local id = bot:EntIndex()
    if not AFK_State[id] then
        AFK_State[id] = {
            is_afk = false,
            action = nil,
            dance_until = 0,
            zombie = nil,
            seat = nil,
            exit_attempts = 0,
            next_action_time = 0,
            last_action_time = 0,
            action_count = 0,
            mob_type = nil,
        }
    end
    return AFK_State[id]
end
local function UpdateOwnerActivity(owner)
    if not IsValid(owner) then return end
    owner._ai_last_move_time = CurTime()
end
local function IsOwnerActive(owner)
    if not IsValid(owner) then return false end
    local lastMove = owner._ai_last_move_time or 0
    return CurTime() - lastMove < AFK_CFG.InactivityTimeout
end
local function ExecuteBotCommand(bot, command)
    if not IsValid(bot) then return end
    hook.Run("PlayerSay", bot, command)
end
local function SpawnChairDirect(bot)
    if not IsValid(bot) then return nil end
    local botPos = bot:GetPos()
    local forward = bot:GetForward()
    local distance = 80
    local offset = forward * distance + Vector(0, 0, 10)
    local pos = botPos + offset
    local hullTr = util.TraceHull({
        start = pos + Vector(0, 0, 36),
        endpos = pos + Vector(0, 0, 36),
        mins = Vector(-20, -20, 0),
        maxs = Vector(20, 20, 72),
        filter = {bot, bot:GetNWEntity("AICompanionOwnerEnt")}
    })
    if hullTr.Hit then
        local angles = {0, 45, 90, 135, 180, 225, 270, 315}
        local found = false
        for _, ang in ipairs(angles) do
            local rad = math.rad(ang)
            local testOffset = Vector(
                math.cos(rad) * distance,
                math.sin(rad) * distance,
                10
            )
            local testPos = botPos + testOffset
            local testHull = util.TraceHull({
                start = testPos + Vector(0, 0, 36),
                endpos = testPos + Vector(0, 0, 36),
                mins = Vector(-20, -20, 0),
                maxs = Vector(20, 20, 72),
                filter = {bot, bot:GetNWEntity("AICompanionOwnerEnt")}
            })
            if not testHull.Hit then
                pos = testPos
                found = true
                break
            end
        end
        if not found then
            for i = 1, 5 do
                local testDistance = distance + (i * 30)
                for _, ang in ipairs(angles) do
                    local rad = math.rad(ang)
                    local testOffset = Vector(
                        math.cos(rad) * testDistance,
                        math.sin(rad) * testDistance,
                        10
                    )
                    local testPos = botPos + testOffset
                    local testHull = util.TraceHull({
                        start = testPos + Vector(0, 0, 36),
                        endpos = testPos + Vector(0, 0, 36),
                        mins = Vector(-20, -20, 0),
                        maxs = Vector(20, 20, 72),
                        filter = {bot, bot:GetNWEntity("AICompanionOwnerEnt")}
                    })
                    if not testHull.Hit then
                        pos = testPos
                        found = true
                        break
                    end
                end
                if found then break end
            end
        end
        if not found then
            pos = botPos + forward * 150 + Vector(0, 0, 10)
        end
    end
    local downTrace = util.TraceLine({
        start = pos + Vector(0, 0, 100),
        endpos = pos - Vector(0, 0, 200),
        filter = {bot, bot:GetNWEntity("AICompanionOwnerEnt")},
        mask = MASK_PLAYERSOLID
    })
    if downTrace.Hit then
        pos = downTrace.HitPos + Vector(0, 0, AFK_CFG.ChairHeight)
    else
        pos = Vector(pos.x, pos.y, botPos.z + AFK_CFG.ChairHeight)
    end
    local finalCheck = util.TraceHull({
        start = pos + Vector(0, 0, 36),
        endpos = pos + Vector(0, 0, 36),
        mins = Vector(-18, -18, 0),
        maxs = Vector(18, 18, 70),
        filter = {bot, bot:GetNWEntity("AICompanionOwnerEnt")}
    })
    if finalCheck.Hit then
        pos = botPos + forward * 200 + Vector(0, 0, 10)
        local downTrace2 = util.TraceLine({
            start = pos + Vector(0, 0, 100),
            endpos = pos - Vector(0, 0, 200),
            filter = {bot, bot:GetNWEntity("AICompanionOwnerEnt")},
            mask = MASK_PLAYERSOLID
        })
        if downTrace2.Hit then
            pos = downTrace2.HitPos + Vector(0, 0, AFK_CFG.ChairHeight)
        end
    end
    local chair = ents.Create("prop_vehicle_prisoner_pod")
    if not IsValid(chair) then return nil end
    chair:SetModel("models/props_c17/chair02a.mdl")
    chair:SetPos(pos)
    chair:Spawn()
    chair:Activate()
    timer.Simple(0.05, function()
        if IsValid(chair) then
            local phys = chair:GetPhysicsObject()
            if IsValid(phys) then
                pcall(function()
                    phys:EnableMotion(false)
                end)
            end
        end
    end)
    return chair
end
local function SpawnMobDirect(bot, mobType)
    if not IsValid(bot) then return nil end
    if not mobType or mobType == "zombie" or mobType == "fight_zombie" then
        mobType = "npc_zombie"
    end
    local spawnDist = AFK_CFG.SpawnDistance[mobType] or AFK_CFG.SpawnDistance.default or 150
    local botAngles = bot:EyeAngles()
    local backward = botAngles:Forward() * -1
    local pos = bot:GetPos() + backward * spawnDist + Vector(0, 0, 10)
    local tr = util.TraceHull({
        start = pos + Vector(0, 0, 36),
        endpos = pos + Vector(0, 0, 36),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 72),
        filter = bot
    })
    if tr.Hit then
        local right = botAngles:Right()
        local offsets = {
            backward * spawnDist + right * 50,
            backward * spawnDist - right * 50,
            backward * (spawnDist * 0.7) + right * 30,
            backward * (spawnDist * 0.7) - right * 30,
        }
        for _, offset in ipairs(offsets) do
            local testPos = bot:GetPos() + offset + Vector(0, 0, 10)
            local testTr = util.TraceHull({
                start = testPos + Vector(0, 0, 36),
                endpos = testPos + Vector(0, 0, 36),
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 72),
                filter = bot
            })
            if not testTr.Hit then
                pos = testPos
                break
            end
        end
    end
    local mob = ents.Create(mobType)
    if not IsValid(mob) then return nil end
    mob:SetPos(pos)
    local toBot = bot:GetPos() - pos
    toBot.z = 0
    if toBot:LengthSqr() > 0.001 then
        toBot:Normalize()
        mob:SetAngles(toBot:Angle())
    end
    local health = 100
    if mobType == "npc_hunter" then
        health = 300
    elseif mobType == "npc_combine_s" or mobType == "npc_metropolice" then
        health = 120
    elseif mobType == "npc_zombine" then
        health = 150
    elseif mobType == "npc_fastzombie" then
        health = 70
    elseif mobType == "npc_poisonzombie" then
        health = 130
    end
    mob:Spawn()
    mob:Activate()
    mob:SetHealth(health)
    return mob
end
function ExecuteAFKActionDirect(bot, owner, state, action)
    if not IsValid(bot) or not state then return end
    if action ~= "fight_zombie" and not string.find(action, "fight_") and IsValid(state.zombie) then
        state.zombie:Remove()
        state.zombie = nil
    end
    if action ~= "sit" and IsValid(state.seat) then
        state.seat:Remove()
        state.seat = nil
    end
    state.exit_attempts = 0
    if bot:InVehicle() then
        pcall(function() bot:ExitVehicle() end)
    end
    local data = GetBotData(bot)
    if data and data.combat and IsValid(data.combat.target) then
        if not (IsValid(state.zombie) and data.combat.target == state.zombie) then
            ClearCombatTarget(bot)
        end
    end
    state.is_afk = true
    state.action = action
    state.dance_until = 0
    if action == "sit" then
        local chair = SpawnChairDirect(bot)
        if IsValid(chair) then
            state.seat = chair
            timer.Simple(0.5, function()
                if IsValid(bot) and IsValid(chair) then
                    local phys = chair:GetPhysicsObject()
                    if IsValid(phys) then
                        pcall(function()
                            phys:EnableMotion(false)
                        end)
                    end
                    local success = pcall(function() 
                        bot:EnterVehicle(chair) 
                    end)
                    if not success or not bot:InVehicle() then
                        timer.Simple(0.3, function()
                            if IsValid(bot) and IsValid(chair) then
                                local success2 = pcall(function() 
                                    bot:EnterVehicle(chair) 
                                end)
                                if not success2 or not bot:InVehicle() then
                                    if IsValid(chair) then 
                                        chair:Remove() 
                                        state.seat = nil 
                                    end
                                    state.action = "wait"
                                end
                            end
                        end)
                    end
                else
                    if IsValid(chair) then 
                        chair:Remove() 
                        state.seat = nil 
                    end
                    state.action = "wait"
                end
            end)
        else
            state.action = "wait"
        end
    elseif action == "fight_zombie" or action == "fight" or string.find(action, "fight_") then
        local mobType = "npc_zombie"
        if action == "fight_zombie" or action == "fight" then
            local mobTypes = {
                "npc_zombie",
                "npc_zombine",
                "npc_poisonzombie",
                "npc_fastzombie",
                "npc_combine_s",
                "npc_metropolice",
                "npc_hunter",
            }
            mobType = mobTypes[math.random(1, #mobTypes)]
        elseif action == "fight_zombine" then
            mobType = "npc_zombine"
        elseif action == "fight_poisonzombie" then
            mobType = "npc_poisonzombie"
        elseif action == "fight_fastzombie" then
            mobType = "npc_fastzombie"
        elseif action == "fight_combine" then
            mobType = "npc_combine_s"
        elseif action == "fight_metropolice" then
            mobType = "npc_metropolice"
        elseif action == "fight_hunter" then
            mobType = "npc_hunter"
        end
        if IsValid(state.zombie) and state.zombie:Alive() then
            return
        end
        if IsValid(state.zombie) then
            state.zombie:Remove()
            state.zombie = nil
        end
        local mob = SpawnMobDirect(bot, mobType)
        if IsValid(mob) then
            state.zombie = mob
            state.mob_type = mobType
            timer.Simple(0.5, function()
                if IsValid(bot) and IsValid(mob) and mob:Alive() then
                    SetCombatTarget(bot, mob, "npc", "afk")
                    local combatWep = GetBotCombatWeapon(bot) or "weapon_smg1"
                    if not bot:HasWeapon(combatWep) then bot:Give(combatWep) end
                    bot:SelectWeapon(combatWep)
                else
                    if IsValid(mob) then 
                        mob:Remove() 
                        state.zombie = nil 
                    end
                end
            end)
        end
    elseif action == "dance" then
        local tauntActs = {
            ACT_GMOD_TAUNT_DANCE,
            ACT_GMOD_TAUNT_MUSCLE,
            ACT_GMOD_TAUNT_CHEER,
            ACT_GMOD_TAUNT_ZOMBIE,
            ACT_GMOD_TAUNT_LAUGH,
        }
        local validActs = {}
        for _, act in ipairs(tauntActs) do
            if act and type(act) == "number" then
                table.insert(validActs, act)
            end
        end
        if #validActs == 0 then
            if ACT_GMOD_TAUNT_DANCE and type(ACT_GMOD_TAUNT_DANCE) == "number" then
                validActs = {ACT_GMOD_TAUNT_DANCE}
            else
                state.action = "wait"
                return
            end
        end
        local chosenAct = validActs[math.random(1, #validActs)]
        if chosenAct and type(chosenAct) == "number" then
            xpcall(
                function() bot:DoAnimationEvent(chosenAct) end,
                function(err)
                    if AI_Utils and AI_Utils.LogDebug then
                        AI_Utils.LogDebug("AFK", "Ошибка анимации: %s", tostring(err))
                    end
                    state.action = "wait"
                    return
                end
            )
        else
            state.action = "wait"
            return
        end
        state.dance_until = CurTime() + AFK_CFG.DanceDuration
    elseif action == "point" then
        local data = GetBotData(bot)
        if data then
            data.point = data.point or {}
            data.point.pos = bot:GetPos() + bot:GetForward() * 500
            data.point.angle = bot:EyeAngles()
            if BotManager then
                BotManager:UpdateData(bot, data)
            end
        end
        SetBotState(bot, AC.Companion.States.POINTING)
        if IsValid(bot) then
            bot:ChatPrint("[AI] Указываю направление.")
        end
    else
        state.action = "wait"
        if IsValid(bot) then
            SetBotState(bot, AC.Companion.States.IDLE)
            bot:SetLocalVelocity(Vector(0, 0, 0))
        end
    end
    state.last_action_time = CurTime()
    state.action_count = state.action_count + 1
    local interval = math.random(AFK_CFG.ActionInterval.min, AFK_CFG.ActionInterval.max)
    state.next_action_time = CurTime() + interval
end
local function ExitAFKMode(bot, state)
    if not IsValid(bot) or not state or not state.is_afk then return end
    ExecuteBotCommand(bot, "!companion standup")
    if IsValid(state.seat) then
        state.seat:Remove()
        state.seat = nil
    end
    if IsValid(state.zombie) then
        state.zombie:Remove()
        state.zombie = nil
    end
    local data = GetBotData(bot)
    if data and data.combat and IsValid(data.combat.target) then
        ClearCombatTarget(bot)
    end
    timer.Simple(0.5, function()
        if IsValid(bot) then
            if bot:InVehicle() then
                pcall(function() bot:ExitVehicle() end)
                timer.Simple(0.3, function()
                    if IsValid(bot) and bot:InVehicle() then
                        pcall(function() bot:ExitVehicle() end)
                        bot:SetPos(bot:GetPos() + Vector(0, 0, 10))
                    end
                    if IsValid(bot) then
                        bot:RemoveFlags(FL_DUCKING)
                        bot:RemoveFlags(FL_ANIMDUCKING)
                        pcall(function() bot:ConCommand("-duck") end)
                    end
                end)
            end
        end
    end)
    timer.Simple(0.2, function()
        if IsValid(bot) then
            SetBotState(bot, AC.Companion.States.FOLLOW)
        end
    end)
    state.is_afk = false
    state.action = nil
    state.dance_until = 0
    state.exit_attempts = 0
    state.next_action_time = 0
    state.last_action_time = 0
end
function ForceAFKMode(bot, action)
    if not IsValid(bot) then return false end
    local state = GetAFKState(bot)
    if not state then return false end
    if state.is_afk then
        ExitAFKMode(bot, state)
        timer.Simple(0.5, function()
            if IsValid(bot) then
                local newState = GetAFKState(bot)
                if newState then
                    local owner = nil
                    local data = GetBotData(bot)
                    if data and IsValid(data.owner) then
                        owner = data.owner
                    else
                        owner = bot:GetNWEntity("AICompanionOwnerEnt")
                    end
                    if IsValid(owner) then
                        owner._ai_last_move_time = 0
                    end
                    ExecuteAFKActionDirect(bot, owner, newState, action or "random")
                end
            end
        end)
        return true
    end
    local owner = nil
    local data = GetBotData(bot)
    if data and IsValid(data.owner) then
        owner = data.owner
    else
        owner = bot:GetNWEntity("AICompanionOwnerEnt")
    end
    if IsValid(owner) then
        owner._ai_last_move_time = 0
    end
    local actionMap = {
        sit = "sit",
        fight = "fight_zombie",
        dance = "dance",
        wait = "wait",
        point = "point",
        random = nil,
    }
    local finalAction = actionMap[action] or action
    if finalAction == nil or finalAction == "random" then
        finalAction = "wait"
    end
    ExecuteAFKActionDirect(bot, owner, state, finalAction)
    return true
end
local function ChooseRandomAction(currentAction)
    local weights = AFK_CFG.ActionWeights
    local availableActions = {}
    local totalWeight = 0
    for action, weight in pairs(weights) do
        if action ~= currentAction then
            table.insert(availableActions, { action = action, weight = weight })
            totalWeight = totalWeight + weight
        end
    end
    if #availableActions == 0 then
        for action, weight in pairs(weights) do
            table.insert(availableActions, { action = action, weight = weight })
            totalWeight = totalWeight + weight
        end
    end
    local r = math.random() * totalWeight
    local cumulative = 0
    for _, item in ipairs(availableActions) do
        cumulative = cumulative + item.weight
        if r <= cumulative then
            return item.action
        end
    end
    return "wait"
end
local function UpdateAFKForBot(bot)
    if not IsValid(bot) then return end
    if not bot:GetNWBool("IsAICompanion", false) then return end
    if not bot:Alive() then return end
    local data = GetBotData(bot)
    local owner = nil
    if data and IsValid(data.owner) then
        owner = data.owner
    else
        owner = bot:GetNWEntity("AICompanionOwnerEnt")
    end
    if not IsValid(owner) then return end
    local state = GetAFKState(bot)
    if not state then return end
    local inCombat = data and data.combat and IsValid(data.combat.target)
    local inVehicle = bot:InVehicle()
    local ownerActive = IsOwnerActive(owner)
    if ownerActive and state.is_afk then
        ExitAFKMode(bot, state)
        return
    end
    if not ownerActive and not state.is_afk then
        if not inCombat and not inVehicle then
            local firstAction = ChooseRandomAction(nil)
            ExecuteAFKActionDirect(bot, owner, state, firstAction)
            return
        end
    end
    if state.is_afk and not ownerActive then
        local now = CurTime()
        local actionFinished = false
        if state.action == "dance" then
            if state.dance_until > 0 and now >= state.dance_until then
                actionFinished = true
            end
        elseif state.action == "fight_zombie" or state.action == "fight" or string.find(state.action, "fight_") then
            if not IsValid(state.zombie) or not state.zombie:Alive() then
                actionFinished = true
                if IsValid(state.zombie) then
                    state.zombie:Remove()
                    state.zombie = nil
                end
                local botData = GetBotData(bot)
                if botData and botData.combat and IsValid(botData.combat.target) then
                    ClearCombatTarget(bot)
                end
            end
        elseif state.action == "point" then
            local pointDuration = 8
            if now - state.last_action_time > pointDuration then
                actionFinished = true
                SetBotState(bot, AC.Companion.States.IDLE)
            end
        elseif state.action == "sit" then
            if now - state.last_action_time > 45 then
                actionFinished = true
                if IsValid(state.seat) then
                    state.seat:Remove()
                    state.seat = nil
                end
                if bot:InVehicle() then
                    pcall(function() bot:ExitVehicle() end)
                end
            end
        elseif state.action == "wait" then
            if now - state.last_action_time > math.random(10, 20) then
                actionFinished = true
            end
        end
        if actionFinished or (state.next_action_time > 0 and now >= state.next_action_time) then
            local newAction = ChooseRandomAction(state.action)
            ExecuteAFKActionDirect(bot, owner, state, newAction)
        end
    end
end
hook.Add("SetupMove", "AICompanion_AFK_TrackActivity", function(ply, _, cmd)
    if not IsValid(ply) or ply:IsBot() then return end
    if cmd:GetForwardMove() ~= 0 or cmd:GetSideMove() ~= 0 or cmd:GetUpMove() ~= 0 then
        UpdateOwnerActivity(ply)
    end
    if cmd:KeyDown(IN_ATTACK) or cmd:KeyDown(IN_JUMP) or cmd:KeyDown(IN_USE) then
        UpdateOwnerActivity(ply)
    end
end)
hook.Add("EntityTakeDamage", "AICompanion_AFK_TrackDamage", function(victim)
    if not IsValid(victim) or not victim:IsPlayer() or victim:IsBot() then return end
    UpdateOwnerActivity(victim)
end)
timer.Create("AICompanion_AFK_Check", AFK_CFG.CheckInterval or 3, 0, function()
    if AC.State.Disabled then return end
    local bots = GetAllCompanions()
    for _, bot in ipairs(bots) do
        if IsValid(bot) and bot:Alive() then
            UpdateAFKForBot(bot)
        end
    end
end)
concommand.Add("ai_afk_debug", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[AI] Только администраторы!")
        end
        return
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("        AFK MODE - ДИАГНОСТИКА")
    print("═══════════════════════════════════════════════════════")
    print("")
    print("  InactivityTimeout: " .. AFK_CFG.InactivityTimeout .. " сек")
    print("  CheckInterval: " .. AFK_CFG.CheckInterval .. " сек")
    print("  ActionInterval: " .. AFK_CFG.ActionInterval.min .. "-" .. AFK_CFG.ActionInterval.max .. " сек")
    print("  ActionWeights:")
    for action, weight in pairs(AFK_CFG.ActionWeights) do
        print("    " .. action .. ": " .. weight)
    end
    print("")
    local bots = GetAllCompanions()
    if #bots == 0 then
        print("  Нет активных ботов-компаньонов")
    else
        print("  Состояние ботов:")
        for _, bot in ipairs(bots) do
            if IsValid(bot) then
                local state = GetAFKState(bot)
                if state then
                    local owner = bot:GetNWEntity("AICompanionOwnerEnt")
                    print("    " .. bot:Nick() .. " (владелец: " .. (IsValid(owner) and owner:Nick() or "?") .. ")")
                    print("      is_afk: " .. tostring(state.is_afk))
                    print("      action: " .. tostring(state.action))
                    print("      next_action_time: " .. tostring(state.next_action_time - CurTime()) .. " сек")
                    print("      action_count: " .. tostring(state.action_count))
                    if state.mob_type then
                        print("      mob_type: " .. tostring(state.mob_type))
                    end
                end
            end
        end
    end
    print("")
    print("═══════════════════════════════════════════════════════")
    print("")
end)
print("[AI AFK] Загружен (циклические случайные действия, расширенный бестиарий)")