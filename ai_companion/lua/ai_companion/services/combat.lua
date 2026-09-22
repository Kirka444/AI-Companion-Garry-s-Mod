-- Combat behavior, targeting, and weapon selection.

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
		_locator = nil,
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
		_zeroVec = Vector(0, 0, 0),
		_boneNames = {
			"ValveBiped.Bip01_Spine2",
			"ValveBiped.Bip01_Spine1",
			"ValveBiped.Bip01_Head",
			"ValveBiped.Bip01_Neck",
			"ValveBiped.Bip01_Pelvis"
		},
		_vecPool = {
			aimPos = Vector(), aimDir = Vector(), flatAim = Vector(),
			botPos = Vector(), tgtPos = Vector(), moveDir = Vector(),
			right = Vector(), backDir = Vector(), dodge = Vector(),
		},
		_reuseVec = Vector(0, 0, 0),
		_reuseVec2 = Vector(0, 0, 0),
		_reuseAng = Angle(0, 0, 0),
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
		local msg = self.utils
			and self.utils.GetLocale
			and self.utils:GetLocalized("log_combat_no_utils")
			or "[AI Combat] utils не передан!"
		error(msg)
	end
	if not self.botmanager then
		local msg = self.utils
			and self.utils.GetLocale
			and self.utils:GetLocalized("log_combat_no_bm")
			or "[AI Combat] botmanager не передан!"
		error(msg)
	end
	if SERVER then
		self:SetupHooks()
		self:StartScanTimer()
	end
	self._initialized = true
	self._locator = AICompanion.GetLocator()
	self._cachedMeleeDist = self._combatConfig.MeleeDist or 400
	self._cachedMeleeApproachDist = self._combatConfig.MeleeApproachDist or 70
	self._cachedMeleeSpeed = self._combatConfig.MeleeSpeed or 400
	self._cachedCombatSpeed = self._combatConfig.CombatSpeed or 220
	self._cachedIdealDist = self._combatConfig.IdealDist or 300
	self._cachedRPGDist = self._combatConfig.RPGDist or 500
	self._cachedCombatBackDist = self._combatConfig.CombatBackDist or 110
	self._cachedCombatStrafeDist = self._combatConfig.CombatStrafeDist or 100
	self._cachedStrafeMin = self._combatConfig.StrafeMinInterval or 0.3
	self._cachedStrafeMax = self._combatConfig.StrafeMaxInterval or 0.9
	self._cachedWeaponSwitchDelay = self._combatConfig.WeaponSwitchDelay or 5
	self._cachedMeleeGiveCooldown = self._combatConfig.MeleeGiveCooldown or 1.0
	self._cachedTickInterval = self._combatConfig.TacticalUpdateInterval or 0.07
	self._cachedAmmoGiveAmount = self._combatConfig.AmmoGiveAmount or 100
	self._cachedRPGCooldown = self._combatConfig.RPGCooldown or 0.1
	self._cachedAltFireCooldown = self._combatConfig.AltFireCooldown or 2.0
	self._cachedOwnerAttackGrace = self._combatConfig.OwnerAttackGrace or 5.0
	self._cachedMedicCombatGrace = self._combatConfig.MedicCombatGrace or 2.0
	self._cachedHealCooldown = self._combatConfig.HealCooldown or 1.2
	self._cachedHealRange = self._combatConfig.HealRange or 140
	self._cachedHealThresholdSelf = self._combatConfig.HealThresholdSelf or 0.55
	self._cachedHealThresholdOwner = self._combatConfig.HealThresholdOwner or 0.7
	self._cachedMedicMoveSpeed = self._combatConfig.MedicMoveSpeed or 300
	self._cachedMedicPostCombatCooldown = self._combatConfig.MedicPostCombatCooldown or 3.0
	self._cachedEnemyCacheInterval = self._combatConfig.EnemyCacheInterval or 2.0
	self._cachedThreatScanInterval = self._combatConfig.ThreatScanInterval or 3.0
	self._cachedThreatScanRadius = self._combatConfig.ThreatScanRadius or 1500
	self._cachedFragMinDist = self._combatConfig.FragMinDist or 150
	self._grenadeCacheGlobal = {}
	self._grenadeCacheGlobalTime = 0
	self._wepCrowbar = "weapon_crowbar"
	self._wepStunstick = "weapon_stunstick"
	self._wepRPG = "weapon_rpg"
	self._wepMedkit = "weapon_medkit"
	self._wepSMG1 = "weapon_smg1"
	self._bitAttack = IN_ATTACK
	self._bitAttack2 = IN_ATTACK2
	self._bitJump = IN_JUMP
	self._bitDuck = IN_DUCK
	self._mathSqrt = math.sqrt
	self._mathClamp = math.Clamp
	self._mathRand = math.Rand
	self._mathRandom = math.random
	self._mathMax = math.max
	self._cachedProtectVehicles = self._combatConfig.ProtectVehicles ~= false
	self._cachedRetaliateOwnerVehicleDamage = self._combatConfig.RetaliateOwnerVehicleDamage ~= false
	self._cachedOwnerVehicleGrace = self._combatConfig.OwnerVehicleGrace or 10
	if self.utils then
		self.utils.LogInfo("Combat", self.utils:GetLocalized("log_combat_init"))
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
	return ent:GetClass() or "error"
end
function Combat:SafeGetPos(ent)
	if not self:IsValid(ent) then return self._zeroVec end
	return ent:GetPos()
end
function Combat:SafeAlive(ent)
	if not self:IsValid(ent) then return false end
	return ent:Alive()
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
	local locator = self._locator or AICompanion.GetLocator()
	if not self._locator then self._locator = locator end
	if not locator then return end
	local movement = locator:get("movement")
	if not movement then return end
	movement:ComeBackToPlayer(bot)
end
function Combat:IsPassenger(bot, cache)
	if cache then
		return cache.isPassenger
	end
	if not self:IsValid(bot) then return false end
	if not bot:InVehicle() then return false end
	local veh = bot:GetVehicle()
	if not veh then return true end
	local locator = self._locator or AICompanion.GetLocator()
	if not self._locator then self._locator = locator end
	local vehicleService = locator and locator:get("vehicle")
	local driver = nil
	if vehicleService then
		local root = vehicleService:GetGlideRoot(veh) or veh
		local driverSeat = vehicleService:GetDriverSeat(root)
		if driverSeat and driverSeat.GetDriver then
			driver = driverSeat:GetDriver()
		end
	end
	if not driver and veh.GetDriver then
		driver = veh:GetDriver()
	end
	if driver == bot then return false end
	return true
end
function Combat:ApplyWorldMovement(cmd, dir, speed)
	if not cmd then return end
	if not dir or dir:LengthSqr() <= 0.001 then return end
	if not speed or speed <= 0 then return end
	local locator = self._locator or AICompanion.GetLocator()
	if not self._locator then self._locator = locator end
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
function Combat:GetVehicleService()
	local locator = self._locator or AICompanion.GetLocator()
	self._locator = locator
	return locator and locator:get("vehicle")
end
function Combat:IsProtectedVehicle(ent)
	if not self:IsValid(ent) then return false end
	local veh = self:GetVehicleService()
	if veh then
		if veh.IsGlideVehicle and veh:IsGlideVehicle(ent) then
			return true
		end
		if veh.IsHL2Vehicle and veh:IsHL2Vehicle(ent) then
			return true
		end
		if veh.ResolveVehicleRoot then
			local ok, root = pcall(veh.ResolveVehicleRoot, veh, ent)
			if ok and self:IsValid(root) and root ~= ent then
				return self:IsProtectedVehicle(root)
			end
		end
	end
	local class = self:SafeGetClass(ent)
	if ent.IsVehicle and ent:IsVehicle() then
		return true
	end
	return class == "prop_vehicle_jeep"
		or class == "prop_vehicle_airboat"
		or class == "prop_vehicle_apc"
		or class == "prop_vehicle_prisoner_pod"
		or class == "prop_vehicle_driveable"
		or string.find(class, "prop_vehicle") ~= nil
end
function Combat:GetVehicleRoot(ent)
	if not self:IsValid(ent) then return nil end
	local veh = self:GetVehicleService()
	if veh then
		if veh.ResolveVehicleRoot then
			local ok, root = pcall(veh.ResolveVehicleRoot, veh, ent)
			if ok and self:IsValid(root) then
				return root
			end
		end
		if veh.GetGlideRoot then
			local ok, root = pcall(veh.GetGlideRoot, veh, ent)
			if ok and self:IsValid(root) then
				return root
			end
		end
	end
	return ent
