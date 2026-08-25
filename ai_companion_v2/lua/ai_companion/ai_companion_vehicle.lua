if AI_COMPANION_VEHICLE_LOADED then return end
AI_COMPANION_VEHICLE_LOADED = true
local AC = _G.AI_COMPANION
_G.AI_Companion = _G.AI_Companion or {}
AC.Companion.BotData = AC.Companion.BotData or {}
local function SafeSetBotData(botID, data)
    if not AC.Companion.BotData then
        AC.Companion.BotData = {}
    end
end
if not Glide then
    Glide = {
        VEHICLE_TYPE = {
            HELICOPTER = "helicopter",
            PLANE = "plane",
            TANK = "tank",
            BOAT = "boat",
            MOTORCYCLE = "motorcycle",
            CAR = "car"
        }
    }
    print("[AI Vehicle]  Glide не найден, функция транспорта ограничена.")
    print("[AI Vehicle]  Установите Glide для полной поддержки транспорта.")
end
local function HasGlide()
    return rawget(_G, "Glide") ~= nil
end
if not AI_Utils then include("ai_companion/ai_companion_utils.lua") end
if not AI_Companion then include("ai_companion/ai_companion_core.lua") end
if not AI_CONFIG then include("ai_companion/ai_config.lua") end
local COMPANION_NAME = AI_CONFIG.COMPANION_NAME
local ENGINE_DEAD_ZONE_ENTER = AI.Config.Vehicle.EngineDeadZoneEnter
local ENGINE_DEAD_ZONE_EXIT = AI.Config.Vehicle.EngineDeadZoneExit
local ENGINE_STOP_DELAY = AI.Config.Vehicle.EngineStopDelay
local ENGINE_IDLE_TIMEOUT = AI.Config.Vehicle.EngineIdleTimeout
local HELI_FOLLOW_MAX_SPEED = AI.Config.Vehicle.Heli.FollowMaxSpeed
local HELI_FOLLOW_APPROACH_DIST = AI.Config.Vehicle.Heli.FollowApproachDist
local HELI_FOLLOW_DEAD_ZONE = AI.Config.Vehicle.Heli.FollowDeadZone
local HELI_ENEMY_MAX_SPEED = AI.Config.Vehicle.Heli.EnemyMaxSpeed
local HELI_ENEMY_APPROACH_DIST = AI.Config.Vehicle.Heli.EnemyApproachDist
local HELI_HEIGHT_DEAD_ZONE = AI.Config.Vehicle.Heli.HeightDeadZone
local HELI_MAX_PITCH = AI.Config.Vehicle.Heli.MaxPitch
local HELI_MAX_ROLL = AI.Config.Vehicle.Heli.MaxRoll
local HELI_DAMPING_FACTOR = AI.Config.Vehicle.Heli.DampingFactor
local HELI_SOFT_ALT_LIMIT = AI.Config.Vehicle.Heli.SoftAltLimit
local HELI_HARD_ALT_LIMIT = AI.Config.Vehicle.Heli.HardAltLimit
local HELI_DOWN_FORCE_MAX = AI.Config.Vehicle.Heli.DownForceMax
local HELI_UP_FORCE_MAX = AI.Config.Vehicle.Heli.UpForceMax
local HELI_FORCE_DEAD_ZONE = AI.Config.Vehicle.Heli.ForceDeadZone
local function IsFiniteNumber(value)
    return type(value) == "number" 
        and value == value 
        and math.abs(value) ~= math.huge
end
local function SanitizeNumber(value, default)
    local default = default or 0
    if type(value) ~= "number" then return default end
    if value ~= value then return default end
    if math.abs(value) == math.huge then return default end
    return value
end
local function SanitizeVector(v, fallback)
    local fallback = fallback or Vector(0, 0, 0)
    if type(v) ~= "Vector" then return Vector(fallback) end
    if not IsFiniteNumber(v.x) or not IsFiniteNumber(v.y) or not IsFiniteNumber(v.z) then
        return Vector(fallback)
    end
    return v
end
local function SafeGetClass(ent)
    if not AI_Utils.IsValid(ent) then return "invalid" end
    local ok, class = pcall(function() return ent:GetClass() end)
    return (ok and class) or "error"
end
local function SafeGetPos(ent)
    if not AI_Utils.IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:GetPos() end)
    return (ok and pos) or Vector()
end
local function SafeGetForward(ent)
    if not AI_Utils.IsValid(ent) then return Vector(1, 0, 0) end
    local ok, fw = pcall(function() return ent:GetForward() end)
    return (ok and fw) or Vector(1, 0, 0)
end
local function SafeGetRight(ent)
    if not AI_Utils.IsValid(ent) then return Vector(0, 1, 0) end
    local ok, r = pcall(function() return ent:GetRight() end)
    return (ok and r) or Vector(0, 1, 0)
end
local function SafeGetUp(ent)
    if not AI_Utils.IsValid(ent) then return Vector(0, 0, 1) end
    local ok, u = pcall(function() return ent:GetUp() end)
    return (ok and u) or Vector(0, 0, 1)
end
local function SafeGetVelocity(ent)
    if not AI_Utils.IsValid(ent) then return Vector() end
    local ok, vel = pcall(function() return ent:GetVelocity() end)
    return (ok and vel) or Vector()
end
local function SafeGetDriver(ent)
    if not AI_Utils.IsValid(ent) then return nil end
    local ok, driver = pcall(function() return ent:GetDriver() end)
    return (ok and driver) or nil
end
local function SafeGetVehicle(ply)
    if not AI_Utils.IsValid(ply) then return nil end
    local ok, veh = pcall(function() return ply:GetVehicle() end)
    return (ok and veh) or nil
end
local function SafeWorldSpaceCenter(ent)
    if not AI_Utils.IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:WorldSpaceCenter() end)
    return (ok and pos) or SafeGetPos(ent)
end
local function SafeGetParent(ent)
    if not AI_Utils.IsValid(ent) then return nil end
    local ok, parent = pcall(function() return ent:GetParent() end)
    return (ok and parent) or nil
end
local function SafeInVehicle(ent)
    if not AI_Utils.IsValid(ent) then return false end
    local ok, iv = pcall(function() return ent:InVehicle() end)
    return ok and iv
end
local function SafeAlive(ent)
    if not AI_Utils.IsValid(ent) then return false end
    local ok, alive = pcall(function() return ent:Alive() end)
    return ok and alive
end
local function IsGlideVehicle(ent)
    if not HasGlide() then return false end
    if not AI_Utils.IsValid(ent) then return false end
    if ent.IsGlideVehicle == true then return true end
    if isfunction(ent.IsGlideVehicle) then
        local ok, result = pcall(function() return ent:IsGlideVehicle() end)
        return ok and result
    end
    return false
end
local function GetGlideRoot(vehicle)
    if not AI_Utils.IsValid(vehicle) then return nil end
    if not HasGlide() then return nil end
    if IsGlideVehicle(vehicle) then return vehicle end
    local parent = SafeGetParent(vehicle)
    if AI_Utils.IsValid(parent) and IsGlideVehicle(parent) then return parent end
    if vehicle.vehicle and AI_Utils.IsValid(vehicle.vehicle) and IsGlideVehicle(vehicle.vehicle) then
        return vehicle.vehicle
    end
    return nil
end
function GetGlideVehicleType(vehicle)
    if not AI_Utils.IsValid(vehicle) then return "unknown" end
    if not HasGlide() then return "unknown" end
    if not IsGlideVehicle(vehicle) then return "unknown" end
    if not Glide or not Glide.VEHICLE_TYPE then return "glide" end
    local vType = vehicle.VehicleType
    if vType == Glide.VEHICLE_TYPE.HELICOPTER then return "helicopter" end
    if vType == Glide.VEHICLE_TYPE.PLANE then return "plane" end
    if vType == Glide.VEHICLE_TYPE.TANK then return "tank" end
    if vType == Glide.VEHICLE_TYPE.BOAT then return "boat" end
    if vType == Glide.VEHICLE_TYPE.MOTORCYCLE then return "motorcycle" end
    if vType == Glide.VEHICLE_TYPE.CAR then return "car" end
    return "glide"
end
local function IsHL2Seat(ent)
    if not AI_Utils.IsValid(ent) then return false end
    local class = SafeGetClass(ent)
    return class == "prop_vehicle_prisoner_pod" 
        or class == "prop_vehicle_driveable"
        or string.match(class, "^prop_vehicle_")
end
local function IsHL2Vehicle(ent)
    if not AI_Utils.IsValid(ent) then return false end
    local class = SafeGetClass(ent)
    return class == "prop_vehicle_jeep" 
        or class == "prop_vehicle_airboat"
        or class == "prop_vehicle_jeep_old"
        or class == "prop_vehicle_driveable"
