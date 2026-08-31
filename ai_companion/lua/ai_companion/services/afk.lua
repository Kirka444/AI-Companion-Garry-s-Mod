
local AFK = {}

function AFK:new(utils, config, state, botmanager, spawn, commands, shared)
    local obj = {

        utils = utils,
        config = config,
        state = state,
        botmanager = botmanager,
        spawn = spawn,
        commands = commands,
        shared = shared,

        _initialized = false,
        _afkState = {},
        _cfg = nil,
        _isEnabled = true,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function AFK:init()
    if self._initialized then return end

    if not SERVER then
        if self.utils then
            self.utils.LogInfo("AFK", "AFK сервис работает только на сервере")
        end
        self._initialized = true
        return
    end

    if game.SinglePlayer() then
        if self.utils then
            self.utils.LogInfo("AFK", "AFK отключена в одиночном режиме")
        end
        self._initialized = true
        return
    end

    self:_LoadConfig()

    self:_LoadState()

    self:SetupHooks()

    self:SetupTimer()

    self:SetupCommands()

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("AFK", "AFK сервис инициализирован (включён: %s)", tostring(self._isEnabled))
    end
end

function AFK:_LoadConfig()

    local defaultCfg = {
        InactivityTimeout = 60,
        CheckInterval = 20,
        ActionInterval = {
            min = 50,
            max = 60,
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
            dance = 15,
            point = 10,
        },
        ZombieLifetime = 15,
        DanceDuration = 5,
        SpawnDistance = {
            default = 150,
            npc_combine_s = 150,
            npc_metropolice = 150,
            npc_zombine = 150,
            npc_poisonzombie = 150,
            npc_fastzombie = 150,
            npc_zombie = 150,
        },
        ChairHeight = 18,
    }

    if self.config then
        local magic = self.config:get("Magic") or {}
        if magic.AFK then
            self._cfg = magic.AFK
        else
            self._cfg = defaultCfg
        end
    else
        self._cfg = defaultCfg
    end

    self._cfg = self:MergeTables(defaultCfg, self._cfg)
end

function AFK:MergeTables(default, custom)
    local result = {}
    for k, v in pairs(default) do
        if custom[k] ~= nil then
            if type(v) == "table" and type(custom[k]) == "table" then
                result[k] = self:MergeTables(v, custom[k])
            else
                result[k] = custom[k]
            end
        else
            result[k] = v
        end
    end

    for k, v in pairs(custom) do
        if result[k] == nil then
            result[k] = v
        end
    end
    return result
end

function AFK:_LoadState()
    if self.state then
        local raw = self.state:getRaw("AFK")
        if raw and raw.Enabled ~= nil then
            self._isEnabled = raw.Enabled
        end
    end
end

function AFK:_SaveState()
    if self.state then
        local raw = self.state:getRaw("AFK") or {}
        raw.Enabled = self._isEnabled
        self.state:setRaw("AFK", raw)
    end
end

function AFK:IsEnabled()
    return self._isEnabled
end

function AFK:SetEnabled(enabled)
    self._isEnabled = enabled
    self:_SaveState()

    if not enabled then

        local allBots = self:GetAllBots()
        for _, bot in ipairs(allBots) do
            if self:IsValid(bot) then
                local state = self:GetAFKState(bot)
                if state and state.is_afk then
                    self:ExitAFKMode(bot, state)
                end
            end
        end
    end

    if self.utils then
        self.utils.LogInfo("AFK", "AFK система %s", enabled and "включена" or "выключена")
    end
end

function AFK:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function AFK:SafeGetClass(ent)
    if not self:IsValid(ent) then return "invalid" end
    local ok, class = pcall(function() return ent:GetClass() end)
    return (ok and class) or "error"
end

function AFK:SafeGetPos(ent)
    if not self:IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:GetPos() end)
    return (ok and pos) or Vector()
end

function AFK:SafeAlive(ent)
    if not self:IsValid(ent) then return false end
    local ok, alive = pcall(function() return ent:Alive() end)
    return ok and alive
end

function AFK:GetAllBots()
    if self.botmanager then
        return self.botmanager:GetAllBots() or {}
    end
    return {}