end
function Combat:GetVehicleDriver(root)
	if not self:IsValid(root) then return nil end
	local veh = self:GetVehicleService()
	if veh and veh.GetDriverSeat then
		local ok, seat = pcall(veh.GetDriverSeat, veh, root)
		if ok and self:IsValid(seat) and seat.GetDriver then
			local d = seat:GetDriver()
			if self:IsValid(d) then
				return d
			end
		end
	end
	if root.GetDriver then
		local d = root:GetDriver()
		if self:IsValid(d) then
			return d
		end
	end
	return nil
end
function Combat:IsBotVehicle(bot, root)
	if not self:IsValid(bot) or not self:IsValid(root) then
		return false
	end
	local data = self:GetBotData(bot)
	if data and data.vehicle then
		if self:IsValid(data.vehicle.locked_vehicle) then
			local lockRoot = self:GetVehicleRoot(data.vehicle.locked_vehicle)
			if lockRoot == root then
				return true
			end
		end
		if self:IsValid(data.vehicle.owner_vehicle) then
			local ownerRoot = self:GetVehicleRoot(data.vehicle.owner_vehicle)
			if ownerRoot == root then
				return true
			end
		end
	end
	if bot:InVehicle() then
		local botVeh = bot:GetVehicle()
		if self:IsValid(botVeh) then
			local botRoot = self:GetVehicleRoot(botVeh)
			if botRoot == root then
				return true
			end
		end
	end
	return false
end
function Combat:GetDamageAttackerEntity(attacker)
	if not self:IsValid(attacker) then
		return attacker
	end
	if self:IsProtectedVehicle(attacker) then
		local root = self:GetVehicleRoot(attacker)
		local driver = self:GetVehicleDriver(root)
		if self:IsValid(driver) then
			return driver
		end
	end
	return attacker
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
	local now = CurTime()
	local cacheKey = bot:EntIndex() .. "_" .. target:EntIndex()
	if bot._aiCanSeeCache and bot._aiCanSeeCache.key == cacheKey
	   and bot._aiCanSeeCache.time and (now - bot._aiCanSeeCache.time) < 0.15 then
		return bot._aiCanSeeCache.result
	end
	local tr = util.TraceLine({
		start = bot:EyePos(),
		endpos = target:WorldSpaceCenter(),
		filter = bot,
		mask = MASK_SHOT
	})
	local result = false
	if not tr.Hit then
		result = true
	elseif self:IsValid(tr.Entity) and tr.Entity == target then
		result = true
	end
	bot._aiCanSeeCache = {
		key = cacheKey,
		result = result,
		time = now
	}
	return result
end
function Combat:GetCachedBonePos(target)
	if not self:IsValid(target) then return nil end
	if not target._aiBoneCache then
		target._aiBoneCache = {}
		for _, name in ipairs(self._boneNames) do
			local bone = target:LookupBone(name)
			if bone then
				target._aiBoneCache.boneID = bone
				break
			end
		end
	end
	if target._aiBoneCache.boneID then
		local pos = target:GetBonePosition(target._aiBoneCache.boneID)
		if pos and pos.x and pos.x ~= 0 then return pos end
	end
	return nil
end
function Combat:GetTargetAimPos(target, useCache)
	if not self:IsValid(target) then return self._zeroVec end
	if useCache and target._aiCachedAimPos then
		local cache = target._aiCachedAimPos
		if CurTime() - cache.time < 0.3 then
			return cache.pos
		end
	end
	local result = nil
	if target:IsPlayer() then
		result = target:EyePos()
	elseif target:IsNPC() or target:IsNextBot() then
		local bonePos = self:GetCachedBonePos(target)
		if bonePos then
			result = bonePos
		else
			local wsc = target:WorldSpaceCenter()
			if wsc then
				result = wsc
			else
				local pos = target:GetPos()
				local mn, mx = target:GetCollisionBounds()
				if mn and mx then
					result = pos + Vector(0, 0, (mn.z + mx.z) * 0.5)
				else
					result = pos
				end
			end
		end
	else
		local wsc = target:WorldSpaceCenter()
		if wsc then
			result = wsc
		else
			result = target:GetPos() + Vector(0, 0, 32)
		end
	end
	if useCache then
		target._aiCachedAimPos = {
			pos = result,
			time = CurTime()
		}
	end
	return result
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
	local meleeDist = self._combatConfig.MeleeDist or 400
	if dist <= meleeDist and not self:IsArmoredTarget(target) then
		local meleeWep = self:GetBotMeleeWeapon(bot)
		if not bot:HasWeapon(meleeWep) then
			self:SafeGiveWeapon(bot, meleeWep)
		end
		if bot:HasWeapon(meleeWep) then
			if not botData.combat then botData.combat = {} end
			botData.combat._weaponCache = { weapon = meleeWep, mode = "melee", time = CurTime() }
			return meleeWep, "melee"
		end
	end
	local combat = botData.combat or {}
	local wc = combat._weaponCache
	local now = CurTime()
	if wc and wc.weapon and (now - wc.time) < 0.5 then
		return wc.weapon, wc.mode
	end
	local function cacheAndReturn(wep, mode)
		if not botData.combat then botData.combat = {} end
		botData.combat._weaponCache = { weapon = wep, mode = mode, time = CurTime() }
		return wep, mode
	end
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
		return cacheAndReturn("weapon_rpg", "rpg")
	end
	if not self:HasAnyAmmo(bot) then
		if not bot:HasWeapon(meleeWep) then
			self:SafeGiveWeapon(bot, meleeWep)
		end
		return cacheAndReturn(meleeWep, "melee")
	end
	local meleeDist = self._combatConfig.MeleeDist or 400
	local currentMode = wc and wc.mode
	if currentMode == "melee" and dist <= meleeDist * 1.25 then
		if not bot:HasWeapon(meleeWep) then
			self:SafeGiveWeapon(bot, meleeWep)
		end
		if bot:HasWeapon(meleeWep) then
			return cacheAndReturn(meleeWep, "melee")
		end
	end
	if dist <= meleeDist then
		if not bot:HasWeapon(meleeWep) then
			self:SafeGiveWeapon(bot, meleeWep)
		end
		if bot:HasWeapon(meleeWep) then
			return cacheAndReturn(meleeWep, "melee")
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
			return cacheAndReturn(meleeWep, "melee")
		end
	end
	return cacheAndReturn(combatWep, "combat")
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
function Combat:UpdateGrenadeCacheGlobal()
	local now = CurTime()
	if self._grenadeCacheGlobalTime and (now - self._grenadeCacheGlobalTime) < 0.3 then return end
	self._grenadeCacheGlobalTime = now
	self._grenadeCacheGlobal = {}
	local grenades = ents.FindByClass("npc_grenade_frag")
	for _, ent in ipairs(grenades) do
		if self:IsValid(ent) then
			table.insert(self._grenadeCacheGlobal, {
				ent = ent,
				pos = ent:GetPos(),
				lastPosUpdate = now
			})
		end
	end