end
local function GetHL2VehicleSeats(parentVehicle)
    if not AI_Utils.IsValid(parentVehicle) then return {} end
    local seats = {}
    local parent = GetGlideRoot(parentVehicle) or parentVehicle
    for _, ent in ipairs(ents.GetAll()) do
        if AI_Utils.IsValid(ent) and IsHL2Seat(ent) then
            local entParent = SafeGetParent(ent)
            if entParent == parent or entParent == parentVehicle then
                table.insert(seats, ent)
            else
                local dist = SafeGetPos(ent):Distance(SafeGetPos(parent))
                if dist < 200 then
                    table.insert(seats, ent)
                end
            end
        end
    end
    return seats
end
local function FindNearestFreeHL2Seat(bot, vehicle)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(vehicle) then return nil end
    local seats = GetHL2VehicleSeats(vehicle)
    if #seats == 0 then return nil end
    local botPos = SafeGetPos(bot)
    local bestSeat, bestDist = nil, 999999
    for _, seat in ipairs(seats) do
        if AI_Utils.IsValid(seat) then
            local driver = SafeGetDriver(seat)
            if not AI_Utils.IsValid(driver) then
                local dist = botPos:Distance(SafeGetPos(seat))
                if dist < bestDist then
                    bestDist = dist
                    bestSeat = seat
                end
            end
        end
    end
    return bestSeat
end
local function GetDriverSeat(vehicle)
    if not AI_Utils.IsValid(vehicle) then return nil end
    if IsHL2Vehicle(vehicle) then return vehicle end
    if HasGlide() then
        local root = GetGlideRoot(vehicle) or vehicle
        if root and IsGlideVehicle(root) and root.seats then
            return root.seats[1]
        end
    end
    return nil
end
local function PatchVehicleInputs(vehicle)
    if not AI_Utils.IsValid(vehicle) then return end
    if vehicle._ai_patched then return end
    if not vehicle.SetInputFloat then return end
    local originalSetInputFloat = vehicle.SetInputFloat
    local originalSetInputBool = vehicle.SetInputBool
    vehicle.SetInputFloat = function(self, playerIndex, inputName, value)
        if type(value) == "number" then
            if value ~= value or math.abs(value) == math.huge then
                value = 0
            end
            value = math.Clamp(value, -1, 1)
        else
            value = 0
        end
        return originalSetInputFloat(self, playerIndex, inputName, value)
    end
    vehicle.SetInputBool = function(self, playerIndex, inputName, value)
        if type(value) ~= "boolean" then
            value = false
        end
        return originalSetInputBool(self, playerIndex, inputName, value)
    end
    vehicle._ai_patched = true
end
if HasGlide() then
    hook.Add("InitPostEntity", "AI_PatchAllVehicles", function()
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and IsGlideVehicle(ent) then
                PatchVehicleInputs(ent)
            end
        end
    end)
    hook.Add("OnEntityCreated", "AI_PatchNewVehicle", function(ent)
        if IsValid(ent) and IsGlideVehicle(ent) then
            timer.Simple(0.1, function()
                if IsValid(ent) then
                    PatchVehicleInputs(ent)
                end
            end)
        end
    end)
end
local HL2_IN_FORWARD = IN_FORWARD or 8
local HL2_IN_BACK = IN_BACK or 16
local HL2_IN_LEFT = IN_LEFT or 128
local HL2_IN_RIGHT = IN_RIGHT or 256
function ApplyHL2VehicleCmd(cmd, throttle, steer)
    if not cmd then 
        AI_Utils.LogDebug("Vehicle", "ApplyHL2VehicleCmd: cmd is nil!")
        return 
    end
    local throttle = SanitizeNumber(throttle, 0)
    local steer = SanitizeNumber(steer, 0)
    AI_Utils.LogDebug("Vehicle", "ApplyHL2VehicleCmd: throttle=" .. tostring(throttle) .. " steer=" .. tostring(steer))
    pcall(function()
        local buttons = 0
        if throttle > 0.05 then
            buttons = buttons + HL2_IN_FORWARD
        elseif throttle < -0.05 then
            buttons = buttons + HL2_IN_BACK
        end
        if steer > 0.15 then
            buttons = buttons + HL2_IN_RIGHT
        elseif steer < -0.15 then
            buttons = buttons + HL2_IN_LEFT
        end
        cmd:SetForwardMove(math.Clamp(throttle * 450, -450, 450))
        cmd:SetSideMove(math.Clamp(steer * 450, -450, 450))
        cmd:SetUpMove(0)
        cmd:SetButtons(buttons)
    end)
end
function ApplyVehicleInputs(vehicle, inputs, seatIndex)
    if not AI_Utils.IsValid(vehicle) then 
        AI_Utils.LogDebug("Vehicle", "ApplyVehicleInputs: INVALID vehicle")
        return 
    end
    if not HasGlide() then 
        AI_Utils.LogDebug("Vehicle", "ApplyVehicleInputs: Glide not available")
        return 
    end
    if not inputs or type(inputs) ~= "table" then 
        AI_Utils.LogDebug("Vehicle", "ApplyVehicleInputs: INVALID inputs")
        return 
    end
    local seatIndex = seatIndex or 1
    local sanitized = {}
    for key, value in pairs(inputs) do
        if type(value) == "number" then
            if value ~= value or math.abs(value) == math.huge then
                sanitized[key] = 0
            else
                sanitized[key] = math.Clamp(value, -1, 1)
            end
        elseif type(value) == "boolean" then
            sanitized[key] = value
        end
    end
    pcall(function()
        if vehicle.SetInputFloat then
            local throttle = sanitized.throttle or 0
            local pitch = sanitized.pitch or 0
            local roll = sanitized.roll or 0
            local yaw = sanitized.yaw or 0
            local accelerate = sanitized.accelerate or 0
            local steer = sanitized.steer or 0
            if throttle ~= throttle then throttle = 0 end
            if pitch ~= pitch then pitch = 0 end
            if roll ~= roll then roll = 0 end
            if yaw ~= yaw then yaw = 0 end
            if accelerate ~= accelerate then accelerate = 0 end
            if steer ~= steer then steer = 0 end
            vehicle:SetInputFloat(seatIndex, "throttle", throttle)
            vehicle:SetInputFloat(seatIndex, "pitch", pitch)
            vehicle:SetInputFloat(seatIndex, "roll", roll)
            vehicle:SetInputFloat(seatIndex, "yaw", yaw)
            vehicle:SetInputFloat(seatIndex, "accelerate", accelerate)
            vehicle:SetInputFloat(seatIndex, "steer", steer)
        end
        if vehicle.SetInputBool then
            local brake = sanitized.brake and (sanitized.brake > 0) or false
            local handbrake = sanitized.handbrake and (sanitized.handbrake > 0) or false
            local attack = sanitized.attack or false
            local fire = sanitized.fire or false
            vehicle:SetInputBool(seatIndex, "brake", brake)
            vehicle:SetInputBool(seatIndex, "handbrake", handbrake)
            if sanitized.attack ~= nil then vehicle:SetInputBool(seatIndex, "attack", attack) end
            if sanitized.fire ~= nil then vehicle:SetInputBool(seatIndex, "fire", fire) end
        end
    end)
end
function GetAimTargetPos(ent)
    if not AI_Utils.IsValid(ent) then return Vector() end
    if ent.IsNPC and ent:IsNPC() then
        local names = {"ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1"}
        for _, n in ipairs(names) do
            local ok, bone = pcall(function() return ent:LookupBone(n) end)
            if ok and bone then
                local ok2, pos = pcall(function() return ent:GetBonePosition(bone) end)
                if ok2 and pos and pos:LengthSqr() > 0.01 then
                    return SanitizeVector(pos, Vector())
                end
            end
        end
    end
    return SanitizeVector(SafeWorldSpaceCenter(ent), Vector())
end
local TankState = {}
local HeliWeaponState = {}
local function CleanupTankState(bot)
    if not AI_Utils.IsValid(bot) then return end
    TankState[bot:EntIndex()] = nil
end
local function CleanupHeliWeaponState(bot)
    if not AI_Utils.IsValid(bot) then return end
    HeliWeaponState[bot:EntIndex()] = nil
end
function ResetBotAimTarget(bot)
    if not AI_Utils.IsValid(bot) then return end
    if not HasGlide() then return end
    if bot._originalGlideGetAimPos then
        bot.GlideGetAimPos = bot._originalGlideGetAimPos
        bot._originalGlideGetAimPos = nil
    end
    if bot._originalGetAimPos then
        bot.GetAimPos = bot._originalGetAimPos
        bot._originalGetAimPos = nil
    end
    if bot._originalGetAimVector then
        bot.GetAimVector = bot._originalGetAimVector
        bot._originalGetAimVector = nil
    end
    bot._aimPos = nil
