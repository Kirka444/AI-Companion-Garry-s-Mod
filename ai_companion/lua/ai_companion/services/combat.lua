
local Combat = {}

function Combat:new(utils, config, state, data, botmanager, shared)
    local obj = {
        utils = utils,
        config = config,
        state = state,
        data = data,
        botmanager = botmanager,
        shared = shared,

        _initialized = false,
        _enemyCache = {},
        _enemyCacheTime = 0,
        _grenadeCache = { list = {}, lastUpdate = 0, botPos = Vector(0, 0, 0) },
        _scanTimer = nil,
        _friendlyNPCs = nil,
        _armoredTargets = nil,
        _threatWeights = nil,
        _idealCombatDist = nil,
        _weapons = nil,
        _combatConfig = nil,
        _magic = nil,
        _grenadeDodgeClasses = { ["npc_grenade_frag"] = true },
        _entityBlacklist = {
            ["worldspawn"] = true,
            ["trigger"] = true,
            ["func_"] = true,
            ["env_"] = true,
            ["point_"] = true,
            ["fire"] = true,
            ["smoke"] = true,
            ["spark"] = true,
        },
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Combat:init()
    if self._initialized then return end

    local configData = self.config:get("Magic") or {}
    self._magic = configData
    self._combatConfig = configData.Combat or {}
    self._weapons = self.config:get("Weapons") or {}
    self._friendlyNPCs = self.config:get("FRIENDLY_NPC_CLASSES") or {}
    self._armoredTargets = self.config:get("ARMORED_TARGETS") or {}
    self._threatWeights = self.config:get("THREAT_WEIGHTS") or {}
    self._idealCombatDist = self.config:get("IDEAL_COMBAT_DIST") or {}

    if not self.utils then
        error("[AI Combat] utils не передан!")
    end
    if not self.botmanager then
        error("[AI Combat] botmanager не передан!")
    end

    if SERVER then
        self:SetupHooks()
        self:StartScanTimer()
    end

    self._initialized = true
    if self.utils then
        self.utils.LogInfo("Combat", "Боевая система инициализирована")
    end
end

function Combat:IsValid(ent)
    return self.utils and self.utils:IsValid(ent)
end

function Combat:IsBotSafe(ent)
    return self.utils and self.utils.IsBotSafe(ent)
end

function Combat:IsPlayerSafe(ent)
    return self.utils and self.utils.IsPlayerSafe(ent)
end

function Combat:SafeGetClass(ent)
    if not self:IsValid(ent) then return "invalid" end
    local ok, class = pcall(function() return ent:GetClass() end)
    return (ok and class) or "error"
end

function Combat:SafeGetPos(ent)
    if not self:IsValid(ent) then return Vector() end
    local ok, pos = pcall(function() return ent:GetPos() end)
    return (ok and pos) or Vector()
end

function Combat:SafeAlive(ent)
    if not self:IsValid(ent) then return false end
    local ok, alive = pcall(function() return ent:Alive() end)
    return ok and alive
end

function Combat:GetBotData(bot)
    if not self:IsValid(bot) then return nil end
    return self.botmanager:GetData(bot)
end

function Combat:GetBotOwner(bot)
    if not self:IsValid(bot) then return nil end
    return self.botmanager:GetOwner(bot)
end

function Combat:GetAllBots()
    return self.botmanager:GetAllBots() or {}
end

function Combat:GetBotState(bot)
    return self.botmanager:GetBotState(bot)
end

function Combat:SetBotState(bot, state)
    return self.botmanager:SetBotState(bot, state)
end

function Combat:GetStates()
    if self.state then
        return self.state:GetStates()
    end
    return {
        IDLE = "idle",
        FOLLOW = "following",
        COMBAT = "combat",
        VEHICLE = "vehicle",
        PROTECT = "protecting",
        PROTECT_VEHICLE = "protecting_vehicle",
        SITTING = "sitting",
        COVER = "cover",
        POINTING = "pointing",
    }
end

function Combat:ComeBackToPlayer(bot)
    if not self:IsValid(bot) then return end

    local locator = _G.AI_GetLocator()
    if not locator then return end

    local movement = locator:get("movement")
    if not movement then return end

    movement:ComeBackToPlayer(bot)
end

function Combat:IsPassenger(bot)
	if not self:IsValid(bot) then return false end
	if not bot:InVehicle() then return false end

	local veh = bot:GetVehicle()
	if not veh then return true end

	local locator = _G.AI_GetLocator()
	local vehicleService = locator and locator:get("vehicle")

	local driver = nil

	if vehicleService then
		local root = vehicleService:GetGlideRoot(veh) or veh
		local driverSeat = vehicleService:GetDriverSeat(root)
		if driverSeat then
			pcall(function() driver = driverSeat:GetDriver() end)
		end
	end

	if not driver then
		pcall(function() driver = veh:GetDriver() end)
	end

	if driver == bot then return false end

	return true
end

function Combat:ApplyWorldMovement(cmd, dir, speed)
    if not cmd then return end
    if not dir or dir:LengthSqr() <= 0.001 then return end
    if not speed or speed <= 0 then return end

    local locator = _G.AI_GetLocator()
    if not locator then return end

    local movement = locator:get("movement")
    if not movement then return end

    local movUtils = movement.utils_movement
    if movUtils and movUtils.ApplyWorldMovement then
        movUtils:ApplyWorldMovement(cmd, dir, speed)
    end
end

function Combat:GetBotMode(bot, modeKey)
    if not self:IsValid(bot) then return false end

    local data = self:GetBotData(bot)
    if data and data.config then
        if modeKey == "stealth_mode" then return data.config.stealth_mode or false end
        if modeKey == "defender_mode" then return data.config.defender_mode or false end
        if modeKey == "medic_mode" then return data.config.medic_mode or false end
        if modeKey == "pacifist_mode" then return data.config.pacifist_mode or false end
        if modeKey == "aggressive_mode" then return data.config.aggressive_mode or false end
    end

    return bot:GetNWBool(modeKey, false)
end

function Combat:IsMedicMode(bot)
    return self:GetBotMode(bot, "medic_mode")
end

function Combat:IsPacifistMode(bot)
    return self:GetBotMode(bot, "pacifist_mode")
end

function Combat:IsDefenderMode(bot)
    return self:GetBotMode(bot, "defender_mode")
end

function Combat:IsAggressiveMode(bot)
    return self:GetBotMode(bot, "aggressive_mode")
end

function Combat:IsStealthMode(bot)
    return self:GetBotMode(bot, "stealth_mode")
end

function Combat:IsValidTarget(ent)
    if not self:IsValid(ent) then return false end
    if ent:IsWorld() then return false end

    local class = self:SafeGetClass(ent)
    if class == "worldspawn" then return false end

    for pattern, _ in pairs(self._entityBlacklist) do
        if string.find(class, pattern) then return false end
    end

    if ent.IsEffect and ent:IsEffect() then return false end
    if ent.IsConstraint and ent:IsConstraint() then return false end

    if class == "prop_physics" and ent:GetModel() == "" then return false end

    return true
end

function Combat:IsArmoredTarget(ent)
    if not self:IsValid(ent) then return false end
    local class = self:SafeGetClass(ent)

    if self._armoredTargets[class] then return true end
    if ent:IsVehicle() then
        if string.find(class, "apc") or string.find(class, "tank") or
           string.find(class, "strider") or string.find(class, "gunship") or
           string.find(class, "helicopter") then return true end
    end
    return false
end

function Combat:IsFriendlyNPC(ent)
    if not self:IsValid(ent) then return false end
    local class = self:SafeGetClass(ent)
    return self._friendlyNPCs[class] == true
end

function Combat:IsHostileByDefault(ent, bot)
    if not self:IsValidTarget(ent) then return false end

    if ent:IsPlayer() then
        if self:IsBotSafe(ent) then

            local owner = self:GetBotOwner(ent)
            if owner and self:IsValid(owner) then
                return false
            end

            if self:IsValid(bot) then
                local botOwner = self:GetBotOwner(bot)
                if self:IsValid(botOwner) and owner == botOwner then
                    return false
                end
            end
        end
        return true
    end

    if ent:IsNPC() then
        if self:IsFriendlyNPC(ent) then return false end
        return true
    end

    if ent:IsNextBot() then
        if self:IsFriendlyNPC(ent) then return false end
        return true
    end

    return false
end

function Combat:CanSeeTarget(bot, target)
    if not self:IsValid(bot) or not self:IsValid(target) then return false end

    local tr = util.TraceLine({
        start = bot:EyePos(),
        endpos = target:WorldSpaceCenter(),
        filter = bot,
        mask = MASK_SHOT
    })

    if not tr.Hit then return true end
    if self:IsValid(tr.Entity) and tr.Entity == target then return true end
    return false
end

function Combat:GetTargetAimPos(target)
    if not self:IsValid(target) then return Vector() end

    if target:IsPlayer() then
        local ok, ep = pcall(function() return target:EyePos() end)
        if ok and ep then return ep end
        return target:GetPos() + Vector(0, 0, 64)
    end

    if target:IsNPC() or target:IsNextBot() then
        local boneNames = {
            "ValveBiped.Bip01_Spine2",
            "ValveBiped.Bip01_Spine1",
            "ValveBiped.Bip01_Head",
            "ValveBiped.Bip01_Neck",
            "ValveBiped.Bip01_Pelvis"
        }
        for _, boneName in ipairs(boneNames) do
            local ok, bone = pcall(function() return target:LookupBone(boneName) end)
            if ok and bone then
                local ok2, pos = pcall(function() return target:GetBonePosition(bone) end)
                if ok2 and pos and pos:LengthSqr() > 0.01 then return pos end
            end
        end

        local ok, wsc = pcall(function() return target:WorldSpaceCenter() end)
        if ok and wsc then return wsc end

        local pos = target:GetPos()
        local mn, mx = target:GetCollisionBounds()
        if mn and mx then
            return pos + Vector(0, 0, (mn.z + mx.z) * 0.5)
        end
        return pos
    end

    local ok, wsc = pcall(function() return target:WorldSpaceCenter() end)
    if ok and wsc then return wsc end
    return target:GetPos() + Vector(0, 0, 32)
end

function Combat:HasAmmoForWeapon(bot, weapon)
    if not self:IsValid(bot) or not self:IsValid(weapon) then return false end

    local infiniteAmmo = self.config:get("INFINITE_AMMO") or false
    if infiniteAmmo then return true end

    local clip = weapon:Clip1()
    if clip and clip > 0 then return true end

    local ammoType = weapon:GetPrimaryAmmoType()
    if ammoType and ammoType ~= -1 then
        local reserve = bot:GetAmmoCount(ammoType)
        if reserve and reserve > 0 then return true end
    end

    local ammoType2 = weapon:GetSecondaryAmmoType()
    if ammoType2 and ammoType2 ~= -1 then
        local reserve = bot:GetAmmoCount(ammoType2)
        if reserve and reserve > 0 then return true end
    end

    local maxClip = weapon:GetMaxClip1()
    if maxClip == -1 or maxClip == 0 then
        return true
    end

    return false
end

function Combat:HasAnyAmmo(bot)
    if not self:IsValid(bot) then return false end
    if self.config:get("INFINITE_AMMO") then return true end

    local weapons = bot:GetWeapons()
    for _, wep in ipairs(weapons) do
        if self:IsValid(wep) then
            if self:HasAmmoForWeapon(bot, wep) then return true end
        end
    end

    return false
end

function Combat:SafeGiveWeapon(bot, weaponClass)
    if not self.utils or not self.utils:IsValid(bot) then return false end
    if not weaponClass or weaponClass == "" then return false end

    if bot:HasWeapon(weaponClass) then return true end

    local ok = pcall(function() bot:Give(weaponClass) end)
    if ok then return true end

    local ok2, weapon = pcall(ents.Create, weaponClass)
    if ok2 and self.utils:IsValid(weapon) then
        weapon:SetOwner(bot)
        weapon:Spawn()

        pcall(function() bot:Give(weaponClass) end)
        return true
    end

    return false
end

function Combat:SafeGiveAmmo(bot, weapon, amount)
    if not self.shared then return false end
    return self.shared:SafeGiveAmmo(bot, weapon, amount)
end

function Combat:GetBotCombatWeapon(bot)
    if not self:IsValid(bot) then return self._weapons.COMBAT or "weapon_smg1" end
    local data = self:GetBotData(bot)
    if data and data.config and data.config.combat_weapon then
        return data.config.combat_weapon
    end
    return self._weapons.COMBAT or "weapon_smg1"
end

function Combat:GetBotMeleeWeapon(bot)
    if not self:IsValid(bot) then return self._weapons.MELEE or "weapon_crowbar" end
    local data = self:GetBotData(bot)
    if data and data.config and data.config.melee_weapon then
        return data.config.melee_weapon
    end
    return self._weapons.MELEE or "weapon_crowbar"
end

function Combat:GetBotIdleWeapon(bot)
    if not self:IsValid(bot) then return self._weapons.IDLE or "weapon_physgun" end
    local data = self:GetBotData(bot)
    if data and data.config and data.config.idle_weapon then
        return data.config.idle_weapon
    end
    return self._weapons.IDLE or "weapon_physgun"
end

function Combat:SelectBestWeapon(bot, target, dist)
    if not self:IsValid(bot) then return "weapon_smg1", "combat" end

    local botData = self:GetBotData(bot)
    if not botData then return "weapon_smg1", "combat" end

    local meleeWep = self:GetBotMeleeWeapon(bot)
    local combatWep = self:GetBotCombatWeapon(bot)

    if self:IsArmoredTarget(target) then
        if not bot:HasWeapon("weapon_rpg") then
            self:SafeGiveWeapon(bot, "weapon_rpg")
        end
        local rpg = bot:GetWeapon("weapon_rpg")
        if self:IsValid(rpg) then
            bot:GiveAmmo(5, "RPG_Round", true)
            if self.config:get("INFINITE_AMMO") or rpg:Clip1() <= 0 then
                rpg:SetClip1(1)
            end
        end
        return "weapon_rpg", "rpg"
    end

    if not self:HasAnyAmmo(bot) then
        if not bot:HasWeapon(meleeWep) then
            self:SafeGiveWeapon(bot, meleeWep)
        end
        return meleeWep, "melee"
    end

    local meleeDist = self._combatConfig.MeleeDist or 110
    if dist < meleeDist then
        if not bot:HasWeapon(meleeWep) then
            self:SafeGiveWeapon(bot, meleeWep)
        end
        if bot:HasWeapon(meleeWep) then
            return meleeWep, "melee"
        end
    end

    if bot:HasWeapon("weapon_frag") then
        local lastThrow = botData.combat.frag_last_throw or 0
        local fragCooldown = self._combatConfig.FragCooldown or 5.0
        local fragMinDist = self._combatConfig.FragMinDist or 150
        local fragMaxDist = self._combatConfig.FragMaxDist or 600
        if CurTime() - lastThrow >= fragCooldown and
           dist > fragMinDist and dist < fragMaxDist then
            return "weapon_frag", "frag"
        end
    end

    if not bot:HasWeapon(combatWep) then
        self:SafeGiveWeapon(bot, combatWep)
        local wep = bot:GetWeapon(combatWep)
        if self:IsValid(wep) then
            self:SafeGiveAmmo(bot, wep, 60)
            if self.config:get("INFINITE_AMMO") then
                wep:SetClip1(wep:GetMaxClip1() or 30)
            end
        end
    end

    local combatWeapon = bot:GetWeapon(combatWep)
    if self:IsValid(combatWeapon) then
        if not self:HasAmmoForWeapon(bot, combatWeapon) and not self.config:get("INFINITE_AMMO") then
            if not bot:HasWeapon(meleeWep) then
                self:SafeGiveWeapon(bot, meleeWep)
            end
            return meleeWep, "melee"
        end
    end

    return combatWep, "combat"
end

function Combat:GetThreatWeight(ent)
    if not self:IsValidTarget(ent) then return 0 end
    if not self:IsValid(ent) then return 0 end

    local class = self:SafeGetClass(ent)
    local weight = self._threatWeights[class] or 1

    if ent:IsPlayer() then
        local wep = ent:GetActiveWeapon()
        if self:IsValid(wep) then
            local wepClass = wep:GetClass()
            if wepClass == "weapon_rpg" or wepClass == "weapon_rocketlauncher" then
                weight = 5
            end
        end
        return weight * 2
    end

    return weight
end

function Combat:SelectHighestThreat(bot, enemies)
    local best, bestWeight = nil, -1
    for _, ent in ipairs(enemies) do
        if self:IsValid(ent) and self:SafeAlive(ent) and self:IsValidTarget(ent) then
            local w = self:GetThreatWeight(ent)
            if w > bestWeight then
                bestWeight = w
                best = ent
            end
        end
    end
    return best
end

function Combat:UpdateGrenadeCache(botPos)
    local now = CurTime()
    local updateInterval = self._combatConfig.GrenadeUpdateInterval or 0.3
    if now - self._grenadeCache.lastUpdate < updateInterval then return end

    self._grenadeCache.lastUpdate = now
    self._grenadeCache.botPos = botPos
    self._grenadeCache.list = {}

    local dodgeRadius = self._combatConfig.GrenadeDodgeRadius or 250
    for _, ent in ipairs(ents.GetAll()) do
        if self:IsValid(ent) and self._grenadeDodgeClasses[self:SafeGetClass(ent)] then
            local dist = botPos:Distance(self:SafeGetPos(ent))
            if dist < dodgeRadius then
                table.insert(self._grenadeCache.list, ent)
            end
        end
    end
end

function Combat:HandleGrenadeDodge(bot, cmd)
    if not self:IsValid(bot) or not cmd then return false end

    local botPos = self:SafeGetPos(bot)
    self:UpdateGrenadeCache(botPos)

    if #self._grenadeCache.list == 0 then return false end

    local dodge = Vector(0, 0, 0)
    local closestDist = 999999
    local dangerDist = self._combatConfig.GrenadeDangerDist or 110

    for _, grenade in ipairs(self._grenadeCache.list) do
        if self:IsValid(grenade) then
            local dir = botPos - self:SafeGetPos(grenade)
            local dist = dir:Length()
            if dist < closestDist then closestDist = dist end
            if dist > 10 then
                dodge = dodge + dir:GetNormalized()
            end
        end
    end

    if dodge:LengthSqr() < 0.01 then return false end
    dodge:Normalize()

    local dodgeSpeed = self._combatConfig.DodgeSpeed or 350
    self:ApplyWorldMovement(cmd, dodge, dodgeSpeed)

    if closestDist < dangerDist then
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP))
    end

    return true