end
function Combat:HandleGrenadeDodge(bot, cmd)
	if not self:IsValid(bot) or not cmd then return false end
	self:UpdateGrenadeCacheGlobal()
	if #self._grenadeCacheGlobal == 0 then return false end
	local botPos = self:SafeGetPos(bot)
	local dodge = Vector(0, 0, 0)
	local closestDist = 999999
	local dangerDist = self._combatConfig.GrenadeDangerDist or 110
	local now = CurTime()
	for _, entry in ipairs(self._grenadeCacheGlobal) do
		local grenade = entry.ent
		if self:IsValid(grenade) then
			local gPos = entry.pos
			if now - (entry.lastPosUpdate or 0) > 0.1 then
				gPos = grenade:GetPos()
				entry.pos = gPos
				entry.lastPosUpdate = now
			end
			local dir = botPos - gPos
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
	local now = CurTime()
	if not bot._aiMedicWeaponCache or (now - bot._aiMedicWeaponCache.time) > 0.5 then
		bot._aiMedicWeaponCache = {
			hasWeapon = bot:HasWeapon("weapon_medkit"),
			time = now
		}
	end
	if not bot._aiMedicWeaponCache.hasWeapon then
		self:SafeGiveWeapon(bot, "weapon_medkit")
		bot._aiMedicWeaponCache.hasWeapon = true
		bot._aiMedicWeaponCache.time = now
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
			local btns = cmd:GetButtons()
			cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
			bot:RemoveFlags(FL_DUCKING)
			bot:RemoveFlags(FL_ANIMDUCKING)
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
	local mn, mx = healTarget:GetCollisionBounds()
	if mn and mx then
		aimPos = targetPos + Vector(0, 0, (mn.z + mx.z) * 0.5)
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
			local btns = cmd:GetButtons()
			cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
			bot:RemoveFlags(FL_DUCKING)
			bot:RemoveFlags(FL_ANIMDUCKING)
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
		local now = CurTime()
		local moveDir = botData.combat._medicMoveDir
		if not botData.combat._lastMedicMoveCalc or (now - botData.combat._lastMedicMoveCalc) > 0.15 then
			local locator = self._locator or AICompanion.GetLocator()
			local movement = locator and locator:get("movement")
			if movement and movement.MoveToTarget then
				movement:MoveToTarget(bot, cmd, targetPos, healTarget)
				moveDir = nil
			else
				moveDir = targetPos - botPos
				moveDir.z = 0
				if moveDir:LengthSqr() > 0.001 then
					moveDir:Normalize()
				else
					moveDir = nil
				end
			end
			botData.combat._medicMoveDir = moveDir
			botData.combat._lastMedicMoveCalc = now
		end
		if moveDir and moveDir:LengthSqr() > 0.001 then
			self:ApplyWorldMovement(cmd, moveDir, self._combatConfig.MedicMoveSpeed or 300)
		end
	end
	return true
end
function Combat:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag, aimPos)
	if not self:IsValid(bot) or not self:IsValid(target) or not cmd then return end
	local botData = self:GetBotData(bot)
	if not botData then return end
	local botPos = self:SafeGetPos(bot)
	local targetPos = self:SafeGetPos(target)
	local idealDist = self._combatConfig.IdealDist or 300
	if isMelee then
		idealDist = self._combatConfig.MeleeDist or 400
	elseif isRPG then
		idealDist = self._combatConfig.RPGDist or 500
	elseif isFrag then
		idealDist = (self._combatConfig.FragMinDist or 150) + 50
	end
	local aimPos = aimPos or self:GetTargetAimPos(target, true)
	local aimDir = aimPos - bot:EyePos()
	if aimDir:LengthSqr() < 0.001 then aimDir = Vector(1, 0, 0) end
	aimDir:Normalize()
	local flatAim = Vector(aimDir.x, aimDir.y, 0)
	if flatAim:LengthSqr() < 0.001 then flatAim = Vector(1, 0, 0) end
	flatAim:Normalize()
	local useNav = false
	local movePos = nil
	local meleeApproach = self._combatConfig.MeleeApproachDist or 70
	if isMelee then
		if dist > meleeApproach then
			local runDir = targetPos - botPos
			runDir.z = 0
			if runDir:LengthSqr() > 0.001 then
				runDir:Normalize()
				self:ApplyWorldMovement(cmd, runDir, self._combatConfig.MeleeSpeed or 400)
			end
			return
		else
			if not botData.combat.next_strafe_change or CurTime() > botData.combat.next_strafe_change then
				botData.combat.strafe_dir = math.random() > 0.5 and 1 or -1
				botData.combat.next_strafe_change = CurTime() + math.Rand(0.15, 0.4)
			end
			local rgt = aimDir:Angle():Right()
			rgt.z = 0
			if rgt:LengthSqr() < 0.001 then
				rgt = Vector(0, 1, 0)
			end
			rgt:Normalize()
			local pull = flatAim * math.Clamp((meleeApproach - dist) * 3.0, 0, 100)
			movePos = botPos + rgt * botData.combat.strafe_dir * 5 + pull
		end
	else
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
			if rgt:LengthSqr() < 0.001 then
				rgt = Vector(0, 1, 0)
			end
			rgt:Normalize()
			local combatStrafeDist = self._combatConfig.CombatStrafeDist or 100
			movePos = botPos + rgt * botData.combat.strafe_dir * combatStrafeDist
		end
	end
	if useNav then
		local locator = self._locator or AICompanion.GetLocator()
		if not self._locator then self._locator = locator end
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
			local meleeSpeed = self._combatConfig.MeleeSpeed or 400
			local combatSpeed = self._combatConfig.CombatSpeed or 220
			local moveSpeed = isMelee and meleeSpeed or combatSpeed
			self:ApplyWorldMovement(cmd, runDir, moveSpeed)
		end
	end
	local btns = cmd:GetButtons()
	cmd:SetButtons(bit.band(btns, bit.bnot(IN_DUCK)))
	bot:RemoveFlags(FL_DUCKING)
	bot:RemoveFlags(FL_ANIMDUCKING)
	bot._aiStealthCrouch = false
end
function Combat:InitTargetQueue(botData)
	if not botData then return end
	if not botData.combat then
		botData.combat = {}
	end
	if not botData.combat.target_queue then
		botData.combat.target_queue = {}
	end