end
function SetBotAimTarget(bot, pos)
    if not AI_Utils.IsValid(bot) then return end
    if not HasGlide() then return end
    local pos = SanitizeVector(pos, Vector())
    bot._aimPos = pos
    if not bot._originalGlideGetAimPos then
        bot._originalGlideGetAimPos = bot.GlideGetAimPos
    end
    bot.GlideGetAimPos = function(self) return self._aimPos or Vector() end
    if not bot._originalGetAimPos then
        bot._originalGetAimPos = bot.GetAimPos
    end
    bot.GetAimPos = function(self) return self._aimPos or Vector() end
    if not bot._originalGetAimVector then
        bot._originalGetAimVector = bot.GetAimVector
    end
    bot.GetAimVector = function(self)
        local aimPos = self._aimPos or Vector()
        local dir = aimPos - self:EyePos()
        if dir:LengthSqr() < 0.001 then return Vector(1, 0, 0) end
        dir:Normalize()
        return dir
    end
end
local function GetHeliWeaponState(bot)
    if not AI_Utils.IsValid(bot) then return nil end
    if not HasGlide() then return nil end
    local id = bot:EntIndex()
    HeliWeaponState[id] = HeliWeaponState[id] or {
        lastFireTime = 0,
        fireCooldown = 0.15,
        missileCooldown = 3.0,
        lastMissileTime = 0,
        maxRange = 3000,
        minRange = 200,
        burstCount = 0,
        burstMax = 8,
        burstPause = 1.5,
        lastBurstEnd = 0,
        isFiring = false
    }
    return HeliWeaponState[id]
end
local function GetHeliWeaponPos(root)
    if not AI_Utils.IsValid(root) then return Vector() end
    local pos = SanitizeVector(SafeWorldSpaceCenter(root), Vector())
    local fw = SanitizeVector(SafeGetForward(root), Vector(1,0,0))
    local up = SanitizeVector(SafeGetUp(root), Vector(0,0,1))
    return pos + fw * 80 + up * (-20)
end
local function CanSeeTargetFromPos(fromPos, target, bot)
    if not AI_Utils.IsValid(target) then return false end
    fromPos = SanitizeVector(fromPos, Vector())
    local targetPos = SanitizeVector(GetAimTargetPos(target), Vector())
    if fromPos:IsZero() or targetPos:IsZero() then return false end
    local tr = util.TraceLine({
        start = fromPos,
        endpos = targetPos,
        filter = function(ent)
            if not AI_Utils.IsValid(ent) then return false end
            if ent == bot then return false end
            local c = SafeGetClass(ent)
            return c ~= "player" and not (IsGlideVehicle(ent)) and c ~= "glide_rotor"
        end,
        mask = MASK_SOLID
    })
    return tr.Entity == target or not tr.Hit
end
local function FireHeliBullet(bot, root, target)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(root) or not AI_Utils.IsValid(target) then return false end
    if not HasGlide() then return false end
    local state = GetHeliWeaponState(bot)
    if not state then return false end
    local now = CurTime()
    if now - state.lastFireTime < state.fireCooldown then return false end
    if now - state.lastBurstEnd < state.burstPause and state.burstCount >= state.burstMax then return false end
    if state.burstCount >= state.burstMax then
        state.burstCount = 0
        state.lastBurstEnd = now
        return false
    end
    local weaponPos = SanitizeVector(GetHeliWeaponPos(root), Vector())
    local targetPos = SanitizeVector(GetAimTargetPos(target), Vector())
    if weaponPos:IsZero() or targetPos:IsZero() then return false end
    local dist = SanitizeNumber(weaponPos:Distance(targetPos), 0)
    if dist > state.maxRange or dist < state.minRange then return false end
    if not CanSeeTargetFromPos(weaponPos, target, bot) then return false end
    local targetVel = SanitizeVector(SafeGetVelocity(target), Vector())
    local bulletSpeed = 8000
    local timeToTarget = SanitizeNumber(dist / bulletSpeed, 0)
    local aimPos = SanitizeVector(targetPos + targetVel * timeToTarget, targetPos)
    local dir = SanitizeVector(aimPos - weaponPos, Vector())
    if dir:LengthSqr() < 0.001 then return false end
    dir:Normalize()
    local eff = EffectData()
    eff:SetOrigin(weaponPos)
    eff:SetAngles(dir:Angle())
    eff:SetScale(1)
    util.Effect("MuzzleFlash", eff)
    root:FireBullets({
        Attacker = bot,
        Damage = 12,
        Force = 50,
        Distance = dist + 500,
        Dir = dir,
        Src = weaponPos,
        HullSize = 2,
        Spread = Vector(0.02, 0.02, 0),
        IgnoreEntity = root,
        TracerName = "Tracer",
        AmmoType = "SMG1",
        Callback = function(attacker, tr, dmginfo) end
    })
    if SERVER then
        root:EmitSound("glide/weapons/turret_mg_loop.wav", 85, 100, 0.6, CHAN_WEAPON)
    end
    state.lastFireTime = now
    state.burstCount = state.burstCount + 1
    state.isFiring = true
    return true
end
local function FireHeliMissile(bot, root, target)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(root) or not AI_Utils.IsValid(target) then return false end
    if not HasGlide() then return false end
    local state = GetHeliWeaponState(bot)
    if not state then return false end
    local now = CurTime()
    if now - state.lastMissileTime < state.missileCooldown then return false end
    local weaponPos = SanitizeVector(GetHeliWeaponPos(root), Vector())
    local targetPos = SanitizeVector(GetAimTargetPos(target), Vector())
    local dist = SanitizeNumber(weaponPos:Distance(targetPos), 0)
    if dist > state.maxRange * 1.5 or dist < state.minRange * 2 then return false end
    if not CanSeeTargetFromPos(weaponPos, target, bot) then return false end
    local missile = ents.Create("glide_missile")
    if not IsValid(missile) then return false end
    local side = (state.lastMissileTime % 2 < 1) and 1 or -1
    local spawnPos = SanitizeVector(weaponPos + SafeGetRight(root) * (30 * side), weaponPos)
    missile:SetPos(spawnPos)
    local missileDir = SanitizeVector(targetPos - spawnPos, Vector(1,0,0))
    if missileDir:LengthSqr() < 0.001 then 
        SafeRemoveEntity(missile)
        return false 
    end
    missile:SetAngles(missileDir:Angle())
    missile:Spawn()
    missile:SetupMissile(bot, root)
    missile:SetTarget(target)
    local phys = missile:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocityInstantaneous(SafeGetForward(root) * 300 + SafeGetVelocity(root))
    end
    local eff = EffectData()
    eff:SetOrigin(spawnPos)
    eff:SetAngles(SafeGetForward(root):Angle())
    eff:SetScale(2)
    util.Effect("MuzzleFlash", eff)
    root:EmitSound("glide/weapons/missile_fire.wav", 90, 100, 0.8)
    state.lastMissileTime = now
    if target:IsPlayer() and Glide.SendMissileDanger then
        Glide.SendMissileDanger(target, missile)
    end
    return true
end
function ControlHeliWeapons(bot, root, target, isEnemy)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(root) then return end
    if not HasGlide() then return end
    if not isEnemy or not AI_Utils.IsValid(target) then
        local state = GetHeliWeaponState(bot)
        if state and state.isFiring then
            state.isFiring = false
            state.burstCount = 0
        end
        return
    end
    local fallbackPos = SanitizeVector(SafeGetPos(root), Vector())
    local aimPos = SanitizeVector(GetAimTargetPos(target), fallbackPos)
    local targetVel = SanitizeVector(SafeGetVelocity(target), Vector())
    aimPos = SanitizeVector(aimPos + targetVel * 0.3, fallbackPos)
    SetBotAimTarget(bot, aimPos)
    FireHeliBullet(bot, root, target)
    local dist = SanitizeNumber(SafeGetPos(root):Distance(GetAimTargetPos(target)), 0)
    if dist > 800 and math.random() < 0.3 then
        FireHeliMissile(bot, root, target)
    end
end
local function GetTerrainHeight(pos)
    local pos = SanitizeVector(pos, Vector())
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 1000),
        endpos = pos - Vector(0, 0, 1000),
        mask = MASK_SOLID,
        filter = function(ent)
            if not AI_Utils.IsValid(ent) then return false end
            local c = SafeGetClass(ent)
            return c ~= "player" and c:sub(1,4) ~= "npc_"
        end
    })
    return tr.Hit and SanitizeNumber(tr.HitPos.z, pos.z - 1000) or pos.z - 1000