end

function Combat:IsMedicBlockedByCombat(bot, botData)
    if not botData then return false end

    local states = self:GetStates()
    local state = self:GetBotState(bot)

    if state == states.COMBAT or
       state == states.PROTECT or
       state == states.PROTECT_VEHICLE or
       (states.COVER and state == states.COVER) then
        return true
    end

    if botData.combat then

        if self:IsValidTarget(botData.combat.target) and self:SafeAlive(botData.combat.target) then
            return true
        end

        local now = CurTime()
        local grace = self._combatConfig.MedicCombatGrace or 2.0

        if botData.combat.last_attack_time and now - botData.combat.last_attack_time < grace then
            return true
        end

        if botData.combat.last_damage_time and now - botData.combat.last_damage_time < grace then
            return true
        end

        if botData.combat.medic_post_combat_cooldown and botData.combat.medic_post_combat_cooldown > now then
            return true
        end
    end

    return false
end

function Combat:GetMedicHealTarget(bot, botData)
    if not self:IsValid(bot) or not bot:Alive() then return nil end

    local allowSelfHeal = self._combatConfig.MedicSelfHeal
    if allowSelfHeal == nil then allowSelfHeal = true end

    local botHp = bot:Health()
    local botMax = math.max(bot:GetMaxHealth(), 1)
    local botPct = botHp / botMax

    local selfThreshold = self._combatConfig.HealThresholdSelf or 0.55

    local owner = self:GetBotOwner(bot)
    local ownerPct = nil
    local ownerThreshold = self._combatConfig.HealThresholdOwner or 0.7

    if self:IsValid(owner) and owner:Alive() then
        ownerPct = owner:Health() / math.max(owner:GetMaxHealth(), 1)
    end

    local botNeeds = allowSelfHeal and botPct < selfThreshold
    local ownerNeeds = ownerPct ~= nil and ownerPct < ownerThreshold

    if botNeeds and ownerNeeds then
        if botPct <= ownerPct then
            return bot, botPct
        end
        return owner, ownerPct
    end

    if ownerNeeds then
        return owner, ownerPct
    end

    if botNeeds then
        return bot, botPct
    end

    return nil, botPct
