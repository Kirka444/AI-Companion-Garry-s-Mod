
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
	{offset = Vector(7.5, 0, 2.5), distance = 0, eyepos = true}
}
ENT.PossessionBinds = {
	[IN_DUCK] = {{coroutine = false, onkeypressed = function(self) self:SetCrouching(not self:IsCrouching()) end}},
	[IN_ATTACK] = {{coroutine = true, onkeydown = function(self) self:PrimaryFire() end}},
	[IN_ATTACK2] = {{coroutine = true, onkeydown = function(self) self:SecondaryFire() end}},
	[IN_RELOAD] = {{coroutine = true, onkeydown = function(self) self:Reload() end}}
}

if SERVER then
	AddCSLuaFile()

	local function GetMaster()
		local plys = player.GetAll()
		if #plys > 0 then return plys[1] end
		return nil
	end

	local function IsTargetAlive(ent)
		if not IsValid(ent) then return false end
		if ent:IsPlayer() then return ent:Alive() end
		if ent:IsNPC() or ent:IsNextBot() then
			return ent:Alive() and ent:Health() > 0
		end
		return ent:Health() > 0
	end

	local function IsCompanion(ent)
		if not IsValid(ent) then return false end
		return ent:GetClass() == "solo_companion_npc"
	end

	
	
	
	local function IsMasterInWay(bot, enemy, master)
		if not IsValid(master) or not IsValid(enemy) then return false end
		local shootPos = bot:GetShootPos()
		local enemyPos = enemy:WorldSpaceCenter()
		local masterPos = master:WorldSpaceCenter()

		
		local tr = util.TraceLine({
			start = shootPos,
			endpos = enemyPos,
			filter = {bot, enemy}
		})
		if tr.Entity == master then return true end

		
		local dir = (enemyPos - shootPos):GetNormalized()
		local totalDist = shootPos:Distance(enemyPos)
		local toMaster = masterPos - shootPos
		local projection = toMaster:Dot(dir)

		if projection > 0 and projection < totalDist then
			local closestPoint = shootPos + dir * projection
			local distance = closestPoint:Distance(masterPos)
			if distance < 45 then
				return true
			end
		end

		return false
	end

	
	
	
	
	local GRENADE_CLASSES = {
		["npc_grenade_frag"] = true, 
		["proj_drg_grenade"] = true, 
		["rpg_round"] = true,         
		["prop_combine_ball"] = true, 
	}

	local GRENADE_RADIUS = 450 

	function ENT:CheckGrenades()
		local myPos = self:GetPos()
		local nearest = nil
		local nearestDist = math.huge

		
		for _, ent in ipairs(ents.FindInSphere(myPos, GRENADE_RADIUS)) do
			if IsValid(ent) and GRENADE_CLASSES[ent:GetClass()] then
				
				if math.abs(ent:GetPos().z - myPos.z) < 128 then
					local d = myPos:Distance(ent:GetPos())
					if d < nearestDist then
						nearestDist = d
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
			self:ChatPrint("[AI] Граната! Уклоняюсь!")
		end

		
		local awayDir = (myPos - nearest:GetPos()):GetNormalized()
		awayDir.z = 0 
		if awayDir:LengthSqr() < 0.01 then
			
			awayDir = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0):GetNormalized()
		end

		local fleePos = myPos + awayDir * 400

		
		if nearestDist < 60 and self:IsOnGround() and self.loco and self.loco.Jump then
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
				ply:ChatPrint("[AI] Компаньон доступен только в одиночной игре!")
			end
			return false
		end
		for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
			if IsValid(ent) and ent ~= self then
				if IsValid(ply) then
					ply:ChatPrint("[AI] На карте уже есть компаньон!")
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

	
	
	
	local SAVE_DIR = "ai_companion_data" 
	local SAVE_PATH = SAVE_DIR .. "/ai_companion_solo.txt"

	function ENT:SaveSettings()
		if self._isLoadingSettings then return end 
		local data = {
			model = self._customModel,
			combatWeapon = self._combatWeaponClass,
			idleWeapon = self._idleWeaponClass,
			nick = self._customNick,
			healEnabled = self._healEnabled,
			healThreshold = self._healThreshold,
			defenderMode = self._defenderMode,
		}
		if not file.Exists(SAVE_DIR, "DATA") then
			file.CreateDir(SAVE_DIR)
		end
		file.Write(SAVE_PATH, util.TableToJSON(data))
		print("[SoloNPC][SERVER] Настройки сохранены в data/" .. SAVE_PATH)
	end

	function ENT:LoadSettings()
		if not file.Exists(SAVE_PATH, "DATA") then
			print("[SoloNPC][SERVER] Файл сохранения не найден, используем стандартные настройки")
			return false
		end
		local json = file.Read(SAVE_PATH, "DATA")
		if not json or json == "" then return false end
		local data = util.JSONToTable(json)
		if not istable(data) then
			print("[SoloNPC][SERVER] Ошибка чтения файла сохранения!")
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

		self._isLoadingSettings = nil
		print("[SoloNPC][SERVER] Настройки загружены из data/" .. SAVE_PATH)
		return true
	end

	
	
	

	
	function ENT:SetBotModel(model)
		if not isstring(model) then return false end
		if not file.Exists(model, "GAME") then return false end
		
		self:SetModel(model)
		self._customModel = model
		
		self.Models = {model}
		self:SaveSettings()
		return true
	end

	
	function ENT:SetCombatWeapon(class)
		if not isstring(class) then return false end
		
		if not self:HasWeapon(class) then
			self:GiveWeapon(class)
		end
		self._combatWeaponClass = class
		self:SaveSettings()
		return true
	end

	
	function ENT:SetIdleWeapon(class)
		if not isstring(class) then return false end
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
		print("[SoloNPC][SERVER] Ник установлен: " .. name .. " | NWString отправлен на клиент")
		self:SaveSettings()
	end

	function ENT:GetCustomNick()
		return self._customNick or "Компаньон"
	end

	
	function ENT:GetPrintName()
		return self._customNick or self.PrintName
	end

	
	
	
	function ENT:SyncWeaponColor(weapon)
		if not IsValid(weapon) or weapon:GetClass() ~= "weapon_physgun" then return end
		local master = GetMaster()
		if not IsValid(master) then return end
		local col = master:GetPlayerColor()
		if not col or (col.x == 0 and col.y == 0 and col.z == 0) then
			col = Vector(0.007843, 0.972549, 0.298039)
		end
		weapon:SetNWVector("WeaponColor", col)
	end

	
	
	
	function ENT:SwitchToCombat()
		if self._currentWeaponMode == "combat" then return end
		self._currentWeaponMode = "combat"
		
		local wep = self._combatWeaponClass or "weapon_smg1"
		if self:HasWeapon(wep) then
			self:SelectWeapon(wep)
		elseif self:HasWeapon("weapon_smg1") then 
			self:SelectWeapon("weapon_smg1")
		end
	end

	function ENT:SwitchToPeaceful()
		if self._currentWeaponMode == "peaceful" then return end
		self._currentWeaponMode = "peaceful"
		
		local wep = self._idleWeaponClass or "weapon_physgun"
		if self:HasWeapon(wep) then
			self:SelectWeapon(wep)
			
			if wep == "weapon_physgun" then
				local weapon = self:GetWeapon(wep)
				if IsValid(weapon) then self:SyncWeaponColor(weapon) end
			end
		elseif self:HasWeapon("weapon_physgun") then 
			self:SelectWeapon("weapon_physgun")
			local physgun = self:GetWeapon("weapon_physgun")
			if IsValid(physgun) then self:SyncWeaponColor(physgun) end
		end
	end

	function ENT:SwitchToMedic()
		if self._currentWeaponMode == "medic" then return end
		self._currentWeaponMode = "medic"
		if self:HasWeapon("weapon_medkit") then
			self:SelectWeapon("weapon_medkit")
		end
	end

	
	
	
	function ENT:CustomInitialize()
		self._myTarget = nil
		self._lastKnownPos = nil
		self._attackMode = false
		self._defenderMode = true
		self._nextShotTime = 0
		self._currentWeaponMode = "peaceful"
		
		
		self._combatWeaponClass = "weapon_smg1"
		self._idleWeaponClass = "weapon_physgun"
		self._customNick = "Компаньон"
		self._healEnabled = true
		self._healThreshold = 0.6 
		
		
		self._healCooldown = 0
		self._isHealing = false
		self._healTimerActive = false
		self._strafeDir = 1
		self._nextStrafeTime = 0
		
		
		self._evadeGrenade = nil
		
		
		self:LoadSettings()

		self:SetDefaultRelationship(D_NU)
		self:SetSelfModelRelationship(D_LI)

		timer.Simple(0.1, function()
			if not IsValid(self) then return end
			
			
			if not self:HasWeapon("weapon_physgun") then self:GiveWeapon("weapon_physgun") end
			if not self:HasWeapon("weapon_smg1") then self:GiveWeapon("weapon_smg1") end
			if not self:HasWeapon("weapon_medkit") then self:GiveWeapon("weapon_medkit") end
			
			self:SwitchToPeaceful()
		end)

		
		timer.Create("ColorSync_" .. self:EntIndex(), 2, 0, function()
			if not IsValid(self) then return end
			local physgun = self:GetWeapon("weapon_physgun")
			if IsValid(physgun) then
				self:SyncWeaponColor(physgun)
			end
		end)
	end

	
	
	
	function ENT:_BaseThink()
		if IsValid(self._myTarget) and IsTargetAlive(self._myTarget) then
			self:SetEnemy(self._myTarget)
			self:AimAt(self._myTarget)
			self:LookAt(self._myTarget)
		elseif self._lastKnownPos then
			self:AimAt(self._lastKnownPos)
			self:LookAt(self._lastKnownPos)
		else
			local master = GetMaster()
			if IsValid(master) then
				self:AimAt(master:WorldSpaceCenter())
				self:LookAt(master:WorldSpaceCenter())
			end
		end
	end

	
	
	
	function ENT:HandleHealing()
		
		if not self._healEnabled then return false end
		
		if self._isHealing then return true end 
		if CurTime() < self._healCooldown then return false end

		local master = GetMaster()
		if not IsValid(master) then return false end

		local masterHP = master:Health()
		local masterMax = master:GetMaxHealth()
		local myHP = self:Health()
		local myMax = self:GetMaxHealth()

		
		local target = nil
		local isMaster = false

		if masterHP / masterMax < self._healThreshold then
			target = master
			isMaster = true
		elseif myHP / myMax < self._healThreshold then
			target = self
		end

		if not IsValid(target) then return false end

		local dist = self:GetPos():Distance(target:GetPos())

		
		if dist > 100 then
			self:SwitchToPeaceful() 
			self:FaceTowards(target)
			local pathRes = self:FollowPath(target, 80)
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
			if not anim then anim = ACT_HL2MP_GESTURE_RELOAD end
			
			self:PlayAnimation(anim)

			
			timer.Simple(1.0, function()
				if not IsValid(self) or not self._isHealing then return end
				
				local hpToHeal = 25
				if isMaster then
					if master:Health() < master:GetMaxHealth() then
						master:SetHealth(math.min(master:Health() + hpToHeal, master:GetMaxHealth()))
						self:ChatPrint("[AI] Лечу вас! (+25 HP)")
					end
				else
					if self:Health() < self:GetMaxHealth() then
						self:SetHealth(math.min(self:Health() + hpToHeal, self:GetMaxHealth()))
						self:ChatPrint("[AI] Лечу себя... (+25 HP)")
					end
				end
				
				self._isHealing = false
				self._healCooldown = CurTime() + 1.0 
				self._healTimerActive = false
			end)
		end
		
		return true
	end

	
	
	
	function ENT:CustomThink()
		if not IsValid(self) or not self:Alive() then return end

		
		if IsValid(self._myTarget) then
			if not IsTargetAlive(self._myTarget) then
				self._myTarget = nil
				self._attackMode = false
				self._lastKnownPos = nil
				return
			end
			self._lastKnownPos = self._myTarget:GetPos()
		end

		
		if not IsValid(self._myTarget) then
			local master = GetMaster()
			if self._defenderMode and IsValid(master) and IsValid(master._lastAttacker) then
				if IsTargetAlive(master._lastAttacker) and not IsCompanion(master._lastAttacker) then
					self._myTarget = master._lastAttacker
					self._attackMode = true
				end
			end
		end

		
		if not IsValid(self._myTarget) then
			local master = GetMaster()
			if self._defenderMode and IsValid(master) and IsValid(master._lastPlayerTarget) then
				local target = master._lastPlayerTarget
				if IsTargetAlive(target) and not IsCompanion(target) and target ~= master then
					self._myTarget = target
					self._attackMode = true
				else
					master._lastPlayerTarget = nil
				end
			end
		end

		
		if self:CheckGrenades() then return end 

		
		if IsValid(self._myTarget) and self._attackMode then
			self:SwitchToCombat()

			local enemy = self._myTarget
			local dist = self:GetPos():Distance(enemy:GetPos())
			local visible = self:Visible(enemy)

			self:AimAt(enemy)
			self:FaceTowards(enemy)

			
			if dist > 600 then
				local pathRes = self:FollowPath(enemy, 100)
				if pathRes == "unreachable" then
					self:Approach(enemy:GetPos(), 1)
				end
				self.loco:SetDesiredSpeed(self.RunSpeed)
			else
				
				if CurTime() >= (self._nextStrafeTime or 0) then
					self._strafeDir = (self._strafeDir or 1) * -1
					self._nextStrafeTime = CurTime() + math.Rand(1.5, 3.0)
				end

				local toEnemy = (enemy:GetPos() - self:GetPos()):GetNormalized()
				local strafeVec = toEnemy:Cross(Vector(0, 0, 1)):GetNormalized() * (self._strafeDir or 1)
				local strafePos = enemy:GetPos() + strafeVec * 200

				local pathRes = self:FollowPath(strafePos, 50)
				if pathRes == "unreachable" then
					self:Approach(strafePos, 1)
				end
				self.loco:SetDesiredSpeed(self.RunSpeed)
			end

			
			if visible and CurTime() >= self._nextShotTime then
				if not IsMasterInWay(self, enemy, GetMaster()) then
					local wep = self:GetActiveWeapon()
					if IsValid(wep) then
						wep:SetClip1(wep:GetMaxClip1())
					end
					self:PrimaryFire()
				end
				self._nextShotTime = CurTime() + 0.1
			end

			return 

		
		elseif self:HandleHealing() then
			return 
		end

		
		self:SwitchToPeaceful()

		if self._attackMode and not IsValid(self._myTarget) then
			self._attackMode = false
			self._lastKnownPos = nil
		end

		local master = GetMaster()
		if IsValid(master) then
			local dist = self:GetPos():Distance(master:GetPos())
			if dist > 100 then
				self:FaceTowards(master)
				local pathRes = self:FollowPath(master, 80)
				if pathRes == "unreachable" then
					self:Approach(master:GetPos(), 1)
				end
				self.loco:SetDesiredSpeed(self.WalkSpeed)
			else
				self.loco:SetDesiredSpeed(0)
			end
		end
	end

	
	
	
	function ENT:OnTakeDamage(dmg)
		local attacker = dmg:GetAttacker()
		local master = GetMaster()

		if not IsValid(attacker) then return end
		if attacker == self then return end
		if attacker == master then return end
		if IsCompanion(attacker) then return end

		self._myTarget = attacker
		self._attackMode = true
		self:ChatPrint("[AI] Атакую обидчика!")
	end

	
	
	
	hook.Add("EntityTakeDamage", "SoloCompanion_DefendPlayer", function(target, dmg)
		local master = GetMaster()
		if not IsValid(master) then return end

		local attacker = dmg:GetAttacker()

		
		if target == master then
			if IsValid(attacker) and (attacker:IsNPC() or attacker:IsNextBot()) then
				if IsCompanion(attacker) then return end

				master._lastAttacker = attacker
				for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
					if IsValid(ent) and ent._defenderMode then
						ent._myTarget = attacker
						ent._attackMode = true
					end
				end
			end
		end

		
		if IsValid(attacker) and attacker:IsPlayer() and attacker == master then
			if IsValid(target) and (target:IsNPC() or target:IsNextBot()) then
				if IsCompanion(target) then return end
				if target == master then return end

				master._lastPlayerTarget = target
				for _, ent in ipairs(ents.FindByClass("solo_companion_npc")) do
					if IsValid(ent) and ent._defenderMode then
						ent._myTarget = target
						ent._attackMode = true
					end
				end
			end
		end
	end)
	
	
	
	hook.Add("EntityTakeDamage", "SoloNPC_FixKillFeedName", function(target, dmginfo)
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
		if IsValid(master) then master:ChatPrint(msg) end
	end

	function ENT:OnRemove()
		timer.Remove("ColorSync_" .. self:EntIndex())
	end
end

AddCSLuaFile()
DrGBase.AddNextbot(ENT)