end
local function ApplyHeliDownForce(root, target, desiredPos)
    if not AI_Utils.IsValid(root) or not AI_Utils.IsValid(target) or not desiredPos then return end
    if not HasGlide() then return end
    local vehPos = SanitizeVector(SafeGetPos(root), Vector())
    local targetPos = SanitizeVector(GetAimTargetPos(target), vehPos)
    local checkPosSafe = SanitizeVector(desiredPos, targetPos)
    local heightAboveTarget = vehPos.z - checkPosSafe.z
    if heightAboveTarget < HELI_SOFT_ALT_LIMIT then return end
    local phys
    pcall(function() phys = root:GetPhysicsObject() end)
    if not phys then return end
    local ok, isValid = pcall(function() return phys:IsValid() end)
    if not ok or not isValid then return end
    local mass = 0
    pcall(function() mass = phys:GetMass() end)
    mass = SanitizeNumber(mass, 500)
    if mass <= 0 then return end
    local up = SanitizeVector(SafeGetUp(root), Vector(0,0,1))
    local overshoot = heightAboveTarget - HELI_SOFT_ALT_LIMIT
    if overshoot < HELI_FORCE_DEAD_ZONE then return end
    local forceMagnitude = math.min(overshoot * mass * 0.8, HELI_DOWN_FORCE_MAX)
    pcall(function()
        phys:ApplyForceCenter((-up) * forceMagnitude)
    end)
end
function CalculateHeliInputs(vehicle, target, isEnemy)
    if not AI_Utils.IsValid(vehicle) or not AI_Utils.IsValid(target) then
        AI_Utils.LogDebug("Vehicle", "CalculateHeliInputs: INVALID params")
        return { throttle = 0.5, pitch = 0, roll = 0, yaw = 0 }
    end
    if not HasGlide() then
        AI_Utils.LogDebug("Vehicle", "CalculateHeliInputs: Glide not available")
        return { throttle = 0.5, pitch = 0, roll = 0, yaw = 0 }
    end
    AI_Utils.LogDebug("Vehicle", "CalculateHeliInputs: isEnemy=" .. tostring(isEnemy))
    local dt = math.Clamp(FrameTime(), 0.001, 0.05)
    local now = CurTime()
    vehicle._ap = vehicle._ap or {}
    local ap = vehicle._ap
    local vehPos = SanitizeVector(SafeGetPos(vehicle), Vector())
    local vehVel = SanitizeVector(SafeGetVelocity(vehicle), Vector())
    local forward = SanitizeVector(SafeGetForward(vehicle), Vector(1,0,0))
    local right = SanitizeVector(SafeGetRight(vehicle), Vector(0,1,0))
    local forwardH = Vector(forward.x, forward.y, 0)
    if forwardH:LengthSqr() < 0.001 then forwardH = Vector(1, 0, 0) end
    forwardH:Normalize()
    local rightH = Vector(right.x, right.y, 0)
    if rightH:LengthSqr() < 0.001 then rightH = Vector(0, 1, 0) end
    rightH:Normalize()
    local targetPos = SanitizeVector(GetAimTargetPos(target), vehPos)
    local targetVel = SanitizeVector(SafeGetVelocity(target), Vector())
    targetVel.z = 0
    local predictedPos = SanitizeVector(targetPos + targetVel * 0.4, targetPos)
    local desiredPos
    if isEnemy then
        ap.circleAng = (ap.circleAng or 0) + dt * 0.35
        local radius = 280
        local tFw = SanitizeVector(SafeGetForward(target), Vector(1,0,0))
        local tRt = SanitizeVector(SafeGetRight(target), Vector(0,1,0))
        local offset = tRt * math.cos(ap.circleAng) * radius
                     + tFw * math.sin(ap.circleAng) * radius * 0.3
        desiredPos = SanitizeVector(predictedPos + offset, predictedPos)
        desiredPos.z = targetPos.z + 140
    else
        if ap.followTarget ~= target then
            ap.followTarget = target
            ap.followPos = nil
            ap.lastFollowOwnerPos = nil
        end
        local moved = ap.lastFollowOwnerPos and targetPos:Distance(ap.lastFollowOwnerPos) or 999999
        if not ap.followPos or moved > 15 then
            local dir
            if targetVel:Length() > 15 then
                dir = targetVel:GetNormalized()
            else
                dir = SanitizeVector(SafeGetForward(target), Vector(1,0,0))
            end
            dir.z = 0
            if dir:LengthSqr() < 0.001 then dir = Vector(1, 0, 0) end
            dir:Normalize()
            ap.followPos = SanitizeVector(predictedPos - dir * 180, predictedPos)
            ap.followPos.z = targetPos.z + 130
            ap.lastFollowOwnerPos = targetPos
        end
        desiredPos = ap.followPos
    end
    desiredPos = SanitizeVector(desiredPos, targetPos + Vector(0,0,130))
    local toDesired = desiredPos - vehPos
    local horiz = Vector(toDesired.x, toDesired.y, 0)
    local distXY = SanitizeNumber(horiz:Length(), 0)
    local dirH = forwardH
    if distXY > 1 then 
        local norm = horiz:GetNormalized()
        if IsFiniteNumber(norm.x) and IsFiniteNumber(norm.y) and IsFiniteNumber(norm.z) then
            dirH = norm
        end
    end
    if distXY < HELI_FOLLOW_DEAD_ZONE and not isEnemy then
        return { throttle = 0.5, pitch = 0, roll = 0, yaw = 0 }
    end
    local maxSpeed = isEnemy and HELI_ENEMY_MAX_SPEED or HELI_FOLLOW_MAX_SPEED
    local approachDist = isEnemy and HELI_ENEMY_APPROACH_DIST or HELI_FOLLOW_APPROACH_DIST
    local desiredSpeed = maxSpeed
    if distXY < approachDist then
        desiredSpeed = maxSpeed * (distXY / approachDist)
    end
    desiredSpeed = math.max(desiredSpeed, 0)
    desiredSpeed = SanitizeNumber(desiredSpeed, 0)
    local velH = Vector(vehVel.x, vehVel.y, 0)
    local currentSpeed = SanitizeNumber(velH:Length(), 0)
    if currentSpeed > desiredSpeed then
        desiredSpeed = desiredSpeed * (1 - HELI_DAMPING_FACTOR) + desiredSpeed * HELI_DAMPING_FACTOR
    end
    local desiredVel = dirH * desiredSpeed
    local velError = desiredVel - velH
    local fwdErr = SanitizeNumber(velError:Dot(forwardH), 0)
    local rightErr = SanitizeNumber(velError:Dot(rightH), 0)
    local yawInput = 0
    if distXY > 50 then
        local dotF = forwardH:Dot(dirH)
        local dotR = rightH:Dot(dirH)
        if dotF < -0.25 then
            yawInput = (dotR >= 0) and 0.8 or -0.8
        else
            yawInput = math.Clamp(dotR * 1.5, -0.8, 0.8)
        end
    end
    local pitchInput = math.Clamp(fwdErr / 350, -HELI_MAX_PITCH, HELI_MAX_PITCH)
    local rollInput = math.Clamp(yawInput * 0.25 + rightErr / 700, -HELI_MAX_ROLL, HELI_MAX_ROLL)
    if math.abs(yawInput) > 0.5 then
        pitchInput = pitchInput * 0.3
    end
    local targetHeight = desiredPos.z
    local heightError = targetHeight - vehPos.z
    local throttleInput = 0.5 + heightError * 0.0035 - vehVel.z * 0.005
    if math.abs(heightError) < HELI_HEIGHT_DEAD_ZONE then
        throttleInput = 0.5
    elseif heightError > 60 then
        throttleInput = math.max(throttleInput, 0.65)
    elseif heightError < -60 then
        throttleInput = math.min(throttleInput, 0.35)
    end
    ApplyHeliDownForce(vehicle, target, desiredPos)
    local groundZ = SanitizeNumber(GetTerrainHeight(vehPos), vehPos.z - 1000)
    local heightAboveGround = vehPos.z - groundZ
    if heightAboveGround < 70 then
        throttleInput = math.max(throttleInput, 0.85)
        pitchInput = math.Clamp(pitchInput, -0.12, 0.12)
        rollInput = math.Clamp(rollInput, -0.12, 0.12)
    end
    throttleInput = math.Clamp(throttleInput, -1, 1)
    if not IsFiniteNumber(throttleInput) then throttleInput = 0.5 end
    local smooth = math.Clamp(dt * 1.6, 0, 1)
    ap.p = (ap.p or 0) + (pitchInput - (ap.p or 0)) * smooth
    ap.r = (ap.r or 0) + (rollInput - (ap.r or 0)) * smooth
    ap.y = (ap.y or 0) + (yawInput - (ap.y or 0)) * smooth
    ap.t = (ap.t or 0.5) + (throttleInput - (ap.t or 0.5)) * smooth
    ap.t = SanitizeNumber(ap.t, 0.5)
    ap.p = SanitizeNumber(ap.p, 0)
    ap.r = SanitizeNumber(ap.r, 0)
    ap.y = SanitizeNumber(ap.y, 0)
    local result = {
        throttle = math.Clamp(ap.t, -1, 1),
        pitch = math.Clamp(ap.p, -1, 1),
        roll = math.Clamp(ap.r, -1, 1),
        yaw = math.Clamp(ap.y, -1, 1)
    }
    AI_Utils.LogDebug("Vehicle", "CalculateHeliInputs RESULT: t=" .. tostring(math.Round(result.throttle,2)) .. " p=" .. tostring(math.Round(result.pitch,2)) .. " r=" .. tostring(math.Round(result.roll,2)) .. " y=" .. tostring(math.Round(result.yaw,2)))
    return result