end

function Combat:SpawnMedicHealthkit(bot, target, timerKey, healCooldown)
    if timer.Exists(timerKey) then return false end

    local kit = ents.Create("item_healthkit")
    if self:IsValid(kit) then
        local pos = self:SafeGetPos(target) + Vector(0, 0, target == bot and 12 or 8)
        kit:SetPos(pos)
        kit:Spawn()

        local fx = EffectData()
        fx:SetOrigin(pos + Vector(0, 0, 32))
        util.Effect("cball_explode", fx)

        timer.Simple(8, function()
            if self:IsValid(kit) then
                kit:Remove()
            end
        end)
    end

    timer.Create(timerKey, healCooldown, 1, function() end)
    return true
end

function Combat:HandleMedicMode(bot, cmd)
    if not self:IsValid(bot) or not bot:Alive() then return false end
    if self:IsPassenger(bot) then return false end

    local botData = self:GetBotData(bot)
    if not botData then return false end

    if not botData.combat then
        botData.combat = {}
    end

    if not self:IsMedicMode(bot) then return false end

    if self:IsMedicBlockedByCombat(bot, botData) then
        return false
    end

    local healTarget, healPct = self:GetMedicHealTarget(bot, botData)

    if not healTarget then

        local idleWep = self:GetBotIdleWeapon(bot)
        local activeWep = bot:GetActiveWeapon()
        local activeClass = self:IsValid(activeWep) and activeWep:GetClass() or ""

        if activeClass ~= idleWep and bot:HasWeapon(idleWep) then
            bot:SelectWeapon(idleWep)
        end

        return false
    end

    if not self:SafeAlive(healTarget) then
        return false
    end

    if not bot:HasWeapon("weapon_medkit") then
        self:SafeGiveWeapon(bot, "weapon_medkit")

        timer.Simple(0.1, function()
            if self:IsValid(bot) and bot:HasWeapon("weapon_medkit") then
                bot:SelectWeapon("weapon_medkit")
            end
        end)

        return true
    end

    local aw = bot:GetActiveWeapon()
    if not self:IsValid(aw) or aw:GetClass() ~= "weapon_medkit" then
        bot:SelectWeapon("weapon_medkit")
        return true
    end

    local healCooldown = self._combatConfig.HealCooldown or 1.2
    local botID = bot:EntIndex()
    local timerKey = "AI_MedkitSpawn_" .. botID

    if healTarget == bot then
        bot._aiMedicSelfHeal = true

        if cmd then
            cmd:ClearMovement()

            local ang = bot:EyeAngles()
            ang.p = math.Clamp(ang.p + 35, -89, 89)
            bot:SetEyeAngles(ang)
            cmd:SetViewAngles(ang)
        end

        if not timer.Exists(timerKey) then
            if cmd then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
            end

            self:SpawnMedicHealthkit(bot, bot, timerKey, healCooldown)
        end

        return true
    else
        bot._aiMedicSelfHeal = nil
    end

    local targetPos = self:SafeGetPos(healTarget)
    local botPos = self:SafeGetPos(bot)
    local dist = botPos:Distance(targetPos)

    local healRange = self._combatConfig.HealRange or 140

    local aimPos = targetPos + Vector(0, 0, 45)
    local okWsc, wsc = pcall(function() return healTarget:WorldSpaceCenter() end)
    if okWsc and wsc then
        aimPos = wsc
    end

    local aimDir = aimPos - bot:EyePos()
    if aimDir:LengthSqr() > 0.001 then
        aimDir:Normalize()
        local aimAng = aimDir:Angle()
        bot:SetEyeAngles(aimAng)

        if cmd then
            cmd:SetViewAngles(aimAng)
        end
    end

    if dist <= healRange then
        if cmd then
            cmd:ClearMovement()
        end

        if not timer.Exists(timerKey) then
            if cmd then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
            end

            self:SpawnMedicHealthkit(bot, healTarget, timerKey, healCooldown)
        end

        return true
    end

    if cmd then
        local locator = _G.AI_GetLocator()
        local movement = locator and locator:get("movement")

        if movement and movement.MoveToTarget then
            movement:MoveToTarget(bot, cmd, targetPos, healTarget)
        else
            local dir = targetPos - botPos
            dir.z = 0

            if dir:LengthSqr() > 0.001 then
                dir:Normalize()
                self:ApplyWorldMovement(cmd, dir, self._combatConfig.MedicMoveSpeed or 300)
            end
        end
    end

    return true
