
local Movement = {}

function Movement:new(utils, config, state, data, botmanager)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        data = data,
        botmanager = botmanager,
        _initialized = false,
        _botCache = {},
        _constants = nil,

        constants = nil,
        navmesh = nil,
        path = nil,
        doors = nil,
        stuck = nil,
        navigation = nil,
        utils_movement = nil,
        stealth = nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Movement:init()
    if self._initialized then return end

    local Constants = include("ai_companion/services/movement/constants.lua")
    self.constants = Constants:new(self.config)
    self._constants = self.constants:get()

    local UtilsMovement = include("ai_companion/services/movement/utils.lua")
    self.utils_movement = UtilsMovement:new(self.utils)

    local NavMesh = include("ai_companion/services/movement/navmesh.lua")
    self.navmesh = NavMesh:new(self.utils_movement, self.constants)

    local Path = include("ai_companion/services/movement/path.lua")
    self.path = Path:new(self.utils_movement, self.constants, self.navmesh)

    local Doors = include("ai_companion/services/movement/doors.lua")
    self.doors = Doors:new(self.utils_movement, self.constants)

    local Stuck = include("ai_companion/services/movement/stuck.lua")
    self.stuck = Stuck:new(self.utils_movement, self.constants, self.navmesh)

    local Stealth = include("ai_companion/services/movement/stealth.lua")
    self.stealth = Stealth:new(self.utils_movement, self.constants)
    self.stealth.data = self.data

    local Navigation = include("ai_companion/services/movement/navigation.lua")
    self.navigation = Navigation:new(
        self.utils_movement, self.constants, self.navmesh, self.path, self.doors, self.stuck, self.stealth
    )
    self.navigation.data = self.data

    if SERVER then
        self:SetupHooks()
    end

    if self.navigation then
        local navAvailable = self.navigation:IsNavMeshAvailable()
        if self.utils then
            self.utils.LogInfo("Movement", "NavMesh доступен: %s", tostring(navAvailable))
            if not navAvailable then
                self.utils.LogInfo("Movement", "Используется режим прямой навигации (без NavMesh)")
            end
        end
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Movement", "Сервис движения инициализирован")
    end
end

function Movement:MoveToTarget(bot, cmd, targetPos, moveTarget)
    if not self:IsValid(bot) or not cmd then return end
    self.navigation:UpdateNavigation(bot, cmd, targetPos, moveTarget)
end

function Movement:IsValid(ent)
    return self.utils and self.utils:IsValid(ent) or (ent and ent.IsValid and ent:IsValid())
end

function Movement:GetNavState(bot)
    if not self:IsValid(bot) then return nil end
    local data = self.data and self.data:GetBotData(bot)
    if not data then return nil end
    return self.navigation:GetNavState(bot, data)
end

function Movement:TeleportToTarget(bot, targetPos, moveTarget, st)
    return self.navigation:TeleportToTarget(bot, targetPos, moveTarget, st)
end

function Movement:InvalidateBotCache(bot)
    if not self:IsValid(bot) then return end
    self._botCache[bot:EntIndex()] = nil
end

function Movement:IsNavMeshAvailable()
    if not self.navigation then return false end
    return self.navigation:IsNavMeshAvailable()
end

function Movement:GetNavigationMode()
    if not self.navigation then return "unknown" end
    return self.navigation:IsNavMeshAvailable() and "navmesh" or "direct"
end

function Movement:IsStealthActive(bot)
    if not self:IsValid(bot) then return false end
    if not self.stealth then return false end
    return self.stealth:IsActive(bot)
end

function Movement:GetStealthState(bot)
    if not self:IsValid(bot) then return { active = false, crouching = false, speed = 0 } end
    if not self.stealth then return { active = false, crouching = false, speed = 0 } end
    return self.stealth:GetState(bot)
end

function Movement:SetStealthEnabled(bot, enable)
    if not self:IsValid(bot) then return end
    if not self.stealth then return end
    self.stealth:SetEnabled(bot, enable)
end
function Movement:ComeBackToPlayer(bot)
    if not self:IsValid(bot) then return end

    local owner = nil
    if self.botmanager then
        owner = self.botmanager:GetOwner(bot)
    end

    if not self:IsValid(owner) then
        local data = self.data and self.data:GetBotData(bot)
        owner = data and data.owner
    end

    if not self:IsValid(owner) then return end
    self:MoveToTarget(bot, nil, owner:GetPos(), owner)