end
local function GetTankState(bot)
    if not AI_Utils.IsValid(bot) then return nil end
    if not HasGlide() then return nil end
    local id = bot:EntIndex()
    TankState[id] = TankState[id] or {
        lastFireTime = 0,
        fireCooldown = 2.0,
        aimStartTime = 0,
        isAiming = false,
        minAimTime = 1.5,
        attackHeldUntil = 0,
        aimSetTime = nil
    }
    return TankState[id]
end
local function ReleaseTankAttack(root)
    if not HasGlide() then return end
    ApplyVehicleInputs(root, {attack = false, fire = false})
end
function UpdateTankAim(bot, root, target, isEnemy)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(root) then return end
    if not HasGlide() then return end
    local aimPos
    if isEnemy and AI_Utils.IsValid(target) then
        local targetPos = SanitizeVector(GetAimTargetPos(target), Vector())
        local targetVel = Vector()
        pcall(function()
            if target.GetVelocity then targetVel = target:GetVelocity()
            elseif target.GetAbsVelocity then targetVel = target:GetAbsVelocity() end
        end)
        targetVel = SanitizeVector(targetVel, Vector())
        local bulletSpeed = 3000
        pcall(function()
            if root.weapons and root.weapons[1] and root.weapons[1].ProjectileSpeed then
                bulletSpeed = root.weapons[1].ProjectileSpeed
            end
        end)
        local dist = SanitizeNumber(targetPos:Distance(SafeGetPos(root)), 0)
        local timeToTarget = dist / math.max(bulletSpeed, 100)
        aimPos = SanitizeVector(targetPos + targetVel * timeToTarget, targetPos)
        pcall(function()
            if root.weapons and root.weapons[1] and root.weapons[1].Gravity then
                aimPos = aimPos - Vector(0, 0, root.weapons[1].Gravity * timeToTarget * timeToTarget * 0.5)
            end
        end)
    else
        if AI_Utils.IsValid(target) then
            aimPos = SanitizeVector(GetAimTargetPos(target), Vector())
        else
            aimPos = SanitizeVector(SafeGetPos(root) + SafeGetForward(root) * 1000 + SafeGetUp(root) * 50, Vector())
        end
    end
    SetBotAimTarget(bot, aimPos)
    pcall(function()
        if root.SetTurretAngle and root.GetTurretOrigin then
            local origin = SanitizeVector(root:GetTurretOrigin(), Vector())
            local dir = aimPos - origin
            if dir:LengthSqr() > 0.001 then
                dir:Normalize()
                local ang = root:WorldToLocalAngles(dir:Angle())
                if root.PitchAngMax then
                    ang[1] = math.Clamp(ang[1], root.PitchAngMax, root.PitchAngMin or 90)
                end
                ang[3] = 0
                root:SetTurretAngle(ang)
            end
        end
    end)
end
function ControlTankCannon(bot, vehicle, target)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(vehicle) or not AI_Utils.IsValid(target) then
        ResetBotAimTarget(bot)
        return false
    end
    if not HasGlide() then return false end
    local root = GetGlideRoot(vehicle) or vehicle
    if not AI_Utils.IsValid(root) then
        ResetBotAimTarget(bot)
        return false
    end
    local state = GetTankState(bot)
    if not state then return false end
    local now = CurTime()
    local botID = bot:EntIndex()
    if state.attackHeldUntil and now > state.attackHeldUntil then
        ReleaseTankAttack(root)
        state.attackHeldUntil = nil
    end
    if now - state.lastFireTime < state.fireCooldown then return true end
    local targetPos = SanitizeVector(GetAimTargetPos(target), Vector())
    local vehPos = SanitizeVector(SafeWorldSpaceCenter(vehicle), Vector())
    local dist = SanitizeNumber(targetPos:Distance(vehPos), 0)
    if dist < 120 then
        ResetBotAimTarget(bot)
        return false
    end
    local aimPos = SanitizeVector(bot._aimPos or targetPos, targetPos)
    local aimError = 1.0
    local turretDir = nil
    local turretOrigin = vehPos
    pcall(function() turretOrigin = SanitizeVector(root:GetTurretOrigin(), vehPos) end)
    pcall(function() turretDir = root:GetTurretAimDirection() end)
    if turretDir then
        local toTarget = aimPos - turretOrigin
        if toTarget:LengthSqr() > 0.001 then
            toTarget:Normalize()
            aimError = turretDir:Dot(toTarget)
        end
    end
    if aimError < 0.92 then return true end
    ApplyVehicleInputs(root, {attack = true, fire = true})
    state.lastFireTime = now
    state.aimSetTime = nil
    state.attackHeldUntil = now + 0.15
    local timerName = "AI_TankFire_" .. botID
    if timer.Exists(timerName) then timer.Remove(timerName) end
    timer.Create(timerName, 0.2, 1, function()
        local currentRoot = GetGlideRoot(vehicle) or vehicle
        if AI_Utils.IsValid(currentRoot) and currentRoot == root then
            ReleaseTankAttack(root)
        end
        timer.Remove(timerName)
    end)
    return true
end
local EngineStopCooldown = {}
function StopVehicle(root, vehicle, cmd)
    if not AI_Utils.IsValid(root) then 
        AI_Utils.LogDebug("Vehicle", "StopVehicle: INVALID root")
        return 
    end
    local driverSeat = GetDriverSeat(vehicle)
    if AI_Utils.IsValid(driverSeat) then
        local driver = SafeGetDriver(driverSeat)
        if not AI_Utils.IsValid(driver) or not driver:GetNWBool("IsAICompanion", false) then
            AI_Utils.LogDebug("Vehicle", "StopVehicle: driver not AI")
            return 
        end
    end
    AI_Utils.LogDebug("Vehicle", "StopVehicle: stopping " .. SafeGetClass(root))
    if IsHL2Vehicle(vehicle) then
        if cmd then
            ApplyHL2VehicleCmd(cmd, 0, 0)
        end
        return
    end
    if HasGlide() and IsGlideVehicle(root) then
        local id = root:EntIndex()
        local now = CurTime()
        if not EngineStopCooldown[id] or now - EngineStopCooldown[id] >= 2.0 then
            EngineStopCooldown[id] = now
            pcall(function()
                if root.TurnOff then root:TurnOff() end
                if root.SetEngineState then root:SetEngineState(false) end
            end)
        end
        ApplyVehicleInputs(root, {
            throttle = 0,
            pitch = 0,
            roll = 0,
            yaw = 0,
            accelerate = 0,
            brake = 1,
            steer = 0,
            handbrake = 0,
            attack = false,
            fire = false
        })
    end
end
function CheckVehicleObstacle(vehicle, direction, distance)
    if not AI_Utils.IsValid(vehicle) then return false, nil, distance end
    distance = distance or 350
    local root = GetGlideRoot(vehicle) or vehicle
    if not AI_Utils.IsValid(root) then return false, nil, distance end
    local vehPos = SafeGetPos(root)
    local forward = direction and SanitizeVector(direction, SafeGetForward(root)) or SafeGetForward(root)
    forward.z = 0
    if forward:LengthSqr() < 0.001 then forward = Vector(1, 0, 0) end
    forward:Normalize()
    local right = SafeGetRight(root)
    right.z = 0
    if right:LengthSqr() < 0.001 then right = Vector(0, 1, 0) end
    right:Normalize()
    local up = SafeGetUp(root)
    local filter = {vehicle, root}
    local parent = SafeGetParent(root)
    if AI_Utils.IsValid(parent) then table.insert(filter, parent) end
    local offsets = {
        up * 40,
        right * -40 + up * 25,
        right * 40 + up * 25,
    }
    local hitDist = distance
    local hitNormal = nil
    local hasObstacle = false
    for _, offset in ipairs(offsets) do
        local startPos = vehPos + offset
        local tr = util.TraceLine({
            start = startPos,
            endpos = startPos + forward * distance,
            filter = filter,
            mask = MASK_SOLID
        })
        if not tr.StartSolid and tr.Hit and tr.Fraction < 1 then
            local ent = tr.Entity
            local class = SafeGetClass(ent)
            if class ~= "prop_door_rotating" and class ~= "func_door" 
               and not ent.IsPlayer and not ent.IsNPC then
                local d = tr.Fraction * distance
                if d < hitDist then
                    hitDist = d
                    hitNormal = tr.HitNormal
                    hasObstacle = true
                end
            end
        end
    end
    if hitDist < distance * 0.5 then
        return true, hitNormal, hitDist
    end
    return false, hitNormal, hitDist
