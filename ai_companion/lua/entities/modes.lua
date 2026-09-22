-- Combat modes and target queue handling for the solo companion NPC.

if not SERVER then
	return
end

local HEAL_HP_AMOUNT = 25
local HEAL_COOLDOWN = 1.0
local COMBAT_CLOSE_RANGE = 80
local COMBAT_STRAFE_MIN = 100
local COMBAT_STRAFE_MAX = 600
local STRAFE_INTERVAL_MIN = 1.2
local STRAFE_INTERVAL_MAX = 2.5
local AGGRO_SCAN_RADIUS = 1500

local IDEAL_DIST_SHOTGUN = 200
local IDEAL_DIST_RANGED = 500
local IDEAL_DIST_DEFAULT = 300

function ENT:IsStealthMode()
	return self._stealthMode == true
end

function ENT:IsPacifistMode()
	return self._pacifistMode == true
end

function ENT:IsAggressiveMode()
	return self._aggressiveMode == true
end

function ENT:IsDefenderMode()
	return self._defenderMode == true
end

function ENT:IsMedicMode()
	return self._healEnabled == true
end

function ENT:SetStealthMode(bool)
	self._stealthMode = bool and true or false
	self:SaveSettings()
end

function ENT:SetPacifistMode(bool)
	self._pacifistMode = bool and true or false

	if self._pacifistMode then
		self:ClearTargetQueue()
		self._myTarget = nil
		self._attackMode = false
		self._lastKnownPos = nil
		self:SwitchToPeaceful()
	end

	self:SaveSettings()
end

function ENT:SetAggressiveMode(bool)
	self._aggressiveMode = bool and true or false
	self:SaveSettings()
end

function ENT:SetDefenderMode(bool)
	self._defenderMode = bool and true or false
	self:SaveSettings()
end

local PRIORITY_MAP = {
	["command_llm"] = 6,
	["owner_attack"] = 5,
	["protect"] = 4,
	["protect_vehicle"] = 4,
	["damage"] = 3,
	["assist"] = 2,
	["aggressive"] = 1,
	["command"] = 1,
}

function ENT:InitTargetQueue()
	if not istable(self._targetQueue) then
		self._targetQueue = {}
	end
end

function ENT:AddToTargetQueue(ent, reason)
	if not IsValid(ent) or ent == self then
		return false
	end

	if self:IsPacifistMode() then
		return false
	end

	self:InitTargetQueue()

	local newPrio = PRIORITY_MAP[reason] or 1

	for _, entry in ipairs(self._targetQueue) do
		if entry.ent == ent then
			local oldPrio = PRIORITY_MAP[entry.reason] or 1

			if newPrio > oldPrio then
				entry.reason = reason
				entry.added = CurTime()
				self:_SortTargetQueue()
			end

			return true
		end
	end

	table.insert(self._targetQueue, {
		ent = ent,
		reason = reason,
		added = CurTime(),
	})

	self:_SortTargetQueue()

	return true
end

function ENT:_SortTargetQueue()
	table.sort(self._targetQueue, function(a, b)
		local prioA = PRIORITY_MAP[a.reason] or 1
		local prioB = PRIORITY_MAP[b.reason] or 1

		if prioA ~= prioB then
			return prioA > prioB
		end

		return a.added < b.added
	end)
end

function ENT:RemoveFromTargetQueue(ent)
	if not istable(self._targetQueue) then
		return
	end

	for i = #self._targetQueue, 1, -1 do
		if self._targetQueue[i].ent == ent then
			table.remove(self._targetQueue, i)
		end
	end
end

function ENT:ClearTargetQueue()
	self._targetQueue = {}
	self._myTarget = nil
	self._attackMode = false
end

function ENT:GetNextTargetFromQueue()
	self:InitTargetQueue()

	for i = #self._targetQueue, 1, -1 do
		local entry = self._targetQueue[i]

		if not IsValid(entry.ent) or not self:IsTargetAlive(entry.ent) then
			table.remove(self._targetQueue, i)
		end
	end

	for _, entry in ipairs(self._targetQueue) do
		if IsValid(entry.ent) and self:IsTargetAlive(entry.ent) then
			return entry.ent, entry.reason
		end
	end

	return nil, nil
end

function ENT:AdvanceToNextTarget()
	if IsValid(self._myTarget) then
		self:RemoveFromTargetQueue(self._myTarget)
	end

	self._myTarget = nil

	local nextTarget = self:GetNextTargetFromQueue()

	if IsValid(nextTarget) then
		self._myTarget = nextTarget
		self._attackMode = true
		self._lastKnownPos = nextTarget:GetPos()
		self:SwitchToCombat()

		return true
	end

	self._attackMode = false
	self._lastKnownPos = nil
	self:SwitchToPeaceful()

	return false
end

function ENT:RequestTarget(ent, reason, force)
	if not IsValid(ent) or ent == self then
		return false
	end

	if self:IsPacifistMode() then
		return false
	end

	self:InitTargetQueue()

	if force then
		self:ClearTargetQueue()
		self._myTarget = ent
		self._attackMode = true
		self._lastKnownPos = ent:GetPos()
		self:SwitchToCombat()

		return true
	end

	self:AddToTargetQueue(ent, reason)

	if not IsValid(self._myTarget) or not self:IsTargetAlive(self._myTarget) then
		return self:AdvanceToNextTarget()
	end

	return true