end

function AFK:GetBotData(bot)
    if not self:IsValid(bot) then return nil end
    if self.botmanager then
        return self.botmanager:GetData(bot)
    end
    return nil
end

function AFK:GetBotOwner(bot)
    if not self:IsValid(bot) then return nil end
    if self.botmanager then
        return self.botmanager:GetOwner(bot)
    end
    return nil
end

function AFK:SetBotState(bot, state)
    if not self:IsValid(bot) then return end
    if self.botmanager then
        return self.botmanager:SetBotState(bot, state)
    end
end

function AFK:UpdateBotData(bot, data)
    if not self:IsValid(bot) then return end
    if self.botmanager then
        return self.botmanager:UpdateData(bot, data)
    end
end

function AFK:ClearCombatTarget(bot)
    if not self:IsValid(bot) then return end
    local data = self:GetBotData(bot)
    if data and data.combat then
        data.combat.target = nil
        data.combat.target_type = nil
        data.combat.triggered_by = nil
        self:UpdateBotData(bot, data)
    end
end

function AFK:GetBotCombatWeapon(bot)
    if not self:IsValid(bot) then return "weapon_smg1" end
    local data = self:GetBotData(bot)
    if data and data.config and data.config.combat_weapon then
        return data.config.combat_weapon
    end
    return "weapon_smg1"
end

function AFK:SendAIMessage(ply, msg)
    if not self:IsValid(ply) or not SERVER then return end

    local prefixColor = Color(255, 200, 0)
    local cleanPrefix = "AI"

    if self.shared then
        self.shared:SendChatMessage(ply, msg, prefixColor, cleanPrefix, ply:Nick(), false)
    end
end