end
function GetAvoidanceDirection(vehicle, targetDir, hitNormal)
    if not hitNormal then return targetDir end
    local forward = SafeGetForward(vehicle)
    local right = SafeGetRight(vehicle)
    local slide = targetDir - (targetDir:Dot(hitNormal) * hitNormal)
    slide.z = 0
    local awayFromWall = -hitNormal * 0.5
    local result = slide + awayFromWall
    if result:LengthSqr() < 0.01 then
        local rightDot = right:Dot(hitNormal)
        result = forward + right * (rightDot > 0 and -1 or 1)
    end
    result:Normalize()
    return result
end
function ControlGroundVehicle(bot, root, vehicle, followPos, cmd)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(root) or not followPos then 
        AI_Utils.LogDebug("Vehicle", "ControlGroundVehicle: INVALID params")
        return 
    end
    AI_Utils.LogDebug("Vehicle", "ControlGroundVehicle: followPos=" .. tostring(followPos) .. " isHL2=" .. tostring(IsHL2Vehicle(vehicle)))
    local vehPos = SanitizeVector(SafeGetPos(root), Vector())
    local toTarget = SanitizeVector(followPos - vehPos, Vector())
    toTarget.z = 0
    local dist = SanitizeNumber(toTarget:Length(), 0)
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if not data then return end
    if not data.vehicle then
        data.vehicle = {
            engine_idle_timer = 0,
            engine_state = "on",
            dead_zone_active = false,
        }
    end
    local vehicleData = data.vehicle
    local isHL2 = IsHL2Vehicle(vehicle)
    local engineOn = isHL2
    if isHL2 then
        if not root._aiEngineRequested then
            root._aiEngineRequested = true
            pcall(function()
                vehicle:Fire("TurnOn", "", 0)
            end)
        end
    elseif HasGlide() and IsGlideVehicle(root) then
        pcall(function()
            if root.GetEngineState then
                engineOn = root:GetEngineState() and true or false
            end
        end)
    end
    local inDeadZone
    if vehicleData.dead_zone_active then
        inDeadZone = dist < ENGINE_DEAD_ZONE_EXIT
    else
        inDeadZone = dist < ENGINE_DEAD_ZONE_ENTER
    end
    vehicleData.dead_zone_active = inDeadZone
    if inDeadZone then
        vehicleData.engine_idle_timer = (vehicleData.engine_idle_timer or 0) + FrameTime()
        if not isHL2 and HasGlide() and engineOn and vehicleData.engine_idle_timer >= ENGINE_IDLE_TIMEOUT then
            pcall(function()
                if root.TurnOff then root:TurnOff() end
                if root.SetEngineState then root:SetEngineState(false) end
            end)
            vehicleData.engine_state = "off"
        end
        if isHL2 then
            if cmd then
                ApplyHL2VehicleCmd(cmd, 0, 0)
            end
            return
        end
        if not engineOn then
            return
        end
        if HasGlide() then
            ApplyVehicleInputs(root, {
                throttle = 0,
                accelerate = 0,
                brake = 1,
                steer = 0,
                handbrake = 1,
                attack = false,
                fire = false
            })
        end
        return
    else
        vehicleData.engine_idle_timer = 0
        if not engineOn and HasGlide() then
            pcall(function()
                if root.TurnOn then root:TurnOn() end
                if root.SetEngineState then root:SetEngineState(true) end
            end)
            vehicleData.engine_state = "on"
        end
    end
    if dist < 1 then
        if isHL2 then
            if cmd then
                ApplyHL2VehicleCmd(cmd, 0, 0)
            end
        elseif HasGlide() then
            ApplyVehicleInputs(root, {
                throttle = 0,
                accelerate = 0,
                brake = 1,
                steer = 0,
                handbrake = 1,
                attack = false,
                fire = false
            })
        end
        return
    end
    local dir = dist > 1 and toTarget:GetNormalized() or SafeGetForward(root)
    dir.z = 0
    if dir:LengthSqr() < 0.001 then dir = Vector(1, 0, 0) end
    dir:Normalize()
    local forward = SafeGetForward(root)
    forward.z = 0
    if forward:LengthSqr() < 0.001 then forward = Vector(1, 0, 0) end
    forward:Normalize()
    local right = SafeGetRight(root)
    right.z = 0
    if right:LengthSqr() < 0.001 then right = Vector(0, 1, 0) end
    right:Normalize()
    local hasObstacle, hitNormal, obstacleDist = CheckVehicleObstacle(root, forward, 450)
    if hasObstacle and obstacleDist < 170 then
        if isHL2 then
            if cmd then
                ApplyHL2VehicleCmd(cmd, 0, 0)
            end
        elseif HasGlide() then
            ApplyVehicleInputs(root, {
                throttle = 0,
                accelerate = 0,
                brake = 1,
                steer = 0,
                handbrake = 1,
                attack = false,
                fire = false
            })
        end
        return
    end
    if hasObstacle then
        dir = GetAvoidanceDirection(root, dir, hitNormal)
    end
    local forwardDot = forward:Dot(dir)
    local rightDot = right:Dot(dir)
    local throttle = 0
    if dist > 800 then
        throttle = 1.0
    elseif dist > 500 then
        throttle = 0.65
    elseif dist > ENGINE_DEAD_ZONE_EXIT then
        throttle = 0.4
    else
        throttle = 0.2
    end
    if hasObstacle then
        throttle = throttle * math.Clamp((obstacleDist - 120) / 320, 0.2, 0.8)
    end
    if forwardDot < -0.45 and dist > 260 then
        throttle = -0.4
    end
    local steer = 0
    if forwardDot > 0.1 then
        steer = rightDot * 1.35
    else
        steer = (rightDot > 0) and 1 or -1
    end
    if hasObstacle and obstacleDist < 260 then
        steer = steer * 1.5
    end
    steer = math.Clamp(steer, -1, 1)
    AI_Utils.LogDebug("Vehicle", "ControlGroundVehicle FINAL: isHL2=" .. tostring(isHL2) .. " throttle=" .. tostring(math.Round(throttle,2)) .. " steer=" .. tostring(math.Round(steer,2)) .. " dist=" .. tostring(math.Round(dist,1)))
    if isHL2 then
        if cmd then
            AI_Utils.LogDebug("Vehicle", "Applying HL2 cmd")
            ApplyHL2VehicleCmd(cmd, throttle, steer)
        else
            AI_Utils.LogDebug("Vehicle", "WARNING: cmd is nil for HL2!")
        end
    elseif HasGlide() then
        AI_Utils.LogDebug("Vehicle", "Applying Glide inputs")
        ApplyVehicleInputs(root, {
            accelerate = math.max(0, throttle),
            brake = math.max(0, -throttle),
            steer = steer
        })
    else
        AI_Utils.LogDebug("Vehicle", "WARNING: neither HL2 nor Glide path!")
    end
    SafeSetBotData(botID, data)