end

function ENT:IsFriendlyEntity(ent)
	if not IsValid(ent) then
		return false
	end

	if ent == self then
		return true
	end

	if ent:GetClass() == "solo_companion_npc" then
		return true
	end

	if ent:IsPlayer() then
		return true
	end

	return false
end

function ENT:AggressiveScan()
	if not self:IsAggressiveMode() then
		return
	end

	if self:IsPacifistMode() then
		return
	end

	if self:VehicleIsValid() then
		return
	end

	if self._aiDisabled then
		return
	end

	if self._isHealing then
		return
	end

	if IsValid(self._myTarget) and self:IsTargetAlive(self._myTarget) then
		return
	end

	local myPos = self:GetPos()
	local bestEnemy = nil
	local bestDist = AGGRO_SCAN_RADIUS

	for _, ent in ipairs(ents.FindInSphere(myPos, AGGRO_SCAN_RADIUS)) do
		if IsValid(ent) and ent ~= self and not self:IsFriendlyEntity(ent) then
			local isEnemy = false

			if ent:IsNPC() then
				isEnemy = true
			elseif ent:IsNextBot() and ent:GetClass() ~= "solo_companion_npc" then
				isEnemy = true
			end

			if isEnemy and self:IsTargetAlive(ent) then
				local dist = myPos:Distance(ent:GetPos())

				if dist < bestDist then
					bestDist = dist
					bestEnemy = ent
				end
			end
		end
	end

	if IsValid(bestEnemy) then
		self:RequestTarget(bestEnemy, "aggressive", false)
	end
end

function ENT:GetIdealCombatDistance()
	local wep = self:GetActiveWeapon()

	if IsValid(wep) then
		local class = wep:GetClass()

		if class == "weapon_shotgun" or class == "weapon_357" then
			return IDEAL_DIST_SHOTGUN
		elseif class == "weapon_crossbow" or class == "weapon_rpg" then
			return IDEAL_DIST_RANGED
		end
	end

	return IDEAL_DIST_DEFAULT
end

function ENT:CombatMovement(enemy, dist)
	if not IsValid(enemy) then
		return
	end

	local shootPos = self:GetShootPos()
	local targetPos = self:GetTargetAimPos(enemy)
	local aimAngles = (targetPos - shootPos):Angle()
	self:SetAngles(Angle(0, aimAngles.y, 0))

	local idealDist = self:GetIdealCombatDistance()

	local currentSpeed = self.loco:GetDesiredSpeed() or 0
	local targetSpeed = self.RunSpeed
	local accel = 300
	local dt = FrameTime()

	if targetSpeed > currentSpeed then
		currentSpeed = math.min(currentSpeed + accel * dt, targetSpeed)
	elseif targetSpeed < currentSpeed then
		currentSpeed = math.max(currentSpeed - accel * dt, targetSpeed)
	end

	self.loco:SetDesiredSpeed(currentSpeed)

	if dist < COMBAT_CLOSE_RANGE then
		local awayDir = self:GetPos() - enemy:GetPos()
		awayDir.z = 0

		if awayDir:LengthSqr() < 0.01 then
			awayDir = Vector(1, 0, 0)
		end

		awayDir:Normalize()

		local strafeVec = awayDir:Cross(Vector(0, 0, 1)):GetNormalized() * (self._strafeDir or 1)
		local movePos = self:GetPos() + awayDir * 60 + strafeVec * 40
		local pathRes = self:FollowPath(movePos, 30)

		if pathRes == "unreachable" then
			self:Approach(movePos, 1)
		end

		return
	end

	if dist > COMBAT_STRAFE_MIN and dist < COMBAT_STRAFE_MAX then
		if CurTime() >= (self._nextStrafeTime or 0) then
			self._strafeDir = (self._strafeDir or 1) * -1
			self._nextStrafeTime = CurTime() + math.Rand(STRAFE_INTERVAL_MIN, STRAFE_INTERVAL_MAX)
		end

		local toEnemy = enemy:GetPos() - self:GetPos()
		toEnemy.z = 0

		if toEnemy:LengthSqr() < 0.01 then
			toEnemy = Vector(1, 0, 0)
		end

		toEnemy:Normalize()

		local strafeVec = toEnemy:Cross(Vector(0, 0, 1)):GetNormalized() * (self._strafeDir or 1)
		local movePos

		if dist > idealDist * 1.3 then
			movePos = enemy:GetPos() - toEnemy * idealDist + strafeVec * 120
		elseif dist < idealDist * 0.5 then
			movePos = self:GetPos() - toEnemy * 100 + strafeVec * 80
		else
			movePos = enemy:GetPos() - toEnemy * dist + strafeVec * 150
		end

		local pathRes = self:FollowPath(movePos, 40)

		if pathRes == "unreachable" then
			self:Approach(movePos, 1)
		end

		return
	end

	local pathRes = self:FollowPath(enemy:GetPos(), 80)

	if pathRes == "unreachable" then
		self:Approach(enemy:GetPos(), 1)
	end

	self.loco:SetDesiredSpeed(self.RunSpeed)
end
