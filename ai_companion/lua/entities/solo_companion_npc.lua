if game.IsDedicated() then
	return
end

if game.MaxPlayers() > 1 then
	return
end

ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"
ENT.IsDrGBaseHuman = true

ENT.PrintName = "Solo Companion NPC"
ENT.Category = "DrGBase"
ENT.Models = {"models/player/urban.mdl"}

ENT.Factions = {FACTION_PLAYERS}

ENT.BehaviourType = AI_BEHAV_CUSTOM
ENT.RangeAttackRange = 2000
ENT.MeleeAttackRange = 0
ENT.ReachEnemyRange = 1000
ENT.AvoidEnemyRange = 750

ENT.RunSpeed = 300
ENT.WalkSpeed = 300
ENT.CrouchSpeed = 100

DrGBase.IncludeFile("animations.lua")
DrGBase.IncludeFile("movements.lua")
DrGBase.IncludeFile("vehicles.lua")
DrGBase.IncludeFile("modes.lua")

ENT.ClimbLadders = false
ENT.ClimbLaddersUp = false
ENT.ClimbSpeed = 60

ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(5, 0, 2.5)

ENT.UseWeapons = true
ENT.Weapons = {"weapon_smg1", "weapon_physgun", "weapon_medkit"}
ENT.DropWeaponOnDeath = false
ENT.AcceptPlayerWeapons = false
ENT.WeaponAccuracy = 0.85

ENT.PossessionEnabled = true
ENT.PossessionPrompt = true
ENT.PossessionCrosshair = true
ENT.PossessionMovement = POSSESSION_MOVE_ANALOG
ENT.PossessionViews = {
	{offset = Vector(0, 30, 20), distance = 100},
	{offset = Vector(7.5, 0, 2.5), distance = 0, eyepos = true},
}
ENT.PossessionBinds = {
	[IN_DUCK] = {
		{
			coroutine = false,
			onkeypressed = function(self)
				self:SetCrouching(not self:IsCrouching())
			end,
		},
	},
	[IN_ATTACK] = {
		{
			coroutine = true,
			onkeydown = function(self)
				self:PrimaryFire()
			end,
		},
	},
	[IN_ATTACK2] = {
		{
			coroutine = true,
			onkeydown = function(self)
				self:SecondaryFire()
			end,
		},
	},
	[IN_RELOAD] = {
		{
			coroutine = true,
			onkeydown = function(self)
				self:Reload()
			end,
		},
	},
}