end
function ControlVehicle(bot, vehicle, owner, cmd)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(vehicle) then 
        AI_Utils.LogDebug("Vehicle", "ControlVehicle: INVALID bot or vehicle")
        return 
    end
    if not AI_Utils.IsValid(owner) then 
        AI_Utils.LogDebug("Vehicle", "ControlVehicle: INVALID owner")
        return 
    end
    local root = GetGlideRoot(vehicle) or vehicle
    if not AI_Utils.IsValid(root) then 
        AI_Utils.LogDebug("Vehicle", "ControlVehicle: INVALID root")
        return 
    end
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if not data then return end
    local driverSeat = GetDriverSeat(vehicle)
    local botIsDriver = AI_Utils.IsValid(driverSeat) and SafeGetDriver(driverSeat) == bot
    local playerIsDriver = AI_Utils.IsValid(driverSeat) and SafeGetDriver(driverSeat) == owner
    local hasEnemy = data.combat and IsValid(data.combat.target)
    AI_Utils.LogDebug("Vehicle", "ControlVehicle: botIsDriver=" .. tostring(botIsDriver) .. " hasEnemy=" .. tostring(hasEnemy) .. " class=" .. SafeGetClass(root))
    if not botIsDriver then
        AI_Utils.LogDebug("Vehicle", "ControlVehicle: bot is NOT driver, stopping")
        StopVehicle(root, vehicle, cmd)
        return
    end
    AI_Utils.LogDebug("Vehicle", "ControlVehicle: bot IS driver, processing vehicle type=" .. tostring(GetGlideVehicleType(root)))
    if HasGlide() and IsGlideVehicle(root) then
        local vType = GetGlideVehicleType(root)
        if vType == "helicopter" then
            local target = hasEnemy and data.combat.target or owner
            local isEnemy = hasEnemy and IsValid(data.combat.target)
            local inputs = CalculateHeliInputs(root, target, isEnemy)
            if inputs then ApplyVehicleInputs(root, inputs) end
            ControlHeliWeapons(bot, root, target, isEnemy)
            return
        end
        if vType == "tank" then
            local aimTarget = hasEnemy and data.combat.target or owner
            UpdateTankAim(bot, root, aimTarget, hasEnemy)
            if hasEnemy then
                ControlTankCannon(bot, vehicle, data.combat.target)
            else
                ReleaseTankAttack(root)
            end
            local followPos = hasEnemy and GetAimTargetPos(data.combat.target) or SafeGetPos(owner)
            followPos = SanitizeVector(followPos, SafeGetPos(owner))
            ControlGroundVehicle(bot, root, vehicle, followPos, cmd)
            return
        end
    end
    local followPos
    if hasEnemy then
        followPos = GetAimTargetPos(data.combat.target)
    else
        followPos = SafeGetPos(owner)
    end
    followPos = SanitizeVector(followPos, SafeGetPos(owner))
    ControlGroundVehicle(bot, root, vehicle, followPos, cmd)
end
function GetBestSeat(vehicle, bot, hasEnemy, playerIsDriver, owner)
    if not AI_Utils.IsValid(vehicle) or not AI_Utils.IsValid(bot) then 
        return nil 
    end
    if not HasGlide() then return nil end
    local root = GetGlideRoot(vehicle) or vehicle
    if not AI_Utils.IsValid(root) then return nil end
    if not IsGlideVehicle(root) or not root.seats then return nil end
    local totalSeats = #root.seats
    if totalSeats <= 1 then return nil end
    local playerSeatIdx = nil
    for i = 1, totalSeats do
        local seat = root.seats[i]
        if AI_Utils.IsValid(seat) and SafeGetDriver(seat) == owner then
            playerSeatIdx = i
            break
        end
    end
    if playerSeatIdx then
        local preferredIdx = playerSeatIdx + 1
        if preferredIdx <= totalSeats then
            local seat = root.seats[preferredIdx]
            if AI_Utils.IsValid(seat) and not AI_Utils.IsValid(SafeGetDriver(seat)) then
                return seat
            end
        end
        local leftIdx = playerSeatIdx - 1
        if leftIdx >= 2 then
            local seat = root.seats[leftIdx]
            if AI_Utils.IsValid(seat) and not AI_Utils.IsValid(SafeGetDriver(seat)) then
                return seat
            end
        end
    end
    for i = 2, totalSeats do
        local seat = root.seats[i]
        if AI_Utils.IsValid(seat) and not AI_Utils.IsValid(SafeGetDriver(seat)) then
            return seat
        end
    end
    return nil
end
function EnterBestSeat(bot, vehicle, force, hasEnemy, playerIsDriver, owner)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(vehicle) then return false end
    if not HasGlide() then return false end
    local bestSeat = GetBestSeat(vehicle, bot, hasEnemy, playerIsDriver, owner)
    if not AI_Utils.IsValid(bestSeat) then return false end
    if bot:InVehicle() then
        local currentVeh = SafeGetVehicle(bot)
        if currentVeh ~= bestSeat then
            pcall(function() bot:ExitVehicle() end)
            timer.Simple(0.1, function()
                if AI_Utils.IsValid(bot) and not bot:InVehicle() then
                    pcall(function() bot:EnterVehicle(bestSeat) end)
                end
            end)
            return true
        end
        return true
    end
    local ok = pcall(function() bot:EnterVehicle(bestSeat) end)
    if ok and bot:InVehicle() then
        local botID = bot:EntIndex()
        local data = GetBotData(bot)
        if data then
            data.vehicle.locked_vehicle = GetGlideRoot(vehicle) or vehicle
            data.vehicle.locked_seat = bestSeat
            SafeSetBotData(botID, data)
        end
        return true
    end
    return false
end
local function FindNearestVehicle(bot, radius)
    if not AI_Utils.IsValid(bot) then return nil end
    radius = radius or 500
    local botPos = SafeGetPos(bot)
    local candidates = {}
    for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
        if not AI_Utils.IsValid(ent) then continue end
        local root = nil
        local isValid = false
        local class = SafeGetClass(ent)
        local dist = botPos:Distance(SafeGetPos(ent))
        if HasGlide() and IsGlideVehicle(ent) then
            isValid = true
            root = ent
        elseif IsHL2Vehicle(ent) then
            isValid = true
            root = ent
        elseif HasGlide() then
            root = GetGlideRoot(ent)
            if AI_Utils.IsValid(root) and IsGlideVehicle(root) then
                isValid = true
            end
        end
        if not isValid or not AI_Utils.IsValid(root) then
            continue
        end
        local driverSeat = GetDriverSeat(root)
        if not AI_Utils.IsValid(driverSeat) then
            continue
        end
        local driver = SafeGetDriver(driverSeat)
        if AI_Utils.IsValid(driver) then
            continue
        end
        table.insert(candidates, {root = root, dist = dist})
    end
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    local result = candidates[1] and candidates[1].root or nil
    return result
end
local function EnterDriverSeat(bot, vehicle)
    if not AI_Utils.IsValid(bot) or not AI_Utils.IsValid(vehicle) then return false end
    local seat = GetDriverSeat(vehicle)
    if not AI_Utils.IsValid(seat) then return false end
    if AI_Utils.IsValid(SafeGetDriver(seat)) then return false end
    local ok = pcall(function() bot:EnterVehicle(seat) end)
    if ok and bot:InVehicle() then
        local botID = bot:EntIndex()
        local data = GetBotData(bot)
        if data then
            data.vehicle.sit_by_command = true
            data.vehicle.locked_vehicle = GetGlideRoot(vehicle) or vehicle
            data.vehicle.locked_seat = seat
            SafeSetBotData(botID, data)
        end
        return true
    end
    return false
end
local function ForceExit(bot)
    if not AI_Utils.IsValid(bot) then return end
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if data then
        data.vehicle.sit_by_command = false
        data.vehicle.locked_vehicle = nil
        data.vehicle.locked_seat = nil
        data.vehicle.cached_turret = nil
        data.vehicle.cached_weapons = nil
        data.vehicle.path = nil
        data.vehicle.path_time = 0
        data.vehicle.path_index = 1
        data.vehicle.dead_zone_active = false
        data.vehicle.engine_state = "on"
        data.vehicle.engine_idle_timer = 0
        SafeSetBotData(botID, data)
    end
    local currentVeh = SafeGetVehicle(bot)
    if AI_Utils.IsValid(currentVeh) then
        local currentRoot = GetGlideRoot(currentVeh) or currentVeh
        if HasGlide() and IsGlideVehicle(currentRoot) then
            pcall(function()
                if currentRoot.TurnOff then currentRoot:TurnOff() end
                if currentRoot.SetEngineState then currentRoot:SetEngineState(false) end
            end)
            local id = currentRoot:EntIndex()
            EngineStopCooldown[id] = nil
        end
    end
    CleanupTankState(bot)
    CleanupHeliWeaponState(bot)
    if bot:InVehicle() then
        pcall(function() bot:ExitVehicle() end)
    end
    ResetBotAimTarget(bot)
end
local function GetAllCompanions()
    local bots = {}
    for _, ply in ipairs(player.GetBots()) do
        if AI_Utils.IsValid(ply) and ply:GetNWBool("IsAICompanion", false) then
            table.insert(bots, ply)
        end
    end
    return bots
end
local function GetCompanion()
    local bots = GetAllCompanions()
    return bots[1]
end
local function ComeBackToPlayer(bot)
    if not AI_Utils.IsValid(bot) then return end
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if data and data.owner then
        data.navigation.goal_pos = data.owner:GetPos()
        SetBotState(bot, AC.Companion.States.FOLLOW)
    end