end

function Combat:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag)
    if not self:IsValid(bot) or not self:IsValid(target) or not cmd then return end

    local botData = self:GetBotData(bot)
    if not botData then return end

    local botPos = self:SafeGetPos(bot)
    local targetPos = self:SafeGetPos(target)

    local idealDist = self._combatConfig.IdealDist or 300
    if isMelee then
        idealDist = self._combatConfig.MeleeDist or 110
    elseif isRPG then
        idealDist = self._combatConfig.RPGDist or 500
    elseif isFrag then
        idealDist = (self._combatConfig.FragMinDist or 150) + 50
    end

    local aimPos = self:GetTargetAimPos(target)
    local aimDir = aimPos - bot:EyePos()
    if aimDir:LengthSqr() < 0.001 then aimDir = Vector(1, 0, 0) end
    aimDir:Normalize()

    local flatAim = Vector(aimDir.x, aimDir.y, 0)
    if flatAim:LengthSqr() < 0.001 then flatAim = Vector(1, 0, 0) end
    flatAim:Normalize()

    local useNav = false
    local movePos = nil

    if dist > idealDist * 1.2 then
        useNav = true
        movePos = targetPos
    elseif dist < idealDist * 0.6 then

        local backDir = -flatAim
        local combatBackDist = self._combatConfig.CombatBackDist or 110
        movePos = botPos + backDir * combatBackDist
    else

        if not botData.combat.next_strafe_change or CurTime() > botData.combat.next_strafe_change then
            botData.combat.strafe_dir = math.random() > 0.5 and 1 or -1
            local strafeMin = self._combatConfig.StrafeMinInterval or 0.3
            local strafeMax = self._combatConfig.StrafeMaxInterval or 0.9
            botData.combat.next_strafe_change = CurTime() + math.Rand(strafeMin, strafeMax)
        end
        local rgt = aimDir:Angle():Right()
        rgt.z = 0
        if rgt:LengthSqr() < 0.001 then rgt = Vector(0, 1, 0) end
        rgt:Normalize()
        local combatStrafeDist = self._combatConfig.CombatStrafeDist or 100
        movePos = botPos + rgt * botData.combat.strafe_dir * combatStrafeDist
    end

    if useNav then
        local locator = _G.AI_GetLocator()
        if locator then
            local movement = locator:get("movement")
            if movement and movement.MoveToTarget then
                movement:MoveToTarget(bot, cmd, movePos or targetPos, target)
            else

                local runDir = (targetPos - botPos)
                runDir.z = 0
                if runDir:LengthSqr() > 0.001 then
                    runDir:Normalize()
                    self:ApplyWorldMovement(cmd, runDir, self._combatConfig.CombatSpeed or 220)
                end
            end
        end
    elseif movePos then
        local runDir = movePos - botPos
        runDir.z = 0
        if runDir:LengthSqr() > 0.001 then
            runDir:Normalize()
            local moveSpeed = isMelee and (self._combatConfig.MeleeSpeed or 400) or (self._combatConfig.CombatSpeed or 220)
            self:ApplyWorldMovement(cmd, runDir, moveSpeed)
        end
    end

    local btns = cmd:GetButtons()
    cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
    bot:RemoveFlags(FL_DUCKING)
    bot:RemoveFlags(FL_ANIMDUCKING)
    bot._aiStealthCrouch = false
end