end
function Combat:AddToTargetQueue(bot, ent, reason)
	if not self:IsValid(bot) or not self:IsValid(ent) then return false end
	if ent == bot then return false end
	local botData = self:GetBotData(bot)
	if not botData then return false end
	self:InitTargetQueue(botData)
	local priorityMap = {
		["owner_attack"] = 5,
		["protect"] = 4,
		["protect_vehicle"] = 4,
		["damage"] = 3,
		["assist"] = 2,
		["aggressive"] = 1,
		["command_llm"] = 6,
	}
	for _, entry in ipairs(botData.combat.target_queue) do
		if entry.ent == ent then
			local newPrio = priorityMap[reason] or 1
			local oldPrio = priorityMap[entry.reason] or 1
			if newPrio > oldPrio then
				entry.reason = reason
				entry.added = CurTime()
				self:_SortQueue(botData.combat.target_queue, priorityMap)
			end
			return true
		end
	end
	table.insert(botData.combat.target_queue, {
		ent = ent,
		reason = reason,
		added = CurTime(),
	})
	self:_SortQueue(botData.combat.target_queue, priorityMap)
	if self.utils then
		self.utils.LogDebug("Combat",
	bot:Nick() .. " добавлен в очередь: " .. self:SafeGetClass(ent) ..
	" (" .. reason .. "), размер очереди: " .. #botData.combat.target_queue)
	end
	return true
end
function Combat:_SortQueue(queue, priorityMap)
	priorityMap = priorityMap or {
		["command_llm"] = 6,
		["owner_attack"] = 5,
		["protect"] = 4,
		["protect_vehicle"] = 4,
		["damage"] = 3,
		["assist"] = 2,
		["aggressive"] = 1,
	}
	table.sort(queue, function(a, b)
		local pa = priorityMap[a.reason] or 1
		local pb = priorityMap[b.reason] or 1
		if pa ~= pb then
			return pa > pb
		end
		return a.added < b.added
	end)
end
function Combat:RemoveFromTargetQueue(bot, ent)
	if not self:IsValid(bot) then return end
	local botData = self:GetBotData(bot)
	if not botData or not botData.combat or not botData.combat.target_queue then return end
	for i = #botData.combat.target_queue, 1, -1 do
		if botData.combat.target_queue[i].ent == ent then
			table.remove(botData.combat.target_queue, i)
		end
	end
end
function Combat:ClearTargetQueue(bot)
	if not self:IsValid(bot) then return end
	local botData = self:GetBotData(bot)
	if not botData or not botData.combat then return end
	botData.combat.target_queue = {}
	botData.combat.target = nil
end
function Combat:UpdateTargetQueue(bot)
	if not self:IsValid(bot) then return end
	local botData = self:GetBotData(bot)
	if not botData or not botData.combat or not botData.combat.target_queue then return end
	for i = #botData.combat.target_queue, 1, -1 do
		local entry = botData.combat.target_queue[i]
		if not self:IsValid(entry.ent) or not self:SafeAlive(entry.ent) then
			table.remove(botData.combat.target_queue, i)
		end
	end
end
function Combat:GetNextTargetFromQueue(bot)
	if not self:IsValid(bot) then return nil end
	local botData = self:GetBotData(bot)
	if not botData or not botData.combat or not botData.combat.target_queue then return nil end
	self:UpdateTargetQueue(bot)
	if self.utils then
		local queueSize = #botData.combat.target_queue
		self.utils.LogDebug("Combat",
			bot:Nick() .. " GetNextTargetFromQueue, очередь после очистки: " .. queueSize)
	end
	for _, entry in ipairs(botData.combat.target_queue) do
		if self:IsValid(entry.ent) and self:SafeAlive(entry.ent) and self:IsValidTarget(entry.ent) then
			return entry.ent, entry.reason
		end
	end
	return nil, nil
end
function Combat:ShouldAbortQueue(bot)
	if not self:IsValid(bot) or not bot:Alive() then
		return true
	end
	local owner = self:GetBotOwner(bot)
	if not self:IsValid(owner) or not owner:Alive() then
		return true
	end
	return false
end
function Combat:AdvanceToNextTarget(bot)
	if not self:IsValid(bot) then return false end
	local botData = self:GetBotData(bot)
	if not botData or not botData.combat then return false end
	if botData.state == "stopped" then
		return false
	end
	if self.utils then
		self.utils.LogDebug("Combat", bot:Nick() .. " AdvanceToNextTarget, очередь: " .. #botData.combat.target_queue)
	end
	if botData.combat.target then
		self:RemoveFromTargetQueue(bot, botData.combat.target)
	end
	botData.combat.target = nil
	local nextTarget, reason = self:GetNextTargetFromQueue(bot)
	if nextTarget and self:IsValid(nextTarget) and self:SafeAlive(nextTarget) then
		botData.combat.target = nextTarget
		botData.combat.target_type = self:IsPlayerSafe(nextTarget) and "player" or "npc"
		botData.combat.triggered_by = reason or "queue"
		botData.combat.last_attack_time = CurTime()
		local states = self:GetStates()
		self:SetBotState(bot, states.COMBAT)
		self:ForceCombatWeapon(bot)
		if self:IsValid(bot) then
			local now = CurTime()
			if not bot._lastNextTargetChat or (now - bot._lastNextTargetChat) > 2.0 then
				local name = self:IsPlayerSafe(nextTarget) and nextTarget:Nick() or self:SafeGetClass(nextTarget)
				bot:ChatPrint(self.utils:GetLocalized("bot_next_target", name))
				bot._lastNextTargetChat = now
			end
		end
		return true
	else
		self:CleanupCombatState(bot, false)
		return false
	end
end
function Combat:RequestTarget(bot, ent, reason, force)
	if not self:IsValid(bot) or not self:IsValid(ent) then return false end
	if ent == bot then return false end
	local botData = self:GetBotData(bot)
	if not botData then return false end
	self:InitTargetQueue(botData)
	if force then
		self:ClearTargetQueue(bot)
		botData.combat.target = ent
		botData.combat.target_type = self:IsPlayerSafe(ent) and "player" or "npc"
		botData.combat.triggered_by = reason or "forced"
		botData.combat.last_attack_time = CurTime()
		local states = self:GetStates()
		self:SetBotState(bot, states.COMBAT)
		self:ForceCombatWeapon(bot)
		return true
	end
	self:AddToTargetQueue(bot, ent, reason)
	local currentTarget = botData.combat.target
	if not self:IsValidTarget(currentTarget) or not self:SafeAlive(currentTarget) then
		return self:AdvanceToNextTarget(bot)
	end
	return true
end
function Combat:HandleCombat(bot, cmd, cache)
	if not self:IsValid(bot) then return false end
	if not bot:Alive() then return false end
	local botData = self:GetBotData(bot)
	if not botData then return false end
	if not botData.combat then botData.combat = {} end
	if botData.state == "stopped" then
		botData.combat.target = nil
		botData.combat.target_type = nil
		botData.combat.triggered_by = nil
		botData.combat.target_queue = {}
		return false
	end
	local isInVehicle = cache and cache.inVehicle or bot:InVehicle()
	if isInVehicle then
		local isDriver = cache and cache.isDriver
		if isDriver == nil then
			isDriver = not self:IsPassenger(bot)
			if cache then cache.isDriver = isDriver end
		end
		if not isDriver then
			if botData.combat then botData.combat.target = nil end
			return false
		end
	end
	if cache and cache.pacifist then
		self:ClearTargetQueue(bot)
		self:CleanupCombatState(bot, false)
		return false
	end
	if self:IsPacifistMode(bot) then
		if cache then cache.pacifist = true end
		self:ClearTargetQueue(bot)
		self:CleanupCombatState(bot, false)
		return false
	end
	self:InitTargetQueue(botData)
	local owner = botData._cachedOwner
	if not owner or not self:IsValid(owner) then
		owner = self:GetBotOwner(bot)
		botData._cachedOwner = owner
	end
	if not self:IsValid(owner) or not owner:Alive() then
		self:ClearTargetQueue(bot)
		self:CleanupCombatState(bot, false)
		return false
	end
	local target = botData.combat.target
	if not self:IsValidTarget(target) or not self:SafeAlive(target) then
		local hasNext = self:AdvanceToNextTarget(bot)
		if hasNext then return true end
		return false
	end
	if target:IsPlayer() and target == owner then
		local grace = self._cachedOwnerAttackGrace
		local trigger = botData.combat.triggered_by
		if trigger ~= "protect_vehicle" then
			if botData.combat.last_damage_time and (CurTime() - botData.combat.last_damage_time > grace) then
				self:RemoveFromTargetQueue(bot, owner)
				return self:AdvanceToNextTarget(bot)
			end
		end
	end
	if isInVehicle then
		botData.combat.last_attack_time = CurTime()
		local states = self:GetStates()
		local currentState = self:GetBotState(bot)
		if currentState ~= states.PROTECT_VEHICLE and currentState ~= states.COMBAT then
			self:SetBotState(bot, states.PROTECT_VEHICLE)
		end
		return true
	end
	local now = CurTime()
	local botPos = bot:GetPos()
	local targetPos = target:GetPos()
	local dx = targetPos.x - botPos.x
	local dy = targetPos.y - botPos.y
	local dz = targetPos.z - botPos.z
	local distSqr = dx*dx + dy*dy + dz*dz
	local dist = self._mathSqrt(distSqr)
	local meleeDist = self._cachedMeleeDist
	local meleeDistSqr = meleeDist * meleeDist
	local tickInterval = self._cachedTickInterval
	local lastTacticalUpdate = botData.combat._lastTacticalUpdate
	local doTacticalUpdate = not lastTacticalUpdate
		or (now - lastTacticalUpdate) >= tickInterval
	if doTacticalUpdate then
		botData.combat._lastTacticalUpdate = now
		if distSqr <= meleeDistSqr then
			local meleeWep = self:GetBotMeleeWeapon(bot)
			if not bot:HasWeapon(meleeWep) then
				local lastMeleeGive = botData.combat.last_melee_give or 0
				if now - lastMeleeGive > self._cachedMeleeGiveCooldown then
					self:SafeGiveWeapon(bot, meleeWep)
					botData.combat.last_melee_give = now
					if meleeWep ~= self._wepCrowbar and meleeWep ~= self._wepStunstick then
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
					if botData.combat.weapon_switch_wait < self._cachedWeaponSwitchDelay then
						botData.combat._cachedDesiredWep = meleeWep
						botData.combat._cachedWeaponMode = "melee"
						botData.combat._cachedIsMelee = true
						botData.combat._cachedIsRPG = false
						botData.combat._cachedIsFrag = false
						self:CombatMovement(bot, cmd, target, dist, true, false, false)
						return true
					end
					botData.combat.weapon_switch_wait = 0
				else
					botData.combat.weapon_switch_wait = 0
				end
				aw = bot:GetActiveWeapon()
				if self:IsValid(aw) and aw:GetClass() == meleeWep then
					local aimPos = botData.combat._cachedAimPosWorld
					if not botData.combat._lastAimCalc or (now - botData.combat._lastAimCalc) > 0.05 then
						aimPos = self:GetTargetAimPos(target, false)
						botData.combat._cachedAimPosWorld = aimPos
						botData.combat._lastAimCalc = now
					end
					local eyePos = bot:EyePos()
					local aDx = aimPos.x - eyePos.x
					local aDy = aimPos.y - eyePos.y
					local aDz = aimPos.z - eyePos.z
					local aLenSqr = aDx*aDx + aDy*aDy + aDz*aDz
					if aLenSqr > 0.001 then
						local aInvLen = 1.0 / self._mathSqrt(aLenSqr)
						aDx, aDy, aDz = aDx * aInvLen, aDy * aInvLen, aDz * aInvLen
						local aimDir = self._reuseVec
						aimDir.x, aimDir.y, aimDir.z = aDx, aDy, aDz
						local aimAng = aimDir:Angle()
						bot:SetEyeAngles(aimAng)
						cmd:SetViewAngles(aimAng)
						bot._aiAimDir = aimDir
						botData.combat.last_attack_time = now
						if self:CanSeeTarget(bot, target) then
							cmd:SetButtons(bit.bor(cmd:GetButtons(), self._bitAttack))
						end
						local approachDist = self._cachedMeleeApproachDist
						local approachDistSqr = approachDist * approachDist
						local moveDir = self._reuseVec2
						if distSqr > approachDistSqr then
							local runLen = self._mathSqrt(distSqr)
							if runLen > 0.001 then
								local invRun = 1.0 / runLen
								moveDir.x = dx * invRun
								moveDir.y = dy * invRun
								moveDir.z = 0
							end
						else
							if not botData.combat.next_strafe_change or now > botData.combat.next_strafe_change then
								botData.combat.strafe_dir = self._mathRandom() > 0.5 and 1 or -1
								botData.combat.next_strafe_change = now + self._mathRand(0.25, 0.75)
							end
							local rgt = aimAng:Right()
							rgt.z = 0
							if rgt:LengthSqr() < 0.001 then
								rgt.x, rgt.y, rgt.z = 0, 1, 0
							else
								rgt:Normalize()
							end
							local side = rgt * botData.combat.strafe_dir * 12
							local closePull = dx * self._mathClamp(approachDist - dist, 0, 40) * 1.2
							moveDir.x = side.x + closePull
							moveDir.y = side.y + closePull
							moveDir.z = 0
						end
						local lastMeleeMoveCalc = botData.combat._lastMeleeMoveCalc
						if not lastMeleeMoveCalc or (now - lastMeleeMoveCalc) > 0.15 then
							local checkTr = util.TraceLine({
								start = botPos + Vector(0, 0, 20),
								endpos = botPos + Vector(0, 0, 20) + moveDir * 40,
								filter = {bot, target},
								mask = MASK_SOLID
							})
							if checkTr.Hit and checkTr.Fraction < 0.3 then
								moveDir.x, moveDir.y, moveDir.z = 0, 0, 0
							end
							botData.combat._cachedMeleeMoveDir = {x = moveDir.x, y = moveDir.y, z = moveDir.z}
							botData.combat._lastMeleeMoveCalc = now
						else
							local cached = botData.combat._cachedMeleeMoveDir
							if cached then
								moveDir.x, moveDir.y, moveDir.z = cached.x, cached.y, cached.z
							end
						end
						if moveDir:LengthSqr() > 0.001 then
							self:ApplyWorldMovement(cmd, moveDir, self._cachedMeleeSpeed)
						end
						botData.combat._cachedDesiredWep = meleeWep
						botData.combat._cachedWeaponMode = "melee"
						botData.combat._cachedIsMelee = true
						botData.combat._cachedIsRPG = false
						botData.combat._cachedIsFrag = false
						return true
					end
				end
			end
		end
		local desiredWep, weaponMode = self:SelectBestWeapon(bot, target, dist)
		if distSqr <= meleeDistSqr and weaponMode ~= "rpg" then
			desiredWep = self:GetBotMeleeWeapon(bot)
			weaponMode = "melee"
		end
		local isMelee = (weaponMode == "melee") or (desiredWep == self._wepCrowbar or desiredWep == self._wepStunstick)
		local isRPG = weaponMode == "rpg"
		local isFrag = false
		if not bot:HasWeapon(desiredWep) then
			self:SafeGiveWeapon(bot, desiredWep)
			local waitTicks = (desiredWep == self._wepRPG) and 3 or 1
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
			if botData.combat.weapon_switch_wait < self._cachedWeaponSwitchDelay then
				self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag)
				return true
			end
			botData.combat.weapon_switch_wait = 0
		else
			botData.combat.weapon_switch_wait = 0
		end
		if self.config:get("INFINITE_AMMO") then
			local wep = bot:GetActiveWeapon()
			if self:IsValid(wep) and wep:Clip1() <= 0 then
				local ammoType = wep:GetPrimaryAmmoType()
				if ammoType and ammoType ~= -1 then
					bot:GiveAmmo(self._cachedAmmoGiveAmount, ammoType, true)
					local maxClip = wep:GetMaxClip1()
					wep:SetClip1(maxClip > 0 and maxClip or 30)
				end
			end
		end
		botData.combat._cachedDesiredWep = desiredWep
		botData.combat._cachedWeaponMode = weaponMode
		botData.combat._cachedIsMelee = isMelee
		botData.combat._cachedIsRPG = isRPG
		botData.combat._cachedIsFrag = isFrag
	end
	local forceMelee = (distSqr <= meleeDistSqr)
	local desiredWep = botData.combat._cachedDesiredWep or self:GetBotCombatWeapon(bot)
	local weaponMode = botData.combat._cachedWeaponMode or "combat"
	local isMelee = forceMelee or (botData.combat._cachedIsMelee == true)
	local isRPG = botData.combat._cachedIsRPG or false
	local isFrag = botData.combat._cachedIsFrag or false
	if forceMelee and not isRPG then
		local meleeWep = self:GetBotMeleeWeapon(bot)
		if not bot:HasWeapon(meleeWep) then
			self:SafeGiveWeapon(bot, meleeWep)
		end
		local aw = bot:GetActiveWeapon()
		if self:IsValid(aw) and aw:GetClass() ~= meleeWep then
			bot:SelectWeapon(meleeWep)
		end
		local aimPos = self:GetTargetAimPos(target, true)
		local eyePos = bot:EyePos()
		local aDx = aimPos.x - eyePos.x
		local aDy = aimPos.y - eyePos.y
		local aDz = aimPos.z - eyePos.z
		local aLenSqr = aDx*aDx + aDy*aDy + aDz*aDz
		if aLenSqr > 0.001 then
			local aInvLen = 1.0 / self._mathSqrt(aLenSqr)
			aDx, aDy, aDz = aDx * aInvLen, aDy * aInvLen, aDz * aInvLen
			local aimDir = self._reuseVec
			aimDir.x, aimDir.y, aimDir.z = aDx, aDy, aDz
			local aimAng = aimDir:Angle()
			bot:SetEyeAngles(aimAng)
			cmd:SetViewAngles(aimAng)
			bot._aiAimDir = aimDir
			if self:CanSeeTarget(bot, target) then
				cmd:SetButtons(bit.bor(cmd:GetButtons(), self._bitAttack))
				botData.combat.last_attack_time = now
			end
		end
		self:CombatMovement(bot, cmd, target, dist, true, false, false)
		return true
	end
	local aimPos = botData.combat._cachedAimPosWorld
	if not botData.combat._lastAimCalc or (now - botData.combat._lastAimCalc) > 0.05 then
		aimPos = self:GetTargetAimPos(target, true)
		botData.combat._cachedAimPosWorld = aimPos
		botData.combat._lastAimCalc = now
	end
	local targetVel = target:GetVelocity() or self._zeroVec
	local bulletSpeed = 5000
	local timeToTarget = dist / bulletSpeed
	local predX = aimPos.x + targetVel.x * timeToTarget
	local predY = aimPos.y + targetVel.y * timeToTarget
	local predZ = aimPos.z + targetVel.z * timeToTarget
	local eyePos = bot:EyePos()
	local dirX, dirY, dirZ = predX - eyePos.x, predY - eyePos.y, predZ - eyePos.z
	local lenSqr = dirX*dirX + dirY*dirY + dirZ*dirZ
	if lenSqr < 0.001 then
		self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag, aimPos)
		return true
	end
	local invLen = 1.0 / self._mathSqrt(lenSqr)
	dirX, dirY, dirZ = dirX * invLen, dirY * invLen, dirZ * invLen
	local aimDir = self._reuseVec
	aimDir.x, aimDir.y, aimDir.z = dirX, dirY, dirZ
	local aimAng = aimDir:Angle()
	bot:SetEyeAngles(aimAng)
	cmd:SetViewAngles(aimAng)
	bot._aiAimDir = aimDir
	local canSee = botData.combat._cachedCanSee
	if not botData.combat._lastSeeCheck or (now - botData.combat._lastSeeCheck) > 0.1 or canSee == nil then
		canSee = self:CanSeeTarget(bot, target)
		botData.combat._cachedCanSee = canSee
		botData.combat._lastSeeCheck = now
	end
	local canShoot = canSee
	if isRPG then
		local active = bot:GetActiveWeapon()
		if not self:IsValid(active) or active:GetClass() ~= self._wepRPG then
			bot:SelectWeapon(self._wepRPG)
			return true
		end
		if now - (botData.combat.rpg_last_fire or 0) >= self._cachedRPGCooldown and canShoot then
			cmd:SetButtons(bit.bor(cmd:GetButtons(), self._bitAttack))
			botData.combat.rpg_last_fire = now
			botData.combat.last_attack_time = now
		end
	elseif isFrag then
	elseif canShoot then
		local atkBtns = self._bitAttack
		if now - (botData.combat.alt_fire_timer or 0) > self._cachedAltFireCooldown then
			atkBtns = bit.bor(atkBtns, self._bitAttack2)
			botData.combat.alt_fire_timer = now
		end
		cmd:SetButtons(bit.bor(cmd:GetButtons(), atkBtns))
		botData.combat.last_attack_time = now
	end
	self:CombatMovement(bot, cmd, target, dist, isMelee, isRPG, isFrag, aimPos)
	return true
