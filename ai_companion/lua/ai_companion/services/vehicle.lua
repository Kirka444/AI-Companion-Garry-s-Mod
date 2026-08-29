
local Vehicle = {}

function Vehicle:new(utils, config, state, data)
    local obj = {

        utils = utils,
        config = config,
        state = state,
        data = data,

        botmanager = nil,
        shared = nil,
        movement = nil,

        _initialized = false,
        _hasGlide = false,
        _const = nil,

        _tankState = {},
        _heliWeaponState = {},
        _engineStopCooldown = {},
        _ramState = {},
		_antiStuck = {},

        _hl2InForward = IN_FORWARD or 8,
        _hl2InBack = IN_BACK or 16,
        _hl2InLeft = IN_LEFT or 128,
        _hl2InRight = IN_RIGHT or 256,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Vehicle:init()
    if self._initialized then return end

    local locator = _G.AI_GetLocator()
    if locator then
        self.botmanager = locator:get("botmanager")
        self.shared = locator:get("shared")
        self.movement = locator:get("movement")
    end

    self._hasGlide = rawget(_G, "Glide") ~= nil

    if not self._hasGlide then
        _G.Glide = {
            VEHICLE_TYPE = {
                HELICOPTER = "helicopter",
                PLANE = "plane",
                TANK = "tank",
                BOAT = "boat",
                MOTORCYCLE = "motorcycle",
                CAR = "car"
            }
        }
        if self.utils then
            self.utils.LogInfo("Vehicle", "Glide не найден, функция транспорта ограничена.")
            self.utils.LogInfo("Vehicle", "Установите Glide для полной поддержки транспорта.")
        end
    end

    local magic = self.config:get("Magic") or {}
    local vehicleConfig = magic.Vehicle or {}
    self._const = vehicleConfig

    if self._hasGlide then
        self:SetupGlidePatches()
    end

    if SERVER then
        self:SetupHooks()
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Vehicle", "Сервис транспорта инициализирован, Glide: %s",
            self._hasGlide and "ДА" or "НЕТ")
    end
end

function Vehicle:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Vehicle:IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and math.abs(value) ~= math.huge
end

function Vehicle:SanitizeNumber(value, default)
    local default = default or 0
    if type(value) ~= "number" then return default end
    if value ~= value then return default end
    if math.abs(value) == math.huge then return default end
    return value
end

function Vehicle:SanitizeVector(v, fallback)
    local fallback = fallback or Vector(0, 0, 0)
    if type(v) ~= "Vector" then return Vector(fallback) end
    if not self:IsFiniteNumber(v.x) or not self:IsFiniteNumber(v.y) or not self:IsFiniteNumber(v.z) then
        return Vector(fallback)
    end
    return v
end

function Vehicle:SafeGetClass(ent)
    if not self:IsValid(ent) then return "invalid" end
    local ok, class = pcall(function() return ent:GetClass() end)
    return (ok and class) or "error"
end

function Vehicle:SafeGetPos(ent)
    if not self:IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:GetPos() end)
    return (ok and pos) or Vector()
end

function Vehicle:SafeGetForward(ent)
    if not self:IsValid(ent) then return Vector(1, 0, 0) end
    local ok, fw = pcall(function() return ent:GetForward() end)
    return (ok and fw) or Vector(1, 0, 0)
end

function Vehicle:SafeGetRight(ent)
    if not self:IsValid(ent) then return Vector(0, 1, 0) end
    local ok, r = pcall(function() return ent:GetRight() end)
    return (ok and r) or Vector(0, 1, 0)
end

function Vehicle:SafeGetUp(ent)
    if not self:IsValid(ent) then return Vector(0, 0, 1) end
    local ok, u = pcall(function() return ent:GetUp() end)
    return (ok and u) or Vector(0, 0, 1)
end

function Vehicle:SafeGetVelocity(ent)
    if not self:IsValid(ent) then return Vector() end
    local ok, vel = pcall(function() return ent:GetVelocity() end)
    return (ok and vel) or Vector()
end

function Vehicle:SafeGetDriver(ent)
    if not self:IsValid(ent) then return nil end
    local ok, driver = pcall(function() return ent:GetDriver() end)
    return (ok and driver) or nil
end

function Vehicle:SafeGetVehicle(ply)
    if not self:IsValid(ply) then return nil end
    local ok, veh = pcall(function() return ply:GetVehicle() end)
    return (ok and veh) or nil
end

function Vehicle:SafeWorldSpaceCenter(ent)
    if not self:IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:WorldSpaceCenter() end)
    return (ok and pos) or self:SafeGetPos(ent)
end

function Vehicle:SafeGetParent(ent)
    if not self:IsValid(ent) then return nil end
    local ok, parent = pcall(function() return ent:GetParent() end)
    return (ok and parent) or nil
end

function Vehicle:SafeInVehicle(ent)
    if not self:IsValid(ent) then return false end
    local ok, iv = pcall(function() return ent:InVehicle() end)
    return ok and iv
end

function Vehicle:SafeAlive(ent)
    if not self:IsValid(ent) then return false end
    local ok, alive = pcall(function() return ent:Alive() end)
    return ok and alive
end

function Vehicle:HasGlide()
    return self._hasGlide
end

function Vehicle:IsGlideVehicle(ent)
    if not self:HasGlide() then return false end
    if not self:IsValid(ent) then return false end
    if ent.IsGlideVehicle == true then return true end
    if isfunction(ent.IsGlideVehicle) then
        local ok, result = pcall(function() return ent:IsGlideVehicle() end)
        return ok and result
    end
    return false
end

function Vehicle:GetGlideRoot(vehicle)
    if not self:IsValid(vehicle) then return nil end
    if not self:HasGlide() then return nil end
    if self:IsGlideVehicle(vehicle) then return vehicle end

    local parent = self:SafeGetParent(vehicle)
    if self:IsValid(parent) and self:IsGlideVehicle(parent) then return parent end

    if vehicle.vehicle and self:IsValid(vehicle.vehicle) and self:IsGlideVehicle(vehicle.vehicle) then
        return vehicle.vehicle
    end
    return nil
end

function Vehicle:GetGlideVehicleType(vehicle)
    if not self:IsValid(vehicle) then return "unknown" end
    if not self:HasGlide() then return "unknown" end
    if not self:IsGlideVehicle(vehicle) then return "unknown" end
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

function Vehicle:IsHL2Seat(ent)
    if not self:IsValid(ent) then return false end
    local class = self:SafeGetClass(ent)
    return class == "prop_vehicle_prisoner_pod"
        or class == "prop_vehicle_driveable"
        or string.match(class, "^prop_vehicle_")
end

function Vehicle:IsHL2Vehicle(ent)
    if not self:IsValid(ent) then return false end
    local class = self:SafeGetClass(ent)
    return class == "prop_vehicle_jeep"
        or class == "prop_vehicle_airboat"
        or class == "prop_vehicle_jeep_old"
        or class == "prop_vehicle_driveable"
end

function Vehicle:GetHL2VehicleSeats(parentVehicle)
    if not self:IsValid(parentVehicle) then return {} end
    local seats = {}
    local parent = self:GetGlideRoot(parentVehicle) or parentVehicle

    for _, ent in ipairs(ents.GetAll()) do
        if self:IsValid(ent) and self:IsHL2Seat(ent) then
            local entParent = self:SafeGetParent(ent)
            if entParent == parent or entParent == parentVehicle then
                table.insert(seats, ent)
            else
                local dist = self:SafeGetPos(ent):Distance(self:SafeGetPos(parent))
                if dist < 200 then
                    table.insert(seats, ent)
                end
            end
        end
    end
    return seats
end

function Vehicle:FindNearestFreeHL2Seat(bot, vehicle)
    if not self:IsValid(bot) or not self:IsValid(vehicle) then return nil end
    local seats = self:GetHL2VehicleSeats(vehicle)
    if #seats == 0 then return nil end

    local botPos = self:SafeGetPos(bot)
    local bestSeat, bestDist = nil, 999999

    for _, seat in ipairs(seats) do
        if self:IsValid(seat) then
            local driver = self:SafeGetDriver(seat)
            if not self:IsValid(driver) then
                local dist = botPos:Distance(self:SafeGetPos(seat))
                if dist < bestDist then
                    bestDist = dist
                    bestSeat = seat
                end
            end
        end
    end
    return bestSeat
end

function Vehicle:PatchVehicleInputs(vehicle)
    if not self:IsValid(vehicle) then return end
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

function Vehicle:SetupGlidePatches()
    if not self:HasGlide() then return end

    local selfRef = self

    hook.Add("InitPostEntity", "AI_Vehicle_PatchAllVehicles", function()
        for _, ent in ipairs(ents.GetAll()) do
            if selfRef:IsValid(ent) and selfRef:IsGlideVehicle(ent) then
                selfRef:PatchVehicleInputs(ent)
            end
        end
    end)

    hook.Add("OnEntityCreated", "AI_Vehicle_PatchNewVehicle", function(ent)
        if selfRef:IsValid(ent) and selfRef:IsGlideVehicle(ent) then
            timer.Simple(0.1, function()
                if selfRef:IsValid(ent) then
                    selfRef:PatchVehicleInputs(ent)
                end
            end)
        end
    end)
end

function Vehicle:ApplyHL2VehicleCmd(cmd, throttle, steer)
    if not cmd then return end
    local throttle = self:SanitizeNumber(throttle, 0)
    local steer = self:SanitizeNumber(steer, 0)

    pcall(function()
        local buttons = 0

        if throttle > 0.05 then
            buttons = buttons + self._hl2InForward
        elseif throttle < -0.05 then
            buttons = buttons + self._hl2InBack
        end

        if steer > 0.15 then
            buttons = buttons + self._hl2InRight + (IN_MOVERIGHT or 1024)
        elseif steer < -0.15 then
            buttons = buttons + self._hl2InLeft + (IN_MOVELEFT or 512)
        end

        cmd:SetForwardMove(math.Clamp(throttle * 450, -450, 450))

        cmd:SetSideMove(math.Clamp(steer * 450, -450, 450))
        cmd:SetUpMove(0)
        cmd:SetButtons(buttons)
    end)
end