function Combat:HandleCombat(bot, cmd)
    if not self:IsValid(bot) then return false end
    if not bot:Alive() then return false end

    local botData = self:GetBotData(bot)
    if not botData then return false end

	local isInVehicle = bot:InVehicle()
	local isDriver = false

	if isInVehicle then
		isDriver = not self:IsPassenger(bot)

		local veh = bot:GetVehicle()
		if veh then
			local locator = _G.AI_GetLocator()
			local vehicleService = locator and locator:get("vehicle")

			if vehicleService then

				local root = vehicleService:GetGlideRoot(veh) or veh
				local driverSeat = vehicleService:GetDriverSeat(root)

				if driverSeat then
					local driver = nil
					pcall(function() driver = driverSeat:GetDriver() end)
					if driver == bot then isDriver = true end
				end
			else

				local driver = nil
				pcall(function() driver = veh:GetDriver() end)
				if driver == bot then isDriver = true end
			end
		end
	end

    if isInVehicle and not isDriver then
        if botData.combat then botData.combat.target = nil end
        return false
    end

    if self:IsPacifistMode(bot) then
        botData.combat.target = nil
        local states = self:GetStates()
        self:SetBotState(bot, states.FOLLOW)
        self:ComeBackToPlayer(bot)
        local idleWep = self:GetBotIdleWeapon(bot)
        if bot:HasWeapon(idleWep) then bot:SelectWeapon(idleWep) end
        return false
    end

    local target = botData.combat.target
    if not self:IsValidTarget(target) or not self:SafeAlive(target) then
        self:CleanupCombatState(bot)
        return false
    end

	if isInVehicle and isDriver then
		botData.combat.last_attack_time = CurTime()

		local states = self:GetStates()
		local currentState = self:GetBotState(bot)
		if currentState ~= states.PROTECT_VEHICLE and currentState ~= states.COMBAT then
			self:SetBotState(bot, states.PROTECT_VEHICLE)
			if self.utils then
				self.utils.LogDebug("Combat", bot:Nick() .. " → PROTECT_VEHICLE (водитель, цель: " .. tostring(target) .. ")")
			end
		end

		return true
	end

	local botPos = self:SafeGetPos(bot)
	local targetPos = self:SafeGetPos(target)
	local dist = botPos:Distance(targetPos)
	local meleeDist = self._combatConfig.MeleeDist or 110

    if self:HandleGrenadeDodge(bot, cmd) then
        return true
    end

    local meleeWep = self:GetBotMeleeWeapon(bot)
    if dist < meleeDist then

        if not bot:HasWeapon(meleeWep) then
            local lastMeleeGive = botData.combat.last_melee_give or 0
            local meleeGiveCooldown = self._combatConfig.MeleeGiveCooldown or 1.0
            if CurTime() - lastMeleeGive > meleeGiveCooldown then
                self:SafeGiveWeapon(bot, meleeWep)
                botData.combat.last_melee_give = CurTime()
                if meleeWep ~= "weapon_crowbar" and meleeWep ~= "weapon_stunstick" then
                    local mw = bot:GetWeapon(meleeWep)
                    if self:IsValid(mw) then
                        self:SafeGiveAmmo(bot, mw, 30)
                    end
                end
            end
        end

        if bot:HasWeapon(meleeWep) then
            local aw = bot:GetActiveWeapon()
            if not self:IsValid(aw) or aw:GetClass() ~= meleeWep then
                bot:SelectWeapon(meleeWep)
                botData.combat.weapon_switch_wait = (botData.combat.weapon_switch_wait or 0) + 1
                local weaponSwitchDelay = self._combatConfig.WeaponSwitchDelay or 5
                if botData.combat.weapon_switch_wait < weaponSwitchDelay then

                    self:CombatMovement(bot, cmd, target, dist, true, false, false)
                    return true
                end
                botData.combat.weapon_switch_wait = 0
            else
                botData.combat.weapon_switch_wait = 0
            end

            aw = bot:GetActiveWeapon()
            if self:IsValid(aw) and aw:GetClass() == meleeWep then
                local aimPos = self:GetTargetAimPos(target)
                local aimDir = aimPos - bot:EyePos()
                if aimDir:LengthSqr() > 0.001 then
                    aimDir:Normalize()
                    local aimAng = aimDir:Angle()
                    bot:SetEyeAngles(aimAng)
                    cmd:SetViewAngles(aimAng)
                    bot._aiAimDir = aimDir
                    botData.combat.last_attack_time = CurTime()

                    if self:CanSeeTarget(bot, target) then
                        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
                    end

                    local bPos = self:SafeGetPos(bot)
                    local tPos = self:SafeGetPos(target)
                    local dirToTarget = tPos - bPos
                    dirToTarget.z = 0

                    local idealMeleeDist = 45
                    local moveDir = Vector(0, 0, 0)

                    if dirToTarget:LengthSqr() > 0.001 then
                        dirToTarget:Normalize()

                        if dist > idealMeleeDist + 10 then
                            moveDir = dirToTarget
                        elseif dist < idealMeleeDist - 15 then
                            moveDir = -dirToTarget
                        else

                            if not botData.combat.next_strafe_change or CurTime() > botData.combat.next_strafe_change then
                                botData.combat.strafe_dir = math.random() > 0.5 and 1 or -1
                                botData.combat.next_strafe_change = CurTime() + 0.5
                            end
                            local rgt = aimAng:Right()
                            rgt.z = 0
                            if rgt:LengthSqr() < 0.001 then rgt = Vector(0, 1, 0) end
                            rgt:Normalize()
                            moveDir = rgt * botData.combat.strafe_dir * 0.3
                        end

                        local checkTr = util.TraceHull({
                            start = bPos + Vector(0, 0, 15),
                            endpos = bPos + Vector(0, 0, 15) + moveDir * 40,
                            mins = Vector(-12, -12, 0),
                            maxs = Vector(12, 12, 20),
                            filter = bot,
                            mask = MASK_PLAYERSOLID
                        })

                        if checkTr.Hit and not checkTr.StartSolid then
                            moveDir = Vector(0, 0, 0)
                        end

                        if moveDir:LengthSqr() > 0.001 then
                            local meleeSpeed = self._combatConfig.MeleeSpeed or 400
                            self:ApplyWorldMovement(cmd, moveDir, meleeSpeed)
                        end
                    end
                    return true
                end
            end
        end
    end

    local desiredWep, weaponMode = self:SelectBestWeapon(bot, target, dist)

    local MELEE_WEAPONS = { ["weapon_crowbar"] = true, ["weapon_stunstick"] = true }
    local isMelee = MELEE_WEAPONS[desiredWep] or false
    local isRPG = weaponMode == "rpg"
    local isFrag = weaponMode == "frag"

    if not bot:HasWeapon(desiredWep) then
        self:SafeGiveWeapon(bot, desiredWep)
        local waitTicks = (desiredWep == "weapon_rpg") and 3 or 1
        botData.combat.weapon_wait_ticks = (botData.combat.weapon_wait_ticks or 0) + 1
        if botData.combat.weapon_wait_ticks < waitTicks then

            self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag)
            return true
        end
        botData.combat.weapon_wait_ticks = 0
    else
        botData.combat.weapon_wait_ticks = 0
    end

    local aw = bot:GetActiveWeapon()
    local awClass = self:IsValid(aw) and aw:GetClass() or "NONE"
    if awClass ~= desiredWep then
        bot:SelectWeapon(desiredWep)
        botData.combat.weapon_switch_wait = (botData.combat.weapon_switch_wait or 0) + 1
        local weaponSwitchDelay = self._combatConfig.WeaponSwitchDelay or 5
        if botData.combat.weapon_switch_wait < weaponSwitchDelay then

            self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag)
            return true
        end
        botData.combat.weapon_switch_wait = 0
    else
        botData.combat.weapon_switch_wait = 0
    end

    if self.config:get("INFINITE_AMMO") then
        local wep = bot:GetActiveWeapon()
        if self:IsValid(wep) then
            if wep:Clip1() <= 0 then
                local ammoType = wep:GetPrimaryAmmoType()
                if ammoType and ammoType ~= -1 then
                    local ammoGiveAmount = self._combatConfig.AmmoGiveAmount or 100
                    bot:GiveAmmo(ammoGiveAmount, ammoType, true)
                    wep:SetClip1(wep:GetMaxClip1() > 0 and wep:GetMaxClip1() or 30)
                end
            end
        end
    end

    local aimPos = self:GetTargetAimPos(target)

    local targetVel = target:GetVelocity() or Vector(0, 0, 0)
    local bulletSpeed = 5000
    local timeToTarget = dist / bulletSpeed
    aimPos = aimPos + targetVel * timeToTarget

    local aimDir = aimPos - bot:EyePos()
    if aimDir:LengthSqr() < 0.001 then

        self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag)
        return true
    end
    aimDir:Normalize()
    local aimAng = aimDir:Angle()

    bot:SetEyeAngles(aimAng)
    cmd:SetViewAngles(aimAng)
    bot._aiAimDir = aimDir

    local canSee = self:CanSeeTarget(bot, target)
    local canShoot = canSee

    if isRPG then
        local active = bot:GetActiveWeapon()
        if not self:IsValid(active) or active:GetClass() ~= "weapon_rpg" then
            bot:SelectWeapon("weapon_rpg")
            return true
        end

        local rpgCooldown = self._combatConfig.RPGCooldown or 0.1
        if CurTime() - (botData.combat.rpg_last_fire or 0) >= rpgCooldown and canShoot then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
            botData.combat.rpg_last_fire = CurTime()
            botData.combat.last_attack_time = CurTime()
        end
    elseif isFrag then
        local fragCooldown = self._combatConfig.FragCooldown or 5.0
        if CurTime() - (botData.combat.frag_last_throw or 0) >= fragCooldown then
            local throwAimPos = targetPos + Vector(0, 0, 30)
            local throwDir = throwAimPos - bot:EyePos()
            if throwDir:LengthSqr() > 0.001 then
                throwDir:Normalize()
                local throwAng = throwDir:Angle()
                local fragThrowAngle = self._combatConfig.FragThrowAngle or 15
                throwAng.p = throwAng.p - fragThrowAngle
                bot:SetEyeAngles(throwAng)
                cmd:SetViewAngles(throwAng)
            end

            local fragMinDist = self._combatConfig.FragMinDist or 150
            local fragMaxDist = self._combatConfig.FragMaxDist or 600
            if dist < fragMaxDist and dist > fragMinDist then
                cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
                botData.combat.frag_last_throw = CurTime()
                botData.combat.last_attack_time = CurTime()
            end
        end
    elseif canShoot then
        local atkBtns = IN_ATTACK
        local altFireCooldown = self._combatConfig.AltFireCooldown or 2.0
        if CurTime() - (botData.combat.alt_fire_timer or 0) > altFireCooldown then
            atkBtns = bit.bor(atkBtns, IN_ATTACK2)
            botData.combat.alt_fire_timer = CurTime()
        end
        cmd:SetButtons(bit.bor(cmd:GetButtons(), atkBtns))
        botData.combat.last_attack_time = CurTime()
    end

    self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag)

    return true