end

function Movement:IsPassenger(bot)
    if not self:IsValid(bot) then return false end
    return bot:InVehicle() or bot:GetNWBool("IsPassenger", false)
end

function Movement:GetAPI()
    return {
        MoveToTarget = function(bot, cmd, targetPos, moveTarget)
            return self:MoveToTarget(bot, cmd, targetPos, moveTarget)
        end,
        GetNavState = function(bot) return self:GetNavState(bot) end,
        TeleportToTarget = function(bot, targetPos, moveTarget, st)
            return self:TeleportToTarget(bot, targetPos, moveTarget, st)
        end,
        IsValid = function(ent) return self:IsValid(ent) end,
        InvalidateBotCache = function(bot) return self:InvalidateBotCache(bot) end,
        GetBotCache = function(bot) return self:GetBotCache(bot) end,
        IsNavMeshAvailable = function() return self:IsNavMeshAvailable() end,
        GetNavigationMode = function() return self:GetNavigationMode() end,
        IsStealthActive = function(bot) return self:IsStealthActive(bot) end,
        GetStealthState = function(bot) return self:GetStealthState(bot) end,
        SetStealthEnabled = function(bot, enable) return self:SetStealthEnabled(bot, enable) end,

        ComeBackToPlayer = function(bot) return self:ComeBackToPlayer(bot) end,
        IsPassenger = function(bot) return self:IsPassenger(bot) end,
    }
end

function Movement:GetBotCache(bot)
    if not self:IsValid(bot) then return nil end
    local botID = bot:EntIndex()
    local cache = self._botCache[botID]
    local now = CurTime()
    if cache and (now - cache.time) < 0.1 then
        return cache
    end

    local data = nil
    local owner = nil

    if self.botmanager then
        data = self.botmanager:GetData(bot)
        if data then
            owner = data.owner
        end
    end

    if not data then
        data = self.data and self.data:GetBotData(bot)
        if data then
            owner = data.owner
        end
    end

    if not self:IsValid(owner) then
        owner = bot:GetNWEntity("AICompanionOwnerEnt")
    end

    cache = {
        data = data,
        owner = owner,
        stealthMode = bot:GetNWBool("AI_StealthMode", false),
        isInCombat = data and data.combat and self:IsValid(data.combat.target),
        time = now,
    }
    self._botCache[botID] = cache
    return cache
end

function Movement:ShouldProcessMovement(bot)
    if not self:IsValid(bot) then return false end
    if not bot:Alive() then return false end

    local isCompanion = bot:GetNWBool("IsAICompanion", false)
    if not isCompanion and self.botmanager then
        local data = self.botmanager:GetData(bot)
        if data then
            isCompanion = true
            bot:SetNWBool("IsAICompanion", true)
            if data.owner then
                bot:SetNWEntity("AICompanionOwnerEnt", data.owner)
                bot:SetNWString("AICompanionOwner", data.owner:Nick())
            end
        end
    end

    if not isCompanion then return false end
    if not bot:IsBot() then return false end
    return true
end

