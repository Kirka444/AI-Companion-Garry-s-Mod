-- Movement speed and ladder handling for the solo companion NPC.

ENT.Type = "nextbot"
ENT.Base = "drgbase_nextbot_human"

function ENT:IsCrouching()
	return self:GetNWBool("DrGBaseCrouching")
end

if SERVER then
	function ENT:SetCrouching(bool)
		self:SetNWBool("DrGBaseCrouching", bool)
	end

	function ENT:OnUpdateSpeed()
		if self:VehicleIsValid() then
			return 0
		end

		local targetSpeed = self.WalkSpeed

		if self:IsClimbing() then
			targetSpeed = self.ClimbSpeed
		elseif self:IsCrouching() then
			if self:IsRunning() then
				targetSpeed = self.WalkSpeed
			else
				targetSpeed = self.CrouchSpeed
			end
		elseif self:IsRunning() then
			targetSpeed = self.RunSpeed
		end

		local currentSpeed = self.loco:GetDesiredSpeed() or 0
		local dt = FrameTime()
		local accel = 400
		local decel = 600

		if targetSpeed > currentSpeed then
			currentSpeed = math.min(currentSpeed + accel * dt, targetSpeed)
		elseif targetSpeed < currentSpeed then
			currentSpeed = math.max(currentSpeed - decel * dt, targetSpeed)
		end

		if currentSpeed < 5 then
			currentSpeed = 0
		end

		self.loco:SetDesiredSpeed(currentSpeed)
		return currentSpeed
	end
	function ENT:OnClimbing(ladder, left, down)
		if IsValid(ladder) then
			self:EmitSlotSound("DrGBaseLadderClimbing", 0.3, "player/footsteps/ladder" .. math.random(4) .. ".wav")
		end

		return not down and left < 112.5
	end

	function ENT:OnStopClimbing(ladder, height, down)
		if down then
			return
		end

		local footstep = false

		self:PlayActivityAndMoveAbsolute(ACT_ZOMBIE_CLIMB_END, self.ClimbAnimRate, function(_, cycle)
			if cycle >= 0.875 and not footstep then
				footstep = true
				self:EmitFootstep()
			end

			if cycle > 0.5 or not IsValid(ladder) then
				return
			end

			self:EmitSlotSound("DrGBaseLadderClimbing", 0.3, "player/footsteps/ladder" .. math.random(4) .. ".wav")
		end)
	end
end