end

function Combat:HandleAimbotCorrection(ent, data)
    if not self:IsValid(ent) or not self:IsBotSafe(ent) then return end
    if not ent:GetNWBool("IsAICompanion", false) then return end

    local botData = self:GetBotData(ent)
    if not botData or not botData.combat.target then return end

    local target = botData.combat.target
    if not self:IsValidTarget(target) then return end

    local aimPos = self:GetTargetAimPos(target)
    local targetVel = target:GetVelocity() or Vector(0, 0, 0)
    local shootPos = ent:GetShootPos()
    local dist = shootPos:Distance(aimPos)

    local bulletSpeed = 5000
    local timeToTarget = math.max(dist / bulletSpeed, 0.01)
    aimPos = aimPos + targetVel * timeToTarget

    local rawDir = aimPos - shootPos
    if rawDir:LengthSqr() > 1e-4 then
        local aimDir = rawDir:GetNormalized()
        local aimAng = aimDir:Angle()
        ent:SetEyeAngles(aimAng)
        ent._aiAimDir = aimDir
        data.Dir = aimDir
        data.Spread = Vector(0, 0, 0)

        local checkTrace = util.TraceLine({ start = shootPos, endpos = aimPos, filter = ent, mask = MASK_SHOT })
        if checkTrace.Hit and checkTrace.Entity and checkTrace.Entity ~= target then
            if checkTrace.Entity:IsWorld() then
                local newAimPos = aimPos + Vector(0, 0, 15)
                local newDir = (newAimPos - shootPos):GetNormalized()
                data.Dir = newDir
                ent:SetEyeAngles(newDir:Angle())
            end
        end
    end

    return true
end

function Combat:UpdateEnemyCache()
    local enemyCacheInterval = self._combatConfig.EnemyCacheInterval or 2.0
    if CurTime() - self._enemyCacheTime < enemyCacheInterval then return end

    self._enemyCacheTime = CurTime()
    self._enemyCache = {}

    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if self:IsValid(ent) and ent:Alive() and self:IsValidTarget(ent) then
            local class = self:SafeGetClass(ent)
            if not self._friendlyNPCs[class] then
                table.insert(self._enemyCache, ent)
            end
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        if self:IsValid(ply) and ply:Alive() and not ply:IsBot() and self:IsValidTarget(ply) then

            local isOwner = false
            local allBots = self:GetAllBots()
            for _, bot in ipairs(allBots) do
				if self:IsPassenger(bot) then continue end
                if self:IsValid(bot) then
                    local owner = self:GetBotOwner(bot)
                    if owner == ply then
                        isOwner = true
                        break
                    end
                end
            end
            if not isOwner then
                table.insert(self._enemyCache, ply)
            end
        end
    end
end

function Combat:StartScanTimer()
    if self._scanTimer then return end

    local scanInterval = self._combatConfig.ThreatScanInterval or 2.0
    self._scanTimer = timer.Create("AICompanion_AggressiveScan", scanInterval, 0, function()
        self:UpdateEnemyCache()

        local allBots = self:GetAllBots()
        for _, bot in ipairs(allBots) do
            if not self:IsValid(bot) or not bot:Alive() then continue end
            if self:IsPassenger(bot) then continue end

            local botData = self:GetBotData(bot)
            if not botData then continue end

            if not self:IsAggressiveMode(bot) then continue end

            if botData.combat.target and self:IsValidTarget(botData.combat.target) and self:SafeAlive(botData.combat.target) then
                continue
            end

            if botData.combat.target then
                botData.combat.target = nil
                local states = self:GetStates()
                self:SetBotState(bot, states.FOLLOW)
                self:ComeBackToPlayer(bot)
                continue
            end

            local botState = self:GetBotState(bot)
            local states = self:GetStates()
            if botState == states.POINTING then continue end

            local botPos = self:SafeGetPos(bot)
            local scanRadius = self._combatConfig.ThreatScanRadius or 1500

            local nearestEnemy, nearestDist = nil, scanRadius
            for _, ent in ipairs(self._enemyCache) do
                if not self:IsValid(ent) then continue end
                if ent == bot then continue end
                if not self:IsValidTarget(ent) then continue end

                local dist = botPos:Distance(self:SafeGetPos(ent))
                if dist < nearestDist then
                    nearestDist = dist
                    nearestEnemy = ent
                end
            end

            if self:IsValid(nearestEnemy) then
                botData.combat.target = nearestEnemy
                botData.combat.target_type = "npc"
                botData.combat.triggered_by = "aggressive"
                botData.combat.last_attack_time = CurTime()
                self:SetBotState(bot, states.COMBAT)
                self:ForceCombatWeapon(bot)

                if self:IsValid(bot) then
                    bot:ChatPrint("[AI] Агрессивный режим: атакую " .. self:SafeGetClass(nearestEnemy))
                end
            end
        end
    end)
end

function Combat:ForceCombatWeapon(bot)
    if not self:IsValid(bot) or not bot:Alive() then return end

    local combatWep = self:GetBotCombatWeapon(bot)
    if not combatWep or combatWep == "" then
        combatWep = "weapon_smg1"
    end

    if not bot:HasWeapon(combatWep) then
        self:SafeGiveWeapon(bot, combatWep)
        timer.Simple(0.1, function()
            if not self:IsValid(bot) then return end
            local wep = bot:GetWeapon(combatWep)
            if self:IsValid(wep) then
                local ammoType = wep:GetPrimaryAmmoType()
                if ammoType and ammoType ~= -1 then
                    bot:GiveAmmo(120, ammoType, true)
                end
                if self.config:get("INFINITE_AMMO") then
                    local maxClip = wep:GetMaxClip1() or 30
                    if maxClip > 0 then wep:SetClip1(maxClip) end
                end
            end
        end)
    end

    bot:SelectWeapon(combatWep)