if SERVER then
	AddCSLuaFile()

	local GRENADE_CLASSES = {
		["npc_grenade_frag"] = true,
		["proj_drg_grenade"] = true,
		["rpg_round"] = true,
		["prop_combine_ball"] = true,
	}

	local GRENADE_RADIUS = 450
	local GRENADE_HEIGHT_TOLERANCE = 128
	local GRENADE_JUMP_DISTANCE = 60
	local GRENADE_FLEE_DISTANCE = 400

	local HEAL_DISTANCE = 100
	local HEAL_HP_AMOUNT = 25
	local HEAL_ANIM_TIME = 1.0
	local HEAL_COOLDOWN = 1.0

	local MASTER_BLOCK_DISTANCE = 45

	local SAVE_DIR = "ai_companion_data"
	local SAVE_PATH = SAVE_DIR .. "/ai_companion_solo.txt"

	local DEFAULT_PHYSGUN_COLOR = Vector(0.007843, 0.972549, 0.298039)

	local WEAPON_MODE_COMBAT = "combat"
	local WEAPON_MODE_PEACEFUL = "peaceful"
	local WEAPON_MODE_MEDIC = "medic"

	local COLOR_SYNC_INTERVAL = 2
	local AGGRO_SCAN_INTERVAL = 2

	local function GetMaster()
		local plys = player.GetAll()

		if #plys > 0 then
			return plys[1]
		end

		return nil
	end

	local function IsCompanion(ent)
		if not IsValid(ent) then
			return false
		end

		return ent:GetClass() == "solo_companion_npc"
	end

	function ENT:CheckGrenades()
		local myPos = self:GetPos()
		local nearest = nil
		local nearestDist = math.huge

		for _, ent in ipairs(ents.FindInSphere(myPos, GRENADE_RADIUS)) do
			if IsValid(ent) and GRENADE_CLASSES[ent:GetClass()] then
				if math.abs(ent:GetPos().z - myPos.z) < GRENADE_HEIGHT_TOLERANCE then
					local dist = myPos:Distance(ent:GetPos())

					if dist < nearestDist then
						nearestDist = dist
						nearest = ent
					end
				end
			end
		end

		if not IsValid(nearest) then
			self._evadeGrenade = nil

			return false
		end

		if self._evadeGrenade ~= nearest then
			self._evadeGrenade = nearest
			self:ChatPrint("[AI] Grenade! Evading!")
		end

		local awayDir = myPos - nearest:GetPos()
		awayDir.z = 0

		if awayDir:LengthSqr() < 0.01 then
			awayDir = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0):GetNormalized()
		end

		local fleePos = myPos + awayDir * GRENADE_FLEE_DISTANCE

		if nearestDist < GRENADE_JUMP_DISTANCE and self:IsOnGround() and self.loco and self.loco.Jump then
			self.loco:Jump()
		end

		local pathRes = self:FollowPath(fleePos, 0)

		if pathRes == "unreachable" then
			self:Approach(fleePos, 1)
		end

		self.loco:SetDesiredSpeed(self.RunSpeed)

		return true
	end

	function ENT:SpawnedBy(ply)
		if not game.SinglePlayer() then
			if IsValid(ply) then
				ply:ChatPrint("[AI] Companion is only available in single-player mode!")
			end

			return false
		end

		for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
			if IsValid(ent) and ent ~= self then
				if IsValid(ply) then
					ply:ChatPrint("[AI] There's already a companion on the map!")
				end

				return false
			end
		end

		return true
	end

	function ENT:GetAnimList()
		return self.Animations.PlayerModel
	end

	function ENT:AIBehaviour()
	end

	function ENT:OnLastEnemy()
	end

	function ENT:SaveSettings()
		if self._isLoadingSettings then
			return
		end

		local data = {
			model = self._customModel,
			combatWeapon = self._combatWeaponClass,
			idleWeapon = self._idleWeaponClass,
			nick = self._customNick,
			healEnabled = self._healEnabled,
			healThreshold = self._healThreshold,
			defenderMode = self._defenderMode,
			stealthMode = self._stealthMode,
			pacifistMode = self._pacifistMode,
			aggressiveMode = self._aggressiveMode,
		}

		if not file.Exists(SAVE_DIR, "DATA") then
			file.CreateDir(SAVE_DIR)
		end

		file.Write(SAVE_PATH, util.TableToJSON(data))
		print("[SoloNPC][SERVER] Settings saved to data/" .. SAVE_PATH)
	end

	function ENT:LoadSettings()
		if not file.Exists(SAVE_PATH, "DATA") then
			print("[SoloNPC][SERVER] Save file not found, using default settings")

			return false
		end

		local json = file.Read(SAVE_PATH, "DATA")

		if not json or json == "" then
			return false
		end

		local data = util.JSONToTable(json)

		if not istable(data) then
			print("[SoloNPC][SERVER] Error reading save file!")

			return false
		end

		self._isLoadingSettings = true

		if isstring(data.model) and data.model ~= "" then
			self:SetBotModel(data.model)
		end

		if isstring(data.combatWeapon) and data.combatWeapon ~= "" then
			self._combatWeaponClass = data.combatWeapon
		end

		if isstring(data.idleWeapon) and data.idleWeapon ~= "" then
			self._idleWeaponClass = data.idleWeapon
		end

		if isstring(self._combatWeaponClass) and not self:HasWeapon(self._combatWeaponClass) then
			self:GiveWeapon(self._combatWeaponClass)
		end

		if isstring(self._idleWeaponClass) and not self:HasWeapon(self._idleWeaponClass) then
			self:GiveWeapon(self._idleWeaponClass)
		end

		if isstring(data.nick) and data.nick ~= "" then
			self:SetCustomNick(data.nick)
		end

		if isbool(data.healEnabled) then
			self._healEnabled = data.healEnabled
		end

		if isnumber(data.healThreshold) then
			self._healThreshold = data.healThreshold
		end

		if isbool(data.defenderMode) then
			self._defenderMode = data.defenderMode
		end

		if isbool(data.stealthMode) then
			self._stealthMode = data.stealthMode
		end

		if isbool(data.pacifistMode) then
			self._pacifistMode = data.pacifistMode
		end

		if isbool(data.aggressiveMode) then
			self._aggressiveMode = data.aggressiveMode
		end

		self._isLoadingSettings = nil
		print("[SoloNPC][SERVER] Settings loaded from data/" .. SAVE_PATH)

		return true
	end

	function ENT:SetBotModel(model)
		if not isstring(model) then
			return false
		end

		if not file.Exists(model, "GAME") then
			return false
		end

		self:SetModel(model)
		self._customModel = model
		self.Models = {model}
		self:SaveSettings()

		return true
	end

	function ENT:SetCombatWeapon(class)
		if not isstring(class) then
			return false
		end

		if not self:HasWeapon(class) then
			self:GiveWeapon(class)
		end

		self._combatWeaponClass = class
		self:SaveSettings()

		return true
	end

	function ENT:SetIdleWeapon(class)
		if not isstring(class) then
			return false
		end

		if not self:HasWeapon(class) then
			self:GiveWeapon(class)
		end

		self._idleWeaponClass = class
		self:SaveSettings()

		return true
	end

	function ENT:SetCustomNick(name)
		self._customNick = name
		self:SetNWString("CustomNick", name)
		print("[SoloNPC][SERVER] Nick set: " .. name .. " | NWString sent to client")
		self:SaveSettings()
	end

	function ENT:GetCustomNick()
		return self._customNick or "Companion"
	end

	function ENT:GetPrintName()
		return self._customNick or self.PrintName
	end

	function ENT:SyncWeaponColor(weapon)
		if not IsValid(weapon) or weapon:GetClass() ~= "weapon_physgun" then
			return
		end

		local master = GetMaster()

		if not IsValid(master) then
			return
		end

		local col = master:GetPlayerColor()

		if not col or (col.x == 0 and col.y == 0 and col.z == 0) then
			col = DEFAULT_PHYSGUN_COLOR
		end

		weapon:SetNWVector("WeaponColor", col)
	end

	hook.Add("PlayerColorChanged", "gmod.one/solo-companion/instant-color-sync", function(ply, oldColor, newColor)
		if not IsValid(ply) then
			return
		end

		local master = GetMaster()

		if ply ~= master then
			return
		end

		for _, npc in ipairs(ents.FindByClass("solo_companion_npc")) do
			if IsValid(npc) then
				local physgun = npc:GetWeapon("weapon_physgun")

				if IsValid(physgun) then
					npc:SyncWeaponColor(physgun)
				end
			end
		end
	end)

	hook.Add("WeaponEquip", "gmod.one/solo-companion/instant-weapon-sync", function(weapon, owner)
		if not IsValid(weapon) or not IsValid(owner) then
			return
		end

		if weapon:GetClass() ~= "weapon_physgun" then
			return
		end

		if owner:GetClass() ~= "solo_companion_npc" then
			return
		end

		timer.Simple(0, function()
			if IsValid(owner) and IsValid(weapon) then
				owner:SyncWeaponColor(weapon)
			end
		end)
	end)

	function ENT:SwitchToCombat()
		if self._currentWeaponMode == WEAPON_MODE_COMBAT then
			return
		end

		self._currentWeaponMode = WEAPON_MODE_COMBAT

		local wep = self._combatWeaponClass or "weapon_smg1"

		if self:HasWeapon(wep) then
			self:SelectWeapon(wep)
		elseif self:HasWeapon("weapon_smg1") then
			self:SelectWeapon("weapon_smg1")
		end
	end

	function ENT:SwitchToPeaceful()
		if self._currentWeaponMode == WEAPON_MODE_PEACEFUL then
			return
		end

		self._currentWeaponMode = WEAPON_MODE_PEACEFUL

		local wep = self._idleWeaponClass or "weapon_physgun"

		if self:HasWeapon(wep) then
			self:SelectWeapon(wep)

			if wep == "weapon_physgun" then
				local weapon = self:GetWeapon(wep)

				if IsValid(weapon) then
					self:SyncWeaponColor(weapon)
				end
			end
		elseif self:HasWeapon("weapon_physgun") then
			self:SelectWeapon("weapon_physgun")

			local physgun = self:GetWeapon("weapon_physgun")

			if IsValid(physgun) then
				self:SyncWeaponColor(physgun)
			end
		end
	end

	function ENT:SwitchToMedic()
		if self._currentWeaponMode == WEAPON_MODE_MEDIC then
			return
		end

		self._currentWeaponMode = WEAPON_MODE_MEDIC

		if self:HasWeapon("weapon_medkit") then
			self:SelectWeapon("weapon_medkit")
		end
	end

	function ENT:IsCrouching()
		return self:GetNWBool("DrGBaseCrouching")
	end

	function ENT:SetCrouching(bool)
		self:SetNWBool("DrGBaseCrouching", bool and true or false)
	end

	function ENT:CustomInitialize()
		self._aiDisabled = false
		self._myTarget = nil
		self._lastKnownPos = nil
		self._attackMode = false
		self._nextShotTime = 0
		self._currentWeaponMode = WEAPON_MODE_PEACEFUL

		self._combatWeaponClass = "weapon_smg1"
		self._idleWeaponClass = "weapon_physgun"
		self._customNick = "Companion"
		self._healEnabled = true
		self._healThreshold = 0.6

		self._healCooldown = 0
		self._isHealing = false
		self._healTimerActive = false
		self._strafeDir = 1
		self._nextStrafeTime = 0

		self._evadeGrenade = nil

		self._stealthMode = false
		self._pacifistMode = false
		self._aggressiveMode = false
		self._defenderMode = true

		self._targetQueue = {}

		self:LoadSettings()

		self:SetDefaultRelationship(D_NU)
		self:SetSelfModelRelationship(D_LI)

		timer.Simple(0.1, function()
			if not IsValid(self) then
				return
			end

			pcall(function()
				if self.GetWeapons then
					for _, w in ipairs(self:GetWeapons()) do
						if IsValid(w) then
							w:Remove()
						end
					end
				end
			end)

			if not self:HasWeapon("weapon_physgun") then
				self:GiveWeapon("weapon_physgun")
			end

			if not self:HasWeapon("weapon_smg1") then
				self:GiveWeapon("weapon_smg1")
			end

			if not self:HasWeapon("weapon_medkit") then
				self:GiveWeapon("weapon_medkit")
			end

			self:SwitchToPeaceful()
		end)

		timer.Create("gmod.one/solo-companion/color-sync-" .. self:EntIndex(), COLOR_SYNC_INTERVAL, 0, function()
			if not IsValid(self) then
				return
			end

			local physgun = self:GetWeapon("weapon_physgun")

			if IsValid(physgun) then
				self:SyncWeaponColor(physgun)
			end
		end)

		timer.Create("gmod.one/solo-companion/aggro-scan-" .. self:EntIndex(), AGGRO_SCAN_INTERVAL, 0, function()
			if not IsValid(self) then
				return
			end

			self:AggressiveScan()
		end)
	end

	function ENT:_BaseThink()
		if self:VehicleIsValid() then
			return
		end

		if self._aiDisabled then
			return
		end

		local master = GetMaster()

		if IsValid(self._myTarget) and self:IsTargetAlive(self._myTarget) then
			self:SetEnemy(self._myTarget)
			self:AimAt(self._myTarget)
			self:LookAt(self._myTarget)
		elseif self._lastKnownPos and self._attackMode then
			self:AimAt(self._lastKnownPos)
			self:LookAt(self._lastKnownPos)
		elseif IsValid(master) then
			self:AimAt(master:WorldSpaceCenter())
			self:LookAt(master:WorldSpaceCenter())
		end
	end

	function ENT:HandleHealing()
		if not self._healEnabled then
			return false
		end

		if self._isHealing then
			return true
		end

		if CurTime() < self._healCooldown then
			return false
		end

		local master = GetMaster()

		if not IsValid(master) then
			return false
		end

		local masterHP = master:Health()
		local masterMax = master:GetMaxHealth()
		local myHP = self:Health()
		local myMax = self:GetMaxHealth()

		local target = nil
		local isMaster = false

		if masterMax > 0 and (masterHP / masterMax) < self._healThreshold then
			target = master
			isMaster = true
		elseif myMax > 0 and (myHP / myMax) < self._healThreshold then
			target = self
		end

		if not IsValid(target) then
			return false
		end

		local dist = self:GetPos():Distance(target:GetPos())

		if dist > HEAL_DISTANCE then
			self:SwitchToPeaceful()
			self:FaceTowards(target)

			local pathRes = self:FollowPath(target:GetPos(), 80)

			if pathRes == "unreachable" then
				self:Approach(target:GetPos(), 1)
			end

			self.loco:SetDesiredSpeed(self.RunSpeed)

			return true
		end

		self:SwitchToMedic()
		self:FaceTowards(target)
		self.loco:SetDesiredSpeed(0)
		self:AimAt(target:WorldSpaceCenter())
		self:LookAt(target:WorldSpaceCenter())

		if not self._healTimerActive then
			self._isHealing = true
			self._healTimerActive = true

			local anim = self:GetShootAnimation()

			if not anim then
				anim = ACT_HL2MP_GESTURE_RELOAD
			end

			self:PlayAnimation(anim)

			timer.Simple(HEAL_ANIM_TIME, function()
				if not IsValid(self) or not self._isHealing then
					return
				end

				if isMaster then
					if master:Health() < master:GetMaxHealth() then
						master:SetHealth(math.min(master:Health() + HEAL_HP_AMOUNT, master:GetMaxHealth()))
						self:ChatPrint("[AI] Healing you! (+" .. HEAL_HP_AMOUNT .. " HP)")
					end
				else
					if self:Health() < self:GetMaxHealth() then
						self:SetHealth(math.min(self:Health() + HEAL_HP_AMOUNT, self:GetMaxHealth()))
						self:ChatPrint("[AI] Healing myself... (+" .. HEAL_HP_AMOUNT .. " HP)")
					end
				end

				self._isHealing = false
				self._healCooldown = CurTime() + HEAL_COOLDOWN
				self._healTimerActive = false
			end)
		end

		return true
	end

	function ENT:IsReachableByHeight(target)
		if not IsValid(target) then
			return false
		end

		local myArea = navmesh.GetNearestNavArea(self:GetPos())
		local targetArea = navmesh.GetNearestNavArea(target:GetPos())

		if not myArea or not targetArea then
			return false
		end

		local myZ = myArea:GetCenter().z
		local targetZ = targetArea:GetCenter().z

		if math.abs(myZ - targetZ) > 200 then
			return false
		end

		return true
	end

	function ENT:IsTargetAlive(ent)
		if not IsValid(ent) then
			return false
		end

		if ent:IsPlayer() then
			return ent:Alive()
		end

		if ent:IsNPC() or ent:IsNextBot() then
			local hp = ent:Health()

			if hp == nil then
				return true
			end

			return hp > 0
		end

		local hp = ent:Health()

		if hp == nil then
			return true
		end

		return hp > 0
	end

	function ENT:IsMasterInWay(enemy)
		local master = GetMaster()

		if not IsValid(master) or not IsValid(enemy) then
			return false
		end

		local shootPos = self:GetShootPos()
		local enemyPos = enemy:WorldSpaceCenter()
		local masterPos = master:WorldSpaceCenter()

		local tr = util.TraceLine({
			start = shootPos,
			endpos = enemyPos,
			filter = {self, enemy},
		})

		if tr.Entity == master then
			return true
		end

		local dir = (enemyPos - shootPos):GetNormalized()
		local totalDist = shootPos:Distance(enemyPos)
		local toMaster = masterPos - shootPos
		local projection = toMaster:Dot(dir)

		if projection > 0 and projection < totalDist then
			local closestPoint = shootPos + dir * projection
			local distance = closestPoint:Distance(masterPos)

			if distance < MASTER_BLOCK_DISTANCE then
				return true
			end
		end

		return false
	end

	function ENT:IdleBehaviour()
		if self:VehicleIsValid() then
			return
		end

		local master = GetMaster()

		if not IsValid(master) then
			return
		end

		local shouldCrouch = false

		if self:IsStealthMode() and IsValid(master) then
			if master:IsPlayer() then
				shouldCrouch = master:Crouching()
			elseif master.IsCrouching then
				shouldCrouch = master:IsCrouching()
			end
		end

		if self.SetCrouching then
			self:SetCrouching(shouldCrouch)
		end

		local dist = self:GetPos():Distance(master:GetPos())
		local targetSpeed = 0

		if dist > HEAL_DISTANCE then
			self:FaceTowards(master)

			local pathRes = self:FollowPath(master:GetPos(), 80)

			if pathRes ~= "unreachable" then
				if shouldCrouch then
					targetSpeed = self.CrouchSpeed
				else
					targetSpeed = self.WalkSpeed
				end
			end
		end

		local currentSpeed = self.loco:GetDesiredSpeed() or 0
		local accel = 200
		local dt = FrameTime()

		if targetSpeed > currentSpeed then
			currentSpeed = math.min(currentSpeed + accel * dt, targetSpeed)
		elseif targetSpeed < currentSpeed then
			currentSpeed = math.max(currentSpeed - accel * dt, targetSpeed)
		end

		self.loco:SetDesiredSpeed(currentSpeed)
	end

	function ENT:CustomThink()
		if not IsValid(self) or not self:Alive() then
			return
		end

		if self._vehRoot and not IsValid(self._vehRoot) then
			self:VehicleExit()
		end

		if not self:VehicleIsValid() then
			if self:GetParent():IsValid() then
				self:SetParent(nil)
			end

			if self:GetMoveType() == MOVETYPE_NONE then
				self:SetMoveType(MOVETYPE_STEP)
				self:SetNotSolid(false)
				self:SetSolid(SOLID_BBOX)
				self:SetCollisionGroup(COLLISION_GROUP_PLAYER)
			end

			if self.loco and self.loco.SetDesiredSpeed then
				local curSpeed = self.loco:GetDesiredSpeed() or 0

				if curSpeed == 0 and not self._aiDisabled then
					self.loco:SetDesiredSpeed(self.WalkSpeed)
				end
			end
		end

		if self:VehicleThink() then
			return
		end

		if self._aiDisabled then
			self.loco:SetDesiredSpeed(0)
			self:SwitchToPeaceful()

			return
		end

		if self:IsPacifistMode() then
			self._myTarget = nil
			self._attackMode = false
			self._lastKnownPos = nil
			self:SwitchToPeaceful()
			self:IdleBehaviour()

			return
		end

		if IsValid(self._myTarget) then
			if not self:IsTargetAlive(self._myTarget) then
				self:AdvanceToNextTarget()

				if not IsValid(self._myTarget) then
					self:IdleBehaviour()

					return
				end
			else
				self._lastKnownPos = self._myTarget:GetPos()
			end
		else
			if self._attackMode then
				self._attackMode = false
				self._lastKnownPos = nil
				self:ClearTargetQueue()
				self:SwitchToPeaceful()
			end
		end

		if not IsValid(self._myTarget) and self:IsDefenderMode() then
			local master = GetMaster()

			if IsValid(master) then
				if IsValid(master._lastAttacker) and self:IsTargetAlive(master._lastAttacker) then
					if not self:IsFriendlyEntity(master._lastAttacker) then
						self:RequestTarget(master._lastAttacker, "protect", false)
					end
				end

				if not IsValid(self._myTarget) and IsValid(master._lastPlayerTarget) then
					local target = master._lastPlayerTarget

					if self:IsTargetAlive(target) and not self:IsFriendlyEntity(target) and target ~= master then
						self:RequestTarget(target, "assist", false)
					else
						master._lastPlayerTarget = nil
					end
				end
			end
		end

		if self:CheckGrenades() then
			return
		end

		if IsValid(self._myTarget) and self._attackMode then
			self:SwitchToCombat()
			self:SetCrouching(false)

			local enemy = self._myTarget
			local dist = self:GetPos():Distance(enemy:GetPos())
			local visible = self:Visible(enemy)

			self:AimAt(enemy)
			self:FaceTowards(enemy)

			self:CombatMovement(enemy, dist)

			if visible and CurTime() >= self._nextShotTime then
				if not self:IsMasterInWay(enemy) then
					local wep = self:GetActiveWeapon()

					if IsValid(wep) then
						wep:SetClip1(wep:GetMaxClip1())
					end

					self:PrimaryFire()
				end

				self._nextShotTime = CurTime() + 0.1
			end

			return
		end

		if self:HandleHealing() then
			return
		end

		self:SwitchToPeaceful()
		self:IdleBehaviour()
	end

	function ENT:OnTakeDamage(dmg)
		local attacker = dmg:GetAttacker()
		local master = GetMaster()

		if not IsValid(attacker) then
			return
		end

		if attacker == self then
			return
		end

		if self._aiDisabled then
			return
		end

		if self:IsPacifistMode() then
			return
		end

		if self:VehicleIsValid() then
			if attacker == self._vehRoot then
				return
			end

			if attacker == self._vehSeat then
				return
			end
		end

		if IsCompanion(attacker) then
			return
		end

		if self:IsFriendlyEntity(attacker) and not attacker:IsPlayer() then
			return
		end

		self:RequestTarget(attacker, "damage", true)

		if not self:VehicleIsValid() then
			self:ChatPrint("[AI] Отвечаю на атаку!")
		end
	end

	hook.Add("EntityTakeDamage", "gmod.one/solo-companion/defend-player", function(target, dmg)
		local master = GetMaster()

		if not IsValid(master) then
			return
		end

		local attacker = dmg:GetAttacker()

		if target == master then
			if IsValid(attacker) and (attacker:IsNPC() or attacker:IsNextBot()) then
				if IsCompanion(attacker) then
					return
				end

				master._lastAttacker = attacker

				for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
					if IsValid(ent) and ent._defenderMode then
						ent:RequestTarget(attacker, "protect", false)
					end
				end
			end
		end

		if IsValid(attacker) and attacker:IsPlayer() and attacker == master then
			if IsValid(target) and (target:IsNPC() or target:IsNextBot()) then
				if IsCompanion(target) then
					return
				end

				if target == master then
					return
				end

				master._lastPlayerTarget = target

				for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
					if IsValid(ent) and ent._defenderMode then
						ent:RequestTarget(target, "assist", false)
					end
				end
			end
		end
	end)

	hook.Add("EntityTakeDamage", "gmod.one/solo-companion/fix-killfeed", function(target, dmginfo)
		local attacker = dmginfo:GetAttacker()

		if IsValid(attacker) and attacker:GetClass() == "solo_companion_npc" then
			local nick = attacker:GetCustomNick()

			if nick and nick ~= "" then
				attacker.PrintName = nick
			end
		end
	end)

	function ENT:ChatPrint(msg)
		local master = GetMaster()

		if IsValid(master) then
			master:ChatPrint(msg)
		end
	end

	function ENT:OnRemove()
		timer.Remove("gmod.one/solo-companion/color-sync-" .. self:EntIndex())
		timer.Remove("gmod.one/solo-companion/aggro-scan-" .. self:EntIndex())
	end
end

AddCSLuaFile()
DrGBase.AddNextbot(ENT)