end
function Combat:HandleAimbotCorrection(ent, data)
	if not self:IsValid(ent) or not self:IsBotSafe(ent) then return end
	if not ent:GetNWBool("IsAICompanion", false) then return end
	local botData = self:GetBotData(ent)
	if not botData or not botData.combat.target then return end
	local target = botData.combat.target
	if not self:IsValidTarget(target) then return end
	local now = CurTime()
	local aimPos = nil
	local targetVel = nil
	if botData.combat._cachedAimPos and botData.combat._cachedAimPos.target == target
	   and (now - botData.combat._cachedAimPos.time) < 0.1 then
		aimPos = botData.combat._cachedAimPos.pos
		targetVel = botData.combat._cachedAimPos.vel
	else
		aimPos = self:GetTargetAimPos(target, true)
		targetVel = target:GetVelocity() or Vector(0, 0, 0)
		botData.combat._cachedAimPos = {
			target = target,
			pos = aimPos,
			vel = targetVel,
			time = now
		}
	end
	local shootPos = ent:GetShootPos()
	local dist = shootPos:Distance(aimPos)
	local bulletSpeed = 5000
	local timeToTarget = math.max(dist / bulletSpeed, 0.01)
	local predX = aimPos.x + targetVel.x * timeToTarget
	local predY = aimPos.y + targetVel.y * timeToTarget
	local predZ = aimPos.z + targetVel.z * timeToTarget
	local rawX, rawY, rawZ = predX - shootPos.x, predY - shootPos.y, predZ - shootPos.z
	local rawLenSqr = rawX*rawX + rawY*rawY + rawZ*rawZ
	if rawLenSqr > 1e-4 then
		local invLen = 1.0 / math.sqrt(rawLenSqr)
		local aimDir = Vector(rawX * invLen, rawY * invLen, rawZ * invLen)
		local aimAng = aimDir:Angle()
		ent:SetEyeAngles(aimAng)
		ent._aiAimDir = aimDir
		data.Dir = aimDir
		data.Spread = Vector(0, 0, 0)
		local checkTrace = nil
		if botData.combat._cachedTrace and botData.combat._cachedTrace.target == target
		   and botData.combat._cachedTrace.shootPos == shootPos
		   and (now - botData.combat._cachedTrace.time) < 0.1 then
			checkTrace = botData.combat._cachedTrace.result
		else
			checkTrace = util.TraceLine({
				start = shootPos,
				endpos = Vector(predX, predY, predZ),
				filter = ent,
				mask = MASK_SHOT
			})
			botData.combat._cachedTrace = {
				target = target,
				shootPos = shootPos,
				result = checkTrace,
				time = now
			}
		end
		if checkTrace.Hit and checkTrace.Entity and checkTrace.Entity ~= target then
			if checkTrace.Entity:IsWorld() then
				local newAimPos = Vector(predX, predY, predZ + 15)
				local newRawX = newAimPos.x - shootPos.x
				local newRawY = newAimPos.y - shootPos.y
				local newRawZ = newAimPos.z - shootPos.z
				local newLen = math.sqrt(newRawX*newRawX + newRawY*newRawY + newRawZ*newRawZ)
				if newLen > 0.001 then
					local newDir = Vector(newRawX/newLen, newRawY/newLen, newRawZ/newLen)
					data.Dir = newDir
					ent:SetEyeAngles(newDir:Angle())
				end
			end
		end
	end
	return true