end

function Combat:ForceMeleeWeapon(bot)
    if not self:IsValid(bot) or not bot:Alive() then return end

    local meleeWep = self:GetBotMeleeWeapon(bot)
    if not meleeWep or meleeWep == "" then
        meleeWep = "weapon_crowbar"
    end

    if not bot:HasWeapon(meleeWep) then
        self:SafeGiveWeapon(bot, meleeWep)
    end

    bot:SelectWeapon(meleeWep)
end

function Combat:CleanupCombatState(bot)
    if not self:IsValid(bot) then return end

    local botData = self:GetBotData(bot)
    if not botData then return end

    if botData.combat and botData.combat.target then
        botData.combat.target = nil
        botData.combat.target_type = nil
        botData.combat.triggered_by = nil
        botData.combat.last_combat_end = CurTime()
        botData.combat.medic_post_combat_cooldown = CurTime() + (self._combatConfig.MedicPostCombatCooldown or 3.0)
		local states = self:GetStates()
		if bot:InVehicle() then
			self:SetBotState(bot, states.VEHICLE)
		else
			self:SetBotState(bot, states.FOLLOW)
			self:ComeBackToPlayer(bot)

			local idleWep = self:GetBotIdleWeapon(bot)
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

        local idleWep = self:GetBotIdleWeapon(bot)

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
end

function Combat:SetupHooks()
    if not SERVER then return end

    local selfRef = self

	hook.Add("StartCommand", "AICompanion_MedicInFollow_v74", function(bot, cmd)
		if not selfRef:IsValid(bot) or not bot:IsBot() then return end
		if not bot:GetNWBool("IsAICompanion", false) then return end

		local botData = selfRef:GetBotData(bot)
		local states = selfRef:GetStates()
		local state = selfRef:GetBotState(bot)

		if state == states.VEHICLE or state == states.SITTING then return end

		if state == states.COMBAT or
		   state == states.PROTECT or
		   state == states.PROTECT_VEHICLE or
		   (states.COVER and state == states.COVER) then
			return
		end

		if botData and botData.combat and selfRef:IsValidTarget(botData.combat.target) and selfRef:SafeAlive(botData.combat.target) then
			return
		end

		local handled = selfRef:HandleMedicMode(bot, cmd)

		if handled then
			return true
		end

	end)

    hook.Add("StartCommand", "AICompanion_Combat_v74", function(bot, cmd)
        if not selfRef:IsValid(bot) or not bot:IsBot() then return end
        if not bot:GetNWBool("IsAICompanion", false) then return end

        local botData = selfRef:GetBotData(bot)
        if not botData then return end

		if not botData.combat.target or not selfRef:IsValidTarget(botData.combat.target) or not selfRef:SafeAlive(botData.combat.target) then

			if bot:InVehicle() then
				local states = selfRef:GetStates()
				local currentState = selfRef:GetBotState(bot)
				if currentState == states.PROTECT_VEHICLE or currentState == states.COMBAT then
					selfRef:SetBotState(bot, states.VEHICLE)
					if selfRef.utils then
						selfRef.utils.LogDebug("Combat", bot:Nick() .. " → VEHICLE (цель потеряна)")
					end
				end
			end
			return
		end

        selfRef:HandleCombat(bot, cmd)
    end)

    hook.Add("EntityFireBullets", "AICompanion_AimbotCorrection_v74", function(ent, data)
        return selfRef:HandleAimbotCorrection(ent, data)
    end)

    hook.Add("EntityTakeDamage", "AICompanion_AssistAndProtect_v74", function(victim, dmg)
        if selfRef.state and selfRef.state:getState("Disabled") then return end
        if not selfRef:IsValid(victim) then return end
        if not selfRef:IsValidTarget(victim) then return end

        local attacker = dmg:GetAttacker()
		if attacker == bot then return end
        if not selfRef:IsValid(attacker) then return end
        if not selfRef:IsValidTarget(attacker) then return end
        if attacker == victim or attacker:IsWorld() then return end

        local okAlive, attackerAlive = pcall(function() return attacker:Alive() end)
        if not okAlive or not attackerAlive then return end

        local bot = nil
        local allBots = selfRef:GetAllBots()
        for _, b in ipairs(allBots) do
            if selfRef:IsValid(b) then
                local owner = selfRef:GetBotOwner(b)
                if owner == attacker then
                    bot = b
                    break
                end
                if owner == victim then
                    bot = b
                    break
                end
            end
        end

        if not selfRef:IsValid(bot) and victim:IsPlayer() and victim:IsBot() and victim:GetNWBool("IsAICompanion", false) then
            bot = victim
        end

        if not selfRef:IsValid(bot) then return end
        if selfRef:IsPassenger(bot) then return end

        local botData = selfRef:GetBotData(bot)
        if not botData then return end
        if selfRef:IsPacifistMode(bot) then return end

        botData.combat.last_damage_time = CurTime()

        local owner = selfRef:GetBotOwner(bot)

        if selfRef:IsValid(owner) and attacker == owner and victim == bot then

            if botData.combat and botData.combat.triggered_by == "command_llm" and botData.combat.target == owner then
                return
            end
			if attacker == bot then return end
            botData.combat.target = attacker
            botData.combat.target_type = "player"
            botData.combat.triggered_by = "owner_attack"
            botData.combat.last_attack_time = CurTime()

            local states = selfRef:GetStates()
            selfRef:SetBotState(bot, states.COMBAT)
            selfRef:ForceCombatWeapon(bot)

            if selfRef:IsValid(bot) then
                bot:ChatPrint("[AI] Хозяин, прекратите! Защищаюсь!")
            end
            return
        end

        if victim == bot then

            if botData.combat and botData.combat.triggered_by == "command_llm" and selfRef:IsValid(botData.combat.target) then
                return
            end

            local dist = bot:GetPos():Distance(attacker:GetPos())
            local meleeDist = selfRef._combatConfig.MeleeDist or 110
            local meleeWep = selfRef:GetBotMeleeWeapon(bot)

            if dist < meleeDist and bot:HasWeapon(meleeWep) then
                return
            end
			if attacker == bot then return end
            botData.combat.target = attacker
            botData.combat.target_type = selfRef:IsPlayerSafe(attacker) and "player" or "npc"
            botData.combat.triggered_by = "damage"
            botData.combat.last_attack_time = CurTime()

            local states = selfRef:GetStates()
            selfRef:SetBotState(bot, states.COMBAT)
            selfRef:ForceCombatWeapon(bot)

            if selfRef:IsValid(bot) then
                local name = selfRef:IsPlayerSafe(attacker) and attacker:Nick() or selfRef:SafeGetClass(attacker)
                bot:ChatPrint("[AI] Меня атакуют! Защищаюсь от " .. name)
            end
            return
        end

        if selfRef:IsValid(owner) and attacker == owner and victim ~= bot then
            if not selfRef:IsDefenderMode(bot) then return end
            if not selfRef:IsValidTarget(victim) then return end
			if attacker == victim then return end
            local isTargetValid = victim:IsNPC() or victim:IsNextBot() or selfRef:IsPlayerSafe(victim)
            if isTargetValid then
                if botData.combat.target == victim then return end

                botData.combat.target = victim
                botData.combat.target_type = selfRef:IsPlayerSafe(victim) and "player" or "npc"
                botData.combat.triggered_by = "assist"
                botData.combat.last_attack_time = CurTime()

                local states = selfRef:GetStates()
                selfRef:SetBotState(bot, states.COMBAT)
                selfRef:ForceCombatWeapon(bot)

                if selfRef:IsValid(owner) then
                    local name = selfRef:IsPlayerSafe(victim) and victim:Nick() or victim:GetClass()
                    owner:ChatPrint("[AI] Помогаю уничтожить " .. name)
                end
            end
            return
        end

        if victim == owner then
            if not selfRef:IsDefenderMode(bot) then return end
            if not selfRef:IsValidTarget(attacker) then return end
            if botData.combat.target == attacker then return end
			if attacker == victim then return end
			if attacker == bot then return end
            botData.combat.target = attacker
            botData.combat.target_type = selfRef:IsPlayerSafe(attacker) and "player" or "npc"
            botData.combat.triggered_by = "protect"
            botData.combat.last_attack_time = CurTime()

            local states = selfRef:GetStates()
            selfRef:SetBotState(bot, states.PROTECT)
            selfRef:ForceCombatWeapon(bot)

            if selfRef:IsValid(bot) and selfRef:IsValid(owner) then
                local name = selfRef:IsPlayerSafe(attacker) and attacker:Nick() or selfRef:SafeGetClass(attacker)
                owner:ChatPrint("[AI] Защищаю вас от " .. name)
            end
            return
        end

        if selfRef:IsValid(victim) and victim.IsGlideVehicle then
            local vehicle = victim
            local driver = vehicle:GetDriver()
            if selfRef:IsValid(driver) and (driver == bot or driver == owner) then
                if not selfRef:IsDefenderMode(bot) then return end
                if not selfRef:IsValidTarget(attacker) then return end
                if botData.combat.target == attacker then return end
				if attacker == victim then return end
				if attacker == bot then return end
                botData.combat.target = attacker
                botData.combat.target_type = selfRef:IsPlayerSafe(attacker) and "player" or "npc"
                botData.combat.triggered_by = "protect_vehicle"
                botData.combat.last_attack_time = CurTime()

                local states = selfRef:GetStates()
                selfRef:SetBotState(bot, states.PROTECT_VEHICLE)
                selfRef:ForceCombatWeapon(bot)

                if selfRef:IsValid(bot) and selfRef:IsValid(owner) then
                    local name = selfRef:IsPlayerSafe(attacker) and attacker:Nick() or selfRef:SafeGetClass(attacker)
                    owner:ChatPrint("[AI] Атакуют наш транспорт! Защищаю от " .. name)
                end
            end
            return
        end
    end)

    hook.Add("PlayerDeath", "AICompanion_ForgetGrudge_v74", function(victim)
        if not selfRef:IsValid(victim) then return end

        local allBots = selfRef:GetAllBots()
        for _, bot in ipairs(allBots) do
            local botData = selfRef:GetBotData(bot)
            if botData and botData.combat and botData.combat.target == victim then
                botData.combat.last_combat_end = CurTime()
                selfRef:CleanupCombatState(bot)
            end
        end
    end)

    hook.Add("OnNPCKilled", "AICompanion_ForgetNPCGrudge_v74", function(npc, attacker, inflictor)
        if not selfRef:IsValid(npc) then return end

        local allBots = selfRef:GetAllBots()
        for _, bot in ipairs(allBots) do
            local botData = selfRef:GetBotData(bot)
            if botData and botData.combat and botData.combat.target == npc then
                botData.combat.last_combat_end = CurTime()
                selfRef:CleanupCombatState(bot)
            end
        end
    end)

    hook.Add("EntityRemoved", "AICompanion_TargetRemoved_v74", function(ent)
        if not selfRef:IsValid(ent) then return end

        local allBots = selfRef:GetAllBots()
        for _, bot in ipairs(allBots) do
            local botData = selfRef:GetBotData(bot)
            if botData and botData.combat and botData.combat.target == ent then
                botData.combat.last_combat_end = CurTime()
                selfRef:CleanupCombatState(bot)
            end
        end
    end)

    hook.Add("PlayerDisconnected", "AICompanion_TargetDisconnected_v74", function(ply)
        if not selfRef:IsValid(ply) then return end

        local allBots = selfRef:GetAllBots()
        for _, bot in ipairs(allBots) do
            local botData = selfRef:GetBotData(bot)
            if botData and botData.combat and botData.combat.target == ply then
                botData.combat.last_combat_end = CurTime()
                selfRef:CleanupCombatState(bot)
            end
        end
    end)

    hook.Add("PlayerSpawn", "AICompanion_ReFollowOnSpawn_v74", function(ply)
        if not selfRef:IsValid(ply) or selfRef:IsBotSafe(ply) then return end

        timer.Simple(0.1, function()
            if not selfRef:IsValid(ply) or not ply:Alive() then return end

            local allBots = selfRef:GetAllBots()
            for _, bot in ipairs(allBots) do
                if not selfRef:IsValid(bot) or not bot:Alive() then continue end

                local botData = selfRef:GetBotData(bot)
                if botData and botData.owner == ply then
                    if not botData.combat.target or not selfRef:IsValid(botData.combat.target) then
                        local states = selfRef:GetStates()
                        selfRef:SetBotState(bot, states.FOLLOW)
                        if selfRef:IsValid(bot) then
                            bot:ChatPrint("[AI] С возвращением! Снова следую за вами.")
                        end
                    end
                end
            end
        end)
    end)