function AFK:GetAFKState(bot)
    if not self:IsValid(bot) then return nil end

    local id = bot:EntIndex()
    if not self._afkState[id] then
        self._afkState[id] = {
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
    return self._afkState[id]
end

function AFK:GetAFKStateRaw(bot)
    if not self:IsValid(bot) then return nil end
    local id = bot:EntIndex()
    return self._afkState[id]
end

function AFK:UpdateOwnerActivity(owner)
    if not self:IsValid(owner) then return end
    owner._ai_last_move_time = CurTime()
end

function AFK:IsOwnerActive(owner)
    if not self:IsValid(owner) then return false end
    local lastMove = owner._ai_last_move_time or 0
    return CurTime() - lastMove < self._cfg.InactivityTimeout
end

function AFK:SpawnChairDirect(bot)
    if not self:IsValid(bot) then return nil end

    local cfg = self._cfg
    local botPos = self:SafeGetPos(bot)
    local forward = bot:GetForward()
    local distance = 80
    local pos = botPos + forward * distance + Vector(0, 0, 10)

    local hullTr = util.TraceHull({
        start = pos + Vector(0, 0, 36),
        endpos = pos + Vector(0, 0, 36),
        mins = Vector(-20, -20, 0),
        maxs = Vector(20, 20, 72),
        filter = {bot}
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
                filter = {bot}
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
                        filter = {bot}
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
        filter = {bot},
        mask = MASK_PLAYERSOLID
    })
    if downTrace.Hit then
        pos = downTrace.HitPos + Vector(0, 0, cfg.ChairHeight)
    else
        pos = Vector(pos.x, pos.y, botPos.z + cfg.ChairHeight)
    end

    local finalCheck = util.TraceHull({
        start = pos + Vector(0, 0, 36),
        endpos = pos + Vector(0, 0, 36),
        mins = Vector(-18, -18, 0),
        maxs = Vector(18, 18, 70),
        filter = {bot}
    })
    if finalCheck.Hit then
        pos = botPos + forward * 200 + Vector(0, 0, 10)
        local downTrace2 = util.TraceLine({
            start = pos + Vector(0, 0, 100),
            endpos = pos - Vector(0, 0, 200),
            filter = {bot},
            mask = MASK_PLAYERSOLID
        })
        if downTrace2.Hit then
            pos = downTrace2.HitPos + Vector(0, 0, cfg.ChairHeight)
        end
    end

    local chair = ents.Create("prop_vehicle_prisoner_pod")
    if not self:IsValid(chair) then return nil end

    chair:SetModel("models/props_c17/chair02a.mdl")
    chair:SetPos(pos)
    chair:Spawn()
    chair:Activate()

    timer.Simple(0.05, function()
        if self:IsValid(chair) then
            local phys = chair:GetPhysicsObject()
            if self:IsValid(phys) then
                pcall(function()
                    phys:EnableMotion(false)
                end)
            end
        end
    end)

    return chair
end

function AFK:SpawnMobDirect(bot, mobType)
    if not self:IsValid(bot) then return nil end

    if not mobType or mobType == "zombie" or mobType == "fight_zombie" then
        mobType = "npc_zombie"
    end

    local cfg = self._cfg
    local spawnDist = cfg.SpawnDistance[mobType] or cfg.SpawnDistance.default or 150
    local botAngles = bot:EyeAngles()
    local backward = botAngles:Forward() * -1
    local pos = self:SafeGetPos(bot) + backward * spawnDist + Vector(0, 0, 10)

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
            local testPos = self:SafeGetPos(bot) + offset + Vector(0, 0, 10)
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
    if not self:IsValid(mob) then return nil end

    mob:SetPos(pos)

    local toBot = self:SafeGetPos(bot) - pos
    toBot.z = 0
    if toBot:LengthSqr() > 0.001 then
        toBot:Normalize()
        mob:SetAngles(toBot:Angle())
    end

    local health = 100
    if mobType == "npc_combine_s" or mobType == "npc_metropolice" then
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

function AFK:ExecuteAFKAction(bot, owner, state, action)
    if not self:IsValid(bot) or not state then return end

    if action ~= "fight_zombie" and not string.find(action, "fight_") and self:IsValid(state.zombie) then
        state.zombie:Remove()
        state.zombie = nil
    end

    if action ~= "sit" and self:IsValid(state.seat) then
        state.seat:Remove()
        state.seat = nil
    end

    state.exit_attempts = 0

    if bot:InVehicle() then
        pcall(function() bot:ExitVehicle() end)
    end

    local data = self:GetBotData(bot)
    if data and data.combat and self:IsValid(data.combat.target) then
        if not (self:IsValid(state.zombie) and data.combat.target == state.zombie) then
            self:ClearCombatTarget(bot)
        end
    end

    state.is_afk = true
    state.action = action
    state.dance_until = 0

    if action == "sit" then
        local chair = self:SpawnChairDirect(bot)
        if self:IsValid(chair) then
            state.seat = chair

            timer.Simple(0.5, function()
                if self:IsValid(bot) and self:IsValid(chair) then
                    local phys = chair:GetPhysicsObject()
                    if self:IsValid(phys) then
                        pcall(function()
                            phys:EnableMotion(false)
                        end)
                    end

                    local success = pcall(function()
                        bot:EnterVehicle(chair)
                    end)

                    if not success or not bot:InVehicle() then
                        timer.Simple(0.3, function()
                            if self:IsValid(bot) and self:IsValid(chair) then
                                local success2 = pcall(function()
                                    bot:EnterVehicle(chair)
                                end)
                                if not success2 or not bot:InVehicle() then
                                    if self:IsValid(chair) then
                                        chair:Remove()
                                        state.seat = nil
                                    end
                                    state.action = "wait"
                                end
                            end
                        end)
                    end
                else
                    if self:IsValid(chair) then
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
        end

        if self:IsValid(state.zombie) and self:SafeAlive(state.zombie) then
            return
        end

        if self:IsValid(state.zombie) then
            state.zombie:Remove()
            state.zombie = nil
        end

        local mob = self:SpawnMobDirect(bot, mobType)
        if self:IsValid(mob) then
            state.zombie = mob
            state.mob_type = mobType

            timer.Simple(0.5, function()
                if self:IsValid(bot) and self:IsValid(mob) and self:SafeAlive(mob) then

                    local data = self:GetBotData(bot)
                    if data then
                        if not data.combat then data.combat = {} end
                        data.combat.target = mob
                        data.combat.target_type = "npc"
                        data.combat.triggered_by = "afk"
                        data.combat.last_attack_time = CurTime()
                        self:UpdateBotData(bot, data)
                    end

                    local states = self.state and self.state:GetStates() or {}
                    self:SetBotState(bot, states.COMBAT or "combat")

                    local combatWep = self:GetBotCombatWeapon(bot)
                    if not bot:HasWeapon(combatWep) then
                        pcall(function() bot:Give(combatWep) end)
                    end
                    bot:SelectWeapon(combatWep)
                else
                    if self:IsValid(mob) then
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
                    if self.utils then
                        self.utils.LogDebug("AFK", "Ошибка анимации: %s", tostring(err))
                    end
                    state.action = "wait"
                    return
                end
            )
        else
            state.action = "wait"
            return
        end

        state.dance_until = CurTime() + self._cfg.DanceDuration

    elseif action == "point" then
        local data = self:GetBotData(bot)
        if data then
            data.point = data.point or {}
            data.point.pos = self:SafeGetPos(bot) + bot:GetForward() * 500
            data.point.angle = bot:EyeAngles()
            self:UpdateBotData(bot, data)
        end

        local states = self.state and self.state:GetStates() or {}
        self:SetBotState(bot, states.POINTING or "pointing")

        if self:IsValid(bot) then
            bot:ChatPrint("[AI] Указываю направление.")
        end

    else
        state.action = "wait"
        if self:IsValid(bot) then
            local states = self.state and self.state:GetStates() or {}
            self:SetBotState(bot, states.IDLE or "idle")
            pcall(function() bot:SetLocalVelocity(Vector(0, 0, 0)) end)
        end
    end

    state.last_action_time = CurTime()
    state.action_count = (state.action_count or 0) + 1

    local interval = math.random(self._cfg.ActionInterval.min, self._cfg.ActionInterval.max)
    state.next_action_time = CurTime() + interval
end

function AFK:ExitAFKMode(bot, state)
    if not self:IsValid(bot) or not state or not state.is_afk then return end

    if self.commands then
        self.commands:FindOwnedBot(bot)

        if self.commands.ExecuteCommand then
            self.commands:ExecuteCommand(bot, "standup", "")
        end
    end

    if self:IsValid(state.seat) then
        state.seat:Remove()
        state.seat = nil
    end

    if self:IsValid(state.zombie) then
        state.zombie:Remove()
        state.zombie = nil
    end

    local data = self:GetBotData(bot)
    if data and data.combat and self:IsValid(data.combat.target) then
        self:ClearCombatTarget(bot)
    end

    timer.Simple(0.5, function()
        if self:IsValid(bot) then
            if bot:InVehicle() then
                pcall(function() bot:ExitVehicle() end)
                timer.Simple(0.3, function()
                    if self:IsValid(bot) and bot:InVehicle() then
                        pcall(function() bot:ExitVehicle() end)
                        bot:SetPos(self:SafeGetPos(bot) + Vector(0, 0, 10))
                    end
                    if self:IsValid(bot) then
                        bot:RemoveFlags(FL_DUCKING)
                        bot:RemoveFlags(FL_ANIMDUCKING)
                        pcall(function() bot:ConCommand("-duck") end)
                    end
                end)
            end
        end
    end)

    timer.Simple(0.2, function()
        if self:IsValid(bot) then
            local states = self.state and self.state:GetStates() or {}
            self:SetBotState(bot, states.FOLLOW or "following")
        end
    end)

    state.is_afk = false
    state.action = nil
    state.dance_until = 0
    state.exit_attempts = 0
    state.next_action_time = 0
    state.last_action_time = 0
end

function AFK:ForceAFKMode(bot, action)
    if not self:IsValid(bot) then return false end

    local state = self:GetAFKState(bot)
    if not state then return false end

    if state.is_afk then
        self:ExitAFKMode(bot, state)
        timer.Simple(0.5, function()
            if self:IsValid(bot) then
                local newState = self:GetAFKState(bot)
                if newState then
                    local owner = self:GetBotOwner(bot)
                    if not self:IsValid(owner) then
                        owner = bot:GetNWEntity("AICompanionOwnerEnt")
                    end
                    if self:IsValid(owner) then
                        owner._ai_last_move_time = 0
                    end
                    self:ExecuteAFKAction(bot, owner, newState, action or "random")
                end
            end
        end)
        return true
    end

    local owner = self:GetBotOwner(bot)
    if not self:IsValid(owner) then
        owner = bot:GetNWEntity("AICompanionOwnerEnt")
    end

    if self:IsValid(owner) then
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

    self:ExecuteAFKAction(bot, owner, state, finalAction)
    return true
end

function AFK:ChooseRandomAction(currentAction)
    local weights = self._cfg.ActionWeights
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

function AFK:UpdateAFKForBot(bot)
    if not self:IsValid(bot) then return end
    if not bot:GetNWBool("IsAICompanion", false) then return end
    if not self:SafeAlive(bot) then return end

    if not self._isEnabled then
        local state = self:GetAFKState(bot)
        if state and state.is_afk then
            self:ExitAFKMode(bot, state)
        end
        return
    end

    local owner = self:GetBotOwner(bot)
    if not self:IsValid(owner) then
        owner = bot:GetNWEntity("AICompanionOwnerEnt")
    end
    if not self:IsValid(owner) then return end

    local data = self:GetBotData(bot)
    local state = self:GetAFKState(bot)
    if not state then return end

    local inCombat = data and data.combat and self:IsValid(data.combat.target)
    local inVehicle = bot:InVehicle()
    local ownerActive = self:IsOwnerActive(owner)

    if ownerActive and state.is_afk then
        self:ExitAFKMode(bot, state)
        return
    end

    if not ownerActive and not state.is_afk then
        if not inCombat and not inVehicle then
            local firstAction = self:ChooseRandomAction(nil)
            self:ExecuteAFKAction(bot, owner, state, firstAction)
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

        elseif state.action == "fight_zombie" or state.action == "fight" or string.find(state.action or "", "fight_") then
            if not self:IsValid(state.zombie) or not self:SafeAlive(state.zombie) then
                actionFinished = true
                if self:IsValid(state.zombie) then
                    state.zombie:Remove()
                    state.zombie = nil
                end
                local botData = self:GetBotData(bot)
                if botData and botData.combat and self:IsValid(botData.combat.target) then
                    self:ClearCombatTarget(bot)
                end
            end

        elseif state.action == "point" then
            local pointDuration = 8
            if now - state.last_action_time > pointDuration then
                actionFinished = true
                local states = self.state and self.state:GetStates() or {}
                self:SetBotState(bot, states.IDLE or "idle")
            end

        elseif state.action == "sit" then
            if now - state.last_action_time > 45 then
                actionFinished = true
                if self:IsValid(state.seat) then
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
            local newAction = self:ChooseRandomAction(state.action)
            self:ExecuteAFKAction(bot, owner, state, newAction)
        end
    end
end

function AFK:SetupHooks()
    if not SERVER then return end

    local selfRef = self

    hook.Add("SetupMove", "AICompanion_AFK_TrackActivity", function(ply, _, cmd)
        if not selfRef:IsValid(ply) or ply:IsBot() then return end

        if cmd:GetForwardMove() ~= 0 or cmd:GetSideMove() ~= 0 or cmd:GetUpMove() ~= 0 then
            selfRef:UpdateOwnerActivity(ply)
        end

        if cmd:KeyDown(IN_ATTACK) or cmd:KeyDown(IN_JUMP) or cmd:KeyDown(IN_USE) then
            selfRef:UpdateOwnerActivity(ply)
        end
    end)

    hook.Add("EntityTakeDamage", "AICompanion_AFK_TrackDamage", function(victim)
        if not selfRef:IsValid(victim) or not victim:IsPlayer() or victim:IsBot() then return end
        selfRef:UpdateOwnerActivity(victim)
    end)

    hook.Add("SetupMove", "AICompanion_AFK_CheckDisabled", function(ply, _, cmd)
        if not selfRef:IsValid(ply) or not ply:IsBot() then return end
        if not ply:GetNWBool("IsAICompanion", false) then return end

        if selfRef.state and selfRef.state:getState("Disabled") then
            local state = selfRef:GetAFKState(ply)
            if state and state.is_afk then
                selfRef:ExitAFKMode(ply, state)
            end
        end
    end)
end

function AFK:SetupTimer()
    if not SERVER then return end

    local selfRef = self
    local checkInterval = self._cfg.CheckInterval or 10

    timer.Create("AICompanion_AFK_Check", checkInterval, 0, function()

        if selfRef.state and selfRef.state:getState("Disabled") then
            return
        end

        local allBots = selfRef:GetAllBots()
        for _, bot in ipairs(allBots) do
            if selfRef:IsValid(bot) and selfRef:SafeAlive(bot) then
                selfRef:UpdateAFKForBot(bot)
            end
        end
    end)

    if self.utils then
        self.utils.LogInfo("AFK", "Таймер проверки запущен (интервал: %d сек)", checkInterval)
    end
end

function AFK:SetupCommands()
    if not SERVER then return end

    local selfRef = self

    concommand.Add("ai_companion_afk_toggle", function(ply)
        if not selfRef:IsValid(ply) then return end
        if not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы могут использовать эту команду!")
            return
        end

        local newState = not selfRef._isEnabled
        selfRef:SetEnabled(newState)

        ply:ChatPrint("[AI] AFK система " .. (newState and "ВКЛЮЧЕНА" or "ВЫКЛЮЧЕНА"))
    end)

    concommand.Add("ai_companion_force_afk", function(ply, cmd, args)
        if not selfRef:IsValid(ply) then return end
        if not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы могут использовать эту команду!")
            return
        end

        local action = args[1] or "random"
        local target = nil

        if args[2] then
            local searchName = string.lower(args[2])
            for _, p in ipairs(player.GetAll()) do
                if selfRef:IsValid(p) and p:IsBot() and p:GetNWBool("IsAICompanion", false) then
                    local nick = string.lower(p:Nick())
                    if string.find(nick, searchName) then
                        target = p
                        break
                    end
                end
            end
        end

        if not selfRef:IsValid(target) then

            target = nil
            if selfRef.botmanager then
                target = selfRef.botmanager:GetBotByOwner(ply)
            end
        end

        if not selfRef:IsValid(target) then
            ply:ChatPrint("[AI] Бот не найден!")
            return
        end

        if selfRef:ForceAFKMode(target, action) then
            ply:ChatPrint("[AI] AFK режим включён для " .. target:Nick() .. " (действие: " .. action .. ")")
        else
            ply:ChatPrint("[AI] Не удалось включить AFK режим")
        end
    end)

    concommand.Add("ai_companion_afk_status", function(ply)
        if not selfRef:IsValid(ply) then return end
        if not ply:IsAdmin() then
            ply:ChatPrint("[AI] Только администраторы могут использовать эту команду!")
            return
        end

        local allBots = selfRef:GetAllBots()
        local afkCount = 0
        local totalCount = #allBots

        for _, bot in ipairs(allBots) do
            if selfRef:IsValid(bot) then
                local state = selfRef:GetAFKState(bot)
                if state and state.is_afk then
                    afkCount = afkCount + 1
                end
            end
        end

        ply:ChatPrint("[AI] === СТАТУС AFK ===")
        ply:ChatPrint("[AI] Система: " .. (selfRef._isEnabled and "ВКЛЮЧЕНА" or "ВЫКЛЮЧЕНА"))
        ply:ChatPrint("[AI] Ботов в AFK: " .. afkCount .. " из " .. totalCount)
        ply:ChatPrint("[AI] Таймаут неактивности: " .. selfRef._cfg.InactivityTimeout .. " сек")
    end)
end

function AFK:GetAPI()
    return {
        IsEnabled = function() return self:IsEnabled() end,
        SetEnabled = function(enabled) return self:SetEnabled(enabled) end,
        ForceAFK = function(bot, action) return self:ForceAFKMode(bot, action) end,
        ExitAFK = function(bot) return self:ExitAFKMode(bot, self:GetAFKState(bot)) end,
        GetAFKState = function(bot) return self:GetAFKState(bot) end,
        IsOwnerActive = function(owner) return self:IsOwnerActive(owner) end,
        GetConfig = function() return self._cfg end,
    }
end

return AFK