end
hook.Add("PlayerEnteredVehicle", "AICompanion_AutoEnterWithOwner_v3", function(ply, vehicle, role)
    local root = GetGlideRoot(vehicle) or vehicle
    if not AI_Utils.IsValid(root) then return end
    local bots = GetAllCompanions()
    for _, bot in ipairs(bots) do
        if not AI_Utils.IsValid(bot) then continue end
        if bot:InVehicle() then continue end
        local botID = bot:EntIndex()
        local data = GetBotData(bot)
        if not data or data.owner ~= ply then continue end
        local hasEnemy = data.combat and IsValid(data.combat.target)
        local driverSeat = GetDriverSeat(root)
        local playerIsDriver = AI_Utils.IsValid(driverSeat) and SafeGetDriver(driverSeat) == ply
        if HasGlide() and IsGlideVehicle(root) and root.seats and #root.seats > 1 then
            local bestSeat = GetBestSeat(root, bot, hasEnemy, playerIsDriver, ply)
            if AI_Utils.IsValid(bestSeat) then
                pcall(function() bot:EnterVehicle(bestSeat) end)
                if bot:InVehicle() then
                    if data then
                        data.vehicle.locked_vehicle = root
                        data.vehicle.locked_seat = bestSeat
                        data.vehicle.sit_by_command = false
                        SafeSetBotData(botID, data)
                    end
                    if AI_Utils.IsValid(bot) then 
                        bot:ChatPrint("[AI] Сажусь в транспорт (Glide).") 
                    end
                    continue
                end
            end
        end
        local hl2Seat = FindNearestFreeHL2Seat(bot, root)
        if AI_Utils.IsValid(hl2Seat) then
            pcall(function() bot:EnterVehicle(hl2Seat) end)
            if bot:InVehicle() then
                if data then
                    data.vehicle.locked_vehicle = root
                    data.vehicle.locked_seat = hl2Seat
                    data.vehicle.sit_by_command = false
                    SafeSetBotData(botID, data)
                end
                if AI_Utils.IsValid(bot) then 
                    bot:ChatPrint("[AI] Сажусь вместе с вами.") 
                end
            end
            continue
        end
        if AI_Utils.IsValid(driverSeat) and not AI_Utils.IsValid(SafeGetDriver(driverSeat)) then
            pcall(function() bot:EnterVehicle(driverSeat) end)
            if bot:InVehicle() then
                if data then
                    data.vehicle.locked_vehicle = root
                    data.vehicle.locked_seat = driverSeat
                    data.vehicle.sit_by_command = false
                    SafeSetBotData(botID, data)
                end
            end
        end
    end
end)
hook.Add("PlayerLeaveVehicle", "AICompanion_OwnerLeftVehicle_v3", function(ply, vehicle)
    local bots = GetAllCompanions()
    for _, bot in ipairs(bots) do
        if not AI_Utils.IsValid(bot) then continue end
        local botID = bot:EntIndex()
        local data = GetBotData(bot)
        if not data or data.owner ~= ply then continue end
        if bot:InVehicle() and not data.vehicle.sit_by_command then
            local botVeh = nil
            pcall(function() botVeh = bot:GetVehicle() end)
            if AI_Utils.IsValid(botVeh) then
                local ownerRoot = GetGlideRoot(vehicle) or vehicle
                local botRoot = GetGlideRoot(botVeh) or botVeh
                if ownerRoot == botRoot then
                    ForceExit(bot)
                    if AI_Utils.IsValid(bot) then bot:ChatPrint("[AI] Владелец вышел, выхожу тоже.") end
                    continue
                end
                local botPos = SafeGetPos(bot)
                local ownerPos = SafeGetPos(ply)
                if botPos:Distance(ownerPos) < 300 then
                    ForceExit(bot)
                    if AI_Utils.IsValid(bot) then bot:ChatPrint("[AI] Владелец вышел, выхожу тоже.") end
                end
            end
        end
    end
end)
hook.Add("EntityRemoved", "AICompanion_VehicleDestroyed_v3", function(ent)
    if not AI_Utils.IsValid(ent) then return end
    local bot = GetCompanion()
    if not AI_Utils.IsValid(bot) then return end
    local botID = bot:EntIndex()
    local data = GetBotData(bot)
    if not data then return end
    if data.vehicle.sit_by_command and data.vehicle.locked_vehicle == ent then
        if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
        data.vehicle.sit_by_command = false
        data.vehicle.locked_vehicle = nil
        data.vehicle.locked_seat = nil
        data.vehicle.path = nil
        SafeSetBotData(botID, data)
        return
    end
    if bot:InVehicle() then
        local botVeh = nil
        pcall(function() botVeh = bot:GetVehicle() end)
        if botVeh == ent then
            pcall(function() bot:ExitVehicle() end)
            data.vehicle.sit_by_command = false
            data.vehicle.locked_vehicle = nil
            data.vehicle.locked_seat = nil
            data.vehicle.path = nil
            SafeSetBotData(botID, data)
            if AI_Utils.IsValid(bot) then bot:ChatPrint("[AI] Сиденье уничтожено!") end
            timer.Simple(0.1, function()
                if AI_Utils.IsValid(bot) then ComeBackToPlayer(bot) end
            end)
            return
        end
    end
    if IsHL2Seat(ent) then
        if data.vehicle.locked_seat == ent then
            if bot:InVehicle() then pcall(function() bot:ExitVehicle() end) end
            data.vehicle.sit_by_command = false
            data.vehicle.locked_vehicle = nil
            data.vehicle.locked_seat = nil
            data.vehicle.path = nil
            SafeSetBotData(botID, data)
            if AI_Utils.IsValid(bot) then bot:ChatPrint("[AI] Транспорт уничтожен!") end
            timer.Simple(0.1, function()
                if AI_Utils.IsValid(bot) then ComeBackToPlayer(bot) end
            end)
        end
    end
end)
hook.Add("CanExitVehicle", "AICompanion_BlockExit_v2", function(vehicle, ply)
    if not AI_Utils.IsValid(ply) then return end
    if not ply:GetNWBool("IsAICompanion", false) then return end
    local botID = ply:EntIndex()
    local data = GetBotData(ply)
    if data and data.vehicle.sit_by_command and AI_Utils.IsValid(data.vehicle.locked_vehicle) then
        if data.vehicle.locked_vehicle == vehicle then
            return false
        end
    end
    if data and not data.vehicle.sit_by_command then
        if data.owner and data.owner:InVehicle() then
            local ownerVeh = nil
            pcall(function() ownerVeh = data.owner:GetVehicle() end)
            if AI_Utils.IsValid(ownerVeh) then
                local ownerRoot = GetGlideRoot(ownerVeh) or ownerVeh
                local botRoot = GetGlideRoot(vehicle) or vehicle
                if ownerRoot == botRoot then
                    return false
                end
            end
            local botPos = SafeGetPos(ply)
            local ownerPos = SafeGetPos(data.owner)
            if botPos:Distance(ownerPos) < 300 then
                return false
            end
        end
    end
end)
hook.Add("PlayerDisconnected", "AI_TankStateCleanup_v3", function(ply)
    CleanupTankState(ply)
    CleanupHeliWeaponState(ply)
    ResetBotAimTarget(ply)
end)
hook.Add("PlayerDeath", "AI_TankStateDeathCleanup_v3", function(victim)
    if victim:GetNWBool("IsAICompanion", false) then
        CleanupTankState(victim)
        CleanupHeliWeaponState(victim)
        ResetBotAimTarget(victim)
    end
end)
_G.EnterDriverSeat = EnterDriverSeat
_G.FindNearestVehicle = FindNearestVehicle
_G.GetDriverSeat = GetDriverSeat
_G.GetGlideRoot = GetGlideRoot
_G.ForceExit = ForceExit
_G.GetAllCompanions = GetAllCompanions
_G.GetCompanion = GetCompanion
_G.ComeBackToPlayer = ComeBackToPlayer
_G.IsGlideVehicle = IsGlideVehicle
_G.ControlVehicle = ControlVehicle
_G.ControlGroundVehicle = ControlGroundVehicle
_G.ControlHeliWeapons = ControlHeliWeapons
_G.UpdateTankAim = UpdateTankAim
_G.ControlTankCannon = ControlTankCannon
_G.CalculateHeliInputs = CalculateHeliInputs
_G.ApplyVehicleInputs = ApplyVehicleInputs
_G.ApplyHL2VehicleCmd = ApplyHL2VehicleCmd
_G.StopVehicle = StopVehicle
_G.CheckVehicleObstacle = CheckVehicleObstacle
_G.GetAvoidanceDirection = GetAvoidanceDirection
_G.GetBestSeat = GetBestSeat
_G.EnterBestSeat = EnterBestSeat
_G.GetGlideVehicleType = GetGlideVehicleType
_G.GetAimTargetPos = GetAimTargetPos
_G.SetBotAimTarget = SetBotAimTarget
_G.ResetBotAimTarget = ResetBotAimTarget
print("[AI Vehicle] v5.2 загружен (исправлен AC.Companion.BotData nil)")
if HasGlide() then
    print("[AI Vehicle] Glide обнаружен, полная поддержка транспорта.")
else
    print("[AI Vehicle] Glide НЕ НАЙДЕН, работает только HL2 транспорт.")
    print("[AI Vehicle] Установите аддон Glide для вертолётов, танков и т.д.")
end