end

function Combat:GetAPI()
    return {
        HandleCombat = function(bot, cmd) return self:HandleCombat(bot, cmd) end,
        HandleMedicMode = function(bot, cmd) return self:HandleMedicMode(bot, cmd) end,
        ForceCombatWeapon = function(bot) return self:ForceCombatWeapon(bot) end,
        ForceMeleeWeapon = function(bot) return self:ForceMeleeWeapon(bot) end,
        GetTargetAimPos = function(target) return self:GetTargetAimPos(target) end,
        CanSeeTarget = function(bot, target) return self:CanSeeTarget(bot, target) end,
        IsValidTarget = function(ent) return self:IsValidTarget(ent) end,
        IsHostileByDefault = function(ent, bot) return self:IsHostileByDefault(ent, bot) end,
        CleanupCombatState = function(bot) return self:CleanupCombatState(bot) end,
        SelectHighestThreat = function(bot, enemies) return self:SelectHighestThreat(bot, enemies) end,
        GetBotMode = function(bot, modeKey) return self:GetBotMode(bot, modeKey) end,
        IsMedicMode = function(bot) return self:IsMedicMode(bot) end,
        IsPacifistMode = function(bot) return self:IsPacifistMode(bot) end,
        IsDefenderMode = function(bot) return self:IsDefenderMode(bot) end,
        IsAggressiveMode = function(bot) return self:IsAggressiveMode(bot) end,
        IsStealthMode = function(bot) return self:IsStealthMode(bot) end,
        IsArmoredTarget = function(ent) return self:IsArmoredTarget(ent) end,
        IsFriendlyNPC = function(ent) return self:IsFriendlyNPC(ent) end,
        HasAnyAmmo = function(bot) return self:HasAnyAmmo(bot) end,
        HasAmmoForWeapon = function(bot, weapon) return self:HasAmmoForWeapon(bot, weapon) end,
        SelectBestWeapon = function(bot, target, dist) return self:SelectBestWeapon(bot, target, dist) end,
        GetThreatWeight = function(ent) return self:GetThreatWeight(ent) end,
        CombatMovement = function(bot, cmd, target, dist, isMelee, isRPG, isFrag)
            return self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag)
        end,
		IsMedicBlockedByCombat = function(bot, botData) return self:IsMedicBlockedByCombat(bot, botData) end,
		GetMedicHealTarget = function(bot, botData) return self:GetMedicHealTarget(bot, botData) end,
    }
end

return Combat