function Vehicle:ApplyVehicleInputs(vehicle, inputs, seatIndex)
    if not self:IsValid(vehicle) then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ApplyVehicleInputs: INVALID vehicle")
        end
        return
    end
    if not self:HasGlide() then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ApplyVehicleInputs: Glide not available")
        end
        return
    end
    if not inputs or type(inputs) ~= "table" then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ApplyVehicleInputs: INVALID inputs")
        end
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
            vehicle:SetInputFloat(seatIndex, "throttle", sanitized.throttle or 0)
            vehicle:SetInputFloat(seatIndex, "pitch", sanitized.pitch or 0)
            vehicle:SetInputFloat(seatIndex, "roll", sanitized.roll or 0)
            vehicle:SetInputFloat(seatIndex, "yaw", sanitized.yaw or 0)
            vehicle:SetInputFloat(seatIndex, "accelerate", sanitized.accelerate or 0)
            vehicle:SetInputFloat(seatIndex, "steer", sanitized.steer or 0)
        end
        if vehicle.SetInputBool then
            vehicle:SetInputBool(seatIndex, "brake", (sanitized.brake and sanitized.brake > 0) or false)
            vehicle:SetInputBool(seatIndex, "handbrake", (sanitized.handbrake and sanitized.handbrake > 0) or false)
            if sanitized.attack ~= nil then
                vehicle:SetInputBool(seatIndex, "attack", sanitized.attack or false)
            end
            if sanitized.fire ~= nil then
                vehicle:SetInputBool(seatIndex, "fire", sanitized.fire or false)
            end
        end
    end)
end

function Vehicle:GetAimTargetPos(ent)
    if not self:IsValid(ent) then return Vector() end
    if ent.IsNPC and ent:IsNPC() then
        local names = {"ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1"}
        for _, n in ipairs(names) do
            local ok, bone = pcall(function() return ent:LookupBone(n) end)
            if ok and bone then
                local ok2, pos = pcall(function() return ent:GetBonePosition(bone) end)
                if ok2 and pos and pos:LengthSqr() > 0.01 then
                    return self:SanitizeVector(pos, Vector())
                end
            end
        end
    end
    return self:SanitizeVector(self:SafeWorldSpaceCenter(ent), Vector())
end

function Vehicle:ResetBotAimTarget(bot)
    if not self:IsValid(bot) then return end
    if not self:HasGlide() then return end

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

function Vehicle:SetBotAimTarget(bot, pos)
    if not self:IsValid(bot) then return end
    if not self:HasGlide() then return end

    local pos = self:SanitizeVector(pos, Vector())
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

function Vehicle:GetHeliWeaponState(bot)
    if not self:IsValid(bot) then return nil end
    if not self:HasGlide() then return nil end

    local id = bot:EntIndex()
    self._heliWeaponState[id] = self._heliWeaponState[id] or {
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
    return self._heliWeaponState[id]
end

function Vehicle:CleanupHeliWeaponState(bot)
    if not self:IsValid(bot) then return end
    self._heliWeaponState[bot:EntIndex()] = nil
end

function Vehicle:GetHeliWeaponPos(root)
    if not self:IsValid(root) then return Vector() end
    local pos = self:SanitizeVector(self:SafeWorldSpaceCenter(root), Vector())
    local fw = self:SanitizeVector(self:SafeGetForward(root), Vector(1,0,0))
    local up = self:SanitizeVector(self:SafeGetUp(root), Vector(0,0,1))
    return pos + fw * 80 + up * (-20)
end

function Vehicle:CanSeeTargetFromPos(fromPos, target, bot)
    if not self:IsValid(target) then return false end
    fromPos = self:SanitizeVector(fromPos, Vector())
    local targetPos = self:SanitizeVector(self:GetAimTargetPos(target), Vector())
    if fromPos:IsZero() or targetPos:IsZero() then return false end

    local tr = util.TraceLine({
        start = fromPos,
        endpos = targetPos,
        filter = function(ent)
            if not self:IsValid(ent) then return false end
            if ent == bot then return false end
            local c = self:SafeGetClass(ent)
            return c ~= "player" and not (self:IsGlideVehicle(ent)) and c ~= "glide_rotor"
        end,
        mask = MASK_SOLID
    })
    return tr.Entity == target or not tr.Hit
end

function Vehicle:FireHeliBullet(bot, root, target)
    if not self:IsValid(bot) or not self:IsValid(root) or not self:IsValid(target) then return false end
    if not self:HasGlide() then return false end

    local state = self:GetHeliWeaponState(bot)
    if not state then return false end

    local now = CurTime()
    if now - state.lastFireTime < state.fireCooldown then return false end
    if now - state.lastBurstEnd < state.burstPause and state.burstCount >= state.burstMax then return false end

    if state.burstCount >= state.burstMax then
        state.burstCount = 0
        state.lastBurstEnd = now
        return false
    end

    local weaponPos = self:SanitizeVector(self:GetHeliWeaponPos(root), Vector())
    local targetPos = self:SanitizeVector(self:GetAimTargetPos(target), Vector())
    if weaponPos:IsZero() or targetPos:IsZero() then return false end

    local dist = self:SanitizeNumber(weaponPos:Distance(targetPos), 0)
    if dist > state.maxRange or dist < state.minRange then return false end
    if not self:CanSeeTargetFromPos(weaponPos, target, bot) then return false end

    local targetVel = self:SanitizeVector(self:SafeGetVelocity(target), Vector())
    local bulletSpeed = 8000
    local timeToTarget = self:SanitizeNumber(dist / bulletSpeed, 0)
    local aimPos = self:SanitizeVector(targetPos + targetVel * timeToTarget, targetPos)
    local dir = self:SanitizeVector(aimPos - weaponPos, Vector())
    if dir:LengthSqr() < 0.001 then return false end
    dir:Normalize()

    if SERVER then
        pcall(function() bot:GiveAmmo(10, "SMG1", true) end)
    end

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

function Vehicle:FireHeliMissile(bot, root, target)
    if not self:IsValid(bot) or not self:IsValid(root) or not self:IsValid(target) then return false end
    if not self:HasGlide() then return false end

    local state = self:GetHeliWeaponState(bot)
    if not state then return false end

    local now = CurTime()
    if now - state.lastMissileTime < state.missileCooldown then return false end

    local weaponPos = self:SanitizeVector(self:GetHeliWeaponPos(root), Vector())
    local targetPos = self:SanitizeVector(self:GetAimTargetPos(target), Vector())
    local dist = self:SanitizeNumber(weaponPos:Distance(targetPos), 0)
    if dist > state.maxRange * 1.5 or dist < state.minRange * 2 then return false end
    if not self:CanSeeTargetFromPos(weaponPos, target, bot) then return false end

    local missile = ents.Create("glide_missile")
    if not self:IsValid(missile) then return false end

    local side = (state.lastMissileTime % 2 < 1) and 1 or -1
    local spawnPos = self:SanitizeVector(weaponPos + self:SafeGetRight(root) * (30 * side), weaponPos)
    missile:SetPos(spawnPos)

    local missileDir = self:SanitizeVector(targetPos - spawnPos, Vector(1,0,0))
    if missileDir:LengthSqr() < 0.001 then
        SafeRemoveEntity(missile)
        return false
    end
    missile:SetAngles(missileDir:Angle())
    missile:Spawn()
    missile:SetupMissile(bot, root)
    missile:SetTarget(target)

    local phys = missile:GetPhysicsObject()
    if self:IsValid(phys) then
        phys:SetVelocityInstantaneous(self:SafeGetForward(root) * 300 + self:SafeGetVelocity(root))
    end

    local eff = EffectData()
    eff:SetOrigin(spawnPos)
    eff:SetAngles(self:SafeGetForward(root):Angle())
    eff:SetScale(2)
    util.Effect("MuzzleFlash", eff)

    root:EmitSound("glide/weapons/missile_fire.wav", 90, 100, 0.8)

    state.lastMissileTime = now
    if target:IsPlayer() and Glide.SendMissileDanger then
        Glide.SendMissileDanger(target, missile)
    end

    return true
end

function Vehicle:ControlHeliWeapons(bot, root, target, isEnemy)
    if not self:IsValid(bot) or not self:IsValid(root) then return end
    if not self:HasGlide() then return end

    if not isEnemy or not self:IsValid(target) then
        local state = self:GetHeliWeaponState(bot)
        if state and state.isFiring then
            state.isFiring = false
            state.burstCount = 0
        end
        return
    end

    local fallbackPos = self:SanitizeVector(self:SafeGetPos(root), Vector())
    local aimPos = self:SanitizeVector(self:GetAimTargetPos(target), fallbackPos)
    local targetVel = self:SanitizeVector(self:SafeGetVelocity(target), Vector())
    aimPos = self:SanitizeVector(aimPos + targetVel * 0.3, fallbackPos)

    self:SetBotAimTarget(bot, aimPos)
    self:FireHeliBullet(bot, root, target)

    local dist = self:SanitizeNumber(self:SafeGetPos(root):Distance(self:GetAimTargetPos(target)), 0)
    if dist > 800 and math.random() < 0.3 then
        self:FireHeliMissile(bot, root, target)
    end
end

function Vehicle:GetTerrainHeight(pos)
    local pos = self:SanitizeVector(pos, Vector())
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 1000),
        endpos = pos - Vector(0, 0, 1000),
        mask = MASK_SOLID,
        filter = function(ent)
            if not self:IsValid(ent) then return false end
            local c = self:SafeGetClass(ent)
            return c ~= "player" and c:sub(1,4) ~= "npc_"
        end
    })
    return tr.Hit and self:SanitizeNumber(tr.HitPos.z, pos.z - 1000) or pos.z - 1000
end

function Vehicle:ApplyHeliDownForce(root, target, desiredPos)
    if not self:IsValid(root) or not self:IsValid(target) or not desiredPos then return end
    if not self:HasGlide() then return end

    local const = self._const or {}
    local vehPos = self:SanitizeVector(self:SafeGetPos(root), Vector())
    local targetPos = self:SanitizeVector(self:GetAimTargetPos(target), vehPos)
    local checkPosSafe = self:SanitizeVector(desiredPos, targetPos)
    local heightAboveTarget = vehPos.z - checkPosSafe.z

    if heightAboveTarget < (const.HeliSoftAltLimit or 200) then return end

    local phys
    pcall(function() phys = root:GetPhysicsObject() end)
    if not phys then return end

    local ok, isValid = pcall(function() return phys:IsValid() end)
    if not ok or not isValid then return end

    local mass = 0
    pcall(function() mass = phys:GetMass() end)
    mass = self:SanitizeNumber(mass, 500)
    if mass <= 0 then return end

    local up = self:SanitizeVector(self:SafeGetUp(root), Vector(0,0,1))
    local overshoot = heightAboveTarget - (const.HeliSoftAltLimit or 200)
    if overshoot < (const.HeliForceDeadZone or 30) then return end

    local forceMagnitude = math.min(overshoot * mass * 0.8, const.HeliDownForceMax or 8000)
    pcall(function()
        phys:ApplyForceCenter((-up) * forceMagnitude)
    end)