end
function Combat:UpdateEnemyCache()
	local enemyCacheInterval = self._combatConfig.EnemyCacheInterval or 3.0
	if CurTime() - self._enemyCacheTime < enemyCacheInterval then return end
	self._enemyCacheTime = CurTime()
	self._enemyCache = {}
	local npcs = ents.FindByClass("npc_*")
	local allBots = self:GetAllBots()
	for _, ent in ipairs(npcs) do
		if self:IsValid(ent) and ent:Alive() and self:IsValidTarget(ent) then
			local class = self:SafeGetClass(ent)
			if not self._friendlyNPCs[class] then
				table.insert(self._enemyCache, ent)
			end
		end
	end
	for _, ply in player.Iterator() do
		if self:IsValid(ply) and ply:Alive() and not ply:IsBot() and self:IsValidTarget(ply) then
			local isOwner = false
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
	local scanInterval = self._combatConfig.ThreatScanInterval or 3.0
	local selfRef = self
	self._scanTimer = timer.Create("gmod.one/ai-companion/aggressive-scan", scanInterval, 0, function()
		selfRef:UpdateEnemyCache()
		selfRef:UpdateGrenadeCacheGlobal()
		local allBots = selfRef:GetAllBots()
		for _, bot in ipairs(allBots) do
			if not selfRef:IsValid(bot) or not bot:Alive() then continue end
			if selfRef:IsPassenger(bot) then continue end
			local botData = selfRef:GetBotData(bot)
			if not botData then continue end
			if botData.state == "stopped" then continue end
			if not selfRef:IsAggressiveMode(bot) then continue end
			local currentTarget = botData.combat.target
			if currentTarget
				and selfRef:IsValidTarget(currentTarget)
				and selfRef:SafeAlive(currentTarget)
			then
				continue
			end
			if botData.combat.target then
				selfRef:AdvanceToNextTarget(bot)
			end
			local botState = selfRef:GetBotState(bot)
			local states = selfRef:GetStates()
			if botState == states.POINTING then continue end
			local botPos = selfRef:SafeGetPos(bot)
			local scanRadius = selfRef._combatConfig.ThreatScanRadius or 1500
			local nearestEnemy, nearestDist = nil, scanRadius
			for _, ent in ipairs(selfRef._enemyCache) do
				if not selfRef:IsValid(ent) then continue end
				if ent == bot then continue end
				if not selfRef:IsValidTarget(ent) then continue end
				local dist = botPos:Distance(selfRef:SafeGetPos(ent))
				if dist < nearestDist then
					nearestDist = dist
					nearestEnemy = ent
				end
			end
			if selfRef:IsValid(nearestEnemy) then
				selfRef:RequestTarget(bot, nearestEnemy, "aggressive", false)
				selfRef:ForceCombatWeapon(bot)
				if selfRef:IsValid(bot) then
					local now = CurTime()
					if not bot._lastAggressiveChat or (now - bot._lastAggressiveChat) > 3.0 then
						local enemyClass = selfRef:SafeGetClass(nearestEnemy)
						local msg = selfRef.utils:GetLocalized("bot_aggressive_attack", enemyClass)
						bot:ChatPrint(msg)
						bot._lastAggressiveChat = now
					end
				end
			end
		end
	end)