function Movement:ProcessMovement(bot, cmd)
    local ctx = self:GetBotCache(bot)
    if not ctx then return end

    local data = ctx.data
    local owner = ctx.owner
    local stealthMode = ctx.stealthMode
    local isInCombat = ctx.isInCombat
    if data and data.combat then
        local hadTarget = data.combat._had_target
        local hasTargetNow = self:IsValid(data.combat.target)

        if hadTarget and not hasTargetNow then
            local idleWep = self.data:GetBotIdleWeapon(bot)
            if bot:HasWeapon(idleWep) then
                bot:SelectWeapon(idleWep)
            else

                self:SafeGiveWeapon(bot, idleWep, "weapon_physgun")
                timer.Simple(0.1, function()
                    if self:IsValid(bot) and bot:HasWeapon(idleWep) then
                        bot:SelectWeapon(idleWep)
                    end
                end)
            end
        end

        data.combat._had_target = hasTargetNow
    end

    local needStealthCrouch = false
    if stealthMode and self:IsValid(owner) and owner:IsPlayer() and owner:Alive() then
        local ok1, crouching = pcall(function() return owner:Crouching() end)
        local ok2, ducking = pcall(function() return owner:KeyDown(IN_DUCK) end)
        if (ok1 and crouching) or (ok2 and ducking) then
            needStealthCrouch = true
        end
    end

    if not stealthMode then
        bot:RemoveFlags(FL_DUCKING)
        bot:RemoveFlags(FL_ANIMDUCKING)
        cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_DUCK)))
    end

    bot._aiStealthCrouch = needStealthCrouch and not isInCombat

    local moveTarget = isInCombat and data.combat.target or owner
    if not moveTarget then
        local nearest = self.utils_movement:GetNearestHuman(bot)
        if self:IsValid(nearest) then moveTarget = nearest end
    end

    local targetIsNoclip = self:IsValid(moveTarget) and moveTarget:IsPlayer() and self.utils_movement:IsTargetNoclip(moveTarget)
    if targetIsNoclip then
        self.utils_movement:ClearDuckFlags(bot)
    end

    if not targetIsNoclip then
        if needStealthCrouch and not isInCombat then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK))
            bot:AddFlags(FL_DUCKING)
            bot:AddFlags(FL_ANIMDUCKING)
        else
            if bot:Crouching() or bit.band(bot:GetFlags(), FL_DUCKING) ~= 0 then
                local pos = bot:GetPos()
                local standCheck = util.TraceHull({
                    start = pos + Vector(0, 0, 8),
                    endpos = pos + Vector(0, 0, 8),
                    mins = Vector(-16, -16, 0),
                    maxs = Vector(16, 16, 72),
                    filter = bot,
                    mask = MASK_PLAYERSOLID
                })
                if not standCheck.Hit then
                    cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_DUCK)))
                    bot:RemoveFlags(FL_DUCKING)
                    bot:RemoveFlags(FL_ANIMDUCKING)
                else
                    cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK))
                end
            end
        end
    end

    local inVehicle = bot:InVehicle()
    if inVehicle then
        local st = self:GetNavState(bot)
        if st then
            st.path = nil
            st.index = 1
        end
        cmd:ClearMovement()
        if self._vehicle then
            local ok, veh = pcall(function() return bot:GetVehicle() end)
            if ok and self:IsValid(veh) then
                pcall(function()
                    self._vehicle:ControlVehicle(bot, veh, owner, cmd)
                end)
            end
        end
        return
    end

    if self:IsValid(owner) and owner:InVehicle() and not bot:InVehicle() and not isInCombat then
        local ownerVeh = nil
        pcall(function() ownerVeh = owner:GetVehicle() end)
        if self:IsValid(ownerVeh) and self._vehicle then
            local root = self._vehicle:GetGlideRoot(ownerVeh) or ownerVeh
            if self:IsValid(root) then
                local driverSeat = self._vehicle:GetDriverSeat(root)
                if self:IsValid(driverSeat) then
                    local driver = nil
                    pcall(function() driver = driverSeat:GetDriver() end)
                    if not self:IsValid(driver) then
                        pcall(function() bot:EnterVehicle(driverSeat) end)
                        if bot:InVehicle() then
                            if data then
                                data.vehicle.locked_vehicle = root
                                data.vehicle.locked_seat = driverSeat
                                data.vehicle.is_driver = true
                                data.vehicle.sit_by_command = false
                                self.data:SetBotData(bot, data)
                            end
                            if bot.ChatPrint then
                                bot:ChatPrint("[AI] Сажусь за руль!")
                            end
                        end
                    end
                end
            end
        end
    end

    local states = self.state and self.state:GetStates() or {}
    local botState = data and data.state or "idle"
    local isPointing = (botState == states.POINTING)
    local isIdle = (botState == states.IDLE)

    if isIdle and not isInCombat then
        cmd:ClearMovement()
        cmd:ClearButtons()
        local lookTarget = owner or moveTarget or bot
        local lookAng = self.utils_movement:GetLookAngle(bot, lookTarget)
        cmd:SetViewAngles(lookAng)
        bot:SetEyeAngles(lookAng)
        return
    end

    if isPointing then
        cmd:ClearMovement()
        cmd:ClearButtons()
        if data and data.point and data.point.angle then
            cmd:SetViewAngles(data.point.angle)
            bot:SetEyeAngles(data.point.angle)
        else
            local lookTarget = owner or moveTarget or bot
            local lookAng = self.utils_movement:GetLookAngle(bot, lookTarget)
            cmd:SetViewAngles(lookAng)
            bot:SetEyeAngles(lookAng)
        end
        return
    end

    if not moveTarget then
        cmd:ClearMovement()
        cmd:ClearButtons()
        local nearest = self.utils_movement:GetNearestHuman(bot)
        if self:IsValid(nearest) then
            local lookAng = self.utils_movement:GetLookAngle(bot, nearest)
            cmd:SetViewAngles(lookAng)
            bot:SetEyeAngles(lookAng)
        end
        return
    end

    local const = self._constants
    local targetPos = self.utils_movement:GetTargetPos(moveTarget, bot, const) or bot:GetPos()
    local botPos = bot:GetPos()

    if isInCombat then
        local locator = _G.AI_GetLocator()
        local combat = locator:get("combat")
        local handled = combat:HandleCombat(bot, cmd)
        if handled then
            local btns = cmd:GetButtons()
            cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
            bot:RemoveFlags(FL_DUCKING)
            bot:RemoveFlags(FL_ANIMDUCKING)
            bot._aiStealthCrouch = false
            return
        end
        local data2 = self.data and self.data:GetBotData(bot)
        if data2 and data2.combat and self:IsValid(data2.combat.target) then
            local btns = cmd:GetButtons()
            cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
            bot:RemoveFlags(FL_DUCKING)
            bot:RemoveFlags(FL_ANIMDUCKING)
            bot._aiStealthCrouch = false
            return
        end
        moveTarget = owner
        if not moveTarget then
            cmd:ClearMovement()
            cmd:ClearButtons()
            return
        end
        targetPos = self.utils_movement:GetTargetPos(moveTarget, bot, const) or botPos
    end

    if self:IsValid(moveTarget) then
        local distToTarget = botPos:DistToSqr(targetPos)
        if distToTarget > const.teleportDist * const.teleportDist then
            local st = self:GetNavState(bot)
            if self:TeleportToTarget(bot, targetPos, moveTarget, st) then return end
        end
    end

    self.navigation:UpdateNavigation(bot, cmd, targetPos, moveTarget)