end

function Vehicle:CalculateHeliInputs(vehicle, target, isEnemy)
    if not self:IsValid(vehicle) or not self:IsValid(target) then
        if self.utils then
            self.utils.LogDebug("Vehicle", "CalculateHeliInputs: INVALID params")
        end
        return { throttle = 0.5, pitch = 0, roll = 0, yaw = 0 }
    end
    if not self:HasGlide() then
        if self.utils then
            self.utils.LogDebug("Vehicle", "CalculateHeliInputs: Glide not available")
        end
        return { throttle = 0.5, pitch = 0, roll = 0, yaw = 0 }
    end

    local const = self._const or {}
    local dt = math.Clamp(FrameTime(), 0.001, 0.05)
    local now = CurTime()

    vehicle._ap = vehicle._ap or {}
    local ap = vehicle._ap

    local vehPos = self:SanitizeVector(self:SafeGetPos(vehicle), Vector())
    local vehVel = self:SanitizeVector(self:SafeGetVelocity(vehicle), Vector())
    local forward = self:SanitizeVector(self:SafeGetForward(vehicle), Vector(1,0,0))
    local right = self:SanitizeVector(self:SafeGetRight(vehicle), Vector(0,1,0))

    local forwardH = Vector(forward.x, forward.y, 0)
    if forwardH:LengthSqr() < 0.001 then forwardH = Vector(1, 0, 0) end
    forwardH:Normalize()

    local rightH = Vector(right.x, right.y, 0)
    if rightH:LengthSqr() < 0.001 then rightH = Vector(0, 1, 0) end
    rightH:Normalize()

    local targetPos = self:SanitizeVector(self:GetAimTargetPos(target), vehPos)
    local targetVel = self:SanitizeVector(self:SafeGetVelocity(target), Vector())
    targetVel.z = 0
    local predictedPos = self:SanitizeVector(targetPos + targetVel * 0.4, targetPos)

    local desiredPos

    if isEnemy then
        ap.circleAng = (ap.circleAng or 0) + dt * 0.35
        local radius = 280
        local tFw = self:SanitizeVector(self:SafeGetForward(target), Vector(1,0,0))
        local tRt = self:SanitizeVector(self:SafeGetRight(target), Vector(0,1,0))
        local offset = tRt * math.cos(ap.circleAng) * radius
                     + tFw * math.sin(ap.circleAng) * radius * 0.3
        desiredPos = self:SanitizeVector(predictedPos + offset, predictedPos)
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
                dir = self:SanitizeVector(self:SafeGetForward(target), Vector(1,0,0))
            end
            dir.z = 0
            if dir:LengthSqr() < 0.001 then dir = Vector(1, 0, 0) end
            dir:Normalize()

            ap.followPos = self:SanitizeVector(predictedPos - dir * 180, predictedPos)
            ap.followPos.z = targetPos.z + 130
            ap.lastFollowOwnerPos = targetPos
        end
        desiredPos = ap.followPos
    end

    desiredPos = self:SanitizeVector(desiredPos, targetPos + Vector(0,0,130))

    local toDesired = desiredPos - vehPos
    local horiz = Vector(toDesired.x, toDesired.y, 0)
    local distXY = self:SanitizeNumber(horiz:Length(), 0)

    local dirH = forwardH
    if distXY > 1 then
        local norm = horiz:GetNormalized()
        if self:IsFiniteNumber(norm.x) and self:IsFiniteNumber(norm.y) and self:IsFiniteNumber(norm.z) then
            dirH = norm
        end
    end

    if distXY < (const.HeliFollowDeadZone or 100) and not isEnemy then
        return { throttle = 0.5, pitch = 0, roll = 0, yaw = 0 }
    end

	local maxSpeed = tonumber(isEnemy and (const.HeliEnemyMaxSpeed or 400) or (const.HeliFollowMaxSpeed or 240)) or 240
	local approachDist = tonumber(isEnemy and (const.HeliEnemyApproachDist or 200) or (const.HeliFollowApproachDist or 350)) or 350

	local desiredSpeed = maxSpeed
	if distXY < approachDist then
		desiredSpeed = maxSpeed * (distXY / approachDist)
	end

	desiredSpeed = math.max(tonumber(desiredSpeed) or 0, 0)
	desiredSpeed = self:SanitizeNumber(desiredSpeed, 0)

    local velH = Vector(vehVel.x, vehVel.y, 0)
    local currentSpeed = self:SanitizeNumber(velH:Length(), 0)

    if currentSpeed > desiredSpeed then
        desiredSpeed = desiredSpeed * (1 - (const.HeliDampingFactor or 0.10)) + desiredSpeed * (const.HeliDampingFactor or 0.10)
    end

    local desiredVel = dirH * desiredSpeed
    local velError = desiredVel - velH
    local fwdErr = self:SanitizeNumber(velError:Dot(forwardH), 0)
    local rightErr = self:SanitizeNumber(velError:Dot(rightH), 0)

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

    local pitchInput = math.Clamp(fwdErr / 350, -(const.HeliMaxPitch or 0.28), const.HeliMaxPitch or 0.28)
    local rollInput = math.Clamp(yawInput * 0.25 + rightErr / 700, -(const.HeliMaxRoll or 0.28), const.HeliMaxRoll or 0.28)

    if math.abs(yawInput) > 0.5 then
        pitchInput = pitchInput * 0.3
    end

	local targetHeight = tonumber(desiredPos.z) or 0
	local vehPosZ = tonumber(vehPos.z) or 0
	local heightError = targetHeight - vehPosZ

	local vehVelZ = tonumber(vehVel.z) or 0
	local throttleInput = 0.5 + heightError * 0.0035 - vehVelZ * 0.005

	if math.abs(heightError) < (const.HeliHeightDeadZone or 20) then
		throttleInput = 0.5
	elseif heightError > 60 then
		throttleInput = math.max(tonumber(throttleInput) or 0.5, 0.65)
	elseif heightError < -60 then
		throttleInput = math.min(tonumber(throttleInput) or 0.5, 0.35)
	end

    self:ApplyHeliDownForce(vehicle, target, desiredPos)

	local groundZ = self:SanitizeNumber(self:GetTerrainHeight(vehPos), vehPos.z - 1000)
	local heightAboveGround = vehPos.z - groundZ

	if heightAboveGround < 70 then

		throttleInput = math.max(tonumber(throttleInput) or 0.5, 0.85)
		pitchInput = math.Clamp(tonumber(pitchInput) or 0, -0.12, 0.12)
		rollInput = math.Clamp(tonumber(rollInput) or 0, -0.12, 0.12)
	end

	throttleInput = math.Clamp(tonumber(throttleInput) or 0.5, -1, 1)
	if not self:IsFiniteNumber(throttleInput) then throttleInput = 0.5 end

    local smooth = math.Clamp(dt * 1.6, 0, 1)
    ap.p = (ap.p or 0) + (pitchInput - (ap.p or 0)) * smooth
    ap.r = (ap.r or 0) + (rollInput - (ap.r or 0)) * smooth
    ap.y = (ap.y or 0) + (yawInput - (ap.y or 0)) * smooth
    ap.t = (ap.t or 0.5) + (throttleInput - (ap.t or 0.5)) * smooth

    ap.t = self:SanitizeNumber(ap.t, 0.5)
    ap.p = self:SanitizeNumber(ap.p, 0)
    ap.r = self:SanitizeNumber(ap.r, 0)
    ap.y = self:SanitizeNumber(ap.y, 0)

	local result = {
		throttle = math.Clamp(tonumber(ap.t) or 0.5, -1, 1),
		pitch = math.Clamp(tonumber(ap.p) or 0, -1, 1),
		roll = math.Clamp(tonumber(ap.r) or 0, -1, 1),
		yaw = math.Clamp(tonumber(ap.y) or 0, -1, 1)
	}

    return result
end

function Vehicle:GetTankState(bot)
    if not self:IsValid(bot) then return nil end
    if not self:HasGlide() then return nil end

    local id = bot:EntIndex()
    self._tankState[id] = self._tankState[id] or {
        lastFireTime = 0,
        fireCooldown = 2.0,
        aimStartTime = 0,
        isAiming = false,
        minAimTime = 1.5,
        attackHeldUntil = 0,
        aimSetTime = nil
    }
    return self._tankState[id]
end

function Vehicle:CleanupTankState(bot)
    if not self:IsValid(bot) then return end
    self._tankState[bot:EntIndex()] = nil
end

function Vehicle:ReleaseTankAttack(root)
    if not self:HasGlide() then return end
    self:ApplyVehicleInputs(root, {attack = false, fire = false})
end