end
function Combat:ForceCombatWeapon(bot)
	if not self:IsValid(bot) or not bot:Alive() then return end
	local botData = self:GetBotData(bot)
	local target = botData and botData.combat and botData.combat.target
	if self:IsValid(target) then
		if self:IsArmoredTarget(target) then
			if not bot:HasWeapon("weapon_rpg") then
				self:SafeGiveWeapon(bot, "weapon_rpg")
			end
			if bot:HasWeapon("weapon_rpg") then
				bot:SelectWeapon("weapon_rpg")
				if botData and botData.combat then
					botData.combat._weaponCache = nil
				end
				return
			end
		else
			local dist = self:SafeGetPos(bot):Distance(self:SafeGetPos(target))
			local meleeDist = self._combatConfig.MeleeDist or 400
			if dist <= meleeDist then
				self:ForceMeleeWeapon(bot)
				return
			end
		end
	end
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
					if maxClip > 0 then
						wep:SetClip1(maxClip)
					end
				end
			end
		end)
	end
	bot:SelectWeapon(combatWep)
	if botData and botData.combat then
		botData.combat._weaponCache = nil
	end
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
	local botData = self:GetBotData(bot)
	if botData and botData.combat then
		botData.combat._weaponCache = nil
	end
end
function Combat:CleanupCombatState(bot, soft)
	if not self:IsValid(bot) then return end
	local botData = self:GetBotData(bot)
	if not botData then return end
	local owner = self:GetBotOwner(bot)
	botData._cachedOwner = owner
	if self.utils then
		local queueSize = 0
		if botData.combat and botData.combat.target_queue then
			queueSize = #botData.combat.target_queue
		end
		self.utils.LogDebug("Combat",
			bot:Nick() .. " CleanupCombatState soft=" .. tostring(soft)
				.. ", очередь: " .. queueSize)
	end
	self:InitTargetQueue(botData)
	local nextTarget, reason = self:GetNextTargetFromQueue(bot)
	if nextTarget and self:IsValid(nextTarget) and self:SafeAlive(nextTarget) then
		botData.combat.target = nextTarget
		botData.combat.target_type = self:IsPlayerSafe(nextTarget) and "player" or "npc"
		botData.combat.triggered_by = reason or "queue"
		botData.combat.last_attack_time = CurTime()
		botData.combat.last_combat_end = nil
		local states = self:GetStates()
		self:SetBotState(bot, states.COMBAT)
		self:ForceCombatWeapon(bot)
		if self:IsValid(bot) then
			local now = CurTime()
			if not bot._lastNextTargetChat or (now - bot._lastNextTargetChat) > 2.0 then
				local name = self:IsPlayerSafe(nextTarget) and nextTarget:Nick() or self:SafeGetClass(nextTarget)
				bot:ChatPrint(self.utils:GetLocalized("bot_next_target", name))
				bot._lastNextTargetChat = now
			end
		end
		return
	end
	if botData.combat then
		botData.combat.target = nil
		botData.combat.target_type = nil
		botData.combat.triggered_by = nil
		botData.combat.last_combat_end = CurTime()
		botData.combat.medic_post_combat_cooldown = CurTime() + (self._combatConfig.MedicPostCombatCooldown or 3.0)
		if not soft then
			botData.combat.target_queue = {}
		end
	end
	local states = self:GetStates()
	if bot:InVehicle() then
		self:SetBotState(bot, states.VEHICLE)
	else
		self:SetBotState(bot, states.FOLLOW)
		self:ComeBackToPlayer(bot)
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
function Combat:SetupHooks()
	if not SERVER then return end
	local selfRef = self
	hook.Add("StartCommand", "gmod.one/ai-companion/start-command", function(bot, cmd)
		local IsValid = IsValid
		local CurTime = CurTime
		local bit_band = bit.band
		local bit_bor = bit.bor
		local bit_bnot = bit.bnot
		if not IsValid(bot) or not bot:IsPlayer() then return end
		if not bot:IsBot() then return end
		if not bot:GetNWBool("IsAICompanion", false) then return end
		if not bot:Alive() then return end
		local botData = selfRef:GetBotData(bot)
		if not botData then return end
		local hasTarget = botData.combat and botData.combat.target
						  and selfRef:IsValidTarget(botData.combat.target)
						  and selfRef:SafeAlive(botData.combat.target)
		if hasTarget then
			if bot:GetNWBool("pacifist_mode", false) then
				selfRef:ClearTargetQueue(bot)
				return
			end
			selfRef:HandleCombat(bot, cmd, nil)
		else
			local state = selfRef:GetBotState(bot)
			local states = selfRef:GetStates()
			if state == states.COMBAT or state == states.PROTECT or state == states.PROTECT_VEHICLE or state == states.COVER then
				if botData.combat and botData.combat.target_queue and #botData.combat.target_queue > 0 then
					selfRef:AdvanceToNextTarget(bot)
				else
					selfRef:CleanupCombatState(bot, false)
				end
				return
			end
			if botData.combat and botData.combat.target_queue and #botData.combat.target_queue > 0 then
				selfRef:AdvanceToNextTarget(bot)
				return
			end
			selfRef:HandleMedicMode(bot, cmd)
		end
	end)
	hook.Add("EntityFireBullets", "gmod.one/ai-companion/correct-bullet-aim", function(ent, data)
		return selfRef:HandleAimbotCorrection(ent, data)
	end)
	hook.Add("EntityTakeDamage", "gmod.one/ai-companion/assist-on-damage", function(victim, dmg)
		if selfRef.state and selfRef.state:getState("Disabled") then return end
		local attacker = dmg:GetAttacker()
		if not IsValid(attacker) or attacker == victim or attacker:IsWorld() then return end
		local now = CurTime()
		local function SafeChatPrint(ent, msg)
			if not IsValid(ent) or not ent:IsPlayer() then return end
			if not ent._lastCombatChat or (now - ent._lastCombatChat) > 1.5 then
				ent:ChatPrint(msg)
				ent._lastCombatChat = now
			end
		end
		local botsToNotify = {}
		local bm = selfRef.botmanager
		local notifySet = {}
		local function AddBot(b)
			if not IsValid(b) then return end
			local idx = b:EntIndex()
			if not notifySet[idx] then
				notifySet[idx] = true
				table.insert(botsToNotify, b)
			end
		end
		local vehicleRoot = nil
		if selfRef._cachedProtectVehicles and selfRef:IsProtectedVehicle(victim) then
			vehicleRoot = selfRef:GetVehicleRoot(victim)
			local driver = selfRef:GetVehicleDriver(vehicleRoot)
			if IsValid(driver) then
				if driver:IsPlayer() and not driver:IsBot() then
					local dSID = driver:SteamID64()
					if bm and bm.ownerIndex and bm.ownerIndex[dSID] then
						for _, uuid in ipairs(bm.ownerIndex[dSID]) do
							local entry = bm.bots and bm.bots[uuid]
							if entry and IsValid(entry.bot) then
								AddBot(entry.bot)
							end
						end
					end
				elseif driver:IsPlayer() and driver:IsBot() and driver:GetNWBool("IsAICompanion", false) then
					AddBot(driver)
				end
			end
			for _, bot in ipairs(selfRef:GetAllBots()) do
				if selfRef:IsBotVehicle(bot, vehicleRoot) then
					AddBot(bot)
				end
			end
		end
		if victim:IsPlayer() and not victim:IsBot() then
			local victimSID = victim:SteamID64()
			if bm and bm.ownerIndex and bm.ownerIndex[victimSID] then
				for _, uuid in ipairs(bm.ownerIndex[victimSID]) do
					local entry = bm.bots and bm.bots[uuid]
					if entry and IsValid(entry.bot) then
						table.insert(botsToNotify, entry.bot)
					end
				end
			end
		end
		if attacker:IsPlayer() and not attacker:IsBot() then
			local attackerSID = attacker:SteamID64()
			if bm and bm.ownerIndex and bm.ownerIndex[attackerSID] then
				for _, uuid in ipairs(bm.ownerIndex[attackerSID]) do
					local entry = bm.bots and bm.bots[uuid]
					if entry and IsValid(entry.bot) and selfRef:IsDefenderMode(entry.bot) then
						table.insert(botsToNotify, entry.bot)
					end
				end
			end
		end
		if victim:IsPlayer() and victim:IsBot() and victim:GetNWBool("IsAICompanion", false) then
			table.insert(botsToNotify, victim)
		end
		for _, bot in ipairs(botsToNotify) do
			if not IsValid(bot) then continue end
			local botDataEarly = selfRef:GetBotData(bot)
			if botDataEarly and botDataEarly.state == "stopped" then
				continue
			end
			if bot:InVehicle() then
				local veh = bot:GetVehicle()
				if veh and veh.GetDriver and veh:GetDriver() ~= bot then continue end
			end
			if bot:GetNWBool("pacifist_mode", false) then continue end
			local botData = selfRef:GetBotData(bot)
			if not botData then continue end
			botData.combat.last_damage_time = now
			local owner = botData._cachedOwner
			if not owner or not IsValid(owner) then
				owner = selfRef:GetBotOwner(bot)
				botData._cachedOwner = owner
			end
			-- Защита транспорта владельца / транспорта бота
			if vehicleRoot and selfRef:IsValid(vehicleRoot) and attacker ~= bot then
				local protect = false
				local driver = selfRef:GetVehicleDriver(vehicleRoot)
				if driver == bot then
					protect = true
				end
				if selfRef:IsValid(owner) and driver == owner then
					protect = true
				end
				if selfRef:IsBotVehicle(bot, vehicleRoot) then
					protect = true
				end
				if selfRef:IsValid(owner) and owner:InVehicle() then
					local ownerVeh = owner:GetVehicle()
					if selfRef:IsValid(ownerVeh) then
						local ownerRoot = selfRef:GetVehicleRoot(ownerVeh)
						if ownerRoot == vehicleRoot then
							protect = true
						end
					end
				end
				if protect then
					local realAttacker = selfRef:GetDamageAttackerEntity(attacker)
					if selfRef:IsValid(realAttacker) and realAttacker ~= bot then
						if dmg:GetDamage() >= 1 then
							botData.combat.last_damage_time = now
							if realAttacker == owner then
								if selfRef._cachedRetaliateOwnerVehicleDamage then
									selfRef:RequestTarget(bot, realAttacker, "protect_vehicle", true)
									SafeChatPrint(
										bot,
										selfRef.utils:GetLocalized("bot_protecting_vehicle",
											selfRef:IsPlayerSafe(realAttacker) and realAttacker:Nick()
											or selfRef:SafeGetClass(realAttacker)
										)
									)
								end
							else
								selfRef:RequestTarget(bot, realAttacker, "protect_vehicle", false)
								if selfRef:IsValid(owner) then
									SafeChatPrint(
										owner,
										selfRef.utils:GetLocalized("bot_protecting_vehicle",
											selfRef:IsPlayerSafe(realAttacker) and realAttacker:Nick()
											or selfRef:SafeGetClass(realAttacker)
										)
									)
								end
							end
							continue
						end
					end
				end
			end
			if IsValid(owner) and attacker == owner and victim == bot then
				local combat = botData.combat
				if combat
					and combat.triggered_by == "command_llm"
					and combat.target == owner
				then
					continue
				end
				if attacker == bot then continue end
				selfRef:RequestTarget(bot, attacker, "owner_attack", true)
				SafeChatPrint(bot, selfRef.utils:GetLocalized("bot_defending_from_owner"))
				continue
			end
			if victim == bot then
				local combat = botData.combat
				if combat
					and combat.triggered_by == "command_llm"
					and selfRef:IsValid(combat.target)
				then
					continue
				end
				if botData.combat and botData.combat.target == attacker then
					continue
				end
				if attacker == bot then continue end
				selfRef:RequestTarget(bot, attacker, "damage", false)
				local name = selfRef:IsPlayerSafe(attacker) and attacker:Nick() or selfRef:SafeGetClass(attacker)
				SafeChatPrint(bot, selfRef.utils:GetLocalized("bot_defending", name))
				continue
			end
			if IsValid(owner) and attacker == owner and victim ~= bot then
				if not selfRef:IsDefenderMode(bot) then continue end
				if not selfRef:IsValidTarget(victim) then continue end
				if attacker == victim then continue end
				local isTargetValid = victim:IsNPC() or victim:IsNextBot() or selfRef:IsPlayerSafe(victim)
				if isTargetValid then
					if botData.combat.target == victim then continue end
					selfRef:RequestTarget(bot, victim, "assist", false)
					local name = selfRef:IsPlayerSafe(victim) and victim:Nick() or victim:GetClass()
					SafeChatPrint(owner, selfRef.utils:GetLocalized("bot_assist_attack", name))
				end
				continue
			end
			if victim == owner then
				if not selfRef:IsDefenderMode(bot) then continue end
				if not selfRef:IsValidTarget(attacker) then continue end
				if botData.combat.target == attacker then continue end
				if attacker == victim then continue end
				if attacker == bot then continue end
				selfRef:RequestTarget(bot, attacker, "protect", false)
				local name = selfRef:IsPlayerSafe(attacker) and attacker:Nick() or selfRef:SafeGetClass(attacker)
				SafeChatPrint(owner, selfRef.utils:GetLocalized("bot_protecting", name))
				continue
			end

		end
	end)
	hook.Add("PlayerDeath", "gmod.one/ai-companion/forget-grudge", function(victim)
		if not selfRef:IsValid(victim) then return end
		local allBots = selfRef:GetAllBots()
		for _, bot in ipairs(allBots) do
			local botData = selfRef:GetBotData(bot)
			if botData and botData.combat then
				selfRef:RemoveFromTargetQueue(bot, victim)
				if botData.combat.target == victim then
					botData.combat.last_combat_end = CurTime()
					selfRef:AdvanceToNextTarget(bot)
				end
			end
		end
	end)
	hook.Add("OnNPCKilled", "gmod.one/ai-companion/forget-grudge", function(npc, attacker, inflictor)
		if not selfRef:IsValid(npc) then return end
		local allBots = selfRef:GetAllBots()
		for _, bot in ipairs(allBots) do
			local botData = selfRef:GetBotData(bot)
			if botData and botData.combat then
				selfRef:RemoveFromTargetQueue(bot, npc)
				if botData.combat.target == npc then
					botData.combat.last_combat_end = CurTime()
					selfRef:AdvanceToNextTarget(bot)
				end
			end
		end
	end)
	hook.Add("EntityRemoved", "gmod.one/ai-companion/clear-target", function(ent)
		if not selfRef:IsValid(ent) then return end
		local allBots = selfRef:GetAllBots()
		for _, bot in ipairs(allBots) do
			local botData = selfRef:GetBotData(bot)
			if botData and botData.combat then
				selfRef:RemoveFromTargetQueue(bot, ent)
				if botData.combat.target == ent then
					botData.combat.last_combat_end = CurTime()
					selfRef:AdvanceToNextTarget(bot)
				end
			end
		end
	end)
	hook.Add("PlayerDisconnected", "gmod.one/ai-companion/clear-lost-target", function(ply)
		if not selfRef:IsValid(ply) then return end
		local allBots = selfRef:GetAllBots()
		for _, bot in ipairs(allBots) do
			local botData = selfRef:GetBotData(bot)
			if botData and botData.combat then
				selfRef:RemoveFromTargetQueue(bot, ply)
				if botData.combat.target == ply then
					botData.combat.last_combat_end = CurTime()
					selfRef:AdvanceToNextTarget(bot)
				end
			end
		end
	end)
	hook.Add("PlayerSpawn", "gmod.one/ai-companion/refollow-owner", function(ply)
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
							bot:ChatPrint(self.utils:GetLocalized("bot_welcome_back"))
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
		GetTargetAimPos = function(target) return self:GetTargetAimPos(target, true) end,
		CanSeeTarget = function(bot, target) return self:CanSeeTarget(bot, target) end,
		IsValidTarget = function(ent) return self:IsValidTarget(ent) end,
		IsHostileByDefault = function(ent, bot) return self:IsHostileByDefault(ent, bot) end,
		CleanupCombatState = function(bot, soft) return self:CleanupCombatState(bot, soft) end,
		RequestTarget = function(bot, ent, reason, force) return self:RequestTarget(bot, ent, reason, force) end,
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
		AddToTargetQueue = function(bot, ent, reason) return self:AddToTargetQueue(bot, ent, reason) end,
		RemoveFromTargetQueue = function(bot, ent) return self:RemoveFromTargetQueue(bot, ent) end,
		ClearTargetQueue = function(bot) return self:ClearTargetQueue(bot) end,
		GetNextTargetFromQueue = function(bot) return self:GetNextTargetFromQueue(bot) end,
		AdvanceToNextTarget = function(bot) return self:AdvanceToNextTarget(bot) end,
		ShouldAbortQueue = function(bot) return self:ShouldAbortQueue(bot) end,
	}
end

hook.Add("StartCommand", "gmod.one/ai-companion/override-ai-disabled", function(ply, cmd)
	if ply:GetNWBool("IsAICompanion", false) then
	end
end)

return Combat