end

function Movement:SetupHooks()
    if not SERVER then return end

    local selfRef = self

    hook.Add("StartCommand", "AICompanion_Movement_v74", function(bot, cmd)
        if not selfRef:ShouldProcessMovement(bot) then return end

        local data = selfRef.data and selfRef.data:GetBotData(bot)
        if data and data.config then
            bot:SetNWBool("AI_StealthMode", data.config.stealth_mode or false)
            bot:SetNWBool("AI_DefenderMode", data.config.defender_mode or false)
            bot:SetNWBool("AI_MedicMode", data.config.medic_mode or false)
            bot:SetNWBool("AI_PacifistMode", data.config.pacifist_mode or false)
            bot:SetNWBool("AI_AggressiveMode", data.config.aggressive_mode or false)
        end

        if selfRef.state and selfRef.state:getState("Disabled") then
            if selfRef:IsValid(bot) and bot:GetNWBool("IsAICompanion", false) and bot:Alive() then
                cmd:ClearMovement()
                cmd:ClearButtons()
            end
            return
        end

        selfRef:ProcessMovement(bot, cmd)
    end)

    hook.Add("PlayerSpawn", "AICompanion_ResetSpawnTimer_v7", function(ply)
        if ply:GetNWBool("IsAICompanion", false) then
            ply._aiSpawnTime = CurTime()
            timer.Simple(0, function()
                if selfRef:IsValid(ply) then
                    ply:RemoveFlags(FL_ANIMDUCKING)
                    ply:RemoveFlags(FL_DUCKING)
                    pcall(function() ply:ConCommand("-duck") end)
                end
            end)
            timer.Simple(0.1, function()
                if selfRef:IsValid(ply) then
                    ply:RemoveFlags(FL_ANIMDUCKING)
                    ply:RemoveFlags(FL_DUCKING)
                end
            end)
            timer.Simple(0.5, function()
                if selfRef:IsValid(ply) then
                    ply:RemoveFlags(FL_ANIMDUCKING)
                    ply:RemoveFlags(FL_DUCKING)
                end
            end)
        end
    end)

    hook.Add("PlayerDeath", "AICompanion_Movement_CacheCleanup", function(victim)
        if victim:IsBot() and victim:GetNWBool("IsAICompanion", false) then
            selfRef:InvalidateBotCache(victim)
        end
    end)

    hook.Add("PlayerDisconnected", "AICompanion_Movement_CacheCleanup", function(ply)
        if ply:IsBot() and ply:GetNWBool("IsAICompanion", false) then
            selfRef:InvalidateBotCache(ply)
        end
    end)
end

return Movement