function Vehicle:UpdateTankAim(bot, root, target, isEnemy)
    if not self:IsValid(bot) or not self:IsValid(root) then return end
    if not self:HasGlide() then return end

    local aimPos
    if isEnemy and self:IsValid(target) then
        local targetPos = self:SanitizeVector(self:GetAimTargetPos(target), Vector())
        local targetVel = Vector()
        pcall(function()
            if target.GetVelocity then targetVel = target:GetVelocity()
            elseif target.GetAbsVelocity then targetVel = target:GetAbsVelocity() end
        end)
        targetVel = self:SanitizeVector(targetVel, Vector())
        local bulletSpeed = 3000
        pcall(function()
            if root.weapons and root.weapons[1] and root.weapons[1].ProjectileSpeed then
                bulletSpeed = root.weapons[1].ProjectileSpeed
            end
        end)
        local dist = self:SanitizeNumber(targetPos:Distance(self:SafeGetPos(root)), 0)
        local timeToTarget = dist / math.max(bulletSpeed, 100)
        aimPos = self:SanitizeVector(targetPos + targetVel * timeToTarget, targetPos)
        pcall(function()
            if root.weapons and root.weapons[1] and root.weapons[1].Gravity then
                aimPos = aimPos - Vector(0, 0, root.weapons[1].Gravity * timeToTarget * timeToTarget * 0.5)
            end
        end)
    else
        if self:IsValid(target) then
            aimPos = self:SanitizeVector(self:GetAimTargetPos(target), Vector())
        else
            aimPos = self:SanitizeVector(self:SafeGetPos(root) + self:SafeGetForward(root) * 1000 + self:SafeGetUp(root) * 50, Vector())
        end
    end

    self:SetBotAimTarget(bot, aimPos)

    pcall(function()
        if root.SetTurretAngle and root.GetTurretOrigin then
            local origin = self:SanitizeVector(root:GetTurretOrigin(), Vector())
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

function Vehicle:ControlTankCannon(bot, vehicle, target)
    if not self:IsValid(bot) or not self:IsValid(vehicle) or not self:IsValid(target) then
        self:ResetBotAimTarget(bot)
        return false
    end
    if not self:HasGlide() then return false end

    local root = self:GetGlideRoot(vehicle) or vehicle
    if not self:IsValid(root) then
        self:ResetBotAimTarget(bot)
        return false
    end

    local state = self:GetTankState(bot)
    if not state then return false end

    local now = CurTime()
    local botID = bot:EntIndex()

    if state.attackHeldUntil and now > state.attackHeldUntil then
        self:ReleaseTankAttack(root)
        state.attackHeldUntil = nil
    end

    if now - state.lastFireTime < state.fireCooldown then return true end

    local targetPos = self:SanitizeVector(self:GetAimTargetPos(target), Vector())
    local vehPos = self:SanitizeVector(self:SafeWorldSpaceCenter(vehicle), Vector())
    local dist = self:SanitizeNumber(targetPos:Distance(vehPos), 0)

    if dist < 120 then
        self:ResetBotAimTarget(bot)
        return false
    end

    local aimPos = self:SanitizeVector(bot._aimPos or targetPos, targetPos)
    local aimError = 1.0
    local turretDir = nil
    local turretOrigin = vehPos

    pcall(function() turretOrigin = self:SanitizeVector(root:GetTurretOrigin(), vehPos) end)
    pcall(function() turretDir = root:GetTurretAimDirection() end)

    if turretDir then
        local toTarget = aimPos - turretOrigin
        if toTarget:LengthSqr() > 0.001 then
            toTarget:Normalize()
            aimError = turretDir:Dot(toTarget)
        end
    end

    if aimError < 0.92 then return true end

    self:ApplyVehicleInputs(root, {attack = true, fire = true})
    state.lastFireTime = now
    state.aimSetTime = nil
    state.attackHeldUntil = now + 0.15

    local timerName = "AI_TankFire_" .. botID
    if timer.Exists(timerName) then timer.Remove(timerName) end
    timer.Create(timerName, 0.2, 1, function()
        local currentRoot = self:GetGlideRoot(vehicle) or vehicle
        if self:IsValid(currentRoot) and currentRoot == root then
            self:ReleaseTankAttack(root)
        end
        timer.Remove(timerName)
    end)

    return true
end

function Vehicle:StopVehicle(root, vehicle, cmd)
    if not self:IsValid(root) then
        if self.utils then
            self.utils.LogDebug("Vehicle", "StopVehicle: INVALID root")
        end
        return
    end

    local driverSeat = self:GetDriverSeat(root)
    if self:IsValid(driverSeat) then
        local driver = self:SafeGetDriver(driverSeat)
        if not self:IsValid(driver) or not driver:GetNWBool("IsAICompanion", false) then
            if self.utils then
                self.utils.LogDebug("Vehicle", "StopVehicle: driver not AI")
            end
            return
        end
    end

    if self.utils then
        self.utils.LogDebug("Vehicle", "StopVehicle: stopping " .. self:SafeGetClass(root))
    end

    if self:IsHL2Vehicle(vehicle) then
        if cmd then
            self:ApplyHL2VehicleCmd(cmd, 0, 0)
        end
        return
    end

    if self:HasGlide() and self:IsGlideVehicle(root) then
        local id = root:EntIndex()
        local now = CurTime()
        if not self._engineStopCooldown[id] or now - self._engineStopCooldown[id] >= 2.0 then
            self._engineStopCooldown[id] = now
            pcall(function()
                if root.TurnOff then root:TurnOff() end
                if root.SetEngineState then root:SetEngineState(false) end
            end)
        end

        self:ApplyVehicleInputs(root, {
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

function Vehicle:CheckVehicleObstacle(vehicle, direction, distance)
    if not self:IsValid(vehicle) then return false, nil, distance end
    distance = distance or 350

    local root = self:GetGlideRoot(vehicle) or vehicle
    if not self:IsValid(root) then return false, nil, distance end

    local vehPos = self:SafeGetPos(root)
    local forward = direction and self:SanitizeVector(direction, self:SafeGetForward(root)) or self:SafeGetForward(root)
    forward.z = 0
    if forward:LengthSqr() < 0.001 then forward = Vector(1, 0, 0) end
    forward:Normalize()

    local right = self:SafeGetRight(root)
    right.z = 0
    if right:LengthSqr() < 0.001 then right = Vector(0, 1, 0) end
    right:Normalize()

    local up = self:SafeGetUp(root)
    local filter = {vehicle, root}
    local parent = self:SafeGetParent(root)
    if self:IsValid(parent) then table.insert(filter, parent) end

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
            local class = self:SafeGetClass(ent)
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

function Vehicle:GetAvoidanceDirection(vehicle, targetDir, hitNormal)
    if not hitNormal then return targetDir end

    local forward = self:SafeGetForward(vehicle)
    local right = self:SafeGetRight(vehicle)

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

function Vehicle:GetRamState(bot)
    if not self:IsValid(bot) then return nil end
    local id = bot:EntIndex()
    if not self._ramState[id] then
        self._ramState[id] = {
            lastRamTime = 0,
            ramCooldown = 1.0,
            lastRamTarget = nil,
            hitCount = 0,
        }
    end
    return self._ramState[id]
end

function Vehicle:HandleRamDamage(bot, root, vehicle, target, dist)
    if not self:IsValid(bot) or not self:IsValid(root) or not self:IsValid(target) then return end
    if not self:SafeAlive(target) then return end

    local const = self._const or {}
    local ramState = self:GetRamState(bot)
    if not ramState then return end

    local now = CurTime()

    local collisionDist = const.RamCollisionDist or 120

    if target:IsPlayer() then
        collisionDist = const.RamCollisionDistPlayer or 100
    end

    if dist > collisionDist then return end

    if now - ramState.lastRamTime < ramState.ramCooldown then return end

    local vehVel = self:SafeGetVelocity(root)
    local speed = vehVel:Length()

    local minSpeedForDamage = const.RamMinSpeed or 100
    if speed < minSpeedForDamage then return end

    local baseDamage = const.RamBaseDamage or 25
    local speedMultiplier = const.RamSpeedMultiplier or 0.15
    local damage = baseDamage + (speed * speedMultiplier)

    if ramState.lastRamTarget == target then
        ramState.hitCount = ramState.hitCount + 1
        damage = damage * (1 + ramState.hitCount * 0.1)
    else
        ramState.hitCount = 1
        ramState.lastRamTarget = target
    end

    local maxDamage = const.RamMaxDamage or 100
    damage = math.min(damage, maxDamage)
    damage = math.Round(damage)

    local dmgInfo = DamageInfo()
    dmgInfo:SetDamage(damage)
    dmgInfo:SetAttacker(bot)
    dmgInfo:SetInflictor(root)
    dmgInfo:SetDamageType(DMG_CRUSH)

    local fwd = self:SafeGetForward(root)
    dmgInfo:SetDamageForce(fwd * speed * 2)
    dmgInfo:SetDamagePosition(self:SafeGetPos(target))

    pcall(function()
        target:TakeDamageInfo(dmgInfo)
    end)

    ramState.lastRamTime = now

    local impactPos = self:SafeGetPos(root) + fwd * 60
    local eff = EffectData()
    eff:SetOrigin(impactPos)
    eff:SetScale(0.5)
    util.Effect("Impact", eff)

    if SERVER then
        root:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 85, 100, 0.8)
    end

    if self.utils then
        self.utils.LogDebug("Vehicle", string.format(
            "RAM HIT! bot=%s target=%s damage=%d speed=%.0f",
            bot:Nick(), self:SafeGetClass(target), damage, speed
        ))
    end
end

function Vehicle:GetAntiStuckState(root, bot)
    self._antiStuck = self._antiStuck or {}

    local id = nil

    if self:IsValid(root) then
        id = root:EntIndex()
    end

    if (not id or id == 0) and self:IsValid(bot) then
        id = bot:EntIndex()
    end

    if not id or id == 0 then
        return nil, nil
    end

    if not self._antiStuck[id] then
        self._antiStuck[id] = {
            phase = 0,
            reverseUntil = 0,
            avoidUntil = 0,
            side = 1,
            attempts = 0,
            lastHitNormal = Vector(0, 0, 0),
            nextCheck = 0,
        }
    end

    return self._antiStuck[id], id
end

function Vehicle:CleanupAntiStuck(bot, root)
    self._antiStuck = self._antiStuck or {}

    if self:IsValid(bot) then
        self._antiStuck[bot:EntIndex()] = nil
    end

    if self:IsValid(root) then
        self._antiStuck[root:EntIndex()] = nil
    end
end

function Vehicle:ChooseAntiStuckSide(root, hitNormal)
    local forward = self:SafeGetForward(root)
    forward.z = 0

    if forward:LengthSqr() < 0.001 then
        forward = Vector(1, 0, 0)
    end

    forward:Normalize()

    local right = self:SafeGetRight(root)
    right.z = 0

    if right:LengthSqr() < 0.001 then
        right = Vector(0, 1, 0)
    end

    right:Normalize()

    local n = nil

    if hitNormal then
        n = Vector(hitNormal.x, hitNormal.y, 0)
    end

    local avoidDir = nil

    if n and n:LengthSqr() > 0.001 then
        avoidDir = self:GetAvoidanceDirection(root, forward, n)
    end

    if not avoidDir or avoidDir:LengthSqr() < 0.001 then
        if math.random() < 0.5 then
            avoidDir = right
        else
            avoidDir = right * -1
        end
    end

    avoidDir.z = 0

    if avoidDir:LengthSqr() < 0.001 then
        avoidDir = right
    end

    avoidDir:Normalize()

    if right:Dot(avoidDir) >= 0 then
        return 1
    end

    return -1
end

function Vehicle:UpdateAntiStuck(bot, root, vehicle, hasObstacle, hitNormal, obstacleDist, isRamming)
    if not self:IsValid(root) then
        return 0, 0, false
    end

    local const = self._const or {}
    local st = self:GetAntiStuckState(root, bot)

    if not st then
        return 0, 0, false
    end

    local now = CurTime()

    local triggerDist = tonumber(const.AntiStuckTriggerDist) or 110
    local hardDist = tonumber(const.AntiStuckHardDist) or 70
    local escapeDist = tonumber(const.AntiStuckEscapeDist) or 230
    local reverseTime = tonumber(const.AntiStuckReverseTime) or 0.8
    local avoidTime = tonumber(const.AntiStuckAvoidTime) or 1.8
    local maxAttempts = tonumber(const.AntiStuckMaxAttempts) or 2
    local revThrottle = tonumber(const.AntiStuckReverseThrottle) or 0.85
    local avoidThrottle = tonumber(const.AntiStuckAvoidThrottle) or 0.6
    local speedThreshold = tonumber(const.AntiStuckSpeedThreshold) or 55
    local cooldown = tonumber(const.AntiStuckCooldown) or 0.9

    obstacleDist = tonumber(obstacleDist) or 999999

    local speed = self:SafeGetVelocity(root):Length()

    if isRamming then
        triggerDist = triggerDist * 0.65
        hardDist = hardDist * 0.65
    end

    if st.phase == 1 then
        if now >= st.reverseUntil or (not hasObstacle) or obstacleDist > escapeDist then
            st.phase = 2
            st.avoidUntil = now + avoidTime
            st.side = self:ChooseAntiStuckSide(root, st.lastHitNormal)

            return avoidThrottle, st.side, true
        end

        return -revThrottle, st.side * 0.35, true
    end

    if st.phase == 2 then
        if now >= st.avoidUntil then
            st.phase = 0
            st.attempts = 0
            st.nextCheck = now + cooldown

            return 0, 0, false
        end

        if hasObstacle and obstacleDist < triggerDist * 0.8 then
            st.attempts = st.attempts + 1

            if st.attempts > maxAttempts then
                st.phase = 0
                st.attempts = 0
                st.nextCheck = now + cooldown * 2

                return 0, 0, false
            end

            st.phase = 1
            st.reverseUntil = now + reverseTime * (1 + (st.attempts - 1) * 0.25)
            st.side = -st.side

            return -revThrottle, st.side * 0.35, true
        end

        return avoidThrottle, st.side, true
    end

    if now < st.nextCheck then
        return 0, 0, false
    end

    local closeWall = hasObstacle and obstacleDist < triggerDist
    local veryClose = hasObstacle and obstacleDist < hardDist

    if closeWall and (veryClose or speed < speedThreshold) then
        st.phase = 1
        st.attempts = 1
        st.reverseUntil = now + reverseTime
        st.lastHitNormal = self:SanitizeVector(hitNormal or Vector(0, 0, 0), Vector(0, 0, 0))
        st.side = self:ChooseAntiStuckSide(root, st.lastHitNormal)

        return -revThrottle, st.side * 0.35, true
    end

    return 0, 0, false
end
function Vehicle:ControlGroundVehicle(bot, root, vehicle, followPos, cmd, ramTarget)
    if not self:IsValid(bot) or not self:IsValid(root) or not followPos then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ControlGroundVehicle: INVALID params")
        end
        return
    end

    local const = self._const or {}
    local vehPos = self:SanitizeVector(self:SafeGetPos(root), Vector())
    local toTarget = self:SanitizeVector(followPos - vehPos, Vector())
    toTarget.z = 0
    local dist = self:SanitizeNumber(toTarget:Length(), 0)

    local data = nil
    if self.botmanager then
        data = self.botmanager:GetData(bot)
    end
    if not data then
        data = self.data:GetBotData(bot)
    end
    if not data then return end

    if not data.vehicle then
        data.vehicle = {
            engine_idle_timer = 0,
            engine_state = "on",
            dead_zone_active = false,
        }
    end
    local vehicleData = data.vehicle
    local isHL2 = self:IsHL2Vehicle(vehicle)

    local isRamming = false
    if self:IsValid(ramTarget) and self:SafeAlive(ramTarget) then
        isRamming = true
    end

    if isHL2 then
        if not root._aiEngineRequested then
            root._aiEngineRequested = true
            pcall(function()
                vehicle:Fire("TurnOn", "", 0)
            end)
        end
    elseif self:HasGlide() and self:IsGlideVehicle(root) then
        pcall(function()
            if root.GetEngineState then
                local engineOn = root:GetEngineState() and true or false
                if not engineOn then
                    if root.TurnOn then root:TurnOn() end
                    if root.SetEngineState then root:SetEngineState(true) end
                end
            end
        end)
    end

    if not isRamming then
        local inDeadZone
        if vehicleData.dead_zone_active then
            inDeadZone = dist < (const.EngineDeadZoneExit or 180)
        else
            inDeadZone = dist < (const.EngineDeadZoneEnter or 120)
        end
        vehicleData.dead_zone_active = inDeadZone

        if inDeadZone then
            vehicleData.engine_idle_timer = (vehicleData.engine_idle_timer or 0) + FrameTime()
            if not isHL2 and self:HasGlide() and vehicleData.engine_idle_timer >= (const.EngineIdleTimeout or 25.0) then
                pcall(function()
                    if root.TurnOff then root:TurnOff() end
                    if root.SetEngineState then root:SetEngineState(false) end
                end)
                vehicleData.engine_state = "off"
            end
            if isHL2 then
                if cmd then self:ApplyHL2VehicleCmd(cmd, 0, 0) end
                return
            end
            if self:HasGlide() then
                self:ApplyVehicleInputs(root, {
                    throttle = 0, accelerate = 0, brake = 1,
                    steer = 0, handbrake = 1, attack = false, fire = false
                })
            end
            return
        else
            vehicleData.engine_idle_timer = 0
        end
    else
        vehicleData.dead_zone_active = false
        vehicleData.engine_idle_timer = 0
    end

    if dist < 1 and not isRamming then
        if isHL2 then
            if cmd then self:ApplyHL2VehicleCmd(cmd, 0, 0) end
        elseif self:HasGlide() then
            self:ApplyVehicleInputs(root, {
                throttle = 0, accelerate = 0, brake = 1,
                steer = 0, handbrake = 1, attack = false, fire = false
            })
        end
        return
    end

    local dir = dist > 1 and toTarget:GetNormalized() or self:SafeGetForward(root)
    dir.z = 0
    if dir:LengthSqr() < 0.001 then dir = Vector(1, 0, 0) end
    dir:Normalize()

    local forward = self:SafeGetForward(root)
    forward.z = 0
    if forward:LengthSqr() < 0.001 then forward = Vector(1, 0, 0) end
    forward:Normalize()

    local right = self:SafeGetRight(root)
    right.z = 0
    if right:LengthSqr() < 0.001 then right = Vector(0, 1, 0) end
    right:Normalize()

    local hasObstacle, hitNormal, obstacleDist = self:CheckVehicleObstacle(root, forward, 450)

    local asThrottle = 0
    local asSteer = 0
    local asActive = false

    local antiStuckResult = {self:UpdateAntiStuck(
        bot,
        root,
        vehicle,
        hasObstacle,
        hitNormal,
        obstacleDist,
        isRamming
    )}

    if #antiStuckResult >= 3 then
        asThrottle = antiStuckResult[1] or 0
        asSteer = antiStuckResult[2] or 0
        asActive = antiStuckResult[3] or false
    end

    if asActive then
        if self.utils then
            self.utils.LogDebug("Vehicle", string.format(
                "AntiStuck active: throttle=%.2f steer=%.2f obstacleDist=%.0f",
                asThrottle,
                asSteer,
                obstacleDist
            ))
        end

        if isHL2 then
            if cmd then
                self:ApplyHL2VehicleCmd(cmd, asThrottle, asSteer)
            end
        elseif self:HasGlide() then
            self:ApplyVehicleInputs(root, {
                throttle = asThrottle,
                accelerate = math.max(0, asThrottle),
                brake = math.max(0, -asThrottle),
                steer = asSteer,
                handbrake = false,
                attack = false,
                fire = false
            })
        end
        return
    end
	if hasObstacle and obstacleDist < 170 then
		if not isRamming then
			if isHL2 then
				if cmd then self:ApplyHL2VehicleCmd(cmd, 0, 0) end
			elseif self:HasGlide() then
				self:ApplyVehicleInputs(root, {
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

		dir = self:GetAvoidanceDirection(root, dir, hitNormal)
	elseif hasObstacle then
		dir = self:GetAvoidanceDirection(root, dir, hitNormal)
	end

    local forwardDot = forward:Dot(dir)
    local rightDot = right:Dot(dir)

    local throttle = 0
    local steer = 0

    if isRamming then

        throttle = 1.0

        if forwardDot > 0.1 then
            steer = rightDot * 1.6
        else
            steer = (rightDot > 0) and 1 or -1
        end
        steer = math.Clamp(steer, -1, 1)

        self:HandleRamDamage(bot, root, vehicle, ramTarget, dist)
    else

        if dist > 800 then
            throttle = 1.0
        elseif dist > 500 then
            throttle = 0.65
        elseif dist > (const.EngineDeadZoneExit or 180) then
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

        if forwardDot > 0.1 then
            steer = rightDot * 1.35
        else
            steer = (rightDot > 0) and 1 or -1
        end
        if hasObstacle and obstacleDist < 260 then
            steer = steer * 1.5
        end
        steer = math.Clamp(steer, -1, 1)
    end

    if isHL2 then
        if cmd then
            self:ApplyHL2VehicleCmd(cmd, throttle, steer)
        end
    elseif self:HasGlide() then
        self:ApplyVehicleInputs(root, {
            accelerate = math.max(0, throttle),
            brake = math.max(0, -throttle),
            steer = steer
        })
    end

    if self.botmanager then
        self.botmanager:UpdateData(bot, data)
    elseif self.data then
        self.data:SetBotData(bot, data)
    end
end

function Vehicle:GetDriverSeat(vehicle)
    if not self:IsValid(vehicle) then return nil end
    if self:IsHL2Vehicle(vehicle) then return vehicle end
    if self:HasGlide() then
        local root = self:GetGlideRoot(vehicle) or vehicle
        if root and self:IsGlideVehicle(root) and root.seats then
            return root.seats[1]
        end
    end
    return nil
end

function Vehicle:GetBotOwnerSafe(bot)
    local data = nil

    if self.botmanager then
        data = self.botmanager:GetData(bot)
    end

    if not data and self.data then
        data = self.data:GetBotData(bot)
    end

    local owner = data and data.owner

    if not self:IsValid(owner) and self.botmanager then
        owner = self.botmanager:GetOwner(bot)
    end

    if not self:IsValid(owner) and self:IsValid(bot) then
        pcall(function()
            owner = bot:GetNWEntity("AICompanionOwnerEnt")
        end)
    end

    return owner
end

function Vehicle:IsFriendlyEntityForBot(bot, ent)
    if not self:IsValid(ent) then return true end
    if ent == bot then return true end

    local owner = self:GetBotOwnerSafe(bot)

    if self:IsValid(owner) and ent == owner then
        return true
    end

    if ent.IsPlayer and ent:IsPlayer() and ent:IsBot() and ent:GetNWBool("IsAICompanion", false) then
        local entOwner = nil
        pcall(function()
            entOwner = ent:GetNWEntity("AICompanionOwnerEnt")
        end)

        if self:IsValid(owner) and self:IsValid(entOwner) and entOwner == owner then
            return true
        end
    end

    local locator = _G.AI_GetLocator()
    local combat = locator and locator:get("combat")

    if combat and combat.IsFriendlyNPC and combat:IsFriendlyNPC(ent) then
        return true
    end

    return false
end

function Vehicle:FindVehicleEnemy(bot, root, data)
    self._enemyScan = self._enemyScan or {}

    if not self:IsValid(bot) then return nil end

    local botID = bot:EntIndex()
    local now = CurTime()

    local scanInterval = (self._const and self._const.VehicleEnemyScanInterval) or 0.5
    local scanRadius = (self._const and (self._const.RamScanRadius or self._const.VehicleEnemyScanRadius)) or 2500

    local cached = self._enemyScan[botID]
    if cached and now - (cached.time or 0) < scanInterval then
        if not cached.target then
            return nil
        end

        if self:IsValid(cached.target) and self:SafeAlive(cached.target) then
            return cached.target
        end
    end

    local basePos = self:SafeGetPos(root or bot)
    local owner = self:GetBotOwnerSafe(bot)

    local bestEnemy = nil
    local bestDist = scanRadius

    local locator = _G.AI_GetLocator()
    local combat = locator and locator:get("combat")

    local function consider(ent)
        if not self:IsValid(ent) then return end
        if not self:SafeAlive(ent) then return end

        if ent == bot then return end
        if self:IsValid(owner) and ent == owner then return end
        if self:IsValid(root) and ent == root then return end

        local entVeh = self:SafeGetVehicle(ent)
        if self:IsValid(entVeh) then
            local entRoot = self:GetGlideRoot(entVeh) or entVeh
            if self:IsValid(root) and entRoot == root then
                return
            end
        end

        if self:IsFriendlyEntityForBot(bot, ent) then return end

        local hostile = true

        if combat and combat.IsHostileByDefault then
            hostile = combat:IsHostileByDefault(ent, bot)
        else
            if ent:IsNPC() or ent:IsNextBot() then
                hostile = true
            elseif ent:IsPlayer() then
                hostile = not ent:IsBot()
            else
                hostile = false
            end
        end

        if not hostile then return end

        local entPos = self:SafeGetPos(ent)
        local dist = basePos:Distance(entPos)

        if dist < bestDist then
            bestDist = dist
            bestEnemy = ent
        end
    end

    if combat and combat._enemyCache and #combat._enemyCache > 0 then
        for _, ent in ipairs(combat._enemyCache) do
            consider(ent)
        end
    end

    local ok, entsInSphere = pcall(ents.FindInSphere, basePos, scanRadius)
    if ok and entsInSphere then
        for _, ent in ipairs(entsInSphere) do
            consider(ent)
        end
    end

    self._enemyScan[botID] = {
        time = now,
        target = bestEnemy
    }

    if self.utils and self:IsValid(bestEnemy) then
        self.utils.LogDebug(
            "Vehicle",
            string.format(
                "%s: найден враг для транспорта: %s (дистанция: %.0f)",
                bot:Nick(),
                self:SafeGetClass(bestEnemy),
                bestDist
            )
        )
    end

    return bestEnemy
end

function Vehicle:ControlVehicle(bot, vehicle, owner, cmd)
    if not self:IsValid(bot) or not self:IsValid(vehicle) then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ControlVehicle: INVALID bot or vehicle")
        end
        return
    end
    if not self:IsValid(owner) then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ControlVehicle: INVALID owner")
        end
        return
    end

    local root = self:GetGlideRoot(vehicle) or vehicle
    if not self:IsValid(root) then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ControlVehicle: INVALID root")
        end
        return
    end

    local data = nil
    if self.botmanager then
        data = self.botmanager:GetData(bot)
    end
    if not data then
        data = self.data:GetBotData(bot)
    end
    if not data then return end

    local driverSeat = self:GetDriverSeat(vehicle)
    local botIsDriver = self:IsValid(driverSeat) and self:SafeGetDriver(driverSeat) == bot
    local playerIsDriver = self:IsValid(driverSeat) and self:SafeGetDriver(driverSeat) == owner

    local hasEnemy = false
    local enemyTarget = nil

    local botData = nil
    if self.botmanager then
        botData = self.botmanager:GetData(bot)
    end
    if not botData and self.data then
        botData = self.data:GetBotData(bot)
    end

    local isPacifist = false
    local isDefender = false

    if botData and botData.config then
        isPacifist = botData.config.pacifist_mode == true
        isDefender = botData.config.defender_mode == true
    end

    if isPacifist then

        if botData and botData.combat and botData.combat.target then
            botData.combat.target = nil
            botData.combat.target_type = nil
            botData.combat.triggered_by = nil
            if self.botmanager then self.botmanager:UpdateData(bot, botData) end
        end
        hasEnemy = false
        enemyTarget = nil

    elseif isDefender then
        if botData and botData.combat and self:IsValid(botData.combat.target) and self:SafeAlive(botData.combat.target) then
            hasEnemy = true
            enemyTarget = botData.combat.target
        else
            hasEnemy = false
            enemyTarget = nil
        end

    else
        if not data.combat then
            data.combat = {}
        end

        if self:IsValid(data.combat.target) and self:SafeAlive(data.combat.target) then
            hasEnemy = true
            enemyTarget = data.combat.target
        end

        if hasEnemy and self:IsValid(owner) and enemyTarget == owner then
            local trigger = data.combat.triggered_by

            if trigger ~= "command" and trigger ~= "command_llm" then
                data.combat.target = nil
                data.combat.target_type = nil
                data.combat.triggered_by = nil

                hasEnemy = false
                enemyTarget = nil

                if self.botmanager then
                    self.botmanager:UpdateData(bot, data)
                end
            end
        end

        if not hasEnemy then
            if self:IsValid(data.combat.target) then
                data.combat.target = nil
            end

            local foundEnemy = self:FindVehicleEnemy(bot, root, data)

            if self:IsValid(foundEnemy) then
                hasEnemy = true
                enemyTarget = foundEnemy

                data.combat.target = foundEnemy

                if foundEnemy:IsPlayer() and not foundEnemy:IsBot() then
                    data.combat.target_type = "player"
                else
                    data.combat.target_type = "npc"
                end

                if not data.combat.triggered_by then
                    data.combat.triggered_by = "vehicle"
                end

                data.combat.last_attack_time = CurTime()

                if self.botmanager then
                    self.botmanager:UpdateData(bot, data)
                end

                if self.utils then
                    self.utils.LogDebug(
                        "Vehicle",
                        string.format(
                            "%s: транспорт получил боевую цель: %s",
                            bot:Nick(),
                            self:SafeGetClass(foundEnemy)
                        )
                    )
                end
            end
        end
    end

    if not botIsDriver then
        if self.utils then
            self.utils.LogDebug("Vehicle", "ControlVehicle: bot is NOT driver, stopping")
        end
        self:StopVehicle(root, vehicle, cmd)
        return
    end

    if self.utils then
        self.utils.LogDebug("Vehicle", "ControlVehicle: bot IS driver, processing vehicle type=" ..
            tostring(self:GetGlideVehicleType(root)) .. " enemy=" .. tostring(enemyTarget and self:SafeGetClass(enemyTarget) or "none"))
    end

    if self:HasGlide() and self:IsGlideVehicle(root) then
        local vType = self:GetGlideVehicleType(root)

        if vType == "helicopter" then
            local target = hasEnemy and enemyTarget or owner
            local isEnemy = hasEnemy and self:IsValid(enemyTarget)
            local inputs = self:CalculateHeliInputs(root, target, isEnemy)
            if inputs then self:ApplyVehicleInputs(root, inputs) end
            self:ControlHeliWeapons(bot, root, target, isEnemy)
            return
        end

        if vType == "tank" then
            local aimTarget = hasEnemy and enemyTarget or owner
            self:UpdateTankAim(bot, root, aimTarget, hasEnemy)
            if hasEnemy then
                self:ControlTankCannon(bot, vehicle, enemyTarget)
            else
                self:ReleaseTankAttack(root)
            end
            local followPos = hasEnemy and self:GetAimTargetPos(enemyTarget) or self:SafeGetPos(owner)
            followPos = self:SanitizeVector(followPos, self:SafeGetPos(owner))
            self:ControlGroundVehicle(bot, root, vehicle, followPos, cmd, hasEnemy and enemyTarget or nil)
            return
        end
    end

    local ramTarget = hasEnemy and enemyTarget or nil
    local followPos
    if hasEnemy and self:IsValid(enemyTarget) then
        followPos = self:GetAimTargetPos(enemyTarget)
    else
        followPos = self:SafeGetPos(owner)
    end
    followPos = self:SanitizeVector(followPos, self:SafeGetPos(owner))
    self:ControlGroundVehicle(bot, root, vehicle, followPos, cmd, ramTarget)
end

function Vehicle:GetBestSeat(vehicle, bot, hasEnemy, playerIsDriver, owner)
    if not self:IsValid(vehicle) or not self:IsValid(bot) then return nil end
    if not self:HasGlide() then return nil end

    local root = self:GetGlideRoot(vehicle) or vehicle
    if not self:IsValid(root) or not root.seats then return nil end

    local totalSeats = #root.seats
    if totalSeats <= 0 then return nil end

    local driverSeat = root.seats[1]
    local isDriverFree = self:IsValid(driverSeat) and not self:IsValid(self:SafeGetDriver(driverSeat))

    if playerIsDriver then
        for i = 2, totalSeats do
            local seat = root.seats[i]
            if self:IsValid(seat) and not self:IsValid(self:SafeGetDriver(seat)) then
                return seat
            end
        end
        return nil
    end

    if isDriverFree then
        return driverSeat
    end

    for i = 2, totalSeats do
        local seat = root.seats[i]
        if self:IsValid(seat) and not self:IsValid(self:SafeGetDriver(seat)) then
            return seat
        end
    end

    return nil
end

function Vehicle:EnterBestSeat(bot, vehicle, force, hasEnemy, playerIsDriver, owner)
    if not self:IsValid(bot) or not self:IsValid(vehicle) then return false end
    if not self:HasGlide() then return false end

    local bestSeat = self:GetBestSeat(vehicle, bot, hasEnemy, playerIsDriver, owner)
    if not self:IsValid(bestSeat) then return false end

    if bot:InVehicle() then
        local currentVeh = self:SafeGetVehicle(bot)
        if currentVeh ~= bestSeat then
            pcall(function() bot:ExitVehicle() end)
            timer.Simple(0.1, function()
                if self:IsValid(bot) and not bot:InVehicle() then
                    pcall(function() bot:EnterVehicle(bestSeat) end)
                end
            end)
            return true
        end
        return true
    end

    local ok = pcall(function() bot:EnterVehicle(bestSeat) end)
    if ok and bot:InVehicle() then
        local data = nil
        if self.botmanager then
            data = self.botmanager:GetData(bot)
            if data then
                data.vehicle.locked_vehicle = self:GetGlideRoot(vehicle) or vehicle
                data.vehicle.locked_seat = bestSeat
                self.botmanager:UpdateData(bot, data)
            end
        else
            data = self.data:GetBotData(bot)
            if data then
                data.vehicle.locked_vehicle = self:GetGlideRoot(vehicle) or vehicle
                data.vehicle.locked_seat = bestSeat
                self.data:SetBotData(bot, data)
            end
        end
        return true
    end
    return false
end

function Vehicle:FindNearestVehicle(bot, radius)
    if not self:IsValid(bot) then return nil end
    radius = radius or 500

    local botPos = self:SafeGetPos(bot)
    local candidates = {}

    for _, ent in ipairs(ents.FindInSphere(botPos, radius)) do
        if not self:IsValid(ent) then continue end

        local root = nil
        local isValid = false
        local class = self:SafeGetClass(ent)
        local dist = botPos:Distance(self:SafeGetPos(ent))

        if self:HasGlide() and self:IsGlideVehicle(ent) then
            isValid = true
            root = ent
        elseif self:IsHL2Vehicle(ent) then
            isValid = true
            root = ent
        elseif self:HasGlide() then
            root = self:GetGlideRoot(ent)
            if self:IsValid(root) and self:IsGlideVehicle(root) then
                isValid = true
            end
        end

        if not isValid or not self:IsValid(root) then
            continue
        end

        local driverSeat = self:GetDriverSeat(root)
        if not self:IsValid(driverSeat) then
            continue
        end

        local driver = self:SafeGetDriver(driverSeat)
        if self:IsValid(driver) then
            continue
        end

        table.insert(candidates, {root = root, dist = dist})
    end

    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    local result = candidates[1] and candidates[1].root or nil
    return result
end

function Vehicle:EnterDriverSeat(bot, vehicle)
    if not self:IsValid(bot) or not self:IsValid(vehicle) then return false end

    local seat = self:GetDriverSeat(vehicle)
    if not self:IsValid(seat) then return false end
    if self:IsValid(self:SafeGetDriver(seat)) then return false end

    local ok = pcall(function() bot:EnterVehicle(seat) end)
    if ok and bot:InVehicle() then
        local data = nil
        if self.botmanager then
            data = self.botmanager:GetData(bot)
        end
        if not data then
            data = self.data:GetBotData(bot)
        end
        if data then
            data.vehicle.sit_by_command = true
            data.vehicle.locked_vehicle = self:GetGlideRoot(vehicle) or vehicle
            data.vehicle.locked_seat = seat
            if self.botmanager then
                self.botmanager:UpdateData(bot, data)
            else
                self.data:SetBotData(bot, data)
            end
        end
        return true
    end
    return false
end

function Vehicle:ForceExit(bot)
    if not self:IsValid(bot) then return end

    local data = nil
    if self.botmanager then
        data = self.botmanager:GetData(bot)
    end
    if not data then
        data = self.data:GetBotData(bot)
    end

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
        if self.botmanager then
            self.botmanager:UpdateData(bot, data)
        else
            self.data:SetBotData(bot, data)
        end
    end

    local currentVeh = self:SafeGetVehicle(bot)
    if self:IsValid(currentVeh) then
        local currentRoot = self:GetGlideRoot(currentVeh) or currentVeh
        if self:HasGlide() and self:IsGlideVehicle(currentRoot) then
            pcall(function()
                if currentRoot.TurnOff then currentRoot:TurnOff() end
                if currentRoot.SetEngineState then currentRoot:SetEngineState(false) end
            end)
            local id = currentRoot:EntIndex()
            self._engineStopCooldown[id] = nil
        end
    end

    self:CleanupTankState(bot)
    self:CleanupHeliWeaponState(bot)

    self._ramState[bot:EntIndex()] = nil
	local antiStuckVeh = self:SafeGetVehicle(bot)
	local antiStuckRoot = nil

	if self:IsValid(antiStuckVeh) then
		antiStuckRoot = self:GetGlideRoot(antiStuckVeh) or antiStuckVeh
	end

	self:CleanupAntiStuck(bot, antiStuckRoot)

    if bot:InVehicle() then
        pcall(function() bot:ExitVehicle() end)
    end

    self:ResetBotAimTarget(bot)
end

function Vehicle:ComeBackToPlayer(bot)
    if not self:IsValid(bot) then return end

    if self.movement then
        self.movement:ComeBackToPlayer(bot)
        return
    end

    local data = nil
    if self.botmanager then
        data = self.botmanager:GetData(bot)
    end
    if not data then
        data = self.data:GetBotData(bot)
    end

    if data and data.owner and self:IsValid(data.owner) then
        data.navigation.goal_pos = data.owner:GetPos()
        if self.botmanager then
            self.botmanager:SetBotState(bot, "following")
        else
            self.data:SetBotState(bot, "following")
        end
    end
end

function Vehicle:ResetBotAfterVehicle(bot)
    if not self:IsValid(bot) then return end

    self:ForceExit(bot)

    local data = nil
    if self.botmanager then data = self.botmanager:GetData(bot) end
    if not data then data = self.data:GetBotData(bot) end
    if not data then return end

    if data.combat then
        data.combat.target = nil
        data.combat.target_type = nil
        data.combat.triggered_by = nil
    end

    if data.navigation then
        data.navigation.path = nil
        data.navigation.path_index = 1
        data.navigation.stuck.time = 0
    end

    if self.botmanager then
        self.botmanager:SetBotState(bot, "following")
    else
        self.data:SetBotState(bot, "following")
    end

    bot:SetNWBool("AI_StealthMode", false)
    bot:RemoveFlags(FL_DUCKING)
    bot:RemoveFlags(FL_ANIMDUCKING)

    self:ComeBackToPlayer(bot)

    if self.utils then
        self.utils.LogDebug("Vehicle", "ResetBotAfterVehicle: Состояние сброшено для " .. bot:Nick())
    end
end

function Vehicle:GetAPI()
    return {
        ControlVehicle = function(bot, vehicle, owner, cmd)
            return self:ControlVehicle(bot, vehicle, owner, cmd)
        end,
        GetGlideRoot = function(vehicle) return self:GetGlideRoot(vehicle) end,
        GetDriverSeat = function(vehicle) return self:GetDriverSeat(vehicle) end,
        GetAimTargetPos = function(ent) return self:GetAimTargetPos(ent) end,
        SetBotAimTarget = function(bot, pos) return self:SetBotAimTarget(bot, pos) end,
        ResetBotAimTarget = function(bot) return self:ResetBotAimTarget(bot) end,
        IsGlideVehicle = function(ent) return self:IsGlideVehicle(ent) end,
        EnterDriverSeat = function(bot, vehicle) return self:EnterDriverSeat(bot, vehicle) end,
        ForceExit = function(bot) return self:ForceExit(bot) end,
        GetGlideVehicleType = function(vehicle) return self:GetGlideVehicleType(vehicle) end,
        ApplyVehicleInputs = function(vehicle, inputs, seatIndex)
            return self:ApplyVehicleInputs(vehicle, inputs, seatIndex)
        end,
        ApplyHL2VehicleCmd = function(cmd, throttle, steer)
            return self:ApplyHL2VehicleCmd(cmd, throttle, steer)
        end,
        StopVehicle = function(root, vehicle, cmd)
            return self:StopVehicle(root, vehicle, cmd)
        end,
        CalculateHeliInputs = function(vehicle, target, isEnemy)
            return self:CalculateHeliInputs(vehicle, target, isEnemy)
        end,
        ControlHeliWeapons = function(bot, root, target, isEnemy)
            return self:ControlHeliWeapons(bot, root, target, isEnemy)
        end,
        UpdateTankAim = function(bot, root, target, isEnemy)
            return self:UpdateTankAim(bot, root, target, isEnemy)
        end,
        ControlTankCannon = function(bot, vehicle, target)
            return self:ControlTankCannon(bot, vehicle, target)
        end,
        GetBestSeat = function(vehicle, bot, hasEnemy, playerIsDriver, owner)
            return self:GetBestSeat(vehicle, bot, hasEnemy, playerIsDriver, owner)
        end,
        EnterBestSeat = function(bot, vehicle, force, hasEnemy, playerIsDriver, owner)
            return self:EnterBestSeat(bot, vehicle, force, hasEnemy, playerIsDriver, owner)
        end,
        FindNearestVehicle = function(bot, radius)
            return self:FindNearestVehicle(bot, radius)
        end,
        ForceExit = function(bot) return self:ForceExit(bot) end,
        ComeBackToPlayer = function(bot) return self:ComeBackToPlayer(bot) end,

        GetRamState = function(bot) return self:GetRamState(bot) end,
        HandleRamDamage = function(bot, root, vehicle, target, dist)
            return self:HandleRamDamage(bot, root, vehicle, target, dist)
        end,
    }
end

function Vehicle:SetupHooks()
    if not SERVER then return end

    local selfRef = self

    hook.Add("PlayerEnteredVehicle", "AICompanion_AutoEnterWithOwner_v3", function(ply, vehicle, role)
        local root = selfRef:GetGlideRoot(vehicle) or vehicle
        if not selfRef:IsValid(root) then return end

        local bots = {}
        if selfRef.botmanager then
            bots = selfRef.botmanager:GetAllBots()
        else

            local allData = selfRef.data:GetAllBotData()
            for _, entry in pairs(allData) do
                if selfRef:IsValid(entry.bot) then
                    table.insert(bots, entry.bot)
                end
            end
        end

		 for _, bot in ipairs(bots) do
			 if not selfRef:IsValid(bot) then continue end
			 if bot:InVehicle() then continue end

			 local data = nil
			 if selfRef.botmanager then data = selfRef.botmanager:GetData(bot) end
			 if not data then data = selfRef.data:GetBotData(bot) end
			 if not data or data.owner ~= ply then continue end

			 local hasEnemy = data.combat and selfRef:IsValid(data.combat.target)
			 local driverSeat = selfRef:GetDriverSeat(root)
			 local playerIsDriver = selfRef:IsValid(driverSeat) and selfRef:SafeGetDriver(driverSeat) == ply

			 if not playerIsDriver and selfRef:IsValid(driverSeat) and not selfRef:IsValid(selfRef:SafeGetDriver(driverSeat)) then
				 pcall(function() bot:EnterVehicle(driverSeat) end)
				 if bot:InVehicle() then
					 if data then
						 data.vehicle.locked_vehicle = root
						 data.vehicle.locked_seat = driverSeat
						 data.vehicle.sit_by_command = false
						 if selfRef.botmanager then selfRef.botmanager:UpdateData(bot, data)
						 else selfRef.data:SetBotData(bot, data) end
					 end
					 if selfRef:IsValid(bot) then bot:ChatPrint("[AI] Сажусь за руль.") end
					 continue
				 end
			 end

			 if selfRef:HasGlide() and selfRef:IsGlideVehicle(root) and root.seats and #root.seats > 1 then
				 local bestSeat = nil

				 for i = 2, #root.seats do
					 local seat = root.seats[i]
					 if selfRef:IsValid(seat) and not selfRef:IsValid(selfRef:SafeGetDriver(seat)) then
						 bestSeat = seat
						 break
					 end
				 end

				 if selfRef:IsValid(bestSeat) then
					 pcall(function() bot:EnterVehicle(bestSeat) end)
					 if bot:InVehicle() then
						 if data then
							 data.vehicle.locked_vehicle = root
							 data.vehicle.locked_seat = bestSeat
							 data.vehicle.sit_by_command = false
							 if selfRef.botmanager then selfRef.botmanager:UpdateData(bot, data)
							 else selfRef.data:SetBotData(bot, data) end
						 end
						 if selfRef:IsValid(bot) then bot:ChatPrint("[AI] Сажусь в транспорт (Glide).") end
						 continue
					 end
				 end
				 continue
			 end

			 local hl2Seat = selfRef:FindNearestFreeHL2Seat(bot, root)
			 if selfRef:IsValid(hl2Seat) then
				 pcall(function() bot:EnterVehicle(hl2Seat) end)
				 if bot:InVehicle() then
					 if data then
						 data.vehicle.locked_vehicle = root
						 data.vehicle.locked_seat = hl2Seat
						 data.vehicle.sit_by_command = false
						 if selfRef.botmanager then selfRef.botmanager:UpdateData(bot, data)
						 else selfRef.data:SetBotData(bot, data) end
					 end
					 if selfRef:IsValid(bot) then bot:ChatPrint("[AI] Сажусь вместе с вами.") end
					 continue
				 end
			 end
		 end
    end)

    hook.Add("PlayerLeaveVehicle", "AICompanion_OwnerLeftVehicle_v3", function(ply, vehicle)

        if ply:GetNWBool("IsAICompanion", false) then
            selfRef:ResetBotAfterVehicle(ply)
            if selfRef:IsValid(ply) then
                ply:ChatPrint("[AI] Вышел из транспорта. Следую за вами.")
            end
            return
        end
        local bots = {}
        if selfRef.botmanager then
            bots = selfRef.botmanager:GetAllBots()
        else
            local allData = selfRef.data:GetAllBotData()
            for _, entry in pairs(allData) do
                if selfRef:IsValid(entry.bot) then
                    table.insert(bots, entry.bot)
                end
            end
        end

        for _, bot in ipairs(bots) do
            if not selfRef:IsValid(bot) then continue end

            local data = nil
            if selfRef.botmanager then
                data = selfRef.botmanager:GetData(bot)
            end
            if not data then
                data = selfRef.data:GetBotData(bot)
            end
            if not data or data.owner ~= ply then continue end

            if bot:InVehicle() and not data.vehicle.sit_by_command then
                local botVeh = nil
                pcall(function() botVeh = bot:GetVehicle() end)
                if selfRef:IsValid(botVeh) then
                    local ownerRoot = selfRef:GetGlideRoot(vehicle) or vehicle
                    local botRoot = selfRef:GetGlideRoot(botVeh) or botVeh

                    if ownerRoot == botRoot then
                        selfRef:ForceExit(bot)
                        if selfRef:IsValid(bot) then bot:ChatPrint("[AI] Владелец вышел, выхожу тоже.") end
                        continue
                    end

                    local botPos = selfRef:SafeGetPos(bot)
                    local ownerPos = selfRef:SafeGetPos(ply)
                    if botPos:Distance(ownerPos) < 300 then
                        selfRef:ForceExit(bot)
                        if selfRef:IsValid(bot) then bot:ChatPrint("[AI] Владелец вышел, выхожу тоже.") end
                    end
                end
            end
        end
    end)
	hook.Add("StartCommand", "AI_Vehicle_StartCommand", function(ply, cmd)
		if not ply:GetNWBool("IsAICompanion", false) then return end
		if not ply:InVehicle() then return end
		local vehicle = ply:GetVehicle()
		if not selfRef:IsValid(vehicle) then return end

		cmd:ClearButtons()
		cmd:SetForwardMove(0)
		cmd:SetSideMove(0)
		cmd:SetUpMove(0)

		local data = nil
		if selfRef.botmanager then data = selfRef.botmanager:GetData(ply) end
		if not data then data = selfRef.data:GetBotData(ply) end
		if not data or not data.owner or not selfRef:IsValid(data.owner) then return end

		selfRef:ControlVehicle(ply, vehicle, data.owner, cmd)
	end)

    hook.Add("CanExitVehicle", "AICompanion_BlockExit_v2", function(vehicle, ply)
        if not selfRef:IsValid(ply) then return end
        if not ply:GetNWBool("IsAICompanion", false) then return end

        local data = nil
        if selfRef.botmanager then
            data = selfRef.botmanager:GetData(ply)
        end
        if not data then
            data = selfRef.data:GetBotData(ply)
        end

        if data and data.vehicle.sit_by_command and selfRef:IsValid(data.vehicle.locked_vehicle) then
            local vehicleRoot = selfRef:GetGlideRoot(vehicle) or vehicle
            if data.vehicle.locked_vehicle == vehicleRoot then
                return false
            end
        end

        if data and not data.vehicle.sit_by_command then
            if data.owner and data.owner:InVehicle() then
                local ownerVeh = nil
                pcall(function() ownerVeh = data.owner:GetVehicle() end)
                if selfRef:IsValid(ownerVeh) then
                    local ownerRoot = selfRef:GetGlideRoot(ownerVeh) or ownerVeh
                    local botRoot = selfRef:GetGlideRoot(vehicle) or vehicle
                    if ownerRoot == botRoot then
                        return false
                    end
                end

                local botPos = selfRef:SafeGetPos(ply)
                local ownerPos = selfRef:SafeGetPos(data.owner)
                if botPos:Distance(ownerPos) < 300 then
                    return false
                end
            end
        end
    end)

	 hook.Add("PlayerDisconnected", "AI_Vehicle_Cleanup_v3", function(ply)
		 if not selfRef:IsValid(ply) then return end
		 if not ply:GetNWBool("IsAICompanion", false) then return end

		 selfRef:CleanupTankState(ply)
		 selfRef:CleanupHeliWeaponState(ply)
		 selfRef:ResetBotAimTarget(ply)
		 selfRef._ramState[ply:EntIndex()] = nil
		 local discVeh = selfRef:SafeGetVehicle(ply)
		local discRoot = nil

		if selfRef:IsValid(discVeh) then
			discRoot = selfRef:GetGlideRoot(discVeh) or discVeh
		end

		selfRef:CleanupAntiStuck(ply, discRoot)

		 local data = nil
		 if selfRef.botmanager then data = selfRef.botmanager:GetData(ply) end
		 if not data then data = selfRef.data:GetBotData(ply) end

		 if data and data.vehicle then
			 data.vehicle.sit_by_command = false
			 data.vehicle.locked_vehicle = nil
			 data.vehicle.locked_seat = nil
			 data.vehicle.dead_zone_active = false
			 data.vehicle.engine_state = "on"
			 data.vehicle.engine_idle_timer = 0
		 end

		 local currentVeh = selfRef:SafeGetVehicle(ply)
		 if selfRef:IsValid(currentVeh) then
			 local currentRoot = selfRef:GetGlideRoot(currentVeh) or currentVeh
			 if selfRef:HasGlide() and selfRef:IsGlideVehicle(currentRoot) then
				 pcall(function()
					 if currentRoot.TurnOff then currentRoot:TurnOff() end
					 if currentRoot.SetEngineState then currentRoot:SetEngineState(false) end
				 end)
				 local id = currentRoot:EntIndex()
				 selfRef._engineStopCooldown[id] = nil
			 end
		 end
	 end)

	 hook.Add("PlayerDeath", "AI_Vehicle_DeathCleanup_v3", function(victim)
		 if not selfRef:IsValid(victim) then return end
		 if not victim:GetNWBool("IsAICompanion", false) then return end

		 selfRef:CleanupTankState(victim)
		 selfRef:CleanupHeliWeaponState(victim)
		 selfRef:ResetBotAimTarget(victim)
		 selfRef._ramState[victim:EntIndex()] = nil
		local deathVeh = selfRef:SafeGetVehicle(victim)
		local deathRoot = nil

		if selfRef:IsValid(deathVeh) then
			deathRoot = selfRef:GetGlideRoot(deathVeh) or deathVeh
		end

		selfRef:CleanupAntiStuck(victim, deathRoot)

		 local data = nil
		 if selfRef.botmanager then data = selfRef.botmanager:GetData(victim) end
		 if not data then data = selfRef.data:GetBotData(victim) end

		 if data and data.vehicle then
			 data.vehicle.sit_by_command = false
			 data.vehicle.locked_vehicle = nil
			 data.vehicle.locked_seat = nil
		 end
	 end)
end

return Vehicle
